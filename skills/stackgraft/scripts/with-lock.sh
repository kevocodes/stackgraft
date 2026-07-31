#!/bin/sh
# with-lock.sh - serialized, compare-and-swap replacement of one cache file.
#
# usage:  sh scripts/with-lock.sh <destination> <payload> <expected>
#         <destination>  the cache file to replace
#         <payload>      a file the CALLER already composed. It is COPIED, never
#                        moved, so a caller retrying after exit 5 still holds it.
#         <expected>     fingerprint of <destination> as the caller READ it:
#                        git hash-object --stdin < <destination>, or "-" when the
#                        caller found no file there. Mandatory.
# stdout: nothing. Every diagnostic goes to stderr.
# exit:   0 committed
#         2 usage error
#         3 lock not acquired - destination untouched
#         4 environment failure: cache directory, copy, rename, or a reclaimed
#           lock that would not delete
#         5 destination changed since <expected> - re-read, re-merge and retry,
#           at most 3 attempts, then ask the user
#
# <expected> is mandatory rather than optional, because serializing the write
# alone does not fix last-writer-wins. Two runs each read the file, each merge
# their own entry, and each write under a perfect lock: the loser's entry is
# still gone. The loss happens in the read-modify-write window, not in the
# write, so the guard has to close that window - and an optional guard is a
# guard nobody passes.
#
# Bounds, stated here as values rather than left to be read out of the control
# flow: WAIT_ATTEMPTS=10 attempts, WAIT_INTERVAL=1 second apart, give a 10
# second wait bound. That is also the staleness bound - a lock already present
# when the wait began, and unchanged when it ended, is reclaimable. Acquisition
# spends at most two of those bounds, so the worst case is 20 seconds and never
# an unbounded wait.
#
# Liveness decides staleness before any timer does. A holder whose pid is gone,
# or whose recorded start time no longer matches, is provably dead and its lock
# is reclaimed at once. A holder that is provably alive is never stolen from.
# Only an unprovable holder reaches the time bound, and getting that one wrong
# degrades to last-writer-wins, which the compare-and-swap guard still refuses,
# while never reclaiming turns one crash into a permanent outage.
#
# Reads no stdin, by design: both other shipped scripts take arguments too, and
# a helper an agent invokes that blocks forever leaves nothing to diagnose.
#
# Writes exactly three things and nothing else:
#   1. the lock directory <destination>.lock, with its owner and tmp files
#      inside it. Reclaiming renames that directory aside to a unique name and
#      deletes it, which is how it is removed rather than a fourth write. That
#      deletion is VERIFIED rather than assumed: an aside that survives its own
#      removal is a fourth path, so the run says so by name and fails with 4
#      instead of committing and reporting a successful reclaim over it. Debris
#      plus a success exit is the worse half - the caller is told the write
#      landed and learns nothing about what is now sitting in the cache.
#   2. one empty staleness reference <destination>.wait.<pid>, the file the wait
#      bound is measured against. It cannot live inside the lock directory,
#      because that directory belongs to whoever holds it.
#   3. the rename of the caller's prepared payload into <destination>.
# It composes no content, parses no JSON, and edits nothing: the agent owns the
# bytes.
#
# Needs git, POSIX sh, POSIX awk and the ordinary file utilities. No flock
# (util-linux ships it, stock macOS does not), no timeout (absent from at least
# one supported platform), no stat, and no separate hashing binary.
#
# Declared limitation: mkdir atomicity is not guaranteed on a network
# filesystem. A cache directory on NFS is out of scope, stated rather than
# worked around.

set -u

WAIT_ATTEMPTS=10
WAIT_INTERVAL=1

