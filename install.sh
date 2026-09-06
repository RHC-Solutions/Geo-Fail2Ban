#!/bin/bash
#
# Geo-Fail2Ban Installation Script
# Telegram alerts, GeoIP enrichment, AbuseIPDB permanent bans, country geoblock.
#
# Usage:  sudo bash install.sh [--skip-geo]
#   --skip-geo   don't download country zone files / enable the geoblock ipset
#

set -e
cd "$(dirname "$0")"

SKIP_GEO=0
[ "${1:-}" = "--skip-geo" ] && SKIP_GEO=1

# Seconds to wait on each interactive prompt before auto-skipping. Override with
# PROMPT_TIMEOUT=N sudo -E bash install.sh
PROMPT_TIMEOUT="${PROMPT_TIMEOUT:-60}"

# Where all program files are installed. Override with: INSTALL_DIR=/path sudo -E bash install.sh
INSTALL_DIR="${INSTALL_DIR:-/opt/geo-fail2ban}"
LEGACY_DIR="/opt/fail2ban-scripts"   # previous default; cleaned up on upgrade

# Firewall backend abstraction (auto-detects firewalld / ufw / iptables)
. scripts/firewall-lib.sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    echo "Please run: sudo bash install.sh"
    exit 1
fi

print_header "Geo-Fail2Ban Installation"
print_info "Install directory: $INSTALL_DIR"

# Step 1: Configuration (interactive — each question auto-skips after PROMPT_TIMEOUT seconds, default 60)
print_header "Configuration"
CONF=/etc/geo-fail2ban.conf
echo "Answer each prompt, or press Enter / wait ${PROMPT_TIMEOUT}s to skip (keeps the shown value)."
echo ""

# Defaults: an existing config, else a pre-filled config/.env, else blank.
if [ -f "$CONF" ]; then
    print_info "Existing $CONF found - its values are the defaults."
    # shellcheck disable=SC1090
    . "$CONF" 2>/dev/null || true
elif [ -f config/.env ]; then
    # shellcheck disable=SC1090
    . config/.env 2>/dev/null || true
fi

# ask <VAR> <prompt> [secret] — waits PROMPT_TIMEOUT seconds; keeps the current value on skip.
ask() {
    local __var="$1" __prompt="$2" __secret="${3:-}" __cur="${!1:-}" __ans="" __show="${!1:-}"
    [ "$__secret" = "secret" ] && [ -n "$__cur" ] && __show="********"
    if [ -n "$__cur" ]; then
        read -t "$PROMPT_TIMEOUT" -r -p "  ${__prompt} [${__show}]: " __ans || true
    else
        read -t "$PROMPT_TIMEOUT" -r -p "  ${__prompt} (Enter/${PROMPT_TIMEOUT}s to skip): " __ans || true
    fi
    echo
    [ -n "$__ans" ] && printf -v "$__var" '%s' "$__ans"
    return 0   # never let an empty answer (skip) trip 'set -e' in the caller
}

ask TELEGRAM_BOT_TOKEN "Telegram bot token"   secret
ask TELEGRAM_CHAT_ID   "Telegram chat ID"
ask IPINFO_API_TOKEN   "ipinfo.io API token"  secret
ask ABUSEIPDB_API_KEY  "AbuseIPDB API key"    secret

read -t "$PROMPT_TIMEOUT" -r -p "  Trusted whitelist IPs, space-separated (Enter/${PROMPT_TIMEOUT}s to skip): " WL_IPS || true
echo

# Geoblock downloads country zone files; ask unless --skip-geo was passed.
# On update, default to the state it's already in (enabled if its cron/unit
# exists), so skipping keeps the current setting instead of forcing a default.
if [ "$SKIP_GEO" -eq 0 ]; then
    if [ -f /etc/cron.d/ipset-geo ] || [ -f /etc/systemd/system/ipset-geo.service ]; then
        _geo_def="Y" _geo_hint="Y/n"          # currently enabled -> keep enabled on skip
    elif [ -f "$CONF" ]; then
        _geo_def="N" _geo_hint="y/N"          # config exists, geoblock not installed -> keep disabled
    else
        _geo_def="Y" _geo_hint="Y/n"          # fresh install -> default on
    fi
    read -t "$PROMPT_TIMEOUT" -r -p "  Enable country geoblock (downloads zone files)? (${_geo_hint}, ${PROMPT_TIMEOUT}s): " _geo || true
    echo
    case "${_geo:-$_geo_def}" in [Nn]*) SKIP_GEO=1 ;; esac
