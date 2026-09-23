#!/bin/sh
# RunetToday — OpenWrt Control Deck
# Single-file router administration, security, backup and diagnostics tool.

APP_NAME="RunetToday"
APP_VERSION="5.0.0 · Control Deck"

RUNETTODAY_DIR="/etc/runettoday"
RUNETTODAY_SNAPSHOT_DIR="$RUNETTODAY_DIR/snapshots"
RUNETTODAY_LOG="$RUNETTODAY_DIR/timeline.log"
RUNETTODAY_CONFIG="$RUNETTODAY_DIR/config"

# Legacy compatibility
LEGACY_DIR="/etc/frostwall"
LEGACY_SNAPSHOT_DIR="$LEGACY_DIR/snapshots"

ADBLOCK_DIR="$RUNETTODAY_DIR/adblock"
ADBLOCK_CUSTOM_FEEDS="/etc/adblock/adblock.custom.feeds"
ADBLOCK_CRON="/etc/crontabs/root"

current_pos=1
USB_MOUNT=""

NOADS_RU_BLOCKER_URL="https://raw.githubusercontent.com/Zalexanninev15/NoADS_RU/refs/heads/main/hosts/blocker.txt"
NOADS_RU_BLOCKER_FL_URL="https://raw.githubusercontent.com/Zalexanninev15/NoADS_RU/refs/heads/main/hosts/blockerFL.txt"
ADBLOCK_EXTRA_FEED_URL="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.txt"

