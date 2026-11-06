-- The weather panel's mapping, shared by the side notch and the Control Nexus (audit 2026-11-06,
-- G8: the first panel moved out of the two duplicated logic files). The forecast parsing is
-- lib/forecast's; this only turns a parsed forecast into the facts, text and rows both scenes draw.

local sysinfo = require("lib.sysinfo")

local M = {}

function M.kind(code, day)
    local k = sysinfo.weather(code, day)
    for i, name in ipairs(sysinfo.WEATHER_KINDS) do if name == k then return i - 1 end end
    return 2
end

-- The current reading: the kind index, the temperature and word, and the lines the notch shows.
function M.current(f)
    local _, word = sysinfo.weather(f.now.code, f.now.day)
    local temp = math.floor((tonumber(f.now.temp) or 0) + 0.5)
    return {
        kind = M.kind(f.now.code, f.now.day),
        temp = string.format("%d°", temp),
        temp_num = temp,
        word = string.upper(tostring(word or "")),
        feels = string.format("FEELS %d°", math.floor((tonumber(f.now.feels) or f.now.temp or 0) + 0.5)),
        range = f.today and f.today.hi and string.format("↑ %d°  ↓ %d°", math.floor(f.today.hi + 0.5), math.floor(f.today.lo + 0.5)) or "",
    }
end

-- The next six hours; `bars` is lib/notch.bars(f.hours) (the caller owns the bar heights).
function M.hours(f, bars)
    local rows = {}
    for i, h in ipairs(f.hours) do
        rows[i] = { n = i - 1, label = h.label .. ":00", temp = h.temp,
                    t = string.format("%d°", math.floor(h.temp + 0.5)),
                    v = bars and bars[i] or 0, kind = M.kind(h.code, h.day) }
    end
    return rows
end

-- The five days, with the high/low range normalised against the whole week.
function M.days(f)
    local lo, hi = math.huge, -math.huge
    for _, d in ipairs(f.days) do lo, hi = math.min(lo, d.lo), math.max(hi, d.hi) end
    local span = math.max(1, hi - lo)
    local rows = {}
    for i, d in ipairs(f.days) do
        rows[i] = { label = string.upper(string.sub(d.label, 1, 3)),
                    hi = tostring(math.floor(d.hi + 0.5)), lo = tostring(math.floor(d.lo + 0.5)),
                    kind = M.kind(d.code, 1), lo_v = (d.lo - lo) / span, hi_v = (d.hi - lo) / span }
    end
    return rows
end

return M
