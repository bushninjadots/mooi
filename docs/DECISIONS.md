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
