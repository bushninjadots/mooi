-- The node's mixer (D230): what is playing, gathered into one row per application. Pure: it reads the decoded
-- JSON of `pactl -f json list sink-inputs` and answers the rows the node shows, plus the pactl commands that set
-- a row's volume or mute. It runs nothing itself.

local M = {}

-- a channel's value_percent ("64%") as a number; anything odd is nil
local function percent(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = v:match("^%s*(-?%d+%.?%d*)")
        return n and tonumber(n) or nil
    end
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- the streams of one application share a row: its name, icon, the stream ids that set it, the average of every
-- channel of every stream, whether all of them are muted, and how many there are
function M.group(list)
    local out, by = {}, {}
    if type(list) ~= "table" then return out end
    for _, item in ipairs(list) do
        -- a stream with no numeric index cannot be addressed, so it is no row
        if type(item) == "table" and type(item.index) == "number" then
            local props = type(item.properties) == "table" and item.properties or {}
            local name = props["application.name"]
            if type(name) ~= "string" or name == "" then name = props["application.process.binary"] end
            if type(name) ~= "string" or name == "" then name = "Unknown" end

            local g = by[name]
            if not g then
                g = { name = name, icon = "", ids = {}, streams = 0, muted = true, total = 0, channels = 0 }
                by[name] = g
                out[#out + 1] = g
            end

            local icon = props["application.icon_name"]
            if g.icon == "" and type(icon) == "string" then g.icon = icon end
            g.ids[#g.ids + 1] = item.index
            g.streams = g.streams + 1
            if item.mute ~= true then g.muted = false end

            if type(item.volume) == "table" then
                for _, channel in ipairs(item.volume) do
                    local p = type(channel) == "table" and percent(channel.value_percent) or nil
                    if p then
                        g.total = g.total + p
                        g.channels = g.channels + 1
                    end
                end
            end
        end
    end

    for _, g in ipairs(out) do
        g.volume = g.channels > 0 and clamp(g.total / g.channels / 100, 0, 1) or 0
        g.total, g.channels = nil, nil
    end

    -- by name, the case of it not mattering
    table.sort(out, function(a, b)
        local la, lb = a.name:lower(), b.name:lower()
        if la == lb then return a.name < b.name end
        return la < lb
    end)
    return out
end

-- the argv of one pactl call per stream, to set the row's volume (0..1.5, so a stream may be pushed up)
function M.set_volume(app, frac)
    local out = {}
    if type(app) ~= "table" or type(app.ids) ~= "table" then return out end
    local f = clamp(tonumber(frac) or 0, 0, 1.5)
    local n = math.floor(f * 100 + 0.5)
    for _, id in ipairs(app.ids) do
        out[#out + 1] = { "pactl", "set-sink-input-volume", tostring(id), tostring(n) .. "%" }
    end
    return out
end

-- the argv of one pactl call per stream, to mute or unmute the row
function M.set_mute(app, on)
    local out = {}
    if type(app) ~= "table" or type(app.ids) ~= "table" then return out end
    for _, id in ipairs(app.ids) do
        out[#out + 1] = { "pactl", "set-sink-input-mute", tostring(id), on and "1" or "0" }
    end
    return out
end

return M
