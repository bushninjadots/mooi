# bar/popups — convention

Popups triggered by the bar modules live here, one folder per popup, named
after the widget id used by `qs_manager.sh`. Each folder holds the popup
component and any service/scripts it needs.

They remain shell widgets: they are registered in `core/WindowRegistry.js`
and also opened by keybinds. The bar only triggers them; this folder is the
identification convention, not an ownership statement.

## Port target

From xlinux, these popups are opened by bar modules and belong here:

| Folder | Triggered by |
|---|---|
| `applauncher/` | `SearchModule` (SUPER+D) |
| `battery/` | `BatteryModule` (SUPER+B) |
| `calendar/` | `CalendarModule` (SUPER+S) |
| `guide/` | `HelpModule` (SUPER+H) — ported |
| `music/` | `MediaModule` (SUPER+M) |
| `network/` | `WifiModule` / `BluetoothModule` (SUPER+N) |
| `system-monitor/` | `SysmonModule` |
| `updater/` | `UpdateModule` (SUPER+U) |
| `volume/` | `VolumeModule` (SUPER+V) |

## Not here

Widgets with keybinds but no bar module keep their own place under `panels/`
(or a future top-level folder):

- `wallpaper` (davincix) — already ported as `panels/davincix/`.
- `clipboard` (SUPER+C), `focustime` (SUPER+SHIFT+T), `quicknotes` (SUPER+Y).
- Settings-side UI (the bar editor, shared tabs) stays in `bar/editor/` and
  `settings/`.
