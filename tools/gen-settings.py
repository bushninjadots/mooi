#!/usr/bin/env python3
"""Generates mooi's settings window (shell/mooi-settings.plm, a program of its own) from the
spec below: the sections, their rows, and each row's control. Every control sends
`set_value(1000 · code + value)`; the codes are lib/setters.luau's SETTERS (1-based) and
100 + n / 200 + n for module n's show / frame. Also rewrites edit mode's per-module grips
between the `// <gen:edit>` markers in shell/mooi.plm.

  tools/gen-settings.py
"""
import re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCENE = ROOT / "shell" / "mooi.plm"

SETTERS = [
    "bar.mode", "bar.surface", "bar.frame", "bar.ground", "bar.rail", "bar.accents",
    "bar.workspaces", "bar.helix_frame", "bar.labels", "bar.wheel", "spine.max_workspaces",
    "media.mode", "media.idle", "bar.visualizer",
    "frame.on", "frame.band", "frame.music", "frame.style", "frame.reach", "frame.edges",
    "theme.source", "theme.color_index", "theme.scheme", "theme.signal", "theme.contrast",
    "tray.style", "notifications.server", "atlas.previews", "island.confirm_close",
    "desktop.manage", "desktop.border", "desktop.border_colour", "desktop.gaps_in",
    "desktop.gaps_out", "desktop.rounding", "desktop.dim_inactive",
    "bar.radius", "bar.outline_width", "bar.outline_colour", "bar.pill", "bar.shadow", "bar.opacity",
    "bar.frost", "bar.smoke", "bar.bg", "bar.bg_light", "bar.bg_sat", "bar.bg_hue",
    "fx.aberration", "fx.glow", "theme.finish", "theme.saturation",
    "desktop.layout", "desktop.column", "desktop.column_fit", "desktop.touchpad_natural",
    "desktop.touchpad_speed", "desktop.mouse_natural", "desktop.mouse_speed", "desktop.blur",
    "desktop.opacity_active", "desktop.opacity_inactive", "desktop.shadow", "desktop.shadow_size",
    "bar.style", "theme.preset",
    "motion.reduced", "island.follow_on_send", "command.max_results",
    "bar.width", "bar.edge", "frame.motion", "frame.radius", "frame.edge", "frame.opacity",
    "bar.height", "bar.offset",
    "apps.kitty", "apps.gtk", "apps.qt",
    "motion.speed", "motion.saver", "power.profile",
    "notifications.dnd", "notifications.quiet_from", "notifications.quiet_to",
    "shutter.enabled", "shutter.pointer", "shutter.edge", "shutter.density", "shutter.preview",
    "shutter.arrange", "shutter.workspace", "shutter.behaviour", "shutter.connections",
    "atlas.rows", "atlas.columns", "atlas.super_tab", "atlas.overview",
    "atlas.private", "atlas.size", "atlas.dim", "atlas.zoom", "atlas.refresh",
    "atlas.gesture", "session.standalone",
    "signals.edge", "signals.max", "signals.linger", "signals.grouping", "signals.density",
    "signals.chamfer", "signals.travel", "signals.effects", "signals.private",
    "wallpaper.matte", "wallpaper.backdrop", "wallpaper.key", "wallpaper.fuzz",
    "desk.on", "desk.parallax", "desk.strength", "desk.depth", "desk.cutout",
    "theme.mode", "theme.light_at", "theme.dark_at", "apps.others",
    "look.corners", "look.corner_size",
    "companion.bmo", "companion.size", "companion.place", "companion.above", "companion.variant",
    "companion.wander", "companion.motion", "companion.throw", "companion.locked", "companion.talk",
    "companion.music", "companion.clock", "companion.react.notes", "companion.react.spaces",
    "companion.react.battery", "companion.react.focus", "companion.react.time",
    "island.style", "clock.view", "shelves.on",
    # Hyprland 0.56: finer blur, the windows' spring and motion blur
    "desktop.blur_vibrancy", "desktop.blur_xray", "desktop.blur_popups", "desktop.wobble", "desktop.motion_blur",
    # the Control Nexus (D102): what the mark opens, and the deck's edge
    "nexus.mode", "nexus.edge", "shelves.autohide",
    # Hyprland 0.57, the Nexus's cards, the notch, Claude
    "desktop.blur_variant", "nexus.rows", "nexus.profile", "nexus.visualiser", "notch.on",
    "nexus.notches", "claude.model",
    # the bar's islands' feet as the visualiser
    "bar.foot_visualizer",
    # music on every mooi edge: the master, its strength and the halo
    "music.rim", "music.rim_gain", "music.rim_glow",
    # how many bars the Control Nexus deck's border is cut into
    "nexus.bars",
    # retired (D118): which Overview opened; mooi's is the only one
    "atlas.engine",
    # the Overview's wheel/key desktop stepping and type-to-run apps
    "atlas.wheel_desktops", "atlas.search_apps", "atlas.search_files",
    "atlas.hot_corner", "atlas.hot_corner_delay",
    # spring edges: a carried window held at an edge steps the desktops (D115)
    "atlas.spring_edges",
    # the desktop widgets (D137)
    "widgets.on", "widgets.depth", "widgets.mood",
    # D144's transition (it sat in the middle of this list for a day, shifting every code after it:
    # appended here, and the list is now checked against lib/setters.luau on every run, D147)
    "desk.transition",
    # the wallpapers (D147): the picker, its look, Wallhaven, the auto-change
    "walls.view", "walls.source", "walls.speed", "walls.veil", "walls.slant", "walls.cards",
    "walls.dots", "walls.swell", "wallhaven.categories", "wallhaven.purity", "wallhaven.sorting",
    "wallhaven.range", "wallhaven.atleast", "wallhaven.ratio", "walls.auto", "walls.auto_every",
    "walls.auto_from", "walls.auto_fullscreen",
    # D152/D153: the islands grown out of the bar (frame.islands for an hour, the same slot)
    "island.morph",
    # D157: the workspaces' transition and the scrolling layout as niri's columns
    "desktop.ws_style", "desktop.ws_feel", "desktop.ws_speed", "desktop.ws_swipe",
    "desktop.column_widths", "desktop.column_follow", "desktop.column_wrap", "desktop.column_keys",
    # D161: how long the session may sit idle before the lock screen takes it (`mooi idle`)
    "lock.idle",
    # D158: the workspaces' shader transition (appended, so no code moved)
    "desktop.ws_fx",
    # and the windows' own opening and closing (lib/wfx), appended for the same reason: the pair,
    # how long it runs, and whether terminals and browsers keep one of their own
    "desktop.window_fx", "desktop.window_fx_speed", "desktop.window_fx_apps",
    # the shaders' own length and light, for both families (lib/wsfx, lib/wfx, lib/fxpal)
    "desktop.ws_fx_speed", "desktop.fx_light",
    # the three colours the `custom` light is drawn in (typed as hex, so their codes set nothing;
    # they are listed so a page's Reset names them)
    "desktop.fx_phos", "desktop.fx_ember", "desktop.fx_trace",
    # D160: the lock screen's key, beside the idle timeout that locks on its own (lock.idle)
    "keys.lock",
    # and the lock's backdrop, its blur and its dimming
    "lock.blur", "lock.dim",
    # and whether the Nexus's pictures are worn on the lock: the banner strip and the profile picture,
    # each on its own switch
    "lock.banner", "lock.avatar",
    # Nautilus's own layer on top of GTK (apps.files): its CSS classes and Papirus's folders
    # recoloured to the palette. Appended, so no code moved.
    "apps.files",
    # D159: kitty's own custom shaders (kitty >= 0.49): the switch, which pipeline, and the pipeline
    # of your own that `custom` wears. Appended, so no code moved; `mooi kitty-shaders` writes it.
    "desktop.kitty_shader_on", "desktop.kitty_shader", "desktop.kitty_shader_custom",
    "desktop.kitty_shader_tint", "desktop.kitty_shader_colour",
    # whether a free model may answer when Claude cannot (claude.free_fallback). Appended, so no code moved.
    "claude.free_fallback",
    # D166: how much each module shows, and whether islands attach to the frame. Appended, so no code moved.
    "bar.density", "frame.islands",
    # D168: the Pill — with the side groups, two at once, moons at most. Appended, so no code moved.
    "pill.sides", "pill.multi", "pill.moons",
    # D169: the Pill's face and hiding when idle. Appended, so no code moved.
    "pill.face", "pill.autohide",
    # D170: the board's pads. Appended, so no code moved. (D202: its music visualiser went with Cue.)
    "pill.pads",
    # D171: the Pill's shape, views, detail and rest. Appended, so no code moved.
    "pill.shape", "pill.views", "pill.detail", "pill.rest",
    # D172: what it does when it is idle. Appended, so no code moved.
    "pill.hide",
    # D174: the Pill's pointer warmth and its ping on a change (its own visual page). Appended.
    "pill.warmth", "pill.ping",
    # D175: the desk on the board's first card — its tiles, its surface, its edge. Appended.
    "pill.desk_clock", "pill.desk_playing", "pill.desk_diagnostics", "pill.desk_calendar",
    "pill.desk_surface", "pill.desk_border",
    # D176: the desk as the workspace viewer (live miniatures). Appended.
    "pill.desk_workspaces",
    # D177: the desk's sizes and its look (form, tint, glow). Appended.
    "pill.desk_clock_size", "pill.desk_playing_size", "pill.desk_diagnostics_size", "pill.desk_calendar_size",
    "pill.desk_form", "pill.desk_tint", "pill.desk_glow",
    # D179: what the right button does. Appended.
    "pill.right",
    # D186: the board's look — a wash over the bar's own plate, and the edge it wears. Appended.
    "pill.board_tint", "pill.board_edge",
    # D188: the peek. Appended, so no code moved.
    "pill.peek",
    # D194: Loom / Fold's operating mode. Appended, so no code moved.
    "loom.mode",
    # D195: Fold, Accordions, and the edge the strips stand on. Appended.
    "loom.fold", "loom.accordions", "loom.edge",
    # D195: the Accordion keys. Appended.
    "keys.loom_add", "keys.loom_next", "keys.loom_prev", "keys.loom_fold", "keys.loom_open", "keys.loom_remove",
    # D197: Cubes, and their two keys. Appended.
    "loom.cubes", "keys.loom_cube", "keys.loom_join",
    # D200: Loom, its threads, and its four keys. Appended.
    "loom.loom", "loom.threads", "keys.loom_link", "keys.loom_flow", "keys.loom_hop", "keys.loom_unlink",
    # D205: a second and a third pill — each a face, and where it sits. Appended.
    "pill.two", "pill.two_at", "pill.three", "pill.three_at",
    # D207: the Sigil. Appended.
    "sigil.pill", "sigil.temperament", "sigil.colour", "sigil.fixed", "sigil.field", "sigil.pointer", "sigil.rest",
]
# codes 100 + n and 200 + n are the modules' show and frame, so settings past the 99th go on from
# 300 (lib/setters `apply` reads them back the same way)
def code(path):
    i = SETTERS.index(path) + 1
    return i if i < 100 else i + 200

MODULES = ["workspaces", "window", "media", "resources", "bandwidth", "keyboard", "weather", "tray",
           "notifications", "mic", "volume", "brightness", "battery", "network", "bluetooth", "clock",
           "caffeine", "recorder", "screenshot", "clipboard", "power", "actions", "overview", "core", "focus", "settings",
           "notes", "wallpaper", "nexus", "updates", "claude", "github",
           "sigil"]   # D207: lib/barlayout.ORDER's last
NAMES = {"workspaces": "Workspaces", "window": "Window title", "media": "Media player", "resources": "Resources",
         "bandwidth": "Bandwidth", "keyboard": "Keyboard layout", "weather": "Weather", "tray": "Tray",
         "notifications": "Notifications", "mic": "Microphone", "volume": "Volume", "brightness": "Brightness",
         "battery": "Battery", "network": "Network", "bluetooth": "Bluetooth", "clock": "Clock",
         "caffeine": "Keep awake", "recorder": "Screen recorder", "screenshot": "Screenshot",
         "clipboard": "Clipboard", "power": "Session", "actions": "Window actions", "overview": "Overview", "core": "Search", "focus": "Focus timer", "settings": "Settings",
         "notes": "Quick notes", "wallpaper": "Wallpapers", "nexus": "Control Nexus", "updates": "System updates", "sigil": "Sigil",
         "claude": "Claude", "github": "GitHub"}
KEYS = [("search", "Search", "Open search (starts mooi if it is not running)"),
        ("window", "Window actions", "Float, pin, fullscreen or close the focused window"),
        ("overview", "Overview", "Every workspace zoomed out (Super+Tab too, below in System)"),
        ("system", "System controls", "Volume, brightness, network, Bluetooth"),
        ("shutter", "Window shutter", "The focused window's controls, unfolding from its edge"),
        ("settings", "Settings", "This window"),
        ("wallpaper", "Wallpapers", "Opens the wallpaper picker: the strip and the colour orbit"),
        ("player", "Music player", "Your library, the queue and lyrics on a turntable"),
        ("desk", "Desk mode", "The desktop widgets gathered over the desktop, or back where they were"),
        ("mode", "Light or dark", "Turn the whole desktop to the other mode now"),
        ("edit", "Edit the bar", "Move, group and hide the bar's modules"),
        ("lock", "Lock screen", "mooi's own lock at once; the session also locks itself after the minutes in Settings → Lock"),
        ("loom_add", "Accordion: add", "The focused window joins your Accordion (Loom / Fold, Hybrid or full mode)"),
        ("loom_next", "Accordion: next", "The next layer out; the one you were using goes back in"),
        ("loom_prev", "Accordion: previous", "The previous layer out"),
        ("loom_fold", "Accordion: fold", "Every layer back in, or the last one out again"),
        ("loom_open", "Accordion: open all", "Every layer out on this workspace, tiled"),
        ("loom_remove", "Accordion: take out", "The focused window leaves its Accordion and stays"),
        ("loom_cube", "Make a Cube", "Every window on this workspace folded into one Cube (the focused one on its front)"),
        ("loom_join", "Join the Cube", "The focused window joins the last Cube's facing side"),
        ("loom_link", "Link windows", "Press on one window, then on another: they are connected"),
        ("loom_flow", "Link as a workflow", "The same, as a step: hopping goes forward along it first"),
        ("loom_hop", "Hop along a link", "To the next window connected to this one, wherever it is"),
        ("loom_unlink", "Unlink the window", "Every connection of the focused window let go"),
        ("stop", "Stop mooi", "Back to ArchEclipse")]

SCHEMES = [("Balanced", 0), ("Faithful", 1), ("Expressive", 2), ("True to image", 3), ("Playful", 4),
           ("Monochrome", 5), ("Muted", 6), ("Rainbow", 7), ("Vibrant", 8), ("Automatic", 9)]

