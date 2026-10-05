# Environment Setup and Startup Flow

## Overview

This document specifies the end-to-end setup and orchestrated initialization procedure for the three-Mac private network. Following this strict startup sequence ensures service dependencies are satisfied without race conditions or false connection errors.

---

## 1. Network Requirements and IP Discovery

### Local Area Network (LAN) Requirements
- All three Macs must be connected to the **same Wi-Fi network or Ethernet subnet** with client-to-client isolation disabled (AP isolation must be off).
- ICMP echo requests (`ping`) must be permitted between all three hosts.

### IP Discovery Procedure
On each Mac, identify the active IPv4 interface address:
```bash
# macOS Wi-Fi interface address discovery
ipconfig getifaddr en0
```
Verify connectivity across nodes:
```bash
# From Mac 1 or Mac 2:
ping -c 3 MAC3_IP
```

---

## 2. Environment Configuration (`cn-team.env`)

Create the active environment file on each machine from the template:
```bash
cp config/cn-team.env.example config/cn-team.env
```
Edit `config/cn-team.env` with the discovered IPs:
```bash
export TEAM=team1
export MAC1_IP=10.7.21.145
export MAC2_IP=10.7.19.92
export MAC3_IP=10.7.29.148
export COLLEGE_DNS=8.8.8.8
```
*(Note: There is NO `MAC4_IP`. All configurations must strictly adhere to the 3-Mac architecture.)*

Run the rendering script to generate active configuration files:
```bash
./scripts/render-configs.sh
```

---

## 3. Service Startup Order

Services must be launched in reverse-dependency order:

```text
Step 1: Mac 3 (Backends A & B)
   │
   ▼
Step 2: Mac 2 (Nginx Edge Load Balancer)
   │
   ▼
Step 3: Mac 1 (dnsmasq Private DNS)
   │
   ▼
Step 4: Clients (DNS Resolver Configuration & Validation)
```

### Step 1: Start Backends on Mac 3
Launch both backend processes on Mac 3 and start Wireshark packet capture:
```bash
# Mac 3 - Terminal 1: Backend A
python3 backend/server.py A 3001

# Mac 3 - Terminal 2: Backend B
python3 backend/server.py B 3002

# Mac 3 - Terminal 3: Wireshark
# Capture interface: en0 (filtered by port 3001 or 3002)
```

### Step 2: Start Nginx Edge on Mac 2
Ensure Mac 3 ports 3001 and 3002 are reachable from Mac 2 before starting `nginx`:
```bash
# Verify upstream connectivity
nc -zv MAC3_IP 3001
nc -zv MAC3_IP 3002

# Start or reload nginx with rendered configuration
sudo nginx -c $(pwd)/config/live/team-https.conf
```

### Step 3: Start Private DNS on Mac 1
Launch `dnsmasq` bound to Mac 1's LAN IP:
```bash
sudo dnsmasq -C $(pwd)/config/live/dnsmasq.conf -d
```

### Step 4: Configure Client DNS & Validate
On the client Mac (or Mac 1):
```bash
# Test direct DNS lookup
dig @MAC1_IP app.team1.test

# Test HTTP and HTTPS endpoints through edge proxy
curl -i http://app.team1.test:8080/
curl -i --cacert certs/rootCA.crt https://app.team1.test:8443/
```

---

## TODO: Future Implementation & Documentation

- [ ] Write pre-flight connectivity verification script into `scripts/`.
- [ ] Add systemd/launchd service configuration notes for background operation if required.
- [ ] Document firewall/SIP considerations on macOS (`pfctl`, macOS Application Firewall).
- [ ] Record exact interface names (`en0` vs `en1`) for each Mac in the lab environment.
