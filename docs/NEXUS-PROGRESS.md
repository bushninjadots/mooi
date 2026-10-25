# mooi · Control Nexus — progress

*Updated 2026-10-25.*

## S1 · Node model foundation (branch `nexus/s1-model`)

The first stage of the Control Nexus model is built and runs:

- `shell/lib/nexusnode.luau` — the node registry (19 types with sizes, limits,
  providers and default flags), the three arrangements (**FULL**, **FOCUS**,
  **MINIMAL**), legacy `nexus.modules` seeding, normalization, and
  provider-filtered visibility.
- `shell/lib/nexusgraph.luau` — the instantiated node graph and orthogonal
  circuit/direct routing with ports. Curved routing is S4.
- `shell/lib/nexuslayout.luau` — pure layout: snap, clamp, bounds, overlap,
  free slot, fit, tidy and focus swap.
- `shell/lib/config.luau` — schema v2 with validated `nexus.arrangements`,
  `nexus.focus`, `nexus.mode` and `nexus.banner.mode`; the legacy keys stay.
- `shell/mooi-nexus.luau` / `.plm` — seeds or loads the model at start and
  publishes `nx_arrangement_count`, `nx_node_count`, `nx_focus`, `nx_mode` and
  `nx_banner_mode`; follows battery, brightness, media, GPU and thermal
  presence, and writes the seeded arrangement once (`MOOI_SAFE=1` refuses).

**Verification.** `bin/mooi check` → **221 unit tests, 0 failed**, all five
scenes compile. `tests/nexus.sh` → the four new model checks pass; the run is
**68 checks, 33 failed**, exactly the 33 inherited plate assertions that were
already failing at the start of S1 (they name features this branch does not
carry). No new failure.

## S2 · Workspace shell (branch `nexus/s1-model`)

The model is on screen now, and the plate's hand-placed blocks are gone:

- **Surface.** One full-window overlay: a 44 px header (mark, `CONTROL NEXUS`, the mode,
  `CIRCUIT`/`MINIMAL`, the arrangement chips, `VIEWS`, `TIDY`, `LOCK`, `×`), the identity banner
  at `FULL 114` / `COMPACT 74` / `STRIP 44` / `HIDDEN 0`, the canvas and a 30 px status strip.
- **Nodes.** `model nx_nodes` carries one row per drawable node — title, reading, note, bar,
  tone, position, size limits, selection, focus, minimized — and the scene draws the rows.
  A press selects, a drag past 4 px moves (snapped to 8 px, clamped to the canvas), the corner
  grip resizes within the type's min/max, and the menu offers **FOCUS AT CENTRE**, **MINIMIZE**
  and **REMOVE FROM LAYOUT**. `Tab` walks the nodes, the arrows move one step, `Enter` focuses,
  `Delete` removes, `Escape` cancels a drag, then closes the drawer, then closes Nexus.
- **Arrangements.** The header chips switch FULL / FOCUS / MINIMAL; the mode switch applies
  MINIMAL's essential-only filter; the banner chip cycles the four heights; `TIDY` repacks on
  the grid. Every gesture writes the settings once, and `MOOI_SAFE=1` refuses the write.
