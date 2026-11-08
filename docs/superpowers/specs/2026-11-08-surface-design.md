# Surface: the living desktop surface — design

> Status: design approved in conversation (2026-11-08), awaiting review of this written spec.
> Builds on: the Sigil (D207, specs/2026-11-07-sigil-design.md), which becomes Surface's engine.
> Absorbs, over its phases: the classic Pill, the Sigil's bar hosts, the desktop widgets (`mooi-widgets`).

## 1. What the owner asked for

The owner's concept ("MOOI SURFACE — the living desktop surface / reveal system"), in its own words where
they decide things:

- "The desktop is not a collection of widgets sitting on wallpaper. **The wallpaper is the surface, and the
  interface lives within it.**" The normal desktop is almost entirely the wallpaper; a hidden subsurface is
  exposed through interaction: **Reveal → Explore → Manipulate → Select → Leave → Revisit**. Anything
  deliberately left behind becomes a **Presence**, which remembers everything about itself.
- Three layers: **Surface** (the wallpaper, visually dominant), **Reveal** (the temporary interaction layer
  around the pointer, e.g. while Super is held), **Presence** (an object left on the surface; not
  necessarily a widget — it can become part of the wallpaper).
- The dynamic Pill is **one Surface object**, not a separate system; Hubs are spatial collections, not
  dropdowns; objects **transform into each other** rather than swap; everything is customisable, edited
  **where it exists**; motion is physical (springs, inertia); performance on modest hardware is "extremely
  important": when nothing happens the desktop is almost free.
- Visual language: precise geometry, controlled radii, depth, subtle light, shader-driven transitions; no
  giant rounded cards, glassmorphism, gradients everywhere, dashboards or generic AI UI.
- "Do not build this as a collection of features. Build a coherent interaction language": **"I touch the
  surface, and the surface responds."**

Decisions made with the owner (2026-11-08):
- Keep the Sigil's engine; Surface grows out of it (it is not trashed).
- **The existing desktop widgets are imported** as Presences (A), and every Presence is **wallpaper-aware**:
  **fitted** to the picture by default, and optionally **woven** into its contours ("follow the picture")
  (C).
- **The bar stays** and works together with Surface; it becomes one more place Presences live (B).
- All four reveal effects (Aperture, Membrane, Ripple, Fold) are wanted; **Aperture is the default** and the
  first built to a high polish — "the least distracting".
- Architecture A: grow `mooi-sigil` into **`mooi-surface`**.

## 2. What the spikes established

- **The Sigil spike (2026-11-07):** a 64-point line on springs costs 0.05 ms compose and 0.3 ms paint on its
  own surface; paths inside the frame's band bodies cost 70–110 ms. Rule: draw on own surfaces only.
- **The Surface spike (2026-11-08):** the wallpaper drawn by the program and rippled by a group shader around
  the pointer ran at 60 fps — a 420 px patch: 0.04 ms compose, 0.10 ms paint, 2 % CPU; the whole screen:
  0.30 ms paint, 4 % CPU. A shader reading a **capture of what is behind** (`behind()`) drew nothing on this
  setup. **Rule: effects work on the wallpaper image mooi draws itself, locally, only while active.**

## 3. Architecture

