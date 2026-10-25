-- Layout maths for the Nexus canvas. Pure: no services, no facts, no state.
-- The scene feeds node rectangles in and gets rectangles back, so a drag can
-- re-run this every frame without touching the settings or the renderer.

local nexusnode = require("lib/nexusnode")

local M = {}

local GUTTER = 20

local function finite(n, fallback)
    n = tonumber(n)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then
        return fallback
    end
    return n
end

-- Round to the nearest grid line. A zero grid means "leave it alone", which is
-- how the reduced/positioning-off mode passes through untouched.
function M.snap(v, grid)
    grid = tonumber(grid) or 0
    if grid <= 0 then return v end
    return math.floor((v + grid / 2) / grid) * grid
end

-- Keep the whole node on the canvas. A node larger than the canvas is pinned
-- to the top-left rather than given a negative ceiling.
function M.clamp(x, y, w, h, canvas)
    w, h = finite(w, 0), finite(h, 0)
    local maxx = math.max(0, canvas.w - w)
    local maxy = math.max(0, canvas.h - h)
    local cx = math.max(0, math.min(finite(x, 0), maxx))
    local cy = math.max(0, math.min(finite(y, 0), maxy))
    return cx, cy
end

function M.bounds(id, w, h)
    local def = nexusnode.get(id)
    if not def then return w, h end
    w = math.max(def.min.w, math.min(def.max.w, finite(w, def.size.w)))
    h = math.max(def.min.h, math.min(def.max.h, finite(h, def.size.h)))
    return w, h
end

-- Padding inflates both boxes, so free_slot can keep a real gutter.
function M.overlap(a, b, pad)
    pad = pad or 0
    return a.x < b.x + b.w + pad and b.x < a.x + a.w + pad
        and a.y < b.y + b.h + pad and b.y < a.y + a.h + pad
end

-- First grid position that keeps the new node clear of the existing ones.
function M.free_slot(nodes, id, canvas, grid)
    grid = math.max(tonumber(grid) or 8, 8)
    local def = nexusnode.get(id)
    local w = def and def.size.w or 200
    local h = def and def.size.h or 120
    local y = 0
    while y + h <= canvas.h do
        local x = 0
        while x + w <= canvas.w do
            local box = { x = x, y = y, w = w, h = h }
            local clear = true
            for _, n in ipairs(nodes) do
                if M.overlap(box, n, 8) then
                    clear = false
                    break
                end
            end
            if clear then return x, y end
            x = x + grid
        end
        y = y + grid
    end
    return M.clamp(0, 0, w, h, canvas)
end

-- Scale an arrangement that outgrows the canvas. Sizes are kept: shrinking a
-- node's text is worse than letting two nodes overlap after a clamp.
function M.fit(nodes, canvas)
    if #nodes == 0 then return nodes end
    local maxx, maxy = 0, 0
    for _, n in ipairs(nodes) do
        maxx = math.max(maxx, n.x + n.w)
        maxy = math.max(maxy, n.y + n.h)
    end
    if maxx <= canvas.w and maxy <= canvas.h then return nodes end
    local s = math.min(
        (canvas.w - GUTTER) / math.max(maxx, 1),
        (canvas.h - GUTTER) / math.max(maxy, 1)
    )
    local out = {}
    for i, n in ipairs(nodes) do
        local copy = {}
        for k, v in pairs(n) do copy[k] = v end
        copy.x, copy.y = M.clamp(M.snap(n.x * s, 8), M.snap(n.y * s, 8), n.w, n.h, canvas)
        out[i] = copy
    end
    return out
end

-- Repack into reading order. Used by TIDY on a canvas too small for the
-- arrangement the user built on a larger screen.
function M.tidy(nodes, canvas, grid)
    grid = math.max(tonumber(grid) or 8, 8)
    local out, x, y, rowh = {}, 0, 0, 0
    for i, n in ipairs(nodes) do
        if x > 0 and x + n.w > canvas.w then
            x = 0
            y = y + rowh + grid
            rowh = 0
        end
        local copy = {}
        for k, v in pairs(n) do copy[k] = v end
        copy.x, copy.y = M.clamp(x, y, n.w, n.h, canvas)
        out[i] = copy
        x = x + n.w + grid
        rowh = math.max(rowh, n.h)
    end
    return out
