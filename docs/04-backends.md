# Backend Services Architecture

## Overview

The application backend layer is hosted entirely on **Mac 3**. To validate multi-instance load balancing, failover, and session independence without requiring additional physical hardware, Mac 3 runs two distinct backend instances as isolated concurrent processes.

Both Backend A and Backend B execute on **Mac 3**.

---

## Service Specifications

| Instance | Host | Port | Launch Command | Identifying Header |
|---|---|---|---|---|
| **Backend A** | Mac 3 (`10.7.29.148`) | TCP 3001 | `python3 backend/server.py A 3001` | `X-Backend: A` |
| **Backend B** | Mac 3 (`10.7.29.148`) | TCP 3002 | `python3 backend/server.py B 3002` | `X-Backend: B` |

Both instances share a single implementation file (`backend/server.py`) parameterized by instance name and listening port via command-line arguments:

```bash
# Terminal 1 on Mac 3: Backend A
python3 backend/server.py A 3001

# Terminal 2 on Mac 3: Backend B
python3 backend/server.py B 3002
```

---

## LAN Access from Mac 2 Nginx

Nginx running on **Mac 2** communicates with both backend services over the local area network (LAN):
- Mac 2 routes traffic to `10.7.29.148:3001` (Backend A on Mac 3)
- Mac 2 routes traffic to `10.7.29.148:3002` (Backend B on Mac 3)

Because both backend processes bind to `0.0.0.0`, they accept socket connections arriving on `en0` across the private subnet (`10.7.x.x`).

---

## Response Headers & Behavior

Every HTTP response produced by the backend includes metadata headers to allow the edge proxy and client to distinguish which backend handled the request:

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Content-Length: 320
X-Backend: A
ETag: "4ccee0b9ba9bdda2ff421ac57a251249"
Cache-Control: public, max-age=60
```

- When contacting instance A directly or via proxy: `X-Backend: A`
- When contacting instance B directly or via proxy: `X-Backend: B`

### Endpoints Supported by `server.py`
1. `GET /`: Cacheable index payload containing service metadata, `ETag`, and `Cache-Control: public, max-age=60`. Evaluates `If-None-Match` and returns `304 Not Modified` when hashes match.
2. `GET /status` or `GET /health`: Dynamic JSON status payload with server timestamp, uptime, client IP, and `Cache-Control: no-store, no-cache, must-revalidate`.
3. `GET /api`: API service metadata endpoint.

---

## Direct Backend Verification

Before testing through the Mac 2 load balancer, each backend service can be verified directly:

```bash
# From Mac 3 (locally) or Mac 2 (over LAN):
curl -i http://10.7.29.148:3001/
# Verify HTTP 200 and header 'X-Backend: A'

curl -i http://10.7.29.148:3002/
# Verify HTTP 200 and header 'X-Backend: B'
```

---

## TODO: Future Implementation & Documentation

- [ ] Measure individual backend response latencies under concurrent load.
- [ ] Add JSON response payload format specifications (`instance`, `timestamp`, `client_ip`, `uptime`).
- [ ] Record direct verification terminal logs in `evidence/C-backends/`.
