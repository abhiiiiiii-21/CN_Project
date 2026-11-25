#!/usr/bin/env bash
# ==============================================================================
# mac1.sh — one-key control panel for Mac 1 (primary DNS)
# ==============================================================================
# Usage:
#   ./scripts/mac1.sh              open the menu (press one key per action)
#   ./scripts/mac1.sh <action>     demo | normal | start | stop | restart |
#                                  status | standby | primary | flush | test | logs
# It changes settings on THIS Mac only. It cannot change the other Macs.
# sudo asks for your Mac password in the terminal.
# ==============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
WIFI="Wi-Fi"
ENV_FILE="${CN_ENV:-$HOME/cn-team.env}"

load() {
    [ -f "$ENV_FILE" ] || { echo "Error: $ENV_FILE not found. Copy config/cn-team.env.example there and fill in the IPs."; return 1; }
    # shellcheck disable=SC1090
    source "$ENV_FILE"
}

# Stop early if this Mac's address is not the MAC1_IP in the env file.
check_ip() {
    local now
    now="$(ipconfig getifaddr en0 2>/dev/null || true)"
    if [ "$now" != "$MAC1_IP" ]; then
        echo "STOP: this Mac's IP is '${now:-none}', but MAC1_IP in $ENV_FILE is $MAC1_IP."
        echo "Check that you are on the project Wi-Fi. If your IP changed, update MAC1_IP"
        echo "on all four Macs, and have each Mac run ./scripts/render-configs.sh again."
        return 1
    fi
}

flush_cache() { ./scripts/dns-demo.sh flush; }

do_demo() {
    load && check_ip || return 1
    echo "== 1/5 Build configs (app and api point to Mac 2)"
    ./scripts/render-configs.sh || return 1
    echo "== 2/5 Start or restart primary DNS"
    ./scripts/dns-ctl.sh primary restart || return 1
    echo "== 3/5 This Mac uses Mac 1, then Mac 4"
    sudo networksetup -setdnsservers "$WIFI" "$MAC1_IP" "$MAC4_IP" || return 1
    echo "== 4/5 Flush DNS cache"
    flush_cache || return 1
    echo "== 5/5 Quick check"
    show_status
    echo
    echo "DEMO MODE is on for Mac 1. Each other client Mac must run:"
    echo "  sudo networksetup -setdnsservers Wi-Fi $MAC1_IP $MAC4_IP"
}

do_normal() {
    echo "Other Macs that use the team DNS should go back to automatic DNS too. On each of them:"
    echo "  sudo networksetup -setdnsservers Wi-Fi empty"
    echo "== 1/3 This Mac: automatic DNS"
    sudo networksetup -setdnsservers "$WIFI" empty || return 1
    echo "== 2/3 Stop primary DNS"
    ./scripts/dns-ctl.sh primary stop || return 1
    echo "== 3/3 Flush DNS cache"
    flush_cache || return 1
    echo
    echo "NORMAL MODE: DNS setting is now:"
    networksetup -getdnsservers "$WIFI"
}

show_status() {
    load || return 1
    echo "My IP:          $(ipconfig getifaddr en0 2>/dev/null || echo none)   (env MAC1_IP: $MAC1_IP)"
    echo "My DNS setting: $(networksetup -getdnsservers "$WIFI" | tr '\n' ' ')"
    if pgrep -f "dnsmasq --conf-file=.*config/live/dnsmasq.conf" >/dev/null; then
        echo "Primary DNS:    RUNNING"
    else
        echo "Primary DNS:    STOPPED"
    fi
    local who ip ans
    for who in "primary:$MAC1_IP" "backup:$MAC4_IP"; do
        ip="${who#*:}"
        ans="$(dig +short "app.$TEAM.test" @"$ip" +time=2 +tries=1 2>/dev/null | grep -v '^;' | head -1)"
        echo "app.$TEAM.test from ${who%%:*} ($ip): ${ans:-NO ANSWER}"
    done
}

run_action() {
    case "$1" in
        demo)    do_demo ;;
        normal)  do_normal ;;
        start)   load && check_ip && ./scripts/dns-ctl.sh primary start ;;
        stop)    ./scripts/dns-ctl.sh primary stop ;;
        restart) load && check_ip && ./scripts/dns-ctl.sh primary restart ;;
        status)  show_status ;;
        standby) load && ./scripts/dns-ctl.sh primary point-app "$MAC3_IP" ;;
        primary) load && ./scripts/dns-ctl.sh primary point-app "$MAC2_IP" ;;
        flush)   flush_cache ;;
        test)    ./scripts/demo.sh all ;;
        logs)    ./scripts/dns-ctl.sh primary logs ;;
        *) echo "Unknown action: $1"; return 1 ;;
    esac
}

if [ $# -gt 0 ]; then
    run_action "$1"
    exit $?
fi

while true; do
    cat <<'MENU'

========= Mac 1 control panel =========
  d  DEMO MODE on   (start DNS, set this Mac's DNS, flush, check)
  n  NORMAL MODE    (automatic DNS, stop DNS, flush)
  --- DNS server ---
  1  start          2  stop           3  restart
  i  status         l  live logs (Ctrl-C closes this panel)
  --- demo actions ---
  e  app -> standby edge, Mac 3   (Ext B / Ext E)
  p  app -> primary edge, Mac 2   (change back)
  f  flush this Mac's DNS cache
  t  run all checks
  q  quit (does not stop DNS)
=======================================
MENU
    printf 'Press a key: '
    read -r -n 1 key || break
    echo
    case "$key" in
        d) run_action demo ;;
        n) run_action normal ;;
        1) run_action start ;;
        2) run_action stop ;;
        3) run_action restart ;;
        i) run_action status ;;
        l) run_action logs ;;
        e) run_action standby ;;
        p) run_action primary ;;
        f) run_action flush ;;
        t) run_action test ;;
        q) break ;;
        *) echo "No action for '$key'." ;;
    esac || echo "The action did not finish. Read the message above."
done
