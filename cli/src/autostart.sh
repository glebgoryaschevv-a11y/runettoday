#!/bin/sh

RT_ROOT="${RUNETTODAY_ROOT:-$HOME/runettoday}"
RT_SCRIPTS_DIR="$RT_ROOT/scripts"
RT_TICK="$RT_SCRIPTS_DIR/telemetry-tick.sh"
RT_LOG="/tmp/runettoday-telemetry.log"
RT_PLIST="$HOME/Library/LaunchAgents/ru.runettoday.telemetry.plist"
RT_LABEL="ru.runettoday.telemetry"
RT_INTERVAL="${RUNETTODAY_INTERVAL:-60}"

autostart_tick_script() {
    mkdir -p "$RT_SCRIPTS_DIR"
    cat > "$RT_TICK" <<EOS
#!/bin/sh
export HOME="$HOME"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:\$PATH
cd "$RT_ROOT" || exit 1
./cli/runettoday device telemetry >> $RT_LOG 2>&1
EOS
    chmod 700 "$RT_TICK"
}

autostart_install() {
    _os="$(uname -s)"
    mkdir -p "$RT_SCRIPTS_DIR"

    if [ "$_os" = "Darwin" ]; then
        autostart_tick_script
        mkdir -p "$HOME/Library/LaunchAgents"

        cat > "$RT_PLIST" <<EOP
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$RT_LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$RT_TICK</string></array>
    <key>StartInterval</key><integer>$RT_INTERVAL</integer>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>$RT_LOG</string>
    <key>StandardErrorPath</key><string>$RT_LOG</string>
</dict>
</plist>
EOP

        launchctl unload "$RT_PLIST" 2>/dev/null
        launchctl load "$RT_PLIST"

        printf '%s\n' "Автопост включён: launchd каждые ${RT_INTERVAL} сек"
        printf '%s\n' "Лог: $RT_LOG"

    elif [ -x /etc/init.d/runettoday ]; then
        /etc/init.d/runettoday enable 2>/dev/null
        /etc/init.d/runettoday start 2>/dev/null
        printf '%s\n' "Автопост включён: init.d + cron"

    else
        printf '%s\n' "Не знаю как настроить автопост на этой системе" >&2
        return 1
    fi
}

autostart_uninstall() {
    if [ "$(uname -s)" = "Darwin" ]; then
        launchctl unload "$RT_PLIST" 2>/dev/null
        rm -f "$RT_PLIST" "$RT_TICK"
        printf '%s\n' "Автопост выключен"
    elif [ -x /etc/init.d/runettoday ]; then
        /etc/init.d/runettoday stop 2>/dev/null
        /etc/init.d/runettoday disable 2>/dev/null
        printf '%s\n' "Автопост выключен"
    fi
}

autostart_status() {
    if [ "$(uname -s)" = "Darwin" ]; then
        if launchctl list 2>/dev/null | grep -q "$RT_LABEL"; then
            printf '%s\n' "Автопост: ВКЛЮЧЁН (launchd, каждые ${RT_INTERVAL} сек)"
        else
            printf '%s\n' "Автопост: ВЫКЛЮЧЕН"
        fi
        if [ -f "$RT_LOG" ]; then
            printf '\nПоследние строки лога:\n'
            tail -n 6 "$RT_LOG"
        fi
    elif [ -x /etc/init.d/runettoday ]; then
        if /etc/init.d/runettoday enabled 2>/dev/null; then
            printf '%s\n' "Автопост: ВКЛЮЧЁН (cron)"
        else
            printf '%s\n' "Автопост: ВЫКЛЮЧЕН"
        fi
    else
        printf '%s\n' "Эта система не поддерживается" >&2
        return 1
    fi
}
