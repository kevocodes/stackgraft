# fingerprint.sh - content fingerprints for stackgraft manifest sources.
#
# usage:  sh scripts/fingerprint.sh [repoRoot]
# stdin:  one path per line, relative to repoRoot or absolute; blanks ignored
# stdout: "<fingerprint><TAB><path>" per input path, in input order.
#         Unreadable path, directory, or hash failure -> "-<TAB><path>".
#         "-" is drift, not an error: a source that vanished really did change.
# exit:   0 ok  ·  2 usage error or cd failed
#
# Needs git only. Writes no file, parses no JSON, probes nothing. --no-filters
# is mandatory: a clean filter could otherwise mask a real content change.

if [ "$#" -gt 1 ]; then
    printf 'usage: sh %s [repoRoot]\n' "$0" >&2
    exit 2
fi
[ "$#" -eq 1 ] && { cd -- "$1" || exit 2; }

while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$path" ] && digest=$(git hash-object --no-filters -- "$path" 2>/dev/null); then
        printf '%s\t%s\n' "$digest" "$path"
    else
        printf -- '-\t%s\n' "$path"
    fi
done
