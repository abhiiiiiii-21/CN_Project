# Transport Layer Security (TLS) & PKI Architecture

## Overview

Secure communication between client browsers and the edge proxy is established using a private Public Key Infrastructure (PKI). **Mac 2** terminates TLS connections on port 8443 using a server certificate issued by a private team Certificate Authority (CA) with Subject Alternative Name (SAN) extensions.

> **Security Note:** Private keys (`*.key`) must **never** be committed to version control. They are generated locally and excluded via `.gitignore`.

---

## Public Key Infrastructure (PKI) Structure

```text
[ Team Root CA ]
   │  (Generates rootCA.key & rootCA.crt)
   │  (Installed into Client Trust Stores / macOS Keychain)
   │
   └── Signs
         │
         ▼
   [ Server Certificate (Mac 2) ]
      - CN: app.TEAM.test
      - SAN: DNS:app.TEAM.test, DNS:api.TEAM.test
      - Terminated at Mac 2 (Nginx :8443)
```

---

## Key Components

### 1. Local / Team Certificate Authority
A self-signed Root CA is generated using `scripts/make-certs.sh`. The Root CA certificate (`rootCA.crt`) is distributed to client devices so that certificates signed by it are recognized as fully trusted.

### 2. Server Certificate & SAN
The server certificate is issued specifically for the team domain namespace and includes Subject Alternative Name (SAN) fields:
- `DNS.1 = app.TEAM.test`
- `DNS.2 = api.TEAM.test`

SAN entries prevent modern browsers and CLI tools from rejecting the certificate due to host mismatch errors.

### 3. TLS Termination at Edge Proxy
Nginx on Mac 2 handles cryptographic negotiation (TLS 1.2 and TLS 1.3), cipher suite selection, and session resumption. Communication between Mac 2 and the upstream backends on Mac 3 remains within the private network over HTTP.

### 4. Client Certificate Trust on macOS
To trust the Root CA on client machines:
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain certs/rootCA.crt
```

---

## Verification Procedures

### 1. Verbose Handshake Verification via `curl`
```bash
curl -v --cacert certs/rootCA.crt https://app.team1.test:8443/
```
**Verification Points:**
- `Server certificate:` matches `app.team1.test`
- `SSL certificate verify ok`
- Handshake protocol: `TLSv1.2` or `TLSv1.3`
- Cipher suite: modern AEAD cipher (e.g., `TLS_AES_256_GCM_SHA384` or `ECDHE-RSA-AES128-GCM-SHA256`)

### 2. Browser Padlock Verification
- Open `https://app.team1.test:8443/` in Safari or Chrome.
- Verify the secure padlock icon is displayed without security warnings or interstitial screens.
- Inspect certificate details: issuer must show Team Root CA and SANs must be valid.

---

## TODO: Future Implementation & Documentation

- [ ] Implement certificate generation script in `scripts/make-certs.sh`.
- [ ] Document OpenSSL configuration profile (`openssl.cnf`) with v3 extensions.
- [ ] Capture verbose curl handshake logs into `evidence/E-tls/curl-handshake.txt`.
- [ ] Save screenshot of trusted browser padlock into `evidence/E-tls/browser-padlock.png`.
