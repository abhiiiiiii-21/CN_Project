# Phase 2 Status Tracker

Last updated: 25 November 2026, after the firewall copies from Mac 3 and Mac 4 were added. Requirements are the bullet points of section 7 of the course project guide.

Legend: ✅ done with evidence · 🟡 partly shown · ⬜ not done

## Mandatory extensions

| Extension | Requirement | Status | Evidence or gap |
|---|---|---|---|
| A | Second resolver with the same records on another Mac | ✅ | `A-backup-dns/mac1-both-resolvers.txt` |
| A | Clients list primary and backup | ✅ | `A-backup-dns/00-step40-two-resolvers.png` |
| A | Stop the primary; clients still resolve | ✅ | `A-backup-dns/02-primary-down.png`, `dns-failover.pcap` |
| A | Explain DNS failure and application failure | ✅ | Report; `A-backup-dns/03-app-down-502.png` |
| B | Short TTL (30 s) | ✅ | `B-ttl/01-ttl30-before-change.txt` |
| B | Resolve, then change the record | ✅ | `B-ttl/02-after-change.txt` |
| B | Old cached answer, then the new one | ✅ | `B-ttl/03-client-watch-ttl.txt` |
| B | Manual flush, immediate change | ✅ | `B-ttl/06-flush-proof.txt` |
| B | Relate to migration and cutover | ✅ | Report |
| C | Only the edge reaches 3001 and 3002 | ✅ | `C-isolation/mac1-client-blocked.txt`. The rules also allow Mac 3, the standby edge |
| C | Use pf rules | ✅ | `C-isolation/03-pf-counters-and-rollback.txt` |
| C | Edge connects, client cannot | ✅ | `C-isolation/02-edge-allowed.png`, `mac1-client-blocked.txt` |
| C | Keep a rollback copy and restore afterwards | ✅ | Restore shown. Copies of the restored setup: `C-isolation/pf-rollback-copy-mac3.txt`, `pf-rollback-copy-mac4.txt`. Taken after the rollback; take a copy before enabling at the final demo |
| D | nginx routes only to the healthy backend | ✅ | `D-ha/backend-a-down.pcap`, `03-nginx-error.png` |
| D | Stop Backend A; Backend B serves everything | ✅ | `D-ha/02-a-down.png` |
| D | Restart A; balancing resumes | ✅ | `D-ha/04-a-back.png` |
| D | Name the single point of failure and the remedy | ✅ | `docs/01-architecture.md` |
| E | Standby nginx on another Mac | ✅ | `E-cutover/mac1-standby-direct-test.txt` |
| E | Point DNS at the standby | ✅ | `E-cutover/client-watch-cutover.txt` |
| E | Cached client on the old edge while new lookups reach the standby | 🟡 | Cached client shown. A fresh lookup captured in the same window is still missing |

**Count: 19 of 20 done, 1 partly shown, 0 not started.** This counts requirements, not marks.

## Extension F

The fault is injected by the faculty at the evaluation, so it cannot be finished beforehand. Preparation: runbook written (`docs/13-troubleshooting-runbook.md`), healthy baseline saved, 1 guided drill done. A blind drill is still recommended.

## Deliverables

| Deliverable | Status |
|---|---|
| Architecture document, updated for Phase 2 | ✅ Written |
| Configuration bundle | ✅ In `config/` and `docs/` |
| Evidence folder | 🟡 The partial item above (Extension E timing) |
| Final report | ✅ Written. Team review pending |
| Final presentation and individual viva | ⬜ At the evaluation |

Also open: subnet mask, gateway and interface name for Mac 2, Mac 3 and Mac 4 (Phase 1 Task A, for the four-Mac layout). Practice run of the 11-step demonstration.

## Mac 1 (Abhishek)

| Task | Status |
|---|---|
| Primary DNS with TTL 30 | ✅ |
| Backup resolver configuration (runs on Mac 4) | ✅ |
| DNS control and demo scripts, DNS guide | ✅ |
| Extension A | ✅ |
| Extension B | ✅ |
| Extension E, DNS change on the primary | ✅ Cutover and cut back. The shared timing item above is still 🟡 |
| Own report sections | ✅ |
| Architecture document for four Macs, README | ✅ |
| Mac 1 network details and DNS config used | ✅ `evidence/phase2/mac1/` |
| Check from Mac 1 for Extensions C and E | ✅ |
| Practice demonstration | ⬜ |
| Viva preparation | ⬜ |

All technical tasks assigned to Mac 1 are done. What is left for Mac 1 is practice, viva preparation, and helping with the shared Extension E timing capture.