- **VIEWS drawer (temporary).** SYSTEM (overview, COPY DIAGNOSTICS and the arrangement's removed
  nodes with **RESTORE**), AUDIO (routing, microphone, output level, Bluetooth), MIXER (one row
  per stream, wheel for the level, press to mute) and SPACES (the compositor's workspaces).
- **PIN** now locks the arrangement against drag and resize: a full-window surface has no
  outside left to press (D76).

**Verification.** `bin/mooi check` → **231 unit tests, 0 failed**, five scenes compile.
`tests/nexus.sh` → **60 checks, 0 failed** in the isolated lab runtime: seeded arrangements, a
snapped drop, minimize/restore, remove/restore, focus at centre, MINIMAL, arrangement switching,
the four banner heights, TIDY, both drawer tabs and the safe-mode refusal. The script's
inherited assertions for the D72 layout panel and the mixer/spaces/power views — features this
branch does not carry — were replaced by the node checks.

**Not checked.** A real pointer dragging a node (the facts were driven directly), a real
pointer on the resize grip and the node menu, and a visual pass at 1366×768 and 2560×1440.

## S3 · Centre focus (branch `nexus/s1-model`)

The node in the middle is a detail body now, and the temporary drawer is gone:

- **Detail bodies.** A focused node draws its reading, its bar and up to eight labelled rows,
  published by the logic (`rows`, `r1l`…`r8l`, `r1v`…`r8v`). System carries the overview's
  eight rows and **COPY DIAGNOSTICS**; Audio carries output, input, microphone, Bluetooth and
  up to four application streams with the plate's own press/wheel controls; Display answers the
  wheel with the backlight; Workspaces lists the compositor's spaces; Media carries the
  transport; Core, CPU, Memory, GPU, Thermal, Storage, Network, Clock and Power show four
  readings each. A missing provider reads `N/A`.
- **RESTORE CENTRE.** The header offers it whenever the middle is not the core; the node that
  was centred inherits the vacated slot, as the focus swap already did.
- **Undo.** `Ctrl+Z` and `Ctrl+Shift+Z` walk up to twenty deep-copied arrangements, recorded
  before every move, resize, focus, removal, restore, mode or banner change, and TIDY. A step is
  a whole arrangement, so a focus swap undoes together with the slot it displaced.
- **The VIEWS drawer is deleted.** Every panel it held now lives in its own node's detail body
  (D77), so nothing is reachable in two places.

**Verification.** `bin/mooi check` → **233 unit tests, 0 failed**, five scenes compile.
`tests/nexus.sh` → **72 checks, 0 failed**: the System detail's eight rows, the Audio detail's
four routing rows, RESTORE CENTRE, a drop undone and redone by position, and the stream and
workspace lists, alongside every S2 check.

**Not checked.** The detail controls from a real pointer (cycling the output device, muting a
stream, the brightness wheel), a media transport press against a live player, and the detail
body at 1366×768, where the rows and the transport share less room.

## S4 · Connections (branch `nexus/s1-model`)

The canvas now shows how the nodes relate:

- **Traces.** The authored graph in `lib/nexusgraph` is instantiated against the nodes on the
  canvas, filtered by the arrangement's hidden list and the mode, routed in the logic (style,
  12 px clearance, 12 px grid) and published as `model nx_edges` — four points, label, meaning
  and a midpoint per trace. The scene draws three segments and never solves a path; during a
  drag the dragged node's end of the trace follows the pointer.
- **Hover inspects.** A node's traces light when the pointer is on it; a trace shows its label
  and meaning on hover. **A press picks** a trace: both endpoints take a flare rim and a small
  panel offers `HIDE TRACE`, `CLOSE` and `RESTORE FULL NETWORK`. Hidden traces persist in the
  arrangement's `edges.hidden` and undo.
- **Focus isolates.** Outside the core, unrelated traces recede to 22 %; the focused node's own
  edges stay lit. In MINIMAL only activity-bearing traces draw.
- **Activity.** A trace whose provider is reporting carries a phosphor mark at its turn.
- **Morph.** Arrangement switches (and focus swaps, RESTORE CENTRE, undo/redo) move nodes over
  ~320 ms in eight whole-pixel steps instead of cutting (D78).

**Verification.** `bin/mooi check` → **234 unit tests, 0 failed**, five scenes compile.
`tests/nexus.sh` → **88 checks, 0 failed**: 8 traces from the authored graph, hover, pick,
endpoint marks, hide and restore, four unrelated traces receding from a focused node, and the
morph settling after a switch.

**Not checked.** Hovering a trace and a node with a real pointer, the trace popover at a narrow
width, and the signal marks against a busy machine (the providers were live but at idle).

**Next.** S5 library and customization: the module library with honest unavailable cards, node
settings, appearance, identity editing and arrangement management.

## Current phase

