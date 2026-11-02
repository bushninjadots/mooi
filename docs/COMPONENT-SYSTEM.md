# Component system

_Status: foundation contract, phase 1. Last checked against main: 2026-11-02._

This document defines how reusable visual components in mooi should be built and how they will grow into the future visual editor, widget system and layout editor. It is a contract for new work and a migration target for existing work; it does **not** claim that every current component already conforms.

Related documents:
- [Architecture](ARCHITECTURE.md) — runtime and state ownership
- [Philosophy](PHILOSOPHY.md) — the six permanent design directions
- [Ferrolume](FERROLUME.md) — the current bar's specific visual language
- [Testing](TESTING.md) — verification commands and evidence

## 1. The central idea

A mooi component is a reusable visual and interaction unit. It should be possible to place the same component in a settings surface, a floating panel, a desktop widget or a future visual editor without rebuilding its behaviour from scratch.

The system shares **contracts**, not one appearance.

A component may have a distinct silhouette, material, density, motion character and expressive treatment. It must still understand the same semantic theme roles, interaction states, sizing rules, input expectations and motion preferences as the rest of mooi.

The six design directions remain inseparable:

1. **Spatial & Futuristic** — components communicate hierarchy, depth and relationships.
2. **Industrial & Technical** — geometry, alignment, construction and detail feel deliberate.
3. **Organic & Fluid** — state changes and rearrangement feel continuous and interruptible.
4. **Minimal & Elegant** — default states remain clear, compact and purposeful.
5. **Cyberpunk & Expressive** — accent, glow and effects communicate state rather than decorate everything.
6. **Playful & Interactive** — components invite exploration and customization without hiding essential controls.

## 2. Component layers

Keep four layers distinct.

| Layer | Owns | Examples in the current repository |
| --- | --- | --- |
| **Tokens and materials** | Semantic colour roles, geometry scales, motion intents and named material recipes | `shell/theme/tokens.plm`, `shell/theme/ferrolume.plm`, `shell/lib/theme.luau`, `shell/lib/ferro.luau` |
| **Primitives** | Small reusable visual/interaction building blocks with stable inputs | Buttons, toggles, sliders, readouts, frames, rules, status marks |
| **Compositions** | Feature-specific arrangements assembled from primitives and domain components | Islands, Nexus cards, Board columns, player views, Ferrolume workspace instrument |
| **Surfaces and applications** | Window/surface lifecycle, data loading, business rules, persistence and system integration | Main shell, Settings, Nexus, Notch, Lumen, Board, Player |

A lower layer must not depend on a higher layer. A primitive must not know about a particular application, invoke system commands, write user settings or decide which window/workspace should be active.

The current `shell/ui/` directory contains a mixture of primitives and feature-specific compositions. That is acceptable during migration. Do not rename or move everything in one sweep.

## 3. Public component contract

New reusable components should follow these rules.

### Inputs

- Declare every variable input in the component signature with a concrete type.
- Pass changing data in as props/parameters; do not duplicate application state inside a visual component.
- Pass actions as typed `event` inputs. The component emits an intent; the owning scene decides what that intent means.
- Provide safe defaults only for genuinely optional visual details.
- Prefer semantic inputs such as `selected`, `disabled`, `busy`, `value`, `label` and `on_change` over unexplained numeric mode codes.
- Keep dimensions explicit where the Pleamar component model requires them. Avoid baking a screen position or monitor size into a reusable control.

Existing Pleamar components sometimes read scene facts directly. Treat those as legacy scene context. New cross-surface primitives should receive their changing values explicitly; only stable imported design tokens and documented scene context may remain ambient.

### Outputs and side effects

- A component may draw, animate, expose hit zones and emit user-intent events.
- It must not execute shell commands, call Hyprland, access the filesystem, fetch remote data or mutate persistent settings.
- It must not own application workflows or make irreversible decisions.
- The containing scene or application handles validation, persistence, system calls, error reporting and recovery.

This keeps a component safe to reuse in a bar, panel, widget or editor preview.

### State model

Where relevant, components should represent these states consistently:

