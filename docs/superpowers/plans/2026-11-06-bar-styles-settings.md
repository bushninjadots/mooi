# Bar & Frame: styles, settings and per-module looks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One Settings page for everything about the bar, five logical styles (Steel removed, Hairline added) whose edges agree with the frame, islands that can attach to the frame without humps, and a per-module look (colour, fill, rounding, outline, glow, display, width).

**Architecture:** Settings stay one validated document (`lib/config`); styles stay presets in `lib/style`; `lib/chassis` gains the attach geometry and per-piece looks; mooi-frame draws floating plates as their own bodies (so each can differ) and joined pieces in the band's tiles; the generated settings window (`tools/gen-settings.py`) gets a Bar & Frame page with folding sections and a per-module Look card driven by one new event.

**Tech Stack:** Pleamar 0.7.11 scenes + Lua logic, Python generators, POSIX sh live tests, Lua 5.4 unit tests.

**Spec:** `docs/superpowers/specs/2026-11-06-bar-styles-settings-design.md` (D166); parent `2026-11-06-bar-redesign-design.md` (D164)

## Scope notes (decided here, against the spec where noted)

- **Content colour** (spec §4: "content colour follows the module's colour") is deferred to the
  module component contract (D164 stage 4), where every module is re-rendered; here a module's colour
  tints its plate, outline and glow, and the content keeps the theme's ink so it stays legible.
- **`display` and `width`** are stored, validated and editable here; the bar applies them with density
  in stage 4.

## Global Constraints

- Requires use slash paths; no `goto`; Pleamar ignores `show:` on shapes inside a `body` — hide shapes by zero size or by keeping them out of the body.
- `settings.json` only through `lib/settingsfile`; setter codes are append-only (gen-settings checks).
- Generated files (`shell/mooi-frame.plm` frame block, `shell/mooi-settings.plm`, `shell/lib/settings_index.luau`) change only through their generators, committed together; CI fails on drift.
- One outline width everywhere; no second line; with the frame on the bar and frame are one body.
- After a logic change: `bin/mooi session`, no new `runtime error` in `~/.local/state/mooi/mooi.log`.
- Live tests restore `settings.json` byte for byte and never move the pointer.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; `setup/capture.sh` before a pushed commit.

## Review Focus

1. A settings file with `bar.style = "steel"` loads as `instrument` and the bar looks the same (every finer value kept).
2. A module look with a bad value (`fill = "chrome"`, `colour = "#12"`) falls back to `style` with a note; the rest of the file is kept.
3. A group (`settings+resources`) styled through either member: the look is stored on and read from its first module only.
4. `frame.islands = attach` with the frame off behaves as `float` (no band to attach to).
5. Folding a section and reopening Settings: the window's height and scrolling still reach the last row.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `shell/lib/config.luau` | `bar.style` without steel + migration; `frame.islands`; `bar.modules.<id>` look keys |
| `shell/lib/style.luau` | presets: Instrument, Glass, Floating, Hairline, Minimal; the frame's line follows the style |
| `shell/lib/modlook.luau` (new) | pure: a module's effective look (style defaults + overrides, group head), as numbers the scene draws |
| `shell/lib/chassis.luau` | attach geometry; per-piece look fields |
| `tools/gen-frame.py` → `shell/mooi-frame.plm`, `shell/mooi-frame.luau` | floating plates as own bodies with per-slot look; joined pieces in the band |
| `tools/gen-settings.py` → `shell/mooi-settings.plm`, `shell/lib/settings_index.luau` | Bar & Frame page, folds, Look card, renames |
| `shell/mooi-settings.luau` | the Look card's event; fold state; open-at-module |
| `shell/mooi.luau` | edit mode: "Look…" opens Settings at the selected module |
| `tests/unit/run.lua`, `tests/chassis.sh` | tests |

---

### Task 1: Schema — styles, frame.islands, module looks, steel migration

**Files:** Modify `shell/lib/config.luau`; Test `tests/unit/run.lua` (section "config")

**Interfaces:**
- Produces: `bar.style ∈ {instrument, glass, floating, hairline, minimal}` (default `instrument`);
  `frame.islands ∈ {float, attach}` (default `float`); per module id in `barlayout.ORDER`:
  `bar.modules.<id>.colour` (text: `style` | role name in `ferro.ROLES` | `#rrggbb` | `wallpaper`, default `style`),
  `.fill ∈ {style, solid, tinted, glass, none}`, `.rounding ∈ {style, square, soft, round, pill}`,
  `.outline ∈ {style, none, accent}`, `.glow ∈ {off, soft, strong}` (default `off`),
  `.display ∈ {icon, icon+value, label+value}` (default `icon+value`), `.width ∈ {fit, fixed}` (default `fit`).

