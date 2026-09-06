# Installation Guide

## System Requirements

- **OS**: any systemd-based Linux (Debian/Ubuntu, RHEL/Fedora/Rocky/Alma, openSUSE, Arch, Alpine)
- **Firewall**: firewalld, ufw, or iptables (auto-detected; installed if missing)
- **Privileges**: Root or sudo access
- **Network**: Outbound HTTPS access for API calls

> **Note for RHEL/Fedora/Rocky/Alma/SUSE/Arch:** the shipped `sshd` jail reads
> `/var/log/auth.log`, which is Debian/Ubuntu-specific. On distros that log SSH
> to `/var/log/secure` or to journald only, edit `logpath` (or set
> `backend = systemd`) in `/etc/fail2ban/jail.local` before the jail will start.

## Quick Start

```bash
# 1. Clone the repository
git clone git@github.com:RHC-Solutions/Geo-Fail2Ban.git
cd Geo-Fail2Ban

# 2. Run the installer. It PROMPTS for your API credentials, so have them
#    ready (see API_SETUP.md). A Telegram bot token is mandatory - the
#    installer exits without one.
sudo bash install.sh
```

That is the whole installation. The installer writes your answers to
`/etc/geo-fail2ban.conf` (mode 0600), installs the jails, creates the ipsets and
firewall rules, enables the boot-restore units and the daily cron jobs, and
finishes by sending a status summary to your Telegram chat.

Use `sudo bash install.sh --skip-geo` to install without the country geoblock.

### Pre-seeding the answers (optional, for unattended installs)

If you would rather not answer prompts, fill in the template **before** running
the installer — `install.sh` reads `config/.env` and uses it to pre-fill every
prompt:

```bash
cp config/.env.example config/.env
nano config/.env
sudo bash install.sh          # press Enter through the prompts to accept them
```

Each prompt also auto-skips after 60 seconds; override with
`PROMPT_TIMEOUT=N sudo -E bash install.sh`.

> **Editing `config/.env` after installing has no effect.** It is only a
> template for the installer. The runtime config — the file every script
> actually reads — is `/etc/geo-fail2ban.conf`. Edit that (then
> `sudo systemctl restart fail2ban`) to change settings on an installed system.

## What the Installer Does

| Step | Action |
|------|--------|
| 1 | Prompts for Telegram / ipinfo.io / AbuseIPDB credentials and the geoblock country lists |
| 2 | Writes `/etc/geo-fail2ban.conf` (0600) and removes any previous install |
| 3 | Installs `fail2ban ipset iptables curl python3-requests` via your package manager |
| 4 | Copies the scripts to `/opt/geo-fail2ban` |
| 5 | Installs the `sshd` and `abuseipdb` jails, the `abuseipdb` filter and the `telegram` action |
| 6 | Creates the `abuseipdb-blacklist` ipset + DROP rule via the detected firewall backend |
| 7 | Downloads country zone files and creates the `geoblock` ipset (unless `--skip-geo`) |
| 8 | Optionally applies the SSH/DNS whitelist |
| 9 | Enables the boot-restore units and the daily cron jobs |
| 10 | Runs a first blacklist import, restarts fail2ban, verifies, and sends a Telegram summary |

## Manual Installation

Only needed if you cannot run `install.sh`. Paths below assume the default
`INSTALL_DIR=/opt/geo-fail2ban`.

