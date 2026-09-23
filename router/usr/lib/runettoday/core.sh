#!/bin/sh
# RunetToday для OpenWrt — ядро: API, авторизация, хранение токенов.

RT_CONFIG="runettoday.main"
RT_VERSION="1.0.0"

rt_log() {
	logger -t runettoday "$*"
	echo "[runettoday] $*"
}

rt_uci_get() {
	uci -q get "$RT_CONFIG.$1" || echo ""
}

rt_uci_set() {
	uci -q set "$RT_CONFIG.$1=$2"
	uci -q commit runettoday
}

# Экранирование строки для JSON-строки
rt_json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r//g'
}

# Извлечь "key":"value" (только для плоских строковых значений)
rt_json_get() {
	sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Базовый вызов API. $1=method, $2=endpoint, $3=body (или ""), $4=token (или "")
rt_api() {
	_method="$1"
	_endpoint="$2"
	_body="$3"
	_token="$4"
	_url="$(rt_uci_get api_url)"
	[ -z "$_url" ] && _url="https://www.runettoday.ru/api/v1"

	if [ -n "$_token" ]; then
		if [ -n "$_body" ]; then
			curl -fsS -X "$_method" "$_url$_endpoint" \
				-H "Content-Type: application/json" \
				-H "Authorization: Bearer $_token" \
				--data "$_body"
		else
			curl -fsS -X "$_method" "$_url$_endpoint" \
				-H "Content-Type: application/json" \
				-H "Authorization: Bearer $_token"
		fi
	else
		if [ -n "$_body" ]; then
			curl -fsS -X "$_method" "$_url$_endpoint" \
				-H "Content-Type: application/json" \
				--data "$_body"
		else
			curl -fsS -X "$_method" "$_url$_endpoint" \
				-H "Content-Type: application/json"
		fi
	fi
}

rt_login() {
	_email="$1"
	_password="$2"

	if [ -z "$_email" ] || [ -z "$_password" ]; then
		printf 'Email: '
		read -r _email
		printf 'Password: '
		stty -echo 2>/dev/null
		read -r _password
		stty echo 2>/dev/null
		echo
	fi

	if [ -z "$_email" ] || [ -z "$_password" ]; then
		rt_log "login: email and password required"
		return 1
	fi

	_e_email="$(rt_json_escape "$_email")"
	_p_password="$(rt_json_escape "$_password")"
	_body="{\"email\":\"$_e_email\",\"password\":\"$_p_password\"}"

	_response="$(rt_api POST /auth/login "$_body" "")" || {
		rt_log "login failed: cannot reach API"
		return 1
	}

	_at="$(printf '%s' "$_response" | rt_json_get x accessToken)"
	_rt="$(printf '%s' "$_response" | rt_json_get x refreshToken)"

	if [ -z "$_at" ] || [ -z "$_rt" ]; then
		rt_log "login failed: unexpected response"
		echo "$_response"
		return 1
	fi

	rt_uci_set email "$_email"
	rt_uci_set access_token "$_at"
	rt_uci_set refresh_token "$_rt"

	rt_log "logged in as $_email"
	echo "Logged in as $_email"
}

rt_logout() {
	_rt="$(rt_uci_get refresh_token)"
	if [ -n "$_rt" ]; then
		_body="{\"refreshToken\":\"$_rt\"}"
		rt_api POST /auth/logout "$_body" "" >/dev/null 2>&1 || true
	fi
	rt_uci_set access_token ""
	rt_uci_set refresh_token ""
	rt_uci_set device_id ""
	echo "Logged out."
}

rt_refresh() {
	_rt="$(rt_uci_get refresh_token)"
	[ -z "$_rt" ] && return 1

	_body="{\"refreshToken\":\"$_rt\"}"
	_response="$(rt_api POST /auth/refresh "$_body" "")" || return 1

	_at="$(printf '%s' "$_response" | rt_json_get x accessToken)"
	_new_rt="$(printf '%s' "$_response" | rt_json_get x refreshToken)"

	[ -z "$_at" ] && return 1
	rt_uci_set access_token "$_at"
	[ -n "$_new_rt" ] && rt_uci_set refresh_token "$_new_rt"
	return 0
}

rt_ensure_auth() {
	_at="$(rt_uci_get access_token)"
	if [ -n "$_at" ]; then
		return 0
	fi
	rt_refresh || {
		rt_log "not logged in"
		return 1
	}
	return 0
}

rt_register_device() {
	if ! rt_ensure_auth; then
		echo "Not logged in. Run: runettoday login"
		return 1
	fi

	_at="$(rt_uci_get access_token)"
	_existing="$(rt_uci_get device_id)"

	if [ -n "$_existing" ]; then
		echo "Device already registered: $_existing"
		return 0
	fi

	_name="$(rt_collect_model)"
	_os="$(rt_collect_os_version)"
	_host="$(hostname)"

	_body="{\"name\":\"$(rt_json_escape "$_name")\",\"type\":\"router\",\"platform\":\"OpenWrt\",\"version\":\"$(rt_json_escape "$_os")\",\"hostname\":\"$(rt_json_escape "$_host")\"}"

	_response="$(rt_api POST /devices "$_body" "$_at")" || {
		echo "Failed to register device."
		return 1
	}

	_did="$(printf '%s' "$_response" | rt_json_get x id)"

	if [ -z "$_did" ]; then
		echo "Server did not return a device id."
		echo "$_response"
		return 1
	fi

	rt_uci_set device_id "$_did"
	echo "Device registered: $_did"
}

rt_send_heartbeat() {
	if ! rt_ensure_auth; then
		echo "Not logged in."
		return 1
	fi

	_did="$(rt_uci_get device_id)"
	if [ -z "$_did" ]; then
		echo "Device not registered. Run: runettoday register"
		return 1
	fi

	_at="$(rt_uci_get access_token)"
	rt_api POST "/devices/$_did/heartbeat" "" "$_at" >/dev/null || {
		# Попробуем refresh и повторить
		if rt_refresh; then
			_at="$(rt_uci_get access_token)"
			rt_api POST "/devices/$_did/heartbeat" "" "$_at" >/dev/null || return 1
		else
			return 1
		fi
	}

	rt_log "heartbeat sent for $_did"
	echo "Heartbeat sent."
}

rt_send_telemetry() {
	if ! rt_ensure_auth; then
		echo "Not logged in."
		return 1
	fi

	_did="$(rt_uci_get device_id)"
	if [ -z "$_did" ]; then
		echo "Device not registered. Run: runettoday register"
		return 1
	fi

	_body="$(rt_telemetry_json)"
	_at="$(rt_uci_get access_token)"

	rt_api POST "/devices/$_did/telemetry" "$_body" "$_at" >/dev/null || {
		if rt_refresh; then
			_at="$(rt_uci_get access_token)"
			rt_api POST "/devices/$_did/telemetry" "$_body" "$_at" >/dev/null || return 1
		else
			return 1
		fi
	}

	rt_log "telemetry sent for $_did"
	echo "Telemetry sent."
}

rt_status() {
	echo "RunetToday on OpenWrt $RT_VERSION"
	echo
	echo "API URL:    $(rt_uci_get api_url)"
	echo "Email:      $(rt_uci_get email)"
	echo "Device ID:  $(rt_uci_get device_id)"
	echo "Logged in:  $([ -n "$(rt_uci_get access_token)" ] && echo yes || echo no)"
	echo "Enabled:    $(rt_uci_get enabled)"
}