| State | Meaning | Expected treatment |
| --- | --- | --- |
| Rest | Available, not currently targeted | Normal material and contrast |
| Hover | Pointer is over the target | Small, clear response; never the only indication of availability |
| Focus | Keyboard/controller focus | Visible focus treatment using the semantic focus role |
| Pressed | Input is currently activating the target | Immediate tactile feedback |
| Selected | The represented option or destination is active | Persistent selected treatment, not just hover |
| Disabled | Action is unavailable | Reduced emphasis and no activation event |
| Busy | Action is in progress | Clear progress/busy feedback; prevent duplicate activation where appropriate |
| Warning / error | Attention or failure needs communicating | Semantic status treatment and explanatory text where possible |

Not every component needs every state. Do not create state visuals that the component cannot actually reach.

### Input behaviour

- A control that can be operated by pointer should have an equivalent keyboard path when the surface supports keyboard input.
- Disabled controls must not emit activation events.
- Focus must remain visible independently of pointer hover.
- Hit areas should be intentional and documented. Use the shared compact/standard/comfortable target sizes rather than shrinking the interactive zone to the visible glyph.
- Drag, scroll and gesture behaviours must not steal input from the containing surface unexpectedly.

## 4. Theme contract

### Semantic roles

Use the shared `Theme` roles for general interface meaning:

- Backgrounds: `bg.primary`, `surface.primary`, `surface.elevated`
- Text: `fg.primary`, `fg.secondary`, `fg.muted`
- Structure: `border.subtle`
- Emphasis: `accent.primary`, `accent.secondary`
- State: `status.ok`, `status.error`, `focus.ring`, `selection.bg`

These roles are resolved centrally by `shell/lib/theme.luau`. A component should not invent a parallel wallpaper palette or hard-code its own general-purpose foreground/background colours.

### Materials and identity

Semantic roles are not a demand that every surface look the same. A design language may define named materials and translate semantic roles into them. Ferrolume is the current example: its steel, trace, phosphor and ember materials create a distinct mechanical instrument while remaining connected to the shared palette.

Feature-specific materials should be:
- named and documented;
- derived from semantic roles or a deliberate theme input;
- contrast-checked for text and important marks;
- responsive to theme changes without a scene restart where the host supports live updates.

Do not use glow, blur, gradients or chromatic effects as substitutes for hierarchy or state.

## 5. Geometry and density

The shared geometry vocabulary lives in `Theme` in `shell/theme/tokens.plm`. Use it for spacing, hit targets, strokes and the common radius family.

- Use the spacing scale for gaps and padding; do not introduce arbitrary values when a scale value fits.
- Use the radius family as a baseline. A component's silhouette may intentionally be angular, chamfered or unrounded.
- Use the stroke scale for outlines and separators.
- Size the interactive target separately from the visible icon or decorative mark.
- A component may offer compact, standard and comfortable density, but density must change spacing and hit areas coherently, not merely shrink text.

The scale is a shared starting point, not a ban on measured exceptions. A special instrument, timeline, visualiser or diagram may need its own geometry. Document why.

## 6. Motion contract

Use named motion intents from `Theme` rather than assigning unrelated spring values to every new control.

Current shared intents include:
- `m.select` — selection and focus change
- `m.enter` / `m.exit` — surface arrival and departure
- `m.expand` / `m.collapse` — disclosure and expansion
- `m.confirm` — confirmation feedback
- `m.reflow` — lists and layouts gaining or losing items

Motion rules:
- Motion communicates cause and state; it is not decoration running continuously without purpose.
- Prefer interruptible springs for spatial movement and layout changes.
- A new input should take control immediately; stale animations must not block interaction.
- Enter and exit may have different timing, but the pair should feel related.
- Respect reduced-motion settings. A reduced-motion path should preserve state feedback and spatial clarity without requiring the full animation.
- Measure important transitions on the real scene. Do not describe an unmeasured spring as smooth or 60 FPS.

Feature-specific motion such as Ferrolume's workspace helix may use its own named spring because it is a defining instrument, not a generic control transition.

## 7. Layout and composition

- Primitives should fit the space their parent gives them and expose their required dimensions.
- Compositions own internal arrangement; the host surface owns placement on screen.
- Avoid coupling a reusable component to a specific monitor resolution, bar position or application window.
- Support clipping and overflow deliberately. Interactive content must remain inside the hit surface that visually contains it.
- Keep layout changes separate from domain actions: moving a card is a layout intent; saving a board is an application responsibility.

