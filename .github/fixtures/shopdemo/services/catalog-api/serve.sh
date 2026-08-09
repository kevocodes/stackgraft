#!/bin/sh
# A writing service, present so the gate has a real (service, store) pair to
# classify. It answers from the database it is pointed at, so the response says
# which database that was.
#
# It applies its own migrations on startup, which is the ordinary shape and the
# one the gate's `migrates` escalation is written for: whatever this entrypoint
# does, it does to whichever store DATABASE_URL names. Overlay it against a
# copy and the copy is what gets migrated; overlay it against the base store
# and the base store is, which is the whole reason that pair is not reusable.
set -eu

for m in /db/migrations/*.sql; do
    [ -e "$m" ] || continue
    printf 'applying %s\n' "$m" >&2
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$m" >&2 || printf 'migration failed: %s\n' "$m" >&2
done

exec nc -lk -p 8080 -e sh /app/handle.sh
