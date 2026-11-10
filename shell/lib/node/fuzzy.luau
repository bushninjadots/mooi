-- The node's fuzzy matcher (D235): how well a typed query fits a name, and the best few names in order. Pure: it
-- compares strings and sorts tables, and never touches the filesystem or runs anything.

local M = {}

-- an exact match wins over a prefix, which wins over everything the subsequence search finds
local EXACT = 100000
local PREFIX = 10000

-- a position that starts a word: the first character, after a separator, or where a lower-case letter turns upper
local function boundary(name, i)
    if i == 1 then return true end
    local prev, cur = name:sub(i - 1, i - 1), name:sub(i, i)
    if prev == " " or prev == "-" or prev == "_" or prev == "." then return true end
    if prev:match("%l") and cur:match("%u") then return true end
    return false
end

-- how well query fits name: 0 when it does not, higher the better
function M.score(query, name)
    if type(query) ~= "string" or type(name) ~= "string" then return 0 end
    if query == "" or name == "" then return 0 end
    if #query > #name then return 0 end

    local q, n = query:lower(), name:lower()
    if q == n then return EXACT end
    if n:sub(1, #q) == q then return PREFIX + #q - #name * 0.1 end

    -- dp[j] is the best score for matching the query so far with its last character at name position j
    local prev = {}
    for j = 1, #n do
        if n:sub(j, j) == q:sub(1, 1) then
            prev[j] = 10 + (boundary(name, j) and 12 or 0) + (j == 1 and 15 or 0) - (j - 1)
        end
    end

    for i = 2, #q do
        local cur = {}
        local ch = q:sub(i, i)
        for j = 1, #n do
            if n:sub(j, j) == ch then
                local best
                for k = 1, j - 1 do
                    if prev[k] then
                        local s = prev[k] + 10 + (boundary(name, j) and 12 or 0)
                        if k == j - 1 then
                            s = s + 8
                        else
                            s = s - (j - k - 1)
                        end
                        if not best or s > best then best = s end
                    end
                end
                cur[j] = best
            end
        end
        prev = cur
    end

    local best
    for j = 1, #n do
        if prev[j] and (not best or prev[j] > best) then best = prev[j] end
    end
    if not best then return 0 end
    if best < 1 then return 1 end
    return best
end

-- the items whose key scores above zero, best first, stable among equals, at most limit (6 by default)
function M.rank(query, items, key, limit)
    local out = {}
    if type(items) ~= "table" or type(key) ~= "string" then return out end

    limit = math.floor(tonumber(limit) or 6)
    if limit <= 0 then return out end

    local scored = {}
    for i = 1, #items do
        local item = items[i]
        if type(item) == "table" then
            local name = item[key]
            if type(name) == "string" then
                local s = M.score(query, name)
                if s > 0 then scored[#scored + 1] = { item = item, score = s, at = i } end
            end
        end
    end

    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.at < b.at
    end)

    for i = 1, math.min(limit, #scored) do out[i] = scored[i].item end
    return out
end

return M
