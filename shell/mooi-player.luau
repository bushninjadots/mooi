-- mooi's music player (docs/PLAYER.md): the logic. mpd is read with mpc (its status, the song, the
-- queue) and listened to with `mpc idleloop`, so nothing is polled except the clock while a song
-- plays; another player is the media service's (MPRIS), with playerctl for what the service does
-- not do (seek, volume, shuffle, loop). The data folder is mooi's (bin/mooi links mooi-player to
-- it): palette.json paints it, the covers are cached in it.

local config = require("lib/config")
local ferro = require("lib/ferro")
local P = require("lib/player")

local HOME = tostring(sys.ask("env", "HOME") or "")
local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind) else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end
local folder = (function()
    local ok, f = pcall(sys.ask, "files.folder")
    return ok and type(f) == "string" and f ~= "" and f or (HOME .. "/.local/share/pleamar/mooi")
end)()
local COVERS = folder .. "/player-covers"

-- ── The shell's colours ──────────────────────────────────────
local settings = config.parse(read("settings.json"), json.decode)
local palette = read("palette.json", "json")
local tint = nil -- the cover's palette while player.colours is "cover" (Matugen roles)
local function paint()
    local out
    if tint then out = ferro.resolve("wallpaper", tint, settings.theme.signal, false, ferro.options(settings, palette and palette.mode)) end
    out = out or ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"] = c.r
        fact["fr_" .. role .. "_g"] = c.g
        fact["fr_" .. role .. "_b"] = c.b
    end
end
paint()
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)

-- Cover colours (`player.colours`): the cover through Matugen (a dry run, the shell's own scheme,
-- source colour and contrast), so each album relights the player. One run per cover, kept.
local tints = {}
local tint_busy = false
local cover_now = ""
local function retint()
    fact.cover_tint = settings.player.colours == "cover"
    local cover = cover_now
    if not fact.cover_tint or cover == nil or cover == "" then
        if tint then tint = nil; paint() end
        return
    end
    if tints[cover] ~= nil then tint = tints[cover] or nil; paint(); return end
    if tint_busy then return end
    tint_busy = true
    run("matugen", { "image", cover, "-m", "dark", "--dry-run", "-j", "hex",
                     "--type", "scheme-" .. tostring(settings.theme.scheme),
                     "--source-color-index", "0",
                     "--contrast", tostring(settings.theme.contrast) }, function(out, code)
        tint_busy = false
        local roles = nil
        if code == 0 then
            local ok, t = pcall(json.decode, out or "")
            if ok and type(t) == "table" and type(t.colors) == "table" then
                roles = {}
                for name, v in pairs(t.colors) do
                    if type(v) == "table" and type(v.dark) == "table" then roles[name] = v.dark.color end
                end
            end
        end
        tints[cover] = roles and { colours = roles } or false
        -- the cover may have changed while Matugen ran
        retint()
    end)
end

-- Every change of cover goes through here, so the colours can follow it.
local function set_cover(path)
    cover_now = path or ""
    text.t_cover = cover_now
    retint()
end

-- Where it hangs: under the bar's reserve, centred on the media module (the bar writes where).
do
    local bar = type(settings.bar) == "table" and settings.bar or {}
    fact.pl_top = (tonumber(bar.offset) or 0) + (tonumber(bar.height) or 30) + 7 + 10
    local anchor = read("player-anchor.json", "json")
    local x = type(anchor) == "table" and tonumber(anchor.x) or nil
    fact.pl_cx = (x and x > 0) and x or -1
end

local function say(s) text.t_status = s or "" end
-- Defined further down, reached for by the song and status code above them.
local lyrics_for   -- the lyrics for a song (local file, the cache, LRCLIB)
local est_sync     -- the lyrics' clock, set from each reading
local wave_for     -- a library song's waveform

-- ── mpd ──────────────────────────────────────────────────────
local music_dir = HOME .. "/Music"
run("cat", { HOME .. "/.config/mpd/mpd.conf" }, function(out, code)
    if code == 0 then music_dir = P.music_dir(out, HOME) or music_dir end
end)
run("mkdir", { "-p", COVERS })

local st = nil            -- the last status
local song = nil          -- the song mpd is on
local queue = {}
local qpage = 0
local QROWS = 9
local covers = {}         -- album key → cover file (or false: it has none)

