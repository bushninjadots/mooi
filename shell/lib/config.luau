-- mooi settings: defaults, validation, and what to say about a bad file.
-- Pure: no pleamar globals, so tests/unit runs it under plain Lua 5.4.
-- Written in the subset Lua 5.4 and Luau share.

local barlayout = require("lib/barlayout")

local M = {}

M.VERSION = 2

-- One row per setting: dotted path, type, default, and limits for numbers.
-- A row with no default is not written by `defaults()`: it is a setting the user may
-- add (the theme's colour overrides), and leaving it out means "not set".
-- `values` is for enums, and "colour" expects #rrggbb (lib/theme.luau owns the palette).
M.SCHEMA = {
    { path = "spine.max_workspaces", kind = "integer", default = 10, min = 1, max = 16 },
    -- The Mechanism (the bar): what the chain's labels say, and what the wheel over it does.
    { path = "bar.labels", kind = "boolean", default = true },
    { path = "bar.wheel", kind = "enum", values = { "step", "off", "invert" }, default = "step" },
    -- The Ferrolume bar (docs/FERROLUME.md). Where the modules go — three lists, left to
    -- right, an entry being one module or several joined with `+` (one shared frame) — and
    -- how the bar is built: separate islands or one full panel, what the panel or the frames
    -- are made of, a border round the full panel, and the media's visualizer.
    { path = "bar.left", kind = "layout", default = barlayout.DEFAULT.left },
    { path = "bar.center", kind = "layout", default = barlayout.DEFAULT.center },
    { path = "bar.right", kind = "layout", default = barlayout.DEFAULT.right },
    -- `notch`: each cluster hangs from the screen's top edge, the centre one a notch, the side
    -- ones flush with the corners, joined to the edge by inner fillets.
    { path = "bar.mode", kind = "enum", values = { "islands", "full", "notch" }, default = "islands" },
    { path = "bar.surface", kind = "enum", values = { "solid", "glass", "blur", "clear", "mech" }, default = "solid" },
    { path = "bar.visualizer", kind = "enum", values = { "mirror", "bars", "line", "dots", "off" }, default = "mirror" },
    -- The instruments (dna, prism, cells) and the everyday switchers: pills (occupied plates that
    -- merge, the active one sliding), segments (thin bars that open on hover to show each
    -- workspace's app), dots (the active one stretched), numbers.
    { path = "bar.workspaces", kind = "enum", values = { "dna", "prism", "cells", "pills", "segments", "dots", "numbers", "compass", "radar" }, default = "dna" },
    -- The DNA's strands as the workspace frame's own edges, in islands mode too (in full mode
    -- they are always the panel's).
    { path = "bar.helix_frame", kind = "boolean", default = true },
    -- The screen frame (ArchEclipse's Tide, in mooi): a band round the screen that the bar is
    -- the top of, swelling with the music. How thick, whether and how it moves with the music,
    -- how far it swells, and along which edges.
    { path = "frame.on", kind = "boolean", default = true },
    { path = "frame.band", kind = "integer", default = 6, min = 2, max = 16 },
    { path = "frame.music", kind = "boolean", default = true },
    { path = "frame.style", kind = "enum", values = { "swell", "crests", "pulse" }, default = "swell" },
    { path = "frame.reach", kind = "integer", default = 18, min = 6, max = 40 },
    { path = "frame.edges", kind = "enum", values = { "all", "sides", "ends" }, default = "all" },
    -- The band's inner corners, its inner edge (a line, a neon line, or none) and how solid it is.
    { path = "frame.radius", kind = "integer", default = 14, min = 0, max = 40 },
    { path = "frame.edge", kind = "enum", values = { "line", "neon", "none" }, default = "line" },
    { path = "frame.opacity", kind = "integer", default = 100, min = 30, max = 100 },
    -- The media module: what it shows, and what it does with nothing playing.
    { path = "media.mode", kind = "enum", values = { "full", "compact", "art", "viz" }, default = "full" },
    { path = "media.idle", kind = "enum", values = { "collapse", "keep", "hide" }, default = "collapse" },
    -- The outline round each island (in full mode, round the panel): a line, its four corners
    -- only, or nothing. What the islands are made of is bar.surface; this is only their edge.
    { path = "bar.frame", kind = "enum", values = { "line", "corners", "none" }, default = "line" },
    { path = "bar.ground", kind = "enum", values = { "black", "tinted", "clear" }, default = "black" },
    { path = "bar.rail", kind = "boolean", default = true },
    { path = "bar.accents", kind = "boolean", default = true },
    -- The look of what the bar is made of (lib/style hands these to the scene). Defaults are the
    -- look the bar had before they existed.
    -- Presets: one choice that sets a coherent look (lib/style). What is stored is the last one
    -- chosen; the settings window shows "Custom" when the details no longer match it.
    { path = "bar.style", kind = "enum", values = { "instrument", "glass", "floating", "minimal", "steel" }, default = "instrument" },
    { path = "theme.preset", kind = "enum", values = { "phosphor", "neon_noir", "concrete", "gunmetal", "alien", "titanium" }, default = "phosphor" },
    { path = "bar.radius", kind = "integer", default = 8, min = 0, max = 16 },
    -- How much of the screen's width the bar spans, centred (islands, the full bar, the notch).
    { path = "bar.width", kind = "integer", default = 100, min = 30, max = 100 },
    -- how thick the bar's row is, and how far down from the screen's edge it sits (px)
    { path = "bar.height", kind = "integer", default = 30, min = 24, max = 44 },
    { path = "bar.offset", kind = "integer", default = 0, min = 0, max = 40 },
    -- Two choices the window offers as one (lib/setters writes the settings under them): the edge
    -- (none, corners, or a line thin / regular / bold — bar.frame and bar.outline_width) and the
    -- frame's music (off, or how it moves — frame.music and frame.style). No default: they are
    -- read from what is under them, and a file that has them keeps them.
    { path = "bar.edge", kind = "enum", values = { "none", "corners", "thin", "regular", "bold" } },
    { path = "frame.motion", kind = "enum", values = { "off", "swell", "ripples", "pulse" } },
    { path = "bar.outline_width", kind = "integer", default = 2, min = 1, max = 3 },
    { path = "bar.outline_colour", kind = "enum", values = { "subtle", "bright", "accent" }, default = "subtle" },
    { path = "bar.pill", kind = "enum", values = { "soft", "outline", "underline", "glow" }, default = "soft" },
    { path = "bar.shadow", kind = "enum", values = { "off", "soft", "medium", "strong" }, default = "off" },
    { path = "bar.opacity", kind = "integer", default = 100, min = 20, max = 100 },
    { path = "bar.frost", kind = "integer", default = 70, min = 0, max = 100 },
    { path = "bar.smoke", kind = "integer", default = 38, min = 0, max = 80 },
    -- The bar's background: black, the wallpaper's own dark, a dark of the main colour, a few
    -- fixed tones, or `bar.bg_colour`; then shifted in lightness, saturation and hue. The text
    -- on it is re-held to its contrast floors, so a light background darkens the text.
    -- (the first tones stay for settings that chose them; the industrial ones are what is offered)
    { path = "bar.bg", kind = "enum", values = { "black", "wallpaper", "accent", "graphite", "navy", "plum", "forest", "wine", "sand", "custom",
        "obsidian", "gunmetal", "concrete", "titanium", "oxide", "alien" }, default = "black" },
    { path = "bar.bg_colour", kind = "colour", default = "#101418" },
    { path = "bar.bg_light", kind = "integer", default = 0, min = -10, max = 40 },
    { path = "bar.bg_sat", kind = "integer", default = 100, min = 0, max = 150 },
    { path = "bar.bg_hue", kind = "integer", default = 0, min = -180, max = 180 },
    -- Effects: chromatic aberration (glass edges split their colours, readings their channels)
    -- and how strongly lit things glow.
    { path = "fx.aberration", kind = "integer", default = 0, min = 0, max = 100 },
    { path = "fx.glow", kind = "integer", default = 100, min = 0, max = 160 },
    -- Every module can be hidden, and can wear its own frame (`inherit` = bar.frame); a group
    -- wears its first member's.
    { path = "island.confirm_close", kind = "boolean", default = true },
    { path = "island.follow_on_send", kind = "boolean", default = false },
    -- every island's look (ui/island.plm): Ferrolume plates, or tethered to their module
    { path = "island.style", kind = "enum", values = { "plate", "tether" }, default = "plate" },
    -- what the clock module shows; a right press on it cycles them
    { path = "clock.view", kind = "enum", values = { "full", "time", "seconds" }, default = "full" },
    -- the spine on the right edge, whose shelves slide out on hover (D100)
    { path = "shelves.on", kind = "boolean", default = true },
    -- and whether it keeps out of sight until the pointer touches the right edge (a hairline shows it is there)
    { path = "shelves.autohide", kind = "boolean", default = false },
    { path = "motion.reduced", kind = "boolean", default = false },
    -- How fast everything moves (%, the springs scaled when the bar starts: bin/mooi snapshot), and
    -- the battery saver: glow, aberration, the frame's music and the visualizer off — on battery,
    -- or always.
    { path = "motion.speed", kind = "integer", default = 100, min = 50, max = 200 },
    { path = "motion.saver", kind = "enum", values = { "off", "battery", "always" }, default = "off" },
    -- The system's power profile (power-profiles-daemon), or `keep` to leave it be.
    { path = "power.profile", kind = "enum", values = { "keep", "power-saver", "balanced", "performance" }, default = "keep" },
    { path = "command.max_results", kind = "integer", default = 7, min = 3, max = 10 },
    { path = "atlas.previews", kind = "boolean", default = true },
    -- The tray's icons: drawn in the bar's own colours (and their own on hover), or as given.
    { path = "tray.style", kind = "enum", values = { "themed", "original" }, default = "themed" },
    -- Your apps in mooi's palette (bin/mooi apps-sync): each off leaves the app as it was.
    { path = "apps.kitty", kind = "boolean", default = false },
    { path = "apps.gtk", kind = "boolean", default = false },
    { path = "apps.qt", kind = "boolean", default = false },
    -- Your own Matugen config (~/.config/matugen/config.toml: btop, fish, cava, Vesktop, Zen,
    -- Spicetify, the widgets…) run with mooi's wallpaper and mode, so they follow day and night.
    { path = "apps.others", kind = "boolean", default = false },
    -- The desktop around the bar (Hyprland's own look), set by mooi only while `manage` is on:
    -- the window border's width and colour (`theme` follows the bar's palette, `keep` leaves
    -- Hyprland's), the gaps between windows and round the screen, the corners, and dimming
    -- the windows that are not focused. Applied live, and kept across restarts by
    -- ~/.config/hypr/config/custom/mooi.lua reading what mooi writes.
    { path = "desktop.manage", kind = "boolean", default = false },
    { path = "desktop.border", kind = "integer", default = 2, min = 0, max = 8 },
    { path = "desktop.border_colour", kind = "enum", values = { "theme", "accent", "keep" }, default = "theme" },
    { path = "desktop.gaps_in", kind = "integer", default = 4, min = 0, max = 20 },
    { path = "desktop.gaps_out", kind = "integer", default = 12, min = 0, max = 40 },
    { path = "desktop.rounding", kind = "integer", default = 12, min = 0, max = 24 },
    { path = "desktop.dim_inactive", kind = "boolean", default = false },
    -- Windows and scrolling. `keep` leaves Hyprland's own value alone (the default for each),
    -- so turning these on changes nothing until one is chosen.
    { path = "desktop.layout", kind = "enum", values = { "keep", "dwindle", "master", "scrolling", "monocle" }, default = "keep" },
    -- Numbers whose lowest value means "keep" (Hyprland's own): the column's width in % (9 keeps),
    -- the scroll speeds in % (4 keeps), the windows' opacity in % (49 keeps).
    { path = "desktop.column", kind = "integer", default = 9, min = 9, max = 100 },
    { path = "desktop.column_fit", kind = "enum", values = { "keep", "fit", "center" }, default = "keep" },
    { path = "desktop.touchpad_natural", kind = "enum", values = { "keep", "on", "off" }, default = "keep" },
    { path = "desktop.touchpad_speed", kind = "integer", default = 4, min = 4, max = 200 },
    { path = "desktop.mouse_natural", kind = "enum", values = { "keep", "on", "off" }, default = "keep" },
    { path = "desktop.mouse_speed", kind = "integer", default = 4, min = 4, max = 200 },
    { path = "desktop.blur", kind = "enum", values = { "keep", "off", "light", "medium", "heavy" }, default = "keep" },
    { path = "desktop.opacity_active", kind = "integer", default = 49, min = 49, max = 100 },
    { path = "desktop.opacity_inactive", kind = "integer", default = 49, min = 49, max = 100 },
    -- Window shadows: a dark soft one, a deep one, or a neon glow in the palette's main colour.
    { path = "desktop.shadow", kind = "enum", values = { "keep", "off", "soft", "deep", "neon" }, default = "keep" },
    { path = "desktop.shadow_size", kind = "integer", default = 14, min = 2, max = 40 },
    -- Hyprland 0.56's finer blur: how much the blur saturates (0 keeps), floating windows blurring
    -- only the wallpaper (xray), and right-click menus blurred behind.
    { path = "desktop.blur_vibrancy", kind = "integer", default = 0, min = 0, max = 100 },
    { path = "desktop.blur_xray", kind = "enum", values = { "keep", "on", "off" }, default = "keep" },
    { path = "desktop.blur_popups", kind = "enum", values = { "keep", "on", "off" }, default = "keep" },
    -- Windows in motion (0.56): a spring under the windows' open and move animations — `off` settles
    -- without overshoot, the rest overshoot and wobble into place, more each step — and motion blur
    -- on windows being moved or resized.
    { path = "desktop.wobble", kind = "enum", values = { "keep", "off", "subtle", "wobbly", "jelly" }, default = "keep" },
    { path = "desktop.motion_blur", kind = "enum", values = { "keep", "off", "soft", "strong" }, default = "keep" },
    -- mooi's keys: "SUPER + ALT + Space" and the like (Hyprland's own spelling). Bound live
    -- and by custom/mooi.lua at Hyprland's start.
    { path = "keys.search", kind = "key", default = "SUPER + ALT + Space" },
    { path = "keys.window", kind = "key", default = "SUPER + ALT + W" },
    { path = "keys.stop", kind = "key", default = "SUPER + ALT + SHIFT + Space" },
    { path = "keys.settings", kind = "key", default = "SUPER + ALT + S" },
    { path = "keys.edit", kind = "key", default = "SUPER + ALT + E" },
    { path = "keys.system", kind = "key", default = "SUPER + ALT + C" },
    { path = "keys.shutter", kind = "key", default = "SUPER + ALT + D" },
    { path = "keys.wallpaper", kind = "key", default = "SUPER + ALT + P" },
    { path = "keys.player", kind = "key", default = "SUPER + ALT + M" },
    -- Who receives the session's notifications: mooi only while it holds the desktop
    -- (`takeover`, so beside ArchEclipse they stay ArchEclipse's — D5), `always`, or `never`.
    { path = "notifications.server", kind = "enum", values = { "takeover", "always", "never" }, default = "takeover" },
    -- Do not disturb: no toasts (urgent ones still come), the notices still kept — always, while
    -- the focus timer runs, or in quiet hours (from … to, the hour of the day).
    -- The Mechanical Shutter (D35): on or off, Super+Alt+right-click on a window as well as its key,
    -- where it unfolds, how big, whether a plate opens under the pointer, and which plates.
    -- The Overview (D37): every workspace zoomed out as a miniature of its screen, a page of
    -- rows × columns; Super+Tab opens it (beside its own key in Keys).
    { path = "atlas.rows", kind = "integer", default = 2, min = 1, max = 3 },
    { path = "atlas.columns", kind = "integer", default = 5, min = 2, max = 6 },
    { path = "atlas.super_tab", kind = "boolean", default = true },
    { path = "atlas.overview", kind = "enum", values = { "grid", "strip", "canvas" }, default = "grid" },
    { path = "atlas.private", kind = "enum", values = { "off", "sensitive", "everything" }, default = "sensitive" },
    -- Its look and feel (D44): each workspace's size as a share of the screen (iNiR's 18 %), how dark
    -- the desktop goes behind it, whether the workspace you are on zooms out into its place, and how
    -- often window pictures are taken while it is open (as it opens is the smooth one: D40).
    { path = "atlas.size", kind = "integer", default = 18, min = 14, max = 24 },
    { path = "atlas.dim", kind = "integer", default = 55, min = 0, max = 80 },
    { path = "atlas.zoom", kind = "boolean", default = true },
    { path = "atlas.refresh", kind = "enum", values = { "open", "steady" }, default = "open" },
    -- mooi as the whole desktop (D48): started at login in place of ArchEclipse's bar, the keys that
    -- only reached ArchEclipse taken over, and nothing bringing ArchEclipse back. ArchEclipse stays
    -- installed: switched off, it is the login shell again.
    { path = "session.standalone", kind = "boolean", default = false },
    -- A touchpad swipe down to open it (D45): off, or with three or four fingers.
    { path = "atlas.gesture", kind = "enum", values = { "off", "three", "four" }, default = "off" },
    { path = "keys.mode", kind = "key", default = "SUPER + ALT + T" },
    { path = "keys.overview", kind = "key", default = "SUPER + ALT + O" },
    { path = "shutter.enabled", kind = "boolean", default = true },
    { path = "shutter.pointer", kind = "boolean", default = true },
    { path = "shutter.edge", kind = "enum", values = { "auto", "left", "inside" }, default = "auto" },
    { path = "shutter.density", kind = "enum", values = { "standard", "compact" }, default = "standard" },
    { path = "shutter.preview", kind = "boolean", default = false },
    { path = "shutter.arrange", kind = "boolean", default = true },
    { path = "shutter.workspace", kind = "boolean", default = true },
    { path = "shutter.behaviour", kind = "boolean", default = true },
    { path = "shutter.connections", kind = "boolean", default = true },
    { path = "notifications.dnd", kind = "enum", values = { "off", "on", "focus", "hours" }, default = "off" },
    { path = "notifications.quiet_from", kind = "integer", default = 22, min = 0, max = 23 },
    { path = "notifications.quiet_to", kind = "integer", default = 7, min = 0, max = 23 },
    -- Signal Loom (D50): where the signals unfold from, how many at once, how long a normal one
    -- stays out (seconds; a low one half as long, an urgent one until it is dealt with), how they
    -- group (a thread: one app and title; an app; none), their size, the cut of their corners,
    -- how far they travel as they unfold (0: they open in place), their glow, and whether what a
    -- notice says shows in the pop-up or waits for the Signal Field.
    { path = "signals.edge", kind = "enum", values = { "top_right", "top_left", "bottom_right", "bottom_left" }, default = "top_right" },
    { path = "signals.max", kind = "integer", default = 4, min = 1, max = 6 },
    { path = "signals.linger", kind = "integer", default = 7, min = 3, max = 30 },
    { path = "signals.grouping", kind = "enum", values = { "thread", "app", "off" }, default = "thread" },
    { path = "signals.density", kind = "enum", values = { "compact", "comfortable" }, default = "compact" },
    { path = "signals.chamfer", kind = "integer", default = 8, min = 0, max = 14 },
    { path = "signals.travel", kind = "integer", default = 100, min = 0, max = 100 },
    { path = "signals.effects", kind = "boolean", default = true },
    { path = "signals.private", kind = "boolean", default = false },
    -- The colours follow the wallpaper's Matugen palette unless the user says otherwise,
    -- because that is the brief's pipeline and what a desktop that already runs Matugen
    -- expects (docs/MECHANISM.md §8). `fixed` is the brief's own palette, and it is also
    -- what shows when no palette has been generated yet; the mark's menu is the switch.
    { path = "theme.source", kind = "enum", values = { "fixed", "wallpaper" }, default = "wallpaper" },
    -- Day and night (D91): the whole desktop — the bar, every mooi window, and the apps mooi
    -- colours — light or dark. `auto` is light from `light_at` to `dark_at` (whole hours, local
    -- time); bin/mooi decides which, so Matugen, the bar and the apps always agree.
    { path = "theme.mode", kind = "enum", values = { "dark", "light", "auto" }, default = "dark" },
    -- Corners on every plate mooi draws (lib/style corners): the shape, and a size on each one's design
    -- BMO, the desktop companion (shell/bmo): started by the bar while companion.bmo is on; his own
    -- place and energy are not settings (bmo-state.json in his data folder)
    { path = "companion.bmo", kind = "boolean", default = true },
    { path = "companion.place", kind = "enum", values = { "desktop", "bar" }, default = "desktop" },
    { path = "companion.size", kind = "enum", values = { "tiny", "small", "medium", "large" }, default = "medium" },
    { path = "companion.variant", kind = "enum", values = { "classic", "night", "pastel", "gameboy", "mooi" }, default = "classic" },
    { path = "companion.above", kind = "boolean", default = false },
    { path = "companion.wander", kind = "integer", default = 2, min = 0, max = 3 },
    { path = "companion.locked", kind = "boolean", default = false },
    { path = "companion.motion", kind = "enum", values = { "still", "calm", "lively" }, default = "calm" },
    { path = "companion.throw", kind = "boolean", default = true },
    { path = "companion.talk", kind = "enum", values = { "off", "rare", "chatty" }, default = "rare" },
    { path = "companion.music", kind = "boolean", default = true },
    { path = "companion.clock", kind = "boolean", default = true },
    { path = "companion.doze", kind = "integer", default = 10, min = 1, max = 100000 },
    { path = "companion.react.notes", kind = "boolean", default = true },
    { path = "companion.react.spaces", kind = "boolean", default = true },
    { path = "companion.react.battery", kind = "boolean", default = true },
    { path = "companion.react.focus", kind = "boolean", default = true },
    { path = "companion.react.time", kind = "boolean", default = true },
    { path = "look.corners", kind = "enum", values = { "chamfer", "bevel", "round", "square" }, default = "chamfer" },
    { path = "look.corner_size", kind = "integer", default = 12, min = 0, max = 24 },
    { path = "theme.light_at", kind = "integer", default = 7, min = 0, max = 23 },
    { path = "theme.dark_at", kind = "integer", default = 19, min = 0, max = 23 },
    -- One table of token = colour: a dotted setting path cannot name a token that has a
    -- dot in it (`theme.overrides.bg.primary` would read as four nested keys). Which
    -- tokens exist, and which of them the user misspelled, is lib/theme.luau's business.
    { path = "theme.overrides", kind = "colours" },
    -- How Matugen extracts the palette (bin/mooi theme-sync reads these too): the scheme
    -- type, which of the wallpaper's five dominant colours it starts from, and the contrast.
    -- `signal` is where the bar's second signal comes from (lib/ferro: auto picks the palette
    -- colour that stands furthest from the phosphor).
    { path = "theme.scheme", kind = "enum", values = { "tonal-spot", "content", "expressive", "fidelity",
        "fruit-salad", "monochrome", "neutral", "rainbow", "vibrant", "smart" }, default = "tonal-spot" },
    { path = "theme.color_index", kind = "integer", default = 0, min = 0, max = 4 },
    { path = "theme.contrast", kind = "integer", default = 0, min = -1, max = 1 },
    { path = "theme.signal", kind = "enum", values = { "auto", "tertiary", "secondary", "complement", "analogous", "triadic" }, default = "auto" },
    -- Luminous colours glow; matte ones are quieter (less saturated, no glow from the palette).
    -- `saturation` pushes the whole palette's colour up or down.
    { path = "theme.finish", kind = "enum", values = { "luminous", "matte", "neon" }, default = "luminous" },
    { path = "theme.saturation", kind = "integer", default = 0, min = -50, max = 50 },
    -- The wallpaper studio's defaults (D61): how a picture with no recipe of its own opens. A
    -- matte (0 leaves it full-bleed), what fills the matte, and whether the picture's own
    -- background — the colour read from its corners — is keyed out into the backdrop.
    { path = "wallpaper.matte", kind = "integer", default = 0, min = 0, max = 25 },
    { path = "wallpaper.backdrop", kind = "enum", values = { "black", "picture", "corners", "edges", "both" }, default = "black" },
    { path = "wallpaper.key", kind = "boolean", default = false },
    { path = "wallpaper.fuzz", kind = "integer", default = 18, min = 0, max = 45 },
    -- The Control Nexus (D102): what the bar's mark opens — the deck, or the spine's shelves all out
    -- at once (Cascade) — and the edge the deck comes from.
    { path = "nexus.mode", kind = "enum", values = { "deck", "cascade" }, default = "deck" },
    { path = "nexus.edge", kind = "enum", values = { "bottom", "top", "left", "right" }, default = "bottom" },
    -- the deck's parts in your order, and those you hid (✎ on the deck arranges them; lib/nexusdeck PARTS)
    { path = "nexus.parts", kind = "ids", max = 12 },
    { path = "nexus.hidden", kind = "ids", max = 12 },
    -- one row of cards along a strip, or two; the profile card small or large; the music on the deck's edge
    { path = "nexus.rows", kind = "integer", default = 1, min = 1, max = 2 },
    { path = "nexus.profile", kind = "enum", values = { "small", "large" }, default = "small" },
    { path = "nexus.visualiser", kind = "boolean", default = true },
    -- The desk (D85, lib/desk): mooi draws the wallpaper so it can travel, and lays Lumen's
    -- cutout over the desktop widgets.
    { path = "desk.on", kind = "boolean", default = false },
    { path = "desk.parallax", kind = "enum", values = { "off", "workspaces", "pointer", "both" }, default = "workspaces" },
    { path = "desk.strength", kind = "integer", default = 45, min = 0, max = 100 },
    { path = "desk.cutout", kind = "boolean", default = true },
    { path = "desk.depth", kind = "boolean", default = true },
    -- The music player (D88): its colours from the shell's palette, or from the album cover.
    { path = "player.colours", kind = "enum", values = { "shell", "cover" }, default = "shell" },
    -- each place's visualiser (the music player overhaul; lib/vizbands STYLES, shell/ui/viz.plm)
    -- the library: how it groups, and how it sorts (the music player overhaul)
    -- the song's video as the visual (mpv, found with yt-dlp on a press): off hides the chip
    { path = "player.video", kind = "boolean", default = true },
    { path = "player.view", kind = "enum", values = { "deck", "stage", "rack" }, default = "deck" },
    { path = "player.library", kind = "enum", values = { "albums", "artists", "genres", "songs" }, default = "albums" },
    { path = "player.sort", kind = "enum", values = { "artist", "album", "year", "title", "time" }, default = "artist" },
    { path = "player.viz_mini", kind = "enum", values = { "spectrum", "mirror", "ring", "aurora", "led", "orbit", "off" }, default = "ring" },
    { path = "player.viz_deck", kind = "enum", values = { "spectrum", "mirror", "ring", "aurora", "led", "orbit", "off" }, default = "ring" },
    { path = "player.viz_stage", kind = "enum", values = { "spectrum", "mirror", "ring", "aurora", "led", "orbit", "off" }, default = "aurora" },
    { path = "player.viz_rack", kind = "enum", values = { "spectrum", "mirror", "ring", "aurora", "led", "orbit", "off" }, default = "led" },
    { path = "player.viz_full", kind = "enum", values = { "spectrum", "mirror", "ring", "aurora", "led", "orbit", "off" }, default = "ring" },
    { path = "nexus.identity.name", kind = "text", default = "mooi system", max = 48 },
    { path = "nexus.identity.avatar", kind = "text", default = "", max = 180 },
    { path = "nexus.identity.banner", kind = "text", default = "", max = 180 },
}

for _, id in ipairs(barlayout.ORDER) do
    M.SCHEMA[#M.SCHEMA + 1] = { path = "bar.modules." .. id .. ".show", kind = "boolean", default = true }
    M.SCHEMA[#M.SCHEMA + 1] = { path = "bar.modules." .. id .. ".frame", kind = "enum",
        values = { "inherit", "line", "corners", "none" }, default = "inherit" }
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

local function get(t, path)
    local node = t
    for key in string.gmatch(path, "[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

local function set(t, path, value)
    local node = t
    local keys = {}
    for key in string.gmatch(path, "[^.]+") do keys[#keys + 1] = key end
    for i = 1, #keys - 1 do
        node[keys[i]] = node[keys[i]] or {}
        node = node[keys[i]]
    end
    node[keys[#keys]] = value
end

function M.defaults()
    local out = { version = M.VERSION }
    for _, row in ipairs(M.SCHEMA) do
        if row.default ~= nil then set(out, row.path, copy(row.default)) end
    end
    return out
end

local function check(row, value)
    if row.kind == "boolean" then
        if type(value) ~= "boolean" then return false, "expected true or false" end
    elseif row.kind == "integer" then
        if type(value) ~= "number" or value ~= math.floor(value) then return false, "expected a whole number" end
        if value < row.min or value > row.max then
            return false, string.format("expected %d to %d", row.min, row.max)
        end
    elseif row.kind == "enum" then
        if type(value) ~= "string" then return false, "expected one of " .. table.concat(row.values, ", ") end
        local known = false
        for _, allowed in ipairs(row.values) do if value == allowed then known = true end end
        if not known then return false, "expected one of " .. table.concat(row.values, ", ") end
    elseif row.kind == "colour" then
        if type(value) ~= "string" or not string.match(value, "^#%x%x%x%x%x%x$") then return false, "expected a colour like #101418" end
    elseif row.kind == "text" then
        if type(value) ~= "string" or #value > row.max or string.find(value, "[%c]") then
            return false, "expected plain text up to " .. tostring(row.max) .. " characters"
        end
    elseif row.kind == "key" then
        if type(value) ~= "string" or not string.match(value, "^[%w%s%+_]+$") or not string.match(value, "%w$") then
            return false, "expected keys like \"SUPER + ALT + Space\""
        end
    elseif row.kind == "layout" then
        local ok, why = barlayout.check_list(value, {})
        if not ok then return false, why end
    elseif row.kind == "ids" then
        if type(value) ~= "table" then return false, "expected a list of module ids" end
        if #value > (row.max or 8) then return false, "expected at most " .. tostring(row.max or 8) .. " ids" end
        for _, id in ipairs(value) do
            if type(id) ~= "string" or #id > 24 or not string.match(id, "^[%w_]+$") then
                return false, "expected ids like \"cpu\""
            end
        end
    elseif row.kind == "colours" then
        if type(value) ~= "table" then return false, "expected a table of token = colour" end
        for token, hex in pairs(value) do
            if type(hex) ~= "string" or not string.match(hex, "^#%x%x%x%x%x%x$") then
                return false, string.format("expected a colour like #A6F3D1 for %s", tostring(token))
            end
        end
    end
    return true
end

-- Keys present in the file that the schema does not know.
local function unknown_keys(t, prefix, known, out)
    for key, value in pairs(t) do
        local path = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
        if path ~= "version" then
            if type(value) == "table" and known.sections[path] then
                unknown_keys(value, path, known, out)
            elseif not known.leaves[path] then
                out[#out + 1] = path
            end
        end
    end
end

local function known_paths()
    local known = { leaves = {}, sections = {} }
    for _, row in ipairs(M.SCHEMA) do
        known.leaves[row.path] = true
        local section = string.match(row.path, "^(.*)%.[^.]+$")
        while section do
            known.sections[section] = true
            section = string.match(section, "^(.*)%.[^.]+$")
        end
    end
    return known
end

-- Validate an already-decoded table. Never fails: a bad value falls back to its
-- default and is reported. Returns settings, problems (fatal-ish), notes (harmless).
-- Settings written by an older mooi: the outline's old names (bezel → line, bracket → corners,
-- plate → none: a raised plate is a material, bar.surface, not an outline), the full panel's
-- border switch, now the outline itself, and `spine.clock`, now the clock module's own switch
-- (`bar.modules.clock.show`) unless the file sets that too.
local OUTLINE = { bezel = "line", bracket = "corners", plate = "none" }
local NUMBERED = {
    column = { keep = 9, third = 33, half = 50, two_thirds = 67, full = 100 },
    touchpad_speed = { keep = 4, slowest = 10, slow = 30, medium = 60, normal = 100, fast = 150 },
    mouse_speed = { keep = 4, slow = 50, normal = 100, fast = 150 },
}
local function migrate(t)
    if type(t) ~= "table" then return end
    -- the desktop's named choices of 2026-10-20, now numbers on sliders
    if type(t.desktop) == "table" then
        for key, map in pairs(NUMBERED) do
            local v = t.desktop[key]
            if type(v) == "string" and map[v] then t.desktop[key] = map[v] end
        end
    end
    local spine = t.spine
    if type(spine) == "table" and spine.clock ~= nil then
        -- moved as it is, so a wrong type is still reported (under its new name)
        if type(t.bar) ~= "table" then t.bar = {} end
        if type(t.bar.modules) ~= "table" then t.bar.modules = {} end
        if type(t.bar.modules.clock) ~= "table" then t.bar.modules.clock = {} end
        if t.bar.modules.clock.show == nil then t.bar.modules.clock.show = spine.clock end
        spine.clock = nil
    end
    -- D102: the Nexus is a deck; of its old settings (the node workspace, the hub, the drawer's
    -- folds, the orbit) only who you are is read. The rest goes quietly rather than as unknown settings.
    if type(t.nexus) == "table" then
        for k in pairs(t.nexus) do
            if k ~= "identity" and k ~= "mode" and k ~= "edge" and k ~= "parts" and k ~= "hidden"
               and k ~= "rows" and k ~= "profile" and k ~= "visualiser" then t.nexus[k] = nil end
        end
    end
    local b = t.bar
    if type(b) ~= "table" then return end
    -- D90: the Workspace Atlas is gone; its bar module's place is the Overview's. An unknown
    -- module would make the whole layout fall back to the default, so the name moves over.
    for _, side in ipairs({ "left", "center", "right" }) do
        if type(b[side]) == "table" then
            for i, entry in ipairs(b[side]) do
                if type(entry) == "string" then
                    b[side][i] = (("+" .. entry .. "+"):gsub("%+atlas%+", "+overview+")):sub(2, -2)
                end
            end
        end
    end
    if type(b.modules) == "table" and b.modules.atlas ~= nil then
        if b.modules.overview == nil then b.modules.overview = b.modules.atlas end
        b.modules.atlas = nil
    end
    if OUTLINE[b.frame] then b.frame = OUTLINE[b.frame] end
    if b.border == false and b.mode == "full" and b.frame == "line" then b.frame = "none" end
    b.border = nil
    if type(b.modules) == "table" then
        for _, m in pairs(b.modules) do
            if type(m) == "table" and OUTLINE[m.frame] then m.frame = OUTLINE[m.frame] end
        end
    end
end

function M.validate(t)
    migrate(t)
    local out = M.defaults()
    local problems, notes = {}, {}
    if type(t) ~= "table" then
        problems[#problems + 1] = "settings are not a JSON object; using defaults"
        return out, problems, notes
    end
    if t.version ~= nil and t.version ~= M.VERSION then
        notes[#notes + 1] = string.format("settings say version %s, this mooi reads %d", tostring(t.version), M.VERSION)
    end
    for _, row in ipairs(M.SCHEMA) do
        local value = get(t, row.path)
        if value ~= nil then
            local ok, why = check(row, value)
            if ok then
                set(out, row.path, value)
            else
                problems[#problems + 1] = string.format("%s: %s, got %s; using %s",
                    row.path, why, tostring(value), (type(row.default) == "table") and "the default" or tostring(row.default))
            end
        end
    end
    -- A module may be placed once across the three lists; a layout that places one twice is
    -- refused whole (all three back to the default), since no single list is the wrong one.
    local seen, ok, why = {}, true, nil
    for _, side in ipairs({ "left", "center", "right" }) do
        if ok then ok, why = barlayout.check_list(out.bar[side], seen) end
    end
    if not ok then
        problems[#problems + 1] = "bar layout: " .. why .. "; using the default layout"
        for _, side in ipairs({ "left", "center", "right" }) do out.bar[side] = copy(barlayout.DEFAULT[side]) end
    end
    local unknown = {}
    unknown_keys(t, "", known_paths(), unknown)
    table.sort(unknown)
    for _, path in ipairs(unknown) do notes[#notes + 1] = "unknown setting ignored: " .. path end
    return out, problems, notes
end

-- From the raw file text. `decode` is pleamar's json.decode (or a test double);
-- it may raise on broken JSON. `raw == nil` means the file does not exist.
function M.parse(raw, decode)
    if raw == nil then return M.defaults(), {}, { "no settings.json yet; using defaults" }, "missing" end
    local ok, t = pcall(decode, raw)
    if not ok then
        return M.defaults(), { "settings.json is not valid JSON (" .. tostring(t) .. "); using defaults" }, {}, "broken"
    end
    local settings, problems, notes = M.validate(t)
    return settings, problems, notes, (#problems == 0) and "ok" or "partial"
end

return M
