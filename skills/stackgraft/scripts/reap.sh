#!/bin/sh
# reap.sh - report this repository's overlays, and act on one only after
#           re-proving inside this script that it is this repository's.
#
# usage:  sh scripts/reap.sh [-C <repoRoot>] [-b <basePort>]... report <hash8>
#         sh scripts/reap.sh [-C <repoRoot>] -b <basePort>... -m stop   <hash8> <target>...
#         sh scripts/reap.sh [-C <repoRoot>] -b <basePort>... -m remove <hash8> <target>...
#
#         -C  the repository root - the MAIN worktree, as fingerprint.sh takes
#             it. Defaults to the working directory.
#         -m  the mutation flag. stop and remove each require it, and remove
#             requires it IN ADDITION to being the removal verb: the removal
#             flag on its own mutates nothing and says which flag is missing.
#             Spelling mutation as its own token is the point rather than a
#             redundancy. An agent that never received the user's mutation
#             flag cannot produce this argument, and editors that pre-fill a
#             permission bypass are why the confirmation cannot live in a
#             prompt.
#         -b  one host port the manifest records as a baseStack port, repeated
#             once per port. This script parses no JSON, so the caller reads
#             them out of the manifest; the decision they drive stays here.
#             At least one is MANDATORY for a container mutation. Each value is
#             a decimal port in 1-65535 with leading zeros stripped, exactly as
#             pick-port.sh validates its own port arguments - so 018103 means
#             18103 rather than a string that matches no published port. That
#             rejects typos and nothing more; see the declared limit below.
#
# A container mutation needs at least one real base port, and its absence is
# unknown rather than none. A caller that passes no -b has told this script
# nothing about which ports belong to the base stack, and deciding a stop
# against a port set that was never supplied is deciding blind - which is how a
# hand-labelled base-stack container gets stopped by omitting a flag. So every
# c: target under a mutation verb is refused until a port is supplied, and that
# refusal has NO override. A flag asserting that the manifest records none was
# tried and removed: nothing here can check such a claim, so an unverifiable
# assertion that switches the exclusion off is the same gate keyed on an
# optional input under another name - and it is a claim about the MANIFEST
# while the decision is about the base stack's real ports, which diverge in the
# manifest-less mode the skill supports. The report path is unaffected: it
# takes no decision, and it is what every invocation runs.
#
# The cost is real and is accepted rather than worked around: a repository
# whose manifest records no baseStack port cannot mutate a container target
# until one is supplied. That repository is degenerate for this skill, which
# exists to overlay onto a running base stack whose ports the overlay must
# avoid - pick-port.sh already needs those same ports.
#
# Declared limit, and it is the whole of the port test rather than an edge of
# it: THE PORT EXCLUSION IS CALLER-SUPPLIED AND CALLER-DEFEATABLE. This script
# parses no JSON, so it never sees the manifest the values came from and cannot
# tell a wrong port from a right one. A caller that passes the wrong value - by
# typo, by a stale manifest, or on purpose - reaches the container the right
# value would have excluded. Validating the range removes typos and closes
# nothing: 1 is a valid port. Refusing on the service NAME is not available
# either, because stackgraft.service holds a manifest service key and the base
# stack runs those same services, so a name test would refuse every overlay
# this script exists to reclaim.
#
# What DOES hold structurally is the allowlist above: only an overlay launch
# writes stackgraft.repo, so a base-stack container is outside the candidate
# set under every flag unless a human hand-labelled it with this repository's
# complete label set. Exactly one shape is left over, and it is accepted rather
# than guarded - a container hand-labelled that way, whose worktree is
# unlisted, and whose published port is not among the values passed.
#
# target: c:<container-id>            one argument
#         p:<pid> <recorded-lstart>   TWO arguments, the second verbatim as it
#                                     was recorded. remove has no meaning for a
#                                     process, so a p: target under remove is
#                                     refused by name as malformed-target at
#                                     exit 3 like any other target that will
#                                     not parse - not a usage error, which
#                                     would end the whole invocation and take
#                                     the proven targets beside it down too.
#
# stdout: tab-separated records, one per line, the first field naming the kind:
#         worktree   a worktree entry and whether it is live
#         container  an overlay of this repository, its verdict, or its outcome
#         process    a host-kind overlay this run signalled
#         host       the host-overlay registry: checked, or unknown and why
#         held       one port a live overlay of this repository holds
#         legacy     a category this report structurally cannot enumerate
#         degraded   something could not be read - which is UNKNOWN, never zero
#         refused    a target that failed its proof or would not parse, and why
#         acted      how many targets were acted on. A skipped no-op is not one.
# exit:   0 ok
#         2 usage error
#         3 at least one target was refused - it failed its proof, or it would
#           not parse; every target that DID prove out was still acted on, and
#           acted says how many
#         4 environment failure, including a proven target the runtime would
#           not act on. The remaining targets are still acted on and acted is
#           still reported.
#
# Every target is re-proved HERE, immediately before acting, and not by the
# caller. An agent that never opened references/reaping.md must still be unable
# to stop something unproven, so the proof lives in the actuator.
#
# A refusal refuses ITS OWN TARGET and nothing else. Every target is proven,
# every proven one is acted on, every unproven one is refused by name, and both
# sets are reported - then exit 3 says at least one was refused. Refusing the
# whole invocation was the earlier shape and it does not survive contact with
# what is actually here: each stop is independent, no state spans two targets,
# and there is no transaction for a partial run to violate. What it did cost
# was real - one unprovable target withheld the reap from every orphan named
# beside it, which is the work the caller asked for and proved out.
#
# That holds at the PARSING layer too, and it did not used to. A target that
# will not parse - a p: with a non-decimal pid, an empty c: id, a shape that is
# neither - is one malformed target, so it is refused by name like any other
# unprovable one while the targets that did prove out are still acted on. Only
# the things that are not a target at all remain usage errors: the verb, the
# hash8, and the options, none of which belong to one target and any of which
# leaves the run with no idea what it was asked to do.
#
# Reads no stdin and WRITES NO FILE, under any verb. The report path in
# particular takes no lock, creates none, and must complete while another
# process holds one.
#
# Parses no JSON: the agent owns the registry's contents. What this script
# reports about the registry is whether it could be READ, which is the claim
# the report actually has to make - an empty list is checked-and-none, and a
# missing or damaged file is unknown, and only the first may render as a zero.
#
# Needs POSIX sh, POSIX awk, git, ps, and - for container kinds only - docker,
# consistent with the skill's existing conditional dependency. No flock, no
# stat, no separate hashing binary.
#
# Declared hazard, not worked around: an unresponsive container daemon can make
# a listing hang. No portable bound exists for it on every supported platform,
# so it is stated here rather than papered over with something that is absent
# from one of them.

