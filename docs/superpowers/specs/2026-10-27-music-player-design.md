# mooi music player — the overhaul (design)

_2026-10-27 · agreed with the user in conversation; mockups in `.superpowers/brainstorm/` (player-views, visualisers)._

## What the user asked for

A library with album art and two views (normal, detailed); full screen fixed (it looked bad; it did
not close — the close half shipped already, 4e15fff); several kinds of player view; a small player
first when the bar's music icon is pressed, with a button to the real player; strong theming;
creative visualisers; synced lyrics; an equaliser; a better DJ vinyl; video of songs.

Decisions made by the user:

| Question | Answer |
|---|---|
| Mini player contents | Compact: cover, title/artist, seekable progress, prev/play/next, volume, "Open player" — **with a live visualiser in it** |
| Library | **Albums** grid (normal) + **detailed** track list; also **Artists** and **Genres** groupings; search in all |
| Player views | **All three**: DJ deck (default), Cover stage, Instrument rack |
| Visualisers | **All six**: Spectrum, Mirror, Radial ring, Aurora, LED matrix, Orbit — chosen per place |
| Equaliser | **EasyEffects** underneath, mooi's own EQ UI on top |
| Video | **B**: the music video *as the visual*, inside the full-screen frame |
| Architecture | **One player program with three sizes** (mini → panel → full) |

What exists today and is kept: mpd through `mpc` (lib/player is pure and tested), the source switch
(mpd or any MPRIS player through `playerctl`), synced lyrics from LRCLIB (and `.lrc` beside the file),
cover colours through Matugen (`player.colours`), the turntable's tonearm that seeks, cava, light/dark
(D91: the palette carries the mode).

## Shape

One program, `shell/mooi-player.plm` + `.luau`, as today — but the scene in **parts** and the logic in
**modules**, because a single 919-line scene and 659-line logic would double:

```
shell/mooi-player.plm          the scene: facts, the one surface, sizes, keys; includes the parts
shell/player/                  parts (`include`), one each:
    mini.plm                   the compact card under the bar's icon
    panel.plm                  the panel frame: header, view chips, the pane (queue · library · lyrics · eq)
    deck.plm  stage.plm  rack.plm   the three views (each draws in panel and in full screen)
    library.plm                albums grid · detailed list · artists · genres
    eq.plm                     the equaliser pane
    full.plm                   full screen: the chosen view large, its controls, video slot
shell/ui/viz.plm               library: the six visualisers as components, fed by parameters
shell/mooi-player.luau         the logic's spine: state, mpc/playerctl, routing events to modules
shell/player/library.luau      library queries, paging, sorting, the art cache
shell/player/eq.luau           EasyEffects presets and live bands
shell/player/video.luau        yt-dlp lookup, mpv lifecycle and placement
shell/lib/player.luau          (exists) pure parsing — grows: album/artist/genre rows, sorting, art paths
shell/lib/eqpreset.luau        pure: bands ↔ EasyEffects preset JSON, built-in presets
```

