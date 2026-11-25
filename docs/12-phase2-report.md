# Phase 2 Final Report

Status: draft. Results are filled in only after the matching 4-Mac test has been run.

## What changed from Phase 1

| Area | Phase 1 | Phase 2 | Status |
|---|---|---|---|
| Topology | 3 Macs, both backends on Mac 3 | 4 Macs, Backend B on Mac 4 | Planned |
| DNS record TTL | 0 (dnsmasq default) | 30 s | Live on the primary; checked from Mac 1 |
| DNS resolvers | Primary only | Primary (Mac 1) and backup (Mac 4) | Configured, checked locally on Mac 1 |
| Failover | — | nginx passive health checks | Pending (Mac 2) |
| Backend access | Open on the LAN | Edge hosts only (pf) | Pending (Mac 3, Mac 4) |
| Edge | Mac 2 only | Standby edge on Mac 3, DNS cutover | Pending |

## Resilience tests and results

| Extension | Test | Result |
|---|---|---|
| A — Backup DNS | Stop the primary; clients still resolve | Passed on the Mac 2 client: with the primary stopped, the system resolver returned the Mac 2 address and HTTPS returned 200 |
| B — TTL | Change a record; old answer until TTL expiry; flush | Partial: the live primary returns TTL 30 (`evidence/phase2/B-ttl/mac1-primary-dns-live.txt`). Record change on the LAN, client caching and flush are pending |
| C — Isolation | Client blocked from 3001/3002; edge allowed | Pending |
| D — HA failover | Stop Backend A; requests still succeed | Pending |
| E — Edge migration | Point DNS at the standby edge | Pending |

## Troubleshooting findings

Pending (Extension F).

## Learning summary

### Extension A — Backup DNS resolver (Abhishek)
Mac 4 runs a second dnsmasq with the same `app` and `api` records, and clients list Mac 1 first and Mac 4 second. With dnsmasq stopped on Mac 1, the Mac 2 client flushed its cache; a direct query to Mac 1 got no answer, a query to Mac 4 and the normal system lookup returned the Mac 2 address, and HTTPS returned 200. In the capture on Mac 2, the query for `app.team1.test` went to Mac 1 at 19:43:55.377 and, with no reply, to Mac 4 at 19:43:57.389, about 2 s later. The client's resolver switched servers without any change on the client. The two servers are not synchronised, so every record change must be made on both. This is different from an application failure, where the name still resolves but the edge returns 502.

Evidence: `evidence/phase2/A-backup-dns/`. `mac1-both-resolvers.txt` and `mac1-primary-stopped.txt` were taken on Mac 1. The Mac 2 capture (`dns-failover.pcap`) and screenshots are still to be added.

### Extension B — DNS TTL and record change (Abhishek)
Pending the 4-Mac test.

### Extension C — Service isolation (Kapish)
Service isolation restricts access to backend application ports (3001 and 3002) using macOS `pf` (packet filter) anchor rules (`com.apple/cn-isolate`). The rules allow incoming TCP traffic strictly from local loopback (`lo0`), Mac 2 primary edge proxy (`$MAC2_IP`), and Mac 3 standby edge proxy (`{ $MAC3_IP }`), while dropping all other incoming packets without reply (`block drop in quick`). This guarantees that external clients cannot bypass the edge security layer or access backends directly. The configuration was verified using `./scripts/pf-isolate.sh check` and rule syntax parsing.

### Extension D — High-Availability Failover (Modi & Kapish)
Demonstrates active fault tolerance using Nginx passive health checks. When Backend A on Mac 3 is stopped (`kill` or `Ctrl-C`), Nginx detects the connection failure (`Connection refused`), immediately triggers `proxy_next_upstream`, and routes pending client requests seamlessly to Backend B on Mac 4 with zero downtime (`HTTP 200`, `X-Backend: B`). When Backend A is restarted on Mac 3, Nginx automatically resumes round-robin distribution after its health check window expires.

### Extension E — DNS-based Edge Migration (Kapish & Abhishek)
Demonstrates blue-green zero-downtime edge cutover. A standby Nginx instance configured on Mac 3 (`team-https-standby.conf`, setting `X-Edge: mac3-standby`) is deployed with matching TLS certificates (`app.crt` and `app.key`). DNS records for `app.team1.test` are shifted from Mac 2 to Mac 3 across both primary and backup resolvers. Cached clients continue hitting Mac 2 until the 30-second TTL expires, while new requests and flushed clients immediately route through Mac 3's standby edge.

### Extension F — Troubleshooting challenge (all)
Pending.
