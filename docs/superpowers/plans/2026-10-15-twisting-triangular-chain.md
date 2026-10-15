# Twisting Triangular Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace rectangular workspace ticks in Region B with a twisting triangular chain (one triangle per workspace, alternating up/down), forming a continuous connected vertical sequence with global index-driven helical twist on navigation changes.

**Architecture:** Scene-only approach (A). Keep existing wheel UI above the chain, chain under wheel. Preserve rail geometry (g.spine 72, g.rail_x 30), wheel (wheel_y=100, 300° arc), no silent wrap (clamp), nav_open/engaged selection, keyboard claim rules, preview≠commit. Chain elements are triangles drawn per workspace in a transformed group loop; each triangle is clickable with hit zone. Transforms use arithmetic (no forbidden conditionals in draw). Spaces model unchanged.

**Tech Stack:** Pleamar 0.4.6 scene language (.plm), Luau (.luau) logic unchanged. Existing tokens/components.

**Spec:** docs/superpowers/specs/2026-10-15-twisting-triangular-chain-design.md

## Global Constraints
- Pleamar 0.4.6 only; no Quickshell.
- Rail: g.spine 72, g.rail_x 30. Wheel: wheel_y=100, wheel_r=18, 300° arc.
- Triangles 24w×20h, alternating up/down. Global index-driven helical twist (cumulative by index). No silent wrap (clamp).
- Active triangle uses accent #A0E8CF. Pointed uses focus.ring.
- Keep existing architecture; all existing tests must remain green.
- Arithmetic in draw (no if for numbers/colours in forbidden forms) — use pick/mix.
- Keyboard claim rules preserved; boundary policy preserved.
- Preview≠commit, interruptible via existing springs.

## Review Focus
- **Boundary clamp at ends:** scrolling/wheel/keys in nav_open and out must not wrap (e.g. at 1 and ws_max) — test boundary cases.
- **Per-triangle hit zones:** clicking triangle must emit ws_pick(w.id); hover/enter sets nav_sel while nav_open — test hit accuracy.
- **Chain connectivity/readability:** alternating orientation and connectors present; active clearly mint — visual contract preserved functionally.
- **External sync:** spaces updates (add/remove workspace) must redraw chain correctly — test model changes.
- **Interruptible motion:** twist phase interrupted mid-transition should settle correctly — test rapid nav changes.

---

### Task 1: Add Triangle component to mechanism.plm
**Files:**
- Modify: `shell/ui/mechanism.plm`

**Interfaces:**
- Produces: `Mechanism.Triangle(w, orient_up, tx, ty, rot_deg)` component (scene element) with hit zone emitting ws_pick on press, setting nav_sel on enter while nav_open, uses arithmetic tone.

- [ ] **Step 1: Write the failing test (conceptual)** — understand current Tick usage. (No new test file required if existing scene tests still compile; verify compilation.)
  - Verify scene compiles after adding Triangle by running `bin/mooi check`.

- [ ] **Step 2: Add Triangle component**  
  Add component after Tick (or before Status/others) in `shell/ui/mechanism.plm`. Exact signature/behavior:
  - size 24,20
  - orient_up bool, tx,ty,rot_deg numbers
  - hit zone from -12,-10 size 24,20, cursor pointer, role button, label "WS {w.id}", selected when here or pointed
  - draw triangle: if orient_up, vertices at (0,-10),(12,10),(-12,10); else (0,10),(12,-10),(-12,-10). Fill with tone = mix(mix(fg.muted,border.subtle,w.exists), accent.primary, here). Stroke 1 with mix(border.subtle,focus.ring, pointed). Also subtle hover fill.
  - on enter hit while nav_open { nav_sel = w.id }
  - on press hit { emit ws_pick(w.id); nav_open = false }

  Use arithmetic only (no if). Example:
  ```text
  let here = w.active
  let pointed = nav_open and w.id == nav_sel
  let tone = mix(mix(fg.muted,border.subtle,w.exists), accent.primary, here)
  zone box hit { from:-12,-10; size:24,20; cursor:pointer; role:button; label:"WS {w.id}"; selected:here or pointed }
  path { stroke:1; color:mix(border.subtle,focus.ring,pointed); fill:tone; move: pick(orient_up,0,-10,0,10); line:pick(orient_up,12,10,12,-10); line:pick(orient_up,-12,10,-12,-10); close }
  box { from:-12,-10; size:24,20; color:fg.primary; opacity:hit.hover*0.25 }
  on enter hit while nav_open { nav_sel=w.id }
  on press hit { emit ws_pick(w.id); nav_open=false }
  ```

