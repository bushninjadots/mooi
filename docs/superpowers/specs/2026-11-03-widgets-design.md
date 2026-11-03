# Desktop widgets: Now Playing and Visualiser, all in Pleamar

Date: 2026-11-03 · Status: design approved in conversation, awaiting spec review

## Intent

mooi's desktop widgets today are a separate Quickshell instance (`~/.config/desktop-widgets`, vendored
from Ryoku: metal clock, lyrics band, notes). The user wants one widget system that is **all in
Pleamar 0.7.11 (language 0.9), more mooi, with fresh widgets**, and wants to retire the Quickshell one.
This first step covers **music and the visualiser only**. Clock, notes and other kinds come later on
the same system.

Success means:

- Now Playing in three layouts and a Visualiser in twelve modes, sitting on the desktop.
- Placed by dragging on the desktop or from Settings, with one saved state.
- Calm until touched.
- Cheap when idle.
- Quickshell `desktop-widgets` no longer runs.

## Decisions made with the user

| Topic | Decision |
|---|---|
| Scope | Music + visualiser only. One system, everything in Pleamar. |
| Now Playing | All three layouts: **Sleeve**, **Lyric stage**, **Record**. |
| Visualiser | A separate widget. The existing six modes (Spectrum, Mirror, Ring, Aurora, LED, Orbit) plus six new ones (**Phosphor scope, Horizon, Dust, Ripple, Skyline, Liquid**): 12 in all. |
| Editing | Both: edit mode on the desktop, and a Widgets page in Settings. One saved state. |
| Idle | Per widget: `hide` / `rest` / `marker`. Defaults: Now Playing rests, Visualiser hides. |
| Pointer (outside edit) | Calm until touched: hover reveals controls; clicking the cover opens mooi's player; empty parts click through. |
| Depth | Widgets stack between the wallpaper and the Desk's `fore` (cut-out) layer. No cut-out maker is rebuilt (Lumen was removed in D118); an existing cut-out still covers the widgets. |
| Sizing | Free resize, 8 px grid snap, per-layout min/max; content scales. |
| Architecture | **A**: one program, one full-screen click-through surface. |
| Monitors | Single monitor (eDP-1, 1920×1080). No per-monitor placement. |
| Visualisers on borders | Never (standing rule): visualisers live inside music components and this widget only. |

Mockups from the brainstorm: `.superpowers/brainstorm/260255-1793702158/content/`
(`now-playing-layouts-v2.html`, `visualiser-modes.html`).

## 1 · Architecture

**Why one surface.** In Pleamar a surface's `margin:` is a plain number that is fixed while the scene
runs, so one surface per widget could not follow a drag. An input region lets clicks through the
empty parts of a surface, so one full-screen surface costs no clicks.

**The program.**

- **Files:** `shell/mooi-widgets.plm` + `shell/mooi-widgets.luau`.
- **Lifecycle:** spawned and kept by the bar while `widgets.on` is set, like `mooi-desk` and
  `mooi-frame` (spawn in `mooi.luau`, line in `bin/mooi check`, entry in the `bin/mooi` program
  list). `widgets.on` goes into the `lib/config` schema (default `true`) and `lib/setters`.
- **Surface:** `size: full, full`, `level: bottom`, `keyboard: on_demand while editing` (none
  otherwise), `rate: 60, 4 while calm`. It must stack under the Desk's `fore`: the desk creates
  `fore` after the widgets. The bar starts `mooi-widgets` before `mooi-desk`, and restarts the desk
  after any restart of the widgets.
- **Calm** means nothing playing, nothing hovered, not editing and no animation running.

**Units, each with one job.**

| Unit | Job | Depends on |
|---|---|---|
| `shell/lib/widgets.luau` (pure, tested) | The model. Read and validate `widgets.json`; layout table (min/default/max); 8 px snap, edge and widget snapping, keeping widgets on screen; layout switching; idle state; defaults. | nothing |
| `shell/ui/widgets.plm` | The look. Components `Sleeve`, `LyricStage`, `Record`, `Visualiser` (picks one of 12 modes), the edit chrome (outline, handles, options panel, + Add chip, guides). | `ui/viz.plm`, theme |
| `shell/ui/viz.plm` (extended) | Six new library components beside the existing six, same signature `(x, y, w, h, t1, t2, still)`, also usable by the player and the bar. New modes may also read `vbass`, `vhigh`, `vbeat`. | the scene's bands |
| `shell/mooi-widgets.luau` | The logic. Feeds now-playing data, bands and lyric lines to the scene; runs edit mode; saves. | `lib/widgets`, `lib/vizfeed`, `lib/player`, `player/lyrics`, `lib/cover`, MPRIS media service |
| Settings → **Widgets** page (`mooi-settings`) | List of widgets with layout/mode, idle and options; **Edit on desktop** button; add/remove. Writes `widgets.json`. | `lib/widgets` |
| Control Nexus | An **EDIT WIDGETS** tile. | `pleamar --say mooi-widgets` |
| `bin/mooi widgets edit` | Enters edit mode (bindable to a key). | `pleamar --say` |