```bash
# 1. Dependencies
sudo apt-get update
sudo apt-get install -y fail2ban ipset iptables curl python3-requests

# 2. Runtime config (this is the file the scripts read)
sudo cp config/.env.example /etc/geo-fail2ban.conf
sudo chmod 600 /etc/geo-fail2ban.conf
sudo nano /etc/geo-fail2ban.conf          # fill in your API keys

# 3. Scripts
sudo mkdir -p /opt/geo-fail2ban
sudo cp scripts/telegram_alert.py scripts/abuseipdb_blocker.py scripts/firewall-lib.sh /opt/geo-fail2ban/
sudo chmod +x /opt/geo-fail2ban/*.py /opt/geo-fail2ban/firewall-lib.sh

# 4. Fail2ban configuration
sudo cp fail2ban/jail.local              /etc/fail2ban/jail.local
sudo cp fail2ban/jail.d/abuseipdb.conf   /etc/fail2ban/jail.d/abuseipdb.conf
sudo cp fail2ban/filter.d/abuseipdb.conf /etc/fail2ban/filter.d/abuseipdb.conf
sudo cp fail2ban/action.d/telegram.conf  /etc/fail2ban/action.d/telegram.conf
sudo touch /var/log/abuseipdb.log        # the permanent-ban jail's watched log

# 5. Blacklist ipset + DROP rule (uses the firewall backend abstraction)
sudo ipset create abuseipdb-blacklist hash:ip family inet hashsize 16384 maxelem 500000 -exist
sudo bash scripts/firewall-lib.sh block abuseipdb-blacklist

# 6. Country geoblock (optional)
sudo mkdir -p /opt/geo-fail2ban/ipset-geo
sudo cp ipset-geo/update.sh /opt/geo-fail2ban/ipset-geo/update.sh
sudo chmod +x /opt/geo-fail2ban/ipset-geo/update.sh
sudo /opt/geo-fail2ban/ipset-geo/update.sh
sudo bash scripts/firewall-lib.sh block geoblock

# 7. Boot persistence
sudo cp systemd/ipset-abuseipdb.service systemd/ipset-geo.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ipset-abuseipdb.service ipset-geo.service

# 8. Daily cron jobs (do NOT run these hourly - see the note below)
sudo cp cron/fail2ban-abuseipdb /etc/cron.d/fail2ban-abuseipdb
sudo cp cron/ipset-geo          /etc/cron.d/ipset-geo
sudo chmod 644 /etc/cron.d/fail2ban-abuseipdb /etc/cron.d/ipset-geo

# 9. Start
sudo systemctl restart fail2ban
```

> **The blacklist import must stay daily.** AbuseIPDB's free tier allows only
> **5 blacklist downloads per day**; an hourly job burns the quota before
> 06:00 and the import then fails silently for the rest of the day.

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

The IP of your current SSH session is added automatically, so this cannot lock
you out of the session you run it from.

## Verifying the Installation

```bash
# Full health check: components, config, ipsets, jails, APIs, cron.
# Sends one Telegram test alert.
sudo bash tests/test_alert.sh

# Add --live to also exercise the permanent-ban pipeline end to end
sudo bash tests/test_alert.sh --live
```

Individual checks:

```bash
sudo systemctl status fail2ban
sudo fail2ban-client status sshd
sudo fail2ban-client status abuseipdb
sudo ipset list -t abuseipdb-blacklist
sudo ipset list -t geoblock
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## Uninstallation

```bash
sudo bash scripts/uninstall.sh
```

Add `--keep-config` to preserve `/etc/geo-fail2ban.conf` (your credentials).

## What Gets Installed

> Programs install under `/opt/geo-fail2ban` by default (override with `INSTALL_DIR=/path`).
> Re-running `install.sh` automatically removes a previous version first, keeping
> your `/etc/geo-fail2ban.conf` credentials.

| Component | Location | Purpose |
|-----------|----------|---------|
| Runtime config | `/etc/geo-fail2ban.conf` | API keys and settings (mode 0600) |
| Alert script | `/opt/geo-fail2ban/telegram_alert.py` | Telegram notifications + permanent-ban escalation |
| Blocker script | `/opt/geo-fail2ban/abuseipdb_blocker.py` | **Daily** blacklist import into an add-only ipset |
| Geo updater | `/opt/geo-fail2ban/ipset-geo/update.sh` | Daily country-zone sync into the `geoblock` ipset |
| Firewall library | `/opt/geo-fail2ban/firewall-lib.sh` | firewalld / ufw / iptables abstraction |
| Jail config | `/etc/fail2ban/jail.local` | SSH protection rules (24h bans) |
| Permanent jail | `/etc/fail2ban/jail.d/abuseipdb.conf` | `bantime = -1` escalation jail |
| Telegram action | `/etc/fail2ban/action.d/telegram.conf` | Fail2Ban action handler |
| Boot restore | `/etc/systemd/system/ipset-{abuseipdb,geo}.service` | Re-create ipsets + rules at boot |
| Cron jobs | `/etc/cron.d/fail2ban-abuseipdb`, `/etc/cron.d/ipset-geo` | Daily refresh |
| Escalation log | `/var/log/abuseipdb.log` | Watched by the permanent-ban jail |
| Blacklist import log | `/var/log/fail2ban-abuseipdb.log` | Daily import output |
| Geoblock log | `/var/log/ipset-geo.log` | Daily zone-sync output |

## Need Help?

- Check [docs/CONFIGURATION.md](CONFIGURATION.md) for detailed settings
- See [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md) for error fixes
- Review [docs/API_SETUP.md](API_SETUP.md) for API configuration