- [ ] **Step 1: Failing tests**

```lua
test("styles: steel is gone; a file on steel keeps its look as instrument", function()
    local s, _, notes = config.validate({ bar = { style = "steel", surface = "mech", outline_colour = "accent", shadow = "medium" } })
    eq(s.bar.style, "instrument"); eq(s.bar.surface, "mech", "finer values kept"); eq(s.bar.outline_colour, "accent")
    local said = false; for _, n in ipairs(notes) do if n:find("steel", 1, true) then said = true end end
    eq(said, true, "the move is noted")
    eq(config.validate({ bar = { style = "hairline" } }).bar.style, "hairline")
end)
test("frame.islands: float by default, attach when chosen", function()
    eq(config.defaults().frame.islands, "float"); eq(config.validate({ frame = { islands = "attach" } }).frame.islands, "attach")
end)
test("module looks: defaults are the style's, bad values fall back with a problem", function()
    local d = config.defaults().bar.modules.clock
    eq(d.colour, "style"); eq(d.fill, "style"); eq(d.rounding, "style"); eq(d.outline, "style"); eq(d.glow, "off")
    eq(d.display, "icon+value"); eq(d.width, "fit")
    local s, p = config.validate({ bar = { modules = { clock = { fill = "chrome", colour = "#12", rounding = "pill" } } } })
    eq(s.bar.modules.clock.fill, "style"); eq(s.bar.modules.clock.colour, "style"); eq(s.bar.modules.clock.rounding, "pill"); eq(#p, 2)
    eq(config.validate({ bar = { modules = { clock = { colour = "#e07b2e" } } } }).bar.modules.clock.colour, "#e07b2e")
    eq(config.validate({ bar = { modules = { clock = { colour = "ember" } } } }).bar.modules.clock.colour, "ember")
end)
```

- [ ] **Step 2: Run** `lua5.4 tests/unit/run.lua --filter "steel"` (and "frame.islands", "module looks") — Expected: FAIL
- [ ] **Step 3: Implement**: enum changes and the per-module rows in the loop at `config.luau:501`; `colour` validated by a function (style · wallpaper · `ferro.ROLES` name · `^#%x%x%x%x%x%x$`); before validation, `bar.style == "steel"` becomes `"instrument"` with a note.
- [ ] **Step 4: Run** the filters and the full suite — Expected: PASS, `0 failed`
- [ ] **Step 5: Commit** `config: Hairline in, Steel out (migrated), frame.islands, module looks (D166)`

---

### Task 2: Presets and the edge rule

**Files:** Modify `shell/lib/style.luau` (`BAR_PRESETS`, `facts`), `tools/gen-frame.py` (`BODY` border); regenerate `shell/mooi-frame.plm`; Test `tests/unit/run.lua`

**Interfaces:**
- Produces: `style.BAR_PRESETS` = the five rows of spec §3 table, in order instrument, glass, floating, hairline, minimal (hairline: `bar.surface = clear, bar.frame = line, bar.outline_width = 1, bar.outline_colour = accent, bar.shadow = off, bar.pill = underline, bar.ground = clear, bar.rail = false, bar.accents = false, bar.opacity = 100`).
- The frame's border becomes `if(bar_frame < 0.5 and st_frame_edge < 1.5, st_owidth, 0)` in every state (band or not): the style's outline decides whether there is a line; `frame.edge` chooses plain or neon, or none.

- [ ] **Step 1: Failing tests**

```lua
test("presets: five styles, hairline is an accent line with no fill, steel is not one", function()
    local st = require("lib/style")
    local names = {}; for _, p in ipairs(st.BAR_PRESETS) do names[#names + 1] = p.name end
    eq(table.concat(names, ","), "instrument,glass,floating,hairline,minimal")
    local s = config.defaults(); st.apply_preset(s, st.BAR_PRESETS, "hairline")
    eq(s.bar.surface, "clear"); eq(s.bar.frame, "line"); eq(s.bar.outline_width, 1); eq(s.bar.outline_colour, "accent")
    eq(st.preset_index(s, st.BAR_PRESETS), 3)
end)
test("edges: a style without an outline gives the frame no line either", function()
    local f = io.open("shell/mooi-frame.plm"); local plm = f:read("a"); f:close()
    assert(plm:find("border: if(bar_frame < 0.5 and st_frame_edge < 1.5, st_owidth, 0), fnec", 1, true))
end)
```