# A page: (rail label, title, what it is for, rail group, rows). A row:
#   ("card", "Name"[, when])         starts a titled card; the rows after it are in it
#   ("note", when, "TEXT")           an ember line, shown while `when` holds
#   (kind, title, description, path, current-value expression, options[, applies-when])
#   ("slider", title, description, path, lo, hi, shown[, applies-when])
#   ("button", title, description, label, event, n)
#   ("schemes",) · ("keys",) · ("layout",)
# Every row with a setting gets its revert arrow (shown while the setting is not its default),
# and every page its Reset (two presses: the first arms it).
SWITCHERS = [("Pills", 3), ("Segments", 4), ("Dots", 5), ("Numbers", 6)]
INSTRUMENTS = [("DNA", 0), ("Prisms", 1), ("Grid", 2), ("Compass", 7), ("Radar", 8)]
LOOKS = [("Phosphor", 0), ("Neon noir", 1), ("Concrete", 2), ("Gunmetal", 3), ("Alien", 4), ("Titanium", 5)]
STYLES = [("Instrument", 0), ("Glass", 1), ("Floating", 2), ("Hairline", 3), ("Minimal", 4)]
SECTIONS = [
    ("Quick", "Quick settings", "The few choices that change the most; every other page holds the rest", "LOOK", [
        ("card", "Look"),
        ("choice", "Look", "A finished palette: base, finish and light together", "theme.preset", "sv_theme_preset", LOOKS),
        ("note", "sv_theme_preset > 5.5", "CUSTOM — CHANGED ON THE COLOUR PAGE"),
        ("choice", "Colours from", "Your wallpaper, or mooi's own teal and orange", "theme.source", "theme_wallpaper", ["mooi default", "Wallpaper"]),
        ("toggle", "Parallax desk", "The wallpaper travels with your workspaces (mooi always draws it)", "desk.on", "sv_desk_on"),
        ("card", "Bar"),
        ("toggle", "Morph", "Islands grow out of the bar as one body with it", "island.morph", "sv_island_morph"),

        ("choice", "Shape", "Islands, one bar across the screen, pieces hanging from the top, or the Pill", "bar.mode", "sv_bar_mode", ["Islands", "Full bar", "Notch", "Pill"]),
        ("choice", "Style", "Machined plates, see-through, lifted, a thin line round each, or no plates at all", "bar.style", "sv_bar_style", STYLES),
        ("note", "sv_bar_style > 4.5", "CUSTOM — CHANGED ON THE BAR PAGE"),
        ("slider", "Thickness", "How tall the bar is", "bar.height", 24, 44, "{sv_bar_height + 24, 0} px"),
        ("button", "The bar and the frame", "Shape, style, frame, every module's place and look", "Open Bar & Frame", "set_pick", "Bar & Frame"),
        ("card", "Workspaces"),
        ("choice", "Switcher", "Everyday", "bar.workspaces", "ws_style", SWITCHERS),
        ("choice", "", "…or an instrument", "bar.workspaces", "ws_style", INSTRUMENTS),
    ]),
    ("Theme & colour", "Theme & colour", "One palette for everything mooi draws: the bar, its islands and panels, your window borders", "LOOK", [
        ("card", "The login screen"),
        ("info", "What it wears", "greetd runs sysc-greet, in this palette: `mooi greet-theme` writes the theme it follows (D190)", "gr_theme"),
        ("card", "Day and night"),
        ("choice", "Mode", "Dark, light, or light by day and dark by night; the bar, mooi's windows and your apps all turn", "theme.mode", "sv_theme_mode", [("Dark", 0), ("Light", 1), ("Auto", 2)]),
        ("slider", "Light from", "The hour it turns light", "theme.light_at", 0, 23, "{sv_theme_light_at, 0}:00", "sv_theme_mode == 2"),
        ("slider", "Dark from", "The hour it turns dark", "theme.dark_at", 0, 23, "{sv_theme_dark_at, 0}:00", "sv_theme_mode == 2"),
        ("card", "Shape"),
        ("choice", "Corners", "Every plate mooi draws: Ferrolume's two cut corners, all four cut, rounded or square", "look.corners", "sv_look_corners", [("Chamfer", 0), ("Bevel", 1), ("Rounded", 2), ("Square", 3)]),
        ("slider", "Corner size", "How big the cut or the rounding is (12 is as designed)", "look.corner_size", 0, 24, "{sv_look_corner_size, 0}", "sv_look_corners != 3"),
        ("card", "Palette"),
        ("choice", "Look", "A finished palette: base, finish and light together", "theme.preset", "sv_theme_preset", LOOKS),
        ("choice", "Colours from", "Your wallpaper, or mooi's own teal and orange", "theme.source", "theme_wallpaper", ["mooi default", "Wallpaper"]),
        ("source", "Start from", "Which of the wallpaper's main colours leads", "theme.color_index", "th_index", None, "theme_wallpaper"),
        ("schemes",),
        ("choice", "Second colour", "The highlight: picked for you, or the main colour's opposite, neighbour or third", "theme.signal", "th_signal",
         [("Auto", 0), ("Opposite", 3), ("Neighbour", 4), ("Triad", 5)]),
        ("card", "Light"),
        ("choice", "Finish", "Matte is calm, Luminous glows, Neon burns", "theme.finish", "sv_theme_finish", [("Matte", 1), ("Luminous", 0), ("Neon", 2)]),
        ("slider", "Colourfulness", "The whole palette's colour, down or up", "theme.saturation", -50, 50, "{sv_theme_saturation - 50, 0}"),
        ("card", "Base"),
        ("choice", "Base", "What everything stands on; text stays readable on any", "bar.bg", "sv_bar_bg",
         [("Black", 0), ("Wallpaper", 1), ("Main colour", 2), ("Custom", 9)]),
        ("choice", "", "…or an industrial material", "bar.bg", "sv_bar_bg",
         [("Obsidian", 10), ("Gunmetal", 11), ("Concrete", 12), ("Titanium", 13), ("Oxide", 14), ("Alien", 15)]),
        ("colourpick",),
        ("slider", "Lightness", "Darker or lighter than the base", "bar.bg_light", -10, 40, "{sv_bar_bg_light - 10, 0}", "sv_bar_bg > 0.5 and sv_bar_bg != 9"),
        ("slider", "Saturation", "From grey to richer than the base", "bar.bg_sat", 0, 150, "{sv_bar_bg_sat, 0}%", "sv_bar_bg > 0.5 and sv_bar_bg != 9"),
        ("slider", "Hue", "Turn the base round the colour wheel", "bar.bg_hue", -180, 180, "{sv_bar_bg_hue - 180, 0}°", "sv_bar_bg > 0.5 and sv_bar_bg != 9"),
        ("card", "Your apps"),
        ("note", "true", "OFF, AN APP KEEPS ITS OWN COLOURS (YOUR MATUGEN SETUP); ON, IT WEARS THIS PALETTE"),
        ("toggle", "Kitty terminal", "Text, selection, cursor and the 16 terminal colours", "apps.kitty", "sv_apps_kitty"),
        ("toggle", "GTK apps", "GTK 3 and 4 (libadwaita), light or dark with mooi; open windows change when reopened", "apps.gtk", "sv_apps_gtk"),
        ("toggle", "Files (Nautilus)", "Its path bar, Places list and file selection in the palette, and Papirus's folder icons recoloured to match; off leaves Nautilus as GTK gives it", "apps.files", "sv_apps_files"),
        ("toggle", "Qt and KDE apps", "Through qt6ct and KDE's colours (Dolphin, Kate…), light or dark; apps change when reopened", "apps.qt", "sv_apps_qt"),
        ("toggle", "Everything else", "Your own Matugen templates (btop, fish, cava, Vesktop, Zen, Spotify, widgets) in mooi's mode", "apps.others", "sv_apps_others"),
    ]),
    ("Motion", "Motion & effects", "How fast things move, what glows, and what goes quiet to save the battery", "LOOK", [
        ("card", "Motion"),
        ("slider", "Speed", "Every animation, slower or faster; the bar restarts (a second) to take it", "motion.speed", 50, 200, "{sv_motion_speed + 50, 0}%"),
        ("toggle", "Reduce motion", "No springs or travel: things are simply there; the bar restarts to take it", "motion.reduced", "sv_motion_reduced"),
        ("card", "Effects"),
        ("slider", "Glow", "How strongly lit things glow", "fx.glow", 0, 160, "{sv_fx_glow, 0}%"),
        ("slider", "Chromatic aberration", "Glass edges and readings split red from cyan", "fx.aberration", 0, 100, "{sv_fx_aberration, 0}%"),
        ("card", "Battery saver"),
        ("choice", "Saver", "Glow, aberration, the frame's music and the visualizer off", "motion.saver", "sv_motion_saver", ["Off", "On battery", "Always"]),
        ("note", "saving", "SAVING NOW"),
    ]),
    ("Bar & Frame", "Bar & Frame", "Everything about the bar and the frame round the screen: four choices here, every detail folded below", "BAR", [
        ("card", "Choose"),
        ("choice", "Shape", "Islands, one bar across the screen, pieces hanging from the top, or the Pill", "bar.mode", "sv_bar_mode", ["Islands", "Full bar", "Notch", "Pill"]),
        ("choice", "Style", "Machined plates, see-through, lifted, a thin line round each, or no plates at all", "bar.style", "sv_bar_style", STYLES),
        ("note", "sv_bar_style > 4.5", "CUSTOM — CHOOSE A STYLE TO START AGAIN"),
        ("toggle", "Screen frame", "A band round the screen that the bar is part of; it can move with the music", "frame.on", "frame_on"),
        ("fold", "Edges & outline", "OUTLINE · COLOUR · CORNERS · ROUNDING · DETAILS"),
        ("card", "Edges"),
        ("choice", "Outline", "None, corner marks, or a line", "bar.edge", "sv_bar_edge", ["None", "Corners", "Thin", "Regular", "Bold"]),
        ("choice", "Outline colour", "A quiet line, a bright one, or the main colour", "bar.outline_colour", "sv_bar_outline_colour", ["Subtle", "Bright", "Accent"], "sv_bar_edge > 0.5"),
        ("slider", "Corner rounding", "The bar, the notch and the islands", "bar.radius", 0, 16, "{sv_bar_radius, 0} px"),
        ("toggle", "Details", "Cuts in the outline, ticks, the comet and the seconds", "bar.accents", "bar_accents"),
        ("fold", "Surface & depth", "MATERIAL · TRANSPARENCY · FROST · SHADOW · HOVER"),
        ("card", "Surface"),
        ("choice", "Surface", "What the plates are: solid, glass, frosted, none, or machined metal", "bar.surface", "bar_surface", ["Solid", "Glass", "Frosted", "None", "Machined"]),
        ("slider", "Transparency", "How much of the desktop shows through", "bar.opacity", 20, 100, "{100 - (sv_bar_opacity + 20), 0}%", "bar_surface < 2.5"),
        ("slider", "Frosting", "How frosted the glass is", "bar.frost", 0, 100, "{sv_bar_frost, 0}%", "bar_surface > 0.5 and bar_surface < 1.5"),
        ("slider", "Tint", "How much the glass darkens what is behind", "bar.smoke", 0, 80, "{sv_bar_smoke, 0}%", "bar_surface > 0.5 and bar_surface < 2.5"),
        ("choice", "Shadow", "Lifts the bar off the desktop", "bar.shadow", "sv_bar_shadow", ["Off", "Soft", "Medium", "Strong"], "bar_surface < 2.5 or bar_surface > 3.5"),
        ("choice", "Hover", "What lights under the pointer", "bar.pill", "sv_bar_pill", ["Soft", "Outline", "Underline", "Glow"]),
        ("fold", "Frame & music", "BAND · CORNERS · EDGE · ISLANDS · SWELL"),
        ("card", "Frame", "not frame_on or not dk_manage"),
        ("note", "not frame_on", "TURN THE SCREEN FRAME ON ABOVE FOR ITS BAND, CORNERS, EDGE AND MUSIC"),
        ("note", "frame_on and not dk_manage", "IT LIES IN THE WINDOWS' OUTER GAP: TURN ON LET MOOI STYLE WINDOWS SO THE GAP FITS IT"),
        ("card", "Band", "frame_on"),
        ("slider", "Band thickness", "How wide the band is", "frame.band", 2, 16, "{sv_frame_band + 2, 0} px"),
        ("slider", "Frame corners", "How round its inner corners are", "frame.radius", 0, 40, "{sv_frame_radius, 0} px"),
        ("choice", "Frame edge", "The frame's line: plain, neon, or none (a style without an outline has none either)", "frame.edge", "sv_frame_edge", ["Line", "Neon", "None"]),
        ("choice", "Islands with the frame", "Float under the band with a little air, or hang from it as one body", "frame.islands", "sv_frame_islands", ["Float", "Attach"], "not bar_full and not st_notch"),
        ("card", "Music", "frame_on"),
        ("choice", "Moves with music", "Still, or its inner edge rolling with the bass (iNiR's frame music)", "frame.motion", "sv_frame_motion", ["Off", "Wave"]),
        ("slider", "Strength", "How far it moves at full volume", "frame.reach", 6, 40, "{sv_frame_reach + 6, 0} px", "frame_music"),
        ("choice", "Which edges", "All of them, the sides, or top and bottom", "frame.edges", "frame_edges", ["All", "Sides", "Top & bottom"], "frame_music"),
        ("fold", "Size & place", "THICKNESS · DISTANCE · LENGTH · RAIL · ISLANDS"),
        ("card", "Size"),
        ("slider", "Thickness", "How tall the bar is", "bar.height", 24, 44, "{sv_bar_height + 24, 0} px"),
        ("slider", "From the edge", "How far down from the top of the screen it sits", "bar.offset", 0, 40, "{sv_bar_offset, 0} px"),
        ("slider", "Length", "How much of the screen's width it spans, centred", "bar.width", 30, 100, "{sv_bar_width + 30, 0}%"),
        ("toggle", "Info rail", "The thin scale line above the bar", "bar.rail", "bar_rail", None, "not st_notch"),
        ("choice", "Clock shows", "The time and date, the time, or the seconds too (a right press on it cycles them)", "clock.view", "sv_clock_view", ["Time and date", "Time", "Seconds"]),
        ("card", "Islands"),
        ("toggle", "Morph", "An island grows out of its module as one body with the bar (and the Control Nexus out of the screen's edge), with the screen frame or without it", "island.morph", "sv_island_morph"),
        ("choice", "Island panels", "Without Morph: Ferrolume plates, or slabs tethered to their module", "island.style", "sv_island_style", [("Plate", 0), ("Tether", 1)]),
        ("fold", "Modules", "ORDER · GROUPS · EACH MODULE'S LOOK · WORKSPACES · MEDIA"),
        ("layout",),
        ("card", "Switcher"),
        ("choice", "Everyday", "Pills, segments that show apps, dots or numbers", "bar.workspaces", "ws_style", SWITCHERS),
        ("choice", "Instrument", "The helix, prisms, grid, a compass or a radar", "bar.workspaces", "ws_style", INSTRUMENTS),
        ("toggle", "Helix forms the island", "The island's own edges twist into the strands", "bar.helix_frame", "helix_frame", None,
         "ws_style < 0.5 and not bar_full and not st_notch"),
        ("toggle", "Numbers", "Each occupied workspace's number", "bar.labels", "bar_labels", None, "ws_style < 2.5"),
        ("card", "Behaviour"),
        ("choice", "Mouse wheel", "Scrolling over the switcher", "bar.wheel", "sv_bar_wheel", [("Changes workspace", 0), ("Inverted", 2), ("Does nothing", 1)]),
        ("slider", "Always shown", "How many it shows at least; it grows to reach the one you are on", "spine.max_workspaces", 1, 16, "{sv_spine_max_workspaces + 1, 0}"),
    
        ("card", "Player"),
        ("choice", "Shows", "How much of the player is on the bar", "media.mode", "media_mode", ["Everything", "Controls", "Cover", "Visualizer"]),
        ("choice", "When nothing plays", "Shrink to a note, stay, or leave the bar", "media.idle", "media_idle", ["Shrink", "Stay", "Hide"]),
        ("choice", "Visualizer", "Moves with the sound", "bar.visualizer", "viz", ["Mirror", "Bars", "Line", "Dots", "Off"], "media_mode != 2"),
    
        ("fold", "The Pill", "ONE CAPSULE THAT BECOMES WHAT IS HAPPENING"),
        # D188: one control for each thing. The face, the wheel's views, the pads and the board's music
        # are edited on the Pill itself (one button); the desk's tiles are one Off · Small · Wide each,
        # under a picture of the desk; the record shape is gone (it was the attached capsule since D187).
        ("card", "At a glance"),
        ("note", "sv_bar_mode != 3", "CHOOSE SHAPE → PILL ABOVE TO SEE IT"),
        ("pillstage",),
        ("card", "Shape"),
        ("pillshapes",),
        ("card", "When idle"),
        ("pillhide",),
        ("card", "Behaviour"),
        ("toggle", "Peek on hover", "Rest the pointer on the Pill and it grows in place into two rows: the song, throughput, controls and clock; weather, the machine, battery, brightness, volume and network. A press on one opens its room, anywhere else the whole board", "pill.peek", "sv_pill_peek"),
        ("toggle", "Flash on a change", "The Pill's edge lights for a moment when the workspace changes or a notice arrives", "pill.ping", "sv_pill_ping"),
        ("slider", "Pointer warmth", "A soft light behind the capsule as the pointer comes near (0: none)", "pill.warmth", 0, 100, "{sv_pill_warmth, 0}%"),
        ("choice", "Right press", "What a right press on the Pill does", "pill.right", "sv_pill_right", ["Calendar", "Board", "Notes", "Settings", "Nothing"]),
        ("card", "What it shows"),
        ("button", "Face, wheel and pads", "Its face at rest, what the wheel turns through, the pads", "Edit on the Pill", "pill_board_edit", 1),
        ("choice", "Detail", "How much each view shows: its icon, a word or two, or more", "pill.detail", "sv_pill_detail", ["Icon", "Brief", "Full"]),
        ("slider", "Back to its face after", "A view the wheel turned to returns to the face after this long (0: it stays)", "pill.rest", 0, 60, "{sv_pill_rest, 0} s"),
        ("choice", "Side groups", "The left and right groups as islands beside the Pill, or the Pill alone", "pill.sides", "sv_pill_sides", ["Show", "Hide"]),
        ("choice", "Two at once", "Moons beside it, the Pill split in two, or pads on traces", "pill.multi", "sv_pill_multi", ["Moons", "Split", "Nodes"]),
        ("slider", "Moons at most", "How many things wait beside the Pill", "pill.moons", 1, 4, "{sv_pill_moons + 1, 0}"),
        # D207: the Sigil, beside the classic Pill until the owner switches (sigil.fixed is file-only for now)
        ("fold", "The Sigil", "ONE LIVING LINE IN PLACE OF THE PILL"),
        ("card", "The Sigil"),
        ("choice", "In the Pill", "The classic Pill, or the Sigil: one living line that becomes what is happening", "sigil.pill", "sv_sigil_pill", ["Classic", "Sigil"]),
        ("choice", "Temperament", "How much it moves: settled, alive, or restless", "sigil.temperament", "sv_sigil_temperament", ["Calm", "Lively", "Restless"]),
        ("choice", "Colour", "The wallpaper's, the song's and the warnings' colours, or one of your own", "sigil.colour", "sv_sigil_colour", ["Follow", "Fixed"]),
        ("choice", "At rest", "What it shows when nothing is happening", "sigil.rest", "sv_sigil_rest", [("Clock", 0), ("Song", 3), ("Weather", 2), ("Machine", 8), ("Battery", 9), ("Spaces", 6), ("BMO", 12)]),
        ("choice", "Your pointer", "Near it, the line moves away, leans toward it, or ignores it", "sigil.pointer", "sv_sigil_pointer", ["Pushes", "Draws", "Ignores"]),
        ("toggle", "The field", "A field of points behind its displays, warmed by your pointer", "sigil.field", "sv_sigil_field"),
        # D205: a second and a third pill, each a face at rest and a place of its own (the rest of the
        # faces — BMO, the Nexus, network, signals, the visualiser — are there by the file, pill.two/three)
        ("card", "More pills"),
        ("choice", "Second pill", "A capsule of its own showing one thing; a press opens its room, the wheel turns its view", "pill.two", "sv_pill_two", [("Off", 0), ("Time", 1), ("Song", 6), ("Weather", 4), ("Machine", 5), ("Battery", 7), ("Spaces", 8)]),
        ("slider", "Where", "Across the screen (0: beside the Pill, on its left); it never covers anything", "pill.two_at", 0, 100, 'pick(sv_pill_two_at > 0, "BESIDE THE PILL", "{sv_pill_two_at, 0}%")'),
        ("choice", "Third pill", "Another, on the Pill's right unless you place it", "pill.three", "sv_pill_three", [("Off", 0), ("Time", 1), ("Song", 6), ("Weather", 4), ("Machine", 5), ("Battery", 7), ("Spaces", 8)]),
        ("slider", "Where", "Across the screen (0: beside the Pill, on its right)", "pill.three_at", 0, 100, 'pick(sv_pill_three_at > 0, "BESIDE THE PILL", "{sv_pill_three_at, 0}%")'),
        ("card", "What may take it"),
        ("pillorder",),
        ("card", "The desk"),
        ("note", "true", "THE BOARD'S FIRST CARD"),
        ("deskstage",),
        ("toggle", "Live workspaces instead", "Each workspace's windows, live, in place of the tiles", "pill.desk_workspaces", "sv_pill_desk_workspaces"),
        ("choice", "The time", "The clock, the date and the week", "pill.desk_clock_size", "sv_pill_desk_clock_size", [("Off", 2), ("Small", 0), ("Wide", 1)]),
        ("choice", "The song", "The cover, the title and how far it has come", "pill.desk_playing_size", "sv_pill_desk_playing_size", [("Off", 2), ("Small", 0), ("Wide", 1)]),
        ("choice", "The machine", "The processor, the memory and the temperature", "pill.desk_diagnostics_size", "sv_pill_desk_diagnostics_size", [("Off", 2), ("Small", 0), ("Wide", 1)]),
        ("choice", "The week", "Seven days in a row, today lit", "pill.desk_calendar_size", "sv_pill_desk_calendar_size", [("Off", 2), ("Small", 0), ("Wide", 1)]),
        ("choice", "Form", "Flat tiles, or the opened vial: the capsule parted, the tiles inside", "pill.desk_form", "sv_pill_desk_form", ["Tiles", "Opened vial"]),
        ("choice", "Surface", "A plate, glass, or a slab tethered to the core", "pill.desk_surface", "sv_pill_desk_surface", ["Plate", "Glass", "Tether"]),
        ("choice", "Tiles' edge", "A hairline, a cut corner, or none", "pill.desk_border", "sv_pill_desk_border", ["Hairline", "Cut", "None"]),
        ("choice", "Tint", "The wallpaper's colours, the accent's, or the ink's", "pill.desk_tint", "sv_pill_desk_tint", ["Wallpaper", "Accent", "Mono"]),
        ("choice", "Glow", "None, a soft halo, or a bright one", "pill.desk_glow", "sv_pill_desk_glow", ["None", "Soft", "Bright"]),
        ("card", "The board's look"),
        ("note", "true", "THE BOARD IS THE BAR'S OWN MATERIAL — ITS OPACITY, FROST, BLUR AND RADIUS COME FROM BAR & FRAME"),
        ("choice", "A wash over it", "The plate as it is, a phosphor glow over it, or the accent's", "pill.board_tint", "sv_pill_board_tint", ["None", "Phosphor", "Accent"]),
        ("choice", "Its edge", "The frame's own edge, a lit hairline round it, or none", "pill.board_edge", "sv_pill_board_edge", ["Theme", "Hairline", "None"]),
    ]),
    ("Windows", "Windows", "Hyprland's windows, styled by mooi so they match. A slider's lowest step keeps your own", "DESKTOP", [
        ("card", "Styling"),
        ("toggle", "Let mooi style windows", "Off: your Hyprland config decides everything here and in Input", "desktop.manage", "dk_manage"),
        ("note", "not dk_manage", "TURN THIS ON TO SET BORDERS, GAPS, OPACITY, SHADOWS, BLUR AND TILING"),
        ("card", "Edges", "dk_manage"),
        ("slider", "Border width", "The outline round each window", "desktop.border", 0, 8, "{sv_desktop_border, 0} px"),
        ("choice", "Border colour", "The palette's two colours, its main one, or Hyprland's", "desktop.border_colour", "dk_colour", ["Palette", "Main colour", "Keep mine"]),
        ("slider", "Corners", "How round the windows are", "desktop.rounding", 0, 24, "{sv_desktop_rounding, 0} px"),
        ("card", "Spacing", "dk_manage"),
        ("slider", "Between windows", "The gap between tiled windows", "desktop.gaps_in", 0, 20, "{sv_desktop_gaps_in, 0} px"),
        ("slider", "At the edges", "The gap round the outside; wider while the screen frame is on", "desktop.gaps_out", 0, 40, "{sv_desktop_gaps_out, 0} px"),
        ("card", "Depth", "dk_manage"),
        ("slider", "Opacity, focused", "The window you are using", "desktop.opacity_active", 49, 100,
         'pick(sv_desktop_opacity_active == 0, "{sv_desktop_opacity_active + 49, 0}%", "KEEP")'),
        ("slider", "Opacity, others", "Every other window", "desktop.opacity_inactive", 49, 100,
         'pick(sv_desktop_opacity_inactive == 0, "{sv_desktop_opacity_inactive + 49, 0}%", "KEEP")'),
        ("choice", "Shadow", "Dark and soft, deep, or a neon glow", "desktop.shadow", "sv_desktop_shadow", ["Keep mine", "Off", "Soft", "Deep", "Neon"]),
        ("slider", "Shadow size", "How far the shadow reaches", "desktop.shadow_size", 2, 40, "{sv_desktop_shadow_size + 2, 0} px", "sv_desktop_shadow > 1.5"),
        ("choice", "Blur", "Behind see-through windows and Frosted bars", "desktop.blur", "sv_desktop_blur", ["Keep mine", "Off", "Light", "Medium", "Heavy"]),
        ("slider", "Blur vibrancy", "How much the colours behind are saturated", "desktop.blur_vibrancy", 0, 100,
         'pick(sv_desktop_blur_vibrancy == 0, "{sv_desktop_blur_vibrancy, 0}%", "KEEP")', "sv_desktop_blur != 1"),
        ("choice", "Floating see-through", "On: a floating window blurs the wallpaper, not the windows under it", "desktop.blur_xray", "sv_desktop_blur_xray", ["Keep mine", "On", "Off"], "sv_desktop_blur != 1"),
        ("choice", "Blur menus", "Right-click menus and popups blurred behind", "desktop.blur_popups", "sv_desktop_blur_popups", ["Keep mine", "On", "Off"], "sv_desktop_blur != 1"),
        ("choice", "Blur finish", "Hyprland 0.57: a material over the blur", "desktop.blur_variant", "sv_desktop_blur_variant",
         [("Keep mine", 0), ("Plain", 1), ("Glass", 2), ("Acrylic", 3), ("Water", 4)], "sv_desktop_blur != 1"),
        ("choice", "", "…or another still one", "desktop.blur_variant", "sv_desktop_blur_variant", [("Ripple", 5), ("Haze", 7), ("Fluid jar", 10)], "sv_desktop_blur != 1"),
        # measured (D131): these three animate, so Hyprland redraws every frame even when nothing moves
        ("choice", "", "…or a moving one: Hyprland redraws all the time (~25–70 % of the GPU, idle)", "desktop.blur_variant", "sv_desktop_blur_variant", [("Aurora", 6), ("Heat", 8), ("Drops", 9)], "sv_desktop_blur != 1"),
        ("toggle", "Dim the others", "Shade every window but the one you are using", "desktop.dim_inactive", "dk_dim"),
        ("card", "Motion", "dk_manage"),
        ("choice", "Wobble", "Windows bend as you drag them (Hyprland 0.57) and bounce as they open and move", "desktop.wobble", "sv_desktop_wobble", ["Keep mine", "Off", "Subtle", "Wobbly", "Jelly"]),
        ("choice", "Motion blur", "Smears a window while it is moved or resized", "desktop.motion_blur", "sv_desktop_motion_blur", ["Keep mine", "Off", "Soft", "Strong"]),
        # D157: going from one workspace to the next, and a swipe's carry
        ("card", "Workspaces", "dk_manage"),
        ("choice", "Transition", "How the windows travel to the next workspace", "desktop.ws_style", "sv_desktop_ws_style",
         [("Keep mine", 0), ("Slide", 1), ("Column", 2), ("Glide", 3)]),
        ("choice", "", "…Column is niri's, the workspaces stacked; Tide is mooi's own, the next one rising as this one dissolves", "desktop.ws_style", "sv_desktop_ws_style", [("Fade", 4), ("Tide", 5)]),
        ("choice", "Feel", "Spring is niri's: quick, no overshoot. Bounce overshoots a little", "desktop.ws_feel", "sv_desktop_ws_feel", ["Keep mine", "Ease", "Spring", "Bounce"], "sv_desktop_ws_style != 0"),
        ("slider", "Duration", "How long the move takes (a spring sets its own)", "desktop.ws_speed", 0, 12,
         'pick(sv_desktop_ws_speed == 0, "{sv_desktop_ws_speed / 10, 1} s", "KEEP")', "sv_desktop_ws_style != 0 and sv_desktop_ws_feel != 2"),
        ("choice", "Swipe", "Flick: a quick swipe goes over, and a long one carries on past the next", "desktop.ws_swipe", "sv_desktop_ws_swipe", ["Keep mine", "Flick", "Steady"]),
        # the light both shader families are drawn in (lib/fxpal): one choice, so the switch and the
        # windows cannot end up two different colours
        ("card", "Shader colours"),
        ("choice", "The light", "Where the transition and the windows' effects take their colour: the bar's own palette (a new wallpaper re-lights them), or a fixed way of their own", "desktop.fx_light", "sv_desktop_fx_light",
         ["Palette", "Phosphor", "Amber", "Ice", "Magenta", "Mono"]),
        # …and two ways of its own on the second row (as the base's materials): three colours you type,
        # or the wallpaper's own Matugen scheme, before the bar re-lights it
        ("choice", "", "…or your own three colours below, or the wallpaper's own as Matugen read it", "desktop.fx_light",
         "sv_desktop_fx_light", [("Custom", 6), ("Matugen", 7)]),
        ("fxcolour", "First colour", "The light the effect is drawn in, typed as #rrggbb (Custom only)", "desktop.fx_phos", "fxp1", None, "sv_desktop_fx_light == 6"),
        ("fxcolour", "Second colour", "The second signal: rings, sparks, debris", "desktop.fx_ember", "fxp2", None, "sv_desktop_fx_light == 6"),
        ("fxcolour", "Third colour", "The ground the shader's marks stand on", "desktop.fx_trace", "fxp3", None, "sv_desktop_fx_light == 6"),
        # the windows' own opening and closing (HyprWindowShade, lib/wfx): a card of its own, in front
        # of the switch's so it lands where the eye is; off is Hyprland's animation, and a pair plays
        # only where the plugin is loaded
        ("card", "Windows waking"),
        ("choice", "Open and close", "A window's arrival and exit as a shader, in the bar's colours. Off is Hyprland's own animation; a pair plays where the HyprWindowShade plugin is loaded", "desktop.window_fx", "sv_desktop_window_fx",
         ["Off", "Phosphor", "Glitch", "Iris"]),
        ("slider", "How long", "Both halves, against the pair's own timing (a quick flick of the eye either way)", "desktop.window_fx_speed", 50, 200,
         "{sv_desktop_window_fx_speed + 50, 0}%", "sv_desktop_window_fx != 0"),
        ("toggle", "Terminals and browsers differ", "A terminal leaves with the Glitch and a browser arrives with the Iris, whatever the pair above is", "desktop.window_fx_apps", "sv_desktop_window_fx_apps", None,
         "sv_desktop_window_fx != 0"),
        # D158: the shader is the compositor's screen shader, not one of Hyprland's animations, so it
        # has a card of its own and works with mooi styling the windows or not
        ("card", "Shader over the switch"),
        ("choice", "Transition shader", "mooi's own, laid over the switch itself for the length of the move; Off is the switch. It runs while mooi's theme watch does", "desktop.ws_fx", "sv_desktop_ws_fx",
         ["Off", "Channel", "Circuit", "Stretch", "Halftone", "Board", "Sigil"]),
        ("slider", "How long", "The shader's own length, against the kind's timing; the move itself has its Duration above", "desktop.ws_fx_speed", 50, 200,
         "{sv_desktop_ws_fx_speed + 50, 0}%", "sv_desktop_ws_fx != 0"),
        # D159: kitty's own custom shaders. A card of its own, because the conf file mooi writes is
        # kitty's, not the compositor's, and it survives mooi not styling the windows at all.
        ("card", "Kitty screen shaders"),
        ("toggle", "On", "kitty's own custom_shaders (kitty 0.49+): mooi writes a small include into kitty.conf and asks kitty to read its config again", "desktop.kitty_shader_on", "sv_desktop_kitty_shader_on"),
        ("choice", "Shader", "A pipeline kitty ships with. Cursor trails need cursor trails on in kitty.conf first", "desktop.kitty_shader", "sv_desktop_kitty_shader",
         ["CRT", "Mooi CRT", "CRT blue", "Thin-film LCD", "Dim inactive", "Matrix", "Cursor trail", "Mine"]),
        ("choice", "Colour", "Which of the palette's colours tints the glass; a role it lacks falls back to primary",
         "desktop.kitty_shader_colour", "sv_desktop_kitty_shader_colour",
         [("Primary", 0), ("Secondary", 1), ("Tertiary", 2), ("Text", 3), ("Text dim", 4), ("Outline", 5), ("Error", 12)],
         "sv_desktop_kitty_shader == 1"),
        ("choice", "", "…or a neutral one", "desktop.kitty_shader_colour", "sv_desktop_kitty_shader_colour",
         [("Outline dim", 6), ("Panel low", 7), ("Panel", 8), ("Panel mid", 9), ("Panel high", 10), ("Surface", 11)],
         "sv_desktop_kitty_shader == 1"),
        ("slider", "Tint", "How much of that colour is laid over the CRT; 0 is kitty's own picture", "desktop.kitty_shader_tint", 0, 100,
         "{sv_desktop_kitty_shader_tint, 0}%", "sv_desktop_kitty_shader == 1"),
        ("kittyfile", "Your pipeline", "A .pipeline or .slang of your own, chosen by path and read by kitty itself (Mine above)", "desktop.kitty_shader_custom", "set_kitty_shader_file", None,
         "sv_desktop_kitty_shader == 7"),
        ("card", "Tiling", "dk_manage"),
        ("choice", "Layout", "How tiled windows are arranged", "desktop.layout", "sv_desktop_layout", ["Keep mine", "Dwindle", "Master", "Scrolling", "Monocle"]),
        ("slider", "Column width", "Scrolling layout: a new column's width", "desktop.column", 9, 100,
         'pick(sv_desktop_column == 0, "{sv_desktop_column + 9, 0}%", "KEEP")', "sv_desktop_layout == 0 or sv_desktop_layout == 3"),
        ("choice", "Focused column", "Scrolling layout: bring it into view, or centre it", "desktop.column_fit", "sv_desktop_column_fit", ["Keep mine", "Fit", "Centre"],
         "sv_desktop_layout == 0 or sv_desktop_layout == 3"),
        ("choice", "Column widths", "Scrolling layout: the widths Super+] and Super+[ step through", "desktop.column_widths", "sv_desktop_column_widths",
         ["Keep mine", "niri (⅓ ½ ⅔ 1)", "Halves", "Quarters"], "sv_desktop_layout == 0 or sv_desktop_layout == 3"),
        ("choice", "Follow focus", "Scrolling layout: the columns scroll to the window you focus", "desktop.column_follow", "sv_desktop_column_follow", ["Keep mine", "On", "Off"],
         "sv_desktop_layout == 0 or sv_desktop_layout == 3"),
        ("choice", "Wrap focus", "Scrolling layout: past the last column, focus goes round to the first", "desktop.column_wrap", "sv_desktop_column_wrap", ["Keep mine", "On", "Off"],
         "sv_desktop_layout == 0 or sv_desktop_layout == 3"),
        ("toggle", "Column keys", "niri's: Super+] [ widths, Super+= − size, Super+Alt+← → move the column, Super+C fit it", "desktop.column_keys", "sv_desktop_column_keys", None,
         "sv_desktop_layout == 0 or sv_desktop_layout == 3"),
    ]),
    ("Input", "Input", "How the touchpad and the mouse scroll. A speed's lowest step keeps your own", "DESKTOP", [
        ("note", "not dk_manage", "TURN ON LET MOOI STYLE WINDOWS (WINDOWS PAGE) TO SET THESE"),
        ("card", "Touchpad", "dk_manage"),
        ("choice", "Direction", "Natural moves the page with your fingers", "desktop.touchpad_natural", "sv_desktop_touchpad_natural", ["Keep mine", "Natural", "Classic"]),
        ("slider", "Speed", "How far a swipe scrolls", "desktop.touchpad_speed", 4, 200,
         'pick(sv_desktop_touchpad_speed == 0, "{(sv_desktop_touchpad_speed + 4) / 100, 2}×", "KEEP")'),
        ("card", "Mouse", "dk_manage"),
        ("choice", "Direction", "Natural or the wheel's classic direction", "desktop.mouse_natural", "sv_desktop_mouse_natural", ["Keep mine", "Natural", "Classic"]),
        ("slider", "Speed", "How far a notch of the wheel scrolls", "desktop.mouse_speed", 4, 200,
         'pick(sv_desktop_mouse_speed == 0, "{(sv_desktop_mouse_speed + 4) / 100, 2}×", "KEEP")'),
    ]),
    ("Shutter", "Window shutter", "A window's controls unfolding from its edge: Super+Alt+D, or Super+Alt+right-click on a window", "DESKTOP", [
        ("card", "Shutter"),
        ("toggle", "Window shutter", "Arrange, workspace, behaviour and connections, at the window", "shutter.enabled", "sv_shutter_enabled"),
        ("toggle", "Super+Alt+right-click", "Opens it on the window under the pointer (right-click alone stays the app's)", "shutter.pointer", "sv_shutter_pointer", None, "sv_shutter_enabled == 1"),
        ("choice", "Unfolds", "Beside the window where there is room, or always to its left, or inside its edge", "shutter.edge", "sv_shutter_edge", ["Where it fits", "Left", "Inside"], "sv_shutter_enabled == 1"),
        ("choice", "Size", "Standard plates, or compact ones", "shutter.density", "sv_shutter_density", ["Standard", "Compact"], "sv_shutter_enabled == 1"),
        ("toggle", "Open on hover", "A plate held under the pointer opens its panel", "shutter.preview", "sv_shutter_preview", None, "sv_shutter_enabled == 1"),
        ("card", "Plates", "sv_shutter_enabled == 1"),
        ("toggle", "Arrange", "Maximize, fullscreen, centre, size, swap, float", "shutter.arrange", "sv_shutter_arrange"),
        ("toggle", "Workspace", "Move it, follow it, bring it here", "shutter.workspace", "sv_shutter_workspace"),
        ("toggle", "Behaviour", "Floating, pinned, opacity, close", "shutter.behaviour", "sv_shutter_behaviour"),
        ("toggle", "Connections", "Its folder, a terminal there, its repository, its other windows", "shutter.connections", "sv_shutter_connections"),
    ]),
    ("Overview", "Overview", "Super+Tab: every workspace at once — search it, move windows between them, save and restore setups", "DESKTOP", [
        ("card", "Moving around"),
        ("toggle", "Wheel steps desktops", "The wheel over the grid, and ← →, walk the desktops; the Overview stays open on each one", "atlas.wheel_desktops", "sv_atlas_wheel_desktops"),
        ("toggle", "Type to run apps", "Installed apps matching the search appear under the row; Ctrl+↑↓ chooses one, Enter starts it", "atlas.search_apps", "sv_atlas_search_apps"),
        ("toggle", "Search files too", "Documents, Downloads, Desktop and your media folders; bounded, literal, and only while nothing on the board matches", "atlas.search_files", "sv_atlas_search_files"),
        ("toggle", "Spring edges", "Carry a window (or a workspace's nameplate) into an edge and hold: the desktops step, or on the canvas the view pans that way; the window lands where you stop", "atlas.spring_edges", "sv_atlas_spring_edges"),
        ("card", "Opening"),
        ("toggle", "Super+Tab opens it", "Its own key (in Keys) always does", "atlas.super_tab", "sv_atlas_super_tab"),
        ("toggle", "Zoom out of your workspace", "The workspace you are on shrinks into its place; off, the panel just comes down", "atlas.zoom", "sv_atlas_zoom"),
        ("choice", "Touchpad swipe", "Swipe down to open it; down is the one way your desktop's own gestures leave free", "atlas.gesture", "sv_atlas_gesture", ["Off", "3 fingers", "4 fingers"]),
        ("card", "Hot corner"),
        ("choice", "Hot corner", "Rest the pointer in a corner to open it; while on, a 6×6 surface takes that corner's clicks", "atlas.hot_corner", "sv_atlas_hot_corner", ["Off", "Top left", "Top right", "Bottom left", "Bottom right"]),
        ("slider", "Rest for", "How long the pointer must rest there", "atlas.hot_corner_delay", 200, 1500, "{sv_atlas_hot_corner_delay + 200, 0}ms", "sv_atlas_hot_corner != 0"),
        ("card", "Shape"),
        ("choice", "Shape", "A grid; a strip under the bar; or a canvas — pan, zoom, and place each workspace anywhere", "atlas.overview", "sv_atlas_overview", ["Grid", "Strip", "Canvas"]),
        ("slider", "Rows", "How many rows of workspaces", "atlas.rows", 1, 3, "{sv_atlas_rows + 1, 0}", "sv_atlas_overview == 0"),
        ("slider", "Columns", "How many workspaces in a row", "atlas.columns", 2, 6, "{sv_atlas_columns + 2, 0}", "sv_atlas_overview == 0"),
        ("slider", "Size", "Each workspace, as a share of the screen; it shrinks if it would not fit", "atlas.size", 14, 24, "{sv_atlas_size + 14, 0}%", "sv_atlas_overview == 0"),
        ("slider", "Dim behind", "How dark the desktop goes behind it", "atlas.dim", 0, 80, "{sv_atlas_dim, 0}%"),
        ("card", "Window pictures"),
        ("toggle", "Pictures", "Live pictures of windows in the Overview", "atlas.previews", "previews"),
        ("choice", "Taken", "As it opens and after a move (smooth), or every 3 seconds too (a small hitch each time)", "atlas.refresh", "sv_atlas_refresh", ["As it opens", "Every 3 s"], "previews"),
        ("choice", "Privacy", "Password managers and private browsing show no picture or title; or nothing does, for sharing the screen", "atlas.private", "sv_atlas_private",
         ["Off", "Sensitive", "Everything"]),
    ]),
    ("Displays", "Displays", "Your monitors as Hyprland has them (set them in your Hyprland config for now)", "DESKTOP", [
        ("card", "Monitors"),
        ("displays",),
    ]),
    ("Wallpaper", "Wallpapers", "mooi draws the wallpaper: pictures, animated ones and videos. Pick them in the picker (Super+W) or the notch", "DESKTOP", [
        ("card", "The picker"),
        ("button", "The wallpaper picker", "The strip, the colour orbit and the circuit board: every picture and live wallpaper in your folders, and Wallhaven (Super+W)", "Open the picker", "wl_settings_open", 1),
        ("choice", "Opens on", "The view it shows first (it remembers the last one you used)", "walls.view", "sv_walls_view", ["Strip", "Orbit", "Circuit"]),
        ("choice", "Source", "What it lists first", "walls.source", "sv_walls_source", ["All", "Pictures", "Live", "Wallhaven"]),
        ("slider", "Veil", "How dark the desktop goes behind the picker", "walls.veil", 50, 100, "{sv_walls_veil + 50, 0}%"),
        ("slider", "Strip slant", "How far the strip's cards lean", "walls.slant", 0, 40, "{sv_walls_slant, 0}"),
        ("choice", "Strip cards", "How large the strip's cards are", "walls.cards", "sv_walls_cards", ["Small", "Medium", "Large"]),
        ("slider", "Orbit dots", "How large each picture's dot is on the colour orbit", "walls.dots", 2, 10, "{sv_walls_dots + 2, 0} px"),
        ("slider", "Swell", "How many pictures swell into thumbnails under the pointer on the orbit", "walls.swell", 6, 24, "{sv_walls_swell + 6, 0}"),
        ("card", "Folders"),
        ("folders",),
        ("card", "Changing pictures"),
        ("choice", "Transition", "How a new picture comes in; picked in the notch, it grows from the notch (the picker can choose its own)", "desk.transition", "sv_desk_transition",
         ["Random", "Grow", "Wipe", "Slide", "Fade"]),
        ("choice", "Speed", "How long the transition takes (your motion speed scales it too)", "walls.speed", "sv_walls_speed", ["Quick", "Normal", "Slow"]),
        ("card", "Auto-change"),
        ("toggle", "Change by itself", "A new wallpaper every so often", "walls.auto", "sv_walls_auto"),
        ("slider", "Every", "Minutes between changes", "walls.auto_every", 5, 240, "{sv_walls_auto_every + 5, 0} min", "sv_walls_auto == 1"),
        ("choice", "From", "Where the next one comes from: a source, the colour chosen last in the picker, or Wallhaven", "walls.auto_from", "sv_walls_auto_from",
         ["All", "Pictures", "Live", "Colour", "Wallhaven"], "sv_walls_auto == 1"),
        ("toggle", "Hold while fullscreen", "No change while a window is fullscreen", "walls.auto_fullscreen", "sv_walls_auto_fullscreen", "sv_walls_auto == 1"),
        ("card", "Wallhaven"),
        ("choice", "Categories", "What its searches include", "wallhaven.categories", "sv_wallhaven_categories",
         ["General", "Anime", "People", "Gen+Anime", "Gen+People", "Anime+People", "All"]),
        ("choice", "Purity", "Sketchy and NSFW need your API key in ~/.config/mooi/wallhaven.key", "wallhaven.purity", "sv_wallhaven_purity",
         ["SFW", "SFW+Sketchy", "Sketchy", "NSFW", "All"]),
        ("choice", "Sorting", "The list it opens on", "wallhaven.sorting", "sv_wallhaven_sorting", ["Top list", "Hot", "Latest", "Random"]),
        ("choice", "Top list range", "How far back the top list looks", "wallhaven.range", "sv_wallhaven_range", ["1D", "3D", "1W", "1M", "3M", "6M", "1Y"]),
        ("choice", "At least", "The smallest size it lists", "wallhaven.atleast", "sv_wallhaven_atleast", ["Your screen", "4K", "Any"]),
        ("choice", "Ratio", "Only your screen's shape, or any", "wallhaven.ratio", "sv_wallhaven_ratio", ["Your screen", "Any"]),
        ("whkey",),
        ("card", "The desk · parallax"),
        ("toggle", "Parallax desk", "The wallpaper travels with your workspaces or the pointer; off, it stays still (also a tile in Control Nexus)", "desk.on", "sv_desk_on"),
        ("choice", "Moves with", "The workspaces as you switch, the pointer, both, or nothing", "desk.parallax", "sv_desk_parallax",
         ["Still", "Workspaces", "Pointer", "Both"], "sv_desk_on == 1"),
        ("slider", "Strength", "How far the picture travels", "desk.strength", 0, 100, "{sv_desk_strength, 0}%", "sv_desk_on == 1"),
    ]),
    ("Widgets", "Widgets", "Music, clocks, notes, GitHub, weather, a focus timer and more on your desktop. Place them in edit mode", "DESKTOP", [
        ("card", "Desktop widgets"),
        ("toggle", "Desktop widgets", "mooi's own widgets on the desktop, under your windows (D137)", "widgets.on", "sv_widgets_on"),
        ("button", "Arrange on the desktop", "Drag, resize and set each one where it sits (also in Control Nexus)", "Edit on desktop", "wg_settings_edit", 1),
        ("toggle", "Depth", "Widgets set to BEHIND sit behind the wallpaper's subject (cut out by rembg)", "widgets.depth", "sv_widgets_depth"),
        ("toggle", "Wallpaper mood", "A calm picture makes them softer and slower, a lively one brighter", "widgets.mood", "sv_widgets_mood"),
        ("card", "Your widgets", "sv_widgets_on == 1"),
        ("widgets",),
    ]),
    ("BMO", "BMO", "Your desktop companion: his size, his home, his look and what he notices (his own panel sets these too)", "DESKTOP", [
        ("card", "BMO"),
        ("toggle", "BMO on your desktop", "Starts with mooi; off, he says goodbye", "companion.bmo", "sv_companion_bmo"),
        ("choice", "Size", "From a little one to a big one", "companion.size", "sv_companion_size", ["XS", "S", "M", "L"], "sv_companion_bmo == 1"),
        ("choice", "Lives", "Anywhere on the desktop, or small, just under the bar", "companion.place", "sv_companion_place", ["Desktop", "Under the bar"], "sv_companion_bmo == 1"),
        ("toggle", "Over the windows", "Off, he stays behind them, on the wallpaper", "companion.above", "sv_companion_above", [], "sv_companion_bmo == 1 and sv_companion_place == 0"),
        ("choice", "Colours", "His variants; mooi takes your wallpaper's colours", "companion.variant", "sv_companion_variant", ["Classic", "Night", "Pastel", "Game Boy", "mooi"], "sv_companion_bmo == 1"),
        ("card", "How he behaves"),
        ("choice", "Wander", "How often he walks about on his own", "companion.wander", "sv_companion_wander", ["Off", "Rare", "Some", "Often"], "sv_companion_bmo == 1"),
        ("choice", "Motion", "Still keeps him in place, lively makes him bouncier", "companion.motion", "sv_companion_motion", ["Still", "Calm", "Lively"], "sv_companion_bmo == 1"),
        ("choice", "Talk", "Off, only what matters, or chatty", "companion.talk", "sv_companion_talk", ["Off", "Rare", "Chatty"], "sv_companion_bmo == 1"),
        ("toggle", "Throw him", "Pick him up and flick: he flies and bounces off the edges", "companion.throw", "sv_companion_throw", [], "sv_companion_bmo == 1"),
        ("toggle", "Lock his place", "He stays where he is; no walking or dragging", "companion.locked", "sv_companion_locked", [], "sv_companion_bmo == 1"),
        ("toggle", "Dance to music", "He dances and sings along while something plays", "companion.music", "sv_companion_music", [], "sv_companion_bmo == 1"),
        ("toggle", "Clock in his panel", "The time and date on his panel's home tab", "companion.clock", "sv_companion_clock", [], "sv_companion_bmo == 1"),
        ("card", "What he notices"),
        ("toggle", "Notifications", "A ding! when one arrives; he never reads what it says", "companion.react.notes", "sv_companion_react_notes", [], "sv_companion_bmo == 1"),
        ("toggle", "Workspaces and windows", "A hop when you switch, a peek at a new window", "companion.react.spaces", "sv_companion_react_spaces", [], "sv_companion_bmo == 1"),
        ("toggle", "Battery", "Hungry when it runs low, glad on the charger", "companion.react.battery", "sv_companion_react_battery", [], "sv_companion_bmo == 1"),
        ("toggle", "Focus timer", "Focused while a block runs, a cheer when it ends", "companion.react.focus", "sv_companion_react_focus", [], "sv_companion_bmo == 1"),
        ("toggle", "Time of day", "Good morning once a day, a yawn late at night", "companion.react.time", "sv_companion_react_time", [], "sv_companion_bmo == 1"),
    ]),
    ("Sound", "Sound", "Where sound plays and where it listens, and each app's own volume", "SYSTEM", [
        ("card", "Output"),
        ("devices", "out"),
        ("card", "Input"),
        ("devices", "in"),
        ("card", "Apps playing"),
        ("note", "snd_apps.count < 1", "NOTHING IS PLAYING"),
        ("appvols",),
    ]),
    ("Power", "Power", "The battery, and how hard the machine works", "SYSTEM", [
        ("card", "Battery"),
        ("info", "Charge", "What is left, and whether it is charging", "pw_text"),
        ("choice", "Battery saver", "Glow, aberration, the frame's music and the visualizer off", "motion.saver", "sv_motion_saver", ["Off", "On battery", "Always"]),
        ("note", "not pw_ppd", "POWER-PROFILES-DAEMON IS NOT RUNNING HERE, SO THERE ARE NO PROFILES TO CHOOSE"),
        ("card", "Power profile", "pw_ppd"),
        ("choice", "Profile", "power-profiles-daemon's: quieter and cooler, or faster", "power.profile", "sv_power_profile", ["Keep", "Saver", "Balanced", "Performance"]),
    ]),
    # D161: when the screen locks by itself, and the picture it wears. The timer is hypridle's
    # (`mooi idle` writes its file); the picture is the Nexus's own identity, chosen here too.
    ("Lock", "Lock screen", "When the screen locks by itself, and the picture it wears", "SYSTEM", [
        ("card", "Locking"),
        ("slider", "Lock after", "Minutes without typing or pointing before mooi's lock screen takes the session",
         "lock.idle", 1, 60, "{sv_lock_idle + 1, 0} min"),
        # the same lock, now: the key does this too (Settings → Keys), and a lock nobody can find
        # by hand is half a lock
        ("choice", "Backdrop", "How far the wallpaper is blurred behind the plate", "lock.blur", "sv_lock_blur", ["Off", "Light", "Medium", "Heavy"]),
        ("slider", "Dim", "How far the wallpaper is dimmed, so the clock and the field read over any picture", "lock.dim", 0, 90,
         "{sv_lock_dim, 0}%"),
        # what those two do to the picture itself, before the screen is locked and the password typed
        ("preview",),
        # whether the lock wears the Nexus's two pictures, each on its own switch (the scene's own
        # lk_ban_on and lk_av_on): a locked screen is a door first, and someone else's photo behind
        # the password is not for every room; a banner without your face is a thing too
        ("toggle", "Show the banner", "The Nexus's banner across the top of the lock screen", "lock.banner", "sv_lock_banner"),
        ("toggle", "Show your picture", "The Nexus's profile picture on its plate above the clock", "lock.avatar", "sv_lock_avatar"),
        ("button", "Lock it now", "mooi's own lock screen straight away; it also takes the session by itself after the minutes above", "Lock now", "lock_now", 0),
        ("note", "true", "THE MACHINE SUSPENDS 30 MIN AFTER THAT · SUPER+L LOCKS NOW"),
        ("card", "Picture"),
        ("info", "On the lock screen", "The same banner or picture the Nexus's profile card shows", "lock_pic_now"),
        ("button", "Profile picture", "A small picture above the clock, chosen here; the Nexus's card shows it too", "Choose", "lock_pic", 0),
        ("button", "Banner", "A wide picture across the top of the lock screen; the Nexus's card shows it too", "Choose", "lock_pic", 1),
        ("note", "true", "A BANNER WINS OVER A PICTURE · THE NEXT LOCK SHOWS IT"),
    ]),
    ("Keys", "Keys", "mooi's keyboard shortcuts. Press Change, then the new keys", "SYSTEM", [("card", "Shortcuts"), ("keys",)]),
    ("System", "System", "Notifications, the islands and comfort", "SYSTEM", [
        ("card", "Notifications and tray"),
        ("choice", "mooi shows notifications", "As the desktop (not a development run), always, or never", "notifications.server", "note_server", ["Desktop", "Always", "Never"]),
        ("choice", "Do not disturb", "No pop-ups (urgent ones still come); the notices wait in the panel, and the Pill is not taken by them", "notifications.dnd", "sv_notifications_dnd",
         ["Off", "On", "While focusing", "Quiet hours"]),
        ("slider", "Quiet from", "The hour quiet begins", "notifications.quiet_from", 0, 23, "{sv_notifications_quiet_from, 0}:00", "sv_notifications_dnd == 3"),
        ("slider", "Quiet until", "The hour it ends", "notifications.quiet_to", 0, 23, "{sv_notifications_quiet_to, 0}:00", "sv_notifications_dnd == 3"),
        ("choice", "Tray icons", "In the palette's colours, or as the apps draw them", "tray.style", "tray_style", ["Themed", "Original"]),
        ("card", "Windows"),
        ("toggle", "Confirm before closing", "Ask once more before closing a window", "island.confirm_close", "confirm_close"),
        ("toggle", "Follow a window you move", "Moving a window to a workspace takes you there too", "island.follow_on_send", "sv_island_follow_on_send"),
        ("card", "Comfort"),
        ("slider", "Search results", "How many results search shows", "command.max_results", 3, 10, "{sv_command_max_results + 3, 0}"),
    ]),
    ("Signals", "Signal Loom", "How notifications arrive, join up and unfold; Reset puts them back as they came", "SYSTEM", [
        ("card", "Where they arrive"),
        ("choice", "Origin", "The corner the signals unfold from; the Signal Field opens there too", "signals.edge", "sv_signals_edge",
         ["Top right", "Top left", "Bottom right", "Bottom left"]),
        ("slider", "At once", "How many signals show; the rest wait behind a +N", "signals.max", 1, 6, "{sv_signals_max + 1, 0}"),
        ("slider", "Stays out", "A normal one, in seconds; a low one half as long, an urgent one until you deal with it", "signals.linger", 3, 30, "{sv_signals_linger + 3, 0} s"),
        ("choice", "Join", "Notices from one conversation (same app and title), from one app, or never", "signals.grouping", "sv_signals_grouping",
         ["Threads", "Apps", "Never"]),
        ("card", "Look and motion"),
        ("choice", "Size", "Compact segments, or roomier ones that show two lines", "signals.density", "sv_signals_density", ["Compact", "Comfortable"]),
        ("slider", "Corner cut", "How much the segments' corners are chamfered", "signals.chamfer", 0, 14, "{sv_signals_chamfer, 0} px"),
        ("slider", "Travel", "How far a signal slides out as it unfolds; none opens it in place", "signals.travel", 0, 100, "{sv_signals_travel, 0}%"),
        ("toggle", "Glow", "The light along an arriving signal and an urgent one's edge (notices still come without it)", "signals.effects", "sv_signals_effects"),
        ("card", "Privacy"),
        ("toggle", "Hide what they say", "Pop-ups show only who it is from; the Signal Field shows the rest", "signals.private", "sv_signals_private"),
    ]),
    ("Advanced", "Advanced", "What mooi is doing, where it keeps things, and its log", "SYSTEM", [
        ("card", "mooi"),
        ("info", "Version", "The shell and Pleamar it runs on", "adv_version"),
        ("info", "The bar", "Its process's share of a core, and its memory", "adv_usage"),
        ("info", "Settings file", "Every setting, as JSON; mooi applies an edit at once", "bar_path"),
        ("actions", [("Open settings.json", "adv_act", 1), ("Open the log", "adv_act", 2), ("Open the shell's folder", "adv_act", 3), ("Restart Hyprland", "adv_act", 4)]),
        ("note", "true", "HYPRLAND READS ITS CONFIG AGAIN AND MOOI'S BAR RESTARTS ON IT · WINDOWS STAY OPEN"),
        ("card", "Log"),
        ("log",),
    ]),
    # D108: everything round the Control Nexus in one place — the deck, its cards and notches, the
    # spine, the side notch and the Claude they ask
    ("Nexus", "Control Nexus", "The deck from the bar's mark, its cards and notches, the side notch, and Claude", "SHELL", [
        ("card", "The deck"),
        ("choice", "Edge", "Where the deck comes from: a strip along the bottom or the top, or a column down a side", "nexus.edge", "sv_nexus_edge", ["Bottom", "Top", "Left", "Right"], "sv_nexus_mode == 0"),
        ("choice", "Layout", "One row of cards along the edge, or a free canvas over the screen: in ✎, carry a card anywhere (the middle too) and pull its corner to size it", "nexus.rows", "sv_nexus_rows", ["One row", "Free canvas"], "sv_nexus_mode == 0"),
        ("choice", "Profile", "Your banner and picture, small or large", "nexus.profile", "sv_nexus_profile", ["Small", "Large"], "sv_nexus_mode == 0"),
        ("toggle", "Notches off the deck", "Claude, music, weather, workspaces, wallpapers and GitHub, out of the deck's ends", "nexus.notches", "sv_nexus_notches", None, "sv_nexus_mode == 0"),
        ("note", "sv_nexus_mode == 0", "ON THE DECK: ✎ CARRIES A CARD BY MOVE, × SHELVES IT, ⇔ RESIZES IT"),
        ("card", "The side notch"),
        ("toggle", "The side notch", "A sliver on the left edge that fans out into Claude, music, workspaces, wallpapers, weather and GitHub", "notch.on", "sv_notch_on"),
        ("note", "sv_notch_on == 1", "DRAG IT ALONG THE EDGE TO MOVE IT; IT STAYS WHERE YOU LEAVE IT"),
        ("card", "Claude"),
        ("choice", "Model", "Which Claude answers in the notch and as BMO (through Claude Code, signed in as you)", "claude.model", "sv_claude_model", ["Default", "Haiku", "Sonnet", "Opus"]),
        ("toggle", "Free models when Claude can't", "If Claude doesn't answer, ask a free model through opencode instead. It sends your question and the last few turns to a third party", "claude.free_fallback", "sv_claude_free_fallback"),
        ("note", "true", "IT CAN TALK, NOT ACT: NO TOOLS, NO FILES. BMO'S CHAT IS IN HIS PANEL"),
    ]),
    # D194: Loom / Fold, appended last so no page's place moves. Only what is built is offered (spec §7):
    # Phase 1 is the mode, its status and the way back.
    ("Loom / Fold", "Loom / Fold", "Experimental: connect and fold your windows into structures, alongside mooi or as the whole desktop", "SHELL", [
        ("card", "Mode"),
        ("choice", "Mode", "Native is mooi as it is; Hybrid adds the Loom / Fold features you turn on; Loom / Fold is the whole spatial experience. Switching back keeps everything", "loom.mode", "sv_loom_mode", [("Native", 0), ("Hybrid", 1), ("Loom / Fold", 2)]),
        ("info", "Status", "What Loom / Fold is doing now", "lf_status"),
        ("button", "Start again", "After it stopped on repeated failures (your windows were brought back)", "Start again", "lf_act", 1),
        ("note", "sv_loom_mode > 0.5", "EXPERIMENTAL · WHAT IS BUILT: ACCORDIONS, CUBES AND LOOM'S CONNECTIONS. TRANSFORMATIONS COME NEXT"),
        # D195: the features built so far, Hybrid's switches (Loom / Fold mode turns every built one on)
        ("card", "Features"),
        ("toggle", "Fold", "Structures your windows fold into. In Loom / Fold mode every built feature is on; these are Hybrid's", "loom.fold", "sv_loom_fold"),
        ("toggle", "Accordions", "Windows as thin layers on a screen edge: pull the one you need, the rest wait. Needs Fold", "loom.accordions", "sv_loom_accordions"),
        ("note", "sv_loom_fold < 0.5 and sv_loom_accordions > 0.5 and sv_loom_mode > 0.5 and sv_loom_mode < 1.5", "ACCORDIONS NEED FOLD — TURN FOLD ON FIRST"),
        ("toggle", "Cubes", "A whole workspace folded into one small solid and unfolded back where it was. Needs Fold", "loom.cubes", "sv_loom_cubes"),
        ("note", "sv_loom_fold < 0.5 and sv_loom_cubes > 0.5 and sv_loom_mode > 0.5 and sv_loom_mode < 1.5", "CUBES NEED FOLD — TURN FOLD ON FIRST"),
        ("choice", "Edge", "The screen edge the Accordions' strips and the docked Cubes stand on", "loom.edge", "sv_loom_edge", [("Right", 0), ("Left", 1)]),
        ("toggle", "Loom", "Connections between windows that do something: hop along them, see them as threads", "loom.loom", "sv_loom_loom"),
        ("choice", "Threads", "When the threads show: a few seconds when the focused window has connections, always, or only while linking", "loom.threads", "sv_loom_threads", [("When relevant", 0), ("Always", 1), ("Hidden", 2)], "sv_loom_loom > 0.5"),
        ("note", "true", "KEYS (SETTINGS → KEYS): SUPER+ALT+A ADD · ] [ NEXT, PREVIOUS · F FOLD · U OPEN ALL · R TAKE OUT · K MAKE A CUBE · J JOIN THE CUBE · N LINK (SHIFT: A WORKFLOW) · H HOP ALONG A LINK. A STRIP: PRESS PULLS, DRAG REORDERS, WHEEL STEPS. A CUBE: PRESS FOLDS OR UNFOLDS, WHEEL TURNS, MIDDLE OPENS ONE SIDE"),
    ]),
]
TAB = {label: i for i, (label, *_rest) in enumerate(SECTIONS)}

