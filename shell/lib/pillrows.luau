-- The Pill's three rows (D199), after ArchEclipse's pill bar (its `barLayoutPill`: rest · core · detail):
-- what the capsule shows at rest (the glance face), and the reveal's two rows under it. Each row is a list
-- of items from one catalogue; the owner arranges them by dragging, on the Pill's own editor (ROWS).
-- Pure: the lists' cleaning, each item's width for what it says now, a row laid out, and a move.

local M = {}

-- Every item, with the index the scene draws it by (`k`), the board's room a press on it opens, and its
-- width as the scene draws it (`w(d)`: d is what the bar knows now — spaces, title, artist, battery…).
M.ITEMS = {
    { id = "spaces",     k = 0,  room = 12, w = function(d) local n = math.max(1, math.min(10, d.spaces or 5)); return n * 10 + 2 end },
    { id = "clock",      k = 1,  room = 1,  w = function() return 46 end },
    { id = "chip",       k = 2,  room = 0,  w = function(d)
        if (d.title or "") ~= "" then
            local w = 22 + 21 + math.min(150, 7 * #d.title)
            if (d.artist or "") ~= "" then w = w + 7 + math.min(120, 6 * #d.artist) end
            return w
        end
        return 22 + 21 + 7 * #(tostring(math.floor(tonumber(d.percent) or 0)) .. "%")
    end },
    { id = "media",      k = 3,  room = 0,  w = function(d) return (d.title or "") ~= "" and (30 + math.min(170, 7 * #d.title)) or 0 end },
    { id = "bandwidth",  k = 4,  room = 4,  w = function() return 150 end },
    { id = "controls",   k = 5,  room = 2,  w = function() return 84 end },
    { id = "weather",    k = 6,  room = 7,  w = function() return 70 end },
    { id = "resources",  k = 7,  room = 6,  w = function() return 100 end },
    { id = "battery",    k = 8,  room = 5,  w = function(d) return d.battery and 70 or 0 end },
    { id = "brightness", k = 9,  room = 3,  w = function(d) return d.brightness and 70 or 0 end },
    { id = "volume",     k = 10, room = 2,  w = function() return 70 end },
    { id = "network",    k = 11, room = 4,  w = function() return 110 end },
    { id = "date",       k = 12, room = 1,  w = function() return 96 end },
}
local BY = {}
for _, it in ipairs(M.ITEMS) do BY[it.id] = it end
M.BY = BY
M.ROWS = { "rest", "core", "detail" }
-- ArchEclipse's defaults (rest: workspaces · clock · chip; core: media · bandwidth · control · clock;
-- detail: weather · resources · battery · brightness · volume · network); its tray has no item here
M.DEFAULT = {
    rest = { "spaces", "clock", "chip" },
    core = { "media", "bandwidth", "controls", "clock" },
    detail = { "weather", "resources", "battery", "brightness", "volume", "network" },
}
M.MAX = 6
M.GAP, M.EDGE = 14, 14

-- A row's list made safe: known items, no repeats within the row, at most eight; nil → the default.
function M.clean(list, row)
    if type(list) ~= "table" then list = M.DEFAULT[row] or {} end
    local out, seen = {}, {}
    for _, id in ipairs(list) do
        if #out >= M.MAX then break end
        if type(id) == "string" and BY[id] and not seen[id] then out[#out + 1] = id; seen[id] = true end
    end
    return out
end

-- The three rows from the Pill's settings.
function M.rows(p)
    p = type(p) == "table" and p or {}
    return { rest = M.clean(p.row_rest, "rest"), core = M.clean(p.row_core, "core"), detail = M.clean(p.row_detail, "detail") }
end

-- A row laid out for what it says now: { { id, k, room, x, w }… } from 0, 14 apart (items with nothing to
-- say — no song, no battery — leave), and its whole width with an edge each side.
function M.layout(list, d)
    d = d or {}
    local out, x = {}, M.EDGE
    for _, id in ipairs(list or {}) do
        local it = BY[id]
        local w = it and it.w(d) or 0
        if w > 0 then
            out[#out + 1] = { id = id, k = it.k, room = it.room, x = x, w = w }
            x = x + w + M.GAP
        end
    end
    local width = (#out > 0) and (x - M.GAP + M.EDGE) or (2 * M.EDGE)
    return out, width
end

-- The items in no row: the editor's shelf.
function M.shelf(rows)
    local used = {}
    for _, r in ipairs(M.ROWS) do for _, id in ipairs(rows[r] or {}) do used[id] = true end end
    local out = {}
    for _, it in ipairs(M.ITEMS) do if not used[it.id] then out[#out + 1] = it.id end end
    return out
end

-- Move an item: taken from row `from` (a row's name, or "shelf"), at its place `i` (1-based), and put in
-- row `to` (or "shelf": hidden) before place `at` (1-based; past the end: last). Returns new rows.
function M.move(rows, from, i, to, at)
    local r = { rest = { table.unpack(rows.rest or {}) }, core = { table.unpack(rows.core or {}) },
                detail = { table.unpack(rows.detail or {}) } }
    local id
    if from == "shelf" then id = M.shelf(rows)[i]
    elseif r[from] then
        id = r[from][i]
        if id then table.remove(r[from], i) end
    end
    if not id then return rows end
    if to ~= "shelf" and r[to] then
        -- already in that row (from the shelf, it was not): the move is a reorder
        -- already in the target row (moved from another row or the shelf): one copy only
        for k = #r[to], 1, -1 do
            if r[to][k] == id then
                table.remove(r[to], k)
                if at and k < at then at = at - 1 end
            end
        end
        -- a reorder within one row: it was taken out first, so a place after it moves up by one
        if from == to and at and i < at then at = at - 1 end
        if #r[to] >= M.MAX then return rows end
        at = math.max(1, math.min(#r[to] + 1, math.floor(tonumber(at) or (#r[to] + 1))))
        table.insert(r[to], at, id)
    end
    return r
end

-- Where in a row a drop at x (row-local) lands: before the first item whose centre is right of x.
function M.drop_at(layout, x)
    for n, it in ipairs(layout) do
        if x < it.x + it.w / 2 then return n end
    end
    return #layout + 1
end

return M
