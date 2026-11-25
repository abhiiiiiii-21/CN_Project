#!/usr/bin/env bash
# ==============================================================================
# dns-ctl.sh — run the team dnsmasq as primary (Mac 1) or backup (Mac 4)
# ==============================================================================
# Usage:
#   ./scripts/dns-ctl.sh primary|backup start|stop|restart|status|logs
#   ./scripts/dns-ctl.sh primary|backup point-app <ip>
#
# point-app rewrites the app.<team>.test record. Run it on both DNS servers
# during a cutover so the resolvers continue to agree.
# ==============================================================================
set -euo pipefail

# shellcheck source=scripts/_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
load_env

usage() {
    echo "Usage: $0 primary|backup start|stop|restart|status|logs|point-app <ip>" >&2
    exit 1
}

ROLE="${1:-}"
ACTION="${2:-}"
case "$ROLE" in
    primary) CONF="$LIVE_DIR/dnsmasq.conf";        SERVER_IP="$MAC1_IP"; WHO="Mac 1, primary DNS" ;;
    backup)  CONF="$LIVE_DIR/dnsmasq-backup.conf"; SERVER_IP="$MAC4_IP"; WHO="Mac 4, backup DNS" ;;
    *) usage ;;
esac

PIDFILE="/tmp/cn-dnsmasq-$ROLE.pid"
LOGFILE="/tmp/cn-dnsmasq-$ROLE.log"

DNSMASQ="$(brew_prefix)/sbin/dnsmasq"
[ -x "$DNSMASQ" ] || DNSMASQ="$(command -v dnsmasq || true)"

running_pid() {
    [ -f "$PIDFILE" ] || return 1
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    if ps -p "$pid" -o comm= 2>/dev/null | grep -q dnsmasq; then
        echo "$pid"
    else
        return 1
    fi
}

do_status() {
    local pid ans port
    if pid="$(running_pid)"; then
        echo "RUNNING (dnsmasq $ROLE, pid $pid, $WHO)"
        ans="$(dig "$APP_DOMAIN" @"$SERVER_IP" +noall +answer +time=2 +tries=1 2>/dev/null || true)"
        if [ -n "$ans" ]; then echo "$ans"; else echo "(no answer from $SERVER_IP for $APP_DOMAIN)"; fi
        echo "Records in config:"
        grep -E '^(host-record|local-ttl)' "$CONF" | sed 's/^/  /'
        port="$(awk -F= '/^port=/ {print $2}' "$CONF")"
        port="${port:-53}"
        ans="$(dig @127.0.0.1 -p "$port" "$APP_DOMAIN" +noall +answer +time=2 +tries=1 2>/dev/null || true)"
        echo "Local answer (dig @127.0.0.1 -p $port $APP_DOMAIN):"
        echo "  ${ans:-NO ANSWER}"
        return 0
    fi
    echo "STOPPED (dnsmasq $ROLE)"
    return 1
}

do_stop() {
    local pid attempts
    if pid="$(running_pid)"; then
        sudo kill "$pid"
        attempts=0
        while [ "$attempts" -lt 10 ]; do
            ps -p "$pid" >/dev/null 2>&1 || break
            sleep 0.3
            attempts=$((attempts + 1))
        done
    fi
    sudo rm -f "$PIDFILE"
}

do_start() {
    [ -n "$DNSMASQ" ] || die "dnsmasq is not installed (brew install dnsmasq)."
    [ -f "$CONF" ] || die "$CONF missing. Run ./scripts/render-configs.sh first."
    warn_if_not_me "$SERVER_IP" "$WHO"
    if running_pid >/dev/null; then
        echo "dnsmasq ($ROLE) already running."
        do_status
        return
    fi
    do_stop
    sudo "$DNSMASQ" --test --conf-file="$CONF"
    if ! sudo "$DNSMASQ" --conf-file="$CONF" --pid-file="$PIDFILE" --log-facility="$LOGFILE"; then
        echo "dnsmasq did not start. If port 53 is busy, stop the other copy:" >&2
        echo "  sudo brew services stop dnsmasq; sudo pkill -x dnsmasq" >&2
        exit 1
    fi
    sleep 1
    do_status
}

case "$ACTION" in
    start)   do_start ;;
    restart) do_stop; do_start ;;
    stop)    do_stop; echo "STOPPED (dnsmasq $ROLE)" ;;
    status)  do_status ;;
    logs)    echo "Ctrl-C to stop watching."; sudo tail -f "$LOGFILE" ;;
    point-app)
        NEW_IP="${3:-}"
        is_ipv4 "$NEW_IP" || die "point-app needs an IPv4 address, got '${NEW_IP}'"
        [ -f "$CONF" ] || die "$CONF missing. Run ./scripts/render-configs.sh first."
        grep -Fq "host-record=$APP_DOMAIN," "$CONF" || die "no host-record for $APP_DOMAIN in $CONF"
        ESCAPED_DOMAIN="$(printf '%s' "$APP_DOMAIN" | sed 's/\./\\./g')"
        sed -i '' -E "s|^host-record=$ESCAPED_DOMAIN,.*|host-record=$APP_DOMAIN,$NEW_IP|" "$CONF"
        echo "$APP_DOMAIN -> $NEW_IP"
        # dnsmasq reads host-record only at startup, so a running server must be restarted.
        do_stop
        do_start
        ;;
    *) usage ;;
esac
