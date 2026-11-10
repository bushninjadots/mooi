-- The node's clock styles (D250): the ways the node can tell the time — pixels, digits, hands, words, bits and
-- dots. Pure: every function takes the hour and minute (and the seconds where a hand or a timer needs them) and
-- returns what to show, and nothing here draws, reads a file or asks the system for the time.

local M = {}

M.STYLES = { "pixel", "digital", "analog", "words", "binary", "dots" }

-- a whole number in range, or the fallback when there is none
local function whole(v, lo, hi, d)
    v = tonumber(v)
    if not v then return d end
    v = math.floor(v)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- the hour on a 12-hour face, 0 to 11 (0 is twelve)
local function hour12(h) return h % 12 end

-- the names of the twelve hours, twelve first
local HOURS = { "twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven" }
local function hour_name(h) return HOURS[hour12(h) + 1] end

-- the only minute counts the words need
local MINUTES = { [5] = "five", [10] = "ten", [20] = "twenty", [25] = "twenty-five" }

-- the hour and minute as digits: 24-hour with a leading zero, 12-hour without one
function M.digital(h, m, h24)
    h = whole(h, 0, 23, 0)
    m = whole(m, 0, 59, 0)
    if h24 then return string.format("%02d:%02d", h, m) end
    local hh = hour12(h)
    if hh == 0 then hh = 12 end
    return string.format("%d:%02d", hh, m)
end

-- the hands' angles in degrees: 0 is twelve o'clock and the way round is clockwise. The hour hand creeps on
-- with the minutes, so half past seven is not quite halfway between seven and eight.
function M.analog(h, m, s)
    h = whole(h, 0, 23, 0)
    m = whole(m, 0, 59, 0)
    s = whole(s, 0, 59, 0)
    return {
        hour = hour12(h) * 30 + m * 0.5,
        minute = m * 6,
        second = s * 6,
    }
end

-- the time in English, rounded to the nearest five minutes: "five past seven", "half past seven",
-- "twenty-five to eight", "seven o'clock", and the two the day turns on, "midnight" and "noon"
function M.words(h, m)
    h = whole(h, 0, 23, 0)
    m = whole(m, 0, 59, 0)
    -- the nearest five minutes, half up, may carry into the next hour or over midnight
    local total = h * 60 + m
    local r = math.floor(total / 5 + 0.5) * 5
    local hh, mm = math.floor(r / 60) % 24, r % 60

    if mm == 0 then
        if hh == 0 then return "midnight" end
        if hh == 12 then return "noon" end
        return hour_name(hh) .. " o'clock"
    end
    if mm == 15 then return "quarter past " .. hour_name(hh) end
    if mm == 30 then return "half past " .. hour_name(hh) end
    if mm == 45 then return "quarter to " .. hour_name(hh + 1) end
    if mm < 30 then return MINUTES[mm] .. " past " .. hour_name(hh) end
    return MINUTES[60 - mm] .. " to " .. hour_name(hh + 1)
end

-- six bits, most significant first
local function bits(v)
    local out = {}
    for i = 6, 1, -1 do
        local p = 2 ^ (i - 1)
        out[#out + 1] = (v % (p * 2)) >= p
    end
    return out
end

-- the hour and minute as two rows of six lights, the 24-hour hour first
function M.binary(h, m)
    h = whole(h, 0, 23, 0)
    m = whole(m, 0, 59, 0)
    return { h = bits(h), m = bits(m) }
end

-- the hour as one lit dot for each hour past twelve, the minute as one for each five minutes, and the
-- minutes in between as up to four smaller dots
function M.dots(h, m)
    h = whole(h, 0, 23, 0)
    m = whole(m, 0, 59, 0)
    return { hours = hour12(h), minutes = math.floor(m / 5), sub = m % 5 }
end

-- milliseconds until what the style shows is next different. A hand with seconds ticks every second, the
-- minute styles on the minute, and the words when their rounding turns over: half a five-minute step
-- before the five-minute marks (…:02:30, …:07:30 and so on), not on them.
function M.next_change_ms(style, now_s, ms)
    local s = whole(now_s, 0, 2 ^ 53, 0)
    ms = whole(ms, 0, 999, 0)

    if style == "analog" then return 1000 - ms end

    if style == "words" then
        local t = (s % 300) * 1000 + ms
        local to = 150000 - t
        if to <= 0 then to = to + 300000 end
        return to
    end

    -- pixel, digital, binary, dots and anything unknown change on the minute
    return (60 - (s % 60)) * 1000 - ms
end

return M
