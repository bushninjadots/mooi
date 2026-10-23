# Architecture

mooi is **one Pleamar scene** (`shell/mooi.plm`) with one Luau logic (`shell/mooi.luau`) on top of Hyprland. It is one scene because Pleamar scenes share no state (limitation G22), and the Spine, Islands and Membranes must.

```
     Hyprland (windows, workspaces, focus, keys)        the system (PipeWire, backlight, power, NM)
        │ socket events / ext-workspace   ▲ hyprctl         │ pleamar services          ▲ sys.call
        ▼                                 │                 ▼                           │
┌─ pleamar process ───────────────────────┼─────────────────────────────────────────────┼──┐
│  render thread · shell/mooi.plm         │      logic thread · shell/mooi.luau          │  │
│   surfaces: Spine · window_island ·     │       settings (lib/config)                  │  │
│     system · command · atlas islands    │       window actions (lib/hypr) ────────────┘  │
│   the slot `open` + rules (never wait)  │       workspace map (lib/spaces; svc)        │
│   springs and layers (lifecycle)        │       icons (lib/apps)                         │
│   ui/island.plm: IslandFrame, Level     │       command membrane (command/lib/search)   │
│                 ◄──────── facts / texts / events ────────►                                │
└───────────────────────────────────────────────────────────────────────────────────────────┘
     ▲ pleamar --say mooi …   (bin/mooi, Super+Alt+Space)          bin/mooi keeper: restarts, takeover
```


## Who owns what

