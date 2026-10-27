# Control Nexus drawer — Implementation Plan

> Executed inline (superpowers:executing-plans).

**Goal:** replace the node-graph Nexus and its hub with one right-side drawer that holds everything
and where every tile acts. **Spec:** docs/superpowers/specs/2026-10-27-nexus-drawer-design.md

## Global Constraints

- Same program name (`mooi-nexus`), same opening path (bar mark → `open_nexus`; `mooi nexus`).
- Island kit for every visual (ui/island.plm); `isl_style` and `cn_*` facts set from settings.
- Read only while open; `spawn` gets `function() end` for the line callback; zone `active:` = takes
  presses; `upper()` only on named texts; theme tokens not in scene-level `let`s.
- `bin/mooi check` green after each task; commit per task; push at block ends.

## Review Focus

1. A click on another window closes the drawer (blur) — but a press inside never does.
2. No battery / no backlight / no Bluetooth adapter / no Wi-Fi: those rows hidden, not "—".
3. Nothing playing: the Now playing section is absent, not empty.
4. The bar not running (feed/updates files missing): those sections say so, not crash.
5. Long names (SSIDs, devices, app names, track titles) clip to one line.

### Task 1: The bar shares notifications and updates
- lib/nexusfeed.luau (pure, tested): `feed(list, now)` → latest 5 `{app, title, ago}`;
  `updates_doc(total, text)`. signals.luau writes nexus-feed.json on every change; bar.luau writes
  updates.json after every look. A bar event `nexus_clear` clears the notifications.

### Task 2: The drawer program — surface, motion, kit, header, folding
- Rewrite shell/mooi-nexus.plm/.luau: the panel surface, slide in/out, blur closes, the plate body,
  the header (avatar, name, time, Settings/Lock/Power/×), section frames with fold state
  (lib/nexusdrawer, pure, tested: order, fold toggling, persistence shape).

### Task 3: Toggles and levels
### Task 4: Now playing and notifications
### Task 5: Connections (Wi-Fi, Bluetooth) and Sound (outputs, apps)
### Task 6: Machine, Today, Updates, Workspaces, Shortcuts
### Task 7: Retire the old Nexus — libs, tests, settings rows, migration; docs
### Task 8: Verify live in both styles; tests; D98; memory; push