fi

# Country list — only relevant when geoblock is enabled. Pre-seed the default
# from the template so a fresh install shows it; on update the existing value
# (sourced from $CONF above) is shown and kept unless you type a new one.
if [ "$SKIP_GEO" -eq 0 ]; then
    # '=' not ':=' — an existing empty value means "block none" and must survive.
    : "${GEOBLOCK_COUNTRIES=$(grep -E '^GEOBLOCK_COUNTRIES=' config/.env.example | head -1 | cut -d'"' -f2)}"
    ask GEOBLOCK_COUNTRIES "Countries to geoblock (space-separated ipdeny codes)"

    # GEOBLOCK_AFRICA is a second list applied ON TOP of the one above. It used
    # to be applied silently, so ask about it explicitly.
    _afr_all="$(grep -E '^GEOBLOCK_AFRICA=' config/.env.example | head -1 | cut -d'"' -f2)"
    if [ -n "${GEOBLOCK_AFRICA-x}" ]; then
        _afr_def="Y" _afr_hint="Y/n"      # unset (fresh) or non-empty -> currently on
    else
        _afr_def="N" _afr_hint="y/N"      # explicitly empty -> currently off
    fi
    read -t "$PROMPT_TIMEOUT" -r -p "  Also geoblock the whole of Africa ($(echo $_afr_all | wc -w) countries, added on top)? (${_afr_hint}, ${PROMPT_TIMEOUT}s): " _afr || true
    echo
    case "${_afr:-$_afr_def}" in
        [Nn]*) GEOBLOCK_AFRICA="" ;;
        *)     GEOBLOCK_AFRICA="${GEOBLOCK_AFRICA:-$_afr_all}" ;;
    esac
fi

# Seed the config from an existing file or the template, then write the answers.
if [ ! -f "$CONF" ]; then
    if [ -f config/.env ]; then cp config/.env "$CONF"; else cp config/.env.example "$CONF"; fi
fi
set_conf() {  # set_conf KEY VALUE — idempotent; escapes sed metacharacters
    local k="$1" v
    v="$(printf '%s' "$2" | sed -e 's/[&|\\]/\\&/g')"
    if grep -qE "^${k}=" "$CONF"; then
        sed -i "s|^${k}=.*|${k}=\"${v}\"|" "$CONF"
    else
        printf '%s="%s"\n' "$k" "$2" >> "$CONF"
    fi
}
set_conf TELEGRAM_BOT_TOKEN "${TELEGRAM_BOT_TOKEN:-}"
set_conf TELEGRAM_CHAT_ID   "${TELEGRAM_CHAT_ID:-}"
set_conf IPINFO_API_TOKEN   "${IPINFO_API_TOKEN:-}"
set_conf ABUSEIPDB_API_KEY  "${ABUSEIPDB_API_KEY:-}"
# Write both geoblock lists only when geoblock was actually configured this run.
# They are written even when empty — "" is a meaningful answer meaning "block
# nothing from this list". With --skip-geo the prompts never ran, so leave
# whatever is already in $CONF alone.
if [ "$SKIP_GEO" -eq 0 ]; then
    set_conf GEOBLOCK_COUNTRIES "${GEOBLOCK_COUNTRIES-}"
    set_conf GEOBLOCK_AFRICA    "${GEOBLOCK_AFRICA-}"
fi
chmod 600 "$CONF"
print_success "Configuration written to $CONF"