if [ -t 1 ]; then
    RESET='\033[0m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    CYAN='\033[36m'
    MAGENTA='\033[35m'
    WHITE='\033[97m'
else
    RESET=''
    BOLD=''
    DIM=''
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    MAGENTA=''
    WHITE=''
fi

# --------------------------------------------------------------------
# BASIC HELPERS
# --------------------------------------------------------------------

clear_screen() {
    command -v clear >/dev/null 2>&1 && clear
}

pause() {
    printf "\n${DIM}────────────────────────────────────────────────────────────────${RESET}\n"
    printf "${DIM}  Нажмите Enter, чтобы вернуться в Control Deck…${RESET}"
    read -r _
}

success() {
    printf "  ${GREEN}●${RESET} ${BOLD}%s${RESET}\n" "$1"
}

warning() {
    printf "  ${YELLOW}▲${RESET} %s\n" "$1"
}

error() {
    printf "  ${RED}✕${RESET} ${BOLD}%s${RESET}\n" "$1"
}

info() {
    printf "  ${CYAN}●${RESET} %s\n" "$1"
}

confirm() {
    printf "\n${YELLOW}Подтвердить действие? [y/N]: ${RESET}"
    read -r answer

    case "$answer" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

router_name() {
    uci -q get 'system.@system[0].hostname' 2>/dev/null ||
        hostname 2>/dev/null ||
        printf 'OpenWrt'
}

ssh_port() {
    uci -q get 'dropbear.@dropbear[0].Port' 2>/dev/null ||
        printf '22'
}

totp_status() {
    if [ -f "$RUNETTODAY_DIR/2fa.conf" ]; then
        printf 'READY'
    else
        printf 'SETUP REQUIRED'
    fi
}

timeline_log() {
    mkdir -p "$RUNETTODAY_DIR" 2>/dev/null || return 0
    chmod 700 "$RUNETTODAY_DIR" 2>/dev/null

    printf '%s  %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S %Z')" \
        "$1" >> "$RUNETTODAY_LOG"
}

# --------------------------------------------------------------------
# DIRECTORY / MIGRATION
# --------------------------------------------------------------------

initialize_runettoday() {
    mkdir -p "$RUNETTODAY_DIR" "$RUNETTODAY_SNAPSHOT_DIR" "$ADBLOCK_DIR" \
        /etc/crontabs 2>/dev/null

    chmod 700 "$RUNETTODAY_DIR" "$RUNETTODAY_SNAPSHOT_DIR" 2>/dev/null
    chmod 600 "$RUNETTODAY_CONFIG" 2>/dev/null

    if [ ! -f "$RUNETTODAY_CONFIG" ]; then
        {
            printf 'RUNETTODAY_VERSION="%s"\n' "$APP_VERSION"
            printf 'CREATED="%s"\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        } > "$RUNETTODAY_CONFIG"
        chmod 600 "$RUNETTODAY_CONFIG"
    fi
}

migrate_legacy_configuration() {
    initialize_runettoday

    [ -d "$LEGACY_DIR" ] || return 0
    [ -f "$RUNETTODAY_DIR/2fa.conf" ] && return 0

    if [ -f "$LEGACY_DIR/2fa.conf" ]; then
        cp "$LEGACY_DIR/2fa.conf" "$RUNETTODAY_DIR/2fa.conf" 2>/dev/null
        chmod 600 "$RUNETTODAY_DIR/2fa.conf" 2>/dev/null
        timeline_log "MIGRATION imported legacy Frostwall 2FA configuration"
    fi

    if [ -f "$LEGACY_DIR/timeline.log" ] && [ ! -f "$RUNETTODAY_LOG" ]; then
        cp "$LEGACY_DIR/timeline.log" "$RUNETTODAY_LOG" 2>/dev/null
    fi

    if [ -d "$LEGACY_SNAPSHOT_DIR" ]; then
        cp -n "$LEGACY_SNAPSHOT_DIR"/*.tar.gz \
            "$RUNETTODAY_SNAPSHOT_DIR/" 2>/dev/null
    fi
}

# --------------------------------------------------------------------
# SNAPSHOTS
# --------------------------------------------------------------------

snapshot_before_change() {
    initialize_runettoday

    snapshot_stamp="$(date '+%Y%m%d-%H%M%S')"
    snapshot_file="$RUNETTODAY_SNAPSHOT_DIR/pre-change-$snapshot_stamp.tar.gz"

    set -- etc/config etc/profile

    [ -d /etc/dropbear ] &&
        set -- "$@" etc/dropbear

    [ -f "$RUNETTODAY_DIR/2fa.conf" ] &&
        set -- "$@" etc/runettoday/2fa.conf

    [ -f /etc/sysupgrade.conf ] &&
        set -- "$@" etc/sysupgrade.conf

    if tar -czf "$snapshot_file" -C / "$@" 2>/dev/null; then
        cp "$snapshot_file" "$RUNETTODAY_SNAPSHOT_DIR/latest.tar.gz" 2>/dev/null
        success "Создан аварийный снимок настроек."
        timeline_log "SNAPSHOT created: $snapshot_file"
        return 0
    fi

    error "Не удалось создать аварийный снимок."
    return 1
}

list_snapshots() {
    printf "\n  ${CYAN}AVAILABLE SNAPSHOTS${RESET}\n\n"

    if ! ls "$RUNETTODAY_SNAPSHOT_DIR"/*.tar.gz >/dev/null 2>&1; then
        warning "Снимков пока нет."
        return
    fi

    ls -lh "$RUNETTODAY_SNAPSHOT_DIR"/*.tar.gz 2>/dev/null
}

restore_local_snapshot() {
    screen_title "BACKUP / RESTORE" "Restore local RunetToday snapshot"

    latest_snapshot="$RUNETTODAY_SNAPSHOT_DIR/latest.tar.gz"

    if [ ! -f "$latest_snapshot" ]; then
        error "Локальный snapshot не найден."
        pause
        return
    fi

    printf "  Snapshot: ${CYAN}%s${RESET}\n" "$latest_snapshot"
    printf "\n"
    warning "Восстановление изменит системную конфигурацию."

    printf "  Для подтверждения введите ${BOLD}RESTORE${RESET}: "
    read -r restore_answer

    [ "$restore_answer" = "RESTORE" ] || {
        warning "Восстановление отменено."
        pause
        return
    }

    if tar -tzf "$latest_snapshot" 2>/dev/null |
        grep -Eq '(^/|(^|/)\.\.(/|$))'; then
        error "Архив содержит небезопасные пути."
        pause
        return
    fi

    if tar -xzf "$latest_snapshot" -C / 2>/dev/null; then
        success "Snapshot восстановлен."
        timeline_log "SNAPSHOT restored: $latest_snapshot"

        warning "Для полного применения конфигурации рекомендуется перезагрузка."
        pause
    else
        error "Не удалось восстановить snapshot."
        pause
    fi
}

# --------------------------------------------------------------------
# USB BACKUP
# --------------------------------------------------------------------

find_usb_mount() {
    for mount_path in /mnt/* /tmp/mountd/* /media/*; do
        [ -d "$mount_path" ] || continue

        mount_device="$(df "$mount_path" 2>/dev/null |
            awk 'NR==2 {print $1}')"

        case "$mount_device" in
            /dev/sd*|/dev/mmcblk*p*|/dev/usb*)
                printf '%s' "$mount_path"
                return 0
                ;;
        esac
    done

    return 1
}

find_usb_partition() {
    for usb_device in \
        /dev/sd[a-z][0-9] \
        /dev/mmcblk[0-9]p[0-9]; do

        [ -b "$usb_device" ] || continue

        printf '%s' "$usb_device"
        return 0
    done

    return 1
}

format_usb_for_runettoday() {
    format_device="$1"

    printf "\n"
    warning "Форматирование $format_device удалит с него ВСЕ файлы."

    printf "  Для форматирования введите ${BOLD}FORMAT${RESET}: "
    read -r format_answer

    [ "$format_answer" = "FORMAT" ] || {
        warning "Форматирование отменено."
        return 1
    }

    if ! command_exists mkfs.ext4; then
        warning "mkfs.ext4 не найден."

        printf "  Установить поддержку ext4? [y/N]: "
        read -r install_answer

        case "$install_answer" in
            y|Y|yes|YES)
                if ! opkg update ||
                    ! opkg install e2fsprogs kmod-fs-ext4; then
                    error "Не удалось установить поддержку ext4."
                    return 1
                fi
                ;;
            *)
                return 1
                ;;
        esac
    fi

    umount "$format_device" 2>/dev/null

    if ! mkfs.ext4 -F "$format_device" >/dev/null 2>&1; then
        error "Форматирование не удалось."
        return 1
    fi

    mkdir -p /mnt/runettoday-usb

    if mount -t ext4 "$format_device" /mnt/runettoday-usb 2>/dev/null; then
        USB_MOUNT="/mnt/runettoday-usb"
        success "Флешка отформатирована и смонтирована."
        return 0
    fi

    error "Не удалось смонтировать ext4."
    return 1
}

prepare_usb() {
    USB_MOUNT="$(find_usb_mount 2>/dev/null)"

    [ -n "$USB_MOUNT" ] && return 0

    printf "  ${DIM}Поиск USB-флешки…${RESET}\n"

    usb_wait=0

    while [ "$usb_wait" -lt 15 ]; do
        USB_MOUNT="$(find_usb_mount 2>/dev/null)"

        [ -n "$USB_MOUNT" ] && return 0

        usb_wait=$((usb_wait + 1))
        sleep 1
    done

    USB_DEVICE="$(find_usb_partition)"

    if [ -z "$USB_DEVICE" ]; then
        error "USB-флешка не найдена."
        return 1
    fi

    warning "Найден раздел $USB_DEVICE, но он не смонтирован."

    printf "  Смонтировать его? [y/N]: "
    read -r usb_answer

    case "$usb_answer" in
        y|Y|yes|YES)
            ;;
        *)
            return 1
            ;;
    esac

    mkdir -p /mnt/runettoday-usb

    if mount "$USB_DEVICE" /mnt/runettoday-usb 2>/dev/null; then
        USB_MOUNT="/mnt/runettoday-usb"
        success "Флешка смонтирована: $USB_MOUNT"
        return 0
    fi

    warning "Файловая система не смонтировалась."

    format_usb_for_runettoday "$USB_DEVICE"
}

create_usb_backup() {
    screen_title \
        "BACKUP / USB DRIVE" \
        "Create a portable RunetToday configuration backup"

    prepare_usb || {
        pause
        return
    }

    backup_stamp="$(date '+%Y%m%d-%H%M%S')"
    backup_router="$(router_name | tr -cd 'A-Za-z0-9._-')"

    [ -n "$backup_router" ] || backup_router="openwrt"

    backup_file="$USB_MOUNT/runettoday-backup-$backup_router-$backup_stamp.tar.gz"
    package_list="/tmp/runettoday-packages-$backup_stamp.txt"
    backup_info="/tmp/runettoday-backup-info-$backup_stamp.txt"

    if command_exists opkg; then
        opkg list-installed 2>/dev/null |
            awk '{print $1}' > "$package_list"
    else
        : > "$package_list"
    fi

    {
        printf 'RunetToday backup\n'
        printf 'Router: %s\n' "$(router_name)"
        printf 'Created: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf 'Version: %s\n' "$APP_VERSION"
        printf 'OpenWrt: %s\n' "$(cat /etc/openwrt_version 2>/dev/null)"
    } > "$backup_info"

    set -- etc/config etc/profile

    [ -d /etc/dropbear ] &&
        set -- "$@" etc/dropbear

    [ -d "$RUNETTODAY_DIR" ] &&
        set -- "$@" etc/runettoday

    [ -f /etc/sysupgrade.conf ] &&
        set -- "$@" etc/sysupgrade.conf

    set -- "$@" \
        tmp/"$(basename "$package_list")" \
        tmp/"$(basename "$backup_info")"

    cp "$package_list" "/tmp/$(basename "$package_list")"
    cp "$backup_info" "/tmp/$(basename "$backup_info")"

    printf "\n  Собираем бэкап…\n"

    if tar -czf "$backup_file" -C / "$@"; then
        success "Бэкап сохранён."

        printf "  ${DIM}%s${RESET}\n" "$backup_file"
        printf "  Размер: ${CYAN}%s${RESET}\n" \
            "$(du -h "$backup_file" 2>/dev/null | awk '{print $1}')"

        timeline_log "USB_BACKUP created: $backup_file"
    else
        error "Не удалось создать бэкап."
    fi

    rm -f "$package_list" "$backup_info"
    rm -f "/tmp/$(basename "$package_list")"
    rm -f "/tmp/$(basename "$backup_info")"

    pause
}

restore_usb_backup() {
    screen_title \
        "RESTORE / USB DRIVE" \
        "Restore settings from a RunetToday backup"

    prepare_usb || {
        pause
        return
    }

    printf "  Доступные бэкапы:\n\n"

    ls -1 "$USB_MOUNT"/runettoday-backup-*.tar.gz 2>/dev/null |
        while IFS= read -r listed_backup; do
            printf "  ${CYAN}•${RESET} %s\n" "$(basename "$listed_backup")"
        done

    latest_backup="$(ls -t \
        "$USB_MOUNT"/runettoday-backup-*.tar.gz \
        2>/dev/null | head -n 1)"

    [ -n "$latest_backup" ] || {
        error "На флешке нет RunetToday backup."
        pause
        return
    }

    printf "\n  Enter — последний backup.\n"
    printf "  Или введите имя файла: "
    read -r restore_choice

    if [ -n "$restore_choice" ]; then
        case "$restore_choice" in
            */*|*..*)
                error "Укажите только имя файла."
                pause
                return
                ;;
        esac

        latest_backup="$USB_MOUNT/$restore_choice"
    fi

    [ -f "$latest_backup" ] || {
        error "Выбранный файл не найден."
        pause
        return
    }

    if tar -tzf "$latest_backup" 2>/dev/null |
        grep -Eq '(^/|(^|/)\.\.(/|$))'; then
        error "Архив содержит небезопасные пути."
        pause
        return
    fi

    printf "\n  Выбран: ${CYAN}%s${RESET}\n" \
        "$(basename "$latest_backup")"

    printf "  Для подтверждения введите ${BOLD}RESTORE${RESET}: "
    read -r restore_answer

    [ "$restore_answer" = "RESTORE" ] || {
        warning "Восстановление отменено."
        pause
        return
    }

    snapshot_before_change || {
        pause
        return
    }

    if tar -xzf "$latest_backup" -C /; then
        success "Настройки восстановлены."
        timeline_log "USB_RESTORE applied: $latest_backup"

        warning "Роутер будет перезагружен через 5 секунд."
        sync
        sleep 5
        reboot
    else
        error "Не удалось распаковать backup."
        pause
    fi
}

# --------------------------------------------------------------------
# NETWORK / SYSTEM
# --------------------------------------------------------------------

show_network() {
    screen_title \
        "NETWORK / STATUS" \
        "Interfaces, routes, addresses and DNS"

    printf "  ${CYAN}INTERFACES${RESET}\n\n"

    if command_exists ubus; then
        ubus call network.interface dump 2>/dev/null |
            jsonfilter -e '@.interface[*].interface' 2>/dev/null |
            while IFS= read -r iface; do
                [ -n "$iface" ] || continue

                printf "  ${BOLD}%s${RESET}\n" "$iface"
                ubus call "network.interface.$iface" status 2>/dev/null |
                    jsonfilter -e \
                    '{up,device,proto,ipv4-address,ipv6-address}' \
                    2>/dev/null
                printf "\n"
            done
    else
        ifconfig 2>/dev/null
    fi

    printf "\n  ${CYAN}DEFAULT ROUTE${RESET}\n"
    ip route 2>/dev/null |
        grep '^default' |
        head -n 5

    printf "\n  ${CYAN}DNS${RESET}\n"

    if [ -f /tmp/resolv.conf.d/resolv.conf.auto ]; then
        cat /tmp/resolv.conf.d/resolv.conf.auto
    elif [ -f /tmp/resolv.conf ]; then
        cat /tmp/resolv.conf
    else
        cat /etc/resolv.conf 2>/dev/null
    fi

    pause
}

network_diagnostics() {
    screen_title \
        "NETWORK / DIAGNOSTICS" \
        "Connectivity tests from the router"

    printf "  ${CYAN}1${RESET}  Gateway\n"
    printf "  ${CYAN}2${RESET}  DNS\n"
    printf "  ${CYAN}3${RESET}  Internet IP\n"
    printf "  ${CYAN}4${RESET}  HTTP/HTTPS\n"
    printf "  ${CYAN}5${RESET}  Back\n\n"

    printf "  ${CYAN}${BOLD}NETWORK › ${RESET}"
    read -r network_choice

    case "$network_choice" in
        1)
            printf "\n"
            ip route 2>/dev/null | grep '^default'
            ;;
        2)
            printf "\n"
            nslookup openwrt.org 2>&1
            ;;
        3)
            printf "\n"
            if command_exists wget; then
                wget -qO- --timeout=10 \
                    https://api.ipify.org 2>/dev/null
                printf "\n"
            elif command_exists uclient-fetch; then
                uclient-fetch -qO- \
                    https://api.ipify.org 2>/dev/null
                printf "\n"
            else
                warning "wget/uclient-fetch не найден."
            fi
            ;;
        4)
            printf "\n"
            if command_exists uclient-fetch; then
                if uclient-fetch -qO /dev/null \
                    https://www.google.com; then
                    success "HTTPS доступен."
                else
                    error "HTTPS недоступен."
                fi
            elif command_exists wget; then
                if wget -qO /dev/null \
                    --timeout=10 https://www.google.com; then
                    success "HTTPS доступен."
                else
                    error "HTTPS недоступен."
                fi
            else
                warning "Нет HTTP-клиента."
            fi
            ;;
        *)
            return
            ;;
    esac

    pause
}

# --------------------------------------------------------------------
# DASHBOARD
# --------------------------------------------------------------------

