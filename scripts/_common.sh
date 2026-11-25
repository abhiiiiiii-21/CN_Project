# shellcheck shell=bash
# Shared helpers for the Phase 2 scripts. Source it; do not run it.
# Written for macOS's bash 3.2 (no associative arrays, no mapfile).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIVE_DIR="$PROJECT_ROOT/config/live"

# System curl trusts the System keychain (team-CA.pem); Homebrew curl does not.
CURL="/usr/bin/curl"
[ -x "$CURL" ] || CURL="curl"

die()  { echo "Error: $*" >&2; exit 1; }
warn() { echo "[WARN] $*" >&2; }

load_env() {
    local f="${CN_ENV:-$HOME/cn-team.env}"
    [ -f "$f" ] || die "$f not found. Do steps 2-3 of the command sheet first."
    # shellcheck disable=SC1090
    source "$f"
    local v
    for v in TEAM MAC1_IP MAC2_IP MAC3_IP MAC4_IP COLLEGE_DNS; do
        [ -n "${!v:-}" ] || die "$v is not set in $f"
    done
    APP_DOMAIN="app.${TEAM}.test"
}

is_ipv4() { echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; }

local_ips() {
    local i
    for i in en0 en1 en2 en3; do ipconfig getifaddr "$i" 2>/dev/null || true; done
}

# warn_if_not_me <ip> <label>: warn when this Mac does not own <ip>.
warn_if_not_me() {
    if ! local_ips | grep -qxF "$1"; then
        warn "This Mac does not have $1 ($2). Are you on the right Mac, or did the IP change?"
    fi
}

brew_prefix() { brew --prefix 2>/dev/null || echo /opt/homebrew; }

# header_value <name> : read one header from stdin (curl -D - output), trimmed.
header_value() {
    grep -i "^$1:" | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}
