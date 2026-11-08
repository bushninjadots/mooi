# The Subsurface: what lies under the wallpaper — design

> Status: design approved in conversation (2026-11-08), awaiting review of this written spec.
> Revises: `2026-11-08-surface-design.md` (Surface). This spec **replaces** its §3 layer 2 (the Reveal overlay),
> §5 (the Reveal and its Hub ring) and §13 (phases); everything else there (the Presence model and memory, §4;
> wallpaper awareness, §7; shaping, §8; the bar and the Sigil, §9; failure, §10; accessibility, §11) stands
> unless this spec says otherwise.
> Builds on: Surface phase 1 (D208, a219569) — its stages, Presence memory, `surface.json`, edit with undo and
> the Aperture shader are kept; its radial Hub and its overlay above every window are removed.

## 1. What the owner asked for

After trying phase 1's description, the owner corrected the idea (2026-11-08):

- "I didn't mean for it to work through windows. It's supposed to do it to the **wallpaper**, and **underneath
  the wallpaper** is the widget things and components, hubs and all. It's not like a dial command thing — it's
  like the wallpaper, and an effect rips open the wallpaper, and you move the mouse around, or bigger
  sections, or just over a component or widget."
- "Within this whole concept think outside the box … like if windows are stacked over it, you can peer behind
  the front window to the one behind."
- "We won't only have tear — there should be other effects too, and shaders as well."
- The overview "can be a fullscreen upgraded version of our control Nexus; we can customise it and have it
  however we want."
- "Things pushing up from the wallpaper, like a notification or music or whatever — even a visualiser: an
  option to merge it seamlessly and thoughtfully, meshing into the wallpaper, or completely above like a
  normal widget, or having an effect on the wallpaper."
- Burying windows: "yes, that's all great".

Decisions made with the owner:
- **Hold Super, roam, click to use.** Letting go of Super heals the opening. Dragging a thing out of the
  opening leaves it on the wallpaper as a Presence.
- **Size: automatic plus scroll.** A small opening at the pointer; it snaps to a thing's shape when over one;
  the scroll wheel widens it into a section, and all the way into the Overview.
- **Buried: everything** — the desktop widgets, hubs, components and BMO.
- **Architecture A, the shared opening** (§3).
- **All the extras are in scope** (the Overview, push up from below, peering behind windows, burying windows,
  more effects), delivered in phases (§12).

## 2. The idea in one line

The wallpaper is a skin. Under it is the **subsurface**, where mooi's things live, each in its own place.
Holding Super **opens** the skin where the pointer is, and the opening always shows **the next layer down**:
over the wallpaper, the subsurface; over a window, the window stacked behind it.

## 3. Architecture: the shared opening

`mooi-surface` owns the **opening** — where it is, its hole shape, its size, what it has snapped to, which
effect draws it — and tells every program under the wallpaper about it. Each of those programs (the
**citizens**) draws its content, and has its zones, **only inside the hole**. Pleamar hands the compositor
only the zones as the input region, so the empty rest of every surface lets the click through
(Pleamar docs 02, "Input region").

This is the pattern the frame chassis already uses (D152): one program owns a shape, the content programs
clip to the identical formula fed by the same numbers.

**The hole shape** is deliberately simple and the same for every effect: a rounded box
`(ox, oy, ow, oh, corner)` plus an openness `k` (0 closed … 1 open). Citizens clip to it. The **effect** draws
its own edge (torn paper, a lit lens rim, a membrane, a fold) over the seam, wider than the seam, so the
simple clip never shows.

**Layers, bottom to top**

