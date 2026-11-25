#!/usr/bin/env bash
# ==============================================================================
# dns-ctl.sh: run the team dnsmasq as primary (Mac 1) or backup (Mac 4)
# ==============================================================================
# Usage:
#   ./scripts/dns-ctl.sh primary|backup start
#   ./scripts/dns-ctl.sh primary|backup stop
#   ./scripts/dns-ctl.sh primary|backup restart
#   ./scripts/dns-ctl.sh primary|backup status
#   ./scripts/dns-ctl.sh primary|backup point-app <ip>   # change app.TEAM.test, restart
#
# dnsmasq runs straight from config/live/ (not via brew services), with its pid
# and log in /tmp/cn-dnsmasq-<role>.{pid,log}. Needs sudo for port 53.
# ==============================================================================

set -euo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
load_env

usage() {
    echo "Usage: $0 primary|backup start|stop|restart|status|point-app <ip>" >&2
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
    [ -n "$pid" ] && ps -p "$pid" -o comm= 2>/dev/null | grep -q dnsmasq && echo "$pid"
}

do_status() {
    local pid
    if pid="$(running_pid)"; then
        echo "RUNNING (dnsmasq $ROLE, pid $pid, $WHO)"
        local ans
        ans="$(dig "$APP_DOMAIN" @"$SERVER_IP" +noall +answer +time=2 +tries=1 2>/dev/null || true)"
        if [ -n "$ans" ]; then echo "$ans"; else echo "(no answer from $SERVER_IP for $APP_DOMAIN)"; fi
        return 0
    fi
    echo "STOPPED (dnsmasq $ROLE)"
    return 1
}

do_stop() {
    local pid
    if pid="$(running_pid)"; then
        sudo kill "$pid"
        local i
        for i in 1 2 3 4 5 6 7 8 9 10; do
            ps -p "$pid" >/dev/null 2>&1 || break
            sleep 0.3
        done
    fi
    sudo rm -f "$PIDFILE"
}

do_start() {
    [ -n "$DNSMASQ" ] || die "dnsmasq is not installed (brew install dnsmasq)."
    [ -f "$CONF" ] || die "$CONF missing. Run ./scripts/render-configs.sh first."
    warn_if_not_me "$SERVER_IP" "$WHO"
    do_stop
    sudo "$DNSMASQ" --test --conf-file="$CONF" >/dev/null 2>&1 \
        || { sudo "$DNSMASQ" --test --conf-file="$CONF"; die "config check failed for $CONF"; }
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
    restart) do_start ;;
    stop)    do_stop; echo "STOPPED (dnsmasq $ROLE)" ;;
    status)  do_status ;;
    point-app)
        NEW_IP="${3:-}"
        is_ipv4 "$NEW_IP" || die "point-app needs an IPv4 address, got '${NEW_IP}'"
        [ -f "$CONF" ] || die "$CONF missing. Run ./scripts/render-configs.sh first."
        grep -q "^host-record=$APP_DOMAIN," "$CONF" || die "no host-record for $APP_DOMAIN in $CONF"
        sed -i '' -E "s|^host-record=$APP_DOMAIN,.*|host-record=$APP_DOMAIN,$NEW_IP|" "$CONF"
        echo "$APP_DOMAIN -> $NEW_IP"
        do_start
        ;;
    *) usage ;;
esac
