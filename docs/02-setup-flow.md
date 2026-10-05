# Environment Setup and Startup Flow

## Overview

This document specifies the end-to-end setup and orchestrated initialization procedure for the three-Mac private network. Following this strict 8-step sequence ensures service dependencies are satisfied without race conditions or false connection errors.

The architecture uses **exactly three physical Macs**:
- **Mac 1**: Private DNS (`dnsmasq`) and Client
- **Mac 2**: Edge Nginx Reverse Proxy, Load Balancer, and TLS Termination
- **Mac 3**: Dual Python Backend Instances (Ports 3001 and 3002) and Wireshark Packet Capture

---

## Recommended Setup Order

```text
Step 1: Common network setup on all Macs
   │
   ▼
Step 2: Mac 1 → dnsmasq (Private DNS)
   │
   ▼
Step 3: Mac 3 → Backend A (:3001) + Backend B (:3002)
   │
   ▼
Step 4: Mac 2 → nginx HTTP (Port 8080)
   │
   ▼
Step 5: Mac 2 → TLS Termination (Port 8443)
   │
   ▼
Step 6: Configure Mac 2 and Mac 3 to use Mac 1 DNS
   │
   ▼
Step 7: Wireshark capture on Mac 3
   │
   ▼
Step 8: Final end-to-end verification
```

---

## Step 1: Common Network Setup on All Macs

### 1.1 Connect to Shared Subnet
- Connect Mac 1, Mac 2, and Mac 3 to the **same local area network** (Wi-Fi or Ethernet switch).
- Ensure client-to-client isolation (AP isolation) is disabled on the router.

### 1.2 Identify Active IP Addresses
Run on each Mac to determine its assigned IPv4 address:
```bash
ipconfig getifaddr en0
```

Verify ping reachability between all three nodes:
```bash
# From Mac 1 / Mac 2 / Mac 3:
ping -c 3 10.7.21.145   # Mac 1
ping -c 3 10.7.19.92    # Mac 2
ping -c 3 10.7.29.148   # Mac 3
```

### 1.3 Initialize Environment File
On each machine, copy the template and configure the current network values:
```bash
cp config/cn-team.env.example config/cn-team.env
```
Populate `config/cn-team.env`:
```bash
export TEAM=team1
export MAC1_IP=10.7.21.145
export MAC2_IP=10.7.19.92
export MAC3_IP=10.7.29.148
export COLLEGE_DNS=8.8.8.8
```

---

## Step 2: Mac 1 → dnsmasq Setup

On **Mac 1**, set up and run the private DNS server:

1. Install `dnsmasq` (via Homebrew if not installed):
   ```bash
   brew install dnsmasq
   ```
2. Verify configuration in `config/live/dnsmasq.conf`:
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
3. Start `dnsmasq` in the foreground for logging:
   ```bash
   sudo dnsmasq -C $(pwd)/config/live/dnsmasq.conf -d
   ```
4. Verify local resolution:
   ```bash
   dig @127.0.0.1 app.team1.test +short
   # Output: 10.7.19.92
   ```

---

## Step 3: Mac 3 → Backend A + Backend B

Both backend instances run concurrently on **Mac 3**.

1. Navigate to the project root on Mac 3:
   ```bash
   cd CN_Project
   ```
2. Start **Backend A** in Terminal 1:
   ```bash
   python3 backend/server.py A 3001
   ```
3. Start **Backend B** in Terminal 2:
   ```bash
   python3 backend/server.py B 3002
   ```
4. Verify both backends respond locally on Mac 3:
   ```bash
   curl -i http://127.0.0.1:3001/api/status
   curl -i http://127.0.0.1:3002/api/status
   ```
   Confirm that each response includes its respective `X-Backend: A` and `X-Backend: B` headers.

---

## Step 4: Mac 2 → Nginx HTTP Setup

On **Mac 2**, set up the HTTP reverse proxy and load balancer:

1. Install `nginx` (e.g. `brew install nginx`).
2. Test network connectivity from Mac 2 to both backends on Mac 3:
   ```bash
   nc -zv 10.7.29.148 3001
   nc -zv 10.7.29.148 3002
   ```
3. Render or configure `config/nginx/team-http.conf.template` with Mac 3's IP.
4. Start nginx:
   ```bash
   sudo nginx -c $(pwd)/config/live/team-http.conf
   ```
5. Test HTTP ingress on port 8080:
   ```bash
   curl -i http://10.7.19.92:8080/
   ```

---

## Step 5: Mac 2 → TLS Setup

On **Mac 2**, configure TLS termination for port 8443:

1. Generate Root CA and server certificates with SAN (`DNS:app.team1.test`, `DNS:api.team1.test`) using `scripts/make-certs.sh`.
2. Configure `ssl_certificate` and `ssl_certificate_key` directives in the Nginx configuration.
3. Reload Nginx:
   ```bash
   sudo nginx -s reload
   ```
4. Trust the Root CA on Mac 1 and test clients:
   ```bash
   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/team-certs/team-CA.pem
   ```

---

## Step 6: Configure Mac 2 and Mac 3 to Use Mac 1 DNS

Point system DNS resolvers on Mac 2 and Mac 3 to Mac 1 (`10.7.21.145`):

```bash
# macOS CLI DNS configuration for Wi-Fi service
sudo networksetup -setdnsservers Wi-Fi 10.7.21.145 8.8.8.8
```

Verify that `app.team1.test` and `api.team1.test` resolve to Mac 2 (`10.7.19.92`):
```bash
dscacheutil -q host -a name app.team1.test
```

---

## Step 7: Wireshark Capture on Mac 3

On **Mac 3**, capture network packets to observe backend ingress:

1. Open Wireshark on Mac 3.
2. Select interface `en0`.
3. Set capture filter:
   ```text
   tcp port 3001 or tcp port 3002
   ```
4. Start the capture before sending test traffic.

---

## Step 8: Final Verification

Run the end-to-end verification suite from the client machine (or Mac 1):

1. **DNS Lookup:**
   ```bash
   dig @10.7.21.145 app.team1.test +short
   ```
2. **HTTP Redirection & Load Balancing:**
   ```bash
   curl -i http://app.team1.test:8080/
   # Expect 301 Redirect to https://app.team1.test:8443/

   for i in {1..4}; do /usr/bin/curl -s https://app.team1.test:8443/api/status; echo; done
   ```
   *Expect load distribution across `X-Backend: A` and `X-Backend: B`.*
3. **HTTPS Verification (using System Keychain):**
   ```bash
   /usr/bin/curl -i https://app.team1.test:8443/api/status
   ```
4. **Caching & 304 Revalidation:**
   ```bash
   ETAG=$(/usr/bin/curl -sI https://app.team1.test:8443/api/info | grep -i "^ETag:" | awk '{print $2}' | tr -d '\r')
   /usr/bin/curl -i -H "If-None-Match: $ETAG" https://app.team1.test:8443/api/info
   ```
   *Expect `HTTP/2 304 Not Modified` with empty body.*
5. **Automated Verification:**
   ```bash
   ./scripts/demo.sh all
   ```
6. **Stop Wireshark capture** on Mac 3 and save the session file into `evidence/G-packet-capture/`.

---

## Implementation & Testing Notes

- Pre-flight connectivity verification script implemented in `scripts/demo.sh` (`./scripts/demo.sh lan` or `./scripts/demo.sh check`).
- Network interface confirmed as `en0` on all three physical Macs.
- Firewall / SIP considerations: Verified that macOS Application Firewall allows inbound connections on ports 53 (`dnsmasq`), 8080/8443 (`nginx`), and 3001/3002 (`python3`).
