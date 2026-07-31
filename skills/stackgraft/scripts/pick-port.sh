#!/bin/sh
# pick-port.sh - deterministic overlay port CANDIDATE for stackgraft.
#
# usage:  sh scripts/pick-port.sh <lo> <hi> <worktree-path> [excluded-port...]
#         Every port argument is decimal and within 1-65535.
# stdout: exactly one integer - a CANDIDATE, never a verified-free port.
#         Availability is not portably checkable and any reading is stale at
#         once, so the authoritative test is the launcher's strict-port bind
#         failure. On that failure re-run with the port appended to the
#         excluded list; never record a failed port in the manifest.
# exit:   0 candidate emitted  ·  2 usage error  ·  3 range exhausted
#         4 environment failure: git could not hash the worktree path. Kept
#         apart from 2 so a caller can tell a bad invocation from a broken
#         toolchain - the first is worth retrying differently, the second is not.
#
# Reads no stdin, by design. Exclusions arrive as arguments so a caller that
# forgets a redirect cannot hang: for a tool agents invoke, blocking forever is
# worse than failing, because it leaves nothing to diagnose.
#
# Needs git and POSIX awk. Probes nothing, writes no file. The start offset is
# derived from the worktree path - required, because it is the only thing that
# makes the offset per-worktree - so two worktrees of one repo do not collide,
# while one worktree keeps the same port across runs however its path was
# spelled: the path is normalised to an absolute physical one (cd + pwd -P)
# before hashing, so "/path/wt", "/path/wt/", a relative form, and /tmp versus
# /private/tmp all land on the same port. An all-digit third
# argument is refused: it is an exclusion sitting in the worktree slot, and
# accepting it would silently drop that port from the excluded set.

usage() {
    printf 'usage: sh %s <lo> <hi> <worktree-path> [excluded-port...]\n' "$0" >&2
    exit 2
}

# Validates one port argument into port_val: decimal, 1-65535, leading zeros
# stripped so arithmetic expansion cannot read "08" as a bad octal constant.
# Sets a global instead of printing, because usage() has to end the script and
# an exit inside a command substitution would only leave the subshell.
port_arg() {
    case ${1:-} in '' | *[!0-9]*) usage ;; esac
    port_val=$1
    while [ "${port_val#0}" != "$port_val" ]; do port_val=${port_val#0}; done
    [ -n "$port_val" ] && [ "${#port_val}" -le 5 ] && [ "$port_val" -le 65535 ] || usage
}

port_arg "${1:-}"; lo=$port_val
port_arg "${2:-}"; hi=$port_val
[ "$lo" -le "$hi" ] || usage
[ "$#" -ge 3 ] && [ -n "$3" ] || usage
case $3 in *[!0-9]*) ;; *) usage ;; esac

span=$((hi - lo + 1))

worktree=$(CDPATH= cd -- "$3" 2>/dev/null && pwd -P) || usage
shift 3

# Exclusions are normalised too: "018099" must exclude 18099, not slip past a
# string comparison against the emitted form.
excluded=' '
for arg in "$@"; do
    [ -n "$arg" ] || continue
    port_arg "$arg"
    excluded="$excluded$port_val "
done

digest=$(printf '%s' "$worktree" | git hash-object --stdin) || exit 4
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
