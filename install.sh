#!/bin/bash
#
# Geo-Fail2Ban Installation Script
# Automated setup for Telegram alerts, GeoIP, and AbuseIPDB integration
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
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

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run as root"
    echo "Please run: sudo bash install.sh"
    exit 1
fi

print_header "Geo-Fail2Ban Installation"

# Step 1: Install dependencies
print_info "Installing dependencies..."
apt-get update > /dev/null 2>&1
apt-get install -y fail2ban python3-pip python3-geoip2 curl git > /dev/null 2>&1
pip3 install requests --break-system-packages > /dev/null 2>&1
print_success "Dependencies installed"

# Step 2: Create directories
print_info "Creating directories..."
mkdir -p /opt/fail2ban-scripts
mkdir -p /var/log/fail2ban-geo
print_success "Directories created"

# Step 3: Copy scripts
print_info "Installing scripts..."
cp scripts/telegram_alert.py /opt/fail2ban-scripts/
cp scripts/abuseipdb_blocker.py /opt/fail2ban-scripts/
chmod +x /opt/fail2ban-scripts/*.py
print_success "Scripts installed"

# Step 4: Copy configurations
print_info "Installing configurations..."
cp config/jail.local /etc/fail2ban/jail.local
cp config/telegram.conf /etc/fail2ban/action.d/telegram.conf
print_success "Configurations installed"

# Step 5: Setup cron jobs
print_info "Setting up cron jobs..."
cat > /etc/cron.d/fail2ban-abuseipdb << 'EOF'
# Run AbuseIPDB blocker every hour
0 * * * * root /opt/fail2ban-scripts/abuseipdb_blocker.py >> /var/log/fail2ban-abuseipdb.log 2>&1

# Update GeoIP database weekly (if available)
0 2 * * 0 root python3 -m geoip2.scripts.update_geoip2 >> /var/log/fail2ban-geoip.log 2>&1
EOF
chmod 644 /etc/cron.d/fail2ban-abuseipdb
print_success "Cron jobs configured"

# Step 6: Check for .env file
if [ ! -f "config/.env" ]; then
    print_error "API credentials not configured!"
    echo ""
    echo "Please configure your API keys:"
    echo "  1. Copy the template:"
    echo "     cp config/.env.example config/.env"
    echo ""
    echo "  2. Edit the file:"
    echo "     sudo nano config/.env"
    echo ""
    echo "  3. Add your API keys:"
    echo "     - Telegram Bot Token (from @BotFather)"
    echo "     - Telegram Chat ID"
    echo "     - ipinfo.io API token"
    echo "     - AbuseIPDB API key"
    echo ""
    exit 1
fi

# Step 7: Restart fail2ban
print_info "Restarting Fail2Ban service..."
systemctl restart fail2ban
sleep 2
print_success "Fail2Ban restarted"

# Step 8: Verify installation
print_header "Verification"

if systemctl is-active --quiet fail2ban; then
    print_success "Fail2Ban service is running"
else
    print_error "Fail2Ban service is not running"
    exit 1
fi

if [ -f "/opt/fail2ban-scripts/telegram_alert.py" ]; then
    print_success "Alert script installed"
else
    print_error "Alert script not found"
    exit 1
fi

if [ -f "/etc/fail2ban/jail.local" ]; then
    print_success "Jail configuration installed"
else
    print_error "Jail configuration not found"
    exit 1
fi

print_header "Installation Complete! 🎉"

echo "Next steps:"
echo ""
echo "1. Configure API credentials (if not already done):"
echo "   sudo nano config/.env"
echo ""
echo "2. Apply firewall whitelist (optional):"
echo "   sudo bash scripts/setup-firewall.sh"
echo ""
echo "3. Test the system:"
echo "   sudo bash tests/test_alert.sh"
echo ""
echo "4. Check status:"
echo "   sudo fail2ban-client status sshd"
echo "   sudo tail -f /var/log/fail2ban.log"
echo ""
echo "5. View documentation:"
echo "   cat docs/CONFIGURATION.md"
echo ""
print_success "Geo-Fail2Ban is now protecting your server!"
echo ""
