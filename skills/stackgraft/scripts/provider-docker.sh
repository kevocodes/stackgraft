#!/bin/sh
# provider-docker.sh - copy a store's state, start an instance on the copy,
#                      say how to reach it, and remove both again.
#
# usage:  sh scripts/provider-docker.sh provision <hash8> <worktree> <store> \
#             <source-volume> <image> <base-instance> <label>...
#         sh scripts/provider-docker.sh address   <hash8> <worktree> <store> [base-instance]
#         sh scripts/provider-docker.sh destroy   <hash8> <worktree> <store>
#
# stdout: tab-separated records, one per line, the first field naming the kind:
#         volume     the copy this run made, by name
#         instance   the container running on that copy, by name
#         bytes      the copy's measured size, in bytes, measured on this run
#         seconds    how long the copy took, measured on this run
#         space      the free-space evidence - see the four shapes below
#         host       how a container-run overlay reaches the instance
#         port       how a host-run overlay reaches it, if a port is published
#         env        a value the caller could not derive from host and port
#         age        the COPY's age - see the four shapes below
#         copy       a copy that exists, with the exact command that removes it
#         refused    a store this run would not act on, and why
# exit:   0 ok
#         2 usage error
#         3 at least one object was refused. provision refuses before it creates
#           anything, or removes what it made first AND READS THE REMOVAL BACK,
#           so exit 3 there always means nothing survives - a copy that would not
#           remove leaves by the exit below rather than as a refusal, because a
#           refusal that reported a removal nobody verified is the leak with a
#           success message over it. destroy refuses PER OBJECT, reap.sh's rule: every
#           object that proved out is still removed and every one that did not is
#           reported by name, so exit 3 there means at least one was left alone
#         4 environment failure, including a copy the runtime would not remove
#
# THIS SCRIPT NAMES NO STORE ENGINE, and that is the requirement rather than a
# style note. Cloning state is the same operation whatever wrote the bytes, and
# it differs between runtimes - so a parameter, a return value or a branch naming
# one particular engine would be the finite per-engine table this change deletes,
# re-entered by another door. Every engine-specific fact this needs is read back
# from the RUNTIME - where the image mounts the state, the environment and
# command the base container runs under, the network it sits on - and a fact that
# cannot be read is a refusal, never a default.
#
# THE BASE INSTANCE IS AN ARGUMENT rather than something found here, and the
# reason is a rule this repository already enforces on itself: finding it would
# take a listing that carries no ownership filter, and no shipped script makes
# one. The caller already holds the value - the source volume, the image and the
# instance all come out of ONE inspection that discovery has already done - so
# taking it as a parameter asks for nothing the caller did not have. What is NOT
# asked for is where the engine keeps its data: that is read from the instance,
# because a caller supplying it would be the engine table under the caller's name.
#
# THE ACTUATOR RE-VERIFIES, THE CALLER ONLY NAMES. reap.sh's rule, adapted:
# destroy re-finds its target with a scoped label query and removes only an
# object whose stackgraft.worktree label EQUALS the worktree argument, normalised
# on both sides. "Destroy another worktree's copy" is unreachable without the
# caller naming that worktree. provision is held to the same rule from the other
# end: the label set the caller supplies is re-verified against the arguments
# before a byte is written, so a caller that names one worktree and labels
# another creates nothing.
#
# NOTHING IS REMOVED THAT DID NOT COME OUT OF A SCOPED QUERY. There is no bulk
# reclamation of any kind here, no way to bring the base stack down with its
# state, and no listing anywhere in this file that is not filtered to this
# repository's own label.
#
# The copy is taken by a SECOND container mounting the source :ro and the
# destination rw, from the store's own image. The base engine is never signalled,
# stopped, paused, or reconfigured - not disturbing the base stack is the property
# the whole tool exists for. The copy is therefore taken LIVE and is
# crash-consistent: a file-level copy of a running engine is what a power cut
# looks like. Engines are built to recover from that and an engine with an
# fsync-ordering dependency may not. That residual is stated rather than answered
# here; the caller's verification query is what catches it.
#
# Reads no stdin. WRITES NO HOST FILE, under any verb - no manifest, no sidecar,
# no cache entry. Parses no JSON: every value read from the runtime is asked for
# one at a time with --format, so there is nothing to parse.
#
# Needs POSIX sh, POSIX awk, git (for one hash) and a container runtime. Nothing
# else: no JSON processor, no scripting runtime, no separate hashing binary, no
# host locking helper, and no tool for bounding a wait.
#
# THE FLAGS PASSED TO A CONTAINER THIS SCRIPT STARTS ARE NOT HOST FLAGS. The
# host-portability rule governs what ships here and runs on the developer's own
# machine; the size and free-space measurements below run inside the store's own
# image. They are still not assumed: each is required to answer in the unit it
# declares, and an image whose tools answer otherwise is a refusal rather than a
# guess.
#
# Declared hazard, not worked around: an unresponsive container daemon can make a
# query or a copy hang. No portable way to bound it exists on every supported
# platform - the obvious helper is absent from one of them - so it is stated here
# rather than papered over.

