-- The Dynamic Pill as a living node (D226; docs/superpowers/specs/2026-11-09-dynamic-pill-node-design.md). The
-- logic: what is happening (the services, Signal Loom's feed, the bar's feed), what the node is now
-- (lib/node/state), where its body and parts go (lib/node/geometry, satellites, universe), how it answers the
-- pointer (lib/node/interaction) — written as facts for shell/mooi-node.plm (tools/gen-node.py) to spring and draw.
-- Event-driven: one timer for the next thing that ends, none at rest.

local config = require("lib/config")
local ferro = require("lib/ferro")
local ST = require("lib/node/state")
local G = require("lib/node/geometry")
local MO = require("lib/node/motion")
local IX = require("lib/node/interaction")
local SAT = require("lib/node/satellites")
local WB = require("lib/wbelow")          -- the apps' ranking (Launch's grid's, D215)

local KIND = { rest = 0, media = 1, notice = 2, volume = 3, workspaces = 4, system = 5, launcher = 6, universe = 7 }
local SAT_KIND = { music = 1, rec = 2, battery = 3, network = 4, music_rec = 5, notice = 6, mic = 7, timer = 8 }

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

-- the clock: a counter of our own in 50 ms steps (the way mooi-surface keeps its reveal's); it only draws when
-- something is due — the next event's end, or the pointer's next decision — so at rest nothing is done
local MS = 0
local function now() return MS end

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

local function personality() return cfg().personality or "organic" end

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

local function show_notices(b)
    local cards = G.cards(b, math.min(3, #N.notices), N.scr)
    local rows = {}
    for i, c in ipairs(cards) do
        local n = N.notices[i]
        local a1 = type(n.actions) == "table" and n.actions[1] or nil
        rows[i] = { x = c.x, y = c.y, w = c.w, h = c.h, app = tostring(n.app or ""), title = tostring(n.title or ""),
                    act = type(a1) == "string" and a1 or "", hasact = type(a1) == "string" and a1 ~= "" }
    end
    model.nc = rows
    fact.nd_more = math.max(0, #N.notices - #rows)
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
        local icon = type(a.icon) == "string" and a.icon or ""
        rows[i] = { x = p.x, y = p.y, w = p.w, h = p.h, name = name, icon = icon, iconed = icon ~= "",
                    letter = string.upper(string.sub(name ~= "" and name or "?", 1, 1)) }
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

local function show_satellites(b, kind)
    if not on_for("satellites") then model.sa = {}; return end
    local f = N.feed
    local list = SAT.collect({ playing = N.media.playing and on_for("media"), media_open = kind == "media", title = N.media.title,
                               recording = f.recording == true, notices = on_for("notices") and #N.notices or 0,
                               battery = N.bat, charging = N.charging, online = N.online })
    local rows = {}
    for i, s in ipairs(SAT.layout(list, b)) do
        rows[i] = { x = s.x, y = s.y, w = s.w, h = s.h, label = s.label, kind = SAT_KIND[s.kind] or 0 }
    end
    model.sa = rows
end

render = function()
    local t = now()
    local pers = personality()
    fact.nd_np = MO.index(pers)
    fact.nd_breath = not (type(N.settings.motion) == "table" and N.settings.motion.reduced == true)
    local kind, reacting = ST.current(N.st, t, { playing = N.media.playing and on_for("media"), near = N.near })
    local anchor = cfg().anchor or "centre"
    local data = { n = #N.ws.list }
    local b = G.body(kind, N.scr, anchor, pers, data)
    -- leaning toward where the pointer came in from
    if N.near and kind ~= "rest" and kind ~= "universe" then b.x = math.max(0, math.min(N.scr.w - b.w, b.x + (N.lean or 0) * 24)) end
    if kind == "universe" then
        local c = G.body("universe", N.scr, "centre", pers, data)
        b = { x = N.scr.w / 2 - c.w / 2, y = N.scr.h / 2 - c.h / 2, w = c.w, h = c.h, r = c.r }
    end
    -- a reaction: the seed stretches toward what is coming before it unfolds
    if reacting then
        local seed = G.body("rest", N.scr, anchor, pers, data)
        b = { x = seed.x - 20, y = seed.y, w = seed.w + 40, h = math.max(seed.h, 8), r = 4 }
    end
    local changed = kind ~= N.kind
    N.kind = kind
    -- a change of shape: what unfolds grows out of the body again (and a cyber node glitches on the way)
    if changed then
        N.gn = (N.gn or 0) + 1
        fact.nd_gn = N.gn
        if pers == "cyber" then
            fact.nd_gl = 1
            after(140, function() fact.nd_gl = 0 end)
        end
    end
    fact.nd_kind = KIND[kind] or 0
    fact.nd_kb = kind == "launcher" or kind == "universe"
    set_body(b, changed and MO.overshoot(pers, cfg().motion or "normal") or 0)
    if kind == "media" then show_media(b) end
    if kind == "notice" then show_notices(b) end
    if kind == "workspaces" then show_rail(b) end
    if kind == "system" then show_system(b) end
    if kind == "launcher" then show_launcher(b) end
    if kind == "universe" then show_universe() end
    if kind == "volume" then
        fact.nd_vol = N.vol or 0
        text.nd_vlabel = "VOLUME " .. math.floor((N.vol or 0) * 100 + 0.5) .. "%"
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
pcall(sys.watch, "battery", function(b)
    if type(b) ~= "table" or b.present == false then N.bat = nil; return end
    N.bat, N.charging = tonumber(b.percent), b.charging == true
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
    v = math.floor(tonumber(v) or 0)
    local b = { x = fact.nd_tx or 0, y = fact.nd_ty or 0, w = fact.nd_tw or 22, h = fact.nd_th or 6 }
    N.pointer = v > 0 and { x = v - 1, y = b.y + b.h / 2 } or nil
    N.pointer_step()
end)

-- ── presses ──
local function toggle_hold(kind)
    if ST.held(N.st, kind) then ST.release(N.st, kind) else
        for _, k in ipairs({ "system", "launcher", "universe" }) do ST.release(N.st, k) end
        ST.hold(N.st, kind)
    end
end
on("nd_press", function()
    local k = N.kind
    if k == "launcher" or k == "universe" then return end
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
    if not N.notices[row + 1] then return end
    run("pleamar", { "--say", "mooi", "emit note_act " .. tostring(row * 10 + (what == 9 and 9 or what)) }, function() end)
    if what == 9 then table.remove(N.notices, row + 1); render() end
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
    N.results = WB.grid_apps(N.apps, type(wd) == "table" and wd.launch_counts or {}, N.q, 6)
    N.sel = math.max(0, math.min(N.sel, #N.results - 1))
end
local function open_launcher()
    for _, k in ipairs({ "system", "universe" }) do ST.release(N.st, k) end
    ST.hold(N.st, "launcher")
    N.q, N.sel = "", 0
    text.nd_q = ""
    search()
    render()
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
    if N.kind == "launcher" then
        if v == 27 then ST.release(N.st, "launcher")
        elseif v == 38 then N.sel = math.max(0, N.sel - 1)
        elseif v == 40 or v == 9 then N.sel = math.min(#N.results - 1, N.sel + 1)
        elseif v == 13 then
            local a = N.results[N.sel + 1]
            if a then pcall(sys.call, "apps.launch", a.exec) end
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
    if a then pcall(sys.call, "apps.launch", a.exec) end
    ST.release(N.st, "launcher")
    render()
end)

-- ── `mooi node …`: Super wakes it; the launcher; the universe ──
on("nd_cmd", function(v)
    v = math.floor(tonumber(v) or 0)
    if v == 1 then
        -- Super: the music if it plays, else what you last held, else the system for a moment
        if N.kind ~= "rest" then for _, k in ipairs({ "system", "launcher", "universe" }) do ST.release(N.st, k) end
        elseif N.media.playing and on_for("media") then ST.push(N.st, "media", now())
        elseif on_for("system") then ST.push(N.st, "system", now()) end
        render()
    elseif v == 2 then
        if ST.held(N.st, "launcher") then ST.release(N.st, "launcher"); render() else open_launcher() end
    elseif v == 3 then
        if ST.held(N.st, "universe") then ST.release(N.st, "universe"); render() else open_universe() end
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
