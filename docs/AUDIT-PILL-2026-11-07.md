# The Pill — audit, 2026-11-07

Read against the running desktop (mooi refreshed from `main` at c2ce9e3, Pleamar 0.7.11): every board
room, both editor tabs, the reveal and the rest face were opened by scripted emits and photographed, and
the code that draws and drives each was read. Decision for the fixes: D193.

## 1. Bugs found — fixed in D193

| # | Where | What happened | Cause | Fix |
| --- | --- | --- | --- | --- |
| B1 | Stash, Find rooms | The Wallpaper strip (four wallpapers and "1–4 of 3192") was drawn over both rooms; in Find it covered the search field | `ui/pillboard.plm`: the Wallpaper group's `show: pk_room > 12.5` had no upper bound | bounded to room 13 |
| B2 | Connections | "No network in reach · the radio may be off" while connected to a network nmcli lists with 74 % | `nets_publish` asked the service once (`sys.ask`), which answers the radio's state without the scan list | the list now comes from the connections shelf's watch (`islands.luau` → `ctx.networks`) |
| B3 | Visualiser | A grey band 4 px tall across the room's foot, silent or not | the spectrum's path started at y 156 with its area closed at 160 | starts at the foot (160): silent, it draws nothing |
| B4 | Connections | The Bluetooth button sat under its name, over the rule and the "networks in reach" label | placed at y 26 in a 40 px header | beside its name |

## 2. Bugs found — still open

- **The workspace viewer (Now, with `desk_workspaces`)** shows three empty frames: no miniatures appeared
  on this run. Its thumbnails depend on the `thumbnails` service lending captures; not traced further here.
- **The board can be closed by an unrelated press or focus change** at the moment it opens (seen once:
  two calls, `open` back to `none` within a second). It opened reliably when called again. Not reproduced
  in isolation.
- **A press on the Pill opens the Control Nexus, not the board, while the face is Nexus.** Intended (D169),
  but it is invisible: nothing on the capsule says its press goes elsewhere.

## 3. What it looks like (visual)

Seen in all sixteen rooms:

- **The pads dominate every room.** Eight 66 × 48 pads, their numbered key hints (11–18) and a circuit of
  traces take the lower ~45 % of the board in *every* room. The room's own content gets 160 px of a 312 px
  card. The pads are the same in every room, so most of the card never changes.
- **Three visual languages in one card**: chamfered Ferrolume buttons (`PkBtn`), the island kit's
  segmented meters (`Level`, which read as a loading bar rather than a slider), and the phosphor circuit
  traces with vias. Plus rounded tiles in Diagnostics and Weather. None of them is wrong alone; together
  they read as parts from four kits.
- **Plate inside plate inside plate**: the board's plate, the core's well, and each button's own chamfer.
- **Dead space where information should be.** Display: one meter and three buttons in a 608 × 150 well,
  the middle empty. Power: a big "100%", a battery gauge, two buttons, the right half empty. Sound: the
  lower right empty. Workspaces: four tiles left-aligned, half the width unused. Signals: one row and a
  void. The rooms lead with controls and leave out the information that would fill them (Power: no time
  remaining, no history; Sound: no per-app volume).
- **Typography is too small and too uniform**: 9–10 px Share Tech Mono in capitals for labels, buttons,
  hints and headers alike. The only hierarchy is the occasional 40 px number (Power, Weather).
- **One colour for everything**: the theme's lavender for accents, selected buttons, meters, traces and
  icons. Nothing says "music" or "battery" by colour; a warning only appears as the ember on a gauge.
- **Header links are tiny** ("◂ NOW", "✎ EDIT" at 10 px in the top right corner).
- **The reveal** (D191) reads well as a status strip, but its twelve items have one weight: nothing tells
  the eye where to land.
- **The editor** is legible now (D188) but is a form: "EDIT THE PILL" is near-invisible grey on grey, and
  the module grid is 32 equal chips.

## 4. How it behaves (motion, reactions, opening, closing)

- **Opening**: the body springs from the capsule (D188, `m.morph` 26/6, ~285 ms to size, ~10 % over).
  The content does not travel with it — it fades in place — so the growth and the contents read as two
  things.
