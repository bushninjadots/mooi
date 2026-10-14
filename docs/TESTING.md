# Testing

All commands run from the repo root.

| Command | What | Touches the session? | Last result |
| --- | --- | --- | --- |
| `bin/tidal check` | compiles the scene; unit tests for `lib/config`, `lib/hypr`, `lib/apps` under Lua 5.4 | no | 18 tests, 0 failed |
| `tests/scene.sh` | runs the real scene about 15 s; drives keys and events through `pleamar --say`; checks `phase`/`sel`/`arming`; rapid-toggle interruption; measures 4 motion tokens with `--record` | shows the Spine and island; **the island holds the keyboard while open**; no Hyprland actions | 15 + 4 checks, 0 failed |
| `tests/integration.sh` | every island action against throwaway `kitty --class tidal-probe` windows, each verified with `hyprctl -j clients`; move to workspace 9; acting on a vanished window | **yes**: opens probe windows, moves one to workspace 9, closes them, restores focus | 16 checks, 0 failed |
| `tests/config-recovery.sh` | good, broken and partly-wrong `settings.json`, and safe mode | backs up and restores the real settings | 10 checks, 0 failed |

Stop any running Tidal first (`bin/tidal stop`). The scripts refuse to start beside one.

## Acceptance criteria: slice 1

| Criterion | Evidence |
| --- | --- |
| A Spine on the left edge that reserves its space and coexists with ArchEclipse | 48×1048 at (0,32) under the 32 px top band (`hyprctl layers`); screenshots |
| One Island with a coherent lifecycle, opened from the keyboard (`bin/tidal open`) and the pointer | scene.sh |
| Keyboard: ←/→/Tab select, Enter/Space apply, Esc collapses → dismisses, Esc cancels a pending close | scene.sh |
| Interruption: rapid toggles settle in the right state with no stuck surface | scene.sh (4 toggles in 240 ms; reopen and close mid-way) |
| Real Hyprland operations, verified by reading back | integration.sh: float, pin, fullscreen, close (with confirmation), move to workspace |
| Honest failure | integration.sh: "That window is gone"; unit: verify() never reports an unchanged window as done |
| Motion tokens hold their contract | scene.sh: enter 183/180, exit 134/140, expand 200/200, collapse 168/160 ms |
| Settings: validated, recoverable, safe mode | config-recovery.sh |
| Reduced motion | `--reduced-motion` with `--record reveal`: 0 frames mid-transition, open → closed directly |
| Near-zero idle | 0.10–0.13 % CPU, 35 MB PSS (AUDIT.md §6) |

## Manual checks (not automated)

1. `bin/tidal run`, then click the Spine's top button: the island grows out of it. Click it again: it folds back into it.
2. Hover the workspace numbers: they highlight. Click one: Hyprland switches to it.
3. With a window focused, `bin/tidal open`, then Move (→ → → Enter), → to choose, Enter: the window moves and the island closes. You stay where you were.
4. `bin/tidal run --reduced-motion`: open and close land at once, with no movement.
5. Write `{"spine":{"clock":` into `~/.local/share/pleamar/tidal/settings.json` while it runs: an orange dot appears above the clock, and nothing else changes.

## Not tested yet

Multi-monitor (only eDP-1 was connected), scale ≠ 1, monitor hotplug, a fullscreen app covering the Spine, crash recovery under a supervisor, input-to-visible latency, Hyprland IPC failure mid-action, and a long-session memory trend.
