-- The Dynamic Pill as a living node (D226; docs/superpowers/specs/2026-11-09-dynamic-pill-node-design.md). The
-- logic: what is happening (the services, Signal Loom's feed, the bar's feed), what the node is now
-- (lib/node/state), where its body and parts go (lib/node/geometry), how it looks (lib/node/look, set
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
local CAL = require("lib/calendar")
local NOTES = require("lib/notes")
local STASH = require("lib/stash")
local CH = require("lib/node/cliphist")
local HI = require("lib/node/history")
local TM = require("lib/node/terminal")
local BMOST = require("lib/bmostate")
local PF = require("lib/pillface")
local CS = require("lib/node/clockstyles")
local WFX = require("lib/node/wsfx")
local VF = require("lib/vizfeed")
local IX = require("lib/node/interaction")
local WB = require("lib/wbelow")          -- the apps' ranking (Launch's grid's, D215)
local KS = require("lib/node/keysheet")
local SSH = require("lib/node/ssh")
local PK = require("lib/node/pkgs")
local SX = require("lib/node/sysextra")
local GX = require("lib/node/galaxy")
local HM = require("lib/node/home")
local WEEK = require("lib/node/week")
local SETTINGS = require("lib/settingsfile")
local SETTINGS_FILE = "settings.json"
local DESK = require("lib/desktop")

local KIND = { rest = 0, media = 1, notice = 2, volume = 3, workspaces = 4, launcher = 6, universe = 7, time = 8, done = 9, privacy = 10, battery = 10, player = 11, panel = 13, launch = 14 }
-- what a press, Super or another opening lets go of (`done` is never among them: it waits to be answered)
local HELD = { "launcher", "universe", "time", "player", "panel" }

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
    panel = "home", wifi_on = false, wifi_name = "Off", bt_on = false,
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
    if N.bmo_show then N.bmo_show() end
end
apply_look()
-- written a moment after the last change (a slider dragged writes once, when it rests)
local save_gen = 0
local function save_look()
    save_gen = save_gen + 1
    local g = save_gen
    after(300, function()
        if g ~= save_gen then return end
        N.saved_text = json.encode(N.look)
        pcall(sys.call, "files.write", LK.FILE, N.saved_text)
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

-- ── reactions (D256): a ring out of the node when something happens — its own colour, or warm ──
N.rn = 0
local function react(warm)
    if N.look.reactions == "off" or N.studio.open then return end
    N.rn = N.rn + 1
    fact.nd_rk = warm and 1 or 0
    fact.nd_rn = N.rn
end
N.react = react

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
local show_panel, open_panel
local show_keys       -- (D267) the shortcut sheet's rows; the keyboard reaches it before it is written, below
local with_terminal   -- (D268) the search line opens SSH and packages in it; defined with btop's, below
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

local function mmss(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return (sec // 60) .. ":" .. string.format("%02d", sec % 60)
end
local function show_media(b)
    local m = N.media
    text.nd_title = m.title ~= "" and m.title or "Nothing playing"
    text.nd_artist = m.artist
    fact.nd_playing = m.playing
    fact.nd_paused = not m.playing and (m.title ~= "" or m.length > 0)
    fact.nd_arted = m.art ~= ""
    fact.nd_prog = (m.length > 0) and math.max(0, math.min(1, m.position / m.length)) or 0
    text.nd_hompos, text.nd_homlen = mmss(m.position), mmss(m.length)
end

-- D237: one card per app (its newest notice, and how many it has sent); each row remembers which notice it is
local function show_notices(b)
    local groups = NT.group(N.notice_list or N.notices)
    -- the card the pointer rests on opens to be read (D245)
    local heights = {}
    for i, g in ipairs(groups) do heights[i] = (N.nc_open == i) and NT.open_height(g) or NT.CARD_H end
    local cards = G.cards(b, math.min(N.look.cards, #groups), N.scr, heights)
    local rows, idx = {}, {}
    local shown = 0
    for i, c in ipairs(cards) do
        local g = groups[i]
        local a1 = g.actions[1]
        rows[i] = { x = c.x, y = c.y, w = c.w, h = c.h, app = NT.label(g), title = g.title, body = g.body,
                    open = N.nc_open == i and g.body ~= "",
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
    -- label, value, hot, how full (0 … 1), whether a press opens btop, its history
    local items = {
        { "CPU", cpu and (math.floor(cpu + 0.5) .. "%") or "—", (cpu or 0) > 85, (cpu or 0) / 100, true, N.hist.cpu },
        { "RAM", mem and (math.floor(mem + 0.5) .. "%") or "—", (mem or 0) > 90, (mem or 0) / 100, true, N.hist.mem },
        { "TEMP", f.temp and (math.floor(f.temp) .. "°") or "—", (tonumber(f.temp) or 0) > 85, math.min(1, (tonumber(f.temp) or 0) / 100), true, N.hist.temp },
        { "NET", N.online and "ON" or "OFF", not N.online, N.online and 1 or 0, false },
        { "BAT", N.bat and (math.floor(N.bat + 0.5) .. "%" .. (N.charging and "+" or "")) or "—", N.bat ~= nil and DV.band(N.bat) == "critical" and not N.charging, (N.bat or 0) / 100, false },
        -- D270 (Minflair's): the graphics card, when it says, and the home folder's disk
        { "GPU", N.gpu and (math.floor(N.gpu + 0.5) .. "%") or "—", (N.gpu or 0) > 90, (N.gpu or 0) / 100, true, N.hist.gpu },
        { "DISK", N.disk and (math.floor(N.disk.pct + 0.5) .. "%") or "—", N.disk ~= nil and N.disk.pct > 90, N.disk and N.disk.pct / 100 or 0, false },
    }
    local rows = {}
    -- D260: the panel's System page is a two-column grid of cards, each with its last twenty readings
    local cw = (b.w - 40) / 2
    for i, it in ipairs(items) do
        local col, row = (i - 1) % 2, (i - 1) // 2
        local r = { x = b.x + 14 + col * (cw + 12), y = b.y + 56 + row * 96, label = it[1], value = it[2], hot = it[3],
                    frac = math.max(0, math.min(1, it[4] or 0)), deep = it[5] == true }
        local bars = it[6] and HI.bars(it[6], 20) or {}
        for k = 0, 19 do r["h" .. k] = bars[k + 1] or (it[6] and 0 or (it[4] or 0)) end
        rows[i] = r
    end
    model.sy = rows
end

-- D311: a window's row wears its app's icon (lib/apps: StartupWMClass, the desktop id, the program, the name)
local APPS = require("lib/apps")
local apps_ix, apps_ix_of = nil, nil
local function app_icon(class)
    if apps_ix_of ~= N.apps then apps_ix, apps_ix_of = APPS.index(N.apps or {}), N.apps end
    return APPS.icon_for(apps_ix, class) or ""
end
local function show_launcher(b)
    local rows = {}
    local grid = #N.results > 0
    for _, a in ipairs(N.results) do if a.kind ~= "app" then grid = false end end
    N.lgrid = grid
    fact.nd_lgrid = grid
    local places = G.results(b, #N.results, grid)
    for i, a in ipairs(N.results) do
        local p = places[i]
        local name = tostring(a.name or a.id or "")
        local icon = (a.kind == "app" and type(a.icon) == "string") and a.icon or ""
        if a.kind == "window" then icon = app_icon(a.app) end
        local letter = a.kind == "web" and "W" or a.kind == "calc" and "=" or a.kind == "command" and "M" or a.kind == "window" and string.sub(tostring(a.app or name), 1, 1) or string.sub(name ~= "" and name or "?", 1, 1)
        local tag = a.tag or CMD.TAG[a.kind] or ""
        if a.kind == "ssh" then letter = ">" elseif a.kind == "pkg" then letter = a.source == "aur" and "A" or "P" elseif a.kind == "info" then letter = "…" end
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
        rows[i] = { i = i - 1, n = tostring(w.id), apps = table.concat(apps, " · "), id = w.id, empty = #apps == 0 }
    end
    model.un = rows
    -- D294: each workspace's windows, live, in its tile
    local pics = GX.pictures(list, N.thumbs, N.clients, 36)
    model.up = pics
    fact.nd_upic = #pics > 0
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
-- (D255) and in the style the look chose: digits, hands, words, binary, dots (lib/node/clockstyles)
local clock_str
local function clock_draw()
    local s = os.date("%H:%M")
    clock_str = s
    local t = os.date("*t")
    local style = N.look.clock_style or "pixel"
    if style == "pixel" then model.ck = CF.cells(s)
    elseif style == "digital" then text.nd_ckd = CS.digital(t.hour, t.min, true)
    elseif style == "analog" then local a = CS.analog(t.hour, t.min, 0); fact.nd_ckh, fact.nd_ckm = a.hour, a.minute
    -- the words round to the nearest five minutes at the half minute (10:02:30 is "five past"), so the seconds count
    elseif style == "words" then text.nd_ckw = CS.words(t.hour, t.min + (t.sec >= 30 and 1 or 0))
    elseif style == "binary" then
        local b = CS.binary(t.hour, t.min)
        for i = 1, 6 do fact["nd_cb" .. (i - 1)] = b.h[i] == true; fact["nd_cb" .. (i + 5)] = b.m[i] == true end
    elseif style == "dots" then local d = CS.dots(t.hour, t.min); fact.nd_ckdh, fact.nd_ckdm = d.hours, d.minutes end
end
every(5000, function()
    if N.look.seed ~= "clock" then clock_str = nil; return end
    -- words turn at the half minute; the others on the minute
    local key = N.look.clock_style == "words" and os.date("%H:%M") .. (tonumber(os.date("%S")) >= 30 and "+" or "") or os.date("%H:%M")
    if key ~= clock_str then clock_draw(); clock_str = key end
end)
N.clock_now = function() clock_str = nil; if N.look.seed == "clock" then clock_draw() end end
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

-- the studio (D229): what the node is shown as on its stage (the eighth chip tours them all), and what it shows
-- when nothing real is there to show
local PREVIEW = { "rest", "media", "notice", "volume", "workspaces", "panel", "launcher" }
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
    -- the long pill (D248): as wide as what it holds
    local form = LK.form(look, N.media.playing)
    fact.nd_long = ({ seed = 0, long = 1, notch = 2 })[form]   -- (D264: the form may follow the music)
    fact.nd_tra = -1   -- D311: where the Tray module is (set by the layouts below), none until one is laid out
    if form ~= "seed" and kind == "rest" and N.long_layout then
        local w = N.long_layout()
        shape.seed_w, shape.seed_h = w, 26
        -- the notch (D251) hangs from the top edge itself, and opens a little under the pointer
        if form == "notch" and not studio then shape.top = 0; shape.seed_h = N.near and 34 or 28 end
    end
    if studio then shape.top = 96 end
    if N.corner_layout then N.corner_layout() end
    -- D311: attached (a notch, or opened from a corner, with the frame on), what it opens grows down out of the
    -- notch itself — from the screen's top edge, in the frame's own fill and line — never a new island under it
    if kind == "rest" then N.from_corner = nil end
    local framed_now = N.settings.frame == nil or N.settings.frame.on ~= false
    local attached = framed_now and not studio and kind ~= "universe" and (form == "notch" or N.from_corner ~= nil)
    if attached then shape.top = 0 end
    fact.nd_att = attached and kind ~= "rest"
    fact.nd_fb = (type(N.settings.frame) == "table" and tonumber(N.settings.frame.band)) or 4
    local anchor = studio and "centre" or (N.from_corner or cfg().anchor or "centre")
    local data = { n = #N.ws.list, page = N.panel, notices = math.min(3, #N.notices) }
    -- at rest with something running, the seed is the time capsule
    local cap = (not studio and kind == "rest") and TK.capsule(N.time, wall()) or nil
    -- the music in the form the look chose (D246): a capsule, a visualiser strip, or a record (always round)
    local bkind = cap and "capsule" or kind
    if kind == "media" and look.music_form ~= "capsule" then bkind = "media_" .. look.music_form end
    local b = G.body(bkind, N.scr, anchor, shape, data)
    show_capsule(cap)
    -- leaning toward where the pointer came in from
    if N.near and not studio and kind ~= "rest" and kind ~= "universe" and not attached then b.x = math.max(0, math.min(N.scr.w - b.w, b.x + (N.lean or 0) * 24)) end
    -- out of a corner: flush with that side, as the corner notch is
    if attached and N.from_corner and kind ~= "rest" then b.x = N.from_corner == "left" and 0 or (N.scr.w - b.w) end
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
    -- D294: the galaxy's windows are copied live only while it is open: asked for on the way in, let go after
    if kind == "universe" and not N.gal_live then
        N.gal_live = true
        pcall(sys.call, "thumbnails.live", "all")
    elseif kind ~= "universe" and N.gal_live then
        N.gal_live = false
        pcall(sys.call, "thumbnails.live")
        pcall(sys.call, "thumbnails.want")
    end
    -- the spectrum is needed now (a music form, the seed's bars): the bar is asked for its feed at once
    if changed and N.wants_bands and N.wants_bands() then run("pleamar", { "--say", "mooi", "emit feed_want" }, function() end) end
    -- the keyboard only for what is opened to be typed into: the time panel, the player and a finish card never
    -- take it, so a timer that ends while you type steals no keys
    fact.nd_kb = studio or kind == "launcher" or kind == "universe" or (kind == "panel" and HM.typing(N.panel, N.hedit, N.hpick))
    set_body(b, changed and LK.overshoot(look) or 0)
    N.bx = b.x
    -- D257: a notch at rest is a piece of the frame's body (the frame draws it, joined to its band); the node
    -- only says where it is, and draws what is inside
    local framed = N.settings.frame == nil or N.settings.frame.on ~= false
    local notch = form == "notch" and kind == "rest" and not studio and framed
    fact.nd_nfr = notch
    -- D310: the corner notches are pieces of the frame's body too (joined to its top and its side), as the centre
    -- is; the node draws only what they hold
    fact.nd_cfr = framed and not studio
    local g = notch and { x = math.floor(b.x + 0.5), w = math.floor(b.w + 0.5), h = math.floor(b.h + 0.5), r = math.floor(math.min(14, b.h / 2 + 4)) } or {}
    if framed and not studio then
        if (fact.nd_lw or 0) > 0 then g.left = { w = fact.nd_lw, h = fact.nd_lh or 28 } end
        if (fact.nd_rw or 0) > 0 then g.right = { w = fact.nd_rw, h = fact.nd_rh or 28 } end
    end
    local geo = (g.x or g.left or g.right) and json.encode(g) or "{}"
    if geo ~= N.node_geo then N.node_geo = geo; pcall(sys.call, "files.write", "node-geo.json", geo) end
    if kind == "media" then show_media(b) end
    -- an opened card belongs to the notices: when they fold (something above them took the node) it is let go
    if kind ~= "notice" then N.nc_open = nil end
    if kind == "notice" then
        N.notice_list = (studio and #N.notices == 0) and SAMPLE_NOTICES or nil
        show_notices(b)
    end
    if kind == "workspaces" then show_rail(b) end
    if kind == "panel" then show_panel(b) end
    if kind == "launcher" then show_launcher(b) end
    if kind == "universe" then show_universe() end
    if kind == "time" then show_time() end
    if kind == "player" then show_media(b); if N.player_show then N.player_show() end end
    if kind == "done" then show_done() end
    if kind == "volume" then
        -- the gauge (D265): the last reading that grew it — the volume, the light, a mute, a lock, the cable
        local g = (not studio and N.gauge) or { icon = "󰕾", label = "VOLUME 60%", level = 0.6 }
        fact.nd_gv = math.max(0, math.min(1, tonumber(g.level) or 0))
        text.nd_vlabel, text.nd_gicon = g.label, g.icon
        fact.nd_gwarm = g.warm == true
    end
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
        if not was then react(false) end
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
    if on_for("workspaces") and before ~= N.ws.active and N.seen_ws then
        -- (D255) the switch shown in the look's way: from which side, and its number
        local plan = WFX.plan(N.look.ws_style, before, N.ws.active, #list)
        fact.nd_wsoff, text.nd_wsl = plan.offset, plan.label
        ST.push(N.st, "workspaces", now())
    end
    N.seen_ws = true
    render()
end)
-- ── the gauge (D265, Minflair's OSD): one reading at a time — what changed last is what it shows ──
local GA = require("lib/node/gauge")
local function gauge(g)
    if not on_for("volume") or not g then return end
    N.gauge = g
    ST.push(N.st, "volume", now())
end
N.gauge_show = gauge
pcall(sys.watch, "audio", function(a)
    if type(a) ~= "table" then return end
    local v, muted, mic = tonumber(a.volume), a.muted == true, a.input_muted == true
    -- D277: the outputs, for Home's switch; the one in use named beside the volume
    N.outputs = type(a.outputs) == "table" and a.outputs or {}
    for _, o in ipairs(N.outputs) do if type(o) == "table" and o.default then text.nd_hout = GA.short_output(o.name) end end
    if N.seen_audio then
        if v and N.vol and math.abs(v - N.vol) > 0.004 then gauge(GA.volume(v, muted))
        elseif muted ~= N.muted then gauge(GA.volume(v or 0, muted)) end
        if mic ~= N.mic_muted then gauge(GA.mic(mic)) end
    end
    N.vol, N.muted, N.mic_muted, N.seen_audio = v, muted, mic, true
    render()
end)
pcall(sys.watch, "brightness", function(b)
    if type(b) ~= "table" or b.present == false then return end
    local l = tonumber(b.level)
    if l and N.light and math.abs(l - N.light) > 0.004 then gauge(GA.light(l)) end
    N.light = l
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
    if type(b) ~= "table" or b.present == false then
        -- no battery: nothing of the last one kept, and a battery put back is a fresh start, not a crossing
        N.bat, N.charging, N.seen_bat = nil, false, false
        render()
        return
    end
    local before, was_charging = N.bat, N.charging
    N.bat, N.charging = tonumber(b.percent), b.charging == true
    if N.seen_bat and was_charging ~= N.charging then react(false); gauge(GA.cable(N.charging, N.bat)) end
    if N.bat and N.seen_bat and DV.crossed_critical(before, N.bat, N.charging) then battery_card(N.bat) end
    N.seen_bat = true
    render()
end)
pcall(sys.watch, "network", function(n)
    if type(n) ~= "table" then return end
    N.net = n
    N.online = n.online ~= false
    N.wifi_on = n.wifi == true
    N.wifi_name = tostring(n.name or (N.wifi_on and "Not connected" or "Off"))
    if N.panel == "wifi" then N.panel_shown = nil end
    render()
end)
pcall(sys.watch, "bluetooth", function(b)
    if type(b) ~= "table" then return end
    N.bts = b
    N.bt_on = b.powered == true
    if N.panel == "bluetooth" then N.panel_shown = nil end
    render()
end)
-- D311: the tray (the Tray module), its items' own pictures; a press, its menu (right) and its middle button
N.tray, N.tray_rows = {}, {}
pcall(sys.watch, "tray", function(list)
    N.tray = type(list) == "table" and list or {}
    local rows = {}
    for i, t in ipairs(N.tray) do
        if i > 10 then break end
        local name = tostring(t.title or t.id or "")
        rows[i] = { icon = tostring(t.icon or ""), iconed = tostring(t.icon or "") ~= "", title = name,
                    letter = string.upper(string.sub(string.match(name, "%w") or "?", 1, 1)) }
    end
    N.tray_rows = rows
    model.ltr = rows
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
        react(false)
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
-- D249: a short history of each reading, for the graphs
N.hist = { cpu = HI.new(40), mem = HI.new(40), temp = HI.new(40), gpu = HI.new(40) }
local function feed_now()
    local f = read("sigil-feed.json", "json")
    N.feed = type(f) == "table" and f or {}
    local r = type(N.feed.resources) == "table" and N.feed.resources or {}
    local function frac(v) v = tonumber(v); if not v then return nil end; return v <= 1 and v or v / 100 end
    if frac(r.cpu) then HI.push(N.hist.cpu, frac(r.cpu)) end
    if frac(r.mem) then HI.push(N.hist.mem, frac(r.mem)) end
    if tonumber(r.temp) then HI.push(N.hist.temp, math.min(1, tonumber(r.temp) / 100)) end
    render()
end
pcall(sys.watch, "files:sigil-feed.json", feed_now)
pcall(sys.watch, "files:settings.json", function()
    N.settings = config.parse(read("settings.json"), json.decode)
    paint()
    if N.show_identity then N.show_identity() end
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
on("nd_press", function(px)
    if N.studio.open then if N.studio_press then N.studio_press() end; return end
    local k = N.kind
    -- D311: at rest a press lands on the module under it (the workspaces, the notices, the clock, ...)
    if k == "rest" and not fact.nd_cap and tonumber(px) and N.module_act and N.module_act(model.lm, tonumber(px) - (N.bx or 0), 0) then return end
    if k == "launcher" or k == "universe" or k == "done" then return end
    -- a press on the panel's own body (not one of its controls) folds the time panel or the player away
    if k == "time" or k == "player" or k == "panel" then ST.release(N.st, k); render(); return end
    -- the music capsule pressed: it grows into the player (D236)
    if k == "media" then if N.open_player then N.open_player() end; return end
    if k == "rest" and fact.nd_cap then if N.open_time then N.open_time() end; return end
    -- at rest the pill itself opens the panel (D260); with music playing, a press on it stays the music's
    if k == "rest" then open_panel("home")
    elseif N.media.playing and k ~= "media" and on_for("media") then ST.push(N.st, "media", now())
    else open_panel("home") end
    render()
end)
on("nd_media", function(v)
    local c = math.floor(tonumber(v) or 0)
    pcall(sys.call, ({ [1] = "media.previous", [2] = "media.toggle", [3] = "media.next" })[c] or "media.toggle")
end)
-- the pointer over a card (row + 1) or gone (0): it opens to be read; leaving waits a moment, so moving from
-- one card to the next never folds them both
on("nd_ncx", function(v)
    v = math.floor(tonumber(v) or 0)
    N.ncx_gen = (N.ncx_gen or 0) + 1
    if v > 0 then
        if N.nc_open ~= v then N.nc_open = v; render() end
    else
        local g = N.ncx_gen
        after(160, function() if g == N.ncx_gen and N.nc_open then N.nc_open = nil; render() end end)
    end
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

-- ── the launcher ──
-- D268: packages (`pkg WORDS`) are asked of `mooi pkg search` once the typing rests, and the answer kept for that
-- query; SSH hosts come from ~/.ssh/config, read when the search line opens
N.pkg = { q = nil, rows = {}, busy = false }
local function search()
    local pq = PK.query(N.q)
    if pq then
        local rows = {}
        if N.pkg.q == pq and not N.pkg.busy then
            for _, r in ipairs(N.pkg.rows) do rows[#rows + 1] = r end
            if #rows == 0 then rows[1] = { kind = "info", name = "No package called “" .. pq .. "”", tag = "" } end
        else
            rows[1] = { kind = "info", name = "Looking for “" .. pq .. "” in the repositories and the AUR…", tag = "" }
        end
        N.results = rows
        N.sel = math.max(0, math.min(N.sel, #N.results - 1))
        return
    end
    local wd = read("widgets.json", "json")
    -- D311: nothing typed, the apps as a grid of their icons (twelve); typed, a list of six of everything
    local apps = WB.grid_apps(N.apps, type(wd) == "table" and wd.launch_counts or {}, N.q, N.q:match("%S") and 6 or 12)
    for _, a in ipairs(apps) do a.kind = a.kind or "app" end
    -- D234: mooi's own commands and the open windows, when something is typed
    if N.q:match("%S") then
        local cmds = CMD.match(N.q, 3)
        for _, h in ipairs(SSH.match(N.ssh_hosts, N.q, 2)) do cmds[#cmds + 1] = h end
        apps = CMD.merge(apps, cmds, CMD.windows(N.clients, N.q, 2), 6)
        -- D256: the last row searches the web for it (sent only if chosen)
        if #apps >= 6 then table.remove(apps) end
        apps[#apps + 1] = { kind = "web", name = "Search the web for “" .. N.q:gsub("^%s+", ""):gsub("%s+$", "") .. "”", query = N.q }
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
-- copied on wl-copy's input, never its command line: an argument is visible to every process and has a length
-- limit; `output = false`, since wl-copy stays to serve it (as the bar's clipboard does)
local function copy(text) run("wl-copy", {}, nil, { input = tostring(text or ""), output = false }) end
N.copy = copy
-- what a chosen row does: an app starts, a window comes forward, a command of mooi's runs, a sum is copied
-- (D268) one of mooi's own commands in the owner's terminal — a package installed or the system updated, where
-- the password and the confirmation are theirs. mooi by its full path: the terminal starts from Hyprland, which
-- has never heard of the repo's bin.
local function in_terminal(args)
    local okb, bin = pcall(sys.ask, "env", "MOOI_BIN")
    if not (okb and type(bin) == "string" and bin:match("^/[%w%._/%-]+$")) then
        local okh, home = pcall(sys.ask, "env", "HOME")
        bin = (okh and type(home) == "string" and home or "") .. "/Projects/mooi/bin/mooi"
        if not bin:match("^/[%w%._/%-]+$") then return end
    end
    for _, w in ipairs(args) do if not tostring(w):match("^[%w@%._%+%-]+$") then return end end
    with_terminal(function(t)
        local argv = t and TM.argv(t, { bin, table.unpack(args) })
        if argv then run("hyprctl", { "dispatch", HY.exec(table.concat(argv, " ")) }, function() end) end
    end)
end
local function choose(a)
    if not a then return end
    if a.kind == "window" then
        local d = HY.dispatch("focus", a.address)   -- the address checked, the expression built safely
        if d then run("hyprctl", { "dispatch", d }, function() end) end
    elseif a.kind == "command" and a.term then
        in_terminal(a.args)
    elseif a.kind == "command" then
        run("mooi", a.args, function() end)
    elseif a.kind == "ssh" and SSH.safe(a.host) then
        -- checked again here: the name is part of a shell line (Hyprland's exec)
        with_terminal(function(t)
            local argv = t and TM.argv(t, { "ssh", a.host })
            if argv then run("hyprctl", { "dispatch", HY.exec(table.concat(argv, " ")) }, function() end) end
        end)
    elseif a.kind == "pkg" and PK.safe_name(a.pkg) then
        in_terminal({ "pkg", "install", a.pkg, a.source == "aur" and "aur" or "repo" })
    elseif a.kind == "info" then
        return
    elseif a.kind == "calc" then
        copy(a.value)
    elseif a.kind == "web" then
        local q = tostring(a.query or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local enc = q:gsub("[^%w%-%._~]", function(ch) return string.format("%%%02X", string.byte(ch)) end)
        run("xdg-open", { "https://duckduckgo.com/?q=" .. enc }, function() end)
    else
        pcall(sys.call, "apps.launch", a.exec)
        -- D311: the Pill becomes the app's tile for a moment — its icon, large, in a rounded square — then folds
        model.lnch = { { icon = type(a.icon) == "string" and a.icon or "", iconed = type(a.icon) == "string" and a.icon ~= "",
                         letter = string.upper(string.sub(tostring(a.name or "?"), 1, 1)) } }
        text.nd_lname = tostring(a.name or "")
        ST.push(N.st, "launch", now())
    end
end
local function open_launcher()
    for _, k in ipairs(HELD) do ST.release(N.st, k) end
    ST.hold(N.st, "launcher")
    N.q, N.sel = "", 0
    text.nd_q = ""
    search()
    render()
    -- D268: the SSH hosts, for the same reason
    local okh, home = pcall(sys.ask, "env", "HOME")
    if okh and type(home) == "string" and home ~= "" then
        run("cat", { home .. "/.ssh/config" }, function(out, code) N.ssh_hosts = code == 0 and SSH.hosts(out) or {} end)
    end
    -- the open windows, for the search to find (a moment later is soon enough: nobody has typed yet)
    run("hyprctl", { "-j", "clients" }, function(out)
        local ok, c = pcall(json.decode, out or "")
        N.clients = ok and type(c) == "table" and c or {}
        if N.q:match("%S") then search(); render() end
    end)
end
local function pkg_search()
    local pq = PK.query(N.q)
    if not pq or (N.pkg.q == pq and not N.pkg.busy) then return end
    N.pkg = { q = pq, rows = {}, busy = true }
    local words = {}
    for w in pq:gmatch("%S+") do words[#words + 1] = w end
    run("mooi", { "pkg", "search", table.unpack(words) }, function(out)
        if N.pkg.q ~= pq then return end
        N.pkg = { q = pq, rows = PK.parse(out or "", 5, pq), busy = false }
        if N.kind == "launcher" then search(); render() end
    end)
end
on("text:nd_q", function(v)
    N.q = tostring(v or ""); N.sel = 0; search(); render()
    if PK.query(N.q) then local q = N.q; after(400, function() if N.q == q then pkg_search() end end) end
end)

-- ── the universe ──
-- D294: the windows' pictures, kept while they come (nothing is copied until the galaxy asks)
N.thumbs = {}
pcall(sys.watch, "thumbnails", function(t)
    N.thumbs = type(t) == "table" and type(t.list) == "table" and t.list or {}
    if N.kind == "universe" then show_universe() end
end)
local function open_universe()
    for _, k in ipairs(HELD) do ST.release(N.st, k) end
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
-- D311: what a module does when pressed (dir 0) or wheeled (1 up, -1 down) at x along its list. True when it
-- did something; false leaves the pill's own press (the panel) or wheel (the volume).
local function module_at(rows, rx)
    for _, m in ipairs(type(rows) == "table" and rows or {}) do
        if rx >= m.x - 7 and rx <= m.x + m.w + 7 then return m end
    end
    return nil
end
local function ws_step(dir)
    local list = N.ws.list
    for i, w in ipairs(list) do
        if w.id == N.ws.active then
            local to = list[math.max(1, math.min(#list, i - dir))]
            if to and to.id ~= w.id then go_workspace(to.id) end
            return
        end
    end
end
N.module_act = function(rows, rx, dir)
    local m = module_at(rows, rx)
    if not m then return false end
    local k = m.kind
    if dir ~= 0 then
        if k == 3 then ws_step(dir); return true end
        return false   -- the volume, anywhere else
    end
    if k == 3 then
        -- the dot pressed (Minflair's): each 6 wide every 11, the active one 18
        local a, best, bd = fact.nd_lmwa or 0, nil, 1e9
        for i = 0, math.min(10, #N.ws.list) - 1 do
            local cx = m.x + 8 + i * 11 + (i > a and 12 or 0) + (i == a and 9 or 3)
            if math.abs(rx - cx) < bd then best, bd = i, math.abs(rx - cx) end
        end
        local w = best and N.ws.list[best + 1]
        if w then go_workspace(w.id) end
        return true
    elseif k == 11 then run("mooi", { "drawer", "notices" }, function() end); return true
    elseif k == 14 then run("mooi", { "drawer", "notices" }, function() end); return true
    elseif k == 12 then open_launcher(); render(); return true
    elseif k == 15 or k == 4 then open_panel("power"); render(); return true
    elseif k == 1 or k == 6 then if N.open_time then N.open_time() end; return true
    elseif k == 5 then if N.open_player then N.open_player() end; return true
    elseif k == 9 then pcall(sys.call, "audio.mute"); return true
    elseif k == 13 then
        -- the tray: the item under it, activated (its menu when it has nothing to activate)
        local item = N.tray[math.floor((rx - m.x + 2) / 20) + 1]
        if item and not pcall(sys.call, "tray.activate", item.key) then pcall(sys.call, "tray.context", item.key) end
        return true
    end
    return false
end
-- a right press: a tray item's menu, wherever the Tray module stands
on("nd_rpress", function(v)
    v = math.floor(tonumber(v) or 0)
    if N.studio.open then return end
    local area = v // 10000
    local x = v % 10000
    local rows = area == 2 and model.lmr or area == 1 and model.lml or model.lm
    local rx = area == 2 and (x - ((N.scr and N.scr.w or 1920) - (fact.nd_rw or 0))) or area == 1 and x or (x - (N.bx or 0))
    local m = module_at(rows, rx)
    if m and m.kind == 13 then
        local item = N.tray[math.floor((rx - m.x + 2) / 20) + 1]
        if item then pcall(sys.call, "tray.context", item.key) end
    end
end)
-- the corners (D311): a press or the wheel over one, at x along it: its module, else the panel / the volume
on("nd_cpress", function(v)
    v = math.floor(tonumber(v) or 0)
    if N.studio.open then return end
    local right = v >= 20000
    local x = v % 10000
    local rows = right and model.lmr or model.lml
    local rx = right and (x - ((N.scr and N.scr.w or 1920) - (fact.nd_rw or 0))) or x
    -- what it opens grows out of this corner (D311)
    N.from_corner = right and "right" or "left"
    if not N.module_act(rows, rx, 0) then open_panel("home") end
    render()
end)
on("nd_cwheel", function(v)
    v = math.floor(tonumber(v) or 0)
    if N.studio.open or v == 0 then return end
    local dir = v > 0 and 1 or -1
    v = math.abs(v)
    local right = v >= 20000
    local x = v % 10000
    local rows = right and model.lmr or model.lml
    local rx = right and (x - ((N.scr and N.scr.w or 1920) - (fact.nd_rw or 0))) or x
    if not N.module_act(rows, rx, dir) then
        pcall(sys.call, "audio.volume", math.max(0, math.min(1, (N.vol or 0.5) + dir * 0.05)))
    end
end)
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
    if N.kind == "panel" then
        if v == 27 and N.panel == "home" and N.hedit then N.close_editor(); render()
        elseif v == 27 then ST.release(N.st, "panel"); render()
        elseif N.panel == "keys" and (v == 38 or v == 40) then N.ksc = N.ksc + (v == 38 and -1 or 1); show_keys(); render()
        elseif N.panel == "notes" and (v == 38 or v == 40) then
            N.npage = math.max(0, (N.npage or 0) + (v == 38 and -1 or 1))
            N.panel_shown = nil; render()
        end
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
        local step = N.lgrid and G.GRID_COLS or 1
        if v == 27 then ST.release(N.st, "launcher")
        elseif v == 38 then N.sel = math.max(0, N.sel - step)
        elseif v == 40 then N.sel = math.max(0, math.min(#N.results - 1, N.sel + step))
        elseif v == 9 or (N.lgrid and v == 39) then N.sel = math.max(0, math.min(#N.results - 1, N.sel + 1))
        elseif N.lgrid and v == 37 then N.sel = math.max(0, N.sel - 1)
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
    if on then react(true) end
    render()
end
local pv_busy = false
every(2000, function()
    -- a process that never answers does not stop the watch: after ten seconds it asks again
    if pv_busy and now() - (N.pv_since or 0) > 10000 then pv_busy = false end
    if cfg().privacy == false or pv_busy then
        if cfg().privacy == false and (N.mic_on or N.cam_on) then N.mic_on, N.cam_on = false, false; render() end
        return
    end
    pv_busy, N.pv_since = true, now()
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
local lyr_cur   -- the line last shown (forgotten with each new song, so its first lines are always written)
local function lyrics_now()
    local m = N.media
    local on = N.settings.node and N.settings.node.lyrics == true
    if not on or m.title == "" then N.lyr, N.lyr_key = nil, nil; fact.nd_lyon = false; return end
    local key = "remote:" .. tostring(m.artist) .. "\t" .. tostring(m.title)   -- as mooi's player keys a song
    if key == N.lyr_key then return end
    N.lyr_key, N.lyr, lyr_cur = key, nil, nil
    fact.nd_lyon = false
    fetch_lyrics(key, m.artist, m.title, "", math.floor((m.length or 0) + 0.5), nil, function(raw)
        if N.lyr_key ~= key then return end
        local lines = (type(raw) == "string" and raw ~= "none" and raw ~= "instrumental") and LY.parse(raw) or {}
        N.lyr = #lines > 0 and lines or nil
        fact.nd_lyon = N.lyr ~= nil
    end)
end
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
-- whether anything shown now draws the spectrum: the player, the music as a visualiser or a record, the seed's bars
local function wants_bands()
    if N.kind == "player" then return true end
    if N.kind == "media" and N.look.music_form ~= "capsule" then return true end
    if N.kind == "panel" and N.media.playing then return true end
    if N.kind == "rest" and N.media.playing and N.has_music_bars and N.has_music_bars() then return true end
    return N.kind == "rest" and N.look.seed_music == "bars" and N.media.playing
end
N.wants_bands = wants_bands
every(3000, function()
    if N.kind ~= "player" and wants_bands() then run("pleamar", { "--say", "mooi", "emit feed_want" }, function() end) end
end)
every(50, function()
    if not wants_bands() then return end
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
    local g, song = N.seek_gen, N.media.title
    -- and only the song it was meant for (a track that changed meanwhile is left where it is)
    after(120, function() if g == N.seek_gen and N.media.title == song then run(argv[1], { table.unpack(argv, 2) }, function() end) end end)
end)
on("nd_mt", function(v)
    v = math.floor(tonumber(v) or 0)
    -- meter * 2000 + its level 0 … 1000 (a stride of 2000, so a full meter is never the next one at zero)
    local m, f = v // 2000, math.min(1000, v % 2000) / 1000
    if m == 0 then
        -- shown at once; the audio system told at most every 40 ms, and always the last place
        fact.nd_vol = f
        N.vol_gen = (N.vol_gen or 0) + 1
        local g = N.vol_gen
        after(40, function() if g == N.vol_gen then pcall(sys.call, "audio.volume", f) end end)
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

-- ── a notice's life (D237): a line drains over it; the pointer resting on the node or on an opened card holds it ──
every(250, function()
    local ev = N.st.events.notice
    if N.kind ~= "notice" or not ev then return end
    if N.near or N.nc_open then ev.till = ev.till + 250 end
    fact.nd_ncl = math.max(0, math.min(1, (ev.till - now()) / ST.LIFE.notice))
end)

-- ── the long pill (D248): the modules the look chose, laid out left to right, the pill as wide as they are ──
N.awin = ""
local MOD_KIND = { clock = 1, window = 2, spaces = 3, battery = 4, music = 5, date = 6, cpu = 7, ram = 8,
                   volume = 9, weather = 10, notices = 11, logo = 12, tray = 13, status = 14, power = 15 }
-- D310/D311: each reading wears a small icon before its words, in the ink, as Minflair's and Noctalia's do
local MOD_ICON = { [2] = "󰖯", [6] = "󰃭", [7] = "󰻠", [8] = "󰍛", [9] = "󰕾", [10] = "󰖐", [11] = "󰂚", [12] = "󰣇", [15] = "⏻" }
local function battery_icon(p)
    if N.charging then return "󰂄" end
    local steps = { "󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹" }
    return steps[math.max(1, math.min(11, math.floor((p or 0) / 10) + 1))]
end
-- the weather the Nexus last read (nexus-weather.json), for the weather module
local function weather_word()
    local w = read("nexus-weather.json", "json")
    local cur = type(w) == "table" and type(w.answer) == "table" and w.answer.current or nil
    local t = type(cur) == "table" and tonumber(cur.temperature_2m)
    return t and (math.floor(t + 0.5) .. "°") or ""
end
-- the modules of one list laid out left to right from x = 14 (D295: the pill's own, or a corner notch's). D311,
-- Minflair's and Noctalia's: small ink icons and plain words, no meters; the workspaces as Minflair's dots (the
-- active one a pill, those with windows brighter); the logo (the launcher), the tray, the status icons (the
-- Control Center) and power. `area` (0 the pill, 1 the left corner, 2 the right) says where the tray is drawn.
local ICON_W = 16
local function lay_modules(list, area)
    local x, rows = 14, {}
    local f = type(N.feed.resources) == "table" and N.feed.resources or {}
    local function pct(v) v = tonumber(v); if not v then return nil end; return v <= 1 and v * 100 or v end
    local function words(t, most) return math.min(most, #t * 6 + 6) end
    for _, name in ipairs(LK.modules(list)) do
        local kind = MOD_KIND[name]
        local w, label, icon = 0, "", MOD_ICON[kind] or ""
        if kind == 1 then label = os.date("%H:%M"); w = 38
        elseif kind == 2 then label = N.awin ~= "" and N.awin or "Desktop"; w = ICON_W + words(label, 170)
        elseif kind == 3 then
            local n = math.min(10, #N.ws.list)
            local a = 0
            for i, ws in ipairs(N.ws.list) do
                if ws.id == N.ws.active then a = i - 1 end
                if i <= 10 then fact["nd_wu" .. (i - 1)] = (tonumber(ws.windows) or 1) > 0 end
            end
            fact.nd_lmws, fact.nd_lmwa = n, a
            if n > 0 then w = (n - 1) * 11 + 18 + 16 end
        elseif kind == 4 then
            if N.bat then label = math.floor(N.bat + 0.5) .. "%"; icon = battery_icon(N.bat); w = ICON_W + 30; fact.nd_lmbat = N.bat / 100 end
        elseif kind == 5 then
            if N.media.playing and N.media.title ~= "" then
                label = N.media.title
                local mm = N.look.music_mod or "bars"
                if mm == "bars" then w = 24 + words(label, 130)
                elseif mm == "cover" then w = 24 + words(label, 140)
                else w = 12 + words(label, 160) end
            end
        elseif kind == 6 then label = os.date("%a %d"); w = ICON_W + 42
        elseif kind == 7 then local c = pct(f.cpu); if c then label = math.floor(c + 0.5) .. "%"; w = ICON_W + 30 end
        elseif kind == 8 then local m = pct(f.mem); if m then label = math.floor(m + 0.5) .. "%"; w = ICON_W + 30 end
        elseif kind == 9 then
            if N.vol then label = math.floor(N.vol * 100 + 0.5) .. "%"; w = ICON_W + 30; if N.muted then icon = "󰖁" end end
        elseif kind == 10 then label = weather_word(); if label ~= "" then w = ICON_W + 28 end
        elseif kind == 11 then if #N.notices > 0 then label = tostring(#N.notices); w = ICON_W + 12 end
        elseif kind == 12 or kind == 15 then w = 16
        elseif kind == 13 then
            local n = #(N.tray_rows or {})
            if n > 0 then w = n * 20 - 4; fact.nd_tra, fact.nd_trx = area, x end
        elseif kind == 14 then w = 4 * 20 - 4
        end
        if w > 0 then rows[#rows + 1] = { kind = kind, x = x, w = w, label = label, icon = icon, lv = -1 }; x = x + w + 14 end
    end
    return rows, x
end
-- whether any list holds the Music module drawn as a visualiser (then the bands are asked for at rest)
N.has_music_bars = function()
    if (N.look.music_mod or "bars") ~= "bars" then return false end
    for _, side in ipairs({ "modules", "left", "right" }) do
        for _, k in ipairs(LK.modules(N.look[side])) do if k == "music" then return true end end
    end
    return false
end
N.long_layout = function()
    local rows, x = lay_modules(N.look.modules, 0)
    model.lm = rows
    return math.max(40, x - 2)
end
-- D295: the corner notches, each as wide as what it holds (none, none); laid out on every render. D310: each
-- opens a little under the pointer, as the centre does (28 → 34)
N.cnear = { left = false, right = false }
N.corner_layout = function()
    local lr, lx = lay_modules(N.look.left, 1)
    local rr, rx = lay_modules(N.look.right, 2)
    -- the status icons (Minflair's right corner): the Control Center, the notices, Wi-Fi, Bluetooth
    text.nd_sgw = (N.wifi_on and N.online ~= false) and "󰤨" or (N.wifi_on and "󰤯" or "󰤭")
    text.nd_sgb = N.bt_on and "󰂯" or "󰂲"
    fact.nd_sgn = #N.notices > 0
    model.lml, model.lmr = lr, rr
    fact.nd_lw = #lr > 0 and lx or 0
    fact.nd_rw = #rr > 0 and rx or 0
    fact.nd_lh = N.cnear.left and 34 or 28
    fact.nd_rh = N.cnear.right and 34 or 28
end
on("nd_corner", function(v)
    v = math.floor(tonumber(v) or 0)
    local side = (v >= 2) and "right" or "left"
    local near = v % 2 == 1
    if N.cnear[side] ~= near then N.cnear[side] = near; render() end
end)
-- what has the focus, while the long pill shows it (asked every second and a half, only then)
every(1500, function()
    if N.kind ~= "rest" or LK.form(N.look) == "seed" or N.studio.open then return end
    local want = false
    for _, k in ipairs(LK.modules(N.look.modules)) do if k == "window" then want = true end end
    if not want then return end
    run("hyprctl", { "-j", "activewindow" }, function(out)
        local ok, w = pcall(json.decode, out or "")
        local t = (ok and type(w) == "table" and type(w.class) == "string" and w.class ~= "") and tostring(w.title ~= "" and w.title or w.class) or ""
        if t ~= N.awin then N.awin = t; render() end
    end)
end)
-- the minute turning, while the long pill holds the clock
local long_min
every(5000, function()
    if N.kind ~= "rest" or LK.form(N.look) == "seed" then return end
    local m = os.date("%H:%M")
    if m ~= long_min then long_min = m; render() end
end)

-- the wheel over the node (D251): the volume, a twentieth a notch (the gauge shows it, as any change does)
on("nd_wheel", function(v)
    if N.studio.open then return end
    v = tonumber(v) or 0
    local dir = v > 0 and 1 or -1
    -- D311: the wheel over the workspaces switches them; anywhere else on the pill, the volume (as before)
    if N.kind == "rest" and math.abs(v) > 1 and N.module_act and N.module_act(model.lm, math.abs(v) - 1 - (N.bx or 0), dir) then return end
    local d = dir > 0 and 0.05 or -0.05
    local to = math.max(0, math.min(1, (N.vol or 0.5) + d))
    pcall(sys.call, "audio.volume", to)
end)

-- ── BMO as the seed (D253): the bar owns BMO and keeps his state in bmo-shared.json; the node only wears his face,
-- worked out the way the bar does (lib/bmostate, lib/pillface), quiet — no lines ──
local function bmo_show()
    if N.look.seed ~= "bmo" then return end
    local doc = read("bmo-shared.json", "json")
    local st = BMOST.normalise(type(doc) == "table" and doc or {}, os.time())
    local music = N.media.playing and N.media.title ~= ""
    local v = BMOST.view(st, os.time(), music)
    local f = PF.numbers(v.face)
    fact.pb_ew, fact.pb_eh, fact.pb_lid, fact.pb_brow, fact.pb_bron = f.ew, f.eh, f.lid, f.brow, f.bron
    fact.pb_tg = f.tg or 0
    fact.pb_sing = v.face == "singing"
    fact.pb_asleep = v.face == "asleep"
    fact.pb_sql, fact.pb_sqr, fact.pb_mc, fact.pb_mo, fact.pb_mw, fact.pb_bl = f.sql, f.sqr, f.mc, f.mo, f.mw, f.bl
end
N.bmo_show = bmo_show
pcall(sys.watch, "files:bmo-shared.json", bmo_show)
-- his face changes with time too (a reaction ends, he gets sleepy): looked at every ten seconds while he is the seed
every(10000, bmo_show)

-- ── the panel (D260): one body grown straight down out of the pill. Home holds what is happening now; the
-- pages its icon row reaches hold what the shelf and the branches used to, and each page keeps that row ──
N.panel = "home"
N.panel_sub, N.panel_items = "", {}
local PANEL_PAGES = { home = 0, calendar = 1, notes = 2, clipboard = 3, stash = 4, wallpaper = 5, system = 6, power = 7, wifi = 8, bluetooth = 9, keys = 10, weather = 11 }
local PANEL_TITLE = { calendar = "Calendar", notes = "Notes", clipboard = "Clipboard", stash = "Stash",
                      wallpaper = "Wallpaper", system = "System", power = "Power", wifi = "Wi-Fi", bluetooth = "Bluetooth", keys = "Shortcuts", weather = "Weather" }
local function ago(t) local s = os.time() - (tonumber(t) or 0); if s < 3600 then return math.max(1, s // 60) .. " min" elseif s < 86400 then return (s // 3600) .. " h" end; return (s // 86400) .. " d" end
local function dnd_state()
    local n = type(N.settings.notifications) == "table" and N.settings.notifications or {}
    return n.dnd ~= nil and n.dnd ~= "off"
end
-- the two radios' own state, from the services that already watch them (D263: no shell, no nmcli)
local function panel_state()
    local n = type(N.net) == "table" and N.net or {}
    N.wifi_on = n.wifi == true
    N.wifi_name = tostring(n.name or (N.wifi_on and "Not connected" or "Off"))
    N.bt_on = type(N.bts) == "table" and N.bts.powered == true or false
    if N.kind == "panel" then render() end
end

-- D285: who this machine is. The Nexus's own identity, and the hostname, on the card above Home's clock.
local HOME_FOLDER = tostring(sys.ask("files.folder") or "")
N.host = ""
N.show_identity = function()
    local nx = type(N.settings.nexus) == "table" and N.settings.nexus or {}
    local id = type(nx.identity) == "table" and nx.identity or {}
    local who = HM.identity(id.name, N.host, id.avatar)
    text.nd_hname, text.nd_hwho, text.nd_hinit = who.name, who.host, who.initial
    local function there(name)
        local ok, yes = pcall(sys.ask, "files.exists", name)
        return ok and yes == true
    end
    text.nd_face = HM.face(HOME_FOLDER, who.avatar, there)
    fact.nd_face_on = text.nd_face ~= ""
end
N.show_identity()
N.hedit, N.hn, N.hpick = false, "", false

local function close_editor()
    N.hedit, fact.nd_hedit, N.hn, text.nd_hn = false, false, "", ""
end
N.close_editor = close_editor

-- the file chooser is a normal window: while it is up the node's surface steps away, so the dialog is above
-- it and keeps the keyboard. Every path back from zenity gives the node back.
local function finish_pick()
    N.hpick, fact.nd_hpick = false, false
    render()
end

local function save_name()
    local name = HM.name(N.hn)
    if not name then return false end
    local before = read(SETTINGS_FILE, "json")
    if type(before) ~= "table" then return false end
    local after = SETTINGS.copy(before)
    after.nexus = type(after.nexus) == "table" and after.nexus or {}
    after.nexus.identity = type(after.nexus.identity) == "table" and after.nexus.identity or {}
    after.nexus.identity.name = name
    local doc = SETTINGS.save(sys, SETTINGS_FILE, before, after, function()
        local s, _, _, state = config.parse(read(SETTINGS_FILE), json.decode)
        if state == "broken" then return nil end
        return s
    end)
    if not doc then return false end
    N.settings = config.parse(read(SETTINGS_FILE), json.decode)
    N.show_identity()
    N.close_editor()
    render()
    return true
end

on("nd_hopen", function()
    N.hedit, fact.nd_hedit = true, true
    N.hn = text.nd_hname or ""
    text.nd_hn = N.hn
    render()
end)
on("text:nd_hn", function(v) N.hn = tostring(v or "") end)
on("nd_hsave", function() save_name() end)
on("nd_hdone", function() save_name() end)
on("nd_hpic", function()
    N.hpick, fact.nd_hpick = true, true
    render()
    local ok = pcall(run, "zenity", { "--file-selection", "--title=Choose your profile picture",
        "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.avif" }, function(out, code)
        finish_pick()
        local path = tostring(out or ""):gsub("%s+$", "")
        if code ~= 0 or path == "" then return end
        run("mooi", { "identity", "avatar", path }, function(_, done)
            if done ~= 0 then return end
            N.settings = config.parse(read(SETTINGS_FILE), json.decode)
            N.show_identity()
            render()
        end)
    end)
    if not ok then finish_pick() end
end)

pcall(run, "hostname", {}, function(out)
    N.host = (tostring(out or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    N.show_identity()
    render()
end)

local function show_panel_home(b)
    show_media(b)
    fact.nd_pgp = 0
    text.nd_pgt, text.nd_pgs = "", ""
    N.dnd_on = dnd_state()
    fact.nd_dnd_on = N.dnd_on
    fact.nd_wifi = N.wifi_on == true
    text.nd_wifin = N.wifi_name or "Off"
    fact.nd_bt = N.bt_on == true
    local cap = TK.capsule(N.time, wall())
    fact.nd_tmr_on = cap ~= nil
    if cap then text.nd_capt = cap.text end
    local rows, idx = {}, {}
    for i, n in ipairs(N.notices) do
        if i > 3 then break end
        rows[i] = { icon = "󰂚", app = string.upper(tostring(n.app or "MOOI")), title = tostring(n.title or ""), age = ago(n.time) }
        idx[i] = i   -- each row is its own notice in the feed's order (nd_nc looks them up here)
    end
    N.notice_rows = idx
    model.pn = rows
    fact.nd_ncn = #rows
    fact.nd_vol = N.vol or 0
    -- D272: the header — the time, the date, the weather and the battery — and a strip of the machine's readings
    text.nd_hclock = os.date("%H:%M")
    text.nd_hdate = HM.date(os.time())
    local w = read("nexus-weather.json", "json")
    text.nd_hwg, text.nd_hwt = HM.weather_line(type(w) == "table" and type(w.answer) == "table" and w.answer.current or nil)
    text.nd_hbat = HM.battery(N.bat, N.charging)
    local f = type(N.feed.resources) == "table" and N.feed.resources or {}
    local function pct(v) v = tonumber(v); if not v then return nil end; return v <= 1 and v * 100 or v end
    local cpu, mem, temp = pct(f.cpu), pct(f.mem), tonumber(f.temp)
    local strip = {
        { HM.reading("CPU", cpu), (cpu or 0) / 100, (cpu or 0) > 85 },
        { HM.reading("RAM", mem), (mem or 0) / 100, (mem or 0) > 90 },
        { HM.reading("TEMP", temp, "°"), math.min(1, (temp or 0) / 100), (temp or 0) > 85 },
        { HM.reading("GPU", N.gpu), (N.gpu or 0) / 100, (N.gpu or 0) > 90 },
    }
    fact.nd_hstrip = on_for("system")   -- D274: Settings → Bar & Pill → Readings on Home
    for i, it in ipairs(strip) do
        text["nd_hs" .. i] = it[1]
        fact["nd_hf" .. i] = math.max(0, math.min(1, it[2]))
        fact["nd_hh" .. i] = it[3]
    end
    -- the light from its own service (D265's watch), so the slider is there whether or not the player has opened
    fact.nd_hasbri = N.light ~= nil
    if N.light and not N.bri_drag then fact.nd_bri = N.light end
    -- game mode (D266): on while its file is there
    N.game = read("game-mode.json") ~= nil
    fact.nd_game = N.game
end

local function show_calendar()
    local now = os.date("*t")
    N.cal = N.cal or { y = now.year, m = now.month }
    local mo = CAL.month(N.cal.y, N.cal.m, { y = now.year, m = now.month, d = now.day })
    local rows = {}
    for i, c in ipairs(mo.cells) do rows[i] = { d = tostring(c.day), muted = not c.cur, today = c.today, weekend = c.weekend } end
    model.cal = rows
    N.panel_sub = string.upper(mo.title)
end
-- D287: the week's weather page, from the Nexus's cached forecast: today now, then the days on one range
local WEATHER_FILE = "nexus-weather.json"
local function show_weather_week()
    local wk = WEEK.week(read(WEATHER_FILE, "json"))
    if not wk then
        model.wkw = {}
        text.nd_wtemp, text.nd_wword, text.nd_wglyph, text.nd_wfeels = "", "", "", ""
        text.nd_whum, text.nd_wwind, text.nd_wcity, text.nd_wsum = "", "", "", ""
        N.panel_sub = "NO FORECAST YET"
        return
    end
    local now = wk.now or {}
    text.nd_wtemp = now.temp or ""
    text.nd_wword = now.word or ""
    text.nd_wglyph = now.glyph or "󰖐"
    text.nd_wfeels = now.feels or ""
    text.nd_whum = now.humidity or ""
    text.nd_wwind = now.wind or ""
    text.nd_wcity = string.upper(wk.city or "")
    text.nd_wsum = wk.summary or ""
    model.wkw = wk.rows
    N.panel_sub = (wk.city ~= "" and string.upper(wk.city) .. " · " or "") .. "THIS WEEK"
end
-- D279: the page's changes go to the bar the same way a new note does — an inbox file in mooi's
-- own data folder, never a command line. Then the page asks again once the bar has had its moment.
local function inbox_add(name, entry)
    local box = read(name, "json")
    box = type(box) == "table" and box or {}
    box[#box + 1] = entry
    pcall(sys.call, "files.write", name, json.encode(box))
end
local function inbox_refresh(page)
    after(400, function() if N.panel == page then N.panel_shown = nil; render() end end)
end
local function show_notes()
    local list = NOTES.decode(read("notes.json", "json"))
    table.sort(list, function(a, b)
        if a.pinned ~= b.pinned then return a.pinned end
        if a.time ~= b.time then return a.time > b.time end
        return a.id > b.id
    end)
    local cards, page = NOTES.slice(list, N.npage or 0, 6)
    N.npage = page
    local rows = {}
    N.panel_items = {}
    for i, n in ipairs(cards) do
        local first, rest = NOTES.split(n.text)
        rows[i] = { id = n.id, title = first, rest = rest, more = rest ~= "", age = ago(n.time), pinned = n.pinned, tag = n.tag or 0 }
        N.panel_items[i] = n.text
    end
    model.ncard = rows
    N.panel_sub = #list .. " NOTES"
end
local function show_stash()
    local items = STASH.decode(read("stash.json", "json"))
    table.sort(items, function(a, b) return (a.time or 0) > (b.time or 0) end)
    local rows = {}
    N.panel_items = {}
    for i, it in ipairs(items) do
        if i > 6 then break end
        rows[i] = { id = it.id, icon = STASH.glyph(it.kind), name = it.name,
                    detail = it.detail ~= "" and it.detail or ago(it.time) }
        N.panel_items[i] = it.url
    end
    model.stz = rows
    N.panel_sub = #items == 0 and "NOTHING KEPT YET" or (#items .. " KEPT")
end
-- D307: the favourites every switcher shares (lib/walls FAVS); "♥ Favs" shows only them
local WALLS = require("lib/walls")
N.wl_favs = WALLS.favs(read(WALLS.FAVS, "json"))
local function wl_list()
    if not N.wl_favonly then return N.walls or {} end
    local out = {}
    for _, it in ipairs(N.walls or {}) do if N.wl_favs[it.path] then out[#out + 1] = it end end
    return out
end
N.wl_list = wl_list
pcall(sys.watch, "files:" .. WALLS.FAVS, function()
    N.wl_favs = WALLS.favs(read(WALLS.FAVS, "json"))
    if N.panel == "wallpaper" then N.panel_shown = nil; render() end
end)
local function show_walls()
    if not N.walls then
        local idx = read("walls-index.json", "json")
        N.walls = {}
        for _, it in ipairs(type(idx) == "table" and type(idx.items) == "table" and idx.items or {}) do
            if type(it.path) == "string" and type(it.thumb) == "string" then N.walls[#N.walls + 1] = it end
        end
        local cur = read("wall.json", "json")
        local src = type(cur) == "table" and cur.source or ""
        N.wl_at = 1
        -- (D273) on the page of nine that holds the one you wear
        for i, it in ipairs(N.walls) do if it.path == src then N.wl_at = ((i - 1) // 9) * 9 + 1 end end
        N.wl_worn = src
    end
    local list = wl_list()
    if N.wl_at > #list then N.wl_at = 1 end
    local rows = {}
    for k = 0, 8 do
        local it = list[N.wl_at + k]
        if it then
            local name = tostring(it.path):match("([^/]+)$") or ""
            rows[#rows + 1] = { img = it.thumb, on = it.path == N.wl_worn, name = (name:gsub("%.[%w]+$", "")), fav = N.wl_favs[it.path] == true }
        end
    end
    model.wl = rows
    fact.nd_wlfav = N.wl_favonly == true
    local pages = math.max(1, math.ceil(#list / 9))
    local what = N.wl_favonly and " FAVOURITES" or " PICTURES"
    N.panel_sub = (#list > 0) and ("PAGE " .. ((N.wl_at - 1) // 9 + 1) .. " OF " .. pages .. "  ·  " .. #list .. what)
        or (N.wl_favonly and "NO FAVOURITES YET · THE ♥ ON A PICTURE ADDS IT" or "NO PICTURES INDEXED YET")
end
local function show_clipboard()
    N.panel_items = {}
    run("cliphist", { "list" }, function(out, code)
        if N.panel ~= "clipboard" then return end
        local list = code == 0 and CH.parse(out, 7) or {}
        local rows = {}
        for i, e in ipairs(list) do
            rows[i] = { label = e.label, detail = e.kind == "text" and "" or string.upper(e.kind), pinned = false }
            N.panel_items[i] = e.id
        end
        model.br = rows
        N.panel_sub = code ~= 0 and "CLIPHIST IS NOT RUNNING" or (#list == 0 and "NOTHING COPIED YET" or "A PRESS PUTS ONE BACK")
        render()
    end)
end
N.clip_choose = function(i)
    local argv = CH.decode_args(N.panel_items[i])
    if not argv then return end
    run(argv[1], { table.unpack(argv, 2) }, function(out, code)
        if code == 0 and out then run("wl-copy", {}, nil, { input = out, output = false }) end
    end)
end
local function strength_bars(s)
    s = tonumber(s) or 0
    if s > 1 then s = s / 100 end
    return math.max(0, math.min(4, math.floor(s * 4 + 0.5)))
end
-- Wi-Fi (D263): what the network service sees — the one in use, then the ones in reach. Joining a new secure
-- network asks for its password here; it goes only to the service, never to a command line or a file.
local function show_wifi()
    local n = type(N.net) == "table" and N.net or {}
    local nets = type(n.networks) == "table" and n.networks or {}
    local active = tostring(n.name or "")
    fact.nd_won = n.wifi == true
    text.nd_wname = active ~= "" and active or (fact.nd_won and "Not connected" or "Off")
    fact.nd_wbars = strength_bars(n.strength)
    fact.nd_wsec = false
    N.wifi_rows = {}
    local rows = {}
    for i, net in ipairs(nets) do
        local ssid = tostring(net.ssid or "")
        if net.active or ssid == active then fact.nd_wbars, fact.nd_wsec = strength_bars(net.strength), net.secure == true end
        if i <= 8 then
            rows[i] = { name = ssid, bars = strength_bars(net.strength), secure = net.secure == true,
                        known = net.known == true, on = net.active == true or ssid == active }
            N.wifi_rows[i] = net
        end
    end
    model.nw = rows
    local err = tostring(n.error or "none")
    text.nd_werr = err ~= "none" and err or ""
    fact.nd_werron = err ~= "none"
    N.panel_sub = #nets .. " IN REACH"
end
-- Bluetooth (D263): the adapter, the device in use, then the ones it knows or sees
local function show_bluetooth()
    local b = type(N.bts) == "table" and N.bts or {}
    fact.nd_btp = b.present ~= false
    fact.nd_btpw = b.powered == true
    fact.nd_btdis = b.discovering == true
    local devs, connected = {}, nil
    for _, d in ipairs(type(b.devices) == "table" and b.devices or {}) do
        if d.connected then connected = d end
        devs[#devs + 1] = d
    end
    table.sort(devs, function(x, y)
        if (x.connected == true) ~= (y.connected == true) then return x.connected == true end
        if (x.paired == true) ~= (y.paired == true) then return x.paired == true end
        return tostring(x.name or "") < tostring(y.name or "")
    end)
    text.nd_bth = connected and tostring(connected.name or connected.address or "Connected") or (fact.nd_btpw and "On" or "Off")
    fact.nd_btbat = connected and tonumber(connected.battery) or -1
    if fact.nd_btbat and fact.nd_btbat < 0 then fact.nd_btbat = -1 end
    N.bt_rows = {}
    local rows = {}
    for i, d in ipairs(devs) do
        if i > 8 then break end
        local detail = d.connected and "CONNECTED" or d.paired and "PAIRED" or ""
        local bat = tonumber(d.battery)
        if bat and bat >= 0 and detail == "" then detail = math.floor(bat * 100 + 0.5) .. "%" end
        rows[i] = { name = tostring(d.name or d.address or "Device"), detail = detail, on = d.connected == true, paired = d.paired == true }
        N.bt_rows[i] = d
    end
    model.bt = rows
    N.panel_sub = #devs .. " DEVICES"
end
-- power (D256): each needs a second press within three seconds, as on the lock; nothing here ends a session by a slip
local POWER = { { label = "Lock", argv = { "mooi", "lock" } }, { label = "Sleep", argv = { "systemctl", "suspend" } },
                { label = "Reboot", argv = { "systemctl", "reboot" } }, { label = "Power off", argv = { "systemctl", "poweroff" } } }
N.armed, N.armed_at = nil, 0
local function show_power()
    local rows = {}
    for i, p in ipairs(POWER) do
        local armed = N.armed == i and now() - N.armed_at < 3000
        rows[i] = { label = p.label, detail = armed and "PRESS AGAIN" or "", pinned = armed }
    end
    model.br = rows
    N.panel_sub = "TWO PRESSES"
end
N.power_choose = function(i)
    local p = POWER[i]
    if not p then return end
    if N.armed == i and now() - N.armed_at < 3000 then
        N.armed = nil
        for _, h in ipairs(HELD) do ST.release(N.st, h) end
        render()
        run(p.argv[1], { table.unpack(p.argv, 2) }, function() end)
    else
        N.armed, N.armed_at = i, now()
        after(3100, function() if N.panel == "power" then show_power(); render() end end)
    end
end
-- the shortcut sheet (D267; k4's and Minflair's Super+K): what Hyprland has bound now, in words. The binds are
-- Hyprland's answer; the words are the config's own comments and mooi's names (lib/node/keysheet), read each time
-- the page opens, so a key changed a minute ago is shown as it is.
N.kq, N.ksc, N.krows = "", 0, {}
local KEYS_SHOWN = 10
show_keys = function()
    local rows = KS.filter(N.krows, N.kq)
    N.ksc = math.max(0, math.min(N.ksc, #rows - KEYS_SHOWN))
    local out = {}
    for i = 1, KEYS_SHOWN do
        local r = rows[N.ksc + i]
        if r then out[i] = { keys = r.keys, what = r.what } end
    end
    model.kb = out
    fact.nd_kmore = math.max(0, #rows - N.ksc - KEYS_SHOWN)
    N.panel_sub = (#rows == #N.krows and #rows or (#rows .. " OF " .. #N.krows)) .. " SHORTCUTS"
    text.nd_pgs = N.panel_sub
end
local function load_keys()
    local binds, words = nil, nil
    local function both()
        if not (binds and words) then return end
        N.krows = KS.rows(binds, words)
        if N.panel == "keys" then show_keys(); render() end
    end
    run("hyprctl", { "binds", "-j" }, function(out, code)
        local ok, b = pcall(json.decode, out or "")
        binds = (code == 0 and ok and type(b) == "table") and b or {}
        both()
    end)
    run("mooi", { "keys-text" }, function(out)
        local name = function(c) return KS.mooi_name(c, DESK.ACTIONS) end
        local w = KS.words(out or "", name)
        -- mooi's chosen keys, as it hands them to Hyprland (lib/desktop's file, in this same data folder)
        KS.words(read("hypr.lua") or "", name, w)
        words = w
        both()
    end)
end
local PANEL_SHOW = { calendar = show_calendar, notes = show_notes, clipboard = show_clipboard, stash = show_stash,
                     wallpaper = show_walls, power = show_power, wifi = show_wifi, bluetooth = show_bluetooth, keys = show_keys,
                     weather = show_weather_week }
show_panel = function(b)
    local pg = PANEL_PAGES[N.panel] or 0
    if pg == 0 then show_panel_home(b); return end
    fact.nd_pgp = pg
    text.nd_pgt = PANEL_TITLE[N.panel] or ""
    N.panel_sub = N.panel_sub or ""
    if N.panel_shown ~= N.panel then
        N.panel_shown = N.panel
        local f = PANEL_SHOW[N.panel]
        if f then f() end
    end
    text.nd_pgs = N.panel_sub or ""
    if N.panel == "system" then show_system(b) end
    if N.panel == "wifi" then show_wifi() end
    if N.panel == "bluetooth" then show_bluetooth() end
end
open_panel = function(page)
    for _, k in ipairs(HELD) do ST.release(N.st, k) end
    N.panel = PANEL_PAGES[page] and page or "home"
    N.panel_sub, N.panel_shown = "", nil
    if N.panel == "notes" then text.nd_nq = ""; N.npage = 0 end
    if N.panel == "home" then N.close_editor() end
    if N.panel == "stash" then N.sclear, fact.nd_sclear = nil, false end
    if N.panel == "keys" then N.kq, N.ksc, text.nd_kq = "", 0, ""; load_keys() end
    if (N.panel == "system" or N.panel == "home") and N.poll_extra then N.poll_extra() end
    if N.panel == "wifi" then N.wifi_ssid, fact.nd_wsel, text.nd_wpw, fact.nd_werron = "", 0, "", false end
    ST.hold(N.st, "panel")
    panel_state()
    if N.panel == "wifi" and N.wifi_on then pcall(sys.call, "network.scan") end
    if N.media.playing then run("pleamar", { "--say", "mooi", "emit feed_want" }, function() end) end
    render()
end
N.open_panel, N.close_panel = open_panel, function() ST.release(N.st, "panel"); render() end
-- D287: a new forecast while the week's page is open is shown at once
pcall(sys.watch, "files:nexus-weather.json", function()
    if N.kind == "panel" and N.panel == "weather" then N.panel_shown = nil; render() end
end)

-- ── the GPU and the disk (D270): asked every two seconds, only while the System page is open. The GPU's source is
-- found once — the kernel's busy file of the first card that has one, else nvidia-smi — and kept ──
local function poll_extra()
    local okh, home = pcall(sys.ask, "env", "HOME")
    if okh and type(home) == "string" and home:match("^/") then
        run("df", { "-P", home }, function(out, code)
            N.disk = code == 0 and SX.disk(out) or nil
        end)
    end
    local function got(v) N.gpu = v; if v then HI.push(N.hist.gpu, v / 100) end; if N.panel == "system" and N.kind == "panel" then render() end end
    if N.gpu_src == "none" then return end
    if N.gpu_src == "nvidia" then
        run("nvidia-smi", SX.NVIDIA, function(out, code) got(code == 0 and SX.busy(out) or nil) end)
    elseif N.gpu_src then
        run("cat", { N.gpu_src }, function(out, code) got(code == 0 and SX.busy(out) or nil) end)
    else
        local i = 0
        local function try()
            i = i + 1
            local path = SX.BUSY[i]
            if not path then
                run("nvidia-smi", SX.NVIDIA, function(out, code)
                    local v = code == 0 and SX.busy(out) or nil
                    N.gpu_src = v and "nvidia" or "none"
                    got(v)
                end)
                return
            end
            run("cat", { path }, function(out, code)
                local v = code == 0 and SX.busy(out) or nil
                if v then N.gpu_src = path; got(v) else try() end
            end)
        end
        try()
    end
end
N.poll_extra = poll_extra
-- (D272: Home shows the GPU too, and its clock turns with the minute while it is open)
every(2000, function() if N.kind == "panel" and (N.panel == "system" or N.panel == "home") then poll_extra() end end)
every(15000, function() if N.kind == "panel" and N.panel == "home" then render() end end)

-- ── a reading pressed (D249): btop, in the owner's terminal — the first of the usual ones that answers, found
-- once by asking each its version (no shell), and started through Hyprland so it is a window like any other ──
local TERMS = { "kitty", "foot", "alacritty", "wezterm", "ghostty", "konsole", "xterm" }
with_terminal = function(go)
    if N.term then go(N.term); return end
    local i = 0
    local function try()
        i = i + 1
        local t = TERMS[i]
        -- none answered: nothing remembered, so a terminal installed later is found on the next press
        if not t then N.term = nil; go(nil); return end
        -- xterm answers only its own single-dash flag
        run(t, { t == "xterm" and "-version" or "--version" }, function(_, code) if code == 0 then N.term = t; go(t) else try() end end)
    end
    try()
end
on("nd_sys", function(v)
    -- the processor, the memory, the heat and (D270) the GPU; the network, the battery and the disk open nothing
    local row = math.floor(tonumber(v) or -1) + 1
    if row < 1 or (row > 3 and row ~= 6) then return end
    with_terminal(function(t)
        local argv = t and TM.argv(t, { "btop" })
        if not argv then return end
        run("hyprctl", { "dispatch", HY.exec(table.concat(argv, " ")) }, function() end)
        for _, h in ipairs(HELD) do ST.release(N.st, h) end
        render()
    end)
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
        react(true)
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
    liquid = "An orb of glass: it wobbles and leaves a trail",
    neon = "A comet in a tube of light: bright, quick, and it throws sparks",
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
    -- D257: the module editor, on the Rest page
    if tab == "Pill" then
        local inl, has, rest = {}, {}, {}
        fact.nd_mside = ({ modules = 0, left = 1, right = 2 })[N.mod_side or "modules"] or 0
        for i, k in ipairs(LK.modules(N.look[N.mod_side or "modules"])) do inl[i] = { label = string.upper(LK.MODULE_NAMES[k]) }; has[k] = true end
        N.mod_rest = {}
        for _, k in ipairs(LK.MODULES) do
            if not has[k] then rest[#rest + 1] = { label = string.upper(LK.MODULE_NAMES[k]) }; N.mod_rest[#N.mod_rest + 1] = k end
        end
        model.md, model.ma = inl, rest
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
    local k = studio_kind()
    if k == "launcher" then N.q, N.sel = "", 0; text.nd_q = ""; search() end
    if k == "panel" then N.panel = "home" end   -- the panel on its home page (D260)
end
local function open_studio()
    for _, k in ipairs(HELD) do ST.release(N.st, k) end
    pcall(math.randomseed, os.time())
    -- the pointer is not followed on the stage: forget where it was, so nothing waits on it after
    N.pointer, N.near, N.lean, N.pointer_due = nil, false, 0, nil
    N.ix = IX.new()
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
on("nd_md", function(v)
    v = math.floor(tonumber(v) or -1)
    local done
    local side = N.mod_side or "modules"
    if v >= 100 then done = LK.module_add(N.look, (N.mod_rest or {})[v - 99], side)
    elseif v >= 0 then
        local i, op = v // 10 + 1, v % 10
        if op == 1 then done = LK.module_move(N.look, i, -1, side)
        elseif op == 2 then done = LK.module_move(N.look, i, 1, side)
        elseif op == 9 then done = LK.module_remove(N.look, i, side) end
    end
    if done then
        -- the stage shows the pill as it is now
        N.studio.pv = 0
        look_changed()
    end
end)
-- D295: which list the module editor edits — the pill's own, the left corner's or the right's
on("nd_mside", function(v)
    N.mod_side = ({ [0] = "modules", [1] = "left", [2] = "right" })[math.floor(tonumber(v) or 0)] or "modules"
    studio_rows()
    render()
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
    N.studio.pv = (N.studio.pv + 1) % (#PREVIEW + 1)   -- the seven states, then the tour, then rest again
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
    -- this program's own write is known by what it says (a failed write leaves nothing to mistake for it)
    local raw = read(LK.FILE)
    if raw ~= nil and raw == N.saved_text then return end
    local slots = N.look.slots
    N.look = look_now()
    -- a hand edit that leaves the saved looks out keeps them
    local doc = read(LK.FILE, "json")
    if type(doc) ~= "table" or doc.slots == nil then N.look.slots = slots end
    apply_look()
    if N.studio.open then studio_rows() end
    render()
end)

-- ── `mooi node …`: Super wakes it; the launcher; the universe; the studio ──
on("nd_cmd", function(v)
    v = math.floor(tonumber(v) or 0)
    if N.studio.open and v ~= 4 then close_studio(); return end
    if v == 1 then
        -- Super: what is open folds away; at rest, the panel grows out of the pill (D260)
        if N.kind ~= "rest" then for _, k in ipairs(HELD) do ST.release(N.st, k) end; render()
        else open_panel("home") end
    elseif v == 2 then
        if ST.held(N.st, "launcher") then ST.release(N.st, "launcher"); render() else open_launcher() end
    elseif v == 3 then
        if ST.held(N.st, "universe") then ST.release(N.st, "universe"); render() else open_universe() end
    elseif v == 4 then
        if N.studio.open then close_studio() else open_studio() end
    elseif v == 5 then
        if ST.held(N.st, "time") then ST.release(N.st, "time"); render() else open_time() end
    elseif v == 6 then
        -- the shortcut sheet (D267): Super+K again lets it go
        if ST.held(N.st, "panel") and N.panel == "keys" then ST.release(N.st, "panel"); render() else open_panel("keys") end
    elseif v == 7 then
        -- D311: the Power module: the panel's power page
        if ST.held(N.st, "panel") and N.panel == "power" then ST.release(N.st, "panel"); render() else open_panel("power") end
    elseif v == 8 then
        -- D311: the Status module: the Control Center out of the frame's right side (D299)
        run("mooi", { "drawer", "notices" }, function() end)
    end
end)

-- ── `mooi osd …` (D265): what has no service of its own — a lock key's light, game mode — told to the gauge ──
on("nd_osd", function(v) gauge(GA.decode(v)); render() end)
-- D277: Home's output name pressed — the next output plays, and the gauge says which
on("nd_out", function()
    local o = GA.next_output(N.outputs)
    if not o or o.default then return end
    pcall(sys.call, "audio.default", o.id)
    gauge(GA.output(o.name))
    render()
end)

-- D306: anything thrown onto the Pill — whatever it is showing — goes into the stash (the bar's, through its
-- inbox, which copies files as a drop on the stash itself does). Pleamar gives a drop to the zone under the
-- pointer, so every zone the Pill draws listens.
local function thrown(data)
    local got = {}
    if type(data) == "table" then
        for _, v in ipairs(data) do if type(v) == "string" and v ~= "" then got[#got + 1] = v end end
    elseif type(data) == "string" then
        for line in string.gmatch(data, "[^\r\n]+") do
            line = string.gsub(string.gsub(line, "^%s+", ""), "%s+$", "")
            if line ~= "" and string.sub(line, 1, 1) ~= "#" then got[#got + 1] = line end
        end
    end
    if #got == 0 then return end
    for _, raw in ipairs(got) do inbox_add("stash-inbox.json", raw) end
    if N.panel == "stash" then inbox_refresh("stash") end
    gauge(GA.stashed(#got))
    render()
end
for _, z in ipairs(require("lib/node/zones")) do on("drop:" .. z, thrown) end

-- D287: Home's weather, pressed, opens the week's page in the same panel
on("nd_hweather", function() open_panel("weather") end)
-- ── the panel's own input (D260): its pages, its four toggles, its notices and the way home ──
on("nd_pg", function(v)
    v = math.floor(tonumber(v) or 0)
    if v == 7 then open_panel("wifi")
    elseif v == 8 then open_panel("bluetooth")
    elseif v == 9 then
        for _, k in ipairs(HELD) do ST.release(N.st, k) end
        render()
        run("mooi", { "settings" }, function() end)
    elseif v == 10 then
        for _, k in ipairs(HELD) do ST.release(N.st, k) end
        render()
        run("mooi", { "nexus" }, function() end)
    elseif v == 11 then open_panel("power")
    else
        local page = ({ [0] = "home", [1] = "calendar", [2] = "notes", [3] = "clipboard", [4] = "stash", [5] = "wallpaper", [6] = "system" })[v]
        if page then open_panel(page) end
    end
end)
on("nd_ptog", function(v)
    v = math.floor(tonumber(v) or 0)
    if v == 1 then
        N.wifi_on = not (N.wifi_on == true)
        pcall(sys.call, "network.wifi", N.wifi_on)
        if N.wifi_on then pcall(sys.call, "network.scan") end
        render()
    elseif v == 2 then
        N.dnd_on = not dnd_state()
        fact.nd_dnd_on = N.dnd_on
        run("pleamar", { "--say", "mooi", "emit note_dnd" }, function() end)
        render()
    elseif v == 3 then
        for _, k in ipairs(HELD) do ST.release(N.st, k) end
        open_time()
    elseif v == 4 then
        N.bt_on = not (N.bt_on == true)
        pcall(sys.call, "bluetooth.power", N.bt_on)
        render()
    elseif v == 5 then
        -- D272: game mode from Home; the gauge says which way it went, and the button follows the file
        N.game = not N.game
        fact.nd_game = N.game
        run("mooi", { "game-mode" }, function() if N.kind == "panel" then render() end end)
    end
end)
-- the radios' pages (D263): join, forget, look again; connect or leave a device
on("nd_wn", function(v)
    local row = N.wifi_rows and N.wifi_rows[math.floor(tonumber(v) or 0) + 1]
    if not row then return end
    local ssid = tostring(row.ssid or "")
    if row.known or not row.secure then pcall(sys.call, "network.connect", ssid)
    else
        N.wifi_ssid = ssid
        fact.nd_wssid = ssid
        fact.nd_wsel = 1
        text.nd_wpw = ""
        render()
    end
end)
on("nd_wf", function(v)
    local row = N.wifi_rows and N.wifi_rows[math.floor(tonumber(v) or 0) + 1]
    if not row then return end
    pcall(sys.call, "network.forget", tostring(row.ssid or ""))
    pcall(sys.call, "network.scan")
end)
on("nd_wr", function() if N.wifi_on then pcall(sys.call, "network.scan") end end)
on("text:nd_wpw", function(v) N.wpw = tostring(v or "") end)
on("nd_wgo", function()
    local ssid = N.wifi_ssid or ""
    if ssid == "" then return end
    -- the password goes only here: not to run(), not to a file (D263)
    pcall(sys.call, "network.connect", ssid, N.wpw or "")
    N.wpw = ""
    text.nd_wpw = ""
    fact.nd_wsel = 0
    render()
end)
on("nd_bd", function(v)
    local d = N.bt_rows and N.bt_rows[math.floor(tonumber(v) or 0) + 1]
    if not d or not d.address then return end
    pcall(sys.call, d.connected and "bluetooth.disconnect" or "bluetooth.connect", tostring(d.address))
end)
on("nd_brf", function() if N.bt_on then pcall(sys.call, "bluetooth.scan", true) end end)
on("nd_pclear", function()
    N.notices = {}
    model.pn = {}
    fact.nd_ncn = 0
    run("pleamar", { "--say", "mooi", "emit note_clear" }, function() end)
    render()
end)
on("nd_popen", function() if N.open_player then N.open_player() end end)
on("nd_pclose", function() ST.release(N.st, "panel"); render() end)

-- on the panel's pages: the month's turns, a note kept, a row copied or opened, a picture worn
on("text:nd_nq", function(v) N.nq = tostring(v or "") end)
on("text:nd_kq", function(v) N.kq, N.ksc = tostring(v or ""), 0; if N.panel == "keys" then show_keys(); render() end end)
on("nd_ksc", function(v) N.ksc = N.ksc + (math.floor(tonumber(v) or 0) * 3); if N.panel == "keys" then show_keys(); render() end end)
on("nd_br", function(v)
    v = math.floor(tonumber(v) or 0)
    local page = N.panel
    if v == 1 or v == 2 then
        local d = v == 1 and -1 or 1
        if page == "calendar" and N.cal then N.cal.y, N.cal.m = CAL.shift(N.cal.y, N.cal.m, d); N.panel_shown = nil
        elseif page == "wallpaper" and #N.wl_list() > 0 then
            -- (D273) a page of nine at a time, round from the last back to the first
            local pages = math.ceil(#N.wl_list() / 9)
            local pg = ((N.wl_at - 1) // 9 + d) % pages
            N.wl_at = pg * 9 + 1
            N.panel_shown = nil
        end
    elseif v == 93 and page == "wallpaper" then
        N.wl_favonly = not N.wl_favonly
        N.wl_at, N.panel_shown = 1, nil
    elseif v >= 30 and v < 39 and page == "wallpaper" then
        local it = N.wl_list()[N.wl_at + v - 30]
        if it then
            local doc = WALLS.toggle(read(WALLS.FAVS, "json"), it.path)
            pcall(sys.call, "files.write", WALLS.FAVS, json.encode(doc))
            N.wl_favs = WALLS.favs(doc)
            N.panel_shown = nil
        end
    elseif (v == 91 or v == 92) and page == "wallpaper" then
        -- Random wears one at random with the picker's own choices; All opens the picker (Super+W)
        if v == 91 then
            run("mooi", { "wall", "next" }, function() N.walls = nil; if N.panel == "wallpaper" then N.panel_shown = nil; render() end end)
        else
            for _, k in ipairs(HELD) do ST.release(N.st, k) end
            run("mooi", { "walls" }, function() end)
        end
    elseif v == 90 and page == "notes" then
        local t = (N.nq or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= "" then
            -- into the bar's inbox, a file in mooi's own data folder (only its owner can read it), never on a
            -- command line where every process could see it (D258); the bar adds it to its notes
            local box = read("notes-inbox.json", "json")
            box = type(box) == "table" and box or {}
            box[#box + 1] = t
            pcall(sys.call, "files.write", "notes-inbox.json", json.encode(box))
            N.npage = 0   -- the new note is at the top, so it can be seen
            after(400, function() if N.panel == "notes" then N.panel_shown = nil; render() end end)
            N.nq, text.nd_nq = "", ""
        end
    elseif v >= 10 and v < 30 then
        local i = v - 9
        if page == "notes" and N.panel_items[i] then N.copy(N.panel_items[i])
        elseif page == "clipboard" and N.clip_choose then N.clip_choose(i)
        elseif page == "stash" and N.panel_items[i] then run("xdg-open", { N.panel_items[i] }, function() end)
        elseif page == "power" then N.power_choose(i)
        elseif page == "wallpaper" then
            local it = N.wl_list()[N.wl_at + i - 1]
            if it then N.wl_worn = it.path; run("mooi", { "wall", "apply", it.path }, function() end); N.panel_shown = nil end
        end
    end
    render()
end)
-- D279: the notes board pages with the wheel; a pin or a × is an op in the bar's inbox.
on("nd_nsw", function(v)
    if N.panel ~= "notes" then return end
    local d = math.floor(tonumber(v) or 0)
    if d == 0 then return end
    N.npage = math.max(0, (N.npage or 0) + d)
    N.panel_shown = nil
    render()
end)
on("nd_npin", function(v)
    local id = math.floor(tonumber(v) or 0)
    if id < 1 or N.panel ~= "notes" then return end
    inbox_add("notes-inbox.json", { op = "pin", id = id })
    inbox_refresh("notes")
end)
on("nd_ndel", function(v)
    local id = math.floor(tonumber(v) or 0)
    if id < 1 or N.panel ~= "notes" then return end
    inbox_add("notes-inbox.json", { op = "remove", id = id })
    inbox_refresh("notes")
end)
-- D279: the Stash page fills the box without the bar's dock: the clipboard, the newest thing in
-- Downloads, or (two presses within three seconds) nothing at all.
on("nd_sclip", function()
    if N.panel ~= "stash" then return end
    run("wl-paste", { "--no-newline" }, function(out, code)
        if code ~= 0 or type(out) ~= "string" or out == "" then return end
        inbox_add("stash-inbox.json", out)
        inbox_refresh("stash")
    end)
end)
on("nd_sdl", function()
    if N.panel ~= "stash" then return end
    local okh, home = pcall(sys.ask, "env", "HOME")
    if not okh or type(home) ~= "string" or home == "" then return end
    run("find", { home .. "/Downloads", "-mindepth", "1", "-maxdepth", "1", "-type", "f", "-printf", "%T@ %p\n" },
        function(out, code)
            if code ~= 0 or type(out) ~= "string" then return end
            local best, when = nil, -1
            for line in string.gmatch(out, "[^\r\n]+") do
                local stamp, path = string.match(line, "^(%S+) (.*)$")
                local t = tonumber(stamp)
                if path and path ~= "" and t and t > when then best, when = path, t end
            end
            if not best then return end
            inbox_add("stash-inbox.json", best)
            inbox_refresh("stash")
        end)
end)
on("nd_sclear", function()
    if N.panel ~= "stash" then return end
    if N.sclear and now() - N.sclear_at < 3000 then
        N.sclear, fact.nd_sclear = nil, false
        inbox_add("stash-inbox.json", { op = "clear" })
        inbox_refresh("stash")
    else
        N.sclear, N.sclear_at = true, now()
        fact.nd_sclear = true
        after(3100, function() if N.panel == "stash" then N.sclear, fact.nd_sclear = nil, false; render() end end)
    end
    render()
end)
on("nd_stdel", function(v)
    local id = math.floor(tonumber(v) or 0)
    if id < 1 or N.panel ~= "stash" then return end
    inbox_add("stash-inbox.json", { op = "remove", id = id })
    inbox_refresh("stash")
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
