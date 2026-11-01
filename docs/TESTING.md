# Testing

All commands run from the repo root. Stop any running mooi first (`bin/mooi stop`); the scripts refuse to start beside one.

| Command | What | Touches the session? | Last result (Pleamar 0.4.6) |
| --- | --- | --- | --- |
| `bin/mooi check` | compiles every scene; parses every logic file (`shell/*.luau`, `shell/lib/*.luau`) with Lua 5.4, since `pleamar --check` does not read the logic; `sh -n` over the launcher and `tests/*.sh`, and `shellcheck -S error` over both when shellcheck is installed; runs the BMO and unit suites **with their exit statuses checked** (a failing suite fails the command); names the optional tools this machine lacks and the pleamar/language it is running on | no | 285 tests, 0 failed (2026-11-01) |
| `tests/scene.sh` | the real scene against the bar that runs today (Ferrolume, the island kit, the deck): the bar's extent, thickness and edge distance; the workspace instrument — its blocks a contiguous run, exactly one active, centred on its own focus slot read from `describe`, inside the bar, and the pressable window agreeing with the clip; the window and system islands (selection, confirmation, expand/collapse, dismissal); slot hand-over; interruption bursts; the Overview (slots, tiles, leaving whole); the command membrane (search, satellites, empty state, reopen); 7 transitions via `--record` with a generous bound rather than the token's exact time; reduced motion | shows mooi for ~40 s; an island holds the keyboard while open; no window actions, results opened, workspace switches, volume or brightness changes | 60 state checks + 7 motion checks, 0 failed (2026-11-01) |
| `tests/integration.sh` | every window action on throwaway `kitty --class mooi-probe` windows, the Overview opening and closing, membrane results/satellites, **the compositor's own keyboard (`wtype`: typing into the field, Escape, the Overview)**, and system controls | **yes**: focuses windows/workspaces, moves one window and briefly changes volume, mute and brightness; all restored | 56 checks, 0 failed |
| `tests/degraded.sh` | mooi with Hyprland's IPC unreachable | shows mooi | 8 checks, 0 failed (2026-11-01) |
| `tests/config-recovery.sh` | good, broken and partly-wrong `settings.json`, a choice made on the bar (workspace labels) being written down and read back, and safe mode | backs up and restores the real settings | 13 checks, 0 failed (2026-11-01; its old `spine.clock` files now exercise the migration) |
| `tests/apps-sync.sh` | your apps in mooi's palette, in a throwaway XDG tree: `bin/mooi apps-sync` renders Kitty, GTK and Qt with the switches on, puts every file back with them off (Kitty's include, both `gtk.css` files and Matugen's outputs, Qt's scheme paths and `custom_palette`), removes a `gtk.css` mooi created where there was none, removes one whose Matugen output had no saved copy to restore, and covers the edges: a Kitty include with trailing whitespace, a lost `apps.state`, and a `custom_palette` the file never had; a Matugen `output_path` written with spaces, a trailing comment and an absolute path is put back verbatim | no (sandboxed `HOME`/`XDG_*`, `pkill` stubbed) | 41 checks, 0 failed (2026-11-01) |
| `tests/media.sh` | the media transport against a real player: starts its own VLC (two tagged files), checks the bar reads the player the system reports, then play/pause, next and previous — each twice, what mooi shows and what `playerctl` says | shows mooi; starts and stops VLC | 11 checks, 0 failed (2026-10-21) |
| `tests/pointer.sh` | a real pointer press on the bar: Pleamar's fake pointer is moved onto a system module (its x/width read from the scene's own layout) and pressed; the press opens the island that module promises — the system island for volume, brightness, network and Bluetooth, the **power** island for the battery (its session menu) — the pointer reached the scene, and Escape closes it | shows mooi | 3 checks, 0 failed (2026-11-01) |
| `tests/notes.sh` | quick notes live: the pad opens, a note written through the input's text/Enter path is saved to `notes.json`, an empty one is refused, a press copies to the clipboard, × forgets and Undo restores, a note is changed in place (Save, then Escape cancelling an edit), the wheel pages seven notes, `mooi note` saves from the terminal, the draft clears on close, notes survive a restart, and (where the module is placed) a real pointer press opens it | shows mooi; writes and restores `notes.json` | 36 checks, 0 failed (2026-11-01) |
| `tests/theme.sh` | the colour pipeline live: the fixed palette, a staged wallpaper palette, an override, a wallpaper with unreadable text **lifted** (D24 §5), a theme an override makes unreadable refused whole, and a **real Matugen run** from the wallpaper on screen (`bin/mooi theme-sync`); then that a palette change touches colour facts only | shows mooi; runs Matugen | 31 checks, 0 failed (2026-10-20) |
| `tests/board.sh` | the Kanban board as a program of its own (D64): the bar starts it and closes it again, the board reads mooi's own `board.json` through the link `bin/mooi` makes, a press on the board leaves it up, and a press outside it — or Escape — takes it away, after which the program ends by itself | shows mooi for ~30 s; writes only in a temporary home | 12 checks, 0 failed (2026-11-01) |
| `tests/nexus.sh` | Control Nexus against the real session: every view and edge followed from `settings.json` while open, the module layouts, the app mixer, Bluetooth rows, the SPACES grid, battery health, the identity import, and the deck's cards | shows mooi; reads and restores `settings.json` | 66 checks, 0 failed (2026-10-31) |
| `tests/wallpaper.sh` | Lumen, the wallpaper studio, live: the source wall and folder walk, the twelve sliders and nine vibes, the backdrop's matte and edge colours, keying the picture's background out, the palette swatches, undo/redo, the picker's folders, and APPLY rendering a still at the screen's size | shows mooi; writes and restores a wallpaper | 58 checks, 0 failed (2026-10-23) |
| `tests/feed.sh` | the shared music feed (D112): the bar's single cava writes `viz-levels.txt` and the notch, the player and the Nexus fold its bands into their rims; a repeated or older `seq` is refused, and two seconds without a line settle every rim | shows mooi; runs cava | 11 checks, 0 failed (2026-11-01) |
| `tests/surfaces.sh [scale]` | every panel read from Pleamar's own region dump (`PLEAMAR_REGIONS=1`), which is what the compositor gets: the press-away plate reaches the pop-up surface's foot, each panel's rows sit on that surface under the strip and inside it, the strip's 160 px surface carries nothing below the strip; the frame, the shutter and the stash dock measure their own surfaces, and a shelf panel stays inside the pop-up surface. Runs at the session's scale, or at the one named (`tests/surfaces.sh 1.5`, put back afterwards) | shows mooi for ~20 s; changes the monitor's scale and restores it | 19 checks, 0 failed (2026-11-01, at scale 1, 1.5 and 0.25 — 1080, 720 and 4320 px tall surfaces) |

