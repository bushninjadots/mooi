# mooi

A fluid, keyboard-first desktop shell for Hyprland, rendered with [Pleamar](https://github.com/k4ditano/pleamar).
It runs **beside** ArchEclipse while it is being built. ArchEclipse stays your login shell; see [docs/SWITCHING.md](docs/SWITCHING.md).

Status: Phase 5 in progress (theme: the brief's palette, the wallpaper's own palette through Matugen, per-token overrides). Phase 4 is done apart from multi-monitor. See [STATUS.md](STATUS.md); the master brief is saved in [docs/BRIEF.md](docs/BRIEF.md) with a coverage audit at the end of it.

## Keys

| | |
| --- | --- |
| Super+Alt+Space | start mooi, or toggle the window island if it runs |
| Super+Alt+Shift+Space | stop mooi (and bring ArchEclipse back after a takeover) |
| SUPER+SHIFT+B | restarts ArchEclipse's bar as always, and ends any mooi takeover |

## Commands

```sh
bin/mooi toggle | start | stop | status
bin/mooi open | system | atlas # window island · system island · Workspace Atlas
bin/mooi theme-sync        # recolour from the wallpaper with Matugen (mooi's own config)
bin/mooi takeover           # mooi as the shell (needs the guard in docs/SWITCHING.md)
bin/mooi run [--safe]       # foreground, for development
bin/mooi check              # compile + unit tests
```

Needs `pleamar` 0.4.6 (language 0.4), `hyprctl`, `jq`, `lua5.4` (tests), and `wpctl`/`brightnessctl` (tests).

## What is there

- **Spine**: a 48 px left rail with the focused window (its icon), workspaces (click to switch; pulses when a window is moved there), a system button (battery and volume) and the time.
- **Window island**: Float, Fullscreen, Pin, Move to workspace, Close (asks twice). Every action is read back from Hyprland before it is reported as done.
- **System island**: volume (drag, scroll, ←→, `m` mute), brightness, battery and network, always showing what the system reports.
- **Workspace Atlas**: `bin/mooi atlas` or the Spine's A button opens a wall of every window, two per row, with a real preview picture from the compositor (`thumbnails`), its app, title and workspace. ←→↑↓ choose, ↵ focuses that window, Esc closes. **`m`** turns the strip below the board into a workspace picker: ←→ (or a click) chooses one and ↵ moves the window there, verified by reading it back — the Atlas stays open, because a move is not a choice — and Esc leaves the strip. **`p`** turns the preview pictures off: no picture is drawn and the compositor is asked to give its frames back, and the choice is remembered as a setting. The bounded map of configured workspaces (including empty slots) is kept as state, and a workspace is focused only after Pleamar's real workspace service confirms it.
- **Theme**: fourteen semantic colour tokens, not colours in components. `theme.source` is `fixed` (the palette above) or `wallpaper` — then `bin/mooi theme-sync` asks Matugen for the dark scheme of your wallpaper and mooi recolours itself live; single tokens can be overridden under `theme.overrides`. A theme that cannot be read (missing tokens, or text that would be unreadable) is refused whole and the last good one stays, with a dot on the Spine.
- One island at a time; opening another hands the slot over. Esc steps back one level at a time.

## Settings

`~/.local/share/pleamar/mooi/settings.json`, created on first run, applied live:

```json
{
  "version": 1,
  "spine":   { "clock": true, "max_workspaces": 10 },
  "island":  { "confirm_close": true, "follow_on_send": false },
  "motion":  { "reduced": false },
  "atlas":   { "previews": true },
  "theme":   { "source": "fixed" }   // or "wallpaper"; add "overrides" to pin single tokens
}
```

A broken file never stops the shell. It falls back to the last good file and shows an orange dot on the Spine.

## Docs

[Brief](docs/BRIEF.md) · [Audit](docs/AUDIT.md) · [Spec](docs/SPEC.md) · [Architecture](docs/ARCHITECTURE.md) · [Switching](docs/SWITCHING.md) · [Decisions](docs/DECISIONS.md) · [Testing](docs/TESTING.md)
