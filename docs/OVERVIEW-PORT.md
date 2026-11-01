# The Overview port: Hyprdrive's mission control, in Pleamar

Date: 2026-10-31 · Target: `shell/mooi.plm` + `shell/mooi.luau` (mooi's own Overview), Settings → Overview
Source: Hyprdrive `hyprland-native` (mission-control overview + dock plugin for Hyprland), read at
its public README and configuration keys on 2026-10-31.

This is the specification for bringing the parts of Hyprdrive that belong to an **overview** into
mooi, in Pleamar, and for the switch that chooses between the ported overview and the plugin.
It is a living checklist: every row says what exists, what was ported, and what cannot live in a
shell process.

The **shape** of the Overview is a setting too (D114): **Mission** is Hyprdrive's own visual, and
**Grid**, **Strip** and **Canvas** are mooi's three older shapes, kept because they are still
useful and still tested. Mission is the default; the others are one choice away.

## Why a port

Hyprdrive is a C++ plugin loaded into the compositor. It is tied to a Hyprland ABI (its README
pins 0.56.2), it must be rebuilt after compositor upgrades, and it draws its own surfaces outside
mooi's theme. mooi's Overview already is a Pleamar scene: theme-aware, keyboard-owned, and
scriptable through `mooi overview`. Porting the overview behaviour removes the compositor coupling
and gives one look, one key map and one settings page.

The plugin is **not currently loaded** on this machine (`hyprctl plugin list` reports none), so the
existing `atlas.engine` switch is a dispatch point, not a feature. The port makes "Pleamar" a real,
complete overview engine.

## What is ported, and where it lives

| Hyprdrive overview feature | Status in mooi | Where |
| --- | --- | --- |
| Mission-control grid of every desktop's windows | **Had it** — the grid shape, with the active workspace's border | `lib/atlas.grid`, `mooi.plm` overview group |
| Hyprdrive's own look: a blurred wallpaper, a workspace strip, one big mission card | **Ported (D114)** — shape **Mission**: the wallpaper behind (`blur: 14`, `brightness: 0.55`, a 52 % veil), a strip of the workspaces you are not on, one large card for the active one with its windows on an 18 px grid | `lib/atlas.mission`, `ov_mission` in `mooi.plm`/`mooi.luau` |
| Real compositor window pictures | **Had it** — the `thumbnails` service (mooi never re-renders a window itself) | `mooi.luau` picture bursts, `atlas.previews` |
| Click a window to go there; X to close | **Had it** — press focuses, middle-click closes, action strip on the canvas | `atlas_window`, `ov_close`, `ov_wact` |
| Hover a tile to lift it | **Had it** — `hover` on each tile's zone | `otile.$i` |
| Search, calculate or run: one list while typing | **Ported (stage 2)** — windows, workspaces and groups first; when nothing on the board matches, a sum (`lib/calc`), installed apps, and files from your own folders (`lib/filesearch`). GNOME search providers are not ported (see below) | `lib/search`, `lib/atlas.search`, `lib/calc`, `lib/filesearch`, `ov_runs` |
| Workspace strip; drag a tile onto a cell | **Had it** — `atlas.overview = strip` | `lib/atlas.strip` |
| Drop on an empty strip cell to make a desktop | **Ported** — a window let go past the last cell makes the next desktop and moves there | `ov_drop_xy` |
| Push a window to the next desktop at the screen's edge | **Ported (D115)** — a carried window held in the left or right edge (28 px) for 420 ms steps to that desktop, and keeps stepping every 420 ms while it is held; the edge lights, a pill names the desktop, and let go away from the board the window goes to the one you stopped at | `atlas.edge`, `atlas.spring_target`, `ov_edging`, `step_desktop` |
| Push against an edge while dragging to pan the canvas | **Ported (D116)** — on the Canvas shape there is no next desktop, so the same band pans the camera toward the edge, up and down as well as sideways, at one speed on the screen whatever the zoom; a carried window or a workspace's nameplate drives it | `atlas.edge_y`, `atlas.pan_by`, `ov_edgey`, `canvas_pan_tick` |
| Hold to swap between windows | **Had it** — dropping a tiled window on a tiled one swaps (no hold needed) | `atlas.rearrange` |
| Scroll wheel / keyboard to step desktops | **Ported** — wheel over the grid (or ← →) walks the existing desktops and keeps the Overview open | `ov_step`, `atlas.step` |
| Several monitors act as one; Tab walks the grids | **Had it, differently** — one page per monitor with `ON <monitor>` and an outline for a workspace shown elsewhere; Tab walks the cells | `atlas.cell_monitors` |
| Trackpad swipe opens it; follows the fingers | **Had it, partly** — the swipe opens it (`atlas.gesture`, 3 or 4 fingers); it does not track the fingers mid-swipe (Pleamar gets a completed gesture, not its frames) | `lib/desktop.gestures` |
| Scroll a scrolling-layout desktop before stepping past it | **Not portable** — that is compositor layout state; the shell can only ask Hyprland to change desktop | — |
| Hot corner opens it | **Ported (stage 3)** — opt-in; a 6×6 surface in the chosen corner takes that corner's clicks and a configurable rest opens the Overview | `hot_tl`–`hot_br`, `hc_enter`/`hc_leave` |
| Tap Super (press and release) opens it | **Not portable** — the plugin sees the modifier's release inside the compositor | — |
| Dock: dash-to-dock, live previews, stacks, badges, autohide | **Out of scope for this port** — that is a separate dock program, not the overview. mooi's bar and Control Nexus already cover launching, focus and cycling | — |
| Mosaic layout | **Out of scope** — a compositor layout cannot be implemented by a layer-shell client | — |

## The Mission shape (D114)

Hyprdrive draws the overview as one large, rounded workspace card over a blurred and dimmed copy of
the wallpaper, with a strip of the other desktops above it and a search field across the top. The
Pleamar scene now draws the same picture, in its own theme, and the geometry is pure and unit-tested:

- **Backdrop:** `~/.cache/current_wallpaper` is drawn full-screen through a `group` with
  `blur: 14` and `brightness: 0.55`, under a 52 % black veil; without a readable wallpaper the
  ground is drawn instead, so the Overview never opens on nothing.
- **Strip:** one chip per workspace at `top + 78`, 96 px high, at most 176 wide, 12 px apart,
  centred; the chip for the active workspace is left out because that workspace is the big card.
  Each chip carries the workspace's label and its window count, and the other workspaces' window
  pictures are shrunk into it.
- **Active card:** `x = (w − aw) / 2`, `y = strip + 96 + 26`, `aw = max(w × 0.50, min(w × 0.84, 1480))`,
  `ah = max(180, h − y − 44)`; 18 px corner, a 52 px header with the workspace's name, a soft
  shadow, and an accent underline under the heading.
- **Windows:** the active workspace's windows are laid out on a mission grid inside the card, with
  28 px padding and 18 px gaps — one column for one window, two up to four, three beyond — and
  every window keeps its real compositor picture. A title bar along the foot of each tile says
  `app · title` when the tile is wide enough (130 px).
- **Search row:** centred above the strip, `min(w × 0.46, 640)` wide, in the same place the other
  shapes put theirs.

Everything the ported hands already did still works in Mission: a press focuses and closes, a drag
carries a window (dropping it on a chip moves it to that workspace), the wheel and ← → step the
desktops and leave the Overview open — with the big card following the desktop it lands on, because
the `workspaces` watcher rebuilds the board while the Overview is up — and the search row still
falls through to sums, apps and files.

## Settings

Settings → Overview:

| Setting | Meaning | Default |
| --- | --- | --- |
| `atlas.engine` | Which overview Super+Tab and the Overview key open: **Pleamar** (mooi's own) or **Hyprdrive** (the plugin, only while it is loaded; otherwise mooi's) | `mooi` |
| `atlas.overview` | The Pleamar Overview's shape: **Mission** (Hyprdrive's: wallpaper, strip, one big card), **Grid**, **Strip** or **Canvas** | `mission` |
| `atlas.wheel_desktops` | The wheel over the grid, and ← →, step to the next/previous desktop | on |
| `atlas.search_apps` | Applications matching the search appear under the row; Enter starts the selected one | on |
| `atlas.search_files` | Files in Desktop, Documents, Downloads, Pictures, Videos and Music matching the search; Enter opens the selected one | on |
| `atlas.hot_corner` | Rest the pointer in this corner to open the Overview; off, or one of the four | off |
| `atlas.hot_corner_delay` | How long the pointer must rest there (200–1500 ms) | 600 |
| `atlas.spring_edges` | Carry a window into an edge of the Overview and hold: the desktops step (and keep stepping), or on the canvas the view pans; the window lands where you stop | on |

