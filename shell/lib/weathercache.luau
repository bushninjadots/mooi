-- Shared cache and location guards for the Notch and Control Nexus weather panels.
-- A cache is reusable only when it contains a parseable forecast and a sane, non-future
-- timestamp. A malformed cache must never suppress a fresh request.

local forecast = require("lib/forecast")
local M = {}

local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function M.fresh(cache, now, ttl)
    if type(cache) ~= "table" or type(cache.answer) ~= "table" then return false end
    if not forecast.parse(cache.answer) then return false end
    local at = tonumber(cache.at)
    now = tonumber(now)
    ttl = tonumber(ttl)
    if not finite(at) or not finite(now) or not finite(ttl) or ttl <= 0 then return false end
    local age = now - at
    return age >= 0 and age < ttl
end

-- ipinfo's loc is "latitude,longitude". Validate both values before they reach a URL.
function M.coordinates(location)
    if type(location) ~= "table" or type(location.loc) ~= "string" then return nil end
    local lat_text, lon_text = location.loc:match("^%s*([^,]+),([^,]+)%s*$")
    if not lat_text then return nil end
    local lat, lon = tonumber(lat_text), tonumber(lon_text)
    if not finite(lat) or not finite(lon) or lat < -90 or lat > 90 or lon < -180 or lon > 180 then
        return nil
    end
    return lat, lon
end

return M