- [ ] **Step 3: Verify compilation**  
  Run: `cd /home/user/Projects/mooi && bin/mooi check 2>&1 | tail -15`  
  Expected: "check passed" (or no errors). Scene compiles.

- [ ] **Step 4: Commit**  
  ```bash
  git add shell/ui/mechanism.plm
  git commit -m "feat(mechanism): add Triangle component for twisting chain"
  ```

### Task 2: Replace Tick rail with twisting triangular chain in mooi.plm (Region B)
**Files:**
- Modify: `shell/mooi.plm`

**Interfaces:**
- Consumes: `Mechanism.Triangle(w, orient_up, tx, ty, rot_deg)`
- Uses existing: `spaces` model, `nav_open`, `nav_sel`, `active_row`, `scale_y`, `g.tick`, `g.rail_x`, `wheel_y`, `wheel_r`, `arcs`, `needle_id`, `needle`, motion props (`m.select`, `m.dial`)

- [ ] **Step 1: Add twist state/params**  
  In scene, add twist parameters (arithmetic-friendly):
  - `let chain_k = 8` (deg per index)
  - `let chain_A = 6` (lateral amplitude)
  - `let chain_B = 2` (vertical ripple)
  - `let phi = 0` (transition phase) — can be driven by events via prop if desired later; start 0.

  (Or just inline expressions; no new facts required.)

