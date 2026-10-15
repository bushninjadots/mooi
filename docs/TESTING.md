# Testing

All commands run from the repo root. Stop any running mooi first (`bin/mooi stop`); the scripts refuse to start beside one.

| Command | What | Touches the session? | Last result (Pleamar 0.4.6) |
| --- | --- | --- | --- |
| `bin/mooi check` | compiles the scene; unit tests for `lib/config`, `lib/theme`, `lib/hypr`, `lib/apps`, `lib/search`, `lib/spaces` under Lua 5.4 | no | 43 tests, 0 failed |
| `tests/scene.sh` | the real scene: the bar (the Mechanism) and its regions, islands, command membrane and Workspace Atlas (its slots, its window tiles, its pictures, its move strip and previews switch), slot hand-over, Escape order, rapid and mid-animation switching, 9 motion tokens via `--record`, reduced motion | shows mooi; an island holds the keyboard while open; no window actions, results opened, workspace switches, volume or brightness changes | 68 state checks + 9 motion checks, 0 failed |
| `tests/integration.sh` | every window action on throwaway `kitty --class mooi-probe` windows, Atlas workspace focus/create, **moving a window to another workspace from the Atlas**, the previews switch, membrane results/satellites, **the compositor's own keyboard (`wtype`: typing into the field, Escape, the Atlas)**, and system controls | **yes**: focuses windows/workspaces, moves one window and briefly changes volume, mute and brightness; all restored | 56 checks, 0 failed |
| `tests/degraded.sh` | mooi with Hyprland's IPC unreachable | shows mooi | 8 checks, 0 failed |
| `tests/config-recovery.sh` | good, broken and partly-wrong `settings.json`, a choice made in the Atlas being written down and read back, and safe mode | backs up and restores the real settings | 13 checks, 0 failed |
| `tests/theme.sh` | the colour pipeline live: the fixed palette, a staged wallpaper palette, an override, an unreadable palette refused whole, and a **real Matugen run** from the wallpaper on screen (`bin/mooi theme-sync`); then that a palette change touches colour facts only | shows mooi; runs Matugen | 28 checks, 0 failed |

## Phase 5 acceptance (first slice: the colour half)

