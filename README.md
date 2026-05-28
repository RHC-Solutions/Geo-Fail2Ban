# 🚀 Geo-Fail2Ban

**Advanced Fail2Ban with GeoIP Telegram Alerts, AbuseIPDB Integration & Automatic IP Blocking**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.7+](https://img.shields.io/badge/python-3.7+-blue.svg)](https://www.python.org/downloads/)
[![Fail2Ban Compatible](https://img.shields.io/badge/Fail2Ban-0.11+-green.svg)](https://www.fail2ban.org/)

---

## ✨ Features

- 🚫 **Real-time SSH Intrusion Detection** - 5 failed attempts = automatic ban
- 📱 **Telegram Alerts** - Get notified instantly when attacks occur
- 🌍 **GeoIP Location Data** - See country, city, timezone, ISP of attacking IP
- 🔴 **AbuseIPDB Integration** - Check IP reputation scores (0-100%)
- 🤖 **Automatic IP Reporting** - Contribute to community threat database
- 📊 **Hourly Threat Import** - Automatically block known-bad IPs from AbuseIPDB
- 🔐 **Firewall Whitelisting** - Restrict SSH/DNS to specific IPs only
- 📝 **Complete Audit Trail** - All events logged with threat intelligence

---

## 📋 Quick Start

### Prerequisites
- **Ubuntu/Debian** Linux system
- **Root** or **sudo** access
- **Fail2Ban** already installed (or will be installed)
- **Python 3.7+**

### Installation (3 minutes)

```bash
# 1. Clone repository
git clone https://github.com/RHC-Solutions/Geo-Fail2Ban.git
cd Geo-Fail2Ban

# 2. Run installation script
sudo bash install.sh

# 3. Configure your API credentials
sudo nano config/.env

# 4. Restart fail2ban
sudo systemctl restart fail2ban
```

**That's it! You're protected.** 🛡️

---

## 🔑 Required API Keys

Get these free API keys and update them in `config/.env`:

### 1. **Telegram Bot**
```
https://t.me/BotFather
→ Create bot → Copy token
→ Save chat ID from first message
```

### 2. **ipinfo.io**
```
https://ipinfo.io
→ Sign up (free tier = 50,000 requests/month)
→ Get API token from dashboard
```

### 3. **AbuseIPDB**
```
https://www.abuseipdb.com
→ Sign up (free tier = 1,000 reports/day)
→ Get API key from account settings
```

---

## ⚙️ Configuration

### API Credentials - `config/.env`

```bash
# Telegram
TELEGRAM_BOT_TOKEN="your_bot_token_here"
TELEGRAM_CHAT_ID="your_chat_id_here"

# GeoIP (ipinfo.io)
IPINFO_API_TOKEN="your_ipinfo_token"

# IP Reputation (AbuseIPDB)
ABUSEIPDB_API_KEY="your_abuseipdb_key"

# Server Settings
SERVER_NAME="your-server-name"
BAN_TIME=86400          # 24 hours in seconds
MAX_RETRIES=5           # Attempts before ban
FIND_TIME=3600          # Detection window (1 hour)
ABUSE_THRESHOLD=75      # Min score to auto-block (0-100%)
```

### Firewall Whitelist - `config/whitelist.txt`

Restrict SSH & DNS to specific IPs:

```bash
# Add one IP per line
203.0.113.10
203.0.113.20
203.0.113.30
203.0.113.31
```

Then apply:
```bash
sudo bash scripts/setup-firewall.sh
```

---

## 📨 Alert Example

When an attack is detected:

```
🚫 Fail2Ban Alert
Server: dns02.example.com
Jail: sshd
Host: 165.154.182.85
Attempts: 5 (Failed login attempts detected)
Action: Banned
Time: 2026-05-28 23:45:12

🌍 GeoIP Information
Country: FI
Region: Uusimaa
City: Helsinki
Timezone: Europe/Helsinki
ASN/Org: AS215590 DpkgSoft International Limited

⚠️ AbuseIPDB Report
🔴 Abuse Score: 100% (CRITICAL)
Total Reports: 305
ISP: UCLOUD INFORMATION TECHNOLOGY
Domain: ucloud.cn
Usage Type: Data Center/Web Hosting
Distinct Users Reporting: 57
Last Reported: 2026-05-28T22:04:09+00:00
```

---

## 📊 How It Works

```
SSH Attack
    ↓
5+ Failed Attempts (within 1 hour)
    ↓
IP Banned by UFW/iptables
    ↓
Telegram Alert Triggered
    ↓
GeoIP Data Fetched (ipinfo.io)
    ↓
Reputation Data Fetched (AbuseIPDB)
    ↓
Alert Sent to Telegram with Full Intel
    ↓
IP Reported to AbuseIPDB (community database)
    ↓
Every Hour: Import high-abuse IPs from AbuseIPDB
    ↓
Preemptive Blocking (Attempts: 0)
```

---

## 📁 Directory Structure

```
Geo-Fail2Ban/
├── README.md                 # This file
├── LICENSE                   # MIT License
├── install.sh                # Automated installer
├── config/
│   ├── .env                  # API credentials (EDIT THIS!)
│   ├── .env.example          # Template
│   ├── whitelist.txt         # IP whitelist for SSH/DNS
│   └── jail.local            # Fail2ban configuration
├── scripts/
│   ├── telegram_alert.py     # Alert script (260 lines)
│   ├── abuseipdb_blocker.py  # Hourly IP import (91 lines)
│   ├── setup-firewall.sh     # UFW firewall setup
│   └── uninstall.sh          # Removal script
├── docs/
│   ├── INSTALLATION.md       # Detailed setup guide
│   ├── CONFIGURATION.md      # Configuration details
│   ├── TROUBLESHOOTING.md    # Common issues
│   └── API_SETUP.md          # API key guides
└── tests/
    └── test_alert.sh         # Send test alert
```

---

## 🚀 Installation Methods

### Method 1: Automated (Recommended)
```bash
sudo bash install.sh
```

### Method 2: Manual Installation
```bash
# 1. Install dependencies
sudo apt-get update
sudo apt-get install -y fail2ban python3-pip curl

# 2. Install Python packages
pip3 install requests

# 3. Copy files
sudo mkdir -p /opt/fail2ban-scripts
sudo cp scripts/* /opt/fail2ban-scripts/
sudo chmod +x /opt/fail2ban-scripts/*.py

# 4. Copy configurations
sudo cp config/jail.local /etc/fail2ban/jail.local
sudo cp config/telegram.conf /etc/fail2ban/action.d/telegram.conf

# 5. Update API keys
sudo nano config/.env

# 6. Set up cron jobs
sudo cp config/crontab /etc/cron.d/fail2ban-abuseipdb

# 7. Restart
sudo systemctl restart fail2ban
```

---

## 🧪 Testing

### Send Test Alert
```bash
sudo bash tests/test_alert.sh
```

### Check Status
```bash
# View all bans
sudo fail2ban-client status sshd

# View logs
sudo tail -f /var/log/fail2ban.log

# View alerts log
sudo tail -f /var/log/fail2ban-abuseipdb.log
```

### Manual Ban (for testing)
```bash
# Ban an IP
sudo fail2ban-client set sshd banip 192.168.1.1

# Unban an IP
sudo fail2ban-client set sshd unbanip 192.168.1.1

# View banned IPs
sudo fail2ban-client get sshd banlist
```

---

## 🔒 Security Hardening

### Restrict SSH to Specific IPs

```bash
# Edit whitelist
sudo nano config/whitelist.txt

# Add your trusted IPs (one per line):
203.0.113.10
203.0.113.20

# Apply firewall rules
sudo bash scripts/setup-firewall.sh
```

### Disable Password Auth (Optional)
```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Find and set:
PasswordAuthentication no
PubkeyAuthentication yes

# Restart SSH
sudo systemctl restart ssh
```

---

## 📊 Configuration Reference

### Fail2Ban Settings

| Setting | Value | Meaning |
|---------|-------|---------|
| bantime | 86400 | Ban duration (24 hours) |
| findtime | 3600 | Detection window (1 hour) |
| maxretry | 5 | Failed attempts before ban |
| logpath | /var/log/auth.log | SSH log file |

### AbuseIPDB Settings

| Setting | Value | Meaning |
|---------|-------|---------|
| ABUSE_THRESHOLD | 75 | Min score for auto-block (0-100%) |
| REPORT_CATEGORIES | 18,22,23 | Categories to report as |
| BLACKLIST_LIMIT | 10000 | Max IPs to import per hour |

---

## 📝 Log Files

All activity is logged for audit trail:

```bash
# Main fail2ban log
sudo tail -f /var/log/fail2ban.log

# AbuseIPDB imports
sudo tail -f /var/log/fail2ban-abuseipdb.log

# GeoIP updates
sudo tail -f /var/log/fail2ban-geoip.log
```

---

## 🐛 Troubleshooting

### Telegram alerts not working?
```bash
# Test API connection
curl -X POST https://api.telegram.org/bot{TOKEN}/getMe

# Check script logs
sudo tail -50 /var/log/fail2ban.log | grep Telegram
```

### GeoIP data missing?
```bash
# Check ipinfo.io token
curl "https://ipinfo.io/8.8.8.8?token=YOUR_TOKEN"

# Verify API quota
curl "https://ipinfo.io?token=YOUR_TOKEN"
```

### AbuseIPDB not blocking?
```bash
# Check API key
curl -H "Key: YOUR_KEY" https://api.abuseipdb.com/api/v2/check?ipAddress=8.8.8.8

# Check hourly cron logs
sudo grep abuseipdb /var/log/syslog
```

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more help.

---

## 🛠️ Manual Configuration

### Edit Jail Config
```bash
sudo nano /etc/fail2ban/jail.local
```

### Edit Alert Script
```bash
sudo nano /opt/fail2ban-scripts/telegram_alert.py
```

### Edit Cron Jobs
```bash
sudo nano /etc/cron.d/fail2ban-abuseipdb
```

### Restart Service
```bash
sudo systemctl restart fail2ban
```

---

## 📖 Documentation

- **[INSTALLATION.md](docs/INSTALLATION.md)** - Detailed setup guide
- **[CONFIGURATION.md](docs/CONFIGURATION.md)** - All configuration options
- **[API_SETUP.md](docs/API_SETUP.md)** - Step-by-step API key setup
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues & fixes
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System design & flow

---

## 🔄 Uninstallation

Remove all Geo-Fail2Ban components:

```bash
sudo bash scripts/uninstall.sh
```

Or manually:
```bash
# Stop service
sudo systemctl stop fail2ban

# Remove files
sudo rm /etc/fail2ban/jail.local
sudo rm /etc/fail2ban/action.d/telegram.conf
sudo rm -rf /opt/fail2ban-scripts
sudo rm /etc/cron.d/fail2ban-abuseipdb

# Restart
sudo systemctl restart fail2ban
```

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

---

## ⚠️ Disclaimer

**Use at your own risk.** This tool modifies firewall rules and system configurations. Always:

- Backup your system before installation
- Test in a non-production environment first
- Keep API keys secure and never commit them
- Monitor logs for false positives
- Ensure you're not blocking legitimate users

---

## 🙋 Support & Issues

Found a bug? Have a question?

- **GitHub Issues**: [Report Issue](https://github.com/RHC-Solutions/Geo-Fail2Ban/issues)
- **Documentation**: See [docs/](docs/) folder
- **Troubleshooting**: [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

---

## 📊 System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 18.04 / Debian 10 | Ubuntu 22.04 / Debian 11+ |
| CPU | 1 Core | 2+ Cores |
| RAM | 512 MB | 2+ GB |
| Disk | 100 MB | 1+ GB |
| Python | 3.6+ | 3.8+ |
| Fail2Ban | 0.11+ | 1.0+ |

---

## 🎉 Credits

Built with:
- [Fail2Ban](https://www.fail2ban.org/) - Intrusion prevention
- [ipinfo.io](https://ipinfo.io/) - GeoIP data
- [AbuseIPDB](https://www.abuseipdb.com/) - IP reputation
- [Telegram Bot API](https://telegram.org/blog/bot-api) - Notifications

---

## 📈 Statistics

- ⭐ Real-time threat intelligence
- 🌍 Global IP reputation database
- 📊 100+ data points per alert
- 🚀 Sub-second ban execution
- 📱 Instant Telegram notifications

---

**Made with ❤️ for security**

⭐ If you find this useful, please star the repository!

---

## Changelog

### v1.0.0 (2026-05-28)
- Initial release
- Telegram alerts with GeoIP
- AbuseIPDB integration
- Automatic IP blocking
- Firewall whitelisting

---

Questions? See [docs/FAQ.md](docs/FAQ.md) or create an issue!
