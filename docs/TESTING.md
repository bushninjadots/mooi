# Testing

All commands run from the repo root. Stop any running mooi first (`bin/mooi stop`); the scripts refuse to start beside one.

| Command | What | Touches the session? | Last result (Pleamar 0.4.6) |
| --- | --- | --- | --- |
| `bin/mooi check` | compiles both scenes; parses every logic file (`shell/*.luau`, `shell/lib/*.luau`) with Lua 5.4, since `pleamar --check` does not read the logic; unit tests for the pure libraries under Lua 5.4 | no | 127 tests, 0 failed (2026-10-21) |
| `tests/scene.sh` | the real scene: the bar (the Mechanism) and its regions, the helix — that the blocks on the bar are a contiguous run of ids, that exactly one is the active one, that it sits on the focus slot (read from the chain's own zone in `describe`, so the suite cannot drift from the scene) and that the slot is before the middle of the screen with the module row after it, and that a preview leaves the chain still (the sample is taken with the chain at rest, because a reading taken mid-slide measures the spring) — islands, command membrane and Workspace Atlas (its slots, its window tiles, its pictures, its move strip and previews switch), slot hand-over, Escape order, rapid and mid-animation switching, 9 motion tokens via `--record`, reduced motion | shows mooi; an island holds the keyboard while open; no window actions, results opened, workspace switches, volume or brightness changes | 77 state checks + 9 motion checks, 0 failed (2026-10-20) |
| `tests/integration.sh` | every window action on throwaway `kitty --class mooi-probe` windows, Atlas workspace focus/create, **moving a window to another workspace from the Atlas**, the previews switch, membrane results/satellites, **the compositor's own keyboard (`wtype`: typing into the field, Escape, the Atlas)**, and system controls | **yes**: focuses windows/workspaces, moves one window and briefly changes volume, mute and brightness; all restored | 56 checks, 0 failed |
| `tests/degraded.sh` | mooi with Hyprland's IPC unreachable | shows mooi | 8 checks, 0 failed (2026-10-20) |
| `tests/config-recovery.sh` | good, broken and partly-wrong `settings.json`, a choice made in the Atlas being written down and read back, and safe mode | backs up and restores the real settings | 13 checks, 0 failed (2026-10-20; its old `spine.clock` files now exercise the migration) |
| `tests/apps-sync.sh` | your apps in mooi's palette, in a throwaway XDG tree: `bin/mooi apps-sync` renders Kitty, GTK and Qt with the switches on, puts every file back with them off (Kitty's include, both `gtk.css` files and Matugen's outputs, Qt's scheme paths and `custom_palette`), removes a `gtk.css` mooi created where there was none, removes one whose Matugen output had no saved copy to restore, and covers the edges: a Kitty include with trailing whitespace, a lost `apps.state`, and a `custom_palette` the file never had; a Matugen `output_path` written with spaces, a trailing comment and an absolute path is put back verbatim | no (sandboxed `HOME`/`XDG_*`, `pkill` stubbed) | 41 checks, 0 failed (2026-10-21) |
| `tests/media.sh` | the media transport against a real player: starts its own VLC (two tagged files), checks the bar reads the player the system reports, then play/pause, next and previous — each twice, what mooi shows and what `playerctl` says | shows mooi; starts and stops VLC | 11 checks, 0 failed (2026-10-21) |
| `tests/pointer.sh` | a real pointer press on the bar: Pleamar's fake pointer is moved onto a system module (its x/width read from the scene's own layout) and pressed; the press opens the system island, the pointer reached the scene, and Escape closes it | shows mooi | 3 checks, 0 failed (2026-10-21) |
| `tests/theme.sh` | the colour pipeline live: the fixed palette, a staged wallpaper palette, an override, a wallpaper with unreadable text **lifted** (D24 §5), a theme an override makes unreadable refused whole, and a **real Matugen run** from the wallpaper on screen (`bin/mooi theme-sync`); then that a palette change touches colour facts only | shows mooi; runs Matugen | 31 checks, 0 failed (2026-10-20) |

## Phase 5 acceptance (first slice: the colour half)

