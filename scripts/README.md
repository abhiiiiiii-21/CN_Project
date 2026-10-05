# Operational Scripts

This directory contains shell automation scripts for certificate provisioning, configuration rendering, and automated demonstration workflows across the 3-Mac architecture.

---

## Script Overview

| Script | Purpose | Supported Subcommands / Flags |
|---|---|---|
| `make-certs.sh` | Generates a team Certificate Authority (CA) and issues TLS certificates with SAN for `app.TEAM.test` and `api.TEAM.test` on Mac 2. Safely prevents overwriting existing CAs. | Run directly on Mac 2: `./scripts/make-certs.sh` (or `CN_ENV=/path/to/env ./scripts/make-certs.sh`). |
| `render-configs.sh` | Reads environment variables from `cn-team.env` and renders template files from `config/` into `config/live/`. | Run with env path or defaults: `./scripts/render-configs.sh [path/to/env]`. |
| `demo.sh` | Read-only verification suite diagnosing LAN connectivity, DNS resolution, backends, load balancing, TLS trust, HTTP protocol, caching, and layered health. | `./scripts/demo.sh [lan\|dns\|backends\|lb\|tls\|http\|cache\|check\|all]` |

---

## Usage Instructions

### 1. `scripts/make-certs.sh`
Run on **Mac 2** to provision the Root CA and issue the edge server certificate with Subject Alternative Names (`DNS:app.$TEAM.test`, `DNS:api.$TEAM.test`):
```bash
./scripts/make-certs.sh
```
- Outputs `team-CA.key` and `team-CA.pem` to `~/team-certs/`.
- Issues `app.key` and `app.crt` to `~/team-certs/` and deploys them to `$(brew --prefix)/etc/nginx/certs/`.
- Safe guard: If `~/team-certs/team-CA.key` already exists, the script stops safely without overwriting.
- Distribution: Distribute **ONLY** `team-CA.pem` to client machines (`Mac 1`, `Mac 3`, etc.). Never distribute private keys (`*.key`).

### 2. `scripts/render-configs.sh`
Generates live deployment files from templates into `config/live/`:
```bash
./scripts/render-configs.sh
```
Renders:
- `config/live/dnsmasq.conf` (Mac 1)
- `config/live/team-http.conf` (Mac 2: Port 8080 redirect to 8443)
- `config/live/team-https.conf` (Mac 2: Port 8443 TLS reverse proxy & load balancer)

### 3. `scripts/demo.sh`
Executes read-only automated checks and diagnostics. Does not alter system or service configurations.
```bash
# Run complete end-to-end demo
./scripts/demo.sh all

# Or run individual verification suites:
./scripts/demo.sh lan        # Verifies 3-Mac reachability (ICMP/TCP)
./scripts/demo.sh dns        # Verifies app and api resolve to Mac 2, nothere returns NXDOMAIN
./scripts/demo.sh backends   # Verifies direct Mac 3:3001 and :3002 status and ETag consistency
./scripts/demo.sh lb         # Dispatches 6+ requests via HTTPS showing X-Backend and X-Upstream-Addr
./scripts/demo.sh tls        # Verifies TLS handshake, trusted Root CA, SAN, issuer without -k
./scripts/demo.sh http       # Verifies HTTP/1.1, HTTP/2, and 8080 -> 8443 redirection
./scripts/demo.sh cache      # Verifies /api/info (ETag, 304) and /api/status (no-store)
./scripts/demo.sh check      # Layered pipeline diagnosis (DNS -> TCP -> TLS -> HTTP)
```
