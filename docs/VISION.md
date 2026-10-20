# mooi · The complete desktop environment vision

> The user's own statement of where mooi is going (2026-10-19), kept as written (reference images
> left out). Subject to change as we go. Read with [PHILOSOPHY.md](PHILOSOPHY.md).

A cohesive, adaptive, deeply customizable Linux environment where everything feels like part of the same living system.

mooi isn't just a shell, a collection of widgets, or a visual theme for Hyprland. Our goal is to build a complete desktop experience around Pleamar, where the interface, applications, system settings, file management, layouts, motion, colors and interactions all share one identity.

We want the freedom and creativity of a heavily customized Linux setup, the polish of a professionally designed operating system, and the fluidity of a spatial, mechanical interface that feels entirely different from conventional desktops.

## 1. One identity across the entire system

Everything should feel like it belongs to mooi. Not merely because it shares the same accent color, but because it follows the same visual, functional and interaction principles.

**The mooi Design Language.** A unified design system defining colors, surfaces, typography, icons, spacing, borders, shadows, depth, motion and interaction states. Every component should use shared design tokens rather than inventing its own appearance.

**System-wide visual consistency.** File manager, terminal, settings, launchers, dialogs, notifications, application menus and desktop widgets should all share the same visual language wherever technically possible.

**A recognizable identity.** mooi should be identifiable through its geometry, typography, restrained colors, mechanical details, precise spacing and characteristic motion, even when no logo is visible.

The rule is simple: one design system, many expressions, no disconnected interfaces.

We shouldn't force every application to look identical. A terminal, file manager and audio player have different purposes. Instead, they should feel like different instruments built by the same design team.

## 2. The mooi Color Engine

Color should be a complete system, not a choice between dark mode and light mode.

Our starting identity can use graphite and charcoal foundations, muted mint or jade as a primary accent, and amber or copper for secondary emphasis. These are starting directions, not permanent restrictions.

### Theming should work at several levels

- **Color foundations.** Backgrounds, elevated surfaces, text, borders, accents, semantic colors, selection states, warnings and error states. Every color has a purpose and adequate contrast.
- **Wallpaper-reactive palettes.** Matugen-style color extraction generates coordinated palettes from a new wallpaper. The resulting theme propagates throughout the shell and supported applications.
- **Theme ingredients.** Expose individual ingredients for customization: accent hue, surface warmth, contrast, transparency, border treatment, corner geometry, depth, motion intensity and effects.
- **Layered themes.** Save a complete theme, then override selected elements without rebuilding everything. Users can change the accent while preserving the rest of the design.
- **Application and toolkit integration.** Coordinate GTK, Qt, terminal colors, icon themes, cursors and supported application styling. Use native theming or application-specific adapters where direct integration is not available.

### Theme ingredients should be independently adjustable

- Palette: generated, predefined or manually created.
- Surfaces: solid, layered, translucent or textured.
- Geometry: square, chamfered, angular or softly rounded.
- Typography: interface font, monospace font, scale and weights.
- Depth: flat, layered, shadowed or dimensional.
- Motion: duration, easing, spring response and transition style.
- Effects: blur, glow, shaders, particles and distortion where supported.
- Density: compact, balanced or spacious layouts.

A user should be able to combine these ingredients into a coherent theme without needing to edit dozens of unrelated configuration files.

## 3. A complete system settings center

The settings center should become the command center for everything mooi can configure.

Rather than scattering options across separate scripts, dotfiles and hidden menus, we want a single discoverable interface backed by a consistent configuration system.

### Proposed settings architecture

| # | Section | Covers |
|---|---------|--------|
| 01 | Appearance & Themes | Palettes, wallpaper extraction, fonts, icons, cursors, surfaces, density and theme presets |
| 02 | Motion & Effects | Animations, easing curves, transitions, blur, shaders, visual effects and performance profiles |
| 03 | Desktop & Layouts | Window gaps, borders, tiling preferences, floating rules, layout presets and workspace behavior |
| 04 | Windows & Workspaces | Workspace identities, window rules, focus behavior, assignments, saved environments and overview settings |
| 05 | Widgets & Components | Available widgets, placement, sizing, visibility, interaction, refresh behavior and custom modules |
| 06 | Input & Gestures | Keyboard shortcuts, mouse behavior, touchpad gestures, edge interactions and custom action mappings |
| 07 | Displays & Graphics | Monitors, resolution, refresh rate, scaling, positioning, screen orientation and supported graphics controls |
| 08 | Sound & Media | Audio outputs, inputs, volume behavior, media controls and supported audio routing |
| 09 | Network & Connectivity | Wi-Fi, Ethernet, VPN and connection controls where supported by the underlying system services |
| 10 | Power & Hardware | Battery, power profiles, lid behavior, peripherals and hardware-dependent settings |
| 11 | Notifications & Focus | Notification rules, priorities, quiet modes, grouping, focus sessions and application permissions |
| 12 | Privacy & Security | Screen locking, session security, application permissions and available system security controls |
| 13 | Files & Applications | Default applications, file associations, opening behavior, launch preferences and integration rules |
| 14 | Accessibility | Text scaling, contrast, reduced motion, keyboard navigation and available assistive features |
| 15 | Advanced & Developer | Configuration inspection, diagnostics, logs, component debugging, performance metrics and advanced overrides |

