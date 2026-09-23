#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_DIR/src/config.sh"
. "$PROJECT_DIR/src/api.sh"
. "$PROJECT_DIR/src/auth.sh"

if ! auth_require_login; then
    exit 1
fi

request_devices() {
    api_request GET /devices "" "$access_token"
}

response="$(request_devices 2>/tmp/runettoday-api-error)"
request_status=$?

if [ "$request_status" -ne 0 ]; then
    if auth_refresh; then
        auth_load

        response="$(request_devices 2>/tmp/runettoday-api-error)"
        request_status=$?
    fi
fi

if [ "$request_status" -ne 0 ]; then
    printf '%s\n' 'Unable to load devices.'

    if [ -s /tmp/runettoday-api-error ]; then
        cat /tmp/runettoday-api-error
    fi

    rm -f /tmp/runettoday-api-error
    exit 1
fi

rm -f /tmp/runettoday-api-error

printf '\nRunetToday Devices\n\n'

printf '%s\n' "$response" | python3 -c '
import json
import sys

data = json.load(sys.stdin)

if isinstance(data, dict):
    devices = data.get("devices", [])
elif isinstance(data, list):
    devices = data
else:
    devices = []

if not devices:
    print("No devices linked.")
    raise SystemExit(0)

for index, device in enumerate(devices, 1):
    name = device.get("name") or "Unnamed device"
    device_id = device.get("id") or "unknown"
    device_type = device.get("type") or "unknown"
    platform = device.get("platform") or "unknown"
    version = device.get("version") or "unknown"
    hostname = device.get("hostname") or "unknown"
    last_seen = device.get("last_seen_at") or "never"

    print(f"{index}. {name}")
    print(f"   ID:        {device_id}")
    print(f"   Type:      {device_type}")
    print(f"   Platform:  {platform}")
    print(f"   Version:   {version}")
    print(f"   Hostname:  {hostname}")
    print(f"   Last seen: {last_seen}")
    print()
'
