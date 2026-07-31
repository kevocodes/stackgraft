#!/bin/sh
# pick-port.sh - deterministic overlay port CANDIDATE for stackgraft.
#
# usage:  sh scripts/pick-port.sh <lo> <hi> <worktree-path> [excluded-port...]
# stdout: exactly one integer - a CANDIDATE, never a verified-free port.
#         Availability is not portably checkable and any reading is stale at
#         once, so the authoritative test is the launcher's strict-port bind
#         failure. On that failure re-run with the port appended to the
#         excluded list; never record a failed port in the manifest.
# exit:   0 candidate emitted  ·  2 usage error  ·  3 range exhausted
#
# Reads no stdin, by design. Exclusions arrive as arguments so a caller that
# forgets a redirect cannot hang: for a tool agents invoke, blocking forever is
# worse than failing, because it leaves nothing to diagnose.
#
# Needs git and POSIX awk. Probes nothing, writes no file. The start offset is
# derived from the worktree path - required, because it is the only thing that
# makes the offset per-worktree - so two worktrees of one repo do not collide,
# while one worktree keeps the same port across runs. An all-digit third
# argument is refused: it is an exclusion sitting in the worktree slot, and
# accepting it would silently drop that port from the excluded set.

usage() {
    printf 'usage: sh %s <lo> <hi> <worktree-path> [excluded-port...]\n' "$0" >&2
    exit 2
}

case ${1:-} in '' | *[!0-9]*) usage ;; esac
case ${2:-} in '' | *[!0-9]*) usage ;; esac
[ "$1" -le "$2" ] || usage
[ "$#" -ge 3 ] && [ -n "$3" ] || usage
case $3 in *[!0-9]*) ;; *) usage ;; esac

lo=$1
span=$(($2 - $1 + 1))

worktree=$3
shift 3
excluded=" $* "

digest=$(printf '%s' "$worktree" | git hash-object --stdin) || exit 2
offset=$(printf '%s' "$digest" | awk -v s="$span" '{n = 0; for (i = 1; i <= 8; i++) n = (n * 16 + index("0123456789abcdef", substr($0, i, 1)) - 1) % s; print n}')

i=0
while [ "$i" -lt "$span" ]; do
    port=$((lo + (offset + i) % span))
    case $excluded in
        *" $port "*) i=$((i + 1)) ;;
        *) printf '%s\n' "$port"; exit 0 ;;
    esac
done
exit 3
