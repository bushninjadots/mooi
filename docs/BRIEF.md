# TIDAL SHELL — MASTER PROJECT BRIEF

Saved verbatim on 2026-10-15, at the user's request, as the authority on intent for the
project now called **mooi** (docs/DECISIONS.md D1). Everything below is the brief as written;
the working checklist condensed from it is docs/SPEC.md, and §15 at the end of this file is
the audit of where the project stands against it.

## A new, fluid, highly customizable Linux desktop shell built with Pleamar and Hyprland

You are the principal software architect, Linux desktop-shell engineer, graphics and animation engineer, interaction designer, and implementation lead for a new project called **Tidal Shell**.

Your job is to help me design, engineer, test, and eventually release a distinctive, high-performance Linux desktop shell. This must become a real, usable, maintainable product, not merely a concept, visual mockup, collection of disconnected widgets, or superficial theme.

You must work directly with the available development environment, inspect actual source code and documentation, verify technical claims, and make incremental, testable progress.

Do not assume a feature is supported simply because it sounds possible. Investigate the relevant APIs and existing implementations first.

---

# 1. PROJECT VISION: FLUID STRUCTURE

Tidal Shell is a desktop interaction environment built around the idea of **fluid structure**.

Traditional desktop shells often consist of a fixed panel, application launcher, system tray, notification popup, dock, and workspace switcher. They may be attractive, but their elements often feel like separate applications placed next to one another.

Tidal Shell should feel like one coherent system.

Its surfaces should emerge from meaningful anchors, adapt to the user's current context, change size when necessary, and transition smoothly between compact and expanded states. However, the shell must remain predictable, precise, responsive, and functional.

The goal is not to make everything float, animate, or behave unpredictably. Motion must communicate state, hierarchy, relationships, and user intent.

The visual philosophy is:

- **Foundry:** precise industrial structure, clean geometry, deliberate spacing, strong hierarchy, technical credibility.
- **Tidal:** fluid movement, spatial relationships, morphing surfaces, responsive transitions, contextual expansion.
- **Workshop:** the user can customize the shell itself, including its layout, appearance, behavior, density, and motion.

The result should be modern, distinctive, technically sophisticated, and professional.

Take inspiration from the usability and clarity of GitHub, Linear, Notion, Figma, Discord, Vercel, and Cartesia. These are references for information hierarchy, developer-oriented quality, precision, and interaction—not interfaces to copy.

Avoid generic AI-generated-looking dashboards, excessive rounded cards, enormous empty panels, decorative gradients, unnecessary glassmorphism, excessive glow, and random animation.

The shell must remain readable and usable during real work.

## Fundamental principles

1. Function before decoration.
2. Animation must communicate something.
3. Keyboard interaction is a first-class interaction method.
4. Pointer interaction must feel direct and intentional.
5. Compact surfaces should expand only when useful.
6. Every feature must have a clear purpose.
7. Configuration must be discoverable and reversible.
8. Customization must not compromise stability.
9. Performance must be measured on real hardware.
10. Existing Hyprland functionality must remain available.
11. Features must degrade gracefully when a system integration is unavailable.
12. Do not introduce AI features as a core product requirement. Tidal Shell should be useful without an AI dependency.

The project is intended to be developed as a fresh, independent codebase. Do not treat an existing dotfiles repository as the project architecture or blindly copy an existing shell.

---

# 2. PART ONE: THE TIDES INTERACTION MODEL

Tidal Shell has five global interaction modes.

These modes describe the overall interaction context, not five different themes or applications.

## 2.1 Rest

The default desktop state.

- The shell occupies minimal space.
- The primary Spine is visible or follows the configured visibility policy.
- Small indicators communicate important system state.
- Contextual surfaces remain hidden until requested or genuinely useful.
- The desktop and applications retain visual priority.
- Background processing and animations are minimized.
- The shell must not constantly demand attention.

Rest should be the most efficient state for everyday desktop use.

## 2.2 Focus

The user is working with a specific application, window, task, or interaction.

- Unnecessary shell elements recede.
- Relevant controls become easier to access.
- Contextual actions may appear near the focused object.
- Notification presentation should avoid unnecessary disruption.
- The shell must not steal focus unexpectedly.
- Keyboard navigation remains predictable.

Focus must not mean that the shell arbitrarily hides important system information or interferes with applications.

## 2.3 Explore

The user deliberately enters a broader view of their desktop or system.

This mode supports:

- Workspace Atlas.
- Window previews.
- Workspace navigation.
- Multi-monitor navigation.
- Window movement between workspaces.
- Layout selection and arrangement.
- Contextual window actions.
- Relevant system and application discovery.

Explore should help the user understand their current desktop state spatially.

It should improve on a conventional workspace overview, rather than merely reproduce a standard overview with different colours.

## 2.4 Workshop

The user edits Tidal Shell itself.

Workshop will eventually provide a visual environment for configuring:

- Component placement.
- Spine and edge arrangements.
- Surface dimensions and density.
- Theme and accent settings.
- Component visibility.
- Motion profiles.
- Activation methods.
- Layout and workspace presentation.
- Behaviour and keyboard shortcuts.

The editor must have a safe preview, undo and redo, validation, explicit apply and revert operations, and recovery from invalid configurations.

Do not attempt to build a complete arbitrary visual programming environment in the first version. Start with a controlled set of supported components and editable properties.

## 2.5 Ambient

A restrained, low-distraction state for background information.

Potential uses include:

- Quiet media information.
- Low-priority notifications.
- Minimal system status.
- Passive progress information when genuinely useful.

Ambient must not become an excuse for permanent screen clutter, intrusive motion, unnecessary polling, or animated decorations with no functional value.

## Mode transitions

Modes should interact coherently. For example:

Rest → Explore → Focus → Rest.

A user may open a contextual surface while in Focus without necessarily changing the entire shell into another mode.

Implement an explicit state model. Avoid unrelated Boolean flags that allow impossible combinations of states.

