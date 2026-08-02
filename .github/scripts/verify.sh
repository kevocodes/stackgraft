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
        printf '  skip  the live-holder control for the unremovable-aside row (no ps -o lstart=)\n'
    fi
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
for term in REUSE ISOLATE REAP; do
    printf '%s' "$body" | grep -q "$term" \
        && fail "body contains the permitting term $term" \
        || ok "body states no $term"
done

# ...and the loop can fire on the term this change adds. The body never
# spelling REAP is what leaves an agent holding only the body able to reach
# refusal and nothing else, so a loop that had quietly stopped looking would
# read from here exactly like a body that is clean.
verdict_hits() {
    _n=0
    for _t in REUSE ISOLATE REAP; do
        printf '%s' "$1" | grep -q "$_t" && _n=$((_n + 1))
    done
    printf '%s\n' "$_n"
}
[ "$(verdict_hits "$body
| Overlay outlived its worktree | REAP it |")" -ge 1 ] \
    && ok "rejected: a body line naming the REAP verdict" \
    || fail "the verdict-term loop cannot report a term it should catch"

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
        awk '/BEGIN lstart probe/ { on = 1; next } /END lstart probe/ { on = 0 } on { print }' "$LOCK"
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
        && git -c user.email=verify@invalid -c user.name=verify commit -q -m scripts \
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
    printf '  skip  labelled-launch and minimal-image rows (no docker daemon or alpine/git image)\n'
fi

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
extract_probe() {
    awk '/BEGIN lstart probe/ { on = 1; next } /END lstart probe/ { on = 0 } on { print }' "$1" 2>/dev/null
}
p_lock=$(extract_probe "$LOCK" | git hash-object --stdin)
p_reap=$(extract_probe "$REAP" | git hash-object --stdin)
if [ -n "$(extract_probe "$REAP")" ] && [ "$p_lock" = "$p_reap" ]; then
    ok "the lstart probe block is byte-identical in with-lock.sh and reap.sh"
else
    fail "the lstart probe block is missing from reap.sh or differs from with-lock.sh"
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
reap_run -b 18103 -m stop 00c0ffee 'c:deadbeefcafe'
if [ "$reap_rc" -ne 2 ]; then
    ok "rejected: a usage error for a supplied base port, which the parser must accept ($reap_rc)"
