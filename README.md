# Computer Networks — Private Network Service Platform

A private multi-tier network service built on a local LAN with **four Macs**: private DNS with a backup resolver, an nginx TLS edge and load balancer, two backends, backend isolation, and a standby edge.

| Machine | Owner | Role |
|---|---|---|
| Mac 1 | Abhishek | Primary DNS (dnsmasq), test client |
| Mac 2 | Modi | nginx edge: TLS and load balancer (:8080, :8443) |
| Mac 3 | Kapish | Backend A (:3001), standby edge |
| Mac 4 | Vikash | Backend B (:3002), backup DNS, test client |

## Where to look

| You need | Open |
|---|---|
| Topology, IP table, request flow by layer | [docs/01-architecture.md](docs/01-architecture.md) |
| Phase 2 final report | [docs/12-phase2-report.md](docs/12-phase2-report.md) |
| Phase 2 guides: DNS, edge, backend and firewall | [docs/10-phase2-dns.md](docs/10-phase2-dns.md), [docs/10-phase2-edge.md](docs/10-phase2-edge.md), [docs/11-phase2-backend.md](docs/11-phase2-backend.md) |
| What is done and what remains | [docs/14-phase2-status.md](docs/14-phase2-status.md) |
| Mac 1 DNS commands and one-key control panel | [docs/16-mac1-commands.md](docs/16-mac1-commands.md) |
| Mac 1 viva guide | [docs/17-mac1-viva-guide.md](docs/17-mac1-viva-guide.md) |
| [Demo day commands](docs/18-demo-day-commands.md) | Commands for Mac 1 to 4, in demo order |
| Mac 1 work log | [docs/15-worklog-mac1.md](docs/15-worklog-mac1.md) |
| Troubleshooting runbook | [docs/13-troubleshooting-runbook.md](docs/13-troubleshooting-runbook.md) |
| Phase 2 evidence | [evidence/phase2/](evidence/phase2/) |
| Phase 1 build documents (three-Mac layout) | `docs/02` to `docs/09` |
| Phase 1 packet capture | [evidence/G-packet-capture/](evidence/G-packet-capture/) |

## Configuration bundle

| File | Contents |
|---|---|
| [config/dnsmasq.conf.template](config/dnsmasq.conf.template) | Primary DNS, TTL 30 |
| [config/phase2/dnsmasq-backup.conf.template](config/phase2/dnsmasq-backup.conf.template) | Backup DNS |
| [config/nginx/](config/nginx/) | Edge config; renders the primary and standby edges. Phase 1 version: git commit `2faaaef` |
| [config/pf-backends.conf.template](config/pf-backends.conf.template) | Backend firewall rules |
| [docs/06-tls.md](docs/06-tls.md) | Certificate setup notes |
| [docs/04-backends.md](docs/04-backends.md) | Backend launch instructions |

`config/live/` holds rendered files and is not committed.

## Quick start

1. Copy `config/cn-team.env.example` to `~/cn-team.env` on every Mac and fill in the four current addresses.
2. On every Mac run `./scripts/render-configs.sh`.
3. Mac 1: `./scripts/dns-ctl.sh primary start`. Mac 4: `./scripts/dns-ctl.sh backup start`.
4. Mac 3: `python3 backend/server.py A 3001`. Mac 4: `python3 backend/server.py B 3002`.
5. Mac 2: `./scripts/edge-apply.sh primary`.
6. On clients: `sudo networksetup -setdnsservers Wi-Fi <MAC1_IP> <MAC4_IP>`, trust the team root CA, then `./scripts/demo.sh all`.

When finished, restore DNS on each Mac with `sudo networksetup -setdnsservers Wi-Fi empty`.

## Scripts

| Script | Use |
|---|---|
| `mac1.sh` | One-key control panel for Mac 1 (also `Mac1.command`) |
| `render-configs.sh` | Build `config/live/` from the env file |
| `dns-ctl.sh` | Start, stop, status and record change for either resolver |
| `edge-apply.sh` | Apply the primary or standby nginx config, or stop nginx |
| `pf-isolate.sh` | Enable, inspect and roll back backend isolation |
| `phase2-demo.sh` | Client demos: `lb`, `watch`, `dns`, `isolation`, `flush` |
| `demo.sh` | Read-only checks of the whole system |
| `make-certs.sh` | Create the team root CA and server certificate (never commit keys) |
