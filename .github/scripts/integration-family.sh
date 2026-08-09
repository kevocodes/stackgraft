#!/bin/sh
# The fourth floor: the generated lifecycle family, and the two falsifiers that
# stop a file this skill wrote from vouching for itself.
#
# `integration.sh` proves the copy road GIVEN a read command. It was given one
# by hand -- the fixture ships `scripts/db-read-postgres` as though a run had
# already offered it and a human had already approved it. The flow that
# produces that file had no floor at all, and on a repository like the one this
# skill was built for it is not optional: with no rung-1 candidate, without
# that file no copy can ever be certified.
#
# usage: sh .github/scripts/integration-family.sh
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

WORK="$REPO/.sg-work-family"
MAIN="$WORK/shopdemo"
STORE=postgres
PROJECT=sg-family-shopdemo
PROBE_NAME="sg-family-probe-$STORE"

cleanup() {
    docker rm -fv "$PROBE_NAME" >/dev/null 2>&1 || true
    [ -d "$MAIN" ] && docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" down -v >/dev/null 2>&1
    rm -rf "$WORK"
    [ -n "${ENV_FILE:-}" ] && rm -f "$ENV_FILE"
    return 0
}
trap cleanup EXIT INT TERM

printf '\nthe generated lifecycle family\n\n'

if ! docker info >/dev/null 2>&1; then
    skip 'no container runtime, so the discriminator cannot be exercised'
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
(
    cd "$MAIN" || exit 1
    git init -q -b main
    git add -A
    git -c user.email=fixture@example.com -c user.name=fixture commit -qm 'the shopdemo base stack'
) >/dev/null 2>&1

DIR="$MAIN/scripts"
[ -d "$DIR" ] \
    && ok 'the repository already has a script directory, so the family has a home this skill did not invent' \
    || fail 'no existing script directory, and inventing one is exactly what the offer may not do'

# --- the collision rule: an offer is withdrawn, never resolved --------------
# The fixture ships db-read-postgres, so a run offering the family here would
# have to land a generated name on a file somebody else owns. The prohibition
# is not scoped to build files: this is a collision and the whole offer goes.

would_generate() {
    # The three names the family would take, from the discovered store key.
    printf 'db-create-%s\ndb-drop-%s\ndb-read-%s\n' "$STORE" "$STORE" "$STORE"
}

# The fixture ships db-read-postgres, and that file DOES this member's job --
# every row below the discriminator proves it. So it is not a collision: the
# offer completes the family, generating the two nobody wrote and leaving the
# one they did alone. A true collision is a file at a family name that is not a
# working member, and that withdraws the whole offer.

supplied=$(would_generate | while read -r n; do [ -x "$DIR/$n" ] && printf '%s\n' "$n"; done)
missing=$(would_generate | while read -r n; do [ -e "$DIR/$n" ] || printf '%s\n' "$n"; done | tr '\n' ' ')
[ "$supplied" = "db-read-$STORE" ] \
    && ok "the repository already supplies one member and it is executable, so the offer completes the family rather than withdrawing: missing $missing" \
    || fail "the supplied-member case could not be set up: '$supplied'"

# A true collision: something at a family name that is no member at all.
printf 'not a lifecycle target\n' > "$DIR/db-create-$STORE"
chmod -x "$DIR/db-create-$STORE"
[ -e "$DIR/db-create-$STORE" ] && [ ! -x "$DIR/db-create-$STORE" ] \
    && ok 'a file at a family name that is not executable is a collision, and no offer is made from it' \
    || fail 'the collision case could not be set up'
rm -f "$DIR/db-create-$STORE"

before=$(git -C "$MAIN" status --porcelain --untracked-files=all | wc -l | tr -d ' ')
[ "$before" = 0 ] \
    && ok 'and neither case left anything behind: the working tree is exactly as it was' \
    || fail "the offer decision left $before change(s) behind"

# --- now the ordinary case: nothing defines the family ---------------------

# Only the two nobody wrote are generated; the supplied read is untouched.

# What the run would write. Three files, together or not at all. Their contents
# are the repository's business, exactly as a rung-1 target's are; what this
# skill is held to is the recorded command -- one program with arguments -- and
# the rules the drop is judged by.
cat > "$DIR/db-create-$STORE" <<'SH'
#!/bin/sh
# Creates the namespace it is given, reaching the store the way this repository
# already reaches it.
set -eu
ident=${1:?usage: db-create-postgres <ident>}
exec docker exec "$SG_INSTANCE" createdb -U shop "$ident"
SH
cat > "$DIR/db-drop-$STORE" <<'SH'
#!/bin/sh
# Removes that same namespace, by the name the family generated and by no other.
set -eu
ident=${1:?usage: db-drop-postgres <ident>}
exec docker exec "$SG_INSTANCE" dropdb -U shop "$ident"
SH
cat > "$DIR/db-read-$STORE" <<'SH'
#!/bin/sh
# Counts what the instance it is given carries. It names no table this
# repository owns, and an instance holding nothing answers zero.
set -eu
instance=${1:?usage: db-read-postgres <instance>}
exec docker exec "$instance" psql -U shop -d shop -tAc \
    "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema')"