Where global modes overlap with local component states, define which state owns the interaction and how transitions are resolved.

Escape should dismiss the topmost dismissible surface. It should not indiscriminately close applications, discard edits, or cancel unrelated system operations.

Critical system and safety-related feedback must take precedence over ambient decoration. A surface containing an active interaction must not disappear merely because a timer or unrelated event changes.

---

# 3. PART TWO: THE SPINE, ISLANDS, AND EDGE MEMBRANES

The core visual architecture consists of three related surface types.

## 3.1 The Spine

The Spine is the primary persistent navigation and system-access rail.

Initial design proposal:

- Approximately 44–52 logical pixels wide.
- Initially positioned on the left edge.
- Configurable position and contents.
- Compact, precise icons and indicators.
- Clear hover, focus, active, and disabled states.
- No unnecessarily large pill-shaped buttons.
- Minimal permanent screen occupation.

Potential Spine contents:

- Workspace access.
- Application launcher or command access.
- Active application or window context.
- Media status.
- Notification status.
- System status.
- Entry into Workshop.
- User-configured shortcuts.

Do not put every feature in the Spine. It should be a navigational anchor, not a miniature control panel containing everything.

The Spine should provide a consistent origin for related interactions.

Its width, spacing, icon size, alignment, visibility, and component order should eventually be configurable.

## 3.2 Islands

Islands are compact contextual surfaces that expand when additional information or controls are required.

Examples include:

- Media controls.
- Audio controls.
- Notification summaries.
- Clipboard access.
- Workspace previews.
- Window actions.
- Quick system controls.
- Search results.
- Progress and transfer information.

An Island should have a clear relationship to its activation point or source object.

For example, selecting the media indicator may expand it into playback controls, track information, and output selection if the underlying integrations support those capabilities.

Selecting a window may reveal a contextual action surface rather than opening an unrelated full-screen menu.

Each Island must have:

- A defined owner and identity.
- A compact state.
- An expanded state where appropriate.
- A documented activation method.
- A documented dismissal method.
- Keyboard navigation.
- Focus management.
- Screen-edge repositioning rules.
- Interruption-safe animations.
- Clear behaviour when another surface opens.

Do not allow duplicate Islands for the same event or interaction unless duplication is an intentional feature.

## 3.3 Edge Membranes

Edge Membranes are larger surfaces that unfold from a defined anchor.

They may be used for:

- Workspace Atlas.
- System controls.
- A larger command interface.
- Notification history.
- Advanced audio controls.
- Workshop.
- Detailed application or window management.

A membrane should feel related to its originating edge or component.

It may expand horizontally, vertically, or into a larger spatial arrangement, depending on the surface and screen dimensions.

The geometry must be predictable. Do not let a panel unpredictably cover the active application or place essential controls outside the usable screen area.

Support different monitor sizes, multiple monitors, screen scaling, and different edge configurations wherever the underlying APIs permit.

## Shared surface lifecycle

Use a coherent lifecycle model such as:

hidden → entering → compact → expanded → exiting → hidden

Not every component needs every state. Define the supported states per component.

Animation must be interruptible. Reopening a surface while it is exiting must not produce duplicate instances, a jump to an incorrect position, or a permanently stuck intermediate state.

Maintain one authoritative state model for each surface.

---

# 4. PART THREE: THE SIX SELECTED DESIGN EXPERIMENTS

These six experiments are core design directions for Tidal Shell. They should share a visual language, state model, configuration system, and animation framework.

They are not six disconnected applications.

## 4.1 Workspace Atlas

Create an improved workspace overview with three possible presentation modes.

### Strip

A compact horizontal or vertical overview of available workspaces and their windows.

Useful for fast switching and low screen occupation.

### Grid

A structured overview showing multiple workspaces and their window arrangements.

Useful for browsing, moving windows, and comparing workspace contents.

### Spatial

A larger spatial arrangement that represents workspaces and monitors as a navigable environment.

This is a presentation and navigation layer, not a new window manager. Actual workspace and window state remains owned by Hyprland.

### Core capabilities

- Display current workspaces and windows.
- Navigate with keyboard and pointer.
- Focus a selected window.
- Switch workspaces.
- Move windows between workspaces.
- Support dragging where the underlying integration permits it.
- Represent multiple monitors.
- Configure layout, density, labels, ordering, and preview dimensions.
- Provide useful window thumbnails when technically feasible.
- Handle empty workspaces clearly.
- Adapt to changing workspace and window counts.
- Avoid stale or misleading previews.
- Provide a privacy mode that can conceal window content if feasible.

### Atlas configuration

Provide settings for:

- Strip, Grid, and Spatial modes.
- Workspace ordering and labels.
- Thumbnail scale.
- Window spacing.
- Overview dimensions.
- Monitor arrangement.
- Animation intensity and duration.
- Preview refresh behaviour.
- Whether application icons and titles appear.
- Whether empty workspaces are displayed.

The default should be immediately usable without configuration.

Do not implement a complicated simulated desktop that becomes disconnected from actual Hyprland state.

## 4.2 Contextual Satellites

Create context-sensitive controls that appear near a selected window, component, or meaningful interaction point.

Support three presentation styles.

### Compact

A small action strip with the most relevant actions.

### Radial

An optional radial menu for directional selection and quick actions.

Radial menus must be optional. They should not become the mandatory interface for ordinary actions or make mouse and keyboard operation slower.

### Expanded

A larger contextual surface for complex actions, additional options, or nested menus.

### Example window actions

Depending on Hyprland capabilities and permissions:

- Focus.
- Move.
- Snap or arrange.
- Resize.
- Pin or float.
- Change workspace.
- Toggle fullscreen.
- Close.
- Access supported window rules.

Every action must map to a real operation. Do not display controls that merely animate without changing the actual system state.

### Behaviour

