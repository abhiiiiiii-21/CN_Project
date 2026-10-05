# System Architecture Specification

## Overview

The **Private Network Service Platform** is an isolated multi-tier network deployment designed to demonstrate core computer networking concepts: private DNS resolution, edge reverse proxying, Layer 7 load balancing, TLS termination, HTTP caching semantics, and deep packet inspection.

The entire topology is deployed across **exactly three physical Mac computers** communicating over a shared local area network (LAN).

> **Important:** There is **NO Mac 4** in this architecture. Both backend application servers run as separate concurrent processes on Mac 3.

---

## Node Roles and Allocation

| Machine | Role | Software / Service | Ports | Description |
|---|---|---|---|---|
| **Mac 1** | Private DNS Server & Test Client | `dnsmasq` | UDP 53 | Resolves team local domain records (`app.team1.test`, `api.team1.test`) to Mac 2; forwards external queries to upstream resolvers. |
| **Mac 2** | Edge Proxy & Load Balancer | `nginx` | TCP 8080 (HTTP)<br/>TCP 8443 (HTTPS) | Acts as edge reverse proxy, terminates TLS connections, and load-balances traffic across Mac 3 backends. |
| **Mac 3** | Dual Backend Services & Monitoring | Python 3 (`server.py`), Wireshark | TCP 3001 (Backend A)<br/>TCP 3002 (Backend B) | Hosts Backend A and Backend B as independent Python HTTP processes; captures network traffic via Wireshark. |

---

## Request Flow

```text
[ Client ]
    │
    │ 1. DNS Query: "app.team1.test"
    ▼
[ Mac 1: Private DNS (dnsmasq :53) ]
    │
    │ 2. Resolves "app.team1.test" -> Mac 2 IP
    ▼
[ Client ]
    │
    │ 3. HTTP (8080) / HTTPS (8443) Request
    ▼
[ Mac 2: Edge Reverse Proxy & Load Balancer (nginx) ]
    │
    ├───────────────────────────────┐
    │ 4a. Forward to Backend A      │ 4b. Forward to Backend B
    ▼                               ▼
[ Mac 3: Backend A (:3001) ]   [ Mac 3: Backend B (:3002) ]
                ▲
                │ (All Mac 3 traffic monitored via Wireshark)
```

1. **DNS Lookup:** The client queries Mac 1 (`dnsmasq` listening on port 53) for `app.team1.test` or `api.team1.test`. Mac 1 returns the IPv4 address of Mac 2.
2. **Edge Ingress:** The client connects to Mac 2 on port 8080 (HTTP) or port 8443 (HTTPS with TLS termination).
3. **Load Balancing:** Nginx on Mac 2 proxies the request to the upstream pool consisting of Mac 3 port 3001 (Backend A) and Mac 3 port 3002 (Backend B) in a round-robin schedule.
4. **Backend Processing:** Mac 3 processes the request and responds with an identifying header (`X-Backend: A` or `X-Backend: B`).
5. **Packet Inspection:** Wireshark on Mac 3 captures ingress TCP connections, HTTP requests, responses, and local packet timing.

---

## TODO: Future Implementation & Documentation

- [ ] Record final static/dynamic IP assignments for Mac 1, Mac 2, and Mac 3.
- [ ] Document MTU settings and link speeds across the local Wi-Fi / switch subnet.
- [ ] Add latency benchmarks between Mac 1, Mac 2, and Mac 3.
- [ ] Verify complete packet flow with exported Wireshark session timestamps.
