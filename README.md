# Tidal Shell

A fluid, keyboard-first desktop shell for Hyprland, rendered with [Pleamar](https://github.com/k4ditano/pleamar).
It runs **beside** your existing setup: it changes nothing in your Hyprland config and starts only when you ask.

Status: Phase 1, the first vertical slice. See [STATUS.md](STATUS.md).

## Run it

```sh
bin/tidal check          # compile + unit tests
bin/tidal run            # foreground; Ctrl+C or `bin/tidal stop` to quit
bin/tidal open           # toggle the window island (bind this to a key)
bin/tidal run --safe     # ignore settings.json, use defaults
```

Needs `pleamar` (tested with 0.3.7, language 0.4), `hyprctl`, `jq` (launcher only) and `lua5.4` (tests).

## What is there

- **Spine**: a 48 px left rail with the focused window, workspaces (click to switch) and the time.
- **Window island**: opened from the Spine's top button or `bin/tidal open`. ←/→ select, Enter applies, Esc goes back or dismisses. Float, Fullscreen, Pin, Move to workspace, Close (asks twice). Every action is read back from Hyprland before it is reported as done.

## Settings

`~/.local/share/pleamar/tidal/settings.json`, created on first run, applied live:

```json
{
  "version": 1,
  "spine":  { "clock": true, "max_workspaces": 10 },
  "island": { "confirm_close": true, "follow_on_send": false },
  "motion": { "reduced": false }
}
```

A broken file never stops the shell. It falls back to the last good file and shows an orange dot on the Spine.

## Docs

[Audit](docs/AUDIT.md) · [Spec](docs/SPEC.md) · [Architecture](docs/ARCHITECTURE.md) · [Testing](docs/TESTING.md)