The important distinction is between mooi-owned settings and settings supplied by Linux services or applications. mooi should provide one coherent interface to both where possible, without pretending it can control hardware or applications that don't expose the required capabilities.

Every setting should have a clear explanation, a sensible default, immediate feedback where safe, and a way to restore its default.

## 4. Layouts become a creative system

We don't want users to be restricted to a single predefined arrangement of panels and windows. mooi should support multiple layers of layout customization.

- **Window layouts.** Tiling, floating, tabbed, stacked, split and asymmetric arrangements, using capabilities provided by Hyprland or compatible extensions.
- **Interface layouts.** Repositionable widgets, configurable panels, modular control surfaces and adjustable interface density.
- **Spatial arrangements.** An overview for moving windows between workspaces, reorganizing groups and changing the structure of a working environment.
- **Saved environments.** Save layouts, application assignments, relevant files, theme overrides and workspace settings together. Restore the parts that can be reliably reconstructed.
- **Layout experimentation.** Preview changes, compare configurations, undo edits and create variations without risking the current working setup.

The goal is not just to provide a list of layouts. It's to make arranging the desktop a creative activity in its own right.

## 5. Desktop widgets that belong to the system

Widgets should be proper components in the mooi ecosystem, not miscellaneous scripts with different styling and behavior. We should support:

- System monitoring: CPU, memory, storage, temperature and network activity.
- Media: current track, playback, volume and output selection.
- Time and planning: clock, calendar, timers, reminders and notes.
- Connectivity: network state, Bluetooth and device status.
- Productivity: shortcuts, command triggers, recent files and active tasks.
- Visual elements: clocks, status displays, decorative motion and ambient effects.
- Custom modules: user-created widgets with configurable appearance and behavior.

Each widget should have consistent controls for size, placement, opacity, visibility, refresh frequency and interaction. Widgets should be discoverable, easy to add or remove, and capable of sharing theme tokens.

Crucially, the system must avoid turning every widget into a permanent card. Some can be tiny indicators, some can be floating instruments, and others can expand into richer interfaces when activated.

## 6. File management should feel native to mooi

The file manager is one of the most important parts of a cohesive desktop. We should either develop a dedicated mooi file manager or create a well-integrated experience around an existing one, depending on what is technically achievable and maintainable.

Its design should support:

- List, grid, compact and split-pane views.
- Breadcrumb navigation and a fast location bar.
- Search, filtering, sorting and saved locations.
- File previews, metadata and useful context menus.
- Tabs, bookmarks, recent files and configurable sidebars.
- Consistent icons, file associations, dialogs and selection states.
- Archive handling, permissions and safe file operations.
- Drag-and-drop between windows and workspaces.
- Optional terminal access from the current directory.
- Configurable file actions and keyboard shortcuts.

The differentiator should be the quality of the integration: files, applications, workspace environments and contextual actions should work together. For example, moving into a development project could let the user open its folder, launch a terminal there and switch to the associated workspace without manually rebuilding the context.

## 7. Terminal and developer experience

The terminal should be a first-class citizen rather than an afterthought. We can provide a coordinated terminal theme for Kitty and other supported terminals, with:

- Matching foreground, background, selection and cursor colors.
- Syntax colors and semantic accents.
- Consistent fonts, typography and spacing.
- Optional transparency and background effects.
- Profiles for different projects or working environments.
- Consistent shell prompt and command-line styling where configured.
- Integration with the desktop's launch actions and workspace layouts.
- A developer-oriented settings area for shortcuts, terminal profiles and diagnostics.

We should also distinguish between terminal configuration and application theming. Kitty can be styled directly through its own configuration, whereas other terminals require their own supported settings or adapters.

The same principle applies to editors, browsers and developer tools: provide polished integrations without promising universal control over every application's internals.

## 8. Motion, fluidity and interaction

Fluidity should be one of mooi's defining qualities, but it must be engineered rather than added as decoration. We want a shared motion system with configurable rules for:

- Opening and closing interfaces.
- Expanding and collapsing widgets.
- Switching views and workspaces.
- Moving between layout configurations.
- Showing contextual controls.
- Resizing and rearranging components.
- Notifications and transient overlays.
- Pointer and touchpad-driven interactions.

Every motion should have a purpose. The interface should communicate relationships, state changes and spatial continuity.

The motion system should expose duration, easing, spring response, delay and reduced-motion controls. It should also adapt to the hardware and avoid expensive effects when they would compromise responsiveness.

Not every application can participate in every transition. We should use Pleamar and compositor capabilities for shell-owned interfaces, and supported integration points for external windows.

## 9. A visual editor for the entire environment

This is where mooi can become more than a predefined desktop environment. The customization system should eventually allow people to construct and change the experience itself. The visual editor should include:

- Component placement and sizing.
- Theme and token editing.
- Layout and spacing controls.
- Motion timeline and easing controls.
- Component states and interaction mapping.
- Widget configuration and composition.
- Shader and visual-effect controls where supported.
- Preview modes for different screen sizes and layouts.
- Configuration validation, undo, redo and versioned presets.
- An advanced configuration mode for precise manual control.

We should make simple customization easy without hiding advanced functionality from people who want to experiment. For example, someone could change a widget's geometry visually, adjust its hover response, change its accent role, preview the result and save it as a reusable component.

The editor itself should use the same design system it edits. It should not look like a separate, unrelated application.

## 10. A system built around reusable components

To make all of this manageable, mooi needs a shared foundation, layered top to bottom:

1. **Design tokens and theme engine.** Colors, typography, surfaces, geometry, motion and effects.
2. **Shared component and interaction system.** Controls, menus, dialogs, widgets, layouts and contextual actions.
3. **System settings.** Configuration and system services.
4. **Desktop interfaces.** Widgets, menus, file manager and controls.
5. **Pleamar + Hyprland + Linux services.** Rendering, window management, hardware, networking, audio and operating-system integration.

The exact implementation can evolve, but the architectural principle matters: shared components should read from common theme tokens and settings, and changes should propagate consistently.

We should not build every application from scratch merely to achieve visual consistency. Some pieces should be native mooi components; others should integrate existing Linux tools. The priority is a coherent, reliable experience.

## 11. Customization without sacrificing reliability

A highly customizable environment can become fragile if every visual choice is implemented as a separate script or configuration hack. mooi should therefore provide:

- A central configuration model.
- Persistent settings with clear ownership.
- Theme and layout import/export.
- Reusable presets and user-defined variations.
- Validation before applying risky changes.
- Undo and reset mechanisms.
- Safe fallback themes and layouts.
- Diagnostics for missing modules or failed integrations.
- Reduced-motion and performance profiles.
- Clear separation between user configuration and system defaults.

A setting should be changed once and propagated through the system, rather than requiring the user to manually edit several files.

## 12. Our development roadmap

We have a large vision, but the implementation should proceed in deliberate stages.

1. **Phase 1 · The foundation.** Establish the design tokens, theme engine, configuration architecture, component conventions and shared motion rules. Ensure the existing Pleamar implementation remains stable.
2. **Phase 2 · The complete visual identity.** Implement the core palette, wallpaper-based color generation, typography, icons, application theme integrations, surfaces and consistent shell components.
3. **Phase 3 · Settings and personalization.** Create the central settings interface, component configuration, layout controls, shortcuts, animation settings and theme management.
4. **Phase 4 · Everyday desktop experience.** Build or integrate the file manager experience, desktop widgets, notifications, application launch actions and polished system controls.
5. **Phase 5 · Spatial interaction.** Develop the workspace overview, window manipulation, saved environments, contextual actions and deeper integration with the desktop's existing interaction model.
6. **Phase 6 · Creative tooling.** Develop the visual editor, advanced customization, reusable components, effect authoring and deeper personalization tools.

These phases can overlap where practical, but the foundation should come first. It will prevent every subsequent feature from inventing its own theme, settings and behavior.

## The final goal

mooi should feel like a complete, carefully engineered operating environment built on top of Linux: visually distinctive, mechanically expressive, fluid to use, practical for daily work and extraordinarily customizable.

A user should be able to change the wallpaper and have the palette adapt; adjust a theme ingredient and see it propagate; redesign the workspace layout; configure widgets; tune animations; customize the terminal; control available system settings; and eventually build new components through a visual editor.

Everything is connected. Everything is configurable. Everything belongs to the same design language.

And the guiding principle is this: mooi gives people a powerful system to shape their own computing environment, without requiring them to become system engineers just to make it their own.
