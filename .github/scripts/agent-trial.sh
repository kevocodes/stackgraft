#!/bin/sh
# The agent trial: a repeatable way to hand this skill to an agent that has
# never seen it, and to judge what came back.
#
# WHY THIS IS NOT A CI JOB. It needs a model in the loop. It is not
# deterministic, its cost is real, and its verdict is a report rather than an
# exit code. Every other floor in this repository drives the mechanism with a
# script that already knows what to pass it -- which is exactly why none of
# them could find what this found: the seeded copy published on every
# interface, a subject derived from a diff that is empty on the ordinary run, a
# sentence telling agents to write a field the schema forbids. What an agent
# supplies is the ABSENCE of that knowledge, and nothing else here supplies it.
#
# What IS mechanical is the half around the model: building an isolated
# subject, capturing what every store held before, and measuring afterwards
# whether any of it moved. The five trials that produced the findings above did
# that by hand each time. This does it the same way twice.
#
# usage:  sh .github/scripts/agent-trial.sh setup      # build it, print the prompt
#         sh .github/scripts/agent-trial.sh check      # judge what the run left
#         sh .github/scripts/agent-trial.sh teardown   # remove all of it
set -u

REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
FIXTURE="$REPO/.github/fixtures/shopdemo"
PROMPT="$REPO/.github/agent-trial/prompt.md"

# Deliberately under $HOME and never under /tmp: the skill carries a hard rule
# against a worktree there, and a harness that broke it would be handing the
# agent a subject the skill forbids.
TRIAL="$HOME/Workspaces/stackgraft-agent-trial"
MAIN="$TRIAL/shopdemo"
TREE="$TRIAL/shopdemo-worktrees/discount"
BASELINE="$TRIAL/.baseline"
PROJECT=sg-fixture-shopdemo
STORES='postgres sessions orders-db catalog-docs'

ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; FAILED=1; }
note() { printf '        %s\n' "$1"; }

read_store() { sh "$MAIN/scripts/db-read-$1" "$PROJECT-$1-1" 2>/dev/null || printf 'unreadable'; }

capture() {
    for s in $STORES; do printf '%s\t%s\n' "$s" "$(read_store "$s")"; done
    # The column list is the check a store count cannot make: an ALTER TABLE
    # moves no table count and no row count, and it is the exact shape of what
    # a worktree's migration does.
    printf 'pg-columns\t%s\n' "$(docker exec "$PROJECT-postgres-1" psql -U shop -d shop -tAc \
        "SELECT string_agg(column_name, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_name='products'" 2>/dev/null)"
    printf 'pg-rows\t%s\n' "$(docker exec "$PROJECT-postgres-1" psql -U shop -d shop -tAc 'SELECT count(*) FROM products' 2>/dev/null)"
}

case ${1:-} in
setup)
    sh "$0" teardown >/dev/null 2>&1
    mkdir -p "$TRIAL"
    cp -R "$FIXTURE" "$MAIN"
    mkdir -p "$MAIN/.agents/skills"
    cp -R "$REPO/skills/stackgraft" "$MAIN/.agents/skills/stackgraft"

    # Nothing from this repository's own verification may be reachable: a
    # trial that can read the floors is measuring the floors.
    if find "$TRIAL" -name 'integration*' -o -name 'verify.sh' | grep -q .; then
        printf 'refusing: a verification script leaked into the trial workspace\n' >&2
        exit 1
    fi

    ( cd "$MAIN" && git init -q -b main && git add -A \
      && git -c user.email=trial@example.com -c user.name=trial commit -qm 'the shopdemo stack' ) >/dev/null 2>&1
    git -C "$MAIN" worktree add -q -b feat/discount "$TREE" >/dev/null 2>&1

    # The change is left UNCOMMITTED on purpose. That is the ordinary shape,
    # and it is the one that found the subject-selection defect.
    mkdir -p "$TREE/db/migrations"
    printf 'ALTER TABLE products ADD COLUMN discount_cents integer NOT NULL DEFAULT 0;\nUPDATE products SET discount_cents = 500 WHERE sku = %s;\n' "'SKU-001'" \
        > "$TREE/db/migrations/001_add_discount.sql"
    python3 - "$TREE/services/catalog-api/handle.sh" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace("""body=$(printf '{"service":"catalog-api","path":"%s","products":%s}' "$path" "$products")""",
"""discounted=$(psql "$DATABASE_URL" -tAc 'SELECT count(*) FROM products WHERE discount_cents > 0' 2>/dev/null || printf 'unavailable')
body=$(printf '{"service":"catalog-api","path":"%s","products":%s,"discounted":%s}' "$path" "$products" "$discounted")""")
p.write_text(s)
PY
    rm -f "$HOME/.cache/stackgraft/shopdemo-"*.json 2>/dev/null
    docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --wait >/dev/null 2>&1 \
        || { printf 'refusing: the base stack did not come up\n' >&2; exit 1; }
    capture > "$BASELINE"

    printf '\nthe agent trial is set up\n\n'
    printf '  worktree      %s\n' "$TREE"
    printf '  skill         %s\n' "$MAIN/.agents/skills/stackgraft"
    printf '  base stack    %s, four stores\n' "$PROJECT"
    printf '  baseline      %s\n\n' "$BASELINE"
    printf '  hand the agent the prompt in %s\n' "$PROMPT"
    printf '  then: sh .github/scripts/agent-trial.sh check\n\n'
    ;;

check)
    [ -f "$BASELINE" ] || { printf 'no baseline: run setup first\n' >&2; exit 2; }
    FAILED=0
    printf '\nwhat the run left\n\n'

    capture > "$TRIAL/.after"
    if diff -u "$BASELINE" "$TRIAL/.after" >/dev/null 2>&1; then
        ok 'every store holds exactly what it held before the run'
        while IFS="$(printf '\t')" read -r k v; do note "$k = $v"; done < "$BASELINE"
    else
        bad 'a store moved -- the run wrote into the base stack'
        diff -u "$BASELINE" "$TRIAL/.after" | tail -n +4
    fi

    left=$(docker ps -a --filter 'label=stackgraft.labels' --format '{{.Names}}' | tr '\n' ' ')
    vols=$(docker volume ls --filter 'label=stackgraft.labels' --format '{{.Name}}' | tr '\n' ' ')
    [ -n "$left$vols" ] && note "still running or held: $left$vols" \
                        || note 'no labelled containers or volumes remain'
    man=$(ls "$HOME/.cache/stackgraft/shopdemo-"*.json 2>/dev/null | head -1)
    [ -n "$man" ] && note "manifest written: $man" || note 'no manifest was written'

    printf '\n  the mechanical half is above. The rest is the report:\n'
    sed -n '/^## Judging/,$p' "$PROMPT" | sed 's/^/  /'
    printf '\n'
    [ "$FAILED" = 0 ] || exit 1
    ;;

teardown)
    docker ps -a --filter 'label=stackgraft.labels' --format '{{.ID}}' | while read -r c; do
        [ -n "$c" ] && docker rm -fv "$c" >/dev/null 2>&1
    done
    docker volume ls --filter 'label=stackgraft.labels' --format '{{.Name}}' | while read -r v; do
        [ -n "$v" ] && docker volume rm -f "$v" >/dev/null 2>&1
    done
    [ -d "$MAIN" ] && docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" down -v >/dev/null 2>&1
    rm -rf "$TRIAL"
    rm -f "$HOME/.cache/stackgraft/shopdemo-"*.json 2>/dev/null
    printf 'the trial is torn down\n'
    ;;

*)
    printf 'usage: %s setup | check | teardown\n' "$0" >&2
    exit 2
    ;;
esac
