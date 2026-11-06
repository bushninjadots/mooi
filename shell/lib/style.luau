-- The bar's look as the scene reads it: settings → facts (`st_*`). Pure, so tests/unit runs it;
-- mooi.luau and the settings window (mooi-settings.luau) both paint from it, so the two cannot
-- read a setting two ways. Colours are not here: lib/ferro builds them (the background too).

local M = {}

local OUTLINE_WIDTH = { 1.0, 1.4, 2.0 }             -- thin, regular, bold
-- How each shadow choice falls: offset down, blur, strength (0 to 1).
local SHADOW = { off = { 0, 0, 0 }, soft = { 2, 10, 0.28 }, medium = { 4, 16, 0.42 }, strong = { 6, 24, 0.62 } }

local function index_of(list, value)
    for i, v in ipairs(list) do if v == value then return i - 1 end end
    return 0
end

-- ── Presets ────────────────────────────────────────────────
-- A preset is a coherent set of the finer settings, written all at once: the bar's material,
-- outline, depth and hover belong together, and so do a palette's finish, base and light — set
-- one by one they can fight (a clear bar with a deep shadow, a light base with a neon glow).
M.BAR_PRESETS = {
    -- an instrument panel: solid hull, a regular line with its cuts, the rail and the details on
    { name = "instrument", set = { ["bar.surface"] = "solid", ["bar.frame"] = "line", ["bar.outline_width"] = 2, ["bar.outline_colour"] = "subtle",
        ["bar.shadow"] = "off", ["bar.ground"] = "black", ["bar.pill"] = "soft", ["bar.opacity"] = 100, ["bar.rail"] = true, ["bar.accents"] = true , ["bar.frost"] = 70, ["bar.smoke"] = 38} },
    -- glass: bent and frosted, a thin bright edge, a soft shadow, nothing else
    { name = "glass", set = { ["bar.surface"] = "glass", ["bar.frame"] = "line", ["bar.outline_width"] = 1, ["bar.outline_colour"] = "bright",
        ["bar.shadow"] = "soft", ["bar.ground"] = "clear", ["bar.pill"] = "outline", ["bar.opacity"] = 85, ["bar.frost"] = 60, ["bar.smoke"] = 30,
        ["bar.rail"] = false, ["bar.accents"] = false } },
    -- floating: solid islands with no edge, lifted by a strong shadow, glowing under the pointer
    { name = "floating", set = { ["bar.surface"] = "solid", ["bar.frame"] = "none", ["bar.outline_width"] = 2, ["bar.outline_colour"] = "subtle",
        ["bar.shadow"] = "strong", ["bar.ground"] = "clear", ["bar.pill"] = "glow", ["bar.opacity"] = 100, ["bar.rail"] = false, ["bar.accents"] = false , ["bar.frost"] = 0, ["bar.smoke"] = 0} },
    -- hairline (D166): no fill at all, only an accent line, so the wallpaper shows through
    { name = "hairline", set = { ["bar.surface"] = "clear", ["bar.frame"] = "line", ["bar.outline_width"] = 1, ["bar.outline_colour"] = "accent",
        ["bar.shadow"] = "off", ["bar.ground"] = "clear", ["bar.pill"] = "underline", ["bar.opacity"] = 100, ["bar.rail"] = false, ["bar.accents"] = false , ["bar.frost"] = 0, ["bar.smoke"] = 0} },
    -- minimal: only the readings on the desktop, an underline for hover
    { name = "minimal", set = { ["bar.surface"] = "clear", ["bar.frame"] = "none", ["bar.outline_width"] = 2, ["bar.outline_colour"] = "subtle",
        ["bar.shadow"] = "off", ["bar.ground"] = "clear", ["bar.pill"] = "underline", ["bar.opacity"] = 100, ["bar.rail"] = false, ["bar.accents"] = false , ["bar.frost"] = 0, ["bar.smoke"] = 0} },
    -- (steel was removed in D166: its look stays reachable as the mech surface with an accent line)
}
M.THEME_PRESETS = {
    { name = "phosphor", set = { ["theme.finish"] = "luminous", ["theme.saturation"] = 0, ["bar.bg"] = "black", ["bar.bg_light"] = 0,
        ["bar.bg_sat"] = 100, ["bar.bg_hue"] = 0, ["fx.glow"] = 100, ["fx.aberration"] = 0 } },
    { name = "neon_noir", set = { ["theme.finish"] = "neon", ["theme.saturation"] = 20, ["bar.bg"] = "obsidian", ["bar.bg_light"] = 0,
        ["bar.bg_sat"] = 100, ["bar.bg_hue"] = 0, ["fx.glow"] = 120, ["fx.aberration"] = 15 } },
    { name = "concrete", set = { ["theme.finish"] = "matte", ["theme.saturation"] = -20, ["bar.bg"] = "concrete", ["bar.bg_light"] = 0,
        ["bar.bg_sat"] = 100, ["bar.bg_hue"] = 0, ["fx.glow"] = 60, ["fx.aberration"] = 0 } },
    { name = "gunmetal", set = { ["theme.finish"] = "luminous", ["theme.saturation"] = 0, ["bar.bg"] = "gunmetal", ["bar.bg_light"] = 0,
        ["bar.bg_sat"] = 100, ["bar.bg_hue"] = 0, ["fx.glow"] = 100, ["fx.aberration"] = 0 } },
    { name = "alien", set = { ["theme.finish"] = "neon", ["theme.saturation"] = 10, ["bar.bg"] = "alien", ["bar.bg_light"] = 0,
        ["bar.bg_sat"] = 120, ["bar.bg_hue"] = 0, ["fx.glow"] = 130, ["fx.aberration"] = 25 } },
    { name = "titanium", set = { ["theme.finish"] = "matte", ["theme.saturation"] = -40, ["bar.bg"] = "titanium", ["bar.bg_light"] = 0,
        ["bar.bg_sat"] = 60, ["bar.bg_hue"] = 0, ["fx.glow"] = 50, ["fx.aberration"] = 0 } },
}