| layer | who | level | mapped |
|---|---|---|---|
| the wallpaper | `mooi-desk` (unchanged; pictures and videos) | background | always |
| the subsurface: hubs, components, buried windows | `mooi-surface`, surface `under` | bottom | only while open |
| the subsurface: widgets | `mooi-widgets` (taught to clip, §6) | bottom | as today; content hidden unless open or left as a Presence |
| BMO's home | BMO (taught to clip) | bottom | as today |
| the edge of the opening | `mooi-surface`, surface `edge` | bottom, restacked above the citizens | only while open |
| Presences left on the wallpaper | `mooi-surface`, surface `desk` (phase 1's) | bottom | while any exist |
| windows | Hyprland | — | — |
| peering patch (§8) | `mooi-surface`, surface `peer` | overlay | only while Super is held over a window with one behind it |
| the bar, islands, frame | unchanged | top | — |

The edge must sit above the citizens. The bottom-level order is kept with the existing restack mechanism
(`widgets_restack`): `mooi-surface` maps `edge` after the citizens, and re-maps it if a citizen restarts.

**The opening facts** (`mooi-surface` → citizens), sent as one packed emit on change, and re-sent when a
citizen asks (`want`), like the chassis geometry (D153):
`op_k` (openness), `op_x, op_y, op_w, op_h, op_r` (the hole), `op_full` (the Overview is open),
`op_snap` (the id of the thing snapped to, or 0). Payloads are packed under 2^24 (Pleamar numbers are
float32, D124).

**The map** (`surface.json`, extended): every citizen's **place** on the subsurface — id, kind, box (as a
fraction of the screen plus an anchor, as Presences already are), monitor. `mooi-surface` uses the boxes to
snap; the citizens use them to lay themselves out. A thing with no place gets one from the default layout
(§5), which the owner can move (§9).

## 4. The gesture

1. **Hold Super** for the delay (default 250 ms, `surface.delay`) with nothing else pressed: a small opening
   (~90 px) appears under the pointer and **follows it** on a spring, a little behind.
   - A tap keeps today's Super tap.
   - Phase 1's safeguard stays: Hyprland sends no Super release after a Super shortcut, so the close events of
     `lib/surface/reveal` (focus change, a new window, a workspace change, a timeout) still heal a stray opening.
     Until the opening is snapped or clicked, it is faint (the first stage), so a slow Super+key shortcut does
     no harm.
2. **Over a thing** (its box within ~40 px of the pointer): the opening **snaps** to that thing's box plus a
   margin, morphing on springs, and the thing wakes (it may animate in, §6).
3. **Scroll** while holding: up widens the opening in steps (thing → section ~40 % of the screen → the whole
   wallpaper = **the Overview**, §7); down narrows it again. Scrolling while snapped widens around that thing.
