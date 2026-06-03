# Installation Guide

## System Requirements

- **OS**: any systemd-based Linux (Debian/Ubuntu, RHEL/Fedora/Rocky/Alma, openSUSE, Arch, Alpine)
- **Firewall**: firewalld, ufw, or iptables (auto-detected; installed if missing)
- **Privileges**: Root or sudo access
- **Network**: Outbound HTTPS access for API calls

## Quick Start

```bash
# Clone the repository
git clone git@github.com:RHC-Solutions/Geo-Fail2Ban.git
cd Geo-Fail2Ban

# Run installation
sudo bash install.sh

# Configure API credentials
sudo cp config/.env.example config/.env
sudo nano config/.env

# Edit with your API keys (see API_SETUP.md for details)
```

## Step-by-Step Installation

### 1. Install Dependencies

```bash
sudo apt-get update
sudo apt-get install -y fail2ban python3-pip python3-geoip2 curl git
sudo pip3 install requests --break-system-packages
```

### 2. Create Required Directories

```bash
sudo mkdir -p /opt/geo-fail2ban
sudo mkdir -p /var/log/fail2ban-geo
```

### 3. Install Scripts

```bash
sudo cp scripts/telegram_alert.py /opt/geo-fail2ban/
sudo cp scripts/abuseipdb_blocker.py /opt/geo-fail2ban/
sudo chmod +x /opt/geo-fail2ban/*.py
```

### 4. Install Configurations

```bash
sudo cp config/jail.local /etc/fail2ban/jail.local
sudo cp config/telegram.conf /etc/fail2ban/action.d/telegram.conf
```

### 5. Setup API Credentials

```bash
sudo cp config/.env.example config/.env
sudo nano config/.env
```

See [API_SETUP.md](API_SETUP.md) for detailed instructions on obtaining API keys.

### 6. Configure Cron Jobs

```bash
sudo bash -c 'cat > /etc/cron.d/fail2ban-abuseipdb << "EOF"
# Refresh AbuseIPDB blacklist daily (free API allows only 5 blacklist requests/day)
10 5 * * * root /opt/geo-fail2ban/abuseipdb_blocker.py >> /var/log/fail2ban-abuseipdb.log 2>&1

# Update GeoIP database weekly
0 2 * * 0 root python3 -m geoip2.scripts.update_geoip2 >> /var/log/fail2ban-geoip.log 2>&1
EOF'
```

### 7. Restart Fail2Ban

```bash
sudo systemctl restart fail2ban
```

### 8. Verify Installation

```bash
# Check Fail2Ban status
sudo systemctl status fail2ban

# Check jail status
sudo fail2ban-client status sshd

# View recent logs
sudo tail -f /var/log/fail2ban.log
```

## Optional: Setup Firewall Whitelist

To restrict SSH and DNS to specific IPs:

```bash
# Create your whitelist from the template (whitelist.txt is git-ignored)
cp config/whitelist.txt.example config/whitelist.txt

# Edit it and add your trusted IPs, one per line
# (replace the 203.0.113.x documentation placeholders with your real IPs)
sudo nano config/whitelist.txt

# Apply firewall rules
sudo bash scripts/setup-firewall.sh
```

## Testing the Installation

```bash
# Test Telegram alert
sudo bash tests/test_alert.sh

# Test AbuseIPDB blocker
sudo python3 /opt/geo-fail2ban/abuseipdb_blocker.py

# Check current bans
sudo fail2ban-client status sshd
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## Uninstallation

To remove Geo-Fail2Ban:

```bash
sudo bash scripts/uninstall.sh
```

## What Gets Installed

> Programs install under `/opt/geo-fail2ban` by default (override with `INSTALL_DIR=/path`).
> Re-running `install.sh` automatically removes a previous version first, keeping
> your `/etc/geo-fail2ban.conf` credentials.

| Component | Location | Purpose |
|-----------|----------|---------|
| Alert Script | `/opt/geo-fail2ban/telegram_alert.py` | Telegram notifications with GeoIP |
| Blocker Script | `/opt/geo-fail2ban/abuseipdb_blocker.py` | Hourly IP import from AbuseIPDB |
| Jail Config | `/etc/fail2ban/jail.local` | SSH protection rules |
| Telegram Action | `/etc/fail2ban/action.d/telegram.conf` | Fail2Ban action handler |
| Cron Jobs | `/etc/cron.d/fail2ban-abuseipdb` | Scheduled tasks |
| Logs | `/var/log/fail2ban-geo/` | Geo-Fail2Ban logs |

## Need Help?

- Check [docs/CONFIGURATION.md](CONFIGURATION.md) for detailed settings
- See [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md) for error fixes
- Review [docs/API_SETUP.md](API_SETUP.md) for API configuration
