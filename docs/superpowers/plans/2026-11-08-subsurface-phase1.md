# Subsurface Phase 1 — The Opening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Holding Super opens the wallpaper itself where the pointer is and shows the subsurface under it — hubs, components, the widgets and BMO — with snap, scroll-to-widen, click-to-use, drag-out-to-keep and heal; the phase 1 radial hub and its overlay above every window are removed.

**Architecture:** `mooi-surface` owns the opening (a pure module computes its state and target hole; one packed set of facts is sent to every citizen on change). Every program follows the global pointer itself with identical springs (a generated `<gen:opening>` block), so nothing is sent while the opening merely follows the pointer. Layers: wallpaper (`mooi-desk`, background) → `ground` (`mooi-surface`, background, mapped on each open so it is above the wallpaper: the hole's dark ground, the hubs, the components) → citizens (`mooi-widgets`, `mooi-viz`, BMO; bottom, drawing and taking clicks only inside the hole) → `edge` (`mooi-surface`, bottom, mapped on each open so it is above the citizens: the effect's rim and the warped wallpaper patch, no zones) → windows.

**Tech Stack:** Pleamar 0.7.11 scenes (`.plm`) + Luau logic, WGSL group shaders, Python 3 generators in `tools/`, Lua 5.4 unit tests (`tests/unit/run.lua`), POSIX sh live tests (`tests/surface.sh`), Hyprland 0.57 Lua config.

**Spec:** `docs/superpowers/specs/2026-11-08-subsurface-design.md` (phase 1, §3–§6, §10, §11), on top of `docs/superpowers/specs/2026-11-08-surface-design.md`.

## Global Constraints

