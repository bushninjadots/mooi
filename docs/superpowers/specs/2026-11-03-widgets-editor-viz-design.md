# Widgets 2a: the editor and the visualiser upgrade

Date: 2026-11-03 · Status: approved in conversation (user waived spec review: "just do it")

## Intent

This is the first of three sub-projects that follow D137:

1. **2a (this spec):** the editor and the visualiser.
2. **2b:** wallpaper awareness.
3. **2c:** Clocks and Notes.

The user wants:

- **Better editor controls:** all four, namely resize from all sides, keyboard and nudge, a better
  options panel, and align and layer tools.
- **A visualiser that can carry many more, finer bars.** Today a wide visualiser has a few fat
  bars.
- **Visual upgrades for every mode family:** bars, flowing, line and particles, and Ring.

**Decisions:**

| Topic | Decision |
|---|---|
| More bars | **A**: the bar's one cava goes to 64 bands with a `v2` feed line; widgets resample to their own count (16–128). |
| Editor | Selection list with marquee, 8 handles, keyboard shortcuts, undo, align/distribute/match, z-order, lock. |
| Panel | 320 px, draggable, live thumbnails, sliders, readouts. |
| Colour | Palette colours for now; 2b adds wallpaper-local colour. |

## 1 · The editor

**Selection** (`fact` list `wg_selmask`, a bit mask over 8 slots).

- Click selects one widget; Shift-click toggles one.
- Dragging on empty desktop draws a marquee that selects everything it touches.
- Esc first clears the selection; a second Esc leaves edit mode.
- Clicking empty desktop clears the selection; Done leaves.

**Handles.**

- Eight engraved handles: four corners and four edge midpoints. Dragging the left or top edge moves
  the origin too. The Record keeps its aspect from corners only.
- The widget redraws live at its new size while dragged, with a readout `w × h · x, y` beside it.
- Snapping and guides work as now; Alt held turns snapping off.

**Keyboard** (while editing):

- **Move:** arrows nudge 8 px, Shift+arrows 1 px.
- **Edit:** Delete removes, Ctrl+D duplicates, Ctrl+Z / Ctrl+Shift+Z undo and redo (30 steps),
  Ctrl+A selects all.
- **Arrange:** L locks, `]` / `[` bring forward or send back.

**Toolbar** (under the top bar):

- With two or more selected: align left / centre / right / top / middle / bottom, distribute
  horizontally / vertically, match width / height.
- With one or more selected: bring to front / send to back, and lock.

**Locked widgets** show a padlock and ignore drag, resize, nudge and align. The toolbar reports how
many were skipped.

## 2 · The options panel

**Shape and place.**

- 320 px wide, with a header strip you can drag. The position chosen holds for the session.
- It defaults to beside the selection, or above or below a full-width widget.
- **⌄** collapses it to the header.
- With several widgets selected it shows only their common settings: opacity, at rest and plate.

**Sections:**

1. **Layout or mode as live thumbnails.**
   - Now Playing: three mini cards.
   - Visualiser: a 4 × 3 grid of mini visualisers driven by the music.
   - Thumbnails exist only while the panel is open.
2. **Sliders** (track, thumb, readout, wheel).
   - All widgets: Opacity 30–100 % and Scale (resizes around the centre).
   - Visualiser: Bars 16–128, Glow 0–100 %, Gap 0–60 %, Smoothing 0–100 %.
   - Now Playing: Text 80–140 %.
3. **At rest:** Hide / Rest / Marker.
4. **Switches.**
   - Now Playing: lyric line, progress, plate, wheel volume.
   - Visualiser: plate, Peaks, Reflection.
5. **Readout and actions.** x, y, w, h as numbers you can scroll; Lock, Duplicate, Remove.

**Saving.** Slider drags are live through scene facts and save once on release.

**Settings → Widgets** rows also get the Bars and Opacity sliders.

## 3 · The visualiser

**Feed v2.**

- The bar's cava runs `bars = 64`. The bar writes the v1 line as now, plus a `v2` line in
  `viz-levels-v2.txt`: `v2 <64 bands> <bass> <high> <beat> <phase> <playing> <missing> <seq>`.
- `lib/vizfeed` gets:
  - `encode_v2` / `decode_v2`
  - `resample(bands, n)`: downsampling averages groups, so values are preserved and endpoints kept;
    upsampling interpolates with smoothstep.
- The widgets read v2 when it is fresh, else v1.

**Per-slot band facts.**

- The logic resamples each visualiser to its own `bars` count and writes facts
  `vz<slot>_<i>`, i < its count, for the at most 3 visualiser slots that get bands (`vzA`, `vzB`,
  `vzC`; a 4th or later visualiser shares slot C's bands).
- The scene draws `repeat i in 0..128` with `show: i < bars`. This keeps per-frame logic writes to
  N values per visualiser.
- Peak-hold values (`pk…`) live in the logic: a peak holds 400 ms, then falls at 1.2 per second.
- `smooth` sets the fall rate of the bands themselves.

**Bar modes.**

- Spectrum, Mirror and Skyline get bar width from `bars` and `gap`, rounded caps, a vertical
  gradient from t1 to t2 brightening near the top, optional peak dots and an optional reflection
  (Skyline always reflects).
- LED becomes a dot matrix whose columns follow `bars`.

**Flowing modes** (straight steps only, D128).

- **Aurora:** 4 layers with parallax drift and a rim highlight on the top layer.
- **Horizon:** a stepped skyline over the full band count, 4 parallax layers, rim highlight.
- **Liquid:** an inner glow shape plus an outer skin, from 32 resampled bands.

**Line and particle modes.**

- **Scope:** a thinner trace plus 3 afterimages, drawn from the last 3 band frames the logic keeps.
- **Dust:** 2 depth layers, each speck with a short trail along its scatter direction.
- **Ripple:** varying thickness and a faint refraction band (a wider, low-alpha ring) inside each
  ring.
- **Orbit:** particles leave fading arc segments.

**Ring.**

- Spokes follow `bars`, up to 128.
- An inner circular waveform (a closed straight-step path of 48 points) and an inner glow.
- Rotates at 6° a second while playing.

**Budget.** Under 8 % GPU for a Sleeve plus a full-width visualiser, at 64 and at 128 bars. Any mode
over budget loses layers or trails until it fits; the numbers are reported.

## 4 · Data, failures, testing

**`widgets.json` version 2.**

- Per widget: `z` (list order), `locked` (bool) and `opacity` (0.3–1, default 1).
- Visualiser options: `bars` (16–128, default 64), `gap` (0–0.6, default 0.3), `smooth` (0–1,
  default 0.5), `peaks` (default true) and `reflection` (default false).
- Now Playing options: `text` (0.8–1.4, default 1).
- Version 1 files load with defaults and are written as version 2 on their next change.

**Failures.**

| Failure | What happens |
|---|---|
| No v2 feed | Resample from v1's 32 bands. |
| External file change | Clears the undo history. |
| A locked widget in an operation | Skipped and counted. |
| Results of any operation | Clamped to the screen. |

**Tests.**

- `lib/widgets`:
  - align / distribute / match
  - z-order, lock, nudge
  - resizing from all 8 handles, with the Record's aspect
  - the marquee hit test
  - undo / redo, and history cleared on an external change
  - v1 → v2 migration and clamps
- `lib/vizfeed`: v2 round-trip, resample up and down, v1 unchanged.

**Live checks** use the scene's own events and screenshots, not the user's pointer:

- the editor operations and the sliders
- every mode at 16, 64 and 128 bars
- GPU for every mode at 64 and 128 bars

At the end, the user gets a short list to try by hand.
