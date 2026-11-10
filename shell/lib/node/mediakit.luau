-- The node's media helpers (D233): one playerctl line read into the state the media card shows, the commands that
-- shuffle, loop and seek, a clock, YouTube's video id and thumbnails, and the mirrored spectrum the card draws.
-- Pure: it reads strings and tables and answers values and argv tables; it runs nothing itself.

local M = {}

-- the exact `playerctl metadata --format` line parse() reads
M.FORMAT = "{{playerName}}\t{{status}}\t{{shuffle}}\t{{loop}}\t{{position}}\t{{mpris:length}}\t{{xesam:url}}\t{{mpris:artUrl}}"

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- microseconds as whole milliseconds; anything unreadable is 0
local function milliseconds(s)
    local n = tonumber(s)
    if not n or n < 0 then return 0 end
    return math.floor(n / 1000 + 0.5)
end

-- "true"/"On"/"1" and their opposites as a boolean
local function switched(s)
    s = trim(s):lower()
    return s == "true" or s == "on" or s == "1" or s == "yes"
end

-- the loop mode as playerctl names it; anything else is no loop
local function loop_name(s)
    s = trim(s):lower()
    if s == "track" then return "Track" end
    if s == "playlist" then return "Playlist" end
    return "None"
end

-- one line of the format above as the card's state; nil when the line is not that line
function M.parse(line)
    if type(line) ~= "string" then return nil end
    line = line:gsub("[\r\n]+$", "")
    if line == "" then return nil end

    local fields = {}
    -- each field followed by its tab: the same split in Luau (Lua 5.1's rules) and Lua 5.4, where a pattern that
    -- may match nothing does not give the same empty matches
    for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
    if #fields < 8 then return nil end

    local status = trim(fields[2]):lower()
    if status == "playing" then status = "Playing"
    elseif status == "paused" then status = "Paused"
    else status = "Stopped" end

    return {
        player = fields[1],
        status = status,
        playing = status == "Playing",
        shuffle = switched(fields[3]),
        loop = loop_name(fields[4]),
        position_ms = milliseconds(fields[5]),
        length_ms = milliseconds(fields[6]),
        url = fields[7],
        art = fields[8],
    }
end

-- the loop mode after the button is pressed: none, then the playlist, then the one track, then none
function M.next_loop(loop)
    if loop == "Playlist" then return "Track" end
    if loop == "Track" then return "None" end
    return "Playlist"
end

-- playerctl's argv, with -p and the player only when there is one to name
local function command(player, args)
    local out = { "playerctl" }
    if type(player) == "string" and player ~= "" then
        out[#out + 1] = "-p"
        out[#out + 1] = player
    end
    for _, arg in ipairs(args) do out[#out + 1] = arg end
    return out
end

function M.cmd_shuffle(player, on)
    return command(player, { "shuffle", on and "On" or "Off" })
end

function M.cmd_loop(player, loop)
    if type(loop) ~= "string" or loop == "" then loop = "None" end
    return command(player, { "loop", loop })
end

-- seek to a share of the track; nil when there is no track length to seek within
function M.cmd_seek(player, frac, length_ms)
    local length = tonumber(length_ms)
    if not length or length <= 0 then return nil end
    local f = clamp(tonumber(frac) or 0, 0, 1)
    local seconds = f * length / 1000
    return command(player, { "position", string.format("%.1f", seconds) })
end

-- milliseconds as the card's clock: 3:07, or 1:02:09 once there is an hour
function M.format_time(ms)
    local n = tonumber(ms)
    if not n or n < 0 then return "0:00" end
    local total = math.floor(n / 1000)
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total - hours * 3600) / 60)
    local seconds = total - hours * 3600 - minutes * 60
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, seconds) end
    return string.format("%d:%02d", minutes, seconds)
end

-- a video id is exactly eleven characters of the url-safe alphabet
local function video_id(s)
    if type(s) ~= "string" or #s ~= 11 then return nil end
    if not s:match("^[A-Za-z0-9_%-]+$") then return nil end
    return s
end

-- the eleven-character id in a YouTube url, in any of the forms the card meets
function M.youtube_id(url)
    if type(url) ~= "string" then return nil end
    local host, rest = url:match("^[Hh][Tt][Tt][Pp][Ss]?://([^/]+)(.*)$")
    if not host then return nil end
    host = host:lower():gsub("^www%.", ""):gsub("^m%.", "")

    if host == "youtu.be" then
        return video_id(rest:match("^/([^/?#]+)"))
    end
    if host ~= "youtube.com" and host ~= "music.youtube.com" then return nil end

    local query = rest:match("^/watch%?(.*)$")
    if query then
        query = query:gsub("#.*$", "")
        for pair in (query .. "&"):gmatch("([^&]*)&") do
            local key, value = pair:match("^([^=]*)=(.*)$")
            if key == "v" then
                local id = video_id(value)
                if id then return id end
            end
        end
        return nil
    end

    local kind, id = rest:match("^/([%a]+)/([^/?#]+)")
    if kind == "shorts" or kind == "live" or kind == "embed" then return video_id(id) end
    return nil
end

-- the stills YouTube keeps for a video, best first
function M.thumbnails(id)
    local out = {}
    if type(id) ~= "string" or id == "" then return out end
    for _, name in ipairs({ "maxresdefault", "sddefault", "hqdefault", "mqdefault" }) do
        out[#out + 1] = "https://i.ytimg.com/vi/" .. id .. "/" .. name .. ".jpg"
    end
    return out
end

-- the picture to show: the metadata's own art, else a YouTube thumbnail, else nothing
function M.art_for(meta)
    if type(meta) ~= "table" then return "" end
    local art = meta.art
    if type(art) == "string" then
        local lower = art:lower()
        if lower:match("^file://") or lower:match("^https?://") then return art end
    end
    local id = M.youtube_id(meta.url)
    if id then return M.thumbnails(id)[1] end
    return ""
end

-- a list of band levels as n mirrored values, the low bands meeting in the middle
function M.mirrored(bands, n)
    n = math.floor(tonumber(n) or 0)
    if n % 2 ~= 0 then n = n - 1 end
    if n <= 0 then return {} end
    local half = n / 2
    local list = type(bands) == "table" and bands or {}
    local count = #list

    local function level(v)
        return clamp(tonumber(v) or 0, 0, 1)
    end

    -- one half from low to high: each slot averages the bands that fall in it, or repeats the nearest band when
    -- there are fewer bands than slots
    local right = {}
    for i = 1, half do
        local first = math.floor((i - 1) * count / half) + 1
        local last = math.floor(i * count / half)
        if last < first then
            local at = math.ceil(i * count / half)
            if at < 1 then at = 1 end
            if at > count then at = count end
            right[i] = level(list[at])
        else
            local total = 0
            for j = first, last do total = total + level(list[j]) end
            right[i] = total / (last - first + 1)
        end
    end

    local out = {}
    for i = 1, half do
        out[i] = right[half - i + 1]
        out[half + i] = right[i]
    end
    return out
end

return M
