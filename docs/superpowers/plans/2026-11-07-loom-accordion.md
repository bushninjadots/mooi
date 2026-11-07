# Loom / Fold Phase 2 — the Accordion: plan

> Spec: docs/superpowers/specs/2026-11-07-loom-fold-design.md §4.1 (approved 2026-11-07, "cool go").
> Executed inline (superpowers:executing-plans).

## Constraints
- Real windows only through `lib/hypr`; a structure's windows park on `special:loom-<sid>`; every move
  `follow = false` except the deliberate focus of a pulled layer.
- One zone per strip (hover and presses read the pointer's place), so the strip's hover never splits.
- Pleamar lets clicks through wherever there is no zone: the strip covers nothing else of the screen.
- Native mooi unchanged; the feature only exists when `lib/loommode` says `accordions` is on.
- Every operation that moves windows is journaled (`lib/loom.journal_begin/end`).

## Tasks
1. `shell/lib/loomaccordion.luau` (pure): create, add (the added window becomes the one in use, the
   previous one parks), pull (one in use at a time), push, step (next/previous), open all (tiled on the
   current workspace), fold (all parked), remove, dissolve, reorder, the active accordion for a window,
   rows for the scene. `lib/loompark.unpark` gains a target workspace. Unit tests.
2. `shell/mooi-loom.luau`: reads settings (mode, switches, edge), runs plans (commands in order, then the
   records, journaled, saved), feeds the scene's models, drops a member whose window closes while running
   (kept when absent at start: a restart), unparks every accordion if the feature is turned off.
3. `shell/mooi-loom.plm` + `shell/ui/loomstrip.plm`: the theme's palette facts; a strip per accordion at
   the chosen edge — compressed (thin machined layers, the one in use slid out and lit), extended on hover
   (rows: the app's initial, the title), a press pulls, the right press removes, the wheel steps, a drag
   reorders, the spine's right press dissolves.
4. Settings → Loom / Fold: Fold, Accordions (needs Fold), Strip edge. `lib/loommode`: fold and accordions
   built.
5. Keys: `mooi loom add|next|prev|fold|open|remove`; Hyprland binds Super+Alt+A / ] / [ / F / O / R in
   `custom/mooi.lua` (checked free first), copied to setup.
6. Live suite on probe windows opened onto hidden workspaces; docs; commit only this work.