set -u

me=${0##*/}
LABELS_VERSION=1
lstart_supported=0
tab=$(printf '\t')
nl='
'

usage() {
    [ "$#" -eq 0 ] || printf '%s: %s\n' "$me" "$1" >&2
    printf 'usage: sh %s [-C <repoRoot>] [-b <basePort>]... report <hash8>\n' "$0" >&2
    printf '       sh %s [-C <repoRoot>] -b <basePort>... -m stop|remove <hash8> <target>...\n' "$0" >&2
    printf '       -b one baseStack port, repeated once per port; a container mutation needs at least one\n' >&2
    printf '       target: c:<container-id>  or  p:<pid> <recorded-lstart>\n' >&2
    exit 2
}

# Validates one port argument into port_val: decimal, 1-65535, leading zeros
# stripped. Same shape as pick-port.sh's port_arg, deliberately - two spellings
# of one rule drift, and this one is about the same manifest values. Sets a
# global instead of printing, because usage() ends the script and an exit
# inside a command substitution would only leave the subshell. $2 is the label
# the argument is reported under when it is rejected.
#
# The strip is the half that matters in practice: 018103 read as a string
# matches no stackgraft.port label, so a manifest value typed with a leading
# zero would silently protect nothing. This rejects what cannot be a port. It
# does NOT make the exclusion sound - see the declared limit in the header.
port_arg() {
    case ${1:-} in
        '') usage "missing ${2:-port argument}" ;;
        *[!0-9]*) usage "${2:-port argument} is not a decimal port: '$1'" ;;
    esac
    port_val=$1
    while [ "${port_val#0}" != "$port_val" ]; do port_val=${port_val#0}; done
    [ -n "$port_val" ] && [ "${#port_val}" -le 5 ] && [ "$port_val" -le 65535 ] \
        || usage "${2:-port argument} is outside 1-65535: '$1'"
}