# Save whitelist IPs (one per line) for the firewall step / setup-firewall.sh
if [ -n "${WL_IPS:-}" ]; then
    { echo "# Geo-Fail2Ban whitelist (generated by install.sh)"
      for _ip in $WL_IPS; do echo "$_ip"; done; } > config/whitelist.txt
    print_success "Saved whitelist IPs to config/whitelist.txt"
fi

# Telegram credentials are required for the tool to do anything useful.
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || printf '%s' "${TELEGRAM_BOT_TOKEN}" | grep -q 'YOUR_BOT_TOKEN_HERE'; then
    print_error "A Telegram bot token is required. Re-run and enter it, or edit $CONF."
    exit 1
fi
[ -z "${ABUSEIPDB_API_KEY:-}" ] && print_info "No AbuseIPDB key — reputation checks & blacklist import will be limited."
[ -z "${IPINFO_API_TOKEN:-}" ]  && print_info "No ipinfo.io token — GeoIP enrichment will be limited."

# Pre-flight: if a previous version is installed, uninstall it first.
# --keep-config preserves /etc/geo-fail2ban.conf (your credentials) so the
# fresh install reuses them. Done AFTER config validation above so we never
# tear down a working install only to bail out on a missing/placeholder config.
if [ -d "$INSTALL_DIR" ] || [ -d "$LEGACY_DIR" ] \
   || [ -f /etc/systemd/system/ipset-abuseipdb.service ] \
   || [ -f /etc/fail2ban/jail.d/abuseipdb.conf ] \
   || [ -f /etc/cron.d/fail2ban-abuseipdb ]; then
    print_info "Previous installation detected - uninstalling it first..."
    INSTALL_DIR="$INSTALL_DIR" bash scripts/uninstall.sh --yes --keep-config
    print_success "Previous version removed (kept /etc/geo-fail2ban.conf)"
fi

# Step 2: Install dependencies (fail2ban + ipset + iptables + curl + python requests).
# Cross-distro: pick whichever package manager this system has.
print_info "Installing dependencies..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban ipset iptables curl python3-requests >/dev/null 2>&1 \
        || DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban ipset iptables curl python3-pip >/dev/null 2>&1
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y epel-release >/dev/null 2>&1 || true   # fail2ban lives in EPEL on RHEL
    dnf install -y fail2ban ipset iptables curl python3-requests >/dev/null 2>&1 \
        || dnf install -y fail2ban ipset iptables curl python3-pip >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release >/dev/null 2>&1 || true
    yum install -y fail2ban ipset iptables curl python3-requests >/dev/null 2>&1 \
        || yum install -y fail2ban ipset iptables curl python3-pip >/dev/null 2>&1
elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install fail2ban ipset iptables curl python3-requests >/dev/null 2>&1 || true
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm fail2ban ipset iptables curl python-requests >/dev/null 2>&1 || true
elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache fail2ban ipset iptables curl py3-requests >/dev/null 2>&1 || true
else
    print_error "No supported package manager found (apt/dnf/yum/zypper/pacman/apk)."
    echo "Install manually: fail2ban ipset iptables curl python3-requests"
    exit 1
fi
# Ensure the python 'requests' module is importable regardless of distro packaging
python3 -c 'import requests' 2>/dev/null \
    || pip3 install requests --break-system-packages >/dev/null 2>&1 \
    || pip3 install requests >/dev/null 2>&1 || true
print_success "Dependencies installed"

# Best-effort install of the first candidate package name that exists on this
# distro. Used for optional extras where the package is named differently
# everywhere and a failure is not fatal.
pkg_install_quiet() {
    local p
    for p in "$@"; do
        if command -v apt-get >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$p" >/dev/null 2>&1 && return 0
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y "$p" >/dev/null 2>&1 && return 0
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "$p" >/dev/null 2>&1 && return 0
        elif command -v zypper >/dev/null 2>&1; then
            zypper --non-interactive install "$p" >/dev/null 2>&1 && return 0
        elif command -v pacman >/dev/null 2>&1; then
            pacman -S --noconfirm "$p" >/dev/null 2>&1 && return 0
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache "$p" >/dev/null 2>&1 && return 0
        fi
    done
    return 1
}

