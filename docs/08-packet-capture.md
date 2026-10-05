# Packet Inspection & Protocol Analysis

## Overview

Packet capture and protocol inspection are primary tools for verifying network correctness across the platform. **Mac 3** runs **Wireshark** to capture ingress traffic to backends (ports 3001/3002) and observe local network interactions. Additional captures on Mac 1 or client machines analyze DNS exchanges and TLS handshakes.

---

## Packet Inspection Objectives

The packet captures document five critical network protocol transitions:
1. **DNS Resolution:** Client querying Mac 1 on UDP port 53.
2. **TCP Connection Establishment:** Standard 3-way handshake (`SYN`, `SYN-ACK`, `ACK`).
3. **TLS Handshake:** Cryptographic negotiation, certificate validation, and key exchange between client and Mac 2 on port 8443.
4. **HTTP Flow:** Plaintext HTTP request/response payloads exchanged between the Mac 2 reverse proxy and Mac 3 backends.
5. **TLS 1.2 Protocol Capture:** Inspection of distinct handshake records characteristic of TLS 1.2.

---

## Capture Filters & Wireshark Display Filters

| Analysis Target | Display Filter | Key Fields & Observations |
|---|---|---|
| **DNS Resolution** | `dns` or `udp.port == 53` | Query record (`app.team1.test`), response Answer A record pointing to `MAC2_IP`. |
| **TCP 3-Way Handshake** | `tcp.flags.syn == 1` or `tcp.port in {8080, 8443, 3001, 3002}` | Sequence numbers (`seq=0`), ACK flag, window scale options. |
| **TLS Handshake** | `tls` or `ssl` | Client Hello (SNI, cipher suites), Server Hello, Certificate chain, Server Key Exchange, Finished. |
| **TLS 1.2 Specifics** | `tls.record.version == 0x0303` | Explicit Key Exchange and Certificate messages visible before encryption begins. |
| **Backend HTTP Traffic** | `http and (tcp.port == 3001 or tcp.port == 3002)` | Request headers forwarded by Mac 2 (`X-Forwarded-For`, `Host`), response headers (`X-Backend`, `ETag`). |

---

## Packet Capture Procedure (Mac 3)

1. Launch Wireshark on **Mac 3**:
   - Select primary active network interface (`en0`).
   - Set capture filter: `tcp port 3001 or tcp port 3002`.
2. Generate client traffic from Mac 1 or external test client.
3. Stop capture in Wireshark and save session file as `mac3-backend-capture.pcapng`.
4. Apply display filters to isolate specific sessions, export screenshots, and annotate protocol frames.

---

## TODO: Future Implementation & Documentation

- [ ] Execute synchronized packet capture across client, Mac 1, and Mac 3 during automated demo.
- [ ] Save `.pcapng` capture files into `evidence/G-packet-capture/`.
- [ ] Take annotated screenshots of DNS exchange, TCP handshake, TLS handshake, and HTTP payload.
- [ ] Document packet round-trip time (RTT) and TCP window sizing observations.
