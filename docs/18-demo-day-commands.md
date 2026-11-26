# Demo Day Commands (Mac 1, 2, 3, 4)

| Mac | Person | Role | IP | Project folder |
|---|---|---|---|---|
| 1 | Abhishek | Primary DNS, client | `10.7.30.25` | `cd ~/Documents/Coding/Assignments/CN_Project` |
| 2 | Modi | nginx edge (TLS, load balancer) | `10.7.29.185` | `cd ~/Desktop/CN_Project` |
| 3 | Kapish | Backend A, standby edge, firewall | `10.7.1.253` | `cd ~/Desktop/vscode/CN/CN_Project` |
| 4 | Vikash | Backend B, backup DNS, client | `10.7.23.21` | `cd ~/Desktop/CN_Project` |

Run every command from your project folder. Type `sudo` passwords only on your own Mac.

**If any IP is different**, update `~/cn-team.env` on all four Macs, run `./scripts/render-configs.sh` on each, restart the services, and use the new IP wherever an IP is typed below.

---

## Part 1: Start the system (in this order)

### 1. Mac 1 (Abhishek)
```bash
./scripts/mac1.sh demo
```

### 2. Mac 3 (Kapish), keep this terminal open
```bash
python3 backend/server.py A 3001
```

### 3. Mac 4 (Vikash), keep this terminal open
```bash
python3 backend/server.py B 3002
```

### 4. Mac 4 (Vikash), in a second terminal
```bash
./scripts/dns-ctl.sh backup start
```

### 5. Mac 2 (Modi), in Apple's Terminal app, not VS Code
```bash
./scripts/edge-apply.sh primary
```

### 6. Mac 4 (Vikash), and any other Mac used as a client
```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.30.25 10.7.23.21
```

### 7. Mac 1 (Abhishek): check everything
```bash
./scripts/demo.sh all
```
```bash
./scripts/phase2-demo.sh lb 8
```

Expected: no `FAIL`, and 8 of 8 requests return 200 with both A and B.

---

## Part 2: Show the basic system

### Mac 1: DNS
```bash
cat config/live/dnsmasq.conf
```
```bash
./scripts/dns-ctl.sh primary status
```
```bash
dig app.team1.test @10.7.30.25
```
```bash
dig api.team1.test @10.7.30.25
```

### Any client: TLS and HTTP
```bash
curl -v https://app.team1.test:8443/api/status
```
```bash
curl -I http://app.team1.test:8080/
```
Expected: `301` to HTTPS.

```bash
curl -sI --http1.1 https://app.team1.test:8443/api/status
```
```bash
curl -sI --http2 https://app.team1.test:8443/api/status
```

### Any client: load balancing
```bash
./scripts/phase2-demo.sh lb 8
```

### Any client: caching
```bash
curl -i https://app.team1.test:8443/api/info
```
Look for `cache-control: public, max-age=60` and `etag`. Then send the ETag back:

```bash
curl -i -H 'If-None-Match: "6402143662621d1b"' https://app.team1.test:8443/api/info
```
Expected: `304`. If the ETag shown by the first command is different, use that one.

### Mac 2 (Modi): edge
```bash
./scripts/edge-apply.sh status
```
```bash
cat config/live/team-https.conf
```

### Mac 3 and Mac 4: backends
Mac 3:
```bash
curl -i http://localhost:3001/api/status
```
Mac 4:
```bash
curl -i http://localhost:3002/api/status
```

---

## Part 3: Extension demos

Finish one demo and restore it before starting the next.

### A. Backup DNS
1. **Mac 4 (client):** both DNS servers must be set (Part 1, step 6).
2. **Mac 1:**
```bash
./scripts/mac1.sh stop
```
3. **Mac 4:**
```bash
./scripts/phase2-demo.sh flush
```
```bash
./scripts/phase2-demo.sh dns
```
```bash
./scripts/phase2-demo.sh lb 4
```
Expected: primary shows no answer, backup answers, requests return 200.

4. **Restore, Mac 1:**
```bash
./scripts/mac1.sh start
```

Optional, to show DNS packets live on a client (stop with Ctrl-C):
```bash
sudo tcpdump -i en0 -nn port 53
```

### D. Backend failure
1. **Mac 3:** press **Ctrl-C** in the Backend A terminal.
2. **Any client:**
```bash
./scripts/phase2-demo.sh lb 6
```
Expected: all 200, only B.

3. **Restore, Mac 3:**
```bash
python3 backend/server.py A 3001
```
4. **Any client:** wait a few seconds, then:
```bash
./scripts/phase2-demo.sh lb 8
```
Expected: A and B both answer.

Extra, both backends down: press Ctrl-C on Mac 3 and Mac 4. A client gets `502`. Start both again.

### C. Firewall isolation
1. **Mac 3 and Mac 4:**
```bash
./scripts/pf-isolate.sh status
```
```bash
./scripts/render-configs.sh
```
```bash
./scripts/pf-isolate.sh enable
```
2. **Mac 1:**
```bash
./scripts/phase2-demo.sh isolation
```
```bash
./scripts/phase2-demo.sh lb 8
```
Expected: both backend ports `BLOCKED`, 8 of 8 through the edge return 200.

3. **Mac 2:** the edge is still allowed.
```bash
nc -vz -G 3 10.7.1.253 3001
```
```bash
nc -vz -G 3 10.7.23.21 3002
```
4. **Mac 3 and Mac 4:** show the counters on the `block` rule.
```bash
./scripts/pf-isolate.sh status
```
5. **Restore, Mac 3 and Mac 4. Do not skip this.**
```bash
./scripts/pf-isolate.sh disable
```
6. **Mac 1:** both ports show `OPEN` again.
```bash
./scripts/phase2-demo.sh isolation
```

