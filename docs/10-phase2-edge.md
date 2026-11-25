# Phase 2: the edge (Mac 2)

Owner: Mac 2 (nginx reverse proxy, load balancer, TLS termination).
This page covers the edge's part of Phase 2: HA failover (Ext D), service isolation as seen from the edge (Ext C) and edge migration (Ext E). Commands are in the team command sheet; the step numbers below refer to it.

---

## What changed from Phase 1

| | Phase 1 | Phase 2 |
|---|---|---|
| Backend B | Mac 3 :3002 | **Mac 4 :3002** |
| Upstream pool | `MAC3_IP:3001`, `MAC3_IP:3002` | `MAC3_IP:3001`, `MAC4_IP:3002` |
| Edge identity | none | `X-Edge: mac2-primary` response header |
| Standby edge | none | Mac 3, same config, `X-Edge: mac3-standby` |
| Deploy | manual copy | `./scripts/render-configs.sh` then `./scripts/edge-apply.sh primary` |
| Backend reachability | any LAN host | only the edges (pf rules on Mac 3 and Mac 4) |

Rendered files (per Mac, not committed):

- `config/live/team-https.conf`: primary edge, installed on Mac 2
- `config/live/team-https-standby.conf`: standby edge, installed on Mac 3 in Ext E
- `config/live/team-http.conf`: port 8080 redirects to 8443 on both

`edge-apply.sh` copies them to `$(brew --prefix)/etc/nginx/servers/`, runs `nginx -t` and only then reloads or starts nginx, so a broken config never goes live.

---

## Request path through the edge

```text
client ──DNS──► Mac 1 / Mac 4   app.team1.test → Mac 2 IP (TTL 30 s)
client ──TCP+TLS :8443──► Mac 2 nginx   (TLS ends here, HTTP/2 to the client)
Mac 2 ──HTTP/1.1──► Mac 3 :3001 (A)  or  Mac 4 :3002 (B)   round-robin
```

Two separate TCP connections per request: client to edge, and edge to backend. The client never learns a backend address; that is what lets backends fail, move or be firewalled without any client change.

Headers that prove the path:

| Header | Set by | Meaning |
|---|---|---|
| `X-Backend` | backend app | which backend produced the body (A or B) |
| `X-Upstream-Addr` | nginx | upstream(s) nginx tried, e.g. `10.x.x.x:3001, 10.x.x.x:3002` after a failover |
| `X-Edge` | nginx | which edge answered (`mac2-primary` / `mac3-standby`) |
| `X-Forwarded-For`, `X-Real-IP` | nginx (to backend) | the real client IP; without them the backend only sees the edge's IP |

---

## Ext D: HA failover

nginx uses **passive health checks**: it marks a backend down only after a real request to it fails.

```nginx
proxy_connect_timeout 2s;
proxy_read_timeout 5s;
proxy_next_upstream error timeout http_502 http_503;
# server defaults: max_fails=1 fail_timeout=10s
```

1. Backend A is stopped (step 23). The next request sent to A gets `connect() failed (61: Connection refused)` in the nginx error log (step 25).
2. Because of `proxy_next_upstream error`, nginx retries the same request on B. The client still gets `200` with `X-Backend: B` (step 24).
3. After one failure (`max_fails=1`) A is skipped for `fail_timeout` = 10 s. After that nginx tries A again, which is why step 27 waits 10 s before A/B alternate again.

Status codes the edge can return, and what they say about the failing layer:

| Code | Cause | Layer |
|---|---|---|
| 200 with only B | A down, failover worked | app (one backend) |
| **502 Bad Gateway** | every upstream refused the connection (both backends stopped, step 47) | app, behind the edge |
| **504 Gateway Timeout** | upstreams never answered (pf drops the SYN; 2 s connect timeout per upstream) | TCP, edge to backend |
| connection refused on :8443 | nginx itself is stopped | TCP, the edge |

In 502 and 504 cases DNS and TLS still succeeded, so the fault is behind the edge.

### Single point of failure

The backends are redundant, but **the Mac 2 nginx is still a single point of failure**: if it stops, every client fails at TCP even though both backends are healthy. Ways to remove it:

- **Two active edges behind one floating IP** (VRRP / keepalived): the standby takes over the address in about a second, no DNS change.
- **DNS failover with health checks** (like Route 53 failover records): DNS stops handing out the dead edge's IP; speed is limited by the TTL.
- **Anycast or a cloud load balancer** in front of several edges.

Ext E demonstrates the second option by hand.

---

## Ext C: isolation, edge view

pf rules on Mac 3 and Mac 4 (`config/live/pf-backends.conf`) allow ports 3001-3002 only from Mac 2 (the primary edge) and Mac 3 (the standby edge), and silently drop everything else.

- From a client Mac the backends show `[BLOCKED]` (step 51), yet `https://app.team1.test:8443` still returns 200.
- From Mac 2, `nc -zv` to both backends succeeds (step 52).

This enforces the Task D rule that clients only ever enter through the edge. Because the rules drop instead of reject, an edge that is not allowed sees a timeout, so the edge returns **504** (fault drill), not 502.

---

## Ext E: edge migration (DNS cutover)

1. Mac 2 hands `app.crt` and `app.key` to Mac 3 only (step 54). The certificate's SAN names `app.team1.test`, not an IP, so the same certificate is valid on any edge that answers for that name.
2. Mac 3 runs `edge-apply.sh standby`: the same upstream pool, `X-Edge: mac3-standby` (step 55).
3. Both DNS servers change `app.team1.test` to Mac 3's IP (step 58).
4. Clients with a cached answer keep reaching Mac 2 for up to the 30 s TTL, then move to Mac 3 (step 59). A client that flushes its cache moves immediately (step 60).
5. Cut back the same way (step 61); Mac 3's nginx is stopped in step 64.

During the switch both edges serve correctly, so no request fails. This is how production traffic is moved between edges or regions: lower the TTL ahead of time, change the record, wait one TTL, then retire the old edge.

---

## Evidence (Mac 2)

| File | Step |
|---|---|
| `evidence/phase2/D-ha/backend-a-down.pcap` | 21 |
| `evidence/phase2/D-ha/03-nginx-error.png` | 25 |
| `evidence/phase2/A-backup-dns/dns-failover.pcap` | 41 |
| `evidence/phase2/A-backup-dns/01-both-up.png` | 42 |
| `evidence/phase2/A-backup-dns/02-primary-down.png` | 44 |
| `evidence/phase2/A-backup-dns/03-app-down-502.png` | 47 |
| `evidence/phase2/C-isolation/02-edge-allowed.png` | 52 |
| `evidence/phase2/E-cutover/` (x-edge after flush) | 60 |

Results are recorded on Day 2 and added to the Phase 2 final report.
