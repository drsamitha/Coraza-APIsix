#!/usr/bin/env bash
# Pushes an upstream + route into etcd via the Admin API, protecting the
# httpbin demo service with the coraza-filter wasm plugin + full OWASP CRS.
set -euo pipefail

ADMIN="http://127.0.0.1:9180"
KEY="edd1c9f034335f136f87ad84b625c8f"

curl -sS -o /dev/null -w 'upstream: %{http_code}\n' \
  "$ADMIN/apisix/admin/upstreams/1" -X PUT \
  -H "X-API-KEY: $KEY" -d '{
    "type": "roundrobin",
    "nodes": { "httpbin:8080": 1 }
  }'

curl -sS -o /dev/null -w 'route: %{http_code}\n' \
  "$ADMIN/apisix/admin/routes/1" -X PUT \
  -H "X-API-KEY: $KEY" -d '{
    "name": "coraza-demo",
    "uri": "/*",
    "upstream_id": "1",
    "plugins": {
      "coraza-filter": {
        "conf": {
          "directives_map": {
            "default": [
              "SecDebugLogLevel 9",
              "SecRuleEngine On",
              "Include @crs-setup-conf",
              "Include @owasp_crs/*.conf"
            ]
          },
          "default_directives": "default"
        }
      }
    }
  }'

echo "route + upstream pushed. Smoke test (Host header avoids the CRS"
echo "numeric-IP-host rule so a clean baseline actually returns 200):"
echo "  clean request : curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: apisix.test' 'http://127.0.0.1:9080/anything'"
echo "  should be blocked (403) by CRS SQLi rules:"
echo "  curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: apisix.test' -G 'http://127.0.0.1:9080/anything' --data-urlencode \"id=1' OR '1'='1\""
