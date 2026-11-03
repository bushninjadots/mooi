-- The desktop widgets' model (D137, docs/superpowers/specs/2026-11-03-widgets-design.md): what
-- widgets.json may hold, each layout's sizes, the 8 px grid and the snapping, where a new widget
-- goes, and what a widget does while nothing plays. Pure: mooi-widgets.luau and the settings
-- window read and write the file, this only works it out. `screen` is { w, h, top } (top: the
-- bar's reserve).

local M = {}

M.GRID = 8
M.MAX = 8
M.FILE = "widgets.json"
M.MARGIN = 64

M.LAYOUTS = {
    sleeve     = { min = { 288, 104 }, def = { 432, 152 }, max = { 864, 304 } },
    lyricstage = { min = { 480, 160 }, def = { 960, 240 }, max = { 1920, 480 } },
    record     = { min = { 200, 248 }, def = { 280, 352 }, max = { 480, 600 }, aspect = true },
    visualiser = { min = { 160, 64 }, def = { 640, 160 } },   -- no max: the screen
}
M.NP_LAYOUTS = { "sleeve", "lyricstage", "record" }
M.MODES = { "spectrum", "mirror", "ring", "aurora", "led", "orbit",
            "scope", "horizon", "dust", "ripple", "skyline", "liquid" }
M.MODE_INDEX, M.LAYOUT_INDEX = {}, {}
for i, m in ipairs(M.MODES) do M.MODE_INDEX[m] = i - 1 end
for i, l in ipairs(M.NP_LAYOUTS) do M.LAYOUT_INDEX[l] = i - 1 end
M.IDLE_INDEX = { hide = 0, rest = 1, marker = 2 }
M.IDLES = { "hide", "rest", "marker" }
M.DEFAULT_IDLE = { nowplaying = "rest", visualiser = "hide" }
M.DEFAULT_MODE = "spectrum"
-- every option a widget of each kind may carry, with its default
M.OPTIONS = {
    nowplaying = { lyrics = true, progress = true, plate = false, scroll_volume = true },
    visualiser = { glow = 0.6, mirror = false, plate = false },
}
local PREFIX = { nowplaying = "np", visualiser = "viz" }

local function grid(v) return math.floor(v / M.GRID + 0.5) * M.GRID end
local function clamp(v, lo, hi) if v < lo then return lo end; if hi and v > hi then return hi end; return v end
local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
    return o
end

function M.layout_of(w) return w.kind == "visualiser" and "visualiser" or w.layout end

-- A size this widget may have: inside its layout's limits, on the grid; a record keeps its shape.
function M.clamp_size(w, width, height)
    local L = M.LAYOUTS[M.layout_of(w)]
    local maxw, maxh = L.max and L.max[1], L.max and L.max[2]
    if L.aspect then
        local r = L.def[1] / L.def[2]
        local h = clamp(grid(height), L.min[2], maxh)
        return clamp(grid(h * r), L.min[1], maxw), h
    end
    return clamp(grid(width), L.min[1], maxw), clamp(grid(height), L.min[2], maxh)
end

-- The widget fully on the screen and under the bar (and never larger than the room there).
function M.clamp_rect(w, screen)
    local o = copy(w)
    local room_h = screen.h - (screen.top or 0)
    o.w, o.h = math.min(o.w, screen.w), math.min(o.h, room_h)
    o.x = clamp(o.x, 0, screen.w - o.w)
    o.y = clamp(o.y, screen.top or 0, screen.h - o.h)
    return o
end

function M.scale(w)
    local L = M.LAYOUTS[M.layout_of(w)]
    if w.kind == "visualiser" then return w.w / L.def[1] end
    return w.h / L.def[2]
end

-- One axis: the place nearest `v` within 8 px where the widget's start, end or middle meets a
-- line; the screen's edges first, then the other widgets'; else the grid. Returns place, line.
local function snap_axis(v, size, edges, lines)
    local best, line, dist = nil, nil, M.GRID + 0.001
    local function try(list)
        for _, t in ipairs(list) do
            for _, cand in ipairs({ t, t - size, t - size / 2 }) do
                local d = math.abs(cand - v)
                if d < dist then best, line, dist = cand, t, d end
            end
        end
    end
    try(edges)
    if not best then try(lines) end
    if best then return best, line end
    return grid(v), nil
end

function M.snap(doc, index, x, y, width, height, screen)
    local me = doc.widgets[index]
    local w, h = width, height
    if me then w, h = M.clamp_size(me, width, height) end
    local vx, hy = {}, {}
    for i, o in ipairs(doc.widgets) do
        if i ~= index then
            vx[#vx + 1] = o.x; vx[#vx + 1] = o.x + o.w; vx[#vx + 1] = o.x + o.w / 2
            hy[#hy + 1] = o.y; hy[#hy + 1] = o.y + o.h; hy[#hy + 1] = o.y + o.h / 2
        end
    end
    local sx, gx = snap_axis(x, w, { 0, screen.w }, vx)
    local sy, gy = snap_axis(y, h, { screen.top or 0, screen.h }, hy)
    local r = M.clamp_rect({ x = sx, y = sy, w = w, h = h }, screen)
    return r.x, r.y, r.w, r.h, { vx = gx, hy = gy }
end

local function overlaps(a, x, y, w, h, gap)
    return x < a.x + a.w + gap and a.x < x + w + gap and y < a.y + a.h + gap and a.y < y + h + gap
end

-- Where a new widget of this layout fits: the first free place, row by row from the bottom left.
function M.free_spot(doc, layout, screen)
    local L = M.LAYOUTS[layout]
    local w, h = math.min(L.def[1], screen.w), L.def[2]
    local top = screen.top or 0
    local y = screen.h - M.MARGIN - h
    while y >= top do
        local x = M.MARGIN
        while x + w <= screen.w do
            local free = true
            for _, o in ipairs(doc.widgets) do
                if overlaps(o, x, y, w, h, 16) then free = false; break end
            end
            if free then return x, y end
            x = x + M.GRID
        end
        y = y - M.GRID
    end
    return M.MARGIN, math.max(top, screen.h - M.MARGIN - h)
end

local function next_id(doc, kind)
    local n = 0
    local pre = PREFIX[kind]
    for _, o in ipairs(doc.widgets) do
        local k = tonumber(string.match(o.id or "", "^" .. pre .. "%-(%d+)$"))
        if k and k > n then n = k end
    end
    return pre .. "-" .. tostring(n + 1)
end

local function options_for(kind, given)
    local out = {}
    given = type(given) == "table" and given or {}
    for k, d in pairs(M.OPTIONS[kind]) do
        local v = given[k]
        if type(d) == "boolean" then out[k] = (type(v) == "boolean") and v or d
        else out[k] = tonumber(v) and clamp(tonumber(v), 0, 1) or d end
    end
    return out
end

local function new_widget(doc, kind, screen)
    local w = { kind = kind, idle = M.DEFAULT_IDLE[kind], options = options_for(kind, nil) }
    if kind == "nowplaying" then w.layout = "sleeve" else w.mode = M.DEFAULT_MODE end
    local L = M.LAYOUTS[M.layout_of(w)]
    w.w, w.h = math.min(L.def[1], screen.w), L.def[2]
    w.x, w.y = M.free_spot(doc, M.layout_of(w), screen)
    w.id = next_id(doc, kind)
    return w
end

function M.defaults(sw, sh)
    local L = M.LAYOUTS.sleeve
    return { version = 1, widgets = {
        { id = "np-1", kind = "nowplaying", layout = "sleeve", x = M.MARGIN, y = sh - L.def[2] - M.MARGIN,
          w = L.def[1], h = L.def[2], idle = "rest", options = options_for("nowplaying", nil) } } }
end

-- One saved entry made safe, or nil and why not.
local function clean(e, screen)
    if type(e) ~= "table" then return nil, "an entry that is not an object" end
    local kind = e.kind
    if kind ~= "nowplaying" and kind ~= "visualiser" then return nil, "unknown kind " .. tostring(kind) end
    local w = { kind = kind, id = type(e.id) == "string" and e.id or nil }
    if kind == "nowplaying" then
        if M.LAYOUT_INDEX[e.layout] == nil then return nil, "unknown layout " .. tostring(e.layout) end
        w.layout = e.layout
    else
        if M.MODE_INDEX[e.mode] == nil then return nil, "unknown mode " .. tostring(e.mode) end
        w.mode = e.mode
    end
    w.idle = M.IDLE_INDEX[e.idle] and e.idle or M.DEFAULT_IDLE[kind]
    w.options = options_for(kind, e.options)
    local L = M.LAYOUTS[M.layout_of(w)]
    w.w, w.h = M.clamp_size(w, tonumber(e.w) or L.def[1], tonumber(e.h) or L.def[2])
    w.x, w.y = tonumber(e.x) or M.MARGIN, tonumber(e.y) or (screen.h - M.MARGIN - w.h)
    return M.clamp_rect(w, screen)
end

-- widgets.json read: (doc, problems). No file → the defaults; a file that does not decode → the
-- defaults with doc.bad (the caller keeps the file as widgets.json.bad); bad entries dropped.
function M.parse(raw, decode, screen)
    local problems = {}
    if raw == nil then return M.defaults(screen.w, screen.h), problems end
    local ok, t = pcall(decode, raw)
    if not ok or type(t) ~= "table" then
        problems[1] = "widgets.json does not read: " .. tostring(t)
        local d = M.defaults(screen.w, screen.h)
        d.bad = true
        return d, problems
    end
    local doc = { version = 1, widgets = {} }
    local seen = {}
    for _, e in ipairs(type(t.widgets) == "table" and t.widgets or {}) do
        local w, why = clean(e, screen)
        if not w then problems[#problems + 1] = why
        elseif #doc.widgets >= M.MAX then problems[#problems + 1] = "more than " .. M.MAX .. " widgets: " .. tostring(w.id) .. " dropped"
        else
            if not w.id or seen[w.id] then w.id = next_id(doc, w.kind) end
            seen[w.id] = true
            doc.widgets[#doc.widgets + 1] = w
        end
    end
    return doc, problems
end

function M.encode(doc)
    local out = { version = 1, widgets = {} }
    for _, w in ipairs(doc.widgets) do
        out.widgets[#out.widgets + 1] = { id = w.id, kind = w.kind, layout = w.layout, mode = w.mode,
            x = w.x, y = w.y, w = w.w, h = w.h, idle = w.idle, options = copy(w.options or {}) }
    end
    return out
end

local function deep_eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
M.same_doc = deep_eq

local function find(doc, id)
    for i, w in ipairs(doc.widgets) do if w.id == id then return i, w end end
    return nil
end
M.find = find

function M.add(doc, kind, screen)
    if #doc.widgets >= M.MAX or not PREFIX[kind] then return doc, nil end
    local d = copy(doc)
    local w = new_widget(d, kind, screen)
    d.widgets[#d.widgets + 1] = w
    return d, w.id
end

function M.remove(doc, id)
    local d = copy(doc)
    local i = find(d, id)
    if i then table.remove(d.widgets, i) end
    return d
end

function M.duplicate(doc, id, screen)
    local i, w = find(doc, id)
    if not i or #doc.widgets >= M.MAX then return doc, nil end
    local d = copy(doc)
    local n = copy(w)
    n.id = next_id(d, w.kind)
    n.x, n.y = M.free_spot(d, M.layout_of(w), screen)
    n = M.clamp_rect(n, screen)
    d.widgets[#d.widgets + 1] = n
    return d, n.id
end

-- Another layout: the place kept, the new layout's own default size, still on the screen.
function M.set_layout(doc, id, layout, screen)
    local d = copy(doc)
    local i, w = find(d, id)
    if not i or w.kind ~= "nowplaying" or M.LAYOUT_INDEX[layout] == nil then return d end
    w.layout = layout
    local L = M.LAYOUTS[layout]
    w.w, w.h = L.def[1], L.def[2]
    d.widgets[i] = M.clamp_rect(w, screen)
    return d
end

function M.idle_state(w, playing)
    if playing then return "shown" end
    if w.idle == "hide" then return "hidden" end
    if w.idle == "marker" then return "marker" end
    return "rest"
end

-- Scene events are float32: slot (0..7) and two grid numbers (0..255) packed under 2^24.
function M.pack(slot, gx, gy) return slot * 65536 + gx * 256 + gy end
function M.unpack(n)
    n = math.floor(tonumber(n) or 0)
    local slot = math.floor(n / 65536)
    local rest = n - slot * 65536
    local gx = math.floor(rest / 256)
    return slot, gx, rest - gx * 256
end

return M
