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

-- Calm: nothing pointed at and no fade under way, so the surface can drop to a few frames a second.
local hovered, calm_at = {}, 0
local function unsettle()
    fact.wg_calm = false
    calm_at = os.time() + 2
end
every(1000, function()
    if fact.wg_calm or fact.editing or next(hovered) ~= nil or os.time() < calm_at then return end
    fact.wg_calm = true
end)

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
            gh = st == "hidden" or st == "marker",
        }
    end
    model.wg = rows
    for i = 0, W.MAX - 1 do
        local r = rows[i + 1]
        fact["op" .. i] = r and r.op or 0
    end
    unsettle()
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

-- ── The hands (calm until touched) ──
-- Pointed at: the hands come at once and stay 1.2 s after the pointer leaves.
local away_seq = {}
on("wg_hov", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, on_it = math.floor(v / 10), v % 10 == 1
    if k < 0 or k >= W.MAX then return end
    away_seq[k] = (away_seq[k] or 0) + 1
    if on_it then
        hovered[k] = true
        fact["hl" .. k] = 1
        unsettle()
    else
        hovered[k] = nil
        local mine = away_seq[k]
        after(1200, function() if away_seq[k] == mine then fact["hl" .. k] = 0; unsettle() end end)
    end
end)
on("wg_ctl", function(v)
    local c = math.floor(tonumber(v) or 0) % 10
    pcall(sys.call, ({ [0] = "media.previous", [1] = "media.toggle", [2] = "media.next" })[c] or "media.toggle")
end)
on("wg_seek", function(v)
    local f = (math.floor(tonumber(v) or 0) % 1000) / 999
    if np.len <= 0 then return end
    np.t = f * np.len
    run("playerctl", { "position", string.format("%.1f", np.t) })
    show_progress(); show_lyric()
end)
local volume = nil
pcall(sys.watch, "audio", function(a) if type(a) == "table" then volume = tonumber(a.volume) end end)
on("wg_vol", function(v)
    if not volume then return end
    for _, w in ipairs(doc.widgets) do
        if w.kind == "nowplaying" and W.find(doc, w.id) == math.floor((tonumber(v) or 0) / 10) + 1 then
            if (w.options or {}).scroll_volume == false then return end
        end
    end
    volume = math.max(0, math.min(1, volume + (math.floor(tonumber(v) or 0) % 10 == 1 and 0.05 or -0.05)))
    pcall(sys.call, "audio.volume", volume)
end)
on("wg_open", function() run("mooi", { "player" }) end)

-- ── Edit mode: carry, pull, choose, add (lib/widgets works it out; saved once per gesture) ──
local pending = nil      -- where the carried or pulled widget would settle: { k, x, y, w, h }
local function panel()
    local k = fact.wg_sel
    local w = doc.widgets[k + 1]
    if not w then fact.wg_sel = -1; return end
    fact.wg_px, fact.wg_py = W.panel_spot(w, 248, 286, room)
    local o = w.options or {}
    fact.wg_sk = w.kind == "visualiser" and 1 or 0
    fact.wg_sl = W.LAYOUT_INDEX[w.layout] or 0
    fact.wg_sm = W.MODE_INDEX[w.mode] or 0
    fact.wg_si = W.IDLE_INDEX[w.idle] or 1
    fact.wg_o3, fact.wg_o4, fact.wg_o5, fact.wg_o6 = o.lyrics ~= false, o.progress ~= false, o.plate == true, o.scroll_volume ~= false
    fact.wg_og = tonumber(o.glow) or 0
end
local function commit(d)
    doc = d
    save()
    publish()
    if fact.wg_sel >= 0 then panel() end
end
on("wg_edit", function(v)
    local on_it = math.floor(tonumber(v) or 0) == 1
    fact.editing = on_it
    if not on_it then fact.wg_sel, fact.wg_dk, fact.wg_rk = -1, -1, -1; pending = nil end
    publish()
end)
on("wg_pick", function(v)
    fact.wg_sel = math.floor(tonumber(v) or -1)
    panel()
end)
on("wg_drag", function(v)
    local k, gx, gy = W.unpack(v)
    local w = doc.widgets[k + 1]
    if not w then return end
    local x, y, ww, hh, g = W.snap(doc, k + 1, gx * W.GRID, gy * W.GRID, w.w, w.h, room)
    pending = { k = k, x = x, y = y, w = ww, h = hh }
    fact.wg_sx, fact.wg_sy, fact.wg_sw, fact.wg_sh = x, y, ww, hh
    fact.wg_gvx, fact.wg_ghy = g.vx or -1, g.hy or -1
end)
on("wg_size", function(v)
    local k, gw, gh = W.unpack(v)
    local w = doc.widgets[k + 1]
    if not w then return end
    local ww, hh = W.clamp_size(w, gw * W.GRID, gh * W.GRID)
    local r = W.clamp_rect({ x = w.x, y = w.y, w = ww, h = hh }, room)
    pending = { k = k, x = r.x, y = r.y, w = r.w, h = r.h }
    fact.wg_sx, fact.wg_sy, fact.wg_sw, fact.wg_sh = r.x, r.y, r.w, r.h
    fact.wg_gvx, fact.wg_ghy = -1, -1
end)
local function settle(v)
    local k = math.floor(tonumber(v) or -1)
    local p = pending
    pending = nil
    fact.wg_gvx, fact.wg_ghy = -1, -1
    if not p or p.k ~= k or not doc.widgets[k + 1] then return end
    fact.wg_sel = k
    commit(W.set_rect(doc, doc.widgets[k + 1].id, p.x, p.y, p.w, p.h, room))
end
on("wg_drop", settle)
on("wg_sized", settle)
on("wg_add", function(v)
    local d, id = W.add(doc, math.floor(tonumber(v) or 0) == 1 and "visualiser" or "nowplaying", room)
    if not id then return end
    fact.wg_sel = W.find(d, id) - 1
    commit(d)
end)
on("wg_opt", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, what, val = math.floor(v / 1000), math.floor((v % 1000) / 100), v % 100
    local w = doc.widgets[k + 1]
    if not w then return end
    local d = doc
    if what == 1 then
        if w.kind == "visualiser" then d = W.set_mode(doc, w.id, W.MODES[val + 1])
        else d = W.set_layout(doc, w.id, W.NP_LAYOUTS[val + 1], room) end
    elseif what == 2 then d = W.set_idle(doc, w.id, W.IDLES[val + 1])
    elseif what >= 3 and what <= 6 then
        d = W.set_option(doc, w.id, ({ [3] = "lyrics", [4] = "progress", [5] = "plate", [6] = "scroll_volume" })[what], val == 1)
    elseif what == 8 then d = W.set_option(doc, w.id, "glow", val / 10)
    elseif what == 9 and val == 1 then
        local id
        d, id = W.duplicate(doc, w.id, room)
        if id then fact.wg_sel = W.find(d, id) - 1 end
    elseif what == 9 and val == 2 then
        d = W.remove(doc, w.id)
        fact.wg_sel = -1
    end
    commit(d)
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
