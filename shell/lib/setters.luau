-- One setting to one value, by number: how the settings window (a program of its own,
-- shell/mooi-settings.plm) and mooi agree on what a control means. Pure, so tests/unit runs it.
--
-- `n = 1000 · code + v`. `code` is a place in M.SETTERS (from 1), or 100 + n / 200 + n for
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
}

local function row_of(path)
    for _, row in ipairs(config.SCHEMA) do if row.path == path then return row end end
end

-- Sets it in `settings` (in place). Returns the setting's path, or nil when `n` names nothing
-- or a value the setting cannot take.
function M.apply(settings, n)
    n = math.floor(tonumber(n) or -1)
    local code, v = math.floor(n / 1000), n % 1000
    local order = barlayout.ORDER
    local path
    if code >= 200 and order[code - 199] then path = "bar.modules." .. order[code - 199] .. ".frame"
    elseif code >= 100 and order[code - 99] then path = "bar.modules." .. order[code - 99] .. ".show"
    else path = M.SETTERS[code] end
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