SH
chmod +x "$DIR/db-create-$STORE" "$DIR/db-drop-$STORE" "$DIR/db-read-$STORE"

written=$(would_generate | while read -r n; do [ -x "$DIR/$n" ] && printf 'x'; done | wc -c | tr -d ' ')
[ "$written" = 3 ] \
    && ok 'the family is complete afterwards -- create, drop and read -- two of them generated and one the repository already had' \
    || fail "only $written of the three files exist, and a partial family is not one"

# --- nothing is staged, nothing is committed -------------------------------

staged=$(git -C "$MAIN" diff --cached --name-only | wc -l | tr -d ' ')
untracked=$(git -C "$MAIN" ls-files --others --exclude-standard -- scripts | wc -l | tr -d ' ')
if [ "$staged" = 0 ] && [ "$untracked" = 2 ]; then
    ok "the generated files land in the working tree and nowhere else: $untracked untracked, $staged staged, and the supplied one still tracked"
else
    fail "the run touched the index: $untracked untracked, $staged staged"
fi

for f in Makefile Taskfile.yml justfile package.json; do
    [ -e "$MAIN/$f" ] && fail "the run created $f, and it may never author a build file"
done
ok 'no Makefile, Taskfile.yml, justfile or package.json was appended to or created'

# --- the drop is judged by effect, before it is shown ----------------------

drop_refused() {
    # A drop may remove only a namespace the name family generated. A literal,
    # or the store's own key, is the base stack's namespace and is rejected.
    case $1 in
        *'{{store}}'*) return 0 ;;
        *'{{isolationIdent}}'*|*'{{isolationLabel}}'*) return 1 ;;
        *) return 0 ;;
    esac
}
drop_refused 'dropdb -U shop {{isolationIdent}}' \
    && fail 'a drop naming the generated identifier was refused, which would withdraw every legitimate offer' \
    || ok 'a drop naming {{isolationIdent}} is accepted, because that namespace belongs to the family itself'
drop_refused 'dropdb -U shop {{store}}' \
    && ok 'a drop naming {{store}} is rejected: that names the base stack namespace rather than the overlay one' \
    || fail 'a drop naming {{store}} was accepted, which aims a destructive verb at the base database'
drop_refused 'dropdb -U shop shop' \
    && ok 'a drop naming a literal is rejected, and no offer is made from it' \
    || fail 'a drop naming a literal was accepted'

# --- the approval is fingerprinted over all three, in order ----------------