- Anchor controls to the selected object where appropriate.
- Reposition near screen edges.
- Avoid covering the target window's most important controls.
- Support keyboard navigation.
- Provide clear action feedback.
- Allow activation and dismissal settings.
- Allow action order, scale, spacing, and visibility to be configured.
- Define predictable submenu and nested-menu behaviour.
- Avoid accidental actions caused by pointer movement.
- Handle unavailable or failed operations honestly.

## 4.3 Morphing Command Membrane

Build a command interface that begins compact and expands as the user interacts with it.

Proposed initial shortcut: Super+Space. Verify existing bindings and conflicts before assigning it.

### Compact state

A focused input for searching applications, windows, commands, and supported system settings.

### Results state

Results appear in an organized list with keyboard navigation, categories, useful icons, and clear selection.

### Interactive state

When a result supports it, the surface may expose relevant controls or actions without opening an entirely separate interface.

Potential capabilities:

- Launch applications.
- Find and focus windows.
- Switch workspaces.
- Search supported shell settings.
- Invoke contextual actions.
- Expose supported system controls.
- Open relevant Workshop settings.
- Show useful secondary information.
- Offer configurable result categories.
- Support keyboard-only interaction.

The command interface must be useful even before every integration is implemented.

### Customization

Allow the user to configure:

- Position and anchor.
- Width and maximum height.
- Expansion behaviour.
- Search categories.
- Result density.
- Keyboard shortcuts.
- Animation profile.
- Preview visibility.
- Pointer-following behaviour, if supported.

Use a fixed, predictable position by default. Pointer-following is an optional experiment, not the primary interaction model.

Do not implement arbitrary command execution from untrusted results. Treat external content as data, not as trusted instructions.

## 4.4 Notification Streams

Create a notification presentation system that can group related events and move between compact and expanded states.

Possible states:

- Compact indicator.
- Incoming notification.
- Grouped stream.
- Expanded details.
- Quiet state.
- Notification history.

### Core capabilities

- Group related notifications where the source provides enough information.
- Group by application, conversation, or category when supported.
- Provide meaningful priority handling.
- Avoid duplicate entries.
- Offer configurable retention and dismissal behaviour.
- Support quiet periods.
- Provide privacy controls for notification content.
- Support keyboard and pointer interaction.
- Provide access to notification history where available.
- Handle notification actions if the underlying protocol exposes them.

Do not silently discard important notifications merely to make the interface look cleaner.

Do not claim that a notification has been delivered, dismissed, or acted upon unless the underlying operation confirms it.

## 4.5 Live Workshop

Workshop is the eventual visual customization environment for Tidal Shell.

It should allow users to manipulate real, supported shell components directly rather than requiring every adjustment to be made by manually editing configuration files.

### Primary editor modes

**Layout**

- Component placement.
- Spine arrangement.
- Edge configuration.
- Surface positioning.
- Supported sizing and alignment.
- Workspace overview layout.

**Appearance**

- Colour and accent.
- Typography where configurable.
- Component visibility.
- Density.
- Geometry.
- Theme selection.
- Wallpaper-derived colours.

**Motion**

- Duration.
- Easing.
- Expansion and collapse.
- Surface transitions.
- Selection feedback.
- Motion profiles.
- Reduced-motion options.

**Behaviour**

- Activation methods.
- Keyboard shortcuts.
- Dismissal rules.
- Component visibility rules.
- Supported contextual actions.
- Edge activation behaviour.

### Editor structure

Use a practical editing interface with:

- A component hierarchy.
- A live preview or canvas.
- A property inspector.
- Clear selection.
- Undo and redo.
- Apply and revert.
- Validation errors.
- A safe recovery path.
- A way to restore defaults.

The preview must distinguish simulated states from live system operations.

Do not claim that every arbitrary component can be edited. Only expose properties that the actual component implementation supports.

### Configuration modes

Provide a straightforward visual editor for ordinary use and, eventually, an advanced declarative configuration editor using JSON, TOML, or another justified format.

Choose one canonical on-disk configuration format after inspecting the framework and project requirements. Do not create multiple competing sources of truth.

## 4.6 Edge Ecosystem

Make shell surfaces accessible through configurable screen edges and activation zones.

Potential roles:

- Navigation edge.
- Status edge.
- Utility edge.
- Context edge.

These are configurable roles, not a requirement to occupy every edge.

### Activation options

Where technically supported:

- Click.
- Double-click.
- Keyboard shortcut.
- Modifier plus pointer.
- Hover with a configurable delay.
- Touchpad gesture.
- Other documented input mechanisms.

### Requirements

- Avoid conflicting activation zones.
- Make accidental activation preventable.
- Support screen edges on multiple monitors.
- Respect fullscreen applications.
- Account for exclusive zones and input regions.
- Provide sensible keyboard alternatives.
- Let the user disable any activation method.
- Ensure the active edge configuration remains understandable and discoverable.

Do not implement hover activation everywhere by default. It can interfere with ordinary pointer movement and other desktop interactions.

---

# 5. PART FOUR: LIVING COMPONENTS AND CONTEXTUAL BEHAVIOUR

Components should behave as members of a shared system.

A component may have compact and expanded presentations, contextual actions, status information, and user-configurable activation behaviour.

Examples include:

- Media component.
- Audio component.
- Workspace component.
- Clipboard component.
- Notification component.
- Command component.
- System status component.
- Window-action component.

Define a common component contract that includes, as appropriate:

- Unique identifier.
- Display name.
- Supported states.
- Supported properties.
- Activation methods.
- Keyboard behaviour.
- Required integrations.
- Optional integrations.
- Configuration schema.
- Accessibility information.
- Performance characteristics.
- Failure and fallback behaviour.

Components must not depend on undocumented side effects from unrelated components.

The component system should eventually permit adding new supported components without rewriting the entire shell.

However, do not build an elaborate plugin framework before a few real components prove that the abstraction is useful.

Start with the smallest architecture that can support the first complete interaction.

---

# 6. PART FIVE: MOTION, GESTURES, AND SPATIAL INTERACTION

Motion is a central part of Tidal Shell, but it must be controlled and consistent.

