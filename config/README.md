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

## Template Placeholders

Configurations use standardized placeholders that are replaced during setup:

| Placeholder | Description | Example Target |
|---|---|---|
| `TEAM` | Team identifier / domain namespace | `team1` |
| `MAC1_IP` | IPv4 address of Mac 1 (Private DNS) | `10.7.21.145` |
| `MAC2_IP` | IPv4 address of Mac 2 (nginx edge / LB) | `10.7.19.92` |
| `MAC3_IP` | IPv4 address of Mac 3 (Dual backends) | `10.7.29.148` |
| `COLLEGE_DNS` | Upstream network DNS resolver | `8.8.8.8` |
| `CERTIFICATE_PATH`| Absolute path to generated TLS certificate | `/etc/ssl/certs/team1.crt` |
| `PRIVATE_KEY_PATH`| Absolute path to generated TLS private key | `/etc/ssl/private/team1.key` |

---

## Usage Workflow

1. Copy `cn-team.env.example` to `cn-team.env` (which is excluded from Git tracking via `.gitignore`).
2. Populate actual discovered LAN IP addresses for Mac 1, Mac 2, and Mac 3.
3. Run `scripts/render-configs.sh` to generate concrete configuration files into `config/live/`.
4. Deploy the rendered configs to the respective machines.
