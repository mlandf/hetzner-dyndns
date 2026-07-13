#!/bin/sh
set -eu

: "${HETZNER_TOKEN?need HETZNER_TOKEN}"
: "${ZONE?need ZONE}"                 # z.B. landfried.it
: "${RECORD_NAME?need RECORD_NAME}"   # z.B. vpn.office oder @
: "${TYPE?need TYPE}"                 # A (IPv4 only)

API="${API:-https://api.hetzner.cloud/v1}"
TTL="${TTL:-60}"

IPV4_CHECK_URL="${IPV4_CHECK_URL:-https://ipv4.icanhazip.com}"

auth="Authorization: Bearer ${HETZNER_TOKEN}"
ct="Content-Type: application/json"

STATE_DIR="${STATE_DIR:-/state}"
mkdir -p "$STATE_DIR"

HEALTH_FILE="$STATE_DIR/health.json"
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

json_escape() {
  # minimal JSON string escape
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_health() {
  # args: status message ip dns_value
  _status="$1"; _msg="$2"; _ip="${3:-}"; _dns="${4:-}"
  _status_e="$(json_escape "$_status")"
  _msg_e="$(json_escape "$_msg")"
  _zone_e="$(json_escape "$ZONE")"
  _rec_e="$(json_escape "$RECORD_NAME")"
  _type_e="$(json_escape "$TYPE")"
  _ip_e="$(json_escape "$_ip")"
  _dns_e="$(json_escape "$_dns")"

  cat > "$HEALTH_FILE" <<EOF
{
  "status": "${_status_e}",
  "message": "${_msg_e}",
  "zone": "${_zone_e}",
  "record": "${_rec_e}",
  "type": "${_type_e}",
  "ip": "${_ip_e}",
  "dns_value": "${_dns_e}",
  "timestamp_utc": "$(now_iso)"
}
EOF
}

# Default health at start of run
write_health "starting" "run_started" "" ""

get_ip_v4() {
  ip="$(curl -fsS "$IPV4_CHECK_URL" | tr -d '\r\n' | awk '{print $1}')"
  echo "$ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || { write_health "error" "bad_ipv4" "$ip" ""; echo "bad IPv4: $ip" >&2; exit 2; }
  echo "$ip"
}

# Cache-Key pro Zone/Record/Type
cache_key="$(printf "%s_%s_%s" "$ZONE" "$RECORD_NAME" "$TYPE" | tr '/: ' '___')"
cache_file="$STATE_DIR/lastip_${cache_key}"
lock_dir="$STATE_DIR/lock_${cache_key}"

# Lock gegen parallele Läufe
if ! mkdir "$lock_dir" 2>/dev/null; then
  # Ein anderer Lauf ist gerade aktiv -> kein Fehler
  write_health "ok" "locked_skip" "" ""
  exit 0
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

# IPv4 only
if [ "$TYPE" != "A" ]; then
  write_health "error" "type_must_be_A_ipv4_only" "" ""
  echo "TYPE must be A (IPv4 only) but is: $TYPE" >&2
  exit 2
fi

IP="$(get_ip_v4)"

# 0) Cache-Check: wenn IP gleich -> sofort raus, KEIN Hetzner API Call
if [ -f "$cache_file" ]; then
  last="$(cat "$cache_file" 2>/dev/null || true)"
  if [ "$last" = "$IP" ]; then
    write_health "ok" "cached_no_api_call" "$IP" "$IP"
    echo "OK cached $TYPE $RECORD_NAME.$ZONE already $IP (no API call)"
    exit 0
  fi
fi

# 1) Zone-ID
ZONE_ID="$(curl -fsS -H "$auth" "$API/zones?name=$ZONE" | jq -r '.zones[0].id // empty' || true)"
if [ -z "$ZONE_ID" ]; then
  write_health "error" "zone_not_found_or_auth" "$IP" ""
  echo "zone not found (or auth issue): $ZONE" >&2
  exit 3
fi

# 2) RRset finden (Name+Type)
RRSETS="$(curl -fsS -H "$auth" "$API/zones/$ZONE_ID/rrsets" || true)"
RRSET_ID="$(echo "$RRSETS" | jq -r --arg n "$RECORD_NAME" --arg t "$TYPE" '.rrsets[] | select(.name==$n and .type==$t) | .id' | head -n1 || true)"
CURR="$(echo "$RRSETS" | jq -r --arg n "$RECORD_NAME" --arg t "$TYPE" '.rrsets[] | select(.name==$n and .type==$t) | .records[0].value // empty' | head -n1 || true)"

if [ -z "${RRSET_ID:-}" ]; then
  write_health "error" "rrset_not_found_create_record_once" "$IP" ""
  echo "rrset not found: $RECORD_NAME ($TYPE) in $ZONE — create the record once in Hetzner DNS UI" >&2
  exit 4
fi

# Wenn DNS schon passt -> Cache refreshen, fertig
if [ "${CURR:-}" = "$IP" ]; then
  echo "$IP" > "$cache_file"
  write_health "ok" "dns_already_matches_cache_refreshed" "$IP" "$CURR"
  echo "OK $TYPE $RECORD_NAME.$ZONE already $IP (cache refreshed)"
  exit 0
fi

# 3) RRset Records setzen (genau 1 Wert)
payload="$(jq -nc --arg value "$IP" --argjson ttl "$TTL" '{records:[{value:$value}], ttl:$ttl}')"

# Hetzner DNS: set_records Action
curl -fsS -X POST -H "$auth" -H "$ct" \
  --data "$payload" \
  "$API/zones/$ZONE_ID/rrsets/$RRSET_ID/actions/set_records" >/dev/null

echo "$IP" > "$cache_file"
write_health "ok" "updated" "$IP" "${CURR:-}"
echo "UPDATED $TYPE $RECORD_NAME.$ZONE: ${CURR:-<empty>} -> $IP"
