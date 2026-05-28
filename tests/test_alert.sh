#!/bin/bash
#
# Geo-Fail2Ban Test Script
# Tests all components and APIs
#

set -e

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

test_pass() {
    echo -e "${GREEN}✓ $1${NC}"
    ((PASSED++))
}

test_fail() {
    echo -e "${RED}✗ $1${NC}"
    ((FAILED++))
}

test_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

test_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

print_header "Geo-Fail2Ban System Test"

# ========== Section 1: System Components ==========
print_header "1. System Components"

# Test fail2ban
if systemctl is-active --quiet fail2ban; then
    test_pass "Fail2Ban service is running"
else
    test_fail "Fail2Ban service is not running"
fi

# Test scripts exist
if [ -f "/opt/fail2ban-scripts/telegram_alert.py" ]; then
    test_pass "Telegram alert script exists"
else
    test_fail "Telegram alert script not found"
fi

if [ -f "/opt/fail2ban-scripts/abuseipdb_blocker.py" ]; then
    test_pass "AbuseIPDB blocker script exists"
else
    test_fail "AbuseIPDB blocker script not found"
fi

# Test configurations
if [ -f "/etc/fail2ban/jail.local" ]; then
    test_pass "Jail configuration exists"
else
    test_fail "Jail configuration not found"
fi

if [ -f "/etc/fail2ban/action.d/telegram.conf" ]; then
    test_pass "Telegram action exists"
else
    test_fail "Telegram action not found"
fi

# ========== Section 2: Configuration Files ==========
print_header "2. Configuration Files"

if [ -f "config/.env" ]; then
    test_pass ".env file exists"
    
    # Check for required variables
    if grep -q "TELEGRAM_BOT_TOKEN" config/.env; then
        test_pass "TELEGRAM_BOT_TOKEN configured"
    else
        test_fail "TELEGRAM_BOT_TOKEN not configured"
    fi
    
    if grep -q "TELEGRAM_CHAT_ID" config/.env; then
        test_pass "TELEGRAM_CHAT_ID configured"
    else
        test_fail "TELEGRAM_CHAT_ID not configured"
    fi
    
    if grep -q "IPINFO_API_TOKEN" config/.env; then
        test_pass "IPINFO_API_TOKEN configured"
    else
        test_fail "IPINFO_API_TOKEN not configured"
    fi
    
    if grep -q "ABUSEIPDB_API_KEY" config/.env; then
        test_pass "ABUSEIPDB_API_KEY configured"
    else
        test_fail "ABUSEIPDB_API_KEY not configured"
    fi
else
    test_fail ".env file not found - create with: cp config/.env.example config/.env"
fi

# ========== Section 3: Network Connectivity ==========
print_header "3. Network Connectivity"

# Test Telegram API
if curl -s -I https://api.telegram.org > /dev/null 2>&1; then
    test_pass "Can reach Telegram API"
else
    test_fail "Cannot reach Telegram API"
fi

# Test ipinfo.io API
if curl -s -I https://ipinfo.io > /dev/null 2>&1; then
    test_pass "Can reach ipinfo.io API"
else
    test_fail "Cannot reach ipinfo.io API"
fi

# Test AbuseIPDB API
if curl -s -I https://api.abuseipdb.com > /dev/null 2>&1; then
    test_pass "Can reach AbuseIPDB API"
else
    test_fail "Cannot reach AbuseIPDB API"
fi

# ========== Section 4: Python Dependencies ==========
print_header "4. Python Dependencies"

# Check Python modules
if python3 -c "import requests" 2>/dev/null; then
    test_pass "requests module installed"
else
    test_fail "requests module not installed"
fi

if python3 -c "import geoip2" 2>/dev/null; then
    test_pass "geoip2 module installed"
else
    test_fail "geoip2 module not installed"
fi

# ========== Section 5: Fail2Ban Configuration ==========
print_header "5. Fail2Ban Configuration"

# Check if sshd jail exists
if sudo fail2ban-client status sshd > /dev/null 2>&1; then
    test_pass "SSH jail is configured"
    
    # Get jail stats
    STATUS=$(sudo fail2ban-client status sshd)
    echo "$STATUS" | head -10 | sed 's/^/  /'
else
    test_fail "SSH jail not found"
fi

# ========== Section 6: API Tests ==========
print_header "6. API Connectivity Tests"