me=${0##*/}
lstart_supported=0

usage() {
    [ "$#" -eq 0 ] || printf '%s: %s\n' "$me" "$1" >&2
    printf 'usage: sh %s <destination> <payload> <expected>\n' "$0" >&2
    printf '       <expected> is git hash-object --stdin over <destination> as read, or - when absent\n' >&2
    exit 2
}

# --- BEGIN lstart probe -----------------------------------------------------
# Kept byte-identical in every script that needs process identity, so a copy
# that drifted shows up as a difference rather than as a subtly weaker proof.
#
# Two conditions, and the second is what makes the first a check: a ps that
# ignores -p answers the first call plausibly and the second with the whole
# table, which on any host running this probe holds more than one process.
# Asking for pid 1 as well is what catches it.
#
# The batched form for several pids at once is one process too:
# ps -o pid=,lstart= -p <comma-separated list>.
lstart_lines() { ps -o lstart= -p "$1" 2>/dev/null | awk 'NF { n++ } END { print n + 0 }'; }
lstart_of()    { ps -o lstart= -p "$1" 2>/dev/null | awk 'NF { print; exit }'; }
lstart_probe() {
    if [ "$(lstart_lines "$$")" = 1 ] && [ "$(lstart_lines 1)" = 1 ]; then
        lstart_supported=1
    else
        lstart_supported=0
    fi
}
# --- END lstart probe -------------------------------------------------------

[ "$#" -eq 3 ] || usage 'expects exactly three arguments: <destination> <payload> <expected>'
destination=$1
payload=$2
expected=$3
[ -n "$destination" ] || usage 'empty destination'
[ -n "$payload" ] || usage 'empty payload'
[ -n "$expected" ] || usage 'empty expected fingerprint'
[ -f "$payload" ] || usage "payload is not a readable file: '$payload'"

case $destination in
    */*) parent=${destination%/*} ;;
    *)   parent=. ;;
esac
if [ ! -d "$parent" ]; then
    printf '%s: cache directory does not exist: %s\n' "$me" "$parent" >&2
    exit 4
fi

lock="$destination.lock"
waitref=
aside=
held=0
holder_state=unknown
holder_pid=

# $aside is set only for the window between renaming a stale lock directory
# aside and deleting it, so a signal landing inside that window still takes the
# path away with it. Outside the window it is empty and nothing is removed.
cleanup() {
    [ "$held" -eq 1 ] && rm -rf "$lock"
    [ -n "$waitref" ] && rm -f "$waitref"
    [ -n "$aside" ] && rm -rf "$aside"
    return 0
}

# A bare trap CONTINUES in POSIX sh, so INT, TERM and HUP each re-exit non-zero
# rather than falling through into the commit. A waiter that never acquired
# leaves held at 0 and removes nothing that is not its own.
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

# Takes the lock and records who holds it: three lines, pid / start time or "-"
# / host. mkdir is atomic and fails when the directory exists, which is the
# whole mutual exclusion.
take() {
    mkdir "$lock" 2>/dev/null || return 1
    held=1
    lstart_probe
    _own='-'
    if [ "$lstart_supported" -eq 1 ]; then
        _own=$(lstart_of "$$")
        [ -n "$_own" ] || _own='-'
    fi
    {
        printf '%s\n' "$$"
        printf '%s\n' "$_own"
        printf '%s\n' "$(uname -n)"
    } > "$lock/owner" 2>/dev/null
    return 0
}

# Classifies the current holder into holder_state, leaving its pid in
# holder_pid so a refusal can name it. The host is part of the identity: a pid
# read from another machine's lock file means nothing here, and an unreadable,
# short or "-" record is unprovable rather than dead.
read_holder() {
    holder_state=unknown
    holder_pid=
    [ -r "$lock/owner" ] || return 0
    _pid=$(awk 'NR == 1 { print; exit }' "$lock/owner" 2>/dev/null)
    _rec=$(awk 'NR == 2 { print; exit }' "$lock/owner" 2>/dev/null)
    _host=$(awk 'NR == 3 { print; exit }' "$lock/owner" 2>/dev/null)
    case ${_pid:-} in
        '' | *[!0-9]*) return 0 ;;
    esac
    [ "${_host:-}" = "$(uname -n)" ] || return 0
    [ "${_rec:--}" != '-' ] || return 0
    holder_pid=$_pid
    _now=$(lstart_of "$_pid")
    if [ -z "$_now" ] || [ "$_now" != "$_rec" ]; then
        holder_state=dead
    else
        holder_state=live
    fi
    return 0
}

# Renames first and deletes second: the rename is atomic, so exactly one of N
# simultaneous waiters wins it and the losers fall back into the ordinary retry
# instead of racing through a half-deleted directory. Reclaiming is reported,
# because a lock that vanished without a word is indistinguishable from one
# that was never there.
#
# The aside is the fourth path this script could leave behind, so its deletion
# is checked rather than assumed. `rm -rf` reports nothing usable here - it
# exits non-zero on some of the ways it can fail and the directory is what the
# answer is about - so the question asked is whether the path is still there.
# One that is gets named and ends the run at 4, with the destination untouched,
# because the alternative is committing and reporting a reclaim while a
# directory nobody mentioned stays in the cache forever.
reclaim() {
    aside="$lock.stale.$$"
    if ! mv "$lock" "$aside" 2>/dev/null; then
        aside=
        return 1
    fi
    rm -rf "$aside"
    if [ -e "$aside" ]; then
        printf '%s: reclaimed the lock at %s but could not delete %s; %s untouched\n' \
            "$me" "$lock" "$aside" "$destination" >&2
        exit 4
    fi
    aside=
    printf '%s: reclaimed an abandoned lock at %s\n' "$me" "$lock" >&2
    return 0
}

wait_bound() {
    _n=0
    while [ "$_n" -lt "$WAIT_ATTEMPTS" ]; do
        sleep "$WAIT_INTERVAL"
        _n=$((_n + 1))
        take && return 0
    done
    return 1
}

# Failure to acquire is a reported failure, never a skipped write: there is no
# unlocked fallback below this point.
refuse() {
    if [ -n "$holder_pid" ]; then
        printf '%s: lock at %s is held by pid %s; %s untouched\n' \
            "$me" "$lock" "$holder_pid" "$destination" >&2
    else
        printf '%s: could not take the lock at %s; %s untouched\n' \
            "$me" "$lock" "$destination" >&2
    fi
    exit 3
}

acquire() {
    take && return 0

    read_holder
    case $holder_state in
        dead)
            reclaim
            take && return 0
            ;;
        live)
            # Never steal from a holder that is provably alive. Wait the whole
            # bound in case it finishes, then refuse.
            wait_bound && return 0
            read_holder
            refuse
            ;;
    esac

    # Unprovable holder. Plant the reference the bound is measured against,
    # wait it out, and only then ask whether the lock predates the whole bound.
    waitref="$destination.wait.$$"
    if ! : > "$waitref" 2>/dev/null; then
        printf '%s: cannot write beside the destination: %s\n' "$me" "$waitref" >&2
        exit 4
    fi
    wait_bound && return 0

    read_holder
    case $holder_state in
        live)
            refuse
            ;;
        dead)
            reclaim
            take && return 0
            ;;
    esac

    if [ -z "$(find "$lock" -prune -newer "$waitref" 2>/dev/null)" ]; then
        # The lock was already there when the reference was planted and has not
        # been replaced since, so it predates the whole bound.
        reclaim
        take && return 0
    else
        # Created during the wait. It is not stale and is not ours to steal, so
        # give it one further bounded cycle and then refuse.
        wait_bound && return 0
    fi

    read_holder
    refuse
}

acquire || exit 3

if [ -e "$destination" ]; then
    if ! current=$(git hash-object --stdin < "$destination"); then
        printf '%s: could not fingerprint %s\n' "$me" "$destination" >&2
        exit 4
    fi
else
    current='-'
fi

if [ "$current" != "$expected" ]; then
    printf '%s: %s changed since it was read (expected %s, found %s); re-read, re-merge and retry, at most 3 attempts, then ask\n' \
        "$me" "$destination" "$expected" "$current" >&2
    exit 5
fi

if ! cp "$payload" "$lock/tmp"; then
    printf '%s: could not stage the payload inside %s\n' "$me" "$lock" >&2
    exit 4
fi
if ! mv "$lock/tmp" "$destination"; then
    printf '%s: could not rename into %s\n' "$me" "$destination" >&2
    exit 4
fi
exit 0