## Shared motion language

Define reusable motion tokens such as:

- surface.enter
- surface.exit
- surface.expand
- surface.collapse
- selection.change
- object.transfer
- state.confirm
- layout.reflow
- focus.change
- ambient

Each token must have a clear purpose.

Prefer transitions that communicate continuity: a compact control expands into a related surface; a selected window moves into a new workspace; a contextual menu emerges from its anchor.

Avoid unrelated bouncing, constant pulsing, exaggerated spring motion, or movement that delays interaction.

## Initial motion profiles

Treat these as starting proposals to validate, not immutable technical requirements.

- **Instant:** approximately 0–60 ms.
- **Precise:** approximately 100–180 ms.
- **Fluid:** approximately 180–280 ms.
- **Expressive:** approximately 240–400 ms.

Different interactions may need different durations. Avoid forcing every animation into one profile.

Support easing curves and, if the framework permits it reliably, carefully controlled spring-based motion.

## Interruption and reversal

Animations must be interruptible.

If the user reverses an interaction, the surface should transition naturally from its current visual state rather than jumping back to a predefined starting point.

The system must handle:

- Repeated activation.
- Rapid opening and closing.
- Window changes during an animation.
- Monitor changes.
- Configuration changes during an animation.
- Reduced-motion settings.
- Errors from the underlying system operation.

Visual transitions must not block keyboard input or prevent the user from recovering control.

## Gesture grammar

Develop a consistent interaction vocabulary.

For example:

- Select: identify an object.
- Expand: reveal more information or controls.
- Transfer: move an object between contexts.
- Reorient: change spatial arrangement.
- Dismiss: close the current transient surface.
- Confirm: communicate a successful operation.

Gestures must be optional where practical and should have keyboard alternatives.

Do not invent gestures that conflict with Hyprland bindings, application gestures, or established input behaviour.

---

# 7. PART SIX: THEMES, WALLPAPER ADAPTATION, AND CONFIGURATION

Tidal Shell needs a coherent theme architecture rather than individually hardcoded colours in each component.

## Visual foundation

Start with a restrained industrial palette:

- Void: #101416
- Steel: #22292D
- Slate: #46545A
- Signal: #A6F3D1
- Heat: #FF925F

These are provisional design tokens. Validate contrast, readability, and actual rendering before treating them as final.

The intended appearance is predominantly solid and dark, with restrained transparency and blur only where they serve a purpose.

Use a consistent spacing system based on a 4-pixel unit, subject to scaling and layout requirements.

Use approximately 8–12-pixel corner radii for compact surfaces as an initial proposal. Avoid huge rounded cards and excessive pill geometry.

Keep separators precise and subtle. Typography should be legible, compact, and appropriate for a technical desktop.

## Semantic theme tokens

Define semantic roles such as:

- background.primary
- background.secondary
- surface.primary
- surface.elevated
- border.subtle
- text.primary
- text.secondary
- text.muted
- accent.primary
- accent.secondary
- status.success
- status.warning
- status.error
- focus.ring
- selection.background

Components should use semantic tokens rather than hardcoded palette values.

## Matugen integration

Investigate and integrate Matugen for wallpaper-derived palettes if the current version and project architecture support it.

Do not run Matugen and Wallust as competing palette generators. Matugen is the preferred direction.

Before implementation:

1. Verify the installed or selected Matugen version.
2. Read the relevant version's documentation.
3. Confirm its supported inputs, outputs, templates, and configuration format.
4. Account for version-specific breaking changes.
5. Define the exact boundary between generated tokens and user overrides.

Wallpaper changes may update semantic colours, but must not unexpectedly change component layout, motion duration, activation behaviour, or workspace arrangement.

## Theme application pipeline

Use a controlled sequence:

1. Obtain wallpaper or selected theme input.
2. Generate or load a palette.
3. Map palette values to semantic tokens.
4. Apply validated user overrides.
5. Validate token completeness and colour values.
6. Check readability and required contrast.
7. Prepare the new theme.
8. Apply it atomically where possible.
9. Roll back if application fails.

The previous working theme must remain recoverable.

## Customization layers

Keep these concepts separate:

1. Base theme.
2. Wallpaper-derived palette.
3. User overrides.
4. Component-specific settings.
5. Interaction settings.
6. Motion settings.
7. Performance settings.

Define deterministic precedence rules. Do not allow a theme update to overwrite the user's saved preferences.

Theme packages should be declarative and validated. Do not execute arbitrary code merely to load a theme.

---

# 8. PART SEVEN: ARCHITECTURE — PLEAMAR + HYPRLAND

This project is intended to use **Pleamar as the shell's rendering and visual-interaction foundation while retaining Hyprland as the window manager and compositor**.

Do not replace Hyprland with pleamar-wm.

Do not assume that Pleamar supports every desired feature. Verify its actual capabilities first.

## 8.1 Technical reconnaissance

Inspect the upstream Pleamar project, current documentation, examples, repository structure, release information, and dependencies.

Verify:

- How Pleamar is launched under an existing Wayland compositor.
- Whether its desktop companion can run independently of pleamar-wm.
- How surfaces are created.
- Which layer-shell protocols and roles are supported.
- How input events are received and routed.
- How animation and interpolation are implemented.
- How rendering and GPU resources are managed.
- How configuration is loaded and validated.
- How dynamic layout changes are handled.
- How multiple displays and scaling are handled.
- How system integrations are expected to work.
- Whether suitable APIs exist for custom surfaces and components.
- What can be achieved without modifying upstream.
- Which features require new code or upstream contributions.

Distinguish confirmed capabilities from assumptions and proposed extensions.

Do not infer support from screenshots or promotional claims.

## 8.2 Hyprland integration

Hyprland remains responsible for actual window management and workspace state.

Investigate the documented mechanisms available for:

- IPC.
- Window and workspace state.
- Focus and activation.
- Window movement.
- Workspace changes.
- Monitor discovery.
- Keyboard bindings.
- Window rules where relevant.

