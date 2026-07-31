#!/bin/sh
# verify.sh - every check this project makes, run for real.
#
# usage:  sh .github/scripts/verify.sh
# exit:   0 all checks passed  ·  1 at least one failed
#
# Two rules this file enforces on itself:
#   - a check that cannot fail is not a check. Every assertion has a matching
#     negative fixture that must be REJECTED, so a validator that silently
#     stopped validating shows up as a failure rather than a pass.
#   - the minimal instance the schema accepts is the one worth tracing. Safety
#     holes live in the smallest legal input, not the realistic one.

set -u
SKILL=skills/stackgraft
fails=0

ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

section() { printf '\n%s\n' "$1"; }

# ---------------------------------------------------------------- shell -----
section "scripts"

for f in "$SKILL"/scripts/*.sh; do
    name=$(basename "$f")
    if command -v dash >/dev/null 2>&1; then
        dash -n "$f" 2>/dev/null && ok "$name parses under dash" || fail "$name fails dash -n"
    else
        sh -n "$f" 2>/dev/null && ok "$name parses under sh" || fail "$name fails sh -n"
    fi
    head -1 "$f" | grep -q '^#!/bin/sh' && ok "$name carries a shebang" || fail "$name has no shebang"
done

wt=$(mktemp -d)

port=$(sh "$SKILL/scripts/pick-port.sh" 18000 18999 "$wt" 2>/dev/null)
case $port in
    1[8-9][0-9][0-9][0-9]) ok "pick-port emits a candidate in range ($port)" ;;
    *)                     fail "pick-port emitted '$port'" ;;
esac

a=$(sh "$SKILL/scripts/pick-port.sh" 18000 18999 "$wt" 2>/dev/null)
b=$(sh "$SKILL/scripts/pick-port.sh" 18000 18999 "$wt/" 2>/dev/null)
[ "$a" = "$b" ] && ok "pick-port is stable across path spellings" || fail "pick-port gave $a then $b for one worktree"

excl=$(sh "$SKILL/scripts/pick-port.sh" 18000 18999 "$wt" "$a" 2>/dev/null)
[ "$excl" != "$a" ] && ok "pick-port honours an exclusion" || fail "pick-port returned an excluded port"

sh "$SKILL/scripts/pick-port.sh" 18000 18000 "$wt" 18000 >/dev/null 2>&1
[ $? -eq 3 ] && ok "pick-port exits 3 when the range is exhausted" || fail "pick-port did not signal exhaustion"

sh "$SKILL/scripts/pick-port.sh" 18000 18999 "$wt" "3000,5173" >/dev/null 2>&1
[ $? -eq 2 ] && ok "pick-port rejects a comma-joined exclusion list" || fail "pick-port accepted a comma list"

sh "$SKILL/scripts/pick-port.sh" 18000 18999 18500 >/dev/null 2>&1
[ $? -eq 2 ] && ok "pick-port rejects a port in the worktree slot" || fail "pick-port swallowed an exclusion as the worktree"

lines=$(printf 'README.md\nLICENSE' | sh "$SKILL/scripts/fingerprint.sh" - 2>/dev/null | wc -l | tr -d ' ')
[ "$lines" = "2" ] && ok "fingerprint keeps a final unterminated line" || fail "fingerprint emitted $lines lines for 2 paths"

miss=$(sh "$SKILL/scripts/fingerprint.sh" no/such/file.txt 2>/dev/null | cut -f1)
[ "$miss" = "-" ] && ok "fingerprint reports a missing path as drift" || fail "fingerprint gave '$miss' for a missing path"

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
    if [ "$rc" -eq 3 ] && [ "$before" = "$after" ] && printf '%s' "$msg" | grep -q "$livepid"; then
        ok "a provably live holder is never stolen from (exit 3, bytes unchanged, pid named)"
    else
        fail "live-holder lock: exit $rc, bytes $before -> $after, said '$msg'"
    fi
else
    printf '  skip  live-holder refusal (this host has no ps -o lstart=)\n'
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
if [ "$rc" -eq 3 ] && [ "$before" = "$after" ]; then
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
d="$lockdir/v10-KILL"
printf 'v10\n' > "$d"
fp=$(git hash-object --stdin < "$d")
sh "$LOCK" "$d" "$lockdir/payload" "$fp" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ ! -d "$d.lock" ]; then
    ok "the next writer reclaims the lock a killed holder left behind"
else
    fail "the lock a killed holder left wedged the next writer (exit $rc)"
fi
rm -rf "$lockdir"

# ---------------------------------------------------------------- body ------
section "skill body"

words=$(awk 'f{n+=NF} /^---$/{c++; if(c==2) f=1} END{print n}' "$SKILL/SKILL.md")
[ "$words" -le 500 ] && ok "body is $words words (ceiling 500)" || fail "body is $words words, over the 500 ceiling"

compat=$(awk -F'"' '/^compatibility:/{print length($2)}' "$SKILL/SKILL.md")
[ "${compat:-0}" -lt 500 ] && ok "compatibility is $compat characters (cap 500)" || fail "compatibility is $compat characters"

body=$(awk 'f; /^---$/{c++; if(c==2) f=1}' "$SKILL/SKILL.md")
for term in REUSE ISOLATE; do
    printf '%s' "$body" | grep -q "$term" \
        && fail "body contains the permitting term $term" \
        || ok "body states no $term"
done

for p in $(grep -o '`\(references\|assets\|scripts\)/[a-z.-]*`' "$SKILL/SKILL.md" | tr -d '`' | sort -u); do
    [ -e "$SKILL/$p" ] && ok "link resolves: $p" || fail "link is broken: $p"
done

# ------------------------------------------------------------ portability ---
section "portability"

if grep -rniE '~/\.claude|codegraph|\bpython3\b|\bjq\b|sha256sum|AppData' "$SKILL" >/dev/null 2>&1; then
    fail "an agent-specific path or an unavailable tool is named in a shipped file"
else
    ok "no agent-specific coupling and no unavailable tool"
fi

# ---------------------------------------------------------------- schema ----
section "schema"

if ! python3 -c 'import jsonschema' 2>/dev/null; then
    printf '  skip  schema checks (python3 + jsonschema not installed)\n'
else
    python3 .github/scripts/check_schema.py || fails=$((fails + 1))
fi

# ---------------------------------------------------------------- result ----
section "result"

if [ "$fails" -eq 0 ]; then
    printf '  all checks passed\n\n'
    exit 0
fi
printf '  %s check(s) failed\n\n' "$fails"
exit 1
