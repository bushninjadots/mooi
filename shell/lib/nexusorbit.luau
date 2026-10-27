-- The orbital Control Nexus (D99): the nodes that can circle the core, the readings its arcs can
-- show, your choice of both (settings' nexus.orbit), and where every node and its trace go. Pure,
-- so tests/unit runs it; the scene draws from the rows the logic publishes from here.

local M = {}

-- What a node can be: a toggle (its nx_tog code) or an action (its nx_go code), its word and the
-- glyph the scene draws for it (its place in the scene's glyph list, from 0).
M.NODES = {
    wifi = { word = "Wi-Fi", tog = 0, glyph = 0 },
    bt = { word = "Bluetooth", tog = 1, glyph = 1 },
    mute = { word = "Sound", tog = 2, glyph = 2 },
    mic = { word = "Mic", tog = 3, glyph = 3 },
    quiet = { word = "Quiet", tog = 4, glyph = 4 },
    night = { word = "Night", tog = 5, glyph = 5 },
    awake = { word = "Awake", tog = 6, glyph = 6 },
    saver = { word = "Saver", tog = 7, glyph = 7 },
    record = { word = "Record", tog = 8, glyph = 8 },
    lock = { word = "Lock", go = 2, glyph = 9 },
    settings = { word = "Settings", go = 1, glyph = 10 },
    screenshot = { word = "Shot", go = 44, glyph = 11 },
}
M.NODE_ORDER = { "wifi", "bt", "mute", "mic", "quiet", "night", "awake", "saver", "record", "lock", "settings", "screenshot" }
M.ARCS = { cpu = "CPU", mem = "Memory", temp = "Temperature", gpu = "Graphics", disk = "Disk", battery = "Battery", volume = "Volume" }
M.ARC_ORDER = { "cpu", "mem", "temp", "gpu", "disk", "battery", "volume" }
M.BACKDROPS = { banner = true, circuit = true, plain = true }
M.DEFAULT = { nodes = { "wifi", "bt", "mute", "mic", "quiet", "night", "awake", "record" },
              arcs = { "cpu", "mem", "temp" }, backdrop = "banner" }

local function pick(list, known, max, default)
    if type(list) ~= "table" then list = default end
    local out, seen = {}, {}
    for _, id in ipairs(list) do
        if known[id] and not seen[id] and #out < max then out[#out + 1] = id; seen[id] = true end
    end
    return out
end

-- Your choice as kept (nexus.orbit), cleaned: known ids, no repeats, ≤ 8 nodes, ≤ 3 arcs.
function M.choose(t)
    t = type(t) == "table" and t or {}
    return { nodes = pick(t.nodes, M.NODES, 8, M.DEFAULT.nodes),
             arcs = pick(t.arcs, M.ARCS, 3, M.DEFAULT.arcs),
             backdrop = M.BACKDROPS[t.backdrop] and t.backdrop or M.DEFAULT.backdrop }
end

-- The toggles and actions not in the orbit, in the catalogue's order (the chips under it).
function M.rest(nodes)
    local inside = {}
    for _, id in ipairs(nodes or {}) do inside[id] = true end
    local out = {}
    for _, id in ipairs(M.NODE_ORDER) do if not inside[id] then out[#out + 1] = id end end
    return out
end

-- n nodes on a ring of radius `r` round (cx, cy), the first at the top, clockwise; each with its
-- trace: from the core's edge (radius r0) out, a kink to the side (alternating, as a board routes
-- around its neighbours), then to the pad.
function M.geometry(n, cx, cy, r, r0)
    local out = {}
    if n <= 0 then return out end
    for k = 0, n - 1 do
        local a = math.rad(-90 + k * 360 / n)
        local side = (k % 2 == 0) and 1 or -1
        local mid = (r0 + r) / 2
        local b = a + math.rad(9) * side
        out[#out + 1] = {
            x = cx + r * math.cos(a), y = cy + r * math.sin(a),
            p1x = cx + r0 * math.cos(a), p1y = cy + r0 * math.sin(a),
            p2x = cx + mid * math.cos(b), p2y = cy + mid * math.sin(b),
            p3x = cx + r * math.cos(a), p3y = cy + r * math.sin(a),
        }
    end
    return out
end

return M
