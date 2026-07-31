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
ROOT=$(pwd)
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
# basenames) nor named anywhere in what the run said ($3).
unreported_debris() {
    ( CDPATH= cd -- "$1" && find . -maxdepth 1 ! -name . | sort ) | while read -r _p; do
        _n=${_p#./}
        case " $2 " in *" $_n "*) continue ;; esac
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
w1_left=$(unreported_debris "$w1" 'w1.json payload' "$(lock_said "$w1_msg")")
if [ "$rc" -eq 0 ] && [ -z "$w1_left" ] && grep -q 'w1-new' "$d"; then
    ok "an ordinary reclaim leaves nothing but the destination ($w1_before-> $w1_after)"
else
    fail "reclaim debris: exit $rc, before '$w1_before' after '$w1_after', unreported '$w1_left'"
fi

# ...and the enumeration can see a fourth path appear. Named after the one that
# really leaked, so a detector that stopped looking is caught by the same shape.
: > "$w1/w1.json.lock.stale.999"
[ -n "$(unreported_debris "$w1" 'w1.json payload' "$(lock_said "$w1_msg")")" ] \
    && ok "rejected: an aside left beside the destination and named nowhere" \
    || fail "the debris enumeration cannot notice a fourth path"
rm -rf "$w1"

# A reclaim whose deletion cannot complete: the aside survives, and reporting
# success over it is the worse half of the leak. Made deterministic with a
# subdirectory rm cannot empty - root ignores those permissions, so the row
# stands down loudly there instead of passing for the wrong reason.
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
    left=$(unreported_debris "$w1b" 'w1b.json payload' "$(lock_said "$msg")")
    chmod -R 700 "$w1b" 2>/dev/null
    if [ "$rc" -ne 0 ] && [ -z "$left" ] && [ "$before" = "$after" ]; then
        ok "a reclaim that cannot delete its aside fails loudly (exit $rc) and names what it left"
    else
        fail "unremovable aside: exit $rc, bytes $before -> $after, unreported '$left'"
    fi
    rm -rf "$w1b"
else
    printf '  skip  the unremovable-aside row (running as root, which ignores the mode)\n'
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

# The ceiling only means something if going over it is caught. Two fixtures:
# one merely over, and one that reproduces the ordering hazard - applying this
# change's ADDS before its CUTS puts the body at 530, so a commit made in that
# order is red at that commit even though both endpoints are legal.
bf=$(mktemp -d)
body_fixture() { cp "$SKILL/SKILL.md" "$1"; awk -v n="$2" 'BEGIN { while (i++ < n) printf "filler "; print "" }' >> "$1"; }

body_fixture "$bf/over.md" 38
[ "$(body_verdict "$bf/over.md")" = fail ] \
    && ok "rejected: a body of $(body_words "$bf/over.md") words, over the ceiling" \
    || fail "ACCEPTED but must be rejected: a body over 500 words"

body_fixture "$bf/adds-first.md" 67
[ "$(body_verdict "$bf/adds-first.md")" = fail ] \
    && ok "rejected: adds applied before cuts, $(body_words "$bf/adds-first.md") words" \
    || fail "ACCEPTED but must be rejected: the adds-before-cuts ordering"
rm -rf "$bf"

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

cf=$(mktemp -d)
cfx="$cf/SKILL.md"

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
    printf '  skip  the donor-cut fixture (it is derived from the shipped value, which failed above)\n'
fi
rm -rf "$cf"

body=$(awk 'f; /^---$/{c++; if(c==2) f=1}' "$SKILL/SKILL.md")
for term in REUSE ISOLATE; do
    printf '%s' "$body" | grep -q "$term" \
        && fail "body contains the permitting term $term" \
        || ok "body states no $term"
done

for p in $(grep -o '`\(references\|assets\|scripts\)/[a-z.-]*`' "$SKILL/SKILL.md" | tr -d '`' | sort -u); do
    [ -e "$SKILL/$p" ] && ok "link resolves: $p" || fail "link is broken: $p"
done

# ...and the loop can report a break. Note the pattern it matches: grepping for
# the literal string "references/" would miss it, because what the loop keys on
# is the backticked form.
link_unresolved() {
    _n=0
    for _p in $(grep -o '`\(references\|assets\|scripts\)/[a-z.-]*`' "$1" | tr -d '`' | sort -u); do
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
# taken out of §0, the cut length is taken out of §0, and the result is what
# the body's own `<repo-basename>-<hash8>.json` template gets built from. The
# length is read from the prose instead of hard-coded, because a hard-coded 8
# would supply the very step whose absence is the defect.
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

# Follows $1's §0 against the common dir $2 and prints what it yields. A file
# stating no truncation does not get 8 assumed for it: it gets the recipe as it
# actually reads, which is the whole digest - precisely what the shipped body
# produced, and precisely what this row has to be able to see.
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
        ok "the body's hash8 pointer resolves: §0 yields '$h8', eight lowercase hex" ;;
    *)
        fail "SKILL.md plus discovery.md §0 yields '${h8:-nothing}' (${#h8} chars), not eight lowercase hex" ;;
esac

# ...and the row goes red the moment the recipe loses that step. The fixture is
# the shipped file with its truncation paragraph deleted - which is the state
# that shipped, and the state every other check in this file reads as healthy.
hf=$(mktemp -d)
awk '!/first 8 characters/' "$DISCOVERY" > "$hf/discovery.md"
h8bad=$(hash8_derive "$hf/discovery.md" "$h8_common")
case ${h8bad:-} in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
        fail "ACCEPTED but must be rejected: §0 with no truncation still resolved to eight hex" ;;
    *)
        ok "rejected: §0 with the truncation removed - the pointer resolves to ${#h8bad} characters, not 8" ;;
