#!/bin/sh
# Behavioural floor: the seeded-copy road, driven end to end against a real
# store rather than against prose describing it.
#
# Everything else this repository verifies asks whether a document says a thing
# and whether a record validates. Both are worth checking and neither can
# notice a recipe that does not run, because the rows check that the prose says
# what it says. This file exists to notice exactly that class, and it earns its
# runtime by booting the store's own image under the store's own entrypoint --
# an --entrypoint override would hide the boot requirements that are the point.
#
# Scope, stated so it is not mistaken for more: this proves the three outputs of
# `references/isolation-providers.md` against one real engine. The offer flow
# above it -- showing a generated family, approval, the fingerprint over three
# files -- is a separate layer and is not claimed here.
#
# usage: sh .github/scripts/integration.sh
#        STACKGRAFT_REQUIRE_RUNTIME=1 makes an absent runtime fatal instead of
#        a named skip, exactly as it does in verify.sh.
set -u

checks=0
failures=0
skips=0

ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }
skip() { skips=$((skips + 1));   printf '  skip  %s\n' "$1"; }

FIXTURE=$(CDPATH= cd -- "$(dirname "$0")/../fixtures/shopdemo" && pwd -P)
PROJECT=sg-fixture-shopdemo
STORE=postgres
LABEL_REPO=sgfixture
COPY_NAME="sg-fixture-copy-$STORE"
COPY_VOLUME="sg-fixture-copyvol-$STORE"
PROBE_NAME="sg-fixture-probe-$STORE"

cleanup() {
    docker rm -fv "$COPY_NAME" "$PROBE_NAME" "sg-fixture-bare-$STORE" >/dev/null 2>&1 || true
    docker volume rm -f "$COPY_VOLUME" >/dev/null 2>&1 || true
    docker compose -p "$PROJECT" -f "$FIXTURE/compose.yaml" down -v >/dev/null 2>&1 || true
    [ -n "${ENV_FILE:-}" ] && rm -f "$ENV_FILE"
    return 0
}
trap cleanup EXIT INT TERM

printf '\nthe seeded-copy road against a real store\n\n'

if ! docker info >/dev/null 2>&1; then
    skip 'no container runtime, so the whole floor is unexercised'
    if [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ]; then
        printf '\n  a runtime was required and none answered\n\n'
        exit 1
    fi
    printf '\n  %s check(s) ran, %s skipped\n\n' "$checks" "$skips"
    exit 0
fi

# --- the base stack, brought up the way the repository brings it up ----------

cleanup
# Taken before anything is created, because the teardown below removes the
# stack's own volume too: a baseline read after `up` can never match.
INVENTORY_BEFORE=$(docker volume ls --format '{{.Name}}' | sort)

if docker compose -p "$PROJECT" -f "$FIXTURE/compose.yaml" up -d --wait >/dev/null 2>&1; then
    ok 'the fixture base stack comes up and its store reports healthy'
else
    fail 'the fixture base stack did not come up; nothing below can be trusted'
    exit 1
fi

BASE=$(docker compose -p "$PROJECT" -f "$FIXTURE/compose.yaml" ps -q "$STORE")
[ -n "$BASE" ] && ok 'the base store instance is discoverable through the orchestrator' \
               || fail 'the base store instance could not be resolved'

# --- read back rather than guess, per isolation-providers.md ----------------
# "Everything engine-specific is read back from the runtime, never guessed and
# never defaulted: which object holds the state, which image runs it, where
# that image mounts it, what environment and command the base container runs
# under, and which network it sits on."

IMAGE=$(docker inspect -f '{{.Config.Image}}' "$BASE")
MOUNT=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Destination}}{{end}}{{end}}' "$BASE")
SOURCE_VOLUME=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' "$BASE")

[ -n "$IMAGE" ] && [ -n "$MOUNT" ] && [ -n "$SOURCE_VOLUME" ] \
    && ok "the image, its mount point and the volume holding the state are read back: $IMAGE at $MOUNT" \
    || fail 'the runtime did not answer for image, mount point or state volume'

# The environment the base container runs under, read back as its own rule
# requires. This is what an instance of the same image needs in order to boot
# at all, and it is a property of the image rather than of the data.
base_env() {
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$BASE" \
        | awk '!/^(PATH|HOSTNAME|HOME|TERM|PG_VERSION|PGDATA|GOSU_VERSION|LANG|PG_MAJOR|PG_SHA256)=/ && NF'
}
# Written to a file rather than expanded on a command line: a value holding a
# whitespace character -- and the shipped image bakes one in -- is one argument
# to the runtime and several to the shell.
ENV_FILE=$(mktemp)
base_env > "$ENV_FILE"

if [ -n "$(base_env)" ]; then
    ok "the environment the base container runs under is read back: $(base_env | awk -F= '{print $1}' | tr '\n' ' ')"
else
    fail 'no environment was read back from the base container'
fi

# --- the copy ---------------------------------------------------------------

docker volume create "$COPY_VOLUME" >/dev/null 2>&1
if docker run --rm \
        -v "$SOURCE_VOLUME":/from:ro -v "$COPY_VOLUME":/to \
        "$IMAGE" sh -c 'cd /from && tar cf - . | (cd /to && tar xf -)' >/dev/null 2>&1; then
    ok 'the state volume is copied byte for byte into a volume this run made'
