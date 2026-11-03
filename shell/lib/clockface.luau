-- The clock widgets' reading of the time (D140): the time in words, the hands' angles, hh:mm in
-- either clock, and the board's next card due (for the Info clock). Pure.

local M = {}

local NAMES = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve" }
local PAST = { [5] = "five past", [10] = "ten past", [15] = "quarter past", [20] = "twenty past", [25] = "twenty-five past",
               [30] = "half past", [35] = "twenty-five to", [40] = "twenty to", [45] = "quarter to", [50] = "ten to", [55] = "five to" }

local function hour_name(h, exact)
    h = h % 24
    if exact and h == 0 then return "midnight" end
    if exact and h == 12 then return "noon" end
    local n = h % 12
    return NAMES[n == 0 and 12 or n]
end

-- "ten past four", "nearly quarter to five", "just after noon": to the nearest five minutes
function M.words(h, m)
    local m5 = math.floor((m + 2) / 5) * 5
    local diff = m - m5
    local hh = h
    if m5 == 60 then m5 = 0; hh = h + 1 end
    local prefix = diff > 0 and "just after " or (diff < 0 and "nearly " or "")
    local body
    if m5 == 0 then
        local name = hour_name(hh, true)
        body = (name == "midnight" or name == "noon") and name or (name .. " o'clock")
    elseif m5 <= 30 then body = PAST[m5] .. " " .. hour_name(hh, false)
    else body = PAST[m5] .. " " .. hour_name(hh + 1, false) end
    return prefix .. body
end

function M.angles(h, m, s)
    return { hour = ((h % 12) + m / 60) * 30, minute = (m + (s or 0) / 60) * 6, second = (s or 0) * 6 }
end

function M.hhmm(h, m, h24)
    if h24 then return string.format("%02d:%02d", h, m) end
    local n = h % 12
    return string.format("%d:%02d", n == 0 and 12 or n, m)
end
function M.ampm(h) return (h % 24) < 12 and "AM" or "PM" end

local WEEKDAYS = { "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY" }   -- day 0 = 1970-01-01, a Thursday

-- The earliest card due today or later that is not in the board's last column (done); `today` is
-- the day number (days since 1970, local) the board uses.
function M.next_due(board, today)
    if type(board) ~= "table" or type(board.cards) ~= "table" then return nil end
    local cols = type(board.columns) == "table" and board.columns or {}
    local done_col = #cols > 0 and cols[#cols].id or nil
    local best
    for _, c in ipairs(board.cards) do
        local due = tonumber(c.due)
        if due and due >= today and c.col ~= done_col and (not best or due < best.due) then best = { due = due, title = tostring(c.title or "") } end
    end
    if not best then return nil end
    local label = best.due == today and "TODAY" or (best.due == today + 1 and "TOMORROW" or WEEKDAYS[best.due % 7 + 1])
    return { title = best.title, label = label, due = best.due }
end

return M
