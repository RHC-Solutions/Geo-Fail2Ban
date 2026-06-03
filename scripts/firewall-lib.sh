#!/bin/bash
#
# firewall-lib.sh — backend-agnostic firewall helpers for Geo-Fail2Ban.
#
# Auto-detects the active firewall backend and translates a small set of
# high-level operations into the right commands for it:
#
#   * firewalld  — firewall-cmd direct rules (block) + rich rules (whitelist)
#   * ufw        — Uncomplicated Firewall (iptables under the hood)
#   * iptables   — raw iptables / iptables-nft + ipset (no firewall manager)
#
# Works as a sourced library (defines fw_* functions) OR as a CLI:
#   firewall-lib.sh detect
#   firewall-lib.sh block      <ipset-name>
#   firewall-lib.sh unblock    <ipset-name>
#   firewall-lib.sh whitelist  <file>   # one IP per line ('#' comments ok)
#
# All operations are idempotent and safe to run repeatedly.

# ----------------------------------------------------------------------------
# Backend detection
# ----------------------------------------------------------------------------
# Prints one of: firewalld | ufw | iptables | none
fw_detect() {
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        echo firewalld
    elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi 'Status: active'; then
        echo ufw
    elif command -v iptables >/dev/null 2>&1; then
        echo iptables
    else
        echo none
    fi
}

# ----------------------------------------------------------------------------
# ipset DROP rule (used for the AbuseIPDB blacklist and the geoblock set)
# ----------------------------------------------------------------------------
# fw_block_set <ipset-name> : drop inbound traffic whose src is in <ipset-name>.
fw_block_set() {
    local set="$1"
    [ -n "$set" ] || { echo "fw_block_set: missing ipset name" >&2; return 1; }
    case "$(fw_detect)" in
        firewalld)
            # Runtime (apply now) and permanent (firewalld restores on reload/boot).
            firewall-cmd --direct --query-rule ipv4 filter INPUT 0 \
                -m set --match-set "$set" src -j DROP >/dev/null 2>&1 \
              || firewall-cmd --direct --add-rule ipv4 filter INPUT 0 \
                -m set --match-set "$set" src -j DROP >/dev/null
            firewall-cmd --permanent --direct --query-rule ipv4 filter INPUT 0 \
                -m set --match-set "$set" src -j DROP >/dev/null 2>&1 \
              || firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 \
                -m set --match-set "$set" src -j DROP >/dev/null
            ;;
        ufw|iptables)
            # ufw uses iptables under the hood, so a raw insert works for both.
            iptables -C INPUT -m set --match-set "$set" src -j DROP 2>/dev/null \
              || iptables -I INPUT 1 -m set --match-set "$set" src -j DROP
            ;;
        *)
            echo "firewall-lib: no usable backend (need firewalld, ufw, or iptables+ipset)" >&2
            return 1
            ;;
    esac
}

# fw_unblock_set <ipset-name> : remove the DROP rule from every backend present.
fw_unblock_set() {
    local set="$1"
    [ -n "$set" ] || return 0
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --direct --remove-rule ipv4 filter INPUT 0 \
            -m set --match-set "$set" src -j DROP >/dev/null 2>&1 || true
        firewall-cmd --permanent --direct --remove-rule ipv4 filter INPUT 0 \
            -m set --match-set "$set" src -j DROP >/dev/null 2>&1 || true
    fi
    if command -v iptables >/dev/null 2>&1; then
        while iptables -C INPUT -m set --match-set "$set" src -j DROP 2>/dev/null; do
            iptables -D INPUT -m set --match-set "$set" src -j DROP 2>/dev/null || break
        done
    fi
}

# ----------------------------------------------------------------------------
# SSH (22/tcp) + DNS (53 tcp/udp) whitelist: allow ONLY the given IPs.
# ----------------------------------------------------------------------------
# Persist raw iptables rules across reboots where tooling is available.
fw_persist_iptables() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 || true
    elif command -v iptables-save >/dev/null 2>&1; then
        if [ -d /etc/iptables ]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        elif [ -d /etc/sysconfig ]; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        fi
    fi
}

