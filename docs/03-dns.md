# Private DNS Architecture and Configuration

## Overview

The platform uses **Mac 1** as a dedicated private Domain Name System (DNS) server running `dnsmasq`. Mac 1 provides local authoritative name resolution for internal team services under the `.test` top-level domain while forwarding external internet queries to upstream resolvers.

---

## Machine Role: Mac 1

- **Host:** Mac 1
- **Service:** `dnsmasq`
- **Transport / Port:** UDP/TCP port 53
- **Network Interface:** Bound to loopback (`127.0.0.1`) and LAN interface `MAC1_IP` (`10.7.21.145`)

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

The verified active configuration ([config/live/dnsmasq.conf](../config/live/dnsmasq.conf)) deployed on Mac 1 is:

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
- `server=8.8.8.8`: Primary upstream resolver (`COLLEGE_DNS`) for external domains.
- `server=1.1.1.1`: Secondary fallback upstream resolver (Cloudflare DNS).
- `local=/team1.test/`: Queries for `team1.test` are answered authoritatively from local records only and never forwarded.
- `host-record`: Maps `app.team1.test` and `api.team1.test` directly to Mac 2 (`10.7.19.92`).
- `domain-needed`: Blocks plain names without dots from being forwarded.
- `bogus-priv`: Blocks reverse lookups for private IP ranges from being forwarded upstream.
- `log-queries`: Emits query logs for demonstration and debugging.

---

## DNS Verification Commands & Observed Results

### 1. Local Resolution from Mac 1 (`@127.0.0.1`)
```bash
dig @127.0.0.1 app.team1.test +noall +answer
# Observed: app.team1.test. 0 IN A 10.7.19.92
# Server:   127.0.0.1#53(127.0.0.1)

dig @127.0.0.1 api.team1.test +noall +answer
# Observed: api.team1.test. 0 IN A 10.7.19.92
# Server:   127.0.0.1#53(127.0.0.1)
```

### 2. External Upstream Forwarding Check
```bash
dig @127.0.0.1 google.com +noall +answer
# Observed: Resolved public IP addresses (e.g., 142.250.29.100) via upstream forwarding
```

### 3. Remote Resolution from Other Macs (`@10.7.21.145`)
From Mac 2, Mac 3, or test client workstations:
```bash
dig @10.7.21.145 app.team1.test +short
# Observed: 10.7.19.92

dig @10.7.21.145 api.team1.test +short
# Observed: 10.7.19.92
```

---

## Evidence Artifacts

DNS verification traces are preserved in `evidence/B-dns/`:
- [dnsmasq-live.png](../evidence/B-dns/dnsmasq-live.png): Live `dnsmasq` service startup and active configuration on Mac 1.
- [dig-mac1.png](../evidence/B-dns/dig-mac1.png): Terminal capture of local resolution for `app.team1.test` and `api.team1.test`.
- [dig-mac3.png](../evidence/B-dns/dig-mac3.png): Remote query execution from Mac 3 querying Mac 1 (`10.7.21.145:53`).
- [internet-dns-forwarding.png](../evidence/B-dns/internet-dns-forwarding.png): Upstream forwarding verification resolving `google.com`.
- [team-env-mac1.png](../evidence/B-dns/team-env-mac1.png): IP environment variable inspection on Mac 1.

---

## Implementation & Testing Notes

- DNS caching and TTL behaviors under load: *Not measured in Phase 1*.
- DNS query latency benchmarks vs direct IP: *Not measured in Phase 1*.
