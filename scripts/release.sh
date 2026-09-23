#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

MAIN_FILE="$PROJECT_ROOT/cli/commands/runettoday.sh"
INSTALLER="$PROJECT_ROOT/installer/install.sh"
UNINSTALLER="$PROJECT_ROOT/installer/uninstall.sh"

RELEASES_DIR="$PROJECT_ROOT/releases"
WEBSITE_RELEASES_DIR="$PROJECT_ROOT/website/releases"

fail() {
    printf '%s\n' "[Release] ERROR: $*" >&2
    exit 1
}

log() {
    printf '%s\n' "[Release] $*"
}

[ -f "$MAIN_FILE" ] || fail "Не найден $MAIN_FILE"
[ -f "$INSTALLER" ] || fail "Не найден $INSTALLER"
[ -f "$UNINSTALLER" ] || fail "Не найден $UNINSTALLER"

VERSION="$(
    awk -F'"' '/^APP_VERSION="/ {
        split($2, parts, " ")
        print parts[1]
        exit
    }' "$MAIN_FILE"
)"

[ -n "$VERSION" ] || fail "Не удалось определить APP_VERSION"

case "$VERSION" in
    *[!0-9.]*)
        fail "Некорректная версия: $VERSION"
        ;;
esac

log "RunetToday release $VERSION"

log "Checking shell syntax..."

sh -n "$MAIN_FILE"
sh -n "$INSTALLER"
sh -n "$UNINSTALLER"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/runettoday-release.XXXXXX")"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

RELEASE_NAME="runettoday-${VERSION}"
PACKAGE_DIR="$TMP_DIR/$RELEASE_NAME"

mkdir -p "$PACKAGE_DIR"

log "Preparing release files..."

cp "$MAIN_FILE" "$PACKAGE_DIR/runettoday.sh"
chmod 0755 "$PACKAGE_DIR/runettoday.sh"

cp "$UNINSTALLER" "$PACKAGE_DIR/uninstall.sh"
chmod 0755 "$PACKAGE_DIR/uninstall.sh"

printf '%s\n' "$VERSION" > "$PACKAGE_DIR/VERSION"

cat > "$PACKAGE_DIR/config.example" <<EOF_CONFIG
# RunetToday configuration
#
# This file is reserved for future configurable settings.
#
RUNETTODAY_VERSION="$VERSION"
EOF_CONFIG

log "Creating release directories..."

mkdir -p "$RELEASES_DIR/$VERSION"
mkdir -p "$WEBSITE_RELEASES_DIR/$VERSION"

ARCHIVE="$RELEASES_DIR/$VERSION/${RELEASE_NAME}.tar.gz"
WEBSITE_ARCHIVE="$WEBSITE_RELEASES_DIR/$VERSION/${RELEASE_NAME}.tar.gz"

log "Creating archive..."

rm -f "$ARCHIVE"
rm -f "$WEBSITE_ARCHIVE"

tar -czf "$ARCHIVE" \
    -C "$TMP_DIR" \
    "$RELEASE_NAME"

cp "$ARCHIVE" "$WEBSITE_ARCHIVE"

log "Generating SHA-256 checksum..."

(
    cd "$RELEASES_DIR/$VERSION"
    shasum -a 256 "$(basename "$ARCHIVE")" \
        > "$(basename "$ARCHIVE").sha256"
)

(
    cd "$WEBSITE_RELEASES_DIR/$VERSION"
    shasum -a 256 "$(basename "$WEBSITE_ARCHIVE")" \
        > "$(basename "$WEBSITE_ARCHIVE").sha256"
)

log "Verifying archive..."

VERIFY_DIR="$TMP_DIR/verify"

mkdir -p "$VERIFY_DIR"

tar -xzf "$ARCHIVE" -C "$VERIFY_DIR"

[ -f "$VERIFY_DIR/$RELEASE_NAME/runettoday.sh" ] ||
    fail "В архиве отсутствует runettoday.sh"

[ -f "$VERIFY_DIR/$RELEASE_NAME/uninstall.sh" ] ||
    fail "В архиве отсутствует uninstall.sh"

[ -f "$VERIFY_DIR/$RELEASE_NAME/VERSION" ] ||
    fail "В архиве отсутствует VERSION"

[ -f "$VERIFY_DIR/$RELEASE_NAME/config.example" ] ||
    fail "В архиве отсутствует config.example"

ARCHIVE_VERSION="$(cat "$VERIFY_DIR/$RELEASE_NAME/VERSION")"

[ "$ARCHIVE_VERSION" = "$VERSION" ] ||
    fail "Версия внутри архива ($ARCHIVE_VERSION) не совпадает с $VERSION"

sh -n "$VERIFY_DIR/$RELEASE_NAME/runettoday.sh"
sh -n "$VERIFY_DIR/$RELEASE_NAME/uninstall.sh"

log "Verifying checksum..."

(
    cd "$RELEASES_DIR/$VERSION"
    shasum -a 256 -c "$(basename "$ARCHIVE").sha256"
)

log "Comparing website archive..."

cmp -s "$ARCHIVE" "$WEBSITE_ARCHIVE" ||
    fail "Архив сайта отличается от основного release-архива"

log "Release created successfully."

printf '\n'
printf '%s\n' "Version:      $VERSION"
printf '%s\n' "Archive:      $ARCHIVE"
printf '%s\n' "Website:      $WEBSITE_ARCHIVE"
printf '%s\n' "Checksum:     $RELEASES_DIR/$VERSION/$(basename "$ARCHIVE").sha256"

printf '\n'
printf '%s\n' "Contents:"

tar -tzf "$ARCHIVE"
