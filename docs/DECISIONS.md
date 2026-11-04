# Decisions

Each one is reversible; the "to change back" line says how.

## D1 · 2026-10-14 · Name: mooi
Renamed from "Tidal Shell". The scene is `mooi.plm` (socket `mooi.sock`), settings live in `~/.local/share/pleamar/mooi/`, and the environment variables are `MOOI_*`.

## D2 · 2026-10-14 · ArchEclipse stays the login shell
mooi never starts at login. Beside mode is the default; takeover is explicit and ends at logout. See SWITCHING.md.
*To change:* add `exec` of `bin/mooi start` (or `takeover`) to `exec.lua`. Not planned until mooi can replace ArchEclipse.

## D3 · 2026-10-14 · Keys: Super+Alt+Space / Super+Alt+Shift+Space
The brief's Super+Space is your float toggle and was kept. *To change:* `bind.lua`, lines under `--- mooi`.

## D4 · 2026-10-14 · Pleamar 0.4.6 for everything
The shared binary was upgraded. 0.4.x paints only what changed (fixes limitation P14) and falls back to ext-workspace when Hyprland's socket is missing. *To change back:* `cp ~/.local/bin/pleamar-0.3.7 ~/.local/bin/pleamar`.

## D5 · 2026-10-14 · Notifications: ArchEclipse keeps them, for now
- **Beside mode:** mooi does **not** declare Pleamar's `notifications` service. ArchEclipse stays the one `org.freedesktop.Notifications` server; nothing is taken from it.
- **Takeover mode (Phase 6):** mooi will declare it only when `MOOI_MODE=takeover`, when ArchEclipse's bar is stopped and the name is free. Pleamar queues behind a server that does not give the name up, so even a mistake would not steal it, but this is to be verified in Phase 6 before relying on it.
- **Why:** two notification servers cannot coexist, and you want ArchEclipse untouched while mooi is tested.
- **To change back / other options:** (a) mooi takes notifications in beside mode too, with a switch as Marea does. (b) mooi shows notifications by reading ArchEclipse's (needs an export from Quickshell). (c) Keep D5. Revisit at Phase 6.

## D6 · 2026-10-14 · One island slot
At most one island is open (`open: none | window | system`). Opening another hands the slot over. Escape acts on the topmost level: a pending confirmation, then an expanded state, then the island. *Alternative considered:* several islands at once with a z-stack. Rejected because it needs a focus model the brief does not ask for yet.

## D7 · 2026-10-14 · Shown values come back from the system
Sliders and window state display what the services or Hyprland report, never the requested value. Requests are coalesced to one every 40 ms (latest wins). Brightness from a slider never goes below 1 %.

## D8 · 2026-10-15 · The keyboard belongs to the scene, and is asked for by its first surface
`keyboard:` is read once per scene: pleamar takes the mode from `scene.surface().keyboard`
(the first surface) and a single `while` condition (the last surface that declares one). With
each island declaring its own `keyboard: exclusive while open == <name>`, **no** island ever
had the keyboard: typing went to the window below and Escape did nothing. So the Spine — the
scene's first surface — carries the scene's only clause, and the islands declare none; each
sheet takes it while it is open. The clause is `exclusive while (open != none or nav_open or
mark_open) and not (open == command and cmode == actions)`.
*Consequence:* giving a window the keyboard (membrane ↵, its Focus satellite, an Atlas tile)
cannot be done while the island holds it, so such an action gives the slot up first, waits the
frame that releases the keyboard, and brings the island back with the failure if it did not
happen. An `on_demand` keyboard would not work: its loan outlives the island by 300 ms.
*The one gap:* while the command membrane is in its window-actions mode the arrows and Enter
belong to the actions, but the focused `input` keeps eating them, and the scene's `blur` effect
does not take the writing cursor back (measured; MECHANISM.md §7). Because the condition above
is the scene's entire claim, making it false for exactly that mode is what frees the field: the
scene then holds no keyboard, the input stops swallowing the keys, and the rules read them.
Narrowing it on the island instead would replace the scene's condition everywhere — measured too,
and the reason an Escape in the Atlas stopped reaching it — which is why the gap is expressed in
the one place it is.
*To change:* if upstream makes `keyboard:` per surface, each island can declare its own again
(AUDIT.md §4 has the experiment and the source lines).

## D9 · 2026-10-15 · The Atlas is a wall of Hyprland's windows; `thumbnails` lends the pictures
The tiles are Hyprland's clients (`hyprctl -j clients`): each brings the address the actions
are verified against and the workspace it sits on, so every tile can be focused. The
`thumbnails` service is used for the pictures only — its ids are the compositor's own
(`18000015`), not addresses — matched to a window by app and title, one window each; a window
without a picture is still a tile, named only. Pictures are asked for only while the Atlas is
up (`thumbnails.want("all")`; `thumbnails.want()` on close).
*Alternative considered:* tiles built from the `thumbnails` list, joined to Hyprland by
address. Rejected: the ids do not match, so a tile could not be focused at all.
*Consequence:* the board is rebuilt on every report while the Atlas is up, so a window opening
or closing moves the tiles under the selection (an index); the board is left as it is while
the Atlas leaves. The bounded 1–16 workspace map stays as state (`spaces`).

## D10 · 2026-10-15 · The Atlas moves a window in place, and previews are a setting you can promise off
`m` gives the strip under the board the room it needs (`bh`, a spring) and turns it into the
workspace picker, drawn from the same `spaces` map; `←→` or a click chooses a slot, ↵ moves
the selected tile's window there through the window island's verified action (`follow = false`,
so the user stays) and **the Atlas stays open**: a move is not a choice, so it should not throw
the board away, and the Spine pulses where it went. Escape leaves the strip, then closes the
Atlas (the two rules are separate, because every rule's `while` is read before any of their
effects are).
*Not digits:* a scene key cannot be a digit (`key 1` is a load error: the keyboard names are
`Escape`, `a`, `Ctrl+k`…), so the picker is walked with ←→ or clicked; a number strip the user
must walk is what the window island already does.
*Previews:* `p` flips `atlas.previews`. Off is a promise that nothing is captured, not a
blinding of the tiles: `thumbnails.want()` is called at once and the frames are given back, and
no picture is matched into a tile while it holds. It is a setting, so the choice survives a
restart — and **safe mode never writes the settings file**, so a test run cannot become the
user's config (checked: `tests/config-recovery.sh` compares the file before and after).
*Alternative considered:* a separate "privacy mode" fact that is not a setting. Rejected: a
privacy switch that forgets itself at the next restart is not one.

## D11 · 2026-10-15 · The theme: fixed by default, wallpaper when asked, one Matugen, no surprises
**`theme.source` is `fixed` by default.** The brief's palette is the shell's identity; a
wallpaper-derived palette is an opt-in, not something that happens to you because you changed
your desktop picture. With `source = wallpaper`, Matugen's dark scheme fills the fourteen
semantic tokens (the mapping is written out in `lib/theme.luau`, one Material role per token).
**Matugen runs with mooi's own config** (`theme/matugen.toml.in` + `theme/palette.json.hbs`,
paths filled in by `bin/mooi theme-sync`), which writes exactly one file — the palette mooi
reads — so the user's `~/.config/matugen/config.toml` keeps owning every other program's
colours and there is still only one palette generator in the session (the brief's rule).
`theme-sync` passes `--source-color-index 0`, the same flag the user's `matugen-theme.sh`
passes, so mooi and ArchEclipse take their colours from the same source colour of the same
wallpaper (checked: identical hexes in both files).
*Colour is a fact, and only colour.* Pleamar has no colour facts, so each token is three number
facts handed to `rgb()`; the logic writes all forty-two or none. A theme update therefore cannot
move a surface, change a spring or touch a workspace (checked in `tests/theme.sh`: `settings.json`
byte-identical, other facts unchanged).
*Refused whole, never half.* Completeness and WCAG contrast are checked before anything is
painted, and a theme that fails leaves the last good one on screen with the Spine's dot lit —
"wallpaper changes may update semantic colours" but they may not make the shell unreadable.
*To change:* set `theme.source` back to `fixed`, or override single tokens under
`theme.overrides`. **To make it automatic:** add one line where your wallpaper is set, e.g. a
post-hook in `~/.config/matugen/config.toml` (the user's file — mooi does not edit it):
`post_hook = "bin/mooi theme-sync >/dev/null 2>&1 || true"` (absolute path), or the same line at
the end of `~/.config/hypr/theme/scripts/matugen-theme.sh`. Then mooi recolours itself live,
without a restart, because it watches the palette file.
*Not built:* light schemes, named theme packages, and a Workshop editor for any of it.

## D12 · 2026-10-15 · The Mechanism: the bar is four regions down one rail, and geometry carries state
mooi's bar — the Mechanism — is the always-present rail the whole shell hangs from, in four
regions top to bottom: **identity** (the mark, opening the bar's own menu), **workspace
navigation** (the Atlas key, the wheel's door, then the helix of workspace blocks with the
carriage riding it), **quick access** (search, the focused window) and **status** (the
essentials, the battery key, the clock). It lives in one surface reserved for the rail: what
opens beside it floats over windows, and nothing beside the rail takes a click (pleamar commits
the input region from what is painted — checked on the running desktop).
*The rule:* **geometry carries state, colour only confirms.** A block's shape and turn and the
carriage's travel say what is; colour agrees. `accent.primary` means *what is*, `focus.ring`
means *what the pointer or the keyboard is on*, and nothing else is allowed to be loud. Two
consequences fell out of it: a conditional colour cannot be a `let` (only an arithmetic
`mix(...)` can), and nothing may be placed from a value that has not arrived — so a widget the
machine cannot have (no backlight, no radio) is not drawn, and the widgets above it close the
gap (`have_bri`, `have_bt`), leaving no hole in the column.
*Scale, not a list.* The workspace map (`lib/spaces`) is drawn as fixed-pitch positions, not as
the workspaces that happen to exist, so a position for a workspace the compositor has not made
yet is still there to be chosen; the pitch is a token (`g.slot`), and `g.slots_y` sits the first
position below Region B's keys.
*Preview is not commit.* The wheel and the scale may show a workspace before the compositor
goes there (`nav_sel` vs `active_row`), and no animation ever delays the real operation: `↵`
asks `workspaces.focus` at once, and the readout catches up. An interrupted animation is simply
the next state (MECHANISM.md §3).
*Status is a door, not a control.* Network, Bluetooth, brightness and volume each show what the
services report and each **opens the system surface**, which owns the controls — the bar never
offers a control it cannot honestly drive. Bluetooth is shown and never toggled: there is no
documented write for it, so `bin/mooi` would have to shell out and read the state back, and a
switch that cannot be trusted to reflect is worse than a state that can.
*Not here:* no workspace overview, no Assemblies, no rewrite of the command membrane, no
notification manager, no replacing Hyprland. Appearance and density (placements, size presets,
accent and surface choices) are still unbuilt — the first-run stopping point.
The whole account is `docs/MECHANISM.md`.
*Revised by D13* (the chain slides, and the readings are modules).

## D13 · 2026-10-16 · The bar is rebuilt from the renewed helix design
You handed over a refined version of the helix (`pleamar helix bar/helix-v2-mooi/`, with its own
`gen.py`) and asked for mooi's bar to be recreated as closely as it can be. It checks out with
`pleamar --check` as its own scene, so the port is a translation and not a reinterpretation: the
same proportions, angles and motion numbers — in mooi's tokens rather than the design's literals,
with mooi's islands, wheel, theme and settings behind them.
*The rail is 90 px now* (`reserve: 90`), and the body's right edge is a path sampled at 58 points
that swings with the chain, with the rack along it — the design's machine, not a border. Windows
move right by 18 px and that is the cost, taken knowingly: the design does not fit in 72.
*The chain slides.* The block the compositor is on always comes to a fixed focus slot at
`screen.height · 0.38`, the chain's angle is written relative to that slot
(`helix_twist·d + helix_roll·roll + parity`), and one that is out of reach fades out and stops
taking input. This departs from D12's *fixed pitch, carriage riding it* — deliberately, and it
changes what the bar shows: a window of about seven positions out of ten, moving under a fixed
mark, rather than all ten at once. Everything else D12 promised holds: the ids on the rail are a
contiguous run, exactly one block is the active one, and it is the one at the slot
(`tests/scene.sh` checks all three). **Preview is still not commit**: `pos` and `roll` follow
`active_row` alone, so the wheel cannot crank the chain, and a preview is named on the dial and
marked with `focus.ring` when its block is on the rail.
*Readings turn over instead of opening a surface.* The status column became the design's
**module column**: one frame for nine prisms, and the four readings (volume, brightness,
Bluetooth, network) plus the clock are `Module`s whose press turns them to their next face —
glyph, number, word. That does replace D12's *status is a door*: those five no longer open the
System surface on a press. The doors that remain are the System door (slot 1) — whose own face
carries the battery — and the three Region C doors; the two ways in that do not go through the
rail are `bin/mooi system` and the membrane's `> sys` result. None of them is a read-only widget
pretending to be a control. The wheel over the volume module sets the level
through the same `vol` event the System island uses, which is the one new control in the column.
The whole account is `docs/MECHANISM.md`; what was verified is in `STATUS.md`.

## D14 · 2026-10-16 · The bar is slimmed to the v4 helix
A fourth revision of the design (`mooi-the-mechanism-slim-helix-v4.zip`, the same
`helix-v2-mooi/` sources regenerated by its `gen.py`) keeps v2's rotation and navigation
structure and makes the whole thing narrower and tighter. It was ported the same way: its
numbers into mooi's tokens, mooi's islands, wheel, theme and settings kept.
*The rail is 76 px now* (`reserve: 76`, the machine inside ~74), down from 90 — so windows move
back by 14 px, which is the point of the revision; every other window shift this bar has made is
recorded here so the cost is never a surprise. `g.edge` 68 (was 80) and its swing `g.edge_amp`
5.5 (was 3): the edge is both tighter to the axis and more alive. A new pair of tokens, `g.inner`
6 and `g.inner_amp` 5.5, replaces the `6 − 3·sin` that used to be written by hand in the body and
in both prism components, so the inner rail has one definition.
*The chain is compressed*: `g.tick` 38 (was 47), block height `g.prism_h` 26 (was 32), prism
radius `g.prism_r` 24 (was 28, face 41.5 = r·√3), and the focus slot moves to
`chain_y = screen.height · 0.36`. The module column tightens the same way: `g.mod_pitch` 36 (was
44) and `g.mod_h` 26 (was 32) — a reading is now one 26 px prism per 36 px of rail, and the
touch zone fills the pitch less a 4 px seam (the design's own numbers). The chain's zone
(`g.frame` 3.75 pitches either side of the slot) is the design's own and smaller than the drawn
band, which stays `g.reach` 2.6 + `g.fade` 1.6.
*Turns are a third clock.* The design gives the chain's roll 1 350 ms and a module's turn
1 100 ms, so `m.roll` moves from 1 200 to 1 350 and a new `m.turn` takes the module press: a
module turning and the chain rolling are two different gestures and should not be heard as one.
*What did not change:* the machine itself (the body, the rails, the rack, the arms, the rods, the
bolts, the shrunken faces and the pivoted labels), the sliding chain and the fixed focus mark,
preview-is-not-commit, the module column's nine slots and their order, the wheel, the mark's
menu, the plate, the theme, and everything in Part Five's settings.
*To change back:* the v2 numbers are in D13's commit and in
`pleamar helix bar/`'s earlier revision; the tokens are one block in `shell/theme/tokens.plm`.
The whole account is `docs/MECHANISM.md`; what was verified is in `STATUS.md`.

## D15 · 2026-10-16 · The bar is exposed: the blocks are the bar
A fifth revision of the design (`mooi-the-mechanism-exposed-helix-v5.zip`, the same
`helix-v2-mooi/` sources regenerated by its own `gen.py`) changes the construction rather than
the proportions: **the workspace blocks and their links are the bar**, instead of blocks sitting
inside a dark backing strip.
*What went:* the body — the 58-point filled edge whose right side was the outer rail
(`shell/ui/edge.plm`), the fixed 6 px shaft down the whole screen, the two full-height rails over
the body (`shell/ui/edge_strands.plm`), the rack of teeth that slid along the outer rail (42 of
them, four to a workspace position, each with its lit band), the arms that slung every block to
the two side rails and the bolts where they landed, and the fixed accent bar that marked the
focus slot. The two body parts are **deleted**, not left empty: the design keeps them as no-op
"legacy compatibility" parts because its `gen.py` writes them, whereas mooi has no generator and
no reason to carry a file that draws nothing.
*What took their place:* nothing structural. The rods that tie each vertex of a block to the two
nearest vertices of its neighbour stay, and the shaft through the gap to the next block becomes
one wider link (8 px at `g.rail_x − 4`, drawn at 80 % of the block's own fade) with no collar on
the chain; the module column keeps its short link and gets a smaller collar (12 × 3, was 16 × 4).
So the machine *is* the silhouette: only the prisms, the rods, the links, the mark's frame, the
wheel's rings, two hairlines and the error dot are painted, and the desktop shows through
everything else. The rail's own empty space therefore passes clicks through to the window
underneath — the same promise the surface already made beside the rail, since pleamar commits the
input region from what is actually painted.
*What did not change:* the reserve (`g.spine` 76, so windows still stop at x 90 with their own
14 px margin and return to x 14 when the bar quits), every proportion (chain pitch 38, prism
radius 24, face 41.5, module pitch 36, prism height 26), the three springs (`m.chain` 900,
`m.roll` 1 350, `m.turn` 1 100 ms), the chain's angles and parity, the focus slot at
`screen.height · 0.36` — now marked only by the block that arrives, turned face-on and lit — 
preview-is-not-commit, the module column's nine slots and their order, the wheel, the mark's
menu, the plate, the theme and the settings. The rail tokens `g.edge`, `g.edge_amp`, `g.inner`
and `g.inner_amp` went with the rails; one token replaces them, `g.bar_w` 68 — the width of the
bar's own zone on the rail, which is the chain's scroll area.
*The cost:* the bar no longer reads as a filled strip. A window onto a chain of four or five
blocks now floats over whatever window is under it, and a block's label is legible because the
block's face is filled, not because the rail behind it is. Where a face is narrow — a block
turned away, the wheel's thin rings — the desktop shows through it. That is the design's intent
("the silhouette should be formed by the rotating triangular blocks and their moving connectors,
not by a rectangular panel behind them") and what the picture on screen shows.
*To change back:* v4's numbers and parts are in the previous commit, and the deleted parts are
one `git show` away; the tokens are one block in `shell/theme/tokens.plm`.
The whole account is `docs/MECHANISM.md`; what was verified is in `STATUS.md`.

## D16 · 2026-10-16 · The bar lies along the top edge: the horizontal v6
A sixth revision of the design (`mooi-the-mechanism-horizontal-v6.zip`, the same `helix-v2-mooi/`
sources) — and with it the master prompt that asks for it: *"The Mechanism must be a horizontal
desktop bar, not a vertical sidebar"*, slim, with the workspace blocks forming the bar, real
system controls on the same line, end caps, no fixed rails, the desktop visible around it, and
short, interruptible motion. That is a change of **direction**, not of proportions, and it is the
one D12–D15 never made: the machine was a rail down the left edge for four revisions.
*The bar is horizontal now*: the surface is `size: full, 220`, `anchor: top`, `reserve: 72`,
`level: top`. The machine uses the first 72 px (axis `g.axis_y` 36); the rest of the surface
carries the wheel's readout and the mark's menu under the strip, painted over the windows and
taking no click. Windows move from x 90 to y 118 = 72 + ArchEclipse's 32 + their own 14 px
margin, and the whole width is theirs again — which is the point of the change, and it is
recorded here so the cost is never a surprise.
*The axis turned 90°.* The rod runs **along** the bar, so a prism's faces turn about it: a face
turning away narrows *in height* and slides up or down the block, and the chain reads as a screw
turning through the focus slot. Every prism in the machine turns on that one axis — the blocks,
the readings, the doors. The chain's own angles, its parity term and the sliding focus slot are
unchanged in kind (`helix_twist` 36, `helix_roll` 180); only the axis they act on moved.
*The column became a row.* Nine prisms under the chain are now twelve slots beside it, on one
line: 0 media (the state, the title, the artist), 1–2 the media **transport** (back · play or
pause · on, a new `Transport` piece), 3 the clock, 4 the System door, 5 volume, 6 brightness,
7 Bluetooth, 8 network, 9 the window door, 10 the Atlas, 11 search. A missing module still
closes its gap, and the pieces after it move along the bar. The wheel moved to the axis's head —
the left of the chain, after the mark — and its two halves are left/right rather than up/down; a
new `Cap` piece closes the machine at its right and carries the error dot that used to sit on the
hairline over the column. The hairline itself survives as one vertical rule where the controls
begin.
*Media is real, and only real.* `service media` is the player's own report, `fact.media_on`
(from the logic, since the scene cannot tell "nothing is playing" from "no player") gates the
transport's zones, and the three controls emit `media_cmd(−1 / 0 / +1)`, which the logic faces at
`sys.call("media.previous" / "next" / "toggle")`. Nothing is shown that is not reported: with no
player the reading's glyph is struck through and the transport takes no press (Pleamar does not
even create a zone whose `active` is false at load — measured both ways). The design's own
invented readouts (`D3`, `R2`, `HN 450`, `FG 007`) are **not** ported: that would be fabricated
system status, which `docs/BRIEF.md` §15 forbids.
*The springs are short now.* `m.chain` 900 → **300 ms**, `m.roll` 1 350 → **450 ms**, `m.turn`
1 100 → **260 ms** — the master prompt's range for a transition (180–320 ms) and the opposite of
what the vertical bar asked for, where a change slid for most of a second. Measured in a
throwaway scene with the tokens themselves: 284 / 450 / 233 ms, the roll 167 ms behind the slide,
so the geared "slides first, turns a beat later" reading survives at a speed you do not wait for.
The workspace is never waited for: `workspaces.focus` is asked at once (§3).
*Labels read like the instrument:* a workspace with no name of its own says its number
zero-padded (`01` … `10`, `lib/spaces`), instead of a bare figure.
*What did not change:* the exposed construction (nothing painted behind the prisms, the desktop
through the strip, click-through where nothing is drawn), preview-is-not-commit, the chain's
two springs following `active_row` alone, the three ways out of the bar, the four islands and
their slot, the theme pipeline, the settings (`spine.*` and `bar.*` keep their names: the strip is
the same strip, and a settings file is not rewritten for a change of direction), and the two
mint/amber rules.
*The cost, and what is not built:* the bar is 1152 px of machine, centred, and on a screen
narrower than about 1168 px it runs past the right edge rather than giving something up (the
`max(8, …)` in the layout — `docs/MECHANISM.md` §1); there is still no second monitor's strip.
In *beside* mode two top strips now want the same 72 px (mooi's and ArchEclipse's); mooi's bar is
the one that is seen (it is the later layer) and ArchEclipse's bar keeps its own 32 px reserved
under it, which is why windows start at 118. Takeover is where the bar is meant to be seen alone.
*To change back:* v5's geometry is in the previous commit; the direction is the scene's four
layout lets, the surface's three lines, and the axis in `shell/ui/mechanism.plm`. The whole
account is `docs/MECHANISM.md`; what was verified is in `STATUS.md`.

## D17 · 2026-10-16 · No dial, and one solid machine from the mark to the cap

The bar's dial is gone. The rotary wheel that stood at the axis's head — its two rings, one
graduation per position on a 300° arc, its needle on a spring, its left and right halves and its
hub — is removed, and with it everything behind it (`nav_open`, `nav_sel`, the `SPACE` readout
plate, the `bar_dial` and `wheel_step` events, the `m.dial` spring and `g.wheel_r`). Three things
made it redundant, and one made it wrong:

- **It was a second way to the same place.** The chain is a workspace selector on its own: a press
  on a block asks `workspaces.focus`, and a notch of the *mouse* wheel over the chain steps one
  position (the `bar.wheel` setting, which stays — that is the wheel over the chain, not the dial).
  What the dial could do that the chain cannot is *preview*: show a workspace without going there.
  That is exactly what the bar should not do. The chain's `pos` and `roll` follow `active_row`
  alone, so the block at the focus slot is always the workspace you are really on — there is no
  state in which the bar claims to be somewhere it is not (MECHANISM.md §3).
- **It cost a fifth of the strip and made the machine two things.** The bar is now one assembly —
  the mark, a neck, the chain's window with its barrel, a neck into the row, the row, the cap —
  with no dial between the pieces.
- **The blocks had to be solid.** Two faults, both found on the screen rather than in the code:
  positions past `g.reach` 2.6 were drawn at a fraction of their opacity (the fifth block at 12 %),
  which is a ghost and reads as a transparent block; and the faces' own bands left the wallpaper
  visible inside a block's silhouette as it turned. A block is now an *opaque* prism — measured on
  the desktop, 46–54 px of graphite across its whole width, with the wallpaper only above and below
  it — and what decides how much of the chain is seen is the chain's own **window**: everything it
  draws is clipped to its zone (`clip box`, `g.frame` 3.75 pitches either side of the focus slot),
  so a block entering or leaving view is *cut off* by the window's edge instead of fading.
  `g.reach` and `g.fade` are gone, and the press follows the same window (`in`).
- **The chain needed a spine of its own.** Workspace 1 has nothing to its left, so the window's
  left half was bare wallpaper and the machine looked broken at the end of the list. The chain's own
  **barrel** — 8 px of graphite at `g.axis_y`, a hairline along each edge, cut by the window's edges
  like everything else in it — now runs the whole width of the window, with a **joint disc** in each
  gap and the blocks threaded on it; the mark's frame is joined to it by a **neck**, and a second
  neck carries it across into the row. The bar has a beginning and an end, and no hole in either.

*What did not change:* the chain's two springs and its angles, the blocks' labels, the module row and
its slots, the keyboard clause except for the dropped `nav_open` term, the theme pipeline, the
settings names (`spine.*`, `bar.*` keep theirs), and the two mint/amber rules.
*The cost:* nothing on the bar can preview any more, and the mobile-of-instruments idea that the
dial carried is gone with it. `tests/scene.sh` lost the four selector checks and gained two: the
chain's window is what decides what is pressable, and nothing stands between the mark and the chain.
The machine is 1112 px wide now (it was 1152), centred the same way.
*To change back:* the dial's code is in the previous commit — the wheel group, the readout plate,
`nav_open`/`nav_sel`, `m.dial`, `g.wheel_r` — and it is a scene-local thing, not a framework one.

## D18 · 2026-10-16 · A steel shaft, matt black, neon marks, and colours that follow the wallpaper

Three things were wrong on the screen, and one was wrong on the *desk*:

1. **The chain's ends were gaps.** With the barrel painted only inside the chain's window, workspace 1
   (nothing to its left) and workspace 10 (nothing to its right) showed a dark hole between the chain
   and the section beside it — the same complaint v6c answered with a body, in a place a body cannot
   reach. The answer is a **shaft**: one steel cylinder, drawn *before* the window and running the whole
   of Region B — from the mark's own frame to the rule where the controls begin — with the window a
   sleeve over it. The blocks are threaded on the shaft, a joint disc sits on it in every gap, and where
   the chain has run out what is seen is the steel it turns on. It is shaded as a cylinder (five bands,
   the top third in light, one specular hairline, the foot closed by the body's black) and capped by a
   collar at each end, so each join is a fitting and not a butt joint. `g.shaft_h` 17.
2. **It was a grey machine, not a dark one.** The body is now the palette's darkest surface
   (`bg.primary`, a matt black), the pieces on it are a step up, and the *marks* are the only light:
   the arriving block, the readings and the doors are the accent, the battery is `status.ok`, the ways
   out and the cap are the second accent. Every face of a prism is shaded by the angle it is turned to
   (`bg.secondary` → `surface.elevated`), so one block's three faces are three greys at every angle,
   and the mark on the lit one is drawn twice — a wide soft stroke under a sharp one — so it reads as
   **neon** on matt black rather than as paint. The body is also *textured*: eight bands of falloff
   under a grain of hairlines (`g.tex` 10), clipped to the slab. Everything smaller with it: the strip
   reserves 56 px (was 64), the machine is **769 px** wide (was 874, and 1112 before that), a block is
   38 px on a 42 px pitch.
3. **Colour was all-or-nothing.** A palette moved the whole bar at once and nothing could be given a
   colour of its own. `bar.tones` is the setting: one colour per mark by name (`chain`, `media`,
   `transport`, `clock`, `system`, `volume`, `brightness`, `bluetooth`, `network`, `window`, `atlas`,
   `search`, `cap`), each defaulting to a palette **role** (`lib/theme.luau`, `M.TONES`), so a wallpaper
   already gives the bar several colours; a name that is not a mark on the bar is reported and the rest
   still apply. The scene draws each mark with `rgb()` over three facts, the same way the tokens are
   painted, so a tone survives a reload, a palette change and a settings edit.
4. **The wallpaper did not follow.** `theme.source` defaults to `wallpaper` now (was `fixed`), and
   `bin/mooi theme-watch` runs `theme-sync` whenever the wallpaper changes — Matugen with mooi's own
   config, one output file, no other program's colours touched. `mooi start` and `mooi takeover` run it
   beside the bar, `mooi stop` ends it, and it is a plain foreground loop a session can run from a
   service of its own. It syncs once at startup when the palette's recorded source (`palette.from`) is
   not the wallpaper now, which is the one case a watcher cannot see. The lock is the truth about a
   watcher — a monitor-mode `inotifywait` used to leave the shell blocked and unable to run its trap, so
   `mooi stop` could leave a watcher behind (`-t 5`, no `-m`).

*What did not change:* the four regions and the row's slots, the springs and the angles, the four
settings the bar already read, the pipeline's precedence (fixed → wallpaper → overrides → check) and
its refusal of a theme that does not pass whole.
*To change back:* the previous geometry is one commit away; `bar.tones` can be left out of the settings
and `theme.source` set to `fixed` to get the brief's palette alone; `bin/mooi`'s watch is three
functions and two calls in `start`/`takeover`/`stop`.

## D19 · 2026-10-16 · One clock for the chain, and the `let steel` that took the scene down

Four things, three of them found on the desk rather than in the design:

1. **The bar would not load.** `shell/theme/tokens.plm` grew a second `let steel` — the palette's
   literal `steel` on line 18 and the derived material `mix(surface.elevated, fg.secondary, 0.30)`
   fifty lines below — and Pleamar refuses a duplicate `let` outright
   (`there is already a 'let steel'`). The scene never came up: the keeper restarted mooi three
   times and gave up, and the desk had no bar at all. The *derived* material is renamed **`metal`**
   (shaft bands, the collar boxes, the Terminus collars; its definition documents the collision),
   and the palette literal keeps `steel` — nothing reads the palette literal as a material, which
   is exactly how the two got the same name without meeting.
2. **The geared pair read as two mechanisms.** v7 slid the chain on `m.chain` (300 ms) and rolled it
   on `m.roll` (450 ms), a beat apart on purpose. On screen the beat showed its cost: during a
   change a neighbour's angle first moved *backward* — the slide led, the roll caught up — so the
   chain twitched before it turned. The two springs are replaced by **one: `m.spin` = 305, 35
   (380 ms)**, driving `pos` alone; slide and turn are the same number now, so they cannot phase-lag
   and the whole chain is one fluid rotation. Measured by hand (throwaway scene, `--record pos`):
   1 %→99 % in **383 ms**, and a retarget 200 ms into a change reaches the new position in 314 ms
   from the re-ask **without ever passing it** (peak 2.9945 of 3).
3. **The step is 132°, not 120°.** The prism lock: its appearance depends only on the angle
   mod 120° — three identical faces, the label riding whichever face is visible — so a step of
   exactly 120° would arrive face-on but leave every neighbour at the *same* orientation: a flat
   chain of identically-oriented plates, no helix. What is needed is that the net step plus the
   visible twist per neighbour is a whole 120°. `helix_turn` **132** does that: each workspace
   step sweeps every block +132°, of which 120° is one more face-turn and −12° the whisper of twist
   a neighbour shows (one full face over ten blocks). The angle law is now
   **`al = 60 − helix_turn·d`** — relative to the slot, so the arriving block is face-on by
   construction — and the `(i mod 2)` parity term is deleted along with `helix_roll`; the rods are
   re-tied to the next block's angular-nearest vertices at the gentler twist.
4. **The finish asked for it.** The plate went to true black (`mix(bg.primary, #000000, 0.55)`,
   measured interior (12,8,8)–(26,20,20) on the running bar); the plain vertical hairline grain is
   a **crossed ±60° weave** now (pitch `g.tex` 9, opacity 0.04, clipped to the slab — woven carbon,
   not brushed streaks); the focus glow was lifted from 4.5 px at 0.20 to **6 px at 0.26** so neon
   reads as light on metal. With it, the v7b slimming that was already in the tree is recorded
   here: `g.spine` 48, `g.tick` 36, `g.frame` 1.5 (the window is three positions, not five), body
   38, machine **590 px** (was 769), Terminus collars at the window's ends, the chain set into a
   recess.

*What did not change:* the four regions and the row's slots, the Prism component and its three
faces, `pos` following `active_row` alone (§3's authority rule), `m.turn` 260 ms and `m.confirm`,
the settings' names, and the palette's own `steel`.
*Verified:* `bin/mooi check` 1392 properties / 2810 instructions, 44 unit tests; every suite green
(`scene.sh` 77 + 9 with a window holding the focus — on an empty workspace its six state-dependent
checks fail as STATUS has always recorded it). The numbers are in `STATUS.md`.
*To change back:* the previous springs and the two-constant helix are in the round below this one;
`m.spin` alone replaces both, so the change is tokens.plm's spring line, the chain's two lets and
its angle line.

## D20 · 2026-10-19 · The bar becomes Ferrolume, and the helix becomes steel

The bar is rebuilt to the **Ferrolume** design system (claude.ai design system "Ferrolume",
its bezel *TopBar*; docs/FERROLUME.md) and replaces the v8 machine. Chosen over Ferrolume's
mechanical variant (*MechTopBar*) by the user, with one instruction of their own: the workspace
area stays a helix rotator — "similar to the one in the shell already but better".

1. **Pleamar, not Quickshell.** mooi already runs on Pleamar 0.4.6 (islands, Hyprland actions,
   theming, tests), Ferrolume ships a Pleamar mapping, and Pleamar has what the design needs
   natively: group `glow:` for "light means live", `arc` for ring gauges, a 600 ms re-light from
   one spring, and WGSL shaders that only repaint while shown (the waveform). Rewriting the shell
   in QML for the bar alone was not worth it.
2. **Tokens copied, prefixed.** Every Ferrolume token lives in `shell/theme/ferrolume.plm` as
   `fl.*` — the Theme library already owns `void`, `steel` and `heat`, and a second `let` of one
   name is what took the scene down in D19 (the alert spring is therefore `relit`, not `heat`).
3. **Two themes on one spring.** Nominal ↔ Alert (battery < 10 %, not charging) is
   `mix(nominal, alert, relit)` on every themed token. The wallpaper may tint the phosphor only
   (`phos`, `phos-fill`, `trace-lit`), per Ferrolume's principle 4; ground, hull, ember and steel
   never follow it. `rgb()` cannot be nested in `mix`/`if`, so those three are mixed per channel.
4. **The helix, better.** Steel prisms (brushed, one lamp, a specular band, `steel-*` tokens)
   instead of graphite tiles; seven positions in view instead of three (`fl.reach` 3.5); a 24°
   twist per block instead of 12° (`fl.helix_turn` 144), so the chain reads as a screw rather
   than a row of tiles; the shaft is as long as the screw and ends in collars, so the ends of
   the list show the end of the part; the window's ends roll the blocks into the bezel's shadow;
   the focus slot is four fixed `trace-lit` brackets; the active block glows for real. Still one
   spring (`fl.helix`, ζ ≈ 0.9, ~420 ms) for slide and turn together, following `active_row`
   only (D19's single clock).
5. **What moved.** The mark is the rail's left end (and a right press on the core). The
   workspace transport is new (previous / next, `--` and no press at the ends). The doors are
   the window and the Atlas; search is the core. Readouts follow the glyph language
   (`VL 064`, `BA 071`, `WF 070`). The surface reserves 88 px (rail + 52 px modules), up from 56.
6. **What stayed.** Every event, fact, island and rule the bar drives is unchanged, and so are
   the zone names the tests read (`chain`, `«Workspace N»`, `mark`).

*Left in place, unused:* `shell/ui/mechanism.plm` (no longer imported), the `g.*` bar geometry
in `tokens.plm`, and the `t_*` mark-colour facts that `lib/theme` still paints from `bar.tones`
— kept so the change can be reverted by restoring one import and the bar section, to be deleted
once the new bar is accepted.

## D21 · 2026-10-19 · Compact, the DNA, a colour engine, and every module switchable

Asked for by the user after D20: smaller; no workspace transport (its slabs go to the media's
previous / next instead); a workspace instrument that is in theme ("morphing alien tech… or
DNA nodes rotating… futuristic yet industrial"); dynamic Matugen theming that applies colours
intelligently and offers different extractions; every component switchable, frames included.

1. **Compact.** A 46 px strip (rail 12, row 30) instead of 88. The reserve is one number, so
   with the rail off the row centres in the same strip rather than the windows moving.
2. **The DNA instrument** is the new default (`bar.workspaces`): phos and ember strands — the
   design's two signals as the two strands — with one rung per workspace whose nodes encode
   its windows, the slot's rung morphing into the lit tag, and an extra turn while moving
   (from `vel(pos)`). The steel prism stays as `prism` (now in the palette's steel), and
   Ferrolume's own grid is `cells`. All three keep the zone names the tests read.
3. **One colour engine for the bar** (`lib/ferro.luau`): nineteen roles built from the
   Matugen palette's hue and held to Ferrolume's contrast floors by lightness alone; the second
   signal chosen to stand apart (≥ 60°) or invented as the complement; grey palettes stay grey;
   Alert on a critical battery. Painted as facts and followed by springs, so every palette
   change glides. Extraction is the user's: scheme, source colour index, contrast and signal,
   all in settings and the menu; the menu re-runs Matugen live (`run: "matugen"`).
4. **Every module switchable**: `bar.modules.<m>.show` / `.frame`, `bar.frame` (bezel, plate,
   bracket, none), `bar.ground`, `bar.rail`, `bar.accents`. Hidden modules give back their
   width. The bar menu is now three columns (look, colour, modules), one `bar_cycle` event.
5. **The theme pipeline, repaired.** The uncommitted Matugen work read a static
   `mooi-themes/current-theme.json` (nothing regenerated it) ahead of the live `palette.json`,
   passed the decoded table where a path was expected and so always fell back; and `paint()`
   wrote twenty extended facts the scene never declared. The logic now reads `palette.json`
   only, the dead painting is gone, and `resolve` keeps the fixed palette underneath a missing
   palette (the unit test that had been failing). `lib/theme`'s `load_theme` /
   `load_standard_theme` and the `~/.config/matugen` mooi template from that work are unused.
6. **Keys.** Super+Alt+Space / Super+Alt+W / Super+Alt+Shift+Space had been lost from
   `hypr/config/bind.lua`; they are in `hypr/config/custom/mooi.lua` now (machine-local, so an
   ArchEclipse update cannot drop them).

## D22 · 2026-10-19 · Every module its own, ArchEclipse's catalogue, and the helix in the bar's edges

Asked for by the user: the Atlas "glitched"; hide ArchEclipse's bar while working; colours that
follow every wallpaper change; gauges that say what they measure; the tag closer to the
helix; visualizer styles; a full-width bar with a background (solid, blur, glass, none) and an
optional border; ArchEclipse's modules brought over with icons in the bar's vibe; every module
individual, with grouping and splitting; and, in the full bar, a workspace switcher that is one
structure with it — chosen from three sketches: **the bar's edges become the helix**.

1. **The glitch was the workflow.** The keeper ran the repo's scene, and pleamar reloads a
   scene whenever its file is saved, so every edit reloaded the live desktop half-way (one
   mid-edit reload hit a logic error). The keeper now runs a snapshot
   (`~/.local/state/mooi/live`); `mooi refresh` updates it and restarts the scene in the same
   mode. Also: special-workspace tiles read SCRATCHPAD, not "WS -99".
2. **Takeover works again.** ArchEclipse's scripts had been replaced, losing two of the three
   guards; the one that matters (the fullscreen sync, which restarts ArchEclipse's bar on every
   focus change) has it back (backup in `~/.local/state/mooi/dotfiles-backup-20261019`), and
   `takeover` requires only that one. SUPER+SHIFT+B remains the way back.
3. **The wallpaper watch missed changes.** After any event in the busy `~/.cache` it slept a
   second, and matched file names; it now compares the wallpaper's target and mtime on every
   wake-up. Verified with two real changes (green ↔ purple) recoloured within a second.
4. **Layout is the logic's** (`lib/barlayout`, tested; `shell/bar.luau`): three lists, `+`
   for groups, widths per module, hidden or absent modules taking no room, the centre centred
   unless it would collide; the scene draws each module at `x_<id>`. Islands or full mode.
5. **Twenty-four modules**, the ArchEclipse catalogue adapted: readings no service gives
   (CPU, memory, temperature, throughput, keyboard, weather) come from `run` and are parsed by
   `lib/sysinfo` (tested), read only while their module is placed; actions use the same tools
   ArchEclipse does (systemd-inhibit, wf-recorder, grim/slurp, cliphist, wlogout, hyprlock).
   Notifications: mooi is the server in takeover only (`notifications.server`), with a notices
   panel and toasts. A new icon set (`shell/icons`) replaces the inline glyphs.
6. **Full mode's helix**: the panel's top and bottom edges ramp into the DNA's strands over the
   workspaces (the body pinching between them) and back out. On glass the pinched middle is the
   hull's smoked tint rather than glass slices, which each caught a bevel and read as a grille.

## D23 · 2026-10-19 · A settings home, an editable bar, the screen frame, and the mechanism

Asked for by the user: the helix frame in islands mode too; a proper settings window that is
the shell's home, its switches live; the media player's minimal modes and what it does with
nothing playing; an edit mode that places anything anywhere; faster recolouring; a machined
"mechanism" surface; ArchEclipse's music-swelling screen frame, joined to the bar.

1. **The settings window is a program of its own** (`shell/mooi-settings.plm`, generated by
   `tools/gen-settings.py`, with `mooi-settings.luau`). Built first as a window surface in the
   bar's scene, it broke the membrane's ← → in about half the runs (found by the scene suite,
   bisected: with the window removed, 4 of 4 passed; with it, 2 of 4); a window in the bar's
   scene takes the keyboard's routing now and then. As its own process it also ends cleanly
   when the compositor closes it. It shares mooi's data folder (bin/mooi links
   `~/.local/share/pleamar/mooi-settings` to it) and writes `settings.json`, which mooi
   applies within the frame; both use `lib/setters` (tested) to agree on what a control means.
   Hyprland floats and centres it (`hypr/config/custom/mooi.lua`).
2. **Edit mode** (`lib/barlayout.drop`, tested; `shell/bar.luau`): modules are picked up and
   carried; every few pixels the layout is planned with the module at the pointer, so the
   others make room live; dropped on a module's middle it joins the group, beside it or in a
   gap it goes there, on the shelf below the bar it is hidden. Escape restores the layout as
   edit mode found it.
3. **The screen frame** is drawn on the bar's own surface (now full-screen, still reserving
   only the strip), so the band and the strip are one silhouette: Tide's maths (cava's bass,
   treble and a travelling phase) for the swell, crests or pulse. It reserves nothing at the
   sides: reserved by strips of their own, the strips were laid out before the bar's surface and
   pushed it in; the band sits in Hyprland's 12 px outer gap instead.
4. **The mechanism** (`bar.surface = mech`): machined housings 5 px wider than their groups so
   neighbours meet at a seam, bolts, a lit lip, recessed bays; vents at the full panel's seams.
5. **The helix as the workspace island's frame** in islands mode (`bar.helix_frame`).
6. **Media**: modes full / compact / art / viz and idle collapse / keep / hide; the layout
   gives the room back. Covers are read from the player (file URLs as they are, web ones
   fetched once).
7. **Recolouring**: the watch no longer waits 0.3 s on a swapped link, and the glide is 300 ms.
8. Also: weather keeps its last reading and retries in a minute when open-meteo fails (it
   answered 503 during this round); tray calls that an item does not implement fall back to its
   menu instead of raising; the scene suite parks the pointer on the frame's band.

## D24 · 2026-10-19 · Plain settings, the desktop and keys, an inspector, and a frame that costs nothing at rest

1. **Settings say what they do, once.** Every row is plain language with one description; a
   row that cannot apply now (the outline in a mode without one, the border colour with no
   border, the desktop's look while mooi does not manage it) is greyed with the reason under
   its title, and a row greyed by two conditions names the one that holds (a `why` that is an
   expression). The same thing is no longer offered in two places (the outline and the old
   border switch are one setting, migrated; Overview no longer repeats "Edit the bar").
2. **Desktop and Keys.** Window border width and colour, gaps, corners and dimming are applied
   live with `hyprctl eval` while `desktop.manage` is on (off: the user's Hyprland config
   decides). The seven keys are captured in the window and written to `hypr.lua`;
   `custom/mooi.lua` records what it bound in `hypr.loaded`, and mooi re-reads Hyprland's
   config when that differs from the settings — comparing with mooi's own previous file missed
   every change Hyprland had never read.
3. **The editor selects.** A press selects a module and an inspector offers its outline, move,
   join, split and hide; the shelf wraps in rows of twelve (a grid's columns are literal).
4. **The screen frame moved to a surface of its own, and is plain at rest.** Measured with
   `pleamar --report` while islands opened and closed: on the bar's surface the frame left
   24 % of frames late (38 % with glass), against 7 % without it; pleamar paints every open
   surface each cycle, and a `body` the size of the screen costs ~16 ms a paint. Plain boxes,
   curved fillets and one stroked rounded box draw the same band for next to nothing (5 %); the
   body is shown only while the swell moves. Glass behind the band cost a third of the frames
   even on the strip alone, so the band is translucent instead. This was also the scene
   suite's intermittent Atlas failure: late frames delivered keys late.
5. **Contrast is lifted, not refused**: a wallpaper palette with unreadable text has the text
   roles raised to the floor, with a note, instead of the whole theme being refused.
6. Fixed: the settings window ended at start (`bar_border` no longer exists in the settings).

## D25 · 2026-10-20 · A visual pass on the bar: instruments that fit, quieter marks, a focus timer

From a capture of every combination of mode, surface, outline and instrument:

1. **An instrument is as long as what it holds.** The window held seven positions whatever the
   count, so five workspaces left half the instrument as empty helix. It now shows them all when
   they fit (`n_vis`, up to `2·fl.reach`) and scrolls past that (`cam`); `chain_x` is the focus
   itself, so the helix's phase — and the generated pinch — needed no change. Pressability is
   being inside the window, no longer the distance from the focus (workspace 1 was unpressable
   from 5).
2. **Numbers where they mean something.** The DNA printed every rung's number over its strands;
   now only occupied workspaces carry theirs (every one under the pointer). The prism printed its
   number on two faces at once; now on the face turned toward you. Cells keep their corner marks
   for the one in use or under the pointer, and show their windows as pips.
3. **Marks that read as marks.** Stroke cuts span the stroke only, in the strip's own colour (at
   5 px they stood proud of the bezel as black blocks); the bolt is a socket head (the slotted one
   read as the letter "s"); the ring gauge lost its core dot (it read as a radio button) except
   when hot; the themed tray prints icons in the phosphor instead of a pale silhouette.
4. **No seam across empty panel.** In full mode a cluster seam is drawn only where clusters meet;
   across an empty stretch the space itself parts them.
5. **Motion that says what happened.** A comet rides the rail with the focus while the instrument
   moves; the minute runs out as a hairline under the clock (`clock.seconds`; accents on).
6. **A focus timer** (`focus`): a block of work, then a break of a fifth of it (≥ 5 min), a ring
   of what is left, a toast at each end; the wheel sets the length at rest. It starts on the
   shelf: the default row no longer fits 1920 px with it and the wider window title (190 px).

## D26 · 2026-10-20 · The look as settings, a notch, a background of your own, Hyprland's scrolling

1. **The look is settings, one module (`lib/style`) for both programs.** Corner radius, outline
   width and colour, pill style, shadow, opacity, glass frost and smoke, chromatic aberration and
   glow strength are `st_*` facts the bar and the settings window both take from `style.facts`.
   Every default is the look the bar had before, so nothing changed until a choice was made.
2. **Outline is the edge, not the fill.** `none` used to drop the island's fill as well; the
   material (`bar.surface`) now always fills, and the outline only draws (or not) its edge.
3. **A notch** (`bar.mode = notch`): lib/barlayout reports the three clusters' extents; each is a
   piece hanging from the top edge — the centre a notch, the sides flush with the corners — its
   foot rounded, its sides met by inner fillets (quadratic curves into the edge), of the bar's
   material, outline and shadow. No rail over it; groups inside a piece are parted by dividers.
4. **A background of your own, kept readable.** lib/ferro takes `bar.bg` (black, the wallpaper's
   own dark, a dark of the main colour, six tones, or `bar.bg_colour`), shifts it in lightness,
   saturation and hue, then re-holds every text role against it — a sand background darkens the
   text. Black leaves the palette exactly as it was.
5. **Colour generation**: two more harmonies for the second signal (a neighbour at +40°, a triad
   at +120°), a colourfulness push (−50…+50) and a **matte** finish (signals at 55 % saturation,
   glow at a quarter). Every glow on the bar is scaled by `st_glow`.
6. **Windows and scrolling are Hyprland's own** (0.56 has a native scrolling layout): layout,
   column width, focus fit, touchpad and mouse direction and speed, window blur — each `keep` by
   default, so mooi writes none of them until one is chosen. Handing one back to `keep` reloads
   Hyprland's config (lib/desktop `claims` / `covers`), since an applied value would otherwise stay.
7. **The tray, in mooi's glyphs**: the network and Bluetooth applets name icons by state, which the
   icon theme lacked (nothing drawn) or drew as a blob; they are now mooi's Wi-Fi (with its arcs)
   and Bluetooth glyphs, and a program that names no icon shows its initial.
8. Fixed: the settings window's clip rose with a scrolled section (only its top showed).

## D27 · 2026-10-20 · One palette for the whole shell, settings by reach, sliders, an industrial finish

1. **One palette.** The islands, panels and dialogs took their colours from a pipeline of their
   own (the brief's fixed palette, or Matugen roles mapped one to one); the bar from lib/ferro. Now
   lib/theme maps its fourteen tokens from lib/ferro's roles (`FROM_FERRO`: surfaces are the hull,
   text the phosphor, the second accent the ember, selection the well), so the base, the finish,
   the colourfulness and the Alert re-light reach everything at once — and Hyprland's borders and
   neon shadow take the same phosphor. The old fixed palette and Matugen mapping are gone; overrides
   and the refusal of an unreadable theme stay. tests/theme.sh works out its expectations with the
   same libraries instead of hard-coding colours.
2. **Text held against all of its surfaces at once**, the hardest first; a base in the luminance
   band where no text can read 4.5:1 (about 9–42 %) is moved to its nearer side, and raised surfaces
   step away from that band. Found by a light pink base being refused (4.2:1).
3. **Settings by reach**: Appearance (everything mooi draws), The bar, Windows (Hyprland), Input.
4. **Sliders for every number**, the lowest step of a Hyprland one meaning KEEP. The desktop's named
   speeds and widths of D26 migrate to numbers. A slider sets only on press, drag or wheel: a first
   version set on any pointer move while a rule thought the zone pressed, and wrote every slider the
   pointer crossed (caught and reverted the same hour; the backups put the values back).
5. **Industrial finish**: the settings window is machined steel on concrete — plates with a
   chamfer and a lit lip, choices in a recessed track lit as lamps, metal switches and sliders on a
   groove with a neon line. Base tones obsidian, gunmetal, concrete, titanium, oxide, alien; a
   **neon** finish (signals near full saturation, lit, 1.7× glow).
6. **Windows**: opacity focused and unfocused, shadows (soft, deep, or a neon glow), with size.

## D28 · 2026-10-20 · Everyday switchers, presets over knobs, machined depth and buttons

1. **Everyday switchers beside the instruments**: pills (ii / iNiR's joined plates and a sliding,
   stretching active pill), segments (ArchEclipse's thin bars, opening under the pointer to show each
   workspace's app), dots, numbers — in Pleamar, one component (`ClassicWs`) and three sliding
   markers in the scene; `lib/spaces` marks runs of occupied workspaces (`joined`).
2. **Presets over knobs.** Material, backdrop, outline, depth and hover were separate settings
   that could fight (a clear bar with a deep shadow; a base colour and a "black" backdrop). A bar
   style and a look now write coherent sets (lib/style `BAR_PRESETS`, `THEME_PRESETS`); the window
   reads which preset the settings match, or Custom. The details moved to Bar details and Colour
   details; Appearance and The bar are a few rows each.
3. **Machined depth**: solid frames and the islands are lighter at the top than at the foot, with
   a faint lit lip; glass and frosted keep their own body.
4. **One button face** (`BtnFace`, ui/island.plm) for the islands' buttons — window actions, the
   move-to-workspace keys, the Atlas's move strip, search's action chips, the close button: machined,
   the edge lit under the pointer, a neon bar under the chosen one, the second colour when armed.
   The system island's levels are a groove, a lit fill and a machined knob.

## D29 · 2026-10-20 · Compass and radar; settings as flat pages with a search; an audit

1. **Compass and radar switchers**: a heading tape under a lubber line, and a scope whose sweep turns
   to the active workspace's bearing, with blips by occupancy — both on the instrument's spring.
2. **Settings, after iNiR's quick page and Serpantinum's rows**: no headings; a Quick page first;
   the Colour details and Bar details pages folded back into Colour and Bar, ordered preset-first;
   a row that does not apply is hidden rather than greyed, the rows under it gliding up; a search
   over every row (Enter opens the first, Escape clears). Generated, so a row added to the spec is
   in the window, in the reflow and in the search at once.
3. **Audit, fixed**: reduced motion, following a moved window and search's result count were
   settings with no row (now in System); the per-mark colours (`bar.tones`, `t_*`, `theme.marks`)
   were painted every recolour and read by nothing since the Mechanism bar went (removed; a file
   that still has `bar.tones` gets the "unknown setting" note); unused settings components (`SHead`,
   `Swatch`, `Slash`) removed. Measured: 0.9 % CPU at rest, 64 MB; suites degraded 8, config-recovery
   13, theme 31 — all 0 failed.

## D30 · 2026-10-20 · Headings that name the parts, a width, styles that differ, search that types

1. **Search never had the keyboard**: a Pleamar window asks for it (`keyboard: on_demand`), and the
   settings window did not, so its field (and the Keys page's capture) took no real key. Now it asks,
   the field takes the cursor when the window gets the keyboard (and on Ctrl+F or /), and gives it up
   while a key is being changed. Checked with real keystrokes (wtype): "frame" → 8, Enter opens it.
2. **Headings again, for the parts of a page** (Shape, Surface, Edges, Extras; Palette, Light, Base;
   Band, Music; Edges, Spacing, Depth, Layout; Touchpad, Mouse; …), hidden with their rows when those
   cannot apply (Windows' parts while mooi does not style windows).
3. **Fewer, plainer choices**: the outline and its weight are one choice (none, corners, thin,
   regular, bold); the frame's music and its motion one (off, swell, ripples, pulse); the strip behind
   the islands is the style's; Matugen's contrast and the wallpaper's 2nd / 3rd colour (what Auto
   picks between) are no longer offered.
4. **A bar width** (`bar.width`, 30–100 %, centred): islands, the full bar and the notch (whose side
   pieces hang free with fillets on both sides when it is narrower); the rail and the strip follow.
5. **Styles that differ**: each also sets the rail and the details, and their parts are further
   apart (glass: a thin bright edge, an outline hover, no rail; floating: no edge, a strong shadow, a
   glowing hover; steel: an accent line, a medium shadow).
6. **The screen frame**: corners, a neon inner edge, solidity; and since it lies in the windows'
   outer gap, that gap is widened to fit it while it is on (it was 2 px here: the frame could not
   be seen at all).

## D31 · 2026-10-20 · Anywhere on the bar; switchers that move as one; a thickness; Ryoku's settings

1. **The switcher stopped moving** because the map stopped at `spine.max_workspaces` (4 here) while
   the focus was on 5 and 7: the active row fell back to the first slot and stayed there. The map
   now reaches the active workspace and the last occupied one past the setting (now "Always shown"),
   and the bar re-lays out when its length changes (lib/spaces; a test).
2. **One motion for every switcher**: the highlight is a liquid whose head runs on a quick spring
   and its tail on a slow one, so it stretches toward where it is going and gathers there; each
   workspace lights by how much of it the highlight covers; and on arrival a ping rings out of the
   new one (`ws_arrived` from the logic, `arr` in the scene). The sliding instruments add a detent
   (their focus brackets give and flare), the compass's lubber line kicks against the turn, the
   radar pings its contact.
3. **Anywhere, in any order**: the Layout page (Ryoku's Bar Studio, in Ferrolume) shows the bar to
   scale, the three lists and the shelf as chips; select one and move it, join or split it, send it
   to any side, remove it, or put a shelved one back. **Spacers** (`gap`, as many as wanted) stretch
   on the sides, pushing what follows toward the middle, so a module can sit anywhere along the bar;
   in the centre they are 24 px. Moves go by place (lib/arrange), since a spacer has no name. The
   Modules page went: showing and outlines are on the Layout page now.
4. **Thickness and distance from the edge** (`bar.height` 24–44, `bar.offset` 0–40); the old
   "width" is now Length. Pleamar's `reserve:` is one number read once, so the bar's surface reserves
   nothing (-1) and seven empty surfaces reserve the bits of `st_res` (lib/style), stacking along the
   top edge: the windows leave the bar exactly its strip, live — and a bar without its rail gives its
   7 px back.
5. **Settings laid out as Ryoku's are**: a rail of pages in groups (Look, Bar, Desktop, System), each
   page a stack of `//NAME_` cards with hairline rows, a stripe of light at the edge of the row under
   the pointer, a page that slides in when chosen; a **revert arrow** on every setting that is not
   its default, and a **Reset** per page (two presses: the first arms it for three seconds).
6. **Tested apart from the desktop**: a lab copy (its own data folder, permissions to change nothing,
   a read-only hyprctl) on a headless output, so the user's bar and settings were not touched while
   it was checked.

## D32 · 2026-10-20 · Edit mode places a module where it is let go, and stops stuttering

1. **Anywhere, for real**: a module dropped into empty space on the bar stays there. The drop puts a
   fixed gap (`"gap:120"`, lib/barlayout) in front of it (behind it on the right) sized so its middle
   lands under the pointer, and shrinks a fixed gap that followed, so what lay beyond does not move
   (tests: within 1 px; the right end unmoved). On a module's middle it still joins its group; beside
   one it goes before or after it. Fixed gaps are kept only where they measure something (the left
   list's start, the right list's end, between modules). In edit mode every spacer and gap shows as a
   hatched box with its width, and a press takes it out.
2. **The stutter**: the scene asks for a preview every few pixels, and each one laid the whole bar out
   again, rewrote ~75 facts and stopped and started the readers (cava, sensors). Now a preview is laid
   out only when the order would change (a gap's width is the drop's to measure), and a preview starts
   and stops nothing. While carrying, the bar shows where it will land: the module's outline at the
   pointer and a line through its middle.
3. **Tidier modules**: the cuts in the islands' outlines read as breaks and are gone; each frame stands
   3 px clear of its modules and islands 16 px apart; the battery, volume and brightness gauges are
   84 px so a value never runs into its ring; the two-line readouts are centred by their letters (the
   value sat low and touched the frame); with nothing playing the media module says so instead of a
   flat visualizer and a dash; the edit shelf and its buttons sit under the bar wherever it is.

## D33 · 2026-10-20 · Lighter, snappier, one colour language for the switchers

1. **Dead code out** (archived first: ~/.local/state/mooi/archive-2026-10-20-mechanism-and-unused.tar.gz):
   the Mechanism bar's code (`shell/mechanism.plm`, `.luau`, `shell/ui/mechanism.plm`), the PNGs only it
   drew, an unused shader, five icons nothing drew, and the Mechanism's tokens (its geometry, three
   springs, a dozen alias colours) from `theme/tokens.plm`. The 24 per-module outline facts the scene
   never read are a Lua table now (only the workspaces' stays a fact, for the helix's edges). A scan
   for unused components and Lua functions found none left.
2. **Measured**: at rest the bar draws no frames and takes ~1–1.5 % of a core (the clock's tick and the
   readers that are on the bar); ~96 MB just started, ~130 MB after a while. Pleamar's `--report`
   found nothing to judge at rest. The reserve surfaces are 1 px tall and cost nothing measurable.
3. **Snappier, after iNiR and Ryoku**: the switchers' highlight runs on iNiR's own timings (its
   `AnimatedTabIndexPair`: a 100 ms head, a 300 ms tail) as critically damped springs — measured on a
   six-workspace jump: head 77 ms, tail 218 ms to 95 %; the sliding instruments arrive in 150 ms with a
   detent's overshoot (they took ~420 ms); modules move to new places in ~260 ms (~400); the ping is
   ~460 ms and rings at the destination rather than riding the slow spring; the dots make room where
   the dash is, not where the instrument spring is.
4. **One colour language**: active is the palette's main colour (on its fill, ink on it), occupied a
   lit trace, empty a dim trace, the arrival ping flare going to the main colour — in all nine. The
   radar's blips and the compass's occupied marks were the second colour (ember) and now match.

## D34 · 2026-10-20 · The palette reaches your apps; the settings the vision asked for; Phase 4

1. **Your apps in mooi's palette** (Colour → Your apps; each off by default): the bar writes
   `apps.json` — its palette in Matugen's role names (lib/appcolors), with eight terminal hues held at
   the main colour's saturation and lightness so red, green and blue stay apart — and the theme watch
   renders it (`bin/mooi apps-sync`): **Kitty** from mooi's template (the `include` line in kitty.conf
   points at colors-mooi.conf); **GTK 3/4** from your own Matugen templates (mooi's otherwise), with your
   Matugen config's two GTK outputs pointed at ~/.cache/mooi while it is on, so two generators never
   write one file (the brief §7); **Qt** through qt5ct / qt6ct (a qt6ct.conf mooi had to create goes when
   it is off). `apps.state` records what was there: off puts it back byte for byte (tested in a
   sandboxed home). `mooi refresh` now restarts the watch too, so it runs the repo's code.
2. **Settings the vision lists**: *Motion & effects* — a speed for everything (50–200 %: the live copy's
   springs and timings are scaled as it is made, the visualizer's excepted, and the bar restarts to take
   it; checked at 150 %: the head spring went 4400 → 9900), reduce motion (now immediate), glow and
   aberration, a battery saver (glow, aberration, the frame's music, the visualizer and cava off — on
   battery or always); *Displays* (read-only, from Hyprland); *Sound* (output and input devices, each
   app's volume); *Power* (the battery, the saver, power-profiles-daemon's profile when it runs — it is
   masked here, so that card hides); *Advanced* (versions, the bar's CPU and memory, the settings file,
   the log). The custom base colour has a picker: hue, richness, lightness and eight quick picks, with the
   base's own adjusters hidden while it is chosen (they would do the same thing). The window is 1180 × 800
   for the sixteen pages.
3. **Notifications as a centre**: the notices stay until dismissed (`notifications.keep(true)` — asked
   after the watch, or the service is not there yet); one row per app with how many it holds, opened out
   by a press; a press on a single one does its app's default and clears it; × on a group clears the
   group. **Do not disturb**: on, while a focus block runs, or in quiet hours — no toasts but urgent ones,
   the bell struck through, a switch in the panel's header. Missed ones (from an earlier run) are listed.
4. **The Atlas has a workspaces board**: a column per workspace (the active one ringed), its windows as
   small previews; a window carried to another column goes to that workspace (v switches views).
   Checked with Pleamar's agent `drag`: a tile carried 440 px asked Hyprland to move it to workspace 4.
5. **Multi-monitor, first step**: every monitor's copy of the bar shares one layout, and it was laid
   out for the focused monitor — a narrower one's bar ran off its edge (seen with a 2560 px headless
   output beside the 1920 px screen: the laptop's bar went blank), and a monitor unplugged left the
   layout at its width. It is now laid out for the narrowest monitor, measured again when the set of
   monitors changes. Still to do: a wider monitor's bar spans only the narrowest's width, and each
   monitor shows every workspace (per-monitor workspaces and layout need the bar's positions and
   springs per copy — Pleamar shares a scene's props across copies).

## D35 · 2026-10-20 · The Mechanical Shutter

A window's controls unfold from its edge: an anchor bracket on its corner, an angular track, four
plates (Arrange, Workspace, Behaviour, Connections), a panel straight out of the open plate, and a
third level where a choice needs it (docs/SHUTTER.md). Super+Alt+D on the focused window, or
Super+Alt+right-click on the one under the pointer (plain right-click is the app's). Pure placement
and action registry (lib/shutter, unit-tested), a controller (shell/shutter.luau) that follows the
window only while open, and commands through lib/hypr's read-back, so nothing is reported done that
is not. New commands were checked on a throwaway window first (maximize, centre, an exact size,
opacity via getprop); pseudo-tiling, always-on-top and the split cannot be read back on Hyprland
0.56, so they are not offered. The Connections plate is deterministic: the window's working folder,
its Git root, a terminal there, its app's other windows; a tool that is missing leaves its connection
out rather than stopping the shutter (the first live run stopped on a missing `kitty` permission).

## D36 · 2026-10-20 · The Atlas's spatial view

The third view of the Workspace Atlas (brief §4.1's Spatial): every monitor drawn to scale where
Hyprland has it, each holding the windows of the workspace it shows, where they really are, with
their pictures, and its workspaces as chips under it. A window carried onto another monitor goes to
the workspace that monitor shows (so windows move between monitors), onto a chip to that workspace;
a press on a window focuses it, on a chip goes to that workspace. `v` steps through the three views.
The geometry and what a drop lands on are lib/atlas (pure, unit-tested with two monitors of
different sizes). Checked in the lab with a second (headless) monitor and a throwaway window: both
monitors drawn side by side, the window carried onto the laptop's monitor asked Hyprland to move it
to that monitor's workspace. Found on the way: a drag reports `pointer.y` with a large offset where
`local` is true, so carried windows on the board and the spatial view now follow `local`.

## D37 · 2026-10-21 · The Overview: the desktop zooms out (Super + Tab)

Asked for: Super + Tab, and the way iNiR's workspace view zooms out. iNiR's overview is a grid of
miniatures of the whole screen, wallpaper and windows, and opening it shrinks the screen you were on
into its cell. mooi's Overview does that: a full-screen surface on the focused monitor, the
wallpaper dimmed behind, rows × columns of miniatures (Settings → System: rows 1–3, columns 2–6,
default 2 × 5), each the wallpaper with its workspace's windows placed as fractions of the monitor,
with their live pictures. On opening, the cell of the active workspace starts at full screen and
springs into its place (`fl.zoom` 430, 41) while the dim and the other cells come in. A press on a cell
goes there (the cell zooms back up as it closes), a window carried onto another cell is moved there,
arrows and Tab move a keyboard ring, Enter goes, Escape or a press on the backdrop puts it away.
Super + Tab opens it while `atlas.super_tab` is on (default); its own key (`keys.overview`,
Super + Alt + O) always does. It is a sibling of the Atlas island, not a replacement: the Atlas keeps
its grid, board and spatial views. The grid geometry is lib/atlas `grid` (unit-tested).

Found on the way: eight `let`s chained on `screen.width`/`height` inside a `screens: each` surface
kept the whole scene redrawing at 60 fps even while that surface was closed (idle went from ~1 % to
3 % of a core). The geometry is now computed in the logic and handed to the scene as facts; idle is
back to 0 frames at rest, ~1 % CPU, 123 MB. The rule: no `let` chains on `screen.*` in an overlay;
compute layout in Luau. Checked live on eDP-1: opens, holds, pictures refresh about three times a
second while open, closes. Not checked by hand: the zoom's feel with a real Super + Tab, a carry
between cells on the real desktop (done in the lab only through the agent). Super + Tab also stays
bound in ArchEclipse's own config (dormant under mooi's takeover); both fire if that is re-enabled.

## D38 · 2026-10-21 · The Overview as a strip; the Atlas's privacy

Two settings under Settings → System. `atlas.overview` grid | strip: the strip is one row of the
workspace map just under the bar, on a plate that slides down from it, the desktop left in view
behind a light dim (no full-screen zoom; Up and Down do nothing). Both shapes come from lib/atlas
(`grid`, `strip`), handed to the scene as facts (D37's rule). `atlas.private` off | sensitive
(default) | everything: password managers (by class) and private browsing (by title) keep their
picture and title to themselves — the compositor is never asked to copy them, not merely not shown
(`thumbnails.want` gets only the ids privacy allows) — and `everything` shows app names only, for
sharing the screen. Setter codes past 99 go to 300+ (`setters.path`). Checked in the lab (a private
test window was never copied, kitty was) and deployed 2026-10-21. Not yet: the spatial view's
label for a private window; pictures re-asked at once when the setting changes while it is open.

## D39 · 2026-10-21 · The Overview's hands: keys, marks, undo, names

The Workspace Atlas brief (Phase 2 and the start of Phase 3) on the Overview that already worked:
- **Keys.** `W` picks the next window in the keyboard's cell (an offset bracket on its corners),
  Enter then focuses it; Shift + arrows carry the picked window a cell over — a real move, the ring
  going with it; `1`…`9` jump to a cell. A cell has no window to pick: it says so.
- **Marks.** Right-click a window, or `X` on the picked one: an ember outline and a corner notch
  (not colour alone). Carrying any marked window, by drag or by keys, carries them all; the hint line
  counts them. Pleamar gives no modifier state with a press, so Ctrl+click was not possible.
- **Undo.** `U` or Ctrl+Z takes the last carry back — only for windows that still exist and are still
  where it put them (lib/atlas `undo`); the rest are counted, not guessed at. One step, not a stack.
- **Saying what happened.** Every carry is the window island's verified move (read back), one window
  after another; the hint line says what moved, or how many of how many and the reason.
- **Names and accents.** `R` names the keyboard's workspace (a field over the cell; Enter keeps it,
  empty clears it, Escape leaves it), `C` steps its accent through none · phos · ember. Kept in mooi's
  own versioned `workspaces.json` (lib/atlas `identities` checks it: junk dropped, names trimmed and
  cut at 24 letters, a newer version not guessed at) — never written into Hyprland's workspace rules.
- **Escape** takes back one thing at a time: the name field, the marks, the pick, then the Overview
  (Pleamar reads a key's guards before any of its rules act, so exactly one fires — tested).

Found on the way: an event the logic answers needs `->` even without a value (five did not reach it).
Checked live on eDP-1 through Pleamar's agent with two throwaway kitty windows on workspace 8: pick,
Shift+Right (Hyprland read back 8 → 9), U (back to 8), two marked and Shift+Left (both to 7), Ctrl+Z
(both back), a name and an accent written and shown, the Escape cascade; the test windows and name
removed afterwards. Not checked: a real hand's drag of a marked group (the drop path is the same
`carry` the keys use); the Overview once closed between two agent runs with no command of ours to
explain it (perhaps a key from the person at the desk), not seen again.

## D40 · 2026-10-21 · The Overview after iNiR's workspace view; dragging that keeps up

Asked for: dragging that is not "really bad", a press-and-hold that does not focus the window and
close, and a zoom-out more like iNiR's. Read from iNiR's own source (modules/overview/
OverviewWidget.qml, OverviewWindow.qml, Overview.qml) and rebuilt in mooi's language:
- **Shape.** One plate just under the bar, rows × columns of the screen at 18 % (iNiR's scale), 6 px
  apart (lib/atlas `grid`, now anchored to the bar's reserve). Plain cells, a large faint number on
  the empty ones, each window its live picture under a veil with its app's icon in the middle, the
  active workspace's border sliding between cells in 180 ms. The hint line sits in the plate's foot.
  The full-screen zoom out of the active cell and the wallpaper in every cell are gone.
- **Opening.** iNiR's unfold: from its top edge, 0.975 × 0.93 → 1, 12 px down, opacity leading, over
  a 55 % dim (iNiR blurs at 40 %; without the blur 40 % left the desktop's text legible behind it).
- **Drag.** It was decided by `pointer.x` alone, so a mostly vertical drag never became one and its
  release was a click: focus and close. Now a press is a click until the pointer travels 5 px either
  way (`length(drag.dx, drag.dy)`); the window is held where it was taken (not recentred), on top;
  the cell under the pointer lights; let go over a workspace, it is shown there at once and glides
  from the pointer into place (per-window springs: `wx.$i: … ~0ms`, then its `follow`), then the
  verified move — a failure is put back by the rebuild; let go anywhere else, it glides home.
  Middle-click closes a window (iNiR), through the verified close.
- **Smoothness.** Measured with `pleamar --report` over repeated drags: 7–17 % of frames late, p99
  31–36 ms. Not the overview's drawing (hiding every part of it changed nothing; a bare full-screen
  surface paints in 0.3 ms) but the window copies: with previews off, 0 % late. Live copies
  (`thumbnails.live`) were worse (~50 %); pausing copies per drag gave 60–70 ms hitches (starting and
  stopping them costs frames of its own). So the Overview copies in bursts — 450 ms once it has
  unfolded and after each move — and the last pictures stand in between: 0–0.4 % late, p99 ~22 ms.
  The Atlas island still copies throughout. Also: the board is rebuilt one at a time and never under
  a carried window, and the scene no longer binds the thumbnails list to a model nothing drew.

Checked live with throwaway windows: a vertical drag moves (Hyprland read back), the Overview stays
open, no focus; the recording shows the unfold, the carry and the glide. Not checked: a real hand's
drag (agent drags only), middle-click close on a real window. Trade-off to know: pictures are
snapshots while the Overview is open, not live video.

## D41 · 2026-10-21 · The Overview: search, a menu, and the zoom-out back

Asked for: search and a workspace action menu, and to keep the zoomed-out view (D40 had dropped
D37's zoom for iNiR's unfold).
- **Zoom.** The workspace you are on starts as the whole screen —clear, the real desktop showing
  through— and shrinks into its cell while the rest of the panel fades in and comes down 12 px
  (iNiR's slide, without its scale: a scaled panel bent the zooming cell). Its windows ride the zoom
  and fade in as it shrinks (their pictures are the last snapshot, so they come in late on purpose).
  Closing grows the chosen workspace back out. The strip does not zoom.
- **Search, typed at once (iNiR).** A row on top of the panel takes the keys as the Overview opens:
  titles and apps light and the rest dim; a workspace's name or its number finds it; the keyboard's
  cell and pick go to the first found, so Enter focuses it, or goes to the workspace (lib/atlas
  `search`, unit-tested). Escape clears the search before anything else.
- **Keys, re-dealt for a text field.** Measured in a test scene: a rule on a letter takes it from the
  field, and the field keeps Return, Left/Right (any modifier) and Ctrl+X. So W, X, U, R, C, the digits
  and Shift+arrows went: Tab / Shift+Tab across workspaces, ↑ ↓ between rows, Alt+↑ ↓ a window in one,
  Ctrl+M marks, Ctrl+Z undoes, F2 names, Menu or Shift+F10 the menu, Enter goes.
- **Menu.** Right-click a workspace, or a window (its workspace's menu with that window picked and its
  own rows first), or Menu: Mark / Close the window, Go, Move N windows here (only when something
  would move), Rename, Next accent, Close its N windows. Both closes ask twice; each window gets the
  verified close (an app may ask to save). Only what can be done there is listed (lib/atlas `menu`).
  Marking with the mouse is now in the menu (right-click had been "mark").
- **Fixed on the way.** The after-move picture refresh read a constant declared lower in the file:
  every successful move since D40 ended in a logic error (the move itself had happened).

Checked live with throwaway windows: the zoom (frames), keys typed straight into the search, a
title search and a number, the menu by right-click and by keys, Move here (Hyprland read back),
Mark, Close twice-asked, a move and Ctrl+Z with no new errors. Not checked: Enter on a result (it
would have switched the person's workspace mid-session; the paths are D37's and D39's), a real
hand's Super + Tab and typing.

## D42 · 2026-10-21 · Workspace groups

The brief's §8: workspaces kept together under a name ("Dev" over 1–3, "Comms" over 4–5), mooi's own
organising layer — never a Hyprland workspace or rule; taking a group away leaves its workspaces and
windows exactly as they were.
- **Kept** in the same `workspaces.json`, a `groups` list (name, accent, workspaces), still version 1:
  the field is new, nothing old changed meaning, and a file from before reads as it was. Checked on
  the way in (lib/atlas `identities`): a workspace in one group at most (the first that claims it),
  names trimmed and cut, unknown colours to the signal's, empty groups dropped, twelve at most.
- **Shown** in the Overview: a 3 px line in the group's colour under each of its workspaces, run across
  the gap to the next one in the row, and the group's name on its first workspace on the page
  (lib/atlas `group_marks`). Search finds a group's workspaces by its name.
- **Changed** from a workspace's menu: "Group ›" turns the same housing to the group page — Join
  (another group), New group…, and in one: Leave, Rename…, Next colour, Take away (asked twice), Back.
  New and Rename use the name field over the cell (the hint line says it names the group).

Found on the way: a second variable used above its `local` (the group being named), the same slip
as D41's — caught by a scan for names used before their declaration, now clean. Checked live on empty
workspaces 3 and 4: a group made, joined, found by search, its page, taken away twice-asked; the
person's own workspace name untouched throughout. Unit tests 107, 0 failed.

## D43 · 2026-10-21 · Saved environments

The brief's §11–12 (Phase 4): a working setup kept to come back to. In the Overview, Ctrl+E (or the
ENVIRONMENTS button on the search row) opens a drawer over the panel's right side:
- **Save this desktop as…** keeps the workspaces' names, accents and groups, each window's app (its
  installed .desktop id) and workspace, and for a terminal the folder its shell is in. Kept in
  mooi's `environments.json`, versioned, twenty at most, sixty windows each.
- **An environment's page:** Restore…, Rename…, Duplicate, Delete (asked twice; the desktop is not
  touched).
- **Restore… shows the plan first** (lib/environments `plan`, unit-tested): names and groups to be
  put back, what is already in place, each window to move (`kitty 9 → 8`), each app to open (`on 8
  in /tmp` — a folder that is gone opens in the home folder, said so), what cannot be (not installed,
  or no app known), and "Nothing open is closed." Restore now carries it out: the identities
  replaced, moves through the verified move, missing apps opened on their workspace with
  `hl.exec_cmd('[workspace N silent] …')`, and a line saying how many moved, were asked to open, and
  could not be. Opening is reported as asked, not as done: an app takes its own time to appear.
- **The file is data, never a script.** It names an app and a folder; the launch is built from the
  app's own installed entry (field codes out), the folder single-quoted, and only for terminals that
  take one (kitty, foot, alacritty, ghostty). A .desktop id that is a path, a relative folder, or one
  with a line break is dropped on the way in; a newer file version is not guessed at.

Found on the way: kitty starts `kitten` helpers beside its shell, and "the newest child" — the
Shutter's way to a terminal's folder (D35) — was a helper in the home folder. lib/hypr
`terminal_shell` now takes the newest child that is a shell; the Shutter's Connections and saving
both use it. Checked live with throwaway kitty windows in /tmp: saved (folders right: the person's
terminal in ~/Projects/mooi, the tests in /tmp), one moved away and one closed, the preview showed
exactly that, Restore now moved one back and opened the other in /tmp on its workspace; delete asked
twice; the person's windows and workspace name untouched, the test environment deleted. Unit tests
112, 0 failed.

## D44 · 2026-10-21 · An Overview page in Settings; the Overview on several monitors

- **Settings → Overview** (Desktop group, after Shutter), gathering what was spread over System and
  adding four: *Opening* — Super+Tab opens it, **Zoom out of your workspace** (off: the panel just
  comes down); *Shape* — grid or strip, rows, columns, **Size** (each workspace as a share of the
  screen, 14–24 %, iNiR's 18 % by default; still shrunk to fit), **Dim behind** (0–80 %, 55 %);
  *Window pictures* — on or off, **Taken** as it opens and after a move (smooth, the default) or every
  3 s too (a hitch each time, said so on the row), privacy. Four settings past the 100th (codes
  301–304). The settings rail's pitch went from 28 to 26 so seventeen pages clear its edit button.
- **Several monitors.** The Overview opens on the focused monitor (iNiR's `activeScreenOnly`) and
  already moved windows across monitors (Hyprland moves by workspace); now, with more than one
  monitor, each workspace names its monitor in its corner, and a workspace another monitor is
  showing right now is outlined in the second signal, "ON HDMI-A-1" (lib/atlas `cell_monitors`).
  With one monitor nothing changes.

Not done, on purpose: pages past ten workspaces (the person does not need them). Checked live: the
page captured; zoom off and a lighter dim through temporary facts (nothing written to settings);
a headless second monitor for a moment (its workspace outlined and named, then removed, focus back
on eDP-1). Unit tests 113, 0 failed.

## D45 · 2026-10-21 · Rearranging inside a workspace; a touchpad swipe for the Overview

The brief's Phase 5, where Hyprland supports it reliably (the file manager left alone, as asked).
- **Rearranging.** A window let go in its own workspace in the Overview: a tiled one dropped on another
  tiled one swaps with it (`hl.dsp.window.swap({ target = … })`); a floating one goes where it was let
  go, its corner kept on its screen (`hl.dsp.window.move({ x, y })`, layout coordinates); anything
  else is Hyprland's tiling's to decide, so nothing is done and the window glides home (a tiled one on
  a floating one says so). Both shown there at once, then the verified action (lib/hypr `swap_with`,
  `place`; lib/atlas `rearrange`). Hyprland 0.56's Lua API documents no arguments for these; they
  were read from its own refusals ("Expected one of: direction, target/with/other, next, prev";
  "direction, x+y(+relative), workspace, …") and each checked on throwaway windows read back — a swap
  with three windows (the third did not move), a placement to the pixel.
- **Touchpad swipe** (Settings → Overview, off by default): three or four fingers *down* — the one
  direction the desktop's own gestures leave free (sideways: workspaces; up: special workspace and
  fullscreen). mooi writes it beside its keys; `~/.config/hypr/config/custom/mooi.lua` (machine-local;
  backed up first to ~/.local/state/mooi/custom-mooi.lua.before-D45) now registers `cfg.gestures`
  with `hl.gesture`, each running `mooi overview`, and records them in hypr.loaded so turning it on or
  off reloads Hyprland. Checked: the file run against a stand-in `hl` (the gesture registered, its
  action runs `mooi overview`, the record matches mooi's); Hyprland accepting the spec (a bad
  direction is refused); a reload with the new file. **Not checked: a swipe by hand.**

Rearranging is not undone by Ctrl+Z (that stays for moves between workspaces); a swap is its own undo.
Unit tests 116, 0 failed.

## D46 · 2026-10-21 · The Overview's canvas

The brief's free-form arrangement. Hyprland's workspaces are numbered, not placed, so the canvas is
mooi's own spatial layer — like names and groups, kept in `workspaces.json` (`canvas`: a workspace's
slot, column and row) and never written into Hyprland.
- **A third shape** (Settings → Overview → Shape → Canvas): a board of slots with room to spare, one
  row and two columns more than the grid (7 × 3 by default), the empty slots drawn faintly. A
  workspace is carried by its number — the badge becomes a handle (a press without carrying still
  goes there) — to any slot; one already there takes the carried one's old slot. Its windows ride
  along, the slot under the pointer lights, and both glide into place.
- **Everything is drawn from slots now.** The logic gives each workspace (and each window) the slot it
  is on — the canvas's where they were put (lib/atlas `canvas_slots`: a saved place kept if free and
  on the board, else its place in the grid, else the first free one), the grid and the strip in
  reading order — so one code path draws all three, and the grid looks exactly as before.
- **Drops are hit-tested in the logic** (`slot_at`, `cell_at`): a carried window sends where it was
  let go, and the logic decides — another workspace (moved), its own (placed or swapped, D45), or
  nowhere (it glides home). ↑ ↓ go to the nearest workspace above or below (`canvas_near`); group
  lines join workspaces that sit side by side on the canvas; the menu says "Put every workspace back
  in order" while the canvas has places kept.

Found on the way: a fact the logic writes does not wake the logic's own watcher on it, so the
keyboard's slot (where the name field opens) lagged after ↑ ↓ — each logic-side change now updates
it directly; and a handler used `save_identities` above its declaration (moved up, scan clean).
Checked live with throwaway windows and the shape switched to canvas for the test (settings.json
restored byte for byte after): a workspace to a free slot (saved), onto another's (swapped), its
window riding along, a window dropped on a moved workspace (Hyprland read back), Ctrl+Z, ↑ ↓, the
menu's tidy; the grid's moves and undo unchanged. Unit tests 119, 0 failed.

## D47 · 2026-10-21 · The Overview's canvas, as asked: a camera over an infinite field

The person's brief (mooi · Spatial Workspace Canvas) replaced D46's board of slots: one continuous
field, workspaces as territories anywhere on it, a camera to pan and zoom. Built in its order 01–02
and the core of 03:
- **A camera over a world.** Every workspace is a rectangle in a world where one unit is one screen
  pixel; the canvas's territories are the screen at full size (so 100 % is a territory the size of
  the screen), the grid's and the strip's are their cells (the camera held still). The camera opens
  on the workspace you are on, filling the screen, and pulls back (to everything, on the canvas); it
  dives into the one chosen as the Overview closes. One code path draws all three shapes; D37's
  special-cased zoom cell is gone.
- **The canvas.** A near-black field (the palette's ground) with a coordinate grid that quietens as it
  pulls back and strengthens while something is carried; territories with clipped corners,
  registration marks off them once near enough to read, a nameplate over each ("02 / HI · 1 WINDOW",
  its group under it, the active one's marker lit) by which it is carried; windows with their
  pictures, icons and — near enough — titles. Drag the field to pan, the wheel zooms where the
  pointer is, a double press on the field makes a workspace there (the next number; Hyprland makes it
  when it is first gone to), Ctrl+F fits all (F itself types into the search), Ctrl+0 goes back to
  where you are, Ctrl+= / Ctrl+− zoom, and a navigation instrument in the corner (− · % · + · FIT ·
  HERE). Click a window: brackets and an action strip (focus, float/tile, fullscreen, close asked
  twice); a double press goes to it; drag it anywhere — onto another territory (moved), within its
  own (placed or swapped, D45). Places are kept in workspaces.json (`canvas`: a territory's corner,
  snapped to 40 px), never in Hyprland; lib/atlas `territories`, `at_world`, `fit`, `focus_cam`,
  `near`, `canvas_place` (unit-tested). Not done from the brief: territory resizing, alignment guides,
  the minimap, pinch (Pleamar has no pinch), middle-button pan (untested here, so not claimed).
- **Found and fixed.** The scene counts in 32-bit floats: drop points packed into one number
  (`tile · 10⁸ + x · 10⁴ + y`) lost their last digits — a territory set down landed thousands of
  pixels off, and D45/D46's window drops were off by up to a few pixels; drop points now travel as
  two facts beside the event. Floating windows were drawn under tiled ones (unreachable once a tiled
  neighbour filled the workspace); they are over them now, as Hyprland shows them.
- **Smoothness, measured** (pleamar --report, repeated agent gestures, this laptop's iGPU): pan 0.3 %
  late frames, window drags 0.3–0.5 %, wheel zoom 0.3–2.5 % (frame work ≈ 6 ms of 16.7; what is late
  is waiting on the compositor, which bisecting every part of the drawing did not move). Opening and
  closing ~3 late frames a cycle — the same as the grid's, i.e. the full-screen surface being made;
  a window's fade moved from its group (an offscreen layer) to its parts, its veil folded into the
  picture's opacity, and layers that cannot be seen not drawn.
- **Theme aware like the islands.** Corners follow Appearance's rounding (`g.radius`,
  `g.radius.item`) everywhere — plate, cells, windows, menu, drawer, search bar, instrument,
  nameplates, and the territories' clipped corners; the plate, menu, drawer, search bar and
  instrument are the islands' machined body (gradient, lit lip, `border.subtle`, shadow); the active
  marker glows by the theme's glow (none under the battery saver); the dim is the palette's ground.
  Motion speed and reduced motion apply as to every spring. Checked by switching the rounding live.

## D48 · 2026-10-21 · mooi as the whole desktop

Asked for: mooi alone, no ArchEclipse. What ArchEclipse still did was inventoried before anything
changed: its bar at login (`bar.sh`, from its own `config/exec.lua`), the bar again on every focus change
(its fullscreen watcher), fourteen keys that only reached it over IPC (search, apps, panels, power,
clipboard, emoji, notes, recording, overview, toggle bar), the lock and suspend keys, and — by
default — the notifications (mooi served them only in a takeover). Everything else at login
(wallpaper picker, desktop widgets, Polkit, theming, applets) is not ArchEclipse and stays.
- **A setting**, Settings → Advanced → "mooi is the whole desktop" (`session.standalone`, off by default),
  written into hypr.lua beside the keys (lib/desktop `file`) and in the key signature, so switching it
  reloads Hyprland.
- **`bin/mooi session`**: a keeper mode that holds the desktop (the same marker every guard knows) and
  never hands back to ArchEclipse; it records its mode (`$rt/mode`) so `stop` and `status` tell it from a
  takeover; a keeper that gives up after three quick crashes now says so in a critical notification
  (before, a desktop could silently lose its bar). Notifications are served whenever mooi holds the
  desktop (`claim`: not only in a takeover). New: `mooi notes`, `mooi clipboard`, `mooi record [area]`,
  and the scene's `open_notes` / `open_clips`.
- **The machine-local Hyprland side** (backups in ~/.local/state/mooi/dotfiles-backup-20261021-standalone):
  `custom/mooi.lua` starts `mooi session` at login and takes over the ArchEclipse keys (or lets go of
  those mooi has nothing for); `bar.sh` stands down while the setting is on (`--force` overrides) and
  the fullscreen watcher never restarts the bar; `custom/session.lua` feeds `cliphist` at login (mooi's
  clipboard panel showed nothing new: only an unloaded file fed it).

Checked: switched on and running as `mooi session` (status "the whole desktop"); `bar.sh`, the watcher
and focus changes all leave ArchEclipse down; a notification arrives in mooi's centre; Super+R, Super+L,
Super+Shift+V and Super open mooi's panels for real (key presses through ydotool); the clipboard panel
lists new copies; the login itself simulated against a stand-in `hl` (starts `mooi session`, rebinds,
lets go). Not checked: an actual logout and login, the recorder keys (they would record), hyprlock's
look (it would lock the screen). Unit tests 120, 0 failed.

**ArchEclipse uninstalled (same day).** Not with its own `uninstall.py`: that takes every file the home
repo tracks, the whole Hyprland config with them. Taken instead, archived first
(~/.local/state/mooi/archive-2026-10-21-archeclipse.tar.gz; edited configs backed up in
dotfiles-backup-20261021-uninstall): the shell (`~/.config/quickshell/archeclipse`), its installer and
updater (`hypr/maintenance`, `dotfiles-update.sh` and its monthly timer, which would have pulled it back),
`archeclipse-eq.service`, and the scripts only it used (`bar.sh`, the fullscreen watcher,
`clipboard-monitor.sh`, `screenrecord.sh`). `exec.lua` no longer starts the bar, the watcher or the old
clipboard monitor; `bind.lua` loses the keys that called it (mooi binds its own) and locks through
`lock-session.sh`. Kept on purpose: the Hyprland config, the wallpaper picker and the desktop widgets
(both read matugen's `colors.json`, so that template stays, under its old name), the app themes
matugen writes, and `~/.cache/archeclipse` (zen's colours live there). `custom/mooi.lua` now holds the
desktop when ArchEclipse is missing whatever the setting says, and `bin/mooi` hands back to it only
when it is installed (`takeover` becomes `session` without it). Checked: Hyprland reloads with no
errors, no key calls `qs ipc` any more, mooi's keys and "standalone" are bound, the picker and widgets
run, matugen recolours with no error, `mooi status` says "ArchEclipse: not installed".

## D49 · 2026-10-21 · Settings is a bar module

The way into mooi's settings was the mark: the rail's left end, or a tab at the bar's edge with the
rail off — fixed, not placeable like everything else. It is now a module, `settings` (lib/barlayout,
32 px), drawn as a dial: six teeth on a ring and an ember index around a hub. Pointing at it turns the
teeth a sixth of a turn; open settings keep it turned and light the hub. Press: open or close the
settings · right press: edit mode (arrange the bar). The mark and the tab now show only while the
module is off the bar, so a layout without it still has a way in. The default row puts it with the
session and search (`settings+power+core`); keep-awake moved to the shelf to make the room (the
1920 px test). The user's own layout got it at the start of `bar.left`
(backup: ~/.local/state/mooi/settings.before-settings-module.json). Checked: compiles, 120 tests, the
dial on the live bar, an agent press opens and closes the settings.

## D50 · 2026-10-21 · The Signal Loom: notifications as signals, and the Field

Notifications were the bar's bell: a count, a panel, and a pop-up from the server. They are now a
module of their own — the Signal Loom — because a notice is an event with a place and a lifetime,
not a list item.
- **A notice is a signal with a tier.** Three tiers, all the server's own words can tell: `whisper`
  (low urgency, or from an app you muted, or anything but an urgent one under do-not-disturb),
  `manifest` (normal), `intervention` (critical). A whisper comes and goes thinly; a manifest
  unfolds with what it says and offers; an intervention stays until it is dealt with. Related
  notices are one signal — same app and title, or same app, per `signals.grouping` — the newest
  speaks for the thread, with how many it holds.
- **Where they unfold.** One of four corners (`signals.edge`), as chamfered segments cut from the
  Ferrolume plate (D50's `ui/loom.plm`, `Chamfer`): up to `signals.max` at once, a `+N` for the
  rest, each with the app's own buttons (up to three), its picture, and Open/Snooze/Dismiss. The
  segment glides `signals.travel` from its edge, its corner is cut `signals.chamfer`, and
  `signals.effects` lights an arrival and an urgent edge (notices still come without it).
  `signals.density` switches compact/comfortable. `signals.linger` times a manifest out (a whisper
  half as long); the pointer on the cluster holds them, and what ran out while held goes when it
  leaves. `signals.private` hides the words in the pop-up; the Field still shows them.
- **The Signal Field.** Pressing a signal (or its cluster) opens the centre: the app's clusters in
  the left column (what was missed included, marked), the chosen cluster's notices on the right —
  body, thread count, snoozed/missed state, the app's buttons and Open/Snooze/Dismiss/Forget. Keys:
  ↑↓ choose a cluster, Shift+↑↓ a notice, ↵ open, Delete dismiss (Forget for a missed one), `s`
  snooze 15 minutes, `m` mute or unmute the app (muted apps whisper); "Dismiss all" clears the
  cluster. Its activity rail is the last six hours, each tick a notice, lit by tier. A notice dismissed
  or acted on is gone from the server too (the server keeps them otherwise, `notifications.keep`).
- **The bar, not the bar's bell.** `shell/signals.luau` takes the server's list (one receiver per
  session: `notifications.server` always / while mooi holds the desktop / never), cleans it through
  `lib/signals` and hands the scene its rows; the bar's bell reads `loom_count`/`loom_more` instead of
  keeping its own count, and the focus timer's toast goes through the loom as a local signal (never the
  server's). Muted apps are `signals.json` in mooi's data folder.
- **The working-out is pure.** `lib/signals.luau` — cleaning (markup out, entities in, control
  characters spaces, cuts on character boundaries), tiers, grouping, slot assignment, the rail's
  positions — is plain Lua 5.4 and unit-tested (7 tests). Settings gains a Signals page (tab 17:
  origin, at once, stays out, join, size, corner cut, travel, glow, hide what they say) with Reset;
  Advanced moves to tab 18.

Checked: both scenes compile, every logic file parses, 127 unit tests, 0 failed; the settings
generator re-runs byte-identical and setter codes 307–315 reach `signals.*` with the schema's ranges.
Not yet checked live: a notice arriving, a signal's time-out, snooze/shelve, the Field's keys.

**Checked live afterwards (real `notify-send`, recorded):** a manifest unfolds (diamond, arm, face)
and times out; a low one whispers; two from one chat thread are one signal ×2 with the app's icon;
a download replaced under its id (`-r`) updates in place; a burst of five leaves `+N WAITING`; the
Field's clusters, thread items, rail ticks, keys, mute/unmute and per-cluster dismiss work; an
urgent notice's own button reaches the app (`notify-send -A` printed `open`). Fixed on the way:
the server gives urgency as the standard's **number** (0/1/2), not a word — critical notices were
never recognised (the old bell had the same bug); an intervention is never the one left waiting
behind `+N`; a whisper's count is inline (its chip spilled out of the slim line); the urgent × sat
on its words; the loom no longer pops over an open Field (they land in it); `bin/mooi start` (and
so any toggle key while mooi is down) becomes `session` when ArchEclipse is not installed — it had
come back "beside", where it does not claim the notices.
**What the server does not pass, so the loom does not pretend:** expiry hints, categories and
progress values (no progress bars, no "reminder" or "developer" layouts beyond what the words carry);
inline reply. Snooze is mooi's (the notice stays on the server, out of sight for 15 minutes).

## D51 · 2026-10-21 · Quick notes: a pad in the bar and its dropdown

A note is something you want out of your head before it is gone, so it takes one press and one
line: the bar's notes module, and a dropdown under it.
- **The module.** `notes` (46 px, lib/barlayout): a page with a folded corner, and how many notes
  are on it, lit like the bell. A press opens the dropdown; a press again, Escape, another panel,
  edit mode or 45 s idle closes it. It is a module like any other — placed, grouped and hidden in
  the Layout page, with the generated grips and the setters' 100 + n / 200 + n codes coming from
  the one module list. The default row now carries it: the screenshot and recorder pair begins on
  the shelf to make the room (46 px where their 60 were).
- **The dropdown.** Drawn in the bar's own surface (no second window to place), under the module,
  in the islands' plate: an input (focused when it opens, Enter saves), the saved notes newest
  first — one line, how long ago, a press copies, the pencil changes one in place (the button
  becomes Save, Escape cancels the change before it closes the pad), × forgets — and a word for a
  moment (`SAVED`, `UPDATED`, `COPIED`, `DELETED`, `RESTORED`). A forgotten note can be put back
  for eight seconds (Undo in the footer, `qn_undo`). Six rows show; the wheel pages through the
  rest, the header saying which of how many. It is theme-aware by construction: `fl.*` and the
  shared plate, like every module.
- **The file.** `notes.json` in mooi's data folder, `{ version = 1, notes = [ { id, text, time } ] }`,
  newest first, capped at 200 (oldest fall off), each note cleaned (control characters, runs of
  space, blank lines folded, cut at 4,000 characters on a character boundary) and never trusted on
  read. A note is a line or two, not a document: no folders, no sync, no editor.
- **The working-out is pure.** `lib/notes.luau` — cleaning, one-line previews, adding (newest first,
  empty refused), changing (same id and place, time moved), restoring (the id kept unless taken),
  finding, removing, decoding a hand-written or older file, encoding, and "how long ago" — is plain
  Lua 5.4 and unit-tested (5 tests). `shell/notes.luau` owns the file, the rows, the undo and the
  clipboard (`wl-copy` on its input), and re-reads the file if something else writes it.
- **From the terminal.** `mooi note "what to remember"` saves a line through the running scene's
  own input path (nothing else touches the file), so a keybind or a script can jot one without
  opening anything; an empty argument is refused with a usage line. The old `mooi notes` (the
  notification panel) is untouched, and the two are told apart by the trailing word.

Checked: both scenes compile, every logic file parses, 132 unit tests, 0 failed; live: the module
placed on the bar, a real pointer press opens the dropdown, a note written through the input's own
text/Enter events is saved and the draft cleared, empty notes are refused, editing keeps the count
and changes the text, Escape cancels an edit, × forgets and Undo restores, the wheel pages seven
notes, `mooi note` saves from the terminal, `notes.json` survives a restart, copy, and Escape closes
(`tests/notes.sh`, 36 checks). Not checked: two notes that differ only after the cut, a matrix of
scale/monitor placements (the dropdown clamps to the screen), a hand editing notes.json while the
pad is open, and editing a note that was written with more than one line (the input is one line; it
is flattened).

## D52 · 2026-10-21 · The pad perfected, and a Kanban board from its rail

**The pad (D51), reviewed.** Fixed: a file with a repeated or missing note id lost those notes on
read (`decode` dropped them while saying it made ids unique — now they are renumbered, none lost);
the placeholder, the footer and the module's label had their two texts the wrong way round
(`pick(c, a, b)` is `a` while `c` is false: the empty pad said "Editing"); the dropdown let presses
through its empty parts to the window under it (a catch zone now); closed from outside mid-edit, it
reopened still editing (`fact:qn_open` resets it). New: **pinned notes** (first, flare-marked, never
taken by the 200-note cap; `pinned` kept in notes.json), **send to the board** (first line the card,
the rest its note, into the board's first column), **the keys** — ↑↓ choose a row, Alt+C copy, Alt+E
edit, Alt+P pin, Alt+B to the board, Alt+Delete forget, Ctrl+B the board — and the look: cut from the
loom's chamfered plate and unfolding like the Signal Field (its head runs out from the module, then
its body drops), with **a rail** down its left — the pad, and the board (with how many of its cards
are late).

**The board.** `shell/board.luau` + `lib/board.luau` (pure, 5 tests) + `ui/board.plm`; board.json in
mooi's data folder. Opened from the pad's rail, Ctrl+B in the pad, or `mooi board`; a surface of its
own in the middle of the screen that opens from its middle (a bar across, then the board).
- **Columns** (Inbox, Doing — limit 3 —, Done to start; up to six, a new one goes before Done; renamed,
  moved, given a work-in-progress limit — over it the head goes ember —, removed only when empty).
  The last column is where work is done: a card reaching it is stamped done, leaving it unstamps it;
  "Archive done" moves those to the archive (kept, capped at 500).
- **Cards**: a title, a note, one of five tags (palette colours and mixes of them, so five stay apart
  whatever the wallpaper gives), a due day (none, today, tomorrow, a week — shown as "today",
  "2 d late", lit ember/flare/phos as it nears), made/changed/done times. Each column scrolls on its
  own; a card is **dragged** anywhere (a lifted copy follows the pointer, a line shows where it will
  land — the drop is computed from coordinates passed as facts beside the event, never packed), or
  stepped with the pane's buttons or Alt+Shift+arrows.
- **The pane**: the chosen card (title and note **saved as you type**, half a second after the last
  key, per card and field so switching cards never loses or misplaces a word), or the chosen column;
  always a field for a new card (Ctrl+N), added at the top of the chosen column.
- **Finding**: search (title and note, any case; Ctrl+F) and a tag filter; hidden cards take no room.
- **Undo** (Ctrl+Z, ten seconds): a deleted card back in its place, an archive, a removed column.
- **Keys**: Alt+arrows choose, Alt+Shift+arrows move, F2 the title, Alt+0–5 the tag, Alt+Delete
  delete, Esc close. Letters are never bare keys (a focused field would lose them).

Checked: both scenes compile, 138 unit tests, 0 failed; live through the agent: the board opens and
closes, cards added from the field, tagged, dated, stepped, dragged (into Done: stamped, "DONE"),
deleted and put back, filtered by search, a column's limit set; the pad's pin (a note pinned and
unpinned), a note sent to the board by Alt+B, the corrected placeholder; recorded. Not checked: a
real pointer drag by hand, six full columns of long titles, a board.json edited by hand while open.

## D54 · 2026-10-22 · The stash: a box on the left edge for whatever you drop on it

**Asked for:** a small stashbox at the left edge of the screen that opens on hover, where links,
images, videos and any file can be dropped, in mooi's theme, with a pulse light running around it
while it is open.

**Where it lives.** `lib/stash.luau` is the pure part (kinds, names, safe names, paging, a file read
back; 7 unit tests in `tests/unit/run.lua`). `shell/stash.luau` owns `stash.json` and the `stash/`
folder in mooi's data folder, and answers drops, presses and the wheel. `ui/stash.plm` draws the kind's
mark and a row; the box itself (`stash_dock`) is a surface of its own in `shell/mooi.plm`. A 9 px rail
sits at the vertical middle of the left edge and opens into a 336 × 558 chamfered plate when the
pointer rests on it for 70 ms; away from the plate and the rail for 120 ms, it closes. Dragging a file
to the left edge opens it too (`drag.over` and the pointer near the edge), because during a compositor
drag hover events are not delivered.

**Closing, told by the zones and not by the cursor.** The first cut closed the box when `cursor.x`
was no longer inside it. That reads well until the compositor is late or wrong: on this machine the
cursor socket reports a `cursor.y` of 110540 at the very moment the pointer is on the rail, so the
box shut 120 ms after it opened. What a surface is told for certain is where the mouse is **while it
is over it** — the zones' own `hover` springs — so closing asks those three and nothing else. A
lesson worth the line: prefer what the surface is told over what somebody else reports about it.

**What a drop does.** Files (and folders) are **copied** into `stash/<time>-<n>-<safe name>` and the
item points at the copy, so moving the original does not empty the stash; the same source dropped
again is the item it already was (it moves to the top). Links and plain text are written down only.
Images are drawn from the copy; a video gets one frame (`ffmpeg`) after it arrives, and the row shows
its glyph until then. A press opens the item (`xdg-open`, or the clipboard for text), a right press or
the × removes it and its copy, a drag carries it out as a file/link/text, and the wheel pages six at a
time. Sixty items are kept.

**Most things a person drags, and that includes songs.** Kinds are link, image, video, song, file and
text: pictures are those the desktop's own libraries know (`png jpg jpeg jfif gif webp avif apng jxl
bmp svg ico tif tiff heic heif`), films are `mp4 mkv webm mov avi m4v mpg mpeg ogv ts m2ts flv wmv vob
mts mxf asf f4v 3gp 3g2 divx rmvb`, and songs are `mp3 m4a m4b aac flac ogg oga opus wav wma aiff aif
alac mka mid midi amr ac3 dts ape mp2 spx wv ra`. Everything else — a PDF, an archive, a font, a
folder — is a file: copied, named by its extension, opened by `xdg-open`. A song or a film is asked its
length by `ffprobe` once it has arrived, and its row says `MP3 · 3:41 · now`; a song that carries cover
art (mp3, m4a and flac usually do) gets it as its picture, and one that does not keeps the level-meter
glyph. `ffprobe` comes with `ffmpeg`, which the video frame already needed, and both had to be added
to the scene's `permissions { run: … }` — a command a scene has not declared does not fail quietly:
it raises, and it did, in the middle of `add_item`. The item is now written down and shown *before* the
picture and the length are asked for, so a missing tool costs the row its decoration and never the
item.

**Why a surface of its own.** The pulse is a light that travels the border; it is stepped by
`every 33ms` while the box is out, not by `time`, so the scene rests while it is closed. The box is
its own 360-wide surface anyway: animating a full-screen surface at 30 fps would repaint the screen,
and D37 already showed what a full-screen repaint costs (the surface is full height so the box can
be centred from `screen.height`, but only the rail's 9 px plate and the box are painted). The surface is always mapped, but only the
rail's 9 px plate is painted, so the rest of it passes clicks through. Nothing asks for the keyboard except while a folder is
being named (`keyboard: exclusive while stash_naming`): hover opens the box, a press acts, leaving
closes it, and the keys are the window's again the moment the name is done or Escape is pressed.

**A Pleamar detail worth remembering.** A drop is sent to the logic only for the **topmost zone** under
the pointer (`Event::Received(hovered.id, …)`), while `on drop zone` rules fire for every zone
underneath. The rows sit on top of the plate, so each row's zone is named `stashrow` and the logic
listens to `drop:zstash`, `drop:stashrow`, `drop:zstash_tab` and `drop:zstash_catch` alike. A row's
zone is really `stashrow#r0#StashRow3633` (`describe` says so), and the platform hands the logic the
name up to the `#` — which is what makes one handler do for every row.

**Folders, one level deep.** A box holds everything; a folder is a place to put some of it. The chip
row at the foot is the folders (`ALL` first, then the ones made, up to five) and the field under it
makes one: a press on the field, a name, Enter. They are the panel's own, not directories in `stash/`:
`stash.json` keeps a `folders` list and each item a `folder` id, so a file keeps its copy where it was
put and only the row knows where it is read. The chip row is reached by slot — the order the folders
were made in, the same order in the logic and in the model — which is why the scene can name a folder
`zfolder.$i` and the logic answer `drop:zfolder.0` … one handler per slot, made in a `for`. Taking a
folder away (a right press on its chip) does not take its items: they go back to the root, and the
box goes back to `ALL` if it was inside it.

**The tray, and why not a drag into a folder.** Each row has a small tray glyph beside its ×: a press
there sends the item to the next folder, and back to the root after the last, saying where it went
(`ALPHA`, `BACK AT THE ROOT`) and showing it on the row's line (`ALPHA · PNG · 2m`). A drag *into* a
folder would be the obvious gesture, and it is the wrong one here: a row already carries its file out
to other programs, so the compositor takes any press-and-move on it and the scene's own drag rules stop
there. The tray is a press, it cannot be confused with carrying something out, and it walks the folders
— five at most — faster than a menu would open.

**Both ways.** A row carries its copy out (`carries: "{r.url}"`), so another program gets a file, a
browser the link, a text editor the text, and mooi keeps its own copy. Dropped back on the box itself,
that same path is recognised (`mine()`): it is not a new item, the one there is moves to the folder it
was let go on, and nothing is copied twice. A drop on a chip goes into that chip's folder; a drop
anywhere else on the plate goes into the folder the box is showing.

**The strip at the edge.** A surface is given the mouse only where it paints something, so a file
dragged to an empty part of the 360 px surface would pass through to whatever is under it, and the
box would never learn it was coming. Round the rail there is therefore a 12 px strip painted at
`opacity: 0.01` (the Shutter's trick) — invisible, inside Hyprland's 12 px `gaps_out`, so no click
meant for a window is taken. It is what the drag enters, and what takes a file let go right at the
edge before the box has finished sliding out. This is why the row is one zone
covering the whole 312 px: the × is drawn, and `local.x` decides whether it was the × (remove) or the
row (open).

**A compiler limit found on the way.** In a component of a library that imports another library, a
`let` cannot see the imported names (`fl.phos` is "nothing called"), though a drawing property can. The
mark's tone is therefore chosen at the call site and passed in as a colour; no colour is held in a
`let` in `ui/stash.plm`.

Checked: both scenes compile (`bin/mooi check`), **148 unit tests, 0 failed**. Live, on a copy of the
shell in `/tmp` with its own data folder (mooi itself was stopped for the tests), with the mouse
moved by `ydotool`: the rail opens the box on hover, the box stays open while the pointer is on it and
closes once it leaves; the pulse advances while the box is out; an image dropped back through the
logic's own door is copied into `stash/` and shown from the copy; a link, a piece of text and a
`.txt` are kept; a video gets its `ffmpeg` poster; the same file again says ALREADY STASHED and is not
copied twice; a press on a text item puts it on the clipboard; the × removes the item, its copy and its
poster; nine items page 1–6 and 7–9, clamped at both ends; and the list is the same after a restart.

For the folders, with the box held open by the lab's own fact and the presses sent by name
(`press znew`, `type stash_new SONGS`, `key Return`): a folder is made by a name and Enter — the field
empties, the box goes into it, and `stash.json` has it; a drop while inside lands in that folder; the
chips move between `ALL` (five items) and a folder (one), and say its name in the head; the tray walks
item → next folder → … → root, and the row's line follows; a right press on a chip removes it and sends
its item home; and the tray press was sent from a row (by name, with the row's press routed to `file`
in the lab copy) and reached the logic as `stash_file`. Not checked live: a chip actually receiving a
drop — the compositor's drag coordinates do not reach the scene in this session (the same limitation
as the drop itself), so `drop:zfolder.N` is wired and reasoned through but not seen fire.

**Not checked live:** the last inch of a real drag-and-drop. A drag started in Thunar does reach the
surface (`drag.over` goes 1 and the box slides out at the edge), but in this session the drag's
coordinates never reach the scene — `pointer.x/y` stay at the last ordinary position — so the drop
lands on no zone. That is the platform's dnd path, not the scene's: the handlers were exercised with
the same payload a compositor hands over (`text/uri-list`, `text/plain`).

---

## D55 · 2026-10-22 · A press outside a panel closes it; the audit of everything that opens

**What prompted it.** The report was «my mouse clicks are not registering, it goes on and off», with the
notifications, the search, the stash, the notes pad and the board named. The audit found three things,
none of them in the input region itself — that part is sound, and `PLEAMAR_REGIONS` now says so in a
line per surface: the bar's zones are committed where the bar draws them, and a closed surface gets
`[]` (its plate goes, its zones with it). What was wrong was what happened to a press that landed
*beside* what was open.

**A layer surface does not hear what is outside it.** D37 onwards every panel was dismissed by its own
×, by Escape or by the idle timer; a press on the desktop did nothing at all, which is exactly what
«my clicks are not registering» feels like — the press is taken by the panel's plate or by the window
and nothing happens, then the next press lands on a control and the panel closes, so the shell seems to
answer «on and off». The bar's surface is the whole screen in any case: a plate declared **before
everything else it draws** now takes the presses the panel's own controls do not, and closes whichever
of `qn_open`, `kb_open`, `mark_open`, `side == notes`, `open == window/system/command` is up. Being
declared first is the whole trick — every panel, row and button is above it, so a press inside a panel
never reaches it; and being in the bar's surface (level `top`) it lies over the windows, so the press
that closes a panel does not also fall through to the window under it. The overview, the shutter and
the Atlas are surfaces of their own (level `overlay`) and are above it, so they are untouched.

**The stash opened from an invisible strip.** The 12 px catcher along the left edge was there for drops
(D54) and had picked up `on hover zstash_catch` as well: crossing the screen's edge anywhere in those
558 px slid a 336 px plate over the desktop, and while it was out its plate took every press that was
not on a row, chip or field. Away from it the box closed after its 700 ms, and back it came. That is
the «opening and closing» seen earlier in the session and a dead region under the pointer in the same
breath. Dropped: the box opens from the **visible rail** (9 px, the thickness of the plate), or from a
drag to the edge (`drag.over`, which is what the strip is for), and a **press on the plate now closes
it** — so no press in the box is ever swallowed. The strip still takes a file let go right at the edge.

**A row that carries is a row that cannot be clicked.** A stash row was one zone with
`carries: "{r.url}"` and `local.x` deciding whether the press was the row, the tray or the ×. The
compositor takes any press-and-move on a zone that carries, so pressing the × and moving a pixel began
a drag and the press was lost; the tray had the same trouble. The body (0–266) carries and opens, the
tray (266–288) and the × (288–312) are zones of their own above it, and none of the three can be
mistaken for another. Right press still removes from all three.

**Audited and left alone.** The Signal Loom's own region is `[]` while nothing is out; the Field, the
board and the pad each catch their own plate and no more; the search island's modes, the mark's menu and
the islands' buttons are all above the new plate and answer as before. The board's surface is its plate
(1240 × 760, ten pixels of margin), so a press *inside* it and outside every control is still the
board's own background — it does not close the board, and does not reach the window either: that is a
panel's own surface, not a gap in it.

**Checked.** Both scenes compile (`bin/mooi check`), **148 unit tests, 0 failed**. Live, on a copy of the
shell with its own data folder and Pleamar's fake pointer: a press on the battery opens the System
island, a press at 900,700 closes it (`Press("dismiss")`, `open = none`) and another on the notes module
opens the pad, which the same press closes (`qn_open = false`); and on the board, opened from the pad's
rail, a press on the board's own background and one on the desktop both close it (`Press("dismiss")`,
`kb_open = false`). The stash was checked with the real pointer: the rail opens the box on hover and
the plate is on screen. **Not checked live:** the strip and the rail told apart by a hand, and the tray
and the × as separate zones — the studio's own shell is on the same screen, so a synthetic press or
hover can land on either and the evidence is ambiguous; both are `bin/mooi check` clean and reasoned
through above.

**A press can still be lost while a panel is opening.** Seen in the log while testing: the bar's sheet
re-commits its input region as a panel's plate grows (`qu_a`, `bu_a`), and the compositor takes the
pointer focus away and gives it back with each commit — `Focus(false) · Leave("dismiss") · Focus(true)
· Enter("dismiss")`, twice a frame — so a press delivered inside that window lands on nothing. It is
over in the few hundred milliseconds the plate takes to open, and it is the composer's region, not the
scene's; the scene can only keep the plate still (it does: the plate does not move once open). Worth
knowing before blaming a rule for a press that never arrived. A press that closes a panel does not
reach the window beneath it: that is the trade, and it is the usual one for a popup.

---

## D57 · 2026-10-23 · Lumen, the wallpaper studio: a folder of your own, the live wallpaper, and a source that is never touched

**Asked for:** a wallpaper editor, and the option of setting the folder it reads wallpapers from —
and/or the wallpaper that is on the desk right now.

**Where it lives.** `shell/mooi-wallpaper.plm` with `shell/mooi-wallpaper.luau`, a program of its
own (`mooi wallpaper`, or the bar's own event), for the same reason the settings window is one: it
holds the keyboard exclusively and declares a surface, and a second keyboard declarer in the bar's
scene would replace its `while` (D8/D53). `bin/mooi` snapshots and checks it like the shell, and
links its data folder to mooi's, so `wallpapers.json` and the `palette.json` it paints with are the
shell's own. `lib/wallpaper.luau` is the pure part — the recipe, its vibes, the crop and every
ImageMagick argument — tested under Lua 5.4; `ui/lumen.plm` draws the plates, the compact sliders,
the vibe row and the source tiles.

**The edit.** A recipe is flat numbers: exposure, contrast, fade, saturation, warmth, tint, hue,
zoom, focus x/y, vignette and grain, plus the name of the vibe it matches (or `custom`). The picture
is copied once into a screen-shaped base in `~/.cache/mooi/wallpaper`; every preview and the final
still are cut from that base by `magick`, so an image four times the screen is decoded once and a
slider redraws from the cached base. The crop keeps the point clicked on the canvas where it was, at
the same fraction of the frame, and the preview and the applied still use the same arguments at
different sizes. Nine vibes (Natural, Ferrolume, Dusk, Cold Signal, Sunbleach, Neon Noir, Ash, Blue
Hour, Mono) are whole recipes; choosing one keeps the crop, because the frame is the user's. The
recipe for every source is remembered (forty at most) so the studio reopens on the grade it was left
with. The palette panel runs the same Matugen call the theme watcher would, dry, and shows the two
signals the bar would wear.

**Applying writes a new file, never the source.** `APPLY TO DESKTOP` renders at the monitor's real
size, writes `wall-<time>-<hash>.jpg` in the studio's cache, and asks the wallpaper picker to set
it (`qs ipc call wallpaper set`). The picker draws it and makes the palette, so the desktop and this
studio relight together; the previous applied still is removed when a new one takes its place. The
picture being edited is only ever read.

**The folder.** The source wall used to read `~/.cache/wallpaper-styles/index.json`, the picker's
cache: it was there or it was not, its folder could not be changed, and the studio had no say in
what was offered. It now reads a folder of its own. The folder is typed into the source wall's field
and remembered as `folder` in `wallpapers.json`; `find <folder> -maxdepth 1 -type f -printf '%T@\t%p\n'`
lists it, `lib/wallpaper.parse_find` keeps the pictures by extension (case-insensitive; a PDF or a
text file in the folder is not a tile) and sorts them newest first, and the list pages six by three.
`SHUFFLE` picks from the filtered list; `FILTER` searches by name. On a first run, with no recorded
folder, the studio takes the folder of the wallpaper on the desk, then the picker's
`settings.json` `wallpaperDir` (so the pictures the desktop already uses are there without typing
anything), then `~/Pictures`.

**Only the page is thumbnailed.** A folder of 2,945 wallpapers (what this machine has) must not wear
the disk: `build_hits` queues a `magick -thumbnail 282x158^ -extent` for the tiles that are about to
be drawn and for no others, one process at a time, into
`~/.cache/mooi/wallpaper/thumbs/<hash of path and mtime>.jpg`, and `identify` fills the tile's
`3840 × 2160`. A tile says `DEVELOPING…` until its picture exists. Paging queues the next page and
the queue is generation-stamped, so a folder changed while thumbnails are being made does not paint
a stale tile. On a revisit the in-memory map answers at once.

**The live wallpaper is two presses away.** `LIVE WALLPAPER'S FOLDER` scans the folder the wallpaper
on the desk came from (`readlink` of the picker's source, or its still), and `USE THE CURRENT
WALLPAPER` at the foot loads that picture itself. The field is the truth for `SCAN`: what is written
in it now, whether it arrived by a key or by the text fact it is bound to.

**The arrow bug this found.** In Pleamar an event reaches the logic only when it is declared
`event name ->` ("Something that happens. With `->`, it also reaches the logic"). The studio's first
cut had nine events without the arrow — `open_browse`, `close_browse`, `shuffle`, `use_current`,
`apply_now`, `reset_recipe`, `close_studio` and the two new folder events — so pressing APPLY, RESET,
CLOSE, SHUFFLE or either folder button changed nothing: the scene heard the press and emitted an
event only the scene could hear. All nine now carry the arrow. Worth writing down because the
mistake is invisible in the scene: `pleamar --check` is happy, the zone is painted and the press is
delivered; only the logic never hears it.

**Checked.** Both scenes compile (`bin/mooi check`), **157 unit tests, 0 failed** — three of them new:
the picture-by-name rule and the folder path, `find`'s list (newest first, non-pictures skipped,
junk lines ignored), and the file's new `folder` field plus the thumbnail arguments. Live, on a copy
of the shell in `/tmp` with its own data folder (`XDG_DATA_HOME`) and its own pictures, the studio
was driven through Pleamar's socket:

- it opened on the recorded desktop (the previous `wallpapers.json` had none, so it took the live
  wallpaper's folder): **2,945 pictures, 164 pages**, the live wallpaper's preview and base, no
  errors;
- setting `src_folder` to a two-picture folder and pressing the logic's own door (`emit set_folder`
  after the field was written) gave **2 pictures, 1 page**, `src_folder` and `folder_show` showed
  that folder, and `wallpapers.json` had `"folder": "/tmp/lumen-lab/pics"` — the `.txt` beside them
  was not a tile;
- the tile thumbnails appeared in the cache for that page (two new files), and `identify` reported
  their sizes;
- `LIVE WALLPAPER'S FOLDER` scanned back to the 2,945-picture folder and wrote it to the field;
- `USE THE CURRENT WALLPAPER` loaded the wallpaper on the desk (`wallhaven-5ymzz7.PNG`, source and
  preview both present);
- clearing the field and scanning left 0 pictures on 1 page, an empty field and
  `NO FOLDER · TYPE ONE ABOVE`, while the last good folder stayed in `wallpapers.json` for the next
  start.

The same events were then sent while the source wall was open (`open_browse`, `set_folder`,
`folder_current`, `use_current`), with `PLEAMAR_REGIONS=1` confirming the new zones are committed
where the wall draws them (the folder field, `SCAN` at 657–763 × 143–181, `LIVE WALLPAPER'S
FOLDER`, the filter and every tile). **Not checked live:** a real hand's
press on those controls — in this session Pleamar's fake pointer reports its move and click but the
studio receives neither (the bar did in D55; here the click is logged and no zone answers), so the
controls were exercised through the same emitted events they send; and `APPLY`, which would change
the wallpaper on the desk, so it was left alone. `bin/mooi wallpaper` from the running shell was not
pressed either (the studio was started directly in the lab).

**Left for later:** a folder browser/dialog (the field and the two shortcuts are what there is), and
per-monitor previews when the outputs differ in size — the studio renders at the focused monitor's
size and the picker scales the still.

---

## D58 · 2026-10-23 · A folder picker in Lumen, a framed picture on the bar, and Super + Alt + P

**Asked for:** a folder picker for the wallpaper studio, a bar component that opens the studio, and
a hotkey that opens it too.

**The picker.** The source wall's folder row gains `BROWSE…`, which opens a plate over the wall at
the folder the studio is reading. It walks one level at a time: `find <folder> -mindepth 1
-maxdepth 1 -type d -printf '%f\n'` lists the subfolders, `lib/wallpaper.parse_dirs` sorts them A→Z
(case-insensitive: the order a person expects), and they are drawn twelve to a page with `‹ PREV` /
`NEXT ›` and a page count. A press on a folder enters it; `↑ PARENT` goes up (`lib/wallpaper.parent`,
`/` stays `/`); `USE THIS FOLDER` scans the folder the picker has arrived at and closes it; `CANCEL`
closes without touching the studio's folder. `Return` chooses and `Escape` cancels, and opening the
picker blurs the folder field, so `Return` cannot be taken by the input behind the plate. The
picker's zones are declared after the source wall's, over a full-screen guard, so nothing behind it
answers while it is up.

**The door on the bar.** `wallpaper` joins `lib/barlayout`'s catalogue as a 32 px module, with
`shell/icons/wallpaper.svg` (a framed picture, a horizon and a sun) and the same press treatment as
the other doors. Its press emits `open_wallpaper`, which the shell already answers by starting
`mooi-wallpaper.plm` (a program of its own), so the bar needs no second path to the studio. It is in
`DEFAULT.right` beside Quick notes, which means a fresh settings file starts with it on the bar. A
bar that was laid out before this does not lose its arrangement: the module is on the **shelf** in
edit mode (`Super + Alt + E`), and dragging it onto the bar places it where it is let go — the same
rule as every module, because `bar.right` is the user's, not a list the shell appends to behind
their back. Its shelf name is in `shell/bar.luau`'s NAMES (which also gained Quick notes' name, a
gap it had), and its Layout-page name in `shell/mooi-settings.luau`'s NAMES, which was missing
Quick notes' name too.

**The key.** `keys.wallpaper`, default `SUPER + ALT + P`, is a setting like the others: it is added
to `lib/desktop`'s ACTIONS as `{ key = "wallpaper", cmd = "wallpaper", name = "Wallpaper studio" }`,
so `desktop.file` writes `{ "SUPER + ALT + P", "wallpaper" }` into `hypr.lua` for Hyprland's start
and mooi applies it live, and `bin/mooi wallpaper` is the command it runs. The settings window's
Keys page gains the row, with the same capture and clash warning as the others, and the settings
schema gains the field, so a settings file written before it simply gets the default.

**The generator.** `tools/gen-settings.py` owns `shell/mooi-settings.plm`, `lib/settings_index.luau`
and edit mode's per-module grips in `shell/mooi.plm`; its `MODULES`, `NAMES` and `KEYS` lists were
updated and the tool run, rather than the four files edited by hand. The module order puts
`wallpaper` after `notes` (index 27), so no existing edit-mode index moved, and the generated
`pick(…)` lists carry `xs_wallpaper` / `ws_wallpaper` by themselves. The hand-written pick lists
(the helix's frame, the frames and dividers, the drag ghost's width) were given the new module in
the same place.

**Checked.** All three scenes compile (`bin/mooi check`), **159 unit tests, 0 failed** — one new,
which asserts the module is in the catalogue and the default bar, that the key file carries
`{ "SUPER + ALT + P", "wallpaper" }`, that `desktop.ACTIONS` has the command, and that
`config.defaults().keys.wallpaper` exists. The picker was driven live in a `/tmp` copy of the shell
with its own data folder: a test folder of 14 subfolders reported `2` pages and `14 FOLDERS`; `NEXT`
moved to page 2; entering a subfolder and choosing it read that folder; `Return` chose the folder
the picker was in (`picking` false, the folder in `src_folder` and `wallpapers.json`); `Escape` closed
the picker and left the source wall open.

**The whole studio, driven live.** A later run pressed and typed through Pleamar's own agent
(`press`, `drag`, `type`, `key` — which enters the zones as a hand does) in a fresh `/tmp` copy with
four pictures, a text file and two subfolders. It confirmed: the live wallpaper's folder on first
run and the `.txt` skipped; a tile press loading its picture and rendering a 1600 × 900 preview;
**all twelve sliders** (exposure, contrast, fade, saturation, warmth, tint, hue, zoom, focus X/Y,
vignette, grain) saved at the value they were set to; all nine vibes whole recipes (MONO = 0
saturation, 8 grain); RESET back to Natural; a vibe keeping the crop; the picker's A→Z rows,
`↑ PARENT`, `Return` choosing and `Escape` cancelling; the filter matching case-insensitively;
`SHUFFLE`, `LIVE WALLPAPER'S FOLDER`, `USE THE CURRENT WALLPAPER`; the empty, missing and cleared
folders reporting themselves instead of failing; only the page's thumbnails made; the palette panel
reading a real Matugen palette from the preview; **APPLY** writing a 1920 × 1080 still (RMSE 0.0018 against
the preview resized to the same size, i.e. what was seen is what was applied), the old still removed,
and the folder, picture and grade restored after a restart. The real picker was then driven on the
desktop itself: the applied still became `~/.cache/current_wallpaper`, and setting the original
source back restored the links.

**Found and fixed on the way:** the Apply button read `pick(applied, "APPLIED ✓", "APPLY TO
DESKTOP")`, and `pick` indexes from 0 — so it said APPLIED ✓ *before* anything was applied and
APPLY TO DESKTOP after. The two are swapped. Nothing else in the studio used `pick` this way.

**And the picture itself did not show.** `image prev = from prev_file, 1, 1` (and the source's
`srcpic`) declared the image's cell as **one pixel**, and an image is fitted into that cell and then
stretched to the `size:` it is drawn at. The preview and the source were therefore one averaged
pixel covering the screen — the wallpaper's colour, none of its picture — while the chrome and the
sliders worked. The file was right all along (1600 × 900, the base 2880 × 1620), which is why the
run of the logic and the still on disk looked correct. Both are declared `1920, 1080` now; a
screenshot with the studio open shows the chosen picture, and choosing another tile replaces it with
that picture's preview.

**The bar and the key, live.** mooi was restarted from the repo (`bin/mooi start`, which snapshots
and binds), the module was placed beside Quick notes in this machine's own `bar.right` (an older
layout, so it was on the shelf), and the running bar was pressed on it: the studio opened (and
`bin/mooi wallpaper` did the same). `hypr.loaded` gained
`SUPER + ALT + P=wallpaper` on the restart, so the key is registered by `custom/mooi.lua`; a
physical press of it was not made. A real hand's press (a mouse via the compositor) on the new
controls was not made either — the agent's press is the same zone path, but not the pointer.

## D60 · 2026-10-23 · Lumen reads a picture's background, and sets a matte and a backdrop

**Asked for:** something has to detect the picture and its background, so its background colours
and effects can be changed. Two things were meant ("matte and backdrop"), so both are here: a
**matte** the picture is inset into, and a **backdrop** that fills it — black, the picture itself
out of focus, or a colour read from the picture's own edges.

**The reading.** `lib/wallpaper.edge_args(source)` is one `magick` pass over a 96 × 54 copy of the
source; `-format` asks for `%[hex:p{x,y}]` at **eight points** — the four corners and the four edge
midpoints — and `edge_colours` (pure, so `tests/unit` runs it under Lua) averages them into three
colours: the corners, the edges, and all eight. Three, not one, because a picture's top edge is
often its sky and its bottom its floor: the user chooses which belongs behind it. The read happens
in `shell/mooi-wallpaper.luau` once per source, **before** the preview is drawn, so a recipe that
already has a backdrop arrives in the new picture's colours and never the last picture's. The three
hexes are published as `text.bg_hex0..2` (to read) and as nine `bg_c*_r/g/b` facts (to draw the
swatches in the picture's own colour — a fact is the only way the logic hands a colour to a scene).

**The recipe.** Four fields: `matte` 0–25 % (0 is none, the picture full-bleed, so every existing
still renders byte-for-byte as before), `bg` 0 black / 1 the picture / 2 corners / 3 edges / 4 both,
`bg_blur` 0–100 % and `bg_dim` 0–100 %. `M.args` composes when the matte is non-zero: the fill (a
solid `xc:#…`, or the picture resized to cover, blurred, and dimmed) is made first at the screen's
size, the graded picture is made at the inset size, and the two are composited centred. The same
arguments make the preview and the still, so **APPLY carries the matte too** — the still handed to
the wallpaper picker is the composited file, not the picture. `bg` has no slider: the BACKDROP tab's
five swatches set it. Choosing a backdrop while the matte is 0 opens the matte to **6 %**, because a
backdrop with no matte is hidden under the picture and a control that appears to do nothing is
worse than one that moves the thing it names.

**The tab.** `M.TABS` gains `BACKDROP` (the fifth), the dock gains the tab, and the row beside it
is five `BGMode` swatches (`ui/lumen.plm`): each shows the colour it will use — black, a dim steel
for the blurred picture, or the detected hex in its own swatch — with its name and hex, a lit rule
for the one chosen, and a `toggle` zone with `selected` for the keyboard ring. The tab's three
sliders (matte, blur, dim) come from the same field table as every other tab, so `set_value`'s
`code * 1000 + offset` path is unchanged; `set_tab`/`step_tab` now run over `#W.TABS` instead of a
hard-coded four.

**Checked.** `bin/mooi check`: all three scenes compile (the studio now 214 properties, 79 zones)
and **161 unit tests, 0 failed** — two new: the matte's arguments (no backdrop without a matte, a
black fill, an inset of `1420x720!` for a 10 % matte on 1600 × 900, a `#203040` fill, the blurred
fill's `-blur 0x7.8` and `-colorize 26%`, and the clamp), and the edge reading (eight points, the
96 × 54 copy, corners/edges/both averaged, and fewer than eight refused). `tests/wallpaper.sh` is
**21 checks, 0 failed** live: a framed 800 × 450 picture (a pale field in a `#204060` frame) is
chosen; `bg_hex0` and `bg_hex1` read `#204060`; BACKDROP is tab 4; choosing CORNERS sets `bg_sel`
to 2 and draws a new preview whose matte samples 31,64,95 with the picture still sitting white on
it (240,240,240); APPLY renders a 1920 × 1080 still with that same matte, so the still is what the
tab showed. The rest of the studio's live checks — the picture on screen (RMSE 0.0037), the source
view, the folder, the sliders — still pass in the same run.

## D61 · 2026-10-23 · Keying a picture's own background out, keeping its edges, and the studio's defaults

**Asked for:** change the picture's background itself, not only the frame round it; keep what was
read; and give the studio its own settings. Three pieces, one family — *the picture knows its
background, and so does the shell*.

**The key.** `key` (a switch) and `key_fuzz` 0–45 % (a slider) join the recipe. When it is on,
`M.args` grades the picture with `-fuzz <fuzz>% -transparent <edge>`, where `<edge>` is the colour
read from the picture's **corners** (`bg.edge`), so whatever the picture's own background is
becomes transparent; the backdrop is composited behind it, full size when there is no matte. Unlike
choosing a fill, keying needs **no** matte — the picture's own background is the hole the backdrop
shows through — so the switch leaves the framing alone. The grain is applied
`-channel RGB +channel` so it cannot eat the transparency it was keyed with. The transparency is
made **before** the grade (warmth, saturation and a vignette move colours), so the fuzz looks for
the colour the file actually has. The BACKDROP tab gains a `KEY OUT` toggle beside the five fills
(`KeyToggle`, a switch with ON/OFF and a lit rule), and the fuzz becomes the tab's fourth slider
(matte, blur, dim, fuzz — the dock's four fit at 342 px apart). The fill is whatever the backdrop
is: black, the blurred picture, or a detected colour, so keying and the fill are one choice.

**The cache.** The three colours are kept per source in `wallpapers.json` (`M.remember_edges`,
`M.edges_of`, capped at `RECIPES_MAX` and pruned oldest-first like the recipes). Opening a picture
draws those swatches **at once** and then reads the file again: if the colours still hold the note
says `CACHED`, if they moved it says `READ NOW` and the new ones are kept. A recipe that uses a
detected colour therefore never flashes the last picture's colour while ImageMagick runs.

**The defaults.** `wallpaper.matte` (0–25), `wallpaper.backdrop` (`black` / `picture` / `corners` /
`edges` / `both`), `wallpaper.key` and `wallpaper.fuzz` (0–45) join the settings schema, with
`lib/setters` codes **appended** after the 116th so no existing control's number moved (they are
316–319). `tools/gen-settings.py` gained a **Wallpaper** page (DESKTOP group, before Sound): the
matte slider, the five backdrops, the key toggle, its fuzz, and a note that keying needs the edges
read. The page was regenerated, not hand-written. A picture with no recipe of its own now opens on
`studio_defaults()` — the settings' matte, backdrop, key and fuzz — and RESET goes there rather than
to bare neutral; a vibe change keeps the whole backdrop (and the crop), because a vibe is the
picture's look and the backdrop is its frame.

**Found on the way: the studio had never read its settings.** `read(name, kind)` called
`sys.ask("files.read", name, kind)` with `kind` nil; the service refuses a third argument that is
not a string, the `pcall` swallowed the error and returned `nil`, so `settings` was always the
defaults — the palette panel's scheme, signal and contrast were ignored too. It now calls the
two-argument form when there is no `kind`, as `mooi-settings.luau` does. Live before the fix: a
`settings.json` with `matte: 10` still opened at 0 %; after it, `10 % matte, black`.

**Checked.** `bin/mooi check`: all three scenes compile (settings now 2005 properties, 732 zones;
the studio 216 properties, 80 zones) and **164 unit tests, 0 failed** — three new: the key's
arguments (the fuzz and the transparent colour, a full-size fill with no matte, no colour read →
no key, `-channel RGB` around the grain, `KEYED` in the summary), the edge cache (kept, read back
from the file, a colour that is not one refused, two colours refused, the oldest dropped), and the
new settings (defaults, and codes 316–319 setting matte, backdrop, key and fuzz without moving any
other code). `tests/wallpaper.sh` is **31 checks, 0 failed** live: a `#204060` field with a white
subject is chosen, KEY OUT turns on, and the preview's field samples 0,0,0 while the subject stays
240,240,240; the edges are in `wallpapers.json`; a restarted studio with `wallpaper.matte = 10`
opens the *new* picture with a black matte (0,0,0) and the picture inset (240,240,240), and picking
it again reports `CACHED`. The settings page itself was driven live in its own scene: the page lit,
the four facts read their defaults, and setting 12 / corners / on / 33 wrote
`"wallpaper": {"backdrop": "corners", "fuzz": 33, "key": true, "matte": 12}` to `settings.json`;
a screenshot shows the page in the rail with the matte, the five backdrops, the key switch and its
note, and no row colliding with the rail's foot. Not checked: a real hand's press on the new
toggle (the agent's press is the same zone path), and keying a photographic background — the
picture driven was a flat field, which is what makes the pixel check exact.

## D62 · 2026-10-23 · The background is what the picture's edge is joined to, and any colour can fill it

**Asked for:** not a colour match but the picture's **background parts** found and recoloured — "a
picture with an alien in the centre and the rest white, and I should be able to change the
background to whatever colour I want" — and a folder browser that can reach the folder the pictures
are actually in. Two things, both about *the thing you mean, not the thing that looks like it*.

**The key is a flood fill now.** D61 keyed by colour: `-fuzz <n>% -transparent <corner colour>`
took **every** pixel near that colour, so a white eye inside the subject went with a white field.
`M.args` now seeds a flood fill at the **eight border points** — four corners and four edge
midpoints — with `-alpha set -fuzz <n>% -fill none -draw "alpha x,y floodfill …"`. What is filled is
the background the edge is **joined to**; the subject's own white eye is not joined to it and stays.
The seeds are pixels, not a colour, so keying no longer needs the edge read at all (it works on a
picture whose corners were never read), and it is done **last** in the grade so the vignette's
composite and the grain cannot put the transparency back.

**Any colour.** `bg` gained a sixth fill, `custom` (index 5), with `bg_custom` — a `#RRGGBB`
validated in `M.clean` (lower-cased; anything else falls back to `#808080`, so the fill is never
nothing) and kept in the picture's recipe beside the rest. The BACKDROP tab gains a **CUSTOM**
swatch drawn in the colour it will use (facts, as every colour in these scenes is) and a small hex
field: type `#c02040`, press Enter, and the picture's own background becomes that. Choosing a fill
opens the matte to 6 % only when the picture is **not** keyed — a keyed picture already has a hole,
so it stays full-bleed.

**Enter, handled where the text is.** A `submit` hands its text to the logic handler and the field's
own text is written back *after* the scene's `on submit` has already fired, so a scene binding that
only `emit`s reads the previous value. Enter in the folder field, the colour field and the picker's
path is now the logic's own (`submit:src_folder`, `submit:bg_custom_hex`, `submit:pick_typed`), which
is given the text. The picker's Return binding is gone with it: Enter in the path goes to the path,
and choosing is the button.

**The folder browser goes anywhere.** Every `find` in the studio is `find -L`, so a folder that is a
**link** (`~/Pictures → /mnt/disk/Pictures`) is listed by the picker and read by the source wall —
before, a link was neither a directory to `find -type d` nor walked as a start point, so the folder
simply read as empty and could not be browsed to. The picker gains a **path field** with GO (and
Enter): `~`, a name under home, or a whole path, taken as it is; **HOME**, **PICTURES** and
**ROOT /** in one press; ten rows to a page to make room for them. A folder that cannot be read is
not a dead end either — the studio shows **home** instead and says so, so a first run on a machine
without `~/Pictures` still finds pictures. `~` expands only as `~` or `~/…`: `~other` is a name.

**Checked.** `bin/mooi check`: all three scenes compile (the studio 222 properties, 85 zones) and
**164 unit tests, 0 failed** — the key's test now reads the eight flood-fill seeds and their
coordinates, that no `-transparent` remains, that the flood fill comes after the grain and the
vignette, and that a custom colour reaches the fill; the custom colour's validation and `~` rules
are new too. `tests/wallpaper.sh` is **49 checks, 0 failed** live: a creature on a `#f4f4f4` field
with white eyes is keyed, `#c02040` is typed as the fill, and the field samples 191,32,64 while the
eye stays 255,255,255 and the creature 16,16,16 — the property a colour key could not have; the
colour is in `wallpapers.json`; the picker's path field goes to a typed folder, PARENT works,
PICTURES jumps to a **symlinked** `~/Pictures`, lists the folder behind the link, enters it, and USE
THIS FOLDER reads its picture. Not checked: a hand's typing into the two new fields (the harness
sends the same `text` and `submit` the input does), and a photographic background — flood fill needs
the background to be one region, which a busy photo is not.

## D63 · 2026-10-23 · A palette for the backdrop, a picture that keeps its quality, and an undo

**Asked for:** colours picked from **swatches**, not typed; images that do not lose quality; and the
studio made more capable. The palette and the lossless path are one idea — *the colour you choose
and the picture you keep are both exact* — and the undo is what makes trying things safe.

**The palette.** `M.SWATCHES` is nine colours: **black** and **white** as they are, and seven of the
shell's own roles — `ink`, `hull`, `well`, `phos`, `trace_lit`, `ember`, `flare` — resolved from the
same `lib/ferro` palette the bar wears, so the swatches change with the wallpaper's colours and are
always the theme's. They are handed to the scene as a `model` (`rows of r, g, b, hex`) rebuilt in
`paint()` whenever the palette is, and drawn by a new `ColorSwatch` (the colour, a lit rule when it
is the fill). A press sets `bg` to 5 and `bg_custom` to that hex, so the **hex field follows the
swatch** and picking and typing are one thing; the field still takes any `#RRGGBB` of its own, and
the five fills read from the picture are unchanged. The mode row and the palette row share the
BACKDROP tab (the swatches sit under the modes; the sliders moved down 12 px to make the room).

**Quality.** The base every preview and still is cut from is now a **lossless PNG** (it was a JPEG at
94), resampled with **Lanczos** named rather than left to the build's default, so an edit starts from
the picture and not from a generation of loss. The preview and the source view are JPEGs at **95
with `-sampling-factor 4:4:4`**: full-resolution colour, so a flat fill or a hard edge stops smearing
its hue into its neighbours the way the default 4:2:0 did. The **still that goes on the desktop is a
PNG** — `M.args` now decides the output by its extension (`M.is_png`), so nothing is thrown away on
the last step; thumbnails stay JPEGs at 88 and 4:4:4, because they are tiles.

**Undo.** The recipe keeps a history (`hist`, `future`, at most 50 deep) that belongs to the picture
and is cleared when another is opened. One entry is kept per **burst** of edits — the first change
after 650 ms of quiet stores the state it started from — so UNDO goes back to before a slider's drag
and not to its last millimetre. UNDO and REDO buttons sit beside RESET (lit only when there is
something to take back or put forward) and `Ctrl+Z` / `Ctrl+Y` do the same; RESET is itself undoable.

**Checked.** `bin/mooi check`: all three scenes compile (the studio 244 properties, 96 zones) and
**166 unit tests, 0 failed** — the quality test reads a PNG output with no `-quality` and a
`png:compression-level`, a JPEG preview with `4:4:4` and 95, a lossless base with Lanczos and a
thumbnail at 88; the palette test reads nine swatches, seven of them roles, each with a name and one
colour. `tests/wallpaper.sh` is **58 checks, 0 failed** live: on the creature whose background was
keyed to `#c02040`, the first swatch is pressed and the field becomes `#000000` and the picture's
background **is** black; UNDO returns the preview to 191,32,64 and REDO puts the swatch back; the
applied still is a **PNG** at 1920 × 1080 whose matte samples **exactly** 32,64,96. `PLEAMAR_REGIONS`
on a copy opened on BACKDROP lists the nine swatches at their places (177–537, 40 px apart) and the
mode row above them with no overlap. Not checked: a hand's press on a swatch (the agent enters the
same zone), and the palette after a wallpaper change — its colours come from the same `paint()` the
bar's do, which is what the rest of the shell already relies on.

## D64 · 2026-10-23 · The board is a program of its own, and a press outside it closes it

**Asked for:** split the board out of the bar's scene, and make a press outside it close it.

**Why split.** The board was a `surface` inside `mooi.plm`: its facts, models, plate, columns, card
zones and key bindings lived in the bar's scene, and its keyboard clause had to be folded into the
bar's — a second declarer *replaces* the scene's `while` condition (D8), which is how the bar once
lost typing altogether (STATUS 2026-10-23). It was a whole application drawn inside the bar. The
settings window and the wallpaper studio are already programs of their own for exactly this reason,
so the board becomes one: `shell/mooi-board.plm` + `shell/mooi-board.luau`.

**What moved, and what did not.** The scene keeps only the board's own drawing (it was already
`ui/board.plm` + `shell/board.luau` + `lib/board`, none of which changed in substance) and gets its
own full-screen surface with `keyboard: exclusive` — no clause to share. `shell/mooi.luau` loads the
board's logic for the badge only: how many cards, how many late, from `board.json` through
`lib/board`; a note sent from the pad is a card added to the file, which the board's watch picks up.
`bin/mooi` links the program's data folder to mooi's (as for the studio), so `board.json` is the
shell's one file. The bar starts the program on `board_show` — a frame later, so it has let go of
the keyboard — and closes it by `--say mooi-board quit` on the same request (`mooi board`, the pad's
rail, its key); the child's exit refreshes the badge, and a failure is logged with its first errors.

**The outside press.** The board's scene brings its own plate: `baway`, a full-screen zone under
everything, emits `close_board` on a press (the ×, Escape and the bar's own toggle do the same). The
logic drops `board_in` first — so the board folds away the way it came — and runs
`pleamar --say mooi-board quit` 240 ms later; the program ends and the compositor gives the keyboard
back to whatever is under it. Nothing is left behind: no hidden surface holding the keyboard, no
second scene answering to `mooi`.

**Checked.** `bin/mooi check`: the bar compiles (7658 properties, 2150 zones — the board's zones are
gone from it) and the board (127 properties, 141 zones), 166 unit tests, 0 failed.
`tests/board.sh` is **11 checks, 0 failed** live: the bar reads mooi's `board.json` for its badge
(3 cards), `emit open_board` starts the program and it reads the same file through the link, the
same event closes it, a press on the desktop at 60,60 (outside the plate, where `PLEAMAR_REGIONS`
says the surface covers the screen) **Presses baway and closes it**, the program exits by itself,
a press at 1400,500 on its plate leaves it up, and Escape closes it.

A note on the pointer: `--mouse` with a move of its own leaves every zone in this session (the
scene gets the leave and no enter for it), so the press is sent without a move and the real pointer
is parked where it should land (`ydotool`). The same press reached a card zone in the board before
the change, so the zone → `emit` path is the one the scene already used.

## D65 · 2026-10-24 · Control Nexus is a program of its own, opened from the Arch mark

**What it is.** Control Nexus is the system command centre: one full-screen program
(`shell/mooi-nexus.plm` + `shell/mooi-nexus.luau`) opened from a `nexus` bar module carrying the
Arch mark. It shows real service readings and bounded local reads (distro/version, kernel,
uptime, CPU model and load with core count, memory, root storage, network rates, temperature,
DRM GPU busy where exposed, the focused Hyprland display), keeps the player's text fields itself,
and is the only place that calls the system for volume, brightness and media transport. A
**System Overview** view toggles from the header and gathers the read-only facts with
**COPY DIAGNOSTICS**; **System Identity** edits the display name and imports avatar/banner images
through `zenity` → `mooi identity`. A refused control is reported in the footer; a missing
sensor says `N/A`.

**Why a program, not an island.** The bar scene has one keyboard clause, and Pleamar's compiler
takes the scene's `while` from the last surface that declares one — an island that wanted the
keyboard would silently replace the bar's condition (D8, D52). Nexus also needs a full-screen
outside-press layer, a free-floating plate and, later, a layout editor. The bar keeps the anchor
and the badge (`nexus_open`); the program owns the room. `bin/mooi nexus`, the mark, ×, Escape or
an outside press (unless pinned) close it; the logic waits 240 ms before quitting so the
compositor gives the keyboard back to what is under it.

**Shell access is an allowlist, never an interpreter.** `permissions.run` names `cat`, `df`,
`uname`, `hostname`, `sensors`, `hyprctl`, `mooi`, `zenity` and `pleamar`; the optional GPU probe
reads fixed `/sys/class/drm/card{0,1,2}/device/gpu_busy_percent` paths instead of running `sh`.
`MOOI_SAFE=1` refuses identity writes as it does every other settings write. Nothing is
interpolated into a command line, and readings are sampled on a two-second loop, not per frame.

**Checked.** `bin/mooi check`: all five scenes compile, **182 unit tests, 0 failed**. In an
isolated runtime (temporary HOME/XDG) the plate reported EndeavourOS, kernel
`7.2.11-arch1-1`, uptime, CPU load with 12 cores, memory, 80 % root disk, `eDP-1 · 1920x1080 ·
60 Hz · 1.00x`, GPU 13 % and 50 °C; pin and the Overview toggled; Escape ended it with no runtime
errors. Saving an identity under `MOOI_SAFE=1` was refused and left `settings.json` untouched;
with writes enabled the name and pinned state survived a restart. The bar-trigger lifecycle was
reproduced in a temporary copy of `shell/` with the bar renamed `mooi-lab` (so the live mooi was
untouched): two rapid activations started exactly one Nexus, the same trigger closed it and
cleared the bar, and reopening worked. **Repaired on the way:** the branch consolidation had
committed unresolved conflict markers in the Nexus scene, logic and next-phase document; the
logic also called `env()` before declaring it, and `sysinfo.cpu_cores` split `/proc/stat` on a
literal `\n`. Not checked: a real pointer on the new Overview controls, the Overview on screen at
every plate width, and multi-monitor placement.

**To change back.** Remove `nexus` from `DEFAULT.right`, delete `shell/mooi-nexus.*` and unwire
`open_nexus` / `nexus_open` in `shell/mooi.luau` and `bin/mooi`.

## D66 · 2026-10-24 · Nexus routes audio and powers the Bluetooth radio from its own view

**What it adds.** A second view in Control Nexus, reached from the **AUDIO** button beside
**SYSTEM**: press the **OUTPUT** or **INPUT** row to make the next device the default, wheel the
**MICROPHONE** row to set its level and press it to mute, and press the Bluetooth card to power
the radio on or off. The view and the System Overview are mutually exclusive; pressing the
active view's button returns to the controls. Device names are the audio service's own
(`outputs` / `inputs`), the microphone is `audio.input` / `input_muted`, and the radio is
`bluetooth.present` / `powered`; an absent adapter reads `N/A`, an empty device list reads `—`,
and a refused `sys.call` is reported in the footer instead of assuming success.

**How it talks to the system.** `sys.call("audio.default", id)` for routing,
`audio.input` / `audio.input_mute` for the microphone, and `bluetooth.power` for the radio; the
scene never fabricates a device or a state. `lib/nexus.next_device` picks the id after the
current default and wraps (the first device when none is default), and is unit-tested. The
permission list gains `bluetooth.*`; `audio.*` was already there.

**Checked.** `bin/mooi check`: all five scenes compile, **183 unit tests, 0 failed**. In an
isolated Nexus run the view named the real output and input devices, read the microphone and
Bluetooth state, and toggled between the audio and system views with no runtime errors. The
write calls themselves were left unfired so the user's sound server and adapter were not
changed; Bluetooth device connection, the device list and app volumes are not built yet.

**To change back.** Remove the audio group and `nx_audio` handlers, drop `bluetooth.*` from the
Nexus permissions, and remove the AUDIO button.

## D67 · 2026-10-24 · Nexus lists the Bluetooth devices and connects to one

**What it adds.** The AUDIO view carries the devices the `bluetooth` service knows, below the
radio card: up to five rows, in the service's own order (connected first), each with the device's
name and `CONNECTED` / `PAIRED` / `NEW`. A press on a row calls `bluetooth.disconnect` for a
connected device and `bluetooth.connect` for any other, with that row's address; `NO DEVICES
KNOWN` when the service reports none. With no adapter the card still reads `N/A` and no rows are
drawn. The model keeps up to eight records while five are drawn, because the plate's room is
what decides the list's length, not the service's.

**States as values, not presence.** A model field declared `bool` is a presence claim in the
scene, and a row has to compare two states (`d.connected == 1`). `lib/nexus.bt_rows` therefore
turns `paired` and `connected` into 0/1, gives a nameless device `Unknown device` to draw, keeps
the row's address for the press, skips a record that is not a table, and stops at the model's
cap. It is pure and unit-tested; the service's records stay on the logic side so a press uses the
address whose name was shown.

**The editor over the views.** The identity editor used to be declared before the view switch, so
a view drawn later covered it. It now comes after every view (including the Bluetooth list) and
carries a catcher zone over its own plate: a press inside the editor no longer reaches the view
behind it.

**Audio cycling reads back.** `sys.call("audio.default", id)` can be accepted while the sound
server keeps its old default (WirePlumber may restore it). The press now asks the service again
400 ms later and reports `OUTPUT SWITCH` / `INPUT SWITCH` in the footer if the name did not
change; a list with nothing to cycle to says `NO OTHER OUTPUT` / `NO OTHER INPUT` instead of
silently doing nothing.

**Checked.** `bin/mooi check`: all five scenes compile, **184 unit tests, 0 failed** (the
Bluetooth row mapping, its cap, its nameless row and its non-record skip). In an isolated Nexus
run the model held the real three known devices, the first row read `Galaxy A16`, the service
reported `present = true` / `powered = false`, and the audio view opened and closed with no
runtime errors in the bar log. The connect/disconnect press was **not** fired, so the user's
adapter was left as it was. `tests/nexus.sh` now launches its bar copy as `mooi-lab` with its own
socket, so it can run beside the live mooi: **24 checks, 0 failed**, including the device count
and the first row's name. Not checked: a real connect or disconnect (BlueZ takes seconds and the
row keeps the service's last report until the change arrives), and a hand's press on a row.

**To change back.** Remove the `btdev` model, its group and the `nx_bt_dev` event and handler;
then `bt_rows` from `lib/nexus` and its unit test.

## D68 · 2026-10-24 · Nexus mixes application streams, tightens the overview, and imports identity images again

**What it adds.** A third view, **MIXER**, beside SYSTEM and AUDIO. It lists the streams the
`audio` service reports, up to seven: the name, what it is playing (when the stream says),
its percentage or `MUTED`, `PLAYING` / `PAUSED`, and a volume bar. The wheel moves the stream
in 5 % steps and a press mutes or unmutes it; `NO AUDIO STREAMS` when the server reports none.
The **System Overview** keeps the same facts but draws them on 22 px rows instead of 27, and
the room that frees carries three readings that were already collected: **CPU LOAD**,
**TEMPERATURE** and **NETWORK** (RX ↓ · TX ↑). `lib/nexus.app_rows` clamps a stream's volume,
keeps its id for the press, names an unnamed stream, skips a non-record and is unit-tested.

**Identity was never importing anything.** In `bin/mooi` four parameter expansions had been
written `\${…}` — the action (`${1:-help}`), the `MOOI_SAFE` guard, the name-length test and
the image argument. The backslash made each one a literal, so `action` never matched a case and
every `mooi identity` command printed its usage; the safe-mode guard and the 48-character test
were broken in the same way. They are shell expansions again. The editor also now checks what
`files.write` returns, not only whether `sys.call` threw: a refused write is reported as a
failure rather than announced as saved.

**The scene could not run `mooi`.** The image picker and **COPY DIAGNOSTICS** run `mooi …` by
name. `bin/mooi` sets `MOOI_BIN` to an absolute path for Hyprland's bindings, but Pleamar's
`run:` permissions name the command, and an absolute path is refused unless that exact path is
declared. The launcher now puts `$root/bin` first on `PATH` before it runs the scene, so the
keeper, the bar and every program it starts resolve `mooi` by name; `tests/nexus.sh` does the
same for its temporary bar.

**Checked.** `bin/mooi check`: all five scenes compile, **185 unit tests, 0 failed**. In an
isolated run (writes enabled) the identity header read the imported name, `nx_avatar_on` and
`nx_banner_on` were true, the editor's save persisted `Studio Rig 3`, a `mooi identity avatar`
run while the scene was up changed the path the scene watched, and a diagnostics copy reached
the clipboard. `tests/nexus.sh`: **29 checks, 0 failed**, including the mixer view and the
Bluetooth list. The live session was restarted on the new snapshot: the scene's `PATH` carries
`bin/mooi`, `bin/mooi nexus` opened, the Nexus read the three known Bluetooth devices
(`Galaxy A16` first), the mixer and overview opened with the real state, the views stayed
exclusive, and Escape closed it and cleared the bar. A playing stream then gave the mixer a real
row (`kew`, 78 %, `PLAYING`) with no runtime errors. Not checked: a real hand on the mixer rows
or the identity editor, the zenity dialog itself, and a visual pass on the denser overview.

**To change back.** Remove the MIXER view, its model, events and handlers; restore the overview
row spacing and the three extra rows; the identity fix stays (the escaped expansions were a bug).

## D69 · 2026-10-24 · Nexus steps under the image picker and keeps its editor's presses

**The picker's window.** `zenity --file-selection` is an ordinary toplevel, and the Nexus is a
full-screen layer surface at `level: overlay` holding the keyboard. The picker's dialog would
be drawn under the plate and could not be typed into. While `nx_picking` is true the surface
drops to `background` and gives the keyboard up (`keyboard: exclusive while nx_picking == 0`),
and the plate is hidden; the fact goes false when zenity answers (or fails to start), and the
plate is drawn again. The `nx_picking` fact also gates the outside-press layer, so the press
that dismisses the dialog is not read as a press outside the Nexus.

**The editor catches its own presses.** The identity editor is drawn last, after every view and
the Bluetooth rows, and carries a catcher zone over its plate, so a press on a field, a button
or the plate itself never reaches the view drawn underneath.

## D70 · 2026-10-24 · A replaced identity image gets a new file name

**The picture was read once per path.** Pleamar's `image … = from text` reads the file the text
names; an import that overwrote `identity/avatar.jpg` left the text unchanged, and the plate
kept the old decode. A settings watch that saw the same path did not help either: the path had
not changed. The user could import a new picture and still see the old one, or nothing.

**The import owns a fresh name.** `bin/mooi identity avatar|banner` now writes
`identity/avatar-<epoch>-<pid>.<ext>` (and the same for `banner`), removes the previous file of
that kind (both the old canonical `avatar.*` and the versioned names) and points settings at the
new name. Every import therefore changes the text the scene reads, and the scene's existing
watch loads the new picture while the Nexus is up. `remove` and `reset` clear both spellings.

**Checked.** `bin/mooi check`: five scenes compile, **185 unit tests, 0 failed**.
`tests/nexus.sh`: **38 checks, 0 failed**, including a second import writing a different file
name, the imported file existing, and the first one being gone. Live, with the Nexus up: a
`.jpg` avatar replaced by another `.jpg` changed on the plate without a restart; the same for a
`.jpg` banner, then the originals restored and shown again. The whole picker path was driven
through the real dialog (`zenity` → `mooi identity avatar`): the dialog appeared above the
Nexus, the chosen file imported, `AVATAR IMAGE UPDATED` appeared, and the new avatar was drawn
with the editor still open. The face's own `mooi` resolution still comes from `bin/mooi`'s
`PATH` (D68); an absolute command path is refused by Pleamar's `run:` allowlist.

**To change back.** Import to the canonical `identity/avatar.<ext>` name again and keep the
scene from expecting a replacement; the old picture will then need a restart to appear.

## D71 · 2026-10-24 · Nexus shows the workspaces and reads the battery's health from UPower

**SPACES.** A fifth header view beside SYSTEM, AUDIO, MIXER and POWER. It draws the first ten
workspaces the compositor reports, two rows of five: the zero-padded id, the window count, and
`CURRENT` or `SHOW`. A press asks `workspaces.focus` for that block's id; the view closes to the
controls only through the header, and the move is the service's to confirm (the Nexus re-reads
the list on its watch). A block sends its **turn**, not the record's value: a copied block cannot
carry a record field out through its press, the same reason the Bluetooth rows send an index, so
the logic keeps the rows it drew and indexes them. `lib/nexus.ws_rows` maps the service's boolean
`active` to 0/1, zero-pads the label, skips a record without a numeric id, and is unit-tested.
The header hides MIXER, SPACES and POWER progressively as the plate unfolds (`cw > 354 / 460 /
570`), so five tabs never run off a narrow plate.

**Battery detail.** The `battery` service carries only `present`, `percent` and `charging`, so
health and the predicted time come from UPower's local report: `upower -e` finds the battery
device, `upower -i` is read for `capacity` (health against design capacity) and
`time to empty` / `time to full`. The collector runs at start and again when the battery service
reports a change. `lib/telemetry.upower` accepts this locale's decimal comma, reads hours or
minutes, and returns nothing it cannot find: a desktop, a missing `upower`, or a battery with no
prediction keeps `HEALTH N/A` / `TIME N/A` (or `ON AC · FULL` when it is charged and the tool
says so). POWER shows the health and the time above uptime. LOCK was already in that view; the
four session actions keep their two-press arming.

**The real pointer.** Earlier synthetic passes used `ydotool click 1`, which is not the left
button (0xC0 is), so they reached nothing and the "unchecked hand" was a test-harness mistake.
With `0xC0` the pointer opened the identity editor, opened the zenity picker, closed the Nexus
with its ×, and showed a workspace with a block. The Nexus's press routing needed no change. The
agent's `press name#k` can address the wrong copy of a repeated zone; a block press was verified
with the pointer, not that form.

**Checked.** `bin/mooi check`: five scenes compile, **188 unit tests, 0 failed** (workspace rows
and two UPower fixtures). `tests/nexus.sh`: **45 checks, 0 failed**, including the SPACES view
opening/closing, the workspace model count and first id, and `HEALTH 81%` / a time line read
from UPower on this machine. Live: the SPACES view drew two workspaces (`01`, `02`), pressing the
current one was reported with no failure, and a pointer press on the other moved the focus to 02
(the session was left on workspace 2). POWER drew `HEALTH 81%` and `ON AC · FULL` and the four
session rows at their boxes. Not fired: LOCK (it would lock the session) and the other three
session actions (they only arm). Not checked: a real discharging prediction on battery, and the
SPACES grid with more than ten workspaces.

**To change back.** Remove the SPACES fact, view, model, event and helper; remove the UPower
collector, its permission and its two texts; POWER returns to its earlier height.

## D72 · 2026-10-24 · Nexus instruments are the user's to arrange, and the banner fills its band

**Instrument layout.** The six live plates (CPU, memory, temperature, root storage, RX, TX) are
now a catalogue the user can arrange. A new **INSTRUMENT LAYOUT** button in the System Overview
opens a panel with one row per instrument: `ON`/`OFF`, and `↑`/`↓` to move it. The plate reads
one fact per instrument for whether it is drawn and one for its slot, so a plate that is put
away leaves no hole: the rest close up, and the media player follows the last row. Turning an
instrument on appends it at the end. `RESTORE ALL` returns the catalogue order.

The saved setting is the list of instruments that are **on**, in order — `nexus.modules` in
`settings.json`. It is checked by a new `ids` kind in `lib/config.luau` (a list of up to eight
ids of letters, digits and `_`), and it has **no default**: a settings file that never carried
one keeps drawing everything, and an empty list is a plate with nothing on it rather than a file
that gets silently refilled. `lib/nexus.modules` takes a saved table as authoritative and drops
strangers and repeats; `layout_action` and `module_rows` are pure and unit-tested. The panel
always lists all six rows in catalogue order (so an empty plate can be filled again) while the
plate itself follows the saved order; a row's press sends its catalogue place, as the workspace
blocks and Bluetooth rows do, because a copy cannot hand a text out through its press.

**The banner, properly sized.** `image … from text, w, h` fixes the *shape of the cell* and the
picture is fitted inside it before the cell is stretched, so a 16:9 photograph dropped into the
plate's 9.8:1 band came out as a 149-pixel thumbnail with empty space around it. The plate no
longer draws the imported file directly. `mooi-nexus.luau` makes one band copy —
`identity/<name>-band.jpg`, 1456×148, cover-cropped with `magick` (centre, `-resize …^` then
`-extent`) — keeps it beside the imported file, and draws that. The imported picture is never
modified; the copy is cached by its name, so it is made once per import, and a new import (which
already gets a new file name, D70) gets a new copy. If the crop cannot be made (no ImageMagick,
a refused command) the original path stays and the plate draws what it drew before rather than
pretending. `magick` joins the scene's `run:` allowlist, and the band is still `N/A`-honest: no
banner means no image.

**What firing the writes found.** With a real `mpv` stream in the mixer, pressing MUTE did
nothing. `lib/nexus.app_rows` kept a stream's id only when it was text, but PulseAudio and
PipeWire report a numeric id, so every row's handle became `""` and the handler returned before
speaking to the sound server. Numeric ids are now kept, and the row's mute/volume work: the
stream read `MUTE: yes` in `pactl`, the service read muted, and three wheel notches moved 63 % to
58 % in both. The Bluetooth write was fired too: the radio was rfkill-soft-blocked, so the
Nexus's power-on was refused (`BLUETOOTH FAILED`); unblocked, the Nexus powered it on and off
again and the connect press reached BlueZ (it answered `br-connection-busy`), but no device was
reachable, so a successful connect/disconnect is still unproven. LOCK and the other session
actions remain unfired.

**SPACES labels.** `pick(i, …)` chooses by place, not by truth, so `pick(w.active, "CURRENT",
"SHOW")` said `CURRENT` on every *other* workspace. Both the label and the block's agent name are
now `pick(w.active, "SHOW", "CURRENT")`; pressing a block moved the session to workspace 1 and
back, with the flags following the compositor.

**Checked.** `bin/mooi check`: five scenes compile, **193 unit tests, 0 failed** (layout
defaults, actions, rows and slots; numeric stream ids; battery detail text). `tests/nexus.sh`:
**58 checks, 0 failed**, including a banner imported through `mooi identity` and drawn as a
`-band.jpg`, and layout hide/reorder/restore in the temporary environment. A discharging
fixture (a fake `upower` in an isolated run) drew `HEALTH 81%` and `2H 18M LEFT` on POWER.
Live: banner band drawn and filling the header; layout panel opened, reordered and saved; mixer
mute and volume verified against `pactl`; radio powered on and off through the Nexus; SPACES
switched workspaces. Not checked: a successful Bluetooth connect/disconnect (no reachable
device), more than ten workspaces live (it needs eleven occupied workspaces; the cap is
unit-tested), LOCK and the session actions, and a pointer pass on the new panel.

**To change back.** Remove `nexus.modules` from the schema and the layout block from the logic;
drop the facts, events, panel and `NInstrument` gating. For the banner, remove `sync_banner`, the
`magick` permission and the band copy files under `identity/`, and restore the image declaration
to the drawn size.

## D73 · 2026-10-24 · The layout is the whole plate, and it can have names

**A catalogue of eleven, in three bands.** D72's panel arranged the six live instruments; the
four control cards and the media player were fixed. Now `lib/nexus.MODULES` holds all eleven,
each with a **band** whose shape it takes: `tiles` (OUTPUT, DISPLAY, NETWORK, POWER — two
columns), `instruments` (the six live plates — three columns) and `player` (the full width). The
catalogue is fixed; a saved layout only says which of them are on and in what order. Moving a
module steps to the next module of its own band, so a card cannot be dropped into the instrument
grid and the player cannot leave its full-width row; a press on a disabled row's arrows does
nothing. The scene draws the cards from `nx_mod_slot_*` (0 … 1), the instruments from the same
facts (0 … 5) and the player last, with a count per band, so hiding one closes the gap in its own
band and leaves the others where they are.

**Three named layouts, and room for six.** A settings file now carries `nexus.layouts` — an
array of `{ name, modules }` — and `nexus.layout`, the name showing. A fresh file gets **FULL**
(every module), **FOCUS** (the four cards, CPU, memory, root storage and the player) and
**MINIMAL** (OUTPUT, DISPLAY and the player); the panel draws one chip per layout and a press
switches to it, writing the name and the set before the plate changes. **SAVE AS** snapshots the
current arrangement under a trimmed, upper-cased name (one to sixteen characters, no repeats,
never more than six), and **DELETE** removes the showing layout and falls back to the first,
refusing to remove the last one. Both rules live in `lib/nexus.layouts`, `layout_named`,
`layout_add` and `layout_remove`, which are pure and unit-tested. A named layout holds module
ids, not whatever else a catalogue might gain: `M.modules` drops strangers and repeats on the
way in, so an edited or older file cannot put a module on the plate that does not exist.

**Schema and migration.** `nexus.layouts` is checked by a new `layouts` kind (at most six, a
plain unique name each, ids of letters, digits and `_`), and `nexus.layout` is text with a
default of `FULL`. Neither has a default for the array itself: no array, or an unusable one,
falls back to the three the plate ships with, so an empty plate is a choice rather than a file
that keeps refilling itself. A file carrying only D72's `nexus.modules` is read once as a
**CUSTOM** layout at the front of the list and *is what shows* — `lib/nexus.layout_state` decides
that, because the settings' defaults otherwise supply `FULL` beside a file that never named a
layout, and the user's arrangement would be kept in the panel but hidden on the plate. The first
save writes `nexus.layouts`, sets `nexus.layout` and clears `nexus.modules`, so the migration
cannot run twice. Under `MOOI_SAFE` the switch lasts for the session and the footer says it was
not saved.

**Checked.** `bin/mooi check`: five scenes compile, **195 unit tests, 0 failed** (the eleven
modules and their bands, a move that cannot leave its band, the named layouts' defaults, names,
limits and validation, the migration choosing CUSTOM). `tests/nexus.sh`: **66 checks, 0 failed**,
including all eleven modules and three chips at start, a card put away and a plate moved within
its band, MINIMAL leaving two cards and the player, and FULL coming back. Live: the panel drew
the three chips with FOCUS current, MINIMAL emptied the plate to OUTPUT, DISPLAY and the player
(`LAYOUT: MINIMAL` in the footer), and the edited FOCUS order and the current name were in
`settings.json`. Not checked: SAVE AS and DELETE pressed by hand, a seventh layout refused on
screen, and the panel at a narrow plate.

## D74 · 2026-10-24 · The banner grows a fastfetch summary and the shell's palette

**A taller band.** The identity header was 74 px, enough for a name, a host and a clock. It is
now 114 px (the plate 720), so it can carry a system summary beneath the name without crowding
it. The banner copy is cover-cropped to the band's new shape — 1456×228 — and its file name
carries the height (`<name>-228-band.jpg`), so an older 148-tall crop is never stretched into the
new band; a fresh import was already getting a new name (D70). Everything under the header moved
with it: the view switch to 170, the views to 198, both panels by +44.

**What it says.** Two monospaced lines, composed in `mooi-nexus.luau` rather than drawn as twelve
cells: `OS`, `KERNEL`, `UPTIME`, `CPU`, `MEMORY` and `ROOT`, each cell padded to a fixed width so
the columns stay still as readings arrive. The CPU drops its `with …` suffix (and an Intel
`N-Core Processor`), because the fastfetch line has one column for it. One text per line also
keeps the plate's text count down; the layout panel already draws a lot of text, and the plate's
text budget is not unlimited. Below them a **PALETTE** strip draws fourteen of the shell's own
roles — ground, hull, hull raised, well, trace dim, trace, trace lit, phos, phos fill, ember,
ember fill, flare, muted, steel 300 — as small chamfered swatches from the same tokens every card
paints, so a wallpaper change re-lights them with the rest of the plate. Both the summary and the
strip are left out on a narrow plate (`cw > 520` and `cw > 460`).

**The layout panel and an open view.** While testing this the layout panel was found to lose all
of its text when a view (SYSTEM, AUDIO, …) was open in the same frame: its fills and zones drew,
its rows and title did not. The same panel drew correctly when opened from the controls. Since
the LAYOUTS button lives in the overview, the panel now takes the plate over: it closes any open
view first and shows itself 60 ms later, on the next turn of the loop, which renders correctly.
That is a workaround for a Pleamar text-culling quirk, not a design rule; the panel also stays at
its old y (132), which overlaps the taller banner's lower edge and the switch row while it is up.

**Checked.** `bin/mooi check`: five scenes compile, **195 unit tests, 0 failed**. `tests/nexus.sh`:
**66 checks, 0 failed**, including the `-228-band.jpg` copy. Isolated captures: the header draws
the two summary lines (`OS EndeavourOS`, `KERNEL 7.2.11-arch1-1`, `UPTIME 3h 6m`,
`CPU AMD Ryzen 5 7430U`, `MEMORY 10.3 / 15.0 GiB`, `ROOT 80% used`), the fourteen swatches, and
the banner copy fills the band; the layout panel opened from the overview now draws its rows.
Not checked: a real photograph in the 6.4:1 band (gradients were used), the header at the widths
where the summary is left out, and the panel's overlap with the switch row on a narrow plate.

## D75 · 2026-10-24 · The D90 node scaffolding is deleted, not built upon

`shell/mooi-nexus.luau` carried a `Node model (D90+)` block from line 470 to the end of the
file: a `node_registry` that was never seeded, `focus_node`/`add_node`/`remove_node` and a
dozen siblings that were never called, and `nx_node_*`, `nx_connection_*`, `nx_view_mode` and
`nx_integration_*` facts that no scene rule read. The plate drew their names as literal text
at `0,0` — `NX_NODE_COUNT`, `NX_LAYOUT_VARIANT`, `NX_INTEGRATION_DISK` — so the only visible
effect of the whole block was a debug label column. The scene also declared the avatar and
banner images a second time in the same block; those two declarations stay, because the real
banner draws that named image and deleting it would remove the picture.

No decision ever ratified D90; the block was scaffolding for this redesign. The node model
starts from the approved spec (`docs/superpowers/specs/2026-10-24-control-nexus-design.md`)
instead, and the dead names are gone so a later reader cannot mistake them for a foundation.
Two smaller cleanups ride along: the duplicate startup `sync_identity()` call is removed, and
the debug text column is deleted.

**Checked.** `bin/mooi check`: five scenes compile, 195 unit tests, 0 failed. `tests/nexus.sh`:
66 checks, 0 failed. Grep for the deleted names returns nothing.

## D76 · 2026-10-25 · The Nexus is a full window drawn from the node model

The plate was right-anchored under the bar, 260–780 px wide, and its eleven modules were
hand-placed blocks in the scene. S2 replaces that with the surface the spec asks for: one
full-window overlay with a 44 px header, the identity banner at one of four heights, the node
canvas and a 30 px status strip. The header carries the workspace's own controls only —
`CIRCUIT`/`MINIMAL`, the arrangement chips, `VIEWS`, `TIDY`, `LOCK` and `×`.

Nothing in the canvas is hardcoded. The logic publishes `model nx_nodes` (one row per node the
machine can support: type, title, reading, note, bar, position, size limits, tone, selection,
focus, minimized) and the scene draws the rows, the same way the Atlas draws `atlas_tiles`.
A press, a drag, a resize or a key comes back as an event with the node's arrangement index;
the proposed geometry travels in the facts beside it (`nx_gx`/`nx_gy`, `nx_rw`/`nx_rh`,
`nx_cw`/`nx_ch`), the way the board's card drop does. The logic snaps to the 8 px grid, clamps
into the canvas, records the arrangement and writes the settings once per gesture — never per
frame.

`PIN` changes meaning with the surface: there is no outside left to press, so the toggle now
locks the arrangement against drag and resize, and the label follows (`LOCK` / `LOCKED`). The
scaffolding's old "stay open" meaning had nothing left to hold.

`VIEWS` is deliberately temporary. It keeps the plate's panels reachable — SYSTEM (the overview,
COPY DIAGNOSTICS and the list of nodes removed from this arrangement), AUDIO (routing, the
microphone, the output level, Bluetooth), MIXER (one row per stream, wheel for the level, press
to mute) and SPACES (the compositor's workspaces) — until S3's detail bodies make them part of a
node instead. The drawer is scene state (`nx_drawer`, `nx_tab`), so nothing about it reaches
the settings file.

**Checked.** `bin/mooi check`: five scenes compile, 231 unit tests, 0 failed. `tests/nexus.sh`:
60 checks, 0 failed — including seeded arrangements, a snapped drop, minimize/restore, removal
and restoration, focus at centre, MINIMAL, arrangement switching, the four banner heights, TIDY
and a drawer tab, all through the isolated lab runtime. The inherited plate assertions this
branch never carried (the D72 layout panel, and the mixer/spaces/power views) were replaced by
these node checks rather than left failing.

## D77 · 2026-10-25 · Detail bodies replace the VIEWS drawer, and the layout has an undo

S2 kept the plate's panels reachable in a temporary drawer. S3 moves each panel to the node
that owns it and deletes the drawer, so nothing is reachable in two places. A focused node now
shows its **detail body** in the middle: the System node carries the overview's eight rows and
COPY DIAGNOSTICS; Audio carries output, input, microphone, Bluetooth and up to four application
streams with the same press/wheel controls; Display answers the wheel with the backlight;
Workspaces is the SPACES list; Media carries the transport; Core, CPU, Memory, GPU, Thermal,
Storage, Network, Clock and Power show four labelled readings each. The rows are published by
the logic (`r1l`…`r8l`, `r1v`…`r8v`, with a `rows` count), so the scene stays a renderer and an
absent provider still says `N/A` rather than a guess.

`RESTORE CENTRE` appears in the header whenever the middle is not the core, and the focus swap
is unchanged: the node already at the centre inherits the vacated slot.

The layout gains an undo history: `nexusnode.remember/undo/redo` keep up to twenty deep-copied
arrangements, taken before every edit that moves, resizes, focuses, removes, restores, retimes
or repacks a node. `Ctrl+Z` steps back, `Ctrl+Shift+Z` forward, and any new edit clears the
forward list. A step is a whole arrangement, so undoing a focus swap also returns the node it
displaced.

**Checked.** `bin/mooi check`: five scenes compile, 233 unit tests, 0 failed. `tests/nexus.sh`:
72 checks, 0 failed — the detail rows for System (8) and Audio (4), RESTORE CENTRE, a drop
undone and redone by position, the stream and workspace lists, and every earlier workspace
check through the isolated lab runtime.

## D78 · 2026-10-25 · An arrangement switch is a move, not a cut

Switching arrangements used to publish the destination positions in one frame. `nexuslayout.blend`
now mixes a node's old and new rectangle in whole pixels, and the logic steps that mix eight
times at 40 ms (320 ms, as the spec asks) while publishing each step. The arrangement itself is
already at the destination, so a drag or a drop taken mid-move lands on the real geometry rather
than a displayed one. Focus swaps, RESTORE CENTRE and undo/redo use the same move, which is why
a focus change no longer snaps the two nodes it trades places with.

The morph runs entirely in the published model: no scene prop per node, no per-frame routing.
Edges read the morphed positions because they are routed from the same rows.

**Checked.** `bin/mooi check`: 234 unit tests (including `blend`'s rounding, clamping and
endpoints), five scenes compile. `tests/nexus.sh`: `nx_morph` returns to zero after an
arrangement switch, so the move finishes rather than sticking.

## D79 · 2026-10-25 · The connection layer is routed once, drawn many frames

Edges are authored in `lib/nexusgraph`, instantiated against the nodes actually on the canvas,
given their style and the arrangement's hidden list, and routed — all in the logic — into
`model nx_edges`: at most four points per trace, plus the label, the meaning and a midpoint.
The scene draws three segments per trace and never solves a path, so the frame cost of a busy
canvas is lines, not geometry.

- **Hover inspects.** Entering a node lights every trace that reaches it; entering a trace shows
  its meaning beside it. Both are facts (`nx_hover`, `nx_hover_edge`), so the scene compares
  rather than guesses.
- **A press picks a trace.** Its two endpoint nodes take a flare rim (`endsel`), and a small
  panel offers `HIDE TRACE`, `CLOSE` and, when anything is hidden, `RESTORE FULL NETWORK`.
  Hidden traces live in the arrangement's `edges.hidden`, so the choice persists and undoes.
- **Focus isolates.** While a node other than the core holds the centre, traces that do not
  reach it draw at 22 % opacity; the focused node's own edges stay lit.
- **Activity.** An edge whose provider is reporting (CPU, memory, GPU, thermal, power, storage,
  network, playback) carries a phosphor mark at its midpoint. In MINIMAL only those edges draw,
  which is the spec's "no decorative traces".

Per-edge hiding is the one interaction that needed a popover: a trace is a line, and a line
cannot carry a menu button without becoming a node.

**Checked.** `bin/mooi check`: 234 unit tests, five scenes compile. `tests/nexus.sh`: 8 traces
drawn from the authored graph, hover lights the trace, a press picks it, both endpoints are
marked, hiding drops the count and RESTORE FULL NETWORK brings it back, and four unrelated
traces recede from a focused node — 88 checks, 0 failed.

## D80 · 2026-10-25 · The Nexus is drawn as a machined instrument, and customised on one plate

The shell's surfaces were flat chamfers and thin labels. They are now built from the design
system the spec asks for, with `body` plates (gradient face, rim, border, shadow) instead of
one-colour paths, and one accent colour chosen from the palette's roles rather than `fl.phos`
everywhere.

- **One accent.** The appearance's accent role is read as `rgb()` of the four role springs, so
  the header, the traces, the brackets, the panel and the status strip share one signal colour
  and it still follows the wallpaper. Brightness and contrast are applied to the published
  roles in the logic, which is the only way to change every surface without a hex in the
  markup; glow scales the existing glows; opacity is the surface group's.
- **Frames read as hardware.** A node is a rail with its index, name and state, port nubs on
  both flanks, a reading with its note and a ticked bar, and a centred detail body with ruled
  rows. Its whole face is one zone declared before the drawing, so hover, selection and focus
  light the frame as one object; the controls inside are declared after it and keep their
  presses.
- **One docked panel** carries S5's four faces — LIBRARY, NODE, LOOK, ARRANGE — instead of four
  surfaces. The header's tabs, the panel's tabs and Escape all address the same fact
  (`nx_panel`), so opening, switching and putting it away behave the same from anywhere.
- **The library is honest.** It lists the whole catalogue with `ON`, `BACK` (removed, restorable
  by the node index it carries) or `N/A` and the provider's reason. It never offers an
  unavailable module a press. Appearance and arrangements are edited in enums and bounded
  numbers, validated by `config`'s existing kinds, and saved with the arrangement; nothing in
  the scene writes a setting.
- **A hidden trace can come back alone.** `model nx_hidden` lists what the arrangement put
  away, labelled from the authored graph, and `nx_edge_show` removes one slot. RESTORE FULL
  NETWORK stays for the whole list.
- **The shell is responsive in three steps.** `tight` drops the arrangement chips when they
  would collide with the panel buttons, `small` keeps only the controls that act on the
  workspace, and `tiny` folds the banner to its strip, hides the status strip, replaces the
  mode switch with one button and shrinks the gutters. The canvas is published to the logic
  once the entrance settles and on every resize, and a shrink runs `nexuslayout.fit` — so the
  arrangement follows a smaller screen without a pan/zoom mode.

**Checked.** `bin/mooi check`: 234 unit tests, five scenes compile. `tests/nexus.sh`: 117
checks, 0 failed — the library's rows and reasons, a removed node restored from it, a hidden
trace listed and restored by slot, the grid, accent, glow, labels and route controls, a size
preset and RESET NODE, NEW/COPY/DELETE on the arrangements, and Escape closing the panel
before the workspace.

## D81 · 2026-10-25 · The library adds a module, and pages by the room the panel has

The module library shipped as a list of what is drawing, what was put away and what the
machine cannot show. Two gaps showed up once it was on screen: a type the arrangement never
carried read `N/A` with "not in this arrangement" and could not be reached at all — CPU,
Memory, Thermal and GPU were permanently outside a fresh FULL — and only the first ten of
nineteen rows were drawn, with no way to see the rest.

- **`ADD`, not `N/A`.** The library's third state is now its own: available but absent from
  this arrangement. `nx_lib_add` takes the catalogue index the row carries, seeds the type
  from the default ratios, and asks `nexuslayout.free_slot` for the first grid slot that
  clears every other node — so a press never lands on the clock. It goes through `remember()`
  like a drag, and undo takes the node off again. A type that is present but hidden is only
  brought back rather than duplicated.
- **Rows page by fit.** `nx_lib_page_size` follows the canvas height the logic already knows
  (ten, eight, six or four), and the scene reads the same fact for its row window, so the
  logic and the drawing cannot disagree about where a page ends. The footer states
  "19 OF 19 MODULES" — filtered count of the whole — and a pair of arrows, each lit only when
  there is a page that way.
- **A drawn control is a shown control.** At `small` the header computed `CENTRE`, `TIDY` and
  `LOCK` onto the close mark's x while only the zones carried `show`, so three button plates
  stacked there. The fix is structural, not cosmetic: components are wrapped in the group
  that shows them, and the right-hand steps are measured from the last button actually drawn.
  `LOCK` now survives every width because it is the one control that changes what a press
  does; `TIDY`, `CENTRE` and the arrangement chips need the room and are gated on it.
- **The banner's veil covers the picture.** Two veils, one of them `sw * 0.55` wide, left a
  visible vertical seam where the words stopped. One even veil at 0.32, drawn only when there
  is an image, keeps the portrait readable and lets the plate's own gradient be the backdrop
  when there is none.

Checked: 234 unit tests; 126 checks in `tests/nexus.sh` (the add and its undo, the page size,
the catalogue count, and a press before the first page); screenshots at 1920×1050, 1366×738
and 720×390; 0.15–0.19 ms of CPU per frame at twelve nodes under `--no-vsync`.

## D82 · 2026-10-25 · The Nexus answers as fast as the bar, and the panel can be carried

Four things, one of them a bug that made the whole workspace feel broken.

- **The spawn dropped the shell's own flag.** The bar launches the Nexus with
  `pleamar --scene … --no-hud` and missed `--stall 0`, so the Nexus ran in pleamar's
  demonstration mode: the logic blocks 600 ms after every decision. Every press, hover and
  key was answered half a second late while the bar itself was instant. The spawn now passes
  `--stall 0` like every other surface mooi opens. Measured after the change: a mode switch
  answered over the socket in 25 ms, the same round trip that took the stall before.
- **One publish per frame.** A pointer sweeping the canvas raises an enter and a leave per
  node and per trace, and each one rebuilt every row, edge and library entry. `publish()` is
  now a request: the build runs once, 16 ms later, and every request inside that window is
  dropped, because the scene can only draw one of them.
- **The panel is carried by its head.** `nx_panel_head` is a drag zone over the panel's title
  and grip; the drop lands in `nexus.panel.x/y` and the panel opens there next time. A press
  without a drag puts it back on the right edge (`nx_panel_dock`). Two integers in the
  settings schema, zero meaning "dock it", and the scene clamps whatever it is given.
- **Two chips said MINIMAL.** The mode and the third arrangement shared the word. The shipped
  arrangement is `BARE` now; `rename_shipped` moves a saved copy only when it still has the
  shape it shipped with, and also the "which one is showing" name, so a file that never
  touched it is migrated once and a file the user made their own keeps the name they chose.
- **The band is engraved when there is no portrait.** Instead of a flat dark plate, a clipped
  rule every 24 px with a lit one every 96 — the same measured language as the grid, drawn
  only when there is no banner image.

Checked: 235 unit tests (including the rename and its refusal to rename an edited copy);
126 checks in `tests/nexus.sh`; the panel dragged to (320, 260) and docked again by a press;
the engraved band and the `BARE` chip read at 1920×1050.

## D83 · 2026-10-25 · Every node says more, and says it inside its own frame

The workspace drew the same four readings the old plate had, and a card could only ever show
those four rows. This adds the numbers the machine was already willing to give, and makes the
frame decide how much of them to show.

- **Three more files, read on the same two-second clock.** `/proc/loadavg` for the three
  averages and how many tasks are runnable, `/sys/…/cpu0/cpufreq/scaling_cur_freq` for the
  package clock, and the rest of `/proc/meminfo` — available memory and swap — beside the used
  figure it already had. `df` also gives back the filesystem's device and what is free, so the
  storage node names `/dev/nvme0n1p2` rather than "the root filesystem".
- **Six to eight rows, never more than fit.** Each type's body now has six to eight labelled
  readings. The logic publishes only the rows that fit the height the card is drawn at
  (`rail + 92`, then 26 px a row), so a compact card shows two and a detail card shows all
  eight, and no row is ever cut in half by the frame. The overview reserves the strip its
  COPY DIAGNOSTICS button sits in.
- **A second line and a second bar.** Every card carries a `sub` line under its note — free
  memory, the package clock, the SSID, what is on the other end of the input — and a focused
  card draws a second, thinner bar under the primary one with its own label: memory beside
  load, the microphone beside the output, the swap and the temperature where they belong.
- **The header is an instrument.** Where the header has room (over 1500 px, past the
  arrangement chips) it carries LOAD, MEM, TEMP and NET with their numbers and bars. They read
  the same facts the nodes do, so the header cannot disagree with the canvas.
- **Everything else follows.** The system node's own rows gained the load average and the
  runnable count; the CPU node its clock and model; the storage node its device and free
  space; the memory node what is available and what is swapped; the clock its kernel and load;
  the media node whether it is playing.

Checked: 238 unit tests (`mem_detail`, `loadavg` and `clock_ghz` have their own), **128 checks**
in `tests/nexus.sh` — a focused card opens its whole body at the detail size and keeps only
one row at the size the catalogue ships, and the last audio row is STREAMS. On screen at
1920×1050: the header cluster reads load, memory, temperature and traffic; the Storage card at
DETAIL shows five rows inside its frame; the System card shows its sub line and both bars.

---

## D84 · 2026-10-26 · The Nexus centre takes a face, the hub is the user's, a new mark, and Lumen works

**Asked for:** the profile picture, banner and identity, and/or a music player with a visualiser,
at the Nexus centre; the same in the compact view; the compact view customisable and better; the
Control Nexus icon fixed; the wallpaper studio made to work properly.

**The centre's faces (`nexus.centre`).** The core node has four faces at the centre of the
workspace: REACTOR (as before), IDENTITY (the banner across the top, the avatar on its edge, the
name, user@host · session, distro · kernel, uptime / workspace / time along the foot, EDIT
IDENTITY), PLAYER (the cover, title, artist, album, a 24-band visualiser the width of the face,
the time and the transport) and ID + PLAYER (who you are on one line over the player). FACE on the
core's rail cycles them. In the ring the core card says what its face is: the name, or the track
and its rows (artist, album, time, player, state). The generic value, note and bars are not drawn
under a face.

**The hub's arrangement (`nexus.hub`, `lib/nexushub`, 9 unit tests).** A hero of five faces —
IDENTITY, PLAYER (the cover blurred behind it), REACTOR (four rings and the readings), ID +
PLAYER, MINIMAL (one line) — then the sections in the user's order: switches, levels, now
playing, machine, workspaces, shortcuts. The logic lays the column out and publishes each
section's top (`nx_hy_*`) and whether it takes room (`nx_hon_*`); the scene draws each section
from its own top and glides when one moves. CUSTOMISE (the arrange glyph by FULL) puts a strip
under the hero (the five faces, COMPACT / WIDE — 452 or 540 px — RESET SECTIONS, DONE) and ▲ ▼ ◉
on every section; a hidden section is a stub that can be shown again. The now-playing section
is left out under a player face, and a machine with no backlight loses that level's row instead
of drawing "NO BACKLIGHT".

**The player.** Covers: `file://` as given (percent-decoded), `https://` fetched with curl,
`data:` written out by ImageMagick (`inline:`). mpv's MPRIS plugin sends a truncated `data:`
cover, which ImageMagick rightly refuses; a cover file beside the track works. The elapsed and
total times were declared in the scene but never set: the logic now carries the reported
position at the player's rate once a second while something plays and the Nexus is up.
**The visualiser** is cava (`cava-nexus.conf`, written in the data folder the service names),
spawned only while something plays and a player face or the now-playing section is on screen,
and stopped on close, on a shortcut that leaves, and when the face changes back.

**The mark.** `icons/nexus.svg` — a hexagonal core in a ring broken by three nodes — replaces
the outline Arch "A" on the bar and in the Nexus header. The old figure was placed at `at: 8, …`,
but a figure's `at` is its **centre**, so the mark sat half off its pill and 7 px high; it is
centred now, brighter at rest, and lit with a rule under it while the Nexus is open.

**Lumen, made to work.**
- *The whole picture is reachable.* The base was centre-cropped to the screen's shape before any
  edit, so most of a tall picture could never be framed. The base now keeps the picture's shape;
  the crop is the largest screen-shaped part of it at zoom 100, placed by fx/fy anywhere along it.
- *FIT* shows the whole picture on the backdrop; *↺ ↻ 90°*, *MIRROR*, *FLIP* and *RESET FRAME* are
  chips on FRAME; zoom goes to 400 %.
- *The hand moves the picture.* Dragging pans it (the preview moves with the hand, the crop follows
  on release, `lib/wallpaper.pan`); the wheel zooms round the pointer (`zoom_at`). A click no longer
  silently moves the focus.
- *New adjustments:* Midtones (gamma) on TONE, Sharpen and Soften on FX. Hue turned only ±90°
  (`hue / 3.6`); it is `hue / 1.8` now, the ±180° the slider says.
- *A black picture.* The vignette's `-compose multiply` outlived its parentheses and multiplied the
  picture into its backdrop whenever a matte, a key or FIT was on. `-compose over` is set before
  that composite, and the vignette and grain are the finished frame's now (after the composite),
  so they reach the backdrop and cannot touch a key's transparency. `-rotate` is followed by
  `+repage`, without which the crop and the composite honoured the rotation's page offset.
- *Fast while dragging.* The base is an `.mpc` (memory-mapped, read without decoding: 160 ms a
  preview instead of 320 ms) and a proxy at a draft's scale answers a drag at once (960 × 540);
  the full preview follows 260 ms after the edits settle. Every render is stamped, so a slow one
  that finishes after a newer one is never shown; the compare view is remade only when the frame
  changed (`frame_key`, `ungraded`).
- *Keys that do not steal from a field.* A letter rule fires even while a field has the caret, so
  typing `#aa1122` as a backdrop colour applied the wallpaper (`a`). The field is taken through a
  zone that sets `typing`; while it holds, Escape only leaves the field and no letter or digit is
  a shortcut. New keys: H hides the studio, C compares, F fits, Ctrl+S saves a copy.
- *SAVE A COPY* writes the still to `~/Pictures/Lumen/<name>-lumen-<time>.png`. *APPLY* falls back to
  `awww img` when the picker is not running (and says the palette waits for the picker).
- *The dock* is laid out from its width: four slider columns whose values never sit on the next
  slider, the vibe under the tabs instead of on BACKDROP, compare / undo / redo / reset at the right.
- *The source wall* makes three thumbnails at a time, Up/Down walk its tiles (Enter in the filter
  opens the lit one), and an arriving thumbnail no longer resets the selection. The folder picker
  called `enter_picker` above its `local` (a nil global: PICTURES on a machine without the folder
  crashed the handler); it is declared first.

**Checked.** `bin/mooi check`: **258 unit tests, 0 failed** (9 hub, 5 new wallpaper: shape and
reach, turn and mirror, pan and zoom, new fields and hue, compose order), all five scenes compile.
In a lab copy (own scene name and data folder, `MOOI_SAFE=1`; Lumen's lab has no `qs`/`awww`):
the four core faces with a silent mpv track (cover, title, ticking time, transport) and the
user's own kew session (live visualiser in the hub's player face); cava starts with a player face
and stops on the reactor; every hub face; customise moved MACHINE above NOW PLAYING, hid SWITCHES
as a stub and widened the plate; Lumen's wheel (3 notches → 146 %), drag (fx 50 → 0 at the edge),
FIT + 90° (a portrait strip on the blurred backdrop), drafts within ~300 ms and the full preview
after, the typing guard (`a` went into the field, applied only after Escape), three thumbnail
workers, PICTURES in the picker. Deployed with `bin/mooi refresh`; the new mark is on the bar.
**Not checked:** APPLY and SAVE A COPY for real (they write to the desktop and to ~/Pictures),
the `awww` fallback, a real mouse drag on the picture (the agent's hand was used), the hub faces
on a narrow screen, and the visualiser with a player that sends a whole `data:` cover.

---

## D85 · 2026-10-26 · The desk: a parallax wallpaper and a cutout over the widgets; the hub gets a rail

**Asked for:** a really good parallax option for the wallpaper (one that can be turned off from
the settings and from quick settings), a cutout so the desktop widgets sit behind the picture or
part of it, a better backdrop and studio settings; and for the compact Nexus: less cramped, more
inventive, with modules that can run lengthways down the side.

**The desk (`shell/mooi-desk.plm`, `lib/desk`, 3 tests).** The wallpaper is drawn by the picker on
the background layer and the widgets sit on the bottom layer above it, and neither is mooi's.
So mooi draws it itself, as a program the bar keeps running while `desk.on` is set: a background
surface over the picker's, the picture a little larger than the screen (`strength` up to a tenth)
travelling with the workspaces (a slow, heavy spring over a row at least four long), the pointer
(`cursor.x/y`, a lighter drift) or both; and a click-through bottom-layer surface, created after
the widgets so it stacks above them and under every window, holding the cutout. With **depth** the
subject travels 1.55× as far as the picture behind it; so that it is not seen twice, Lumen also
makes a **plate** — the still with the subject's place filled by the picture out of focus (a
quarter-size blur through the widened mask), of which only the uncovered band is ever seen. The
desk follows `~/.cache/current_wallpaper_source` (what the picker draws) every 2 s and uses
Lumen's layers only while they belong to that picture (`desk.json`); a video or GIF wallpaper is
left to the picker. Motion saving and reduced motion keep it still.

**The cutout (Lumen's DESK tab).** KEY floods the background from the top and the upper sides
only — never the foot, where a standing subject meets the frame (seeding from all eight points
took the black hair and dress of a portrait away); REGION is a box drawn by dragging on the
picture; KEY + REGION is the key inside the box; AI uses `rembg` when it is installed (a photo's
subject cannot be keyed). The mask comes from the still without vignette or grain. APPLY then
writes the cutout and the plate beside the still. The tab also carries the desk's switches (on,
still / workspaces / pointer / both, depth, over the widgets, strength), written to settings.json
read fresh just before. Settings window: a Quick-page switch and a Desk card on the Wallpaper page;
Control Nexus: a PARALLAX tile.

**Settings that did not stick.** `lib/config` validates against a schema and drops what it does
not name: D84's `nexus.hub` and `nexus.centre` were written and then stripped at the next read, so
neither survived a restart. They are in the schema now with `desk.*`, and a test reloads them.

**The hub (`lib/nexushub` rewritten, 10 tests).** A hero across the top, then a main column (476
or 584 px) and, when anything is sent there, a 164 px rail beside it. Every section has an upright
form for the rail: tiles two across, levels as standing sliders, the player as a cover over its
track, the visualiser as bands either side of a spine (a new section, shipped hidden), the
machine as stacked ring gauges, the workspaces as a grid of two. CUSTOMISE adds ⇄ to each section;
▲ ▼ move within its own column. The look: an engraved caption with a node on a lit spine down the
margin for every section, ten tiles with a lit edge (PARALLAX and CLIPBOARD added), ring gauges
with traces, thicker glowing levels, a mirrored visualiser, workspace cells with window dots.

**Checked.** `bin/mooi check`: 263 unit tests, 0 failed; six scenes compile. Lab copies: the desk
ran with a region cutout (its surfaces above `desktop-widgets` and the visualiser, below windows);
Lumen's KEY preview on a line-art picture; APPLY made the cutout, the plate and desk.json in ~4 s
(the lab's hand-off to the picker was stubbed; those files were then deleted); the hub with a rail
and in customise mode. **Not checked:** the desk on the live desktop (it is off until switched on),
the parallax's feel on a real workspace switch, `rembg` (not installed), the settings window's new
rows on screen.

---

## D86 · 2026-10-26 · The stash, the notes, the Signal Field and the board, better in use and to look at

**Asked for:** the stash box, the notifications centre, the notes and the Kanban board improved in
every way, visually included; and every part themed from the wallpaper.

- **Stash.** Ways in that are not a drop: PASTE stashes what is on the clipboard (file paths, links
  or text, read with `wl-paste`; a picture on the clipboard is only bytes there, so SHOT or a drop
  takes pictures) and SHOT stashes a region chosen with `slurp`, taken by `grim` straight into the
  stash folder. Ways to find things: chips (all, pictures, links, files, text) and a search, both
  `lib/stash.filter` (tested). The box is taller for the new row.
- **Notes.** A colour per note (its stripe, pressed: none → phos → flare → ember → trace), a tick
  (a ticked note sinks below the open ones, dimmed), a search in the header (↑↓ walk what it
  shows), and two-line rows: the first line is the note's name, the rest a quiet line under it.
  `lib/notes` keeps `tag` and `done` in notes.json (tested). The pad is 468 × 404.
- **Signal Field.** A summary strip — waiting, apps, urgent, missed — with a bar of each app's
  share (the chosen one lit, an urgent one ember); nothing waiting is a still scope, ALL QUIET.
- **Board.** How much is done as a meter in the head, a column's limit as segments under its name,
  an empty column that says what it is for, cards with a lit tag edge, a top highlight and the due
  date as a pill.
- **Theming.** Every program with chrome paints from palette.json and re-lights when it changes
  (the bar, the Nexus, Lumen, the settings window, the board); the desk draws only pictures. Hard
  hexes left are shadows, the aberration fringe and Lumen's initial text values.

**Found on the way.** `bin/mooi refresh` hot-reloads the bar's scene, but logic modules it
`require`s stay as they were loaded: the Field's new counts read 0 until the bar was restarted.
Logic changes in bar modules need the keeper's restart.

**Checked.** 265 unit tests; scenes compile. Lab bar: the stash's chips (LINKS left two of five),
search ("coffee" → one), PASTE (a text item from the clipboard); the pad's colours, ticks and the
ticked note sinking; the board's meter, WIP segments and empty column. Live, after a restart: three
test notices from two apps gave 3 WAITING · 2 APPS · 1 URGENT and a two-segment share bar; they
were cleared. **Not checked:** SHOT (it needs a hand to choose a region), the board's due pill
(the seeded date was written in the wrong unit), the board at a larger size (its geometry is fixed
in the logic and the scene; a resizable board is a follow-up).

---

## D87 · 2026-10-26 · The desk actually starts; "both" parallax no longer clips; the studio's button

**The desk never ran.** `desk_sync` called `spawn(cmd, args, nil, on_exit)`; pleamar's `spawn`
needs a function for its line callback, so every call raised "error converting Lua nil to
function" (mooi.log) and the desk stayed off with `desk.on` set. It now passes a line callback that
keeps the first error lines for the exit log. The bar's screen recorder made the same call
(`bar.luau`, wf-recorder) and gets the same fix — that one goes live at the bar's next restart,
since `bar.luau` is a cached module.

**Both, clipped.** With parallax "both" the picture's place was `wsx + pointer · 0.4`, clamped to
0…1, so on the first or last workspace of the row half the pointer's travel was cut off (measured:
36 px for a full sweep, 72 expected). It is now `0.5 + (wsx − 0.5) · 0.6 + pointer · 0.4`: the
workspaces take 0.6 of the travel and the pointer 0.4 round it, never clipped.

**Checked live:** the desk starts with the bar; turning `desk.on` off ends it and on again starts it
(settings.json edited and restored byte-identical); workspace 3 → 5 moves the picture 36 px, as the
row (5 long, strength 94) predicts, 31 px of it in the first 250 ms; the settings codes 320–324
name desk.on/parallax/strength/depth/cutout. Not checked: the cutout and depth (no Lumen cutout for
the current picture).

**The wallpaper studio's button** placed its figure with top-left maths (`at: 8, top + (h−16)/2`)
though `at` is a figure's centre (D84), so it sat half off its pill and high. It is centred now, and
`icons/wallpaper.svg` is redrawn in the Nexus mark's round-cap stroke: a framed picture with a
studio sparkle.

---

## D88 · 2026-10-26 · The music player is finished and on the bar

**Asked for:** finish the player. **Done:** the program (shell/mooi-player.*, written over D87's
evening) is now started by the bar: `open_player` in mooi.luau (spawned like the studio, the
media module's centre written to `player-anchor.json` first), a left press on the media module's
track or pill (the right press is play/pause; the wheel, the slabs and the visualiser keep theirs),
`mooi player`, and `keys.player` = Super+Alt+M (free on this desktop; on the Keys page). bin/mooi
links its data folder to mooi's and checks it on refresh. **Cover colours:** `player.colours`
(shell | cover, in the schema) and a COVER chip; the cover goes through Matugen with source colour
0 and the shell's scheme and contrast, once per cover. The player's permissions lacked `matugen`,
which made the first try silently do nothing.

**mpd was wedged.** `mpc` timed out: mpd's main loop had stopped accepting (6 connections queued on
a backlog of 5) after its auto-detected ALSA output, through the alsa-pipewire bridge, looked for a
"PCM" mixer that does not exist. ~/.config/mpd/mpd.conf now has a native `pipewire` output with a
software mixer (backup ~/.local/state/mooi/mpd.conf.before-2026-10-26); mpd was restarted.

**Checked live** (agent commands on the running player): it opens from `mooi player` under the
media module; the library (728 artists), search ("free bird" → the song), LRCLIB's synced lyrics,
full screen, the source switch; play/pause at low volume with the record turning 200°/s and the
tonearm following progress; COVER relit the accent from a blue cover and back.

## D89 · 2026-10-27 · BMO moves from Quickshell to pleamar

**Asked for:** port the BMO companion (rebuilt in Quickshell on 2026-10-26, ~/.config/quickshell/bmo)
to pleamar if possible. He goes behind windows by default, and chat/ollama is left out for now.
**Done:** `companion/bmo/`: `bmo.plm` (the scene: one full-screen surface on the bottom layer,
with only his own zones taking input, plus his panel and right-click menu while they are open),
`bmo.luau` (the logic: position, walking, dancing, sleep, speech, music, settings),
`brain.luau` (pure: faces, moods, poke and drift choices, energy, settings validation) and
`test.lua` (`lua5.4 companion/bmo/test.lua`, 8 tests). The logic owns where he stands and his
face, the pose's gestures own his body, and the drawing adds them together, so two animations
never fight over a value. His data folder is ~/.local/share/pleamar/bmo (`settings.json`:
wander, locked, size, motion, music, doze, clock, above, x/y). Music comes from the `media`
service (MPRIS). Permissions are `hyprctl` (monitor size), `kitty` and `loginctl` (panel
shortcuts) and `pleamar` (quitting himself). He doesn't get a shell.

**Driving him from outside:** `pleamar --say bmo "emit ui N"` (1 panel, 4 home, 5 sleep/wake,
120 walk, 121 dance, 122 look, 30–37 moods, the rest listed in `on("ui")`), `"fact above true"`
to see him over windows, `"get mood_t"` / `wx` / `energy` to read him.

**Checked live:** walking (turns three-quarter with side depth, strides, faces front again),
dancing (happy face, arm sway and tilt, stops on its own after 6–12 s), a click counts as a poke,
a double-click opens the panel, a drag carries him clamped to the screen with the face changing,
sleep cycles its "z / z z / z z Z" bubble and pressing sleep again wakes him, music start/stop
changes his mood, and a new song gets an excited face and a "♪ title" bubble (mpd at low volume,
restored afterwards). Also seen: all four panel tabs and the menu. Note that the `still` motion
setting turns off the hop and breathing by design.

**Retired:** the Quickshell BMO (its uncommitted rewrite and ~/.local/state/bmo) is archived in
~/.local/state/mooi/archive-2026-10-27-quickshell-bmo.tar.gz and the directory removed; the
original is still in the home dotfiles repo's history.

**Not done:** autostart. The line for ~/.config/hypr/config/custom/session.lua (inside the
`hyprland.start` handler, because Hyprland doesn't run `pleamar --autostart`) was blocked by the
agent's permission check and is left for the user to add. Not checked: a real re-login, his
placement on a second monitor (he uses the focused monitor's size), and long-run energy/doze
over hours.

## D90 · 2026-10-27 · One workspace viewer: the Workspace Atlas is removed, the Overview stays

**Asked for:** two workspace viewers is one too many. Remove the Atlas completely and keep the
Overview. **Removed:** the Atlas island (`atlas_island`: the windows grid, the workspaces board
and the spatial view), its 16 key rules, its open/close rules and layer, the facts and events
only it used (`atlas_sel`, `atlas_mode`, `atlas_ws`, `atlas_target`, `atlas_view`, `atlas_cols`,
`atlas_drop`, `atlas_go`, `atlas_move`, `atlas_previews`, `open_atlas`, `sp_mons`, `sp_chips`,
`sp_drop`, `sp_chip`, the tiles' `col/row/sx/sy/sw/sh/svis`), `atlas` from the `open` enum,
their logic handlers (the move strip, the board and spatial drops, the `p` previews toggle,
workspace focus), `lib/atlas.spatial`/`drop` and their test, `keys.atlas` (Super+Alt+A),
`mooi atlas`, and the Atlas row on the Keys page.

**Kept, under their old names:** what the Overview was built on: `model atlas_tiles`,
`atlas_busy`, `atlas_window` (focus a window), `lib/atlas` (grid, canvas, privacy, search,
menus, names and groups), and the `atlas.*` settings. Renaming the settings would need a
migration of every saved file for no visible gain; the names are internal. `atlas.previews`
stays a setting (Settings → Overview → Pictures), now without a key of its own.

**The bar button.** The Atlas's bar module (32 px, index 22 in `barlayout.ORDER`) is now
`overview`: same place in the order, so no other module's settings code moved; a press emits
`open_overview` and it lights with the Overview (`ov_z`). An unknown module in `bar.left/center/
right` makes `lib/config` drop the whole layout for the default, so `config.migrate` renames
`atlas` → `overview` in the three lists (inside `a+b` groups too) and moves `bar.modules.atlas`
to `bar.modules.overview`. Unit-tested. The user's own layout (with `atlas` on the left) came
through unchanged: no config error, the button at x 278. Backup:
~/.local/state/mooi/settings.before-d90-2026-10-27.json.

**Tests:** `tests/scene.sh` and `tests/integration.sh` now open and close the Overview where
they drove the Atlas; `tests/config-recovery.sh` checks the settings round trip with the bar's
labels toggle (the same logic-writes-the-file path the Atlas's `p` used). `bin/mooi check`:
seven scenes compile, **271 unit tests, 0 failed**. Live after a restart: the bar button
opened the Overview (5 workspaces, 2 window tiles, Canvas, live pictures) and Escape closed it.
Not run: the live scripts (scene.sh, integration.sh, config-recovery.sh) — they grab the
keyboard and need mooi stopped.

## D91 · 2026-10-27 · Day and night, and every app on the palette

**Asked for:** check all theming; Qt, GTK and the terminal must follow it; a light mode that looks
as good as the dark one, with everything going along with it. Choices made by the user: a manual
switch plus a schedule, GTK 3 moved to adw-gtk3, Papirus icons everywhere, and mooi allowed to edit
the Hyprland env and run their own Matugen config.

**The audit found** that Qt apps were never themed (`QT_QPA_PLATFORMTHEME=qt6ct` lived only in
~/.config/environment.d, which systemd services get but apps Hyprland starts do not); GTK 3 apps
ignored the palette (gsettings named WhiteSur-Dark, which hardcodes its colours; settings.ini said
adw-gtk3-dark); GTK used WhiteSur icons and Qt Papirus; KDE apps read colours from kdeglobals, and
Dolphin, EasyEffects and Kdenlive each kept a dark scheme of their own in their rc; the terminal's
colour 0 was the background's colour; the user's own Matugen templates (btop, fish, cava, Vesktop,
Zen, Spicetify, widgets, picker) were only rendered by the wallpaper picker, always dark.

**One source of truth for the mode.** `theme.mode` dark | light | auto with `theme.light_at` /
`theme.dark_at` (hours, default 7 and 19). `bin/mooi mode_now` decides; the watch's key includes it
(so auto flips within 5 s of the hour); `theme_sync` runs Matugen in that mode and stamps `mode`
into palette.json; `lib/ferro.resolve` reads it from the palette, so the bar and every mooi window
(settings, player, studio, board, Nexus) turn with no code of their own; the bar writes it into
apps.json for `apps-sync`. Switch: Settings → Colour → Day and night, `mooi mode [light|dark|auto]`
(none: the other one now), Super+Alt+T (`keys.mode`).

**The light palette** (`ferro.derive_light`): the same nineteen roles as paper — Matugen's light
surfaces for ground/hull/raised, the phosphor a deep ink held 6:1 on the ground (7:1 turns it
black), fills deep with `ink` near-white, steel inverted, engrave dark. `adjust` is mode-aware:
neon caps lightness at 0.45 by day, every industrial base has a daylight twin
(`LIGHT_BACKGROUNDS`), the fixed palette and the Alert re-light are built the light way. By day
the bar's glow keeps 30 % and the islands' shadows 35 % (a dark smudge on paper otherwise).
Unit-tested over 12 finish × base combinations: every floor and the islands' token check hold.

**Apps.** `apps-sync` now also sets adw-gtk3 / adw-gtk3-dark, Papirus-Light / Papirus-Dark and
`color-scheme` prefer-light / prefer-dark (gsettings and both settings.ini), Qt's icon theme,
renders theme/apps/kde.colors into ~/.local/share/color-schemes/Mooi.colors and copies its colour
groups into kdeglobals (ColorScheme=Mooi, Papirus), and clears per-app `[UiSettings] ColorScheme`
overrides — each original kept in apps.state and put back when the switch goes off. The terminal's
hues by day are inks held 4.5:1 on its background; colour 0/8 are the outline and muted tones.
`apps.others` (new, "Everything else"): theme_sync also runs ~/.config/matugen/config.toml with the
same image, scheme and mode. Outside the repo: ~/.config/hypr/config/env.lua sets
`QT_QPA_PLATFORMTHEME=qt6ct` (also applied to the running session). Backups:
~/.local/state/mooi/theming-backup-2026-10-27/.

**Checked live**, dark → light → dark: Matugen, the bar (`light`), gsettings, kdeglobals and the
user's template outputs all switched; screenshots of kitty, nwg-look (GTK 3), Nautilus (GTK 4),
pavucontrol-qt and Dolphin in both modes, and the settings window by day. GTK 4/libadwaita follow
the preference live; GTK 3 and Qt/KDE apps take the new mode when reopened; Nautilus runs as a
service (`nautilus -q`). `bin/mooi check`: **273 unit tests, 0 failed**. Not checked: a real
re-login, the auto switch crossing an hour boundary live, Vesktop/Zen/Spotify windows by eye, VLC
(the one Qt 5 app; qt6ct does not reach Qt 5), and the wallpaper picker running Matugen itself
(always dark) racing mooi's run after a wallpaper change.

## D92 · 2026-10-27 · The music player overhaul

**Asked for:** a library with album art and normal/detailed views; full screen fixed (it looked bad
and did not close); several view types; a small player first from the bar's icon, then the real one;
strong theming; creative visualisers; synced lyrics; video of songs; an equaliser; a better DJ vinyl;
and (mid-way) the mini player as something unconventional "like our Control Nexus … with nodes,
circuitry", and the bar's visualiser adaptive to the wallpaper like the rest of the bar. Designed in
`docs/superpowers/specs/2026-10-27-music-player-design.md`, built from
`docs/superpowers/plans/2026-10-27-music-player.md` in nine tasks; docs/PLAYER.md describes the result.

**Built:** one program, three sizes — the **signal-board mini card** (the cover as a core node in a
progress ring, pads and traces, a visualiser on the bus, pulses while it plays), the panel, full screen —
in one surface; three views — **DJ deck** (CUE, 33/45, pitch, VU), **cover stage** (sung line lit),
**instrument rack** (analyser, lit time, file format, EQ knobs, real waveform); six visualisers in
`shell/ui/viz.plm`, shared with the **bar**, whose visualiser now takes the main accent into the second;
the **library** (albums grid with covers, artists, genres, songs, sort, search, a cover cache, generated
covers); **lyric offsets**; the **EasyEffects equaliser**; the **music video** in the view's box.
Fixes on the way: the bar's media note swallowed by its wheel zone (dd83506), full screen on a second
surface that took no presses (4e15fff), a press right after closing taken as a second close, the mini
card's cover turning round the card's corner, the cover colours staying dark by day.

**Rulings worth knowing** (all in the plan's ledger): sixteen common bands for the visualisers; the
rack's format from ffmpeg (mpc cannot print mpd's `audio`); EQ off gives back the user's previous
EasyEffects preset because EasyEffects persists bypass and the last preset (found live and restored);
video fetched by yt-dlp then played (YouTube refuses mpv's stream), placed under the overlay with a
hole drawn round it; EQ state in `player-eq.json`.

**Checked live** on the real session with agent drives and real clicks: every size and transition,
quick reopen, the six visualisers in the mini card and the deck/full ring, the library (1281 albums,
covers page by page with one process at a time, groupings, sort, search), the three views in panel and
full, light and dark (also switching with the player open), CUE, lyric offsets kept across reopen,
the EQ (presets written, the user's two presets byte-identical, off restoring `live_eq` with bypass
off), and video in both boxes with mpd picking up where it reached. `bin/mooi check`: **294 unit
tests, 0 failed**. Not checked: the video's sound (output was muted), a live auto mode-switch at the
hour with the player open, multi-monitor placement.

## D93 · 2026-10-27 · One corner style for every plate

**Asked for:** a system-wide choice of chamfered corners or normal ones, with the radius from
Settings (rounded ↔ squared on a slider), and other border types if they work. **Done:**
`look.corners` (chamfer · bevel · round · square) and `look.corner_size` (0–24, 12 = as designed), on
Settings → Colour → Shape. `lib/style.corners` turns them into two facts every scene declares
(`cn_kind`, `cn_scale`), and the shared shapes follow them: `Chamfer` and `CutButton` (ui/loom.plm —
the bar's panels and islands' plates, the player, the board, the Nexus), `Plate` (ui/lumen.plm, the
wallpaper studio), `IslandFrame` (ui/island.plm: its rounded body takes the size, and goes square; under
chamfer and bevel it stays round, since its machined gradient body is a rounded box). Each shape keeps
its own designed corner; the size scales it. Checked live: Rounded (16) and Bevel on the bar and the
player, then back to the default. `bin/mooi check`: 299 unit tests, 0 failed. Not covered: the
settings window's own cards (drawn without these components), shapes drawn as raw paths outside them,
and the bar's body, which keeps its own `bar.radius` ("Corner rounding" on the Bar page).

## D94 · 2026-10-27 · BMO, better: starts with mooi, thrown, sized, coloured, aware, alive

**Asked for:** make BMO better and start him at login, with variants and animations, a smaller size,
a place on the bar, better dragging, and "pick, drag and throw him and he can bounce off the sides".
**Done**, in this order (one commit each):
- **Starts with mooi** (26d67ee): the bar supervises him (`bmo_sync` in shell/mooi.luau) while
  `companion.bmo` is on; he moved to shell/bmo and his settings became mooi's `companion` section.
  His data folder is a link to mooi's (bin/mooi `settings_link`): a link to the one file was
  replaced by a copy on his first `files.write`, so the folder is linked instead. Where he stands
  is his own (`bmo-state.json`).
- **Dragging and throwing** (1c59620): dragged, he is where the hand is at once; let go fast and he
  flies (brain.luau `release`, `fly`: gravity, bounces off the walls, floor and top, rolls to rest),
  dizzy after a hard landing.
- **XS and the bar** (54e002f): sizes XS/S/M/L; "under the bar" makes him small and over windows,
  walking just under the bar.
- **Variants** (818adcf): classic, night, pastel, Game Boy and mooi. Palettes in brain.luau, handed
  to the scene as `rgb()` numbers; mooi's comes from palette.json and follows the wallpaper, its
  ink pushed until the face on his screen reads (4.5:1).
- **Desktop awareness** (f9ad0da): a notification is "ding!" — the bar tells him (`emit tell N`:
  only one program may receive notifications), he never sees its words, and a whisper (muted,
  quiet time, low urgency) stays silent. A hop on a workspace switch, hungry at 15 % battery, glad
  on the charger, focused with the focus timer and a cheer when a block ends, good morning once a
  day, a yawn after 23:00. Each has its `companion.react.*` switch.
- **Idle life** (3a4e4aa): he sits, plays a little tennis on his own screen, hums with notes
  floating up, and peeks at a new window. One `set_activity` owns what he is doing, so a walk, a
  hand or sleep ends any of them.
- **Talk** (67f3686): off / rare / chatty governs every line; pools by moment that never repeat one
  of the last four; one bubble at a time (a passing remark never covers a ding, his hunger or a cheer).
- **Settings → BMO** (00b5bf7): every `companion.*` setting. The rail's items went from 26 to 24 px
  so its twenty-one pages clear the edit button.

Checked live: the bar starting him after a refresh, a real-pointer throw (walls, ceiling, floor
bounces, rest, "whoa…"), bar mode and XS, each variant from his LOOK tab and from Settings, a real
notification arriving as "ding!" with the second within 20 s silent, the focus cheer, his game,
humming and sitting, and the Settings page. `bin/mooi check`: 299 unit tests and 27 of BMO's, 0
failed. Not checked live: the workspace hop and the window peek (switching the user's workspace and
opening windows were left alone), the battery reactions, morning and late-night lines at their hours.

## D95 · 2026-10-27 · A system updates module

**Asked for:** an icon module on the bar that says when system updates are waiting, and runs the
updater when clicked. **Done:** the `updates` module (barlayout ORDER 29, width 42): a tray-and-arrow
icon, dim when up to date, lit with an ember count badge (as the bell's) when updates wait,
breathing while it looks; its tooltip says what is waiting ("48 updates · 26 packages · 5 AUR · 17
Flatpak"). bar.luau looks soon after starting and then hourly while the module is on the bar:
`checkupdates` (pacman-contrib: a temporary copy of the database, never the real one), `paru -Qua`
(or `yay`), `flatpak remote-ls --updates`; lib/updates (pure, 4 unit tests) parses and words it.
More waiting than at the last look is a notice through Signal Loom. A press opens kitty ("mooi ·
updates") running `paru -Syu` (else `yay -Syu`, else `sudo pacman -Syu`), then `flatpak update`, and
waits for Enter; its closing looks again. Placed on the user's bar before the bell. Found on the
way: `mooi refresh` had stopped restarting the bar (fixed separately). Checked live: the counts
match the three tools run directly. Not pressed: the press runs a real system update.

## D96 · 2026-10-27 · A hardening pass

**Asked for:** check recent work on a properly restarted bar, measure and fix performance, run the
live test scripts. **Found and fixed:**
- `mooi refresh` had not restarted the bar since a284174 (835bcb4) — every check since had run on
  stale Luau libraries. Re-checked on a fresh bar: corners, theme mode, BMO supervision; log clean.
- **The bar never rested** (71bfe83): the Overview timed double presses with `time`, and a scene
  that names `time` draws 60 frames a second for ever. Two layers on an instant spring hold the
  350 ms window instead. Idle: 1804 frames / 30 s → 0, 4 % → 2 % of a core.
- **The window island acted on the previous window** on every second opening (5332373): the scene
  set `open` before clearing `target_ok`. Close/Move/Float could reach the wrong window.
- **Search → "Workspace N" bounced back** (8110b6b): closing the palette after the switch let
  Hyprland refocus the old window. It closes first, waits the keyboard handover, then switches.
- The mark's menu toggles were re-emitted by a scene rule and toggled twice; removed.
- tests/integration.sh honours `island.follow_on_send` and waits for asynchronous switches.

**Measured, not changed:** workspace switching is mostly smooth (18 switches: 3.8 % of frames a few
ms late, none a whole frame lost, worst 30 ms); the late ones are painting (~12 ms, GPU, while
Hyprland animates too) — likely the switcher's glow; a look decision. The log's "slow frame" lines
measure the gap after a rest and overstate it; `pleamar --report` is the measure to trust.
**Tests:** unit 303 + BMO 27; scene.sh 71/71; config-recovery.sh 13/13; integration.sh 42/42 twice
in a row. Left to the user: deleting ~/.local/share/pleamar/bmo.old.1185462 (the auto-mode
classifier refused the delete).

## D97 · 2026-10-27 · The bar's islands: one kit, two styles, six new islands

**Asked for:** one design for every pop-up under the bar, a system statistics island from resources,
clock view states and a calendar, media view states, better volume/brightness/battery islands, a
weather island; then "Ferrolume plate option and our own something new options", and "do what you
think is best" (the user away; every choice below was delegated). Spec and plan:
docs/superpowers/specs/2026-10-27-bar-islands-design.md, docs/superpowers/plans/2026-10-27-bar-islands.md.

**The kit** (shell/ui/island.plm): `IslandFrame` draws the body in the style of `island.style` —
**plate** (a chamfered Ferrolume plate that follows look.corners, a lit top run, mono caps) or
**tether** (a rounded slab hanging 12 px under its module on a hairline tether ending in a lit node;
calm headers, pills, smooth meters). Pieces: IsleHead, IsleRule, IsleStat, IsleGauge, IsleMeter,
IsleBtn; BtnFace and Level follow the style, so the Window, System and Search islands changed with it.
Settings → Colour → Islands.

**The islands** (shell/mooi.plm; logic in the new shell/islands.luau; data read only while open):
**stats** (resources: CPU+temperature, memory, GPU busy, root disk, swap, the 3 busiest processes;
btop/nvtop), **calendar** (clock: 6×7 from Monday, ISO week, ‹ Today ›, wheel, arrows),
**weather** (weather module: now, feels/wind/humidity, high/low, 6 hours, 5 days with ranges; one
open-meteo request when opened, 10-minute cache, offline keeps the last), **sound** (volume module:
output and mic levels, mute, mixer, output devices), **display** (brightness, night light via
hyprsunset 4000 K, Dark · Light · Auto), **power** (battery: charge, upower's time and health, the
battery saver, the power profile only when power-profiles-daemon answers — masked here, so hidden;
keep awake, lock, session). Pure parsing, tested: lib/calendar, lib/stats (incl. upower), lib/forecast.

**View states:** the clock's right press cycles `clock.view` (full · time · seconds; also on Settings
→ Bar); the media module's right press cycles media.mode; play/pause moved to the visualizer's left
press and a middle press. The Control Nexus is left for its own spec (the user: "it can be different").

**Correction to D96:** "0 frames at rest" was measured while the bar was hidden behind a full-screen
window. With it shown, the idle bar redraws ~2 frames a second for real changes — the clock's second
hand and the resources readout — against 60 before D96. Still the fix it was; the number was wrong.

**Checked:** every island opened from its module (sound and display set open directly: the volume
module is not on the user's bar) and screenshotted in both styles; module press again closes; night
light on/off (process count 1 → 0); clock and media views cycled through and back to the user's own.
Unit 311 + BMO 27; scene.sh 71/71 twice; integration.sh 42/42 twice; config-recovery 13/13 three
times (its safe-mode wait fixed: --say succeeds against a stale socket).

## D98 · 2026-10-27 · The Control Nexus is a drawer

**Asked for:** "perfect the control nexus … all the important info inside and buttons leading
somewhere", "unobtrusive but has everything"; the user chose one Nexus (not two views), a right-side
drawer, and the twelve sections. Spec and plan: docs/superpowers/specs/2026-10-27-nexus-drawer-design.md,
docs/superpowers/plans/2026-10-27-nexus-drawer.md.

**The drawer** (shell/mooi-nexus.plm/.luau, rewritten; same program, same mark, `mooi nexus`): a
420 px column on the right edge under the bar, the screen's height below it, sliding in and out
(~220 ms); nothing is dimmed or covered; drawn by the island kit in plate or tether. Head: identity,
user@host, time, Settings · Lock · Session · ×. Sections, each folding (nexus.folded), the column
scrolling: quick toggles (Wi-Fi, Bluetooth, sound, mic, quiet, night light, keep awake, battery
saver, record — each lit when on, its state worded), levels, now playing (only while there is a
player), notifications (the bar's nexus-feed.json: app, title, when — never a body; none under
signals.private), Wi-Fi and Bluetooth rows that join / connect, outputs and app volumes, the machine
(CPU+temperature, memory, disk, GPU; btop on a press; the battery line), today (the week, the
weather — kept 10 minutes in nexus-weather.json; a press opens the bar's calendar/weather island),
system updates (the bar's updates.json; Update runs the bar's updater), workspaces, shortcuts.
Column geometry is lib/nexusdrawer (pure, tested); the feed is lib/nexusfeed (tested).

**Closing:** Esc, ×, the mark (the bar asks it to slide away), a blur, the workspace changing, or
another app taking the focus (by class — see the spec's deviation note). It ends 900 ms after it
starts sliding so a `pleamar --say` it just started is not cut off.

**Retired:** the node workspace and the hub, lib/nexus, nexusgraph, nexuslayout, nexusnode, nexushub,
telemetry and their 82 tests; the nexus.* settings only they read (a migration keeps identity and
folds, tested). The scene went from ~3500 lines and thousands of properties to 255 properties.

**Checked live:** both styles top to bottom with real data (networks, devices, apps, updates
"6 updates · 5 packages · 1 AUR", Springfield's weather); fold and unfold (saved, everything below
moves); the night light toggled through the bar and back (process 1 → 0); the wheel scrolls; Today
opens the calendar island; a notification opens the Signal Field; Esc closes; another app's window
closes it. Unit 234 + BMO 27; integration.sh 42/42. Not pressed live: Wi-Fi join, Bluetooth connect,
output switch, record, lock and session (each would change the user's machine or session).
**Fixed the same night:** the drawer closed as soon as the mouse moved. This Hyprland has
`input:follow_mouse = 1`, so the focus — and the keyboard — move whenever the pointer crosses a
window; closing on a focus change or a blur therefore closed it on every mouse move. Both rules are
gone: it closes on Esc, ×, the mark, or a workspace change. Checked with real clicks: open from the
mark, click inside, sweep the pointer across the windows — it stays; Esc closes it.

## D99 · 2026-10-28 · The orbital Nexus: you at the core of a circuit board

**Asked for:** "a different visual design altogether"; of three mockups (Monolith, Editorial, Orbital)
the user chose Orbital, "with nodes, circuit board, a little more creativity, has everything and is
customizable". **Done:** the drawer's top is a board (your banner faint behind it, a circuit pattern,
or plain — nexus.orbit.backdrop): your picture at the core in an accent ring, three live arcs round it
(nexus.orbit.arcs: any three of CPU, memory, temperature, GPU, disk, battery, volume, in shades of the
accent), a dashed bus ring, and eight hexagonal nodes (nexus.orbit.nodes: any eight of the nine
toggles and lock, settings, screenshot) wired to the core by traces with vias — a node that is on
lights its pad and its trace, and a press sends a pulse home along its wire (a layer, 550 ms). The
time and a capsule of buttons (customise ✎, settings, lock, session, ×) sit on the board; the name
(a press renames), user@host · uptime and the arcs' legend under it; the toggles not in the orbit
as chips below. ✎ opens a sheet over the board to choose the nodes, the arcs and the board, saved
at once. The column below keeps every section; the old toggle grid and profile card went into the
orbit. lib/nexusorbit (pure, 3 tests): the catalogue, cleaning a choice, the geometry of nodes and
traces. A table named `on` had shadowed pleamar's `on()` — the logic crashed at load until renamed.
**Checked live:** both styles; the Night node on and off through the bar (process 1 → 0, its trace lit);
arcs swapped to GPU and back, the board to Circuit and back (saved each time). Unit 237 + BMO 27.

## D100 · 2026-10-28 · The spine: shelves that slide out on hover

**Asked for:** "change the whole dynamic … shapes, shelves in and out, extensions extended out on
hover"; of three mocked dynamics (Spine & Shelves, Hive, Bloom) the user chose Spine & Shelves.
**Done** (in the bar's own scene, so hover is instant and nothing launches): nine hexagonal tabs down
the right edge on a slim backing — connections, sound, display, power, machine, calendar, weather,
notifications, updates (the last two with count badges). Hovering a tab for 140 ms slides its shelf
out level with it, tied to it by a short glowing trace; moving down the spine switches shelves; a
press pins one; it goes home once the pointer has been over neither the tab nor its shelf for 500 ms
(`on still max(tab.hover, keep.hover) for 500ms`). The shelves are the islands (D97) drawn beside the
spine instead of under the bar — each gained a `keep_*` region so reading it is "over it" — and three
of their own: connections (Wi-Fi and Bluetooth lists and radios; joining a known network, a locked one
opens Settings; connecting devices), notifications (count, quiet, open the Signal Field, clear all),
updates (what is waiting, Update now). A module's press still opens its island under the bar.
`shelves.on` (Settings → Colour, "The spine"). The bar may now control the network and Bluetooth
(`network.*`, `bluetooth.*`).

**Found:** `on hover dismiss for …` fires while the pointer is anywhere over that zone, even under
other zones; `on away tab for …` checks its `while` as the pointer leaves, before the shelf has the
hover — both closed a shelf the pointer had just entered. `on still` re-checks and resets.
**Checked with the real pointer:** hover opens, gliding into the shelf keeps it, sliding down the
spine switches (connections → machine), leaving closes; calendar, updates, weather (tether) shown.
Unit 237 + BMO 27. The Nexus mark still opens the D99 drawer: whether it stays is the user's call.

## D101 · 2026-10-28 · Hyprland 0.56's wobble, motion blur and finer blur in Settings → Windows

**Asked for:** "hyprland just had update with new functions like wobbly windows and blur functions add
them to settings so we can use them when wanted".
**Found** (Hyprland 0.56.2, `hyprctl -j descriptions` and the binary): no mesh-deforming wobbly
windows (no option, no string, no plugin loaded). What 0.56 has is spring-physics curves
(`hl.curve{ type = "spring", mass, stiffness, dampening }`), `decoration:motion_blur` and more blur
fields (`vibrancy`, `xray`, `popups`, noise, contrast…). An `hl.animation` without `style` clears the
one set before it.
**Done:** `desktop.wobble` (keep/off/subtle/wobbly/jelly) puts a spring of mooi's own, `mooi_wobble`,
under `windowsIn` (its `popin 87%` given again) and `windowsMove`: `off` is critically damped and each
step after overshoots further. Also `desktop.motion_blur` (keep/off/soft 6/strong 16 samples),
`desktop.blur_vibrancy` (0 keeps), `desktop.blur_xray` and `desktop.blur_popups` (keep/on/off), shown
while blur is not Off. They are all part of `desktop.look()`, so they apply live and at Hyprland's start.
Each one is claimed, so going back to Keep mine reloads Hyprland's own values.
**Checked:** each call evaluated live and read back; through the window, Wobbly + Soft set
`windowsMove` to `spring:mooi_wobble` and 6 samples and wrote the curve to hypr.lua; Keep mine
brought back `ease` and motion blur off. Unit 238 + BMO 27. Not checked: how each spring feels.

## D102 · 2026-10-28 · The Control Nexus is a deck, on any edge; Cascade beside it

**Asked for:** of three new directions (Console, Context, Scenes) "merge somehow all 3 i like the
workspaces shown underneath with preview but also remember we need it unobtrusive but with all the
info"; then "build it but make it so it can go top side or bottom … from side as well. it must look
great and ergonomic and flow nicely with our mooi type theme". Cascade (the spine's shelves all out at
once) "must be option in settings to have opt in or out".
**Done:** the Nexus program (shell/mooi-nexus.plm/.luau) is rewritten as the deck: one surface the size
of the screen, presses passing through where nothing is drawn, the deck sliding in from its edge
(`nexus.edge`: bottom · top · left · right). Along the top or bottom it is a 236 px strip (1680 px at
most): a head of scenes, what is waiting and who you are; below it this window, the workspaces and the
console. Down a side it is a 404 px column of the same bays stacked, only as tall as what it holds, kept
clear of the spine's tabs on the right. **This window**: its app, title, where it is, its own sound as a
level (the audio stream matched by process, then by name), Float · Full · Pin · Close, its last
notification. **Workspaces**: miniatures of the screen with the wallpaper and each window where it is,
with the compositor's picture of it (`thumbnails`, a 500 ms burst; atlas.previews and atlas.private
respected), "+" for a new one; pointed at for 260 ms, a 520 px preview grows out on the open side, where
a window is focused with a press, Go goes there and "Send window here" moves the window you are in.
**Console**: faders (everything, up to two apps that play, the microphone, the screen; press, drag or
wheel), eight lit switch keys, CPU, memory, battery, disk, and the song. **Waiting**: the pressing first,
each with the press that deals with it (recording → STOP, low battery → SAVER, notifications → OPEN,
updates → UPDATE, the weather → DAY, quiet → END). **Scenes**: Focus, Night, Present, Saver to start;
pointed at, what switching would change grows out ("quiet on · screen 35%"); a press makes it so (only
what differs is touched); "+ Save" keeps the desktop as it is as "Mine"; a right press removes one; the
scene the desktop already is wears a dot. Kept in nexus-scenes.json. **Cascade** (`nexus.mode`): nine
compact shelves (switches, connections, sound, music, machine, today, notifications, updates,
workspaces) come out 30 ms apart down the right edge, each tied to the spine and leaning out under the
pointer; a press acts or opens the full island. Both island styles (plate, tether) are drawn by the
same pieces (shell/ui/deck.plm). The geometry, the miniatures, what is waiting and scenes are
lib/nexusdeck (pure, 10 tests); lib/nexusdrawer and lib/nexusorbit are gone with the drawer (D98) and
the orbit (D99), and their settings (`nexus.folded`, `nexus.orbit`) go quietly.
**Found:** a full-screen surface is the monitor less the bar's reserve (1920 × 1049 here), so the deck is
placed in Hyprland's `reserved` area, not the monitor; library lets cannot name the Theme library's
tokens, and a colour cannot be chosen with `if()` in a let — the deck's colours are `mix(plate, tether,
isl_style)` over `rgb()` lets of the colour facts; a zone cannot be read from the `move:` of the group
that holds it.
**Checked live:** tests/nexus.sh, 21 checks (opens; every edge followed from settings.json while open;
the preview growing below a top deck; a scene's changes; Save writing nexus-scenes.json and a right
press removing it; Cascade; ending on close; a clean log). Screenshots of bottom, top, left, right, a
workspace preview, a scene's changes, Cascade and the tether style. Unit 242 + BMO 27. Not checked: the
faders and switch keys pressed by a real pointer (their events are the drawer's, which were), several
monitors, and a screen narrower than 1366 px.

## D103 · 2026-10-28 · The deck arranged by hand, seven parts, twelve quick settings; the rest of the list

**Asked for:** "where can i customize it and move parts around and i want better visuals details and all
other type quick settings… make it amazing unique cool and responsive", then "do the rest of still to do".
**Done:** the deck is made of **parts** — This window, Workspaces, Mixer, Quick settings, Music, Machine,
Today — each numbered in your order (01…07) with a lit head. **✎** on the deck arranges it: every part
shows MOVE (carry it along the deck; it is put back where its middle is let go, lib/nexusdeck
`place_at`) and × (hide it); the head becomes an arranging bar with the four edges as little screens,
the hidden parts to show again, Reset and Done. Kept in settings.json `nexus.parts` / `nexus.hidden`;
Settings → Colour → Control Nexus says where. **Responsive:** along a strip the parts are packed in your
order and, when the screen cannot hold them all, the least kept give way first (Today, Machine, Music,
Mixer, This window; never the workspaces), listed in the arranging bar as having no room; the deck is
only as wide as what it holds and the room left is shared out. Down a side the same, by height.
**Quick settings:** twelve tiles with their icons, lit while on, their state in words — Wi-Fi,
Bluetooth, Sound, Mic, Quiet, Night, Awake, Power (cycles power-saver → balanced → performance through
power-profiles-daemon; "No daemon" when it is not there), Record, Dark/Light (the bar's `set_mode`),
Screenshot (an area), Clipboard. The old "Saver" key and scene drove motion.saver, not the battery: a
scene's `saver` is now the power-saver profile. **Machine:** the last 40 s of the processor and the memory
as bars (sampled every second while open), heat, disk, battery, uptime. **Today:** the date large, the
weekday, the weather glyph and temperature, the week from Monday. **Mixer:** a scale on every fader.
**Music:** the cover with its shadow, the player, the song, elapsed and length, the transport. The
deck's corners carry registration marks; the head is a raised band. **Window pictures:** a 900 ms burst
asked twice (the compositor's pictures often come on the second); a window without one shows its app's
name; the wallpaper under the miniatures is a 640 × 360 copy (nexus-wall.jpg — the studio's copy has no
extension and was never drawn). **The rest of the list:** a miniature window carried onto another
workspace's tile moves there (onto its own, a press: go there); "+ Save" opens a naming panel — the name
(twelve letters) and, if wanted, one of the Overview's saved environments to restore with the scene (the
bar's new `env_restore_at`, environments.luau: planned and carried out at once); and the spine hides
(`shelves.autohide`): its tabs slide off the edge, touching the edge brings them back, 700 ms off them
(and no shelf out) puts them away, and a hairline keeps their place, ember while notifications or updates
wait.
**Found:** `local.x` counts from the zone's own `from:`, so the faders and the window's sound read a few
pixels off before; zones declared in a `repeat` could not be read after it in one place (the transport's
are written out); a colour cannot be chosen with `if()` in a `let` (`mix(a, b, flag)` does it).
**Checked:** tests/nexus.sh 31 checks (adds: twelve quick settings, every part on a wide screen, ✎, a part
hidden and kept, a part carried to the front and numbered 01, Reset, the edge chosen on the deck, a scene
saved under its typed name). Unit 244 + BMO 27. The spine's autohide in the running bar through its
facts (hidden, revealed, put away after the pointer left, restored). Screenshots: the deck, arranging,
the naming panel with environments, the left column with a preview. Not checked: carrying a part or a
window with a real mouse (the rules are the deck's own; only their events were driven), and restoring an
environment from a scene end to end.

## D104 · 2026-10-28 · The deck in HUD fashion: lamps, master caution, lock-on, power-on

**Asked for:** "use the new designs i added for inspiration if possible … surprise me and wow me". No
design of the user's was found (the repo, the home folder, the claude.ai artifacts and the Open Design
library were looked through); what had just been added was the Open Design plugin, so its catalogue was
the inspiration: its **HUD** system (a fighter's head-up display), taken for its rules, not its green —
status in four states, a warning that overrides everything, reference brackets, nothing animated that does
not say something has changed.
**Done:** every part's head carries a **lamp** — standby (dim), active, caution (flare), alert (a fixed
red, #ff4d4d, that no palette takes over): the window lit while there is one, the mixer amber while muted,
quick settings red while recording, music lit while playing, the machine amber past 90 % memory or disk
and red when hot. A **master caution** replaces the clock in the head while something presses — ● REC, a
battery at 20 % or less off the charger, heat past 85°, the processor past 90 % — naming the most pressing
one. **Lock-on:** four brackets close on the workspace pointed at, again for each new one, with LOCK, as its
preview grows out. **Power-on:** opening, a lit scan line sweeps the deck once (620 ms) and the parts come
online after it, 50 ms apart, each easing in from its edge; with reduced motion the springs settle and it is
simply there.
**Checked:** tests/nexus.sh 31/31; unit 244; a recording of opening, the lock-on and arranging, its frames
read (the sweep with later parts dark; the brackets and LOCK on workspace 1).

## D105 · 2026-10-28 · The deck is cards on a circuit; every one moves; profile, activity, a visualiser

**Asked for:** "nodes circuitry · move any of those modules around, even the scenes · option bigger banner
and profile pic · a music visualiser, maybe on the border · better visual of the music player · better
borders and cards · … that activity map of hyprland use".
**Done:** the deck has no fixed head any more: **every part is a card** — Profile, Scenes, Waiting, This
window, Workspaces, Quick settings, Music, Mixer, Machine, Today, Activity — and every card can be carried
anywhere with ✎ (scenes included). A **rail** along the top keeps the deck's own controls (time or the
master caution, ✎, settings, lock, session, ×) and the circuit's **bus**: each card's lamp is wired up to
it with a trace and a pad, neighbours are joined by traces down the gaps with vias at the turns, and the
power-on runs a pulse along the bus as the scan line crosses. Cards are cut plates (look.corners) with a
lit run off the cut, a corner tick, and a lift and shadow while carried. Cards **flow** in your order into
one row or **two** (nexus.rows), each row filled out to the deck's width, the least kept giving way only
when two rows cannot hold them; a first deck keeps Mixer, Machine, Today and Activity on the shelf.
**Profile**: your banner across the top (or a pattern of its own), your picture over its edge, a press on
either to change it (zenity, `mooi identity`); small or large (nexus.profile). **Music**: the cover faint
behind the card, a 16-band visualiser under the song; and a 32-band **visualiser on the deck's open edge**
while something plays (cava, nexus.visualiser). **Activity**: the last seven days hour by hour as a heat
map and the three apps most used, from activity.json, which the bar now counts a minute at a time (the
focused window's app; shell/activity.luau, lib/activity, 8 days kept). The arranging controls grow out of
the deck: edge, rows, profile size, the shelf, Reset, Done.
**Found:** a fact the logic sets itself does not fire the logic's `fact:` handler (the visualiser waited
for one); text sizes must be numbers, not expressions; cava reads silence while the sound is muted.
**Checked:** tests/nexus.sh 35/35 (adds: the first deck's seven cards and four on the shelf, the circuit's
seven nodes, Scenes carried to the front, two rows and a large profile saved); unit 247 (layout rewritten:
rows, packing, shelf, placing across rows, circuit, chips; activity). Screenshots of one row, two rows with
every card, the right column, the large profile with the real banner and picture. Not seen: the
visualiser moving (the machine was muted), the activity map with a week in it.

## D106 · 2026-10-28 · The side notch; Claude in the shell and in BMO; GitHub; notches off the Nexus

**Asked for:** "a notch on the side that'll open up on hover and that can be a Claude chat … wire up
Claude (you) to BMO and create a bar module for you that opens a nice panel, … a GitHub module that opens
up all relevant info with activity", then "a notch on side, open on hover, an arc like wallpaper switcher
… the workspace view as an arc for preview and switching, music player slides out … better weather
visuals", and "it's in the way of the stash, do it so I can drag on the side of the screen edge, but I
originally meant for those notches to come off the side of the Control Nexus".
**Done:** **the side notch** (shell/mooi-notch.plm/.luau, lib/notch): a lit sliver on the left edge, started
by the bar and kept running (notch.on) so pointing at it is instant; it fans out into six hexagonal tabs
on an arc — Claude, Music, Workspaces, Wallpapers, Weather, GitHub — each opening its panel; carried along
the edge it stays where it is let go (notch-state.json; it starts a third of the way down, above the
stash); it folds away when the pointer leaves, unless a tab was pressed or Claude is answering.
**Off the Nexus:** the deck grows two notches of its own — tabs rising from its corners along a strip,
from its open side down a column — and pointing at one opens that panel beside the deck (lib/notch
`from_deck`); the deck closing takes the panel with it. **Claude:** a chat with your own Claude through
Claude Code (lib/claude): `claude -p` in stream-json, read as it answers, no tools (it talks, it cannot
act), plugins' hooks off for the call, no MCP, no skills, run where no CLAUDE.md is (the runtime folder) —
about five seconds and under a cent a turn; the conversation goes on by its session and is kept in
notch-claude.json; New chat starts over; suggestions when empty; claude.model picks the model. **BMO:** his
menu has Ask BMO… (the chat in his voice: Claude answers as BMO and he says it in his bubble, a line at a
time) and Chat with Claude. **Music** slides out: the cover behind, the song, a 24-band visualiser, where it
is, the transport. **Workspaces** and **Wallpapers** are carousels on an arc, the middle one largest, the
wheel turning them: a press goes to a workspace (its windows drawn where they are) or wears a picture
(thumbnails made once into the data folder; applied as the studio does — the picker, else awww).
**Weather**: now (glyph, temperature, feels, range), the next six hours as bars, five days with their
range bars. **GitHub** (through `gh`, signed in as you): you, your contribution calendar for 26 weeks,
your open pull requests, what you did lately, your latest repositories, the unread count (on the tab and
on the bar's module). **Bar modules** Claude and GitHub (lib/barlayout, appended so no code moved) open their
panels; both were added to the user's bar.
**Found:** `claude -p --bare` is not signed in (it skips the keychain); without `disableAllHooks` a turn
cost ~$0.08 and 12 s (the user's plugin hooks), with it ~$0.004 and 5 s; a rule's header must be on one line;
a safety hook refuses any command whose text contains a destructive-looking string, even inside a test.
**Checked:** unit 249 (claude args/stream/wrap; notch fan, panels, carousel, bars, thumbnails, pictures,
`from_deck`); tests/nexus.sh 35/35; live: a Claude answer in the panel, BMO answering through it and
saying it, weather and GitHub panels with real data, the deck's notches opening Claude and the workspace
arc beside the real right-hand column, the bar's two modules. Not checked: carrying the nub with a real
mouse, the wallpaper arc wearing a picture (not pressed, to leave the desktop as it was).

## D107 · 2026-10-29 · Hyprland 0.57: real wobbly windows and blur finishes

**Asked for:** "now I have the Hyprland update so update those previous things with the new hyprland
functions". **Found** (the 0.57.0 binary, installed 2026-10-28 23:45; the session still runs 0.56.2 until
the next login): `decoration:wobble` (enabled, intensity, stiffness, damping, mass, mesh — a spring mesh
that bends a window while it is moved or resized) and `decoration:blur:variant` with acrylic, aurora,
drops, fluid_jar, glass, haze, heat_shimmer, ripple and water (each with its own fields).
**Done:** Settings → Windows → Wobble now also turns on the real wobble (subtle 0.6 · wobbly 1.0 · jelly
1.7 intensity, their stiffness and damping); Off turns it off. A new **Blur finish** row (Plain, Glass,
Acrylic, Water; or a moving one: Ripple, Aurora, Haze, Heat, Drops) sets the variant. Both are sent as
`pcall(hl.config, …)` of their own after the look, so 0.56 prints that it does not know them and goes on
(checked live: the setting after it still applied).
**Not checked:** how they look — that needs 0.57 running (log out and in). The variant's value is the
name as the binary lists it; if 0.57 wants another spelling, its error will say so in the log.

## D108 · 2026-10-29 · A Control Nexus settings page; angular notches; cards resized

**Asked for:** "fix the notches on nexus like angular, improve the spacing on them when things expand out …
put all proper settings for all this and easily found where makes sense", "option on control nexus resize
the cards and they adjust well and automatically". **Done:** a page of its own, Settings → SHELL →
**Nexus**: the deck (what the mark opens, edge, rows, profile size, music on the edge, notches off the deck),
the spine (on, hidden), the side notch (on) and Claude (its model: default, Haiku, Sonnet, Opus); the rail
tightened to 22 px an item so twenty-two pages and five groups clear its button. The deck's **notches** are
cut trapezoids rising out of its corners (hanging under it at the top, out of a column's open side), their
hexagons 48 px apart; a panel opening from one leaves the notch's 34 px and a gap clear. **Cards resize**:
✎ ⇔ on a card turns it small · medium · large (0.82 · 1 · 1.4 of its width along a strip, 168 px at least);
the deck packs again round it (the workspaces take or give the room), a card too large for the row says so
and gives way; kept as nexus.sizes. Also fixed: the Workspaces card on the shelf broke the tiles (a removed
size constant). Checked: unit 250; tests/nexus.sh 37/37 (adds ⇔ making a card large and wider); the page
and the rail captured; the notches and a panel opened from one captured on a bottom deck.

## D109 · 2026-10-29 · BMO: his own chat, game pop-ups, a tantrum, peeking from behind windows

**Asked for:** "the bmo claude chat for the chat to be inside him", "when bmo plays games … a notification
pops up on his screen, make an angry emotion for him where he throws an angry tantrum, more animations …
he can peek through on and under windows". **Done:** his panel has a **CHAT** tab (and his menu's "Talk to
BMO…" opens it): what you type there goes to the side notch, which asks Claude in BMO's voice on a session
of his own and sends the answer back — he says it in his bubble, a line at a time, and it is written in the
panel; his surface takes the keyboard only while his panel is out. While he plays his game, **pop-ups** drop
onto his screen (1UP!, HI-SCORE!, LEVEL UP, COMBO x3…). Poked four times in three seconds he throws a
**tantrum**: a new angry face (slitted eyes, hard brows, a square shout, flushed), a stamping, shaking
gesture done twice, his screen washed red, steam puffing out of his head, a cross word, and grumpy after.
**Peeking**: now and then, instead of a stroll, he goes to the edge of a window on your workspace, tucked
behind it (he lives under the windows), leans out with a glance and maybe a "peekaboo!", and goes back.
Outside codes 126 peek, 127 tantrum. Checked live: the chat answering in his voice (8 lines in the panel),
four pokes setting off the tantrum and its words, a peek to a window's edge and back. BMO's 27 tests pass.

## D110 · 2026-10-29 · The side notch answers the real pointer; the wheel stays on the chain; Super alone opens nothing

**Asked for:** "left side panel … its there but nothing happens", "holding super opens search … only make 1
and that is super+a", "fix workspace logic numbering and scrolling". **Found:** the stash's 12 px edge strip
(D54's drop catcher, y 233–847 on a 1080 screen) is an overlay surface and the notch is a top one: the nub
(y ~275–415) sat entirely under it, so a real pointer never reached it — D106 had only been tried with
synthetic events. Moved below the strip, the same hover opened the fan. The bar's wheel clamped to
spine.max_workspaces (5) although the chain grows to the focus (9): a turn "next" from 9 went to 5; and
asking for the workspace already there is, with Hyprland's workspace_back_and_forth on, "go back" — the
wheel at the end of the chain (and a press on the lit workspace) threw you to the last one.
**Done:** the notch writes the band its nub and fan need (cut0, cut1, screen pixels; lib/notch `cut`,
NUB_REACH 150) to notch-state.json each time it places the nub; the bar watches it (`notch_cut`, facts
nub_cut0/1) and cuts its edge strip in two round it (zstash_catch, zstash_catch2); with the notch off the
strip is whole again. A nub carried onto the stash's tab is put just above or below it (lib/notch
`nub_cy`). The wheel clamps to the chain as drawn (`ws_last`, from lib/spaces rows); `ws_pick` leaves the
workspace already focused alone. The Super-alone binding (ArchEclipse's search) was dropped from the
machine-local ~/.config/hypr/config/custom/mooi.lua and is unbound; Super+A is the one key.
**Checked:** with the real pointer (hl.dsp.cursor.move) the nub at its default place fans out and folds
when left, and the strip below still catches; ydotool's wheel over the compass: 9 → 9 at the end, 8, 7,
back to 9; Hyprland reloaded without errors, no Super-alone bind left; unit 250, BMO 27.

## D111 · 2026-10-29 · Two rows on every edge; the wallpapers arc narrowed by colour; a restart for Hyprland

**Asked for:** "one or two rows … when i click two rows i dont see a difference", "two rows doesnt work on
the left and right side and only top and bottom, i want it for all sides", "the quick wallpaper switcher …
only has same few wallpapers can we add more … on the inside is a range of colors and shows wallpapers of
those colors", "the bottom and top nexus have different modules they must be the same card types, visuals
why do they miss the left and right deck", "a restart hyprland button that refreshes it and restarts the
bar".
**Rows:** `nexus.rows` was read only along a strip, and even there it meant "flow onto a second row when
the first is full" — with a handful of cards, nothing moved. Now **Two means two**: the cards are split
over both in your order, half the width each (lib/nexusdeck `layout`); down a side the two rows are two
columns, and the deck grows out towards the desktop (800 px wide at 388 a card). The Settings row is no
longer hidden for a column.
**The cut:** both splits walked down from the middle and could settle on a cut where the first side fits
and the second does not, and a card gave way although another cut held them all — the right deck showed 5
of 11 cards for it. `M.split` scans every cut and takes the one nearest the middle that holds both (or the
least overrun when none does). All four edges now hold the same eleven cards at the same settings.
**Wallpapers:** the panel showed the first forty names of three thousand, alphabetically, every time. It
draws forty afresh each open (lib/notch `draw`), the one worn pinned first; thumbnails are cached by path.
**Colour:** each picture's mean colour is read once, in the background, a batch of 32 through one `magick`
(a JPEG read at `jpeg:size=64x64`, then sRGB — a grey picture has one channel and its green and blue read
as none otherwise), kept in `wallpaper-hues.json`; greys are filed under nothing. Twelve bands are drawn
along the inside of the arc (a ring at 0.62 of the cards' radius, made to the screen's height, so it stays
clear on a short one); a press narrows the arc to that band's pictures and says how many, pressing it again
gives the whole folder back. The folder's colours are read first for the forty on the arc, so a press has
pictures under it at once; the rest of the folder is read at about 30 a second and the caption counts it.
**Restart:** `mooi restart-hypr` runs `hyprctl reload`, then the bar comes back on the new config (windows
stay open; mooi's own windows restart); Settings → Advanced → Restart Hyprland and a ↻ in the Nexus rail.
**Checked:** 253 unit tests; `tests/nexus.sh` 37 checks against the compositor; every scene compiles; the
right deck measured 800×994 with all eleven cards; pressing a colour on a live panel narrowed twelve
pictures to the one cyan among them, its thumbnail made.

## D112 · 2026-10-30 · Music on every edge: one feed, one rim

**One producer, one feed, one library.** The rim used to be four private copies: `BarFoot` in the bar,
`EdgeBars` in the Nexus, and cava read separately by the notch and the player. `shell/lib/vizfeed.luau`
writes one line (`viz-levels.txt`: 32 bands, bass, high, beat, phase, playing, missing, seq) from the
bar's single cava at up to 30 Hz, and every surface folds those bands into `rm0..rm15`, `rm_bass`,
`rm_high`, `rm_beat`, `rm_phase`, `rm_gain`, `rm_glow`, `rm_on` and draws `shell/ui/rim.plm` on its own
border. A repeated or older `seq` is refused; two seconds without a line settles every rim (`rm_on` 0).
The bar starts cava when the visualiser or `frame.music` wants it, so a machine has one cava, not four.

**The rim is the border lifting.** `Rim.Edge` runs bars along a straight edge, each reading the band at
its place on the whole edge, joined at the feet and capped in the surface's own line colour;
`Rim.Rect` lays four edges round a plate with corner gaps and a side mask. At rest `rm_on` is 0 and
nothing extra is drawn: the plain border is still the border. `music.rim` (default on), `music.rim_gain`
(25–150) and `music.rim_glow` are the master controls; the retired `bar.foot_visualizer` is read only
when `music.rim` is absent.

**Where it draws.** Bar: islands' frames and the full panel (left, right, bottom), the notch pieces'
feet, and every bar pop-up (left, right, bottom). Nexus: the deck's open side and notch tabs, and only
the card being carried. Notch: each panel's four sides; the nub and the fan's tabs glow on the beat but
grow no bars. Player: mini, panel, and the cinema's inner stage/rack. The screen frame is deliberately
left plain: its music body was the most expensive thing in the scene and the effect the user disliked,
so `frame.music` now defaults to **false**.

**Measured:** with the bar idle in islands mode, 61 fps, 0 late frames; rules 1.15 ms, compose 0.97 ms,
paint 0.52 ms, the rest waiting for the screen. Splitting the bar's layer into a 1920×160 strip and a
pop-up surface cut an active frame's paint (5.6–6.3 ms over the whole 1920×1080) to the strip alone.
Not measured while silent: `pgrep -c cava` under playback, and the 60 s rim-on/rim-off samples — nothing
was playing music during the pass.

## D113 · 2026-10-31 · Hyprdrive's Overview in Pleamar, and the engine switch

**One overview, ours.** Hyprdrive's overview is compositor C++ tied to a Hyprland ABI; mooi's is a
Pleamar scene that is theme-aware, keyboard-owned and scriptable. The parts that belong to an
overview were ported: the wheel and ← → step the existing desktops and keep the Overview open
(`lib/atlas.step`), a window dropped past the last strip cell makes the next desktop, and the search
row falls through from the board to a safe sum (`lib/calc`), ranked installed apps and bounded files
from the folders people keep (`lib/filesearch`). Four opt-in 6×6 hot-corner surfaces open it after a
configurable rest. `atlas.engine` chooses Pleamar or Hyprdrive's plugin, which is only a dispatch
point while its plugin is not loaded; the Pleamar side closes the plugin's overview before opening,
so the two never stack. Not portable, and documented as such: tap-Super (a client never sees a
modifier release), finger-following swipes, scrolling-layout pass-through, Mosaic, and GNOME search
providers (sums are parsed by a tiny evaluator with no `load()` and a size cap instead).

## D114 · 2026-10-31 · The Mission shape: Hyprdrive's own picture

**The port is visual, not only behavioural.** Settings → Overview → Shape gained **Mission**, and it
is the default: the wallpaper behind (`blur: 14`, `brightness: 0.55`, a 52 % veil), a strip of the
workspaces you are not on (96 px high, at most 176 wide, 12 apart), and one large card for the one
you are (letterboxed, capped at 1480 wide, down to 44 px above the foot) whose windows sit on an
18 px mission grid — one column for one, two up to four, three beyond. The geometry is
`lib/atlas.mission`, pure and unit-tested; Grid, Strip and Canvas stay because each is still the
right shape for something. Focus, close, drag-and-carry, wheel/arrow stepping, type-to-run, sums and
file rows all work in it unchanged, and the large card follows the desktop the wheel steps to
because the workspaces watch rebuilds the board while the Overview is up.

## D115 · 2026-11-01 · Spring edges: a held window at the edge steps the desktops

**Hyprdrive's `drag:spring_edges`, in the Overview.** Carrying a window into the left or right edge
of the screen (28 px) and holding it for 420 ms steps to that desktop, and holding on keeps stepping
every 420 ms; the edge lights, a pill names the desktop, and let go away from the board the window
goes to the desktop the hold reached instead of gliding home (`lib/atlas.spring_target`). The scene
only reports where the pointer is (`ov_edging`); the logic steps, through the same `step_desktop`
the wheel and ← → use, so all three walk one list. Leaving the edge cancels the rest. `atlas.edge`
and `spring_target` are pure and unit-tested, and `atlas.spring_edges` is a setting (on, as
Hyprdrive has it) whose control is the last code, so no other setting moved.

## D116 · 2026-11-01 · Canvas edges: the same hold pans the field

**The canvas has no next desktop to step to, so the edges pan it.** The same band, in any of the
four edges, moves the camera toward the edge — up and down as well as sideways — while a window or a
workspace's nameplate is carried. The speed is `atlas.pan_by`'s 1100 screen px a second divided by
the zoom, so it looks the same near or far, in a step every 16 ms that stops by itself when no edge
is held. The scene reports both axes (`ov_edging`, `ov_edgey`); one loop in the logic moves
`ov_cx`/`ov_cy` and emits `ov_pan`, which the scene answers with `cam_x: ov_cx ~0ms` — the camera
must be where the pan put it, because a drop reads the world through that corner and a camera still
gliding would land a territory off. Hyprdrive's Mosaic canvas itself stays out of scope: it is
compositor layout, and a layer-shell client cannot park windows off screen.

## D117 · 2026-11-01 · The panels are drawn *inside* the popup surface
D112 split the bar off the pop-up layer: the strip became its own 1920×160 surface, and
`popup_surface` (full screen, just above it) took the panels. But a named surface carries what
is **inside its braces**, and the panels had been left loose after the declaration, so they went
to the scene's own surface — the strip's, 160 px tall. Every island, the quick-notes pad, the
settings panel, the spine's shelves and the press-away plate were painted on it and had their
bottoms cut off at y = 160; `screen.height` also read 160, so the plate reached only 129 px
down and the shelf clamps collapsed to `st_res + 6`. The declaration now sits after the hot-
corner surfaces, its block wraps the panels and closes before `frame_surface`, and the height
the panel content measures is `popup_surface.height` (1080) rather than the strip's.
Checked live: with the system island open, the pop-up surface's regions are the full-screen
plate (0, 31 → 1920, 1080) plus the island's rows, and the notes panel's rows land inside it;
`tests/scene.sh` 60 state + 7 motion, `tests/pointer.sh` 3, both 0 failed.
*To change back:* leave the panels loose; nothing else depends on where the block sits, and the
cost of moving one back is the clipping this fixes.

## D118 · 2026-11-02 · Visualisers live inside music components; one wallpaper picker

**Borders no longer move with the music.** The rim of D112 is gone from the bar's pop-ups, the notch's
panels and the Nexus (deck, notches, the carried card). What stays, by the user's choice, are the
visualisers *inside* the music components: the bar's media module, the notch's Music panel, the Nexus
Music card and the player. Outside them only the screen frame moves (D119), with the bar's border joining
it when `frame.music` is on. The feed (`viz-levels.txt`) is written only while a reader asks for it
(`feed_want`), and the theme watcher no longer wakes on it (it cost ~60 % of a core while playing).
The Nexus fell from 14,996 to 807 properties.
**Wallpapers:** Lumen (the studio, its library, kit and settings page) is removed. Skwd Wall is the one
other picker (`mooi wallpaper`, the bar's button, the notch panel's button); the notch's own Wallpapers
arc stays (the user asked for it back), walking the whole folder through a sliding 40-row window.
**Also removed:** the Overview's Mission shape (D114) and the Hyprdrive engine switch (D113) — the plugin
never built here. `atlas.engine` stays in the schema only so later setting codes keep their places; a
file that chose mission or hyprdrive is migrated to the grid.
*To change back:* the rim library (`ui/rim.plm`) is still used by the frame; re-adding it to a surface is
a matter of folding the feed there again, at the property cost above.

## D119 · 2026-11-02 · The screen frame is its own program; its border is one line with the bar's

Pleamar's per-frame cost grows with the scene, and the bar's scene held ~17k properties, so anything
animating all the time (the frame's swell) cost ~20 % of a core. `shell/mooi-frame.plm/.luau` is now a
separate small scene, started by the bar while `frame.on` is set, under it. The bar writes `bar-geo.json`
(its pieces) when its layout changes; the frame reads it and draws the sides, the foot and the top. In
notch mode the frame's line turns into a fillet at each piece and the piece's own outline (open strokes
starting where the fillet ends) carries it round to the next, so frame and bar read as one border in
every mode; in islands and full mode the top line is the bar row's foot. Bar scene: 17,393 → 7,007
properties. Measured with music: bar 10 % + frame 6.8 % (was ~28 % for the bar alone); paused, frame 0.5 %.

## D120 · 2026-11-02 · The Nexus stays running

The bar starts the Nexus once, hidden; the mark toggles it (`emit nx_toggle`), ~0.1 s to the first frame
instead of ~1.1 s of compiling, and cards keep their data and graphs their history. Hidden, its readers
rest (0.5 % CPU). `MOOI_NEXUS_OPEN=1` opens it on spawn (tests). The opening is staged: a ~420 ms slide,
the scan once the deck is in, cards coming online behind it. Visualisers read the feed at its own pace
while shown (a coalesced file watch had held them to ~4 updates a second).

## D121 · 2026-11-02 · The side notch and the stash: one family

At rest each keeps the same lit hairline on its edge — brighter when pointed at, warm when something
waits (a badge on the notch, items in the stash). The notch's arc fan became a track of flat hexagonal
tabs, mirrored on the left edge, its panels opening beside the track (`lib/notch` PANEL_X 168 → 60).
One set of timings: revealed 60 ms after the edge is touched, a tab opens its panel after 140 ms, a
press pins it, and it goes home 500 ms after the pointer leaves.

## D122 · 2026-11-02 · Nexus: two rows are a free canvas

With two rows the deck becomes a canvas over the screen below the bar (`lib/nexusdeck.canvas_layout`).
In edit mode a card carried anywhere stays there (its middle where it was let go, on an 8 px grid, kept
on the canvas), and a corner handle sizes it (at least 168×96). Places and sizes are saved in
thousandths of the canvas (`nexus.canvas`, `c<n>_<x>_<y>_<w>_<h>`) so they hold on another screen; a card
never placed starts from the two-row deck, centred. The s/m/l size now works down a side too (it scales
the card's height), which gives the left and right edges the options the top and bottom had.

## D123 · 2026-11-02 · The spine is removed; visualisers gain automatically

**The spine (D100) is gone** — its tabs, hairline, three shelves, the Nexus's Cascade mode and their
settings. Islands open under the bar only; a file with `nexus.mode = cascade` gets the deck. (The scene
had `shelves_on` start true, which is why it showed while switched off.) This supersedes D102's Cascade
and D103's spine autohide.
**Gain:** cava hears the music after mpd's own volume, and the mooi player runs mpd quietly, so the bands
sat near 1/1000 of their range and nothing moved. `lib/vizfeed` now reads them against a ceiling that
rises at once and sinks over seconds, with a silence gate (unit-tested).

## D124 · 2026-11-02 · The two-row canvas stays inside the two rows; exact drops

**The user did not want the canvas over the whole screen** (D122): two rows keep the deck's own band on
its edge — the screen's width and two rows tall along the top or bottom, two columns wide from under the
bar to the foot down a side — and the free placement happens *inside* it. `canvas_layout` lays the normal
two-row deck on that edge for any card never placed, then lets each placed card keep its spot and size,
kept inside the band. The plate is opaque again (it no longer covers the desktop). Places saved under D122
were shares of the whole screen; they now read as shares of the band and are kept inside it (✎ → Reset
starts clean).
**Drops were rounded.** A card and a point went to the logic as `100000000·code + 10000·x + y`, but scene
numbers are float32 (whole only up to 2^24 = 16,777,216), so drops and corner pulls landed 32–128 px off
depending on the card. They are now `1000000·code + 1000·(x/4) + y/4` (at most 10,999,999: exact, to
4 px — finer than the 8 px grid), read by `lib/nexusdeck.unpack_event`. Checked in an isolated Nexus: a
card dropped at (920, 236) centred there; a corner pulled to 300×152 gave 304×152 (it gave 304×128).

## D125 · 2026-11-02 · Arranging the canvas made easy; every card the same on every edge; one Part

**Easier to place (asked).** While a card is carried or its corner pulled, the logic answers each move
(`dk_drag`, `dk_sizing`) with where it would settle, and the deck outlines that spot over the cards (the
landing; `dk_l*`, gliding on `m.select`). It settles by `lib/nexusdeck`: a **16 px grid** counted from the
first card's corner; edges within **14 px** of a neighbour's (side by side at the deck's 8 px gap, or lined
up with it) or of the band's ends **meet** them; a gap nearly its size **narrows it to fit** (to 60 %);
otherwise the **nearest free place**, never on another card. Let go with its middle **on a card, the two
change slots** (place and size together), since a full band has no free place; the other card's landing
shows in the warm tone. A corner stops a gap short of a card it would run into. The dropped card glides
from the hand to its place (its spring is set where it was let go), no longer from where it started.
Places are saved in ten-thousandths (`k<n>_…`; 1/1000 of the band was 2 px off the grid); `c<n>_…` still
reads.
**The same on every edge (asked: "why is the top and bottom one different to the sides?").** Cards chose
their layout by the deck's edge (`dk_vert`): down a side Music lost its visualiser, play plate and times,
the rail its date. Each card now lays itself out by **its own size**: Music is compact under 196 px tall
and keeps everything; Machine puts its graphs side by side when short; the workspaces' miniatures take a
row or columns, whichever makes them bigger in the bay (`tiles(…, nil, …)`); the date shows when the rail
is 560 px wide. `dk_vert` is left only for geometry (the sweep, the notch tabs).
**Redundancy.** The eleven cards each carried ~30 hand-copied lines of arranging controls and two glide
props; they are one `component Part` (children = the card's content), and `EditFrame` is gone: the scene
is 1806 → 1523 lines. The spine's leftovers are removed: `SPINE_W`/`opts.spine` (it still took 58 px off a
right-hand or canvas deck), the dead `GO[50]` shelf, a Cascade comment; the card events decode in one
`card_event`.
**Performance:** measured the same, open ~1.5–1.9 % and hidden ~0.5–0.7 % of a core, before and after; the
gain is in the code, not the runtime, which was already small. The `cat /proc/…` readers stay:
`files.read` is limited to the scene's own folder.
**Checked** with the real pointer (ydotool) on an isolated Nexus: a card carried onto Workspaces changed
slots with it (Workspaces took two columns in the narrow slot); a corner pulled to 211×205 settled
210×214 on the band's foot; a card let go at (326, 34) met Profile's side at (320, 30). `tests/nexus.sh`
not run (it clashes with the resident Nexus by name); 284 unit tests, `mooi check`.

## D126 · 2026-11-02 · The left edge's tabs as they were, as a pair; no border visualiser on the player

**The tabs.** D121 turned the side notch's nub and the stash's tab into 2 px hairlines; the user wanted
the earlier design back, the two the same, following the wallpaper. `ui/edgetab.plm`'s `Tab` is the nub
as it was before D121 — a raised sliver standing out of the edge, lit, three grip marks, a little larger
and brighter while pointed at or open — and both use it at the same 92 px. Its colour is the palette's
(Ferrolume's phosphor in Plate, the accent in Tether), so a new wallpaper relights it with everything
else. Something waiting (a notch badge, items in the stash) is a small dot near its top in the
counter-signal rather than a different colour, so the pair never shows two colours (with a GitHub badge
nearly always present, the notch's "warm" tab had become permanently the second accent). The nub's zone
is 14×140 again. The track of tabs that slides out is unchanged.
**The player.** Its mini, panel and full views still drew `rim.Rect` on their own border (D112). Under
D123's automatic gain those bars, at ~1/1000 before, started to move, so the bordered visualiser looked
"brought back". The user wants visualisers inside the music components only: the three `rim.Rect`s, the
player's `rm*` facts and their feed are removed; the player's own visualisers (`nv*`) stay. With this no
surface draws the rim except the screen frame's `frame.music` / `music.rim` (opt-in).

## D127 · 2026-11-02 · The frame is a chassis: iNiR's iRiS frame, in pleamar

**What the user had asked, and what had been missed.** At 12:52 the user asked for iNiR's music frame
"recreated exactly" (github.com/snowarch/iNiR), and at 13:05 confirmed a plan that included deleting the
bars along the bar's foot and building that frame; neither was done (the next commit removed the spine).
The audit of `mooi-frame` against iNiR found: the frame and the bar were two objects (islands floating
over a line under them); the band at 31 % read as smoke beside opaque islands; "swell" moved each side
in and out as a straight line; the streak under the bar was the old border visualiser (`rim.Edge`); the
outline was eight strokes glued with round caps, the neon halo doubling where they met; and the frame's
40 px round corners sat beside chamfered islands.
**iNiR's model** (`modules/iris/field/IrisField.frag`, `frame/IrisFramePulse.qml`): everything on an edge
is one signed-distance field — the band is the outside of an inset rounded rectangle, the bar's pieces
rounded boxes smooth-unioned into it, painted with one tint, one hairline round the union, one shadow.
Pleamar's `body` is the same thing (its shapes melt with `blend`, `border` outlines the silhouette), so
`mooi-frame.plm` is now one body: the band's four edges as closed paths (their blend rounds the inner
corners), then each of the bar's islands (islands mode), its three pieces (notch) or its panel (full)
as a box rising off the screen, blended into the band (12 px fillets). Fill, opacity, glass, frost,
smoke and shadow are the bar's own, so the bar and the frame are one material; while the frame is on
the bar paints none of those plates or outlines (`frame_on` in `shell/mooi.plm`) and only draws what
stands on them. `bar-geo.json` now carries the islands and the panel as well as the notch clusters.
**The music is iNiR's, exactly:** bass = the mean of the lowest four of sixteen bands, √, × 1.4; the
level follows it at 18/s rising and 3.2/s falling; the phase runs at (0.6 + 2.4·level)/s; the band's
inner edge is pushed in by level × reach (`frame.reach` × 1.6, 29 px by default) times
0.60 + 0.24·sin(y·0.011 + t) + 0.16·sin(y·0.027 − 1.4t) along the sides (x·0.009 − t, x·0.023 + 1.2t along
the top and foot, with `frame.edges`), and an etched light at 35 % runs along the moving edge. The old
swell/crests/pulse, the bar's border joining in (`music.rim` for the frame) and the band's own opacity
are gone from Settings (Moves with music: Off / Wave; the outline: line, neon, none).
**Measured:** with music, frame 4.5 % of a core (the old one 6.8 %), the bar unchanged; paused 0.4 %.
Checked live in islands, full and notch modes (screenshots), the wave with music playing (level ~0.5).
**Also:** the stash now opens when its tab is pointed at (60 ms), as the side notch does — the user had
asked that both "open on hover"; a press pins it, leaving closes it (checked with the real pointer).
**The corners (same day, the user's screenshot).** Two faults: the etched light ran the whole height of
each side, through the corners and the top and foot bands; and the corners were made by blending the
four edges, which bulged, and the top two took the 12 px fillet of the island sitting in them while the
foot's took the 35 px blend, so top and bottom differed. Now the edges join plainly and each inner
corner is an explicit quarter round of `frame.radius`, set where the moving side meets the top's inner
edge (the foot of a piece sitting in that corner, else the band) or the foot, computed in two steps so
its ends land on the moving edges; each corner piece reaches back to the screen's corner, so only its
round is ever an edge. The light runs only along the straight part of each side. Checked with a red
debug copy at full music level and live.
**The lag (same day).** With the music on, the GPU went from ~45 % to ~90 % and frames took ~117 ms: the
whole chassis was one full-screen body on one surface, so every step of the wave repainted the whole
screen. Measured by elimination: freezing the wave brought it back; removing the moving strips' bodies
or the glow and shadow did not; moving the moving parts to a second full-screen surface halved it. Now
the still chassis (band, pieces, corners at rest, the one outline) is on `frame` and is painted only
when the bar's layout changes; the moving edges are three narrow surfaces (`frame_l`, `frame_r` 128 px
wide, `frame_b` 128 px tall), open only while the edge moves, each a strip in the chassis's material
without an outline of its own (the wave only pushes inward, so they cover the still edge) plus one
stroked line tracing the moving edge and its corners. The top stays still (the bar is there).
Measured: GPU 54 % playing against 43 % paused (it was ~90 %), no slow frames in 6 s.

## D128 · 2026-11-02 · The frame swells on all four sides as one silhouette; a faster login
**Asked for:** all sides of the frame to swell with the music, smoothly, with the edges joined (they
came apart while music played), better performance, and a faster shell start at login.
**What was wrong (audited with a forced-level debug copy on the overlay layer, zoomed):** D127's split
left the still chassis under three moving strips with no outline of their own; its neon outline and glow
showed beside the moving edge in every corner (two arcs, broken pieces at the top corners), and the top
never moved. Measuring it also showed why a single moving body was so dear: pleamar draws a `body` as one
quad over its bounding box and every pixel measures its distance to *every* segment of *every* shape in
it (twice with a shadow), and a `curve` is flattened into length/4 segments.
**Now:** the whole frame is one silhouette — the band's four moving edges (the top too, between and under
the bar's pieces, which ride on it), the four corner rounds and the bar's pieces — drawn by four surfaces
that do not overlap (`frame_t` 160 px and `frame_b` 128 px the full width, `frame_l`/`frame_r` 128 px
between them), so each repaints only its own pixels. Each strip is cut into tiles: a body clipped to its
stretch (the clip bounds the quad) holding only the pieces of edge within 64 px of it, cut from the same
chain, so neighbouring tiles and strips meet exactly. The edges are straight steps every 22.5 px down the
sides and 30 px along the ends, within 0.1 px of the wave. `tools/gen-frame.py` writes it all
(`// <gen:frame>`). A corner now counts as covered by a piece of the bar within the side's whole swing,
not only its round, so a side never runs up past an island it would melt into (with `frame.radius` 0 it
did, and the etched light ran across the island); the light stops 8 px short of each round so its glow
does not either. **Measured** (per-process GPU time from DRM fdinfo, music level held at 0.75, 8 s): the
first single-body version of this 46 %, tiled 22 %, tiled in straight steps 10 %, the old split 7 % with
a still top; with straight steps the shadow is nearly free again, so it stays on while the edges move.
**Login:** `mooi session` compiled nine scenes one after another before the bar could start (~1.1 s
of every login). The live copy now carries a stamp (pace speed and pleamar version); when nothing under
`shell/` is newer, no file came or went and the stamp matches, it is used as it is; otherwise the nine
checks run at once (~0.8 s → ~0.5 s). The frame starts 50 ms after the bar's logic, not 1 s (until it is
up the bar's pieces stand on nothing, D127); the notch at 0.7 s (was 2 s), BMO at 1.4 s (was 2.5 s).
Measured from `mooi session` to the compositor showing the surface: the bar at ~0.7–1.0 s (was ~1.6 s),
the whole frame at ~1.0–1.2 s (was ~1.8 s). Not checked: an actual logout and login.

## D129 · 2026-11-02 · The notch's workspaces show the windows themselves, live, and stand closer
**Asked for:** live previews in the left side notch's Workspaces panel, and the panel brought in, as
it stood very far out.
**Now:** each miniature window paints the window itself (pleamar's `thumbnails` service). While the
Workspaces panel is up, the windows of the three workspaces round the arc's middle are asked for live
(`thumbnails.live`, copied when they change, up to 30 a second) and the rest on the arc for a still;
when the panel closes or changes, nothing is copied. Settings → Overview's previews and privacy
(`atlas.previews`, `atlas.private`) apply as in the Overview and the Nexus. A window is paired with its
picture by app and title, else by an unused one of the same app (a terminal's title spinner changes
between Hyprland's list and the compositor's). Hyprland does not draw a workspace that is not shown, so
a window there keeps its last frame (or, never seen, its plain box). The arc's middle card now stands a
fixed 260 px out from the notch (its centre was the arc's radius out, ~530 px on a 1080 px screen).
**Measured:** the notch at ~2.7 % GPU with the panel open on a busy terminal, 0 % closed; frames
advanced ?448 → ?458 in a second while open and stopped once closed. Checked live with a test window
moved to workspace 7 (its card showed its last frame).
**The Wallpapers panel too (same day):** its middle picture's centre now stands a fixed 390 px out
from the notch (it was ~530 px), its left edge just clear of the colour band along the arc's inside
(which reaches ~206 px); the cards further round stay clear of the band. The pictures were already the
wallpapers themselves, so nothing else changed there.

## D130 · 2026-11-02 · The Wallpapers panel: a source row under its title, and Wallhaven
**Asked for:** a better Skwd Wall button in a better place, and a second button that shows pictures
from Wallhaven.
**Now:** under the panel's title is one row: **FOLDER · WALLHAVEN**, the two sources (the chosen one
lit), then, past a divider, **SKWD WALL ↗**, the full picker, which opens a program of its own. The
button used to float alone at the panel's far top corner, 560 px out and level with nothing.
**Wallhaven** fills the same arc with the month's top list from wallhaven.cc's public search (no key):
safe for work only (`purity=100`, and any answer not marked sfw is dropped), general and anime, at
least the screen's size, and the screen's shape snapped to the nearest ratio Wallhaven knows. A page of
24 at a time, the next one fetched as the wheel nears the end of what is loaded. The colour swatches
search by the nearest Wallhaven colour. Thumbnails are fetched and cut to 16:9 as they near the middle,
kept as `wh-<id>.jpg` in the data folder. A press saves the full picture into the studio's folder as
`wallhaven-<id>.<ext>`, so it stays in the collection, and wears it the same way as any other (the picker,
its script, or awww). Only ids of letters and digits and https links on Wallhaven's own hosts are taken
from an answer (`lib/notch.wallhaven_page`, tested). Nothing is asked of Wallhaven until its source is
chosen. **Checked live:** 24 pictures with thumbnails, paging to 48, the Blues colour, back to the
folder; the full download checked on its own. Not checked: a press wearing one, which would have
changed the desktop's wallpaper and palette mid-session.

## D131 · 2026-11-03 · Why the GPU sat at its top clock with nothing happening
**Asked for:** find and fix the idle GPU use (Hyprland ~35 % of the GPU, the card at 1800 MHz, nothing
moving).
**Measured** (Hyprland's own GPU time from DRM fdinfo, on an empty workspace, clients paused with
SIGSTOP one at a time; `debug:damage_blink` to see what was repainted):
- Hyprland redrew the whole screen 60 times a second. With every client paused it still cost ~25 %:
  the **blur finish**. Only three of Hyprland 0.57's variants animate, and they redraw forever even on a
  still desktop: `drops` ~72 %, `aurora` ~30 %, `heat_shimmer` ~24 % (the one set here). Plain/kawase,
  haze, acrylic, frost, prism, water, fluid_jar and ripple cost 0 % when nothing moves.
- With the blur plain, pausing **BMO** alone took Hyprland from ~22 % to ~0 %. His "lively" breath was
  an endless posture (1.5 px over 3.6 s); while anything animates, a pleamar scene asks the compositor
  for a frame every tick even when nothing visible changed, so Hyprland drew 60 frames a second, and
  with blur each re-blurred the screen. (pleamar's own damage was small; snapping his height to half
  pixels did not help, the ticking is what costs.)
**Now:** his breath is a breath now and then: the logic raises `inhale` for 0.56 s every 3.4–4.2 s while
breathing, a 520 ms spring follows it, and he is still in between (bmo.luau `breathe`, bmo.plm `chest`).
BMO alone, breathing: ~22 % → ~4.6 %; everything running with the plain blur: ~22 % → ~9 %.
Settings → Windows → Blur finish now groups the finishes by what they cost: the still ones (Fluid jar
added, it was never offered), and the three moving ones in a row of their own that says they redraw all
the time (~25–70 % of the GPU, idle). The blur finish itself is the user's choice and is left as it is.

## D132 · 2026-11-03 · Islands that stayed on screen, BMO's copies: pleamar's frame pool
**Asked for:** the bar's islands glitch and get stuck, and so does BMO when he is moved a lot.
**Seen:** opening islands one after another (resources, weather, calendar, sound, power) left them on
screen after they closed, some frozen mid-fade or drawn half-cut; Escape closed none of them, and the
bar's state said nothing was open (`open = none`, every island's `rv` 0). Islands from before the test
were already stuck.
**Found, by elimination:** not the bar's drawing (a debug build of pleamar listed nothing on
`popup_surface` once the islands closed, and repainting it whole every frame changed nothing), not the
notch, Nexus, frame or BMO (ending each left the ghosts), not Hyprland's layer animations (off, still
there); gone with the whole shell stopped. With `PLEAMAR_SWAPCHAIN=1` — the surfaces presented through
the standard swapchain instead of pleamar's own pool of reused frames — the same sequence, run three
times, left nothing, the islands open and close normally, and BMO thrown about seven times in four
seconds left no copies. So under quick changes the pool showed a frame still holding an older frame's
pixels. **Now:** `bin/mooi` starts the shell with `PLEAMAR_SWAPCHAIN=1` (the keeper and `mooi run`);
every program the bar starts inherits it. The bar itself costs 0.4 % of the GPU this way.
**Not done:** the pool's bug itself is pleamar's (k4ditano/pleamar); not reported upstream (the user's choice, 2026-11-03),
and the installed copy is not patched: `PLEAMAR_SWAPCHAIN=1` stays the fix.

## D133 · 2026-11-03 · The launcher has one mode: mooi is the desktop
**Asked for:** remove the beside and takeover modes from `bin/mooi`.
**Why:** ArchEclipse has been uninstalled since D48, so there is nothing to run beside and nothing to
hand the desktop back to. Every start already fell through to `session`. The two modes were kept
alive only by `archeclipse_installed` checks, a marker file that ArchEclipse's scripts no longer read,
and a guard in a dotfile that no longer exists.
**Now:** `bin/mooi session` is the one way to start mooi. `start` is the same command, kept so old
keys and scripts keep working. On a running mooi it restarts on a fresh snapshot, which is what
Super+Shift+B is bound to. The keeper takes no mode: it runs the scene with `MOOI_MODE=session`, and
its `keep.pid` is the only state (the `takeover` marker and `mode` file are gone; `stop` clears
any left by an older launcher). `stop` only stops. `status` no longer reports ArchEclipse. The
`takeover` command, `bar.sh` / `shell-engine.sh` calls and the ArchEclipse helpers are removed.
docs/SWITCHING.md is now about running mooi. It still says how to restore ArchEclipse from its
archive by hand.
**Kept:** the `notifications.server` value `takeover` (a saved setting; it now means "while the keeper
runs mooi", and a bare `mooi run` still does not claim notifications). Settings → Advanced → "mooi is
the whole desktop" (mooi.lua still reads it, for the day ArchEclipse is restored).
**Checked:** `bin/mooi check` (286 tests, 0 failed). On the live desktop: `session` over the old
keeper, `refresh` (keeper kept), `stop` (no keeper left), `start`.

## D134 · 2026-11-03 · Two leftovers of the old modes
**Asked for:** tidy the two settings D133 left behind.
**Notifications:** `notifications.server`'s `takeover` is now `desktop`. That means mooi claims
notifications while the keeper runs it, and not in a bare `mooi run`, which now reports its mode as
`run` instead of `beside`. In Settings → System the choices are "Desktop · Always · Never". A saved
`takeover` is moved to `desktop` quietly on load (tested).
**Standalone:** "mooi is the whole desktop" is gone from Settings → Advanced, and `session.standalone`
now defaults to true. The key stays because `custom/mooi.lua` still reads it. Restoring ArchEclipse
means setting it false in settings.json by hand (docs/SWITCHING.md).
**Checked:** `bin/mooi check` (286 tests, 0 failed); both Settings pages seen on the live desktop.

## D135 · 2026-11-03 · Ready for Pleamar 0.7.11: what an upgrade from 0.4.6 changes
**Asked for:** find out whether Pleamar can be safely upgraded (0.4.6 → 0.7.11, language 0.4 → 0.9).
**Tried:** 0.7.11 built in a scratch worktree, never installed. All nine scenes compile unchanged and
`bin/mooi check` passes on it. Mooi ran on it for a session, every program included (the keeper's
PATH pointed at the new binary). The bar, system island, Overview, notch, Nexus, player and
search were all seen working.
**Found, and fixed for both versions:**
- **Covers:** 0.7's `media` service hands over a path (`/tmp/cover.jpg`) where 0.4 gave the URL
  (`file:///tmp/cover.jpg`), so the bar, notch, player and Nexus showed no cover. One rule now
  reads both, `lib/cover.luau` (unit-tested); BMO, which has its own require path, takes a path too.
- **`mooi refresh` turned the bar off:** 0.5+ quits cleanly (exit 0) on SIGTERM, as it does for
  `--say quit`, and the keeper reads exit 0 as "stopped". `refresh` now leaves a mark
  (`$XDG_RUNTIME_DIR/mooi/again`) that makes the next exit a restart; `stop` and `session` clear it
  first. Tested on both versions: two refreshes in a row keep the keeper, stop leaves none.
- **`ferrolume.plm:832`:** `max` was given three numbers. Only the first two were read, so an armed
  plate row never showed its 0.8 highlight. The calls are nested now.
**The frame pool (D132):** the same five real clicks and an Escape, three rounds each, without
`PLEAMAR_SWAPCHAIN=1`. On 0.4.6 every island stayed on screen while the bar said none was open (the
D132 bug). On 0.7.11 nothing was left behind. Upstream has fixed it.
**Not done yet:** installing 0.7.11. The scenes still declare `language 0.4`, and switching them to
0.9 is its own step.

## D136 · 2026-11-03 · Pleamar 0.7.11 installed; the scenes are language 0.9
**Asked for:** install the update tested in D135.
**Now:** the pleamar source (`~/.local/share/pleamar/src/pleamar`) is at tag v0.7.11 (2738889). The
binary built from it is `~/.local/bin/pleamar`, and the old one is kept as
`~/.local/bin/pleamar-0.4.6`. To go back: `cp ~/.local/bin/pleamar-0.4.6 ~/.local/bin/pleamar`,
check out v0.4.6 in the source, and revert this commit. All 21 scene files now declare `language 0.9`;
switched, they compile to exactly the same thing (property, instruction, rule and zone counts
unchanged). `tools/gen-settings.py` writes the new header, and `bin/mooi check` expects 0.9.
**Seen:** the first restart on 0.7.11 found a frame and a Nexus left over from 0.4.6, which does not
end what a scene started when it quits; 0.7.11 does. After removing them, a restart and a refresh
leave one of each program.
**Kept for now:** `PLEAMAR_SWAPCHAIN=1` (D132). 0.7.11 no longer shows the frame-pool bug (D135), so it
can go once a day on the new version has shown nothing else.

## D137 · 2026-11-03 · Desktop widgets in Pleamar: Now Playing and the Visualiser
**Asked for:** one widget system, all in Pleamar, "more mooi", fresh widgets, replacing the Quickshell
`~/.config/desktop-widgets`; music first. Spec `docs/superpowers/specs/2026-11-03-widgets-design.md`,
plan `docs/superpowers/plans/2026-11-03-widgets.md`.
**Built:**
- **The program.** `shell/mooi-widgets.plm` + `.luau`, kept by the bar while `widgets.on` (on by
  default). One full-screen surface on the bottom layer, below the bar's strip (it reports its size,
  `wg_room`, so `widgets.json` coordinates are under the bar). Empty parts take no clicks.
  `rate: 30, 4 while calm`.
- **The model.** `lib/widgets` (pure, 16 tests): widgets.json validation (at most 8 widgets; bad
  entries dropped; an unreadable file becomes `widgets.json.bad` and the defaults show), layout
  sizes, 8 px snapping to edges and other widgets, free spots, add / duplicate / remove, idle rules,
  the options panel's place, events packed under 2^24.
- **Now Playing.** Sleeve, Lyric stage and Record (`ui/widgets.plm`), scaled by `u = h / default`.
  Any player, through the media service. Lyrics come through `player/lyricfetch`, now shared with the
  player (same cache).
- **The Visualiser.** Twelve modes: the six from `ui/viz.plm`, plus Scope, Horizon, Dust, Ripple,
  Skyline and Liquid, added there as library components (no state; the scene keeps the ring pool and
  the beat). The widgets ask the bar for its feed (`feed_want`, every 3 s while one shows music).
- **Calm until touched.** Hover comes from `desk.cursor` (Hyprland's socket), not from a zone, so the
  widgets keep no clicks. Controls, seek and the cover's zones exist only while shown. The wheel on a
  cover is the volume, and the cover opens the player. At rest: rest (35 %), hide, or a ♪ marker.
- **Edit mode.** Entered with `mooi widgets edit`, the ✎ Widgets button on the Nexus Quick card, or
  Settings → Widgets. Drag (snapped, with guides), resize from the right / bottom edge and the corner
  (a record keeps its shape), and an options panel beside the widget (layout or mode, at rest,
  switches, glow, duplicate, remove). + Now Playing / + Visualiser; Esc, Done or a press on the
  desktop leaves. Saved once per gesture (temporary file, then mv).
- **Settings → Widgets.** The switch, Edit on desktop, and a row per widget (layout, or mode with
  ◂ ▸; at rest; ×), plus add.
- **Retired:** Quickshell `desktop-widgets` is no longer started (`hypr/config/exec.lua`), and its
  layer and window rules are gone. Its files stay for a few days (TODO).
**Found on the way:**
- BMO's full-screen bottom surface took the clicks of anything under it on the same level. The
  widgets now restart above him whenever he comes up (`widgets_restack`).
- A zone's `show:` did not follow a spring, so the controls read the logic's facts (`hl0…7`).
- `screen` is not known while a logic file loads.
- Aurora's curves cost 12 % across the full width; it is now drawn in straight steps sampled along
  the same curves (under its blur it looks the same in the player and the bar too). The glow radius
  is capped at 12 px.
**Checked:**
- `bin/mooi check`: 306 unit tests, 0 failed; every scene compiles.
- Live: each layout, playing and resting; the lyric line following the song; progress (0.63 at
  191/302 s); real clicks on play/pause, seek and the cover; the wheel volume; marker and hide;
  live reload of widgets.json; edit mode through its events (drag, snap to a neighbour's edge, size
  clamp, mode, idle, glow, plate, layout, duplicate, remove, add) and on screen; the Settings page
  and its events; Edit on desktop.
- **GPU** (drm-engine-gfx, Sleeve + a 1920×200 visualiser, glow 0.6, synthetic music): spectrum 3.6 ·
  mirror 2.7 · ring 1.1 · aurora 5.9 · led 1.8 · orbit 1.5 · scope 5.8 · horizon 5.2 · dust 3.3 ·
  ripple 1.4 · skyline 3.4 · liquid 2.1 %. Idle: 0.00 %.
**Not checked:** a full drag and resize with the real pointer (one drag worked; you were using the
machine, so pointer automation stopped); the Settings rows pressed by hand; a fresh login (does the
widget start before BMO and then restack, and is Quickshell's widget instance gone for good).

## D138 · 2026-11-03 · Widgets 2a: a real editor, and visualisers with up to 128 bars
**Asked for:** better editor controls (resize from all sides, keyboard and nudge, a better options
panel, align and layer tools); visualiser bars that suit big, wide widgets (a setting for more
bars); better visuals for every family. Spec `docs/superpowers/specs/2026-11-03-widgets-editor-viz-design.md`,
plan `docs/superpowers/plans/2026-11-03-widgets-editor-viz.md`. Wallpaper awareness (2b) and
Clocks and Notes (2c) are next.
**Built:**
- **The feed.** The bar's one cava runs 64 bands. It writes the v1 line (32 bands, resampled) for
  everyone as before, and a `v2` line (`viz-levels-v2.txt`, 64 bands) while the widgets ask.
  `lib/vizfeed` has `encode_v2` / `decode_v2` / `resample` (groups averaged going down, eased going
  up).
- **Bars per visualiser.** The widgets logic resamples into each visualiser's own count (16–128)
  with smoothing (rise at once, fall by `smooth`) and peak dots (held 12 frames, falling 1.2 a
  second). These go into models `vzA/vzB/vzC`, one record per bar, plus 32 bands `vs*` for the
  shapes drawn as paths, and the Scope's last three frames.
- **Three lanes.** Visualisers are drawn by three scene-level lanes, from `ui/vizwide.plm`, which
  `tools/gen-vizwide.py` generates. That means **at most three visualisers** (the model refuses a
  fourth). Drawing them inside the 8-slot widget loop would have meant ~50k instructions.
- **Modes.**
  - Spectrum / Mirror / Skyline: thin round bars, lit tops, peak dots, reflection.
  - LED: a matrix with a column per bar.
  - Ring: a spoke per bar with peaks, an inner waveform and glow, a slow turn.
  - Aurora: three parallax layers and a crest.
  - Horizon: far ranges behind a stepped skyline over every bar.
  - Liquid: a skin round an inner glow.
  - Scope: three true afterimages.
  - Dust: two depths with trails.
  - Ripple: rings with a refracting band.
  - Orbit: trailing arcs.
- **The editor.**
  - Choosing: a press chooses; a right press adds or takes away; a marquee on the desktop chooses
    what it touches; Esc clears, Esc again leaves.
  - Handles: eight engraved handles (a record keeps its shape: corners only), with live resizing
    and a size readout by the pointer.
  - Carrying a chosen widget carries the whole selection.
  - Keys: arrows / Shift+arrows nudge 8 / 1 px, Delete, Ctrl+D, Ctrl+Z / Ctrl+Shift+Z (30 steps,
    cleared when the file changes elsewhere), Ctrl+A, L lock, ] [ order.
  - Toolbar: align ×6, spread ×2, same width / height, front / back, lock.
  - A SNAP switch.
  - Locked widgets show a padlock, and a note counts the ones skipped.
- **The panel.** 320 px, dragged by its header (it stays there), folds with ⌄. Live thumbnails of
  the three layouts or the twelve modes. Sliders for opacity, scale, text size, bars, glow, gap
  and smoothing. At rest, switches (now with peaks and reflection), a readout, lock / duplicate /
  remove.
- **Settings → Widgets.** Each row has opacity and bars sliders.
- **widgets.json version 2.** Adds z, locked and opacity, the visualiser's bars / gap / smooth /
  peaks / reflection, and Now Playing's text. Version 1 files load with defaults.
**Not as asked:**
- Pleamar reports no modifiers on a press, so Shift-click became a right press and holding Alt
  became the SNAP switch.
- With several widgets chosen, the panel edits the last one; the toolbar does the rest.
**Checked:**
- `bin/mooi check`: 325 unit tests, 0 failed (14 new for the editor, 4 for v2 and resampling,
  1 for the visualiser cap).
- Live, through the scene's own events and screenshots: selection, marquee, nudge, align, undo and
  redo, lock and its note, handle resize from the left, the sliders, the panel moved, and the
  Settings sliders.
- Both feeds are written while playing.
- **GPU** (drm-engine-gfx, Sleeve + a 1920×200 visualiser, synthetic 64-band music; 64 / 128 bars):
  spectrum 5.9/6.0 · mirror 6.1/6.2 · ring 3.5/3.4 · aurora 7.1/7.4 · led 2.9/3.9 · orbit 4.2/4.1 ·
  scope 6.7/6.7 · horizon 6.8/6.5 · dust 7.0/7.0 · ripple 2.8/3.0 · skyline 5.7/5.8 · liquid
  6.5/6.9 %. Measurements wander by about ±1.5.
**Not checked:** the handles, the marquee and the panel's header pressed with the real pointer
(you were at the machine); the keys pressed on a real keyboard.

## D139 · 2026-11-03 · Widgets 2b: they read the wallpaper and can sit behind its subject; resizing fixed
**Asked for:**
- widgets legible on any spot, with local colour, that know where the subject is (suggest, never
  move), and follow the picture's mood
- depth: widgets behind objects in the wallpaper, with a switch on each widget and a master switch
- fixed resizing ("funky and glitchy")

Spec `docs/superpowers/specs/2026-11-03-widgets-wallpaper-aware-design.md`, plan `…/plans/2026-11-03-widgets-wallpaper-aware.md`.

**Resizing.** Pleamar gives a drag to every zone under the press, not only the top one. Pulling a
handle therefore also moved the widget, and drew a marquee on the desktop. Now:
- each press names its owner (`wg_hold`), and every drag and release checks it
- a pulled widget is drawn from facts, so nothing is rebuilt under the pointer
- the carried offset is cleared by the logic once the new place is published, so it no longer
  flashes back

**Reading the wallpaper.** `mooi wallmap` runs `tools/wallmap.py`, started by the widgets whenever
`~/.cache/current_wallpaper_source` changes; the result is applied only if it is still the current
picture.
- **Framing:** the picture is framed as the picker frames it (fill and crop to 1920×1080, centred).
- **The cut-out:** rembg cuts the subject out, feathered 1.5 px. It uses bria-rmbg (1 GB, about
  40 s on five cores the first time a picture is seen; `nice 19`). `mooi wallmap <file> fast` uses
  isnet instead, which is faint on dark art.
- **The map:** a 32×18 grid of luma, Lab colour, detail and subject, plus the picture's mood.
- **Cache:** results are kept by the picture's content in `~/.cache/mooi/wallmap/`.

rembg is installed with `uv tool install --python 3.13 "rembg[cpu,cli]"`, because system Python is
3.14; `setup/install.sh` does the same.

**`lib/wallmap`** (pure, 7 tests): what is under a rectangle, the text tone, haze, a local accent kept
at ≥ 4.5:1, the nearest calm free spot, and mood.

**In the widgets:**
- **Adapted widgets** (ADAPT, on by default) take light or dark words, a haze as strong as the detail
  underneath, and an accent from the colours there; visualisers use it as their two colours.
- **Mood** scales glow (0.6–1.2) and pace (0.7–1.2).
- **Depth:** BEHIND puts a widget behind the subject, using `z:` order (behind 1, cut-out 2, rest 3).
  The cut-out is drawn only in the box round the widgets behind it: 8.65 % across the full screen,
  5.3 % clipped.
- **Edit mode** shades the subject's cells and marks a widget "OVER THE PICTURE'S SUBJECT"; CALM
  SPOT moves it to the nearest calm free place (undoable). Nothing moves by itself.
- **Settings → Widgets** has Depth and Wallpaper mood switches.

**Also fixed:**
- the 2a Text-size parameter was named `tx`, the same as the Sleeve's text column, so Sleeve titles
  vanished
- `lib/wallmap.parse` dropped the cut-out's path, so depth could never turn on

**Checked:**
- `bin/mooi check`: 335 tests, 0 failed.
- wallmap on the current wallpaper (cut-out and map written; a calm picture reads calm).
- Depth live in a scratch copy with synthetic music (screenshot: the bars pass behind the figure,
  the Sleeve stays in front with adapted words).
- GPU 5.3 % with depth on.
- The resizing paths through their events.

**Not checked:** resizing with the real pointer (you were at the machine), a wallpaper change end to
end (the background run and the swap), and a video wallpaper.

## D140 · 2026-11-03 · Widgets 2c: Clock, Notes and GitHub
**Asked for:** clocks (big digital, analogue, words, info), mooi's notes on the desktop, and a GitHub
repo widget. Spec `docs/superpowers/specs/2026-11-03-widgets-clock-notes-github-design.md`, plan
`…/plans/2026-11-03-widgets-clock-notes-github.md`.

**Kinds and limits.**
- `clock`: digital, analogue, words, info. Up to eight, drawn in the widgets' loop.
- `notes`: list. One, drawn as a scene-level lane.
- `github`: card, commits, pulse. Two, drawn as lanes G1 and G2, generated by
  `tools/gen-wgithub.py` → `ui/wgithub.plm`.

A scene cannot pick a model by number, so each lane is written out once from a template.

**Clock.**
- The logic ticks once a second, and only while a clock exists. The hands glide on springs.
- **Words:** `lib/clockface.words`.
- **Info strip:** weather from `nexus-weather.json`, the battery service (`present`, `percent`,
  `charging`), the next due card from the board, and the ISO week.
- **Today** is worked out with `date +%z`, as the board does: Pleamar's `os.date` has no `!*t`.

**Notes.** Edited in place: a press edits, Enter saves, Esc cancels; "+ NOTE" adds one. Each row has
pin / done / ×. A save re-reads `notes.json` first, so a change made in the side panel meanwhile is
kept.

**GitHub.** Read through `gh`:
- one GraphQL query for the card and its 8 commits with their check state
- the runs (`actions/runs`) and the weekly activity (`stats/commit_activity`; a 202 keeps the last
  answer)
- every 5 minutes, or every minute while a run is going
- cached in `gh-<owner>-<repo>.json`, shared when two widgets show the same repository
- if `gh` is missing, the widget says how to install it and sign in
- a press on the title, a commit or a run opens it with `xdg-open`

**Edit mode.** Five add chips, dimmed at their limit (3 visualisers, 1 notes, 2 GitHub, 8 widgets in
all). The panel has the layouts, 24 HOUR / SECONDS and the REPO field. Settings → Widgets lists the
new kinds and has their add buttons.

**Settings rail.** It had 23 pages, so Nexus ran under "Edit on the bar" in the 800 px window. The
rail now clips above that button and scrolls with the wheel.

**Checked:** unit tests (351), `mooi check`. Live: the GitHub card, commits and activity against
bushninjadots/mooi, the cache written, the clock words and date, the weather and battery, and 4
notes. The rail was screenshotted scrolled and unscrolled. The widgets drew 0.09 % GPU at rest,
measured while the desktop was covered.

**Not checked:** screenshots of each clock, notes and GitHub layout on the desktop (you were using
the machine, and the desktop was covered), and note editing with the real keyboard.

## D141 · 2026-11-03 · Widgets 3: seven more kinds, a look for all, groups, ambient rest, desk mode
**Asked for:** all the widget ideas and improvements; the Info clock with a weather symbol and a
battery icon; the resize handles back; better music widgets and controls, with an optional
visualiser in the Sleeve; GitHub's activity map. No spec: built straight from the list.

**The handles.** Inside the widgets' loop, a `z:` hid the whole edit group under pleamar 0.7.11, so
every outline and handle was gone; it was removed. While editing, the surface rises to `overlay`.
BMO's and the desk's bottom-layer surfaces had been taking its presses whenever they came up after
it. `level:` takes a single `while` step.

**Twelve slots** (`W.MAX`). `publish()` writes op/hl 0…11, and a new test checks that the scene
declares them. The first raise without the scene stopped the logic loading: "no fact called op8".

**The new kinds** (`ui/wextra.plm`, data from `lib/deskdata`, tested):

| Kind | Layouts | Data |
|---|---|---|
| weather | horizon, days | `nexus-weather.json`. Horizon is 24 hours of sky with a temperature trace and rain streaks; days are five columns with a range bar |
| system | scope, gauges | `/proc` and `sensors`, every 2 s while shown |
| calendar | month | `board.json`. A press opens the board filtered to that day (`kb_day`, `due:N` in `lib/board.shows`) |
| timer | ring, slab | Focus, then a 5-minute break; BMO says when each ends. The wheel adds or takes a minute; `mooi focus` |
| claude | ticker, quote | The notch's last line (`notch-claude.json`). The light shows Claude Code's processes, lit while their CPU is above 6 % |
| photo | frame, polaroid | A folder, a new picture every 5, 10 or 30 minutes. `mooi photo-prep` crops it, and rembg cuts the subject out, which is drawn over the frame |
| launch | shelf, column | The apps service, the open windows, and notifications unseen since the app was opened (they pulse) |

`pleamar --say` and service watches hand over a service's list itself, not `{ list }`.

**GitHub:**
- **ACTIVITY** layout: the owner's year of contributions (GraphQL `contributionsCollection`,
  `lib/ghparse.heat`).
- **CI warning:** BMO speaks when the newest run turns to failing.

**Lanes.** The kinds with lists are lanes generated by `tools/gen-wlanes.py` (notes, GitHub ×2,
weather, system, calendar, launcher). A group's own properties cannot read the `let`s inside it, so
each lane's nearness and opacity are lets at surface level.

**Music widgets:**
- **The Transport:** shuffle, previous, play, next, repeat (`playerctl`), the times on the progress
  bar, and the Transport under the title instead of over the cover.
- **VISUALISER IN IT:** 16 bands from the bar's feed, in the Sleeve, the Lyric stage and the Record.
- **Analogue clock:** its second hand breathes with the bass.

**Info clock:** a drawn weather symbol (`wg.WxIcon`: 8 kinds) with its word, and a battery icon with
a charging bolt (`wg.BatIcon`).

**The look of them all** (`widgets.json`: `style`, `shadows`, `ambient`):
- **Styles:** adaptive, phosphor, ink, chrome, paper.
- **Shadows:** cast away from the wallpaper's light (`DD.light`).
- **Ambient rest:** after 2 minutes idle (`on idle for 120s`), widgets fade to faint outlines. They
  come back with the pointer's distance; near enough, all of them wake.
- **Idle rule:** only the music kinds follow it now. Clocks no longer dim when the music stops.

**Groups:** GROUP and UNGROUP in the editor. Choosing one member chooses the group, and a group rests
as one.

**Desk mode** (Super+Alt+G, `mooi widgets desk`, the toolbar): the surface goes to `overlay`, the
desktop is blurred by the compositor (`glass` with `lens: false`), and the widgets glide into a
centred arrangement (`W.desk_layout`). Esc or a press on the desk leaves.

**Checked:**
- 361 unit tests and `mooi check`
- live: all twelve kinds added; screenshots of edit mode, desk mode, chrome style with shadows, the
  Info clock, the Sleeve transport, the activity map and the photo stepping out of its frame
- the timer running (`24:59 FOCUS`) and the launcher's icons

**Not checked:**
- the ambient rest after a real 2 minutes idle
- shadows in the adaptive style on the desktop
- the photo's polaroid
- the calendar's press opening the board
- BMO's CI line, which needs a failing run

## D142 · 2026-11-03 · The music island: ArchEclipse's player, from the bar
**Asked for** (in the notes): "change music player for the one i made in archeclipse that comes out
from the bar". The source is ArchEclipse's `MprisIsland.qml`
(`~/.local/state/mooi/archive-2026-10-21-archeclipse.tar.gz`).

**Ported as an island of the bar** (`open == music`, the island kit D97, both styles):
- a record turning (`spin`) with the cover as its label, inside a ring of 48 spokes made from the
  bar's 16 bands, mirrored
- the title, artist and album
- a seekable progress bar with its times
- shuffle · previous · play · next · repeat (`playerctl`)
- **Full player**, which opens `mooi player`

**Opening it:** a press on the media module (its title, its pill, or its visualiser in the compact
mode) opens it. A middle press still plays or pauses, and the wheel is still the volume.

**Feeds:**
- `bar.luau` keeps the bands coming while the island is open (`music_isl`).
- The island reads the song from facts (`mu_*`, `med_*`); the `med` service is not visible from
  the popup surface.
- The position ticks every 500 ms while the island is open.

**Left out:** ArchEclipse's 10-band EQ. The full player keeps its EasyEffects EQ.

## D143 · 2026-11-04 · BMO tells jokes; a free model when Claude cannot answer
**Asked:** what differs between BMO's chat and Claude's; make him tell jokes; without credits there
is no talking to him, so fall back to other AIs (ChatGPT, freebuff, opencode free) where possible.

**The difference:** none in the engine. Both ask the `claude` command (Claude Code, the user's
account, no tools). BMO's persona answers in character in one or two sentences, he keeps a session
of his own, and he answers in his bubble.

**Jokes.** `bmo/brain` LINES.joke holds 16 of his own. One idle line in five is a joke, and
`mooi bmo joke` (event `joke`) always tells one. No AI is involved, so they work without credits.
His Claude persona now loves jokes and puns too.

**The fallback** (`lib/claude.fallback_args` / `fallback_text`, tested):
- **When:** Claude errors or ends without an answer (no credits, offline, signed out).
- **What:** the notch's chat and BMO's own chat ask `opencode run` with its free models in turn
  (deepseek-v4.1-flash-free, big-pickle, beam-free). The same persona and the last turns are written
  into the question.
- **Locked down:** it runs in the runtime folder, without `--auto`, so nothing that needs permission
  is approved.
- **Marked:** the notch adds "ANSWERED BY … (FREE)". If no free model answers either, BMO says his
  brain is fuzzy and tells one of his own jokes.

**Not usable here (checked):**
- `codex` refuses every model on a ChatGPT sign-in (`model_not_found`).
- `freebuff` is interactive only, with no one-shot mode.
- opencode's default model is not available in this country, so a free model is named every time.

## D144 · 2026-11-04 · Wallpaper transitions: Skwd's from the notch, and mooi's desk
**Asked for:** Skwd's wallpaper transitions when the wallpaper is changed from the notch sidebar.

**The notch wears through Skwd.**
- It runs `skwd-helm apply <path>`. Skwd's daemon (`skwd-walld`) plays its transition on its own
  `skwd-paper` layer, and its post-processing hook (`wallpaper-styles/bin/skwd-sync`) hands the
  picture to the Quickshell picker and the palette, exactly as a pick in Skwd Wall does.
- The daemon runs on demand. When the notch had to start it, it stops it 6 s later; the picker
  draws the same picture underneath, so nothing changes on screen.
- If Skwd fails, the picker's IPC and its script run as before.
- Checked: the current picture applied through Skwd (`applied`, the source link kept), and the
  daemon was stopped again.

**mooi's own desk** (when `desk.on`) gets transitions too. `desk.transition` (Settings → Desk) is
random, grow, wipe, slide or fade:
- the incoming picture is drawn over the outgoing one: a radial mask, a clip, a push, or opacity
- about a second (`~950ms`)
- picked in the notch, the circle grows from the notch's edge (`from_notch`, its `nt_cy`)

**Not checked:** a notch pick end to end on screen (you were away; it would change your wallpaper),
and the desk's transitions on screen (`desk.on` is off here).

## D145 · 2026-11-04 · mooi draws every wallpaper, and picks them itself
**Asked for:** wallpaper changes were "a bit funky, sometimes slow or glitchy" (D144's Skwd daemon, cold
started per pick, then a handoff to the Quickshell picker underneath). Our own switcher in Pleamar: it
must handle pictures and live wallpapers, with a Skwd-like view and another, unique one. Spec:
docs/superpowers/specs/2026-11-04-wallpaper-switcher-design.md.

**One drawer.** mooi-desk is the wallpaper and always runs (the bar keeps it up); `desk.on` is now only
whether it travels (off: the picture still, at the screen's size). It draws stills and animated
pictures (Pleamar plays GIF / animated PNG / WebP itself). A video is mpvpaper's: the desk draws the
video's still through the transition, mpvpaper starts under it (`mooi wall live`, ~1.2 s later), and
the desk fades out once it is up (`live_on`). Leaving a video, mpvpaper stops 150 ms after the desk
has the new state, so the transition starts from the still.
- mpvpaper runs with `load-scripts=no`: mpv's MPRIS script made the wallpaper the bar's and BMO's
  "song playing" (found on screen).

**One apply.** `mooi wall apply FILE [--from-y N] [--transition KIND]` writes `wall.json` (the desk
watches it), sets `~/.cache/current_wallpaper_source` / `current_wallpaper` (the still), and starts or
stops mpvpaper. The theme watch already recolours from the still link, so there is no palette step
of its own. The notch (D130's panel: now with the live folder, video thumbnails by ffmpeg, LIVE
labels), the picker and the CLI all wear through it. Skwd's daemon, `skwd-helm`, the qs picker's IPC
and awww are out of the path (not uninstalled: TODO).

**The picker, `mooi-walls`** (Super+W, Super+Alt+L, `mooi walls`, the bar's wallpaper button, the
notch's ALL OF THEM ↗, Settings → Desk): a program of its own, running only while open.
- top row: STRIP · ORBIT, ALL · PICTURES · LIVE, `/` searches the names, the transition to wear with
  (↻, or `t`), ×. Chosen view / source / transition kept in walls-state.json.
- **strip**: slanted cards (a path clip), the middle one large, ← → Shift+← → Home End and the wheel,
  `r` a random one, a press on the middle card or Enter wears it.
- **colour orbit**: every picture a dot of its mean colour on one image (walls-orbit.png): angle = hue,
  distance = lightness, greys in a ring at the middle. A 20 × 20 grid of hover zones tells the logic
  where the pointer is; the 16 nearest swell into thumbnails, spread out like a loupe, and the middle
  shows the palette the nearest would give the shell (`matugen --dry-run -j hex`, 250 ms debounce,
  cached). The wheel turns it; a press wears the nearest.
- Space shows the picture over the whole screen (a toggle: Pleamar has no key release).
- The swollen thumbnails have no zones of their own, so moving over them still moves the swell.

**The index**, tools/wallindex.py (`mooi wall index`, run each time the picker opens; nice 19, one
pass at a time): walls-index.json + walls-orbit.png in mooi's data folder (a scene reads only its
own), thumbnails and video stills in ~/.cache/mooi/walls. Incremental by mtime; unreadable files are
remembered and not retried until they change. First pass here: 3,211 (36 videos, 5 animated) in
8.5 min; a pass with nothing new 0.4 s. JPEGs decode in draft mode; Pillow's pixel guard raised to
400 MP (a 191 MP picture was refused).

**Checked on screen** (with the user's go-ahead): the strip and the orbit (hover via `wl_cell`), a
picture worn with grow and with wipe, an mp4 worn (mpvpaper up, desk `live`, frames moving, ~10 % CPU),
and back to a picture (mpvpaper gone); the notch's panel reading wall.json. The user's motion speed
(198 %) makes the desk's ~950 ms transitions 480 ms.
**Not checked:** Super+W itself (Hyprland reads custom/mooi.lua on its next reload); a real pointer on
the orbit; a press in the notch end to end.

## D146 · 2026-11-04 · Skwd Wall and the Quickshell picker retired
**Asked for:** "retire anything and all from Skwd Wall".
- Archived (restorable, README inside) in `~/.local/state/mooi/archive/skwd-2026-11-04`: the nine
  `~/.local/bin/skwd-*` programs and `qs-wallpaperpicker`, `~/.config/skwd-wall-v2`, `wallpaper-styles`,
  `qs-wallpaperpicker`, `~/.local/share/skwd-wall-v2` and `skwd-lens` (571 MB), the `skwd-walld` user
  unit, kitty's `skwd-colors.conf` and fish's `skwd-colors.fish`, and each config file as it was before
  (`*.before`). The caches (`~/.cache/skwd-wall-v2`, 1.1 GB) deleted. Running copies stopped (a
  `skwd-wall-still` was still drawing under the desk).
- Your configs: exec.lua no longer starts the Quickshell picker; bind.lua's Super+W and qs_manager.sh's
  wallpaper target run `mooi walls`; kitty.conf and config.fish lose their skwd-colors lines; matugen's
  `qs-wallpaperpicker` template is gone and the palette JSON template reads its copy in
  `~/.config/matugen/templates/quickshell-colors.json.hbs` (checked: `mooi theme-sync` runs your
  templates without an error).
- The repo: setup/ no longer captures `qs-wallpaperpicker` or `wallpaper-styles`; the bar, Settings and
  Super+W's name say "the picker". Left for you: `sudo pacman -Rns awww` (nothing requires it).

## D147 · 2026-11-04 · The picker grows: colours, the circuit board, Wallhaven, Settings → Wallpapers
**Asked for:** Matugen swatches and a colour palette to choose pictures by in the strip; another picker
view "like a circuit board or signals"; Wallhaven in every picker; settings to customise it.
- **Colour row** (every view): 24 hue chips of 15° and the greys, LIGHT · ANY · DARK (lib/walls
  `chip_of`, `colour_ok`). The strip shows its middle picture's palette (the orbit's Matugen dry run).
- **Circuit board** (STRIP · ORBIT · CIRCUIT, Tab cycles): a 5 × 3 board; the CORE in the middle cell
  shows the chosen chip's picture on its die with the palette as pads; fourteen banks round it (the
  arc's twelve colours clockwise from the top left, GREYS and LIVE beside the core), six chips each,
  the wheel pages a bank. Copper traces run from the core along the gaps (lib/walls `board`); the
  route to the chosen chip is lit (`route_to_chip`, square at every step, tested) and a signal runs it
  once per choice (a prop following a counter: `pt - (pulse_n - 1)` goes 0 → 1). Arrows route chip to
  chip, ↑↓ three along.
- **Wallhaven**, the fourth source: TOPLIST (1D…1Y) · HOT · LATEST · RANDOM; the search (after 700 ms of
  quiet) and the colour chip go to its API (a chip → the nearest of its 29 colours, by hue then the most
  vivid); pages load as the strip nears the end or a bank is paged; thumbnails two at a time into
  ~/.cache/mooi/walls/wh; on the orbit each is placed by the most colourful colour it lists (the first is
  usually a dark neutral). Choosing one saves it as `wallhaven-<id>.<ext>` into the first folder and
  wears it. `bin/mooi` does every request (`mooi wall wallhaven search|thumb|wear|random`): URLs checked
  to be Wallhaven's own hosts, ids letters and digits, the API key read from
  `~/.config/mooi/wallhaven.key` (0600) and handed to curl as a header on stdin. Without a key the search
  is SFW whatever the setting says.
- **Settings → Wallpapers** (the Desk page, grown): the picker's default view and source, the veil, the
  strip's slant and card size, the orbit's dots and swell; the folders (a list with ×, a path field and
  + Add folder; `walls.folders`, a new `paths` kind: absolute or ~/, eight at most); the transition and
  its speed (quick 0.5 s / normal 0.95 s / slow 1.6 s — three props in the desk, `pace` picks); the
  auto-change; Wallhaven's categories, purity, sorting, range, minimum size and ratio, and whether a key
  was found.
- **Auto-change**: the desk looks once a minute; past `walls.auto_every` minutes since the last change
  (a pick by hand counts) and no window fullscreen (unless allowed), `mooi wall next <from>` wears one at
  random from all / pictures / live / the colour chosen last in the picker / Wallhaven.
- **Found and fixed:** D144 had put `desk.transition` in the middle of tools/gen-settings.py's setter
  list but not of lib/setters.luau's, so every Settings control from Day/Night onwards (56 of them) was
  read by the bar as its neighbour since last night. Appended at the end of both; gen-settings now
  refuses to run when the lists differ, and a unit test compares them. Also: the Settings logic stopped
  at load on an undeclared `key_desk` text (D141's desk-mode key); declared.
**Checked on screen:** the colour row and the strip's swatches; Wallhaven in the strip (24 of 48 pages)
and on the orbit; the circuit board with routes to a top, a side and a bottom bank; the Settings page.
**Not checked:** wearing from Wallhaven end to end (a save into your folder); a sketchy/NSFW search (no
key here); the auto-change firing (it waits its minutes); the Settings folder rows on screen.

## D148 · 2026-11-04 · Biomass: the islands grown on living circuitry
**Asked for:** an option in Settings so that every island that morphs open — from the bar, the notches,
wherever — is connected by "organic flowy circuitry, Mechanicus biomass". The user was away; these are
my choices.
- `island.biomass` (Settings → Bar, beside the island style; off by default — **turned on in your
  settings** so you see it). It layers over either style (plate or tether), not a third style: many
  islands read `isl_style > 0.5` as the tether.
- **Bar and Control Nexus islands** (ui/island.plm `IslandFrame`, so all ten of the bar's and the Nexus's
  get it): the island hangs 44 px under the bar on an umbilical — a steel core cable with a lit fibre,
  two strands braided round it, six ribs like vertebrae with nodes — webbed to the island's top; roots
  curl along the bar's foot from where it opened; veins run from the cable along the top edge to the
  corners and down the island's border, gripping it from outside with hooked tendrils; nodules of steel
  and ember where it took root; a signal runs down the cable and out along the veins as it opens.
- **The side notch**: the open panel grown out of its lit tab — a ribbed cable across (an arc's hub for
  Workspaces and Wallpapers), veins climbing and descending the card's edge, nodules, the signal.
- **Cost**: it all follows each island's own opening spring and rests when the island is open — no
  `time`, no wave, so the bar never repaints for it (the bar scene is 32k instructions; a continuous
  animation there costs every frame). Straight steps only. The bar's instruction count grew ~800.
**Checked on screen:** the system island opening and open; the notch's music panel.
**Not checked:** the other islands one by one, the Nexus's, the tether style with it, light mode.

## D149 · 2026-11-04 · Stuck wallpapers fixed; the orbit and the board in a panel; islands that morph
**Asked for:** a larger core with the pictures morphing round it; wallpapers "sometimes get stuck
showing parts of another image"; the orbit and the board not the whole screen; the orbit's pick was
"not the one I want"; islands that actually morph (not D148's cables), the Nexus "as part of the border".
- **Stuck wallpapers** (a): the desk declared both slots 16:9, and Pleamar fits a picture *inside* its
  cell before stretching it — 179 of 394 pictures sampled are another shape, so they were letterboxed
  and the outgoing slot (never hidden) showed in the bands. Now declared at their own size and drawn
  `fit: cover`; the outgoing picture is hidden once it has gone; a pick during a transition waits for
  it to end (the latest wins). Checked: three picks 0.2 s apart end on the last.
- **The orbit** (b): a colour dial on the left of a panel (point at it, or press to hold the point —
  a reticle), and on the right the picture in view large with its palette and a grid of the twelve
  nearest; hovering a thumbnail shows that one, pressing it wears that one. The swelling pile is gone.
- **The board** (b): a panel; a large CORE (620 px die) with twenty chips round it — six above, six
  below, four each side — each on its own square trace (lib/walls `panel`, `ring`, tested: in the
  panel, clear of the core and of each other, square). The chosen picture morphs from its chip into
  the die while the last one fades under it; a new page (the wheel, ↑ ↓) spreads out of the core. The
  colour banks are gone: the colour row narrows the board.
- **Morph** (c), `island.morph` in the same setter slot as D148's `island.biomass` (renamed; the cables,
  roots and veins removed): a bar island is one body with a lip on the bar's foot and a neck, blended
  (`blend`), one lit outline — it starts as a swelling of the bar and drops away on a thinning neck. The
  Control Nexus no longer slides in: the border along its edge bulges, a narrow swelling widening into
  the deck, fused with a run of the border (fillet 30), its content fading in after. The side notch's
  panel melts into its lit tab. All of it follows the opening springs and rests when open.
**Checked on screen:** the board and the orbit panels; the system island morphing; the Nexus out of the
right border. **Not checked:** every other island; the Nexus on the other edges; light mode.

## D150 · 2026-11-04 · rembg only when asked; Wallhaven's key in Settings; the morph done as iNiR does it
**Asked for:** "when changing wallpaper CPU hits 100 %" (rembg, though off in Settings); a place for the
Wallhaven API key; "morphing looks absolutely horrible — look at iNiR"; "I don't see these in Settings".
- **rembg** (a): the widgets ran `mooi wallmap` on every new wallpaper, and it always ran rembg (a 1 GB
  model, every core for ~40 s) to cut out a subject that only `widgets.depth` uses — off here. Now
  `mooi wallmap FILE nocut` (the map only) unless depth is on, and with depth on rembg gets two threads,
  `nice 19`, `ionice -c 3`. Measured after: a wallpaper change is one ~19 % blip in Pleamar, then quiet.
- **Wallhaven's key** (b): Settings → Wallpapers → Wallhaven, a hidden field with Save and Forget. Saved
  as `wallhaven.key` in mooi's data folder (`files.write` makes it 0600; not captured into setup/),
  emptied from the field at once, then checked: a sketchy/NSFW search answers 200 for a key Wallhaven
  takes and 401 for one it refuses (`/settings` answers 404 either way). bin/mooi reads it first, then
  ~/.config/mooi/wallhaven.key.
- **Where things are** (b): the island style and Morph were on the Colour page; now Settings → Bar →
  Islands, and Morph on Quick settings too.
- **The morph** (c), from reading iNiR's `IrisMorphSurface.qml` (absorbShare 0.55, pullLag 1.8, fuse
  ~30, content riding the body): the body starts as the module's pill at 55 % on the bar's edge and grows
  into the island — across on the spring, down on the spring squared — flush from the module's foot,
  corners from the pill's to the island's, fused (22) with a run of the bar's edge as wide as the body
  plus a fillet each side, so it flares out of the edge; the content rides the body's foot and fades in
  over the first third. D149's neck, lip and 22 px drop are gone. The Nexus: along its edge on the spring,
  out of it on the spring squared, corners growing, content riding its leading edge.
  Checked: a scratch scene rendering the island at rv 0.15 / 0.36 / 0.57 / 0.78 (the real one opens too
  fast to catch at 198 % motion speed).

## D151 · 2026-11-04 · Every morph removed
**Asked for:** "remove any morphing from the notches … as well as all the morphing anywhere, it's very
very bad, we need to redo this much better". ui/island.plm, mooi-nexus, mooi-notch (and the facts set in
mooi, mooi-notch and mooi-nexus logic) are back to D147d (1929590): islands, the Nexus deck and the
notch's panels open as they did before D148. `island.morph` is gone from the schema, from both setter
lists (it was the last entry: no code moved), from Settings → Bar and Quick, and from settings.json.
A better morph is to be designed from scratch (see the conversation of 2026-11-04 for what was learnt).

## D152 · 2026-11-04 · The chassis (B): islands grow out of the frame as part of its body
**Asked for:** "B" — the full iNiR chassis: the band, the bar and every island one shape.
**Probe first** (throwaway, scratchpad): a chassis program and a content program, a 2 s spring.
(a) `level: bottom, top while …` and `level: top, overlay while …` stack right, even with the chassis
started after the content; (b) the content riding the body from another program does not visibly
drift; (c) ~10 % GPU while it grows, 0 at rest — **with a spring**: a long duration tween (`~2000ms`)
kept the probe painting every frame (4.6 % GPU) after it had arrived; springs settle and rest.
**Built, the bar's islands** (window, system, stats, calendar, music, weather, sound, display, power):
- mooi-frame draws the island: `frame_p` (tools/gen-frame.py `place_surface`) is the top strip's tiles
  the island crosses (`pl_l`…`pl_e`) with the island's box melted into each tile's body (`blend: 30`), on
  the top layer only while it is out; `frame_t` leaves those tiles out meanwhile — they meet exactly.
  The body grows out of the bar's piece: from the module's pill (55 %, 14 px above the island's top,
  inside the piece) — across on the spring, down on the spring squared, corners 6 → 14.
- ui/island.plm `IslandFrame(…, ox, oy)`: with `ch_on` (frame on and `frame.islands`, Settings → Frame,
  on by default) an island under a module draws no body, only its content, clipped to the same shape
  from the same numbers, riding its foot and fading in over the first third. As it starts to open it
  emits its box and its module's middle (`pl_xy`, `pl_wh`, `pl_t`, packed under 2^24); shell/mooi.luau
  sends them to the frame in one `--say` with a count of openings (`pl_n`: the frame's spring follows
  the count, so each opening runs from 0), and `pl_on false` when `open` changes; messages queued, one
  after another. The bar's surface and its islands' go to the overlay layer while one is out, so they
  stay over the frame's top-layer body.
- New springs `m.isl` (230, 26: ~420 ms, a slight swell) and `m.isl_out` (900, 60), used by both.
- Shelf islands, the command membrane and the frame off: plates as before.
**Checked on screen:** the system island (from the network module) growing out of its piece — frames
caught mid-growth — and the calendar out of the centre piece; switching calendar → system; the frame's
GPU: ~3.4 % while it grows, 0 open and still, 0 after. **Next:** the Control Nexus and the side notch.
- **D152b, the Control Nexus:** the frame's `dk` place — a sliver on the band's inner edge, a third of the
  deck's length, spreads along the edge on the spring and pours out of it on the spring squared; frame_p
  now carries every strip's tiles (top, foot, sides; the screen is cut so each pixel is drawn once), each
  with every place's box. mooi-nexus draws only its content (`DeckFrame` plate hidden), riding the body's
  leading edge, with its own copy of the count and springs (`nm_*`); its surface starts under the bar's
  reserve, so the deck goes to the frame offset by it. The bar stays over it (`nxo`). Checked: the deck
  out of the right border, frames caught mid-growth.
- **D152c, the side notch:** a card panel (Claude, music, weather, GitHub) opened from the nub is the
  frame's `nt` place, its body running from the band itself to the card's far side — the border swelling
  out, the tabs on it — and the notch draws only the content (`Card(…, bare)`), riding the body's far edge.
  The arcs (workspaces, wallpapers) and panels opened beside the Nexus are as before. Checked: Claude and
  music out of the left border, switching between them, closing.

## D153 · 2026-11-04 · The morph without the frame, smoother, and off the notch
**Asked for:** no morph on the notch ("they look horrible"); better, smoother animations; the morph not
only with the frame but for every bar; the setting right.
- **The notch** is back to its own panels (mooi-notch, ui/deck.plm as at D152b); the frame's `nt` place
  is gone (two places: `pl`, `dk`).
- **Without the frame**: `island.morph` (Settings → Bar → Islands, and Quick; `frame.islands` renamed in
  its slot, the last of the setter lists) is its own switch. mooi-frame runs for it alone: `band_on`
  (frame.on) shows the band — every band path in a tile is `show: band_on` — and without it the bar's
  pieces float where the bar's own plates would (`st_offset`), so an island grows out of its piece in the
  islands, full and notch layouts alike. The bar hides its plates whenever the frame paints them
  (`pf = frame_on or ch_on`). Checked on screen in the notch layout, frame on and off.
- **Smoother**: `frame_p` declared no rate, so it kept frame_t's 30: the body grew at half the bar's
  rate. Now 60. The handover was measured at 52–69 ms, and the content had started at once, ahead of its
  body: islands now say where they are the moment they are asked for (`want`), their own reveal starts
  `after 60ms`, and their close `after 90ms`, while the frame's "let it go" waits 40 ms and is skipped
  if another island was handed over meanwhile (the two arrive in one instant now); an island another
  takes over from goes at once (`busy`). The Nexus tells the frame first and starts its own clock 55 ms
  later (`nm_on`). The frame rests at 0 when nothing moves.

## D154 · 2026-11-04 · The morph's bugs, found frame by frame; the Nexus's opening; performance
**Asked for:** animations still buggy; the Nexus's opening; the frame's borders; performance, measured.
Recorded at 60 fps (wf-recorder) and read a frame at a time — screenshots had hidden all of this:
- **A body with nothing in it**: the bar's "it closed" and a new island's geometry arrive in the same
  instant, and once crossed the frame kept a body the bar had closed. `pl_sync` now decides from `open`
  as it is (an island and its geometry, once per opening, or nothing), not from the order of messages;
  a closing is sent at once. Stress-checked: toggles, a switch, double and fast presses — all consistent.
- **A stall at the start**: `frame_p` moved from the bottom layer to the top as an island opened, and
  the compositor held it three frames, then it jumped. It is on the top layer for good (it draws nothing
  idle); the bar, its islands and the Nexus are on the overlay layer for good (the bar back on top while
  a window is fullscreen), so nothing changes layer during an animation.
- **A stale body after a close**: with nothing drawn, `frame_p` kept its last frame. A 1 px, 1 % box
  keeps it painting.
- **Content outside its body**: the content now starts 30 ms after the island is asked for (it was 60,
  from before the stall was gone), leaves with the quicker `m.exit` and is hidden the moment the island
  is asked to close; the body shrinks away empty. Recorded: open and close, nothing floats.
- **See-through bodies**: the frame's material is the band's (31 % here): windows showed through an
  island or the deck. Each place has a solid underlay of the same colour under the band's body
  (`1 − 0.06 / (1 − fop)`, ~94 % together); the band keeps its own.
- **The Nexus**: its cards came online from 240 to 790 ms (not paced), so the deck stood empty most of a
  second; now 100–350 ms, 25 ms apart; the traces between cards light with the cards, not before them.
- **Performance** (per program, CPU of a core / GPU, measured over 6 s): at rest 5.3 % / 1.2 % for all of
  mooi. With music: the theme watch woke 30 times a second on the v2 visualiser feed (2.5 % → 0.3 %, now
  excluded); the widgets wrote ~120 visualiser facts a tick whether they had changed or not (only when
  they move now: 22.7 % → 19.5 %); mooi in all 36 % → 31 %. The widgets' remaining cost is their scene
  (39k instructions, every frame, for one 127-bar visualiser): the next step is the visualiser as a small
  program of its own. Borders: looked at closely, left as they are (the swell style's edge is by design).

## D155 · 2026-11-04 · The visualisers as a program of their own
**Asked for:** "do next for visualiser" (D154's note: the widgets' scene redrew all 39k instructions 30
times a second for one 127-bar visualiser).
- **mooi-viz** (shell/mooi-viz.plm + .luau, 17k instructions, no zones, the widgets' bottom layer): the
  three visualiser lanes (ui/vizwide.plm), its own palette, and the music — it takes the bar's feed itself
  (the bars, the bands, the scope's afterimages, the beat's rings; facts written only when they move).
  The bar keeps it running beside the widgets (`viz_sync`: one copy, strays cleared, restarted if it ends;
  in a `do` block — mooi.luau's main chunk is at Lua's 200 locals).
- **The widgets** still decide where each visualiser is and how it looks: their logic sends the lane
  facts (and each slot's opacity, `smooth`, the mood) whenever any of it changes, looked at every 400 ms;
  `hold` while they are edited or gathered (desk mode), when the widgets draw them themselves so a drag
  stays live. They ask every 3 s whether it is up (`viz_ext`); without it they draw as before.
- **Spins gated:** the record's turntable turns only with a Now Playing in the Record layout (`np_rec`),
  the drifting modes only while the widgets draw visualisers.
- Found: mooi-viz's logic stopped on its first line (`st_glow` undeclared) — a test copy run in the
  foreground showed it; declared.
**Measured with music** (8 s, CPU of a core): the widgets 22.7 % (D154 start) → 3.9 %; mooi-viz 11 %
(1.4 ms of rules a frame against the widgets' 2.9); the two together 14.9 % against 22.7. At rest both
~1 %. The rest of mooi-viz's cost is the visualiser chosen (127 bars, scope, reflection).
**Checked:** edit mode hands the visualiser back to the widgets and takes it again after.

## D156 · 2026-11-04 · The notch's Games panel: everything installed, Steam's and the desktop's
**Asked for:** "create a notch bottom corner that can find and list all games installed on my system
including steam so it shows them keep it in theme and looks like the other notches".
- **A seventh tab**, at the bottom of the notch's track: GAMES, its card beside the fan as the others
  (460 × 560), its glyph a gamepad (`icons/games.svg`), its panel drawn in the same head / chips / rows
  language as the GitHub one.
- **Where the games come from** (`shell/lib/games.luau`, pure, unit-tested): Steam's `libraryfolders.vdf`
  names its libraries; every `appmanifest_*.acf` in their `steamapps` is a game — Proton, the Linux
  runtimes, SteamVR and the redistributables are manifests too and are left out; and one `grep` over the
  menus (`/usr`, `/usr/local`, `~/.local/share`, the flatpak exports) takes the `.desktop` entries filed
  under `Game`, leaving out what is hidden, a terminal program, or a launcher that only starts games
  (Steam, Lutris, Heroic, Bottles, ProtonUp, PortProton, protontricks, Faugus). Two `grep`s and two
  `find`s, once a minute when the panel opens — **no network for the list itself** (a picture is the one
  thing fetched, below, and only for a game the machine has none of).
- **The row**: Steam's own picture, already on disk — `appcache/librarycache/<appid>/header.jpg` or
  `library_header.jpg`, and where a game has neither, its portrait `library_600x900.jpg` cropped to fill
  the row — then the name, `STEAM · 440` or `APP · org.example.Game`, PLAY while pointed at. The wheel turns the list
  (twelve rows, the window slides); ALL · STEAM · APPS narrows it; the head carries the counts, the foot
  where the window is.
- **A press starts one** — Steam through `steam://rungameid/<appid>` (`xdg-open`), the rest through
  `gtk-launch <id>` — and folds the notch away, as the music panel's player does.
- `mooi notch games` opens it from the command line; `lib/notch.PANELS[6]` gives the Nexus-side layout
  its size. The Nexus's own notches (six hexagons out of the deck) are unchanged, as the deck's ends
  have no room for a seventh.
- **The folders on the disk** (asked for after the first cut listed nothing): Steam is not the only
  place a game lives. `~/games`, `~/Games` and `~/GOG Games` are walked two levels down for a launcher —
  a `.sh`, an AppImage, an `.x86_64`, a `.run`, or the game's own `.exe` — and PortProton's
  `prefixes/<game>/drive_c/…` deeper still; a folder holding only an installer (`setup*.exe`), crash
  handlers, redistributables or a prefix's `drive_c` is left out. Rows read `LOCAL · NATIVE`,
  `LOCAL · WINE` or `LOCAL · PORTPROTON`, and ALL · STEAM · APPS · LOCAL narrows the list.
- **`mooi game <folder> [program] [--proton]`** starts one: its own launcher or AppImage where the
  folder has one, else `wine`, else PortProton (always PortProton inside its own prefixes), from the
  game's own folder. The notch only runs `mooi`, which its allowlist already had.
- **Why the first cut listed nothing**: the notch's `launch()` helper kept a command's output only
  when it exited 0, and discovery exits 2 (`grep` over a menu folder this machine has not) or 1 (`find`
  over a Steam path it has not). Every answer was read as empty, so the panel said nothing was
  installed. Discovery now reads through `probe()`, which keeps what a command printed whatever it
  exited with; `launch()` is unchanged for the tools where a failure is a failure.
- **The same arc as the wallpapers and the workspaces** (asked for after the first list): not a card
  of rows but 280 × 158 cards on the notch's own arc — the wheel turns it, the one in the middle is
  large and ringed, its name and source under it, PLAY on the card. The logic walks the filtered list
  with a middle index and slides a twelve-card window (`gm_base`, `gm_c`, the `gmc` spring) the way
  the wallpapers' `wp_base`/`wp_c` do, so the arc never jumps as the window moves.
- **A preview on every card where one exists, no network**: Steam's header or its cropped poster; a
  folder's own `icon.png`, `logo.png`, `game.png` or `steam_icon.png`, found beside its program (the
  one `find` over the roots carries them); and the menus' icons — one `grep` takes each entry's
  `Icon=`, one `find` over the icon themes' PNGs (flatpak's exports included) resolves them by name,
  the biggest size winning, an absolute `Icon=` used as it is. PNG only: the scene reads pictures,
  not drawings. A card with no art keeps its well, its name and PLAY.
- **A picture from online where the machine has none** (asked for: "download proper icons online
  so they all look good"): Steam's store answers a name with its appid — `storesearch`, **keyless** —
  and its CDN gives the 616 × 353 capsule, which is the card's own shape. Both answers are kept in
  `~/.cache/mooi/games`: `<key>.json` for what the search said and `<key>.jpg` for the picture, the key
  being the title in dashes plus a short hash of the title exactly, so two games that read alike keep
  apart. A game is therefore asked once: a bare row is dressed from that cache with **nothing
  fetched**, and only what is still bare goes online — at most 24 in a pass, once a quarter hour, and
  only while the panel is open. The store's longer title is taken where ours stops at a colon or a
  dash ("Hotline Miami 2" → "Hotline Miami 2: Wrong Number"); a title that merely starts the same
  ("Hydra" is not "Hydra Heli 2") is refused, so nobody gets another game's art. Steam's own wide
  header, already on disk, keeps its place over a fetched one; a portrait poster (the two Steam games
  here had only `library_600x900.jpg`, cropped into a card it is not the shape of) and a menu's 16 px
  icon give way to the capsule, which is what made Cataclysm — and Starbound — read at a glance. Where the store has never heard of it — Starsector, Jackify,
  OpenStarbound — the card keeps its well and its name, and the answer is cached so it is not asked
  again.
**Checked:** `tests/unit/run.lua` (the library/manifest/menu/folder parsing, the merge, the filters,
the icon lookups, and the store's names, keys and cache), `bin/mooi check` (the scene compiles), and
the running notch's own list and cards read back (`pleamar --say mooi-notch "get gm_t"`, `get
gm.N.pic`). Not checked: starting a game from the panel.

## D157 · 2026-11-04 · The workspaces' transition, niri's columns, and the Nexus's notches back
**Asked for:** "improve workspace scrolling also add niri type scrolling if possible and another new kind
if we can" — then: "not the workspace switcher … the actual transition of workspace window to next";
and "on the nexus after adding the morphing the notches are not there anymore".
- **Settings → Windows → Workspaces** (desktop.ws_*, applied live by `look()` like the rest of the
  windows' look, kept across restarts by custom/mooi.lua): *Transition* — Slide, **Column** (niri's: the
  workspaces stacked top to bottom, `slidevert`), Glide (`slidefade 20%`), Fade, and **Tide**, mooi's own:
  the two leaves apart, the next workspace rising in faded (`slidefadevert 30%`) while this one dissolves
  where it stands (`fade`). *Feel* — Ease (out-expo), **Spring** (niri's: critically damped, stiffness
  1000 against 2·√1000 ≈ 63), Bounce (a little past, then back). *Duration* in tenths (a spring sets its
  own). *Swipe* — Flick (a short quick swipe goes over, a long one carries past the next) or Steady.
  A kept feel under a chosen style moves by the ease: Hyprland's `default` is near instant in this config.
- **Probed on the live Hyprland 0.57 first** (values put back after): the workspaces' leaves take slide,
  slidevert, slidefade N%, slidefadevert N%, fade and forced sides (`slide top`) — `popin` and the gnome
  styles are refused there (windows' alone), so the new kind is built from the in/out leaves and a spring.
- **Settings → Windows → Tiling** (the scrolling layout): Column widths (niri's ⅓ ½ ⅔ 1, halves,
  quarters: `explicit_column_widths`), Follow focus, Wrap focus, and **Column keys** — niri's, as layout
  messages: Super+] / Super+[ step the widths, Super+= / Super+− ±10 %, Super+Alt+→ / ← move the column,
  Super+C fits it. Each key is let go before it is bound, so applying the look again never binds it twice;
  every new setting is claimed, so going back to Keep reloads Hyprland and its own value returns.
- **The Nexus's notches**: since D152b the deck's content is clipped to the chassis body, and the notch
  tabs stand outside the deck — clipped away. The clip now opens past the body by their reach (56 px) as
  the body settles (`smooth(0.86, 1)` of the reveal), so they rise out of the deck's edge once it is out.
- Not done: the swipe's direction stays the desktop's own (config/gesture.lua: three fingers sideways;
  up is the special workspace), so Column's stacked workspaces are still swiped sideways.
