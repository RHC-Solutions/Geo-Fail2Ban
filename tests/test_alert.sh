#!/bin/bash
#
# Geo-Fail2Ban Test Script
# Validates all components after deployment.
#
# Usage:  sudo bash tests/test_alert.sh [--live]
#
#   Standalone health check — run it any time. It sends one Telegram "test
#   alert" (the same one install.sh fires at the end) so you can confirm
#   delivery, and validates components, config, firewall, jails and APIs.
#
#   --live   also run an end-to-end permanent-ban test: appends a TEST-NET IP
#            to /var/log/abuseipdb.log, verifies the abuseipdb jail bans it,
#            then unbans and cleans up. Sends 2 more Telegram alerts.
#

# NOTE: no 'set -e' here on purpose - failed checks are counted, not fatal.

LIVE=0
[ "${1:-}" = "--live" ] && LIVE=1

# Install directory (matches install.sh; override with INSTALL_DIR=...)
INSTALL_DIR="${INSTALL_DIR:-/opt/geo-fail2ban}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test results
PASSED=0
FAILED=0

# Helper functions
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

test_pass() { echo -e "${GREEN}✓ $1${NC}"; PASSED=$((PASSED+1)); }
test_fail() { echo -e "${RED}✗ $1${NC}"; FAILED=$((FAILED+1)); }
test_info() { echo -e "${CYAN}ℹ $1${NC}"; }
test_warn() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

print_header "Geo-Fail2Ban System Test"

# ========== Section 1: System Components ==========
print_header "1. System Components"

if systemctl is-active --quiet fail2ban; then
    test_pass "Fail2Ban service is running"
else
    test_fail "Fail2Ban service is not running"
fi

for f in "$INSTALL_DIR/telegram_alert.py" "$INSTALL_DIR/abuseipdb_blocker.py"; do
    if [ -f "$f" ]; then
        test_pass "$(basename "$f") exists"
    else
        test_fail "$(basename "$f") not found"
    fi
done

for f in /etc/fail2ban/jail.local \
         /etc/fail2ban/jail.d/abuseipdb.conf \
         /etc/fail2ban/filter.d/abuseipdb.conf \
         /etc/fail2ban/action.d/telegram.conf; do
    if [ -f "$f" ]; then
        test_pass "$f exists"
    else
        test_fail "$f not found"
    fi
done

if [ -f /var/log/abuseipdb.log ]; then
    test_pass "/var/log/abuseipdb.log exists (permanent-ban escalation channel)"
else
    test_fail "/var/log/abuseipdb.log missing (abuseipdb jail cannot start without it)"
fi

# ========== Section 2: Configuration ==========
print_header "2. Configuration"

# Runtime config is /etc/geo-fail2ban.conf (installed from config/.env)
CONF=""
if [ -f /etc/geo-fail2ban.conf ]; then
    CONF=/etc/geo-fail2ban.conf
    test_pass "/etc/geo-fail2ban.conf exists (runtime config)"
    PERMS=$(stat -c %a /etc/geo-fail2ban.conf)
    if [ "$PERMS" = "600" ]; then
        test_pass "Config permissions are 600"
    else
        test_warn "Config permissions are $PERMS (fixing to 600)"
        chmod 600 /etc/geo-fail2ban.conf
    fi
elif [ -f config/.env ]; then
    CONF=config/.env
    test_warn "Using config/.env - run install.sh to install it to /etc/geo-fail2ban.conf"
else
    test_fail "No config found - cp config/.env.example config/.env, edit it, run install.sh"
fi

if [ -n "$CONF" ]; then
    for key in TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID IPINFO_API_TOKEN ABUSEIPDB_API_KEY; do
        if grep -q "^${key}=" "$CONF" && ! grep "^${key}=" "$CONF" | grep -q 'YOUR_.*_HERE'; then
            test_pass "$key configured"
        else
            test_fail "$key not configured (placeholder or missing)"
        fi
    done
fi

# ========== Section 3: Firewall (ipsets + rules) ==========
print_header "3. Firewall: ipsets and DROP rules"

