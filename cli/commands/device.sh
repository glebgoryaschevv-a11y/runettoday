#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_DIR/src/config.sh"
. "$PROJECT_DIR/src/api.sh"
. "$PROJECT_DIR/src/auth.sh"
. "$PROJECT_DIR/src/telemetry.sh"

RUNETTODAY_DEVICE_FILE="$RUNETTODAY_CONFIG_DIR/device"

show_help() {
    cat <<'HELP'
RunetToday Device

Usage:
  runettoday device <command>

Commands:
  add                   Register this computer
  remove <device-id>    Remove a device
  heartbeat             Send device heartbeat
  telemetry             Send device telemetry
  help                  Show this help
HELP
}

device_save_id() {
    device_id="$1"

    mkdir -p "$RUNETTODAY_CONFIG_DIR"
    chmod 700 "$RUNETTODAY_CONFIG_DIR"

    umask 077

    temporary_file="$RUNETTODAY_DEVICE_FILE.tmp"

    printf 'device_id=%s\n' "$device_id" > "$temporary_file"

    chmod 600 "$temporary_file"
    mv "$temporary_file" "$RUNETTODAY_DEVICE_FILE"
}

device_load_id() {
    if [ ! -f "$RUNETTODAY_DEVICE_FILE" ]; then
        return 1
    fi

    chmod 600 "$RUNETTODAY_DEVICE_FILE" 2>/dev/null || true

    . "$RUNETTODAY_DEVICE_FILE"

    if [ -z "${device_id:-}" ]; then
        return 1
    fi

    return 0
}

device_clear_id() {
    rm -f "$RUNETTODAY_DEVICE_FILE"
}

device_add() {
    if ! auth_require_login; then
        exit 1
    fi

    _os="$(uname -s)"

    case "$_os" in
        Darwin)
            name="$(scutil --get ComputerName 2>/dev/null || hostname)"
            platform="macOS"
            version="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
            hostname_value="$(hostname)"
            ;;
        Linux)
            name="$(hostname)"
            platform="Linux"
            if [ -r /etc/os-release ]; then
                version="$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-${VERSION_ID:-unknown}}")"
            else
                version="unknown"
            fi
            hostname_value="$(hostname)"
            ;;
        *)
            printf '%s\n' "RunetToday: unsupported OS: $_os"
            exit 1
            ;;
    esac

    name_json="$(printf '%s' "$name" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
    type_json="$(printf '%s' "desktop" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
    platform_json="$(printf '%s' "$platform" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
    version_json="$(printf '%s' "$version" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
    hostname_json="$(printf '%s' "$hostname_value" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"

    body="{\"name\":$name_json,\"type\":$type_json,\"platform\":$platform_json,\"version\":$version_json,\"hostname\":$hostname_json}"

    response="$(api_request POST /devices "$body" "$access_token" 2>/tmp/runettoday-api-error)"
    request_status=$?

    if [ "$request_status" -ne 0 ]; then
        if auth_refresh; then
            auth_load
            response="$(api_request POST /devices "$body" "$access_token" 2>/tmp/runettoday-api-error)"
            request_status=$?
        fi
    fi

    if [ "$request_status" -ne 0 ]; then
        printf '%s\n' 'Unable to register device.'
        if [ -s /tmp/runettoday-api-error ]; then
            cat /tmp/runettoday-api-error
        fi
        rm -f /tmp/runettoday-api-error
        exit 1
    fi

    rm -f /tmp/runettoday-api-error

    device_id="$(printf '%s' "$response" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
device = data.get("device", data)
device_id = device.get("id", "")

if device_id:
    print(device_id)
')"

    if [ -z "$device_id" ]; then
        printf '%s\n' 'RunetToday: server did not return a device ID.'
        exit 1
    fi

    device_save_id "$device_id"

    printf '\nDevice registered successfully.\n\n'

    printf '%s\n' "$response" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
device = data.get("device", data)

print("Name:      " + str(device.get("name", "unknown")))
print("ID:        " + str(device.get("id", "unknown")))
print("Type:      " + str(device.get("type", "unknown")))
print("Platform:  " + str(device.get("platform", "unknown")))
print("Version:   " + str(device.get("version", "unknown")))
print("Hostname:  " + str(device.get("hostname", "unknown")))
'

    printf '\nLocal device ID saved.\n'
}