| Criterion | Evidence |
| --- | --- |
| Semantic tokens, not hardcoded colours in components | `shell/theme/tokens.plm`; components read `bg.*`, `surface.*`, `fg.*`, `accent.*`, `status.*`, `focus.ring`, `selection.bg`; `tests/unit` checks all fourteen exist |
| The configuration and override model | `theme.source` (`fixed` \| `wallpaper`) and `theme.overrides` (token = colour) in `settings.json`, validated by `lib/config.luau` (enum and colour kinds, unit-tested); precedence: fixed → wallpaper → overrides, in `lib/theme.luau`, unit-tested |
| Wallpaper colours, from the verified Matugen workflow | Matugen 4.2.0, mooi's own config (`theme/matugen.toml.in`, `theme/palette.json.hbs`) so nothing of the user's theming is written; `bin/mooi theme-sync` runs it and mooi picks the palette up live (`files:palette.json`); `tests/theme.sh` compares the painted facts with the palette's own hex values, including a real run from the current wallpaper |
| Validation and recovery | Completeness and WCAG contrast checks per token pair (`lib/theme.luau`, unit-tested); a theme that fails is refused **whole** — `tests/theme.sh` checks the facts still hold the last good theme and the Spine's dot is lit; `theme_error` is shown with a reason in the log |
| Wallpaper updates never reset user settings, or anything else | `tests/theme.sh`: `settings.json` byte-identical across every palette change, and `ws_max`, `show_clock`, `previews` and `phase` unchanged — colour facts are the only thing a palette writes |
| Not in this slice | light scheme, named theme packages, a Workshop editor for it, automatic wallpaper hook (the user's one line, D11) |

## Phase 4 acceptance (multi-monitor still open)

| Criterion | Evidence |
| --- | --- |
| Bounded map of positive workspaces, including empty slots | `lib/spaces.luau`; clamps to 1–16 configured slots; excludes special/invalid identifiers; `scene.sh` checks the map read from the live service |
| Current workspace and window counts come from Hyprland's service | scene `workspaces` service model; no local state mirror |
| Keyboard and pointer can select; Escape dismisses | `scene.sh` (selection, dismissal, no workspace switched); `integration.sh` opens it and closes it with a **real** Escape from the compositor |
| Focus/create closes only after workspace service confirms active | `atlas_go` waits for service updates and reports failure honestly; `integration.sh` switches to workspace 9 through the membrane and `hyprctl` agrees |
| Every tile is a window Hyprland lists, and can be focused | `scene.sh`: `atlas_tiles.count` equals Hyprland's visible windows and tile 0 carries Hyprland's own address; `integration.sh` (live) and a manual run: ↵ on a tile focuses it and the Atlas closes |
| Thumbnails: the compositor's pictures, asked for only while the Atlas is up | `thumbnails.capturing` is true here; `scene.sh` checks the first tile has a picture; `thumbnails.want()` on close |
| A previews switch that stops the capture | `p` flips `atlas.previews`; `scene.sh` checks the first tile loses its picture and `integration.sh` the same live; `config-recovery.sh` checks the choice reaches `settings.json`, and that safe mode does not write it |
| Per-workspace window moves | `m` opens the strip (the `spaces` map), ←→ choose, ↵ moves the selected tile's window through the verified action; `integration.sh` moves a real probe to workspace 9 and confirms it with `hyprctl`, with the user staying where they are and the Atlas still open; `scene.sh` checks the strip, its starting workspace and Escape leaving it |

## Phase 2 acceptance

| Criterion | Evidence |
| --- | --- |
| Surface states defined once, used by more than one surface | `open` slot + `IslandFrame`; window and system islands (ARCHITECTURE.md) |
| Interruption-safe transitions | scene.sh: window → system → window in 120 ms ends clean; 4 toggles in 240 ms; reopen and close mid-way |
| Motion tokens exist and hold | scene.sh measures all nine on every run (1 %→99 % of travel, against the token's own `~`); the numbers of the last full run are in STATUS.md, and nothing here repeats them, so a document cannot go stale on its own |
| Keyboard focus and dismissal | only the open island holds the keyboard; Esc order: confirmation → expanded → island (scene.sh) |
| Reduced motion | scene.sh: 0 frames between open and closed |
| Rapid and repeated interactions validated | scene.sh; integration.sh: 11 volume requests in a burst end on the last |
| Real system state, shown as reported | integration.sh: wpctl / brightnessctl / hyprctl agree with what mooi shows |
| Degrades without Hyprland IPC | degraded.sh |
| Frame timing | `pleamar --report`: "smooth · 60 fps against 60 Hz", 4 of 672 frames late (0.6 %), none over 2.5 periods. The late ones are paint 7 ms + waiting for the screen, not rules (0.03 ms) |
| Idle cost | 0.2 % CPU (no island) · 0.4 % (island open) · 24 MB PSS |
| Supervision | keeper restarts a killed scene (tested); `bin/mooi stop` leaves no keeper or marker |

## Manual checks

1. Super+Alt+Space: mooi appears beside ArchEclipse with the command membrane open. Type an app's name and press ↵: it starts, and next time it ranks higher. Super+Alt+W: the window island grows out of the top Spine button.
2. Click the battery button at the bottom of the Spine: the system island grows upwards out of it, and the window island leaves.
3. Drag the volume level and scroll over it; ↑↓ choose the row, ←→ adjust, `m` mutes.
4. Move a window to another workspace from the window island: that workspace's number in the Spine pulses.
4b. `bin/mooi atlas` (or the Spine's A button): every window is there as a preview; ←→↑↓ move, ↵ focuses that window and the Atlas closes, Esc dismisses. Press `m`: the strip appears and the board makes room for it; ←→ (or a click) chooses a workspace, ↵ moves that window there — stay where you are and watch the Spine pulse, and the Atlas should stay open — and Esc leaves the strip. Press `p`: the pictures go and come back, and the choice is remembered after a restart. Type in the membrane while it is open: it should type, and Esc should close it (both failed before the keyboard fix, AUDIT.md §4).
5. `bin/mooi theme-sync` (optionally with an image), then set `theme.source` to `wallpaper` in `~/.local/share/pleamar/mooi/settings.json`: mooi recolours itself from the wallpaper within a frame, and back with `fixed`. Add an override (`"overrides": { "accent.primary": "#FF00FF" }`) and it wins; point the palette at something unreadable and the Spine shows the dot instead, keeping what it had.
6. Super+Alt+Shift+Space: mooi goes; ArchEclipse is untouched.

## Not tested yet

Launching an app from the membrane (manual check 1: tests never start real apps); takeover end to end (blocked, see SWITCHING.md); multi-monitor (LG not connected); scale ≠ 1; hotplug; fullscreen apps over the Spine; settings changed mid-animation; input-to-visible latency; and a long-session memory trend. In the Atlas, a window moving between workspaces while the move strip is open is not covered, and neither is a move onto the workspace the window already occupies.

`tests/integration.sh` drives real keys through `wtype` (the compositor's virtual keyboard) because the `--say` channel injects keys straight into the scene and would never have caught the keyboard problems it now guards (AUDIT.md §4); it is skipped, saying so, where `wtype` is missing.