# Builds one tab-separated record. Values reaching here never contain a tab: a
# path that does would arrive C-quoted from git and is rejected as unresolvable
# before it gets this far.
emit() {
    _line=$1
    shift
    for _f in "$@"; do _line="$_line$tab$_f"; done
    printf '%s\n' "$_line"
}

# --- BEGIN lstart probe -----------------------------------------------------
# Kept byte-identical in every script that needs process identity, so a copy
# that drifted shows up as a difference rather than as a subtly weaker proof.
#
# Two conditions, and the second is what makes the first a check: a ps that
# ignores -p answers the first call plausibly and the second with the whole
# table, which on any host running this probe holds more than one process.
# Asking for pid 1 as well is what catches it.
#
# The batched form for several pids at once is one process too:
# ps -o pid=,lstart= -p <comma-separated list>.
lstart_lines() { ps -o lstart= -p "$1" 2>/dev/null | awk 'NF { n++ } END { print n + 0 }'; }
lstart_of()    { ps -o lstart= -p "$1" 2>/dev/null | awk 'NF { print; exit }'; }
lstart_probe() {
    if [ "$(lstart_lines "$$")" = 1 ] && [ "$(lstart_lines 1)" = 1 ]; then
        lstart_supported=1
    else
        lstart_supported=0
    fi
}
# --- END lstart probe -------------------------------------------------------

# --- BEGIN worktree liveness ------------------------------------------------
# Kept together and delimited so the liveness rule can be exercised on its own,
# without a container runtime: it is the rule that decides kill or not.
WT_NL='
'
WT_TAB=$(printf '\t')

# Resolves one path to its absolute physical spelling, or to nothing when it
# will not resolve. /tmp and /private/tmp are one directory and two strings,
# and a raw comparison between them reads as "the worktree is gone" - which is
# a stop, on live work. A path git still C-quotes (control characters, an
# embedded quote) is unresolvable by construction and is never guessed at.
norm_path() {
    case $1 in '"'*) return 0 ;; esac
    ( CDPATH= cd -- "$1" 2>/dev/null && pwd -P ) || return 0
}

# Turns `git worktree list --porcelain` on stdin into one record per worktree:
#   live<TAB><physical path> · prunable<TAB><path> · unresolvable<TAB><path>
# -z is not used: it postdates the declared git 2.5+ floor.
# prunable is proof of neither liveness nor absence, so it classifies unknown
# rather than resolving to the permissive side.
wt_scan() {
    awk '
        /^worktree / { if (p != "") print s "\t" p; p = substr($0, 10); s = "live"; next }
        /^prunable/  { if (p != "") s = "prunable" }
        END          { if (p != "") print s "\t" p }
    ' | while IFS="$WT_TAB" read -r _s _p; do
        if [ "$_s" = prunable ]; then
            printf 'prunable%s%s\n' "$WT_TAB" "$_p"
        else
            _n=$(norm_path "$_p")
            if [ -n "$_n" ]; then
                printf 'live%s%s\n' "$WT_TAB" "$_n"
            else
                printf 'unresolvable%s%s\n' "$WT_TAB" "$_p"
            fi
        fi
    done
}

