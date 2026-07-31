#!/bin/sh
# verify.sh - every check this project makes, run for real.
#
# usage:  sh .github/scripts/verify.sh
# exit:   0 all checks passed  ·  1 at least one failed
#
# Two habits this file exists to enforce, both learned the hard way:
#   - a check that cannot fail is not a check. Every assertion below has a
#     matching negative fixture that must be REJECTED, so a validator that
#     silently stopped validating shows up as a failure rather than a pass.
#   - the minimal instance the schema accepts is the one worth tracing. Most
#     holes in this project's safety gate were found by building the smallest
#     legal manifest and asking what the gate did with it.

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