show_dashboard() {
    screen_title \
        "DASHBOARD / SYSTEM STATUS" \
        "Live health overview for this router"

    printf "  ${CYAN}ROUTER${RESET}  %s\n" "$(router_name)"
    printf "  ${CYAN}TIME${RESET}    %s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf "  ${CYAN}SSH${RESET}     port %s\n" "$(ssh_port)"

    printf "\n  ${BOLD}UPTIME${RESET}\n"
    uptime

    printf "\n  ${BOLD}MEMORY${RESET}\n"
    free 2>/dev/null |
        awk 'NR==1 || /Mem:/ {print "  "$0}'

    printf "\n  ${BOLD}STORAGE${RESET}\n"
    df -h 2>/dev/null |
        awk 'NR==1 || /overlay|rootfs/ {print "  "$0}'

    printf "\n  ${BOLD}SERVICES${RESET}\n"

    if /etc/init.d/firewall enabled >/dev/null 2>&1; then
        printf "  ${GREEN}●${RESET} Firewall: enabled\n"
    else
        printf "  ${YELLOW}●${RESET} Firewall: not enabled\n"
    fi

    if /etc/init.d/dropbear running >/dev/null 2>&1; then
        printf "  ${GREEN}●${RESET} SSH: running\n"
    else
        printf "  ${RED}●${RESET} SSH: stopped\n"
    fi

    if command_exists tailscale &&
        tailscale status >/dev/null 2>&1; then
        printf "  ${GREEN}●${RESET} Tailscale: online\n"
    else
        printf "  ${YELLOW}●${RESET} Tailscale: unavailable/offline\n"
    fi

    if command_exists adblock &&
        /etc/init.d/adblock running >/dev/null 2>&1; then
        printf "  ${GREEN}●${RESET} AdBlock: active\n"
    else
        printf "  ${DIM}●${RESET} AdBlock: inactive\n"
    fi

    printf "\n  ${BOLD}SECURITY${RESET}\n"

    key_count="$(awk '
        NF && $1 !~ /^#/ {count++}
        END {print count+0}
    ' /etc/dropbear/authorized_keys 2>/dev/null)"

    printf "  SSH keys: %s\n" "$key_count"

    password_auth="$(
        uci -q get \
        'dropbear.@dropbear[0].PasswordAuth' \
        2>/dev/null || printf '1'
    )"

    if [ "$password_auth" = "0" ]; then
        printf "  Password SSH: ${GREEN}disabled${RESET}\n"
    else
        printf "  Password SSH: ${YELLOW}enabled${RESET}\n"
    fi

    printf "  TOTP: %s\n" "$(totp_status)"

    printf "\n  ${BOLD}ADBLOCK${RESET}\n"
    printf "  Domains: %s\n" "$(adblock_domain_count)"

    pause
}

# --------------------------------------------------------------------
# SECURITY
# --------------------------------------------------------------------

configure_ssh_safe_mode() {
    screen_title \
        "SSH / SAFE MODE" \
        "Keys first, passwords disabled only after verification"

    key_file="/etc/dropbear/authorized_keys"

    key_count="$(awk '
        NF && $1 !~ /^#/ {count++}
        END {print count+0}
    ' "$key_file" 2>/dev/null)"

    password_auth="$(
        uci -q get \
        'dropbear.@dropbear[0].PasswordAuth' \
        2>/dev/null || printf '1'
    )"

    printf "  Ключей: ${CYAN}%s${RESET}\n" "$key_count"
    printf "  Вход по паролю: ${CYAN}%s${RESET}\n\n" "$password_auth"

    if [ "$password_auth" = "0" ]; then
        success "Безопасный режим уже включён."
        pause
        return
    fi

    if [ "$key_count" -lt 1 ]; then
        error "SSH-ключей нет. Сначала добавьте ключ."
        pause
        return
    fi

    warning "Убедитесь, что вход по ключу уже проверен."

    confirm || {
        warning "Изменение отменено."
        pause
        return
    }

    snapshot_before_change || {
        pause
        return
    }

    if uci set 'dropbear.@dropbear[0].PasswordAuth=0' &&
        uci set 'dropbear.@dropbear[0].RootPasswordAuth=0' &&
        uci commit dropbear &&
        /etc/init.d/dropbear restart; then

        success "Парольный SSH-вход отключён."
        timeline_log "SSH_SAFE_MODE enabled"
    else
        error "Не удалось изменить настройки SSH."
    fi

    pause
}

configure_root_password() {
    screen_title \
        "ROOT / CREDENTIALS" \
        "Update administrator credentials"

    warning "Используйте длинный уникальный пароль."
    passwd root

    timeline_log "ROOT_PASSWORD changed"
    pause
}

# --------------------------------------------------------------------
# SSH PORT WITH ROLLBACK
# --------------------------------------------------------------------

schedule_port_rollback() {
    old_port="$1"
    new_port="$2"

    rollback_state="/tmp/runettoday-port-rollback"

    rm -f "$rollback_state"

    (
        trap '' HUP

        sleep 90

        [ -f "$rollback_state" ] || exit 0

        uci set "dropbear.@dropbear[0].Port=$old_port"
        uci commit dropbear
        /etc/init.d/dropbear restart

        rm -f "$rollback_state"
    ) >/dev/null 2>&1 &

    rollback_pid=$!

    printf '%s|%s|%s\n' \
        "$old_port" "$new_port" "$rollback_pid" \
        > "$rollback_state"
}

confirm_port_change() {
    rollback_state="/tmp/runettoday-port-rollback"

    [ -f "$rollback_state" ] || {
        warning "Нет ожидающего подтверждения."
        return 1
    }

    IFS='|' read -r old_port new_port rollback_pid \
        < "$rollback_state"

    if [ "$(ssh_port)" != "$new_port" ]; then
        error "Текущий SSH-порт не совпадает."
        return 1
    fi

    kill "$rollback_pid" 2>/dev/null
    rm -f "$rollback_state"

    success "SSH-порт $new_port подтверждён."
    timeline_log "SSH_PORT confirmed: $new_port"

    return 0
}

configure_ssh_port() {
    screen_title \
        "SSH / ACCESS PORT" \
        "Change remote access port with automatic rollback"

    old_ssh_port="$(ssh_port)"

    printf "  Текущий порт: ${CYAN}${BOLD}%s${RESET}\n\n" \
        "$old_ssh_port"

    printf "  Новый порт ${DIM}(1–65535):${RESET} "
    read -r new_port

    [ -z "$new_port" ] && return

    case "$new_port" in
        *[!0-9]*)
            error "Порт должен состоять только из цифр."
            pause
            return
            ;;
    esac

    if [ "$new_port" -lt 1 ] 2>/dev/null ||
        [ "$new_port" -gt 65535 ] 2>/dev/null; then
        error "Допустимы значения от 1 до 65535."
        pause
        return
    fi

    [ "$new_port" = "$old_ssh_port" ] && {
        warning "Этот порт уже используется."
        pause
        return
    }

    printf "\n  Подключение:\n"
    printf "  ${CYAN}ssh root@IP -p %s${RESET}\n" "$new_port"

    confirm || {
        warning "Изменение отменено."
        pause
        return
    }

    snapshot_before_change || {
        pause
        return
    }

    if uci set "dropbear.@dropbear[0].Port=$new_port" &&
        uci commit dropbear; then

        schedule_port_rollback "$old_ssh_port" "$new_port"

        if /etc/init.d/dropbear restart; then
            success "SSH-порт изменён на $new_port."
            timeline_log \
                "SSH_PORT changed: $old_ssh_port -> $new_port"

            warning "Автооткат через 90 секунд."

            printf "\n"
            printf "  Подключитесь на новый порт.\n"
            printf "  Затем выполните:\n"
            printf "  ${CYAN}%s --confirm-port${RESET}\n" "$0"
        else
            error "Dropbear не перезапустился."
        fi
    else
        error "Не удалось изменить порт."
    fi

    pause
}

# --------------------------------------------------------------------
# FIREWALL
# --------------------------------------------------------------------

configure_firewall() {
    screen_title \
        "FIREWALL / BASELINE" \
        "SYN flood and invalid packet protection"

    printf "  Будут включены:\n"
    printf "  ${CYAN}•${RESET} SYN flood protection\n"
    printf "  ${CYAN}•${RESET} Drop invalid packets\n\n"

    snapshot_before_change || {
        pause
        return
    }

    if uci set 'firewall.@defaults[0].syn_flood=1' &&
        uci set 'firewall.@defaults[0].drop_invalid=1' &&
        uci commit firewall &&
        /etc/init.d/firewall restart; then

        success "Базовая защита firewall включена."
        timeline_log "FIREWALL_BASELINE enabled"
    else
        error "Не удалось применить firewall."
    fi

    pause
}

# --------------------------------------------------------------------
# BANIP
# --------------------------------------------------------------------

configure_banip() {
    screen_title \
        "BANIP / THREAT FEEDS" \
        "Optional blocklists for hostile networks"

    if ! command_exists banip; then
        warning "banIP не установлен."

        confirm || {
            warning "Установка отменена."
            pause
            return
        }

        if ! opkg update || ! opkg install banip; then
            error "Не удалось установить banIP."
            pause
            return
        fi
    fi

    snapshot_before_change || {
        pause
        return
    }

    if uci set 'banip.global.ban_enabled=1' &&
        uci commit banip &&
        /etc/init.d/banip enable &&
        /etc/init.d/banip restart; then

        success "banIP включён."
        timeline_log "BANIP enabled"
    else
        error "Не удалось включить banIP."
    fi

    pause
}

# --------------------------------------------------------------------
# PANIC MODE
# --------------------------------------------------------------------

enable_panic_mode() {
    screen_title \
        "PANIC MODE" \
        "Temporarily block LAN clients from Internet"

    warning "Интернет клиентов будет отключён на 5 минут."
    warning "Доступ к самому роутеру из LAN сохранится."

    printf "\n  Для подтверждения введите ${BOLD}PANIC${RESET}: "
    read -r panic_answer

    [ "$panic_answer" = "PANIC" ] || {
        warning "Panic Mode отменён."
        pause
        return
    }

    snapshot_before_change || {
        pause
        return
    }

    if uci set 'firewall.runettoday_panic=rule' &&
        uci set \
        'firewall.runettoday_panic.name=RunetToday Panic WAN Lockdown' &&
        uci set 'firewall.runettoday_panic.src=lan' &&
        uci set 'firewall.runettoday_panic.dest=wan' &&
        uci set 'firewall.runettoday_panic.target=REJECT' &&
        uci commit firewall &&
        /etc/init.d/firewall restart; then

        (
            trap '' HUP
            sleep 300

            uci -q delete firewall.runettoday_panic
            uci commit firewall
            /etc/init.d/firewall restart

            timeline_log "PANIC_MODE auto rollback completed"
        ) >/dev/null 2>&1 &

        success "Panic Mode включён."
        warning "Автоматическое восстановление через 5 минут."

        timeline_log "PANIC_MODE enabled"
    else
        error "Не удалось включить Panic Mode."
    fi

    pause
}

# --------------------------------------------------------------------
# TOTP
# --------------------------------------------------------------------

