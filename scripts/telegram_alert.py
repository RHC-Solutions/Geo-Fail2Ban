#!/usr/bin/env python3
"""
Fail2Ban Telegram Alert Script with GeoIP and AbuseIPDB Integration
"""

import sys
import requests
import socket
import html
import os
import shutil
import subprocess
from datetime import datetime

def _bin(name):
    """Locate a system binary. ipset/iptables live in /usr/sbin on Debian and
    RHEL, /sbin on Alpine and /usr/bin on Arch, and fail2ban's PATH does not
    always include the sbin directories - so search explicitly."""
    found = shutil.which(name)
    if found:
        return found
    for d in ('/usr/sbin', '/sbin', '/usr/bin', '/bin', '/usr/local/sbin'):
        cand = os.path.join(d, name)
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return name

IPSET = _bin('ipset')
IPTABLES = _bin('iptables')

# Configuration is read from /etc/geo-fail2ban.conf (KEY=value lines).
# Secrets live there - never hardcode them here (this file is in git).
CONFIG_FILE = "/etc/geo-fail2ban.conf"

def esc(value):
    """Escape a value for Telegram's parse_mode=HTML.

    Everything interpolated into an alert - the hostname, the jail name and
    especially the org/isp/domain strings coming back from ipinfo.io and
    AbuseIPDB - is third-party text. Telegram only accepts a small tag
    whitelist and rejects the whole message with HTTP 400 on a stray '&' or
    '<' (e.g. an ASN owned by 'AT&T Services, Inc.'), which would silently
    drop the ban notification.
    """
    return html.escape(str(value), quote=False)

