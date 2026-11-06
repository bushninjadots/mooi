# Architecture

_Last checked against `main`: 2026-11-06. This describes the implementation that exists now, not the original proposed architecture. For intended future behaviour, see [VISION.md](VISION.md), [PHILOSOPHY.md](PHILOSOPHY.md) and [BRIEF.md](BRIEF.md). For reusable visual component rules, see [COMPONENT-SYSTEM.md](COMPONENT-SYSTEM.md). For verified test results and their dates, see [TESTING.md](TESTING.md) and [STATUS.md](../STATUS.md)._

## 1. System boundary

mooi is a desktop shell built on **Pleamar 0.7.11 (language 0.9)** and **Hyprland**.

- **Pleamar** owns scene rendering, scene input, surfaces, facts, models, events and the process that runs each scene.
- **Hyprland** remains authoritative for windows, focus, workspaces, monitors and compositor operations. mooi asks Hyprland to perform actions and reads back the resulting state; it does not maintain a competing window-manager state.
- **The Linux system** remains authoritative for hardware and desktop services such as audio, brightness, battery, network and Bluetooth. mooi presents reported state and uses the relevant system tools or Pleamar services for actions.
- **mooi's launcher and keeper** (`bin/mooi`) start, stop, refresh and supervise the shell. The keeper restarts a scene after a crash and has a bounded give-up rule. Takeover/session modes have explicit hand-back behaviour.

mooi is not a replacement compositor or a second window manager. It is a coordinated set of shell scenes and integrations that sit on top of Hyprland.

## 2. Runtime shape

The implementation is no longer the original one-scene prototype. The persistent shell and several substantial surfaces are separate Pleamar programs.

| Program / scene | Responsibility |
| --- | --- |
| `shell/mooi.plm` + `shell/mooi.luau` | Main shell scene: Ferrolume bar, island slot, workspace state, Overview integration and the shell's primary interactions |
| `shell/mooi-settings.plm` + `shell/mooi-settings.luau` | Settings window; edits the same validated settings document used by the shell |
| `shell/mooi-nexus.plm` + `shell/mooi-nexus.luau` | Control Nexus and its system/control views |
| `shell/mooi-notch.plm` + `shell/mooi-notch.luau` | Side notch and its contextual panels |
| `shell/mooi-player.plm` + `shell/mooi-player.luau` | Music player |
| `shell/mooi-board.plm` + `shell/mooi-board.luau` | Kanban board |
| `shell/mooi-frame.plm` + `shell/mooi-frame.luau` | Screen frame: the band and bar chassis, its own program |
| `shell/mooi-desk.plm` + `shell/mooi-desk.luau` | Desk scene / desktop integration |
| `shell/mooi-walls.plm` + `shell/mooi-walls.luau` | Wallpaper picker (Lumen was removed, D118) |
| `shell/mooi-viz.plm` + `shell/mooi-viz.luau` | Visualiser program (D155) |
| `shell/mooi-widgets.plm` + `shell/mooi-widgets.luau` | Desktop widgets |
| `shell/mooi-lock.plm` + `shell/mooi-lock.luau` | Lock screen (D160) |

BMO has its own logic and UI resources under `shell/bmo/`. Shared visual building blocks live under `shell/ui/`; the component contract is documented in [COMPONENT-SYSTEM.md](COMPONENT-SYSTEM.md). Theme definitions and Ferrolume styling live under `shell/theme/`. Player-specific code is grouped under `shell/player/`.

The separate programs are intentional: large, independently opened tools should not take keyboard routing or lifecycle ownership away from the persistent bar. They are not separate desktop environments. The launcher creates links so the programs share mooi's data directory and therefore the same settings, palette and relevant saved documents.

### Lifecycle and launch

Use `bin/mooi` as the supported entry point. It provides the start/stop/toggle/status commands, opens named surfaces, launches standalone tools, performs theme operations, refreshes the running snapshot and runs the project check. It also owns the keeper, runtime markers, scene process discovery and the shared-data links.

