#!/bin/sh
# A writing service, present so the gate has a real (service, store) pair to
# classify. It answers from the database it is pointed at, so the response says
# which database that was.
set -eu

exec nc -lk -p 8080 -e sh /app/handle.sh