- Ships behind `surface.on` (default `false`); with it off, every program behaves exactly as on `main` today (widgets and BMO always visible, Super tap = `emit pill_call`, Super+wheel = the bar's).
- Never cut through a window: no surface of this phase is at level `top` or `overlay` (the old `reveal` overlay is deleted).
- Nothing in the frame's band; idle (no opening) = nothing mapped by `mooi-surface` beyond today's `bar`/`drop`/`desk`, and citizens' below-groups hidden (Pleamar skips hidden groups).
- Each layer < 1 ms compose + paint at 60 fps (`pleamar --report`).
- Springs only for the opening's motion, never a long `~…ms` tween (D152: it keeps a scene painting). One spring for all programs: `spring sg.op = 220, 24`.
- Paths animated per frame use straight steps (`move`/`line`), never `curve` (D128).
- Emit payloads packed under 2^24 (float32, D124); coordinates clamped to 0…4095.
- Never `screen.height` in a multi-surface scene: use `<surface>.height` (found live, D208).
- A new setting: `lib/config` default + validation, `tools/gen-settings.py` SETTERS kept in sync with `shell/lib/setters.luau` (gen refuses a mismatch), edit zones only through `tools/gen-settings.py` MODULES.
- Generated blocks are never hand-edited; CI regenerates and diffs (`.github/workflows/check.yml`, `bin/mooi check`).
- Tests never move the real pointer; live checks drive `pleamar --say`. The real Super key is tried only with the owner.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; decision number for this phase: **D209**.

## Review Focus

1. **Super+click on the desktop is eaten by Hyprland's `SUPER + mouse:272` window-drag bind** → a click while holding Super must reach the citizen's zone (Task 1 decides; Task 7 owns the fallback and its test).
2. **`mooi-surface` dies while an opening is open** → citizens hide their below-things within a second and the drag bind (if unbound) is restored (Task 7, Task 10).
3. **The owner holds Super for a shortcut** (Super+Return) → the opening stays faint, takes no keyboard and no clicks, and heals on the focus change (Task 3, Task 7).
4. **A widget dragged out lands half off-screen or on the bar** → it is clamped fully on screen below the bar reserve (Task 8).
5. **Surface switched off while an opening is open, or widgets/BMO restarted mid-opening** → everything returns to today's always-visible state; a restarted citizen asks for and receives the current opening (Task 8, Task 9).

---

### Task 1: Check the desk's facts with the owner

Three behaviours decide the fallback paths; none can be checked without real keys. Nothing from this task is kept but the findings.

**Files:**
- Create (scratch only): `$SCRATCH/probe/probe.plm` — one surface at `level: background`, one at `bottom`, each a 300×300 box with a zone that `emit`s `hit(1|2)` and prints via the logic.
- Modify: `docs/superpowers/plans/2026-11-08-subsurface-phase1.md` — append a `## Findings (Task 1)` section.

- [ ] **Step 1:** Run the probe beside mooi (`pleamar --scene $SCRATCH/probe/probe.plm`), ask the owner to (a) click each box plainly, (b) click each box **while holding Super**, (c) hold Super and roll the wheel over each box. Record which presses reach the probe and whether Super+wheel ran `mooi wheel` (check `~/.local/state/mooi/mooi.log` / the bar's workspace change).
- [ ] **Step 2:** Record the findings: F1 Super+click reaches a layer zone (yes/no); F2 the `background` box is above `mooi-desk`'s wallpaper when mapped after it (yes/no); F3 Super+wheel reaches `mooi wheel` with the pointer over a layer (yes/no).
- [ ] **Step 3:** Commit the findings section (`docs: subsurface phase 1 — the desk's findings (D209)`).

If F1 is **no**, Task 7's "drag bind" step is required; if yes, it is skipped. If F2 is **no**, Task 5 moves `ground` to `level: bottom` and Task 7 re-maps citizens after it (`widgets_restack` pattern). If F3 is **no**, the wheel step of Task 7 binds nothing new and widening is keyboard-only (PageUp/PageDown) — tell the owner.

---

### Task 2: `lib/surface/opening` — the opening's state and target hole

**Files:**
- Create: `shell/lib/surface/opening.luau`
- Test: `tests/unit/run.lua` (new section `surface: opening (D209)`)

**Interfaces:**
- Produces:
  - `M.R = 90` (follow hole radius), `M.SNAP = 40` (snap reach, px from a box's edge), `M.MARGIN = 16` (hole margin round a snapped box), `M.SECTION = 0.4` (section = 40 % of the screen's width and height), `M.CORNER = 18`.
  - `M.MODES = { closed = 0, follow = 1, snapped = 2, section = 3, full = 4 }`
  - `M.state() -> { mode = 0, k = 0, snap = nil, step = 0 }`
  - `M.open(st)` → mode follow, k 1; `M.heal(st)` → mode closed, k 0, snap nil, step 0.
  - `M.near(boxes, p) -> box|nil` — `boxes = { { id = string, x, y, w, h }, … }`; the box whose edge distance to `p` is ≤ `SNAP`, the nearest; a point inside counts as distance 0; ties → the smaller box.
  - `M.move(st, boxes, p)` — in follow/snapped: snaps to `near` (mode snapped, `st.snap = box`) or back to follow; in section/full: no change.
  - `M.widen(st, scr)` / `M.narrow(st, scr)` — follow|snapped → section → full; full → section → (snapped if `st.snap` else follow). `scr = { w, h }`.
  - `M.hole(st, p, scr) -> { x, y, w, h, r }` — the target: follow: a `2R` square centred on `p`, `r = R`; snapped: the box grown by `MARGIN`, `r = CORNER`; section: `SECTION·w × SECTION·h` centred on the snap box's centre (or `p`), clamped on screen, `r = CORNER`; full: `0,0,w,h`, `r = 0`.
  - `M.pack(st, hole) -> a, b, c` — integers < 2^24: `a = x*4096 + y`, `b = w*4096 + h`, `c = mode*1000 + r` (all clamped to 0…4095, `r` to 0…999).
  - `M.unpack(a, b, c) -> { x, y, w, h, mode, r }` (for tests and the scene's mirror).

- [ ] **Step 1: Write the failing tests** — in a `do … end` block with `local OP = require("lib/surface/opening")`:
  - `opening: closed until opened, healed back` — `state().mode == 0`; after `open`, `mode == 1, k == 1`; after `heal`, `mode == 0, snap == nil, step == 0`.
  - `opening: snaps within 40 px, the nearest, back to follow when far` — boxes `{a: 100,100,200,100}`, `{b: 400,100,50,50}`; `move` at `(330,150)` → snapped to `a` (30 px off its right edge); at `(345,150)` → follow (45 px off `a`, 55 off `b`); at `(420,120)` (inside `b`) → `b`.
  - `opening: the hole for each mode` — follow at `(500,400)` → `{410,310,180,180,r=90}`; snapped to `a` → `{84,84,232,132,r=18}`; widen from snapped on `1920×1080` → section `{768×432}` centred on `a`'s centre `(200,150)` clamped to `x = 0, y = 0`; widen again → full `{0,0,1920,1080,r=0}`; narrow twice → snapped again.
  - `opening: pack stays under 2^24 and round-trips` — for a full hole on `4000×3000` and a follow hole at `(-50, 5000)`: every packed value `< 2^24` and `>= 0`; `unpack(pack(...))` equals the clamped hole.
- [ ] **Step 2:** Run `lua5.4 tests/unit/run.lua 2>&1 | tail -5` — expected: the four new tests FAIL (module not found).
- [ ] **Step 3:** Implement `shell/lib/surface/opening.luau` to the interface above (pure, no Pleamar globals; `math` only).
- [ ] **Step 4:** Run `lua5.4 tests/unit/run.lua 2>&1 | tail -3` — expected: all pass, `0 failed`.
- [ ] **Step 5:** Commit `surface: the opening's state and target hole (D209)`.

---

### Task 3: `lib/surface/reveal` — stages without the hub ring

**Files:**
- Modify: `shell/lib/surface/reveal.luau` (remove `GROUPS`, `SOURCES`, `groups`, `pick`, `release`, `RING`, `DEAD`, `LEAVE`, `STEP`, `HUB_MS`, `EXPAND_MS`, `R`; stages become 0 none · 1 faint · 2 open)
- Test: `tests/unit/run.lua` sections `surface: reveal (D208)` and `surface: review fixes (D208)` — replace the ring tests

**Interfaces:**
- Consumes: nothing.
- Produces: `M.DELAY = 250`, `M.OPEN_MS = 350`, `M.IDLE_MS = 6000`; `M.state()`, `M.down(st, now)`, `M.tick(st, now, p)` (stage 1 from `DELAY`, 2 from `DELAY + OPEN_MS`; closes after `IDLE_MS` without pointer movement), `M.up(st, now) -> "tap"|"release"|nil` (unchanged semantics), `M.finish(st)`, `M.close_on(event)` (unchanged list). New: `M.firm(st)` → true once stage 2 has lasted ≥ 300 ms **and** the pointer has moved ≥ 24 px since the down (the gate for keyboard and clicks, Review Focus 3).

- [ ] **Step 1: Write the failing tests** — replace `the hub picks by angle…` and `release cancels, opens or leaves` with:
  - `reveal: two stages, no ring` — after `DELAY + OPEN_MS + 500` the stage is 2 (not 3); `RV.pick == nil` and `RV.GROUPS == nil`.
  - `reveal: firm only after it has been open and the pointer moved` — at stage 2 for 400 ms with the pointer still → `firm == false`; after a 30 px move → `true`; a fresh down → `false`.
  - Keep `a tap is a tap…` (change its `stage, 3` expectation to `2`, drop the anchor asserts), `never outlives its safeguards`, and review I2.
- [ ] **Step 2:** Run the unit tests — expected: the new tests FAIL.
- [ ] **Step 3:** Implement the slimmed module (track `st.down_p` at the first tick and `st.open_at` when stage 2 begins).
- [ ] **Step 4:** Run the unit tests — expected: reveal tests pass. (`surface: logic (D208)` and `surface: scene (D208)` will fail until Tasks 5 and 7; mark them `-- updated in Task 5/7` and leave failing only if the executor runs tasks out of order — in order they are rewritten there.)
- [ ] **Step 5:** Commit `surface: the reveal's stages without the hub ring (D209)`.

---

### Task 4: The shared opening block — `tools/gen-opening.py`

**Files:**
- Create: `tools/gen-opening.py`
- Modify: `shell/mooi-widgets.plm`, `shell/bmo/bmo.plm`, `shell/mooi-viz.plm` (insert empty `// <gen:opening>` / `// </gen:opening>` marker pairs at scene level, before the first `surface`), `tools/gen-surface.py` (emit the same block by importing the generator's `block()`), `.github/workflows/check.yml` and the `check` case of `bin/mooi` (run `python3 tools/gen-opening.py` with the other generators before the diff)
- Test: `tests/unit/run.lua` (new section `surface: the shared opening (D209)`)

**Interfaces:**
- Produces, identical text in every citizen and in `mooi-surface.plm`:
  - events: `event op_a ->`, `event op_b ->`, `event op_c ->`, `event sf_set ->`, `event op_want ->` (declared so `pleamar --say <prog> "emit op_a N"` lands)
  - facts: `fact op_ta = 0`, `fact op_tb = 0`, `fact op_tc = 0` (the last packed values), `fact sf_on = false` (Surface on), `fact sf_bmo = true` (BMO lives below), and rules setting them from the events (`sf_set v`: `sf_on = mod(v, 2) == 1`, `sf_bmo = floor(v / 2) == 1`) — in the scene language's own form for an event with a value (as `wg_marq0` is received today).
  - `spring sg.op = 220, 24`
  - lets: `op_mode = floor(op_tc / 1000)`, `op_r0 = op_tc - op_mode * 1000`, and the target `op_tx/op_ty/op_tw/op_th`: in mode 1 (follow) the `2·90` square on `cursor.x, cursor.y` (90 = `opening.R`, written by the generator from one constant), otherwise unpacked from `op_ta`, `op_tb`.
  - props on `sg.op`: `op_x`, `op_y`, `op_w`, `op_h`, `op_r` following the targets; `op_k` following `if(op_mode > 0, 1, 0)`.
  - `let op_vis = sf_on and op_k > 0.01` and `let sf_below = sf_on` (the gate citizens use).
- `def block() -> list[str]` in `tools/gen-opening.py`; `python3 tools/gen-opening.py` rewrites the text between the markers in each citizen file (refuses, exit 1, if a file lacks the markers).

- [ ] **Step 1: Write the failing test** — `opening block: one text in every program` reads the four `.plm` files, extracts the text between the markers (for `mooi-surface.plm`, between the same markers emitted by `gen-surface.py`), asserts all four are equal, non-empty, contain `spring sg.op = 220, 24`, `event op_a ->`, `cursor.x`, and `90`; and that `tools/gen-opening.py` contains `R = 90` (one constant, the same as `opening.R`: `eq(require("lib/surface/opening").R, 90)`).
- [ ] **Step 2:** Run the unit tests — expected FAIL (no markers).
- [ ] **Step 3:** Write `tools/gen-opening.py`, add the markers, call `block()` from `gen-surface.py`, run `python3 tools/gen-opening.py && python3 tools/gen-surface.py`.
- [ ] **Step 4:** Run `lua5.4 tests/unit/run.lua | tail -3` and `bin/mooi check` — expected: unit test passes; every scene compiles (`pleamar --check`) — the block must compile in all four scenes.
- [ ] **Step 5:** Commit `surface: one opening block shared by every program under the wallpaper (D209)`.

---

### Task 5: `mooi-surface` scene — `ground` and `edge`, the Tear, the old overlay gone

**Files:**
- Modify: `tools/gen-surface.py` (`surface_layers()`: delete the `reveal` surface, `RING_N`, `rv_g*`, `rv_s*`, `rv_pick_*`, `rv_ring`, `rv_t1` and the Pill-in-the-aperture; add `ground` and `edge`; keep `desk`)
- Create: `shell/shaders/tear.wgsl`
- Regenerate: `shell/mooi-surface.plm`
- Test: `tests/unit/run.lua` section `surface: scene (D208)` → rewrite as `surface: scene (D209)`

**Interfaces:**
- Consumes: the opening block (Task 4): `op_x, op_y, op_w, op_h, op_r, op_k, op_mode, op_vis`.
- Produces:
  - `fact sf_fx = 1` (1 Tear, 2 Aperture), `text rv_wall` / `image rv_img` (kept).
  - `surface ground { size: full, full; anchor: top; level: background; reserve: -1; keyboard: none; rate: 60, 20 while calm; open: op_vis }` — draws, clipped to the hole (`clip box { from: op_x, op_y; size: op_w, op_h; corner: op_r }`): the dark subsurface ground (the Aperture shader's `sub` colour + 14 px grid, as one box with `shader: ground…` or plain boxes) and a group `below` that Task 6 fills.
  - `surface edge { size: full, full; anchor: top; level: bottom; reserve: -1; keyboard: none; rate: 60; open: op_vis }` — **no zones**; a group clipped to the hole grown by 40 px, `shader: tear, op_k, op_x, op_y, op_w, op_h, op_r` (or `aperture` when `sf_fx == 2`, with its existing arguments from the hole's centre and `min(op_w, op_h) / 2`), drawing `image rv_img { at: 0, 0; size: edge.width, edge.height; fit: cover }`; transparent inside the hole.
  - `shaders/tear.wgsl`: `fn shade(s: Shader) -> vec4<f32>`; `s.a = (k, x, y, w)`, `s.b = (h, r, 0, 0)` (or Pleamar's argument layout as `aperture.wgsl` reads `s.a`); outside the rounded box: the picture, displaced outward up to 10 px by a seeded value-noise band 6–22 px wide (the ragged lip), lightened 18 % on the lip (the paper's underside), a 14 px inner shadow at the hole's border; inside: alpha 0. `t * t`, never `pow` of a negative.

- [ ] **Step 1: Write the failing tests** (`scene: the opening at the wallpaper, never over windows`):
  - `not plm:find("surface reveal {")`, `not plm:find("level: overlay")` inside the new surfaces (search the `ground`/`edge` blocks), `plm:find("surface ground {")` with `level: background` and `open: op_vis`, `plm:find("surface edge {")` with `level: bottom`, and no `zone` between `surface edge {` and its closing brace.
  - `plm:find("shader: tear")` and `read("shell/shaders/tear.wgsl"):find("fn shade(s: Shader) -> vec4<f32>")`, and the shader has no `pow(`.
  - `image rv_img { at: 0, 0; size: edge.width, edge.height` and still `not plm:find("size: screen.width, screen.height")`.
  - `not plm:find("rv_g0")` (the ring is gone).
- [ ] **Step 2:** Run the unit tests — expected FAIL.
- [ ] **Step 3:** Implement in `gen-surface.py`, write `tear.wgsl`, regenerate.
- [ ] **Step 4:** Run unit tests and `bin/mooi check` — expected PASS; then render check in a scratch copy: `pleamar --scene` a copy with `op_tc = 2018` (snapped, r 18), `op_ta/op_tb` for a 400×240 hole at (700,400) and `sf_on = true`, screenshot with `grim` → the ragged rim over the wallpaper, the dark ground inside. Show the screenshot to the owner (show_image).
- [ ] **Step 5:** Commit `surface: the opening at the wallpaper — ground, edge and the Tear (D209)`.

---

### Task 6: What lives below — hubs, components, the map

**Files:**
- Create: `shell/lib/surface/below.luau`
- Modify: `tools/gen-surface.py` (fill `ground`'s `below` group), `shell/mooi-surface.luau` (data for the hubs and components; presses)
- Test: `tests/unit/run.lua` (new section `surface: below (D209)`)

**Interfaces:**
- Produces (`below.luau`, pure):
  - `M.HUBS = { "apps", "music", "walls", "settings", "notes" }` (`notes` = Notifications), `M.COMPONENTS = { "wifi", "bt", "volume", "bright", "battery", "power" }`.
  - `M.SIZES = { apps = {360, 220}, music = {320, 140}, walls = {360, 120}, settings = {300, 140}, notes = {320, 220} }`, components `{56, 56}` each, 12 px apart.
  - `M.defaults(scr) -> places` — `places = { [id] = { x, y, w, h } }`: hubs centred along an arc through the middle third (`y` from `0.36·h` at the ends to `0.30·h` in the middle, evenly spread across `0.12·w … 0.88·w`), components in one row ending 32 px from the right and 96 px from the bottom, `bmo` home at `{ x = 0.06·w, y = h − 300, w = 160, h = 196 }`.
  - `M.merge(saved, scr) -> places` — saved places kept (clamped fully on screen), missing ids from `defaults`, unknown ids dropped.
  - `M.boxes(places, widgets, bar_h) -> boxes` — the snap list for `opening.near`: every place, plus each widget from `widgets.json` (`{ id = "w:" .. w.id, x = w.x, y = w.y + bar_h, w = w.w, h = w.h }`, skipping widgets with `above == true`).
- Scene: in `ground`'s `below` group, for each hub `k` facts `hb{k}_x/y/w/h`, and its drawing; for each component `cp{k}_x/y`; zones `hbz{k}_{n}`/`cpz{k}` that `emit sb_press(code)` (`code = hub*100 + item` or `900 + component`), `show: op_vis` (a zone in a hidden group is never live).
  - Apps: up to 12 app marks (`text ab{n}` name + icon image from the `apps` service's icon path), the most launched first (the service's own order if it has no count), 4×3 grid.
  - Music: art (`image` from `media` art), title, artist, ‹ ▶/❚❚ › (presses → `playerctl previous|play-pause|next` via `run`), a 1.4 px progress hairline.
  - Wallpapers: 6 newest thumbnails from `walls-index.json` (data folder; thumbs at `~/.cache/mooi/walls` as the picker uses); press → `run("mooi", {"wall", "apply", path})`.
  - Settings: 8 section marks (Bar & Frame, Wallpapers, Widgets, Theme, Islands, Notch, Sound, The Sigil); press → `run("pleamar", {"--say", "mooi", "emit open_settings"})` (page argument only if `emit open_settings` already takes one — check `shell/mooi.luau`; else the plain open).
  - Notifications: the 4 newest from the logic's existing `notices()` data, summary + app; "Clear" → the existing clear path used by the bar (grep `clear` in the notifications code; reuse, do not invent).
  - Components: icon + value (Wi-Fi SSID/off, BT on/off, volume %, brightness %, battery %, power glyph); a press toggles (Wi-Fi `nmcli radio wifi on|off`, BT `bluetoothctl power on|off`), volume/brightness show a 0–100 bar and a wheel over them steps 5 % (`on scroll`), power opens a row of 5 (lock, sleep, log out, restart, shut down) where log out/restart/shut down need a second press within 3 s (fact `pw_arm`).
- Places persist in `surface.json` under `"places"` (the logic's existing save path; `version` unchanged, an older file simply has none).

- [ ] **Step 1: Write the failing tests:** `below: default places are on screen and apart` (1920×1080: every place fully inside, no two hubs overlap, components in one row, right edge at `1920 − 32`); `below: saved places kept and clamped, unknown dropped, missing filled` (saved `apps` at `x = 1900` → clamped to `1920 − 360`; `bogus` dropped; `music` from defaults); `below: boxes include widgets below the bar, skip kept-above ones` (`widgets = { {id="clk-1",x=80,y=68,w=440,h=192}, {id="n",x=0,y=0,w=10,h=10,above=true} }`, `bar_h = 34` → contains `w:clk-1` at `y = 102`, not `w:n`).
- [ ] **Step 2:** Run unit tests — expected FAIL.
- [ ] **Step 3:** Implement `below.luau`; generate the `below` group; wire the logic (place facts on load, data watchers already present for media/audio/battery/network/bluetooth; add `apps` and `files:walls-index.json`; `on("sb_press")`).
- [ ] **Step 4:** Unit tests + `bin/mooi check` pass; scratch render (as Task 5 Step 4) with `op_tc = 4000` (full) shows every hub and component; screenshot shown to the owner.
- [ ] **Step 5:** Commit `surface: what lives below — the hubs, the components, their places (D209)`.

---

### Task 7: `mooi-surface` logic — the opening live

**Files:**
- Modify: `shell/mooi-surface.luau` (replace `show_reveal`, the ring parts of `rv_up`, the `rv_move` handling), `tools/gen-surface.py` (`edge`/`ground` keyboard and the `rv_move` reporter moved onto `edge` — `on change rv_q while op_vis` works on any surface since `cursor.x` is global), `bin/mooi` (`wheel` and a `reveal heal` case), `setup/home/.config/hypr/config/custom/mooi.lua` only if Task 1 F1 = no
- Test: `tests/unit/run.lua` section `surface: logic (D208)` → `surface: logic (D209)`

**Interfaces:**
- Consumes: `opening` (Task 2), `reveal` (Task 3), `below.boxes/merge` (Task 6), the block's events (Task 4).
- Produces:
  - `local CITIZENS = { "mooi-widgets", "mooi-viz", "mooi-bmo" }` — the exact scene names as `pleamar --say` knows them (check `pgrep -a pleamar`; BMO's is the name `bin/mooi` starts him under).
  - `broadcast()` — packs `opening.pack(SF.op, opening.hole(SF.op, SF.ptr, SF.scr))`, sets its own `op_ta/op_tb/op_tc`, and for each citizen runs `pleamar --say <c> "emit op_a <a>"` (then b, c) **only when the packed triple changed** and not for a pure follow move (in follow mode `a`/`b` are not sent — the citizens follow the pointer themselves; only `c` changes).
  - `on("op_want")` → re-sends the current triple to every citizen (a citizen calls `pleamar --say mooi-surface "emit op_want"` on load).
  - `emit sf_set <v>` to each citizen on start, on `settings.json` change, and on `op_want` (`v` = 1 if Surface on + 2 if `surface.bmo_below`; Task 9 adds the setting, until then bit 2 is set).
  - Stage 2 → `opening.open`, `broadcast()`; every `rv_move` → `opening.move(SF.op, boxes, p)`, `broadcast()`; `rv_up` with `release` → `opening.heal` (unless mode full: stays until `rv_esc`/`op_close`), `broadcast()`; safeguards (`close_on`) heal too.
  - `on("op_wheel", v)` → `widen` (v > 0) / `narrow`, `broadcast()`; `bin/mooi wheel N`: if `pleamar --say mooi-surface "get op_vis"` prints `true` → `emit op_wheel N`, else today's path unchanged.
  - Keyboard: `edge` gets `keyboard: exclusive while op_vis and sf_firm` (`fact sf_firm` set from `reveal.firm`), keys: `Tab`/`Shift+Tab` → `emit op_key(1|-1)` (walk `boxes` in reading order, snapping), `Return` → `emit op_key(2)` (press the snapped thing's main action: hub → its first item, component → its toggle, widget → nothing), `Page_Up`/`Page_Down` → `op_wheel(±1)`, `Escape` → `rv_esc`.
  - **Drag bind (only if Task 1 F1 = no):** on open `run("hyprctl", {"keyword", "unbind", "SUPER, mouse:272"})`; on heal, on load, and from `bin/mooi reveal heal` (called by the keeper when `mooi-surface` ends) re-bind with the exact line Hyprland's config uses (`hyprctl keyword bindm "SUPER, mouse:272, movewindow"`); the 0.57 Lua syntax may differ — use what `hyprctl` accepts on this desk and record it.
  - Drag-out from a hub: `on("sb_drag", code)` while open → on its `sb_drop` with the pointer outside the hole → `presence.new(source_of(code), x, y, SF.scr)` (music → `music`, apps → `apps` source added to `lib/surface/sources` only if absent; components → their source names that already exist: `volume`, `battery`, `network`, `bluetooth`), saved and drawn as today's Presences.

- [ ] **Step 1: Write the failing tests:** rewrite `logic: hold Super …` to assert: handlers `rv_down`, `rv_up`, `rv_move`, `rv_esc`, `op_wheel`, `op_want`, `op_key`, `sb_press`, `sb_drop` exist; `require("lib/surface/opening")`; the logic contains `"emit op_a "` and `"emit sf_set "`; `bin/mooi` has `"emit op_wheel"` and a `reveal` case `heal`; the guards (`SF_guard("workspace")`, `SF_guard("focus")`, the title-change line) and `"emit pill_call"` kept. Plus a pure test `opening: a follow move sends nothing to the citizens` exercising the logic's change detector — put the detector in `opening.lua` as `M.changed(prev, a, b, c) -> boolean` returning false when only the pointer moved in follow mode (prev and next `c` equal, mode 1).
- [ ] **Step 2:** Run unit tests — expected FAIL.
- [ ] **Step 3:** Implement the logic, `bin/mooi` cases, and the regenerated scene.
- [ ] **Step 4:** Unit tests + `bin/mooi check` pass; live smoke on the running desk with Surface on (owner's settings restored after): `pleamar --say mooi-surface "emit rv_down"`, wait 1 s → `get op_vis` = `true`; `emit rv_move <x*10000+y>` onto the clock widget's centre → `get op_tc` = `2018`; `emit op_wheel 1` → `get op_tc` = `3018`; `emit rv_up` → `get op_vis` = `false` within 0.6 s.
- [ ] **Step 5:** Commit `surface: the opening live — follow, snap, widen, heal, the keyboard path (D209)`.

---

### Task 8: `mooi-widgets` and `mooi-viz` as citizens

**Files:**
- Modify: `shell/mooi-widgets.plm`, `shell/mooi-widgets.luau`, `shell/mooi-viz.plm`, `shell/mooi-viz.luau`
- Test: `tests/unit/run.lua` (new section `surface: citizens (D209)`)

**Interfaces:**
- Consumes: the block (`op_x … op_vis`, `sf_on`), `op_want`.
- Produces:
  - Widgets: a per-widget field `above` (bool, default false; validated where `widgets.json` entries are validated) and a scene fact per drawn widget slot `w{n}_above` (or the existing per-widget record field, read in the loop as `w.above`).
  - Every widget's drawing and zones sit in `group { show: not sf_on or w.above or editing or wg_desk or op_vis; group { clip box { … the hole … }; show-clip only when sf_on and not w.above and not editing and not wg_desk } … }` — the exact nesting chosen so that an above/edited widget is unclipped; **no `z:` inside the loop's children** (de53b69).
  - Zones of below-widgets are live only while `op_vis` (they are inside the hidden group otherwise).
  - Drag-out: while `op_vis` and not editing, `on drag` of a widget's body zone records the drag; `on release` with the pointer outside the hole (`cursor.x/y` vs `op_x…op_h`) → `emit wg_keep(slot * 10000000 + x*4096... )` packed as `slot, x, y` in two emits (≤ 2^24) → the logic sets `above = true`, moves the widget's top-left to the drop point clamped fully on screen and below the bar reserve (Review Focus 4), saves `widgets.json`. A press-drag of an above widget released inside an open hole sets `above = false`.
  - On load each logic runs `run("pleamar", {"--say", "mooi-surface", "emit op_want"})`.
  - `mooi-viz` lanes: the same gate (clip to the hole unless their widget is above), driven by the same block.

- [ ] **Step 1: Write the failing tests:** `citizens: widgets hide below and clip to the hole` — `mooi-widgets.plm` contains the markers, `op_vis`, `clip box { from: op_x, op_y; size: op_w, op_h; corner: op_r }`, `w.above` (or the chosen name), and the `for` loop body has no `z:`; `mooi-widgets.luau` and `mooi-viz.luau` contain `"emit op_want"`; a pure test of the clamp: put `keep_at(w, x, y, scr, bar_h)` in `shell/lib/widgets.luau` if that module exists (else the closest pure widgets library — check `shell/lib/`), asserting a 440×192 widget dropped at `(1900, 1070)` on 1920×1080 with `bar_h = 34` lands at `(1480, 1080 − 34 − 192)` (widget coordinates are below the bar reserve) and `above == true`.
- [ ] **Step 2:** Run unit tests — expected FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Unit tests + `bin/mooi check` pass; live: with Surface **off** → `pleamar --say mooi-widgets get op_vis` is `false` and widgets are visible (screenshot equals a `main` screenshot of the same region); Surface **on**, no opening → a screenshot of the clock widget's box shows only wallpaper; `rv_down` + `rv_move` onto it → the box shows the widget inside the torn hole. Show both screenshots to the owner.
- [ ] **Step 5:** Commit `widgets: citizens of the subsurface — below until opened, kept above when dragged out (D209)`.

---

### Task 9: BMO's home, the settings, the stand-down

**Files:**
- Modify: `shell/bmo/bmo.plm`, `shell/bmo/bmo.luau`, `shell/lib/config.luau` (defaults/validation), `tools/gen-settings.py` (SETTERS + the Surface rows in MODULES), `shell/lib/setters.luau` (generated/in sync), `shell/mooi-settings.plm` (generated parts only, via the generator)
- Test: `tests/unit/run.lua` (extend `surface: citizens (D209)`; config section)

**Interfaces:**
- Produces:
  - Settings: `surface.effect` ∈ `"tear" | "aperture"` (default `"tear"`), `surface.bmo_below` bool (default `true`). `mooi-surface` maps `effect` to `sf_fx` (1/2).
  - BMO: his body drawn inside the hole when `sf_on and sf_bmo and at_home` (`at_home` = not `above`, not `on_bar`, not walking — use his existing state names; read `bmo.luau` for them), otherwise as today. His zones follow the same gate. On load: `emit op_want`. `mooi-surface` now sets bit 2 of `sf_set` from `surface.bmo_below`.
  - Settings page (Bar & Frame → The Sigil → Surface): rows "Opening effect: Tear / Aperture" and "BMO lives below: on/off", next to the existing on switch and delay.
  - Stand-down (Review Focus 2/5): every citizen's block treats a missing `mooi-surface` as closed — `mooi-surface` sends `sf_set` on start; `bin/mooi`'s keeper, when it sees `mooi-surface` end, runs `mooi reveal heal`, which sends `emit op_c 0` to each citizen (and re-binds the drag bind if Task 7 unbound it).

- [ ] **Step 1: Write the failing tests:** config: `defaults().surface.effect == "tear"`, `bmo_below == true`, `validate({surface={effect="nonsense"}})` → `"tear"`; setters: the existing SETTERS/setters sync test passes with the two new keys; `bmo.plm` has the markers and `op_vis`; `bmo.luau` has `"emit op_want"`; `bin/mooi` `reveal heal` sends `"emit op_c 0"`.
- [ ] **Step 2:** Run unit tests — expected FAIL.
- [ ] **Step 3:** Implement; run `python3 tools/gen-settings.py`, `python3 tools/gen-opening.py`, `python3 tools/gen-surface.py`.
- [ ] **Step 4:** Unit tests + `bin/mooi check` pass; live: kill `mooi-surface` during an open opening → within 1 s `pleamar --say mooi-widgets get op_vis` = `false`; the keeper respawns it and `sf_on` is re-sent.
- [ ] **Step 5:** Commit `surface: BMO's home below, the opening's settings, citizens stand down without it (D209)`.

---

### Task 10: The live suite and the budget

**Files:**
- Modify: `tests/surface.sh` (replace the `Surface (D208): hold Super — the reveal` and `a Presence left behind…` parts)

- [ ] **Step 1:** Write the checks (each via `pleamar --say`, settings and `surface.json` and `widgets.json` restored byte for byte — add `widgets.json` to the existing backup/restore):
  - a quick tap opens nothing; held 1.2 s → `op_vis` true in `mooi-surface` **and** in `mooi-widgets`;
  - no surface of `mooi-surface` at overlay: `hyprctl layers -j` lists its surfaces only at levels 0 (background) and 1 (bottom) while open;
  - `rv_move` onto the clock widget → `op_tc` = 2018 in both programs; `op_wheel 1` → 3018; `op_wheel 1` → 4000; `rv_up` with full → still open; `rv_esc` → closed;
  - a widget kept above: emit the drag-out pair for slot 0 → `jq '.widgets[0].above' widgets.json` = `true`; drag back in → `false`;
  - a Presence from the Music hub dragged out → `jq '.presences[-1].source'` = `music`;
  - `mooi-widgets` restarted while open → after 3 s its `op_tc` equals `mooi-surface`'s;
  - `mooi-surface` killed while open → widgets' `op_vis` false within 1 s;
  - budget: `pleamar --report mooi-surface --seconds 4` while open, compose + paint < 1.0 ms; same for `mooi-widgets`;
  - idle: with the opening closed, `hyprctl layers -j` shows no `ground`/`edge` surface.
- [ ] **Step 2:** Run `tests/surface.sh` with Surface on — expected: all pass; `SHOTS=$SCRATCH/shots` keeps screenshots of follow, snapped, section, full.
- [ ] **Step 3:** Commit `tests: the subsurface live — opening, citizens, kept above, stand-down, budget (D209)`.

---

### Task 11: Docs, decision, the owner's real-key check

**Files:**
- Modify: `docs/DECISIONS.md` (or the project's decision log — find where D208 is recorded) with D209; `docs/TODO.md` (phase 2–5 of the subsurface, the light-through-the-skin idea under phase 3); `README`/docs page that describes Surface (find with `grep -rl "Surface" docs/ README*`)

- [ ] **Step 1:** Write D209: what changed (opening at the wallpaper, citizens, Tear), the Task 1 findings, and what stays off by default.
- [ ] **Step 2:** Run the full gate: `bin/mooi check`, `lua5.4 tests/unit/run.lua | tail -2`, `tests/surface.sh` — all green; then `setup/capture.sh` (required before every mooi commit; it refuses personal data).
- [ ] **Step 3:** Commit `docs: the subsurface phase 1 (D209)` and push to `origin main` after the owner has seen the screenshots.
- [ ] **Step 4:** With the owner: switch Surface on, hold Super over the desktop, roam, snap onto a widget and a hub, scroll to widen, click a hub item while holding, drag a widget out, let go; then Super+Return and Super+W to confirm no opening lingers. Record the outcome in D209.

## Findings (Task 1, 2026-11-08, with the owner)

- **F1 — no.** A click while holding Super never reaches a layer zone at `background` or `bottom`: Hyprland's
  `SUPER + mouse:272` (window drag, `bind.lua`) takes it. → Task 7's drag-bind step is **required**.
- **F2 — yes.** A `level: background` surface mapped after `mooi-desk` draws above the wallpaper (the probe's box
  showed over it). → `ground` stays at `background`. (Probe gotcha: a scene's first surface with
  `size: full, full` came out 1920×84 — give such scenes a stub first surface or explicit sizes.)
- **F3 — yes.** Super + wheel runs `mooi wheel N` (the bar switched workspace), whatever layer is under the
  pointer. → Task 7 routes `mooi wheel` to `mooi-surface` while an opening is open.
- Tooling: a scene started from Claude's sandboxed shell is killed when the command ends; start probes through
  Hyprland: `hyprctl dispatch "hl.dsp.exec_cmd(\"…\")"`.
