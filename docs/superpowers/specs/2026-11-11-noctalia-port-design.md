# Noctalia v5 into mooi, and settings people understand (2026-11-11)

The owner (2026-11-11), with a screenshot of Minflair's Convex style: "I meant side notches like this; improve and
simplify all the settings to be understandable; look at Noctalia version 5, import stuff from there — widgets,
shaders and effects and other features and bars, components, especially the dynamic pill; port what's missing and,
where we have it, refine ours to match theirs; look at their layouts and especially how they do their settings, and
make all mooi settings better like theirs."

Noctalia v5 (github.com/noctalia-dev/noctalia-shell, v5.4.1, MIT) is a native C++/OpenGL ES shell read at `03d144e`.
Nothing is copied: mooi rebuilds in Pleamar, the way it did k4 and Minflair (docs/superpowers/specs/2026-11-10-…).

## 1. Side notches (Minflair's Convex panels) — D299

What the owner showed: a dashboard out of the frame's left side (profile, GitHub numbers, contributions, updates, a
quote) and a **control centre** out of its right (Wi-Fi, Bluetooth, Night light, Caffeine, Game mode, Battery as tiles;
brightness, volume and microphone sliders; a performance-mode choice), both one body with the frame. mooi's D275
drawers have the dashboard; the right one holds notices. The right drawer becomes Minflair's control centre, its
notices moving under the tiles; both drawers lose their floating shadow and gain the frame's outline running round
them, so they read as the frame bulging out.

## 2. Settings, Noctalia's way — D300 onwards

How Noctalia's settings work (src/shell/settings, assets/translations/en.json):
- **Sections** in a sidebar, each with an icon: Appearance, Bar, Dock, Desktop, Wallpaper, Control Center, Launcher,
  Notifications, OSD, Lock Screen, Power, Services, Keybinds, Screenshot, Accessibility, Shell, System.
- Each section is cut into **groups** (General, Layout, Capsules, Behavior, Effects…), each a card.
- Each **row**: a short label in title case (one to three words), a one-line description that says what changes and
  in what unit, and the control that fits — a switch, a segmented choice of two to four, a dropdown past that, a
  slider with its unit, or a stepper for counts and milliseconds.
- **Rows that cannot apply are hidden**, not dimmed (`visibleWhen`): auto-hide's delay appears only with auto-hide on.
- Every row has search words; search runs across every section.

mooi's Settings has sections, cards, rows with descriptions, search and per-page reset, but grew by accretion:
thirty pages, names that are mooi's private vocabulary ("Ferrolume", "Signal Loom", "Subsurface", "the node"),
descriptions written as prose, related controls on different pages, dead rows dimmed rather than gone. The
overhaul, in steps:
1. **The map** (D300): the sidebar regrouped into Noctalia-like sections, in an order a newcomer follows —
   Appearance, Bar, Pill, Dock, Side panels, Desktop & widgets, Wallpaper, Windows, Effects, Notifications, Lock &
   idle, Power, Sound & display, Keys, Apps, System. Pages that are one feature's knobs become groups of its section.
2. **The words** (D302, with opencode): every label one to three plain words; every description one line, saying
   what it changes, in what unit, and what "off" means; mooi's private names explained once (a page subtitle) and
   never used as labels.
3. **Hide, don't dim** (D303): rows whose condition fails are folded away with the space they took.

## 3. Ports from Noctalia (refining what mooi has)

| Noctalia | mooi | Wave |
| --- | --- | --- |
| Bar widgets in **capsules** (fill, border, radius, padding, thickness) | the Pill's modules share one body | A: Pill → "Capsules": one body, or each module its own capsule |
| Bar widgets: lock keys, keyboard layout, power profile, night light, caffeine, privacy, network, bluetooth, media, notifications, sysmon, tray, screenshot, theme mode, custom text | the Pill has 11 modules | A (opencode): every one of these as a Pill module |
| Weather effects (rain, snow, clouds, sun, stars shaders) | live wallpaper has music/time effects | A: weather in the picture, from the weather mooi already reads |
| Hot corners (each corner an action, a delay) | none | A |
| Screen corners (rounded screen) | the frame rounds them; nothing without the frame | B |
| OSD kinds: keyboard layout, power profile, night light, caffeine, do-not-disturb, media | the gauge (D265) | B |
| Desktop widgets: sticker, label, button, volume, fancy visualiser | 16 kinds | B (opencode) |
| Dock: magnification, smart auto-hide, window previews | the dock (D280) | B |
| Control centre tabs, home shortcuts | the panel's icon row | — the panel already is this |
| Backdrop (blur/tint behind panels) | Pleamar glass on panels | — has it |
| Plugins, templates store, Niri/Umbriel pages | — | not planned (mooi is one program per surface) |

## Testing

As for the k4/Minflair port: pure helpers tested in tests/unit/port.lua, scenes compiled, `bin/mooi check` with CI's
shellcheck before every push, live screenshots driven by `pleamar --say`, never the owner's pointer.
