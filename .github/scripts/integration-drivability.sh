#!/bin/sh
# The fifth floor: are the documents drivable at all.
#
# What this can and cannot answer, said first, because the difference is the
# whole reason this file is written the way it is.
#
# It CANNOT answer whether an agent reading SKILL.md reasons well -- picks the
# right step, reads the gate correctly, refuses when it should. That needs a
# model in the loop, which is not deterministic, needs credentials, and whose
# verdict is not an assertion. No row here claims it.
#
# It CAN answer the necessary condition underneath that, which is testable and
# was never tested: does everything the documents tell an agent to reach EXIST,
# and does it BEHAVE as the documents say. A pointer to a file that moved, a
# usage line that drifted from the script it describes, a placeholder outside
# the closed set the example itself uses -- each of those blocks an agent
# before it reasons about anything, and none of them is visible to a row that
# checks the prose says what the prose says.
#
# usage: sh .github/scripts/integration-drivability.sh
set -u

checks=0
failures=0
skips=0

ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }
skip() { skips=$((skips + 1));   printf '  skip  %s\n' "$1"; }

REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
SKILL="$REPO/skills/stackgraft"
FIXTURE="$REPO/.github/fixtures/shopdemo"
WORK="$REPO/.sg-work-drive"
MAIN="$WORK/shopdemo"
TREE="$WORK/shopdemo-worktrees/probe"

cleanup() { rm -rf "$WORK"; return 0; }
trap cleanup EXIT INT TERM

printf '\nare the documents drivable\n\n'

cleanup
mkdir -p "$MAIN"
cp -R "$FIXTURE/." "$MAIN/"
(
    cd "$MAIN" || exit 1
    git init -q -b main
    git add -A
    git -c user.email=f@example.com -c user.name=f commit -qm base
) >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b probe "$TREE" >/dev/null 2>&1

# --- every pointer the documents hand an agent resolves ---------------------

