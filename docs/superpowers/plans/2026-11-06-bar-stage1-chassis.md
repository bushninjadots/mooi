# Bar redesign · Stage 1: core and chassis — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One shape model draws the bar's pieces in every mode, so islands float without empty humps, the bar's foot sits at one height whatever the frame does, and the schema carries `bar.material` and `bar.density`.

**Architecture:** A pure Lua module (`shell/lib/chassis.luau`) turns the bar's layout (`bar-geo.json`) and look into piece rectangles. mooi-frame's logic writes them as facts (`px0…`), and the generated frame scene (`tools/gen-frame.py`) draws those facts instead of re-deriving geometry. The bar keeps its own plates only as a fallback for when the frame program is not running.

**Tech Stack:** Pleamar 0.7.11 (language 0.9) scenes and Lua logic; Python generator; POSIX sh tests; Lua 5.4 unit tests.

**Spec:** `docs/superpowers/specs/2026-11-06-bar-redesign-design.md` (§2, §3, §9 stage 1, §10)

## Global Constraints

- Requires use slash paths only (`require("lib/chassis")`); the gate refuses dotted ones.
- `settings.json` is only written through `lib/settingsfile`; this stage adds no writer.
- The frame scene is generated: edit `tools/gen-frame.py`, run it, commit both; CI fails on drift.
- Outline width rule (commit 0ac5421) stays: every tile border is
  `if(band_on, if(st_frame_edge < 1.5, st_owidth, 0), if(bar_frame < 0.5, st_owidth, 0))`; no second line.
- Performance budget: bar ≤ ~2 % of a core, frame with swell ≤ ~10 % GPU; sample before and after.
- After every logic change: `bin/mooi session`, then `grep "runtime error" ~/.local/state/mooi/mooi.log`
  must be empty for the new run.
- Live tests touch the owner's desktop: they must restore `settings.json` byte for byte and never move
  the pointer.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; run `setup/capture.sh`
  before a commit that is pushed.

## Review Focus

1. A module that is hidden or 0 px wide (`iw = 0`) must produce no piece at all, not a 6 px sliver.
2. An island touching the screen's left or right edge with the frame on: the frame corner must still
   turn at the piece's foot (today's `covL`/`covR`), not cut through it.
3. `bar.offset` > 0 or `bar.rail` on moves `fl.top`: the foot must follow (`fl.top + bar.height`), in
   every state.
4. The frame program dies or never starts: the bar must draw its own plates again (no outline-less bar).
5. A settings file with `bar.material = "chrome"` (unknown) loads as `ferrolume` with a problem noted,
   and the rest of the file is kept.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `shell/lib/config.luau` | schema: `bar.material`, `bar.density` |
| `shell/lib/chassis.luau` (new) | pure: layout + look → piece rects; corner coverage |
| `shell/mooi-frame.luau` | reads geo, calls chassis, writes `px/py/pw/ph/pr/pk` facts |
| `tools/gen-frame.py` → `shell/mooi-frame.plm` | draws the pieces from those facts |
| `shell/mooi.luau`, `shell/mooi.plm` | frame always runs; `chassis_up` fact replaces `pf`'s `ch_on` |
| `tests/unit/run.lua` | unit tests for all of the above |
| `tests/chassis.sh` (new) | live harness: foot height, outline weight, hump check, restore |
| `docs/TESTING.md`, `docs/DECISIONS.md`, `STATUS.md` | the new suite, D165, status |

---

### Task 1: Schema — `bar.material` and `bar.density`

**Files:**
- Modify: `shell/lib/config.luau` (SCHEMA, near `bar.mode`, line ~29)
- Test: `tests/unit/run.lua` (section "config")

**Interfaces:**
- Produces: `settings.bar.material ∈ {"ferrolume","liquid","cartridge"}` (default `"ferrolume"`),
  `settings.bar.density ∈ {"minimal","balanced","rich"}` (default `"balanced"`). Not in the settings
  window or setters yet (stages 4 and 7 add them).

- [ ] **Step 1: Write the failing test** `"the bar's material and density: defaults, and an unknown one falls back"`

```lua
local d = config.defaults()
eq(d.bar.material, "ferrolume"); eq(d.bar.density, "balanced")
local s, p = config.validate({ bar = { material = "chrome", density = "rich", height = 30 } })
eq(s.bar.material, "ferrolume", "unknown material falls back")
eq(s.bar.density, "rich"); eq(s.bar.height, 30, "the rest is kept"); eq(#p, 1, "one problem")
```

