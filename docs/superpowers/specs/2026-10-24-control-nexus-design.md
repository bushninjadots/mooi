# mooi · Control Nexus — Design

**Date:** 2026-10-24
**Status:** For review
**Scope:** Replace the fixed Control Nexus plate with a full-window, node-based control environment, staged so every step is runnable and revertable.

---

## 1. Intent

The Control Nexus becomes the place where the machine is shaped around the user's work:

> Everything is a node. Every node can move. Any node can become the centre. Anything unnecessary can disappear.

It is not a dashboard with circuit decoration. It is one coherent environment: a full-window canvas of movable module nodes joined by meaningful, animated pathways, with a configurable identity banner and a low-profile status strip. The existing eclectic plate, its verified integrations and its design language survive; its fixed layout does not.

**Non-goals for this design:**

- No second shell framework, no new global navigation. The bar keeps ownership of Home, Applications, Files and settings entry points.
- No pan/zoom canvas in this increment.
- No fabricated telemetry or decorative animation that implies a real system state.
- No uninstall/disable behaviour behind "remove node". Removal is layout-only.
- No free-form user wiring until a later stage; the first graph is authored.

---

## 2. Baseline (what exists today)

| Layer | File | Notes |
| --- | --- | --- |
| Render | `shell/mooi-nexus.plm` (~46 KB) | One overlay surface, right-anchored plate `min(780, w-48) × min(660, h-82)`, all geometry computed from `let` expressions, `show:`-gated groups |
| Logic | `shell/mooi-nexus.luau` (658 lines) | Palette, media state, identity, layout persistence, allowlisted collectors |
| Pure helpers | `shell/lib/nexus.luau` (385 lines, 195 unit tests) | Module catalogue, layouts, device rows, battery text |
| Data | Pleamar services + allowlisted commands | `workspaces clock audio brightness battery network bluetooth media files env`; `cat df uname hostname sensors hyprctl mooi zenity` |
| Persistence | `settings.json` via `shell/lib/config.luau` | Schema v1, dotted paths, atomic writes, `MOOI_SAFE` |
| Tests | `bin/mooi check`, `tests/unit/run.lua`, `tests/nexus.sh` | 5 scenes compile, 195 unit tests, 66 isolated live checks |

Facts:

- The plate draws 11 hardcoded modules in three bands plus five mutually exclusive header views and a 114 px identity band (the banner image itself is still declared at 74 px — an inconsistency this design removes by deriving the band from the configured mode).
- **There is no node system.** `shell/mooi-nexus.luau:470-658` contains a `Node model (D90+)` stub: `node_registry` is never seeded, every `focus_node`/`add_node`/`remove_node`/… function is never called, and the `nx_node_*`, `nx_connection_*` facts are never read. The scene instead paints literal debug text (`"NX_NODE_COUNT"`, `"NX_LAYOUT_VARIANT"`, …) at `0,0`. This is unratified scaffolding and is deleted in S1.
- No applications/window provider, no notification service outside the bar's Signal Loom, no project model. Those modules therefore ship as unavailable library entries, not fake nodes.

### Language constraints that shape the design

From Pleamar 0.4.6 / language 0.4:

- Rules cannot write record fields; facts can be written. **Node coordinates, drag offsets, selection and focus are therefore facts**, not model fields.
- `show: expr` on groups, boxes and zones is the visibility mechanism. What is not shown is not a zone.
- `for r in rows` unfolds only over records that exist, and inside it `r.field` is usable as text or number.
- `include "part.plm"` splices a `part` into the scene with full access to the scene's facts and lets. Libraries (`import`) only declare `let`, `spring` and `component`.
- `time` exists only if the scene names it, and stops under reduced motion.
- One scene owns one keyboard clause. Nexus already owns its own.
- Live text and drawn text are budgeted; the existing 60 ms view-then-panel workaround for the text-culling quirk is retained where a panel follows a view change.

**Consequence:** each edge that must track a drag at frame rate is drawn by a per-edge component call fed live coordinate facts. A model-driven edge list would only update after a logic round-trip and is not used for the core graph.

---

## 3. Design language

The six permanent directions apply as one system:

