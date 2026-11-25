# Phase 2 Final Report

Team: Abhishek (Mac 1), Modi (Mac 2), Kapish (Mac 3), Vikash (Mac 4). Tests were run on the four Macs on 25 November 2026. A full read-only check (`./scripts/demo.sh all`) passed all 8 tests from Mac 1: `evidence/phase2/final-demo-all.txt`.

## What changed from Phase 1

| Area | Phase 1 | Phase 2 |
|---|---|---|
| Topology | 3 Macs, both backends on Mac 3 | 4 Macs, Backend B on Mac 4 |
| DNS record TTL | 0 (dnsmasq default) | 30 s |
| DNS resolvers | Primary only | Primary (Mac 1) and backup (Mac 4) |
| Failover | Not covered by a Phase 2 test | nginx passive health checks, tested by stopping Backend A |
| Backend access | Open on the LAN | `pf` rules allow only the edge Macs (enabled for the test, then rolled back) |
| Edge | Mac 2 only | Standby edge on Mac 3, DNS cutover tested |
| Operations | Manual commands | Scripts for DNS, edge, firewall and client demos |

## Resilience tests and results

| Extension | Test | Result |
|---|---|---|
| A — Backup DNS | Stop the primary; clients still resolve | Passed on the Mac 2 client: with the primary stopped, the system resolver returned the Mac 2 address and HTTPS returned 200 |
| B — TTL | Change a record; old answer until TTL expiry; flush | Passed: after a change the Mac 4 client kept the old address for about 12 s before switching. In a separate flush test it returned the old address just before the flush and the new one just after, within the same second (`evidence/phase2/B-ttl/06-flush-proof.txt`) |
| C — Isolation | Client blocked from 3001/3002; edge allowed | Passed from the Mac 1 client: both ports timed out; 8/8 requests through the edge returned 200, alternating A and B (`evidence/phase2/C-isolation/mac1-client-blocked.txt`). Mac 2 can still connect to both (`02-edge-allowed.png`). Rollback shown: after `disable` on both Macs, both ports were open again and 6/6 requests returned 200 |
| D — HA failover | Stop Backend A; requests still succeed | Passed (Mac 2 evidence): 10/10 returned 200 from Backend B with A stopped; 6/6 split 3/3 after restart (`evidence/phase2/D-ha/`) |
| E — Edge migration | Point DNS at the standby edge | Passed: after the cutover the Mac 4 client stayed on `mac2-primary` until 21:03:17 and used `mac3-standby` from 21:03:20; after the cut back it returned at 21:05:57. HTTP 200 on every watch line shown (`evidence/phase2/E-cutover/`) |

## Troubleshooting findings

Faults found while setting up the 4-Mac network. These happened on their own. The faculty-injected challenge takes place at the evaluation.

| Symptom | Layer | How it was isolated | Cause and fix |
|---|---|---|---|
| Backup DNS gave no answer | DNS | Ping and port 3002 worked; TCP 53 was refused and the UDP query timed out | Nothing was reachable on port 53 at Mac 4's address. It answered after Mac 4 updated its address and restarted the backup resolver |
| All HTTPS requests failed on Mac 4 | TLS | The name resolved and TCP connected; `curl -v` showed `unable to get local issuer certificate` | Mac 4 did not trust the team root CA. Fixed by installing the CA that signed the edge certificate, after checking its fingerprint |
| Mac 3 env file had an old address | Configuration | `MAC3_IP` differed from the address on `en0` | The file was from an earlier session. Replaced with the current four addresses before enabling the firewall |

**Practice drill 1 (guided; the fault had been disclosed beforehand).** The upstream port for Backend A on Mac 2 was changed from 3001 to 3005. Client settings, both resolvers, TCP to the edge and TLS were healthy. All requests returned 200 but only Backend B answered. `x-upstream-addr` showed nginx trying Mac 3 on 3005; from Mac 1, port 3001 accepted connections and 3005 was refused; the nginx error log showed `Connection refused` for 3005. After re-rendering the config and reloading nginx, both backends answered again. Lesson: a 200 response does not show that both backends are healthy. Evidence: `evidence/phase2/F-troubleshooting/`.

## Learning summary

### Extension A — Backup DNS resolver (Abhishek)
Mac 4 runs a second dnsmasq with the same `app` and `api` records, and clients list Mac 1 first and Mac 4 second. With dnsmasq stopped on Mac 1, the Mac 2 client flushed its cache; a direct query to Mac 1 got no answer, a query to Mac 4 and the normal system lookup returned the Mac 2 address, and HTTPS returned 200. In the capture on Mac 2, the query for `app.team1.test` went to Mac 1 at 19:43:55.377 and, with no reply, to Mac 4 at 19:43:57.389, about 2 s later. The client's resolver switched servers without any change on the client. The two servers are not synchronised, so every record change must be made on both. This is different from an application failure, where the name still resolves but the edge returns 502.

