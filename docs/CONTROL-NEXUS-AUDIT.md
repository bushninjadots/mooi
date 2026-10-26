# Control Nexus — Phase 0 audit and implementation plan

> **Historical planning note:** this document predates the implemented standalone Control Nexus and contains an earlier recommendation to extend the System island. The implementation decision has since changed: Nexus is a separate Pleamar program (`shell/mooi-nexus.plm` + `shell/mooi-nexus.luau`). For the current architecture, built scope and verification status, use [`NEXUS-AUDIT.md`](NEXUS-AUDIT.md) and [`NEXUS-PROGRESS.md`](NEXUS-PROGRESS.md). The remainder below is retained as historical design context, not the current implementation plan.

Date: 2026-10-23  
Base audited: `main` at `00e72d8730a8dad1e372f5c47f8101409b5b7118`  
Scope: read-only repository audit and safe implementation plan. No runtime files changed in this phase.

## Decision

Build **mooi · Control Nexus** as an evolution of the existing **System island**, not as a second system panel or a new Pleamar scene.

The repository already has one Pleamar scene (`shell/mooi.plm`) and one Luau logic process (`shell/mooi.luau`). The scene owns the shared island slot (`fact open`) and currently supports `none | window | system | command | atlas | shutter | overview`. The existing System island is at `shell/mooi.plm` near line 3993 and uses `open == system`; the bar's system-status modules already route to `open_system`. Creating a second panel or scene would duplicate state and risk keyboard, focus, animation, and service ownership conflicts.

The new name can describe the expanded experience while retaining the current internal `system` slot until there is a tested reason to rename it.

## Repository facts found

- **Runtime:** Pleamar scene `shell/mooi.plm`, logic `shell/mooi.luau`, launcher/supervisor `bin/mooi`.
- **Shared design system:** `shell/lib/theme.luau`, `shell/lib/ferro.luau`, and the scene's shared theme tokens. The wallpaper/Matugen pipeline already exists; reuse it rather than adding a second palette engine.
- **Settings:** versioned schema/defaults/validation are in `shell/lib/config.luau`; settings are stored under `~/.local/share/pleamar/mooi/settings.json` and have recovery behavior. Any new preferences must go through this system or a deliberately documented separate versioned config.
- **Existing system data:** Pleamar services expose audio, brightness, battery, network, Bluetooth, media and other information. The bar already displays media, volume, brightness, battery, network, Bluetooth, resource telemetry and notifications modules.
- **Existing system controls:** the System island currently has a volume level control and optional brightness control, network state, Bluetooth state, and battery status. Its keyboard handling and close behavior are scene rules. Its current size/layout is defined in the existing island.
- **Notifications:** the existing Signal Loom and notification-related UI exist, but notification ownership is intentionally constrained. The repository documents that ArchEclipse remains the notification server in beside mode; declaring Pleamar's notification service without an explicit ownership/hand-off plan can steal `org.freedesktop.Notifications`.
- **Theme/editor:** the bar already has an edit mode and settings UI. A new Control Nexus visual editor should be scoped to the Nexus layout, not replace or silently alter the bar editor.
- **Safe-mode precedent:** `MOOI_SAFE=1` / `bin/mooi run --safe` uses built-in defaults and avoids writing the real settings file.
- **Test infrastructure:** `bin/mooi check`, unit tests, scene/motion tests and integration/degraded/config-recovery suites exist. Some suites require the actual desktop and system services.

## Important environment and validation caveat

This audit used repository files available through GitHub. It did **not** run the code on the user's machine, inspect the current live desktop, verify installed services, or execute the test suite. The machine-specific audit in `docs/AUDIT.md` is historical and must not be treated as proof that every service or dependency is currently available.

Before any runtime edits, fetch the current working tree on the user's machine and run the baseline checks there. Do not upgrade Pleamar, change the login shell, alter Hyprland bindings, or touch ArchEclipse configuration as part of this feature's first slice.

## Desired experience

Open Control Nexus from a small Arch mark/icon within the existing bar. Preserve the current bar and its layout. The surface should feel like a structured, spatially expanding instrument: graphite/charcoal foundations, existing wallpaper-adaptive semantic accents, precise technical typography, machined/chamfered geometry and restrained motion. It must express all six mooi design directions without becoming a generic rounded-card dashboard:

1. **Spatial & Futuristic** — layered zones and clear depth.
2. **Industrial & Technical** — machined edges, readouts, measured alignment.
3. **Organic & Fluid** — restrained spring motion and adaptive transitions.
4. **Minimal & Elegant** — deliberate hierarchy and no decorative clutter.
5. **Cyberpunk & Expressive** — controlled accent signals, not constant neon.
6. **Playful & Interactive** — responsive, tactile controls with clear feedback.

## Proposed module scope

Implement only capabilities that can be connected to a verified existing API/service. Missing services must produce an honest unavailable state, never a fake working control.