# Detect the firewall backend now that iptables/ufw/firewalld are present
FW_BACKEND="$(fw_detect)"
print_info "Firewall backend: $FW_BACKEND"
if [ "$FW_BACKEND" = "none" ]; then
    print_error "No usable firewall backend (need firewalld, ufw, or iptables+ipset)."
    exit 1
fi

# Step 3: Scripts
print_info "Installing scripts to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
cp scripts/telegram_alert.py scripts/abuseipdb_blocker.py "$INSTALL_DIR/"
cp scripts/firewall-lib.sh "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR"/*.py "$INSTALL_DIR/firewall-lib.sh"
print_success "Scripts installed to $INSTALL_DIR"

# Step 4: Fail2ban configuration
print_info "Installing fail2ban configuration..."
[ -f /etc/fail2ban/jail.local ] && cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak
cp fail2ban/jail.local /etc/fail2ban/jail.local
cp fail2ban/jail.d/abuseipdb.conf /etc/fail2ban/jail.d/abuseipdb.conf
cp fail2ban/filter.d/abuseipdb.conf /etc/fail2ban/filter.d/abuseipdb.conf
cp fail2ban/action.d/telegram.conf /etc/fail2ban/action.d/telegram.conf
sed -i "s#/opt/geo-fail2ban#$INSTALL_DIR#g" /etc/fail2ban/action.d/telegram.conf
touch /var/log/abuseipdb.log

# Point the sshd jail at whatever this host actually logs SSH to. The shipped
# jail.local assumes Debian/Ubuntu's /var/log/auth.log; RHEL/Fedora/SUSE use
# /var/log/secure, and several modern distros log only to the journal. Getting
# this wrong means the sshd jail never starts at all.
if [ -f /var/log/auth.log ]; then
    print_info "sshd log source: /var/log/auth.log"
elif [ -f /var/log/secure ]; then
    sed -i 's#^logpath = /var/log/auth.log#logpath = /var/log/secure#' /etc/fail2ban/jail.local
    print_info "sshd log source: /var/log/secure"
else
    sed -i 's#^logpath = /var/log/auth.log#backend = systemd#' /etc/fail2ban/jail.local
    print_info "sshd log source: systemd journal (backend = systemd)"
    # fail2ban's systemd backend needs the python journal bindings.
    if ! python3 -c 'import systemd.journal' 2>/dev/null; then
        pkg_install_quiet python3-systemd systemd-python python-systemd py3-systemd \
            || print_warning "python systemd bindings not found — the sshd jail may fail to start"
    fi
fi
print_success "Fail2ban jails installed (sshd 24h + abuseipdb permanent)"

# Step 5: AbuseIPDB blacklist ipset (permanent, add-only)
print_info "Setting up AbuseIPDB blacklist ipset..."
ipset create abuseipdb-blacklist hash:ip family inet hashsize 16384 maxelem 500000 -exist
fw_block_set abuseipdb-blacklist
cp systemd/ipset-abuseipdb.service /etc/systemd/system/
# firewalld persists its own DROP rule, so the boot unit only restores the ipset.
# For ufw/iptables the unit re-adds the iptables rule at boot.
[ "$FW_BACKEND" = "firewalld" ] && sed -i '/--match-set abuseipdb-blacklist/d' /etc/systemd/system/ipset-abuseipdb.service
print_success "AbuseIPDB blacklist ipset + DROP rule active ($FW_BACKEND)"

# Step 6: Geoblock (optional)
if [ "$SKIP_GEO" -eq 0 ]; then
    print_info "Setting up country geoblock..."
    mkdir -p "$INSTALL_DIR/ipset-geo"
    cp ipset-geo/update.sh "$INSTALL_DIR/ipset-geo/update.sh"
    chmod +x "$INSTALL_DIR/ipset-geo/update.sh"
    cp systemd/ipset-geo.service /etc/systemd/system/
    cp cron/ipset-geo /etc/cron.d/ipset-geo
    sed -i "s#/opt/geo-fail2ban#$INSTALL_DIR#g" /etc/cron.d/ipset-geo
    print_info "Downloading country zone files (this can take a minute)..."
    "$INSTALL_DIR/ipset-geo/update.sh" || print_error "geoblock refresh failed (will retry via daily cron)"
    fw_block_set geoblock
    [ "$FW_BACKEND" = "firewalld" ] && sed -i '/--match-set geoblock/d' /etc/systemd/system/ipset-geo.service
    print_success "Geoblock active (countries from GEOBLOCK_COUNTRIES in /etc/geo-fail2ban.conf)"
else
    print_info "Skipping geoblock (--skip-geo)"
fi

# Step 6b: Optionally apply the SSH/DNS whitelist now (only if IPs were given)
if [ -n "${WL_IPS:-}" ]; then
    print_warning "Restricting SSH/DNS to your whitelist will block all other sources."
    read -t "$PROMPT_TIMEOUT" -r -p "  Apply the SSH/DNS whitelist now via $FW_BACKEND? (y/N, ${PROMPT_TIMEOUT}s): " _apply || true
    echo
    case "${_apply:-}" in
        [Yy]*)
            read -r -a wl_ips_arr <<< "$WL_IPS"
            fw_apply_whitelist "${wl_ips_arr[@]}"
            WL_APPLIED=1
            print_success "Whitelist applied (your current SSH IP was auto-included)."
            ;;
        *)  print_info "Skipped. Apply later with: sudo bash scripts/setup-firewall.sh" ;;
    esac
fi

# Step 7: Persistence + cron
print_info "Enabling boot persistence and cron jobs..."
systemctl daemon-reload
systemctl enable ipset-abuseipdb.service > /dev/null 2>&1
[ "$SKIP_GEO" -eq 0 ] && systemctl enable ipset-geo.service > /dev/null 2>&1
cp cron/fail2ban-abuseipdb /etc/cron.d/fail2ban-abuseipdb
sed -i "s#/opt/geo-fail2ban#$INSTALL_DIR#g" /etc/cron.d/fail2ban-abuseipdb
# Only our own files — a bare /etc/cron.d/* glob would relax the permissions of
# unrelated packages' cron files, some of which are deliberately restricted.
chmod 644 /etc/cron.d/fail2ban-abuseipdb
[ -f /etc/cron.d/ipset-geo ] && chmod 644 /etc/cron.d/ipset-geo
# Keep the three log files this tool writes from growing without bound.
if [ -d /etc/logrotate.d ]; then
    cp logrotate/geo-fail2ban /etc/logrotate.d/geo-fail2ban
    chmod 644 /etc/logrotate.d/geo-fail2ban
fi
print_success "Boot restore services enabled, daily cron + logrotate installed"

# Step 8: First blacklist fetch (best effort - free API allows 5/day)
print_info "Fetching AbuseIPDB blacklist (may hit daily rate limit)..."
"$INSTALL_DIR/abuseipdb_blocker.py" 2>&1 | tail -2 || true
ipset save abuseipdb-blacklist > /etc/ipset-abuseipdb.conf

# Step 9: Restart fail2ban
print_info "Restarting Fail2Ban service..."
systemctl restart fail2ban
sleep 2
print_success "Fail2Ban restarted"

# Step 10: Verify installation
print_header "Verification"

FAIL=0
systemctl is-active --quiet fail2ban \
    && print_success "Fail2Ban service is running" \
    || { print_error "Fail2Ban service is not running"; FAIL=1; }
fail2ban-client status sshd > /dev/null 2>&1 \
    && print_success "sshd jail active (24h bans + Telegram alerts)" \
    || { print_error "sshd jail not active"; FAIL=1; }
fail2ban-client status abuseipdb > /dev/null 2>&1 \
    && print_success "abuseipdb jail active (PERMANENT bans, score >= threshold)" \
    || { print_error "abuseipdb jail not active"; FAIL=1; }
case "${FW_BACKEND:-iptables}" in
    iptables)
        iptables -C INPUT -m set --match-set abuseipdb-blacklist src -j DROP 2>/dev/null \
            && print_success "Blacklist DROP rule present ($(ipset list -t abuseipdb-blacklist | awk '/Number of entries/{print $4}') IPs)" \
            || { print_error "Blacklist DROP rule missing"; FAIL=1; }
        ;;
    firewalld)
        firewall-cmd --permanent --query-rich-rule='rule family="ipv4" source ipset="abuseipdb-blacklist" drop' >/dev/null 2>&1 \
            && print_success "Blacklist DROP rule present ($(ipset list -t abuseipdb-blacklist | awk '/Number of entries/{print $4}') IPs)" \
            || { print_error "Blacklist DROP rule missing"; FAIL=1; }
        ;;
    ufw)
        ufw status 2>/dev/null | grep -qiE 'abuseipdb-blacklist|ipset.*abuseipdb-blacklist' \
            && print_success "Blacklist DROP rule present ($(ipset list -t abuseipdb-blacklist | awk '/Number of entries/{print $4}') IPs)" \
            || { print_error "Blacklist DROP rule missing"; FAIL=1; }
        ;;
    *)
        print_error "Unknown firewall backend '${FW_BACKEND:-unset}'"; FAIL=1;
        ;;
esac
[ "$FAIL" -ne 0 ] && exit 1

# Step 11: Send a full install-status summary to Telegram. This doubles as the
# end-to-end delivery test. Non-fatal: a failure only warns.
send_install_status() {
    [ -z "${TELEGRAM_BOT_TOKEN:-}" ] && return 1
    local host now bl thresh geo wl gc msg
    host="$(hostname -f 2>/dev/null || hostname)"
    now="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    bl="$(ipset list -t abuseipdb-blacklist 2>/dev/null | awk '/Number of entries/{print $4}')"
    thresh="$(grep -E '^ABUSE_THRESHOLD=' "$CONF" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"' | sed 's/#.*//' | tr -d ' ')"
    if [ "$SKIP_GEO" -eq 0 ]; then
        gc="$(ipset list -t geoblock 2>/dev/null | awk '/Number of entries/{print $4}')"
        geo="enabled — ${GEOBLOCK_COUNTRIES:-?} (${gc:-0} CIDRs)"
    else
        geo="disabled"
    fi
    [ "${WL_APPLIED:-0}" -eq 1 ] && wl="applied" || wl="not applied"

    msg="✅ <b>Geo-Fail2Ban installed</b>
