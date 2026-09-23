#!/bin/sh

set -eu

INSTALL_ROOT="${RUNETTODAY_INSTALL_ROOT:-/opt/runettoday}"

case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin)
        DEFAULT_BIN_DIR="/usr/local/bin"
        DEFAULT_CONFIG_DIR="/usr/local/etc/runettoday"
        DEFAULT_DATA_DIR="/usr/local/var/lib/runettoday"
        ;;
    *)
        DEFAULT_BIN_DIR="/usr/bin"
        DEFAULT_CONFIG_DIR="/etc/runettoday"
        DEFAULT_DATA_DIR="/var/lib/runettoday"
        ;;
esac

BIN_DIR="${RUNETTODAY_BIN_DIR:-$DEFAULT_BIN_DIR}"
CONFIG_DIR="${RUNETTODAY_CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
DATA_DIR="${RUNETTODAY_DATA_DIR:-$DEFAULT_DATA_DIR}"

BIN_PATH="${BIN_DIR}/runettoday"

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        printf '%s\n' "ERROR: administrator privileges are required." >&2
        exit 1
    fi
}

printf '%s\n' "Removing RunetToday..."

run_privileged rm -f "$BIN_PATH"
run_privileged rm -rf "$INSTALL_ROOT"

if [ "${1:-}" = "--purge" ]; then
    run_privileged rm -rf "$CONFIG_DIR"
    run_privileged rm -rf "$DATA_DIR"
    printf '%s\n' "Configuration and data removed."
else
    printf '%s\n' "Configuration and data were preserved."
    printf '%s\n' "Use --purge to remove them."
fi

printf '%s\n' "RunetToday removed."
