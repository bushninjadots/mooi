# mooi

A fluid, keyboard-first desktop shell for Hyprland, rendered with [Pleamar](https://github.com/k4ditano/pleamar).
It runs **beside** ArchEclipse while it is being built. ArchEclipse stays your login shell; see [docs/SWITCHING.md](docs/SWITCHING.md).

Status: Phase 2 done. See [STATUS.md](STATUS.md).

## Keys

| | |
| --- | --- |
| Super+Alt+Space | start mooi, or toggle the window island if it runs |
| Super+Alt+Shift+Space | stop mooi (and bring ArchEclipse back after a takeover) |
| SUPER+SHIFT+B | restarts ArchEclipse's bar as always, and ends any mooi takeover |

## Commands

```sh
bin/mooi toggle | start | stop | status
bin/mooi open | system      # the window island · the system island
bin/mooi takeover           # mooi as the shell (needs the guard in docs/SWITCHING.md)
bin/mooi run [--safe]       # foreground, for development
bin/mooi check              # compile + unit tests
```

Needs `pleamar` 0.4.6 (language 0.4), `hyprctl`, `jq`, `lua5.4` (tests), and `wpctl`/`brightnessctl` (tests).

## What is there

- **Spine**: a 48 px left rail with the focused window (its icon), workspaces (click to switch; pulses when a window is moved there), a system button (battery and volume) and the time.
- **Window island**: Float, Fullscreen, Pin, Move to workspace, Close (asks twice). Every action is read back from Hyprland before it is reported as done.
- **System island**: volume (drag, scroll, ←→, `m` mute), brightness, battery and network, always showing what the system reports.
- One island at a time; opening another hands the slot over. Esc steps back one level at a time.

## Settings

`~/.local/share/pleamar/mooi/settings.json`, created on first run, applied live:

```json
{
  "version": 1,
  "spine":  { "clock": true, "max_workspaces": 10 },
  "island": { "confirm_close": true, "follow_on_send": false },
  "motion": { "reduced": false }
}
```

A broken file never stops the shell. It falls back to the last good file and shows an orange dot on the Spine.

## Docs

[Audit](docs/AUDIT.md) · [Spec](docs/SPEC.md) · [Architecture](docs/ARCHITECTURE.md) · [Switching](docs/SWITCHING.md) · [Decisions](docs/DECISIONS.md) · [Testing](docs/TESTING.md)