- [ ] **Step 2: Replace column rail with chain group**  
  In Region B (around line ~308–317), remove `column rail { for w in spaces { Tick(w, bar_labels) } }`. Add `group chain` under wheel:
  - iterate over spaces in order (spaces is bounded map in order 1..ws_max; in scene `for w in spaces` gives rows)
  - for each w compute i = w.index (0-based) — spaces rows from lib/spaces.luau are 0-based index in list? Check: rows built as out[#out+1] for id=1..limit; scene accesses `spaces.$j` by index. In column loop, `for w in spaces` gives elements with fields; w.index may not exist. Use index: in repeat/for over model, can use position? Alternatively track by id order: iterate by generating i from position. Easier: in scene loop, derive i as (w.id - 1).
  - th = chain_k*i + phi
  - cx = g.rail_x + chain_A*sin(th)
  - cy = scale_y + i*g.tick + chain_B*sin(th)
  - orient_up = (i % 2 == 0)
  - render Triangle(w, orient_up, 0,0,0) transformed via group pivot cx,cy rotate th*1deg (or pass rot)

  Also add thin connector lines between consecutive: for j from 0 to count-2 draw line between cy_j + (orient_up_j? -10:10?) and cy_{j+1} + (orient_up_{j+1}? +10:-10) with small opacity (0.25–0.4) to read as chain links. Use arithmetic.

- [ ] **Step 3: Keep spine, carriage, wheel, zones**  
  Keep spine line (g.rail_x vertical). Carriage (trav) already follows active_row * g.tick from scale_y — with triangular chain, vertical centers are at scale_y + i*g.tick + ripple; for active workspace i_a = active_row (0-based in list by position? active_row is index in spaces rows? lib/spaces.luau returns rows in order id=1..limit, so active_row is index of that row). Since Y_i = scale_y + i*g.tick + B*sin(th_i), and i is position index (0-based by workspace order), carriage Y should follow Y_{i_a} (use same formula for active). Also dial_y same for nav_sel-1.

  Update trav/dial_y follows to use chain Y:
  - let i_a = active_row (index in spaces list, 0-based)
  - trav follows scale_y + i_a*g.tick + chain_B*sin(chain_k*i_a + phi)
  - let i_n = nav_sel-1
  - dial_y follows scale_y + i_n*g.tick + chain_B*sin(chain_k*i_n + phi)

  Keep scale zone? Or rely on per-triangle hits. Current scale zone is box over whole span; triangles are on top. Can keep zone for scroll (backwards compat) or remove — but scroll over scale is used. Either keep scale zone (covers vertical span) and also triangles accept hits (triangles on top win). Keep scale zone as is.

- [ ] **Step 4: Verify compilation and basic behavior**  
  Run: `cd /home/user/Projects/mooi && bin/mooi check 2>&1 | tail -10`  
  Expected: check passed.

- [ ] **Step 5: Run scene tests**  
  Run: `cd /home/user/Projects/mooi && bash tests/scene.sh 2>&1 | tail -20`  
  Expected: all scene tests pass (68 state + 9 motion, 0 failed). Existing contracts preserved.

- [ ] **Step 6: Commit**  
  ```bash
  git add shell/mooi.plm
  git commit -m "feat(scene): replace Tick rail with twisting triangular chain"
  ```

### Task 3: Add directional wave on navigation (phi) and verify
**Files:**
- Modify: `shell/mooi.plm`

**Interfaces:**
- Uses existing events: `wheel_step`, nav keys (Left/Up/Right/Down), `ws_pick` results in state change (active_row/nav_sel). Add small phi animation on change.

- [ ] **Step 1: Add phi motion**  
  Add prop for phi: `prop phi = 0 ~m.select` (or new spring). On navigation events that change active selection (wheel_step when not nav_open causing ws_pick? Or when engaged changing nav_sel; twist is global by index; directional wave can be triggered on any change). Also on external changes? Keep subtle.  
  Trigger phi advance: when nav_sel changes (engaged) or when active_row changes (committed). Since events are scene-local, can do: on wheel_step while nav_open { ...; phi = phi + (d>0? sign: -sign)*chain_k*0.25 ~m.select }? Or simpler: on nav change, bump phi by small amount in direction of travel over 150–250ms. Use existing spring `m.select` (200–300ms).  
  Example: on ws_pick(n) { phi = phi + sign(n - (active_row+1))*chain_k*0.5 ~m.select } (approx). Or track last.

  But easier: add `event nav_changed(dir)` conceptually; in practice on wheel_step/nav keys when engaged, adjust phi slightly in travel direction: `phi = phi + d*chain_k*0.3 ~m.select`. On commit (ws_pick) also nudge.

- [ ] **Step 2: Verify no regressions**  
  Run scene tests: `bash tests/scene.sh 2>&1 | tail -5`  
  Expected: pass.

- [ ] **Step 3: Run all tests**  
  Run: `bash tests/unit/run.lua 2>&1 | tail -2; bash tests/integration.sh 2>&1 | tail -2; bash tests/degraded.sh 2>&1 | tail -2; bash tests/config-recovery.sh 2>&1 | tail -2; bash tests/theme.sh 2>&1 | tail -2`  
  Expected: all green (43/0, 56/0, 8/0, 13/0, 28/0).

- [ ] **Step 4: Commit**  
  ```bash
  git add shell/mooi.plm
  git commit -m "feat(scene): add directional wave (phi) to twisting chain"
  ```

### Task 4: Visual sanity & docs update
**Files:**
- Modify: `docs/MECHANISM.md` (optional but nice)

**Interfaces:**
- Documents new chain mechanism.

- [ ] **Step 1: Quick visual check (optional)**  
  If desired, start/stop: `bin/mooi start 2>&1 >/dev/null && sleep 0.5 && bin/mooi stop 2>&1 | tail -1`

- [ ] **Step 2: Update docs**  
  Update docs/MECHANISM.md to note triangular chain replaces ticks, global index-driven helical twist, wheel above chain. Keep constraints.

- [ ] **Step 3: Final verification**  
  Run: `cd /home/user/Projects/mooi && bin/mooi check && bash tests/scene.sh && bash tests/unit/run.lua >/dev/null && bash tests/integration.sh >/dev/null && echo 'ALL OK'`  
  Expected: ALL OK.

- [ ] **Step 4: Commit**  
  ```bash
  git add docs/MECHANISM.md 2>/dev/null; git commit -m "docs: document twisting triangular chain mechanism" 2>&1 | tail -2
  ```

@59@