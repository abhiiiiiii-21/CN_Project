#!/usr/bin/env bash
# ==============================================================================
# dns-ctl.sh — run the team dnsmasq (Phase 2)
# ==============================================================================
# Usage:
#   ./scripts/dns-ctl.sh primary start|stop|restart|status|logs     (Mac 1)
#   ./scripts/dns-ctl.sh backup  start|stop|restart|status|logs     (Mac 4, Ext A)
#   ./scripts/dns-ctl.sh primary point-app <IP>                     (Ext B / Ext E)
#
# point-app rewrites the app.<team>.test record in the local config and
# restarts dnsmasq. Run it on BOTH Mac 1 and Mac 4 so the resolvers agree.
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib-env.sh
source "$ROOT/scripts/lib-env.sh"
cn_load_env "$ROOT"

ROLE="${1:-}"; CMD="${2:-}"
case "$ROLE" in
    primary) CONF="$ROOT/config/live/dnsmasq.conf" ;;
    backup)  CONF="$ROOT/config/live/dnsmasq-backup.conf" ;;
    *) echo "Usage: $0 <primary|backup> <start|stop|restart|status|logs|point-app IP>"; exit 1 ;;
esac
PIDFILE="/tmp/cn-dnsmasq-$ROLE.pid"
LOGFILE="/tmp/cn-dnsmasq-$ROLE.log"
DNSMASQ="$(command -v dnsmasq || echo "$(brew --prefix 2>/dev/null || echo /opt/homebrew)/sbin/dnsmasq")"

[ -f "$CONF" ] || { echo "Error: $CONF missing. Run ./scripts/render-configs.sh first."; exit 1; }
[ -x "$DNSMASQ" ] || { echo "Error: dnsmasq not found. Run: brew install dnsmasq"; exit 1; }

is_running() { [ -f "$PIDFILE" ] && sudo kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

do_start() {
    if is_running; then echo "dnsmasq ($ROLE) already running, pid $(cat "$PIDFILE")"; return; fi
    sudo "$DNSMASQ" --test -C "$CONF"
    sudo "$DNSMASQ" -C "$CONF" --pid-file="$PIDFILE" --log-facility="$LOGFILE"
    sleep 1
    do_status
}

do_stop() {
    if is_running; then
        sudo kill "$(cat "$PIDFILE")"
        sudo rm -f "$PIDFILE"
        echo "dnsmasq ($ROLE) stopped."
    else
        sudo pkill -f "dnsmasq -C $CONF" 2>/dev/null && echo "dnsmasq ($ROLE) stopped." || echo "dnsmasq ($ROLE) was not running."
    fi
}

do_status() {
    if is_running; then echo "dnsmasq ($ROLE): RUNNING, pid $(cat "$PIDFILE"), config $CONF"
    else echo "dnsmasq ($ROLE): STOPPED"; fi
    echo "Records in config:"; grep -E '^(host-record|local-ttl)' "$CONF" | sed 's/^/  /'
    local port ans
    port="$(awk -F= '/^port=/ {print $2}' "$CONF")"; port="${port:-53}"
    ans="$(dig @127.0.0.1 -p "$port" "app.$TEAM.test" +noall +answer +time=2 +tries=1 2>/dev/null | grep -v '^;' || true)"
    echo "Local answer (dig @127.0.0.1 -p $port app.$TEAM.test):"
    echo "  ${ans:-NO ANSWER}"
}

case "$CMD" in
    start)   do_start ;;
    stop)    do_stop ;;
    restart) do_stop; do_start ;;
    status)  do_status ;;
    logs)    echo "Ctrl-C to stop watching."; sudo tail -f "$LOGFILE" ;;
    point-app)
        IP="${3:-}"
        [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: $0 $ROLE point-app <IPv4>"; exit 1; }
        sed -i '' -E "s/^host-record=app\.([^,]+),.*/host-record=app.\1,$IP/" "$CONF"
        echo "app.$TEAM.test -> $IP in $CONF"
        do_stop; do_start ;;
    *) echo "Usage: $0 <primary|backup> <start|stop|restart|status|logs|point-app IP>"; exit 1 ;;
esac
