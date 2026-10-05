# Failure Scenario Demonstrations

## Overview

A robust distributed network platform must demonstrate resilience, graceful degradation, and informative failure modes when faults occur. This document defines five specific failure scenarios (F1 through F5) evaluated during project testing across the three-Mac topology, with actual observed results and evidence references.

---

## Failure Scenarios & Observed Evidence

### F1: Wrong DNS Server
- **Scenario:** The client attempts to query an external DNS resolver (`8.8.8.8`) instead of the private Mac 1 DNS server (`10.7.21.145`) for the private internal domain `app.team1.test`.
- **Expected Outcome:** DNS lookup fails with `NXDOMAIN` because external public resolvers have no authoritative knowledge of the private `.test` zone. LAN connectivity remains intact.
- **Reproduction Commands:**
  ```bash
  sudo networksetup -setdnsservers Wi-Fi $COLLEGE_DNS
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder
  dig app.$TEAM.test
  ping -c 2 $MAC2_IP
  ```
- **Observed Result (Evidence-Verified):**
  - DiG query to `8.8.8.8#53` returned status `NXDOMAIN` with 0 answers and root server SOA authority (`a.root-servers.net`).
  - ICMP ping to Mac 2 (`10.7.19.92`) succeeded with 0.0% packet loss, confirming the local area network was fully operational and isolating the issue specifically to name resolution.
    - **Evidence Artifact:** [F1-wrong-dns-server.png](../evidence/failures/F1-wrong-dns-server.png)

---

### F2: Wrong DNS Record
- **Scenario (Deliberate Failure Configuration):** The client queries a DNS record that mistakenly resolves `app.team1.test` to an incorrect host (Mac 3, historically `10.7.29.148`) instead of the edge proxy Mac 2 (`$MAC2_IP`).
- **Expected Outcome:** The client resolves the address, but TCP connection to port 8443 fails because Mac 3 only runs backend services on ports 3001/3002 and does not listen on port 8443.
- **Reproduction Commands:**
  ```bash
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder
  dig +short app.$TEAM.test
  /usr/bin/curl -sS https://app.$TEAM.test:8443/api/status
  ```
- **Observed Result (Evidence-Verified from Historical Test Configuration):**
  - `dig +short` returned `10.7.29.148` (the deliberate incorrect DNS target used for demonstration).
  - Curl reported: `curl: (7) Failed to connect to app.team1.test port 8443 after 12 ms: Couldn't connect to server`.
  - Demonstrates that incorrect DNS host mapping routes client traffic to the wrong tier, causing TCP connection establishment failures.
  - **Evidence Artifact:** [F2-wrong-dns.png](../evidence/failures/F2-wrong-dns.png)

---

### F3: Backend A Down (Single Node Failover on Mac 3)
- **Scenario:** The **Backend A** process on **Mac 3** (`:3001`) is terminated, while **Backend B** (`:3002`) on the same Mac 3 remains running and healthy.
- **Expected Outcome:** Nginx on Mac 2 detects the upstream connection failure on port 3001, automatically retries and fails over to Backend B via `proxy_next_upstream`, and returns HTTP 200 with `X-Backend: B`. The failover is transparent to the client.
- **Reproduction Steps:**
  1. On **Mac 3**, terminate Backend A (`Ctrl+C` or `kill <PID_Backend_A>`).
  2. Send consecutive requests through Mac 2 edge proxy:
     ```bash
     for i in 1 2 3 4; do
         /usr/bin/curl -s -D - -o /dev/null https://app.$TEAM.test:8443/api/status | grep -iE 'HTTP|x-backend'
     done
     ```
- **Observed Result (Evidence-Verified):**
  - Prior to failure, responses alternated between `x-backend: A` and `x-backend: B`.
  - After Backend A was stopped, all 4 test requests returned `HTTP/2 200` with header `x-backend: B`.
  - Zero dropped connections or client-visible errors were encountered.
  - **Evidence Artifact:** [f3-backend-stopped.png](../evidence/failures/f3-backend-stopped.png)

---

### F4: Both Backends Down (Upstream Pool Exhaustion on Mac 3)
- **Scenario:** Both **Backend A** (`:3001`) and **Backend B** (`:3002`) processes are terminated on **Mac 3**.
- **Expected Outcome:** Nginx on Mac 2 cannot establish an upstream connection to any server in the `team_backend` pool and returns `HTTP/2 502 Bad Gateway`.
- **Reproduction Steps:**
  1. On **Mac 3**, stop both Backend A and Backend B processes.
  2. Send a request to Mac 2:
     ```bash
     /usr/bin/curl -si https://app.$TEAM.test:8443/api/status | head -1
     ```
- **Observed Result (Evidence-Verified):**
  - Nginx returned: `HTTP/2 502`.
  - Confirms standard RFC 7231 gateway behavior when all upstream pool members are unreachable.
  - **Evidence Artifact:** [F4-both-backends-down.png](../evidence/failures/F4-both-backends-down.png)

---

### F5: Wrong Destination Port
- **Scenario:** The client attempts to connect to an unopened port on Mac 2 (e.g., HTTPS on port 9443 instead of 8443).
- **Expected Outcome:** Connection is rejected immediately with a TCP RST packet (`Connection refused`).
- **Reproduction Commands:**
  ```bash
  /usr/bin/curl -sS https://app.$TEAM.test:9443/
  nc -vz $MAC2_IP 8443
  nc -vz $MAC2_IP 9443
  ```
- **Observed Result (Evidence-Verified):**
  - Curl reported: `curl: (7) Failed to connect to app.team1.test port 9443 after 1086 ms: Couldn't connect to server`.
  - Netcat to port 8443: `Connection to 10.7.19.92 port 8443 [tcp/pcsync-https] succeeded!`.
  - Netcat to port 9443: `nc: connectx to 10.7.19.92 port 9443 (tcp) failed: Connection refused`.
  - Demonstrates that requests to closed ports elicit immediate TCP RST rejection at the transport layer.
  - **Evidence Artifact:** [F5-wrong-port.png](../evidence/failures/F5-wrong-port.png)

---

## Evidence Summary

All 5 failure modes (F1–F5) have been empirically executed, verified, and preserved in the repository under `evidence/failures/`:
- `evidence/failures/F1-wrong-dns-server.png`
- `evidence/failures/F2-wrong-dns.png`
- `evidence/failures/f3-backend-stopped.png`
- `evidence/failures/F4-both-backends-down.png`
- `evidence/failures/F5-wrong-port.png`
