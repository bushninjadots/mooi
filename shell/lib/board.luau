-- The board (D52): a Kanban board beside the quick notes — columns of cards you move as work moves.
-- Pure, so tests/unit runs it under plain Lua 5.4 (written in the subset Lua 5.4 and Luau share);
-- shell/board.luau owns the file and hands the scene its rows.
--
-- A board is { columns = { { id, title, wip } }, cards = { { id, col, title, note, tag, due,
-- created, updated, done_at } }, archive = { cards }, next_id }. A card's place in its column is its
-- place in `cards` among the cards of that column (so moving one is taking it out and putting it
-- back). `tag` is 0 (none) or 1 … 5, a colour of the palette; `due` a day (days since 1970, local)
-- or nil; the last column is where work is done: a card that reaches it is stamped `done_at`.

local M = {}

M.VERSION = 1
M.MAX_COLUMNS, M.MAX_CARDS, M.MAX_ARCHIVE = 6, 300, 500
M.TITLE_MAX, M.NOTE_MAX, M.COLUMN_MAX = 140, 1000, 24
M.TAGS = 5

local function cut(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 and string.byte(s, i + 1) and string.byte(s, i + 1) >= 0x80 and string.byte(s, i + 1) < 0xC0 do i = i - 1 end
    return string.sub(s, 1, i) .. "…"
end

-- One line of text as kept: control characters spaces, runs of space one, trimmed, cut.
function M.line(s, n)
    if type(s) ~= "string" then return "" end
    s = string.gsub(s, "%c", " ")
    s = string.gsub(s, "%s+", " ")
    s = string.gsub(string.gsub(s, "^ ", ""), " $", "")
    return cut(s, n)
end

local function int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return v
end

-- A board to start with: what is waiting, what is being done (three at a time), what is done.
function M.new()
    return { version = M.VERSION, next_id = 4,
             columns = { { id = 1, title = "Inbox", wip = 0 }, { id = 2, title = "Doing", wip = 3 }, { id = 3, title = "Done", wip = 0 } },
             cards = {}, archive = {} }
end

local function take_id(b)
    local id = b.next_id
    b.next_id = id + 1
    return id
end

local function clean_card(c, cols)
    if type(c) ~= "table" then return nil end
    local title = M.line(c.title, M.TITLE_MAX)
    if title == "" then return nil end
    local col = tonumber(c.col)
    if cols and not cols[col] then return nil end
    return { id = int(c.id, 1, 2 ^ 31), col = col, title = title, note = M.line(c.note, M.NOTE_MAX),
             tag = int(c.tag, 0, M.TAGS) or 0, due = int(c.due, 0, 200000),
             created = math.floor(tonumber(c.created) or 0), updated = math.floor(tonumber(c.updated) or 0),
             done_at = int(c.done_at, 0, 2 ^ 40) }
end

-- The file read back. Whatever is not a column or a card is dropped; a card whose column is gone is
-- dropped too; ids are made unique (a repeated one gets a new number); no column, a new board.
-- Never raises.
function M.decode(t)
    if type(t) ~= "table" or type(t.columns) ~= "table" then return M.new() end
    local b = { version = M.VERSION, columns = {}, cards = {}, archive = {}, next_id = 1 }
    local seen, cols, max = {}, {}, 0
    local loose = {}
    local function place(x)
        if x.id and not seen[x.id] then seen[x.id] = true; if x.id > max then max = x.id end; return true end
        loose[#loose + 1] = x
        return false
    end
    for _, c in ipairs(t.columns) do
        if type(c) == "table" and #b.columns < M.MAX_COLUMNS then
            local title = M.line(c.title, M.COLUMN_MAX)
            if title ~= "" then
                local col = { id = int(c.id, 1, 2 ^ 31), title = title, wip = int(c.wip, 0, 99) or 0 }
                place(col)
                b.columns[#b.columns + 1] = col
            end
        end
    end
    -- columns renumbered now, so the cards can find theirs
    for _, x in ipairs(loose) do max = max + 1; x.id = max; seen[x.id] = true end
    loose = {}
    if #b.columns == 0 then return M.new() end
    for _, c in ipairs(b.columns) do cols[c.id] = true end
    for _, c in ipairs(type(t.cards) == "table" and t.cards or {}) do
        local card = #b.cards < M.MAX_CARDS and clean_card(c, cols)
        if card then place(card); b.cards[#b.cards + 1] = card end
    end
    for _, c in ipairs(type(t.archive) == "table" and t.archive or {}) do
        local card = #b.archive < M.MAX_ARCHIVE and clean_card(c, nil)
        if card then place(card); b.archive[#b.archive + 1] = card end
    end
    for _, x in ipairs(loose) do max = max + 1; x.id = max end
    b.next_id = math.max(max + 1, int(t.next_id, 1, 2 ^ 31) or 1)
    return b
end

function M.encode(b)
    return { version = M.VERSION, next_id = b.next_id, columns = b.columns, cards = b.cards, archive = b.archive }
end

function M.column(b, id)
    for i, c in ipairs(b.columns) do if c.id == id then return c, i end end
    return nil
end
function M.card(b, id)
    for i, c in ipairs(b.cards) do if c.id == id then return c, i end end
    return nil
end
-- A column's cards, in order.
function M.cards_in(b, col)
    local out = {}
    for _, c in ipairs(b.cards) do if c.col == col then out[#out + 1] = c end end
    return out
end
local function last_col(b) return b.columns[#b.columns].id end

-- Put `card` (not in `cards`) at place `index` (1 … n + 1) of column `col`.
local function insert(b, card, col, index)
    card.col = col
    local seen, at = 0, #b.cards + 1
    for i, c in ipairs(b.cards) do
        if c.col == col then
            seen = seen + 1
            if seen == index then at = i; break end
        end
    end
    if seen < index then
        -- after the column's last card
        at = #b.cards + 1
        for i = #b.cards, 1, -1 do if b.cards[i].col == col then at = i + 1; break end end
    end
    table.insert(b.cards, at, card)
end

-- A new card at the top of a column. An empty title is not a card.
function M.add(b, col, title, note, now)
    if #b.cards >= M.MAX_CARDS then return nil, "the board is full (" .. M.MAX_CARDS .. " cards): archive what is done" end
    if not M.column(b, col) then return nil, "no such column" end
    local t = M.line(title, M.TITLE_MAX)
    if t == "" then return nil, "a card needs a title" end
    now = math.floor(tonumber(now) or 0)
    local card = { id = take_id(b), col = col, title = t, note = M.line(note, M.NOTE_MAX), tag = 0,
                   created = now, updated = now }
    if col == last_col(b) then card.done_at = now end
    insert(b, card, col, 1)
    return card
end

-- Change a card: any of `title` (never empty), `note`, `tag` (0 … 5), `due` (a day, or false for
-- none). Says whether anything changed.
function M.update(b, id, f, now)
    local c = M.card(b, id)
    if not c then return false end
    local changed = false
    if f.title ~= nil then
        local t = M.line(f.title, M.TITLE_MAX)
        if t ~= "" and t ~= c.title then c.title = t; changed = true end
    end
    if f.note ~= nil then
        local n = M.line(f.note, M.NOTE_MAX)
        if n ~= c.note then c.note = n; changed = true end
    end
    if f.tag ~= nil then
        local g = int(f.tag, 0, M.TAGS)
        if g and g ~= c.tag then c.tag = g; changed = true end
    end
    if f.due ~= nil then
        local d = f.due ~= false and int(f.due, 0, 200000) or nil
        if d ~= c.due then c.due = d; changed = true end
    end
    if changed then c.updated = math.floor(tonumber(now) or 0) end
    return changed
end

-- Move a card to place `index` of column `col` (clamped). Reaching the last column stamps it done;
-- leaving it takes the stamp off. Says whether it moved.
function M.move(b, id, col, index, now)
    local c, i = M.card(b, id)
    if not c or not M.column(b, col) then return false end
    local from_col = c.col
    local from_index = 0
    for _, x in ipairs(b.cards) do
        if x.col == from_col then from_index = from_index + 1 end
        if x == c then break end
    end
    table.remove(b.cards, i)
    local n = #M.cards_in(b, col)
    index = math.max(1, math.min(math.floor(tonumber(index) or 1), n + 1))
    insert(b, c, col, index)
    if col == last_col(b) and from_col ~= col then c.done_at = math.floor(tonumber(now) or 0)
    elseif col ~= last_col(b) then c.done_at = nil end
    if from_col ~= col or from_index ~= index then c.updated = math.floor(tonumber(now) or 0); return true end
    return false
end

-- Where a card is: its column's place among the columns, and its own place in that column.
function M.place_of(b, id)
    local c = M.card(b, id)
    if not c then return nil end
    local _, ci = M.column(b, c.col)
    local k = 0
    for _, x in ipairs(b.cards) do
        if x.col == c.col then k = k + 1 end
        if x == c then break end
    end
    return ci, k
end

-- A step: one column left or right (to the same place, as near as it goes), or one place up or down.
function M.step(b, id, dx, dy, now)
    local ci, k = M.place_of(b, id)
    if not ci then return false end
    if dx ~= 0 then
        local to = b.columns[ci + dx]
        if not to then return false end
        return M.move(b, id, to.id, k, now)
    end
    local c = M.card(b, id)
    return M.move(b, id, c.col, k + dy, now)
end

-- Take a card off the board; what comes back is what Undo needs to put it back where it was.
function M.remove(b, id)
    local c = M.card(b, id)
    if not c then return nil end
    local _, k = M.place_of(b, id)
    local _, i = M.card(b, id)
    table.remove(b.cards, i)
    return { card = c, col = c.col, index = k }
end
-- Put back what `remove` took (to its column and place, or the first column if that is gone).
function M.restore(b, taken)
    if type(taken) ~= "table" or type(taken.card) ~= "table" then return false end
    if M.card(b, taken.card.id) then return false end
    local col = M.column(b, taken.col) and taken.col or b.columns[1].id
    insert(b, taken.card, col, taken.index or 1)
    return true
end

-- Columns: at most six, never fewer than one; a column is removed only when it is empty.
function M.add_column(b, title)
    if #b.columns >= M.MAX_COLUMNS then return nil, "six columns at most" end
    local t = M.line(title, M.COLUMN_MAX)
    if t == "" then t = "Column " .. (#b.columns + 1) end
    local col = { id = take_id(b), title = t, wip = 0 }
    -- before the last (Done stays last)
    table.insert(b.columns, math.max(#b.columns, 1), col)
    return col
end
function M.rename_column(b, id, title)
    local c = M.column(b, id)
    local t = M.line(title, M.COLUMN_MAX)
    if not c or t == "" then return false end
    c.title = t
    return true
end
function M.set_wip(b, id, n)
    local c = M.column(b, id)
    n = int(n, 0, 99)
    if not c or not n then return false end
    c.wip = n
    return true
end
function M.remove_column(b, id)
    local _, i = M.column(b, id)
    if not i then return false, "no such column" end
    if #b.columns <= 1 then return false, "a board keeps one column" end
    if #M.cards_in(b, id) > 0 then return false, "move or archive its cards first" end
    table.remove(b.columns, i)
    return true
end
function M.move_column(b, id, d)
    local _, i = M.column(b, id)
    local j = i and i + d
    if not i or j < 1 or j > #b.columns then return false end
    b.columns[i], b.columns[j] = b.columns[j], b.columns[i]
    return true
end

-- What is done goes to the archive (kept in the file, newest first, capped). Says how many.
function M.archive_done(b, now)
    local done = last_col(b)
    local keep, n = {}, 0
    for _, c in ipairs(b.cards) do
        if c.col == done then
            c.done_at = c.done_at or math.floor(tonumber(now) or 0)
            table.insert(b.archive, 1, c); n = n + 1
        else keep[#keep + 1] = c end
    end
    b.cards = keep
    while #b.archive > M.MAX_ARCHIVE do table.remove(b.archive) end
    return n
end

-- ── Days ──
-- Today, as days since 1970 where you are (`offset` the zone's seconds east of UTC).
function M.today(t, offset) return math.floor(((tonumber(t) or 0) + (tonumber(offset) or 0)) / 86400) end
-- A due preset: "today", "tomorrow", "week" (a week from today), "none".
function M.preset(name, today)
    if name == "today" then return today end
    if name == "tomorrow" then return today + 1 end
    if name == "week" then return today + 7 end
    return false
end
-- 0 none · 1 later · 2 soon (within two days) · 3 today · 4 late.
function M.due_state(due, today)
    if not due then return 0 end
    local d = due - today
    if d < 0 then return 4 end
    if d == 0 then return 3 end
    if d <= 2 then return 2 end
    return 1
end
function M.due_text(due, today)
    if not due then return "" end
    local d = due - today
    if d < -1 then return string.format("%d d late", -d) end
    if d == -1 then return "yesterday" end
    if d == 0 then return "today" end
    if d == 1 then return "tomorrow" end
    if d < 7 then return string.format("in %d d", d) end
    return string.format("in %d w", math.floor(d / 7 + 0.5))
end

-- Whether a card shows under the filter: `query` (any case, in its title or note) and `tag`
-- (0: any).
function M.shows(c, query, tag)
    if tag and tag > 0 and c.tag ~= tag then return false end
    if query and query ~= "" then
        -- "due:N": the cards due on day N (the desktop calendar's press, D141)
        local day = string.match(query, "^due:(%d+)$")
        if day then return c.due == tonumber(day) end
        local q = string.lower(query)
        return string.find(string.lower(c.title), q, 1, true) ~= nil or string.find(string.lower(c.note), q, 1, true) ~= nil
    end
    return true
end

-- ── Where everything sits ──
M.CARD_H, M.CARD_NOTE_H, M.CARD_GAP, M.HEAD_H = 58, 78, 8, 44
function M.height(c) return (c.note ~= "" and M.CARD_NOTE_H or M.CARD_H) end

-- The columns across `width` from `x0`, and their cards down from `y0 + HEAD_H` (each column
-- scrolled by `scroll[col]` px, clamped to what it holds, the cards clipped to `height`).
-- Returns { cols = { { id, title, wip, x, w, count, over, scroll, len } }, cards = { { id, col,
-- ci, k, x, y, w, h, shown } } } — `shown` false for a card the filter hides (it takes no room).
function M.layout(b, o)
    local n = #b.columns
    local gap = o.gap or 12
    local w = math.floor((o.width - gap * (n - 1)) / n)
    local out = { cols = {}, cards = {} }
    for ci, col in ipairs(b.columns) do
        local x = o.x0 + (ci - 1) * (w + gap)
        local list = M.cards_in(b, col.id)
        local len = 0
        for _, c in ipairs(list) do if M.shows(c, o.query, o.tag) then len = len + M.height(c) + M.CARD_GAP end end
        local view = o.height - M.HEAD_H
        local scroll = math.max(0, math.min((o.scroll and o.scroll[col.id]) or 0, math.max(len - view, 0)))
        out.cols[ci] = { id = col.id, title = col.title, wip = col.wip, x = x, w = w, count = #list,
                         over = col.wip > 0 and #list > col.wip, scroll = scroll, len = len, view = view }
        local y = o.y0 + M.HEAD_H - scroll
        for k, c in ipairs(list) do
            local shown = M.shows(c, o.query, o.tag)
            local h = M.height(c)
            out.cards[#out.cards + 1] = { id = c.id, col = col.id, ci = ci, k = k, x = x, y = y, w = w, h = h, shown = shown }
            if shown then y = y + h + M.CARD_GAP end
        end
    end
    return out
end

-- Where a card let go at (gx, gy) lands: the column under it (the nearest, past the edges) and
-- its place there, counted without the card itself (as `move` wants it): just after the last shown
-- card whose middle is above the pointer.
function M.drop_target(lay, gx, gy, dragged)
    local best, bd = nil, math.huge
    for _, c in ipairs(lay.cols) do
        local d = 0
        if gx < c.x then d = c.x - gx elseif gx > c.x + c.w then d = gx - (c.x + c.w) end
        if d < bd then best, bd = c, d end
    end
    if not best then return nil end
    local index, k = 1, 0
    for _, c in ipairs(lay.cards) do
        if c.col == best.id and c.id ~= dragged then
            k = k + 1
            if c.shown and gy > c.y + c.h / 2 then index = k + 1 end
        end
    end
    return best.id, index
end

-- What the header says: how many cards, how many late, how many due today.
function M.stats(b, today)
    local s = { cards = #b.cards, late = 0, today = 0, archived = #b.archive }
    local done = last_col(b)
    for _, c in ipairs(b.cards) do
        if c.col ~= done then
            local st = M.due_state(c.due, today)
            if st == 4 then s.late = s.late + 1 elseif st == 3 then s.today = s.today + 1 end
        end
    end
    return s
end

return M
