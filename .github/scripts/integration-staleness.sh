#!/bin/sh
# The twelfth floor: does the overlay run the worktree's code?
#
# Every other floor here launches a unit that reads its source at run time, so
# the question never arose. Most repositories do not: a `build:` stanza with no
# source mount bakes the tree into an image, and the orchestrator's own
# single-unit run form -- the one references/discovery.md derives an
# overlayCommand from -- reuses the tag that is already there. That tag was
# built from the MAIN checkout, so the overlay serves the base stack's code and
# answers correctly while the change under test is not in it. references/traps.md
# already names the consequence for a different cause: "you will test the old
# code and believe it passed."
#
# This floor drives both halves as behaviour rather than asserting the sentence:
# that the bare run form serves the stale code, and that the rule which replaced
# it serves the worktree's without moving the base project's own image.
#
# usage: sh .github/scripts/integration-staleness.sh
set -u

checks=0
failures=0
ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }

REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
FIXTURE="$REPO/.github/fixtures/monodemo"
WORK="$REPO/.sg-work-staleness"
MAIN="$WORK/monodemo"
TREE="$WORK/worktrees/marker"
PROJECT=sg-staleness
SVC=web
OVERLAY_TAG=sg-staleness-overlay-web:trial

cleanup() {
    docker rm -fv sg-staleness-overlay >/dev/null 2>&1 || true
    [ -d "$MAIN" ] && docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" down -v >/dev/null 2>&1
    docker image rm -f "$OVERLAY_TAG" >/dev/null 2>&1 || true
    docker image rm -f "$PROJECT-$SVC" >/dev/null 2>&1 || true
    # The negative control rebuilds the base project's tag on purpose, which
    # ORPHANS the image that tag pointed at -- it survives untagged, and an
    # inventory read by repository:tag sees it as <none>:<none>. Removed by the
    # id this run recorded rather than by pruning dangling images, which would
    # take objects belonging to whoever else uses this daemon.
    [ -n "${BASE_IMAGE_ID:-}" ] && docker image rm -f "$BASE_IMAGE_ID" >/dev/null 2>&1
    rm -rf "$WORK"
    return 0
}
trap cleanup EXIT INT TERM

printf '\ndoes the overlay run the worktree code\n\n'

if ! docker info >/dev/null 2>&1; then
    printf '  skip  no container runtime\n'
    [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ] && exit 1
    exit 0
fi

cleanup
IMAGES_BEFORE=$(docker image ls --format '{{.Repository}}:{{.Tag}}' | sort)
mkdir -p "$WORK"
cp -R "$FIXTURE" "$MAIN"

# The premise: this unit bakes its source. A mounted unit would make the whole
# floor vacuous, so it is asserted rather than assumed.
if grep -q 'COPY . /app' "$MAIN/web/Dockerfile" && ! grep -A3 '^  web:' "$MAIN/compose.yaml" | grep -q 'volumes'; then
    ok 'the subject bakes its source into the image and mounts nothing, which is the ordinary shape and the one the run form gets wrong'
else
    fail 'the subject no longer bakes its source, so this floor tests nothing'
    exit 1
fi

( cd "$MAIN" && git init -q -b main && git add -A \
  && git -c user.email=f@e.com -c user.name=f commit -qm base ) >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b feat/marker "$TREE" >/dev/null 2>&1

# The base stack: built from the MAIN checkout, exactly as a developer's is.
docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" build "$SVC" >/dev/null 2>&1 \
    || { fail 'the base image would not build'; exit 1; }
docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --no-deps "$SVC" >/dev/null 2>&1
BASE_IMAGE_ID=$(docker image inspect -f '{{.Id}}' "$PROJECT-$SVC" 2>/dev/null)
[ -n "$BASE_IMAGE_ID" ] \
    && ok "the base stack's own image exists and is what a launch would reuse" \
    || fail 'the base image is missing, so there is nothing to reuse or protect'

# The change under test, in the worktree only, in a file the image bakes in.
printf '#!/bin/sh\necho "build=worktree"\n' > "$TREE/web/version.sh"
chmod +x "$TREE/web/version.sh"
[ "$(sh "$TREE/web/version.sh")" = build=worktree ] && [ "$(sh "$MAIN/web/version.sh")" = build=main ] \
    && ok 'the worktree and the main checkout now differ in a file the image bakes in' \
    || fail 'the two checkouts do not differ, so nothing distinguishes stale from fresh'

# --- half one: the run form as derived, with no rebuild ----------------------
# This is what an overlayCommand taken from the orchestrator's own single-unit
# form does. The answer it gives is a real answer from a real container.

stale=$(docker compose -p "$PROJECT" --project-directory "$TREE" -f "$TREE/compose.yaml" \
        run --rm --no-deps "$SVC" sh /app/version.sh 2>/dev/null | tr -d '\r\n ')
case $stale in
    build=main)
        ok 'the bare run form serves the MAIN checkout code from a worktree launch -- the defect, reproduced, and the reason the rule exists' ;;
    build=worktree)
        fail 'the bare run form served the worktree code, so this runtime does not reuse the tag and the rule below rests on nothing' ;;
    *)
        fail "the bare run form answered '$stale', which is neither checkout" ;;
esac

# --- half two: the rule -- build under a tag the base project does not own ---

