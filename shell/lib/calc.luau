-- The Overview's sums (OVERVIEW-PORT stage 2): a small arithmetic evaluator for the search row.
-- Pure and deliberately tiny: + - * / % ^, parentheses, unary signs and decimals. No load(), no
-- environment, no names — text that is not a sum is not arithmetic, and a sum too large (or one
-- that divides by zero) is refused rather than returned as infinity.

local M = {}

M.MAX_POW = 64
M.MAX = 1e12

local function fail() error({ calc = true }, 0) end

local function parse(s)
    local i = 1
    local function peek() return string.sub(s, i, i) end
    local function skip() while peek():match("%s") do i = i + 1 end end
    local expr

    local function number()
        skip()
        local start = i
        while peek():match("[%d%.]") do i = i + 1 end
        local n = tonumber(string.sub(s, start, i - 1))
        if not n then fail() end
        return n
    end

    local function primary()
        skip()
        local c = peek()
        if c == "(" then
            i = i + 1
            local v = expr()
            skip()
            if peek() ~= ")" then fail() end
            i = i + 1
            return v
        elseif c == "+" then
            i = i + 1
            return primary()
        elseif c == "-" then
            i = i + 1
            return -primary()
        end
        return number()
    end

    local function power()
        local base = primary()
        skip()
        if peek() == "^" then
            i = i + 1
            local e = power()
            if math.abs(e) > M.MAX_POW then fail() end
            local v = base ^ e
            if v ~= v or math.abs(v) > M.MAX then fail() end
            return v
        end
        return base
    end

    local function product()
        local v = power()
        while true do
            skip()
            local c = peek()
            if c == "*" then
                i = i + 1
                v = v * power()
            elseif c == "/" then
                i = i + 1
                local d = power()
                if d == 0 then fail() end
                v = v / d
            elseif c == "%" then
                i = i + 1
                local d = power()
                if d == 0 then fail() end
                v = v % d
            else
                return v
            end
        end
    end

    expr = function()
        local v = product()
        while true do
            skip()
            local c = peek()
            if c == "+" then
                i = i + 1
                v = v + product()
            elseif c == "-" then
                i = i + 1
                v = v - product()
            else
                return v
            end
        end
    end

    local v = expr()
    skip()
    if i <= #s then fail() end
    return v
end

-- The value of `text`, or nil when it is not a sum, divides by zero, or runs past MAX.
function M.eval(text)
    local s = tostring(text or "")
    if s == "" or not string.find(s, "[%d%.]") then return nil end
    -- a word carrying digits is a name, not arithmetic ("kitty2", "mp3")
    if string.find(s, "[%a_]") then return nil end
    local ok, v = pcall(parse, s)
    if not ok or type(v) ~= "number" or v ~= v or math.abs(v) > M.MAX then return nil end
    return v
end

-- How a result is written in the list and on the clipboard: a whole number plainly, the rest to
-- ten significant figures.
function M.format(v)
    v = tonumber(v)
    if not v then return "" end
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.10g", v)
end

return M
