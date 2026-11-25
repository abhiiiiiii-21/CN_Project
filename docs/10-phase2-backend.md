# Phase 2 — Backend A, isolation and standby edge (Mac 3)

Mac 3 owner: Kapish. Covers Backend A, Extension C (service isolation with pf) and the edge side of Extension E (standby nginx for the DNS cutover).

| Mac | Person | Role |
|---|---|---|
| Mac 1 | Abhishek | Primary DNS (dnsmasq), test client |
| Mac 2 | Modi | nginx edge: TLS and load balancing |
| Mac 3 | Kapish | Backend A, pf firewall, standby edge |
| Mac 4 | Vikash | Backend B, backup DNS, pf firewall, test client |

## Files

| File | Purpose |
|---|---|
| `backend/server.py` | Backend A: `python3 backend/server.py A 3001` |
| `config/pf-backends.conf.template` | Ext C rules, same file on Mac 3 and Mac 4 |
| `config/nginx/team-https.conf.template` | Rendered as `config/live/team-https-standby.conf` for Mac 3 (`X-Edge: mac3-standby`) |
| `scripts/pf-isolate.sh` | `check`, `enable`, `status`, `disable` (rollback) |
| `scripts/edge-apply.sh` | `standby` installs and starts nginx on Mac 3, `stop` stops it |

## Mac 3 steps in the command sheet

| Step | Action | Expect |
|---|---|---|
| 0.3 | `nginx -v \|\| brew install nginx` | `nginx version: nginx/...` |
| 9 / 13 | Ctrl-C the old Phase 1 Backend B (:3002); keep Backend A running | `"backend": "A"` from `curl http://$MAC3_IP:3001/api/status` |
| 20 | START Backend A (T2): `python3 backend/server.py A 3001` | `Backend A listening on 0.0.0.0:3001` |
| 23 | STOP Backend A (Ctrl-C) | Clients still get `HTTP 200`, all `X-Backend: B` |
| 26 | START Backend A | A/B alternate again after about 10 s |
| 35 | `./scripts/pf-isolate.sh check` then `enable` | `Rules parse OK`, `pf enabled`, 4 rules |
| 37 | `./scripts/pf-isolate.sh disable` | `Rolled back` |
| 46 / 48 | STOP / START Backend A (with Vikash) | `HTTP/2 502` while both are down |
| 50 | `./scripts/pf-isolate.sh enable` | `pf enabled` |
| 53 | `./scripts/pf-isolate.sh status` | Rules with hit counters; keep pf ON |
| 55 | Copy `app.crt` + `app.key`, then `./scripts/edge-apply.sh standby` | `test is successful`, `nginx started` |
| 62 | `./scripts/pf-isolate.sh disable` | `Rolled back`, no rules |
| 64 | `./scripts/edge-apply.sh stop` | `nginx stopped` (Mac 2 keeps running) |

**Order note for steps 9–13:** step 11 (Modi: `nc -zv $MAC3_IP 3001`) needs Backend A already running. Make sure A is up during step 9, not only at step 13.

## Extension C — Service isolation

Rules (`config/live/pf-backends.conf`, rendered on each backend Mac):

```
pass in quick on lo0 proto tcp from any to any port 3001:3002
pass in quick proto tcp from <Mac 2> to any port 3001:3002
pass in quick proto tcp from { <Mac 3> } to any port 3001:3002
block drop in quick proto tcp from any to any port 3001:3002
```

- **Why these four:** Mac 2 is the primary edge. Mac 3 is the standby edge in Ext E and must reach Backend B on Mac 4. `lo0` lets the standby nginx on Mac 3 reach Backend A on the same Mac. Everything else is dropped.
- **`block drop`, not `block return`:** a dropped SYN gets no reply, so a client sees a timeout (`[BLOCKED] no reply`). That is what a firewalled port looks like, as opposed to `Connection refused` from a stopped service.
- **Where the rules live:** the anchor `com.apple/cn-isolate`. The stock `/etc/pf.conf` already contains `anchor "com.apple/*"` and is loaded at boot by `/System/Library/LaunchDaemons/com.apple.pfctl.plist`, so loading our anchor is enough. `/etc/pf.conf` is never edited.
- **Rollback:** `pfctl -E` enables pf with a reference token. `disable` flushes the anchor and releases that token, so pf goes back to exactly the state it was in before.
- **Fault drill:** deleting the Mac 2 line (`sed '/from $MAC2_IP/d'`) leaves the edge unable to reach the backends. nginx waits `proxy_connect_timeout 2s` per backend, so the client gets `504` after about 4 s. The Mac 3 address is written in braces so that sed pattern cannot also delete it.

## Extension E — Standby edge on Mac 3

- `team-https-standby.conf` is rendered from the same template as Mac 2's config. Same upstream pool (`Mac 3:3001`, `Mac 4:3002`), same certificate. The only difference is `X-Edge: mac3-standby`.
- The certificate's SAN is `app.team1.test`, not an IP, so the same certificate is valid on whichever Mac answers for that name. Only `app.crt` and `app.key` are copied (step 54). The CA key never leaves Mac 2.
- pf stays ON during Ext E. The standby nginx reaches Backend A through `lo0` and Backend B through the `{ <Mac 3> }` rule on Mac 4. Both are allowed, so the cutover also shows that isolation and migration work together.
- Cutover is done by DNS (steps 58–61). Mac 3's nginx answers only for clients whose cached record has expired (30 s TTL) or who flushed their cache.

## Troubleshooting on Mac 3

| Symptom | Check |
|---|---|
| Step 11 `nc` to :3001 fails | Is Backend A running? `lsof -nP -iTCP:3001 -sTCP:LISTEN` |
| Step 36 shows Backend A `[OPEN]` with pf ON | `sudo pfctl -s info \| head -1` must say `Enabled`; `sudo pfctl -sr \| grep com.apple` must list the anchor |
| Step 55 `nginx -t` fails | `ls $(brew --prefix)/etc/nginx/certs/` must show `app.crt app.key`; run `./scripts/render-configs.sh` again |
| Step 55 `bind() ... 8443 failed` | Another nginx is already running: `./scripts/edge-apply.sh stop`, then `standby` again |
| Standby returns 504 with pf ON | Mac 4 rules must contain Mac 3's IP: `./scripts/pf-isolate.sh status` on Mac 4 |

## Local pre-check

`evidence/phase2/C-isolation/mac3-local-precheck.txt`: run on Mac 3 alone against `main`, using placeholder IPs. It covers rendering, standby config, pf rule set and drill, and Backend A (LAN reachability, 304, refused when stopped). nginx and pf were not run, so it is not 4-Mac evidence.
