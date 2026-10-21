# Switching between ArchEclipse and mooi

## mooi as the whole desktop (D48)

> **ArchEclipse is uninstalled on this machine (2026-10-21, D48).** mooi is the desktop whatever the
> setting says, and the way back below needs it restored first: `tar xzf
> ~/.local/state/mooi/archive-2026-10-21-archeclipse.tar.gz -C ~`, then the `exec.lua` / `bind.lua`
> backups from `~/.local/state/mooi/dotfiles-backup-20261021-uninstall/` (or `git checkout` them in the
> home repo).

**Settings → Advanced → "mooi is the whole desktop"** (`session.standalone`) makes mooi the shell you log
into. ArchEclipse stays installed and is never started:

- at login `~/.config/hypr/config/custom/mooi.lua` runs `bin/mooi session`; ArchEclipse's own start
  hook still calls `bar.sh`, which stands down while the setting is on (`bar.sh --force` starts
  ArchEclipse anyway), and its fullscreen watcher never brings the bar back;
- `bin/mooi session` holds the desktop like a takeover, serves notifications, and never hands back to
  ArchEclipse; if mooi crashes three times in a row the keeper gives up **and says so in a critical
  notification** (Super+Shift+B starts it again);
- the keys that only reached ArchEclipse are mooi's: **Super** and **Super+A** search · **Super+R** the
  system panel · **Super+L** notices · **Super+Shift+V** clipboard · **Super+Escape** the power menu
  (wlogout) · **Super+Shift+R** / **Super+Ctrl+Shift+R** record the screen / an area · **Super+Shift+B**
  (re)start mooi. Toggle bar (Super+Alt), media panel (Super+M), emoji (Super+.) and notes
  (Super+Shift+N) have nothing in mooi yet: they are let go rather than calling a shell that is not there;
- the lock and suspend keys and hypridle use `scripts/lock-session.sh` (ArchEclipse's lock if it runs,
  hyprlock otherwise), and the clipboard history mooi shows is fed by `cliphist` from login.

**Back to ArchEclipse:** switch the setting off — the next login is ArchEclipse's — or now:
`bin/mooi stop` then `~/.config/hypr/scripts/bar.sh --force`.

## Beside ArchEclipse (the setting off)

**ArchEclipse is the shell you log into.** Every mooi state lives in `$XDG_RUNTIME_DIR` (tmpfs, wiped at logout).

## The keys

| Key | What it does |
| --- | --- |
| **Super+Alt+Space** | toggle the command membrane; if mooi is not running, start it **beside** ArchEclipse first |
| **Super+Alt+W** | toggle the window island (mooi must be running) |
| **`bin/mooi atlas`** / the bar's Atlas prism | open or close the Workspace Atlas |
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
