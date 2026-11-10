-- The panel's Home header (D272): the words and glyphs it shows above the music. Pure, so the unit suite runs it.

local M = {}

-- Open-Meteo's weather codes (the Nexus's weather file) as a Nerd glyph and a word
local CODES = {
    { 0, 0, "󰖙", "Clear" }, { 1, 2, "󰖕", "Partly cloudy" }, { 3, 3, "󰖐", "Cloudy" }, { 45, 48, "󰖑", "Fog" },
    { 51, 57, "󰖗", "Drizzle" }, { 61, 67, "󰖖", "Rain" }, { 71, 77, "󰖘", "Snow" }, { 80, 82, "󰖖", "Showers" },
    { 85, 86, "󰖘", "Snow showers" }, { 95, 99, "󰖓", "Thunder" },
}
function M.weather(code)
    code = tonumber(code)
    if not code then return "", "" end
    for _, c in ipairs(CODES) do if code >= c[1] and code <= c[2] then return c[3], c[4] end end
    return "󰖐", ""
end

-- the weather line from nexus-weather.json's `answer.current`: "󰖕 18° · Partly cloudy", or "" without one
function M.weather_line(cur)
    if type(cur) ~= "table" then return "", "" end
    local t = tonumber(cur.temperature_2m)
    if not t then return "", "" end
    local glyph, word = M.weather(cur.weather_code)
    return glyph, math.floor(t + 0.5) .. "°" .. (word ~= "" and (" · " .. word) or "")
end

-- the battery as the header says it: "󰁹 90%", "󰂄 54%" while charging; "" with no battery
local LEVELS = { "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹" }
function M.battery(pct, charging)
    pct = tonumber(pct)
    if not pct then return "" end
    local g = charging and "󰂄" or LEVELS[math.max(1, math.min(10, math.ceil(pct / 10)))]
    return g .. " " .. math.floor(pct + 0.5) .. "%"
end

-- the date under the clock: "Tuesday 10 November"
function M.date(t) return os.date("%A ", t) .. tonumber(os.date("%d", t)) .. os.date(" %B", t) end

-- a reading for the strip: "CPU 20%", or "CPU —"
function M.reading(label, v, unit)
    v = tonumber(v)
    if not v then return label .. " —" end
    return label .. " " .. math.floor(v + 0.5) .. (unit or "%")
end

local function trim(s)
    s = type(s) == "string" and s or ""
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

-- the profile card's words: the display name (never empty), the hostname, the picture's file, and the letter
-- shown when there is no picture
function M.identity(name, host, avatar)
    name = trim(name)
    if name == "" then name = "mooi" end
    host = trim(host)
    avatar = trim(avatar)
    return { name = name, host = host, avatar = avatar, initial = string.upper(string.sub(name, 1, 1)) }
end

-- the picture's path, or "" when there is no name or the file is not there (then the card keeps the initial)
function M.face(folder, avatar, exists)
    folder = trim(folder)
    avatar = trim(avatar)
    if folder == "" or avatar == "" then return "" end
    if exists and not exists(avatar) then return "" end
    return folder .. "/" .. avatar
end

return M