Use documented interfaces and stable integration boundaries.

The shell must not become a competing window manager or maintain a second, inconsistent representation of window state.

Use an adapter layer between shell features and Hyprland-specific operations.

This should make it possible to test shell logic independently and potentially support other compositors in the future without promising that portability in the initial release.

## 8.3 Rendering and system boundaries

Separate the project into logical responsibilities, adapted to what Pleamar actually supports:

- Application or shell entry point.
- Surface and scene management.
- Component lifecycle and state.
- Input and keyboard handling.
- Animation and transition management.
- Theme and token management.
- Configuration and validation.
- Hyprland integration.
- Optional system integrations.
- Diagnostics and performance measurement.

Do not create layers that add complexity without a real purpose.

Avoid maintaining duplicate state between the UI, configuration files, and Hyprland.

## 8.4 Existing Quickshell setup

I have an existing Quickshell setup and other desktop projects. Do not delete or replace them.

Tidal Shell must be developed independently and must not automatically launch conflicting Quickshell surfaces.

Do not introduce duplicate bars, docks, notification systems, or edge surfaces.

If an existing service or component is useful, evaluate it explicitly. Do not create a hybrid architecture just because it is convenient.

Any later decision to reuse existing infrastructure must be documented and reversible.

## 8.5 Configuration and recovery

Configuration should be:

- Explicit.
- Validated.
- Versioned.
- Documented.
- Backward-compatible where reasonably possible.
- Recoverable when malformed.
- Applied predictably.

Maintain a known-good configuration or equivalent recovery mechanism.

Invalid settings must not leave the shell unusable at login.

Provide a safe way to launch with default settings if the primary configuration fails.

Do not modify my global Hyprland configuration or session startup automatically during the initial audit.

## 8.6 Repository and project hygiene

Create an independent Git repository for Tidal Shell once the audit and initial design are sufficiently clear.

Use sensible commits and keep unrelated files out of the project.

Never commit secrets, personal data, machine-specific absolute paths, or generated runtime files unnecessarily.

Use a documented development configuration separate from the production session.

Do not make irreversible system changes without explaining them and receiving approval.

---

# 9. PART EIGHT: PERFORMANCE, RELIABILITY, AND THE DELIVERY ROADMAP

Performance is a product requirement, not a future optimization task.

The shell should feel responsive on my actual machine.

Current hardware context:

- MSI Modern 15.
- AMD Ryzen 5 7430U.
- Integrated graphics.
- 1920×1080 internal display.
- External LG display over HDMI.
- Arch/EndeavourOS Linux.
- Hyprland 0.56.2 at the time of this brief.

Verify the current environment before relying on these details, since software versions and configuration may have changed.

## 9.1 Performance targets

Use these as initial measurable targets:

- 60 FPS baseline where the scene and hardware permit it.
- 16.7 ms frame budget at 60 Hz.
- 8.3 ms frame budget at 120 Hz when applicable.
- Under 50 ms input-to-visible-response target for ordinary interactions, where measurable.
- Minimal idle CPU/GPU usage when no active animation or work is occurring.
- No continuous unnecessary polling.
- No uncontrolled growth in memory usage.
- No visible stalls during ordinary surface expansion, workspace switching, or notification presentation.

Measure actual frame times, CPU, memory, and GPU behaviour where tools permit.

Do not claim a target has been achieved without evidence.

Separate measurements for startup, idle, simple animation, complex animation, multi-monitor use, and high event volume.

Do not sacrifice usability or stability to reach a benchmark number.

## 9.2 Reliability requirements

Test:

- Repeated surface opening and closing.
- Rapid state transitions.
- Invalid configuration.
- Missing optional integrations.
- Hyprland IPC failure or delayed responses.
- Display resolution and scale changes.
- Monitor connection and disconnection.
- Fullscreen applications.
- Session startup and shutdown.
- Recovery after the shell crashes.
- Reduced-motion behaviour.
- Theme generation failure.
- High notification volume.

The shell must fail safely. A failed visual operation must not silently pretend that the underlying system operation succeeded.

## 9.3 Development phases

Work in the following order. Do not skip ahead merely because a later feature is visually exciting.

### Phase 0 — Audit, specification, and foundation

- Inspect the machine and development environment.
- Inspect upstream Pleamar documentation and source.
- Verify the independent companion launch path.
- Map available APIs and limitations.
- Confirm how the shell can operate on top of Hyprland.
- Define the minimum viable architecture.
- Document known risks.
- Establish repository structure and development workflow.
- Define a reversible test strategy.
- Produce a concise implementation plan with acceptance criteria.

Do not modify the existing desktop session or install unverified dependencies during the initial audit.

### Phase 1 — First real shell surface

Build the smallest working vertical slice:

- A minimal Spine or equivalent anchor.
- One functional Island.
- A coherent state lifecycle.
- Keyboard activation and dismissal.
- One real, verified Hyprland interaction.
- Basic configuration.
- Logging and a repeatable test procedure.

The goal is to prove the architecture works, not to imitate the final appearance with fake functionality.

### Phase 2 — Shared motion and interaction framework

- Define surface states.
- Implement interruption-safe transitions.
- Establish motion tokens.
- Implement keyboard focus and dismissal.
- Add reduced-motion support.
- Validate rapid and repeated interactions.

### Phase 3 — Command Membrane and Contextual Satellites

- Build searchable results.
- Add application and window access where supported.
- Add contextual window actions.
- Add compact and expanded presentations.
- Verify that operations change the real system state.

### Phase 4 — Workspace Atlas

- Build Strip mode.
- Build Grid mode.
- Investigate and implement Spatial mode.
- Integrate real workspace and window state.
- Add monitor navigation.
- Add supported window movement.
- Test multi-monitor behaviour.

Do not attempt to implement every overview mode simultaneously if doing so prevents delivery of a working first mode.

### Phase 5 — Themes and Matugen

