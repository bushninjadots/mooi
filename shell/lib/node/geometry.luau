-- The node's shapes (D226, spec §3, §8). Pure: each state's body — x, y, w, h, corner — at the anchor, and the parts
-- that grow from it (the rail's stops, the notices' cards, the system's spokes, the launcher's rows). A personality
-- (its look) changes corners, the seed and the top, never the layout's logic. Everything is kept on the screen.

local M = { MARGIN = 16, TOP = 8 }

local SIZE = {
    rest = { 22, 6 }, media = { 440, 64 }, notice = { 180, 10 }, volume = { 280, 16 },
    system = { 44, 44 }, launcher = { 600, 46 }, universe = { 64, 64 },
    time = { 560, 170 }, done = { 440, 76 }, capsule = { 124, 22 }, privacy = { 360, 44 }, battery = { 360, 44 }, player = { 620, 200 },
    media_visualiser = { 420, 46 }, shelf = { 380, 34 }, branch = { 560, 270 }, media_vinyl = { 176, 176 },
}
-- the shape (lib/node/look's M.shape): the seed's size, how round the corners are (0 square … 1 a capsule), and how
-- far from the top it sits; without one, the organic seed
local PLAIN = { seed_w = 22, seed_h = 6, round = 1, top = 8 }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function M.body(kind, scr, anchor, shape, data)
    local W = tonumber(scr and scr.w) or 1920
    shape = type(shape) == "table" and shape or PLAIN
    data = data or {}
    local w, h
    if kind == "workspaces" then
        local n = math.max(1, tonumber(data.n) or 5)
        w, h = n * 56 + 28, 30
    elseif kind == "rest" then
        w, h = tonumber(shape.seed_w) or 22, tonumber(shape.seed_h) or 6
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
    local r = math.min(w, h) / 2 * clamp(tonumber(shape.round) or 1, 0, 1)
    return { x = x, y = tonumber(shape.top) or M.TOP, w = w, h = h, r = r }
end

-- the rail's stops: centres along the body, one per workspace
function M.rail(body, n)
    local out = {}
    local pad = 28
    for i = 1, n do out[i] = body.x + pad / 2 + (i - 0.5) * (body.w - pad) / n end
    return out
end

-- the notices' cards, branching down from the node (a stem, then each card under the last)
-- (D245: `heights` may give a card its own height — one opened to be read — and those under it move down)
function M.cards(body, n, scr, heights)
    local W = tonumber(scr and scr.w) or 1920
    local out = {}
    local cw, chh = 340, 58
    local x = clamp(body.x + body.w / 2 - cw / 2, M.MARGIN, W - M.MARGIN - cw)
    local y = body.y + body.h + 22
    for i = 1, n do
        local h = (type(heights) == "table" and tonumber(heights[i])) or chh
        out[i] = { x = x, y = y, w = cw, h = h }
        y = y + h + 8
    end
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
