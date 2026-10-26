-- The Control Nexus connection graph.
--
-- Relationships are authored here, not discovered: every edge states what
-- it means, so a drawn line never implies an integration that does not
-- exist. Rendering and interaction live in the scene.

local M = {}

-- Draw order is trunk first: the core bus sits under the satellite
-- signals so a busy node never hides the spine of the network.
M.EDGES = {
    { id = "core-system", from = "core", to = "system", kind = "trunk", label = "SYSTEM", meaning = "core bus" },
    { id = "core-network", from = "core", to = "network", kind = "trunk", label = "LINK", meaning = "core bus" },
    { id = "core-audio", from = "core", to = "audio", kind = "trunk", label = "AUDIO", meaning = "core bus" },
    { id = "core-workspaces", from = "core", to = "workspaces", kind = "trunk", label = "SPACES", meaning = "core bus" },
    { id = "core-storage", from = "core", to = "storage", kind = "trunk", label = "STORE", meaning = "core bus" },

    { id = "cpu-system", from = "cpu", to = "system", kind = "signal", label = "LOAD", meaning = "processor load", activity = "cpu" },
    { id = "memory-system", from = "memory", to = "system", kind = "signal", label = "MEM", meaning = "memory pressure", activity = "memory" },
    { id = "gpu-system", from = "gpu", to = "system", kind = "signal", label = "GPU", meaning = "graphics load", activity = "gpu" },
    { id = "thermal-system", from = "thermal", to = "system", kind = "signal", label = "TEMP", meaning = "thermals", activity = "thermal" },
    { id = "power-system", from = "power", to = "system", kind = "signal", label = "PWR", meaning = "power draw", activity = "power" },
    { id = "storage-system", from = "storage", to = "system", kind = "signal", label = "DISK", meaning = "capacity", activity = "storage" },
    { id = "storage-files", from = "storage", to = "files", kind = "signal", label = "FILES", meaning = "storage appears in Files" },
    { id = "network-system", from = "network", to = "system", kind = "signal", label = "NET", meaning = "throughput", activity = "network" },
    { id = "audio-media", from = "audio", to = "media", kind = "signal", label = "MEDIA", meaning = "playback", activity = "media" },
    { id = "workspaces-applications", from = "workspaces", to = "applications", kind = "signal", label = "APPS", meaning = "windows in spaces" },
}

-- `types` is a set of node ids the caller has decided are drawable. Both
-- ends must exist; availability is the caller's judgement, not ours.
function M.instantiate(types)
    local edges = {}
    for _, edge in ipairs(M.EDGES) do
        if types[edge.from] and types[edge.to] then
            edges[#edges + 1] = edge
        end
    end
    return edges
end

function M.count(edges)
    return #edges
end

-- The edges the scene can ever draw, in authored order: both ends need a slot (see
-- nexusnode.SLOTS). The scene keeps one trace per row, so this order is its order.
function M.drawable(slot)
    local out = {}
    for _, edge in ipairs(M.EDGES) do
        local a, b = slot(edge.from), slot(edge.to)
        if a and b then out[#out + 1] = { edge = edge, a = a, b = b } end
    end
    return out
end

-- The geometry of a trace between two rects, exactly as the scene draws it (the scene
-- computes the same sums every frame, so a trace follows a node while it is carried or
-- while it springs to a new place). The ports sit on the two sides that face each other
-- across the wider gap; where those sides overlap by a row's height the trace runs straight,
-- otherwise each port slides toward the other node's centre and the trace turns once on
-- the middle line `m`. `hz` says whether it leaves sideways (true) or up and down.
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

M.PORT_INSET = 12
M.STRAIGHT = 24

function M.trace(a, b)
    local gapx = math.max(b.x - (a.x + a.w), a.x - (b.x + b.w))
    local gapy = math.max(b.y - (a.y + a.h), a.y - (b.y + b.h))
    local acx, acy = a.x + a.w / 2, a.y + a.h / 2
    local bcx, bcy = b.x + b.w / 2, b.y + b.h / 2
    local t = { hz = gapx >= gapy }
    if t.hz then
        local east = bcx >= acx
        t.x1 = east and a.x + a.w or a.x
        t.x2 = east and b.x or b.x + b.w
        local lo, hi = math.max(a.y, b.y), math.min(a.y + a.h, b.y + b.h)
        if hi - lo >= M.STRAIGHT then
            t.y1 = (lo + hi) / 2
            t.y2 = t.y1
        else
            t.y1 = clamp(bcy, a.y + M.PORT_INSET, a.y + a.h - M.PORT_INSET)
            t.y2 = clamp(acy, b.y + M.PORT_INSET, b.y + b.h - M.PORT_INSET)
        end
        t.m = (t.x1 + t.x2) / 2
    else
        local south = bcy >= acy
        t.y1 = south and a.y + a.h or a.y
        t.y2 = south and b.y or b.y + b.h
        local lo, hi = math.max(a.x, b.x), math.min(a.x + a.w, b.x + b.w)
        if hi - lo >= M.STRAIGHT then
            t.x1 = (lo + hi) / 2
            t.x2 = t.x1
        else
            t.x1 = clamp(bcx, a.x + M.PORT_INSET, a.x + a.w - M.PORT_INSET)
            t.x2 = clamp(acx, b.x + M.PORT_INSET, b.x + b.w - M.PORT_INSET)
        end
        t.m = (t.y1 + t.y2) / 2
    end
    return t
end

return M