set -u

me=${0##*/}
LABELS_VERSION=1
tab=$(printf '\t')

# The labels a copy must carry to be one. Four, not the overlay's five:
# stackgraft.service holds a MANIFEST SERVICE KEY and a copy belongs to a store,
# not to a service, so writing one there would make a volume claim to be a
# service that reap.sh then reads as a launched overlay. stackgraft.store is
# written from this script's own argument.
COPY_LABEL_KEYS='stackgraft.labels stackgraft.repo stackgraft.worktree stackgraft.store'

usage() {
    [ "$#" -eq 0 ] || printf '%s: %s\n' "$me" "$1" >&2
    printf 'usage: sh %s provision <hash8> <worktree> <store> <source-volume> <image> <base-instance> <label>...\n' "$0" >&2
    printf '       sh %s address   <hash8> <worktree> <store> [base-instance]\n' "$0" >&2
    printf '       sh %s destroy   <hash8> <worktree> <store>\n' "$0" >&2
    exit 2
}

emit() {
    _line=$1
    shift
    for _f in "$@"; do _line="$_line$tab$_f"; done
    printf '%s\n' "$_line"
}

# A refusal is a store this run would not act on. It never means "something went
# wrong halfway": every refusal path below runs before anything is created, or
# removes what it made first.
refuse() {
    emit refused "$store" "$1"
    exit 3
}

envfail() { printf '%s: %s\n' "$me" "$1" >&2; exit 4; }

# DS27's normalisation, byte-identical in intent to reap.sh's: the physical
# absolute path, with an unresolvable path resolving to nothing rather than to a
# guess. Both sides of every worktree comparison go through this, so a caller
# spelling its own worktree with a symlink or a trailing slash still matches the
# label it wrote, and a path that cannot be resolved matches NOTHING.
norm_path() { ( CDPATH= cd -- "$1" 2>/dev/null && pwd -P ); }

# A docker object name must start alphanumeric and hold only [A-Za-z0-9_.-].
# The store key is repository data, so it is validated rather than trusted, and
# the worktree path is hashed rather than embedded because a path holds
# characters a name may not.
#
# git is the hasher for the same reason it is everywhere else here: it is already
# a hard dependency, and the obvious standalone digest tool is absent from macOS.
copy_name() {
    _wt=$(printf '%s' "$1" | git hash-object --stdin 2>/dev/null | awk '{print substr($0, 1, 8)}')
    [ -n "$_wt" ] || return 1
    printf 'sg-%s-%s-%s\n' "$2" "$_wt" "$3"
}

# ---------------------------------------------------------------- arguments --
[ "$#" -ge 1 ] || usage "no verb"
verb=$1
shift

# THE VERB IS DECIDED BEFORE ANYTHING ELSE, and the dispatch at the bottom is
# what runs it rather than what validates it. Ordering it after the runtime check
# means a machine with no container runtime answers a TYPO with an environment
# failure - measured on a minimal image, where an unknown verb exited 4 and the
# caller was told the runtime was missing rather than that the verb was wrong. A
# usage error is a fact about the invocation and is knowable without a runtime.
case $verb in
    provision | address | destroy) ;;
    *) usage "unknown verb: '$verb' - expected provision, address or destroy" ;;
