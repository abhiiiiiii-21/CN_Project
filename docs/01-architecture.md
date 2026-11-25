# System Architecture Specification (Phase 2)

## Overview

A private network service platform on **four Macs** on one Wi-Fi LAN: private DNS with a backup resolver, an nginx edge that terminates TLS and load-balances, two backends on separate machines, backend isolation with `pf`, and a standby edge for DNS-based cutover.

Phase 1 ran on three Macs, with both backends on Mac 3. That version of this document is in git history (commit `2faaaef`). Documents `02` to `09` describe the Phase 1 build.

## Machine roles and services

| Machine | Owner | Role | Software | Ports |
|---|---|---|---|---|
| Mac 1 | Abhishek | Primary DNS, test client | dnsmasq | 53 UDP/TCP |
| Mac 2 | Modi | Edge: reverse proxy, load balancer, TLS termination | nginx | 8080 (redirect), 8443 (HTTPS) |
| Mac 3 | Kapish | Backend A; standby edge (Ext E) | `backend/server.py`, nginx | 3001; 8443 and 8080 when standby |
| Mac 4 | Vikash | Backend B; backup DNS; test client | `backend/server.py`, dnsmasq | 3002; 53 UDP/TCP |

## IP inventory (Phase 2 lab session, 25 November 2026)

Addresses are not hard-coded in templates. They come from `~/cn-team.env`.

| Machine | Variable | IPv4 | Interface | Subnet mask | Default gateway | MAC address |
|---|---|---|---|---|---|---|
| Mac 1 | `MAC1_IP` | `10.7.30.25` | `en0` | `255.255.224.0` | `10.7.0.1` | `e4:43:89:f1:51:ed` |
| Mac 2 | `MAC2_IP` | `10.7.29.185` | `en0` | `255.255.224.0` | `10.7.0.1` | `06:1e:db:4d:fe:de` |
| Mac 3 | `MAC3_IP` | `10.7.1.253` | `en0` | `255.255.224.0` | `10.7.0.1` | `aa:b6:b8:36:70:b0` |
| Mac 4 | `MAC4_IP` | `10.7.23.21` | `en0` | `255.255.224.0` | `10.7.0.1` | `f6:d8:7f:02:21:a1` |

The subnet is `10.7.0.0/19`, and all four addresses are inside it. Each row was read on that Mac (`evidence/phase2/mac1/network-details.txt`, `evidence/phase2/network-details-mac2-4.txt`). Upstream DNS: `8.8.8.8`, then `1.1.1.1`.

DNS records, both resolvers, TTL 30 s: `app.team1.test` and `api.team1.test` point to Mac 2.

## Network topology

```mermaid
flowchart LR
    C["Client Mac"]
    D1["Mac 1: primary DNS :53"]
    D2["Mac 4: backup DNS :53"]
    E["Mac 2: nginx edge :8443"]
    S["Mac 3: standby edge :8443"]
    A["Mac 3: Backend A :3001"]
    B["Mac 4: Backend B :3002"]
    C -->|"DNS query"| D1
    C -.->|"if primary does not answer"| D2
    C -->|"HTTPS"| E
    C -.->|"after DNS cutover"| S
    E -->|"HTTP"| A
    E -->|"HTTP"| B
    S -.-> A
    S -.-> B
```

All traffic crosses the same Wi-Fi network. With backend isolation on, ports 3001 and 3002 accept only Mac 2, Mac 3 (standby edge) and loopback.

## Request flow by protocol layer

```mermaid
sequenceDiagram
    participant C as Client
    participant D as DNS (Mac 1, backup Mac 4)
    participant E as nginx edge (Mac 2)
    participant B as Backend (Mac 3 or Mac 4)
    C->>D: Application, DNS over UDP 53: A? app.team1.test
    D-->>C: Mac 2 address, TTL 30
    C->>E: Transport, TCP SYN to 8443
    E-->>C: SYN-ACK
    C->>E: ACK
    C->>E: TLS ClientHello
    E-->>C: ServerHello, Certificate, Finished
    C->>E: TLS Finished
    C->>E: Application, HTTP/2 request inside TLS
    E->>B: new TCP connection, HTTP/1.x (not encrypted)
    B-->>E: response with X-Backend
    E-->>C: response inside TLS, adds X-Edge and X-Upstream-Addr
```

| Layer (TCP/IP) | Protocol | Role here |
|---|---|---|
| Application | DNS | Finds the edge address |
| Application | HTTP/2 to the edge, HTTP/1.x to backends | Requests, caching headers, load-balanced responses |
| Between application and transport | TLS 1.2 / 1.3 | Encryption and server identity, ends at the edge |
| Transport | UDP 53; TCP 8443, 8080, 3001, 3002 | DNS datagrams; reliable byte streams |
| Internet | IPv4, ICMP | Addressing and reachability (`ping`) |
| Link | Wi-Fi (802.11), interface `en0` | Frames on the LAN |

DNS can also use TCP 53. The client opens one TCP connection to the edge, and the edge opens a separate one to a backend. The client does not need to know any backend address.

## Resilience and remaining single points of failure

| Failure | What covers it | Limit |
|---|---|---|
| Primary DNS down | Backup resolver on Mac 4 | Lookups wait about 2 s before trying the backup; records are not synchronised |
| One backend down | nginx passive health check and retry on the other backend | Detected only when a real request fails |
| Edge moved or taken out of service | Standby nginx on Mac 3 and a DNS record change | Manual; clients move as their cached answers expire |

The **active edge is still a single point of failure**: if Mac 2 stops without warning, nothing changes the DNS record automatically. Removing it would need two live edges with automatic failover, for example a shared virtual IP (VRRP/keepalived on platforms that support it) or health-checked DNS records. Both backends and clients also depend on the same Wi-Fi network.

## Cloud equivalents

| Here | Cloud |
|---|---|
| dnsmasq, primary and backup | Managed DNS such as Route 53 |
| nginx edge | Load balancer (AWS ALB, GCP Load Balancing) |
| Backends | Application instances |
| pf rules | Security groups |
| DNS cutover to the standby edge | Blue/green traffic switch |