Do not add a second independent supervisor or start duplicate scene processes from ad-hoc shell commands without first checking how `bin/mooi` manages that scene. Preserve its locking, recovery and takeover rules.

## 3. State ownership and communication

The central rule is **one authoritative owner per kind of state**.

| State | Authority | How mooi uses it |
| --- | --- | --- |
| Windows, focus and workspaces | Hyprland | Reads through Hyprland/Pleamar integration; requests actions and confirms them against compositor state |
| Hardware and system status | Linux services / Pleamar services | Displays reported values; does not treat a requested value as confirmed until the system reports it |
| Main island slot and its visible phase | Main scene rules | Scene-side state keeps keyboard dismissal and surface hand-over responsive |
| User preferences | Shared `settings.json` | Validated against `shell/lib/config.luau`; defaults and recovery protect against malformed settings |
| Theme palette | Matugen output plus theme settings/overrides | `shell/lib/theme.luau` validates palette completeness and contrast before applying it |
| Saved tool data | The relevant JSON documents in mooi's shared data directory | Each tool owns its document shape and reads/writes through its own logic |
| Workspace map | `shell/lib/spaces` and compositor reports | Shared representation used by the bar and Overview; it is not a second compositor database |

The main scene uses Pleamar facts, models, events and scene rules for its live UI. Logic is separated into Luau modules and scene logic files. Standalone programs share persistent documents through the data-directory links created by the launcher; do not assume that arbitrary in-memory state is shared between Pleamar processes.

When implementing a feature, first identify its state owner and persistence boundary. Avoid mirrored state that can disagree with Hyprland or another scene.

## 4. Configuration and persistence

The primary user configuration is:

```text
~/.local/share/pleamar/mooi/settings.json
```

The schema, defaults, validation and recovery behaviour live in `shell/lib/config.luau`. Settings are applied live where supported. Invalid documents should produce a useful diagnostic and fall back safely; do not silently discard a malformed section or write an unvalidated value.

Other saved documents include the generated theme palette and tool-specific data such as wallpaper and board state. Standalone scenes use links into the shared mooi data directory so they operate on the same documents rather than maintaining divergent copies.

When adding a setting:
1. Add it to the canonical schema with a default and validation.
2. Define its meaning and units.
3. Connect the settings UI to that schema rather than inventing a second source of truth.
4. Ensure old or partial settings files remain safe.
5. Add tests for defaults, valid values, invalid values and persistence/recovery.

## 5. Theme system

The theme system is a shared platform feature, not a collection of unrelated component colours. The portable theme-package data model is documented in [THEME-PACKAGES.md](THEME-PACKAGES.md); it captures visual settings only and preserves unrelated user configuration when applied.

- Matugen derives a palette from the selected wallpaper when wallpaper theming is enabled.
- mooi maps palette values to semantic roles in its theme layer.
- User overrides are applied and checked for completeness and contrast.
- A valid theme is applied to the running shell; a rejected theme leaves the last known-good appearance in place.
- Ferrolume has its own role mapping in `shell/lib/ferro` / `shell/theme/ferrolume.plm`, derived from the shared palette.
- App adapters extend the palette to supported GTK, Qt/KDE, Kitty and icon-theme surfaces.

The main theme logic is in `shell/lib/theme.luau`; the launcher exposes `theme-sync` and `theme-watch`. Keep semantic tokens as the interface between palette generation and UI components. Do not hard-code a new independent palette into a widget.

The current implementation is not a universal theme engine for every Linux application. Adapter coverage is explicit and depends on the target toolkit and app.

## 6. Main interaction model

The main scene owns the persistent bar and its primary shell interactions. The Ferrolume bar is the current implementation; the older Mechanism concept is design history, not the active bar.

