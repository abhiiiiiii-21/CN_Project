#!/usr/bin/env bash
# ==============================================================================
# dns-demo.sh — client-side DNS demonstrations for Phase 2 (run on a client Mac)
# ==============================================================================
# Usage:
#   ./scripts/dns-demo.sh dns     ask primary, backup and system resolver (Ext A)
#   ./scripts/dns-demo.sh watch   every 2s: cached IP + HTTPS status (Ext B, Ext E)
#   ./scripts/dns-demo.sh flush   flush the macOS DNS cache (needs sudo)
# Everything is read-only except "flush".
# ==============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib-env.sh
source "$ROOT/scripts/lib-env.sh"
cn_load_env "$ROOT"

APP="app.$TEAM.test"
# dscacheutil uses the macOS resolver cache; dig does not.
sys_ip() { dscacheutil -q host -a name "$APP" 2>/dev/null | awk '/ip_address/ {print $2; exit}'; }

case "${1:-}" in
    dns)
        echo "Configured resolvers (scutil --dns):"
        scutil --dns | awk '/^resolver #1/{f=1} /^resolver #2/{exit} f && /nameserver/'
        for s in "$MAC1_IP:primary (Mac 1)" "$MAC4_IP:backup (Mac 4)"; do
            ip="${s%%:*}"; name="${s#*:}"
            ans="$(dig @"$ip" "$APP" +noall +answer +time=2 +tries=1 2>&1 | grep -v '^;' | head -1)"
            printf '  %-17s %-15s -> %s\n' "$name" "$ip" "${ans:-NO ANSWER (resolver down?)}"
        done
        echo "  system resolver: $APP -> $(sys_ip)" ;;
    watch)
        echo "Ctrl-C to stop. primary edge=$MAC2_IP  standby edge=$MAC3_IP"
        while true; do
            code="$(/usr/bin/curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 "https://$APP:8443/api/status")"
            printf '%s  system-resolver: %-15s  HTTPS: %s\n' "$(date +%T)" "$(sys_ip)" "$code"
            sleep 2
        done ;;
    flush)
        sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder && echo "macOS DNS cache flushed." ;;
    *) sed -n '3,10p' "$0"; exit 1 ;;
esac