# Answers live | prunable | unresolvable | absent for ONE recorded worktree
# value against an index wt_scan produced.
#
# The recorded value is already physical - the launch wrote it through the same
# normalisation - so it is compared WHOLE, never word-split, and never
# re-resolved: an orphan's directory is gone by definition, and re-resolving it
# would turn the one case this exists for into "unproven".
#
# One entry that would not resolve makes every "absent" answer unproven
# instead, because a path nobody can spell might be the very one being looked
# for. Unknown is never orphaned.
wt_state() {
    _want=$1
    _rest=$2
    _blind=0
    while [ -n "$_rest" ]; do
        case $_rest in
            *"$WT_NL"*) _line=${_rest%%"$WT_NL"*}; _rest=${_rest#*"$WT_NL"} ;;
            *)          _line=$_rest; _rest= ;;
        esac
        [ -n "$_line" ] || continue
        _s=${_line%%"$WT_TAB"*}
        _p=${_line#*"$WT_TAB"}
        if [ "$_s" = unresolvable ]; then
            _blind=1
            continue
        fi
        if [ "$_p" = "$_want" ]; then
            printf '%s\n' "$_s"
            return 0
        fi
    done
    if [ "$_blind" -eq 1 ]; then printf 'unresolvable\n'; else printf 'absent\n'; fi
}
# --- END worktree liveness --------------------------------------------------

repo_root=.
base_ports=' '
base_given=0
mutate=0

while [ "$#" -gt 0 ]; do
    case $1 in
        -C) [ "$#" -ge 2 ] || usage 'missing repository root after -C'
            repo_root=$2
            shift 2 ;;
        -b) [ "$#" -ge 2 ] || usage 'missing port after -b'
            port_arg "$2" 'base port'
            base_ports="$base_ports$port_val "
            base_given=1
            shift 2 ;;
        -m) mutate=1
            shift ;;
        --) shift
            break ;;
        -*) usage "unknown option: '$1'" ;;
        *)  break ;;
    esac
done

[ "$#" -ge 1 ] || usage 'missing verb: report, stop or remove'
verb=$1
shift
[ "$#" -ge 1 ] || usage 'missing hash8'
hash8=$1
shift
case $hash8 in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) usage "hash8 is not eight lowercase hex digits: '$hash8'" ;;
esac

case $verb in
    report)
        [ "$#" -eq 0 ] || usage 'report takes no target - it never mutates'
        [ "$mutate" -eq 0 ] || usage 'report never mutates, so -m has no meaning with it'
        ;;
    stop | remove)
        [ "$#" -ge 1 ] || usage "$verb needs at least one target"
        if [ "$mutate" -eq 0 ]; then
            emit refused "$verb" mutation-flag-required \
                'mutation was not requested: pass -m, the mutation flag, in addition to the verb'
            printf '%s: %s needs the mutation flag -m; nothing was stopped or removed\n' "$me" "$verb" >&2
            exit 2
        fi
        ;;
    *) usage "unknown verb: '$verb' - expected report, stop or remove" ;;
esac

root=$(CDPATH= cd -- "$repo_root" 2>/dev/null && pwd -P)
if [ -z "$root" ]; then
    printf '%s: not a readable directory: %s\n' "$me" "$repo_root" >&2
    exit 4
fi

if wt_raw=$(git -C "$root" -c core.quotePath=false worktree list --porcelain 2>/dev/null); then
    wt_ok=1
    wt_index=$(printf '%s\n' "$wt_raw" | wt_scan)
else
    wt_ok=0
    wt_index=
fi

# One command -v, one argument: busybox reports only its first.
docker_ok=0
if command -v docker >/dev/null 2>&1; then
    docker_ok=1
fi

# The tab is a literal, taken from printf rather than from the CLI's own \t
# expansion, which is not the same thing on every version of it.
ps_fmt="{{.ID}}$tab{{.State}}$tab{{.Label \"stackgraft.labels\"}}$tab{{.Label \"stackgraft.worktree\"}}$tab{{.Label \"stackgraft.service\"}}$tab{{.Label \"stackgraft.port\"}}"

