# The Mechanism

The bar: mooi's own machine along the **top edge of the screen**. It is the one surface that is
always there — it says where you are, lets you move between workspaces, opens the four islands,
shows the state of the machine and drives the player — and everything else in mooi opens *beside*
or *under* it.

This file is the bar's design and its implementation constraints. Scene code cites it as
**§1** (what the geometry may and may not say) and **§3** (what a preview may and may not
commit to).

The bar is built in `shell/mooi.plm` (`// ══ The Mechanism · the bar ══`, the first surface and
everything down to its rules), its reusable shapes are in `shell/ui/mechanism.plm`
(`Mark`, `Prism`, `Module`, `Door`, `Transport`, `Cap`, `Plate`, `Rule`), and its geometry and
colour come from `shell/theme/tokens.plm`. There are no body parts: the machine is drawn from
those pieces and nothing else (`shell/ui/edge.plm` and `edge_strands.plm` are gone). What is
deliberately **not** here is at the end of this file.

It is a port of the renewed design (`pleamar helix bar/helix-v2-mooi/`, **v6, the horizontal
exposed helix**, checked with `pleamar --check` before it was ported): the same idea — triangular
prisms turning on one shared axis, graphite surfaces, mint for what is and amber for the
machine's own accents, nothing painted behind any of it — turned to mooi's own axis and to
mooi's own services. The design's scene is a standalone sketch with invented readouts (`D3`,
`HN 450`) and a static row; mooi keeps its sliding chain, its wheel, its islands and its theme,
and every value it shows comes from a service.

## §1 · What the geometry may say

The bar is drawn on a **horizontal strip**: a `full × 220` canvas, `anchor: top`, `reserve: 56`,
`level: top` — of which the machine uses the first **47 px** (its axis at `g.axis_y` 24, its
prisms 32 across, its zones `g.zone_h` 46 tall). It is one machine along that axis, with nothing
behind it:

- **the chain**: the workspace positions as triangular prisms on the bar's axis, sliding along it
  so that the block the compositor is on always comes to the focus slot. Every vertex of a block
  is tied to the two nearest vertices of its neighbour by rods, and one wider link runs through
  each gap: the blocks and their rods *are* the bar (v5). A block's faces turn **about the bar's
  own axis** (the rod runs along the bar), so a face turning away narrows in *height* and slides
  up or down the block — the twist is read as a screw turning through the focus slot.
- **the module row**: twelve slots of prisms beside the chain, on the same axis — the media
  reading and its transport, the clock, the System door, the four readings, and the bar's three
  ways out of itself. Each is joined to the next by a short link and a collar. A reading is a
  `Module` (a prism whose press turns it over to its next face); a door is the same shape held
  still; the transport is the same plate, wider, with three controls on it.
- **the shaft**: one **steel shaft** runs under the whole of the chain — from the mark's own frame
  to the rule where the controls begin — and the chain's window is a *sleeve* over it. The blocks
  are threaded on the shaft, a joint disc sits on it in every gap, and where the chain has run out
  (workspace 1 has nothing to its left, workspace 10 nothing to its right) what is seen is the
  shaft itself. That is the end of the "gap at the ends" problem: the window no longer shows a
  dark hole beside the first or the last block, it shows the steel they turn on (v7). The shaft is
  shaded as a cylinder — five bands, the top third catching the light, one specular hairline — and
  closed by a collar at each end, so the joins are fittings and not butt joints.
- **the end cap** at the right, which finishes the machine and carries the error dot.

