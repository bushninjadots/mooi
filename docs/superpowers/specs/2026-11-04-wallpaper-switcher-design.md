# D145 · mooi's own wallpaper switcher — design

Date: 2026-11-04 · Status: approved and built (D145 in docs/DECISIONS.md records where the build differs: Space toggles the preview, `/` searches)

## Why

Wallpaper changes are sometimes slow or glitchy. Today three things take turns drawing the
wallpaper: the Quickshell picker (`qs-wallpaperpicker`) draws it, `skwd-walld` is cold-started for
each notch pick to play its transition on its own layer and is stopped 6 s later, and mooi's desk
(`mooi-desk.plm`) can draw it too but is off (`desk.on = false`). The handoff between them, a
daemon starting up, and the palette sync running during the transition are the likely causes.

## Goals

- mooi draws the wallpaper, always, in Pleamar: stills, animated images and videos.
- One apply path, used by the notch, the new picker and the CLI.
- A new picker program with two views: a Skwd-style skewed **strip**, and mooi's own
  **colour orbit**.
- Transitions that never stutter: no daemon cold start, no layer handoff, palette work after the
  transition has begun.

## Non-goals

- No Wallhaven changes (the notch's FOLDER · WALLHAVEN row stays as it is).
- Skwd / Quickshell picker files are not deleted from the system; they leave the wallpaper path.
  Their removal from `setup/` follows a few days later (as with the old widgets).
- No new palette pipeline: `matugen` with mooi's existing extraction args stays the one writer.

## Kinds of wallpaper

| kind       | files                         | drawn by                                   |
|------------|-------------------------------|--------------------------------------------|
| `still`    | jpg/jpeg/png/webp (static)    | mooi-desk (Pleamar image)                  |
| `animated` | gif, animated webp/png        | mooi-desk (Pleamar plays them natively)    |
| `video`    | mp4/webm/mkv                  | `mpvpaper` underneath; mooi-desk steps aside |

Pleamar plays GIF / animated PNG / animated WebP looping, waking only on frame changes and pausing
when unseen (docs/11-language-reference.md, `image`). It has no video player; `mpvpaper` (installed)
plays videos on the background layer. Today: ~3,170 images and 4 GIFs in `~/Pictures/wallpapers`,
36 mp4 in `~/Pictures/livewalls`.

## Architecture (approach A)

Three focused pieces:

1. **mooi-desk is the wallpaper.** Always running on the background layer (the `desk.on` switch
   goes away as a way to turn the desk off; parallax/cutout settings stay). It draws the picture and
   plays the transition (`desk.transition`: random/grow/wipe/slide/fade, existing D144 code).
2. **`lib/walls.luau` + `mooi wall apply <file>`** — the one apply path. Pure planning in Lua
   (unit-tested), side effects done by the caller through `launch`.
3. **`mooi-walls`** — the picker, a separate program on the overlay layer that runs only while open
   (Pleamar's per-frame cost scales with scene size; animated things live in small scenes).

### Apply flow

```
notch / picker / `mooi wall apply FILE`
  → walls.plan(FILE)
     kind      = still | animated | video
     still     = FILE, or an ffmpeg frame of it (cached ~/.cache/mooi/walls/stills/<sha>.jpg)
  → emit to mooi-desk: wall_next(FILE, still, kind, transition, origin)
  → desk transitions to the new picture (a video comes in as its still)
     · video: start `mpvpaper -l background -o "no-audio loop" '*' FILE`; once its process is
       up and a short settle (~400 ms) has passed, the desk fades its picture out → the video shows
     · leaving a video: the desk fades a still in over it first, then mpvpaper is stopped
  → after the transition starts: symlinks ~/.cache/current_wallpaper_source → FILE and
     ~/.cache/current_wallpaper → still (lock screens and others keep reading these),
     then matugen on the still (existing args from hypr/theme/scripts/matugen-extract,
     light/dark from gsettings) → palette.json → the shell repaints
```

One mpvpaper at most: mooi records its pid (`~/.cache/mooi/walls/mpvpaper.pid`) and kills a stray
before starting another. `-p` (auto-pause when hidden) is on.

Removed from the path: `skwd-helm apply`, starting/stopping `skwd-walld`, the qs-wallpaperpicker
IPC and its `wallpaper-apply` fallback, and awww. The notch code in `shell/mooi-notch.luau` that
does this (around `skwd-helm` / `qs … ipc call wallpaper set`) is replaced by `mooi wall apply`.
At session start mooi stops `skwd-walld` and does not start the Quickshell picker for wallpapers.

## The index

`tools/wallindex.py` (nice 19, background) writes `~/.cache/mooi/walls/index.json`:

```json
{ "version": 1, "items": [
  { "path": "...", "kind": "still|animated|video", "hue": 217.9, "grey": false,
    "luma": 0.41, "mtime": 1730000000, "thumb": "~/.cache/mooi/walls/thumbs/<sha>.jpg" } ] }
```

- Thumbnails 320 × 180, cover-cropped: ImageMagick for images (first frame of animated ones),
  `ffmpeg -ss 1 -frames:v 1` for videos.
- Hue: reuses `wallpaper-hues.json` values where present (the notch's cache), so the notch then
  reads the index instead; `grey` is true where that cache says `false`.
- Incremental: only files whose mtime changed or that are new; removed files dropped.
- Also renders the orbit's dot image (`orbit.png`, see below) whenever the index changes.
- The picker opens at once with whatever exists and refreshes when the index file changes
  (`sys.watch`).

Folders: `~/Pictures/wallpapers` and `~/Pictures/livewalls` by default; `settings.walls.folders`
(Settings → Wallpaper) changes them.

## The picker: `mooi-walls`

Opened with Super+W (and `mooi walls`, and the notch's ↗). Super+W today runs
`wallpaper-styles/bin/wallpaper-picker toggle` (`~/.config/hypr/config/bind.lua:54`); mooi's own
`custom/mooi.lua` unbinds it and binds `mooi walls`, so the user's bind.lua is untouched.
`mooi wallpaper` (Super+Alt+L, today `skwd-wall-v2`) opens `mooi-walls` too. Overlay layer, keyboard exclusive while
open. Shared top row: source (PICTURES · LIVE · ALL; LIVE = videos and animated), type-to-search
on file name, transition choice. Tab switches views (the last used is remembered in
`settings.walls.view`). Esc closes. Enter / click wears the picture; the picker closes as the
transition starts.

### Strip view (Skwd-like)

A band across the lower third: ~15 slanted (parallelogram-clipped) cards, the centred one larger.
←/→ and scroll slide it; a LIVE tag on videos; animated images play in their card. A model of 32
thumbnail slots holds the visible cards plus a margin — the folder's size never matters.

### Orbit view (mooi's own)

- Every picture placed on a wheel: angle = hue, radius = luma (lighter at the rim, darker
  inwards). Greyscale pictures form a small ring at the centre.
- The whole folder is one pre-rendered image (`orbit.png`, one coloured dot per picture) — one
  image, not 3,200 shapes. Scroll spins the wheel (the image rotates); right-click zooms into the
  hue under the pointer (the image scales).
- The ~40 pictures nearest the pointer swell into real thumbnails (a 48-slot model).
- The centre shows the palette the hovered picture would give the shell: `matugen image <still>
  --dry-run -j hex` with mooi's args, debounced 250 ms, cached per picture
  (`~/.cache/mooi/walls/palettes/<sha>.json`).
- Holding Space shows the hovered picture on the desk behind; releasing returns.

### Pleamar budget

The atlas is at most 2048 × 8192 (~280 thumbnails of 320 × 180). The picker holds at most
32 + 48 thumbnail slots plus `orbit.png`. Only the open view's slots are filled.

## The notch

The Wallpapers carousel stays: it reads the index, shows LIVE tags (videos as their still),
and wears through `mooi wall apply`. Its ↗ opens `mooi-walls` instead of Skwd Wall. The grow
transition still starts from the notch's edge (`from_notch`).

## Errors

- A missing or undecodable file: skipped by the index, with the reason in the index's `skipped`
  list; `mooi wall apply` exits non-zero and the notch says COULD NOT WEAR IT.
- mpvpaper fails to start or dies: the desk stays on the video's still; the notch / picker says so.
- matugen missing or failing: the picture changes; the palette stays.
- The index not built yet: the picker shows what exists and a "reading N pictures…" line.

## Testing

- `tests/unit/run.lua`: `walls.kind`, `walls.plan`, orbit placement (hue/luma → x,y; greys
  centre), the strip window (which slots for a position), search/source filters, the debounce.
- `tools/wallindex.py`: run on a scratch folder with a still, a GIF, an mp4 and a broken file.
- On screen: drive with `pleamar --say mooi-walls "emit …"` and screenshots; no pointer automation
  or workspace switching without asking. Check each transition into and out of a video, and GPU
  cost (DRM fdinfo per pid) of the desk with an animated wallpaper and the picker open.

## Decision record

Logged as D145 in docs/DECISIONS.md when built.