### B and E. TTL, cache and switching to the standby edge
1. **Mac 3, in Apple's Terminal app, new window** (Backend A keeps running):
```bash
./scripts/edge-apply.sh standby
```
2. **Mac 1:** test the standby before changing DNS.
```bash
curl -i --resolve app.team1.test:8443:10.7.1.253 https://app.team1.test:8443/api/status
```
Expected: 200 and `x-edge: mac3-standby`.

3. **Mac 4:** use Mac 1 only, so the backup cannot give the old address.
```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.30.25
```
```bash
./scripts/phase2-demo.sh watch
```
4. **Mac 1:** switch to the standby.
```bash
./scripts/mac1.sh standby
```
5. **Mac 1:** ask the DNS server directly. It gives the new IP at once.
```bash
dig app.team1.test @10.7.30.25
```
6. **Mac 4:** keep watching. Do not flush. It moves to `mac3-standby` when its saved answer expires, normally within 30 seconds.
7. **Mac 4, second terminal:** type these, but press Enter on the second only after step 8.
```bash
sudo -v
```
```bash
./scripts/phase2-demo.sh flush
```
8. **Mac 1:** switch back.
```bash
./scripts/mac1.sh primary
```
As soon as it finishes, Mac 4 presses Enter on the flush. The watch should show `mac2-primary`. If it changed before the flush, say so: that run does not prove the flush caused it.

9. **Restore, Mac 4:** press Ctrl-C on the watch, then:
```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.30.25 10.7.23.21
```
10. **Restore, Mac 3:** stop the standby edge only. Backend A keeps running.
```bash
./scripts/edge-apply.sh stop
```

---

## Part 4: Extension F, the teacher breaks something

Check in this order and stop at the first failure: **client settings → DNS → TCP → TLS → HTTP.** Say each result out loud. Change nothing until you can name the broken layer.

Run on a client:

**1. Client settings** (expect Mac 1, then Mac 4)
```bash
scutil --dns | grep nameserver | head -2
```
**2. DNS** (both should answer `10.7.29.185`)
```bash
dig app.team1.test @10.7.30.25
```
```bash
dig app.team1.test @10.7.23.21
```
**2b. The Mac's saved answer**
```bash
dscacheutil -q host -a name app.team1.test
```
**3. TCP** (expect `succeeded`)
```bash
nc -vz -G 3 10.7.29.185 8443
```
**4. TLS** (expect `SSL certificate verify ok`)
```bash
curl -v https://app.team1.test:8443/ 2>&1 | grep -E "subject:|issuer:|verify|SSL"
```
**5. HTTP** (expect 200, and both A and B)
```bash
./scripts/phase2-demo.sh lb 6
```

| You see | Problem is likely in | Next step |
|---|---|---|
| Wrong nameservers | Client settings | Set DNS again (Part 1, step 6) |
| No DNS answer | DNS server | `./scripts/dns-ctl.sh primary status` (Mac 1) or `backup status` (Mac 4) |
| Wrong IP | DNS record | `grep host-record config/live/dnsmasq*.conf` |
| `dig` right, saved answer old | Client cache | `./scripts/phase2-demo.sh flush` |
| `Connection refused` on 8443 | Edge is not listening | Mac 2: `./scripts/edge-apply.sh status` |
| Certificate error | TLS | Check `subject` and `issuer`; do not use `-k` |
| `502` or `504` | Edge to backend | Mac 2 error log, below |
| Only A or only B | One backend or upstream | Mac 2 error log, then check that backend |

Mac 2 error log:
```bash
tail -n 20 "$(brew --prefix)/var/log/nginx/error.log"
```

If the log shows `no live upstreams` or `No route to host` while another Mac can reach both backends, run these on Mac 2 in Apple's Terminal app:
```bash
./scripts/edge-apply.sh stop
```
```bash
./scripts/edge-apply.sh primary
```

---

## Part 5: Quick fixes by Mac

| Mac | Check | Restart |
|---|---|---|
| 1 | `./scripts/mac1.sh status` | `./scripts/mac1.sh restart` |
| 2 | `./scripts/edge-apply.sh status` | `./scripts/edge-apply.sh primary` |
| 3 | `curl -i http://localhost:3001/api/status` | `python3 backend/server.py A 3001` |
| 4 | `./scripts/dns-ctl.sh backup status` | `./scripts/dns-ctl.sh backup restart` |
| 4 | `curl -i http://localhost:3002/api/status` | `python3 backend/server.py B 3002` |

---

## Part 6: After the demo is over

Run these only when the teacher has finished.

1. **Mac 4 and every other client Mac:**
```bash
sudo networksetup -setdnsservers Wi-Fi empty
```
2. **Mac 1:**
```bash
./scripts/mac1.sh normal
```
3. **Mac 2:**
```bash
./scripts/edge-apply.sh stop
```
4. **Mac 3:** press Ctrl-C on Backend A. Then:
```bash
./scripts/pf-isolate.sh disable
```
```bash
./scripts/edge-apply.sh stop
```
5. **Mac 4:** press Ctrl-C on Backend B. Then:
```bash
./scripts/pf-isolate.sh disable
```
```bash
./scripts/dns-ctl.sh backup stop
```
