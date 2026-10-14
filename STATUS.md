# Status

_Last updated 2026-10-14._

## Done

- **Phase 0, audit**: machine, Pleamar (docs, source, upstream) and Hyprland integration, all verified by experiment. See `docs/AUDIT.md`.
- **Phase 1, slice 1**, all on Pleamar 0.3.7 over Hyprland 0.56.2:
  - The Spine: a 48 px left rail with the focused window's icon (resolved through .desktop files), live workspaces (click to switch), and a clock.
  - Window satellite island: Float / Fullscreen / Pin / Move to workspace / Close (with confirmation). Each action is verified against Hyprland afterwards.
  - Lifecycle hidden ⇄ compact ⇄ expanded, interruptible, with measured motion tokens and reduced motion.
  - Settings: versioned JSON, validation, known-good fallback, safe mode, live reload.
  - Tests: unit (18), scene lifecycle and motion (19), live Hyprland (16), config recovery (10). All pass.

## Decisions taken (reversible)

| Decision | Why |
| --- | --- |
| One scene, several named surfaces | Pleamar scenes share no state (G22) |
| `phase` is owned by scene rules, not the logic | Escape keeps working even if the logic hangs |
| Window actions target an **address** captured on open; success comes from read-back | Hyprland answers "ok" for missing windows |
| JSON for settings | The only format Pleamar reads and writes; atomic writes |
| Motion tokens are critically damped springs `m.*` | `spring k,c` = `~Tms` when k=(6.64/T)², c=2·6.64/T; measured |
| `--stall 0` | Pleamar's default 600 ms logic block is a demo setting |
| Move uses `follow = false` | The satellite moves the window, not you (setting `island.follow_on_send`) |
| Repo at `~/Projects/mooi` | Empty dir you launched from; already ignored by the `~` dotfiles repo |

## Needs your decision

1. **Global shortcut.** Super+Space is your float toggle. Bind `bin/tidal open` to something free (e.g. Super+Alt+Space or Super+W)? Nothing in your Hyprland config has been changed.
2. **Running it daily.** `bin/tidal run` is manual. Starting it at login means adding an `exec` line (a reversible change to `exec.lua`) and a supervisor like `pleamar-keep`. The Spine also reserves 48 px on the left for as long as it runs.
3. **Pleamar 0.3.7 → 0.4.6.** Upstream moved five releases on the audit day. Upgrading the shared `~/.local/bin/pleamar` also affects Desk and Polkit. The alternative is a separate binary just for Tidal.
4. **Notifications (Phase 6).** Pleamar can only be *the* notification server. Either Tidal takes over from ArchEclipse (with a switch, as Marea does) or it shows ArchEclipse's notifications some other way.

## Known gaps

- Multi-monitor untested (the LG was not connected). The Spine is on one monitor.
- Frame p99 22 ms and max 31 ms during animation: some frames are late at 60 Hz, cause not yet attributed (`pleamar --report` is the next tool).
- The island cannot be dismissed by clicking elsewhere (a layer surface does not hear clicks outside it). Esc, the Spine button, × and 30 s idle all dismiss it.
- Global modes (Focus / Explore / …) are specified, not implemented.
- No crash supervisor for Tidal yet.

## Next concrete step

Phase 2: extract the island lifecycle into a reusable component (a second island, the Command Membrane, will be its first user), add `pleamar --report` frame attribution, and test with the LG attached.
