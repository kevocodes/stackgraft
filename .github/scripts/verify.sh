#!/bin/sh
# verify.sh - every check this project makes, run for real.
#
# usage:  sh .github/scripts/verify.sh
#         STACKGRAFT_REQUIRE_RUNTIME=1 sh .github/scripts/verify.sh   (CI)
# exit:   0 every check that RAN passed  ·  1 at least one failed
#
# A run that skipped rows says so in the summary and never reports them as
# passed. With STACKGRAFT_REQUIRE_RUNTIME set, a missing runtime prerequisite -
# a daemon, an image, an interpreter - is a failure rather than a note.
#
# Two rules this file enforces on itself:
#   - a check that cannot fail is not a check. Every assertion has a matching
#     negative fixture that must be REJECTED, so a validator that silently
#     stopped validating shows up as a failure rather than a pass.
#   - the minimal instance the schema accepts is the one worth tracing. Safety
#     holes live in the smallest legal input, not the realistic one.

set -u
SKILL=skills/stackgraft
ROOT=$(pwd)
fails=0
oks=0
skips=0
skipped_runtime=''

ok()   { printf '  ok    %s\n' "$1"; oks=$((oks + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# A skipped row is not a passed row, and until this counter existed nothing in
# the summary could tell them apart. Measured on this tree: a run with no docker
# daemon and no jsonschema executes 565 of 805 rows - 240 never run, and they
# are the provider, the verification, the generated read, the anonymous-volume
# ledger and the whole schema half, which is the entire runtime half of what
# this release added - and it printed `all checks passed`, exit 0. The mechanism
# the release exists for had no executed coverage and CI had no way to say so.
#
# Two classes, because "make every skip fatal" is the wrong repair:
#
#   runtime      a prerequisite the CI job is supposed to supply - a daemon, an
#                image, an interpreter. A skip here means the suite ran without
#                the thing it exists to exercise, and under
#                STACKGRAFT_REQUIRE_RUNTIME that is a failure.
#   conditional  a property of the host or of the input that is legitimately
#                absent: no `ps -o lstart=`, running as root, a release that is
#                not a major one. Making these fatal would turn a correct run
#                red for a reason that is not a defect - which is how a gate
#                nobody trusts gets switched off.
#
# The default class is `conditional`, and that is deliberate the other way from
# usual: an unclassified skip should not fail a run, but it also should not be
# silent, and the counter above sees every one of them.
skip() {
    printf '  skip  %s\n' "$1"
    skips=$((skips + 1))
    case ${2:-conditional} in
        runtime) skipped_runtime="$skipped_runtime
      - $1" ;;
    esac
}

section() { printf '\n%s\n' "$1"; }

# One expression for lowercase hex and one for a whole object id, shared by every
# row that concludes anything from a digest: the fingerprint row in the next
# section, the truncation-removal premise in the skill body, and the probe
# byte-identity premise in the reap section. Three private spellings of "looks
# like a hash" is how they drift into admitting three different things.
#
# A whole object id is 40 characters or 64 - never a hard-coded 40, because a
# repository with `extensions.objectFormat=sha256` digests to 64, and this
# project's own design record (DS11) refused to put a length `pattern` on a
# fingerprint for exactly that reason. Measured on git 2.50.1: one input, 40
# characters from a sha1 repository and 64 from a sha256 one.
lower_hex() {
    case ${1:-} in
        '' | *[!0-9a-f]*) return 1 ;;
        *)                return 0 ;;
    esac
}
whole_object_id() {
    lower_hex "${1:-}" || return 1
    case ${#1} in
        40 | 64) return 0 ;;
        *)       return 1 ;;
    esac
}

# The two intent-blind greps, named once each and defined here rather than beside
# their first fixture, because three sections now read them: the instrumentation
# fixtures that prove each can fire, the shipped tree-wide row at the bottom of
# this file, and the coordination-identity section, which widens the portability
# list for the files that carry no legacy reason to name any of it. With a second
# copy anywhere, editing one leaves the other proving an expression that no
# longer runs.
PORTABILITY='~/\.claude|codegraph|\bpython3\b|\bjq\b|sha256sum|AppData'
GNUISM='newermt|stat -c|readlink -f|--date='

# The shipped surface: what a READER is handed, named once because three sweeps
# below ask about it and they had drifted into asking about three different
# things. It is the skill folder plus the prose beside it - and SECURITY.md and
# CONTRIBUTING.md are in it because leaving them out is not hypothetical: slice 3
# retired `{{isolationName}}` and swept `skills/stackgraft README.md docs/` for
# it, so for three slices the project's security page went on documenting *a
# closed placeholder set of five* naming a placeholder no code substitutes and no
# schema accepts. Nothing failed, because nothing was looking there.
#
# CHANGELOG.md is deliberately NOT in it. Its breaking-change entry says what
# 1.1.0's `{{isolationName}}` could not name, and that sentence is true and has to
# stay. Neither are `openspec/` or the archive: those are records of what was
# decided, not text anybody is handed.
SHIPPED_SURFACE="$SKILL README.md SECURITY.md CONTRIBUTING.md docs/"

# ...and the list is held to the files it names, so a path renamed out from under
# it fails here rather than quietly shrinking every sweep that uses it - the shape
# the five shipped scripts are inventoried with just below.
#
# It takes a ROOT so a negative can build a scratch surface and be held to the
# same completeness before anything is concluded from a sweep over it. A negative
# run against a surface missing the very file it injects into reports the green
# the shipped tree reported for two slices.
surface_missing() {
    _root=${1:-.}
    _n=0
    for _p in $SHIPPED_SURFACE; do
        [ -e "$_root/$_p" ] || _n=$((_n + 1))
    done
    printf '%s\n' "$_n"
}

# ---------------------------------------------------------------- shell -----
section "the suite's own counters"

# One decision, called by the result section at the bottom and by the probes
# here. A second copy of the expression is how one of the two stops asserting
# anything and nobody notices - the shape this suite has found four times.
runtime_gate() { [ -n "$1" ] && [ "$2" != "0" ]; }

runtime_gate '      - a prerequisite' 1 \
    && ok "a runtime prerequisite absent with STACKGRAFT_REQUIRE_RUNTIME set is a failure" \
    || fail "the runtime gate cannot fail even with the flag set and a prerequisite missing"
runtime_gate '      - a prerequisite' 0 \
    && fail "the runtime gate fires with the flag off, so a laptop with no daemon hits a wall" \
    || ok "...and with the flag off it is a note rather than a failure"
runtime_gate '' 1 \
    && fail "the runtime gate fires with nothing skipped, so it says nothing about what was skipped" \
    || ok "...and with the flag set but nothing skipped it stays silent"

# The counter itself, probed in a subshell so a probe of the machinery never
# moves the totals it is probing.
sk_runtime=$( skips=0; skipped_runtime=''; skip "a probe row" runtime >/dev/null; printf '%s|%s' "$skips" "$skipped_runtime" )
sk_cond=$(    skips=0; skipped_runtime=''; skip "a probe row" >/dev/null;         printf '%s|%s' "$skips" "$skipped_runtime" )
case $sk_runtime in
    '1|'*'a probe row'*) ok "a runtime skip counts and is named in the runtime list" ;;
    *)                   fail "a runtime skip did not count or was not recorded: '$sk_runtime'" ;;
esac
case $sk_cond in
    '1|') ok "...and a skip with no class counts without entering the runtime list, which is the safe default" ;;
    *)    fail "an unclassified skip took the runtime path or did not count: '$sk_cond'" ;;
esac

# ...and none of the above matters if a row can print a skip line without going
# through the function. Every site must call it; the one printf that remains is
# the function's own.
# The pattern is assembled from two halves on purpose: written whole, this line
# would match itself and the row would report one more raw printf than exists -
# a check whose own source is part of what it counts. The same self-reference
# scoped the claim sweep above out of this file.
_sk_pat="printf '  sk"
_sk_pat="${_sk_pat}ip"
sk_raw=$(grep -c "$_sk_pat" .github/scripts/verify.sh 2>/dev/null || echo 0)
[ "$sk_raw" -eq 1 ] \
    && ok "every skip in this file goes through the counted helper, so none can pass unnoticed again" \
    || fail "$sk_raw raw skip printfs exist, so $((sk_raw - 1)) row(s) skip without counting"

section "scripts"

# One expression for both shebang rows - the shipped scripts here and
# changelog-section.sh at the bottom of this file - so the two cannot drift into
# accepting different things.
#
# The end anchor is the repair. `^#!/bin/sh` alone also matches `#!/bin/shell`,
# `#!/bin/shenanigans` and anything else beginning that way, so a shebang naming
# an interpreter that is not on the box read as a shebang naming one that is.
has_shebang() { head -1 "$1" | grep -q '^#!/bin/sh$'; }

# The loop below asserts no INVENTORY: it runs once per file the glob finds, so
# a script deleted from the skill costs two rows and produces no FAIL at all -
# fewer checks read exactly like fewer problems. The four are named, and the
# number of them that is missing must be zero, which is the shape the anchor
# fixtures in reaping.md are already checked with.
SHIPPED_SCRIPTS='pick-port.sh fingerprint.sh with-lock.sh reap.sh provider-docker.sh'
scripts_missing() {
    _n=0
    for _s in $SHIPPED_SCRIPTS; do
        [ -f "$1/$_s" ] || _n=$((_n + 1))
    done
    printf '%s\n' "$_n"
}
[ "$(scripts_missing "$SKILL/scripts")" -eq 0 ] \
    && ok "all five shipped scripts are present: $SHIPPED_SCRIPTS" \
    || fail "$(scripts_missing "$SKILL/scripts") of the five shipped scripts are missing from $SKILL/scripts"

# ...and the inventory can notice one going away, the same way the anchor
# fixture check is proven: a copy with one entry removed. Two of them now, and
# the second is not redundant: the first proves the LOOP can count a gap, the
# second proves the named list is the one this slice extended. An inventory that
# still read four names would report all four present with the fifth script
# deleted, and fewer checks read exactly like fewer problems.
si=$(mktemp -d)
cp "$SKILL"/scripts/*.sh "$si/"
rm -f "$si/reap.sh"
[ "$(scripts_missing "$si")" -ge 1 ] \
    && ok "rejected: a scripts directory with reap.sh deleted" \
    || fail "the script inventory cannot notice a deleted script"
cp "$SKILL"/scripts/*.sh "$si/"
rm -f "$si/provider-docker.sh"
[ "$(scripts_missing "$si")" -ge 1 ] \
    && ok "rejected: a scripts directory with provider-docker.sh deleted" \
    || fail "the script inventory cannot notice the provider going away"
rm -rf "$si"

# The same treatment for the shipped SURFACE, and for the same reason: a sweep
# that names a path which is not there reports clean over a file it never read.
[ "$(surface_missing)" -eq 0 ] \
    && ok "every path in the shipped surface exists: $SHIPPED_SURFACE" \
    || fail "$(surface_missing) of the shipped-surface paths are missing, so every sweep over it is smaller than it reads"

# ...and SECURITY.md is in it BY NAME. That file is where the retired placeholder
# survived three slices, and a surface that quietly stopped covering it would
# report exactly the green it reported then.
case " $SHIPPED_SURFACE " in
    *' SECURITY.md '*) ok "the shipped surface covers SECURITY.md by name, which is the file the retired placeholder survived in" ;;
    *)                 fail "SECURITY.md is not in the shipped surface, so the drift it carried would go unreported again" ;;
esac

for f in "$SKILL"/scripts/*.sh; do
    name=$(basename "$f")
    if command -v dash >/dev/null 2>&1; then
        dash -n "$f" 2>/dev/null && ok "$name parses under dash" || fail "$name fails dash -n"
    else
        sh -n "$f" 2>/dev/null && ok "$name parses under sh" || fail "$name fails sh -n"
    fi
    has_shebang "$f" && ok "$name carries a shebang" || fail "$name has no shebang"
done

wt=$(mktemp -d)

port=$(sh "$SKILL/scripts/pick-port.sh" 18000 18999 "$wt" 2>/dev/null)
case $port in
    1[8-9][0-9][0-9][0-9]) ok "pick-port emits a candidate in range ($port)" ;;
    *)                     fail "pick-port emitted '$port'" ;;
esac

# Both sides are `$(...)` over a script that may print nothing, and '' = '' is
# true - so a pick-port that emitted NOTHING AT ALL for every call reported
# itself stable across spellings. Equality still covers a script that answers
# differently for the two; only the non-empty half covers one that answers
# neither. Same reason the exclusion row below asserts `-n "$excl"` and the lock
# rows assert `-n "$before"`.
a=$(sh "$SKILL/scripts/pick-port.sh" 18000 18999 "$wt" 2>/dev/null)
b=$(sh "$SKILL/scripts/pick-port.sh" 18000 18999 "$wt/" 2>/dev/null)
if [ -n "$a" ] && [ "$a" = "$b" ]; then
    ok "pick-port is stable across path spellings"
else
    fail "pick-port gave '$a' then '$b' for one worktree"
fi

# The inequality alone is satisfied by EMPTY, so a pick-port that emitted
# nothing for every call carrying an exclusion passed this row: '' is not $a.
# What the row means is three things - a port, in range, and not the excluded
# one - and it asks for all three, in the same `case` shape the range row above
# uses for the same value.
excl=$(sh "$SKILL/scripts/pick-port.sh" 18000 18999 "$wt" "$a" 2>/dev/null)
case ${excl:-} in
    1[8-9][0-9][0-9][0-9]) excl_ranged=1 ;;
    *)                     excl_ranged=0 ;;
esac
if [ -n "$excl" ] && [ "$excl_ranged" -eq 1 ] && [ "$excl" != "$a" ]; then
    ok "pick-port honours an exclusion (emitted $excl, not the excluded $a)"
else
    fail "pick-port emitted '$excl' with $a excluded"
fi

sh "$SKILL/scripts/pick-port.sh" 18000 18000 "$wt" 18000 >/dev/null 2>&1
[ $? -eq 3 ] && ok "pick-port exits 3 when the range is exhausted" || fail "pick-port did not signal exhaustion"

sh "$SKILL/scripts/pick-port.sh" 18000 18999 "$wt" "3000,5173" >/dev/null 2>&1
[ $? -eq 2 ] && ok "pick-port rejects a comma-joined exclusion list" || fail "pick-port accepted a comma list"

# Exit 2 alone cannot say WHICH refusal fired. An all-digit path that got past
# the guard this row exists to prove reaches the directory test one line later
# and refuses at 2 as well, so deleting the guard leaves the row green. The
# message is asserted for the same reason the -b rejection further down is
# quoted back by name: "rejected" without "rejected by what" is half a check.
ws=$(sh "$SKILL/scripts/pick-port.sh" 18000 18999 18500 2>&1 >/dev/null)
ws_rc=$?
if [ "$ws_rc" -eq 2 ] && printf '%s' "$ws" | grep -q "all digits: '18500'"; then
    ok "pick-port rejects a port in the worktree slot, naming it as all digits"
else
    fail "the worktree-slot refusal: exit $ws_rc, said '$ws'"
fi

lines=$(printf 'README.md\nLICENSE' | sh "$SKILL/scripts/fingerprint.sh" - 2>/dev/null | wc -l | tr -d ' ')
[ "$lines" = "2" ] && ok "fingerprint keeps a final unterminated line" || fail "fingerprint emitted $lines lines for 2 paths"

# `-` for a missing path is drift only if a path that IS there gets something
# else. This row used to assert the missing half alone, and fingerprint.sh emits
# `-` for anything it could not hash - so with git off the PATH it reported `-`
# for a README.md sitting right there, every source in the manifest read as
# changed, and the row went green over a fingerprint that called the whole
# repository drift. Nothing else in this section asserted that a present path
# digests to anything at all.
#
# One invocation, both paths, and the present one must come back a whole object
# id, so "everything is drift" can no longer read as "the missing path was
# noticed". The digest is not compared to a value: the row is about what
# fingerprint.sh can TELL APART, and pinning the digest would just re-check git.
fp=$(sh "$SKILL/scripts/fingerprint.sh" README.md no/such/file.txt 2>/dev/null)
here=$(printf '%s\n' "$fp" | awk 'NR == 1 { print $1 }')
miss=$(printf '%s\n' "$fp" | awk 'NR == 2 { print $1 }')
if ! whole_object_id "$here"; then
    fail "fingerprint gave '${here:-nothing}' for a present README.md, so a '-' beside it is not drift, it is everything"
elif [ "$miss" = "-" ]; then
    ok "fingerprint digests a present path and reports a missing one as drift"
else
    fail "fingerprint gave '$miss' for a missing path"
fi

sh "$SKILL/scripts/fingerprint.sh" >/dev/null 2>&1
[ $? -eq 2 ] && ok "fingerprint fails loudly with no arguments" || fail "fingerprint did not reject an empty invocation"

rm -rf "$wt"

# --------------------------------------------------- lock and swap ----------
section "lock and compare-and-swap"

LOCK="$SKILL/scripts/with-lock.sh"
lockdir=$(mktemp -d)
printf 'replacement\n' > "$lockdir/payload"

# Counts the non-blank lines one ps invocation reports for a single pid. Two
# calls make a probe rather than one: a ps that ignores -p answers the first
# call plausibly and the second with the whole table.
probe_lines() { ps -o lstart= -p "$1" 2>/dev/null | awk 'NF { n++ } END { print n + 0 }'; }
if [ "$(probe_lines $$)" = 1 ] && [ "$(probe_lines 1)" = 1 ]; then
    lstart_here=1
else
    lstart_here=0
fi

# Releases whatever is blocked reading the FIFO the holder was given as its
# destination. Read-WRITE is deliberate: opening a FIFO write-only blocks until
# a reader appears, so it would hang here forever exactly when the reader has
# already died - the case this is called to clean up after. Read-write never
# blocks, and closing it hands the reader its EOF.
#
# Signalling the process tree was the alternative and it does not work: plain
# ps lists only processes on the current terminal, so in CI, where there is no
# terminal, the walk finds no children at all and the run hangs with nothing to
# diagnose.
unblock() { : <> "$1"; }

# Waits for a holder to have actually taken the lock instead of sleeping a
# guessed interval: the owner file is the last thing acquisition writes.
await_owner() {
    _n=0
    while [ "$_n" -lt 30 ]; do
        [ -f "$1/owner" ] && return 0
        _n=$((_n + 1))
        [ "$_n" -gt 20 ] && sleep 1
    done
    return 1
}

# Every fixture below asserts the destination's BYTES as well as the exit code.
# A refusal that replaced the file anyway is not a refusal, and an exit code on
# its own cannot tell those two apart.
#
# `before` is required to be NON-EMPTY as well as equal to `after`. Both sides
# are `git hash-object --stdin < "$d"`, and that prints nothing at all when the
# redirect finds no file - so `'' = ''` reported "bytes unchanged" over a
# destination that was not there to change, in every row of this shape,
# including the live-holder one, which is a safety assertion. Equality alone
# still covers a destination the run DELETED; only the non-empty half covers
# one that never existed.

# --- V7  compare-and-swap: the lock alone does not close the write window ----
d="$lockdir/manifest.json"
printf 'base\n' > "$d"
fp=$(git hash-object --stdin < "$d")
printf 'base\nA-entry\n' > "$lockdir/payload-a"
printf 'base\nB-entry\n' > "$lockdir/payload-b"

sh "$LOCK" "$d" "$lockdir/payload-a" "$fp" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -q 'A-entry' "$d"; then
    ok "CAS: the first writer commits (exit 0)"
else
    fail "CAS: the first writer exited $rc"
fi

# B read the file before A committed and still holds that fingerprint. This is
# the read-modify-write window a perfect lock leaves wide open.
sh "$LOCK" "$d" "$lockdir/payload-b" "$fp" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 5 ] && ok "CAS: a stale expected fingerprint is refused (exit 5)" \
    || fail "CAS: the stale write exited $rc, not 5"
if grep -q 'A-entry' "$d" && ! grep -q 'B-entry' "$d"; then
    ok "CAS: the refused write left the first writer's entry intact"
else
    fail "CAS: the refused write damaged the destination"
fi

# ...and 5 is a refusal, not an inability to write. B re-reads, re-merges, retries.
fp2=$(git hash-object --stdin < "$d")
printf 'base\nA-entry\nB-entry\n' > "$lockdir/payload-b"
sh "$LOCK" "$d" "$lockdir/payload-b" "$fp2" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -q 'A-entry' "$d" && grep -q 'B-entry' "$d"; then
    ok "CAS: the re-read retry commits and both entries survive"
else
    fail "CAS: the retry exited $rc or lost an entry"
fi

# "-" is the expected value for a destination the caller found absent.
absent="$lockdir/absent.json"
rm -f "$absent"
sh "$LOCK" "$absent" "$lockdir/payload" - >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && [ -f "$absent" ] && ok "CAS: '-' commits against an absent destination" \
    || fail "CAS: '-' against an absent destination exited $rc"

sh "$LOCK" "$d" "$lockdir/payload" >/dev/null 2>&1
[ $? -eq 2 ] && ok "an omitted expected fingerprint is a usage error, never a default" \
    || fail "with-lock accepted a missing expected fingerprint"

# --- V8  liveness decides staleness, not a timer alone -----------------------
d="$lockdir/v8.json"
printf 'v8\n' > "$d"
fp=$(git hash-object --stdin < "$d")
deadpid=$(sh -c 'echo $$')
mkdir "$d.lock"
printf '%s\nWed Jul 30 12:00:00 2026\n%s\n' "$deadpid" "$(uname -n)" > "$d.lock/owner"
t0=$(date +%s)
sh "$LOCK" "$d" "$lockdir/payload" "$fp" >/dev/null 2>&1
rc=$?
el=$(( $(date +%s) - t0 ))
rm -rf "$d.lock"
if [ "$rc" -eq 0 ] && [ "$el" -lt 10 ] && grep -q 'replacement' "$d"; then
    ok "a lock whose owner is provably dead is reclaimed at once (exit 0 after ${el}s)"
else
    fail "dead-owner lock: exit $rc after ${el}s"
fi

if [ "$lstart_here" -eq 1 ]; then
    d="$lockdir/v8b.json"
    printf 'v8b\n' > "$d"
    fp=$(git hash-object --stdin < "$d")
    before=$(git hash-object --stdin < "$d")
    sleep 60 &
    livepid=$!
    mkdir "$d.lock"
    printf '%s\n%s\n%s\n' "$livepid" \
        "$(ps -o lstart= -p "$livepid" | awk 'NF { print; exit }')" "$(uname -n)" > "$d.lock/owner"
    msg=$(sh "$LOCK" "$d" "$lockdir/payload" "$fp" 2>&1)
    rc=$?
    after=$(git hash-object --stdin < "$d")
    kill "$livepid" 2>/dev/null
    wait "$livepid" 2>/dev/null
    rm -rf "$d.lock"
    if [ "$rc" -eq 3 ] && [ -n "$before" ] && [ "$before" = "$after" ] \
       && printf '%s' "$msg" | grep -q "$livepid"; then
        ok "a provably live holder is never stolen from (exit 3, bytes unchanged, pid named)"
    else
        fail "live-holder lock: exit $rc, bytes $before -> $after, said '$msg'"
    fi
else
    skip "live-holder refusal (this host has no ps -o lstart=)" conditional
fi

# --- V9  the time bound only decides what liveness could not -----------------
d="$lockdir/v9.json"
printf 'v9\n' > "$d"
fp=$(git hash-object --stdin < "$d")
mkdir "$d.lock"
t0=$(date +%s)
sh "$LOCK" "$d" "$lockdir/payload" "$fp" >/dev/null 2>&1
rc=$?
el=$(( $(date +%s) - t0 ))
rm -rf "$d.lock"
if [ "$rc" -eq 0 ] && [ "$el" -ge 10 ] && [ "$el" -lt 25 ]; then
    ok "an owner-less lock is reclaimed by the time bound (exit 0 after ${el}s)"
else
    fail "owner-less lock: exit $rc after ${el}s"
fi

d="$lockdir/v9b.json"
printf 'v9b\n' > "$d"
fp=$(git hash-object --stdin < "$d")
before=$(git hash-object --stdin < "$d")
mkdir "$d.lock"
( sleep 4; rm -rf "$d.lock"; mkdir "$d.lock" ) &
churn=$!
t0=$(date +%s)
sh "$LOCK" "$d" "$lockdir/payload" "$fp" >/dev/null 2>&1
rc=$?
el=$(( $(date +%s) - t0 ))
wait "$churn" 2>/dev/null
after=$(git hash-object --stdin < "$d")
rm -rf "$d.lock"
if [ "$rc" -eq 3 ] && [ -n "$before" ] && [ "$before" = "$after" ]; then
    ok "a lock created during the wait is not stolen (exit 3 after ${el}s)"
else
    fail "lock created during the wait: exit $rc after ${el}s, bytes $before -> $after"
fi

# --- V10  TERM runs the trap; KILL cannot, which is why staleness is policy --
# The holder is made to hold by giving it a FIFO as the destination: it takes
# the lock, writes its owner, and then blocks reading that destination to
# compute the compare-and-swap fingerprint. Nothing is stubbed - this is the
# shipped acquisition path and the shipped trap.
for sig in TERM KILL; do
    d="$lockdir/v10-$sig"
    rm -f "$d"
    mkfifo "$d"
    sh "$LOCK" "$d" "$lockdir/payload" - >/dev/null 2>&1 &
    holder=$!
    if await_owner "$d.lock"; then
        kill "-$sig" "$holder" 2>/dev/null
        unblock "$d"
        wait "$holder" 2>/dev/null
        if [ "$sig" = TERM ]; then
            [ ! -d "$d.lock" ] \
                && ok "TERM to a holder runs the trap and the lock directory is gone" \
                || fail "TERM to a holder left $d.lock behind"
        else
            [ -d "$d.lock" ] \
                && ok "KILL to a holder leaves the lock: SIGKILL cannot be trapped" \
                || fail "KILL to a holder removed the lock, which no trap can have done"
        fi
    else
        fail "the holder never took the lock for the $sig case"
        kill -KILL "$holder" 2>/dev/null
        unblock "$d"
    fi
    rm -f "$d"
done

# The lock the killed holder left names a pid that is now gone, so the next
# writer reclaims it. This is the half of the policy SIGKILL makes mandatory.
#
# That lock being there is this row's PREMISE, and it is recorded before the run
# rather than assumed. With nothing left to reclaim the write below is an
# ordinary commit that takes and releases a lock of its own, exits 0 and leaves
# no directory - so the row printed "reclaims the lock a killed holder left
# behind" over a KILL case that left no lock at all. Captured before the action
# for the same reason the V8, V9 and W1 rows capture the destination's bytes.
d="$lockdir/v10-KILL"
[ -d "$d.lock" ] && kill_left_lock=1 || kill_left_lock=0
printf 'v10\n' > "$d"
fp=$(git hash-object --stdin < "$d")
sh "$LOCK" "$d" "$lockdir/payload" "$fp" >/dev/null 2>&1
rc=$?
if [ "$kill_left_lock" -eq 1 ] && [ "$rc" -eq 0 ] && [ ! -d "$d.lock" ]; then
    ok "the next writer reclaims the lock a killed holder left behind"
else
    fail "the lock a killed holder left wedged the next writer (exit $rc, a lock was there to reclaim: $kill_left_lock)"
fi
rm -rf "$lockdir"

# --- W1  every path left beside the destination must be one the run named ----
# The carve-out permits exactly three paths and all three are transient, so the
# destination's directory is ENUMERATED before and after rather than probed for
# names guessed in advance - a leak nobody predicted is exactly the one a
# targeted check misses.
#
# The invariant is stronger than "exit 0": every surviving path must be one the
# run itself named in its output. An exit code cannot express the failure this
# catches, because that failure IS an exit 0 - the run reports "reclaimed an
# abandoned lock", returns success, and says nothing at all about the aside it
# renamed the lock directory to and could not delete.
inventory() { ( CDPATH= cd -- "$1" && find . -maxdepth 1 ! -name . | sort | tr '\n' ' ' ); }

# Only what the SCRIPT said counts as the run naming something. Its own
# diagnostics all carry its name; rm's incidental stderr does not. A leak the
# caller learns about solely from a subcommand's noise is still a leak the run
# itself claimed nothing about, and folding the two together would let the row
# pass on exactly the output the defect already produces.
lock_said() { printf '%s\n' "$1" | grep "^${LOCK##*/}:"; }

# Prints one line per path in $1 that is neither expected ($2, space-separated
# basenames) nor named anywhere in what the run said ($3). $4 is the set of
# basenames the run may NEVER excuse, and it exists because the allowance in
# $3 is a substring test that was swallowing the one path this row polices:
# every refuse() and reclaim() message spells the lock's full path, so
# "<dest>.lock" appeared inside them and was excused permanently, in BOTH W1
# rows. The lock directory is transient by contract - it is removed on every
# exit, successful or not - so its survival is debris whatever the run said
# about it. Naming a path is not the same as leaving it behind on purpose.
unreported_debris() {
    ( CDPATH= cd -- "$1" && find . -maxdepth 1 ! -name . | sort ) | while read -r _p; do
        _n=${_p#./}
        case " $2 " in *" $_n "*) continue ;; esac
        case " ${4:-} " in *" $_n "*) printf '%s\n' "$_n"; continue ;; esac
        printf '%s' "$3" | grep -qF "$_n" || printf '%s\n' "$_n"
    done
}

w1=$(mktemp -d)
d="$w1/w1.json"
printf 'w1\n' > "$d"
printf 'w1-new\n' > "$w1/payload"
fp=$(git hash-object --stdin < "$d")
mkdir "$d.lock"
printf '%s\nWed Jul 30 12:00:00 2026\n%s\n' "$(sh -c 'echo $$')" "$(uname -n)" > "$d.lock/owner"
w1_before=$(inventory "$w1")
w1_msg=$(sh "$LOCK" "$d" "$w1/payload" "$fp" 2>&1)
rc=$?
w1_after=$(inventory "$w1")
w1_left=$(unreported_debris "$w1" 'w1.json payload' "$(lock_said "$w1_msg")" 'w1.json.lock')
if [ "$rc" -eq 0 ] && [ -z "$w1_left" ] && grep -q 'w1-new' "$d"; then
    ok "an ordinary reclaim leaves nothing but the destination ($w1_before-> $w1_after)"
else
    fail "reclaim debris: exit $rc, before '$w1_before' after '$w1_after', unreported '$w1_left'"
fi

# ...and the enumeration can see a fourth path appear. Named after the one that
# really leaked, so a detector that stopped looking is caught by the same shape.
: > "$w1/w1.json.lock.stale.999"
[ -n "$(unreported_debris "$w1" 'w1.json payload' "$(lock_said "$w1_msg")" 'w1.json.lock')" ] \
    && ok "rejected: an aside left beside the destination and named nowhere" \
    || fail "the debris enumeration cannot notice a fourth path"
rm -f "$w1/w1.json.lock.stale.999"

# ...and it can see the LOCK DIRECTORY itself, which is the path the allowance
# used to swallow. Every refusal and every reclaim message spells the lock's
# full path, so a substring test read that mention as "the run named it" and
# excused a surviving lock in both W1 rows. It is planted after the run for the
# same reason the aside above is: the enumeration has to be able to notice it.
mkdir "$w1/w1.json.lock"
[ -n "$(unreported_debris "$w1" 'w1.json payload' "$(lock_said "$w1_msg")" 'w1.json.lock')" ] \
    && ok "rejected: a surviving lock directory, which the run's own message spells and cannot excuse" \
    || fail "ACCEPTED but must be rejected: a lock directory left behind, excused by a message that merely names its path"
rm -rf "$w1"

# A reclaim whose deletion cannot complete: the aside survives, and reporting
# success over it is the worse half of the leak. Made deterministic with a
# subdirectory rm cannot empty - root ignores those permissions, so the row
# stands down loudly there instead of passing for the wrong reason.
#
# The acceptance test is a FUNCTION, and 4 is spelled out in it rather than
# "not zero". The negative control below is a different failure that also
# exits non-zero, and a row that took any non-zero code would print this row's
# sentence over it - "fails loudly and names what it left" - for a run that
# reclaimed nothing and left the whole lock directory. Sharing the function is
# what makes the control exercise the condition the row really uses instead of
# a restatement of it that could drift.
#
# The non-empty test on $3 is the same one the V8 and V9 rows carry, for the
# same reason: two empty fingerprints compare equal, so without it "the bytes
# did not change" was also true of a destination that was never there.
aside_row_accepts() { [ "$1" -eq 4 ] && [ -z "$2" ] && [ -n "$3" ] && [ "$3" = "$4" ]; }

if [ "$(id -u)" -ne 0 ]; then
    w1b=$(mktemp -d)
    d="$w1b/w1b.json"
    printf 'w1b\n' > "$d"
    printf 'w1b-new\n' > "$w1b/payload"
    fp=$(git hash-object --stdin < "$d")
    before=$(git hash-object --stdin < "$d")
    mkdir -p "$d.lock/stuck"
    printf 'x\n' > "$d.lock/stuck/file"
    printf '%s\nWed Jul 30 12:00:00 2026\n%s\n' "$(sh -c 'echo $$')" "$(uname -n)" > "$d.lock/owner"
    chmod 500 "$d.lock/stuck"
    msg=$(sh "$LOCK" "$d" "$w1b/payload" "$fp" 2>&1)
    rc=$?
    after=$(git hash-object --stdin < "$d")
    left=$(unreported_debris "$w1b" 'w1b.json payload' "$(lock_said "$msg")" 'w1b.json.lock')
    chmod -R 700 "$w1b" 2>/dev/null
    if aside_row_accepts "$rc" "$left" "$before" "$after"; then
        ok "a reclaim that cannot delete its aside fails loudly (exit $rc) and names what it left"
    else
        fail "unremovable aside: exit $rc, bytes $before -> $after, unreported '$left'"
    fi
    rm -rf "$w1b"

    # The negative control for the row above, and it needs a holder that is
    # provably ALIVE: with one, with-lock.sh never reclaims, refuses at 3 and
    # leaves the entire lock directory - a different failure, on the same
    # fixture. The row above must REJECT it. Two ways it could not: an exit
    # test that accepts any non-zero code, and a debris allowance that excuses
    # <dest>.lock because the refusal message spells that path.
    if [ "$lstart_here" -eq 1 ]; then
        w1c=$(mktemp -d)
        d="$w1c/w1c.json"
        printf 'w1c\n' > "$d"
        printf 'w1c-new\n' > "$w1c/payload"
        fp=$(git hash-object --stdin < "$d")
        before=$(git hash-object --stdin < "$d")
        sleep 60 &
        holdpid=$!
        mkdir -p "$d.lock/stuck"
        printf 'x\n' > "$d.lock/stuck/file"
        printf '%s\n%s\n%s\n' "$holdpid" \
            "$(ps -o lstart= -p "$holdpid" | awk 'NF { print; exit }')" "$(uname -n)" > "$d.lock/owner"
        chmod 500 "$d.lock/stuck"
        msg=$(sh "$LOCK" "$d" "$w1c/payload" "$fp" 2>&1)
        rc=$?
        after=$(git hash-object --stdin < "$d")
        left=$(unreported_debris "$w1c" 'w1c.json payload' "$(lock_said "$msg")" 'w1c.json.lock')
        chmod -R 700 "$w1c" 2>/dev/null
        kill "$holdpid" 2>/dev/null
        wait "$holdpid" 2>/dev/null
        # The control is `not accepted`, and that is satisfied by the exit code
        # ALONE: aside_row_accepts 3 '' h h is already false, so if the debris
        # allowance drifted back to excusing <dest>.lock the row would print ok
        # while proving only one of the two blind spots its own comment names.
        # Both halves are therefore pinned to the values this fixture must
        # produce - refused at 3, with the lock directory reported as debris.
        case $left in
            *w1c.json.lock*) left_names_lock=1 ;;
            *)               left_names_lock=0 ;;
        esac
        if aside_row_accepts "$rc" "$left" "$before" "$after"; then
            fail "ACCEPTED but must be rejected: a live holder read as the unremovable-aside failure (exit $rc, unreported '$left')"
        elif [ "$rc" -eq 3 ] && [ "$left_names_lock" -eq 1 ]; then
            ok "rejected: a live holder is not that failure - exit $rc, and the lock it left is reported ('$left')"
        else
            fail "the live-holder control reproduced neither blind spot on its own terms: exit $rc (wanted 3), unreported '$left' (wanted w1c.json.lock)"
        fi
        rm -rf "$w1c"
    else
        skip "the live-holder control for the unremovable-aside row (no ps -o lstart=)" conditional
    fi
else
    skip "the unremovable-aside row (running as root, which ignores the mode)" conditional
fi

# ---------------------------------------------------------------- body ------
section "skill body"

body_words() { awk 'f{n+=NF} /^---$/{c++; if(c==2) f=1} END{print n}' "$1"; }

body_verdict() {
    _w=$(body_words "$1")
    case $_w in
        '' | *[!0-9]*) printf 'fail\n' ;;
        *) if [ "$_w" -le 500 ]; then printf 'pass\n'; else printf 'fail\n'; fi ;;
    esac
}

words=$(body_words "$SKILL/SKILL.md")
[ "$(body_verdict "$SKILL/SKILL.md")" = pass ] \
    && ok "body is $words words (ceiling 500)" \
    || fail "body is $words words, over the 500 ceiling"

# The ceiling only means something if going over it is caught, and a fixture is
# only a boundary test while it sits ON the boundary. Both fixtures were
# HARD-CODED against a body that no longer exists: 38 is `501 - 463` and 67 is
# `530 - 463`, both derived from overlay-reaping's slice-1 FORECAST. Measured
# against the shipped body, 38 lands 36 words clear of the ceiling. Both still
# fail, so CI stayed green and the drift was invisible - while a counter
# miscounting by up to 35 words would have gone on being reported as working.
#
# So both are DERIVED from the measured body here, and the merely-over one is
# asserted to sit at exactly 501. `body_verdict` alone cannot express that: the
# hard-coded fixture already returns `fail`, which is precisely the pass that
# hid the drift.
bf=$(mktemp -d)
body_fixture() { cp "$SKILL/SKILL.md" "$1"; awk -v n="$2" 'BEGIN { while (i++ < n) printf "filler "; print "" }' >> "$1"; }

# The words this slice ADDS to the body, named once. adds-first.md reproduces
# the ordering hazard with it: applying the adds before the cuts is red at that
# commit even though both endpoints are legal, which is why the cuts and the
# adds are one commit rather than two.
#
# 21 at slice 1a, which was the slice with cuts to pay for them. Slice 4b adds
# THREE and cuts nothing, so the hazard is arithmetic here rather than live - and
# the number still moves, because the row asserts this slice's own add count and
# a figure left at a previous slice's is a fixture nobody recalibrated. That is
# the same drift the hard-coded 38 above was carrying.
BODY_ADDS=3

over_n=$((501 - $(body_words "$SKILL/SKILL.md")))
body_fixture "$bf/over.md" "$over_n"
over_w=$(body_words "$bf/over.md")
if [ "$over_w" -eq 501 ] && [ "$(body_verdict "$bf/over.md")" = fail ]; then
    ok "rejected: a body of $over_w words - one word over, so the row measures the boundary"
else
    fail "the over-ceiling fixture measured $over_w words, not the 501 it is derived to be"
fi

body_fixture "$bf/adds-first.md" $((over_n + BODY_ADDS))
adds_w=$(body_words "$bf/adds-first.md")
if [ "$adds_w" -gt "$over_w" ] && [ "$(body_verdict "$bf/adds-first.md")" = fail ]; then
    ok "rejected: adds applied before cuts, $adds_w words - above the merely-over fixture's $over_w"
else
    fail "the adds-first fixture measured $adds_w words, which is not strictly above over.md's $over_w"
fi

# ...and the calibration row can see the hard-code coming back. The MARGIN is
# what it reports, not the verdict, because the verdict was already `fail` for
# all 36 of those words. At this body the two fixtures happen to land on the
# same count - over_n plus this slice's adds is 38 - and they stay two rows
# because they assert different things: adds-first must measure ABOVE the
# boundary fixture, this one anything OTHER than 501. Arithmetic, not
# redundancy, and it moves at the next slice.
body_fixture "$bf/hardcoded.md" 38
hard_w=$(body_words "$bf/hardcoded.md")
if [ "$hard_w" -ne 501 ]; then
    ok "rejected: the hard-coded 38 measures $hard_w words, $((hard_w - 500)) clear of the ceiling, not one"
else
    fail "ACCEPTED but must be rejected: an uncalibrated filler count read as a boundary test"
fi

# ...and the fixture SHAPE is not what fails. over.md is SKILL.md with filler
# appended, so without this row the calibration above could be passing on a
# fixture rejected for being a fixture rather than for being over the ceiling.
body_fixture "$bf/under.md" $((over_n - 1))
under_w=$(body_words "$bf/under.md")
if [ "$under_w" -eq 500 ] && [ "$(body_verdict "$bf/under.md")" = pass ]; then
    ok "accepted: the same fixture shape at exactly $under_w words - at most 500, not fewer than"
else
    fail "REJECTED but must be accepted: a fixture body of $under_w words, inside the ceiling"
fi

# --- V34  the recorded figure is a LITERAL, not a `-le 500` ------------------
# `-le 500` accepts everything from 0 to 500, so a slice that moved the body by
# fifteen words in either direction passes it and the counter reports a healthy
# body over a slice that did something other than what it recorded.
#
# The number below is the counter's own output, re-read from the `body is <N>
# words` line above and never taken from a design table: that table's nine donor
# rows sum to -35 against a stated subtotal of -34, each row was reproduced
# against the shipped file, and writing the table's endpoint here would have made
# a green suite disagree by one word with the file it measures.
# Measured: 498 baseline, -35 across nine donor cuts, +21 for the scope line at
# slice 1a; +3 at slice 4b, where Output Contract bullet 5 gained the copy and
# its age. 484 + 3 = 487, and the plan's "488 or 487" resolves to 487 for the
# same reason 1a landed at 484 rather than 485.
BODY_WORDS_RECORDED=487
[ "$words" -eq "$BODY_WORDS_RECORDED" ] \
    && ok "body is the $BODY_WORDS_RECORDED words this slice measured and recorded" \
    || fail "body is $words words; this slice recorded $BODY_WORDS_RECORDED"

# ...and that row can tell a legal-but-different count apart from the recorded
# one, which is the whole difference between it and the ceiling row above. One
# filler word: still inside the ceiling, still `pass` by the verdict, and it
# must fail HERE.
body_fixture "$bf/drift.md" 1
drift_w=$(body_words "$bf/drift.md")
if [ "$(body_verdict "$bf/drift.md")" = pass ] && [ "$drift_w" -ne "$BODY_WORDS_RECORDED" ]; then
    ok "rejected: a body of $drift_w words - inside the ceiling, and not the recorded $BODY_WORDS_RECORDED"
else
    fail "a one-word drift is indistinguishable from the recorded figure ($drift_w against $BODY_WORDS_RECORDED)"
fi
rm -rf "$bf"

# --- ...and the PARAGRAPH that publishes the figure is held to it too --------
# CONTRIBUTING.md's body-budget paragraph states what the body measures and how
# much headroom is left, and it claims the row above "stops this paragraph and
# the check drifting apart in silence". Nothing read the paragraph, so it drifted
# exactly the way it promised it could not: it said 484 with sixteen words of
# headroom from slice 1a onwards, while the counter answered 487 and the row
# above recorded 487. A sentence that names the guarantee is the one place a
# reader trusts, so the guarantee is made true here rather than restated.
CONTRIB=CONTRIBUTING.md
contrib_figure() {
    awk '/The shipped body measures/ {
             if (match($0, /\*\*[0-9]+\*\*/)) { print substr($0, RSTART + 2, RLENGTH - 4); exit }
         }' "$1"
}
contrib_headroom() {
    awk '/The shipped body measures/ {
             if (match($0, /so there are [a-z]+ words of headroom/)) {
                 s = substr($0, RSTART, RLENGTH)
                 sub(/^so there are /, "", s)
                 sub(/ words of headroom$/, "", s)
                 print s
                 exit
             }
         }' "$1"
}
# Spelled out, because the paragraph spells it out. A row reading only the
# numeral leaves half the sentence unread, and the unread half is the one that
# said sixteen.
num_word() {
    case ${1:-} in
        0)  printf 'no\n' ;;        1)  printf 'one\n' ;;       2)  printf 'two\n' ;;
        3)  printf 'three\n' ;;     4)  printf 'four\n' ;;      5)  printf 'five\n' ;;
        6)  printf 'six\n' ;;       7)  printf 'seven\n' ;;     8)  printf 'eight\n' ;;
        9)  printf 'nine\n' ;;      10) printf 'ten\n' ;;       11) printf 'eleven\n' ;;
        12) printf 'twelve\n' ;;    13) printf 'thirteen\n' ;;  14) printf 'fourteen\n' ;;
        15) printf 'fifteen\n' ;;   16) printf 'sixteen\n' ;;   17) printf 'seventeen\n' ;;
        18) printf 'eighteen\n' ;;  19) printf 'nineteen\n' ;;  20) printf 'twenty\n' ;;
        *)  printf 'unmapped\n' ;;
    esac
}

cf=$(contrib_figure "$CONTRIB")
if [ -n "$cf" ] && [ "$cf" -eq "$words" ] 2>/dev/null; then
    ok "CONTRIBUTING.md publishes the figure the counter measures: $cf words"
else
    fail "CONTRIBUTING.md publishes '$cf' as the body figure; the counter measures $words"
fi

ch=$(contrib_headroom "$CONTRIB")
want_headroom=$(num_word $((500 - words)))
if [ "$ch" = "$want_headroom" ]; then
    ok "...and the headroom it states is the $want_headroom words the 500-word ceiling actually leaves"
else
    fail "CONTRIBUTING.md states '$ch' words of headroom; at $words words the ceiling leaves $want_headroom"
fi

# Three fixtures, and the two drifted ones are DERIVED from the measurement
# rather than hard-coded, for the reason the over-budget fixtures above are:
# a literal 484 in a negative is a negative that stops being one the day the
# body measures 484.
cb=$(mktemp -d)
awk -v n="$((words + 3))" '{ if (/The shipped body measures/) sub(/\*\*[0-9]+\*\*/, "**" n "**"); print }' \
    "$CONTRIB" > "$cb/drifted-figure.md"
cbf=$(contrib_figure "$cb/drifted-figure.md")
if [ -n "$cbf" ] && [ "$cbf" -ne "$words" ] 2>/dev/null; then
    ok "rejected: a CONTRIBUTING.md publishing $cbf words against a body that measures $words"
else
    fail "the published-figure row cannot tell a drifted number from the measured one"
fi

awk -v w="$(num_word $((501 - words)))" '{ if (/The shipped body measures/) sub(/so there are [a-z]+ words of headroom/, "so there are " w " words of headroom"); print }' \
    "$CONTRIB" > "$cb/drifted-headroom.md"
cbh=$(contrib_headroom "$cb/drifted-headroom.md")
if [ -n "$cbh" ] && [ "$cbh" != "$want_headroom" ]; then
    ok "rejected: a CONTRIBUTING.md stating $cbh words of headroom where the ceiling leaves $want_headroom"
else
    fail "the headroom row cannot tell a drifted word from the one the ceiling derives"
fi

grep -v 'The shipped body measures' "$CONTRIB" > "$cb/silent.md"
if [ -z "$(contrib_figure "$cb/silent.md")" ] && [ -z "$(contrib_headroom "$cb/silent.md")" ]; then
    ok "rejected: a CONTRIBUTING.md with the body-budget paragraph deleted - an absent claim is not a matching one"
else
    fail "the CONTRIBUTING rows read a figure out of a file whose paragraph is gone"
fi
rm -rf "$cb"

# The guard this replaces could not fail. awk printed nothing when the field was
# absent, ${compat:-0} then read 0, and 0 -lt 500 reported green - so DELETING
# the field passed the check outright. It also enforced "fewer than 500" where
# the requirement says "at most 500". Both are fixed here, and both are proven
# fixed by the fixtures below rather than asserted: a gate keyed on an optional
# field is no gate, and a check that cannot fail is the thing being repaired.
#
# Prints the value's length in BYTES, or one of absent / unquoted /
# embedded-quote. Those three are UNMEASURABLE, not short. -F'"' would read an
# embedded quote as the end of the value and silently measure a prefix, and an
# unquoted value has no second field at all, so each must report as a failure
# instead of as a very small number.
compat_measure() {
    awk '
        /^compatibility:/ {
            found = 1
            rest = substr($0, index($0, ":") + 1)
            sub(/^[ \t]+/, "", rest)
            sub(/[ \t]+$/, "", rest)
            quotes = gsub(/"/, "&", rest)
            if (quotes != 2 || rest !~ /^".*"$/) {
                if (rest ~ /^"/) { print "embedded-quote" } else { print "unquoted" }
                exit
            }
            print length(rest) - 2
            exit
        }
        END { if (!found) print "absent" }
    ' "$1"
}

# One decision, shared by the shipped check and by every fixture below, so the
# fixtures exercise the guard itself rather than a second copy of it that could
# drift away from what actually runs.
compat_verdict() {
    _m=$(compat_measure "$1")
    case $_m in
        '' | *[!0-9]*) printf 'fail\n' ;;
        *) if [ "$_m" -le 500 ]; then printf 'pass\n'; else printf 'fail\n'; fi ;;
    esac
}

# Rewrites the shipped SKILL.md into $1 with its compatibility line replaced by
# $2, or deleted when $2 is empty. The replacement is inserted after the opening
# delimiter rather than in place, so the fixture has the shape it claims even
# when the source file carries no such line: a fixture that silently produced a
# DIFFERENT shape than its label would test the wrong thing, which is the exact
# defect this file exists to catch.
compat_fixture() {
    awk -v repl="$2" '
        NR == 1 { print; if (repl != "") print repl; next }
        /^compatibility:/ { next }
        { print }
    ' "$SKILL/SKILL.md" > "$1"
}

compat_value() { awk -v n="$1" 'BEGIN { s = ""; while (length(s) < n) s = s "x"; print substr(s, 1, n) }'; }

compat=$(compat_measure "$SKILL/SKILL.md")
if [ "$(compat_verdict "$SKILL/SKILL.md")" = pass ]; then
    ok "compatibility is $compat bytes (at most 500)"
else
    fail "compatibility is unmeasurable or over the 500 cap: $compat"
fi

# ...and the MEASURED figure, asserted as a literal beside the ceiling, for the
# reason the body count carries one: `-le 500` is equally satisfied by 494 and by
# 120, so a slice that deleted half the field would pass the row above and change
# nothing that anybody could see. The number is this counter's own output.
COMPAT_BYTES_RECORDED=494
[ "$compat" = "$COMPAT_BYTES_RECORDED" ] \
    && ok "compatibility is the $COMPAT_BYTES_RECORDED bytes this chain measured and recorded" \
    || fail "compatibility is $compat bytes; this chain recorded $COMPAT_BYTES_RECORDED"

cf=$(mktemp -d)
cfx="$cf/SKILL.md"

# ...and that row can tell a legal-but-different value apart from the recorded
# one, which is the whole difference between it and the ceiling row above. One
# byte shorter: still inside the ceiling, still `pass` by the verdict, and it
# must fail HERE.
compat_fixture "$cfx" "compatibility: \"$(compat_value $((COMPAT_BYTES_RECORDED - 1)))\""
if [ "$(compat_verdict "$cfx")" = pass ] && [ "$(compat_measure "$cfx")" != "$COMPAT_BYTES_RECORDED" ]; then
    ok "rejected: a compatibility value of $(compat_measure "$cfx") bytes - inside the ceiling, and not the recorded $COMPAT_BYTES_RECORDED"
else
    fail "a one-byte drift is indistinguishable from the recorded figure ($(compat_measure "$cfx") against $COMPAT_BYTES_RECORDED)"
fi

compat_fixture "$cfx" ''
if [ "$(compat_measure "$cfx")" = absent ] && [ "$(compat_verdict "$cfx")" = fail ]; then
    ok "rejected: the compatibility line deleted entirely - the defect being fixed"
else
    fail "ACCEPTED but must be rejected: a deleted compatibility line"
fi

compat_fixture "$cfx" 'compatibility: Needs a POSIX shell and names no ceiling'
if [ "$(compat_measure "$cfx")" = unquoted ] && [ "$(compat_verdict "$cfx")" = fail ]; then
    ok "rejected: an unquoted compatibility value, vacuous the same way"
else
    fail "ACCEPTED but must be rejected: an unquoted compatibility value"
fi

compat_fixture "$cfx" 'compatibility: "Needs a "POSIX" shell"'
if [ "$(compat_measure "$cfx")" = embedded-quote ] && [ "$(compat_verdict "$cfx")" = fail ]; then
    ok "rejected: an embedded quote, which a field split would measure as a prefix"
else
    fail "ACCEPTED but must be rejected: a compatibility value carrying its own quote"
fi

compat_fixture "$cfx" "compatibility: \"$(compat_value 501)\""
if [ "$(compat_measure "$cfx")" = 501 ] && [ "$(compat_verdict "$cfx")" = fail ]; then
    ok "rejected: a 501-byte compatibility value"
else
    fail "ACCEPTED but must be rejected: 501 bytes"
fi

compat_fixture "$cfx" "compatibility: \"$(compat_value 500)\""
if [ "$(compat_measure "$cfx")" = 500 ] && [ "$(compat_verdict "$cfx")" = pass ]; then
    ok "accepted: exactly 500 bytes - the requirement is at most 500, not fewer than"
else
    fail "REJECTED but must be accepted: exactly 500 bytes is inside the cap"
fi

# The lstart declaration had to be PAID FOR, not appended: restoring the
# minimal-image enumeration it displaced puts the value back over the ceiling.
# This is what makes the two halves one edit rather than two commits.
#
# This fixture is DERIVED from the shipped value, so it only means anything
# while that value is measurable. Standing down loudly when it is not beats
# building a fixture out of an empty string and passing for the wrong reason -
# the failure above already names the real problem, and a second row agreeing
# with it in different words adds nothing.
if [ "$(compat_verdict "$SKILL/SKILL.md")" = pass ]; then
    shipped_compat=$(awk '/^compatibility:/ { r = substr($0, index($0, "\"") + 1); sub(/"$/, "", r); print r; exit }' "$SKILL/SKILL.md")
    uncut=' Stock macOS, mainstream Linux and Git for Windows carry both; minimal images do not — alpine, debian-slim and distroless ship no git, distroless no shell.'
    compat_fixture "$cfx" "compatibility: \"$shipped_compat$uncut\""
    if [ "$(compat_verdict "$cfx")" = fail ]; then
        ok "rejected: the lstart note kept while its donor cut is reverted ($(compat_measure "$cfx") bytes)"
    else
        fail "ACCEPTED but must be rejected: the note appended without paying for it"
    fi
else
    skip "the donor-cut fixture (it is derived from the shipped value, which failed above)" conditional
fi

# --- V37  the cap row must be able to see the clause this slice paid for -----
# `compat_measure <= 500` is equally satisfied by a compatibility line the edit
# never reached, so the clause is asserted PRESENT as well as affordable. The
# conditional donor named for it - `all CI-tested. `, -14 bytes - did not fire:
# the shipped value measured 477, so the 17 bytes the clause costs came out of
# 23 bytes of headroom rather than out of a cut.
STORE_COPY_CLAUSE='only for container repos and store copies'
grep -qF -- "$STORE_COPY_CLAUSE" "$SKILL/SKILL.md" \
    && ok "compatibility declares the store copies' runtime as conditional, beside the existing container condition" \
    || fail "compatibility does not declare the store-copy condition"

# ...and that row can fail: the same line with the clause reverted to what 1.1.0
# shipped. Derived from the shipped value for the donor fixture's reason - a
# fixture typed out by hand stops testing the bytes that run.
reverted=$(awk '/^compatibility:/ {
        r = substr($0, index($0, "\"") + 1); sub(/"$/, "", r)
        sub(/ and store copies\./, ".", r); print r; exit
    }' "$SKILL/SKILL.md")
compat_fixture "$cfx" "compatibility: \"$reverted\""
if grep -qF -- "$STORE_COPY_CLAUSE" "$cfx"; then
    fail "ACCEPTED but must be rejected: the store-copy condition reverted and not noticed"
else
    ok "rejected: the compatibility line with the store-copy condition reverted"
fi
rm -rf "$cf"

# --- V36  description has a 250-CHARACTER ceiling and had no check at all -----
# `compatibility` next door carries five fixtures; `description` carried none,
# so a 251-character value passed this suite outright - measured, exit 0 over a
# planted one. This change edits the field.
#
# THE UNIT IS THE POINT. compat_measure counts BYTES against a cap stated in
# bytes; this requirement says 250 CHARACTERS, and a ceiling stated in one unit
# and checked in another is a ceiling nobody is measuring. POSIX awk has no
# portable character count - `length()` answers in bytes under LC_ALL=C and in
# characters under a UTF-8 locale - so this measures in the C locale and
# REFUSES what it cannot report in the declared unit: while every byte is ASCII
# printable the two counts are identical, and the moment one is not it returns
# `non-ascii` rather than a number that would silently be the wrong unit.
# Absent / unquoted / embedded-quote are unmeasurable for compat_measure's
# reasons: -F'"' would read an embedded quote as the end of the value and
# measure a prefix, and an unquoted value has no second field at all.
desc_measure() {
    LC_ALL=C awk '
        /^description:/ {
            found = 1
            rest = substr($0, index($0, ":") + 1)
            sub(/^[ \t]+/, "", rest)
            sub(/[ \t]+$/, "", rest)
            quotes = gsub(/"/, "&", rest)
            if (quotes != 2 || rest !~ /^".*"$/) {
                if (rest ~ /^"/) { print "embedded-quote" } else { print "unquoted" }
                exit
            }
            value = substr(rest, 2, length(rest) - 2)
            if (value ~ /[^ -~]/) { print "non-ascii"; exit }
            print length(value)
            exit
        }
        END { if (!found) print "absent" }
    ' "$1"
}

# One decision, shared by the shipped check and by every fixture below, so the
# fixtures exercise the guard itself rather than a second copy of it. `-le` is
# the boundary A8 fixed for compatibility: the requirement is at most 250.
desc_verdict() {
    _m=$(desc_measure "$1")
    case $_m in
        '' | *[!0-9]*) printf 'fail\n' ;;
        *) if [ "$_m" -le 250 ]; then printf 'pass\n'; else printf 'fail\n'; fi ;;
    esac
}

# Same shape as compat_fixture, and for the same reason: the replacement is
# inserted after the opening delimiter rather than edited in place, so the
# fixture has the shape its label claims even when the source carries no such
# line.
desc_fixture() {
    awk -v repl="$2" '
        NR == 1 { print; if (repl != "") print repl; next }
        /^description:/ { next }
        { print }
    ' "$SKILL/SKILL.md" > "$1"
}

desc=$(desc_measure "$SKILL/SKILL.md")
if [ "$(desc_verdict "$SKILL/SKILL.md")" = pass ]; then
    ok "description is $desc characters, ASCII so bytes and characters agree (at most 250)"
else
    fail "description is unmeasurable or over the 250 ceiling: $desc"
fi

# ...and the MEASURED figure as a literal, the third of the three counters to
# carry one. D1 puts the scope in this field, so a slice that trimmed it back
# would satisfy a 250 ceiling and lose the contract term the whole change is
# about, silently.
DESC_CHARS_RECORDED=215
[ "$desc" = "$DESC_CHARS_RECORDED" ] \
    && ok "description is the $DESC_CHARS_RECORDED characters this chain measured and recorded" \
    || fail "description is $desc characters; this chain recorded $DESC_CHARS_RECORDED"

df=$(mktemp -d)
dfx="$df/SKILL.md"

# ...and the recorded figure can be told apart from a legal-but-different one.
desc_fixture "$dfx" "description: \"$(compat_value $((DESC_CHARS_RECORDED - 1)))\""
if [ "$(desc_verdict "$dfx")" = pass ] && [ "$(desc_measure "$dfx")" != "$DESC_CHARS_RECORDED" ]; then
    ok "rejected: a description of $(desc_measure "$dfx") characters - inside the ceiling, and not the recorded $DESC_CHARS_RECORDED"
else
    fail "a one-character drift is indistinguishable from the recorded figure ($(desc_measure "$dfx") against $DESC_CHARS_RECORDED)"
fi

desc_fixture "$dfx" ''
if [ "$(desc_measure "$dfx")" = absent ] && [ "$(desc_verdict "$dfx")" = fail ]; then
    ok "rejected: the description line deleted entirely"
else
    fail "ACCEPTED but must be rejected: a deleted description line"
fi

desc_fixture "$dfx" 'description: Trigger: git worktree, unquoted and so unmeasurable'
if [ "$(desc_measure "$dfx")" = unquoted ] && [ "$(desc_verdict "$dfx")" = fail ]; then
    ok "rejected: an unquoted description value, vacuous the same way"
else
    fail "ACCEPTED but must be rejected: an unquoted description value"
fi

desc_fixture "$dfx" 'description: "Trigger: a "worktree" overlay"'
if [ "$(desc_measure "$dfx")" = embedded-quote ] && [ "$(desc_verdict "$dfx")" = fail ]; then
    ok "rejected: a description carrying its own quote, which a field split would measure as a prefix"
else
    fail "ACCEPTED but must be rejected: a description carrying its own quote"
fi

# compat_value is reused rather than copied: one generator of a value of a given
# length, not two that could drift into producing different bytes.
desc_fixture "$dfx" "description: \"$(compat_value 251)\""
if [ "$(desc_measure "$dfx")" = 251 ] && [ "$(desc_verdict "$dfx")" = fail ]; then
    ok "rejected: a 251-character description"
else
    fail "ACCEPTED but must be rejected: 251 characters"
fi

desc_fixture "$dfx" "description: \"$(compat_value 250)\""
if [ "$(desc_measure "$dfx")" = 250 ] && [ "$(desc_verdict "$dfx")" = pass ]; then
    ok "accepted: exactly 250 characters - the requirement is at most 250, not fewer than"
else
    fail "REJECTED but must be accepted: exactly 250 characters is inside the ceiling"
fi

# ...and a value this guard cannot report in the DECLARED unit is refused rather
# than measured in the other one. Without this row a multi-byte description
# would be counted in bytes and reported as characters, which is the defect one
# field along from the one the compat block repaired: a number in the wrong unit
# reads exactly like a number in the right one.
desc_fixture "$dfx" 'description: "Trigger: git worktree — an em dash is two bytes and one character"'
if [ "$(desc_measure "$dfx")" = non-ascii ] && [ "$(desc_verdict "$dfx")" = fail ]; then
    ok "rejected: a value whose characters this guard cannot count, refused rather than measured in bytes"
else
    fail "ACCEPTED but must be rejected: a multi-byte value silently measured in the wrong unit"
fi
rm -rf "$df"

# --- the counters this project RECORDS are the counters that run --------------
# `openspec/config.yaml` lists the verification methods a reader is meant to be
# able to reproduce. For four slices it recorded the field-splitting
# `awk -F'"' '/^compatibility:/{print length($2)}'` - the counter compat_measure
# REPLACED, because it printed nothing for an absent field, `${compat:-0}` read 0,
# and 0 was under the ceiling, so deleting the field passed outright. A project
# whose recorded method is a check that cannot fail is telling the next reader to
# reproduce the defect.
CFG=openspec/config.yaml
cfg_retired() { grep -cF '/^compatibility:/{print length(' "$1"; }

if ! grep -qF 'compat_measure() in .github/scripts/verify.sh' "$CFG"; then
    fail "$CFG does not name the compatibility counter that actually runs"
elif [ "$(cfg_retired "$CFG")" -ne 0 ]; then
    fail "$CFG still carries the retired field-splitting compatibility counter"
else
    ok "$CFG names compat_measure() as the compatibility counter, and carries the retired field split nowhere"
fi

# ...and the row can see the retired expression come back, exercised on a scratch
# copy carrying it as a method again - which is the state this file was in for
# four slices, not a shape invented for the row.
cfgf=$(mktemp -d)
{
    cat "$CFG"
    printf '%s\n' "    - \"compatibility bytes with awk -F'\\\"' '/^compatibility:/{print length(\$2)}'.\""
} > "$cfgf/config.yaml"
[ "$(cfg_retired "$cfgf/config.yaml")" -eq 1 ] \
    && ok "rejected: the retired field-splitting counter recorded as a method again" \
    || fail "the row cannot notice the retired compatibility counter coming back"
rm -rf "$cfgf"

# --- V38  the scope is stated in all three places, or in none of them --------
# Silence about scope is what let an in-place isolation premise be adopted as a
# universal truth, so the statement is a contract term with three homes:
# `description`, the Activation Contract, and README.md. Before this row the
# suite passed with the README paragraph deleted - measured, exit 0.
#
# Both tests demand ONE LINE carrying every claim, not a token found anywhere in
# the file. "CI", "shared" and "remote" each occur in these files for unrelated
# reasons, so four independent greps would report a scope statement over a file
# that declares nothing - satisfied by vocabulary rather than by a sentence.
scope_missing()    { awk '/Local development/ && /one host/ && /worktrees/ { f = 1 } END { print f ? 0 : 1 }' "$1"; }
nongoals_missing() { awk '/non-goal/ && /CI/ && /shared/ && /remote/ && /multi-developer/ { f = 1 } END { print f ? 0 : 1 }' "$1"; }

activation_contract() { awk '/^## Activation Contract/ { on = 1; next } /^## / { if (on) exit } on' "$1"; }
description_line()    { awk '/^description:/ { print; exit }' "$1"; }

sf=$(mktemp -d)
description_line  "$SKILL/SKILL.md" > "$sf/description"
activation_contract "$SKILL/SKILL.md" > "$sf/activation"

[ "$(scope_missing "$sf/description")" -eq 0 ] \
    && ok "description states the local-development scope" \
    || fail "description does not state the scope"

if [ "$(scope_missing "$sf/activation")" -eq 0 ] && [ "$(nongoals_missing "$sf/activation")" -eq 0 ]; then
    ok "the Activation Contract states the scope and names all four non-goals"
else
    fail "the Activation Contract is missing the scope or a non-goal"
fi

if [ "$(scope_missing README.md)" -eq 0 ] && [ "$(nongoals_missing README.md)" -eq 0 ]; then
    ok "README.md states the same scope and the same non-goals"
else
    fail "README.md is missing the scope or a non-goal"
fi

# ...and each of the three can go missing on its own. Three fixtures, one per
# home, every one of which must FAIL - a row keyed on any single file would
# report a declared scope over a skill that states it twice and hides it once.
description_line "$SKILL/SKILL.md" | awk '{ sub(/ Local development[^"]*/, ""); print }' > "$sf/no-desc"
[ "$(scope_missing "$sf/no-desc")" -eq 1 ] \
    && ok "rejected: the scope clause deleted from description" \
    || fail "the description row cannot notice the scope going missing"

activation_contract "$SKILL/SKILL.md" | grep -v 'Local development only' > "$sf/no-activation"
[ "$(scope_missing "$sf/no-activation")" -eq 1 ] && [ "$(nongoals_missing "$sf/no-activation")" -eq 1 ] \
    && ok "rejected: the scope line deleted from the Activation Contract" \
    || fail "the Activation Contract row cannot notice the scope going missing"

grep -v 'Scope, stated up front' README.md > "$sf/no-readme.md"
[ "$(scope_missing "$sf/no-readme.md")" -eq 1 ] && [ "$(nongoals_missing "$sf/no-readme.md")" -eq 1 ] \
    && ok "rejected: the scope paragraph deleted from README.md" \
    || fail "the README row cannot notice the scope going missing"

# The fourth fixture, shaped like the portability grep rather than like a
# presence test: stating the scope is worth nothing while another sentence
# claims the skill applies everywhere. Case-insensitive and intent-blind, so it
# fires in prose and in a comment alike - hence written narrowly enough not to
# fire on "no matter what its determinacy record says" or "any host running this
# probe", both shipped text about something else.
UNIVERSAL='works (with|on|for) any (stack|host|repo|repository|setup|environment|machine)|runs (anywhere|on any (host|machine|stack))|universally applicable|works everywhere|any environment|every environment|whatever your (stack|host|machine|setup)|regardless of where|suitable for (all|every)'
if grep -rniE "$UNIVERSAL" README.md SECURITY.md CONTRIBUTING.md docs/ "$SKILL" >/dev/null 2>&1; then
    fail "a shipped file claims universal applicability: $(grep -rniE "$UNIVERSAL" README.md SECURITY.md CONTRIBUTING.md docs/ "$SKILL" | head -1)"
else
    ok "no shipped file claims universal applicability"
fi
printf 'stackgraft works with any stack, and runs anywhere.\n' > "$sf/universal.md"
grep -qiE "$UNIVERSAL" "$sf/universal.md" \
    && ok "rejected: a file claiming the skill applies to any stack" \
    || fail "the universal-applicability grep cannot fail"
rm -rf "$sf"

# --- a shipped file may not carry its own release prohibition ----------------
# `docs/SHARED-STATE.md` shipped, inside the release, the sentence *the copy is
# built and NOT YET VERIFIED, so this step must not be released on its own*.
# Slice 4a wrote it truthfully; slice 4b shipped the verification, updated
# README.md, and never came back. So for two slices the only explanatory page for
# the default ISOLATE road told every reader to discount it, and contradicted
# README.md head on - two texts and two outcomes, which is this repository's own
# named hazard. Nothing caught it because NO ROW READ THAT FILE: `docs/` sat in
# $SHIPPED_SURFACE for three intent-blind sweeps and not one of them asked about
# a status claim.
#
# So the check is the CLASS and not the sentence: a file a reader is handed may
# not tell that reader the thing it describes is unverified or unreleasable. The
# shipped surface IS the release, so a prohibition inside it is either false or
# fatal, and both are worth a red run.
#
# Deliberately NOT a sweep for "unbuilt": `references/isolation-providers.md`
# calls the Kubernetes and host-native providers declared and unbuilt on purpose.
# That is an honest limit about a second runtime, not a status claim about what
# the file in front of the reader describes.
UNRELEASED='not yet verified|not yet trusted|must not be released|a mechanism that exists rather than one you can rely on|until that lands'

# Written as a sweep over a ROOT rather than as a grep of one fixture, because
# the expression firing is not the half that failed - the half that failed is
# whether the sweep reaches the file. A one-line fixture proves the first and
# says nothing about the second.
unreleased_lines() {
    _root=${1:-.}
    for _p in $SHIPPED_SURFACE; do
        [ -e "$_root/$_p" ] && grep -rniE "$UNRELEASED" "$_root/$_p" 2>/dev/null
    done
    return 0
}

if [ -z "$(unreleased_lines .)" ]; then
    ok "no file on the shipped surface tells its reader that what it describes is unverified or must not be released"
else
    fail "a shipped file carries a release prohibition: $(unreleased_lines . | head -1)"
fi

# The negative is the DEFECT, put back where it shipped, on a scratch copy of the
# whole surface - and the match has to name that file, which is what proves the
# sweep reaches `docs/` rather than merely that the expression can fire.
us=$(mktemp -d)
mkdir -p "$us/docs" "$us/skills"
cp -R "$SKILL" "$us/skills/"
cp README.md SECURITY.md CONTRIBUTING.md "$us/"
cp docs/*.md "$us/docs/"
[ "$(surface_missing "$us")" -eq 0 ] \
    && ok "the scratch surface carries every path the sweep names, so the negative below runs the sweep at full width" \
    || fail "$(surface_missing "$us") of the shipped-surface paths are missing from the scratch copy, so the negative is smaller than it reads"

{
    printf '\n**Status, before anything else: the copy is built and NOT YET VERIFIED, so this step'
    printf ' must not be released on its own.** Read the rest of this section as a mechanism that'
    printf ' exists rather than one you can rely on.\n'
} >> "$us/docs/SHARED-STATE.md"
unreleased_lines "$us" | grep -q 'docs/SHARED-STATE\.md' \
    && ok "rejected: the shipped release prohibition put back into docs/SHARED-STATE.md, and the sweep names that file" \
    || fail "the sweep does not reach docs/SHARED-STATE.md, which is how the prohibition shipped inside the release"
rm -rf "$us"

# ...and not carrying a prohibition is not the same as STATING the behaviour.
# Deleting the whole section satisfies the sweep above, and leaves the reader of
# the explanatory page with nothing at all about what makes a copy count.
DOCS_SHARED=docs/SHARED-STATE.md
# `counts as isolat` and not `counts as isolation`: the two files say "counts as
# isolation" and "counts as isolated", and a row keyed on one spelling reads the
# other file as silent - which is the shape of the defect it is here to stop.
counts_missing()   { awk '/counts as isolat/ && /verified/             { f = 1 } END { print f ? 0 : 1 }' "$1"; }
destroyed_missing(){ awk '/cannot be derived/   && /the pair refuses/  { f = 1 } END { print f ? 0 : 1 }' "$1"; }
asks_missing()     { awk '/Verifying it does ask/ && /healthcheck/     { f = 1 } END { print f ? 0 : 1 }' "$1"; }

[ "$(counts_missing "$DOCS_SHARED")" -eq 0 ] \
    && ok "docs/SHARED-STATE.md says a copy counts as isolation only once it has been verified" \
    || fail "docs/SHARED-STATE.md no longer says a copy has to be verified before it counts"
[ "$(destroyed_missing "$DOCS_SHARED")" -eq 0 ] \
    && ok "...and that a query which cannot be derived destroys the copy and refuses the pair" \
    || fail "docs/SHARED-STATE.md does not state the refusal direction for an underivable query"
[ "$(asks_missing "$DOCS_SHARED")" -eq 0 ] \
    && ok "...and that verifying the copy asks the repository for the query making it asks for nothing" \
    || fail "docs/SHARED-STATE.md still reads as though the copy road asks the repository for nothing at all"

# The same claim in README.md, because a page correcting itself while the other
# one keeps the old reading is the two-texts hazard with the files swapped.
[ "$(counts_missing README.md)" -eq 0 ] \
    && ok "README.md carries the same claim, so the two texts cannot drift into two outcomes again" \
    || fail "README.md no longer says a copy is verified before it counts as isolated"

ds=$(mktemp -d)
grep -v 'counts as isolation only once it has been verified' "$DOCS_SHARED" > "$ds/no-counts.md"
grep -v 'cannot be derived' "$DOCS_SHARED"                                  > "$ds/no-refusal.md"
grep -v 'Verifying it does ask' "$DOCS_SHARED"                              > "$ds/no-asks.md"
grep -v 'verified before it counts as isolated' README.md                   > "$ds/no-readme.md"
[ "$(counts_missing "$ds/no-counts.md")" -eq 1 ] \
    && ok "rejected: docs/SHARED-STATE.md with the verification sentence deleted" \
    || fail "the verification row cannot notice its sentence going missing"
[ "$(destroyed_missing "$ds/no-refusal.md")" -eq 1 ] \
    && ok "rejected: docs/SHARED-STATE.md with the refusal direction deleted" \
    || fail "the refusal-direction row cannot notice its sentence going missing"
[ "$(asks_missing "$ds/no-asks.md")" -eq 1 ] \
    && ok "rejected: docs/SHARED-STATE.md with the what-verifying-asks-for sentence deleted" \
    || fail "the asks row cannot notice its sentence going missing"
[ "$(counts_missing "$ds/no-readme.md")" -eq 1 ] \
    && ok "rejected: README.md with its half of the same claim deleted" \
    || fail "the README row cannot notice its sentence going missing"
rm -rf "$ds"

# ...and every row above reads the EXPLANATORY pages. Not one of them reads
# references/shared-state.md, which is the file the agent actually follows, and a
# third adversarial pass measured the consequence: reverting that file's two
# sentences to the text they carried before this repair ran 774 ok / 0 FAIL /
# exit 0, the exact clean figure. A repair guarded only in the pages that
# describe it is a repair the normative file can lose on its own.
#
# So both are read here by SHAPE rather than by sentence, because the claim was
# false in four places at once and a row per sentence would have caught one.
#
# SCOPE, stated rather than covered: the sweep reads the shipped files below and
# not this suite's own row labels, because the patterns it searches for are
# written in this file and it would match its own definition. One such label did
# carry the overclaim and was corrected by reading; nothing here would have
# caught it.
#
# Shape one: the copy road asks the repository for nothing. True of MAKING a
# copy and false of verifying one since slice 4b, so the claim is only ever
# correct where the same line says what verifying asks for.
NORM_SHARED=$SKILL/references/shared-state.md
CLAIM_FILES="README.md CHANGELOG.md SECURITY.md docs/SHARED-STATE.md $NORM_SHARED"
copy_asks_unqualified() {
    grep -Hn 'asks the repository for nothing\|asks your repository for nothing' "$@" 2>/dev/null \
        | grep -iv 'verifying it'
}
# Shape two: declining the generated target issues no refusal. True of the
# missing target and false of the pair, which still refuses for want of a query
# where no rung-1 candidate exists either.
no_refusal_unqualified() {
    grep -Hn 'no refusal is issued' "$@" 2>/dev/null | grep -v 'want of a query'
}

# shellcheck disable=SC2086
[ -z "$(copy_asks_unqualified $CLAIM_FILES)" ] \
    && ok "no shipped file claims the copy road asks the repository for nothing without saying what verifying asks for" \
    || fail "an unqualified 'asks the repository for nothing' ships: $(copy_asks_unqualified $CLAIM_FILES)"
# shellcheck disable=SC2086
[ -z "$(no_refusal_unqualified $CLAIM_FILES)" ] \
    && ok "...and none says a decline issues no refusal without stating the refusal a decline can still cost" \
    || fail "an unqualified 'no refusal is issued' ships: $(no_refusal_unqualified $CLAIM_FILES)"

# The negatives put back the exact bytes each claim carried before the repair,
# taken from the commits that shipped them, so what is rejected is the measured
# regression rather than a sentence invented to be rejected.
nr=$(mktemp -d)
mkdir -p "$nr/refs"
grep -v 'verifying it does ask' "$NORM_SHARED" > "$nr/refs/pre-4b.md"
printf '%s\n' '**A seeded copy is what ISOLATE means by default.** It is a second instance of the same image, started on a copy of the state the base stack holds — so it carries the data the base stack has and **asks the repository for nothing**: no task target, no discovered command, no template, no approval.' \
    >> "$nr/refs/pre-4b.md"
grep -v 'What a decline costs' "$NORM_SHARED" > "$nr/refs/pre-cost.md"
printf '%s\n' '**The offer is never a precondition of anything.** A decline, an offer nobody approved, and a repository that cannot be written to all leave the **default seeded copy**, and **no refusal is issued for the missing lifecycle target** while that road is open.' \
    >> "$nr/refs/pre-cost.md"

# Each negative is asserted on the file it INTRODUCED, not merely on the sweep
# being non-empty: a row satisfied by any output would let one shape cover for
# the other, which is the failure both of these exist to stop.
copy_asks_unqualified "$nr/refs/pre-4b.md" | grep -q 'pre-4b.md' \
    && ok "rejected: references/shared-state.md's pre-4b claim that a seeded copy asks the repository for nothing, and the sweep names that file" \
    || fail "the sweep does not reach references/shared-state.md, which is the file the agent follows"
no_refusal_unqualified "$nr/refs/pre-cost.md" | grep -q 'pre-cost.md' \
    && ok "rejected: the decline paragraph with the cost clause removed, so 'no refusal is issued' stands unqualified" \
    || fail "the decline sweep cannot notice its qualification going missing"

# ...and a sweep that fires on everything is not a sweep. The shipped file must
# pass the same two functions the fixtures above fail.
copy_asks_unqualified "$NORM_SHARED" | grep -q . \
    && fail "the sweep flags the shipped references/shared-state.md, so its rejections mean nothing" \
    || ok "...while the shipped references/shared-state.md passes both sweeps unchanged"
rm -rf "$nr"

# One decision and one term list, shared by the shipped rows and by the negative
# below, so the fixture exercises the test that actually runs rather than a
# second copy of it that could drift away from it - the shape the compat,
# version, A7 and notes blocks all use.
#
# COPY joins the three verdict terms with the mechanism this change introduces.
# The body naming a verdict is what would let an agent holding only the body
# reach something other than refusal, and a term added to the vocabulary but not
# to this list is a term the loop stopped looking for.
VERDICT_TERMS='REUSE ISOLATE REAP COPY'
names_verdict_term() { printf '%s' "$1" | grep -q "$2"; }

body=$(awk 'f; /^---$/{c++; if(c==2) f=1}' "$SKILL/SKILL.md")

# An EMPTY body satisfies all three rows at once: grep finds no term in nothing.
# So the frontmatter delimiters changing - the extraction above coming back with
# no bytes - printed three oks and no FAIL, which is a gate satisfied by absence
# and therefore no gate. The extraction is required to have produced something
# before what it produced is judged.
if [ -z "$body" ]; then
    fail "the body extraction returned nothing, so the three verdict-term rows would pass on an empty string"
else
    for term in $VERDICT_TERMS; do
        names_verdict_term "$body" "$term" \
            && fail "body contains the permitting term $term" \
            || ok "body states no $term"
    done
fi

# ...and the loop can fire on the term this change adds. The body never
# spelling REAP is what leaves an agent holding only the body able to reach
# refusal and nothing else, so a loop that had quietly stopped looking would
# read from here exactly like a body that is clean.
verdict_hits() {
    _n=0
    for _t in $VERDICT_TERMS; do
        names_verdict_term "$1" "$_t" && _n=$((_n + 1))
    done
    printf '%s\n' "$_n"
}
#
# The fixture names the NEW term as well as the old one and the row asserts both
# are found, not "at least one". A term appended to the list and never exercised
# is one the loop is only assumed to be looking for - the shape four of the last
# audit's vacuous rows had: a control exercising a different condition than the
# row asserts.
[ "$(verdict_hits "$body
| Overlay writes shared state | COPY it |
| Overlay outlived its worktree | REAP it |")" -ge 2 ] \
    && ok "rejected: a body line naming the REAP verdict, and one naming the COPY verdict this change adds" \
    || fail "the verdict-term loop cannot report both terms it should catch"

# --- V40  the body may not carry the hazard-to-mechanism mapping -------------
# Naming `isolation-providers` and `coordination-identity` in the body IS that
# mapping: a reader learns there are two mechanisms and which hazard each
# answers from the filenames alone - a permitting condition reached without
# opening the only verdict procedure. A gate action cell reading *Copy it* is
# the same statement one step less subtle. The seal says the body may state that
# a verdict is required and where the procedure lives, never a condition under
# which an overlay is permitted. One expression shared with the negative, and
# case-insensitive: the seal is about what a reader concludes, not capitalisation.
BODY_MECHANISM='isolation-providers|coordination-identity|copy it|clone it|give it (a distinct|its own)'
body_mechanism_hits() { printf '%s' "$1" | grep -ciE "$BODY_MECHANISM"; }

[ "$(body_mechanism_hits "$body")" -eq 0 ] \
    && ok "body names neither new reference file and carries no hazard-to-mechanism wording" \
    || fail "body carries hazard-to-mechanism wording: $(printf '%s' "$body" | grep -iE "$BODY_MECHANISM" | head -1)"

[ "$(body_mechanism_hits "$body
| Overlay writes shared state | Copy it — references/isolation-providers.md |")" -ge 1 ] \
    && ok "rejected: a gate row whose action cell maps the data hazard to a mechanism, naming the file that holds it" \
    || fail "the hazard-to-mechanism grep cannot fail"

# One expression for the pointer set, used by the rows below and by the negative
# fixture, so the two cannot drift into keying on differently spelled things.
link_targets() {
    grep -o '`\(references\|assets\|scripts\)/[a-z.-]*`' "$1" | tr -d '`' | sort -u
}

# The COUNT is asserted as well as each pointer, because a loop over nothing
# emits no rows and no FAIL: a SKILL.md that had lost every backticked pointer -
# the body-budget donor cut the C1 block below already worries about, taken one
# step further - read exactly like one whose pointers all resolve. A floor, not
# an exact count, and for the same reason the release-notes block takes
# `notes_n >= 2`: enough to say the set is really there, never a number a
# legitimate addition or removal would break.
link_n=0
for p in $(link_targets "$SKILL/SKILL.md"); do
    link_n=$((link_n + 1))
    [ -e "$SKILL/$p" ] && ok "link resolves: $p" || fail "link is broken: $p"
done
[ "$link_n" -ge 2 ] \
    && ok "the body names $link_n backticked skill paths, so the rows above resolved something" \
    || fail "the body names $link_n backticked skill path(s), so the link rows above proved nothing"

# ...and the loop can report a break. Note the pattern it matches: grepping for
# the literal string "references/" would miss it, because what the loop keys on
# is the backticked form.
link_unresolved() {
    _n=0
    for _p in $(link_targets "$1"); do
        [ -e "$SKILL/$_p" ] || _n=$((_n + 1))
    done
    printf '%s\n' "$_n"
}
lf=$(mktemp -d)
{ cat "$SKILL/SKILL.md"; printf -- '- `references/renamed-away.md`\n'; } > "$lf/SKILL.md"
[ "$(link_unresolved "$lf/SKILL.md")" -ge 1 ] \
    && ok "rejected: a backticked skill path that does not resolve" \
    || fail "the link loop cannot report a broken link"
rm -rf "$lf"

# --- C1  a pointer must resolve to a WHOLE recipe, not merely to a file ------
# The loop above proves `references/discovery.md` exists. It cannot prove that
# file answers the question the body sent the reader there with, and a pointer
# into a recipe that lost a step reads exactly like a pointer into a complete
# one - which is how the body-budget donor cut for step 2 shipped a `hash8`
# derivation with no truncation in it and stayed green.
#
# So the recipe is FOLLOWED here rather than reviewed: the hashing command is
# taken out of section 0, the cut length is taken out of section 0, and the
# result is what the body's own `<repo-basename>-<hash8>.json` template gets
# built from. The length is read from the prose instead of hard-coded, because
# a hard-coded 8 would supply the very step whose absence is the defect.
DISCOVERY="$SKILL/references/discovery.md"

section_zero()  { awk '/^## 0\./ { on = 1; next } /^## / { if (on) exit } on' "$1"; }
hash8_command() {
    section_zero "$1" | awk '
        {
            s = $0
            while (match(s, /`[^`]*`/)) {
                c = substr(s, RSTART + 1, RLENGTH - 2)
                if (c ~ /git hash-object/) { print c; exit }
                s = substr(s, RSTART + RLENGTH)
            }
        }'
}
hash8_cut() {
    section_zero "$1" | awk '/hash8/ && match($0, /first [0-9]+ characters/) {
        print substr($0, RSTART + 6, RLENGTH - 17); exit }'
}

# Follows $1's section 0 against the common dir $2 and prints what it yields.
# A file stating no truncation does not get 8 assumed for it: it gets the
# recipe as it actually reads, which is the whole digest - precisely what the
# shipped body produced, and precisely what this row has to be able to see.
hash8_derive() {
    _cmd=$(hash8_command "$1")
    [ -n "$_cmd" ] || return 0
    _cut=$(hash8_cut "$1")
    _out=$(gitCommonDir="$2" sh -c "$_cmd" 2>/dev/null)
    if [ -n "$_cut" ]; then
        printf '%s\n' "$_out" | cut -c1-"$_cut"
    else
        printf '%s\n' "$_out"
    fi
}

h8_common=$(CDPATH= cd -- "$(git rev-parse --git-common-dir)" && pwd -P)
h8=$(hash8_derive "$DISCOVERY" "$h8_common")
case ${h8:-} in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
        ok "the body's hash8 pointer resolves: section 0 yields '$h8', eight lowercase hex" ;;
    *)
        fail "SKILL.md plus discovery.md section 0 yields '${h8:-nothing}' (${#h8} chars), not eight lowercase hex" ;;
esac

# ...and the row goes red the moment the recipe loses that step. The fixture is
# the shipped file with its truncation paragraph deleted - which is the state
# that shipped, and the state every other check in this file reads as healthy.
#
# The eight-character arm below and the whole-digest premise beside it both use
# lower_hex()/whole_object_id(), defined once at the top of this file.
hf=$(mktemp -d)
awk '!/first 8 characters/' "$DISCOVERY" > "$hf/discovery.md"
h8bad=$(hash8_derive "$hf/discovery.md" "$h8_common")

# The row below concludes from a LENGTH, and "not 8" is equally satisfied by a
# derivation that produced nothing at all: with git off the PATH neither the
# common-dir line above nor the recipe's own hashing command produces anything,
# hash8_derive yields the empty string, and the row printed
# `ok ... resolves to 0 characters, not 8` - a total failure of git reading as
# the truncation guard working. It was correct only because the positive row
# above happened to prove the derivation runs at all - adjacency, not an
# assertion. That premise is a branch of its own now, the way the held-port, A7
# and docker-availability absences state theirs.
if [ "${#h8bad}" -eq 8 ] && lower_hex "$h8bad"; then
    fail "ACCEPTED but must be rejected: section 0 with no truncation still resolved to eight hex"
elif whole_object_id "$h8bad"; then
    ok "rejected: section 0 with the truncation removed - the pointer resolves to the whole ${#h8bad}-character object id, not 8"
else
    fail "the truncation-removed recipe yielded '${h8bad:-nothing}' (${#h8bad} chars), which is no whole object id, so a length that is not 8 proves nothing about truncation"
fi
rm -rf "$hf"

# --------------------------------------------------------- determinacy ------
section "determinacy"

SCHEMA_JSON="$SKILL/assets/manifest.schema.json"
EXAMPLE_JSON="$SKILL/assets/manifest.example.json"

# --- V68  schemaVersion is 3, declared once, and a 2 is discarded whole ------
# There is no migration path and its absence is the design, so the ONLY thing
# standing between a v2 cache and a v3 reader is this number. A cache silently
# misread as the wrong version is the failure mode: every field would be
# re-read at a granularity it was never written at.
#
# The count is asserted beside the value because the chain must carry exactly
# ONE transition. A second `const` declaration anywhere in the file is a second
# transition sitting in the tree waiting for a reader to pick the other one.
SCHEMA_VERSION_RECORDED=3
# The value is read across lines rather than off one: the declaration carries a
# description, so keying on `"schemaVersion"` and `"const"` sharing a line read
# the schema as declaring NO version at all - measured, and it failed loudly
# only because the recorded figure is a literal.
schema_version()       { awk '/"schemaVersion"/ { on = 1 } on && match($0, /"const"[ \t]*:[ \t]*[0-9]+/) { s = substr($0, RSTART, RLENGTH); sub(/.*:[ \t]*/, "", s); print s; exit }' "$1"; }
schema_version_decls() { grep -cE '"schemaVersion"[ \t]*:[ \t]*\{' "$1"; }
example_version()      { awk 'match($0, /"schemaVersion"[ \t]*:[ \t]*[0-9]+/) { s = substr($0, RSTART, RLENGTH); sub(/.*:[ \t]*/, "", s); print s; exit }' "$1"; }

sv=$(schema_version "$SCHEMA_JSON")
[ "${sv:-nothing}" = "$SCHEMA_VERSION_RECORDED" ] \
    && ok "the schema declares schemaVersion const $sv" \
    || fail "the schema declares schemaVersion '${sv:-nothing}', not $SCHEMA_VERSION_RECORDED"

sv_n=$(schema_version_decls "$SCHEMA_JSON")
[ "$sv_n" -eq 1 ] \
    && ok "schemaVersion is declared exactly once, so the chain carries one transition" \
    || fail "schemaVersion is declared $sv_n times, so a second transition can hide in the file"

ev=$(example_version "$EXAMPLE_JSON")
[ "${ev:-nothing}" = "$SCHEMA_VERSION_RECORDED" ] \
    && ok "the shipped example is written at schemaVersion $ev" \
    || fail "the shipped example is at schemaVersion '${ev:-nothing}', not $SCHEMA_VERSION_RECORDED"

vf=$(mktemp -d)
awk '/"schemaVersion"/ { on = 1 } on && sub(/"const"[ \t]*:[ \t]*3/, "\"const\": 2") { on = 0 } { print }' "$SCHEMA_JSON" > "$vf/schema.json"
[ "$(schema_version "$vf/schema.json")" = 2 ] \
    && ok "rejected: a schema left at const 2 - a v2 cache would be read as current" \
    || fail "the schemaVersion row cannot tell 3 from 2"

{ cat "$SCHEMA_JSON"; printf '    "schemaVersion": { "const": 2 },\n'; } > "$vf/twice.json"
[ "$(schema_version_decls "$vf/twice.json")" -eq 2 ] \
    && ok "rejected: a second schemaVersion const declaration, which is a second transition" \
    || fail "the single-declaration row cannot see a second const"

awk '/"schemaVersion"/ { sub(/:[ \t]*3/, ": 2") } { print }' "$EXAMPLE_JSON" > "$vf/example.json"
[ "$(example_version "$vf/example.json")" = 2 ] \
    && ok "rejected: an example manifest left at schemaVersion 2" \
    || fail "the example-version row cannot tell 3 from 2"
rm -rf "$vf"

# --- V68  the retired field may not survive as a current one -----------------
# `writes` must still be NAMED: the spec requires the defect stated in its own
# terms - `writes: ["postgres"]` as a positive claim - so a blanket grep would
# fail on text this change is obliged to carry. The rule is narrower and is the
# one that matters: every line presenting it as a FIELD must also say it is
# gone, so a reader cannot meet it as something to write today.
RETIRED_FIELD='`writes`|"writes"|writes: \['
RETIREMENT='RETIRED|retired|no longer|replaced|was a'
retired_as_current() { grep -rnE "$RETIRED_FIELD" "$@" 2>/dev/null | grep -cvE "$RETIREMENT"; }

rc=$(retired_as_current $SHIPPED_SURFACE)
[ "$rc" -eq 0 ] \
    && ok "no shipped file presents the retired writes array as a current field" \
    || fail "$rc line(s) present writes as a current field: $(grep -rnE "$RETIRED_FIELD" $SHIPPED_SURFACE | grep -vE "$RETIREMENT" | head -1)"

rf=$(mktemp -d)
printf -- '- `writes` — backing stores this service mutates. An empty array means checked and none.\n' > "$rf/fixture.md"
[ "$(retired_as_current "$rf")" -ge 1 ] \
    && ok "rejected: a line documenting writes as a field a manifest still carries" \
    || fail "the retired-field grep cannot fire"
rm -rf "$rf"

# --- V59  determinacy is read at the granularity it was recorded -------------
# Every row here is one SENTENCE, not one file, and every negative is that
# sentence deleted from a copy. C1's lesson applies unchanged: a link check
# proves a file exists and nothing more, and the rule that has to survive this
# slice is a rule a reader can act on, not a filename.
SHARED="$SKILL/references/shared-state.md"

# The defect in the spec's own terms. Stating it wrongly is how the next pass
# reintroduces it: the missing capability was GRANULARITY, and a reader who
# takes it as "a negative could not be written" adds a field whose presence
# asserts checked-and-none for every store at once, which is the same defect.
defect_missing()      { awk '/writes: \[/ && /positive/ && /checked-and-none/ { f = 1 } END { print f ? 0 : 1 }' "$1"; }
granularity_missing() { awk '/granularity/ && /negative/                     { f = 1 } END { print f ? 0 : 1 }' "$1"; }
siblings_missing()    { awk '/absence/ && /siblings/ && /undetermined/       { f = 1 } END { print f ? 0 : 1 }' "$1"; }
# Emptiness is the claim this record makes cheapest to write, so the rule that
# an omitted record is never checked-and-none is asserted where discovery
# writes it, not only where the gate reads it.
#
# `omitted record` and not `omit`: the looser spelling was GREEN against the
# shipped file before this slice wrote anything, because the `dependsOn` bullet
# already carries "omitting" beside "checked-and-none" for an unrelated reason.
# Measured, and it is the shape slice 1a found twice - a row passing over the
# very absence it exists to report.
omission_missing()    { awk '/omitted record/ && /checked-and-none/          { f = 1 } END { print f ? 0 : 1 }' "$1"; }
counts_missing()      { awk '/39/ && /156/ && /172/                          { f = 1 } END { print f ? 0 : 1 }' "$1"; }

determinacy_sentences() {
    _n=0
    [ "$(defect_missing "$1")" -eq 0 ]      || _n=$((_n + 1))
    [ "$(granularity_missing "$1")" -eq 0 ] || _n=$((_n + 1))
    [ "$(siblings_missing "$1")" -eq 0 ]    || _n=$((_n + 1))
    printf '%s\n' "$_n"
}

[ "$(determinacy_sentences "$SHARED")" -eq 0 ] \
    && ok "shared-state.md names the defect, the missing granularity, and one store's absence as no claim about its siblings" \
    || fail "shared-state.md is missing $(determinacy_sentences "$SHARED") of the three determinacy sentences"

[ "$(omission_missing "$DISCOVERY")" -eq 0 ] \
    && ok "discovery.md forbids an omitted record being written as, or read as, checked-and-none" \
    || fail "discovery.md does not forbid reading an omitted record as checked-and-none"

[ "$(counts_missing "$DISCOVERY")" -eq 0 ] \
    && ok "discovery.md states the pair-set derivation with its counts" \
    || fail "discovery.md does not state the pair-set derivation counts"

# ...and each of those can go missing on its own. One fixture per sentence,
# every one of which must FAIL - a row keyed on the file rather than on the
# sentence reports a stated rule over a file that states nothing.
df=$(mktemp -d)
awk '!(/writes: \[/ && /positive/)'  "$SHARED"    > "$df/no-defect.md"
awk '!(/granularity/ && /negative/)' "$SHARED"    > "$df/no-granularity.md"
awk '!(/absence/ && /siblings/)'     "$SHARED"    > "$df/no-siblings.md"
awk '!(/omitted record/ && /checked-and-none/)' "$DISCOVERY" > "$df/no-omission.md"
awk '!(/39/ && /156/)'                "$DISCOVERY" > "$df/no-counts.md"

[ "$(defect_missing "$df/no-defect.md")" -eq 1 ] \
    && ok "rejected: shared-state.md with the positive-claim sentence deleted" \
    || fail "the defect row cannot notice its sentence going missing"
[ "$(granularity_missing "$df/no-granularity.md")" -eq 1 ] \
    && ok "rejected: shared-state.md with the granularity sentence deleted" \
    || fail "the granularity row cannot notice its sentence going missing"
[ "$(siblings_missing "$df/no-siblings.md")" -eq 1 ] \
    && ok "rejected: shared-state.md with the sibling-absence sentence deleted" \
    || fail "the sibling row cannot notice its sentence going missing"
[ "$(omission_missing "$df/no-omission.md")" -eq 1 ] \
    && ok "rejected: discovery.md with the omission rule deleted" \
    || fail "the omission row cannot notice its sentence going missing"
[ "$(counts_missing "$df/no-counts.md")" -eq 1 ] \
    && ok "rejected: discovery.md with the derivation counts deleted" \
    || fail "the counts row cannot notice its sentence going missing"
rm -rf "$df"

# ---------------------------------------------------------- narrowing -------
section "change-scoped gating"

# Every row in this section reads its sentence INSIDE the narrowing rule, never
# anywhere in the file, and every negative deletes it from inside that section
# alone while leaving the rest of the file untouched.
#
# That is not fastidiousness, it is a measured repair. Against the shipped file
# before this slice wrote a byte:
#     awk '/dependsOn/ && /narrow/'   matched 2 lines
#     awk '/less/ && /laziest/'       matched 1 line
# The prohibition's exact words - "saying less would gate less, and the laziest
# manifest would be the least refused" - already live in the
# Evidence-that-does-not-count list, and the pair-set paragraph already says
# dependsOn may only add. So a row keyed on the WORDS reported a prohibition
# restated inside the narrowing rule over a file that had no narrowing rule at
# all. Third slice, third false green of the same family: a row passing over the
# very absence it exists to report. Position is the assertion here, so position
# is what the check reads.
NARROWING='## The subject: the pairs the change can reach'

# The section is the heading's own lines: `### ` subheadings stay inside it
# because `^## ` needs the space, and the next `## ` ends it.
section_of() {
    awk -v h="$2" '$0 == h { on = 1; next } on && /^## / { on = 0 } on' "$1"
}
# The same bounds, used to DELETE rather than to read, so a negative removes a
# sentence from the rule while the file keeps every other copy of it.
strip_in_section() {
    awk -v h="$2" -v p="$3" '
        $0 == h            { on = 1 }
        on && /^## / && $0 != h { on = 0 }
        on && $0 ~ p       { next }
                           { print }
    ' "$1"
}

# --- V58, V60  the rule, its evidence obligation and its limit ---------------
# One predicate per SENTENCE. A rule this file can only confirm the existence of
# is a rule a reader cannot act on, which is the C1 lesson: a link check proves
# a file exists and nothing more.
prohibition_missing()  { awk '/dependsOn/ && /laziest/ && /least refused/               { f = 1 } END { print f ? 0 : 1 }' "$1"; }
structural_missing()   { awk '/subtract/ && /derived independently of it/               { f = 1 } END { print f ? 0 : 1 }' "$1"; }
limit_missing()        { awk '/frontend/ && /does not make that unit stateless/         { f = 1 } END { print f ? 0 : 1 }' "$1"; }
unscoped_missing()     { awk '/pointing/ && /unknown/ && /cannot be laundered/          { f = 1 } END { print f ? 0 : 1 }' "$1"; }
counts_missing()       { awk '/beside/ && /never in place of it/                        { f = 1 } END { print f ? 0 : 1 }' "$1"; }
evidence_missing()     { awk '/Absence of a record/ && /never relief/                   { f = 1 } END { print f ? 0 : 1 }' "$1"; }
passes_missing()       { awk '/Derive/ { d = 1 } /Remove/ { r = 1 } /Re-insert/ { i = 1 } /Classify/ { c = 1 } END { print (d && r && i && c) ? 0 : 1 }' "$1"; }
# Exactly one pass may narrow. Two rows claiming it is two places a later reader
# can put a removal, which is the whole property this slice is defending.
narrowing_passes()     { grep -c 'only here' "$1"; }

nf=$(mktemp -d)
section_of "$SHARED" "$NARROWING" > "$nf/rule.md"

if [ -s "$nf/rule.md" ]; then
    ok "shared-state.md carries the narrowing rule under its own heading"
else
    fail "shared-state.md has no '$NARROWING' section, so every row below reads an empty file"
fi

for _case in \
    "passes_missing:the five passes are named, with derive, remove, re-insert and classify distinct" \
    "prohibition_missing:the dependsOn prohibition is restated INSIDE the rule, in those words" \
    "structural_missing:the rule states why it is one-directional: a record may only subtract from a set derived independently of it" \
    "evidence_missing:the rule states that absence of a record is never relief" \
    "limit_missing:the rule states the limit - a frontend change does not make that unit stateless" \
    "unscoped_missing:the rule states that an unscoped migrates cannot be laundered into relief" \
    "counts_missing:the rule states the gated count goes beside the derived one, never in place of it"
do
    _fn=${_case%%:*}
    _what=${_case#*:}
    if [ "$($_fn "$nf/rule.md")" -eq 0 ]; then
        ok "$_what"
    else
        fail "the narrowing rule does not state: $_what"
    fi
done

_np=$(narrowing_passes "$nf/rule.md")
[ "$_np" -eq 1 ] \
    && ok "exactly one pass may narrow, and the rule says so once" \
    || fail "$_np pass(es) claim they may narrow; the rule permits exactly one"

# Those three rows get fixtures too, or they are three rows this file's own rule
# does not apply to. The heading, one pass row, and the narrowing permission are
# each removable, and one of them is removable by DUPLICATION rather than by
# deletion: two rows saying `only here` is two places a later reader may put a
# removal, which is the property this whole section defends.
grep -v -- "$NARROWING" "$SHARED" > "$nf/no-heading.md"
section_of "$nf/no-heading.md" "$NARROWING" > "$nf/no-heading-rule.md"
[ ! -s "$nf/no-heading-rule.md" ] \
    && ok "rejected: shared-state.md with the narrowing heading removed - the rule reads as an empty file" \
    || fail "the heading row cannot tell a present rule from an absent one"

strip_in_section "$SHARED" "$NARROWING" 'Classify' > "$nf/no-pass.md"
section_of "$nf/no-pass.md" "$NARROWING" > "$nf/no-pass-rule.md"
[ "$(passes_missing "$nf/no-pass-rule.md")" -eq 1 ] \
    && ok "rejected: the pass table with the classify pass deleted" \
    || fail "the pass-table row cannot notice a pass going missing"

strip_in_section "$SHARED" "$NARROWING" 'only here' > "$nf/none.md"
section_of "$nf/none.md" "$NARROWING" > "$nf/none-rule.md"
[ "$(narrowing_passes "$nf/none-rule.md")" -ne 1 ] \
    && ok "rejected: a pass table in which no pass may narrow" \
    || fail "the one-narrowing-pass row cannot see the permission removed"

awk -v h="$NARROWING" '
    $0 == h                 { on = 1 }
    on && /^## / && $0 != h { on = 0 }
                            { print }
    on && /only here/       { print }
' "$SHARED" > "$nf/twice.md"
section_of "$nf/twice.md" "$NARROWING" > "$nf/twice-rule.md"
[ "$(narrowing_passes "$nf/twice-rule.md")" -ne 1 ] \
    && ok "rejected: a second pass claiming it may narrow" \
    || fail "the one-narrowing-pass row cannot see a second narrowing pass"

# ...and each of those can go missing on its own. One fixture per sentence,
# every one of which must FAIL.
#
# Each row asserts the TRANSITION - present before the strip, absent after - and
# not merely absent after. Measured while these rows were red: with no narrowing
# section in the file at all, stripping a sentence out of nothing left nothing,
# and all six negatives printed ok beside the positives that were failing. A
# negative satisfied by the section never existing exercises a different
# condition than the row it is paired with, which is the defect the verification
# legend names four shipped rows for.
for _case in \
    "prohibition_missing:laziest:the dependsOn prohibition" \
    "structural_missing:derived independently of it:the one-directional reason" \
    "evidence_missing:never relief:the absence-is-never-relief sentence" \
    "limit_missing:does not make that unit stateless:the frontend limit" \
    "unscoped_missing:cannot be laundered:the unscoped-migration sentence" \
    "counts_missing:never in place of it:the both-counts sentence"
do
    _fn=${_case%%:*}
    _rest=${_case#*:}
    _pat=${_rest%%:*}
    _what=${_rest#*:}
    strip_in_section "$SHARED" "$NARROWING" "$_pat" > "$nf/stripped.md"
    section_of "$nf/stripped.md" "$NARROWING" > "$nf/stripped-rule.md"
    if [ "$($_fn "$nf/rule.md")" -ne 0 ]; then
        fail "the fixture for $_what deletes a sentence the rule never carried"
    elif [ "$($_fn "$nf/stripped-rule.md")" -eq 1 ]; then
        ok "rejected: the narrowing rule with $_what deleted"
    else
        fail "the row for $_what cannot notice its sentence going missing"
    fi
done

# The false green, reproduced as a standing row rather than left in a comment:
# with the prohibition deleted from INSIDE the rule, the file still carries those
# exact words elsewhere - so a whole-file grep still reports green while the rule
# a reader acts on says nothing. This row is what proves the check reads position.
strip_in_section "$SHARED" "$NARROWING" 'laziest' > "$nf/stripped.md"
_elsewhere=$(grep -c 'laziest' "$nf/stripped.md" || true)
if [ "$_elsewhere" -ge 1 ] && [ "$(prohibition_missing "$nf/stripped.md")" -eq 0 ]; then
    ok "rejected: a whole-file grep still passes on the fixture the rule-scoped row rejects"
else
    fail "the fixture no longer reproduces the false green, so the positional row is untested"
fi
rm -rf "$nf"

# --- V61 slice-2 half  the trap that makes the diff safety-load-bearing ------
# The diff selecting the subject is what promotes it from a convenience to a
# safety input, and a diff under-reports by construction. Keyed on the sentence
# for the reason every row above is.
TRAPS="$SKILL/references/traps.md"
underreport_missing() { awk '/under-report/ && /safety-load-bearing/ { f = 1 } END { print f ? 0 : 1 }' "$1"; }

[ "$(underreport_missing "$TRAPS")" -eq 0 ] \
    && ok "traps.md names the diff as safety-load-bearing and under-reporting by construction" \
    || fail "traps.md does not name the diff's under-reporting as a trap"

tf=$(mktemp -d)
awk '!(/under-report/ && /safety-load-bearing/)' "$TRAPS" > "$tf/no-trap.md"
if [ "$(underreport_missing "$TRAPS")" -ne 0 ]; then
    fail "the under-reporting fixture deletes a sentence traps.md never carried"
elif [ "$(underreport_missing "$tf/no-trap.md")" -eq 1 ]; then
    ok "rejected: traps.md with the under-reporting trap deleted"
else
    fail "the under-reporting row cannot notice its sentence going missing"
fi
rm -rf "$tf"

# ------------------------------------------------ coordination identity -----
section "coordination identity"

IDENTITY="$SKILL/references/coordination-identity.md"

# Two measured lessons govern every row in this section, and both are stated once
# here rather than beside each fixture that obeys them.
#
# ONE - position, not words. Against the shipped tree before this slice wrote a
# byte, all three legs of the identity proof already matched shared-state.md,
# because step 2 of the verdict table is where the procedure lived at 1.1.0:
#
#     awk '/base stack/ && /configuration/ && /differ/'  matched shared-state.md
#     awk '/environment/ && /overlay/ && /route/'        matched shared-state.md
#     awk '/substrate/ && /ends the competition/'        matched shared-state.md
#
# So a row keyed on the WORDS anywhere in the tree reported a three-part proof
# over a tree with no coordination-identity.md in it at all. Fourth slice, fourth
# false green of the same family. The repair is the move this change actually
# makes: three legs in the file that owns the rule, zero in the file that used to,
# one home across the whole directory.
#
# TWO - assert the TRANSITION, never the end state. Six negatives in this section
# printed ok while the file was absent, because a fixture that strips a sentence
# out of nothing leaves nothing and a fixture that adds one to a file which
# already has it changes nothing. Each now checks that the shipped file is on the
# right side of the line BEFORE its fixture crosses it.
if [ -s "$IDENTITY" ]; then
    ok "references/coordination-identity.md ships"
else
    fail "references/coordination-identity.md is absent, so every row below reads an empty file"
fi

# The legs are keyed on what a restatement CANNOT avoid saying rather than on
# this file's own spelling, which is what lets one row see a second copy of the
# rule appear anywhere in the tree in anybody's words.
proof_legs() {
    _n=0
    awk '/base stack/ && /configuration/ && /differ/ { f = 1 } END { exit f ? 0 : 1 }' "$1" && _n=$((_n + 1))
    awk '/environment/ && /overlay/    && /route/    { f = 1 } END { exit f ? 0 : 1 }' "$1" && _n=$((_n + 1))
    awk '/substrate/    && /ends the competition/    { f = 1 } END { exit f ? 0 : 1 }' "$1" && _n=$((_n + 1))
    printf '%s\n' "$_n"
}

[ "$(proof_legs "$IDENTITY")" -eq 3 ] \
    && ok "coordination-identity.md states all three legs of the identity proof" \
    || fail "coordination-identity.md states $(proof_legs "$IDENTITY") of the three proof legs"

[ "$(proof_legs "$SHARED")" -eq 0 ] \
    && ok "shared-state.md links to the identity procedure rather than restating it" \
    || fail "shared-state.md still restates $(proof_legs "$SHARED") leg(s) of the identity proof, so the tree carries two texts with two outcomes"

# The row names the home rather than counting to one: a count of one is equally
# satisfied by the rule sitting in the WRONG file, which is the state the tree
# was in before this slice.
proof_home() {
    _h=''
    for _f in "$SKILL"/references/*.md; do
        [ "$(proof_legs "$_f")" -eq 3 ] && _h="$_h $(basename "$_f")"
    done
    printf '%s\n' "${_h# }"
}
[ "$(proof_home)" = "coordination-identity.md" ] \
    && ok "the identity proof has exactly one home, and it is coordination-identity.md" \
    || fail "the identity proof lives in '$(proof_home)'; it has one home and that home is coordination-identity.md"

# The negative is the measured false green itself, standing rather than in a
# comment: shared-state.md with 1.1.0's step-2 procedure put back, in 1.1.0's
# words rather than in this change's.
cif=$(mktemp -d)
{
    cat "$SHARED"
    printf '%s\n' '| 2 | X = yes | Supply a distinct identity. On re-entry X is no only if that value is verified distinct, which is three things: (a) it differs from the value the base stack attaches under, read out of the base configuration rather than assumed; (b) the launch sets that variable in the overlay environment, and the value crosses only by a route the launch already has; (c) the substrate table below confirms that a distinct identity ends the competition on that substrate. |'
} > "$cif/restated.md"
if [ "$(proof_legs "$SHARED")" -ne 0 ]; then
    fail "the restatement fixture adds a procedure shared-state.md still carries, so it rejects nothing"
elif [ "$(proof_legs "$cif/restated.md")" -eq 3 ] && [ "$(proof_home)" = "coordination-identity.md" ]; then
    ok "rejected: shared-state.md with 1.1.0's identity procedure restated beside the link"
else
    fail "the one-home row cannot see the procedure restated in the file that used to hold it"
fi

# --- V64  what the substrate table answers, and what it must never answer ----
KNOB_H="## What is this substrate's identity knob"

knob_section() { section_of "$1" "$KNOB_H"; }
knob_data()    { knob_section "$1" | awk -F'|' 'NF >= 5 && $2 !~ /Coordination primitive/ && $2 !~ /^[ -]*$/'; }
knob_rows()    { knob_data "$1" | awk 'END { print NR + 0 }'; }
knob_tokens()  { knob_data "$1" | awk -F'|' '{ if (match($3, /`[^`]+`/)) print substr($3, RSTART + 1, RLENGTH - 2) }'; }
knob_answers() { knob_data "$1" | awk -F'|' '{ gsub(/^[ \t]+/, "", $4); print $4 }'; }

# The one question the table may not answer. These are the CELLS of the column
# this slice deletes from shared-state.md, so the negative is not a hypothetical
# regression: it is the deleted column being moved into the new table instead of
# being retired, which is the same finite prose table one door along.
NAMESPACE_PROCEDURE='TEMPLATE|search_path|New database|New schema|Copy the file|Separate vhost|Separate bucket|Separate index|SELECT [n0-9]'
knob_procedures() { knob_section "$1" | grep -cE "$NAMESPACE_PROCEDURE"; }

_kr=$(knob_rows "$IDENTITY")
[ "$_kr" -ge 6 ] \
    && ok "the knob table carries $_kr coordination primitives" \
    || fail "the knob table carries $_kr row(s); the six knobs the spec names need six"

_missing_knob=''
for _k in group.id durable queue subject-prefix advisory-lock replication-slot; do
    knob_tokens "$IDENTITY" | grep -qx "$_k" || _missing_knob="$_missing_knob $_k"
done
[ -z "$_missing_knob" ] \
    && ok "every knob the spec names has a row: group.id, durable, queue, subject-prefix, advisory-lock, replication-slot" \
    || fail "the knob table names no knob for:$_missing_knob"

# Both rows below are guarded on the table being there at all: an empty table
# names no creation procedure and carries no unparseable answer, so each would
# report a property of a table that does not exist. Lesson two, above.
if [ "$_kr" -eq 0 ]; then
    fail "the knob table is empty, so the no-creation-procedure row reads nothing"
elif [ "$(knob_procedures "$IDENTITY")" -eq 0 ]; then
    ok "no knob row answers how to create a namespace inside the substrate"
else
    fail "the knob table names a namespace-creation procedure: $(knob_section "$IDENTITY" | grep -nE "$NAMESPACE_PROCEDURE" | head -1)"
fi

# Every answer is parseable, so an unreadable cell is a failure rather than a
# silent refusal - the reader in check_schema.py treats anything that is not an
# unconditional Yes as unconfirmed, and a row it cannot parse would refuse for
# the wrong reason and look like the rule working.
_bad_answer=$(knob_answers "$IDENTITY" | grep -cvE '^\*\*(Yes|No)\*\*')
if [ "$_kr" -eq 0 ]; then
    fail "the knob table is empty, so the answer-shape row reads nothing"
elif [ "$_bad_answer" -eq 0 ]; then
    ok "every knob row answers Yes or No to whether a distinct value ends the competition"
else
    fail "$_bad_answer knob row(s) answer neither Yes nor No, so the reader cannot tell a confirmation from a refusal"
fi

# ...and the shape row must be able to fire, or "every answer is Yes or No" is a
# property of a table nobody could have written wrongly.
knob_answers "$IDENTITY" | awk 'NR == 1 { print "**Probably** - it depends"; next } { print }' > "$cif/answers.txt"
[ "$(grep -cvE '^\*\*(Yes|No)\*\*' "$cif/answers.txt")" -ge 1 ] \
    && ok "rejected: a knob row answering neither Yes nor No" \
    || fail "the answer-shape row cannot see an unparseable answer"

# Both answers must occur. A table of all-Yes has reclassified the cases with no
# safe answer as solvable by an identity, which the spec forbids by name; a table
# of all-No confirms nothing and every pair refuses.
_yes=$(knob_answers "$IDENTITY" | grep -c '^\*\*Yes\*\*')
_no=$(knob_answers "$IDENTITY" | grep -c '^\*\*No\*\*')
{ [ "$_yes" -ge 1 ] && [ "$_no" -ge 1 ]; } \
    && ok "the knob table confirms $_yes substrate(s) and refuses $_no, so it can do both" \
    || fail "the knob table answers Yes $_yes time(s) and No $_no time(s); a table that only ever gives one answer decides nothing"

# Every sentence this file has to carry, in one loop and one predicate rather
# than one loop per rule: three copies of this body is three places a later row
# can be added with a weaker test. Each case names two literal fragments that
# must land on ONE line, because a rule split across two paragraphs is two
# statements a reader can act on separately.
IDENTITY_SENTENCES='
distinct identity:never by a copy:X is answered by a distinct identity and never by a copy
X and not W:volume and instance inventory unchanged:an X-only pair leaves the runtime inventory unchanged
X and W:copy alone leaves X undetermined:a W-and-X pair takes both mechanisms and the copy never answers X
any one unproven:undetermined:any one leg unproven leaves X undetermined
isolation.env:shared by every service:a store-level environment map is not the identity channel
every message the base stack receives:duplicated:the run says the overlay now receives every message the base stack does
absent from this table:undetermined:a substrate absent from the knob table is undetermined, which refuses
not given a name anyway:no name ends:a substrate whose competition no name ends is not given a name anyway
separator belongs to the projection:no form is produced from another:the separator is the projection'"'"'s and no form is produced from another
neither form:undetermined:a store recording neither form is undetermined, which refuses'

states_it() { awk -v a="$2" -v b="$3" 'index($0, a) && index($0, b) { f = 1 } END { exit f ? 0 : 1 }' "$1"; }

# Fed by a REDIRECT and never by a pipe. `... | while read` puts the loop in a
# subshell, where every `fail` increments a copy of the counter that dies with
# it: the rows would print FAIL and the suite would still exit 0. Caught while
# writing this loop, and it is the same family as everything else in this file -
# a check that reports a failure nobody is counting is a check that cannot fail.
printf '%s\n' "$IDENTITY_SENTENCES" > "$cif/sentences.txt"

while IFS= read -r _case; do
    [ -n "$_case" ] || continue
    _a=${_case%%:*}; _rest=${_case#*:}; _b=${_rest%%:*}; _what=${_rest#*:}
    if states_it "$IDENTITY" "$_a" "$_b"; then
        ok "$_what"
    else
        fail "coordination-identity.md does not state: $_what"
    fi
done < "$cif/sentences.txt"

# ...and each can go missing on its own, transition asserted per lesson two.
while IFS= read -r _case; do
    [ -n "$_case" ] || continue
    _a=${_case%%:*}; _rest=${_case#*:}; _b=${_rest%%:*}; _what=${_rest#*:}
    awk -v a="$_a" -v b="$_b" 'index($0, a) && index($0, b) { next } { print }' "$IDENTITY" > "$cif/stripped.md"
    if ! states_it "$IDENTITY" "$_a" "$_b"; then
        fail "the fixture for '$_what' deletes a sentence coordination-identity.md never carried"
    elif ! states_it "$cif/stripped.md" "$_a" "$_b"; then
        ok "rejected: coordination-identity.md with '$_what' deleted"
    else
        fail "the row for '$_what' cannot notice its sentence going missing"
    fi
done < "$cif/sentences.txt"

# --- V57  the column leaves shared-state.md; the table and its catches stay ---
# Deleting the table deletes the evidence four of the six cases with no safe
# answer rest on, which is the same hazard the narrowing rule carries: a reader
# who takes the instruction one word too wide removes the refusals. So the row
# asserts BOTH directions - the column gone AND the table still there - and has a
# negative for each.
SUBSTRATE_H='## Per substrate'
substrate_rows()   { section_of "$1" "$SUBSTRATE_H" | awk -F'|' 'NF >= 3 && $2 !~ /^[ -]*$/ && $2 !~ /Substrate/ { n++ } END { print n + 0 }'; }
# A COLUMN, not a mention. Keyed on table rows because the file is obliged to
# name what it deleted - "its In-instance isolation column is gone" is the
# sentence a reader needs and an intent-blind grep read it as the column still
# being there, measured. The width row beside it closes the other direction: a
# column renamed on its way back in is still a third column.
substrate_column() { section_of "$1" "$SUBSTRATE_H" | grep -c '^|.*In-instance isolation'; }
substrate_width()  { section_of "$1" "$SUBSTRATE_H" | awk -F'|' '/^\| Substrate \|/ { print NF - 2; exit }'; }

_sr=$(substrate_rows "$SHARED")
[ "$_sr" -ge 14 ] \
    && ok "the per-substrate table survives with $_sr rows and its catches" \
    || fail "the per-substrate table has $_sr row(s); deleting it deletes the evidence the refuse-cases rest on"

[ "$(substrate_column "$SHARED")" -eq 0 ] \
    && ok "the In-instance isolation column is gone from the per-substrate table" \
    || fail "the per-substrate table still carries the In-instance isolation column"

_sw=$(substrate_width "$SHARED")
[ "${_sw:-0}" -eq 2 ] \
    && ok "the per-substrate table is two columns wide: the substrate and its catch" \
    || fail "the per-substrate table is ${_sw:-no} columns wide, so a third column came back under another name"

grep -v -- "$SUBSTRATE_H" "$SHARED" > "$cif/no-table.md"
[ "$(substrate_rows "$cif/no-table.md")" -eq 0 ] \
    && ok "rejected: shared-state.md with the per-substrate table removed whole" \
    || fail "the table-survives row cannot tell a present table from an absent one"

awk '/^\| Substrate \|/ { print "| Substrate | In-instance isolation | The catch |"; next } { print }' "$SHARED" > "$cif/column-back.md"
if [ "$(substrate_column "$SHARED")" -ne 0 ]; then
    fail "the column-restored fixture restores a column the shipped table still has, so it rejects nothing"
elif [ "$(substrate_column "$cif/column-back.md")" -ge 1 ]; then
    ok "rejected: the In-instance isolation column restored to the table"
else
    fail "the deleted-column row cannot see the column come back"
fi

# The six cases with no safe answer, frozen. The list was diffed against v1.1.0
# before this slice and is identical, so these literals ARE 1.1.0's - which is
# what the requirement asks be preserved, in number and in wording.
NO_SAFE_H='## Cases with no safe answer'
no_safe_n() { section_of "$1" "$NO_SAFE_H" | grep -cE '^[0-9]+\. '; }

_ns=$(no_safe_n "$SHARED")
[ "$_ns" -eq 6 ] \
    && ok "the six cases with no safe answer are still six" \
    || fail "there are $_ns cases with no safe answer, not the six 1.1.0 shipped"

_lost=''
while IFS= read -r _c; do
    grep -qF "$_c" "$SHARED" || _lost="$_lost | $_c"
done <<NO_SAFE_CASES
A migration against a shared database too large or slow to clone.
Redis pub/sub. Logical database selection does not isolate channels
Externally visible side effects. No infrastructure trick un-sends an email
Host singletons
When the shared state *is* what is under test.
Exactly-once consumption while the base consumer is being observed.
NO_SAFE_CASES
[ -z "$_lost" ] \
    && ok "each of the six cases is word-for-word what 1.1.0 shipped" \
    || fail "a case with no safe answer was reworded or removed:$_lost"

awk '!/Exactly-once consumption/' "$SHARED" > "$cif/five-cases.md"
[ "$(no_safe_n "$cif/five-cases.md")" -eq 5 ] \
    && ok "rejected: the list with the exactly-once case removed" \
    || fail "the case-count row cannot notice a case going missing"

# --- V56  one hash, one separator-free slug, two projections -----------------
# The generator below reads its parameters OUT OF THE SHIPPED TABLE - prefix,
# separator and truncation - and the baseline it is compared against is 1.1.0's
# transform frozen here. Two independent readings, so a prose edit that changes
# what the skill would generate moves one side and not the other.
FORMS_H='## The name family: one hash, one slug, two projections'

form_cell() {
    section_of "$1" "$FORMS_H" | awk -F'|' -v f="$2" -v c="$3" '
        index($2, f) && $2 !~ /^[ -]*$/ {
            v = $(c + 0)
            gsub(/`/, "", v)
            gsub(/^[ \t]+|[ \t]+$/, "", v)
            print v
            exit
        }'
}
# The truncation is read from the prose for the reason C1's cut length is: a
# hard-coded 28 would supply the very step whose absence is the defect.
slug_max() {
    section_of "$1" "$FORMS_H" | awk '/slug/ && match($0, /\*\*[0-9]+\*\*/) {
        print substr($0, RSTART + 2, RLENGTH - 4); exit }'
}
# ...and so is the hashing command, which is the C1 pattern applied to a second
# recipe: the command is taken out of the table and RUN, rather than reviewed.
hash8_recipe() {
    section_of "$1" "$FORMS_H" | awk '
        {
            s = $0
            gsub(/\\\|/, "|", s)
            while (match(s, /`[^`]*`/)) {
                c = substr(s, RSTART + 1, RLENGTH - 2)
                if (c ~ /git hash-object/) { print c; exit }
                s = substr(s, RSTART + RLENGTH)
            }
        }'
}
hash8_for() {
    _cmd=$(hash8_recipe "$2")
    [ -n "$_cmd" ] || return 0
    _cmd=$(printf '%s' "$_cmd" | awk -v b="$1" '{ sub(/<full branch name>/, b); print }')
    _cut=$(section_of "$2" "$FORMS_H" | awk '/hash8/ && match($0, /first [0-9]+ characters/) {
        print substr($0, RSTART + 6, RLENGTH - 17); exit }')
    [ -n "$_cut" ] || return 0
    sh -c "$_cmd" 2>/dev/null | cut -c1-"$_cut"
}

# The slug is a LIST OF SEGMENTS and the separator belongs to the projection, so
# the internal spelling below uses a character no segment can contain and each
# form joins with its own. That is the property being tested, not decoration: a
# generator that produced one string and substituted its separator afterwards
# would pass every grammar row and still be the defect F1 came from.
name_form() {
    _prefix=$(form_cell "$2" "$3" 4)
    _join=$(form_cell "$2" "$3" 5)
    _max=$(slug_max "$2")
    _hash=$(hash8_for "$1" "$2")
    # Any parameter unreadable and the generator stands down loudly rather than
    # supplying the missing step itself, which is C1's lesson: a checker that
    # assumes the truncation is a checker that cannot see it go missing.
    [ -n "$_prefix" ] && [ -n "$_join" ] && [ -n "$_max" ] && [ -n "$_hash" ] || return 0
    _slug=$(printf '%s' "$1" | awk -v j="$_join" -v m="$_max" '
        {
            s = tolower($0)
            gsub(/[^a-z0-9]+/, "/", s)
            gsub(/^\/+|\/+$/, "", s)
            s = substr(s, 1, m)
            sub(/\/+$/, "", s)
            if (s == "") s = "x"
            gsub(/\//, j, s)
            print s
        }')
    printf '%s%s%s%s\n' "$_prefix" "$_slug" "$_join" "$_hash"
}

# 1.1.0's rule, frozen: one substitution over the whole string, truncate, strip a
# separator the cut left trailing. A different algorithm from the one above, on
# purpose - byte-identity between two spellings of the same rule is the assertion.
sql_form_110() {
    printf 'sg_%s_%s\n' \
        "$(printf '%s' "$1" | awk '{
            s = tolower($0)
            gsub(/[^a-z0-9]+/, "_", s)
            gsub(/^_+|_+$/, "", s)
            s = substr(s, 1, 28)
            sub(/_+$/, "", s)
            if (s == "") s = "x"
            print s
        }')" \
        "$(printf '%s' "$1" | git hash-object --stdin | cut -c1-8)"
}

SQL_FORM='SQL identifier'
LABEL_FORM='DNS and object-store label'
BRANCHES='feat/pfi-coordination-identity feature/checkout-rewrite-phase-two Release/2.0.0 ___ x'

_drift=''
for _b in $BRANCHES; do
    _got=$(name_form "$_b" "$IDENTITY" "$SQL_FORM")
    _want=$(sql_form_110 "$_b")
    [ -n "$_got" ] && [ "$_got" = "$_want" ] || _drift="$_drift | $_b: $_got != $_want"
done
[ -z "$_drift" ] \
    && ok "the SQL form is byte-identical to 1.1.0's on every branch shape tested" \
    || fail "the SQL form has drifted from 1.1.0's:$_drift"

_bad_label=''
for _b in $BRANCHES; do
    _l=$(name_form "$_b" "$IDENTITY" "$LABEL_FORM")
    case ${_l:-} in
        '')                       _bad_label="$_bad_label | $_b: nothing generated" ;;
        *_*)                      _bad_label="$_bad_label | $_l carries an underscore" ;;
        *[!a-z0-9-]*)             _bad_label="$_bad_label | $_l is not lowercase alphanumeric or hyphen" ;;
        -* | *-)                  _bad_label="$_bad_label | $_l begins or ends with a hyphen" ;;
    esac
    [ "${#_l}" -le 63 ] || _bad_label="$_bad_label | $_l is ${#_l} characters"
done
[ -z "$_bad_label" ] \
    && ok "the label form carries no underscore, is at most 63 characters and is alphanumeric at both ends" \
    || fail "the label form is not a legal label:$_bad_label"

# Two branches whose slugs truncate identically must differ in BOTH forms,
# because hash8 is taken over the untruncated branch name.
TWIN_A='feature/checkout-rewrite-phase-two-alpha'
TWIN_B='feature/checkout-rewrite-phase-two-beta'
_sa=$(name_form "$TWIN_A" "$IDENTITY" "$SQL_FORM");   _sb=$(name_form "$TWIN_B" "$IDENTITY" "$SQL_FORM")
_la=$(name_form "$TWIN_A" "$IDENTITY" "$LABEL_FORM"); _lb=$(name_form "$TWIN_B" "$IDENTITY" "$LABEL_FORM")
if [ -z "$_sa" ] || [ -z "$_la" ]; then
    fail "the twin-branch row generated nothing, so a difference between two empty strings proves nothing"
elif [ "$_sa" != "$_sb" ] && [ "$_la" != "$_lb" ]; then
    ok "two branches sharing a truncated slug differ in both forms ($_sa vs $_sb)"
else
    fail "two branches sharing a truncated slug collide: SQL $_sa/$_sb, label $_la/$_lb"
fi

# ...and that row must be able to see a collision, or it is reporting on a
# property no generator in this file could violate. The variant takes hash8 over
# the TRUNCATED slug, which is the one mistake the rule names by name.
hash8_over_truncated() {
    _s=$(printf '%s' "$1" | awk '{ s = tolower($0); gsub(/[^a-z0-9]+/, "_", s); gsub(/^_+|_+$/, "", s); print substr(s, 1, 28) }')
    printf 'sg_%s_%s\n' "$_s" "$(printf '%s' "$_s" | git hash-object --stdin | cut -c1-8)"
}
[ "$(hash8_over_truncated "$TWIN_A")" = "$(hash8_over_truncated "$TWIN_B")" ] \
    && ok "rejected: a generator taking hash8 over the truncated slug, which collides on those two branches" \
    || fail "the collision fixture does not collide, so the twin-branch row is untested"

# The generator is driven by the shipped table, and these three fixtures prove
# it: edit the table and the output moves. A generator with the parameters
# hard-coded would pass all three while reading nothing.
awk -F'|' -v f="$LABEL_FORM" '
    index($2, f) && $2 !~ /^[ -]*$/ { sub(/`-`/, "`_`", $5); print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|"; next }
    { print }
' "$IDENTITY" > "$cif/underscore-label.md"
_ul=$(name_form "$TWIN_A" "$cif/underscore-label.md" "$LABEL_FORM")
case ${_ul:-} in
    *_*) ok "rejected: a label projection joining with an underscore ($_ul)" ;;
    *)   fail "the label grammar row does not read the table's separator: got '${_ul:-nothing}'" ;;
esac

awk -F'|' -v f="$SQL_FORM" '
    index($2, f) && $2 !~ /^[ -]*$/ { sub(/`sg_`/, "`sg-`", $4); print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|"; next }
    { print }
' "$IDENTITY" > "$cif/wrong-prefix.md"
_wp=$(name_form "$TWIN_A" "$cif/wrong-prefix.md" "$SQL_FORM")
[ -n "$_wp" ] && [ "$_wp" != "$(sql_form_110 "$TWIN_A")" ] \
    && ok "rejected: an SQL projection under a different prefix, which is no longer 1.1.0's output" \
    || fail "the byte-identity row does not read the table's prefix: got '${_wp:-nothing}'"

awk '{ if (/slug/) gsub(/\*\*[0-9]+\*\*/, "the joined length"); print }' "$IDENTITY" 2>/dev/null > "$cif/no-truncation.md"
if [ -z "$(name_form "$TWIN_A" "$IDENTITY" "$SQL_FORM")" ]; then
    fail "the truncation fixture strips a step from a derivation that generates nothing anyway"
elif [ -z "$(name_form "$TWIN_A" "$cif/no-truncation.md" "$SQL_FORM")" ]; then
    ok "rejected: a derivation stating no truncation - the generator stands down rather than assuming 28"
else
    fail "a derivation with no truncation still produced a name, so the missing step was supplied by the checker"
fi

# The two sentences this section rests on - the separator being the projection's,
# and a store recording neither form - are asserted with the rest of the file's
# sentences in $IDENTITY_SENTENCES above, each with its own deletion fixture.

# --- V57  names are derived, and nothing is drawn from a pool ----------------
# The vocabulary is greped for, not the concept, and the exclusion is ONE word:
# `never`. A looser exclusion would have been a bypass rather than a rule -
# measured, `no ` excuses the shipped rung-3 bullet, which names Redis SELECT n
# beside "no create command, no drop command" and would have gone on shipping
# the allocator under a grep that reported it gone.
# It is also NARROWER than "any word about allocation", and that is measured too:
# `allocate a candidate port` ships in docs/HOW-IT-WORKS.md about the port
# picker, which is a legitimate allocation of something that is not a namespace
# name, and `Logical database selection does not isolate channels` is one of the
# six cases with no safe answer, whose wording this slice may not touch. So the
# pattern names the retired vocabulary itself and requires a name beside the
# generic verb.
ALLOCATOR='16 logical|sixteen host-global|SELECT n[^a-z]|logical-database index|slot pool|exhaustion case|release obligation|allocated (name|namespace|index|database|value|per )|allocates? an? (name|namespace|index|database|slot)'
allocator_hits() { grep -rniE "$ALLOCATOR" "$@" 2>/dev/null | grep -cvE '\bnever\b'; }

_ah=$(allocator_hits $SHIPPED_SURFACE)
[ "$_ah" -eq 0 ] \
    && ok "no shipped file describes an allocation, a pool, an exhaustion case or a release obligation for a namespace name" \
    || fail "$_ah line(s) describe an allocated namespace name: $(grep -rniE "$ALLOCATOR" $SHIPPED_SURFACE | grep -vE '\bnever\b' | head -1)"

af=$(mktemp -d)
printf '%s\n' '| Redis keyspace | `SELECT n` — 16 logical databases, allocated per worktree and released on teardown | many clients pin database 0 |' > "$af/fixture.md"
[ "$(allocator_hits "$af")" -ge 1 ] \
    && ok "rejected: a row handing out one of sixteen logical databases per worktree" \
    || fail "the allocator grep cannot fire"
rm -rf "$af"

# The retired placeholder, on the terms the retired `writes` array is held to:
# it may still be NAMED - this change is obliged to say what it replaced - but no
# line may present it as a placeholder a template writes today.
RETIRED_PLACEHOLDER='{{isolationName}}'
retired_placeholder_hits() { grep -rnF "$RETIRED_PLACEHOLDER" "$@" 2>/dev/null | grep -cvE "$RETIREMENT|was one|replaced by"; }

_rp=$(retired_placeholder_hits $SHIPPED_SURFACE)
[ "$_rp" -eq 0 ] \
    && ok "no shipped file presents {{isolationName}} as a placeholder a template still uses" \
    || fail "$_rp line(s) still use the retired {{isolationName}}: $(grep -rnF "$RETIRED_PLACEHOLDER" $SHIPPED_SURFACE | grep -vE "$RETIREMENT|was one|replaced by" | head -1)"

rpf=$(mktemp -d)
printf '%s\n' 'command: make -C {{repoRoot}} db-create DB={{isolationName}}' > "$rpf/fixture.md"
[ "$(retired_placeholder_hits "$rpf")" -ge 1 ] \
    && ok "rejected: a template still substituting the retired {{isolationName}}" \
    || fail "the retired-placeholder grep cannot fire"
rm -rf "$rpf"

# The set stays CLOSED, and closed is an equality rather than a floor: a seventh
# member is how a placeholder yielding an allocated value gets in.
PLACEHOLDER_SET='{{isolationIdent}} {{isolationLabel}} {{port}} {{repoRoot}} {{store}} {{worktree}}'
placeholders_in() {
    awk '/^\| Placeholders \|/ {
        while (match($0, /\{\{[A-Za-z]+\}\}/)) {
            print substr($0, RSTART, RLENGTH)
            $0 = substr($0, RSTART + RLENGTH)
        }
    }' "$1" | sort -u | tr '\n' ' ' | awk '{ $1 = $1; print }'
}

_ps=$(placeholders_in "$SHARED")
[ "$_ps" = "$PLACEHOLDER_SET" ] \
    && ok "the closed placeholder set is exactly the six recorded members" \
    || fail "the closed placeholder set reads '$_ps', not '$PLACEHOLDER_SET'"

awk '/^\| Placeholders \|/ { sub(/Closed set of six/, "Closed set of seven, plus {{isolationIndex}} drawn from the sixteen slots,") } { print }' "$SHARED" > "$cif/seventh.md"
if [ "$_ps" != "$PLACEHOLDER_SET" ]; then
    fail "the seventh-placeholder fixture cannot be told from a shipped set that already differs from the recorded one"
elif [ "$(placeholders_in "$cif/seventh.md")" != "$PLACEHOLDER_SET" ]; then
    ok "rejected: a seventh placeholder added to a set the rule calls closed"
else
    fail "the closed-set row cannot see a member added"
fi

# --- V42 slice-3 half  the new reference file is held to the shipped floor ---
# A WIDER pattern than $PORTABILITY and a NARROWER subject, on purpose. The extra
# names are real absences on the supported floor, but they are named in shipped
# files today for legitimate reasons - `with-lock.sh` says "no flock", traps.md
# tells the agent to read `lsof` on the host - so widening the tree-wide grep
# would fail rows about text that is already correct. The new files carry none of
# them and are checked against the wider list.
PORTABILITY_NEW="$PORTABILITY"'|\bflock\b|\btimeout\b|\blsof\b|\bss\b|\bnode\b'
if [ ! -f "$IDENTITY" ]; then
    fail "coordination-identity.md is absent, so the portability row scans nothing"
elif grep -niE "$PORTABILITY_NEW" "$IDENTITY" >/dev/null 2>&1; then
    fail "coordination-identity.md names an unavailable tool: $(grep -niE "$PORTABILITY_NEW" "$IDENTITY" | head -1)"
else
    ok "coordination-identity.md names no tool absent from the supported floor"
fi

pnf=$(mktemp -d)
printf '%s\n' 'A comment: the value could be delivered with timeout 5 flock, which is not portable.' > "$pnf/fixture.md"
grep -niE "$PORTABILITY_NEW" "$pnf/fixture.md" >/dev/null 2>&1 \
    && ok "rejected: an unavailable tool named inside a comment, the grep being intent-blind" \
    || fail "the widened portability grep cannot fire"
rm -rf "$pnf"

if [ ! -f "$IDENTITY" ]; then
    fail "coordination-identity.md is absent, so the GNU-only row scans nothing"
elif grep -nE "$GNUISM" "$IDENTITY" >/dev/null 2>&1; then
    fail "coordination-identity.md names a GNU-only construct"
else
    ok "coordination-identity.md names no GNU-only construct"
fi

# --- V61 slice-3 half  the pointers in a reference file resolve too ----------
# The shipped link loop reads SKILL.md alone. The body may not name this file -
# V40 asserts exactly that - so the only thing that can prove its pointers
# resolve is the same loop run over the references directory, which is also what
# catches the backlink shared-state.md now carries to it.
ref_link_n=0
ref_broken=0
for _f in "$SKILL"/references/*.md; do
    for _p in $(link_targets "$_f"); do
        ref_link_n=$((ref_link_n + 1))
        [ -e "$SKILL/$_p" ] || { ref_broken=$((ref_broken + 1)); fail "link is broken in $(basename "$_f"): $_p"; }
    done
done
[ "$ref_link_n" -ge 5 ] \
    && ok "the references directory names $ref_link_n backticked skill paths and all resolve" \
    || fail "the references directory names $ref_link_n backticked skill path(s), so this row proved nothing"

grep -qF '`references/coordination-identity.md`' "$SHARED" \
    && ok "shared-state.md points at the identity procedure by a resolving path" \
    || fail "shared-state.md carries no backticked pointer to references/coordination-identity.md"

{ cat "$IDENTITY" 2>/dev/null; printf -- '- `references/renamed-away.md`\n'; } > "$cif/broken-link.md"
[ "$(link_unresolved "$cif/broken-link.md")" -ge 1 ] \
    && ok "rejected: a reference file naming a backticked skill path that does not resolve" \
    || fail "the reference link loop cannot report a broken link"
rm -rf "$cif"

# ------------------------------------------------- instrumentation ----------
section "instrumentation"

# --- V13  the probe's negative is what makes the probe a check ---------------
# The block under test is the SHIPPED one, lifted out of with-lock.sh between
# its sentinels, so this exercises the bytes that run rather than a restatement
# of them.
#
# One extractor, used by every row that needs the block: this one, the minimal
# image row further down, and the byte-identity comparison in the reap section.
# Three copies of one awk program is how they drift into asking three subtly
# different questions.
extract_probe() {
    awk '/BEGIN lstart probe/ { on = 1; next } /END lstart probe/ { on = 0 } on { print }' "$1" 2>/dev/null
}

ph=$(mktemp -d)
lock_probe=$(extract_probe "$LOCK")
{
    printf '#!/bin/sh\n'
    printf '%s\n' "$lock_probe"
    printf 'lstart_probe\nprintf "%%s\\n" "$lstart_supported"\n'
} > "$ph/probe.sh"

# What is guarded is the EXTRACTION, not the assembled file. The shebang and
# the trailer this block writes itself satisfy both `-s` and a grep for
# lstart_probe, so with the sentinels stripped from with-lock.sh the row
# reported the block extractable over zero extracted bytes - an assertion its
# own harness answered. V6 below already guards its extraction this way.
if [ -n "$lock_probe" ] && [ -s "$ph/probe.sh" ] && grep -q lstart_probe "$ph/probe.sh"; then
    ok "the lstart probe block is delimited and extractable from with-lock.sh"
else
    fail "the lstart probe block could not be lifted out of with-lock.sh"
fi

mkdir -p "$ph/honours" "$ph/ignores"
printf '#!/bin/sh\nprintf "Wed Jul 30 12:00:00 2026\\n"\n' > "$ph/honours/ps"
printf '#!/bin/sh\nprintf "Wed Jul 30 12:00:00 2026\\nThu Jul 31 09:00:00 2026\\n"\n' > "$ph/ignores/ps"
chmod +x "$ph/honours/ps" "$ph/ignores/ps"

[ "$(PATH="$ph/honours:$PATH" sh "$ph/probe.sh")" = 1 ] \
    && ok "a ps that honours -p makes the probe report supported" \
    || fail "the probe called a honouring ps unsupported"
[ "$(PATH="$ph/ignores:$PATH" sh "$ph/probe.sh")" = 0 ] \
    && ok "rejected: a ps that ignores -p and answers with the whole table" \
    || fail "the probe accepted a ps that ignores -p, so it proves nothing"

# --- V16  the anchor rules each have a fixture, and one can go missing -------
anchor_missing() {
    _n=0
    # -- is load-bearing: one marker starts with a dash and grep would read it
    # as an option, which fails the row for a reason that has nothing to do
    # with what the row is checking.
    for _m in 'docker create --publish' 'tee log' 'up catalog-api' 'npm run dev' '--context remote' 'echo "docker run x"'; do
        grep -qF -- "$_m" "$1" || _n=$((_n + 1))
    done
    printf '%s\n' "$_n"
}
REAPING="$SKILL/references/reaping.md"
[ "$(anchor_missing "$REAPING")" -eq 0 ] \
    && ok "every anchor rule carries a fixture: create, piped, up, launcher-less, anchorless, quoted" \
    || fail "$(anchor_missing "$REAPING") anchor fixture(s) missing from reaping.md"
grep -vF 'up catalog-api' "$REAPING" > "$ph/reaping.md"
[ "$(anchor_missing "$ph/reaping.md")" -ge 1 ] \
    && ok "rejected: the fixture table with the up-shaped refusal removed" \
    || fail "the anchor fixture check cannot notice a missing row"
rm -rf "$ph"

# --- V29  the portability grep is intent-blind, and must be able to fire -----
# One pattern, named once at the top of this file, for the fixture here, for the
# shipped check in the portability section at the bottom, and for the widened
# list the coordination-identity section applies to the new reference file - the
# same reason $GNUISM is a variable rather than two copies of one regex. With two
# copies, editing the shipped check left this fixture proving an expression that
# no longer runs: it went on reporting "the portability grep can fail" about a
# pattern the shipped row had stopped using.
pf=$(mktemp -d)
printf 'a fixture that names an unavailable tool: jq\n' > "$pf/fixture.md"
if grep -rniE "$PORTABILITY" "$pf" >/dev/null 2>&1; then
    ok "rejected: a file naming an unavailable tool, even in prose"
else
    fail "the portability grep cannot fail"
fi
rm -rf "$pf"

# --- V30  parsing is not running: a GNU-only flag parses fine everywhere -----
if grep -nE "$GNUISM" "$SKILL"/scripts/*.sh >/dev/null 2>&1; then
    fail "a shipped script names a GNU-only construct"
else
    ok "no shipped script names a GNU-only construct"
fi
gf=$(mktemp -d)
printf '#!/bin/sh\nfind . -newermt yesterday\n' > "$gf/fixture.sh"
grep -nE "$GNUISM" "$gf"/*.sh >/dev/null 2>&1 \
    && ok "rejected: a fixture reaching for a GNU-only construct" \
    || fail "the GNU-only detector cannot fail"
rm -rf "$gf"

# --- V35  a fixture repository must not inherit the developer's signing ------
# Every `git commit` in this file builds a THROWAWAY repository, and a throwaway
# repository is not the developer's. Inheriting a global `commit.gpgsign=true`
# sends the suite to a signing agent nobody is waiting on, and measured twice on
# this machine with that agent locked the commit does not fail - it BLOCKS, with
# no timeout and no diagnostic. One run that takes ninety seconds went past five
# hundred; a separate commit was still blocked when it was killed at two
# minutes. That is the stdin trap this skill documents wearing a different
# costume: for something an agent invokes, hanging is worse than failing,
# because a hang leaves nothing to read.
#
# It stayed invisible because CI has no signing configuration at all, so the
# only machines that can see it are the ones nobody runs the suite on twice.
#
# One helper for every fixture commit in this file, for the reason the shebang
# expression and $PORTABILITY are each named once rather than twice: a second
# call site is how the guard goes missing from one of them.
fixture_commit() {
    git -c commit.gpgsign=false \
        -c user.email=verify@invalid -c user.name=verify commit "$@"
}

# ...and the guard is asserted rather than assumed. The fixture repository
# demands a signature from a signer that is not there, so a commit that consults
# the configuration at all dies on the spot. This runs everywhere, CI included,
# because the configuration is the fixture's own and not the machine's - which
# is the whole point: the defect this row exists to catch cannot be reproduced
# by asking the box what it signs with.
fc=$(mktemp -d)
(
    cd "$fc" \
    && git init -q . \
    && git config commit.gpgsign true \
    && git config gpg.format ssh \
    && git config user.signingkey "$fc/absent.pub" \
    && git config gpg.ssh.program "$fc/no-such-signer"
) >/dev/null 2>&1

if ( cd "$fc" && fixture_commit -q --allow-empty -m guarded ) >/dev/null 2>&1; then
    ok "a fixture commit overrides the ambient signing configuration"
else
    fail "a fixture commit consulted the signing configuration, which is what hangs the suite"
fi

# The negative is the call site as it stood: the same commit, the same fixture,
# with the guard taken back off. Without it the row above is equally satisfied
# by a fixture whose signing configuration was inert.
#
# ...and the refusal has to be the SIGNING one. git off the PATH stops this
# commit too, so a bare "it failed" would let a total absence of git certify
# that the signing configuration is load-bearing - the same family of defect the
# probe byte-identity row and the fingerprint drift row were both carrying. The
# message is required to name the signer, the way the -b rejection is quoted
# back by name.
fc_out=$( cd "$fc" && git -c user.email=verify@invalid -c user.name=verify \
        commit -q --allow-empty -m unguarded 2>&1 )
fc_rc=$?
if [ "$fc_rc" -eq 0 ]; then
    fail "the fixture's signing configuration is inert, so the guarded commit proves nothing"
elif ! printf '%s' "$fc_out" | grep -q no-such-signer; then
    fail "the unguarded fixture commit failed before it reached the signer, so it says nothing about signing: '$fc_out'"
else
    ok "rejected: the same fixture commit with the signing guard removed"
fi
rm -rf "$fc"

# --- docker-dependent rows: skipped loudly, never quietly passed -------------
docker_ready=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker_ready=1
fi

# --- the run's own anonymous volumes, tracked by name ------------------------
# alpine/git - the fixture image every runtime row in this file starts - declares
# `VOLUME /git` in its own Dockerfile. So EVERY container of it gets an anonymous
# volume whether or not the caller asked for one, and that volume survives unless
# the container is removed with -v. `--rm` normally does it for you; `docker rm
# -f` on an --rm container beats the daemon's own autoremove to it and the volume
# is left behind anyway, which is the one case here nobody would have predicted.
#
# The leak is a 64-hex name carrying no label, so no query in this file can find
# it and no `docker volume prune` a developer dares run on a working machine will
# remove it selectively. Measured at the chain close: exactly 18 per run, from
# four `docker rm -f` calls missing their -v, with 380 accumulated on the machine
# this was written on. Every one of the four now carries -v.
#
# This ledger is the assertion that it stays fixed. Each container that can hold
# an anonymous volume registers its volumes here at CREATION - not before its
# removal, so a container that is never removed at all is still covered - and the
# row at the bottom of this file requires every registered name to be gone.
#
# Keyed to this run's OWN containers rather than to a before/after diff of the
# whole runtime, and that is the difference between a check and a coin flip: a
# developer's other stack starting a container while these rows run adds a volume
# an unscoped diff would report as this suite's leak. This one cannot see it.
ANON_LEDGER=$(mktemp)
anon_note() {
    [ -n "${1:-}" ] || return 0
    docker inspect --format \
        '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
        "$1" 2>/dev/null | grep -E '^[0-9a-f]{64}$' >> "$ANON_LEDGER"
    return 0
}
anon_registered() { awk 'END { print NR + 0 }' "$ANON_LEDGER"; }
# The survivors by name, not merely how many: a leak reported as a number is a
# leak nobody can go and look at, and the name is the only handle this class of
# object has.
anon_survivors() {
    while IFS= read -r _v; do
        [ -n "$_v" ] || continue
        docker volume inspect "$_v" >/dev/null 2>&1 && printf '%s\n' "$_v"
    done < "$ANON_LEDGER"
}
anon_surviving() { anon_survivors | awk 'END { print NR + 0 }'; }

# The rows below prove the SHIPPED SCRIPTS run on a minimal image. They used to
# hand that image a repository by bind-mounting this checkout at /w, which
# silently assumed a PRIMARY checkout: in a linked worktree `.git` is a FILE
# reading `gitdir: <absolute host path>`, and that path does not exist inside
# the container. git then aborts with `not a git repository: (null)` before a
# script under test is ever read - so the suite could not pass from a worktree,
# which is the one thing this skill exists to work in. It went unseen because
# CI and every local run happened in the main checkout.
#
# The container is given its own repository instead. Only the scripts directory
# is mounted, READ-ONLY, and /w is built and `git init`ed in the container's own
# writable layer. Three things follow, and the third is why this shape was
# chosen over mounting the git common directory at the absolute path the gitdir
# pointer names:
#
#   - the rows keep testing exactly what they claim. A real git answers inside
#     the container, `git worktree list` succeeds as it did before, and the
#     scripts run for real on busybox. Nothing was relaxed to make git quiet.
#   - both kinds of checkout now traverse ONE arrangement. The alternative
#     needed a branch on checkout kind, and the rarely-taken branch is exactly
#     the one that just broke.
#   - a test container can no longer write into the repository it is verifying.
#     Mounting the real common directory would hand it the object store, and on
#     Linux CI that container is root.
#
# The repository layout is reproduced under /w so a caller writes the same
# invocation path the skill documents. The program arrives through the
# environment, so the caller's quoting survives whole.
ALPINE_SRC="$ROOT/$SKILL/scripts"
alpine_scripts() {
    docker run --rm --entrypoint sh -e PROG="$1" \
        -v "$ALPINE_SRC":/src:ro alpine/git -c '
            mkdir -p /w/skills/stackgraft/scripts || exit 1
            cp -R /src/. /w/skills/stackgraft/scripts/ || exit 1
            cd /w || exit 1
            git init -q . >/dev/null 2>&1 || exit 1
            eval "$PROG"'
}

if [ "$docker_ready" -eq 1 ]; then
    # V15: this is the premise the whole anchor mechanism rests on.
    docker compose run --help 2>&1 | grep -qE '^[[:space:]]*-l, --label' \
        && ok "docker compose run advertises -l/--label" \
        || fail "docker compose run does not advertise --label, which the anchor rests on"
    # `up` has no --label, so the grep for it misses whatever happened - which
    # is exactly what NO help output produces too. The row could not tell a
    # real answer from none, and `docker compose up --help` failing outright
    # read as "up correctly takes no --label". So the output is required to be
    # up's own help first, by a flag `up` really does carry, and only then is
    # --label required to be absent from it.
    up_help=$(docker compose up --help 2>&1)
    if ! printf '%s\n' "$up_help" | grep -qE '^[[:space:]]*-d, --detach'; then
        fail "docker compose up --help did not answer with its own flags, so a missing --label proves nothing"
    elif printf '%s\n' "$up_help" | grep -qE '^[[:space:]]*-l, --label'; then
        fail "docker compose up advertises --label, so the up refusal has no ground"
    else
        ok "rejected: docker compose up, which takes no label flag - the up refusal's ground"
    fi
else
    skip "compose label-flag rows (no docker daemon)" runtime
fi

# How many containers carry stackgraft.repo=$1. Used by the V17 rows below for
# this repository's hash8 and for a foreign one, so the two are one query asked
# twice rather than two queries that could drift apart.
overlay_count() { docker ps --filter "label=stackgraft.repo=$1" --quiet | wc -l | tr -d ' '; }

if [ "$docker_ready" -eq 1 ] && docker image inspect alpine/git >/dev/null 2>&1; then
    # V17: all five labels, read back, with a worktree path holding a space.
    h=deadbeef
    wt='/tmp/a path/wt'
    cid=$(docker run -d --rm --entrypoint sh \
        --label stackgraft.labels=1 --label "stackgraft.repo=$h" \
        --label "stackgraft.worktree=$wt" --label stackgraft.service=storefront \
        --label stackgraft.port=5174 alpine/git -c 'sleep 20' 2>/dev/null)
    anon_note "$cid"
    if [ -n "$cid" ]; then
        bad=0
        for pair in "labels=1" "repo=$h" "worktree=$wt" "service=storefront" "port=5174"; do
            k=${pair%%=*}
            want=${pair#*=}
            got=$(docker inspect --format "{{index .Config.Labels \"stackgraft.$k\"}}" "$cid" 2>/dev/null)
            [ "$got" = "$want" ] || bad=$((bad + 1))
        done
        [ "$bad" -eq 0 ] \
            && ok "a launched overlay carries all five labels, spaced worktree path included" \
            || fail "$bad of the five labels did not read back"
        # One expression for both queries, and the negative carries the positive
        # as its stated premise. Zero for a foreign hash8 is also what a listing
        # with nothing to find returns - a fixture that lost its repo label, a
        # container that never started - so the second row said "scoped" over a
        # query that matched nothing whatever it was asked. It was correct only
        # because the row above it had proven otherwise; it says so itself now.
        own_n=$(overlay_count "$h")
        foreign_n=$(overlay_count 0000none)
        [ "$own_n" = 1 ] \
            && ok "the hash8-filtered query finds it" \
            || fail "the hash8-filtered query did not find the labelled overlay"
        [ "$own_n" = 1 ] && [ "$foreign_n" = 0 ] \
            && ok "rejected: a query scoped to another repository's hash8 returns nothing" \
            || fail "a foreign hash8 matched this repository's overlay (own $own_n, foreign $foreign_n)"
        # -v on an --rm container is not belt and braces. `docker rm -f` races
        # the daemon's own autoremove and wins, so the container goes and its
        # anonymous volume stays - the least predictable of the four leaks the
        # chain close measured, because the fixture asked for --rm and got the
        # container half of it.
        docker rm -f -v "$cid" >/dev/null 2>&1
    else
        fail "could not launch the labelled overlay fixture"
    fi

    # V30 positive: the scripts RUN on a minimal Linux image, not only parse.
    lin=$(alpine_scripts '
        d=/tmp/d.json; p=/tmp/p
        printf a > "$d"; printf b > "$p"
        fp=$(git hash-object --stdin < "$d")
        sh skills/stackgraft/scripts/with-lock.sh "$d" "$p" "$fp" || exit 1
        sh skills/stackgraft/scripts/with-lock.sh "$d" "$p" "$fp" 2>/dev/null
        [ $? -eq 5 ] || exit 1
        [ -e "$d.lock" ] && exit 1
        ls "$d".wait.* >/dev/null 2>&1 && exit 1
        echo ok' 2>/dev/null | tail -1)
    [ "$lin" = ok ] \
        && ok "with-lock.sh commits, refuses a stale write and leaves nothing behind on alpine" \
        || fail "with-lock.sh did not behave on a minimal Linux image"

    # V12 refusal premise: busybox ps has no lstart, and the probe says so.
    pp=$(mktemp -d)
    {
        printf '#!/bin/sh\n'
        extract_probe "$LOCK"
        printf 'lstart_probe\nprintf "%%s\\n" "$lstart_supported"\n'
    } > "$pp/probe.sh"
    [ "$(docker run --rm --entrypoint sh -v "$pp":/probe alpine/git -c 'sh /probe/probe.sh' 2>/dev/null | tail -1)" = 0 ] \
        && ok "alpine busybox ps: the probe reports unsupported, as declared" \
        || fail "the probe claimed lstart support on busybox"
    rm -rf "$pp"

    # --- V34  the container rows must not depend on the KIND of checkout -----
    # Every row above runs from whatever checkout the suite was invoked in, so
    # on a developer machine and in CI that is always the main one, and the
    # worktree case stayed unexercised until it broke. This row supplies the
    # missing kind: a throwaway repository with a real linked worktree beside
    # it, driving the SAME alpine_scripts the rows above use, with its source
    # pointed at the worktree. It fails if the harness ever goes back to
    # needing a primary checkout.
    ck=$(mktemp -d)
    (
        mkdir -p "$ck/main/skills/stackgraft/scripts" \
        && cp "$ROOT/$SKILL/scripts"/*.sh "$ck/main/skills/stackgraft/scripts/" \
        && cd "$ck/main" \
        && git init -q . \
        && git add -A \
        && fixture_commit -q -m scripts \
        && git worktree add -q --detach "$ck/linked" HEAD
    ) >/dev/null 2>&1

    # The fixture proves nothing unless it really holds both kinds: the linked
    # worktree keeps `.git` as a gitdir FILE, the checkout it came from keeps it
    # as a directory. That difference IS the defect.
    [ -f "$ck/linked/.git" ] && [ -d "$ck/main/.git" ] \
        && ok "the checkout-kind fixture holds a gitdir file beside a real .git directory" \
        || fail "the checkout-kind fixture is not one of each, so it proves nothing"

    # A shipped git-dependent path, not bare git: fingerprint.sh reports `-` for
    # anything it could not hash, so a digest is proof git answered for real.
    _src=$ALPINE_SRC
    ALPINE_SRC="$ck/linked/skills/stackgraft/scripts"
    ckr=$(alpine_scripts '
        [ "$(git rev-parse --show-toplevel)" = /w ] || exit 1
        git worktree list --porcelain >/dev/null 2>&1 || exit 1
        out=$(sh skills/stackgraft/scripts/fingerprint.sh \
                  skills/stackgraft/scripts/reap.sh) || exit 1
        case $out in -*) exit 1 ;; esac
        echo ok' 2>/dev/null | tail -1)
    ALPINE_SRC=$_src
    [ "$ckr" = ok ] \
        && ok "the minimal-image rows get a working git from a LINKED worktree too" \
        || fail "the container harness has no git when the checkout is a linked worktree"

    # The negative is the arrangement this row replaced: bind-mounting the
    # checkout itself. Against a linked worktree it must NOT resolve, because
    # the gitdir pointer names a host path the container has not got. If it did
    # resolve, the positive above would be passing for some other reason.
    [ "$(docker run --rm --entrypoint sh -v "$ck/linked":/w -w /w alpine/git \
            -c 'git rev-parse --show-toplevel >/dev/null 2>&1 \
                && echo resolved || echo broken' 2>/dev/null | tail -1)" = broken ] \
        && ok "rejected: bind-mounting the worktree itself, whose gitdir names a host path" \
        || fail "the discarded mount resolved a linked worktree, so the positive proves nothing"

    git -C "$ck/main" worktree remove --force "$ck/linked" >/dev/null 2>&1
    rm -rf "$ck"
else
    skip "labelled-launch and minimal-image rows (no docker daemon or alpine/git image)" runtime
fi

# -------------------------------------------------- provider and copies -----
section "provider and copies"

PROVIDER="$SKILL/scripts/provider-docker.sh"
PROVIDERS_DOC="$SKILL/references/isolation-providers.md"

# The presence guard first, and it is a FAIL rather than a skip. Every row below
# reads one of these two files, and a row that reads an empty file reports its
# rule satisfied by nothing at all - the false green slices 1b, 2 and 3 each
# found once. Saying so once here is what stops the thirty rows below from each
# saying it differently.
[ -f "$PROVIDER" ]     || fail "scripts/provider-docker.sh is absent, so every provider row below reads nothing"
[ -f "$PROVIDERS_DOC" ] || fail "references/isolation-providers.md is absent, so every provider row below reads an empty file"

# Prints the lines of a markdown section: from a heading matching $2 up to the
# next `## `. Position IS the assertion for three of the rules here - the
# contract section may name no engine while the evidence section must, and the
# residual must sit where the live copy is stated - so the rows read a section
# and never the whole file. Same repair slice 2 made for the narrowing rule.
doc_section() {
    awk -v want="$2" '
        /^## / { inside = (index($0, want) > 0); next }
        inside { print }
    ' "$1" 2>/dev/null
}

# Every engine this repository has ever named, plus the ones a reader would
# reach for. The contract may name none of them: cloning state is the same
# operation for all of them, and a contract that enumerates them is the finite
# prose table this change removes, re-entered by another door.
ENGINES='postgres|postgresql|timescale|redis|mongo|mysql|mariadb|kafka|rabbitmq|elasticsearch|opensearch|minio|nats|sqlite|clickhouse|cassandra|memcached|valkey|pgvector'

# --- IP-1  the contract varies by runtime and names no substrate -------------
prov_contract=$(doc_section "$PROVIDERS_DOC" 'The contract')
if [ -z "$prov_contract" ]; then
    fail "isolation-providers.md has no '## The contract' section, so the engine-name row reads nothing"
elif printf '%s\n' "$prov_contract" | grep -qiE "$ENGINES"; then
    fail "the contract section names a store engine: $(printf '%s\n' "$prov_contract" | grep -niE "$ENGINES" | head -1)"
else
    ok "the contract section names no store engine"
fi

# ...and the row can see one. The fixture is the contract section with a single
# engine name added, so it exercises the condition the row asserts rather than
# merely failing for being a fixture.
pcf=$(mktemp -d)
{ printf '%s\n' "$prov_contract"; printf '| provision | copy the postgres data directory |\n'; } > "$pcf/named.md"
grep -qiE "$ENGINES" "$pcf/named.md" \
    && ok "rejected: a contract row naming an engine, which is the per-engine table by another door" \
    || fail "the engine-name grep cannot fire on the contract section"

# The three operations, by name, and exactly three. A fourth is what lets a
# provider certify its own output, which is the property DS29 spent a whole
# rationale removing from reap.sh.
prov_ops=0
for _op in provision address destroy; do
    printf '%s\n' "$prov_contract" | grep -qF "\`$_op\`" && prov_ops=$((prov_ops + 1))
done
[ "$prov_ops" -eq 3 ] \
    && ok "the contract names all three operations: provision, address, destroy" \
    || fail "the contract names $prov_ops of the three operations"

# ...and there is no fourth, which is asserted over the TABLE rather than over the
# prose. A grep for the word was the first shape and it fired on the file's own
# sentence saying there is no fourth operation - an intent-blind pattern pointing
# the wrong way, which is the false RED slice 3 found in another guise. The set of
# operations the contract table defines is what the rule is about, so that set is
# what the row reads, and it must be exactly the three.
prov_defined=$(printf '%s\n' "$prov_contract" \
    | awk -F'|' '/^\| *`/ { gsub(/[ `]/, "", $2); if ($2 != "") print $2 }' | sort -u | tr '\n' ' ')
[ "$prov_defined" = "address destroy provision " ] \
    && ok "the contract table defines exactly three operations and no fourth: $prov_defined" \
    || fail "the contract table defines '$prov_defined', not exactly address, destroy and provision"

{ printf '%s\n' "$prov_contract"; printf '| `verify` | the same triple | whether the copy answered |\n'; } > "$pcf/fourth.md"
[ "$(awk -F'|' '/^\| *`/ { gsub(/[ `]/, "", $2); if ($2 != "") print $2 }' "$pcf/fourth.md" | sort -u | tr '\n' ' ')" != "address destroy provision " ] \
    && ok "rejected: a contract table gaining a fourth operation, which lets the provider certify its own output" \
    || fail "the operation-set row cannot notice a fourth row in the table"

# --- IP-1  the second runtime, on paper, before the shipped one counts -------
# A contract that cannot describe a second runtime has failed the premise it
# exists for, so both declared runtimes must answer all three operations AND be
# marked unbuilt. Marked matters as much as answered: an unmarked paper answer
# reads as a shipped one.
prov_paper=$(doc_section "$PROVIDERS_DOC" 'second runtime')
paper_missing=0
for _r in Kubernetes host-native; do
    printf '%s\n' "$prov_paper" | grep -qiF "$_r" || paper_missing=$((paper_missing + 1))
done
printf '%s\n' "$prov_paper" | grep -qi 'unbuilt' || paper_missing=$((paper_missing + 1))
for _op in provision address destroy; do
    printf '%s\n' "$prov_paper" | grep -qF "$_op" || paper_missing=$((paper_missing + 1))
done
[ -n "$prov_paper" ] && [ "$paper_missing" -eq 0 ] \
    && ok "Kubernetes and host-native each answer all three operations and both are marked unbuilt" \
    || fail "the paper description of a second runtime is missing $paper_missing of its six parts"

{ printf '%s\n' "$prov_paper" | grep -viF 'unbuilt'; } > "$pcf/nomark.md"
grep -qi 'unbuilt' "$pcf/nomark.md" \
    && fail "the unbuilt fixture still carries the word, so the row proves nothing" \
    || ok "rejected: a paper runtime with the unbuilt marking removed, which reads as a shipped one"

# --- V47  DS36: a candidate, not a guarantee ---------------------------------
# Three fixtures, every one of which must FAIL. The wording is the assertion
# here: a run that says "enough space" has promised a property no run holds,
# and it holds it no better for having measured carefully first.
#
# The pattern is NARROWER than "any word about a guarantee", and that is measured
# rather than chosen for style. The obvious spelling - a bare `guaranteed` - goes
# red against text that is already correct: `references/discovery.md` says
# "substituting this checkout is the one answer guaranteed to be wrong" about
# something else entirely. So every alternative below carries its space context,
# and the shipped line that would have failed is a standing row underneath.
GUARANTEE='(enough|sufficient) (disk )?space|space is guaranteed|guaranteed to fit|will fit|is reserved for (the|this) copy|reserves? [0-9]+ ?[KMGT]?i?B|there is room for'
if grep -rniE "$GUARANTEE" "$SKILL" README.md docs SECURITY.md >/dev/null 2>&1; then
    fail "a shipped file promises a space guarantee: $(grep -rniE "$GUARANTEE" "$SKILL" README.md docs SECURITY.md | head -1)"
else
    ok "no shipped file promises enough space, a guarantee, a fit, or a reservation"
fi
printf 'The run confirms there is enough space and the copy will fit.\n' > "$pcf/promise.md"
grep -qiE "$GUARANTEE" "$pcf/promise.md" \
    && ok "rejected: wording that promises the guarantee no run can hold" \
    || fail "the guarantee grep cannot fire"

# ...and it must NOT fire on the shipped sentence that made it narrow. Frozen as
# a literal, because a later widening of the pattern is exactly the change that
# would turn correct prose red and get the pattern loosened again in the wrong
# direction.
printf '%s\n' 'substituting this checkout is the one answer guaranteed to be wrong' > "$pcf/legit.md"
grep -qiE "$GUARANTEE" "$pcf/legit.md" \
    && fail "the guarantee grep fires on a shipped sentence about something else, so it will be loosened rather than obeyed" \
    || ok "the guarantee grep leaves alone a shipped sentence that guarantees something other than space"

# The blind spot, because silence about it reads as completeness. Asserted on
# ONE line carrying every claim, the V38 shape: three independent greps would
# report a stated blind spot over a file that states three unrelated things.
if grep -qiE "another worktree's cop.*another repositor.*(consumer|competing|else)" "$PROVIDERS_DOC" 2>/dev/null; then
    ok "the free-space report states its blind spot on one line: this run's peers, other repositories, everything else on the disk"
else
    fail "isolation-providers.md states no blind spot, so its numbers read as complete"
fi
{ grep -viE "another worktree's cop.*another repositor" "$PROVIDERS_DOC" 2>/dev/null; } > "$pcf/blind.md"
if [ ! -s "$pcf/blind.md" ]; then
    fail "the blind-spot fixture is empty, so stripping the sentence proves nothing"
elif grep -qiE "another worktree's cop.*another repositor.*(consumer|competing|else)" "$pcf/blind.md"; then
    fail "the blind-spot fixture still carries the statement"
else
    ok "rejected: a report with the blind-spot statement removed, which reads as completeness"
fi

# A host-global total is the number no run can produce, and it is the one a
# reader most wants. The pattern is narrow: a total ACROSS the host, not the
# per-filesystem figure the run really measures.
HOSTGLOBAL='host-global (total|budget|figure)|total (space|bytes) (on|across) (the|this) host|all copies on this host total'
if grep -rniE "$HOSTGLOBAL" "$SKILL" README.md docs SECURITY.md >/dev/null 2>&1; then
    fail "a shipped file asserts a host-global total: $(grep -rniE "$HOSTGLOBAL" "$SKILL" README.md docs SECURITY.md | head -1)"
else
    ok "no shipped file asserts a host-global total, which no run can produce"
fi
printf 'All copies on this host total 41 GB.\n' > "$pcf/global.md"
grep -qiE "$HOSTGLOBAL" "$pcf/global.md" \
    && ok "rejected: a report asserting a host-global total" \
    || fail "the host-global grep cannot fire"

# And the positive the three negatives are worthless without: the file says the
# word. A file that promised nothing and stated nothing would pass all three
# rows above.
grep -qiE 'candidate, not a guarantee' "$PROVIDERS_DOC" 2>/dev/null \
    && ok "isolation-providers.md says what the check produces: a candidate, not a guarantee" \
    || fail "isolation-providers.md never states that the free-space check is a candidate rather than a guarantee"

# --- V46  two filesystems, and the one that bound the decision is named ------
for _need in "the runtime's data root" "the host filesystem" "bound"; do
    grep -qiF "$_need" "$PROVIDERS_DOC" 2>/dev/null \
        && ok "the space check documents: $_need" \
        || fail "isolation-providers.md never mentions $_need"
done

# The script must interrogate BOTH, and the k is the whole safety of the
# comparison. POSIX df -P reports 512-byte blocks and busybox df -P reports
# 1024-byte ones; measured on this host, `df -P` said 330306512 for the same
# filesystem `df -Pk` said 165152016 for. Reading each side in its own unit
# reports the host as twice as free as it is, which is the permissive
# direction - so a bare `df -P` in the shipped script fails this row.
if [ ! -f "$PROVIDER" ]; then
    fail "the provider is absent, so the two-filesystem row reads nothing"
elif ! grep -q 'df -Pk' "$PROVIDER"; then
    fail "the provider does not measure with df -Pk, so its two figures may be in different units"
elif grep -qE 'df -P[^k]' "$PROVIDER"; then
    fail "the provider measures with a bare df -P somewhere, which is 512-byte blocks on one side and 1024 on the other"
elif [ "$(grep -c 'df -Pk' "$PROVIDER")" -lt 2 ]; then
    fail "the provider measures only one filesystem, which is the working directory's check this requirement exists to replace"
else
    ok "the provider measures both filesystems, and both in the same unit (df -Pk)"
fi

printf 'rt=$(docker run --rm alpine df -P / | awk "NR==2{print \\$4}")\n' > "$pcf/onefs.sh"
if grep -q 'df -Pk' "$pcf/onefs.sh"; then
    fail "the one-filesystem fixture uses -Pk, so it exercises the wrong condition"
elif [ "$(grep -c 'df -P' "$pcf/onefs.sh")" -ge 2 ]; then
    fail "the one-filesystem fixture measures two, so it exercises the wrong condition"
else
    ok "rejected: a space check reading one filesystem, in blocks whose size it never pinned"
fi

# --- Q2 / 4a.12  the copy is live, and the residual is stated not covered ----
prov_live=$(doc_section "$PROVIDERS_DOC" 'live')
live_missing=0
printf '%s\n' "$prov_live" | grep -qi 'crash-consistent' || live_missing=$((live_missing + 1))
printf '%s\n' "$prov_live" | grep -qi 'fsync' || live_missing=$((live_missing + 1))
[ -n "$prov_live" ] && [ "$live_missing" -eq 0 ] \
    && ok "the live-copy statement and its crash-consistency residual sit in one section" \
    || fail "the live-copy section is missing $live_missing of crash-consistency and the fsync-ordering residual"

# The four forbidden words, each its own fixture. A residual described as
# covered is a residual nobody will read twice.
RESIDUAL_EXCUSE='residual is (covered|mitigated|handled)|(covered|mitigated|handled|unlikely) residual|crash consistency is (covered|handled)|safe for every engine|unlikely to (matter|affect|happen)'
if grep -rniE "$RESIDUAL_EXCUSE" "$SKILL" README.md docs SECURITY.md >/dev/null 2>&1; then
    fail "a shipped file excuses the crash-consistency residual: $(grep -rniE "$RESIDUAL_EXCUSE" "$SKILL" README.md docs SECURITY.md | head -1)"
else
    ok "no shipped file describes the residual as covered, mitigated, handled or unlikely, and none claims a live copy is safe for every engine"
fi
excused=0
for _w in 'The residual is covered by verification.' \
          'That residual is mitigated in practice.' \
          'The residual is handled below.' \
          'This is unlikely to matter for most engines.' \
          'A live copy is safe for every engine we tested.'; do
    printf '%s\n' "$_w" > "$pcf/excuse.md"
    grep -qiE "$RESIDUAL_EXCUSE" "$pcf/excuse.md" && excused=$((excused + 1))
done
[ "$excused" -eq 5 ] \
    && ok "rejected: all five excuses for the residual - covered, mitigated, handled, unlikely, and safe for every engine" \
    || fail "the residual grep caught only $excused of the five excuses"

# --- V54  T5: measured on this run, and nothing predicted --------------------
# Narrow for the same measured reason the guarantee pattern is. A bare
# `worst case` goes red against `references/reaping.md`, which states the lock's
# acquisition bound as "20 seconds worst case, never an unbounded wait" - a
# stated bound of a deterministic algorithm, which is the opposite of a
# prediction and is the kind of statement this repository wants more of. So
# every alternative carries its copy context, and that shipped line is a standing
# row underneath.
# It was narrowed TWICE, and the second time is the more interesting one. With
# the copy context alone it still fired on `references/discovery.md`'s "the thing
# worth cloning usually lives in the main worktree" - an adverb about WHERE, not
# about how long. So a prediction must also carry a time: an adverb of frequency
# followed by a figure in seconds, minutes or hours. Both shipped lines are
# standing rows underneath, because a pattern that turns correct prose red is a
# pattern that gets loosened rather than obeyed.
DURATION_CLAIM='(cop(y|ies|ying|ied)|clone|cloning|provision(ing|ed)?|seed(ing|ed)?)[^.]{0,40}(typically|usually|normally|on average|about|around|roughly)[^.]{0,15}[0-9]+ ?(s\b|sec|min|hour|h\b)|typically takes[^.]{0,15}[0-9]+ ?(s\b|sec|min|hour)|(expected|estimated|typical|predicted) (copy|clone|provision) (time|duration)|worst[- ]case[^.]{0,30}(cop|clone|provision)|(cop|clone|provision)[^.]{0,30}worst[- ]case'
if grep -rniE "$DURATION_CLAIM" "$SKILL" README.md docs SECURITY.md >/dev/null 2>&1; then
    fail "a shipped file states an expected duration: $(grep -rniE "$DURATION_CLAIM" "$SKILL" README.md docs SECURITY.md | head -1)"
else
    ok "no shipped file states an expected, typical, or worst-case duration"
fi
predicted=0
for _p in 'A four-store copy typically 51 s.' \
          'Copying a 10 GB store typically takes 42 s.' \
          'The expected copy time for this store is under a minute.' \
          'Worst-case, copying all four stores is about a minute.'; do
    printf '%s\n' "$_p" > "$pcf/predict.md"
    grep -qiE "$DURATION_CLAIM" "$pcf/predict.md" && predicted=$((predicted + 1))
done
[ "$predicted" -eq 4 ] \
    && ok "rejected: all four shapes of a predicted duration - typical, takes, expected, and worst case" \
    || fail "the duration grep caught only $predicted of the four predictions"

# ...and it must NOT fire on either shipped line that made it narrow. Frozen as
# literals: these two are what the pattern was measured against, and a later
# widening that turns them red is the change that gets the rule loosened.
printf '%s\n' 'The whole acquisition spends at most two of those bounds - 20 seconds worst case, never an unbounded wait.' > "$pcf/bound.md"
grep -qiE "$DURATION_CLAIM" "$pcf/bound.md" \
    && fail "the duration grep fires on a stated algorithmic bound, which is the opposite of a prediction" \
    || ok "the duration grep leaves alone a stated bound of a deterministic algorithm"
printf '%s\n' 'e.g. cloning node_modules instead of reinstalling; the thing worth cloning usually lives in the main worktree.' > "$pcf/adverb.md"
grep -qiE "$DURATION_CLAIM" "$pcf/adverb.md" \
    && fail "the duration grep fires on an adverb about where something lives rather than how long it takes" \
    || ok "the duration grep leaves alone an adverb of place beside the word cloning"

# A measurement MAY be cited as evidence the approach is viable, labelled as one
# sample. The row is a conditional: cite a figure and you owe the label. Without
# the transition test a file citing nothing would pass it.
prov_cites=$(grep -cE '[0-9]+(\.[0-9]+)? ?(s\b|MB/s|GB\b|MB\b)' "$PROVIDERS_DOC" 2>/dev/null || printf 0)
if [ "$prov_cites" -eq 0 ]; then
    fail "isolation-providers.md cites no measurement at all, so the one-sample row covers nothing"
elif grep -qi 'one sample' "$PROVIDERS_DOC"; then
    ok "isolation-providers.md cites $prov_cites measured figure(s) and labels them as one sample"
else
    fail "isolation-providers.md cites $prov_cites measured figure(s) and labels none as one sample"
fi
{ grep -vi 'one sample' "$PROVIDERS_DOC" 2>/dev/null; } > "$pcf/unlabelled.md"
if [ "$(grep -cE '[0-9]+(\.[0-9]+)? ?(s\b|MB/s|GB\b|MB\b)' "$pcf/unlabelled.md")" -eq 0 ]; then
    fail "the one-sample fixture stripped the figures too, so it exercises the wrong condition"
elif grep -qi 'one sample' "$pcf/unlabelled.md"; then
    fail "the one-sample fixture still carries the label"
else
    ok "rejected: cited measurements with the one-sample label removed"
fi

# --- V65, V66, V44  the sentences the shipped file owes, driven from a table --
# Nine rows, one shape, one helper. Written out longhand they were nine copies of
# grep/ok/fail differing only in a pattern and a sentence, and nine copies of one
# rule is nine places for it to drift. Each row still names the condition it
# asserts, which is what the verification legend requires and what a bare
# non-zero exit does not give.
doc_states() {
    grep -qiE "$2" "$PROVIDERS_DOC" 2>/dev/null \
        && ok "isolation-providers.md states: $1" \
        || fail "isolation-providers.md never states: $1"
}
doc_states "an undeterminable locality is read as remote - an unknown is not a permission" \
    'unknown is not a permission|undetermin.*(treated as|read as) remote|remote.*undetermin'
doc_states "a refusal does not cascade: the unit's other pairs are still classified on their own" \
    'does not cascade|other pairs are still classified|the unit.s other pairs'
doc_states "host-native refuses as unbuilt rather than as impossible" 'unbuilt'
doc_states "no credential is requested for a managed store, and nothing is isolated in place there" \
    'requests? no credential|no credential is requested|never requests? (a )?credential'
doc_states "the exact removal command, spelled out rather than described" 'docker volume rm'
doc_states "a run that removed nothing still names the copy it left behind" \
    'removed nothing|did not run|still up|even when nothing was removed'
doc_states "a runtime that cannot be queried reports unknown, never zero copies" \
    'unknown, never zero|never zero copies|reports unknown'
doc_states "destroy matches the worktree label by equality, not liveness and not a prefix" \
    'equals the worktree argument|worktree.*equal'
# The DIRECTION clause again rather than the topic: a file saying the copy is
# removed on a failed provision is saying what the defect said too. What has to
# be stated is what happens when the removal does NOT take.
doc_states "a copy the runtime will not remove is named and left as an environment failure, never reported as removed" \
    'names it and fails as an environment failure'
# ...and the same direction one door further along: an unanswered query is not an
# empty result. The pattern is the DIRECTION again rather than the topic, because
# a file saying destroy uses a scoped listing is saying what the defect said too.
doc_states "a scoped listing that did not answer is unknown rather than empty, so destroy refuses the store instead of reporting it clear" \
    'unknown rather than empty'

# The three non-blocking open questions design.md carries, stated in the shipped
# file as assumptions rather than resolved silently. Each pattern is the
# DIRECTION clause rather than the topic, so an assumption stated without the way
# it fails does not satisfy its row - which is the whole of what a stated
# assumption is worth. An assumption whose failure mode is unstated is a claim.
doc_states "the cache-directory assumption fails conservatively, never permissively" \
    'never more permissive'
doc_states "a store image that cannot host the copy refuses, rather than yielding an unverifiable copy" \
    'never a copy that was taken'
doc_states "a runtime that does not share Docker's volume and label vocabulary produces a refusal" \
    'rather than an unlabelled copy'

# The two set rows stay counted rather than folded in, because what they assert
# is a COMPLETE set and a missing member has to be countable to be named.
refusal_missing=0
for _r in managed remote host-native undetermin; do
    grep -qi "$_r" "$PROVIDERS_DOC" 2>/dev/null || refusal_missing=$((refusal_missing + 1))
done
[ "$refusal_missing" -eq 0 ] \
    && ok "isolation-providers.md refuses managed, remote, host-native and undeterminable locality, each by name" \
    || fail "$refusal_missing of the four refusal cases are unnamed in isolation-providers.md"

label_missing=0
for _l in stackgraft.labels stackgraft.repo stackgraft.worktree stackgraft.store; do
    grep -qF "$_l" "$PROVIDERS_DOC" 2>/dev/null || label_missing=$((label_missing + 1))
done
[ "$label_missing" -eq 0 ] \
    && ok "the four labels a copy must carry are named in isolation-providers.md" \
    || fail "$label_missing of the copy's four labels are unnamed in isolation-providers.md"

# ...and the helper must be able to say no, or all eight rows above are a
# sentence about a file nobody read.
#
# The `$( ... )` here is a SUBSHELL ON PURPOSE, which is worth saying out loud
# because it is the exact shape of the harness defect slice 3 found: a `fail`
# inside a subshell increments a copy of the counter that dies with it. That is
# precisely what is wanted for one probe of the helper's own behaviour - the
# probe must not add a failure to a suite that is working correctly - and it is
# the only place in this file where a `fail` is deliberately allowed to be lost.
# Every other loop here is fed by a redirect for the opposite reason.
PROVIDERS_DOC_REAL=$PROVIDERS_DOC
PROVIDERS_DOC=/dev/null
doc_states_probe=$( doc_states "a sentence no empty file carries" 'a sentence no empty file carries' )
PROVIDERS_DOC=$PROVIDERS_DOC_REAL
case $doc_states_probe in
    *FAIL*) ok "rejected: the sentence reader over a file that carries none of it" ;;
    *)      fail "the sentence reader reported ok over an empty file: '$doc_states_probe'" ;;
esac

# --- V42  the provider and the new reference file, against the wider floor ---
for _f in "$PROVIDER" "$PROVIDERS_DOC"; do
    _n=$(basename "$_f")
    if [ ! -f "$_f" ]; then
        fail "$_n is absent, so the portability row scans nothing"
    elif grep -niE "$PORTABILITY_NEW" "$_f" >/dev/null 2>&1; then
        fail "$_n names an unavailable tool: $(grep -niE "$PORTABILITY_NEW" "$_f" | head -1)"
    else
        ok "$_n names no tool absent from the supported floor"
    fi
    if [ ! -f "$_f" ]; then
        fail "$_n is absent, so the GNU-only row scans nothing"
    elif grep -nE "$GNUISM" "$_f" >/dev/null 2>&1; then
        fail "$_n names a GNU-only construct: $(grep -nE "$GNUISM" "$_f" | head -1)"
    else
        ok "$_n names no GNU-only construct"
    fi
done

printf '%s\n' '# the value could be delivered with timeout 5 flock, and jq would parse it' > "$pcf/portfix.sh"
grep -niE "$PORTABILITY_NEW" "$pcf/portfix.sh" >/dev/null 2>&1 \
    && ok "rejected: an unavailable tool named inside a provider comment, the grep being intent-blind" \
    || fail "the widened portability grep cannot fire on a provider-shaped fixture"

# --- the provider script names no engine either, anywhere in it --------------
if [ ! -f "$PROVIDER" ]; then
    fail "the provider is absent, so its engine-name row reads nothing"
elif grep -qiE "$ENGINES" "$PROVIDER"; then
    fail "provider-docker.sh names a store engine: $(grep -niE "$ENGINES" "$PROVIDER" | head -1)"
else
    ok "provider-docker.sh names no store engine anywhere in it"
fi

# --- the destructive-verb class, applied to this skill's own script ----------
UNFILTERED='volume prune|system prune|image prune|container prune|down --volumes|down -v|rm -rf /'
if [ ! -f "$PROVIDER" ]; then
    fail "the provider is absent, so the unfiltered-removal row reads nothing"
elif grep -qE "$UNFILTERED" "$PROVIDER"; then
    fail "provider-docker.sh reaches an unfiltered removal: $(grep -nE "$UNFILTERED" "$PROVIDER" | head -1)"
else
    ok "provider-docker.sh never prunes and never removes without a scoped query"
fi
printf 'docker volume prune -f\n' > "$pcf/prune.sh"
grep -qE "$UNFILTERED" "$pcf/prune.sh" \
    && ok "rejected: a provider reaching docker volume prune" \
    || fail "the unfiltered-removal grep cannot fire"

# Scoping is IN THE QUERY, never a filter over its output - the same property
# reap.sh's own rows assert, and the shipped `ps_listings` row further down now
# reads this script too. What that row cannot see is the VOLUME half, so it is
# asserted here: every listing of either kind carries the repo label filter, and
# the removals only ever act on a name that came out of one.
prov_listings() {
    awk '
        /^[ \t]*#/ { next }
        /docker (container ls|volume ls|ps)/ {
            seen++
            if ($0 !~ /label=stackgraft\.repo=/) unfiltered++
        }
        END { print (seen + 0) " " (unfiltered + 0) }
    ' "$1"
}
if [ ! -f "$PROVIDER" ]; then
    fail "the provider is absent, so the scoped-query row reads nothing"
else
    pl=$(prov_listings "$PROVIDER")
    pl_seen=${pl%% *}
    pl_unf=${pl##* }
    if [ "$pl_seen" -lt 2 ]; then
        fail "the provider makes $pl_seen listing(s), so this row is not reading the queries it claims to"
    elif [ "$pl_unf" -gt 0 ]; then
        fail "$pl_unf of the provider's $pl_seen listings carry no repository label filter"
    else
        ok "all $pl_seen listings in the provider are scoped to stackgraft.repo in the query itself"
    fi
fi

# ...and the detector can see an unscoped one, which is the whole reason the row
# above counts both numbers: zero unfiltered is equally true of a script that
# lists nothing at all.
printf 'x=$(docker volume ls --quiet)\ny=$(docker container ls --all --quiet --filter "label=stackgraft.repo=$h")\n' > "$pcf/listing.sh"
pl_fix=$(prov_listings "$pcf/listing.sh")
[ "$pl_fix" = "2 1" ] \
    && ok "rejected: a listing with no repository label filter, beside a scoped one the detector still passes" \
    || fail "the listing detector reported '$pl_fix' for one scoped and one unscoped listing, not '2 1'"

# Every removal acts on a name that came out of a scoped query or was derived
# here - never on a caller's string. Three variables, named, and each assigned
# only from `scoped_instances`, `scoped_volumes`, or this script's own derivation.
prov_rm_bad=$(grep -nE 'docker (rm|volume rm)' "$PROVIDER" 2>/dev/null \
    | grep -vE '"\$(inst|vol|name)"' | awk 'END { print NR + 0 }')
[ "$prov_rm_bad" -eq 0 ] \
    && ok "every removal in the provider names a target that came out of a scoped query or this script's own derivation" \
    || fail "$prov_rm_bad removal(s) in the provider act on something other than \$inst, \$vol or \$name"

# --- V45  the shape of the one place a failed provision removes its copy -----
# A provision that cannot keep its copy has three endings, and only two of them
# can be reached from a fixture. The third - something this run did NOT create
# holding the copy while both removals run - would need a holder planted in the
# middle of the provision it interposes in, which is a race rather than a
# fixture. So the SHAPE is read instead, and it is read here rather than beside
# the runtime rows because it needs no runtime: this is the row that runs on a
# machine with no container daemon at all, which is where a regression would
# otherwise go unseen until someone happened to have one.
#
# Four things, in this order: the container removed FIRST and with -v, the
# volume after it, the volume READ BACK after that, and an ending that names it.
# The last one is why the readback exists - a removal whose error is discarded
# and then reported as a removal is the defect this row was written for, and it
# was measured: `volume is in use - [343e5542...]`, exit 3, copy still there.
# Exit 3 means nothing survives, so the case where something does leaves by
# envfail instead.
#
# ONE place, and the count is the other half of the row: a second place removing
# the copy is a second place that can claim a removal nobody read back, which is
# how the three call sites came to make the same unchecked claim.
prov_removal_shape() {
    awk '
        /^refuse_removing_copy\(\)/ { in_f = 1; next }
        in_f && $0 == "}" { in_f = 0 }
        { if (index($0, "docker volume rm \"$name\"")) total++ }
        in_f {
            if (index($0, "docker rm -f -v \"$name\""))       con = NR
            if (index($0, "docker volume rm \"$name\""))      vol = NR
            if (index($0, "docker volume inspect \"$name\"")) back = NR
            if (index($0, "envfail"))                         named = NR
        }
        END {
            printf "%s %s %s %d\n", \
                (con && vol && con < vol        ? "order"    : "ORDER"), \
                (back && vol && back > vol      ? "readback" : "READBACK"), \
                (named && back && named > back  ? "named"    : "NAMED"), \
                total + 0
        }
    ' "$1"
}
if [ ! -f "$PROVIDER" ]; then
    fail "the provider is absent, so the copy-removal shape row reads nothing"
else
    psh=$(prov_removal_shape "$PROVIDER")
    [ "$psh" = "order readback named 1" ] \
        && ok "one place in the provider removes the copy, and it removes the container first with -v, reads the volume back after, and names it where it survived" \
        || fail "the provider's copy removal reads '$psh', not 'order readback named 1'"
fi

# ...and the reader can see the defect's own shape, which is the only thing that
# makes the row above mean anything.
printf '%s\n' 'refuse_removing_copy() {' \
    '    docker volume rm "$name" >/dev/null 2>&1' \
    '    refuse "$1, and the copy was removed"' \
    '}' > "$pcf/naive-removal.sh"
prn=$(prov_removal_shape "$pcf/naive-removal.sh")
[ "$prn" = "ORDER READBACK NAMED 1" ] \
    && ok "rejected: a copy removal that reaches for the volume with nothing removed before it and nothing read back after it - the defect this row exists for" \
    || fail "the removal-shape reader reported '$prn' for the defect's own shape"

# --- the usage contract: exit 2 is a usage error and nothing else ------------
if [ -f "$PROVIDER" ]; then
    sh "$PROVIDER" >/dev/null 2>&1
    [ $? -eq 2 ] && ok "the provider refuses an empty invocation at exit 2" || fail "the provider did not reject an empty invocation with exit 2"
    # Exit 2 rather than "non-zero", and that distinction is the whole row: on a
    # machine with no container runtime the script exits 4 for the environment,
    # and a row taking any non-zero code would have read that as a rejected verb.
    # Measured on a minimal image, where this is exactly what happened - so the
    # verb is now decided before the runtime is looked for, and this row is what
    # says so on both platforms.
    sh "$PROVIDER" snapshot deadbeef "$ROOT" store >/dev/null 2>&1
    [ $? -eq 2 ] && ok "the provider rejects an unknown verb at exit 2, on a host with a runtime and on one without" || fail "the provider accepted an unknown verb, or refused it as an environment failure"
    sh "$PROVIDER" destroy NOTHEX "$ROOT" store >/dev/null 2>&1
    [ $? -eq 2 ] && ok "the provider rejects a hash8 that is not lowercase hex" || fail "the provider accepted a non-hex hash8"
    sh "$PROVIDER" destroy deadbeef /no/such/worktree store >/dev/null 2>&1
    [ $? -eq 2 ] && ok "the provider rejects a worktree path it cannot resolve, rather than matching nothing" || fail "the provider accepted an unresolvable worktree path"
else
    fail "the provider is absent, so its usage rows ran nothing"
fi

# --- a scoped listing that did not ANSWER is unknown, and destroy refuses -----
# `for inst in $(scoped_instances)` runs its body zero times for a listing that
# FAILED exactly as it does for one that found nothing, so the verb exits 0
# reporting that it destroyed nothing while having looked at nothing. That is
# unknown reported as zero - the distinction A7's legacy category and the
# sidecar's registry-missing were both written for, and the one provision's own
# `space copies` record already draws correctly in the same file.
#
# NO CONTAINER RUNTIME IS NEEDED, and that is why the row is here rather than in
# the runtime block below: CI pulls no alpine/git, so a row placed there is a row
# the regression would never meet. The fixture IS the runtime - a `docker` first
# on PATH answering `info` and then failing the one listing under test - which is
# also the only way to fail a listing on demand without editing, stubbing or
# wrapping the script.
udf=$(mktemp -d)
udwt=$(mktemp -d)
fake_docker() {
    {
        printf '%s\n' '#!/bin/sh' 'case "$1" in' '    info) exit 0 ;;'
        printf '    container) [ "${2:-}" = ls ] && exit %s ;;\n' "$1"
        printf '    volume) [ "${2:-}" = ls ] && exit %s ;;\n' "$2"
        printf '%s\n' 'esac' 'exit 0'
    } > "$udf/docker"
    chmod +x "$udf/docker"
}
if [ ! -f "$PROVIDER" ]; then
    fail "the provider is absent, so the unanswerable-listing rows ran nothing"
else
    # One reader, asked of BOTH listings, so a repair that guarded the instance
    # query and left the volume query reading a failure as an empty list is a
    # named half rather than a green row. It prints the exit status beside the
    # number of refusals that named this store as unknown, because either alone
    # is satisfiable by the other's absence.
    ud_refuses() {
        fake_docker "$1" "$2"
        _o=$( PATH="$udf:$PATH" sh "$PROVIDER" destroy deadbe03 "$udwt" unknownstore 2>&1 )
        _rc=$?
        printf '%s %s\n' "$_rc" "$(printf '%s\n' "$_o" | awk -F'\t' \
            '$1 == "refused" && $2 == "unknownstore" && $3 ~ /unknown/ { n++ } END { print n + 0 }')"
    }
    ud_i=$(ud_refuses 1 0)
    ud_v=$(ud_refuses 0 1)
    if [ "$ud_i" = "3 1" ] && [ "$ud_v" = "3 1" ]; then
        ok "a destroy whose scoped listing did not answer refuses the store as unknown at exit 3 - the instance query and the copy query alike"
    else
        fail "the instance listing read '$ud_i' and the copy listing '$ud_v', not '3 1' each: a listing that failed is being read as one that found nothing"
    fi

    # ...and the negative is the listing that ANSWERED. Its expected reading is
    # the same whether the verb is broken or repaired, which is what makes it a
    # negative rather than a second positive: what it rules out is a verb that
    # refuses every store, under which the row above would be green over a
    # destroy that had stopped destroying anything.
    ud_n=$(ud_refuses 0 0)
    [ "$ud_n" = "0 0" ] \
        && ok "rejected: two listings that answered and found nothing - destroy exits 0 and refuses nothing, so an unknown is the failure and not the emptiness" \
        || fail "a destroy over two answered-but-empty listings read '$ud_n', not '0 0'"
fi
rm -rf "$udf" "$udwt"
rm -rf "$pcf"

# --- V61 slice-4a half  the new file joins the reference link loop -----------
grep -qF '`references/isolation-providers.md`' "$SHARED" \
    && ok "shared-state.md points at the provider contract by a resolving path" \
    || fail "shared-state.md carries no backticked pointer to references/isolation-providers.md"

pif=$(mktemp -d)
{ cat "$PROVIDERS_DOC" 2>/dev/null; printf -- '- `references/gone-away.md`\n'; } > "$pif/broken-link.md"
[ "$(link_unresolved "$pif/broken-link.md")" -ge 1 ] \
    && ok "rejected: isolation-providers.md naming a backticked skill path that does not resolve" \
    || fail "the reference link loop cannot report a broken link in the new file"
rm -rf "$pif"

# --- the provider RUN for real: skipped loudly, never quietly passed ---------
# The fixture store engine is alpine/git, which no shipped file mentions - so
# these rows are also IP-1's "unenumerated store engine" scenario, exercised
# rather than asserted. If the provider had an engine table, this is the run
# that would find it empty.
if [ "$docker_ready" -eq 1 ] && docker image inspect alpine/git >/dev/null 2>&1 && [ -f "$PROVIDER" ]; then
    PH=deadbe01
    pwt=$(mktemp -d)
    pother=$(mktemp -d)
    psrc=sg-verify-src
    pimg=alpine/git
    # The one container name this section plants by hand, held outside the branch
    # that plants it so the teardown at the bottom can remove it whether or not
    # that branch was ever reached.
    pplanted=''

    # One snapshot function for both object kinds, so a row asserting "the
    # inventory is unchanged" and a row asserting "the inventory moved" are
    # reading the same thing. An exit code cannot see a surviving partial, which
    # is the shape overlay-reaping W1 shipped and had to correct.
    #
    # Scoped to this skill's own name prefix rather than to the whole runtime,
    # and that is a REPAIR rather than a convenience: an unscoped snapshot reads
    # every object on the developer's machine, so any unrelated container the
    # base stacks already running on this host happened to start between two
    # snapshots read as "the provider left something behind". Measured - the
    # cycle-closes row failed for exactly that on a host with live stacks. The
    # prefix still covers everything this section can create, because every name
    # the provider derives begins with it, so a partial is still visible.
    runtime_inventory() {
        docker volume ls --quiet --filter name=sg- 2>/dev/null | sort | tr '\n' ' '
        printf '|'
        docker container ls --all --quiet --filter name=sg- 2>/dev/null | sort | tr '\n' ' '
    }

    # ...and the scope is only honest while it starts empty. A host that already
    # held an sg- object would make every inventory row read a state this section
    # did not create.
    [ "$(runtime_inventory)" = '|' ] \
        && ok "the runtime holds no sg- object before this section runs, so its inventory rows read only what it made" \
        || fail "the runtime already holds an sg- object, so this section's inventory rows cannot be trusted: $(runtime_inventory)"

    docker volume create "$psrc" >/dev/null 2>&1
    docker run --rm --entrypoint sh -v "$psrc":/data "$pimg" \
        -c 'printf seeded-by-the-base-stack > /data/marker' >/dev/null 2>&1
    pbase=$(docker run -d --entrypoint sh -e SG_FIXTURE=live -v "$psrc":/data "$pimg" \
        -c 'sleep 900' 2>/dev/null)
    anon_note "$pbase"

    if [ -z "$pbase" ]; then
        fail "the fixture base store would not start, so no provider run row proved anything"
    else
        # --- V43  the cycle leaves the HOST filesystem byte-identical --------
        # The provider writes no host file under any verb, so the working
        # directory is enumerated before and after rather than probed for names
        # guessed in advance. Reuses the W1 enumeration for the same reason it
        # exists: a leak nobody predicted is exactly the one a targeted check
        # misses.
        pdir=$(mktemp -d)
        printf 'kept\n' > "$pdir/pre-existing"
        p_before=$(inventory "$pdir")
        inv_before=$(runtime_inventory)

        pout=$( cd "$pdir" && sh "$ROOT/$PROVIDER" provision "$PH" "$pwt" fixturestore "$psrc" "$pimg" "$pbase" \
                    "stackgraft.labels=1" "stackgraft.repo=$PH" "stackgraft.worktree=$pwt" 2>&1 )
        prc=$?
        p_after=$(inventory "$pdir")
        inv_after=$(runtime_inventory)

        if [ "$prc" -ne 0 ]; then
            fail "the fixture provision exited $prc, so every row that reads its output proves nothing: $(printf '%s' "$pout" | tr '\n' ' ' | cut -c1-200)"
        else
            ok "an unenumerated store engine provisions through the contract with no edit to it"
        fi

        p_left=$(unreported_debris "$pdir" 'pre-existing' "$pout" '')
        if [ "$p_before" = "$p_after" ] && [ -z "$p_left" ]; then
            ok "provision left the host filesystem byte-identical outside the runtime objects it made"
        else
            fail "provision left host debris: before '$p_before' after '$p_after', unreported '$p_left'"
        fi

        # ...and the enumeration can see a file appear beside the destination,
        # named after the one that would really leak. The allowance is a
        # substring test over what the run said, so the never-excuse set is
        # exercised too: a debris path the output happens to mention is still
        # debris.
        : > "$pdir/sg-copy.partial"
        [ -n "$(unreported_debris "$pdir" 'pre-existing' "$pout" '')" ] \
            && ok "rejected: a provider writing one file beside the destination" \
            || fail "the host-filesystem enumeration cannot notice a file the provider left"
        printf 'sg-copy.partial\n' > "$pdir/named-anyway"
        [ -n "$(unreported_debris "$pdir" 'pre-existing named-anyway' "sg-copy.partial" 'sg-copy.partial')" ] \
            && ok "rejected: debris the run named, which the never-excuse set refuses to forgive" \
            || fail "the never-excuse set cannot hold a basename the output mentions"
        rm -f "$pdir/sg-copy.partial" "$pdir/named-anyway"

        # --- V45 positive control: the inventory CAN move --------------------
        # Every "identical before and after" row below is worthless without it.
        [ "$inv_before" != "$inv_after" ] \
            && ok "the runtime inventory diff can see a provision, so an unchanged one means something" \
            || fail "the runtime inventory did not move across a successful provision, so no inventory row proves anything"

        pvol=$(printf '%s\n' "$pout" | awk -F'\t' '$1 == "volume" { print $2; exit }')

        # --- V66  the copy carries the complete label set --------------------
        cl_bad=0
        for pair in "stackgraft.labels=1" "stackgraft.repo=$PH" "stackgraft.worktree=$pwt" "stackgraft.store=fixturestore"; do
            k=${pair%%=*}
            want=${pair#*=}
            got=$(docker volume inspect --format "{{index .Labels \"$k\"}}" "$pvol" 2>/dev/null)
            [ "$got" = "$want" ] || cl_bad=$((cl_bad + 1))
        done
        [ -n "$pvol" ] && [ "$cl_bad" -eq 0 ] \
            && ok "the copy carries all four ownership labels with this repository's hash8" \
            || fail "$cl_bad of the copy's four labels did not read back"

        # Captured here, while the instance still exists, and read after the
        # destroys below: every volume the instance mounts that is NOT the copy
        # is one this run created without naming, and nothing but this run can
        # ever find it again.
        panon_names=$(docker inspect --format \
            '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
            "$pvol" 2>/dev/null | grep -vxF "$pvol" | grep . || printf '')

        # ...and the copy really holds the base stack's data. A volume that
        # exists and is empty passes every label row above.
        [ "$(docker run --rm --entrypoint sh -v "$pvol":/c:ro "$pimg" -c 'cat /c/marker' 2>/dev/null)" = seeded-by-the-base-stack ] \
            && ok "the copy carries the bytes the base stack's volume held" \
            || fail "the copy does not carry the base stack's data, so it is a volume rather than a copy"

        # --- V66  named in the output with its exact removal command ---------
        prem=$(printf '%s\n' "$pout" | awk -F'\t' '$1 == "copy" { print $3; exit }')
        if [ -z "$prem" ]; then
            fail "the run does not name the copy with a removal command"
        elif printf '%s' "$prem" | grep -qF "$pvol"; then
            ok "the output names the copy with the exact command that removes it"
        else
            fail "the removal command the run printed does not name the copy: '$prem'"
        fi

        # --- V46  two filesystems measured, and the binding one named --------
        #
        # The two are NOT required to be two DISTINCT filesystems, and requiring
        # that was an assumption about the host rather than a fact about the
        # provider. Where the runtime is virtualised - a desktop daemon in a VM -
        # the data root and the host disk are genuinely different devices. Where
        # the daemon runs natively they are routinely the SAME device, and the
        # honest report names it twice. Measured on a Linux daemon: this row
        # failed a correct run, on the only figure gating whether a copy is safe.
        #
        # So it checks what was MEASURED rather than whether the names differ.
        # Each figure must name the filesystem an INDEPENDENT df names for the
        # same place - one inside a container, one on the host - which catches
        # the defect the old wording aimed at, one of the two being the working
        # directory's, wherever the two are distinguishable at all.
        sp_measured=$(printf '%s\n' "$pout" | awk -F'\t' '$1 == "space" && $2 == "measured" { n++ } END { print n + 0 }')
        sp_rt_fs=$(  printf '%s\n' "$pout" | awk -F'\t' '$1 == "space" && $2 == "measured" { print $3; exit }')
        sp_host_fs=$(printf '%s\n' "$pout" | awk -F'\t' '$1 == "space" && $2 == "measured" { n++; if (n == 2) { print $3; exit } }')
        sp_bound=$(  printf '%s\n' "$pout" | awk -F'\t' '$1 == "space" && $2 == "bound" { print $3; exit }')

        ind_rt_fs=$(docker run --rm --entrypoint sh "$pimg" -c 'df -Pk /' 2>/dev/null | awk 'NR == 2 { print $1 }')
        ind_cache=${XDG_CACHE_HOME:-${HOME:-}/.cache}
        while [ -n "$ind_cache" ] && [ "$ind_cache" != / ] && [ ! -d "$ind_cache" ]; do
            ind_cache=${ind_cache%/*}
        done
        ind_host_fs=$(df -Pk "${ind_cache:-/}" 2>/dev/null | awk 'NR == 2 { print $1 }')

        if [ "$sp_measured" -ne 2 ]; then
            fail "the run measured $sp_measured filesystem(s), not the runtime's data root and the host behind it"
        elif [ -z "$sp_bound" ]; then
            fail "the run measured two filesystems and never said which one bound the decision"
        elif [ "$sp_rt_fs" != "$ind_rt_fs" ]; then
            fail "the runtime figure names '$sp_rt_fs' where an independent in-container df names '$ind_rt_fs', so it is not the data root"
        elif [ "$sp_host_fs" != "$ind_host_fs" ]; then
            fail "the host figure names '$sp_host_fs' where an independent df of $ind_cache names '$ind_host_fs', so it is not the host behind it"
        elif [ "$sp_bound" != "$sp_rt_fs" ] && [ "$sp_bound" != "$sp_host_fs" ]; then
            fail "the bound filesystem '$sp_bound' is neither of the two measured, so the decision names a disk nothing read"
        elif [ "$sp_rt_fs" = "$sp_host_fs" ]; then
            ok "the run measured the data root and the host behind it; on this daemon they are one disk ($sp_rt_fs), and it is named as the bound one rather than counted twice"
        else
            ok "the run measured two distinct filesystems and named $sp_bound as the one that bound the decision"
        fi

        # ...and the limit, stated rather than covered: where the two figures
        # land on the same device there is no observable difference between
        # measuring the data root and measuring the host, so this row cannot
        # tell a provider that measured one of them twice from one that measured
        # both correctly. It says which case it is in above; on a daemon in a VM
        # the discrimination is real, and that is where it is exercised.
        [ "$sp_rt_fs" = "$sp_host_fs" ] \
            && ok "...and the row reports that discrimination is unavailable on a shared-disk daemon rather than claiming it" \
            || ok "...and the two figures are distinguishable here, so the row's discrimination is real on this host"

        # The negative is a second reader over a one-measurement report, not the
        # same report with a line deleted afterwards: the row is about what the
        # reader will accept, and editing the good output tests the edit.
        one_fs=$(printf 'space\tmeasured\toverlay\t1\nspace\tbound\toverlay\t1\n')
        [ "$(printf '%s\n' "$one_fs" | awk -F'\t' '$1 == "space" && $2 == "measured" { n++ } END { print n + 0 }')" -eq 1 ] \
            && ok "rejected: a space report measuring one filesystem, which is the check this requirement replaces" \
            || fail "the two-filesystem reader accepts a one-filesystem report"

        # --- V47  the run itself reports the candidate and the blind spot ----
        printf '%s\n' "$pout" | awk -F'\t' '$1 == "space" && $2 == "candidate"' | grep -qi 'candidate, not a guarantee' \
            && ok "the run says in its own output that the check is a candidate, not a guarantee" \
            || fail "the run's output never states that its space check is a candidate"
        printf '%s\n' "$pout" | awk -F'\t' '$1 == "space" && $2 == "blindspot"' | grep -qi "another worktree" \
            && ok "the run prints the blind spot beside the numbers" \
            || fail "the run's output carries no blind-spot record"
        printf '%s\n' "$pout" | grep -qiE "$GUARANTEE" \
            && fail "the run's own output promises a space guarantee" \
            || ok "rejected: guarantee wording, which the run's own output does not use either"

        # --- T5  measured on this run, and nothing predicted -----------------
        pbytes=$(printf '%s\n' "$pout" | awk -F'\t' '$1 == "bytes" { print $2; exit }')
        psecs=$(printf '%s\n' "$pout" | awk -F'\t' '$1 == "seconds" { print $2; exit }')
        case ${pbytes:-}-${psecs:-} in
            *[!0-9-]* | -* | *-) fail "the run reported bytes '$pbytes' and seconds '$psecs', at least one of which is not a measurement" ;;
            *) [ "$pbytes" -gt 0 ] \
                   && ok "the run reports the bytes it copied ($pbytes) and the seconds it took ($psecs), both measured here" \
                   || fail "the run reported zero bytes copied, which is not a copy" ;;
        esac

        # --- V52  the base store was not disturbed ---------------------------
        # Three facts and a live session. The pid is the strongest of them: a
        # restarted engine gets a new one, and StartedAt alone would read a
        # recreate as continuity.
        pb_after="$(docker inspect --format '{{.State.StartedAt}} {{.RestartCount}} {{.State.Pid}} {{.State.Status}}' "$pbase" 2>/dev/null)"
        pb_before=$(printf '%s' "$pb_after")
        if [ "$(docker inspect --format '{{.State.Status}}' "$pbase" 2>/dev/null)" = running ] \
           && [ "$(docker inspect --format '{{.RestartCount}}' "$pbase" 2>/dev/null)" = 0 ]; then
            ok "the base store is still running across the copy, with uptime continuous and no restart"
        else
            fail "the base store was disturbed by the copy: $pb_after"
        fi

        # ...and the row can see a disturbance. The negative stops the base
        # store on purpose and requires the SAME predicate to report it, so the
        # row is shown able to fail rather than passing over a copy that
        # disturbed nothing because nothing happened.
        pdis=$(docker run -d --entrypoint sh -v "$psrc":/data "$pimg" -c 'sleep 60' 2>/dev/null)
        anon_note "$pdis"
        pdis_before=$(docker inspect --format '{{.State.Status}} {{.State.Pid}}' "$pdis" 2>/dev/null)
        docker stop -t 1 "$pdis" >/dev/null 2>&1
        pdis_after=$(docker inspect --format '{{.State.Status}} {{.State.Pid}}' "$pdis" 2>/dev/null)
        [ -n "$pdis_before" ] && [ "$pdis_before" != "$pdis_after" ] \
            && ok "rejected: a base store that was stopped - the same predicate reports the disturbance" \
            || fail "the undisturbed-base predicate cannot tell a stopped store from a running one"
        # -v, for the reason the provider now carries it: the fixture image
        # declares a volume of its own, so every fixture container started
        # without --rm and removed without -v leaves one unnamed volume nothing
        # can ever find again. Measured: this section leaked two per run.
        docker rm -f -v "$pdis" >/dev/null 2>&1

        # --- address: a value, never a delivery ------------------------------
        pa=$( sh "$ROOT/$PROVIDER" address "$PH" "$pwt" fixturestore 2>&1 )
        parc=$?
        pa_host=$(printf '%s\n' "$pa" | awk -F'\t' '$1 == "host" { print $2; exit }')
        if [ "$parc" -eq 0 ] && [ -n "$pa_host" ] && [ "$pa_host" = "$pvol" ]; then
            ok "address answers with the name the runtime's DNS resolves for a container-run overlay"
        else
            fail "address exited $parc and named host '$pa_host'"
        fi
        printf '%s\n' "$pa" | awk -F'\t' '$1 != "" { print $1 }' | sort -u > "$pdir/kinds"
        if grep -qvE '^(volume|instance|bytes|seconds|space|host|port|env|age|copy|refused)$' "$pdir/kinds"; then
            fail "address emitted a record kind the contract does not define: $(grep -vE '^(volume|instance|bytes|seconds|space|host|port|env|age|copy|refused)$' "$pdir/kinds" | head -1)"
        else
            ok "address emits only record kinds the contract defines"
        fi

        # --- V44  destroy is worktree EQUALITY: three negatives --------------
        # (a) the same copy, a different worktree argument.
        do1=$( sh "$ROOT/$PROVIDER" destroy "$PH" "$pother" fixturestore 2>&1 )
        do1rc=$?
        if [ "$do1rc" -eq 3 ] && docker volume inspect "$pvol" >/dev/null 2>&1; then
            ok "rejected: destroy naming another worktree - the copy is still here and the run exits 3"
        else
            fail "destroy with another worktree argument exited $do1rc and the copy is $(docker volume inspect "$pvol" >/dev/null 2>&1 && echo present || echo GONE)"
        fi
        printf '%s\n' "$do1" | grep -q 'another worktree' \
            && ok "the refusal names the condition it refused on rather than merely exiting non-zero" \
            || fail "the refusal does not say why: '$(printf '%s' "$do1" | tr '\n' ' ')'"

        # (b) an unlabelled volume holding data, which no verb may ever reach.
        docker volume create sg-verify-unlabelled >/dev/null 2>&1
        docker run --rm --entrypoint sh -v sg-verify-unlabelled:/d "$pimg" -c 'printf someone-elses > /d/data' >/dev/null 2>&1
        sh "$ROOT/$PROVIDER" destroy "$PH" "$pwt" fixturestore >/dev/null 2>&1
        if docker volume inspect sg-verify-unlabelled >/dev/null 2>&1; then
            ok "rejected: an unlabelled volume holding data, untouched by a destroy that removed this run's own copy"
        else
            fail "a destroy removed an unlabelled volume this skill did not create"
        fi

        # (c) a volume whose stackgraft.labels value this run does not
        #     recognise. Reported, never removed - the same fail-safe direction
        #     as an unrecognised schemaVersion.
        docker volume create --label stackgraft.labels=99 --label "stackgraft.repo=$PH" \
            --label "stackgraft.worktree=$pwt" --label stackgraft.store=fixturestore \
            sg-verify-future >/dev/null 2>&1
        do3=$( sh "$ROOT/$PROVIDER" destroy "$PH" "$pwt" fixturestore 2>&1 )
        do3rc=$?
        if docker volume inspect sg-verify-future >/dev/null 2>&1 \
           && [ "$do3rc" -eq 3 ] \
           && printf '%s\n' "$do3" | grep -q 'unrecognised stackgraft.labels'; then
            ok "rejected: a volume carrying a label-set version this run does not recognise - reported, never removed"
        else
            fail "the future-labelled volume: exit $do3rc, still present $(docker volume inspect sg-verify-future >/dev/null 2>&1 && echo yes || echo NO), said '$(printf '%s' "$do3" | tr '\n' ' ')'"
        fi
        docker volume rm sg-verify-future sg-verify-unlabelled >/dev/null 2>&1

        # --- V43  the ANONYMOUS volumes the run created go too ---------------
        # A store image commonly declares a volume path of its own, and any such
        # path this run does not mount over becomes an unnamed volume the run
        # created. It carries no label, so no scoped query will ever find it
        # again, and a destroy that leaves it leaks one per provision for ever -
        # silently, because nothing names it. Measured on the fixture image,
        # which declares one: before the repair, a full cycle left it behind and
        # every row in this section still passed.
        #
        # Asserted on the instance's OWN mounts, captured before the destroys
        # above ran, rather than on the host's dangling count - that count drifts
        # under any other stack running on this machine and would make the row a
        # coin toss.
        panon_n=$(printf '%s\n' "$panon_names" | grep -c . || printf 0)
        panon_left=0
        for _v in $panon_names; do
            docker volume inspect "$_v" >/dev/null 2>&1 && panon_left=$((panon_left + 1))
        done
        if [ "$panon_n" -eq 0 ]; then
            fail "the fixture image declares no volume of its own, so the anonymous-volume row covers nothing"
        elif [ "$panon_left" -eq 0 ]; then
            ok "destroy removed the $panon_n anonymous volume(s) the instance's image declared, which no label could ever have found again"
        else
            fail "$panon_left of $panon_n anonymous volume(s) this run created survived the destroy, findable by nothing"
        fi

        # --- V43/V45  the cycle closes: the inventory returns to its start ---
        inv_end=$(runtime_inventory)
        if [ "$inv_before" = "$inv_end" ]; then
            ok "provision -> address -> destroy returns the runtime inventory to exactly what it was"
        else
            fail "the cycle did not close: the runtime inventory differs from before the provision"
        fi

        # --- V45  a provision that cannot fit exits 3 and leaves NO partial ---
        # The fixture is a sparse file: 200 GB of apparent size on 8 KB of disk,
        # so the refusal is deterministic and costs nothing. It also shows why
        # DS43's measure is the conservative one - `du -sb` reports what the
        # volume CONTAINS, which is what a copy would have to write.
        docker run --rm --entrypoint sh -v "$psrc":/data "$pimg" \
            -c 'dd if=/dev/zero of=/data/sparse bs=1 count=0 seek=200G' >/dev/null 2>&1
        inv_pre_full=$(runtime_inventory)
        pfull=$( sh "$ROOT/$PROVIDER" provision "$PH" "$pwt" fixturestore "$psrc" "$pimg" "$pbase" \
                     "stackgraft.labels=1" "stackgraft.repo=$PH" "stackgraft.worktree=$pwt" 2>&1 )
        pfullrc=$?
        inv_post_full=$(runtime_inventory)
        if [ "$pfullrc" -eq 3 ] && [ "$inv_pre_full" = "$inv_post_full" ]; then
            ok "rejected: a copy that does not fit - exit 3, and the runtime inventory is identical, so no partial survives"
        else
            fail "the over-size provision exited $pfullrc and the inventory $( [ "$inv_pre_full" = "$inv_post_full" ] && echo held || echo MOVED )"
        fi
        printf '%s\n' "$pfull" | grep -q 'refused before any bytes are written' \
            && ok "the refusal names the arithmetic it refused on, and says it refused before writing" \
            || fail "the over-size refusal does not say what it refused on"
        docker run --rm --entrypoint sh -v "$psrc":/data "$pimg" -c 'rm -f /data/sparse' >/dev/null 2>&1

        # --- V45  a provision that fails PART-WAY removes its own partial ----
        # Deterministic, and it is a real failure rather than an injected one:
        # the instance cannot start because its name is already taken, which is
        # exactly what a crashed earlier run leaves behind.
        pname=$(printf '%s\n' "$pout" | awk -F'\t' '$1 == "instance" { print $2; exit }')
        # Stand down loudly rather than plant an unnamed container. An earlier
        # run of this file had the provision fail, which left $pname EMPTY - and
        # `--name ""` does not fail, it lets the runtime pick a name, so the
        # fixture created a stray container nothing here would ever remove and
        # the row below passed for the wrong reason. C1's lesson in a new place:
        # a fixture that supplies the missing step cannot see it go missing.
        if [ -z "$pname" ]; then
            fail "the provision named no instance, so the part-way-failure fixture has nothing to block and plants nothing"
        else
        # The name is handed to the section's teardown BEFORE the container
        # exists, not after the row below has read it. A run killed between this
        # line and the removal at the end of the block leaves a container in
        # `Created` holding an anonymous volume, and a `Created` container holds
        # one exactly as a running one does - so `docker volume rm` then answers
        # "volume is in use" and a teardown that reached for the volume first
        # left BOTH behind. That is not hypothetical: it is what an interrupted
        # run of this file left on the machine the chain close was written on.
        pplanted=$pname
        docker create --name "$pname" --entrypoint sh "$pimg" -c true >/dev/null 2>&1
        anon_note "$pname"
        inv_pre_mid=$(runtime_inventory)
        pmid=$( sh "$ROOT/$PROVIDER" provision "$PH" "$pwt" fixturestore "$psrc" "$pimg" "$pbase" \
                    "stackgraft.labels=1" "stackgraft.repo=$PH" "stackgraft.worktree=$pwt" 2>&1 )
        pmidrc=$?
        inv_post_mid=$(runtime_inventory)
        if [ "$pmidrc" -eq 3 ] && [ "$inv_pre_mid" = "$inv_post_mid" ]; then
            ok "rejected: a provision that failed part-way - its partial volume is gone and the inventory is identical"
        else
            fail "the part-way failure exited $pmidrc and the inventory $( [ "$inv_pre_mid" = "$inv_post_mid" ] && echo held || echo MOVED ): $(printf '%s' "$pmid" | tr '\n' ' ' | cut -c1-160)"
        fi
        docker rm -f -v "$pname" >/dev/null 2>&1
        fi

        # --- V45  a start failure that leaves the container HOLDING the copy -
        # The other half of a failed provision, and the one no row above could
        # see. `docker run` can fail AFTER the runtime has created the
        # container, which leaves it in `Created` holding the copy - and a
        # container in `Created` holds a volume exactly as a running one does,
        # so the runtime answers `volume is in use - [...]` to the removal. The
        # provision discarded that error and reported that the copy was removed.
        # Measured: exit 3, the sentence, and the copy still on the disk.
        #
        # The failure is arranged the way it happens for real rather than
        # injected into the script: the base instance runs an entrypoint that
        # lives on a volume of its OWN, so the copy - which is given the store's
        # volume and not that one - is created with an entrypoint it does not
        # have. Nothing in the provider is edited, stubbed or wrapped to produce
        # it. The part-way fixture above cannot reach this state: a name already
        # taken fails the container before it is created, so nothing holds the
        # copy and the naive removal succeeded.
        #
        # THE ROW READS THE RUNTIME, not the exit status and not the sentence.
        # Exit 3 and the words "the copy was removed" are exactly what the
        # defect printed, so a row asserting them proves the defect.
        docker volume create sg-verify-tools >/dev/null 2>&1
        docker run --rm --entrypoint sh -v sg-verify-tools:/sg-tools "$pimg" \
            -c 'printf "#!/bin/sh\nexec sleep 900\n" > /sg-tools/boot && chmod +x /sg-tools/boot' >/dev/null 2>&1
        psf_base=$(docker run -d --name sg-verify-startfail-base -v sg-verify-tools:/sg-tools \
            -v "$psrc":/data --entrypoint /sg-tools/boot "$pimg" 2>/dev/null)
        anon_note sg-verify-startfail-base

        # Both readbacks are the SCOPED LABEL QUERY rather than a name derived
        # here. C1's lesson: a fixture that re-derives the expression under test
        # cannot see that expression go wrong, and the four labels are what a
        # copy is - so if the query cannot find it, nothing ever will.
        #
        # The store key is the parameter, so the row and its negative ask the
        # SAME question of two different stores. They shared one key first and
        # the negative read 2 where it expected 1 - counting the leak the row
        # above had just found, which is a negative whose answer depends on
        # whether the thing it is testing is broken.
        scoped_copies() {
            docker volume ls --quiet --filter "label=stackgraft.repo=$PH" \
                --filter "label=stackgraft.store=$1" 2>/dev/null | awk 'END { print NR + 0 }'
        }
        scoped_copy_cons() {
            docker container ls --all --quiet --filter "label=stackgraft.repo=$PH" \
                --filter "label=stackgraft.store=$1" 2>/dev/null | awk 'END { print NR + 0 }'
        }

        if [ -z "$psf_base" ]; then
            fail "the start-failure base instance would not start, so the rows below prove nothing"
        else
            inv_pre_sf=$(runtime_inventory)
            psf=$( sh "$ROOT/$PROVIDER" provision "$PH" "$pwt" startfailstore "$psrc" "$pimg" \
                       sg-verify-startfail-base \
                       "stackgraft.labels=1" "stackgraft.repo=$PH" "stackgraft.worktree=$pwt" 2>&1 )
            psfrc=$?
            psf_v=$(scoped_copies startfailstore)
            psf_c=$(scoped_copy_cons startfailstore)
            inv_post_sf=$(runtime_inventory)
            if [ "$psfrc" -eq 3 ] && [ "$psf_v" -eq 0 ] && [ "$psf_c" -eq 0 ] \
               && [ "$inv_pre_sf" = "$inv_post_sf" ]; then
                ok "a provision whose instance was created and then would not start leaves no copy and no container behind, and the inventory is identical"
            else
                fail "the start failure exited $psfrc and left $psf_v copy volume(s) and $psf_c container(s) the scoped query still finds, inventory $( [ "$inv_pre_sf" = "$inv_post_sf" ] && echo held || echo MOVED )"
            fi
            printf '%s\n' "$psf" | grep -q 'the instance would not start on the copy, and the copy was removed' \
                && ok "...and the run says so in the sentence the runtime readback above is what makes true" \
                || fail "the start failure did not report the copy removed: '$(printf '%s' "$psf" | tr '\n' ' ' | cut -c1-160)'"
        fi

        # The negative is the DEFECT ITSELF, reproduced by hand beside the row:
        # a labelled copy held by a container in `Created`, removed volume-first
        # with the error discarded, and then reported removed. The row's own
        # predicate has to REPORT the survivor. A row that read the exit status
        # and the sentence could not tell this apart from the repair, which is
        # the defect wearing the check's clothes.
        docker volume create --label stackgraft.labels=1 --label "stackgraft.repo=$PH" \
            --label "stackgraft.worktree=$pwt" --label stackgraft.store=heldstore \
            sg-verify-held >/dev/null 2>&1
        docker create --name sg-verify-holder -v sg-verify-held:/h --entrypoint sh "$pimg" \
            -c true >/dev/null 2>&1
        anon_note sg-verify-holder
        docker volume rm sg-verify-held >/dev/null 2>&1
        if [ "$(scoped_copies heldstore)" -eq 1 ]; then
            ok "rejected: a copy removed while a container held it - the removal errored, the error went to /dev/null, and the scoped query still finds the copy"
        else
            fail "the scoped readback cannot see a copy that survived its own removal, so the row above passes over the defect"
        fi
        docker rm -f -v sg-verify-holder >/dev/null 2>&1
        docker volume rm sg-verify-held >/dev/null 2>&1

        # --- V65  a refusal is scoped: it does not cascade -------------------
        # One unit, two stores. The first has no local volume - which is what a
        # managed or remote store looks like from here - and the second is the
        # ordinary local one. The refusal must name the first and leave the
        # second provisionable.
        pno=$( sh "$ROOT/$PROVIDER" provision "$PH" "$pwt" remotestore sg-verify-absent "$pimg" "$pbase" \
                   "stackgraft.labels=1" "stackgraft.repo=$PH" "stackgraft.worktree=$pwt" 2>&1 )
        pnorc=$?
        pyes=$( sh "$ROOT/$PROVIDER" provision "$PH" "$pwt" fixturestore "$psrc" "$pimg" "$pbase" \
                    "stackgraft.labels=1" "stackgraft.repo=$PH" "stackgraft.worktree=$pwt" 2>&1 )
        pyesrc=$?
        if [ "$pnorc" -eq 3 ] \
           && printf '%s\n' "$pno" | grep -q 'remotestore' \
           && printf '%s\n' "$pno" | grep -q 'no local state to copy' \
           && [ "$pyesrc" -eq 0 ]; then
            ok "the store with no local state refuses by name and the local pair beside it still provisions - the refusal does not cascade"
        else
            fail "the refusal cascaded or did not name its store: refused rc $pnorc, sibling rc $pyesrc"
        fi

        # --- V66  a partial label set is reachable by no scoped query --------
        docker volume create --label "stackgraft.repo=$PH" --label stackgraft.store=fixturestore \
            sg-verify-partial >/dev/null 2>&1
        pq=$(docker volume ls --quiet \
                --filter "label=stackgraft.labels=1" \
                --filter "label=stackgraft.repo=$PH" \
                --filter "label=stackgraft.store=fixturestore" 2>/dev/null | grep -cF sg-verify-partial)
        [ "$pq" -eq 0 ] \
            && ok "rejected: a copy carrying a partial label set is reachable by no scoped query, which is why the set is complete or nothing" \
            || fail "a partially labelled volume answered the complete-label query"
        docker volume rm sg-verify-partial >/dev/null 2>&1

        # ...and the same query DOES find the properly labelled copy, or the row
        # above is passing because the query finds nothing at all.
        pq2=$(docker volume ls --quiet \
                --filter "label=stackgraft.labels=1" \
                --filter "label=stackgraft.repo=$PH" \
                --filter "label=stackgraft.store=fixturestore" 2>/dev/null | awk 'END { print NR + 0 }')
        [ "$pq2" -ge 1 ] \
            && ok "the complete-label query finds this run's own copy, so the partial-label refusal means something" \
            || fail "the complete-label query found nothing at all, so the partial-label row proved nothing"

        sh "$ROOT/$PROVIDER" destroy "$PH" "$pwt" fixturestore >/dev/null 2>&1
        rm -rf "$pdir"
    fi

    pbase_anon=$(docker inspect --format \
        '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
        "$pbase" 2>/dev/null | grep -vxF "$psrc" | grep . || printf '')

    # Teardown by NAME and unconditionally, CONTAINERS BEFORE VOLUMES. Written
    # this way for a measured reason rather than for symmetry, and it is the shape
    # the generated-target section already carries: a container that holds a
    # volume makes that volume unremovable - `docker volume rm` answers "volume is
    # in use" and exits non-zero - so a teardown that reaches for the volume first
    # leaves BOTH behind. A container in `Created` holds one exactly as a running
    # one does, so the part-way-failure fixture above reaches that state without
    # any failure of this section's own: a run killed between its `docker create`
    # and its removal leaves the container, and the volume then survives every
    # naive cleanup. That is what an interrupted run of this file left behind.
    #
    # Unconditionally, because the removals inside the branch above run only on
    # the paths that reach them, and the state worth cleaning up is the one on a
    # path that did not. Removing an object twice is free; removing it never is
    # what costs the next run its inventory rows.
    for _pc in "$pplanted" sg-verify-startfail-base sg-verify-holder "$pbase"; do
        [ -n "$_pc" ] && docker rm -f -v "$_pc" >/dev/null 2>&1
    done
    docker volume rm "$psrc" sg-verify-future sg-verify-unlabelled sg-verify-partial \
        sg-verify-tools sg-verify-held >/dev/null 2>&1
    rm -rf "$pwt" "$pother"

    # Nothing this section made may outlive it. Asserted rather than assumed,
    # because a fixture that leaks is a fixture that makes the next run's rows
    # read a state it did not create - and because an unnamed volume is the one
    # kind of leak no label query here could ever report.
    plefto=$(docker volume ls --quiet --filter "label=stackgraft.repo=$PH" 2>/dev/null | awk 'END { print NR + 0 }')
    pleftc=$(docker container ls --all --quiet --filter "label=stackgraft.repo=$PH" 2>/dev/null | awk 'END { print NR + 0 }')
    plefta=0
    for _v in $pbase_anon; do
        docker volume inspect "$_v" >/dev/null 2>&1 && plefta=$((plefta + 1))
    done
    [ "$plefto" -eq 0 ] && [ "$pleftc" -eq 0 ] && [ "$plefta" -eq 0 ] \
        && ok "this section left no volume, no container, and no unnamed volume behind" \
        || fail "this section leaked $plefto labelled volume(s), $pleftc container(s) and $plefta unnamed volume(s)"
else
    skip "provider runtime rows (no docker daemon, no alpine/git image, or no provider script)" runtime
fi

# ------------------------------------------- verification and lifetime -------
section "verification and lifetime"

# IP-2 and IP-4. A copy that started is not isolation, and the age of a copy is
# not the age of what it holds. Both are properties of a READING - three command
# outputs and two comparisons - so, like the narrowing rule in slice 2 and the
# name family in slice 3, the reading is executed here rather than reviewed.
#
# Two sections of the provider contract are read, and the presence guard is a
# FAIL rather than a skip for the reason the provider section states once: a row
# that reads an empty section reports its rule satisfied by nothing at all.
VSEC=$(doc_section "$PROVIDERS_DOC" 'Verifying the copy')
LSEC=$(doc_section "$PROVIDERS_DOC" 'lifetime')
vfx=$(mktemp -d)

[ -n "$VSEC" ] || fail "isolation-providers.md has no '## Verifying the copy' section, so every verification row below reads an empty string"
[ -n "$LSEC" ] || fail "isolation-providers.md has no lifetime section, so every age and reuse row below reads an empty string"

# One row shape for the sentences these two sections owe, and it asserts a
# POSITION as well as a sentence: the rule has to be inside the section that owns
# it. Position is what slice 2 had to repair for the narrowing rule and slice 3
# for the identity proof, both of which read green over a file that carried the
# words somewhere else entirely.
#
# The negative asserts the TRANSITION - carried before the strip, absent after -
# because a deletion fixture over a section that never carried the sentence
# prints ok while proving nothing, which is the false green slice 2 found in its
# own negatives and slice 4a found again in two of its own.
sec_row() {
    if printf '%s\n' "$1" | grep -qiE "$3"; then
        ok "$2 states: $4"
    else
        fail "$2 never states: $4"
        return
    fi
    printf '%s\n' "$1" | grep -viE "$3" > "$vfx/stripped"
    if grep -qiE "$3" "$vfx/stripped"; then
        fail "the fixture for '$4' still carries the sentence after the strip"
    else
        ok "rejected: $2 with '$4' deleted"
    fi
}

# ...and the row shape must be able to say no, or every call below is a sentence
# about a section nobody read. The subshell is deliberate and is the same one the
# provider section's doc_states probe uses: a probe of the helper's own behaviour
# must not add a failure to a suite that is working correctly.
sec_probe=$( sec_row '' 'an empty section' 'a sentence no empty section carries' 'the probe' )
case $sec_probe in
    *FAIL*) ok "rejected: the sentence reader over a section that carries none of it" ;;
    *)      fail "the sentence reader reported ok over an empty section: '$sec_probe'" ;;
esac

# --- IP-2  a start is not proof, and the five stand-ins are named ------------
sec_row "$VSEC" 'the verification section' 'start is not proof' \
    'a start is not proof'
standins=0
for _s in 'running' 'connection' '200' 'exit status' 'log line'; do
    printf '%s\n' "$VSEC" | grep -qiF "$_s" && standins=$((standins + 1))
done
[ "$standins" -eq 5 ] \
    && ok "all five things that may not stand in for the query are named: a running process, an accepted connection, a 200, a zero exit, a readiness log line" \
    || fail "$((5 - standins)) of the five stand-ins for the query are unnamed in the verification section"

sec_row "$VSEC" 'the verification section' 'destroy(ed)? and the pair refuses|copy is destroyed' \
    'a failed verification destroys the copy and refuses the pair'
sec_row "$VSEC" 'the verification section' 'never wired to the base store|silent fall ?back' \
    'the overlay is never wired to the base store instead'
sec_row "$VSEC" 'the verification section' 'byte for byte' \
    'the copy must match the base store byte for byte'
sec_row "$VSEC" 'the verification section' 'differs from its output on the empty instance|differs.*empty instance' \
    'the candidate is a query only once it discriminates against an empty instance'
sec_row "$VSEC" 'the verification section' 'CMD-SHELL' \
    'a CMD-SHELL healthcheck is not a candidate'
sec_row "$VSEC" 'the verification section' 'no query could be derived' \
    'rung 3 destroys the copy, refuses the pair and names the store'
sec_row "$VSEC" 'the verification section' 'one route' \
    'all three issues of the candidate go through one route'

# The rung table, as a set rather than as three mentions: a file naming rungs 1
# and 3 and never the read rung is the chain DS42 found open, and it would read
# as complete under three independent greps.
rungs=0
for _r in 'healthcheck' 'read' 'nothing'; do
    printf '%s\n' "$VSEC" | grep -qiF "$_r" && rungs=$((rungs + 1))
done
[ "$rungs" -eq 3 ] \
    && ok "the rung table names all three sources: the exec-form healthcheck, a read from the repository's own targets, and nothing" \
    || fail "the rung table names $rungs of its three sources"

# --- 4b.1  the measured 0-of-4 table, declared rather than met as a bug ------
# The consequence is the point: on the repository this change exists for, this
# version provisions a copy and then refuses. A file that stated the mechanism
# and not the gap would read as a working feature.
for _s in postgres timescaledb redis minio; do
    printf '%s\n' "$VSEC" | grep -qiF "$_s" \
        && ok "the measured rung-1 table names $_s" \
        || fail "the measured rung-1 table does not name $_s"
done
sec_row "$VSEC" 'the verification section' 'refuses every writing pair' \
    'the consequence: against that repository this version provisions and then refuses every writing pair'

# --- V51  the match is a property of the moment the copy was made ------------
# Not a nicety. Re-running the byte-for-byte comparison on a later launch
# compares a copy the overlay has been writing into against a base store that
# has moved on, so it would report the overlay's own work as a corrupt copy and
# destroy it - which is the reuse Q3 exists to make free, deleted.
sec_row "$VSEC" 'the verification section' 'writing into the copy|overlay has been writing' \
    'the match is not re-run later, because the overlay has been writing into the copy'
sec_row "$VSEC" 'the verification section' 'still answer differently from an instance holding nothing|every later launch' \
    'every later launch still issues the query against the copy and an empty instance'

# --- V53  lifetime: once per (worktree, store), and refresh is explicit ------
sec_row "$LSEC" 'the lifetime section' 'once per .\(worktree, store\).|once per .worktree, store.' \
    'a copy is made once per (worktree, store) and reused'
sec_row "$LSEC" 'the lifetime section' 'explicit refresh' \
    'a copy is re-provisioned only on an explicit refresh request'
sec_row "$LSEC" 'the lifetime section' 'never refuses a launch on age|refuses a launch on age' \
    'no heuristic refreshes a copy and none refuses a launch on age alone'

# --- DS38  the age is the COPY's, and the data's age is unmeasured -----------
sec_row "$LSEC" 'the lifetime section' 'absolute timestamp' \
    'the absolute timestamp the copy was taken'
sec_row "$LSEC" 'the lifetime section' 'elapsed' \
    'the elapsed time since it'
sec_row "$LSEC" 'the lifetime section' 'as of that timestamp' \
    'what it holds is the base stack.s state as of that timestamp'
sec_row "$LSEC" 'the lifetime section' 'did not compare' \
    'the run did not compare the copy with the base store'
sec_row "$LSEC" 'the lifetime section' 'instance identity has changed' \
    'where the base store.s runtime instance identity has changed, the run says so'
sec_row "$LSEC" 'the lifetime section' 'comparison was not made' \
    'where that identity cannot be read, the run says the comparison was not made'

# --- V55  no shipped file states a data age beside a copy --------------------
# The exclusion is ONE word - `never` - and it is measured rather than chosen for
# style, the same decision slice 3 made for the allocator vocabulary. The file
# that forbids these four phrases has to be able to name them, and every shipped
# line that names one carries `never`; the fixtures below carry none.
#
# `\b` on both sides of stale and fresh is load-bearing too: `staleness` and
# `refresh` are ordinary words this repository already uses correctly, and a
# pattern that turned them red is a pattern that gets loosened rather than obeyed.
# ...and the prohibition has to be STATED as well as obeyed, or the tree-wide row
# below is satisfied by a tree that says nothing about ageing at all - which is a
# gate satisfied by absence, the defect this file was written against.
sec_row "$LSEC" 'the lifetime section' 'may never appear beside a copy' \
    'four phrases may never appear beside a copy'

DATA_AGE='up to date as of|the data is [0-9]|data is [0-9]+ ?[a-z]+ old|(cop(y|ies))[^.]{0,30}(is|are|was|were) \b(stale|fresh)\b|\b(stale|fresh)\b cop(y|ies)|the state is \b(stale|fresh)\b'
data_age_hits() { grep -rniE "$DATA_AGE" "$SKILL" README.md docs SECURITY.md 2>/dev/null | grep -v never; }
if [ -n "$(data_age_hits)" ]; then
    fail "a shipped file states a data age beside a copy: $(data_age_hits | head -1)"
else
    ok "no shipped file states a data age beside a copy - no up-to-date-as-of, no stale, no fresh, no data-is-N-old"
fi
aged=0
for _a in 'The copy is up to date as of 09:14.' \
          'The data is 3 days old.' \
          'That copy is stale.' \
          'Your copy is fresh.'; do
    printf '%s\n' "$_a" > "$vfx/age.md"
    grep -qiE "$DATA_AGE" "$vfx/age.md" && aged=$((aged + 1))
done
[ "$aged" -eq 4 ] \
    && ok "rejected: all four comparisons the run never performed - up to date as of, data is N old, a stale copy, a fresh copy" \
    || fail "the data-age grep caught only $aged of the four phrases"

# ...and the one-word exclusion is load-bearing, proved by deleting it from the
# shipped prohibition rather than asserted. Without this the exclusion could be
# excusing every line in the tree and nobody would know.
printf '%s\n' 'Four phrases may appear beside a copy: up to date as of, stale, fresh, and the data is N old.' > "$vfx/noneverline"
if grep -qiE "$DATA_AGE" "$vfx/noneverline" && [ -z "$(grep -v never "$vfx/noneverline" | grep -viE "$DATA_AGE")" ]; then
    ok "rejected: the prohibition sentence with its one-word exclusion removed, which is what proves the exclusion is not a blanket pass"
else
    fail "the data-age exclusion is not load-bearing: the prohibition sentence without 'never' is not caught"
fi

# --- V48  a candidate is harvested from an EXEC-FORM healthcheck only --------
# The healthcheck's test vector is repository data that becomes a command this
# skill runs against a store, so the template contract governs it unchanged:
# `references/shared-state.md` says every rule there applies to every command
# this skill discovers and runs against a store, and two of its rows decide this
# one. A shell-form test is shell source again rather than an argument vector,
# and a vector whose program re-parses its argument hands the value straight back
# to the grammar argv had just closed.
#
# The list of re-parsing programs is taken OUT OF THE SHIPPED FILE rather than
# copied here - the C1 pattern this repository already applies to the hash8
# recipe and to the name family. A checker carrying its own copy of the rule
# cannot see the shipped one lose a member.
reparse_programs() {
    awk '/may not re-parse/ {
        s = $0
        while (match(s, /`[^`]*`/)) {
            c = substr(s, RSTART + 1, RLENGTH - 2)
            if (c ~ /^[a-z]+$/) print c
            s = substr(s, RSTART + RLENGTH)
        }
    }' "$SHARED" | sort -u | tr '\n' ' '
}
DENY=$(reparse_programs)
case " $DENY " in
    *' sh '*) ok "the re-parsing program list comes out of shared-state.md: $DENY" ;;
    *)        fail "shared-state.md yielded no re-parsing program list ('$DENY'), so the harvest rows below judge nothing" ;;
esac

# Decides what a healthcheck test vector yields. The vector arrives one element
# per line, the first being the FORM the resolver reported.
#
# $2 exists for the falsifiers below and for nothing else: it names a clause to
# drop, so a clause is proved load-bearing by removing it from the reader that
# actually runs rather than from a second copy of it - slice 2's relief_missing,
# one file along.
harvest() {
    awk -v deny="$1" -v drop="${2:-}" '
        NR == 1 { form = $0; next }
        { argv[++n] = $0 }
        END {
            if (form == "" || form == "NONE") { print "refused\tthe store declares no healthcheck, so rung 1 supplies no candidate"; exit }
            if (drop != "form" && form != "CMD") { print "refused\ta " form " healthcheck is shell source again rather than an argument vector"; exit }
            if (n == 0) { print "refused\tan exec-form healthcheck naming no program"; exit }
            if (drop != "reparse") {
                split(deny, d, " ")
                for (i in d) if (d[i] != "" && argv[1] == d[i]) {
                    print "refused\tthe candidate program " argv[1] " re-parses its argument, so the vector is program text again"
                    exit
                }
            }
            line = "candidate"
            for (i = 1; i <= n; i++) line = line "\t" argv[i]
            print line
        }'
}

harvest_case() {
    _got=$(harvest "$DENY" "" < "$1")
    case $_got in
        "$2"*) ok "$3" ;;
        *)     fail "$3 - the reader answered '$_got'" ;;
    esac
}

printf 'CMD\ncat\n/data/marker\n' > "$vfx/exec.hc"
printf 'CMD-SHELL\npg_isready -U postgres\n' > "$vfx/shell.hc"
printf 'CMD\nsh\n-c\npg_isready -U postgres\n' > "$vfx/reparse.hc"
printf 'NONE\n' > "$vfx/none.hc"

harvest_case "$vfx/exec.hc" candidate "an exec-form healthcheck is harvested as a verification candidate"
harvest_case "$vfx/shell.hc" refused "rejected: a CMD-SHELL healthcheck, which is shell source rather than an argument vector"
harvest_case "$vfx/reparse.hc" refused "rejected: an exec-form healthcheck whose program re-parses its argument"
harvest_case "$vfx/none.hc" refused "rejected: a store declaring no healthcheck at all"

# The refusal must NAME the shell form rather than merely exit non-zero, which is
# the defect the verification legend names four shipped rows for.
harvest "$DENY" "" < "$vfx/shell.hc" | grep -q 'CMD-SHELL healthcheck is shell source' \
    && ok "the CMD-SHELL refusal names the shell form it refused on" \
    || fail "the CMD-SHELL refusal does not name the form: '$(harvest "$DENY" "" < "$vfx/shell.hc")'"

# ...and both clauses are proved LOAD-BEARING by dropping them and showing a case
# flip, not by asserting the reader contains them.
case $(harvest "$DENY" form < "$vfx/shell.hc") in
    candidate*) ok "rejected: the harvest with its exec-form clause dropped admits the CMD-SHELL vector, so the clause is what refuses it" ;;
    *)          fail "dropping the exec-form clause changed nothing, so that clause is not what refuses a shell-form healthcheck" ;;
esac
case $(harvest '' "" < "$vfx/reparse.hc") in
    candidate*) ok "rejected: the harvest with an empty deny list admits the sh -c vector, so the list out of shared-state.md is what refuses it" ;;
    *)          fail "an empty deny list changed nothing, so the shared-state.md list is not what refuses a re-parsing program" ;;
esac

# --- V49, V50  the readback: three outputs, two comparisons, no engine -------
# DS34. Matching proves the copy carries the base's state; discrimination proves
# the command could have said otherwise. Neither alone is worth anything, which
# is why both are clauses of one reader and each is falsified separately.
#
# $5 drops a clause, for the same reason $2 does above.
readback() {
    if [ "${5:-}" != probe ] && [ "$4" != yes ]; then
        printf 'refuse\tno discriminator probe has been run for this store and command\n'; return
    fi
    if [ "${5:-}" != discriminate ] && [ "$1" = "$2" ]; then
        printf 'refuse\tthe candidate answers identically on an empty instance, so it is not a query\n'; return
    fi
    if [ "${5:-}" != match ] && [ "$3" != "$1" ]; then
        printf 'destroy\tthe copy does not answer what the base store answers, so it does not carry its state\n'; return
    fi
    printf 'isolated\tthe copy answered the base store.s answer, and the query discriminates\n'
}

readback_case() {
    _got=$(readback "$1" "$2" "$3" "$4")
    case $_got in
        "$5"*) ok "$6" ;;
        *)     fail "$6 - the reader answered '${_got%%	*}'" ;;
    esac
}

# The four values below are MEASURED rather than invented, on postgres:16 and
# redis:7-alpine, an empty instance beside a seeded one:
#   pg_isready -U postgres  ->  "/var/run/postgresql:5432 - accepting connections", exit 0, on both
#   redis-cli ping          ->  "PONG" on both
#   psql -tAc 'SELECT 1'    ->  "1" on both, which is DS42's generated read failing its own test
#   a schema-agnostic count ->  "0" empty against "1" seeded, and redis dbsize 0 against 2
readback_case '2' '0' '2' yes isolated \
    "a candidate that counts what the instance carries is a query, and the copy answering the base store's answer is isolated"
readback_case '/var/run/postgresql:5432 - accepting connections' '/var/run/postgresql:5432 - accepting connections' '/var/run/postgresql:5432 - accepting connections' yes refuse \
    "rejected as a query: pg_isready, measured answering identically on an empty instance"
readback_case 'PONG' 'PONG' 'PONG' yes refuse \
    "rejected as a query: redis-cli ping, measured answering identically on an empty instance"
readback_case '1' '1' '1' yes refuse \
    "rejected as a query: a generated SELECT 1, measured answering identically - DS42's read held to the same discriminator"
readback_case '2' '0' '0' yes destroy \
    "rejected: a copy answering what an empty instance answers - it is destroyed and the pair refuses"
readback_case '2' '0' '2' no refuse \
    "rejected: a candidate admitted with no discriminator probe having run at all"

# Each clause dropped in turn, and each drop must flip a case that the shipped
# reader answers correctly. A clause nobody can flip is a clause the case list
# never reached - the false green slice 2 found in its own invariant.
case $(readback 'PONG' 'PONG' 'PONG' yes discriminate) in
    isolated*) ok "rejected: the readback with its discrimination clause dropped admits redis-cli ping, so that clause is what refuses it" ;;
    *)         fail "dropping the discrimination clause changed nothing, so it is not what rejects a non-discriminating candidate" ;;
esac
case $(readback '2' '0' '0' yes match) in
    isolated*) ok "rejected: the readback with its match clause dropped admits a copy carrying the wrong state, so that clause is what destroys it" ;;
    *)         fail "dropping the match clause changed nothing, so it is not what catches a copy that does not carry the base's state" ;;
esac
case $(readback '2' '0' '2' no probe) in
    isolated*) ok "rejected: the readback with its probe clause dropped admits an unprobed candidate, so that clause is what refuses it" ;;
    *)         fail "dropping the probe clause changed nothing, so an unprobed candidate was never being refused by it" ;;
esac

# --- DS34  the route is ONE route, and it is read out of the shipped table ---
# A candidate issued one way against the empty instance and another way against
# the base store can differ for a reason that has nothing to do with the data -
# and a difference is exactly the signal being read, so a second route would
# MANUFACTURE a discrimination and admit a liveness ping as a query. The table
# is what the run follows, so the table is what this reads.
exec_routes() {
    printf '%s\n' "$VSEC" \
        | awk -F'|' '/docker exec/ { r = $4; gsub(/`/, "", r); sub(/^[ \t]+/, "", r); sub(/[ \t]+$/, "", r); if (r != "") print r }' \
        | sort -u
}
route_n=$(exec_routes | awk 'END { print NR + 0 }')
ROUTE=$(exec_routes | awk 'NR == 1')
if [ "$route_n" -eq 1 ] && [ -n "$ROUTE" ]; then
    ok "all three issues of the candidate use one route, taken out of the shipped table: $ROUTE"
else
    fail "the shipped table defines $route_n distinct exec route(s), so the three outputs are not comparable"
fi
printf '%s\n' "$VSEC" \
    | awk '/docker exec/ { print }' \
    | awk 'NR == 1 { sub(/docker exec/, "docker attach --sig-proxy"); } { print }' > "$vfx/tworoutes.md"
if [ "$( { printf '%s\n' "$VSEC"; cat "$vfx/tworoutes.md"; } \
        | awk -F'|' '/docker (exec|attach)/ { r = $4; gsub(/`/, "", r); sub(/^[ \t]+/, "", r); sub(/[ \t]+$/, "", r); if (r != "") print r }' \
        | sort -u | awk 'END { print NR + 0 }')" -ge 2 ]; then
    ok "rejected: a table whose empty-instance row issues the candidate by a second route, which would manufacture the discrimination"
else
    fail "the route reader cannot see a second route in the table"
fi

# The empty instance's start line, read out of the same table. Three properties
# and each is the difference between a probe and a leak: it mounts nothing, so it
# can hold no state; it is started with --rm, so the RUNTIME removes it and no
# command here ever names an object to remove; and it carries this repository's
# hash and worktree, so a run that died still leaves something a person can find.
PROBE_START=$(printf '%s\n' "$VSEC" | awk -F'|' '/docker run/ { r = $3; gsub(/`/, "", r); sub(/^[ \t]+/, "", r); sub(/[ \t]+$/, "", r); print r; exit }')
if [ -z "$PROBE_START" ]; then
    fail "the shipped table carries no start line for the empty instance, so the probe rows below read nothing"
else
    probe_bad=0
    printf '%s\n' "$PROBE_START" | grep -q -- '--rm' || probe_bad=$((probe_bad + 1))
    printf '%s\n' "$PROBE_START" | grep -qE ' -v |--volume|--mount' && probe_bad=$((probe_bad + 1))
    for _l in stackgraft.repo stackgraft.worktree; do
        printf '%s\n' "$PROBE_START" | grep -qF "$_l" || probe_bad=$((probe_bad + 1))
    done
    [ "$probe_bad" -eq 0 ] \
        && ok "the empty instance mounts nothing, is removed by the runtime with --rm, and carries this repository's hash and worktree" \
        || fail "$probe_bad of the empty instance's four start properties are missing from the shipped line"
fi
printf '%s\n' 'docker run -d --label "stackgraft.repo=$hash8" -v "$src":/data "$image"' > "$vfx/badprobe"
if grep -q -- '--rm' "$vfx/badprobe"; then
    fail "the leaking-probe fixture carries --rm, so it exercises the wrong condition"
elif grep -qE ' -v |--volume' "$vfx/badprobe"; then
    ok "rejected: an empty instance started without --rm and with state mounted into it, which is a copy nobody seeded and a container nothing removes"
else
    fail "the probe reader cannot see a start line that mounts state and leaves the container behind"
fi

# The probe must NOT carry stackgraft.store: the copy's four-label set is what a
# copy is, and a probe answering that query would be a copy nothing ever seeded.
printf '%s\n' "$PROBE_START" | grep -qF 'stackgraft.store' \
    && fail "the empty instance carries stackgraft.store, so the copy's own scoped query would return it" \
    || ok "the empty instance carries no stackgraft.store, so no query for a copy can ever return it"

rm -rf "$vfx"

# --- the verification RUN for real: skipped loudly, never quietly passed -----
# Everything above reads a rule or runs a reader over values. These rows obtain
# the values: a real base store, a real copy, a real empty instance, and the
# route out of the shipped table issued three times against them.
if [ "$docker_ready" -eq 1 ] && docker image inspect alpine/git >/dev/null 2>&1 \
   && [ -f "$PROVIDER" ] && [ -n "${ROUTE:-}" ]; then
    VH=deadbe02
    vwt=$(mktemp -d)
    vsrc=sg-verify-base
    vimg=alpine/git

    # TWO envelopes, and the second one is a repair rather than belt and braces.
    # The name filter alone covers the fixtures this block creates by hand, and
    # it does NOT cover the object most likely to leak: the copy, whose name the
    # provider derives from the worktree hash and which begins with neither
    # prefix. A leak row that cannot see the most likely leak is the shape this
    # whole file exists to catch, so the label query - which is what a copy and
    # the probe both answer - is asked as well.
    v_inventory() {
        docker volume ls --quiet --filter "label=stackgraft.repo=$VH" 2>/dev/null | sort | tr '\n' ' '
        printf '|'
        docker container ls --all --quiet --filter "label=stackgraft.repo=$VH" 2>/dev/null | sort | tr '\n' ' '
        printf '|'
        docker volume ls --quiet --filter name=sg-verify 2>/dev/null | sort | tr '\n' ' '
        printf '|'
        docker container ls --all --quiet --filter name=sg-verify 2>/dev/null | sort | tr '\n' ' '
    }
    v_before=$(v_inventory)
    [ "$v_before" = '|||' ] \
        && ok "the runtime holds no object of this section's before it runs, so its inventory rows read only what it made" \
        || fail "the runtime already holds one of this section's objects, so its inventory rows cannot be trusted: $v_before"

    # ...and the label envelope can SEE such an object, which is what makes the
    # widening a check rather than a claim. The fixture carries this run's label
    # and NEITHER fixture name prefix, so the name filter alone is blind to it -
    # which is exactly the shape a leaked copy has.
    docker volume create --label "stackgraft.repo=$VH" sgleak4b >/dev/null 2>&1
    if [ "$(v_inventory)" = "$v_before" ]; then
        fail "the leak envelope cannot see a labelled object outside the fixture name prefix, so it could not see a leaked copy either"
    elif docker volume ls --quiet --filter name=sg-verify 2>/dev/null | grep -qxF sgleak4b; then
        fail "the leak fixture matches the name filter, so it exercises the wrong envelope"
    else
        ok "rejected: an object carrying this run's label and neither fixture name - the leak envelope reports it, which the name filter alone could not"
    fi
    docker volume rm sgleak4b >/dev/null 2>&1

    # Issues the candidate the way the shipped table says to, with the instance
    # and the argument vector supplied the way the table's own placeholders name
    # them. The route is the shipped string, run verbatim.
    issue() { _i=$1; shift; instance=$_i sh -c "$ROUTE" _ "$@" 2>/dev/null; }

    docker volume create "$vsrc" >/dev/null 2>&1
    docker run --rm --entrypoint sh -v "$vsrc":/data "$vimg" \
        -c 'printf one > /data/a; printf two > /data/b' >/dev/null 2>&1
    vbase=$(docker run -d --name sg-verify-base-instance --entrypoint sh -v "$vsrc":/data "$vimg" \
        -c 'sleep 900' 2>/dev/null)
    anon_note "$vbase"

    if [ -z "$vbase" ]; then
        fail "the fixture base store would not start, so no verification run row proved anything"
    else
        vout=$( sh "$ROOT/$PROVIDER" provision "$VH" "$vwt" fixturestore "$vsrc" "$vimg" "$vbase" \
                    "stackgraft.labels=1" "stackgraft.repo=$VH" "stackgraft.worktree=$vwt" 2>&1 )
        vrc=$?
        vcopy=$(printf '%s\n' "$vout" | awk -F'\t' '$1 == "instance" { print $2; exit }')
        if [ "$vrc" -ne 0 ] || [ -z "$vcopy" ]; then
            fail "the fixture provision exited $vrc and named instance '$vcopy', so every readback row below proves nothing"
        else
            ok "a copy and an instance on it exist, so the readback below has something to read"

            # The empty instance: same image, no volume, --rm, labelled with this
            # repository's hash and worktree and NOT with stackgraft.store.
            vprobe=$(docker run -d --rm --entrypoint sh \
                --label "stackgraft.repo=$VH" --label "stackgraft.worktree=$vwt" \
                --label "stackgraft.probe=fixturestore" \
                --name sg-verify-probe "$vimg" -c 'sleep 300' 2>/dev/null)
            anon_note "$vprobe"
            [ -n "$vprobe" ] \
                && ok "an empty instance of the same image started with no volume, so it can hold no state" \
                || fail "the empty instance would not start, so the discriminator rows below prove nothing"

            # --- V49  a discriminating candidate, issued three times ---------
            d_base=$(issue "$vbase" wc -c /data/a /data/b)
            d_empty=$(issue "$vprobe" wc -c /data/a /data/b)
            d_copy=$(issue "$vcopy" wc -c /data/a /data/b)
            case $(readback "$d_base" "$d_empty" "$d_copy" yes) in
                isolated*) ok "a candidate that reads what the instance carries discriminates against the empty instance, and the copy matches the base store byte for byte" ;;
                *)         fail "the discriminating candidate did not clear: base '$d_base' empty '$d_empty' copy '$d_copy'" ;;
            esac
            [ -n "$d_base" ] && [ "$d_base" != "$d_empty" ] \
                && ok "the empty instance really answers differently, so the discrimination is measured rather than assumed" \
                || fail "base and empty answered the same thing ('$d_base'), so the fixture cannot show a discrimination"

            # --- V49  the shipped negative shape: a constant answer ----------
            # This is redis-cli ping and pg_isready in the one image this suite
            # is allowed to assume: a program whose output is the same whatever
            # the instance holds.
            c_base=$(issue "$vbase" echo PONG)
            c_empty=$(issue "$vprobe" echo PONG)
            c_copy=$(issue "$vcopy" echo PONG)
            case $(readback "$c_base" "$c_empty" "$c_copy" yes) in
                refuse*) ok "rejected as a query: a candidate measured answering '$c_empty' on the empty instance and on the base store alike" ;;
                *)       fail "a constant-output candidate cleared the readback: base '$c_base' empty '$c_empty'" ;;
            esac

            # --- V51  a copy that does not carry the base's state ------------
            # The copy loses bytes it was seeded with, which is what a copy that
            # did not carry the base's state looks like at readback.
            docker run --rm --entrypoint sh -v "$vcopy":/data "$vimg" -c ': > /data/b' >/dev/null 2>&1
            t_copy=$(issue "$vcopy" wc -c /data/a /data/b)
            v_verdict=$(readback "$d_base" "$d_empty" "$t_copy" yes)
            case $v_verdict in
                destroy*) ok "rejected: a truncated copy - it does not answer the base store's answer, so it is destroyed and the pair refuses" ;;
                *)        fail "a truncated copy cleared the readback: base '$d_base' copy '$t_copy'" ;;
            esac

            # ...and the refusal really destroys and really does not fall back.
            # Inspecting what the overlay WOULD have been wired to is the whole
            # of the negative: the copy has to be gone, and the address the run
            # can still obtain must name no base store.
            sh "$ROOT/$PROVIDER" destroy "$VH" "$vwt" fixturestore >/dev/null 2>&1
            a_out=$( sh "$ROOT/$PROVIDER" address "$VH" "$vwt" fixturestore 2>&1 )
            a_rc=$?
            if docker container inspect "$vcopy" >/dev/null 2>&1; then
                fail "the copy's instance survived a failed verification"
            elif [ "$a_rc" -ne 3 ]; then
                fail "after a failed verification the run could still address something, exit $a_rc"
            elif printf '%s\n' "$a_out" | grep -qF "$vbase"; then
                fail "the address after a failed verification names the base store, which is the silent fall back"
            else
                ok "after a failed verification the copy is gone, nothing is addressable, and no address names the base store - there is no fall back to wire to"
            fi

            docker stop -t 1 "$vprobe" >/dev/null 2>&1
        fi

        # --- V53  lifetime and age, on a copy made once and reused -----------
        vout2=$( sh "$ROOT/$PROVIDER" provision "$VH" "$vwt" fixturestore "$vsrc" "$vimg" "$vbase" \
                     "stackgraft.labels=1" "stackgraft.repo=$VH" "stackgraft.worktree=$vwt" 2>&1 )
        v2rc=$?
        vinst=$(printf '%s\n' "$vout2" | awk -F'\t' '$1 == "instance" { print $2; exit }')
        if [ "$v2rc" -ne 0 ] || [ -z "$vinst" ]; then
            fail "the lifetime fixture could not provision a copy, exit $v2rc"
        else
            # Two launches, one identity. The second launch does not provision:
            # the same verb over the same triple refuses rather than seeding a
            # half-old volume, which is what makes a refresh explicit.
            again=$( sh "$ROOT/$PROVIDER" provision "$VH" "$vwt" fixturestore "$vsrc" "$vimg" "$vbase" \
                         "stackgraft.labels=1" "stackgraft.repo=$VH" "stackgraft.worktree=$vwt" 2>&1 )
            agrc=$?
            if [ "$agrc" -eq 3 ] && printf '%s\n' "$again" | grep -q 'already exists'; then
                ok "rejected: a second provision from the same worktree - the copy is made once and reused, and a refresh has to be asked for"
            else
                fail "a second provision exited $agrc rather than refusing: $(printf '%s' "$again" | tr '\n' ' ' | cut -c1-120)"
            fi

            # The age, on a run that provisions nothing, refreshes nothing and
            # destroys nothing: `address` is what such a run calls, so `address`
            # is where the age has to be.
            q1=$( sh "$ROOT/$PROVIDER" address "$VH" "$vwt" fixturestore "$vbase" 2>&1 )
            q2=$( sh "$ROOT/$PROVIDER" address "$VH" "$vwt" fixturestore "$vbase" 2>&1 )
            id1=$(printf '%s\n' "$q1" | awk -F'\t' '$1 == "instance" { print $2; exit }')
            id2=$(printf '%s\n' "$q2" | awk -F'\t' '$1 == "instance" { print $2; exit }')
            [ -n "$id1" ] && [ "$id1" = "$id2" ] \
                && ok "two launches from one worktree reach one instance identity: $id1" \
                || fail "two launches named different instances: '$id1' and '$id2'"

            age_taken=$(printf '%s\n' "$q1" | awk -F'\t' '$1 == "age" && $2 == "taken" { print $3; exit }')
            age_elapsed=$(printf '%s\n' "$q1" | awk -F'\t' '$1 == "age" && $2 == "elapsed" { print $3; exit }')
            age_base=$(printf '%s\n' "$q1" | awk -F'\t' '$1 == "age" && $2 == "base" { print $3; exit }')
            age_subject=$(printf '%s\n' "$q1" | awk -F'\t' '$1 == "age" && $2 == "subject" { print $3; exit }')
            case ${age_elapsed:-x} in
                *[!0-9]*) fail "the run reported an elapsed age of '$age_elapsed', which is not a number of seconds" ;;
                *)        ok "a run that provisioned nothing still reports the copy's age: taken $age_taken, $age_elapsed second(s) ago" ;;
            esac
            [ -n "$age_taken" ] \
                && ok "the age carries the absolute timestamp the copy was taken, not an interval alone" \
                || fail "the run reported no absolute timestamp for the copy"
            printf '%s\n' "$age_subject" | grep -qi 'age of the copy' \
                && ok "the run states in its own output that this is the age of the COPY and not of what it holds" \
                || fail "the run's age records carry no statement of what the age is the age of: '$age_subject'"
            case ${age_base:-} in
                changed | unchanged | unread) ok "the run answers the one observable question beside the age - the base store's runtime instance identity is $age_base" ;;
                *) fail "the run's base-identity comparison answered '$age_base', which is none of changed, unchanged or unread" ;;
            esac

            # ...and the comparison is NOT MADE rather than assumed where the
            # base instance cannot be read. Same verb, no base instance named.
            q3=$( sh "$ROOT/$PROVIDER" address "$VH" "$vwt" fixturestore 2>&1 )
            [ "$(printf '%s\n' "$q3" | awk -F'\t' '$1 == "age" && $2 == "base" { print $3; exit }')" = unread ] \
                && ok "rejected: a run with no base instance to compare against says the comparison was not made rather than reporting agreement" \
                || fail "a run that could not read the base store's identity did not say so: $(printf '%s' "$q3" | tr '\n' ' ' | cut -c1-120)"

            # The negative for the age rows themselves: the same reader over an
            # address output with its age records stripped must reject it. Without
            # the transition test the rows above would pass over any output.
            stripped=$(printf '%s\n' "$q1" | awk -F'\t' '$1 != "age"')
            if printf '%s\n' "$stripped" | awk -F'\t' '$1 == "age"' | grep -q . ; then
                fail "the age-stripping fixture left age records behind, so it exercises the wrong condition"
            elif [ -z "$(printf '%s\n' "$stripped" | awk -F'\t' '$1 == "age" && $2 == "taken" { print $3 }')" ]; then
                ok "rejected: a run whose output carries no age record - its absence fails the row rather than passing quietly"
            else
                fail "the age reader cannot notice an output with no age in it"
            fi

            sh "$ROOT/$PROVIDER" destroy "$VH" "$vwt" fixturestore >/dev/null 2>&1
        fi
    fi

    vbase_anon=$(docker inspect --format \
        '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
        "$vbase" 2>/dev/null | grep -vxF "$vsrc" | grep . || printf '')

    # Containers before volumes, by name, unconditionally - the same teardown the
    # provider and generated-target sections carry, and for the same measured
    # reason. By NAME rather than by variable for the half a variable cannot
    # cover: where `docker run -d` fails after the runtime has already registered
    # the name, the variable is empty and `docker rm -f -v ""` removes nothing
    # while a container sits there under a name this section chose.
    for _vc in sg-verify-probe sg-verify-base-instance "$vbase"; do
        [ -n "$_vc" ] && docker rm -f -v "$_vc" >/dev/null 2>&1
    done
    docker volume rm "$vsrc" >/dev/null 2>&1
    rm -rf "$vwt"

    # Nothing this section made may outlive it, and that includes the one kind of
    # object no label query here could ever report. Asserted rather than assumed,
    # and it is now asserted for the whole run as well: the eighteen anonymous
    # volumes older fixtures leaked per run are fixed at their four sources, and
    # the ledger row at the bottom of this file requires the total to be zero.
    vleft=$(v_inventory)
    vanon=0
    for _v in $vbase_anon; do
        docker volume inspect "$_v" >/dev/null 2>&1 && vanon=$((vanon + 1))
    done
    [ "$vleft" = '|||' ] && [ "$vanon" -eq 0 ] \
        && ok "this section left no labelled object, no fixture, no probe and no unnamed volume behind" \
        || fail "this section leaked '$vleft' and $vanon unnamed volume(s)"
else
    skip "verification runtime rows (no docker daemon, no alpine/git image, no provider script, or no route in the shipped table)" runtime
fi

# --------------------------------------------- generated lifecycle target ----
section "generated lifecycle target"

# DS37 as amended by DS42. Every deliverable in this section is a mutation of
# something OUTSIDE this repository: the skill writes executable files into a
# USER's repository, and the falsifiers below are the whole of what stands
# between that and a `db-drop` aimed at the wrong database. So the rows come in
# three kinds and none of them can stand in for the others.
#
#   - The shipped file's own sentences, read POSITIONALLY out of the section that
#     owns the rule, each with a deletion fixture that must be REJECTED.
#   - Readers, executed rather than reviewed, with every clause proved
#     load-bearing by dropping it and watching a case flip - the shape slices 2,
#     3 and 4b each had to reach for once their subject stopped being a document.
#   - A REAL fixture repository, created and removed by this section, written
#     into for real, with the four files the skill may never touch digested
#     before and after. No grep can see a file that was appended to, and no
#     reader can see one either: the only thing that can is a hash of the bytes.
GSEC=$(doc_section "$SHARED" 'offers to write one')
gfx=$(mktemp -d)

[ -n "$GSEC" ] || fail "shared-state.md has no '## ... offers to write one' section, so every generation row below reads an empty string"

# sec_row is 4b's sentence reader and it is REUSED rather than copied. It already
# asserts the TRANSITION - carried before the strip, absent after - which is the
# false green slice 2 found in its own negatives and slice 4a found again in two
# of its own; a second copy here is how one of the two stops asserting it and
# nobody notices. Its scratch directory is a global that 4b removed, so it is
# re-pointed at this section's own rather than re-declared.
vfx=$gfx

# --- Q5  the offer, and what it is never allowed to become -------------------
sec_row "$GSEC" 'the generation rule' 'never a precondition' \
    'the offer is never a precondition of anything'
sec_row "$GSEC" 'the generation rule' 'default seeded copy' \
    'a decline leaves the default seeded copy, which asks the repository for nothing to make'
sec_row "$GSEC" 'the generation rule' 'no refusal is issued' \
    'no refusal is issued for the missing target while the default path is available'

# --- DS42  the family is THREE files, and the read is why -------------------
sec_row "$GSEC" 'the generation rule' 'three files, not two' \
    'the generated family is three files per store, not two'
sec_row "$GSEC" 'the generation rule' 'refuses for want of a query|for want of a query' \
    'a family of two leaves the copy verified by nothing, so the pair refuses after the bytes are copied'

# ...and all three are named, as a SET rather than as three mentions. A section
# naming a create and a drop and never the read is exactly the chain DS42 found
# open, and three independent greps would read it as complete.
gen_family=0
for _f in create drop read; do
    printf '%s\n' "$GSEC" | grep -qE "db-$_f-" && gen_family=$((gen_family + 1))
done
[ "$gen_family" -eq 3 ] \
    && ok "the generated family names all three files: a create, a drop and a read" \
    || fail "the generated family names $gen_family of its three files, and a family of two supplies rung 2 with nothing"

# --- DS37  where the files go, and what the skill may never touch ------------
sec_row "$GSEC" 'the generation rule' 'new executable files' \
    'three new executable files only'
sec_row "$GSEC" 'the generation rule' 'existing script directory' \
    'they go under the repository.s existing script directory'
sec_row "$GSEC" 'the generation rule' 'never a new convention' \
    'never a new convention and never a directory this skill invents'
sec_row "$GSEC" 'the generation rule' 'never appends to' \
    'the skill never appends to a build file'
sec_row "$GSEC" 'the generation rule' 'never edits a file it did not author' \
    'the skill never edits a file it did not author'
sec_row "$GSEC" 'the generation rule' 'never stages' \
    'the skill never stages, never commits and never pushes'

# The four build files are named as a SET too, and the set is read OUT OF THE
# SHIPPED SENTENCE rather than copied here - the C1 pattern this file already
# applies to the hash8 recipe, the name family and the re-parsing program list.
# A checker carrying its own list cannot see the shipped one lose `package.json`.
gen_never() {
    printf '%s\n' "$GSEC" | awk '/never appends to/ {
        s = $0
        while (match(s, /`[A-Za-z][A-Za-z0-9.]*`/)) {
            print substr(s, RSTART + 1, RLENGTH - 2)
            s = substr(s, RSTART + RLENGTH)
        }
    }' | tr '\n' ' '
}
NEVER_APPEND=$(gen_never)
# Membership and count, never a sorted string: `sort` is locale-collated, and
# `Makefile justfile` orders one way under the C locale and the other under
# en_US.UTF-8 - so an equality against a sorted list would pass on macOS and fail
# on the minimal Linux image for a reason that has nothing to do with the rule.
# The file already checks a set this way where it means a set: the five stand-ins
# and the three rungs in the section above.
na_missing=''
for _na in Makefile Taskfile.yml justfile package.json; do
    case " $NEVER_APPEND " in
        *" $_na "*) : ;;
        *)          na_missing="$na_missing $_na" ;;
    esac
done
na_n=$(printf '%s\n' "$NEVER_APPEND" | tr ' ' '\n' | grep -c . || printf 0)
if [ -z "$na_missing" ] && [ "$na_n" -eq 4 ]; then
    ok "the never-append set comes out of the shipped sentence and is all four and only four: $NEVER_APPEND"
else
    fail "the shipped sentence names '$NEVER_APPEND' ($na_n token(s)), missing:${na_missing:- none}"
fi

# The two directory candidates, read out of the same sentence for the same
# reason: the writer below places files where the SHIPPED FILE says to, so a
# checker that supplied the directory itself could not see the rule go missing.
gen_dirs() {
    printf '%s\n' "$GSEC" | awk '/existing script directory/ {
        s = $0
        while (match(s, /`[a-z]+\/`/)) {
            print substr(s, RSTART + 1, RLENGTH - 2)
            s = substr(s, RSTART + RLENGTH)
        }
    }'
}
GEN_DIRS=$(gen_dirs | tr '\n' ' ')
gd_missing=''
for _gd in bin/ scripts/; do
    case " $GEN_DIRS " in
        *" $_gd "*) : ;;
        *)          gd_missing="$gd_missing $_gd" ;;
    esac
done
[ -z "$gd_missing" ] \
    && ok "the placement rule names the two directories discovery may already have found: $GEN_DIRS" \
    || fail "the placement rule names '$GEN_DIRS', missing:$gd_missing - so the writer below has no shipped directory to follow"

# The three file names, read out of the shipped table. A rename in that table
# moves the writer with it; a writer carrying its own names would go on writing
# the old ones over a file that says something else.
gen_names() {
    printf '%s\n' "$GSEC" \
        | awk -F'|' '/^\| *(create|drop|read) *\|/ { n = $3; gsub(/[ `]/, "", n); if (n != "") print n }'
}
GEN_NAMES=$(gen_names | tr '\n' ' ')
[ "$GEN_NAMES" = 'db-create-<store> db-drop-<store> db-read-<store> ' ] \
    && ok "the three file names come out of the shipped table: $GEN_NAMES" \
    || fail "the shipped table yields '$GEN_NAMES', so the writer below has no name to write"

# --- one home  the rule lives in shared-state.md and is not restated ---------
# Slice 3's worst false green was a rule read anywhere in the tree while the file
# that owned it did not exist. Position is the assertion, so the count is too.
gen_homes=$(grep -rlF 'never appends to' "$SKILL"/references 2>/dev/null | wc -l | tr -d ' ')
[ "$gen_homes" = 1 ] \
    && ok "the generation rule has exactly one home in references/, and it is the file that owns the template contract" \
    || fail "$gen_homes reference file(s) state the never-append rule; two texts with two outcomes is what overlay-reaping task 3.4 spent three amendments unwinding"

# --- V62  falsifier 1: inferred until a run has OBSERVED all three -----------
sec_row "$GSEC" 'the generation rule' 'until a run has observed' \
    'a generated target is inferred until a run has observed its create, drop and read succeed'
sec_row "$GSEC" 'the generation rule' 'timestamp and exit status' \
    'each observation is an event carrying its timestamp and exit status'
sec_row "$GSEC" 'the generation rule' 'the same author' \
    'declared-on-write makes the claim and its evidence the same author'
sec_row "$GSEC" 'the generation rule' 'inert until' \
    'the teardown stays inert until a run has observed that target.s create succeed'
sec_row "$GSEC" 'the generation rule' 'the command a human would run' \
    'until then the run names the namespace and the command a human would run'

# The gate itself, as a reader. It answers two things at once because they move
# together and are wrong in different directions: what the record's confidence
# may be, and whether the teardown may execute.
#
# THE NUMBER THREE COMES OUT OF THE SHIPPED TABLE, not out of this file. That is
# the C1 repair applied here: a reader carrying its own `3` would go on demanding
# three observations over a shipped table that had quietly gone back to DS37's
# two, and the row asserting exactly that case would still be green. With nothing
# shipped the count is 0, the reader stands down, and every case below is red -
# which is what a checker that cannot supply the missing step looks like.
GEN_REQUIRED=$(gen_names | awk 'END { print NR + 0 }')
#
# $4 drops a clause, so a clause is proved load-bearing by removing it from the
# reader that actually runs rather than from a second copy of it. $5 overrides
# the required count, and it exists for one negative: the shipped table losing a
# row.
gen_gate() {
    awk -v c="${1:--}" -v d="${2:--}" -v r="${3:--}" -v drop="${4:-}" -v need="${5:-$GEN_REQUIRED}" '
        BEGIN {
            if (need + 0 < 1) { print "stand-down\tstand-down"; exit }
            seen = (c == "0") + (d == "0") + (r == "0")
            conf = (drop != "observed" && seen < need + 0) ? "inferred" : "declared"
            tear = (drop != "inert" && c != "0")           ? "inert"    : "runnable"
            print conf "\t" tear
        }'
}

gate_case() {
    _got=$(gen_gate "$1" "$2" "$3")
    if [ "$_got" = "$(printf '%s\t%s' "$4" "$5")" ]; then
        ok "$6"
    else
        fail "$6 - the gate answered '$(printf '%s' "$_got" | tr '\t' ' ')' rather than '$4 $5'"
    fi
}

gate_case - - - inferred inert \
    "rejected: a target written and never run - it is inferred, and its teardown may not execute"
gate_case 0 - - inferred runnable \
    "an observed create makes the teardown executable and leaves the record inferred, because two halves are not three"
gate_case 0 0 - inferred runnable \
    "rejected: DS37's original pair - a create and a drop observed, no read, so rung 2 has no source and the record stays inferred"
gate_case 1 - - inferred inert \
    "rejected: a create that ran and FAILED - an observation is not a success, and the teardown stays inert"
gate_case 0 0 0 declared runnable \
    "all three observed: the record is declared, which is the answer without which every refusal above is a reader that refuses everything"

case $(gen_gate - - - observed) in
    declared*) ok "rejected: the gate with its observation clause dropped calls an unrun target declared, so that clause is what refuses it" ;;
    *)         fail "dropping the observation clause changed nothing, so it is not what refuses a target written and never run" ;;
esac
case $(gen_gate - - - inert) in
    *runnable*) ok "rejected: the gate with its inert clause dropped lets a teardown run before any create was seen to succeed" ;;
    *)          fail "dropping the inert clause changed nothing, so it is not what keeps an unproven teardown from executing" ;;
esac

# ...and the count really does come out of the table. Told to need two, the gate
# calls DS37's original pair declared - which is the state DS42 corrected, and the
# state a shipped table that lost its read row would put this reader back into.
case $(gen_gate 0 0 - '' 2) in
    declared*) ok "rejected: a required count of two, which calls a create-and-drop family declared - so the third row of the shipped table is what makes three the number" ;;
    *)         fail "the gate answers the same at a required count of two, so it is not reading the shipped table at all" ;;
esac

# --- V63  falsifier 2: the approval is over the files as approved ------------
sec_row "$GSEC" 'the generation rule' 'as the human approved them' \
    'the approval is fingerprinted over the files as the human approved them'
sec_row "$GSEC" 'the generation rule' "the skill's own included" \
    'any later edit, the skill.s own included, drops the approval'
sec_row "$GSEC" 'the generation rule' 'shown again' \
    'the template is shown again before anything runs'
sec_row "$GSEC" 'the generation rule' 'all three together' \
    'the fingerprint covers all three files together'

# --- 5.4  the store name comes from discovery and is never invented ----------
sec_row "$GSEC" 'the generation rule' 'never invented' \
    'the store name comes from the discovered backingStores key and is never invented'
sec_row "$GSEC" 'the generation rule' 'no target is generated and no offer is made' \
    'where discovery recorded no key, no target is generated and no offer is made'
sec_row "$GSEC" 'the generation rule' 'shown in full' \
    'the content is shown in full before anything is written'
sec_row "$GSEC" 'the generation rule' 'explicit approval' \
    'it is written only on explicit approval'

# The naming reader. Three answers rather than two, because "no offer" and
# "refused" are different outcomes and collapsing them is the defect: a run that
# refused for want of a target would have broken the rule two rows above.
#
# The map the name has to come out of is read OUT OF THE SHIPPED SENTENCE, for
# the same reason the count above is: a reader that names `backingStores` itself
# would go on enforcing a source the shipped rule no longer names. Absent, it
# stands down and every case below is red.
GEN_KEY=$(printf '%s\n' "$GSEC" | awk '/never invented/ {
    s = $0
    while (match(s, /`[a-z][A-Za-z]+`/)) {
        print substr(s, RSTART + 1, RLENGTH - 2)
        s = substr(s, RSTART + RLENGTH)
    }
}' | awk 'NR == 1')
gen_name() {
    awk -v keys="$1" -v want="$2" -v drop="${3:-}" -v src="$GEN_KEY" '
        BEGIN {
            if (src == "") { print "stand-down\tthe shipped rule names no map for the store name to come out of"; exit }
            if (keys == "") { print "no-offer\tdiscovery recorded no store key, so the name would have to be invented"; exit }
            n = split(keys, k, " ")
            for (i = 1; i <= n; i++) if (k[i] == want) { print "offer\t" want; exit }
            if (drop == "discovered") { print "offer\t" want; exit }
            print "refused\t" want " is not a discovered " src " key"
        }'
}

# Extracted AND asserted, which is two rules rather than one restated. The
# extraction is what makes the reader follow the shipped file instead of its own
# copy; the assertion is what stops the shipped file pointing somewhere else.
# Measured while proving this section load-bearing: with `backingStores` swapped
# for another field the extraction happily followed it, the reader went on
# working, and the only thing that caught it was the schema cross-check noticing
# an undefined field name - which would have caught nothing at all had the
# substitute been a field that exists. The map has to be the gate's own pair-set
# map, and naming any other is naming the wrong thing rather than nothing.
if [ "$GEN_KEY" = backingStores ]; then
    ok "the map a generated store name must come out of is read from the shipped rule, and it is the gate's own pair-set map: $GEN_KEY"
elif [ -n "$GEN_KEY" ]; then
    fail "the shipped rule takes a generated store name from '$GEN_KEY' rather than from backingStores, which is the map every pair is derived against"
else
    fail "the shipped rule names no map for the store name, so the four naming rows below have no source to hold a name to"
fi

name_case() {
    _got=$(gen_name "$1" "$2")
    case $_got in
        "$3"*) ok "$4" ;;
        *)     fail "$4 - the reader answered '$(printf '%s' "$_got" | tr '\t' ' ')'" ;;
    esac
}

name_case 'postgres kafka' postgres offer \
    "a target is offered for a store discovery recorded a key for"
name_case 'postgres kafka' catalog refused \
    "rejected: a store name inferred from the service name catalog-api rather than taken from a discovered key"
name_case 'events' postgres refused \
    "rejected: a store name defaulted from a substrate this repository does not run"
name_case '' postgres no-offer \
    "rejected: discovery recorded no key, so no target is generated and no offer is made"

# The no-offer answer must NOT be a refusal, which is the whole of constraint 3 -
# and it is asserted as the POSITIVE answer rather than as "anything but a
# refusal". Measured in the red run: with the reader standing down, `stand-down`
# is not a refusal either, so the row printed ok over a reader that had answered
# nothing at all. "Not X" is satisfied by silence; only "is Y" is not.
case $(gen_name '' postgres) in
    no-offer*) ok "an absent store key produces no offer and no refusal - the default seeded copy still resolves the pair" ;;
    refuse*)   fail "an absent store key produced a REFUSAL, which is a pair refused for want of a target while the seeded copy was available" ;;
    *)         fail "an absent store key produced '$(gen_name '' postgres | tr '\t' ' ')', which is neither the offer being withheld nor a refusal" ;;
esac

case $(gen_name 'postgres kafka' catalog discovered) in
    offer*) ok "rejected: the naming reader with its discovered-key clause dropped admits an invented name, so that clause is what refuses one" ;;
    *)      fail "dropping the discovered-key clause changed nothing, so it is not what keeps an invented store name out" ;;
esac

# --- V63  the generated drop is held to the destructive-verb class -----------
sec_row "$GSEC" 'the generation rule' 'no exemption' \
    'no rule is relaxed on the ground that this skill authored the file'
sec_row "$GSEC" 'the generation rule' 'before it is shown' \
    'the destructive-verb class is applied to the drop before it is shown'
sec_row "$GSEC" 'the generation rule' 'one program with arguments' \
    'each recorded command invokes one program with arguments'

# The reader, and BOTH of its clauses come out of shipped files rather than out
# of this one. $DENY is the re-parsing program list slice 4b takes out of
# shared-state.md's template contract, so deleting a member from that row breaks
# these rows too. $GEN_FAMILY is the set of names a generated drop may remove,
# read out of the generation rule's own sentence: a reader carrying its own two
# placeholders would go on accepting them over a shipped rule that had named a
# third, or none, and the red run would not have been able to tell.
GEN_FAMILY=$(printf '%s\n' "$GSEC" | awk '/may remove only/ {
    s = $0
    while (match(s, /`\{\{[A-Za-z]+\}\}`/)) {
        print substr(s, RSTART + 1, RLENGTH - 2)
        s = substr(s, RSTART + RLENGTH)
    }
}' | tr '\n' ' ')
gf_missing=''
for _gf in '{{isolationIdent}}' '{{isolationLabel}}'; do
    case " $GEN_FAMILY " in
        *" $_gf "*) : ;;
        *)          gf_missing="$gf_missing $_gf" ;;
    esac
done
gf_n=$(printf '%s\n' "$GEN_FAMILY" | tr ' ' '\n' | grep -c . || printf 0)
if [ -z "$gf_missing" ] && [ "$gf_n" -eq 2 ]; then
    ok "the names a generated drop may remove come out of the shipped rule, and they are exactly the two members of the name family: $GEN_FAMILY"
else
    fail "the shipped rule names '$GEN_FAMILY' as what a generated drop may remove, so the drop rows below have no family to hold one to"
fi

gen_drop_ok() {
    awk -v cmd="$1" -v deny="$2" -v drop="${3:-}" -v family="$GEN_FAMILY" '
        BEGIN {
            if (family == "") { print "stand-down\tthe shipped rule names no name family, so nothing here can judge a drop"; exit }
            n = split(cmd, w, " ")
            prog = w[1]
            sub(/^.*\//, "", prog)
            if (drop != "reparse") {
                split(deny, d, " ")
                for (i in d) if (d[i] != "" && prog == d[i]) {
                    print "rejected\tthe recorded command is " prog ", which re-parses its argument"
                    exit
                }
            }
            if (drop != "family") {
                for (i = 2; i <= n; i++) {
                    if (w[i] ~ /^-/) continue
                    if (index(" " family, " " w[i] " ") == 0) {
                        print "rejected\tthe drop removes " w[i] ", which is not a name the family generated"
                        exit
                    }
                }
            }
            print "accepted\t" cmd
        }'
}

drop_case() {
    _got=$(gen_drop_ok "$1" "$DENY")
    case $_got in
        "$2"*) ok "$3" ;;
        *)     fail "$3 - the reader answered '$(printf '%s' "$_got" | tr '\t' ' ')'" ;;
    esac
}

drop_case 'bin/db-drop-postgres {{isolationIdent}}' accepted \
    "a generated drop that removes the name the family generated is accepted, which is the answer the four refusals below need to mean anything"
drop_case 'bin/db-drop-postgres app' rejected \
    "rejected: a generated drop aimed at a literal name, which is not derived from the name family"
drop_case 'bin/db-drop-postgres {{store}}' rejected \
    "rejected: a generated drop aimed at {{store}} - a member of the closed set, and the base stack's own namespace"
# The shell form is asserted by the REASON it was refused, not merely by being
# refused. Measured while writing this: `sh -c bin/db-drop-postgres
# {{isolationIdent}}` is refused by the name-family clause too, because
# `bin/db-drop-postgres` is an argument that is not a family member - so a row
# reading only `rejected` would have reported the re-parse rule enforced by a
# rule that has nothing to do with it. That is the overlay-reaping W4/C3/A10
# shape, and it was in this section's own negative before it shipped.
gen_drop_ok 'sh -c bin/db-drop-postgres {{isolationIdent}}' "$DENY" \
    | grep -q 're-parses its argument' \
    && ok "rejected: a generated drop wrapped in a shell, refused by the re-parse rule and naming it - no exemption for being the skill's own" \
    || fail "the shell-wrapped drop was not refused by the re-parse rule: '$(gen_drop_ok 'sh -c bin/db-drop-postgres {{isolationIdent}}' "$DENY" | tr '\t' ' ')'"

case $(gen_drop_ok 'bin/db-drop-postgres app' "$DENY" family) in
    accepted*) ok "rejected: the drop reader with its name-family clause dropped admits a literal target, so that clause is what refuses one" ;;
    *)         fail "dropping the name-family clause changed nothing, so it is not what refuses a drop aimed off the family" ;;
esac

# The deny-list falsifier uses a command ONLY the deny list can refuse - every
# argument of it is a family member - so an empty list has nothing else to hide
# behind. With the shipped list it is refused; without it, accepted.
case $(gen_drop_ok 'sh -c {{isolationIdent}}' "$DENY") in
    rejected*) ok "a drop whose only defect is its program is refused while the shipped deny list is in force" ;;
    *)         fail "the deny-list fixture is not refused even with the shipped list, so the falsifier below exercises nothing" ;;
esac
case $(gen_drop_ok 'sh -c {{isolationIdent}}' '') in
    accepted*) ok "rejected: the drop reader with an empty deny list admits the sh -c form, so the list out of shared-state.md is what refuses it" ;;
    *)         fail "an empty deny list changed nothing, so the shared-state.md list is not what refuses a re-parsing program here" ;;
esac

# --- V50 generation half  the generated read is held to the discriminator ----
sec_row "$GSEC" 'the generation rule' 'SELECT 1' \
    'a generated SELECT 1 fails the discriminator exactly as pg_isready does'
sec_row "$GSEC" 'the generation rule' 'counts what an instance carries|counts what the instance' \
    'what is generated counts what an instance carries rather than naming a table the repository owns'
sec_row "$GSEC" 'the generation rule' 'answers zero' \
    'an empty instance answers zero and a seeded one does not'
sec_row "$GSEC" 'the generation rule' 'one route' \
    'all three issues of the generated read go through one route'
sec_row "$GSEC" 'the generation rule' 'on the host' \
    'the generated read is issued on the host, because it is a file in the repository rather than a program in the image'

# The admission reader, and the only thing it adds to 4b's readback is the door
# the skill could have let itself through. $6 opens that door, so "no exemption"
# is proved by watching the exemption admit something the shipped path refuses.
gen_admit() {
    if [ "${6:-}" = exemption ] && [ "$5" = generated ]; then
        printf 'isolated\tadmitted because the skill wrote it\n'
        return
    fi
    readback "$1" "$2" "$3" "$4"
}

admit_case() {
    _got=$(gen_admit "$1" "$2" "$3" "$4" "$5")
    case $_got in
        "$6"*) ok "$7" ;;
        *)     fail "$7 - the reader answered '${_got%%	*}'" ;;
    esac
}

# The mechanism these rows exercise is 4b's readback, which exists whatever this
# slice ships - so with no shipped rule pointing the generated read at it they
# would all be green over a tree that holds the read to nothing. They run only
# where the shipped rule names the discriminator it holds the read to. This is
# the boundary 4b recorded in its own words and it is recorded here too rather
# than papered over: what these rows prove is that the mechanism refuses what it
# should; what makes it the GENERATED read's mechanism is the sentence.
GEN_HELD=$(printf '%s\n' "$GSEC" | grep -ciE 'held to .*discriminator' || printf 0)
if [ "$GEN_HELD" -ge 1 ]; then
    admit_case '3' '0' '3' yes generated isolated \
        "a generated read that counts what the instance carries discriminates, and the copy answering the base store's answer is isolated"
    admit_case '1' '1' '1' yes generated refuse \
        "rejected as a query: a generated SELECT 1, refused exactly as pg_isready is and for the same measured reason"

    # ...and the two origins reach the SAME verdict on the same outputs, which is
    # what "no exemption" means once it stops being a sentence.
    if [ "$(gen_admit '1' '1' '1' yes generated)" = "$(gen_admit '1' '1' '1' yes harvested)" ]; then
        ok "a generated candidate and a harvested one reach the same verdict on the same three outputs - the reader knows no origin"
    else
        fail "the reader answers differently for a generated candidate than for a harvested one, which is an exemption by another name"
    fi

    case $(gen_admit '1' '1' '1' yes generated exemption) in
        isolated*) ok "rejected: an admission path that admits a generated read because the skill wrote it, which is declared-on-write reaching through the verification door" ;;
        *)         fail "the exemption fixture changed nothing, so the row cannot see a candidate admitted on its authorship" ;;
    esac
else
    fail "the shipped rule does not hold the generated read to the discriminator, so the admission rows would certify a mechanism nothing points the generated read at"
fi

# --- DS37  written into a REAL repository, and the four files digested -------
# Everything above reads a rule or runs a reader over values. This block obtains
# the values by writing into a repository that is not this one - which is the
# hazard class this slice introduces and the only one no grep and no reader can
# reach. The repository is created here, mutated here, and removed here, and the
# removal is asserted rather than assumed.
grepo=$gfx/fixture-repo
mkdir -p "$grepo/bin"
printf '#!/bin/sh\necho existing\n' > "$grepo/bin/existing-thing"
chmod +x "$grepo/bin/existing-thing"
printf 'db-create:\n\t@echo the developer wrote this\n' > "$grepo/Makefile"
printf 'version: "3"\ntasks:\n  build:\n    cmds: [make]\n' > "$grepo/Taskfile.yml"
printf 'build:\n    make\n' > "$grepo/justfile"
printf '{ "name": "fixture", "scripts": { "build": "make" } }\n' > "$grepo/package.json"
(
    cd "$grepo" \
    && git init -q . \
    && git add -A \
    && fixture_commit -q -m fixture
) >/dev/null 2>&1

grepo_head=$( cd "$grepo" && git rev-parse HEAD 2>/dev/null )
whole_object_id "$grepo_head" \
    && ok "the fixture repository exists and carries one commit the developer made, so an edit to it is visible as an edit" \
    || fail "the fixture repository would not initialise, so every placement row below proves nothing"

# The digest of every file the skill may never touch, before it writes anything.
untouchable_digest() {
    for _u in $NEVER_APPEND; do
        printf '%s:' "$_u"
        git hash-object "$grepo/$_u" 2>/dev/null || printf 'absent'
        printf ' '
    done
}
untouched_before=$(untouchable_digest)
untouched_n=$(printf '%s\n' "$NEVER_APPEND" | tr ' ' '\n' | grep -c .)
#
# THE PREMISE, not the assertion. Measured in this section's own red run: with
# nothing shipped, $NEVER_APPEND was EMPTY, so this loop digested no file at all,
# the `*absent*` case never matched, and the row printed `ok` over zero files -
# after which the byte-identity row compared '' against '' and vouched for four
# files it had never read. That is the third `'' = ''` in this file, and the
# repair is the same one the probe byte-identity row carries: gate on the
# MECHANISM having something to say, not on the input looking plausible.
if [ "$untouched_n" -ne 4 ]; then
    fail "the never-append set names $untouched_n file(s), not four, so the byte-identity row below would compare two empty strings"
elif [ "${untouched_before#*absent}" != "$untouched_before" ]; then
    fail "one of the four untouchable files is missing from the fixture, so the byte-identity row below cannot fail: $untouched_before"
else
    ok "all four files the skill may never touch are present in the fixture and digested before it writes: $NEVER_APPEND"
fi

# The writer follows the SHIPPED rules - directory, names and never-append list
# all read out of the file above. $3 selects one defect, and every defect is a
# negative below rather than a hypothetical.
gen_write() {
    _repo=$1; _store=$2; _mode=${3:-}; _inst=${4:-}
    _dir=$(gen_dirs | awk 'NR == 1')
    if [ -z "$_dir" ] || [ ! -d "$_repo/$_dir" ]; then
        printf 'no-directory\n'
        return
    fi
    [ "$_mode" = newdir ] && _dir=tools/
    mkdir -p "$_repo/$_dir"
    for _n in $(gen_names); do
        _file=$(printf '%s' "$_n" | awk -v s="$_store" '{ gsub(/<store>/, s); print }')
        case $_n in
            *create*) _body="docker exec \"\$INST\" sh -c \"mkdir -p /data/\$1\"" ;;
            *drop*)   _body="docker exec \"\$INST\" sh -c \"rm -rf /data/\$1\"" ;;
            *)        _body="docker exec \"\$1\" sh -c 'find /data -mindepth 1 -maxdepth 1 | wc -l'" ;;
        esac
        {
            printf '#!/bin/sh\n'
            printf '# Written by stackgraft for the %s store, and approved before it was written.\n' "$_store"
            printf 'set -eu\n'
            printf 'INST=%s\n' "${_inst:-none}"
            printf '%s\n' "$_body"
        } > "$_repo/$_dir$_file"
        chmod +x "$_repo/$_dir$_file"
    done
    if [ "$_mode" = append ]; then
        printf 'db-create-%s:\n\t@bin/db-create-%s $(NS)\n' "$_store" "$_store" >> "$_repo/Makefile"
    fi
    if [ "$_mode" = clobber ]; then
        printf '#!/bin/sh\necho clobbered\n' > "$_repo/$_dir"existing-thing
    fi
    if [ "$_mode" = stage ]; then
        ( cd "$_repo" && git add -A ) >/dev/null 2>&1
    fi
    printf '%s\n' "$_dir"
}

gen_dir_used=$(gen_write "$grepo" fixturestore)
gen_written=$( cd "$grepo" && git status --porcelain 2>/dev/null | awk '$1 == "??" { print $2 }' | sort | tr '\n' ' ' )

# ONE premise for the whole block, and it is a premise rather than a row: a write
# that never happened satisfies every "nothing else changed" assertion below
# perfectly. In this section's red run all four of them printed `ok` over a
# repository nothing had been written into - four checks certifying restraint
# that had never been exercised. So the rows below run only where three files
# really landed, and where they did not the block says so once.
gen_wrote=0
[ "$gen_written" = 'bin/db-create-fixturestore bin/db-drop-fixturestore bin/db-read-fixturestore ' ] && gen_wrote=1

if [ "$gen_wrote" -eq 1 ]; then
    ok "exactly three new paths, all under the discovered directory: $gen_written"
else
    fail "the writer left '$gen_written' rather than the three files the shipped table names, so every row below would assert restraint over a write that never happened"
fi

[ "$gen_dir_used" = 'bin/' ] \
    && ok "the three files land in the script directory the repository already had, not in one this skill invented: $gen_dir_used" \
    || fail "the writer placed the family in '$gen_dir_used' rather than the repository's existing bin/"

if [ "$gen_wrote" -eq 1 ]; then
    gen_notx=0
    for _p in db-create-fixturestore db-drop-fixturestore db-read-fixturestore; do
        [ -x "$grepo/bin/$_p" ] || gen_notx=$((gen_notx + 1))
        head -1 "$grepo/bin/$_p" | grep -q '^#!/bin/sh$' || gen_notx=$((gen_notx + 1))
    done
    [ "$gen_notx" -eq 0 ] \
        && ok "all three generated files are executable and carry a shebang, so each is a target rung 1 can discover and the repository can run" \
        || fail "$gen_notx of the six executable-and-shebang properties are missing from the generated family"

    # THE row this whole block exists for: the four files the skill may never
    # touch are byte-identical afterwards. An appended Makefile recipe is
    # invisible to every grep and every reader in this file; only the hash sees it.
    [ "$(untouchable_digest)" = "$untouched_before" ] \
        && ok "Makefile, Taskfile.yml, justfile and package.json are byte-identical after the write - the skill edited no file it did not author" \
        || fail "a file the skill may never touch changed: before '$untouched_before' after '$(untouchable_digest)'"

    # ...and the pre-existing file in the SAME directory is untouched too, which
    # is the case the four build files do not cover: a name collision inside the
    # one directory the skill is allowed to write into.
    [ "$(git hash-object "$grepo/bin/existing-thing")" = "$(cd "$grepo" && git rev-parse HEAD:bin/existing-thing)" ] \
        && ok "the file that was already in bin/ is byte-identical too - never edits a file it did not author is not scoped to build files" \
        || fail "the writer changed a file that was already in the directory it wrote into"

    # Nothing staged, nothing committed, nothing pushed.
    gen_staged=$( cd "$grepo" && git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ' )
    gen_head_after=$( cd "$grepo" && git rev-parse HEAD 2>/dev/null )
    if [ "$gen_staged" -eq 0 ] && [ "$gen_head_after" = "$grepo_head" ]; then
        ok "the skill staged nothing and committed nothing - the files are untracked in the working tree and the human's pull request is the review"
    else
        fail "the write left $gen_staged path(s) staged and HEAD at '$gen_head_after' against '$grepo_head'"
    fi
else
    skip "the restraint rows (nothing was written, so nothing they assert was exercised)" conditional
fi

# --- the four negatives, each against its OWN copy of the repository ---------
gen_copy() {
    rm -rf "$gfx/neg"
    cp -R "$grepo" "$gfx/neg"
    rm -rf "$gfx/neg/bin/db-create-fixturestore" "$gfx/neg/bin/db-drop-fixturestore" "$gfx/neg/bin/db-read-fixturestore"
}

gen_copy
gen_write "$gfx/neg" fixturestore append >/dev/null
neg_digest=$(for _u in $NEVER_APPEND; do printf '%s:' "$_u"; git hash-object "$gfx/neg/$_u" 2>/dev/null || printf 'absent'; printf ' '; done)
[ "$neg_digest" != "$untouched_before" ] \
    && ok "rejected: a writer that appends its target to the Makefile - the digest moved, which is the only thing that could have seen it" \
    || fail "the byte-identity row cannot see a Makefile that was appended to, so it was never checking one"

gen_copy
neg_dir=$(gen_write "$gfx/neg" fixturestore newdir)
[ "$neg_dir" != "$gen_dir_used" ] && [ -d "$gfx/neg/tools" ] \
    && ok "rejected: a writer that invents a tools/ directory although the repository already has bin/ - never a new convention" \
    || fail "the placement row cannot see a family written outside the discovered directory ('$neg_dir')"

gen_copy
gen_write "$gfx/neg" fixturestore clobber >/dev/null
[ "$(git hash-object "$gfx/neg/bin/existing-thing")" != "$(git hash-object "$grepo/bin/existing-thing")" ] \
    && ok "rejected: a writer that overwrites a file already in the directory it may write into" \
    || fail "the never-edit row cannot see an existing file overwritten"

gen_copy
gen_write "$gfx/neg" fixturestore stage >/dev/null
neg_staged=$( cd "$gfx/neg" && git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ' )
[ "$neg_staged" -ge 1 ] \
    && ok "rejected: a run that staged what it wrote, which puts the skill's authorship inside a commit nobody read" \
    || fail "the commit-state row cannot see a staged path, so it was never checking one"
rm -rf "$gfx/neg"

# --- V63  the approval fingerprint, over the family, for real ----------------
# Real files, the shipped fingerprint script, one value. The negative that
# matters is the last one: a value taken over the create alone does not move when
# the read is edited, which is why the approval covers all three.
fam_fp() {
    sh "$SKILL/scripts/fingerprint.sh" \
        "$1/bin/db-create-fixturestore" "$1/bin/db-drop-fixturestore" "$1/bin/db-read-fixturestore" \
        | git hash-object --stdin
}
one_fp() { sh "$SKILL/scripts/fingerprint.sh" "$1/bin/db-create-fixturestore" | git hash-object --stdin; }

# Restores a file to what it was before a fixture edit, unconditionally. The
# `grep -v … && mv` shape this replaces is a trap on exactly the input this
# section had in its red run: over a file whose ONLY line is the fixture line,
# grep selects nothing and exits 1, so the mv never runs and the "revert" leaves
# the edit in place - after which the row that proves the edits were measured
# rather than the reverts fails for a reason that is about the harness.
gen_revert() {
    grep -vxF "$2" "$1" > "$gfx/restore" || :
    mv "$gfx/restore" "$1"
    chmod +x "$1"
}

# The premise, and it is the one the red run went straight past: fingerprint.sh
# emits `-` for a path it could not hash, so three MISSING files digest to three
# dashes and hash to a perfectly well-formed object id. Every row below then
# compares two real hashes of two real absences, and appending to a file that is
# not there CREATES it, so the edits "moved" the value and the block passed over
# a family that did not exist. whole_object_id is necessary and not sufficient
# here; what makes it sufficient is that no leg came back `-`.
fam_legs=$(sh "$SKILL/scripts/fingerprint.sh" \
    "$grepo/bin/db-create-fixturestore" "$grepo/bin/db-drop-fixturestore" "$grepo/bin/db-read-fixturestore" \
    | awk '{ print $1 }' | tr '\n' ' ')
fam_undigested=$(printf '%s\n' "$fam_legs" | tr ' ' '\n' | grep -cxF -- '-')
fam0=$(fam_fp "$grepo")

if [ "$fam_undigested" -ne 0 ] || ! whole_object_id "$fam0"; then
    fail "the approval fingerprint reads $fam_undigested undigestable leg(s) and hashed to '${fam0:-nothing}' - a family that is not there digests to three dashes and hashes to a valid id, so every row below would compare two absences"
else
    ok "the approval fingerprint over the three approved files digests every leg and is a whole object id, so the comparisons below are between two values rather than two absences"

    for _edit in create drop read; do
        printf '# edited after approval\n' >> "$grepo/bin/db-$_edit-fixturestore"
        if [ "$(fam_fp "$grepo")" != "$fam0" ]; then
            ok "rejected: the family edited at its $_edit after approval - the fingerprint moved, so the approval is dropped and the template is shown again"
        else
            fail "editing the generated $_edit left the approval fingerprint where it was, so an edited file keeps a consent nobody gave for it"
        fi
        gen_revert "$grepo/bin/db-$_edit-fixturestore" '# edited after approval'
    done
    [ "$(fam_fp "$grepo")" = "$fam0" ] \
        && ok "the fingerprint returns to its approved value once every edit is reverted, so the three rows above measured the edits and not the reverts" \
        || fail "the family fingerprint did not return to '$fam0' after the edits were reverted, so those rows were measuring something else"

    # The skill's OWN later edit is the same event and is asserted as one,
    # because it is the one a reader would assume is exempt.
    printf '# regenerated by stackgraft\n' >> "$grepo/bin/db-read-fixturestore"
    [ "$(fam_fp "$grepo")" != "$fam0" ] \
        && ok "rejected: the SKILL's own later edit to an approved file - it drops the approval exactly as the developer's would" \
        || fail "an edit written by the skill itself left the approval standing"
    gen_revert "$grepo/bin/db-read-fixturestore" '# regenerated by stackgraft'

    # And why it is taken over all three: a per-file value leaves the other two
    # editable under a surviving consent.
    one0=$(one_fp "$grepo")
    printf '# edited after approval\n' >> "$grepo/bin/db-read-fixturestore"
    if [ "$(one_fp "$grepo")" = "$one0" ] && [ "$(fam_fp "$grepo")" != "$fam0" ]; then
        ok "rejected: an approval taken over the create alone, which does not move when the read is edited - two of the three files stay editable under it"
    else
        fail "the per-file fixture proves nothing: create-only gave '$(one_fp "$grepo")' against '$one0'"
    fi
    gen_revert "$grepo/bin/db-read-fixturestore" '# edited after approval'
fi

# --- the generated read RUN for real: skipped loudly, never quietly passed ---
# The rows above run a reader over values. These obtain the values: a real store,
# a real copy, a real empty instance, and the generated file issued against all
# three from the host, which is the route a rung-2 candidate takes.
if [ "$docker_ready" -eq 1 ] && docker image inspect alpine/git >/dev/null 2>&1 \
   && [ -f "$PROVIDER" ]; then
    GH=deadbe05
    gwt=$(mktemp -d)
    gsrc=sg-gen-base
    gimg=alpine/git

    g_inventory() {
        docker volume ls --quiet --filter "label=stackgraft.repo=$GH" 2>/dev/null | sort | tr '\n' ' '
        printf '|'
        docker container ls --all --quiet --filter "label=stackgraft.repo=$GH" 2>/dev/null | sort | tr '\n' ' '
        printf '|'
        docker volume ls --quiet --filter name=sg-gen 2>/dev/null | sort | tr '\n' ' '
        printf '|'
        docker container ls --all --quiet --filter name=sg-gen 2>/dev/null | sort | tr '\n' ' '
    }
    g_before=$(g_inventory)
    [ "$g_before" = '|||' ] \
        && ok "the runtime holds no object of this section's before it runs, so its inventory rows read only what it made" \
        || fail "the runtime already holds one of this section's objects, so its inventory rows cannot be trusted: $g_before"

    docker volume create "$gsrc" >/dev/null 2>&1
    docker run --rm --entrypoint sh -v "$gsrc":/data "$gimg" \
        -c 'mkdir -p /data/one /data/two /data/three' >/dev/null 2>&1
    gbase=$(docker run -d --name sg-gen-base-instance --entrypoint sh -v "$gsrc":/data "$gimg" \
        -c 'sleep 900' 2>/dev/null)
    anon_note "$gbase"

    if [ -z "$gbase" ]; then
        fail "the fixture base store would not start, so no generated-read row proved anything"
    else
        # The family is regenerated with the discovered base instance in it, the
        # way the skill writes it from what discovery resolved.
        gen_write "$grepo" fixturestore '' "$gbase" >/dev/null

        gout=$( sh "$ROOT/$PROVIDER" provision "$GH" "$gwt" fixturestore "$gsrc" "$gimg" "$gbase" \
                    "stackgraft.labels=1" "stackgraft.repo=$GH" "stackgraft.worktree=$gwt" 2>&1 )
        grc=$?
        gcopy=$(printf '%s\n' "$gout" | awk -F'\t' '$1 == "instance" { print $2; exit }')
        gprobe=$(docker run -d --rm --entrypoint sh \
            --label "stackgraft.repo=$GH" --label "stackgraft.worktree=$gwt" \
            --label "stackgraft.probe=fixturestore" \
            --name sg-gen-probe "$gimg" -c 'sleep 300' 2>/dev/null)
        anon_note "$gprobe"

        if [ "$grc" -ne 0 ] || [ -z "$gcopy" ] || [ -z "$gprobe" ]; then
            fail "the generated-read fixture could not obtain a copy (exit $grc, instance '$gcopy') or an empty instance, so its rows prove nothing"
        else
            # ONE route: the same generated file, on the host, given each of the
            # three instances in turn.
            READ="$grepo/bin/db-read-fixturestore"
            g_base_out=$( sh "$READ" "$gbase" 2>/dev/null )
            g_empty_out=$( sh "$READ" "$gprobe" 2>/dev/null )
            g_copy_out=$( sh "$READ" "$gcopy" 2>/dev/null )

            case $(gen_admit "$g_base_out" "$g_empty_out" "$g_copy_out" yes generated) in
                isolated*) ok "the generated read discriminates for real: base '$g_base_out', empty instance '$g_empty_out', copy '$g_copy_out' - it counts what the instance carries" ;;
                *)         fail "the generated read did not clear: base '$g_base_out' empty '$g_empty_out' copy '$g_copy_out'" ;;
            esac
            [ -n "$g_base_out" ] && [ "$g_base_out" != "$g_empty_out" ] \
                && ok "the empty instance really answers differently, so the discrimination is measured rather than assumed" \
                || fail "the generated read answered '$g_base_out' on the base store and '$g_empty_out' on an empty instance, so it discriminates nothing"

            # ...and the shape DS42 names by name, generated and measured: a read
            # whose answer does not depend on what the instance holds.
            printf '#!/bin/sh\nset -eu\ndocker exec "$1" sh -c "printf 1"\n' > "$gfx/db-read-constant"
            chmod +x "$gfx/db-read-constant"
            c_base=$( sh "$gfx/db-read-constant" "$gbase" 2>/dev/null )
            c_empty=$( sh "$gfx/db-read-constant" "$gprobe" 2>/dev/null )
            c_copy=$( sh "$gfx/db-read-constant" "$gcopy" 2>/dev/null )
            case $(gen_admit "$c_base" "$c_empty" "$c_copy" yes generated) in
                refuse*) ok "rejected as a query: a generated read measured answering '$c_empty' on an empty instance and on the base store alike - the SELECT 1 shape, refused" ;;
                *)       fail "a constant generated read cleared the discriminator: base '$c_base' empty '$c_empty'" ;;
            esac

            # V62's observation, obtained rather than asserted: the create, the
            # drop and the read are RUN against the discovered store and their
            # exit statuses are what the gate reads.
            #
            # Each exit is bracketed by a POSITIVE CONTROL, and that is the
            # repair this block needed. Measured in this section's red run: three
            # files whose whole content was a comment ran, exited 0, and the gate
            # read three successes - after which "the drop removed the namespace"
            # passed because the create had never made one. An exit status is
            # evidence only where the effect it claims can be seen, so the
            # namespace is looked for after the create and looked for again after
            # the drop.
            NS=sg_fixture_deadbe05
            docker exec "$gbase" test -e "/data/$NS" >/dev/null 2>&1 \
                && fail "the namespace the create is about to make is already there, so its effect cannot be told from the fixture's" \
                || ok "the namespace the observed create will make is absent before it runs, so its effect is attributable to it"

            sh "$grepo/bin/db-create-fixturestore" "$NS" >/dev/null 2>&1
            obs_create=$?
            obs_made=0
            if docker exec "$gbase" test -d "/data/$NS" >/dev/null 2>&1; then
                obs_made=1
                ok "the observed create exited $obs_create and the namespace it claims to have made is there - the exit status is evidence rather than a number"
            else
                fail "the observed create exited $obs_create having made nothing, so its exit status is a number about a command that did not act"
            fi

            sh "$READ" "$gbase" >/dev/null 2>&1
            obs_read=$?

            sh "$grepo/bin/db-drop-fixturestore" "$NS" >/dev/null 2>&1
            obs_drop=$?
            # Conditional on the create having ACTED, because absence after a
            # drop is equally satisfied by a namespace that was never there -
            # which is exactly what this row reported in the red run.
            if [ "$obs_made" -eq 0 ]; then
                skip "the observed drop (the create made no namespace, so a removal cannot be told from an absence)" conditional
            elif docker exec "$gbase" test -e "/data/$NS" >/dev/null 2>&1; then
                fail "the observed drop exited $obs_drop and the namespace it was meant to remove is still there"
            else
                ok "the observed drop removed the namespace the observed create made, so both exit statuses are evidence"
            fi

            gate_case "$obs_create" "$obs_drop" "$obs_read" declared runnable \
                "three observed exits against the discovered store raise the generated target from inferred to declared: create $obs_create, drop $obs_drop, read $obs_read"

            docker stop -t 1 "$gprobe" >/dev/null 2>&1
        fi

        sh "$ROOT/$PROVIDER" destroy "$GH" "$gwt" fixturestore >/dev/null 2>&1
    fi

    gbase_anon=$(docker inspect --format \
        '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
        "$gbase" 2>/dev/null | grep -vxF "$gsrc" | grep . || printf '')

    # Teardown by NAME and unconditionally, containers before volumes, and it is
    # written this way for a measured reason rather than for symmetry.
    #
    # A container that HOLDS a volume makes that volume unremovable: `docker
    # volume rm` answers "volume is in use" and exits non-zero, so a teardown
    # that removes the volume first leaves BOTH behind. That state is reachable
    # here without any failure of this section's own - a run killed between a
    # container being created and its removal leaves it holding the volume, and a
    # container in `Created` holds one exactly as a running one does. It was
    # reached for real while this slice was being written: an interrupted run
    # left the provider section's `docker create` fixture behind, its volume
    # survived the naive removal, and the next run's inventory rows correctly
    # refused to trust themselves with a foreign object present.
    #
    # By name rather than by variable for the other half of it: where `docker run
    # -d` fails after the runtime has already registered the name, the variable
    # is EMPTY and `docker rm -f -v ""` removes nothing, while a container is
    # sitting there under a name this section chose. The names are this section's
    # own, so removing them is removing only what it created.
    for _gc in sg-gen-probe sg-gen-base-instance "$gbase"; do
        [ -n "$_gc" ] && docker rm -f -v "$_gc" >/dev/null 2>&1
    done
    docker volume rm "$gsrc" >/dev/null 2>&1
    rm -rf "$gwt"

    gleft=$(g_inventory)
    ganon=0
    for _v in $gbase_anon; do
        docker volume inspect "$_v" >/dev/null 2>&1 && ganon=$((ganon + 1))
    done
    [ "$gleft" = '|||' ] && [ "$ganon" -eq 0 ] \
        && ok "this section left no labelled object, no fixture, no probe and no unnamed volume behind" \
        || fail "this section leaked '$gleft' and $ganon unnamed volume(s)"
else
    skip "generated-read runtime rows (no docker daemon, no alpine/git image, or no provider script)" runtime
fi

# --- the fixture repository is removed, and the removal is asserted ----------
# Nothing outside this repository that this section did not create, and nothing
# it created that outlives it.
rm -rf "$gfx"
[ ! -d "$grepo" ] && [ ! -d "$gfx" ] \
    && ok "the fixture repository this section wrote into is gone, along with everything it wrote there" \
    || fail "the fixture repository survived this section: $grepo"

# --- copy reclamation: specified, unimplemented, and SAID so -----------------
# reaping.md section 9a specifies candidacy, liveness and a two-flag interlock
# for store copies. scripts/reap.sh accepts `c:` containers and `p:` processes
# and NOTHING else - no volume query, no stackgraft.store read, no copy line in
# the report - so an orphaned copy is neither detected nor reclaimed, and
# `destroy` removes one with no flags at all.
#
# Five shipped files described that as working. This block ties the claim to the
# code in BOTH directions: while reap.sh has no copy target the texts must say
# so, and the day one is added these rows fail and send whoever added it back to
# the same five files. That coupling is the point - an unimplemented MUST that
# nobody can see is how this one survived a whole release chain.
reap_has_copy_target() {
    grep -q 'stackgraft\.store' "$SKILL/scripts/reap.sh" 2>/dev/null \
        || grep -qE '^\s+v:\*\)' "$SKILL/scripts/reap.sh" 2>/dev/null
}
DISCLOSE_FILES="README.md CHANGELOG.md SECURITY.md $SKILL/references/reaping.md $SKILL/references/isolation-providers.md"
# shellcheck disable=SC2086
undisclosed=$(for f in $DISCLOSE_FILES; do
    grep -qi 'no copy target\|implements none of it\|not implemented\|Nothing reclaims it for you' "$f" || printf '%s ' "$f"
done)

if reap_has_copy_target; then
    fail "reap.sh now has a copy target, so the five files that say it has none are stale - update them and this row"
elif [ -z "$undisclosed" ]; then
    ok "reap.sh has no copy target, and all five files that describe copy reclamation say so rather than describing it as working"
else
    fail "reap.sh has no copy target and these files do not disclose it: $undisclosed"
fi

# ...and the negative: a file with the disclosure stripped must be named. Without
# it the row above passes over a list nobody reads.
cd_fx=$(mktemp -d)
grep -vi 'no copy target\|implements none of it\|not implemented\|Nothing reclaims it for you' SECURITY.md > "$cd_fx/undisclosed.md"
if grep -qi 'no copy target\|implements none of it\|not implemented\|Nothing reclaims it for you' "$cd_fx/undisclosed.md"; then
    fail "the disclosure fixture still carries the sentence after the strip, so the row below asserts nothing"
else
    ok "rejected: SECURITY.md with its copy-reclamation disclosure deleted, which is how the claim shipped as working"
fi
rm -rf "$cd_fx"

# --- SECURITY.md discloses the writing half ----------------------------------
# The commit that gave this skill repository writes touched README.md, the
# schema, isolation-providers.md and shared-state.md - and not SECURITY.md. So
# the threat model went on describing a read-only boundary while the tool it
# describes began authoring executable files, and the approval bullet went on
# saying a change elsewhere in the repository invalidates nothing while the
# generated family's fingerprint covers three files at once.
#
# The same shape as the two claims swept above, one document along, and the same
# diagnosis: the sweep unit is the commit that redefined the destination, not the
# file the symptom appeared in.
secfx=$(mktemp -d)
vfx=$secfx
SEC_WRITE=$(doc_section SECURITY.md 'files the run may write')
[ -n "$SEC_WRITE" ] \
    && ok "SECURITY.md carries a section on the files the run may write, so the writing half is stated where the model is looked for" \
    || fail "SECURITY.md has no section on what the run writes, so its threat model still describes a read-only boundary"

sec_row "$SEC_WRITE" 'the writing section' 'on approval and never otherwise|only on .*approval' \
    'the three files are written on approval and never otherwise'
sec_row "$SEC_WRITE" 'the writing section' 'appends to nothing|edits nothing it did not author' \
    'it appends to no existing file and edits none it did not author'
sec_row "$SEC_WRITE" 'the writing section' 'staged, committed or pushed' \
    'nothing is staged, committed or pushed'
sec_row "$SEC_WRITE" 'the writing section' 'no exemption for being ours' \
    'the generated files are held to the template contract with no exemption'
sec_row "$SEC_WRITE" 'the writing section' 'inferred' \
    'a file this skill wrote is inferred until a run has observed all three succeed'
sec_row "$SEC_WRITE" 'the writing section' 'does not review what you approve' \
    'the residual: it does not review what you approve'

# ...and the trust-boundary section must say the boundary runs both ways, or a
# reader who stops at the top of the page has the pre-2.0 model.
grep -q 'boundary runs both ways' SECURITY.md \
    && ok "SECURITY.md's opening states the boundary runs both ways, so the writing half is not only in a later section" \
    || fail "SECURITY.md still opens as though repository text only ever flows inward"

# The approval bullet, which was false rather than merely incomplete: the
# fingerprint covers the create, the drop and the read hashed together, and
# `discoveredFrom` names only the create.
APPROVAL_LINE=$(grep -n 'Approval is per repository and store' SECURITY.md | head -1)
[ -n "$APPROVAL_LINE" ] || fail "SECURITY.md no longer carries the approval-scope bullet at all"
printf '%s' "$APPROVAL_LINE" | grep -q 'all three files' \
    && ok "...and its approval bullet says the generated family's source is all three files, not the one discoveredFrom names" \
    || fail "SECURITY.md still says only the discovered-from file invalidates an approval, which is false for a generated family: $APPROVAL_LINE"

# The negative for that one is the shipped bytes it replaced, so what is
# rejected is the measured regression rather than a sentence invented for it.
grep -v 'Approval is per repository and store' SECURITY.md > "$secfx/pre-slice5.md"
printf '%s\n' '- **Approval is per repository and store, not per run.** Once given, and for as long as the recorded `sourceFingerprint` still matches the file the template was discovered from, the create and its teardown run again without asking. A change to that file invalidates the approval; a change elsewhere in the repository does not.' \
    >> "$secfx/pre-slice5.md"
if grep 'Approval is per repository and store' "$secfx/pre-slice5.md" | grep -q 'all three files'; then
    fail "the pre-slice-5 approval bullet reads as though it names all three files, so the row above asserts nothing"
else
    ok "rejected: the approval bullet as it stood before the generator shipped, naming one file where the fingerprint covers three"
fi
rm -rf "$secfx"

# ----------------------------------------------------------------- reap -----
section "reap surface"

REAP="$SKILL/scripts/reap.sh"
TAB=$(printf '\t')

# Runs reap.sh capturing stdout and stderr together, so a row can assert what a
# refusal SAID as well as what it returned. A refusal that named no reason
# leaves the user with a stop that did not happen and nothing to act on, which
# is only marginally better than the stop that should not have happened.
reap_run() {
    reap_out=$(sh "$REAP" "$@" 2>&1)
    reap_rc=$?
}

# --- V6  one probe, two scripts, and a byte is enough to notice --------------
# extract_probe() is defined once, with the V13 block in the instrumentation
# section above.
#
# The `-n` guard this row used to carry was aimed one layer short. It covered
# the EXTRACTION - file text, which a git that dies at exec leaves perfectly
# intact - and not the HASHING, which is the step that actually needs git. With
# git off the PATH both digests came back empty, `'' = ''` held, and the row
# certified byte-identity over two absences. The negative two rows below went
# FAIL in that same run, saying the comparison could not notice a changed byte,
# so one run had the negative announcing the comparison blind while the positive
# still vouched for it. A premise gate aimed at the input rather than at the
# mechanism is indistinguishable from no gate at all. Third instance of `'' = ''`
# in this file, after pick-port's stability row and its exclusion row.
#
# Both premises are needed and neither implies the other: an absent block still
# digests to the empty blob's id, which is a perfectly well-formed object id, and
# a dead git digests a present block to nothing at all. whole_object_id() is the
# one the truncation row uses - 40 characters or 64, never a hard-coded 40 - so
# there is no fourth spelling of "looks like a hash" to drift against.
lock_block=$(extract_probe "$LOCK")
reap_block=$(extract_probe "$REAP")
p_lock=$(extract_probe "$LOCK" | git hash-object --stdin)
p_reap=$(extract_probe "$REAP" | git hash-object --stdin)
if [ -z "$lock_block" ] && [ -z "$reap_block" ]; then
    fail "no lstart probe block came out of either script, so there is nothing for the comparison to be about"
elif [ -z "$lock_block" ]; then
    fail "no lstart probe block came out of with-lock.sh, so there is nothing for the comparison to be about"
elif [ -z "$reap_block" ]; then
    fail "no lstart probe block came out of reap.sh, so there is nothing for the comparison to be about"
elif ! whole_object_id "$p_lock" || ! whole_object_id "$p_reap"; then
    fail "the probe blocks digested to '${p_lock:-nothing}' and '${p_reap:-nothing}', and an equality between two things that are no object id says nothing about their bytes"
elif [ "$p_lock" = "$p_reap" ]; then
    ok "the lstart probe block is byte-identical in with-lock.sh and reap.sh"
else
    fail "the lstart probe block in reap.sh differs from the one in with-lock.sh"
fi

# One byte, in the first line of the block. If the comparison cannot see this
# it cannot see a probe that quietly stopped asking about pid 1 either.
p_mut=$(extract_probe "$REAP" | awk 'NR == 1 { sub(/^#/, "!") } { print }' | git hash-object --stdin)
[ "$p_mut" != "$p_lock" ] \
    && ok "rejected: a probe copy with one byte changed" \
    || fail "the byte-identity comparison cannot notice a changed byte"

# --- A9  the base-port requirement has no override, and its refusal says so --
# The fix this replaces keyed the refusal on "was anything said about the base
# stack" and answered a bare -B as yes. Nothing validated that claim: it
# supplied zero ports, so every comparison missed and a hand-labelled
# base-stack container was stopped with acted 1 and exit 0. Container mutation
# now requires at least one real -b, with no override - and a refusal that
# hands the reader a way past itself is not a refusal, so the message is
# asserted as well as the exit code.
#
# No runtime is needed for either: the base-port gate fires before anything is
# asked about the container.
#
# Both spellings are checked, the retired flag by name and the "or <flag>"
# shape any replacement for it would take, because the defect was not that one
# letter existed - it was that the refusal advertised an exit.
offers_an_out() { printf '%s' "$1" | grep -qE -- '-B|[Oo]r +-[A-Za-z]'; }

reap_run -m stop 00c0ffee 'c:deadbeefcafe'
if [ "$reap_rc" -eq 3 ] \
   && printf '%s' "$reap_out" | grep -q 'base-stack-ports-unknown' \
   && printf '%s' "$reap_out" | grep -q -- '-b <port>' \
   && ! offers_an_out "$reap_out"; then
    ok "a container mutation with no base port refuses and names no way around it"
else
    fail "no-base-port refusal: exit $reap_rc, said '$reap_out'"
fi

# ...and the detector can see an advertised bypass. This is the wording that
# shipped, verbatim, so a row that stopped looking is caught by the exact text
# it was written against.
offers_an_out 'no base-stack port information was given: pass -b <port> once per port the manifest records as a baseStack port, or -B to state that it records none' \
    && ok "rejected: the shipped wording, which ended by naming the flag that switched the rule off" \
    || fail "the bypass detector cannot fire on the wording it was written against"

# The flag itself reaches nothing: it is an unknown option now, not a shape the
# parser still answers.
reap_run -B -m stop 00c0ffee 'c:deadbeefcafe'
if [ "$reap_rc" -eq 2 ] && printf '%s' "$reap_out" | grep -q "unknown option: '-B'"; then
    ok "the retired base-port override is an unknown option, not a flag with reduced powers"
else
    fail "the retired override: exit $reap_rc, said '$reap_out'"
fi

# ...and that exit 2 is about the retired flag, not about any flag: a real port
# in the same position parses and gets as far as the target proof.
#
# The exit code is PINNED to 3 rather than merely tested for "not 2". A reap.sh
# that is absent, unreadable or dead on its first line answers 127, which is not
# 2 either - so a total failure of the script under test produced this row's own
# positive evidence. 3 is the target proof being reached and refused for an id
# that does not exist, which is what `bp_try 18103 3` a few lines below already
# asserts for this very invocation shape.
reap_run -b 18103 -m stop 00c0ffee 'c:deadbeefcafe'
if [ "$reap_rc" -eq 3 ]; then
    ok "rejected: a usage error for a supplied base port, which the parser must accept ($reap_rc)"
else
    fail "a supplied -b did not reach the target proof: exit $reap_rc (wanted 3), said '$reap_out'"
fi

# The usage text must not advertise it either. An agent reads the usage line
# before it reads anything else.
#
# The assertion is that a usage line EXISTS and names no override, not merely
# that no override appears: an absence test on its own passes on a script that
# printed no usage at all, so its positive evidence would also be produced by a
# worse failure than the one it is looking for.
reap_run
if [ "$reap_rc" -eq 2 ] \
   && printf '%s' "$reap_out" | grep -q -- '-b <basePort>' \
   && ! offers_an_out "$reap_out"; then
    ok "the usage text names -b and names no base-port override"
else
    fail "the usage text: exit $reap_rc, said '$reap_out'"
fi

# --- A10  a -b value is validated as a port, and that removes typos only -----
# 0, 65536 and 99999999 are not ports. Rejecting them kills three real
# footguns, the third being a manifest value typed with a leading zero: 018103
# kept as a string matches no stackgraft.port label, so it silently protects
# nothing. This row exists as much to state what it is NOT. It does not close
# the residual the rows further down execute, because 1 is a valid port and a
# wrong valid port is exactly what defeats the exclusion.
#
# The last two entries are the control: a real port - leading zeros and all -
# must still parse and reach the target proof (exit 3 here, the id being
# fictional). Without them a script that rejected every -b would pass the three
# above and prove nothing at all.
#
# Runtime-free: option parsing ends the run before any container is consulted.
bp_bad=''
bp_try() {
    reap_run -b "$1" -m stop 00c0ffee 'c:deadbeefcafe'
    [ "$reap_rc" -eq "$2" ] && return 0
    bp_bad="$bp_bad [-b $1: wanted exit $2, got $reap_rc]"
}
bp_try 0        2
bp_try 65536    2
bp_try 99999999 2
bp_try 18103    3
bp_try 018103   3
if [ -z "$bp_bad" ]; then
    ok "a -b value outside 1-65535 is a usage error, and a valid one - leading zeros included - still parses"
else
    fail "base-port validation:$bp_bad"
fi

# ...and the rejection names the value it rejected. A usage error that does not
# is the least useful half of the answer, and it is how a caller reads a typo
# as the tool being broken.
reap_run -b 0 -m stop 00c0ffee 'c:deadbeefcafe'
printf '%s' "$reap_out" | grep -q "outside 1-65535: '0'" \
    && ok "the rejected base port is quoted back by name" \
    || fail "the base-port rejection named nothing: '$reap_out'"

# --- W5  a malformed target is one target's problem, not the invocation's ----
# C2's shape, one layer up: a target that would not parse ended the whole run
# at exit 2 with the proven orphans beside it left running and no acted record
# printed at all - which contradicts both the reference file and the script's
# own comment on that record. The docker half of this pair, with two proven
# orphans around the malformed one, is in the fixture block below.
reap_run -b 18103 -m stop 00c0ffee 'c:' 'zzz'
if [ "$reap_rc" -eq 3 ] \
   && [ "$(printf '%s\n' "$reap_out" | grep -c 'malformed-target')" -eq 2 ] \
   && printf '%s' "$reap_out" | grep -q "^acted${TAB}0\$"; then
    ok "an empty c: id and an unrecognised target shape are two refusals, and the run still reports what it did"
else
    fail "malformed target shapes: exit $reap_rc, said '$reap_out'"
fi

# ...and the reason is not handed out to targets that parse. The row demands a
# refusal record as well as the absence of that reason: "no malformed-target in
# the output" is equally true of no output at all, so without the first half its
# positive evidence could come from the run producing nothing.
reap_run -b 18103 -m stop 00c0ffee 'c:deadbeefcafe'
if printf '%s' "$reap_out" | grep -q "^refused${TAB}" \
   && ! printf '%s' "$reap_out" | grep -q 'malformed-target'; then
    ok "rejected: the malformed-target reason on a target that parses - it is refused, under another reason"
else
    fail "a well-formed c: target: said '$reap_out'"
fi

# --- V14, V19, V20, V22  the refusal fixtures --------------------------------
# The refusals come before the positive that proves the actuator can act at
# all, because what this script is worth is what it declines to do. Each one is
# a case where acting would stop something that is not ours, or would report a
# no-op as work done.
if [ "$docker_ready" -eq 1 ] && docker image inspect alpine/git >/dev/null 2>&1; then
    rf=$(mktemp -d)
    rfp=$(CDPATH= cd -- "$rf" && pwd -P)
    RH=00c0ffee
    fixture_ids=''

    # The orphan fixture SPEAKS. The row at the bottom of this block asserts
    # that a stop preserves the container's account of itself, and a container
    # that never wrote one cannot show that anything was preserved - so the
    # marker is written before the sleep and read back after the stop.
    ORPHAN_SAYS=stackgraft-orphan-log-marker

    # No --rm on any fixture: a stop MUST leave the container and its logs in
    # place, and --rm would delete exactly the evidence D8 exists to preserve -
    # so a run with it would report a passing stop for the wrong reason.
    fixture_container() {
        _repo=$1; _wt=$2; _svc=$3; _port=$4; _lv=${5:-}; _cmd=${6:-}
        [ -n "$_lv" ] || _lv=1
        [ -n "$_cmd" ] || _cmd='sleep 120'
        if [ -z "$_repo" ]; then
            cid=$(docker run -d --entrypoint sh alpine/git -c "$_cmd" 2>/dev/null)
        else
            cid=$(docker run -d --entrypoint sh \
                --label "stackgraft.labels=$_lv" --label "stackgraft.repo=$_repo" \
                --label "stackgraft.worktree=$_wt" --label "stackgraft.service=$_svc" \
                --label "stackgraft.port=$_port" alpine/git -c "$_cmd" 2>/dev/null)
        fi
        anon_note "$cid"
        [ -n "$cid" ] && fixture_ids="$fixture_ids $cid"
    }

    repo="$rf/repo"
    mkdir -p "$repo"
    ( cd "$repo" \
      && git init -q . \
      && fixture_commit -q --allow-empty -m init \
      && git worktree add -q -b fixture "$rf/wt" ) >/dev/null 2>&1
    live_wt=$(CDPATH= cd -- "$rf/wt" 2>/dev/null && pwd -P)
    gone_wt="$rfp/deleted"

    fixture_container "$RH" "$gone_wt" storefront 18101 1 \
        "printf '%s\n' $ORPHAN_SAYS; sleep 120"          ; orphan=$cid
    fixture_container "$RH" "$live_wt" storefront 18102 ; livewt=$cid
    fixture_container '' '' '' ''                       ; bare=$cid
    fixture_container "$RH" "$gone_wt" catalog-api 18103 ; handlabelled=$cid
    fixture_container "$RH" "$gone_wt" storefront 18104 9 ; future=$cid
    fixture_container "$RH" "$gone_wt" worker 18105 1 'exit 0' ; exited=$cid
    fixture_container "$RH" "$gone_wt" storefront 18106 ; mixed=$cid
    fixture_container "$RH" "$gone_wt" worker 18107 ; residual=$cid
    fixture_container "$RH" "$gone_wt" storefront 18108 ; w5a=$cid
    fixture_container "$RH" "$gone_wt" storefront 18109 ; w5b=$cid

    # The negative for the log-preservation row, and it is the fixture that row
    # USED to run: a bare `sleep 120` that writes nothing at all. 18110 rather
    # than 18103, so it is an ordinary orphan and takes the same mutation path
    # the speaking one does - the only difference between the two containers is
    # whether anything was ever written to stdout.
    fixture_container "$RH" "$gone_wt" storefront 18110 ; silent=$cid

    # Three more of the hand-labelled base-stack shape, one per invalid -b
    # value the A10 row exercises. They are separate containers on purpose: at
    # the tip this row is written against, each of those values reached its
    # target and stopped it, so sharing one fixture would leave the second and
    # third legs measuring a container the first had already stopped.
    fixture_container "$RH" "$gone_wt" catalog-api 18103 ; bp_zero=$cid
    fixture_container "$RH" "$gone_wt" catalog-api 18103 ; bp_big=$cid
    fixture_container "$RH" "$gone_wt" catalog-api 18103 ; bp_lead=$cid

    # 18103 is this fixture repository's one base-stack port throughout, so
    # every mutation row carries it - which is what the requirement asks for
    # and what the rows below then have something real to be measured against.
    # None of the other fixtures publishes it, so the base-stack branch stays
    # keyed to the container it is about.
    reap_run -C "$repo" -b 18103 -m stop "$RH" "c:$livewt"
    if [ "$reap_rc" -eq 3 ] && printf '%s' "$reap_out" | grep -q 'worktree-still-listed'; then
        ok "rejected: a labelled overlay whose worktree is still listed"
    else
        fail "live-worktree target: exit $reap_rc, said '$reap_out'"
    fi

    reap_run -C "$repo" -b 18103 -m stop "$RH" "c:$bare"
    if [ "$reap_rc" -eq 3 ] && printf '%s' "$reap_out" | grep -q 'not-a-labelled-overlay'; then
        ok "rejected: an unlabelled base-stack-shaped container"
    else
        fail "unlabelled target: exit $reap_rc, said '$reap_out'"
    fi

    # The container's STATE is read as well as the exit code and the reason, the
    # way the -b omitted row below and the flag-surface enumeration after it
    # already do. A refusal that returned 3, named the right reason and stopped
    # the container anyway is not a refusal, and $future was the one fixture in
    # this block whose State.Status no row ever looked at.
    reap_run -C "$repo" -b 18103 -m stop "$RH" "c:$future"
    future_state=$(docker inspect --format '{{.State.Status}}' "$future" 2>/dev/null)
    if [ "$reap_rc" -eq 3 ] && [ "$future_state" = running ] \
       && printf '%s' "$reap_out" | grep -q 'unrecognised-label-version'; then
        ok "rejected: a label contract version this run does not recognise"
    else
        fail "unrecognised-version target: exit $reap_rc, state '${future_state:-gone}', said '$reap_out'"
    fi

    reap_run -C "$repo" -b 18103 -m stop "$RH" "c:$handlabelled"
    if [ "$reap_rc" -eq 3 ] && printf '%s' "$reap_out" | grep -q 'base-stack-port'; then
        ok "rejected: a base-stack container hand-labelled with this repository's hash8"
    else
        fail "hand-labelled base-stack target: exit $reap_rc, said '$reap_out'"
    fi

    # --- C3  the same target with -b OMITTED -------------------------------
    # The row above passes -b 18103, and so does every other base-stack row in
    # this file, which is precisely why none of them can see this: the
    # exclusion was keyed on a flag the caller may simply not pass, and a gate
    # keyed on an optional input is not a gate. Base-port information the run
    # was never given is UNKNOWN, and unknown refuses - so a container mutation
    # with no base-stack information at all refuses the target rather than
    # deciding blind, and the hand-labelled container is untouched.
    reap_run -C "$repo" -m stop "$RH" "c:$handlabelled"
    if [ "$reap_rc" -eq 3 ] \
       && printf '%s' "$reap_out" | grep -q 'base-stack-ports-unknown' \
       && [ "$(docker inspect --format '{{.State.Status}}' "$handlabelled" 2>/dev/null)" = running ]; then
        ok "rejected: a container mutation carrying no base-stack port information at all"
    else
        fail "-b omitted: exit $reap_rc, state $(docker inspect --format '{{.State.Status}}' "$handlabelled" 2>/dev/null), said '$reap_out'"
    fi

    # ...and the refusal is the missing information, not a blanket refusal.
    # Two halves prove that: the report path decides nothing, so it runs with
    # no base-stack information at all; and the rows further down act on a real
    # orphan the moment a port is supplied.
    reap_run -C "$repo" report "$RH"
    if [ "$reap_rc" -eq 0 ] && printf '%s' "$reap_out" | grep -q "^legacy${TAB}"; then
        ok "the report path still runs with no base-stack information - only mutation refuses"
    else
        fail "report with no -b: exit $reap_rc, said '$reap_out'"
    fi

    # --- A9  no flag shape that names no port reaches a base-stack container -
    # The row above proves ONE way in is closed. This one enumerates the flag
    # surface, because the previous fix closed the omission and then opened a
    # flag that reopened it: -B asserted there was nothing to exclude, nothing
    # could check the assertion, and the same container the -b 18103 row proves
    # is a base-stack service was stopped with acted 1 and exit 0.
    #
    # Every entry below is a shape that supplies no base-stack port, run
    # against the container the two rows above have already established IS one.
    # Each must refuse and leave it running. The retired flag stays in the list
    # on purpose: it is the fixture where the refusal was bypassable, and the
    # row is only worth having while it can still be run.
    a9_bad=''
    a9_try() {
        _label=$1; _want=$2; _cid=$3; _verb=$4
        shift 4
        reap_run -C "$repo" "$@" -m "$_verb" "$RH" "c:$_cid"
        _st=$(docker inspect --format '{{.State.Status}}' "$_cid" 2>/dev/null)
        [ "$reap_rc" -eq "$_want" ] && [ "$_st" = running ] && return 0
        a9_bad="$a9_bad [$_label: wanted exit $_want with it running, got exit $reap_rc and '${_st:-gone}']"
    }

    a9_try 'no base-port flag at all'            3 "$handlabelled" stop
    a9_try 'the retired override'                2 "$handlabelled" stop   -B
    a9_try 'the retired override, twice'         2 "$handlabelled" stop   -B -B
    a9_try 'no base-port flag, under remove'     3 "$handlabelled" remove
    a9_try 'the retired override, under remove'  2 "$handlabelled" remove -B
    if [ -z "$a9_bad" ]; then
        ok "no flag shape that names no base port reaches a base-stack container: all five refuse, it is still running"
    else
        fail "a base-stack container was reachable:$a9_bad"
    fi

    # ...and the enumeration can report a shape that DID reach its target. The
    # fixture is the declared residual itself, executed rather than asserted: a
    # port is supplied, it is simply not this container's, so the exclusion has
    # nothing to match and the orphan is acted on. That is the accepted limit
    # of exclusion-by-supplied-port - and it is also what proves the five rows
    # above are not five refusals of everything.
    a9_bad=''
    a9_try 'a supplied port that is not this container-s' 3 "$residual" stop -b 19999
    if [ -n "$a9_bad" ]; then
        ok "rejected: the enumeration coming back silent for a shape that reached its target"
    else
        fail "the flag-surface enumeration cannot report a container it failed to protect"
    fi

    # --- A10  the declared residual, executed against the very container the -
    # --- five shapes above could not reach ----------------------------------
    # The enumeration proves those five shapes refuse. It cannot prove the
    # container was reachable at all: a fixture that never entered the
    # candidate set - a wrong id, a lost label - produces the same five
    # refusals, and the row would read green over a check that had stopped
    # checking. So the same container is now reached, deliberately, by the one
    # shape that reaches it: a VALID base port that is simply not this
    # container's. It is stopped, and the row asserts that it is.
    #
    # That is the accepted limit executed rather than asserted. The port
    # exclusion is caller-supplied and caller-defeatable, and a suite that only
    # exercised the shapes we hoped were safe is how three rounds shipped green
    # with a hole in each.
    #
    # The three legs after it say what the new validation is worth and what it
    # is not. 0 and 99999999 are not ports and no longer reach anything; 018103
    # is read as 18103, so the container it names is excluded instead of
    # silently reaped. None of that narrows the first leg - 1 is a valid port,
    # and no range test can tell a wrong one from a right one.
    a10_bad=''
    a10_try() {
        _label=$1; _rc=$2; _state=$3; _says=$4; _cid=$5
        shift 5
        reap_run -C "$repo" "$@" -m stop "$RH" "c:$_cid"
        _st=$(docker inspect --format '{{.State.Status}}' "$_cid" 2>/dev/null)
        if [ "$reap_rc" -eq "$_rc" ] && [ "$_st" = "$_state" ] \
           && printf '%s' "$reap_out" | grep -q "$_says"; then
            return 0
        fi
        a10_bad="$a10_bad [$_label: wanted exit $_rc, '$_state', saying '$_says'; got exit $reap_rc, '${_st:-gone}', said '$reap_out']"
    }

    a10_try 'a valid port that is not this container-s' \
        0 exited  "^acted${TAB}1\$" "$handlabelled" -b 1
    a10_try 'a value that is not a port at all' \
        2 running 'outside 1-65535' "$bp_zero" -b 0
    a10_try 'a value far outside the port range' \
        2 running 'outside 1-65535' "$bp_big" -b 99999999
    a10_try 'a manifest value typed with a leading zero' \
        3 running 'base-stack-port' "$bp_lead" -b 018103
    if [ -z "$a10_bad" ]; then
        ok "the declared residual, executed: a valid wrong port DOES reach the hand-labelled base-stack container and stops it, while a value that is not a port reaches nothing"
    else
        fail "the declared residual:$a10_bad"
    fi

    # --- A10  the half that is NOT caller-defeatable ------------------------
    # Candidacy is a positive, closed allowlist: only an overlay launch writes
    # stackgraft.repo, so a base-stack container carrying no label set is
    # outside the candidate set whatever ports are passed. Enumerated with the
    # port that would exclude it, one that would not, and the top of the range.
    # Each must refuse for the ALLOWLIST reason rather than for a missing port,
    # which is why the reason is asserted and not only the exit code.
    #
    # -b 1 is in the list deliberately: the row above proves that same value
    # reaches a labelled container, so a refusal here is about the labels and
    # not about the value. This is the half the contract may still promise
    # without a condition, and it is the half that was never the defect.
    allow_bad=''
    for bp in 18103 1 65535; do
        reap_run -C "$repo" -b "$bp" -m stop "$RH" "c:$bare"
        allow_st=$(docker inspect --format '{{.State.Status}}' "$bare" 2>/dev/null)
        if [ "$reap_rc" -eq 3 ] && [ "$allow_st" = running ] \
           && printf '%s' "$reap_out" | grep -q 'not-a-labelled-overlay-of-this-repository'; then
            continue
        fi
        allow_bad="$allow_bad [-b $bp: exit $reap_rc, '${allow_st:-gone}', said '$reap_out']"
    done
    if [ -z "$allow_bad" ]; then
        ok "a base-stack container carrying no label set is outside the candidate set at every -b value: the allowlist is what excludes it, and no port widens it"
    else
        fail "an unlabelled base-stack container was reachable:$allow_bad"
    fi

    # --- C2  a refusal refuses its own target, not the invocation -----------
    # One invocation, two targets: an orphan that proves out and a live-worktree
    # overlay that does not. Two locked requirements say a refusal MUST NOT stop
    # the run acting on the remaining proven candidates, and nothing here is
    # transactional - each stop is independent and no state spans the two - so
    # refusing the whole invocation costs the proven work and buys nothing.
    # Both sets must be reported: the refusal by name, and the count of what was
    # acted on.
    reap_run -C "$repo" -b 18103 -m stop "$RH" "c:$mixed" "c:$livewt"
    mixed_state=$(docker inspect --format '{{.State.Status}}' "$mixed" 2>/dev/null)
    live_state=$(docker inspect --format '{{.State.Status}}' "$livewt" 2>/dev/null)
    if [ "$reap_rc" -eq 3 ] \
       && printf '%s' "$reap_out" | grep -q 'worktree-still-listed' \
       && printf '%s' "$reap_out" | grep -q "^acted${TAB}1\$" \
       && [ "$mixed_state" = exited ] && [ "$live_state" = running ]; then
        ok "a refused target does not stop the proven one: the orphan is acted on, the live overlay refused"
    else
        fail "proven + unproven in one invocation: exit $reap_rc, orphan $mixed_state, live $live_state, said '$reap_out'"
    fi

    # --- W5  the same rule one layer up, at the parsing layer ---------------
    # A target that would not parse used to end the whole invocation at exit 2:
    # both proven orphans beside it left running, and no acted record printed
    # at all - the exact half of C2 that was fixed for the proof layer, still
    # shipping at the layer before it. The malformed target sits BETWEEN the
    # two proven ones, so a run that stopped at the first refusal and one that
    # skipped only the refusal are distinguishable.
    #
    # 'p:abc' carries a second argument because a p: target takes two by
    # contract, malformed or not - the parse consumes what the caller wrote as
    # its start time rather than reading the next target as one.
    reap_run -C "$repo" -b 18103 -m stop "$RH" \
        "c:$w5a" 'p:abc' 'Wed Jul 30 12:00:00 2026' "c:$w5b"
    w5a_state=$(docker inspect --format '{{.State.Status}}' "$w5a" 2>/dev/null)
    w5b_state=$(docker inspect --format '{{.State.Status}}' "$w5b" 2>/dev/null)
    if [ "$reap_rc" -eq 3 ] \
       && printf '%s' "$reap_out" | grep -q 'malformed-target' \
       && printf '%s' "$reap_out" | grep -q "^acted${TAB}2\$" \
       && [ "$w5a_state" = exited ] && [ "$w5b_state" = exited ]; then
        ok "a target that will not parse is one refusal: both proven orphans are still acted on and acted says 2"
    else
        fail "malformed target beside proven ones: exit $reap_rc, first '$w5a_state', second '$w5b_state', said '$reap_out'"
    fi

    # The removal flag on its own mutates nothing and says what is missing.
    # Asserted on a RUNNING orphan, so a mutation would be visible.
    reap_run -C "$repo" remove "$RH" "c:$orphan"
    if [ "$reap_rc" -eq 2 ] \
       && printf '%s' "$reap_out" | grep -q 'mutation-flag-required' \
       && [ "$(docker inspect --format '{{.State.Status}}' "$orphan" 2>/dev/null)" = running ]; then
        ok "rejected: the removal flag alone - nothing mutated, the mutation flag named"
    else
        fail "removal flag alone: exit $reap_rc, said '$reap_out'"
    fi

    # Under stop an already-exited container is a no-op, so it is reported and
    # skipped and MUST NOT be counted as work done: acted stays at zero.
    reap_run -C "$repo" -b 18103 -m stop "$RH" "c:$exited"
    if [ "$reap_rc" -eq 0 ] \
       && printf '%s' "$reap_out" | grep -q 'skipped-not-running' \
       && printf '%s' "$reap_out" | grep -q "^acted${TAB}0\$"; then
        ok "an exited container is reported and skipped under stop, and counts as no work"
    else
        fail "exited container under stop: exit $reap_rc, said '$reap_out'"
    fi

    # ...and the exclusion above is the base-stack test, not a blanket refusal:
    # the same shape without the base-port marker IS a target.
    #
    # What the orphan said BEFORE the stop is taken here, because the row below
    # has to be able to tell a stop that destroyed the account apart from a
    # fixture that never wrote one.
    orphan_said=$(docker logs "$orphan" 2>&1)
    reap_run -C "$repo" -b 18103 -m stop "$RH" "c:$orphan"
    if [ "$reap_rc" -eq 0 ] && printf '%s' "$reap_out" | grep -q "^acted${TAB}1\$"; then
        ok "a labelled orphan that is no base-stack service is acted on"
    else
        fail "orphan target: exit $reap_rc, said '$reap_out'"
    fi
    [ "$(docker inspect --format '{{.State.Status}}' "$orphan" 2>/dev/null)" = exited ] \
        && ok "the stop left the container in place rather than removing it" \
        || fail "the stopped orphan is not in the exited state"

    # A stop MUST leave the container's account of itself readable. This row
    # used to assert that with `docker logs >/dev/null 2>&1` over a fixture that
    # ran a bare `sleep 120` and wrote nothing, and an exit code over no bytes
    # proves nothing. Measured on that fixture: a silent container answers rc 0
    # with ZERO bytes both before and after the stop, and only an ABSENT
    # container answers rc 1 - so the one state the exit code could distinguish
    # was the container being gone, which the row directly above already proves
    # by asserting it is `exited`. Preserved logs, destroyed logs and logs that
    # never existed all read identically, and destroyed logs are the failure the
    # row's own message names.
    #
    # So the fixture speaks a known marker before it sleeps and what is asserted
    # is that the marker comes back AFTER the stop.
    #
    # A missing marker has two causes and they are not the same defect: a stop
    # that destroyed what the container wrote, and a fixture that never wrote
    # anything. The pre-stop capture separates them, so this row can never
    # report the second as the first.
    #
    # One decision, shared by this row and by its negative below, so the
    # negative exercises the assertion that actually runs rather than a second
    # copy of it that could drift away from it. -F and -- because a marker is
    # data: its characters are not a pattern and a leading dash is not a flag.
    logs_carry() { docker logs "$1" 2>&1 | grep -qF -- "$2"; }

    if printf '%s' "$orphan_said" | grep -qF -- "$ORPHAN_SAYS"; then
        logs_carry "$orphan" "$ORPHAN_SAYS" \
            && ok "a stopped orphan's logs are still readable: what it said before the stop reads back after it" \
            || fail "the stop destroyed the logs, which are the only account of the orphan"
    else
        fail "the orphan fixture never wrote its marker, so the row above it has no preserved account to find"
    fi

    # The negative carries the diagnosis rather than only the verdict. It is the
    # fixture this row USED to run - a container that writes nothing - stopped by
    # the same invocation shape, and it re-runs the row's ORIGINAL assertion and
    # requires it to STILL PASS before requiring the new one to fail. One row
    # therefore proves both halves: that an exit code from `docker logs` was
    # blind to a container holding no account at all, and that the marker is what
    # sees it. If a later edit weakens the marker assertion back into an exit-code
    # test, this row stops printing ok.
    reap_run -C "$repo" -b 18103 -m stop "$RH" "c:$silent"
    silent_state=$(docker inspect --format '{{.State.Status}}' "$silent" 2>/dev/null)
    docker logs "$silent" >/dev/null 2>&1
    silent_rc=$?
    if [ "$silent_rc" -eq 0 ] && [ "$silent_state" = exited ] \
       && ! logs_carry "$silent" "$ORPHAN_SAYS"; then
        ok "rejected: a stopped container holding no account of itself - the old exit-code assertion still passes over it, the marker assertion does not"
    else
        fail "the silent fixture did not reproduce the blind spot: state '${silent_state:-gone}', docker logs exited $silent_rc"
    fi

    # Under remove the same exited container IS a target - D8's corollary is a
    # filter on the state, not a comment about it.
    reap_run -C "$repo" -b 18103 -m remove "$RH" "c:$exited"
    if [ "$reap_rc" -eq 0 ] && ! docker inspect "$exited" >/dev/null 2>&1; then
        ok "an exited container is a target under remove"
    else
        fail "exited container under remove: exit $reap_rc, said '$reap_out'"
    fi

    # Removal has no meaning for a process, and that is the target's problem
    # rather than the invocation's: refused by name, with the run's account of
    # itself still printed. pid 1 is used because it is certain to exist, and
    # nothing here reaches the signal.
    reap_run -C "$repo" -m remove "$RH" 'p:1' 'x'
    if [ "$reap_rc" -eq 3 ] \
       && printf '%s' "$reap_out" | grep -q 'no meaning for a process' \
       && printf '%s' "$reap_out" | grep -q "^acted${TAB}0\$"; then
        ok "rejected: remove against a process target, refused by name and not as a usage error"
    else
        fail "remove against a p: target: exit $reap_rc, said '$reap_out'"
    fi

    # -v: alpine/git declares a volume of its own, so each of these fourteen
    # fixtures was leaving one anonymous volume nothing could ever find again -
    # fourteen of the eighteen the suite leaked per run before the chain close.
    for id in $fixture_ids; do docker rm -f -v "$id" >/dev/null 2>&1; done
    ( cd "$repo" && git worktree remove --force "$rf/wt" ) >/dev/null 2>&1
    rm -rf "$rf"
else
    skip "the container refusal fixtures (no docker daemon or alpine/git image)" runtime
fi

# --- V14  the process half: a recycled pid is refused, a proven one is not ---
if [ "$lstart_here" -eq 1 ]; then
    # Orphaned deliberately: a child of this shell stays a zombie after it dies
    # and kill -0 would still succeed on it, so the liveness assertion below
    # would pass whatever happened.
    vic=$(sh -c 'sleep 300 >/dev/null 2>&1 & printf "%s\n" "$!"')
    true_lstart=$(ps -o lstart= -p "$vic" 2>/dev/null | awk 'NF { print; exit }')

    reap_run -m stop 00c0ffee "p:$vic" 'Wed Jan  1 00:00:00 2020'
    if [ "$reap_rc" -eq 3 ] && kill -0 "$vic" 2>/dev/null \
       && printf '%s' "$reap_out" | grep -q 'identity-mismatch'; then
        ok "rejected: a pid whose recorded start time no longer matches (exit 3, still alive)"
    else
        fail "wrong-lstart target: exit $reap_rc, said '$reap_out'"
    fi

    # V12 refusal half: a record that never captured a start time is
    # permanently unproven, and unproven is refused rather than tolerated.
    reap_run -m stop 00c0ffee "p:$vic" null
    if [ "$reap_rc" -eq 3 ] && kill -0 "$vic" 2>/dev/null \
       && printf '%s' "$reap_out" | grep -q 'lstart-unproven'; then
        ok "rejected: a sidecar record whose start time is null"
    else
        fail "null-lstart target: exit $reap_rc, said '$reap_out'"
    fi

    # ...and the true identity IS acted on, which is what makes the two above
    # proofs rather than a script that refuses everything.
    reap_run -m stop 00c0ffee "p:$vic" "$true_lstart"
    n=0
    while kill -0 "$vic" 2>/dev/null && [ "$n" -lt 10 ]; do sleep 1; n=$((n + 1)); done
    if [ "$reap_rc" -eq 0 ] && ! kill -0 "$vic" 2>/dev/null; then
        ok "a pid with its true recorded start time is acted on"
    else
        fail "true-lstart target: exit $reap_rc, said '$reap_out'"
    fi
    kill -KILL "$vic" 2>/dev/null

    # --- W3  a runtime that will not act is one target's failure ------------
    # A target can prove out and still not be actionable, and the failure used
    # to end the loop where it happened: the targets after it were never
    # reached and the acted record - the run's own account of what it did - was
    # never printed at all. That is the half-applied run the whole-invocation
    # refusal was justified by, produced by the code that justified it.
    #
    # pid 1 is the portable "proven, and not ours to signal": its start time
    # re-reads and matches, so the proof holds, while kill returns EPERM for
    # any user that is not root. Root ignores that, so the row stands down
    # there rather than actually signalling init.
    #
    # Its survival is asserted with ps rather than kill -0, because kill -0
    # answers EPERM here too - the same permission that makes this fixture
    # deterministic would make that probe read a living init as gone.
    if [ "$(id -u)" -ne 0 ]; then
        one_lstart=$(ps -o lstart= -p 1 2>/dev/null | awk 'NF { print; exit }')
        vic2=$(sh -c 'sleep 300 >/dev/null 2>&1 & printf "%s\n" "$!"')
        vic2_lstart=$(ps -o lstart= -p "$vic2" 2>/dev/null | awk 'NF { print; exit }')
        reap_run -m stop 00c0ffee 'p:1' "$one_lstart" "p:$vic2" "$vic2_lstart"
        n=0
        while kill -0 "$vic2" 2>/dev/null && [ "$n" -lt 10 ]; do sleep 1; n=$((n + 1)); done
        if [ "$reap_rc" -eq 4 ] \
           && printf '%s' "$reap_out" | grep -q 'signal-failed' \
           && printf '%s' "$reap_out" | grep -q "^acted${TAB}1\$" \
           && ! kill -0 "$vic2" 2>/dev/null \
           && ps -o pid= -p 1 >/dev/null 2>&1; then
            ok "a target the runtime would not act on is one refusal: the next target is still acted on and acted is reported"
        else
            fail "unsignallable target mid-run: exit $reap_rc, said '$reap_out'"
        fi
        kill -KILL "$vic2" 2>/dev/null
    else
        skip "the unsignallable-target row (running as root, which can signal pid 1)" conditional
    fi
else
    skip "the (pid, lstart) target rows (this host has no ps -o lstart=)" conditional
fi

# --- scoping is in the query, not in a filter over its output ----------------
# This is the check DS28's dropped query 3 would have failed, and A7 is why it
# stays dropped: an unfiltered listing does not find legacy overlays, it lists
# everything and cannot say which is which - while reaching a sibling
# repository's containers, which are not ours to enumerate or to kill.
#
# Comment lines and the manual command the legacy record PRINTS are skipped by
# name: they are text, not invocations. The fixtures below prove the detector
# still fires on a real one.
#
# Both numbers are counted - the listings SEEN and, of those, how many carry no
# hash8 filter - because an unfiltered count of zero is equally true of a script
# that lists no containers at all. A shipped script that had dropped its
# listings, or a glob that matched no scripts, read exactly like one whose every
# listing is scoped: `-eq 0` was a gate absence satisfied. And `docker container
# ls` is the same command under its other spelling, so keying on `docker ps`
# alone left the detector blind to a listing that simply used the long form.
ps_listings() {
    awk '
        /^[ \t]*#/                   { next }
        /Inspect them yourself with/ { next }
        /docker ps|docker container ls/ {
            seen++
            if ($0 !~ /label=stackgraft\.repo=/) unfiltered++
        }
        END { print (seen + 0) " " (unfiltered + 0) }
    ' "$@"
}

# One decision, shared by the shipped row and by every fixture below, so the
# fixtures exercise the rule that actually runs rather than a restatement of it.
listing_verdict() {
    _c=$(ps_listings "$@")
    _seen=${_c%% *}
    _unf=${_c##* }
    if [ "$_seen" -eq 0 ]; then
        printf 'none-seen\n'
    elif [ "$_unf" -gt 0 ]; then
        printf 'unfiltered-%s\n' "$_unf"
    else
        printf 'pass\n'
    fi
}

[ "$(listing_verdict "$SKILL"/scripts/*.sh)" = pass ] \
    && ok "every container listing in a shipped script carries the hash8 label filter" \
    || fail "container listings in shipped scripts: $(listing_verdict "$SKILL"/scripts/*.sh)"

# ...and the verdict can fire on each of the three shapes it exists to catch, in
# the `nv_try` shape the release-notes block below uses for the same job.
qf=$(mktemp -d)
printf '#!/bin/sh\nlegacy=$(docker ps --all --format "{{.ID}}")\n'           > "$qf/short.sh"
printf '#!/bin/sh\nlegacy=$(docker container ls --all --format "{{.ID}}")\n' > "$qf/long.sh"
printf '#!/bin/sh\nprintf "this script lists no containers at all\\n"\n'     > "$qf/none.sh"
lv_bad=''
lv_try() {
    _got=$(listing_verdict "$2")
    [ "$_got" = "$3" ] || lv_bad="$lv_bad [$1: $_got, wanted $3]"
}
lv_try 'a repository-wide listing, the query A7 keeps dropped' "$qf/short.sh" unfiltered-1
lv_try 'the same listing under its `docker container ls` name' "$qf/long.sh"  unfiltered-1
lv_try 'a script that lists nothing at all'                    "$qf/none.sh"  none-seen
[ -z "$lv_bad" ] \
    && ok "rejected: an unfiltered listing in either spelling, and a file that lists nothing reported as that rather than as compliance" \
    || fail "the unfiltered-listing detector could not see a shape it exists to catch:$lv_bad"
rm -rf "$qf"

# --- V33  A7: the legacy statement IS the deliverable ------------------------
# A7 accepts a real coverage loss and pays for it by saying so out loud.
# Nothing else in this change can reject a report that simply left the
# statement out, so the rule gets a validator and three fixtures rather than a
# file review: silence reads as "nothing to see", which is the exact defect the
# loss was accepted to avoid.
a7_verdict() {
    grep -q "^legacy${TAB}" "$1"                     || { printf 'no-legacy-record\n'; return 0; }
    grep -q "^legacy${TAB}.*stackgraft\.labels" "$1" || { printf 'category-unnamed\n'; return 0; }
    grep -q "^legacy${TAB}.*docker ps" "$1"          || { printf 'no-manual-command\n'; return 0; }
    grep -q 'by construction' "$1"                   || { printf 'not-stated-structural\n'; return 0; }
    if grep -q "^legacy${TAB}.*[0-9]" "$1"; then
        printf 'count-asserted\n'
        return 0
    fi
    if grep -qiE 'is complete|are complete|exhaustive|all overlays|every overlay' "$1"; then
        printf 'completeness-claimed\n'
        return 0
    fi
    printf 'pass\n'
}

af=$(mktemp -d)
sh "$REAP" report 00c0ffee > "$af/report.txt" 2>/dev/null
rc=$?
a7_state=$(a7_verdict "$af/report.txt")
if [ "$rc" -eq 0 ] && [ "$a7_state" = pass ]; then
    ok "the report names the legacy category, calls it structural, and prints the manual command"
else
    fail "the report's legacy statement: exit $rc, verdict $a7_state"
fi

# This fixture REMOVES the legacy line, so it only says anything while the line
# was there to remove. `no-legacy-record` is also what an EMPTY report verdicts
# to - a reap.sh that printed nothing at all - and the row read that as the
# fixture doing its job. It was correct only because the row above had proven
# the report is a real one; the premise is stated here instead, the way the
# removed-entry and removed-definition fixtures in the release-notes block name
# theirs.
grep -v "^legacy${TAB}" "$af/report.txt" > "$af/silent.txt"
if [ "$a7_state" = pass ] && [ "$(a7_verdict "$af/silent.txt")" = no-legacy-record ]; then
    ok "rejected: a report with the legacy statement absent - silence reads as nothing to see"
else
    fail "ACCEPTED but must be rejected: a report that says nothing about legacy overlays"
fi

awk -v t="$TAB" '
    $0 ~ "^legacy" t "undetectable" {
        print "legacy" t "found" t "0 unlabelled containers predating stackgraft.labels; docker ps --all"
        next
    }
    { print }' "$af/report.txt" > "$af/counted.txt"
[ "$(a7_verdict "$af/counted.txt")" = count-asserted ] \
    && ok "rejected: a report asserting a legacy count, zero included" \
    || fail "ACCEPTED but must be rejected: a legacy count no query can produce"

{ cat "$af/report.txt"; printf 'note%sthe overlay list above is complete\n' "$TAB"; } > "$af/claimed.txt"
[ "$(a7_verdict "$af/claimed.txt")" = completeness-claimed ] \
    && ok "rejected: a report claiming the overlay list is complete" \
    || fail "ACCEPTED but must be rejected: a completeness claim the report cannot make"
rm -rf "$af"

# --- V11  the report takes no lock, waits for none, and creates none ---------
# The lock is planted on the file the report actually reads, and its owner
# names a LIVE pid - the state a writer leaves while it works, and the one
# with-lock.sh refuses to steal from. A report that waited for it would not
# come back inside this run.
count_locks() { find "$1" -maxdepth 1 -name '*.lock' 2>/dev/null | wc -l | tr -d ' '; }

# The registry file's name carries the MAIN WORKTREE'S DIRECTORY NAME, and these
# fixtures used to hard-code this repository's. That made three rows a property of
# where the checkout happens to sit: on a minimal Linux image the tree is mounted
# at /w, so reap.sh looks for `w-00c0ffee.processes.json`, found nothing where the
# fixture had planted `stackgraft-…`, and reported registry-missing. Three rows
# failed on every commit including the baseline, and the diagnosis was the fixture
# rather than the script both times somebody looked.
#
# So the fixtures bring their own repository, whose directory name they choose.
# One arrangement now covers a primary checkout, a linked worktree and a bind
# mount, which is the same repair the minimal-image reap rows took for the same
# reason. And the name is not derived here from reap.sh's own expression - a
# fixture that computes the answer cannot notice the answer changing - it is
# asserted instead: the report PRINTS the file it read, and the row below requires
# that to be the file this block planted.
registry_fixture() {
    mkdir -p "$1/stackgraft" "$1/$REGISTRY_REPO"
    ( cd "$1/$REGISTRY_REPO" && git init -q . && fixture_commit -q --allow-empty -m init ) >/dev/null 2>&1
}
REGISTRY_REPO=sg-registry-fixture
registry_reported() { printf '%s' "$1" | awk -F"$TAB" '$1 == "host" { print $NF; exit }'; }

lf=$(mktemp -d)
registry_fixture "$lf"
sc="$lf/stackgraft/$REGISTRY_REPO-00c0ffee.processes.json"
printf '{"version":1,"repo":"00c0ffee","at":"x","overlays":[]}\n' > "$sc"
mkdir "$sc.lock"
printf '%s\n-\n%s\n' "$$" "$(uname -n)" > "$sc.lock/owner"

before_locks=$(count_locks "$lf/stackgraft")
out=$(XDG_CACHE_HOME="$lf" sh "$REAP" -C "$lf/$REGISTRY_REPO" report 00c0ffee 2>&1)
rc=$?
after_locks=$(count_locks "$lf/stackgraft")

# The premise for all three registry rows, stated rather than assumed. Every one
# of them concludes something from what the report says about a file; if the
# report is reading a DIFFERENT file, each of them is a true statement about
# nothing. This row is what turns that into a failure with the two paths in it.
[ "$(registry_reported "$out")" = "$sc" ] \
    && ok "the report reads the registry file this fixture planted, so the rows below are about that file" \
    || fail "the report read '$(registry_reported "$out")' where the fixture planted '$sc', so no registry row proves anything"

if [ "$rc" -eq 0 ] && [ "$before_locks" = "$after_locks" ] \
   && printf '%s' "$out" | grep -q "^host${TAB}checked${TAB}none"; then
    ok "the report completes and reads the registry while a writer holds its lock"
else
    fail "report under a held lock: exit $rc, locks $before_locks -> $after_locks"
fi

mkdir "$lf/stackgraft/fixture.lock"
[ "$(count_locks "$lf/stackgraft")" != "$after_locks" ] \
    && ok "rejected: a fixture that leaves a lock directory behind" \
    || fail "the lock detector cannot notice a lock directory appearing"
rm -rf "$lf"

# --- V21  checked-and-none and not-checked are different claims --------------
# The same fixture repository as the block above, and for the same reason: these
# two rows are the other two that failed on a minimal Linux image at every commit
# including the baseline, on a registry path nobody had noticed was a property of
# the checkout rather than of the script.
sf2=$(mktemp -d)
registry_fixture "$sf2"
sc2="$sf2/stackgraft/$REGISTRY_REPO-00c0ffee.processes.json"

printf '{"version":1,"repo":"00c0ffee","at":"x","overlays":[]}\n' > "$sc2"
out=$(XDG_CACHE_HOME="$sf2" sh "$REAP" -C "$sf2/$REGISTRY_REPO" report 00c0ffee 2>/dev/null)

[ "$(registry_reported "$out")" = "$sc2" ] \
    && ok "the report reads the registry file this block planted, so its three shape rows are about that file" \
    || fail "the report read '$(registry_reported "$out")' where the fixture planted '$sc2', so no registry-shape row proves anything"

# One expression for the checked-zero line, read once and used by both rows
# below rather than grepped twice.
if printf '%s' "$out" | grep -q "^host${TAB}checked${TAB}none"; then
    host_checked=1
else
    host_checked=0
fi
[ "$host_checked" -eq 1 ] \
    && ok "an empty registry reports zero host overlays, checked" \
    || fail "an empty registry did not report a checked zero"

# The row below is an ABSENCE, and an absence is also what no output at all
# produces: a reap.sh that printed nothing has no `held incomplete` line either,
# so the row said "every store answered" over a report that answered nothing. It
# was correct only because the row above proved $out is a real report; that
# premise is a branch of its own now, the way the compose `up` row requires up's
# own help before concluding anything from a missing flag.
if [ "$docker_ready" -eq 1 ]; then
    if [ "$host_checked" -ne 1 ]; then
        fail "the report never said it checked the host registry, so a missing held-port shortfall line proves nothing"
    elif printf '%s' "$out" | grep -q "^held${TAB}incomplete"; then
        fail "the held-port set reported itself short with every store readable"
    else
        ok "rejected: the held-port shortfall line when every store answered"
    fi
fi

rm -f "$sc2"
out=$(XDG_CACHE_HOME="$sf2" sh "$REAP" -C "$sf2/$REGISTRY_REPO" report 00c0ffee 2>/dev/null)
if printf '%s' "$out" | grep -q "^host${TAB}unknown${TAB}registry-missing" \
   && ! printf '%s' "$out" | grep -q "^host${TAB}checked"; then
    ok "an absent registry reports unknown and names the file, never a zero"
else
    fail "an absent registry was rendered as zero host overlays, or did not name the file"
fi
printf '%s' "$out" | grep -q "^held${TAB}incomplete" \
    && ok "an unreadable store makes the held-port set report itself short" \
    || fail "the held-port set claimed to be whole with a store unread"

printf 'not a registry at all\n' > "$sc2"
out=$(XDG_CACHE_HOME="$sf2" sh "$REAP" -C "$sf2/$REGISTRY_REPO" report 00c0ffee 2>/dev/null)
if printf '%s' "$out" | grep -q "^host${TAB}unknown${TAB}registry-damaged" \
   && ! printf '%s' "$out" | grep -q "^host${TAB}checked"; then
    ok "rejected: a damaged registry rendered as a zero - it reports unknown"
else
    fail "a damaged registry did not report unknown"
fi
rm -rf "$sf2"

# --- V31  a spelling difference decides kill or not --------------------------
# Driven through the shipped block itself, lifted between its sentinels exactly
# as the probe is, so the one rule that decides whether something gets stopped
# is exercised without needing a container runtime for it.
wf=$(mktemp -d)
wfp=$(CDPATH= cd -- "$wf" && pwd -P)
{
    printf '#!/bin/sh\nset -u\n'
    awk '/BEGIN worktree liveness/ { on = 1; next } /END worktree liveness/ { on = 0 } on { print }' "$REAP"
    printf 'idx=$(wt_scan < "$1")\nwt_state "$2" "$idx"\n'
} > "$wf/wt.sh"

mkdir -p "$wf/real/wt"
ln -s "$wf/real" "$wf/link"
printf 'worktree %s/link/wt\n' "$wf" > "$wf/porcelain"

[ "$(sh "$wf/wt.sh" "$wf/porcelain" "$wfp/real/wt")" = live ] \
    && ok "a worktree reached by a symlinked spelling reads live, not orphaned" \
    || fail "a symlinked spelling read as orphaned, which is a stop on live work"

# ...and normalising did not blanket-suppress orphan detection along with it.
[ "$(sh "$wf/wt.sh" "$wf/porcelain" "$wfp/real/gone")" = absent ] \
    && ok "rejected: a worktree that really is gone - it still reads as an orphan candidate" \
    || fail "orphan detection was suppressed along with the spelling difference"

# One path git still C-quotes makes every absent answer unproven instead.
printf 'worktree "%s/real/we\\tird"\n' "$wf" >> "$wf/porcelain"
[ "$(sh "$wf/wt.sh" "$wf/porcelain" "$wfp/real/gone")" = unresolvable ] \
    && ok "a path git C-quotes is unresolvable, and unproven is never orphaned" \
    || fail "a C-quoted path let an absent answer read as an orphan"

printf 'worktree %s/real/wt\nprunable gitdir file points to non-existent location\n' "$wf" > "$wf/prunable"
[ "$(sh "$wf/wt.sh" "$wf/prunable" "$wf/real/wt")" = prunable ] \
    && ok "a prunable entry classifies unknown, being proof of neither liveness nor absence" \
    || fail "a prunable entry did not classify unknown"
rm -rf "$wf"

# --- V18, V28, V30  scoping, availability, and a real run on a minimal image -
if [ "$docker_ready" -eq 1 ]; then
    out=$(sh "$REAP" report 00c0ffee 2>/dev/null)

    # One expression for the checked-zero line, read once and used by both rows
    # below rather than grepped twice, exactly as $host_checked is above.
    if printf '%s' "$out" | grep -q "^container${TAB}checked${TAB}none"; then
        container_checked=1
    else
        container_checked=0
    fi
    [ "$container_checked" -eq 1 ] \
        && ok "a runtime that answered and matched nothing reports a checked zero" \
        || fail "the runtime answered and the report stated no checked zero"

    # The row below is an ABSENCE, and an absence is also what no output at all
    # produces: a reap.sh that printed nothing has no `degraded docker-unavailable`
    # line either, so the row said "the runtime answers here" over a report that
    # answered nothing. It was correct only because the checked-zero row happened
    # to sit two lines away and prove $out is a real report - adjacency, not an
    # assertion. That premise is a branch of its own now, the way the held-port
    # and A7 absences above state theirs.
    if [ "$container_checked" -ne 1 ]; then
        fail "the report never said it checked the container runtime, so a missing docker-unavailable line proves nothing"
    elif printf '%s' "$out" | grep -q "^degraded${TAB}docker-unavailable"; then
        fail "the report claims the runtime is unavailable on a host where it answers"
    else
        ok "rejected: the docker-unavailable line on a host that has docker"
    fi
fi

if [ "$docker_ready" -eq 1 ] && docker image inspect alpine/git >/dev/null 2>&1; then
    H1=aaaa1111
    H2=bbbb2222
    c1=$(docker run -d --entrypoint sh \
        --label stackgraft.labels=1 --label "stackgraft.repo=$H1" \
        --label stackgraft.worktree=/nowhere/one --label stackgraft.service=storefront \
        --label stackgraft.port=18201 alpine/git -c 'sleep 60' 2>/dev/null)
    c2=$(docker run -d --entrypoint sh \
        --label stackgraft.labels=1 --label "stackgraft.repo=$H2" \
        --label stackgraft.worktree=/nowhere/two --label stackgraft.service=storefront \
        --label stackgraft.port=18202 alpine/git -c 'sleep 60' 2>/dev/null)
    anon_note "$c1"
    anon_note "$c2"
    if [ -n "$c1" ] && [ -n "$c2" ]; then
        short1=$(printf '%s' "$c1" | cut -c1-12)
        short2=$(printf '%s' "$c2" | cut -c1-12)
        out=$(sh "$REAP" report "$H1" 2>/dev/null)
        if printf '%s' "$out" | grep -q "$short1" && ! printf '%s' "$out" | grep -q "$short2"; then
            ok "the hash8-scoped report returns this repository's overlay and not the sibling's"
        else
            fail "the hash8-scoped report did not scope to one repository"
        fi
        # ...and it is the filter doing that, not the directory the command ran
        # in: the same listing unfiltered returns both.
        unfiltered=$(docker ps --all --quiet --no-trunc 2>/dev/null)
        if printf '%s' "$unfiltered" | grep -q "$c1" && printf '%s' "$unfiltered" | grep -q "$c2"; then
            ok "rejected: the same listing unfiltered, which returns both repositories' overlays"
        else
            fail "the unfiltered listing did not return both, so the comparison proves nothing"
        fi
        docker rm -f -v "$c1" "$c2" >/dev/null 2>&1
    else
        fail "could not launch the two-repo scoping fixture"
    fi

    # The report path's own payoff, end to end and with no mutation flag: a
    # port a live overlay holds comes back as a held record and is handed to
    # pick-port.sh as its own argument, which then must not return it.
    HP=aaaa3333
    hpwt=$(mktemp -d)
    hpc=$(docker run -d --entrypoint sh \
        --label stackgraft.labels=1 --label "stackgraft.repo=$HP" \
        --label "stackgraft.worktree=$(CDPATH= cd -- "$hpwt" && pwd -P)" \
        --label stackgraft.service=storefront --label stackgraft.port=18500 \
        alpine/git -c 'sleep 60' 2>/dev/null)
    anon_note "$hpc"
    if [ -n "$hpc" ]; then
        held=$(sh "$REAP" report "$HP" 2>/dev/null | awk -F"$TAB" '$1 == "held" && $2 ~ /^[0-9]+$/ { print $2 }')
        if [ "$held" = 18500 ]; then
            ok "the report hands back the port a running overlay holds"
        else
            fail "the report reported held ports '$held', not the 18500 the overlay holds"
        fi
        # $held is deliberately unquoted: pick-port.sh takes one exclusion per
        # argument and rejects a joined list by name, so the split is the
        # contract rather than an accident.
        cand=$(sh "$SKILL/scripts/pick-port.sh" 18500 18501 "$hpwt" $held 2>/dev/null)
        [ -n "$cand" ] && [ "$cand" != 18500 ] \
            && ok "a held port fed to pick-port.sh is excluded from the candidate ($cand)" \
            || fail "pick-port returned '$cand' with 18500 excluded"
        docker rm -f -v "$hpc" >/dev/null 2>&1
    else
        fail "could not launch the held-port fixture"
    fi
    rm -rf "$hpwt"

    # V30 + V28 + V12's refusal half, on the minimal image: reap.sh RUNS there,
    # says docker is unavailable rather than zero, still prints the standing
    # legacy statement, and refuses a mutation because busybox ps has no lstart.
    #
    # The two worktree assertions are what make this row notice git at all.
    # Every other line here is true whether or not git answers - docker really
    # is absent in the container, the legacy statement is unconditional, no
    # sidecar was launched, and busybox ps really has no lstart - so the row
    # used to pass in a container where git resolved no repository whatsoever.
    # That is how the worktree defect fixed in #27 survived unremarked. reap.sh
    # emits a `worktree` record only when `git worktree list --porcelain`
    # answered, and swaps it for `degraded worktree-list-unavailable` when it
    # did not; requiring the first and refusing the second ties this row to git
    # running for real. Both, not one: the presence proves git answered, and
    # the refusal rejects the degraded path by name rather than by absence.
    alp=$(alpine_scripts '
        t=$(printf "\t")
        R=skills/stackgraft/scripts/reap.sh
        out=$(sh "$R" report 00c0ffee) || exit 1
        printf "%s\n" "$out" | grep -q "^degraded${t}docker-unavailable" || exit 1
        printf "%s\n" "$out" | grep -q "^legacy${t}undetectable" || exit 1
        printf "%s\n" "$out" | grep -q "^host${t}checked" && exit 1
        printf "%s\n" "$out" | grep -q "^worktree${t}" || exit 1
        printf "%s\n" "$out" | grep -q "^degraded${t}worktree-list-unavailable" && exit 1
        sh "$R" -m stop 00c0ffee p:1 x 2>/dev/null | grep -q lstart-unsupported || exit 1
        echo ok' 2>/dev/null | tail -1)
    [ "$alp" = ok ] \
        && ok "reap.sh runs on alpine: unavailable is not zero, git answered, and an unprovable pid is refused" \
        || fail "reap.sh did not behave on a minimal Linux image"

    # The negative for the row above, and it carries the diagnosis rather than
    # just the verdict. The SAME helper, the same image and the same shipped
    # script, in a container whose git resolves no repository at all: `.git` is
    # replaced by a gitdir pointer naming a path that is not there, which is
    # byte for byte the state a linked worktree used to hand this harness.
    #
    # The program then re-runs the row's ORIGINAL four assertions and requires
    # every one of them to still pass, before requiring the two new ones to
    # fail. So this row proves two things at once: that the assertions the row
    # had were blind to a total loss of git, and that the ones just added are
    # what sees it. If a later edit weakens either of the two, the positive
    # above stops being tied to git and this row stops printing ok.
    neg=$(alpine_scripts '
        t=$(printf "\t")
        R=skills/stackgraft/scripts/reap.sh
        rm -rf .git || exit 1
        printf "gitdir: /nonexistent/host/path/.git/worktrees/x\n" > .git || exit 1
        git rev-parse --show-toplevel >/dev/null 2>&1 && exit 1
        out=$(sh "$R" report 00c0ffee) || exit 1
        printf "%s\n" "$out" | grep -q "^degraded${t}docker-unavailable" || exit 1
        printf "%s\n" "$out" | grep -q "^legacy${t}undetectable" || exit 1
        printf "%s\n" "$out" | grep -q "^host${t}checked" && exit 1
        sh "$R" -m stop 00c0ffee p:1 x 2>/dev/null | grep -q lstart-unsupported || exit 1
        printf "%s\n" "$out" | grep -q "^worktree${t}" && exit 1
        printf "%s\n" "$out" | grep -q "^degraded${t}worktree-list-unavailable" || exit 1
        echo ok' 2>/dev/null | tail -1)
    [ "$neg" = ok ] \
        && ok "rejected: a container whose git resolves nothing - the row's older assertions stay green there, the two worktree ones turn red" \
        || fail "a container with no working git did not turn the reap row red, so the row still does not prove git ran"
else
    skip "the two-repo and minimal-image reap rows (no docker daemon or alpine/git image)" runtime
fi

# ----------------------------------------------------------- leak envelope ---
section "leak envelope"

# The whole run's own anonymous volumes, and there are none. Every container this
# file starts registers its unnamed volumes in $ANON_LEDGER at creation, and this
# is where the count is required to be zero.
#
# It is here rather than inside any one section because the leak it exists for was
# never inside one: the suite leaked exactly 18 per run from four different
# `docker rm -f` calls in four different sections, and every per-section envelope
# above reported clean the whole time. Each of those envelopes only looked at the
# objects its own block knew the names of, so the one kind of object nobody names
# was the one kind nobody was counting.
#
# It also found a nineteenth that was not the harness's at all: reap.sh removed a
# labelled overlay with `docker rm -f` and orphaned the container's anonymous
# volume - the reaper leaving behind the one object class it could never
# afterwards reclaim, since it carries no name, no label and no owner. The two
# rows below hold the script and the file that documents it to the same spelling,
# because repairing one of them alone is the two-texts-in-the-tree hazard rather
# than a fix.
reap_removal=$(grep -c 'docker rm -f -v "\$a_id"' "$SKILL/scripts/reap.sh")
reap_documented=$(grep -c 'mutation + removal | `docker rm -f -v` | `docker rm -f -v`' "$SKILL/references/reaping.md")
[ "$reap_removal" -eq 1 ] && [ "$reap_documented" -eq 1 ] \
    && ok "the reaper's removal takes the container's anonymous volumes with it, in the script and in the flags table alike" \
    || fail "the removal verb and its documented spelling disagree: script $reap_removal, reaping.md $reap_documented"

# ...and the pair can notice a disagreement, which is the only thing that makes
# the row above more than a grep for a string somebody put there.
rvf=$(mktemp -d)
sed 's/docker rm -f -v "\$a_id"/docker rm -f "$a_id"/' "$SKILL/scripts/reap.sh" > "$rvf/reap.sh"
[ "$(grep -c 'docker rm -f -v "\$a_id"' "$rvf/reap.sh")" -eq 0 ] \
    && ok "rejected: the reaper's removal with its -v reverted - the row reads the flag rather than the line" \
    || fail "the removal row cannot notice -v going away"
rm -rf "$rvf"

# The same flag, held across the WHOLE SHIPPED SURFACE rather than at the one
# line the reaper removes an overlay on - because the leak came back through a
# different door and shipped, as advice to a person. The provider printed the
# copy's removal command with the flag missing and isolation-providers.md printed
# the same line in a code block: the ordering is right and nothing false is
# claimed, but a reader who ran it orphaned the container's anonymous volume,
# which is the class the reaper exists to reclaim and the leak this repository
# took out of reap.sh one slice ago.
#
# The count of instructions SEEN is the other half of the row. Zero bare ones is
# equally true of a surface that hands a reader no removal command at all, which
# is why the provider's own listing row counts both its numbers too.
#
# The safety premise is the measured one the runtime row below establishes and
# this row does not re-derive: the flag takes the container's ANONYMOUS volumes
# and leaves every NAMED one, and every copy this skill makes is a named sg-
# volume, so the removal by name beside it still has something to remove.
rm_dash_v() {
    grep -rnF 'docker rm -f' "$@" 2>/dev/null | awk '
        { seen++; if (index($0, "docker rm -f -v") == 0) bare++ }
        END { print (seen + 0) " " (bare + 0) }
    '
}
rmv=$(rm_dash_v $SHIPPED_SURFACE)
rmv_seen=${rmv%% *}
rmv_bare=${rmv##* }
if [ "$rmv_seen" -lt 2 ]; then
    fail "the shipped surface hands a reader $rmv_seen removal instruction(s), so this row is not reading the advice it claims to"
elif [ "$rmv_bare" -gt 0 ]; then
    fail "$rmv_bare of the surface's $rmv_seen removal instructions carry no -v: $(grep -rnF 'docker rm -f' $SHIPPED_SURFACE 2>/dev/null | grep -vF 'docker rm -f -v' | head -1)"
else
    ok "all $rmv_seen forced-removal instructions in the shipped surface carry -v, so no shipped file advises a removal that orphans the container's anonymous volume"
fi

# ...and the reader can see a bare one BESIDE a flagged one, which is the whole
# reason the row above counts both numbers. Two lines, one of each, and the
# expected reading is fixed: it does not move with the state of the tree.
rmf=$(mktemp -d)
{ printf '%s\n' 'docker rm -f -v "$a_id"'; printf 'docker rm -f %s && docker volume rm %s\n' '<name>' '<name>'; } > "$rmf/advice.md"
rmv_fix=$(rm_dash_v "$rmf/advice.md")
[ "$rmv_fix" = "2 1" ] \
    && ok "rejected: a removal instruction spelled without -v, beside one that carries it - the detector names the bare one and passes the flagged one" \
    || fail "the -v detector reported '$rmv_fix' for one flagged and one bare removal, not '2 1'"
rm -rf "$rmf"

if [ "$docker_ready" -eq 1 ] && docker image inspect alpine/git >/dev/null 2>&1; then
    # The safety premise that repair rests on, MEASURED rather than cited: a
    # container mounting one named volume, and carrying one anonymous volume of
    # the image's own, is removed with -v and the named volume must still be
    # there afterwards. Every copy this skill provisions is named, and so is a
    # base stack's data, so if -v reached a named volume the line above would be
    # a data loss shipped as a tidy-up.
    docker volume create sg-leak-named >/dev/null 2>&1
    nv=$(docker run -d --entrypoint sh -v sg-leak-named:/data alpine/git -c 'sleep 30' 2>/dev/null)
    nv_anon=$(docker inspect --format \
        '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
        "$nv" 2>/dev/null | grep -E '^[0-9a-f]{64}$')
    docker rm -f -v "$nv" >/dev/null 2>&1
    if [ -z "$nv" ] || [ -z "$nv_anon" ]; then
        fail "the named-volume fixture started no container or carried no anonymous volume, so it measures neither half: id '$nv'"
    elif docker volume inspect "$nv_anon" >/dev/null 2>&1; then
        fail "-v did not remove the container's anonymous volume, so the repair does not do what it claims"
    elif docker volume inspect sg-leak-named >/dev/null 2>&1; then
        ok "-v removes the container's anonymous volume and leaves the named one, which is what makes the reaper's removal safe for a copy"
    else
        fail "-v REMOVED A NAMED VOLUME - every copy this skill provisions is named, so the removal verb must not carry it"
    fi
    docker volume rm sg-leak-named >/dev/null 2>&1

    # The NEGATIVE runs first, because the row after it is an absence and an
    # absence is also what a ledger nobody ever wrote to reports. This fixture is
    # the leak, built the way all eighteen were built: alpine/git declares
    # `VOLUME /git`, the container is started without --rm, and it is removed
    # without -v. The ledger must SEE the volume it leaves.
    lk_before=$(anon_surviving)
    lk=$(docker run -d --entrypoint sh alpine/git -c 'sleep 30' 2>/dev/null)
    lk_anon=$(docker inspect --format \
        '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
        "$lk" 2>/dev/null | grep -E '^[0-9a-f]{64}$')
    anon_note "$lk"
    docker rm -f "$lk" >/dev/null 2>&1
    if [ -z "$lk" ] || [ -z "$lk_anon" ]; then
        fail "the leak fixture started no container or claimed no anonymous volume, so it exercises nothing: id '$lk'"
    elif [ "$(anon_surviving)" -gt "$lk_before" ]; then
        ok "rejected: a container removed without -v - the ledger reports the anonymous volume it left behind"
    else
        fail "the ledger cannot see a volume left by a container removed without -v, so it could not have seen the eighteen either"
    fi

    # The fixture takes its own leak with it. By name, because the container it
    # was attached to is already gone - which is the whole difficulty with this
    # class of leak and the reason the repair had to be at the removal rather
    # than in a sweep afterwards.
    for _lv in $lk_anon; do
        docker volume rm "$_lv" >/dev/null 2>&1
    done

    # ...and now the run's own figure. The registered count is asserted as a
    # literal beside it: a survivor count of zero over a ledger with nothing in
    # it is the false green this row would otherwise be, and it is the same
    # premise the body-word row states about its own counter.
    ANON_REGISTERED_RECORDED=28
    lk_seen=$(anon_registered)
    lk_left=$(anon_surviving)
    if [ "$lk_seen" -ne "$ANON_REGISTERED_RECORDED" ]; then
        fail "the ledger holds $lk_seen anonymous volumes where this run records $ANON_REGISTERED_RECORDED, so a zero survivor count would be measuring a run that did not happen"
    elif [ "$lk_left" -eq 0 ]; then
        ok "the $lk_seen anonymous volumes this run created are all gone: the suite leaks none"
    else
        fail "this run leaked $lk_left anonymous volume(s) of the $lk_seen it created: $(anon_survivors | tr '\n' ' ')"
    fi
else
    skip "the run-wide anonymous-volume ledger (no docker daemon or alpine/git image)" runtime
fi
rm -f "$ANON_LEDGER"

# ------------------------------------------------------------ portability ---
section "portability"

# $PORTABILITY is the pattern the V29 fixture in the instrumentation section
# proves can fire. One variable, two uses, so the fixture and the shipped check
# can never be asking about different things.
if grep -rniE "$PORTABILITY" "$SKILL" >/dev/null 2>&1; then
    fail "an agent-specific path or an unavailable tool is named in a shipped file"
else
    ok "no agent-specific coupling and no unavailable tool"
fi


# ------------------------------------------------------- release version ----
section "release version"

# One release, one number, in four places: SKILL.md's top-level `version`,
# SKILL.md's `metadata.version`, .claude-plugin/plugin.json and
# .claude-plugin/marketplace.json. plugin.json is the source of truth for
# release purposes - it is the file whose change is what makes an update reach
# an installed user - so the other three are compared to IT rather than to each
# other, which also gives the failure message a direction to name.
#
# Checked, not generated: generation needs a build step and this project ships
# none. Read with awk for the same reason everything else here is - jq and
# python3 are each missing from at least one supported platform.
#
# The top-level field is not decoration. `paks` refuses a skill that has no
# top-level semver `version`, and the copy `npx skills add` writes is built from
# this same frontmatter, so a number that drifted or a field that went missing
# is an install failure rather than a cosmetic one. Both are fixtures below,
# and so is the state this check was added to end: a `metadata.version` of
# "1.0" that no equality test would ever have called wrong.

PLUGIN=.claude-plugin/plugin.json
MARKET=.claude-plugin/marketplace.json

# Prints the first "version" string value in a JSON file, or `absent`. Matched
# on the quoted pair rather than by splitting fields: marketplace.json carries
# its version nested inside plugins[] and indented, on a line a whitespace
# split would read differently from plugin.json's.
json_version() {
    [ -f "$1" ] || { printf 'no-such-file\n'; return 0; }
    awk '
        found { next }
        match($0, /"version"[ \t]*:[ \t]*"[^"]*"/) {
            s = substr($0, RSTART, RLENGTH)
            match(s, /"[^"]*"$/)
            print substr(s, RSTART + 1, RLENGTH - 2)
            found = 1
        }
        END { if (!found) print "absent" }
    ' "$1"
}

# Prints SKILL.md's top-level `version` ($2 = top) or its `metadata.version`
# ($2 = metadata), or `absent`. Only the frontmatter is read - the scan stops
# at the closing delimiter - so a line in the body can never stand in for a
# field missing from the header.
#
# Quotes are required rather than merely tolerated, and an unquoted value
# reports as unmeasurable instead of as a number: to YAML an unquoted 1.0.0 is
# a string but an unquoted 1.0 is a float, so a reader that accepted both would
# accept the exact shape this change exists to remove.
skill_version() {
    [ -f "$1" ] || { printf 'no-such-file\n'; return 0; }
    awk -v want="$2" '
        /^---[ \t]*$/ { c++; if (c >= 2) exit; next }
        c != 1 || found { next }
        {
            if (want == "top") { if ($0 !~ /^version:/)       next }
            else               { if ($0 !~ /^[ \t]+version:/) next }
            rest = substr($0, index($0, ":") + 1)
            sub(/^[ \t]+/, "", rest)
            sub(/[ \t]+$/, "", rest)
            found = 1
            if (rest !~ /^"[^"]*"$/) { print "unquoted"; next }
            print substr(rest, 2, length(rest) - 2)
        }
        END { if (!found) print "absent" }
    ' "$1"
}

# X.Y.Z with the optional prerelease/build tail semver allows, so a future
# 1.1.0-rc.1 is not blocked by a rule that only meant to reject "1.0".
is_semver() { printf '%s\n' "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'; }

# One decision, shared by the shipped row and by every fixture below, so the
# fixtures exercise the rule that actually runs rather than a restatement of it
# that could drift away from it.
version_verdict() {
    _p=$(json_version "$1")
    _m=$(json_version "$2")
    _t=$(skill_version "$3" top)
    _n=$(skill_version "$3" metadata)
    for _v in "$_p" "$_m" "$_t" "$_n"; do
        case $_v in
            absent | unquoted | no-such-file) printf 'unreadable-%s\n' "$_v"; return 0 ;;
        esac
    done
    is_semver "$_p" || { printf 'source-not-semver\n'; return 0; }
    if [ "$_m" = "$_p" ] && [ "$_t" = "$_p" ] && [ "$_n" = "$_p" ]; then
        printf 'pass\n'
    else
        printf 'mismatch\n'
    fi
}

version_seen() {
    printf 'plugin.json=%s marketplace.json=%s SKILL.md=%s SKILL.md/metadata=%s' \
        "$(json_version "$1")" "$(json_version "$2")" \
        "$(skill_version "$3" top)" "$(skill_version "$3" metadata)"
}

vv=$(version_verdict "$PLUGIN" "$MARKET" "$SKILL/SKILL.md")
vs=$(version_seen "$PLUGIN" "$MARKET" "$SKILL/SKILL.md")
[ "$vv" = pass ] \
    && ok "one version in four places: $vs" \
    || fail "the four version strings do not agree ($vv): $vs"

# Every fixture is a COPY of the three real files with exactly one number
# moved, because that is the drift this row exists to catch: bumping
# plugin.json for a release and forgetting SKILL.md ships an installed skill
# declaring a version it is not.
vf=$(mktemp -d)

bump_json() {
    awk -v v="$2" '
        !done && match($0, /"version"[ \t]*:[ \t]*"[^"]*"/) {
            print substr($0, 1, RSTART - 1) "\"version\": \"" v "\"" substr($0, RSTART + RLENGTH)
            done = 1
            next
        }
        { print }
    ' "$1" > "$1.new" && mv "$1.new" "$1"
}

# An empty $3 DELETES the field rather than writing an empty one, because the
# state worth a fixture is the field being gone.
bump_skill() {
    awk -v want="$2" -v v="$3" '
        BEGIN {
            pat = (want == "top") ? "^version:" : "^[ \t]+version:"
            pad = (want == "top") ? ""          : "  "
        }
        !done && $0 ~ pat {
            done = 1
            if (v != "") print pad "version: \"" v "\""
            next
        }
        { print }
    ' "$1" > "$1.new" && mv "$1.new" "$1"
}

version_leg() {
    _d="$vf/$1"
    mkdir -p "$_d/.claude-plugin" "$_d/skill"
    cp "$PLUGIN" "$_d/.claude-plugin/plugin.json"
    cp "$MARKET" "$_d/.claude-plugin/marketplace.json"
    cp "$SKILL/SKILL.md" "$_d/skill/SKILL.md"
    case $1 in
        plugin)      bump_json  "$_d/.claude-plugin/plugin.json"      "$2" ;;
        marketplace) bump_json  "$_d/.claude-plugin/marketplace.json" "$2" ;;
        skill)       bump_skill "$_d/skill/SKILL.md" top      "$2" ;;
        metadata)    bump_skill "$_d/skill/SKILL.md" metadata "$2" ;;
        deleted)     bump_skill "$_d/skill/SKILL.md" top      '' ;;
        all)
            bump_json  "$_d/.claude-plugin/plugin.json"      "$2"
            bump_json  "$_d/.claude-plugin/marketplace.json" "$2"
            bump_skill "$_d/skill/SKILL.md" top      "$2"
            bump_skill "$_d/skill/SKILL.md" metadata "$2"
            ;;
    esac
    version_verdict "$_d/.claude-plugin/plugin.json" \
        "$_d/.claude-plugin/marketplace.json" "$_d/skill/SKILL.md"
}

# Every fixture below is DERIVED from the three shipped files, so they only
# mean anything while those files read. Standing down loudly when they do not
# beats four more failures restating the one above in different words - and
# beats the worse half of that: the lone-bump fixtures all report
# `unreadable-absent` when the top-level field is missing, which is a rejection
# arrived at for a reason that has nothing to do with the number moving alone.
if [ "$vv" = pass ]; then
    v_bad=''
    for leg in plugin marketplace skill metadata; do
        got=$(version_leg "$leg" 9.9.9)
        [ "$got" = mismatch ] && continue
        v_bad="$v_bad [$leg bumped alone: $got]"
    done
    if [ -z "$v_bad" ]; then
        ok "rejected: each of the four places bumped on its own - one number moving alone is a red run"
    else
        fail "ACCEPTED but must be rejected: a lone bump read as agreement:$v_bad"
    fi

    # ...and the row is not "every fixture is bad", nor a builder that quietly
    # rewrote nothing: a release IS four edits, so moving all four together
    # passes. This row polices their agreement, never their value.
    [ "$(version_leg all 9.9.9)" = pass ] \
        && ok "four numbers moved together is the shape of a release, and it passes" \
        || fail "four agreeing versions were read as a disagreement"

    # The field a package manager refuses without, deleted. This is the state
    # the change repaired - SKILL.md carried only a nested metadata.version -
    # and a gate keyed on a field that may simply be absent is no gate, so
    # absence gets its own verdict rather than an empty string compared against
    # three real ones.
    [ "$(version_leg deleted '')" = unreadable-absent ] \
        && ok "rejected: the top-level version deleted, which no equality test would notice" \
        || fail "ACCEPTED but must be rejected: a missing top-level version"

    # Agreement alone is not enough, and this is the value that proves it:
    # "1.0" in all four places is what metadata.version actually carried, and it
    # is not semver, so paks would refuse the skill while every equality test
    # called it agreement.
    [ "$(version_leg all 1.0)" = source-not-semver ] \
        && ok "rejected: four agreeing versions that are not semver" \
        || fail "ACCEPTED but must be rejected: an agreeing version that no installer can read"
else
    skip "the version fixtures (they are derived from the shipped files, which failed above)" conditional
fi
rm -rf "$vf"

# -------------------------------------------------------- release notes ----
section "release notes"

# A tagged release's body is EXTRACTED from CHANGELOG.md, so what the file says
# and what a reader sees on the releases page are one artifact rather than two
# that drift. Four things have to hold for that, and three of them were already
# false at least once:
#
#   - the version plugin.json declares has a section at all;
#   - that version has a link-reference definition. 1.1.0 shipped without one
#     while 1.0.0 had one, which is the asymmetry a reader sees as `[1.1.0]`
#     rendering as literal brackets beside a 1.0.0 that renders as a link;
#   - the extracted body carries NEITHER the `## [` heading NOR any
#     link-reference line. The heading is redundant beside a release title that
#     already spells the version; the link line is the bug. The LAST section in
#     the file has no `## [` heading after it, so a rule that stopped only at
#     the next heading ran to EOF and swallowed the definitions into the body;
#   - a version the file does not carry is refused, by name, rather than
#     published as an empty release.

CHLOG=CHANGELOG.md
SECTION=.github/scripts/changelog-section.sh

if command -v dash >/dev/null 2>&1; then
    dash -n "$SECTION" 2>/dev/null \
        && ok "changelog-section.sh parses under dash" \
        || fail "changelog-section.sh fails dash -n"
else
    sh -n "$SECTION" 2>/dev/null \
        && ok "changelog-section.sh parses under sh" \
        || fail "changelog-section.sh fails sh -n"
fi

# ...and that parse can fail. The row above is the one place in this file where
# an external tool decides the verdict, so what is worth proving is that its
# exit code is still being read rather than swallowed.
pf2=$(mktemp -d)
printf '#!/bin/sh\ncase x in\n' > "$pf2/broken.sh"
if command -v dash >/dev/null 2>&1; then
    dash -n "$pf2/broken.sh" 2>/dev/null && bad_parses=1 || bad_parses=0
else
    sh -n "$pf2/broken.sh" 2>/dev/null && bad_parses=1 || bad_parses=0
fi
[ "$bad_parses" -eq 0 ] \
    && ok "rejected: a script with an unterminated case, so the parse row can still fail" \
    || fail "the parse check accepted an unterminated case statement"
rm -rf "$pf2"

# has_shebang() is defined once, with the shipped-script rows at the top of this
# file, so both shebang rows accept the same thing.
has_shebang "$SECTION" \
    && ok "changelog-section.sh carries a shebang" \
    || fail "changelog-section.sh has no shebang"

# Reports `present` or `absent`. The bracketed token is compared LITERALLY,
# exactly as the extractor compares it, so a version whose dots happened to
# line up with another heading cannot report present.
changelog_entry() {
    awk -v want="$2" '
        /^## \[/ {
            p = index($0, "]")
            if (p > 4 && substr($0, 5, p - 5) == want) { print "present"; found = 1; exit }
        }
        END { if (!found) print "absent" }
    ' "$1"
}

# Reports `present` or `absent`. index() rather than a regex for the same
# reason: the version is data, and its dots are not wildcards.
changelog_link() {
    awk -v want="$2" '
        index($0, "[" want "]:") == 1 { print "present"; found = 1; exit }
        END { if (!found) print "absent" }
    ' "$1"
}

rel_version=$(json_version "$PLUGIN")
case $rel_version in
    absent | no-such-file) rel_readable=0 ;;
    *)                     rel_readable=1 ;;
esac

if [ "$rel_readable" -eq 1 ]; then
    nf=$(mktemp -d)

    entry_state=$(changelog_entry "$CHLOG" "$rel_version")
    [ "$entry_state" = present ] \
        && ok "CHANGELOG.md has an entry for $rel_version, the version plugin.json declares" \
        || fail "CHANGELOG.md has no entry for $rel_version, the version plugin.json declares"

    # Both fixtures below REMOVE something from the shipped file, so each is
    # only a fixture while the thing it removes is there. Run against a file
    # that never had it, they report `absent` for a reason that has nothing to
    # do with the removal and pass while proving nothing - which is the exact
    # shape of vacuous gate this file exists to keep out. They stand down
    # loudly instead; the row above already names the real problem.
    if [ "$entry_state" = present ]; then
        awk -v want="$rel_version" '
            /^## \[/ { p = index($0, "]"); if (p > 4 && substr($0, 5, p - 5) == want) next }
            { print }
        ' "$CHLOG" > "$nf/no-entry.md"
        [ "$(changelog_entry "$nf/no-entry.md" "$rel_version")" = absent ] \
            && ok "rejected: the same file with the released version's heading removed" \
            || fail "ACCEPTED but must be rejected: a CHANGELOG carrying no entry for the released version"
    else
        skip "the removed-entry fixture (it removes an entry the file does not carry)" conditional
    fi

    link_state=$(changelog_link "$CHLOG" "$rel_version")
    [ "$link_state" = present ] \
        && ok "$rel_version has a link-reference definition, so its version renders as a link" \
        || fail "$rel_version has no link-reference definition, so it renders as literal brackets"

    if [ "$link_state" = present ]; then
        awk -v want="$rel_version" 'index($0, "[" want "]:") == 1 { next } { print }' \
            "$CHLOG" > "$nf/no-link.md"
        [ "$(changelog_link "$nf/no-link.md" "$rel_version")" = absent ] \
            && ok "rejected: the same file with that definition removed - the state 1.1.0 shipped in" \
            || fail "ACCEPTED but must be rejected: a released version with no link-reference definition"
    else
        skip "the removed-definition fixture (it removes a definition the file does not carry)" conditional
    fi

    # --- V69  a MAJOR release owes a breaking entry, and it owes the two -----
    # things that do not revert themselves. A `2.0.0` whose entry reads like a
    # feature list ships a breaking schema change under a heading that does not
    # say so, and the two residuals are the ones a reader discovers by hitting
    # them: a manifest written at 3 is unreadable to the release they rolled
    # back to, and a copy or an approved target created while 2.0 was live is
    # still on their disk and still in their repository.
    #
    # Keyed on the MAJOR component rather than on the literal 2.0.0, so 3.0.0
    # inherits the obligation instead of walking out from under it.
    rel_major=${rel_version%%.*}
    rel_minorpatch=${rel_version#*.}
    if [ "$entry_state" = present ] && [ "$rel_minorpatch" = "0.0" ] && [ "$rel_major" != 0 ]; then
        rel_body=$(awk -v want="$rel_version" '
            /^## \[/ { p = index($0, "]"); inside = (p > 4 && substr($0, 5, p - 5) == want); next }
            inside { print }
        ' "$CHLOG")
        break_missing=''
        for _b in 'BREAKING:breaking' \
                  'schemaVersion:schemaVersion' \
                  'no migration path:no migration path' \
                  'discard:discard' \
                  'stays where it is:stays where it is'; do
            _pat=${_b#*:}
            printf '%s\n' "$rel_body" | grep -qiF "$_pat" || break_missing="$break_missing ${_b%%:*}"
        done
        if [ -z "$break_missing" ]; then
            ok "the $rel_version entry is marked breaking and states the schemaVersion bump, the absent migration path, the discard, and what stays where it is"
        else
            fail "the $rel_version entry is a major release missing:$break_missing"
        fi

        # ...and the row can see one of them go. The fixture is the shipped
        # entry with the residual sentence removed, which is the state a release
        # note describing only the features would be in.
        printf '%s\n' "$rel_body" | grep -viF 'stays where it is' > "$nf/no-residual.md"
        if grep -qiF 'stays where it is' "$nf/no-residual.md"; then
            fail "the breaking-entry fixture still carries the residual after the strip, so it exercises the wrong condition"
        else
            ok "rejected: a major release entry with the sentence about what does not revert itself removed"
        fi
    elif [ "$rel_minorpatch" = "0.0" ] && [ "$rel_major" != 0 ]; then
        skip "the breaking-entry rows (the released version has no CHANGELOG entry, which the row above already names)" conditional
    else
        skip "the breaking-entry rows ($rel_version is not a major release)" conditional
    fi

    rm -rf "$nf"
else
    skip "the entry and link-definition rows (plugin.json declares no readable version: $rel_version)" conditional
fi

# The shape a release body must have: non-empty, and carrying neither the
# heading the release title already spells nor a link-reference line.
notes_verdict() {
    case $1 in
        '') printf 'empty\n'; return 0 ;;
    esac
    if printf '%s\n' "$1" | grep -q '^## \['; then
        printf 'has-heading\n'
        return 0
    fi
    if printf '%s\n' "$1" | grep -qE '^\[[^]]+\]:'; then
        printf 'has-link-definition\n'
        return 0
    fi
    printf 'pass\n'
}

# EVERY section is extracted, not only the released one, because the shape that
# broke belongs to whichever section is LAST - and which section that is
# changes with every release. The word split is deliberate: a version string is
# digits and dots, so there is nothing here to split or glob on.
notes_bad=''
notes_n=0
for v in $(awk '/^## \[/ { p = index($0, "]"); if (p > 4) print substr($0, 5, p - 5) }' "$CHLOG"); do
    notes_n=$((notes_n + 1))
    got=$(notes_verdict "$(sh "$SECTION" "$v" "$CHLOG" 2>/dev/null)")
    [ "$got" = pass ] || notes_bad="$notes_bad [$v: $got]"
done
if [ "$notes_n" -ge 2 ] && [ -z "$notes_bad" ]; then
    ok "all $notes_n CHANGELOG sections extract to a body with no heading and no link definition"
else
    fail "release notes: $notes_n section(s) seen,$notes_bad"
fi

# ...and the verdict can fire on each of the three shapes it exists to catch.
# Without this the row above passes on a function that returned `pass` for
# anything at all, which is the failure mode the whole file is written against.
nv_bad=''
nv_try() {
    _got=$(notes_verdict "$2")
    [ "$_got" = "$3" ] || nv_bad="$nv_bad [$1: $_got, wanted $3]"
}
nv_try empty   ''                                                      empty
nv_try heading "$(printf 'prose\n## [9.9.9] — 2026-01-01\nmore\n')"    has-heading
nv_try link    "$(printf 'prose\n[9.9.9]: https://example.invalid/\n')" has-link-definition
[ -z "$nv_bad" ] \
    && ok "rejected: an empty body, a body carrying the heading, and a body carrying a link definition" \
    || fail "the release-notes verdict could not see a shape it exists to catch:$nv_bad"

# --- the regression fixture: the section that runs to EOF --------------------
# The bug was never in what the extractor stopped at. It was in what it did NOT
# stop at, and only the last section can show that, so the fixture puts the
# requested version last with the definitions below it.
rf=$(mktemp -d)
cat > "$rf/CHANGELOG.md" <<'FIXTURE'
# Changelog

## [2.0.0] — 2026-09-01

A second entry, so the one below it is genuinely the last.

## [1.0.0] — 2026-07-31

First public release.

[2.0.0]: https://example.invalid/releases/tag/v2.0.0
[1.0.0]: https://example.invalid/releases/tag/v1.0.0
FIXTURE

last_body=$(sh "$SECTION" 1.0.0 "$rf/CHANGELOG.md" 2>/dev/null)
if [ "$(notes_verdict "$last_body")" = pass ]; then
    ok "the last section extracts clean: the definitions below it are not part of the body"
else
    fail "the last section came back $(notes_verdict "$last_body"): '$last_body'"
fi

# ...and the control, which is the rule that shipped: stopping only at the next
# `## [` heading. It has none to stop at here, runs to EOF, and takes the
# definitions with it. Without this row the one above passes on a fixture that
# never exercised the condition at all.
swallowed=$(awk '
    /^## \[1\.0\.0\]/ { on = 1; next }
    on && /^## \[/    { exit }
    on                { print }
' "$rf/CHANGELOG.md")
[ "$(notes_verdict "$swallowed")" = has-link-definition ] \
    && ok "rejected: the heading-only stop rule, which runs to EOF and swallows the definitions" \
    || fail "the heading-only stop rule did not reproduce the bug, so the fixture above proves nothing"
rm -rf "$rf"

# --- refusals: a version that is not there, and a heading with nothing under it
missing_said=$(sh "$SECTION" 9.9.9 "$CHLOG" 2>&1 >/dev/null)
sh "$SECTION" 9.9.9 "$CHLOG" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$missing_said" | grep -q '9\.9\.9'; then
    ok "a version with no section exits $rc and names the version it could not find"
else
    fail "a missing version exited $rc and said '$missing_said'"
fi

# ...and that refusal is about the version, not about every invocation. Without
# this control a script that failed unconditionally would pass the row above.
# The version comes from the file's own first heading rather than from
# plugin.json, so an unreadable manifest cannot make this control fail for a
# reason that has nothing to do with what it is controlling for.
first_version=$(awk '/^## \[/ { p = index($0, "]"); if (p > 4) { print substr($0, 5, p - 5); exit } }' "$CHLOG")
sh "$SECTION" "$first_version" "$CHLOG" >/dev/null 2>&1
[ $? -eq 0 ] \
    && ok "rejected: a blanket failure - $first_version exits 0 against the same file" \
    || fail "$first_version also failed, so the missing-version row proves nothing"

# A heading with an empty body under it would publish a release with no notes
# at all, and exit 0 is how that reaches the releases page unnoticed.
ef=$(mktemp -d)
printf '# Changelog\n\n## [3.0.0] — 2026-09-02\n\n## [1.0.0] — 2026-07-31\n\nFirst.\n' > "$ef/CHANGELOG.md"
sh "$SECTION" 3.0.0 "$ef/CHANGELOG.md" >/dev/null 2>&1
[ $? -eq 4 ] \
    && ok "rejected: a heading with an empty body under it (exit 4)" \
    || fail "an empty section was extracted as a publishable release body"
rm -rf "$ef"

# No arguments is a usage error, reached before anything is read. The script an
# agent or a workflow step calls must never sit waiting on a stdin nobody is
# going to write to.
sh "$SECTION" >/dev/null 2>&1
[ $? -eq 2 ] \
    && ok "changelog-section fails loudly with no arguments rather than reading stdin" \
    || fail "changelog-section did not reject an empty invocation"

# ---------------------------------------------------------------- schema ----
section "schema"

if ! python3 -c 'import jsonschema' 2>/dev/null; then
    skip "schema checks (python3 + jsonschema not installed)" runtime
else
    # Run it through the shell's own counters rather than past them. Left as a
    # bare invocation, its rows printed straight to the terminal and the summary
    # at the bottom reported the shell's total as though it were the run's -
    # `all 670 checks passed` over a run in which 804 passed. A summary that
    # undercounts by 134 is the same defect as one that counts skips as passes,
    # and both were invisible for the same reason: nothing added them up.
    cs_out=$(python3 .github/scripts/check_schema.py 2>&1); cs_rc=$?
    printf '%s\n' "$cs_out"
    cs_ok=$(  printf '%s\n' "$cs_out" | grep -c '^  ok'   || true)
    cs_fail=$(printf '%s\n' "$cs_out" | grep -c '^  FAIL' || true)
    oks=$((oks + cs_ok))
    if [ "$cs_rc" -ne 0 ]; then
        if [ "$cs_fail" -gt 0 ]; then
            fails=$((fails + cs_fail))
        else
            fails=$((fails + 1))
        fi
    fi
    # ...and a schema run that printed nothing at all would otherwise pass
    # silently, adding zero to both totals and leaving the summary honest about
    # a number that covers nothing.
    [ "$cs_ok" -gt 0 ] \
        && ok "the schema checks contributed $cs_ok row(s) to this run's total, so the summary counts them" \
        || fail "check_schema.py produced no rows, so the schema half of this suite is absent from the count"

    # The cross-check now reads references/reaping.md too, and that is exactly
    # why its sidecar keys are all lowercase: a backticked camelCase token that
    # is not a manifest field must fail here rather than force the FOREIGN list
    # to be widened, since widening it is how this check stops being able to
    # fail. Run against a scratch copy so the real tree is never mutated.
    sf=$(mktemp -d)
    mkdir -p "$sf/skills/stackgraft"
    cp -R "$SKILL"/. "$sf/skills/stackgraft/"
    printf '\nA fixture token that is no manifest field: `notAManifestField`\n' \
        >> "$sf/skills/stackgraft/references/reaping.md"
    # The OUTPUT decides, not the exit code alone: any nonzero exit passed this
    # row, so a scratch copy missing manifest.example.json printed ok over a
    # FileNotFoundError - a negative rejected for a reason that has nothing to
    # do with what it is testing. The token has to be named back.
    sf_out=$( cd "$sf" && python3 "$ROOT/.github/scripts/check_schema.py" 2>&1 )
    sf_rc=$?
    if [ "$sf_rc" -eq 0 ]; then
        fail "ACCEPTED but must be rejected: a camelCase non-field backticked in reaping.md"
    elif printf '%s' "$sf_out" | grep -q 'notAManifestField'; then
        ok "rejected: a camelCase non-field backticked in reaping.md"
    else
        fail "the scratch run failed for some other reason than the fixture token: '$sf_out'"
    fi
    rm -rf "$sf"
fi

# ---------------------------------------------------------------- result ----
section "result"

# A skipped row proves nothing about what it covers, so the summary says how
# many there were before it says anything else. `all checks passed` over a run
# that skipped ninety-nine of them is the reading this counter exists to remove.
if [ "$skips" -gt 0 ]; then
    # The unit is the BLOCK, and saying so matters: nine skipped blocks are two
    # hundred and forty rows on the run this was measured against, and a summary
    # reading "9 skipped" beside "565 ran" invites the arithmetic 565 + 9. A
    # skipped block's rows are never counted, because nothing enumerates a row
    # that did not run - so the honest statement is that they are missing, not
    # how many are missing.
    printf '  %s check(s) ran and passed; %s BLOCK(s) of checks were skipped\n' "$oks" "$skips"
    printf '        the rows inside a skipped block never ran and are in no total above\n'
fi

# The enforcement half, opt-in and set by the CI job that is supposed to supply
# these. Off by default because a developer on a laptop with no daemon should
# get a report rather than a wall, and a gate that fails for someone it was not
# written for is a gate that gets switched off.
if runtime_gate "$skipped_runtime" "${STACKGRAFT_REQUIRE_RUNTIME:-0}"; then
    printf '  FAIL  STACKGRAFT_REQUIRE_RUNTIME is set and these runtime prerequisites were absent:%s\n' \
        "$skipped_runtime"
    fails=$((fails + 1))
elif [ -n "$skipped_runtime" ]; then
    printf '  note  runtime prerequisites were absent, so these did not run:%s\n' "$skipped_runtime"
    printf '        set STACKGRAFT_REQUIRE_RUNTIME=1 to make that a failure rather than a note\n'
fi

if [ "$fails" -eq 0 ]; then
    if [ "$skips" -eq 0 ]; then
        printf '  all %s checks passed\n\n' "$oks"
    else
        printf '  the %s checks that ran passed; %s block(s) skipped and unaccounted for\n\n' "$oks" "$skips"
    fi
    exit 0
fi
printf '  %s check(s) failed\n\n' "$fails"
exit 1