missing=''
for doc in "$SKILL/SKILL.md" "$SKILL"/references/*.md; do
    for ref in $(grep -o '`\(references/[a-z-]*\.md\|scripts/[a-z-]*\.sh\|assets/[a-z._-]*\.json\)`' "$doc" \
                 | tr -d '`' | sort -u); do
        [ -e "$SKILL/$ref" ] || missing="$missing $(basename "$doc"):$ref"
    done
done
[ -z "$missing" ] \
    && ok 'every references/, scripts/ and assets/ path named in a shipped document resolves to a file that ships' \
    || fail "a document points an agent at something that is not there:$missing"

# Nothing may ship that no document tells an agent to use: an agent cannot
# reach a helper it is never told about, and a helper nothing names is either
# dead or a gap in the instructions.
orphans=''
for s in "$SKILL"/scripts/*.sh; do
    n=$(basename "$s")
    grep -qR "scripts/$n" "$SKILL/SKILL.md" "$SKILL"/references/*.md || orphans="$orphans $n"
done
[ -z "$orphans" ] \
    && ok 'every shipped script is named by at least one document, so nothing an agent needs is reachable only by listing the directory' \
    || fail "a script ships that no document names:$orphans"

# --- the documented invocations run, and the wrong ones fail loudly ---------
# A usage line that drifted from the script it describes is the failure mode
# with no symptom: the agent copies the documented form and gets a stranger.

run_doc_form() {
    _label=$1; shift
    if "$@" >/dev/null 2>&1; then
        ok "$_label"
    else
        fail "$_label -- the documented form did not work"
    fi
}
refuses_empty() {
    _label=$1; _script=$2
    sh "$SKILL/scripts/$_script" >/dev/null 2>&1
    _rc=$?
    [ "$_rc" -ne 0 ] \
        && ok "$_label (exit $_rc)" \
        || fail "$_label -- it succeeded with no arguments, so a malformed call is silent"
}

HASH8=$(printf '%s' "$MAIN/.git" | git hash-object --stdin | cut -c1-8)

run_doc_form 'fingerprint.sh runs its documented form: [-C repoRoot] <path>...' \
    sh "$SKILL/scripts/fingerprint.sh" -C "$MAIN" compose.yaml
printf 'compose.yaml\n' > "$WORK/paths"
run_doc_form 'fingerprint.sh runs its documented stdin form: a trailing - reads paths from stdin' \
    sh -c "cd '$MAIN' && printf 'compose.yaml\n' | sh '$SKILL/scripts/fingerprint.sh' -"
refuses_empty 'fingerprint.sh fails loudly with no arguments' fingerprint.sh

run_doc_form 'pick-port.sh runs its documented form: <lo> <hi> <worktree> [excluded-port ...]' \
    sh "$SKILL/scripts/pick-port.sh" 18000 18200 "$TREE" 15432 18080
refuses_empty 'pick-port.sh fails loudly with no arguments' pick-port.sh

printf '{}\n' > "$WORK/payload.json"
run_doc_form 'with-lock.sh runs its documented form: <destination> <payload> <expected>, with - for no file' \
    sh "$SKILL/scripts/with-lock.sh" "$WORK/cache.json" "$WORK/payload.json" -
refuses_empty 'with-lock.sh fails loudly with no arguments' with-lock.sh

run_doc_form 'reap.sh runs its documented report form: [-C <repoRoot>] [-b <basePort>]... report <hash8>' \
    sh "$SKILL/scripts/reap.sh" -C "$MAIN" -b 15432 report "$HASH8"
refuses_empty 'reap.sh fails loudly with no arguments' reap.sh

# A mutation with no port refuses rather than guessing, which the documents
# state as a rule an agent relies on before it ever passes one.
sh "$SKILL/scripts/reap.sh" -C "$MAIN" -m stop "$HASH8" 'c:whatever' >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] \
    && ok "reap.sh refuses a mutation given no base port rather than guessing one (exit $rc)" \
    || fail 'reap.sh accepted a mutation with no base port, so the rule an agent is told to rely on is not enforced'

# --- the step an agent takes first, taken exactly as written ----------------
# SKILL.md step 1 and discovery.md section 0: derive gitCommonDir at the
# worktree top, take repoRoot from it, and key the cache on its first eight
# characters. An agent that cannot reproduce this reads a manifest nothing
# wrote and rediscovers on every run.

DERIVED=$(cd "$TREE" && CDPATH= cd -- "$(git rev-parse --git-common-dir)" && pwd -P)
EXPECTED=$(CDPATH= cd -- "$MAIN/.git" && pwd -P)
[ "$DERIVED" = "$EXPECTED" ] \
    && ok 'from inside a worktree the documented derivation yields the MAIN checkout git dir, not this one' \
    || fail "the documented derivation gave '$DERIVED' where the main common dir is '$EXPECTED'"

D_HASH=$(printf '%s' "$DERIVED" | git hash-object --stdin | cut -c1-8)
[ "$D_HASH" = "$HASH8" ] && [ ${#D_HASH} = 8 ] \
    && ok "hash8 is the first eight characters of that digest and is reproducible from either checkout: $D_HASH" \
    || fail "hash8 did not reproduce: '$D_HASH' against '$HASH8'"

# echo would append a newline and digest to something else, which the document
# names as the way two spellings key two manifests for one repository.
NL_HASH=$(printf '%s\n' "$DERIVED" | git hash-object --stdin | cut -c1-8)
[ "$NL_HASH" != "$HASH8" ] \
    && ok 'a trailing newline really does key a different manifest, which is why the document forbids echo here' \
    || fail 'the no-trailing-newline rule makes no difference, so the reason given for it is not the reason'

# --- the copy road cannot depend on an engine, and this is what makes it so ---
# "Blind to the substrate" is a claim about the procedure. The four engines the
# behavioural floors run prove it holds for four; this proves it CANNOT fail for
# a fifth, by checking that the code has nowhere to put the knowledge.

ENGINE_WORDS='postgres|postgresql|pgvector|timescale|mysql|mariadb|mongo|redis|valkey|minio|kafka|rabbitmq|elasticsearch|clickhouse|cassandra|couchdb|nats'
hits=$(grep -ciE "$ENGINE_WORDS" "$SKILL/scripts/provider-docker.sh" || true)
[ "${hits:-0}" = 0 ] \
    && ok 'the shipped provider names no engine anywhere, so a store it has never heard of takes the same road as one it has' \
    || fail "the provider names an engine $hits time(s), which is a special case waiting to be relied on"

subs=$(grep -ci 'substrate' "$SKILL/scripts/provider-docker.sh" || true)
[ "${subs:-0}" = 0 ] \
    && ok 'and it never reads a substrate: the copy road is given a store key and the runtime facts, never a label for what the engine is' \
    || fail "the provider reads a substrate $subs time(s), so an unlabelled store could be refused for want of a label"

# The one place the finiteness is allowed to live: the advice. A substrate with
# no row there selects no advice, which is a gap in guidance and never a gate.
for f in "$SKILL/references/shared-state.md" "$SKILL/references/discovery.md"; do
    grep -q 'undetermined' "$f" || fail "$(basename "$f") does not admit an undetermined value anywhere"
done
ok 'and the documents admit an undetermined substrate, which is what keeps a store nobody wrote advice for inside the map'

# --- the placeholder set an agent substitutes into is closed ---------------
# shared-state.md states a closed set of six. An agent copying the shipped
# example must not meet a seventh: an unknown placeholder invalidates the
# template, so one in the example is an instruction to produce a refusal.

CLOSED='isolationIdent isolationLabel store worktree repoRoot port'
# The `case` stays OUTSIDE the command substitution deliberately: bash 3.2 --
# which is what /bin/sh is on macOS -- cannot parse a case pattern inside $( ),
# because its parser counts the pattern's own `)` as the substitution's close.
# dash and bash 5 accept it, so CI alone would never have said so.
strays=''
for p in $(grep -o '{{[a-zA-Z]*}}' "$SKILL/assets/manifest.example.json" | tr -d '{}' | sort -u); do
    case " $CLOSED " in
        *" $p "*) ;;
        *) strays="$strays$p " ;;
    esac
done
[ -z "$strays" ] \
    && ok 'every placeholder in the shipped example is inside the closed set of six the gate states' \
    || fail "the example hands an agent a placeholder outside the closed set: $strays"

for p in $CLOSED; do
    grep -q "{{$p}}" "$SKILL/references/shared-state.md" \
        || fail "the closed set names $p and shared-state.md never shows it, so an agent has no form to copy"
done
ok 'each member of the closed set appears in the file that declares the set, so none is named without a form'

cleanup
printf '\nresult\n'
if [ "$failures" -eq 0 ]; then
    printf '  %s check(s) ran and passed; %s skipped\n\n' "$checks" "$skips"
    exit 0
fi
printf '  %s check(s) ran; %s failed; %s skipped\n\n' "$checks" "$failures" "$skips"
exit 1