4. **Click while holding**: the click goes to the thing (it is a real zone of a real program).
5. **Drag a thing out past the edge** and drop it: it becomes a **Presence** — left on the wallpaper, visible
   without Super, remembered (phase 1's memory and edit stay). Dragging a Presence back into an opening buries
   it again.
6. **Let go of Super**: the opening **heals** — the effect plays its close (Tear: the seam knits shut), and the
   citizens hide with it. Exception: the Overview stays open until Esc, a click on empty wallpaper, or Super
   tapped again.
7. **Over a window** instead of the wallpaper: §8 (peering).

Keyboard path (accessibility): while Super is held, Tab / Shift+Tab walk the things on screen and snap to
each, Enter clicks, PageUp/PageDown widen and narrow, Esc heals. Reduced motion: the opening appears and heals
at once, without a follow lag.

Pointer over the bar or the frame: no opening; the bar answers as today.

## 5. What lives below

**Hubs — places, not menus** (drawn by `mooi-surface` in `under`):
- **Apps:** a field of app marks (from Pleamar's `apps` service), the most used largest; a click launches.
  Typing while it is snapped filters it.
- **Music:** the player for what is playing (art, title, transport, seek), the visualiser inside it
  (visualisers only inside music things, by the standing rule).
- **Wallpapers:** a strip of recent wallpapers from `walls-index.json`; a click wears one (`mooi wall apply`).
- **Settings:** the Settings sections as marks; a click opens `mooi-settings` at that page.
- **Notifications:** the recent notifications, newest first, with their actions; clear all.

**Components — small controls** (drawn by `mooi-surface`): Wi-Fi, Bluetooth, volume, brightness, battery,
power (lock, sleep, log out, restart, shut down; the last three confirm by a second press).

**Widgets:** every widget `mooi-widgets` shows today, at the same place, now under the wallpaper (§6).

**BMO:** a home on the subsurface where he sits when not elsewhere; opening onto him wakes him; a click talks
to him as today.

**Buried windows** (phase 4, §8): live tiles where they were buried.

**The default layout**, for anything without a place: hubs along a gentle arc in the middle third, components
in a tight row near the bottom-right, BMO bottom-left, widgets where they already are. Fitted to the
wallpaper's calm areas once `wall-sense.json` exists (Surface §7).

The phase 1 radial Hub (a ring of group words and a second ring of sources around the pointer) and the
`reveal` surface at level `overlay` are **removed**.

## 6. Citizens: hiding below, coming up

Each citizen gets one small library, `lib/surface/citizen.luau` (pure, unit-tested), and one scene fragment
generated into it, so every citizen behaves the same:

- It **listens** for the opening facts and keeps `op_*` facts of its own.
- Its content is drawn inside `group { clip box { from: op_x, op_y; size: op_w, op_h; corner: op_r } … }`,
  shown only while `op_k > 0` — or always, for the things that are Presences.
- Its zones exist only inside the hole (a zone's `show:` tests its box against the hole), so a hidden widget
  is never clickable.
- On start it asks `mooi-surface` for the opening (`want`), and **reports its things' boxes** (id, box) for
  snapping. A citizen that ends leaves its boxes behind for 5 s, then they are dropped.
- **Coming up:** when the opening snaps to a thing, the thing rises (a short scale and fade from 96 % with a
  depth shadow) — springs only, never a long tween (D152: a long tween keeps a scene painting).

**When nothing is open** a citizen draws nothing, and its surfaces are not repainted (`rate: …, 20 while calm`;
hidden groups are skipped whole by Pleamar). Idle cost: zero over today.

## 7. The Overview (phase 2)

Scrolled all the way open, the whole wallpaper peels back: the full subsurface as one canvas — the
**full-screen successor to the Nexus**.
- Every thing at its place, all awake; the wallpaper pulled back to a thin lit margin round the screen.
- **Arranged however the owner likes**, right there: drag to move, edges resize, the shape handle and
  inspector of Surface §8; snapping to a grid or to the wallpaper's lines; undo.
- The Nexus's deck and two-row canvas cards move here as citizens; the old Nexus retires once the Overview
  covers it (its own decision then, not here).
- Closed by Esc, a click on the margin, or Super tapped.

## 8. Peering behind and burying (phase 4)

**Peering.** Super held with the pointer over a window: if another window lies under the pointer behind it
(Hyprland's stacking, from `hyprctl clients`: floating over tiled, the focused over the rest, a fullscreen
window over its workspace), a patch opens in the front window showing **the window behind**, live, from
Pleamar's `thumbnails.live` service, drawn in the `peer` surface (level overlay) with the current effect's
edge. Scroll widens the patch. If nothing is behind, nothing opens: an opening never cuts through to the
desktop (the owner's correction). Risk: Hyprland may not render a fully covered window, so its picture can be
its last frame (the service then marks it stale); the plan's first task verifies it on this desk.

**Burying a window.**
- **By drag:** while an opening is open, a window dragged (Super + left drag, Hyprland's move) and dropped
  with the pointer inside the opening is buried. Risk: the plan's first task checks that Hyprland's window
  move and Surface's opening coexist; if not, only the key ships.
- **By key:** `Super+B` (a setting) buries the focused window at the pointer.
- Burying moves the window to the hidden workspace `special:mooi-buried` and leaves a **live tile** (its
  thumbnail, its app mark, its title) at the drop spot on the subsurface, remembered in `surface.json`.
- Opening onto the tile and clicking it brings the window back to the current workspace, focused, and the
  tile is gone. A buried window that closes takes its tile with it.

## 9. Push up from below (phase 3)

Every citizen and Presence chooses how it meets the wallpaper (`meet`, per thing, in its memory):
- **woven** — it lives in the picture: a song change, a notification or an event makes a soft **bulge** in the
  wallpaper over the thing's place (a displacement shader on the wallpaper patch, a few hundred ms), and its
  words press up through the picture, tinted from the pixels beneath, then settle back. Notifications ask for
  this by default: no popups needed for the quiet ones.
- **above** — an ordinary widget on top of the wallpaper (today's widgets).
- **moves the wallpaper** — the thing drives an effect on the picture around it: a visualiser makes the
  wallpaper ripple and breathe with the music; the clock a slow light sweep at the hour. Always local, a patch
  round the thing, never the whole screen (performance rule).

Woven words stay straight and readable (Pleamar cannot set text on a curve); high-contrast mode puts a solid
plate under them.

## 10. Effects (Tear and Aperture in this spec's phase 1; more in phase 5)

An **effect** = an open/close motion on `k` + an edge drawing + a shader over the wallpaper patch around the
hole (the wallpaper image `mooi-surface` draws itself; Surface §2's spike: ~0.1 ms for a 420 px patch).
- **Tear** (new default): the wallpaper rips along a jagged, slightly curled edge (a seeded noise outline drawn
  as straight steps, never `curve`, D128), with the paper's underside lighter at the lip and a depth shadow
  inside; heals as a seam knitting shut.
- **Aperture** (phase 1's, kept): a lens hole with a lit rim.
- Phase 5: **Membrane**, **Ripple**, **Fold**, **Dissolve**, **Glass**, the owner's own shaders (a
  `shaders/surface/` folder, each declaring its parameters), and effect chains.
- Settings: the effect, intensity, edge width, colour influence, open/close speed.

Video wallpapers: the shader warps a still of the video (Pleamar cannot read the video's frames); the edge
covers the join. Accepted, and stated in Settings.

## 11. Performance, failure, testing

**Performance:** nothing mapped or repainting while no opening is open; the edge and its shader only in a patch
round the hole; each layer < 1 ms compose + paint at 60 fps (`pleamar --report`); nothing in the frame's band.
The Overview may paint the whole screen while it is open.

**Failure:**
- `mooi-surface` ends → respawned (five quick ends and it stays down). While it is down no opening exists, so
  every citizen hides its below-things and keeps its Presences. The desktop stays usable.
- A citizen ends → its boxes drop after 5 s; the others are untouched.
- A citizen never answers → the opening still opens and shows the others.
- `surface.json` broken → as Surface §10 (the broken entry dropped and reported, a backup per save).

**Testing:**
- Unit: `lib/surface/citizen` (clip, zone gating, packing), the opening's snap/scroll/heal logic in
  `lib/surface/reveal`, the default layout, the map's validation and migration from phase 1's `surface.json`.
- Every scene compiles; generated scenes are checked against their generators in CI.
- Live (`tests/surface.sh`, via `pleamar --say`, never the real pointer): open, follow, snap to a widget, widen,
  click through to a widget's zone, drag out to a Presence, heal; a citizen restart; `mooi-surface` killed →
  citizens hidden.
- Performance: `pleamar --report` per layer against the budget; screenshots of each stage.
- The real Super key, with the owner (phase 1's open item C1).

## 12. Phases (one plan each)

1. **The opening.** The shared opening and its facts; Tear and Aperture; follow, snap, scroll to a section,
   heal; the hubs and components in `under`; `mooi-widgets` and BMO as citizens; click to use; drag out to a
   Presence and back; the keyboard path. The radial Hub and the overlay `reveal` surface removed.
2. **The Overview.** Full open, arranged in place, the Nexus's cards as citizens.
3. **Push up from below.** `meet`: woven, above, moves the wallpaper; notifications woven by default.
4. **Peering and burying.** The two checks first (covered windows' pictures; Hyprland's move vs the opening).
5. **More effects.** Membrane, Ripple, Fold, Dissolve, Glass, owner shaders, chains.

Each phase ships behind `surface.on` (off until the owner has tried it with the real Super key).

## 13. Out of scope here

Surface's later phases that this spec does not change (personalities, arrangements and snapshots,
relationships, the full Surface Editor); mooi Pulse; BMO's organism body; touch and gestures beyond the
pointer, the wheel and the keyboard.