docker build -q -t "$OVERLAY_TAG" -f "$TREE/web/Dockerfile" "$TREE/web" >/dev/null 2>&1 \
    || fail 'the overlay image would not build from the worktree'
fresh=$(docker run --rm --name sg-staleness-overlay "$OVERLAY_TAG" sh /app/version.sh 2>/dev/null | tr -d '\r\n ')
[ "$fresh" = build=worktree ] \
    && ok 'and a launch of that tag serves the WORKTREE code, which is what the overlay was for' \
    || fail "the tagged build served '$fresh' rather than the worktree's code"

# --- and the other half the two-command route is supposed to give ------------
# The tag alone was never the point. The rule it replaced asked for a tag the
# base project does not own AND the preferred network route, which runs under
# the base project -- and one Compose selector sets both, so that pair could not
# be satisfied. Building and running as two commands is only the resolution if
# the launched container really can reach the base stack by name, so that is
# measured here rather than argued.

BASE_NET=$(docker inspect -f '{{range $n, $_ := .NetworkSettings.Networks}}{{$n}}{{end}}' "$PROJECT-$SVC-1" 2>/dev/null)
[ -n "$BASE_NET" ] \
    && ok "the base stack's own network is readable from a running base container: $BASE_NET" \
    || fail 'the base stack network could not be read back, so an overlay has no name to attach to'

if [ -n "$BASE_NET" ]; then
    # Compared against the base container's ADDRESS on that network, not against
    # whether the name resolves at all. A service name like `web` is generic
    # enough to resolve through the host's own DNS -- measured: it did on a CI
    # runner and did not on the machine this was written on -- so "it resolved"
    # is not evidence that it reached the base stack. The address is.
    BASE_IP=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$BASE_NET\").IPAddress}}" "$PROJECT-$SVC-1" 2>/dev/null)
    [ -n "$BASE_IP" ] \
        && ok "the base container's address on that network is readable: $BASE_IP" \
        || fail 'the base container has no address on its own network, so there is nothing to resolve to'

    reach=$(docker run --rm --network "$BASE_NET" --entrypoint sh "$OVERLAY_TAG" \
        -c "getent hosts $SVC 2>/dev/null | awk '{print \$1; exit}'" 2>/dev/null | tr -d '\r\n ')
    [ "$reach" = "$BASE_IP" ] \
        && ok "and the worktree-tagged image, launched on that network, resolves $SVC to the base container itself -- the wiring the one-command form could not keep" \
        || fail "the two-command route resolved $SVC to '$reach' rather than the base container at $BASE_IP"

    isolated=$(docker run --rm --entrypoint sh "$OVERLAY_TAG" \
        -c "getent hosts $SVC 2>/dev/null | awk '{print \$1; exit}'" 2>/dev/null | tr -d '\r\n ')
    [ "$isolated" != "$BASE_IP" ] \
        && ok "while the same image off that network reaches something else or nothing ('$isolated'), so the row above is the network and not the image" \
        || fail 'the image reached the base container with no network attached, so that row proves nothing'
fi

AFTER_IMAGE_ID=$(docker image inspect -f '{{.Id}}' "$PROJECT-$SVC" 2>/dev/null)
[ "$AFTER_IMAGE_ID" = "$BASE_IMAGE_ID" ] \
    && ok "and the base project's own image is untouched by it, so the developer's next whole-stack up is unchanged" \
    || fail "the base project's image moved from ${BASE_IMAGE_ID#sha256:} to ${AFTER_IMAGE_ID#sha256:}"

# --- the negative control for the second half -------------------------------
# The rule says to build under a tag the base project does not own. That is only
# load-bearing if building under ITS tag actually moves it, so this does exactly
# what the rule forbids and measures the damage.

docker compose -p "$PROJECT" --project-directory "$TREE" -f "$TREE/compose.yaml" \
    build "$SVC" >/dev/null 2>&1
CONTAMINATED=$(docker image inspect -f '{{.Id}}' "$PROJECT-$SVC" 2>/dev/null)
[ "$CONTAMINATED" != "$BASE_IMAGE_ID" ] \
    && ok "a rebuild under the base project's own selector DOES move its image, which is what the tag rule prevents" \
    || fail "a rebuild under the base project's selector left its image alone, so the tag rule guards nothing"

# and the running container still holds the old one, which is why this is quiet
RUNNING=$(docker inspect -f '{{.Image}}' "$PROJECT-$SVC-1" 2>/dev/null)
[ "$RUNNING" = "$BASE_IMAGE_ID" ] \
    && ok 'while the running base container keeps the image it started on, which is why the damage is invisible until the next up' \
    || fail "the running base container's image changed underneath it: $RUNNING"

cleanup
IMAGES_AFTER=$(docker image ls --format '{{.Repository}}:{{.Tag}}' | sort)
[ "$IMAGES_BEFORE" = "$IMAGES_AFTER" ] \
    && ok 'the image inventory is identical at start and end' \
    || fail 'the run left images behind'

printf '\nresult\n'
if [ "$failures" -eq 0 ]; then
    printf '  %s check(s) ran and passed\n\n' "$checks"; exit 0
fi
printf '  %s check(s) ran; %s failed\n\n' "$checks" "$failures"; exit 1
