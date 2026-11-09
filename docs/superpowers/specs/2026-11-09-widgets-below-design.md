# The widgets below: one system under the wallpaper — design

> Status: approved in conversation (2026-11-09). The owner approved the design, then the spec and its plan in
> advance ("choose all you recommended options and build").
> Revises: `2026-11-08-subsurface-design.md` §5 (what lives below) and §9's Presences. The opening (§3–§4), the
> effects (§10), the Overview's idea (§7) and the later phases (§8, §9, §9a) stand.
> Builds on: D209–D214 (the opening, its hubs and components), D137–D141 (the widgets).

## 1. What the owner asked for

"The widgets we have already should be the ones there, plus new designs to facilitate what we're trying to
build — it's in the spec." Then, of three ways to make one system out of the subsurface's two, the owner chose
**widgets only**: everything under the wallpaper is a real mooi widget, with its looks, the Wardrobe and edit
mode; the hubs and components mooi-surface drew itself (D209–D214) go.

## 2. The idea in one line

Under the wallpaper live mooi's widgets. The opening shows them; dragging one out keeps it above the wallpaper
(that is what a Presence is now); the Overview is the widgets' own edit mode on the whole canvas.

## 3. What lives below

**The existing kinds take the hubs' parts.**
- Music → **Now Playing** (its three layouts) and a **Visualiser** beside it.
- Apps → **Launch**, with a new third layout, **grid**: the twelve most launched apps (counts kept in
  `widgets.json`, beside the list), filtered by what is typed while the Overview is open (§6). Its shelf and
  column layouts keep the chosen apps, as today.
- Clock, Calendar, Weather and every other kind: as today, under the wallpaper (D209's citizens).

**Four new kinds** — each a *lane* (one of it, drawn by its own group, like Weather, D141), in the widgets'
Ferrolume vocabulary (`wg.Ground` plate, `ink`/`acc` from the five looks, `u` scale, Share Tech Mono labels,
Exo 2 words), each with its options in the editor like every kind.

| kind | layouts (min · default) | what it shows | what a press does |
|---|---|---|---|
| `notices` | `stack` 280×200 · 360×260 | the newest four notices from the bar's feed (`nexus-feed.json`): app, title, how long ago; the first action as a chip; a cross; CLEAR; "Nothing new" | a row: the notice's own default, else the Nexus; the chip: that action; the cross: dismiss; CLEAR: all (the bar's signals: `note_act`, `note_clear`) |
| `wallpapers` | `strip` 300×110 · 420×140 | the six newest pictures of the picker's index (`walls-index.json`) | wears it (`mooi wall apply`) |
| `settings` | `pages` 260×130 · 320×170 | eight marks: Theme & colour, Bar & Frame, Wallpapers, Widgets, Sound, Power, BMO, The Subsurface | opens the settings window at that page (`open_settings_at`, D214) |
| `controls` | `row` 420×72 · 452×80; `column` 72×420 · 80×452 | Wi-Fi, Bluetooth, volume, brightness, battery, power — glyph, value, a bar for the three levels | Wi-Fi / Bluetooth: the radio; volume / brightness: the wheel ±5 %; power: its five ways out, the last three asking twice (D214) |

Options: `notices` rows 3–6 (4); `controls` which of the six show (all); every kind's `plate`, `adapt`, `behind`.

**The default set, placed once.** The first time Surface is on, mooi-widgets places, under the wallpaper, the
default set: Now Playing (sleeve), Visualiser, Launch (grid), Clock (digital), Calendar, Weather, Notices,
Wallpapers, Settings and Controls (row), each kind only if the owner has none of it yet, laid out by the
chosen arrangement (`surface.layout`: arc, row, grid, calm — lib/surface/below's maths, generalised to any
list of boxes), every one wholly on the screen and apart. `widgets.json` then carries `below_seeded = true`,
and it never happens again on its own. The widget limit rises from 12 to 16 so the set fits beside the
owner's own.

## 4. What leaves mooi-surface

mooi-surface keeps: the opening (the hole, faint, away, follow, snap, section, full, heal), the eight effects,
the ground (the wallpaper under it, its tint, grid and glow), the Overview's canvas and its Close, the keyboard
walk (over the widgets' boxes), BMO's reported box, the repaint veil, the Sigil.

Removed: the five hubs, the six components, the power row, typing, seek, place editing (`sf_edit`, `sf_reset`,
`sf_undo`, the handles, the eight-pixel snap of places), `places` and `usage` in `surface.json`, the D214
Settings/Notices/Music code paths in its logic and scene, and the Presence layer (`desk`, its eight slots,
`pp_*`, `ed_*`). Settings rows that only drove them go: the components' side, Edit places, Reset places,
power confirm (power confirm moves to the Controls widget's options).

## 5. Presences become widgets kept above

A Presence was a thing left on the wallpaper. A widget kept above (`above = true`, D209) is exactly that, with
every look and edit. So: dragging a widget out of the opening keeps it above (as today); dragging one kept
above back into an opening buries it (as today).

**The migration, once.** On its first start after this change, mooi-surface reads `surface.json`'s Presences
and asks mooi-widgets to add each as a widget kept above at the same place (centre kept): music → Now Playing
(sleeve), clock → Clock, calendar → Calendar, weather → Weather, notifications → Notices, volume / network /
bluetooth / battery → Controls, resources → System; the rest are dropped with a line in the log. Two of the
same single kind become one. `surface.json` is then rewritten without `presences` and `places` (its backup
kept, as every save). A file already migrated is left alone.

## 6. The Overview is edit mode

Opening the Overview (`op_mode` 4) puts mooi-widgets into edit mode (`wg_edit 1`): drag, resize, the inspector,
multi-select, align and undo — all of which exist (D138). Healing the Overview leaves it (`wg_edit 0`). The
canvas stays mooi-surface's; the widgets in edit mode sit above it. While the Overview is open, letters typed
filter the Launch grid (`op_type` is sent on to mooi-widgets), Esc clears the filter before it heals.

## 7. Settings → The Subsurface

Kept: on and hold time; the eight effects and their look; the wallpaper under it; the light; the Overview's
margin; the widgets' style; Keep above / Put below; BMO lives below. "Where things live" becomes the
arrangement (arc, row, grid, calm) and a **Re-arrange** button, which lays every widget below out again by it
(through edit mode's undo: one undo puts them back). Removed rows: as §4.

## 8. Failure

- mooi-widgets down: the opening opens on the wallpaper alone (as a citizen ending, D209); nothing seeded or
  migrated is lost (the files hold it).
- A migration that cannot reach mooi-widgets is retried at mooi-surface's next start: `surface.json` keeps its
  Presences until mooi-widgets says the widgets were added (`wg_migrated`).
- `widgets.json` full (16): seeding and migration add what fits and log the rest.

## 9. Testing

- Unit: the four kinds' layouts, options and lane facts; the Launch grid's ranking and filter; the default set
  (only missing kinds, on screen, apart, every arrangement, once); the migration map; mooi-surface no longer
  declaring the removed names.
- Every scene compiles; generated blocks match their generators (gate).
- Rendered: each new kind in each look through the logic-free preview (a copy of the scene at the overlay
  level, driven by `--say`), the default set under an opening, and the Overview in edit mode.
- Live (`tests/surface.sh`): adjusted for widgets in place of hubs; run with the owner.

## 10. Out of scope

The later phases (the Nexus's cards, push up, peering and burying, the owner's shaders); the Overview above the
windows (it is the wallpaper's, under them, as before).
