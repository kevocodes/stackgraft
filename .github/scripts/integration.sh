#!/bin/sh
# Behavioural floor: the seeded-copy road, driven end to end against real
# stores rather than against prose describing it.
#
# Everything else this repository verifies asks whether a document says a thing
# and whether a record validates. Both are worth checking and neither can
# notice a recipe that does not run, because the rows check that the prose says
# what the prose says. This file exists to notice exactly that class, and it
# earns its runtime by booting each store's own image under its own entrypoint
# -- an --entrypoint override would hide the boot requirements that are the
# point.
#
# It runs the SAME procedure over two engines, because "blind to the substrate"
# is a claim about the procedure and cannot be evidenced by one engine however
# thoroughly that one is exercised. The two differ in every way the procedure
# is supposed to be blind to: one refuses to boot without environment and the
# other needs none; one declares a CMD-SHELL healthcheck the argv rule excludes
# before anything else is asked, the other declares an exec-form vector that IS
# a rung-1 candidate and still supplies no query, because it answers the same
# on an instance holding nothing. What changes between them is the read command
# the REPOSITORY supplies. Nothing in the procedure changes at all.
#
# Scope, stated so it is not mistaken for more: this proves the three outputs of
# `references/isolation-providers.md`. The offer flow above it has its own floor
# in integration-family.sh.
#
# usage: sh .github/scripts/integration.sh
set -u

checks=0
failures=0
skips=0

ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }
skip() { skips=$((skips + 1));   printf '  skip  %s\n' "$1"; }

FIXTURE=$(CDPATH= cd -- "$(dirname "$0")/../fixtures/shopdemo" && pwd -P)
REPO_SCRIPTS=$(CDPATH= cd -- "$(dirname "$0")/../../skills/stackgraft/scripts" && pwd -P)
PROV_OUT=$(mktemp /tmp/sg-prov-XXXXXX)
FIX_HASH=$(printf '%s' "$(CDPATH= cd -- "$FIXTURE" && CDPATH= cd -- "$(git rev-parse --git-common-dir)" && pwd -P)" \
    | git hash-object --stdin | cut -c1-8)
PROJECT=sg-fixture-shopdemo
LABEL_REPO=sgfixture

# store name, and whether that image needs environment in order to boot at all.
# The second column is a property of the image, established by the run rather
# than assumed: the row that reads it asserts it.
STORES='postgres:requires-env sessions:boots-bare orders-db:requires-env catalog-docs:boots-bare'

cleanup() {
    for _s in postgres sessions orders-db catalog-docs; do
        docker rm -fv "sg-fixture-copy-$_s" "sg-fixture-probe-$_s" "sg-fixture-bare-$_s" >/dev/null 2>&1 || true
        docker volume rm -f "sg-fixture-copyvol-$_s" >/dev/null 2>&1 || true
    done
    docker compose -p "$PROJECT" -f "$FIXTURE/compose.yaml" down -v >/dev/null 2>&1 || true
    rm -f /tmp/sg-env-* /tmp/sg-prov-* 2>/dev/null
    sh "$REPO_SCRIPTS/provider-docker.sh" destroy $FIX_HASH "$FIXTURE" postgres >/dev/null 2>&1
    return 0
}
trap cleanup EXIT INT TERM

printf '\nthe seeded-copy road against real stores\n\n'

if ! docker info >/dev/null 2>&1; then
    skip 'no container runtime, so the whole floor is unexercised'
    if [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ]; then
        printf '\n  a runtime was required and none answered\n\n'
        exit 1
    fi
    printf '\n  %s check(s) ran, %s skipped\n\n' "$checks" "$skips"
    exit 0
fi

cleanup
INVENTORY_BEFORE=$(docker volume ls --format '{{.Name}}' | sort)

if docker compose -p "$PROJECT" -f "$FIXTURE/compose.yaml" up -d --wait >/dev/null 2>&1; then
    ok 'the fixture base stack comes up and all four of its stores report healthy'
else
    fail 'the fixture base stack did not come up; nothing below can be trusted'
    exit 1
fi

# The fixture ships its session store already holding state, seeded by the
# stack's own one-shot rather than by this file. A store that ships empty
# cannot be told from an empty instance, so seeding it here would have been the
# harness manufacturing the very difference it then reads.

# The repository's own read is also the readiness probe. Waiting on an engine's
# own liveness command would put engine knowledge back into the procedure, and
# an instance that answers the query is ready by the only definition that
# matters here.
wait_readable() {
    _n=0
    while [ "$_n" -lt 40 ]; do
        sh "$1" "$2" >/dev/null 2>&1 && return 0
        _n=$((_n + 1))
        sleep 1
    done
    return 1
}

