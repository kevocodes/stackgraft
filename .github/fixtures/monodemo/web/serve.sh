#!/bin/sh
# One entry point for every backend unit. What a unit DOES at startup is decided
# by its name, which is how a reader tells W from X apart here: `orders` applies
# its schema on boot, `billing` runs a scheduler loop over rows the ledger holds.
set -eu
name=$1
port=$2

psql_ () { psql "$LEDGER_URL" -tAc "$1" 2>/dev/null || true; }

case $name in
    orders)
        # Applies the schema this unit owns, every time it starts. Whatever
        # LEDGER_URL points at is what gets written.
        until psql_ 'SELECT 1' | grep -q 1; do sleep 1; done
        psql_ 'CREATE TABLE IF NOT EXISTS order_lines (id serial PRIMARY KEY, sku text NOT NULL, qty integer NOT NULL DEFAULT 1)'
        psql_ 'ALTER TABLE order_lines ADD COLUMN IF NOT EXISTS note text'
        ;;
    billing)
        # A scheduler singleton: one loop per stack, driving the cadence written
        # in billing_schedules. A second one fires the same schedules again.
        until psql_ 'SELECT 1' | grep -q 1; do sleep 1; done
        ( while true; do
              psql_ "UPDATE billing_schedules SET last_fired = now() WHERE cron_expression IS NOT NULL"
              sleep 60
          done ) &
        ;;
esac

while true; do
    printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{"service":"%s"}\n' "$name" \
        | nc -l -p "$port" >/dev/null 2>&1 || sleep 1
done