else
    fail "a supplied -b was rejected as a usage error, so the row above proves nothing"
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
        [ -n "$cid" ] && fixture_ids="$fixture_ids $cid"
    }

    repo="$rf/repo"
    mkdir -p "$repo"
    ( cd "$repo" \
      && git init -q . \
      && git -c user.email=v@example.invalid -c user.name=verify commit -q --allow-empty -m init \
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

    reap_run -C "$repo" -b 18103 -m stop "$RH" "c:$future"
    if [ "$reap_rc" -eq 3 ] && printf '%s' "$reap_out" | grep -q 'unrecognised-label-version'; then
        ok "rejected: a label contract version this run does not recognise"
    else
        fail "unrecognised-version target: exit $reap_rc, said '$reap_out'"
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

    for id in $fixture_ids; do docker rm -f "$id" >/dev/null 2>&1; done
    ( cd "$repo" && git worktree remove --force "$rf/wt" ) >/dev/null 2>&1
    rm -rf "$rf"
else
    printf '  skip  the container refusal fixtures (no docker daemon or alpine/git image)\n'
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
        printf '  skip  the unsignallable-target row (running as root, which can signal pid 1)\n'
    fi
else
    printf '  skip  the (pid, lstart) target rows (this host has no ps -o lstart=)\n'
fi

# --- scoping is in the query, not in a filter over its output ----------------
# This is the check DS28's dropped query 3 would have failed, and A7 is why it
# stays dropped: an unfiltered listing does not find legacy overlays, it lists
# everything and cannot say which is which - while reaching a sibling
# repository's containers, which are not ours to enumerate or to kill.
#
# Comment lines and the manual command the legacy record PRINTS are skipped by
# name: they are text, not invocations. The fixture below proves the detector
# still fires on a real one.
unfiltered_ps() {
    awk '
        /^[ \t]*#/                   { next }
        /Inspect them yourself with/ { next }
        /docker ps/ && !/label=stackgraft\.repo=/ { n++ }
        END { print n + 0 }
    ' "$@"
}
[ "$(unfiltered_ps "$SKILL"/scripts/*.sh)" -eq 0 ] \
    && ok "every container listing in a shipped script carries the hash8 label filter" \
    || fail "$(unfiltered_ps "$SKILL"/scripts/*.sh) unfiltered container listing(s) in shipped scripts"

qf=$(mktemp -d)
printf '#!/bin/sh\nlegacy=$(docker ps --all --format "{{.ID}}")\n' > "$qf/fixture.sh"
[ "$(unfiltered_ps "$qf/fixture.sh")" -ge 1 ] \
    && ok "rejected: a repository-wide container listing, the query A7 keeps dropped" \
    || fail "the unfiltered-listing detector cannot fire"
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
if [ "$rc" -eq 0 ] && [ "$(a7_verdict "$af/report.txt")" = pass ]; then
    ok "the report names the legacy category, calls it structural, and prints the manual command"
else
    fail "the report's legacy statement: exit $rc, verdict $(a7_verdict "$af/report.txt")"
fi

grep -v "^legacy${TAB}" "$af/report.txt" > "$af/silent.txt"
[ "$(a7_verdict "$af/silent.txt")" = no-legacy-record ] \
    && ok "rejected: a report with the legacy statement absent - silence reads as nothing to see" \
    || fail "ACCEPTED but must be rejected: a report that says nothing about legacy overlays"

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

lf=$(mktemp -d)
mkdir -p "$lf/stackgraft"
sc="$lf/stackgraft/stackgraft-00c0ffee.processes.json"
printf '{"version":1,"repo":"00c0ffee","at":"x","overlays":[]}\n' > "$sc"
mkdir "$sc.lock"
printf '%s\n-\n%s\n' "$$" "$(uname -n)" > "$sc.lock/owner"

before_locks=$(count_locks "$lf/stackgraft")
out=$(XDG_CACHE_HOME="$lf" sh "$REAP" report 00c0ffee 2>&1)
rc=$?
after_locks=$(count_locks "$lf/stackgraft")
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
sf2=$(mktemp -d)
mkdir -p "$sf2/stackgraft"
sc2="$sf2/stackgraft/stackgraft-00c0ffee.processes.json"

printf '{"version":1,"repo":"00c0ffee","at":"x","overlays":[]}\n' > "$sc2"
out=$(XDG_CACHE_HOME="$sf2" sh "$REAP" report 00c0ffee 2>/dev/null)
printf '%s' "$out" | grep -q "^host${TAB}checked${TAB}none" \
    && ok "an empty registry reports zero host overlays, checked" \
    || fail "an empty registry did not report a checked zero"
if [ "$docker_ready" -eq 1 ]; then
    if printf '%s' "$out" | grep -q "^held${TAB}incomplete"; then
        fail "the held-port set reported itself short with every store readable"
    else
        ok "rejected: the held-port shortfall line when every store answered"
    fi
fi

rm -f "$sc2"
out=$(XDG_CACHE_HOME="$sf2" sh "$REAP" report 00c0ffee 2>/dev/null)
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
out=$(XDG_CACHE_HOME="$sf2" sh "$REAP" report 00c0ffee 2>/dev/null)
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
    if printf '%s' "$out" | grep -q "^degraded${TAB}docker-unavailable"; then
        fail "the report claims the runtime is unavailable on a host where it answers"
    else
        ok "rejected: the docker-unavailable line on a host that has docker"
    fi
    printf '%s' "$out" | grep -q "^container${TAB}checked${TAB}none" \
        && ok "a runtime that answered and matched nothing reports a checked zero" \
        || fail "the runtime answered and the report stated no checked zero"
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
        docker rm -f "$c1" "$c2" >/dev/null 2>&1
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
        docker rm -f "$hpc" >/dev/null 2>&1
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
    printf '  skip  the two-repo and minimal-image reap rows (no docker daemon or alpine/git image)\n'
fi

# ------------------------------------------------------------ portability ---
section "portability"

if grep -rniE '~/\.claude|codegraph|\bpython3\b|\bjq\b|sha256sum|AppData' "$SKILL" >/dev/null 2>&1; then
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
    printf '  skip  the version fixtures (they are derived from the shipped files, which failed above)\n'
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

head -1 "$SECTION" | grep -q '^#!/bin/sh' \
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
        printf '  skip  the removed-entry fixture (it removes an entry the file does not carry)\n'
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
        printf '  skip  the removed-definition fixture (it removes a definition the file does not carry)\n'
    fi

    rm -rf "$nf"
else
    printf '  skip  the entry and link-definition rows (plugin.json declares no readable version: %s)\n' "$rel_version"
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
