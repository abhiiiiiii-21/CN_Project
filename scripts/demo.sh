#!/usr/bin/env bash
# ==============================================================================
# demo.sh
# ==============================================================================
# Read-only verification and demonstration script for the 3-Mac Computer Networks
# Phase 1 private network platform.
#
# IMPORTANT:
# This script is strictly READ-ONLY. It does NOT modify DNS settings, Nginx configs,
# dnsmasq configs, certificates, or system services.
#
# Usage:
#   ./scripts/demo.sh [lan|dns|backends|lb|tls|http|cache|check|all]
#
# Environment:
#   Sources ~/cn-team.env (or CN_ENV=/path/to/env if set)
# ==============================================================================

set -uo pipefail

CURL_BIN="/usr/bin/curl"
if [ ! -x "$CURL_BIN" ]; then
    CURL_BIN="curl"
fi

ENV_FILE="${CN_ENV:-$HOME/cn-team.env}"

if [ ! -f "$ENV_FILE" ]; then
    if [ -f "config/cn-team.env" ]; then
        ENV_FILE="config/cn-team.env"
    else
        echo "Error: Environment file not found at: $ENV_FILE"
        echo "Ensure ~/cn-team.env exists or specify CN_ENV=/path/to/env"
        exit 1
    fi
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# Required variables check (Strictly 3 Macs)
for var in TEAM MAC1_IP MAC2_IP MAC3_IP COLLEGE_DNS; do
    if [ -z "${!var:-}" ]; then
        echo "Error: Required variable '$var' is not set in $ENV_FILE"
        exit 1
    fi
done

APP_DOMAIN="app.${TEAM}.test"
API_DOMAIN="api.${TEAM}.test"
NOTHERE_DOMAIN="nothere.${TEAM}.test"

# Color helpers
BOLD="\033[1m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

