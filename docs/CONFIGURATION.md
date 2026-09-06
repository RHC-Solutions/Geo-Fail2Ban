# Configuration Guide

## Overview

Geo-Fail2Ban is configured through four files:

| File | Purpose |
|------|---------|
| **`/etc/geo-fail2ban.conf`** | API credentials and settings — **the file the scripts read at runtime** |
| **`/etc/fail2ban/jail.local`** | The `sshd` jail: ban time, retries, log source |
| **`/etc/fail2ban/jail.d/abuseipdb.conf`** | The permanent-ban jail (`bantime = -1`) |
| **`/etc/fail2ban/action.d/telegram.conf`** | Alert action handler |

> `config/.env` is **only** a template that pre-fills the installer's prompts.
> Editing it on an installed system changes nothing. Edit
> `/etc/geo-fail2ban.conf` instead, then `sudo systemctl restart fail2ban`.

---

## Configuration File: /etc/geo-fail2ban.conf

Plain `KEY=value` lines, mode 0600. Values may be quoted; a `#` after an
unquoted value starts a comment. **These are all the keys the code reads** —
anything else in the file is ignored.

### API Credentials

```bash
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"

# GeoIP Configuration (ipinfo.io)
IPINFO_API_TOKEN="your_ipinfo_token"

# IP Reputation Configuration (AbuseIPDB)
ABUSEIPDB_API_KEY="your_abuseipdb_key"
```

See [API_SETUP.md](API_SETUP.md) for obtaining these.

### AbuseIPDB Settings

```bash
# Confidence score (0-100) that triggers a PERMANENT ban, and the minimum
# score used when importing the daily blacklist.
# Higher = stricter. Read by both telegram_alert.py and abuseipdb_blocker.py.
ABUSE_THRESHOLD=75

# Categories reported back to AbuseIPDB when an IP is banned.
# 18 = SSH Exploit, 22 = Malware, 23 = Spam Bot
# See: https://www.abuseipdb.com/categories
REPORT_CATEGORIES="18,22,23"

# Max IPs fetched per DAILY blacklist import (not per hour — the free tier
# allows only 5 blacklist downloads per day).
BLACKLIST_LIMIT=10000
```

### Geoblock Settings

```bash
# Countries dropped entirely at the firewall (ipdeny.com country codes).
GEOBLOCK_COUNTRIES="cn vn in bd pk ng ao"

# A SECOND list, applied ON TOP of GEOBLOCK_COUNTRIES. With both defaults
# that is 60 countries blocked, not 7.
GEOBLOCK_AFRICA="dz ao bj bw bf bi cv cm cf td km cg cd ci dj eg gq er sz et ga gm gh gn gw ke ls lr ly mg mw ml mr mu ma mz na ne ng rw st sn sc sl so za ss sd tz tg tn ug eh zm zw"
```

Set either key to `""` to block nothing from that list. Removing a country code
also removes it from the ipset on the next run — the stale zone file is pruned.
Apply a change immediately instead of waiting for the daily cron:

```bash
sudo /opt/geo-fail2ban/ipset-geo/update.sh
```

### Settings that do NOT live here

Ban duration, retry count and the detection window are **fail2ban** settings,
not keys in this file. Change them in `/etc/fail2ban/jail.local` (see below).
There is no `BAN_TIME`, `MAX_RETRIES`, `FIND_TIME`, `SERVER_NAME`, `LOG_LEVEL`
or `LOG_DIR` key — setting one has no effect.

---

## Configuration File: /etc/fail2ban/jail.local

### SSH Jail Configuration

```ini
[sshd]
enabled = true
port = ssh
filter = sshd

# Debian/Ubuntu. install.sh rewrites this to 'logpath = /var/log/secure' on
# RHEL/Fedora/SUSE, or to 'backend = systemd' where SSH logs only to the
# journal. A logpath pointing at a missing file stops the jail starting.
logpath = /var/log/auth.log

# Failed attempts before a ban
maxretry = 5

# Detection window, seconds (3600 = 1 hour)
findtime = 3600

# Ban duration, seconds (86400 = 24 hours)
bantime = 86400

action = %(action_)s
         telegram
```

After editing: `sudo systemctl restart fail2ban`.

### Permanent-Ban Jail — /etc/fail2ban/jail.d/abuseipdb.conf

`telegram_alert.py` appends any banned IP scoring at or above
`ABUSE_THRESHOLD` to `/var/log/abuseipdb.log`. This jail tails that file and
bans on the first line seen, forever:

```ini
[abuseipdb]
enabled = true
filter = abuseipdb
logpath = /var/log/abuseipdb.log
maxretry = 1
bantime = -1
findtime = 1w
action = %(action_)s
         telegram
```

> Use `%(action_)s`, not `%(action_mw)s`: the latter adds a sendmail-whois
> action, so every permanent ban would try to mail root through an MTA the host
> may not have.

