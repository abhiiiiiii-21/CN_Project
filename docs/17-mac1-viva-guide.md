# Mac 1 Viva Guide — DNS (Abhishek)

## 1. Your 30-second introduction

> "I handled Mac 1, the private DNS server of our network. It runs dnsmasq and tells clients that `app.team1.test` and `api.team1.test` are at Mac 2, our nginx edge. In Phase 2 I added a 30-second TTL and prepared a backup DNS server on Mac 4. I demonstrated three things: clients keep resolving when my DNS is stopped, clients use a cached answer until it expires or is flushed, and we can move traffic to a standby edge just by changing a DNS record."

## 2. What DNS does in our project

DNS is like a phone book. It turns a name into an IP address. It does **not** carry the web traffic.

1. The client asks Mac 1: "What is the IP of `app.team1.test`?" (UDP port 53)
2. Mac 1 answers: Mac 2's IP, valid for 30 seconds.
3. The client opens a TCP connection to Mac 2 on port 8443.
4. TLS handshake: the client checks Mac 2's certificate.
5. The client sends the HTTPS request. nginx forwards it to Backend A (Mac 3) or Backend B (Mac 4).

Your part is steps 1 and 2.

Addresses in our lab session: Mac 1 `10.7.30.25`, Mac 2 `10.7.29.185`, Mac 3 `10.7.1.253`, Mac 4 `10.7.23.21`.

## 3. Your config, line by line

| Line | Meaning |
|---|---|
| `listen-address=127.0.0.1,10.7.30.25` | Answer on my own Mac and on my LAN address |
| `bind-interfaces` | Open sockets only on those addresses |
| `no-resolv` | Do not take upstream servers from the system's resolver file; use the ones listed here |
| `server=8.8.8.8`, `server=1.1.1.1` | Forward other names, such as `google.com`, to these servers |
| `local=/team1.test/` | Answer `team1.test` only from my own data; never forward it |
| `local-ttl=30` | Clients may cache my local answers for 30 seconds |
| `host-record=app.team1.test,10.7.29.185` | `app` points to Mac 2 |
| `host-record=api.team1.test,10.7.29.185` | `api` points to Mac 2 |
| `domain-needed` | Do not forward names that have no dot |
| `bogus-priv` | Do not forward reverse lookups for private IP addresses |
| `log-queries` | Log every query, useful for proof and debugging |

The IPs are not typed by hand. `~/cn-team.env` holds them, and `render-configs.sh` builds the config from a template.

## 4. Your three demonstrations

### Extension A — Backup DNS

- **Problem:** if the only DNS server stops, nobody can find the website by name.
- **What we did:** a second dnsmasq on Mac 4 with the same records. Clients listed Mac 1 and then Mac 4.
- **Demo:** stop my DNS. On the client, flush the cache, then open the website.
- **Result:** HTTP 200. In Modi's capture, the query went to my Mac at 19:43:55.377. With no reply, it went to Mac 4 at 19:43:57.389, about 2 seconds later.
- **Say:** "The client moved to the backup by itself. I did not change anything on the client."
- **Who did what:** I ran the primary and wrote the backup config. Vikash ran the backup. Modi was the client and took the capture.

### Extension B — TTL and record change

- **Problem:** after a DNS change, do clients see it immediately? No, because they cache.
- **What we did:** TTL 30. I changed `app` from Mac 2 to Mac 3, and Vikash watched.
- **Result:** Vikash kept the old IP for about 12 seconds after my server had the new one, then changed. The wait is whatever time is left on the cached answer, from 0 to 30 seconds.
- **Flush test:** my DNS restarted with the new record at 22:58:59. At 22:59:08 Vikash still had the old IP. After the flush, in the same second, Vikash had the new IP.
- **Why web requests failed in the first test:** the standby nginx was not running. DNS pointed correctly, but nothing was serving there.
- **Say:** "DNS only gives an address. It does not check whether a service is running there."

### Extension E — DNS cutover (my part: the DNS change)

- **Idea:** move users from one edge to another without changing anything on the clients.
- **What we did:** Kapish started a standby nginx on Mac 3. I changed `app` to Mac 3, and later changed it back.
- **Result of the timing test:** my DNS restarted at 23:25:12. Modi's fresh lookup got Mac 3 at 23:25:12. Vikash's cached client stayed on the old edge until at least 23:25:18 and used the standby at 23:25:20. Times are from different Macs' clocks.
- **First cutover run:** every watch line we recorded returned HTTP 200, going and coming back, because both edges were running.
- **Say:** "Keep the old server running for at least the TTL, because some clients still use it."

