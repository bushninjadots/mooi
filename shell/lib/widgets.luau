-- The desktop widgets' model (D137, docs/superpowers/specs/2026-11-03-widgets-design.md): what
-- widgets.json may hold, each layout's sizes, the 8 px grid and the snapping, where a new widget
-- goes, and what a widget does while nothing plays. Pure: mooi-widgets.luau and the settings
-- window read and write the file, this only works it out. `screen` is { w, h, top } (top: the
-- bar's reserve).

local M = {}

M.VERSION = 2
M.GRID = 8
M.MAX = 8
M.MAX_VIZ = 3             -- the scene draws three visualiser lanes (D138)
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
    nowplaying = { lyrics = true, progress = true, plate = false, scroll_volume = true, text = 1 },
    visualiser = { glow = 0.6, plate = false, bars = 64, gap = 0.3, smooth = 0.5, peaks = true, reflection = false },
}
-- the numbers' ranges (the rest are 0 … 1); `int` ones are whole
M.OPTION_RANGES = {
    bars = { 16, 128, true }, gap = { 0, 0.6 }, smooth = { 0, 1 }, text = { 0.8, 1.4 }, glow = { 0, 1 },
}
local function option_number(key, v, d)
    local r = M.OPTION_RANGES[key] or { 0, 1 }
    local n = tonumber(v)
    if not n then return d end
    if n < r[1] then n = r[1] elseif n > r[2] then n = r[2] end
    if r[3] then n = math.floor(n + 0.5) end
    return n
end
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

local function count_kind(doc, kind)
    local n = 0
    for _, w in ipairs(doc.widgets) do if w.kind == kind then n = n + 1 end end
    return n
end
M.count_kind = count_kind

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
        else out[k] = option_number(k, v, d) end
    end
    return out
end

local function new_widget(doc, kind, screen)
    local w = { kind = kind, idle = M.DEFAULT_IDLE[kind], options = options_for(kind, nil), opacity = 1, locked = false }
    if kind == "nowplaying" then w.layout = "sleeve" else w.mode = M.DEFAULT_MODE end
    local L = M.LAYOUTS[M.layout_of(w)]
    w.w, w.h = math.min(L.def[1], screen.w), L.def[2]
    w.x, w.y = M.free_spot(doc, M.layout_of(w), screen)
    w.id = next_id(doc, kind)
    return w
end

