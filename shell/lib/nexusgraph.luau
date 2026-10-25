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

-- Routing is pure geometry over two rects. It never looks at the rest of
-- the network, so a drag can re-route one edge per frame without a scan.

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function snapped(v, step)
    if not step or step <= 0 then return v end
    return math.floor(v / step + 0.5) * step
end

function M.port(rect, toward)
    local cx = rect.x + rect.w / 2
    local cy = rect.y + rect.h / 2
    local dx = (toward.x or cx) - cx
    local dy = (toward.y or cy) - cy
    if math.abs(dx) >= math.abs(dy) then
        local east = dx >= 0
        return (east and rect.x + rect.w or rect.x),
            clamp(toward.y or cy, rect.y, rect.y + rect.h),
            (east and "e" or "w")
    end
    local south = dy >= 0
    return clamp(toward.x or cx, rect.x, rect.x + rect.w),
        (south and rect.y + rect.h or rect.y),
        (south and "s" or "n")
end

local function push(points, x, y)
    local last = points[#points]
    if last and last.x == x and last.y == y then return end
    points[#points + 1] = { x = x, y = y }
end

-- Circuit routes are orthogonal with a single dogleg. Ports always face
-- the other node's centre, so an opposite pair needs one mid-axis elbow
-- and a perpendicular pair needs one corner.
function M.route(a, b, opts)
    opts = opts or {}
    if type(a) ~= "table" or type(b) ~= "table" then return {}, false end
    if (a.w or 0) <= 0 or (a.h or 0) <= 0 or (b.w or 0) <= 0 or (b.h or 0) <= 0 then
        return {}, false
    end
    local clearance = tonumber(opts.clearance) or 12
    local step = tonumber(opts.step) or 12
    local ca = { x = a.x + a.w / 2, y = a.y + a.h / 2 }
    local cb = { x = b.x + b.w / 2, y = b.y + b.h / 2 }
    local x1, y1, s1 = M.port(a, cb)
    local x2, y2, s2 = M.port(b, ca)
    if opts.style == "direct" then
        return { { x = x1, y = y1 }, { x = x2, y = y2 } }, true
    end
    if opts.style == "curved" then
        -- Curved routing: use bezier-like smooth curves
        local points = {}
        push(points, x1, y1)
        -- Calculate control points for smooth curve
        local dx = x2 - x1
        local dy = y2 - y1
        local dist = math.sqrt(dx * dx + dy * dy)
        -- Control point offset based on distance
        local offset = math.min(dist * 0.3, 60)
        -- Determine control points based on port directions
        local cx1, cy1 = x1, y1
        local cx2, cy2 = x2, y2
        if s1 == "e" then cx1 = x1 + offset
        elseif s1 == "w" then cx1 = x1 - offset
        elseif s1 == "n" then cy1 = y1 - offset
        elseif s1 == "s" then cy1 = y1 + offset end
        if s2 == "e" then cx2 = x2 + offset
        elseif s2 == "w" then cx2 = x2 - offset
        elseif s2 == "n" then cy2 = y2 - offset
        elseif s2 == "s" then cy2 = y2 + offset end
        -- Generate bezier curve points (simplified to 8 segments for performance)
        local segments = 8
        for i = 1, segments do
            local t = i / segments
            local mt = 1 - t
            local px = mt * mt * mt * x1 + 3 * mt * mt * t * cx1 + 3 * mt * t * t * cx2 + t * t * t * x2
            local py = mt * mt * mt * y1 + 3 * mt * mt * t * cy1 + 3 * mt * t * t * cy2 + t * t * t * y2
            push(points, px, py)
        end
        push(points, x2, y2)
        if #points < 2 then
            push(points, x1, y1 + (step > 0 and step or 1))
        end
        return points, true
    end
    -- Default circuit (orthogonal) routing
    local points = {}
    push(points, x1, y1)
    if x1 ~= x2 and y1 ~= y2 then
        if (s1 == "e" and s2 == "w") or (s1 == "w" and s2 == "e") then
            local lo, hi = math.min(x1, x2), math.max(x1, x2)
            local mid = snapped((x1 + x2) / 2, step)
            if mid <= lo or mid >= hi then mid = (x1 + x2) / 2 end
            push(points, mid, y1)
            push(points, mid, y2)
        elseif (s1 == "n" and s2 == "s") or (s1 == "s" and s2 == "n") then
            local lo, hi = math.min(y1, y2), math.max(y1, y2)
            local mid = snapped((y1 + y2) / 2, step)
            if mid <= lo or mid >= hi then mid = (y1 + y2) / 2 end
            push(points, x1, mid)
            push(points, x2, mid)
        elseif s1 == s2 then
            if s1 == "e" or s1 == "w" then
                local mid = math.max(x1, x2) + clearance + step
                if s1 == "w" then mid = math.min(x1, x2) - clearance - step end
                push(points, mid, y1)
                push(points, mid, y2)
            else
                local mid = math.max(y1, y2) + clearance + step
                if s1 == "n" then mid = math.min(y1, y2) - clearance - step end
                push(points, x1, mid)
                push(points, x2, mid)
            end
        else
            push(points, x2, y1)
        end
    end
    push(points, x2, y2)
    if #points < 2 then
        push(points, x1, y1 + (step > 0 and step or 1))
    end
    return points, true
end

-- True when no segment midpoint sits inside the rect grown by clearance.
function M.clear(points, rect, clearance)
    clearance = clearance or 12
    for i = 2, #points do
        local mx = (points[i].x + points[i - 1].x) / 2
        local my = (points[i].y + points[i - 1].y) / 2
        if mx > rect.x - clearance and mx < rect.x + rect.w + clearance
            and my > rect.y - clearance and my < rect.y + rect.h + clearance then
            return false
        end
    end
    return true
end

return M