log_info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_pass()    { echo -e "${GREEN}[PASS]${RESET} $*"; }
log_fail()    { echo -e "${RED}[FAIL]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_header()  { echo -e "\n${BOLD}======================================================================${RESET}\n${BOLD}$*${RESET}\n${BOLD}======================================================================${RESET}"; }

# ------------------------------------------------------------------------------
# TEST 1: LAN Connectivity Check (Exactly 3 Macs)
# ------------------------------------------------------------------------------
test_lan() {
    log_header "TEST 1: LAN Reachability (3-Mac Architecture)"
    local overall_pass=true

    check_host() {
        local name="$1"
        local ip="$2"
        local port="$3"
        local ping_ok=false
        local tcp_ok=false

        echo -n "Checking $name ($ip)... "

        # 1. Try ICMP ping (1 packet, 1 second timeout)
        if ping -c 1 -t 1 "$ip" >/dev/null 2>&1 || ping -c 1 -W 1000 "$ip" >/dev/null 2>&1; then
            ping_ok=true
        fi

        # 2. Try TCP fallback if port provided
        if [ -n "$port" ]; then
            if nc -z -G 2 "$ip" "$port" >/dev/null 2>&1; then
                tcp_ok=true
            fi
        fi

        if [ "$ping_ok" = true ]; then
            log_pass "$name ($ip) is reachable via ICMP ping."
        elif [ "$tcp_ok" = true ]; then
            log_pass "$name ($ip) is reachable via TCP :$port (ICMP ping blocked/filtered)."
        else
            log_fail "$name ($ip) could not be reached via ICMP or TCP."
            overall_pass=false
        fi
    }

    check_host "Mac 1 (DNS)" "$MAC1_IP" 53
    check_host "Mac 2 (Nginx Edge / TLS)" "$MAC2_IP" 8443
    check_host "Mac 3 (Backend Services)" "$MAC3_IP" 3001

    if [ "$overall_pass" = true ]; then
        log_pass "LAN connectivity check: PASS"
        return 0
    else
        log_fail "LAN connectivity check: FAIL"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# TEST 2: Private DNS Verification
# ------------------------------------------------------------------------------
test_dns() {
    log_header "TEST 2: DNS Resolution via Mac 1 ($MAC1_IP:53)"
    local overall_pass=true

    echo "Querying Mac 1 for $APP_DOMAIN..."
    local app_dig
    app_dig="$(dig @"$MAC1_IP" "$APP_DOMAIN" +noall +answer +comments 2>&1 || true)"
    echo "$app_dig"

    local app_ip
    app_ip="$(dig @"$MAC1_IP" "$APP_DOMAIN" +short 2>/dev/null | tr -d '\r' | tail -1)"
    local app_server
    app_server="$(echo "$app_dig" | grep -i "SERVER:" || true)"

    if [ -n "$app_server" ]; then
        log_info "DNS Responder: $app_server"
    fi

    if [ "$app_ip" = "$MAC2_IP" ]; then
        log_pass "$APP_DOMAIN resolved to Mac 2 IP ($MAC2_IP)"
    else
        log_fail "$APP_DOMAIN resolved to '$app_ip', expected '$MAC2_IP'"
        overall_pass=false
    fi

    echo ""
    echo "Querying Mac 1 for $API_DOMAIN..."
    local api_ip
    api_ip="$(dig @"$MAC1_IP" "$API_DOMAIN" +short 2>/dev/null | tr -d '\r' | tail -1)"
    if [ "$api_ip" = "$MAC2_IP" ]; then
        log_pass "$API_DOMAIN resolved to Mac 2 IP ($MAC2_IP)"
    else
        log_fail "$API_DOMAIN resolved to '$api_ip', expected '$MAC2_IP'"
        overall_pass=false
    fi

    echo ""
    echo "Querying Mac 1 for non-existent domain: $NOTHERE_DOMAIN..."
    local nx_dig
    nx_dig="$(dig @"$MAC1_IP" "$NOTHERE_DOMAIN" 2>&1 || true)"
    if echo "$nx_dig" | grep -q "status: NXDOMAIN"; then
        log_pass "$NOTHERE_DOMAIN returned status: NXDOMAIN as expected."
    else
        log_fail "$NOTHERE_DOMAIN did not return NXDOMAIN."
        echo "$nx_dig" | grep "status:" || true
        overall_pass=false
    fi

    if [ "$overall_pass" = true ]; then
        log_pass "DNS resolution check: PASS"
        return 0
    else
        log_fail "DNS resolution check: FAIL"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# TEST 3: Direct Backend Verification (Mac 3 :3001 and :3002)
# ------------------------------------------------------------------------------
test_backends() {
    log_header "TEST 3: Direct Backend Services on Mac 3"
    local overall_pass=true

    echo "1. Checking Backend A on http://$MAC3_IP:3001/api/status..."
    local resp_a
    resp_a="$($CURL_BIN -sS --connect-timeout 3 -i "http://$MAC3_IP:3001/api/status" 2>&1 || true)"
    local hdr_a
    hdr_a="$(echo "$resp_a" | grep -i "^X-Backend:" | tr -d '\r' | awk '{print $2}')"
    if [ "$hdr_a" = "A" ]; then
        log_pass "Backend A responded with X-Backend: A"
    else
        log_fail "Backend A check failed. Received: '$hdr_a'. Raw output:\n$resp_a"
        overall_pass=false
    fi

    echo ""
    echo "2. Checking Backend B on http://$MAC3_IP:3002/api/status..."
    local resp_b
    resp_b="$($CURL_BIN -sS --connect-timeout 3 -i "http://$MAC3_IP:3002/api/status" 2>&1 || true)"
    local hdr_b
    hdr_b="$(echo "$resp_b" | grep -i "^X-Backend:" | tr -d '\r' | awk '{print $2}')"
    if [ "$hdr_b" = "B" ]; then
        log_pass "Backend B responded with X-Backend: B"
    else
        log_fail "Backend B check failed. Received: '$hdr_b'. Raw output:\n$resp_b"
        overall_pass=false
    fi

    echo ""
    echo "3. Checking ETag consistency on /api/info across Backend A and Backend B..."
    local info_a
    info_a="$($CURL_BIN -sS --connect-timeout 3 -i "http://$MAC3_IP:3001/api/info" 2>&1 || true)"
    local etag_a
    etag_a="$(echo "$info_a" | grep -i "^ETag:" | tr -d '\r' | awk '{print $2}')"

    local info_b
    info_b="$($CURL_BIN -sS --connect-timeout 3 -i "http://$MAC3_IP:3002/api/info" 2>&1 || true)"
    local etag_b
    etag_b="$(echo "$info_b" | grep -i "^ETag:" | tr -d '\r' | awk '{print $2}')"

    log_info "Backend A /api/info ETag: $etag_a"
    log_info "Backend B /api/info ETag: $etag_b"

    if [ -n "$etag_a" ] && [ "$etag_a" = "$etag_b" ]; then
        log_pass "ETag matches identically between Backend A and Backend B ($etag_a)"
    else
        log_fail "ETag mismatch between backends: A='$etag_a', B='$etag_b'"
        overall_pass=false
    fi

    if [ "$overall_pass" = true ]; then
        log_pass "Backend services check: PASS"
        return 0
    else
        log_fail "Backend services check: FAIL"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# TEST 4: Load Balancing Test (Mac 2 Nginx -> Mac 3 Backends)
# ------------------------------------------------------------------------------
test_lb() {
    log_header "TEST 4: Load Balancing via https://$APP_DOMAIN:8443/api/status"
    local total_reqs=6
    local success_count=0
    local sequence=()

    echo "Dispatching $total_reqs consecutive requests through Mac 2 edge proxy..."

    for i in $(seq 1 $total_reqs); do
        local resp
        resp="$($CURL_BIN -sS --connect-timeout 3 -i "https://$APP_DOMAIN:8443/api/status" 2>&1 || true)"
        local backend
        backend="$(echo "$resp" | grep -i "^X-Backend:" | tr -d '\r' | awk '{print $2}')"
        local upstream
        upstream="$(echo "$resp" | grep -i "^X-Upstream-Addr:" | tr -d '\r' | awk '{print $2}')"

        if [ -n "$backend" ]; then
            success_count=$((success_count + 1))
            sequence+=("Req $i: Backend $backend (${upstream:-upstream})")
            echo "  Request $i -> X-Backend: $backend | X-Upstream-Addr: ${upstream:-not set}"
        else
            sequence+=("Req $i: FAILED")
            echo "  Request $i -> FAILED to receive valid response. Error: $(echo "$resp" | head -1)"
        fi
    done

    echo ""
    log_info "Observed Request Distribution Sequence:"
    for item in "${sequence[@]}"; do
        echo "    $item"
    done

    if [ "$success_count" -eq "$total_reqs" ]; then
        log_pass "Load balancer processed all $total_reqs requests successfully: PASS"
        return 0
    else
        log_fail "Load balancer failed on $((total_reqs - success_count)) of $total_reqs requests: FAIL"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# TEST 5: TLS & Certificate Validation
# ------------------------------------------------------------------------------
test_tls() {
    log_header "TEST 5: TLS Verification (Strict PKI Validation without -k)"
    local overall_pass=true

    echo "1. Checking TLS connection to https://$APP_DOMAIN:8443/api/status..."
    local curl_v
    curl_v="$($CURL_BIN -v --connect-timeout 4 "https://$APP_DOMAIN:8443/api/status" 2>&1 || true)"

    # Check TLS Handshake & Certificate Verification
    if echo "$curl_v" | grep -qi "SSL certificate verify ok"; then
        log_pass "Certificate validation succeeded against trusted Root CA."
    elif echo "$curl_v" | grep -qi "server certificate verification OK"; then
        log_pass "Server certificate verification OK."
    else
        log_fail "Certificate validation failed. Ensure Team Root CA is in System Keychain."
        echo "$curl_v" | grep -iE "SSL certificate|certificate verify|error" | head -5 || true
        overall_pass=false
    fi

    # Check Subject & SAN
    local san_match
    san_match="$(echo "$curl_v" | grep -i "subjectAltName: host \"$APP_DOMAIN\" matched" || true)"
    if [ -n "$san_match" ]; then
        log_pass "Subject Alternative Name (SAN) verified: $san_match"
    else
        # Fallback check for common name / cert subject
        local cert_subject
        cert_subject="$(echo "$curl_v" | grep -i "subject:" || true)"
        log_info "Certificate subject info: ${cert_subject:-none}"
    fi

    # Check Issuer
    local cert_issuer
    cert_issuer="$(echo "$curl_v" | grep -i "issuer:" || true)"
    if [ -n "$cert_issuer" ]; then
        log_pass "Certificate Issuer verified: $cert_issuer"
    else
        log_warn "Issuer line not captured in curl verbose output."
    fi

    # Check TLS Protocol Version
    local tls_version
    tls_version="$(echo "$curl_v" | grep -iE "SSL connection using (TLSv1\.[23])" || true)"
    if [ -n "$tls_version" ]; then
        log_pass "Negotiated TLS Version: $tls_version"
    else
        log_info "TLS connection established."
    fi

    # Check API Domain SAN via https://api.TEAM.test:8443/api/status
    echo ""
    echo "2. Checking TLS connection to secondary SAN domain https://$API_DOMAIN:8443/api/status..."
    local api_curl
    api_curl="$($CURL_BIN -sS --connect-timeout 4 -o /dev/null -w "%{http_code}" "https://$API_DOMAIN:8443/api/status" 2>&1 || true)"
    if [ "$api_curl" = "200" ]; then
        log_pass "Secondary SAN domain $API_DOMAIN connected securely with HTTP 200."
    else
        log_fail "Secondary SAN domain $API_DOMAIN check returned: '$api_curl'"
        overall_pass=false
    fi

    if [ "$overall_pass" = true ]; then
        log_pass "TLS verification check: PASS"
        return 0
    else
        log_fail "TLS verification check: FAIL"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# TEST 6: HTTP Protocol & Redirect Verification
# ------------------------------------------------------------------------------
test_http() {
    log_header "TEST 6: HTTP Protocol & Redirection (8080 -> 8443)"
    local overall_pass=true

    # 1. HTTP/1.1 check
    echo "1. Checking HTTP/1.1 support..."
    local h1_resp
    h1_resp="$($CURL_BIN --http1.1 -sS --connect-timeout 3 -i "https://$APP_DOMAIN:8443/api/status" 2>&1 || true)"
    if echo "$h1_resp" | grep -q "^HTTP/1\.1 200"; then
        log_pass "HTTP/1.1 200 OK verified."
    else
        log_fail "HTTP/1.1 request failed. First line: $(echo "$h1_resp" | head -1)"
        overall_pass=false
    fi

    # 2. HTTP/2 check
    echo ""
    echo "2. Checking HTTP/2 support..."
    if $CURL_BIN --version | grep -qi "HTTP2"; then
        local h2_resp
        h2_resp="$($CURL_BIN --http2 -sS --connect-timeout 3 -i "https://$APP_DOMAIN:8443/api/status" 2>&1 || true)"
        if echo "$h2_resp" | grep -qiE "^HTTP/2 200"; then
            log_pass "HTTP/2 200 OK verified."
        else
            log_warn "HTTP/2 not negotiated (returned: $(echo "$h2_resp" | head -1))."
        fi
    else
        log_warn "Local curl binary does not support HTTP/2; skipping HTTP/2 test."
    fi

    # 3. HTTP 8080 -> HTTPS 8443 Redirection check
    echo ""
    echo "3. Checking plaintext redirect: http://$APP_DOMAIN:8080/ -> https://$APP_DOMAIN:8443/..."
    local redir_resp
    redir_resp="$($CURL_BIN -sS --connect-timeout 3 -i "http://$APP_DOMAIN:8080/" 2>&1 || true)"
    local status_line
    status_line="$(echo "$redir_resp" | head -1 | tr -d '\r')"
    local loc_header
    loc_header="$(echo "$redir_resp" | grep -i "^Location:" | tr -d '\r' | awk '{print $2}')"

    echo "  Status line:     $status_line"
    echo "  Location header: $loc_header"

    if echo "$status_line" | grep -qE "301|302|307|308"; then
        if echo "$loc_header" | grep -qE "https://${APP_DOMAIN}:8443/"; then
            log_pass "Port 8080 successfully redirects to https://$APP_DOMAIN:8443/"
        else
            log_warn "Redirect returned status $status_line, but Location header was '$loc_header'."
        fi
    else
        log_fail "Port 8080 did not return a redirect status code. Raw status: $status_line"
        overall_pass=false
    fi

    if [ "$overall_pass" = true ]; then
        log_pass "HTTP protocol and redirection check: PASS"
        return 0
    else
        log_fail "HTTP protocol and redirection check: FAIL"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# TEST 7: HTTP Caching & Conditional Revalidation
# ------------------------------------------------------------------------------
test_cache() {
    log_header "TEST 7: HTTP Caching & ETag Validation (/api/info & /api/status)"
    local overall_pass=true

    echo "1. Initial fetch of cacheable resource: https://$APP_DOMAIN:8443/api/info..."
    local initial_resp
    initial_resp="$($CURL_BIN -sS --connect-timeout 3 -i "https://$APP_DOMAIN:8443/api/info" 2>&1 || true)"

    local initial_status
    initial_status="$(echo "$initial_resp" | head -1 | tr -d '\r')"
    local cache_ctrl
    cache_ctrl="$(echo "$initial_resp" | grep -i "^Cache-Control:" | tr -d '\r' | cut -d':' -f2- | sed 's/^[[:space:]]*//')"
    local etag
    etag="$(echo "$initial_resp" | grep -i "^ETag:" | tr -d '\r' | awk '{print $2}')"

    echo "  Status:        $initial_status"
    echo "  Cache-Control: $cache_ctrl"
    echo "  ETag:          $etag"

    if echo "$initial_status" | grep -q "200"; then
        log_pass "Initial request returned HTTP 200 OK."
    else
        log_fail "Initial request returned: $initial_status"
        overall_pass=false
    fi

    if echo "$cache_ctrl" | grep -qi "public" && echo "$cache_ctrl" | grep -qi "max-age=60"; then
        log_pass "Cache-Control header verified: public, max-age=60"
    else
        log_fail "Cache-Control header mismatch: '$cache_ctrl', expected 'public, max-age=60'"
        overall_pass=false
    fi

    if [ -z "$etag" ]; then
        log_fail "No ETag header returned by /api/info."
        overall_pass=false
    else
        log_pass "Extracted ETag automatically: $etag"
    fi

    echo ""
    echo "2. Sending conditional request with If-None-Match: $etag..."
    local cond_resp
    cond_resp="$($CURL_BIN -sS --connect-timeout 3 -i -H "If-None-Match: $etag" "https://$APP_DOMAIN:8443/api/info" 2>&1 || true)"
    local cond_status
    cond_status="$(echo "$cond_resp" | head -1 | tr -d '\r')"

    echo "  Conditional Status: $cond_status"

    if echo "$cond_status" | grep -q "304"; then
        log_pass "Conditional revalidation returned HTTP 304 Not Modified."
    else
        log_fail "Conditional revalidation failed. Expected 304, got: $cond_status"
        overall_pass=false
    fi

    echo ""
    echo "3. Checking dynamic endpoint: https://$APP_DOMAIN:8443/api/status..."
    local status_resp
    status_resp="$($CURL_BIN -sS --connect-timeout 3 -i "https://$APP_DOMAIN:8443/api/status" 2>&1 || true)"
    local dyn_cache
    dyn_cache="$(echo "$status_resp" | grep -i "^Cache-Control:" | tr -d '\r' | cut -d':' -f2- | sed 's/^[[:space:]]*//')"
    local dyn_code
    dyn_code="$(echo "$status_resp" | head -1 | tr -d '\r')"

    echo "  Status:        $dyn_code"
    echo "  Cache-Control: $dyn_cache"

    if echo "$dyn_code" | grep -q "200" && echo "$dyn_cache" | grep -qi "no-store"; then
        log_pass "/api/status correctly returns 200 with Cache-Control: no-store"
    else
        log_fail "/api/status cache validation failed (Status: '$dyn_code', Cache-Control: '$dyn_cache')"
        overall_pass=false
    fi

    if [ "$overall_pass" = true ]; then
        log_pass "HTTP caching check: PASS"
        return 0
    else
        log_fail "HTTP caching check: FAIL"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# TEST 8: Layered Diagnostic Check (DNS -> TCP -> TLS -> HTTP)
# ------------------------------------------------------------------------------
test_check() {
    log_header "TEST 8: Layered Diagnostic Pipeline (DNS -> TCP -> TLS -> HTTP)"

    # Layer 1: DNS
    echo -n "Layer 1 [DNS]: Resolving $APP_DOMAIN via Mac 1 ($MAC1_IP:53)... "
    local resolved_ip
    resolved_ip="$(dig @"$MAC1_IP" "$APP_DOMAIN" +short 2>/dev/null | tr -d '\r' | tail -1)"
    if [ "$resolved_ip" = "$MAC2_IP" ]; then
        echo -e "${GREEN}OK${RESET} ($APP_DOMAIN -> $MAC2_IP)"
    else
        echo -e "${RED}FAILED${RESET}"
        log_fail "DNS Layer Failure: $APP_DOMAIN resolved to '${resolved_ip:-empty}', expected '$MAC2_IP'."
        echo "Cannot proceed past failing DNS layer."
        return 1
    fi

    # Layer 2: TCP
    echo -n "Layer 2 [TCP]: Connecting to Mac 2 at $MAC2_IP:8443... "
    if nc -z -G 2 "$MAC2_IP" 8443 >/dev/null 2>&1; then
        echo -e "${GREEN}OK${RESET} (Port 8443 open and accepting connections)"
    else
        echo -e "${RED}FAILED${RESET}"
        log_fail "TCP Layer Failure: Connection to $MAC2_IP:8443 was refused or timed out."
        echo "Check if Nginx is running on Mac 2."
        return 1
    fi

    # Layer 3: TLS
    echo -n "Layer 3 [TLS]: Handshaking and validating certificate for $APP_DOMAIN... "
    local tls_check
    tls_check="$($CURL_BIN -v --connect-timeout 4 "https://$APP_DOMAIN:8443/api/status" 2>&1 || true)"
    if echo "$tls_check" | grep -qiE "certificate verify ok|verification OK"; then
        echo -e "${GREEN}OK${RESET} (Trusted CA + SAN validated)"
    else
        echo -e "${RED}FAILED${RESET}"
        log_fail "TLS Layer Failure: Certificate verification failed."
        echo "OpenSSL/cURL Error Details:"
        echo "$tls_check" | grep -iE "SSL certificate|alert|error" | head -5
        return 1
    fi

    # Layer 4: HTTP
    echo -n "Layer 4 [HTTP]: Requesting application payload from /api/status... "
    local http_check
    http_check="$($CURL_BIN -sS --connect-timeout 3 -i "https://$APP_DOMAIN:8443/api/status" 2>&1 || true)"
    local http_code
    http_code="$(echo "$http_check" | head -1 | tr -d '\r')"
    local x_backend
    x_backend="$(echo "$http_check" | grep -i "^X-Backend:" | tr -d '\r' | awk '{print $2}')"

    if echo "$http_code" | grep -q "200" && [ -n "$x_backend" ]; then
        echo -e "${GREEN}OK${RESET} (HTTP 200 OK | Backend: $x_backend)"
    else
        echo -e "${RED}FAILED${RESET}"
        log_fail "HTTP Layer Failure: Expected 200 OK with X-Backend header."
        echo "Raw response: $(echo "$http_check" | head -3)"
        return 1
    fi

    echo ""
    log_pass "All layers (DNS -> TCP -> TLS -> HTTP) verified successfully: PASS"
    return 0
}

# ------------------------------------------------------------------------------
# Dispatcher
# ------------------------------------------------------------------------------
TARGET="${1:-check}"

case "$TARGET" in
    lan)
        test_lan
        ;;
    dns)
        test_dns
        ;;
    backends)
        test_backends
        ;;
    lb)
        test_lb
        ;;
    tls)
        test_tls
        ;;
    http)
        test_http
        ;;
    cache)
        test_cache
        ;;
    check)
        test_check
        ;;
    all)
        test_lan || true
        test_dns || true
        test_backends || true
        test_lb || true
        test_tls || true
        test_http || true
        test_cache || true
        test_check || true
        ;;
    *)
        echo "Usage: $0 {lan|dns|backends|lb|tls|http|cache|check|all}"
        exit 1
        ;;
esac
