# Configuration Guide

## Overview

Geo-Fail2Ban is configured through three main files:

1. **`config/.env`** - API credentials and settings
2. **`/etc/fail2ban/jail.local`** - Fail2Ban rules
3. **`/etc/fail2ban/action.d/telegram.conf`** - Alert action handler

## Configuration File: config/.env

### API Credentials

```bash
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"

# GeoIP Configuration
IPINFO_API_TOKEN="your_ipinfo_token"

# IP Reputation Configuration
ABUSEIPDB_API_KEY="your_abuseipdb_key"
```

See [API_SETUP.md](API_SETUP.md) for obtaining these.

### Server Configuration

```bash
# Server hostname (used in alerts)
SERVER_NAME="my-server"

# Location description (used in alerts)
SERVER_LOCATION="Datacenter Name or City"
```

### Fail2Ban Settings

```bash
# Ban duration (seconds)
# Default: 86400 (24 hours)
# Examples:
#   3600 = 1 hour
#   86400 = 24 hours
#   604800 = 1 week
BAN_TIME=86400

# Failed attempts before ban
# Default: 5
# Range: 3-10 (recommended)
MAX_RETRIES=5

# Detection window (seconds)
# Default: 3600 (1 hour)
# Examples:
#   600 = 10 minutes
#   3600 = 1 hour
#   7200 = 2 hours
FIND_TIME=3600
```

### AbuseIPDB Settings

```bash
# Minimum abuse score for auto-block (0-100%)
# Default: 75
# Higher = stricter filtering
# Lower = catch more potential attackers
ABUSE_THRESHOLD=75

# Report categories to import
# 18 = SSH Exploit, 22 = Malware, 23 = Spam Bot
# See: https://www.abuseipdb.com/categories
REPORT_CATEGORIES="18,22,23"

# Max IPs to import per hour
# Default: 10000
# Depends on API rate limits
BLACKLIST_LIMIT=10000
```

### Logging Configuration

```bash
# Log level
# Options: DEBUG, INFO, WARNING, ERROR
LOG_LEVEL="INFO"

# Log directory
LOG_DIR="/var/log/fail2ban-geo"
```

### Advanced Features

```bash
# Enable detailed GeoIP information
ENABLE_IPINFO_DETAILS=true

# Detect Tor exit nodes
ENABLE_TOR_DETECTION=true

# Detect VPN usage (requires additional API)
ENABLE_VPN_DETECTION=false

# Include WHOIS data
WHOIS_LOOKUP=true
```

---

## Configuration File: /etc/fail2ban/jail.local

### SSH Jail Configuration

```ini
[sshd]
# Enable the jail
enabled = true

# Monitor SSH logs
logpath = /var/log/auth.log

# Action on ban
action = telegram[name=%(jail)s]

# Max attempts before ban
maxretry = 5

# Time window for attempts (seconds)
findtime = 3600

# Ban duration (seconds)
bantime = 86400
```

### Custom Jails

You can add additional jails for other services:

```ini
[apache-auth]
enabled = true
port = http,https
logpath = /var/log/apache2/error.log
maxretry = 5
action = telegram[name=%(jail)s]

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 5
action = telegram[name=%(jail)s]
```

---

## Configuration File: /etc/fail2ban/action.d/telegram.conf

### Telegram Action Handler

```ini
[Definition]
# Action name
actionname = Telegram Alert

# Command when IP is banned
actionban = /opt/geo-fail2ban/telegram_alert.py <ip> <name> ban

# Command when IP is unbanned
actionunban = /opt/geo-fail2ban/telegram_alert.py <ip> <name> unban

# Default values
default_user_agent = Fail2Ban
```

---

## Performance Tuning

### For High-Traffic Servers

```bash
# Increase time window to reduce false positives
FIND_TIME=7200  # 2 hours

# Increase attempts threshold
MAX_RETRIES=10

# More selective abuse threshold
ABUSE_THRESHOLD=85
```

### For Security-Focused Servers

