# Packet Inspection & Protocol Analysis

## Overview

Packet capture and protocol inspection are primary tools for verifying network correctness across the platform. Traffic was captured on the shared network using **Wireshark** on **Mac 3**, recording end-to-end interactions across the DNS, TCP, TLS, and HTTP application layers.

The complete Wireshark session capture is stored in the repository as [phase1-full-flow-tls12.pcapng](../evidence/G-packet-capture/phase1-full-flow-tls12.pcapng).

> **Historical Evidence Note:** The IP addresses shown in this packet-capture section (e.g., client `10.7.29.148`, Mac 1 `10.7.21.145`, Mac 2 `10.7.19.92`) correspond to the network configuration used when the capture was recorded. They are historical evidence values and do not necessarily represent the current deployment configuration.

---

## Packet Inspection Objectives & Captured Protocols

### 1. DNS Resolution (UDP Port 53)
- **Observed Flow:**
  - Client (`10.7.29.148`) dispatches standard DNS query `0x4e5f` for `app.team1.test` to Mac 1 (`10.7.21.145:53`).
  - Mac 1 responds with standard query response returning IPv4 address `10.7.19.92` (Mac 2 edge proxy).
- **Wireshark Display Filter:** `dns.qry.name contains "test"`
- **Evidence Artifact:** [ws-dns.png](../evidence/G-packet-capture/ws-dns.png)

### 2. TCP Connection Establishment (3-Way Handshake)
- **Observed Flow:**
  - Ingress connection initiated between client (`10.7.29.148`) and Mac 2 edge proxy (`10.7.19.92:8443`).
  - Standard 3-way handshake captured: `[SYN, ECE, CWR]` -> `[SYN, ACK, ECE]` -> `[ACK]`.
- **Wireshark Display Filter:** `tcp.port == 8443 && tcp.flags.syn == 1`
- **Evidence Artifact:** [ws-tcp.png](../evidence/G-packet-capture/ws-tcp.png)

### 3. TLS 1.2 Handshake & Negotiation
- **Observed Flow:**
  - Client Hello: advertises supported cipher suites and SNI (`app.team1.test`).
  - Server Hello & Certificate: Mac 2 edge proxy returns server certificate issued by `team1 Local Root CA`.
  - Server Key Exchange & Server Hello Done.
  - Client Key Exchange, Change Cipher Spec, and Encrypted Handshake Message.
- **Wireshark Display Filter:** `tls.handshake`
- **Evidence Artifact:** [ws-tls.png](../evidence/G-packet-capture/ws-tls.png)

### 4. Encrypted Application Data
- **Observed Flow:**
  - Subsequent application traffic traversing port 8443 is fully encrypted under TLS 1.2 record type 23 (Application Data), verifying channel privacy across the LAN.
- **Wireshark Display Filter:** `tls.record.content_type == 23`
- **Evidence Artifact:** [ws-encrypted.png](../evidence/G-packet-capture/ws-encrypted.png)

### 5. Plaintext Upstream HTTP & Connection Termination
- **Observed Flow:**
  - Mac 2 reverse proxy (`10.7.19.92:57916`) forwards decrypted plaintext request `GET /api/status HTTP/1.1` to Mac 3 Backend A (`10.7.29.148:3001`).
  - Backend A responds with `HTTP/1.0 200 OK`, `X-Backend: A`, `Cache-Control: no-store`, and JSON status body.
  - Connection teardown via TCP `FIN, ACK` sequence.
- **Wireshark Display Filter:** `tcp.port == 3001`
- **Evidence Artifacts:**
  - [ws-flow-graph.png](../evidence/G-packet-capture/ws-flow-graph.png): Wireshark flow graph illustrating request, response, and packet directions.
  - [ws-termination.png](../evidence/G-packet-capture/ws-termination.png): Frame listing of upstream HTTP session and TCP connection teardown.

---

## Evidence Artifacts Index

| Evidence File | Protocol Analyzed | Description |
|---|---|---|
| `phase1-full-flow-tls12.pcapng` | Complete Flow | Raw Wireshark packet capture file covering DNS, TCP, TLS, and HTTP |
| `ws-dns.png` | DNS (UDP :53) | Query and response mapping `app.team1.test` to `10.7.19.92` |
| `ws-tcp.png` | TCP Handshake | SYN and SYN-ACK frames establishing connection on port 8443 |
| `ws-tls.png` | TLS 1.2 Handshake | Client Hello, Server Hello, Certificate chain, and Key Exchange |
| `ws-encrypted.png` | TLS Record Layer | Encrypted Application Data packets (Type 23) |
| `ws-flow-graph.png` | HTTP Flow Graph | End-to-end visual exchange between Nginx proxy and Backend A |
| `ws-termination.png` | TCP Teardown | HTTP 200 response delivery and FIN/ACK connection closing |

---

## Implementation & Testing Notes

- Packet Round-Trip Time (RTT) and TCP window scaling variations under congestion: *Not measured in Phase 1*.
- All protocol captures were performed on interface `en0` and verified in Wireshark.
