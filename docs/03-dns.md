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

The internal domain namespace is configured as `team1.test`:

| Fully Qualified Domain Name (FQDN) | Record Type | Target Address | Purpose |
|---|---|---|---|
| `app.team1.test` | A | `10.7.19.92` (`MAC2_IP`) | Web application ingress at Mac 2 edge |
| `api.team1.test` | A | `10.7.19.92` (`MAC2_IP`) | API service ingress at Mac 2 edge |

Both local domain names resolve directly to the **Mac 2 edge proxy**, which terminates TLS and load-balances across the backend services on Mac 3.

---

## dnsmasq Configuration on Mac 1

The verified active configuration (`config/live/dnsmasq.conf`) deployed on Mac 1 is:

```text
listen-address=127.0.0.1,10.7.21.145
bind-interfaces

no-resolv
server=8.8.8.8
server=1.1.1.1

local=/team1.test/
host-record=app.team1.test,10.7.19.92
host-record=api.team1.test,10.7.19.92

domain-needed
bogus-priv
log-queries
```

### Directive Breakdown
- `listen-address=127.0.0.1,10.7.21.145`: Restricts listener to loopback and LAN IP.
- `bind-interfaces`: Binds specifically to the specified interfaces.
- `no-resolv`: Ignores host `/etc/resolv.conf` to avoid recursive loops.
- `server=8.8.8.8`: Primary upstream resolver for external domains.
- `server=1.1.1.1`: Secondary fallback upstream resolver.
- `local=/team1.test/`: Queries for `team1.test` are answered authoritatively from local records only and never forwarded.
- `host-record`: Maps `app.team1.test` and `api.team1.test` directly to Mac 2 (`10.7.19.92`).
- `domain-needed`: Blocks plain names without dots from being forwarded.
- `bogus-priv`: Blocks reverse lookups for private IP ranges from being forwarded upstream.
- `log-queries`: Emits query logs to stdout/stderr for demonstration and debugging.

---

## DNS Verification Commands

### 1. Local Resolution from Mac 1 (`@127.0.0.1`)
Verify internal domain resolution on the loopback interface:
```bash
dig @127.0.0.1 app.team1.test +short
# Expected output: 10.7.19.92

dig @127.0.0.1 api.team1.test +short
# Expected output: 10.7.19.92
```

### 2. External Upstream Forwarding Check
Verify that non-local queries are forwarded to upstream resolvers:
```bash
dig @127.0.0.1 google.com +short
# Expected output: Public IP addresses for google.com
```

### 3. Remote Resolution from Other Macs (`@10.7.21.145`)
From Mac 2, Mac 3, or test client workstations:
```bash
dig @10.7.21.145 app.team1.test +short
# Expected output: 10.7.19.92

dig @10.7.21.145 api.team1.test +short
# Expected output: 10.7.19.92

dig @10.7.21.145 google.com +short
# Expected output: Public IP addresses for google.com
```

---

## TODO: Future Implementation & Documentation

- [ ] Capture query logs from `dnsmasq` under active load (`log-queries` output).
- [ ] Document DNS caching and TTL behaviors observed during testing.
- [ ] Measure DNS query latency vs direct IP connections.
- [ ] Place terminal output captures in `evidence/B-dns/`.
