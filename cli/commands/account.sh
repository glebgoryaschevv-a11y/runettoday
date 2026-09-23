#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_DIR/src/config.sh"
. "$PROJECT_DIR/src/api.sh"
. "$PROJECT_DIR/src/auth.sh"

if ! auth_require_login; then
    exit 1
fi

request_account() {
    api_request GET /me "" "$access_token"
}

response="$(request_account 2>/tmp/runettoday-api-error)"
request_status=$?

if [ "$request_status" -ne 0 ]; then
    if auth_refresh; then
        auth_load

        response="$(request_account 2>/tmp/runettoday-api-error)"
        request_status=$?
    fi
fi

if [ "$request_status" -ne 0 ]; then
    printf '%s\n' 'Unable to load account.'

    if [ -s /tmp/runettoday-api-error ]; then
        cat /tmp/runettoday-api-error
    fi

    rm -f /tmp/runettoday-api-error
    exit 1
fi

rm -f /tmp/runettoday-api-error

printf '\nRunetToday Account\n\n'

printf '%s\n' "$response" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
user = data.get("user", data)

print("ID:    " + str(user.get("id", "unknown")))
print("Email: " + str(user.get("email", "unknown")))
'
