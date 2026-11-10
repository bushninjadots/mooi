-- The Dynamic Pill as a living node (D226; docs/superpowers/specs/2026-11-09-dynamic-pill-node-design.md). The
-- logic: what is happening (the services, Signal Loom's feed, the bar's feed), what the node is now
-- (lib/node/state), where its body and parts go (lib/node/geometry, satellites), how it looks (lib/node/look, set
-- in its studio, D229), how it answers the pointer (lib/node/interaction) — written as facts for
-- shell/mooi-node.plm (tools/gen-node.py) to spring and draw.
-- Event-driven: one timer for the next thing that ends, none at rest.

local config = require("lib/config")
local ferro = require("lib/ferro")
local ST = require("lib/node/state")
local G = require("lib/node/geometry")
local LK = require("lib/node/look")
local TK = require("lib/node/timekit")
local PV = require("lib/node/privacy")
local CF = require("lib/node/clockfont")
local DV = require("lib/node/devices")
local CMD = require("lib/node/commands")
local HY = require("lib/hypr")
local MK = require("lib/node/mediakit")
local NT = require("lib/node/notices")
local CALC = require("lib/node/calc")
local UN = require("lib/node/units")
local MX = require("lib/node/mixer")
local LY = require("lib/node/lyrics")
local VF = require("lib/vizfeed")
local IX = require("lib/node/interaction")
local SAT = require("lib/node/satellites")
local WB = require("lib/wbelow")          -- the apps' ranking (Launch's grid's, D215)

local KIND = { rest = 0, media = 1, notice = 2, volume = 3, workspaces = 4, system = 5, launcher = 6, universe = 7, time = 8, done = 9, privacy = 10, battery = 10, player = 11 }
-- what a press, Super or another opening lets go of (`done` is never among them: it waits to be answered)
local HELD = { "system", "launcher", "universe", "time", "player" }
local SAT_KIND = { music = 1, rec = 2, battery = 3, network = 4, music_rec = 5, notice = 6, mic = 7, timer = 8, cam = 9 }

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind) else ok, v = pcall(sys.ask, "files.read", name) end
    if ok then return v end
end

N = {
    settings = config.parse(read("settings.json"), json.decode),
    scr = { w = 1920, h = 1080 },
    st = ST.new(), ix = IX.new(),
    media = { title = "", artist = "", playing = false, art = "", length = 0, position = 0 },
    ws = { active = 1, list = {} },
    vol = nil, bat = nil, charging = false, online = true,
    notices = {}, notice_seen = nil, feed = {},
    apps = {}, q = "", results = {}, sel = 0,
    pointer = nil, due = nil,
    clients = {},
}

local function cfg() local n = N.settings.node; return type(n) == "table" and n or {} end
local function on_for(kind) return cfg()[kind] ~= false end

-- ── its look (lib/node/look): node-look.json, or — before the studio ever saved one — the personality chosen in
-- Settings before D229 ──
local function look_now() return LK.normalise(read(LK.FILE, "json"), cfg().personality) end
N.look = look_now()
local function apply_look()
    for k, v in pairs(LK.facts(N.look)) do fact[k] = v end
    if N.clock_now then N.clock_now() end
end
apply_look()
-- written a moment after the last change (a slider dragged writes once, when it rests)
local save_gen = 0
local function save_look()
    save_gen = save_gen + 1
    local g = save_gen
    after(300, function()
        if g ~= save_gen then return end
        N.saving = true
        pcall(sys.call, "files.write", LK.FILE, json.encode(N.look))
    end)
end

-- the clock: a counter of our own in 50 ms steps (the way mooi-surface keeps its reveal's); it only draws when
-- something is due — the next event's end, or the pointer's next decision — so at rest nothing is done
local MS = 0
local function now() return MS end

-- ── the time tools' clock (D231): the wall's seconds, and this program's 50 ms steps within each one, so a timer
-- neither drifts with a late timer nor jumps a whole second ──
local wall_s, wall_ms0 = os.time(), 0
local function wall()
    local sec = os.time()
    if sec ~= wall_s then wall_s, wall_ms0 = sec, MS end
    return sec * 1000 + math.min(999, MS - wall_ms0)
end
local function local_date(sec) return os.date("*t", sec) end
local function local_time(d) return os.time(d) end
N.time = TK.normalise(read(TK.FILE, "json"))
local function save_time() pcall(sys.call, "files.write", TK.FILE, json.encode(N.time)) end
N.done = {}   -- what finished and waits to be answered, oldest first

-- ── the palette, as every program wearing Ferrolume paints it ──
local palette = read("palette.json", "json")
local function paint()
    local s = N.settings
    local out = ferro.resolve(s.theme.source, palette, s.theme.signal, false, ferro.options(s))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
end
paint()
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)

-- ── drawing what the node is ──
local render
local function schedule()
    -- what is due next: the next event that ends, or the pointer's next decision
    local t = ST.next_change(N.st, now())
    if N.pointer_due and (not t or N.pointer_due < t) then t = N.pointer_due end
    N.due = t
end
every(50, function()
    MS = MS + 50
    if N.pointer_due and MS >= N.pointer_due then N.pointer_due = nil; if N.pointer_step then N.pointer_step() end end
    if N.due and MS >= N.due then N.due = nil; render() end
end)


local function set_body(b, overshoot)
    local o = overshoot or 0
    fact.nd_tx, fact.nd_ty, fact.nd_tw, fact.nd_th, fact.nd_tr = b.x - b.w * o / 2, b.y, b.w * (1 + o), b.h, b.r
    if o > 0 then after(110, function() fact.nd_tx, fact.nd_tw = b.x, b.w end) end
end

local function show_media(b)
    local m = N.media
    text.nd_title = m.title ~= "" and m.title or "Nothing playing"
    text.nd_artist = m.artist
    fact.nd_playing = m.playing
    fact.nd_prog = (m.length > 0) and math.max(0, math.min(1, m.position / m.length)) or 0
end

