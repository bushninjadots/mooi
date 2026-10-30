# Music on every edge

**Date:** 2026-10-29
**Status:** design, awaiting approval
**Approach:** 3 — a geometry rim on every surface, with a shared glow and one audio feed

## Why

mooi already has a border that steps with the music: `bar.foot_visualizer`, the
"bars" style on the notch pieces' feet. It is the one visualiser the user
actually keeps on. But it reaches only the bottom edge of the notch mode, and
every other surface that reacts to music does so on its own:

- the bar's islands and full panel have no music on their borders at all;
- the Control Nexus draws `EdgeBars` on one open side only, from its own cava;
- the notch has no border reaction, only the bars inside the Music panel;
- the player has its own inner visualisers and its own cava;
- the screen frame has a music swell the user says looks bad.

Four scenes, up to four cava processes, four band counts (16, 32, 24, 24) and
four phases. Nothing moves together. The user's words: *"yes i want it
altogether … yes i want every mooi surface"*.

The goal is one living edge: when music plays, every mooi surface carries the
same bars around its real border, on the same beat, in the style that already
exists. When nothing plays, every surface is exactly the plain border it is
today.

## What success looks like

- With music playing, the bar (all three modes), its pop-up islands, the Nexus
  deck and its cards, the notch panels and the player all show bars growing
  outward from their exposed edges.
- All of them share one envelope, one beat and one phase: they breathe as one
  system rather than four visualisers that happen to be on screen.
- At rest, every bar is zero height and the surfaces look unchanged.
- One cava process runs at a time, not one per scene.
- The bar scene stays within the current frame budget (target: no more than
  ~5% late frames over a 60-second sample, versus the same sample with the rim
  off).
- The inner visualisers (the media module, the notch Music bars, the player's
  ring/spectrum and the `player.viz_*` settings) keep working exactly as they
  do now.
- `bar.foot_visualizer` still means "the border is the visualiser"; it now
  means the whole border, everywhere.

## Non-goals (phase one)

- The standalone scenes: Settings (`mooi-settings`), the wallpaper studio
  (`mooi-board`), the wallpaper window (`mooi-wallpaper`), the desk windows and
  BMO. They are separate processes and get the rim later, using the same
  library and feed, without rework.
- Any rim around the monitor itself or the screen frame.
- New visualiser styles inside panels. The existing inner visualisers stay.
- A new dependency, a new daemon, or a compositor feature.

## Anti-goals

- A rim that draws a second static border at rest, making surfaces look
  double-edged.
- Bars on every chip, button, field and text box. That is noise, not life.
- A full-screen shader or full-surface blur running at 30 fps.
- Per-surface cava processes or per-surface clocks that drift apart.
- Changing what the existing inner visualisers look like.

## Constraints

Pleamar 0.4.6:

- `path` is one stroke of at most 64 already-flattened points. A 32-bar run is
  better drawn as boxes plus 1 px lines, the way `EdgeBars` already does it.
