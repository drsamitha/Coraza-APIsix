#!/usr/bin/env bash
# Test 2 (etcd config hot-sync path, contrast case):
# Flips SecRuleEngine On/Off on the live route via the Admin API. This only
# rewrites the route's `conf` in etcd - every APISIX worker watches etcd and
# swaps it into shared memory on its own. No `apisix reload` call here at
# all, no nginx worker restart. Run scripts/load-test.sh in the background
# first so you have traffic in flight while this runs.
#
# Usage: ./toggle-etcd-rule.sh On|Off
set -euo pipefail

STATE="${1:?usage: toggle-etcd-rule.sh On|Off}"
ADMIN="http://127.0.0.1:9180"
KEY="edd1c9f034335f136f87ad84b625c8f"

echo "$(date -u +%FT%TZ) setting SecRuleEngine $STATE via Admin API (etcd write, no reload)"
curl -sS -o /dev/null -w '%{http_code}\n' \
  "$ADMIN/apisix/admin/routes/1" -X PATCH \
  -H "X-API-KEY: $KEY" -d "{
    \"plugins\": {
      \"coraza-filter\": {
        \"conf\": {
          \"directives_map\": {
            \"default\": [
              \"SecDebugLogLevel 9\",
              \"SecRuleEngine $STATE\",
              \"Include @crs-setup-conf\",
              \"Include @owasp_crs/*.conf\"
            ]
          },
          \"default_directives\": \"default\"
        }
      }
    }
  }"
echo "$(date -u +%FT%TZ) etcd write returned"