This boundary is essential for future freeform desktop widgets and workspace layouts.

## 8. Persistence and customization

A component does not write its own configuration. Its host owns the settings schema, validation, persistence and migrations.

Future editor-facing components will need a descriptor layer containing, at minimum:
- stable component ID and version;
- display name and category;
- supported size/density variants;
- configurable properties with types, defaults and validation;
- exposed events/actions;
- theme roles and material dependencies;
- motion intents;
- minimum/maximum size and resize behaviour;
- accessibility/input capabilities;
- preview and safe fallback behaviour.

This descriptor layer is **not implemented yet**. Do not pretend that a Pleamar component signature alone is enough for a safe visual editor. Build the descriptor system only after the runtime contract has been exercised by real components.

## 9. Current implementation map

Already present:
- A shared semantic colour vocabulary and contrast validation.
- A small geometry and spring vocabulary in `shell/theme/tokens.plm`.
- A separate Ferrolume material and motion vocabulary.
- Reusable Pleamar libraries in `shell/ui/`.
- Examples of event-driven components that receive events from their host, including Board parts and island controls.
- A clear separation between many domain logic modules and their visual compositions.

Still inconsistent or missing:
- A complete spacing, stroke and hit-target scale.
- Consistent state naming and presentation across surfaces.
- A systematic compact/standard/comfortable density contract.
- A component descriptor/registry for discovery and visual editing.
- Shared primitive implementations for common controls across Settings, Nexus, Board and future widgets.
- A reusable motion/reduced-motion contract across all standalone scenes.
- Automated checks that enforce the component contract.

## 10. Migration plan

Do this in small, verifiable steps.

### Phase 1 — shared vocabulary (current)

- Complete the common geometry scale without changing existing component appearance.
- Document the contract and its boundaries.
- Keep existing names such as `g.radius` and `g.radius.item` working.

### Phase 2 — primitive pilot

Choose one repeated control with clear use in more than one surface. Build a shared primitive with explicit props and event outputs. Migrate two consumers and compare behaviour and appearance before migrating more.

Good first candidates are a button/action surface, a toggle, a slider or a section header. Choose based on actual duplication, not aesthetics alone.

### Phase 3 — state and motion consistency

Unify focus, hover, pressed, selected, disabled and busy behaviour. Add reduced-motion handling and tests. Keep feature-specific visual character.

### Phase 4 — composition and density

Create reusable layout primitives and density variants. Move repeated patterns out of feature-specific files only when the shared contract is proven.

### Phase 5 — editor-ready descriptors

Add component metadata, safe property schemas, previews, placement constraints, persistence and undo/redo. This is the foundation for the visual component editor and widget ecosystem.

## 11. Acceptance checklist for new shared components

Before calling a component reusable, verify:

- [ ] It has a stable name and a clear responsibility.
- [ ] Changing data and actions are explicit inputs.
- [ ] It owns no system calls, persistence or application workflow.
- [ ] It uses semantic theme roles or a documented material mapping.
- [ ] It follows shared geometry and density rules, or documents a measured exception.
- [ ] Focus, disabled and selected states are correct where relevant.
- [ ] Pointer and keyboard behaviour are coherent where supported.
- [ ] Motion is interruptible and respects reduced motion.
- [ ] Its hit region matches its visible and interactive bounds.
- [ ] At least two real consumers use it before it is treated as a general primitive.
- [ ] Tests cover its state transitions and invalid inputs.

The goal is not a generic component library bolted onto mooi. The goal is one coherent environment whose components can be recombined, customized and eventually edited visually without losing mooi's identity.

## 12. Existing component inventory and first migration boundary

The current code already contains reusable controls. Do not create a second generic library beside them.

| Source | Existing pieces | Current responsibility |
|---|---|---|
| `shell/ui/ferrolume.plm` | `SButton`, `SToggle`, `SSlider`, `SChoice`, `STrack`, `SResult` | Ferrolume controls and selection surfaces |
| `shell/ui/lumen.plm` | `Button`, `Slider`, `Tab`, `KeyToggle`, `BGMode`, `ColorSwatch`, `Vibe` | Wallpaper-studio controls and palette/source selection |
| `shell/ui/loom.plm` | `CutButton`, `FieldCluster`, `FieldItem` | Notification-field-specific actions and rows |
| `shell/ui/board.plm` | `TagDot`, `KColumn`, `KCard` | Board-specific data presentation |