- [ ] **Step 2: Run** — Expected: FAIL
- [ ] **Step 3: Implement** the presets; change `BODY`'s border in `gen-frame.py`; regenerate; update the earlier "one width everywhere" test's expectation if it names the old expression.
- [ ] **Step 4: Run** unit suite, `pleamar --check shell/mooi-frame.plm` — Expected: PASS / ok
- [ ] **Step 5: Commit** `style: five presets, and the frame's line follows the style (D166)`

---

### Task 3: Module looks — `lib/modlook`

**Files:** Create `shell/lib/modlook.luau`; Test `tests/unit/run.lua` (section "modlook")

**Interfaces:**
- Consumes: validated settings; `lib/ferro` roles table (`{ role = {r,g,b} }`); `lib/barlayout` groups (`"a+b"` entries in `bar.left/center/right`).
- Produces:
  - `modlook.head(settings, id) -> string`: the group's first module for any member, else `id`.
  - `modlook.of(settings, id, roles) -> { fill = 0..4, r = number, outline = 0|1|2, glow = 0|1|2, colour = {r,g,b} | nil }`
    where fill: 0 solid · 1 tinted · 2 glass · 3 none · 4 style-default resolved from `bar.surface`
    (solid/mech → 0, glass/blur → 2, clear → 3); `r`: style → `bar.radius`, square 0, soft 4, round 10,
    pill = half the bar height; outline: style → `bar.frame == "line"` and 1 or 0, none 0, accent 2;
    colour: nil for `style`, the role's colour, the parsed hex, or `roles.primary` for `wallpaper`.

- [ ] **Step 1: Failing tests**

```lua
local ML = require("lib/modlook")
test("modlook: style means the bar's own; overrides win; a group is styled by its head", function()
    local s = config.validate({ bar = { radius = 7, height = 24, surface = "glass", frame = "line",
        left = { "settings+resources", "weather" }, modules = { settings = { fill = "solid", rounding = "pill", colour = "ember" } } } })
    local roles = { ember = { r = 0.9, g = 0.5, b = 0.2 }, primary = { r = 0.5, g = 0.8, b = 0.7 } }
    eq(ML.head(s, "resources"), "settings", "a member's look is its head's")
    local l = ML.of(s, "resources", roles)
    eq(l.fill, 0); eq(l.r, 12, "pill = half the height"); eq(l.colour.r, 0.9)
    local w = ML.of(s, "weather", roles)
    eq(w.fill, 2, "glass from the bar's surface"); eq(w.r, 7); eq(w.outline, 1); eq(w.colour, nil)
end)
```

- [ ] **Step 2: Run** — FAIL (module missing)
- [ ] **Step 3: Implement** `lib/modlook.luau` (pure).
- [ ] **Step 4: Run** — PASS; suite `0 failed`
- [ ] **Step 5: Commit** `modlook: a module's effective look`

---

### Task 4: The chassis — attach, and per-piece looks

**Files:** Modify `shell/lib/chassis.luau`; Test `tests/unit/run.lua` (section "chassis")