Existing, unchanged: `atlas.super_tab`, `atlas.zoom`, `atlas.gesture`, `atlas.rows`,
`atlas.columns`, `atlas.size`, `atlas.dim`, `atlas.previews`, `atlas.refresh`, `atlas.private`.
**Shape** now groups the four layouts; Rows and Columns still apply to Grid, and the Canvas keeps
its own pan/zoom.

On a machine where Hyprdrive's plugin is not loaded (as on this one, where `hyprctl plugin list`
reports none), choosing **Hyprdrive** falls back to Pleamar: there is no visible change because the
plugin is what would draw. The settings row and the launcher agree on that fallback; `hyprctl plugin
list` is the check.

The switch is real in both directions:

- `bin/mooi overview` reads `.atlas.engine`. With `hyprdrive` and the plugin loaded it closes mooi's
  overview state and dispatches `hyprdrive:overview toggle all`; otherwise it emits
  `open_overview` for the Pleamar scene.
- The Pleamar scene closes Hyprdrive's overview before opening, so the two never stack.

## Interaction map (ported overview)

- **Open:** Super+Tab, `keys.overview`, the bar's Overview button, `mooi overview`, or the gesture.
- **Search:** type; windows/workspaces/groups light first. When nothing on the board matches and
  `atlas.search_apps` is on, matching applications are listed under the row. Enter starts the
  selected app; Ctrl+↑/Ctrl+↓ chooses one. Enter on a matched window focuses it; on a matched
  workspace it goes there.
