#!/usr/bin/env bash
# NOTE: targets the phase-2 multi-CRS-version Dockerfile, not yet landed -
# apisix/Dockerfile currently builds a single pre-built coraza-proxy-wasm
# binary (phase 1, used to validate the etcd hot-sync path). This script
# and swap-wasm-reload.sh will work once Dockerfile grows the two
# from-source builder stages (CRS_VERSION_A/CRS_VERSION_B build args) again.
#
# Rebuilds the apisix image with a chosen pair of CRS minor versions baked
# in as the two swappable wasm binaries (see apisix/Dockerfile).
#
# Usage: ./build-crs-variant.sh [CRS_VERSION_A] [CRS_VERSION_B]
# Defaults: 4.3.0 4.4.0
set -euo pipefail
cd "$(dirname "$0")/.."

CRS_VERSION_A="${1:-4.3.0}"
CRS_VERSION_B="${2:-4.4.0}"

echo "Building apisix image with CRS ${CRS_VERSION_A} + ${CRS_VERSION_B}..."
docker compose build \
  --build-arg CRS_VERSION_A="$CRS_VERSION_A" \
  --build-arg CRS_VERSION_B="$CRS_VERSION_B" \
  apisix

echo "Done. Binaries inside the image:"
echo "  /usr/local/apisix/proxywasm/coraza-proxy-wasm-${CRS_VERSION_A}.wasm"
echo "  /usr/local/apisix/proxywasm/coraza-proxy-wasm-${CRS_VERSION_B}.wasm"
