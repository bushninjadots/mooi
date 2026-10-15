# The Mechanism

The bar: mooi's own rail down the left edge of the screen. It is the one surface that is
always there — it says where you are, lets you move between workspaces, opens the four
islands, and shows the state of the machine — and everything else in mooi opens *beside*
it.

This file is the bar's design and its implementation constraints. Scene code cites it as
**§1** (what the geometry may and may not say) and **§3** (what a preview may and may not
commit to).

The bar is built in `shell/mooi.plm` (`// ══ The Mechanism · the bar ══`, the first surface
and everything down to its rules), its two reusable shapes are in `shell/ui/mechanism.plm`
(`Key`, `Status`, `Mark`, `Slot`, `Plate`, `Rule`), and its geometry and colour come from
`shell/theme/tokens.plm`. What is deliberately **not** here is at the end of this file.

## §1 · What the geometry may say

The bar is drawn on **one rail** — a 48 px surface, `anchor: left`, `reserve: 48`,
`level: top` — with one axis down it, `g.rail_x = 24`. The mark, the carriage, the dial and
the status glyphs all line up on that axis, so a change in any one of them is read against
the same line.

The rule the whole bar is built on:

> **Geometry carries state. Colour only confirms it.**

A workspace's mark is as tall as the workspace is busy (`g.mark_min = 5` for a slot Hyprland
has not made yet, up to `g.mark = 15` for one with windows); the carriage sits where the
active workspace is; the spoke leans towards the wheel's choice; the cursor ring is where the
pointer is. You can read the bar with the colour turned off. Colour then says two things and
only two:

| Token | Means |
| --- | --- |
| `accent.primary` | **what is** — the active workspace, a level that is set, a radio that is on |
| `focus.ring` | **what is pointed at** — the key or the position under the pointer, the wheel's own choice |
| `fg.*` / `border.subtle` | the quiet majority: hairlines, labels, the unfilled part of a level |
| `status.error` | something is wrong and you can act on it (a refused theme, a low battery, a mute, no connection) |

Two consequences the code depends on, both verified on the running desktop:

- **A conditional colour cannot be a `let`.** `let` takes an expression or a plain colour;
  `if(cond, a, b)` returns one colour, so `let tone = if(lit, accent.primary, fg.muted)` is a
  load error. The bar writes the arithmetic instead — `mix(fg.muted, accent.primary, p)` with
  `p` a 0–1 number — which is also what makes the level meters continuous rather than stepped.
  `clamp()` keeps `p` in range. (A `let` **is** allowed inside a `group`, which is where the
  per-widget ones live.)
- **Nothing is placed from a value that has not arrived yet.** The scale is laid out from the
  configured span (`ws_max`), never from what the service has reported so far, so the bar does
  not move when the first report lands (`let span_h = ws_max * g.slot`).

Two more of Pleamar's that the bar is careful about:

- `pick(i, a, b, …)` is **0-based** — index 0 is the first. It also takes a `bool` as the
  index, so `pick(cond, "when false", "when true")` is the idiom for a label. `if(cond, a, b)`
  is the opposite order and is for numbers and colours. Getting these two the wrong way round
  is silent: the label reads backwards and nothing complains.
- `path` is **one stroke per `path`** (`move` once, then `line`/`curve`, optionally `close`);
  several strokes are several `path`s. This is how the Bluetooth rune is drawn.

Geometry tokens (`shell/theme/tokens.plm`): `g.spine` 48 (rail width and the surface's
reserve) · `g.rail_x` 24 · `g.slot` 26 (pitch of one workspace position) · `g.slots_y` 132
(where the first position sits — **below** Region B's keys and their hairline, so the scale's
list zone never covers them) · `g.slot_h` 24 · `g.mark`/`g.mark_min` 15/5 · `g.carriage` 11 ·
`g.key_w`/`g.key_h` 36/26 · `g.sp` 30 (pitch of one Region D status widget) · `g.plate` 196 ·
`g.radius.key` 6.

The surface is reserved for the rail; what floats beside it — the wheel's readout, the mark's
menu — is painted over the windows, and because pleamar commits the input region from what is
actually painted, nothing off the rail takes a click.

## §2 · The four regions

Top to bottom, one rail:

**A · identity.** The mark (`Mark`, 32×32) — a frame, the index and graduations, opening the
bar's own menu: colours (fixed or from the wallpaper), the scale's labels, what the wheel
does, and the path of the settings file. A hairline closes the region.

