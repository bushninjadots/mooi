-- The side notch (D106): a nub on the left edge that fans out into tabs on an arc when pointed at —
-- Claude, Music, Workspaces, Wallpapers, Weather, GitHub — each opening its panel beside the fan.
-- Pure, so tests/unit runs it; shell/mooi-notch.luau reads the system and hands this what it found.

local M = {}

M.TABS = {
    { id = "claude", word = "Claude" },
    { id = "music", word = "Music" },
    { id = "spaces", word = "Workspaces" },
    { id = "walls", word = "Wallpapers" },
    { id = "weather", word = "Weather" },
    { id = "github", word = "GitHub" },
}
M.FAN_R = 100         -- the fan's radius round the nub (its hexagons a finger apart)
M.FAN_SPAN = 120      -- degrees, top tab to bottom tab
M.PANEL_X = 60        -- a panel's left edge: past the track of tabs (D119: a column, as the spine's)
M.NUB_Y = 0.3         -- where the nub starts, as a share of the screen's height (above the stash)
-- each panel's size (the carousels have none: they are arcs across the screen)
M.PANELS = { [0] = { w = 440, h = 600 }, [1] = { w = 440, h = 220 }, [4] = { w = 440, h = 340 }, [5] = { w = 460, h = 600 } }
M.ARC_R = 560         -- the carousel's radius (its centre off the screen to the left)
M.ARC_STEP = 12       -- degrees between neighbours on it
M.ARC_SEEN = 46       -- and how far from the middle one is still drawn

M.NUB_REACH = 150     -- the nub and its fan, above and below its middle: the stash's edge strip leaves this to the notch
M.STASH_TAB = 128     -- the stash's tab, in the middle of the screen's full height (shell/mooi.plm sb_tab_h)

-- The nub's middle on a surface h tall whose top is `top` px down a screen full_h tall: kept off the
-- surface's ends and, when the stash's tab is given, clear of it (the stash is overlay, the notch is not:
-- over the tab the stash would take the pointer). Returns the middle in the surface's own pixels.
function M.nub_cy(share, h, top, full_h)
    local cy = math.floor(math.max(160, math.min(h - 160, h * share)))
    if full_h then
        local tab0, tab1 = (full_h - M.STASH_TAB) / 2 - top, (full_h + M.STASH_TAB) / 2 - top
        if cy + 70 > tab0 and cy - 70 < tab1 then
            cy = (cy < (tab0 + tab1) / 2) and math.floor(tab0 - 70) or math.ceil(tab1 + 70)
        end
    end
    return cy
end

-- The band of the screen (its full-height pixels) the nub and its fan need to themselves.
function M.cut(cy, top)
    return top + cy - M.NUB_REACH, top + cy + M.NUB_REACH
end

function M.tab_index(id)
    for i, t in ipairs(M.TABS) do if t.id == id then return i - 1 end end
    return nil
end

