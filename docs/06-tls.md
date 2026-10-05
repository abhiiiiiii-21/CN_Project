# Transport Layer Security (TLS) & PKI Architecture

## Overview

Secure communication between client browsers and the edge proxy is established using a private Public Key Infrastructure (PKI). **Mac 2** terminates TLS connections on port 8443 using a server certificate issued by a private team Certificate Authority (CA) with Subject Alternative Name (SAN) extensions.

> **Security Note:** Private keys (`*.key`) must **never** be committed to version control. They are generated locally and excluded via `.gitignore`. Only the public Root CA certificate is distributed to clients.

---

## Public Key Infrastructure (PKI) Structure

```text
[ Team Root CA ]
   │  (team-CA.key & team-CA.pem generated in ~/team-certs/)
   │  (team-CA.pem installed into Client Trust Stores / macOS Keychain)
   │
   └── Signs
         │
         ▼
   [ Server Certificate (Mac 2 Edge) ]
      - Subject: CN = app.team1.test
      - Issuer:  CN = team1 Local Root CA
      - SAN:     DNS:app.team1.test, DNS:api.team1.test
      - Terminated at Mac 2 (Nginx :8443)
```

---

## Key Components

### 1. Local / Team Certificate Authority
A self-signed Root CA is generated using [scripts/make-certs.sh](../scripts/make-certs.sh). The Root CA certificate (`team-CA.pem`) is distributed to client devices so that certificates signed by it are recognized as fully trusted.
- Root CA Key: `~/team-certs/team-CA.key` (permission `0600`)
- Root CA Public Certificate: `~/team-certs/team-CA.pem` (permission `0644`)
- Safety Guard: `scripts/make-certs.sh` automatically checks for existing Root CA keys and stops safely without overwriting.

### 2. Server Certificate & Subject Alternative Names (SAN)
The server certificate is issued specifically for the team domain namespace and includes Subject Alternative Name (SAN) fields:
- `DNS.1 = app.team1.test`
- `DNS.2 = api.team1.test`

SAN entries are required by modern web browsers and CLI tools (e.g., macOS cURL, Chrome, Safari) to validate server identity without host mismatch warnings.
- Server Key: `~/team-certs/app.key` -> copied to `$(brew --prefix)/etc/nginx/certs/app.key`
- Server Certificate: `~/team-certs/app.crt` -> copied to `$(brew --prefix)/etc/nginx/certs/app.crt`

### 3. TLS Termination at Nginx (Mac 2)
Nginx on Mac 2 handles cryptographic negotiation (TLS 1.2 and TLS 1.3), ALPN protocol negotiation (HTTP/2 and HTTP/1.1), cipher suite selection, and session resumption:
- Listens on `8443 ssl;` with `http2 on;`
- Uses `ssl_protocols TLSv1.2 TLSv1.3;`
- Cipher suites: `HIGH:!aNULL:!MD5;`
- Decrypts traffic and reverse proxies over plain HTTP to Mac 3 backends (`:3001` and `:3002`).

### 4. Client Certificate Trust on macOS
To establish trust for the Root CA on client devices running macOS:
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/team-certs/team-CA.pem
```

---

## Verification Procedures

### 1. Verbose Handshake Verification via `curl`
Testing HTTPS without the `-k` (insecure) flag:
```bash
/usr/bin/curl -v https://app.team1.test:8443/api/status
```
**Observed Output (from evidence):**
```text
* Host app.team1.test was resolved.
* IPv4: 10.7.19.92
* Connected to app.team1.test (10.7.19.92) port 8443
* ALPN: curl offers h2,http/1.1
* SSL connection using TLSv1.3 / AEAD-CHACHA20-POLY1305-SHA256
* ALPN: server accepted h2
* Server certificate:
*  subject: CN=app.team1.test
*  subjectAltName: host "app.team1.test" matched cert's "app.team1.test"
*  issuer: CN=team1 Local Root CA
*  SSL certificate verify ok.
* using HTTP/2
< HTTP/2 200
< server: nginx/1.31.6
< content-type: application/json
< x-backend: A
< cache-control: no-store
< x-upstream-addr: 10.7.29.148:3001
{"backend": "A", "status": "ok", "time": "2026-10-05T15:02:54.067897+00:00"}
```

### 2. Browser Padlock Verification
- Navigate to `https://app.team1.test:8443/api/status` in Google Chrome or Safari.
- Verified: The browser displays the secure padlock icon without warnings.
- The certificate viewer confirms:
  - Status: "Connection is secure" / "Certificate is valid"
  - Common Name: `app.team1.test`
  - SANs: `app.team1.test`, `api.team1.test`
  - Issuer: `team1 Local Root CA`

---

## Evidence Artifacts

The TLS setup is verified and supported by photographic evidence:
- [curl-tls.jpeg](../evidence/E-tls/curl-tls.jpeg): Shows verbose curl handshake verifying TLSv1.3 negotiation, trusted issuer `CN=team1 Local Root CA`, SAN match, HTTP/2 ALPN acceptance, and `HTTP/2 200` response.
- [browser-padlock.jpeg](../evidence/E-tls/browser-padlock.jpeg): Screenshot of Google Chrome verifying green padlock, trusted certificate status, and valid payload delivery on port 8443.

---

## Operational Guidelines

1. **Certificate Generation:** Implemented in `scripts/make-certs.sh`.
2. **Automated Verification:** Implemented in `scripts/demo.sh tls`.
3. **Private Key Protection:** Private keys remain strictly on Mac 2 with `0600` permissions.
