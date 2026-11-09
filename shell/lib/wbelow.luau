-- The widgets below (D215, docs/superpowers/specs/2026-11-09-widgets-below-design.md): what lives under the
-- wallpaper is mooi's widgets. Pure: the default set placed once, the whole set re-arranged, the Presences of
-- D208 turned into widgets kept above, the Launch grid's apps and the Settings widget's pages. `screen` is the
-- widgets' { w, h, top } (top: the bar's reserve; widgets are placed in the surface below it).

local W = require("lib/widgets")
local below = require("lib/surface/below")

local M = {}

-- the default set, in order: kind and layout (the visualiser has a mode instead)
M.DEFAULT_SET = {
    { "nowplaying", "sleeve" }, { "visualiser" }, { "launch", "grid" }, { "clock", "digital" },
    { "calendar", "month" }, { "weather", "horizon" }, { "notices", "stack" }, { "wallpapers", "strip" },
    { "settings", "pages" }, { "controls", "row" },
}

-- a Presence's source → the widget that does its work
M.MIGRATE = { music = "nowplaying", clock = "clock", calendar = "calendar", weather = "weather",
              notifications = "notices", volume = "controls", network = "controls", bluetooth = "controls",
              battery = "controls", resources = "system" }

-- the Settings widget's marks: the word, and the page's tab in mooi-settings (lib/settings_index's `tab`)
M.SETTINGS = { { "Theme & colour", 1 }, { "Bar & Frame", 3 }, { "Wallpapers", 9 }, { "Widgets", 10 },
               { "Sound", 12 }, { "Power", 13 }, { "BMO", 11 }, { "The Subsurface", 20 } }

local function room(screen) return { w = screen.w, h = screen.h - (screen.top or 0) } end

local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
    return o
end

local function place(doc, ids, screen, layout)
    local items, want = {}, {}
    for _, id in ipairs(ids) do want[id] = true end
    for _, w in ipairs(doc.widgets) do
        if want[w.id] then items[#items + 1] = { id = w.id, w = w.w, h = w.h } end
    end
    local at = below.arrange(items, room(screen), layout)
    for _, w in ipairs(doc.widgets) do
        local p = at[w.id]
        if p then
            local r = W.clamp_rect({ kind = w.kind, layout = w.layout, mode = w.mode, x = p.x, y = p.y, w = w.w, h = w.h }, screen)
            w.x, w.y = r.x, r.y
        end
    end
    return doc
end

-- (doc, how many were added, problems). Once: a doc already seeded comes back as it was.
function M.seed(doc, screen, layout)
    if doc.below_seeded then return doc, 0, {} end
    local d, added, problems = copy(doc), {}, {}
    for _, e in ipairs(M.DEFAULT_SET) do
        local kind, lay = e[1], e[2]
        if W.count_kind(d, kind) == 0 then
            local id
            d, id = W.add(d, kind, screen)
            if id then
                if lay then d = W.set_layout(d, id, lay, screen) end
                local _, w = W.find(d, id)
                w.above = false
                added[#added + 1] = id
            else
                problems[#problems + 1] = "no room for " .. kind .. " (" .. W.MAX .. " widgets at most)"
            end
        end
    end
    d = place(d, added, screen, layout)
    d.below_seeded = true
    return d, #added, problems
end

-- every widget under the wallpaper laid out again; those kept above stay where they are
function M.arrange_all(doc, screen, layout)
    local d, ids = copy(doc), {}
    for _, w in ipairs(d.widgets) do if w.above ~= true then ids[#ids + 1] = w.id end end
    return place(d, ids, screen, layout)
end

-- (doc, problems). Each Presence becomes a widget kept above, centred where it was; one widget per kind.
-- A Presence's fx, fy are fractions of the whole screen; the widgets' surface starts `bar_h` below its top
-- (screen.top when not given).
function M.migrate(presences, doc, screen, bar_h)
    if doc.migrated_presences then return doc, {} end
    local d, problems, made = copy(doc), {}, {}
    for _, p in ipairs(type(presences) == "table" and presences or {}) do
        local kind = type(p) == "table" and M.MIGRATE[p.source]
        if not kind then
            problems[#problems + 1] = "a Presence of " .. tostring(type(p) == "table" and p.source) .. " has no widget; dropped"
        elseif not made[kind] then
            local id
            d, id = W.add(d, kind, screen)
            if id then
                made[kind] = true
                local _, w = W.find(d, id)
                w.above = true
                local cx = (tonumber(p.fx) or 0.5) * screen.w
                local bar = bar_h or (screen.top or 0)
                local full = bar_h and (screen.h + bar_h) or screen.h
                local cy = (tonumber(p.fy) or 0.5) * full - bar
                local r = W.clamp_rect({ kind = w.kind, layout = w.layout, mode = w.mode, x = cx - w.w / 2, y = cy - w.h / 2, w = w.w, h = w.h }, screen)
                w.x, w.y = r.x, r.y
            else
                problems[#problems + 1] = "no room for a " .. kind .. " from a Presence"
            end
        end
    end
    d.migrated_presences = true
    return d, problems
end

-- The Launch grid: the most launched first (counts by app id), those whose name starts with what is typed
-- before those that only have it, then the service's order; at most n.
function M.grid_apps(list, counts, q, n)
    q = type(q) == "string" and string.lower(q) or ""
    local rows = {}
    for i, a in ipairs(type(list) == "table" and list or {}) do
        if type(a) == "table" and type(a.exec) == "string" and a.exec ~= "" then
            local name = string.lower(tostring(a.name or a.id or ""))
            local at = q == "" and 1 or string.find(name, q, 1, true)
            if at then rows[#rows + 1] = { a = a, i = i, c = tonumber(counts and counts[a.id]) or 0, lead = at == 1 } end
        end
    end
    table.sort(rows, function(p, r)
        if p.lead ~= r.lead then return p.lead end
        if p.c ~= r.c then return p.c > r.c end
        return p.i < r.i
    end)
    local out = {}
    for i = 1, math.min(n, #rows) do out[i] = rows[i].a end
    return out
end

-- The Wallpapers widget: the n newest pictures in the picker's index (walls-index.json) that have a thumbnail.
function M.walls(index, n)
    local rows = {}
    local items = type(index) == "table" and type(index.items) == "table" and index.items or {}
    for i, it in ipairs(items) do
        if type(it) == "table" and type(it.path) == "string" and type(it.thumb) == "string" and it.thumb ~= "" then
            rows[#rows + 1] = { path = it.path, thumb = it.thumb, t = tonumber(it.mtime) or 0, i = i }
        end
    end
    table.sort(rows, function(p, r) if p.t ~= r.t then return p.t > r.t end return p.i < r.i end)
    local out = {}
    for i = 1, math.min(n, #rows) do out[i] = { path = rows[i].path, thumb = rows[i].thumb } end
    return out
end

return M