# EVERY container listing goes through one of these two, and the hash8 filter
# is part of the query rather than something applied to its output. An
# unscoped listing reaches a sibling repository's containers one directory
# away, which are not ours to enumerate and not ours to kill.
scoped_rows() { docker ps --all --filter "label=stackgraft.repo=$hash8" "$@" --format "$ps_fmt" 2>/dev/null; }
scoped_ids()  { docker ps --all --filter "label=stackgraft.repo=$hash8" "$@" --quiet 2>/dev/null; }

# Splits one row into the six globals the classifier reads. Parameter
# expansion rather than read, because a service name or a path containing a
# space has to survive whole.
split_row() {
    _r=$1
    r_id=${_r%%"$tab"*};    _r=${_r#*"$tab"}
    r_state=${_r%%"$tab"*}; _r=${_r#*"$tab"}
    r_ver=${_r%%"$tab"*};   _r=${_r#*"$tab"}
    r_wt=${_r%%"$tab"*};    _r=${_r#*"$tab"}
    r_svc=${_r%%"$tab"*}
    r_port=${_r#*"$tab"}
}

# Candidacy is a POSITIVE, CLOSED allowlist. Only an overlay launch ever writes
# stackgraft.repo, so a base-stack container is not excluded from the candidate
# set - it was never in it, and the scoped query above is the only way anything
# enters. This function can then only narrow: every branch but `orphan` is a
# refusal reason or a report line, and `orphan` is the sole actionable answer.
#
# The base-port branch is the second, independent condition, for a repository
# that writes the label itself: a container publishing a port THE RUN PASSED as
# a base-stack port is never a target, however it is labelled, and the anomaly
# is reported. It compares against the supplied values and nothing else - the
# manifest is never read here - so it excludes exactly what the caller named.
classify() {
    if [ "$r_ver" != "$LABELS_VERSION" ]; then
        printf 'unrecognised-label-version\n'
        return 0
    fi
    if [ -z "$r_wt" ] || [ -z "$r_svc" ] || [ -z "$r_port" ]; then
        printf 'incomplete-label-set\n'
        return 0
    fi
    case $base_ports in
        *" $r_port "*) printf 'base-stack-port\n'; return 0 ;;
    esac
    if [ "$wt_ok" -eq 0 ]; then
        printf 'worktree-list-unavailable\n'
        return 0
    fi
    case $(wt_state "$r_wt" "$wt_index") in
        live)         printf 'worktree-still-listed\n' ;;
        prunable)     printf 'worktree-prunable\n' ;;
        unresolvable) printf 'worktree-unresolvable\n' ;;
        *)            printf 'orphan\n' ;;
    esac
}

# ------------------------------------------------------------- the report ---

sidecar_path() {
    _common=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null) || return 1
    [ -n "$_common" ] || return 1
    case $_common in /*) ;; *) _common="$root/$_common" ;; esac
    _main=$(CDPATH= cd -- "$_common/.." 2>/dev/null && pwd -P)
    [ -n "$_main" ] || return 1
    printf '%s/stackgraft/%s-%s.processes.json\n' \
        "${XDG_CACHE_HOME:-${HOME:-}/.cache}" "${_main##*/}" "$hash8"
}

# A presence test, never a parse. An empty list is checked-and-none; a file
# with no list in it at all is damaged, which is unknown. Only the first of
# those may ever be rendered as a zero.
registry_shape() {
    awk '{ gsub(/[ \t\r]/, ""); s = s $0 }
         END { if (s !~ /"overlays":/)        print "damaged"
               else if (s ~ /"overlays":\[\]/) print "none"
               else                            print "records" }' "$1" 2>/dev/null
}

report_worktrees() {
    if [ "$wt_ok" -eq 0 ]; then
        emit degraded worktree-list-unavailable \
            'liveness could not be established, so no overlay is classified as an orphan'
        return 0
    fi
    printf '%s\n' "$wt_index" | while IFS="$tab" read -r _s _p; do
        [ -n "$_s" ] || continue
        emit worktree "$_s" "$_p"
    done
}

