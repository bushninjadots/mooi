-- Push up from below (the Subsurface spec §9, §9a; D217): the pure decisions. Which widget below meets the
-- wallpaper how (`meet`: woven, moves, still — or above, for one kept above), the words that press up, one light
-- or push at a time, where a notice's spark shows, and which window its light travels to. lib/surface/light runs
-- them; nothing here touches the system.

local M = {}

-- each kind that can meet the wallpaper, and how it does by default; any of them may be still
M.MEET = { nowplaying = "woven", notices = "woven", visualiser = "moves", clock = "moves" }
local WORDS_MAX = 60
local EDGE_IN = 14

local function num(v) return type(v) == "number" and v == v end

function M.meet(w)
    if type(w) ~= "table" then return "still" end
    if w.above == true then return "above" end
    local d = M.MEET[w.kind]
    if not d then return "still" end
    local o = type(w.options) == "table" and w.options.meet or nil
    if o == "still" then return "still" end
    return d
end

-- the first widget of `kind` below the wallpaper that meets it as `want`, in screen coordinates
function M.target(widgets, kind, want, bar_h)
    for _, w in ipairs(type(widgets) == "table" and widgets or {}) do
        if type(w) == "table" and w.kind == kind and M.meet(w) == want and num(w.x) and num(w.y) and num(w.w) and num(w.h) then
            return { x = w.x, y = w.y + (tonumber(bar_h) or 0), w = w.w, h = w.h }
        end
    end
    return nil
end

local function short(s)
    if utf8.len(s) and utf8.len(s) > WORDS_MAX then
        return string.sub(s, 1, utf8.offset(s, WORDS_MAX) - 1) .. "…"
    end
    return s
end

-- what presses up: the song, or the notice
function M.words(kind, d)
    d = type(d) == "table" and d or {}
    local a, b
    if kind == "nowplaying" then a, b = d.title, d.artist
    elseif kind == "notices" then a, b = d.app, d.title end
    a = type(a) == "string" and a or ""
    b = type(b) == "string" and b or ""
    local sep = kind == "nowplaying" and " — " or " · "
    local s = (a ~= "" and b ~= "") and (a .. sep .. b) or (a ~= "" and a or b)
    return short(s)
end

-- one at a time: what comes while one runs waits, the newest in place of the rest, counted
function M.queue() return { busy = false, waiting = nil } end
function M.push(q, item)
    if not q.busy then q.busy = true; item.n = item.n or 1; return true end
    local n = q.waiting and q.waiting.n or 0
    item.n = n + 1
    q.waiting = item
    return false
end
function M.done(q)
    local nx = q.waiting
    q.waiting = nil
    if not nx then q.busy = false end
    return nx
end

-- the windows on the workspace shown, on this monitor's coordinates
function M.rects(clients, ws, mon)
    local out = {}
    local ox, oy = (type(mon) == "table" and tonumber(mon.x)) or 0, (type(mon) == "table" and tonumber(mon.y)) or 0
    for _, c in ipairs(type(clients) == "table" and clients or {}) do
        if type(c) == "table" and c.mapped ~= false and c.hidden ~= true and type(c.workspace) == "table"
            and c.workspace.id == ws and type(c.at) == "table" and type(c.size) == "table" then
            out[#out + 1] = { x = (tonumber(c.at[1]) or 0) - ox, y = (tonumber(c.at[2]) or 0) - oy,
                              w = tonumber(c.size[1]) or 0, h = tonumber(c.size[2]) or 0,
                              class = c.class, title = c.title, address = c.address }
        end
    end
    return out
end
function M.fullscreen(clients, ws)
    for _, c in ipairs(type(clients) == "table" and clients or {}) do
        if type(c) == "table" and type(c.workspace) == "table" and c.workspace.id == ws and (tonumber(c.fullscreen) or 0) > 0
            and c.hidden ~= true then return true end
    end
    return false
end

function M.covered(p, rects)
    for _, r in ipairs(rects or {}) do
        if p.x >= r.x and p.x <= r.x + r.w and p.y >= r.y and p.y <= r.y + r.h then return true end
    end
    return false
end

