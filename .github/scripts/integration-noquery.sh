#!/bin/sh
# The tenth floor: what a real first run actually gets.
#
# Every copy-road floor here is handed a rung-2 source, because the fixture ships
# a db-read-<store> per store. A real repository ships none -- that is the
# measured case this skill was built for, where zero of four stores supply a
# rung-1 candidate either -- so the outcome most repositories meet on their first
# run had never been driven: the bytes are copied, no query can be derived for
# them, the copy is destroyed, and the pair refuses.
#
# That is the documented behaviour and it is the expensive one. It copies
# gigabytes and then refuses, which a developer will read as a bug unless the run
# says why. Nothing had ever checked that it happens at all.
#
# usage: sh .github/scripts/integration-noquery.sh
set -u

checks=0
failures=0
ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }

REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
FIXTURE="$REPO/.github/fixtures/shopdemo"
SCRIPTS="$REPO/skills/stackgraft/scripts"
WORK="$REPO/.sg-work-noquery"
MAIN="$WORK/shopdemo"
TREE="$WORK/shopdemo-worktrees/discount"
PROJECT=sg-noquery-shopdemo
STORE=postgres

cleanup() {
    [ -n "${HASH:-}" ] && [ -d "$MAIN" ] && \
        sh "$SCRIPTS/provider-docker.sh" destroy "$HASH" "$TREE" "$STORE" >/dev/null 2>&1
    [ -d "$MAIN" ] && docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" down -v >/dev/null 2>&1
    rm -rf "$WORK"
    return 0
}
trap cleanup EXIT INT TERM

printf '\nno query: what a real first run gets\n\n'

if ! docker info >/dev/null 2>&1; then
    printf '  skip  no container runtime\n'
    [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ] && exit 1
    exit 0
fi

cleanup
INVENTORY_BEFORE=$(docker volume ls --format '{{.Name}}' | sort)

mkdir -p "$MAIN"
cp -R "$FIXTURE/." "$MAIN/"
# The repository a real developer has: no lifecycle family, and therefore no
# read to verify a copy with.
rm -f "$MAIN"/scripts/db-read-*
( cd "$MAIN" && git init -q -b main && git add -A \
  && git -c user.email=f@e.com -c user.name=f commit -qm base ) >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b feat/discount "$TREE" >/dev/null 2>&1
HASH=$(printf '%s' "$(CDPATH= cd -- "$MAIN" && CDPATH= cd -- "$(git rev-parse --git-common-dir)" && pwd -P)" \
    | git hash-object --stdin | cut -c1-8)

docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --wait >/dev/null 2>&1 \
    && ok 'the base stack is up' || { fail 'the base stack did not come up'; exit 1; }
BASE=$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" ps -q "$STORE")
IMAGE=$(docker inspect -f '{{.Config.Image}}' "$BASE")
SRCVOL=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}|{{.Destination}}{{"\n"}}{{end}}{{end}}' "$BASE" \
    | awk -F'|' 'NF && $1 !~ /^[0-9a-f]{64}$/ { print $1; exit }')

# --- neither rung answers, and both for their own stated reason --------------

hc=$(docker inspect -f '{{json .Config.Healthcheck.Test}}' "$BASE" 2>/dev/null)
case "$hc" in
    *CMD-SHELL*) ok 'rung 1 is empty: the store declares a CMD-SHELL healthcheck, which is shell source and the argv rule excludes before anything else is asked' ;;
    *) fail "the store's healthcheck is not the shape this floor needs: $hc" ;;
esac
reads=$(ls "$MAIN"/scripts/db-read-* 2>/dev/null | wc -l | tr -d ' ')
targets=$(ls "$MAIN"/Makefile "$MAIN"/Taskfile.yml "$MAIN"/justfile "$MAIN"/package.json 2>/dev/null | wc -l | tr -d ' ')
[ "$reads" = 0 ] && [ "$targets" = 0 ] \
    && ok 'rung 2 is empty too: the repository defines no lifecycle family and no build file that could hold one' \
    || fail "this repository is not the no-query case: $reads read(s), $targets build file(s)"

# --- the bytes are copied anyway, which is the expensive part ----------------

if sh "$SCRIPTS/provider-docker.sh" provision "$HASH" "$TREE" "$STORE" \
        "$SRCVOL" "$IMAGE" "$BASE" \
        'stackgraft.labels=1' "stackgraft.repo=$HASH" \
        "stackgraft.worktree=$TREE" "stackgraft.store=$STORE" > "$WORK/prov" 2>/dev/null; then
    bytes=$(awk -F'\t' '$1=="bytes"{print $2}' "$WORK/prov")
    ok "the copy is provisioned before the query is known -- $bytes bytes, spent on a pair that is about to refuse"
else
    fail "the provider could not provision: $(head -2 "$WORK/prov" | tr '\n' ' ')"
fi
COPY=$(awk -F'\t' '$1=="instance"{print $2}' "$WORK/prov")
VOL=$(awk -F'\t' '$1=="volume"{print $2}' "$WORK/prov")
[ -n "$COPY" ] && [ -n "$VOL" ] \
    && ok "and both objects are named, so what is about to be removed is not a guess: $COPY" \
    || fail 'the provider named no instance or volume'

# --- with no query, the copy is destroyed and the pair refuses ---------------
# The refusal direction is the whole point: a copy that cannot be verified is
# never wired to the base store instead, and it is never left behind either.

sh "$SCRIPTS/provider-docker.sh" destroy "$HASH" "$TREE" "$STORE" >/dev/null 2>&1
gone_i=$(docker ps -a --filter "name=^${COPY}$" --format '{{.Names}}' | wc -l | tr -d ' ')
gone_v=$(docker volume inspect "$VOL" >/dev/null 2>&1 && printf 1 || printf 0)
[ "$gone_i" = 0 ] && [ "$gone_v" = 0 ] \
    && ok 'the unverifiable copy is destroyed, instance and volume both, read back rather than claimed' \
    || fail "the refused copy survived: instance=$gone_i volume=$gone_v"

base_tables=$(docker exec "$BASE" psql -U shop -d shop -tAc \
    "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')" 2>/dev/null)
[ "$base_tables" = 2 ] \
    && ok 'and the base store was never wired to instead: it still holds exactly what it held, and no overlay ever reached it' \
    || fail "the base store moved: $base_tables tables"

# --- and the offer is the way out, named in the directory that exists --------

[ -d "$MAIN/scripts" ] \
    && ok 'the repository has an existing script directory, so the three files the run offers have a home it did not invent' \
    || fail 'no existing script directory, and inventing one is what the offer may not do'
for n in db-create-$STORE db-drop-$STORE db-read-$STORE; do
    [ -e "$MAIN/scripts/$n" ] && fail "the offer's target $n already exists, so this is not the case the offer answers"
done
ok 'and none of the three names is taken, so the offer is reachable rather than withdrawn -- which is the way out of this refusal'

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
