-- Ranking for the command membrane. Pure: tests/unit runs it under Lua 5.4.
--
-- An item is { title = "Firefox", alt = { "firefox", "Web Browser" }, kind = "app",
-- key = "app:firefox.desktop", base = 0 }. Its score is the best match of the query
-- against its title (full weight) or any alt (80 %), plus how often it was chosen.

local M = {}

local function lower(s) return string.lower(tostring(s or "")) end

local function boundary(s, i) -- i starts a word in s
    if i == 1 then return true end
    local prev = string.sub(s, i - 1, i - 1)
    return string.find(prev, "[%s%-_%./:@]") ~= nil
end

-- How well `q` matches `s` (both any case); nil when it does not.
function M.score(q, s)
    q, s = lower(q), lower(s)
    if q == "" then return 0 end
    if s == "" then return nil end
    if s == q then return 1000 end
    local at = string.find(s, q, 1, true)
    if at == 1 then return 800 - math.min(#s - #q, 100) end
    -- a word inside the text starting with the query ("code" in "visual studio code")
    local from = 1
    while at do
        if boundary(s, at) then return 600 - math.min(at, 100) end
        from = at + 1
        at = string.find(s, q, from, true)
    end
    if string.find(s, q, 1, true) then return 400 - math.min(string.find(s, q, 1, true), 100) end
    -- letters in order ("ff" in "firefox"): rewards runs and word starts, punishes gaps
    local score, si, run, first = 100, 1, 0, nil
    for qi = 1, #q do
        local c = string.sub(q, qi, qi)
        local found = string.find(s, c, si, true)
        if not found then return nil end
        first = first or found
        if found == si and qi > 1 then run = run + 1; score = score + 8 * run else run = 0 end
        if boundary(s, found) then score = score + 12 end
        score = score - math.min(found - si, 10)
        si = found + 1
    end
    return score - math.min(first, 20)
end

-- The best of title and alts.
function M.match(q, item)
    local best = M.score(q, item.title)
    for _, a in ipairs(item.alt or {}) do
        local s = M.score(q, a)
        if s then
            s = s * 0.8
            if not best or s > best then best = s end
        end
    end
    return best
end

M.USAGE_WEIGHT = 15
M.USAGE_CAP = 20

-- Items that match, best first, at most `limit`. `usage[key]` counts past choices.
function M.rank(items, q, usage, limit)
    usage = usage or {}
    local out = {}
    for _, item in ipairs(items) do
        local s = M.match(q, item)
        if s then
            local used = math.min(tonumber(usage[item.key or ""]) or 0, M.USAGE_CAP)
            out[#out + 1] = { item = item, score = s + (item.base or 0) + used * M.USAGE_WEIGHT }
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return lower(a.item.title) < lower(b.item.title)
    end)
    local ranked = {}
    for i = 1, math.min(#out, limit or #out) do ranked[i] = out[i].item end
    return ranked
end

-- What the query asks for: a prefix narrows the kinds.
--   "@fire" → windows only · ">sys" → mooi actions only · "3" → workspace 3 first
function M.parse(query)
    local q = tostring(query or "")
    q = string.gsub(q, "^%s+", "")
    q = string.gsub(q, "%s+$", "")
    local first = string.sub(q, 1, 1)
    if first == "@" then return { kinds = { window = true }, text = string.sub(q, 2) } end
    if first == ">" then return { kinds = { action = true }, text = string.sub(q, 2) } end
    local n = tonumber(string.match(q, "^(%d+)$"))
    if n then return { workspace = n, text = q } end
    return { text = q }
end

-- Usage counts stay small: the oldest half is forgotten past `cap` entries.
function M.remember(usage, key, cap)
    usage[key] = (tonumber(usage[key]) or 0) + 1
    local keys = {}
    for k in pairs(usage) do if k ~= key then keys[#keys + 1] = k end end   -- never the one just chosen
    if #keys + 1 > (cap or 200) then
        table.sort(keys, function(a, b) return usage[a] < usage[b] end)
        for i = 1, math.floor(#keys / 2) do usage[keys[i]] = nil end
    end
    return usage
end

return M
