#!/bin/sh
# The one line that differs between the main checkout and a worktree. The web
# unit's Dockerfile bakes this file in with COPY, so nothing but a rebuild from
# the worktree can change what a launched container actually runs -- which is
# the whole subject of .github/scripts/integration-staleness.sh.
echo "build=main"
