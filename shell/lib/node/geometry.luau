-- The node's shapes (D226, spec §3, §8). Pure: each state's body — x, y, w, h, corner — at the anchor, and the parts
-- that grow from it (the rail's stops, the notices' cards, the system's spokes, the launcher's rows). A personality
-- changes corners and the seed, never the layout's logic. Everything is kept on the screen.

local M = { MARGIN = 16, TOP = 8 }

local SIZE = {
    rest = { 22, 6 }, media = { 440, 64 }, notice = { 180, 10 }, volume = { 280, 16 },
    system = { 44, 44 }, launcher = { 600, 46 }, universe = { 64, 64 },
}
local CORNER = { minimal = 1, organic = 1, technical = 0.18, cyber = 0.32 }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function M.body(kind, scr, anchor, personality, data)
    local W = tonumber(scr and scr.w) or 1920
    data = data or {}
    local w, h
    if kind == "workspaces" then
        local n = math.max(1, tonumber(data.n) or 5)
        w, h = n * 56 + 28, 30
    elseif kind == "rest" and personality == "minimal" then
        w, h = 6, 6
    else
        local s = SIZE[kind] or SIZE.rest
        w, h = s[1], s[2]
    end
    w = math.min(w, W - 2 * M.MARGIN)
    local x
    if anchor == "left" then x = M.MARGIN
    elseif anchor == "right" then x = W - M.MARGIN - w
    else x = (W - w) / 2 end
    x = clamp(x, 0, W - w)
    local r = math.min(w, h) / 2 * (CORNER[personality] or 1)
    return { x = x, y = M.TOP, w = w, h = h, r = r }
end

-- the rail's stops: centres along the body, one per workspace
function M.rail(body, n)
    local out = {}
    local pad = 28
    for i = 1, n do out[i] = body.x + pad / 2 + (i - 0.5) * (body.w - pad) / n end
    return out
end

-- the notices' cards, branching down from the node (a stem, then each card under the last)
function M.cards(body, n, scr)
    local W = tonumber(scr and scr.w) or 1920
    local out = {}
    local cw, chh = 340, 58
    local x = clamp(body.x + body.w / 2 - cw / 2, M.MARGIN, W - M.MARGIN - cw)
    for i = 1, n do out[i] = { x = x, y = body.y + body.h + 22 + (i - 1) * (chh + 8), w = cw, h = chh } end
    return out
end

-- the system's spokes: points round the node (below it, left to right)
function M.spokes(body, n)
    local out = {}
    local cx, cy = body.x + body.w / 2, body.y + body.h / 2
    for i = 1, n do
        local a = math.rad(180 - (i - 0.5) * 180 / n)
        out[i] = { x = cx + math.cos(a) * 120, y = cy + math.sin(a) * 70 + 30 }
    end
    return out
end

-- the launcher's rows, growing down from the search line
function M.results(body, n)
    local out = {}
    for i = 1, n do out[i] = { x = body.x, y = body.y + body.h + 8 + (i - 1) * 46, w = body.w, h = 42 } end
    return out
end

return M
