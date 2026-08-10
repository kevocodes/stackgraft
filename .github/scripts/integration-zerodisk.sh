#!/bin/sh
# The seventh floor: the zero-disk road, which every other floor here declines.
#
# `references/shared-state.md` calls the seeded copy the default and isolating
# in place the optimisation. The optimisation had no floor at all: no fixture
# defines a database lifecycle target, so every pair in this repository reaches
# step 5 and takes a copy, and rungs 1 through 4, the template contract, the
# destructive-verb class and the approval were things we knew the documents'
# opinion of and nothing about the behaviour of.
#
# This builds the repository the other floors are not: one that already defines
# a create and a drop. That makes N=yes, which is step 4 -- a namespace inside
# the instance already running, no second container and no bytes copied.
#
# usage: sh .github/scripts/integration-zerodisk.sh
set -u

checks=0
failures=0
skips=0

ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }
skip() { skips=$((skips + 1));   printf '  skip  %s\n' "$1"; }

REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
FIXTURE="$REPO/.github/fixtures/shopdemo"
SCRIPTS="$REPO/skills/stackgraft/scripts"
WORK="$REPO/.sg-work-zerodisk"
MAIN="$WORK/shopdemo"
TREE="$WORK/shopdemo-worktrees/discount"
PROJECT=sg-zerodisk-shopdemo
IDENT=sg_wt_discount

cleanup() {
    docker rm -fv sg-zerodisk-overlay sg-zerodisk-holder >/dev/null 2>&1 || true
    if [ -d "$MAIN" ]; then
        docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" exec -T postgres \
            psql -U shop -d postgres -c "DROP DATABASE IF EXISTS $IDENT" >/dev/null 2>&1
        docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" down -v >/dev/null 2>&1
    fi
    rm -rf "$WORK"
    return 0
}
trap cleanup EXIT INT TERM

printf '\nthe zero-disk road\n\n'

if ! docker info >/dev/null 2>&1; then
    skip 'no container runtime, so the in-instance road is unexercised'
    if [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ]; then
        printf '\n  a runtime was required and none answered\n\n'
        exit 1
    fi
    printf '\n  %s check(s) ran, %s skipped\n\n' "$checks" "$skips"
    exit 0
fi

cleanup
mkdir -p "$MAIN"
cp -R "$FIXTURE/." "$MAIN/"

# The repository the other floors are not: it defines the lifecycle pair, so
# rung 1 answers and the pair never reaches the copy road at all.
cat > "$MAIN/scripts/db-create-postgres" <<'SH'
#!/bin/sh
# Creates the namespace it is given, templated from the base so the overlay
# gets the shape AND the contents. An empty namespace is a different thing
# from a copy, and a feature that reads what the base stack loaded cannot be
# exercised in one.
set -eu
ident=${1:?usage: db-create-postgres <ident>}
exec docker exec "$SG_INSTANCE" psql -U shop -d postgres -v ON_ERROR_STOP=1 \
    -c "CREATE DATABASE \"$ident\" TEMPLATE shop"
SH
cat > "$MAIN/scripts/db-drop-postgres" <<'SH'
#!/bin/sh
# Removes that same namespace, by the name the family generated and no other.
set -eu
ident=${1:?usage: db-drop-postgres <ident>}
exec docker exec "$SG_INSTANCE" psql -U shop -d postgres -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE \"$ident\""
SH
chmod +x "$MAIN/scripts/db-create-postgres" "$MAIN/scripts/db-drop-postgres"

(
    cd "$MAIN" || exit 1
    git init -q -b main && git add -A
    git -c user.email=f@e.com -c user.name=f commit -qm base
) >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b feat/discount "$TREE" >/dev/null 2>&1
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