| State | Owner | Notes |
| --- | --- | --- |
| Windows, workspaces, focus | **Hyprland** | Never mirrored. Read on demand (`hyprctl -j`) or from the `workspaces` service (Hyprland socket; ext-workspace if the socket is gone) |
| Volume, mute, brightness, battery, network | **the system** | Shown from Pleamar's services. A requested change shows only once the service reports it |
| `open` (none / window / system / command / atlas): the island slot | **scene rules** | Input on the render thread, so Escape and the Spine buttons work even if the logic hangs. Actions close their own surface only if it still holds the slot |
| `phase` (compact / expanded) | scene rules | Depth of whichever island holds the slot |
| `sel`, `wsel`, `arming`, `srow`, `cmode`, `csel`, `asel`, `carming`, `atlas_sel`, `atlas_mode`, `atlas_ws` | scene rules | Selection and close confirmation (the `c…` ones are the membrane's) and the Atlas's (its tile, browse or move, and the workspace the move strip has chosen) |
| Membrane results (`model res`) | logic (`shell/command.luau`) | Rebuilt on every keystroke from windows (`hyprctl -j clients`, read on open and after actions), apps (`apps` service), workspaces and mooi actions; ranked by `lib/search` |
| Usage counts | `~/.local/share/pleamar/mooi/usage.json` | How often each result was chosen; lifts it in ranking, capped so relevance wins. Forgets the least used half past 200 entries |
| `busy` / `atlas_busy` | set by rules, cleared by the logic | A window or Atlas workspace action is with Hyprland; actions are refused while it holds |
| Window target | logic, **from Hyprland** | Captured by address when the window island opens, refreshed after every action |
| Settings | `~/.local/share/pleamar/mooi/settings.json` | The only on-disk source. JSON, versioned, schema in `lib/config.luau` |
| Tokens | `shell/theme/tokens.plm` | Colours, geometry, motion; components use semantic names only |
| Atlas board (`model atlas_tiles`) | logic, **from Hyprland** | One tile per window Hyprland lists (address, class, title, workspace), rebuilt while the Atlas is up; the `thumbnails` service only lends the picture, matched to a window by app and title |
| `spaces` (the workspace map) | logic (`lib/spaces`) | The bounded 1–16 workspace slots, from the `workspaces` service; **the Mechanism's chain and the Atlas's move strip both draw it** — the one place workspace state becomes rows, holding the positions the compositor has not made yet as well as the ones it has |
| The colour facts (`c_*_r/g/b`) | logic (`lib/theme`) | Forty-two facts: three per semantic token, 0 to 1, and `theme/tokens.plm` hands each to `rgb()`. Set together, or not at all. `palette.json` (Matugen) and `theme.*` settings are the only inputs; nothing else in the scene reads or writes them |
| `theme_error` | logic | The new theme did not pass completeness or contrast; the last good one is on screen and the Spine's dot says so |
| `previews` | logic, from settings (`atlas.previews`) | Preview pictures on or off. Off means they are not drawn, the frames are given back to the compositor and none is asked for again; `p` flips it and writes the setting (never in safe mode) |
| The keyboard | **scene rules + the first surface** | `keyboard: exclusive while (open != none or mark_open or side != none or bar_edit or qn_open or stash_naming) and not (open == command and cmode == actions)`; pleamar reads the mode from the scene's first surface and the single `while` from the last one that declares a clause, so the bar carries the scene's only clause — and it lets go in the command membrane's window-actions mode, where the arrows and Enter belong to the actions (below; D8; MECHANISM.md §7). The settings window, the wallpaper studio and the board are **programs of their own** and hold the keyboard in their own scenes (D64), so the bar's clause no longer names them |
| The bar's own state (`mark_open`, `bar_labels`, `bar_wheel`, `active_row`, `bar_version`, `bar_path`) | scene rules, fed by the logic | The Mechanism: whether the mark's menu is open, whether the blocks carry labels, whether the wheel over the chain steps a workspace, which workspace is active (from the `workspaces` service), and the version and path the menu names. The chain's own two phases (`pos`, `roll`), the module faces and the blocks' angles are read off those: no second source of truth |

## The Mechanism (the bar)

The always-present strip along the **top edge**, in one surface reserved for it (56 px, `anchor: top`) — one exposed machine along it, ported from the renewed design (`pleamar helix bar/helix-v2-mooi/`, v6, the horizontal exposed helix): a matt black **body** whose surface is the bar's background (v7), a **shaft** of steel running the whole of the navigation region, the **chain** of workspace blocks threaded on that shaft — it slides along the bar so the block the compositor is on always sits at the focus slot, and the window it is seen through is a sleeve over the shaft, so the ends of the list show steel rather than a hole — a **module row** beside it of twelve slots and one frame — the media reading and its transport, the clock, the System door, the four readings (volume, brightness, Bluetooth, network) and the bar's three ways out (the focused window, the Atlas, the membrane) — and the mark at the left end, with the end cap at the right. Off the machine the desktop shows through the strip wherever there is no body, prism, shaft or cap. Everything under the strip — the mark's menu — floats over windows, and because pleamar commits the input region from what is actually painted, nothing there takes a click — nor does the strip's own empty space, measured on the running desktop. What the bar *asks of the machine* is the transport (the player's own commands) and the volume module: everything else it shows is a report.

Two rules hold it together, both written out in **docs/MECHANISM.md**:

* **Geometry carries state, colour only confirms.** Which way a block is turned, which position sits at the focus slot, which face of a module is toward you, how long a level bar is — those say what is; colour agrees. `accent.primary` means *what is*, `focus.ring` means *what the pointer or the keyboard is on*, and nothing else is allowed to be loud.
* **The compositor is the only authority.** A press on a block, or a notch of the wheel over the chain, asks `workspaces.focus` at once and never waits for an animation; the chain — whose slide and roll follow `active_row` alone — moves only when the service says the workspace changed, so the block at the focus slot is always where you really are. Nothing on the bar can point somewhere you are not (the dial that could was removed in v6b), and interrupted motion is simply the next state.

The chain draws the `spaces` map through `pos`, in workspace units, so a workspace the compositor has not made yet still has a position to be chosen — and the window onto it moves with you. The readings (modules) are read-only: a press turns the prism over to its next face, and the tiles report what the services say. The System door opens the surface that owns the controls — the bar never offers a control it cannot honestly drive, which is why Bluetooth is shown and never toggled (there is no documented write for it). Absent hardware closes its own gap: a module the machine cannot have is not drawn and the slots after it move along the bar (`have_clock`, `have_bri`, `have_bt`); the media reading and its transport are always drawn (a player coming and going must not move every control after them), and it is their *zones* that go quiet when there is nothing to drive (`fact.media_on`).

Not here: the workspace overview, Assemblies, a rewrite of the command membrane, a notification manager, and appearance & density (placements, size presets, accent and surface choice) — the first-run stopping point.

## The island slot and lifecycle

```
                open_window                       activate(Move)
   none ─────────────────────────► window/compact ───────────────► window/expanded
    ▲ ▲ ◄── Esc / button / × / 30 s idle ──┘  ▲ ◄────────── Esc ───────┘
    │ │                                        │
    │ └── target gone · closed · moved (logic)  open_system / open_window hand the slot over
    │                                        ▼
    └────── Esc / button ─────────────── system
```

Escape takes the topmost level first: a pending close confirmation, then the expanded state, then the island.

Each island has its own reveal spring (`rv.window`, `rv.system`). `entering` and `exiting` are not states: they are that spring travelling (`layer life.*`: `m.enter` in, `m.exit` out). Handing the slot over moves both springs at once, each from where it is. Rapid switching therefore never leaves a half-open island (tested: window → system → window inside 120 ms). A surface stays mapped while its spring is above 0.004, so it never vanishes before it has left.

### The keyboard, and giving it to a window

`keyboard:` is read once for the scene, and by the scene's **first** surface: pleamar takes
the mode from `scene.surface().keyboard` (the bar, which declares the scene's only clause)
and the single `while` condition from the last surface that declares one. An island's own
`keyboard: exclusive while open == <name>` is therefore never read — worse, a second
declarer silently *replaces* the scene's condition, so an island that asks for the keyboard
only while it is open takes it away from every other instrument at once. With the islands
carrying their own clauses nothing took the keyboard at all, so typing went to the window
under the island and Escape never arrived (the harness never noticed, because
`pleamar --say mooi "key Escape"` injects the key straight into the scene — see
docs/AUDIT.md). The bar's clause says "while an island, the side panel, edit mode, the
quick-notes pad or the stash's naming field is up, or the mark's menu is open" — and gives the
keyboard up in the command membrane's window-actions mode, where the focused `input` would
otherwise eat the arrows and Enter (MECHANISM.md §7). The settings window, the wallpaper studio
and the board are whole programs of their own (`mooi-settings.plm`, `mooi-wallpaper.plm`,
`mooi-board.plm`): each is its own scene with its own exclusive clause, so the bar does not name
them at all — and before it starts one, it lets go (D64).

A window cannot be given the keyboard while a layer holds it: Hyprland answers the dispatches
but leaves the keyboard where it is. `focus` (the membrane's ↵ on a window, its Focus
satellite, an Atlas tile) therefore gives the slot up first and dispatches once the layer has
let go (`HANDOVER_MS`, mooi.luau); if it did not happen, `run_action` brings that island back
with what happened, so the failure is read and not guessed. The window island's own actions
(float, fullscreen, pin, move, close) do not need it. An `on_demand` keyboard would not work
here: its loan outlives the island by 300 ms.

Global modes (Rest / Focus / Explore / Workshop / Ambient) are still only specified. They will be one more scene-owned enum above the slot.

## The wallpaper studio (Lumen)

A program of its own (`shell/mooi-wallpaper.plm`, `.luau`), like the settings window: it holds the
keyboard exclusively and has a surface of its own, so it cannot share the bar's single keyboard
clause (D8/D53). Its data folder is linked to mooi's by `bin/mooi`, so `wallpapers.json` is the
shell's and `palette.json` relights the studio with the bar. `lib/wallpaper` is the pure part — the
recipe, the vibes, the crop and the exact ImageMagick arguments — and the logic runs them. One
picture is edited at a time through a screen-shaped base in mooi's cache; a preview is a new
1600 × 900 file, and `APPLY` renders the screen's size and hands that still to the wallpaper picker
(`qs ipc call wallpaper set`), which draws it and makes the palette. **The source is only ever
read**: every edit is a new file, and the recipe per source is kept so the studio reopens on it.

The source wall reads a folder, not a fixed cache: `find <folder> -maxdepth 1 -type f -printf`
lists it, `lib/wallpaper.parse_find` keeps the pictures by extension (newest first), and only the
tiles on the page are thumbnailed — one `magick` at a time, into `~/.cache/mooi/wallpaper/thumbs` —
so a folder of thousands costs a page, not thousands of files. Every read is `find -L`, so a folder
that is a link is read as the folder it points at. The folder is chosen in the studio (the field,
the `BROWSE…` picker — a typed path, `HOME`/`PICTURES`/`ROOT`, then subfolders a level at a time —
or the live wallpaper's own folder) and kept in `wallpapers.json`; on a first run it is whichever of
the recorded folder, the live wallpaper's folder, the picker's `wallpaperDir`, or `~/Pictures`
exists first, and the studio's own stills in its cache are never mistaken for a folder of pictures.
A folder that cannot be read shows home instead of a dead end.

**Quality** (D63): the base is a lossless PNG resampled with Lanczos, previews and the source view
are JPEGs at 95 with `4:4:4` colour, and the still applied is a PNG (`M.args` writes what the
output's extension asks for, `M.is_png`). The recipe keeps a history — one entry per burst of edits,
cleared per picture — which is what UNDO/REDO and `Ctrl+Z`/`Ctrl+Y` walk; the backdrop's palette is
`M.SWATCHES`, seven of the theme's roles and two neutrals, rebuilt in `paint()`.

**The background key** (`M.args` with `key` on, D62) is a flood fill from the eight border points
(`-alpha set -fuzz N% -fill none -draw "alpha x,y floodfill …"`), so it takes the background the
picture's edge is joined to rather than every pixel of a colour, needs no colour read, and is made
last so no composite or grain can put the transparency back. The hole is filled by the backdrop:
black, the picture blurred, a colour read from the edges, or `bg_custom`, a `#RRGGBB` typed in the
studio and kept in the picture's recipe. The bar's
framed-picture module (a press emits `open_wallpaper`) and the `keys.wallpaper` key
(`SUPER + ALT + P`, from `lib/desktop`'s actions) open the studio; both are ordinary modules/keys,
so the settings window lists them with every other one.

## The board (Kanban)

A program of its own too (`shell/mooi-board.plm`, `.luau`, D64). `shell/board.luau` is still the
board (over the pure `lib/board`: columns with limits, cards, tags, due days, undo), and
`mooi-board.luau` paints the shell's Ferrolume roles from `palette.json`, starts that logic and
puts the scene away again. `board.json` is mooi's own — `bin/mooi` links the program's data folder
to the shell's, as it does for the studio and the settings window — so a note the pad sends to the
board (a card added to the file by `shell/mooi.luau`) arrives through the board's own watch.

The bar keeps only what the pad's rail shows: how many cards there are and how many are late,
read from `board.json` through the same `lib/board` rules. It starts the program on `board_show`
(the pad's rail, `Ctrl+Shift+B`/the pad's key, or `mooi board`) — after a frame, so the bar has
let go of the keyboard first — and closes it by `--say mooi-board quit` on the same request; the
program's exit is reported back, which refreshes the badge. The entrance is the one it had in the
bar's scene (a bar across, then the board drops open around it).

**Leaving.** A press on the plate under the board covers the screen: a press anywhere the board is
not (`baway`, under every control) emits `close_board`, as do the ×, Escape and a press on the
bar's own board button. The logic brings `board_in` down (the board folds away the way it came),
then runs `pleamar --say mooi-board quit` 240 ms later, so the compositor gives the keyboard back
to whatever is under it. That is what makes the outside press the *whole* screen's, not just the
bar's: the board no longer shares the bar's scene, so it brings its own plate (the bar's plate
still closes its own panels).

## The motion framework

| Token | Spring | Duration | Used by |
| --- | --- | --- | --- |
| `m.instant` | 12247, 221 | 60 ms | state flips that must not lag |
| `m.select` | 3062, 111 | 120 ms | selection.change, focus.change, feedback text, level values |
| `m.enter` | 1361, 74 | 180 ms | surface.enter |
| `m.exit` | 2249, 95 | 140 ms | surface.exit |
| `m.expand` / `m.collapse` | 1102, 66 / 1722, 83 | 200 / 160 ms | window island depth |
| `m.confirm` | 765, 55 | 240 ms | state.confirm: the Spine pulses the workspace a window was moved to |
| `m.reflow` | 911, 60 | 220 ms | layout.reflow: the workspace column |
| `m.spin` | 305, 35 | 380 ms | the chain of workspace blocks sliding and turning as one mechanism |
| `m.turn` | 652, 51 | 260 ms | a module's prism turning to its next face |

All are critically damped, which means no overshoot and the duration is time to 99 %. `tests/scene.sh` measures the islands' nine transitions on every run; the chain's spin and a module's turn are the bar's own and are measured by hand, because the chain only moves when the compositor really changes workspace and the suite promises never to (the numbers are in STATUS.md). `--reduced-motion` settles every spring at once (tested: 0 frames between open and closed).

## Adding an island

1. Add a value to `fact open` and a reveal spring `rv.<name>` with its `layer life.<name>`.
2. Declare `surface <name>_island` anchored to the edge it belongs to and `margin:`ed clear of the bar's strip — the window island hangs from the top left under the bar, the command island from the top centre (`margin: 84, 0, 0, …`), the System island from the bottom left, the Atlas centred — with `open: open == <name> or rv.<name> > 0.004`. **No `keyboard:` clause**: the bar's single clause (above) is the scene's, and a second declarer would silently replace its `while` condition for the whole scene.
3. Draw it inside `IslandFrame(rv.<name>, w, h[, up: true][, centre: true])` from `ui/island.plm` (`centre` grows from the middle of the top edge, for an island with no Spine anchor).
4. Add `on open_<name>` rules (toggle and hand-over), its keys guarded by `while open == <name>`, and an Escape rule.
5. Add it to `tests/scene.sh`.

## Actions: the honesty loop

```
rule: activate(k) → busy = true; emit act(k)
logic: read window by address ── gone? → "That window is gone", close the island
       build Lua dispatch (lib/hypr: address validated as ^0x%x+$)
       hyprctl dispatch … ── not "ok"? → "Hyprland refused: …"
       read window back ── compare with before (close: poll 6 × 250 ms)
       → op_done "Floating" / op_failed "Hyprland did not change floating"
```

"ok" from `hyprctl` is not trusted: Hyprland answers "ok" for an address that does not exist. Without Hyprland's IPC, the window island opens and says there is nothing to act on, and actions stay refused (`tests/degraded.sh`).

## Configuration and recovery

1. `MOOI_SAFE=1` (or `bin/mooi run --safe`): built-in defaults, and the file is not read.
2. File missing: defaults, which are then written to the file.
3. File broken (not JSON): `settings.known-good.json`, the last file that loaded with no problems; otherwise defaults. The Spine shows a heat-coloured dot.
4. A field wrong (type or range): that field's default, the rest applied, the dot shown.
5. Unknown keys: logged and ignored. A newer `version`: noted.

Kinds: `boolean`, `integer` (with `min`/`max`), `enum` (with `values`), and `colours` (a table of
token = `#rrggbb`, which is how `theme.overrides` is kept to one setting whose token names may
contain dots — a dotted setting path could not name them). A row with no default is not written
by `defaults()`: it is a setting the user may add, and its absence means "not set".

The file is watched, so edits apply live (the theme is one of the things applied). `motion.reduced`
is read by `bin/mooi` at launch (it maps to `--reduced-motion`).

## Files

| | |
| --- | --- |
| `shell/mooi.plm` | the scene: the bar (the Mechanism), the islands, the command membrane, rules |
| `shell/ui/island.plm` | shared pieces: `IslandFrame`, `Level` |
| `shell/theme/tokens.plm` | palette, semantic colours, geometry, motion springs |
| `shell/mooi.luau` | glue: settings, window target and verified actions (`run_action`, with the keyboard hand-over), the Atlas board and its pictures, the move strip's subject and target, preview privacy, system requests, icons, the pad's badge and the board's program (start and close) |
| `shell/mooi-board.plm` · `.luau` | the Kanban board as its own program (D64): the scene (columns, cards, the pane, keys) and the logic that paints the palette, starts `shell/board.luau` and quits it on `close_board` |
| `shell/board.luau` · `lib/board.luau` | the board's scene-keeping and file, and the pure board rules (unit-tested) |
| `shell/command.luau` | the command membrane: what it lists, and what choosing a result or satellite does |
| `shell/lib/spaces.luau` | the bounded, pure workspace-slot map the bar's scale and the Atlas's move strip draw |
| `shell/lib/theme.luau` | the pure theme model: the fixed palette, Matugen roles → semantic tokens, overrides, colour maths and contrast checks |
| `theme/matugen.toml.in` · `theme/palette.json.hbs` | mooi's own Matugen config and template (`bin/mooi theme-sync` fills the paths in): one output file, no other program's colours touched |
| `shell/lib/config.luau` · `hypr.luau` · `apps.luau` · `search.luau` · `spaces.luau` | pure modules, unit-tested under Lua 5.4 |
| `bin/mooi` | launcher, keeper and shell switch (SWITCHING.md) |
| `tests/` | unit, scene lifecycle and motion, live Hyprland and system, degraded IPC, config recovery |

## Workspace Atlas

The Atlas is a wall of the windows that exist, two per row, with the workspace each sits on.
Hyprland's clients are what it is built from — with their own addresses, so every tile can be
focused — and Pleamar's `thumbnails` service lends the pictures: while the Atlas is up,
`thumbnails.want("all")` asks the compositor to copy every window, and the reports carry each
picture's *path with a version*, which `image … = from` paints and reloads as it changes
(`stale` when the compositor stops copying that window). A picture cannot be matched by
identifier — the ids are the compositor's own (`18000015`), not Hyprland addresses — so it is
matched by app and title, one window each; a window with no picture is still a tile, named
only. On closing, `thumbnails.want()` gives the frames back and no more pictures are taken.

The board is rebuilt on every report while the Atlas is open (windows opening and closing
move the tiles under the selection, and the pictures refresh), and left as it is while the
Atlas leaves, so the way out is whole. A tile focuses its window through the same verified
path as everything else, hand-over included; a failure brings the Atlas back and says what
happened in the logic's own words (the header line shows `text feedback`), never that it
must have worked.

**Moving a window.** `m` turns the strip below the board into a workspace picker built from the
same `model spaces`, so an empty slot can be chosen and Hyprland creates it. ←→ (or a
click) picks one, ↵ emits `atlas_move` and the logic moves **the selected tile's** window there
through the same verified path as the window island (`run_action`: read, dispatch, read back),
with `follow = false` so the user stays where they are. The Atlas is *not* closed — a move is
not a choice — and the Spine pulses that workspace. The strip starts on the workspace the
selected window is on (`fact.atlas_ws`, kept in step from the board and the selection) and its
subject is named by `text atlas_target`, both set by the logic. `←→` are the only keys: a
scene key cannot be a digit, so the picker is walked, not typed at.

**Previews are a promise.** `p` toggles `previews` (the `atlas.previews` setting, written and
reloaded like any other). While it is off, no picture is matched into a tile and
`thumbnails.want()` is called at once, so the compositor stops copying; on it is called
`thumbnails.want("all")` again. A safe-mode run never writes the settings file, so the test
harnesses can flip it without touching the user's config.

`shell/lib/spaces.luau` still turns the `workspaces` service's positive records into the
configured 1–16 slot map (`model spaces`: id, window count, active, exists), including
the empty slots Hyprland will create; `atlas_go` requests `workspaces.focus` and closes only
once a service update reports that workspace active. The map is state, not the drawing: the
tiles are the drawing, and the strip borrows it.

## Theme: colour is data, and it can change while the shell runs

mooi's look is fourteen semantic tokens, not colours written into components. Each token is
`rgb(r, g, b)` over three facts, because that is the one way Pleamar lets the logic hand over a
colour that did not exist when the scene was read (docs/AUDIT.md; `docs/11-language-reference.md`,
`rgb(r, g, b)`). The facts are born with the brief's palette, so the shell looks right even
before any theme is read.

The brief's pipeline runs in `shell/lib/theme.luau` (pure, unit-tested), in this order:

| Step | Where | What |
| --- | --- | --- |
| 1 · input | `bin/mooi theme-sync` | Matugen 4.2.0 reads the wallpaper (the picker's still at `~/.cache/current_wallpaper`, or an image you pass) with **mooi's own config**, so the only thing written is the palette file — the user's own Matugen config keeps recolouring everything else |
| 2 · palette | `~/.local/share/pleamar/mooi/palette.json` | `theme/palette.json.hbs`: the ten Material roles mooi maps, as hex. Declarative data: no code runs to load a theme |
| 3 · mapping | `M.FROM_MATUGEN` | One role per token (`surface_dim` → `bg.primary`, `on_surface` → `fg.primary`, `primary` → `accent.primary`…), and `selection.bg` is a blend of `bg.primary` and `primary`, computed numerically so it is validated like the rest |
| 4 · overrides | `theme.overrides` in settings | `token = "#rrggbb"`; wins over the palette, and an unknown or malformed one is ignored with a note |
| 5 · completeness | `M.check` | All fourteen tokens, or the theme is refused |
| 6 · contrast | `M.REQUIRED` | WCAG ratios for text on its three surfaces (4.5:1) and for the accent ring and error text (3:1); the numbers in `docs/AUDIT.md` §7 are these pairs |
| 7 · apply | `paint()` · `paint_marks()` in `mooi.luau` | The forty-two token facts and the thirty-nine mark facts, written only after the checks pass — so it is atomic in effect: all or none |
| 8 · marks | `M.marks` · `bar.tones` | One colour per mark on the bar: the palette role each one takes (`M.TONES`), with `bar.tones.<mark> = "#rrggbb"` over it. An unknown name or colour is ignored with a note |
| 9 · rollback | `theme_error` | Nothing is written when a check fails; the last good theme stays on screen and the cap's dot says the theme was refused |

mooi re-runs steps 3–9 whenever the settings change, a new palette file arrives (`files:palette.json`),
or something asks it to (`pleamar --say mooi "emit recolor"`, which is what `theme-sync` does, and
what `bin/mooi theme-watch` runs on every wallpaper change — with `mooi start`/`takeover` starting
the watch beside the bar and `mooi stop` ending it).
What a palette can touch is exactly colour: layout, motion, behaviour and workspace settings are
not inputs to any of it, and `tests/theme.sh` checks that (settings byte-identical, other facts
unchanged). `theme.source = wallpaper` by default (D18), so the bar follows the wallpaper unless the
user says `fixed`; with no palette generated yet the fixed palette shows and the log says why.

The toolchain is a dependency of the *test*, not of the shell: with no `palette.json` and
`source = wallpaper`, mooi says so and keeps the fixed palette.

## The command membrane

Super+Alt+Space, the Spine's search button or `bin/mooi toggle`. A fixed island at the top centre: a field, then up to `command.max_results` results (3–10, default 7).

| Typed | Lists |
| --- | --- |
| nothing | open windows (most recently focused first), then apps, lifted by usage |
| text | windows, apps, workspaces and mooi actions, ranked: exact > prefix > word start > substring > letters in order; alternative names (class, desktop id, exec) at 80 % |
| `@text` | windows only |
| `>text` | mooi actions only (system controls, window actions) |
| `3` | workspace 3 first (offered even if empty) |

↵ opens the selected result: an app starts through `apps.launch` (only apps the `apps` service reported, never text from a window title); a window is focused; a workspace is switched to and the membrane closes only once Hyprland reports it; a mooi action opens its island. Tab (or ⋯ on the row) opens a window result's **satellite actions** inline: Focus, Bring here (to the current workspace, never following), Float, Fullscreen, Close (asks once). They go through the same verified path as the window island (`run_action`: read, dispatch, read back). Esc order: close confirmation → satellites → membrane.
