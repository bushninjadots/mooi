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
M.PANEL_X = 168       -- a panel's left edge: past the fan
M.NUB_Y = 0.3         -- where the nub starts, as a share of the screen's height (above the stash)
-- each panel's size (the carousels have none: they are arcs across the screen)
M.PANELS = { [0] = { w = 440, h = 600 }, [1] = { w = 440, h = 220 }, [4] = { w = 440, h = 340 }, [5] = { w = 460, h = 600 } }
M.ARC_R = 560         -- the carousel's radius (its centre off the screen to the left)
M.ARC_STEP = 12       -- degrees between neighbours on it
M.ARC_SEEN = 46       -- and how far from the middle one is still drawn

function M.tab_index(id)
    for i, t in ipairs(M.TABS) do if t.id == id then return i - 1 end end
    return nil
end

-- Each tab's centre on the fan round (0, cy).
function M.fan(cy)
    local out, n = {}, #M.TABS
    for i = 0, n - 1 do
        local a = -M.FAN_SPAN / 2 + M.FAN_SPAN * i / (n - 1)
        local r = math.rad(a)
        out[#out + 1] = { x = math.cos(r) * M.FAN_R + 10, y = cy + math.sin(r) * M.FAN_R, angle = a }
    end
    return out
end

-- Where a panel opens from a side of the Control Nexus (lib/nexusdeck's layout `d`, in the screen):
-- `tab`, and `left` for the deck's left end (or a column's open side). Along a strip it rises over
-- (or hangs under) that end; beside a column it opens on the column's open side. The carousels turn
-- from the screen's nearer edge. Returns { px, py, ox, acy, dir }.
function M.from_deck(d, tab, left, sw, sh)
    local p = M.PANELS[tab] or { w = 440, h = 400 }
    local g = 12
    local r = {}
    if not d.vertical then
        r.px = left and math.max(g, d.x) or math.min(sw - p.w - g, d.x + d.w - p.w)
        r.py = d.edge == "bottom" and (d.y - p.h - g) or (d.y + d.h + g)
        r.dir = left and 1 or -1
        r.ox = left and 0 or sw
        r.acy = d.edge == "bottom" and math.max(430, (d.y) / 2) or math.min(sh - 430, (d.y + d.h + sh) / 2)
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

return M