## 5. Commands to show

```bash
./scripts/mac1.sh                               # control panel
dig app.team1.test @10.7.30.25                  # ask my server directly
dig app.team1.test @10.7.23.21                  # ask the backup
dscacheutil -q host -a name app.team1.test      # what this Mac resolves (uses its cache)
scutil --dns | grep nameserver | head -2        # which DNS servers this Mac uses
./scripts/dns-ctl.sh primary point-app <IP>     # change the app record
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder   # flush on macOS
sudo lsof -nP -i :53                            # who is listening on port 53
```

In `dig` output, `app.team1.test. 30 IN A 10.7.29.185` means: name, TTL 30 seconds, internet class, A record, IPv4 address.

## 6. Cross-questions and answers

### DNS basics

1. **What is DNS?** A system that turns names into IP addresses and other records.
2. **Which port and protocol?** Port 53. Normal queries use UDP; TCP is used for large or truncated answers and zone transfers.
3. **Why UDP?** A query and answer are small. UDP needs no handshake, so it is fast. If there is no reply, the client retries.
4. **Which OSI or TCP/IP layer?** Application layer. It travels over UDP or TCP at the transport layer.
5. **What is an A record?** Name to IPv4 address. AAAA is for IPv6, CNAME is an alias, NS names the zone's DNS server, MX is for mail, PTR is IP to name.
6. **What is dnsmasq?** A small DNS forwarder (it can also do DHCP; we use only DNS). It answers our local names itself and forwards the rest.
7. **Is yours a recursive resolver?** No. dnsmasq forwards outside names to 8.8.8.8 or 1.1.1.1, which do the resolving.
8. **How is a public name normally resolved?** The resolver asks a root server, then the top-level domain server such as `.com`, then the domain's authoritative server, and caches the answer.
9. **Recursive and iterative?** Recursive: "get me the final answer." Iterative: each server replies with the next server to ask.

### Our design

10. **Why `.test` and not `.local`?** `.test` is reserved for testing. macOS uses `.local` for multicast DNS (Bonjour), so it would conflict.
11. **Why do both names point to Mac 2, not to the backends?** Mac 2 is the single entry point. It does TLS and load balancing, and the backends can change without clients knowing.
12. **How does a client know to ask your server?** We set its DNS servers with `networksetup`.
13. **What happens for `google.com`?** My server forwards it to the upstream server and returns the answer.
14. **What for `abc.team1.test`?** NXDOMAIN, meaning the name does not exist. It is not forwarded.
15. **Why do you need `sudo`?** Port 53 is a privileged port on our setup.

### TTL and cache

16. **What is TTL?** How long an answer may be cached.
17. **Why 30 seconds?** Short enough to see changes during a demo.
18. **What was it before?** 0 in Phase 1, the dnsmasq default for its local records, so they were not meant to be cached.
19. **Low or high TTL: trade-off?** Low: changes spread quickly, but there are more queries. High: fewer queries and faster repeat lookups, but changes spread slowly.
20. **Why does `dig` show the new IP while the client has the old one?** `dig` asks the DNS server directly. Applications use the macOS resolver, which has a cache.
21. **Where can DNS be cached?** The application or browser, the operating system, and DNS resolvers on the way.
22. **Does flushing your Mac flush other Macs?** No. Each Mac has its own cache.
23. **Does a DNS change break an open connection?** No. An existing TCP connection already has the IP. DNS affects new lookups.
24. **Why did the record change need a restart?** dnsmasq reads `host-record` lines when it starts, so `point-app` restarts it. An early version did not restart a running server; this was fixed.

### Backup DNS

25. **Is it automatic primary and secondary?** The client's resolver decides which listed server to use. In our test it moved to the backup after about 2 seconds. macOS does not promise to always try them in strict order.
26. **How are the two servers synchronised?** They are not. Both have the same records from the same variables. A change must be made on both. Real DNS systems can use zone transfers from a primary to secondaries.
27. **What if you change only one?** Clients can get different answers depending on which server they ask.
28. **Why not use 8.8.8.8 as the backup?** It does not know our private name and would answer NXDOMAIN. That is a valid answer, so the client would not go on to another server.
29. **DNS failure and application failure: difference?** DNS failure: the name cannot be resolved, although machines can still be reached by IP. Application failure: the name resolves, but the service is down, for example nginx returns 502 when both backends are stopped.

