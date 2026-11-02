# clipboard — converted plugin

Clipboard manager panel (cliphist) converted from the shell core into a
self-contained plugin under the standard in `docs/plugins.md`.

```
clipboard/
  plugin.json              manifest (type: shell; provides.panels.clipboard)
  hypr.lua                 SUPER+C toggles the panel (SDK: mod.bind)
  ui/
    ClipboardManager.qml   the panel: text/image history, preview, paging
  scripts/
    clip_fetcher.py        cliphist reader (paging + image cache, argv)
  settings/
    ClipboardPage.qml      items per page + panel position
  README.md
```

## Deploy contract (dots)

- The whole plugin lands at `ui/plugins/clipboard/` (UI face); the shell panel
  host loads it through `provides.panels.clipboard`.
- The runtime subset (`plugin.json`, `hypr.lua`, `scripts/`) goes to
  `~/.config/hypr/plugins/clipboard/`; the panel resolves the fetcher across
  deploy layouts (managed tree, user plugin, transitional core path).
- Installed by default (`DEFAULT_PLUGINS` in dots).

## Settings

`settings.json` → `"clipboard"`: `fetchLimit`; position in
`widgets."clipboard".position`. Edited by the plugin's own page
(`p_clipboard`).

## Dependencies

`cliphist`, `python3` (installed with the stack).