- Boxes and bodies are axis-aligned; there are no rotated rectangles.
  Diagonal edges (the notch fan's hexagons) cannot carry straight bars without
  shearing. They get a lit edge and glow instead.
- A WGSL `shader` is clipped to its own rectangle and `corner`. It cannot
  follow a compound silhouette (the three notch pieces, the Nexus notch tabs)
  without several quads, and it costs the full area it covers.
- A `group` accepts `glow: radius, amount, colour` and blooms from the group's
  actual painted silhouette. It is the only effect that hugs an arbitrary
  shape. It costs the group's bounding box, so each side must be its own small
  group, not one group around the whole panel.
- The files service is shared between the scenes. Writes are atomic (written
  alongside, then moved into place). `sys.watch("files:name", f)` reports
  changes from any scene; there is no documented unwatch.
- A library's code behaves as if it were written at the start of the scene, so
  a shared component can read scene facts by name. That is how `ui/ferrolume`
  already reads `st_*`.
- All mooi surfaces are full-screen with `reserve`, so bars may grow outward
  into the desktop area without being clipped.
- `motion.reduced` and `motion.saver` must keep working.

## Approaches considered

1. **Geometry rim.** Turn `BarFoot` into a reusable component and lay bars on
   every perimeter. Exact shapes, closest to the existing style, no shader
   risk. Cost: per-shape geometry, and a purely geometric rim feels stiffer.
2. **Shader rim.** One WGSL rounded-border shader per surface, with audio bars,
   flow and glow in the fragment. The most fluid and cheap per pixel, but it is
   rectangular: the Nexus notches and the notch's three pieces would need
   several quads, diagonal shapes still cannot follow, and only eight audio
   values fit per shader instance.
3. **Hybrid — picked.** Geometry for the actual bars on every exact shape,
   plus a shared glow/flow layer, all driven by one feed.

**Refinement, stated plainly:** the shared glow/flow layer is built from
Pleamar's per-side `group { glow }` and a shared phase, not from a new WGSL
shader. The picked approach promised "geometry + shared glow/flow", and this
delivers exactly that. A shader would be a rectangle trying to imitate shapes
that the group glow follows natively, and it would put a full-panel fragment
pass at 30 fps on the bar, Nexus, notch and player at once. WGSL stays
available as a later upgrade behind the same `Rim` API if the glow proves too
subtle.

## How it works

### 1. One feed for every surface

**New pure module:** `shell/lib/vizfeed.luau`, so `tests/unit` can exercise it
without a running shell.

**File:** `viz-levels.txt` in the scene's files folder (the same folder as
`settings.json` and the cava configs).

**Format, one line, versioned:**

```
v1 <32 ints 0..1000> <bass> <high> <beat> <phase> <playing> <missing> <seq>
```

- `v1` is the format. A consumer that does not know it ignores the line.
- 32 bands, left to right, as integers (1000 = full). Integers keep the line
  short and parse trivially.
- `bass`, `high`, `beat`: 0..1000.
- `phase`: 0..1000, one full turn per bar of the music (or a slow free-running
  turn when no tempo is known). Shared by every surface.
- `playing`: 0 or 1.
- `missing`: 1 when cava cannot run (not installed / cannot read PipeWire).
- `seq`: a counter, so consumers can tell a new frame from a repeated one and
  detect a stalled producer.

`vizfeed.encode(t)` returns the line; `vizfeed.decode(text)` returns a table
or `nil` for a partial/unknown line; `vizfeed.silent()` is the rest frame.
Constants for the filename, band count and staleness live in the module.

**Producer:** `shell/bar.luau`.

- One cava, 32 bands, 30 fps, the existing pipewire/raw/ascii setup.
- The existing `swell` envelope grows into the shared analysis: level, high,
  beat (a rising edge with a short refractory period), and phase (advanced by
  the detected beat interval, otherwise a slow fixed turn). The bar's own
  `lv0..lv15`, `fbass`, `fhigh`, `fph` facts are derived from the same 32 bands,
  so the bar's existing visualisers and the screen frame (if the user leaves
  it on) stay in sync with the rims.
- Publish when a band moved by more than a small epsilon, at most 30 times a
  second, plus a keepalive at least every 500 ms while playing. Publish
  immediately on play, pause and stop.
- On pause/stop: write `vizfeed.silent()` once and stop cava, exactly as the
  bar does today.
- Keep `fact.viz_missing` accurate; the `missing` token carries the same fact
  to the other scenes.
- While `motion.reduced` is on, do not start cava for the rim alone and publish
  silence.

**Consumers:** `mooi-nexus.luau`, `mooi-notch.luau`, `mooi-player.luau`.

- Delete their cava config, spawn, kill, parsing and `sent` bookkeeping.
- `sys.watch("files:viz-levels.txt", ...)` once at startup. In the callback,
  decode, ignore a repeated `seq`, and only write band facts while the surface
  is open (Nexus deck open, notch Music/panel open, player open).