local function get(s, path)
    local v = s
    for k in string.gmatch(path, "[^.]+") do if type(v) ~= "table" then return nil end; v = v[k] end
    return v
end
local function put(s, path, value)
    local keys = {}
    for k in string.gmatch(path, "[^.]+") do keys[#keys + 1] = k end
    local node = s
    for i = 1, #keys - 1 do node[keys[i]] = node[keys[i]] or {}; node = node[keys[i]] end
    node[keys[#keys]] = value
end

function M.apply_preset(s, presets, name)
    for _, p in ipairs(presets) do
        if p.name == name then for path, v in pairs(p.set) do put(s, path, v) end end
    end
end

-- The edge as one choice: none, corners, or a line thin / regular / bold.
local EDGES = { none = { "none", 2 }, corners = { "corners", 2 }, thin = { "line", 1 }, regular = { "line", 2 }, bold = { "line", 3 } }
function M.apply_edge(s, name)
    local e = EDGES[name]
    if e then put(s, "bar.frame", e[1]); put(s, "bar.outline_width", e[2]) end
end
function M.edge_index(s)
    local f, w = s.bar.frame, s.bar.outline_width
    if f == "none" then return 0 elseif f == "corners" then return 1 end
    return 1 + w                      -- thin 2 · regular 3 · bold 4
end
-- The frame's music as one choice: off, or how it moves.
function M.apply_motion(s, name)
    if name == "off" then put(s, "frame.music", false)
    elseif name then put(s, "frame.music", true); put(s, "frame.style", name == "ripples" and "crests" or name) end
end
function M.motion_index(s)
    if not s.frame.music then return 0 end
    return ({ swell = 1, crests = 2, pulse = 3 })[s.frame.style] or 1
end

-- Which preset the settings are now, from 0, or #presets when none matches ("Custom").
function M.preset_index(s, presets)
    for i, p in ipairs(presets) do
        local same = true
        for path, v in pairs(p.set) do if get(s, path) ~= v then same = false end end
        if same then return i - 1 end
    end
    return #presets
end

-- `s` is validated settings (lib/config). Returns { fact name = value }.
function M.facts(s)
    local b, fx = s.bar, s.fx
    local sh = SHADOW[b.shadow] or SHADOW.off
    -- The row's top: the edge distance, then a notch's 6 px, the rail's 15 or the plain 8.
    local top = b.offset + ((b.mode == "notch") and 6 or (b.rail and 15 or 8))
    return {
        st_notch = b.mode == "notch",
        st_radius = b.radius,
        st_owidth = OUTLINE_WIDTH[b.outline_width] or 1.4,
        st_ocol = index_of({ "subtle", "bright", "accent" }, b.outline_colour),
        st_pill = index_of({ "soft", "outline", "underline", "glow" }, b.pill),
        st_sh_y = sh[1], st_sh_blur = sh[2], st_sh_a = sh[3],
        st_opacity = b.opacity / 100,
        st_frost = b.frost,
        st_smoke = b.smoke,
        st_aberr = fx.aberration / 100,
        st_glow = ({ matte = 0.25, luminous = 1, neon = 1.7 })[s.theme.finish] * fx.glow / 100,
        st_wheel = index_of({ "step", "off", "invert" }, b.wheel),
        st_width = b.width / 100,
        st_height = b.height,
        st_offset = b.offset,
        -- the strip the windows leave the bar: down to the row's foot and a pixel of air
        st_res = top + b.height + 1,
        st_frame_r = s.frame.radius,
        st_frame_edge = index_of({ "line", "neon", "none" }, s.frame.edge),
        st_frame_op = s.frame.opacity / 100,
    }
end

-- Corners, everywhere mooi draws a plate (look.corners, look.corner_size): which shape — 0 chamfer
-- (Ferrolume's two cut corners), 1 bevel (all four cut), 2 rounded, 3 square — and a scale on each
-- component's own designed corner (12 is as designed; square has none).
M.CORNERS = { "chamfer", "bevel", "round", "square" }
function M.corners(s)
    local l = type(s) == "table" and type(s.look) == "table" and s.look or {}
    local k = 0
    for i, v in ipairs(M.CORNERS) do if v == l.corners then k = i - 1 end end
    local size = tonumber(l.corner_size) or 12
    return k, k == 3 and 0 or size / 12
end

return M