esac
rm -rf "$hf"

# ------------------------------------------------- instrumentation ----------
section "instrumentation"

# --- V13  the probe's negative is what makes the probe a check ---------------
# The block under test is the SHIPPED one, lifted out of with-lock.sh between
# its sentinels, so this exercises the bytes that run rather than a restatement
# of them.
ph=$(mktemp -d)
{
    printf '#!/bin/sh\n'
    awk '/BEGIN lstart probe/ { on = 1; next } /END lstart probe/ { on = 0 } on { print }' "$LOCK"
    printf 'lstart_probe\nprintf "%%s\\n" "$lstart_supported"\n'
} > "$ph/probe.sh"

if [ -s "$ph/probe.sh" ] && grep -q lstart_probe "$ph/probe.sh"; then
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
pf=$(mktemp -d)
printf 'a fixture that names an unavailable tool: jq\n' > "$pf/fixture.md"
if grep -rniE '~/\.claude|codegraph|\bpython3\b|\bjq\b|sha256sum|AppData' "$pf" >/dev/null 2>&1; then
    ok "rejected: a file naming an unavailable tool, even in prose"
else
    fail "the portability grep cannot fail"
fi
rm -rf "$pf"

# --- V30  parsing is not running: a GNU-only flag parses fine everywhere -----
GNUISM='newermt|stat -c|readlink -f|--date='
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

# --- docker-dependent rows: skipped loudly, never quietly passed -------------
docker_ready=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker_ready=1
fi

if [ "$docker_ready" -eq 1 ]; then
    # V15: this is the premise the whole anchor mechanism rests on.
    docker compose run --help 2>&1 | grep -qE '^[[:space:]]*-l, --label' \
        && ok "docker compose run advertises -l/--label" \
        || fail "docker compose run does not advertise --label, which the anchor rests on"
    docker compose up --help 2>&1 | grep -qE '^[[:space:]]*-l, --label' \
        && fail "docker compose up advertises --label, so the up refusal has no ground" \
        || ok "rejected: docker compose up, which takes no label flag - the up refusal's ground"
else
    printf '  skip  compose label-flag rows (no docker daemon)\n'
fi

if [ "$docker_ready" -eq 1 ] && docker image inspect alpine/git >/dev/null 2>&1; then
    # V17: all five labels, read back, with a worktree path holding a space.
    h=deadbeef
    wt='/tmp/a path/wt'
    cid=$(docker run -d --rm --entrypoint sh \
        --label stackgraft.labels=1 --label "stackgraft.repo=$h" \
        --label "stackgraft.worktree=$wt" --label stackgraft.service=storefront \
        --label stackgraft.port=5174 alpine/git -c 'sleep 20' 2>/dev/null)
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
        [ "$(docker ps --filter "label=stackgraft.repo=$h" --quiet | wc -l | tr -d ' ')" = 1 ] \
            && ok "the hash8-filtered query finds it" \
            || fail "the hash8-filtered query did not find the labelled overlay"
        [ "$(docker ps --filter 'label=stackgraft.repo=0000none' --quiet | wc -l | tr -d ' ')" = 0 ] \
            && ok "rejected: a query scoped to another repository's hash8 returns nothing" \
            || fail "a foreign hash8 matched this repository's overlay"
        docker rm -f "$cid" >/dev/null 2>&1
    else
        fail "could not launch the labelled overlay fixture"
    fi

    # V30 positive: the scripts RUN on a minimal Linux image, not only parse.
    lin=$(docker run --rm --entrypoint sh -v "$ROOT":/w -w /w alpine/git -c '
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
        awk '/BEGIN lstart probe/ { on = 1; next } /END lstart probe/ { on = 0 } on { print }' "$LOCK"
        printf 'lstart_probe\nprintf "%%s\\n" "$lstart_supported"\n'
    } > "$pp/probe.sh"
    [ "$(docker run --rm --entrypoint sh -v "$pp":/probe alpine/git -c 'sh /probe/probe.sh' 2>/dev/null | tail -1)" = 0 ] \
        && ok "alpine busybox ps: the probe reports unsupported, as declared" \
        || fail "the probe claimed lstart support on busybox"
    rm -rf "$pp"
else
    printf '  skip  labelled-launch and minimal-image rows (no docker daemon or alpine/git image)\n'
fi

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
    if ( cd "$sf" && python3 "$ROOT/.github/scripts/check_schema.py" >/dev/null 2>&1 ); then
        fail "ACCEPTED but must be rejected: a camelCase non-field backticked in reaping.md"
    else
        ok "rejected: a camelCase non-field backticked in reaping.md"
    fi
    rm -rf "$sf"
fi

# ---------------------------------------------------------------- result ----
section "result"

if [ "$fails" -eq 0 ]; then
    printf '  all checks passed\n\n'
    exit 0
fi
printf '  %s check(s) failed\n\n' "$fails"
exit 1
