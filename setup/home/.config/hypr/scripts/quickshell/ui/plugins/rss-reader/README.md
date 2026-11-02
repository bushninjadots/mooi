# rss-reader — converted plugin

Feed reader panel (RSS/Atom) converted from the shell core into a
self-contained plugin under the standard in `docs/plugins.md`.

```
rss-reader/
  plugin.json              manifest (type: shell; provides.panels.rss-reader)
  hypr.lua                 SUPER+O toggles the panel (SDK: mod.bind)
  ui/
    RssReader.qml          the reader panel: search, per-feed filters,
                           colored cards, relative times, keyboard nav
    ReaderDefaults.js      default feeds + refresh presets (shared)
  scripts/
    fetch.py               curl + python fetcher (URLs as argv, JSON stdout)
  settings/
    ReaderPage.qml         the plugin's own settings page: feeds manager,
                           refresh, descriptions and panel position
  README.md
```

## Deploy contract (dots)

- The whole plugin lands at `ui/plugins/rss-reader/` (UI face); the panel is
  loaded by the shell's panel host through `provides.panels.rss-reader` — the
  core `WindowRegistry` no longer knows it.
- The runtime subset (`plugin.json`, `hypr.lua`, `scripts/`) goes to
  `~/.config/hypr/plugins/rss-reader/` (the loader evaluates `hypr.lua`).
- Installed by default (`DEFAULT_PLUGINS` in dots), so existing users keep
  the panel and the SUPER+O bind.

## Settings

`settings.json` → `"rss-reader"`: `feeds[]` (URLs), `refreshMs`,
`showDesc`; the panel position lives in `widgets."rss-reader".position`.
Everything is edited by the plugin's own page (`p_rss-reader`); on first run
the reader imports the legacy in-tree `feeds.txt` when present, else seeds
the bundled defaults.

## Dependencies

`python3` and `curl` (installed with the stack).
