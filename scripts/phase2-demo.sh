#!/usr/bin/env bash
# ==============================================================================
# phase2-demo.sh: client-side demo helpers for Phase 2
# ==============================================================================
# Usage:
#   ./scripts/phase2-demo.sh flush        # flush the macOS DNS cache (sudo)
#   ./scripts/phase2-demo.sh lb [N]       # N requests (default 6): code, X-Backend, X-Edge
#   ./scripts/phase2-demo.sh watch        # every 2 s: system-resolver IP + X-Edge (Ctrl-C)
#   ./scripts/phase2-demo.sh isolation    # can THIS Mac reach the backends? (Ext C)
#   ./scripts/phase2-demo.sh dns          # ask primary and backup DNS directly + system resolver
#
# Uses /usr/bin/curl (trusts the System keychain) and the system resolver,
# so results include the client's DNS cache. dig always bypasses that cache.
# ==============================================================================

set -uo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
load_env

URL="https://$APP_DOMAIN:8443/api/status"

# What the OS resolver (mDNSResponder, with its cache) returns.
system_ip() {
    dscacheutil -q host -a name "$APP_DOMAIN" 2>/dev/null | awk '/^ip_address:/ {print $2; exit}'
}

# fetch <timeout>: prints the response headers of one GET to $URL.
fetch() { "$CURL" -s -o /dev/null -D - --connect-timeout 2 -m "$1" "$URL" 2>/dev/null; }

status_code() { head -1 | awk '{print $2}'; }

do_flush() {
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
    echo "[OK] macOS DNS cache flushed"
}

do_lb() {
    local n="${1:-6}" i hdrs code be edge up ok=0 a=0 b=0
    echo "$n requests to $URL"
    for i in $(seq 1 "$n"); do
        hdrs="$(fetch 10)"
        code="$(printf '%s\n' "$hdrs" | status_code)"
        be="$(printf '%s\n' "$hdrs" | header_value X-Backend)"
        edge="$(printf '%s\n' "$hdrs" | header_value X-Edge)"
        up="$(printf '%s\n' "$hdrs" | header_value X-Upstream-Addr)"
        if [ -z "$code" ]; then
            printf '  %2d  FAIL (no response)\n' "$i"
            continue
        fi
        printf '  %2d  HTTP %s  X-Backend: %-2s X-Edge: %-13s upstream: %s\n' \
            "$i" "$code" "${be:--}" "${edge:--}" "${up:--}"
        [ "$code" = "200" ] && ok=$((ok + 1))
        [ "$be" = "A" ] && a=$((a + 1))
        [ "$be" = "B" ] && b=$((b + 1))
    done
    echo "Summary: $ok/$n HTTP 200, Backend A: $a, Backend B: $b"
}

do_watch() {
    local ip hdrs code edge be
    echo "Watching $APP_DOMAIN every 2 s (TTL is 30 s). Ctrl-C to stop."
    while true; do
        ip="$(system_ip)"
        hdrs="$(fetch 4)"
        code="$(printf '%s\n' "$hdrs" | status_code)"
        edge="$(printf '%s\n' "$hdrs" | header_value X-Edge)"
        be="$(printf '%s\n' "$hdrs" | header_value X-Backend)"
        printf '%s  system-resolver: %-15s  HTTP %-3s  X-Edge: %-13s X-Backend: %s\n' \
            "$(date +%H:%M:%S)" "${ip:-(none)}" "${code:----}" "${edge}" "${be}"
        sleep 2
    done
}

# probe <label> <ip> <port>
probe() {
    local out
    if out="$(nc -z -v -G 2 -w 2 "$2" "$3" 2>&1)"; then
        printf '  %-22s %s:%-5s [OPEN]\n' "$1" "$2" "$3"
    elif echo "$out" | grep -qi refused; then
        printf '  %-22s %s:%-5s [CLOSED] connection refused: service down, not firewalled\n' "$1" "$2" "$3"
    else
        printf '  %-22s %s:%-5s [BLOCKED] no reply (timed out): dropped by firewall\n' "$1" "$2" "$3"
    fi
}

do_isolation() {
    echo "From this Mac ($(local_ips | tr '\n' ' '))"
    probe "Backend A (Mac 3)" "$MAC3_IP" 3001
    probe "Backend B (Mac 4)" "$MAC4_IP" 3002
    local code
    code="$("$CURL" -s -o /dev/null -w '%{http_code}' --connect-timeout 3 -m 10 "$URL" 2>/dev/null)"
    printf '  %-22s %s  HTTP %s\n' "Edge (via DNS)" "$URL" "${code:-000}"
}

# ask <label> <server-ip>
ask() {
    local ans
    ans="$(dig "$APP_DOMAIN" @"$2" +short +time=2 +tries=1 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | tail -1)"
    printf '  %-24s %-15s -> %s\n' "$1" "$2" "${ans:-NO ANSWER}"
}

do_dns() {
    echo "Client resolver order (scutil --dns):"
    scutil --dns | awk '/nameserver\[[0-9]+\]/ {print $3}' | awk '!seen[$0]++' | head -3 | sed 's/^/  /'
    echo "Direct queries for $APP_DOMAIN:"
    ask "Primary DNS (Mac 1)" "$MAC1_IP"
    ask "Backup DNS (Mac 4)" "$MAC4_IP"
    local ip
    ip="$(system_ip)"
    printf '  %-24s %-15s -> %s\n' "System resolver" "(OS cache)" "${ip:-NO ANSWER}"
}

case "${1:-}" in
    flush)     do_flush ;;
    lb)        do_lb "${2:-6}" ;;
    watch)     do_watch ;;
    isolation) do_isolation ;;
    dns)       do_dns ;;
    *) echo "Usage: $0 flush|lb [N]|watch|isolation|dns" >&2; exit 1 ;;
esac