The shell's island slot is scene-owned. Opening another island hands the slot over rather than allowing unrelated islands to compete for focus. The Overview uses Hyprland workspace/window state and offers multiple presentations and saved environments. Window and workspace actions must remain requests to Hyprland, with results confirmed from the compositor.

The settings window, Nexus, notch, player, wallpaper studio and board are separate programs with their own scene lifecycle. Shared styling and shared saved data do not mean their transient UI state should be duplicated in the main scene.

## 7. Safety and degraded operation

Preserve these existing boundaries:

- Keep Pleamar scene `permissions` allowlists narrow and specific to the scene.
- Pass command arguments as argument arrays; do not build shell command strings from user-controlled values.
- Validate window addresses and other identifiers before using them in compositor commands.
- Treat filenames, search queries, settings files and external service responses as untrusted input.
- Keep safe-mode and last-known-good configuration/theme recovery paths working.
- Missing optional tools should disable or degrade the relevant feature with a clear explanation, not prevent the core shell from starting.
- Be explicit about external data requests. For example, the weather feature uses IP-based location lookup and a forecast provider; keep its activation and privacy behaviour documented.

These are design and implementation guardrails, not a claim that the project has undergone a formal penetration test.

## 8. Testing and verification

The local project gate is:

```sh
bin/mooi check
```

It checks scene compilation with the installed Pleamar version, parses the Luau logic with Lua 5.4, runs the pure unit suites and reports optional dependencies. Behavioural suites under `tests/` cover live scene interactions, recovery, degraded operation, surfaces, pointer input and individual tools. Some suites alter the live session or start real applications; read [TESTING.md](TESTING.md) before running them.

GitHub Actions runs `tests/gate.sh`, the same portable static checks, unit suites and sandboxed suites `bin/mooi check` starts with. It does **not** compile Pleamar scenes, because the workflow does not provision the project's Pleamar 0.7.11 binary. A green CI run therefore does not replace `bin/mooi check` on a machine with the supported Pleamar version.

Treat test evidence as dated. A suite's historical green result is not proof that it passed on the current commit. Do not update test counts or claim a suite passed unless it was actually run.

## 9. Current constraints and known gaps

These are implementation boundaries, not invitations to pretend unfinished work exists:

- Multi-monitor behaviour is still an open area. Test on more than one monitor before claiming full support.
- Some standalone-session responsibilities and integrations still need coverage; consult [SWITCHING.md](SWITCHING.md) and the dated status notes.
- CI does not compile Pleamar scenes yet.
- The main scene and settings scene are large files. Refactor incrementally around clear ownership and tested modules; avoid splitting code merely to reduce line counts.
- The current settings centre is primarily mooi's settings surface, not a complete replacement for every operating-system settings utility.
- A general-purpose desktop widget framework, full file manager, visual layout/component editor and shader/VFX authoring environment are future product work, not capabilities to assume are already present.

## 10. Rules for future contributors and coding agents

Before changing code:

1. Read this file for the actual architecture.
2. Read [STATUS.md](../STATUS.md) for the current verified state and open work.
3. Read [DECISIONS.md](DECISIONS.md) before changing an established design decision.
4. Read [TESTING.md](TESTING.md) and choose the narrowest relevant tests.
5. Trace the existing state owner, config schema, permissions and launcher path before adding a parallel implementation.

After changing code:

1. Add or update tests at the layer where the behaviour belongs.
2. Run the relevant tests and record exactly what was run.
3. Update status and documentation when the implementation or evidence changes.
4. Keep the six design directions in [PHILOSOPHY.md](PHILOSOPHY.md) intact without turning them into six disconnected visual themes.

When documents disagree, prefer the current source code and dated test evidence for what exists, [DECISIONS.md](DECISIONS.md) for accepted historical decisions, and [VISION.md](VISION.md) / [BRIEF.md](BRIEF.md) for intended future direction. Do not treat an old specification checklist as proof of current implementation.
