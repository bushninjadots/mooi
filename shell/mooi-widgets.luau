-- The desktop widgets' logic (D137): widgets.json through lib/widgets into the scene's model, what
-- is playing (any player, through the media service), its lyrics (player/lyricfetch, the
-- player's own cache) and the bar's visualiser feed. The data folder is mooi's (bin/mooi links
-- mooi-widgets to it), so settings.json, palette.json and widgets.json are the shell's own.

local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")
local W = require("lib/widgets")
local P = require("lib/player")
local vizfeed = require("lib/vizfeed")
local coverart = require("lib/cover")

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end
local HOME = tostring(sys.ask("env", "HOME"))
local folder = (function()
    local ok, f = pcall(sys.ask, "files.folder")
    return ok and type(f) == "string" and f ~= "" and f or (HOME .. "/.local/share/pleamar/mooi")
end)()
local COVERS = folder .. "/player-covers"
local fetch = require("player/lyricfetch")({ read = read })

-- ── The shell's colours, corners and finish, as the board wears them ──
local settings = config.parse(read("settings.json"), json.decode)
local palette = read("palette.json", "json")
local function paint()
    fact.cn_kind, fact.cn_scale = style.corners(settings)
    local look = style.facts(settings)
    if look and look.st_glow then fact.st_glow = look.st_glow end
    local motion = type(settings.motion) == "table" and settings.motion or {}
    fact.viz_still = motion.reduced == true or motion.saver == "always"
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
end
paint()
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)
pcall(sys.watch, "files:settings.json", function() settings = config.parse(read("settings.json"), json.decode); paint() end)

-- ── The widgets ──
-- The room under the bar: the surface says how big it is once it is placed (`screen` is not known
-- while this file loads), so until then a 1080p screen under a 34 px bar.
local room = { w = 1920, h = 1046, top = 0 }
local doc, written = nil, nil
local playing = false

local function publish()
    local rows = {}
    for _, w in ipairs(doc.widgets) do
        local st = W.idle_state(w, playing)
        local o = w.options or {}
        rows[#rows + 1] = {
            kind = w.kind == "visualiser" and 1 or 0,
            lay = W.LAYOUT_INDEX[w.layout] or 0,
            mode = W.MODE_INDEX[w.mode] or 0,
            x = w.x, y = w.y, w = w.w, h = w.h, u = W.scale(w),
            idle = W.IDLE_INDEX[w.idle] or 1,
            st = ({ shown = 0, rest = 1, hidden = 2, marker = 3 })[st],
            op = ({ shown = 1, rest = 0.35, hidden = 0, marker = 0 })[st],
            glow = tonumber(o.glow) or 0, plate = o.plate == true,
            lyr = o.lyrics ~= false, prog = o.progress ~= false,
        }
    end
    model.wg = rows
end

local function load()
    local raw = read(W.FILE)
    local d, problems = W.parse(raw, json.decode, room)
    for _, p in ipairs(problems) do log("widgets · " .. p) end
    if d.bad then
        run("mv", { "-f", folder .. "/" .. W.FILE, folder .. "/" .. W.FILE .. ".bad" })
        log("widgets · widgets.json kept as widgets.json.bad; the defaults are shown")
    end
    doc = d
    publish()
end

-- Saved whole, at once: a temporary file moved over the real one.
local function save()
    local enc = W.encode(doc)
    written = enc
    pcall(sys.call, "files.write", W.FILE .. ".tmp", enc)
    run("mv", { "-f", folder .. "/" .. W.FILE .. ".tmp", folder .. "/" .. W.FILE })
end

load()
pcall(sys.watch, "files:" .. W.FILE, function()
    local raw = read(W.FILE)
    if raw == nil then return end
    local ok, t = pcall(json.decode, raw)
    if ok and written and W.same_doc(t, written) then return end
    load()
end)
-- packed as width · 4096 + height (under 2^24)
on("wg_room", function(v)
    v = math.floor(tonumber(v) or 0)
    local w, h = math.floor(v / 4096), v % 4096
    if w < 200 or h < 200 or (w == room.w and h == room.h) then return end
    room.w, room.h = w, h
    load()
end)

-- ── What is playing ──
local np = { key = nil, data = nil, t = 0, at = os.time(), rate = 1, len = 0, sung = nil }
local function set_cover(path)
    text.np_cover_path = path or ""
    fact.np_cover_on = path ~= nil and path ~= ""
end
local function show_lyric()
    local a, b, c = P.lyric_lines(np.data, np.t, 0)
    if b == np.sung then return end
    np.sung = b
    text.np_prev, text.np_line, text.np_next = a, b, c
    fact.np_sung = b ~= ""
    -- the new line fades in
    fact.np_line_in = 0
    after(40, function() fact.np_line_in = 1 end)
