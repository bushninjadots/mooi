# Contributing

mooi is a Hyprland desktop shell written for Pleamar 0.7.11 (language 0.9). Read
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first; [docs/TESTING.md](docs/TESTING.md) lists every
suite.

## Before you send a change

```sh
bin/mooi check
```

That runs `tests/gate.sh` (syntax, shellcheck when installed, Lua parsing, the unit/BMO suites and
the sandboxed suites), compiles every `shell/**/*.plm`, and checks that `docs/TESTING.md` names every
test script and no missing one. CI runs the same gate with `sh tests/gate.sh --no-pleamar`; the
scene compile needs Pleamar and a compositor.

Live suites (`scene`, `integration`, `media`, `theme`, `nexus`, `notes`, `pointer`, `board`,
`feed`, `surfaces`) change the session and are documented as such. Stop mooi first; the scripts
refuse to run beside it.

## Settings

- The schema in `shell/lib/config.luau` is the single source of truth. Add a setting there, add its
  setter in `shell/lib/setters.luau`, then add the row in `tools/gen-settings.py` and run it.
- Settings are written through `lib/settingsfile.luau` (read, merge only the leaves you changed,
  write). Never write `settings.json` whole from a scene.
- A failed save must be visible to the user, not discarded.

## Generated files

`tools/gen-settings.py` writes `shell/mooi-settings.plm`, `shell/lib/settings_index.luau` and the
edit-mode block in `shell/mooi.plm`; `tools/gen-frame.py` writes the frame blocks. Edit the
generator, never the block, and commit the generator and its output together. CI fails when
regenerating changes the tree.

## House style

Match the surrounding code: comments explain *why*, not what; no new runtime dependency without a
fallback; commands run argv-only; per-scene permission allowlists stay narrow. A change that touches
the lock screen, the keeper or `bin/mooi` should say what was tested live and what was only
compiled.