**Phase 1 complete; Phase 2 complete; Phase 3 started.** Phase 0 reconnaissance is
`docs/NEXUS-AUDIT.md`; the staged plan is `docs/CONTROL-NEXUS-NEXT-PHASE.md`. Audio routing, the
Bluetooth radio and device list, the application mixer, identity personalisation (name, avatar
and banner, imported through the editor or the CLI), workspace navigation and battery detail are
built and verified live. Phase 3's module customisation is in: all eleven modules of the plate —
the four control cards, the six live instruments and the player — can be turned off and reordered
within their band, and the plate carries three named layouts (**FULL**, **FOCUS**, **MINIMAL**)
with **SAVE AS** and **DELETE**, saved in `settings.json` as `nexus.layouts` and `nexus.layout`.
The identity header now carries a fastfetch-like summary (OS, kernel, uptime, CPU, memory, root)
and a strip of the shell's palette. What remains is the rest of the hardware detail,
palette-level layout presets, and a visual pass at every plate width.

## Built

- **Bar trigger.** A `nexus` module (the Arch mark, `shell/icons/arch.svg`) in
  `DEFAULT.right`; a press opens or closes exactly one standalone program, and the bar carries
  `nexus_open` so its own state is real.
- **Program.** `shell/mooi-nexus.plm` + `shell/mooi-nexus.luau` — a full-screen overlay with a
  right-anchored plate under the bar, an outside-press dismissal (unless pinned), ×, Escape,
  entrance/exit springs, the shared palette and theme tokens, and a duplicate-start guard.
- **Readings.** Clock/date, workspace, audio, brightness, battery, network, Bluetooth
  (present/powered), media; distro + version, kernel, uptime, CPU model, CPU load with core
  count, memory, root filesystem, network RX/TX rates, temperature, DRM GPU busy where the
  driver exposes it, and the Hyprland display summary. Missing sensors stay `N/A`.
- **Safe controls.** Output volume (wheel, click to mute), brightness (wheel), media transport
  (previous / play-pause / next). A refused call is reported in the footer, never faked.
- **System Overview.** A read-only panel toggled from the header: distro + version, kernel,
  uptime, CPU, memory, root storage, displays, GPU, host, session, workspace/time, and
  **COPY DIAGNOSTICS** (`mooi diagnostics copy`, local-only). Back returns to the controls.
- **System Identity.** Editable display name through a native Pleamar input, plus avatar and
  banner imports (`zenity` → `mooi identity`), rendered by the scene's own images. Paths stay
  inside mooi's data folder; writes are refused under `MOOI_SAFE=1`.
- **Persistence.** `nexus.pinned` and `nexus.identity.*` in `settings.json` (schema v1,
  validated, atomic writes).
- **Audio routing view (Phase 2).** A second header view: press **OUTPUT** or **INPUT** to cycle
  the default device, wheel the **MICROPHONE** row to set its level, press it to mute, and toggle
  the **Bluetooth** radio. Device names come from the audio service (`outputs` / `inputs`), the
  microphone level from `audio.input` / `input_muted`, and the radio from `bluetooth.present` /
  `powered`. An absent adapter says `N/A`; a refused call is reported in the footer.
  `lib/nexus.next_device` / `default_device` are pure and unit-tested.
- **Bluetooth devices (Phase 2).** Below the radio card, the AUDIO view lists up to five devices
  the `bluetooth` service reports, the connected ones first as the service orders them: name on
  the left, `CONNECTED` / `PAIRED` / `NEW` on the right. Pressing a row calls
  `bluetooth.connect` or `bluetooth.disconnect` with that device's address; `NO DEVICES KNOWN`
  when the service reports none. `lib/nexus.bt_rows` turns the service's booleans into the
  0/1 values the scene compares, gives a nameless device something to draw, and is unit-tested.
  The row is drawn for the first five, since that is the plate's room; the model keeps up to
  eight and the logic keeps the same rows, so a press uses the address whose name it showed.
- **Application mixer (Phase 2).** A third header view, **MIXER**, lists each stream the sound
  server reports (up to seven) with its name, what it is playing, its percentage or `MUTED`,
  `PLAYING` / `PAUSED`, and a bar. Wheel sets it in 5 % steps (`audio.app_volume`, batched every
  40 ms and read back 300 ms later); press mutes or unmutes (`audio.app_mute`).
  `lib/nexus.app_rows` clamps the volume, keeps the stream id, names an unnamed stream, skips
  a non-record and is unit-tested. A stream's id is kept whether it is text or a number: the
  sound server reports a number, and a text-only check left every row without a handle.
