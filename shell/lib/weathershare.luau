-- One weather path for the bar, the weather island, the notch and the Nexus (audit 2026-11-06,
-- G7). It keeps one location memo (`ipinfo.json`, 24 h) and one forecast cache
-- (`nexus-weather.json`, 10 min), so a cold cache costs one IP lookup, not one per panel.
--
-- Pure in the decisions, thin in the I/O: the caller passes `read(name)`, `fetch(url, done)` and
-- `write(name, doc)`, because each scene has its own `run`/`sys` helpers. `done` receives the
-- fresh document, or the last usable one, or nil.

local forecast = require("lib/forecast")
local weathercache = require("lib/weathercache")

local M = { LOCATION_TTL = 86400, FORECAST_TTL = 600 }

function M.refresh(opts, done)
    local now = tonumber(opts.now) or os.time()
    local cached = opts.read("nexus-weather.json")
    if not weathercache.fresh(cached, now, M.FORECAST_TTL) then cached = nil end
    -- A fresh forecast is the answer: nothing is asked of open-meteo until it ages out, unless
    -- the caller insists (`force`). Without this every panel open cost a request (fourth pass, L6).
    if cached and not opts.force then done(cached); return end

    local function save(name, doc) pcall(opts.write, name, doc) end

    local function with_location(loc)
        opts.fetch(forecast.url(loc.lat, loc.lon), function(answer)
            if type(answer) ~= "table" or not forecast.parse(answer) then done(cached); return end
            local doc = { at = now, city = loc.city, answer = answer }
            save("nexus-weather.json", doc)
            done(doc)
        end)
    end

    local memo = opts.read("ipinfo.json")
    local loc = weathercache.location(memo, now, M.LOCATION_TTL)
    if loc then with_location(loc); return end

    opts.fetch("https://ipinfo.io/json", function(where)
        local lat, lon = weathercache.coordinates(where)
        if not lat then done(cached); return end
        local city = type(where) == "table" and where.city or nil
        save("ipinfo.json", { at = now, city = city, loc = tostring(where.loc) })
        with_location({ lat = lat, lon = lon, city = city })
    end)
end

-- A cache is usable when it is fresh; exported for the panels that want to draw it before
-- asking (the notch and the Nexus do).
function M.cached(read, now)
    local doc = read("nexus-weather.json")
    local t = tonumber(now) or os.time()
    return weathercache.fresh(doc, t, M.FORECAST_TTL) and doc or nil
end

return M