1. **Identity header:** editable display label and optional avatar. Local-only by default; no network account dependency.
2. **System controls:** volume/mute and brightness using the existing Pleamar services and verified write events. Network and Bluetooth should initially be status/read-only unless a supported, verified write path exists.
3. **Media:** current player and transport using the existing media service/actions. Show no fabricated track or player state.
4. **Telemetry:** CPU/RAM/temperature/network rate only where current, bounded readers already exist or can be added without blocking the render thread. Start readers only while the Nexus needs them and stop them when closed.
5. **Notifications:** integrate with the existing Signal Loom only where current ownership permits. Do not claim that notifications are available in beside mode unless a real, tested bridge exists.
6. **Quick actions:** reuse existing mooi actions and report failures. Avoid shell-string interpolation; use fixed command names/argument arrays and validate user-controlled input.
7. **Layout editor:** initially edit Nexus module visibility, order, size and placement only. Use a draft state, preview, undo/reset, validation, and explicit save/apply. Do not modify the bar's own layout as a side effect.

## Safe architecture rules

- Keep a single Pleamar scene and the existing shared island lifecycle.
- Reuse the existing `open_system` event and island slot for the first vertical slice.
- Reuse theme tokens and the current validated settings pipeline.
- Never block the render thread on commands, filesystem operations or services.
- Treat service/compositor reports as the source of truth; show requested values only after confirmation.
- Preserve Escape and other scene-level dismissal paths, and make all motion interruptible.
- Avoid a full-screen input-catching surface; keep the interactive bounds to the visible panel.
- Do not introduce a second notification daemon, a new framework, a new scene, or an alternative config system.
- Keep new controls unavailable rather than presenting a misleading control if the underlying system API is absent.
- Do not change login/takeover behavior or the existing bar as part of the first slice.

## Phased implementation

### Phase 0 — audit only (this document)

No runtime changes. Confirm architecture, existing services, lifecycle and hazards. Done for repository-level review; machine baseline remains to be run locally.

### Phase 1 — safe visual foundation

- Add a small, accessible Arch mark trigger to the existing bar, after checking the current mark/menu and available bar geometry.
- Route it to the existing System island; preserve existing keyboard and close rules.
- Expand the existing island into the Control Nexus shell with a responsive, bounded layout.
- Initially use existing reported values and existing controls only.
- Add/extend scene tests for open, close, Escape, hand-over, reduced motion, and no duplicate surfaces.

### Phase 2 — verified real integrations

- Add media and telemetry only after checking the current service contracts and the actual Pleamar version.
- Add read/write behavior one integration at a time, with read-back and degraded-service tests.
- Keep notification ownership unchanged until a separate explicit hand-off design is tested.

### Phase 3 — identity and theme

- Add local identity preferences through validated configuration.
- Reuse the current Matugen/theme token pipeline.
- Verify contrast and missing-avatar behavior.

### Phase 4 — motion and placement

- Add the spatial expansion/retraction animation using existing spring conventions.
- Test interruption, fast repeated toggles, multi-monitor placement and reduced-motion behavior.
- Close on outside click only if Pleamar's layer/input model can support it without stealing clicks or trapping keyboard focus. Otherwise retain reliable Escape, trigger and close-button dismissal.

### Phase 5 — Nexus layout editor

- Add a Nexus-only edit mode with drag/reorder/resize, preview, undo/reset, and validated persistence.
- Save atomically with versioning and recovery.
- Never execute code from imported presets; accept data-only, schema-validated layouts.

### Phase 6 — polish

- Run the available local test suites, then manual checks with actual services.
- Measure idle CPU/RAM, open-panel frame time and interaction latency.
- Verify that the existing bar, settings, workspace overview, notification owner and shell switching still behave as before.

## Baseline checklist before Phase 1

Run on the actual machine from the checked-out repository:

1. `git status --short --branch` and preserve all existing uncommitted work.
2. Record `git rev-parse HEAD`; confirm the working tree corresponds to the intended branch.
3. Run `bin/mooi check` and the existing unit suite before edits.
4. Run the scene/motion suite in its documented safe setup.
5. Record Pleamar version and availability of the services used by the current System island.
6. Inspect the current bar mark/menu and the current `system_island` layout before choosing the icon's exact placement.
7. Do not run integration tests that manipulate real windows, volume, brightness or shell takeover without first reading their scripts and confirming they are safe in the current session.

## Acceptance criteria for the first implementation slice

- The existing bar remains visually and functionally intact except for the intentional Nexus trigger.
- The trigger opens exactly one panel using the existing island slot.
- The panel displays only values reported by real services.
- Volume/mute and brightness actions work through existing supported paths and reflect read-back state.
- Missing services do not crash the scene or display false controls.
- Escape, close button and trigger dismissal work; rapid open/close does not leave a stuck surface.
- No notification ownership changes, shell takeover changes, dependency upgrades, or writes to the user's live settings happen as part of development tests.
- The local baseline and new tests pass; machine-only checks are explicitly reported rather than assumed.

## Next action

Start with a local read-only baseline and inspect the current `system_island` and bar mark. Then implement Phase 1 on this feature branch only. Do not merge to `main` until the user has reviewed the diff and the local tests pass.