base32_value() {
    case "$1" in
        A) printf 0 ;; B) printf 1 ;; C) printf 2 ;; D) printf 3 ;;
        E) printf 4 ;; F) printf 5 ;; G) printf 6 ;; H) printf 7 ;;
        I) printf 8 ;; J) printf 9 ;; K) printf 10 ;; L) printf 11 ;;
        M) printf 12 ;; N) printf 13 ;; O) printf 14 ;; P) printf 15 ;;
        Q) printf 16 ;; R) printf 17 ;; S) printf 18 ;; T) printf 19 ;;
        U) printf 20 ;; V) printf 21 ;; W) printf 22 ;; X) printf 23 ;;
        Y) printf 24 ;; Z) printf 25 ;; 2) printf 26 ;; 3) printf 27 ;;
        4) printf 28 ;; 5) printf 29 ;; 6) printf 30 ;; 7) printf 31 ;;
        *) return 1 ;;
    esac
}

base32_to_hex_16() {
    input="$1"
    output=""

    while [ -n "$input" ]; do
        chunk="$(printf '%s' "$input" | cut -c 1-8)"
        input="$(printf '%s' "$input" | cut -c 9-)"

        b0="$(base32_value "$(printf '%s' "$chunk" | cut -c 1)")" || return 1
        b1="$(base32_value "$(printf '%s' "$chunk" | cut -c 2)")" || return 1
        b2="$(base32_value "$(printf '%s' "$chunk" | cut -c 3)")" || return 1
        b3="$(base32_value "$(printf '%s' "$chunk" | cut -c 4)")" || return 1
        b4="$(base32_value "$(printf '%s' "$chunk" | cut -c 5)")" || return 1
        b5="$(base32_value "$(printf '%s' "$chunk" | cut -c 6)")" || return 1
        b6="$(base32_value "$(printf '%s' "$chunk" | cut -c 7)")" || return 1
        b7="$(base32_value "$(printf '%s' "$chunk" | cut -c 8)")" || return 1

        output="$output$(printf '%02x%02x%02x%02x%02x' \
            $(((b0 << 3) | (b1 >> 2))) \
            $((((b1 & 3) << 6) | (b2 << 1) | (b3 >> 4))) \
            $((((b3 & 15) << 4) | (b4 >> 1))) \
            $((((b4 & 1) << 7) | (b5 << 2) | (b6 >> 3))) \
            $((((b6 & 7) << 5) | b7)))"
    done

    printf '%s' "$output"
}

generate_totp_secret() {
    alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'

    if command_exists openssl; then
        attempt=0

        while [ "$attempt" -lt 5 ]; do
            secret="$(
                openssl rand -base64 48 2>/dev/null |
                tr -dc 'A-Z2-7' |
                cut -c 1-16
            )"

            if [ "${#secret}" -eq 16 ]; then
                printf '%s' "$secret"
                return 0
            fi

            attempt=$((attempt + 1))
        done
    fi

    secret=""
    index=0

    while [ "$index" -lt 16 ]; do
        byte="$(
            od -An -N1 -tu1 /dev/urandom 2>/dev/null |
            tr -d ' '
        )"

        [ -n "$byte" ] || return 1

        char="$(
            printf '%s' "$alphabet" |
            cut -c $((byte % 32 + 1))
        )"

        secret="$secret$char"
        index=$((index + 1))
    done

    printf '%s' "$secret"
}

install_totp_profile() {
    screen_title \
        "TOTP / SSH SECURITY" \
        "Additional TOTP challenge for interactive SSH sessions"

    if ! command_exists openssl; then
        error "OpenSSL не найден."
        pause
        return
    fi

    initialize_runettoday

    selected_secret=""

    if [ -f "$RUNETTODAY_DIR/2fa.conf" ]; then
        . "$RUNETTODAY_DIR/2fa.conf"

        printf "  TOTP уже настроен.\n"
        printf "  Enter — оставить текущий.\n"
        printf "  N — создать новый.\n"
        printf "  Или введите свою Base32-фразу.\n\n"
        printf "  › "
        read -r requested_secret

        case "$requested_secret" in
            '')
                selected_secret="$RUNETTODAY_TOTP_SECRET"
                ;;
            n|N)
                selected_secret="$(generate_totp_secret)"
                ;;
            *)
                selected_secret="$requested_secret"
                ;;
        esac
    else
        printf "  Создаём уникальный секрет для этого роутера.\n"
        printf "  Enter — автоматически сгенерировать.\n"
        printf "  Или введите свою Base32-фразу.\n\n"
        printf "  › "
        read -r requested_secret

        if [ -n "$requested_secret" ]; then
            selected_secret="$requested_secret"
        else
            selected_secret="$(generate_totp_secret)"
        fi
    fi

    selected_secret="$(
        printf '%s' "$selected_secret" |
        tr -d ' -' |
        tr 'a-z' 'A-Z'
    )"

    case "$selected_secret" in
        *[!A-Z2-7]*|'')
            error "Недопустимая Base32-фраза."
            pause
            return
            ;;
    esac

    [ "${#selected_secret}" -eq 16 ] || {
        error "Секрет должен содержать 16 символов."
        pause
        return
    }

    selected_hex="$(base32_to_hex_16 "$selected_secret")" || {
        error "Не удалось преобразовать TOTP secret."
        pause
        return
    }

    printf "\n"
    printf "  ${CYAN}╭──────────────────────────────╮${RESET}\n"
    printf "  ${CYAN}│${RESET}  ${WHITE}${BOLD}%s${RESET}  ${CYAN}│${RESET}\n" \
        "$selected_secret"
    printf "  ${CYAN}╰──────────────────────────────╯${RESET}\n\n"

    printf "  SHA-1 · 6 digits · 30 seconds\n"
    printf "  Добавьте этот секрет в Apple Passwords или другой TOTP-клиент.\n\n"

    snapshot_before_change || {
        pause
        return
    }

    mkdir -p "$RUNETTODAY_DIR"
    chmod 700 "$RUNETTODAY_DIR"

    umask 077

    {
        printf 'RUNETTODAY_TOTP_SECRET=%s\n' "$selected_secret"
        printf 'RUNETTODAY_TOTP_HEX_KEY=%s\n' "$selected_hex"
    } > "$RUNETTODAY_DIR/2fa.conf"

    chmod 600 "$RUNETTODAY_DIR/2fa.conf"

    cp /etc/profile /etc/profile.runettoday.bak 2>/dev/null || {
        error "Не удалось создать backup /etc/profile."
        pause
        return
    }

    sed -i \
        '/# --- RUNETTODAY 2FA START ---/,/# --- RUNETTODAY 2FA END ---/d' \
        /etc/profile

    cat >> /etc/profile <<'EOF'

# --- RUNETTODAY 2FA START ---
# Additional TOTP challenge for interactive SSH sessions.

if [ -n "$SSH_TTY" ] && [ -t 0 ]; then
    if [ ! -r /etc/runettoday/2fa.conf ]; then
        printf '\033[31m[RunetToday] TOTP configuration not found. Session closed.\033[0m\n'
        exit 1
    fi

    . /etc/runettoday/2fa.conf

    RUNETTODAY_AUTHENTICATED=0

    if command -v ntpd >/dev/null 2>&1; then
        printf '\033[2m[RunetToday] Synchronizing time… \033[0m'

        if ntpd -n -q -p pool.ntp.org >/dev/null 2>&1; then
            printf '\033[32mOK\033[0m\n'
        else
            printf '\033[33mFAILED\033[0m\n'
        fi
    fi

    for RUNETTODAY_ATTEMPT in 1 2 3; do
        printf '\033[33m[RunetToday 2FA] Enter 6-digit code: \033[0m'

        read -r RUNETTODAY_USER_CODE || exit 1

        RUNETTODAY_USER_CODE=$(
            printf '%s' "$RUNETTODAY_USER_CODE" |
            tr -d ' '
        )

        case "$RUNETTODAY_USER_CODE" in
            [0-9][0-9][0-9][0-9][0-9][0-9])
                ;;
            *)
                printf '\033[31m[RunetToday] Code must contain 6 digits.\033[0m\n'
                continue
                ;;
        esac

        RUNETTODAY_BASE_TIME=$(date +%s)

        for RUNETTODAY_OFFSET in 0 -1 1; do
            RUNETTODAY_STEP=$(
                (
                    RUNETTODAY_BASE_TIME / 30 +
                    RUNETTODAY_OFFSET
                )
            )

            RUNETTODAY_COUNTER_HEX=$(
                printf '%016x' "$RUNETTODAY_STEP"
            )

            RUNETTODAY_COUNTER_ESCAPED=$(
                printf '%s' "$RUNETTODAY_COUNTER_HEX" |
                sed 's/../\\x&/g'
            )

            RUNETTODAY_HMAC=$(
                printf '%b' "$RUNETTODAY_COUNTER_ESCAPED" |
                openssl dgst -sha1 \
                    -mac HMAC \
                    -macopt hexkey:"$RUNETTODAY_TOTP_HEX_KEY" 2>/dev/null |
                awk '{print $NF}' |
                tr 'A-Z' 'a-z'
            )

            [ "${#RUNETTODAY_HMAC}" -eq 40 ] || continue

            RUNETTODAY_LAST_NIBBLE=$(
                printf '%s' "$RUNETTODAY_HMAC" |
                tail -c 1
            )

            case "$RUNETTODAY_LAST_NIBBLE" in
                [0-9a-f])
                    ;;
                *)
                    continue
                    ;;
            esac

            RUNETTODAY_TRUNCATION_OFFSET=$(
                printf '%d' "0x$RUNETTODAY_LAST_NIBBLE"
            )

            RUNETTODAY_START=$(
                (
                    RUNETTODAY_TRUNCATION_OFFSET * 2 + 1
                )
            )

            RUNETTODAY_END=$(
                (
                    RUNETTODAY_START + 7
                )
            )

            RUNETTODAY_PART_HEX=$(
                printf '%s' "$RUNETTODAY_HMAC" |
                cut -c "$RUNETTODAY_START"-"$RUNETTODAY_END"
            )

            RUNETTODAY_PART=$(
                printf '%d' "0x$RUNETTODAY_PART_HEX"
            )

            RUNETTODAY_CODE=$(
                (
                    (RUNETTODAY_PART & 2147483647) % 1000000
                )
            )

            RUNETTODAY_CODE=$(
                printf '%06d' "$RUNETTODAY_CODE"
            )

            if [ "$RUNETTODAY_USER_CODE" = "$RUNETTODAY_CODE" ]; then
                RUNETTODAY_AUTHENTICATED=1
                break
            fi
        done

        [ "$RUNETTODAY_AUTHENTICATED" -eq 1 ] && break

        printf '\033[31m[RunetToday] Invalid code.\033[0m\n'
    done

    if [ "$RUNETTODAY_AUTHENTICATED" -eq 1 ]; then
        printf '\033[32m[RunetToday] Access granted.\033[0m\n'
    else
        printf '\033[31m[RunetToday] Too many attempts. Session closed.\033[0m\n'
        exit 1
    fi
