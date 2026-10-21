# Twisting Triangular Chain — Design Spec

**Status:** Draft (approved) — **superseded 2026-10-16** by the renewed design and its port, then by that design's slim v4, then by its exposed v5, and now by its **horizontal v6** (docs/DECISIONS.md **D13**, **D14**, **D15** and **D16**; `pleamar helix bar/helix-v2-mooi/`)
**Path:** Architectural (brainstorming → design → spec → plans)
**Date:** 2026-10-15

## 1. Problem statement recap
Replace rectangular ticks (Tick component) in Region B with a twisting triangular chain: one triangle per workspace, alternating orientation (up/down), forming a connected vertical sequence. On workspace change the entire chain executes a coordinated mechanical twist (directional wave) — not rigid spin, not flat list. Wheel UI stays above the chain; chain is under wheel as modular moving mechanism. Supersedes triangular prism. Constraints: Pleamar 0.4.6, Hyprland, existing architecture preserved. No silent wrap (clamp). All existing tests green.

## 2. Goals
- Visual form: continuous chain of triangles, alternating up/down, connected links between consecutive positions.
- Motion: global index-driven helical twist (anchor C). Cumulative by workspace index i with small per-step angle k*i plus transition phase φ(t_dir) for directional wave on change. Interruptible via existing springs.
- Interactions: each triangle clickable (ws_pick), hover/enter sets nav_sel while nav_open, scroll/keys work, boundaries clamped.
- Preserve contracts: nav_open/engaged selection, keyboard claim rules, boundary policy (clamp no wrap), external Hyprland sync via `spaces` model, preview≠commit.
- Keep scene arithmetic (no forbidden conditionals in draw). Follow Pleamar 0.4.6 constraints.

## 3. Anchor & transformation (global index-driven helical)
Positions i = 0..n-1 in order of workspace ids shown (1..ws_max). 
- Base twist per index: θ_i = k * i + φ(t), k = 8° (proposed). φ advances over 150–250ms on nav change (directional wave). 
- Lateral offset from rail axis g.rail_x: x_i = A * sin(θ_i), A = 6 (proposed), clamped so chain stays inside rail visual width (reserve 72 unchanged).
- Vertical: center Y_i = scale_y + i*g.tick + B*sin(θ_i), B=2 (subtly mechanical). Pitch preserved (g.tick).
- Orientation: orient_i = (i % 2 == 0) ? up : down. Triangle drawn in local coords, transformed to (x_i,Y_i,θ_i) in scene group.
- Depth read: width/scale varies subtly with |sin(θ_i)| (mix) to enhance 3D feel without heavy effects.

## 4. Geometry (numbers)
- Rail: g.spine 72, g.rail_x 30.
- Wheel: wheel_y=100, wheel_r=18, 300° arc over arcs=max(spaces.count-1,1).
- Triangle: w_t=24, h_t=20 (proposed). Connectors between (Y_i + h_t/2_dir?) to (Y_{i+1} - h_t/2_{opp}) as thin stroke along chain.
- Active: #A0E8CF (accent.primary). Pointed: focus.ring outline. Missing/exists/windows states influence triangle weight/stroke via tone (blend), arithmetic.
- No silent wrap: clamp all moves (scroll/wheel/keys).

## 5. Components (mechanism.plm)
Add `Triangle` component:
```text
component Triangle(w: record, orient_up: bool, tx:number, ty:number, rot_deg:number) {
  size: 24,20
  let here=w.active; let pointed=nav_open and w.id==nav_sel
  zone box hit { from: -12,-10; size:24,20; cursor:pointer; role:button; label:"WS {w.id}" }
  // draw triangle in local coords (point up/down), transformed by group
  ...
  on enter hit while nav_open { nav_sel=w.id }
  on press hit { emit ws_pick(w.id); nav_open=false }
}
```
Transforms applied in scene group (pivot center). Tone arithmetic: mix fg/border/accent by exists/windows/active.

## 6. Scene changes (mooi.plm Region B)
Replace column rail loop (lines ~314–317) with:
```text
group chain {
  for w in spaces {
    let i = w.index  (0-based)
    let th = k*i + phi
    let cx = g.rail_x + A*sin(th)
    let cy = scale_y + i*g.tick + B*sin(th)
    group { pivot:cx,cy; rotate:th*1deg
      Triangle(w, (i%2==0), 0,0,0)
    }
    // connectors between consecutive (optional thin line)
  }
}
```
Keep spine line, carriage (trav follows active triangle Y), wheel above, scale zone or rely on per-triangle hits. Wheel/keys/scroll rules unchanged (clamp). Boundary policy unchanged.

## 7. Motion & state
- φ driven by events wheel_step/nav keys/change via spring (m.select/m.dial), 150–250ms, interruptible.
- Carriage/dial follow same truth (active_row/nav_sel). Preview≠commit preserved.

## 8. Files touched
- `shell/ui/mechanism.plm`: add Triangle; optionally keep Tick (not used) or leave.
- `shell/mooi.plm`: Region B chain group replaces column rail; ensure hit zones don’t block wheel (wheel above). 
- No Luau logic changes required (spaces unchanged).

## 9. Testing/verification
- `bin/mooi check` passes. All existing suites (unit/scene/integration/degraded/config-recovery/theme) remain green. Scene compile stats comparable.
- Manual sanity: chain connected, alternates, active mint, nav_open preview works, clamp at ends, wheel UI above.

## 10. Recommendation
Approach A (scene-only). k=8°, A=6, B=2, triangle 24×20.

@54@