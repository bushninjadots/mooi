-- What lives below (D209, the Subsurface spec §5): the places on the subsurface the opening shows. The hubs
-- (Apps, Music, Wallpapers, Settings, Notifications — `notes`) are places, not menus; the components (Wi-Fi,
-- Bluetooth, volume, brightness, battery, power) are small controls; BMO has a home there. Pure: where each one
-- lives (defaults, a saved arrangement kept on the screen), the boxes the opening snaps to, and what the Apps
-- and Wallpapers hubs show. Places are screen pixels { x, y, w, h }; surface.json keeps them under "places".

local M = { COMPONENT = 56, GAP = 12, RIGHT = 32, BOTTOM = 96 }
M.HUBS = { "apps", "music", "walls", "settings", "notes" }
M.COMPONENTS = { "wifi", "bt", "volume", "bright", "battery", "power" }
M.SIZES = { apps = { 360, 220 }, music = { 320, 140 }, walls = { 360, 120 }, settings = { 300, 140 }, notes = { 320, 220 } }
M.BMO = { 160, 196 }

local function round(v) return math.floor(v + 0.5) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function num(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function size_of(id)
    if M.SIZES[id] then return M.SIZES[id][1], M.SIZES[id][2] end
    if id == "bmo" then return M.BMO[1], M.BMO[2] end
    return M.COMPONENT, M.COMPONENT
end

-- The first arrangement: the hubs centred along an arc through the middle third (their centres 0.36·h at
-- the ends, 0.30·h in the middle, evenly across 0.12·w … 0.88·w); the components in one row ending 32 px from
-- the right and 96 px from the bottom; BMO's home low on the left.
function M.defaults(scr)
    local W, H = scr.w, scr.h
    local out = {}
    local n = #M.HUBS
    for i, id in ipairs(M.HUBS) do
        local w, h = size_of(id)
        local f = (i - 1) / (n - 1)
        local t = 2 * f - 1
        local cx, cy = W * (0.12 + 0.76 * f), H * (0.30 + 0.06 * t * t)
        out[id] = { x = round(cx - w / 2), y = round(cy - h / 2), w = w, h = h }
    end
    local c, g = M.COMPONENT, M.GAP
    local x0 = W - M.RIGHT - (#M.COMPONENTS * c + (#M.COMPONENTS - 1) * g)
    for i, id in ipairs(M.COMPONENTS) do
        out[id] = { x = x0 + (i - 1) * (c + g), y = H - M.BOTTOM - c, w = c, h = c }
    end
    out.bmo = { x = round(0.06 * W), y = H - 300, w = M.BMO[1], h = M.BMO[2] }
    return out
end

-- A saved arrangement: each place kept where it was left, wholly on this screen; a place it lacks (or one
-- that is not a number) from the defaults; an id that is not ours dropped. Sizes are ours, never the file's.
function M.merge(saved, scr)
    local out = M.defaults(scr)
    if type(saved) ~= "table" then return out end
    for id, d in pairs(out) do
        local s = saved[id]
        if type(s) == "table" and num(s.x) and num(s.y) then
            d.x = round(clamp(s.x, 0, math.max(0, scr.w - d.w)))
            d.y = round(clamp(s.y, 0, math.max(0, scr.h - d.h)))
        end
    end
    return out
end

-- what surface.json keeps of them: where each one is
function M.save(places)
    local out = {}
    for id, p in pairs(places or {}) do out[id] = { x = p.x, y = p.y } end
    return out
end

-- Every box the opening may snap to (lib/surface/opening `near`): the places, then each widget that lives
-- under the wallpaper (widgets.json is in the widgets surface's pixels, which start below the bar's strip:
-- bar_h down; one kept above the wallpaper is not here).
function M.boxes(places, widgets, bar_h)
    local out = {}
    local function put(id)
        local p = places and places[id]
        if p then out[#out + 1] = { id = id, x = p.x, y = p.y, w = p.w, h = p.h } end
    end
    for _, id in ipairs(M.HUBS) do put(id) end
    for _, id in ipairs(M.COMPONENTS) do put(id) end
    put("bmo")
    for _, w in ipairs(type(widgets) == "table" and widgets or {}) do
        if type(w) == "table" and w.above ~= true and num(w.x) and num(w.y) and num(w.w) and num(w.h) then
            out[#out + 1] = { id = "w:" .. tostring(w.id), x = w.x, y = w.y + (bar_h or 0), w = w.w, h = w.h }
        end
    end
    return out
end

-- The Apps hub's marks: the most launched first (counts by the app's id, kept in surface.json), the rest in
-- the service's own order; at most n.
function M.apps(list, counts, n)
    local rows = {}
    for i, a in ipairs(type(list) == "table" and list or {}) do
        if type(a) == "table" and type(a.exec) == "string" and a.exec ~= "" then
            rows[#rows + 1] = { a = a, i = i, c = tonumber(counts and counts[a.id]) or 0 }
        end
    end
    table.sort(rows, function(p, q) if p.c ~= q.c then return p.c > q.c end return p.i < q.i end)
    local out = {}
    for i = 1, math.min(n, #rows) do out[i] = rows[i].a end
    return out
end

-- The Wallpapers hub: the n newest pictures in the picker's index (walls-index.json) that have a thumbnail.
function M.walls(doc, n)
    local rows = {}
    local items = type(doc) == "table" and type(doc.items) == "table" and doc.items or {}
    for i, it in ipairs(items) do
        if type(it) == "table" and type(it.path) == "string" and type(it.thumb) == "string" and it.thumb ~= "" then
            rows[#rows + 1] = { path = it.path, thumb = it.thumb, t = tonumber(it.mtime) or 0, i = i }
        end
    end
    table.sort(rows, function(p, q) if p.t ~= q.t then return p.t > q.t end return p.i < q.i end)
    local out = {}
    for i = 1, math.min(n, #rows) do out[i] = { path = rows[i].path, thumb = rows[i].thumb } end
    return out
end

return M
