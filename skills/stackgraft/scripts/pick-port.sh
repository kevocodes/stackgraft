# pick-port.sh - deterministic overlay port CANDIDATE for stackgraft.
#
# usage:  sh scripts/pick-port.sh <lo> <hi> [worktree-path]
# stdin:  zero or more excluded ports, one integer per line. Redirect from a
#         file, a pipe, or /dev/null. An interactive terminal carries no
#         exclusions, so it is read as an empty list and never blocks.
# stdout: exactly one integer - a CANDIDATE, never a verified-free port.
#         Availability is not portably checkable and any reading is stale at
#         once, so the authoritative test is the launcher's strict-port bind
#         failure. On that failure add the port to the exclude list and ask
#         again; never record a failed port in the manifest.
# exit:   0 candidate emitted  ·  2 usage error  ·  3 range exhausted
#
# Needs git and POSIX awk. Probes nothing, writes no file. The start offset is
# derived from the worktree path so two worktrees of one repo do not collide,
# while one worktree keeps the same port across runs.

usage() {
    printf 'usage: sh %s <lo> <hi> [worktree-path]\n' "$0" >&2
    exit 2
}

case ${1:-} in '' | *[!0-9]*) usage ;; esac
case ${2:-} in '' | *[!0-9]*) usage ;; esac
[ "$1" -le "$2" ] || usage

span=$(($2 - $1 + 1))
digest=$(printf '%s' "${3:-$PWD}" | git hash-object --stdin) || exit 2
offset=$(printf '%s' "$digest" | awk -v s="$span" '{n = 0; for (i = 1; i <= 8; i++) n = (n * 16 + index("0123456789abcdef", substr($0, i, 1)) - 1) % s; print n}')

excluded=' '
if [ ! -t 0 ]; then
    while IFS= read -r port; do
        case $port in '' | *[!0-9]*) continue ;; esac
        excluded="$excluded$port "
    done
fi

i=0
while [ "$i" -lt "$span" ]; do
    port=$(($1 + (offset + i) % span))
    case $excluded in
        *" $port "*) i=$((i + 1)) ;;
        *) printf '%s\n' "$port"; exit 0 ;;
    esac
done
exit 3
