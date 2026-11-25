# Phase 2 — Troubleshooting Runbook (Extension F)

The faculty injects one fault into the running system. Find the broken layer, then fix or isolate it. Work from the bottom of the request path upwards, and say each step and result out loud: correct method earns partial credit even if the fix is incomplete.

**Order: client settings → DNS → TCP → TLS → HTTP.** Stop at the first layer that fails. Change nothing until you can name the broken layer.

## The checks

Run on a client Mac that uses the team DNS. The "healthy" values come from `evidence/phase2/F-troubleshooting/00-healthy-baseline.txt`. IP addresses are those of the lab session; use the current ones.

| # | Layer | Command | Healthy |
|---|---|---|---|
| 1 | Client settings | `scutil --dns \| grep nameserver \| head -2` | Mac 1, then Mac 4 |
| 2 | DNS | `dig app.team1.test @10.7.30.25` and `dig app.team1.test @10.7.23.21` | Both answer `10.7.29.185`, TTL 30 |
| 2b | DNS, client cache | `dscacheutil -q host -a name app.team1.test` | `10.7.29.185` |
| 3 | TCP | `nc -vz -G 3 10.7.29.185 8443` | `succeeded` |
| 4 | TLS | `curl -v https://app.team1.test:8443/ 2>&1 \| grep -E "subject:\|issuer:\|verify\|SSL"` | `subject: CN=app.team1.test`, `SSL certificate verify ok` |
| 5 | HTTP | `curl -i https://app.team1.test:8443/api/status` | `200`, `x-backend`, `x-edge: mac2-primary` |

Run check 5 at least four times. A single healthy backend hides a fault in the other: both `A` and `B` must appear.

Shortcut for layers 2 to 5: `./scripts/demo.sh check`. It queries Mac 1 only, so it does not test the backup resolver or the client's DNS settings.

## What a failure means

| You see | Broken layer | Look next |
|---|---|---|
| Wrong or missing nameservers in check 1 | Client settings | `networksetup -getdnsservers Wi-Fi` |
| `dig` times out on one resolver | DNS server | Is dnsmasq running on that Mac? `./scripts/dns-ctl.sh primary\|backup status` |
| `dig` answers with the wrong IP | DNS record | `grep host-record config/live/dnsmasq*.conf` on both resolver Macs |
| `dig` is right but `dscacheutil` is old | Client cache | `./scripts/phase2-demo.sh flush` |
| `Connection refused` on 8443 | TCP: nothing listening | On Mac 2: `./scripts/edge-apply.sh status`, `sudo lsof -nP -iTCP:8443` |
| TCP connect times out | TCP: path or firewall | `ping`, the IP address, the Wi-Fi network, firewall |
| `curl: (60)` or a name mismatch | TLS | `subject`, `issuer`, expiry; is the team CA trusted on this client? |
| `502 Bad Gateway` | Edge to backend | On Mac 2: nginx `error.log`; `nc -vz <backend IP> <port>` |
| `504 Gateway Time-out` or slow replies | Edge to backend, packets dropped | On the backend Mac: `./scripts/pf-isolate.sh status` |
| `200`, but only A or only B | One upstream | `x-upstream-addr`, nginx `error.log`, that backend process, upstream port |

On Mac 2:

```bash
tail -n 20 "$(brew --prefix)/var/log/nginx/error.log"
```

## Telling failures apart

- **Name fails, IP works:** DNS problem.
- **Name resolves, connection refused:** nothing is listening on that address and port.
- **Connection works, certificate fails:** TLS trust or certificate problem. Do not "fix" it with `-k`.
- **TLS works, status is 502 or 504:** the edge is fine; the problem is between the edge and the backends.

## Practice drills

One person injects a fault without saying which. Another diagnoses with the checks above. The person who injected it keeps the undo command ready. Run one fault at a time, undo it, then confirm with `./scripts/demo.sh check`.

The "expected" column is what should happen. Record what really happened.

Before using `render-configs.sh` to undo a fault, check that `~/cn-team.env` on that Mac has the current four addresses.

| ID | Who injects | Inject | Expected | Undo |
|---|---|---|---|---|
| F1 | Abhishek and Vikash | `./scripts/dns-ctl.sh primary point-app 10.7.29.200` and `./scripts/dns-ctl.sh backup point-app 10.7.29.200` | DNS answers, wrong IP; TCP fails | Same commands with `10.7.29.185` |
| F2 | Diagnoser's partner, on the diagnoser's Mac | `sudo networksetup -setdnsservers Wi-Fi 8.8.8.8` | `app.team1.test` does not resolve; the internet still works | `sudo networksetup -setdnsservers Wi-Fi 10.7.30.25 10.7.23.21` |
| F3 | Modi | `./scripts/edge-apply.sh stop` | DNS is right; connection refused on 8443 | `./scripts/edge-apply.sh primary` |
| F4 | Modi | Serve a temporary wrong certificate (commands below) | TCP works; certificate error | `./scripts/render-configs.sh && ./scripts/edge-apply.sh primary` |
| F5 | Modi | `sed -i '' 's/:3001;/:3005;/' config/live/team-https.conf && ./scripts/edge-apply.sh primary` | `200`, but only B answers | `./scripts/render-configs.sh && ./scripts/edge-apply.sh primary` |
| F6 | Kapish and Vikash | Ctrl-C on both backends | TLS works; `502` | Start both backends again |
| F7 | Kapish and Vikash | `./scripts/render-configs.sh && sed -i '' '/from 10.7.29.185 /d' config/live/pf-backends.conf && ./scripts/pf-isolate.sh enable` | TLS works; `502` or `504` from the edge | `./scripts/pf-isolate.sh disable && ./scripts/render-configs.sh` |

F4 commands, on Mac 2. They create a throwaway certificate in `/tmp` and leave the real certificate and key untouched:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=wrong.team1.test -keyout /tmp/bad.key -out /tmp/bad.crt
sed -i '' -e 's|ssl_certificate .*;|ssl_certificate /tmp/bad.crt;|' -e 's|ssl_certificate_key .*;|ssl_certificate_key /tmp/bad.key;|' config/live/team-https.conf
./scripts/edge-apply.sh primary
```

## Drill log

| # | Fault ID | Diagnoser | Layer named | Correct | What gave it away | Fixed |
|---|---|---|---|---|---|---|
| 1 (guided: fault ID disclosed beforehand) | F5 | Abhishek | HTTP, edge to upstream | Yes | All 200 but only B; `x-upstream-addr` showed Mac 3 on 3005; 3001 accepted, 3005 refused; nginx `error.log` showed `Connection refused` | Yes, A and B both answer again |
