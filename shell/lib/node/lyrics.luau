-- The node's lyrics (D230): LRC time-synced words, read into timed lines and asked for at a moment. Pure: text
-- in, lines out; it fetches nothing, and the query it builds is only a string for someone else to ask.

local M = {}

-- a stamp's minutes, seconds and fraction of a second, in milliseconds
local function stamp_ms(m, s, frac)
    local ms = tonumber(m) * 60000 + tonumber(s) * 1000
    if frac and frac ~= "" then
        if #frac == 1 then ms = ms + tonumber(frac) * 100
        elseif #frac == 2 then ms = ms + tonumber(frac) * 10
        else ms = ms + tonumber(frac:sub(1, 3)) end
    end
    return ms
end

-- the timed lines of an LRC file, in time order; a line may carry several stamps, and an offset moves them all
function M.parse(text)
    local out = {}
    if type(text) ~= "string" then return out end

    local offset = 0
    local o = text:lower():match("%[offset:%s*([+-]?%d+)%s*%]")
    if o then offset = tonumber(o) or 0 end

    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        local stamps, rest = {}, line
        while true do
            local m, s, frac, tail = rest:match("^%s*%[(%d+):(%d+)%.?(%d*)%](.*)$")
            if not m then break end
            stamps[#stamps + 1] = stamp_ms(m, s, frac)
            rest = tail
        end
        -- no stamp: a tag ([ar:…], [ti:…]) or plain text, and not a lyric
        if #stamps > 0 then
            local words = rest:match("^%s*(.-)%s*$") or ""
            for _, t in ipairs(stamps) do
                out[#out + 1] = { t = t - offset, line = words }
            end
        end
    end

    -- in time order, and lines stamped alike keep the file's order
    for i, e in ipairs(out) do e.n = i end
    table.sort(out, function(a, b)
        if a.t == b.t then return a.n < b.n end
        return a.t < b.t
    end)
    for _, e in ipairs(out) do e.n = nil end
    return out
end

-- which line is current at a moment: the last one at or before it, 0 before the first
function M.at(lines, ms)
    if type(lines) ~= "table" then return 0 end
    local at = tonumber(ms) or 0
    local found = 0
    for i, e in ipairs(lines) do
        local t = type(e) == "table" and tonumber(e.t)
        if t and t <= at then found = i end
    end
    return found
end

-- the lines around the current one, as words, blank where there is none
function M.window(lines, ms, n)
    local w = { prev = "", cur = "", next = "" }
    if type(lines) ~= "table" then return w end
    local function words(i)
        local e = lines[i]
        if type(e) ~= "table" or e.line == nil then return "" end
        return tostring(e.line)
    end
    local i = M.at(lines, ms)
    if i > 0 then w.cur = words(i) end
    if i > 1 then w.prev = words(i - 1) end
    if lines[i + 1] then w.next = words(i + 1) end
    return w
end

-- everything outside the unreserved set is escaped, so a space is %20 and a name may hold anything
local function escape(s)
    return (tostring(s or ""):gsub("[^A-Za-z0-9%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- the query a lyrics service is asked with; built here, asked elsewhere
function M.query(artist, title, length_s)
    local d = math.floor(tonumber(length_s) or 0)
    if d < 0 then d = 0 end
    return "artist_name=" .. escape(artist) .. "&track_name=" .. escape(title) .. "&duration=" .. tostring(d)
end

return M
