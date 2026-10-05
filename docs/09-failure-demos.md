# Failure Scenario Demonstrations

## Overview

A robust distributed network platform must demonstrate resilience, graceful degradation, and informative failure modes when faults occur. This document defines five specific failure scenarios (F1 through F5) evaluated during project testing.

> **Note:** Do not fabricate test results in advance. Outputs, traces, and screenshots will be captured and documented in `evidence/failures/` during actual execution.

---

## Failure Scenarios

### F1: Wrong DNS Server
- **Scenario:** The client attempts to query a DNS server other than Mac 1 (e.g., public DNS or an unconfigured LAN host) for the internal domain `app.team1.test`.
- **Expected Outcome:** DNS lookup fails with `NXDOMAIN` or query timeout because external resolvers have no authoritative knowledge of `.test` private records.
- **Reproduction Command:**
  ```bash
  # Query an external or wrong DNS server
  dig @8.8.8.8 app.team1.test
  ```
- **Observed Result:** *(TODO: Record output during testing)*

---

### F2: Wrong DNS Record
- **Scenario:** The client queries Mac 1 for a subdomain that does not exist in `dnsmasq.conf` (e.g., `invalid.team1.test`).
- **Expected Outcome:** `dnsmasq` responds with `NXDOMAIN` (non-existent domain).
- **Reproduction Command:**
  ```bash
  dig @MAC1_IP invalid.team1.test
  ```
- **Observed Result:** *(TODO: Record output during testing)*

---

### F3: Backend A Down (Single Node Failover)
- **Scenario:** Backend A process on Mac 3 (`:3001`) is terminated, while Backend B (`:3002`) remains healthy.
- **Expected Outcome:** Nginx detects the connection failure on port 3001, automatically routes traffic to Backend B via `proxy_next_upstream`, and returns HTTP 200 with header `X-Backend: B`. No outage is visible to the client.
- **Reproduction Steps:**
  1. Kill Backend A on Mac 3 (`kill -9 <PID_Backend_A>`).
  2. Send requests to Mac 2:
     ```bash
     curl -i http://app.team1.test:8080/
     ```
- **Observed Result:** *(TODO: Record output during testing)*

---

### F4: Both Backends Down (Upstream Pool Exhaustion)
- **Scenario:** Both Backend A (`:3001`) and Backend B (`:3002`) are stopped on Mac 3.
- **Expected Outcome:** Nginx cannot establish upstream connections to any server in the pool and returns `HTTP/1.1 502 Bad Gateway`.
- **Reproduction Steps:**
  1. Terminate both backend processes on Mac 3.
  2. Send request to Mac 2:
     ```bash
     curl -i http://app.team1.test:8080/
     ```
- **Observed Result:** *(TODO: Record output during testing)*

---

### F5: Wrong Destination Port
- **Scenario:** The client attempts to connect to an unopened port on Mac 2 (e.g., port 8081 or 9000).
- **Expected Outcome:** The connection is rejected immediately with `Connection refused` (TCP RST packet received).
- **Reproduction Command:**
  ```bash
  curl -i http://app.team1.test:8081/
  ```
- **Observed Result:** *(TODO: Record output during testing)*

---

## TODO: Future Implementation & Documentation

- [ ] Execute each failure test case during live lab demo.
- [ ] Save raw terminal session logs for F1 through F5 into `evidence/failures/`.
- [ ] Capture Wireshark packet captures showing TCP RST for F5 and upstream connection errors for F4.