Evidence: `evidence/phase2/A-backup-dns/`. `mac1-both-resolvers.txt` and `mac1-primary-stopped.txt` were taken on Mac 1. The Mac 2 capture (`dns-failover.pcap`) and screenshots are in the same folder.

### Extension B — DNS TTL and record change (Abhishek)
`local-ttl=30` makes dnsmasq give the team records a 30 s TTL; its default is 0, which tells clients not to cache. With Mac 4 using only the primary, `app.team1.test` was changed from Mac 2 (10.7.29.185) to Mac 3 (10.7.1.253). The restarted dnsmasq started at 20:10:58, but the client's system resolver returned the old address up to 20:11:10 and the new one from 20:11:12: it was reusing its cached answer. The delay is whatever is left of the TTL, so it can be anything up to 30 s. After switching, web requests failed because the test did not include a standby edge. The manual flush was tested separately. The primary restarted with the new record at 22:58:59. At 22:59:08 the Mac 4 client still returned 10.7.29.185 from its cache; after `dscacheutil -flushcache` and a restart signal to mDNSResponder, still at 22:59:08, it returned 10.7.1.253. In a production migration, the TTL is lowered in advance and the old server is kept running until cached answers have expired.

### Extension C — Service isolation (Kapish)
Service isolation restricts access to backend application ports (3001 and 3002) using macOS `pf` (packet filter) anchor rules (`com.apple/cn-isolate`). The rules allow incoming TCP traffic strictly from local loopback (`lo0`), Mac 2 primary edge proxy (`$MAC2_IP`), and Mac 3 standby edge proxy (`{ $MAC3_IP }`), while dropping all other incoming packets without reply (`block drop in quick`). This guarantees that external clients cannot bypass the edge security layer or access backends directly. The configuration was verified using `./scripts/pf-isolate.sh check` and rule syntax parsing.

**Measured results.** With the rules enabled on Mac 3 and Mac 4, both backend ports timed out from Mac 1, Mac 2 could connect to both, and 8/8 requests through the edge returned 200, alternating A and B. The block rule counted 4 packets on Mac 4 and 2 on Mac 3. After `pf-isolate.sh disable` on both, both ports were open from Mac 1 again. The project rules live in their own anchor and `/etc/pf.conf` is not edited. A copy of `/etc/pf.conf`, the pf status and the active rules was saved on both Macs after the rollback: pf disabled, no project rules (`evidence/phase2/C-isolation/pf-rollback-copy-mac3.txt` and `-mac4.txt`). No such copy was taken before the first enable.

### Extension D — High-Availability Failover (Modi & Kapish)
Demonstrates fault tolerance using nginx passive health checks. When Backend A on Mac 3 is stopped (`kill` or `Ctrl-C`), Nginx detects the connection failure (`Connection refused`), immediately triggers `proxy_next_upstream`, and routes pending client requests seamlessly to Backend B on Mac 4 with zero downtime (`HTTP 200`, `X-Backend: B`). When Backend A is restarted on Mac 3, Nginx automatically resumes round-robin distribution after its health check window expires.

### Extension E — DNS-based Edge Migration (Kapish & Abhishek)
Demonstrates blue-green zero-downtime edge cutover. A standby Nginx instance configured on Mac 3 (`team-https-standby.conf`, setting `X-Edge: mac3-standby`) is deployed with matching TLS certificates (`app.crt` and `app.key`). DNS records for `app.team1.test` are shifted from Mac 2 to Mac 3 across both primary and backup resolvers. Cached clients continue to use Mac 2 until their cached answer expires (at most 30 s), while fresh lookups receive Mac 3's address.

**Measured results (DNS side, Abhishek).** The standby was first tested from Mac 1 with `curl --resolve`, before any DNS change. At the cutover the primary restarted with the new record at 21:02:54; the Mac 4 client kept its cached address until 21:03:17 and used the standby from 21:03:20. At the cut back the primary restarted at 21:05:42; the client stayed on the standby until 21:05:55 and returned to Mac 2 at 21:05:57. Both edges stayed up, so every watch line shown returned HTTP 200. The old server must therefore keep running for at least the TTL after a cutover. A separate flushed-client check was not captured in this run.

### Extension F — Troubleshooting challenge (all)
We diagnose in a fixed order: client DNS settings, DNS, TCP, TLS, then HTTP, stopping at the first layer that fails and changing nothing until the broken layer is named. The runbook (`docs/13-troubleshooting-runbook.md`) lists a check and a healthy result for each layer. In one guided practice drill, layers up to TLS were healthy and every request returned 200, yet only Backend B answered; the upstream header, a direct port test and the nginx error log traced this to a wrong upstream port. The main lesson is that a successful status code does not prove that every component is healthy. The faculty-injected fault is handled live at the evaluation.
