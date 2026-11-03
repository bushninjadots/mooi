# Widgets 2b: wallpaper awareness and depth

Date: 2026-11-03 · Status: approved in conversation ("yes yes"); the user waived written-spec review
(as in 2a)

## Intent

The widgets react to the wallpaper behind them, in five ways the user picked:

- **Legible on any spot:** text tone and haze adapt to the picture under each widget.
- **Local colour:** the accent comes from the colours under the widget.
- **Avoid the subject:** suggest only; nothing moves by itself.
- **Mood:** glow, pace and softness follow the picture's character.
- **Depth:** a widget can sit behind the picture's subject. There is a per-widget switch plus a
  master switch.

The cut-out comes from **rembg** (approved), installed with
`uv tool install --python 3.13 "rembg[cpu,cli]"`, because system Python is 3.14.

## 1 · `mooi wallmap <file>`

**What starts it.** The widgets logic watches `~/.cache/current_wallpaper_source`; on a change it
runs `bin/mooi wallmap` in the background.

**Cache.** `~/.cache/mooi/wallmap/<sha1>/`, holding `still.png` (the framed still), `cut.png` and
`map.json`. When the run is done, the picture's directory is copied as `wall-cut.png` and
`wall-map.json` into mooi's data folder.

**Framing.** As the picker frames it: `-resize 1920x1080^ -gravity center -extent 1920x1080`.
For a video or GIF, the first frame is used and `depth` is false.

**`cut.png`.** `rembg i still.png`, then the alpha is feathered by 1.5 px. Without rembg,
`"cut": false`.

**`map.json`:**

| Field | Meaning |
|---|---|
| `cols` | 32 |
| `rows` | 18 |
| `cells` | `[{l, a, b, d, s}]` row by row. `l` is luma 0–1; `a`, `b` are Lab channels in −1…1; `d` is detail, the edge density 0–1 after Sobel; `s` is subject, the cut-out's mean alpha 0–1. |
| `mood` | `{luma, sat, contrast, detail}`, each 0–1 |
| `cut` | bool |
| `depth` | bool |
| `src` | the source file |

## 2 · `lib/wallmap` (pure, tested)

- `M.parse(t) -> map | nil`
- `M.under(map, x, y, w, h, screen) -> { l, a, b, d, s }`: the mean over the cells the rectangle
  covers (`s` is the max).
- `M.tone(l) -> "light" | "dark"`: dark text when `l > 0.58`.
- `M.haze(d, l) -> 0..1`: 0.2 + 0.7·d, plus 0.2 if l is mid-grey (0.35–0.65); clamped.
- `M.accent(cell, palette_rgb, ground_rgb) -> rgb`: the Lab colour under the widget at L = 0.7,
  chroma ≥ 0.25, blended 35 % toward the palette accent, then lightened or darkened until its
  contrast with `ground_rgb` is ≥ 4.5.
- `M.calm_spot(map, doc, index, screen) -> x, y | nil`: the nearest place, by centre distance, on an
  8 px raster, where the widget fits without overlapping others and has subject < 0.15 and
  detail < 0.45 under it.
- `M.mood(m) -> { glow = 0.6…1.2, pace = 0.7…1.2, soft = 0…1 }`

## 3 · Widgets

**Options.** `adapt` (default true) and `behind` (default false) on every widget.

**`settings.json`.** `widgets.depth` (default true) and `widgets.mood` (default true).

**Per row facts.** For every widget the logic sets:

- `tn`: 1 for dark text, 0 for light
- `hz`: haze strength
- `ar`, `ag`, `ab`: the accent
- `over`: true when `s > 0.3`, for the hint in edit mode

**Scene.**

- **Colour.** Components take the text colour and the accent from these values when `adapt` is on;
  otherwise the palette, as now. Visualiser lanes use the accent (and a mix of it) as `t1` / `t2`.
- **Depth.** Widgets with `behind` (and the master on, and the map's `depth`) are drawn first,
  lanes included. Then the image `wall-cut.png` is drawn at `0, −bar` with size `screen`. The rest
  are drawn after.
- **Mood.** It scales visualiser glow and `np_tspd` (pace), and haze softness.
- **Edit mode.** Subject cells are shaded at 10 %; a widget over the subject shows the hint; the
  panel has **ADAPT** and **BEHIND** switches and a **FIND A CALM SPOT** button, which can be undone.

## 4 · Settings, cost, tests

**Settings → Widgets** gets Depth and Mood switches. When rembg is missing, the Depth row reads
"needs rembg".

**Cost.** GPU with depth on: Sleeve + full-width visualiser + the cut-out still under 8 %.

**Tests.**

- `lib/wallmap`: parse, under, tone, haze, accent contrast, calm_spot, mood.
- Live: wallmap on the current wallpaper (files written, cut-out visible), an adapted widget and a
  widget behind the subject (screenshots), and GPU.
