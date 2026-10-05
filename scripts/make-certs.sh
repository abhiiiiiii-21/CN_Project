#!/usr/bin/env bash
# ==============================================================================
# make-certs.sh
# ==============================================================================
# TODO: Implement local team CA generation and TLS server certificate issuance.
# - Generate Root CA private key and self-signed certificate.
# - Generate server private key and CSR for domain names:
#     - app.TEAM.test
#     - api.TEAM.test
# - Include Subject Alternative Names (SAN) in OpenSSL configuration.
# - Sign server certificate with Root CA.
# - Output certificates for Mac 2 (nginx) and Root CA for client trust stores.
# ==============================================================================