fi

# --- RUNETTODAY 2FA END ---
EOF

    success "TOTP-проверка добавлена в /etc/profile."
    printf "  Backup: /etc/profile.runettoday.bak\n"

    timeline_log "TOTP configured"

    warning "Откройте новое SSH-подключение для проверки."
    pause
}

# --------------------------------------------------------------------
# ADBLOCK
# --------------------------------------------------------------------

adblock_dependencies() {
    if ! command_exists opkg; then
        error "opkg не найден."
        return 1
    fi

    if ! opkg update >/dev/null 2>&1; then
        error "Не удалось обновить список пакетов."
        return 1
    fi

    if ! command_exists wget &&
        ! command_exists uclient-fetch &&
        ! command_exists curl; then

        if ! opkg install wget-ssl >/dev/null 2>&1 &&
            ! opkg install uclient-fetch >/dev/null 2>&1; then
            error "Не удалось установить загрузчик."
            return 1
        fi
    fi

    if ! command_exists adblock; then
        if ! opkg install adblock >/dev/null 2>&1; then
            error "Не удалось установить adblock."
            return 1
        fi
    fi

    return 0
}

adblock_download() {
    adblock_url="$1"
    adblock_output="$2"

    if command_exists uclient-fetch; then
        uclient-fetch -q \
            -O "$adblock_output" \
            "$adblock_url" >/dev/null 2>&1
        return $?
    fi

    if command_exists wget; then
        wget -q \
            -O "$adblock_output" \
            "$adblock_url" >/dev/null 2>&1
        return $?
    fi

    if command_exists curl; then
        curl -fsSL \
            --connect-timeout 15 \
            --max-time 120 \
            -o "$adblock_output" \
            "$adblock_url" >/dev/null 2>&1
        return $?
    fi

    return 1
}

validate_feed_url() {
    case "$1" in
        https://raw.githubusercontent.com/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

adblock_write_feeds() {
    mkdir -p "$ADBLOCK_DIR" /etc/adblock || return 1

    validate_feed_url "$NOADS_RU_BLOCKER_URL" || return 1
    validate_feed_url "$NOADS_RU_BLOCKER_FL_URL" || return 1
    validate_feed_url "$ADBLOCK_EXTRA_FEED_URL" || return 1

    cat > "$ADBLOCK_CUSTOM_FEEDS" <<EOF
{
 "noads_ru_blockerfl": {
   "url": "$NOADS_RU_BLOCKER_FL_URL",
   "rule": "feed 0.0.0.0 2",
   "size": "XL",
   "descr": "NoADS_RU Hosts BlockerFL"
 },
 "noads_ru_blocker": {
   "url": "$NOADS_RU_BLOCKER_URL",
   "rule": "feed 0.0.0.0 2",
   "size": "L",
   "descr": "NoADS_RU Hosts Blocker"
 },
 "hagezi_pro": {
   "url": "$ADBLOCK_EXTRA_FEED_URL",
   "rule": "feed 0.0.0.0 2",
   "size": "XL",
   "descr": "HaGeZi Pro DNS Blocklist"
 }
}
EOF

    chmod 600 "$ADBLOCK_CUSTOM_FEEDS"
}

adblock_domain_count() {
    count="0"

    for list_file in \
        /tmp/dnsmasq.d/adb_list.overall \
        /var/run/adblock/adb_list.overall \
        /etc/adblock/adb_list.overall; do

        if [ -f "$list_file" ]; then
            count="$(
                grep -cE '^[^#[:space:]]' \
                "$list_file" 2>/dev/null
            )"

            printf '%s' "${count:-0}"
            return
        fi
    done

    printf '0'
}

adblock_install() {
    screen_title \
        "DNS / AD BLOCKER" \
        "Network-wide advertising and tracker protection"

    printf "  Источники:\n"
    printf "  ${CYAN}•${RESET} NoADS_RU Hosts Blocker\n"
    printf "  ${CYAN}•${RESET} NoADS_RU Hosts BlockerFL\n"
    printf "  ${CYAN}•${RESET} HaGeZi Pro\n\n"

    printf "  Списки загружаются с удалённых источников.\n\n"

    confirm || {
        warning "Настройка отменена."
        pause
        return
    }

    snapshot_before_change || {
        pause
        return
    }

    if ! adblock_dependencies; then
        pause
        return
    fi

    if ! adblock_write_feeds; then
        error "Не удалось создать конфигурацию списков."
        pause
        return
    fi

    success "Источники списков настроены."

    printf "  Загружаем актуальные списки…\n"

    if ! /etc/init.d/adblock reload \
        >/tmp/runettoday-adblock.log 2>&1; then

        error "Не удалось загрузить списки."

        printf "\n"
        tail -n 30 /tmp/runettoday-adblock.log 2>/dev/null

        pause
        return
    fi

    /etc/init.d/adblock enable >/dev/null 2>&1

    uci set adblock.global.adb_enabled='1' 2>/dev/null
    uci commit adblock 2>/dev/null

    mkdir -p /etc/crontabs

    if [ -f "$ADBLOCK_CRON" ]; then
        grep -v 'RUNETTODAY_ADBLOCK_UPDATE' \
            "$ADBLOCK_CRON" \
            > /tmp/runettoday-cron-new 2>/dev/null
    else
        : > /tmp/runettoday-cron-new
    fi

    printf '15 4 * * * /etc/init.d/adblock reload # RUNETTODAY_ADBLOCK_UPDATE\n' \
        >> /tmp/runettoday-cron-new

    mv /tmp/runettoday-cron-new "$ADBLOCK_CRON"
    chmod 600 "$ADBLOCK_CRON"

    /etc/init.d/cron enable >/dev/null 2>&1
    /etc/init.d/cron restart >/dev/null 2>&1

    count="$(adblock_domain_count)"

    success "DNS-блокировщик включён."

    printf "\n"
    printf "  ${GREEN}●${RESET} Status: ENABLED\n"
    printf "  ${GREEN}●${RESET} Domains: ${CYAN}%s${RESET}\n" "$count"
    printf "  ${GREEN}●${RESET} Update: daily 04:15\n"

    timeline_log "ADBLOCK enabled: $count domains"

    pause
}

adblock_update() {
    screen_title \
        "DNS / AD BLOCKER" \
        "Update remote blocklists"

    if ! command_exists adblock; then
        warning "AdBlock ещё не установлен."
        pause
        return
    fi

    printf "  Загружаем свежие списки…\n\n"

    if /etc/init.d/adblock reload \
        >/tmp/runettoday-adblock-update.log 2>&1; then

        count="$(adblock_domain_count)"

        success "Списки успешно обновлены."
        printf "  Доменов: ${CYAN}%s${RESET}\n" "$count"

        timeline_log "ADBLOCK updated: $count domains"
    else
        error "Не удалось обновить списки."
        tail -n 30 /tmp/runettoday-adblock-update.log 2>/dev/null
    fi

    pause
}

adblock_status() {
    screen_title \
        "DNS / AD BLOCKER" \
        "Current protection status"

    if ! command_exists adblock; then
        printf "  Status: ${YELLOW}NOT INSTALLED${RESET}\n"
        pause
        return
    fi

    if /etc/init.d/adblock running >/dev/null 2>&1; then
        printf "  Service: ${GREEN}RUNNING${RESET}\n"
    else
        printf "  Service: ${YELLOW}STOPPED${RESET}\n"
    fi

    enabled="$(
        uci -q get adblock.global.adb_enabled 2>/dev/null ||
        printf '0'
    )"

    if [ "$enabled" = "1" ]; then
        printf "  Enabled: ${GREEN}YES${RESET}\n"
    else
        printf "  Enabled: ${YELLOW}NO${RESET}\n"
    fi

    printf "  Domains: ${CYAN}%s${RESET}\n" \
        "$(adblock_domain_count)"

    printf "\n  Sources:\n"
    printf "  • NoADS_RU Hosts Blocker\n"
    printf "  • NoADS_RU Hosts BlockerFL\n"
    printf "  • HaGeZi Pro\n"

    if grep -q 'RUNETTODAY_ADBLOCK_UPDATE' \
        "$ADBLOCK_CRON" 2>/dev/null; then
        printf "\n  Automatic update: ${GREEN}YES${RESET}\n"
        printf "  Schedule: 04:15 daily\n"
    else
        printf "\n  Automatic update: ${YELLOW}NO${RESET}\n"
    fi

    pause
}

adblock_disable() {
    screen_title \
        "DNS / AD BLOCKER" \
        "Disable network-wide advertising protection"

    if ! command_exists adblock; then
        warning "AdBlock не установлен."
        pause
        return
    fi

    warning "DNS-блокировка будет отключена."
    printf "  Конфигурация останется на роутере.\n\n"

    confirm || {
        warning "Отключение отменено."
        pause
        return
    }

    snapshot_before_change || {
        pause
        return
    }

    if uci set adblock.global.adb_enabled='0' &&
        uci commit adblock &&
        /etc/init.d/adblock stop; then

        if [ -f "$ADBLOCK_CRON" ]; then
            grep -v 'RUNETTODAY_ADBLOCK_UPDATE' \
                "$ADBLOCK_CRON" \
                > /tmp/runettoday-cron-disabled 2>/dev/null

            mv /tmp/runettoday-cron-disabled "$ADBLOCK_CRON"
            chmod 600 "$ADBLOCK_CRON"

            /etc/init.d/cron restart >/dev/null 2>&1
        fi

        success "DNS-блокировщик отключён."
        timeline_log "ADBLOCK disabled"
    else
        error "Не удалось отключить AdBlock."
    fi

    pause
}