- [ ] **Step 2: Run** `lua5.4 tests/unit/run.lua --filter "material"` — Expected: FAIL (`nil` vs `"ferrolume"`)
- [ ] **Step 3: Add the two enum rows** to `M.SCHEMA` with the values and defaults above.
- [ ] **Step 4: Run** the filter again — Expected: PASS; then `lua5.4 tests/unit/run.lua | tail -1` — `0 failed`
- [ ] **Step 5: Commit** `config: bar.material and bar.density (D164 stage 1)`

---

### Task 2: The shape model — `lib/chassis.luau`

**Files:**
- Create: `shell/lib/chassis.luau`
- Test: `tests/unit/run.lua` (new section "chassis")

**Interfaces:**
- Consumes: the decoded `bar-geo.json` table (`{ islands = {{x,w}…}, left/center/right/panel = {x,w}, saving }`).
- Produces:
  - `chassis.SLOTS = 20`
  - `chassis.look(settings) -> look` with `look = { mode = "islands"|"full"|"notch", band = bool, top = number,
    mod_h = number, radius = number, n_pad = 10, n_r = radius + 4, n_b = number, screen_w = number }`
    where `top = bar.offset + (notch and 6 or (bar.rail and 15 or 8))` (same as `theme/ferrolume.plm`'s
    `fl.top`), `mod_h = bar.height`, `n_b = band and (top + mod_h + 1) or (top + mod_h + 6)`.
  - `chassis.pieces(geo, look) -> { { x, y, w, h, r, k }, … }` — at most `SLOTS`, in slot order:
    - islands: one per island with `w > 0`: `x = ix - 3, y = top, w = iw + 6, h = mod_h, r = radius,
      k = 0` (floating plates, the bar's own `Frame` geometry: they never touch the band, so no humps).
    - full: one piece from `panel`: `x = px, y = band and -40 or top, w = pw, h = (top + mod_h) - y,
      r = radius, k = 12` (joined to the band).
    - notch: one per non-empty `left`/`center`/`right`: `x = gx - n_pad, y = band and -40 or bar.offset,
      w = gw + 2 * n_pad, h = n_b - y, r = n_r, k = 12` (hanging from the top, as the notch design is).
  - `chassis.foot(look) -> number`: `top + mod_h` for islands/full, `n_b` for notch.
  - `chassis.covers(pieces, look, side) -> bool` (`side = "left"|"right"`): a piece reaches within
    `cr = band_w + frame_r + reach + 12` of that screen edge (today's `covL`/`covR`; `look` gains
    `band_w`, `frame_r`, `reach` from `frame.band`, `frame.radius`, `frame.reach * 1.6`).

- [ ] **Step 1: Write the failing tests** (section "chassis")

```lua
local chassis = require("lib/chassis")
local function L(t) local l = { mode = "islands", band = true, top = 8, mod_h = 24, radius = 7, n_pad = 10, n_r = 11, n_b = 33,
                                screen_w = 1920, band_w = 2, frame_r = 14, reach = 16 }
                    for k, v in pairs(t or {}) do l[k] = v end; return l end
local geo = { islands = { { x = 12, w = 182 }, { x = 0, w = 0 }, { x = 637, w = 280 } },
              left = { x = 12, w = 448 }, center = { x = 637, w = 646 }, right = { x = 1492, w = 416 }, panel = { x = 12, w = 1896 } }
test("chassis: islands float as plates, one per visible module, never up into the band", function()
    local p = chassis.pieces(geo, L())
    eq(#p, 2, "the 0-wide module has no piece")
    eq(p[1].x, 9); eq(p[1].w, 188); eq(p[1].y, 8); eq(p[1].h, 24); eq(p[1].k, 0, "no blend: crisp plates")
    for _, q in ipairs(p) do assert(q.y >= 8, "no piece reaches above the row: no hump") end
end)
test("chassis: one foot whatever the frame does", function()
    for _, band in ipairs({ true, false }) do
        local p = chassis.pieces(geo, L({ band = band }))
        eq(p[1].y + p[1].h, 32, "islands foot, band " .. tostring(band))
        local f = chassis.pieces(geo, L({ mode = "full", band = band }))
        eq(f[1].y + f[1].h, 32, "full foot, band " .. tostring(band))
    end
    eq(chassis.foot(L()), 32); eq(chassis.foot(L({ mode = "notch" })), 33)
end)
test("chassis: offset and rail move the row and its foot together", function()
    local s = config.validate({ bar = { offset = 6, rail = true, height = 30 } })
    local l = chassis.look(s)
    eq(l.top, 21); eq(chassis.foot(l), 51)
end)
test("chassis: notch pieces hang from the top, full joins the band", function()
    local n = chassis.pieces(geo, L({ mode = "notch" }))
    eq(#n, 3); eq(n[1].y, -40); eq(n[1].x, 2); eq(n[1].w, 468); eq(n[1].y + n[1].h, 33); eq(n[1].k, 12)
    eq(chassis.pieces(geo, L({ mode = "full" }))[1].y, -40)
end)
test("chassis: an island at the screen's edge is covered by the corner", function()
    local edge = { islands = { { x = 4, w = 40 }, { x = 1880, w = 36 } } }
    local p = chassis.pieces(edge, L())
    eq(chassis.covers(p, L(), "left"), true); eq(chassis.covers(p, L(), "right"), true)
    eq(chassis.covers(chassis.pieces(geo, L()), L(), "right"), false)
end)
```

- [ ] **Step 2: Run** `lua5.4 tests/unit/run.lua --filter "chassis"` — Expected: FAIL (`module 'lib/chassis' not found`)
- [ ] **Step 3: Implement** `shell/lib/chassis.luau` with the four functions and the constant above; pure (no `sys`, no `fact`).
- [ ] **Step 4: Run** the filter — Expected: PASS (5 tests); full suite `0 failed`
- [ ] **Step 5: Commit** `chassis: one shape model for the bar's pieces (D164 stage 1)`

---

### Task 3: The frame draws the pieces from the model

**Files:**
- Modify: `shell/mooi-frame.luau` (`geo()`, `apply()`; lines ~45–145)
- Modify: `tools/gen-frame.py` (`PIECES`, the `PY`/`PH` constants, `covL`/`covR` users)
- Regenerate: `shell/mooi-frame.plm`
- Test: `tests/unit/run.lua` (section "chassis")

**Interfaces:**
- Consumes: `chassis.look`, `chassis.pieces`, `chassis.covers` (Task 2).
- Produces: frame facts `px0…px19`, `py…`, `pw…`, `ph…`, `pr…`, `pk…` (numbers; `pw = 0` hides a slot),
  `covL`, `covR` (bools, now facts instead of scene `let`s). The scene's per-mode piece formulas and the
  `ix/iw`, `plx/pcx/prx`, `gp_x` facts are removed.

- [ ] **Step 1: Write the failing test** `"the frame scene draws pieces only from the model's facts"`

```lua
local f = io.open("shell/mooi-frame.plm"); local plm = f:read("a"); f:close()
assert(plm:find("box { from: px0, py0; size: pw0, ph0; corner: pr0; blend: pk0", 1, true), "slot 0 from facts")
assert(plm:find("px19", 1, true), "all 20 slots")
eq(plm:find("ix0 - 3", 1, true), nil, "no geometry re-derived in the scene")
eq(plm:find("let covL", 1, true), nil, "corner coverage comes from the logic")
```

- [ ] **Step 2: Run** the filter — Expected: FAIL
- [ ] **Step 3: Change `gen-frame.py`**: `PIECES` becomes 20 slots of
  `box { from: px{i}, py{i}; size: pw{i}, ph{i}; corner: pr{i}; blend: pk{i}; show: pw{i} > 0 and px{i} < {x1} + 48 and px{i} + pw{i} > {x0} - 48 }`
  (tile culling kept); declare the 120 facts and `covL`/`covR` as facts; delete the `let covL/covR`
  lines and the `PY`/`PH` per-mode formulas. Run `python3 tools/gen-frame.py`.
- [ ] **Step 4: Change `mooi-frame.luau`**: `geo()` stores the decoded geo; a `place()` function calls
  `chassis.pieces(geo, chassis.look(settings))`, writes each slot's six facts (zeroing unused slots),
  and `covL`/`covR` from `chassis.covers`; call `place()` from `geo()` and from the settings watcher.
- [ ] **Step 5: Verify** `pleamar --check shell/mooi-frame.plm` — Expected: `ok`; unit filter PASS; `sh tests/gate.sh` — `gate: ok`
- [ ] **Step 6: Commit** `frame: draw the bar's pieces from lib/chassis`

---

### Task 4: The frame always runs; the bar's plates become the fallback

**Files:**
- Modify: `shell/mooi.luau` (`frame_sync`, line ~2150; `fact.ch_on`, line ~110)
- Modify: `shell/mooi.plm` (`fact ch_on`, `let pf`, line ~33–35)
- Test: `tests/unit/run.lua`

**Interfaces:**
- Produces: bar fact `chassis_up` (bool): true while the frame program runs (set when `spawn` succeeds,
  false in its exit callback and when `frame_tries` gives up). `let pf = chassis_up` replaces
  `frame_on or ch_on`. `island.morph` keeps meaning "islands grow out of their piece", nothing more.

- [ ] **Step 1: Write the failing test** `"the bar's own plates are only a fallback for a missing frame"`

```lua
local f = io.open("shell/mooi.plm"); local plm = f:read("a"); f:close()
assert(plm:find("let pf = chassis_up", 1, true), "pf follows the running frame")
local g = io.open("shell/mooi.luau"); local lu = g:read("a"); g:close()
assert(not lu:find("settings.island.morph ~= false)\n    if not want", 1, true), "the frame no longer depends on morph or frame.on")
assert(lu:find("fact.chassis_up = false", 1, true), "an exited frame hands the plates back to the bar")
```

- [ ] **Step 2: Run** the filter — Expected: FAIL
- [ ] **Step 3: Implement**: `frame_sync` wants the frame always (safe mode included); set
  `fact.chassis_up = true` once spawned, `false` on exit and on give-up; scene: `fact chassis_up = false`,
  `let pf = chassis_up`; remove `ch_on` from both files.
- [ ] **Step 4: Verify** `bin/mooi check` — Expected: exit 0, 13 scenes compile.
- [ ] **Step 5: Verify live** `bin/mooi session`; `grep -c "runtime error" ~/.local/state/mooi/mooi.log`
  shows no new line; `pgrep -af mooi-frame.plm` shows the frame. Then `pkill -f mooi-frame.plm`: within
  10 s the bar shows its own plates (screenshot `grim -g "0,0 1920x60"`), and `frame_sync` restarts the frame.
- [ ] **Step 6: Commit** `bar: the frame always draws the chassis; the bar's plates are its fallback`

---

### Task 5: `tests/chassis.sh` — the live harness

**Files:**
- Create: `tests/chassis.sh` (from the 2026-11-06 `combos.sh` pattern)
- Modify: `docs/TESTING.md` (new row: local only, needs a running mooi and Hyprland)

**Interfaces:**
- Consumes: a running mooi; `jq`, `grim`, `magick`, `playerctl`.
- Produces: exit 0 when every check passes; prints one line per state and `N checks, M failed`.

- [ ] **Step 1: Write the script**: refuses to run unless `bin/mooi status` says mooi is the desktop;
  copies `settings.json` and restores it on EXIT/INT/TERM (and restores the player's paused/playing
  state); for shape ∈ {islands, full, notch} × border ∈ {none, thin, regular, bold} × frame ∈ {off, on}
  × swell ∈ {off, on}: writes the state with `jq`, waits 2.5 s, screenshots `0,0 1920x130`, and checks:
  - **foot**: the brightest row in column `x = ix0 + 20` (from `bar-geo.json`) between `y = 20` and
    `y = 60` is within 1 px of the same shape's frame-off value (border ≠ none);
  - **weight**: the count of rows brighter than the background at that column is 1 for thin, 2 for
    regular and bold, 0 for none (±1);
  - **no hump** (islands): in the column at the middle of the widest gap between islands, no row above
    the foot is brighter than the background by more than 25 levels.
- [ ] **Step 2: Run it against the current tree** `sh tests/chassis.sh` — Expected before Tasks 3–4 are
  live: foot and hump checks FAIL (the 2026-11-06 measurements: 31/34/37); after: `0 failed`.
- [ ] **Step 3: Verify** `md5sum ~/.local/share/pleamar/mooi/settings.json` matches before and after.
- [ ] **Step 4: Commit** `tests: chassis.sh, the bar's foot, weight and humps in every state`

---

### Task 6: Live verification, performance and docs

**Files:**
- Modify: `docs/DECISIONS.md` (D165), `STATUS.md`, `docs/TESTING.md` (result and date)

- [ ] **Step 1: Run** `bin/mooi session`, then `sh tests/chassis.sh` — Expected: `0 failed`.
- [ ] **Step 2: Performance**: with music playing muted and swell on, sample 20 s of
  `ps -o %cpu -p <bar pid>` and the GPU busy % (`cat /sys/class/drm/card*/device/gpu_busy_percent`),
  before (previous commit's session) and after. Expected: bar ≤ ~2 %, GPU ≤ ~10 %; record both.
- [ ] **Step 3: Before/after screenshots** of islands, full and notch with the frame on and off; show
  them to the owner (`show_image` with `compare`).
- [ ] **Step 4: Docs**: D165 "Stage 1: one chassis shape" (what changed, the measurements); STATUS
  verified table; TESTING row date.
- [ ] **Step 5: Gate and push**: `bin/mooi check`; the CI gate in an `ubuntu:24.04` container
  (`sh tests/gate.sh --no-pleamar`); `setup/capture.sh`; commit `docs: bar stage 1 verified (D165)`;
  `git push origin main`; confirm the GitHub run is green.