Run again on 2026-11-01, with mooi stopped and started afterwards: scene **60 + 7**,
config-recovery **13**, degraded **8**, board **12**, notes **36**, pointer **3**, feed **11**,
apps-sync **41** — **191 checks, 0 failed**. Two of those were red before they were fixed, and
both were the suites' own faults, not the shell's. `degraded.sh`'s readiness loop asked
`say "get open"` through `get`, which pipes through `tail`, so the pipeline answered with
`tail`'s status and a scene that never came up counted as ready — it now asks the scene
directly. `pointer.sh` assumed every system readout opens the system island, but the
battery module opens the **power** island by design (`on press zbat … open = power`); it
clicked `battery` and called the truthful answer wrong — the expectation now follows the
module it pressed. Not re-run: `integration.sh`, `media.sh`, `theme.sh`, `wallpaper.sh` and
`nexus.sh`, which write to the session, start a player, recolour the desk or rewrite the
wallpaper; their rows still carry the dates of their last runs.

`.github/workflows/check.yml` runs the parts of the gate that need no Pleamar on every push and pull request: `sh -n` and `shellcheck -S error` over the launcher and every test script, the Lua 5.4 parse of every logic file, and both unit suites. It cannot compile the scenes — that needs the pleamar binary — and says so rather than passing without it. It ran **green** on 2026-11-01 (run 41300875532) after two fixes it found: the workflow's own YAML (a step name carrying `: `) and **SC1087** in `bin/mooi` — `$was_re[[:space:]]` read as an array index, now `${was_re}`.