family_fingerprint() {
    sh "$SCRIPTS/fingerprint.sh" -C "$MAIN" \
        "scripts/db-create-$STORE" "scripts/db-drop-$STORE" "scripts/db-read-$STORE" \
        | awk '{print $1}' | git hash-object --stdin
}
APPROVED=$(family_fingerprint)
case "$APPROVED" in
    ''|*[!0-9a-f]*) fail "the approval fingerprint produced no value: '$APPROVED'" ;;
    *) ok "the approval is fingerprinted over the three files hashed together, in the order create, drop, read: ${APPROVED%"${APPROVED#????????}"}…" ;;
esac

# A value taken over one of them would leave the other two editable under a
# consent nobody gave for them, so each is checked on its own.
# The files are untracked, so git cannot restore them: keep byte-exact copies
# and put them back from those. Truncating the lines just appended is the same
# idea done less reliably, and a corrupted read would then fail every row below
# it for a reason that has nothing to do with what those rows test.
mkdir -p "$WORK/pristine"
for half in create drop read; do cp "$DIR/db-$half-$STORE" "$WORK/pristine/db-$half"; done

for half in create drop read; do
    printf '\n# a later edit\n' >> "$DIR/db-$half-$STORE"
    moved=$(family_fingerprint)
    if [ "$moved" != "$APPROVED" ]; then
        ok "editing the $half moves the approval, so all three are shown again before anything runs"
    else
        fail "editing the $half left the approval where it was, so that file is editable under a consent nobody gave"
    fi
    cp "$WORK/pristine/db-$half" "$DIR/db-$half-$STORE"
    chmod +x "$DIR/db-$half-$STORE"
done
[ "$(family_fingerprint)" = "$APPROVED" ] \
    && ok 'undoing every edit returns the approval to the value the human approved' \
    || fail 'the approval did not return to its approved value after the edits were undone'

# --- the generated read against a real store -------------------------------

docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --wait >/dev/null 2>&1
BASE=$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" ps -q "$STORE")
IMAGE=$(docker inspect -f '{{.Config.Image}}' "$BASE")
ENV_FILE=$(mktemp)
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$BASE" \
    | awk '!/^(PATH|HOSTNAME|HOME|TERM|PG_VERSION|PGDATA|GOSU_VERSION|LANG|PG_MAJOR|PG_SHA256)=/ && NF' > "$ENV_FILE"
docker run -d --name "$PROBE_NAME" --label "stackgraft.probe=$STORE" --env-file "$ENV_FILE" "$IMAGE" >/dev/null 2>&1
_n=0; while [ "$_n" -lt 40 ]; do docker exec "$PROBE_NAME" pg_isready -U shop -d shop >/dev/null 2>&1 && break; _n=$((_n+1)); sleep 1; done

out_base=$(sh "$DIR/db-read-$STORE" "$BASE" 2>/dev/null || printf 'unreadable')
out_probe=$(sh "$DIR/db-read-$STORE" "$PROBE_NAME" 2>/dev/null || printf 'unreadable')
printf '        generated read: base=%s  empty=%s\n' "$out_base" "$out_probe"

[ "$out_base" != unreadable ] && [ "$out_base" != "$out_probe" ] \
    && ok "the generated read discriminates: the base store answers '$out_base' where an empty instance answers '$out_probe'" \
    || fail "the generated read discriminates nothing: base '$out_base' against empty '$out_probe'"

# The document says a generated SELECT 1 must fail this test exactly as
# pg_isready does. Both answer the same on an instance holding nothing, which
# is the one distinction the whole road exists to make.
# Waited for rather than sampled: an empty answer is an instance that has not
# finished booting, and reading it as "it answered differently" would turn a
# race into evidence that the rule refusing SELECT 1 rests on nothing.
answer_select1() {
    _n=0
    while [ "$_n" -lt 40 ]; do
        _a=$(docker exec "$1" psql -U shop -d shop -tAc 'SELECT 1' 2>/dev/null)
        [ -n "$_a" ] && { printf '%s' "$_a"; return 0; }
        _n=$((_n + 1))
        sleep 1
    done
    printf 'unreadable'
}
sel_base=$(answer_select1 "$BASE")
sel_probe=$(answer_select1 "$PROBE_NAME")
[ "$sel_base" = "$sel_probe" ] \
    && ok "a generated SELECT 1 answers '$sel_base' on both and is refused as a query, exactly as pg_isready is" \
    || fail "SELECT 1 discriminated ('$sel_base' against '$sel_probe'), so the rule refusing it rests on nothing"

# --- inferred until three successes are observed ---------------------------

observe() { "$@" >/dev/null 2>&1; printf '%s' "$?"; }
export SG_INSTANCE="$BASE"
IDENT=sg_family_probe_ns

create_status=$(observe sh "$DIR/db-create-$STORE" "$IDENT")
read_status=$(observe sh "$DIR/db-read-$STORE" "$BASE")

# A create that ran and FAILED is an observation too, and it is not a success:
# the record stays inferred and the teardown stays inert. Creating a namespace
# that already exists is the ordinary way that happens -- a name postgres would
# merely quote is not a failure, because createdb quotes it and succeeds.
again_status=$(observe sh "$DIR/db-create-$STORE" "$IDENT")
drop_status=$(observe sh "$DIR/db-drop-$STORE" "$IDENT")

if [ "$create_status" = 0 ] && [ "$read_status" = 0 ] && [ "$drop_status" = 0 ]; then
    ok "all three are observed to succeed against the discovered store (create=$create_status read=$read_status drop=$drop_status), which is what raises the record from inferred to declared"
else
    fail "the family did not work against the store: create=$create_status read=$read_status drop=$drop_status"
fi

[ "$again_status" != 0 ] \
    && ok "a create that ran and failed exits non-zero ($again_status), so that observation is recorded as the failure it was and the record stays inferred" \
    || fail 'a create against an existing namespace reported success, so a failure would be recorded as the observation that raises the record'

cleanup
printf '\nresult\n'
if [ "$failures" -eq 0 ]; then
    printf '  %s check(s) ran and passed; %s skipped\n\n' "$checks" "$skips"
    exit 0
fi
printf '  %s check(s) ran; %s failed; %s skipped\n\n' "$checks" "$failures" "$skips"
exit 1
