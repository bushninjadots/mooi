# shell

Quickshell shell for the [equisdots](https://github.com/equisdots) desktop,
built up port by port from xlinux (the stable base).

Version: **0.1.0** · License: MIT

## State

The xlinux shell was ported as-is (behaviour preserved, naming updated) and
restructured into `core/` + `ui/`; it is the shell running live at
`~/.config/hypr/scripts/quickshell`. Renames applied: `dock` to `bar`, the
legacy bar to `ClassicBar` (since removed — the bar is a single zones engine
under the config key `"bar"`; `bar.enabled` is its master switch).

Running subsystems:

- **Bar** — host + zones engine + 18 modules + editor; complete bars can ship as plugins (`provides.bar.provider`).
- **Popups** — applauncher, battery, calendar, guide, music, network,
  system-monitor, updater, volume.
- **Shadows** — host-drawn popup/menu shadows plus bar island/strip
  shadows (`ui/Main.qml`, `ui/bar/Zone.qml`, `ShadowsPage.qml`;
  `settings.json → shadows`, applies live).
- **Glass** — translucent shell backgrounds + compositor backdrop blur
  (`settings.json → glass`, hyprland `layers.lua`; Theme → Glass page).
- **Plugin hosts** — plugins may ship a host adapter (manifest `host` entry)
  that the shell mounts generically (`ui/PluginHosts.qml`); hosts can also
  publish `frameObstacle` rects for the screen frame. Nyx (equisdots/nyx) is
  the first: a click-through island/notch that morphs into a dock, with its
  own settings page under Plugins.
- **Plugins** — installed-plugin registry and manager: folder discovery
  (`~/.config/hypr/plugins` + `plugins-user`), enable/disable and a Configure
  shortcut per plugin (`ui/bar/editor/PluginsPage.qml`; standard, samples and
  contracts in equisdots/plugins → `docs/plugins.md`).
- **Frame** — a bezel hugging all four screen edges, drawn on the Bottom layer
  and reserving space so tiled windows never cross it; it hugs the bar, host
  overlays and edge-anchored widgets (launcher/panels) with rounded corners
  and morphs live with them (`ui/frame/Frame.qml`, `core/FrameGeometry.js`,
  `core/FrameBus.qml`; `settings.json → frame`; Theme → Frame page).
- **Panels** — clipboard, davincix, file-search, focustime, idle,
  quickactions, quicknotes, rss-reader, scale, window-controls.
- **Lock**, **notifications** (server + history + popups) and the **floating
  widgets** (faces, redactor, loader).
- **Core** — Config, Caching, Scaler, WindowRegistry.js, Personalization.js,
  EditorNav.js, Theme/SysData/Cava/WidgetSync and the compositor adapter
  (`core/Compositor.qml` + `core/compositors/Hyprland.qml`).

Known pending:

- Compositor scope is Hyprland; the Niri backend in
  `equisdots/docs/compositor-api.md` is a plan item, not active work.
- The palette directory is frozen at `dock/palettes` (shared contract with
  `theme-sync`, `colors.lua` and `dots`).
- Some popup helpers (diary, schedule) have no script yet; schedule is
  optional (existence-guarded), diary is still a dead button.
- The `install/` layer does not exist yet.
- The plugin standard is POC-level (Nyx + the `hello` sample); the first
  converted plugins (screenshots, idle-lock, monitors) will land in
  equisdots/plugins.

## Layout

| Path | Content |
|---|---|
| `Shell.qml` | Entry point (mounts `Main`, `Bar`, `Floating`, `Widgets`) |
| `core/` | Services and contracts (no visuals) |
| `core/compositors/Hyprland.qml` | Hyprland backend of the compositor surface |
| `core/scripts/watchers/` | Data-fetcher scripts the bar polls |
| `ui/bar/` | Bar host, zones engine, modules, `Colors.qml`, `edit/` + `editor/`, `popups/` |
| `ui/panels/` | Standalone widgets (davincix, clipboard, focustime, ...) |
| `Lock.qml` (root) | PAM session lock (alternate entry point) |
| `ui/notifications/`, `ui/widgets/` | Notification layer, floating widgets |
| `ui/settings/tabs/` | Shared settings tabs (host API) |

## Local checks

No CI: run the checks locally before pushing.

```bash
scripts/check.sh
```

- `qmllint` over every `.qml` file (needs the Qt declarative tools). `ui/Main.qml`
  is in the script allowlist because of a qmllint limitation with the current
  Quickshell qmltypes; the shell loads it at runtime.
- `node --check` over the plain `.js` modules (the `.pragma library` directive
  is stripped first).

## Docs

- `docs/architecture.md` — layer map and contracts.
- `docs/bar.md` — bar host, master switch, zones, styles, plugin bars.
- `docs/bar-modules.md` — module contract, `ModulePill` API, compact mode,
  per-module personalization.
- `docs/windows.md` — windows, widget popups, IPC and watchers.
- the island/notch integration is documented in its plugin (equisdots/nyx → `docs/shell-integration.md`).
- `docs/desktop-widgets.md` — floating widget subsystem and redactor.
- `docs/themes.md` — palette system, live editing and theme-sync.
- `docs/personalization.md` — configuration surface (bar, modules,
  per-subsystem options).
- `docs/development.md` — local check scripts and development pitfalls.
