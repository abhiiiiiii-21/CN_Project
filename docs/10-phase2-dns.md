# Phase 2 — DNS (Mac 1)

Mac 1 owner: Abhishek. Covers Extension A (backup DNS resolver), Extension B (TTL and controlled record change) and the DNS side of Extension E (edge cutover).

| Mac | Person | Role |
|---|---|---|
| Mac 1 | Abhishek | Primary DNS (dnsmasq), test client |
| Mac 2 | Modi | nginx edge: TLS and load balancing |
| Mac 3 | Kapish | Backend A, standby edge |
| Mac 4 | Vikash | Backend B, backup DNS, test client |

## Files

| File | Purpose |
|---|---|
| `config/dnsmasq.conf.template` | Primary resolver. Adds `local-ttl=30`. |
| `config/phase2/dnsmasq-backup.conf.template` | Backup resolver for Mac 4. Same records. |
| `scripts/dns-ctl.sh` | Start, stop, status, logs and record change for either resolver. |
| `scripts/dns-demo.sh` | Client side: resolver check, watch, cache flush. |
| `scripts/render-configs.sh` | Builds `config/live/*` from `~/cn-team.env` (now needs `MAC4_IP`). |

## Setup (lab day)

Run in every new terminal:

```bash
cd ~/CN_Project
git pull --rebase --autostash
source ~/cn-team.env
```

`--autostash` is needed because rendering and `point-app` modify tracked files in `config/live/`.

Create `~/cn-team.env` from `config/cn-team.env.example` with the four current IPs (`ipconfig getifaddr en0` on each Mac), share it with the team, then:

```bash
./scripts/render-configs.sh ~/cn-team.env
```

Start the primary resolver:

```bash
./scripts/dns-ctl.sh primary start
```

On each client Mac, use the primary resolver:

```bash
sudo networksetup -setdnsservers Wi-Fi "$MAC1_IP"
```

## Extension B — TTL and record change

Only the primary should be configured on the clients during this test.

1. Client (Mac 4): `./scripts/dns-demo.sh watch`. It shows the Mac 2 IP.
2. Mac 1, show TTL 30:
   ```bash
   dig app.team1.test @"$MAC1_IP" +noall +answer
   ```
3. Mac 1, change the record:
   ```bash
   ./scripts/dns-ctl.sh primary point-app "$MAC3_IP"
   ```
4. The client keeps the Mac 2 IP until its cached entry expires (at most 30 s), then shows the Mac 3 IP.
5. Mac 1, change it back:
   ```bash
   ./scripts/dns-ctl.sh primary point-app "$MAC2_IP"
   ```
6. Client, flush the cache. The change is visible immediately:
   ```bash
   ./scripts/dns-demo.sh flush
   ```
7. Save screenshots or a recording in `evidence/phase2/B-ttl/`.

`dig` queries the server directly and does not use the macOS cache. The watch command uses `dscacheutil`, which does.

## Extension A — backup resolver

1. Mac 4: `./scripts/dns-ctl.sh backup start`
2. Mac 1, confirm both give the same answer:
   ```bash
   dig app.team1.test @"$MAC1_IP" +noall +answer
   dig app.team1.test @"$MAC4_IP" +noall +answer
   ```
3. Every client lists both resolvers, primary first:
   ```bash
   sudo networksetup -setdnsservers Wi-Fi "$MAC1_IP" "$MAC4_IP"
   ```
   Do not add the college or a public resolver. It does not know `team1.test` and would answer NXDOMAIN.
4. Capture on a client that runs no DNS server (Mac 2):
   ```bash
   sudo tcpdump -i en0 -nn -w evidence/phase2/A-backup-dns/dns-failover.pcap port 53
   ```
5. Mac 1: `./scripts/dns-ctl.sh primary stop`
6. Client: `./scripts/dns-demo.sh flush`, then `./scripts/dns-demo.sh dns`, then `curl -sI https://app.team1.test:8443/`. The primary gives no answer; the name still resolves.
7. Mac 1: `./scripts/dns-ctl.sh primary start`

## Extension E — DNS side of the cutover

Start only after the standby nginx on Mac 3 is running and the backend firewall allows Mac 3.

1. Client: `./scripts/dns-demo.sh watch`
2. Change both resolvers together so they agree:
   - Mac 1: `./scripts/dns-ctl.sh primary point-app "$MAC3_IP"`
   - Mac 4: `./scripts/dns-ctl.sh backup point-app "$MAC3_IP"`
3. Cached clients use the old edge for up to 30 s. New lookups go to the standby edge. Keep the old edge running during this window.
4. Cut back with the same two commands using `"$MAC2_IP"`.
5. Save evidence in `evidence/phase2/E-cutover/`.

## End of session

On every Mac that was pointed at the team resolvers:

```bash
sudo networksetup -setdnsservers Wi-Fi empty
```

Then on Mac 1:

```bash
./scripts/dns-ctl.sh primary stop
```

## Viva notes

- **DNS failure vs application failure.** DNS failure: the name cannot be resolved, although the hosts are still reachable by IP. Application failure: the name resolves and the edge accepts TCP and TLS, but no backend is healthy, so the edge returns 502.
- **Why `local-ttl=30`.** dnsmasq answers from its own configuration with TTL 0 by default (observed in Phase 1, see `03-dns.md`), so clients do not cache.
- **TTL.** The longest time a cached answer may be reused. Lowering it before a migration shortens the time clients keep using the old address.
- **Backup resolver.** It is a second independent server with the same records. Nothing synchronises the two, so a record change must be made on both.
- **Production equivalent.** Changing a Route 53 record during a blue/green cutover.

## Local pre-check

Before the lab, both configurations were run on Mac 1 alone, on test ports and with placeholder IPs: TTL 30, identical answers from both, record change, backup answering with the primary stopped, and NXDOMAIN for an unknown team name. Output: `evidence/phase2/B-ttl/mac1-local-precheck.txt`. It was only a pre-check. Client caching and resolver failover were tested afterwards on the four Macs; see `evidence/phase2/A-backup-dns/` and `evidence/phase2/B-ttl/`.
