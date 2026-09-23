#!/bin/sh

RUNETTODAY_CONFIG_DIR="${RUNETTODAY_CONFIG_DIR:-$HOME/.config/runettoday}"
RUNETTODAY_CREDENTIALS_FILE="$RUNETTODAY_CONFIG_DIR/credentials"

auth_init() {
    mkdir -p "$RUNETTODAY_CONFIG_DIR"
    chmod 700 "$RUNETTODAY_CONFIG_DIR"
}

auth_save() {
    access_token="$1"
    refresh_token="$2"
    email="$3"

    auth_init

    temporary_file="$RUNETTODAY_CREDENTIALS_FILE.tmp"

    umask 077

    cat > "$temporary_file" <<EOF2
email=$email
access_token=$access_token
refresh_token=$refresh_token
EOF2

    chmod 600 "$temporary_file"
    mv "$temporary_file" "$RUNETTODAY_CREDENTIALS_FILE"
}

auth_load() {
    if [ ! -f "$RUNETTODAY_CREDENTIALS_FILE" ]; then
        return 1
    fi

    if [ "$(stat -f '%Lp' "$RUNETTODAY_CREDENTIALS_FILE" 2>/dev/null)" != "600" ]; then
        chmod 600 "$RUNETTODAY_CREDENTIALS_FILE"
    fi

    . "$RUNETTODAY_CREDENTIALS_FILE"
}

auth_clear() {
    rm -f "$RUNETTODAY_CREDENTIALS_FILE"
}

auth_refresh() {
    if ! auth_load; then
        return 1
    fi

    current_email="${email:-}"

    if [ -z "${refresh_token:-}" ]; then
        return 1
    fi

    refresh_json="$(printf '%s' "$refresh_token" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"

    response="$(api_request POST /auth/refresh "{\"refreshToken\":$refresh_json}" 2>/tmp/runettoday-refresh-error)"

    if [ $? -ne 0 ]; then
        rm -f /tmp/runettoday-refresh-error
        return 1
    fi

    rm -f /tmp/runettoday-refresh-error

    new_access_token="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')" || return 1
    new_refresh_token="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin)["refreshToken"])')" || return 1

    auth_save "$new_access_token" "$new_refresh_token" "$current_email"
}

auth_require_login() {
    if ! auth_load; then
        printf '%s\n' "RunetToday: you are not logged in."
        printf '%s\n' "Run: runettoday login"
        return 1
    fi

    if [ -z "${access_token:-}" ] || [ -z "${refresh_token:-}" ]; then
        printf '%s\n' "RunetToday: credentials are incomplete."
        return 1
    fi

    return 0
}