- **Step desktops:** wheel over the grid, or ← → when the search row is empty. The Overview stays
  open on the new desktop's page — in Mission, the large card moves to the workspace it stepped to.- **Move windows:** drag a tile to a cell (the marked windows go along); in the strip, drop past the last cell to make a new desktop there; drop inside a workspace to place a floating window or swap two tiled ones. In Mission, dropping a tile on a strip chip moves it to that workspace.
- **Spring edges:** carry a window into the left or right edge of the screen and hold it there. The
  edge lights, a pill names the desktop, and after 420 ms the Overview steps to it; holding on keeps
  stepping every 420 ms. Let go off the board and the window goes to the desktop the hold reached
  (`atlas.spring_target`), not home. Leaving the edge or letting go cancels the rest. This is the
  wheel's own walk (`step_desktop`), so all three keep the Overview open on each desktop.
- **Spring edges on the canvas:** the same hold, in any of the four edges, pans the camera instead —
  1100 screen px a second toward the edge, divided by the zoom so the speed looks the same near or
  far, every 16 ms while it is held (`atlas.pan_by`, `canvas_pan_tick`). A window or a nameplate can
  be carried across the whole field this way and dropped on a territory that was off screen.
- **Escape** unwinds one layer at a time: menu → name field → search → marks → pick → Overview.

## What a shell cannot do (and why)

1. **Tap-Super.** The plugin observes a modifier press/release with no other key. A Wayland client
   sees neither modifier state nor the compositor's key history. The existing Super+Tab bind stays
   the open command.
