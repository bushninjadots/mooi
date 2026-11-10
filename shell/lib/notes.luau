-- Quick notes (D51): the little pad behind the bar's notes module. Pure, so tests/unit runs it
-- under plain Lua 5.4 (written in the subset Lua 5.4 and Luau share); shell/notes.luau owns the
-- file and hands the scene its rows.
--
-- A note is { id, text, time, pinned }: `text` is what was written (kept as lines, cleaned), `time`
-- the second it was saved, `id` a number that never repeats within a file, `pinned` whether it
-- stays at the top. Pinned notes first, then the newest.
-- Nothing here is a document: a note is a line or two you wanted out of your head quickly, so
-- there is one list, a cap, and no folders.

local M = {}

-- The order every list is kept in: pinned first, then what is still to do (a ticked note sinks
-- below the open ones, D86), then newest, then the higher id.
local function before(a, b)
    if (a.pinned == true) ~= (b.pinned == true) then return a.pinned == true end
    if (a.done == true) ~= (b.done == true) then return b.done == true end
    if a.time ~= b.time then return a.time > b.time end
    return a.id > b.id
end
M.before = before

M.MAX = 200              -- how many notes are kept; the oldest fall off
M.TEXT_MAX = 4000        -- characters kept of one note
M.ROW_MAX = 6            -- rows the dropdown shows; the rest wait in notes.json
M.PREVIEW = 96           -- one-line preview's length
M.TAGS = 5               -- a note's colour: 0 none, 1 phos, 2 flare, 3 ember, 4 trace (D86)

