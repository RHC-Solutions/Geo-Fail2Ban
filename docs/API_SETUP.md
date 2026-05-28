# API Setup Guide

This guide walks you through setting up the required APIs for Geo-Fail2Ban.

## Telegram Bot Setup

### Step 1: Create a Telegram Bot

1. Open Telegram and search for **@BotFather**
2. Start the chat and send `/start`
3. Send `/newbot`
4. Follow the prompts:
   - Enter a name: `Geo-Fail2Ban` (or your choice)
   - Enter a username: `geo_fail2ban_bot` (or similar, must end with `_bot`)
5. BotFather will provide your **Bot Token**

Example token: `REDACTED-TELEGRAM-BOT-TOKEN`

### Step 2: Get Your Chat ID

#### Option A: Direct Message (Simple)
1. Send a message to your bot: `/start`
2. Open this URL in browser: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
3. Replace `<YOUR_BOT_TOKEN>` with your token
4. Look for `"chat":{"id":XXXXX}` - that's your Chat ID

#### Option B: Group Chat
1. Add your bot to a group
2. Send any message
3. Use the URL from above to find the Chat ID (negative for groups)

Example Chat ID: `REDACTED-TELEGRAM-CHAT-ID` (group) or `123456789` (direct)

### Step 3: Update .env

```bash
TELEGRAM_BOT_TOKEN="your_token_here"
TELEGRAM_CHAT_ID="your_chat_id_here"
```

### Testing

```bash
curl -X POST https://api.telegram.org/bot{TOKEN}/sendMessage \
  -d chat_id={CHAT_ID} \
  -d text="Test message" \
  -d parse_mode="HTML"
```

---

## ipinfo.io API Setup

### Step 1: Create Account

1. Go to https://ipinfo.io
2. Click "Sign Up" (free tier available)
3. Create account with email
4. Verify email

### Step 2: Get API Token

1. Log in to https://ipinfo.io
2. Click your profile → Settings
3. Under "Token" you'll see your **API Token** (32 characters)

Example token: `REDACTED-IPINFO-TOKEN`

### Step 3: Verify Rate Limits

Free tier: 50,000 requests/month (~1,650/day)
- Each IP lookup = 1 request
- Recommended for small/medium servers

Paid tiers available for higher volume.

### Step 4: Update .env

```bash
IPINFO_API_TOKEN="your_token_here"
```

### Testing

```bash
curl "https://ipinfo.io/8.8.8.8?token=your_token_here"
```

Expected response:
```json
{
  "ip": "8.8.8.8",
  "country": "US",
  "city": "Mountain View",
  "region": "California",
  "loc": "37.4056,-122.0775",
  "timezone": "America/Los_Angeles",
  "org": "AS15169 Google LLC"
}
```

---

## AbuseIPDB API Setup

### Step 1: Create Account

1. Go to https://www.abuseipdb.com
2. Click "Sign Up" (free tier available)
3. Fill in registration details
4. Verify email

### Step 2: Get API Key

1. Log in to https://www.abuseipdb.com
2. Click Account → API
3. Copy your **API Key** (64 characters)

Example key: `REDACTED-ABUSEIPDB-KEY`

### Step 3: Check Rate Limits

Free tier: 1,000 API calls/day
- Each IP report = 1 API call
- Sufficient for most deployments

Premium tiers for higher volume.

### Step 4: Update .env

```bash
ABUSEIPDB_API_KEY="your_key_here"
```

### Testing

```bash
curl -G https://api.abuseipdb.com/api/v2/check \
  -d "ipAddress=8.8.8.8" \
  -d "maxAgeInDays=90" \
  -H "Key: your_api_key_here" \
  -H "Accept: application/json"
```

Expected response includes `abuseConfidenceScore` and report details.

---

## Complete .env File

Once all APIs are configured:

```bash
sudo nano config/.env
```

Fill in all values:

```
TELEGRAM_BOT_TOKEN="REDACTED-TELEGRAM-BOT-TOKEN"
TELEGRAM_CHAT_ID="REDACTED-TELEGRAM-CHAT-ID"
IPINFO_API_TOKEN="REDACTED-IPINFO-TOKEN"
ABUSEIPDB_API_KEY="REDACTED-ABUSEIPDB-KEY"
SERVER_NAME="my-server"
SERVER_LOCATION="Datacenter"
BAN_TIME=86400
MAX_RETRIES=5
FIND_TIME=3600
ABUSE_THRESHOLD=75
REPORT_CATEGORIES="18,22,23"
```

---

## Verify All APIs

Run the test script:

```bash
sudo bash tests/test_alert.sh
```

Or manually test each:

### Test Telegram
```bash
sudo python3 -c "
from scripts.telegram_alert import send_telegram_alert
send_telegram_alert('Test IP', 'Test Alert', 'Test Country', '1', 'Ban', 'Test Server')
"
```

### Test ipinfo.io
```bash
python3 -c "
import requests
token = 'your_token'
resp = requests.get(f'https://ipinfo.io/8.8.8.8?token={token}')
print(resp.json())
"
```

### Test AbuseIPDB
```bash
python3 -c "
import requests
headers = {
    'Key': 'your_api_key',
    'Accept': 'application/json'
}
params = {'ipAddress': '8.8.8.8', 'maxAgeInDays': '90'}
resp = requests.get('https://api.abuseipdb.com/api/v2/check', params=params, headers=headers)
print(resp.json())
"
```

---

## API Costs

| Service | Free Tier | Limit | Cost Beyond |
|---------|-----------|-------|-------------|
| Telegram | ✓ Unlimited | None | N/A |
| ipinfo.io | ✓ | 50k/month | $0.08/1k |
| AbuseIPDB | ✓ | 1k calls/day | $35/mo for unlimited |

---

## Security Notes

⚠️ **IMPORTANT**
- Never commit `.env` file to git
- Keep API keys confidential
- Use `.gitignore` to prevent accidental commits
- Rotate keys periodically
- Consider using environment variables in production