- **Module layout and named layouts (Phase 3).** A new **LAYOUT** panel (System Overview →
  `LAYOUTS`) lists every module of the plate with `ON`/`OFF` and `↑`/`↓`: the four control
  cards, the six live instruments and the media player, in three bands. A move stays inside its
  band, so a card cannot enter the instrument grid and the player keeps its full-width row; the
  plate reads one fact per module for whether it is drawn and one for its slot, so each band's
  gap closes and nothing else moves. `RESTORE` returns the catalogue order.
  The panel also carries a chip per named layout — **FULL**, **FOCUS**, **MINIMAL** on a fresh
  file — with **SAVE AS** naming a copy of the current arrangement (up to six, unique names,
  sixteen characters) and **DELETE** removing the showing one, never the last. The set is
  `nexus.layouts` (`{ name, modules }` records) and the showing name is `nexus.layout`, both
  validated by new `layouts` / text kinds with no array default, so a file without one still
  ships the three. D72's single `nexus.modules` list is migrated once into a **CUSTOM** layout
  instead of being lost. `lib/nexus.modules` / `layout_action` / `module_rows` / `layouts` /
  `layout_named` / `layout_add` / `layout_remove` are pure and unit-tested.
- **Banner band.** The plate no longer stretches the imported picture into its strip. The logic
  makes one cover-cropped band copy (`identity/<name>-228-band.jpg`, 1456×228) with `magick`,
  cached beside the import, and draws that at the band's own aspect; the imported file is left
  as it was, and the height in the name keeps an older crop from being stretched. Without
  ImageMagick the plate keeps drawing the original rather than claiming a band it could not
  make.
- **Banner summary and palette (D74).** The identity band is 114 px tall and holds two
  monospaced lines from the logic (`nx_spec_1`/`nx_spec_2`): OS, kernel, uptime, CPU (model
  without its `with …` suffix), memory and root, each cell padded to a fixed width. Under them a
  **PALETTE** strip draws fourteen shell roles as small chamfered swatches (`ground`, `hull`,
  `hull_raised`, `well`, `trace_dim`, `trace`, `trace_lit`, `phos`, `phos_fill`, `ember`,
  `ember_fill`, `flare`, `muted`, `steel_300`). Both are left out below 520 / 460 px of plate
  width. The layout panel now closes an open view and waits 60 ms before showing itself: drawing
  a view and the panel in one frame made the panel's text disappear (a Pleamar quirk).
- **Denser overview.** Eleven facts on 22 px rows: the previous eight plus **CPU LOAD**,
  **TEMPERATURE** and **NETWORK** (RX ↓ · TX ↑).
- **Workspace view (Phase 2).** A fifth header view, **SPACES**, draws the compositor's first ten
  workspaces in two rows of five: the zero-padded id, the window count and `CURRENT` / `SHOW`.
  Each block's press calls `workspaces.focus` with the id the logic kept for the row it drew;
  the list comes back through the service's watch, so the plate follows the compositor rather
  than the press. `lib/nexus.ws_rows` maps a record's boolean `active` to 0/1 (a record's bool
  is a presence claim), zero-pads the label, skips a record without a numeric id and keeps the
  ten-block cap; it is unit-tested. `nx_ws` carries the block's **turn**, as the Bluetooth rows
  do, because a copied block cannot hand a record field out through its press.
- **Battery detail (Phase 2).** The `battery` service only carries present/percent/charging, so
  health and the predicted time come from UPower's local report (`upower -e` → `upower -i`),
  read at start and again when the battery service changes. POWER shows `HEALTH 81%` and
  `ON AC · FULL` (or `4H 30M LEFT` / `TO FULL`) above uptime; no battery, no tool or no
  prediction stays `N/A`. `lib/telemetry.upower` accepts the locale's decimal comma and hours or
  minutes, and is unit-tested. LOCK was already built; the four session rows still arm.
- **Identity import repaired.** `bin/mooi identity` works again: four parameter expansions in it
  had been written escaped (`\${…}`), so every action fell through to the usage text and no
  image was ever imported. `bin/mooi` also puts its own `bin` on `PATH`, which is how the
  scene's picker and diagnostics copy can run `mooi` by name, and a refused `files.write` is no
  longer reported as a successful save.