- **Spatial:** a central core, orbiting domains, layered surfaces, depth through scale and opacity rather than gratuitous blur.
- **Industrial:** chamfered octagonal housings, header rails, port nubs, thin separators, monospaced numerals, technical micro-labels.
- **Organic:** spring-based repositioning, continuous connection endpoints, directional easing, no abrupt layout jumps.
- **Minimal:** generous negative space, one detail body at a time, short labels, removability everywhere.
- **Cyberpunk:** restrained mint/cyan and amber signal light, glows only on live state, dark graphite surfaces.
- **Playful:** direct manipulation, magnetic alignment, inspectable edges, safe reversible customization.

All colour comes from Ferrolume roles (`fr_*`) and semantic tokens (`c_*`). No literal hex in node, edge or panel code.

---

## 4. Surface and global layout

One full-window surface: `kind: window`, `size: full, full`, `level: overlay`, `keyboard: exclusive`. `PIN` locks the arrangement against drag and resize (the old "stay open on outside press" meaning has no outside left to press); `×` closes after the existing 240 ms exit. `Escape` resolves in order: close the topmost panel or menu, else cancel an active drag and restore its start position, else clear the selection, else close Nexus. The plate's outside-press-to-close zone is removed.

Five bands:

| Band | Height | Contents |
| --- | --- | --- |
| Header | 44 px | Arch mark, `CONTROL NEXUS` + active mode, `CIRCUIT │ MINIMAL`, arrangement chips, `+ NODE`, `LAYOUT`, `PIN`, `×` |
| Identity banner | `FULL 114` / `COMPACT 74` / `STRIP 44` / `HIDDEN 0` | Avatar, name, tagline, clock, date, workspace, optional image with scrim |
| Canvas | remaining | Node field, optional grid and circuit traces behind nodes |
| Status strip | 30 px | Focus name, node/edge counts, load · mem · temp · net summary, edge style, theme, keyboard hint |

- Canvas gutters are 20 px. Node coordinates are canvas-relative, so changing banner height never moves a node.
- The banner's configured mode is the single source of truth for its height; the image is declared at band size. The editor sets the mode.
- Global navigation is **not** duplicated. The header only controls the workspace.
- **Responsive:** no pan/zoom. Positions clamp into the canvas; `fit` proportionally rescales the arrangement when the canvas shrinks below its bounding box; `TIDY` re-packs overlapping nodes onto the grid. Below 720×420, the banner collapses to `STRIP` and the status strip hides.

---

## 5. Node model

### 5.1 Registry — `shell/lib/nexusnode.luau` (pure)

Each type declares:

```lua
{
  id = "cpu", title = "CPU", category = "system",
  accent = "phos",                   -- Ferrolume role name
  size = { w = 220, h = 132, min = { 180, 96 }, max = { 420, 280 } },
  presets = { S = ..., M = ..., L = ..., detail = { 560, 380 } },
  capabilities = { focus = true, resize = true, expand = false, duplicate = false, removable = true },
  provider = "cpu",
  body = "cpu",
  availability = "connected",        -- or { "unavailable", "No window provider" }
}
```

The scene never hardcodes a module list; the library and the renderer read this table.

**One instance per type in this increment.** The data model allows `instance.id != type`, so duplication can arrive later without a schema change; `duplicate` is false for every shipped type.

### 5.2 Instance state

Max 16 instances. Per instance: type, canvas `x/y`, `w/h`, `visible`, `minimized`, `expanded`, `essential`, `config`, and implied z-order (selected raises, focused is top). Positions and visibility are facts persisted by logic; content is not stored per instance.

### 5.3 Frame

`NFrame` component: chamfered octagonal housing, thin header rail with category glyph, title and state dot, body slot, port nubs derived from the node's edges, corner resize grip, menu affordance. States: normal, hovered, selected, focused, dragging, minimized (rail only), collapsed (single reading), expanded, disabled, loading, warning, error. `connecting` is defined for the later user-link stage and unused before then.

Compact body: title, primary reading, unit, sparkline or bar, one supporting line, and up to two inline actions (mute, play/pause, focus workspace). Never a wall of numbers.

### 5.4 Dragging and resizing

