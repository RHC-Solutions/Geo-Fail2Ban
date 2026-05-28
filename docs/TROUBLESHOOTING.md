# Troubleshooting Guide

## Common Issues and Solutions

### Installation Issues

#### Issue: "Permission denied" when running install.sh

**Problem**: Script not executable or not running as root.

**Solution**:
```bash
# Make script executable
chmod +x install.sh

# Run as root
sudo bash install.sh
```

#### Issue: "fail2ban: command not found"

**Problem**: fail2ban not installed.

**Solution**:
```bash
sudo apt-get update
sudo apt-get install -y fail2ban
```

#### Issue: "ModuleNotFoundError: No module named 'geoip2'"

**Problem**: Python dependencies not installed.

**Solution**:
```bash
sudo apt-get install -y python3-geoip2
sudo pip3 install requests --break-system-packages
```

---

### Configuration Issues

#### Issue: Alerts not sending via Telegram

**Symptoms**: No Telegram messages when IPs are banned.

**Diagnosis**:
```bash
# 1. Check if .env exists
sudo test -f config/.env && echo "✓ .env exists" || echo "✗ .env missing"

# 2. Verify credentials
sudo grep TELEGRAM config/.env

# 3. Check if script is executable
sudo test -x /opt/fail2ban-scripts/telegram_alert.py && echo "✓ Executable" || echo "✗ Not executable"

# 4. Check fail2ban logs
sudo tail -20 /var/log/fail2ban.log | grep -i telegram
```

**Solutions**:

1. **Missing .env file**:
   ```bash
   sudo cp config/.env.example config/.env
   sudo nano config/.env
   # Fill in your API keys
   ```

2. **Invalid Telegram credentials**:
   ```bash
   # Test Telegram API directly
   BOTTOKEN="your_token_here"
   CHATID="your_chat_id_here"
   curl -X POST "https://api.telegram.org/bot$BOTTOKEN/sendMessage" \
     -d "chat_id=$CHATID" \
     -d "text=Test message"
   ```

3. **Network connectivity**:
   ```bash
   # Test internet access
   curl -I https://api.telegram.org
   
   # Check DNS
   nslookup api.telegram.org
   ```

---

### Ban and Detection Issues

#### Issue: "Attempts: 0" shown in alerts (preemptive blocks)

**Explanation**: This is NOT an error. It means the IP was blocked by AbuseIPDB before it attempted an attack on your server.

**Context**:
- `Attempts: 5+` = IP attacked your server
- `Attempts: 0` = AbuseIPDB blocked it preemptively

Both are valid security actions.

---

#### Issue: IPs not being banned

**Symptoms**: Repeated failed SSH attempts but no bans occurring.

**Diagnosis**:
```bash
# 1. Check if jail is active
sudo fail2ban-client status sshd

# 2. Check ban time
sudo fail2ban-client get sshd bantime

# 3. Check max retries setting
sudo fail2ban-client get sshd maxretry

# 4. Check if filter is catching attempts
sudo fail2ban-client get sshd logpath
```

**Solutions**:

1. **Jail not enabled**:
   ```bash
   sudo fail2ban-client set sshd enabled true
   sudo systemctl restart fail2ban
   ```

2. **Wrong log path**:
   ```bash
   # Verify log file exists
   sudo test -f /var/log/auth.log && echo "✓ Log file exists"
   
   # Check permissions
   sudo ls -l /var/log/auth.log
   ```

3. **Filter not matching**:
   ```bash
   # Check if SSH failures are in log
   sudo grep "Failed password" /var/log/auth.log | tail -5
   
   # Test filter manually
   sudo fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf
   ```

---

#### Issue: Banning too aggressively (false positives)

**Symptoms**: Legitimate users getting banned, support complaints.

**Solutions**:

1. **Increase attempts threshold**:
   ```bash
   # Edit jail.local
   sudo nano /etc/fail2ban/jail.local
   
   # Change maxretry value
   [sshd]
   maxretry = 10  # Increased from 5
   
   # Restart
   sudo systemctl restart fail2ban
   ```

2. **Increase time window**:
   ```bash
   [sshd]
   findtime = 7200  # 2 hours instead of 1 hour
   ```

3. **Whitelist trusted IPs**:
   ```bash
   # Edit jail.local
   [sshd]
   ignoreip = 127.0.0.1/8 203.0.113.10 203.0.113.20
   ```

---

### AbuseIPDB Integration Issues

#### Issue: AbuseIPDB blocker not running

**Symptoms**: `/var/log/fail2ban-abuseipdb.log` not updating.

**Diagnosis**:
```bash
# 1. Check if cron job exists
sudo cat /etc/cron.d/fail2ban-abuseipdb

# 2. Check cron logs
sudo grep CRON /var/log/syslog | tail -20

# 3. Run script manually
sudo python3 /opt/fail2ban-scripts/abuseipdb_blocker.py
```

**Solutions**:

1. **Missing cron job**:
   ```bash
   sudo bash -c 'cat > /etc/cron.d/fail2ban-abuseipdb << "EOF"
   0 * * * * root /opt/fail2ban-scripts/abuseipdb_blocker.py >> /var/log/fail2ban-abuseipdb.log 2>&1
   EOF'
   ```