- **Changing rooms**: the body re-springs to the new size, but most rooms are 150–160 tall, so the change
  is a jump of content inside a box that barely moves. No direction: Calendar → Sound looks the same as
  Sound → Calendar.
- **Closing**: content leaves first, then the body folds (D189) — clean, but the last frame of every fold
  drops the capsule's plate for one frame (the frame/bar surface hand-over, D189 limits).
- **Reactions**: the capsule warms to the pointer (D173), flashes its edge on a change (D188), and the
  spectrum rises with the music (D191). The board has no reaction to anything happening while it is open
  (a notice arriving while Sound shows changes nothing on the board).

## 5. How it works (functionality and logic)

- **Three entry points, three meanings**: a left press (the board — or the Nexus with that face), Super
  twice (the board, never the Nexus), hover (the reveal). The right press is a fourth (the owner's choice,
  D179). Each is reasonable; together they are hard to predict.
- **The pads duplicate the rooms**: a pad mostly opens a room — which the wheel over the board, the reveal's
  items and the header also do.
- **The Now room is two different things**: the clock/desk, or "Now playing" when music plays (`pk_music`),
  with the HALO/RIVER button floating in its corner.

## 6. Settings (34 keys under `pill.*`)

`sides multi face pads viz shape views detail rest autohide hide warmth ping desk_clock desk_playing
desk_diagnostics desk_calendar desk_surface desk_border desk_workspaces desk_clock_size desk_playing_size
desk_diagnostics_size desk_calendar_size desk_form desk_tint desk_glow right board_tint board_edge moons
peek off order`

Redundant or overlapping:

- `autohide` is superseded by `hide` (D172) and only read for migration — it should be migrated away and dropped.
- `desk_clock`, `desk_playing`, `desk_diagnostics`, `desk_calendar` are booleans whose job `desk_*_size`
  (`off · small · wide`, D188) already does.
- `face`, `views`, `detail` and `rest` together describe "what the capsule shows": one rest face, a list
  the wheel turns through, how much text, and how long a turned view lasts.
- `shape` (attached · floating · dot) and `hide` (stay · tuck · vanish) both decide how it rests;
  `dot` is a shape that hides by being one.
- `board_tint`, `board_edge`, `desk_surface`, `desk_border`, `desk_form`, `desk_tint`, `desk_glow` are seven
  appearance switches for two surfaces (the board and the desk card on it).
- `multi` (moons · split · nodes), `moons` and `sides` describe the same thing: what else shows beside it.
- The face and the board's music are chosen in the editor; the rest of these on the Settings page.

## 7. Performance

Not re-measured in this audit. D188's figures stand (bar 7.9 %, frame 9.3 % of a core with music and
swell on). The spectrum (D191) adds 32 boxes redrawn with the bands while music plays and the capsule
rests; nothing while silent.

## 8. Recommendations (for the redesign, not done here)

1. **The room is the card.** Drop the always-on pad row; pads become one room ("Shortcuts") or a strip
   that appears on hover. Each room gets the whole card and its own height.
2. **One component kit for every room**: a metric (big number + label + trend), a slider (continuous, not
   segmented), a toggle row, a list row, a tile. Ferrolume's chamfer on the card, not on every button.
3. **Information first**: each room leads with what is true now (Power: time left, rate; Sound: what is
   playing where, per-app levels; Workspaces: miniatures), controls second.
4. **A colour per kind** derived from the theme (music, system, network, power, time), used sparingly.
5. **Content travels with the body**: contents scale/slide from the capsule on open and back on close;
   room changes slide in the wheel's direction.
6. **Settings collapse** to: Rest face (one picker with pictures), When idle (one choice that merges
   shape + hide), Beside it (one choice for multi/moons/sides), Look (one preset for board + desk),
   Desk tiles (one list), Peek, Flash. `autohide` and the four `desk_*` booleans are migrated and removed.
7. **Switchable layouts**: whole presets (arrangement + kit + colour use + motion), picked from pictures.
