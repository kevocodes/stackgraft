#!/bin/sh
# The sixth floor: two worktrees at once, which is the claim this skill is named
# for and the one a user notices first if it is broken.
#
# "One host, one base stack, N worktrees" is the scope the README states, and
# every other floor here runs exactly one. The differentiating case is two
# features touching the SAME service: a bind-mount slot is single-occupancy, so
# the simple alternatives serialise, and this is where a copy per worktree is
# worth what it costs.
#
# What it has to prove is narrow and mostly about isolation between the two,
# not between either and the base:
#   - two overlays on different ports, neither handed the other's,
#   - a distinct copy per worktree, each carrying the base's state,
#   - each overlay reading ITS OWN copy -- proven by a column that exists in
#     one worktree's migration and not the other's, in both directions,
#   - the base store carrying neither change,
#   - and destroy for one worktree leaving the other's copy alone, which is the
#     provider's worktree-equality guard and the one thing here that, if wrong,
#     destroys work nobody can recover.
#
# usage: sh .github/scripts/integration-parallel.sh
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
WORK="$REPO/.sg-work-parallel"
MAIN="$WORK/shopdemo"
TREE_A="$WORK/shopdemo-worktrees/discount"
TREE_B="$WORK/shopdemo-worktrees/stock"
PROJECT=sg-parallel-shopdemo
STORE=postgres

cleanup() {
    for n in sg-parallel-overlay-a sg-parallel-overlay-b; do
        docker rm -fv "$n" >/dev/null 2>&1 || true
    done
    if [ -d "$MAIN" ]; then
        for t in "$TREE_A" "$TREE_B"; do
            sh "$SCRIPTS/provider-docker.sh" destroy "${HASH:-00000000}" "$t" "$STORE" >/dev/null 2>&1
        done
        docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" down -v >/dev/null 2>&1
    fi
    rm -rf "$WORK"
    rm -f /tmp/sg-par-* 2>/dev/null
    return 0
}
trap cleanup EXIT INT TERM

printf '\ntwo worktrees at once\n\n'

if ! docker info >/dev/null 2>&1; then
    skip 'no container runtime, so the parallel case is unexercised'
    if [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ]; then
        printf '\n  a runtime was required and none answered\n\n'
        exit 1
    fi
    printf '\n  %s check(s) ran, %s skipped\n\n' "$checks" "$skips"
    exit 0
fi

cleanup
INVENTORY_BEFORE=$(docker volume ls --format '{{.Name}}' | sort)

mkdir -p "$MAIN"
cp -R "$FIXTURE/." "$MAIN/"
(
    cd "$MAIN" || exit 1
    git init -q -b main && git add -A
    git -c user.email=f@e.com -c user.name=f commit -qm base
) >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b feat/discount "$TREE_A" >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b feat/stock    "$TREE_B" >/dev/null 2>&1

HASH=$(printf '%s' "$(CDPATH= cd -- "$MAIN" && CDPATH= cd -- "$(git rev-parse --git-common-dir)" && pwd -P)" \
    | git hash-object --stdin | cut -c1-8)

[ -d "$TREE_A" ] && [ -d "$TREE_B" ] \
    && ok "two worktrees exist off one repository, sharing one git common dir and therefore one manifest key ($HASH)" \
    || { fail 'the two worktrees were not created'; exit 1; }

# Two DIFFERENT changes to the SAME service. Each adds a column the other does
# not, so a response naming one and not the other is proof of which copy was
# read -- in both directions, which no single-worktree floor can establish.
mk_change() {
    _tree=$1; _col=$2; _field=$3
    mkdir -p "$_tree/db/migrations"
    printf 'ALTER TABLE products ADD COLUMN %s integer NOT NULL DEFAULT 0;\nUPDATE products SET %s = 7 WHERE sku = %s;\n' \
        "$_col" "$_col" "'SKU-001'" > "$_tree/db/migrations/001_$_col.sql"
    python3 - "$_tree/services/catalog-api/handle.sh" "$_col" "$_field" <<'PY'
import sys, pathlib
p, col, field = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
s = s.replace(
    """body=$(printf '{"service":"catalog-api","path":"%s","products":%s}' "$path" "$products")""",
    """%s=$(psql "$DATABASE_URL" -tAc 'SELECT count(*) FROM products WHERE %s > 0' 2>/dev/null || printf 'unavailable')
body=$(printf '{"service":"catalog-api","path":"%%s","products":%%s,"%s":%%s}' "$path" "$products" "$%s")""" % (field, col, field, field))
p.write_text(s)
PY
}
mk_change "$TREE_A" discount_cents discounted
mk_change "$TREE_B" stock_units    stocked

docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --wait >/dev/null 2>&1 \
    && ok 'the base stack is up, and it is the only one: neither worktree brings up a second' \
    || { fail 'the base stack did not come up'; exit 1; }

BASE=$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" ps -q "$STORE")
IMAGE=$(docker inspect -f '{{.Config.Image}}' "$BASE")
SRCVOL=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}|{{.Destination}}{{"\n"}}{{end}}{{end}}' "$BASE" \
    | awk -F'|' 'NF && $1 !~ /^[0-9a-f]{64}$/ { print $1; exit }')
NETWORK=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$BASE")
BASE_PORTS=$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" ps --format json 2>/dev/null \
    | python3 -c 'import json,sys; print(" ".join(sorted({str(p["PublishedPort"]) for l in sys.stdin for p in (json.loads(l).get("Publishers") or []) if p.get("PublishedPort")})))' 2>/dev/null)

# --- a copy per worktree, through the shipped provider ----------------------

provision() {
    sh "$SCRIPTS/provider-docker.sh" provision "$HASH" "$1" "$STORE" "$SRCVOL" "$IMAGE" "$BASE" \
        "stackgraft.labels=1" "stackgraft.repo=$HASH" "stackgraft.worktree=$1" "stackgraft.store=$STORE" 2>/dev/null
}
provision "$TREE_A" > /tmp/sg-par-a
provision "$TREE_B" > /tmp/sg-par-b
COPY_A=$(awk -F'\t' '$1=="instance"{print $2}' /tmp/sg-par-a)
COPY_B=$(awk -F'\t' '$1=="instance"{print $2}' /tmp/sg-par-b)

if [ -n "$COPY_A" ] && [ -n "$COPY_B" ] && [ "$COPY_A" != "$COPY_B" ]; then
    ok "each worktree gets its own copy, named apart by the worktree rather than by the store alone: $COPY_A / $COPY_B"
else
    fail "the two worktrees did not yield two distinct copies: '$COPY_A' and '$COPY_B'"
fi

for c in "$COPY_A" "$COPY_B"; do
    docker network connect "$NETWORK" "$c" >/dev/null 2>&1 || true
done

wait_readable() {
    _n=0
    while [ "$_n" -lt 40 ]; do
        sh "$FIXTURE/scripts/db-read-$STORE" "$1" >/dev/null 2>&1 && return 0
        _n=$((_n + 1)); sleep 1
    done
    return 1
}
wait_readable "$COPY_A" && wait_readable "$COPY_B" \
    && ok 'both copies answer as stores, and each carries the base state it was taken from' \
    || fail 'a copy never became readable'

# --- a port per worktree, neither handed the other's ------------------------

# shellcheck disable=SC2086
PORT_A=$(sh "$SCRIPTS/pick-port.sh" 18300 18399 "$TREE_A" $BASE_PORTS 2>/dev/null)
# The second pick excludes the first, which is what step 3 feeding step 8 means
# when two worktrees are live at once.
# shellcheck disable=SC2086
PORT_B=$(sh "$SCRIPTS/pick-port.sh" 18300 18399 "$TREE_B" $BASE_PORTS "$PORT_A" 2>/dev/null)
if [ -n "$PORT_A" ] && [ -n "$PORT_B" ] && [ "$PORT_A" != "$PORT_B" ]; then
    ok "each worktree picks its own port and the second is never handed the first: $PORT_A / $PORT_B"
else
    fail "the two picks collided or failed: '$PORT_A' and '$PORT_B'"
fi

launch() {
    _name=$1; _tree=$2; _copy=$3; _port=$4
    docker run -d --name "$_name" --network "$NETWORK" \
        --label "stackgraft.labels=1" --label "stackgraft.repo=$HASH" \
        --label "stackgraft.worktree=$_tree" --label "stackgraft.service=catalog-api" \
        --label "stackgraft.port=$_port" \
        --env "DATABASE_URL=postgres://shop:shop@$_copy:5432/shop" \
        -v "$_tree/services/catalog-api":/app:ro -v "$_tree/db/migrations":/db/migrations:ro \
        -p "127.0.0.1:$_port:8080" "$IMAGE" sh /app/serve.sh >/dev/null 2>&1
}
launch sg-parallel-overlay-a "$TREE_A" "$COPY_A" "$PORT_A" \
    && launch sg-parallel-overlay-b "$TREE_B" "$COPY_B" "$PORT_B" \
    && ok 'both overlays launch, from their own worktrees, against their own copies' \
    || fail 'an overlay did not launch'

