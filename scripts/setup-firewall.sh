#!/bin/bash
#
# Firewall Whitelist Setup Script
# Restricts SSH (22) and DNS (53) to whitelisted IPs only
#

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check root
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run as root"
    exit 1
fi

# Check UFW
if ! command -v ufw &> /dev/null; then
    print_error "UFW not found. Install with: sudo apt-get install ufw"
    exit 1
fi

print_header "Firewall Whitelist Configuration"

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

# Read whitelist
readarray -t IPS < <(grep -v '^#' config/whitelist.txt | grep -v '^$')

if [ ${#IPS[@]} -eq 0 ]; then
    print_error "No IPs found in config/whitelist.txt"
    echo "Edit config/whitelist.txt and add your trusted IPs"
    exit 1
fi

echo "Found ${#IPS[@]} IPs to whitelist:"
for ip in "${IPS[@]}"; do
    echo "  • $ip"
done
echo ""

# Add SSH rules
echo "Adding SSH (22) rules..."
for ip in "${IPS[@]}"; do
    ufw allow from "$ip" to any port 22 proto tcp comment "SSH from $ip" 2>/dev/null || true
done
print_success "SSH rules added"

# Add DNS rules
echo "Adding DNS (53) rules..."
for ip in "${IPS[@]}"; do
    ufw allow from "$ip" to any port 53 proto tcp comment "DNS TCP from $ip" 2>/dev/null || true
    ufw allow from "$ip" to any port 53 proto udp comment "DNS UDP from $ip" 2>/dev/null || true
done
print_success "DNS rules added"

# Add deny rules
echo "Adding DENY rules for all others..."
ufw deny 22/tcp comment "SSH - Deny all others" 2>/dev/null || true
ufw deny 22 comment "SSH - Deny all others" 2>/dev/null || true
ufw deny 53/tcp comment "DNS - Deny all others" 2>/dev/null || true
ufw deny 53/udp comment "DNS - Deny all others" 2>/dev/null || true
print_success "DENY rules added"

# Reload UFW
ufw reload 2>/dev/null || true

print_header "Configuration Complete"
echo "Firewall rules:"
ufw status | grep -E "22|53" || echo "No rules found"

echo ""
print_success "SSH and DNS are now restricted to whitelisted IPs only!"
