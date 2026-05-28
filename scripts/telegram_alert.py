#!/usr/bin/env python3
"""
Fail2Ban Telegram Alert Script with GeoIP and AbuseIPDB Integration
"""

import sys
import json
import requests
import socket
import os
import subprocess
from datetime import datetime

# Configuration
TELEGRAM_BOT_TOKEN = "6409269239:AAF1PeehGQRCd1HAkBAvaTZYG3ncRJqX1-M"
TELEGRAM_CHAT_ID = "-1002402681303"
ABUSEIPDB_API_KEY = "d46b7b95df00f6115459e2593e7ea5c7ad954383128fe60da683871e84068a32e0109c2ebdc0bf67"
IPINFO_API_TOKEN = "e7dda13207bb37"

def get_hostname():
    """Get actual server hostname"""
    try:
        hostname = subprocess.check_output(['hostname', '-f'], text=True).strip()
        if not hostname:
            hostname = socket.getfqdn()
        return hostname
    except:
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
            print(f"DEBUG: GeoIP response: {json.dumps(data, indent=2)}", file=sys.stderr)
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

def format_telegram_message(action, jail, ip_address, attempts, geoip_data, abuse_data):
    """Format the Telegram alert message with full details"""
    
    server_name = get_hostname()
    
    message = f"🚫 <b>Fail2Ban Alert</b>\n"
    message += f"<b>Server:</b> {server_name}\n"
    message += f"<b>Jail:</b> {jail}\n"
    message += f"<b>Host:</b> {ip_address}\n"
    message += f"<b>Attempts:</b> {attempts}"
    
    # Explain what Attempts means
    if attempts == "0":
        message += " (Preemptive block - from AbuseIPDB blacklist)"
    else:
        message += " (Failed login attempts detected)"
    
    message += f"\n<b>Action:</b> {action}\n"
    message += f"<b>Time:</b> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
    
    # GeoIP Information
    if geoip_data and geoip_data.get('success'):
        message += f"\n🌍 <b>GeoIP Information</b>\n"
        
        # Country
        country_code = geoip_data.get('country', 'N/A')
        if country_code and country_code != 'N/A':
            message += f"<b>Country:</b> {country_code}\n"
        
        # Region
        region = geoip_data.get('region', 'N/A')
        if region and region != 'N/A':
            message += f"<b>Region:</b> {region}\n"
        
        # City
        city = geoip_data.get('city', 'N/A')
        if city and city != 'N/A':
            message += f"<b>City:</b> {city}\n"
        
        # Timezone
        timezone = geoip_data.get('timezone', 'N/A')
        if timezone and timezone != 'N/A':
            message += f"<b>Timezone:</b> {timezone}\n"
        
        # ASN/Org
        org = geoip_data.get('org', 'N/A')
        if org and org != 'N/A':
            message += f"<b>ASN/Org:</b> {org}\n"
    
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
            message += f"<b>ISP:</b> {isp}\n"
        
        domain = abuse_data.get('domain', '')
        if domain:
            message += f"<b>Domain:</b> {domain}\n"
        
        # Usage Type
        usage = abuse_data.get('usageType', '')
        if usage:
            message += f"<b>Usage Type:</b> {usage}\n"
        
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
            message += f"<b>Last Reported:</b> {last_report}\n"
    
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
            error_msg = response.json() if response.status_code != 200 else str(response.status_code)
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
            'category': '18,22,23',  # Categories: SSH Exploit, Malware, Spam Bot
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
    
    print(f"Processing alert: {action} - {jail} - {ip_address} - attempts: {attempts}", file=sys.stderr)
    
    # Get GeoIP and abuse info
    geoip_data = get_geoip_info(ip_address)
    abuse_data = get_abuseipdb_info(ip_address)
    
    # Format message
    message = format_telegram_message(action, jail, ip_address, attempts, geoip_data, abuse_data)
    
    # Send to Telegram
    send_telegram_alert(message)
    
    # Report to AbuseIPDB if banning
    if action.lower() == "banned":
        report_to_abuseipdb(ip_address)

if __name__ == "__main__":
    main()