- **Picker over an overlay (D69).** While `zenity` is up, the Nexus surface steps from
  `level: overlay` to `background` and gives the keyboard up (`keyboard: exclusive while
  nx_picking == 0`), so the dialog is above the plate and can be typed into. The plate and the
  outside-press layer hide until the answer comes back; the identity editor is drawn last and
  catches its own presses.
- **A replaced picture shows (D70).** `mooi identity avatar|banner` now writes a fresh
  `identity/<kind>-<epoch>-<pid>.<ext>` on every import, removes the previous file of that kind
  and points settings at the new name. A scene's image is not re-read at the same path, so this
  is what makes the plate change while it is open, from the editor, the picker or the CLI.

## Files changed

New earlier: `docs/NEXUS-AUDIT.md`, `docs/NEXUS-PROGRESS.md`, `shell/mooi-nexus.plm`,
`shell/mooi-nexus.luau`, `shell/icons/arch.svg`, `docs/CONTROL-NEXUS-NEXT-PHASE.md`,
`shell/lib/telemetry.luau`, `tests/nexus.sh`.

Modified across the Nexus build passes:

- `shell/mooi-nexus.plm` — resolved the merge markers left by the branch consolidation;
  System Overview view and its toggle; the audio routing view and its toggle; identity presence
  facts and initial; availability-aware Bluetooth footer; input declaration brought to the
  language's current properties; command allowlist (`hyprctl`, `mooi`, `zenity`, no `sh`).
- `shell/mooi-nexus.luau` — resolved merge markers; fixed `env()` being used before it was
  declared (the logic died at startup); `sync_identity()` publishes name, initial, paths and
  presence facts from one place; per-identity writes respect `MOOI_SAFE`; GPU busy read over
  fixed `card0…card2` paths instead of a shell; distro row carries the OS version; audio
  device names and the microphone/Bluetooth paths are read back from the services.
