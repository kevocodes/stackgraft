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
PROMPT="$REPO/.github/agent-trial/prompt.md"

# The subject is an argument because a trial re-run against the same subject
# measures the same surface. Every finding worth having came from a subject the
# previous trial did not have: shopdemo answers "can an agent drive the overlay",
# monodemo answers what a repository SHAPED like a real one does to that — one
# build context shared by five units with a dockerfile at its root, stores only
# durable state identifies, an empty rung 1, and no lifecycle family at all.
SUBJECT=${2:-shopdemo}
case $SUBJECT in
    shopdemo)
        BRANCH=feat/discount; WT=discount
        PROJECT=sg-fixture-shopdemo
        STORES='postgres sessions orders-db catalog-docs' ;;
    monodemo)
        BRANCH=feat/order-notes; WT=order-notes
        PROJECT=sg-fixture-monodemo
        STORES='ledger archive cache snapshots' ;;
    *)
        printf 'unknown subject: %s (shopdemo | monodemo)\n' "$SUBJECT" >&2; exit 2 ;;
esac

FIXTURE="$REPO/.github/fixtures/$SUBJECT"

# Deliberately under $HOME and never under /tmp: the skill carries a hard rule
# against a worktree there, and a harness that broke it would be handing the
# agent a subject the skill forbids.
TRIAL="$HOME/Workspaces/stackgraft-agent-trial"
MAIN="$TRIAL/$SUBJECT"
TREE="$TRIAL/$SUBJECT-worktrees/$WT"
BASELINE="$TRIAL/.baseline"

ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; FAILED=1; }
note() { printf '        %s\n' "$1"; }

# The harness keeps its own readers under .harness/, because setup removes the
# repository's copies on purpose: the subject must not ship the answer, and the
# measurement still has to be able to ask the question.
read_store() { sh "$TRIAL/.harness/db-read-$1" "$PROJECT-$1-1" 2>/dev/null || printf 'unreadable'; }

# A baseline is the measurement everything else is compared against, so it is
# waited for rather than sampled: a store still starting reads as unreadable,
# and an unreadable baseline cannot show that anything moved. Each reader FAILS
# when it cannot reach its store, which is what makes waiting on it meaningful.
wait_readable() {
    for s in $STORES; do
        _n=0
        while [ "$_n" -lt 90 ]; do
            sh "$TRIAL/.harness/db-read-$s" "$PROJECT-$s-1" >/dev/null 2>&1 && break
            _n=$((_n + 1)); sleep 1
        done
        [ "$_n" -lt 90 ] || { printf 'refusing: %s never became readable, so no baseline can be taken\n' "$s" >&2; exit 1; }
    done
}

capture() {
    for s in $STORES; do printf '%s\t%s\n' "$s" "$(read_store "$s")"; done
    # A store count is not enough on its own. An ALTER TABLE moves no table
    # count and no row count, and it is the exact shape of what a worktree's
    # migration does, so the relational store is also read column by column.
    case $SUBJECT in
    shopdemo)
        printf 'pg-columns\t%s\n' "$(docker exec "$PROJECT-postgres-1" psql -U shop -d shop -tAc \
            "SELECT string_agg(column_name, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_name='products'" 2>/dev/null)"
        printf 'pg-rows\t%s\n' "$(docker exec "$PROJECT-postgres-1" psql -U shop -d shop -tAc 'SELECT count(*) FROM products' 2>/dev/null)" ;;
    monodemo)
        printf 'pg-columns\t%s\n' "$(docker exec "$PROJECT-ledger-1" psql -U mono -d mono -tAc \
            "SELECT string_agg(column_name, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_name='order_lines'" 2>/dev/null)"
        printf 'pg-rows\t%s\n' "$(docker exec "$PROJECT-ledger-1" psql -U mono -d mono -tAc 'SELECT count(*) FROM invoices' 2>/dev/null)"
        # The scheduler's own row: billing's loop stamps it, so a SECOND loop
        # running in an overlay is visible here and nowhere else.
        printf 'scheduler\t%s\n' "$(docker exec "$PROJECT-ledger-1" psql -U mono -d mono -tAc \
            'SELECT count(*) FROM billing_schedules' 2>/dev/null)" ;;
    esac
}

