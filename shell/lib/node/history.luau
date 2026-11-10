-- The node's short history of a reading (D246): the last few samples of one number, kept in a ring so a
-- little graph can be drawn from it. Pure: it holds numbers and answers lists and points; it reads and
-- draws nothing itself.

local M = {}

local DEFAULT = 60
local MIN, MAX = 2, 240

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function count(h)
    return type(h) == "table" and tonumber(h.count) or 0
end

-- a new ring of n samples (2..240, 60 by default)
function M.new(n)
    n = math.floor(tonumber(n) or DEFAULT)
    if n < MIN then n = MIN end
    if n > MAX then n = MAX end
    return { n = n, i = 0, count = 0, data = {} }
end

-- add one reading; anything that is not a finite number is ignored, and the value is held to 0..1
function M.push(h, v)
    if type(h) ~= "table" or type(v) ~= "number" or v ~= v then return end
    local n = math.floor(tonumber(h.n) or DEFAULT)
    if n < MIN then n = MIN end
    if n > MAX then n = MAX end
    h.n = n
    h.i = (tonumber(h.i) or 0) % n + 1
    h.data[h.i] = clamp(v, 0, 1)
    h.count = math.min(n, (tonumber(h.count) or 0) + 1)
end

-- the readings from oldest to newest, at most n of them
function M.values(h)
    local out = {}
    local n = math.floor(tonumber(h and h.n) or DEFAULT)
    local c = count(h)
    if type(h) ~= "table" or c == 0 or n <= 0 then return out end
    local start = ((tonumber(h.i) or 0) - c) % n + 1
    for k = 1, c do
        out[k] = h.data[((start - 1 + (k - 1)) % n) + 1]
    end
    return out
end

-- the highest reading, or 0 when there is none
function M.peak(h)
    local best = 0
    for _, v in ipairs(M.values(h)) do
        if v > best then best = v end
    end
    return best
end

-- the average reading, or 0 when there is none
function M.mean(h)
    local vals = M.values(h)
    if #vals == 0 then return 0 end
    local total = 0
    for _, v in ipairs(vals) do total = total + v end
    return total / #vals
end

-- n readings across the history: short histories sit at the right, with zeroes at the left; longer ones
-- are averaged into n equal stretches
local function resample(h, n)
    n = math.floor(tonumber(n) or DEFAULT)
    if n < 1 then n = 1 end
    local vals = M.values(h)
    local out = {}
    for i = 1, n do out[i] = 0 end
    if #vals == 0 then return out end
    if #vals <= n then
        local off = n - #vals
        for i = 1, #vals do out[off + i] = vals[i] end
        return out
    end
    for i = 1, n do
        local lo = math.floor((i - 1) * #vals / n) + 1
        local hi = math.floor(i * #vals / n)
        if hi < lo then hi = lo end
        local total = 0
        for k = lo, hi do total = total + vals[k] end
        out[i] = total / (hi - lo + 1)
    end
    return out
end

-- n values for a bar graph, oldest at the left and newest at the right
function M.bars(h, n)
    return resample(h, n)
end

-- n points across a box of width w and height ht; the newest reading is at the right edge
function M.points(h, x, y, w, ht, n)
    n = math.floor(tonumber(n) or DEFAULT)
    if n < 1 then n = 1 end
    x, y = tonumber(x) or 0, tonumber(y) or 0
    w, ht = tonumber(w) or 0, tonumber(ht) or 0
    local vals = resample(h, n)
    local out = {}
    for i = 1, n do
        local at = n == 1 and w or (i - 1) * w / (n - 1)
        out[i] = { x = x + at, y = y + ht * (1 - vals[i]) }
    end
    return out
end

return M
