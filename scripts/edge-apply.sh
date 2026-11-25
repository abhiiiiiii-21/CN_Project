#!/usr/bin/env bash
# ==============================================================================
# edge-apply.sh: install the edge nginx config and start/reload nginx
# ==============================================================================
# Usage:
#   ./scripts/edge-apply.sh primary   # Mac 2: team-https.conf          (X-Edge: mac2-primary)
#   ./scripts/edge-apply.sh standby   # Mac 3: team-https-standby.conf  (X-Edge: mac3-standby)
#   ./scripts/edge-apply.sh stop      # stop nginx on this Mac
#   ./scripts/edge-apply.sh status
#
# Copies config/live/ files into $(brew --prefix)/etc/nginx/servers/ as
# team-http.conf and team-https.conf, runs `nginx -t`, then reloads or starts.
# Re-run it after editing config/live/team-https*.conf.
# ==============================================================================

set -euo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
load_env

NGINX_DIR="$(brew_prefix)/etc/nginx"
SERVERS_DIR="$NGINX_DIR/servers"
NGINX="$(command -v nginx || true)"
[ -n "$NGINX" ] || die "nginx is not installed (brew install nginx)."

nginx_running() { pgrep -x nginx >/dev/null 2>&1; }

# nginx may have been started with sudo in Phase 1; fall back to sudo for signals.
nginx_signal() { "$NGINX" -s "$1" 2>/dev/null || sudo "$NGINX" -s "$1"; }

apply() {
    local src="$1" me="$2" label="$3" edge="$4"
    [ -f "$LIVE_DIR/$src" ] || die "config/live/$src missing. Run ./scripts/render-configs.sh first."
    [ -f "$LIVE_DIR/team-http.conf" ] || die "config/live/team-http.conf missing. Run ./scripts/render-configs.sh first."
    [ -f "$NGINX_DIR/certs/app.crt" ] && [ -f "$NGINX_DIR/certs/app.key" ] \
        || die "TLS cert/key missing in $NGINX_DIR/certs (see step 0.2 / 55)."
    grep -qE '^[[:space:]]*include[[:space:]]+servers/\*' "$NGINX_DIR/nginx.conf" 2>/dev/null \
        || warn "$NGINX_DIR/nginx.conf has no 'include servers/*;' line, so these files will be ignored."
    warn_if_not_me "$me" "$label"

    mkdir -p "$SERVERS_DIR"
    rm -f "$SERVERS_DIR"/team-*.conf
    cp "$LIVE_DIR/team-http.conf" "$SERVERS_DIR/team-http.conf"
    cp "$LIVE_DIR/$src"           "$SERVERS_DIR/team-https.conf"
    echo "Installed config/live/$src -> $SERVERS_DIR/team-https.conf ($edge)"

    if ! "$NGINX" -t 2>&1; then
        die "nginx -t failed; nothing was reloaded."
    fi

    if nginx_running; then
        nginx_signal reload
        echo "nginx reloaded"
    else
        "$NGINX"
        echo "nginx started"
    fi
}

case "${1:-}" in
    primary) apply team-https.conf         "$MAC2_IP" "Mac 2, primary edge" mac2-primary ;;
    standby) apply team-https-standby.conf "$MAC3_IP" "Mac 3, standby edge" mac3-standby ;;
    stop)
        if nginx_running; then
            nginx_signal stop
            echo "nginx stopped"
        else
            echo "nginx was not running"
        fi
        ;;
    status)
        if nginx_running; then echo "nginx RUNNING"; else echo "nginx STOPPED"; fi
        grep -h "add_header X-Edge" "$SERVERS_DIR"/team-https.conf 2>/dev/null | sed 's/^[[:space:]]*/installed: /' || true
        ;;
    *) echo "Usage: $0 primary|standby|stop|status" >&2; exit 1 ;;
esac