device_remove() {
    if ! auth_require_login; then
        exit 1
    fi

    device_id="${1:-}"

    if [ -z "$device_id" ]; then
        printf '%s\n' 'Usage: runettoday device remove <device-id>'
        exit 1
    fi

    response="$(api_request DELETE "/devices/$device_id" "" "$access_token" 2>/tmp/runettoday-api-error)"
    request_status=$?

    if [ "$request_status" -ne 0 ]; then
        if auth_refresh; then
            auth_load

            response="$(api_request DELETE "/devices/$device_id" "" "$access_token" 2>/tmp/runettoday-api-error)"
            request_status=$?
        fi
    fi

    if [ "$request_status" -ne 0 ]; then
        printf '%s\n' 'Unable to remove device.'

        if [ -s /tmp/runettoday-api-error ]; then
            cat /tmp/runettoday-api-error
        fi

        rm -f /tmp/runettoday-api-error
        exit 1
    fi

    rm -f /tmp/runettoday-api-error

    current_device_id=""

    if device_load_id; then
        current_device_id="$device_id"
    fi

    if [ "$current_device_id" = "$1" ]; then
        device_clear_id
        printf 'Local device ID cleared.\n'
    fi

    printf 'Device removed: %s\n' "$device_id"
}

device_heartbeat() {
    if ! auth_require_login; then
        exit 1
    fi

    if ! device_load_id; then
        printf '%s\n' 'RunetToday: this computer is not registered.'
        printf '%s\n' 'Run: ./cli/runettoday device add'
        exit 1
    fi

    current_device_id="$device_id"

    response="$(api_request POST "/devices/$current_device_id/heartbeat" "" "$access_token" 2>/tmp/runettoday-api-error)"
    request_status=$?

    if [ "$request_status" -ne 0 ]; then
        if auth_refresh; then
            auth_load

            response="$(api_request POST "/devices/$current_device_id/heartbeat" "" "$access_token" 2>/tmp/runettoday-api-error)"
            request_status=$?
        fi
    fi

    if [ "$request_status" -ne 0 ]; then
        printf '%s\n' 'Unable to send device heartbeat.'

        if [ -s /tmp/runettoday-api-error ]; then
            cat /tmp/runettoday-api-error
        fi

        rm -f /tmp/runettoday-api-error
        exit 1
    fi

    rm -f /tmp/runettoday-api-error

    printf '\nHeartbeat sent successfully.\n\n'

    printf '%s\n' "$response" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
device = data.get("device", data)

print("Device:    " + str(device.get("name", "unknown")))
print("ID:        " + str(device.get("id", "unknown")))
print("Last seen: " + str(device.get("last_seen_at", "unknown")))
'
}

device_telemetry() {
    if ! auth_require_login; then
        exit 1
    fi

    if ! device_load_id; then
        printf '%s\n' 'RunetToday: this computer is not registered.'
        printf '%s\n' 'Run: ./cli/runettoday device add'
        exit 1
    fi

    current_device_id="$device_id"

    telemetry_json="$(telemetry_collect)" || {
        printf '%s\n' 'RunetToday: failed to collect telemetry.'
        exit 1
    }

    response="$(api_request POST "/devices/$current_device_id/telemetry" "$telemetry_json" "$access_token" 2>/tmp/runettoday-api-error)"
    request_status=$?

    if [ "$request_status" -ne 0 ]; then
        if auth_refresh; then
            auth_load

            response="$(api_request POST "/devices/$current_device_id/telemetry" "$telemetry_json" "$access_token" 2>/tmp/runettoday-api-error)"
            request_status=$?
        fi
    fi

    if [ "$request_status" -ne 0 ]; then
        printf '%s\n' 'Unable to send device telemetry.'

        if [ -s /tmp/runettoday-api-error ]; then
            cat /tmp/runettoday-api-error
        fi

        rm -f /tmp/runettoday-api-error
        exit 1
    fi

    rm -f /tmp/runettoday-api-error

    printf '\nTelemetry sent successfully.\n\n'

    printf '%s\n' "$telemetry_json" | python3 -c '
import json
import sys

data = json.load(sys.stdin)

print("Model:            " + str(data.get("model", "unknown")))
print("Platform:         " + str(data.get("platform", "unknown")))
print("OS version:       " + str(data.get("osVersion", "unknown")))
print("App version:      " + str(data.get("appVersion", "unknown")))
print("Storage total:    " + str(data.get("storageTotal", "unknown")))
print("Storage used:     " + str(data.get("storageUsed", "unknown")))
print("Storage free:     " + str(data.get("storageFree", "unknown")))
print("Memory total:     " + str(data.get("memoryTotal", "unknown")))
print("Memory available: " + str(data.get("memoryAvailable", "unknown")))
print("Battery level:    " + str(data.get("batteryLevel", "unknown")))
print("Battery state:    " + str(data.get("batteryState", "unknown")))
print("Network type:     " + str(data.get("networkType", "unknown")))
'
}

case "${1:-}" in
    add)
        device_add
        ;;

    remove)
        shift
        device_remove "$@"
        ;;

    heartbeat)
        device_heartbeat
        ;;

    telemetry)
        device_telemetry
        ;;

    help|--help|-h|"")
        show_help
        ;;

    *)
        printf 'Unknown device command: %s\n\n' "$1"
        show_help
        exit 1
        ;;
esac
