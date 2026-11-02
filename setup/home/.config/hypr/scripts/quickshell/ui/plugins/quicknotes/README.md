# quicknotes — converted plugin

Scratch notepad panel converted from the shell core into a self-contained
plugin under the standard in `docs/plugins.md`.

```
quicknotes/
  plugin.json              manifest (type: shell; provides.panels.quicknotes)
  hypr.lua                 SUPER+Y toggles the panel (SDK: mod.bind)
  ui/
    QuickNotes.qml         the panel: editor with auto-save
  settings/
    QuickNotesPage.qml     auto-save delay + panel position
  README.md
```

## Deploy contract (dots)

- The whole plugin lands at `ui/plugins/quicknotes/`; the shell panel host
  loads it through `provides.panels.quicknotes`.
- The runtime subset (`plugin.json`, `hypr.lua`) goes to
  `~/.config/hypr/plugins/quicknotes/`.
- Installed by default (`DEFAULT_PLUGINS` in dots).

## Settings

`settings.json` → `"quicknotes"`: `saveDebounceMs`; position in
`widgets."quicknotes".position`. Edited by the plugin's own page
(`p_quicknotes`). Notes keep the classic path:
`~/.cache/quickshell/quicknotes.txt`.
