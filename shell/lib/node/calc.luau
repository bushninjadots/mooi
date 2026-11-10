-- The node's search-line calculator (D235): a hand-written tokenizer and recursive-descent parser, so the text the
-- person types is only ever numbers and the operators below. Nothing is loaded or run from the input, and the only
-- library touched is math. Also the formatter the result is shown with.

local M = {}

local CONSTANTS = { pi = math.pi, e = math.exp(1), tau = 2 * math.pi }

local function degrees(x) return x * math.pi / 180 end
local function radians(x) return x * 180 / math.pi end
local function round(x)
    if x >= 0 then return math.floor(x + 0.5) end
    return math.ceil(x - 0.5)
end

local FUNCTIONS = {
    sqrt = math.sqrt,
    abs = math.abs,
    floor = math.floor,
    ceil = math.ceil,
    round = round,
    sin = function(x) return math.sin(degrees(x)) end,
    cos = function(x) return math.cos(degrees(x)) end,
    tan = function(x) return math.tan(degrees(x)) end,
    asin = function(x) return radians(math.asin(x)) end,
    acos = function(x) return radians(math.acos(x)) end,
    atan = function(x) return radians(math.atan(x)) end,
    ln = math.log,
    log = function(x) return math.log(x, 10) end,
}

-- one number: 12, 3.5, .5, 1e3, 1_000, and a comma as the decimal point when it sits between digits
local function read_number(text, i)
    local len = #text
    local buf = {}
    local function digit_at(k)
        return k <= len and text:sub(k, k):match("%d") ~= nil
    end

    while i <= len do
        local c = text:sub(i, i)
        if c:match("%d") then
            buf[#buf + 1] = c
            i = i + 1
        elseif c == "_" and #buf > 0 and digit_at(i + 1) then
            i = i + 1
        else
            break
        end
    end

    local whole = #buf > 0
    local c = text:sub(i, i)
    if c == "." or (c == "," and whole and digit_at(i + 1)) then
        buf[#buf + 1] = "."
        i = i + 1
        while i <= len do
            local d = text:sub(i, i)
            if d:match("%d") then
                buf[#buf + 1] = d
                i = i + 1
            elseif d == "_" and digit_at(i + 1) then
                i = i + 1
            else
                break
            end
        end
    end

    if text:sub(i):match("^[eE][%+%-]?%d") then
        local sign = text:sub(i):match("^[eE]([%+%-]?)")
        buf[#buf + 1] = "e"
        if sign ~= "" then buf[#buf + 1] = sign end
        i = i + 1 + #sign
        while i <= len do
            local d = text:sub(i, i)
            if d:match("%d") then
                buf[#buf + 1] = d
                i = i + 1
            elseif d == "_" and digit_at(i + 1) then
                i = i + 1
            else
                break
            end
        end
    end

    local value = tonumber(table.concat(buf))
    if not value then return nil, i, "bad number" end
    return value, i, nil
end

local function tokenize(text)
    local tokens = {}
    local i = 1
    local len = #text

    while i <= len do
        local c = text:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c:match("%d") or (c == "." and text:sub(i + 1, i + 1):match("%d")) then
            local value, after, err = read_number(text, i)
            if not value then return nil, err end
            tokens[#tokens + 1] = { t = "num", v = value }
            i = after
        elseif c:match("%a") then
            if c == "x" or c == "X" then
                tokens[#tokens + 1] = { t = "op", v = "*" }
                i = i + 1
            else
                local start = i
                while i <= len and text:sub(i, i):match("%a") do i = i + 1 end
                tokens[#tokens + 1] = { t = "name", v = text:sub(start, i - 1):lower() }
            end
        else
            local two = text:sub(i, i + 1)
            if two == "×" then
                tokens[#tokens + 1] = { t = "op", v = "*" }
                i = i + 2
            elseif two == "÷" then
                tokens[#tokens + 1] = { t = "op", v = "/" }
                i = i + 2
            elseif c == "+" or c == "-" or c == "*" or c == "/" or c == "^" or c == "%"
                or c == "(" or c == ")" then
                tokens[#tokens + 1] = { t = "op", v = c }
                i = i + 1
            else
                return nil, "unexpected character"
            end
        end
    end

    if #tokens == 0 then return nil, "empty" end
    return tokens
end

-- recursive descent: expr is + and -, term is * / % and the two word forms, unary is a sign, power is ^, primary
-- is a number, constant, function call or parenthesised expression. Percent is a postfix on the primary.
local function parse(tokens)
    local pos = 1
    local depth = 0
    local parse_expr, parse_term, parse_unary, parse_primary, parse_power

    local function fail(reason) error({ reason = reason }, 0) end
    local function peek() return tokens[pos] end
    local function take() local t = tokens[pos]; pos = pos + 1; return t end
    local function is_op(t, v) return t and t.t == "op" and t.v == v end
    local function starts_operand(t)
        if not t then return false end
        if t.t == "num" or t.t == "name" then return true end
        return t.t == "op" and t.v == "("
    end

    parse_primary = function()
        local t = peek()
        if not t then fail("unexpected end") end
        local value, percent

        if t.t == "num" then
            take()
            value, percent = t.v, false
        elseif t.t == "name" then
            take()
            if CONSTANTS[t.v] ~= nil then
                value, percent = CONSTANTS[t.v], false
            elseif FUNCTIONS[t.v] then
                if not is_op(peek(), "(") then fail("expected (") end
                take()
                local inner = parse_expr()
                if not is_op(peek(), ")") then fail("expected )") end
                take()
                value, percent = FUNCTIONS[t.v](inner), false
            else
                fail("unknown name")
            end
        elseif is_op(t, "(") then
            take()
            value, percent = parse_expr()
            if not is_op(peek(), ")") then fail("expected )") end
            take()
        else
            fail("unexpected token")
        end

        -- a percent is postfix, unless the % is the modulo operator with an operand after it
        while is_op(peek(), "%") and not starts_operand(tokens[pos + 1]) do
            take()
            value, percent = value / 100, true
        end
        return value, percent
    end

    parse_power = function()
        local value, percent = parse_primary()
        if is_op(peek(), "^") then
            take()
            value, percent = value ^ parse_unary(), false
        end
        return value, percent
    end

    parse_unary = function()
        local t = peek()
        if is_op(t, "-") or is_op(t, "+") then
            take()
            local value, percent = parse_unary()
            if t.v == "-" then value = -value end
            return value, percent
        end
        return parse_power()
    end

    parse_term = function()
        local left, percent = parse_unary()
        while true do
            local t = peek()
            if not (is_op(t, "*") or is_op(t, "/") or is_op(t, "%")) then break end
            take()
            local right = parse_unary()
            if t.v == "*" then
                left = left * right
            elseif t.v == "/" then
                if right == 0 then fail("division by zero") end
                left = left / right
            else
                if right == 0 then fail("division by zero") end
                left = left % right
            end
            percent = false
        end
        return left, percent
    end

    parse_expr = function()
        depth = depth + 1
        if depth > 64 then fail("too deep") end

        local left, percent = parse_term()
        while true do
            local t = peek()
            if not (is_op(t, "+") or is_op(t, "-")) then break end
            take()
            local right, right_percent = parse_term()
            if right_percent then
                -- "200 + 10%" is ten percent of the left side, not a tenth added to it
                local delta = left * right
                if t.v == "+" then left = left + delta else left = left - delta end
            elseif t.v == "+" then
                left = left + right
            else
                left = left - right
            end
            percent = false
        end

        depth = depth - 1
        return left, percent
    end

    local value = parse_expr()
    if pos <= #tokens then fail("unexpected token") end
    return value
end

-- evaluate the search line: value, nil or nil, reason
function M.eval(text)
    if type(text) ~= "string" then return nil, "not text" end
    if #text > 200 then return nil, "too long" end

    local tokens, err = tokenize(text)
    if not tokens then return nil, err end

    local ok, value = pcall(parse, tokens)
    if not ok then
        if type(value) == "table" and value.reason then return nil, value.reason end
        return nil, "bad expression"
    end
    if value ~= value then return nil, "not a number" end
    if value == math.huge or value == -math.huge then return nil, "not a number" end
    return value, nil
end

-- whether a word appears in the text on its own, not inside a longer word
local function word(lower, w)
    local init = 1
    while true do
        local a, b = lower:find(w, init, true)
        if not a then return false end
        local before = a == 1 or not lower:sub(a - 1, a - 1):match("%a")
        local after = b == #lower or not lower:sub(b + 1, b + 1):match("%a")
        if before and after then return true end
        init = b + 1
    end
end

-- whether the text is worth evaluating: a number or constant, something to do with it, and only allowed marks
function M.looks_like(text)
    if type(text) ~= "string" or text == "" then return false end

    local rest = text:gsub("[%d%a%s%+%-%*/%^%%%(%)%.,%_]", "")
    rest = rest:gsub("×", ""):gsub("÷", "")
    if rest ~= "" then return false end

    local lower = text:lower()
    local has_value = lower:match("%d") ~= nil
    if not has_value then
        for name in pairs(CONSTANTS) do
            if word(lower, name) then has_value = true; break end
        end
    end
    if not has_value then return false end

    local has_op = text:match("[%+%-%*/%^%%%(%)]") ~= nil
    if not has_op and (text:find("×", 1, true) or text:find("÷", 1, true)) then has_op = true end
    if not has_op and text:match("[%d%)%.]%s*[xX]%s*[%d%(%.]") then has_op = true end
    if not has_op then
        for name in pairs(FUNCTIONS) do
            if word(lower, name) then has_op = true; break end
        end
    end
    return has_op
end

-- a value as the card writes it: ten significant digits, no trailing zeros, plain between 1e-6 and 1e15
function M.format(v)
    if type(v) ~= "number" or v ~= v then return "" end
    if v == 0 then return "0" end
    if v == math.huge or v == -math.huge then return "" end

    local sign = v < 0 and "-" or ""
    local a = math.abs(v)
    local e = math.floor(math.log(a) / math.log(10))
    local p = 10 ^ e
    if a < p then e = e - 1 elseif a >= p * 10 then e = e + 1 end

    if a >= 1e-6 and a < 1e15 then
        local text
        if e > 9 then
            local step = 10 ^ (e - 9)
            local rounded = math.floor(a / step + 0.5) * step
            text = string.format("%.0f", rounded)
        else
            local places = 9 - e
            local scale = 10 ^ places
            local rounded = math.floor(a * scale + 0.5) / scale
            text = string.format("%." .. places .. "f", rounded)
            text = text:gsub("0+$", ""):gsub("%.$", "")
        end
        return sign .. text
    end

    local text = string.format("%.9e", a)
    local whole, frac, exp = text:match("^(%d+)%.(%d+)e([%+%-]%d+)$")
    if not whole then return sign .. text end
    frac = frac:gsub("0+$", "")
    local mantissa = whole
    if frac ~= "" then mantissa = whole .. "." .. frac end
    return sign .. mantissa .. "e" .. exp
end

return M
