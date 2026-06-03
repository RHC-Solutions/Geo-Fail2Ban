#!/bin/bash
# Refresh geoblock ipset from ipdeny.com country zone files.
set -euo pipefail

LIST_DIR=/etc/ipset-geo/lists
SAVE_FILE=/etc/ipset-geo/ipset.conf
SET=geoblock
TMP_SET=${SET}_tmp

# Country lists come from /etc/geo-fail2ban.conf (GEOBLOCK_COUNTRIES /
# GEOBLOCK_AFRICA); the values below are fallback defaults.
CONF=/etc/geo-fail2ban.conf
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"
COUNTRIES="${GEOBLOCK_COUNTRIES:-cn in vn pk bd ru}"
AFRICA="${GEOBLOCK_AFRICA:-dz ao bj bw bf bi cv cm cf td km cg cd ci dj eg gq er sz et ga gm gh gn gw ke ls lr ly mg mw ml mr mu ma mz na ne ng rw st sn sc sl so za ss sd tz tg tn ug eh zm zw}"

mkdir -p "$LIST_DIR"
cd "$LIST_DIR"

fetch() {
  local cc=$1
  curl -fsS --max-time 30 -o "${cc}.zone.new" \
    "https://www.ipdeny.com/ipblocks/data/aggregated/${cc}-aggregated.zone" \
    && mv "${cc}.zone.new" "${cc}.zone" \
    || { echo "WARN: fetch failed for $cc, keeping previous list" >&2; rm -f "${cc}.zone.new"; }
}

for cc in $COUNTRIES; do fetch "$cc"; done

: > africa.zone.new
for cc in $AFRICA; do
  curl -fsS --max-time 20 \
    "https://www.ipdeny.com/ipblocks/data/aggregated/${cc}-aggregated.zone" \
    >> africa.zone.new 2>/dev/null || true
done
if [ -s africa.zone.new ]; then
  sort -u africa.zone.new -o africa.zone
fi
rm -f africa.zone.new

ipset create "$TMP_SET" hash:net family inet hashsize 16384 maxelem 200000 -exist
ipset flush "$TMP_SET"
for f in "$LIST_DIR"/*.zone; do
  while IFS= read -r cidr; do
    [ -z "$cidr" ] && continue
    ipset add "$TMP_SET" "$cidr" -exist
  done < "$f"
done

ipset create "$SET" hash:net family inet hashsize 16384 maxelem 200000 -exist
ipset swap "$TMP_SET" "$SET"
ipset destroy "$TMP_SET"

ipset save "$SET" > "$SAVE_FILE"
echo "$(date -Is) geoblock refreshed: $(ipset list -t "$SET" | awk '/Number of entries/{print $4}') CIDRs"
