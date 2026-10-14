# Testing

All commands run from the repo root. Stop any running mooi first (`bin/mooi stop`); the scripts refuse to start beside one.

| Command | What | Touches the session? | Last result (Pleamar 0.4.6) |
| --- | --- | --- | --- |
| `bin/mooi check` | compiles the scene; unit tests for `lib/config`, `lib/hypr`, `lib/apps` under Lua 5.4 | no | 18 tests, 0 failed |
| `tests/scene.sh` | the real scene about 25 s: both islands, the slot hand-over, Escape order, rapid and mid-animation switching, 5 motion tokens via `--record`, reduced motion | shows mooi; an island holds the keyboard while open; no actions, no volume or brightness changes | 26 + 5 checks, 0 failed |
| `tests/integration.sh` | every window action on throwaway `kitty --class mooi-probe` windows (verified with `hyprctl`), the move pulse, a vanished window; volume, mute and brightness verified with `wpctl`/`brightnessctl`, slider floor, request bursts | **yes**: probe windows, workspace 9, volume, mute and brightness changed briefly and **restored** | 23 checks, 0 failed |
| `tests/degraded.sh` | mooi with Hyprland's IPC unreachable | shows mooi | 8 checks, 0 failed |
| `tests/config-recovery.sh` | good, broken and partly-wrong `settings.json`, and safe mode | backs up and restores the real settings | 10 checks, 0 failed |

## Phase 2 acceptance

| Criterion | Evidence |
| --- | --- |
| Surface states defined once, used by more than one surface | `open` slot + `IslandFrame`; window and system islands (ARCHITECTURE.md) |
| Interruption-safe transitions | scene.sh: window → system → window in 120 ms ends clean; 4 toggles in 240 ms; reopen and close mid-way |
| Motion tokens exist and hold | scene.sh: enter 182/180, exit 151/140, expand 201/200, collapse 161/160, system enter 190/180 ms |
| Keyboard focus and dismissal | only the open island holds the keyboard; Esc order: confirmation → expanded → island (scene.sh) |
| Reduced motion | scene.sh: 0 frames between open and closed |
| Rapid and repeated interactions validated | scene.sh; integration.sh: 11 volume requests in a burst end on the last |
| Real system state, shown as reported | integration.sh: wpctl / brightnessctl / hyprctl agree with what mooi shows |
| Degrades without Hyprland IPC | degraded.sh |
| Frame timing | `pleamar --report`: "smooth · 60 fps against 60 Hz", 4 of 672 frames late (0.6 %), none over 2.5 periods. The late ones are paint 7 ms + waiting for the screen, not rules (0.03 ms) |
| Idle cost | 0.2 % CPU (no island) · 0.4 % (island open) · 24 MB PSS |
| Supervision | keeper restarts a killed scene (tested); `bin/mooi stop` leaves no keeper or marker |

## Manual checks

1. Super+Alt+Space: mooi appears beside ArchEclipse. Press it again: the window island grows out of the top Spine button.
2. Click the battery button at the bottom of the Spine: the system island grows upwards out of it, and the window island leaves.
3. Drag the volume level and scroll over it; ↑↓ choose the row, ←→ adjust, `m` mutes.
4. Move a window to another workspace from the window island: that workspace's number in the Spine pulses.
5. Super+Alt+Shift+Space: mooi goes; ArchEclipse is untouched.

## Not tested yet

Takeover end to end (blocked, see SWITCHING.md), multi-monitor (LG not connected), scale ≠ 1, hotplug, fullscreen apps over the Spine, settings changed mid-animation, input-to-visible latency, and a long-session memory trend.