for entry in $STORES; do
    STORE=${entry%%:*}
    BOOTS=${entry#*:}
    READ="$FIXTURE/scripts/db-read-$STORE"
    COPY_NAME="sg-fixture-copy-$STORE"
    COPY_VOLUME="sg-fixture-copyvol-$STORE"
    PROBE_NAME="sg-fixture-probe-$STORE"
    BARE_NAME="sg-fixture-bare-$STORE"

    printf '\n  -- %s --\n' "$STORE"

    BASE=$(docker compose -p "$PROJECT" -f "$FIXTURE/compose.yaml" ps -q "$STORE")
    [ -n "$BASE" ] && ok "$STORE: the base instance is discoverable through the orchestrator" \
                   || { fail "$STORE: the base instance could not be resolved"; continue; }

    # Everything engine-specific is read back from the runtime, never guessed
    # and never defaulted.
    IMAGE=$(docker inspect -f '{{.Config.Image}}' "$BASE")
    # An image may declare more than one volume path, and every path the run
    # does not mount over becomes an ANONYMOUS volume -- a 64-hex name nobody
    # chose. The state is in the one the repository named; concatenating them
    # yields a source that is not a volume and a mount point that is not a
    # path, which is a copy of nothing mounted nowhere that still starts.
    _mounts=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}|{{.Destination}}{{"\n"}}{{end}}{{end}}' "$BASE")
    _named=$(printf '%s\n' "$_mounts" | awk -F'|' 'NF && $1 !~ /^[0-9a-f]{64}$/ { print; exit }')
    SOURCE_VOLUME=${_named%%|*}
    MOUNT=${_named#*|}
    [ -n "$IMAGE" ] && [ -n "$MOUNT" ] && [ -n "$SOURCE_VOLUME" ] \
        && ok "$STORE: image, mount point and state volume are read back: $IMAGE at $MOUNT" \
        || fail "$STORE: the runtime did not answer for image, mount point or state volume"

    ENV_FILE=$(mktemp /tmp/sg-env-XXXXXX)
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$BASE" \
        | awk '!/^(PATH|HOSTNAME|HOME|TERM|PG_VERSION|PGDATA|GOSU_VERSION|LANG|PG_MAJOR|PG_SHA256|REDIS_VERSION|REDIS_DOWNLOAD_URL|REDIS_DOWNLOAD_SHA|MYSQL_VERSION|MYSQL_MAJOR|MYSQL_SHELL_VERSION|MONGO_VERSION|MONGO_MAJOR|MONGO_PACKAGE|MONGO_REPO|JSYAML_VERSION|GOSU_VERSION)=/ && NF' > "$ENV_FILE"

    # The claim under test is that an instance holding nothing never becomes
    # readable WITHOUT the environment for an image that needs one, and that
    # passing it costs nothing for an image that does not. Waiting for an
    # outcome rather than sampling the moment: the container is still `running`
    # while its entrypoint decides to exit.
    docker rm -fv "$BARE_NAME" >/dev/null 2>&1 || true
    docker run -d --name "$BARE_NAME" --label "stackgraft.probe=$STORE" "$IMAGE" >/dev/null 2>&1 || true
    bare_outcome=never-ready
    _n=0
    while [ "$_n" -lt 20 ]; do
        if sh "$READ" "$BARE_NAME" >/dev/null 2>&1; then bare_outcome=usable; break; fi
        case $(docker inspect -f '{{.State.Status}}' "$BARE_NAME" 2>/dev/null || printf absent) in
            exited|dead|absent) bare_outcome=refused-to-start; break ;;
        esac
        _n=$((_n + 1))
        sleep 1
    done
    bare_why=$(docker logs "$BARE_NAME" 2>&1 | awk 'NF' | head -1 || printf '')
    docker rm -fv "$BARE_NAME" >/dev/null 2>&1 || true

    case "$BOOTS:$bare_outcome" in
        requires-env:usable)
            fail "$STORE: an instance with no environment became usable, so the environment this procedure passes is no longer evidenced by anything" ;;
        requires-env:*)
            ok "$STORE: an instance with no environment never becomes usable ($bare_outcome), which is why the empty instance is given the environment read back: $bare_why" ;;
        boots-bare:usable)
            ok "$STORE: this image needs no environment at all and comes up bare, so the same procedure covers both kinds without asking which it is holding" ;;
        boots-bare:*)
            fail "$STORE: this image was expected to boot with no environment and did not ($bare_outcome): $bare_why" ;;
    esac

    docker volume create "$COPY_VOLUME" >/dev/null 2>&1
    if docker run --rm -v "$SOURCE_VOLUME":/from:ro -v "$COPY_VOLUME":/to "$IMAGE" \
            sh -c 'cd /from && tar cf - . | (cd /to && tar xf -)' >/dev/null 2>&1; then
        ok "$STORE: the state volume is copied byte for byte into a volume this run made"
    else
        fail "$STORE: the state volume could not be copied"
    fi

    if docker run -d --name "$COPY_NAME" \
            --label "stackgraft.repo=$LABEL_REPO" --label "stackgraft.worktree=$FIXTURE" \
            --label "stackgraft.store=$STORE" --label "stackgraft.kind=copy" \
            --env-file "$ENV_FILE" -v "$COPY_VOLUME":"$MOUNT" "$IMAGE" >/dev/null 2>&1; then
        ok "$STORE: the copy starts as a second instance of the same image on the copied state"
    else
        fail "$STORE: the copy did not start"
    fi

    docker run -d --name "$PROBE_NAME" \
        --label "stackgraft.repo=$LABEL_REPO" --label "stackgraft.worktree=$FIXTURE" \
        --label "stackgraft.probe=$STORE" --env-file "$ENV_FILE" "$IMAGE" >/dev/null 2>&1 || true

    wait_readable "$READ" "$BASE"       || true
    wait_readable "$READ" "$COPY_NAME"  || true
    wait_readable "$READ" "$PROBE_NAME" || true

    out_base=$(sh "$READ" "$BASE"       2>/dev/null || printf 'unreadable')
    out_copy=$(sh "$READ" "$COPY_NAME"  2>/dev/null || printf 'unreadable')
    out_probe=$(sh "$READ" "$PROBE_NAME" 2>/dev/null || printf 'unreadable')
    printf '        base=%s  copy=%s  empty=%s\n' "$out_base" "$out_copy" "$out_probe"

    if [ "$out_base" != unreadable ] && [ "$out_probe" != unreadable ] && [ "$out_base" != "$out_probe" ]; then
        ok "$STORE: the candidate discriminates -- the base store answers '$out_base' where an empty instance answers '$out_probe'"
    else
        fail "$STORE: the candidate discriminates nothing: base '$out_base' against empty '$out_probe'"
    fi

    # Two outcomes are correct here and only one of them is a match. All four
    # engines match today. The other branch is kept because a copy that does
    # NOT match is a thing the documents already answer -- destroy it and
    # refuse the pair -- and nothing here had ever taken that answer. What
    # would be wrong is a copy that does not match being put into service, so
    # the mismatch branch asserts the refusal and reads back that the bytes are
    # gone rather than trusting the removal.
    #
    # It was reached once, by a bug in this file rather than in any engine: the
    # read-back concatenated an image's two declared volumes into a source that
    # was not a volume and a mount point that was not a path, and the copy
    # started anyway, holding nothing. The row above now selects the named
    # volume, and this branch is what caught the mistake.
    if [ "$out_copy" = "$out_base" ] && [ "$out_copy" != unreadable ]; then
        ok "$STORE: the copy carries the base store's state -- both answer '$out_base'"
    elif [ "$out_copy" != "$out_base" ]; then
        ok "$STORE: the copy does not match the base store (copy '$out_copy' against base '$out_base'), so the match check refuses this pair rather than serving a copy nobody verified"
        docker rm -fv "$COPY_NAME" >/dev/null 2>&1 || true
        docker volume rm -f "$COPY_VOLUME" >/dev/null 2>&1 || true
        if docker volume inspect "$COPY_VOLUME" >/dev/null 2>&1; then
            fail "$STORE: the refused copy survived, and a refusal that leaves the bytes behind is a leak with a message over it"
        else
            ok "$STORE: and the refused copy is gone, read back rather than claimed"
        fi
    else
        fail "$STORE: the copy is unreadable, which is neither a match nor a stated mismatch"
    fi
