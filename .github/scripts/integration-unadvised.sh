#!/bin/sh
# The eleventh floor: a store the documents say nothing about.
#
# Four engines run in the other floors, and every one of them has a row in
# shared-state.md's per-substrate table. That proves the procedure holds for
# four. It does not prove what "blind to the substrate" actually claims, which is
# that a store nobody wrote advice for takes the same road as one they did.
#
# This drives the whole copy road for CouchDB. There is not one line about
# CouchDB anywhere in this skill -- no advice row, no name in the provider, no
# port in any table -- so its substrate is undetermined by construction, and
# that has to be a gap in GUIDANCE rather than a gate.
#
# usage: sh .github/scripts/integration-unadvised.sh
set -u

checks=0
failures=0
ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }

REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
SKILL="$REPO/skills/stackgraft"
SCRIPTS="$SKILL/scripts"
WORK="$REPO/.sg-work-unadvised"
MAIN="$WORK/repo"
TREE="$WORK/worktrees/change"
PROJECT=sg-unadvised
STORE=archive
IMAGE=couchdb:3

cleanup() {
    docker rm -fv sg-unadvised-probe sg-unadvised-mute >/dev/null 2>&1 || true
    [ -n "${HASH:-}" ] && [ -d "$MAIN" ] && \
        sh "$SCRIPTS/provider-docker.sh" destroy "$HASH" "$TREE" "$STORE" >/dev/null 2>&1
    [ -d "$MAIN" ] && docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" down -v >/dev/null 2>&1
    rm -rf "$WORK"
    return 0
}
trap cleanup EXIT INT TERM

printf '\na store the documents say nothing about\n\n'

if ! docker info >/dev/null 2>&1; then
    printf '  skip  no container runtime\n'
    [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ] && exit 1
    exit 0
fi