- Press arms; movement past 4 px lifts the node.
- The lifted copy follows `drag.dx/dy`; connection endpoints read the same offsets, so paths track at frame rate.
- Release emits a drop. Logic clamps to canvas, snaps to an 8 px magnetic grid (configurable off), records undo, and persists once.
- Alignment guides appear within 6 px of another node's edge or centre.
- `Escape` cancels and restores the pre-drag position; `Ctrl+Z`/`Ctrl+Shift+Z` undo/redo the last 20 layout operations.
- Corner grip resizes within the type's min/max, snapped to the grid.
- Keyboard: `Tab`/`Shift+Tab` cycle nodes, arrows move one grid step, `Shift+arrow` four, `Enter` focuses at centre, `Delete` removes from layout, `Escape` clears selection.

### 5.5 Focus at centre

`nx_focus` holds a type id. Focusing:

1. Animates the chosen node to the centre at its `detail` size.
2. Swaps the previous centre into the vacated slot.
3. Leaves every other node exactly where it was.
4. Re-anchors edges to the new endpoints.
5. Renders that module's detail body in the centre.

`RESTORE CENTRE` re-focuses `core`; each arrangement stores its own focus. The Core stays an ordinary removable node.

### 5.6 Removal and restoration

Removal is layout-only and never touches a service. Removed nodes live in the Module Library and can be restored to a free slot or the last pointer position. `RESET NODE` restores type defaults; `RESTORE DEFAULT LAYOUT` rebuilds the shipped arrangement without deleting user arrangements.

---

## 6. Connection engine

### 6.1 Authored graph — `shell/lib/nexusgraph.luau` (pure)

Edges connect types; instantiation keeps only edges whose endpoints exist.

**Trunks:** `core → system`, `core → network`, `core → audio`, `core → workspaces`, `core → storage`.

**Satellites:**

| From | To | Meaning |
| --- | --- | --- |
| cpu | system | load |
| memory | system | memory |
| gpu | system | graphics |
| thermal | system | thermals |
| power | system | power |
| storage | system | capacity |
| storage | files | storage |
| network | throughput | receive/transmit |
| audio | media | playback |
| workspaces | applications | windows (unavailable: not drawn) |

Every edge carries a label and a meaning string shown on hover. An edge for an unavailable module is simply absent.

### 6.2 Routing and rendering

- Orthogonal traces, 12 px chamfered elbows, 12 px clearance around node bounds, deterministic dogleg when blocked. Pure and unit-tested; stable between frames.
- One component call per edge with the two live endpoint facts plus drag offsets.
- Styles: `circuit` (default), `curved`, `direct`. Thickness 1–2 px, brightness, label visibility, Core bus visibility and animation speed are configurable.
- Signal markers move only on edges with real activity (reading above its idle threshold, active playback, non-zero rate) and stop when activity stops.

### 6.3 Interaction

Hover inspects; click selects an edge and highlights both endpoints; focus isolates the focused node and its immediate neighbours while unrelated edges recede; per-edge hide/show; `RESTORE FULL NETWORK`.

User-created links are deferred. When added, they are dashed and tagged `VISUAL`, and never claim behaviour.

**Caps:** 16 nodes, 24 drawn edges.

---

## 7. Module catalogue

**Connected (can appear in the default workspace):** Core, System (load/memory/temp/uptime aggregate), CPU, Memory, GPU, Thermal, Storage, Network, Audio, Display, Workspaces, Media, Clock, Power/Battery.

**Detail bodies absorb the old views:** System is the existing SYSTEM overview; Audio holds routing, microphone and Bluetooth plus a Mixer section for per-stream volume and mute; Workspaces is the existing SPACES grid; Display covers brightness and monitors. The plate's volume and mute controls live in the Audio compact node, brightness in Display. No verified capability is dropped.

**Unavailable, library-only, visibly disabled with a reason:** Applications, Projects, Notifications, Quick Actions, Files.

**Default arrangement:** Core at centre; System, Network, Storage, Audio, Display, Workspaces, Clock as satellites; Media appears only while a player is active; Power appears when a battery exists. Eight anchors always, up to ten with Media and Power, so the canvas keeps negative space.

Default positions are generated from canvas ratios (not fixed pixels), then edited freely:

