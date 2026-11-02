# screenshots — converted plugin

Screenshots (area / full / edit via satty) and screen recording (virtual
audio routing, gpu-screen-recorder), converted from the `hyprland` core into a
self-contained plugin under the standard in `docs/plugins.md`.

```
screenshots/
  plugin.json              manifest (type: mixed; defaultEnabled: true)
  hypr.lua                 the four Print binds (SDK: mod.bind / mod.script)
  scripts/
    screenshot.sh          entry point (the four binds call it)
    caching.sh             vendored: QS cache/state dirs (qs_ensure_cache)
  ui/
    ScreenshotOverlay.qml  the area-selection / recording UI (standalone
                           quickshell instance launched by the script)
  README.md
```

## Deploy contract (dots, F1)

- The **whole repo** goes to the shell tree at
  `~/.config/hypr/scripts/quickshell/ui/plugins/screenshots/` (UI face: the
  overlay is a standalone `quickshell -p` entry; its imports target the shell
  tree). `screenshot.sh` resolves the overlay at the deployed path first, then
  the current shell copy, then its sibling `ui/` for dev/staging.
- The **runtime subset** also goes to `~/.config/hypr/plugins/screenshots/`:
  `plugin.json`, `hypr.lua`, `scripts/` (the loader evaluates `hypr.lua` there;
  `mod.script()` resolves the scripts).

## Dependencies

`gpu-screen-recorder`, `grim`, `satty`, `wl-clipboard`, `pactl` (PipeWire),
`quickshell`, `zbarimg` (QR), `python3`, `notify-send` (libnotify). The
hyprland installer already installs them.

## Status

Cut over: the feature no longer ships inside `hyprland` (`keybinds.lua`) or
`shell` (`ScreenshotOverlay.qml`); those copies are removed and `dots`
installs this plugin by default (`DEFAULT_PLUGINS`: deploy by convention; the
manifest's `defaultEnabled` keeps it on for existing users). The overlay is
declared as a `standalone` entry: `dots` generates a root-level launcher
(`plugin-screenshots-ScreenshotOverlay.qml`) so it runs with the shell tree
as the config root and imports the core kit; the script launches the launcher
and resolves its own copy across deploy layouts (managed registry copy,
managed UI tree, user plugin, transitional core path).

The recording bar indicator is plugin-provided too: the manifest declares
`provides.bar.modules.recording` (`bar/Recording.qml`) and the bar resolves
the implementation for the core `recording` slot — the shell keeps no
recording state (`bar.isRecording` and the core poller were removed). The
plugin's page (`p_screenshots`) covers enablement through the standard
manager; other changes vs. the original: notification titles lost their
emoji; `caching.sh` is vendored unchanged.

## Enable

```sh
# pre-cutover: install it by hand (user plugin) ...
cp -r . ~/.config/hypr/plugins-user/screenshots
# ... then enable it:
#   Settings -> Plugins -> "Screenshots & Recording" (or, once F1 lands:
#   dots plugins enable screenshots)
```
