# Switching between ArchEclipse and mooi

**ArchEclipse is always the shell you log into.** Nothing in Hyprland's autostart mentions mooi, and every mooi state lives in `$XDG_RUNTIME_DIR` (tmpfs, wiped at logout). A reboot or re-login always lands in ArchEclipse.

## The keys

| Key | What it does |
| --- | --- |
| **Super+Alt+Space** | mooi not running → start it **beside** ArchEclipse. Running → toggle its window island |
| **Super+Alt+Shift+Space** | stop mooi. After a takeover, also make sure ArchEclipse is back |
| **SUPER+SHIFT+B** (unchanged) | restart ArchEclipse's bar, and now also **end any mooi takeover**: the universal way back |

## The two ways mooi runs

| | Beside (default) | Takeover |
| --- | --- | --- |
| How | Super+Alt+Space, `bin/mooi start` | `bin/mooi takeover` |
| ArchEclipse | runs as always | bar stopped (wallpaper, desktop widgets, Desk, Polkit keep running) |
| Notifications, tray | ArchEclipse | not handled yet: mooi has no notification server before Phase 6 |
| Lock key | ArchEclipse | `swaylock` (shell-ipc.sh fallback) until mooi has a lock screen |
| Other shell keys (search, record, left panel) | ArchEclipse | a notice that it is not in mooi yet |
| If mooi crashes | restarted (3 quick crashes → gives up) | restarted; when it gives up, **ArchEclipse comes back by itself** |

## How takeover stays safe

- `bin/mooi takeover` starts mooi first and stops ArchEclipse's bar (`bar.sh --kill`) **only once mooi is confirmed up**. If mooi fails to start, ArchEclipse is never touched.
- The keeper process writes its pid to `$XDG_RUNTIME_DIR/mooi/takeover`. The guards below act only while that pid is alive, so a stale marker (keeper killed) is ignored and everything behaves as before.
- When the keeper ends, however it ends (stop, crash give-up, SIGTERM), it removes its marker and starts ArchEclipse if it is not running.
- `bar.sh` (autostart, SUPER+SHIFT+B, maintenance restarts) removes the marker and tells mooi to quit before starting the bar.

## The guards in your dotfiles

Backups of the originals: `~/.local/state/mooi/dotfiles-backup-20261014/`.

| File | Change | Status |
| --- | --- | --- |
| `hypr/config/bind.lua` | the two keys above | **added** |
| `hypr/scripts/bar.sh` | starting the bar ends a takeover | **added** |
| `hypr/scripts/shell-ipc.sh` | during a live takeover: lock → swaylock, others → a notice | **added** |
| `hypr/scripts/quickshell-fullscreen-sync.sh` | during a live takeover, do not restart the bar | **not added**: the edit was refused by the permission system. Add it yourself (below) |

Until the last guard is there, `bin/mooi takeover` refuses to run and says why. Without it, the fullscreen sync restarts ArchEclipse on the next focus change and `bar.sh` then ends the takeover. That is safe, but the takeover would not last.

Add this to `~/.config/hypr/scripts/quickshell-fullscreen-sync.sh`, just above `exec 8>"$LOCK_FILE"`:

```bash
# mooi holds the desktop (`mooi takeover`, see bar.sh): leave the bar down. Only
# while the keeper whose pid the marker holds is alive; a stale marker is ignored.
MOOI_TAKEOVER="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mooi/takeover"
if [ -f "$MOOI_TAKEOVER" ] && kill -0 "$(cat "$MOOI_TAKEOVER" 2>/dev/null || echo 0)" 2>/dev/null; then
    exit 0
fi
```

## Removing mooi entirely

Delete the two `bind.lua` lines under `--- mooi`, the `MOOI_TAKEOVER` blocks in the three scripts (or restore the backups), and `~/Projects/mooi` plus `~/.local/share/pleamar/mooi`. ArchEclipse never depended on any of it.

## Pleamar version

`~/.local/bin/pleamar` is **0.4.6**, built from `~/.local/share/pleamar/src/pleamar` (git, tag v0.4.6). The previous binary is `~/.local/bin/pleamar-0.3.7`. Rollback:

```sh
cp ~/.local/bin/pleamar-0.3.7 ~/.local/bin/pleamar
```

Every existing scene (Desk, Polkit, the six Tide variants, Marea) compiled on 0.4.6 before the swap. Desk and Polkit kept running their loaded 0.3.7 and move to 0.4.6 at their next restart (normally the next login).