**Interfaces:**
- Consumes: `modlook.of` (Task 3).
- Produces: `chassis.look(s)` gains `attach = (s.frame.islands == "attach" and band and mode == "islands")`;
  with `attach`, `top_band = top` (the band reaches the islands' top), `top_room = 0`, and island pieces
  are `{ x = ix - 3, y = -40, w = iw + 6, h = foot + 40, r = 0, k = 0, j = true }`.
  `chassis.pieces(geo, look, looks)` takes optional `looks` = `{ [slot] = modlook }` keyed by island
  index (bar-geo `islands[i].id`, which bar.luau now writes as the frame's module id) and copies `fill`,
  `outline`, `glow`, `colour` onto floating island pieces and their `r` onto `p.r`.

- [ ] **Step 1: Failing tests**

```lua
test("attach: the band comes down to the islands' top and they hang from it, one body", function()
    local s = config.validate({ bar = { mode = "islands", rail = false, offset = 0 }, frame = { on = true, islands = "attach", band = 2 } })
    local l = chassis.look(s)
    eq(l.attach, true); eq(l.top_band, 8, "band to the row's top: gaps are recesses, not tabs"); eq(l.top_room, 0)
    local p = chassis.pieces({ islands = { { x = 12, w = 100 } } }, l)
    eq(p[1].y, -40); eq(p[1].y + p[1].h, 32, "one foot"); eq(p[1].j, true)
    local off = chassis.look(config.validate({ bar = { mode = "islands" }, frame = { on = false, islands = "attach" } }))
    eq(off.attach, false, "no frame, nothing to attach to")
end)
test("chassis: a floating island carries its own look", function()
    local l = L()
    local p = chassis.pieces({ islands = { { x = 12, w = 100, id = "weather" } } }, l, { [1] = { fill = 0, r = 12, outline = 2, glow = 1, colour = { r = 1, g = 0, b = 0 } } })
    eq(p[1].r, 12); eq(p[1].fill, 0); eq(p[1].outline, 2); eq(p[1].glow, 1); eq(p[1].colour.r, 1)
end)
```

- [ ] **Step 2: Run** — FAIL
- [ ] **Step 3: Implement**; `bar.luau` adds `id = f.id` to each `islands` entry it writes (the frame's first module id; read `out.frames` entries for their id field, or the first id of the group).
- [ ] **Step 4: Run** — PASS; suite `0 failed`
- [ ] **Step 5: Commit** `chassis: islands attach to the frame, and each carries its own look`

---

### Task 5: The frame draws each floating plate its own way

**Files:** Modify `tools/gen-frame.py`, `shell/mooi-frame.luau`; regenerate `shell/mooi-frame.plm`; Test `tests/unit/run.lua`

**Interfaces:**
- Consumes: Task 4 pieces; `modlook.of`; `ferro.resolve` roles (already painted in the frame).
- Produces: per slot facts `pf{i}` (fill 0–3), `po{i}` (outline 0–2), `pg{i}` (glow 0–2), `pc{i}_r/g/b`
  (colour; `-1` red = theme), `pj{i}` (bool joined). Joined slots (`pj`) stay inside the band tiles'
  bodies (as now). Floating slots are drawn by a new generated group per strip (top strip only) of 20
  bodies, one per slot, each: `color: mix(fcol, pc, if(pc_r >= 0, tint, 0))` with tint 0.35 for tinted and
  1 for solid, `glass` when `pf == 2`, opacity 0 when `pf == 3`, `border: if(po > 0.5, st_owidth, 0)`
  in `fnec` (or `fl.phos` for accent), glow by `pg`; a floating slot's box is degenerate (`size: 0, 0`)
  inside the band tiles so it is drawn once.

- [ ] **Step 1: Failing test** `"floating plates are drawn by their own bodies with their own look"`: the plm contains `body {` blocks with `pf0`, `po0`, `pc0_r`, and the tile box for slot 0 has size `if(pj0, pw0, 0)`.
- [ ] **Step 2: Run** — FAIL
- [ ] **Step 3: Implement** generator + logic (logic computes looks with `modlook.of` for each island id and writes the facts).
- [ ] **Step 4: Verify** `pleamar --check`, unit suite, `bin/mooi session` + log clean; a screenshot with `bar.modules.weather = { fill = "solid", colour = "ember", rounding = "pill" }` set temporarily (restored after) shows only the weather island changed.
- [ ] **Step 5: Commit** `frame: each floating plate drawn with its own fill, colour, rounding, outline and glow`

---

### Task 6: Settings — the Bar & Frame page

**Files:** Modify `tools/gen-settings.py`; regenerate `shell/mooi-settings.plm`, `shell/lib/settings_index.luau`; Modify `shell/mooi-settings.luau` (fold state, resets); Test `tests/unit/run.lua`

**Interfaces:**
- Produces: `SECTIONS` without pages Bar, Layout, Frame, Workspaces, Media; a page
  `("Bar & Frame", "Bar & Frame", "Everything about the bar and the frame round the screen: four choices, the rest folded below", "BAR", [...])`
  whose rows are: a card **Choose** (Shape `bar.mode` · Style `bar.style` with STYLES =
  Instrument, Glass, Floating, Hairline, Minimal · Frame `frame.on` · Density `bar.density`), then folds
  **Edges & outline**, **Surface & depth**, **Frame & music** (adds `frame.islands` Float/Attach),
  **Size & place**, **Modules** (the layout editor, then Workspaces and Media cards), **The Pill**
  (a note row "COMES WITH THE PILL"). Page Colour renamed `("Theme & colour", ...)`; Quick's Bar card
  rows unchanged plus a button "Bar & Frame" that opens the page.
- New row kind `("fold", "Name", "summary text expression")`: a clickable header with a ▸/▾ fact
  `fd_<n>` (first fold open); the rows of a fold are hidden while closed and every row and card below
  moves up by the fold's body height (a `move:` on each following group, computed from the `fd_*` facts).
- `settings_index` rows point at the new page; `rows.layout_tab` is the Bar & Frame tab.

- [ ] **Step 1: Failing tests**: `settings_index` has no row whose page is "Layout", "Screen frame",
  "Workspaces" or "Media"; every bar.*/frame.* setting row's page is "Bar & Frame"; the generated plm
  contains `fd_0` and the rail label "Theme & colour"; STYLES has no "Steel".
- [ ] **Step 2: Run** — FAIL
- [ ] **Step 3: Implement** the generator changes (fold kind, page, renames); regenerate; the settings
  logic resets folds to the first open on each open of the window.
- [ ] **Step 4: Verify** generator determinism (run twice, no diff), `pleamar --check shell/mooi-settings.plm`,
  unit suite, open Settings live (`bin/mooi settings`), screenshot the page folded and unfolded, and scroll
  to the last row of the page with every fold open.
- [ ] **Step 5: Commit** `settings: one Bar & Frame page with folding sections (D166)`

---

### Task 7: The Look card, and "Look…" from edit mode

**Files:** Modify `tools/gen-settings.py` (Look card under the layout editor's Selected card), `shell/mooi-settings.luau`, `shell/mooi.luau`, `shell/mooi.plm`; Test `tests/unit/run.lua`

**Interfaces:**
- Produces: event `lay_look -> n` in mooi-settings: `n = key * 16 + value` with keys 0 colour (value:
  0 style, 1 phos, 2 ember, 3 trace, 4 wallpaper), 1 fill (0 style … 4 none), 2 rounding (0 style … 4 pill),
  3 outline (0 style, 1 none, 2 accent), 4 glow (0 off … 2 strong), 5 display, 6 width, 15 reset all;
  writes `bar.modules[modlook.head(id)]` through `lib/settingsfile`. A hex colour field reuses the
  settings window's hex input pattern (event `lay_hex`). Bar: in edit mode, the selected module's
  toolbar gains "Look…" → `run("mooi", { "settings", "module", id })`; `bin/mooi settings module <id>`
  starts Settings and says `emit open_module <k>` (k = index in `barlayout.ORDER`), which selects it on
  Bar & Frame → Modules with the Modules fold open.

- [ ] **Step 1: Failing tests**: a pure helper `modlook.decode(n) -> key, value` round-trips every key/value;
  `modlook.apply(settings, id, key, value)` writes to the head for a group member and `reset` removes all
  seven keys; the settings plm has `emit lay_look` zones; `bin/mooi` has a `settings module` branch.
- [ ] **Step 2: Run** — FAIL
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Verify live**: select the weather module in Settings, set fill solid / colour ember /
  rounding pill — the bar's weather island changes and only it; "Look…" from edit mode opens Settings
  at that module (use `pleamar --say` to drive, no pointer). Restore settings after.
- [ ] **Step 5: Commit** `settings: each module's look, from Settings or the bar's edit mode`

---

### Task 8: The live harness, verification and docs

**Files:** Modify `tests/chassis.sh`, `docs/TESTING.md`, `docs/DECISIONS.md` (D167), `STATUS.md`

- [ ] **Step 1: Extend `tests/chassis.sh`**: an outer loop over styles (instrument, glass, floating,
  hairline, minimal) for islands × frame off/on × swell off/on (outline from the style, surface as the
  style sets it for the hump check only; weight checks keep surface solid), and islands with
  `frame.islands = attach`: the gap column has no outline between the band's inner edge (`top`) and the
  foot, and the foot is one height. Styles with no outline: zero lines with the frame on too.
- [ ] **Step 2: Run** `sh tests/chassis.sh` — Expected: `0 failed`; settings md5 unchanged.
- [ ] **Step 3: Screens**: every style frame off / on / swelling; four differently styled islands; the
  Bar & Frame page folded and open — shown to the owner with `compare` against today.
- [ ] **Step 4: Performance**: `perf.sh` pattern before/after (bar, frame, GPU) — no regression beyond
  the 20 plate bodies' cost, recorded.
- [ ] **Step 5: Docs, gate, CI container, capture, commit** `docs: Bar & Frame verified (D167)`.
