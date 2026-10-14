# Status

_Last updated 2026-10-14._

## Done

- **Phase 0, audit**: docs/AUDIT.md.
- **Phase 1, first slice**: the Spine, the window island, real Hyprland actions verified by read-back, settings with recovery.
- **Renamed to mooi** (docs/DECISIONS.md D1).
- **Shell switching** (docs/SWITCHING.md): Super+Alt+Space starts mooi beside ArchEclipse or toggles its island, and Super+Alt+Shift+Space stops it. A keeper restarts mooi after a crash. `bin/mooi takeover` is built, and safe by design, but disabled until one guard is added (below). ArchEclipse is always the login shell.
- **Pleamar upgraded to 0.4.6** for everything; 0.3.7 kept for rollback (D4).
- **Phase 2, motion and interaction framework**:
  - One island slot (`open`) with hand-over, an Escape order, and per-island reveal springs: interruptible by construction and tested.
  - Shared `IslandFrame` and `Level` components (`shell/ui/island.plm`), and a recipe for adding islands (ARCHITECTURE.md).
  - A second island, **system**: volume, mute, brightness, battery, network, from Pleamar's services, coalesced requests, shown-as-reported.
  - Motion tokens extended (`m.confirm`: workspace pulse after a move; `m.reflow`: workspace list), 5 measured on every test run; reduced motion tested.
  - Degraded Hyprland IPC tested; frame timing attributed ("smooth", 0.6 % late frames, paint plus vblank, not logic).
- Tests: unit 18 · scene 31 · live 23 · degraded 8 · config 10, all passing on 0.4.6.

## Needs you

1. **One guard for takeover.** The permission system refused my edit to `~/.config/hypr/scripts/quickshell-fullscreen-sync.sh`. The six lines are in docs/SWITCHING.md. Until they are in, `bin/mooi takeover` refuses to run (safely). After adding them, I can test takeover end to end, if you allow it.
2. **Desk and Polkit still run 0.3.7** in memory; they move to 0.4.6 at your next login. If anything looks off there: `cp ~/.local/bin/pleamar-0.3.7 ~/.local/bin/pleamar`.

## Remembered for later

- **Notifications (D5):** ArchEclipse keeps them in beside mode. mooi will claim them only in takeover mode (Phase 6). The alternatives are listed in D5 if you want to change it.

## Known gaps

- Multi-monitor untested (the LG was not connected). The Spine is on one monitor.
- Islands cannot be dismissed by clicking elsewhere (a layer surface does not hear outside clicks). Esc, the Spine buttons, × and 30 s idle dismiss them.
- Global modes (Focus / Explore / …) are still only specified.
- Takeover has no notifications, tray or lock screen of its own yet (lock falls back to swaylock).

## Next concrete step

Phase 3: the Command Membrane, a third island in the slot with a text field, results (apps from the `apps` service, windows from `hyprctl -j clients`, workspaces, mooi settings) and inline actions. Contextual satellites will reuse the window island's actions. The likely key is Super+Alt+Space's sibling, to be decided then.
