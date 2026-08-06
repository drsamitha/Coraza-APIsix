# Coraza-APIsix

Docker Compose setup that puts the [Coraza](https://coraza.io/) WAF, running
the OWASP Core Rule Set (CRS), in front of Apache APISIX. Coraza runs as a
[coraza-proxy-wasm](https://github.com/corazawaf/coraza-proxy-wasm) filter
loaded by APISIX's Wasm plugin runtime.

## Stack

| Service  | Image                              | Role                                |
|----------|-------------------------------------|--------------------------------------|
| etcd      | `quay.io/coreos/etcd`               | APISIX configuration store           |
| apisix    | built from `apisix/Dockerfile`      | API gateway + Coraza WAF (CRS)       |
| httpbin   | `mccutchen/go-httpbin`              | Demo upstream service                |
| dashboard | `apache/apisix-dashboard`           | Web UI for routes and plugin config  |

## Prerequisites

- Docker and Docker Compose

## Quick start

```bash
docker compose up -d --build
./scripts/push-route.sh
```

`push-route.sh` registers the demo upstream and a route protected by the
Coraza WAF plugin with the full CRS rule set enabled.

Verify it's working:

```bash
# clean request -> 200
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: apisix.test' \
  http://127.0.0.1:9080/anything

# SQL injection pattern -> 403 (blocked by CRS)
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: apisix.test' \
  -G http://127.0.0.1:9080/anything --data-urlencode "id=1' OR '1'='1"
```

A `Host` header other than the raw IP is used because CRS flags numeric-IP
hosts by default.

## Ports

| Port | Purpose            |
|------|---------------------|
| 9080 | APISIX data plane   |
| 9180 | APISIX Admin API    |
| 8080 | httpbin (direct)    |
| 2379 | etcd client API     |
| 9000 | Dashboard UI        |

## Dashboard

A web UI is available at `http://localhost:9000` (login `admin` / `admin`).
It reads and writes the same etcd store as the Admin API, so routes,
upstreams, and the `coraza-filter` plugin's CRS directives can be viewed or
edited there directly, and changes take effect the same way as the CLI
scripts below — no reload needed.

Change the default credentials and secret in `dashboard/conf.yaml` before
using this outside a local test environment.

`dashboard/schema.json` is the dashboard's bundled plugin schema with a
`coraza-filter` entry added — the stock image doesn't recognize this
custom wasm plugin, so without it the dashboard refuses to save any route
that references it (`schema not found` error), in both the visual plugin
editor and the raw JSON editor.

### Custom rules: what actually works

`Include @crs-setup-conf` and `Include @owasp_crs/*.conf` look like
filesystem paths but aren't — CRS is compiled into the `.wasm` binary at
build time (Go's `embed`), and `@`-prefixed names are the only resources
the plugin can `Include`. There's no live directory to drop a `.conf`
file into, and no config option to allow one: pointing `Include` at a
real mounted file (e.g. `Include /tmp/custom.conf`) fails outright -
the wasm sandbox has no general filesystem access, and the plugin
rejects it with `failed to readfile: ... invalid name`, breaking the
route (`503`) until reverted.

The only way to add a custom rule that takes effect immediately is an
inline `SecRule` string appended to `directives_map.default`, via the
Admin API, the dashboard, or `scripts/toggle-etcd-rule.sh`'s pattern -
that's a plain JSON/etcd write, not a file read, so it hits the same
hot-sync path documented below.

**For a large ruleset**, inlining every rule as a `directives_map` string
doesn't scale (etcd value size limits, unreadable JSON). The only option
is the same one CRS itself uses: vendor the `.conf` files into
`coraza-proxy-wasm`'s source tree and compile them into a new `.wasm`
binary, then get APISIX to load it via `config.yaml`'s
`wasm.plugins[].file` path and `apisix reload` - not an etcd write, so
it's a different (and slower to iterate) path than the single-rule case
above.

This was verified directly: two builds of `coraza-proxy-wasm` (different
upstream versions, standing in for "rebuilt with a different ruleset")
were baked into one image, `config.yaml` was pointed at the second one,
and `apisix reload` was run while a request loop hit the route
continuously - zero dropped or errored requests across the swap.
`apisix reload` is a graceful nginx worker reload: new workers load the
new binary, old workers finish in-flight requests and exit, so this is
"hot" in the no-downtime sense even though it needs an explicit reload
command and a rebuilt binary, unlike the instant etcd path above.

One operational gotcha found in the process: if `config.yaml` is a
Docker bind-mounted single file (as it is here), editing it with
`sed -i` either fails outright (`Device or resource busy`, if run
inside the container) or silently stops working (if run on the host,
since `sed -i` replaces the file via rename, and the container's mount
stays pinned to the old, now-orphaned inode). Editing it in place
without a rename - e.g. `sed '...' file > tmp && cat tmp > file` run
inside the container - avoids both failure modes.

### Adding a custom rule via the GUI

1. Log in at `http://localhost:9000` (`admin` / `admin`).

   ![Login](docs/screenshots/01-login.png)

2. Open **Route**, where `coraza-demo` (the route from `push-route.sh`)
   is listed.

   ![Routes list](docs/screenshots/02-routes-list.png)

3. Use the row's **More → View** action, not **Configure** — the
   step-by-step wizard's plugin picker fails to render plugin cards in
   this dashboard build (a Monaco editor web-worker issue), so it's not
   usable for editing `coraza-filter`. **View** opens a raw JSON editor
   for the whole route instead.

   ![Raw Data Editor](docs/screenshots/03-raw-data-editor.png)

4. Add a rule to the `directives_map.default` array, e.g.:

   ```
   SecRule REQUEST_HEADERS:X-Custom-Block "@streq yes" "id:1001,phase:1,deny,status:403,msg:'custom GUI rule'"
   ```

   ![Custom rule added](docs/screenshots/04-custom-rule-added.png)

5. Click **Submit**. This writes straight to etcd, same as the Admin API
   scripts — no reload, and no dropped requests for traffic already in
   flight.

Verify it immediately:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: apisix.test' \
  http://127.0.0.1:9080/anything                                  # 200

curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: apisix.test' \
  -H 'X-Custom-Block: yes' http://127.0.0.1:9080/anything          # 403
```

## Testing config reload under load

APISIX propagates plugin configuration changes (e.g. route rules, WAF
settings) to every worker via its etcd watch, with no reload command and
no worker restart. `scripts/toggle-etcd-rule.sh` and `scripts/load-test.sh`
demonstrate this:

```bash
# terminal 1
./scripts/load-test.sh

# terminal 2
./scripts/toggle-etcd-rule.sh Off
./scripts/toggle-etcd-rule.sh On
```

Stop the load generator with Ctrl+C to see the request/error count, or
inspect the full log at `/tmp/coraza-load-test.log`.

## Repository layout

```
apisix/                 APISIX image (Dockerfile, config.yaml)
dashboard/               Dashboard config (conf.yaml, schema.json)
docker-compose.yml       Service definitions
docs/screenshots/        Dashboard walkthrough screenshots
scripts/
  push-route.sh           Registers the demo route and upstream
  load-test.sh            Continuous request generator
  toggle-etcd-rule.sh      Toggles SecRuleEngine via the Admin API
```
