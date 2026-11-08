-- The Sigil's colour (D207, spec §6): layers, each beating the one below — a fixed colour the owner chose,
-- then a system event (warning amber, error the palette's error, success green), then the album art's colour
-- for music, then the wallpaper's Matugen primary, then mooi's phosphor. Pure; colours are {r, g, b} 0…255.

local M = {}

local PHOS = "#d6e38a"
local EVENT = { warning = "#e3743c", success = "#7fd38a" }

local function rgb(hex)
    local r, g, b = tostring(hex or ""):match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

-- ctx = { palette = palette.json, cover = { hex, … } | nil, event = "warning" | "error" | "success" | nil, settings }
function M.resolve(source_id, ctx)
    ctx = type(ctx) == "table" and ctx or {}
    local sig = type(ctx.settings) == "table" and type(ctx.settings.sigil) == "table" and ctx.settings.sigil or {}
    local colours = type(ctx.palette) == "table" and type(ctx.palette.colours) == "table" and ctx.palette.colours or {}
    if sig.colour == "fixed" and rgb(sig.fixed) then return rgb(sig.fixed) end
    if ctx.event == "error" then return rgb(colours.error) or rgb("#f05c50") end
    if ctx.event and EVENT[ctx.event] then return rgb(EVENT[ctx.event]) end
    if source_id == "music" and type(ctx.cover) == "table" and rgb(ctx.cover[1]) then return rgb(ctx.cover[1]) end
    return rgb(colours.primary) or rgb(PHOS)
end

-- part of the way from cur to want (k 0 … 1), for a colour that eases rather than jumps
function M.ease(cur, want, k)
    local out = {}
    for i = 1, 3 do out[i] = math.floor((cur[i] or 0) + ((want[i] or 0) - (cur[i] or 0)) * k + 0.5) end
    return out
end

return M
