#!/bin/bash
#
# Geo-Fail2Ban Uninstallation Script
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Options
ASSUME_YES=0
KEEP_CONFIG=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes)      ASSUME_YES=1 ;;
        --keep-config) KEEP_CONFIG=1 ;;
        *) echo "Unknown option: $arg"; echo "Usage: $0 [--yes] [--keep-config]"; exit 1 ;;
    esac
done

# Install directory to remove (matches install.sh; override with INSTALL_DIR=...)
INSTALL_DIR="${INSTALL_DIR:-/opt/geo-fail2ban}"
LEGACY_DIR="/opt/fail2ban-scripts"

# Firewall backend helpers (removes rules from firewalld/ufw/iptables).
# Best-effort: falls back to raw iptables below if the lib isn't present.
[ -f "$(dirname "$0")/firewall-lib.sh" ] && . "$(dirname "$0")/firewall-lib.sh"

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}✗ This script must be run as root${NC}"
    exit 1
fi

print_header "Geo-Fail2Ban Uninstallation"

print_warning "This will remove Geo-Fail2Ban components from your system"
if [ "$ASSUME_YES" -ne 1 ]; then
    read -p "Are you sure? Type 'yes' to continue: " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Uninstallation cancelled"
        exit 1
    fi
fi

print_warning "Stopping Fail2Ban service..."
systemctl stop fail2ban || true
print_success "Service stopped"

print_warning "Removing configuration files..."
rm -f /etc/fail2ban/jail.local
rm -f /etc/fail2ban/jail.d/abuseipdb.conf
rm -f /etc/fail2ban/filter.d/abuseipdb.conf
rm -f /etc/fail2ban/action.d/telegram.conf
if [ "$KEEP_CONFIG" -eq 1 ]; then
    print_warning "Keeping /etc/geo-fail2ban.conf (credentials preserved)"
else
    rm -f /etc/geo-fail2ban.conf
fi
print_success "Configuration files removed"

print_warning "Removing scripts..."
rm -rf "$INSTALL_DIR"
if [ "$LEGACY_DIR" != "$INSTALL_DIR" ]; then
    rm -rf "$LEGACY_DIR"
fi
print_success "Scripts removed ($INSTALL_DIR)"

print_warning "Removing cron jobs..."
rm -f /etc/cron.d/fail2ban-abuseipdb
rm -f /etc/cron.d/ipset-geo
print_success "Cron jobs removed"

print_warning "Removing ipsets, firewall rules and persistence units..."
systemctl disable --now ipset-abuseipdb.service ipset-geo.service 2>/dev/null || true
rm -f /etc/systemd/system/ipset-abuseipdb.service /etc/systemd/system/ipset-geo.service
systemctl daemon-reload
if command -v fw_unblock_set >/dev/null 2>&1; then
    fw_unblock_set abuseipdb-blacklist
    fw_unblock_set geoblock
else
    iptables -D INPUT -m set --match-set abuseipdb-blacklist src -j DROP 2>/dev/null || true
    iptables -D INPUT -m set --match-set geoblock src -j DROP 2>/dev/null || true
fi
ipset destroy abuseipdb-blacklist 2>/dev/null || true
ipset destroy geoblock 2>/dev/null || true
rm -f /etc/ipset-abuseipdb.conf
rm -rf /etc/ipset-geo
print_success "Ipsets and firewall rules removed"

print_warning "Restarting Fail2Ban..."
systemctl restart fail2ban 2>/dev/null || true
print_success "Fail2Ban restarted"

print_header "Uninstallation Complete"
echo -e "${GREEN}Geo-Fail2Ban has been removed from your system${NC}"
echo ""
echo "To restore default Fail2Ban:"
echo "  sudo systemctl restart fail2ban"
echo ""
