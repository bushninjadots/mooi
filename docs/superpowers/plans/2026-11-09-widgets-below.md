# The widgets below — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything under the wallpaper is a real mooi widget: four new widget kinds, a Launch grid, a default
set placed once, Presences migrated to widgets kept above, the Overview as edit mode, and mooi-surface's own
hubs, components and Presence layer removed.

**Architecture:** The new kinds are *lanes* in mooi-widgets (one each, like Weather, D141): their sizes and options
in `lib/widgets`, their drawings in a new `shell/ui/wbelow.plm`, their lane groups from `tools/gen-wlanes.py`, their
feeds and presses in a new logic module `shell/lib/wbelow_feed.luau` (mooi-widgets.luau is near Lua's 200 locals).
Pure decisions (seeding, arranging, migration, the Launch grid) live in `shell/lib/wbelow.luau`. mooi-surface keeps
only the opening and its ground/edge/Overview canvas.

**Tech Stack:** Pleamar scenes (language 0.9), Luau logic, Python generators, Lua 5.4 unit tests.

**Spec:** `docs/superpowers/specs/2026-11-09-widgets-below-design.md`

## Global Constraints

- New kinds and layouts (min · default): `notices` `stack` 280×200 · 360×260; `wallpapers` `strip` 300×110 · 420×140;
  `settings` `pages` 260×130 · 320×170; `controls` `row` 420×72 · 452×80, `column` 72×420 · 80×452; `launch` gains `grid`.
- Options: `notices.rows` 3–6 (4); `controls.show` the six (all on), `controls.power_confirm` (true); every kind `plate`, `adapt`, `behind`.
- Settings marks and tabs: Theme & colour 1, Bar & Frame 3, Wallpapers 9, Widgets 10, Sound 12, Power 13, BMO 11, The Subsurface 21.
- Default set: Now Playing (sleeve), Visualiser, Launch (grid), Clock (digital), Calendar, Weather, Notices, Wallpapers, Settings, Controls (row); only missing kinds; once (`below_seeded = true`).
- Widget limit 12 → 16.
- Migration map: music→nowplaying, clock→clock, calendar→calendar, weather→weather, notifications→notices,
  volume/network/bluetooth/battery→controls, resources→system; else dropped with a log line.
- Every pleamar path `require("lib/x")` with slashes; never write settings.json outside its policy.

## Review Focus

- Seeding on a screen too small for the set: every seeded widget must still be wholly on screen (clamped, may overlap) — test in Task 2.
- A widgets.json already holding 16: seeding/migration add nothing, log, and never drop the owner's widgets — test in Task 2.
- Migration run twice (restart mid-way): no duplicate widgets — test in Task 2 (`migrate` idempotent via the flag and single-kind merge).
- Surface off: no seeding, no edit-mode toggling from the Overview — test in Task 4 (logic strings).
- The Overview healed while a widget drag is held: edit mode leaves cleanly (`wg_edit 0` drops gestures, existing) — covered by the existing handler; asserted in Task 5.

---

### Task 1: The kinds in lib/widgets

**Files:** Modify `shell/lib/widgets.luau`; Test `tests/unit/run.lua` (new section "widgets below (D215)").

**Interfaces — Produces:** `W.KIND_NUM.notices = 12, wallpapers = 13, settings = 14, controls = 15`; `W.MAX = 16`;
`W.KIND_LAYOUTS.launch = { "shelf", "column", "grid" }`; `W.LAYOUTS.stack/strip/pages/row/column2/grid` (controls'
column layout is named `ccolumn` to stay distinct from Launch's `column`); `W.KIND_MAX` 1 for each new kind;
`W.ADD_ORDER` gains the four; `W.OPTIONS` for the four.

- [ ] Step 1: tests — `W.add(doc, "notices", scr)` gives a widget of layout `stack` at 360×260; each new kind refuses a
  second; `W.MAX == 16`; `W.set_layout(doc, id, "grid")` on a launch widget works; `notices.rows` clamps to 3–6.
- [ ] Step 2: run, see them fail. Step 3: implement. Step 4: run `lua5.4 tests/unit/run.lua`, all pass. Step 5: commit.

### Task 2: The pure decisions — lib/wbelow

**Files:** Create `shell/lib/wbelow.luau`; Modify `shell/lib/surface/below.luau` (export `arrange`); Test `tests/unit/run.lua`.

**Interfaces — Produces:**
- `below.arrange(items: {{id,w,h}}, scr: {w,h}, layout: string) -> { [id] = {x,y,w,h} }` — the arc/row/grid/calm
  maths for any list, clamped on screen.
- `wbelow.DEFAULT_SET` (kind, layout pairs, spec order); `wbelow.seed(doc, scr, layout) -> doc, added: number, problems`
  (only missing kinds, `above = false`, sets `doc.below_seeded = true`; a seeded doc is returned unchanged).
- `wbelow.arrange_all(doc, scr, layout) -> doc` (every widget not kept above, laid out by `below.arrange`).
- `wbelow.MIGRATE` map; `wbelow.migrate(presences, doc, scr) -> doc, problems` (adds kept-above widgets centred on
  each Presence; one per single kind; sets `doc.migrated_presences = true`; a migrated doc is returned unchanged).
- `wbelow.grid_apps(list, counts, q, n)` — moved from `below.apps` (same ranking, D214 tests move with it).
- `wbelow.SETTINGS` — moved from `below.SETTINGS`.
- [ ] Steps: tests first for each function including the Review Focus cases (small screen 1366×768, full doc of 16,
  migration twice), fail, implement, pass, commit.

### Task 3: The drawings and lanes

**Files:** Create `shell/ui/wbelow.plm` (components `Notices`, `Walls`, `Pages`, `Controls`); Modify
`shell/ui/wextra.plm` (Launch `lay == 2`: a 4×3 grid of marks and names, the typed filter shown), `tools/gen-wlanes.py`
(lanes `nc`, `wp`, `pg`, `ct`; `PO` to po15), `shell/mooi-widgets.plm` (import, models `nc max 6 { title, app, ago,
act, a1 }`, `wp max 6 { thumb: image 96, 80; on }`, facts for controls (`ct_wifi … ct_bat_frac`, `ct_pw_open`,
`ct_pw_arm`, `ln_q`), fades po12–po15, the add menu at 16 chips, permissions (services network, bluetooth,
brightness, battery, audio; run mooi, nmcli, bluetoothctl, systemctl, hyprctl, pleamar)); Test `tests/unit/run.lua`.

**Interfaces — Produces (events the scene emits):** `nc_go(row*10+what)` (0 default · 1 action · 9 dismiss; row 0-based;
90 = clear), `wp_go(i)`, `pg_go(i)`, `ct_go(k)` (1 wifi … 6 power), `ct_wheel(k*10+up)`, `ct_pw(n)` (1–5).
- [ ] Steps: tests asserting the components, the four lanes and the events exist; regenerate (`python3 tools/gen-wlanes.py`);
  `pleamar --check shell/mooi-widgets.plm` ok; tests pass; commit.

### Task 4: The feeds, seeding, migration, edit mode — logic

**Files:** Create `shell/lib/wbelow_feed.luau` (`return function(ctx)`: watches nexus-feed.json, walls-index.json,
network, bluetooth, audio, brightness, battery, apps; fills the models/facts; handles the Task 3 events; launch grid
counts and `ln_q`); Modify `shell/mooi-widgets.luau` (require it; LANE map gains the four; on `sf_set` with Surface on:
seed once via `wbelow.seed` with `settings.surface.layout`; migrate once from `surface.json` via `wbelow.migrate`;
events `wg_arrange` (re-arrange, through history) and `ln_type(code)`); Test `tests/unit/run.lua`.
- [ ] Steps: tests on the strings that wire it (seed guarded by Surface on and the flag; migration flag; `wg_arrange`
  pushes history); implement; `lua5.4` parse; tests pass; commit.

### Task 5: mooi-surface keeps only the opening

**Files:** Modify `tools/gen-surface.py`, `shell/mooi-surface.luau`, `shell/lib/surface/below.luau` (keep `arrange`,
`boxes` for widgets and BMO only), `tools/gen-settings.py` + regenerate, `shell/lib/config.luau` (retire the removed
keys like D214's), `tests/surface.sh`, `tests/unit/run.lua` (D209–D214 tests of removed things deleted or rewritten).
- Remove: hubs, components, power row, typing, seek, places, usage, `sf_edit/sf_reset/sf_undo`, handles, the desk
  layer and `pp_*`/`ed_*`, Overview UNDO/RESET; mooi-surface rewrites surface.json without `presences`/`places` once
  widgets.json says `migrated_presences`.
- Add: entering full emits `wg_edit 1` to mooi-widgets, healing full emits `wg_edit 0`; `op_type` forwarded as `ln_type`;
  the settings button "Re-arrange" emits `wg_arrange` to mooi-widgets.
- [ ] Steps: update tests first (removed names absent; forwarders present); implement; regenerate; check; commit.

### Task 6: Verify, render, record

- [ ] `bin/mooi check` green; previews of the four new kinds (logic-free copy at overlay, `--say` data) and the Launch grid;
  DECISIONS D215, TODO, memory; merge to main; push.
