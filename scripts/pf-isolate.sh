#!/usr/bin/env bash
# ==============================================================================
# pf-isolate.sh: Ext C backend isolation on Mac 3 / Mac 4
# ==============================================================================
# Usage:
#   ./scripts/pf-isolate.sh check     # parse config/live/pf-backends.conf only
#   ./scripts/pf-isolate.sh enable    # load rules into anchor, enable pf
#   ./scripts/pf-isolate.sh disable   # flush the anchor, release pf  ("Rolled back")
#   ./scripts/pf-isolate.sh status
#
# Rules live in the anchor com.apple/cn-isolate, which the stock macOS
# /etc/pf.conf already evaluates ("anchor com.apple/*"). /etc/pf.conf is never
# edited. pf is enabled with a reference token (pfctl -E) so disable gives back
# exactly what enable took.
# ==============================================================================

set -euo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
load_env

ANCHOR="com.apple/cn-isolate"
RULES="$LIVE_DIR/pf-backends.conf"
TOKEN_FILE="/tmp/cn-pf-isolate.token"

# pfctl prints harmless ALTQ notices on macOS; hide them.
pf() { sudo pfctl "$@" 2>&1 | grep -v -e 'ALTQ' -e '^$' || true; }

need_rules() { [ -f "$RULES" ] || die "$RULES missing. Run ./scripts/render-configs.sh first."; }

check_backend_mac() {
    if ! local_ips | grep -qxF "$MAC3_IP" && ! local_ips | grep -qxF "$MAC4_IP"; then
        warn "This Mac is neither Mac 3 ($MAC3_IP) nor Mac 4 ($MAC4_IP). pf rules belong on the backend Macs."
    fi
}

do_check() {
    need_rules
    if sudo pfctl -a "$ANCHOR" -nf "$RULES" >/dev/null 2>&1; then
        echo "Rules parse OK ($RULES)"
    else
        pf -a "$ANCHOR" -nf "$RULES"
        die "pf rules did not parse."
    fi
}

list_rules() {
    local r
    r="$(pf -a "$ANCHOR" -sr)"
    if [ -n "$r" ]; then echo "$r"; else echo "(no rules in anchor $ANCHOR)"; fi
}

case "${1:-}" in
    check)
        do_check
        ;;
    enable)
        check_backend_mac
        do_check
        pf -a "$ANCHOR" -f "$RULES" >/dev/null
        if [ ! -s "$TOKEN_FILE" ]; then
            token="$(sudo pfctl -E 2>&1 | awk '/Token/ {print $NF}')"
            [ -n "$token" ] && echo "$token" > "$TOKEN_FILE"
        fi
        echo "pf enabled (anchor $ANCHOR)"
        echo "Rules:"
        list_rules
        ;;
    disable)
        pf -a "$ANCHOR" -F rules >/dev/null
        if [ -s "$TOKEN_FILE" ]; then
            pf -X "$(cat "$TOKEN_FILE")" >/dev/null
            rm -f "$TOKEN_FILE"
        fi
        echo "Rolled back (anchor $ANCHOR flushed)"
        echo "Rules:"
        list_rules
        ;;
    status)
        pf -s info | head -1
        echo "Rules in $ANCHOR (with hit counters):"
        r="$(pf -a "$ANCHOR" -v -sr)"
        if [ -n "$r" ]; then echo "$r"; else echo "(none)"; fi
        ;;
    *)
        echo "Usage: $0 check|enable|disable|status" >&2
        exit 1
        ;;
esac
