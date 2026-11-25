# Phase 2 Final Report

Status: draft. Results are filled in only after the matching 4-Mac test has been run.

## What changed from Phase 1

| Area | Phase 1 | Phase 2 | Status |
|---|---|---|---|
| Topology | 3 Macs, both backends on Mac 3 | 4 Macs, Backend B on Mac 4 | Planned |
| DNS record TTL | 0 (dnsmasq default) | 30 s | Configured, checked locally on Mac 1 |
| DNS resolvers | Primary only | Primary (Mac 1) and backup (Mac 4) | Configured, checked locally on Mac 1 |
| Failover | — | nginx passive health checks | Pending (Mac 2) |
| Backend access | Open on the LAN | Edge hosts only (pf) | Pending (Mac 3, Mac 4) |
| Edge | Mac 2 only | Standby edge on Mac 3, DNS cutover | Pending |

## Resilience tests and results

| Extension | Test | Result |
|---|---|---|
| A — Backup DNS | Stop the primary; clients still resolve | Pending 4-Mac test |
| B — TTL | Change a record; old answer until TTL expiry; flush | Pending 4-Mac test |
| C — Isolation | Client blocked from 3001/3002; edge allowed | Pending |
| D — HA failover | Stop Backend A; requests still succeed | Pending |
| E — Edge migration | Point DNS at the standby edge | Pending |

## Troubleshooting findings

Pending (Extension F).

## Learning summary

### Extension A — Backup DNS resolver (Abhishek)
Pending the 4-Mac test.

### Extension B — DNS TTL and record change (Abhishek)
Pending the 4-Mac test.

### Extension C — Service isolation (Kapish)
Pending.

### Extension D — High-availability failover (Modi)
Pending.

### Extension E — DNS-based edge migration (Kapish, Abhishek)
Pending.

### Extension F — Troubleshooting challenge (all)
Pending.