- Map the shared 32 bands onto each scene's existing fact count: Nexus keeps
  `dv0..dv31`; notch and player keep `mv0..mv23` / `nv0..nv23` by sampling the
  32 evenly. The player's existing 24→16 thinning for `ui/viz.plm` is
  untouched.
- `missing` sets each scene's `*_viz_missing` fact, so the existing "CAVA
  MISSING" messages keep working.
- A stale feed (no new `seq` for ~2 s while `playing` is 1) settles the rims to
  rest rather than freezing them mid-bar. The next frame resumes.

**Why a file and not a bus:** the scenes are separate processes, the files
service already offers atomic writes and change notification, and a ~250-byte
line at 30 fps is cheaper and simpler than a new IPC surface. The cost is up to
one frame of latency, which is under the visual threshold for a 30 fps
visualiser and is the same for every surface, so they stay in sync with each
other.

### 2. The `Rim` library

**New:** `shell/ui/rim.plm`, imported by every scene that draws rims.

Contract: the scene sets these facts before including the rim (or the rim
reads them by name, as `Ferrolume` reads `st_*`):

| fact | meaning |
| --- | --- |
| `rm0 … rm15` | the 16 display bands, 0..1 (the feed's 32 already folded) |
| `rm_bass`, `rm_high` | 0..1 |
| `rm_beat` | 0..1, 1 on the beat, decaying |
| `rm_phase` | 0..1, one turn per bar |
| `rm_gain` | strength multiplier, from the setting |
| `rm_glow` | 0 or 1 |
| `rm_on` | 0 or 1: music is playing and the rim is wanted |

The scene maps the feed into these facts in one small block; a scene that does
not use rims does not include the library, so nothing changes there.

**Components:**

- `Edge(u0, u1, span0, span1, at, dir, n, tint, hot, line_c)` — a run of bars
  along one straight edge. `u0..u1` is the run; `span0..span1` is the whole
  edge, so band positions do not stretch when a run is split around a notch or
  a corner. `at` is the edge coordinate, `dir` is +1/-1 (outward), `n` is the
  number of bars (capped at 32), `tint` is the bar fill, `hot` the accent used
  on the beat, `line_c` the 1 px edge.
- `Rect(x, y, w, h, r, mask, tint, hot, line_c, density)` — four `Edge`s with
  corner gaps of `r + 1`, and a four-bit `mask` for which sides are exposed.
  The top of the bar strip and anything flush to a screen edge are masked off.
- `Glow(amount, colour)` — the wrapper each `Edge` uses: a group containing
  that side's boxes and lines, with `glow: 7 * scale, amount * rm_beat, colour`
  when `rm_glow` and `rm_on`. One group per side keeps the effect's bounds to
  a strip, not the whole panel.

**Bar behaviour:**

- Bar height: `reach * rm_gain * band * (0.75 + 0.25 * rm_beat)`, with a
  travelling term `0.9 + 0.1 * sin(2π(rm_phase - pos))` so a soft wave moves
  along the edge. `reach` is 8-12 px depending on surface size.
- Bars grow **outward** from the border, exactly like `BarFoot` and `EdgeBars`.
  At rest they are 0 tall and only the surface's existing border shows.
- `n` is chosen per edge: roughly one bar per 12-16 px, capped at 32, min 6.
  Short edges get fewer, wide edges more, so a mini player card does not get
  the same 32 bars as a 1200 px panel.
- Fill uses `mix(tint, hot, 0.35 * rm_beat)`; the 1 px line stays the surface's
  own edge colour, so the rim reads as the border lifting, not a sticker.
- `rm_gain` multiplies height and caps at 1.5. `rm_glow` toggles the halo.
- `motion.reduced` (or a still frame) forces `rm_on = 0`, which leaves the
  plain border.

**Why boxes, not one path:** a 32-bar run would exceed the 64-point path limit
once both sides of the bars are counted, and boxes give each bar its own
height without rebuilding a path every frame. This is the `EdgeBars` technique
generalised to any edge and any shape.

### 3. Where the rim goes

| Surface | Edges | Treatment |
| --- | --- | --- |
| Bar, islands mode | each island frame's exposed sides (left/right/bottom; top only if the island is not flush to the screen) | full rim on the island frames; pop-up islands get left/right/bottom (top attached to the bar) |
| Bar, full panel | left, right, bottom; top attached to the screen | full rim |
| Bar, notch mode | left piece: left + bottom; centre: bottom; right: right + bottom | full rim on each piece, following the fillets |
| Bar pop-ups (`IslandFrame`) | left, right, bottom | full rim, glow |
| Nexus deck (`DeckFrame`) | every exposed side, preserving the notch gaps | full rim replaces `EdgeBars` |
| Nexus bay cards | all four, only when the card is the focused/cascade surface | soft rim; otherwise glow only, so five spectra do not compete |
| Nexus notch tabs | their outer faces | rim on the straight faces, glow around the tab |
| Notch nub | — | glow only (tiny) |
| Notch fan tabs | outer straight edges | lit edge + glow; no bars (hexagons are diagonal) |
| Notch panels | all four exposed sides | full rim |
| Player mini | left, right, bottom | rim at low density + glow |
| Player panel | all four exposed sides | full rim |
| Player cinema | the inner plate's edges, not the screen | full rim; if the view is edge-to-edge, none |
| Chips, buttons, fields, text | — | nothing |

Every one of these surfaces already has a plain border path. The rim only adds
bars on top of it; it never draws a second base border.

### 4. Settings

- **Master:** new `music.rim` (boolean, default `true`). `bar.foot_visualizer`
  is honoured as an alias when `music.rim` is absent, so an existing config
  that turned the foot visualiser off keeps it off. The old key is left in the
  file, not rewritten.
- **Strength:** `music.rim_gain` (integer 25-150, default 100).
- **Glow:** `music.rim_glow` (boolean, default `true`).
- Settings → Bar gets the master ("MUSIC ON EVERY EDGE"), a strength slider and
  a glow toggle, where the foot-visualiser row is today. The config key shown
  is `music.rim`; the alias is noted in the row's description.
- `nexus.visualiser` stays and becomes the Nexus deck's own override: with it
  off, the deck keeps its plain border even when the master is on. Its label
  becomes "MUSIC ON THE DECK'S EDGES".
- The player's `player.viz_*` settings keep controlling the inner visualisers.
  Phase one gives the player no separate rim toggle; it follows the master.
- The notch follows the master.
- `motion.reduced` and `motion.saver` force the rims to rest, regardless of the
  master.

### 5. Retiring the screen-frame swell

The screen frame's music body is the most expensive thing in the scene
(measured 24-38% late frames versus 5% for the plain band) and the user says it
looks bad. `frame.music` defaults to **false** from this change on. The code
and the setting stay, so anyone who wants the swell can turn it back on; the
rim does not attach to the screen frame and does not replace it.

### 6. Performance

- One cava at 32 bands instead of up to four cavas.
- One 250-byte atomic write at ≤30 fps, plus a 2 Hz keepalive.
- Rim geometry: at most 32 bars per side; the visible set at any time is on the
  order of 100-200 boxes and lines.
- Glow: one group per side, 6-9 px radius, only while playing and only when
  `music.rim_glow` is on. The halo's bounds are the side strip, not the panel.
- Consumer reads only while their surface is open; a closed scene ignores the
  watch callback's contents (it still costs one tiny read).
- Budget check: 60-second sample in each mode with the rim on and off. Target
  ≤5% late frames, and no regression in the bar's baseline. If exceeded: lower
  the bar count per edge first, then the glow radius, then disable glow for the
  largest surface. The plan must include the measurement, not just the target.

### 7. Testing

**Unit (`tests/unit/run.lua`):**

- `vizfeed` round-trips a full frame, silence and a missing frame.
- `decode` rejects a truncated line, an unknown version and a wrong band
  count without throwing.
- `decode` accepts a line with extra trailing fields (forward compatibility).
- staleness: a repeated `seq` is not new; an old `seq` is not new.
- the 32→16 and 32→24 mappings preserve order and endpoints.

**Compile:** `pleamar --check` on `mooi.plm`, `mooi-nexus.plm`,
`mooi-notch.plm`, `mooi-player.plm`, `mooi-settings.plm` and `ui/rim.plm`.

**Integration (`tests/`):** extend the existing scene/nexus/media tests with:

- only one cava process while music plays (`pgrep -c cava` is 1);
- `viz-levels.txt` exists, advances while playing, and settles on pause;
- the feed disappears/stales without crashing a consumer; rims rest;
- master off → no bars anywhere; Nexus override off → only the Nexus rests.

**Manual matrix:** bar islands / full / notch; Nexus top / bottom / left /
right edges and vertical deck; notch fan and each panel; player mini / panel /
cinema; solid / glass / blur / clear / mech surfaces; motion reduced; no cava
installed.

### 8. Phases

1. `vizfeed` + the producer in the bar + remove the three consumer cavas.
2. `Rim` library + the bar (all three modes and pop-ups).
3. Nexus deck, cards and notch tabs.
4. Notch panels, nub and fan.
5. Player mini, panel and cinema.
6. Settings, screen-frame default, tests and measurement.

Each phase compiles and can be looked at on its own; phases 3-5 do not depend
on each other once the feed and library exist.

## Risks and mitigations

- **Group glow cost or muddiness.** One group per side, small radius, off by
  default only if measurement says so; the `Rim` API keeps the glow separate
  from the bars so it can be tuned or dropped without touching geometry.
- **Bars at screen edges.** Outward bars on a flush edge would be clipped or
  invisible. The per-surface masks above skip flush edges; each scene passes a
  mask, and the bar's top and the notch's top are always off.
- **Feed latency/jitter.** Up to 33 ms, identical for every consumer, so the
  surfaces stay relative to each other. The beat envelope is computed once, on
  the producer, so a late read cannot produce a double beat.
- **No unwatch.** Consumers keep one watch for their lifetime; the callback is
  cheap and only applies while open. If a later Pleamar adds unwatch, the
  consumer can attach and detach with its panel.
- **Fact-name collisions.** All rim facts use the `rm` prefix, and the library
  documents the contract in its header.
- **Bar band regression.** The bar keeps `lv0..lv15` derived from the new 32
  bands; the inner media visualiser still reads `vb0..vb15` exactly as now.
- **Settings migration.** `music.rim` absent + `bar.foot_visualizer` present is
  the only legacy path; a unit test covers true, false and both-present.

## Left to the builder

- Exact bar counts and `reach` per surface within the stated ranges, tuned by
  eye on the real screen.
- Whether the Nexus bay cards get a soft rim or glow only in the non-focused
  state; the document's preference is glow only, but the builder may keep a
  thin rim if the deck looks dead.
- The precise beat detector (rising edge, refractory period) and phase
  advance, using the existing `swell` code as the starting point.
- Which existing `Frame`/`IslandFrame`/`DeckFrame` call sites need an extra
  `mask` argument versus a scene-level wrapper.
- The settings row layout and wording, within the labels above.
- Whether the notch's music panel keeps its inner bars when the panel rim is
  on; the intent is yes (inside and edge are different layers).

## Calls made in this document (check these while reading)

- The glow/flow layer uses Pleamar group glow, not a new WGSL shader; the
  outcome of approach 3 is unchanged.
- The master lives at `music.rim`; `bar.foot_visualizer` is a backwards-
  compatible alias rather than the master itself.
- `frame.music` flips to off by default.
- Standalone scenes are phase two, not phase one.
- Player inner visualisers are untouched and have no separate rim switch in
  phase one.
