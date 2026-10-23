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

- **The bar** (Ferrolume): three lists of modules — left, centre, right — each module a reading or a control (workspaces, the focused window, media with its visualizer, resources, throughput, keyboard, weather, tray, notifications, mic, volume, brightness, battery, network, Bluetooth, clock, keep-awake, recorder, screenshot, clipboard, session, window actions, Atlas, search, quick notes, wallpaper studio). Modules join into one frame with `+`, can be hidden or re-outlined, and the bar is either separate islands or one full panel. The workspaces are a **DNA double helix** by default (prism and cells selectable). The thin tab at the left edge opens mooi's settings window; the bar has an edit mode (drag modules, drop on one to group, onto the shelf to hide, Escape to undo). Details: [docs/FERROLUME.md](docs/FERROLUME.md). The weather module asks ipinfo.io where you are (from your IP address) and open-meteo for the forecast, every ten minutes while it is on the bar, so it starts on the shelf (edit mode places it); off the bar, no request is made.
- **The stash**: a 9 px rail at the middle of the left edge opens on hover into a small box for whatever you drop on it — links, pictures, songs, videos, any file, or plain text. Files are copied into mooi's own stash folder (so moving the original does not empty it), pictures show themselves, videos get one frame of themselves, songs get their own cover art (or a level meter when they carry none), a video or a song says how long it runs, and a light runs round the border while the box is out. A row's tray puts it in its next folder and back at the root after the last, the chip row at the foot is the folders (a name and Enter makes one; a right press on a chip takes it away and sends its items home), and what is dropped goes into the folder the box is showing. A press opens an item, a drag carries it back out (and dropped back on the box, it moves rather than copies again), the × or a right press removes it, and the wheel pages. Details: [docs/DECISIONS.md](docs/DECISIONS.md) D54.
- **Lumen, the wallpaper studio**: `bin/mooi wallpaper` opens a full-screen editor over the desk — the picture is the canvas, and a grade dock edits exposure, contrast, fade, colour, crop, vignette and grain with nine vibes to start from, a live preview drawn from a screen-shaped base, and the bar's palette read from the picture before it is applied. **The source wall reads a folder of your own** and opens on `~/Pictures`: type the folder in the field, or press `BROWSE…` — a picker with a **typed path** (`~`, a name, or `/mnt/disk/pics`), `HOME` / `PICTURES` / `ROOT /`, parent and `USE THIS FOLDER`, that walks subfolders A→Z ten a page and follows links (`~/Pictures → /mnt/…` reads as the folder behind it) — or press `LIVE WALLPAPER'S FOLDER` for the pictures beside the wallpaper on the desk now; the choice is remembered in `wallpapers.json`; tiles carry a thumbnail made for the page, the filter searches by name, and `USE THE CURRENT WALLPAPER` loads the one on the desk. The **BACKDROP** tab frames the picture in a matte, or **replaces its own background**: `REPLACE BG` finds the background the picture's edge is joined to (a white field behind a creature goes, the creature's white eyes stay) and fills it with black, the blurred picture, a colour read from the picture, one of **nine palette swatches** (the shell's own ink, hull, well, phos, trace, ember and flare, plus black and white), or **any colour typed as `#RRGGBB`**. `UNDO` / `REDO` (`Ctrl+Z` / `Ctrl+Y`) step through the recipe, and what leaves the studio keeps its quality: the base is a lossless PNG, previews keep full colour resolution, and the still handed to the picker is a **PNG**. The bar carries a framed-picture module that opens it (on the shelf until you place it in edit mode, for a bar laid out before this), and `Super + Alt + P` opens it from anywhere. `APPLY TO DESKTOP` renders the screen's size and hands the still to the wallpaper picker; the source picture is never touched. Details: [docs/DECISIONS.md](docs/DECISIONS.md) D57.
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