**Retiring Quickshell `desktop-widgets`.**

- **Now:** remove its start from `hypr/config/exec.lua` and its `desktop-widgets` rules from
  `layerrule.lua` / `windowrule.lua`, both live and in `setup/`.
- **Kept for now:** its files stay in `~/.config/desktop-widgets` and `setup/home/.config/` for a
  few days.
- **Later:** a later step deletes them and drops them from `setup/capture.sh`.

**Out of scope:** a cut-out maker, other widget kinds, per-monitor placement, widgets above windows.

## 2 · Saved state and sizing

**`widgets.json`** lives in mooi's data folder beside `board.json`. `mooi-widgets` is added to
`settings_link` in `bin/mooi`, so the program, the settings window and the bar share it.

```json
{ "version": 1,
  "widgets": [
    { "id": "np-1", "kind": "nowplaying", "layout": "sleeve",
      "x": 64, "y": 720, "w": 432, "h": 152,
      "idle": "rest", "options": { "lyrics": true, "progress": true, "plate": false, "scroll_volume": true } },
    { "id": "viz-1", "kind": "visualiser", "mode": "horizon",
      "x": 0, "y": 880, "w": 1920, "h": 200,
      "idle": "hide", "options": { "glow": 0.6, "mirror": false } } ] }
```

- **Fields.** `kind`: `nowplaying` | `visualiser`. `layout`: `sleeve` | `lyricstage` | `record`.
  `mode`: `spectrum` `mirror` `ring` `aurora` `led` `orbit` `scope` `horizon` `dust` `ripple`
  `skyline` `liquid`. `idle`: `hide` | `rest` | `marker`.
- **Instances.** It is a list, so you can have several of each. `id` is unique (`np-N`, `viz-N`).
- **Layout switch.** Position is kept. The size becomes the new layout's default, clamped to its
  min/max and kept on screen.
- **Validation (`lib/widgets`).**
  - Unknown kinds, layouts, modes or options are dropped, with a log line.
  - Numbers are clamped to their layout's min/max.
  - A widget off screen is pulled back on screen, respecting the bar's reserve.
  - Duplicate ids are renumbered.
- **Missing file:** use the defaults (one Sleeve at the bottom left, no visualiser).
- **Unreadable file:** use the defaults and rename the file to `widgets.json.bad`. Never silently
  overwrite it.
- **Saving.** Atomic write (temp file + rename). A drag or resize is saved once, on release.

**Sizes (px at 1080p).**

| Layout | min | default | max | Aspect |
|---|---|---|---|---|
| Sleeve | 288×104 | 432×152 | 864×304 | free |
| Lyric stage | 480×160 | 960×240 | 1920×480 | free |
| Record | 200×248 | 280×352 | 480×600 | fixed (resize from corners only) |
| Visualiser | 160×64 | 640×160 | screen | free |

**Scaling.** Each widget has one scale `u = h / default_h` (`w / default_w` for the visualiser).
Type, cover, record, padding and line widths all multiply by `u`. Extra width beyond the scaled
default goes to text (Sleeve's title and lyric line, Lyric stage's line length), never to stretching
the cover.

## 3 · Edit mode and pointer

**Entering.** Control Nexus tile, Settings → Widgets **Edit on desktop**, or `mooi widgets edit`.

**While editing.**

- **Display.** A faint 8 px grid over the desktop and a thin outline on every widget. Windows are
  not moved or hidden.
- **Hidden widgets.** A widget whose idle rule currently hides it shows as a dashed ghost.
- **Drag and resize.** Drag the body to move; drag an edge or corner to resize (Record: corners
  only).
