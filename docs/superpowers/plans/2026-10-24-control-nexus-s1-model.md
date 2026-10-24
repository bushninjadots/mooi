# Control Nexus S1 — Model Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the pure node, edge, layout and settings model the full-window Control Nexus will render, with no visible change to the running plate.

**Architecture:** Delete the unratified D90 scaffolding, then add three pure modules (`nexusnode`, `nexusgraph`, `nexuslayout`) and schema v2 in `config.luau`. The scene logic seeds arrangements from legacy settings, filters nodes by real provider presence and publishes count/focus/mode facts. No scene drawing changes beyond removing the debug text.

**Tech Stack:** Pleamar 0.4.6 (language 0.4) scenes, Luau logic written in the Lua 5.4 / Luau shared subset, plain `lua5.4` unit tests, isolated Pleamar runtime for integration tests.

**Spec:** `docs/superpowers/specs/2026-10-24-control-nexus-design.md`

**Scope note:** This is the S1 plan. S2 (workspace shell), S3 (centre focus), S4 (connections), S5 (library/customization) and S6 (polish) get their own plans once S1 lands, because each depends on the exact shapes S1 proves. Do not start S2 from this document.

## Global Constraints

- Pleamar 0.4.6 / language 0.4; the repository's scenes must keep compiling with `pleamar --check`.
- Every `.luau` file must parse under `lua5.4` — use only the Lua 5.4 ∩ Luau subset, no `continue`, no compound assignment, no `+=`.
- Rules never write record fields; all mutable scene state is facts. Logic writes facts and settings only.
- All colour comes from Ferrolume roles (`fr_*`) or semantic tokens (`c_*`); no hex in new UI code.
- No fabricated telemetry: absent providers yield `N/A` or an absent node, never a guessed value.
- Caps: 16 node instances, 24 drawn edges, 8 arrangements, names unique and ≤16 characters.
- `MOOI_SAFE=1` disables every settings write; avoid it in code paths that must persist.
- Never restart, signal or poke the user's live mooi session. Integration checks use the isolated `mooi-lab` copy in `tests/nexus.sh`.
- Preserve the existing plate's behaviour and all 195 unit tests except the version assertions this plan deliberately updates.

## Review Focus

1. **Legacy v1 settings** that hide modules or name removed ids (`reactor`, `player`) must still produce a usable FULL arrangement; seeds keep the mapped modules visible and never fail the whole file. (Task 7 test `seeds from legacy modules`.)
2. **Hand-edited arrangements** — 9 entries, duplicate names, unknown node type, non-numeric coordinates — must fall back safely without crashing or silently keeping the invalid parts. (Task 6 reject tests; Task 2 unknown-type drop test.)
3. **Missing hardware** — no battery, no brightness sensor, no player, no GPU — must hide the conditional nodes and never show a fake reading. (Task 2 availability tests; Task 7 `visible_nodes` test.)
4. **A canvas smaller than the arrangement** — 1366×768 or a banner growth — must clamp and rescale nodes instead of drawing them off-screen. (Task 5 `fit` and `clamp` tests.)
5. **Focus on a removed node or on the node already centred** — must fall back to `core` or be a no-op, never lose or duplicate a node. (Task 5 focus tests; Task 7 focus fallback test.)

---

### Task 1: Delete the D90 scaffolding