`ui/viz.plm` is a library (not a part) so **the bar imports it too**: the media module's visualiser
becomes these components (piece 3), coloured like every other bar component — the main accent
(`fl.phos`) rising into the second (`fl.ember`/`fl.flare`) with the level — so it follows the
wallpaper, the light/dark mode and, while the player shows cover colours, nothing else (the bar
keeps the shell's palette). Today it draws only from the second accent (ember → flare), which with
a violet wallpaper reads as an unrelated pink-red: the user's report.

### Sizes (`fact size: mini | panel | full`)

- **mini** — the bar writes `player-anchor.json` (the media module's centre, as today). The program
  opens as a 420 × 200 **signal board** hanging from it, in the Control Nexus's language (the user's
  redesign, 2026-10-27): the cover is the core node (press: play/pause) inside a progress ring
  (press or drag round it to seek), previous/next are pad nodes wired to it by 45° traces, the
  title a readout on its own trace, the volume a via sliding up a trace, the visualiser pins stand
  on a bus along the foot (style from `player.viz_mini`), pulses run the traces while it plays
  (driven by the record's turning, so a paused card is still), and **OPEN PLAYER**. A press
  outside closes it.
- **panel** — OPEN PLAYER (or `mooi player --panel`, Super+Alt+M) grows the card into the panel in
  place (one spring on `pl_w/pl_h/pl_x`, not a second window). The panel is today's layout rebuilt:
  the chosen **view** on the left, the **pane** on the right (QUEUE · LIBRARY · LYRICS · EQ).
- **full** — FULL (or `f`) takes the screen: the chosen view large, the pane's lyrics or queue beside
  it where the view has room, controls 56 px and up, a 48 px close and a press on empty background
  close (as fixed in 4e15fff). Escape steps back one size: full → panel → (closed). From mini, it closes.

Everything is in the one surface (the lesson of 4e15fff: a second surface took no presses).
Keyboard: exclusive in panel and full; **none in mini** (a card must not steal typing), so mini's
Escape is a press-outside instead.

### The three views (`player.view: deck | stage | rack`, chips in the header)

- **DJ deck** (default) — the platter with a strobe ring (dots that stand still at 33⅓ when the
  music plays at speed), the cover as the record's label, the tonearm (seeks, as today), a **pitch
  fader** (mpd has no speed control, so the fader is ±8 % *visual* only unless the source is
  playerctl with `rate`; stated in its tooltip — never faked as audio), a **cue** button (back to
  the start of the track, or to the last seek point), two VU meters from cava's low and high bands,
  33/45 chip (record spin speed only). The visualiser rings the platter (Radial ring by default).
- **Cover stage** — the cover large with a soft shadow, its colours (Matugen cover palette, already
  computed for `player.colours`) blurred across the background, synced lyrics beside it with the
  sung line lit and the rest fading, controls under the cover. Visualiser: Aurora by default, behind.
- **Instrument rack** — chamfered panels: spectrum or LED matrix analyser, the track and file
  details (the file's extension, and rate/bits/channels from mpd's `audio` status field),
  an LED time readout, a waveform-style scrubber (cava bands over time, not a real waveform — said
  so), and the EQ's three knobs (low/mid/high → the EQ's bands, two-way).

Each view is one part that reads `vw` (its width) and `vh` and draws at either size.

### Visualisers (`shell/ui/viz.plm`)

Six components with the same signature — `(x, y, w, h, bands, tone1, tone2, level)` where bands is
the scene's 48-band cava model: **Spectrum** (bars, falling peak caps), **Mirror** (bars both ways),
**Ring** (radial, given a centre and radius instead of a box), **Aurora** (three layered paths whose
heights follow low/mid/high, blurred), **LED** (a dot grid lit per column, top dots in the second
tone), **Orbit** (particles on three rings: bass swells the inner, treble speeds the outer).
Choice per place: `player.viz_mini`, `player.viz_deck`, `player.viz_stage`, `player.viz_rack`,
`player.viz_full` (enum of the six + off), switched by a chip on the visualiser itself (click cycles).
Reduced motion and the battery saver (D34 `saving()`) draw them still or off. One cava process
for the program (as today), started only while a visualiser is shown and music plays.

### Library

Queries through `mpc` (mpd's database; 1229 albums, 2374 songs here):

- **Albums** (normal view) — a grid of covers, 4–6 columns by width, album + artist under each,
  sorted by artist/album/year (chip); a press opens the album: its tracks, with PLAY ALL / ADD /
  per-track play and add. **Artists** — a list with a count; a press shows that artist's albums as
  the grid. **Genres** — the same, by genre. **Songs** (detailed view) — rows with a 32 px cover,
  title, artist, album, year, length, play/add; sortable by any column (chip on the header).
- **Search** — the field filters whichever grouping is shown (mpd `search any`).
- **Art cache** — `~/.cache/mooi/covers/<hash>-<size>.jpg` at 64 and 256 px: the embedded picture
  (`ffmpeg -an -vcodec copy`) or `cover|folder|front.(jpg|png)` beside the file, resized with
  `magick`; made lazily for the page on screen (at most 24 at a time, one process at a time), kept
  across runs. No art: a generated cover — the palette's two tones in a split, the album's initials.
- Paging as today (the page on screen only); the grid keeps its scroll per grouping.

### Lyrics

Kept as built (LRCLIB synced, `.lrc` beside the file, plain lyrics scroll). Changes: the sung line
large and lit in **stage** and **full**; a press on a line seeks there (exists for synced); an offset
nudge (±0.5 s, kept per track in the data folder) for lyrics that run early or late.

### Equaliser (`player.eq`)

mooi's EQ pane: 10 bands (31 Hz–16 kHz, ±12 dB), a preamp, presets **Flat, Bass, Treble, Vocal,
Rock, Electronic, Acoustic** plus the user's own (SAVE AS), and on/off. Underneath, EasyEffects:
`lib/eqpreset` writes `~/.local/share/easyeffects/output/mooi.json` (an equalizer plugin, 10 bands)
and the logic loads it with `easyeffects -l mooi`; EasyEffects is started as a background service
(`easyeffects --service-mode --hide-window`) when the EQ is first switched on, and left running.
Moving a band rewrites and reloads after 150 ms of quiet. The user's existing presets (`live_eq`,
`vespera_eq`) are listed and loadable, never overwritten. The rack's three knobs map to the
average of bands 1–3, 4–7, 8–10. EasyEffects missing: the pane says so and how to install it.

### Video (B: as the visual)

A **VIDEO** chip on the deck and stage views (and in full screen). Press: yt-dlp finds the best
match (`ytsearch1:"<artist> - <title> official video"`, format ≤ 1080p), mpd is **paused** at its
position, and **mpv** plays it with `--no-border --title=mooi-video --input-ipc-server=…`, its
audio as the music. Placement: a Hyprland window rule for `title:mooi-video` — float, pin, no
focus, no border/shadow — and the logic moves/resizes it (`hyprctl dispatch` on the address) to
the view's visual area: the record/cover box in panel, the stage area in full screen. The player
is an overlay layer, which is always drawn above windows, so mpv sits **under** it and the player
leaves that area transparent (no drawing there), with a thin frame round it. The scene follows mpv's time
over its IPC socket (progress bar, lyrics stay in sync). Closing the video (chip again, Escape,
the track ending, the view changing) quits mpv and resumes mpd **from where the video reached**.
If placement fails (mpv not mapped in 3 s, or the compositor refuses), it falls back to A: a
floating mpv window over the player, said in the footer. No match: "No video found", nothing else.
Network only on press; never automatic.

### Theming

The palette as everywhere (lib/ferro via `palette.json`, light and dark), `player.colours`
shell | cover as today. New: each view gets its material — deck: brushed steel plinth (steel roles),
stage: glass over the cover's blur, rack: chamfered hull panels with engraved labels — all from
roles, so day mode works without a second design. The chamfer follows the coming system-wide corner
setting (roadmap: after this work); until then the bar's chamfer.

## Settings (lib/config schema rows; the Media page in Settings)

`player.view` deck|stage|rack (deck) · `player.viz_mini|deck|stage|rack|full` (mirror, ring, aurora,
led, ring) · `player.library` albums|artists|genres|songs (albums) · `player.sort` artist|album|year
(artist) · `player.eq.on` (false) · `player.eq.preset` (flat) · `player.eq.bands` (10 numbers) ·
`player.video` (true: the chip is shown). Every row added to the schema (D85: unknown keys are dropped).

## Errors and edges

- mpd down: library and queue say "mpd is not running" with the command to start it; MPRIS sources
  still work for transport and the mini card.
- Nothing playing: mini shows the last track greyed with PLAY, or "Nothing playing — open the library".
- A 1229-album grid never loads all covers: only the visible page, queued, capped.
- EasyEffects / yt-dlp / mpv missing: the control is shown disabled with one line saying what is missing.
- Light mode: covers and video keep their own colours; everything drawn is from roles.

## Testing

- Unit (tests/unit/run.lua): album/artist/genre row parsing and sorting, art cache paths, the
  generated-cover tones, EQ bands ↔ EasyEffects JSON round trip and presets, the knob ↔ band
  mapping, the lyric offset, video search string and the resume position.
- Live, on the real session with agent drives and real clicks (as 4e15fff): mini opens from the
  bar's icon and OPEN PLAYER grows it; each view in panel and full; full closes by X, background
  and Escape; library groupings, sort, search, paging and covers appearing; each visualiser in each
  place; EQ on/off audibly changes (and EasyEffects shows the preset); a video plays in place and
  mpd resumes after. Screenshots in light and dark.
- `bin/mooi check` compiles the scene and its parts.

## Build order (pieces, each shipped and shown)

1. Split the scene and logic into parts/modules (no visible change) — the ground for the rest.
2. Mini player + sizes (mini → panel → full), full screen rebuilt on the panel's surface.
3. `ui/viz.plm`, the six visualisers and their per-place choice — **the bar's media visualiser included** (`bar.visualizer` keeps its four existing styles mapped onto the library: bars → Spectrum, mirror → Mirror, dots → LED, line → Aurora-thin).
4. Library: art cache, albums grid, detailed list, artists, genres, sort, search.
5. The three views (deck rebuilt, stage, rack) and their theming.
6. Lyrics polish (sung line, offset).
7. Equaliser (lib/eqpreset, EasyEffects, pane, rack knobs).
8. Video (B, with the A fallback).

## Not in scope

A real waveform (needs decoding the file), audio speed change for mpd (mpd cannot), streaming
services' libraries (Spotify's queue is controlled through MPRIS only), lyrics editing.