else
    fail 'the state volume could not be copied'
fi

# The copy is a second instance of the same image, on the copied state, under
# the environment read back above. Four labels are what a copy is.
if docker run -d --name "$COPY_NAME" \
        --label "stackgraft.repo=$LABEL_REPO" \
        --label "stackgraft.worktree=integration" \
        --label "stackgraft.store=$STORE" \
        --label "stackgraft.kind=copy" \
        --env-file "$ENV_FILE" \
        -v "$COPY_VOLUME":"$MOUNT" \
        "$IMAGE" >/dev/null 2>&1; then
    ok 'the copy starts as a second instance of the same image on the copied state'
else
    fail 'the copy did not start'
fi

# --- the empty instance -----------------------------------------------------
# The instance holds nothing because it mounts nothing. That is a property of
# what it is given, never of what it is told: an image can require environment
# in order to boot at all, and a store image that refuses to initialise without
# one is the ordinary case rather than an exotic one.
#
# The first row proves that requirement is real, so that a later reader cannot
# take the environment back out and still see this file pass. The second row is
# the empty instance the comparison actually needs.

BARE_NAME="sg-fixture-bare-$STORE"
docker rm -fv "$BARE_NAME" >/dev/null 2>&1 || true
docker run -d --name "$BARE_NAME" --label "stackgraft.probe=$STORE" "$IMAGE" >/dev/null 2>&1 || true

# The claim is that such an instance never becomes usable -- not that it is
# already dead the instant after `run` returns. Reading the status straight back
# is a race the runner wins and a laptop loses: the container is still `running`
# while its entrypoint is deciding to exit, and the row then reports the
# opposite of what happened. So this waits for the outcome instead of sampling
# the moment, and only a readiness answer falsifies it.
bare_outcome() {
    _n=0
    while [ "$_n" -lt 30 ]; do
        if docker exec "$BARE_NAME" pg_isready -U shop -d shop >/dev/null 2>&1; then
            printf 'usable'
            return 0
        fi
        case $(docker inspect -f '{{.State.Status}}' "$BARE_NAME" 2>/dev/null || printf absent) in
            exited|dead|absent) printf 'refused-to-start'; return 0 ;;
        esac
        _n=$((_n + 1))
        sleep 1
    done
    printf 'never-ready'
}

bare_state=$(bare_outcome)
bare_why=$(docker logs "$BARE_NAME" 2>&1 | awk 'NF' | head -1 || printf '')
docker rm -fv "$BARE_NAME" >/dev/null 2>&1 || true

if [ "$bare_state" = usable ]; then
    fail 'an instance of this image launched with no environment became usable, so this row no longer evidences why the environment is passed'
else
    ok "an instance of this image launched with no environment never becomes usable ($bare_state), which is why the empty instance is given the environment read back: $bare_why"
fi

docker run -d --name "$PROBE_NAME" \
    --label "stackgraft.repo=$LABEL_REPO" \
    --label "stackgraft.worktree=integration" \
    --label "stackgraft.probe=$STORE" \
    --env-file "$ENV_FILE" \
    "$IMAGE" >/dev/null 2>&1 || true

probe_state=$(docker inspect -f '{{.State.Status}}' "$PROBE_NAME" 2>/dev/null || printf 'absent')
probe_why=$(docker logs "$PROBE_NAME" 2>&1 | awk 'NF' | head -1 || printf '')

if [ "$probe_state" = running ]; then
    ok 'the empty instance comes up under the environment read back from the base container'
else
    fail "the empty instance is '$probe_state', so no comparison can be made against it: $probe_why"
fi

# --- the three outputs, through one route -----------------------------------

READ="$FIXTURE/scripts/db-read-$STORE"
wait_ready() {
    _n=0
    while [ "$_n" -lt 40 ]; do
        docker exec "$1" pg_isready -U shop -d shop >/dev/null 2>&1 && return 0
        _n=$((_n + 1))
        sleep 1
    done
    return 1
}

wait_ready "$BASE"      || true
wait_ready "$COPY_NAME" || true
wait_ready "$PROBE_NAME" 2>/dev/null || true

out_base=$(sh "$READ" "$BASE"       2>/dev/null || printf 'unreadable')
out_copy=$(sh "$READ" "$COPY_NAME"  2>/dev/null || printf 'unreadable')
out_probe=$(sh "$READ" "$PROBE_NAME" 2>/dev/null || printf 'unreadable')

printf '        base=%s  copy=%s  empty=%s\n' "$out_base" "$out_copy" "$out_probe"

# Comparison one: the candidate is a query only once its output on the base
# store differs from its output on the empty instance.
if [ "$out_base" != unreadable ] && [ "$out_probe" != unreadable ] && [ "$out_base" != "$out_probe" ]; then
    ok "the candidate discriminates: the base store answers '$out_base' where an empty instance answers '$out_probe'"
else
    fail "the candidate discriminates nothing: base '$out_base' against empty '$out_probe'"
fi

# Comparison two: the copy is verified only once its output matches the base
# store's, byte for byte.
if [ "$out_copy" != unreadable ] && [ "$out_copy" = "$out_base" ]; then
    ok "the copy carries the base store's state: both answer '$out_base'"
else
    fail "the copy does not match the base store: copy '$out_copy' against base '$out_base'"
fi

# --- and it leaves nothing behind -------------------------------------------

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