**B · navigation.** The region the design spends the most on. Two keys of the bar's own kind
sit above the scale they belong to — the Atlas (the overview handoff) and the wheel's door —
then a hairline, then the **scale itself**: one `Slot` per configured workspace position,
1–`ws_max`, drawn on the rail axis. A slot's mark height is its window count and `focus.ring`
marks the position under the pointer; the **carriage** (three boxes riding a travelling `trav`
spring) sits where the active workspace is. The wheel's door opens the **dial**: a spoke that
leans towards the wheel's choice, an arc, and a plate reading `SPACE`, the workspace name and
number, and the keys that work there. The mark's menu opens in the same place.

**C · quick access.** Two keys: search (the command membrane) and the focused window's
actions. Above them, a hairline.

**D · status.** Bottom-anchored, on the rail axis: **network, Bluetooth, brightness, volume**,
then the **system key** (battery) and the **clock**. Each of the first four is a glyph whose
*geometry* carries its state and each opens the system surface; see §6. The error dot (a
refused theme, a broken settings file) sits just above the region's hairline.

## §3 · Preview is not commit

The wheel previews a workspace without moving you to it.

> **A preview is a position the wheel is pointing at. A commit is what the compositor has
> actually done. They are never drawn as the same thing.**

`nav_sel` is where the wheel points; `active_row` is where you are. The spoke leans towards
the choice and stands straight when they agree (`lean = clamp((active_row - (nav_sel - 1)) * 30,
-60, 60)`) — so "the wheel points where you already are" is legible as the spoke being
straight, without a second mark. The readout names the previewed workspace; the active
workspace keeps `accent.primary`. Committing (`↵`) asks `workspaces.focus` and closes the
dial; the carriage moves when the *service* says the workspace changed, not when the key was
pressed.

Two rules follow, and they are why the wheel is built the way it is:

- **Never delay the real operation for an animation.** The focus call is made at once; the
  animation is what happens while it lands. Nothing in the bar waits for a spring.
- **Interruption is free.** Every transition is a spring that can be re-targeted mid-flight;
  there is no queue and no "wait for the animation" step. Pressing the wheel's key again
  closes the dial wherever it is.

## §4 · The state machine

| State | What holds it | Leaves by |
| --- | --- | --- |
| **compact resting** | nothing; the bar alone | any key or the islands |
| **workspace navigation** (`nav_open`) | the wheel's door | `↵` (commit), `←→`/scroll (choose), `Esc` (back, no commit) |
| **expanded** | an island at depth (the window island's Move) | `Esc` collapses before it closes |
| **contextual** | an island holds the slot (`open`) | `Esc`, a button, `×`, 30 s idle |
| **overview handoff** | the Atlas (Super+Tab's destination) | `Esc` first leaves its move strip, then closes it |
| **dismissal & focus** | the Escape chain | topmost first: confirmation → expanded → island |

Two instruments never open at once: `bar_menu` and `bar_dial` are one at a time (`on
press`/`toggle` guards in the rules). The islands follow the one-slot rule
(`docs/ARCHITECTURE.md`), which the bar does not change.

`Esc` unwinds in order — a pending close confirmation, then the expanded state, then the
island; in the wheel it leaves without committing; in the Atlas it leaves the move strip and
keeps the Atlas, then closes it.

## §5 · Motion

The bar adds one token to the shared set: **`m.confirm`** (765, 55 · 240 ms), the workspace
pulse after a window is moved. Everything else is the framework's (`m.select`, `m.enter`,
`m.exit`, `m.expand`/`m.collapse`, `m.reflow`), critically damped, measured on every
`tests/scene.sh` run. `--reduced-motion` settles every spring at once.

The bar never animates at rest: no idle pulsing, no per-frame polling, no process spawned to
watch anything. State the bar shows comes from Pleamar's services (`clock`, `battery`,
`network`, `bluetooth`, `brightness`, `audio`, `workspaces`), which push; the bar reads.

## §6 · The status widgets, and the system surface

Region D shows the five essentials and the clock. Each widget is a **glyph whose geometry is
the value**, and each one is a **way into the system surface** — not a control:

| Widget | Geometry says | Opens |
| --- | --- | --- |
| **network** | three bars, as many lit as the signal has (0–100 %); a link mark on a wire; a struck line when offline | the system surface |
| **Bluetooth** | the rune, lit when the radio is on, struck when off, a dot while it is scanning; absent if the machine has no adapter | the system surface |
| **brightness** | a sun whose size and rays grow with the level | the system surface |
| **volume** | a speaker with a level bar; struck while muted | the system surface |
| **system key** | the battery outline and its level | the system surface |
| **clock** | the time | — |

The system surface owns the controls (Volume, Brightness, and the state of the network and
Bluetooth). The bar's widgets report; they do not request. That is deliberate: a widget that
only opens a surface must not offer something the surface cannot do, and there is **no
documented bluetooth write** in Pleamar 0.4.6 (`sys.call` has none, and a `bluetooth` service
you can only *listen* to is asked for with `permissions.services: "bluetooth"`). So Bluetooth
is shown, never toggled from the bar; turning it on would need `bluetoothctl` through a `run:`
permission and a read-back, which is not built.

A widget for something the machine cannot have is not drawn at all (no backlight, no radio),
and the ones above it close the gap (`have_bri`, `have_bt`), so the column never has a hole
in it.

## §7 · The keyboard

The bar is the scene's **first** surface, so it carries the scene's only `keyboard:` clause:

```
keyboard: exclusive while (open != none or nav_open or mark_open) and not (open == command and cmode == actions)
```

pleamar reads the *mode* from the first surface and the *`while`* from the last surface that
declares one, so no island may declare its own (a second one would silently replace this
condition scene-wide — see `docs/ARCHITECTURE.md`). The bar asks for the keyboard only while
one of its own instruments has a reason to: an island is up, the wheel is engaged, or the
mark's menu is open.

The one gap is the command surface in its window-actions mode. There the `←→` and `↵` belong
to the actions, but a focused `input` eats `←→` as caret movement and `↵` as a newline, and
no `blur` effect takes the writing cursor back from a scene-level rule. The scene therefore
**drops its keyboard claim** in exactly that state — the `not (open == command and cmode ==
actions)` — and the `input` stops seeing the keys. This is the launcher behaviour Pleamar
documents for `keyboard:` with a `while`.

## §8 · Settings the bar reads

| Setting | Default | What it changes |
| --- | --- | --- |
| `spine.clock` | `true` | the clock at the foot of the rail |
| `spine.max_workspaces` | `10` | how many positions the scale holds (1–16) |
| `bar.labels` | `true` | whether each position carries its workspace's name |
| `bar.wheel` | `step` | `step` moves a window as the wheel scrolls; `off` ignores the scroll |
| `theme.source` | `fixed` | the palette (see `docs/DECISIONS.md` D11) |
| `island.confirm_close`, `island.follow_on_send`, `motion.reduced`, `atlas.previews` | — | the islands', not the bar's |

All are validated, persisted and applied live (`docs/ARCHITECTURE.md`, "Configuration and
recovery"). `bin/mooi` reads `motion.reduced` at launch (it maps to `--reduced-motion`). A
safe-mode run reads defaults and never writes the file.

## What is deliberately not here

This is the bar, and the bar's own infrastructure. Not in it: any workspace **overview** of
its own (Super+Tab hands off to the Atlas), the **Assemblies**, a Command Membrane rewrite
(the bar *opens* the membrane; it does not own it), a notification manager, or replacing
Hyprland. Global modes (Rest / Focus / Explore / Workshop / Ambient) are still only specified
above the slot.

The bar's **appearance and density** work is not finished: there are no placement options
(four were specified), no size presets, and no accent or surface choice — the rail's geometry
and the palette's semantic tokens are the only knobs today, and the two bar settings above.
That is the first-run stopping point: the bar is whole as a *thing* (regions, scale, wheel,
state machine, motion, keyboard, status) and honest about its state, and appearance/density is
the next increment rather than a half-built one.

## Verifying it

`bin/mooi check` compiles the scene and runs the unit tests. `tests/scene.sh` drives the bar
and the islands through their state machine and measures the springs. And because pleamar can
print every surface's zones in surface pixels:

```
bin/mooi start
pleamar --say mooi describe        # every surface, its zones, and anything covering another
```

`describe` is how the Region B collision (the workspace scale's list zone starting *under* the
wheel's key) was found and fixed, and how the Region D stack was confirmed to have no overlap:
it names the zone, its rectangle, and any zone it covers. Reach for it before trust.