lifecycle=$(for n in db-create-postgres db-drop-postgres db-read-postgres; do [ -x "$MAIN/scripts/$n" ] && printf 'x'; done | wc -c | tr -d ' ')
[ "$lifecycle" = 3 ] \
    && ok 'the repository defines a create, a drop and a read, so rung 1 answers and this pair never reaches the copy road' \
    || fail "the lifecycle family is incomplete here ($lifecycle of 3), which is the other floors' case and not this one"

docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --wait >/dev/null 2>&1 \
    && ok 'the base stack is up' || { fail 'the base stack did not come up'; exit 1; }

BASE=$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" ps -q postgres)
IMAGE=$(docker inspect -f '{{.Config.Image}}' "$BASE")
NETWORK=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$BASE")
export SG_INSTANCE="$BASE"

VOLS_BEFORE=$(docker volume ls --format '{{.Name}}' | sort)
CONTAINERS_BEFORE=$(docker ps -aq | sort)

# --- the destructive-verb class, judged before the drop is ever run ---------

drop_line=$(awk '/DROP DATABASE/ { print; exit }' "$MAIN/scripts/db-drop-postgres")
case "$drop_line" in
    *'$ident'*) ok 'the drop removes only the namespace it is handed, never a literal and never the base one' ;;
    *) fail "the drop names something other than its argument: $drop_line" ;;
esac
case "$drop_line" in
    *'DROP DATABASE "shop"'*|*'DROP DATABASE shop'*) fail 'the drop names the base namespace, which is the destructive verb this class exists to catch' ;;
    *) ok 'and it does not name the base namespace, which no argument could make safe' ;;
esac

# --- the create, and the claim that gives this road its name ----------------

if sh "$MAIN/scripts/db-create-postgres" "$IDENT" >/dev/null 2>&1; then
    ok "the create makes a namespace inside the instance already running: $IDENT"
else
    fail 'the create did not run'
fi

VOLS_AFTER=$(docker volume ls --format '{{.Name}}' | sort)
CONTAINERS_AFTER=$(docker ps -aq | sort)
[ "$VOLS_BEFORE" = "$VOLS_AFTER" ] \
    && ok 'ZERO DISK: no volume was created, which is the whole of what this road buys over a seeded copy' \
    || fail 'the in-instance road created a volume, so it is a copy wearing another name'
[ "$CONTAINERS_BEFORE" = "$CONTAINERS_AFTER" ] \
    && ok 'and no second container: the store process is reused and only the namespace is new' \
    || fail 'the in-instance road started a container'

ns_tables=$(docker exec "$BASE" psql -U shop -d "$IDENT" -tAc \
    "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')" 2>/dev/null)
ns_rows=$(docker exec "$BASE" psql -U shop -d "$IDENT" -tAc 'SELECT count(*) FROM products' 2>/dev/null)
[ "$ns_tables" = 2 ] && [ "$ns_rows" = 5 ] \
    && ok "the namespace carries the base's shape AND its contents ($ns_tables tables, $ns_rows rows), because this repository's create templates from it" \
    || fail "the namespace does not carry the base state: $ns_tables tables, $ns_rows rows"

# --- the overlay, wired to the namespace rather than to a copy --------------

PORT=$(sh "$SCRIPTS/pick-port.sh" 18400 18499 "$TREE" 13306 15432 16379 17017 18080 2>/dev/null)
docker run -d --name sg-zerodisk-overlay --network "$NETWORK" \
    --label "stackgraft.labels=1" --label "stackgraft.repo=zerodisk" \
    --label "stackgraft.worktree=$TREE" --label "stackgraft.service=catalog-api" \
    --label "stackgraft.port=$PORT" \
    --env "DATABASE_URL=postgres://shop:shop@postgres:5432/$IDENT" \
    -v "$TREE/services/catalog-api":/app:ro -v "$TREE/db/migrations":/db/migrations:ro \
    -p "127.0.0.1:$PORT:8080" "$IMAGE" sh /app/serve.sh >/dev/null 2>&1 \
    && ok "the overlay launches on $PORT, pointed at the namespace inside the base instance" \
    || fail 'the overlay did not launch'

