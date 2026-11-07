-- One setting to one value, by number: how the settings window (a program of its own,
-- shell/mooi-settings.plm) and mooi agree on what a control means. Pure, so tests/unit runs it.
--
-- `n = 1000 · code + v`. `code` is a place in M.SETTERS (from 1; past 99, 200 more), or 100 + n / 200 + n for
-- module n's `show` / `frame` (n from 0, in lib/barlayout's ORDER). `v` is an enum value's
-- place in its list (from 0), 0 or 1 for a switch, and for a number its distance from the
-- setting's minimum.

local config = require("lib/config")
local style = require("lib/style")
local barlayout = require("lib/barlayout")

local M = {}

M.SETTERS = {
    "bar.mode", "bar.surface", "bar.frame", "bar.ground", "bar.rail", "bar.accents",
    "bar.workspaces", "bar.helix_frame", "bar.labels", "bar.wheel", "spine.max_workspaces",
    "media.mode", "media.idle", "bar.visualizer",
    "frame.on", "frame.band", "frame.music", "frame.style", "frame.reach", "frame.edges",
    "theme.source", "theme.color_index", "theme.scheme", "theme.signal", "theme.contrast",
    "tray.style", "notifications.server", "atlas.previews", "island.confirm_close",
    "desktop.manage", "desktop.border", "desktop.border_colour", "desktop.gaps_in",
    "desktop.gaps_out", "desktop.rounding", "desktop.dim_inactive",
    -- 37 onwards: the look, the background, the effects, the palette's finish, windows and scrolling
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
    -- D61: the wallpaper studio's defaults, after everything above so no code moved.
    "wallpaper.matte", "wallpaper.backdrop", "wallpaper.key", "wallpaper.fuzz",
    -- D85: the desk (mooi's own wallpaper: parallax, and the cutout over the widgets).
    "desk.on", "desk.parallax", "desk.strength", "desk.depth", "desk.cutout",
    -- D91: day and night, and your own Matugen templates.
    "theme.mode", "theme.light_at", "theme.dark_at", "apps.others",
    -- the corners on every plate
    "look.corners", "look.corner_size",
    -- BMO (shell/bmo), Settings → BMO
    "companion.bmo", "companion.size", "companion.place", "companion.above", "companion.variant",
    "companion.wander", "companion.motion", "companion.throw", "companion.locked", "companion.talk",
    "companion.music", "companion.clock", "companion.react.notes", "companion.react.spaces",
    "companion.react.battery", "companion.react.focus", "companion.react.time",
    -- the bar's islands and the clock (D97)
    "island.style", "clock.view", "shelves.on",
    -- Hyprland 0.56: finer blur, the windows' spring and motion blur
    "desktop.blur_vibrancy", "desktop.blur_xray", "desktop.blur_popups", "desktop.wobble", "desktop.motion_blur",
    -- the Control Nexus (D102): what the mark opens, and the deck's edge
    "nexus.mode", "nexus.edge", "shelves.autohide",
    -- Hyprland 0.57, the Nexus's cards, the notch, Claude
    "desktop.blur_variant", "nexus.rows", "nexus.profile", "nexus.visualiser", "notch.on",
    "nexus.notches", "claude.model",
    -- the bar's islands' feet as the visualiser (bar.foot_visualizer)
    "bar.foot_visualizer",
    -- music on every mooi edge: the master, its strength and the halo
    "music.rim", "music.rim_gain", "music.rim_glow",
    -- how many bars the Control Nexus deck's border is cut into (nexus.bars)
    "nexus.bars",
    -- retired (D118): which Overview opened (atlas.engine); kept so the codes after it do not move
    "atlas.engine",
    -- the Overview's wheel/key desktop stepping and type-to-run
    "atlas.wheel_desktops", "atlas.search_apps", "atlas.search_files",
    "atlas.hot_corner", "atlas.hot_corner_delay",
    -- spring edges: a carried window held at an edge steps the desktops (D115)
    "atlas.spring_edges",
    -- the desktop widgets (D137)
    "widgets.on", "widgets.depth", "widgets.mood",
    -- D144's transition (tools/gen-settings.py had it in the middle of its copy for a day: D147)
    "desk.transition",
    -- the wallpapers (D147): the picker, its look, Wallhaven, the auto-change
    "walls.view", "walls.source", "walls.speed", "walls.veil", "walls.slant", "walls.cards",
    "walls.dots", "walls.swell", "wallhaven.categories", "wallhaven.purity", "wallhaven.sorting",
    "wallhaven.range", "wallhaven.atleast", "wallhaven.ratio", "walls.auto", "walls.auto_every",
    "walls.auto_from", "walls.auto_fullscreen",
    -- D152/D153: the islands grown out of the bar (frame.islands for an hour, the same slot)
    "island.morph",
    -- D157: the workspaces' transition and the scrolling layout as niri's columns
    "desktop.ws_style", "desktop.ws_feel", "desktop.ws_speed", "desktop.ws_swipe",
    "desktop.column_widths", "desktop.column_follow", "desktop.column_wrap", "desktop.column_keys",
    -- D161: how long the session may sit idle before the lock screen takes it (`mooi idle`)
    "lock.idle",
    -- D158: the workspaces' shader transition, as one switch and one choice (lib/wsfx)
    "desktop.ws_fx",
    -- the windows' opening and closing, the same way (lib/wfx; appended, so no code moved)
    "desktop.window_fx", "desktop.window_fx_speed", "desktop.window_fx_apps",
    -- and the shaders' own length and light, shared by both (lib/wsfx, lib/wfx, lib/fxpal)
    "desktop.ws_fx_speed", "desktop.fx_light",
    -- the three colours the `custom` light is drawn in: typed as hex in the settings window (that
    -- window's own event), so their codes set nothing; they are here so a page's Reset names them
    "desktop.fx_phos", "desktop.fx_ember", "desktop.fx_trace",
    -- D160: the lock screen's key (SUPER + L); the idle timeout that locks on its own is lock.idle
    "keys.lock",
    -- and the lock's backdrop: how far the wallpaper behind the plate is blurred and dimmed
    "lock.blur", "lock.dim",
    -- and whether the lock wears the Nexus's banner and its profile picture, each on its own switch
    "lock.banner", "lock.avatar",
    -- Nautilus's own layer on top of apps.gtk (apps.files): the CSS classes apps-sync appends to
    -- gtk.css and Papirus's folders recoloured to the palette. Appended, so no code moved.
    "apps.files",
    -- D159: kitty's own custom shaders (kitty ≥ 0.49): the switch, which pipeline, and the pipeline
    -- of your own that `custom` wears. Appended, so no code moved. The conf is written by
    -- `mooi kitty-shaders` (bin/mooi), never by a scene: the files service stops at mooi's folder.
    "desktop.kitty_shader_on", "desktop.kitty_shader", "desktop.kitty_shader_custom",
    "desktop.kitty_shader_tint", "desktop.kitty_shader_colour",
    -- whether a free model may answer when Claude cannot (claude.free_fallback). Appended, so no code moved.
    "claude.free_fallback",
    -- D166: how much each module shows, and whether islands attach to the frame. Appended, so no code moved.
    "bar.density", "frame.islands",
    -- D168: the Pill — with the side groups, two at once, moons at most. Appended, so no code moved.
    "pill.sides", "pill.multi", "pill.moons",
    -- D169: the Pill's face and hiding when idle. Appended, so no code moved.
    "pill.face", "pill.autohide",
    -- D170: the board's pads and its music visualiser. Appended, so no code moved.
    "pill.pads", "pill.viz",
    -- D171: the Pill's shape, views, detail and rest. Appended, so no code moved.
    "pill.shape", "pill.views", "pill.detail", "pill.rest",
    -- D172: what it does when it is idle — stay, tuck or vanish. Appended, so no code moved.
    "pill.hide",
    -- D174: the Pill's pointer warmth and its ping on a change (Settings → The Pill, the visual page)
    "pill.warmth", "pill.ping",
    -- D175: the desk on the board's first card — its tiles, its surface, its edge
    "pill.desk_clock", "pill.desk_playing", "pill.desk_diagnostics", "pill.desk_calendar",
    "pill.desk_surface", "pill.desk_border",
    -- D176: the desk as the workspace viewer (live miniatures)
    "pill.desk_workspaces",
    -- D177: the desk's sizes and its look (form, tint, glow)
    "pill.desk_clock_size", "pill.desk_playing_size", "pill.desk_diagnostics_size", "pill.desk_calendar_size",
    "pill.desk_form", "pill.desk_tint", "pill.desk_glow",
    -- D179: what the right button does
    "pill.right",
    -- D186: the board's look — a wash of the theme's light over the bar's plate, and its edge
    "pill.board_tint", "pill.board_edge",
    -- D188: the peek. Appended, so no code moved.
    "pill.peek",
}

local function row_of(path)
    for _, row in ipairs(config.SCHEMA) do if row.path == path then return row end end
end

-- Sets it in `settings` (in place). Returns the setting's path, or nil when `n` names nothing
-- or a value the setting cannot take.
-- The setting a control's code names (`list` is M.SETTERS unless a test gives its own). Settings
-- past the 99th go on from 300, above the modules' 100 + n and 200 + n.
function M.path(code, list)
    list = list or M.SETTERS
    local order = barlayout.ORDER
    if code >= 300 then return list[code - 200] end
    if code >= 200 then return order[code - 199] and "bar.modules." .. order[code - 199] .. ".frame" end
    if code >= 100 then return order[code - 99] and "bar.modules." .. order[code - 99] .. ".show" end
    return list[code]
end

function M.apply(settings, n)
    if type(settings) ~= "table" then return nil end   -- nothing to write into: a code that sets nothing
    n = math.floor(tonumber(n) or -1)
    local code, v = math.floor(n / 1000), n % 1000
    local path = M.path(code)
    local row = path and row_of(path)
    if not row then return nil end
    local value
    if row.kind == "boolean" then value = v == 1
    elseif row.kind == "enum" then value = row.values[v + 1]
    elseif row.kind == "integer" then value = math.max(row.min, math.min(row.max, row.min + v)) end
    if value == nil then return nil end
    local node, keys = settings, {}
    for k in string.gmatch(path, "[^.]+") do keys[#keys + 1] = k end
    for i = 1, #keys - 1 do node = node[keys[i]] end
    node[keys[#keys]] = value
    -- a preset writes the settings it stands for
    if path == "bar.style" then style.apply_preset(settings, style.BAR_PRESETS, value) end
    if path == "theme.preset" then style.apply_preset(settings, style.THEME_PRESETS, value) end
    if path == "bar.edge" then style.apply_edge(settings, value) end
    if path == "frame.motion" then style.apply_motion(settings, value) end
    return path
end

-- Where a choice sits in its setting's list, from 0: how an enum reaches a scene.
function M.position(path, value)
    local row = row_of(path)
    if row and row.values then
        for i, v in ipairs(row.values) do if v == value then return i - 1 end end
    end
    return 0
end

return M
