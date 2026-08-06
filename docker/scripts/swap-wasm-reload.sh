#!/usr/bin/env bash
# NOTE: targets the phase-2 multi-CRS-version Dockerfile (see
# build-crs-variant.sh) - won't find a matching binary against the current
# phase-1 image, which only bakes in one coraza-proxy-wasm.wasm.
#
# Test 1 (wasm-binary / CRS-version reload path):
# Points config.yaml's wasm.plugins[0].file at the other CRS-version binary
# already baked into the image, then runs `apisix reload` - APISIX's
# graceful nginx-worker reload (new workers get the new binary, old workers
# drain in-flight requests and exit; no container restart, no dropped
# connections expected). Run scripts/load-test.sh in the background before
# calling this so you have traffic in flight during the swap.
#
# Usage: ./swap-wasm-reload.sh 4.4.0
set -euo pipefail

CRS_VERSION="${1:?usage: swap-wasm-reload.sh <CRS_VERSION>}"
CONTAINER="coraza-test-apisix"
WASM_PATH="/usr/local/apisix/proxywasm/coraza-proxy-wasm-${CRS_VERSION}.wasm"

docker exec "$CONTAINER" test -f "$WASM_PATH" || {
  echo "error: $WASM_PATH not found in container - was the image built with CRS_VERSION_A/B=${CRS_VERSION}?" >&2
  exit 1
}

echo "$(date -u +%FT%TZ) swapping wasm.plugins[0].file -> $WASM_PATH"
docker exec "$CONTAINER" sh -c "
  sed -i 's#file: /usr/local/apisix/proxywasm/coraza-proxy-wasm-.*\.wasm#file: $WASM_PATH#' /usr/local/apisix/conf/config.yaml
"

echo "$(date -u +%FT%TZ) apisix reload starting"
docker exec "$CONTAINER" apisix reload
echo "$(date -u +%FT%TZ) apisix reload returned"