# monodemo ships NO db-read-<store> of its own -- that absence is the whole
# point of the subject, since it is what a real first run meets. So the harness
# authors its own, which never enter the trial workspace's repository.
write_monodemo_readers() {
    d=$1
    cat > "$d/db-read-ledger" <<'SH'
#!/bin/sh
set -eu
exec docker exec "$1" psql -U mono -d mono -tAc \
    "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema')"
SH
    cat > "$d/db-read-archive" <<'SH'
#!/bin/sh
set -eu
# curl first and let its status stand on its own: a count that is also its own
# failure value cannot be told from an empty store.
exec docker exec "$1" sh -c '
  dbs=$(curl -sf -u mono:mono http://127.0.0.1:5984/_all_dbs) || exit 1
  printf "%s" "$dbs" | tr "," "\n" | grep -c "\"[^_]" || true'
SH
    cat > "$d/db-read-cache" <<'SH'
#!/bin/sh
set -eu
exec docker exec "$1" redis-cli DBSIZE
SH
    cat > "$d/db-read-snapshots" <<'SH'
#!/bin/sh
set -eu
exec docker exec "$1" sh -c 'ls -1 /snapshots 2>/dev/null | wc -l'
SH
    chmod +x "$d"/db-read-*
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
    # The fixture ships a db-read-<store> per store so the copy-road floors have
    # a rung-2 source. A real repository has none -- that is the measured case
    # this skill was built for, "zero of four stores supply a rung-1 candidate" --
    # so every trial run against the fixture as shipped was easier than life:
    # the query was pre-answered and the generated-family offer, which is what a
    # real first run actually meets, was never reached. The trial removes them.
    mkdir -p "$TRIAL/.harness"
    case $SUBJECT in
    shopdemo)
        cp "$MAIN"/scripts/db-read-* "$TRIAL/.harness/"
        rm -f "$MAIN"/scripts/db-read-* ;;
    monodemo)
        # Nothing to move: this subject ships none, which is the case it exists
        # to present. The harness supplies its own measurement instead.
        write_monodemo_readers "$TRIAL/.harness" ;;
    esac
    leaked=$(find "$MAIN" -name 'db-read-*' -o -name 'db-create-*' -o -name 'db-drop-*')
    if [ -n "$leaked" ]; then
        printf 'refusing: a lifecycle file is visible to the agent: %s\n' "$leaked" >&2
        exit 1
    fi

    if find "$TRIAL" -name 'integration*' -o -name 'verify.sh' | grep -q .; then
        printf 'refusing: a verification script leaked into the trial workspace\n' >&2
        exit 1
    fi

    ( cd "$MAIN" && git init -q -b main && git add -A \
      && git -c user.email=trial@example.com -c user.name=trial commit -qm "the $SUBJECT stack" ) >/dev/null 2>&1
    git -C "$MAIN" worktree add -q -b "$BRANCH" "$TREE" >/dev/null 2>&1

    # The change is left UNCOMMITTED on purpose. That is the ordinary shape,
    # and it is the one that found the subject-selection defect.
    if [ "$SUBJECT" = monodemo ]; then
        # The change touches this unit's OWN tree and the SHARED one in the same
        # commit, so the build-context ambiguity is live rather than hypothetical,
        # and the added ALTER sits inside the orders branch so the migration
        # trigger has exactly one store to reach.
        printf '# what orders owns\nmodule = "orders"\nnote_max_len = 280\n' > "$TREE/backend/orders/module.conf"
        # @Q@ rather than %s as the stand-in for a quote: serve.sh's own printf
        # carries %s, and substituting those would rewrite the fixture's output.
        awk '{ print }
             /ADD COLUMN IF NOT EXISTS note text/ {
                 print "        psql_ @Q@ALTER TABLE order_lines ADD COLUMN IF NOT EXISTS note_len integer@Q@" }' \
            "$TREE/backend/serve.sh" > "$TREE/.serve.new"
        sed "s/@Q@/'/g" "$TREE/.serve.new" > "$TREE/backend/serve.sh"
        rm -f "$TREE/.serve.new"
        rm -f "$HOME/.cache/stackgraft/$SUBJECT-"*.json 2>/dev/null
        docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --build >/dev/null 2>&1 \
            || { printf 'refusing: the base stack did not come up\n' >&2; exit 1; }
        wait_readable
        capture > "$BASELINE"
        printf '\nthe agent trial is set up\n\n'
        printf '  subject       %s\n' "$SUBJECT"
        printf '  worktree      %s\n' "$TREE"
        printf '  skill         %s\n' "$MAIN/.agents/skills/stackgraft"
        printf '  base stack    %s\n' "$PROJECT"
        printf '  baseline      %s\n\n' "$BASELINE"
        printf '  hand the agent the prompt in %s\n' "$PROMPT"
        printf '  then: sh .github/scripts/agent-trial.sh check %s\n\n' "$SUBJECT"
        exit 0
    fi

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
    rm -f "$HOME/.cache/stackgraft/$SUBJECT-"*.json 2>/dev/null
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
    man=$(ls "$HOME/.cache/stackgraft/$SUBJECT-"*.json 2>/dev/null | head -1)
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
    printf 'usage: %s setup|check|teardown [shopdemo|monodemo]\n' "$0" >&2
    exit 2
    ;;
esac