**One program, `mooi-surface`** (`shell/mooi-surface.plm`, generated; `shell/mooi-surface.luau`), the
renamed and generalised `mooi-sigil`, started and respawned by mooi as the frame and the Sigil are. Pure
parts under `shell/lib/surface/` (the Sigil's modules move here; their tests keep passing):

| module | does |
|---|---|
| `sources` | what can be shown (the Sigil's catalogue, grown) |
| `shapes` | the line's forms — 64 points for every kind in any box (the Sigil's) |
| `director` | what each bar host shows; priorities, urgency (the Sigil's) |
| `palette` | colour layers (the Sigil's) |
| `bodies` | temperaments, motion numbers (the Sigil's) |
| `presence` | the Presence model, its memory, validation, migration (new) |
| `reveal` | the reveal's stages, what is near the pointer, release outcomes (new) |
| `wallsense` | contours, lines, calm areas, local colour; placement and snapping (new) |
| `effects` | effect parameters: Aperture first; Membrane, Ripple, Fold later (new) |

**Three layers on screen**, each mapped only while needed:
1. **Presences** — a surface just above `mooi-desk`'s wallpaper and below every window (level `bottom`),
   so they are part of the wallpaper; they wake when approached on a visible desktop.
2. **Reveal** — an overlay above everything, mapped only while Super is held: the Aperture (a hole drawing
   the real wallpaper image and its subsurface), so it **opens through windows**; the Hub and Pill rise in it.
3. **Bar hosts** — the Pill and islands (the Sigil's hosts) as Presences anchored to the bar.

**Files**
- `surface.json` — the arrangement: every Presence and its memory; saved on change; a backup kept per save.
- `settings.json` → `surface.*` — behaviour: trigger and delay, default effect, temperament, edit modifier,
  snapping, high contrast; validated by `lib/config`; setters appended.
- `wall-sense.json` — the wallpaper analysis (§7), beside today's `wall-map.json`.

**Holding Super:** Hyprland binds Super's press and release to `mooi` (lib/hypr, the existing Lua config).
Held ~250 ms with nothing else pressed → the Reveal starts at its faint first stage; a tap keeps today's
behaviour (the Pill's call); the delay is a setting. Known risk: a slow Super+key shortcut may begin a faint
reveal, since Hyprland does not report that the shortcut fired; the faint stage keeps it harmless. The first
task of phase 1 verifies the binding on this desk.

**Performance rules:** effects only around the pointer or a Presence and only while active; nothing in the
frame's band; nothing mapped or repainting when idle; each layer < 1 ms compose + paint at 60 fps
(`pleamar --report`); `rate: …, 20 while calm`.

## 4. The Presence

A Presence = **what it shows** (a source) + **how it is presented** (form and mode) + **where it lives**
(memory).

- **Forms** (the line engine's silhouettes; a change of form morphs): pill · bar · island · orb · freeform ·
  woven (follows the wallpaper, §7).
- **Modes**: ghost (icon, one line, a hairline of progress) · embedded (quiet type on the wallpaper) ·
  aperture (the wallpaper parts around it) · bloom (its colours — Music's album art — light the wallpaper
  near it) · full (the complete control surface; Music: play, pause, previous, next, seek, volume, queue).
- **States**, transitions smooth: active · persistent · ambient (wakes when the pointer nears) · dormant
  (loaded, hidden: another workspace) · transient (only during a reveal). Approaching a persistent or ambient
  Presence wakes it one step (ghost → embedded → full); leaving settles it; holding Super over it expands it.
- **Memory** (`surface.json`): id, source, form, mode, effect, position as a fraction of the screen plus an
  anchor, size, workspace (one or all), monitor, state, priority, its own options, and a `links` slot
  (relationships, later phases). Restored exactly; a missing or resized monitor clamps it back on screen,
  never restored off-screen.
- Duplicates allowed; each has its own memory.
- **Import of the widgets:** each entry of `widgets.json` becomes a Presence at its place, its options mapped
  (clock → clock, now-playing → music, visualisers → visualiser with the same mode, photo and focus →
  sources added for them); `widgets.json` is kept as a backup; `mooi-widgets` retires after the import is
  verified on the desk.

## 5. The Reveal

Stages, each growing from the last, on springs, following the pointer a little behind:
1. **Touch** (Super held ~250 ms): a faint ring of light, a slight lens at the pointer.
2. **Open**: the Aperture opens to ~120 px — through windows to the real wallpaper, the subsurface darker
   inside a lit rim; a small Pill `mooi` at its centre.
3. **Hub**: the Pill unfolds into a ring of groups round the rim — Time, Sound, Machine, Work, You, Desk, and
   This window over a window.
4. **Approach**: moving toward a group pulls the rim that way and opens a second ring of its sources;
   neighbours lean aside; moving toward a source morphs the Pill into it (`♫ Music` → `♫ Artist — Song`).
5. **Expand**: resting on it (~400 ms) grows it into its full form inside the aperture.

Release (configurable per source): in the middle → cancel; on a source → open it (music plays/pauses and stays
open in full until left; the clock opens the calendar); **dragged past the rim and released → left behind as
a Presence** where dropped.

Context under the pointer (phase 1): over a Presence → it expands in place with its actions; over a window →
This window joins the Hub; over the bar → the bar's Pill answers. The owner's own spatial map comes later.

Exit reverses entrance: the content back into the Pill, the Pill into the rim, the aperture closed into the
wallpaper. Keyboard: arrows walk the ring while Super is held, Enter opens, Super+Tab cycles sources, Esc
cancels. Reduced motion: everything in place at once.

## 6. Effects

Effect primitives with parameters (intensity, radius, falloff, speed, softness, colour influence):
**Aperture** (default; phase 1), **Membrane**, **Ripple**, **Fold** (phase 2); composable chains later. Each
is a group shader over the wallpaper image the program draws (§2), in a patch around its target, active only
while revealing or while a Presence's mode uses it. The mockup (`.superpowers/brainstorm/…/surface-reveal.html`,
local) holds the reference look of all four.

## 7. Wallpaper awareness

**Reading**, once per wallpaper (extending `tools/wallmap.py`, off to the side, seconds, never blocking; a
video wallpaper read from its still) → `wall-sense.json`:
- the subject's contour — the cut-out's outline, simplified to a polyline in screen coordinates;
- strong lines — the clearest edges and straight lines with their angles, a horizon if there is one;
- calm areas — low-detail rectangles, ranked by size;
- (already in `wall-map.json`) light, colour, detail and subject per cell.

**Fitted** (every Presence, default): a new or imported Presence settles into the nearest calm area; dragging
snaps gently to strong lines (within ~24 px; can be off); it keeps out of the subject's busiest part or tucks
behind the subject (depth, the cut-out, as today's widgets); its tone and accent come from the picture
beneath it with guaranteed contrast.

**Woven** (per Presence, "follow the picture"): its outline takes the nearest contour or line, resampled into
the line engine's points; a visualiser can ride a contour. Words stay straight and readable (Pleamar cannot
set text on a curve). A new wallpaper re-weaves it, or returns it to its own form if nothing suitable is near.

On a wallpaper change: colours re-fit at once; positions stay unless a Presence now sits on the subject's
busiest part, in which case it moves to the nearest calm place and remembers its own spot for the next one.

## 8. Shaping it

- **Direct manipulation:** hold Alt + Super over a Presence (a setting) → edit mode: drag moves (fitted
  snapping), an edge resizes, the shape handle cycles forms, a compact inspector beside it (mode, effect,
  workspace, source, reset, duplicate, delete). Undo/redo (Ctrl+Z, Ctrl+Shift+Z). Changes save and apply
  live, no restart.
- **Later phases**, designed for, not built in phase 1: the full Surface Editor (position, size, form,
  layout, surface, motion, appearance, interaction); **personalities** (Minimal, Organic, Mechanical,
  Spatial, Cyber, Playful, the owner's own — visual and motion language, physics, effects, default forms);
  **arrangements and snapshots**; per-workspace arrangements; relationships, magnetism, collision avoidance,
  clusters, gravity; surface trails and the focus field; effect chains; import/export; an experimental mode.

## 9. The bar, the Sigil, the widgets

- The Sigil becomes Surface's engine; its Pill and island hosts become Presences anchored to the bar, keeping
  today's behaviour and the owner's current Sigil settings (BMO at rest, calm, drawn to the pointer).
- The classic Pill stays selectable until Surface covers it; then it retires as the Sigil spec §9 describes.
- `mooi-widgets` is imported (§4), then retired.

## 10. Failure

- `mooi-surface` ends: respawned; five quick ends and it stays down; the bar's stand-in clock (and the old
  widgets, until imported) keep the desktop usable.
- `surface.json` broken or partial: the broken Presence is dropped and reported, the rest stands; each save
  keeps a backup.
- Missing monitors or workspaces: Presences dormant or clamped, never lost.
- No `wall-sense.json` yet: fitted placement falls back to the screen's calm defaults; woven Presences keep
  their own form.

## 11. Accessibility

Keyboard paths (§5); reduced motion (instant changes, no idle effects; Pleamar's `motion.reduced` and mooi's);
high contrast (solid plates under words); adjustable stage delays; nothing reachable only by pointer movement.

## 12. Testing

- Unit: Presence memory, validation and migration (including the widgets import); reveal stages and release
  outcomes; wallsense placement and snapping; aperture geometry; the Sigil's existing suites under their new
  paths.
- Every scene compiles (`bin/mooi check`, CI checks generated scenes against their generators).
- Live (`tests/surface.sh`): reveals driven through `pleamar --say` (never the real pointer), settings and
  `surface.json` restored byte for byte; a Presence left, restored after a restart, woken by proximity
  (simulated via facts); the crash fallback.
- Performance: `pleamar --report mooi-surface` per layer against §3's budget; screenshots of each stage.

## 13. Phases (each its own plan)

1. **The engine and the touch:** rename and generalise the Sigil into `mooi-surface` (tests green, the bar
   unchanged); the Super binding verified; the Reveal with the Aperture; the Hub; the Pill in the aperture;
   the Music reference Presence (leave, memory, wake on approach, modes ghost · embedded · full); basic
   direct manipulation with undo.
2. Wallsense (fitted, then woven); the widgets import and `mooi-widgets` retired; more sources as Presences;
   Membrane, Ripple and Fold; modes aperture and bloom.
3. Personalities, arrangements, per-workspace memory, relationships, morphs between Presences, clusters.
4. The full Surface Editor, import/export, experimental mode, accessibility polish, docs; the classic Pill
   retired.

## 14. Out of scope here

mooi Pulse (diagnostics), BMO's organism body, desk mode expanded (each its own spec, each able to appear as
Presences later); touch and gestures beyond the pointer and keyboard; multi-monitor beyond keeping
Presences valid on monitor changes.
