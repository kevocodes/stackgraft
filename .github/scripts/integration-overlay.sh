#!/bin/sh
# The second floor: the overlay run, end to end, on a real repository.
#
# `integration.sh` proves the provider road -- a copy of a real store, verified
# against an empty instance. That is one segment of ten steps. Nobody installs
# this skill to obtain a verified copy; they install it so the service they
# changed runs on another port, against its own data, and answers. That run had
# never completed once, so this file drives it:
#
#   a real git repository, a real worktree with a real change, the skill's own
#   pick-port.sh, an overlay launched from the worktree's code and wired to the
#   copy rather than to the base store, a migration applied through it, one
#   verification request carrying headers -- and then the claim that matters,
#   which is that the base store is provably untouched.
#
# usage: sh .github/scripts/integration-overlay.sh
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

# Never under /tmp or /var/tmp: the skill carries a hard rule against placing a
# worktree there because both are reaped, and a test that broke that rule would
# be exercising something the skill forbids.
WORK="$REPO/.sg-work"
MAIN="$WORK/shopdemo"
TREE="$WORK/shopdemo-worktrees/discount-column"

PROJECT=sg-overlay-shopdemo
STORE=postgres
COPY_NAME="sg-overlay-copy-$STORE"
COPY_VOLUME="sg-overlay-copyvol-$STORE"
OVERLAY_NAME="sg-overlay-catalog-api"

cleanup() {
    docker rm -fv "$OVERLAY_NAME" "$COPY_NAME" >/dev/null 2>&1 || true
    docker volume rm -f "$COPY_VOLUME" >/dev/null 2>&1 || true
    [ -d "$MAIN" ] && docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" down -v >/dev/null 2>&1
    rm -rf "$WORK"
    [ -n "${ENV_FILE:-}" ] && rm -f "$ENV_FILE"
    return 0
}
trap cleanup EXIT INT TERM

printf '\nthe overlay run against a real repository\n\n'

if ! docker info >/dev/null 2>&1; then
    skip 'no container runtime, so the whole run is unexercised'
    if [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ]; then
        printf '\n  a runtime was required and none answered\n\n'
        exit 1
    fi
    printf '\n  %s check(s) ran, %s skipped\n\n' "$checks" "$skips"
    exit 0
fi

cleanup
INVENTORY_BEFORE=$(docker volume ls --format '{{.Name}}' | sort)

# --- a real repository, and a real worktree off it ---------------------------

mkdir -p "$MAIN"
cp -R "$FIXTURE/." "$MAIN/"
(
    cd "$MAIN" || exit 1
    git init -q -b main
    git add -A
    git -c user.email=fixture@example.com -c user.name=fixture commit -qm 'the shopdemo base stack'
) >/dev/null 2>&1

if git -C "$MAIN" rev-parse --git-dir >/dev/null 2>&1; then
    ok 'the fixture is materialised as a real git repository'
else
    fail 'the fixture repository could not be created'
    exit 1
fi

git -C "$MAIN" worktree add -q -b feat/discount-column "$TREE" >/dev/null 2>&1
if [ -d "$TREE" ]; then
    ok 'a worktree is created off it, outside /tmp as the skill requires'
else
    fail 'the worktree was not created'
    exit 1
fi

# The change: a migration the base store must never see, and the service code
# that reads what the migration adds.
mkdir -p "$TREE/db/migrations"
printf 'ALTER TABLE products ADD COLUMN discount_cents integer NOT NULL DEFAULT 0;\nUPDATE products SET discount_cents = 500 WHERE sku = %s;\n' "'SKU-001'" \
    > "$TREE/db/migrations/001_add_discount.sql"
