-- The weather island's forecast (D97): open-meteo's answer (current + hourly + daily, local
-- times) as now, today's high and low, the next six hours and five days. Pure, so tests/unit
-- runs it; an answer it cannot read is nil, a part it cannot read is empty.

local calendar = require("lib/calendar")

local M = {}

local DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

local function list(t, k) return type(t) == "table" and type(t[k]) == "table" and t[k] or {} end

function M.parse(t)
    if type(t) ~= "table" or type(t.current) ~= "table" then return nil end
    local c = t.current
    local out = {
        now = { temp = tonumber(c.temperature_2m) or 0, feels = tonumber(c.apparent_temperature) or tonumber(c.temperature_2m) or 0,
                humidity = tonumber(c.relative_humidity_2m) or 0, wind = tonumber(c.wind_speed_10m) or 0,
                code = tonumber(c.weather_code) or -1, day = tonumber(c.is_day) or 1 },
        today = { hi = nil, lo = nil },
        hours = {}, days = {},
    }
    -- the six hours after the current one ("2026-10-27T20:15" → from 21:00)
    local now_hour = tostring(c.time or ""):sub(1, 13)
    local ht, htemp, hcode, hday = list(t.hourly, "time"), list(t.hourly, "temperature_2m"), list(t.hourly, "weather_code"), list(t.hourly, "is_day")
    local start = nil
    for i, when in ipairs(ht) do
        if tostring(when):sub(1, 13) == now_hour then start = i + 1; break end
    end
    if start then
        for i = start, math.min(#ht, start + 5) do
            out.hours[#out.hours + 1] = { label = tostring(ht[i]):sub(12, 13), temp = tonumber(htemp[i]) or 0,
                                          code = tonumber(hcode[i]) or -1, day = tonumber(hday[i]) or 1 }
        end
    end
    -- five days from today
    local dt, dcode, dmax, dmin = list(t.daily, "time"), list(t.daily, "weather_code"), list(t.daily, "temperature_2m_max"), list(t.daily, "temperature_2m_min")
    for i = 1, math.min(5, #dt) do
        local y, m, d = tostring(dt[i]):match("^(%d+)%-(%d+)%-(%d+)")
        local label = i == 1 and "Today" or (y and DAYS[calendar.weekday(tonumber(y), tonumber(m), tonumber(d)) + 1] or "")
        out.days[#out.days + 1] = { label = label, code = tonumber(dcode[i]) or -1,
                                    hi = tonumber(dmax[i]) or 0, lo = tonumber(dmin[i]) or 0 }
    end
    if out.days[1] then out.today.hi, out.today.lo = out.days[1].hi, out.days[1].lo end
    return out
end

-- open-meteo's request for (lat, lon).
function M.url(lat, lon)
    return "https://api.open-meteo.com/v1/forecast?latitude=" .. lat .. "&longitude=" .. lon
        .. "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
        .. "&hourly=temperature_2m,weather_code,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min"
        .. "&timezone=auto&forecast_days=6"
end

return M
