# Bar & Frame: styles, settings and per-module looks

Date: 2026-11-06 · Status: design approved in brainstorming, spec awaiting review · Decision: D166
Part of: `docs/superpowers/specs/2026-11-06-bar-redesign-design.md` (D164), replacing its stage 2 and
taking the per-module half of stage 4 and the settings half of stage 6. The Pill (stage 3) follows.
Mockups: `.superpowers/brainstorm/583795-1793963491/content/` (settings-ia, styles, modules)

## 1. Why

After stage 1 the owner reported:

- Settings for the bar are spread over eight pages (Quick, Colour, Motion, Bar, Layout, Workspaces,
  Media, and Screen frame under Desktop) and are hard to find; the Pill has no option yet.
- The Steel style should be removed; the styles should be better and make sense.
- In islands mode every module or group should be its own: order, colour, fill, rounding.
- Edges must be logical with the frame and with every style.
- With the frame on, the bar and frame should read as one body, and swell should move that body.

Success: someone who has never used mooi finds everything about the bar on one page, understands
the four big choices without reading, and can still reach every detail; every style looks deliberate
with the frame off, on, and swelling; any island can be made to look different from the others.

## 2. One page: Bar & Frame

- A new settings page **Bar & Frame** (group BAR) replaces the pages **Bar**, **Layout** and
  **Screen frame**. **Workspaces** and **Media** become entries under its Modules section (those
  modules' own settings). **Colour** is renamed **Theme & colour** and stays the desktop-wide palette.
  Motion, Quick and the rest stay; Quick keeps shortcuts that open Bar & Frame at a section.
- **Top: four big choices**, always visible:
  - **Shape**: Full · Notch · Islands (· Pill, added by stage 3)
  - **Style**: Instrument · Glass · Floating · Hairline · Minimal (+ "Custom" when edited)
  - **Frame**: Off · On
  - **Density**: Minimal · Balanced · Rich (stored now; applied by stage 4)
- **Below: folded sections**, in this order, each with a one-line summary of its current values:
  1. **Edges & outline** — outline (none · corners · thin · regular · bold), outline colour, corners
     shape and size, the bar's rounding.
  2. **Surface & depth** — surface (solid · glass · blur · clear · mech), opacity, frost, smoke, ground,
     shadow, hover pill.
  3. **Frame & music** — band, radius, edge (line · neon · none), opacity, sides, swell (off · swell ·
     ripples · pulse), reach, and **islands: float · attach** (§5).
  4. **Size & place** — height, width, offset, rail, accents, labels, wheel.
  5. **Modules** — the order and each module's or group's look (§4); Workspaces and Media inside.
  6. **The Pill** — a placeholder entry ("comes with the Pill") until stage 3 fills it.
- The real bar is the preview: every change shows on it at once. No second rendering of the bar.
- Search keeps finding every setting (the generated `settings_index` follows the new pages).
- The settings window is generated (`tools/gen-settings.py`): folded sections need a section/fold
  primitive in the generator; setter codes stay append-only (no code moves).

## 3. Styles

A style is a preset over the finer settings; picking one writes them, editing any one shows Custom.

| Style | Surface | Outline | Width | Colour | Shadow | Hover pill | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Instrument** (default) | solid | line | regular | subtle | off | soft | rail and accents on |
| **Glass** | glass | line | thin | bright | soft | outline | frost 60, smoke 30, opacity 85 |
| **Floating** | solid | none | — | — | strong | glow | |
| **Hairline** (new) | clear | line | thin | accent | off | underline | no fill: the wallpaper shows through |
| **Minimal** | clear | none | — | — | off | underline | readings only |

- **Steel is removed** from `bar.style`. A file with `bar.style = "steel"` loads as `instrument` with
  every finer value it carries kept (so the bar looks the same until the owner changes something), and
  a note says so. `bar.surface = "mech"` stays as a surface anyone can pick.
- Each style is defined once (`lib/style` `BAR_PRESETS`); the settings window, the editor and theme
  profiles read it from there.

## 4. Per-module looks

- Modules are ordered and grouped as today (`bar.left/center/right`, `a+b` groups share a plate).
- Each module (or group, keyed by its first module) may override, under `bar.modules.<id>`:

| Key | Values | Default |
| --- | --- | --- |
| `colour` | `style` · a palette role (`phos`, `ember`, `trace`, …) · `#rrggbb` · `wallpaper` | `style` |
| `fill` | `style` · `solid` · `tinted` · `glass` · `none` | `style` |
| `rounding` | `style` · `square` · `soft` · `round` · `pill` | `style` |
| `outline` | `style` · `none` · `accent` | `style` |
| `glow` | `off` · `soft` · `strong` | `off` |
| `display` | `icon` · `icon+value` · `label+value` | `icon+value` |
| `width` | `fit` · `fixed` | `fit` |

- `style` means "as the bar's style says", so nothing changes until chosen. Colours follow the theme
  (a role) unless a fixed `#rrggbb` is picked.
- The chassis draws each island's plate with its own fill, rounding and outline: `lib/chassis` gains
  per-piece look fields (`fill`, `r`, `outline`, `colour`), and the frame scene's slots carry them.
  Content colour (icons, text) follows the module's colour.
- **Editor**: the on-bar edit mode (✎) opens the same per-module controls as Settings → Modules, with
  "same as the style", copy look and paste look. Both write through `lib/settingsfile`.

## 5. Edges with the frame (the rules)

- One outline width everywhere (Edges & outline).
- With the frame on, the bar and the frame are **one body**, and swell moves that body:
  - **Full** is the frame's top (stage 1).
  - **Notch** hangs from the band (stage 1).
  - **Islands**, `frame.islands`:
    - `float` (default): plates under the band with 3 px of air (stage 1).
    - `attach`: each island hangs from the band and swells with it. To keep the gaps from reading as
      empty tabs, the band's inner edge between attached islands sits level with their top (the band
      thickens to the islands' top, as one strip with the islands hanging below it), so a gap is a
      recess in one body, not a tab.
- The band takes the style's outline colour; a style with no outline (Floating, Minimal) gives the
  frame no line, only its band's fill: turning the frame on never adds a line the style lacks.
- Neon (`frame.edge`) remains the frame's own glow choice on top of the style's line.

## 6. Settings migration

- Every existing key keeps its name and value; only `bar.style = "steel"` is migrated (§3).
- New keys: `frame.islands` (`float`), `bar.modules.<id>.{colour, fill, rounding, outline, glow,
  display, width}` (all default as in §4). `bar.density` and `bar.material` exist since stage 1.
- Setter codes are appended; the settings window's codes are checked on every generate (as today).

## 7. Testing

- Unit: steel migration; each preset's values; preset → Custom detection; per-module defaults and
  validation (bad colour, unknown fill fall back with a note); chassis per-piece look; attach geometry
  (band level with island tops, one foot); settings index covers every key on its new page.
- `tests/chassis.sh` extended: every style × frame off/on × swell, and `frame.islands` float/attach;
  the attach check asserts no gap reads as a tab (no outline across a gap below the band's inner edge).
- Before/after screenshots of every style with the frame off, on and swelling; per-module looks shown
  on a live bar with four differently styled islands.
- Gate, CI container, and `runtime error`-free logs after `bin/mooi session`.

## 8. Out of scope

- The Pill itself (stage 3), Liquid and Cartridge (stages 7–8), density's effect on modules (stage 4),
  the interactive tray (stage 5).