- `shell/lib/nexus.luau` — `next_device` / `default_device` for routing lists; `bt_rows` for
  the Bluetooth list (states as 0/1, a skip for non-records, the model's cap kept).
- `tests/unit/run.lua` — fixtures for the routing and Bluetooth rows (184 tests now).
- `shell/mooi-nexus.plm` — the `btdev` model, the five-row Bluetooth list and its rows' press
  event, the identity editor moved after every view so it is drawn over them, and a catch zone
  under it so a press inside the editor does not reach the view behind.
- `shell/mooi-nexus.luau` — watches `bluetooth` for the device records and maps a row press to
  `bluetooth.connect` / `bluetooth.disconnect`; audio cycling reads the service back instead of
  assuming the switch landed; `NO OTHER OUTPUT` / `NO OTHER INPUT` when there is nothing to
  cycle to.
- `tests/nexus.sh` — the bar copy is renamed `mooi-lab` with its own socket, so the lifecycle
  test can run beside a live mooi; the CPU reading is polled until the first sample; the
  Bluetooth list count and first row name are checked; the mixer opens and closes and its
  stream list is checked; the SPACES view opens and closes and its model count and first id
  are checked; battery health from UPower and a non-empty time line are checked; two identity
  imports into a throw-away data folder must write different names, leave one avatar file and
  keep the imported one.
- `shell/mooi-nexus.plm` (D68) — the `nxapp` model, the MIXER view and its rows, the third
  header button, the views kept exclusive, and the overview's 22 px rows with the three new
  readings.
- `shell/mooi-nexus.luau` (D68) — reads `audio.apps` into the model, sends `audio.app_volume`
  on a 40 ms batch and reads the service back, calls `audio.app_mute` on a press, and checks
  what `files.write` returns for identity and pin saves.
- `bin/mooi` (D68) — unescape the identity parameter expansions and put `$root/bin` on `PATH`
  for the scene's `mooi` commands.
- `bin/mooi` (D70) — identity imports write a fresh versioned file name; `remove` and `reset`
  clear both the old canonical and the versioned names.
- `shell/mooi-nexus.plm` (D69) — `nx_picking` drops the surface to `background`, gives the
  keyboard up and hides the plate; the editor's catch zone keeps presses out of the view.
- `shell/mooi-nexus.plm` (D71) — the fifth SPACES tab and view, the `nxws` model, the blocks'
  press event, and POWER's battery card grown for health/time; `workspaces.focus` and `upower`
  added to the allowlist.
- `shell/mooi-nexus.luau` (D71) — view activation through one table (SPACES included), the
  workspace list read and indexed for a press, and the UPower collector with N/A fallbacks.
- `shell/lib/nexus.luau` (D71) — `ws_rows` for the workspace blocks.
- `shell/lib/telemetry.luau` (D71) — `upower` for health, state and a predicted time.
- `shell/mooi-nexus.plm` (D73, D74) — the `NInstrument` component, the cards and instruments
gated by `nx_mod_on_*` and placed by `nx_mod_slot_*`, the player gated on its own fact, the
LAYOUT panel with its three bands, the layout chips and the SAVE AS / name / DELETE footer, the
banner band grown to 114 px with the two summary lines and the fourteen palette swatches, the
banner image declared at 1456×228, the views and switch moved down, the SPACES labels put the
right way round, and `magick` added to the allowlist.
- `shell/mooi-nexus.luau` (D72, extended by D73 and D74) — the layout state, its facts and the
panel's actions, the named layouts' read/write/switch/save/delete, the `nexus.modules`
migration, the settings write and its safe-mode refusal, the band copy made once per import
(named for its height), the fastfetch lines composed and padded from the readings, and battery
text through `lib/nexus.battery_detail`.
- `shell/lib/nexus.luau` (D73) — `BANDS` and an eleven-module `MODULES`, `modules`,
`layout_action` with band-aware moves, `band_count`, `module_rows`, `layouts`, `default_layouts`,
`layout_named`, `layout_state` (the `nexus.modules` migration), `layout_add`, `layout_remove`,
`battery_detail`; numeric stream ids kept.
- `shell/lib/config.luau` (D73) — the `ids` kind kept for `nexus.modules`, the new `layouts`
kind, and `nexus.layout` / `nexus.layouts`.
- `tests/unit/run.lua` (D73) — layout defaults/actions/rows/slots across three bands, the named
layouts' defaults, lookup, add/remove rules, the migration choosing CUSTOM, and validation,
numeric stream ids, battery detail, and the setting's validation (195 tests now).
- `tests/nexus.sh` (D73, D74) — a banner imported through the CLI drawn as a `-228-band.jpg`;
eleven modules and three layouts at start; hide, band move, restore; MINIMAL and FULL switching
the plate (66 checks now).
- `tests/unit/run.lua` (D71) — workspace rows and two UPower fixtures (188 tests now).
- `tests/unit/run.lua` (D68) — the app mixer row mapping (185 tests now).
- `shell/lib/sysinfo.luau` — `cpu_cores` split on a literal `\n` instead of a newline; the
  display scale formats as `1.00x`.
- `tests/unit/run.lua` — new telemetry fixtures use real newlines; the layout fixture now
  reflects the real default `media.idle = "collapse"` (nothing playing).
- `tests/nexus.sh` — checks the local collector and the System Overview toggle.

## Verification

- `./bin/mooi check`: **all five scenes compile** (bar, settings, wallpaper studio, board,
  Nexus), **193 unit tests, 0 failed**.
- **Banner (live + lifecycle test):** the imported 2560×1440 photograph was cropped into
  `identity/banner-…-band.jpg` and filled the identity header at its own aspect, instead of the
  149-pixel thumbnail the old declaration drew. `tests/nexus.sh` imports a banner through the
  CLI into the temporary folder and checks the plate draws a `-228-band.jpg`.
- **Banner summary and palette (isolated captures):** the 114 px header drew the two summary
  lines with real readings (`OS EndeavourOS`, `KERNEL 7.2.11-arch1-1`, `UPTIME 3h 6m`,
  `CPU AMD Ryzen 5 7430U`, `MEMORY 10.3 / 15.0 GiB`, `ROOT 80% used`) over a full-width
  `banner-228-band.jpg`, with the fourteen swatches below and the plate's rows and footer
  fitting inside 720 px. The layout panel opened from the overview after the new 60 ms turn and
  drew its chips, rows and footer.
- **Migration (isolated):** a settings file with only the D72 list (`cpu`, `player`) started the
  plate with a fourth chip, CUSTOM, as the one showing: no control cards, one instrument and the
  player, in the saved order. Before `lib/nexus.layout_state`, the defaults' `FULL` won and the
  saved order was kept in the panel but not drawn; the file was not rewritten by reading it.
- **Layout (live + lifecycle test):** the panel opened from the System Overview with the three
  chips (FULL, FOCUS, MINIMAL) and all eleven modules in their three bands; turning memory off
  dropped the instrument count and closed its gap, moving a plate up swapped it within the
grid, and RESTORE brought the catalogue back. MINIMAL left OUTPUT, DISPLAY and the player on
an otherwise empty plate with `LAYOUT: MINIMAL` in the footer. The edited FOCUS order and its
current name were written to `settings.json` (`nexus.layouts`, `nexus.layout`, no
`nexus.modules`). The lifecycle test repeats hide, band move, restore and MINIMAL/FULL in the
temporary environment.
- **Mixer writes (live):** a real `mpv` stream gave the mixer a row; pressing MUTE put the
  service at `muted = 1` and `pactl` at `Mute: yes`, and three wheel notches moved it from 63 %
  to 58 % in both. The first pass did nothing: the stream id is a number and `app_rows` kept
  only text ids. Fixed, and the unit test now covers a numeric id.
- **Bluetooth writes (live):** the adapter is rfkill-soft-blocked, so the Nexus's power-on was
  refused and reported `BLUETOOTH FAILED`; unblocked, the Nexus powered it on and off again. A
  connect press reached BlueZ (it answered `br-connection-busy`), but none of the three known
  devices was reachable, so no connection was made. The radio was returned to its blocked state.
- **Discharging battery (isolated fixture):** a fake `upower` reporting `state: discharging`,
  `capacity: 81.4%` and `time to empty: 2.3 hours` on an otherwise real scene drew `HEALTH 81%`
  and `2H 18M LEFT` on POWER while the battery service still said 98 %.
- **SPACES labels (live):** the label inversion was found and fixed (`CURRENT` was drawn on the
  workspaces that were not current); pressing `01` moved the session to workspace 1 and the
  flags followed, then `02` brought it back.
- **Application mixer (isolated):** the mixer opened and closed, the audio and overview views
  closed with it, and the stream list answered from the sound server (empty that run: nothing
  was playing). The row layout was compiled but not drawn with a live stream.
- **Identity (isolated, writes enabled):** the imported name, avatar and banner were read back;
  `nx_avatar_on` / `nx_banner_on` were true; the editor's save persisted `Studio Rig 3`; a
  `mooi identity avatar` run while the scene was up changed the path the scene watched; and a
  diagnostics copy reached the clipboard. No runtime errors.
- **Identity picker and replacement (live):** the real `zenity` dialog opened above the Nexus;
  the chosen file imported through `mooi identity avatar`; `AVATAR IMAGE UPDATED` appeared and
  the new picture was drawn with the editor still open. A `.jpg` avatar replaced by a different
  `.jpg`, and a `.jpg` banner likewise, changed on the plate with no restart; the originals were
  then restored and drawn again. The identity folder ended with one avatar and one banner file.
- **Workspaces and battery (live):** SPACES drew the compositor's two workspaces (`01`, `02`);
  a pointer press on the second block moved the focus to workspace 2 (the session was left
  there), and pressing the current block through the agent reported the event with no failure.
  POWER drew `HEALTH 81%` and `ON AC · FULL`; the four session rows sat inside the plate. A real
  left click (ydotool `0xC0`) also opened the identity editor, opened the zenity picker and
  closed the Nexus with its ×: the earlier "no pointer" result was `click 1`, not the left button.
- **Live after the restart:** the scene's env carries `PATH=…/bin:…` and `MOOI_BIN`; the
  Nexus read `bluetooth.present = true`, three known devices (`Galaxy A16` first), opened the
  mixer and the overview with real readings (10 % CPU, 51 °C, 2K ↓ / 2K ↑) and kept the three
  views exclusive; Escape closed it and the bar cleared `nexus_open`. A second pass with a
  playing stream drew a real mixer row (`kew`, 78 %, `PLAYING`) with no runtime errors.
- **Bluetooth list (isolated):** the model held the service's three known devices, the first
  row read `Galaxy A16`, `bluetooth.present = true` and `powered = false`, and the audio view
  opened and closed with no runtime errors in the bar log. The connect/disconnect press was
  **not** fired, so the user's adapter was left alone.
- **Lifecycle test as rewritten:** `tests/nexus.sh` is **66 checks, 0 failed** against the
  temporary `mooi-lab` bar beside the live mooi, including the SPACES view, the UPower health
  line, a CLI-imported banner drawn as a band copy, eleven modules and three layouts, hiding,
  moving within a band, restoring, and MINIMAL/FULL switching the whole plate.
- **Isolated run** (temporary `HOME`/`XDG`, `MOOI_SAFE=1`, no effect on the running bar):
  real readings — EndeavourOS, kernel `7.2.11-arch1-1`, uptime, CPU load with 12 cores,
  memory, 80 % root disk, `eDP-1 · 1920x1080 · 60 Hz · 1.00x`, GPU 13 %, 50 °C; pin on/off;
  Overview on/off; Escape ended the program; no runtime errors.
- **Identity:** saving in safe mode is refused with a notice and settings are untouched;
  with writes enabled the name persists to `settings.json` and survives a restart.
- **Audio view (isolated):** the output named `Ryzen HD Audio Controller Speaker`, the input
  `Ryzen HD Audio Controller Digital Microphone`, `audio.input = 0` and `input_muted = false`,
  Bluetooth `present = true`, `powered = false`; the audio and overview views are mutually
  exclusive; no runtime errors. The write paths (cycling a device, mic level/mute, powering the
  radio) were **not** exercised, so the user's audio and Bluetooth were left untouched.
- **Live deployment:** after `bin/mooi refresh` the Arch mark is on the real bar (`x_nexus` =
  1097), `bin/mooi nexus` opens the program, the bar marks `nexus_open` true, the AUDIO view
  names the real output device, and Escape ends it and clears the bar's state.
- **Lifecycle:** a live mooi is running on this machine, so the combined test was reproduced
  in a temporary copy of `shell/` with the bar scene renamed `mooi-lab` (its own socket):
  two rapid activations start exactly one Nexus, the bar marks `nexus_open` true, the same
  trigger closes it and clears the bar, reopening works, and Escape ends it. No bar errors.

## Not checked

- The Overview toggle, COPY DIAGNOSTICS, and the layout panel's SAVE AS and DELETE from a real
  pointer (the facts, the agent's hand and a pointer pass on older controls were used; the
  naming and removal rules are unit-tested).
- A seventh layout being refused on screen, and the panel at a narrow plate.
- The Overview's on-screen density at every plate width, and multi-monitor placement.
- Power profiles (power-profiles-daemon is masked): still unavailable, as the audit requires.
- A successful Bluetooth connect/disconnect: the radio was powered on and off through the Nexus
  and the connect press reached BlueZ, but none of the three known devices was reachable. A row
  while BlueZ is working is untested for the same reason.
- The SPACES grid past ten workspaces live: it needs eleven occupied workspaces, which would
  mean opening them on the real desktop. The cap and ordering are unit-tested; the live grid
  drew the two workspaces this session had.
- LOCK and the other three session actions: they are drawn and arm, but firing LOCK would lock
  the session, so none was executed.
- A battery actually discharging on this machine (it is on AC); the text is covered by a fake
  UPower fixture.
- A visual pass over the five-tab header, the Overview and the band banner with a small picture.
- A real photograph in the banner's 6.4:1 band (gradients and flat colours were used), and the
  header at the widths where the summary and palette are left out.
- The layout panel's overlap with the taller banner and the switch row on a narrow plate.

## Next step

1. Add the remaining hardware detail behind capability checks (fans, per-output controls).
2. Fire SAVE AS and DELETE from a real pointer, and check the panel at a narrow plate.
3. Fire the Bluetooth connect/disconnect with a device powered on, and watch a row while BlueZ
   works.
4. A visual pass over the five-tab header, the Overview and the layout panel at every width.