### Custom Jails

Additional services can reuse the same Telegram action:

```ini
[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 5
action = %(action_)s
         telegram
```

---

## Configuration File: /etc/fail2ban/action.d/telegram.conf

The action passes four positional arguments to `telegram_alert.py`:
`<action> <jail> <ip> <failures>`.

```ini
[Definition]
# No alert on jail start/stop: those carry no real IP, and alerting on them
# meant a Telegram message per jail on every fail2ban restart.
actionstart =
actionstop  =
actioncheck =

actionban   = /opt/geo-fail2ban/telegram_alert.py "Banned"   "<name>" "<ip>" "<failures>"
actionunban = /opt/geo-fail2ban/telegram_alert.py "Unbanned" "<name>" "<ip>" "<failures>"

[Init]
```

Only `Banned` and `Unbanned` produce an alert; any other action word is ignored.

---

## Performance Tuning

These are fail2ban settings in `jail.local`, plus `ABUSE_THRESHOLD` in
`/etc/geo-fail2ban.conf`.

### For High-Traffic Servers

```ini
findtime = 7200     # 2 hours — fewer false positives
maxretry = 10
```
```bash
ABUSE_THRESHOLD=85  # more selective
```

### For Security-Focused Servers

```ini
findtime = 600      # 10 minutes — aggressive
maxretry = 3
bantime  = 604800   # 1 week
```
```bash
ABUSE_THRESHOLD=50  # catch more threats
```

### For Development Servers

```ini
findtime = 14400
maxretry = 20
bantime  = 300      # 5 minutes
```
```bash
ABUSE_THRESHOLD=100 # effectively disables permanent-ban escalation
```

---

## Monitoring

### View Logs

```bash
# Fail2Ban main log
sudo tail -f /var/log/fail2ban.log

# Daily AbuseIPDB blacklist import
sudo tail -f /var/log/fail2ban-abuseipdb.log

# Daily country-zone sync
sudo tail -f /var/log/ipset-geo.log

# Permanent-ban escalation channel (IPs fed to the abuseipdb jail)
sudo tail -f /var/log/abuseipdb.log
```

All four are rotated by `/etc/logrotate.d/geo-fail2ban`.

### Check Active Jails

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client status abuseipdb

# Unban an IP
sudo fail2ban-client set sshd unbanip <ip>
```

Note that unbanning in fail2ban does **not** remove an IP from the
`abuseipdb-blacklist` ipset, which is add-only:

```bash
sudo ipset del abuseipdb-blacklist <ip>
sudo ipset save abuseipdb-blacklist > /etc/ipset-abuseipdb.conf
```

### Real-Time Monitoring

```bash
watch -n 1 'sudo fail2ban-client status sshd | grep "Currently banned"'
sudo tail -f /var/log/fail2ban.log | grep --color=always "Ban\|Unban"
```

---

## Firewall Integration

`scripts/setup-firewall.sh` auto-detects the active backend (**firewalld**, **ufw**,
or raw **iptables**) and applies the SSH/DNS whitelist accordingly — you don't pick
one. The UFW commands below are just one backend's example.

```bash
# Edit whitelist (one IP per line)
sudo nano config/whitelist.txt

# Apply rules (works on firewalld / ufw / iptables)
sudo bash scripts/setup-firewall.sh
```

The IP of your current SSH session is always added automatically, so this
cannot lock you out of the session you run it from.

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

### Inspecting the result

```bash
# ufw
sudo ufw status numbered

# firewalld
sudo firewall-cmd --list-rich-rules

# iptables
sudo iptables -S INPUT
```

---

## Troubleshooting Configuration

### Issue: Telegram alerts not sending

1. Verify the runtime credentials:
   ```bash
   sudo grep -E "TELEGRAM|IPINFO|ABUSEIPDB" /etc/geo-fail2ban.conf
   ```

2. Send a test alert through the installed script:
   ```bash
   sudo python3 /opt/geo-fail2ban/telegram_alert.py test
   ```

3. Or run the full health check:
   ```bash
   sudo bash tests/test_alert.sh
   ```

### Issue: Bans not working

1. Check the jail is running:
   ```bash
   sudo fail2ban-client status sshd
   ```

2. Verify the jail is watching a log source that exists:
   ```bash
   sudo grep -E '^(logpath|backend)' /etc/fail2ban/jail.local
   sudo test -f /var/log/auth.log && echo "auth.log exists"
   sudo test -f /var/log/secure  && echo "secure exists"
   ```

3. Test the filter against real log lines:
   ```bash
   sudo fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf
   ```

### Issue: AbuseIPDB import failing

1. Verify the API key:
   ```bash
   sudo grep ABUSEIPDB /etc/geo-fail2ban.conf
   ```

2. Check rate limits — the free tier allows 5 blacklist downloads per day:
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