_n=0
while [ "$_n" -lt 30 ]; do
    BODY=$(curl -s "http://127.0.0.1:$PORT/products" 2>/dev/null)
    [ -n "$BODY" ] && break
    _n=$((_n + 1)); sleep 1
done
printf '        %s\n' "${BODY:-unreachable}"
case "${BODY:-}" in
    *'"discounted":1'*) ok 'it serves its own migration, applied to the namespace and read back from it' ;;
    *) fail "the overlay did not serve its change: ${BODY:-unreachable}" ;;
esac

base_col=$(docker exec "$BASE" psql -U shop -d shop -tAc \
    "SELECT count(*) FROM information_schema.columns WHERE table_name='products' AND column_name='discount_cents'" 2>/dev/null)
[ "$base_col" = 0 ] \
    && ok 'and the base namespace in the same instance never saw it: same server process, different database, zero new columns' \
    || fail "the base namespace took the migration: $base_col new column(s)"

# --- the per-substrate catch this road carries, exercised --------------------
# references/shared-state.md, PostgreSQL: "TEMPLATE needs no active connections
# to the source". It held above only because this service's connections are
# transient. A held connection is the ordinary way it does not.

docker run -d --name sg-zerodisk-holder --network "$NETWORK" "$IMAGE" \
    psql "postgres://shop:shop@postgres:5432/shop" -c 'SELECT pg_sleep(60)' >/dev/null 2>&1
_n=0
while [ "$_n" -lt 20 ]; do
    held=$(docker exec "$BASE" psql -U shop -d postgres -tAc \
        "SELECT count(*) FROM pg_stat_activity WHERE datname='shop'" 2>/dev/null)
    [ "${held:-0}" -gt 0 ] && break
    _n=$((_n + 1)); sleep 1
done
if sh "$MAIN/scripts/db-create-postgres" "${IDENT}_2" >/dev/null 2>&1; then
    fail 'templating succeeded with a connection held open, so the documented PostgreSQL catch rests on nothing'
    docker exec "$BASE" psql -U shop -d postgres -c "DROP DATABASE ${IDENT}_2" >/dev/null 2>&1
else
    ok 'the documented PostgreSQL catch is real: with a connection held to the source, templating refuses -- which is why this road is the optimisation and the copy is the default'
fi
docker rm -fv sg-zerodisk-holder >/dev/null 2>&1

# --- the drop, and what survives it -----------------------------------------

docker rm -fv sg-zerodisk-overlay >/dev/null 2>&1
if sh "$MAIN/scripts/db-drop-postgres" "$IDENT" >/dev/null 2>&1; then
    ok 'the drop removes the namespace it created'
else
    fail 'the drop did not run'
fi
gone=$(docker exec "$BASE" psql -U shop -d postgres -tAc \
    "SELECT count(*) FROM pg_database WHERE datname='$IDENT'" 2>/dev/null)
base_rows=$(docker exec "$BASE" psql -U shop -d shop -tAc 'SELECT count(*) FROM products' 2>/dev/null)
[ "$gone" = 0 ] && [ "$base_rows" = 5 ] \
    && ok 'and the base namespace is untouched by the teardown: the namespace is gone, the five rows are not' \
    || fail "teardown left the wrong state: namespace present=$gone, base rows=$base_rows"

VOLS_END=$(docker volume ls --format '{{.Name}}' | sort)
[ "$VOLS_BEFORE" = "$VOLS_END" ] \
    && ok 'the volume inventory is identical from before the create to after the drop' \
    || fail 'the run left volumes behind'

cleanup
printf '\nresult\n'
if [ "$failures" -eq 0 ]; then
    printf '  %s check(s) ran and passed; %s skipped\n\n' "$checks" "$skips"
    exit 0
fi
printf '  %s check(s) ran; %s failed; %s skipped\n\n' "$checks" "$failures" "$skips"
exit 1
