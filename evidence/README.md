# Evidence & Verification Artifacts

This directory stores experimental evidence, terminal outputs, screenshots, and packet captures gathered during test execution and demonstration of the **Computer Networks Phase 1 — Private Network Service Platform**.

> **Note:** Evidence files will be populated during testing and live demonstrations. No fabricated screenshots or mock outputs are placed here in advance.

---

## Directory Index & Expected Evidence

### `A-lan/`
- Local network topology diagrams and IP configuration outputs (`ifconfig`, `ipconfig getifaddr en0`).
- Inter-node connectivity test results (`ping` across Mac 1, Mac 2, and Mac 3).

### `B-dns/`
- DNS query traces demonstrating resolution via Mac 1 (`dig @MAC1_IP app.team1.test` and `dig @MAC1_IP api.team1.test`).
- Verification that requests resolve to Mac 2 IP (`10.7.19.92`).
- Verification of upstream DNS resolution (`dig @MAC1_IP google.com`).

### `C-backends/`
- Verification of independent backend services running on Mac 3 (`curl http://MAC3_IP:3001` and `curl http://MAC3_IP:3002`).
- Validation of direct response headers (`X-Backend: A` and `X-Backend: B`).

### `D-load-balancing/`
- Repeated HTTP/HTTPS requests to Mac 2 (`curl http://app.team1.test:8080/` or `https://app.team1.test:8443/`).
- Logs demonstrating round-robin alternating distribution between Backend A and Backend B.

### `E-tls/`
- Verbose curl handshake logs (`curl -v --cacert ... https://app.team1.test:8443`).
- Screenshots showing browser padlock and validated certificate chain details for `app.team1.test`.

### `F-caching/`
- HTTP response header captures showing `Cache-Control` and `ETag`.
- Conditional request outputs with `If-None-Match` demonstrating HTTP `304 Not Modified`.
- Verification of `no-store` status/dynamic endpoint behaviors.

### `G-packet-capture/`
- Packet capture files (`.pcapng`) recorded on Mac 3 with Wireshark.
- Filtered screenshots documenting:
  - DNS query/response packets
  - TCP 3-way handshake (`SYN`, `SYN-ACK`, `ACK`)
  - TLS 1.2 / TLS 1.3 cryptographic handshakes
  - HTTP application data payloads

### `failures/`
- Documented outputs and behavior for test scenarios F1 through F5:
  - **F1**: Wrong DNS server specified by client.
  - **F2**: Wrong / unconfigured DNS record query.
  - **F3**: Backend A failure (Backend B remains active, seamless proxy handling).
  - **F4**: Both backends down (nginx returns `502 Bad Gateway`).
  - **F5**: Request sent to incorrect destination port.