| Node | Ratio (x, y) |
| --- | --- |
| core | 0.50, 0.50 |
| system | 0.72, 0.42 |
| network | 0.80, 0.20 |
| storage | 0.76, 0.70 |
| audio | 0.30, 0.44 |
| clock | 0.22, 0.20 |
| workspaces | 0.24, 0.72 |
| media | 0.50, 0.84 |
| display | 0.62, 0.70 |
| power | 0.88, 0.55 |

---

## 8. Views and arrangements

Two modes,

- **CIRCUIT** — the full environment.
- **MINIMAL** — only nodes marked essential; banner `STRIP` or `HIDDEN`; no grid, no Core bus, no decorative traces; only activity-bearing edges.

An **arrangement** captures: mode, every node (type, position, size, visibility, essential, expansion, config), focus id, edge style plus per-edge visibility, banner mode and appearance. Eight maximum, names unique and ≤16 characters.

Shipped arrangements: `FULL` (circuit), `FOCUS` (circuit, reduced set), `MINIMAL` (essential only). They seed the Essential/Balanced/Advanced presets from the brief.

Spatial view is deferred until a window provider exists; Telemetry lives in the System and Network detail bodies; Custom is a saved Circuit arrangement. Switching arrangements morphs positions over ~320 ms without remounting.

---

## 9. Identity banner

Modes `FULL 114`, `COMPACT 74`, `STRIP 44`, `HIDDEN 0`, set in the identity panel.

Fields: avatar (image or initial), editable display name, tagline, clock, date, workspace, session, optional banner image with fit/fill and a focal offset, all with a graded scrim for contrast. Per-element visibility. Name ≤48 characters, no control characters, validated before save. Image selection uses `zenity` then `mooi identity avatar|banner <path>`, as today.

Profile data stays independent of the Linux account.

---

## 10. Customization surfaces

- **Node menu** (right-click, menu key, frame affordance): Focus at Centre, Expand/Collapse, Minimize, Configure, Connections, Remove from Layout, Reset Node. Only valid actions appear.
- **Node settings:** size preset, label/sparkline visibility, accent role, refresh, reset.
- **Module library:** search, category tabs, availability badges, `NOT CONNECTED` cards disabled with a reason, add at pointer or first free slot.
- **Appearance panel:** accent role, brightness, contrast, surface opacity, glow, edge brightness/thickness/style/speed, grid, reduced-motion override. Values are enums/numbers, never hex; brightness and contrast are applied by mixing the Ferrolume roles toward the palette's extremes, so theme changes still propagate.
- **Arrangements bar:** switch, save, rename, delete, restore.
- **Identity panel:** as §9.

All customization is reversible; no destructive confirmation is needed for layout changes.

---

## 11. Live data

Providers are keyed behind a small table in `mooi-nexus.luau`; pure formatting stays in `lib/`.

| Provider | Source | Cadence |
| --- | --- | --- |
| clock, workspaces, media, audio, brightness, battery, network, bluetooth | Pleamar services | event-driven |
| cpu, memory, temperature, root storage, network rates | `/proc/stat`, `/proc/meminfo`, `sensors -j`, `df -Pk /`, `/proc/net/dev` | 2 s |
| GPU | `/sys/class/drm/card*/device/gpu_busy_percent` when present | 2 s |
| static identity (distro, kernel, host, uptime, CPU model, displays) | `/etc/os-release`, `uname`, `hostname`, `/proc/uptime`, `/proc/cpuinfo`, `hyprctl monitors -j` | once |

Every node body is gated by availability and has explicit `loading`, `live`, `stale` (no sample in 3× interval), `unavailable`, `denied` and `error` states plus last-good time. Missing sources show `N/A`, never a guess. No value is interpolated into a command. Sampling stops when Nexus closes. User controls are batched at 40 ms; failures surface in the status strip.

---

## 12. Architecture and file map

```
shell/
  mooi-nexus.plm            rewritten full-window scene, includes parts
  mooi-nexus.luau           providers, layout persistence, actions, undo
  lib/
    nexus.luau              existing pure helpers (kept)
    nexusnode.luau          registry, instance validation, defaults
    nexusgraph.luau         authored edges, instantiation, routing
    nexuslayout.luau        snap, clamp, fit, tidy, focus swap, overlap
    config.luau             + schema v2 kinds and migration
  ui/nexus/
    frame.plm               NFrame library component
    edge.plm                NEdge library component
    nodes.plm               per-type compact bodies (part, included)
    details.plm             per-type detail bodies (part, included)
    banner.plm              banner modes and identity summary (part)
    chrome.plm              header, status strip, arrangement chips (part)
    library.plm             module library (part)
    panels.plm              node settings, appearance, identity (part)
```