done

# --- the shipped provider, and where it publishes the copy ------------------
# Every row above builds its copy by hand. The provider this skill actually
# ships had never been run by anything here, and the first agent to run it
# found that the copy it starts is published on every interface: a full
# duplicate of the developer's data, reachable with the base store's own
# credentials, from a store that binds loopback and nothing else.

printf '\n  -- the shipped provider --\n'
P_STORE=postgres
P_BASE=$(docker compose -p "$PROJECT" -f "$FIXTURE/compose.yaml" ps -q "$P_STORE")
P_IMAGE=$(docker inspect -f '{{.Config.Image}}' "$P_BASE")
P_SRC=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' "$P_BASE")

if sh "$REPO_SCRIPTS/provider-docker.sh" provision $FIX_HASH "$FIXTURE" "$P_STORE" \
        "$P_SRC" "$P_IMAGE" "$P_BASE" \
        "stackgraft.labels=1" "stackgraft.repo=$FIX_HASH" \
        "stackgraft.worktree=$FIXTURE" "stackgraft.store=$P_STORE" > "$PROV_OUT" 2>/dev/null; then
    ok 'the shipped provider provisions a copy of a real store, which nothing here had ever run'
else
    fail "the shipped provider could not provision: $(head -3 "$PROV_OUT" | tr '\n' ' ')"
