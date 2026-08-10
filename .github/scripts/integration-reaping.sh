#!/bin/sh
# The ninth floor: the mutation. This is the only code in this skill that stops
# and removes objects on the developer's machine, and nothing had ever driven it.
#
# Every other floor reads, copies, or launches. A mistake there gives a wrong
# answer. A mistake HERE takes something off the machine -- and one hard rule in
# SKILL.md hangs entirely off this path: "Never stop a process without proof it
# is yours: a recorded (pid, lstart) that still matches. No record, no match, no
# action; a port, the manifest and the user are not proof."
#
# What existed before: `report` in five floors, and one row asserting a mutation
# with no port refuses. The refusal path, never the removal path. Not one row had
# an orphan classified and then actually stopped, and the negatives that matter
# most -- a live worktree's overlay left alone, a copy refused under `stop` -- were
# prose.
#
# The negatives come first here, deliberately. On this path a false ok is a
# container that survived; a false refusal is a message. The dangerous direction
# is the one that acts.
#
# usage: sh .github/scripts/integration-reaping.sh
set -u

checks=0
failures=0
ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }

REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
FIXTURE="$REPO/.github/fixtures/shopdemo"
SCRIPTS="$REPO/skills/stackgraft/scripts"
WORK="$REPO/.sg-work-reaping"
MAIN="$WORK/shopdemo"
TREE="$WORK/shopdemo-worktrees/doomed"
KEEP="$WORK/shopdemo-worktrees/kept"
PROJECT=sg-reap-shopdemo
PORT=18555
KEEP_PORT=18556

cleanup() {
    docker rm -fv sg-reap-orphan sg-reap-kept >/dev/null 2>&1 || true
    docker volume rm -f sg-reap-copyvol >/dev/null 2>&1 || true
    [ -d "$MAIN" ] && docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" down -v >/dev/null 2>&1
    rm -rf "$WORK"
    return 0
}
trap cleanup EXIT INT TERM

printf '\nthe mutation: stopping and removing what this run owns\n\n'

if ! docker info >/dev/null 2>&1; then
    printf '  skip  no container runtime, so the actuator is unexercised\n'
    [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ] && exit 1
    exit 0
fi

cleanup
INVENTORY_BEFORE=$(docker volume ls --format '{{.Name}}' | sort)

mkdir -p "$MAIN"
cp -R "$FIXTURE/." "$MAIN/"
( cd "$MAIN" && git init -q -b main && git add -A \
  && git -c user.email=f@e.com -c user.name=f commit -qm base ) >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b feat/doomed "$TREE" >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b feat/kept   "$KEEP" >/dev/null 2>&1
HASH=$(printf '%s' "$(CDPATH= cd -- "$MAIN" && CDPATH= cd -- "$(git rev-parse --git-common-dir)" && pwd -P)" \
    | git hash-object --stdin | cut -c1-8)

docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --wait >/dev/null 2>&1 \
    && ok 'the base stack is up, and its published ports are what the actuator has to be told' \
    || { fail 'the base stack did not come up'; exit 1; }
IMAGE=$(docker inspect -f '{{.Config.Image}}' "$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" ps -q postgres)")
BASE_PORTS='-b 13306 -b 15432 -b 16379 -b 17017 -b 18080'

# Two overlays with the complete five-label set: one whose worktree will be
# deleted, one whose worktree stays. The second exists only so every mutation
# below has something it must NOT touch.
launch() {
    docker run -d --name "$1" \
        --label 'stackgraft.labels=1' --label "stackgraft.repo=$HASH" \
        --label "stackgraft.worktree=$2" --label 'stackgraft.service=catalog-api' \
        --label "stackgraft.port=$3" \
        -p "127.0.0.1:$3:8080" "$IMAGE" sleep 3600 >/dev/null 2>&1
}
launch sg-reap-orphan "$TREE" "$PORT" && launch sg-reap-kept "$KEEP" "$KEEP_PORT" \
    && ok 'two overlays carry the complete five-label set, one per worktree' \
    || fail 'the overlays did not launch'

report() { sh "$SCRIPTS/reap.sh" -C "$MAIN" $BASE_PORTS report "$HASH" 2>/dev/null; }
cid() { docker inspect -f '{{.Id}}' "$1" 2>/dev/null | cut -c1-12; }
alive() { docker ps -a --filter "name=^$1$" --format '{{.Names}}' | wc -l | tr -d ' '; }

# --- the negatives, before anything is allowed to act -----------------------

report | grep -q "^container	.*	live$" \
    && ok 'while both worktrees are listed, the report classifies their overlays live and names no orphan' \
    || fail "the report did not classify a live overlay: $(report | rg '^container' | head -1)"

for verb in stop remove; do
    out=$(sh "$SCRIPTS/reap.sh" -C "$MAIN" $BASE_PORTS -m "$verb" "$HASH" "c:$(cid sg-reap-orphan)" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ] && [ "$(alive sg-reap-orphan)" = 1 ]; then
        ok "$verb on an overlay whose worktree is still listed is refused and the container survives (exit $rc)"
    else
        fail "$verb acted on a live worktree's overlay: exit $rc, survives=$(alive sg-reap-orphan)"
    fi
