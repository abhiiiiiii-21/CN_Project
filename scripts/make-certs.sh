#!/usr/bin/env bash
# ==============================================================================
# make-certs.sh
# ==============================================================================
# Generates a private Team Root CA and issues TLS server certificates with SAN
# for app.TEAM.test and api.TEAM.test on Mac 2 (Nginx Edge / TLS termination).
#
# Usage:
#   ./scripts/make-certs.sh
#   CN_ENV=/custom/path/cn-team.env ./scripts/make-certs.sh
# ==============================================================================

set -euo pipefail

ENV_FILE="${CN_ENV:-$HOME/cn-team.env}"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Shared environment file not found at: $ENV_FILE"
    echo "Please ensure ~/cn-team.env exists or specify CN_ENV=/path/to/env"
    exit 1
fi

echo "Sourcing environment variables from: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

# Validate required variables
for var in TEAM MAC1_IP MAC2_IP MAC3_IP COLLEGE_DNS; do
    if [ -z "${!var:-}" ]; then
        echo "Error: Required variable '$var' is not set in $ENV_FILE"
        exit 1
    fi
done

CERTS_DIR="$HOME/team-certs"
CA_KEY="$CERTS_DIR/team-CA.key"
CA_CERT="$CERTS_DIR/team-CA.pem"
SERVER_KEY="$CERTS_DIR/app.key"
SERVER_CSR="$CERTS_DIR/app.csr"
SERVER_CERT="$CERTS_DIR/app.crt"
OPENSSL_CNF="$CERTS_DIR/openssl-san.cnf"

mkdir -p "$CERTS_DIR"

# ------------------------------------------------------------------------------
# 1. Team Root CA Generation (Safe Guard)
# ------------------------------------------------------------------------------
if [ -f "$CA_KEY" ]; then
    echo "Notice: Existing Team Root CA detected at $CA_KEY."
    echo "Stopping safely to avoid overwriting existing Root CA."
    echo "If you intentionally wish to regenerate all certificates, backup and remove $CERTS_DIR first."
    exit 0
fi

echo "===> Generating new Team Root CA for Team '$TEAM'..."
openssl genrsa -out "$CA_KEY" 2048
chmod 600 "$CA_KEY"

openssl req -x509 -new -nodes \
    -key "$CA_KEY" \
    -sha256 \
    -days 3650 \
    -out "$CA_CERT" \
    -subj "/CN=${TEAM} Local Root CA"
chmod 644 "$CA_CERT"

echo "  [OK] Generated Root CA Key:  $CA_KEY"
echo "  [OK] Generated Root CA Cert: $CA_CERT"

# ------------------------------------------------------------------------------
# 2. Server Key and CSR with Subject Alternative Names (SAN)
# ------------------------------------------------------------------------------
echo "===> Generating server private key and certificate with SAN..."
openssl genrsa -out "$SERVER_KEY" 2048
chmod 600 "$SERVER_KEY"

# Build OpenSSL configuration file for SAN extensions
cat > "$OPENSSL_CNF" <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = req_distinguished_name
req_extensions     = v3_req

[ req_distinguished_name ]
CN = app.${TEAM}.test

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage         = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName   = @alt_names

[ alt_names ]
DNS.1 = app.${TEAM}.test
DNS.2 = api.${TEAM}.test
EOF

openssl req -new \
    -key "$SERVER_KEY" \
    -out "$SERVER_CSR" \
    -config "$OPENSSL_CNF"

# ------------------------------------------------------------------------------
# 3. Sign Server Certificate with Team Root CA
# ------------------------------------------------------------------------------
openssl x509 -req \
    -in "$SERVER_CSR" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$SERVER_CERT" \
    -days 365 \
    -sha256 \
    -extfile "$OPENSSL_CNF" \
    -extensions v3_req
chmod 644 "$SERVER_CERT"

# Clean up temporary CSR and config
rm -f "$SERVER_CSR" "$OPENSSL_CNF" "$CERTS_DIR/team-CA.srl"

echo "  [OK] Generated Server Key:  $SERVER_KEY"
echo "  [OK] Generated Server Cert: $SERVER_CERT"

# ------------------------------------------------------------------------------
# 4. Verify Server Certificate
# ------------------------------------------------------------------------------
echo "===> Verifying server certificate against Root CA..."
openssl verify -CAfile "$CA_CERT" "$SERVER_CERT"

# ------------------------------------------------------------------------------
# 5. Deploy to Nginx Certificates Directory
# ------------------------------------------------------------------------------
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo '/opt/homebrew')"
NGINX_CERTS_DIR="$BREW_PREFIX/etc/nginx/certs"

echo "===> Copying server certificate and key to Nginx directory: $NGINX_CERTS_DIR..."
mkdir -p "$NGINX_CERTS_DIR"
cp "$SERVER_CERT" "$NGINX_CERTS_DIR/app.crt"
cp "$SERVER_KEY" "$NGINX_CERTS_DIR/app.key"
chmod 600 "$NGINX_CERTS_DIR/app.key"
chmod 644 "$NGINX_CERTS_DIR/app.crt"

echo "  [OK] Copied $NGINX_CERTS_DIR/app.crt"
echo "  [OK] Copied $NGINX_CERTS_DIR/app.key"

# ------------------------------------------------------------------------------
# 6. Client Distribution & Security Instructions
# ------------------------------------------------------------------------------
echo ""
echo "========================================================================"
echo " CERTIFICATE GENERATION COMPLETE"
echo "========================================================================"
echo "IMPORTANT SECURITY NOTICE:"
echo "Distribute ONLY the Root CA public certificate to client machines:"
echo "  $CA_CERT"
echo ""
echo "NEVER copy, commit, or distribute private keys:"
echo "  DO NOT DISTRIBUTE: $CA_KEY"
echo "  DO NOT DISTRIBUTE: $SERVER_KEY"
echo "  DO NOT DISTRIBUTE: $NGINX_CERTS_DIR/app.key"
echo ""
echo "To trust this Root CA on macOS client devices (Mac 1, Mac 3, test client):"
echo "  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CA_CERT"
echo "========================================================================"