# fw_apply_whitelist <ip> [<ip> ...]
fw_apply_whitelist() {
    local backend zone ip rule
    backend="$(fw_detect)"

    # Lockout safety net: always include the IP of the current SSH session.
    local here=""
    [ -n "${SSH_CLIENT:-}" ]     && here="${SSH_CLIENT%% *}"
    [ -z "$here" ] && [ -n "${SSH_CONNECTION:-}" ] && here="${SSH_CONNECTION%% *}"
    set -- "$@" $here

    case "$backend" in
        ufw)
            for ip in "$@"; do
                [ -n "$ip" ] || continue
                ufw allow from "$ip" to any port 22 proto tcp >/dev/null 2>&1 || true
                ufw allow from "$ip" to any port 53 proto tcp >/dev/null 2>&1 || true
                ufw allow from "$ip" to any port 53 proto udp >/dev/null 2>&1 || true
            done
            ufw deny 22/tcp >/dev/null 2>&1 || true
            ufw deny 53/tcp >/dev/null 2>&1 || true
            ufw deny 53/udp >/dev/null 2>&1 || true
            ufw reload    >/dev/null 2>&1 || true
            ;;
        firewalld)
            zone="$(firewall-cmd --get-default-zone)"
            # Drop the broad services so only our per-source rich rules let 22/53 in.
            firewall-cmd --permanent --zone="$zone" --remove-service=ssh >/dev/null 2>&1 || true
            firewall-cmd --permanent --zone="$zone" --remove-service=dns >/dev/null 2>&1 || true
            for ip in "$@"; do
                [ -n "$ip" ] || continue
                for spec in '22 tcp' '53 tcp' '53 udp'; do
                    local p="${spec%% *}" proto="${spec##* }"
                    rule="rule family=\"ipv4\" source address=\"$ip\" port port=\"$p\" protocol=\"$proto\" accept"
                    firewall-cmd --permanent --zone="$zone" --add-rich-rule="$rule" >/dev/null 2>&1 || true
                done
            done
            firewall-cmd --reload >/dev/null 2>&1 || true
            ;;
        iptables)
            # Keep loopback and already-established connections alive (anti-lockout).
            iptables -C INPUT -i lo -j ACCEPT 2>/dev/null \
              || iptables -I INPUT 1 -i lo -j ACCEPT
            iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
              || iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
            for ip in "$@"; do
                [ -n "$ip" ] || continue
                iptables -C INPUT -s "$ip" -p tcp --dport 22 -j ACCEPT 2>/dev/null || iptables -I INPUT -s "$ip" -p tcp --dport 22 -j ACCEPT
                iptables -C INPUT -s "$ip" -p tcp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -s "$ip" -p tcp --dport 53 -j ACCEPT
                iptables -C INPUT -s "$ip" -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -s "$ip" -p udp --dport 53 -j ACCEPT
            done
            # Block everyone else (appended, so the ACCEPTs above take precedence).
            iptables -C INPUT -p tcp --dport 22 -j DROP 2>/dev/null || iptables -A INPUT -p tcp --dport 22 -j DROP
            iptables -C INPUT -p tcp --dport 53 -j DROP 2>/dev/null || iptables -A INPUT -p tcp --dport 53 -j DROP
            iptables -C INPUT -p udp --dport 53 -j DROP 2>/dev/null || iptables -A INPUT -p udp --dport 53 -j DROP
            fw_persist_iptables
            ;;
        *)
            echo "firewall-lib: no usable backend for whitelist" >&2
            return 1
            ;;
    esac
}

# ----------------------------------------------------------------------------
# CLI front-end (only when executed directly, not when sourced)
# ----------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    _cmd="${1:-}"; shift 2>/dev/null || true
    case "$_cmd" in
        detect)  fw_detect ;;
        block)   fw_block_set "$@" ;;
        unblock) fw_unblock_set "$@" ;;
        whitelist)
            _file="${1:-}"
            [ -f "$_file" ] || { echo "usage: $0 whitelist <file>" >&2; exit 1; }
            mapfile -t _ips < <(grep -vE '^[[:space:]]*#' "$_file" | grep -vE '^[[:space:]]*$')
            fw_apply_whitelist "${_ips[@]}"
            ;;
        *) echo "usage: $0 {detect|block <set>|unblock <set>|whitelist <file>}" >&2; exit 1 ;;
    esac
fi
