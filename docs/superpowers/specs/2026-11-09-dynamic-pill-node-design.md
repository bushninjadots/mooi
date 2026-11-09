# The Dynamic Pill as a living node — design

> Status: approved in conversation (2026-11-09). The owner's brief ("MOOI DYNAMIC PILL — COMPLETE REFACTOR &
> REDESIGN", 25 sections) with three answers: remove **all of Loom / Fold** (done, D225); **one new engine** replacing
> both the classic Pill (D168–D206) and the Sigil (D207); **all stages without stops**. The brief speaks of
> QML/Quickshell; mooi is Pleamar — every part below is the Pleamar form of the brief's idea.

## 1. The idea

The Pill is no longer a pill. It is **a node**: a tiny seed at the top of the screen that grows a different
structure for each thing that happens, then recombines into the seed. Seed → react → unfold → branch / orbit →
interact → recombine → rest. Glancing at the desktop shows almost nothing.

## 2. One program: `mooi-node`

- `shell/mooi-node.plm` (one full-width surface at the top, `level: top`, rising to `overlay` for the universe;
  input only where something is drawn — the rest of the screen takes its clicks as usual) and
  `shell/mooi-node.luau` (the logic).
- Pure libraries, unit-tested, in `shell/lib/node/`:
  - `state` — what the node is: rest, react, media, notice, volume, workspaces, system, launcher, universe; each
    event's priority and lifetime; what wins; when it recombines.
  - `geometry` — each state's target shape: the body (x, y, w, h, corner), its branches (segments), its satellite
    slots; the anchor; the personality's variant.
  - `motion` — the four personalities as spring constants, stagger and overshoot; the animation intensity.
  - `interaction` — the pointer: approach, hover, leave with thresholds, hysteresis and a cooldown; the side it comes
    from (expansion leans that way).
  - `satellites` — contextual objects (music, notice, recording, volume, battery, network, workspace, timer):
    appear, orbit, attach, merge, recombine; the merge rule (music + recording → one composite).
  - `universe` — Super+Tab's workspaces arranged round the node; the chosen one dominant.
- It reads mooi's existing sources, adding no duplicate watchers in other programs: the `media`, `workspaces`,
  `audio`, `battery`, `network` services (one watcher each, here); notices from Signal Loom's feed
  (`nexus-feed.json` — only one program may receive notifications); recording from mooi's own flag; system numbers
  from the bar's feed (`sigil-feed.json`).
- `mooi.luau` starts it in Pill mode (as it starts the frame), respawns it like the others.

## 3. The states and their geometry

- **Rest — the seed.** A 22 × 6 capsule (Minimal: a 6 px point) under the top edge; breathes very slightly
  (a 2 s spring cycle, off under reduced motion); a faint tick for the active workspace's change.
- **React.** Something happened: the seed stretches toward the event's shape before it unfolds (a 120 ms lead).
- **Media — lateral.** A horizontal capsule grown both ways: the cover, title and artist, play/pause and skip, a
  progress line, a small visualiser woven into the capsule's floor (the music's level). Stays while playing and
  the pointer is near; otherwise it shrinks to a music satellite.
- **Notice — branching.** A short stem drops from the node and a card branches from it (app, title, its first
  action); several stack as branches. Each leaves on its own after its time; a press opens its app (D223).
- **Volume / brightness — a gauge.** The node becomes a line gauge for two seconds.
- **Workspaces — a rail.** `1 ── 2 ── [3] ── 4 ── 5`: the active one physically selected (a sliding bead); a change
  animates along the rail; shown for a moment on a change, or while the pointer hovers.
- **System — a cluster.** CPU, RAM, temperature, network round the node on short spokes; only when opened (a press
  on the seed, or the pointer resting on it).
- **Launcher — search.** Super+Space: the node widens into a search line; results grow below it (apps by name,
  then by launch count — `lib/wbelow.grid_apps`); arrows choose, Return launches, Esc recombines. The keyboard is
  the node's only while it is a launcher.
- **Universe — Super+Tab.** The node becomes the centre of the workspaces: each an orbiting tile (its number, its
  windows' app marks) round it, the active dominant; the wheel or arrows move round, Return or a press goes there,
  Esc recombines. Level overlay while open.

Shapes morph through one continuous body — seed → capsule → branch → cluster → expanded → back — on springs: the
body's box and corner are springs, branches grow from the body's edge, satellites leave from and return to it.

## 4. Satellites

Up to six at once, round the node (an arc under it): music (when the media state is not open), notice count,
recording, mic in use, low battery, network lost, a running timer. Each has a priority and a lifetime; the arc keeps
the highest; a press opens its state. **Merging:** music + recording become one composite capsule (● REC · bars ·
MUSIC ▶); volume merges into music while playing.

## 5. Spatial behaviour and the pointer

Anchored at the top (centre by default; left or right a setting). The node leans toward the side the pointer
approaches from; it never follows the pointer. Approach (within 120 px) wakes it a little; hovering 250 ms unfolds
the preview of what it holds; leaving retracts after 600 ms; thresholds keep ordinary pointer movement from
triggering it (hysteresis 40 px, cooldown 400 ms). Sensitivity: off, low, normal, high.

## 6. Keys

Super (tap) wakes it — the media or the last thing, else the system cluster for a moment. **Super+Space** the
launcher; **Super+Tab** the universe — both in Settings → Keys (they replace ArchEclipse's float toggle and Atlas's
Super+Tab while the node is the Pill). Holding Super stays the Subsurface's.

## 7. The wallpaper

Through mooi-surface (one event, no new program): a small ripple on the wallpaper at the node when a notice
arrives; a soft local dim round the launcher; with music, Live wallpaper's glow at the node. Optional (one setting).

## 8. Personalities (one engine)

**Minimal** (fast, restrained: a point at rest, short travel, no overshoot) · **Organic** (soft, elastic: a capsule,
overshoot, slower settle) · **Technical** (precise: square corners, linear rails, tick marks) · **Cyber**
(fragmented: segmented capsule, quicker, a glitch offset on change). They change spring constants and a few geometry
choices, never the code path.

## 9. Settings (Settings → The Pill, replacing the Pill's ~40 and the Sigil's 7)

On (the node is the Pill in Pill mode) · personality · animation intensity (calm, normal, lively) · pointer
sensitivity · anchor (left, centre, right) · what may unfold: media, notices, workspaces, volume, system ·
satellites (on/off) · wallpaper effects (on/off). Keys: launcher, universe.

## 10. What goes

After the node stands in for them: the classic Pill (its face, pads, rows, board, peek, morph, extra pills, desk
faces; `ui/pill*.plm`, `pillboard`, `lib/pill*`, its ~40 settings and the frame's pill body) and the Sigil
(mooi-surface's `bar`/`drop` surfaces and `lib/surface/{hosts,director,shapes,bodies,sources,layout,palette}`,
`sigil.*`, the bar's host and feed writing that only it reads). Shared parts other programs use stay.

## 11. Cost

Nothing repaints at rest but the seed's slow breath (rate 20 while calm); everything is event-driven; one watcher
per service; no polling; the universe asks for no window pictures (app marks only).

## 12. Out of scope

Downloads (no source in mooi), Git state (no source), touch gestures.
