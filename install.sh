#!/bin/bash
#
# Geo-Fail2Ban Installation Script
# Telegram alerts, GeoIP enrichment, AbuseIPDB permanent bans, country geoblock.
#
# Usage:  sudo bash install.sh [--skip-geo]
#   --skip-geo   don't download country zone files / enable the geoblock ipset
#

set -e
cd "$(dirname "$0")"

SKIP_GEO=0
[ "${1:-}" = "--skip-geo" ] && SKIP_GEO=1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ $1${NC}"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    echo "Please run: sudo bash install.sh"
    exit 1
fi

print_header "Geo-Fail2Ban Installation"

# Step 1: Configuration file (do this FIRST - everything depends on it)
if [ ! -f /etc/geo-fail2ban.conf ]; then
    if [ -f config/.env ]; then
        cp config/.env /etc/geo-fail2ban.conf
        print_success "Installed config/.env -> /etc/geo-fail2ban.conf"
    else
        print_error "API credentials not configured!"
        echo ""
        echo "  1. Copy the template:   cp config/.env.example config/.env"
        echo "  2. Edit it:             nano config/.env"
        echo "     (Telegram bot token + chat ID, ipinfo.io token, AbuseIPDB key)"
        echo "  3. Re-run:              sudo bash install.sh"
        echo ""
        exit 1
    fi
else
    print_info "/etc/geo-fail2ban.conf already exists - keeping it"
fi
chmod 600 /etc/geo-fail2ban.conf

if grep -q 'YOUR_BOT_TOKEN_HERE' /etc/geo-fail2ban.conf; then
    print_error "/etc/geo-fail2ban.conf still contains placeholder values - edit it first"
    exit 1
fi

# Step 2: Install dependencies
print_info "Installing dependencies..."
apt-get update > /dev/null 2>&1
apt-get install -y fail2ban ipset python3-requests curl > /dev/null 2>&1 \
    || apt-get install -y fail2ban ipset python3-pip curl > /dev/null 2>&1
python3 -c 'import requests' 2>/dev/null || pip3 install requests --break-system-packages > /dev/null 2>&1
print_success "Dependencies installed"

# Step 3: Scripts
print_info "Installing scripts..."
mkdir -p /opt/fail2ban-scripts
cp scripts/telegram_alert.py scripts/abuseipdb_blocker.py /opt/fail2ban-scripts/
chmod +x /opt/fail2ban-scripts/*.py
print_success "Scripts installed to /opt/fail2ban-scripts"

# Step 4: Fail2ban configuration
print_info "Installing fail2ban configuration..."
[ -f /etc/fail2ban/jail.local ] && cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak
cp fail2ban/jail.local /etc/fail2ban/jail.local
cp fail2ban/jail.d/abuseipdb.conf /etc/fail2ban/jail.d/abuseipdb.conf
cp fail2ban/filter.d/abuseipdb.conf /etc/fail2ban/filter.d/abuseipdb.conf
cp fail2ban/action.d/telegram.conf /etc/fail2ban/action.d/telegram.conf
touch /var/log/abuseipdb.log
print_success "Fail2ban jails installed (sshd 24h + abuseipdb permanent)"

# Step 5: AbuseIPDB blacklist ipset (permanent, add-only)
print_info "Setting up AbuseIPDB blacklist ipset..."
ipset create abuseipdb-blacklist hash:ip family inet hashsize 16384 maxelem 500000 -exist
iptables -C INPUT -m set --match-set abuseipdb-blacklist src -j DROP 2>/dev/null \
    || iptables -I INPUT 1 -m set --match-set abuseipdb-blacklist src -j DROP
cp systemd/ipset-abuseipdb.service /etc/systemd/system/
print_success "AbuseIPDB blacklist ipset + DROP rule active"

# Step 6: Geoblock (optional)
if [ "$SKIP_GEO" -eq 0 ]; then
    print_info "Setting up country geoblock..."
    mkdir -p /etc/ipset-geo/bin
    cp ipset-geo/update.sh /etc/ipset-geo/bin/update.sh
    chmod +x /etc/ipset-geo/bin/update.sh
    cp systemd/ipset-geo.service /etc/systemd/system/
    cp cron/ipset-geo /etc/cron.d/ipset-geo
    print_info "Downloading country zone files (this can take a minute)..."
    /etc/ipset-geo/bin/update.sh || print_error "geoblock refresh failed (will retry via weekly cron)"
    iptables -C INPUT -m set --match-set geoblock src -j DROP 2>/dev/null \
        || iptables -I INPUT 1 -m set --match-set geoblock src -j DROP
    print_success "Geoblock active (countries from GEOBLOCK_COUNTRIES in /etc/geo-fail2ban.conf)"
else
    print_info "Skipping geoblock (--skip-geo)"
fi

# Step 7: Persistence + cron
print_info "Enabling boot persistence and cron jobs..."
systemctl daemon-reload
systemctl enable ipset-abuseipdb.service > /dev/null 2>&1
[ "$SKIP_GEO" -eq 0 ] && systemctl enable ipset-geo.service > /dev/null 2>&1
cp cron/fail2ban-abuseipdb /etc/cron.d/fail2ban-abuseipdb
chmod 644 /etc/cron.d/*
print_success "Boot restore services enabled, daily blacklist cron installed"

# Step 8: First blacklist fetch (best effort - free API allows 5/day)
print_info "Fetching AbuseIPDB blacklist (may hit daily rate limit)..."
/opt/fail2ban-scripts/abuseipdb_blocker.py 2>&1 | tail -2 || true
ipset save abuseipdb-blacklist > /etc/ipset-abuseipdb.conf

# Step 9: Restart fail2ban
print_info "Restarting Fail2Ban service..."
systemctl restart fail2ban
sleep 2
print_success "Fail2Ban restarted"

# Step 10: Verify installation
print_header "Verification"

FAIL=0
systemctl is-active --quiet fail2ban \
    && print_success "Fail2Ban service is running" \
    || { print_error "Fail2Ban service is not running"; FAIL=1; }
fail2ban-client status sshd > /dev/null 2>&1 \
    && print_success "sshd jail active (24h bans + Telegram alerts)" \
    || { print_error "sshd jail not active"; FAIL=1; }
fail2ban-client status abuseipdb > /dev/null 2>&1 \
    && print_success "abuseipdb jail active (PERMANENT bans, score >= threshold)" \
    || { print_error "abuseipdb jail not active"; FAIL=1; }
iptables -C INPUT -m set --match-set abuseipdb-blacklist src -j DROP 2>/dev/null \
    && print_success "Blacklist DROP rule present ($(ipset list -t abuseipdb-blacklist | awk '/Number of entries/{print $4}') IPs)" \
    || { print_error "Blacklist DROP rule missing"; FAIL=1; }
[ "$FAIL" -ne 0 ] && exit 1

print_header "Installation Complete! 🎉"

echo "How it works:"
echo "  • Failed SSH logins -> 24h ban + Telegram alert (BANNED/UNBANNED headers)"
echo "  • Banned IP with AbuseIPDB score >= threshold -> escalated to PERMANENT ban"
echo "  • AbuseIPDB blacklist imported daily into an add-only ipset (never expires)"
echo "  • Everything survives reboot (systemd restore units)"
echo ""
echo "Useful commands:"
echo "  sudo fail2ban-client status sshd"
echo "  sudo fail2ban-client status abuseipdb"
echo "  sudo ipset list -t abuseipdb-blacklist"
echo "  sudo bash tests/test_alert.sh"
echo ""
print_success "Geo-Fail2Ban is now protecting your server!"
echo ""