| Criterion | Evidence |
| --- | --- |
| Semantic tokens, not hardcoded colours in components | `shell/theme/tokens.plm`; components read `bg.*`, `surface.*`, `fg.*`, `accent.*`, `status.*`, `focus.ring`, `selection.bg`; `tests/unit` checks all fourteen exist |
| The configuration and override model | `theme.source` (`fixed` \| `wallpaper`) and `theme.overrides` (token = colour) in `settings.json`, validated by `lib/config.luau` (enum and colour kinds, unit-tested); precedence: fixed → wallpaper → overrides, in `lib/theme.luau`, unit-tested |
| Wallpaper colours, from the verified Matugen workflow | Matugen 4.2.0, mooi's own config (`theme/matugen.toml.in`, `theme/palette.json.hbs`) so nothing of the user's theming is written; `bin/mooi theme-sync` runs it and mooi picks the palette up live (`files:palette.json`); `tests/theme.sh` compares the painted facts with the palette's own hex values, including a real run from the current wallpaper |
| Validation and recovery | Completeness and WCAG contrast checks per token pair (`lib/theme.luau`, unit-tested); a theme that fails is refused **whole** — `tests/theme.sh` checks the facts still hold the last good theme and the Spine's dot is lit; `theme_error` is shown with a reason in the log |
| Wallpaper updates never reset user settings, or anything else | `tests/theme.sh`: `settings.json` byte-identical across every palette change, and `ws_max`, `show_clock`, `previews` and `phase` unchanged — colour facts are the only thing a palette writes |
| Not in this slice | light scheme, named theme packages, a Workshop editor for it (the wallpaper hook is mooi's own `bin/mooi theme-watch`, D18) |

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
| Motion tokens exist and hold | scene.sh measures the islands' nine transitions on every run (1 %→99 % of travel, against the token's own `~`); the numbers of the last full run are in STATUS.md, and nothing here repeats them, so a document cannot go stale on its own. The bar's own three (`m.confirm`, `m.spin`, `m.turn`) are not in that set — the chain moves only on a real workspace change, which the suite promises not to make, so the chain's spin and the module turn were measured by hand (STATUS.md). `m.dial` is gone with the dial itself (D17); `m.chain` and `m.roll` with the geared pair (D19) |
| Keyboard focus and dismissal | only the open island holds the keyboard; Esc order: confirmation → expanded → island (scene.sh) |
| Reduced motion | scene.sh: 0 frames between open and closed |
| Rapid and repeated interactions validated | scene.sh; integration.sh: 11 volume requests in a burst end on the last |
| Real system state, shown as reported | integration.sh: wpctl / brightnessctl / hyprctl agree with what mooi shows |
| Degrades without Hyprland IPC | degraded.sh |
| Frame timing | `pleamar --report`: "smooth · 60 fps against 60 Hz", 4 of 672 frames late (0.6 %), none over 2.5 periods. The late ones are paint 7 ms + waiting for the screen, not rules (0.03 ms) |
| Idle cost | Phase 2: 0.2 % CPU (no island) · 0.4 % (island open) · 24 MB PSS. With the Ferrolume bar (2026-10-20, resources reader on, no island): 1.1 % CPU over 10 s · 67 MB PSS |
| Supervision | keeper restarts a killed scene (tested); `bin/mooi stop` leaves no keeper or marker |

## Manual checks

1. Super+Alt+Space: mooi appears beside ArchEclipse with the command membrane open. Type an app's name and press ↵: it starts, and next time it ranks higher. Super+Alt+W: the window island opens under the bar's left end.
2. Click the System prism in the bar's row (the one carrying the battery): the system island reaches up from the bottom-left corner, and the window island leaves.
3. Drag the volume level and scroll over it; ↑↓ choose the row, ←→ adjust, `m` mutes.
4. Move a window to another workspace from the window island: the bar pulses that workspace's block.
4b. `bin/mooi atlas` (or the Atlas prism in the bar's row): every window is there as a preview; ←→↑↓ move, ↵ focuses that window and the Atlas closes, Esc dismisses. Press `m`: the strip appears and the board makes room for it; ←→ (or a click) chooses a workspace, ↵ moves that window there — stay where you are and watch that workspace's block pulse, and the Atlas should stay open — and Esc leaves the strip. Press `p`: the pictures go and come back, and the choice is remembered after a restart. Type in the membrane while it is open: it should type, and Esc should close it (both failed before the keyboard fix, AUDIT.md §4).
5. `bin/mooi theme-sync` (optionally with an image), then set `theme.source` to `wallpaper` in `~/.local/share/pleamar/mooi/settings.json`: mooi recolours itself from the wallpaper within a frame, and back with `fixed`. Add an override (`"overrides": { "accent.primary": "#FF00FF" }`) and it wins; point the palette at something unreadable and the bar's end cap shows the dot instead, keeping what it had.
6. Super+Alt+Shift+Space: mooi goes; ArchEclipse is untouched.

## Not tested yet

Launching an app from the membrane (manual check 1: tests never start real apps); takeover end to end (blocked, see SWITCHING.md); multi-monitor with real hardware (the LG is not connected — see the live checks below for what a virtual output covered); fullscreen apps over the bar; a screen narrower than the machine's 1152 px (the bar runs past the right edge rather than giving something up); the Signal Loom live (a notice arriving, a time-out, snooze/shelve, the Field's keys — `lib/signals` is unit-tested, the scene only compiled); settings changed mid-animation; input-to-visible latency; and a long-session memory trend. In the Atlas, a window moving between workspaces while the move strip is open is not covered, and neither is a move onto the workspace the window already occupies.

## Screens, checked live (2026-10-21)

Not a script — it reconfigures the running session, so it is done by hand (restore afterwards):

| Check | What was done | Result |
| --- | --- | --- |
| scale ≠ 1 | `hyprctl eval` set `eDP-1` to 1.25, then 1.5, then back to 1 | the bar relaid out each time: `bar_x1` 1914 → 1530 (1920/1.25 − 12 + 6) → 1274 (1920/1.5) → 1914; mooi stayed up and answering |
| hotplug | `hyprctl output create headless`, then that output set to 1280×720, then `hyprctl output remove` | no crash; the narrowest monitor won (`bar_x1` 1274 while it was the narrowest, back to 1914 after) |
| a bar on the second screen | `grim -o HEADLESS-N` while it was up | the bar was drawn there — 306 lit columns across the top strip of the 1280×720 capture |

Still open: two real panels side by side, per-screen arrangement (one layout serves all, the narrowest), and behaviour when a monitor is unplugged while an island is open.

`tests/integration.sh` drives real keys through `wtype` (the compositor's virtual keyboard) because the `--say` channel injects keys straight into the scene and would never have caught the keyboard problems it now guards (AUDIT.md §4); it is skipped, saying so, where `wtype` is missing.
