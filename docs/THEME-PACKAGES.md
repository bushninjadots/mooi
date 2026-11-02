# Theme packages

_Status: pure package model and validation are implemented; no package browser or visual editor._

Theme packages let a user preserve and share a coherent visual configuration without exporting unrelated personal settings.

## Package boundary

The format is JSON and versioned:

```json
{
  "format": "mooi-theme",
  "version": 1,
  "name": "Foundry",
  "description": "Graphite surfaces and phosphor accents",
  "settings": {
    "theme": {
      "mode": "dark",
      "source": "wallpaper",
      "finish": "matte",
      "saturation": -8,
      "overrides": {
        "accent.primary": "#A6F3D1"
      }
    },
    "look": {
      "corners": "chamfer",
      "corner_size": 12
    }
  }
}
```

The example is intentionally partial. A package may include any supported path in the explicit visual allowlist in `shell/lib/themeprofiles.luau`.

Included categories:
- Palette source, mode, Matugen extraction choices, semantic colour overrides and finish.
- Global geometry and corner treatment.
- Shell effects and motion speed.
- Bar material and visual construction.
- Desktop border, opacity, shadow and blur appearance.
- Notification signal density and presentation.

Excluded categories:
- Keyboard shortcuts and input preferences.
- Workspace assignments, window rules and layouts.
- Personal identity, avatars and banners.
- Privacy, security and accessibility preferences.
- Application enablement preferences and unrelated tool data.
- Arbitrary commands, scripts, callbacks or executable content.

## Pure API

`require("lib/themeprofiles")` exposes:

- `capture(settings, name, description)` — validate current settings and produce a package containing only the visual allowlist.
- `validate(package)` — check format/version, metadata, allowed paths, config-schema values and semantic colour-token names. Returns a canonical package or a reason.
- `apply(current, package)` — validate the package and return a copied settings document with only package-owned visual paths replaced.

Applying a package preserves unrelated current settings, including keys and fields owned by integrations unknown to this version of mooi. Neither capture nor apply mutates its input.

The model is pure Lua/Luau and is covered by `tests/unit/run.lua`. The next integration step is user-facing import/export and a saved-package location; this document does not claim those commands or UI exist yet.

## Safety and compatibility

- Unknown setting paths are rejected, not silently ignored.
- Invalid enum, numeric, boolean and colour values are rejected by the canonical settings schema.
- Unknown semantic colour roles are rejected.
- Future package versions are rejected until an explicit migration exists.
- Packages contain data only. They cannot execute code or change system services.
- The current settings schema remains authoritative; package validation does not define a parallel set of setting rules.
