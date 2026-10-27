-- The calendar island's month (D97): six weeks from Monday, each day marked as the month's own,
-- today, or a weekend; the month a press away; ISO week numbers. Pure, so tests/unit runs it.

local M = {}

M.MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August",
             "September", "October", "November", "December" }

local function idiv(a, b) return math.floor(a / b) end
local function leap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end

function M.days_in(y, m)
    if m == 2 then return leap(y) and 29 or 28 end
    if m == 4 or m == 6 or m == 9 or m == 11 then return 30 end
    return 31
end

-- The day of the week, 0 Monday … 6 Sunday (Sakamoto's method).
local T = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
function M.weekday(y, m, d)
    if m < 3 then y = y - 1 end
    local sun0 = (y + idiv(y, 4) - idiv(y, 100) + idiv(y, 400) + T[m] + d) % 7   -- 0 Sunday
    return (sun0 + 6) % 7
end

-- The month `delta` months from (y, m).
function M.shift(y, m, delta)
    local n = (y * 12 + (m - 1)) + delta
    return idiv(n, 12), n % 12 + 1
end

-- The ISO 8601 week of a date (weeks from Monday; week 1 holds the year's first Thursday).
function M.iso_week(y, m, d)
    local function ordinal(yy, mm, dd)
        local n = dd
        for i = 1, mm - 1 do n = n + M.days_in(yy, i) end
        return n
    end
    local wd = M.weekday(y, m, d) + 1                 -- 1 Monday … 7 Sunday
    local week = idiv(ordinal(y, m, d) - wd + 10, 7)
    if week < 1 then
        local py = y - 1
        local dec31 = M.weekday(py, 12, 31) + 1
        local pdays = leap(py) and 366 or 365
        return idiv(pdays - dec31 + 10, 7)
    end
    local days = leap(y) and 366 or 365
    if week == 53 and (days - ordinal(y, m, d)) < (4 - wd) then return 1 end
    return week
end

-- The 42 cells of (y, m): { day, cur, today, weekend }, from the Monday on or before the 1st.
-- `today` = { y, m, d } or nil.
function M.month(y, m, today)
    local lead = M.weekday(y, m, 1)
    local py, pm = M.shift(y, m, -1)
    local pdays = M.days_in(py, pm)
    local days = M.days_in(y, m)
    local cells = {}
    for i = 0, 41 do
        local c
        if i < lead then c = { day = pdays - lead + i + 1, cur = false }
        elseif i < lead + days then
            local d = i - lead + 1
            c = { day = d, cur = true,
                  today = today ~= nil and today.y == y and today.m == m and today.d == d }
        else c = { day = i - lead - days + 1, cur = false } end
        c.today = c.today == true
        c.weekend = i % 7 >= 5
        cells[#cells + 1] = c
    end
    return { title = M.MONTHS[m] .. " " .. y, cells = cells }
end

return M
