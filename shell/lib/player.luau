-- The music player's working-out (docs/PLAYER.md): what mpc says, what a lyric file says, where the
-- tonearm points. Pure: no processes, no files — tests/unit runs it under Lua 5.4, and
-- shell/mooi-player.luau runs the commands and hands the scene the results.

local M = {}

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function clamp(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end

-- ── mpc ───────────────────────────────────────────────────────────
-- The formats the player asks mpc for: tab-separated fields, one item a line.
M.STATUS_FMT = "%state%\t%currenttime%\t%totaltime%\t%volume%\t%random%\t%repeat%\t%single%\t%consume%\t%songpos%\t%length%"
M.SONG_FIELDS = { "file", "artist", "albumartist", "album", "title", "track", "date", "time", "position" }
M.SONG_FMT = "%file%\t%artist%\t%albumartist%\t%album%\t%title%\t%track%\t%date%\t%time%\t%position%"

-- "3:13", "1:02:03" or "75" as seconds; anything else is 0.
function M.seconds(s)
    s = trim(s)
    local h, m, sec = s:match("^(%d+):(%d+):(%d+)$")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec) end
    m, sec = s:match("^(%d+):(%d+)$")
    if m then return tonumber(m) * 60 + tonumber(sec) end
    return tonumber(s:match("^(%d+)$") or "") or 0
end

-- Seconds as the player writes them: 3:05, 1:02:03.
function M.clock(n)
    n = math.max(0, math.floor(tonumber(n) or 0))
    local h, m, s = math.floor(n / 3600), math.floor(n % 3600 / 60), n % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- `mpc status STATUS_FMT`: what mpd is doing. A line that is not one (mpd not running, an error)
-- answers nil.
function M.parse_status(out)
    local line = trim(tostring(out or ""):match("[^\n]*") or "")
    local f = {}
    for part in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = trim(part) end
    if #f < 10 then return nil end
    local state = f[1]
    if state ~= "playing" and state ~= "paused" and state ~= "stopped" then return nil end
    local vol = tonumber((f[4]:gsub("%%", ""))) or -1
    return {
        state = state, elapsed = M.seconds(f[2]), total = M.seconds(f[3]),
        volume = vol < 0 and -1 or clamp(vol, 0, 100),
        random = f[5] == "on", ["repeat"] = f[6] == "on", single = f[7] == "on", consume = f[8] == "on",
        pos = tonumber(f[9]) or 0, length = tonumber(f[10]) or 0,
    }
end