local function show_queue()
    local pages = math.max(1, math.ceil(#queue / QROWS))
    qpage = math.max(0, math.min(qpage, pages - 1))
    local rows = {}
    for i = qpage * QROWS + 1, math.min(#queue, (qpage + 1) * QROWS) do
        local s = queue[i]
        rows[#rows + 1] = { pos = s.position - 1, title = s.title, artist = s.artist, time = P.clock(s.seconds),
                            current = st ~= nil and s.position - 1 == st.pos and st.state ~= "stopped", n = #rows }
    end
    model.queue = rows
    fact.q_count = #queue
    fact.q_page = qpage
    fact.q_pages = pages
end

local function refresh_queue()
    run("mpc", { "-f", P.SONG_FMT, "playlist" }, function(out, code)
        if code ~= 0 then queue = {}; show_queue(); return end
        queue = P.parse_songs(out)
        -- `mpc playlist` gives no %position% on every version: number them as they come
        for i, s in ipairs(queue) do if s.position < 1 then s.position = i end end
        show_queue()
    end)
end

-- The cover: the art embedded in the file, taken once per album into the data folder.
local function show_cover(s)
    if fact.src ~= "library" then return end
    if not s then set_cover(""); fact.cover_on = false; return end
    local key = P.hash((s.albumartist ~= "" and s.albumartist or s.artist) .. "\t" .. (s.album ~= "" and s.album or s.file))
    local known = covers[key]
    if known then set_cover(known); fact.cover_on = true; return end
    if known == false then set_cover(""); fact.cover_on = false; return end
    local dest = COVERS .. "/" .. key .. ".png"
    run("magick", { "identify", dest }, function(_, have)
        if have == 0 then covers[key] = dest; if song == s then set_cover(dest); fact.cover_on = true end; return end
        run("ffmpeg", { "-v", "error", "-y", "-i", P.path(music_dir, s.file), "-an", "-frames:v", "1",
                        "-vf", "scale=480:480:force_original_aspect_ratio=increase,crop=480:480", dest }, function(_, code)
            covers[key] = code == 0 and dest or false
            if song ~= s then return end
            set_cover(code == 0 and dest or "")
            fact.cover_on = code == 0
        end)
    end)
end

local function show_song(s)
    fact.has_song = s ~= nil
    if not s then
        text.t_title, text.t_artist, text.t_album, text.t_meta = "", "", "", ""
        show_cover(nil)
        return
    end
    text.t_title = s.title
    text.t_artist = s.artist
    text.t_album = s.album
    local ext = string.upper(s.file:match("%.([%w]+)$") or "")
    local bits = {}
    if ext ~= "" then bits[#bits + 1] = ext end
    if s.date ~= "" then bits[#bits + 1] = s.date:sub(1, 4) end
    if s.track ~= "" then bits[#bits + 1] = "TRACK " .. s.track end
    text.t_meta = table.concat(bits, "  ·  ")
    show_cover(s)
    if wave_for then wave_for(s) end
    if lyrics_for then lyrics_for(s.file, s.artist, s.title, s.album, s.seconds, P.path(music_dir, s.file)) end
end

local function refresh_song()
    run("mpc", { "-f", P.SONG_FMT, "current" }, function(out)
        local s = P.parse_songs(out)[1]
        if s and song and s.file == song.file then return end
        song = s
        if fact.src == "library" then show_song(s) end
        show_queue()
    end)
end

local viz   -- the visualiser follows the state; defined with cava, below
local mpd_mixer = false
-- The system's output, for a player without a mixer of its own (and for any other player).
local sys_vol = nil
pcall(sys.watch, "audio", function(a)
    if type(a) ~= "table" then return end
    sys_vol = math.floor((tonumber(a.volume) or 0) * 100 + 0.5)
    if not mpd_mixer then fact.vol = sys_vol; fact.vol_on = true end
end)
local function show_status()
    if fact.src ~= "library" then return end
    if not st then
        fact.mpd_on = false; fact.pstate = "stopped"; fact.progress = 0
        text.t_elapsed, text.t_total = "0:00", "0:00"
        return
    end
    fact.mpd_on = true
    fact.pstate = st.state
    fact.progress = st.total > 0 and st.elapsed / st.total or 0
    text.t_elapsed = P.clock(st.elapsed)
    text.t_total = P.clock(st.total)
    -- mpd's own mixer when it has one; otherwise the system's output (the audio service)
    mpd_mixer = st.volume >= 0
    if mpd_mixer then fact.vol = st.volume; fact.vol_on = true end
    fact.rnd, fact.rpt, fact.sgl = st.random, st["repeat"], st.single
    if est_sync then est_sync(st.elapsed, st.state == "playing") end
    if viz then viz() end
end

local function refresh_status(then_)
    run("mpc", { "status", P.STATUS_FMT }, function(out, code)
        local was = st
        st = code == 0 and P.parse_status(out) or nil
        show_status()
        if st and (not was or was.pos ~= st.pos or was.length ~= st.length or was.state == "stopped") then refresh_song() end
        if not st then song = nil; if fact.src == "library" then show_song(nil) end end
        if then_ then then_() end
    end)
end

-- The clock: while a song plays and the player is up, mpc is asked once a second.
local ticking = false
local function tick()
    if ticking then return end
    ticking = true
    local function step()
        if fact.pl_open == 0 or not st or st.state ~= "playing" or fact.src ~= "library" then ticking = false; return end
        refresh_status()
        after(1000, step)
    end
    after(1000, step)
end

-- mpd says when something changes: the player (a song, play/pause, seek), the mixer, the options,
-- the queue. If mpd is not there the loop ends, and it is tried again a little later.
local idle = nil
local function listen_mpd()
    if idle then return end
    local mine
    mine = spawn("mpc", { "idleloop", "player", "mixer", "options", "playlist" }, function(line)
        if idle ~= mine then return end
        if line:find("playlist", 1, true) then refresh_queue() end
        refresh_status(function() if st and st.state == "playing" then tick() end end)
    end, function()
        if idle ~= mine then return end
        idle = nil
        if fact.pl_open ~= 0 then after(3000, listen_mpd) end
    end)
    idle = mine
end

local function mpc(args, done)
    run("mpc", args, function(out, code)
        if code ~= 0 then say("MPD DID NOT ANSWER") end
        refresh_status(function() if st and st.state == "playing" then tick() end end)
        if done then done(out, code) end
    end)
end

-- ── Another player (MPRIS) ────────────────────────────────────
local remote = nil
local remote_at = 0
local function show_remote()
    if fact.src ~= "remote" then return end
    local m = remote
    fact.has_song = m ~= nil and m.title ~= ""
    if not fact.has_song then show_song(nil); fact.pstate = "stopped"; return end
    text.t_title = m.title
    text.t_artist = m.artist or ""
    text.t_album = m.album or ""
    text.t_meta = string.upper(m.player or "")
    local pos = (tonumber(m.position) or 0)
    if m.playing then pos = pos + (os.time() - remote_at) * (tonumber(m.rate) or 1) end
    local len = tonumber(m.length) or 0
    fact.pstate = m.playing and "playing" or "paused"
    if viz then viz() end
    fact.progress = len > 0 and math.min(1, pos / len) or 0
    text.t_elapsed, text.t_total = P.clock(pos), P.clock(len)
    if est_sync then est_sync(pos, m.playing == true) end
    if lyrics_for then lyrics_for("remote:" .. tostring(m.artist) .. "\t" .. tostring(m.title), tostring(m.artist or ""), tostring(m.title or ""), tostring(m.album or ""), len, nil) end
    local art = type(m.art) == "string" and m.art or ""
    local path = art:match("^file://(.*)$")
    if path then
        set_cover((path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))); fact.cover_on = true
    elseif art:match("^https?://") then
        local dest = COVERS .. "/remote-" .. P.hash(art) .. ".img"
        run("curl", { "-fsSL", "--max-time", "8", "-o", dest, art }, function(_, code)
            if code == 0 and remote and remote.art == art then set_cover(dest); fact.cover_on = true end
        end)
    else
        set_cover(""); fact.cover_on = false
    end
end
pcall(sys.watch, "media", function(m)
    remote = (type(m) == "table" and type(m.title) == "string" and m.title ~= "" and m.player ~= "mpd") and m or nil
    remote_at = os.time()
    fact.has_remote = remote ~= nil
    text.t_remote = remote and string.upper(remote.player or "") or ""
    show_remote()
end)

-- ── The visualiser: cava while something plays and the player is up ──
local CAVA = "cava-player.conf"
pcall(sys.call, "files.write", CAVA, table.concat({
    "[general]", "bars = 24", "framerate = 30",
    "[input]", "method = pipewire",
    "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
    "ascii_max_range = 1000", "bar_delimiter = 59", "frame_delimiter = 10",
    "[smoothing]", "noise_reduction = 66", "" }, "\n"))
local cava, sent = nil, {}
local function hush()
    if cava then kill(cava, "term"); cava = nil end
    for i = 0, 23 do fact["nv" .. i] = 0.03; sent[i] = 0.03 end
end
local function listen_cava()
    if cava then return end
    local mine
    mine = spawn("cava", { "-p", folder .. "/" .. CAVA }, function(line)
        if cava ~= mine then return end
        local i = 0
        for v in line:gmatch("(%d+);") do
            if i > 23 then break end
            local x = math.min(1, (tonumber(v) or 0) / 1000)
            if math.abs(x - (sent[i] or 0)) > 0.02 then fact["nv" .. i] = x; sent[i] = x end
            i = i + 1
        end
    end, function() if cava == mine then cava = nil end end)
    cava = mine
end
function viz()
    if fact.pl_open ~= 0 and fact.pstate == "playing" then listen_cava() else hush() end
end

-- ── The hands ────────────────────────────────────────────────
local function on_library() return fact.src == "library" end
local function pctl(args) run("playerctl", args, function(_, code) if code ~= 0 then say("THAT PLAYER CANNOT DO THAT") end end) end

on("pl_toggle", function()
    if on_library() then mpc({ "toggle" }) else pcall(sys.call, "media.toggle") end
end)
on("pl_next", function() if on_library() then mpc({ "next" }) else pcall(sys.call, "media.next") end end)
on("pl_prev", function() if on_library() then mpc({ "prev" }) else pcall(sys.call, "media.previous") end end)
-- 0 … 1000 a fraction of the song; -5/-6 five seconds back/on, -7/-8 thirty
on("pl_seek", function(v)
    v = math.floor(tonumber(v) or 0)
    local rel = ({ [-5] = -5, [-6] = 5, [-7] = -30, [-8] = 30 })[v]
    if on_library() then
        if not st or st.state == "stopped" then return end
        if rel then mpc({ "seek", (rel > 0 and "+" or "") .. tostring(rel) })
        else mpc({ "seek", string.format("%.1f%%", math.max(0, math.min(1000, v)) / 10) }) end
    elseif remote then
        local len = tonumber(remote.length) or 0
        if rel then pctl({ "position", tostring(math.abs(rel)) .. (rel > 0 and "+" or "-") })
        elseif len > 0 then pctl({ "position", tostring(math.floor(len * v / 1000)) }) end
    end
end)
on("pl_vol", function(v)
    v = math.max(0, math.min(100, math.floor(tonumber(v) or 0)))
    fact.vol = v
    if on_library() and mpd_mixer then mpc({ "volume", tostring(v) })
    else pcall(sys.call, "audio.volume", v / 100) end
end)
on("pl_rnd", function() if on_library() then mpc({ "random" }) else pctl({ "shuffle", "Toggle" }) end end)
on("pl_rpt", function() if on_library() then mpc({ "repeat" }) else pctl({ "loop", "Playlist" }) end end)
on("pl_sgl", function() if on_library() then mpc({ "single" }) end end)
on("pl_play", function(v) if on_library() then mpc({ "play", tostring(math.floor(tonumber(v) or 0) + 1) }) end end)
on("pl_del", function(v) if on_library() then mpc({ "del", tostring(math.floor(tonumber(v) or 0) + 1) }, refresh_queue) end end)
on("pl_clear", function() if on_library() then mpc({ "clear" }, refresh_queue) end end)
on("pl_qpage", function(d) qpage = qpage + ((tonumber(d) or 0) > 0 and 1 or -1); show_queue() end)

-- ── The library (mpd) ────────────────────────────────────────
-- Artists (by their album artist) → their albums → the album's songs, and a search over every
-- song. The artists' list is read once a session; the rest when it is opened. A row's ▶ plays it
-- now (the queue becomes it), its + adds it to the queue, a press on it goes into it.
local LROWS = 9
local lib = { level = 0, artist = nil, album = nil, page = 0, rows = {}, query = "" }
local artists = nil

local function show_lib()
    local list = lib.rows
    local pages = math.max(1, math.ceil(#list / LROWS))
    lib.page = math.max(0, math.min(lib.page, pages - 1))
    local rows = {}
    for i = lib.page * LROWS + 1, math.min(#list, (lib.page + 1) * LROWS) do
        local r = list[i]
        rows[#rows + 1] = { name = r.name, sub = r.sub or "", n = #rows, k = i, song = r.file ~= nil }
    end
    model.librows = rows
    fact.lib_count = #list
    fact.lib_page = lib.page
    fact.lib_pages = pages
    fact.lib_level = lib.level
    text.lib_where = lib.level == 0 and "ARTISTS" or lib.level == 1 and string.upper(lib.artist or "")
        or lib.level == 2 and string.upper((lib.album or "") .. "  ·  " .. (lib.artist or "")) or ("SEARCH · " .. string.upper(lib.query))
end

local function open_artists()
    lib.level, lib.page = 0, 0
    local function fill()
        lib.rows = {}
        for _, a in ipairs(artists or {}) do lib.rows[#lib.rows + 1] = { name = a } end
        show_lib()
    end
    if artists then fill(); return end
    text.lib_where = "READING THE LIBRARY…"
    run("mpc", { "list", "albumartist" }, function(out, code)
        artists = code == 0 and P.parse_names(out) or {}
        if lib.level == 0 then fill() end
    end)
end
local function open_artist(a)
    lib.level, lib.artist, lib.page = 1, a, 0
    run("mpc", { "list", "album", "albumartist", a }, function(out)
        lib.rows = {}
        for _, al in ipairs(P.parse_names(out)) do lib.rows[#lib.rows + 1] = { name = al, sub = a } end
        show_lib()
    end)
end
local function open_album(a, al)
    lib.level, lib.artist, lib.album, lib.page = 2, a, al, 0
    run("mpc", { "-f", P.SONG_FMT, "find", "albumartist", a, "album", al }, function(out)
        lib.rows = {}
        local songs = P.parse_songs(out)
        table.sort(songs, function(x, y) return (tonumber(x.track:match("%d+")) or 0) < (tonumber(y.track:match("%d+")) or 0) end)
        for _, sg in ipairs(songs) do
            lib.rows[#lib.rows + 1] = { name = sg.title, sub = (sg.track ~= "" and (sg.track .. "  ·  ") or "") .. P.clock(sg.seconds), file = sg.file }
        end
        show_lib()
    end)
end
local function search(q)
    lib.query = q
    if q == "" then open_artists(); return end
    lib.level, lib.page = 3, 0
    run("mpc", { "-f", P.SONG_FMT, "search", "any", q }, function(out)
        if lib.query ~= q then return end
        lib.rows = {}
        for _, sg in ipairs(P.parse_songs(out)) do
            if #lib.rows >= 200 then break end
            lib.rows[#lib.rows + 1] = { name = sg.title, sub = sg.artist .. "  ·  " .. sg.album, file = sg.file }
        end
        show_lib()
    end)
end

-- What a row is, as mpc's words: a song is its file; an album or an artist, a find.
local function row_find(r)
    if r.file then return nil, r.file end
    if lib.level == 0 then return { "albumartist", r.name } end
    if lib.level == 1 then return { "albumartist", lib.artist, "album", r.name } end
end
local function add_row(r, play_now)
    local find, file = row_find(r)
    local function go()
        if find then
            local args = { "findadd" }
            for _, a in ipairs(find) do args[#args + 1] = a end
            mpc(args, function() refresh_queue(); if play_now then mpc({ "play" }) end end)
        elseif file then
            mpc({ "add", file }, function()
                refresh_queue()
                if play_now then mpc({ "play" }) end
            end)
        end
    end
    if play_now then mpc({ "clear" }, go) else go() end
    say(play_now and "PLAYING · " .. string.upper(r.name) or "ADDED · " .. string.upper(r.name))
end

on("lib_open", function(v)
    local r = lib.rows[math.floor(tonumber(v) or 0)]
    if not r then return end
    if lib.level == 0 then open_artist(r.name)
    elseif lib.level == 1 then open_album(lib.artist, r.name)
    else add_row(r, true) end
end)
on("lib_play", function(v) local r = lib.rows[math.floor(tonumber(v) or 0)]; if r then add_row(r, true) end end)
on("lib_add", function(v) local r = lib.rows[math.floor(tonumber(v) or 0)]; if r then add_row(r, false) end end)
on("lib_back", function()
    if lib.level == 2 and lib.artist then open_artist(lib.artist)
    elseif lib.level == 3 then text.lib_query = ""; lib.query = ""; open_artists()
    else open_artists() end
end)
on("lib_page", function(d) lib.page = lib.page + ((tonumber(d) or 0) > 0 and 1 or -1); show_lib() end)
local search_gen = 0
on("text:lib_query", function(v)
    search_gen = search_gen + 1
    local g = search_gen
    after(250, function() if g == search_gen then search(tostring(v or "")) end end)
end)
on("pl_pane", function(v)
    local n = math.floor(tonumber(v) or 0)
    fact.pane = n == 1 and "library" or n == 2 and "lyrics" or "queue"
    if fact.pane == "library" and not artists then open_artists() end
end)

-- ── The waveform: a picture of the whole song, made once by ffmpeg and kept by the file ──
local WAVES = folder .. "/player-waves"
run("mkdir", { "-p", WAVES })
local wave_file = nil
wave_for = function(s)
    text.t_wave = ""; fact.wave_on = false
    if not s or fact.src ~= "library" then return end
    local dest = WAVES .. "/" .. P.hash(s.file) .. ".png"
    wave_file = s.file
    run("magick", { "identify", dest }, function(_, have)
        if have == 0 then if wave_file == s.file then text.t_wave = dest; fact.wave_on = true end; return end
        run("ffmpeg", { "-v", "error", "-y", "-i", P.path(music_dir, s.file), "-filter_complex",
                        "aformat=channel_layouts=mono,showwavespic=s=720x96:colors=white:scale=sqrt:draw=full",
                        "-frames:v", "1", dest }, function(_, code)
            if code == 0 and wave_file == s.file then text.t_wave = dest; fact.wave_on = true end
        end)
    end)
end

-- Full screen (F): the same player, the record large, the lyrics beside it.
on("pl_full", function() fact.full = not fact.full end)

-- ── Lyrics ───────────────────────────────────────────────────
-- A `.lrc` beside the song first, then LRCLIB (once: the answer, even "none", is kept in the data
-- folder by the song). Synced lines follow the song: the logic carries the time on between mpd's
-- readings in quarter seconds, and the lit line moves with it.
local LYR = folder .. "/player-lyrics"
run("mkdir", { "-p", LYR })
local lyr = { key = nil, data = nil, at = -1 }
local est = { t = 0, playing = false }
local LYR_ROWS = 9
est_sync = function(t, playing) est.t = tonumber(t) or 0; est.playing = playing end

local function show_lyrics()
    local d = lyr.data
    fact.lyr_on = d ~= nil and #d.lines > 0
    fact.lyr_synced = d ~= nil and d.synced == true
    local rows = {}
    if d and #d.lines > 0 then
        local cur = d.synced and P.lyric_at(d, est.t) or 0
        lyr.at = cur
        -- the lit line sits third from the top, the coming ones under it
        local first = d.synced and math.max(1, cur - 2) or math.max(1, lyr.scroll or 1)
        for i = first, math.min(#d.lines, first + LYR_ROWS - 1) do
            local l = d.lines[i]
            rows[#rows + 1] = { text = l.text ~= "" and l.text or "♪", cur = i == cur, dist = math.abs(i - math.max(cur, 1)),
                                t = math.floor(l.t * 10), n = #rows }
        end
    end
    model.lyr = rows
end

function lyrics_for(key, artist, title, album, seconds, path)
    if lyr.key == key then return end
    lyr.key, lyr.data, lyr.scroll = key, nil, 1
    text.lyr_note = "LOOKING FOR THE LYRICS…"
    show_lyrics()
    local cache = "player-lyrics/" .. P.hash(key) .. ".lrc"
    local function got(raw, source)
        if lyr.key ~= key then return end
        if raw == "none" then lyr.data = nil; text.lyr_note = "NO LYRICS FOUND FOR THIS SONG"
        elseif raw == "instrumental" then lyr.data = nil; text.lyr_note = "INSTRUMENTAL"
        else lyr.data = P.parse_lrc(raw); text.lyr_note = source end
        show_lyrics()
    end
    local function ask_lrclib()
        if artist == "" or title == "" then got("none", ""); return end
        run("curl", { "-fsSL", "--max-time", "10", "-H", "User-Agent: mooi (https://github.com/bushninjadots/mooi)",
                      P.lrclib_url(artist, title, album, seconds) }, function(out, code)
            local ans = nil
            if code == 0 then
                local ok, t = pcall(json.decode, out or "")
                ans = ok and P.from_lrclib(t) or nil
                if ok and type(t) == "table" then
                    local keep = t.instrumental == true and "instrumental" or (t.syncedLyrics ~= nil and t.syncedLyrics ~= json.null and t.syncedLyrics)
                        or (t.plainLyrics ~= nil and t.plainLyrics ~= json.null and t.plainLyrics) or "none"
                    if type(keep) ~= "string" then keep = "none" end
                    pcall(sys.call, "files.write", cache, keep)
                    got(keep, "LYRICS · LRCLIB")
                    return
                end
            end
            -- 404 is LRCLIB's "not known": remembered, so the song is not asked about again
            if code == 22 then pcall(sys.call, "files.write", cache, "none") end
            got(ans and "" or "none", "")
        end)
    end
    local cached = read(cache)
    if type(cached) == "string" and cached ~= "" then got(cached, "LYRICS · SAVED"); return end
    local beside = P.lrc_beside(path)
    if beside then
        run("cat", { beside }, function(out, code)
            if code == 0 and out and out ~= "" then got(out, "LYRICS · BESIDE THE SONG") else ask_lrclib() end
        end)
    else
        ask_lrclib()
    end
end

-- the quarter-second clock, only while there are lyrics to follow
every(250, function()
    if fact.pl_open == 0 or not lyr.data or not lyr.data.synced then return end
    if est.playing then est.t = est.t + 0.25 end
    if P.lyric_at(lyr.data, est.t) ~= lyr.at then show_lyrics() end
end)
on("lyr_seek", function(v)
    local t = (tonumber(v) or 0) / 10
    if fact.src == "library" then mpc({ "seek", P.clock(t) }) else run("playerctl", { "position", tostring(t) }) end
    est.t = t
    show_lyrics()
end)
on("lyr_scroll", function(d)
    if not lyr.data or lyr.data.synced then return end
    lyr.scroll = math.max(1, math.min(#lyr.data.lines, (lyr.scroll or 1) + ((tonumber(d) or 0) > 0 and -3 or 3)))
    show_lyrics()
end)

local function set_source(src)
    fact.src = src
    if src == "library" then show_song(song); show_status(); show_queue(); tick()
    else show_remote() end
    viz()
end
on("pl_src", function(v) set_source(tonumber(v) == 1 and "remote" or "library") end)

on("pl_tint", function()
    local fresh = config.parse(read("settings.json"), json.decode)
    fresh.player.colours = fresh.player.colours == "cover" and "shell" or "cover"
    if tostring(sys.ask("env", "MOOI_SAFE") or "") ~= "1" then
        if not pcall(sys.call, "files.write", "settings.json", fresh) then say("COULD NOT SAVE THE SETTING"); return end
    end
    settings.player = fresh.player
    retint()
end)

on("pl_close", function()
    if fact.pl_open == 0 then return end
    fact.pl_open = 0
    hush()
    if idle then kill(idle, "term"); idle = nil end
    after(260, function() run("pleamar", { "--say", "mooi-player", "quit" }) end)
end)

-- ── Up ───────────────────────────────────────────────────────
-- It opens on the library; if mpd is idle while another player plays, it opens on that one.
fact.pl_open = 1
refresh_status(function()
    refresh_queue()
    if (not st or st.state ~= "playing") and remote and remote.playing then set_source("remote")
    else set_source("library") end
    if st and st.state == "playing" then tick() end
end)
listen_mpd()