Parts are used where the code needs the scene's facts and lets; libraries are used for `NFrame`/`NEdge`, which take everything as parameters.

### Fact map

| Fact | Meaning |
| --- | --- |
| `nx_<type>_on` | type present in the current arrangement |
| `nx_<type>_x/y/w/h` | persisted canvas geometry |
| `nx_<type>_vis/min/sel/exp` | visibility, minimized, selected, expanded |
| `nx_drag`, `nx_drag_dx/dy` | active drag target and live offset |
| `nx_focus` | focused type id |
| `nx_resize`, `nx_resize_dw/dh` | active resize and live delta |
| `nx_edge_count`, `nx_edge_<id>_on` | drawn edges and per-edge visibility |
| `nx_mode` | `circuit` \| `minimal` |
| `nx_banner_mode` | `full` \| `compact` \| `strip` \| `hidden` |
| `nx_<type>_*` | content readings and detail rows, all guarded by `_on` |

Rules write only facts; logic writes persisted config. No scene rule writes a record field.

### Caps

16 nodes, 24 edges, 8 arrangements, 20 undo entries, 16-character arrangement names.

---

## 13. Persistence — schema v2

New validated config kinds:

| Key | Kind | Rules |
| --- | --- | --- |
| `nexus.arrangements` | `arrangements` | ≤8; each validated field-by-field; unique names ≤16 chars |
| `nexus.nodes` | `node_list` | ≤16; known types only; coordinates clamped; sizes clamped per type |
| `nexus.focus` | `text`/enum of type ids | falls back to `core` |
| `nexus.mode` | enum `circuit\|minimal` | default `circuit` |
| `nexus.banner.mode` | enum `full\|compact\|strip\|hidden` | default `compact` |
| `nexus.appearance.*` | enums/ints/bools | accent role, brightness, contrast, opacity, glow, grid, motion |
| `nexus.edge.style` | enum `circuit\|curved\|direct` | default `circuit` |
| `nexus.edge.width` | enum `1\|2` | default `1` |
| `nexus.edge.animation` | bool | default true |

Migration v1 → v2 maps `nexus.layout` / `nexus.modules` / `nexus.layouts` into a `FULL` arrangement; legacy keys become read-only and are no longer written. A one-time `settings.v1.bak` is kept.

Writes are atomic and debounced to drag/resize end, never per frame. Unknown types, dangling edges and duplicate arrangement names are dropped; missing focus falls back to `core`. `MOOI_SAFE=1` still disables all writes. Restoring defaults rebuilds only the shipped arrangement.

---

## 14. Motion and accessibility

- Named springs only, shared with the rest of mooi; positional changes animate, telemetry does not.
- Focus transitions ~320 ms; node lift/drop 180 ms; panel reveal 200 ms; edge style changes cross-fade.
- `--reduced-motion` and the appearance override disable travel and signal markers while preserving state changes.
- Keyboard map as in §5.4 plus `Escape` to close panels, `Ctrl+Z`/`Ctrl+Shift+Z` for layout undo/redo.
- Every node, edge and control exposes `label:`, `role:`, `value:`, `checked:` and `selected:` for the agent interface and screen-reader-equivalent description.
- Text contrast meets the platform's readable minimum against graphite surfaces in both palette directions.

---

## 15. Performance

- No continuous full-scene redraw: `time` is not named globally; signal markers are driven by a 40 ms tick only while at least one active edge exists.
- Telemetry at 2 s; static data once; controls batched at 40 ms.
- Routing recomputed per edge from facts, with no per-frame allocation loops and a 24-edge cap.
- Text budget: one detail body at a time, compact labels ≤18 characters, no duplicate summary text across bands.
- Loading, stale and unavailable states are painted, never blank.

---

## 16. Staging