- Define semantic tokens.
- Build the configuration and override model.
- Integrate the verified Matugen workflow.
- Implement validation and recovery.
- Ensure wallpaper updates do not reset user settings.

### Phase 6 — Notification Streams and Edge Ecosystem

- Integrate the available notification source.
- Implement grouping and priority handling.
- Add privacy settings and retention.
- Add configurable edge activation.
- Test fullscreen and multi-monitor conflicts.

### Phase 7 — Live Workshop

- Build the supported component hierarchy.
- Add the property inspector.
- Implement preview and selection.
- Add apply, revert, undo, and redo.
- Validate saved configurations.
- Add recovery from invalid edits.

### Phase 8 — Extension and release preparation

- Evaluate a declarative extension or component-package system.
- Document supported extension boundaries.
- Add installation and removal procedures.
- Add clean startup and shutdown behaviour.
- Produce documentation, screenshots, performance results, and release notes.
- Prepare a stable initial release.

A future extension system must not be a prerequisite for shipping the first usable version.

---

# 10. VISUAL DESIGN AND DETAIL RULES

The shell should look deliberately designed, not like a pile of independent widgets.

## Geometry

- Use a consistent spacing scale.
- Align controls to a deliberate grid.
- Maintain consistent icon sizes and baselines.
- Use restrained corner radii.
- Avoid oversized rounded containers.
- Use separators and negative space intentionally.
- Preserve enough contrast to distinguish adjacent surfaces.

## Colour

Use semantic colours consistently.

Accent colours should communicate selection, focus, action, or state. They should not be applied indiscriminately.

The initial palette is industrial and restrained, with mint as the primary signal and orange as a secondary heat or warning accent. Validate all status semantics before assigning final roles.

## Transparency and blur

Use transparency or blur only when it improves context or visual hierarchy.

Provide a solid-surface fallback.

Do not make every panel translucent, and do not let text contrast depend on whatever happens to be behind the panel.

## Information density

Support compact and comfortable density settings where appropriate.

Avoid both extremes:

- Huge panels containing very little useful information.
- Overcrowded interfaces with indistinguishable icons and controls.

## Responsive layout

Account for:

- Different resolutions.
- Different display scales.
- Narrow displays.
- Multiple monitors.
- Monitor position.
- Fullscreen windows.
- Edge placement.
- Content overflow.

A panel that looks good in a static screenshot but fails on a real desktop is not finished.

---

# 11. PRODUCTIVITY AND DAILY CONVENIENCE

The shell must improve everyday desktop interaction, not simply provide visual novelty.

Prioritize the features with the clearest daily value:

1. A substantially better workspace overview.
2. Contextual actions for windows and relevant objects.
3. An efficient command interface.
4. Notification grouping and prioritization.
5. Consistent access to common system controls.
6. Keyboard-first navigation.
7. Direct configuration and visual customization.
8. Smooth movement between related interface states.

Do not introduce recipe-based workflows as a central product concept.

Do not force users to construct complex automation sequences just to use ordinary shell features.

Prefer individual capabilities that are useful independently and work together naturally.

Avoid implementing a large catalogue of novelty widgets before the core desktop interactions are solid.

---

# 12. TESTING AND ACCEPTANCE CRITERIA

Every phase must have an explicit definition of done.

For each feature, document:

- What the user can do.
- Which underlying system APIs it uses.
- What state is authoritative.
- What configuration is supported.
- How it behaves when unavailable.
- How to test it.
- How to recover if it fails.
- What remains incomplete.

Use real system state in integration tests wherever possible. Mocked data may be used for isolated UI development, but the finished feature must not be presented as integrated until it actually is.

Use automated tests for configuration parsing, state transitions, validation, and other logic that can be tested independently.

For visual and interaction behaviour, create repeatable manual test procedures where automated testing is impractical.

Do not silently remove existing functionality to make a test pass.

Do not rewrite unrelated parts of the project during a focused feature task.

Keep a clear record of verified behaviour, incomplete functionality, and technical debt.

---

# 13. HOW YOU MUST WORK WITH ME

I want you to do the engineering work, not merely give me long lists of things I could do myself.

Work incrementally and make meaningful progress in each session.

Follow these rules:

1. Start by inspecting the actual environment and upstream project.
2. Read relevant documentation before writing integration code.
3. Separate confirmed facts from assumptions and design proposals.
4. Do not install packages, replace desktop components, alter startup configuration, or delete existing files during the initial audit.
5. Explain any system-level change before requesting approval.
6. Prefer small, reversible changes.
7. Keep a working state at the end of each development phase.
8. Use Git checkpoints at sensible milestones once the project repository is established.
9. Do not create an enormous speculative architecture before proving the first vertical slice.
10. Do not use fake functionality to make the UI appear complete.
11. Do not invent APIs, CLI flags, configuration keys, or Pleamar capabilities.
12. Do not claim tests passed unless you actually ran them.
13. Do not claim performance results without measurements.
14. If a feature is blocked, identify the precise blocker and investigate a realistic alternative.
15. Prefer full, clearly identified file replacements when that makes implementation easier to apply and verify, but avoid overwriting unrelated user work.
16. When providing terminal commands, explain which directory they assume and what they change.
17. Do not repeatedly ask me to make technical decisions you can resolve through investigation. Make a justified choice, explain it, and flag only decisions that materially affect architecture, safety, or product direction.
18. Keep the implementation aligned with the product vision. Do not turn Tidal Shell into a generic dashboard or an oversized collection of cards.
19. Maintain a concise project status document with completed work, current work, blockers, decisions, and the next concrete step.
20. Do not stop after producing a plan if the next safe, useful task can be completed. Proceed through investigation and implementation in controlled stages.

If you have terminal access, use it to inspect the actual machine and repository. If you do not have access, state the limitation and provide the smallest useful set of commands to obtain the required evidence.

---

# 14. IMMEDIATE FIRST TASK

**Begin with Phase 0. Do not start by writing the whole shell.**

Perform the following steps:

1. Identify the current working directory and determine whether a project repository already exists.
2. Inspect the OS, Hyprland version, relevant installed graphics and Wayland components, and available development tools without changing the system.
3. Locate the authoritative Pleamar upstream repository and its current documentation.
4. Inspect the actual source and examples to establish how the desktop companion can run under Hyprland without replacing the compositor.
5. Identify the real mechanisms for surfaces, rendering, input, animations, configuration, and system integration.
6. Determine what can be implemented immediately and what depends on missing APIs or additional work.
7. Evaluate whether Pleamar is suitable for the first working Spine and Island, based on evidence rather than appearance alone.
8. Propose a clean independent repository structure and a minimum viable vertical slice.
9. Define measurable acceptance criteria for that slice.
10. Identify all proposed dependencies and any system-level changes that would eventually be required. Do not install them yet.
11. Write a concise audit report, including verified findings, unknowns, risks, and the recommended first implementation.
12. Save the project specification and audit findings in the project documentation once a suitable independent project directory has been established without overwriting existing work.

Then proceed with the first implementation only when the architecture and safety of the changes are clear. If a decision genuinely requires my approval, explain the alternatives and why it matters.

## Final objective

Build Tidal Shell into a cohesive, fast, customizable, visually distinctive desktop shell in which the Spine, Islands, Edge Membranes, Workspace Atlas, Contextual Satellites, Morphing Command Membrane, Notification Streams, and Live Workshop all feel like parts of one carefully engineered system.

The defining quality should be **fluidity with control**: expressive transitions, useful spatial interaction, and deep customization, backed by precise behaviour, real system integration, measurable performance, and reliable recovery.

Start with the audit. Verify the technology. Build one working vertical slice. Prove it. Then expand the system without losing its coherence.

## How to use this prompt

I recommend pasting the entire prompt into Claude Code or your chosen coding agent from a clean working directory, with terminal access enabled.

Then let it complete the initial audit. The first result should be a report explaining what Pleamar actually supports, how it can run alongside Hyprland, what needs custom implementation, and what the first working slice should contain.

Do not let it immediately generate every feature at once. The most important milestone is proving one real surface, one working contextual interaction, and one actual Hyprland operation. Once that works, the rest of the shell can grow on a tested foundation instead of becoming a beautiful but fragile collection of disconnected panels.

---

# 15. WHERE MOOI STANDS AGAINST THIS BRIEF (2026-10-15, bar re-audited 2026-10-16)

One note before the audit: the brief's own §3.1 places the Spine on the **left edge** as an
initial proposal, and later work asked for the opposite — the master prompt that came with the
design's v6 says *"The Mechanism must be a horizontal desktop bar, not a vertical sidebar"*.
mooi follows that, and D16 records the change, its reasons and the way back; everything below is
written for the horizontal bar.

The brief above is unchanged; this section is the answer to "where are we on it". One line per
brief item, with the evidence and what is still missing. Evidence lives in `docs/AUDIT.md`
(what Pleamar and Hyprland actually do, measured), `docs/ARCHITECTURE.md` (how the shell is put
together), `docs/TESTING.md` (what is checked, and how), `STATUS.md` (the numbers of the last
full run) and `docs/DECISIONS.md` (every choice, with the way back).

## 9.3 Phases

| Phase | State | Evidence | Still missing |
| --- | --- | --- | --- |
| 0 Audit and foundation | **done** | `docs/AUDIT.md`; independent repo; `bin/mooi check` + four test suites | nothing outstanding |
| 1 First real surface | **done** | Spine + window island + verified Hyprland actions; `tests/integration.sh` | nothing outstanding |
| 2 Motion and interaction framework | **done** | one island slot, Escape order, `m.*` springs measured each run, reduced motion, degraded IPC | nothing outstanding |
| 3 Command Membrane and Satellites | **done** | search + ranking + usage, app launch, inline window actions; unit/scene/live tests | settings search and "open Workshop settings" (Workshop is Phase 7) |
| 4 Workspace Atlas | **mostly done** | window tiles with real `thumbnails` previews, bounded workspace map, focus/create, window moves, previews switch | **Strip/Grid/Spatial modes as named modes** (one Grid view exists), **multi-monitor**, drag between workspaces, per-workspace per-window dragging |
| 5 Themes and Matugen | **first slice done** | fourteen semantic tokens as `rgb()` over logic-set facts; `lib/theme.luau` (fixed → wallpaper → overrides → completeness → contrast → apply, unit-tested); `bin/mooi theme-sync` + `theme/matugen.toml.in` + `theme/palette.json.hbs` (Matugen 4.2.0, mooi's own config, one output file); live swap proved in `tests/theme.sh` (28 checks), including a real Matugen run from the wallpaper on screen and a palette that was refused whole | light schemes, named theme packages, and a Workshop editor for it (the wallpaper hook is mooi's own `bin/mooi theme-watch`, D18) |
| 6 Notifications and Edges | **blocked / not started** | D5 (ArchEclipse owns notifications in beside mode) | notification ownership in takeover, grouping, quiet periods, edge activation |
| 7 Live Workshop | **not started** | — | the editor: hierarchy, inspector, preview, apply/revert, undo/redo |
| 8 Extensions and release | **not started** | — | packaging, install/remove, release notes; also the one takeover guard (SWITCHING.md) |

## Part One — the five modes

- **Rest**: implemented. The bar is a 72 px strip along the top — the Mechanism, a chain of
  turning blocks and their links beside a row of readings, with no panel behind them
  (docs/MECHANISM.md) — islands are
  closed by default, and nothing in the bar animates at rest (`0.2 %` idle CPU with no island,
  TESTING.md).
- **Focus / Explore / Workshop / Ambient**: **specified only**. There is no mode enum yet: each
  island is its own state and `open` owns the slot (D6). The Atlas is Explore in practice and
  the system island is Ambient-ish, but the brief's global enum is not built, and the brief's
  rule that a surface in active use never vanishes on a timer is honoured (`idle for 30s` closes
  nothing that is busy — it is the safety net for an abandoned keyboard grab).