-- D237: one card per app (its newest notice, and how many it has sent); each row remembers which notice it is
local function show_notices(b)
    local groups = NT.group(N.notice_list or N.notices)
    local cards = G.cards(b, math.min(N.look.cards, #groups), N.scr)
    local rows, idx = {}, {}
    local shown = 0
    for i, c in ipairs(cards) do
        local g = groups[i]
        local a1 = g.actions[1]
        rows[i] = { x = c.x, y = c.y, w = c.w, h = c.h, app = NT.label(g), title = g.title,
                    act = type(a1) == "string" and a1 or "", hasact = type(a1) == "string" and a1 ~= "" }
        idx[i] = g.idx
        shown = shown + g.count
    end
    N.notice_rows = idx
    model.nc = rows
    fact.nd_ncn = #rows
    fact.nd_more = math.max(0, #(N.notice_list or N.notices) - shown)
end

local function show_rail(b)
    local list = N.ws.list
    local stops = G.rail(b, #list)
    local rows = {}
    for i, w in ipairs(list) do
        rows[i] = { x = stops[i], n = tostring(w.id), on = w.id == N.ws.active, used = (tonumber(w.windows) or 1) > 0 }
        if w.id == N.ws.active then fact.nd_beadx = stops[i] end
    end
    model.rl = rows
end

local function show_system(b)
    local f = type(N.feed.resources) == "table" and N.feed.resources or {}
    -- the bar's feed gives the processor and the memory as fractions (0 … 1), the temperature in degrees
    local function pct(v) v = tonumber(v); if not v then return nil end; return v <= 1 and v * 100 or v end
    local cpu, mem = pct(f.cpu), pct(f.mem)
    local items = {
        { "CPU", cpu and (math.floor(cpu + 0.5) .. "%") or "—", (cpu or 0) > 85 },
        { "RAM", mem and (math.floor(mem + 0.5) .. "%") or "—", (mem or 0) > 90 },
        { "TEMP", f.temp and (math.floor(f.temp) .. "°") or "—", (tonumber(f.temp) or 0) > 85 },
        { "NET", N.online and "ON" or "OFF", not N.online },
    }
    if N.bat then
        items[#items + 1] = { "BAT", math.floor(N.bat + 0.5) .. "%" .. (N.charging and "+" or ""), DV.band(N.bat) == "critical" and not N.charging }
    end
    local sp = G.spokes(b, #items)
    local rows = {}
    for i, it in ipairs(items) do rows[i] = { x = sp[i].x, y = sp[i].y, label = it[1], value = it[2], hot = it[3] } end
    model.sy = rows
end

local function show_launcher(b)
    local rows = {}
    local places = G.results(b, #N.results)
    for i, a in ipairs(N.results) do
        local p = places[i]
        local name = tostring(a.name or a.id or "")
        local icon = (a.kind == "app" and type(a.icon) == "string") and a.icon or ""
        local letter = a.kind == "calc" and "=" or a.kind == "command" and "M" or a.kind == "window" and string.sub(tostring(a.app or name), 1, 1) or string.sub(name ~= "" and name or "?", 1, 1)
        local tag = CMD.TAG[a.kind] or ""
        if a.kind == "window" and a.workspace ~= "" then tag = "WINDOW · " .. a.workspace end
        rows[i] = { x = p.x, y = p.y, w = p.w, h = p.h, name = name, icon = icon, iconed = icon ~= "",
                    letter = string.upper(letter), tag = tag }
    end
    model.lr = rows
    fact.nd_sel = N.sel
end

-- the orbit is drawn by the scene from each workspace's place in the ring and a sprung turn (nd_rot); the turn
-- is a running count, so stepping past the last one carries on round instead of spinning back the long way
local function show_universe()
    local list = N.ws.list
    local rows = {}
    for i, w in ipairs(list) do
        local apps = {}
        for _, c in ipairs(N.clients) do
            if type(c.workspace) == "table" and c.workspace.id == w.id and #apps < 4 then apps[#apps + 1] = tostring(c.class or "") end
        end
        rows[i] = { i = i - 1, n = tostring(w.id), apps = table.concat(apps, " · "), id = w.id }
    end
    model.un = rows
    fact.nd_un_n = math.max(1, #list)
    fact.nd_rott = N.rot or 0
end
local function ws_index(id)
    for i, w in ipairs(N.ws.list) do if w.id == id then return i - 1 end end
    return 0
end
local function turn(dir)
    local n = #N.ws.list
    if n == 0 then return end
    N.rot = (N.rot or 0) + dir
    N.uni_at = N.ws.list[(N.rot % n) + 1].id
end

-- the panel: the mode on stage, the others on the rail; each mode's own controls
local MODE_NAMES = { timer = "TIMER", stopwatch = "STOPWATCH", focus = "FOCUS", alarm = "ALARM" }
local CONTROLS = {
    timer = { { "+1M", 21 }, { "+5M", 22 }, { "+10M", 23 }, { "-1M", 24 } },
    stopwatch = { { "LAP", 12 } },
    focus = { { "SKIP", 12 } },
    alarm = { { "H+", 31 }, { "H-", 32 }, { "M+", 33 }, { "M-", 34 } },
}
-- the clock seed (D241): the time's lit cells, written when the minute turns (looked at every five seconds)
local clock_str
every(5000, function()
    if N.look.seed ~= "clock" then clock_str = nil; return end
    local s = os.date("%H:%M")
    if s ~= clock_str then clock_str = s; model.ck = CF.cells(s) end
end)
N.clock_now = function() clock_str = nil; if N.look.seed == "clock" then clock_str = os.date("%H:%M"); model.ck = CF.cells(clock_str) end end
N.clock_now()
-- the readout as the matrix's lit cells, written only when what it says changes
local px_str
local function pixels(str)
    if str == px_str then return end
    px_str = str
    model.px = CF.cells(str)
    fact.nd_pxw = CF.width(str)
end
local function show_time()
    local t, now = N.time, wall()
    local r = TK.readouts(t, now)
    local mode = t.mode
    local me = r[mode]
    fact.nd_tmm = (LK.index_of(TK.MODES, mode) or 1) - 1
    text.nd_tmr = me.value
    pixels(me.value)
    fact.nd_tmp = me.frac
    if mode == "timer" then
        text.nd_tms = me.on and "RUNNING" or me.paused and "PAUSED" or ("SET " .. TK.format(t.timer.set))
        text.nd_tmgl = me.on and "PAUSE" or me.paused and "RESUME" or "START"
        text.nd_tm2l = "RESET"
    elseif mode == "stopwatch" then
        local laps = t.stopwatch.laps
        text.nd_tms = #laps > 0 and ("LAP " .. #laps .. "  ·  " .. TK.format(laps[1] - (laps[2] or 0), true)) or (me.on and "RUNNING" or "READY")
        text.nd_tmgl = me.on and "STOP" or me.paused and "GO ON" or "START"
        text.nd_tm2l = "RESET"
    elseif mode == "focus" then
        text.nd_tms = me.phase .. "  ·  ROUND " .. me.round .. " OF " .. TK.ROUNDS .. (me.paused and "  ·  PAUSED" or "")
        text.nd_tmgl = me.on and "PAUSE" or (me.paused and "RESUME" or "START")
        text.nd_tm2l = "STOP"
    else
        text.nd_tms = me.on and ("RINGS IN " .. TK.format_left((t.alarm.next or now) - now)) or "OFF"
        text.nd_tmgl = me.on and "TURN OFF" or "SET"
        text.nd_tm2l = "CLOSE"
    end
    local tc = {}
    for i, c in ipairs(CONTROLS[mode]) do tc[i] = { label = c[1], code = c[2] } end
    model.tc = tc
    local rail = {}
    for i, m in ipairs(TK.MODES) do
        if m ~= mode then rail[#rail + 1] = { label = MODE_NAMES[m], value = r[m].value, on = r[m].on, m = i - 1 } end
    end
    model.tr = rail
end
-- the seed's capsule while something runs (a value written only when it changes)
local cap_text, cap_mode
local function show_capsule(c)
    fact.nd_cap = c ~= nil
    if not c then cap_text, cap_mode = nil, nil; return end
    if c.text ~= cap_text then cap_text = c.text; text.nd_capt = c.text end
    if c.mode ~= cap_mode then cap_mode = c.mode; text.nd_capm = MODE_NAMES[c.mode] end
    fact.nd_capf = c.frac
    fact.nd_capu = c.urgent
end
local function show_done()
    local d = N.done[1]
    if not d then return end
    text.nd_dnt = d.title
    text.nd_dnd = d.detail .. (#N.done > 1 and ("  ·  +" .. (#N.done - 1) .. " MORE") or "")
end

local function show_satellites(b, kind)
    if not on_for("satellites") then model.sa = {}; return end
    local f = N.feed
    local list = SAT.collect({ playing = N.media.playing and on_for("media"), media_open = kind == "media", title = N.media.title,
                               recording = f.recording == true, notices = on_for("notices") and #N.notices or 0,
                               battery = N.bat, charging = N.charging, online = N.online,
                               mic = N.mic_on, cam = N.cam_on })
    local rows = {}
    for i, s in ipairs(SAT.layout(list, b)) do
        if i > N.look.satellites then break end
        rows[i] = { x = s.x, y = s.y, w = s.w, h = s.h, label = s.label, kind = SAT_KIND[s.kind] or 0 }
    end
    model.sa = rows
end

-- the studio (D229): what the node is shown as on its stage (the eighth chip tours them all), and what it shows
-- when nothing real is there to show
local PREVIEW = { "rest", "media", "notice", "volume", "workspaces", "system", "launcher" }
local SAMPLE_NOTICES = {
    { app = "MOOI", title = "A notice grows out of the node", actions = { "Open" } },
    { app = "CALENDAR", title = "Stand-up in ten minutes" },
    { app = "MAIL", title = "Three new messages", actions = { "Read" } },
    { app = "DOWNLOADS", title = "wallpaper-pack.zip is done" },
    { app = "SYSTEM", title = "Updates are ready" },
    { app = "MUSIC", title = "Added to your library" },
}
N.studio = { open = false, tab = 0, row = 0, pv = 0, tour = 1 }
local function studio_kind()
    local pv = N.studio.pv
    if pv == #PREVIEW then return PREVIEW[N.studio.tour] end
    return PREVIEW[pv + 1] or "rest"
end

render = function()
    local t = now()
    local look = N.look
    fact.nd_breath = not (type(N.settings.motion) == "table" and N.settings.motion.reduced == true)
    local studio = N.studio.open
    local kind, reacting
    if studio then kind, reacting = studio_kind(), false
    else kind, reacting = ST.current(N.st, t, { playing = N.media.playing and on_for("media"), near = N.near }) end
    -- on the studio's stage: in the middle, a little way down
    local shape = LK.shape(look)
    if studio then shape.top = 96 end
    local anchor = studio and "centre" or (cfg().anchor or "centre")
    local data = { n = #N.ws.list }
    -- at rest with something running, the seed is the time capsule
    local cap = (not studio and kind == "rest") and TK.capsule(N.time, wall()) or nil
    local b = G.body(cap and "capsule" or kind, N.scr, anchor, shape, data)
    show_capsule(cap)
    -- leaning toward where the pointer came in from
    if N.near and not studio and kind ~= "rest" and kind ~= "universe" then b.x = math.max(0, math.min(N.scr.w - b.w, b.x + (N.lean or 0) * 24)) end
    if kind == "universe" then
        local c = G.body("universe", N.scr, "centre", shape, data)
        b = { x = N.scr.w / 2 - c.w / 2, y = N.scr.h / 2 - c.h / 2, w = c.w, h = c.h, r = c.r }
    end
    -- a reaction: the seed stretches toward what is coming before it unfolds
    if reacting then
        local seed = G.body("rest", N.scr, anchor, shape, data)
        b = { x = seed.x - 20, y = seed.y, w = seed.w + 40, h = math.max(seed.h, 8), r = math.min(4, seed.r + 1) }
    end
    local changed = kind ~= N.kind
    N.kind = kind
    -- a change of shape: what unfolds grows out of the body again (and a cyber node glitches on the way)
    if changed then
        N.gn = (N.gn or 0) + 1
        fact.nd_gn = N.gn
        if look.style == "cyber" then
            fact.nd_gl = 1
            after(140, function() fact.nd_gl = 0 end)
        end
    end
    fact.nd_kind = KIND[kind] or 0
    -- the keyboard only for what is opened to be typed into: the time panel, the player and a finish card never
    -- take it, so a timer that ends while you type steals no keys
    fact.nd_kb = studio or kind == "launcher" or kind == "universe"
    set_body(b, changed and LK.overshoot(look) or 0)
    if kind == "media" then show_media(b) end
    if kind == "notice" then
        N.notice_list = (studio and #N.notices == 0) and SAMPLE_NOTICES or nil
        show_notices(b)
    end
    if kind == "workspaces" then show_rail(b) end
    if kind == "system" then show_system(b) end
    if kind == "launcher" then show_launcher(b) end
    if kind == "universe" then show_universe() end
    if kind == "time" then show_time() end
    if kind == "player" then show_media(b); if N.player_show then N.player_show() end end
    if kind == "done" then show_done() end
    if kind == "volume" then
        local v = N.vol or (studio and 0.6) or 0
        fact.nd_vol = v
        text.nd_vlabel = "VOLUME " .. math.floor(v * 100 + 0.5) .. "%"
    end
    show_satellites(b, kind)
    if reacting then N.pointer_due = math.min(N.pointer_due or math.huge, now() + ST.REACT_MS + 10) end
    schedule()
end

-- ── what is happening ──
pcall(sys.watch, "media", function(m)
    if type(m) ~= "table" then return end
    local was, was_title = N.media.playing, N.media.title
    N.media = { title = tostring(m.title or ""), artist = tostring(m.artist or ""), playing = m.playing == true,
                art = tostring(m.art or ""), length = tonumber(m.length) or 0, position = tonumber(m.position) or 0 }
    local art = N.media.art:gsub("^file://", "")
    text.nd_art = art
    fact.nd_arted = art ~= ""
    -- music starting, or a new song: the media branch grows for a moment, then it is a satellite
    if on_for("media") and N.media.playing and (not was or N.media.title ~= was_title) and was_title ~= nil then
        ST.push(N.st, "media", now())
    end
    render()
end)
pcall(sys.watch, "workspaces", function(w)
    if type(w) ~= "table" then return end
    local before = N.ws.active
    local list = {}
    for _, x in ipairs(type(w.list) == "table" and w.list or {}) do
        local id = tonumber(x.id or x)
        if id and id > 0 then list[#list + 1] = { id = id, windows = tonumber(x.windows) } end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    N.ws = { active = tonumber(w.active) or before, list = list }
    if on_for("workspaces") and before ~= N.ws.active and N.seen_ws then ST.push(N.st, "workspaces", now()) end
    N.seen_ws = true
    render()
end)
pcall(sys.watch, "audio", function(a)
    if type(a) ~= "table" then return end
    local v = tonumber(a.volume)
    if v and N.vol and math.abs(v - N.vol) > 0.004 and on_for("volume") then ST.push(N.st, "volume", now()) end
    N.vol = v
    render()
end)
-- the battery (D233): falling into its last fifth unplugged grows a warm card, with the time left from upower
local function battery_card(pct)
    text.nd_pvt = "BATTERY " .. math.floor(pct + 0.5) .. "%"
    text.nd_pvd = "Plug in soon"
    fact.nd_pvon = true
    ST.push(N.st, "battery", now())
    render()
    run("upower", { "-i", "/org/freedesktop/UPower/devices/DisplayDevice" }, function(out)
        local u = DV.upower(out)
        local left = u and DV.format_minutes(u.minutes_left) or ""
        if left ~= "" then text.nd_pvd = "About " .. left .. " left  ·  plug in soon" end
    end)
end
pcall(sys.watch, "battery", function(b)
    if type(b) ~= "table" or b.present == false then N.bat = nil; return end
    local before = N.bat
    N.bat, N.charging = tonumber(b.percent), b.charging == true
    if N.bat and N.seen_bat and DV.crossed_critical(before, N.bat, N.charging) then battery_card(N.bat) end
    N.seen_bat = true
    render()
end)
pcall(sys.watch, "network", function(n)
    if type(n) ~= "table" then return end
    N.online = n.online ~= false
    render()
end)
pcall(sys.watch, "apps", function(a)
    N.apps = type(a) == "table" and (type(a.list) == "table" and a.list or (a[1] ~= nil and a) or {}) or {}
end)
-- the notices, from Signal Loom's feed (only one program may receive them)
local function notices_now()
    local f = read("nexus-feed.json", "json")
    local items = type(f) == "table" and type(f.items) == "table" and f.items or {}
    N.notices = items
    local first = items[1]
    local stamp = first and (tostring(first.time or "") .. tostring(first.title or "")) or nil
    if stamp and stamp ~= N.notice_seen and N.notice_seen ~= nil and on_for("notices") then
        ST.push(N.st, "notice", now())
        -- the wallpaper answers with a small ripple at the node (mooi-surface, D226)
        if cfg().wallpaper ~= false then
            local cx = math.floor((fact.nd_tx or 0) + (fact.nd_tw or 22) / 2 + 0.5)
            run("pleamar", { "--say", "mooi-surface", "emit nd_fx " .. tostring(cx) }, function() end)
        end
    end
    N.notice_seen = stamp or ""
    render()
end
pcall(sys.watch, "files:nexus-feed.json", notices_now)
-- the bar's feed: the system's numbers, recording
local function feed_now()
    local f = read("sigil-feed.json", "json")
    N.feed = type(f) == "table" and f or {}
    render()
end
pcall(sys.watch, "files:sigil-feed.json", feed_now)
pcall(sys.watch, "files:settings.json", function()
    N.settings = config.parse(read("settings.json"), json.decode)
    paint()
    render()
end)

-- ── the pointer (lib/node/interaction): the scene says when it is over the node ──
local function pointer_step()
    local b = { x = fact.nd_tx or 0, y = fact.nd_ty or 0, w = fact.nd_tw or 22, h = fact.nd_th or 6 }
    local p = N.pointer or { x = -9999, y = -9999 }
    local r = IX.pointer(N.ix, p, b, now(), cfg().pointer or "normal")
    N.near, N.lean = r.hover, r.side
    fact.nd_lean = r.side
end
N.pointer_step = function()
    local was = N.near
    pointer_step()
    -- still deciding (waiting to unfold, or to retract): look again a little later
    if N.pointer or N.ix.hover then N.pointer_due = now() + 100 end
    if N.near ~= was then render() else schedule() end
end
on("nd_hover", function(v)
    if N.studio.open then return end
    v = math.floor(tonumber(v) or 0)
    local b = { x = fact.nd_tx or 0, y = fact.nd_ty or 0, w = fact.nd_tw or 22, h = fact.nd_th or 6 }
    N.pointer = v > 0 and { x = v - 1, y = b.y + b.h / 2 } or nil
    N.pointer_step()
end)

-- ── presses ──
local function toggle_hold(kind)
    if ST.held(N.st, kind) then ST.release(N.st, kind) else
        for _, k in ipairs(HELD) do ST.release(N.st, k) end
        ST.hold(N.st, kind)
    end
end
on("nd_press", function()
    if N.studio.open then if N.studio_press then N.studio_press() end; return end
    local k = N.kind
    if k == "launcher" or k == "universe" or k == "done" then return end
    -- a press on the panel's own body (not one of its controls) folds the time panel or the player away
    if k == "time" or k == "player" then ST.release(N.st, k); render(); return end
    -- the music capsule pressed: it grows into the player (D236)
    if k == "media" then if N.open_player then N.open_player() end; return end
    if k == "rest" and fact.nd_cap then if N.open_time then N.open_time() end; return end
    if k == "system" then ST.release(N.st, "system")
    elseif N.media.playing and k ~= "media" and on_for("media") then ST.push(N.st, "media", now())
    elseif on_for("system") then toggle_hold("system") end
    render()
end)
on("nd_media", function(v)
    local c = math.floor(tonumber(v) or 0)
    pcall(sys.call, ({ [1] = "media.previous", [2] = "media.toggle", [3] = "media.next" })[c] or "media.toggle")
end)
on("nd_nc", function(v)
    v = math.floor(tonumber(v) or -1)
    local row, what = v // 10, v % 10
    -- the card's own notice in the feed's order (cards are gathered by app, D237), as mooi numbers them
    local i = N.notice_rows and N.notice_rows[row + 1]
    if N.studio.open or not i or not N.notices[i] then return end
    run("pleamar", { "--say", "mooi", "emit note_act " .. tostring((i - 1) * 10 + (what == 9 and 9 or what)) }, function() end)
    if what == 9 then table.remove(N.notices, i); render() end
end)
on("nd_ws", function(v)
    local w = N.ws.list[math.floor(tonumber(v) or -1) + 1]
    if w then run("hyprctl", { "dispatch", 'hl.dsp.focus({ workspace = "' .. tostring(w.id) .. '" })' }) end
end)
on("nd_sa", function(v)
    local k = math.floor(tonumber(v) or 0)
    if k == SAT_KIND.music or k == SAT_KIND.music_rec then ST.push(N.st, "media", now())
    elseif k == SAT_KIND.notice then ST.push(N.st, "notice", now())
    elseif k == SAT_KIND.network or k == SAT_KIND.battery then toggle_hold("system") end
    render()
end)

-- ── the launcher ──
local function search()
    local wd = read("widgets.json", "json")
    local apps = WB.grid_apps(N.apps, type(wd) == "table" and wd.launch_counts or {}, N.q, 6)
    for _, a in ipairs(apps) do a.kind = a.kind or "app" end
    -- D234: mooi's own commands and the open windows, when something is typed
    if N.q:match("%S") then
        apps = CMD.merge(apps, CMD.match(N.q, 3), CMD.windows(N.clients, N.q, 2), 6)
        -- D238: a conversion ("5 km in mi", "20 c to f") is answered first; Return copies the answer
        local u = UN.answer(N.q)
        if u then
            table.insert(apps, 1, { kind = "calc", name = "= " .. u.text, value = u.text })
            while #apps > 6 do table.remove(apps) end
        -- D235: a sum is worked out (lib/node/calc: its own parser, nothing run) and comes first; Return copies it
        elseif CALC.looks_like(N.q) then
            local v = CALC.eval(N.q)
            if v then
                local shown = CALC.format(v)
                table.insert(apps, 1, { kind = "calc", name = "= " .. shown, value = shown })
                while #apps > 6 do table.remove(apps) end
            end
        end
    end
    N.results = apps
    N.sel = math.max(0, math.min(N.sel, #N.results - 1))
end
-- what a chosen row does: an app starts, a window comes forward, a command of mooi's runs, a sum is copied
local function choose(a)
    if not a then return end
    if a.kind == "window" then
        local d = HY.dispatch("focus", a.address)   -- the address checked, the expression built safely
        if d then run("hyprctl", { "dispatch", d }, function() end) end
    elseif a.kind == "command" then
        run("mooi", a.args, function() end)
    elseif a.kind == "calc" then
        run("wl-copy", { tostring(a.value) }, function() end)
    else
        pcall(sys.call, "apps.launch", a.exec)
    end
end
local function open_launcher()
    for _, k in ipairs(HELD) do ST.release(N.st, k) end
    ST.hold(N.st, "launcher")
    N.q, N.sel = "", 0
    text.nd_q = ""
    search()
    render()
    -- the open windows, for the search to find (a moment later is soon enough: nobody has typed yet)
    run("hyprctl", { "-j", "clients" }, function(out)
        local ok, c = pcall(json.decode, out or "")
        N.clients = ok and type(c) == "table" and c or {}
        if N.q:match("%S") then search(); render() end
    end)
end
on("text:nd_q", function(v) N.q = tostring(v or ""); N.sel = 0; search(); render() end)

-- ── the universe ──
local function open_universe()
    for _, k in ipairs({ "system", "launcher" }) do ST.release(N.st, k) end
    N.uni_at = N.ws.active
    N.rot = ws_index(N.ws.active)
    ST.hold(N.st, "universe")
    run("hyprctl", { "-j", "clients" }, function(out)
        local ok, c = pcall(json.decode, out or "")
        N.clients = ok and type(c) == "table" and c or {}
        render()
    end)
    render()
end
local function go_workspace(id)
    run("hyprctl", { "dispatch", 'hl.dsp.focus({ workspace = "' .. tostring(id) .. '" })' })
end
on("nd_un", function(v)
    go_workspace(math.floor(tonumber(v) or 1))
    ST.release(N.st, "universe")
    render()
end)

-- ── the keyboard, while the node holds it ──
on("nd_key", function(v)
    v = math.floor(tonumber(v) or 0)
    if N.studio.open then if N.studio_key then N.studio_key(v) end; return end
    if N.kind == "done" then
        if v == 27 or v == 13 or v == 32 then N.answer_done() end
        return
    end
    if N.kind == "player" then
        if v == 27 then ST.release(N.st, "player"); render()
        elseif v == 32 then pcall(sys.call, "media.toggle")
        elseif v == 37 then pcall(sys.call, "media.previous")
        elseif v == 39 then pcall(sys.call, "media.next") end
        return
    end
    if N.kind == "time" then
        local m = LK.index_of(TK.MODES, N.time.mode) or 1
        if v == 27 then ST.release(N.st, "time"); render()
        elseif v == 32 or v == 13 then N.time_cmd(10)
        elseif v == 37 or v == 39 or v == 9 then N.time.mode = TK.MODES[(m - 1 + (v == 37 and -1 or 1)) % #TK.MODES + 1]; save_time(); render() end
        return
    end
    if N.kind == "launcher" then
        if v == 27 then ST.release(N.st, "launcher")
        elseif v == 38 then N.sel = math.max(0, N.sel - 1)
        elseif v == 40 or v == 9 then N.sel = math.min(#N.results - 1, N.sel + 1)
        elseif v == 13 then
            local a = N.results[N.sel + 1]
            choose(a)
            ST.release(N.st, "launcher")
        end
    elseif N.kind == "universe" then
        if v == 27 then ST.release(N.st, "universe")
        elseif v == 37 or v == 38 then turn(-1)
        elseif v == 39 or v == 40 or v == 9 then turn(1)
        elseif v == 13 then go_workspace(N.uni_at or N.ws.active); ST.release(N.st, "universe") end
    end
    render()
end)
on("nd_lr", function(v)
    local a = N.results[math.floor(tonumber(v) or -1) + 1]
    choose(a)
    ST.release(N.st, "launcher")
    render()
end)

-- ── privacy (D232): who has the microphone, whether the camera is open — every two seconds while allowed ──
N.mic_on, N.cam_on = false, false
local function privacy_card(what, on, who)
    text.nd_pvt = what .. (on and " ON" or " OFF")
    text.nd_pvd = on and (who ~= "" and who or "In use") or "No longer in use"
    fact.nd_pvon = on
    ST.push(N.st, "privacy", now())
    render()
end
local pv_busy = false
every(2000, function()
    if cfg().privacy == false or pv_busy then
        if cfg().privacy == false and (N.mic_on or N.cam_on) then N.mic_on, N.cam_on = false, false; render() end
        return
    end
    pv_busy = true
    -- which sources are monitors changes only when a device comes or goes: asked again every half minute
    local function with_monitors(go)
        if N.pv_monitors and now() - (N.pv_mon_at or 0) < 30000 then go(N.pv_monitors); return end
        run("pactl", { "-f", "json", "list", "sources" }, function(sout)
            local sok, sources = pcall(json.decode, sout or "")
            N.pv_monitors, N.pv_mon_at = PV.monitors(sok and sources or nil), now()
            go(N.pv_monitors)
        end)
    end
    with_monitors(function(monitors)
    run("pactl", { "-f", "json", "list", "source-outputs" }, function(out, code)
        local ok, list = pcall(json.decode, out or "")
        local users = (code == 0 and ok) and PV.mic_users(list, monitors) or {}
        local on = #users > 0
        local ch = PV.changed(N.mic_on, on)
        N.mic_on = on
        if ch then privacy_card("MICROPHONE", on, table.concat(users, " · ")) end
        -- fuser prints the processes on its standard output (the device names go to the other): any number is a
        -- process holding a camera open
        run("fuser", { "/dev/video0", "/dev/video1", "/dev/video2", "/dev/video3" }, function(fout)
            pv_busy = false
            local cam = type(fout) == "string" and fout:find("%d") ~= nil
            local cc = PV.changed(N.cam_on, cam)
            N.cam_on = cam
            if cc then privacy_card("CAMERA", cam, "") end
        end)
    end)
    end)
end)

-- ── the player (D236): while it is open, the player's state each second, the light and the microphone every two,
-- the music's bands from the bar's feed twenty times a second (asked for every three) ──
N.pl = nil
local function player_show()
    local m = N.pl
    fact.nd_shuf = m and m.shuffle or false
    fact.nd_loop = m and (m.loop == "Playlist" and 1 or m.loop == "Track" and 2 or 0) or 0
    local len = m and m.length_ms or (N.media.length or 0) * 1000
    local pos = m and m.position_ms or 0
    if m and m.playing and N.pl_at then pos = math.min(len, pos + (wall() - N.pl_at)) end
    text.nd_pos = MK.format_time(pos)
    text.nd_len = MK.format_time(len)
    fact.nd_prog = len > 0 and math.max(0, math.min(1, pos / len)) or 0
    fact.nd_vol = N.vol or 0
end
N.player_show = player_show
local function player_poll()
    run("playerctl", { "metadata", "--format", MK.FORMAT }, function(out, code)
        N.pl = code == 0 and MK.parse(out) or nil
        N.pl_at = wall()
        if N.kind == "player" then player_show() end
    end)
end
local function devices_poll()
    run("brightnessctl", { "-m" }, function(out)
        local b = DV.brightness(out)
        fact.nd_hasbri = b ~= nil
        if b and not N.bri_drag then fact.nd_bri = b.frac end
    end)
    run("pactl", { "get-source-volume", "@DEFAULT_SOURCE@" }, function(out)
        local v = DV.source_volume(out)
        if v and not N.mic_drag then fact.nd_mic = math.min(1, v) end
    end)
    run("pactl", { "get-source-mute", "@DEFAULT_SOURCE@" }, function(out)
        local m = DV.source_mute(out)
        if m ~= nil then fact.nd_micm = m end
    end)
end
-- the words (D240, only while Settings allows it): mooi's own player's fetcher and cache (a file beside the song,
-- the saved answer, LRCLIB once), followed at a quarter of a second
local fetch_lyrics = require("player/lyricfetch")({ read = read })
N.lyr, N.lyr_key = nil, nil
local function lyrics_now()
    local m = N.media
    local on = N.settings.node and N.settings.node.lyrics == true
    if not on or m.title == "" then N.lyr, N.lyr_key = nil, nil; fact.nd_lyon = false; return end
    local key = "remote:" .. tostring(m.artist) .. "\t" .. tostring(m.title)   -- as mooi's player keys a song
    if key == N.lyr_key then return end
    N.lyr_key, N.lyr = key, nil
    fact.nd_lyon = false
    fetch_lyrics(key, m.artist, m.title, "", math.floor((m.length or 0) + 0.5), nil, function(raw)
        if N.lyr_key ~= key then return end
        local lines = (type(raw) == "string" and raw ~= "none" and raw ~= "instrumental") and LY.parse(raw) or {}
        N.lyr = #lines > 0 and lines or nil
        fact.nd_lyon = N.lyr ~= nil
    end)
end
local lyr_cur
every(250, function()
    if N.kind ~= "player" or not N.lyr then return end
    local pos = N.pl and N.pl.position_ms or 0
    if N.pl and N.pl.playing and N.pl_at then pos = pos + (wall() - N.pl_at) end
    local w = LY.window(N.lyr, pos, 1)
    if w.cur ~= lyr_cur then lyr_cur = w.cur; text.nd_lyc = w.cur ~= "" and w.cur or "♪"; text.nd_lyn = w.next end
end)
local function open_player()
    for _, k in ipairs(HELD) do ST.release(N.st, k) end
    ST.hold(N.st, "player")
    player_poll(); devices_poll(); lyrics_now()
    run("pleamar", { "--say", "mooi", "emit feed_want" }, function() end)
    render()
end
N.open_player = open_player
local pl_tick = 0
every(1000, function()
    if N.kind ~= "player" then return end
    pl_tick = pl_tick + 1
    player_poll()
    lyrics_now()
    if pl_tick % 2 == 0 then devices_poll() end
    if pl_tick % 3 == 0 then run("pleamar", { "--say", "mooi", "emit feed_want" }, function() end) end
end)
-- the bands: the bar's 32, the lower 16 mirrored round the middle; a fact written only when it moves enough to see
local sp_last, viz_seq = {}, nil
every(50, function()
    if N.kind ~= "player" then return end
    local ok, raw = pcall(sys.ask, "files.read", VF.FILE)
    local t = ok and type(raw) == "string" and VF.decode(raw) or nil
    if t and VF.newer(viz_seq, t.seq) then viz_seq = t.seq else t = nil end
    if not t then return end
    local bands = t.playing and VF.resample(t.bands, 16) or {}
    local m = MK.mirrored(bands, 32)
    for i = 1, 32 do
        local v = m[i] or 0
        if math.abs((sp_last[i] or -1) - v) > 0.01 then sp_last[i] = v; fact["nd_sp" .. (i - 1)] = v end
    end
end)
on("nd_pl", function(v)
    v = math.floor(tonumber(v) or 0)
    local player = N.pl and N.pl.player or ""
    if v == 1 then
        local argv = MK.cmd_shuffle(player, not (N.pl and N.pl.shuffle))
        if N.pl then N.pl.shuffle = not N.pl.shuffle end   -- shown at once; the next poll says what it is
        run(argv[1], { table.unpack(argv, 2) }, function() end)
    elseif v == 5 then
        local nxt = MK.next_loop(N.pl and N.pl.loop or "None")
        if N.pl then N.pl.loop = nxt end
        local argv = MK.cmd_loop(player, nxt)
        run(argv[1], { table.unpack(argv, 2) }, function() end)
    elseif v == 2 or v == 3 or v == 4 then
        pcall(sys.call, ({ [2] = "media.previous", [3] = "media.toggle", [4] = "media.next" })[v])
        if v == 3 and N.pl then N.pl.playing = not N.pl.playing; N.pl.position_ms = N.pl.position_ms + (wall() - (N.pl_at or wall())); N.pl_at = wall() end
    elseif v == 7 then
        fact.nd_mix = not fact.nd_mix
        if fact.nd_mix and N.mix_poll then N.mix_poll() end
    elseif v == 6 then
        fact.nd_micm = not fact.nd_micm
        local argv = DV.toggle_source_mute()
        run(argv[1], { table.unpack(argv, 2) }, function() end)
    end
    player_show()
end)
-- the mixer (D239): one row per app playing, from PipeWire's playback streams, polled each second while shown
N.mix = {}
local function mix_rows()
    local rows = {}
    for i, a in ipairs(N.mix) do if i <= 4 then rows[i] = { name = a.name, vol = math.min(1, a.volume), muted = a.muted } end end
    model.mx = rows
end
N.mix_poll = function()
    run("pactl", { "-f", "json", "list", "sink-inputs" }, function(out, code)
        local ok, list = pcall(json.decode, out or "")
        if code ~= 0 or not ok then return end
        if N.mix_drag then return end
        N.mix = MX.group(list)
        mix_rows()
    end)
end
every(1000, function() if N.kind == "player" and fact.nd_mix then N.mix_poll() end end)
local function run_all(cmds) for _, argv in ipairs(cmds) do run(argv[1], { table.unpack(argv, 2) }, function() end) end end
on("nd_mx", function(v)
    v = math.floor(tonumber(v) or 0)
    local a = N.mix[v // 2000 + 1]
    if not a then return end
    a.volume = math.min(1000, v % 2000) / 1000
    mix_rows()
    N.mix_drag = true
    N.mx_gen = (N.mx_gen or 0) + 1
    local g = N.mx_gen
    after(80, function()
        if g ~= N.mx_gen then return end
        run_all(MX.set_volume(a, a.volume))
        after(600, function() if g == N.mx_gen then N.mix_drag = false end end)
    end)
end)
on("nd_mxm", function(v)
    local a = N.mix[math.floor(tonumber(v) or -1) + 1]
    if not a then return end
    a.muted = not a.muted
    mix_rows()
    run_all(MX.set_mute(a, a.muted))
end)
on("nd_seek", function(v)
    local f = math.max(0, math.min(1000, tonumber(v) or 0)) / 1000
    local len = N.pl and N.pl.length_ms or 0
    local argv = MK.cmd_seek(N.pl and N.pl.player or "", f, len)
    if not argv then return end
    if N.pl then N.pl.position_ms, N.pl_at = math.floor(f * len), wall() end
    player_show()
    -- a drag says where many times a second: the player is told the last place, a moment after it rests
    N.seek_gen = (N.seek_gen or 0) + 1
    local g = N.seek_gen
    after(120, function() if g == N.seek_gen then run(argv[1], { table.unpack(argv, 2) }, function() end) end end)
end)
on("nd_mt", function(v)
    v = math.floor(tonumber(v) or 0)
    -- meter * 2000 + its level 0 … 1000 (a stride of 2000, so a full meter is never the next one at zero)
    local m, f = v // 2000, math.min(1000, v % 2000) / 1000
    if m == 0 then
        fact.nd_vol = f
        pcall(sys.call, "audio.volume", f)
    elseif m == 1 or m == 2 then
        if m == 1 then fact.nd_bri = math.max(0.01, f); N.bri_drag = true else fact.nd_mic = f; N.mic_drag = true end
        N.mt_gen = (N.mt_gen or 0) + 1
        local g = N.mt_gen
        after(80, function()
            if g ~= N.mt_gen then return end
            local argv = m == 1 and DV.set_brightness(f) or DV.set_source_volume(f)
            run(argv[1], { table.unpack(argv, 2) }, function() end)
            after(600, function() if g == N.mt_gen then N.bri_drag, N.mic_drag = false, false end end)
        end)
    end
end)

-- ── a notice's life (D237): a line drains over it; the pointer resting on the node holds it ──
every(250, function()
    local ev = N.st.events.notice
    if N.kind ~= "notice" or not ev then return end
    if N.near then ev.till = ev.till + 250 end
    fact.nd_ncl = math.max(0, math.min(1, (ev.till - now()) / ST.LIFE.notice))
end)

-- ── the time tools (D231) ──
local function chime()
    -- three rising notes of mooi's own, soft: it says so without startling
    for i, hz in ipairs({ 880, 1318.5, 1760 }) do
        pcall(sound.tone, { wave = "sine", freq = hz, ms = 220, volume = 0.3, delay = (i - 1) * 170, release = 160 })
    end
end
local function open_time()
    for _, k in ipairs(HELD) do ST.release(N.st, k) end
    ST.hold(N.st, "time")
    render()
end
local was_cap = false
local function time_tick()
    local t = N.time
    if not (TK.busy(t) or N.kind == "time") then return end
    local now = wall()
    local done = TK.tick(t, now, local_date, local_time)
    if #done > 0 then
        for _, d in ipairs(done) do N.done[#N.done + 1] = d end
        save_time()
        chime()
        -- under a fullscreen window the node cannot be seen: the desktop's notifications say it too
        run("hyprctl", { "-j", "activewindow" }, function(out)
            local ok, win = pcall(json.decode, out or "")
            if ok and DV.fullscreen(win) then
                for _, d in ipairs(done) do run("notify-send", { "-a", "mooi", "-u", "critical", d.title, d.detail }, function() end) end
            end
        end)
        ST.hold(N.st, "done")
        render()
        return
    end
    local cap = N.kind == "rest" and not N.studio.open and TK.capsule(t, now) or nil
    if (cap ~= nil) ~= was_cap then was_cap = cap ~= nil; render(); return end
    if cap then show_capsule(cap) end
    if N.kind == "time" then show_time() end
end
every(250, time_tick)
-- the stopwatch's hundredths, only while it is on stage and running (ten times a second: the matrix is many cells)
every(100, function()
    if N.kind == "time" and N.time.mode == "stopwatch" and N.time.stopwatch.since then
        pixels(TK.format(TK.stopwatch_ms(N.time, wall()), true))
    end
end)
N.open_time = open_time
N.time_cmd = function(v)
    v = math.floor(tonumber(v) or -1)
    local t, now = N.time, wall()
    local mode = t.mode
    if v >= 0 and v <= 3 then t.mode = TK.MODES[v + 1]
    elseif v == 10 then
        if mode == "timer" then TK.timer_go(t, now)
        elseif mode == "stopwatch" then TK.stopwatch_go(t, now)
        elseif mode == "focus" then TK.focus_go(t, now)
        else TK.alarm_set(t, not t.alarm.on, now, local_date, local_time) end
    elseif v == 11 then
        if mode == "timer" then TK.timer_reset(t)
        elseif mode == "stopwatch" then TK.stopwatch_reset(t)
        elseif mode == "focus" then TK.focus_reset(t)
        else ST.release(N.st, "time") end
    elseif v == 12 then
        if mode == "stopwatch" then TK.lap(t, now) elseif mode == "focus" then TK.focus_skip(t, now) end
    elseif v >= 21 and v <= 24 then
        TK.timer_add(t, ({ [21] = 60000, [22] = 300000, [23] = 600000, [24] = -60000 })[v])
    elseif v >= 31 and v <= 34 then
        local dh, dm = ({ [31] = 1, [32] = -1 })[v] or 0, ({ [33] = 5, [34] = -5 })[v] or 0
        TK.alarm_nudge(t, dh, dm, now, local_date, local_time)
    else return end
    save_time()
    render()
end
on("nd_tm", function(v) N.time_cmd(v) end)
-- the card answered: the next thing that finished, or back to what it was
local function answer_done()
    table.remove(N.done, 1)
    if #N.done == 0 then ST.release(N.st, "done") end
    render()
end
N.answer_done = answer_done
on("nd_dn", answer_done)

-- ── the studio (D229): `mooi node studio` — the node on a stage, and a deck of what it may look like ──
local PRESET_DESC = {
    organic = "Soft and elastic: it breathes, and leans into the music",
    minimal = "A point. Fast, restrained, next to no glow",
    technical = "Ruled and precise: ticks, brackets, square corners",
    cyber = "Quick and broken: segments, an ember glow, a glitch on every change",
}
local function title(s) s = tostring(s or ""); return (s:gsub("^%l", string.upper)) end
local function slot_label(x)
    if not x then return "Empty: save the look you are wearing here" end
    return title(x.preset) .. (x.custom and ", made your own" or "") .. "  ·  " .. title(x.seed) .. " seed  ·  "
        .. title(x.texture) .. "  ·  " .. tostring(x.glow) .. "% glow"
end
local function studio_rows()
    local st = N.studio
    local tab = LK.TABS[st.tab + 1]
    fact.nd_tab = st.tab
    if st.tab == 0 then
        model.sk = {}
        local ps = {}
        for i, name in ipairs(LK.PRESETS) do
            local p = LK.preset(name)
            local sh = LK.shape(p)
            ps[i] = { name = title(name), desc = PRESET_DESC[name], on = N.look.preset == name and not N.look.custom,
                      sw = sh.seed_w, sh = sh.seed_h, sr = sh.round, seed = LK.facts(p).nd_seed }
        end
        model.ps = ps
        local sl = {}
        for i = 1, LK.SLOTS do
            local x = N.look.slots[i]
            sl[i] = { label = slot_label(x or nil), full = x and true or false }
        end
        model.sl = sl
    else
        model.sk = LK.rows(N.look, tab)
    end
    st.row = math.max(0, math.min(st.row, math.max(0, #(LK.SCHEMA[tab] or {}) - 1)))
    fact.nd_kr = st.tab == 0 and -1 or st.row
    fact.nd_pv = st.pv
    text.nd_lookname = string.upper(N.look.preset) .. (N.look.custom and " · MADE YOURS" or "")
end
-- the look moved: the scene told, the file written (a moment later), the deck and the node redrawn
local function look_changed()
    apply_look()
    save_look()
    studio_rows()
    render()
end
local function prepare_preview()
    if studio_kind() == "launcher" then N.q, N.sel = "", 0; text.nd_q = ""; search() end
end
local function open_studio()
    for _, k in ipairs(HELD) do ST.release(N.st, k) end
    pcall(math.randomseed, os.time())
    N.studio.open = true
    fact.nd_studio = true
    studio_rows()
    render()
end
local function close_studio()
    N.studio.open = false
    fact.nd_studio = false
    render()
end
local function wear(t)
    local slots = N.look.slots
    N.look = LK.normalise(t)
    N.look.slots = slots
end
local function row_key(row)
    local r = (LK.SCHEMA[LK.TABS[N.studio.tab + 1]] or {})[row + 1]
    return r and r.key
end
on("nd_tab", function(v)
    N.studio.tab = math.max(0, math.min(#LK.TABS - 1, math.floor(tonumber(v) or 0)))
    N.studio.row = 0
    studio_rows()
end)
on("nd_sk", function(v)
    v = math.floor(tonumber(v) or 0)
    local row = v // 2000   -- row * 2000 + 0 … 1000: a full slider is never the next row at zero
    local key = row_key(row)
    if not key then return end
    N.studio.row = row
    if LK.set_frac(N.look, key, math.min(1000, v % 2000) / 1000) then look_changed() end
end)
on("nd_so", function(v)
    v = math.floor(tonumber(v) or 0)
    local row, j = v // 10, v % 10
    local key = row_key(row)
    if not key then return end
    N.studio.row = row
    if LK.set_choice(N.look, key, j + 1) then look_changed() end
end)
on("nd_pv", function(v)
    N.studio.pv = math.max(0, math.min(#PREVIEW, math.floor(tonumber(v) or 0)))
    N.studio.tour = 1
    prepare_preview()
    studio_rows()
    render()
end)
on("nd_ps", function(v)
    local name = LK.PRESETS[math.floor(tonumber(v) or 0) + 1]
    if not name then return end
    wear(LK.preset(name))
    look_changed()
end)
on("nd_slot", function(v)
    v = math.floor(tonumber(v) or -1)
    local k, what = v // 10 + 1, v % 10
    if k < 1 or k > LK.SLOTS then return end
    if what == 0 then
        local c = {}
        for key, x in pairs(N.look) do if key ~= "slots" then c[key] = x end end
        N.look.slots[k] = c
    elseif what == 1 and N.look.slots[k] then wear(N.look.slots[k])
    elseif what == 9 then N.look.slots[k] = false
    else return end
    look_changed()
end)
on("nd_stc", function(v)
    v = math.floor(tonumber(v) or 0)
    if v == 1 then N.look = LK.shuffle(math.random, N.look.slots); look_changed()
    elseif v == 2 then close_studio()
    elseif v == 3 then wear(LK.preset(N.look.preset)); look_changed() end
end)
-- pressing the node on the stage: the next state
N.studio_press = function()
    N.studio.pv = (N.studio.pv + 1) % #PREVIEW
    prepare_preview()
    studio_rows()
    render()
end
-- the keyboard: Esc done · Tab the next page · ↑↓ a row · ←→ change it (on Presets: the next preset)
N.studio_key = function(v)
    local st = N.studio
    if v == 27 or (v == 13 and st.tab == 0) then close_studio(); return end
    if v == 9 then st.tab = (st.tab + 1) % #LK.TABS; st.row = 0; studio_rows(); return end
    if st.tab == 0 then
        if v == 37 or v == 39 then
            local i = LK.index_of(LK.PRESETS, N.look.preset) or 1
            i = (i - 1 + (v == 39 and 1 or -1)) % #LK.PRESETS + 1
            wear(LK.preset(LK.PRESETS[i]))
            look_changed()
        end
        return
    end
    if v == 38 then st.row = st.row - 1; studio_rows()
    elseif v == 40 then st.row = st.row + 1; studio_rows()
    elseif v == 37 or v == 39 or v == 13 then
        local key = row_key(st.row)
        if key and LK.nudge(N.look, key, v == 37 and -1 or 1) then look_changed() end
    end
end
-- the tour: every state in turn
every(2200, function()
    local st = N.studio
    if not st.open or st.pv ~= #PREVIEW then return end
    st.tour = st.tour % #PREVIEW + 1
    prepare_preview()
    render()
end)
-- a hand edit of node-look.json (not this program's own write) is worn at once
pcall(sys.watch, "files:" .. LK.FILE, function()
    if N.saving then N.saving = false; return end
    local slots = N.look.slots
    N.look = look_now()
    apply_look()
    if N.studio.open then studio_rows() end
    render()
end)

-- ── `mooi node …`: Super wakes it; the launcher; the universe; the studio ──
on("nd_cmd", function(v)
    v = math.floor(tonumber(v) or 0)
    if N.studio.open and v ~= 4 then close_studio(); return end
    if v == 1 then
        -- Super: the music if it plays, else what you last held, else the system for a moment
        if N.kind ~= "rest" then for _, k in ipairs(HELD) do ST.release(N.st, k) end
        elseif N.media.playing and on_for("media") then ST.push(N.st, "media", now())
        elseif on_for("system") then ST.push(N.st, "system", now()) end
        render()
    elseif v == 2 then
        if ST.held(N.st, "launcher") then ST.release(N.st, "launcher"); render() else open_launcher() end
    elseif v == 3 then
        if ST.held(N.st, "universe") then ST.release(N.st, "universe"); render() else open_universe() end
    elseif v == 4 then
        if N.studio.open then close_studio() else open_studio() end
    elseif v == 5 then
        if ST.held(N.st, "time") then ST.release(N.st, "time"); render() else open_time() end
    end
end)

-- ── the screen it stands on ──
run("hyprctl", { "-j", "monitors" }, function(out)
    local ok, mons = pcall(json.decode, out or "")
    for _, m in ipairs(ok and type(mons) == "table" and mons or {}) do
        if m.focused then N.scr = { w = tonumber(m.width) / (tonumber(m.scale) or 1), h = tonumber(m.height) / (tonumber(m.scale) or 1) } end
    end
    render()
end)
notices_now(); feed_now()
render()
log("node · up")
