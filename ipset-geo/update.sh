#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin  # cron.d default PATH lacks /usr/sbin (ipset)
# Refresh geoblock ipset from ipdeny.com country zone files.
set -euo pipefail

LIST_DIR=/etc/ipset-geo/lists
SAVE_FILE=/etc/ipset-geo/ipset.conf
SET=geoblock
TMP_SET=${SET}_tmp

# Country lists come from /etc/geo-fail2ban.conf (GEOBLOCK_COUNTRIES /
# GEOBLOCK_AFRICA); the values below apply only when the key is absent
# entirely. Note the '-' rather than ':-': setting a key to "" means "block
# nothing from this list", as the config template documents. With ':-' an
# empty value fell back to the defaults below, so clearing GEOBLOCK_COUNTRIES
# silently kept blocking cn/vn/in/bd/pk/ng/ao.
CONF=/etc/geo-fail2ban.conf
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"
COUNTRIES="${GEOBLOCK_COUNTRIES-cn vn in bd pk ng ao}"
AFRICA="${GEOBLOCK_AFRICA-dz ao bj bw bf bi cv cm cf td km cg cd ci dj eg gq er sz et ga gm gh gn gw ke ls lr ly mg mw ml mr mu ma mz na ne ng rw st sn sc sl so za ss sd tz tg tn ug eh zm zw}"

# GEOBLOCK_AFRICA is applied on top of GEOBLOCK_COUNTRIES, so say so out loud -
# it is easy to miss that the continent list is in play as well.
echo "geoblock lists: GEOBLOCK_COUNTRIES=[${COUNTRIES:-none}] GEOBLOCK_AFRICA=[$(echo $AFRICA | wc -w) codes]"

mkdir -p "$LIST_DIR"
cd "$LIST_DIR"

fetch() {
  local cc=$1
  curl -fsS --max-time 30 -o "${cc}.zone.new" \
    "https://www.ipdeny.com/ipblocks/data/aggregated/${cc}-aggregated.zone" \
    && mv "${cc}.zone.new" "${cc}.zone" \
    || { echo "WARN: fetch failed for $cc, keeping previous list" >&2; rm -f "${cc}.zone.new"; }
}

# Progress bar over the per-country downloads. Only drawn when stdout is a
# terminal, so the daily-cron log (update.sh >> ...log) stays clean.
_progress() {  # _progress <current> <total> <label>
  [ -t 1 ] || return 0
  local cur=$1 total=$2 label=$3 width=30 filled pct hashes dashes
  if [ "$total" -gt 0 ]; then
    filled=$(( cur * width / total )); pct=$(( cur * 100 / total ))
  else
    filled=$width; pct=100
  fi
  hashes=$(printf '%*s' "$filled" '' | tr ' ' '#')
  dashes=$(printf '%*s' "$(( width - filled ))" '' | tr ' ' '-')
  printf '\r  [%s%s] %3d%% (%d/%d) %-16s' "$hashes" "$dashes" "$pct" "$cur" "$total" "$label"
}

TOTAL=$(( $(echo $COUNTRIES | wc -w) + $(echo $AFRICA | wc -w) ))
DONE=0

for cc in $COUNTRIES; do
  fetch "$cc"
  DONE=$((DONE + 1)); _progress "$DONE" "$TOTAL" "$cc"
done

: > africa.zone.new
for cc in $AFRICA; do
  curl -fsS --max-time 20 \
    "https://www.ipdeny.com/ipblocks/data/aggregated/${cc}-aggregated.zone" \
    >> africa.zone.new 2>/dev/null || true
  DONE=$((DONE + 1)); _progress "$DONE" "$TOTAL" "africa/$cc"
done
if [ -t 1 ]; then printf '\n'; fi
if [ -s africa.zone.new ]; then
  sort -u africa.zone.new -o africa.zone
fi
rm -f africa.zone.new

# Drop zone files for countries that are no longer configured. The load loop
# below globs *.zone, so without this a country removed from GEOBLOCK_COUNTRIES
# would keep being loaded into the set from its stale file - making it
# impossible to un-block a country without deleting the file by hand.
KEEP=" $(echo $COUNTRIES) "
[ -n "$(echo $AFRICA)" ] && KEEP="${KEEP}africa "
for f in "$LIST_DIR"/*.zone; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .zone)"
  case "$KEEP" in
    *" $base "*) ;;
    *) echo "removing stale zone list: $base" >&2; rm -f "$f" ;;
  esac
done

shopt -s nullglob
ZONES=( "$LIST_DIR"/*.zone )
shopt -u nullglob

# No lists on disk. If nothing is configured that is the correct outcome (an
# empty set); if countries ARE configured, every download must have failed, and
# swapping in an empty set here would silently wipe a working geoblock.
if [ "${#ZONES[@]}" -eq 0 ] && [ -n "$(echo $COUNTRIES $AFRICA)" ]; then
  echo "WARN: no zone files available (all downloads failed?) - geoblock left unchanged" >&2
  exit 0
fi

ipset create "$TMP_SET" hash:net family inet hashsize 16384 maxelem 200000 -exist
ipset flush "$TMP_SET"
# One batched 'ipset restore' rather than a fork per CIDR. The default country
# list is on the order of 30k networks, i.e. 30k process spawns the old way.
# Guarded: expanding an empty array is an error under 'set -u' on bash < 4.4.
if [ "${#ZONES[@]}" -gt 0 ]; then
  { grep -hE '^[0-9]' "${ZONES[@]}" || true; } \
    | tr -d '\r' \
    | sed -e "s|^|add ${TMP_SET} |" -e 's|$| -exist|' \
    | ipset restore -exist
fi

ipset create "$SET" hash:net family inet hashsize 16384 maxelem 200000 -exist
ipset swap "$TMP_SET" "$SET"
ipset destroy "$TMP_SET"

ipset save "$SET" > "$SAVE_FILE"
echo "$(date -Is) geoblock refreshed: $(ipset list -t "$SET" | awk '/Number of entries/{print $4}') CIDRs"
