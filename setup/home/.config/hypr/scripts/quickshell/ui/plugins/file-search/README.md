# file-search — converted plugin

File search panel (fd/find) converted from the shell core into a
self-contained plugin under the standard in `docs/plugins.md`.

```
file-search/
  plugin.json              manifest (type: shell; provides.panels.file-search)
  hypr.lua                 SUPER+apostrophe toggles the panel (SDK: mod.bind)
  ui/
    FileSearch.qml         the panel: debounced query + results list
  scripts/
    fetch.sh               fd/find searcher (query arg, paths on stdout)
  settings/
    FileSearchPage.qml     query debounce + panel position
  README.md
```

## Deploy contract (dots)

- The whole plugin lands at `ui/plugins/file-search/`; the shell panel host
  loads it through `provides.panels.file-search`.
- The runtime subset (`plugin.json`, `hypr.lua`, `scripts/`) goes to
  `~/.config/hypr/plugins/file-search/`; the panel resolves the searcher
  across deploy layouts (managed tree, user plugin, transitional core path).
- Installed by default (`DEFAULT_PLUGINS` in dots).

## Settings

`settings.json` → `"file-search"`: `debounceMs`; position in
`widgets."file-search".position`. Edited by the plugin's own page
(`p_file-search`).

## Dependencies

`fd` preferred, `find` fallback (installed with the stack).