W, H = 1180, 800    # the window
XR = 1138           # where a row's control ends
TX = 274            # where a row's words begin
TOP = 112           # where a page's first card begins
CARD_HEAD, CARD_FOOT, CARD_GAP = 44, 8, 14

def sv(path): return "sv_" + path.replace(".", "_")
def df(path): return "df_" + path.replace(".", "_")

def revert(path, x, y):
    return f'SRevert({x}, {y}, {sv(path)} != {df(path)}, set_value, {code(path) * 1000} + {df(path)})'

def controls(kind, path, expr, opts, y):
    out = []
    c = code(path)
    if kind == "toggle":
        out.append(f'SToggle({XR - 46}, {y + 18}, {expr}, set_value, {c}, "{path}")')
        return out, XR - 46
    opts = [(o, i) if isinstance(o, str) else o for i, o in enumerate(opts)]
    total = 470 if len(opts) >= 5 else 440
    w = max(70, min(132, total // len(opts)))
    x = XR - w * len(opts)
    left = x
    out.append(f'STrack({x}, {y + 16}, {w * len(opts)})')
    for label, v in opts:
        out.append(f'SChoice({x}, {y + 16}, {w}, "{label}", {expr} == {v}, set_value, {c * 1000 + v})')
        x += w
    return out, left

MODULES_FOLD = [None]  # the Modules fold's fact, for "Look…" (D166), then the Look card's y with only it open
MAXS = [""]           # each page's scroll limit (review I2)
PAGE_FOLDS = {}       # each page's folds: (fact, nominal y)
PROPS = []          # each row's and card's place and height, springs they glide on (scene level)
INDEX = []          # (title, what it does, page, page title, its place): what search looks through
RESETS = {}         # page → the settings its Reset puts back

def row_lines(r, y, first, reverted):
    """One row's lines at its place `y` as if every row above were shown, and its height."""
    lines, k = [], r[0]
    if k == "note":
        lines.append(f'text "{r[2]}" {{ at: {TX}, {y + 14}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.ember }}')
        return lines, 28
    rule = "false" if first else "true"
    if k == "devices":
        lst = "snd_out" if r[1] == "out" else "snd_in"
        lines.append(f'for d in {lst} {{ SDevice(d, {y + 6}, snd_pick) }}')
        lines.append(f'text "NONE FOUND" {{ at: {TX}, {y + 24}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted; show: {lst}.count < 1 }}')
        return lines, f"(12 + max(1, {lst}.count) * 44)"
    if k == "appvols":
        lines.append(f'for a in snd_apps {{ SAppVol(a, {y + 4}, snd_app) }}')
        return lines, "(8 + snd_apps.count * 52)"
    if k == "displays":
        lines.append(f'for m in dp_list {{ SDisplay(m, {y + 6}) }}')
        return lines, "(12 + max(1, dp_list.count) * 60)"
    if k == "whkey":
        # Wallhaven's API key (D150): typed hidden, saved into mooi's data folder readable by you alone,
        # checked with Wallhaven; never shown again, never in settings.json or the repo
        lines.append(f'SRow({y}, "API key", "For sketchy and NSFW (with Purity above) and your account\'s filters. Get it at wallhaven.cc/settings/account", true, "", 420, {rule})')
        lines.append(f'box {{ from: {XR - 520}, {y + 18}; size: 300, 26; corner: 4; color: fl.ground; opacity: 0.6 }}')
        lines.append(f'box {{ from: {XR - 520}, {y + 18}; size: 300, 26; corner: 4; stroke: 1; color: fl.steel_700 }}')
        lines.append(f'input wh_key_in {{ at: {XR - 510}, {y + 24}; width: 280; size: 12; family: "Share Tech Mono"; color: fl.engrave; selection: fl.well; secret: true; placeholder: "paste your key" }}')
        lines.append(f'SButton({XR - 210}, {y + 19}, 100, "Save key", wh_key_save, 0)')
        lines.append(f'SButton({XR - 100}, {y + 19}, 100, "Forget", wh_key_forget, 0)')
        lines.append(f'text wh_key {{ at: {XR}, {y + 56}; anchor: right center; size: 10; weight: 600; family: "Share Tech Mono"; color: fl.phos; width: 520; lines: 1; align: right }}')
        return lines, 72
    if k == "folders":
        lines.append(f'for m in wf_list {{ SFolder(m, {y + 6}) }}')
        fy = f"{y + 10} + wf_list.count * 46"
        lines.append(f'box {{ from: {TX}, {fy}; size: 560, 32; corner: 5; color: fl.ground; opacity: 0.6 }}')
        lines.append(f'box {{ from: {TX}, {fy}; size: 560, 32; corner: 5; stroke: 1; color: fl.steel_700 }}')
        lines.append(f'input wf_new {{ at: {TX + 12}, {fy} + 8; width: 536; size: 12; family: "Share Tech Mono"; color: fl.engrave; selection: fl.well; placeholder: "~/Pictures/more-walls" }}')
        lines.append(f'SButton({TX + 572}, {fy} + 2, 130, "+ Add folder", wf_add, 0, false, wf_list.count < 8)')
        return lines, "(56 + wf_list.count * 46)"
    if k == "widgets":
        lines.append(f'for m in sw_list {{ SWidget(m, {y + 6}) }}')
        lines.append(f'SButton({TX}, {y + 14} + sw_list.count * 96, 170, "+ Now Playing", sw_add, 0, false, sw_list.count < 12)')
        lines.append(f'SButton({TX + 180}, {y + 14} + sw_list.count * 96, 150, "+ Visualiser", sw_add, 1, false, sw_list.count < 12 and sw_nviz < 3)')
        lines.append(f'SButton({TX + 340}, {y + 14} + sw_list.count * 96, 110, "+ Clock", sw_add, 2, false, sw_list.count < 12)')
        lines.append(f'SButton({TX + 460}, {y + 14} + sw_list.count * 96, 110, "+ Notes", sw_add, 3, false, sw_list.count < 12 and sw_nnotes < 1)')
        lines.append(f'SButton({TX + 580}, {y + 14} + sw_list.count * 96, 120, "+ GitHub", sw_add, 4, false, sw_list.count < 12 and sw_ngh < 2)')
        # D141: the one-of kinds, a second row (sw_one: a bit each, weather first)
        for i, (word, wdt) in enumerate([("+ Weather", 110), ("+ System", 104), ("+ Calendar", 116), ("+ Focus", 96), ("+ Claude", 100), ("+ Photo", 96), ("+ Launcher", 116)]):
            x = TX + sum(w for _, w in [("+ Weather", 110), ("+ System", 104), ("+ Calendar", 116), ("+ Focus", 96), ("+ Claude", 100), ("+ Photo", 96), ("+ Launcher", 116)][:i]) + 8 * i
            lines.append(f'SButton({x}, {y + 50} + sw_list.count * 96, {wdt}, "{word}", sw_add, {5 + i}, false, sw_list.count < 12 and mod(floor(sw_one / {2 ** i}), 2) < 0.5)')
        return lines, "(96 + sw_list.count * 96)"
    if k == "log":
        lines.append(f'box {{ from: {TX}, {y + 4}; size: {XR - TX}, 232; corner: 5; color: fl.ground; opacity: 0.7 }}')
        lines.append(f'for l in adv_log {{ SLogLine(l, {y + 18}) }}')
        return lines, 244
    if k == "info":
        _, title, desc, value = r
        lines.append(f'SRow({y}, "{title}", "{desc}", true, "", 360, {rule})')
        lines.append(f'text {value} {{ at: {XR}, {y + 30}; anchor: right center; size: 12; weight: 600; family: "Share Tech Mono"; color: fl.phos; width: 460; lines: 1; align: right }}')
        return lines, 60
    if k == "actions":
        bx = TX
        for label, ev, n in r[1]:
            w = 30 + len(label) * 8
            lines.append(f'SButton({bx}, {y + 14}, {w}, "{label}", {ev}, {n})'); bx += w + 10
        return lines, 58
    if k == "colourpick":
        # the custom base: hue, saturation and lightness, a row of quick picks, the colour itself
        lines.append(f'SRow({y}, "Custom colour", "Pick the base: hue, then how rich and how light", true, "", 300, {rule})')
        lines.append(f'box {{ from: {XR - 86}, {y + 12}; size: 86, 36; corner: 6; color: rgb(cp_r, cp_g, cp_b) }}')
        lines.append(f'box {{ from: {XR - 86}, {y + 12}; size: 86, 36; corner: 6; stroke: 1; color: fl.trace_lit }}')
        lines.append(f'text cp_hex {{ at: {XR - 43}, {y + 30}; anchor: center; size: 11; weight: 700; family: "Share Tech Mono"; color: fl.engrave; outline: 2, fl.ground }}')
        for n, (lab, cc, span, shown) in enumerate([("Hue", 1, 360, "{cp_h, 0}°"), ("Richness", 2, 100, "{cp_s, 0}%"), ("Lightness", 3, 60, "{cp_l, 0}%")]):
            yy = y + 60 + n * 40
            lines.append(f'text "{lab.upper()}" {{ at: {TX}, {yy + 14}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted }}')
            lines.append(f'SSlider({TX + 120}, {yy}, 560, cp_{"hsl"[n]}, {span}, set_colour, {cc}, "{lab}", "{shown}", true)')
        for n in range(8):
            lines.append(f'SColour({TX + n * 106}, {y + 184}, "", rgb(cq{n}_r, cq{n}_g, cq{n}_b), false, set_colour, {9000 + n}, true)')
        return lines, 228
    if k == "fxcolour":
        # one of the shaders' three colours (desktop.fx_*): a field for any #rrggbb, a Set beside it,
        # and the colour itself as the swatch
        _, title, desc, path, key = r[:5]
        n = int(key[3:])
        lines.append(f'SRow({y}, "{title}", "{desc}", true, "", 420, {rule})')
        lines.append(f'box {{ from: {XR - 530}, {y + 16}; size: 310, 28; corner: 4; color: fl.ground; opacity: 0.6 }}')
        lines.append(f'box {{ from: {XR - 530}, {y + 16}; size: 310, 28; corner: 4; stroke: 1; color: fl.steel_700 }}')
        lines.append(f'input {key}_in {{ at: {XR - 520}, {y + 22}; width: 290; size: 12; family: "Share Tech Mono"; color: fl.engrave; selection: fl.well; placeholder: "#rrggbb" }}')
        lines.append(f'SButton({XR - 210}, {y + 17}, 100, "Set", set_fxcolour, {n})')
        lines.append(f'box {{ from: {XR - 100}, {y + 13}; size: 88, 34; corner: 6; color: rgb({key}_r, {key}_g, {key}_b) }}')
        lines.append(f'box {{ from: {XR - 100}, {y + 13}; size: 88, 34; corner: 6; stroke: 1; color: fl.trace_lit }}')
        lines.append(f'text {key}_hex {{ at: {XR - 56}, {y + 30}; anchor: center; size: 11; weight: 700; family: "Share Tech Mono"; color: fl.engrave; outline: 2, fl.ground }}')
        return lines, 62
    if k == "kittyfile":
        # a pipeline of the user's own (desktop.kitty_shader == custom): chosen with zenity and kept
        # as the path kitty reads, never copied; the logic saves it (set_kitty_shader_file)
        _, title, desc, path, ev = r[:5]
        lines.append(f'SRow({y}, "{title}", "{desc}", true, "", 400, {rule})')
        lines.append(f'text kitty_shader_now {{ at: {XR - 200}, {y + 30}; anchor: right center; size: 10; weight: 600; family: "Share Tech Mono"; color: fl.phos; width: 300; lines: 1; align: right }}')
        lines.append(f'SButton({XR - 190}, {y + 15}, 190, "Choose a pipeline", {ev}, 0)')
        return lines, 60
    if k == "button":
        _, title, desc, label, ev, n = r
        n = TAB[n] if n in TAB else n
        lines.append(f'SRow({y}, "{title}", "{desc}", true, "", 400, {rule})')
        lines.append(f'SButton({XR - 180}, {y + 15}, 180, "{label}", {ev}, {n})')
        return lines, 60
    if k == "pillstage":
        # D174: the Pill as the choices make it, at twice its size (ui/pillpreview.plm)
        lines.append(f"SPillStage({y + 6})")
        return lines, 194
    if k == "pillshapes":
        # D174: the four shapes as pictures, the chosen one filled, edged and checked
        # D204: a fourth, the morph (its outline flows between capsule, blob, drop and bead)
        for n, (label, v) in enumerate([("Attached", 0), ("Floating", 1), ("Dot", 2), ("Morph", 3)]):
            lines.append(f'SPillShape({TX + n * 212}, {y + 8}, 200, "{label}", {v}, sv_pill_shape == {v}, set_value, {code("pill.shape") * 1000 + v})')
        if "pill.shape" not in reverted:
            lines.append(revert("pill.shape", XR - 4, y + 16)); reverted.add("pill.shape")
        return lines, 124
    if k == "pillhide":
        # D174: the three resting forms as pictures
        for n, (label, v) in enumerate([("Stay", 0), ("Tuck away", 1), ("Vanish", 2)]):
            lines.append(f'SPillHide({TX + n * 212}, {y + 8}, 200, "{label}", {v}, sv_pill_hide == {v}, set_value, {code("pill.hide") * 1000 + v})')
        if "pill.hide" not in reverted:
            lines.append(revert("pill.hide", XR - 4, y + 16)); reverted.add("pill.hide")
        return lines, 124
    if k == "deskstage":
        # D180: the desk's visual editor — drawn as the settings make it, presses change its look
        lines.append(f'SDeskStage({y + 6})')
        return lines, 202
    if k == "pillorder":
        # D168: the activities in their order, each with on/off and up/down (mooi-settings.luau, lib/pill)
        h = 0
        for n in range(6):
            yy = y + h
            lines.append(f'text pord{n} {{ at: {TX}, {yy + 18}; anchor: left center; size: 14; weight: 600; family: "Exo 2"; color: if(pon{n}, fl.engrave, fl.steel_500) }}')
            lines.append(f'text pdesc{n} {{ at: {TX + 160}, {yy + 18}; anchor: left center; size: 11; family: "Exo 2"; color: fl.muted; width: 420; lines: 1 }}')
            lines.append(f'group {{ show: n_pill > {n}; SButton({XR - 236}, {yy + 3}, 92, pick(pon{n}, "Off", "On"), pill_act, {n * 4}, pon{n}) }}')
            lines.append(f'SButton({XR - 136}, {yy + 3}, 64, "▲", pill_act, {n * 4 + 1})')
            lines.append(f'SButton({XR - 66}, {yy + 3}, 64, "▼", pill_act, {n * 4 + 2})')
            h += 40
        lines.append(f'text "THE TIME AND WORKSPACES SHOW WHEN NOTHING ELSE IS HAPPENING" {{ at: {TX}, {y + h + 14}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted }}')
        return lines, h + 30
    if k == "keys":
        h = 0
        for n, (key, title, desc) in enumerate(KEYS):
            yy = y + h
            lines.append(f'SRow({yy}, "{title}", "{desc}", true, "", 330, {"false" if n == 0 else "true"})')
            lines.append(f'SKeys(700, {yy + 16}, pick(capturing == {n}, key_{key}, cap_text), capturing == {n})')
            lines.append(f'SButton({XR - 96}, {yy + 15}, 96, pick(capturing == {n}, "Change", "Cancel"), key_change, {n}, capturing == {n})')
            lines.append(f'text key_clash_{key} {{ at: 700, {yy + 52}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.ember }}')
            h += 60
        return lines, h
    if k == "schemes":
        for n, (label, v) in enumerate(SCHEMES):
            col, row = n % 5, n // 5
            lines.append(f'SScheme({TX + col * 174}, {y + 6 + row * 66}, "{label}", rgb(sp{v}_r, sp{v}_g, sp{v}_b), rgb(se{v}_r, se{v}_g, se{v}_b), th_scheme == {v}, set_value, {code("theme.scheme") * 1000 + v}, true)')
        return lines, 142
    if k == "preview":
        # The lock's backdrop, as it will look: the wallpaper the shell is wearing, behind the blur
        # and the dimming chosen on the rows above (lock.blur, lock.dim), with the clock and the
        # plate over it at the size they are drawn. The picture is the still in ~/.cache, which the
        # logic hands the scene, so a video's current frame shows too.
        px, py, pw, ph = TX, y + 4, 300, 168
        cx, cy = px + pw // 2, py + ph // 2
        lines.append(f'box {{ from: {px}, {py}; size: {pw}, {ph}; color: fl.ground }}')
        lines.append(f'group {{ show: lk_wp_on; opacity: 0.42; blur: pick(sv_lock_blur, 0, 22, 54, 96); '
                     f'image lkwp {{ at: {px - 20}, {py - 20}; size: {pw + 40}, {ph + 40}; fit: cover }} }}')
        lines.append(f'box {{ from: {px}, {py}; size: {pw}, {ph}; color: fl.ground; opacity: sv_lock_dim / 100 }}')
        lines.append(f'text "22:41" {{ at: {cx}, {cy - 18}; anchor: center; size: 34; weight: 700; family: "Share Tech Mono"; color: fl.phos }}')
        lines.append(f'box {{ from: {cx - 62}, {cy + 12}; size: 124, 22; corner: 2; color: fl.steel_700; opacity: 0.9 }}')
        lines.append(f'text "PASSWORD" {{ at: {cx}, {cy + 23}; anchor: center; size: 9; weight: 700; family: "Share Tech Mono"; color: fl.muted }}')
        lines.append(f'box {{ from: {px}, {py}; size: {pw}, {ph}; stroke: 1; color: fl.trace_dim }}')
        lines.append(f'text "NO WALLPAPER STILL YET" {{ at: {cx}, {cy}; anchor: center; size: 10; family: "Share Tech Mono"; color: fl.muted; show: not lk_wp_on }}')
        lines.append(f'text "AS IT LOCKS" {{ at: {px + pw + 26}, {py + 14}; anchor: left center; size: 10; weight: 700; family: "Share Tech Mono"; color: fl.ember }}')
        lines.append(f'text "THE WALLPAPER AT THAT BLUR AND THAT DIMMING, WITH THE CLOCK AND THE PLATE OVER IT; A PICTURE SHOWS WHAT THE SETTINGS ABOVE WILL DO TO IT" '
                     f'{{ at: {px + pw + 26}, {py + 34}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted; width: {XR - px - pw - 30} }}')
        return lines, 180
    if k == "slider":
        _, title, desc, path, lo, hi, shown = r[:7]
        shown_expr = shown if shown.startswith("pick(") else f'"{shown}"'
        sw = 330
        x = XR - sw - 80
        lines.append(f'SRow({y}, "{title}", "{desc}", true, "", {x - TX - 50}, {rule})')
        lines.append(f'SSlider({x}, {y + 16}, {sw}, {sv(path)}, {hi - lo}, set_value, {code(path)}, "{title}", {shown_expr}, true)')
        if path not in reverted:
            lines.append(revert(path, x - 30, y + 30)); reverted.add(path)
        return lines, 60
    kind, title, desc, path, expr = r[:5]
    opts = r[5] if len(r) > 5 else None
    if kind == "source":
        x = XR - 5 * 90
        lines.append(f'SRow({y}, "{title}", "{desc}", true, "", {x - TX - 50}, {rule})')
        for v in range(5):
            lines.append(f'SColour({x + v * 90}, {y + 14}, "{["1st", "2nd", "3rd", "4th", "5th"][v]}", rgb(sc{v}_r, sc{v}_g, sc{v}_b), th_index == {v}, set_value, {code(path) * 1000 + v}, true)')
        if path not in reverted:
            lines.append(revert(path, x - 30, y + 30)); reverted.add(path)
        return lines, 60
    ctl, left = controls(kind, path, expr, opts or [], y)
    lines.append(f'SRow({y}, "{title}", "{desc}", true, "", {max(160, left - TX - 50)}, {rule})')
    lines += ctl
    if path not in reverted:
        lines.append(revert(path, left - 30, y + 30)); reverted.add(path)
    return lines, 60

LOOK_ROWS = [  # D166: (title, fact, key, labels) — the keys and values are lib/modlook's KEYS and VALUES
    ("Colour", "lk_colour", 0, ["Style", "Main", "Ember", "Flare", "Trace", "Wallpaper"]),
    ("Fill", "lk_fill", 1, ["Style", "Solid", "Tinted", "Glass", "None"]),
    ("Rounding", "lk_round", 2, ["Style", "Square", "Soft", "Round", "Pill"]),
    ("Outline", "lk_outline", 3, ["Style", "None", "Accent"]),
    ("Glow", "lk_glow", 4, ["Off", "Soft", "Strong"]),
    ("Shows", "lk_display", 5, ["Icon", "Icon + value", "Label + value"]),
    ("Width", "lk_width", 6, ["Fit", "Fixed"]),
]
LOOK_H = 44 + 36 * len(LOOK_ROWS) + 48

def look_card(y):
    """D166: the selected module's own look — colour, fill, rounding, outline, glow, what it shows and
    its width — each "as the style" until chosen; a group is styled through its first module."""
    ln = [f'SCard({y}, {LOOK_H}, "Look")',
          f'text "SELECT A MODULE ON THE BAR TO GIVE IT A LOOK OF ITS OWN" {{ at: {TX}, {y + 70}; anchor: left center; size: 11; family: "Share Tech Mono"; color: fl.muted; show: lay_kind < 0.5 or lay_kind > 1.5 }}',
          'group {', '    show: lay_kind > 0.5 and lay_kind < 1.5']
    for n, (title, f, key, labels) in enumerate(LOOK_ROWS):
        yy = y + 44 + n * 36
        w = 96 if len(labels) > 3 else 120
        x0 = XR - w * len(labels)
        ln.append(f'    text "{title}" {{ at: {TX}, {yy + 15}; anchor: left center; size: 14; weight: 600; family: "Exo 2"; color: fl.engrave }}')
        ln.append(f'    STrack({x0}, {yy}, {w * len(labels)})')
        for v, label in enumerate(labels):
            ln.append(f'    SChoice({x0 + v * w}, {yy}, {w}, "{label}", {f} == {v}, lay_look, {key * 16 + v})')
    yb = y + 44 + 36 * len(LOOK_ROWS) + 8
    ln.append(f'    text "A GROUP SHARES ITS FIRST MODULE\'S LOOK · ICONS KEEP THE THEME\'S INK" {{ at: {TX}, {yb + 15}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted }}')
    ln.append(f'    SButton({XR - 180}, {yb}, 180, "Same as the style", lay_look, {15 * 16})')
    ln.append('}')
    return ln

def layout_page(y):
    """The Layout page: a preview of the bar, what is selected and what can be done with it, and
    the three lists and the shelf as chips (all placed by the logic: mooi-settings.luau)."""
    yz = y + 308 + LOOK_H + 14
    ln = []
    ln.append(f'SCard({y}, 112, "Preview")')
    ln.append(f'text "TO SCALE · CLICK A MODULE TO SELECT IT" {{ at: {XR}, {y + 21}; anchor: right center; size: 10; family: "Share Tech Mono"; color: fl.muted }}')
    ln.append(f'box {{ from: {TX}, {y + 54}; size: {XR - TX}, 36; corner: 5; color: fl.ground }}')
    ln.append(f'box {{ from: {TX}, {y + 54}; size: {XR - TX}, 36; corner: 5; stroke: 1; color: fl.steel_700 }}')
    ln.append(f'line {{ from: {(TX + XR) / 2}, {y + 50}; to: {(TX + XR) / 2}, {y + 94}; width: 1; color: fl.trace_dim }}')
    ln.append(f'for p in lay_prev {{ LPrev(p, {y + 59}, lay_pick) }}')
    ln.append(f'SCard({y + 126}, 168, "Selected")')
    ln.append(f'text "SELECT A MODULE OR A SPACER BELOW, OR ON THE PREVIEW" {{ at: {TX}, {y + 200}; anchor: left center; size: 11; family: "Share Tech Mono"; color: fl.muted; show: lay_kind < 0.5 }}')
    ln.append('group {')
    ln.append('    show: lay_kind > 0.5')
    ln.append(f'    text lay_name {{ at: {TX}, {y + 194}; anchor: left center; size: 17; weight: 700; family: "Exo 2"; color: fl.phos }}')
    ln.append(f'    text lay_where {{ at: {TX}, {y + 216}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.ember; width: 560; lines: 1 }}')
    by = y + 240
    # placed: move, group, send, remove
    ln.append('    group {')
    ln.append('        show: lay_kind < 2.5')
    bx = TX
    for label, op, w, en in [("◀ Move", 1, 82, "lay_c1"), ("Move ▶", 2, 82, "lay_c2"), ("Join ◀", 3, 74, "lay_c3"), ("Join ▶", 4, 74, "lay_c4"), ("Split", 5, 64, "lay_c5")]:
        ln.append(f'        SButton({bx}, {by}, {w}, "{label}", lay_act, {op}, false, {en})'); bx += w + 6
    bx += 22
    ln.append(f'        text "SEND TO" {{ at: {bx}, {by + 15}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted }}'); bx += 60
    for label, op, en in [("Left", 6, "lay_c6"), ("Centre", 7, "lay_c7"), ("Right", 8, "lay_c8")]:
        ln.append(f'        SButton({bx}, {by}, 70, "{label}", lay_act, {op}, false, {en})'); bx += 76
    ln.append(f'        SButton({XR - 96}, {by}, 96, "Remove", lay_act, 9)')
    ln.append('    }')
    # a module's own outline (islands)
    ln.append('    group {')
    ln.append('        show: lay_kind > 0.5 and lay_kind < 1.5')
    ln.append(f'        text "OUTLINE" {{ at: {XR - 4 * 84 - 66}, {y + 200}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted }}')
    ln.append(f'        STrack({XR - 4 * 84}, {y + 186}, {4 * 84})')
    for v, label in enumerate(["Default", "Line", "Corners", "None"]):
        ln.append(f'        SChoice({XR - 4 * 84 + v * 84}, {y + 186}, 84, "{label}", lay_fi == {v}, set_value, (200 + lay_mod) * 1000 + {v})')
    ln.append(f'        text "A GROUP WEARS ITS FIRST MODULE\'S OUTLINE" {{ at: {XR}, {y + 224}; anchor: right center; size: 10; family: "Share Tech Mono"; color: fl.muted; show: lay_grouped }}')
    ln.append('    }')
    # on the shelf: where to put it
    ln.append('    group {')
    ln.append('        show: lay_kind > 2.5')
    bx = TX
    ln.append(f'        text "PUT IT" {{ at: {bx}, {by + 15}; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted }}'); bx += 54
    for label, op in [("On the left", 6), ("In the centre", 7), ("On the right", 8)]:
        ln.append(f'        SButton({bx}, {by}, 120, "{label}", lay_act, {op}, true)'); bx += 126
    ln.append('    }')
    ln.append('}')
    ln += look_card(y + 308)
    # the zones and the shelf
    for z, name in enumerate(["Left", "Centre", "Right", "Shelf — not on the bar"]):
        ln.append(f'SCard({yz} + lz{z}_y, lz{z}_h, "{name}")')
        if z < 3:
            ln.append(f'SButton({XR - 110}, {yz} + lz{z}_y + 7, 110, "+ Spacer", lay_act, {10 + z})')
            ln.append(f'text "EMPTY · SELECT SOMETHING AND SEND IT HERE" {{ at: {TX}, {yz} + lz{z}_y + 66; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted; show: lz{z}_n < 0.5 }}')
        else:
            ln.append(f'text "EVERY MODULE IS ON THE BAR" {{ at: {TX}, {yz} + lz{z}_y + 66; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted; show: lz{z}_n < 0.5 }}')
    ln.append(f'for g in lay_groups {{ LGroup(g, {yz}) }}')
    ln.append(f'for c in lay_chips {{ LChip(c, {yz}, lay_pick) }}')
    ln.append(f'SButton({TX}, {yz} + lay_zh + 4, 200, "Edit on the bar instead", set_action, 1, bar_edit)')
    return ln, f"{308 + LOOK_H + 14} + lay_zh + 48"

def section(i, rows, indent, page):
    """A page's cards and rows, each at its place as if every row above were shown; the props that
    carry them to where they are with the hidden ones left out."""
    lines, y, above = [], TOP, []        # above: (height, when) of everything placed so far
    def place(): return " + ".join([str(TOP)] + [str(hh) if c == "true" else f"if({c}, {hh}, 0)" for hh, c in above])
    card, reverted = None, set()
    resets = RESETS.setdefault(i, [])
    def close_card():
        nonlocal card, y
        if card is None: return
        k, cwhen, start, members, cy, cname = card
        hexpr = " + ".join([str(CARD_HEAD + CARD_FOOT)] + [str(hh) if c == "true" else f"if({c}, {hh}, 0)" for hh, c in members])
        PROPS.append(f"    prop gc_{i}_{k} = {CARD_HEAD + CARD_FOOT + sum(h for h, c in members if isinstance(h, int))} ~m.reflow\n    follow gc_{i}_{k} = {hexpr}")
        # the card's sheet is drawn first, under its rows
        lines[start:start] = ["group {", f"    show: {cwhen}", f"    move: 0, gy_{i}_c{k} - {cy}", f'    SCard({cy}, gc_{i}_{k}, "{cname}")', "}"]
        above.append((CARD_FOOT + CARD_GAP, cwhen)); y += CARD_FOOT + CARD_GAP
        card = None
    nk = 0
    fold = "true"                       # the open/closed state of the fold everything below belongs to
    fold_meta = [None]                  # the current fold, for search (review I1)
    def where(yy):
        """A row's fold and its y with only that fold open (the page's other folds closed)."""
        m = fold_meta[0]
        if m is None: return (None, yy)
        fv, k, body, f0, step = m
        return (fv, f0 + (k + 1) * step + (yy - body))
    nfold = 0
    def both(a, b): return b if a == "true" else (a if b == "true" else f"({a}) and ({b})")
    for j, r in enumerate(rows):
        if r[0] == "fold":
            # D166: a fold's header (its name, what it holds, ▸/▾): everything after it, up to the next
            # fold, shows only while it is open; the first fold on a page starts open
            close_card()
            fv = f"fd_{i}_{nfold}"
            PROPS.append(f"    fact {fv} = {'true' if nfold == 0 else 'false'}")
            hy = y
            PROPS.append(f"    prop gy_{i}_f{nfold} = {y} ~m.reflow\n    follow gy_{i}_f{nfold} = {place()}")
            hh = CARD_HEAD + 8
            lines += ["group {", f"    move: 0, gy_{i}_f{nfold} - {hy}",
                      f'    SCard({hy}, {hh}, "")',
                      f'    text pick({fv}, "▸  {r[1]}", "▾  {r[1]}") {{ at: {TX}, {hy + 26}; anchor: left center; size: 15; weight: 700; family: "Exo 2"; color: mix(fl.engrave, fl.phos, {fv}) }}',
                      f'    text "{r[2]}" {{ at: {XR}, {hy + 26}; anchor: right center; size: 10; family: "Share Tech Mono"; color: fl.muted; width: 520; lines: 1; align: right }}',
                      f'    zone box fz_{i}_{nfold} {{ from: 256, {hy}; size: 900, {hh}; cursor: pointer; role: button; label: "Open or fold {r[1]}" }}',
                      f"    on press fz_{i}_{nfold} {{ {fv} = not {fv} }}",
                      "}"]
            above.append((hh + CARD_GAP, "true")); y += hh + CARD_GAP
            fold = fv
            PAGE_FOLDS.setdefault(i, []).append((fv, hy))
            fold_meta[0] = (fv, nfold, y, PAGE_FOLDS[i][0][1], hh + CARD_GAP)   # (fact, k, body start, first fold y, header step)
            if r[1] == "Modules":
                MODULES_FOLD[0] = fv
                # where the Look card is with only this fold open: the first fold's place, a closed header
                # for each fold before this one, this header, then the layout's own 308 px to the Look card
                f0 = PAGE_FOLDS[i][0][1]
                MODULES_FOLD.append(f0 + (len(PAGE_FOLDS[i]) - 1) * (hh + CARD_GAP) + hh + CARD_GAP + 308)
            nfold += 1
            INDEX.append((r[1], r[2], i, page, hy, None, hy))
            continue
        if r[0] == "card":
            close_card()
            cwhen = both(r[2] if len(r) > 2 else "true", fold)
            PROPS.append(f"    prop gy_{i}_c{nk} = {y} ~m.reflow\n    follow gy_{i}_c{nk} = {place()}")
            card = [nk, cwhen, len(lines), [], y, r[1]]
            above.append((CARD_HEAD, cwhen)); y += CARD_HEAD
            nk += 1
            continue
        if r[0] == "layout":
            close_card()
            ll, hexpr = layout_page(y)
            PROPS.append(f"    prop gy_{i}_lay = {y} ~m.reflow\n    follow gy_{i}_lay = {place()}")
            lines.append("group {"); lines.append(f"    show: {fold}"); lines.append(f"    move: 0, gy_{i}_lay - {y}")
            lines += ["    " + l for l in ll]; lines.append("}")
            above.append((hexpr, fold))
            resets.append("@layout")
            INDEX.append(("Layout", "Put any module anywhere on the bar, in any order; group, hide, add spacers", i, page, y) + where(y))
            # what follows the layout sits below it (review I1): its nominal height, the zones at a usual 400
            y += 308 + LOOK_H + 14 + 400 + 48
            continue
        cwhen = card[1] if card else fold
        rwhen = ("theme_wallpaper" if r[0] == "schemes" else "sv_bar_bg == 9" if r[0] == "colourpick" else r[1] if r[0] == "note" else
                 (r[7] if r[0] == "slider" and len(r) > 7 else (r[6] if len(r) > 6 and r[0] not in ("slider", "button", "info") else "true")))
        when = rwhen if cwhen == "true" else (cwhen if rwhen == "true" else f"({cwhen}) and ({rwhen})")
        first = card is not None and not card[3]
        rl, h = row_lines(r, y, first, reverted)
        name = f"gy_{i}_{j}"
        PROPS.append(f"    prop {name} = {y} ~m.reflow\n    follow {name} = {place()}")
        lines.append("group {")
        lines.append(f"    show: {when}")
        lines.append(f"    move: 0, {name} - {y}")
        lines += ["    " + l for l in rl]
        lines.append("}")
        if r[0] in ("choice", "toggle", "slider", "source", "button") and r[1]:
            INDEX.append((r[1], r[2], i, page, y) + where(y))
        if r[0] in ("choice", "toggle", "slider", "source") and r[3] not in resets:
            resets.append(r[3])
        if r[0] == "colourpick" and "bar.bg_colour" not in resets:
            resets.append("bar.bg_colour")
        if r[0] == "schemes" and "theme.scheme" not in resets:
            resets.append("theme.scheme")
        if r[0] == "keys":
            resets.append("@keys")
        if r[0] == "pillshapes":
            INDEX.append(("Shape", "Attached, floating or a dot: as pictures", i, page, y) + where(y))
            if "pill.shape" not in resets: resets.append("pill.shape")
        if r[0] == "pillhide":
            INDEX.append(("When idle", "Stay, tuck away or vanish: as pictures", i, page, y) + where(y))
            if "pill.hide" not in resets: resets.append("pill.hide")
        if r[0] == "pillorder":
            INDEX.append(("What may take it", "The Pill's activities in order: battery, recording, notifications, music, volume and brightness", i, page, y) + where(y))
            resets += ["pill.order", "pill.off"]
        if card is not None:
            card[3].append((h, rwhen))
        # a list's height is an expression; its rows' nominal places assume a short one (the
        # props carry every row to its real place)
        above.append((h, when)); y += h if isinstance(h, int) else 100
    close_card()
    total = place()
    body = "\n".join(indent + "    " + l for l in lines)
    return f"{indent}group {{\n{indent}    show: set_tab == {i}\n{body}\n{indent}}}", total

def generate():
    ind = "        "
    groups, heights = [], []
    for i, (_, page, _, _, rows) in enumerate(SECTIONS):
        g, h = section(i, rows, ind + "    ", page)
        groups.append(g); heights.append(h)
    nav, ny, last = [], 136, None
    for i, (label, _, _, grp, _) in enumerate(SECTIONS):
        if grp != last:
            nav.append(f'{ind}    SNavGroup({ny + (3 if last else 0)}, "{grp}")'); ny += 21 if last else 20; last = grp
        # 22 an item (SNav is 24 tall; its neighbours overlap it by its padding). The rail scrolls
        # when the pages outgrow the window: 23 pages ran under the edit button at 800 px
        nav.append(f'{ind}    SNav({ny}, "{label}", set_tab == {i}, {i}, set_pick)'); ny += 22
    titles = ", ".join(f'"{t}"' for _, t, _, _, _ in SECTIONS)
    subs = ", ".join(f'"{s}"' for _, _, s, _, _ in SECTIONS)
    maxs = ", ".join(f"max(0, {h} + 24 - screen.height)" for h in heights)
    MAXS[0] = f"pick(set_tab, {maxs})"
    return f"""{ind}// The rail: mooi's mark, search, the pages in their groups, and the bar's own edit mode.
{ind}box {{ from: 0, 0; size: 232, screen.height; color: mix(fl.steel_900, fl.hull, 0.35) }}
{ind}group {{ glow: 6, (0.6) * st_glow, fl.phos; box {{ from: 231, 0; size: 1, screen.height; color: fl.phos; opacity: 0.3 }} }}
{ind}box {{ from: 232, 0; size: 1, screen.height; color: fl.trace_dim }}
{ind}text "MOOI" {{ at: 24, 38; anchor: left center; size: 24; weight: 700; family: "Exo 2"; color: fl.phos; shadow: 0, 0, 8, 40%, fl.phos }}
{ind}text "SETTINGS · {{upper(bar_version)}}" {{ at: 24, 62; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.ember; width: 190; lines: 1 }}
{ind}zone box set_find {{ from: 14, 82; size: 204, 34; corner: 5; cursor: text; role: region; label: "Search the settings" }}
{ind}box {{ from: 14, 82; size: 204, 34; corner: 5; color: fl.ground }}
{ind}box {{ from: 14, 82; size: 204, 34; corner: 5; stroke: 1; color: mix(mix(fl.steel_700, fl.trace_lit, set_find.hover), fl.phos, searching) }}
{ind}ellipse {{ at: 31, 98; radius: 5; stroke: 1.3; color: mix(fl.muted, fl.phos, searching) }}
{ind}line {{ from: 34.5, 101.5; to: 38.5, 105.5; width: 1.3; color: mix(fl.muted, fl.phos, searching) }}
{ind}text "SEARCH · CTRL F" {{ at: 46, 99; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted; show: not searching }}
{ind}input set_query {{ at: 46, 90; width: 164; size: 12; family: "Exo 2"; color: fl.phos; selection: fl.well }}
{ind}on press set_find {{ focus set_query }}
{ind}// the pages, scrolled by the wheel when they do not fit above the edit button
{ind}zone box set_rail {{ from: 0, 124; size: 232, screen.height - 200 }}
{ind}on scroll set_rail {{ set_navs = clamp(set_navs - wheel * 44, 0, max(0, {ny + 6} - (screen.height - 76))) }}
{ind}group {{
{ind}    clip box {{ from: 0, 124 + set_navs_s; size: 232, screen.height - 200 }}
{ind}    move: 0, 0 - set_navs_s
{chr(10).join(nav)}
{ind}}}
{ind}box {{ from: 14, screen.height - 77; size: 204, 1; color: fl.trace_dim; show: {ny + 6} > screen.height - 76 }}
{ind}SButton(16, screen.height - 64, 200, "Edit on the bar", set_action, 1, bar_edit)
{ind}text "CHANGES APPLY AT ONCE" {{ at: 18, screen.height - 18; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.trace }}

{ind}// The page: its cards and rows (scrolled by the wheel), sliding in when it is chosen.
{ind}zone box set_body {{ from: 233, 96; size: screen.width - 233, screen.height - 96 }}
{ind}on scroll set_body {{ set_scroll = clamp(set_scroll - wheel * 48, 0, pick(set_tab, {maxs})) }}
{ind}group {{
{ind}    // the clip is in the moved group's own coordinates: it is carried back down by the scroll,
{ind}    // or it rises with the rows and a scrolled section showed only its top (fixed 2026-10-20)
{ind}    clip box {{ from: 233, 96 + set_scroll_s; size: screen.width - 233, screen.height - 96 }}
{ind}    move: 0, 0 - set_scroll_s
{ind}    group {{
{ind}        opacity: pg
{ind}        move: 0, 14 * (1 - pg)
{chr(10).join(groups)}
{ind}    }}
{ind}    // Search: what matches, from every page; a press goes to it
{ind}    group {{
{ind}        show: searching
{ind}        box {{ from: 233, 96 + set_scroll_s; size: screen.width - 233, screen.height - 96; color: mix(fl.ground, fl.steel_900, 0.6) }}
{ind}        text "{{set_hits, 0}} MATCHING · ENTER OPENS THE FIRST · ESC CLEARS" {{ at: {TX}, 120 + set_scroll_s; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.ember }}
{ind}        for r in set_results {{ SResult(r, 140 + set_scroll_s + r.index * 64, set_jump) }}
{ind}    }}
{ind}}}
{ind}// The header, over the scrolled rows: the page's name, what it is for, and its Reset.
{ind}box {{ from: 233, 0; size: screen.width - 233, 96; color: mix(fl.ground, fl.steel_900, 0.6) }}
{ind}text pick(set_tab, {titles}) {{ at: 256, 40; anchor: left center; size: 26; weight: 600; family: "Exo 2"; color: fl.phos }}
{ind}text pick(set_tab, {subs}) {{ at: 256, 70; anchor: left center; size: 12; family: "Exo 2"; color: fl.muted; width: 700; lines: 1 }}
{ind}box {{ from: 233, 95; size: screen.width - 233, 1; color: fl.trace_dim }}
{ind}group {{
{ind}    show: not searching
{ind}    SButton(screen.width - 236, 30, 164, pick(rs_armed == set_tab, "Reset this page", "Press again to reset"), set_reset, set_tab, rs_armed == set_tab)
{ind}}}
{ind}zone box set_close {{ from: screen.width - 52, 30; size: 32, 32; corner: 6; cursor: pointer; role: button; label: "Close the settings" }}
{ind}box {{ from: screen.width - 52, 30; size: 32, 32; corner: 6; color: fl.hull_raised; opacity: set_close.hover }}
{ind}line {{ from: screen.width - 42, 40; to: screen.width - 30, 52; width: 1.5; color: mix(fl.muted, fl.ember, set_close.hover) }}
{ind}line {{ from: screen.width - 30, 40; to: screen.width - 42, 52; width: 1.5; color: mix(fl.muted, fl.ember, set_close.hover) }}
{ind}on press set_close {{ emit set_action(9) }}"""

def edit():
    """Edit mode, per module: an outline, a zone that picks the module up (or, clicked without
    moving, chooses it), and the inspector that opens under the chosen one."""
    ind = "    "
    out = []
    for i, m in enumerate(MODULES):
        out.append(f"""{ind}group {{
{ind}    show: bar_edit and p_{m}
{ind}    zone box ez_{m} {{ from: xs_{m}, fl.top; size: ws_{m}, fl.mod_h; cursor: grab; role: button; label: "Move {NAMES[m]}" }}
{ind}    box {{ from: xs_{m} + 1, fl.top + 1; size: ws_{m} - 2, fl.mod_h - 2; corner: 5; color: if(ed_drag == {i} and ed_merge, fl.ember_fill, fl.well)
{ind}          opacity: if(ed_drag == {i}, 0.6, if(ed_sel == {i}, 0.4, 0.2 * ez_{m}.hover)) }}
{ind}    box {{ from: xs_{m} + 1, fl.top + 1; size: ws_{m} - 2, fl.mod_h - 2; corner: 5; stroke: if(ed_sel == {i}, 2, 1.2)
{ind}          color: if(ed_sel == {i} or ed_drag == {i}, fl.flare, mix(fl.trace_lit, fl.flare, ez_{m}.hover)); opacity: if(ed_drag >= 0 and ed_drag != {i}, 0.45, 0.85) }}
{ind}}}
{ind}on press ez_{m} while bar_edit {{ ed_press = {i}; ed_px = pointer.x; ed_x = pointer.x; ed_y = pointer.y }}
{ind}on drag ez_{m} while ed_press == {i} and ed_drag < 0 and abs(pointer.x - ed_px) > 5 {{ ed_drag = {i}; ed_sel = -1 }}
{ind}on release ez_{m} while ed_drag == {i} {{ emit edit_drop(ed_drag * 100000 + round(clamp(ed_x, 0, 49999)) + if(ed_y > st_res + 4, 50000, 0)); ed_drag = -1; ed_press = -1 }}
{ind}on release ez_{m} while ed_drag < 0 and ed_press == {i} {{ ed_sel = if(ed_sel == {i}, -1, {i}); ed_press = -1 }}""")
    names = ", ".join(f'"{NAMES[m]}"' for m in MODULES)
    xs = ", ".join(f"xs_{m}" for m in MODULES)
    ws = ", ".join(f"ws_{m}" for m in MODULES)
    fis = ", ".join(f"fi_{m}" for m in MODULES)
    gs = ", ".join(f"g_{m}" for m in MODULES)
    out.append(f"""{ind}// The ghost's word: what letting go now will do.
{ind}text pick(max(ed_drag, 0), {names}) {{ at: ed_x, ed_y - 4; anchor: center; size: 12; weight: 700; family: "Exo 2"; color: fl.ink; show: ed_drag >= 0 }}
{ind}text pick(if(ed_y > st_res + 4, 2, if(ed_merge, 1, 0)), "MOVE HERE", "JOIN THIS GROUP", "HIDE") {{ at: ed_x, ed_y + 8; anchor: center; size: 10; family: "Share Tech Mono"; color: fl.ink; show: ed_drag >= 0 }}
{ind}// The inspector, under the chosen module: what it is, its outline, and what can be done with it.
{ind}let ed_ix = clamp(pick(max(ed_sel, 0), {xs}) + pick(max(ed_sel, 0), {ws}) / 2 - 170, 12, screen.width - 352)
{ind}let ed_fi = pick(max(ed_sel, 0), {fis})
{ind}let ed_g = pick(max(ed_sel, 0), {gs})
{ind}group {{
{ind}    show: bar_edit and ed_sel >= 0 and ed_drag < 0
{ind}    move: ed_ix, st_res + 92
{ind}    FlPlate(340, 128) {{
{ind}        text pick(max(ed_sel, 0), {names}) {{ at: 14, 18; anchor: left center; size: 14; weight: 600; family: "Exo 2"; color: fl.phos }}
{ind}        text pick(ed_g, "ON ITS OWN", "IN A GROUP") {{ at: 326, 18; anchor: right center; size: 10; family: "Share Tech Mono"; color: fl.ember }}
{ind}        text "OUTLINE" {{ at: 14, 46; anchor: left center; size: 10; family: "Share Tech Mono"; color: fl.muted }}
{ind}        SChoice(80, 32, 64, "Default", ed_fi == 0, set_value, (200 + ed_sel) * 1000 + 0)
{ind}        SChoice(144, 32, 64, "Line", ed_fi == 1, set_value, (200 + ed_sel) * 1000 + 1)
{ind}        SChoice(208, 32, 64, "Corners", ed_fi == 2, set_value, (200 + ed_sel) * 1000 + 2)
{ind}        SChoice(272, 32, 64, "None", ed_fi == 3, set_value, (200 + ed_sel) * 1000 + 3)
{ind}        SButton(14, 72, 40, "◀", edit_op, ed_sel * 10 + 0)
{ind}        SButton(58, 72, 40, "▶", edit_op, ed_sel * 10 + 1)
{ind}        SButton(106, 72, 70, "Join ◀", edit_op, ed_sel * 10 + 2)
{ind}        SButton(180, 72, 70, "Join ▶", edit_op, ed_sel * 10 + 3)
{ind}        SButton(254, 72, 72, "Hide", edit_op, ed_sel * 10 + 5, true)
{ind}        group {{
{ind}            opacity: if(ed_g, 1, 0.35)
{ind}            SButton(106, 104, 144, "Split from group", edit_op, ed_sel * 10 + 4)
{ind}        }}
{ind}        SButton(254, 104, 72, "Look…", edit_op, ed_sel * 10 + 6)
{ind}    }}
{ind}}}
{ind}on key Left while bar_edit and ed_sel >= 0 {{ emit edit_op(ed_sel * 10 + 0) }}
{ind}on key Right while bar_edit and ed_sel >= 0 {{ emit edit_op(ed_sel * 10 + 1) }}
{ind}on key Delete while bar_edit and ed_sel >= 0 {{ emit edit_op(ed_sel * 10 + 5); ed_sel = -1 }}
{ind}on edit_op(v) while v - floor(v / 10) * 10 == 5 {{ ed_sel = -1 }}""")
    return "\n".join(out)

HEADER = """language 0.9
import "theme/tokens.plm"
import "theme/ferrolume.plm"
import "ui/ferrolume.plm"
import "ui/pillpreview.plm"

// GENERATED by tools/gen-settings.py — edit that, not this.
//
// mooi's settings: the shell's home, a window of its own. It is a program apart from the bar
// (shell/mooi.plm starts it from the mark, and it ends when its window is closed): a window in
// the bar's own scene took the keyboard's routing from the islands now and then. It shares
// mooi's data folder (bin/mooi links ~/.local/share/pleamar/mooi-settings to mooi's), reads
// and writes the same settings.json, and mooi applies whatever it writes within the frame.
// Its logic (mooi-settings.luau) publishes the settings as the same facts the bar reads, and
// paints the same palette (lib/ferro), so the window wears what the bar wears.
scene Mooi {
    permissions {
        run: "pleamar", "matugen", "hyprctl", "powerprofilesctl", "xdg-open", "tail", "ps", "mooi", "zenity"
        services: "files", "files.write", "files.remove", "env", "audio", "audio.*", "battery"
    }
"""

def shared_facts():
    """The facts the window reads, declared exactly as mooi.plm declares them."""
    text = SCENE.read_text()
    want = re.compile(r"^    (fact|prop|follow) (c_\w+|fr_\w+|pr_\w+|ws_style|bar_frame|bar_ground|bar_rail|bar_accents|"
                      r"bar_full|bar_surface|viz|bar_foot_viz|music_rim|music_rim_gain|music_rim_glow|helix_frame|media_mode|media_idle|frame_on|frame_band|"
                      r"frame_music|frame_style|frame_reach|frame_edges|note_server|th_scheme|th_index|th_contrast|"
                      r"th_signal|theme_wallpaper|show_clock|previews|confirm_close|bar_labels|bar_wheel|"
                      r"m_\w+|fi_\w+|g_\w+|st_\w+)\b.*$", re.M)
    return "\n".join(m.group(0) for m in want.finditer(text))

def check_setters():
    """The window's codes are places in this list; lib/setters.luau decodes them with its own copy.
    They must be the same list, in the same order (D147: one entry out of place shifted 56 settings)."""
    lua = (ROOT / "shell" / "lib" / "setters.luau").read_text()
    block = lua[lua.index("M.SETTERS = {"):lua.index("\n}", lua.index("M.SETTERS = {"))]
    theirs = re.findall(r'"([a-z_]+\.[a-z_.]+)"', block)
    if theirs != SETTERS:
        for i, (a, b) in enumerate(zip(SETTERS, theirs)):
            if a != b:
                raise SystemExit(f"setters differ at {i + 1}: here {a!r}, lib/setters.luau {b!r}")
        raise SystemExit(f"setters differ in length: here {len(SETTERS)}, lib/setters.luau {len(theirs)}")

def main():
    check_setters()
    body = generate()
    out = HEADER + shared_facts() + """
    text bar_version = "mooi"
    text bar_path = ""
    fact ws_max = 10
    fact tray_style = 0
    fact dk_manage = false
    fact dk_border = 2
    fact dk_colour = 0
    fact dk_gin = 4
    fact dk_gout = 12
    fact dk_round = 12
    fact dk_dim = false
    fact capturing = -1       // the key being changed (its row), or −1
""" + "".join(f"    fact sv_{p.replace('.', '_')} = 0\n    fact df_{p.replace('.', '_')} = 0\n" for p in SETTERS) + """
    text cap_text = "Press the new keys… (Esc cancels)"
    event key_change ->       // to the logic: change key n (99: all back to the defaults)
""" + "".join(f"    text key_{k} = \"\"\n    text key_clash_{k} = \"\"\n" for k, _, _ in KEYS) + "".join(
        f"    fact sp{v}_r = 0.5\n    fact sp{v}_g = 0.8\n    fact sp{v}_b = 0.7\n    fact se{v}_r = 0.9\n    fact se{v}_g = 0.5\n    fact se{v}_b = 0.2\n" for v in range(10)) + "".join(
        f"    fact sc{v}_r = 0.3\n    fact sc{v}_g = 0.3\n    fact sc{v}_b = 0.3\n" for v in range(5)) + """
    fact bar_edit = false     // the bar's edit mode (the logic asks the bar)
    prop sp_ang = 0           // D174, D188: the stage's flash — the edge breathing while pill.ping is on
    spin sp_ang by if(sv_pill_ping > 0.5, 70, 0)
    fact set_tab = 0          // the section shown
    fact set_scroll = 0       // how far its rows are scrolled
    fact set_navs = 0         // how far the rail's pages are scrolled
    prop set_navs_s = 0 ~m.reflow
    follow set_navs_s = set_navs
    prop set_scroll_s = 0 ~m.reflow
    follow set_scroll_s = clamp(set_scroll, 0, @MAXS@)
    event set_value ->        // to the logic: one setting to one value (lib/setters)
    event set_action ->       // to the logic: 1 the bar's edit mode
    event set_pick            // a section chosen
    text set_query = ""       // what search looks for
    fact searching = false    // there is something to look for
    fact set_hits = 0
    model set_results max 8 { title: text; desc: text; page: text }
    event set_jump ->         // to the logic: open result n
    on key Escape while searching { emit set_jump(-1) }
    on focus while capturing < 0 { focus set_query }
    on key Ctrl+f { focus set_query }
    on key slash while capturing < 0 { focus set_query }
    on key_change { blur }
    event set_reset ->        // to the logic: put page n's settings back (the first press arms it)
    fact rs_armed = -1        // the page whose Reset is armed, or −1
    // The Layout page (mooi-settings.luau places every chip): what is selected and what it can do.
    event lay_pick ->         // to the logic: chip n chosen (a preview box names its chip)
    event lay_act ->          // to the logic: 1 ◀ · 2 ▶ · 3 join ◀ · 4 join ▶ · 5 split · 6-8 to left/centre/right · 9 remove · 10-12 a spacer in left/centre/right
    model lay_chips max 48 { x: number; y: number; w: number; label: text; sel: bool; kind: number; idx: number }
    model lay_groups max 24 { x: number; y: number; w: number }
    model lay_prev max 40 { x: number; w: number; label: text; sel: bool; chip: number }
    fact lay_kind = 0         // what is selected: 0 nothing · 1 a module on the bar · 2 a spacer · 3 a module on the shelf
    text lay_name = ""
    text lay_where = ""
    fact lay_mod = 0          // the selected module's place in the order (its outline's code)
    fact lay_fi = 0           // its outline
    fact lay_grouped = false
    event lay_look ->         // to the logic (D166): the selected module's look, key * 16 + value (lib/modlook)
    event pill_act ->         // to the logic (D168): row * 4 + 0 on/off · 1 up · 2 down (lib/pill.reorder)
    fact n_pill = 5
    fact pon0 = true
    fact pon1 = true
    fact pon2 = true
    fact pon3 = true
    fact pon4 = true
    fact pon5 = true
    text pord0 = ""
    text pord1 = ""
    text pord2 = ""
    text pord3 = ""
    text pord4 = ""
    text pord5 = ""
    text pdesc0 = ""
    text pdesc1 = ""
    text pdesc2 = ""
    text pdesc3 = ""
    text pdesc4 = ""
    text pdesc5 = ""
    event open_module ->      // from the bar (D166, its edit mode's Look…): select that module (barlayout.ORDER index) on Bar & Frame
    fact lk_colour = 0        // its look's positions in lib/modlook's lists (-1: none, a custom colour)
    fact lk_fill = 0
    fact lk_round = 0
    fact lk_outline = 0
    fact lk_glow = 0
    fact lk_display = 1
    fact lk_width = 0
    fact lay_zh = 400         // how tall the zones and the shelf are, together
    // The system pages (mooi-settings.luau reads them): sound, displays, power, the log.
    model snd_out max 12 { name: text; on: bool; n: number }
    model snd_in max 12 { name: text; on: bool; n: number }
    model snd_apps max 10 { name: text; title: text; vol: number }
    event snd_pick ->         // to the logic: output n, or input 100 + n
    event snd_app ->          // to the logic: app (n + 1) · 1000 + volume %
    model dp_list max 6 { name: text; model: text; mode: text; place: text; focused: bool }
    // The wallpaper folders (walls.folders, D147): one row each, a field to add one
    model wf_list max 8 { path: text; n: text; missing: bool }
    text wf_new = ""
    text wh_key = ""          // whether a Wallhaven key is saved, and whether Wallhaven took it
    text wh_key_in = ""       // the key as it is typed (hidden), emptied once saved
    event wh_key_save ->      // to the logic: save what wh_key_in says
    event wh_key_forget ->    // to the logic: remove the saved key
    event wf_del ->           // to the logic: remove folder n
    event wf_add ->           // to the logic: add what wf_new says
    // The desktop widgets (widgets.json, lib/widgets): one row each; what a row's controls send.
    model sw_list max 12 { name: text; detail: text; mode: text; kind: number; choice: number; idle: number; opa: number; bars: number; nlay: number }
    event sw_choice ->        // to the logic: row · 100 + layout (0 … 2) or mode (0 … 11)
    event sw_idle ->          // to the logic: row · 10 + 0 hide · 1 rest · 2 marker
    event sw_remove ->        // to the logic: the row
    event sw_add ->           // to the logic: the kind (lib/widgets ADD_ORDER, from 0)
    fact sw_nviz = 0          // visualisers listed (three at most)
    fact sw_nnotes = 0        // notes listed (one at most)
    fact sw_ngh = 0           // GitHub widgets listed (two at most)
    fact sw_one = 0           // the one-of kinds there already, a bit each: weather 1 · system 2 · calendar 4 · timer 8 · claude 16 · photo 32 · launcher 64
    event sw_slide ->         // to the logic: (row · 10 + 1 opacity · 2 bars) · 1000 + value
    event wg_settings_edit -> // to the logic: edit the widgets on the desktop (this window goes)
    event pill_board_edit ->  // to the logic (D170): the Pill's board, open in edit (this window goes)
    event wl_settings_open -> // to the logic: open the wallpaper picker (this window goes)
    text pw_text = ""
    text lf_status = ""       // D194: Loom / Fold's status line (lib/loommode.status_line)
    event lf_act ->           // to the logic (D194): 1 start Loom / Fold again after a recovery
    text lock_pic_now = ""    // the lock screen's picture (Settings → Lock): the identity's banner or picture
    text lk_wp = ""           // the wallpaper still the lock's backdrop preview wears (Settings → Lock)
    fact lk_wp_on = false     // there is one to show
    image lkwp = from lk_wp, 640, 360
    event lock_pic ->         // to the logic: choose it (0 the profile picture, 1 the banner)
    event lock_now ->         // to the logic: lock the session now (`mooi lock`)
    fact pw_ppd = false       // power-profiles-daemon answers
    fact saving = false       // the battery saver is on now
    text adv_version = ""
    text adv_usage = ""
    text gr_theme = ""        // D190: what the login screen wears, asked of `mooi greet-theme --status`
    model adv_log max 12 { line: text; warn: bool }
    event adv_act ->          // to the logic: 1 open settings.json · 2 open the log · 3 open the shell's folder · 4 restart Hyprland and the bar
    // The custom base colour (bar.bg_colour) as hue, richness and lightness, and eight quick picks.
    event set_colour ->       // to the logic: 1000 · (1 hue · 2 richness · 3 lightness) + value, or 9000 + a quick pick
    text cp_hex = "#101418"
    fact cp_h = 210
    fact cp_s = 10
    fact cp_l = 7
    fact cp_r = 0.06
    fact cp_g = 0.08
    fact cp_b = 0.09
""" + "".join(f"    fact cq{n}_r = 0.1\n    fact cq{n}_g = 0.1\n    fact cq{n}_b = 0.1\n" for n in range(8)) + "".join(
        f"    fact fxp{i}_r = 0.5\n    fact fxp{i}_g = 0.5\n    fact fxp{i}_b = 0.5\n    text fxp{i}_hex = \"#7FCFB6\"\n    text fxp{i}_in = \"\"\n"
        for i in range(1, 4)) + (
        "    // The shaders' own three colours (desktop.fx_phos/ember/trace), the `custom` light: each typed\n"
        "    // as #rrggbb into its field, read back and saved by the logic (set_fxcolour: 1, 2 or 3).\n"
        "    event set_fxcolour ->\n    text kitty_shader_now = \"\"\n    event set_kitty_shader_file ->\n") + "".join(f"    fact lay_c{n} = true\n" for n in range(1, 9)) + "".join(f"    fact lz{z}_y = 0\n    fact lz{z}_h = 90\n    fact lz{z}_n = 0\n" for z in range(4)) + """
""" + "\n".join(PROPS) + """
    // A page chosen slides in: it starts a little low and clear, and settles.
    prop pg = 1
    layer page_in {
        fresh for 30ms after set_pick { pg: 0 ~1ms }
        shown                         { pg: 1 ~m.enter }
    }
    on set_pick(v) { set_tab = v; set_scroll = 0; rs_armed = -1 }

    surface settings_win {
        kind: window
        title: "mooi · settings"
        size: 1180, 800
        // the keyboard on a click (search, key capture): a window has none unless it asks
        keyboard: on_demand
        box { from: 0, 0; size: screen.width, screen.height; color: mix(fl.ground, fl.steel_900, 0.6) }
""" + body.replace("{ind}on press set_close {{ settings_open = false }}", "") + """
    }
}
"""
    out = out.replace("on press set_close { settings_open = false }", "on press set_close { emit set_action(9) }")
    out = out.replace("@MAXS@", MAXS[0])
    (ROOT / "shell" / "mooi-settings.plm").write_text(out)
    def lua(t): return '"' + t.replace("\\", "\\\\").replace('"', '\\"') + '"'
    rows = "\n".join(f'    {{ title = {lua(t)}, desc = {lua(d)}, tab = {tab}, page = {lua(pg)}, y = {yy}'
                     + (f', fold = "{fd}", fy = {fy}' if fd else '') + ' },' for t, d, tab, pg, yy, fd, fy in INDEX)
    resets = "\n".join(f'    [{tab}] = {{ ' + ", ".join(lua(x) for x in paths) + ' },' for tab, paths in sorted(RESETS.items()))
    (ROOT / "shell" / "lib" / "settings_index.luau").write_text(
        "-- GENERATED by tools/gen-settings.py: every setting the window shows, for its search, and what\n"
        "-- each page's Reset puts back (`@layout`: the bar's lists; `@keys`: the keys).\n"
        "-- `tab` is the page (from 0), `y` the row's place on it with every row shown.\nlocal rows = {\n" + rows + "\n}\n"
        "rows.resets = {\n" + resets + "\n}\n"
        f"rows.layout_tab = {TAB['Bar & Frame']}\nrows.modules_fold = \"{MODULES_FOLD[0]}\"\nrows.modules_look_y = {MODULES_FOLD[1]}\nrows.layout_folds = {{ " + ", ".join('\"' + f + '\"' for f, _ in PAGE_FOLDS[TAB['Bar & Frame']]) + " }\n"
        "rows.page_folds = { " + ", ".join(f"[{k}] = {{ " + ", ".join('\"' + f + '\"' for f, _ in v) + " }" for k, v in sorted(PAGE_FOLDS.items())) + " }\nreturn rows\n")
    text = SCENE.read_text()
    pat = re.compile(r"([ \t]*)// <gen:edit>\n.*?// </gen:edit>", re.S)
    if not pat.search(text):
        raise SystemExit("marker <gen:edit> not found")
    text = pat.sub(lambda m: f"{m.group(1)}// <gen:edit>\n{edit()}\n{m.group(1)}// </gen:edit>", text)
    SCENE.write_text(text)

if __name__ == "__main__":
    main()