report_containers() {
    if [ "$docker_ok" -eq 0 ]; then
        emit degraded docker-unavailable \
            'the container runtime is absent, so container overlays are unknown - never zero'
        store_incomplete=1
        return 0
    fi
    if ! _rows=$(scoped_rows); then
        emit degraded docker-unavailable \
            'the container runtime did not answer, so container overlays are unknown - never zero'
        store_incomplete=1
        return 0
    fi
    if [ -z "$_rows" ]; then
        # Checked, and none. Said out loud, because an omitted line and a
        # verified zero are different claims and only one of them is evidence.
        emit container checked none
        return 0
    fi
    printf '%s\n' "$_rows" | while IFS= read -r _row; do
        [ -n "$_row" ] || continue
        split_row "$_row"
        _v=$(classify)
        case $_v in
            unrecognised-label-version | incomplete-label-set)
                emit refused "c:$r_id" "$_v" \
                    'reported, never acted on: this is not a record this run can read as ownership'
                ;;
            base-stack-port)
                emit refused "c:$r_id" base-stack-port \
                    "publishes $r_port, which this run supplied as a base-stack port - an anomaly, and never a target"
                ;;
            worktree-still-listed)
                emit container "$r_id" "$r_state" "$r_svc" "$r_port" "$r_wt" live
                ;;
            orphan)
                emit container "$r_id" "$r_state" "$r_svc" "$r_port" "$r_wt" orphan
                ;;
            *)
                emit container "$r_id" "$r_state" "$r_svc" "$r_port" "$r_wt" "unknown:$_v"
                ;;
        esac
        # Occupancy, not liveness: a running orphan holds its port exactly as
        # firmly as a live overlay does, and port selection cares about which
        # ports are taken rather than about which of them ought to be.
        case $_v in
            unrecognised-label-version | incomplete-label-set | base-stack-port) ;;
            *) if [ "$r_state" = running ]; then emit held "$r_port"; fi ;;
        esac
    done
}

report_registry() {
    _sc=$(sidecar_path) || _sc=
    if [ -z "$_sc" ]; then
        emit host unknown registry-path-unresolved \
            'the repository root would not resolve, so the host-overlay registry could not be located'
        store_incomplete=1
    elif [ ! -e "$_sc" ]; then
        emit host unknown registry-missing "$_sc"
        store_incomplete=1
    elif [ ! -r "$_sc" ]; then
        emit host unknown registry-unreadable "$_sc"
        store_incomplete=1
    else
        case $(registry_shape "$_sc") in
            damaged) emit host unknown registry-damaged "$_sc"; store_incomplete=1 ;;
            none)    emit host checked none "$_sc" ;;
            *)       emit host checked records "$_sc" ;;
        esac
    fi
}

# Printed on every report, whether or not anything was found, because there is
# nothing to find it with. The category is named, its invisibility is stated as
# structural, and the command the user runs themselves is given - but no count
# is ever claimed for it, zero included, since no query can produce one.
report_legacy() {
    emit legacy undetectable \
        'overlays launched before the stackgraft.labels contract existed carry no label and are invisible by construction: nothing distinguishes one from any other container on this host, so no query can enumerate them and no number is claimed here. Inspect them yourself with: docker ps --all'
    emit legacy remote \
        'an overlay whose worktree lives on another host is outside local scope by construction: it is never classified as an orphan and is never acted on from here'
}

if [ "$verb" = report ]; then
    store_incomplete=0
    report_worktrees
    report_containers
    report_registry
    report_legacy
    if [ "$store_incomplete" -ne 0 ]; then
        emit held incomplete \
            'an ownership store could not be read, so the held-port set is short of what is really held'
    fi
    exit 0
fi

# ----------------------------------------------------------- the actuator ---

plan=
refusals=0

refuse() {
    emit refused "$1" "$2" "$3"
    refusals=$((refusals + 1))
}