# Load .env if it exists
if [ -f "config/.env" ]; then
    source config/.env
    
    # Test ipinfo.io
    test_info "Testing ipinfo.io API with test IP 8.8.8.8..."
    GEOIP_RESP=$(curl -s "https://ipinfo.io/8.8.8.8?token=$IPINFO_API_TOKEN" 2>/dev/null || echo "{}")
    if echo "$GEOIP_RESP" | grep -q '"country"'; then
        test_pass "ipinfo.io API working"
        echo "  Country: $(echo "$GEOIP_RESP" | grep -o '"country":"[^"]*' | cut -d'"' -f4)"
        echo "  City: $(echo "$GEOIP_RESP" | grep -o '"city":"[^"]*' | cut -d'"' -f4)"
        echo "  ISP: $(echo "$GEOIP_RESP" | grep -o '"org":"[^"]*' | cut -d'"' -f4)"
    else
        test_fail "ipinfo.io API test failed (check token)"
    fi
    
    # Test AbuseIPDB
    test_info "Testing AbuseIPDB API with test IP 8.8.8.8..."
    ABUSE_RESP=$(curl -s -G https://api.abuseipdb.com/api/v2/check \
        -d "ipAddress=8.8.8.8" \
        -d "maxAgeInDays=90" \
        -H "Key: $ABUSEIPDB_API_KEY" \
        -H "Accept: application/json" 2>/dev/null || echo "{}")
    
    if echo "$ABUSE_RESP" | grep -q '"abuseConfidenceScore"'; then
        test_pass "AbuseIPDB API working"
        SCORE=$(echo "$ABUSE_RESP" | grep -o '"abuseConfidenceScore":[0-9]*' | cut -d':' -f2)
        echo "  Abuse Score: $SCORE%"
    else
        test_fail "AbuseIPDB API test failed (check API key)"
    fi
    
    # Test Telegram
    test_info "Testing Telegram Bot..."
    TELEGRAM_TEST=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getMe" 2>/dev/null || echo "{}")
    
    if echo "$TELEGRAM_TEST" | grep -q '"ok":true'; then
        test_pass "Telegram Bot token is valid"
        BOT_NAME=$(echo "$TELEGRAM_TEST" | grep -o '"first_name":"[^"]*' | cut -d'"' -f4)
        echo "  Bot Name: $BOT_NAME"
    else
        test_fail "Telegram Bot token is invalid"
    fi
else
    test_warn ".env file not found - skipping API tests"
fi

# ========== Section 7: Cron Jobs ==========
print_header "7. Cron Jobs"

if [ -f "/etc/cron.d/fail2ban-abuseipdb" ]; then
    test_pass "Cron jobs configured"
    echo ""
    echo "Scheduled tasks:"
    cat /etc/cron.d/fail2ban-abuseipdb | grep -v "^#" | grep -v "^$" | sed 's/^/  /'
else
    test_fail "Cron jobs not configured"
fi

# ========== Section 8: Permissions ==========
print_header "8. File Permissions"

if [ -x "/opt/fail2ban-scripts/telegram_alert.py" ]; then
    test_pass "telegram_alert.py is executable"
else
    test_warn "telegram_alert.py is not executable (attempting fix)"
    chmod +x /opt/fail2ban-scripts/telegram_alert.py
fi

if [ -x "/opt/fail2ban-scripts/abuseipdb_blocker.py" ]; then
    test_pass "abuseipdb_blocker.py is executable"
else
    test_warn "abuseipdb_blocker.py is not executable (attempting fix)"
    chmod +x /opt/fail2ban-scripts/abuseipdb_blocker.py
fi

# ========== Section 9: Logs ==========
print_header "9. Log Files"

if [ -d "/var/log/fail2ban-geo" ]; then
    test_pass "Log directory exists"
else
    test_warn "Log directory not found (creating)"
    mkdir -p /var/log/fail2ban-geo
    chmod 755 /var/log/fail2ban-geo
fi

if [ -f "/var/log/fail2ban.log" ]; then
    test_pass "Fail2Ban log exists"
    RECENT=$(sudo tail -3 /var/log/fail2ban.log)
    echo "  Recent entries:"
    echo "$RECENT" | sed 's/^/    /'
else
    test_warn "Fail2Ban log not found"
fi

# ========== Summary ==========
print_header "Test Summary"

TOTAL=$((PASSED + FAILED))
PERCENT=$((PASSED * 100 / TOTAL))

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
