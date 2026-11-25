#!/usr/bin/env bash
# ==============================================================================
# render-configs.sh
# ==============================================================================
# Renders config/*.template into config/live/ using ~/cn-team.env
# (or CN_ENV=/path, or the first argument).
#
# Outputs (6):
#   config/live/dnsmasq.conf             Mac 1 primary DNS
#   config/live/dnsmasq-backup.conf      Mac 4 backup DNS
#   config/live/team-http.conf           edge :8080 -> :8443 redirect
#   config/live/team-https.conf          Mac 2 primary edge   (X-Edge: mac2-primary)
#   config/live/team-https-standby.conf  Mac 3 standby edge   (X-Edge: mac3-standby)
#   config/live/pf-backends.conf         Mac 3 + Mac 4 backend firewall (Ext C)
#
# config/live/ is machine-specific and is not committed (see .gitignore).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TPL="$PROJECT_ROOT/config"
LIVE="$PROJECT_ROOT/config/live"

if [ -n "${CN_ENV:-}" ]; then
    ENV_FILE="$CN_ENV"
elif [ -n "${1:-}" ]; then
    ENV_FILE="$1"
else
    ENV_FILE="$HOME/cn-team.env"
fi

[ -f "$ENV_FILE" ] || { echo "Error: environment file not found: $ENV_FILE (do steps 2-3 of the command sheet)"; exit 1; }

echo "Sourcing environment variables from: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

for var in TEAM MAC1_IP MAC2_IP MAC3_IP MAC4_IP COLLEGE_DNS; do
    if [ -z "${!var:-}" ]; then
        echo "Error: required variable '$var' is not set in $ENV_FILE"
        exit 1
    fi
done

BREW_PREFIX="$(brew --prefix 2>/dev/null || echo '/opt/homebrew')"
CERT_PATH="${CERTIFICATE_PATH:-$BREW_PREFIX/etc/nginx/certs/app.crt}"
KEY_PATH="${PRIVATE_KEY_PATH:-$BREW_PREFIX/etc/nginx/certs/app.key}"

mkdir -p "$LIVE"
echo "Rendering configuration templates for team '$TEAM'..."

# render <template> <output> [extra sed args...]
render() {
    local src="$1" out="$2"
    shift 2
    sed \
        -e "s/LISTEN_IP/${LISTEN_IP:-}/g" \
        -e "s/EDGE_NAME/${EDGE_NAME:-}/g" \
        -e "s/MAC1_IP/$MAC1_IP/g" \
        -e "s/MAC2_IP/$MAC2_IP/g" \
        -e "s/MAC3_IP/$MAC3_IP/g" \
        -e "s/MAC4_IP/$MAC4_IP/g" \
        -e "s/COLLEGE_DNS/$COLLEGE_DNS/g" \
        -e "s|CERTIFICATE_PATH|$CERT_PATH|g" \
        -e "s|PRIVATE_KEY_PATH|$KEY_PATH|g" \
        -e "s/TEAM/$TEAM/g" \
        "$src" > "$out"
    if grep -nE 'LISTEN_IP|EDGE_NAME|MAC[0-9]_IP|COLLEGE_DNS|CERTIFICATE_PATH|PRIVATE_KEY_PATH' "$out" | grep -v '^[0-9]*:#' >/dev/null; then
        echo "  [FAIL] Unreplaced placeholder left in ${out#"$PROJECT_ROOT"/}"
        exit 1
    fi
    echo "  [OK] Rendered ${out#"$PROJECT_ROOT"/}"
}

LISTEN_IP="$MAC1_IP" render "$TPL/dnsmasq.conf.template"              "$LIVE/dnsmasq.conf"
LISTEN_IP="$MAC4_IP" render "$TPL/dnsmasq.conf.template"              "$LIVE/dnsmasq-backup.conf"
render                      "$TPL/nginx/team-http.conf.template"      "$LIVE/team-http.conf"
EDGE_NAME=mac2-primary render "$TPL/nginx/team-https.conf.template"   "$LIVE/team-https.conf"
EDGE_NAME=mac3-standby render "$TPL/nginx/team-https.conf.template"   "$LIVE/team-https-standby.conf"
render                      "$TPL/pf-backends.conf.template"          "$LIVE/pf-backends.conf"

echo "Configuration rendering complete."