Between them, what is painted is the mark's own frame, the shaft, the blocks, the joint discs, one
hairline where the controls begin, and that cap. Everything else on the strip is transparent: the
desktop shows through it, and a click there belongs to the window underneath.
Measured on the running desktop (screenshot of the strip, 2026-10-16, v8): the machine is 590 px
wide and its body 42 px tall edge to edge (a 38 px slab between two hairlines), the chain's window
is 108 px of a 1920 px screen, a block's band is 32 px of graphite with the body's black above and
below it, the shaft's bands read 117102101 at the top of its light through 726059 and 473636 to
292222 at the foot (the palette of the moment — the live theme is the wallpaper's, rose here), the
active block's label (in the chain's mark colour, two figures) is centred on its face with its
edges lit (208151148 against its neighbours' plain 115100100), and the wallpaper shows only
outside the machine, around the strip's pieces.

The mark, the necks, the shaft, the chain, the row and the cap all line up on `g.axis_y`, so a
change in any one of them is read against the same line.

The rule the whole bar is built on:

> **Geometry carries state. Colour only confirms it.**

A workspace's block is turned the way its place on the chain says, and the block the compositor is
on is the one at the focus slot; a module shows its glyph, its number or its name by which face is
turned to you; a level is a bar's length; a block is cut off at the chain's window rather than
faded; the cursor ring is where the pointer is. You can read the bar with the colour turned off. Colour then says
two things and only two:

| Token | Means |
| --- | --- |
| `accent.primary` | **what is** — the active workspace, a level that is set, a radio that is on, a player that is running |
| `focus.ring` | **what is pointed at** — the key or the position under the pointer |
| `fg.*` / `border.subtle` | the quiet majority: hairlines, labels, the unfilled part of a level |
| `status.error` | something is wrong and you can act on it (a refused theme, a low battery, a mute, no connection) |

Two consequences the code depends on, both verified on the running desktop:

- **A conditional colour cannot be a `let`.** `let` takes an expression or a plain colour;
  `if(cond, a, b)` returns one colour, so `let tone = if(lit, accent.primary, fg.muted)` is a
  load error. The bar writes the arithmetic instead — `mix(fg.muted, accent.primary, p)` with
  `p` a 0–1 number — which is also what makes the level meters continuous rather than stepped.
  `clamp()` keeps `p` in range. (A `let` **is** allowed inside a `group`, which is where the
  per-widget ones live.)
- **Nothing is placed from a value that has not arrived yet.** The machine is laid out from its
  own fixed spans and the screen's width — never from `spaces.count` or any other report — so the
  bar does not move when the first report lands. (`x0 = max(8, (screen.width − machine_w) / 2)`,
  and every other x is derived from `x0`.)

Three more of Pleamar's that the bar is careful about:

- `pick(i, a, b, …)` is **0-based** — index 0 is the first. It also takes a `bool` as the
  index, so `pick(cond, "when false", "when true")` is the idiom for a label. `if(cond, a, b)`
  is the opposite order and is for numbers and colours. Getting these two the wrong way round
  is silent: the label reads backwards and nothing complains.
- `path` is **one stroke per `path`** (`move` once, then `line`/`curve`, optionally `close`);
  several strokes are several `path`s. This is how the Bluetooth rune and the transport's
  triangles are drawn.
- **A zone whose `active:` is false when the scene loads is not created at all** — `describe`
  does not list it and nothing reaches it. That is how the transport takes no press while there
  is no player (`active: usable` with `media_on` false): measured both ways with
  `pleamar --say mooi "fact media_on true"` — the three zones appear at 940, 973 and 1005 and
  vanish again.

Geometry tokens (`shell/theme/tokens.plm`): `g.spine` 48 (the strip the bar's body spans — the
surface reserves 56, and the mark's menu hangs at `g.spine + 8`) · `g.axis_y` 24 (the axis
everything lines up on) · `g.zone_h` 46 (how tall a zone on the bar is) ·
`g.tick` 36 (pitch of one workspace position) ·
`g.frame` 1.5 (the chain's window: pitches either side of the focus slot — the clip and the press
both stop there; one block's run each way, and the half pitch that keeps the outermost one whole) ·
`g.blk_w` 32 (one block along the bar) · `g.prism_r` 18 (its circumradius, 36 across the
silhouette), `g.prism_faceh` 27.7 (the face dead-on: an equilateral face 32 wide is 32·√3/2 tall —
the scene cannot take a square root, so the number is spelled out; that near-equilateral face is
what makes a block read as a triangular plate) and
`g.prism_chamfer` 2.5 · `g.mod_w` 30, `g.mod_h` 36 and `g.mod_pitch` 34 (the row) · `g.cap_w` 16 ·
`g.body_h` 38 (the matt black slab) · `g.shaft_h` 14 (the steel the blocks turn on) · `g.tex` 9
(the grain's pitch) · `g.plate` 190.

The layout along the screen is the scene's own lets, all of them arithmetic on those tokens:
`chain_span = 2·frame·tick`, then the machine is
`32 + neck_w(12) + chain_span + 12 + 11·mod_pitch + mod_w + 6 + cap_w` = **590 px** wide
(mark · neck · chain window · gap · row · gap · cap), centred with
`x0 = max(8, (screen.width − machine_w)/2)` — 665 on a 1920 px screen, so the margins are equal —
the chain's window at `frame_x = x0 + 44` (709 here), the focus slot at `chain_x = x0 + 98` (763),
the first module at `row_x0 = x0 + 179` (844), the cap at `cap_x = x0 + 582` (1247), and the shaft from
`x0 + 30` to `rule_x` (695 to 823 here). Nothing in that chain of sums is a literal that a token
cannot move: widen a block (`g.blk_w`) or the chain's window (`g.frame`) and the machine's centre
follows. On a screen narrower than about 606 px the machine runs past the right edge (that is what
the `max(8, …)` says): the bar does not shrink itself yet.

The chain's own turn is carried by one scene constant: `helix_turn` **132** — the degrees every
block turns per workspace step, of which 120° is one full face-turn of the three-faced prism and
the remaining −12° is the gentle twist each neighbour shows in front of the next (§2). One spring
(`m.spin`, §5) turns and slides the chain together.

The surface is reserved for the strip; what hangs below it — the mark's menu — is painted over the
windows, and because pleamar commits the input region from what is actually
painted, nothing there takes a click. Measured on the running desktop: `hyprctl monitors` reads
`reserved [0, 96, 0, 0]` while the bar is up (56 of it is mooi's; the rest is ArchEclipse's, which
mooi runs beside), and the real windows sit below it plus their 14 px margin — where they used to
sit at x 90 when the bar was a rail down the left edge. On quit the reserve goes back to the
monitor's own top inset.

## §2 · The four regions

Left to right, one axis:

**A · identity.** The mark (`Mark`, 32×32) at the left end — a frame, a miniature spine and its
detents, one of them accent — opening the bar's own menu: colours (fixed or from the wallpaper),
the chain's labels, whether the wheel over the chain steps, and the path of the settings file. The
menu hangs under the mark, below the strip. The mark's frame is the machine's beginning: the
**neck** starts at it.

**B · navigation.** The machine's middle: the **neck**, the chain's **window** and the **chain** of
workspace blocks. One `Prism` per configured workspace position, 1–`ws_max`, on the bar's axis. A
block is a triangular prism seen from the front — three faces 120° apart, of which only those
turning toward you are drawn, each narrowing as it turns away — so the row of them reads as one
machined link rather than a list of marks. The blocks are threaded on the chain's own **shaft**,
which runs under the whole region: a block is a *solid* piece of graphite (v6b — nothing is faded,
so a position is either in view or cut off), every vertex of it is tied to the two nearest vertices
of its neighbour by rods, and a **joint disc** sits on the shaft in each gap. (v5 removed the arms
that used to sling each block to two side rails; v6b removed the fade and the rotary dial; v7 took
the barrel out of the window and made it a shaft the window is a sleeve over, so the ends of the
list — where there is no block — show steel and not a hole.)

**The chain slides.** `pos` — the chain's place in workspace units — is a spring that follows
`active_row`, so the block the compositor is on always comes to the focus slot at
`chain_x` (the centre of the chain's own zone). There is no fixed mark on the slot any more (v5
drops the accent bar that used to stand there): the block that arrives is turned face-on and lit,
and that is what says where you are. What you see is a **window** onto the chain: everything the
chain draws is clipped to its own zone (`g.frame` 1.5 pitches either side of the slot — one block's
run each way and the half pitch that keeps the outermost one whole, so three positions out of ten at
most, and two when the compositor is on the first or the last), a block entering or leaving view is
cut off by the window's edge, and a block outside it takes no press either — never a list that ran
out, and never a ghost: measured on the desktop, a block is 32 px of graphite across its whole
width, with the body's black above and below it. Workspace 1 has nothing to its left, and the shaft
is what runs there, so the machine is unbroken at the end of the list — and the same at its right
end, on the last configured position. A block's press is the block's own
width and not the pitch: the four pixels between two blocks belong to the chain, and the outermost
block of the window stays whole — a zone cut by the window takes no press, which is what `tests/scene.sh`
proves against the window the scene itself declares.

Block *i*, `d = i − pos` positions from the slot in front of you, is turned by
`(60 − helix_turn·d)°`. The angle is written in *relative* terms — the block's distance from the
slot, not its own index — which is what makes the chain one thread moving through the slot instead
of ten marks. `60` is the prism's face-on angle (a face is square to you at `al ≡ 60 (mod 120)`,
the three faces being 120° apart), so the block on the slot sits dead-on at rest — one face, its
label upright and unsqueezed, the other two away — and every other block is turned by its distance:
`helix_turn` = 132° each position out, of which 120° is one more full face-turn and −12° a whisper
of twist that builds along the chain (a full face over ten blocks). Because the step and the twist
always land in whole 120°s, the block that arrives is face-on without a parity term — the
`(i mod 2)` switch v7 needed is gone — and because slide and turn are the same spring (§5), they
cannot fall out of phase: one mechanism moving through the slot, never a slide whose roll lags
behind it (v7's geared pair could move a neighbour's angle backward before the roll caught up).
`pos` is a `follow` of `active_row` alone, so the chain turns only when the compositor reports a
change and a preview never turns it (§3); the block that arrives has its mark's colour
(`bar.tones.chain`, which is `accent.primary` until it is set) on its edges and its label, twice
drawn — a soft wide stroke under a sharp one — and a bolted face of its neighbours' own tone around
it.

A workspace's label is what `lib/spaces` makes of it: a named workspace says its name, shortened
to three letters; a workspace with no name of its own says its number, **zero-padded to two
figures** (`01` … `10`), the way the rest of the instrument reads. A label is squeezed with its own
face, so a block turned away carries a foreshortened label and the block that arrives carries an
upright one.

The mark's menu is the bar's only instrument of its own, and it opens under the mark.

**C · the module row** and **D · the end cap** are one line of prisms beside the chain, on the
same axis (the tokens place them: `g.mod_pitch`, `g.mod_w`, `g.mod_h`). Slot by slot, from the
chain outwards:

| Slot | Piece | Kind | Press |
| --- | --- | --- | --- |
| 0 | media (state · title · artist) | `Module` | turns over |
| 1–2 | the transport: back · play or pause · on | `Transport` | emits `media_cmd(-1 / 0 / +1)` |
| 3 | the clock (time · date · day) | `Module` | turns over |
| 4 | the battery, and the System surface | `Door` | opens the System island |
| 5 | volume (speaker · level · bar) | `Module` | turns over; the wheel over it sets the level |
| 6 | brightness (sun · level · bar) | `Module` | turns over |
| 7 | Bluetooth (rune · on/off · label) | `Module` | turns over |
| 8 | network (meter · percentage · name) | `Module` | turns over |
| 9 | the focused window (icon or letter) | `Door` | opens the window island |
| 10 | the Atlas | `Door` | opens the Workspace Atlas |
| 11 | search | `Door` | opens the command membrane |

A module's three faces are written by the scene — what it shows on each is §6 — and a press turns
it to the next one, so one prism holds a glyph, a number and a name in the place of three widgets.
A door is the same shape held still, its press opening a surface instead. Which slot a piece takes
is computed from what the machine has (§6), so a module that cannot exist closes its gap and
everything after it moves along the bar. A hairline before slot 0 says where the controls begin;
the **end cap** (`Cap`) says where they end — a faceted block in the same graphite, one amber
chevron, and the error dot (a refused theme, a broken settings file) on it.

## §3 · The compositor is the only authority

Nothing on the bar can point at a workspace that is not the one you are on. There is no dial and
no preview any more (v6b): the wheel that used to stand at the axis's head, its needle, its
`SPACE` readout and the `nav_open` selector behind them are gone, and with them the whole idea of
showing a position the compositor has not been asked for.

> **A press on a block, or a notch of the wheel over the chain, is a question asked of
> `workspaces.focus`. The chain moves when the *service* says the workspace changed — never when
> the press happened.**

That is why `pos` is a `follow` of `active_row` alone: the chain's own state is the
compositor's answer and nothing else. It is also what makes the bar honest — the block at the
focus slot is the workspace you are really on, always, and there is no state in which the bar
claims to be somewhere it is not.

Two rules follow, and they are what the bar is built to:

- **Never delay the real operation for an animation.** The focus call is made at once; the
  animation is what happens while it lands. Nothing in the bar waits for a spring.
- **Interruption is free.** Every transition is a spring that can be re-targeted mid-flight;
  there is no queue and no "wait for the animation" step. Pressing a block while the chain is
  still moving from the last change simply re-aims it (measured: a second change 200 ms into the
  first reaches the new position in 314 ms and never passes it — §5).

## §4 · The state machine

| State | What holds it | Leaves by |
| --- | --- | --- |
| **compact resting** | nothing; the bar alone | any key or the islands |
| **expanded** | an island at depth (the window island's Move) | `Esc` collapses before it closes |
| **contextual** | an island holds the slot (`open`) | `Esc`, a button, `×`, 30 s idle |
| **overview handoff** | the Atlas (Super+Tab's destination) | `Esc` first leaves its move strip, then closes it |
| **dismissal & focus** | the Escape chain | topmost first: confirmation → expanded → island |

The bar has one instrument of its own at a time — the mark's menu (`bar_menu`) — and it excludes
the islands, so a press on the mark closes whatever island was up. The islands follow the one-slot
rule (`docs/ARCHITECTURE.md`), which the bar does not change.

`Esc` unwinds in order — a pending close confirmation, then the expanded state, then the
island; in the wheel it leaves without committing; in the Atlas it leaves the move strip and
keeps the Atlas, then closes it.

## §5 · Motion

The bar adds three tokens to the shared set, all critically damped by the same rule as the rest
(`k = (6.64/T)²`, `c = 2·6.64/T`):

| Token | Reaches 99 % at | For | Measured |
| --- | --- | --- | --- |
| `m.confirm` | 240 ms | the workspace pulse after a window is moved | (shared) |
| `m.spin` | 380 ms | the chain sliding and turning, as one mechanism | 383 ms |
| `m.turn` | 260 ms | a module's prism turning to its next face | 233 ms |

A change moves the chain on **one** clock: `m.spin` carries the slide and the turn together, so the
mechanism reads as a single thing rotating through the focus slot. v7's pair — a 300 ms slide with
a 450 ms roll a beat behind it, deliberately geared — read as two mechanisms and could let a
neighbour's angle move *backward* before the roll caught up; v8 retires the pair. A press turns a
module on a clock of its own. They were **shortened** in v6 — 900/1350/1100 ms in
the vertical bar, which made a workspace change something you watched — to the renewed design's
own range for a transition (180–380 ms for the chain); the workspace has already changed by then
(the compositor is never waited for: §3). All are interruptible — re-targeting mid-flight simply
re-aims the spring, and the chain settles wherever the compositor really is.

Everything else is the framework's (`m.select`, `m.enter`, `m.exit`, `m.expand`/`m.collapse`,
`m.reflow`), and `tests/scene.sh` measures the islands' nine transitions on every run.
`--reduced-motion` settles every spring at once, the chain included.

The bar's chain and its modules' turns are **not** measured on every run: the suite promises never
to change workspace, and the chain only moves on a committed change. They were measured by hand
instead — a throwaway scene declaring the bar's own spring, recorded with `--record pos` and driven
by `--say … "fact go N"` exactly as `active_row` drives the bar (removed after), each at 1 %→99 %
of its travel: the chain's spin **383 ms** (token 380) and a module's turn **233 ms** (token 260).
Asked for a second position 200 ms into the first change, the chain reaches the new one in **314 ms**
from the re-ask (517 ms from where the motion began) and never passes it — 2.9945 of 3 at its peak —
which is what makes an interrupted change land cleanly. A measurement of the tokens, not of the
bar: committing a real `ws_pick` would have switched the user's workspace, which the suite does
not do.

The bar never animates at rest: no idle pulsing, no per-frame polling, no process spawned to
watch anything. State the bar shows comes from Pleamar's services (`clock`, `battery`, `network`,
`bluetooth`, `brightness`, `audio`, `media`, `workspaces`), which push; the bar reads.

## §6 · The modules, the transport, and the System surface

The row's readings are **`Module`s**: prisms whose three faces the scene writes, and whose press
turns them over to the next one. Each face is a different *kind* of reading — the shape first,
then the number, then the word — so the same prism replaces the glyph, the value and the name that
used to need three widgets:

| Module | face0 (the glyph) | face1 (the number) | face2 (the word) |
| --- | --- | --- | --- |
| **media** | the state: two bars while it plays, a triangle while it is paused, struck and quiet while nothing is on | the track's title | the artist |
| **volume** | the speaker, struck while muted | `42 %` | the level bar |
| **brightness** | a sun sized by the level | `100 %` | the level bar |
| **Bluetooth** | the rune, lit when the radio is on, struck when off, a dot while it scans | `on` / `off` | `BT` |
| **network** | three bars, as many lit as the signal has; a link mark on a wire; a struck line when offline | `42 %` (`—` when offline) | `online` / `offline` |
| **clock** | the time | the date | the day |

The geometry is the value — the bars are lit to the signal, the sun is sized by the level, the
rune is struck when the radio is off, the transport's play glyph is a triangle or two bars — and
the press is a read, never a write: turning a module over asks the services for nothing.

**The media, and its transport.** `service media as med { playing, title, artist }` is the
player's own report, so nothing is invented. The one thing the scene cannot read for itself is
whether there is a player with anything on it at all (`title` is empty when nothing has played),
so the logic watches `media` and sets `fact.media_on` — and the bar says so: with nothing on, the
reading's glyph is struck through and quiet, and the three transport zones are not created at all
(§1). When there is something, `active` is true and the plate takes its presses: back and on emit
`media_cmd(−1)` and `media_cmd(+1)`, the middle one `media_cmd(0)`, and the logic is what faces
the player (`sys.call("media.previous" / "media.next" / "media.toggle")`). Like the System
surface, the transport is the only thing here that *asks*: it is a control, not a reading.

Two of the readings have a control of their own: the **wheel over the volume module** sets the
level (`emit vol`, clamped, through the same event the System island uses), and a press on the
**System door** (slot 4) opens the surface that owns Volume and Brightness.

The System surface owns the controls (Volume, Brightness, and the state of the network and
Bluetooth). The readings report; they do not request. That is deliberate: a piece that only opens
a surface must not offer something the surface cannot do, and there is **no documented bluetooth
write** in Pleamar 0.4.6 (`sys.call` has none, and a `bluetooth` service you can only *listen* to
is asked for with `permissions.services: "bluetooth"`). So Bluetooth is shown, never toggled from
the bar; turning it on would need `bluetoothctl` through a `run:` permission and a read-back,
which is not built. The keyboard and the command membrane have their own ways in — `> sys` in the
membrane lists the System control among the mooi actions — so the System surface is reachable
with the bar's shape changing under no one.

A module for something the machine cannot have is not drawn at all (no backlight, no radio), and
the slots after it close the gap: the scene computes each slot from what exists (`have_clock`,
`have_bri`, `have_bt`), so the row never has a hole in it. The media reading and its transport
are not gated that way — they are always there, because a player coming and going must not move
every control after them along the bar; what changes is whether they answer (§1).

## §7 · The keyboard

The bar is the scene's **first** surface, so it carries the scene's only `keyboard:` clause:

```
keyboard: exclusive while (open != none or mark_open) and not (open == command and cmode == actions)
```

pleamar reads the *mode* from the first surface and the *`while`* from the last surface that
declares one, so no island may declare its own (a second one would silently replace this
condition scene-wide — see `docs/ARCHITECTURE.md`). The bar asks for the keyboard only while
one of its own instruments has a reason to: an island is up, or the mark's menu is open.

The one gap is the command surface in its window-actions mode. There the `←→` and `↵` belong
to the actions, but a focused `input` eats `←→` as caret movement and `↵` as a newline, and
no `blur` effect takes the writing cursor back from a scene-level rule. The scene therefore
**drops its keyboard claim** in exactly that state — the `not (open == command and cmode ==
actions)` — and the `input` stops seeing the keys. This is the launcher behaviour Pleamar
documents for `keyboard:` with a `while`.

## §8 · The surface, the marks, and the colours

**Matt black, steel, and neon on top.** The **body** is `plate` — `bg.primary` taken most of the way
to true black (`mix(bg.primary, #000000, 0.55)`; measured on the running bar, an interior of
(12,8,8)–(26,20,20)) — a chamfered slab from the mark's edge to the cap's, with eight bands of
falloff under a crossed grain (`g.tex` 9) clipped to it, so it reads as a matt black plate and not
as a rectangle of colour. The **shaft** is `metal`: `surface.elevated` lifted toward `fg.secondary`,
shaded as a cylinder. Every piece on the bar — a block, a module, a door, the cap — sits between the two,
and every **mark** is one of the palette's accents (§8). A new wallpaper moves all of it at once,
and nothing in the scene writes a colour that is not one of those.

**Matte, not gloss.** The body is laid down in eight bands that darken from its top to its foot
and then a grain over them: hairlines crossed at ±60°, every `g.tex` pixels, clipped to the slab,
at the edge of seeing — a weave rather than a brushed streak, so the surface reads as woven carbon
and not as striped paint. There is no bevel and no gradient that pretends the light is somewhere it
is not — a matte surface is read by its *texture*, and a body with nothing on it reads as a fill. The
marks are the opposite: **neon**. Every mark that means something is drawn twice, a wide soft
stroke under a sharp one (the arriving block's outline: 6 px at 0.26 of the block's proximity under
a sharp one, up from 4.5 at 0.20 when the glow was last tuned; the frame's own edge; a door with
its surface up), so what is lit reads as lit.

**Marks.** Each mark on the bar has a colour, and by default that colour is a palette **role**
(`lib/theme.luau`, `M.TONES`): the chain's arriving block, the readings and the doors are the
accent, the clock is text, the battery is `status.ok`, and the ways out, the brightness and the
cap are the second accent. So one wallpaper already gives the bar several colours rather than
one, and `bar.tones` gives any mark a colour of its own:

```json
"bar": { "tones": { "clock": "#FF00FF", "volume": "#00E5FF" } }
```

A name that is not a mark on the bar is reported (`theme · bar.tones.nope is not a mark on the
bar; ignored`) and the rest still apply — a misspelled mark must not cost the user their
colours. The marks are the pieces the scene draws: `chain`, `media`, `transport`, `clock`,
`system`, `volume`, `brightness`, `bluetooth`, `network`, `window`, `atlas`, `search`, `cap`.

**The wallpaper follows mooi on its own.** `mooi theme-sync` runs Matugen with mooi's own config
(one output file, no other program's colours touched) and `bin/mooi theme-watch` runs that
whenever the wallpaper changes. `mooi start` and `mooi takeover` start the watch beside the bar
and `mooi stop` ends it; it is also a plain foreground loop, so a session can run it from a
service of its own. It syncs once at startup when the palette's recorded source is not the
wallpaper now (`palette.from`), which is the one case a watcher cannot see: the wallpaper
changed while mooi was down. Matugen writes in place, so two syncs at once could hand mooi half
a palette — the watch takes a lock, and mooi refuses a half palette whole and keeps the last
good one.

## §9 · Settings the bar reads

| Setting | Default | What it changes |
| --- | --- | --- |
| `spine.clock` | `true` | the clock module in the row (slot 3) |
| `spine.max_workspaces` | `10` | how many positions the chain holds (1–16) |
| `bar.labels` | `true` | whether each block carries its workspace's name |
| `bar.wheel` | `step` | `step` changes workspace as the wheel scrolls over the chain; `off` ignores it (the wheel over the volume module is that module's own control, and always works) |
| `bar.tones` | — | a colour per mark on the bar (`bar.tones.clock = "#A6F3D1"`); unset marks take their palette role (§8) |
| `theme.source` | `wallpaper` | where the colours come from: the wallpaper's Matugen palette, or `fixed`, the brief's own (`docs/DECISIONS.md` D11) |
| `theme.overrides` | — | a colour per semantic token, over the palette |
| `island.confirm_close`, `island.follow_on_send`, `motion.reduced`, `atlas.previews` | — | the islands', not the bar's |

The `spine.*` names are kept from the vertical bar (the strip is the same strip, and a settings
file is not rewritten for a change of direction); they mean the bar.

All are validated, persisted and applied live (`docs/ARCHITECTURE.md`, "Configuration and
recovery"). `bin/mooi` reads `motion.reduced` at launch (it maps to `--reduced-motion`). A
safe-mode run reads defaults and never writes the file.

## What is deliberately not here

This is the bar, and the bar's own infrastructure. Not in it: any workspace **overview** of
its own (Super+Tab hands off to the Atlas), the **Assemblies**, a Command Membrane rewrite
(the bar *opens* the membrane; it does not own it), a notification manager, or replacing
Hyprland. Global modes (Rest / Focus / Explore / Workshop / Ambient) are still only specified
above the chain.

The bar's **appearance and density** work is not finished: there are no placement options
(four were specified) and no size presets — the machine's geometry is still tokens
(`g.prism_*`, `g.mod_*`, `g.tick`, `g.axis_y`) rather than settings. Colour is further along:
the three surface levels come from the palette and `bar.tones` colours each mark (§8), so one
icon or all of them can be a colour of their own, and there is no per-mark *shape* choice yet —
a mark is drawn in the bar's own vocabulary whatever colour it takes. The
proportions of the renewed design are tokens (`g.prism_*`, `g.mod_*`, `g.tick`, `g.axis_y`), so
the machine can be rescaled from one file, but nothing in the bar's own settings exposes them
yet. Two things a *horizontal* bar wants that are not built either: a **second monitor's** strip
(the surface is one monitor's), and a **narrow screen** — under about 1168 px the machine runs
past the right edge rather than giving something up.

That is the first-run stopping point: the bar is whole as a *thing* (regions, chain, wheel,
transport, state machine, motion, keyboard, status) and honest about its state, and
appearance/density is the next increment rather than a half-built one.

## Verifying it

`bin/mooi check` compiles the scene and runs the unit tests. `tests/scene.sh` drives the bar
and the islands through their state machine and measures the springs. And because pleamar can
print every surface's zones in surface pixels:

```
bin/mooi start
pleamar --say mooi describe        # every surface, its zones, and anything covering another
```

`describe` is how the Region B collision (the workspace scale's list zone starting *under* the
wheel's key) was found and fixed, and how the machinery along the bar was confirmed to have no
overlap: it names the zone, its rectangle, and any zone it covers. It is also how the transport's
gating was measured (§1) and how `tests/scene.sh` proves the chain's window and its focus slot —
the suite reads the slot from the chain's own zone rather than repeating the scene's arithmetic.
Reach for it before trust.
