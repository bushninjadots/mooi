#!/usr/bin/env bash
# Lock the session with whichever shell is up (dotfiles audit, 2026-10-21): ArchEclipse's own secure
# lock while it runs; hyprlock otherwise (mooi's takeover stops ArchEclipse, and its IPC lock then did
# nothing — the lock key and the suspend key with it).
#   lock-session.sh            lock
#   lock-session.sh --suspend  lock, then suspend once the lock has engaged
qs_conf="$HOME/.config/quickshell/archeclipse"
lock() {
    if pgrep -af -- "$qs_conf" 2>/dev/null | grep -v -F 'ipc call' | grep -q .; then
        qs -p "$qs_conf" ipc call lock activate && return 0
    fi
    pgrep -x hyprlock >/dev/null 2>&1 && return 0
    setsid -f hyprlock >/dev/null 2>&1 </dev/null
}
lock
if [ "$1" = "--suspend" ]; then
    sleep 1
    systemctl suspend
fi
