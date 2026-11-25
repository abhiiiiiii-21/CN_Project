# Phase 2 — Backend A, Ext C Isolation, Ext E Standby Edge (Mac 3 · Kapish)

## Mac 3 Role Summary

| Mac | Person | Role |
|---|---|---|
| Mac 1 | Abhishek | Primary DNS (`dnsmasq`), test client |
| Mac 2 | Modi | nginx edge: TLS and load balancing |
| **Mac 3** | **Kapish** | **Backend A `:3001`, pf firewall, standby nginx edge `:8443`** |
| Mac 4 | Vikash | Backend B `:3002`, backup DNS, pf firewall, test client |

## Files owned by Mac 3

| File | Purpose |
|---|---|
| `backend/server.py` | Backend A: `python3 backend/server.py A 3001` |
| `config/pf-backends.conf.template` | Ext C firewall rules (also used on Mac 4) |
| `config/nginx/team-https.conf.template` | Rendered as `config/live/team-https-standby.conf` for Mac 3 (`X-Edge: mac3-standby`) |
| `scripts/pf-isolate.sh` | `check`, `enable`, `status`, `disable` (rollback) |
| `scripts/edge-apply.sh` | `standby` starts nginx on Mac 3; `stop` stops it |

## Ext C — Backend Isolation (pf firewall)

The firewall rules allow **only** the nginx edge Macs to reach the backend ports:

```
pass in quick on lo0 proto tcp from any to any port 3001:3002   # loopback
pass in quick proto tcp from MAC2_IP to any port 3001:3002       # Mac 2 (primary edge)
pass in quick proto tcp from { MAC3_IP } to any port 3001:3002   # Mac 3 (standby edge)
block drop in quick proto tcp from any to any port 3001:3002     # everyone else
```

The braces around `MAC3_IP` in the third rule prevent the Day 3 fault drill (`sed '/from $MAC2_IP/d'`) from accidentally deleting the Mac 3 line too.

### Enable
```bash
./scripts/pf-isolate.sh check    # parse rules only (safe, no sudo needed)
./scripts/pf-isolate.sh enable   # loads rules into anchor, enables pf
```

### Disable / Rollback
```bash
./scripts/pf-isolate.sh disable  # flush anchor, return pf to previous state
```

## Ext E — Standby nginx Edge

When DNS is cut over to `MAC3_IP` (Steps 58–61), Mac 3 serves HTTPS traffic:

```bash
# Receive app.crt and app.key from Modi (AirDrop)
mkdir -p "$(brew --prefix)/etc/nginx/certs"
cp ~/Downloads/app.crt ~/Downloads/app.key "$(brew --prefix)/etc/nginx/certs/"
chmod 600 "$(brew --prefix)/etc/nginx/certs/app.key"
rm ~/Downloads/app.key   # delete private key from Downloads

./scripts/edge-apply.sh standby   # installs team-https-standby.conf, starts nginx
```

The standby config has `add_header X-Edge mac3-standby always;`.

## Step sequence (Mac 3 only)

| Step | Action | Expect |
|---|---|---|
| 0.3 | `nginx -v \|\| brew install nginx` | `nginx version: nginx/1.31.10` ✓ |
| 13 | Keep Backend A running (`curl http://$MAC3_IP:3001/api/status`) | `"backend": "A"` |
| 20 | `python3 backend/server.py A 3001` (T2, leave open) | `Backend A listening on 0.0.0.0:3001` |
| 23 | Ctrl-C T2 — STOP Backend A | Vikash sees all `X-Backend: B` |
| 26 | `python3 backend/server.py A 3001` (T2) — START Backend A | A/B alternate again |
| 35 | `./scripts/pf-isolate.sh check && enable` | `Rules parse OK`, `pf enabled`, 4 rules |
| 37 | `./scripts/pf-isolate.sh disable` | `Rolled back` |
| 46 | Ctrl-C T2 — STOP Backend A | 502 on edge |
| 48 | `python3 backend/server.py A 3001` — START Backend A | 200 again |
| 50 | `./scripts/pf-isolate.sh enable` | `pf enabled` |
| 53 | `./scripts/pf-isolate.sh status` | Rules with hit counters; screenshot |
| 55 | Copy certs + `./scripts/edge-apply.sh standby` | `nginx started` |
| 62 | `./scripts/pf-isolate.sh disable` | `Rolled back`; screenshot |
| 64 | `./scripts/edge-apply.sh stop` | `nginx stopped` |

> **Order note for steps 9–13:** Step 11 (Modi: `nc -zv $MAC3_IP 3001`) requires Backend A to already be running on Mac 3. Start it in T2 at step 9/13 before Modi runs his connectivity check.