if ipset list -t abuseipdb-blacklist > /dev/null 2>&1; then
    ENTRIES=$(ipset list -t abuseipdb-blacklist | awk '/Number of entries/{print $4}')
    test_pass "abuseipdb-blacklist ipset exists ($ENTRIES IPs permanently blocked)"
else
    test_fail "abuseipdb-blacklist ipset missing"
fi

if iptables -C INPUT -m set --match-set abuseipdb-blacklist src -j DROP 2>/dev/null; then
    test_pass "Blacklist DROP rule present in INPUT"
else
    test_fail "Blacklist DROP rule missing from INPUT"
fi

if systemctl is-enabled --quiet ipset-abuseipdb.service 2>/dev/null; then
    test_pass "ipset-abuseipdb.service enabled (survives reboot)"
else
    test_fail "ipset-abuseipdb.service not enabled - bans lost on reboot!"
fi

# Geoblock is optional (--skip-geo)
if ipset list -t geoblock > /dev/null 2>&1; then
    GENTRIES=$(ipset list -t geoblock | awk '/Number of entries/{print $4}')
    test_pass "geoblock ipset exists ($GENTRIES CIDRs)"
    if iptables -C INPUT -m set --match-set geoblock src -j DROP 2>/dev/null; then
        test_pass "Geoblock DROP rule present in INPUT"
    else
        test_fail "geoblock ipset is populated but its DROP rule is MISSING - blocking nothing"
    fi
    if systemctl is-enabled --quiet ipset-geo.service 2>/dev/null; then
        test_pass "ipset-geo.service enabled"
    else
        test_warn "ipset-geo.service not enabled"
    fi
else
    test_info "geoblock ipset not present (installed with --skip-geo?)"
fi

# ========== Section 4: Python Dependencies ==========
print_header "4. Python Dependencies"

if python3 -c "import requests" 2>/dev/null; then
    test_pass "requests module installed"
else
    test_fail "requests module not installed"
fi

for s in telegram_alert.py abuseipdb_blocker.py; do
    if python3 -m py_compile "$INSTALL_DIR/$s" 2>/dev/null; then
        test_pass "$s compiles"
    else
        test_fail "$s has syntax errors"
    fi
done

# ========== Section 5: Fail2Ban Jails ==========
print_header "5. Fail2Ban Jails"

if fail2ban-client status sshd > /dev/null 2>&1; then
    test_pass "sshd jail active (temporary bans)"
    fail2ban-client status sshd | grep -E 'Currently banned|Total banned' | sed 's/^/  /'
else
    test_fail "sshd jail not found"
fi

if fail2ban-client status abuseipdb > /dev/null 2>&1; then
    test_pass "abuseipdb jail active (PERMANENT bans, bantime = -1)"
    fail2ban-client status abuseipdb | grep -E 'Currently banned|Total banned' | sed 's/^/  /'
else
    test_fail "abuseipdb jail not found - permanent-ban escalation will not work"
fi

# ========== Section 6: API Connectivity ==========
print_header "6. API Connectivity Tests"