### What is shared already

- The Settings scene imports `shell/ui/ferrolume.plm` and uses `SButton` and `SToggle` repeatedly across settings pages. These are already genuine shared primitives; the first improvement should strengthen their contract and verification rather than relocate them for appearance's sake.
- The Wallpaper Studio imports `shell/ui/lumen.plm` and uses `Lumen.Button` across its toolbar, editing modes, browser and picker. Its variable height, tone and solid/outline treatment are intentionally different from the fixed 30 px Ferrolume action button.
- `Loom.CutButton` is a drawing helper used inside `FieldItem`; it does not own a hit zone or emit an event. It is not interchangeable with either action-button component.
- `Lumen.KeyToggle` and `Ferrolume.SToggle` have different geometry and motion. Keep their visual treatments distinct until a shared behaviour layer can be introduced without flattening their identities.

### First migration boundary

The first safe boundary is the **action-button contract**, not a forced shared appearance:

1. Keep each surface's visual component and its current call signature.
2. Define and verify the same semantic requirements: accessible button role and label, disabled state reflected in the hit zone, one explicit action event, and no hidden application workflow.
3. Add a shared test/verification path for those requirements before migrating any consumer.
4. Only then consider a shared low-level interaction primitive if Pleamar's component composition supports it cleanly.

This is deliberately conservative. The existing source demonstrates that the components are visually related but not structurally identical. A premature merge would either break current call sites or erase the distinct Lumen and Ferrolume treatments.

### Current verification

`tests/components.sh` is the first executable guard for this boundary. It checks that both existing action-button components declare a button role, expose a meaningful label and enabled state on the hit target, and emit the caller-supplied action payload. It also checks that Settings and Wallpaper Studio still consume their respective components.

Run it with:

```sh
sh tests/components.sh
```

This is a source-contract check, not a Pleamar runtime or pointer-interaction test. The scene compiler and live disabled-click behaviour still require verification with the installed Pleamar runtime.

## 13. Editor-ready component descriptor registry

The first descriptor registry now lives in `shell/lib/components.luau`. It describes the two existing action buttons without changing their Pleamar implementations:

- `ferrolume.button` → `FerrolumeParts.SButton`
- `lumen.button` → `Lumen.Button`

Each descriptor carries:

- Stable ID, category, name, description and exact source location.
- Design direction and surface identity, so an editor can preserve each treatment.
- Geometry mode, preferred dimensions, resize rules and hard constraints.
- Typed properties with defaults, editor visibility, ranges, groups and units.
- Separate non-editable event/data bindings.
- Implemented and not-yet-implemented interaction states.
- Event names and payload descriptions.
- Theme-role dependencies and motion notes.
- A preview recipe suitable for a future scene-backed preview renderer.

### Registry API

The module is pure Lua/Luau and has no Pleamar globals or filesystem side effects:

- `components.ids()` — stable, sorted IDs.
- `components.list(category?)` — descriptor copies for a category or the full catalogue.
- `components.get(id)` — one defensive descriptor copy.
- `components.defaults(id)` — editable property defaults only.
- `components.validate(id, values)` — validates typed, bounded editor values and rejects unknown fields.

The validator deliberately accepts only property data. It does not accept event callbacks, code, scene fragments or arbitrary executable values. The event/data wiring remains owned by the scene and its logic. This is a metadata and validation foundation, not yet a visual editor, live preview renderer, persistence format or undo/redo implementation.

### First supported editor properties

| Component | Editable properties | Geometry |
|---|---|---|
| `ferrolume.button` | width, label, hot treatment, enabled | Fixed 30 px height; width 32–720 px |
| `lumen.button` | width, height, label, tone, solid treatment, enabled | Width 32–720 px; height 24–120 px |

Position (`x`, `y`) is supplied by the layout engine and is not exposed as a style control. Event handler and payload bindings are not editable properties. The descriptors explicitly mark hover/enabled as implemented and focus/pressed visuals as not yet implemented; the editor must not present planned states as working features.

The registry is covered by the pure unit suite in `tests/unit/run.lua`, which is already part of CI. It tests stable discovery, defensive copies, valid and invalid property values, safe defaults and honest state metadata.

