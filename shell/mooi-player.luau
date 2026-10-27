-- mooi's music player (docs/PLAYER.md): the logic. mpd is read with mpc (its status, the song, the
-- queue) and listened to with `mpc idleloop`, so nothing is polled except the clock while a song
-- plays; another player is the media service's (MPRIS), with playerctl for what the service does
-- not do (seek, volume, shuffle, loop). The data folder is mooi's (bin/mooi links mooi-player to
-- it): palette.json paints it, the covers are cached in it.

local config = require("lib/config")
local ferro = require("lib/ferro")
local P = require("lib/player")
local VZ = require("lib/vizbands")

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
fact.cn_kind, fact.cn_scale = require("lib/style").corners(settings)   -- corners on every plate (look.corners)
local palette = read("palette.json", "json")
local tint = nil -- the cover's palette while player.colours is "cover" (Matugen roles)
local last_roles = nil   -- the palette as painted last (the library's generated covers take its tones)
local function paint()
    local out
    if tint then out = ferro.resolve("wallpaper", tint, settings.theme.signal, false, ferro.options(settings, palette and palette.mode)) end
    out = out or ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    last_roles = out
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"] = c.r
        fact["fr_" .. role .. "_g"] = c.g
        fact["fr_" .. role .. "_b"] = c.b
    end
end
paint()
local retint   -- below: the cover's colours, which a new mode re-reads
pcall(sys.watch, "files:palette.json", function()
    palette = read("palette.json", "json")
    paint()
    if retint then retint() end   -- a new mode re-reads the cover's scheme on its side
end)

-- Cover colours (`player.colours`): the cover through Matugen (a dry run, the shell's own scheme,
-- source colour and contrast), so each album relights the player. One run per cover, kept.
local tints = {}
local tint_busy = false
local cover_now = ""
function retint()
    fact.cover_tint = settings.player.colours == "cover"
    local cover = cover_now
    if not fact.cover_tint or cover == nil or cover == "" then
        if tint then tint = nil; paint() end
        return
    end
    -- one tint per cover and mode: the day takes the light side of its scheme
    local mode = (palette and palette.mode == "light") and "light" or "dark"
    local key = cover .. "\t" .. mode
    if tints[key] ~= nil then tint = tints[key] or nil; paint(); return end
    if tint_busy then return end
    tint_busy = true
    run("matugen", { "image", cover, "-m", mode, "--dry-run", "-j", "hex",
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
                    local side = type(v) == "table" and v[mode] or nil
                    if type(side) == "table" then roles[name] = side.color end
                end
            end
        end
        tints[key] = roles and { colours = roles, mode = mode } or false
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
    -- the bar's icon opens the mini card; `mooi player --panel` and the key, the panel
    fact.size = (type(anchor) == "table" and anchor.size == "mini") and "mini" or "panel"
end

local function say(s) text.t_status = s or "" end
-- Defined further down, reached for by the song and status code above them.
local lyrics_for   -- the lyrics for a song (local file, the cache, LRCLIB)
local est_sync     -- the lyrics' clock, set from each reading
local wave_for     -- a library song's waveform
local audio_for    -- a library song's format, for the rack

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
    if audio_for then audio_for(s) end
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
-- Reduced motion and "always" saving keep the visualisers still and cava off (as the desk does).
local motion = type(settings.motion) == "table" and settings.motion or {}
fact.viz_still = motion.reduced == true or motion.saver == "always"
function viz()
    if fact.pl_open ~= 0 and fact.pstate == "playing" and not fact.viz_still then listen_cava() else hush() end
end

-- ── The hands ────────────────────────────────────────────────
local video   -- the music video (shell/player/video.luau), made further down: the transport stops it
local function on_library() return fact.src == "library" end
local function pctl(args) run("playerctl", args, function(_, code) if code ~= 0 then say("THAT PLAYER CANNOT DO THAT") end end) end

on("pl_toggle", function()
    if fact.video_on then video.stop(); return end   -- the transport, while a video plays, is the way back to the music
    if on_library() then mpc({ "toggle" }) else pcall(sys.call, "media.toggle") end
end)
on("pl_next", function() if fact.video_on then video.stop(); return end; if on_library() then mpc({ "next" }) else pcall(sys.call, "media.next") end end)
on("pl_prev", function() if fact.video_on then video.stop(); return end; if on_library() then mpc({ "prev" }) else pcall(sys.call, "media.previous") end end)
-- 0 … 1000 a fraction of the song; -5/-6 five seconds back/on, -7/-8 thirty
local last_seek = nil   -- where the song was last carried to (the deck's CUE)
on("pl_seek", function(v)
    if fact.video_on then return end   -- the video has its own clock; mpd waits
    v = math.floor(tonumber(v) or 0)
    local rel = ({ [-5] = -5, [-6] = 5, [-7] = -30, [-8] = 30 })[v]
    if on_library() then
        if not st or st.state == "stopped" then return end
        if rel then mpc({ "seek", (rel > 0 and "+" or "") .. tostring(rel) })
        else
            last_seek = st.total * math.max(0, math.min(1000, v)) / 1000   -- CUE comes back here
            mpc({ "seek", string.format("%.1f%%", math.max(0, math.min(1000, v)) / 10) })
        end
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

local set_source   -- below: which side the player shows (the library turns to mpd when played from)
-- ── The library (mpd): shell/player/library.luau ─────────────
local library = require("player/library").new({
    mpc = mpc, refresh_queue = refresh_queue, say = say, home = HOME,
    music_dir = function() return music_dir end,
    roles = function() return last_roles or ferro.resolve("fixed", palette, "auto", false) end,
    group = settings.player.library, sort = settings.player.sort,
    use_library = function() if fact.src ~= "library" and set_source then set_source("library") end end,
    -- the grouping and sort are remembered (player.library, player.sort)
    remember = function(group, sort)
        if tostring(sys.ask("env", "MOOI_SAFE") or "") == "1" then return end
        local fresh = config.parse(read("settings.json"), json.decode)
        fresh.player.library, fresh.player.sort = group, sort
        pcall(sys.call, "files.write", "settings.json", fresh)
    end,
})
local function set_pane(v)
    local n = math.floor(tonumber(v) or 0)
    fact.pane = n == 1 and "library" or n == 2 and "lyrics" or n == 4 and "eq" or "queue"
    if fact.pane == "library" and not library.ready() then library.open() end
end
on("pl_pane", set_pane)

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
-- The three sizes (lib/player `size_after`): the scene's `cinema` is the library's "full".
local close_player   -- below, with the rest of leaving
local function size_now() return fact.size == "cinema" and "full" or tostring(fact.size) end
local function go_size(action)
    local to = P.size_after(size_now(), action)
    if to == nil then close_player(); return end
    fact.size = to == "full" and "cinema" or to
    -- grown from a card with nothing playing: the library is what there is to do
    if action == "grow" and not fact.has_song then set_pane(1) end
end
on("pl_full", function() go_size("full") end)
on("pl_size", function(v)
    local n = math.floor(tonumber(v) or 0)
    go_size(({ [-1] = "outside", [-2] = "escape", [1] = "grow", [2] = "full" })[n] or "open")
end)

-- ── The music video: shell/player/video.luau ──
video = require("player/video").new({ home = HOME, say = say, mpc = mpc, song = function() return song end, status = function() return st end,
    est = function(t, playing) if est_sync then est_sync(t, playing) end end })
fact.video_ok = settings.player.video

-- ── The equaliser: shell/player/eq.luau (EasyEffects underneath) ──
require("player/eq").new({ home = HOME, say = say, read = read, folder = folder })

-- ── Lyrics: shell/player/lyrics.luau ─────────────────────────
do
    local lyrics = require("player/lyrics")({ folder = folder, read = read, mpc = mpc })
    lyrics_for, est_sync = lyrics.lyrics_for, lyrics.est_sync
end

function set_source(src)
    fact.src = src
    if src == "library" then show_song(song); show_status(); show_queue(); tick()
    else show_remote() end
    viz()
end
on("pl_src", function(v) set_source(tonumber(v) == 1 and "remote" or "library") end)

-- Each place's visualiser: the setting's style, as the scene's index; a press on its chip turns it.
local VIZ_PLACES = { [0] = "viz_mini", [1] = "viz_deck", [2] = "viz_full", [3] = "viz_stage", [4] = "viz_rack" }
local function show_viz_styles()
    for _, key in pairs(VIZ_PLACES) do fact[key] = VZ.index(settings.player[key]) end
end
show_viz_styles()
on("viz_next", function(v)
    local key = VIZ_PLACES[math.floor(tonumber(v) or -1)]
    if not key then return end
    local fresh = config.parse(read("settings.json"), json.decode)
    fresh.player[key] = VZ.next(fresh.player[key])
    if tostring(sys.ask("env", "MOOI_SAFE") or "") ~= "1" then pcall(sys.call, "files.write", "settings.json", fresh) end
    settings.player = fresh.player
    show_viz_styles()
end)

-- The views: the deck, the stage, the rack (player.view, remembered).
local VIEWS = { [0] = "deck", [1] = "stage", [2] = "rack" }
fact.view = settings.player.view
on("pl_view", function(v)
    local want = VIEWS[math.floor(tonumber(v) or 0)] or "deck"
    fact.view = want
    if tostring(sys.ask("env", "MOOI_SAFE") or "") == "1" then return end
    local fresh = config.parse(read("settings.json"), json.decode)
    fresh.player.view = want
    settings.player = fresh.player
    pcall(sys.call, "files.write", "settings.json", fresh)
end)
-- CUE: back to where the song was last carried to, if that is behind the needle; else its start.
on("pl_cue", function()
    if not on_library() or not st or st.state == "stopped" then return end
    local t = P.cue_point(last_seek, st.elapsed)
    mpc({ "seek", P.clock(t) })
end)
-- The rack's line: the file's format, from ffmpeg's stream line (mpc cannot print mpd's).
local audio_file = nil
audio_for = function(s)
    text.t_audio = ""
    if not s or fact.src ~= "library" then return end
    audio_file = s.file
    local ext = string.upper(s.file:match("%.([%w]+)$") or "")
    -- `-i` alone prints the streams (after every tag, which can run long) on the error output
    run("ffmpeg", { "-hide_banner", "-i", P.path(music_dir, s.file) }, function(out)
        if audio_file ~= s.file then return end
        text.t_audio = P.audio_line(P.audio_from_ffmpeg(out), ext)
    end, { errors = true })
end

on("pl_tint", function()
    local fresh = config.parse(read("settings.json"), json.decode)
    fresh.player.colours = fresh.player.colours == "cover" and "shell" or "cover"
    if tostring(sys.ask("env", "MOOI_SAFE") or "") ~= "1" then
        if not pcall(sys.call, "files.write", "settings.json", fresh) then say("COULD NOT SAVE THE SETTING"); return end
    end
    settings.player = fresh.player
    retint()
end)

function close_player()
    if fact.pl_open == 0 then return end
    video.stop()
    fact.pl_open = 0
    hush()
    if idle then kill(idle, "term"); idle = nil end
    after(260, function() run("pleamar", { "--say", "mooi-player", "quit" }) end)
end
on("pl_close", close_player)

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