configure_adblock() {
    while :; do
        screen_title \
            "DNS / AD BLOCKER" \
            "Network-wide advertising & tracker protection"

        printf "  [1] Настроить блокировщик\n"
        printf "  [2] Обновить списки\n"
        printf "  [3] Статус\n"
        printf "  [4] Отключить\n"
        printf "  [5] Назад\n\n"

        printf "  ${CYAN}${BOLD}DNS / AD BLOCKER › ${RESET}"
        read -r adblock_choice

        case "$adblock_choice" in
            1) adblock_install ;;
            2) adblock_update ;;
            3) adblock_status ;;
            4) adblock_disable ;;
            5|q|Q|'') return ;;
            *) warning "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

# --------------------------------------------------------------------
# TAILSCALE
# --------------------------------------------------------------------

show_tailscale() {
    screen_title \
        "TAILSCALE / MESH" \
        "Private remote management network"

    if ! command_exists tailscale; then
        error "Tailscale не установлен."
        pause
        return
    fi

    printf "  ${CYAN}STATUS${RESET}\n\n"
    tailscale status 2>&1

    printf "\n  ${CYAN}IP ADDRESSES${RESET}\n"
    tailscale ip 2>/dev/null

    printf "\n  ${CYAN}VERSION${RESET}\n"
    tailscale version 2>/dev/null | head -n 3

    pause
}

tailscale_diagnostics() {
    screen_title \
        "TAILSCALE / DIAGNOSTICS" \
        "Connectivity and control-plane diagnostics"

    if ! command_exists tailscale; then
        error "Tailscale не установлен."
        pause
        return
    fi

    printf "  Проверка состояния…\n\n"

    tailscale status 2>&1

    printf "\n"

    if tailscale netcheck 2>/dev/null; then
        success "Netcheck завершён."
    else
        warning "Netcheck завершился с ошибкой."
    fi

    pause
}

tailscale_menu() {
    while :; do
        screen_title \
            "TAILSCALE" \
            "Private management network"

        printf "  [1] Status\n"
        printf "  [2] Diagnostics\n"
        printf "  [3] Restart service\n"
        printf "  [4] Back\n\n"

        printf "  ${CYAN}${BOLD}TAILSCALE › ${RESET}"
        read -r choice

        case "$choice" in
            1)
                show_tailscale
                ;;
            2)
                tailscale_diagnostics
                ;;
            3)
                if confirm; then
                    /etc/init.d/tailscale restart
                    timeline_log "TAILSCALE service restarted"
                fi
                pause
                ;;
            4|q|Q|'')
                return
                ;;
            *)
                warning "Неизвестная команда."
                ;;
        esac
    done
}

# --------------------------------------------------------------------
# CLIENTS
# --------------------------------------------------------------------

show_connected_devices() {
    screen_title \
        "CLIENTS / DEVICE AUDIT" \
        "Connected devices visible to this router"

    printf "  ${CYAN}DHCP LEASES${RESET}\n\n"

    if [ -f /tmp/dhcp.leases ]; then
        awk '{
            printf "  %-16s %-18s %s\n", $3, $2, $4
        }' /tmp/dhcp.leases
    else
        warning "DHCP lease database не найден."
    fi

    printf "\n  ${CYAN}WIRELESS${RESET}\n\n"

    if command_exists iwinfo; then
        for wifi_radio in $(
            iwinfo 2>/dev/null |
            awk '/ESSID:/ {print $1}'
        ); do
            printf "  ${BOLD}%s${RESET}\n" "$wifi_radio"
            iwinfo "$wifi_radio" assoclist 2>/dev/null
            printf "\n"
        done
    else
        warning "iwinfo не найден."
    fi

    timeline_log "DEVICE_AUDIT viewed"
    pause
}

# --------------------------------------------------------------------
# SECURITY TIMELINE
# --------------------------------------------------------------------

show_security_timeline() {
    screen_title \
        "SECURITY / TIMELINE" \
        "RunetToday actions and system security events"

    if [ -s "$RUNETTODAY_LOG" ]; then
        tail -n 100 "$RUNETTODAY_LOG"
    else
        warning "Событий пока нет."
    fi

    printf "\n  ${CYAN}BANIP EVENTS${RESET}\n"

    logread 2>/dev/null |
        grep -i banip |
        tail -n 20

    pause
}

# --------------------------------------------------------------------
# UPDATE CENTER
# --------------------------------------------------------------------

check_firmware_updates() {
    screen_title \
        "UPDATE CENTER" \
        "Check OpenWrt firmware upgrade availability"

    if ! command_exists owut; then
        warning "owut не установлен."

        printf "  Установить инструмент проверки? [y/N]: "
        read -r update_answer

        case "$update_answer" in
            y|Y|yes|YES)
                if ! opkg update ||
                    ! opkg install owut; then
                    error "Не удалось установить owut."
                    pause
                    return
                fi
                ;;
            *)
                pause
                return
                ;;
        esac
    fi

    printf "\n  Проверяем обновления без установки…\n\n"

    owut check

    timeline_log "UPDATE_CHECK executed"

    pause
}

# --------------------------------------------------------------------
# DIAGNOSTICS / DOCTOR
# --------------------------------------------------------------------

doctor_check() {
    doctor_name="$1"
    doctor_command="$2"

    printf "  %-28s " "$doctor_name"

    if sh -c "$doctor_command" >/dev/null 2>&1; then
        printf "${GREEN}OK${RESET}\n"
        return 0
    fi

    printf "${RED}FAIL${RESET}\n"
    return 1
}

run_doctor() {
    screen_title \
        "RUNETTODAY DOCTOR" \
        "System health and configuration diagnostics"

    passed=0
    failed=0

    printf "  ${CYAN}SYSTEM${RESET}\n"

    if [ -f /etc/openwrt_release ]; then
        printf "  %-28s ${GREEN}OK${RESET}\n" "OpenWrt"
        passed=$((passed + 1))
    else
        printf "  %-28s ${RED}FAIL${RESET}\n" "OpenWrt"
        failed=$((failed + 1))
    fi

    if command_exists uci; then
        printf "  %-28s ${GREEN}OK${RESET}\n" "UCI"
        passed=$((passed + 1))
    else
        printf "  %-28s ${RED}FAIL${RESET}\n" "UCI"
        failed=$((failed + 1))
    fi

    if command_exists ubus; then
        printf "  %-28s ${GREEN}OK${RESET}\n" "UBus"
        passed=$((passed + 1))
    else
        printf "  %-28s ${RED}FAIL${RESET}\n" "UBus"
        failed=$((failed + 1))
    fi

    printf "\n  ${CYAN}NETWORK${RESET}\n"

    if ip route 2>/dev/null | grep -q '^default'; then
        printf "  %-28s ${GREEN}OK${RESET}\n" "Default route"
        passed=$((passed + 1))
    else
        printf "  %-28s ${RED}FAIL${RESET}\n" "Default route"
        failed=$((failed + 1))
    fi

    if nslookup openwrt.org >/dev/null 2>&1; then
        printf "  %-28s ${GREEN}OK${RESET}\n" "DNS resolution"
        passed=$((passed + 1))
    else
        printf "  %-28s ${RED}FAIL${RESET}\n" "DNS resolution"
        failed=$((failed + 1))
    fi

    if command_exists uclient-fetch; then
        if uclient-fetch -qO /dev/null \
            https://www.google.com >/dev/null 2>&1; then
            printf "  %-28s ${GREEN}OK${RESET}\n" "HTTPS connectivity"
            passed=$((passed + 1))
        else
            printf "  %-28s ${RED}FAIL${RESET}\n" "HTTPS connectivity"
            failed=$((failed + 1))
        fi
    elif command_exists wget; then
        if wget -qO /dev/null \
            --timeout=10 https://www.google.com; then
            printf "  %-28s ${GREEN}OK${RESET}\n" "HTTPS connectivity"
            passed=$((passed + 1))
        else
            printf "  %-28s ${RED}FAIL${RESET}\n" "HTTPS connectivity"
            failed=$((failed + 1))
        fi
    else
        printf "  %-28s ${YELLOW}SKIP${RESET}\n" "HTTPS client"
    fi

    printf "\n  ${CYAN}SERVICES${RESET}\n"

    if /etc/init.d/firewall running >/dev/null 2>&1; then
        printf "  %-28s ${GREEN}OK${RESET}\n" "Firewall"
        passed=$((passed + 1))
    else
        printf "  %-28s ${RED}FAIL${RESET}\n" "Firewall"
        failed=$((failed + 1))
    fi

    if /etc/init.d/dnsmasq running >/dev/null 2>&1; then
        printf "  %-28s ${GREEN}OK${RESET}\n" "DNSMasq"
        passed=$((passed + 1))
    else
        printf "  %-28s ${RED}FAIL${RESET}\n" "DNSMasq"
        failed=$((failed + 1))
    fi

    if /etc/init.d/dropbear running >/dev/null 2>&1; then
        printf "  %-28s ${GREEN}OK${RESET}\n" "Dropbear SSH"
        passed=$((passed + 1))
    else
        printf "  %-28s ${RED}FAIL${RESET}\n" "Dropbear SSH"
        failed=$((failed + 1))
    fi

    printf "\n  ${CYAN}STORAGE${RESET}\n"

    if df /overlay >/dev/null 2>&1; then
        printf "  %-28s ${GREEN}OK${RESET}\n" "Overlay filesystem"
        passed=$((passed + 1))
    else
        printf "  %-28s ${RED}FAIL${RESET}\n" "Overlay filesystem"
        failed=$((failed + 1))
    fi

    printf "\n"
    printf "  Result: ${GREEN}%s passed${RESET}, ${RED}%s failed${RESET}\n" \
        "$passed" "$failed"

    timeline_log "DOCTOR executed: passed=$passed failed=$failed"

    pause
}

# --------------------------------------------------------------------
# REPORT
# --------------------------------------------------------------------