function M.defaults(sw, sh)
    local L = M.LAYOUTS.sleeve
    return { version = M.VERSION, widgets = {
        { id = "np-1", kind = "nowplaying", layout = "sleeve", x = M.MARGIN, y = sh - L.def[2] - M.MARGIN,
          w = L.def[1], h = L.def[2], idle = "rest", options = options_for("nowplaying", nil), opacity = 1, locked = false } } }
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
    w.opacity = clamp(tonumber(e.opacity) or 1, 0.3, 1)
    w.locked = e.locked == true
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
    local doc = { version = M.VERSION, widgets = {} }
    local seen = {}
    for _, e in ipairs(type(t.widgets) == "table" and t.widgets or {}) do
        local w, why = clean(e, screen)
        if not w then problems[#problems + 1] = why
        elseif #doc.widgets >= M.MAX then problems[#problems + 1] = "more than " .. M.MAX .. " widgets: " .. tostring(w.id) .. " dropped"
        elseif w.kind == "visualiser" and count_kind(doc, "visualiser") >= M.MAX_VIZ then
            problems[#problems + 1] = "more than " .. M.MAX_VIZ .. " visualisers: " .. tostring(w.id) .. " dropped"
        else
            if not w.id or seen[w.id] then w.id = next_id(doc, w.kind) end
            seen[w.id] = true
            doc.widgets[#doc.widgets + 1] = w
        end
    end
    return doc, problems
end

function M.encode(doc)
    local out = { version = M.VERSION, widgets = {} }
    for i, w in ipairs(doc.widgets) do
        out.widgets[#out.widgets + 1] = { id = w.id, kind = w.kind, layout = w.layout, mode = w.mode,
            x = w.x, y = w.y, w = w.w, h = w.h, idle = w.idle, options = copy(w.options or {}),
            z = i, opacity = w.opacity or 1, locked = w.locked == true }
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

-- Whether a widgets.json just read should replace what is shown: not when it is what is shown
-- already (the program's own write coming back), otherwise always — even if it equals an older write.
function M.should_reload(file_doc, shown)
    return not deep_eq(file_doc, M.encode(shown))
end
-- The pointed-at slots that still exist once there are only n widgets.
function M.prune_hover(hovered, n)
    local out = {}
    for k, v in pairs(hovered) do if k < n then out[k] = v end end
    return out
end

local function find(doc, id)
    for i, w in ipairs(doc.widgets) do if w.id == id then return i, w end end
    return nil
end
M.find = find

function M.add(doc, kind, screen)
    if #doc.widgets >= M.MAX or not PREFIX[kind] then return doc, nil end
    if kind == "visualiser" and count_kind(doc, "visualiser") >= M.MAX_VIZ then return doc, nil end
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
    if w.kind == "visualiser" and count_kind(doc, "visualiser") >= M.MAX_VIZ then return doc, nil end
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

-- One widget changed, the rest as they were; nonsense is ignored (a doc comes back unchanged).
local function change(doc, id, fn)
    local d = copy(doc)
    local i, w = find(d, id)
    if i then fn(w) end
    return d
end
function M.set_mode(doc, id, mode)
    return change(doc, id, function(w) if w.kind == "visualiser" and M.MODE_INDEX[mode] then w.mode = mode end end)
end
function M.set_idle(doc, id, idle)
    return change(doc, id, function(w) if M.IDLE_INDEX[idle] then w.idle = idle end end)
end
function M.set_option(doc, id, key, value)
    return change(doc, id, function(w)
        local d = M.OPTIONS[w.kind][key]
        if d == nil then return end
        w.options = w.options or {}
        if type(d) == "boolean" then w.options[key] = value == true
        else w.options[key] = option_number(key, value, w.options[key] or d) end
    end)
end
-- Where a dragged or resized widget settles: its own limits, on the screen.
function M.set_rect(doc, id, x, y, width, height, screen)
    local d = copy(doc)
    local i, w = find(d, id)
    if not i then return d end
    w.w, w.h = M.clamp_size(w, width, height)
    w.x, w.y = x, y
    d.widgets[i] = M.clamp_rect(w, screen)
    return d
end
-- The options panel's place: beside the widget, right if there is room, else left; on the screen.
-- With no room either side (a full-width visualiser), above it, or below it when the top is short.
function M.panel_spot(w, pw, ph, screen)
    local gap, top = 12, screen.top or 0
    if w.x + w.w + gap + pw <= screen.w then return w.x + w.w + gap, clamp(w.y, top, screen.h - ph) end
    if w.x - gap - pw >= 0 then return w.x - gap - pw, clamp(w.y, top, screen.h - ph) end
    local x = clamp(w.x, 0, screen.w - pw)
    if w.y - gap - ph >= top then return x, w.y - gap - ph end
    return x, clamp(w.y + w.h + gap, top, screen.h - ph)
end

-- ── The editor's operations (D138) ──
function M.set_field(doc, id, key, value)
    return change(doc, id, function(w)
        if key == "opacity" then w.opacity = clamp(tonumber(value) or 1, 0.3, 1)
        elseif key == "locked" then w.locked = value == true end
    end)
end

-- the selected widgets, in the order given: { i, w } each
local function picked(doc, ids)
    local out = {}
    for _, id in ipairs(ids) do
        local i, w = find(doc, id)
        if i then out[#out + 1] = { i = i, w = w } end
    end
    return out
end

function M.nudge(doc, ids, dx, dy, screen)
    local d = copy(doc)
    local skipped = 0
    for _, p in ipairs(picked(d, ids)) do
        if p.w.locked then skipped = skipped + 1
        else
            p.w.x, p.w.y = p.w.x + dx, p.w.y + dy
            d.widgets[p.i] = M.clamp_rect(p.w, screen)
        end
    end
    return d, skipped
end

function M.align(doc, ids, how, screen)
    local d = copy(doc)
    local sel = picked(d, ids)
    if #sel < 2 then return d, 0 end
    local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(sel) do
        l, t = math.min(l, p.w.x), math.min(t, p.w.y)
        r, b = math.max(r, p.w.x + p.w.w), math.max(b, p.w.y + p.w.h)
    end
    local skipped = 0
    for _, p in ipairs(sel) do
        local w = p.w
        if w.locked then skipped = skipped + 1
        else
            if how == "left" then w.x = l
            elseif how == "right" then w.x = r - w.w
            elseif how == "centre" then w.x = (l + r) / 2 - w.w / 2
            elseif how == "top" then w.y = t
            elseif how == "bottom" then w.y = b - w.h
            elseif how == "middle" then w.y = (t + b) / 2 - w.h / 2 end
            w.x, w.y = math.floor(w.x + 0.5), math.floor(w.y + 0.5)
            d.widgets[p.i] = M.clamp_rect(w, screen)
        end
    end
    return d, skipped
end

-- Even gaps between the selected (locked ones are left out), the outer two staying where they are.
function M.distribute(doc, ids, axis, screen)
    local d = copy(doc)
    local sel, skipped = {}, 0
    for _, p in ipairs(picked(d, ids)) do
        if p.w.locked then skipped = skipped + 1 else sel[#sel + 1] = p end
    end
    if #sel < 3 then return d, skipped end
    local pos, size = (axis == "v") and "y" or "x", (axis == "v") and "h" or "w"
    table.sort(sel, function(a, b) return a.w[pos] < b.w[pos] end)
    local first, last = sel[1].w, sel[#sel].w
    local total, sum = last[pos] + last[size] - first[pos], 0
    for _, p in ipairs(sel) do sum = sum + p.w[size] end
    local gap = (total - sum) / (#sel - 1)
    local at = first[pos]
    for _, p in ipairs(sel) do
        p.w[pos] = math.floor(at + 0.5)
        at = at + p.w[size] + gap
        d.widgets[p.i] = M.clamp_rect(p.w, screen)
    end
    return d, skipped
end

-- The first selected widget's width (or height) given to the rest, inside their own limits.
function M.match(doc, ids, dim, screen)
    local d = copy(doc)
    local sel = picked(d, ids)
    if #sel < 2 then return d, 0 end
    local want, skipped = sel[1].w[dim], 0
    for k = 2, #sel do
        local w = sel[k].w
        if w.locked then skipped = skipped + 1
        else
            local nw, nh = M.clamp_size(w, dim == "w" and want or w.w, dim == "h" and want or w.h)
            w.w, w.h = nw, nh
            d.widgets[sel[k].i] = M.clamp_rect(w, screen)
        end
    end
    return d, skipped
end

-- A handle dragged (0 tl, 1 t, 2 tr, 3 r, 4 br, 5 b, 6 bl, 7 l): the opposite edges stay where
-- they are, the size keeps its limits (a record its shape) and the room on the screen.
local MOVES_L = { [0] = true, [6] = true, [7] = true }
local MOVES_R = { [2] = true, [3] = true, [4] = true }
local MOVES_T = { [0] = true, [1] = true, [2] = true }
local MOVES_B = { [4] = true, [5] = true, [6] = true }
function M.resize_from(doc, id, handle, dx, dy, screen)
    local _, w = find(doc, id)
    if not w then return 0, 0, 0, 0 end
    local l, t, r, b = w.x, w.y, w.x + w.w, w.y + w.h
    local top = screen.top or 0
    local nl, nt, nr, nb = l, t, r, b
    if MOVES_L[handle] then nl = l + dx end
    if MOVES_R[handle] then nr = r + dx end
    if MOVES_T[handle] then nt = t + dy end
    if MOVES_B[handle] then nb = b + dy end
    local maxw = MOVES_L[handle] and r or (screen.w - l)
    local maxh = MOVES_T[handle] and (b - top) or (screen.h - t)
    local ww = math.min(nr - nl, math.floor(maxw / M.GRID) * M.GRID)
    local hh = math.min(nb - nt, math.floor(maxh / M.GRID) * M.GRID)
    local L = M.LAYOUTS[M.layout_of(w)]
    if L.aspect then
        -- a side handle changes the other side with it; the height leads
        if handle == 3 or handle == 7 then hh = ww * L.def[2] / L.def[1] end
        local ratio = L.def[1] / L.def[2]
        if hh * ratio > maxw then hh = maxw / ratio end
        hh = math.floor(math.min(hh, maxh) / M.GRID) * M.GRID
    end
    ww, hh = M.clamp_size(w, ww, hh)
    local x = MOVES_L[handle] and (r - ww) or l
    local y = MOVES_T[handle] and (b - hh) or t
    local c = M.clamp_rect({ x = x, y = y, w = ww, h = hh }, screen)
    return c.x, c.y, c.w, c.h
end

-- Selection as a bit mask over the slots (slot i is 2^i).
function M.marquee(doc, x0, y0, x1, y1)
    local l, r = math.min(x0, x1), math.max(x0, x1)
    local t, b = math.min(y0, y1), math.max(y0, y1)
    local mask = 0
    for i, w in ipairs(doc.widgets) do
        if w.x < r and l < w.x + w.w and w.y < b and t < w.y + w.h then mask = mask + 2 ^ (i - 1) end
    end
    return math.floor(mask)
end
function M.ids_of(doc, mask)
    local out = {}
    mask = math.floor(tonumber(mask) or 0)
    for i, w in ipairs(doc.widgets) do
        if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then out[#out + 1] = w.id end
    end
    return out
end
function M.mask_of(doc, ids)
    local mask = 0
    for _, id in ipairs(ids) do
        local i = find(doc, id)
        if i then mask = mask + 2 ^ (i - 1) end
    end
    return math.floor(mask)
end

-- Drawing order is the list's order (later is in front).
function M.raise(doc, ids, dir)
    local d = copy(doc)
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    local list = d.widgets
    if dir == "front" or dir == "back" then
        local mine, rest = {}, {}
        for _, w in ipairs(list) do if want[w.id] then mine[#mine + 1] = w else rest[#rest + 1] = w end end
        local out = {}
        local a, b = (dir == "front") and rest or mine, (dir == "front") and mine or rest
        for _, w in ipairs(a) do out[#out + 1] = w end
        for _, w in ipairs(b) do out[#out + 1] = w end
        d.widgets = out
    elseif dir == "forward" then
        for i = #list - 1, 1, -1 do
            if want[list[i].id] and not want[list[i + 1].id] then list[i], list[i + 1] = list[i + 1], list[i] end
        end
    elseif dir == "backward" then
        for i = 2, #list do
            if want[list[i].id] and not want[list[i - 1].id] then list[i], list[i - 1] = list[i - 1], list[i] end
        end
    end
    return d
end

-- Undo: the docs before each change (at most 30), and the ones undone.
function M.history() return { undo = {}, redo = {}, max = 30 } end
function M.push(h, doc)
    h.undo[#h.undo + 1] = copy(doc)
    if #h.undo > h.max then table.remove(h.undo, 1) end
    h.redo = {}
end
function M.undo(h, current)
    if #h.undo == 0 then return nil end
    local prev = table.remove(h.undo)
    h.redo[#h.redo + 1] = copy(current)
    return prev
end
function M.redo(h, current)
    if #h.redo == 0 then return nil end
    local nxt = table.remove(h.redo)
    h.undo[#h.undo + 1] = copy(current)
    return nxt
end
function M.clear(h) h.undo, h.redo = {}, {} end

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