- Escape order (topmost dismissible first) is implemented and tested; it never touches
  applications or disk state.

## Part Two — surfaces

- **Spine**: implemented — a **horizontal** bar along the top (72 px, `reserve: 72`), ported from
  the design you handed over: the mark and its menu at the left end, a neck into the chain, the
  chain of workspace blocks — solid prisms threaded on the chain's own barrel — that slides to a
  focus slot, cut off by its own window, then the module row — the media reading and its
  transport, the clock, the System door, four readings (volume, brightness, Bluetooth, network)
  and the bar's three ways out (the focused window, the Atlas, the search) — each a prism whose
  press turns it over, closed by an end cap that carries the error dot (docs/MECHANISM.md,
  D16–D17). There is **no dial** any more: the machine runs from the mark to the cap with nothing
  between the pieces. Settings: `spine.clock`, `spine.max_workspaces`, `bar.labels`, `bar.wheel`.
  Position, width and component order are **not yet configurable** — the appearance-and-density
  slice that comes next — and a narrower screen than the machine's 1112 px is not handled yet
  either.
- **Islands**: four (window, system, command, atlas), one slot, hand-over, per-island reveal
  springs, keyboard navigation, Escape order, no duplicates, interruption-safe (tested).
- **Edge Membranes**: the Atlas is drawn as a centred membrane with an anchored growth frame
  (`IslandFrame`); **nothing unfolds from a screen edge yet**, and multi-monitor is untested.
- Lifecycle: implemented as springs per island (`rv.*`) plus one authoritative `open` state.

## Part Three — the six experiments

- **4.1 Workspace Atlas**: real Hyprland state, keyboard and pointer, focus, workspace switch,
  window moves to a workspace, previews with a switch that gives the frames back. **Strip /
  Grid / Spatial are not selectable modes**, monitors are not represented, dragging is not
  implemented, and window ordering/labels/thumbnail scale are not settings.
- **4.2 Contextual Satellites**: compact + expanded exist (window island; inline satellites in
  the membrane). **Radial does not**, and action order/scale/spacing are not configurable.
- **4.3 Command Membrane**: built (compact field → results → inline actions), fixed position,
  keyboard-first, no untrusted execution (apps only via `apps.launch`). Position/width/density
  are not settings yet.
- **4.4 Notification Streams**: **not built** — ArchEclipse is the notification server while mooi
  runs beside it (D5). Nothing is claimed that has not happened: mooi simply does not show
  notifications yet.
- **4.5 Live Workshop**: **not built**. The canonical format is decided (JSON, the only format
  Pleamar reads and writes), and settings are validated and recoverable today.
- **4.6 Edge Ecosystem**: **not built** (no hover/edge activation of any kind).

## Part Four — living components

Islands share `IslandFrame`/`Level` and a written recipe (ARCHITECTURE.md), and each has a
defined owner, states, activation, dismissal and fallback. There is **no formal component
contract document** and no plugin system, deliberately (the brief asks for the smallest
architecture that works first).

## Part Five — motion

Tokens exist (`m.instant/select/enter/exit/expand/collapse/confirm/reflow/spin/turn`),
are critically damped springs, and **the islands' nine transitions are measured on every scene
run** (1 %→99 % of travel) plus a reduced-motion check; the bar's own (`m.spin` 380 ms, `m.turn`
260 ms) are measured by hand, because the chain only moves when the
compositor really changes workspace and the suite promises not to (STATUS.md). Interruption and reversal are by construction. **Gestures are not
implemented**; neither is `focus.change` as a separate token (selection uses `m.select`).

## Part Six — theme

Fourteen semantic tokens, a 4 px grid, 10/8 px radii, mostly solid surfaces (one `blur` and one
shadow, both deliberate); contrast was adjusted (`fg.muted`) and is noted in AUDIT §7. **The
pipeline is built** (Phase 5 first slice): the tokens are `rgb()` over facts the logic sets, so a
theme changes while the shell runs; the precedence is fixed palette → wallpaper palette → user
overrides, then completeness and WCAG contrast, then one atomic paint; a theme that fails is
refused whole and the last good one stays. Matugen 4.2.0 supplies the wallpaper palette through
mooi's own config (one output file, the user's theming untouched), and `theme.source` defaults to
`wallpaper` (D18; `fixed` is the brief's palette alone). What is not there: a light
scheme, declarative theme *packages*, and a Workshop editor — the wallpaper hook is mooi's own
(`bin/mooi theme-watch`, D18), so there is nothing in your pipeline to add
(docs/DECISIONS.md D11, D18).

## Part Seven — architecture

Pleamar renders (0.4.6) and Hyprland manages; pleamar-wm is not used; the Hyprland adapter
(`shell/lib/hypr.luau`) is the only place that knows Hyprland syntax and is unit-tested;
no duplicated window/workspace state; configuration is JSON, versioned, validated, with a
known-good file and safe mode; the existing Quickshell setup is untouched and nothing duplicate
is launched (SWITCHING.md). Diagnostics: `--record`, `--report`, `PLEAMAR_TIMING`, the test
suites.

## Part Eight — performance and reliability

Measured: idle 0.13–0.2 % CPU; frame timing 0.6 % late frames (paint + vblank, not logic);
24 MB PSS. Tested: rapid and repeated transitions, invalid config, safe mode, degraded
Hyprland IPC, crash recovery (keeper), reduced motion, and now theme failure. **Not measured:
input-to-visible latency**, multi-monitor, scale ≠ 1, hotplug, session shutdown; **not tested:
notification volume** (no notifications yet).

## Parts 10–12 — design rules, daily value, testing

Geometry/colour/density rules are followed as tokens, not hardcoded values. Daily value is
being built in the brief's order (Atlas → satellites → membrane → system controls → keyboard →
theme). Every phase has an acceptance table in `docs/TESTING.md`, with what is verified, what
is incomplete and how to recover.
