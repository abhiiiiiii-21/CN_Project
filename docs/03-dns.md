# Private DNS Architecture and Configuration

## Overview

The platform uses **Mac 1** as a dedicated private Domain Name System (DNS) server running `dnsmasq`. Mac 1 provides local authoritative name resolution for internal team services under the `.test` top-level domain while forwarding external internet queries to upstream resolvers.

---

## Machine Role: Mac 1

- **Host:** Mac 1
- **Service:** `dnsmasq`
- **Transport / Port:** UDP/TCP port 53
- **Network Interface:** Bound to `127.0.0.1` and `MAC1_IP` (`10.7.21.145`)

---

## Domain Namespace and Records

The internal domain namespace is configured as `TEAM.test` (e.g., `team1.test`):

| Fully Qualified Domain Name (FQDN) | Record Type | Target Address | Purpose |
|---|---|---|---|
| `app.team1.test` | A | `MAC2_IP` (`10.7.19.92`) | Web application ingress at Mac 2 edge |
| `api.team1.test` | A | `MAC2_IP` (`10.7.19.92`) | API service ingress at Mac 2 edge |

Both local subdomains resolve directly to the **Mac 2 edge proxy**, which handles TLS termination and backend load balancing.

---

## Upstream Forwarding Configuration

External resolution is configured so that client nodes pointing to Mac 1 can still resolve standard internet domains:
- **Primary Upstream:** `COLLEGE_DNS` (e.g., `8.8.8.8`)
- **Secondary Upstream:** `1.1.1.1` (Cloudflare public DNS)
- `no-resolv` is set in `dnsmasq.conf` to avoid reading local `/etc/resolv.conf` loops.
- `bogus-priv` and `domain-needed` prevent private queries from leaking to external resolvers.

---

## DNS Verification Commands

To verify DNS functionality from any host on the LAN:

### 1. Authoritative Local Record Lookup
```bash
dig @MAC1_IP app.team1.test +short
# Expected output: MAC2_IP (e.g. 10.7.19.92)

dig @MAC1_IP api.team1.test +short
# Expected output: MAC2_IP (e.g. 10.7.19.92)
```

### 2. Upstream Internet Forwarding Check
```bash
dig @MAC1_IP google.com +short
# Expected output: Public IP address of google.com
```

### 3. macOS System DNS Resolution Check
```bash
dscacheutil -q host -a name app.team1.test
```

---

## TODO: Future Implementation & Documentation

- [ ] Capture query logs from `dnsmasq` under active load (`log-queries` output).
- [ ] Document DNS caching and TTL behaviors observed during testing.
- [ ] Measure DNS query latency vs direct IP connections.
- [ ] Place terminal output captures in `evidence/B-dns/`.
