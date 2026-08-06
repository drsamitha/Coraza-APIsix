# Phase 1: single coraza-proxy-wasm binary (official pre-built release),
# just enough to stand up APISIX + Coraza + CRS and validate the etcd
# config hot-sync reload path (SecRuleEngine toggle via Admin API).
#
# The wasm-binary/CRS-version swap-reload test (two binaries baked in,
# built from source with different CRS versions) is phase 2 - see
# apisix/Dockerfile.multi-crs once that lands.

FROM apache/apisix:3.8.0-debian
ARG CORAZA_PROXY_WASM_VERSION=0.5.0

USER root
ADD https://github.com/corazawaf/coraza-proxy-wasm/releases/download/${CORAZA_PROXY_WASM_VERSION}/coraza-proxy-wasm-${CORAZA_PROXY_WASM_VERSION}.zip /tmp/coraza-proxy-wasm.zip
RUN mkdir -p /usr/local/apisix/proxywasm \
    && apt-get update && apt-get install -y --no-install-recommends unzip \
    && unzip /tmp/coraza-proxy-wasm.zip -d /usr/local/apisix/proxywasm \
    && mv /usr/local/apisix/proxywasm/main.wasm /usr/local/apisix/proxywasm/coraza-proxy-wasm.wasm 2>/dev/null || true \
    && rm -f /tmp/coraza-proxy-wasm.zip \
    && apt-get remove -y unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/* \
    && chown -R apisix:apisix /usr/local/apisix/proxywasm

COPY config.yaml /usr/local/apisix/conf/config.yaml
RUN chown apisix:apisix /usr/local/apisix/conf/config.yaml
USER apisix