<b>Server:</b> ${host}
<b>Time:</b> ${now}
<b>Install dir:</b> ${INSTALL_DIR}
<b>Firewall:</b> ${FW_BACKEND}

<b>Protection active</b>
• sshd jail: 24h bans + Telegram alerts
• AbuseIPDB jail: PERMANENT ban at score ≥ ${thresh:-75}%
• Blacklist ipset: ${bl:-0} IPs (daily import)
• Geoblock: ${geo}
• SSH/DNS whitelist: ${wl}

All ipsets &amp; firewall rules restore on reboot."

    curl -fsS --max-time 15 \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${msg}" \
        --data-urlencode "parse_mode=HTML" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null
}

print_info "Sending install status to Telegram..."
if send_install_status; then
    print_success "Install status sent — check your Telegram chat"
else
    print_error "Could not send Telegram status — verify TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID in $CONF"
fi

print_header "Installation Complete! 🎉"

echo "How it works:"
echo "  • Failed SSH logins -> 24h ban + Telegram alert (BANNED/UNBANNED headers)"
echo "  • Banned IP with AbuseIPDB score >= threshold -> escalated to PERMANENT ban"
echo "  • AbuseIPDB blacklist imported daily into an add-only ipset (never expires)"
echo "  • Everything survives reboot (systemd restore units)"
echo ""
echo "Useful commands:"
echo "  sudo fail2ban-client status sshd"
echo "  sudo fail2ban-client status abuseipdb"
echo "  sudo ipset list -t abuseipdb-blacklist"
echo "  sudo bash tests/test_alert.sh"
echo ""
print_success "Geo-Fail2Ban is now protecting your server!"
echo ""