```bash
# Short detection window (aggressive)
FIND_TIME=600  # 10 minutes

# Lower attempt threshold
MAX_RETRIES=3

# Lower abuse threshold (catch more threats)
ABUSE_THRESHOLD=50

# Longer ban time
BAN_TIME=604800  # 1 week
```

### For Development Servers

```bash
# Longer time window
FIND_TIME=14400  # 4 hours

# Higher attempt threshold
MAX_RETRIES=20

# Disable AbuseIPDB blocking
ABUSE_THRESHOLD=100  # Effectively disabled

# Shorter ban time
BAN_TIME=300  # 5 minutes
```

---

## Monitoring Configuration

### View Logs

```bash
# Fail2Ban main log
sudo tail -f /var/log/fail2ban.log

# Geo-Fail2Ban specific logs
sudo tail -f /var/log/fail2ban-geo/*

# AbuseIPDB blocker log
sudo tail -f /var/log/fail2ban-abuseipdb.log
```

### Check Active Jails

```bash
# List all jails
sudo fail2ban-client status

# Check specific jail
sudo fail2ban-client status sshd

# View current bans
sudo fail2ban-client set sshd unbanip <ip>
```

### Real-Time Monitoring

```bash
# Monitor bans in real-time
watch -n 1 'sudo fail2ban-client status sshd | grep "Currently banned"'

# Monitor logs with colors
sudo tail -f /var/log/fail2ban.log | grep --color=always "Ban\|Unban"
```

---

## Firewall Integration

### UFW Configuration

```bash
# Edit whitelist
sudo nano config/whitelist.txt

# Apply rules
sudo bash scripts/setup-firewall.sh

# View current rules
sudo ufw status numbered
```

### Example Whitelist

```
# config/whitelist.txt
# Add one IP per line

# Office networks
203.0.113.10
203.0.113.20

# Additional locations
203.0.113.30
203.0.113.31
```

### Manual UFW Configuration

```bash
# Allow SSH from specific IP
sudo ufw allow from 203.0.113.10 to any port 22 proto tcp

# Deny SSH from everywhere else
sudo ufw deny 22

# Allow DNS from specific IP
sudo ufw allow from 203.0.113.10 to any port 53

# Reload rules
sudo ufw reload
```

---

## Troubleshooting Configuration

### Issue: Telegram alerts not sending

1. Verify `.env` credentials:
   ```bash
   sudo grep -E "TELEGRAM|IPINFO|ABUSEIPDB" config/.env
   ```

2. Test Telegram API:
   ```bash
   python3 -c "
   import requests
   import os
   token = 'YOUR_TOKEN'
   chat_id = 'YOUR_CHAT_ID'
   url = f'https://api.telegram.org/bot{token}/sendMessage'
   requests.post(url, json={'chat_id': chat_id, 'text': 'Test'})
   "
   ```

### Issue: Bans not working

1. Check jail is enabled:
   ```bash
   sudo fail2ban-client status sshd
   ```

2. Verify logpath exists:
   ```bash
   sudo test -f /var/log/auth.log && echo "Log file exists"
   ```

3. Check permissions:
   ```bash
   sudo ls -l /var/log/auth.log
   ```

### Issue: AbuseIPDB import failing

1. Verify API key:
   ```bash
   grep ABUSEIPDB config/.env
   ```

2. Check rate limits:
   ```bash
   sudo tail -50 /var/log/fail2ban-abuseipdb.log | grep -i "error\|rate\|429"
   ```

---

## Best Practices

1. **Review logs regularly** - Check `/var/log/fail2ban.log` for patterns
2. **Monitor Telegram alerts** - Ensure you're receiving notifications
3. **Adjust thresholds gradually** - Start conservative, tighten over time
4. **Document changes** - Keep notes of configuration modifications
5. **Test before deploying** - Use `test_alert.sh` after changes
6. **Backup configurations** - Keep copies of working configs
7. **Review whitelist quarterly** - Remove unused IPs