esac

[ "$#" -ge 3 ] || usage "$verb needs <hash8> <worktree> <store>"
hash8=$1
worktree_arg=$2
store=$3
shift 3

case $hash8 in
    '' | *[!0-9a-f]*) usage "hash8 is not lowercase hex: '$hash8'" ;;
esac
case $store in
    '' | -* | *[!A-Za-z0-9_.-]*) usage "store key is not a legal object-name component: '$store'" ;;
esac

worktree=$(norm_path "$worktree_arg")
[ -n "$worktree" ] || usage "worktree path is not a readable directory: '$worktree_arg'"

command -v docker >/dev/null 2>&1 || envfail "docker is not on PATH"
docker info >/dev/null 2>&1 || envfail "the container runtime is not answering"

name=$(copy_name "$worktree" "$hash8" "$store") || envfail "git could not hash the worktree path"

# Two scoped queries, and the scoping is IN THE QUERY rather than in a filter
# over its output, exactly as reap.sh keeps its. An unfiltered listing does not
# exist anywhere in this script, so one can never reach a removal.
# The repo filter sits on the SAME LINE as the command in both, so a reader - and
# the check that reads shipped scripts for exactly this - sees the scoping where
# the listing is rather than three lines below it.
#
# THE LABEL-SET VERSION IS NOT IN THE QUERY, and that is the difference between
# reporting an object and never seeing it. Filtering on it was the first shape and
# it made an object carrying a version this run does not recognise INVISIBLE:
# never found, so never reported, so a destroy over it exited 0 saying nothing at
# all. "Reported, never removed" needs the object found first. So the query scopes
# to this repository and this store, and the version is re-verified in the
# actuator like every other property of the target.
scoped_instances() {
    docker container ls --all --quiet --filter "label=stackgraft.repo=$hash8" \
        --filter "label=stackgraft.store=$store" 2>/dev/null
}
scoped_volumes() {
    docker volume ls --quiet --filter "label=stackgraft.repo=$hash8" \
        --filter "label=stackgraft.store=$store" 2>/dev/null
}
label_of()   { docker inspect --format "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null; }
vlabel_of()  { docker volume inspect --format "{{index .Labels \"$2\"}}" "$1" 2>/dev/null; }

# The whole of the worktree test, and it is EQUALITY after normalisation on both
# sides - never a prefix, never a substring. A recorded label that will not
# normalise resolves to nothing, and nothing equals nothing is refused by the
# emptiness test rather than accepted by it.
mine() {
    _recorded=$1
    [ -n "$_recorded" ] || return 1
    _recorded=$(norm_path "$_recorded")
    [ -n "$_recorded" ] || return 1
    [ "$_recorded" = "$worktree" ]
}

# ---------------------------------------------------------------- provision --

# EVERY PROVISION PATH THAT HAS MADE A COPY AND CANNOT KEEP IT REMOVES IT
# THROUGH HERE, and it is one function because "and the copy was removed" is a
# claim until the removal has been read back. Three call sites made that claim
# out of a removal whose error was discarded, and one of them was measured
# making it over a copy that survived: `volume is in use - [343e5542...]`,
# swallowed by the redirect, exit 3, and the copy still on the disk.
#
# INSTANCE FIRST, COPY SECOND - destroy's own rule, which the verb that creates
# both did not follow. A `docker run` that fails AFTER the container was created
# leaves it in `Created`, and a container in `Created` holds a volume exactly as
# a running one does, so the runtime will not remove the copy under it.
#
# THE CONTAINER IS REMOVED ONLY WHERE IT HOLDS THE COPY, and that is the
# ownership test rather than a caution. The copy did not exist when this verb
# started - a name already taken is refused far above, before a byte is written
# - so this run created it, and anything mounting it was created after it was.
# The container carrying that mount, under the name this script derived for this
# run, is therefore this run's own and removing it is removing what this run
# made. A container that merely carries the NAME and holds nothing is the orphan
# an earlier run left behind, and it is left exactly where it was found: that is
# what a provision failing on a name already taken must not disturb.
#
# `-v` is reap.sh's flag for reap.sh's reason: the anonymous volumes the image
# declared and this run therefore created go with the container, while every
# NAMED volume - the copy included - is left for the removal by name below.
#
# AND THE COPY IS READ BACK. Where it survives, something this run cannot remove
# is holding it, and the honest report is the leak NAMED rather than a success
# message over it - destroy's own unremovable-aside precedent, taken as an
# ENVIRONMENT FAILURE rather than a refusal, because exit 3 here means nothing
# survives and this is the case where something did.
#
# The reason is the caller's sentence and the ending is this function's, so no
# path here can spell a removal that did not happen.
refuse_removing_copy() {
    case $(docker container inspect --format \
        "{{range .Mounts}}{{if eq .Name \"$name\"}}holds{{end}}{{end}}" "$name" 2>/dev/null) in
        *holds*) docker rm -f -v "$name" >/dev/null 2>&1 ;;
    esac
    docker volume rm "$name" >/dev/null 2>&1
    if docker volume inspect "$name" >/dev/null 2>&1; then
        envfail "$1, and the copy '$name' is still here: the runtime would not remove it, so it is named rather than reported removed"
    fi
    refuse "$1, and the copy was removed"
}

