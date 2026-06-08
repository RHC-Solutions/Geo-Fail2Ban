# RHC Solutions

```text
 ____  _   _  ____    ____        _       _   _
|  _ \| | | |/ ___|  / ___|  ___ | |_   _| |_(_) ___  _ __  ___
| |_) | |_| | |      \___ \ / _ \| | | | | __| |/ _ \| '_ \/ __|
|  _ <|  _  | |___    ___) | (_) | | |_| | |_| | (_) | | | \__ \
|_| \_\_| |_|\____|  |____/ \___/|_|\__,_|\__|_|\___/|_| |_|___/
```

**Website:** [rhcsolutions.com](https://rhcsolutions.com) &nbsp;·&nbsp; **Telegram:** [t.me/rhcsolutions](https://t.me/rhcsolutions)

---

## 🚀 Geo-Fail2Ban

**Advanced Fail2Ban with GeoIP Telegram Alerts, AbuseIPDB Integration & Automatic IP Blocking**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.7+](https://img.shields.io/badge/python-3.7+-blue.svg)](https://www.python.org/downloads/)
[![Fail2Ban Compatible](https://img.shields.io/badge/Fail2Ban-0.11+-green.svg)](https://www.fail2ban.org/)

---

## ✨ Features

- 🚫 **Real-time SSH Intrusion Detection** - 5 failed attempts = automatic 24h ban
- ⛔ **Permanent Ban Escalation** - banned IPs with AbuseIPDB score ≥ 75% are banned FOREVER (`bantime = -1`)
- 📱 **Telegram Alerts** - explicit `BANNED` / `UNBANNED` headers, with permanent-ban status on every unban
- 🌍 **GeoIP Location Data** - See country (with 🏴 flag emoji), city, timezone, ISP of attacking IP
- 🔴 **AbuseIPDB Integration** - Check IP reputation scores (0-100%)
- 🤖 **Automatic IP Reporting** - Contribute to community threat database
- 📊 **Daily Blacklist Import** - AbuseIPDB blacklist into an add-only ipset (~10,000 IPs, never expires)
- 🗺️ **Country Geoblock** - permanently drops whole countries at the firewall via ipset. Default block list: 🇨🇳 China, 🇻🇳 Vietnam, 🇮🇳 India, 🇧🇩 Bangladesh, 🇵🇰 Pakistan, 🇳🇬 Nigeria, 🇦🇴 Angola. Zone files **auto-sync daily** from ipdeny.com
- 🔁 **Reboot-safe** - systemd units restore all ipsets and firewall rules at boot
- 🔐 **Firewall Whitelisting** - Restrict SSH/DNS to specific IPs only
- 🧱 **Any firewall** - works with **firewalld**, **ufw**, or raw **iptables** (auto-detected)
- 🐧 **Any Linux** - Debian/Ubuntu, RHEL/Fedora/Rocky/Alma, openSUSE, Arch, Alpine
- 💬 **Interactive installer** - prompts for tokens & whitelist IPs (each auto-skips after 60s)
- 📝 **Complete Audit Trail** - All events logged with threat intelligence

---

## 📋 Quick Start

### Prerequisites
- **Any systemd-based Linux** — Debian/Ubuntu, RHEL/Fedora/Rocky/Alma, openSUSE, Arch, or Alpine
- A firewall: **firewalld**, **ufw**, or **iptables** — auto-detected (installed if missing)
- **Root** or **sudo** access
- **Python 3.7+** (the installer pulls the remaining dependencies for your distro)

### Installation (3 minutes)

```bash
# 1. Clone repository
git clone https://github.com/RHC-Solutions/Geo-Fail2Ban.git
cd Geo-Fail2Ban

# 2. Run the interactive installer (use --skip-geo to skip country blocking)
sudo bash install.sh
```

The installer **asks** for your Telegram bot token + chat ID, ipinfo.io token,
AbuseIPDB key, and whitelist IPs. Each question **auto-skips after 60 seconds**
(keeping the current value). Prefer non-interactive? Pre-fill `config/.env`
(`cp config/.env.example config/.env && nano config/.env`) and the installer
uses it as the defaults.

**That's it! You're protected.** 🛡️

> **Install location:** everything is installed under `/opt/geo-fail2ban` by default.
> Install elsewhere with `INSTALL_DIR=/srv/geo-fail2ban sudo -E bash install.sh`.
>
> **Upgrading / reinstalling:** `install.sh` auto-detects a previous version and
> uninstalls it first (keeping your `/etc/geo-fail2ban.conf` credentials), so
> re-running it always yields a clean install.

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

# AbuseIPDB settings
ABUSE_THRESHOLD=75           # Min score for PERMANENT ban (0-100%)
REPORT_CATEGORIES="18,22,23" # Categories reported back to AbuseIPDB
BLACKLIST_LIMIT=10000        # Max IPs per daily blacklist import

# Geoblock (ipdeny.com country codes; empty = block none)
# Defaults: cn=China vn=Vietnam in=India bd=Bangladesh pk=Pakistan ng=Nigeria ao=Angola
GEOBLOCK_COUNTRIES="cn vn in bd pk ng ao"
```

The installer copies this file to `/etc/geo-fail2ban.conf` (chmod 600) — that
is what the scripts read at runtime. Edit that file to change settings later.

#### Country Geoblock (auto-sync)

Every country in `GEOBLOCK_COUNTRIES` is **dropped at the firewall permanently**
(no expiry) via the `geoblock` ipset. A daily cron job
(`/etc/cron.d/ipset-geo`) **auto-syncs** the country IP ranges from
[ipdeny.com](https://www.ipdeny.com), so the block stays current as ranges
change. On reboot the `ipset-geo` systemd unit restores the set and its DROP
rule.

Add or remove countries by editing `GEOBLOCK_COUNTRIES` in
`/etc/geo-fail2ban.conf` (space-separated [ipdeny country codes](https://www.ipdeny.com/ipblocks/)),
then re-sync immediately instead of waiting for the daily cron:

```bash
sudo /opt/geo-fail2ban/ipset-geo/update.sh
```

### Firewall Whitelist - `config/whitelist.txt`

Restrict SSH & DNS to specific IPs. First create your whitelist from the
template (the real `whitelist.txt` is git-ignored, so your IPs stay private):

```bash
cp config/whitelist.txt.example config/whitelist.txt
nano config/whitelist.txt
```

Add one IP per line (the values below are documentation placeholders — replace them):

```bash
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
🚫 Fail2Ban Alert — BANNED
Server: dns02.example.com
Jail: sshd
Host: 165.154.182.85
Attempts: 5 (Failed login attempts detected)
Action: 🚫 Banned (temporary, expires per jail bantime)
⛔ Escalated to PERMANENT ban (AbuseIPDB score ≥ 75%)
Time: 2026-05-28 23:45:12

🌍 GeoIP Information
Country: 🇫🇮 FI
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

When a temporary ban expires, the unban alert tells you whether the IP is
still blocked:

```
✅ Fail2Ban Alert — UNBANNED
Server: dns02.example.com
Jail: sshd
Host: 165.154.182.85
Action: ✅ Unbanned (temporary ban expired)
⛔ Still PERMANENTLY blocked via AbuseIPDB blacklist
```

---

## 📊 How It Works

```
SSH Attack
    ↓
5+ Failed Attempts (within 1 hour)
    ↓
IP Banned by iptables for 24h (sshd jail)
    ↓
GeoIP Data Fetched (ipinfo.io)
    ↓
Reputation Data Fetched (AbuseIPDB)
    ↓
Score ≥ 75%? → written to /var/log/abuseipdb.log
    ↓             ↓
    ↓         'abuseipdb' jail bans it PERMANENTLY (bantime = -1)
    ↓
Alert Sent to Telegram with Full Intel
    ↓
IP Reported to AbuseIPDB (community database)

In parallel:
  • Daily: AbuseIPDB blacklist (score ≥ 75) imported into the add-only
    'abuseipdb-blacklist' ipset → dropped at the top of INPUT, forever.
    (The free API allows only 5 blacklist downloads/day — do NOT run hourly.)
  • Daily: country zone files auto-sync the 'geoblock' ipset from ipdeny.com
    (default: cn vn in bd pk ng ao — permanent firewall DROP; --skip-geo to disable).
  • On boot: systemd units restore both ipsets and their DROP rules.
```

---

## 📁 Directory Structure

```
Geo-Fail2Ban/
├── README.md                 # This file
├── LICENSE                   # MIT License
├── install.sh                # Automated installer (--skip-geo to skip geoblock)
├── config/
│   ├── .env                  # API credentials (EDIT THIS! - git-ignored)
│   ├── .env.example          # Template
│   ├── whitelist.txt.example # IP whitelist template (tracked)
│   └── whitelist.txt         # Your real trusted IPs (git-ignored)
├── fail2ban/                 # Mirrors /etc/fail2ban/
│   ├── jail.local            # sshd jail (24h bans + telegram action)
│   ├── jail.d/abuseipdb.conf # Permanent jail (bantime = -1)
│   ├── filter.d/abuseipdb.conf
│   └── action.d/telegram.conf
├── scripts/
│   ├── telegram_alert.py     # Alerts + permanent-ban escalation
│   ├── abuseipdb_blocker.py  # Daily blacklist -> add-only ipset
│   ├── firewall-lib.sh       # Backend abstraction (firewalld/ufw/iptables)
│   ├── setup-firewall.sh     # SSH/DNS whitelist (any firewall)
│   └── uninstall.sh          # Removal script
├── ipset-geo/
│   └── update.sh             # Daily country-zone auto-sync (geoblock ipset)
├── systemd/
│   ├── ipset-abuseipdb.service  # Restore blacklist ipset + rule at boot
│   └── ipset-geo.service        # Restore geoblock ipset + rule at boot
├── cron/
│   ├── fail2ban-abuseipdb    # Daily blacklist import (API limit: 5/day)
│   └── ipset-geo             # Daily geoblock auto-sync
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
sudo mkdir -p /opt/geo-fail2ban
sudo cp scripts/* /opt/geo-fail2ban/
sudo chmod +x /opt/geo-fail2ban/*.py

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

# Check daily cron logs
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
sudo nano /opt/geo-fail2ban/telegram_alert.py
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
sudo rm -rf /opt/geo-fail2ban
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
| OS | Any systemd Linux (Debian/Ubuntu, RHEL/Fedora, SUSE, Arch, Alpine) | Latest stable release |
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
