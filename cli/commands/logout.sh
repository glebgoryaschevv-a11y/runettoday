#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_DIR/src/config.sh"
. "$PROJECT_DIR/src/api.sh"
. "$PROJECT_DIR/src/auth.sh"

if ! auth_load; then
    printf '%s\n' 'RunetToday: you are not logged in.'
    exit 0
fi

if [ -n "${refresh_token:-}" ]; then
    refresh_json="$(printf '%s' "$refresh_token" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"

    api_request POST /auth/logout "{\"refreshToken\":$refresh_json}" "" \
        >/dev/null 2>&1 || true
fi

auth_clear

printf '%s\n' 'Logged out successfully.'
