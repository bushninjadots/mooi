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
-- `offset` (seconds, the song's own nudge) moves the lines earlier (+) or later (−).
function M.lyric_at(lyrics, t, offset)
    if type(lyrics) ~= "table" or not lyrics.synced then return 0 end
    local now = (tonumber(t) or 0) + (tonumber(offset) or 0)
    local at = 0
    for i, l in ipairs(lyrics.lines) do
        if l.t <= now + 0.05 then at = i else break end
    end
    return at
end
-- The lines either side of the one being sung, as text ("" where there is none): what a widget
-- shows. Unsynced or missing lyrics give three empty lines.
function M.lyric_lines(lyrics, t, offset)
    local at = M.lyric_at(lyrics, t, offset)
    if at == 0 then return "", "", "" end
    local function line(i) local l = lyrics.lines[i]; return l and l.text or "" end
    return line(at - 1), line(at), line(at + 1)
end
-- A nudge kept in half seconds, at most ten either way.
function M.clamp_offset(x)
    local v = math.floor((tonumber(x) or 0) * 2 + 0.5) / 2
    return math.max(-10, math.min(10, v))
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

-- ── The library (the music player overhaul) ──────────────────
-- One `mpc listall` row per song, every field the library groups and sorts by.
M.LIB_FIELDS = { "albumartist", "artist", "album", "date", "genre", "title", "time", "track", "file" }
M.LIB_FMT = "%albumartist%\t%artist%\t%album%\t%date%\t%genre%\t%title%\t%time%\t%track%\t%file%"

local function present(s) return type(s) == "string" and s ~= "" end
-- Albums from song rows, in the order they are first met: by album artist (else the artist, else
-- "Unknown artist") and album (else "Unknown album"). Each keeps its year, its song count and its
-- first song (whose file carries the cover).
function M.albums(rows)
    local out, at = {}, {}
    for _, r in ipairs(rows or {}) do
        local artist = present(r.albumartist) and r.albumartist or (present(r.artist) and r.artist or "Unknown artist")
        local album = present(r.album) and r.album or "Unknown album"
        local key = artist .. "\t" .. album
        local a = at[key]
        if not a then
            a = { artist = artist, album = album, year = tostring(r.date or ""):sub(1, 4), n = 0, file = r.file }
            at[key] = a
            out[#out + 1] = a
        end
        a.n = a.n + 1
        if a.year == "" and present(r.date) then a.year = r.date:sub(1, 4) end
    end
    return out
end

-- A copy sorted by `key`: names ignore case and a leading "The"; years oldest first, undated last;
-- time by its seconds.
local function name_key(v) return (string.lower(tostring(v or "")):gsub("^the%s+", "")) end
function M.sort(list, key)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    local function cmp(a, b)
        if key == "year" then
            local ya, yb = tonumber(a.year), tonumber(b.year)
            if ya and yb then return ya < yb end
            if ya or yb then return ya ~= nil end
            return false
        elseif key == "time" then
            return (tonumber(a.seconds) or 0) < (tonumber(b.seconds) or 0)
        end
        local na, nb = name_key(a[key]), name_key(b[key])
        if (na == "") ~= (nb == "") then return nb == "" end   -- the nameless go last
        return na < nb
    end
    table.sort(out, cmp)
    return out
end

-- A song's second line in the library: the artist, the album and the year it has — or that it has none.
function M.song_line(r)
    local parts = {}
    if present(r.artist) then parts[#parts + 1] = r.artist end
    if present(r.album) then parts[#parts + 1] = r.album end
    if present(r.date) then parts[#parts + 1] = r.date:sub(1, 4) end
    return #parts > 0 and table.concat(parts, "  ·  ") or "No tags"
end

-- An album's songs in track order ("2/12" is 2); songs with no number after, every tie by path —
-- table.sort is not stable, so a comparator that cannot tell two apart must still order them.
function M.album_tracks(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    local function n(r) return tonumber(tostring(r.track or ""):match("%d+")) end
    table.sort(out, function(a, b)
        local na, nb = n(a), n(b)
        if na and nb and na ~= nb then return na < nb end
        if (na == nil) ~= (nb == nil) then return na ~= nil end
        return tostring(a.file or "") < tostring(b.file or "")
    end)
    return out
end

-- Where a song's cover is kept, at 64 or 256 px.
function M.cover_file(dir, file, size)
    return tostring(dir) .. "/" .. M.hash(file) .. "-" .. tostring(size) .. ".jpg"
end

-- A cover for an album with none: two tones of the palette chosen by the name, and its initials.
-- `a` is the ground the initials (engraved) sit on; `b` the stripe across it.
function M.cover_tones(name, roles)
    local ferro = require("lib/ferro")
    local h = tonumber(M.hash(name):sub(1, 4), 16) / 65535
    local a = ferro.mix(roles.well, roles.hull_raised, 0.3 + h * 0.5)
    local b = ferro.mix(roles.phos, roles.ember, h)
    local ini = ""
    -- the first letter of the first two words, whole (a UTF-8 letter is several bytes: a lone lead
    -- byte is not text); only ASCII is upper-cased, the rest is kept as written
    local count = 0
    for w in tostring(name or ""):gmatch("[%w\128-\255]+") do
        if count < 2 then
            local first = w:match("^[%z\1-\127\194-\244][\128-\191]*") or ""
            ini = ini .. (#first == 1 and string.upper(first) or first)
            count = count + 1
        end
    end
    return { a = a, b = b, initials = ini ~= "" and ini or "?" }
end

-- ── The views (the music player overhaul) ────────────────────
-- The file's audio, from ffmpeg's stream line ("Audio: flac, 44100 Hz, stereo, s16 (24 bit)"):
-- mpc cannot print mpd's own `audio` field. Float samples count as 32 bits.
function M.audio_from_ffmpeg(out)
    local line = tostring(out or ""):match("Audio:[^\n]*")
    if not line then return nil end
    local rate = tonumber(line:match("(%d+) Hz"))
    if not rate then return nil end
    local ch = line:match("Hz, ([^,]+)")
    local channels = (ch == "mono" and 1) or (ch == "stereo" and 2) or tonumber((ch or ""):match("^(%d+)")) or 2
    local bits = tonumber(line:match("%((%d+) bit%)")) or tonumber(line:match(", [su](%d+)")) or (line:match(", flt") and 32) or 16
    return { rate = rate, bits = bits, channels = channels }
end
-- The rack's line: the file's format, then what mpd says it is playing.
function M.audio_line(a, ext)
    local parts = { ext ~= "" and ext or nil }
    if a then
        parts[#parts + 1] = string.format("%g kHz", a.rate / 1000)
        parts[#parts + 1] = a.bits .. " bit"
        parts[#parts + 1] = a.channels == 1 and "mono" or (a.channels == 2 and "stereo" or (a.channels .. " ch"))
    end
    return table.concat(parts, " · ")
end
-- CUE: back to where the song was last carried to, if that is behind the needle; else its start.
function M.cue_point(last_seek, now)
    if last_seek and last_seek >= 0 and last_seek < now then return last_seek end
    return 0
end

-- ── Video (the music player overhaul) ────────────────────────
-- yt-dlp's search for the song's video; nil with no title (nothing to look for).
function M.video_query(artist, title)
    if not present(title) then return nil end
    return "ytsearch1:" .. (present(artist) and (artist .. " - ") or "") .. title .. " official video"
end
-- Whether VIDEO is offered: an mpd song with a title. The reason when not, for its label.
function M.video_allowed(src, song)
    if src ~= "library" then return false, "Video plays for your library's songs (mpd)" end
    if type(song) ~= "table" or not present(song.title) then return false, "Nothing playing" end
    return true, ""
end
-- Where mpd picks up when the video closes: as far as the video got, inside the song.
function M.resume_at(video_t, song_len)
    local t, len = tonumber(video_t) or 0, tonumber(song_len) or 0
    if t < 0 or t >= len then return 0 end
    return t
end

-- yt-dlp's `--newline` progress ("[download]  42.7% of …") as a number, or nil.
function M.video_progress(line)
    local pct = tostring(line or ""):match("^%[download%]%s+([%d.]+)%%")
    return pct and tonumber(pct) or nil
end
-- Where a song's video is kept once fetched (YouTube refuses mpv's own stream; yt-dlp fetches it).
function M.video_file(dir, artist, title)
    return tostring(dir) .. "/" .. M.hash(tostring(artist or "") .. "\t" .. tostring(title or "")) .. ".mp4"
end

return M
