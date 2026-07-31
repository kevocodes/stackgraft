#!/bin/sh
# fingerprint.sh - content fingerprints for stackgraft manifest sources.
#
# usage:  sh scripts/fingerprint.sh [-C repoRoot] <path>...
#         sh scripts/fingerprint.sh [-C repoRoot] -      # paths on stdin
# stdout: "<fingerprint><TAB><path>" per input path, in input order.
#         Unreadable path, directory, or hash failure -> "-<TAB><path>".
#         "-" is drift, not an error: a source that vanished really did change.
# exit:   0 ok  ·  2 usage error or cd failed
#
# Paths are arguments by default; stdin is read only when the single argument
# is "-". A caller that forgets a redirect gets a usage error instead of a
# process blocked forever with nothing to diagnose.
#
# Needs git only. Writes no file, parses no JSON, probes nothing. --no-filters
# is mandatory: a clean filter could otherwise mask a real content change.

usage() {
    printf 'usage: sh %s [-C repoRoot] <path>...\n' "$0" >&2
    printf '       sh %s [-C repoRoot] -\n' "$0" >&2
    exit 2
}

emit() {
    if [ -f "$1" ] && digest=$(git hash-object --no-filters -- "$1" 2>/dev/null); then
        printf '%s\t%s\n' "$digest" "$1"
    else
        printf -- '-\t%s\n' "$1"
    fi
}

if [ "${1:-}" = "-C" ]; then
    [ "$#" -ge 3 ] || usage
    cd -- "$2" || exit 2
    shift 2
fi
[ "$#" -ge 1 ] || usage

if [ "$1" = "-" ] && [ "$#" -eq 1 ]; then
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        emit "$path"
    done
else
    for path in "$@"; do
        [ -n "$path" ] || continue
        emit "$path"
    done
fi