provision() {
    [ "$#" -ge 4 ] || usage "provision needs <source-volume> <image> <base-instance> <label>..."
    src=$1
    image=$2
    base=$3
    shift 3

    # The label set is re-verified against the ARGUMENTS before anything is
    # created. A caller that names one worktree and labels another is the
    # mislabelled copy nothing can later find, and it is refused here rather
    # than discovered by a destroy that cannot see it.
    seen_labels=
    for l in "$@"; do
        case $l in
            stackgraft.labels=*)   [ "${l#*=}" = "$LABELS_VERSION" ] || refuse "the label set version is not $LABELS_VERSION: '$l'" ;;
            stackgraft.repo=*)     [ "${l#*=}" = "$hash8" ]          || refuse "stackgraft.repo does not equal the hash8 argument: '$l'" ;;
            stackgraft.worktree=*) mine "${l#*=}"                    || refuse "stackgraft.worktree does not equal the worktree argument: '$l'" ;;
            stackgraft.store=*)    [ "${l#*=}" = "$store" ]          || refuse "stackgraft.store does not equal the store argument: '$l'" ;;
            *=*) ;;
            *) refuse "a label is not KEY=VALUE: '$l'" ;;
        esac
        seen_labels="$seen_labels ${l%%=*}"
    done
    for k in $COPY_LABEL_KEYS; do
        [ "$k" = stackgraft.store ] && continue
        case " $seen_labels " in
            *" $k "*) ;;
            *) refuse "the label set is incomplete: no $k" ;;
        esac
    done

    # The labels become `--label L` pairs by rotating them through the positional
    # parameters, which is the only container sh has that survives a value with a
    # space in it - and a worktree path with a space is the ordinary case this
    # repository already tests for elsewhere. Both the volume and the instance are
    # built from this one list, so the two cannot drift into carrying different
    # sets and leaving half a copy unreachable.
    n=$#
    i=0
    while [ "$i" -lt "$n" ]; do
        l=$1
        shift
        set -- "$@" --label "$l"
        i=$((i + 1))
    done
    set -- "$@" --label "stackgraft.store=$store"

    docker volume inspect "$src" >/dev/null 2>&1 \
        || refuse "no local volume named '$src' on this runtime, so there is no local state to copy"

    # A destination that already exists is a copy from an earlier run, and this
    # verb does not decide what becomes of it. Writing into it would seed a
    # half-old volume; removing it would be a teardown nobody asked for. Refuse,
    # and let the caller destroy first - a refresh is destroy then provision, and
    # spelling it that way is what keeps a refresh explicit.
    docker volume inspect "$name" >/dev/null 2>&1 \
        && refuse "a copy named '$name' already exists; destroy it first if a refresh is what you want"

    # Where the image mounts that volume, and under what environment, read from
    # the base instance the caller named. Not guessed, not defaulted, not derived
    # from the engine's name. An instance that cannot be inspected, or that does
    # not mount the volume the caller also named, is a refusal: the two arguments
    # have to describe the same store or nothing below is about that store.
    docker inspect "$base" >/dev/null 2>&1 \
        || refuse "the base instance '$base' cannot be inspected on this runtime"
    mount=$(docker inspect --format \
        "{{range .Mounts}}{{if eq .Name \"$src\"}}{{.Destination}}{{end}}{{end}}" "$base" 2>/dev/null)
    [ -n "$mount" ] || refuse "the base instance '$base' does not mount '$src', so the two arguments do not describe one store"
    net=$(docker inspect --format \
        '{{range $k, $v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$base" 2>/dev/null \
        | awk 'NF { print; exit }')
    base_env=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$base" 2>/dev/null)
    # The command the base container actually runs, not the image's default. An
    # image started under a command the compose file supplied is not the same
    # instance when started without it, and "run the same image" taken literally
    # produces a container that exits immediately. Read back like every other
    # runtime fact here; asked for one element per line so there is no JSON to
    # parse and an argument holding a newline is unrepresentable rather than
    # silently split.
    base_cmd=$(docker inspect --format '{{range .Config.Cmd}}{{println .}}{{end}}' "$base" 2>/dev/null)
    # The entrypoint too, and only where the runtime's own CLI can express it.
    # --entrypoint takes ONE string, so a base container running a multi-element
    # entrypoint override is a shape this runtime cannot reproduce: that is a
    # refusal with the shape named, never a copy quietly started under a
    # different entrypoint from the one holding the base stack's data.
    base_ep=$(docker inspect --format '{{range .Config.Entrypoint}}{{println .}}{{end}}' "$base" 2>/dev/null)
    ep_n=$(printf '%s\n' "$base_ep" | awk 'NF { n++ } END { print n + 0 }')
    [ "$ep_n" -le 1 ] || refuse "the base container runs a $ep_n-element entrypoint override, which this runtime's CLI cannot reproduce in one argument"
    base_ep=$(printf '%s\n' "$base_ep" | awk 'NF { print; exit }')

    # --- the size, and the two filesystems ---------------------------------
    #
    # The runtime's own report is NOT read. Its disk-usage report gives a human
    # string with a unit - measured "7.34MB" on server 29.5.3 and again on 24.0.9
    # - and its volume-inspection usage field answers null on both. A shell that
    # had to parse the first would be parsing a value the runtime does not promise
    # to keep stable. Counting bytes inside a container answers 7344130 on both,
    # which needs no parsing at all.
    #
    # --entrypoint sh is not optional: an image that declares its own entrypoint
    # would otherwise be handed the measurement as ARGUMENTS to the engine, and
    # the run would fail for a reason that reads exactly like an unmeasurable
    # volume. Measured: alpine/git declares one, and without this the size row
    # refused every store.
    probe() { docker run --rm --entrypoint sh "$@" 2>/dev/null; }
    bytes=$(probe -v "$src":/sg-src:ro "$image" -c 'du -sb /sg-src' | awk 'NR == 1 { print $1 }')
    case ${bytes:-} in
        '' | *[!0-9]*) refuse "the source volume's size could not be measured in bytes inside its own image" ;;
    esac

    # The kilobyte flag is not decoration and the k is the whole safety of the
    # comparison. The POSIX portable-format flag reports 512-byte blocks on the
    # host here and 1024-byte ones inside a minimal image: measured on this host,
    # the bare form said 330306512 for the same filesystem the kilobyte form said
    # 165152016 for. Reading the two sides in their own units reports the host as
    # twice as free as it is, which is the permissive direction.
    avail_kib() { awk 'NR == 2 { print $4 }'; }
    rt_fs=$(probe "$image" -c 'df -Pk /' | awk 'NR == 2 { print $1 }')
    rt_kib=$(probe "$image" -c 'df -Pk /' | avail_kib)
    cache=${XDG_CACHE_HOME:-${HOME:-}/.cache}
    while [ -n "$cache" ] && [ "$cache" != / ] && [ ! -d "$cache" ]; do cache=${cache%/*}; done
    host_fs=$(df -Pk "${cache:-/}" 2>/dev/null | awk 'NR == 2 { print $1 }')
    host_kib=$(df -Pk "${cache:-/}" 2>/dev/null | avail_kib)
    case ${rt_kib:-}x${host_kib:-} in
        *[!0-9x]* | x* | *x) refuse "free space could not be established for the runtime's data root or for the host filesystem behind it" ;;
    esac

    # The binding filesystem is the smaller of the two, and it is NAMED. The
    # runtime's data disk is a sparse image that grows into the host, so the two
    # figures are not the same claim and the host's is usually the real one.
    bound=$(awk -v r="$rt_kib" -v h="$host_kib" -v rf="$rt_fs" -v hf="$host_fs" \
        'BEGIN { if (h + 0 <= r + 0) printf "%s\t%d\n", hf, h; else printf "%s\t%d\n", rf, r }')
    bound_fs=${bound%%"$tab"*}
    bound_kib=${bound#*"$tab"}
    emit space measured "$rt_fs" "$rt_kib"
    emit space measured "$host_fs" "$host_kib"
    emit space bound "$bound_fs" "$bound_kib"

    # This repository's copies already on it, from the scoped query the report
    # pass already makes. A runtime that will not answer reports unknown, never
    # zero: zero is a claim and an unanswered query is not one.
    if held=$(scoped_volumes); then
        emit space copies "$(printf '%s\n' "$held" | awk 'NF { n++ } END { print n + 0 }')"
    else
        emit space copies unknown
    fi
    emit space blindspot "another worktree's copy that does not exist yet, another repository's copies, and every other consumer of this disk are not counted and cannot be"
    emit space candidate "this is a candidate, not a guarantee: two runs that each pass this check can still collide, and no run holds a reservation"

    awk -v need="$bytes" -v have="$bound_kib" 'BEGIN { exit !(need / 1024 <= have) }' \
        || refuse "the copy needs $bytes bytes and $bound_fs has ${bound_kib}KiB, so it is refused before any bytes are written"

    # --- the copy ----------------------------------------------------------
    docker volume create "$@" "$name" >/dev/null 2>&1 \
        || refuse "the copy volume could not be created"

    started=$(date +%s)
    if ! docker run --rm -v "$src":/sg-src:ro -v "$name":/sg-dst --entrypoint sh "$image" \
            -c 'cd /sg-src && cp -a . /sg-dst/' >/dev/null 2>&1; then
        # A partial copy does not survive a failed provision any more than it
        # survives a refusal. The volume list is left exactly as it was found.
        refuse_removing_copy "the copy failed part-way"
    fi
    elapsed=$((  $(date +%s) - started ))

    copied=$(probe -v "$name":/sg-dst:ro "$image" -c 'du -sb /sg-dst' | awk 'NR == 1 { print $1 }')
    case ${copied:-0} in
        '' | 0 | *[!0-9]*)
            refuse_removing_copy "the copy measured no bytes, so it is not a copy"
            ;;
    esac

    # --- the instance ------------------------------------------------------
    # The same label list the volume was built from, prepended with the run's own
    # options. The environment is the BASE CONTAINER'S, read back rather than
    # invented: an engine that needs a variable to start needs the one it is
    # already running under, and defaulting one from a sibling is the invention
    # discovery.md forbids. PATH is dropped because it belongs to the image.
    set -- -d --name "$name" -v "$name":"$mount" -P "$@"
    [ -n "${net:-}" ] && set -- "$@" --network "$net"
    [ -n "${base_ep:-}" ] && set -- "$@" --entrypoint "$base_ep"
    while IFS= read -r e; do
        case $e in '' | PATH=*) continue ;; esac
        set -- "$@" -e "$e"
    done <<SG_ENV
$base_env
SG_ENV
    set -- "$@" "$image"
    while IFS= read -r c; do
        [ -n "$c" ] && set -- "$@" "$c"
    done <<SG_CMD
$base_cmd
SG_CMD

    if ! docker run "$@" >/dev/null 2>&1; then
        # The container this run just named is exactly what a start failure
        # leaves holding the copy, so it goes first and the copy goes after it.
        refuse_removing_copy "the instance would not start on the copy"
    fi

    emit volume "$name"
    emit instance "$name"
    emit bytes "$copied"
    emit seconds "$elapsed"
    emit copy "$name" "docker rm -f $name && docker volume rm $name"
}

# ---------------------------------------------------------------------- age --
# An ISO-8601 timestamp to epoch seconds, in POSIX awk, because the two obvious
# helpers are each absent from one supported platform: the flag that parses a
# date string is GNU-only and its BSD spelling takes a different one, and this
# repository ships nothing that is allowed to depend on either. The arithmetic is
# the ordinary civil-from-days one and it needs no table and no library.
#
# The offset is read rather than assumed. The runtime answers with its own
# offset for a volume and with Z for a container, and taking one for the other
# moves the age by hours - in whichever direction the reader is standing.
iso_epoch() {
    awk -v s="${1:-}" '
        function dfc(y, m, d,   era, yoe, doy, doe) {
            if (m <= 2) y = y - 1
            era = int((y >= 0 ? y : y - 399) / 400)
            yoe = y - era * 400
            doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
            doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
            return era * 146097 + doe - 719468
        }
        BEGIN {
            if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) exit
            e = dfc(substr(s, 1, 4) + 0, substr(s, 6, 2) + 0, substr(s, 9, 2) + 0) * 86400 \
                + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 + substr(s, 18, 2)
            tail = substr(s, 20)
            if (match(tail, /[+-][0-9][0-9]:?[0-9][0-9]$/)) {
                o = substr(tail, RSTART)
                e -= (substr(o, 1, 1) == "-" ? -1 : 1) \
                     * (substr(o, 2, 2) * 3600 + substr(o, length(o) - 1, 2) * 60)
            }
            print e
        }'
}

# THE AGE REPORTED IS THE COPY'S, AND THE DATA'S AGE IS STATED AS UNMEASURED
# rather than implied. The two clocks diverge the moment the base store is
# restored, reseeded, or migrated, and this run compares nothing: it knows when
# the copy was taken and it does not know what the base store has done since. So
# a phrase like "up to date as of" is never written here or anywhere else this
# skill ships, and neither is "stale", "fresh", or a data age of the form "the
# data is N old" - every one of them is a comparison nobody performed.
#
# One further fact is reported because it is OBSERVED rather than inferred: the
# base store's instance has or has not started since the copy was taken. Where
# the caller named no base instance, or it cannot be inspected, the answer is
# `unread` - the comparison was not made - never agreement by default.
report_age() {
    _created=$(docker volume inspect --format '{{.CreatedAt}}' "$name" 2>/dev/null)
    _taken=$(iso_epoch "$_created")
    _now=$(date +%s 2>/dev/null)
    case ${_taken:-}x${_now:-} in
        *[!0-9x]* | x* | *x)
            emit age taken unread
            emit age elapsed unread
            ;;
        *)
            emit age taken "$_created"
            emit age elapsed "$(( _now - _taken < 0 ? 0 : _now - _taken ))"
            ;;
    esac
    emit age subject "this is the age of the copy; what it holds is the base store's state as of that timestamp, and this run did not compare the two"

    _base=${1:-}
    if [ -z "$_base" ]; then
        emit age base unread
        return
    fi
    _started=$(iso_epoch "$(docker inspect --format '{{.State.StartedAt}}' "$_base" 2>/dev/null)")
    case ${_started:-}x${_taken:-} in
        *[!0-9x]* | x* | *x) emit age base unread ;;
        *) [ "$_started" -gt "$_taken" ] \
               && emit age base changed \
               || emit age base unchanged ;;
    esac
}

# ------------------------------------------------------------------ address --
address() {
    inst=$(scoped_instances | awk 'NR == 1 { print }')
    [ -n "$inst" ] || refuse "no instance of this repository's copy of '$store' exists for this worktree"
    mine "$(label_of "$inst" stackgraft.worktree)" \
        || refuse "the instance found carries another worktree's label"

    # host is the container NAME, not its hostname. On a user-defined network -
    # which is what a compose base stack runs on - the name is what the runtime's
    # DNS resolves for a container-run overlay; the hostname is the container id
    # and resolves for nobody.
    iname=$(docker inspect --format '{{.Name}}' "$inst" 2>/dev/null | awk '{ sub(/^\//, ""); print }')
    emit instance "$iname"
    emit host "$iname"

    # A value, never a delivery: the launch's existing channel carries it. What
    # is returned is what the runtime assigned - this script picks no port,
    # because pick-port.sh already picks ports and two allocators on one host is
    # the object this change deleted elsewhere.
    docker port "$inst" 2>/dev/null | awk -F: 'NF > 1 { print $NF }' | while IFS= read -r p; do
        [ -n "$p" ] && printf 'port\t%s\n' "$p"
    done

    # The age is emitted HERE and not from provision, because this is the verb a
    # run that provisions nothing, refreshes nothing and destroys nothing still
    # calls: the copy has to be addressed before the overlay can be wired to it.
    # Putting the age anywhere else would make it conditional on the run having
    # done something, which is exactly the run that most needs to be told how old
    # the state it is about to test against is.
    report_age "${1:-}"

    # Zero env records, and the reason is stated rather than left as an absence:
    # the names a service reads its address from are the manifest's, not this
    # script's, and inventing one would be the defaulted-from-a-sibling variable
    # discovery.md forbids. The record kind exists for a runtime that must carry
    # a value the caller cannot derive from host and port; Docker has none.
}

# ------------------------------------------------------------------ destroy --
destroy() {
    left=
    refused_any=0
    for inst in $(scoped_instances); do
        if ! mine "$(label_of "$inst" stackgraft.worktree)"; then
            emit refused "$store" "an instance labelled for another worktree was left alone"
            refused_any=1
            continue
        fi
        if [ "$(label_of "$inst" stackgraft.labels)" != "$LABELS_VERSION" ]; then
            emit refused "$store" "an instance carries an unrecognised stackgraft.labels value"
            refused_any=1
            continue
        fi
        # -v removes the ANONYMOUS volumes the image declared and this run
        # therefore created, and it leaves every named one alone - the copy
        # included, which is removed by name below after the instance is gone.
        # Without it a store image declaring a volume path this run does not
        # mount leaks one unnamed volume per provision, invisibly, for ever.
        # Measured on the fixture image, which declares one.
        docker rm -f -v "$inst" >/dev/null 2>&1 || left="$left $inst"
    done

    # Instance first, volume second. A volume still attached to a container is a
    # volume the runtime refuses to remove, and reporting that as success is the
    # half of the leak that matters.
    for vol in $(scoped_volumes); do
        if ! mine "$(vlabel_of "$vol" stackgraft.worktree)"; then
            emit refused "$store" "a volume labelled for another worktree was left alone"
            refused_any=1
            continue
        fi
        if [ "$(vlabel_of "$vol" stackgraft.labels)" != "$LABELS_VERSION" ]; then
            emit refused "$store" "a volume carries an unrecognised stackgraft.labels value"
            refused_any=1
            continue
        fi
        docker volume rm "$vol" >/dev/null 2>&1 || left="$left $vol"
    done

    # A volume the runtime would not remove is an exit 4 that NAMES it, the
    # with-lock.sh unremovable-aside precedent: reporting success over a
    # surviving copy is the half of the leak that matters.
    [ -z "$left" ] || envfail "these objects would not remove and are still here:$left"
    [ "$refused_any" -eq 0 ] || exit 3
}

# The verb was validated at the top, so this dispatch has no unknown branch: two
# places deciding one thing is how they come to decide it differently.
case $verb in
    provision) provision "$@" ;;
    address)   [ "$#" -le 1 ] || usage "address takes at most one further argument, the base instance to compare the copy's age against"; address "$@" ;;
    destroy)   [ "$#" -eq 0 ] || usage "destroy takes no further arguments"; destroy ;;
esac