end

-- Any node can take the centre. The displaced centre inherits the target's
-- old slot, and every unrelated node keeps its position.
function M.focus(nodes, id, canvas)
    local target, ti
    for i, n in ipairs(nodes) do
        if n.type == id then
            target, ti = n, i
            break
        end
    end
    if not target then return nodes, false end

    local cx, cy = canvas.w / 2, canvas.h / 2
    local best, besti, bestarea = nil, nil, 0
    for i, n in ipairs(nodes) do
        if n.x <= cx and cx <= n.x + n.w and n.y <= cy and cy <= n.y + n.h then
            local area = n.w * n.h
            if area > bestarea then
                best, besti, bestarea = n, i, area
            end
        end
    end
    if besti == ti then return nodes, false end

    local def = nexusnode.get(id)
    local dw, dh = target.w, target.h
    if def then dw, dh = def.detail.w, def.detail.h end

    local out = {}
    for i, n in ipairs(nodes) do
        local copy = {}
        for k, v in pairs(n) do copy[k] = v end
        out[i] = copy
    end
    if best then
        local ox, oy = M.clamp(target.x, target.y, best.w, best.h, canvas)
        out[besti].x, out[besti].y = ox, oy
    end
    local nx, ny = M.clamp(cx - dw / 2, cy - dh / 2, dw, dh, canvas)
    out[ti].x, out[ti].y = nx, ny
    out[ti].w, out[ti].h = dw, dh
    return out, true
end

-- One keyboard nudge, snapped and clamped.
function M.move_step(node, dx, dy, canvas, grid)
    grid = tonumber(grid) or 0
    local x = M.snap(node.x + dx * grid, grid)
    local y = M.snap(node.y + dy * grid, grid)
    return M.clamp(x, y, node.w, node.h, canvas)
end

-- ── arrangement operations ───────────────────────────────────
-- A drop, a resize and a restore all end the same way: the node in the arrangement
-- holds snapped, clamped numbers, and the caller decides when to persist. Each
-- returns whether anything changed, so a no-op never costs a settings write.

-- Move a node to a canvas position. The scene clamps too, so an off-canvas drop
-- from a narrow window cannot put the node somewhere it can never be grabbed again.
function M.place(node, x, y, canvas, grid)
    if type(node) ~= "table" or not canvas then return false end
    local px, py = M.clamp(M.snap(tonumber(x) or node.x, grid), M.snap(tonumber(y) or node.y, grid),
        node.w, node.h, canvas)
    if px == node.x and py == node.y then return false end
    node.x, node.y = px, py
    return true
end

-- Resize within the type's min/max. Snapping happens before the bounds so the grip
-- cannot step a node past its own limit.
function M.resize(node, w, h, grid)
    if type(node) ~= "table" then return false end
    local nw, nh = M.bounds(node.type, tonumber(w) or node.w, tonumber(h) or node.h)
    nw, nh = M.bounds(node.type, M.snap(nw, grid), M.snap(nh, grid))
    if nw == node.w and nh == node.h then return false end
    node.w, node.h = nw, nh
    return true
end

-- A removed node keeps its slot in the arrangement, so removing never shifts the
-- indices the scene holds. Restoring re-hides nothing: a node that would land on
-- a neighbour goes to the first free slot instead.
function M.restore(nodes, index, canvas, grid)
    if type(nodes) ~= "table" or not canvas then return false end
    local node = nodes[index]
    if type(node) ~= "table" or node.vis then return false end
    local others = {}
    for i, other in ipairs(nodes) do
        if i ~= index and other.vis then others[#others + 1] = other end
    end
    local clash = false
    for _, other in ipairs(others) do
        if M.overlap(node, other, 0) then
            clash = true
            break
        end
    end
    if clash then
        node.x, node.y = M.free_slot(others, node.type, canvas, grid)
    end
    node.x, node.y = M.clamp(node.x, node.y, node.w, node.h, canvas)
    node.vis = true
    return true
end

return M
