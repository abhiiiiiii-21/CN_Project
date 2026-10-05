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
      - CN: app.team1.test
      - SAN: DNS:app.team1.test, DNS:api.team1.test
      - Terminated at Mac 2 (Nginx :8443)
```

---

## Key Components

### 1. Local / Team Certificate Authority
A self-signed Root CA is generated using `scripts/make-certs.sh`. The Root CA certificate (`rootCA.crt`) is distributed to client devices so that certificates signed by it are recognized as fully trusted.

### 2. Server Certificate & Subject Alternative Names (SAN)
The server certificate is issued specifically for the team domain namespace and includes Subject Alternative Name (SAN) fields:
- `DNS.1 = app.team1.test`
- `DNS.2 = api.team1.test`

SAN entries are required by modern web browsers and CLI tools to validate the server identity without host mismatch warnings.

### 3. TLS Termination at Nginx (Mac 2)
Nginx on Mac 2 handles cryptographic negotiation (TLS 1.2 and TLS 1.3), cipher suite selection, and session resumption:
- Listens on `8443 ssl`
- Uses `ssl_protocols TLSv1.2 TLSv1.3;`
- Cipher suites: `HIGH:!aNULL:!MD5;`
- Proxies decrypted requests over plain HTTP to Mac 3 backends.

### 4. Certificate Trust on macOS
To establish trust for the Root CA on client devices running macOS:
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
- Inspect certificate details: issuer must show Team Root CA and SANs must match `app.team1.test`.

---

## TODO: Future Implementation & Documentation

- [ ] Implement certificate generation script in `scripts/make-certs.sh`.
- [ ] Document OpenSSL configuration profile (`openssl.cnf`) with v3 extensions.
- [ ] Capture verbose curl handshake logs into `evidence/E-tls/curl-handshake.txt`.
- [ ] Save screenshot of trusted browser padlock into `evidence/E-tls/browser-padlock.png`.
