#!/usr/bin/env python3
"""
AbuseIPDB Blocker - Automatically blocks IPs from AbuseIPDB
"""

import requests
import sys
import json
from datetime import datetime
import subprocess

ABUSEIPDB_API_KEY = "REDACTED-ABUSEIPDB-KEY"
ABUSE_SCORE_THRESHOLD = 75  # Block IPs with score >= 75%
F2B_BLACKLIST_JAIl = "abuseipdb-blacklist"

def get_blacklisted_ips():
    """Get list of high-abuse IPs from AbuseIPDB"""
    try:
        headers = {
            'Key': ABUSEIPDB_API_KEY,
            'Accept': 'application/json'
        }
        params = {
            'limit': 10000,
            'abuseScore': ABUSE_SCORE_THRESHOLD
        }
        
        response = requests.get(
            'https://api.abuseipdb.com/api/v2/blacklist',
            headers=headers,
            params=params,
            timeout=15
        )
        
        if response.status_code == 200:
            data = response.json()
            ips = [line.split(',')[0] for line in data.get('data', '').strip().split('\n') if line]
            return ips
        else:
            print(f"Failed to fetch blacklist: {response.text}", file=sys.stderr)
            return []
    except Exception as e:
        print(f"Error fetching AbuseIPDB blacklist: {e}", file=sys.stderr)
        return []

def add_to_fail2ban(ip_address):
    """Add IP to fail2ban blacklist jail"""
    try:
        cmd = [
            'fail2ban-client',
            'set',
            F2B_BLACKLIST_JAIl,
            'banip',
            ip_address
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        
        if result.returncode == 0:
            print(f"Added {ip_address} to fail2ban blacklist", file=sys.stderr)
            return True
        else:
            print(f"Failed to add {ip_address}: {result.stderr}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"Error adding to fail2ban: {e}", file=sys.stderr)
        return False

def main():
    """Main execution"""
    
    print(f"[{datetime.now().isoformat()}] Fetching AbuseIPDB blacklist...", file=sys.stderr)
    
    # Get blacklisted IPs
    ips = get_blacklisted_ips()
    
    if not ips:
        print("No IPs to block", file=sys.stderr)
        return
    
    print(f"Found {len(ips)} IPs to block", file=sys.stderr)
    
    # Add each IP to fail2ban
    blocked_count = 0
    for ip in ips[:100]:  # Limit to 100 IPs per run
        if add_to_fail2ban(ip):
            blocked_count += 1
    
    print(f"Blocked {blocked_count} IPs from AbuseIPDB", file=sys.stderr)

if __name__ == "__main__":
    main()
