# HTTP Caching & Conditional Requests

## Overview

This document specifies the caching semantics implemented by the backend application on **Mac 3** and proxied through the **Mac 2** edge reverse proxy. It covers cache validation directives, entity tags (`ETag`), conditional request handling (`If-None-Match`), and dynamic non-cacheable endpoints as implemented in [backend/server.py](../backend/server.py).

---

## Caching Endpoints & Headers

### 1. Cacheable Metadata Endpoint (`/api/info`)
- **Route:** `GET /api/info`
- **Response Headers:**
  ```http
  HTTP/1.1 200 OK
  Content-Type: application/json
  Content-Length: 97
  X-Backend: A
  Cache-Control: public, max-age=60
  ETag: "6402143662621d1b"
  ```
- **Payload:**
  ```json
  {"service": "team-app", "version": "1.0.0", "note": "This content is identical on every backend"}
  ```
- **Semantics:**
  - `Cache-Control: public, max-age=60`: Tells client browsers and intermediate caches that the response is fresh for 60 seconds.
  - `ETag`: Content-based entity tag computed via SHA-1 digest of the serialized payload body (`"6402143662621d1b"`).

### 2. Dynamic Real-Time Status Endpoint (`/api/status`)
- **Route:** `GET /api/status`
- **Response Headers:**
  ```http
  HTTP/1.1 200 OK
  Content-Type: application/json
  Content-Length: 76
  X-Backend: A
  Cache-Control: no-store
  ```
- **Payload:**
  ```json
  {"backend": "A", "status": "ok", "time": "2026-10-05T16:33:43.364592+00:00"}
  ```
- **Semantics:**
  - `Cache-Control: no-store`: Instructs all clients and intermediary proxies never to store or cache any portion of the response. Every request must be forwarded to the backend to generate a fresh timestamp.

---

## Conditional Requests and HTTP 304 Validation

When a client holds a cached representation of `/api/info` and needs to revalidate its freshness, it issues a conditional GET request supplying the saved tag in the `If-None-Match` header.

### Protocol Interaction Flow

```text
Client (Browser / cURL)              Mac 2 (Edge Nginx)              Mac 3 (server.py)
   │                                         │                                │
   │ 1. GET /api/info ──────────────────────>│ 2. Proxy Pass ────────────────>│
   │                                         │                                │ (Computes ETag)
   │ 4. 200 OK (ETag: "6402143662621d1b") <──│ 3. 200 OK + ETag <────────────│
   │                                         │                                │
   │ [Cache stored locally for 60s]          │                                │
   │                                         │                                │
   │ 5. GET /api/info                        │                                │
   │    If-None-Match: "6402143662621d1b" ──>│ 6. Proxy Pass ────────────────>│
   │                                         │                                │ (Matches ETag)
   │ 8. 304 Not Modified (Empty Body) <──────│ 7. 304 Not Modified <──────────│
```

1. **Initial Request:** The client requests `GET /api/info`. The server responds with `HTTP 200 OK`, `Cache-Control: public, max-age=60`, the JSON payload, and `ETag: "6402143662621d1b"`.
2. **Conditional Revalidation:** The client sends `If-None-Match: "6402143662621d1b"`.
3. **Cache Hit (Unmodified):** The backend compares the header against `INFO_ETAG`. Because the content has not changed, the server emits `HTTP 304 Not Modified` without a response body, saving network bandwidth.
4. **Cache Miss (Modified):** If the resource changed, the backend would return `HTTP 200 OK` with the new ETag and updated payload body.

---

## Verification Commands

Verification should be performed through the edge reverse proxy using HTTPS:

### 1. Initial Fetch of Cacheable Resource
```bash
/usr/bin/curl -i https://app.$TEAM.test:8443/api/info
```
**Verification Points:**
- Status: `HTTP/2 200`
- `Cache-Control: public, max-age=60`
- `ETag: "6402143662621d1b"`

### 2. Conditional Request with `If-None-Match`
```bash
ETAG=$(/usr/bin/curl -sI https://app.$TEAM.test:8443/api/info | grep -i "^ETag:" | awk '{print $2}' | tr -d '\r')
/usr/bin/curl -i -H "If-None-Match: $ETAG" https://app.$TEAM.test:8443/api/info
```
**Expected Output:**
```http
HTTP/2 304 
x-backend: A
cache-control: public, max-age=60
etag: "6402143662621d1b"
x-upstream-addr: 10.7.29.148:3001
```
*(Response body is empty; status code is 304).*

### 3. Dynamic No-Store Verification
```bash
/usr/bin/curl -i https://app.$TEAM.test:8443/api/status
```
**Expected Output:**
```http
HTTP/2 200
x-backend: A
cache-control: no-store
x-upstream-addr: 10.7.29.148:3001
```

---

## Evidence Artifacts

The caching protocol interaction has been fully captured and validated:
- [caching.png](../evidence/F-caching/caching.png): Documents `Cache-Control: public, max-age=60` and `ETag: "6402143662621d1b"` on `/api/info`, conditional request revalidation, and `Cache-Control: no-store` on `/api/status`.

---

## Implementation & Testing Notes

- Browser DevTools Network tab verification: Tested and confirmed 304 / disk-cache behavior.
- ETag computation and conditional handling are fully implemented in `backend/server.py`.
