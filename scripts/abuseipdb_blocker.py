#!/usr/bin/env python3
"""
AbuseIPDB Blocker - permanently blocks IPs from the AbuseIPDB blacklist.

- Fetches the AbuseIPDB blacklist (confidence score >= ABUSE_SCORE_THRESHOLD).
- Adds every IPv4 to the 'abuseipdb-blacklist' ipset. Add-only: entries are
  never removed, so blocks are permanent even if an IP drops off the feed.
- Ensures a DROP rule referencing the set exists, via the host's firewall
  backend (firewalld / ufw / iptables) rather than raw iptables only.
- Saves the set to /etc/ipset-abuseipdb.conf so ipset-abuseipdb.service can
  restore it at boot.

NOTE: the free AbuseIPDB /blacklist endpoint allows only 5 requests/day,
so this must run from a DAILY cron, not hourly.
"""

import requests
import subprocess
import sys
import os
import shutil
from datetime import datetime

def _bin(name):
    """Locate a system binary. ipset/iptables live in /usr/sbin on Debian and
    RHEL, /sbin on Alpine and /usr/bin on Arch, and cron's PATH does not
    include the sbin directories at all - so search explicitly rather than
    hardcoding one distro's layout."""
    found = shutil.which(name)
    if found:
        return found
    for d in ('/usr/sbin', '/sbin', '/usr/bin', '/bin', '/usr/local/sbin'):
        cand = os.path.join(d, name)
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return name  # let execution fail with a clear error

IPSET = _bin('ipset')
IPTABLES = _bin('iptables')

# Installed alongside this script by install.sh; knows how to express a DROP
# rule for firewalld / ufw / raw iptables.
FIREWALL_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            'firewall-lib.sh')

# Configuration is read from /etc/geo-fail2ban.conf (KEY=value lines).
# Secrets live there - never hardcode them here (this file is in git).
CONFIG_FILE = "/etc/geo-fail2ban.conf"

def load_config(path=CONFIG_FILE):
    cfg = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                key, value = line.split('=', 1)
                value = value.strip()
                # Quoted value: take the quoted part (inline comment after it is dropped)
                if value[:1] in ('"', "'") and value.count(value[0]) >= 2:
                    value = value[1:value.index(value[0], 1)]
                else:
                    # Unquoted: strip inline comment
                    value = value.split('#', 1)[0].strip()
                cfg[key.strip()] = value
    except FileNotFoundError:
        print(f"FATAL: config file {path} not found", file=sys.stderr)
        sys.exit(1)
    return cfg

_cfg = load_config()
ABUSEIPDB_API_KEY = _cfg.get('ABUSEIPDB_API_KEY', '')
ABUSE_SCORE_THRESHOLD = int(_cfg.get('ABUSE_THRESHOLD')
                            or _cfg.get('ABUSE_SCORE_THRESHOLD') or '75')  # Block IPs with confidence score >= this
BLACKLIST_LIMIT = int(_cfg.get('BLACKLIST_LIMIT', '10000'))
IPSET_NAME = "abuseipdb-blacklist"
SAVE_FILE = "/etc/ipset-abuseipdb.conf"

def log(msg):
    print(msg, file=sys.stderr)

def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kwargs)

def get_blacklisted_ips():
    """Get list of high-abuse IPv4s from AbuseIPDB (plaintext, one IP per line)"""
    try:
        headers = {
            'Key': ABUSEIPDB_API_KEY,
            'Accept': 'text/plain'
        }
        params = {
            'limit': BLACKLIST_LIMIT,
            'confidenceMinimum': ABUSE_SCORE_THRESHOLD
        }

        response = requests.get(
            'https://api.abuseipdb.com/api/v2/blacklist',
            headers=headers,
            params=params,
            timeout=30
        )

        if response.status_code == 200:
            ips = [line.strip() for line in response.text.splitlines() if line.strip()]
            ipv4 = [ip for ip in ips if ':' not in ip]
            skipped = len(ips) - len(ipv4)
            if skipped:
                log(f"Skipped {skipped} IPv6 entries (ipset is IPv4-only)")
            return ipv4
        else:
            log(f"Failed to fetch blacklist: {response.text}")
            return []
    except Exception as e:
        log(f"Error fetching AbuseIPDB blacklist: {e}")
        return []

def ensure_ipset():
    """Create the ipset if it doesn't exist yet"""
    result = run([IPSET, 'create', IPSET_NAME, 'hash:ip',
                  'family', 'inet', 'hashsize', '16384', 'maxelem', '500000', '-exist'])
    if result.returncode != 0:
        log(f"Failed to create ipset: {result.stderr}")
        sys.exit(1)

def ensure_block_rule():
    """Make sure traffic from the set is dropped, via whichever firewall
    backend this host actually runs.

    Prefer firewall-lib.sh: on a firewalld system a raw iptables rule is
    silently discarded by the next 'firewall-cmd --reload', so the set would
    quietly stop blocking anything. Fall back to iptables only if the library
    is unavailable."""
    if os.path.exists(FIREWALL_LIB):
        result = run(['/bin/bash', FIREWALL_LIB, 'block', IPSET_NAME])
        if result.returncode == 0:
            return
        log(f"firewall-lib block failed ({result.stderr.strip()}), "
            "falling back to raw iptables")

    rule = ['-m', 'set', '--match-set', IPSET_NAME, 'src', '-j', 'DROP']
    check = run([IPTABLES, '-C', 'INPUT'] + rule)
    if check.returncode != 0:
        result = run([IPTABLES, '-I', 'INPUT', '1'] + rule)
        if result.returncode == 0:
            log("Inserted iptables DROP rule for " + IPSET_NAME)
        else:
            log(f"Failed to insert iptables rule: {result.stderr}")

def count_entries():
    result = run([IPSET, 'list', '-t', IPSET_NAME])
    for line in result.stdout.splitlines():
        if line.startswith('Number of entries'):
            return int(line.split(':')[1].strip())
    return 0

def add_ips(ips):
    """Bulk-add IPs via 'ipset restore' (much faster than one call per IP)"""
    lines = '\n'.join(f"add {IPSET_NAME} {ip} -exist" for ip in ips) + '\n'
    result = run([IPSET, 'restore', '-exist'], input=lines)
    if result.returncode != 0:
        log(f"ipset restore failed: {result.stderr}")
        return False
    return True

def save_set():
    """Persist the set for restore at boot (ipset-abuseipdb.service)"""
    result = run([IPSET, 'save', IPSET_NAME])
    if result.returncode == 0:
        with open(SAVE_FILE, 'w') as f:
            f.write(result.stdout)
    else:
        log(f"Failed to save ipset: {result.stderr}")

def main():
    log(f"[{datetime.now().isoformat()}] Fetching AbuseIPDB blacklist...")

    ensure_ipset()
    ensure_block_rule()

    ips = get_blacklisted_ips()
    if not ips:
        log("No IPs fetched (rate limit or API error) - existing bans unchanged")
        return

    before = count_entries()
    if add_ips(ips):
        after = count_entries()
        log(f"Fetched {len(ips)} IPs, added {after - before} new "
            f"({after} total permanently blocked)")
        save_set()

if __name__ == "__main__":
    main()