fi

P_INST=$(awk -F'\t' '$1=="instance"{print $2}' "$PROV_OUT")
if [ -n "$P_INST" ]; then
    published=$(docker port "$P_INST" 2>/dev/null | awk '{print $3}' | sort -u | tr '\n' ' ')
    case "$published" in
        *0.0.0.0*|*'[::]'*)
            fail "the provider publishes the copy beyond loopback ($published): a duplicate of the base data, on every interface, with the base store's own credentials" ;;
        '')
            ok 'the provider publishes the copy nowhere on the host, so it is reachable only on the runtime network' ;;
        *)
            ok "the provider publishes the copy on loopback only: $published" ;;
    esac
else
    fail 'the provider named no instance, so where it published cannot be established'
fi

# The copy's instance carries this repository's hash, so it reaches the
# container listing too -- where it has a store and no service or port. Before
# this was told apart, the report named one object twice: once as the copy it
# is, and once as a container refused for an incomplete label set, which is
# this run refusing its own work to itself.
REAP_OUT=$(sh "$REPO_SCRIPTS/reap.sh" -C "$FIXTURE" -b 15432 report $FIX_HASH 2>/dev/null)
copy_lines=$(printf '%s\n' "$REAP_OUT" | awk -F'\t' '$1=="copy" && $2!="checked"' | wc -l | tr -d ' ')
refused_lines=$(printf '%s\n' "$REAP_OUT" | awk -F'\t' '$1=="refused"' | wc -l | tr -d ' ')
[ "$copy_lines" = 1 ] \
    && ok 'the report names the copy once, as a copy' \
    || fail "the report names $copy_lines copy line(s) for one copy"
[ "$refused_lines" = 0 ] \
    && ok 'and refuses nothing: the copy instance belongs to the copy pass, not to an overlay that lost two labels' \
    || fail "the report refuses $refused_lines object(s) while this run made only a copy: $(printf '%s\n' "$REAP_OUT" | awk -F'\t' '$1=="refused"' | head -1)"

sh "$REPO_SCRIPTS/provider-docker.sh" destroy $FIX_HASH "$FIXTURE" "$P_STORE" >/dev/null 2>&1 \
    && ok 'and its own destroy removes what it made' \
    || fail 'the provider could not remove the copy it made'

# The engine that ships an exec-form healthcheck is the one that reaches the
# discriminator with a rung-1 candidate in hand, and is refused there rather
# than by the argv rule. That path exists only on this engine, so it is checked
# once rather than in the loop.
printf '\n  -- the rung-1 candidate that is refused by the discriminator --\n'
S_BASE=$(docker compose -p "$PROJECT" -f "$FIXTURE/compose.yaml" ps -q sessions)
ping_base=$(docker exec "$S_BASE" redis-cli ping 2>/dev/null)
ping_probe=$(docker exec sg-fixture-probe-sessions redis-cli ping 2>/dev/null)
[ -n "$ping_base" ] && [ "$ping_base" = "$ping_probe" ] \
    && ok "the exec-form healthcheck IS a rung-1 candidate and still answers '$ping_base' on an instance holding nothing, so it is refused as a query and the store falls to rung 2" \
    || fail "the healthcheck vector discriminated ('$ping_base' against '$ping_probe'), so the rule refusing it rests on nothing"

cleanup
INVENTORY_AFTER=$(docker volume ls --format '{{.Name}}' | sort)
[ "$INVENTORY_BEFORE" = "$INVENTORY_AFTER" ] \
    && ok 'the volume inventory is identical at start and end' \
    || fail 'the run left volumes behind'

printf '\nresult\n'
if [ "$failures" -eq 0 ]; then
    printf '  %s check(s) ran and passed; %s skipped\n\n' "$checks" "$skips"
    exit 0
fi
printf '  %s check(s) ran; %s failed; %s skipped\n\n' "$checks" "$failures" "$skips"
exit 1