awk '
    /^products=/ {
        print
        print "discounted=$(psql \"$DATABASE_URL\" -tAc '"'"'SELECT count(*) FROM products WHERE discount_cents > 0'"'"' 2>/dev/null || printf unavailable)"
        next
    }
    /^body=\$\(printf/ {
        print "body=$(printf '"'"'{\"service\":\"catalog-api\",\"path\":\"%s\",\"products\":%s,\"discounted\":%s}'"'"' \"$path\" \"$products\" \"$discounted\")"
        next
    }
    { print }
' "$TREE/services/catalog-api/handle.sh" > "$TREE/services/catalog-api/handle.sh.new"
mv "$TREE/services/catalog-api/handle.sh.new" "$TREE/services/catalog-api/handle.sh"
chmod +x "$TREE/services/catalog-api/handle.sh"

changed=$(git -C "$TREE" status --porcelain --untracked-files=all | awk '{print $2}' | sort | tr '\n' ' ')
case "$changed" in
    *db/migrations/*|*services/catalog-api/*)
        ok "the worktree diff touches a migrations directory and the service's own tree: $changed" ;;
    *)
        fail "the worktree diff is not the subject this run needs: $changed" ;;
esac

# --- the base stack ----------------------------------------------------------

if docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --wait >/dev/null 2>&1; then
    ok 'the base stack is up, with the store holding the seeded state'
else
    fail 'the base stack did not come up'
    exit 1
fi

BASE=$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" ps -q "$STORE")
IMAGE=$(docker inspect -f '{{.Config.Image}}' "$BASE")
MOUNT=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Destination}}{{end}}{{end}}' "$BASE")
SOURCE_VOLUME=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' "$BASE")
NETWORK=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$BASE")

[ -n "$NETWORK" ] \
    && ok "the network the base stack sits on is read back: $NETWORK" \
    || fail 'the network could not be read back'

ENV_FILE=$(mktemp)
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$BASE" \
    | awk '!/^(PATH|HOSTNAME|HOME|TERM|PG_VERSION|PGDATA|GOSU_VERSION|LANG|PG_MAJOR|PG_SHA256)=/ && NF' > "$ENV_FILE"

# --- the copy, on the base stack's own network so an overlay can reach it ----

docker volume create "$COPY_VOLUME" >/dev/null 2>&1
docker run --rm -v "$SOURCE_VOLUME":/from:ro -v "$COPY_VOLUME":/to "$IMAGE" \
    sh -c 'cd /from && tar cf - . | (cd /to && tar xf -)' >/dev/null 2>&1

if docker run -d --name "$COPY_NAME" --network "$NETWORK" \
        --label "stackgraft.repo=sgoverlay" --label "stackgraft.worktree=discount-column" \
        --label "stackgraft.store=$STORE" --label "stackgraft.kind=copy" \
        --env-file "$ENV_FILE" -v "$COPY_VOLUME":"$MOUNT" "$IMAGE" >/dev/null 2>&1; then
    ok 'the copy is started on the base stack network, reachable by name from an overlay'
else
    fail 'the copy did not start'
fi

wait_ready() {
    _n=0
    while [ "$_n" -lt 40 ]; do
        docker exec "$1" pg_isready -U shop -d shop >/dev/null 2>&1 && return 0
        _n=$((_n + 1))
        sleep 1
    done
    return 1
}
wait_ready "$COPY_NAME" && ok 'the copy answers as a store' || fail 'the copy never became ready'

# --- the port, picked by the skill's own script ------------------------------

# The base stack publishes 18080, which sits inside the range asked for here.
# Step 3 of the skill excludes this repository's held ports before step 8 picks
# one, and each exclusion is its own argument -- "15432,18080" is a single
# argument that is not a port and is rejected by name rather than split.
BASE_PORTS=$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" ps --format json 2>/dev/null \
    | python3 -c 'import json,sys; print(" ".join(sorted({str(p["PublishedPort"]) for l in sys.stdin for p in (json.loads(l).get("Publishers") or []) if p.get("PublishedPort")})))' 2>/dev/null)
# shellcheck disable=SC2086
PORT=$(sh "$SCRIPTS/pick-port.sh" 18000 18200 "$TREE" $BASE_PORTS 2>/dev/null)
case "$PORT" in
    ''|*[!0-9]*) fail "pick-port.sh did not yield an integer: '$PORT'" ;;
    *)
        if [ "$PORT" -ge 18000 ] && [ "$PORT" -le 18200 ]; then
            ok "pick-port.sh yields a candidate inside the requested range: $PORT"
        else
            fail "pick-port.sh yielded $PORT, outside 18000-18200"
        fi
        case " $BASE_PORTS " in
            *" $PORT "*) fail "pick-port.sh yielded $PORT, which the base stack publishes" ;;
            *) ok "the candidate avoids every port the base stack holds: excluded $BASE_PORTS" ;;
        esac
        ;;
esac

# --- nothing here applies the migration, and that is the repair -------------
# An earlier version of this file ran the migration itself, with a psql command
# it composed -- which is the one thing `references/discovery.md` forbids
# outright: an overlay's road is derived from the repository or it is not taken.
# A floor that invents the step proves a road nobody has.
#
# The unit migrates from its own entrypoint instead, which is the ordinary
# shape and the one the gate's `migrates` escalation exists for. So the
# migration reaches the copy because the overlay was launched against the copy,
# and for no other reason. Nothing below runs it.

case $(awk '/migrations/ { m = 1 } /psql/ { p = 1 } END { print (m && p) ? "runs" : "no" }' \
        "$TREE/services/catalog-api/serve.sh") in
    runs) ok 'the unit applies its own migrations on startup, so the run needs no route of its own and invents none' ;;
    *)    fail 'the unit no longer migrates from its entrypoint, so this floor is back to proving a road nobody has' ;;
esac

# --- the overlay: the worktree's code, the picked port, wired to the copy ----

if docker run -d --name "$OVERLAY_NAME" --network "$NETWORK" \
        --label "stackgraft.repo=sgoverlay" --label "stackgraft.worktree=discount-column" \
        --label "stackgraft.service=catalog-api" --label "stackgraft.port=$PORT" \
        --label "stackgraft.kind=overlay" \
        --env "DATABASE_URL=postgres://shop:shop@$COPY_NAME:5432/shop" \
        -v "$TREE/services/catalog-api":/app:ro \
        -v "$TREE/db":/db:ro \
        -p "127.0.0.1:$PORT:8080" \
        "$IMAGE" sh /app/serve.sh >/dev/null 2>&1; then
    ok "the overlay launches from the worktree's own code, bound strictly to 127.0.0.1:$PORT"
else
    fail 'the overlay did not launch'
fi

# --- verified with a real request, never /health ----------------------------

response=''
_n=0
while [ "$_n" -lt 30 ]; do
    response=$(curl -s -i -H 'Accept: application/json' -H 'X-Request-Id: sg-integration' \
        "http://127.0.0.1:$PORT/catalog" 2>/dev/null) && [ -n "$response" ] && break
    _n=$((_n + 1))
    sleep 1
done

status=$(printf '%s' "$response" | awk 'NR==1{print $2}')
body=$(printf '%s' "$response" | awk 'f{print} /^\r?$/{f=1}' | tr -d '\r')

if [ "$status" = 200 ]; then
    ok "the overlay answers a real request carrying headers: $status"
else
    fail "the overlay did not answer 200 on a real request: '$status'"
fi

case "$body" in
    *'"discounted":1'*)
        ok "the response proves it read the migrated copy rather than the base store: $body" ;;
    *)
        fail "the response does not evidence the copy: $body" ;;
esac

# --- the claim the whole skill exists for -----------------------------------

base_cols=$(docker exec "$BASE" psql -U shop -d shop -tAc \
    "SELECT count(*) FROM information_schema.columns WHERE table_name = 'products' AND column_name = 'discount_cents'" 2>/dev/null)
if [ "$base_cols" = 0 ]; then
    ok 'the base store never saw the migration: zero new columns on products'
else
    fail "the base store was written to: $base_cols new column(s) on products"
fi

base_products=$(docker exec "$BASE" psql -U shop -d shop -tAc 'SELECT count(*) FROM products' 2>/dev/null)
[ "$base_products" = 5 ] \
    && ok 'the base store still holds exactly the rows it started with' \
    || fail "the base store's row count moved: $base_products"

# --- the manifest is written through the skill's own lock -------------------

CACHE="$WORK/manifest.json"
PAYLOAD="$WORK/payload.json"
printf '{"schemaVersion":3,"repoRoot":"%s","verifiedOverlays":[{"unit":"catalog-api","port":%s}]}\n' "$MAIN" "$PORT" > "$PAYLOAD"
if sh "$SCRIPTS/with-lock.sh" "$CACHE" "$PAYLOAD" - >/dev/null 2>&1; then
    ok 'the manifest is committed through with-lock.sh with the no-file expectation'
else
    fail 'with-lock.sh refused the first write'
fi

expected=$(git hash-object "$CACHE" 2>/dev/null)
printf '{"schemaVersion":3,"repoRoot":"%s","verifiedOverlays":[]}\n' "$MAIN" > "$PAYLOAD"
if sh "$SCRIPTS/with-lock.sh" "$CACHE" "$PAYLOAD" "$expected" >/dev/null 2>&1; then
    ok 'a second write with the fingerprint the caller read is committed'
else
    fail 'with-lock.sh refused a write carrying the correct expectation'
fi

if sh "$SCRIPTS/with-lock.sh" "$CACHE" "$PAYLOAD" "$expected" >/dev/null 2>&1; then
    fail 'with-lock.sh committed a write whose expectation is stale, so nothing detects a concurrent writer'
else
    ok 'a write carrying a stale fingerprint is refused, which is what makes the cache safe across worktrees'
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
