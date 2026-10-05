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

Both instances share a single implementation file ([backend/server.py](../backend/server.py)) parameterized by instance name and listening port via command-line arguments:

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
- `X-Backend: A` when served by instance A
- `X-Backend: B` when served by instance B

### Endpoints Supported by `backend/server.py`

The implementation in `backend/server.py` defines the following exact routes:

1. **`GET /` — Basic Backend Response**
   - Returns JSON containing server confirmation and local hostname:
     ```json
     {"message": "Backend A is running", "host": "Kapishs-MacBook-Pro-2.local"}
     ```
   - Headers: `Content-Type: application/json`, `X-Backend: A` (or `B`).

2. **`GET /api/status` — Dynamic Status Endpoint**
   - Returns real-time timestamp and operational status:
     ```json
     {"backend": "A", "status": "ok", "time": "2026-10-05T16:33:43.364592+00:00"}
     ```
   - Headers: `Cache-Control: no-store`, `Content-Type: application/json`, `X-Backend: A` (or `B`).
   - Ensures clients and proxies never cache live health and status information.

3. **`GET /api/info` — Cacheable Static Metadata Endpoint**
   - Returns service metadata identical across backends:
     ```json
     {"service": "team-app", "version": "1.0.0", "note": "This content is identical on every backend"}
     ```
   - Headers: `Cache-Control: public, max-age=60`, `ETag: "6402143662621d1b"`, `X-Backend: A` (or `B`).
   - Evaluates incoming `If-None-Match` header: if the ETag matches, replies with `304 Not Modified` and an empty body.

*(Note: Legacy paths such as `/status`, `/health`, or `/api` are not implemented in `backend/server.py` and return `404 {"error": "not found"}` with the identifying `X-Backend` header).*

---

## Direct Backend Verification

Before testing through the Mac 2 load balancer, each backend service can be verified directly on Mac 3:

```bash
# 1. Verify dynamic status on Backend A
curl -i http://10.7.29.148:3001/api/status
# Expected: HTTP 200, X-Backend: A, Cache-Control: no-store

# 2. Verify dynamic status on Backend B
curl -i http://10.7.29.148:3002/api/status
# Expected: HTTP 200, X-Backend: B, Cache-Control: no-store

# 3. Verify cacheable endpoint on Backend A
curl -i http://10.7.29.148:3001/api/info
# Expected: HTTP 200, X-Backend: A, Cache-Control: public, max-age=60, ETag: "6402143662621d1b"

# 4. Verify cacheable endpoint on Backend B
curl -i http://10.7.29.148:3002/api/info
# Expected: HTTP 200, X-Backend: B, Cache-Control: public, max-age=60, ETag: "6402143662621d1b"
```

---

## Evidence Artifacts

Direct verification has been executed and confirmed:
- [backend-a.png](../evidence/C-backends/backend-a.png): Shows Backend A process listening on `:3001`, returning `X-Backend: A`, `/api/status` with `no-store`, and `/api/info` with `ETag: "6402143662621d1b"`.
- [backend-b.png](../evidence/C-backends/backend-b.png): Shows Backend B process listening on `:3002`, returning `X-Backend: B`, `/api/status`, and matching `ETag` on `/api/info`.

---

## Implementation & Testing Notes

- Concurrent load response latency benchmarks: *Not measured in Phase 1*.
- Payload formats and route handlers are fully implemented and verified in `backend/server.py`.
