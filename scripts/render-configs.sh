#!/usr/bin/env bash
# ==============================================================================
# render-configs.sh
# ==============================================================================
# Template rendering script using environment variables.
# - Source variables from config/cn-team.env (TEAM, MAC1_IP, MAC2_IP, MAC3_IP, COLLEGE_DNS).
# - Substitute placeholders in:
#     - config/dnsmasq.conf.template -> config/live/dnsmasq.conf
#     - config/nginx/team-http.conf.template -> config/live/team-http.conf
#     - config/nginx/team-https.conf.template -> config/live/team-https.conf
# - Validate generated files for completeness.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${1:-$PROJECT_ROOT/config/cn-team.env}"

if [ ! -f "$ENV_FILE" ]; then
    echo "Notice: Environment file not found at: $ENV_FILE"
    echo "To render configurations, copy config/cn-team.env.example to config/cn-team.env and configure your network IPs."
    exit 1
fi

echo "Sourcing environment variables from: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

# Required variables check
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

# 2. Mac 2: team-http.conf
sed \
    -e "s/TEAM/$TEAM/g" \
    -e "s/MAC3_IP/$MAC3_IP/g" \
    "$PROJECT_ROOT/config/nginx/team-http.conf.template" > "$PROJECT_ROOT/config/live/team-http.conf"
echo "  [OK] Rendered config/live/team-http.conf"

# 3. Mac 2: team-https.conf (rendered only if certificates are specified)
CERT_PATH="${CERTIFICATE_PATH:-}"
KEY_PATH="${PRIVATE_KEY_PATH:-}"

if [ -n "$CERT_PATH" ] && [ -n "$KEY_PATH" ]; then
    sed \
        -e "s/TEAM/$TEAM/g" \
        -e "s/MAC3_IP/$MAC3_IP/g" \
        -e "s|CERTIFICATE_PATH|$CERT_PATH|g" \
        -e "s|PRIVATE_KEY_PATH|$KEY_PATH|g" \
        "$PROJECT_ROOT/config/nginx/team-https.conf.template" > "$PROJECT_ROOT/config/live/team-https.conf"
    echo "  [OK] Rendered config/live/team-https.conf"
else
    echo "  [INFO] Skipping config/live/team-https.conf (CERTIFICATE_PATH and PRIVATE_KEY_PATH not set yet)."
fi

echo "Configuration rendering complete."
