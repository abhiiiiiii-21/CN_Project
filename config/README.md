# Configuration Management

This directory contains configuration templates and environment specifications for the **Computer Networks Phase 1 — Private Network Service Platform**.

The project operates across **exactly three Macs**:
- **Mac 1**: Private DNS Server (`dnsmasq`) on UDP port 53.
- **Mac 2**: Edge reverse proxy, load balancer, and TLS termination (`nginx`) on ports 8080 and 8443.
- **Mac 3**: Dual Python backend instances (Ports 3001 and 3002) and Wireshark packet capture.

> **Note:** Both backend instances (Backend A and Backend B) run concurrently on Mac 3.

---

## Directory Structure

```text
config/
├── README.md                 # Configuration documentation and guidelines
├── cn-team.env.example       # Template environment variables for network setup
├── dnsmasq.conf.template     # dnsmasq configuration template for Mac 1
├── nginx/
│   ├── team-http.conf.template   # nginx HTTP port 8080 redirect template
│   └── team-https.conf.template  # nginx HTTPS port 8443 TLS reverse proxy template
└── live/
    ├── dnsmasq.conf          # Active verified dnsmasq configuration for Mac 1
    ├── team-http.conf        # Active verified nginx HTTP 8080 redirect config
    └── team-https.conf       # Active verified nginx HTTPS 8443 TLS config
```

---

## Environment Variables & Template Placeholders

Configurations use standardized placeholders that are injected via `./scripts/render-configs.sh` from the deployment environment (`~/cn-team.env`):

| Variable / Placeholder | Description | Example / Default Value |
|---|---|---|
| `TEAM` | Team identifier / domain namespace | `team1` (`app.$TEAM.test`, `api.$TEAM.test`) |
| `MAC1_IP` | IPv4 address of Mac 1 (Private DNS :53) | Discovered LAN IP (e.g. `10.7.21.145`) |
| `MAC2_IP` | IPv4 address of Mac 2 (Nginx Edge / TLS / LB) | Discovered LAN IP (e.g. `10.7.19.92`) |
| `MAC3_IP` | IPv4 address of Mac 3 (Dual Backends + Wireshark) | Discovered LAN IP (e.g. `10.7.29.148`) |
| `COLLEGE_DNS` | Upstream network DNS resolver | `8.8.8.8` (or campus resolver) |
| `CERTIFICATE_PATH`| Path to generated server TLS certificate | `$(brew --prefix)/etc/nginx/certs/app.crt` |
| `PRIVATE_KEY_PATH`| Path to generated server TLS private key | `$(brew --prefix)/etc/nginx/certs/app.key` |

---

## Usage Workflow

1. Copy `config/cn-team.env.example` to `~/cn-team.env` (or `config/cn-team.env`). Both are excluded from Git tracking via `.gitignore`.
2. Populate the actual discovered LAN IP addresses for `MAC1_IP`, `MAC2_IP`, and `MAC3_IP`.
3. Run `./scripts/render-configs.sh` to generate concrete configuration files into `config/live/`:
   - `config/dnsmasq.conf.template` → `config/live/dnsmasq.conf`
   - `config/nginx/team-http.conf.template` → `config/live/team-http.conf`
   - `config/nginx/team-https.conf.template` → `config/live/team-https.conf`
4. Deploy the rendered configs to the respective machines.
