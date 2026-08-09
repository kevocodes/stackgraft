#!/bin/sh
# One request, one response, counted out of DATABASE_URL. A caller can tell the
# base database from an isolated copy by the answer rather than by trusting the
# address it was given.
set -u

read -r request_line
while read -r header; do
    case "$(printf '%s' "$header" | tr -d '\r')" in
        "") break ;;
    esac
done

path=$(printf '%s' "$request_line" | awk '{print $2}')
products=$(psql "$DATABASE_URL" -tAc 'SELECT count(*) FROM products' 2>/dev/null || printf 'unavailable')
body=$(printf '{"service":"catalog-api","path":"%s","products":%s}' "$path" "$products")

printf 'HTTP/1.1 200 OK\r\n'
printf 'Content-Type: application/json\r\n'
printf 'X-Service: catalog-api\r\n'
printf 'Content-Length: %s\r\n' "${#body}"
printf '\r\n'
printf '%s' "$body"