-- Cut at `n`, never in the middle of a character: back off to the start of one, then mark it.
local function cut(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 and string.byte(s, i + 1) and string.byte(s, i + 1) >= 0x80 and string.byte(s, i + 1) < 0xC0 do i = i - 1 end
    return string.sub(s, 1, i) .. "…"
end

-- What is kept of a written note: newlines as \n, other control characters spaces, runs of
-- spaces one, a line's edges trimmed, the whole trimmed, and cut to TEXT_MAX.
function M.clean(s)
    if type(s) ~= "string" then return "" end
    s = string.gsub(s, "\r\n", "\n")
    s = string.gsub(s, "\r", "\n")
    s = string.gsub(s, "%c", function(c) return c == "\n" and "\n" or " " end)
    s = string.gsub(s, "[ \t]+", " ")
    s = string.gsub(s, " *\n *", "\n")
    s = string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")
    s = string.gsub(s, "\n\n\n+", "\n\n")
    return cut(s, M.TEXT_MAX)
end

-- A note as one line, for a row: every run of whitespace a space, cut.
function M.one_line(s, n)
    if type(s) ~= "string" then return "" end
    s = string.gsub(s, "%s+", " ")
    s = string.gsub(string.gsub(s, "^ ", ""), " $", "")
    return cut(s, n or M.PREVIEW)
end

-- Add a note (newest first). An empty one is not a note: the list comes back with `nil`.
function M.add(list, text, now)
    list = list or {}
    local t = M.clean(text)
    if t == "" then return list, nil end
    local id = 0
    for _, n in ipairs(list) do if n.id > id then id = n.id end end
    local note = { id = id + 1, text = t, time = math.floor(tonumber(now) or 0), pinned = false }
    table.insert(list, 1, note)
    table.sort(list, before)
    -- the cap takes the oldest that is not pinned
    while #list > M.MAX do
        local drop = #list
        while drop > 1 and list[drop].pinned do drop = drop - 1 end
        table.remove(list, drop)
    end
    return list, note
end

-- Change what a note says. The note keeps its id and its place; `time` moves to now, so a row
-- says when it was last touched. An empty text is refused (a note is never blank).
function M.update(list, id, text, now)
    local t = M.clean(text)
    if t == "" then return list, nil end
    for _, n in ipairs(list or {}) do
        if n.id == id then
            n.text = t
            n.time = math.floor(tonumber(now) or 0)
            return list, n
        end
    end
    return list, nil
end

-- Put a note back (the one just forgotten), where its time says it belongs. Its id is kept
-- unless something else has taken it meanwhile.
function M.restore(list, note, now)
    if type(note) ~= "table" then return list, nil end
    local t = M.clean(note.text)
    if t == "" then return list, nil end
    list = list or {}
    local id = tonumber(note.id)
    if not id or id < 1 or id ~= math.floor(id) or M.find(list, id) then
        local max = 0
        for _, n in ipairs(list) do if n.id > max then max = n.id end end
        id = max + 1
    end
    local back = { id = id, text = t, time = math.floor(tonumber(note.time) or tonumber(now) or 0), pinned = note.pinned == true }
    table.insert(list, back)
    table.sort(list, before)
    while #list > M.MAX do table.remove(list) end
    return list, back
end

-- Pin a note to the top, or let it go back among the rest; says whether it is pinned now.
function M.pin(list, id)
    for _, n in ipairs(list or {}) do
        if n.id == id then
            n.pinned = not n.pinned
            table.sort(list, before)
            return list, n.pinned
        end
    end
    return list, nil
end

-- A note's colour, the next one round (none → phos → flare → ember → trace → none); says the new one.
function M.tag(list, id)
    local n = M.find(list or {}, id)
    if not n then return list, nil end
    n.tag = ((tonumber(n.tag) or 0) + 1) % M.TAGS
    return list, n.tag
end

-- Tick a note off, or open it again; a ticked note sinks below the open ones. Says whether it is done.
function M.done(list, id)
    local n = M.find(list or {}, id)
    if not n then return list, nil end
    n.done = not n.done
    table.sort(list, before)
    return list, n.done
end

-- The notes whose text has `query` in it (any case); every note when it is empty.
function M.filter(list, query)
    local q = string.lower(tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if q == "" then return list or {} end
    local out = {}
    for _, n in ipairs(list or {}) do
        if string.find(string.lower(n.text or ""), q, 1, true) then out[#out + 1] = n end
    end
    return out
end

-- A note as a board card: its first line the title, the rest its note.
function M.split(text)
    local t = M.clean(text)
    local first, rest = string.match(t, "^([^\n]*)\n?(.*)$")
    return first or "", rest or ""
end

function M.find(list, id)
    for _, n in ipairs(list) do if n.id == id then return n end end
    return nil
end

-- Remove one note; says whether it was there.
function M.remove(list, id)
    for i, n in ipairs(list or {}) do
        if n.id == id then table.remove(list, i); return list, true end
    end
    return list, false
end

-- One page of the board: `size` notes from `at`, clamped to what is there. Says the page
-- actually shown (a wheel past either end stays on the last) and how many pages there are,
-- so the panel can page without counting the list itself.
function M.slice(list, at, size)
    list = list or {}
    size = math.floor(tonumber(size) or 6)
    if size < 1 then size = 1 end
    local pages = math.max(1, math.ceil(#list / size))
    local page = math.floor(tonumber(at) or 0)
    if page < 0 then page = 0 end
    if page > pages - 1 then page = pages - 1 end
    local out = {}
    local first = page * size + 1
    for i = first, math.min(#list, first + size - 1) do out[#out + 1] = list[i] end
    return out, page, pages
end

-- What came in on the panel's inbox (D279): a string is a note to add, a table is an op on
-- one already kept (`remove` or `pin`). Plain strings keep working, so an older bar and a new
-- panel never disagree. Says whether anything changed.
function M.receive(list, box, now)
    list = list or {}
    local changed = false
    for _, e in ipairs(type(box) == "table" and box or {}) do
        if type(e) == "string" then
            local c = M.clean(e)
            if c ~= "" then list = M.add(list, c, now); changed = true end
        elseif type(e) == "table" then
            local id = math.floor(tonumber(e.id) or 0)
            local op = tostring(e.op or "")
            if id >= 1 then
                if op == "remove" then list = M.remove(list, id); changed = true
                elseif op == "pin" then list = M.pin(list, id); changed = true end
            end
        end
    end
    return list, changed
end

-- The file read back: whatever is not a note is dropped, ids are made unique (a repeated or
-- missing one gets a new number, so no note is lost), pinned first then the newest, and the list
-- is capped. A file written by an older mooi, or by hand, never raises.
function M.decode(t)
    local out = {}
    local seen = {}
    local loose = {}
    if type(t) ~= "table" then return out end
    local rows = type(t.notes) == "table" and t.notes or t
    if type(rows) ~= "table" then return out end
    for _, n in ipairs(rows) do
        if type(n) == "table" then
            local id = tonumber(n.id)
            local text = M.clean(n.text)
            local tag = math.floor(tonumber(n.tag) or 0)
            if tag < 0 or tag >= M.TAGS then tag = 0 end
            local note = { id = id, text = text, time = math.floor(tonumber(n.time) or 0), pinned = n.pinned == true,
                           tag = tag, done = n.done == true }
            if text ~= "" then
                if id and id >= 1 and id == math.floor(id) and not seen[id] then
                    seen[id] = true
                    out[#out + 1] = note
                else
                    loose[#loose + 1] = note
                end
            end
        end
    end
    local max = 0
    for id in pairs(seen) do if id > max then max = id end end
    for _, note in ipairs(loose) do
        max = max + 1
        note.id = max
        out[#out + 1] = note
    end
    table.sort(out, before)
    while #out > M.MAX do table.remove(out) end
    return out
end

-- What is written to the file.
function M.encode(list)
    local rows = {}
    for _, n in ipairs(list or {}) do
        rows[#rows + 1] = { id = n.id, text = n.text, time = n.time, pinned = n.pinned == true or nil,
                            tag = (n.tag and n.tag > 0) and n.tag or nil, done = n.done == true or nil }
    end
    return { version = 1, notes = rows }
end

-- How long ago, for a row: seconds from `now`, small and quiet.
function M.ago(now, t)
    local d = math.floor((tonumber(now) or 0) - (tonumber(t) or 0))
    if d < 60 then return "now" end
    if d < 3600 then return math.floor(d / 60) .. "m" end
    if d < 86400 then return math.floor(d / 3600) .. "h" end
    if d < 2419200 then return math.floor(d / 86400) .. "d" end
    return math.floor(d / 604800) .. "w"
end

return M