prove_container() {
    _id=$1
    # Fail closed on the base stack BEFORE anything else is asked about this
    # container. A port set the caller never supplied is not an empty one, and
    # comparing against it would answer "no base port matches" for every
    # container on the host - which is a gate keyed on an optional input, and
    # so no gate at all.
    #
    # The message names what is missing and nothing else. It used to offer the
    # flag that switched the whole rule off, which is a refusal advertising its
    # own bypass; there is no bypass now, so there is none to name.
    if [ "$base_given" -eq 0 ]; then
        refuse "c:$_id" base-stack-ports-unknown \
            'no base-stack port was given: pass -b <port> once per port the manifest records as a baseStack port. Absent information is unknown, and unknown refuses'
        return 0
    fi
    if [ "$docker_ok" -eq 0 ]; then
        refuse "c:$_id" docker-unavailable 'the container runtime is absent or did not answer'
        return 0
    fi
    if [ -z "$(scoped_ids --filter "id=$_id")" ]; then
        refuse "c:$_id" not-a-labelled-overlay-of-this-repository \
            "no container with that id carries stackgraft.repo=$hash8"
        return 0
    fi
    _row=$(scoped_rows --filter "id=$_id" | awk 'NR == 1')
    if [ -z "$_row" ]; then
        refuse "c:$_id" not-a-labelled-overlay-of-this-repository \
            'the scoped query returned no record for that id'
        return 0
    fi
    split_row "$_row"
    _v=$(classify)
    case $_v in
        orphan) ;;
        base-stack-port)
            refuse "c:$_id" base-stack-port \
                "publishes $r_port, which this run supplied as a base-stack port"
            return 0 ;;
        worktree-still-listed)
            refuse "c:$_id" worktree-still-listed \
                "its worktree $r_wt is still listed, so the overlay is live and is not a target under any flag"
            return 0 ;;
        *)
            refuse "c:$_id" "$_v" 'the proof this target needs did not hold'
            return 0 ;;
    esac
    if [ -z "$r_state" ]; then
        refuse "c:$_id" container-state-unknown \
            'the runtime reported no state, and a mutation decision is never taken on a missing field'
        return 0
    fi
    plan="${plan}c$tab$r_id$tab$r_state$tab$r_svc$tab$r_port$nl"
}

prove_process() {
    _pid=$1
    _rec=$2
    case $_pid in
        '' | *[!0-9]*)
            refuse "p:$_pid" malformed-target \
                "a p: target needs a decimal pid: '$_pid'"
            return 0 ;;
    esac
    case $_rec in
        '' | '-' | null)
            refuse "p:$_pid" lstart-unproven \
                'the record carries no start time, so this overlay is report-only for good'
            return 0 ;;
    esac
    lstart_probe
    if [ "$lstart_supported" -eq 0 ]; then
        refuse "p:$_pid" lstart-unsupported \
            'ps on this host reports no process start time, so ownership cannot be proven here'
        return 0
    fi
    _now=$(lstart_of "$_pid")
    if [ -z "$_now" ]; then
        refuse "p:$_pid" identity-mismatch \
            "pid $_pid is not running, so the recorded start time cannot be re-read"
        return 0
    fi
    if [ "$_now" != "$_rec" ]; then
        refuse "p:$_pid" identity-mismatch \
            "pid $_pid reports start time '$_now' but '$_rec' was recorded: the pid was recycled and this process is not ours"
        return 0
    fi
    plan="${plan}p$tab$_pid$nl"
}

