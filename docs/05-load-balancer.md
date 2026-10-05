# Load Balancer & Reverse Proxy Configuration

## Overview

**Mac 2** functions as the network's edge reverse proxy and Layer 7 load balancer powered by `nginx`. It receives ingress traffic from client devices on HTTP port 8080 and HTTPS port 8443, terminates TLS connections, and distributes requests across the upstream backend pool on Mac 3.

---

## Upstream Pool Configuration

The load balancer upstream pool consists of the two backend instances on **Mac 3**:

```nginx
upstream team_backend {
    server MAC3_IP:3001;
    server MAC3_IP:3002;
}
```

Both backend instances run concurrently as isolated processes on Mac 3. When generating deployable configuration via `./scripts/render-configs.sh`, the placeholder `MAC3_IP` is replaced by the actual host IP defined in `~/cn-team.env` (e.g. `10.7.21.145`).

---

## Load Balancing & Reverse Proxy Mechanics

### 1. Reverse Proxying & Port Roles
Nginx acts as the single point of ingress for the application domain names (`app.team1.test` and `api.team1.test`):
- **Port 8080 (HTTP):** Standard HTTP plaintext listener that automatically redirects all incoming requests to HTTPS on port 8443 (`return 301 https://$host:8443$request_uri;`).
- **Port 8443 (HTTPS):** Encrypted HTTPS listener that terminates TLS 1.2 / 1.3, negotiates HTTP/2 via ALPN, decrypts requests, and proxies them over HTTP/1.1 to Mac 3 backends.

Nginx injects standard proxy headers into the upstream request:
- `Host: $host`
- `X-Real-IP: $remote_addr`
- `X-Forwarded-For: $proxy_add_x_forwarded_for`
- `X-Forwarded-Proto https`
- `add_header X-Upstream-Addr $upstream_addr always;` (returns the upstream IP:port in response headers)

### 2. Round-Robin Distribution
By default, Nginx distributes incoming client requests across the upstream servers in round-robin fashion:
- Upstream target 1: `$MAC3_IP:3001` (Backend A on Mac 3)
- Upstream target 2: `$MAC3_IP:3002` (Backend B on Mac 3)

> **Note on Sequence:** While round-robin scheduling balances load evenly across backend workers, connection keep-alive, TCP session reuse, or HTTP/2 stream multiplexing from a single client can influence the observed distribution sequence. A strictly alternating sequence is an observed lab result under discrete connections, not a universal protocol guarantee under all connection patterns. Overall distribution balances across both backends.

### 3. High-Availability Failover
Failover is controlled via Nginx upstream error handling directives:
- `proxy_connect_timeout 2s;`
- `proxy_read_timeout 5s;`
- `proxy_next_upstream error timeout http_502 http_503;`

If Backend A stops responding or encounters an error, Nginx transparently re-routes the pending client request to Backend B without returning a failure to the user.

---

## Ingress Ports and Protocols

| Port | Protocol | Security | Role / Upstream Target |
|---|---|---|---|
| **8080** | HTTP | Plaintext | HTTP Ingress -> 301 Redirect to `https://$host:8443$request_uri` |
| **8443** | HTTPS | TLS 1.2 / 1.3 | TLS Termination -> `http://team_backend` (Mac 3:3001 / Mac 3:3002) |

---

## Verification Procedures

### Load Balancing Check
```bash
for i in {1..6}; do
    /usr/bin/curl -s https://app.team1.test:8443/api/status
    echo
done
```
**Observed Output (from evidence):**
```text
{"backend": "A", "status": "ok", "time": "2026-10-05T15:01:22.838067+00:00"}
{"backend": "B", "status": "ok", "time": "2026-10-05T15:01:22.958487+00:00"}
{"backend": "A", "status": "ok", "time": "2026-10-05T15:01:23.009835+00:00"}
{"backend": "B", "status": "ok", "time": "2026-10-05T15:01:23.050413+00:00"}
{"backend": "A", "status": "ok", "time": "2026-10-05T15:01:23.088991+00:00"}
{"backend": "B", "status": "ok", "time": "2026-10-05T15:01:23.124942+00:00"}
```

---

## Evidence Artifacts

- [lb-alternating.jpeg](../evidence/D-load-balancing/lb-alternating.jpeg): Terminal output capturing 6 consecutive requests through Mac 2 showing alternating backend responses (`"backend": "A"` and `"backend": "B"`).
- [f3-backend-stopped.png](../evidence/failures/f3-backend-stopped.png): Demonstrates upstream failover to Backend B when Backend A is stopped.

---

## Implementation & Testing Notes

- Upstream failover response latency under simulated crashes: *Not measured in Phase 1*.
- Nginx access log formatting for `$upstream_addr` and `$request_time`: Handled via injected response header `X-Upstream-Addr: $upstream_addr`.
