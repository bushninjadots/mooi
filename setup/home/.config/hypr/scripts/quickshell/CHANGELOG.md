# Changelog

All notable changes to the equisdots shell are documented here.
Dates use YYYY-MM-DD.

## [2026-10-16]

### Added
- **Bar master switch** (`bar.enabled`): the Bar group's new **General** page toggles the whole bar live — off unmaps every bar window (no UI, no reserved edge) and preserves the layout for the way back on.
- **Complete plugin bars** (`provides.bar.provider`): a plugin can ship a whole bar; `ui/PluginHosts.qml` mounts it exactly like a host adapter (injected `host` handle, `surfaces`/`frameObstacle` contracts) with the plugin's master switch and its own settings page as its menu. POC fixture: `plugins/hello-bar` in `equisdots/plugins`.
- **Id-integrity warnings in the Plugins manager**: a card whose plugin shadows another copy (the scan's `shadowed` list) or lives in a folder that does not match its manifest id (`dirMismatch`) shows a short warning note — duplicates are never silent.

### Changed
- **Bar group pages**: Engine → **General** (`d_engine` → `d_general`), now hosting the master switch, a live overview and the popup-position grid.
- `barEngine` and `classicbar` are no longer read: leftover keys in user files are ignored, never rewritten.

### Removed
- **Classic bar engine**: `ui/bar/ClassicBar.qml`, the Classic Bar editor page, `PosCardClassic`, `ClassicSectionCard`, the `classic*` helpers in `BarLayout.js` and the classic branches in `Bar.qml`/`BarEditor.qml`.

### Fixed
- **Empty-file trap in the plugin settings writes** (Plugins manager + Plugins panel): the jq guards now seed with `[ -s ]` (exists *and* non-empty) instead of `[ -f ]` — `jq` on an empty file exits 0 with no output, so a truncated `settings.json` could never repair itself through the old seed.

### Documentation
- `docs/bar.md` rewritten for the single bar + plugin bars; `docs/personalization.md` updated.

## [2026-10-15]

### Changed
- **Screenshots overlay left the shell**: `ScreenshotOverlay.qml` now ships with the `screenshots` plugin (deployed to `ui/plugins/screenshots/ui/`); the recording bar module resolves the plugin's script across deploy layouts (managed registry/tree, user plugin, transitional core path).
- **Timex and RSS Reader moved to plugins**: `ui/Main.qml` resolves plugin-provided panels (`manifest provides.panels`) and the General position grid lists them dynamically; the `timex` plugin ships the calendar/weather popup + its settings page, the `rss-reader` plugin a rebuilt reader panel + its own feed manager page. `SUPER+S`/`SUPER+O` come from the plugins' `hypr.lua`.
- **Clipboard, QuickNotes and File Search moved to plugins**: same panel mechanism + their own settings pages; `SUPER+C`, `SUPER+Y` and `SUPER+'` come from each plugin's `hypr.lua`.
- **Bar modules can be plugin-provided**: `provides.bar.modules.<id>` lets a plugin supply a module implementation for a core slot; the recording indicator is now `screenshots`' `bar/Recording.qml` and the shell keeps no recording state (`bar.isRecording` and the core poller were removed).
- **Weather and Resources islands moved to their plugins**: the weather bar module now ships with `timex` (self-polling the engine; the `weather.sh` shim and the bar's weather poller are gone) and the CPU/RAM island ships with `sysmon` (reads the core `SysData`); the sysmon plugin installs by default and its floating monitor becomes opt-in via a new `sysmon.panelEnabled` toggle.

### Removed
- `ScreenshotOverlay.qml` (the plugin owns it; `dots` installs the plugin by default).
- `ui/timex/` (popup + settings tab) and `ui/panels/rss-reader/` (panel + fetcher + feeds) — both ship with their plugins now.
- `ui/panels/clipboard/`, `ui/panels/quicknotes/`, `ui/panels/file-search/` and `ui/bar/modules/RecordingModule.qml` — the plugins ship them now.

## [2026-10-02]

### Added
- **Wallpaper picker: interactive scenes** (`ui/panels/davincix/`): `scn_<name>.jpg` thumbnails are listed like any wallpaper, marked with a `JS` badge and applied through the davincix kernel. `getCleanName()` resolves the `scn_` and `000_` prefixes and the flattened `__` paths used by nested media.
- **New transition set**: the filter-bar transition selector offers the reveal effects (`pixelate`, `ripple`, `blinds`, `spiral`, `static`, `parallax`, `parallax-left`, `parallax-right`, `parallax-invert`, `melt`, `shatter`) alongside the existing ones.
- **Palette widget** (`ui/panels/palette/PaletteWidget.qml`, `SUPER + SHIFT + P`): standalone palette switcher with the same X / Custom / User sections, filter and cards as the editor's Palette page. Selecting a palette applies it live (same `Config.setSetting` write) and closes the widget; its anchor is configurable through `settings.widgets.palette.position`. Also listed in the mascot dock.

### Changed
- Wallpaper deletion supports scene directories and flattened nested paths.

### Documentation
- `docs/davincix-scenes.md` documents the picker integration (entry naming, badge, apply and delete flows).

### Fixed
- **Palette widget previews**: the second swatch row used `model: [2, 3]` with `colors[index]`, so every card repainted `color0`/`color1` on the bottom row; it now uses `model: [0, 1]` with `colors[2 + index]`, matching the editor's cards and the real palette files.

## [2026-09-28]

### Added
- **Effects kernel** (`core/scripts/hypr-effects.sh` + `core/HyprEffects.qml`): shared reader/writer for the window-effect knobs used by the Hyprland tab and the Window Controls widget. Partial updates, JSON state as source of truth and live apply through `hyprctl eval`; the Lua overrides are only written on demand (close/Save).
- **Theme > Shadows page**: host-drawn popup/menu shadows with `RectangularShadow` (position, size, morph and fade aware), configured from `settings.json -> shadows` and applied live. Panels may expose `shadowRadius` to match their own corners (the app launcher does).
- **Theme > Glass page**: translucent backgrounds plus compositor backdrop blur for popups, menus and the bar through Hyprland layer rules (`hyprland/config/layers.lua`). `settings.json -> glass` drives the background alpha; cards stay opaque so text remains legible.
- **Palette sections**: the Palette page is grouped under centered `X`, `Custom` and `User` titles, with a shared palette card component. Community palettes live in a subfolder and are resolved through `index.json` (`category` + optional `path`).
- **Window border gradients**: optional two-stop gradient per border (second color + angle) in Style and Hyprland, built on a shared `WindowBordersSection` component; the compositor adapter receives border specs instead of plain hex values.
- **Bar shadows**: island capsules and the optional strip draw their own shadows from the same `shadows` config, with surface padding and an input mask so the padding does not capture clicks.
- **Theme > Mascots > Species and Count**: the island can show 1, 2 or 3 mascots (`settings.json -> mascots.count`; the island width adapts to the number) and each one can be `flame` (default little fire, replaces the old unrecognizable chibi blob), `cat`, `dog`, `eyes` (just a pair of manga eyes with a big tracking iris, angry lash, sleepy lids and happy arcs) or `mixed` (cat / dog / eyes). Faces are drawn with `QtQuick.Shapes`: pointy ears with inner ear, forehead stripes, whiskers and pink nose for cats; floppy ears, eye patch, muzzle and tongue-when-happy for dogs. Every mood (angry, surprised, happy, sleepy) shows on the face: ears, eyelids, brows and mouth.
- **Mascots > Position**: the island can be anchored to any of the nine screen positions (`settings.json -> mascots.position`, 3x3 pad in Theme > Mascots); the click dock always unfolds from the island toward the screen centre (upwards when the island sits at the bottom).
- **Theme > Mascots > Dots**: new species made of a cluster of colored dots that trail the cursor inside the island (no face); the reach widens when surprised, droops when sleepy, bounces when happy and jitters when angry.
- **Mascots island dock**: clicking the island unfolds `ui/mascots/MascotDock.qml`, a rectangular panel with small widget miniatures (3 per page, chevron paging and page dots). Picking a miniature launches that widget through `qs_manager.sh open <id>`; paging slides the strip horizontally (OutCubic). Hovering the island surprises the mascots; only the island and the open dock capture input, the rest of the surface stays click-through.
- **Mascots module**: the overlay now lives in a self-contained `ui/mascots/` module (overlay + one file per species + shared face + dock + vendored metrics) with the palette, settings path and widget hooks injected; `ui/Mascots.qml` is a thin shell wrapper, ready to extract to its own repo.

### Changed
- Effect knobs no longer trigger a configuration reload while dragging: changes preview live, and the Lua overrides are persisted once when the UI closes or Save is pressed.
- Bar thickness now sets the cross-size in both orientations (the vertical floor was removed); the Style stepper lower bound is 24.
- The Hyprland tab description reflects the live apply path (no reload).

### Fixed
- BarEditor and WidgetRedactor first open: `uiScale` is taken synchronously from `Config`, avoiding the wrong first layout that displaced the nav pill and morphed the panel.
- Glass: color parsing no longer mistakes the alpha prefix of `#aarrggbb` for red (all surfaces turned reddish).
- Mascots: the pupils now track the cursor proportionally to the eye size (the old offset was a fixed 2.4 px, barely visible at large sizes and disproportionate at the small ones) and the look direction is smoothed per frame.
- Mascots: the look direction compared screen-space cursor coordinates with window-local mascot coordinates, so the eyes only tracked the right half of the screen; the surface origin is now part of the math (also for the widget-occlusion rect).
- Mascots: `idleTimer` / `moodTimer` were referenced as root properties (`overlay.idleTimer`), which is not how QML ids resolve, so the idle-sleep restart threw on hover and never ran from cursor movement.
- Settings menu (SUPER+SHIFT+D) did not open: a missing comma in the `BarEditor.qml` page map broke the whole component, so switching to it left the previous widget's frame on screen.
- Calendar was unreachable: its `WindowRegistry.js` entry was on the same line as a `//` comment and got swallowed, so `getLayout("calendar")` returned null. `scripts/check.sh` now runs a semantic smoke test over the widget registry, since `node --check` cannot see this class of bug.
- Mascots dock/page icons: 5-digit font codepoints were written as `\uXXXX` escapes, which QML parses as 4 hex digits plus a leftover character; the glyphs are now literal characters. The Timex card uses a clock, the pager uses plain chevrons and the Davincix card shows a live thumbnail of the current wallpaper (`current_wallpaper.png`) with the image glyph as fallback.
