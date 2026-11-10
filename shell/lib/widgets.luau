-- The desktop widgets' model (D137, docs/superpowers/specs/2026-11-03-widgets-design.md): what
-- widgets.json may hold, each layout's sizes, the 8 px grid and the snapping, where a new widget
-- goes, and what a widget does while nothing plays. Pure: mooi-widgets.luau and the settings
-- window read and write the file, this only works it out. `screen` is { w, h, top } (top: the
-- bar's reserve).

local M = {}

M.VERSION = 2
M.GRID = 8
M.MAX = 16               -- sixteen widgets (D215: the subsurface's four kinds beside the twelve)
M.MAX_VIZ = 3             -- the scene draws three visualiser lanes (D138)
M.FILE = "widgets.json"
M.MARGIN = 64

M.LAYOUTS = {
    sleeve     = { min = { 288, 104 }, def = { 432, 152 }, max = { 864, 304 } },
    lyricstage = { min = { 480, 160 }, def = { 960, 240 }, max = { 1920, 480 } },
    record     = { min = { 200, 248 }, def = { 280, 352 }, max = { 480, 600 }, aspect = true },
    visualiser = { min = { 160, 64 }, def = { 640, 160 } },   -- no max: the screen
    -- D140: clocks, notes, GitHub
    digital  = { min = { 240, 96 }, def = { 400, 150 }, max = { 1200, 450 } },
    analogue = { min = { 140, 140 }, def = { 240, 240 }, max = { 640, 640 }, aspect = true },
    words    = { min = { 280, 90 }, def = { 480, 140 }, max = { 1400, 420 } },
    info     = { min = { 320, 140 }, def = { 440, 190 }, max = { 1100, 475 } },
    -- D301: more designs for the same kinds
    flip     = { min = { 240, 120 }, def = { 400, 180 }, max = { 1200, 540 } },
    minimal  = { min = { 240, 80 }, def = { 400, 130 }, max = { 1200, 390 } },
    dots     = { min = { 240, 120 }, def = { 400, 180 }, max = { 1200, 540 } },
    list     = { min = { 260, 160 }, def = { 360, 300 }, max = { 900, 900 } },
    card     = { min = { 300, 140 }, def = { 400, 190 }, max = { 900, 430 } },
    commits  = { min = { 320, 200 }, def = { 440, 320 }, max = { 1000, 800 } },
    pulse    = { min = { 320, 160 }, def = { 440, 220 }, max = { 1100, 560 } },
    heat     = { min = { 420, 120 }, def = { 640, 170 }, max = { 1400, 380 } },
    -- D141: weather, system, calendar, focus timer, Claude, photo, launcher
    horizon  = { min = { 360, 120 }, def = { 560, 170 }, max = { 1600, 480 } },
    days     = { min = { 320, 130 }, def = { 460, 170 }, max = { 1200, 440 } },
    glance   = { min = { 220, 160 }, def = { 300, 220 }, max = { 600, 600 }, aspect = true },
    week     = { min = { 420, 150 }, def = { 560, 200 }, max = { 1200, 500 } },
    scope    = { min = { 300, 130 }, def = { 420, 180 }, max = { 1200, 520 } },
    gauges   = { min = { 300, 110 }, def = { 420, 150 }, max = { 1100, 400 } },
    bars     = { min = { 300, 150 }, def = { 420, 210 }, max = { 1100, 560 } },
    rings    = { min = { 220, 220 }, def = { 300, 300 }, max = { 600, 600 }, aspect = true },
    month    = { min = { 260, 240 }, def = { 340, 320 }, max = { 800, 760 } },
    agenda   = { min = { 260, 240 }, def = { 340, 360 }, max = { 800, 800 } },
    sticky   = { min = { 220, 200 }, def = { 300, 280 }, max = { 600, 600 }, aspect = true },
    ring     = { min = { 160, 160 }, def = { 240, 240 }, max = { 600, 600 }, aspect = true },
    slab     = { min = { 280, 90 }, def = { 420, 130 }, max = { 1100, 340 } },
    bar      = { min = { 300, 80 }, def = { 440, 110 }, max = { 1200, 220 } },
    ticker   = { min = { 360, 64 }, def = { 640, 84 }, max = { 1920, 200 } },
    quote    = { min = { 300, 140 }, def = { 420, 200 }, max = { 1000, 560 } },
    frame    = { min = { 200, 160 }, def = { 360, 270 }, max = { 1200, 900 } },
    polaroid = { min = { 180, 210 }, def = { 260, 300 }, max = { 700, 810 }, aspect = true },
    circle   = { min = { 180, 180 }, def = { 240, 240 }, max = { 600, 600 }, aspect = true },
    shelf    = { min = { 200, 64 }, def = { 480, 84 }, max = { 1600, 160 } },
    column   = { min = { 64, 200 }, def = { 84, 440 }, max = { 160, 1000 } },
    -- D215: what lives below the wallpaper — Launch's grid, the notices, the wallpapers, the settings, the controls
    grid     = { min = { 300, 200 }, def = { 360, 240 }, max = { 1200, 800 } },
    stack    = { min = { 280, 200 }, def = { 360, 260 }, max = { 900, 700 } },
    strip    = { min = { 300, 110 }, def = { 420, 140 }, max = { 1400, 320 } },
    pages    = { min = { 260, 130 }, def = { 320, 170 }, max = { 800, 420 } },
    row      = { min = { 420, 72 }, def = { 452, 80 }, max = { 900, 140 } },
    ccolumn  = { min = { 72, 420 }, def = { 80, 452 }, max = { 140, 900 } },
}
-- each kind's layouts, in order (the first is a new one's)
M.KIND_LAYOUTS = {
    nowplaying = { "sleeve", "lyricstage", "record" },
    clock = { "digital", "analogue", "words", "info", "flip", "minimal", "dots" },
    notes = { "list", "sticky" },
    github = { "card", "commits", "pulse", "heat" },
    weather = { "horizon", "days", "glance", "week" },
    system = { "scope", "gauges", "bars", "rings" },
    calendar = { "month", "agenda" },
    timer = { "ring", "slab", "bar" },
    claude = { "ticker", "quote" },
    photo = { "frame", "polaroid", "circle" },
    launch = { "shelf", "column", "grid" },
    notices = { "stack" },
    wallpapers = { "strip" },
    settings = { "pages" },
    controls = { "row", "ccolumn" },
}
-- how many of a kind the scene can draw (the rest by M.MAX)
M.KIND_MAX = { visualiser = 3, notes = 1, github = 2, weather = 1, system = 1, calendar = 1, timer = 1, claude = 1, photo = 1, launch = 1,
               notices = 1, wallpapers = 1, settings = 1, controls = 1 }
-- the kinds that follow the music (the idle rule is theirs; the rest are always shown, and rest with ambient)
M.MUSIC = { nowplaying = true, visualiser = true }
-- each kind's number in the scene (model wg.kind)
M.KIND_NUM = { nowplaying = 0, visualiser = 1, clock = 2, notes = 3, github = 4, weather = 5, system = 6, calendar = 7,
               timer = 8, claude = 9, photo = 10, launch = 11,
               notices = 12, wallpapers = 13, settings = 14, controls = 15 }
M.ADD_ORDER = { "nowplaying", "visualiser", "clock", "notes", "github", "weather", "system", "calendar", "timer", "claude", "photo", "launch",
               "notices", "wallpapers", "settings", "controls" }
M.NP_LAYOUTS = { "sleeve", "lyricstage", "record" }
M.KINDS = {}
for k in pairs(M.KIND_NUM) do M.KINDS[k] = true end
M.MODES = { "spectrum", "mirror", "ring", "aurora", "led", "orbit",
            "scope", "horizon", "dust", "ripple", "skyline", "liquid" }
M.MODE_INDEX, M.LAYOUT_INDEX = {}, {}
for i, m in ipairs(M.MODES) do M.MODE_INDEX[m] = i - 1 end
for _, list in pairs(M.KIND_LAYOUTS) do for i, l in ipairs(list) do M.LAYOUT_INDEX[l] = i - 1 end end
M.LAYOUT_KIND = {}
for kind, list in pairs(M.KIND_LAYOUTS) do for _, l in ipairs(list) do M.LAYOUT_KIND[l] = kind end end
M.IDLE_INDEX = { hide = 0, rest = 1, marker = 2 }
M.IDLES = { "hide", "rest", "marker" }
M.DEFAULT_IDLE = { nowplaying = "rest", visualiser = "hide" }   -- every other kind: "rest" (the rule is only the music's)
M.DEFAULT_MODE = "spectrum"
-- every option a widget of each kind may carry, with its default
M.OPTIONS = {
    nowplaying = { meet = "woven", lyrics = true, progress = true, plate = false, scroll_volume = true, text = 1, adapt = true, behind = false, viz = false },
    visualiser = { meet = "moves", glow = 0.6, plate = false, bars = 64, gap = 0.3, smooth = 0.5, angle = 0, lean = 0, peaks = true, reflection = false, adapt = true, behind = false },
    clock = { meet = "moves", h24 = true, seconds = true, plate = false, adapt = true, behind = false },
    notes = { rows = 6, plate = false, adapt = true, behind = false },
    github = { repo = "bushninjadots/mooi", plate = false, adapt = true, behind = false },
    weather = { plate = false, adapt = true, behind = false },
    system = { plate = false, adapt = true, behind = false },
    calendar = { plate = false, adapt = true, behind = false },
    timer = { minutes = 25, plate = false, adapt = true, behind = false },
    claude = { plate = false, adapt = true, behind = false },
    photo = { folder = "~/Pictures", every = 10, pop = true, plate = false, adapt = true, behind = false },
    launch = { apps = "kitty,zen,code,nautilus,spotify", plate = false, adapt = true, behind = false },
    notices = { meet = "woven", nrows = 4, plate = false, adapt = true, behind = false },
    wallpapers = { plate = false, adapt = true, behind = false },
    settings = { plate = false, adapt = true, behind = false },
    controls = { wifi = true, bt = true, volume = true, bright = true, battery = true, power = true,
                 power_confirm = true, plate = false, adapt = true, behind = false },
}
-- the look of them all (widgets.json, beside the list): a style, the ambient rest, shadows
M.STYLES = { "adaptive", "phosphor", "ink", "chrome", "paper" }
M.STYLE_INDEX = {}
for i, s in ipairs(M.STYLES) do M.STYLE_INDEX[s] = i - 1 end
-- the numbers' ranges (the rest are 0 … 1); `int` ones are whole
M.OPTION_RANGES = {
    minutes = { 1, 180, true }, every = { 1, 120, true }, bars = { 16, 128, true }, gap = { 0, 0.6 }, smooth = { 0, 1 }, text = { 0.8, 1.4 }, glow = { 0, 1 }, rows = { 3, 20, true },
    angle = { -180, 180 },
    lean = { -40, 40 },
    nrows = { 3, 6, true },
}
-- the text options: a GitHub repository is owner/name
function M.option_string(key, v)
    if key == "repo" and type(v) == "string" and v:match("^[%w%-%._]+/[%w%-%._]+$") then return v end
    if key == "folder" and type(v) == "string" and #v > 0 and #v < 400 and not v:find("[%c]") then return v end
    -- the launcher's apps: desktop file ids or commands, comma-separated, twelve at most
    if key == "apps" and type(v) == "string" and #v < 600 and not v:find("[%c;|&$`]") then return v end
    -- D217: how it meets the wallpaper while below (lib/surface/skin): pushing up, moving it, or still
    if key == "meet" and (v == "woven" or v == "moves" or v == "still") then return v end
    return nil
end
local function option_number(key, v, d)
    local r = M.OPTION_RANGES[key] or { 0, 1 }
    local n = tonumber(v)
    if not n then return d end
    if n < r[1] then n = r[1] elseif n > r[2] then n = r[2] end
    if r[3] then n = math.floor(n + 0.5) end
    return n
end
local PREFIX = { nowplaying = "np", visualiser = "viz", clock = "clk", notes = "nts", github = "gh", weather = "wx",
                 system = "sys", calendar = "cal", timer = "tmr", claude = "cl", photo = "ph", launch = "ln",
                 notices = "nc", wallpapers = "wp", settings = "pg", controls = "ct" }

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

-- D209: a widget dragged out of the opening is kept above the wallpaper, wholly on the screen and
-- with the bar's reserve's worth of room under it. x, y are the widget area's coordinates (its 0 is
-- the bar's reserve down); above is set.
function M.keep_at(w, x, y, scr, bar_h)
    local o = copy(w)
    o.x = clamp(math.floor((tonumber(x) or 0) + 0.5), 0, math.max(0, scr.w - o.w))
    o.y = clamp(math.floor((tonumber(y) or 0) + 0.5), 0, math.max(0, scr.h - (bar_h or 0) - o.h))
    o.above = true
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
        -- (D218: not `and v or d`, which read every switch saved off as its default)
        if type(d) == "boolean" then if type(v) == "boolean" then out[k] = v else out[k] = d end
        elseif type(d) == "string" then out[k] = M.option_string(k, v) or d
        else out[k] = option_number(k, v, d) end
    end
    return out
end

local function new_widget(doc, kind, screen)
    local w = { kind = kind, idle = M.DEFAULT_IDLE[kind] or "rest", options = options_for(kind, nil), opacity = 1, locked = false }
    if kind == "visualiser" then w.mode = M.DEFAULT_MODE else w.layout = M.KIND_LAYOUTS[kind][1] end
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
    if not M.KINDS[kind] then return nil, "unknown kind " .. tostring(kind) end
    local w = { kind = kind, id = type(e.id) == "string" and e.id or nil }
    if kind ~= "visualiser" then
        if M.LAYOUT_KIND[e.layout] ~= kind then return nil, "unknown layout " .. tostring(e.layout) end
        w.layout = e.layout
    else
        if M.MODE_INDEX[e.mode] == nil then return nil, "unknown mode " .. tostring(e.mode) end
        w.mode = e.mode
    end
    w.idle = M.IDLE_INDEX[e.idle] and e.idle or M.DEFAULT_IDLE[kind] or "rest"
    w.group = type(e.group) == "string" and #e.group > 0 and #e.group < 40 and e.group or nil
    w.options = options_for(kind, e.options)
    w.opacity = clamp(tonumber(e.opacity) or 1, 0.3, 1)
    w.locked = e.locked == true
    w.above = e.above == true       -- D209: kept above the wallpaper
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
    doc.style = M.STYLE_INDEX[t.style] and t.style or "adaptive"
    doc.ambient = t.ambient ~= false
    doc.shadows = t.shadows == true
    -- D215: the subsurface's once-only steps, and Launch's grid counts
    doc.below_seeded = t.below_seeded == true
    doc.migrated_presences = t.migrated_presences == true
    doc.launch_counts = {}
    for k, v in pairs(type(t.launch_counts) == "table" and t.launch_counts or {}) do
        if type(k) == "string" and #k < 200 and tonumber(v) then doc.launch_counts[k] = math.floor(tonumber(v)) end
    end
    local seen = {}
    for _, e in ipairs(type(t.widgets) == "table" and t.widgets or {}) do
        local w, why = clean(e, screen)
        if not w then problems[#problems + 1] = why
        elseif #doc.widgets >= M.MAX then problems[#problems + 1] = "more than " .. M.MAX .. " widgets: " .. tostring(w.id) .. " dropped"
        elseif M.KIND_MAX[w.kind] and count_kind(doc, w.kind) >= M.KIND_MAX[w.kind] then
            problems[#problems + 1] = "more than " .. M.KIND_MAX[w.kind] .. " " .. w.kind .. ": " .. tostring(w.id) .. " dropped"
        else
            if not w.id or seen[w.id] then w.id = next_id(doc, w.kind) end
            seen[w.id] = true
            doc.widgets[#doc.widgets + 1] = w
        end
    end
    return doc, problems
end

function M.encode(doc)
    local out = { version = M.VERSION, widgets = {}, style = doc.style or "adaptive", ambient = doc.ambient ~= false,
                  shadows = doc.shadows == true, below_seeded = doc.below_seeded == true,
                  migrated_presences = doc.migrated_presences == true, launch_counts = copy(doc.launch_counts or {}) }
    for i, w in ipairs(doc.widgets) do
        out.widgets[#out.widgets + 1] = { id = w.id, kind = w.kind, layout = w.layout, mode = w.mode,
            x = w.x, y = w.y, w = w.w, h = w.h, idle = w.idle, options = copy(w.options or {}),
            z = i, opacity = w.opacity or 1, locked = w.locked == true, group = w.group, above = w.above == true }
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
    if M.KIND_MAX[kind] and count_kind(doc, kind) >= M.KIND_MAX[kind] then return doc, nil end
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
    if M.KIND_MAX[w.kind] and count_kind(doc, w.kind) >= M.KIND_MAX[w.kind] then return doc, nil end
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
    if not i or M.LAYOUT_KIND[layout] ~= w.kind then return d end
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
        elseif type(d) == "string" then w.options[key] = M.option_string(key, value) or w.options[key] or d
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
    -- a record's width comes from its height and may round past the room; step down until it fits
    while L.aspect and ww > maxw and hh > L.min[2] do ww, hh = M.clamp_size(w, ww, hh - M.GRID) end
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
    if playing or (w.kind and not M.MUSIC[w.kind]) then return "shown" end
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

-- The look of them all (D141): style (one of M.STYLES), shadows, ambient.
function M.set_look(doc, key, value)
    local d = copy(doc)
    if key == "style" and M.STYLE_INDEX[value] then d.style = value
    elseif key == "shadows" then d.shadows = value == true
    elseif key == "ambient" then d.ambient = value == true end
    return d
end

-- D210: one field on every widget at once — above the wallpaper, below it, plated. The Subsurface's
-- settings page uses it so the owner can take the whole desktop back with one press.
function M.set_all(doc, key, value)
    local d = copy(doc)
    for _, w in ipairs(d.widgets) do w[key] = value end
    return d
end

-- D222: one widget on the desktop (above the wallpaper: always shown, an ordinary widget) or below it (only in
-- the opening). Set from its editor.
function M.set_above(doc, id, on)
    return change(doc, id, function(w) w.above = on == true end)
end

-- ── Groups (D141): widgets chosen, carried and faded as one ──
-- The chosen ones made a group (a new id); any group they were in is left. A group of one is none.
function M.group(doc, ids)
    if #ids < 2 then return doc end
    local d = copy(doc)
    local n = 1
    local used = {}
    for _, w in ipairs(d.widgets) do if w.group then used[w.group] = true end end
    while used["g" .. n] do n = n + 1 end
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    for _, w in ipairs(d.widgets) do if want[w.id] then w.group = "g" .. n end end
    return M.tidy_groups(d)
end
function M.ungroup(doc, ids)
    local d = copy(doc)
    local gone = {}
    for _, id in ipairs(ids) do
        local _, w = find(d, id)
        if w and w.group then gone[w.group] = true end
    end
    for _, w in ipairs(d.widgets) do if w.group and gone[w.group] then w.group = nil end end
    return d
end
-- groups left with one member are dissolved
function M.tidy_groups(d)
    local n = {}
    for _, w in ipairs(d.widgets) do if w.group then n[w.group] = (n[w.group] or 0) + 1 end end
    for _, w in ipairs(d.widgets) do if w.group and n[w.group] < 2 then w.group = nil end end
    return d
end
-- the ids, with every member of their groups
function M.with_groups(doc, ids)
    local groups, out, seen = {}, {}, {}
    for _, id in ipairs(ids) do
        local _, w = find(doc, id)
        if w and w.group then groups[w.group] = true end
    end
    for _, id in ipairs(ids) do if not seen[id] then seen[id] = true; out[#out + 1] = id end end
    for _, w in ipairs(doc.widgets) do
        if w.group and groups[w.group] and not seen[w.id] then seen[w.id] = true; out[#out + 1] = w.id end
    end
    return out
end
-- each widget's group as a number (0 none, 1 … for the scene's "GROUPED" tags)
function M.group_numbers(doc)
    local num, out, n = {}, {}, 0
    for i, w in ipairs(doc.widgets) do
        if w.group then
            if not num[w.group] then n = n + 1; num[w.group] = n end
            out[i] = num[w.group]
        else out[i] = 0 end
    end
    return out
end

-- ── Desk mode (D141): every widget gathered into one arrangement, centred, for a look ──
-- Rows filled left to right (a group's members kept together, the taller first), each row centred,
-- the block centred under the bar. Returns { { x, y } } in the doc's order; one that does not fit
-- keeps its own place.
function M.desk_layout(doc, screen, gap)
    gap = gap or 24
    local top = screen.top or 0
    local room_w, room_h = screen.w - 2 * M.MARGIN, screen.h - top - 2 * 32
    local order = {}
    for i in ipairs(doc.widgets) do order[#order + 1] = i end
    local gnum = M.group_numbers(doc)
    table.sort(order, function(a, b)
        local ga, gb = gnum[a] > 0 and gnum[a] or 1000 + a, gnum[b] > 0 and gnum[b] or 1000 + b
        if ga ~= gb then
            -- groups first, then by height
            local ha, hb = doc.widgets[a].h, doc.widgets[b].h
            if (gnum[a] > 0) ~= (gnum[b] > 0) then return gnum[a] > 0 end
            if gnum[a] > 0 then return ga < gb end
            if ha ~= hb then return ha > hb end
        end
        return a < b
    end)
    local rows, row, rw, rh = {}, {}, 0, 0
    for _, i in ipairs(order) do
        local w = doc.widgets[i]
        local need = (#row > 0 and gap or 0) + w.w
        if #row > 0 and rw + need > room_w then rows[#rows + 1] = { items = row, w = rw, h = rh }; row, rw, rh = {}, 0, 0; need = w.w end
        row[#row + 1] = i; rw = rw + need; rh = math.max(rh, w.h)
    end
    if #row > 0 then rows[#rows + 1] = { items = row, w = rw, h = rh } end
    local total = 0
    for k, r in ipairs(rows) do total = total + r.h + (k > 1 and gap or 0) end
    local out = {}
    local y = top + 32 + math.max(0, (room_h - total) / 2)
    for _, r in ipairs(rows) do
        local x = M.MARGIN + math.max(0, (room_w - r.w) / 2)
        for _, i in ipairs(r.items) do
            local w = doc.widgets[i]
            if y + r.h <= screen.h and x + w.w <= screen.w then
                out[i] = { x = math.floor(x), y = math.floor(y + (r.h - w.h) / 2) }
            else out[i] = { x = w.x, y = w.y } end
            x = x + w.w + gap
        end
        y = y + r.h + gap
    end
    return out
end

return M
