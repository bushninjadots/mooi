-- What lives below (D209, the Subsurface spec §5): the places on the subsurface the opening shows. The hubs
-- (Apps, Music, Wallpapers, Settings, Notifications — `notes`) are places, not menus; the components (Wi-Fi,
-- Bluetooth, volume, brightness, battery, power) are small controls; BMO lives there too, wherever he stands
-- (he tells mooi-surface his box: the spec §6, a citizen reports its things). Pure: where each one lives
-- (defaults, a saved arrangement kept on the screen), the boxes the opening snaps to, and what the Apps,
-- Wallpapers and Settings hubs show. Places are screen pixels { x, y, w, h } while running; surface.json keeps
-- them under "places" as fractions of the screen (fx, fy) with their size, and the monitor they were made on,
-- so an arrangement survives a change of resolution (the spec §3, "the map").

local M = { COMPONENT = 56, GAP = 12, RIGHT = 32, BOTTOM = 96 }
M.HUBS = { "apps", "music", "walls", "settings", "notes" }
M.COMPONENTS = { "wifi", "bt", "volume", "bright", "battery", "power" }
M.SIZES = { apps = { 360, 220 }, music = { 320, 140 }, walls = { 360, 120 }, settings = { 300, 140 }, notes = { 320, 220 } }
-- how small a hub may be shaped before its contents stop fitting; components are fixed
M.MIN = { apps = { 300, 200 }, music = { 260, 130 }, walls = { 300, 110 }, settings = { 260, 130 }, notes = { 280, 200 } }
M.LAYOUTS = { "arc", "row", "grid", "calm" }
M.SIDES = { "right", "centre", "left" }
M.DEFAULT_LAYOUT = "arc"
-- the Settings hub's marks: the word, and the page's tab in mooi-settings (lib/settings_index's `tab`)
M.SETTINGS = { { "Theme & colour", 1 }, { "Bar & Frame", 3 }, { "Wallpapers", 9 }, { "Widgets", 10 },
               { "Sound", 12 }, { "Power", 13 }, { "BMO", 11 }, { "The Subsurface", 21 } }

local function round(v) return math.floor(v + 0.5) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function num(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function size_of(id)
    if M.SIZES[id] then return M.SIZES[id][1], M.SIZES[id][2] end
    return M.COMPONENT, M.COMPONENT
end

-- The first arrangement: the hubs centred along an arc through the middle third (their centres 0.36·h at
-- the ends, 0.30·h in the middle, evenly across 0.12·w … 0.88·w); the components in one row ending 32 px from
-- the right and 96 px from the bottom. Everything is kept wholly on the screen (a narrow one included).
-- `opts` picks where the hubs sit (`layout`: arc, row, grid, calm) and which side the components'
-- row ends on (`components`: right, centre, left).
-- The arc is D209's and is what no options means, so a file with no settings reads exactly as before.
function M.defaults(scr, opts)
    opts = type(opts) == "table" and opts or {}
    local W, H = scr.w, scr.h
    local out = {}
    local n = #M.HUBS
    local layout = opts.layout
    if layout ~= "row" and layout ~= "grid" and layout ~= "calm" then layout = M.DEFAULT_LAYOUT end
    if layout == "row" then
        -- one straight row, every hub centred in it, gaps of 32 px
        local total, gap = 0, 32
        for _, id in ipairs(M.HUBS) do local w = size_of(id); total = total + w end
        total = total + gap * (n - 1)
        local x = (W - total) / 2
        for _, id in ipairs(M.HUBS) do
            local w, h = size_of(id)
            out[id] = { x = round(x), y = round(H * 0.34 - h / 2), w = w, h = h }
            x = x + w + gap
        end
    elseif layout == "grid" then
        -- three columns by two rows: Apps, Music, Wallpapers above; Settings and Notices below
        local col = { 0.18, 0.50, 0.82 }
        local row = { 0.24, 0.44 }
        local at = { apps = { 1, 1 }, music = { 2, 1 }, walls = { 3, 1 }, settings = { 1, 2 }, notes = { 2, 2 } }
        for _, id in ipairs(M.HUBS) do
            local w, h = size_of(id)
            local c, r = at[id][1], at[id][2]
            out[id] = { x = round(W * col[c] - w / 2), y = round(H * row[r] - h / 2), w = w, h = h }
        end
    elseif layout == "calm" then
        -- low and out of the wallpaper's way: a gentle row in the lower band
        local total, gap = 0, 24
        for _, id in ipairs(M.HUBS) do local w = size_of(id); total = total + w end
        total = total + gap * (n - 1)
        local x = (W - total) / 2
        for i, id in ipairs(M.HUBS) do
            local w, h = size_of(id)
            local t = (i - 1) / (n - 1) * 2 - 1
            out[id] = { x = round(x), y = round(H * (0.60 + 0.012 * t * t) - h / 2), w = w, h = h }
            x = x + w + gap
        end
    else
        -- the arc: centres 0.36·h at the ends, 0.30·h in the middle, evenly across 0.12·w … 0.88·w
        for i, id in ipairs(M.HUBS) do
            local w, h = size_of(id)
            local f = (i - 1) / (n - 1)
            local t = 2 * f - 1
            local cx, cy = W * (0.12 + 0.76 * f), H * (0.30 + 0.06 * t * t)
            out[id] = { x = round(cx - w / 2), y = round(cy - h / 2), w = w, h = h }
        end
    end
    local c, g = M.COMPONENT, M.GAP
    local row_w = #M.COMPONENTS * c + (#M.COMPONENTS - 1) * g
    local side = opts.components
    local x0
    if side == "left" then x0 = M.RIGHT
    elseif side == "centre" then x0 = round((W - row_w) / 2)
    else x0 = W - M.RIGHT - row_w end
    for i, id in ipairs(M.COMPONENTS) do
        out[id] = { x = x0 + (i - 1) * (c + g), y = H - M.BOTTOM - c, w = c, h = c }
    end
    for _, d in pairs(out) do
        d.x = round(clamp(d.x, 0, math.max(0, W - d.w)))
        d.y = round(clamp(d.y, 0, math.max(0, H - d.h)))
    end
    return out
end

-- A saved arrangement: each place kept where it was left and at the size it was shaped to, wholly on this
-- screen; a place it lacks (or one that is not a number) from the defaults; an id that is not ours dropped.
-- A component keeps its fixed size; a hub stops at M.MIN so its words still fit.
function M.merge(saved, scr, opts)
    local out = M.defaults(scr, opts)
    if type(saved) ~= "table" then return out end
    for id, d in pairs(out) do
        local s = saved[id]
        if type(s) == "table" then
            local mn = M.MIN[id]
            if mn and num(s.w) and num(s.h) then
                d.w = round(clamp(s.w, mn[1], scr.w))
                d.h = round(clamp(s.h, mn[2], scr.h))
            end
            -- fractions of the screen (D214); a file from D209-D213 has pixels
            local x = num(s.fx) and s.fx * scr.w or (num(s.x) and s.x or d.x)
            local y = num(s.fy) and s.fy * scr.h or (num(s.y) and s.y or d.y)
            d.x = round(clamp(x, 0, math.max(0, scr.w - d.w)))
            d.y = round(clamp(y, 0, math.max(0, scr.h - d.h)))
        end
    end
    return out
end

-- what surface.json keeps of them: where each one is, as a fraction of the screen, and how big
local function frac(v) return math.floor(v * 10000 + 0.5) / 10000 end
function M.save(places, scr)
    local out = {}
    local W, H = scr and scr.w or 1920, scr and scr.h or 1080
    for id, p in pairs(places or {}) do
        out[id] = { fx = frac(p.x / W), fy = frac(p.y / H), w = p.w, h = p.h }
    end
    return out
end

-- Every box the opening may snap to (lib/surface/opening `near`): the places, BMO where he stands (`bmo`, his
-- own report; none while he is away or not below), then each widget that lives under the wallpaper
-- (widgets.json is in the widgets surface's pixels, which start below the bar's strip: bar_h down; one kept
-- above the wallpaper is not here).
function M.boxes(places, widgets, bar_h, bmo)
    local out = {}
    local function put(id)
        local p = places and places[id]
        if p then out[#out + 1] = { id = id, x = p.x, y = p.y, w = p.w, h = p.h } end
    end
    for _, id in ipairs(M.HUBS) do put(id) end
    for _, id in ipairs(M.COMPONENTS) do put(id) end
    if type(bmo) == "table" and num(bmo.x) and num(bmo.y) and num(bmo.w) and num(bmo.h) and bmo.w > 0 then
        out[#out + 1] = { id = "bmo", x = bmo.x, y = bmo.y, w = bmo.w, h = bmo.h }
    end
    for _, w in ipairs(type(widgets) == "table" and widgets or {}) do
        if type(w) == "table" and w.above ~= true and num(w.x) and num(w.y) and num(w.w) and num(w.h) then
            out[#out + 1] = { id = "w:" .. tostring(w.id), x = w.x, y = w.y + (bar_h or 0), w = w.w, h = w.h }
        end
    end
    return out
end

-- Arrange: a dragged place sits on the nearest line of the canvas's grid.
function M.snap(x, y, step)
    step = tonumber(step) or 8
    if step < 1 then step = 1 end
    local function one(v)
        v = tonumber(v) or 0
        return math.floor(v / step + 0.5) * step
    end
    return one(x), one(y)
end

-- The Apps hub's marks: the most launched first (counts by the app's id, kept in surface.json), the rest in
-- the service's own order; at most n.
-- `q` (typed while the hub is snapped): only the apps whose name has it, those whose name starts with it first.
function M.apps(list, counts, n, q)
    q = type(q) == "string" and string.lower(q) or ""
    local rows = {}
    for i, a in ipairs(type(list) == "table" and list or {}) do
        if type(a) == "table" and type(a.exec) == "string" and a.exec ~= "" then
            local name = string.lower(tostring(a.name or a.id or ""))
            local at = q == "" and 1 or string.find(name, q, 1, true)
            if at then
                rows[#rows + 1] = { a = a, i = i, c = tonumber(counts and counts[a.id]) or 0, lead = at == 1 }
            end
        end
    end
    table.sort(rows, function(p, q2)
        if p.lead ~= q2.lead then return p.lead end
        if p.c ~= q2.c then return p.c > q2.c end
        return p.i < q2.i
    end)
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