-- Tab-separated rows (`-f SONG_FMT`) as songs: every field named, `seconds` from `time`, and a
-- name to show even when the tags are missing (the file's own name, without its folder or ending).
function M.parse_songs(out, fields)
    fields = fields or M.SONG_FIELDS
    local list = {}
    for line in tostring(out or ""):gmatch("[^\n]+") do
        local f, i = {}, 0
        for part in (line .. "\t"):gmatch("([^\t]*)\t") do i = i + 1; f[fields[i] or ("f" .. i)] = trim(part) end
        if f.file and f.file ~= "" then
            f.seconds = M.seconds(f.time)
            if not f.title or f.title == "" then
                f.title = (f.file:match("([^/]+)$") or f.file):gsub("%.[%w]+$", "")
            end
            f.artist = (f.artist ~= nil and f.artist ~= "") and f.artist or (f.albumartist or "")
            f.position = tonumber(f.position) or 0
            list[#list + 1] = f
        end
    end
    return list
end

-- One name a line (`mpc list album`, `mpc list albumartist`), blanks dropped, sorted A→Z ignoring
-- case and a leading "The ".
local function sort_key(s) return (string.lower(s):gsub("^the ", "")) end
function M.parse_names(out)
    local list, seen = {}, {}
    for line in tostring(out or ""):gmatch("[^\n]+") do
        local n = trim(line)
        if n ~= "" and not seen[n] then seen[n] = true; list[#list + 1] = n end
    end
    table.sort(list, function(a, b) return sort_key(a) < sort_key(b) end)
    return list
end

-- A file's path on disk, from mpd's music folder and the song's `file`.
function M.path(music_dir, file)
    music_dir = trim(music_dir)
    if file == nil or file == "" then return "" end
    if file:sub(1, 1) == "/" then return file end
    if music_dir:sub(-1) == "/" then return music_dir .. file end
    return music_dir .. "/" .. file
end

-- The `music_directory` line of an mpd.conf (quoted, `~` expanded).
function M.music_dir(conf, home)
    for line in tostring(conf or ""):gmatch("[^\n]+") do
        local v = line:match('^%s*music_directory%s+"([^"]+)"') or line:match("^%s*music_directory%s+(%S+)")
        if v then
            if v:sub(1, 1) == "~" then v = tostring(home or "") .. v:sub(2) end
            return v
        end
    end
    return nil
end

-- A short stable name for a cache file (a cover per album, a waveform per file, lyrics per song).
function M.hash(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 4294967296 end
    return string.format("%08x", h)
end

-- ── The turntable ─────────────────────────────────────────────────
-- The tonearm's angle (degrees from its rest, clockwise): set down on the outer groove at the
-- song's start, travelling to the label's edge at its end; parked off the record while stopped.
M.ARM_REST, M.ARM_START, M.ARM_END = 0, 20, 40
function M.arm(progress, state)
    if state == "stopped" or state == nil then return M.ARM_REST end
    return M.ARM_START + (M.ARM_END - M.ARM_START) * clamp(tonumber(progress) or 0, 0, 1)
end

-- The seek a dragged arm asks for: its angle back to a fraction of the song.
function M.arm_fraction(angle)
    return clamp(((tonumber(angle) or 0) - M.ARM_START) / (M.ARM_END - M.ARM_START), 0, 1)
end

-- ── Lyrics ────────────────────────────────────────────────────────
-- An LRC file: `[mm:ss.xx]` stamps (several may lead one line), an `[offset:±ms]` tag, metadata
-- tags ignored. Returns { synced = true, lines = { { t, text } … } } in time order, or, for text with
-- no stamps, { synced = false, lines = { { t = 0, text } … } }.
function M.parse_lrc(s)
    s = tostring(s or "")
    local offset = 0
    local timed, plain = {}, {}
    for raw in (s .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw:gsub("\r$", "")
        local off = line:match("^%s*%[offset:%s*([+-]?%d+)%s*%]")
        if off then
            offset = (tonumber(off) or 0) / 1000
        elseif not line:match("^%s*%[%a+:.*%]%s*$") then
            local stamps, rest = {}, line
            while true do
                local m, sec, after = rest:match("^%s*%[(%d+):(%d+%.?%d*)%](.*)$")
                if not m then break end
                stamps[#stamps + 1] = tonumber(m) * 60 + tonumber(sec)
                rest = after
            end
            rest = trim(rest)
            if #stamps > 0 then
                for _, t in ipairs(stamps) do timed[#timed + 1] = { t = t, text = rest } end
            elseif rest ~= "" then
                plain[#plain + 1] = { t = 0, text = rest }
            end
        end
    end
    if #timed > 0 then
        -- a positive offset shows the lines earlier
        for _, l in ipairs(timed) do l.t = math.max(0, l.t - offset) end
        table.sort(timed, function(a, b) return a.t < b.t end)
        return { synced = true, lines = timed }
    end
    return { synced = false, lines = plain }
end

-- The line being sung at `t` (seconds): the last one that has started, 0 before the first.
function M.lyric_at(lyrics, t)
    if type(lyrics) ~= "table" or not lyrics.synced then return 0 end
    local at = 0
    for i, l in ipairs(lyrics.lines) do
        if l.t <= (tonumber(t) or 0) + 0.05 then at = i else break end
    end
    return at
end

local function enc(s)
    return (tostring(s or ""):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end
M.urlencode = enc

-- LRCLIB's lookup for a song (artist, title, album, length in seconds).
function M.lrclib_url(artist, title, album, seconds)
    local q = "artist_name=" .. enc(artist) .. "&track_name=" .. enc(title)
    if album and album ~= "" then q = q .. "&album_name=" .. enc(album) end
    if seconds and tonumber(seconds) and tonumber(seconds) > 0 then q = q .. "&duration=" .. math.floor(tonumber(seconds) + 0.5) end
    return "https://lrclib.net/api/get?" .. q
end

-- LRCLIB's answer (decoded JSON): the synced lyrics when there are some, else the plain ones, else
-- nil; `instrumental` says there are none to find.
function M.from_lrclib(t)
    if type(t) ~= "table" then return nil end
    if t.instrumental == true then return { synced = false, lines = {}, instrumental = true } end
    if type(t.syncedLyrics) == "string" and t.syncedLyrics ~= "" then return M.parse_lrc(t.syncedLyrics) end
    if type(t.plainLyrics) == "string" and t.plainLyrics ~= "" then return M.parse_lrc(t.plainLyrics) end
    return nil
end

-- A song's lyric file beside it: the same name with `.lrc`.
function M.lrc_beside(path)
    if type(path) ~= "string" or path == "" then return nil end
    return (path:gsub("%.[%w]+$", "")) .. ".lrc"
end

-- The player's three sizes (the music player overhaul): a mini card under the bar's icon, the
-- panel, full screen. What an action does to the size it is in; nil is closed. `open` keeps the
-- size asked for; the bar's press closes from any size (it toggles the program).
local SIZES = {
    mini = { escape = false, outside = false, grow = "panel", full = "full", bar = false },
    panel = { escape = false, outside = false, grow = "panel", full = "full", bar = false },
    full = { escape = "panel", outside = "full", grow = "full", full = "panel", bar = false },
}
function M.size_after(size, action)
    if action == "open" then return size end
    local row = SIZES[size]
    if not row then return nil end
    local to = row[action]
    if to == nil then return size end
    return to or nil
end

return M
