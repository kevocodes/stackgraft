#!/bin/sh
# The only thing this directory does. There is deliberately no database
# lifecycle target here: that absence is the ordinary case, and it is what the
# generated family exists to answer.
set -eu

cd "$(dirname "$0")/.."
exec docker compose up -d --wait