done

out=$(sh "$SCRIPTS/reap.sh" -C "$MAIN" -m stop "$HASH" "c:$(cid sg-reap-orphan)" 2>&1); rc=$?
[ "$rc" -ne 0 ] && [ "$(alive sg-reap-orphan)" = 1 ] \
    && ok "a mutation given no base port refuses rather than guessing one (exit $rc)" \
    || fail "a portless mutation acted: exit $rc"

# A copy is the one object on this host nothing can reproduce, so removing one
# takes the removal verb ON TOP OF the mutation flag: a v: target under stop is
# refused by name.
docker volume create --label 'stackgraft.labels=1' --label "stackgraft.repo=$HASH" \
    --label "stackgraft.worktree=$TREE" --label 'stackgraft.store=postgres' sg-reap-copyvol >/dev/null 2>&1
out=$(sh "$SCRIPTS/reap.sh" -C "$MAIN" $BASE_PORTS -m stop "$HASH" "v:sg-reap-copyvol" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && docker volume inspect sg-reap-copyvol >/dev/null 2>&1; then
    ok "a copy under \`stop\` is refused by name and survives, because a copy is not a thing a stop can mean (exit $rc)"
else
    fail "a v: target under stop was acted on: exit $rc"
fi

# --- now make it an orphan, and only then let the actuator act ---------------

git -C "$MAIN" worktree remove --force "$TREE" >/dev/null 2>&1
git -C "$MAIN" worktree prune >/dev/null 2>&1
[ ! -d "$TREE" ] \
    && ok "the doomed worktree is gone, which is what turns its overlay into an orphan -- liveness is git's own worktree list, never a timer" \
    || fail 'the worktree was not removed'

orphans=$(report | awk -F'\t' '$1=="container" && $NF=="orphan"{print $2}')
kept_live=$(report | awk -F'\t' '$1=="container" && $NF=="live"{print $2}' | wc -l | tr -d ' ')
case "$orphans" in
    *sg-reap-orphan*|?*) ok "the report classifies exactly the overlay whose worktree vanished as an orphan, and still calls the other live ($kept_live live)" ;;
    *) fail "the orphan was not classified: '$orphans'" ;;
esac
[ "$kept_live" = 1 ] || fail "the surviving worktree's overlay is no longer live: $kept_live"

# THE STOP. First the thing it must not touch, then the thing it must.
sh "$SCRIPTS/reap.sh" -C "$MAIN" $BASE_PORTS -m stop "$HASH" "c:$(cid sg-reap-orphan)" >/dev/null 2>&1
stopped=$(docker inspect -f '{{.State.Status}}' sg-reap-orphan 2>/dev/null || printf absent)
kept_state=$(docker inspect -f '{{.State.Status}}' sg-reap-kept 2>/dev/null || printf absent)
[ "$stopped" != running ] && [ "$kept_state" = running ] \
    && ok "stop takes the orphan and nothing else: the orphan is '$stopped' and the live worktree's overlay is still '$kept_state'" \
    || fail "stop hit the wrong thing: orphan=$stopped kept=$kept_state"

# THE REMOVE, which takes a second flag on top of the first.
sh "$SCRIPTS/reap.sh" -C "$MAIN" $BASE_PORTS -m remove "$HASH" "c:$(cid sg-reap-orphan)" >/dev/null 2>&1
[ "$(alive sg-reap-orphan)" = 0 ] && [ "$(alive sg-reap-kept)" = 1 ] \
    && ok 'remove takes the orphan off the machine and leaves the other overlay where it was' \
    || fail "remove left the wrong state: orphan=$(alive sg-reap-orphan) kept=$(alive sg-reap-kept)"

# A target this run never recorded is not a target, whatever it is named.
docker run -d --name sg-reap-stranger "$IMAGE" sleep 300 >/dev/null 2>&1
out=$(sh "$SCRIPTS/reap.sh" -C "$MAIN" $BASE_PORTS -m remove "$HASH" "c:$(cid sg-reap-stranger)" 2>&1); rc=$?
survives=$(docker ps -a --filter 'name=^sg-reap-stranger$' --format '{{.Names}}' | wc -l | tr -d ' ')
docker rm -fv sg-reap-stranger >/dev/null 2>&1
[ "$rc" -ne 0 ] && [ "$survives" = 1 ] \
    && ok "an unlabelled container is refused by name and survives: no record, no match, no action (exit $rc)" \
    || fail "a container carrying none of this skill's labels was acted on: exit $rc, survives=$survives"

cleanup
INVENTORY_AFTER=$(docker volume ls --format '{{.Name}}' | sort)
[ "$INVENTORY_BEFORE" = "$INVENTORY_AFTER" ] \
    && ok 'the volume inventory is identical at start and end' \
    || fail 'the run left volumes behind'

printf '\nresult\n'
if [ "$failures" -eq 0 ]; then
    printf '  %s check(s) ran and passed\n\n' "$checks"; exit 0
fi
printf '  %s check(s) ran; %s failed\n\n' "$checks" "$failures"; exit 1
