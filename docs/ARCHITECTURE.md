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
| `spaces` (the workspace map) | logic (`lib/spaces`) | The bounded 1–16 workspace slots, from the `workspaces` service; **the Mechanism's scale and the Atlas's move strip both draw it** — the one place workspace state becomes rows, holding the positions the compositor has not made yet as well as the ones it has |
| The colour facts (`c_*_r/g/b`) | logic (`lib/theme`) | Forty-two facts: three per semantic token, 0 to 1, and `theme/tokens.plm` hands each to `rgb()`. Set together, or not at all. `palette.json` (Matugen) and `theme.*` settings are the only inputs; nothing else in the scene reads or writes them |
| `theme_error` | logic | The new theme did not pass completeness or contrast; the last good one is on screen and the Spine's dot says so |
| `previews` | logic, from settings (`atlas.previews`) | Preview pictures on or off. Off means they are not drawn, the frames are given back to the compositor and none is asked for again; `p` flips it and writes the setting (never in safe mode) |
| The keyboard | **scene rules + the first surface** | `keyboard: exclusive while (open != none or nav_open or mark_open) and not (open == command and cmode == actions)`; pleamar reads the mode from the scene's first surface and the single `while` from the last one that declares a clause, so the bar carries the scene's only clause — and it lets go in the command membrane's window-actions mode, where the arrows and Enter belong to the actions (below; D8; MECHANISM.md §7) |
| The bar's own state (`nav_open`, `nav_sel`, `mark_open`, `bar_labels`, `bar_wheel`, `active_row`, `bar_version`, `bar_path`) | scene rules, fed by the logic | The Mechanism: whether the wheel is engaged and what it previews, whether the mark's menu is open, whether the scale shows labels, what the wheel does over the scale, which workspace is active (from the `workspaces` service), and the version and path the menu names |

## The Mechanism (the bar)

The always-present rail, in one surface reserved for it: **identity** (the mark → the bar's own menu), **workspace navigation** (the Atlas key, the wheel's door, then the scale of workspace positions with the carriage riding it), **quick access** (search, the focused window) and **status** (network, Bluetooth, brightness, volume, the battery key, the clock). Everything beside the rail — the wheel's readout, the mark's menu — floats over windows, and because pleamar commits the input region from what is actually painted, nothing beside the rail takes a click (checked on the running desktop).

Two rules hold it together, both written out in **docs/MECHANISM.md**:

* **Geometry carries state, colour only confirms.** A position's size and the carriage's travel say what is; colour agrees. `accent.primary` means *what is*, `focus.ring` means *what the pointer or the keyboard is on*, and nothing else is allowed to be loud.
* **Preview is not commit.** The wheel and the scale may show a workspace before the compositor goes there (`nav_sel` vs `active_row`); `↵` asks `workspaces.focus` at once and never waits for an animation, and interrupted motion is simply the next state.

The scale draws the `spaces` map at fixed pitch, so a workspace the compositor has not made yet still has a position to be chosen. The status widgets read the services and each **opens the system surface**, which owns the controls — the bar never offers a control it cannot honestly drive, which is why Bluetooth is shown and never toggled (there is no documented write for it). Absent hardware closes its own gap: a widget the machine cannot have is not drawn and the ones above it move up (`have_bri`, `have_bt`).

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
docs/AUDIT.md). The bar's clause says "while an island is up, the wheel is engaged, or the
mark's menu is open" — and gives the keyboard up in the command membrane's window-actions
mode, where the focused `input` would otherwise eat the arrows and Enter (MECHANISM.md §7).

A window cannot be given the keyboard while a layer holds it: Hyprland answers the dispatches
but leaves the keyboard where it is. `focus` (the membrane's ↵ on a window, its Focus
satellite, an Atlas tile) therefore gives the slot up first and dispatches once the layer has
let go (`HANDOVER_MS`, mooi.luau); if it did not happen, `run_action` brings that island back
with what happened, so the failure is read and not guessed. The window island's own actions
(float, fullscreen, pin, move, close) do not need it. An `on_demand` keyboard would not work
here: its loan outlives the island by 300 ms.

Global modes (Rest / Focus / Explore / Workshop / Ambient) are still only specified. They will be one more scene-owned enum above the slot.

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

All are critically damped, which means no overshoot and the duration is time to 99 %. `tests/scene.sh` measures five of them on every run. `--reduced-motion` settles every spring at once (tested: 0 frames between open and closed).

## Adding an island

1. Add a value to `fact open` and a reveal spring `rv.<name>` with its `layer life.<name>`.
2. Declare `surface <name>_island` anchored next to its bar anchor, with `open: open == <name> or rv.<name> > 0.004`. **No `keyboard:` clause**: the bar's single clause (above) is the scene's, and a second declarer would silently replace its `while` condition for the whole scene.
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
| `shell/ui/mechanism.plm` | the bar's pieces: `Key`, `Status`, `Mark`, `Slot`, `Plate`, `Rule` — geometry carries state, colour only confirms |
| `shell/ui/island.plm` | shared pieces: `IslandFrame`, `Level` |
| `shell/theme/tokens.plm` | palette, semantic colours, geometry, motion springs |
| `shell/mooi.luau` | glue: settings, window target and verified actions (`run_action`, with the keyboard hand-over), the Atlas board and its pictures, the move strip's subject and target, preview privacy, system requests, icons |
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
| 7 · apply | `paint()` in `mooi.luau` | The forty-two facts, written only after the checks pass — so it is atomic in effect: all or none |
| 8 · rollback | `theme_error` | Nothing is written when a check fails; the last good theme stays on screen and the Spine's dot says the theme was refused |

mooi re-runs steps 3–8 whenever the settings change, a new palette file arrives (`files:palette.json`),
or something asks it to (`pleamar --say mooi "emit recolor"`, which is what `theme-sync` does).
What a palette can touch is exactly colour: layout, motion, behaviour and workspace settings are
not inputs to any of it, and `tests/theme.sh` checks that (settings byte-identical, other facts
unchanged). `theme.source = fixed` by default, so the wallpaper only takes over when asked.

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