# The premise, asserted rather than assumed: if anybody ever writes advice for
# this engine, this floor stops being about an unadvised one and must be told.
advice=$(grep -ciE 'couchdb' "$SKILL/SKILL.md" "$SKILL"/references/*.md "$SKILL"/assets/*.json "$SCRIPTS"/*.sh 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
[ "$advice" = 0 ] \
    && ok 'this skill contains no mention of this engine: no advice row, no name in the provider, no port in any table' \
    || fail "the skill mentions this engine $advice time(s), so this floor no longer tests an unadvised store"

cleanup
INVENTORY_BEFORE=$(docker volume ls --format '{{.Name}}' | sort)
mkdir -p "$MAIN/scripts"

# A repository with one unadvised store and one unit that reads it.
printf 'name: %s\nservices:\n  %s:\n    image: %s\n    environment:\n      COUCHDB_USER: shop\n      COUCHDB_PASSWORD: shop\n    volumes:\n      - archive_data:/opt/couchdb/data\nvolumes:\n  archive_data:\n' \
    "$PROJECT" "$STORE" "$IMAGE" > "$MAIN/compose.yaml"

# The read the repository supplies. It counts what an instance carries and names
# no database this repository owns, exactly as the contract asks -- and it is the
# ONLY engine-specific thing in this run, which is the point.
# It fails when the instance cannot answer, and only then. That distinction is
# the whole contract: `grep -c` exits 1 on zero matches, so a read that swallows
# every status prints `0` for "empty" AND for "not up yet", and anything waiting
# on it is satisfied by an instance that has not booted. Ask curl first, and let
# its status be the failure; the count is only computed once there is an answer.
cat > "$MAIN/scripts/db-read-$STORE" <<'SH'
#!/bin/sh
set -eu
instance=${1:?usage: db-read-archive <instance>}
exec docker exec "$instance" sh -c '
  dbs=$(curl -sf -u shop:shop http://127.0.0.1:5984/_all_dbs) || exit 1
  printf "%s" "$dbs" | tr "," "\n" | grep -c "\"[^_]" || true'
SH
chmod +x "$MAIN/scripts/db-read-$STORE"

( cd "$MAIN" && git init -q -b main && git add -A \
  && git -c user.email=f@e.com -c user.name=f commit -qm base ) >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b feat/change "$TREE" >/dev/null 2>&1
HASH=$(printf '%s' "$(CDPATH= cd -- "$MAIN" && CDPATH= cd -- "$(git rev-parse --git-common-dir)" && pwd -P)" \
    | git hash-object --stdin | cut -c1-8)

docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --wait >/dev/null 2>&1 \
    || { fail 'the unadvised store did not come up'; exit 1; }
BASE=$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" ps -q "$STORE")
_n=0; while [ "$_n" -lt 60 ]; do
    docker exec "$BASE" curl -s -u shop:shop http://127.0.0.1:5984/ >/dev/null 2>&1 && break
    _n=$((_n + 1)); sleep 1
done
docker exec "$BASE" curl -s -X PUT -u shop:shop http://127.0.0.1:5984/ledger >/dev/null 2>&1
docker exec "$BASE" curl -s -X PUT -u shop:shop http://127.0.0.1:5984/invoices >/dev/null 2>&1
ok 'the base stack runs it and it holds state, which is all the identification rule asks'

# --- identification: by the state, and the substrate stays undetermined ------

ident=$(python3 "$REPO/.github/scripts/lib-storeid.py" "$MAIN/compose.yaml")
by_state=${ident%%|*}; by_name=${ident#*|}
[ "$by_state" = "$STORE" ] \
    && ok "the structural reading finds it: $by_state" \
    || fail "the structural reading missed it: '$by_state'"
[ -z "$by_name" ] \
    && ok 'and a name-matching reading finds nothing, because no word in its image is an engine such a pass knows' \
    || fail "a name-matching reading found '$by_name', so this image is not the unadvised shape"

# --- the copy road, driven by the shipped provider, knowing nothing ----------

SRCVOL=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' "$BASE")
if sh "$SCRIPTS/provider-docker.sh" provision "$HASH" "$TREE" "$STORE" \
        "$SRCVOL" "$IMAGE" "$BASE" \
        'stackgraft.labels=1' "stackgraft.repo=$HASH" \
        "stackgraft.worktree=$TREE" "stackgraft.store=$STORE" > "$WORK/prov" 2>/dev/null; then
    ok "the shipped provider copies it with no idea what it is: $(awk -F'\t' '$1=="bytes"{print $2}' "$WORK/prov") bytes"
else
    fail "the provider refused an engine it has never heard of: $(head -2 "$WORK/prov" | tr '\n' ' ')"
fi
COPY=$(awk -F'\t' '$1=="instance"{print $2}' "$WORK/prov")

READ="$MAIN/scripts/db-read-$STORE"
wait_readable() { _n=0; while [ "$_n" -lt 60 ]; do sh "$1" "$2" >/dev/null 2>&1 && return 0; _n=$((_n+1)); sleep 1; done; return 1; }
ENV_FILE=$(mktemp)
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$BASE" \
    | awk '!/^(PATH|HOSTNAME|HOME|TERM|GOSU_VERSION|LANG)=/ && NF' > "$ENV_FILE"
docker run -d --name sg-unadvised-probe --label "stackgraft.probe=$STORE" \
    --env-file "$ENV_FILE" "$IMAGE" >/dev/null 2>&1
wait_readable "$READ" "$BASE" || true
wait_readable "$READ" sg-unadvised-probe || true
out_base=$(sh "$READ" "$BASE" 2>/dev/null || printf unreadable)
out_probe=$(sh "$READ" sg-unadvised-probe 2>/dev/null || printf unreadable)
# The copy gets the same chance to finish starting that the base had: an answer
# is waited for until it stops changing toward the base's, never sampled at the
# first moment one can be had. A copy that genuinely lost the state converges on
# nothing, times out, and reports the last answer it gave -- so waiting cannot
# turn a wrong answer into a right one, which is the only thing that would matter.
out_copy=unreadable
_n=0; while [ "$_n" -lt 60 ]; do
    out_copy=$(sh "$READ" "$COPY" 2>/dev/null || printf unreadable)
    [ "$out_copy" = "$out_base" ] && break
    _n=$((_n + 1)); sleep 1
done
rm -f "$ENV_FILE"
printf '        base=%s  copy=%s  empty=%s\n' "$out_base" "$out_copy" "$out_probe"

[ "$out_base" != unreadable ] && [ "$out_base" != "$out_probe" ] \
    && ok "the repository's own read discriminates: base '$out_base' against an empty instance '$out_probe'" \
    || fail "the read discriminated nothing: base '$out_base' empty '$out_probe'"
[ "$out_copy" = "$out_base" ] \
    && ok "and the copy carries the base state -- both answer '$out_base', for an engine this skill cannot name" \
    || fail "the copy does not match: copy '$out_copy' against base '$out_base'"

# --- and the read's failure is visible, which the comparison above rests on ---
# The instance that matters here is running but not serving, which is what "has
# not finished starting" actually looks like: the route reaches it, and the store
# behind the route does not answer. An instance that is merely *created* fails at
# the route itself and every shape of read fails with it, so it would prove
# nothing about the shape.

docker run -d --name sg-unadvised-mute --entrypoint sh "$IMAGE" -c 'sleep 300' >/dev/null 2>&1
if sh "$READ" sg-unadvised-mute >/dev/null 2>&1; then
    fail 'the read answered for an instance whose store is not serving, so its failure is invisible'
else
    ok 'the read exits non-zero where the route reaches the instance and the store does not answer'
fi

# The negative control, because the rule is only load-bearing if the shape it
# forbids actually breaks it: the same read written as a counting pipeline that
# swallows its status answers `0` against that same instance -- the value an
# empty store answers -- and nothing downstream could tell the two apart.
cat > "$WORK/db-read-swallowed" <<'SH'
#!/bin/sh
set -eu
exec docker exec "$1" sh -c \
  'curl -s -u shop:shop http://127.0.0.1:5984/_all_dbs | tr "," "\n" | grep -c "\"[^_]" || true'
SH
chmod +x "$WORK/db-read-swallowed"
swallowed=$(sh "$WORK/db-read-swallowed" sg-unadvised-mute 2>/dev/null || printf failed)
[ "$swallowed" = "$out_probe" ] \
    && ok "and the forbidden shape answers '$swallowed' for that same instance -- the value an empty store answers, which is why the rule exists" \
    || fail "the negative control did not reproduce the collision: not-serving '$swallowed' against empty '$out_probe'"
docker rm -fv sg-unadvised-mute >/dev/null 2>&1

sh "$SCRIPTS/provider-docker.sh" destroy "$HASH" "$TREE" "$STORE" >/dev/null 2>&1
docker volume inspect "$(awk -F'\t' '$1=="volume"{print $2}' "$WORK/prov")" >/dev/null 2>&1 \
    && fail 'the copy survived its own destroy' \
    || ok 'and its own destroy removes it, still knowing nothing about the engine'

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
