#!/usr/bin/env bash
# Continuously requests the route and logs timestamp + HTTP status, so a
# reload can be measured for dropped requests. Run in the background,
# trigger a reload in another terminal, then Ctrl+C to see the summary.
#
# Usage: ./load-test.sh [output-log] [interval-seconds]
set -euo pipefail

LOG="${1:-/tmp/coraza-load-test.log}"
INTERVAL="${2:-0.05}"
URL="http://127.0.0.1:9080/anything"

: > "$LOG"
echo "logging to $LOG (Ctrl+C to stop)"

count=0
errors=0
trap 'echo; echo "requests: $count  non-2xx/errors: $errors"; exit 0' INT TERM

while true; do
  ts="$(date -u +%FT%T.%3NZ)"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 -H 'Host: apisix.test' "$URL" || echo "ERR")"
  echo "$ts $code" >> "$LOG"
  count=$((count + 1))
  case "$code" in
    2??) ;;
    *) errors=$((errors + 1)) ;;
  esac
  sleep "$INTERVAL"
done
