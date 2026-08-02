#!/bin/sh
# changelog-section.sh - print one release's CHANGELOG section, heading removed.
#
# usage:  sh .github/scripts/changelog-section.sh <version> [changelog]
#         sh .github/scripts/changelog-section.sh 1.1.0
#
# exit:   0  the section was found and its body printed on stdout
#         2  usage error, or the changelog does not exist
#         3  the file has no `## [<version>]` section
#         4  the section exists but its body is empty
#
# The version is an ARGUMENT and this script reads no stdin under any
# invocation, including the empty one: for a tool an agent or a CI step calls,
# hanging with nothing to diagnose is worse than failing.
#
# Two things are stripped, and the second one is the whole reason this file
# exists rather than an awk one-liner in a workflow:
#
#   - The `## [<version>] - <date>` heading. A GitHub release already renders
#     the version as its title and shows the tag beside it, so repeating it in
#     the body says the same thing twice - and it was the half that rendered
#     inconsistently.
#   - Everything from the first link-reference definition onwards. Those
#     definitions live at the FOOT of the file, which means the last section
#     has no `## [` heading after it: a rule that stopped only at the next
#     heading ran to EOF and took them into the release body. That is not a
#     hypothetical. It is why one published release rendered its version as a
#     blue link inside its own notes while the next rendered `[1.1.0]` as
#     literal brackets.

set -u

me=${0##*/}

usage() {
    printf '%s: usage: %s <version> [changelog]\n' "$me" "$me" >&2
    printf '%s: the version is an argument; this script never reads stdin\n' "$me" >&2
    exit 2
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage

version=$1
file=${2:-CHANGELOG.md}

# A leading dash in either slot is refused rather than passed on: awk would
# read `-` as a request to read standard input, which is the one thing this
# script promises never to do.
case $version in
    '' | -*) usage ;;
esac
case $file in
    '' | -*) usage ;;
esac

if [ ! -f "$file" ]; then
    printf '%s: no such changelog: %s\n' "$me" "$file" >&2
    exit 2
fi

# The bracketed token is compared LITERALLY. Building a regex out of the
# version would make its dots match any character, so a request for 1.1.0
# would also be answered by a section headed 1x1y0.
#
# Blank lines are held back rather than printed as they arrive, so the body
# starts and ends on real content: a release body opening with two blank lines
# is not wrong, but it is noise the file's own formatting did not intend.
section=$(
    awk -v want="$version" '
        /^## \[/ {
            p = index($0, "]")
            if (p > 4 && substr($0, 5, p - 5) == want) {
                found = 1
                on = 1
                next
            }
            if (on) exit
            next
        }

        on && /^\[[^]]+\]:/ { exit }

        on {
            if ($0 ~ /^[ \t]*$/) { if (started) blanks++; next }
            for (; blanks > 0; blanks--) print ""
            started = 1
            print
        }

        END {
            if (!found)   exit 3
            if (!started) exit 4
        }
    ' "$file"
)
rc=$?

case $rc in
    0)
        printf '%s\n' "$section"
        ;;
    3)
        printf '%s: no entry for %s in %s\n' "$me" "$version" "$file" >&2
        exit 3
        ;;
    4)
        printf '%s: the entry for %s in %s has an empty body\n' "$me" "$version" "$file" >&2
        exit 4
        ;;
    *)
        printf '%s: could not read %s (awk exited %s)\n' "$me" "$file" "$rc" >&2
        exit 1
        ;;
esac
