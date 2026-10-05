# HTTP Caching & Conditional Requests

## Overview

This document specifies the caching semantics implemented by the backend application on **Mac 3** and proxied through the **Mac 2** edge. It covers cache validation directives, entity tags (`ETag`), conditional request handling (`If-None-Match`), and dynamic non-cacheable endpoints.

---

## Caching Headers & Directives

### 1. `Cache-Control`
- **Static / Cacheable Resources (`/` or `/static`):**
  ```http
  Cache-Control: public, max-age=60
  ```
  Instructs client browsers and intermediary proxies that the payload can be cached locally for up to 60 seconds.
- **Dynamic / Real-time Status (`/status` or `/health`):**
  ```http
  Cache-Control: no-store, no-cache, must-revalidate
  ```
  Ensures client devices and proxies never store responses, forcing an end-to-end fetch on every invocation.

### 2. `ETag` (Entity Tag)
The backend generates a content-based digest (e.g., MD5 or SHA-256 hash of the response payload):
```http
ETag: "9f8a3c2e1b4a"
```

---

## Conditional Requests and HTTP 304

When a cached response expires or requires revalidation, the client sends a conditional GET request including the stored `ETag` in the `If-None-Match` request header.

### Flow Diagram

```text
Client                              Mac 2 / Mac 3
  │                                       │
  │─── 1. GET / ─────────────────────────>│
  │<── 2. 200 OK (ETag: "abc123") ────────│
  │                                       │
  │ [Cache expired / Revalidation]        │
  │                                       │
  │─── 3. GET / (If-None-Match: "abc123")>│
  │<── 4. 304 Not Modified ───────────────│ (No body transferred)
```

1. **Initial Request:** Client issues `GET /`. The server returns `200 OK`, payload data, and an `ETag: "abc123"`.
2. **Conditional Revalidation:** Subsequent request sends `If-None-Match: "abc123"`.
3. **Response:** If content has not changed, backend returns `304 Not Modified` with an empty response body, preserving network bandwidth.
4. **Modified Content:** If content has changed, backend returns `200 OK` with the new `ETag` and updated body.

---

## Verification Commands

### Initial Fetch (Obtaining ETag)
```bash
curl -i http://app.team1.test:8080/
```
*Note the returned `ETag` header (e.g., `ETag: "hash123"`).*

### Conditional Request (Expecting 304)
```bash
curl -i -H 'If-None-Match: "hash123"' http://app.team1.test:8080/
```
*Verify response status is `HTTP/1.1 304 Not Modified` and Content-Length is 0.*

### Dynamic No-Store Endpoint Check
```bash
curl -i http://app.team1.test:8080/status
```
*Verify response contains `Cache-Control: no-store`.*

---

## TODO: Future Implementation & Documentation

- [ ] Implement ETag computation logic in `backend/server.py`.
- [ ] Add conditional `If-None-Match` header parser and 304 response generator.
- [ ] Record header traces for both 200 OK and 304 Not Modified in `evidence/F-caching/`.
- [ ] Document browser DevTools Network tab caching behavior.