**S1 — Model, no visible change.** Delete the D90 stub and debug text; record the removal in `DECISIONS.md`; add `nexusnode`, `nexusgraph`, `nexuslayout`, schema v2 + migration; unit tests. The plate behaves exactly as before.

**S2 — Workspace shell.** Full-window frame with header, banner modes, canvas and status strip. The plate's 11 modules are mapped into the node catalogue rather than copied one-to-one: output and display become Audio and Display nodes, CPU/memory/temp fold into System with CPU, Memory and Thermal still available separately, RX/TX fold into Network, and the player becomes Media. Every module gains drag, snap, resize, select, minimize, remove/restore and persisted geometry. A temporary `VIEWS` drawer keeps SYSTEM/AUDIO/MIXER/SPACES reachable until S3.

**S3 — Centre focus.** Detail bodies for all connected modules at centre; focus swap, return, undo; delete the temporary drawer.

**S4 — Connections.** Authored graph, routing, styles, hover inspection, isolation, activity markers, counts.

**S5 — Library and customization.** Module library with honest unavailable cards, node settings, appearance panel, identity/banner editing, arrangements, Minimal mode.

**S6 — Polish.** Full keyboard map, reduced motion, focus rings, performance pass, documentation updates.

Each stage must compile, pass `bin/mooi check`, pass the unit suite and `tests/nexus.sh`, and be individually revertable.

---

## 17. Testing

**Unit (`tests/unit/run.lua`):** registry validation and defaults; edge instantiation including unavailable endpoints; routing determinism, clearance and doglegs; snap/clamp/fit/tidy; focus swap and restore; migration v1→v2; arrangement limits and name rules; provider state machine; keyboard move steps; undo/redo.

**Integration (`tests/nexus.sh`, isolated lab runtime only):** scene starts; `describe` exposes nodes, edges and panels with agent labels; synthetic press/drag/release moves a node and the persisted position changes; focus-at-centre swaps ids and keeps the previous centre available; library add/remove/restore; Minimal hides non-essential nodes; arrangement save and restore round-trips; edge counts match the graph; unavailable modules never appear in the default arrangement; banner mode changes height; text presence guards the text-culling quirk.

**Never** restart or interfere with the user's live session; all live checks run against the isolated `mooi-lab` copy.

---

## 18. Risks

| Risk | Mitigation |
| --- | --- |
| Text budget / culling | one detail body, short labels, existing 60 ms pattern, text assertions in tests |
| Fact growth | one instance per type in v1, `_on` gates, 16-node cap |
| Frame cost with drag + edges | 24-edge cap, per-edge component calls, markers only on activity, 40 ms tick |
| No pan/zoom on small screens | `fit`, `TIDY`, banner auto-collapse, documented limitation |
| Migration data loss | atomic write, `settings.v1.bak`, migration unit tests |
| Feature loss mid-sequence | `VIEWS` drawer until S3 parity, legacy layout keys kept for one release |
| Live session interference | isolated runtime for every check |

---

## 19. Acceptance criteria

1. Nodes can be dragged and repositioned; positions persist. (S2)
2. Connections follow their nodes during and after a drag. (S4)
3. Any connected node can become the centre. (S3)
4. The previous centre remains available as a node. (S3)
5. Nodes can be added from the Module Library. (S5)
6. Removing a node leaves its service untouched. (S2)
7. Modules can be hidden or minimized. (S2)
8. The banner is independently customizable, including mode and height. (S5)
9. At least two modes plus eight arrangements save and restore. (S5)
10. Minimal mode shows only essential nodes. (S5)
11. Edge style, thickness, brightness and animation are configurable. (S4)
12. All metrics come from real providers or show `N/A`. (S1/S6)
13. Layouts persist across restarts. (S2)
14. The default arrangement restores safely. (S2)
15. The interface stays responsive at 16 nodes / 24 edges. (S6)
16. Keyboard navigation and reduced motion work. (S6)
17. The existing mooi/Pleamar architecture remains intact. (all)
18. The result reads unmistakably as mooi, not a generic dashboard. (all)

**Deferred by decision:** Spatial view (needs a window provider), user-created visual links, pan/zoom, duplicate instances, notifications/projects/quick-action providers. All are represented in the library as `NOT CONNECTED` rather than faked.
