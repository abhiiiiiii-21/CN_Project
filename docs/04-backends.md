# Backend Services Architecture

## Overview

The application backend layer is hosted entirely on **Mac 3**. To validate multi-instance load balancing, failover, and session independence without requiring additional physical hardware, Mac 3 runs two distinct backend instances as isolated concurrent processes.

> **Important:** There is **NO Mac 4**. Both Backend A and Backend B execute on Mac 3.

---

## Service Specifications

| Instance | Host | Port | Launch Command | Identifying Header |
|---|---|---|---|---|
| **Backend A** | Mac 3 (`MAC3_IP`) | TCP 3001 | `python3 backend/server.py A 3001` | `X-Backend: A` |
| **Backend B** | Mac 3 (`MAC3_IP`) | TCP 3002 | `python3 backend/server.py B 3002` | `X-Backend: B` |

Both instances share a single implementation file (`backend/server.py`) parameterized by instance name and listening port via command-line arguments.

---

## Response Headers & Behavior

Every HTTP response produced by the backend includes metadata headers to allow the edge proxy and client to distinguish which backend handled the request:

```http
HTTP/1.1 200 OK
Content-Type: application/json
X-Backend: A
ETag: "hash-value"
Cache-Control: public, max-age=60
```

- When contacting instance A directly or via proxy: `X-Backend: A`
- When contacting instance B directly or via proxy: `X-Backend: B`

---

## Direct Backend Verification

Before verifying through the Mac 2 load balancer, each backend must be tested directly from Mac 2 or Mac 3:

```bash
# Test Backend A
curl -i http://MAC3_IP:3001/
# Verify HTTP 200 and header 'X-Backend: A'

# Test Backend B
curl -i http://MAC3_IP:3002/
# Verify HTTP 200 and header 'X-Backend: B'
```

---

## TODO: Future Implementation & Documentation

- [ ] Implement `backend/server.py` supporting dynamic port binding, `X-Backend` header injection, and caching headers (`ETag`, `Cache-Control`).
- [ ] Add JSON response payload format specifications (`instance`, `timestamp`, `client_ip`, `uptime`).
- [ ] Implement `/health` and `/status` endpoints for health checking.
- [ ] Record direct verification terminal logs in `evidence/C-backends/`.