### Cutover

30. **What is a DNS-based cutover?** Changing a record so new lookups go to another server.
31. **Why did Vikash still reach the old edge?** Vikash's Mac had the old answer cached.
32. **Is the cutover instant?** No. Each client moves when its cached answer expires or is flushed.
33. **How is this done in production?** For example with Route 53: lower the TTL in advance, change the record, keep the old server running, then raise the TTL.
34. **Did you change `api` too?** No. `point-app` changes only `app`.
35. **Why did the certificate still work on the standby?** It is issued for the name `app.team1.test`, not for an IP, and the standby had that certificate and key.
36. **Weakness of DNS failover?** It was manual, and clients keep old answers until they expire. dnsmasq did not check whether the edge was healthy.

### Troubleshooting

37. **The website does not open. What do you check?** In order: client DNS settings, DNS answer, TCP to port 8443, TLS certificate, then HTTP status.
38. **`dig` times out. Why?** The DNS server is stopped, the IP is wrong, or the network or a firewall blocks port 53.
39. **NXDOMAIN and timeout: difference?** NXDOMAIN: a server answered that the name does not exist. Timeout: no answer arrived.
40. **DNS is correct but the site fails. What next?** Test TCP with `nc -vz <ip> 8443`, then TLS and HTTP with `curl -v`.
41. **How can you see DNS packets?** With Wireshark or `tcpdump` on port 53. In Wireshark, the filter is `dns`.
42. **Is your DNS secure?** Our queries are plain text. Anyone able to capture the traffic can read them, and DNS can be spoofed. DNSSEC checks that records are authentic; DNS over HTTPS or TLS encrypts the queries.

## 7. Short answers about teammates' parts

The viva can ask you about the whole system.

| Topic | Short answer |
|---|---|
| nginx | Reverse proxy and load balancer. Clients connect to it; it forwards to the backends, round-robin |
| TLS termination | TLS ends at nginx. nginx to backend is plain HTTP |
| TLS handshake | ClientHello, ServerHello, certificate, key exchange, Finished. In TLS 1.3 the certificate is already encrypted |
| TCP handshake | SYN, SYN-ACK, ACK |
| Failover (Ext D) | Passive health check: nginx notices a failure when a real request fails, retries on the other backend, and skips the failed one for a short time |
| Firewall (Ext C) | macOS `pf` allows ports 3001 and 3002 only from Mac 2, Mac 3 (standby) and the machine itself. Others are dropped, so they time out |
| Refused and timeout | Refused: usually nothing is listening. Timeout: no reply, for example packets are dropped |
| 502 | nginx works but cannot get a valid response from a backend |
| Caching and 304 | `Cache-Control: max-age=60` lets the client reuse a response. With `ETag` and `If-None-Match`, an unchanged resource returns 304 without the body |
| Single point of failure | The active edge, Mac 2. Fixing it needs two edges with automatic failover, for example a shared virtual IP or health-checked DNS |

## 8. Do not say these

- Do not say the two DNS servers sync automatically.
- Do not say macOS always asks the primary first.
- Do not say DNS does load balancing in our project. nginx does.
- Do not say a change always takes exactly 30 seconds. It is at most the remaining TTL for a cached answer.
- Do not say you took Modi's packet capture.
- If you do not know an answer, say what you would check, and how.

## 9. Before the viva tomorrow

1. **IPs can change on a new day.** On every Mac run `ipconfig getifaddr en0`. If any IP changed, update `~/cn-team.env` on all four Macs and run `./scripts/render-configs.sh` on each. The IPs in this guide are from the 25 November session.
2. Join the same Wi-Fi, then follow the demo order in [16-mac1-commands.md](16-mac1-commands.md).
3. Press `d` in the control panel and check with `i`. The panel's admin actions had only been tested with `sudo` simulated when this guide was written, so try it early.
4. Practise sections 1 and 4 aloud twice.
5. Ask a teammate to ask you ten questions from section 6 in random order.
