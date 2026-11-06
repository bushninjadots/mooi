-- A module's own look (D166): what Settings → Bar & Frame → Modules and the bar's edit mode set under
-- bar.modules.<id> (colour, fill, rounding, outline, glow), resolved against the bar's style into the
-- numbers the frame draws a plate with. Pure. A group of modules (`a+b` in a layout list) shares one
-- plate, so its look is stored on, and read from, its first module (its head).

local barlayout = require("lib/barlayout")

local M = {}

-- fill: 0 solid · 1 tinted · 2 glass · 3 none; outline: 0 none · 1 the style's line · 2 accent;
-- glow: 0 off · 1 soft · 2 strong
local FILL = { solid = 0, tinted = 1, glass = 2, none = 3 }
local SURFACE_FILL = { solid = 0, mech = 0, glass = 2, blur = 2, clear = 3 }
local GLOW = { off = 0, soft = 1, strong = 2 }

-- The group's first module for any member of it, else the id itself.
function M.head(s, id)
    local b = type(s) == "table" and s.bar or {}
    for _, side in ipairs({ "left", "center", "right" }) do
        for _, entry in ipairs(type(b[side]) == "table" and b[side] or {}) do
            local ids = barlayout.split(entry)
            if ids then
                for _, x in ipairs(ids) do if x == id then return ids[1] end end
            end
        end
    end
    return id
end

local function hex(v)
    local r, g, b = string.match(v, "^#(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return { r = tonumber(r, 16) / 255, g = tonumber(g, 16) / 255, b = tonumber(b, 16) / 255 }
end

-- `roles`: the palette (lib/ferro's resolved roles, plus `primary` for "from the wallpaper").
function M.of(s, id, roles)
    local b = s.bar
    local mods = type(b.modules) == "table" and b.modules or {}
    local m = mods[M.head(s, id)] or {}
    roles = roles or {}
    local fill = FILL[m.fill] or SURFACE_FILL[b.surface] or 0
    local r = ({ square = 0, soft = 4, round = 10, pill = math.floor((b.height or 24) / 2) })[m.rounding] or b.radius
    local outline
    if m.outline == "none" then outline = 0
    elseif m.outline == "accent" then outline = 2
    else outline = (b.frame == "line") and 1 or 0 end
    local colour = nil
    local c = m.colour
    if type(c) == "string" and c ~= "style" then
        if c == "wallpaper" then colour = roles.primary
        elseif c:sub(1, 1) == "#" then colour = hex(c)
        else colour = roles[c] end
    end
    return { fill = fill, r = r, outline = outline, glow = GLOW[m.glow] or 0, colour = colour }
end

return M