export_report() {
    screen_title \
        "REPORT / EXPORT" \
        "Create a compact RunetToday health report"

    report_stamp="$(date '+%Y%m%d-%H%M%S')"
    report_file="/tmp/runettoday-report-$report_stamp.txt"

    {
        printf 'RUNETTODAY HEALTH REPORT\n'
        printf '========================\n'
        printf 'Router: %s\n' "$(router_name)"
        printf 'Generated: %s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf 'Version: %s\n' "$APP_VERSION"

        printf '\n[ OPENWRT ]\n'
        cat /etc/openwrt_version 2>/dev/null

        printf '\n[ UPTIME ]\n'
        uptime

        printf '\n[ MEMORY ]\n'
        free 2>/dev/null

        printf '\n[ STORAGE ]\n'
        df -h 2>/dev/null

        printf '\n[ NETWORK ]\n'
        ip addr 2>/dev/null
        ip route 2>/dev/null

        printf '\n[ SSH ]\n'
        uci -q show dropbear 2>/dev/null

        printf '\n[ FIREWALL ]\n'
        uci -q show firewall 2>/dev/null | head -n 80

        printf '\n[ TAILSCALE ]\n'
        tailscale status 2>/dev/null

        printf '\n[ RECENT SYSTEM LOGS ]\n'
        logread 2>/dev/null | tail -n 80

        printf '\n[ RUNETTODAY TIMELINE ]\n'
        tail -n 80 "$RUNETTODAY_LOG" 2>/dev/null
    } > "$report_file"

    if prepare_usb; then
        report_target="$USB_MOUNT/$(basename "$report_file")"

        if cp "$report_file" "$report_target"; then
            success "Отчёт сохранён на флешке."
            printf "  %s\n" "$report_target"
        else
            warning "Не удалось скопировать отчёт."
            printf "  Локально: %s\n" "$report_file"
        fi
    else
        warning "Флешка не найдена."
        printf "  Отчёт: %s\n" "$report_file"
    fi

    timeline_log "REPORT exported: $report_file"

    pause
}

# --------------------------------------------------------------------
# SETTINGS
# --------------------------------------------------------------------

show_about() {
    screen_title \
        "RUNETTODAY / ABOUT" \
        "Security Control Deck"

    printf "  ${BOLD}%s${RESET}\n\n" "$APP_NAME"
    printf "  Version: %s\n" "$APP_VERSION"
    printf "  Config:  %s\n" "$RUNETTODAY_DIR"
    printf "  Log:     %s\n" "$RUNETTODAY_LOG"

    printf "\n  RunetToday предоставляет:\n"
    printf "  • OpenWrt diagnostics\n"
    printf "  • SSH security\n"
    printf "  • Firewall configuration\n"
    printf "  • TOTP verification\n"
    printf "  • DNS / AdBlock\n"
    printf "  • banIP\n"
    printf "  • Tailscale diagnostics\n"
    printf "  • USB backups\n"
    printf "  • Panic Mode\n"

    pause
}

settings_menu() {
    while :; do
        screen_title \
            "SETTINGS" \
            "RunetToday configuration"

        printf "  [1] Root password\n"
        printf "  [2] About\n"
        printf "  [3] Back\n\n"

        printf "  ${CYAN}${BOLD}SETTINGS › ${RESET}"
        read -r settings_choice

        case "$settings_choice" in
            1)
                configure_root_password
                ;;
            2)
                show_about
                ;;
            3|q|Q|'')
                return
                ;;
            *)
                warning "Неизвестная команда."
                ;;
        esac
    done
}

# --------------------------------------------------------------------
# SECURITY TOOLS
# --------------------------------------------------------------------

enterprise_tools() {
    while :; do
        screen_title \
            "SECURITY TOOLS" \
            "Audit, timeline, update checks and incident response"

        printf "  [1] Device Audit\n"
        printf "  [2] Security Timeline\n"
        printf "  [3] Update Center\n"
        printf "  [4] Panic Mode\n"
        printf "  [5] SSH Safe Mode\n"
        printf "  [6] Firewall Baseline\n"
        printf "  [7] Back\n\n"

        printf "  ${CYAN}${BOLD}SECURITY › ${RESET}"
        read -r enterprise_choice

        case "$enterprise_choice" in
            1) show_connected_devices ;;
            2) show_security_timeline ;;
            3) check_firmware_updates ;;
            4) enable_panic_mode ;;
            5) configure_ssh_safe_mode ;;
            6) configure_firewall ;;
            7|q|Q|'') return ;;
            *) warning "Неизвестная команда." ;;
        esac
    done
}

# --------------------------------------------------------------------
# MAIN MENU
# --------------------------------------------------------------------

screen_title() {
    clear_screen

    printf "\n${MAGENTA}╭────────────────────────────────────────────────────────────────╮${RESET}\n"
    printf "${MAGENTA}│${RESET}  ${WHITE}${BOLD}%-60s${RESET}  ${MAGENTA}│${RESET}\n" "$1"
    printf "${MAGENTA}│${RESET}  ${DIM}%-60s${RESET}  ${MAGENTA}│${RESET}\n" "$2"
    printf "${MAGENTA}╰────────────────────────────────────────────────────────────────╯${RESET}\n\n"
}

header() {
    clear_screen

    printf "\n${CYAN}╭────────────────────────────────────────────────────────────────╮${RESET}\n"
    printf "${CYAN}│${RESET}  ${WHITE}${BOLD}%-60s${RESET}  ${CYAN}│${RESET}\n" \
        "R U N E T T O D A Y   ◆   CONTROL DECK"
    printf "${CYAN}│${RESET}  ${DIM}%-60s${RESET}  ${CYAN}│${RESET}\n" \
        "OpenWrt security & network administration / $APP_VERSION"
    printf "${CYAN}╰────────────────────────────────────────────────────────────────╯${RESET}\n"
}

menu_item() {
    item_number="$1"
    item_label="$2"

    if [ "$current_pos" -eq "$item_number" ]; then
        printf \
            "  ${MAGENTA}│${RESET} ${CYAN}❯${RESET} ${WHITE}${BOLD}%-70s${RESET} ${MAGENTA}│${RESET}\n" \
            "$item_label"
    else
        printf \
            "  ${MAGENTA}│${RESET}   ${DIM}%-70s${RESET} ${MAGENTA}│${RESET}\n" \
            "$item_label"
    fi
}

run_selected() {
    case "$current_pos" in
        1) show_dashboard ;;
        2) create_usb_backup ;;
        3) restore_usb_backup ;;
        4) configure_ssh_port ;;
        5) configure_ssh_safe_mode ;;
        6) configure_firewall ;;
        7) install_totp_profile ;;
        8) configure_banip ;;
        9) configure_adblock ;;
        10) export_report ;;
        11) show_network ;;
        12) network_diagnostics ;;
        13) show_connected_devices ;;
        14) tailscale_menu ;;
        15) run_doctor ;;
        16) enterprise_tools ;;
        17) settings_menu ;;
        18) runettoday_login ;;
        19) runettoday_register ;;
    esac
}

# --------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------

show_help() {
    cat <<EOF
RunetToday — OpenWrt Control Deck

Usage:
  $0
  $0 --help
  $0 --version
  $0 --status
  $0 --doctor
  $0 --backup
  $0 --confirm-port

Options:
  --help          Show this help
  --version       Show version
  --status        Show router status
  --doctor        Run diagnostics
  --backup        Create local snapshot
  --confirm-port  Confirm changed SSH port

Interactive menu:
  1   Dashboard
  2   Backup / USB
  3   Restore / USB
  4   SSH / Port
  5   SSH / Safe Mode
  6   Firewall
  7   TOTP
  8   banIP
  9   DNS / AdBlock
  10  Report
  11  Network
  12  Network Diagnostics
  13  Clients
  14  Tailscale
  15  Doctor
  16  Security Tools
  17  Settings

EOF
}

show_status_cli() {
    printf 'RunetToday %s\n' "$APP_VERSION"
    printf 'Router: %s\n' "$(router_name)"
    printf 'OpenWrt: %s\n' "$(cat /etc/openwrt_version 2>/dev/null)"
    printf 'SSH port: %s\n' "$(ssh_port)"
    printf 'TOTP: %s\n' "$(totp_status)"

    if /etc/init.d/firewall running >/dev/null 2>&1; then
        printf 'Firewall: RUNNING\n'
    else
        printf 'Firewall: STOPPED\n'
    fi

    if /etc/init.d/dropbear running >/dev/null 2>&1; then
        printf 'SSH: RUNNING\n'
    else
        printf 'SSH: STOPPED\n'
    fi

    if command_exists adblock &&
        /etc/init.d/adblock running >/dev/null 2>&1; then
        printf 'AdBlock: RUNNING\n'
    else
        printf 'AdBlock: OFF\n'
    fi

    if command_exists tailscale &&
        tailscale status >/dev/null 2>&1; then
        printf 'Tailscale: ONLINE\n'
    else
        printf 'Tailscale: OFFLINE/UNAVAILABLE\n'
    fi
}

create_cli_backup() {
    initialize_runettoday

    if snapshot_before_change; then
        printf '%s\n' \
            "$RUNETTODAY_SNAPSHOT_DIR/latest.tar.gz"
        return 0
    fi

    return 1
}

# --------------------------------------------------------------------
# MACOS UNIVERSAL AUDIT
# --------------------------------------------------------------------

universal_probe() {
    universal_target="$1"
    universal_port="${2:-22}"

    universal_result="$(mktemp -t runettoday-probe.XXXXXX)" ||
        return 1

    if ssh \
        -o ConnectTimeout=8 \
        -p "$universal_port" \
        "$universal_target" '
        if command -v ubus >/dev/null 2>&1 &&
           [ -f /etc/openwrt_release ]; then

            echo PLATFORM=openwrt
            echo OS=OpenWrt

            if command -v jsonfilter >/dev/null 2>&1; then
                board=$(ubus call system board 2>/dev/null)

                echo "MODEL=$(printf "%s" "$board" |
                    jsonfilter -e "@.model")"

                echo "FIRMWARE=$(printf "%s" "$board" |
                    jsonfilter -e "@.release.description")"
            else
                echo "MODEL=$(cat /tmp/sysinfo/model 2>/dev/null)"
                echo "FIRMWARE=$(cat /etc/openwrt_version 2>/dev/null)"
            fi

            command -v uci >/dev/null 2>&1 &&
                echo CAP_UCI=1 ||
                echo CAP_UCI=0

            command -v iwinfo >/dev/null 2>&1 &&
                echo CAP_WIFI=1 ||
                echo CAP_WIFI=0

            command -v opkg >/dev/null 2>&1 &&
                echo CAP_PACKAGES=opkg ||
                echo CAP_PACKAGES=none

            [ -d /sys/class/block ] &&
                echo CAP_STORAGE=1 ||
                echo CAP_STORAGE=0

        elif [ -f /etc/os-release ]; then
            echo PLATFORM=linux

            echo "OS=$(grep "^PRETTY_NAME=" /etc/os-release |
                cut -d "=" -f 2- |
                tr -d "\"")"

            echo "MODEL=$(uname -m)"
            echo "FIRMWARE=$(uname -sr)"
        else
            exit 42
        fi
    ' > "$universal_result" 2>/dev/null &&
        grep -q '^PLATFORM=' "$universal_result"; then

        cat "$universal_result"
        rm -f "$universal_result"

        return 0
    fi

    rm -f "$universal_result"

    universal_routeros="$(
        ssh \
            -o ConnectTimeout=8 \
            -p "$universal_port" \
            "$universal_target" \
            '/system resource print' \
            2>/dev/null
    )" || return 1

    printf '%s\n' "$universal_routeros" |
        grep -qi 'uptime' || return 1

    printf '%s\n' \
        'PLATFORM=routeros' \
        'OS=MikroTik RouterOS' \
        'MODEL=RouterOS device' \
        'FIRMWARE=Detected via SSH CLI' \
        'CAP_UCI=0' \
        'CAP_WIFI=unknown' \
        'CAP_PACKAGES=routeros' \
        'CAP_STORAGE=unknown'
}

