#!/usr/bin/env bash
# ==============================================================================
# render-configs.sh
# ==============================================================================
# Template rendering script using environment variables.
# - Source variables from cn-team.env (TEAM, MAC1_IP, MAC2_IP, MAC3_IP, COLLEGE_DNS).
# - Substitute placeholders in:
#     - config/dnsmasq.conf.template -> config/live/dnsmasq.conf
#     - config/nginx/team-http.conf.template -> config/live/team-http.conf
#     - config/nginx/team-https.conf.template -> config/live/team-https.conf
# - Validate generated files for completeness.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -n "${CN_ENV:-}" ]; then
    ENV_FILE="$CN_ENV"
elif [ -n "${1:-}" ]; then
    ENV_FILE="$1"
elif [ -f "$HOME/cn-team.env" ]; then
    ENV_FILE="$HOME/cn-team.env"
else
    ENV_FILE="$PROJECT_ROOT/config/cn-team.env"
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "Notice: Environment file not found at: $ENV_FILE"
    echo "To render configurations, ensure ~/cn-team.env exists or copy config/cn-team.env.example to config/cn-team.env."
    exit 1
fi

echo "Sourcing environment variables from: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

# Required variables check (Strictly 3 Macs)
for var in TEAM MAC1_IP MAC2_IP MAC3_IP COLLEGE_DNS; do
    if [ -z "${!var:-}" ]; then
        echo "Error: Required variable '$var' is not set in $ENV_FILE"
        exit 1
    fi
done

mkdir -p "$PROJECT_ROOT/config/live"

echo "Rendering configuration templates for Team '$TEAM'..."

# 1. Mac 1: dnsmasq.conf
sed \
    -e "s/TEAM/$TEAM/g" \
    -e "s/MAC1_IP/$MAC1_IP/g" \
    -e "s/MAC2_IP/$MAC2_IP/g" \
    -e "s/COLLEGE_DNS/$COLLEGE_DNS/g" \
    "$PROJECT_ROOT/config/dnsmasq.conf.template" > "$PROJECT_ROOT/config/live/dnsmasq.conf"
echo "  [OK] Rendered config/live/dnsmasq.conf"

# 2. Mac 2: team-http.conf (Port 8080 redirect to HTTPS 8443)
sed \
    -e "s/TEAM/$TEAM/g" \
    "$PROJECT_ROOT/config/nginx/team-http.conf.template" > "$PROJECT_ROOT/config/live/team-http.conf"
echo "  [OK] Rendered config/live/team-http.conf"

# 3. Mac 2: team-https.conf (Port 8443 TLS load balancer)
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo '/opt/homebrew')"
DEFAULT_CERT="$BREW_PREFIX/etc/nginx/certs/app.crt"
DEFAULT_KEY="$BREW_PREFIX/etc/nginx/certs/app.key"

CERT_PATH="${CERTIFICATE_PATH:-$DEFAULT_CERT}"
KEY_PATH="${PRIVATE_KEY_PATH:-$DEFAULT_KEY}"

sed \
    -e "s/TEAM/$TEAM/g" \
    -e "s/MAC3_IP/$MAC3_IP/g" \
    -e "s|CERTIFICATE_PATH|$CERT_PATH|g" \
    -e "s|PRIVATE_KEY_PATH|$KEY_PATH|g" \
    "$PROJECT_ROOT/config/nginx/team-https.conf.template" > "$PROJECT_ROOT/config/live/team-https.conf"
echo "  [OK] Rendered config/live/team-https.conf"

echo "Configuration rendering complete."