## Overview port live check (2026-10-31)

With `atlas.engine = mooi` and the shell refreshed from the repo (`bin/mooi refresh`):

### Mission shape (D114, `atlas.overview = mission`)

- Super+Tab (a real `wtype -M logo -P Tab -p Tab -m logo`) opened it: `get open` read `overview`, and the facts agreed with the geometry — `ov_mission = true`, `ov_W = 1920`, `ov_H = 1080`, `ov_mission_search_y = 69`, `ov_awx = 220`, `ov_awy = 231`, `ov_aww = 1480`, `ov_awh = 805`, `ov_mission_gap = 18`, `ov_mission_pad = 28`, `ov_mission_head = 52`.
- The screen (screenshot) showed the blurred wallpaper, the centred search row, the workspace chips in the strip, and one large rounded card holding the active workspace's real window thumbnails with `app · title` bars — not the old grid/canvas.
- `emit ov_step 1` (Pleamar's event syntax is `emit name value`, not `emit name(value)`) moved to workspace 2 (`hyprctl activeworkspace` read `2`) with the Overview still open and the large card following it (`ov_act = 1`). The workspaces watch rebuilds the board while the Overview is up.
- `text ov_q cleaned_leads` gave `1 RESULT · ENTER USES IT`; Escape cleared the search and a second Escape closed the Overview.
- The older feature checks still hold in Mission: `btop` gives six application rows, and `2+3*4` gives `= 14`.

### Feature pass (D113, any shape)

- `bin/mooi overview` opened the Pleamar Overview; a second call closed it (`pleamar --say mooi 'get open'` read `overview`, then `none`).
- With the Overview open, `text ov_q 2+3*4` gave one row, `= 14`, `RESULT · ENTER COPIES`; `btop` (no board match) gave six application rows; `cleaned_leads` gave `cleaned_leads.xlsx`, `FILE · ~/Downloads/cleaned_leads.xlsx`.
- Escape cleared the search, and a second Escape closed the Overview.

Not exercised: the Mission shape on a second monitor, a hand resting in a hot corner, Enter on a row (it would launch or open something), dropping a window past the strip in Mission, and the Hyprdrive side of the switch (its plugin is not loaded on this machine).

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
| Every tile is a window Hyprland lists, and can be focused | `scene.sh`: `atlas_tiles.count` equals Hyprland's visible windows and tile 0 carries Hyprland's own address; `integration.sh` (live) and a manual run: a window chosen in the Overview focuses it and the Overview closes |
| Thumbnails: the compositor's pictures, asked for only while the Overview is up | `thumbnails.capturing` is true here; `scene.sh` checks the first tile has a picture; `thumbnails.want()` on close |

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
| Idle cost | Phase 2: 0.2 % CPU (no island) · 0.4 % (island open) · 24 MB PSS. With the Ferrolume bar (2026-10-20, resources reader on, no island): 1.1 % CPU over 10 s · 67 MB PSS. **2026-10-31, the whole shell running** (bar + notch; 20 s from `/proc/<pid>/stat`, PSS from `smaps_rollup`): **2.35 % of a core** (bar 2.10 %, notch 0.25 %) · **360 MB PSS** (bar 286 MB, notch 81 MB). One sample; it does not separate visualiser work from idle when something is playing |
| Supervision | keeper restarts a killed scene (tested); `bin/mooi stop` leaves no keeper or marker |

## Manual checks

1. Super+Alt+Space: mooi appears beside ArchEclipse with the command membrane open. Type an app's name and press ↵: it starts, and next time it ranks higher. Super+Alt+W: the window island opens under the bar's left end.
2. Click the System prism in the bar's row (the one carrying the battery): the system island reaches up from the bottom-left corner, and the window island leaves.
3. Drag the volume level and scroll over it; ↑↓ choose the row, ←→ adjust, `m` mutes.
4. Move a window to another workspace from the window island: the bar pulses that workspace's block.
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