if [ -n "$CONF" ]; then
    # shellcheck disable=SC1090
    source "$CONF"

    test_info "Testing ipinfo.io API with test IP 8.8.8.8..."
    GEOIP_RESP=$(curl -s --max-time 10 "https://ipinfo.io/8.8.8.8?token=$IPINFO_API_TOKEN" 2>/dev/null || echo "{}")
    if echo "$GEOIP_RESP" | grep -q '"country"'; then
        test_pass "ipinfo.io API working"
        echo "  Country: $(echo "$GEOIP_RESP" | grep -o '"country":"[^"]*' | cut -d'"' -f4)"
    else
        test_fail "ipinfo.io API test failed (check token)"
    fi

    test_info "Testing AbuseIPDB API with test IP 8.8.8.8..."
    ABUSE_RESP=$(curl -s --max-time 10 -G https://api.abuseipdb.com/api/v2/check \
        -d "ipAddress=8.8.8.8" \
        -d "maxAgeInDays=90" \
        -H "Key: $ABUSEIPDB_API_KEY" \
        -H "Accept: application/json" 2>/dev/null || echo "{}")
    if echo "$ABUSE_RESP" | grep -q '"abuseConfidenceScore"'; then
        test_pass "AbuseIPDB API working"
    else
        test_fail "AbuseIPDB API test failed (check API key)"
    fi

    test_info "Testing Telegram Bot..."
    TELEGRAM_TEST=$(curl -s --max-time 10 -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getMe" 2>/dev/null || echo "{}")
    if echo "$TELEGRAM_TEST" | grep -q '"ok":true'; then
        BOT_NAME=$(echo "$TELEGRAM_TEST" | grep -o '"first_name":"[^"]*' | cut -d'"' -f4)
        test_pass "Telegram Bot token is valid (bot: $BOT_NAME)"
    else
        test_fail "Telegram Bot token is invalid"
    fi

    # Actually deliver a test alert to the chat (same 'test' action install.sh
    # runs). Prefer the installed script; fall back to a direct sendMessage so
    # this works even before install / regardless of config location.
    test_info "Sending a Telegram test alert (check your chat)..."
    if [ -f /etc/geo-fail2ban.conf ] && [ -f "$INSTALL_DIR/telegram_alert.py" ] \
       && python3 "$INSTALL_DIR/telegram_alert.py" test >/dev/null 2>&1; then
        test_pass "Telegram test alert sent via telegram_alert.py — check your chat"
    elif [ -n "${TELEGRAM_CHAT_ID:-}" ] && \
         curl -s --max-time 10 "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d "chat_id=$TELEGRAM_CHAT_ID" \
            --data-urlencode "text=✅ Geo-Fail2Ban test alert — $(hostname -f 2>/dev/null || hostname) $(date '+%F %T')" \
            2>/dev/null | grep -q '"ok":true'; then
        test_pass "Telegram test alert sent — check your chat"
    else
        test_fail "Could not send Telegram test alert (check TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID)"
    fi
else
    test_warn "No config found - skipping API tests"
fi

# ========== Section 7: Cron Jobs ==========
print_header "7. Cron Jobs"

if [ -f /etc/cron.d/fail2ban-abuseipdb ]; then
    if grep -qE '^[0-9]+ \* \* \* \*' /etc/cron.d/fail2ban-abuseipdb; then
        test_fail "Blacklist cron runs HOURLY - the free API allows 5/day, switch to daily!"
    else
        test_pass "Daily blacklist import cron configured"
    fi
    grep -v '^#' /etc/cron.d/fail2ban-abuseipdb | grep -v '^$' | sed 's/^/  /'
else
    test_fail "Cron job /etc/cron.d/fail2ban-abuseipdb not configured"
fi

# ========== Section 8: Live End-to-End Test (optional) ==========
if [ "$LIVE" -eq 1 ]; then
    print_header "8. LIVE Test: permanent-ban pipeline (TEST-NET IP)"
    TEST_IP="192.0.2.123"   # RFC 5737 TEST-NET-1, never routed
    test_info "Appending $TEST_IP to /var/log/abuseipdb.log (2 Telegram alerts expected)..."
    echo "$TEST_IP" >> /var/log/abuseipdb.log
    sleep 10
    if fail2ban-client status abuseipdb | grep -q "$TEST_IP"; then
        test_pass "abuseipdb jail permanently banned $TEST_IP from log append"
        fail2ban-client set abuseipdb unbanip "$TEST_IP" > /dev/null 2>&1
        test_info "Test IP unbanned and cleaned up"
    else
        test_fail "abuseipdb jail did NOT pick up $TEST_IP (check fail2ban backend/logs)"
    fi
fi

# ========== Summary ==========
print_header "Test Summary"

TOTAL=$((PASSED + FAILED))
PERCENT=$((PASSED * 100 / (TOTAL > 0 ? TOTAL : 1)))

echo -e "${GREEN}Passed:${NC} $PASSED/$TOTAL"
echo -e "${RED}Failed:${NC} $FAILED/$TOTAL"
echo -e "${CYAN}Success Rate:${NC} $PERCENT%"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ALL TESTS PASSED! System is ready 🎉${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    exit 0
else
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Some tests failed. Please review the output above.${NC}"
    echo -e "${YELLOW}  See docs/TROUBLESHOOTING.md for help.${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    exit 1
fi
