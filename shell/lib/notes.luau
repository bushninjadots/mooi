-- Quick notes (D51): the little pad behind the bar's notes module. Pure, so tests/unit runs it
-- under plain Lua 5.4 (written in the subset Lua 5.4 and Luau share); shell/notes.luau owns the
-- file and hands the scene its rows.
--
-- A note is { id, text, time }: `text` is what was written (kept as lines, cleaned), `time` the
-- second it was saved, `id` a number that never repeats within a file. The newest is first.
-- Nothing here is a document: a note is a line or two you wanted out of your head quickly, so
-- there is one list, a cap, and no folders.

local M = {}

M.MAX = 200              -- how many notes are kept; the oldest fall off
M.TEXT_MAX = 4000        -- characters kept of one note
M.ROW_MAX = 6            -- rows the dropdown shows; the rest wait in notes.json
M.PREVIEW = 96           -- one-line preview's length

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
    local note = { id = id + 1, text = t, time = math.floor(tonumber(now) or 0) }
    table.insert(list, 1, note)
    while #list > M.MAX do table.remove(list) end
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
    local back = { id = id, text = t, time = math.floor(tonumber(note.time) or tonumber(now) or 0) }
    table.insert(list, back)
    table.sort(list, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        return a.id > b.id
    end)
    while #list > M.MAX do table.remove(list) end
    return list, back
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

-- The file read back: whatever is not a note is dropped, ids are made unique, the newest is
-- first, and the list is capped. A file written by an older mooi, or by hand, never raises.
function M.decode(t)
    local out = {}
    local seen = {}
    if type(t) ~= "table" then return out end
    local rows = type(t.notes) == "table" and t.notes or t
    if type(rows) ~= "table" then return out end
    for _, n in ipairs(rows) do
        if type(n) == "table" then
            local id = tonumber(n.id)
            local text = M.clean(n.text)
            local time = math.floor(tonumber(n.time) or 0)
            if id and id >= 1 and id == math.floor(id) and not seen[id] and text ~= "" then
                seen[id] = true
                out[#out + 1] = { id = id, text = text, time = time }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        return a.id > b.id
    end)
    while #out > M.MAX do table.remove(out) end
    return out
end

-- What is written to the file.
function M.encode(list)
    local rows = {}
    for _, n in ipairs(list or {}) do
        rows[#rows + 1] = { id = n.id, text = n.text, time = n.time }
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
