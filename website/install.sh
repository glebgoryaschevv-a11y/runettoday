#!/bin/sh

set -eu

APP_NAME="RunetToday"
APP_VERSION="5.0.0"

BASE_URL="${RUNETTODAY_BASE_URL:-https://www.runettoday.ru}"
RELEASE_URL="${BASE_URL}/releases/${APP_VERSION}/runettoday-${APP_VERSION}.tar.gz"

OS_NAME="$(uname -s 2>/dev/null || echo unknown)"
ARCH_NAME="$(uname -m 2>/dev/null || echo unknown)"

if [ -n "${RUNETTODAY_INSTALL_ROOT:-}" ]; then
    INSTALL_ROOT="$RUNETTODAY_INSTALL_ROOT"
else
    INSTALL_ROOT="/opt/runettoday"
fi

if [ -n "${RUNETTODAY_BIN_DIR:-}" ]; then
    BIN_DIR="$RUNETTODAY_BIN_DIR"
else
    case "$OS_NAME" in
        Darwin)
            BIN_DIR="/usr/local/bin"
            ;;
        *)
            BIN_DIR="/usr/bin"
            ;;
    esac
fi

BIN_PATH="${BIN_DIR}/runettoday"

if [ -n "${RUNETTODAY_CONFIG_DIR:-}" ]; then
    CONFIG_DIR="$RUNETTODAY_CONFIG_DIR"
else
    case "$OS_NAME" in
        Darwin)
            CONFIG_DIR="/usr/local/etc/runettoday"
            ;;
        *)
            CONFIG_DIR="/etc/runettoday"
            ;;
    esac
fi

if [ -n "${RUNETTODAY_DATA_DIR:-}" ]; then
    DATA_DIR="$RUNETTODAY_DATA_DIR"
else
    case "$OS_NAME" in
        Darwin)
            DATA_DIR="/usr/local/var/lib/runettoday"
            ;;
        *)
            DATA_DIR="/var/lib/runettoday"
            ;;
    esac
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/runettoday-install.XXXXXX")"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

log() {
    printf '%s\n' "[RunetToday] $*"
}

fail() {
    printf '%s\n' "[RunetToday] ERROR: $*" >&2
    exit 1
}

USE_SUDO=1

if [ -n "${RUNETTODAY_INSTALL_ROOT:-}" ] || [ -n "${RUNETTODAY_BIN_DIR:-}" ] || [ -n "${RUNETTODAY_CONFIG_DIR:-}" ] || [ -n "${RUNETTODAY_DATA_DIR:-}" ]; then
    USE_SUDO=0
fi

run_privileged() {
    if [ "$USE_SUDO" -eq 0 ]; then
        "$@"
    elif [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        fail "Для установки требуются права администратора. Запустите установщик от root или установите sudo."
    fi
}

download() {
    URL="$1"
    OUTPUT="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$URL" -o "$OUTPUT"
        return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -qO "$OUTPUT" "$URL"
        return 0
    fi

    fail "Не найден curl или wget."
}

log "RunetToday ${APP_VERSION}"
log "System: ${OS_NAME}"
log "Architecture: ${ARCH_NAME}"
log "Downloading release..."

ARCHIVE="${TMP_DIR}/runettoday-${APP_VERSION}.tar.gz"

download "$RELEASE_URL" "$ARCHIVE" ||
    fail "Не удалось скачать релиз: ${RELEASE_URL}"

if [ ! -s "$ARCHIVE" ]; then
    fail "Скачанный архив пустой."
fi

log "Extracting release..."

EXTRACT_DIR="${TMP_DIR}/release"
mkdir -p "$EXTRACT_DIR"

tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"

RELEASE_DIR="${EXTRACT_DIR}/runettoday-${APP_VERSION}"

if [ ! -f "$RELEASE_DIR/runettoday.sh" ]; then
    fail "В релизе отсутствует runettoday.sh."
fi

log "Installing to ${INSTALL_ROOT}..."

run_privileged mkdir -p \
    "$INSTALL_ROOT" \
    "$CONFIG_DIR" \
    "$DATA_DIR" \
    "$BIN_DIR"

# RunetToday Control Deck uses fixed OpenWrt runtime paths.
# Keep these directories initialized before the first launch.
if [ -f /etc/openwrt_release ]; then
    run_privileged mkdir -p \
        /etc/runettoday \
        /etc/runettoday/snapshots \
        /etc/runettoday/adblock \
        /etc/crontabs

    run_privileged chmod 700 /etc/runettoday
    run_privileged chmod 700 /etc/runettoday/snapshots

    if [ ! -f /etc/runettoday/config ]; then
        run_privileged sh -c '{
            printf "RUNETTODAY_VERSION=\"%s\"\\n" "$1"
            printf "CREATED=\"%s\"\\n" "$(date "+%Y-%m-%d %H:%M:%S %Z")"
        } > /etc/runettoday/config' sh "$APP_VERSION"
    fi

    run_privileged chmod 600 /etc/runettoday/config
fi

run_privileged cp \
    "$RELEASE_DIR/runettoday.sh" \
    "$INSTALL_ROOT/runettoday.sh"

run_privileged chmod 0755 \
    "$INSTALL_ROOT/runettoday.sh"

run_privileged cp \
    "$RELEASE_DIR/VERSION" \
    "$INSTALL_ROOT/VERSION"

if [ -f "$RELEASE_DIR/config.example" ]; then
    if [ ! -f "$CONFIG_DIR/runettoday.conf" ]; then
        run_privileged cp \
            "$RELEASE_DIR/config.example" \
            "$CONFIG_DIR/runettoday.conf"
    fi
fi

run_privileged rm -f "$BIN_PATH"

run_privileged ln -s \
    "$INSTALL_ROOT/runettoday.sh" \
    "$BIN_PATH"

log "Installation completed."
printf '\n'

printf '%s\n' "RunetToday ${APP_VERSION} installed successfully."
printf '%s\n' "Binary: ${BIN_PATH}"
printf '%s\n' "Program: ${INSTALL_ROOT}/runettoday.sh"
printf '%s\n' "Config: ${CONFIG_DIR}"
printf '%s\n' "Data: ${DATA_DIR}"
printf '\n'

printf '%s\n' "Try:"
printf '%s\n' "  runettoday"
printf '%s\n' "  runettoday --version"
printf '%s\n' "  runettoday status"
