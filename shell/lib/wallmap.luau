-- The wallpaper, as the desktop widgets read it (D139): what lies under a widget (light, colour,
-- detail, subject), the text tone and haze that stay readable there, an accent taken from the
-- colours there that keeps its contrast, the calmest free spot, and the picture's mood. Pure:
-- tools/wallmap.py measures the picture (wall-map.json), mooi-widgets.luau applies this.
-- `screen` is the widgets' room { w, h, top }: under the bar, so the map (the whole screen) is
-- offset by the bar's height.

local M = {}

local function clamp(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end

function M.parse(t)
    if type(t) ~= "table" or type(t.cells) ~= "table" then return nil end
    local cols, rows = tonumber(t.cols), tonumber(t.rows)
    if not cols or not rows or #t.cells ~= cols * rows then return nil end
    return { cols = cols, rows = rows, cells = t.cells, mood = type(t.mood) == "table" and t.mood or {},
             cut = t.cut == true, depth = t.depth == true, w = tonumber(t.w) or 1920, h = tonumber(t.h) or 1080,
             src = t.src }
end

-- The cells a widget covers, in the map's (whole screen) coordinates: light, colour and detail
-- averaged, subject at its most.
function M.under(map, x, y, w, h, screen)
    local bar = math.max(0, map.h - (screen and screen.h or map.h))
    local cw, ch = map.w / map.cols, map.h / map.rows
    local c0 = clamp(math.floor(x / cw), 0, map.cols - 1)
    local c1 = clamp(math.floor((x + w - 1) / cw), 0, map.cols - 1)
    local r0 = clamp(math.floor((y + bar) / ch), 0, map.rows - 1)
    local r1 = clamp(math.floor((y + bar + h - 1) / ch), 0, map.rows - 1)
    local n, l, a, b, d, s = 0, 0, 0, 0, 0, 0
    for r = r0, r1 do
        for c = c0, c1 do
            local cell = map.cells[r * map.cols + c + 1]
            n = n + 1
            l, a, b, d = l + (cell.l or 0), a + (cell.a or 0), b + (cell.b or 0), d + (cell.d or 0)
            if (cell.s or 0) > s then s = cell.s end
        end
    end
    if n == 0 then return { l = 0.5, a = 0, b = 0, d = 0, s = 0 } end
    return { l = l / n, a = a / n, b = b / n, d = d / n, s = s }
end

function M.tone(l) return (l or 0) > 0.58 and "dark" or "light" end

-- How much haze behind the words: more over detail, more over mid greys (where neither light nor
-- dark text stands out).
function M.haze(d, l)
    local h = 0.2 + 0.7 * (d or 0)
    if l and l > 0.35 and l < 0.65 then h = h + 0.2 end
    return clamp(h, 0, 1)
end

-- ── Colour ──
local function to_lin(c) return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
local function from_lin(c) return c <= 0.0031308 and 12.92 * c or 1.055 * c ^ (1 / 2.4) - 0.055 end
local function luminance(c) return 0.2126 * to_lin(c.r) + 0.7152 * to_lin(c.g) + 0.0722 * to_lin(c.b) end
function M.contrast(c1, c2)
    local a, b = luminance(c1), luminance(c2)
    if a < b then a, b = b, a end
    return (a + 0.05) / (b + 0.05)
end
-- Lab (L 0..100, a and b about ±128) to sRGB 0..1, clamped
local function lab_rgb(L, A, B)
    local fy = (L + 16) / 116
    local fx, fz = fy + A / 500, fy - B / 200
    local function inv(t) return t ^ 3 > 0.008856 and t ^ 3 or (t - 16 / 116) / 7.787 end
    local X, Y, Z = inv(fx) * 0.95047, inv(fy), inv(fz) * 1.08883
    local r = 3.2406 * X - 1.5372 * Y - 0.4986 * Z
    local g = -0.9689 * X + 1.8758 * Y + 0.0415 * Z
    local b = 0.0557 * X - 0.2040 * Y + 1.0570 * Z
    return { r = clamp(from_lin(clamp(r, 0, 1)), 0, 1), g = clamp(from_lin(clamp(g, 0, 1)), 0, 1), b = clamp(from_lin(clamp(b, 0, 1)), 0, 1) }
end

-- The colour under a widget made into an accent: its hue at a clear lightness and some chroma,
-- leaning towards the palette's own, then lightened or darkened until it reads on the ground.
function M.accent(cell, palette, ground)
    local a, b = (cell.a or 0) * 128, (cell.b or 0) * 128
    local chroma = math.sqrt(a * a + b * b)
    if chroma < 32 then
        if chroma < 1 then a, b, chroma = 0, -1, 1 end
        a, b = a / chroma * 32, b / chroma * 32
    end
    local dark_ground = luminance(ground) < 0.4
    local L = dark_ground and 72 or 38
    local c
    for _ = 1, 24 do
        local raw = lab_rgb(L, a, b)
        c = { r = raw.r * 0.65 + palette.r * 0.35, g = raw.g * 0.65 + palette.g * 0.35, b = raw.b * 0.65 + palette.b * 0.35 }
        if M.contrast(c, ground) >= 4.5 then return c end
        L = L + (dark_ground and 4 or -4)
        if L > 100 or L < 0 then break end
    end
    -- the hue cannot carry it: plain light or dark
    return dark_ground and { r = 0.95, g = 0.95, b = 0.95 } or { r = 0.05, g = 0.05, b = 0.05 }
end

-- The nearest place (by centre) of the same size, on a 16 px raster, clear of the other widgets and
-- calm (little subject, little detail) underneath; nil if there is none.
function M.calm_spot(map, doc, index, screen)
    local me = doc.widgets[index]
    if not me then return nil end
    local top = screen.top or 0
    local best, bx, by = math.huge, nil, nil
    local mcx, mcy = me.x + me.w / 2, me.y + me.h / 2
    local y = top
    while y + me.h <= screen.h do
        local x = 0
        while x + me.w <= screen.w do
            local dist = (x + me.w / 2 - mcx) ^ 2 + (y + me.h / 2 - mcy) ^ 2
            if dist < best then
                local free = true
                for i, o in ipairs(doc.widgets) do
                    if i ~= index and x < o.x + o.w + 8 and o.x < x + me.w + 8 and y < o.y + o.h + 8 and o.y < y + me.h + 8 then free = false; break end
                end
                if free then
                    local u = M.under(map, x, y, me.w, me.h, screen)
                    if u.s < 0.15 and u.d < 0.45 then best, bx, by = dist, x, y end
                end
            end
            x = x + 16
        end
        y = y + 16
    end
    return bx, by
end

-- The picture's character as how the widgets move: lively pictures glow and move more, calm and
-- low-contrast ones are softer and slower.
function M.mood(m)
    m = m or {}
    local sat, con, det = tonumber(m.sat) or 0, tonumber(m.contrast) or 0, tonumber(m.detail) or 0
    local life = clamp(0.45 * sat + 0.35 * con + 0.6 * det, 0, 1)
    return { glow = 0.6 + 0.6 * life, pace = 0.7 + 0.5 * clamp(det * 1.5 + con * 0.5, 0, 1), soft = 1 - clamp(con * 1.5, 0, 1) }
end

return M
