# mooi

A fluid, keyboard-first desktop shell for Hyprland, rendered with [Pleamar](https://github.com/k4ditano/pleamar).
It is the whole desktop: the login starts it, and nothing runs beside it; see [docs/SWITCHING.md](docs/SWITCHING.md).

Status: the shell is built and in use, and the last full audit (docs/AUDIT-2026-11-01.md) is the current picture: 285 unit tests and nine scenes compile under one gate, `bin/mooi check`. The bar is the **Ferrolume** bar — a compact strip along the top edge with a DNA-helix workspace instrument (docs/FERROLUME.md, D20–D24) — and around it: the island kit, Control Nexus, the side notch, the music player, the wallpaper studio (Lumen), the stash, the Kanban board, BMO, and mooi's own Overview with Hyprdrive's overview ported into it (docs/OVERVIEW-PORT.md: the Mission shape, spring edges, canvas edges). Multi-monitor is the part of Phase 4 still open; the command membrane of Phase 5 is gone, replaced by the Overview's search (D33). The earlier Mechanism bar is design history only (docs/MECHANISM.md; its code was removed in D33 and is archived in ~/.local/state/mooi). See [STATUS.md](STATUS.md); the master brief is saved in [docs/BRIEF.md](docs/BRIEF.md) with a coverage audit at the end of it.

## Keys

| | |
| --- | --- |
| Super+Alt+Space | the command membrane (starts mooi first if it is not running) |
| Super+Alt+Shift+Space | stop mooi |
| Super+Shift+B | start mooi, or restart it |

## Commands

```sh
bin/mooi session | toggle | stop | status   # (start = session)
bin/mooi open | system | overview # window island · system island · the Overview
bin/mooi theme-sync        # recolour from the wallpaper with Matugen (mooi's own config)
bin/mooi theme-watch       # follow the wallpaper: recolour whenever it changes (session runs it)
bin/mooi run [--safe]       # foreground, for development
bin/mooi refresh            # copy the repo into the running snapshot and restart the scene
bin/mooi settings | edit    # the settings window · the bar's edit mode
bin/mooi check              # compile, parse the logic, unit tests
```

Needs `pleamar` 0.7.11 (language 0.9), `hyprctl`, `jq`, `lua5.4` (tests), and `wpctl`/`brightnessctl` (tests).

Optional, with a fallback when absent: `cava` for the bar's and player's visualizers (`pacman -S cava`; without it the bar says CAVA MISSING), `rembg` for the wallpaper studio's AI cutout (`pipx install "rembg[cli]"`; the studio offers the install line), and the store/player tools the bar's modules call (`playerctl`/`mpc`, `mpv`, `ffmpeg`, `yt-dlp`, `magick`, `wf-recorder`/`grim`/`slurp`, `checkupdates`, `paru`/`yay`, `flatpak`). `bin/mooi check` names what this machine lacks.

## What is there

- **The bar** (Ferrolume): three lists of modules — left, centre, right — each module a reading or a control (workspaces, the focused window, media with its visualizer, resources, throughput, keyboard, weather, tray, notifications, mic, volume, brightness, battery, network, Bluetooth, clock, keep-awake, recorder, screenshot, clipboard, session, window actions, Overview, search, quick notes, wallpaper studio). Modules join into one frame with `+`, can be hidden or re-outlined, and the bar is either separate islands or one full panel. The workspaces are a **DNA double helix** by default (prism and cells selectable). The thin tab at the left edge opens mooi's settings window; the bar has an edit mode (drag modules, drop on one to group, onto the shelf to hide, Escape to undo). Details: [docs/FERROLUME.md](docs/FERROLUME.md). The weather module asks ipinfo.io where you are (from your IP address) and open-meteo for the forecast, every ten minutes while it is on the bar, so it starts on the shelf (edit mode places it); off the bar, no request is made.
- **The stash**: a 9 px rail at the middle of the left edge opens on hover into a small box for whatever you drop on it — links, pictures, songs, videos, any file, or plain text. Files are copied into mooi's own stash folder (so moving the original does not empty it), pictures show themselves, videos get one frame of themselves, songs get their own cover art (or a level meter when they carry none), a video or a song says how long it runs, and a light runs round the border while the box is out. A row's tray puts it in its next folder and back at the root after the last, the chip row at the foot is the folders (a name and Enter makes one; a right press on a chip takes it away and sends its items home), and what is dropped goes into the folder the box is showing. A press opens an item, a drag carries it back out (and dropped back on the box, it moves rather than copies again), the × or a right press removes it, and the wheel pages. Details: [docs/DECISIONS.md](docs/DECISIONS.md) D54.
- **Lumen, the wallpaper studio**: `bin/mooi wallpaper` opens a full-screen editor over the desk — the picture is the canvas, and a grade dock edits exposure, contrast, fade, colour, crop, vignette and grain with nine vibes to start from, a live preview drawn from a screen-shaped base, and the bar's palette read from the picture before it is applied. **The source wall reads a folder of your own** and opens on `~/Pictures`: type the folder in the field, or press `BROWSE…` — a picker with a **typed path** (`~`, a name, or `/mnt/disk/pics`), `HOME` / `PICTURES` / `ROOT /`, parent and `USE THIS FOLDER`, that walks subfolders A→Z ten a page and follows links (`~/Pictures → /mnt/…` reads as the folder behind it) — or press `LIVE WALLPAPER'S FOLDER` for the pictures beside the wallpaper on the desk now; the choice is remembered in `wallpapers.json`; tiles carry a thumbnail made for the page, the filter searches by name, and `USE THE CURRENT WALLPAPER` loads the one on the desk. The **BACKDROP** tab frames the picture in a matte, or **replaces its own background**: `REPLACE BG` finds the background the picture's edge is joined to (a white field behind a creature goes, the creature's white eyes stay) and fills it with black, the blurred picture, a colour read from the picture, one of **nine palette swatches** (the shell's own ink, hull, well, phos, trace, ember and flare, plus black and white), or **any colour typed as `#RRGGBB`**. `UNDO` / `REDO` (`Ctrl+Z` / `Ctrl+Y`) step through the recipe, and what leaves the studio keeps its quality: the base is a lossless PNG, previews keep full colour resolution, and the still handed to the picker is a **PNG**. The bar carries a framed-picture module that opens it (on the shelf until you place it in edit mode, for a bar laid out before this), and `Super + Alt + P` opens it from anywhere. `APPLY TO DESKTOP` renders the screen's size and hands the still to the wallpaper picker; the source picture is never touched. Details: [docs/DECISIONS.md](docs/DECISIONS.md) D57.
- **Window island**: Float, Fullscreen, Pin, Move to workspace, Close (asks twice). Every action is read back from Hyprland before it is reported as done.
- **System island**: volume (drag, scroll, ←→, `m` mute), brightness, battery and network, always showing what the system reports.
- **The music player** (the bar's music icon, `mooi player`, Super+Alt+M): a signal-board mini card first, then the panel and full screen; three views (DJ deck, cover stage, instrument rack), six visualisers shared with the bar, a library with covers (albums, artists, genres, songs), synced lyrics with per-song offsets, an EasyEffects equaliser, and the song's music video in the view. docs/PLAYER.md.
- **The Overview** (Super+Tab, `bin/mooi overview` or the bar's Overview button): Hyprdrive's mission control by default — the wallpaper blurred behind, a strip of the workspaces you are not on, and one large card holding the active workspace's windows — with a grid, a strip under the bar, and a canvas you pan, zoom and arrange still available as shapes (Settings → Overview → Shape). Drag windows between workspaces, search, name and group workspaces, and save environments. Pictures can be turned off (`atlas.previews`) and privacy hides password managers and private windows. (The Workspace Atlas it replaced was removed in D90.)
- **Day and night**: Settings → Colour → Mode (dark, light, or auto by the hour), `bin/mooi mode [light|dark|auto]` or Super+Alt+T. The bar, every mooi window and the apps mooi colours (kitty, GTK 3/4 via adw-gtk3, Qt via qt6ct, KDE apps via kdeglobals, Papirus icons, and your own Matugen templates) all turn together.
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

## A new machine

`setup/` holds the rest of this desktop (Hyprland's config, mooi's settings and state, fonts, the
package lists, the pleamar commit). On a fresh EndeavourOS/Arch install: clone this repo to
`~/Projects/mooi` and run `setup/install.sh`. Run `setup/capture.sh` before committing to keep it
current. See [setup/README.md](setup/README.md).