-- Each tab's centre on the fan round (0, cy).
-- Each tab's centre in the track round (0, cy): a column 40 px apart, as the spine's on the right
-- edge (D119; it was a fan on an arc). `x` is where the logic adds its 22 to reach the tabs' middle.
M.TAB_STEP = 40
function M.fan(cy)
    local out, n = {}, #M.TABS
    for i = 0, n - 1 do
        out[#out + 1] = { x = 1, y = cy + (i - (n - 1) / 2) * M.TAB_STEP, angle = 0 }
    end
    return out
end

-- Where a panel opens from a side of the Control Nexus (lib/nexusdeck's layout `d`, in the screen):
-- `tab`, and `left` for the deck's left end (or a column's open side). Along a strip it rises over
-- (or hangs under) that end; beside a column it opens on the column's open side. The carousels turn
-- from the screen's nearer edge. Returns { px, py, ox, acy, dir }.
M.EAR = 34            -- how far the deck's notches stick out of it: a panel opens past them
function M.from_deck(d, tab, left, sw, sh)
    local p = M.PANELS[tab] or { w = 440, h = 400 }
    local g = 14 + M.EAR
    local r = {}
    if not d.vertical then
        r.px = left and math.max(g, d.x) or math.min(sw - p.w - g, d.x + d.w - p.w)
        r.py = d.edge == "bottom" and (d.y - p.h - g) or (d.y + d.h + g)
        r.dir = left and 1 or -1
        r.ox = left and 0 or sw
        r.acy = d.edge == "bottom" and math.max(430, (d.y - M.EAR) / 2) or math.min(sh - 430, (d.y + d.h + M.EAR + sh) / 2)
    else
        local cy = d.y + 60
        r.py = M.panel_y(cy + p.h / 2 - 40, p.h, sh)
        if d.edge == "right" then r.px, r.dir, r.ox = d.x - p.w - g, -1, d.x
        else r.px, r.dir, r.ox = d.x + d.w + g, 1, d.x + d.w end
        r.acy = math.max(430, math.min(sh - 430, sh / 2))
    end
    for k, v in pairs(r) do r[k] = math.floor(v + 0.5) end
    return r
end

-- Where a panel `h` tall opens: beside the fan, level with the nub, kept on a screen `sh` tall.
function M.panel_y(cy, h, sh)
    return math.floor(math.max(12, math.min(sh - h - 12, cy - h / 2)) + 0.5)
end

-- The carousel: item `i` (from 0) with `c` the one in the middle (a fraction while it glides) — its
-- angle, and whether it is drawn at all.
function M.arc(i, c)
    local a = (i - c) * M.ARC_STEP
    return a, math.abs(a) <= M.ARC_SEEN
end

-- The hours' temperatures as bar heights 0.15..1 (the coldest the shortest).
function M.bars(hours)
    local lo, hi = math.huge, -math.huge
    for _, h in ipairs(hours or {}) do
        local t = tonumber(h.temp) or 0
        lo, hi = math.min(lo, t), math.max(hi, t)
    end
    local out = {}
    for i, h in ipairs(hours or {}) do
        local t = tonumber(h.temp) or 0
        out[i] = hi > lo and 0.15 + 0.85 * (t - lo) / (hi - lo) or 0.6
    end
    return out
end

-- A short, stable name for a picture's thumbnail (djb2 over its path).
function M.thumb_name(path)
    local h = 5381
    for i = 1, #path do h = (h * 33 + string.byte(path, i)) % 4294967296 end
    return string.format("nt-%08x.jpg", h)
end

-- The pictures worth a thumbnail in a listing (`find` output): images, sorted, at most `max`.
M.IMAGE = { jpg = true, jpeg = true, png = true, webp = true, avif = true }
function M.pictures(listing, max)
    local out = {}
    for line in tostring(listing or ""):gmatch("[^\n]+") do
        local ext = line:match("%.([%w]+)$")
        if ext and M.IMAGE[string.lower(ext)] then out[#out + 1] = line end
    end
    table.sort(out)
    while #out > (max or 40) do out[#out] = nil end
    return out
end

-- A colour's hue (0..360) and how strongly it has one (0..1, grey near 0), from its red, green and
-- blue as 0..1 (or 0..255): the mean colour of a picture, read by magick (shell/mooi-notch.luau).
function M.hue(r, g, b)
    r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
    if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
    local hi, lo = math.max(r, g, b), math.min(r, g, b)
    local d = hi - lo
    local sat = hi > 0 and d / hi or 0
    if d == 0 then return 0, 0 end
    local h
    if hi == r then h = ((g - b) / d) % 6
    elseif hi == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    return (h * 60) % 360, sat
end

-- The colour band (0..n-1) a hue falls in, each band centred on its own colour: with 8, red is
-- 337.5°..22.5°, orange 22.5°..67.5°, and so on round the wheel.
function M.band(hue, n)
    n = math.max(1, math.floor(tonumber(n) or 8))
    local step = 360 / n
    return math.floor((((tonumber(hue) or 0) % 360) + step / 2) / step) % n
end

-- `max` of them, drawn afresh: a folder of thousands should not open on the same first forty
-- names every time. The same `seed` draws the same ones, so a test — or a redraw — is repeatable.
function M.draw(list, max, seed)
    local out = {}
    for i, v in ipairs(type(list) == "table" and list or {}) do out[i] = v end
    -- a Lehmer generator: kept under 2^53, where a Lua number is still exact (a wider one loses
    -- its low bits, and the shuffle leaves most of the list where it found it)
    local s = math.floor(tonumber(seed) or 0) % 2147483646
    for i = #out, 2, -1 do
        s = (s * 48271) % 2147483647
        local j = (s % i) + 1
        out[i], out[j] = out[j], out[i]
    end
    while #out > (max or 40) do out[#out] = nil end
    return out
end

return M