universal_fleet() {
    inventory="$1"

    [ -f "$inventory" ] || {
        printf 'Inventory file not found: %s\n' "$inventory" >&2
        return 2
    }

    printf '\nRUNETTODAY FLEET VIEW\n\n'

    printf '%-18s %-14s %-28s %-12s\n' \
        'NAME' 'PLATFORM' 'MODEL' 'STATUS'

    printf '%-18s %-14s %-28s %-12s\n' \
        '------------------' \
        '--------------' \
        '----------------------------' \
        '------------'

    while IFS='|' read -r fleet_name fleet_target fleet_port; do
        case "$fleet_name" in
            ''|'#'*) continue ;;
        esac

        [ -n "$fleet_port" ] || fleet_port=22

        fleet_data="$(
            universal_probe \
                "$fleet_target" \
                "$fleet_port" \
                2>/dev/null
        )"

        if [ -n "$fleet_data" ]; then
            fleet_platform="$(
                printf '%s\n' "$fleet_data" |
                sed -n 's/^PLATFORM=//p' |
                head -n 1
            )"

            fleet_model="$(
                printf '%s\n' "$fleet_data" |
                sed -n 's/^MODEL=//p' |
                head -n 1 |
                cut -c 1-28
            )"

            printf '%-18s %-14s %-28s %-12s\n' \
                "$fleet_name" \
                "$fleet_platform" \
                "$fleet_model" \
                'ONLINE'
        else
            printf '%-18s %-14s %-28s %-12s\n' \
                "$fleet_name" \
                '-' \
                '-' \
                'OFFLINE/AUTH'
        fi
    done < "$inventory"
}

# --------------------------------------------------------------------
# CLI ARGUMENT HANDLING
# --------------------------------------------------------------------

case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --version|-v)
        printf '%s %s\n' "$APP_NAME" "$APP_VERSION"
        exit 0
        ;;
    --status)
        initialize_runettoday
        show_status_cli
        exit 0
        ;;
    --doctor)
        initialize_runettoday
        run_doctor
        exit 0
        ;;
    --backup)
        initialize_runettoday
        create_cli_backup
        exit $?
        ;;
    --confirm-port)
        confirm_port_change
        exit $?
        ;;
    --audit)
        [ -n "${2:-}" ] || {
            printf \
                'Usage: %s --audit user@router-ip [ssh-port]\n' \
                "$0" >&2
            exit 2
        }

        universal_probe "$2" "${3:-22}" || {
            printf \
                'Router was not identified. Check SSH access and port.\n' \
                >&2
            exit 1
        }

        exit 0
        ;;
    --fleet)
        [ -n "${2:-}" ] || {
            printf \
                'Usage: %s --fleet routers.txt\n' \
                "$0" >&2
            exit 2
        }

        universal_fleet "$2"
        exit $?
        ;;
    "")
        ;;
    *)
        show_help
        exit 2
        ;;
esac

# --------------------------------------------------------------------
# INITIALIZATION
# --------------------------------------------------------------------

initialize_runettoday
migrate_legacy_configuration

# Synchronize time for TOTP.
if command_exists ntpd; then
    ntpd -n -q -p pool.ntp.org >/dev/null 2>&1
fi

# --------------------------------------------------------------------
# RUNETTODAY ACCOUNT
# --------------------------------------------------------------------

runettoday_cli() {
    if [ -x "$HOME/runettoday/cli/runettoday" ]; then
        "$HOME/runettoday/cli/runettoday" "$@"
    elif [ -x "/usr/bin/runettoday" ] && [ -d "/usr/lib/runettoday" ]; then
        /usr/bin/runettoday "$@"
    else
        error "RunetToday CLI не найден"
        return 1
    fi
}

runettoday_setup_telemetry() {
    if [ -x "$HOME/runettoday/cli/runettoday" ]; then
        "$HOME/runettoday/cli/runettoday" auto on
    elif [ -x /etc/init.d/runettoday ]; then
        /etc/init.d/runettoday enable
        /etc/init.d/runettoday start
        success "Автопост включён (init.d)"
    else
        warning "Не знаю как включить автопост"
    fi
}

runettoday_login() {
    clear_screen
    printf "${BOLD}${CYAN}RunetToday · Вход в аккаунт${RESET}\n\n"

    if ! runettoday_cli login; then
        printf "\n"
        error "Не удалось войти"
        pause
        return
    fi
    printf "\n"
    runettoday_setup_telemetry
    printf "\n"
    success "Всё готово. Данные уходят автоматически."
    pause
}

runettoday_register() {
    clear_screen
    printf "${BOLD}${CYAN}RunetToday · Создание аккаунта${RESET}\n\n"

    if ! runettoday_cli register; then
        printf "\n"
        error "Не удалось создать аккаунт"
        pause
        return
    fi
    printf "\n"
    runettoday_setup_telemetry
    printf "\n"
    success "Всё готово."
    pause
}

# --------------------------------------------------------------------
# INTERACTIVE CONTROL DECK
# --------------------------------------------------------------------

while :; do
    header

    printf "\n  ${DIM}SYSTEM STATUS${RESET}\n"

    printf \
        "  ${GREEN}●${RESET} SSH ${CYAN}%s${RESET}" \
        "$(ssh_port)"

    printf \
        "    ${GREEN}●${RESET} CLOCK ${CYAN}%s${RESET}" \
        "$(date '+%H:%M')"

    printf \
        "    ${GREEN}●${RESET} TOTP ${CYAN}%s${RESET}\n" \
        "$(totp_status)"

    printf "\n"
    printf \
        "  ${MAGENTA}╭─ CONTROL MENU ───────────────────────────────────────────────────────────╮${RESET}\n"

    menu_item 1 \
        '[1]  DASHBOARD               Router health / Статистика'

    menu_item 2 \
        '[2]  BACKUP / USB            Save configuration / Бэкап'

    menu_item 3 \
        '[3]  RESTORE / USB           Restore configuration / Восстановление'

    menu_item 4 \
        '[4]  SSH / PORT              Safe change + rollback / Порт SSH'

    menu_item 5 \
        '[5]  SSH / SAFE MODE         Keys only / Только ключи'

    menu_item 6 \
        '[6]  FIREWALL / BASELINE     Base protection / Firewall'

    menu_item 7 \
        '[7]  ROUTER / TOTP           Apple Passwords / TOTP'

    menu_item 8 \
        '[8]  BANIP / THREAT FEEDS    Threat blocking / BanIP'

    menu_item 9 \
        '[9]  DNS / AD BLOCKER        Ads & trackers / DNS'

    menu_item 10 \
        '[10] REPORT / EXPORT         Health report / Отчёт'

    menu_item 11 \
        '[11] NETWORK / STATUS        Interfaces / Сеть'

    menu_item 12 \
        '[12] NETWORK / DIAGNOSTICS   DNS / Internet tests'

    menu_item 13 \
        '[13] CLIENTS / DEVICES       DHCP / Wi-Fi clients'

    menu_item 14 \
        '[14] TAILSCALE               Private management'

    menu_item 15 \
        '[15] DOCTOR                  System diagnostics'

    menu_item 16 \
        '[16] SECURITY TOOLS          Audit / Panic / Updates'

    menu_item 17 \
        '[17] SETTINGS                Router administration'

    menu_item 18 \
        '[18] RUNETTODAY LOGIN        Войти в аккаунт'

    menu_item 19 \
        '[19] RUNETTODAY REGISTER     Создать аккаунт'

    printf \
        "  ${MAGENTA}╰────────────────────────────────────────────────────────────────────────╯${RESET}\n"

    printf "\n"
    printf \
        "  ${DIM}[w/s] navigation   [Enter] open   [1–9] quick select   [q] exit${RESET}\n"

    printf "\n"
    printf "  ${CYAN}${BOLD}RUNETTODAY › ${RESET}"

    read -r key

    case "$key" in
        w|W)
            [ "$current_pos" -gt 1 ] &&
                current_pos=$((current_pos - 1))
            ;;
        s|S)
            [ "$current_pos" -lt 19 ] &&
                current_pos=$((current_pos + 1))
            ;;
        1)
            current_pos=1
            run_selected
            ;;
        2)
            current_pos=2
            run_selected
            ;;
        3)
            current_pos=3
            run_selected
            ;;
        4)
            current_pos=4
            run_selected
            ;;
        5)
            current_pos=5
            run_selected
            ;;
        6)
            current_pos=6
            run_selected
            ;;
        7)
            current_pos=7
            run_selected
            ;;
        8)
            current_pos=8
            run_selected
            ;;
        9)
            current_pos=9
            run_selected
            ;;
        0)
            current_pos=10
            run_selected
            ;;
        '')
            run_selected
            ;;
        18|login|L)
            current_pos=18
            run_selected
            ;;
        19|register|R)
            current_pos=19
            run_selected
            ;;
        q|Q)
            clear_screen
            printf "${GREEN}RunetToday stopped. Берегите сеть!${RESET}\n"
            exit 0
            ;;
        e|E)
            enterprise_tools
            ;;
        *)
            warning "Неизвестная команда."
            sleep 1
            ;;
    esac
done