2. **Invalid API key**:
   ```bash
   # Verify key in .env
   sudo grep ABUSEIPDB config/.env
   
   # Test API directly
   curl -G https://api.abuseipdb.com/api/v2/check \
     -d "ipAddress=8.8.8.8" \
     -d "maxAgeInDays=90" \
     -H "Key: YOUR_API_KEY_HERE" \
     -H "Accept: application/json"
   ```

3. **Rate limiting**:
   - Check error logs: `sudo tail -50 /var/log/fail2ban-abuseipdb.log`
   - Wait for rate limit window to reset (usually 1 hour)
   - Consider upgrading API plan if hitting limits frequently

---

### Firewall Issues

#### Issue: Can't connect to SSH after setup

**Symptoms**: SSH connection times out or refused.

**Diagnosis**:
```bash
# 1. Check UFW status
sudo ufw status

# 2. View SSH-related rules
sudo ufw status | grep 22

# 3. Check if port 22 is open
sudo netstat -tlnp | grep 22
```

**Solutions**:

1. **IP not in whitelist**:
   ```bash
   # Add your IP to whitelist
   echo "YOUR.IP.HERE" | sudo tee -a config/whitelist.txt
   
   # Reapply firewall rules
   sudo bash scripts/setup-firewall.sh
   ```

2. **UFW rule precedence issue**:
   ```bash
   # View all rules
   sudo ufw status numbered
   
   # Delete conflicting rule (by number)
   sudo ufw delete <number>
   
   # Reapply
   sudo bash scripts/setup-firewall.sh
   ```

3. **Emergency reset**:
   ```bash
   # Disable UFW temporarily (USE WITH CAUTION)
   sudo ufw disable
   
   # Add your IP to whitelist
   echo "YOUR.IP.HERE" | sudo tee -a config/whitelist.txt
   
   # Re-enable with correct rules
   sudo ufw enable
   sudo bash scripts/setup-firewall.sh
   ```

---

### GeoIP/API Issues

#### Issue: GeoIP data not showing in alerts

**Symptoms**: Alerts show "Unknown" for country/city.

**Diagnosis**:
```bash
# 1. Test ipinfo.io API
curl "https://ipinfo.io/8.8.8.8?token=YOUR_TOKEN"

# 2. Check if token is valid
sudo grep IPINFO config/.env

# 3. Check script output
sudo tail -20 /var/log/fail2ban.log
```

**Solutions**:

1. **Invalid API token**:
   ```bash
   # Verify token at https://ipinfo.io
   sudo nano config/.env
   # Update IPINFO_API_TOKEN
   ```

2. **API rate limit exceeded**:
   ```bash
   # Free tier: 50,000/month
   # Check usage at https://ipinfo.io
   
   # Upgrade plan if needed or wait for reset
   ```

3. **Network issue**:
   ```bash
   # Test connectivity
   curl -I https://ipinfo.io
   
   # Check DNS
   nslookup ipinfo.io
   ```

---

### Logging and Monitoring Issues

#### Issue: No logs being generated

**Diagnosis**:
```bash
# Check log directory
sudo ls -la /var/log/fail2ban-geo/

# Check main fail2ban log
sudo ls -la /var/log/fail2ban.log

# Check permissions
sudo test -r /var/log/fail2ban.log && echo "✓ Readable"
```

**Solutions**:

1. **Create missing directories**:
   ```bash
   sudo mkdir -p /var/log/fail2ban-geo
   sudo chown root:root /var/log/fail2ban-geo
   sudo chmod 755 /var/log/fail2ban-geo
   ```

2. **Check fail2ban service**:
   ```bash
   sudo systemctl status fail2ban
   sudo systemctl restart fail2ban
   ```

---

### Performance Issues

#### Issue: High CPU usage

**Diagnosis**:
```bash
# Check top processes
top -b -n 1 | grep -E "fail2ban|python3"

# Check jail status
sudo fail2ban-client status
```

**Solutions**:

1. **Too many active jails**: Disable unused jails in `/etc/fail2ban/jail.local`
2. **Increase findtime**: Longer detection windows reduce CPU
3. **Increase maxretry**: Higher threshold reduces false positives

---

## Debug Mode

### Enable Debug Logging

```bash
# Edit .env
sudo nano config/.env
LOG_LEVEL="DEBUG"

# Restart fail2ban
sudo systemctl restart fail2ban

# View detailed logs
sudo tail -f /var/log/fail2ban.log
```

### Manual Script Testing

```bash
# Test alert script
sudo python3 /opt/fail2ban-scripts/telegram_alert.py 192.168.1.1 sshd ban

# Test blocker script
sudo python3 /opt/fail2ban-scripts/abuseipdb_blocker.py

# Verbose output
sudo python3 -u /opt/fail2ban-scripts/telegram_alert.py 192.168.1.1 sshd ban 2>&1
```

---

## Getting Help

1. **Check logs first**:
   ```bash
   sudo tail -50 /var/log/fail2ban.log
   sudo tail -50 /var/log/fail2ban-abuseipdb.log
   ```

2. **Verify configuration**:
   ```bash
   sudo fail2ban-client status
   sudo fail2ban-client get sshd all
   ```

3. **Test APIs independently**:
   - Telegram: Send test message via `curl`
   - ipinfo.io: Query test IP
   - AbuseIPDB: Check API key validity

4. **Review documentation**:
   - [INSTALLATION.md](INSTALLATION.md)
   - [CONFIGURATION.md](CONFIGURATION.md)
   - [API_SETUP.md](API_SETUP.md)

