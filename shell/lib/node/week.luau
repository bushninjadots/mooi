-- The week's weather (D282): the Nexus's cached forecast as today plus six days, with one shared range for the
-- bars. Pure, so the unit suite runs it.

local M = {}

local calendar = require("lib/calendar")
local home = require("lib/node/home")

local DAYS = { "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN" }

local function list(t, k)
    if type(t) ~= "table" or type(t[k]) ~= "table" then return {} end
    return t[k]
end

local function round(n)
    n = tonumber(n)
    if not n then return nil end
    return math.floor(n + 0.5)
end

local function temp(n, suffix)
    n = round(n)
    if not n then return "—" end
    return n .. suffix
end

-- Open-Meteo's wet codes: drizzle, rain, snow, showers and thunder
local function wet(code)
    code = tonumber(code) or -1
    return (code >= 51 and code <= 67) or (code >= 71 and code <= 77)
        or (code >= 80 and code <= 86) or (code >= 95 and code <= 99)
end

function M.week(doc)
    if type(doc) ~= "table" or type(doc.answer) ~= "table" then return nil end
    local answer = doc.answer
    local daily = type(answer.daily) == "table" and answer.daily or {}
    local times, codes = list(daily, "time"), list(daily, "weather_code")
    local maxs, mins = list(daily, "temperature_2m_max"), list(daily, "temperature_2m_min")
    local rows, low, high, rainy = {}, math.huge, -math.huge, 0
    for i = 1, math.min(7, #times) do
        local hi, lo = tonumber(maxs[i]), tonumber(mins[i])
        if hi and lo then
            local y, m, d = tostring(times[i]):match("^(%d+)%-(%d+)%-(%d+)")
            local code = tonumber(codes[i]) or -1
            local glyph = home.weather(code)
            local label = i == 1 and "TODAY"
                or (y and DAYS[calendar.weekday(tonumber(y), tonumber(m), tonumber(d)) + 1] or "")
            local is_wet = wet(code)
            if is_wet then rainy = rainy + 1 end
            low, high = math.min(low, lo), math.max(high, hi)
            rows[#rows + 1] = {
                label = label, glyph = glyph, hi = temp(hi, "°"), lo = temp(lo, "°"),
                hi_n = hi, lo_n = lo, wet = is_wet,
            }
        end
    end
    if #rows == 0 then return nil end
    local span = math.max(1, high - low)
    for _, r in ipairs(rows) do
        r.lo_v = (r.lo_n - low) / span
        r.hi_v = (r.hi_n - low) / span
    end
    local cur = type(answer.current) == "table" and answer.current or nil
    local now = nil
    if cur and tonumber(cur.temperature_2m) then
        local glyph, word = home.weather(cur.weather_code)
        now = {
            temp = temp(cur.temperature_2m, "°"),
            feels = "FEELS " .. temp(cur.apparent_temperature or cur.temperature_2m, "°"),
            humidity = "HUMIDITY " .. temp(cur.relative_humidity_2m, "%"),
            wind = "WIND " .. temp(cur.wind_speed_10m, " KM/H"),
            glyph = glyph, word = string.upper(word or ""),
        }
    end
    local hi, lo = round(high), round(low)
    return {
        city = tostring(doc.city or ""),
        now = now,
        rows = rows,
        high = hi,
        low = lo,
        wet = rainy,
        summary = "HIGH " .. hi .. "°  ·  LOW " .. lo .. "°  ·  " .. rainy .. " WET " .. (rainy == 1 and "DAY" or "DAYS"),
    }
end

return M
