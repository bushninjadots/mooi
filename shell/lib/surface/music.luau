-- Music in the picture (D223, docs/superpowers/specs/2026-11-09-music-in-the-picture-design.md): a Live wallpaper
-- effect where strips of the wallpaper are pulled up out of it by the music. Pure: the bands packed for a shader,
-- the places it grows from (an edge line, drawn areas, picked colours, the subject) read and kept valid. Kept in
-- surface.json's `music` (mooi-surface's own file).

local M = { AREAS = 4, COLOURS = 2, MIN_W = 40, MIN_H = 30 }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function num(v) return type(v) == "number" and v == v end

-- sixteen bands (0 … 1) in six numbers: three bytes each, so float32 carries them whole
function M.pack(b)
    b = type(b) == "table" and b or {}
    local out = {}
    for i = 0, 5 do
        local v = 0
        for j = 0, 2 do
            local x = tonumber(b[i * 3 + j + 1]) or 0
            v = v * 256 + math.floor(clamp(x, 0, 1) * 255 + 0.5)
        end
        out[i + 1] = v
    end
    return out
end

-- the bar's 32 bands, to sixteen (pairwise)
function M.bands16(b)
    local out = {}
    for i = 1, 16 do
        local a, c = tonumber(b and b[i * 2 - 1]) or 0, tonumber(b and b[i * 2]) or 0
        out[i] = (a + c) / 2
    end
    return out
end

local function hexok(h) return type(h) == "string" and h:match("^#%x%x%x%x%x%x$") ~= nil end
function M.hex(h) if not hexok(h) then return 0 end; return tonumber(h:sub(2), 16) end

local function area(a)
    if type(a) ~= "table" or not (num(a.x) and num(a.y) and num(a.w) and num(a.h)) then return nil end
    if a.w < M.MIN_W or a.h < M.MIN_H then return nil end
    return { x = math.floor(a.x), y = math.floor(a.y), w = math.floor(a.w), h = math.floor(a.h) }
end

-- whatever surface.json holds, as places to grow from
function M.read(m)
    m = type(m) == "table" and m or {}
    local out = { edge = m.edge ~= false, edge_at = clamp(math.floor(tonumber(m.edge_at) or 100), 10, 100),
                  subject = m.subject == true, areas = {}, colours = {} }
    for _, a in ipairs(type(m.areas) == "table" and m.areas or {}) do
        local v = area(a)
        if v and #out.areas < M.AREAS then out.areas[#out.areas + 1] = v end
    end
    for _, c in ipairs(type(m.colours) == "table" and m.colours or {}) do
        if hexok(c) and #out.colours < M.COLOURS then out.colours[#out.colours + 1] = string.lower(c) end
    end
    return out
end

local function copy(m)
    local o = M.read(m)
    return o
end

-- a drawn area: the newest kept, the oldest let go past four; too small, nothing
function M.add_area(m, a)
    local o = copy(m)
    local v = area(a)
    if not v then return o end
    o.areas[#o.areas + 1] = v
    while #o.areas > M.AREAS do table.remove(o.areas, 1) end
    return o
end

-- a picked colour: the newest kept (picked again, it moves to the end), the oldest let go past two
function M.add_colour(m, h)
    local o = copy(m)
    if not hexok(h) then return o end
    h = string.lower(h)
    for i = #o.colours, 1, -1 do if o.colours[i] == h then table.remove(o.colours, i) end end
    o.colours[#o.colours + 1] = h
    while #o.colours > M.COLOURS do table.remove(o.colours, 1) end
    return o
end

-- the edge's band: bars rise from a line `at` % down the screen, up to `height` % of the screen
function M.edge_rect(scr, at, height)
    local W, H = tonumber(scr and scr.w) or 1920, tonumber(scr and scr.h) or 1080
    local base = H * clamp(tonumber(at) or 100, 10, 100) / 100
    local h = math.min(base, H * clamp(tonumber(height) or 25, 5, 80) / 100)
    return { x = 0, y = math.floor(base - h), w = W, h = math.floor(h) }
end

return M