ask() {
    _n=0
    while [ "$_n" -lt 30 ]; do
        _r=$(curl -s -H 'Accept: application/json' "http://127.0.0.1:$1/products" 2>/dev/null)
        [ -n "$_r" ] && { printf '%s' "$_r"; return 0; }
        _n=$((_n + 1)); sleep 1
    done
    printf 'unreachable'
}
BODY_A=$(ask "$PORT_A")
BODY_B=$(ask "$PORT_B")
printf '        A=%s\n        B=%s\n' "$BODY_A" "$BODY_B"

# --- the claim: each overlay reads its own data, in both directions ---------

case "$BODY_A" in
    *'"discounted":1'*) case "$BODY_A" in
        *stocked*) fail "worktree A sees worktree B's column, so the two are not isolated: $BODY_A" ;;
        *) ok "worktree A serves its own migration and not the other's: $BODY_A" ;;
    esac ;;
    *) fail "worktree A did not serve its own change: $BODY_A" ;;
esac
case "$BODY_B" in
    *'"stocked":1'*) case "$BODY_B" in
        *discounted*) fail "worktree B sees worktree A's column, so the two are not isolated: $BODY_B" ;;
        *) ok "worktree B serves its own migration and not the other's: $BODY_B" ;;
    esac ;;
    *) fail "worktree B did not serve its own change: $BODY_B" ;;
esac

cols=$(docker exec "$BASE" psql -U shop -d shop -tAc \
    "SELECT count(*) FROM information_schema.columns WHERE table_name = 'products' AND column_name IN ('discount_cents','stock_units')" 2>/dev/null)
[ "$cols" = 0 ] \
    && ok 'the base store carries neither change: two worktrees migrated, and zero of it landed on the shared data' \
    || fail "the base store took $cols column(s) from the worktrees"

# --- destroying one worktree's copy leaves the other's alone ----------------
# The guard that matters most here: an object is removed only where its
# recorded worktree label EQUALS the worktree argument. If that is ever a
# prefix or a substring, one worktree's teardown eats another's data, and a
# copy is the one thing on this host nothing can reproduce.

# First the falsifier, because a guard that cannot be shown to hold is a
# comment. The directory both worktrees sit under is a PREFIX of both paths and
# equal to neither: a matcher that accepted prefixes would take both copies on
# this call, which is the shape of the accident this guard exists to prevent.
PARENT=$(dirname "$TREE_A")
sh "$SCRIPTS/provider-docker.sh" destroy "$HASH" "$PARENT" "$STORE" >/dev/null 2>&1
survived=$(docker ps -a --filter "name=^${COPY_A}$" --filter "name=^${COPY_B}$" --format '{{.Names}}' | wc -l | tr -d ' ')
[ "$survived" = 2 ] \
    && ok 'a worktree argument that is a prefix of both worktrees and equal to neither removes nothing' \
    || fail "a prefix of both worktree paths removed $((2 - survived)) copy(ies): the label is being matched by prefix, and one worktree's teardown can eat another's data"

sh "$SCRIPTS/provider-docker.sh" destroy "$HASH" "$TREE_A" "$STORE" >/dev/null 2>&1
gone_a=$(docker ps -a --filter "name=^${COPY_A}$" --format '{{.Names}}' | wc -l | tr -d ' ')
kept_b=$(docker ps -a --filter "name=^${COPY_B}$" --format '{{.Names}}' | wc -l | tr -d ' ')
[ "$gone_a" = 0 ] \
    && ok "destroying worktree A's copy removed it" \
    || fail "worktree A's copy survived its own destroy"
[ "$kept_b" = 1 ] \
    && ok "and left worktree B's copy alone -- the worktree label is matched by equality, not by prefix" \
    || fail "destroying worktree A's copy also took worktree B's, which is unrecoverable data loss"

still=$(sh "$FIXTURE/scripts/db-read-$STORE" "$COPY_B" 2>/dev/null)
[ -n "$still" ] && [ "$still" != 0 ] \
    && ok "worktree B's copy still answers with its state after the other was destroyed: $still" \
    || fail "worktree B's copy stopped answering after worktree A was destroyed: '$still'"

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