# A target that will not parse is refused like any other unprovable target: by
# name, with its reason, while the rest of the list is still proven and acted
# on. Ending the whole invocation here is the shape that was already corrected
# one layer down, and it costs the same thing - the reap the caller asked for
# on the orphans that were named correctly beside the typo.
#
# The p: branch consumes its second argument BEFORE deciding anything, so a
# refused p: target does not leave its recorded lstart to be read as the next
# target. When there is no second argument there is no next target either, and
# the loop ends after the refusal.
while [ "$#" -gt 0 ]; do
    target=$1
    shift
    case $target in
        c:*)
            if [ -z "${target#c:}" ]; then
                refuse "$target" malformed-target 'empty container id in a c: target'
            else
                prove_container "${target#c:}"
            fi
            ;;
        p:*)
            if [ "$#" -eq 0 ]; then
                refuse "$target" malformed-target \
                    'a p: target takes two arguments: p:<pid> <recorded-lstart>'
            else
                recorded=$1
                shift
                if [ "$verb" = remove ]; then
                    refuse "$target" malformed-target \
                        'remove has no meaning for a process; stop signals it'
                else
                    prove_process "${target#p:}" "$recorded"
                fi
            fi
            ;;
        *)  refuse "$target" malformed-target \
                'a target is c:<container-id> or p:<pid> <recorded-lstart>' ;;
    esac
done

# Refusals are already reported, one record each, naming their own target. They
# do not stop what follows: every target that proved out is acted on here, and
# the exit code at the end says that some target did not.
acted=0
unactionable=0
rest=$plan
while [ -n "$rest" ]; do
    case $rest in
        *"$nl"*) line=${rest%%"$nl"*}; rest=${rest#*"$nl"} ;;
        *)       line=$rest; rest= ;;
    esac
    [ -n "$line" ] || continue
    kind=${line%%"$tab"*}
    fields=${line#*"$tab"}
    if [ "$kind" = c ]; then
        a_id=${fields%%"$tab"*};    fields=${fields#*"$tab"}
        a_state=${fields%%"$tab"*}; fields=${fields#*"$tab"}
        a_svc=${fields%%"$tab"*}
        a_port=${fields#*"$tab"}
        if [ "$verb" = stop ]; then
            # D8's corollary is a filter on the state, not a comment about it:
            # stopping something already stopped is a no-op that would report
            # as work done. Reported, skipped, and not counted.
            if [ "$a_state" != running ]; then
                emit container "$a_id" "$a_state" "$a_svc" "$a_port" skipped-not-running
                continue
            fi
            if docker stop "$a_id" >/dev/null 2>&1; then
                emit container "$a_id" "$a_state" "$a_svc" "$a_port" stopped
                acted=$((acted + 1))
            else
                emit refused "c:$a_id" stop-failed 'the runtime would not stop it'
                printf '%s: docker stop failed for %s; the other targets are unaffected\n' "$me" "$a_id" >&2
                unactionable=$((unactionable + 1))
            fi
        else
            if docker rm -f "$a_id" >/dev/null 2>&1; then
                emit container "$a_id" "$a_state" "$a_svc" "$a_port" removed
                acted=$((acted + 1))
            else
                emit refused "c:$a_id" remove-failed 'the runtime would not remove it'
                printf '%s: docker rm failed for %s; the other targets are unaffected\n' "$me" "$a_id" >&2
                unactionable=$((unactionable + 1))
            fi
        fi
    else
        if kill "$fields" 2>/dev/null; then
            emit process "$fields" signalled
            acted=$((acted + 1))
        else
            emit refused "p:$fields" signal-failed 'the signal could not be delivered'
            printf '%s: could not signal pid %s; the other targets are unaffected\n' "$me" "$fields" >&2
            unactionable=$((unactionable + 1))
        fi
    fi
done

# Always printed, on every path out of the loop. It is the run's own account of
# what it did, so suppressing it on the way to an error leaves the caller with
# a failure and no idea what already happened.
emit acted "$acted"

if [ "$unactionable" -gt 0 ]; then
    printf '%s: %s proven target(s) could not be acted on by the runtime; %s acted on, %s refused before acting.\n' \
        "$me" "$unactionable" "$acted" "$refusals" >&2
    exit 4
fi
if [ "$refusals" -gt 0 ]; then
    printf '%s: %s target(s) were refused individually, each by name and with a reason; %s proven target(s) were acted on.\n' \
        "$me" "$refusals" "$acted" >&2
    exit 3
fi
exit 0
