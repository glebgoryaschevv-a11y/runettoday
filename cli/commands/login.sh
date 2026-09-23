#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_DIR/src/config.sh"
. "$PROJECT_DIR/src/api.sh"
. "$PROJECT_DIR/src/auth.sh"
. "$PROJECT_DIR/src/autostart.sh" 2>/dev/null || true

printf '\nRunetToday Account\n'
printf '%s\n\n' 'Sign in'

printf 'Email: '
IFS= read -r email

printf 'Password: '
stty -echo
IFS= read -r password
stty echo
printf '\n'

email_json="$(printf '%s' "$email" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
password_json="$(printf '%s' "$password" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"

body="{\"email\":$email_json,\"password\":$password_json}"

response="$(api_request POST /auth/login "$body" 2>/tmp/runettoday-api-error)"

if [ $? -ne 0 ]; then
    printf '%s\n' 'Login failed.'

    if [ -s /tmp/runettoday-api-error ]; then
        cat /tmp/runettoday-api-error
    fi

    rm -f /tmp/runettoday-api-error
    exit 1
fi

rm -f /tmp/runettoday-api-error

access_token="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')"
refresh_token="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin)["refreshToken"])')"
user_email="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin)["user"]["email"])')"

auth_save "$access_token" "$refresh_token" "$user_email"

printf '\nLogin successful.\n'
printf 'Signed in as: %s\n' "$user_email"

# Регистрируем это устройство в аккаунте (если ещё не зарегистрировано)
if ! [ -f "$HOME/.config/runettoday/device" ]; then
    printf '\nRegistering this device...\n'
    "$PROJECT_DIR/commands/device.sh" add || true
fi

# Включаем автопост телеметрии (раз в 10 секунд)
autostart_install >/dev/null 2>&1 || true
