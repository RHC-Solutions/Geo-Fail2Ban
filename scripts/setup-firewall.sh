#!/bin/bash
#
# Firewall Whitelist Setup Script
# Restricts SSH (22) and DNS (53) to whitelisted IPs only.
#
# Works with firewalld, ufw, or raw iptables — whichever is active
# (auto-detected via scripts/firewall-lib.sh).
#

set -e
cd "$(dirname "$0")/.."   # repo root, so config/ and scripts/ resolve

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header()  { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Load the firewall backend abstraction
if [ ! -f scripts/firewall-lib.sh ]; then
    print_error "scripts/firewall-lib.sh not found"
    exit 1
fi
# shellcheck source=firewall-lib.sh
. scripts/firewall-lib.sh

print_header "Firewall Whitelist Configuration"

BACKEND="$(fw_detect)"
if [ "$BACKEND" = "none" ]; then
    print_error "No supported firewall found (need firewalld, ufw, or iptables)."
    exit 1
fi
echo "Detected firewall backend: $BACKEND"

# Check if whitelist file exists. It is git-ignored (it holds your real IPs),
# so on a fresh clone create it from the template and ask the user to edit it.
if [ ! -f "config/whitelist.txt" ]; then
    if [ -f "config/whitelist.txt.example" ]; then
        cp config/whitelist.txt.example config/whitelist.txt
        print_error "Whitelist not configured yet."
        echo "Created config/whitelist.txt from the template."
        echo "Edit it and add your trusted IPs, then re-run this script:"
        echo "  sudo nano config/whitelist.txt"
        exit 1
    fi
    print_error "Whitelist file not found: config/whitelist.txt"
    exit 1
fi

# Read whitelist (skip comments and blank lines)
readarray -t IPS < <(grep -vE '^[[:space:]]*#' config/whitelist.txt | grep -vE '^[[:space:]]*$')

if [ ${#IPS[@]} -eq 0 ]; then
    print_error "No IPs found in config/whitelist.txt"
    echo "Edit config/whitelist.txt and add your trusted IPs"
    exit 1
fi

echo "Found ${#IPS[@]} IP(s) to whitelist:"
for ip in "${IPS[@]}"; do
    echo "  • $ip"
done
echo ""
print_warning "This restricts SSH (22) and DNS (53) to the IPs above ONLY."
print_warning "The IP of your current SSH session is added automatically to avoid lockout."
echo ""

# Apply via the detected backend
echo "Applying whitelist via $BACKEND ..."
fw_apply_whitelist "${IPS[@]}"
print_success "SSH and DNS are now restricted to whitelisted IPs only!"

# Show resulting rules
print_header "Active Rules"
case "$BACKEND" in
    ufw)       ufw status | grep -E '22|53' || echo "No matching rules found" ;;
    firewalld) firewall-cmd --list-rich-rules; echo "(default zone: $(firewall-cmd --get-default-zone))" ;;
    iptables)  iptables -S INPUT | grep -E 'dpt:22|dpt:53|--dport 22|--dport 53|lo |ESTABLISHED' || echo "No matching rules found" ;;
esac
echo ""
