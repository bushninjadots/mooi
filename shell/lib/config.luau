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
    { path = "bar.mode", kind = "enum", values = { "islands", "full", "notch", "pill" }, default = "islands" },
    { path = "pill.sides", kind = "enum", values = { "show", "hide" }, default = "show" },

    -- D208: Surface — hold Super and the wallpaper opens at the pointer (the Reveal); `delay` is how long Super
    -- is held before it begins (a quicker tap keeps Super's old meaning)
    { path = "surface.on", kind = "boolean", default = false },   -- review C1: off until the owner tries the real key with it
    { path = "surface.delay", kind = "integer", default = 250, min = 150, max = 800 },
    { path = "surface.hold", kind = "boolean", default = false },   -- D271: holding Super opens it (off: Super is the tap)
    -- D209: how the wallpaper opens (the Tear or the Aperture), and whether BMO lives under it
    { path = "surface.effect", kind = "enum", values = { "tear", "aperture", "membrane", "ripple", "fold", "dissolve", "glass", "glow" }, default = "tear" },
    { path = "surface.bmo_below", kind = "boolean", default = true },
    -- D210: the Subsurface's own page — the opening's strength and edge, the wallpaper under it, the light,
    -- the layout, the widget look, and the power row's confirmation. Same order as tools/gen-settings.py.
    { path = "surface.intensity", kind = "integer", default = 85, min = 20, max = 100 },
    { path = "surface.edge", kind = "integer", default = 50, min = 20, max = 100 },
    { path = "surface.colour", kind = "enum", values = { "accent", "plain", "warm" }, default = "accent" },
    { path = "surface.speed", kind = "integer", default = 220, min = 100, max = 600 },
    { path = "surface.radius", kind = "integer", default = 18, min = 8, max = 40 },
    { path = "surface.wall", kind = "boolean", default = true },
    { path = "surface.dim", kind = "integer", default = 35, min = 0, max = 80 },
    { path = "surface.tint", kind = "integer", default = 18, min = 0, max = 100 },
    { path = "surface.fit", kind = "enum", values = { "cover", "contain" }, default = "cover" },
    { path = "surface.grid", kind = "integer", default = 45, min = 0, max = 100 },
    { path = "surface.labels", kind = "boolean", default = true },
    { path = "surface.glow", kind = "enum", values = { "off", "subtle", "bright" }, default = "subtle" },
    { path = "surface.ping", kind = "boolean", default = true },
    -- D217: push up from below — news bulges the wallpaper and presses its words up; the ping's light travels to
    -- the app's window and round its border
    { path = "surface.push", kind = "boolean", default = true },
    { path = "surface.trace", kind = "boolean", default = true },
    { path = "surface.layout", kind = "enum", values = { "arc", "row", "grid", "calm" }, default = "arc" },
    -- retired (D215): the widgets below replaced the components; kept so a saved value stays valid and no setter code moves
    { path = "surface.components", kind = "enum", values = { "right", "centre", "left" }, default = "right" },
    -- retired (D214): BMO is snapped to where he stands; kept so a saved value stays valid and no setter code moves
    { path = "surface.bmo_side", kind = "enum", values = { "left", "right" }, default = "left" },
    { path = "surface.overview", kind = "integer", default = 16, min = 0, max = 40 },
    -- retired (D215): the widgets below replaced the components; kept so a saved value stays valid and no setter code moves
    { path = "surface.power_confirm", kind = "boolean", default = true },
    { path = "surface.widget_style", kind = "enum", values = { "adaptive", "phosphor", "ink", "chrome", "paper" }, default = "adaptive" },
    -- D164: what the bar's body is made of (stage 1 draws Ferrolume; Liquid and Cartridge arrive in
    -- stages 7 and 8) and how much each module shows (stage 4 applies it)
    { path = "bar.material", kind = "enum", values = { "ferrolume", "liquid", "cartridge" }, default = "ferrolume" },
    { path = "bar.density", kind = "enum", values = { "minimal", "balanced", "rich" }, default = "balanced" },
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
    -- D166: with the frame on, islands float under its band or attach to it (lib/chassis)
    { path = "frame.islands", kind = "enum", values = { "float", "attach" }, default = "float" },
    { path = "frame.band", kind = "integer", default = 6, min = 2, max = 16 },
    { path = "frame.music", kind = "boolean", default = false },
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
    -- the islands' feet step with the music (the bar's border as the visualiser)
    { path = "bar.foot_visualizer", kind = "boolean", default = true },
    -- Music on every mooi edge: the master, how far it reaches, and its halo. The old foot
    -- switch is read as the master only when this is absent (see M.validate).
    { path = "music.rim", kind = "boolean", default = true },
    { path = "music.rim_gain", kind = "integer", default = 100, min = 25, max = 150 },
    { path = "music.rim_glow", kind = "boolean", default = true },
    -- The look of what the bar is made of (lib/style hands these to the scene). Defaults are the
    -- look the bar had before they existed.
    -- Presets: one choice that sets a coherent look (lib/style). What is stored is the last one
    -- chosen; the settings window shows "Custom" when the details no longer match it.
    { path = "bar.style", kind = "enum", values = { "instrument", "glass", "floating", "hairline", "minimal" }, default = "instrument" },   -- D166: steel removed (migrated in validate), hairline added
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
    -- These two are transports for a choice, not settings anything reads: choosing an edge writes
    -- bar.frame and bar.outline_width (lib/style `apply_edge`), and the window shows which one it is
    -- by deriving it back (`edge_index`). They had no default until the 2026-11-01 audit: a file
    -- that carried one kept a value that meant nothing, so `defaults()` gains the neutral one and
    -- `validate` checks it like any other.
    { path = "bar.edge", kind = "enum", values = { "none", "corners", "thin", "regular", "bold" }, default = "regular" },   -- = the default bar.frame line at width 2
    { path = "frame.motion", kind = "enum", values = { "off", "swell", "ripples", "pulse" }, default = "off" },
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
    -- D152/D153: an island under a module grows out of the bar's piece as one body with it (iNiR's
    -- chassis), drawn by mooi-frame — with the screen frame on or not, in every bar layout — and the
    -- Control Nexus out of the screen's edge; off, islands are plates or tethers as before
    { path = "island.morph", kind = "boolean", default = true },
    -- what the clock module shows; a right press on it cycles them
    { path = "clock.view", kind = "enum", values = { "full", "time", "seconds" }, default = "full" },
    -- the spine on the right edge, whose shelves slide out on hover (D100)
    { path = "shelves.on", kind = "boolean", default = true },
    -- and whether it keeps out of sight until the pointer touches the right edge (a hairline shows it is there)
    { path = "shelves.autohide", kind = "boolean", default = true },   -- D119: a hairline at rest, like the notch and the stash
    -- the side notch (D106): a sliver on the left edge that fans out into Claude, music, workspaces,
    -- wallpapers, weather and GitHub; the Claude it asks (an alias `claude --model` takes; empty: its default)
    { path = "notch.on", kind = "boolean", default = true },
    { path = "claude.model", kind = "enum", values = { "default", "haiku", "sonnet", "opus" }, default = "default", empty = true },
    -- When Claude cannot answer, whether a free model through opencode may (D143). Off by default:
    -- it sends the question and the last turns to a third party (fourth pass, L3).
    { path = "claude.free_fallback", kind = "boolean", default = false },
    { path = "motion.reduced", kind = "boolean", default = false },
    -- How fast everything moves (%, the springs scaled when the bar starts: bin/mooi snapshot), and
    -- the battery saver: glow, aberration, the frame's music and the visualizer off — on battery,
    -- or always.
    { path = "motion.speed", kind = "integer", default = 100, min = 50, max = 200 },
    { path = "motion.saver", kind = "enum", values = { "off", "battery", "always" }, default = "off" },
    -- The system's power profile (power-profiles-daemon), or `keep` to leave it be.
    { path = "power.profile", kind = "enum", values = { "keep", "power-saver", "balanced", "performance" }, default = "keep" },
    -- D161: how long the session may sit idle before the lock screen takes it. hypridle owns the
    -- timer, so `mooi idle` writes its file from this (and the machine suspends half an hour after).
    { path = "lock.idle", kind = "integer", default = 30, min = 1, max = 60 },
    -- D160: what the lock screen's backdrop does with the wallpaper — how far it is blurred behind
    -- the plate, and how far it is dimmed (a share of the ground painted over it), so the clock and
    -- the field read over any picture. The lock scene's own (shell/mooi-lock, copied in at each lock).
    { path = "lock.blur", kind = "enum", values = { "off", "light", "medium", "heavy" }, default = "medium" },
    { path = "lock.dim", kind = "integer", default = 72, min = 0, max = 90 },
    -- whether the lock screen wears the Nexus's two pictures, each on its own switch: its banner
    -- across the top, and the profile picture on its plate above the clock. Both on by default; off
    -- is a screen that says less about whose it is, which is what some rooms want.
    { path = "lock.banner", kind = "boolean", default = true },
    { path = "lock.avatar", kind = "boolean", default = true },
    { path = "command.max_results", kind = "integer", default = 7, min = 3, max = 10 },
    { path = "atlas.previews", kind = "boolean", default = true },
    -- The tray's icons: drawn in the bar's own colours (and their own on hover), or as given.
    { path = "tray.style", kind = "enum", values = { "themed", "original" }, default = "themed" },
    -- Your apps in mooi's palette (bin/mooi apps-sync): each off leaves the app as it was.
    { path = "apps.kitty", kind = "boolean", default = false },
    { path = "apps.gtk", kind = "boolean", default = false },
    { path = "apps.qt", kind = "boolean", default = false },
    -- Nautilus's own layer on top of apps.gtk: its CSS classes (path bar, Places, selection) and
    -- Papirus's folders recoloured to the palette. Off leaves the file manager as GTK gives it.
    { path = "apps.files", kind = "boolean", default = true },
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
    -- Hyprland 0.57's blur variants: glass, acrylic, water, aurora and more on top of the blur
    { path = "desktop.blur_variant", kind = "enum", values = { "keep", "none", "glass", "acrylic", "water", "ripple", "aurora", "haze", "heat_shimmer", "drops", "fluid_jar" }, default = "keep" },
    -- D157: going from one workspace to the next. How the windows travel (`column` is niri's: the
    -- workspaces stacked top to bottom; `tide` is mooi's own: the new one rises in as the old
    -- dissolves where it stands), how the move feels (`spring` is niri's critically damped spring,
    -- `bounce` overshoots a little), how long (tenths of a second, 0 keeps Hyprland's own), and
    -- how a touchpad swipe carries (`flick`: a quick flick goes over and may carry on past one).
    { path = "desktop.ws_style", kind = "enum", values = { "keep", "slide", "column", "glide", "fade", "tide" }, default = "keep" },
    { path = "desktop.ws_feel", kind = "enum", values = { "keep", "ease", "spring", "bounce" }, default = "keep" },
    { path = "desktop.ws_speed", kind = "integer", default = 0, min = 0, max = 12 },
    { path = "desktop.ws_swipe", kind = "enum", values = { "keep", "flick", "steady" }, default = "keep" },
    -- Kitty's own custom shaders (kitty ≥ 0.49, the `custom_shaders` option): mooi writes a small
    -- include beside the settings and points kitty.conf at it, then asks kitty to read its config
    -- again. The value names a pipeline kitty ships with, `mooi-crt` (kitty's crt tinted with a
    -- colour from the bar's palette, rendered from palette.json), or — `custom` — a pipeline of
    -- your own, kept as the path kitty itself understands (absolute, or under ~/.config/kitty/shaders/).
    { path = "desktop.kitty_shader_on", kind = "boolean", default = false },
    { path = "desktop.kitty_shader", kind = "enum",
      values = { "crt", "mooi-crt", "crt-blue", "tft", "dim-inactive-windows", "inside-the-matrix", "cursor-trail-motion-blur", "custom" },
      default = "crt" },
    -- Which of the palette's colours does the tinting: a role from palette.json, `primary` by
    -- default (the accent the bar wears), or a neutral for a colder glass. A role the palette
    -- does not carry falls back to `primary`.
    { path = "desktop.kitty_shader_colour", kind = "enum",
      values = { "primary", "secondary", "tertiary", "on_surface", "on_surface_variant", "outline",
                 "outline_variant", "surface_container_lowest", "surface_container_low",
                 "surface_container", "surface_container_high", "surface_dim", "error" },
      default = "primary" },
    -- How much of that colour is laid over the picture: 0 is kitty's own crt, 100 the full tint.
    { path = "desktop.kitty_shader_tint", kind = "integer", default = 55, min = 0, max = 100 },
    { path = "desktop.kitty_shader_custom", kind = "text", max = 200, default = "" },
    -- D158: the workspaces' shader transition. One switch and one choice in one: `off` is the
    -- switch, and naming a kind is what turns it on. Hyprland's screen shader (lib/wsfx writes it,
    -- bin/mooi ws-fx applies it at each workspace change) runs for the length of that move and is
    -- put back after; a screen shader of your own — hyprshade's and the like — is never replaced.
    { path = "desktop.ws_fx", kind = "enum", values = { "off", "channel", "circuit", "stretch", "halftone", "board", "sigil" }, default = "off" },
    -- how long that transition runs, as a share of its own length (100 is as designed); both the
    -- shader's clock and the length `mooi ws-fx` holds it for are stretched, so they cannot drift
    { path = "desktop.ws_fx_speed", kind = "integer", default = 100, min = 50, max = 200 },
    -- The windows' own half of that: each opens and closes as a screen does, one shot per window.
    -- Off is Hyprland's own animation; naming a pair is the switch, and lib/wfx writes both shaders
    -- (in the palette) plus the two window rules in front of them. It plays only where the
    -- HyprWindowShade plugin is loaded — without it the rules are names nothing reads, and the
    -- windows animate exactly as Hyprland says.
    { path = "desktop.window_fx", kind = "enum", values = { "off", "phosphor", "glitch", "iris" }, default = "off" },
    -- how long that pair runs, as a share of its own lengths (100 is as designed)
    { path = "desktop.window_fx_speed", kind = "integer", default = 100, min = 50, max = 200 },
    -- and whether a terminal and a browser keep a pair of their own (lib/wfx `APPS`)
    { path = "desktop.window_fx_apps", kind = "boolean", default = true },
    -- The light both shader families are drawn in (lib/fxpal): the bar's own palette, so the switch
    -- and the windows follow the wallpaper; the wallpaper's own Matugen scheme (`matugen`: its
    -- primary, tertiary and secondary as Matugen wrote them, before lib/ferro re-lights the bar);
    -- three colours of your own (`custom`, below); or one of a few fixed ways. `palette` is the default.
    { path = "desktop.fx_light", kind = "enum", values = { "palette", "phosphor", "amber", "ice", "magenta", "mono", "custom", "matugen" }, default = "palette" },
    -- the `custom` way's three colours, as #rrggbb: the light, its second signal, and the ground the
    -- shader's marks stand on. Any colour; one that is not a colour falls back to mooi's phosphor.
    { path = "desktop.fx_phos", kind = "colour", default = "#7fcfb6" },
    { path = "desktop.fx_ember", kind = "colour", default = "#e07b2e" },
    { path = "desktop.fx_trace", kind = "colour", default = "#3d6a60" },
    -- D157: the scrolling layout as niri's columns: the widths a column steps through, the tape
    -- following focus, focus wrapping round the ends, and niri's keys for the columns.
    { path = "desktop.column_widths", kind = "enum", values = { "keep", "niri", "halves", "quarters" }, default = "keep" },
    { path = "desktop.column_follow", kind = "enum", values = { "keep", "on", "off" }, default = "keep" },
    { path = "desktop.column_wrap", kind = "enum", values = { "keep", "on", "off" }, default = "keep" },
    { path = "desktop.column_keys", kind = "boolean", default = false },
    -- mooi's keys: "SUPER + ALT + Space" and the like (Hyprland's own spelling). Bound live
    -- and by custom/mooi.lua at Hyprland's start.
    { path = "keys.search", kind = "key", default = "SUPER + ALT + Space" },
    { path = "keys.window", kind = "key", default = "SUPER + ALT + W" },
    { path = "keys.stop", kind = "key", default = "SUPER + ALT + SHIFT + Space" },
    -- D226: the node's keys (Super+Space was ArchEclipse's float toggle; Super+Tab the Overview's)
    { path = "keys.node_launch", kind = "key", default = "SUPER + space" },
    { path = "keys.node_universe", kind = "key", default = "SUPER + Tab" },
    { path = "keys.node_time", kind = "key", default = "SUPER + T" },
    { path = "keys.node_keys", kind = "key", default = "SUPER + K" },
    { path = "keys.surface", kind = "key", default = "SUPER + ALT + U" },   -- D271: the Subsurface's Overview
    { path = "keys.drawer_left", kind = "key", default = "SUPER + D" },      -- D275: the Dashboard drawer
    { path = "keys.drawer_right", kind = "key", default = "SUPER + N" },     -- D275: the notices drawer
    { path = "keys.arcade", kind = "key", default = "SUPER + G" },           -- D276: the arcade
    { path = "keys.dock", kind = "key", default = "SUPER + SHIFT + D" },     -- D280: the dock held up
    { path = "dock.on", kind = "boolean", default = true },
    { path = "dock.empty", kind = "boolean", default = false },
    { path = "drawers.on", kind = "boolean", default = true },
    { path = "drawers.dashboard", kind = "boolean", default = true },
    { path = "drawers.notices", kind = "boolean", default = true },
    { path = "drawers.edge", kind = "boolean", default = false },
    { path = "drawers.github", kind = "boolean", default = true },
    { path = "drawers.quote", kind = "boolean", default = true },   -- D267: the shortcut sheet
    { path = "keys.settings", kind = "key", default = "SUPER + ALT + S" },
    -- D160: the lock screen at once. The session also locks itself after `lock.idle` minutes
    -- (hypridle, Settings → Lock); this is the key for when you are leaving now.
    { path = "keys.lock", kind = "key", default = "SUPER + L" },
    { path = "keys.edit", kind = "key", default = "SUPER + ALT + E" },
    { path = "keys.system", kind = "key", default = "SUPER + ALT + C" },
    { path = "keys.shutter", kind = "key", default = "SUPER + ALT + D" },
    { path = "keys.wallpaper", kind = "key", default = "SUPER + ALT + P" },
    { path = "keys.player", kind = "key", default = "SUPER + ALT + M" },
    { path = "keys.desk", kind = "key", default = "SUPER + ALT + G" },
    -- Who receives the session's notifications: mooi while it runs as the desktop (`desktop`: under
    -- the keeper, not a bare `mooi run`), `always`, or `never`. `takeover` before D134.
    { path = "notifications.server", kind = "enum", values = { "desktop", "always", "never" }, default = "desktop" },
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
    -- mooi as the whole desktop (D48). With ArchEclipse uninstalled it is always on and no longer in
    -- Settings (D134); custom/mooi.lua still reads it, so restoring ArchEclipse means setting it false
    -- in settings.json by hand (docs/SWITCHING.md).
    { path = "session.standalone", kind = "boolean", default = true },
    -- A touchpad swipe down to open it (D45): off, or with three or four fingers.
    { path = "atlas.gesture", kind = "enum", values = { "off", "three", "four" }, default = "off" },
    -- Retired with Hyprdrive (D118): mooi's Overview is the only one. Kept in the schema so its
    -- settings code does not move; nothing reads it, and the migration drops it from files.
    { path = "atlas.engine", kind = "enum", values = { "mooi" }, default = "mooi" },
    -- The ported overview (docs/OVERVIEW-PORT.md): the wheel over the grid (and ← →) steps the
    -- desktops, and typing lists installed apps under the search row to start with Enter.
    { path = "atlas.wheel_desktops", kind = "boolean", default = true },
    { path = "atlas.search_apps", kind = "boolean", default = true },
    { path = "atlas.search_files", kind = "boolean", default = true },
    -- The hot corner (OVERVIEW-PORT stage 3): rest the pointer in a corner to open it. Off by
    -- default; while on, a 6×6 surface takes that corner's clicks (the price of the corner).
    { path = "atlas.hot_corner", kind = "enum", values = { "off", "top-left", "top-right", "bottom-left", "bottom-right" }, default = "off" },
    { path = "atlas.hot_corner_delay", kind = "integer", default = 600, min = 200, max = 1500 },
    -- Spring edges (OVERVIEW-PORT, D115): carry a window into the left or right edge of the
    -- Overview and hold; the desktops step, and the window lands on the one you stop at.
    { path = "atlas.spring_edges", kind = "boolean", default = true },
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
    -- D209: how the shared BMO sees and behaves. `eyes` follows the pointer; `cheek` is a bounded
    -- tone (Off/Tease/Flirty/Unfiltered), never explicit; `hands` gates what he may do unasked.
    { path = "companion.eyes", kind = "boolean", default = true },
    { path = "companion.cheek", kind = "enum", values = { "Off", "Tease", "Flirty", "Unfiltered" }, default = "Tease" },
    { path = "companion.hands", kind = "enum", values = { "Off", "Look", "Balanced", "Trusted" }, default = "Balanced" },
    { path = "companion.react.herdr", kind = "boolean", default = true },
    { path = "companion.react.browser", kind = "boolean", default = true },
    -- D210: Herdr's agents in the bar. `poll` is seconds between snapshots (2–10).
    { path = "herdr.path", kind = "string", default = "herdr" },
    { path = "herdr.poll", kind = "integer", default = 3, min = 2, max = 10 },
    { path = "herdr.show_idle", kind = "boolean", default = false },
    { path = "herdr.show_done", kind = "boolean", default = false },
    { path = "herdr.brief", kind = "boolean", default = true },
    { path = "herdr.brief_lines", kind = "integer", default = 4, min = 2, max = 8 },
    { path = "herdr.focus_on_open", kind = "boolean", default = false },
    -- D219: Live wallpaper — the picture itself moves, round the widgets below or all of it; four effects, each
    -- with its strength, size and blend (lib/surface/skin `live`)
    -- D226: the Dynamic Pill as a living node (docs/superpowers/specs/2026-11-09-dynamic-pill-node-design.md §9):
    -- what it may unfold, how it moves and answers the pointer, where it sits — intent, not implementation
    { path = "node.on", kind = "boolean", default = true },
    { path = "node.personality", kind = "enum", values = { "organic", "minimal", "technical", "cyber" }, default = "organic" },
    { path = "node.pointer", kind = "enum", values = { "off", "low", "normal", "high" }, default = "normal" },
    { path = "node.anchor", kind = "enum", values = { "left", "centre", "right" }, default = "centre" },
    { path = "node.media", kind = "boolean", default = true },
    { path = "node.notices", kind = "boolean", default = true },
    { path = "node.workspaces", kind = "boolean", default = true },
    { path = "node.volume", kind = "boolean", default = true },
    { path = "node.system", kind = "boolean", default = true },
    { path = "node.wallpaper", kind = "boolean", default = true },
    { path = "node.privacy", kind = "boolean", default = true },   -- D232: the microphone and the camera
    { path = "node.lyrics", kind = "boolean", default = false },   -- D240: the player's words from LRCLIB (asks the internet)
    { path = "live.on", kind = "boolean", default = true },
    { path = "live.where", kind = "enum", values = { "widgets", "whole" }, default = "widgets" },
    { path = "live.speed", kind = "integer", default = 100, min = 50, max = 200 },
    { path = "live.ripple.on", kind = "boolean", default = true },
    { path = "live.ripple.strength", kind = "integer", default = 60, min = 0, max = 100 },
    { path = "live.ripple.size", kind = "integer", default = 50, min = 0, max = 100 },
    { path = "live.ripple.blend", kind = "integer", default = 50, min = 0, max = 100 },
    { path = "live.breathe.on", kind = "boolean", default = true },
    { path = "live.breathe.strength", kind = "integer", default = 40, min = 0, max = 100 },
    { path = "live.breathe.size", kind = "integer", default = 50, min = 0, max = 100 },
    { path = "live.breathe.blend", kind = "integer", default = 60, min = 0, max = 100 },
    { path = "live.flow.on", kind = "boolean", default = false },
    { path = "live.flow.strength", kind = "integer", default = 30, min = 0, max = 100 },
    { path = "live.flow.size", kind = "integer", default = 50, min = 0, max = 100 },
    { path = "live.flow.blend", kind = "integer", default = 70, min = 0, max = 100 },
    { path = "live.sweep.on", kind = "boolean", default = true },
    { path = "live.sweep.strength", kind = "integer", default = 60, min = 0, max = 100 },
    { path = "live.sweep.size", kind = "integer", default = 50, min = 0, max = 100 },
    { path = "live.sweep.blend", kind = "integer", default = 50, min = 0, max = 100 },
    -- D223: Music in the picture — strips of the wallpaper pulled up out of it by the music
    { path = "live.music.on", kind = "boolean", default = true },
    { path = "live.music.strength", kind = "integer", default = 70, min = 0, max = 100 },
    { path = "live.music.size", kind = "integer", default = 50, min = 0, max = 100 },
    { path = "live.music.blend", kind = "integer", default = 40, min = 0, max = 100 },
    { path = "live.music.height", kind = "integer", default = 25, min = 5, max = 80 },
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
    -- Retired with the wallpaper studio (D118): nothing reads these now. They stay in the schema
    -- so a settings file that carries them still validates, and settings codes do not move.
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
    -- one row of cards, or two (down a side that is two columns); the profile card small or large;
    -- the music on the deck's edge
    { path = "nexus.rows", kind = "integer", default = 1, min = 1, max = 2 },
    { path = "nexus.profile", kind = "enum", values = { "small", "large" }, default = "small" },
    { path = "nexus.visualiser", kind = "boolean", default = true },
    -- how many bars the deck's open border is cut into (the notches' faces carry their own share)
    { path = "nexus.bars", kind = "enum", values = { "eight", "twelve", "sixteen", "twentyfour" }, default = "sixteen" },
    { path = "nexus.notches", kind = "boolean", default = true },
    -- each card's size along a strip, as "id_s" / "id_l" (medium is not listed)
    { path = "nexus.sizes", kind = "ids", max = 12 },
    -- D119: with two rows the deck is a free canvas; each card's place and size there, as
    -- "c<n>_<x>_<y>_<w>_<h>" in thousandths of the canvas (lib/nexusdeck clean_canvas)
    { path = "nexus.canvas", kind = "ids", max = 12 },
    -- The desk (D85, lib/desk): mooi draws the wallpaper so it can travel, and lays Lumen's
    -- cutout over the desktop widgets.
    { path = "desk.on", kind = "boolean", default = false },
    { path = "desk.parallax", kind = "enum", values = { "off", "workspaces", "pointer", "both" }, default = "workspaces" },
    { path = "desk.strength", kind = "integer", default = 45, min = 0, max = 100 },
    { path = "desk.cutout", kind = "boolean", default = true },
    { path = "desk.depth", kind = "boolean", default = true },
    -- how a new picture comes in (D144): random, a circle growing (from the notch when
    -- picked there), a wipe, a slide, or a fade
    { path = "desk.transition", kind = "enum", values = { "random", "grow", "wipe", "slide", "fade" }, default = "random" },
    -- D145/D147: the wallpapers — where they are, the picker's defaults and look (shell/mooi-walls)
    { path = "walls.folders", kind = "paths", max = 8, default = { "~/Pictures/wallpapers", "~/Pictures/livewalls" } },
    { path = "walls.view", kind = "enum", values = { "strip", "orbit", "circuit" }, default = "strip" },
    { path = "walls.source", kind = "enum", values = { "all", "pictures", "live", "wallhaven" }, default = "all" },
    -- how long the desk's transition takes: 0.5 s, 0.95 s, 1.6 s (before the motion speed)
    { path = "walls.speed", kind = "enum", values = { "quick", "normal", "slow" }, default = "normal" },
    { path = "walls.veil", kind = "integer", default = 93, min = 50, max = 100 },
    { path = "walls.slant", kind = "integer", default = 22, min = 0, max = 40 },
    { path = "walls.cards", kind = "enum", values = { "small", "medium", "large" }, default = "medium" },
    { path = "walls.dots", kind = "integer", default = 5, min = 2, max = 10 },
    { path = "walls.swell", kind = "integer", default = 16, min = 6, max = 24 },
    -- the auto-change: a new wallpaper every so many minutes, from a source (or the colour chosen
    -- last in the picker), held while a window is fullscreen
    { path = "walls.auto", kind = "boolean", default = false },
    { path = "walls.auto_every", kind = "integer", default = 30, min = 5, max = 240 },
    { path = "walls.auto_from", kind = "enum", values = { "all", "pictures", "live", "colour", "wallhaven" }, default = "pictures" },
    { path = "walls.auto_fullscreen", kind = "boolean", default = true },
    -- Wallhaven (wallhaven.cc) in the picker: what its searches ask for. Sketchy and NSFW need an API
    -- key, kept in mooi's data folder as wallhaven.key (0600), with ~/.config/mooi/wallhaven.key as a
    -- fallback (audit 2026-11-06, G13); never in the settings
    { path = "wallhaven.categories", kind = "enum", values = { "general", "anime", "people", "general+anime", "general+people", "anime+people", "all" }, default = "general+anime" },
    { path = "wallhaven.purity", kind = "enum", values = { "sfw", "sfw+sketchy", "sketchy", "nsfw", "all" }, default = "sfw" },
    { path = "wallhaven.sorting", kind = "enum", values = { "toplist", "hot", "latest", "random" }, default = "toplist" },
    { path = "wallhaven.range", kind = "enum", values = { "1d", "3d", "1w", "1M", "3M", "6M", "1y" }, default = "1M" },
    { path = "wallhaven.atleast", kind = "enum", values = { "screen", "4k", "any" }, default = "screen" },
    { path = "wallhaven.ratio", kind = "enum", values = { "screen", "any" }, default = "screen" },
    -- D137: the desktop widgets (shell/mooi-widgets, widgets.json is theirs)
    { path = "widgets.on", kind = "boolean", default = true },
    -- D139: widgets behind the wallpaper's subject, and the wallpaper's mood in how they move
    { path = "widgets.depth", kind = "boolean", default = true },
    { path = "widgets.mood", kind = "boolean", default = true },
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
    -- D166: each module's (or group's, on its first module) own look; "style" is the bar's own
    local base = "bar.modules." .. id
    M.SCHEMA[#M.SCHEMA + 1] = { path = base .. ".colour", kind = "modcolour", default = "style" }
    M.SCHEMA[#M.SCHEMA + 1] = { path = base .. ".fill", kind = "enum", values = { "style", "solid", "tinted", "glass", "none" }, default = "style" }
    M.SCHEMA[#M.SCHEMA + 1] = { path = base .. ".rounding", kind = "enum", values = { "style", "square", "soft", "round", "pill" }, default = "style" }
    M.SCHEMA[#M.SCHEMA + 1] = { path = base .. ".outline", kind = "enum", values = { "style", "none", "accent" }, default = "style" }
    M.SCHEMA[#M.SCHEMA + 1] = { path = base .. ".glow", kind = "enum", values = { "off", "soft", "strong" }, default = "off" }
    M.SCHEMA[#M.SCHEMA + 1] = { path = base .. ".display", kind = "enum", values = { "icon", "icon+value", "label+value" }, default = "icon+value" }
    M.SCHEMA[#M.SCHEMA + 1] = { path = base .. ".width", kind = "enum", values = { "fit", "fixed" }, default = "fit" }
end

-- The palette roles a module's colour may name (lib/ferro's ROLES; listed here so config needs no ferro)
local MODCOLOUR_ROLES = { ground = true, hull = true, hull_raised = true, well = true, trace_dim = true, trace = true,
    trace_lit = true, phos = true, phos_fill = true, ember = true, ember_fill = true, flare = true, muted = true, ink = true,
    steel_900 = true, steel_700 = true, steel_500 = true, steel_300 = true, engrave = true }

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
        -- An empty string is "unset" for an enum that allows it (claude.model: pass no --model at
        -- all), so it becomes the default rather than a problem reported on every load (audit
        -- 2026-10-29).
        if value == "" and row.empty then return true, nil, row.default end
        local known = false
        for _, allowed in ipairs(row.values) do if value == allowed then known = true end end
        if not known then return false, "expected one of " .. table.concat(row.values, ", ") end
    elseif row.kind == "modcolour" then
        local ok = type(value) == "string" and (value == "style" or value == "wallpaper" or MODCOLOUR_ROLES[value]
            or string.match(value, "^#%x%x%x%x%x%x$") ~= nil)
        if not ok then return false, "expected style, wallpaper, a palette role or a colour like #e07b2e" end
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
            if row.allowed then
                local ok = false
                for _, a in ipairs(row.allowed) do if a == id then ok = true end end
                if not ok then return false, "expected only " .. table.concat(row.allowed, ", ") end
            end
        end
    elseif row.kind == "paths" then
        if type(value) ~= "table" then return false, "expected a list of folders" end
        if #value > (row.max or 8) then return false, "expected at most " .. tostring(row.max or 8) .. " folders" end
        for _, f in ipairs(value) do
            if type(f) ~= "string" or #f > 240 or string.find(f, "[%c]") or not (f:sub(1, 1) == "/" or f:sub(1, 2) == "~/") then
                return false, "expected folders like \"~/Pictures/wallpapers\""
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
    -- D118: the Mission shape and Hyprdrive's engine are gone; a file that chose them gets the grid
    -- and mooi's own Overview, quietly (they were choices, not mistakes).
    if type(t.atlas) == "table" then
        if t.atlas.overview == "mission" then t.atlas.overview = "grid" end
        if t.atlas.engine == "hyprdrive" then t.atlas.engine = "mooi" end
    end
    -- D119: the spine and the Nexus's Cascade (its shelves all out at once) are gone: the deck
    if type(t.nexus) == "table" and t.nexus.mode == "cascade" then t.nexus.mode = "deck" end
    -- D134: there is no takeover any more; mooi as the desktop is what it meant
    if type(t.notifications) == "table" and t.notifications.server == "takeover" then t.notifications.server = "desktop" end
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
               and k ~= "rows" and k ~= "profile" and k ~= "visualiser" and k ~= "bars"
               and k ~= "notches" and k ~= "sizes" and k ~= "canvas" then t.nexus[k] = nil end
        end
    end
    -- D227: the classic Pill and the Sigil are gone (the node is the Pill, D226): of their settings only whether
    -- the side groups show beside it (pill.sides) is read; the rest goes quietly rather than as unknown settings
    if type(t.pill) == "table" then t.pill = { sides = t.pill.sides } end
    t.sigil = nil
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
    -- D166: the Steel style is gone; a file on it reads as Instrument, every finer value it set kept
    -- (surface mech, accent outline, …), so the bar looks the same until something is changed
    if type(t.bar) == "table" and t.bar.style == "steel" then
        t.bar.style = "instrument"
        notes[#notes + 1] = "bar.style: steel is no longer a style; now instrument, with its finer settings kept"
    end
    if t.version ~= nil and t.version ~= M.VERSION then
        notes[#notes + 1] = string.format("settings say version %s, this mooi reads %d", tostring(t.version), M.VERSION)
    end
    -- A whole section of the wrong type (a hand edit, a truncated write) used to vanish without a
    -- word, every setting in it silently back to its default (audit 2026-11-01, A1). A wrong leaf
    -- was always reported; now a wrong section is too.
    local known = known_paths()
    local sections = {}
    for path in pairs(known.sections) do sections[#sections + 1] = path end
    table.sort(sections)
    for _, path in ipairs(sections) do
        local value = get(t, path)
        if value ~= nil and type(value) ~= "table" then
            problems[#problems + 1] = string.format("%s: expected a group of settings, got %s; using the defaults", path, type(value))
        end
    end
    for _, row in ipairs(M.SCHEMA) do
        local value = get(t, row.path)
        if value ~= nil then
            local ok, why, fixed = check(row, value)
            if ok then
                set(out, row.path, fixed ~= nil and fixed or value)
            else
                problems[#problems + 1] = string.format("%s: %s, got %s; using %s",
                    row.path, why, tostring(value), (type(row.default) == "table") and "the default" or tostring(row.default))
            end
        end
    end
    -- The bar's Outline (bar.edge) is one choice shown in Settings, but what is drawn is bar.frame
    -- and bar.outline_width (lib/style.apply_edge writes all three). A preset or a theme profile that
    -- set the pair without the choice left Settings saying "Bold" over a bar drawn with none; the pair
    -- is the truth, so the choice is derived from it on every load.
    do
        local fr, ow = get(out, "bar.frame"), get(out, "bar.outline_width")
        local edge = fr == "none" and "none" or fr == "corners" and "corners"
            or ({ "thin", "regular", "bold" })[tonumber(ow) or 2] or "regular"
        if get(t, "bar.edge") ~= nil and get(t, "bar.edge") ~= edge then
            notes[#notes + 1] = "bar.edge: " .. tostring(get(t, "bar.edge")) .. " did not match the drawn outline; now " .. edge
        end
        set(out, "bar.edge", edge)
    end
    -- D112: the bar's foot switch was the first rim. A file that predates music.rim keeps its
    -- answer; a file that has the master is never overridden by the old key.
    local master = get(t, "music.rim")
    local legacy = get(t, "bar.foot_visualizer")
    if master == nil and legacy ~= nil then
        if type(legacy) == "boolean" then
            set(out, "music.rim", legacy)
            notes[#notes + 1] = "music.rim: read from bar.foot_visualizer"
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
    unknown_keys(t, "", known, unknown)
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