end
local function lyrics_for(m)
    local artist, title = tostring(m.artist or ""), tostring(m.title or "")
    local key = "remote:" .. artist .. "\t" .. title
    if key == np.key then return end
    np.key, np.data, np.sung = key, nil, nil
    show_lyric()
    if artist == "" or title == "" then return end
    local path = coverart.path(type(m.url) == "string" and m.url or "")
    fetch(key, artist, title, tostring(m.album or ""), np.len, path, function(raw, _)
        if np.key ~= key then return end
        if raw == "none" or raw == "instrumental" or raw == "" then np.data = nil
        else np.data = P.parse_lrc(raw) end
        show_lyric()
    end)
end
local function show_progress()
    fact.np_progress = np.len > 0 and math.min(1, np.t / np.len) or 0
    fact.np_arm_at = P.arm(fact.np_progress, playing and "playing" or (fact.np_has and "paused" or "stopped"))
end

pcall(sys.watch, "media", function(m)
    local has = type(m) == "table" and type(m.title) == "string" and m.title ~= ""
    local was = playing
    playing = has and m.playing == true
    fact.np_has, fact.np_playing = has, playing
    if not has then
        text.np_title, text.np_artist = "", ""
        np.key, np.data, np.len, np.t = nil, nil, 0, 0
        set_cover(nil)
    else
        text.np_title, text.np_artist = m.title, tostring(m.artist or "")
        np.t, np.at, np.rate = tonumber(m.position) or 0, os.time(), tonumber(m.rate) or 1
        np.len = tonumber(m.length) or 0
        lyrics_for(m)
        local art = type(m.art) == "string" and m.art or ""
        local path = coverart.path(art)
        if path then set_cover(path)
        elseif coverart.remote(art) then
            local dest = COVERS .. "/remote-" .. P.hash(art) .. ".img"
            run("curl", { "-fsSL", "--max-time", "8", "-o", dest, art }, function(_, code)
                if code == 0 then set_cover(dest) end
            end)
        else set_cover(nil) end
    end
    show_progress()
    show_lyric()
    if was ~= playing then publish() end
end)
-- the song's clock between the service's readings, in quarter seconds
every(250, function()
    if not playing then return end
    np.t = np.t + 0.25 * np.rate
    show_progress()
    if np.data and np.data.synced then show_lyric() end
end)

-- ── The visualiser's feed (the bar's one cava) ──
local function any_viz()
    for _, w in ipairs(doc.widgets) do if w.kind == "visualiser" then return true end end
    return false
end
local viz_seq, viz_at, last_beat = nil, 0, 0
local rings = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
local function hush() for i = 0, 15 do fact["vb" .. i] = 0.03 end; fact.np_beat = 0 end
local function take_viz()
    local ok, raw = pcall(sys.ask, "files.read", vizfeed.FILE)
    if not ok or type(raw) ~= "string" then return end
    local t = vizfeed.decode(raw)
    if not t or not vizfeed.newer(viz_seq, t.seq) then return end
    viz_seq, viz_at = t.seq, os.time()
    if not t.playing then hush(); return end
    local b = vizfeed.map(t.bands, 16)
    for i = 0, 15 do fact["vb" .. i] = b[i + 1] end
    local beat = (tonumber(t.beat) or 0) > 0.9 and last_beat <= 0.9
    last_beat = tonumber(t.beat) or 0
    if beat then
        fact.np_beat = 1
        after(60, function() fact.np_beat = 0 end)
        table.remove(rings, 1)
        rings[4] = { 0.02, math.min(1, 0.5 + (b[2] or 0)) }
    end
end
every(33, function()
    if not (playing and any_viz() and not fact.viz_still) then return end
    take_viz()
    for k = 1, 4 do
        local r = rings[k]
        if r[2] > 0.02 then
            r[1] = r[1] + 0.025; r[2] = r[2] * 0.96
            fact["rp_r" .. (k - 1)], fact["rp_a" .. (k - 1)] = math.min(1.2, r[1]), r[2]
        elseif fact["rp_a" .. (k - 1)] ~= 0 then fact["rp_a" .. (k - 1)] = 0 end
    end
end)
-- The bar runs the one cava and writes the feed for a few seconds after each ask (D118).
every(3000, function()
    if playing and any_viz() and not fact.viz_still then run("pleamar", { "--say", "mooi", "emit feed_want" }) end
end)
every(400, function()
    if viz_seq and not vizfeed.fresh(viz_at * 1000, os.time() * 1000) then viz_seq, viz_at = nil, 0; hush() end
end)
