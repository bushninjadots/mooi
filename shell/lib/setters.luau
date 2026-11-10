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
    "bar.mode",
    "bar.surface",
    "bar.frame",
    "bar.ground",
    "bar.rail",
    "bar.accents",
    "bar.workspaces",
    "bar.helix_frame",
    "bar.labels",
    "bar.wheel",
    "spine.max_workspaces",
    "media.mode",
    "media.idle",
    "bar.visualizer",
    "frame.on",
    "frame.band",
    "frame.music",
    "frame.style",
    "frame.reach",
    "frame.edges",
    "theme.source",
    "theme.color_index",
    "theme.scheme",
    "theme.signal",
    "theme.contrast",
    "tray.style",
    "notifications.server",
    "atlas.previews",
    "island.confirm_close",
    "desktop.manage",
    "desktop.border",
    "desktop.border_colour",
    "desktop.gaps_in",
    "desktop.gaps_out",
    "desktop.rounding",
    "desktop.dim_inactive",
    "bar.radius",
    "bar.outline_width",
    "bar.outline_colour",
    "bar.pill",
    "bar.shadow",
    "bar.opacity",
    "bar.frost",
    "bar.smoke",
    "bar.bg",
    "bar.bg_light",
    "bar.bg_sat",
    "bar.bg_hue",
    "fx.aberration",
    "fx.glow",
    "theme.finish",
    "theme.saturation",
    "desktop.layout",
    "desktop.column",
    "desktop.column_fit",
    "desktop.touchpad_natural",
    "desktop.touchpad_speed",
    "desktop.mouse_natural",
    "desktop.mouse_speed",
    "desktop.blur",
    "desktop.opacity_active",
    "desktop.opacity_inactive",
    "desktop.shadow",
    "desktop.shadow_size",
    "bar.style",
    "theme.preset",
    "motion.reduced",
    "island.follow_on_send",
    "command.max_results",
    "bar.width",
    "bar.edge",
    "frame.motion",
    "frame.radius",
    "frame.edge",
    "frame.opacity",
    "bar.height",
    "bar.offset",
    "apps.kitty",
    "apps.gtk",
    "apps.qt",
    "motion.speed",
    "motion.saver",
    "power.profile",
    "notifications.dnd",
    "notifications.quiet_from",
    "notifications.quiet_to",
    "shutter.enabled",
    "shutter.pointer",
    "shutter.edge",
    "shutter.density",
    "shutter.preview",
    "shutter.arrange",
    "shutter.workspace",
    "shutter.behaviour",
    "shutter.connections",
    "atlas.rows",
    "atlas.columns",
    "atlas.super_tab",
    "atlas.overview",
    "atlas.private",
    "atlas.size",
    "atlas.dim",
    "atlas.zoom",
    "atlas.refresh",
    "atlas.gesture",
    "session.standalone",
    "signals.edge",
    "signals.max",
    "signals.linger",
    "signals.grouping",
    "signals.density",
    "signals.chamfer",
    "signals.travel",
    "signals.effects",
    "signals.private",
    "wallpaper.matte",
    "wallpaper.backdrop",
    "wallpaper.key",
    "wallpaper.fuzz",
    "desk.on",
    "desk.parallax",
    "desk.strength",
    "desk.depth",
    "desk.cutout",
    "theme.mode",
    "theme.light_at",
    "theme.dark_at",
    "apps.others",
    "look.corners",
    "look.corner_size",
    "companion.bmo",
    "companion.size",
    "companion.place",
    "companion.above",
    "companion.variant",
    "companion.wander",
    "companion.motion",
    "companion.throw",
    "companion.locked",
    "companion.talk",
    "companion.music",
    "companion.clock",
    "companion.react.notes",
    "companion.react.spaces",
    "companion.react.battery",
    "companion.react.focus",
    "companion.react.time",
    "island.style",
    "clock.view",
    "shelves.on",
    "desktop.blur_vibrancy",
    "desktop.blur_xray",
    "desktop.blur_popups",
    "desktop.wobble",
    "desktop.motion_blur",
    "nexus.mode",
    "nexus.edge",
    "shelves.autohide",
    "desktop.blur_variant",
    "nexus.rows",
    "nexus.profile",
    "nexus.visualiser",
    "notch.on",
    "nexus.notches",
    "claude.model",
    "bar.foot_visualizer",
    "music.rim",
    "music.rim_gain",
    "music.rim_glow",
    "nexus.bars",
    "atlas.engine",
    "atlas.wheel_desktops",
    "atlas.search_apps",
    "atlas.search_files",
    "atlas.hot_corner",
    "atlas.hot_corner_delay",
    "atlas.spring_edges",
    "widgets.on",
    "widgets.depth",
    "widgets.mood",
    "desk.transition",
    "walls.view",
    "walls.source",
    "walls.speed",
    "walls.veil",
    "walls.slant",
    "walls.cards",
    "walls.dots",
    "walls.swell",
    "wallhaven.categories",
    "wallhaven.purity",
    "wallhaven.sorting",
    "wallhaven.range",
    "wallhaven.atleast",
    "wallhaven.ratio",
    "walls.auto",
    "walls.auto_every",
    "walls.auto_from",
    "walls.auto_fullscreen",
    "island.morph",
    "desktop.ws_style",
    "desktop.ws_feel",
    "desktop.ws_speed",
    "desktop.ws_swipe",
    "desktop.column_widths",
    "desktop.column_follow",
    "desktop.column_wrap",
    "desktop.column_keys",
    "lock.idle",
    "desktop.ws_fx",
    "desktop.window_fx",
    "desktop.window_fx_speed",
    "desktop.window_fx_apps",
    "desktop.ws_fx_speed",
    "desktop.fx_light",
    "desktop.fx_phos",
    "desktop.fx_ember",
    "desktop.fx_trace",
    "keys.lock",
    "lock.blur",
    "lock.dim",
    "lock.banner",
    "lock.avatar",
    "apps.files",
    "desktop.kitty_shader_on",
    "desktop.kitty_shader",
    "desktop.kitty_shader_custom",
    "desktop.kitty_shader_tint",
    "desktop.kitty_shader_colour",
    "claude.free_fallback",
    "bar.density",
    "frame.islands",
    "pill.sides",
    "surface.on",
    "surface.delay",
    "surface.effect",
    "surface.bmo_below",
    "surface.intensity",
    "surface.edge",
    "surface.colour",
    "surface.speed",
    "surface.radius",
    "surface.wall",
    "surface.dim",
    "surface.tint",
    "surface.fit",
    "surface.grid",
    "surface.labels",
    "surface.glow",
    "surface.ping",
    "surface.layout",
    "surface.components",
    "surface.bmo_side",
    "surface.overview",
    "surface.power_confirm",
    "surface.widget_style",
    "companion.eyes",
    "companion.cheek",
    "companion.hands",
    "companion.react.herdr",
    "companion.react.browser",
    "herdr.path",
    "herdr.poll",
    "herdr.show_idle",
    "herdr.show_done",
    "herdr.brief",
    "herdr.brief_lines",
    "herdr.focus_on_open",
    -- D217: push up from below. Appended.
    "surface.push", "surface.trace",
    -- D219: Live wallpaper. Appended.
    "live.on", "live.where", "live.speed",
    "live.ripple.on", "live.ripple.strength", "live.ripple.size", "live.ripple.blend",
    "live.breathe.on", "live.breathe.strength", "live.breathe.size", "live.breathe.blend",
    "live.flow.on", "live.flow.strength", "live.flow.size", "live.flow.blend",
    "live.sweep.on", "live.sweep.strength", "live.sweep.size", "live.sweep.blend",
    -- D223: Music in the picture. Appended.
    "live.music.on", "live.music.strength", "live.music.size", "live.music.blend", "live.music.height",
    -- D226: the node (the Dynamic Pill). Appended.
    "node.on", "node.pointer", "node.anchor", "node.media", "node.notices",
    "node.workspaces", "node.volume", "node.system", "node.wallpaper",
    "keys.node_launch", "keys.node_universe", "keys.node_time", "node.privacy", "node.lyrics",
    -- D267: the shortcut sheet. Appended.
    "keys.node_keys",
    -- D271: holding Super is its own switch; the Overview's key. Appended.
    "surface.hold", "keys.surface",
    -- D275: the side drawers. Appended.
    "drawers.on", "drawers.dashboard", "drawers.notices", "drawers.edge", "drawers.github", "drawers.quote",
    "keys.drawer_left", "keys.drawer_right",
    -- D276: the arcade. Appended.
    "keys.arcade",
    -- D280: the dock. Appended.
    "dock.on", "dock.empty", "keys.dock",
    -- D281. Appended.
    "keys.ask",
    -- D289. Appended.
    "keys.term",
    -- D293: the charge limit. Appended.
    "power.charge_limit",
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
