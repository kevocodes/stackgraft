#!/bin/sh
# The harness that runs the agent trial needs a model. Whether that harness
# still WORKS does not, and a trial nobody can set up is a trial nobody runs.
# This is the part that can rot silently: setup, a clean check, teardown, and
# nothing left behind.
set -u

checks=0
failures=0
ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }

REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
TRIAL_SH="$REPO/.github/scripts/agent-trial.sh"
TRIAL="$HOME/Workspaces/stackgraft-agent-trial"

printf '\nthe agent-trial harness\n\n'

if ! docker info >/dev/null 2>&1; then
    printf '  skip  no container runtime\n'
    [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ] && exit 1
    exit 0
fi

sh "$TRIAL_SH" teardown >/dev/null 2>&1
sh "$TRIAL_SH" setup >/dev/null 2>&1 \
    && ok 'setup builds the subject and brings its stores up' \
    || fail 'setup did not complete'

[ -d "$TRIAL/shopdemo-worktrees/discount" ] \
    && ok 'the worktree exists, outside /tmp as the skill requires' \
    || fail 'no worktree was created'
[ -f "$TRIAL/shopdemo/.agents/skills/stackgraft/SKILL.md" ] \
    && ok 'the skill is installed where an agent is told to find it' \
    || fail 'the skill was not installed into the subject'

# The change must be uncommitted, because that is the shape that found the
# subject-selection defect and a committed one would hide it again.
committed=$(git -C "$TRIAL/shopdemo-worktrees/discount" diff --name-only main...HEAD | wc -l | tr -d ' ')
dirty=$(git -C "$TRIAL/shopdemo-worktrees/discount" status --porcelain -uall | wc -l | tr -d ' ')
[ "$committed" = 0 ] && [ "$dirty" -gt 0 ] \
    && ok "the change is uncommitted, which is the ordinary shape: $dirty path(s) dirty, 0 committed" \
    || fail "the subject's change is not in the ordinary shape: $dirty dirty, $committed committed"

# The subject must not ship the answer: a repository with a db-read-<store>
# already in it has rung 2 pre-answered and never meets the generated-family
# offer, which is what a real first run actually reaches.
shipped=$(ls "$TRIAL/shopdemo"/scripts/db-read-* 2>/dev/null | wc -l | tr -d ' ')
[ "$shipped" = 0 ] \
    && ok 'the subject ships no read command, so the trial meets the offer a real first run meets' \
    || fail "the subject ships $shipped read command(s), which pre-answers rung 2 and makes the trial easier than life"
harness=$(ls "$TRIAL/.harness"/db-read-* 2>/dev/null | wc -l | tr -d ' ')
[ "$harness" = 4 ] \
    && ok 'and the harness kept its own copies, so the measurement can still ask what the subject cannot answer' \
    || fail "the harness has $harness reader(s) of 4, so check cannot measure every store"

leaked=$(find "$TRIAL" \( -name 'integration*' -o -name 'verify.sh' \) 2>/dev/null | wc -l | tr -d ' ')
[ "$leaked" = 0 ] \
    && ok 'nothing from this repository verification leaked into the subject' \
    || fail "$leaked verification script(s) are readable from inside the trial"

sh "$TRIAL_SH" check >/dev/null 2>&1 \
    && ok 'check passes on an untouched subject, so a clean run reads as clean' \
    || fail 'check failed with nothing having run'

# And it must be able to fail, or it measures nothing.
docker exec sg-fixture-shopdemo-postgres-1 psql -U shop -d shop \
    -c 'ALTER TABLE products ADD COLUMN smoke_only integer' >/dev/null 2>&1
if sh "$TRIAL_SH" check >/dev/null 2>&1; then
    fail 'check passed after a column was added to the base store, so it cannot see a write'
else
    ok 'check fails when the base store is written to, which is the one thing it exists to notice'
fi

sh "$TRIAL_SH" teardown >/dev/null 2>&1
[ -d "$TRIAL" ] && fail 'teardown left the trial directory behind' \
                || ok 'teardown removes the workspace'
left=$(docker ps -a --filter 'name=sg-fixture-shopdemo' --format '{{.Names}}' | wc -l | tr -d ' ')
[ "$left" = 0 ] && ok 'and leaves no containers of its own' \
               || fail "teardown left $left container(s)"

printf '\nresult\n'
if [ "$failures" -eq 0 ]; then
    printf '  %s check(s) ran and passed\n\n' "$checks"; exit 0
fi
printf '  %s check(s) ran; %s failed\n\n' "$checks" "$failures"; exit 1