**Files:**
- Modify: `shell/mooi-nexus.luau`
- Modify: `shell/mooi-nexus.plm`
- Modify: `docs/DECISIONS.md`
- Test: existing `bin/mooi check` and `tests/nexus.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: a scene with no `node_registry`, no `nx_node_*` / `nx_connection_*` / `nx_view_mode` / `nx_integration_*` debug facts and no debug text.

- [ ] **Step 1: Confirm nothing reads the scaffolding**

Run:
```bash
grep -n "node_registry\|focus_node\|add_node\|remove_node\|nx_node_count\|nx_connection_count\|nx_view_mode" shell/mooi-nexus.luau shell/mooi-nexus.plm
```
Expected: every hit in `mooi-nexus.luau` is at or after the `── Node model (D90+)` comment; every hit in `mooi-nexus.plm` is inside the debug text block near the top. No other file references them.

- [ ] **Step 2: Delete the logic block**

Delete from the `-- ── Node model (D90+) ─────` comment to the end of `shell/mooi-nexus.luau`. The file must still end with the `nx_close` handler it had before the block.

- [ ] **Step 3: Delete the scene debug block**

In `shell/mooi-nexus.plm`, delete the contiguous group of literal debug texts (`"NX_NODE_COUNT"`, `"NX_NODE_FOCUS"`, `"NX_LAYOUT_VARIANT"`, `"NX_CONNECTION_COUNT"`, `"NX_NODE_VISIBLE"`, `"NX_NODE_EXPANDED"`, `"NX_MODULE_COUNT"`, `"NX_VIEW_MODE"`, `"NX_INTEGRATION_RAM/CPU/GPU/DISK"`) and the duplicate `image nx_avatar` / `image nx_banner` declarations that sit in that block. Keep the banners actually drawn inside the identity band (`image nx_banner` at the band and `image nx_avatar` under the header) working.

- [ ] **Step 4: Remove the duplicate startup identity call**

`sync_identity()` is called at lines 51 and 85 with no change between the calls. Delete the second call only; keep the one after `fact.nx_pinned = settings.nexus.pinned`.

- [ ] **Step 5: Record the removal**

Append to `docs/DECISIONS.md` the next free decision number (D75 as of writing):

> **D75 — the D90 node scaffolding is deleted, not built upon.** It was unratified: `node_registry` was never seeded, its functions were never called, and the `nx_node_*` facts were never read; the plate drew their names as literal text. The node model starts from the approved spec (`docs/superpowers/specs/2026-10-24-control-nexus-design.md`).

- [ ] **Step 6: Verify and commit**

Run:
```bash
bin/mooi check
grep -rn "NX_NODE_COUNT\|nx_view_mode\|node_registry" shell/ || true
```
Expected: check passes (5 scenes compile, 195 tests, 0 failed); grep prints nothing.

```bash
git add shell/mooi-nexus.luau shell/mooi-nexus.plm docs/DECISIONS.md
git commit -m "Remove the unratified D90 node scaffolding"
```

---

### Task 2: Node registry

**Files:**
- Create: `shell/lib/nexusnode.luau`
- Modify: `tests/unit/run.lua` (new `nexusnode` section before the final summary)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `M.TYPES: { {id, title, category, accent, status, requires, size={w,h}, min={w,h}, max={w,h}, detail={w,h}, essential, capabilities={focus,resize,expand,duplicate,removable}} }` in display order.
  - `M.get(id) -> type|nil`
  - `M.available(type_id, present) -> ok:boolean, reason:string|nil`, where `present` is a set such as `{battery=true, brightness=true, media=true, gpu=true, sensors=true}`.
  - `M.normalize_nodes(list) -> nodes, dropped` — drops unknown, duplicate and malformed entries; clamps sizes; fills booleans.
  - `M.default_nodes(canvas) -> nodes` and `M.seed_arrangements(legacy) -> arrangements`.
  - `M.normalize_arrangements(list) -> arrangements, dropped`, `M.visible_nodes(arrangement, present) -> nodes`.

- [ ] **Step 1: Write the failing tests**

Append a `print("nexusnode")` section to `tests/unit/run.lua`, add `local nexusnode = require("lib/nexusnode")` beside the other requires, and write tests asserting:

```lua
-- registry
eq(#nexusnode.TYPES, 19, "connected plus unavailable types")
eq(nexusnode.get("core").title, "Nexus Core", "core title")
eq(nexusnode.get("nope"), nil, "unknown type")
local ok, why = nexusnode.available("power", {})
eq(ok, false, "no battery hides power"); eq(why, "No battery provider", "reason names the provider")
eq(nexusnode.available("power", { battery = true }), true, "battery makes power available")
eq(nexusnode.available("applications", { windows = true }), false, "unavailable types stay unavailable")

-- normalisation
local nodes = nexusnode.normalize_nodes({
    { type = "cpu", x = 10, y = 10, w = 10, h = 10 },
    { type = "cpu", x = 99, y = 99, w = 200, h = 200 },
    { type = "ghost", x = 0, y = 0, w = 100, h = 100 },
    "nonsense",
})
eq(#nodes, 1, "duplicate and unknown dropped")
eq(nodes[1].w, nexusnode.get("cpu").min.w, "width clamped to minimum")
eq(nodes[1].h, nexusnode.get("cpu").min.h, "height clamped to minimum")
eq(nodes[1].vis, true, "visibility defaults on")
eq(nodes[1].min, false, "minimised defaults off")
eq(nodes[1].essential, false, "essential defaults off")

-- defaults and seeds
local arranged = nexusnode.default_nodes({ w = 1920, h = 892 })
eq(#arranged, 10, "ten default nodes")
eq(arranged[1].type, "core", "core comes first")
eq(arranged[1].x + arranged[1].w / 2, 960, "core is horizontally centred")
eq(arranged[1].y + arranged[1].h / 2, 446, "core is vertically centred")
local seeds = nexusnode.seed_arrangements({ modules = { "cpu", "network", "player", "output" } })
eq(#seeds, 3, "three shipped arrangements")
eq(seeds[1].name, "FULL", "first is FULL"); eq(seeds[3].name, "MINIMAL", "last is MINIMAL")
eq(seeds[1].nodes[1].type, "core", "a seed always keeps the core")
for _, n in ipairs(seeds[1].nodes) do
    if n.type == "media" then eq(n.vis, true, "legacy player maps to media") end
end

-- availability filtering
local visible = nexusnode.visible_nodes(seeds[1], { battery = false, brightness = false, media = false })
for _, n in ipairs(visible) do
    eq(n.type ~= "power" and n.type ~= "display" and n.type ~= "media", true, "absent providers hide their node")
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `lua5.4 tests/unit/run.lua`
Expected: FAIL — `module 'lib/nexusnode' not found`.

- [ ] **Step 3: Implement the registry**

Create `shell/lib/nexusnode.luau` with `local M = {}` and `return M`, in the style of `shell/lib/nexus.luau` (comment why, not what).

The 19 types, in order, with `status` `"connected"` unless noted:

| id | title | category | accent | requires | size | min | max | detail | essential |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| core | Nexus Core | system | phos | — | 260×260 | 200×200 | 520×520 | 420×420 | true |
| system | System | system | phos | — | 240×160 | 200×110 | 520×360 | 620×420 | true |
| cpu | CPU | system | phos | — | 210×130 | 170×100 | 400×260 | 460×300 | false |
| memory | Memory | system | phos | — | 210×130 | 170×100 | 400×260 | 460×300 | false |
| gpu | GPU | system | phos | gpu | 210×130 | 170×100 | 400×260 | 460×300 | false |
| thermal | Thermal | system | ember | sensors | 210×130 | 170×100 | 400×260 | 460×300 | false |
| storage | Storage | system | flare | — | 210×130 | 170×100 | 400×260 | 460×300 | false |
| network | Network | connectivity | flare | — | 240×150 | 200×110 | 480×300 | 560×360 | true |
| audio | Audio | audio | phos | — | 240×150 | 200×110 | 480×300 | 560×360 | false |
| display | Display | system | phos | brightness | 220×130 | 180×100 | 420×260 | 480×300 | false |
| workspaces | Workspaces | workspaces | trace_lit | — | 260×170 | 220×120 | 520×340 | 600×400 | false |
| media | Media | audio | phos | media | 280×140 | 230×110 | 560×300 | 620×380 | false |
| clock | Clock | information | trace_lit | — | 200×120 | 160×96 | 380×240 | 420×280 | true |
| power | Power | system | ember | battery | 220×130 | 180×100 | 420×260 | 480×300 | false |
| applications | Applications | applications | trace_lit | windows | 240×150 | 200×110 | 480×300 | 560×360 | false |
| projects | Projects | files | phos | projects | 240×150 | 200×110 | 480×300 | 560×360 | false |
| notifications | Notifications | information | flare | notifications | 240×150 | 200×110 | 480×300 | 560×360 | false |
| quickactions | Quick Actions | actions | ember | actions | 240×150 | 200×110 | 480×300 | 560×360 | false |
| files | Files | files | trace_lit | files | 260×160 | 220×120 | 520×340 | 600×400 | false |

`applications`, `projects`, `notifications`, `quickactions` and `files` have `status = "unavailable"` and a `reason` (`"No window provider"`, `"No project provider"`, `"Notifications live in the bar"`, `"Not implemented yet"`, `"No file provider"`). All capabilities are `{ focus = true, resize = true, expand = false, duplicate = false, removable = true }` except `core`, whose `removable` is still true (the centre is a role) and whose `focus` is true.

`available` returns `false, reason` for unavailable types, then checks `requires` against `present`, returning `"No <provider> provider"` (provider lowercased; `sensors` says `"No sensor provider"`). `normalize_nodes` caps at 16, keeps the first occurrence of a type, and clamps `w`/`h` to the type's min/max.

`default_nodes(canvas)` uses the ratio table from the spec §7, with `media` and `power` included, and positions the node centre at `ratio.x * canvas.w`, `ratio.y * canvas.h`, clamped so the whole node fits. `seed_arrangements(legacy)` returns:

- `FULL`: default nodes at a 1920×892 reference canvas; if `legacy.modules` is a table, map plate ids (`output`→`audio`, `temp`→`thermal`, `rx`/`tx`→`network`, `player`→`media`) and set `vis = true` only for mapped types plus always `core`, `system`, `clock`; unmapped defaults stay but `vis = false`.
- `FOCUS`: `core`, `system`, `network`, `audio`, `storage`, `workspaces`.
- `MINIMAL`: `core`, `system`, `clock`, with `banner = "strip"`.

Every seed has `mode = "circuit"` (MINIMAL `"minimal"`), `focus = "core"`, `edges = { hidden = {}, style = "circuit", width = 1, animation = true }`, and the spec's appearance defaults. `visible_nodes` filters by `available` only; it does not reorder.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `lua5.4 tests/unit/run.lua`
Expected: PASS, no failures.

- [ ] **Step 5: Commit**

```bash
git add shell/lib/nexusnode.luau tests/unit/run.lua
git commit -m "Add the Nexus node registry and arrangement seeds"
```

---

### Task 3: Authored connection graph

**Files:**
- Create: `shell/lib/nexusgraph.luau`
- Modify: `tests/unit/run.lua`

**Interfaces:**
- Consumes: nothing (type ids are plain strings).
- Produces:
  - `M.EDGES` — `{ {id, from, to, kind, label, meaning, activity} }`.
  - `M.instantiate(types) -> edges` for a set of present type ids, both endpoints required.
  - `M.count(edges) -> number`.

- [ ] **Step 1: Write the failing tests**

```lua
print("nexusgraph")
test("graph: every authored edge connects known node types", function()
    local nxnode = require("lib/nexusnode")
    for _, e in ipairs(nexusgraph.EDGES) do
        eq(nxnode.get(e.from) ~= nil, true, "known source " .. tostring(e.from))
        eq(nxnode.get(e.to) ~= nil, true, "known target " .. tostring(e.to))
        eq(type(e.meaning), "string", "meaning for " .. e.id)
    end
end)
test("graph: instantiation keeps only edges whose endpoints exist", function()
    local edges = nexusgraph.instantiate({ core = true, system = true, storage = true })
    local ids = {}
    for _, e in ipairs(edges) do ids[e.id] = true end
    eq(ids["core-system"], true, "trunk kept")
    eq(ids["storage-system"], true, "satellite kept")
    eq(ids["storage-files"], nil, "files absent, edge absent")
    eq(ids["cpu-system"], nil, "cpu absent, edge absent")
    eq(nexusgraph.count(edges), 3, "exactly the three edges with both ends")
end)
test("graph: unavailable endpoints never draw", function()
    local all = {}
    for _, t in ipairs(require("lib/nexusnode").TYPES) do
        if t.status ~= "unavailable" then all[t.id] = true end
    end
    local edges = nexusgraph.instantiate(all)
    for _, e in ipairs(edges) do
        eq(e.to ~= "applications" and e.to ~= "files", true, "unavailable target not drawn")
    end
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua5.4 tests/unit/run.lua`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `shell/lib/nexusgraph.luau`**

The authored edges, in draw order:

| id | from | to | kind | label | meaning | activity |
| --- | --- | --- | --- | --- | --- | --- |
| core-system | core | system | trunk | SYSTEM | core bus | nil |
| core-network | core | network | trunk | LINK | core bus | nil |
| core-audio | core | audio | trunk | AUDIO | core bus | nil |
| core-workspaces | core | workspaces | trunk | SPACES | core bus | nil |
| core-storage | core | storage | trunk | STORE | core bus | nil |
| cpu-system | cpu | system | signal | LOAD | processor load | cpu |
| memory-system | memory | system | signal | MEM | memory pressure | memory |
| gpu-system | gpu | system | signal | GPU | graphics load | gpu |
| thermal-system | thermal | system | signal | TEMP | thermals | thermal |
| power-system | power | system | signal | PWR | power draw | power |
| storage-system | storage | system | signal | DISK | capacity | storage |
| storage-files | storage | files | signal | FILES | storage appears in Files | nil |
| network-system | network | system | signal | NET | throughput | network |
| audio-media | audio | media | signal | MEDIA | playback | media |
| workspaces-applications | workspaces | applications | signal | APPS | windows in spaces | nil |

`instantiate(types)` keeps an edge only when `types[from] and types[to]`; it never inspects availability beyond that, so the caller passes only available types. `count` returns `#edges`.

- [ ] **Step 4: Run tests**

Run: `lua5.4 tests/unit/run.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shell/lib/nexusgraph.luau tests/unit/run.lua
git commit -m "Add the authored Nexus connection graph"
```

---

### Task 4: Orthogonal edge routing

**Files:**
- Modify: `shell/lib/nexusgraph.luau`
- Modify: `tests/unit/run.lua`

**Interfaces:**
- Consumes: `M.EDGES` from Task 3.
- Produces:
  - `M.port(rect, toward) -> x, y, side` where `rect = {x,y,w,h}` and `toward = {x,y}`.
  - `M.route(a, b, opts) -> points, ok`; `opts = { style = "circuit"|"direct", clearance = 12, step = 12 }`; `points` is `{ {x,y}, ... }`; `ok` is false only for degenerate rects.
  - `M.clear(points, rect, clearance) -> boolean` (used by tests and later isolation drawing).

- [ ] **Step 1: Write the failing tests**

```lua
print("nexusgraph routing")
local function inside(pt, r, pad)
    return pt.x > r.x - pad and pt.x < r.x + r.w + pad and pt.y > r.y - pad and pt.y < r.y + r.h + pad
end
test("routing: ports sit on the side facing the other node", function()
    local x, y, side = nexusgraph.port({ x = 0, y = 0, w = 100, h = 100 }, { x = 300, y = 50 })
    eq(side, "e", "east side"); eq(x, 100, "on the edge"); eq(y, 50, "at the target's height")
    x, y, side = nexusgraph.port({ x = 0, y = 0, w = 100, h = 100 }, { x = 50, y = -300 })
    eq(side, "n", "north side"); eq(y, 0, "on the top edge")
end)
test("routing: a circuit route is orthogonal, clear of both nodes, and deterministic", function()
    local a = { x = 100, y = 100, w = 200, h = 140 }
    local b = { x = 700, y = 400, w = 220, h = 130 }
    local p1 = nexusgraph.route(a, b, { style = "circuit", clearance = 12 })
    local p2 = nexusgraph.route(a, b, { style = "circuit", clearance = 12 })
    eq(#p1, #p2, "same point count")
    for i = 1, #p1 do eq(p1[i].x, p2[i].x, "x stable " .. i); eq(p1[i].y, p2[i].y, "y stable " .. i) end
    eq(p1[1].x >= a.x and p1[1].x <= a.x + a.w, true, "starts on a")
    eq(p1[#p1].x >= b.x and p1[#p1].x <= b.x + b.w, true, "ends on b")
    for i = 2, #p1 do
        eq(p1[i].x == p1[i - 1].x or p1[i].y == p1[i - 1].y, true, "segment " .. i .. " is orthogonal")
    end
    for i = 2, #p1 do
        local mx, my = (p1[i].x + p1[i - 1].x) / 2, (p1[i].y + p1[i - 1].y) / 2
        eq(inside({ x = mx, y = my }, a, 11), false, "segment " .. i .. " leaves a")
        eq(inside({ x = mx, y = my }, b, 11), false, "segment " .. i .. " leaves b")
    end
end)
test("routing: direct is two points, degenerate is refused", function()
    eq(#nexusgraph.route({ x = 0, y = 0, w = 10, h = 10 }, { x = 50, y = 50, w = 10, h = 10 }, { style = "direct" }), 2, "two points")
    local pts, ok = nexusgraph.route({ x = 0, y = 0, w = 0, h = 0 }, { x = 5, y = 5, w = 10, h = 10 }, {})
    eq(ok, false, "degenerate refused"); eq(#pts, 0, "nothing to draw")
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua5.4 tests/unit/run.lua`
Expected: FAIL — `route` is nil.

- [ ] **Step 3: Implement ports and routing**

Port selection compares centre deltas: if `|dx| >= |dy|` use `e`/`w`, else `n`/`s`. The port coordinate is the rect edge, clamped to the rect span so the connector never leaves the frame.

`route`:

- Degenerate input (`w <= 0` or `h <= 0` on either rect) returns `{}, false`.
- `direct` returns the two port centres.
- `circuit` chooses both ports, then builds an orthogonal polyline: if the ports share an axis (same `x` or same `y`) it is two points; otherwise insert a dogleg at the midpoint of the free axis. When both chosen sides face away from each other, route around via `min(a.y, b.y) - clearance - step` (or the bottom equivalent) and snap every elbow to `step`. Never emit a zero-length segment: collapse duplicates, then guarantee at least two distinct points.
- `clear(points, rect, clearance)` returns true when no segment midpoint falls inside the inflated rect; used by the tests above.

The routing must be pure and allocation-bounded: no loops over the whole node list, only the two rects.

- [ ] **Step 4: Run tests**

Run: `lua5.4 tests/unit/run.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shell/lib/nexusgraph.luau tests/unit/run.lua
git commit -m "Route Nexus edges orthogonally around their nodes"
```

---

### Task 5: Layout math

**Files:**
- Create: `shell/lib/nexuslayout.luau`
- Modify: `tests/unit/run.lua`

**Interfaces:**
- Consumes: `nexusnode.get(id)` for per-type details.
- Produces:
  - `M.clamp(x, y, w, h, canvas) -> x, y`
  - `M.snap(v, grid) -> number`
  - `M.bounds(type_id, w, h) -> w, h`
  - `M.overlap(a, b, pad) -> boolean`
  - `M.free_slot(nodes, type_id, canvas, grid) -> x, y`
  - `M.fit(nodes, canvas) -> nodes`
  - `M.tidy(nodes, canvas, grid) -> nodes`
  - `M.focus(nodes, id, canvas) -> nodes, ok`
  - `M.move_step(node, dx, dy, canvas, grid) -> x, y`

- [ ] **Step 1: Write the failing tests**

```lua
print("nexuslayout")
local canvas = { w = 1920, h = 892 }
local function node(t, x, y, w, h)
    return { type = t, x = x, y = y, w = w or 200, h = h or 120, vis = true, min = false, essential = false }
end
test("layout: clamp keeps the whole node on the canvas", function()
    eq(nexuslayout.clamp(-50, -50, 200, 120, canvas), 0, "left and top")
    eq(select(2, nexuslayout.clamp(9999, 9999, 200, 120, canvas)), 892 - 120, "bottom")
    eq(select(1, nexuslayout.clamp(9999, 0, 2000, 120, canvas)), 0, "wider than canvas")
end)
test("layout: snap is nearest and grid-safe", function()
    eq(nexuslayout.snap(13, 8), 16, "rounds up"); eq(nexuslayout.snap(11, 8), 8, "rounds down")
    eq(nexuslayout.snap(13, 0), 13, "no grid, no change")
end)
test("layout: bounds use the registry", function()
    local w, h = nexuslayout.bounds("cpu", 10, 9999)
    eq(w, require("lib/nexusnode").get("cpu").min.w, "min width")
    eq(h, require("lib/nexusnode").get("cpu").max.h, "max height")
    eq(nexuslayout.bounds("ghost", 123, 45), 123, "unknown keeps what it was given")
end)
test("layout: overlap includes padding", function()
    eq(nexuslayout.overlap(node("cpu", 0, 0, 100, 100), node("cpu", 90, 90, 100, 100), 0), true, "overlaps")
    eq(nexuslayout.overlap(node("cpu", 0, 0, 100, 100), node("cpu", 105, 0, 100, 100), 8), false, "pad 8 clear at 105")
end)
test("layout: a free slot never overlaps and respects the canvas", function()
    local nodes = { node("cpu", 0, 0, 210, 130), node("cpu", 0, 130, 210, 130) }
    local x, y = nexuslayout.free_slot(nodes, "network", canvas, 8)
    eq(x % 8, 0, "snapped x"); eq(y % 8, 0, "snapped y")
    for _, n in ipairs(nodes) do
        eq(nexuslayout.overlap({ x = x, y = y, w = 240, h = 150 }, n, 8), false, "clear of " .. n.x .. "," .. n.y)
    end
    eq(x + 240 <= canvas.w and y + 150 <= canvas.h, true, "inside")
end)
test("layout: fit rescales an arrangement that outgrows the canvas", function()
    local nodes = { node("cpu", 0, 0), node("clock", 1800, 800) }
    local fitted = nexuslayout.fit(nodes, { w = 800, h = 400 })
    for _, n in ipairs(fitted) do
        eq(n.x + n.w <= 800 and n.y + n.h <= 400, true, "fitted inside")
    end
    eq(fitted[1].type, "cpu", "order preserved")
end)
test("layout: tidy repacks without overlap", function()
    local nodes = { node("cpu", 500, 500), node("memory", 510, 505), node("clock", 520, 510) }
    local tidy = nexuslayout.tidy(nodes, canvas, 8)
    for i = 1, #tidy do
        for j = i + 1, #tidy do
            eq(nexuslayout.overlap(tidy[i], tidy[j], 8), false, "no overlap " .. i .. "/" .. j)
        end
    end
end)
test("layout: focus swaps the old centre into the vacated slot and leaves the rest", function()
    local nodes = { node("core", 830, 316, 260, 260), node("cpu", 100, 100), node("network", 600, 100) }
    local out, ok = nexuslayout.focus(nodes, "cpu", canvas)
    eq(ok, true, "focused")
    eq(out[1].x, 100, "core takes the vacated slot's origin")
    eq(out[1].y, 100, "core takes the vacated slot's origin on y")
    eq(out[2].x + out[2].w / 2, canvas.w / 2, "cpu is centred")
    eq(out[2].y + out[2].h / 2, canvas.h / 2, "cpu centred vertically")
    eq(out[3].x, 600, "unrelated node untouched")
end)
test("layout: focus refuses an unknown or already-centred node", function()
    local nodes = { node("core", 830, 316, 260, 260), node("cpu", 100, 100) }
    eq(select(2, nexuslayout.focus(nodes, "ghost", canvas)), false, "unknown")
    local out, ok = nexuslayout.focus(nodes, "core", canvas)
    eq(ok, false, "already centre"); eq(out[1].x, 830, "unchanged")
end)
test("layout: keyboard move is one snapped step and stays inside", function()
    local n = node("cpu", 8, 8)
    eq(nexuslayout.move_step(n, 1, 0, canvas, 8), 16, "one step right")
    eq(select(1, nexuslayout.move_step(n, -100, 0, canvas, 8)), 0, "clamped")
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua5.4 tests/unit/run.lua`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `shell/lib/nexuslayout.luau`**

- `clamp`: when the node is wider/taller than the canvas, pin the origin to 0; otherwise clamp to `[0, canvas - size]`.
- `fit`: compute the bounding box of all nodes; if it fits, return the same table untouched. Otherwise scale origins by `min((canvas.w - gutter)/(maxX + w), (canvas.h - gutter)/(maxY + h))` with `gutter = 20`, snap, clamp, and keep sizes. Preserve order and every other field.
- `free_slot`: scan rows from the top-left with `step = max(grid, 8)`, testing against existing nodes inflated by 8; fall back to the last clamped position when nothing is free.
- `tidy`: pack in reading order into rows sized from the widest node, snapping and clamping; return new tables, do not mutate input.
- `focus`: find the node and the current centre node. If the id is missing, or the target is already the centre (its box contains the canvas centre and it is the largest centred node), return the input and `false`. Otherwise give the old centre the target's old box, give the target its type's `detail` size centred on the canvas, clamp both, leave others untouched, return new tables.
- `move_step`: `snap(node.x + dx * grid, grid)` then clamp.
- `bounds`: unknown types pass through; known types clamp to `min`/`max`.

No module-level mutable state.

- [ ] **Step 4: Run tests**

Run: `lua5.4 tests/unit/run.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shell/lib/nexuslayout.luau tests/unit/run.lua
git commit -m "Add Nexus layout, snap, fit and centre-swap maths"
```

---

### Task 6: Settings schema v2

**Files:**
- Modify: `shell/lib/config.luau`
- Modify: `tests/unit/run.lua`

**Interfaces:**
- Consumes: nothing new.
- Produces: `config.VERSION == 2`; new schema rows listed below; `check` support for kind `"arrangements"`; legacy rows retained.

- [ ] **Step 1: Write the failing tests**

Add to the existing config section:

```lua
test("nexus v2: new settings have defaults and the file is version 2", function()
    local d = config.defaults()
    eq(d.version, 2, "version")
    eq(d.nexus.mode, "circuit", "mode")
    eq(d.nexus.banner.mode, "compact", "banner")
    eq(d.nexus.edge.style, "circuit", "edge style")
    eq(d.nexus.edge.width, 1, "edge width")
    eq(d.nexus.appearance.accent, "phos", "accent")
    eq(d.nexus.appearance.glow, 60, "glow")
    eq(#d.nexus.arrangements, 0, "no arrangements yet")
end)
test("nexus v2: a valid arrangement is accepted", function()
    local a = { name = "FULL", mode = "circuit", focus = "core", banner = "full",
        nodes = { { type = "core", x = 0, y = 0, w = 260, h = 260, vis = true, min = false, essential = true } },
        edges = { hidden = {}, style = "circuit", width = 1, animation = true },
        appearance = { accent = "phos", brightness = 100, contrast = 100, opacity = 100, glow = 60, grid = true, motion = true } }
    local s, p = config.validate({ version = 2, nexus = { arrangements = { a } } })
    eq(#p, 0, "no problems"); eq(#s.nexus.arrangements, 1, "kept"); eq(s.nexus.arrangements[1].name, "FULL", "name")
end)
test("nexus v2: bad arrangements fall back whole, never partly", function()
    local function arr(name, extra)
        local a = { name = name, mode = "circuit", focus = "core", banner = "full", nodes = {}, edges = { hidden = {} }, appearance = {} }
        for k, v in pairs(extra or {}) do a[k] = v end
        return a
    end
    local _, p = config.validate({ version = 2, nexus = { arrangements = { arr("A"), arr("A") } } })
    eq(#p > 0, true, "duplicate names rejected")
    local s, p2 = config.validate({ version = 2, nexus = { arrangements = { arr("ok", { mode = "spiral" }) } } })
    eq(#p2 > 0, true, "bad mode rejected"); eq(#s.nexus.arrangements, 0, "list dropped")
    local _, p3 = config.validate({ version = 2, nexus = { arrangements = { arr("ok", { nodes = { { type = "cpu", x = "left" } } }) } } })
    eq(#p3 > 0, true, "non-numeric coordinate rejected")
    local _, p4 = config.validate({ version = 2, nexus = { arrangements = { arr("a"), arr("b"), arr("c"), arr("d"), arr("e"), arr("f"), arr("g"), arr("h"), arr("i") } } })
    eq(#p4 > 0, true, "more than eight rejected")
end)
test("nexus v2: legacy keys survive the version bump", function()
    local s, p = config.validate({ version = 1, nexus = { layout = "FOCUS", modules = { "cpu", "network" }, layouts = { { name = "MINE", modules = { "cpu" } } } } })
    eq(#p, 0, "no problems")
    eq(s.nexus.layout, "FOCUS", "legacy layout kept"); eq(s.nexus.layouts[1].name, "MINE", "legacy named layout kept")
    eq(#s.nexus.modules, 2, "legacy modules kept")
end)
```

Update the three existing version assertions: `defaults ... version` 1→2 (line ~282), `a newer version is noted` uses version 3 instead of 2, and any `version = 1` fixture that asserted a note continues to be accepted (notes, not problems).

- [ ] **Step 2: Run to verify failure**

Run: `lua5.4 tests/unit/run.lua`
Expected: FAIL — version is 1 / arrangements missing.

- [ ] **Step 3: Implement schema v2**

Set `M.VERSION = 2`.

Add rows:

```lua
{ path = "nexus.arrangements", kind = "arrangements", default = {} },
{ path = "nexus.focus", kind = "text", default = "core", max = 24 },
{ path = "nexus.mode", kind = "enum", values = { "circuit", "minimal" }, default = "circuit" },
{ path = "nexus.banner.mode", kind = "enum", values = { "full", "compact", "strip", "hidden" }, default = "compact" },
{ path = "nexus.appearance.accent", kind = "enum", values = { "phos", "flare", "ember", "trace_lit" }, default = "phos" },
{ path = "nexus.appearance.brightness", kind = "integer", default = 100, min = 60, max = 140 },
{ path = "nexus.appearance.contrast", kind = "integer", default = 100, min = 60, max = 140 },
{ path = "nexus.appearance.opacity", kind = "integer", default = 100, min = 40, max = 100 },
{ path = "nexus.appearance.glow", kind = "integer", default = 60, min = 0, max = 100 },
{ path = "nexus.appearance.grid", kind = "boolean", default = true },
{ path = "nexus.appearance.motion", kind = "boolean", default = true },
{ path = "nexus.edge.style", kind = "enum", values = { "circuit", "curved", "direct" }, default = "circuit" },
{ path = "nexus.edge.width", kind = "integer", default = 1, min = 1, max = 2 },
{ path = "nexus.edge.animation", kind = "boolean", default = true },
{ path = "nexus.edge.labels", kind = "boolean", default = true },
```

Add a local `check_arrangement(a)` and the `elseif row.kind == "arrangements"` branch to `check`, following the `layouts` style:

- `#value <= 8`.
- Each entry is a table with `name` (non-empty string, ≤16, no control chars, unique), `mode` in `circuit|minimal`, `focus` plain string ≤24, `banner` in the four modes.
- `nodes` is a table of ≤16 tables; each needs `type` matching `^[%w_]+$` and ≤24 chars, numeric `x`, `y`, `w`, `h` (finite, `-4000..4000` for origins, `40..1200` for sizes), booleans `vis`/`min`/`essential`.
- `edges`, when present, is a table; `hidden` is ≤24 id strings; `style` in the three styles; `width` 1 or 2; `animation` boolean. Missing edge fields are accepted and filled by the logic.
- `appearance`, when present, is a table with the same accent/brightness/contrast/opacity/glow/grid/motion bounds as the rows above; missing fields are accepted and filled by the logic.
- Any violation rejects the whole list, matching `layouts`.

Do not remove `nexus.layout`, `nexus.layouts`, `nexus.modules` — the plate still reads them until S5.

- [ ] **Step 4: Run tests**

Run: `lua5.4 tests/unit/run.lua`
Expected: PASS, count increases by the new tests.

- [ ] **Step 5: Commit**

```bash
git add shell/lib/config.luau tests/unit/run.lua
git commit -m "Add Nexus schema v2 with validated arrangements"
```

---

### Task 7: Seed and publish the model from the scene logic

**Files:**
- Modify: `shell/mooi-nexus.luau`
- Modify: `tests/nexus.sh`
- Modify: `docs/NEXUS-PROGRESS.md`

**Interfaces:**
- Consumes: `nexusnode.seed_arrangements`, `nexusnode.normalize_arrangements`, `nexusnode.visible_nodes`, `config.VERSION 2`.
- Produces facts: `nx_arrangement_count`, `nx_node_count`, `nx_focus`, `nx_mode`, `nx_banner_mode`. No scene block reads them yet; S2 does.

- [ ] **Step 1: Write the failing integration checks**

In `tests/nexus.sh`, after the existing "three named layouts start" check, add:

```bash
is "three arrangements are seeded" "$(get nx_arrangement_count)" 3
case "$(get nx_node_count)" in
    8|9|10) ok "the default arrangement has 8 to 10 anchors" ;;
    *) bad "default arrangement has $(get nx_node_count) nodes" ;;
esac
is "the centre starts on the core" "$(get nx_focus)" core
is "the mode starts as circuit" "$(get nx_mode)" circuit
```

Also assert the legacy plate still works (the existing module/layout checks already do) — do not remove them.

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/nexus.sh`
Expected: FAIL — `nx_arrangement_count` is empty.

- [ ] **Step 3: Implement the seed and publish**

In `shell/mooi-nexus.luau`, require `lib/nexusnode` beside the other requires.

Presence is read the same way the plate reads it: the scene already declares `battery` and `brightness`, and logic listens to declared services with `sys.watch`. Add a module-level `present` table and two watchers; the GPU, thermal and media presence come from facts the sampling code already publishes (`nx_gpu_on`, `nx_temp_on`, `nx_has`).

After the initial samples, add `sync_model()`:

```lua
local present = { battery = false, brightness = false, seeded = false }

local function sync_model()
    local p = {
        battery = present.battery,
        brightness = present.brightness,
        media = fact.nx_has == true,
        gpu = fact.nx_gpu_on == true,
        sensors = fact.nx_temp_on == true,
    }
    local arrangements = nexusnode.normalize_arrangements(settings.nexus and settings.nexus.arrangements or {})
    local seeded = false
    if #arrangements == 0 then
        arrangements = nexusnode.seed_arrangements(settings.nexus or {})
        seeded = true
    end
    local active = arrangements[1]
    fact.nx_arrangement_count = #arrangements
    fact.nx_node_count = #nexusnode.visible_nodes(active, p)
    fact.nx_focus = active.focus
    fact.nx_mode = active.mode
    fact.nx_banner_mode = active.banner
    if seeded and tostring(sys.ask("env", "MOOI_SAFE") or "") ~= "1" then
        if type(settings.nexus) ~= "table" then settings.nexus = {} end
        settings.nexus.arrangements = arrangements
        settings.nexus.focus = active.focus
        settings.nexus.mode = active.mode
        settings.nexus.banner = { mode = active.banner }
        local ok = pcall(sys.call, "files.write", FILE, settings)
        if not ok then text.nx_notice_text = "Could not save the Nexus model" end
    end
end

pcall(sys.watch, "battery", function(b)
    present.battery = type(b) == "table" and b.present == true
    sync_model()
end)
pcall(sys.watch, "brightness", function(b)
    present.brightness = type(b) == "table" and b.present == true
    sync_model()
end)
```

Call `sync_model()` once after the first live sample so `nx_gpu_on` / `nx_temp_on` / `nx_has` exist, and again at the end of each 2 s sample. Once an arrangement exists `seeded` is false, so later calls only publish facts. In the settings watch, call `sync_model()` only when `#settings.nexus.arrangements` changed, to avoid rewriting while a name is edited.

`normalize_arrangements` must also handle a stored `focus` that names a type not in the arrangement: fall back to `"core"` when present, otherwise the first node's type.

- [ ] **Step 4: Run the unit and isolated integration suites**

Run:
```bash
bin/mooi check
bash tests/nexus.sh
```
Expected: unit suite passes; every check in `nexus.sh` reports ok, including the new arrangement facts and the untouched plate checks.

- [ ] **Step 5: Record progress**

Append to `docs/NEXUS-PROGRESS.md`: S1 built (registry, graph, routing, layout, schema v2, seeding), verification commands and counts, what is not yet visible, and the next step (S2 workspace shell).

- [ ] **Step 6: Commit**

```bash
git add shell/mooi-nexus.luau tests/nexus.sh docs/NEXUS-PROGRESS.md
git commit -m "Seed the Nexus model from legacy settings"
```

---

## Self-Review

**Spec coverage for S1:** node registry (§5.1), instance state/limits (§5.2), graph catalogue (§6.1), routing (§6.2, circuit/direct; curved is S4), layout/snap/fit/focus swap (§5.4–5.5), schema v2 and validation (§13), seeding and provider filtering (§7, §11), removal of the dead stub (§2). Spatial/notification/app providers, user links, pan/zoom and duplication are explicitly deferred by the spec.

**Type consistency:** `nexusnode.get`, `normalize_nodes`, `visible_nodes`, `seed_arrangements`; `nexusgraph.instantiate`, `route`, `port`; `nexuslayout.focus`, `fit`, `tidy`, `free_slot`; config kinds `arrangements`. No later task renames these.

**Proportion:** the plan fixes names, shapes and assertions; bodies stay with the implementer, except the one non-obvious algorithm (orthogonal dogleg routing) and the required migration snippet.
