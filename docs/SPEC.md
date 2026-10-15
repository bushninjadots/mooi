# mooi: product specification (condensed)

Condensed from the master brief (2026-10-14). The project was renamed from "Tidal Shell" to **mooi** on 2026-10-14; the brief's "Tidal" pillar is called **Flow** here. The brief is the authority on intent. This file is the working checklist, with the decisions taken since in *italics*.

## Vision: fluid structure

One coherent shell: surfaces emerge from meaningful anchors, change size only when useful, and move between compact and expanded states. The shell stays predictable, precise and keyboard-first. **Foundry** (precise structure), **Flow** (continuous motion), **Workshop** (the user edits the shell itself).

Principles: function before decoration · motion communicates something · the keyboard is first-class · compact by default · every feature has a purpose · configuration is discoverable and reversible · customization never costs stability · performance is measured · Hyprland keeps all its functionality · degrade gracefully · no AI dependency.

Avoid: generic dashboards, oversized rounded cards, decorative gradients, gratuitous glass or glow, random animation.

## 1. Modes (global)

Rest (default, minimal) · Focus (recede, contextual) · Explore (Atlas, spatial) · Workshop (edit the shell) · Ambient (quiet background info).

One explicit state model, no loose booleans. Escape dismisses the **topmost dismissible** surface only. Critical feedback outranks ambient. A surface in active use never disappears on a timer.
*Slice 1 implements Rest only. Modes will be one scene-owned enum.*

## 2. Surfaces

- **Spine**: a 44–52 px rail, left by default, configurable. It holds workspaces, launcher/command, active context, status and Workshop entry, but not everything. *Slice 1: 48 px, window context, workspaces, clock.*
- **Islands**: compact contextual surfaces with an owner, compact and expanded states, activation and dismissal, keyboard navigation, focus management, edge repositioning, interruption-safe motion, and no duplicates. *Slice 1: the window satellite.*
- **Edge Membranes**: larger surfaces unfolding from an edge (Atlas, system controls, history, Workshop) with predictable geometry, multi-monitor support and scaling.
- **Lifecycle**: hidden → entering → compact → expanded → exiting → hidden, interruptible, with one authoritative state per surface.

## 3. The six experiments

1. **Workspace Atlas**: Strip / Grid / Spatial. Real Hyprland state, keyboard and pointer, move windows, monitors, thumbnails when feasible, a privacy mode. Configurable. Not a second window manager. *Phase 4: window tiles with real previews (`thumbnails`, verified on Hyprland), a bounded workspace map with empty slots and confirmed focus, moving a window to a workspace from the Atlas, and a previews switch that gives the compositor's frames back (`p`, remembered as a setting); monitor support remains.*
2. **Contextual Satellites**: Compact / Radial (optional) / Expanded, anchored near the object. Every action maps to a real operation, with honest failure. *Slice 1 is a compact + expanded satellite for the focused window.*
3. **Morphing Command Membrane**: compact input → results → inline actions. Apps, windows, workspaces, settings. Fixed position by default. Never executes untrusted results. *Super+Alt+Space (Super+Space is toggle floating). Built in Phase 3, see ARCHITECTURE.md.*
4. **Notification Streams**: grouping, priority, quiet periods, privacy, history, actions. Never silently drops, and never claims delivery or dismissal without confirmation. *Blocked by ownership: ArchEclipse is the notification server.*
5. **Live Workshop**: Layout / Appearance / Motion / Behaviour. Hierarchy, preview, inspector, undo/redo, apply/revert, validation, recovery. Exposes only supported properties. One canonical format. *Canonical format: JSON (the only one Pleamar reads and writes).*
6. **Edge Ecosystem**: configurable edge roles and activations (click, keyboard, modifier+pointer, delayed hover, gestures). No conflicts, respects fullscreen and exclusive zones, keyboard alternatives, every activation can be disabled. Hover is off by default.

## 4. Components

A shared contract: id, name, states, properties, activations, keyboard behaviour, required and optional integrations, config schema, accessibility (*Pleamar `label:`/`role:`*), performance, fallback. Build the abstraction only after a few real components need it.

## 5. Motion

Tokens: surface.enter / exit / expand / collapse, selection.change, object.transfer, state.confirm, layout.reflow, focus.change, ambient. Profiles: Instant 0–60 · Precise 100–180 · Fluid 180–280 · Expressive 240–400 ms. Interruptible and reversible from the current visual state. Reduced motion supported. Gestures (select, expand, transfer, reorient, dismiss, confirm) are optional, with keyboard equivalents.
*Implemented as critically damped springs named `m.*` in `tokens.plm`, measured by `tests/scene.sh`.*

## 6. Theme

Palette: Void #101416 · Steel #22292D · Slate #46545A · Signal #A6F3D1 · Heat #FF925F (provisional). Semantic tokens, a 4 px grid, 8–12 px radii, mostly solid with restrained transparency. Matugen (not Wallust) supplies wallpaper colours. Pipeline: input → palette → semantic mapping → user overrides → validate → contrast → prepare → apply atomically → roll back. Layers stay separate: base, wallpaper, overrides, component, interaction, motion, performance. Themes are declarative.
*fg.muted was raised for contrast (AUDIT.md §7). Built in Phase 5's first slice: the fourteen semantic tokens are `rgb(r, g, b)` over facts the logic sets, so a theme changes while the scene runs; the pipeline (fixed → wallpaper → overrides → completeness → contrast → apply, rollback if it fails) lives in `shell/lib/theme.luau`; `bin/mooi theme-sync` runs Matugen 4.2.0 with mooi's own config and writes only the palette mooi reads. `theme.source` is `fixed` by default: wallpaper colours are opt-in. Light schemes, theme packages and an editor remain.*

## 7. Architecture

Pleamar renders, Hyprland manages; pleamar-wm is not used. A Hyprland adapter layer, no duplicated state, and the existing Quickshell setup untouched with no duplicate bars, docks or daemons. Configuration is explicit, validated, versioned and recoverable, with a safe launch. An independent repo with a dev configuration separate from the session.

## 8. Performance and reliability

60 FPS, a 16.7 ms frame budget, input-to-visible under 50 ms, near-zero idle, no polling, no memory growth. Measure startup, idle, simple and complex animation, multi-monitor and high event volume. Test repeated and rapid transitions, invalid config, missing integrations, IPC failure, resolution and scale changes, hotplug, fullscreen, session start and stop, crash recovery, reduced motion, theme failure and notification floods.

## 9. Roadmap

0 Audit ✔ · **1 First real surface ✔ (slice 1)** · 2 Motion and interaction framework ✔ · **3 Command Membrane and Satellites ✔** · **4 Workspace Atlas (first slice)** · **5 Themes and Matugen (first slice: colours)** · 6 Notifications and Edges · 7 Live Workshop · 8 Extensions and release.

## Daily-value priority

Atlas > window satellites > command interface > notifications > system controls > keyboard-first navigation > visual customization > smooth state changes.
