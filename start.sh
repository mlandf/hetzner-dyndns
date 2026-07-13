#!/bin/sh
set -eu

mkdir -p /state

HEALTH_JSON="/state/health.json"
HEALTH_TXT="/state/healthz"

write_ok() {
  echo "OK" > "$HEALTH_TXT"
}

write_err() {
  echo "ERROR" > "$HEALTH_TXT"
}

# initial
echo '{"status":"starting","message":"container_started"}' > "$HEALTH_JSON"
write_ok

# Mini Webserver
python3 -u -m http.server 22222 --directory /state --bind 0.0.0.0 &
WEBPID="$!"

cleanup() {
  kill "$WEBPID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

while true; do
  if /app/hetzner-ddns.sh; then
    write_ok
  else
    write_err
  fi
  sleep 300
done
