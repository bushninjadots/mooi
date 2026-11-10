-- The node's device readings (D232): the screen's brightness, the microphone's volume and mute, the battery, and
-- the few numbers the device panel draws from them. Pure: it reads the text of brightnessctl, pactl and upower
-- and answers values and argv tables; it runs nothing itself.

local M = {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- a decimal that may have been written with a comma, as a number
local function number(s)
    if type(s) == "number" then return s end
    if type(s) ~= "string" then return nil end
    return tonumber((s:gsub(",", ".")))
end

-- one line of `brightnessctl -m` as device, current and max, else nil
local function brightness_line(line)
    local fields = {}
    -- each field followed by its comma: the same split in Luau (Lua 5.1's rules) and Lua 5.4, where a pattern that
    -- may match nothing does not give the same empty matches
    for field in (line .. ","):gmatch("([^,]*),") do fields[#fields + 1] = trim(field) end
    local device = fields[1]
    if not device or device == "" then return nil end

    local current, maximum = number(fields[3]), number(fields[5])
    if current and maximum and maximum > 0 then
        return { device = device, frac = clamp(current / maximum, 0, 1) }
    end

    -- no usable current and max: the percentage field is still a reading
    local p = fields[4] and fields[4]:match("^(%d+%.?%d*)%s*%%$")
    if p then return { device = device, frac = clamp(tonumber(p) / 100, 0, 1) } end
    return nil
end

-- the backlight's name and how far up it is, from `brightnessctl -m`
function M.brightness(text)
    if type(text) ~= "string" then return nil end
    for line in text:gmatch("[^\r\n]+") do
        local b = brightness_line(line)
        if b then return b end
    end
    return nil
end

-- the argv that sets the backlight; never 0%, because a black screen is not a setting
function M.set_brightness(frac)
    local f = clamp(tonumber(frac) or 0, 0.01, 1)
    local n = math.floor(f * 100 + 0.5)
    return { "brightnessctl", "-q", "set", tostring(n) .. "%" }
end

-- the microphone's level, the average of the percentages pactl prints for its channels
function M.source_volume(text)
    if type(text) ~= "string" then return nil end
    local total, count = 0, 0
    for p in text:gmatch("(%d+%.?%d*)%%") do
        total = total + tonumber(p)
        count = count + 1
    end
    if count == 0 then return nil end
    return total / count / 100
end

-- whether the microphone is muted: true, false, or nil when the text says neither
function M.source_mute(text)
    if type(text) ~= "string" then return nil end
    local answer = text:match("[Mm]ute:%s*(%a+)")
    if not answer then return nil end
    answer = answer:lower()
    if answer == "yes" then return true end
    if answer == "no" then return false end
    return nil
end

-- the argv that sets the microphone's level (0..1.5, so it may be pushed up)
function M.set_source_volume(frac)
    local f = clamp(tonumber(frac) or 0, 0, 1.5)
    local n = math.floor(f * 100 + 0.5)
    return { "pactl", "set-source-volume", "@DEFAULT_SOURCE@", tostring(n) .. "%" }
end

-- the argv that flips the microphone's mute
function M.toggle_source_mute()
    return { "pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle" }
end

-- a duration in upower's words ("2,3 hours", "35.5 minutes", "45 seconds") as minutes
local function minutes(value)
    local n, unit = value:match("(%d+[%.,]?%d*)%s*(%a+)")
    if not n then return nil end
    n = number(n)
    unit = unit:lower()
    if unit:match("^hour") then return math.floor(n * 60 + 0.5) end
    if unit:match("^minute") then return math.floor(n + 0.5) end
    if unit:match("^second") then return math.floor(n / 60 + 0.5) end
    return nil
end

-- the battery's percentage, state and remaining times, from `upower -i`; nil without a percentage line
function M.upower(text)
    if type(text) ~= "string" then return nil end
    local percent, state, left, full_in
    for line in text:gmatch("[^\r\n]+") do
        local key, value = line:match("^%s*([%w][%w%s%-]*):%s*(.-)%s*$")
        if key then
            key = trim(key):lower()
            if key == "percentage" then
                local p = value:match("^(%d+[%.,]?%d*)%s*%%$")
                if p then percent = number(p) end
            elseif key == "state" then
                state = trim(value)
            elseif key == "time to empty" then
                left = minutes(value)
            elseif key == "time to full" then
                full_in = minutes(value)
            end
        end
    end
    if not percent then return nil end
    return {
        percent = percent,
        state = state or "",
        charging = state == "charging" or state == "pending-charge",
        full = state == "fully-charged",
        minutes_left = left,
        minutes_to_full = full_in,
    }
end

-- how the battery's percentage reads: good, low, or critical
function M.band(percent)
    if type(percent) ~= "number" then return nil end
    if percent >= 50 then return "good" end
    if percent >= 20 then return "low" end
    return "critical"
end

-- true only when the battery has just fallen below 20 and is not charging
function M.crossed_critical(before, after, charging)
    if charging then return false end
    if type(after) ~= "number" or after >= 20 then return false end
    if before ~= nil and (type(before) ~= "number" or before < 20) then return false end
    return true
end

-- a number of minutes as the panel writes it; nothing to say for nil or less than none
function M.format_minutes(m)
    local n = tonumber(m)
    if not n or n < 0 then return "" end
    n = math.floor(n + 0.5)
    if n < 1 then return "< 1 min" end
    if n < 60 then return n .. " min" end
    local hours = math.floor(n / 60)
    return hours .. " h " .. (n - hours * 60) .. " min"
end

-- whether the active window is fullscreen, from `hyprctl -j activewindow`
function M.fullscreen(win)
    if type(win) ~= "table" then return false end
    local f = win.fullscreen
    if f == true or (type(f) == "number" and f > 0) then return true end
    local client = win.fullscreenClient
    return type(client) == "number" and client > 0
end

-- how many of a meter's n segments are lit
function M.segments(frac, n)
    local count = tonumber(n) or 0
    if count < 0 then count = 0 end
    local f = clamp(tonumber(frac) or 0, 0, 1)
    return math.floor(f * count + 0.5)
end

-- where a drag at x sits on a meter that starts at x0 and is w wide
function M.frac_at(x, x0, w)
    local width = tonumber(w) or 0
    if width <= 0 then return 0 end
    return clamp(((tonumber(x) or 0) - (tonumber(x0) or 0)) / width, 0, 1)
end

return M