- **Snapping.** Moves snap to the 8 px grid, to the screen edges (inside the bar's reserve) and to
  other widgets' edges and centres. A guide line shows each snap.
- **Options panel.** Clicking a widget opens its panel beside it, on the side with room: layout or
  mode, idle rule, options, **Duplicate**, **Remove**.
- **Adding.** A **+ Add** chip at the top centre adds a Now Playing or a Visualiser at its default
  size, placed in free space.
- **Leaving.** Esc, **Done**, or a click on empty desktop saves and leaves.

**Outside edit mode: calm until touched.**

- **Hover.**
  - The widget lifts slightly and its edge brightens.
  - Small controls fade in: previous / play-pause / next.
  - Sleeve and Record also get a seekable progress trace.
  - Everything fades out about 1.2 s after the pointer leaves.
- **Click.** Clicking the cover or record opens `mooi-player`. Only the cover, controls and progress
  catch clicks; everything else on a widget passes through.
- **Scroll.** Scrolling over a Now Playing widget changes the volume (`scroll_volume`, on by
  default).
- **The visualiser never takes input** outside edit mode.

**Idle (nothing playing).**

- `rest`: dims to about 35 % and shows the last track faded; the record stops with its tonearm
  lifted.
- `hide`: fades out.
- `marker`: shrinks to a small engraved glyph in place; clicking it opens the player.
- Reduced motion and motion saving: fades become cuts; spin, drift and Dust stop (resting shapes).

## 4 · Look and data flow

**Look: Ferrolume.**

- **Palette and corners.** The same `fr_*` palette facts as the other programs, painted from
  `palette.json` and re-lit on apply, and the corner facts `cn_kind` / `cn_scale`.
- **Type.** Exo 2 for titles, Share Tech Mono for captions and times.
- **Backing.** No card boxes by default: a soft shadow for legibility on any wallpaper. The optional
  `plate` option adds a tinted Ferrolume backing.

**The layouts.**

- **Sleeve.** Cover with a lit rim; to its right the title, artist (mono), current lyric line
  (phosphor; hidden when lyrics are off or missing) and a fine progress trace.
- **Lyric stage.** Current line large and centred, previous and next faded above and below, a small
  cover and title as a caption at the corner. Lines cross-fade at their LRC timestamps. Without
  synced lyrics it shows the title large.
- **Record.** A vinyl disc with the cover as its label, turning at 33⅓ rpm while playing; the
  tonearm follows progress via `lib/player.arm`; title and artist below.
- **Visualiser.** Any of the 12 modes in two palette tones (`t1` → `t2`), with a `glow` option and
  `mirror` where it applies. No box; clipped to its own rectangle.

**The new modes.**

| Mode | What it draws |
|---|---|
| Phosphor scope | An oscilloscope trace with a fading afterimage (a few trailing copies at falling alpha). |
| Horizon | Four layered filled hills; the bass lifts the far layers, the treble ripples the near ones. |
| Dust | About 120 specks drifting; they scatter outward on the beat and settle back. |
| Ripple | Rings spreading from the centre on each beat, sized by beat strength (a small ring pool). |
| Skyline | Spectrum bars on a waterline with a faded reflection below. |
| Liquid | A soft round shape whose edge bulges with the bands (bass at the bottom, treble at the top). |

**Data flow.**

- **Audio.** The bar's `viz-levels.txt` is read through `lib/vizfeed` into the scene facts
  (`vb0…vb15`, `vbass`, `vhigh`, `vbeat`). No second cava runs.
- **Music.** The MPRIS media service gives title, artist, album, state, position and cover for any
  player.
  - **Lyrics:** `player/lyrics`, in order: the `.lrc` beside the file, then the cache, then LRCLIB.
    The current line comes from `lib/player.lyric_at`.
  - **Covers:** through `lib/cover`, as paths (D135).
- **State.** `widgets.json` → `lib/widgets` → scene facts. Edit events from the scene are
  validated by `lib/widgets`, applied, and saved on release.
- **Live updates.** The Settings page writes the same file; the program watches it and reloads its
  model live.

## 5 · Failures, cost, testing

**Failures.**

| Failure | What happens |
|---|---|
| No audio feed, or it goes stale | The visualiser draws its resting shape (`still`). |
| No player | The idle rules apply. |
| No lyrics, or the fetch fails | Sleeve hides the line; Lyric stage shows the title. |
| No cover | The Ferrolume placeholder glyph. |
| Bad `widgets.json` | Defaults, and the file is kept as `.bad`. |
| The program crashes | The bar restarts it like the frame. After 3 crashes within 60 s it stops and logs why. |

**Cost.**

- One small `body` per widget, so nothing spans the screen.
- Animated outlines use straight steps, not `curve`.
- Dust is a single shape list.
- `rate: 60, 4 while calm`.
- **Budget**, measured with DRM fdinfo `drm-engine-gfx` per pid (not `gpu_busy_percent`):
  - idle: under 1 %
  - Sleeve plus a full-width visualiser, playing: under 8 %
  - any mode over budget is simplified before shipping

**Testing.**

- **Unit tests** (`tests/`) for `lib/widgets`:
  - validation and clamping
  - snapping (grid, edges, other widgets)
  - keeping widgets on screen
  - layout switching
  - idle state
  - defaults and `.bad` fallback
  - renumbering duplicate ids
- **`bin/mooi check`:** the new scene and the extended `ui/viz.plm` compile; all unit tests pass.
- **Live checks.**
  - Each layout and each of the 12 modes on real music, screenshotted and shown to the user.
  - Edit mode driven with `ydotool`: drag, resize, snap, options, add, remove, save, restart, state
    kept.
  - The Desk cut-out still covers the widgets.
  - A GPU measurement for every mode and for idle.
- **Retirement.** After a fresh login, Quickshell `desktop-widgets` is not running and nothing
  refers to it.
- **Housekeeping.** Decisions logged in `docs/DECISIONS.md` (next: D137), `setup/capture.sh` run
  before commit.