-- where the spark shows: the widget's middle, or — a window over it — the nearest edge of the screen; with no
-- widget, the top right corner
function M.spark(box, rects, scr)
    local W, H = tonumber(scr and scr.w) or 1920, tonumber(scr and scr.h) or 1080
    if type(box) ~= "table" then return { x = W - EDGE_IN, y = EDGE_IN } end
    local c = { x = box.x + box.w / 2, y = box.y + box.h / 2 }
    if not M.covered(c, rects) then return c end
    local d = { c.x, c.y, W - c.x, H - c.y }      -- left, top, right, bottom
    local best = 1
    for i = 2, 4 do if d[i] < d[best] then best = i end end
    local y = math.max(EDGE_IN, math.min(H - EDGE_IN, c.y))
    local x = math.max(EDGE_IN, math.min(W - EDGE_IN, c.x))
    if best == 1 then return { x = EDGE_IN, y = y } end
    if best == 2 then return { x = x, y = EDGE_IN } end
    if best == 3 then return { x = W - EDGE_IN, y = y } end
    return { x = x, y = H - EDGE_IN }
end

-- the window of the app a notice came from (its class or title holds the app's name), else the focused one
function M.window_for(app, clients, ws, mon, focused)
    local rects = M.rects(clients, ws, mon)
    local want = string.lower(type(app) == "string" and app or "")
    if want ~= "" then
        for _, r in ipairs(rects) do
            local cl = string.lower(tostring(r.class or ""))
            local ti = string.lower(tostring(r.title or ""))
            if (cl ~= "" and (cl:find(want, 1, true) or want:find(cl, 1, true))) or ti:find(want, 1, true) then return r end
        end
    end
    for _, r in ipairs(rects) do
        if focused and r.address == focused then return r end
    end
    return nil
end

-- D223: the window of the app a notice came from, on any workspace — the one used most recently of several
-- (Hyprland's focusHistoryID, 0 the latest); its address, or nil when the app has none
function M.find_app(app, clients)
    local want = string.lower(type(app) == "string" and app or "")
    if want == "" or type(clients) ~= "table" then return nil end
    local best, bh
    for _, c in ipairs(clients) do
        if type(c) == "table" and c.mapped ~= false and type(c.address) == "string" then
            local cl, ti = string.lower(tostring(c.class or "")), string.lower(tostring(c.title or ""))
            if (cl ~= "" and (cl:find(want, 1, true) or want:find(cl, 1, true))) or ti:find(want, 1, true) then
                local h = tonumber(c.focusHistoryID) or 999
                if not best or h < bh then best, bh = c.address, h end
            end
        end
    end
    return best
end

-- where a line from `p` toward the window's middle meets its border (p inside: the nearest side)
function M.edge_point(p, r)
    local cx, cy = r.x + r.w / 2, r.y + r.h / 2
    local dx, dy = cx - p.x, cy - p.y
    local inside = p.x >= r.x and p.x <= r.x + r.w and p.y >= r.y and p.y <= r.y + r.h
    if inside or (dx == 0 and dy == 0) then
        local d = { p.x - r.x, p.y - r.y, r.x + r.w - p.x, r.y + r.h - p.y }
        local best = 1
        for i = 2, 4 do if d[i] < d[best] then best = i end end
        if best == 1 then return { x = r.x, y = p.y } elseif best == 2 then return { x = p.x, y = r.y }
        elseif best == 3 then return { x = r.x + r.w, y = p.y } end
        return { x = p.x, y = r.y + r.h }
    end
    local t = 1
    if dx ~= 0 then
        for _, sx in ipairs({ r.x, r.x + r.w }) do
            local s = (sx - p.x) / dx
            local y = p.y + s * dy
            if s >= 0 and s < t and y >= r.y - 0.01 and y <= r.y + r.h + 0.01 then t = s end
        end
    end
    if dy ~= 0 then
        for _, sy in ipairs({ r.y, r.y + r.h }) do
            local s = (sy - p.y) / dy
            local x = p.x + s * dx
            if s >= 0 and s < t and x >= r.x - 0.01 and x <= r.x + r.w + 0.01 then t = s end
        end
    end
    return { x = p.x + t * dx, y = p.y + t * dy }
end

-- which side of the window a point on its border is on: 0 top · 1 right · 2 bottom · 3 left
function M.side(p, r)
    local d = { math.abs(p.y - r.y), math.abs(p.x - (r.x + r.w)), math.abs(p.y - (r.y + r.h)), math.abs(p.x - r.x) }
    local best = 1
    for i = 2, 4 do if d[i] < d[best] then best = i end end
    return best - 1
end

-- D222: the screen's edge, where a notice's light travels when there is no window to reach (mooi's frame)
function M.frame(scr)
    local W, H = tonumber(scr and scr.w) or 1920, tonumber(scr and scr.h) or 1080
    return { x = 10, y = 10, w = W - 20, h = H - 20 }
end

-- the clock's sweep: when the hour turns ("HH:MM")
function M.hour(prev, now)
    if type(prev) ~= "string" or type(now) ~= "string" then return false end
    local a, b = prev:match("^(%d+):"), now:match("^(%d+):")
    return a ~= nil and b ~= nil and a ~= b
end

-- ── Live wallpaper (D219): its own feature, its own page ──
M.LIVE_FX = { "ripple", "breathe", "flow", "sweep" }
M.LIVE_MODE = { ripple = 1, breathe = 2, flow = 3, sweep = 4 }
M.LIVE_DEFAULT = {
    ripple = { on = true, strength = 60, size = 50, blend = 50 },
    breathe = { on = true, strength = 40, size = 50, blend = 60 },
    flow = { on = false, strength = 30, size = 50, blend = 70 },
    sweep = { on = true, strength = 60, size = 50, blend = 50 },
}
local function pct(v, d) local n = tonumber(v); if not n then return d end; return math.max(0, math.min(100, math.floor(n + 0.5))) end

-- the settings, read whole and clamped (whatever settings.json holds)
function M.live(settings)
    local l = type(settings) == "table" and type(settings.live) == "table" and settings.live or {}
    local out = { on = l.on ~= false, where = (l.where == "whole") and "whole" or "widgets",
                  speed = math.max(50, math.min(200, math.floor((tonumber(l.speed) or 100) + 0.5))), fx = {} }
    for _, k in ipairs(M.LIVE_FX) do
        local d, e = M.LIVE_DEFAULT[k], type(l[k]) == "table" and l[k] or {}
        local on = d.on
        if type(e.on) == "boolean" then on = e.on end
        out.fx[k] = { on = on, strength = pct(e.strength, d.strength), size = pct(e.size, d.size), blend = pct(e.blend, d.blend) }
    end
    -- D223: Music in the picture — its own card; the places it grows from are surface.json's (lib/surface/music)
    local m = type(l.music) == "table" and l.music or {}
    out.music = { on = m.on ~= false, strength = pct(m.strength, 70), size = pct(m.size, 50), blend = pct(m.blend, 40),
                  height = math.max(5, math.min(80, math.floor((tonumber(m.height) or 25) + 0.5))) }
    return out
end

-- one effect for its shader: kind · 1e6 + strength · 1e4 + size · 100 + blend, each 0 … 99 (under 2^24)
function M.pack(mode, strength, size, blend)
    local function c(v) return math.max(0, math.min(99, math.floor((tonumber(v) or 0) + 0.5))) end
    return mode * 1000000 + c(strength) * 10000 + c(size) * 100 + c(blend)
end

-- how much of the screen the windows hide (sampled on a 48 × 27 grid: overlaps counted once)
function M.covered_share(rects, scr)
    local W, H = tonumber(scr and scr.w) or 1920, tonumber(scr and scr.h) or 1080
    if type(rects) ~= "table" or #rects == 0 then return 0 end
    local n, hit = 0, 0
    for i = 0, 47 do
        for j = 0, 26 do
            n = n + 1
            if M.covered({ x = (i + 0.5) * W / 48, y = (j + 0.5) * H / 27 }, rects) then hit = hit + 1 end
        end
    end
    return hit / n
end

-- how far round a widget an effect's patch reaches (px), by its size
function M.reach(size) return 20 + (tonumber(size) or 50) * 2.8 end

return M
