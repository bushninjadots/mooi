# mooi

A fluid, keyboard-first desktop shell for Hyprland, rendered with [Pleamar](https://github.com/k4ditano/pleamar).
It runs **beside** ArchEclipse while it is being built. ArchEclipse stays your login shell; see [docs/SWITCHING.md](docs/SWITCHING.md).

Status: Phase 5 in progress. The bar is the **Ferrolume** bar: a compact strip along the top edge, built to the Ferrolume design system, with a DNA-helix workspace instrument (docs/FERROLUME.md, D20–D24). The earlier Mechanism bar is design history only (docs/MECHANISM.md; its code was removed in D33 and is archived in ~/.local/state/mooi). Phase 4 is done apart from multi-monitor. See [STATUS.md](STATUS.md); the master brief is saved in [docs/BRIEF.md](docs/BRIEF.md) with a coverage audit at the end of it.

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
bin/mooi theme-watch       # follow the wallpaper: recolour whenever it changes (start runs it)
bin/mooi takeover           # mooi as the shell (needs the guard in docs/SWITCHING.md)
bin/mooi run [--safe]       # foreground, for development
bin/mooi refresh            # copy the repo into the running snapshot and restart the scene
bin/mooi settings | edit    # the settings window · the bar's edit mode
bin/mooi check              # compile, parse the logic, unit tests
```

Needs `pleamar` 0.4.6 (language 0.4), `hyprctl`, `jq`, `lua5.4` (tests), and `wpctl`/`brightnessctl` (tests).

## What is there

- **The bar** (Ferrolume): three lists of modules — left, centre, right — each module a reading or a control (workspaces, the focused window, media with its visualizer, resources, throughput, keyboard, weather, tray, notifications, mic, volume, brightness, battery, network, Bluetooth, clock, keep-awake, recorder, screenshot, clipboard, session, window actions, Atlas, search). Modules join into one frame with `+`, can be hidden or re-outlined, and the bar is either separate islands or one full panel. The workspaces are a **DNA double helix** by default (prism and cells selectable). The thin tab at the left edge opens mooi's settings window; the bar has an edit mode (drag modules, drop on one to group, onto the shelf to hide, Escape to undo). Details: [docs/FERROLUME.md](docs/FERROLUME.md). The weather module asks ipinfo.io where you are (from your IP address) and open-meteo for the forecast, every ten minutes while it is on the bar, so it starts on the shelf (edit mode places it); off the bar, no request is made.
- **Window island**: Float, Fullscreen, Pin, Move to workspace, Close (asks twice). Every action is read back from Hyprland before it is reported as done.
- **System island**: volume (drag, scroll, ←→, `m` mute), brightness, battery and network, always showing what the system reports.
- **Workspace Atlas**: `bin/mooi atlas` or the bar's Atlas door opens a wall of every window, two per row, with a real preview picture from the compositor (`thumbnails`), its app, title and workspace. ←→↑↓ choose, ↵ focuses that window, Esc closes. **`m`** turns the strip below the board into a workspace picker: ←→ (or a click) chooses one and ↵ moves the window there, verified by reading it back — the Atlas stays open, because a move is not a choice — and Esc leaves the strip. **`p`** turns the preview pictures off: no picture is drawn and the compositor is asked to give its frames back, and the choice is remembered as a setting. The bounded map of configured workspaces (including empty slots) is kept as state, and a workspace is focused only after Pleamar's real workspace service confirms it.
- **Theme**: the islands use fourteen semantic colour tokens, not colours in components; the bar uses Ferrolume's nineteen roles, built from the same palette (`lib/ferro`). `theme.source` is `wallpaper` by default — the bar takes the dark scheme Matugen makes from your wallpaper, and **follows it on its own**: `bin/mooi start` runs `theme-watch`, which recolours whenever the wallpaper changes (`fixed` is the brief's own palette instead, and what shows before a palette exists). Single tokens can be overridden under `theme.overrides`, and how the palette is extracted (`theme.scheme`, `theme.color_index`, `theme.contrast`, `theme.signal`) is set from the settings window. A wallpaper whose text would be unreadable has its text colours lifted (lightness only, hue kept) rather than refused (D24); a theme that still cannot be read — an override that makes text unreadable — is refused whole and the last good one stays, with an error dot on the bar.
- One island at a time; opening another hands the slot over. Esc steps back one level at a time.

## Settings

`~/.local/share/pleamar/mooi/settings.json`, created on first run, applied live:

```json
{
  "version": 1,
  "spine":   { "max_workspaces": 10 },
  "bar":     { "mode": "islands", "workspaces": "dna",   // or "full"; "prism", "cells"
               "left": ["workspaces", "window"], "center": ["media"], "right": ["clock"],
               "modules": { "weather": { "show": false } } },   // every module can be hidden
  "island":  { "confirm_close": true, "follow_on_send": false },
  "motion":  { "reduced": false },
  "atlas":   { "previews": true },
  "theme":   { "source": "wallpaper" }   // or "fixed"; add "overrides" to pin single tokens
}
```

Most settings are easier to change from the settings window (the tab at the bar's left edge, or Super+Alt+S); the full list is the schema in `shell/lib/config.luau`. A broken file never stops the shell: it falls back to the last good file and shows an error dot on the bar. (`spine.clock` from an older mooi is read as `bar.modules.clock.show`.)

## Docs

[Vision](docs/VISION.md) · [Philosophy](docs/PHILOSOPHY.md) · [Ferrolume bar](docs/FERROLUME.md) · [Brief](docs/BRIEF.md) · [Audit](docs/AUDIT.md) · [Spec](docs/SPEC.md) · [Architecture](docs/ARCHITECTURE.md) · [Mechanism](docs/MECHANISM.md) · [Switching](docs/SWITCHING.md) · [Decisions](docs/DECISIONS.md) · [Testing](docs/TESTING.md)