def country_flag(country_code):
    """Convert a 2-letter ISO country code into its flag emoji (e.g. PT -> 🇵🇹)."""
    cc = (country_code or "").strip().upper()
    if len(cc) != 2 or not cc.isalpha():
        return ""
    return "".join(chr(0x1F1E6 + ord(c) - ord('A')) for c in cc)

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
TELEGRAM_BOT_TOKEN = _cfg.get('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_CHAT_ID = _cfg.get('TELEGRAM_CHAT_ID', '')
ABUSEIPDB_API_KEY = _cfg.get('ABUSEIPDB_API_KEY', '')
IPINFO_API_TOKEN = _cfg.get('IPINFO_API_TOKEN', '')
REPORT_CATEGORIES = _cfg.get('REPORT_CATEGORIES', '18,22,23')

# Permanent ban escalation: any banned IP with an AbuseIPDB confidence score
# >= this threshold is also written to ABUSEIPDB_LOG, where the 'abuseipdb'
# jail (maxretry=1, bantime=-1) picks it up and bans it forever.
PERMANENT_JAIL = "abuseipdb"
PERMANENT_SCORE_THRESHOLD = int(_cfg.get('ABUSE_THRESHOLD')
                                or _cfg.get('ABUSE_SCORE_THRESHOLD') or '75')
ABUSEIPDB_LOG = "/var/log/abuseipdb.log"
IPSET_BLACKLIST = "abuseipdb-blacklist"

def get_hostname():
    """Get actual server hostname"""
    try:
        hostname = subprocess.check_output(['hostname', '-f'], text=True).strip()
        if not hostname:
            hostname = socket.getfqdn()
        return hostname
    except Exception:
        return socket.getfqdn()

def get_geoip_info(ip_address):
    """Get detailed GeoIP info from ipinfo.io"""
    try:
        response = requests.get(
            f"https://ipinfo.io/{ip_address}?token={IPINFO_API_TOKEN}",
            timeout=5
        )
        
        if response.status_code == 200:
            data = response.json()
            # Add success flag for consistency
            data['success'] = True
            return data
        else:
            print(f"GeoIP API error: {response.status_code}", file=sys.stderr)
            return None
    except Exception as e:
        print(f"Error fetching GeoIP data: {e}", file=sys.stderr)
        return None

def get_abuseipdb_info(ip_address):
    """Get abuse info from AbuseIPDB API"""
    try:
        headers = {
            'Key': ABUSEIPDB_API_KEY,
            'Accept': 'application/json'
        }
        params = {
            'ipAddress': ip_address,
            'maxAgeInDays': '90',
            'verbose': ''
        }
        
        response = requests.get(
            'https://api.abuseipdb.com/api/v2/check',
            headers=headers,
            params=params,
            timeout=5
        )
        
        if response.status_code == 200:
            data = response.json()
            result = data.get('data', {})
            return result
        else:
            print(f"AbuseIPDB API error: {response.status_code}", file=sys.stderr)
            return None
    except Exception as e:
        print(f"Error fetching AbuseIPDB data: {e}", file=sys.stderr)
        return None

def is_permanently_banned(ip_address):
    """Check if IP is still blocked by the permanent jail chain or the
    AbuseIPDB blacklist ipset. Uses iptables/ipset directly - calling
    fail2ban-client from inside an action can deadlock."""
    try:
        result = subprocess.run(
            [IPTABLES, '-C', f'f2b-{PERMANENT_JAIL}', '-s', ip_address,
             '-j', 'REJECT', '--reject-with', 'icmp-port-unreachable'],
            capture_output=True, timeout=5
        )
        if result.returncode == 0:
            return True
    except Exception:
        pass
    try:
        result = subprocess.run(
            [IPSET, 'test', IPSET_BLACKLIST, ip_address],
            capture_output=True, timeout=5
        )
        return result.returncode == 0
    except Exception:
        return False

def escalate_to_permanent_ban(ip_address):
    """Append IP to the abuseipdb jail's logfile so fail2ban bans it with
    bantime=-1 (forever). Writing to the watched log instead of calling
    fail2ban-client avoids re-entering the fail2ban server from an action."""
    try:
        with open(ABUSEIPDB_LOG, 'a') as f:
            f.write(ip_address + '\n')
        print(f"Escalated {ip_address} to permanent ban via '{PERMANENT_JAIL}' jail", file=sys.stderr)
        return True
    except Exception as e:
        print(f"Error escalating {ip_address} to permanent ban: {e}", file=sys.stderr)
        return False

def format_telegram_message(action, jail, ip_address, attempts, geoip_data, abuse_data, escalated=False):
    """Format the Telegram alert message with full details"""

    server_name = get_hostname()

    banned = action.lower() == "banned"
    header_emoji = "🚫" if banned else "✅"
    message = f"{header_emoji} <b>Fail2Ban Alert — {'BANNED' if banned else 'UNBANNED'}</b>\n"
    message += f"<b>Server:</b> {esc(server_name)}\n"
    message += f"<b>Jail:</b> {esc(jail)}\n"
    message += f"<b>Host:</b> {esc(ip_address)}\n"
    message += f"<b>Attempts:</b> {esc(attempts)}"

    # Explain what Attempts means
    if attempts == "0":
        message += " (Preemptive block - from AbuseIPDB blacklist)"
    else:
        message += " (Failed login attempts detected)"

    # Action line: make ban state explicit
    if banned:
        if jail == PERMANENT_JAIL:
            message += f"\n<b>Action:</b> ⛔ Banned PERMANENTLY (AbuseIPDB jail, never expires)\n"
        else:
            message += f"\n<b>Action:</b> 🚫 Banned (temporary, expires per jail bantime)\n"
            if escalated:
                message += f"⛔ <b>Escalated to PERMANENT ban</b> (AbuseIPDB score ≥ {PERMANENT_SCORE_THRESHOLD}%)\n"
    else:
        message += f"\n<b>Action:</b> ✅ Unbanned (temporary ban expired)\n"
        if is_permanently_banned(ip_address):
            message += f"⛔ <b>Still PERMANENTLY blocked</b> via AbuseIPDB blacklist\n"
        else:
            message += f"⚠️ This IP is no longer blocked\n"
    message += f"<b>Time:</b> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
    
    # GeoIP Information
    if geoip_data is not None:
        message += f"\n🌍 <b>GeoIP Information</b>\n"
        
        # Country
        country_code = geoip_data.get('country', 'N/A')
        if country_code and country_code != 'N/A':
            flag = country_flag(country_code)
            message += f"<b>Country:</b> {flag + ' ' if flag else ''}{esc(country_code)}\n"
        
        # Region
        region = geoip_data.get('region', 'N/A')
        if region and region != 'N/A':
            message += f"<b>Region:</b> {esc(region)}\n"
        
        # City
        city = geoip_data.get('city', 'N/A')
        if city and city != 'N/A':
            message += f"<b>City:</b> {esc(city)}\n"
        
        # Timezone
        timezone = geoip_data.get('timezone', 'N/A')
        if timezone and timezone != 'N/A':
            message += f"<b>Timezone:</b> {esc(timezone)}\n"
        
        # ASN/Org
        org = geoip_data.get('org', 'N/A')
        if org and org != 'N/A':
            message += f"<b>ASN/Org:</b> {esc(org)}\n"
    
    # Abuse Information
    if abuse_data:
        message += f"\n⚠️ <b>AbuseIPDB Report</b>\n"
        
        abuse_score = abuse_data.get('abuseConfidenceScore', 0)
        total_reports = abuse_data.get('totalReports', 0)
        
        # Abuse score with emoji indicator
        if abuse_score >= 75:
            emoji = "🔴"
            risk = "CRITICAL"
        elif abuse_score >= 50:
            emoji = "🟠"
            risk = "HIGH"
        elif abuse_score >= 25:
            emoji = "🟡"
            risk = "MEDIUM"
        else:
            emoji = "🟢"
            risk = "LOW"
        
        message += f"{emoji} <b>Abuse Score:</b> {abuse_score}% ({risk})\n"
        message += f"<b>Total Reports:</b> {total_reports}\n"
        
        # ISP and Domain
        isp = abuse_data.get('isp', '')
        if isp:
            message += f"<b>ISP:</b> {esc(isp)}\n"
        
        domain = abuse_data.get('domain', '')
        if domain:
            message += f"<b>Domain:</b> {esc(domain)}\n"
        
        # Usage Type
        usage = abuse_data.get('usageType', '')
        if usage:
            message += f"<b>Usage Type:</b> {esc(usage)}\n"
        
        # Is Tor?
        is_tor = abuse_data.get('isTor', False)
        if is_tor:
            message += f"🔐 <b>Tor Node:</b> Yes\n"
        
        # Threat Assessment
        distinct_users = abuse_data.get('numDistinctUsers', 0)
        if distinct_users > 0:
            message += f"<b>Distinct Users Reporting:</b> {distinct_users}\n"
        
        # Last reported
        last_report = abuse_data.get('lastReportedAt', '')
        if last_report:
            message += f"<b>Last Reported:</b> {esc(last_report)}\n"
    
    return message

def send_telegram_alert(message):
    """Send alert message to Telegram"""
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = {
            'chat_id': TELEGRAM_CHAT_ID,
            'text': message,
            'parse_mode': 'HTML'
        }
        
        response = requests.post(url, json=data, timeout=10)
        
        if response.status_code == 200:
            print("Telegram alert sent successfully", file=sys.stderr)
            return True
        else:
            try:
                error_msg = response.json()
            except Exception:
                error_msg = response.text or str(response.status_code)
            print(f"Failed to send Telegram alert: {error_msg}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"Error sending Telegram alert: {e}", file=sys.stderr)
        return False

def report_to_abuseipdb(ip_address):
    """Report IP to AbuseIPDB"""
    try:
        headers = {
            'Key': ABUSEIPDB_API_KEY,
            'Accept': 'application/json'
        }
        data = {
            'ip': ip_address,
            'category': REPORT_CATEGORIES,  # default 18,22,23: SSH Exploit, Malware, Spam Bot
            'comment': f'Banned by Fail2Ban on {get_hostname()}'
        }
        
        response = requests.post(
            'https://api.abuseipdb.com/api/v2/report',
            headers=headers,
            data=data,
            timeout=5
        )
        
        if response.status_code == 200:
            print(f"IP {ip_address} reported to AbuseIPDB", file=sys.stderr)
    except Exception as e:
        print(f"Error reporting to AbuseIPDB: {e}", file=sys.stderr)

def main():
    """Main execution"""
    
    # Get parameters from fail2ban
    action = sys.argv[1] if len(sys.argv) > 1 else "Banned"
    jail = sys.argv[2] if len(sys.argv) > 2 else "unknown"
    ip_address = sys.argv[3] if len(sys.argv) > 3 else "0.0.0.0"
    attempts = sys.argv[4] if len(sys.argv) > 4 else "1"

    # Connectivity/installation test: send a simple confirmation and exit,
    # skipping the GeoIP/AbuseIPDB lookups, escalation and reporting.
    # Exit status reflects whether Telegram accepted the message.
    if action.lower() == "test":
        server_name = get_hostname()
        test_msg = (
            "✅ <b>Geo-Fail2Ban — Test Alert</b>\n"
            f"<b>Server:</b> {esc(server_name)}\n"
            f"<b>Time:</b> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
            "Installation complete — Telegram alerts are working. 🎉"
        )
        sys.exit(0 if send_telegram_alert(test_msg) else 1)

    # Only ban/unban events produce an alert. Fail2ban also invokes actions on
    # jail start/stop; those carry no real IP (0.0.0.0) and previously fell
    # through to the unban branch, so every 'systemctl restart fail2ban' sent
    # one bogus "UNBANNED 0.0.0.0" message per jail and burned an ipinfo.io +
    # AbuseIPDB lookup on it. telegram.conf no longer wires those up, but stay
    # defensive so a stale action file can't resurrect the behaviour.
    if action.lower() not in ("banned", "unbanned"):
        print(f"Ignoring non-ban action '{action}' for jail '{jail}'", file=sys.stderr)
        return

    print(f"Processing alert: {action} - {jail} - {ip_address} - attempts: {attempts}", file=sys.stderr)
    
    # Get GeoIP and abuse info
    geoip_data = get_geoip_info(ip_address)
    abuse_data = get_abuseipdb_info(ip_address)

    # Escalate to permanent ban: any banned IP known to AbuseIPDB with a high
    # confidence score gets fed into the permanent 'abuseipdb' jail.
    # Skip when the ban already comes from the permanent jail itself.
    escalated = False
    if action.lower() == "banned" and jail != PERMANENT_JAIL and abuse_data:
        score = abuse_data.get('abuseConfidenceScore', 0)
        if score >= PERMANENT_SCORE_THRESHOLD:
            escalated = escalate_to_permanent_ban(ip_address)

    # Format message
    message = format_telegram_message(action, jail, ip_address, attempts, geoip_data, abuse_data, escalated)

    # Send to Telegram
    send_telegram_alert(message)

    # Report to AbuseIPDB if banning (skip the permanent jail's ban event -
    # the originating jail already reported this IP)
    if action.lower() == "banned" and jail != PERMANENT_JAIL:
        report_to_abuseipdb(ip_address)

if __name__ == "__main__":
    main()