2. **Finger-following swipe and magnetic detents.** Pleamar delivers completed gesture events, not
   per-frame finger positions; the existing open gesture is the honest equivalent.
3. **Scrolling-layout pass-through and Mosaic.** Both are compositor layout internals, not client
   state.
4. **GNOME search providers.** These need a provider D-Bus protocol and per-provider result
   shapes. Sums are ported safely instead: `lib/calc` is a small recursive-descent parser with no
   `load()`, no names and a size cap, so typing text can never run code.

## Phases

1. **Switch + ported hands — done:** `atlas.engine` labels and description; wheel/key desktop
   stepping; drop-to-create in the strip; type-to-run apps; settings, tests, generated window.
2. **Search parity — done:** safe arithmetic and bounded, literal file results beside installed
   apps, with one list under the row and `atlas.search_files` to turn files off.
3. **Corner surface — done:** four opt-in 6×6 corner surfaces, a rest delay, and no ripple (the
   Overview's own pull-back is the motion). The corner clicks it takes are the stated price.
4. **Dock decision — done:** no separate dock. The bar, Control Nexus and the type-to-run list
   already cover launch, focus and cycling; a dock would duplicate them and keep another surface
   on screen all the time.
5. **The visual port — done (D114):** the **Mission** shape draws Hyprdrive's picture itself — the
   blurred wallpaper, the workspace strip, and one large active card whose windows are laid out on
   a mission grid — with the geometry in `lib/atlas.mission`, a unit test, and the settings'
   **Shape** choice regenerated. Grid, Strip and Canvas remain; Mission is the default.
6. **Spring edges — done (D115):** Hyprdrive's `drag:spring_edges`, inside the Overview: a held
   window at the left or right edge steps the desktops and lands on the one the hold stopped at.
   `atlas.edge` / `atlas.spring_target` are pure and unit-tested; `atlas.spring_edges` is a setting
   (on) whose control is the last code, so no other setting moved.
7. **Canvas edges — done (D116):** the same hold on the Canvas shape pans the camera in all four
   directions (`atlas.edge_y`, `atlas.pan_by`), so Hyprdrive's "push against the screen's edge while
   dragging to pan the canvas" exists on the shape that is mooi's own field rather than a Mosaic
   layout. Mosaic itself remains out of scope (see above).

## Verification

- Pure logic (`atlas.step`, `atlas.edge`, `atlas.edge_y`, `atlas.spring_target`, `atlas.pan_by`,
  `atlas.mission`, app ranking through `lib/search`) has unit tests.
- `tools/gen-settings.py` regenerates the settings window; the controls appear on the Overview
  page (Shape now offers Grid, Strip, Canvas and Mission) and write their settings through
  `lib/setters`.
- `bin/mooi check` compiles the scene, parses the logic and runs the unit suite (**280 tests, 0 failed**).
- Live on 2026-10-31, with `atlas.engine = mooi` and `atlas.overview = mission` and the shell
  refreshed:
  - Super+Tab opened the Overview; the screen showed the blurred wallpaper, the centred search row,
    the workspace chips and one large rounded card (1920 × 1080: x 220→1700, y 231→1036) holding
    the active workspace's real window thumbnails with `app · title` bars.
  - `emit ov_step 1` moved to workspace 2 with the Overview still open, and the large card moved to
    it (`ov_act = 1`) — the workspaces watch rebuilds the board.
  - `cleaned_leads` produced its one `~/Downloads/cleaned_leads.xlsx` file row; Escape cleared the
    search first and closed the Overview second.
  - The earlier feature checks still hold: `btop` gives six application rows, and `2+3*4` gives
    `= 14`.
- Not exercised live: the Mission shape on a second monitor, a hand in a hot corner, Enter launching
  or opening a result, dropping a window past the strip in Mission, and the Hyprdrive side of the
  switch (its plugin is not loaded on this machine).
