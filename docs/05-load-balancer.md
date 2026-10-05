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

With current network parameters, `MAC3_IP` resolves to `10.7.29.148`. Both servers execute concurrently on Mac 3.

---

## Load Balancing & Reverse Proxy Mechanics

### 1. Reverse Proxying
Nginx acts as the single point of entry for the application domain names (`app.team1.test` and `api.team1.test`). Ingress traffic from clients is accepted on:
- **Port 8080**: Standard HTTP plaintext communication.
- **Port 8443**: Encrypted HTTPS communication terminated at Nginx.

Nginx strips TLS overhead (on port 8443) and forwards plain HTTP requests internally to the upstream pool, injecting standard proxy headers:
- `Host: $host`
- `X-Real-IP: $remote_addr`
- `X-Forwarded-For: $proxy_add_x_forwarded_for`
- `X-Forwarded-Proto: $scheme`

### 2. Round-Robin Scheduling
By default, Nginx distributes incoming client requests across the upstream servers in sequential round-robin fashion:
- Request 1 → `MAC3_IP:3001` (Backend A on Mac 3)
- Request 2 → `MAC3_IP:3002` (Backend B on Mac 3)
- Request 3 → `MAC3_IP:3001` (Backend A on Mac 3)
- Request 4 → `MAC3_IP:3002` (Backend B on Mac 3)

### 3. High-Availability Failover
Failover is controlled via Nginx upstream error handling directives:
- `proxy_connect_timeout 2s;`
- `proxy_read_timeout 5s;`
- `proxy_next_upstream error timeout http_502 http_503;`

If Backend A stops responding or encounters an error, Nginx transparently re-routes the pending client request to Backend B without returning a failure to the user.

---

## Ingress Ports and Protocols

| Port | Protocol | Security | Upstream Target |
|---|---|---|---|
| **8080** | HTTP | Plaintext | `http://team_backend` (Mac 3:3001 / Mac 3:3002) |
| **8443** | HTTPS | TLS 1.2 / 1.3 | `http://team_backend` (Mac 3:3001 / Mac 3:3002) |

---

## Verification Procedures

### Sequential Load Balancing Check
```bash
for i in {1..4}; do
    curl -sI http://app.team1.test:8080/ | grep -i "X-Backend:"
done
```
**Expected Output:**
```text
X-Backend: A
X-Backend: B
X-Backend: A
X-Backend: B
```

### Failover Check
1. Stop Backend A on Mac 3 (`Ctrl+C` in Terminal 1).
2. Execute requests against Mac 2:
```bash
curl -sI http://app.team1.test:8080/ | grep -i "X-Backend:"
```
**Expected Output:** All requests resolve to `X-Backend: B` with HTTP 200 status.

---

## TODO: Future Implementation & Documentation

- [ ] Tune upstream keepalive connections for HTTP/1.1 backend pooling.
- [ ] Measure failover response latency under simulated backend crashes.
- [ ] Document access log format capturing `$upstream_addr`, `$status`, and `$request_time`.
- [ ] Store alternating curl traces in `evidence/D-load-balancing/`.
