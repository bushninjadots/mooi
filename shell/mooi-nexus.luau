-- mooi's Control Nexus (D98): the drawer's logic. What the drawer shows is read only while it is
-- open (the program ends when it closes): the services the scene binds straight to, the machine
-- every 2 s, the bar's own switches every 2 s, and two files the bar writes (nexus-feed.json,
-- updates.json). Every press goes to the system (sys.call) or to the bar (`pleamar --say mooi`),
-- which alone can open its islands, clear notifications, record or run the updater. The column's
-- geometry is lib/nexusdrawer's; settings.json is mooi's own (bin/mooi links the data folder).

local config = require("lib/config")
local ferro = require("lib/ferro")
local theme = require("lib/theme")
local style = require("lib/style")
local sysinfo = require("lib/sysinfo")
local stats = require("lib/stats")
local calendar = require("lib/calendar")
local forecast = require("lib/forecast")
local drawer = require("lib/nexusdrawer")

local FILE = "settings.json"

local function env(name, fallback)
    local ok, v = pcall(sys.ask, "env", name)
    if ok and type(v) == "string" and v ~= "" then return v end
    return fallback
end
local function read(name, kind)
    local ok, v = pcall(sys.ask, "files.read", name, kind or "json")
    return ok and v or nil
end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function launch(cmd, args, done)
    local ok = pcall(run, cmd, args, function(out, code) if done then done(code == 0 and out or nil) end end)
    if not ok and done then done(nil) end
end
local function bar(...) launch("pleamar", { "--say", "mooi", ... }) end

local settings = config.parse(read(FILE), json.decode)
local screen_w = 1920
local wifi_on, bt_powered = true, false
local data_folder = env("XDG_DATA_HOME", env("HOME", "") .. "/.local/share") .. "/pleamar/mooi"

-- ── The look: the shell's palette, the island style, the corners ──
local function paint()
    local palette = read("palette.json")
    local roles = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not roles then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = roles[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
    local colours = theme.resolve(settings.theme, roles)
    for name, c in pairs(colours or {}) do
        local f = "c_" .. string.gsub(name, "%.", "_")
        -- the scene declares the tokens it draws with; any other the theme names is skipped
        pcall(function() fact[f .. "_r"], fact[f .. "_g"], fact[f .. "_b"] = c.r, c.g, c.b end)
    end
    fact.cn_kind, fact.cn_scale = style.corners(settings)
    fact.isl_style = settings.island.style == "tether" and 1 or 0
    local look = style.facts(settings)
    if look and look.st_glow then fact.st_glow = look.st_glow end
end
paint()

-- ── Who, and where the drawer sits (under the bar, the screen's height below it) ──
do
    local id = type(settings.nexus) == "table" and type(settings.nexus.identity) == "table" and settings.nexus.identity or {}
    local name = type(id.name) == "string" and id.name ~= "" and id.name or "mooi"
    text.nx_name = name
    text.nx_initial = string.upper(string.sub(name, 1, 1))
    if type(id.avatar) == "string" and id.avatar ~= "" then text.nx_avatar = data_folder .. "/" .. id.avatar; fact.nx_avatar_on = true end
    launch("whoami", {}, function(u) launch("hostname", {}, function(h)
        text.nx_who = string.lower(trim(u) .. "@" .. trim(h))
    end) end)
    fact.nx_top = (tonumber(settings.bar.offset) or 0) + (tonumber(settings.bar.height) or 30) + 6
    launch("hyprctl", { "-j", "monitors" }, function(out)
        local ok, mons = pcall(json.decode, out or "")
        local h = 1080
        if ok and type(mons) == "table" then
            for _, m in ipairs(mons) do
                if m.focused and tonumber(m.height) then
                    h = math.floor(m.height / (tonumber(m.scale) or 1) + 0.5)
                    screen_w = math.floor(m.width / (tonumber(m.scale) or 1) + 0.5)
                end
            end
        end
        fact.nx_h = h - fact.nx_top - 6
    end)
end

-- ── The column: folds, counts, and each section's top ──
local folded = drawer.folded_set(type(settings.nexus) == "table" and settings.nexus.folded or nil)
local counts = { playing = false, notes = 0, nets = 0, bt = 0, outs = 1, apps = 0, bright = false, ws = 1 }
local function relayout()
    local l = drawer.layout(counts, folded)
    for _, id in ipairs(drawer.ORDER) do
        fact["y_" .. id] = l.shown[id] and l.top[id] or 0
        fact["f_" .. id] = folded[id] == true
    end
    fact.nx_total = l.total
end
relayout()
local function save_folds()
    if env("MOOI_SAFE", "") == "1" then return end
    local doc = read(FILE)       -- read again: whatever changed elsewhere is kept
    if type(doc) ~= "table" then return end
    doc.nexus = type(doc.nexus) == "table" and doc.nexus or {}
    doc.nexus.folded = drawer.folded_list(folded)
    pcall(sys.call, "files.write", FILE, doc)
end
on("nx_fold", function(v)
    local id = drawer.ORDER[(tonumber(v) or -1) + 1]
    if not id then return end
    folded = drawer.toggle(folded, id)
    relayout()
    save_folds()
end)

-- ── Opening and closing ──
local closing = false
local function close(why)
    if closing then return end
    closing = true
    log("nexus · closing: " .. tostring(why or "asked"))
    fact.nx_open = false
    -- gone from sight in ~220 ms; it ends later, so what a press just asked of the bar or started
    -- (a `pleamar --say` takes ~250 ms) is not cut off with it
    after(900, function() launch("pleamar", { "--say", "mooi-nexus", "quit" }) end)
end
on("nx_close", function() close("asked (Esc, × or the mark)") end)
after(40, function() fact.nx_open = true end)

-- ── What the services say, for the counts and the rows' presses ──
local nets, devices, outputs, apps = {}, {}, {}, {}
local media = {}
pcall(sys.watch, "network", function(n)
    nets = type(n) == "table" and type(n.networks) == "table" and n.networks or {}
    wifi_on = not (type(n) == "table" and n.wifi == false)
    counts.nets = #nets; relayout()
    text.t_s0 = (type(n) == "table" and n.wifi == false) and "Off" or ((type(n) == "table" and n.online) and tostring(n.name or "Connected") or "No network")
end)
pcall(sys.watch, "bluetooth", function(b)
    devices = type(b) == "table" and type(b.devices) == "table" and b.devices or {}
    counts.bt = #devices; relayout()
    local present, powered = type(b) == "table" and b.present, type(b) == "table" and b.powered
    bt_powered = powered == true
    text.t_s1 = not present and "No adapter" or (powered and (#devices > 0 and (#devices .. " known") or "On") or "Off")
    text.bt_empty = not present and "No Bluetooth adapter" or (powered and "No devices paired" or "Bluetooth is off")
end)
pcall(sys.watch, "audio", function(a)
    if type(a) ~= "table" then return end
    outputs = type(a.outputs) == "table" and a.outputs or {}
    apps = type(a.apps) == "table" and a.apps or {}
    counts.outs, counts.apps = #outputs, math.min(6, #apps); relayout()
    text.t_s2 = a.muted and "Muted" or string.format("%d %%", math.floor((tonumber(a.volume) or 0) * 100 + 0.5))
    text.t_s3 = a.input_muted and "Muted" or "Live"
end)
pcall(sys.watch, "brightness", function(b) counts.bright = type(b) == "table" and b.present == true; relayout() end)
pcall(sys.watch, "workspaces", function(w)
    local first = counts.ws_seen == nil
    local active = type(w) == "table" and tonumber(w.active) or nil
    if not first and active and active ~= counts.active_ws then close("the workspace changed") end   -- the desktop moved on
    counts.ws_seen = true; counts.active_ws = active
end)
-- No closing on a focus change or on losing the keyboard: with Hyprland's focus following the
-- mouse (input:follow_mouse), both happen whenever the pointer crosses a window, and the drawer
-- went the moment the mouse moved. It stays until Esc, ×, the mark, or a workspace change.

-- ── Now playing: the cover, and the position carried at the player's rate ──
local art_url, covers = nil, 0
local function cover(url)
    if url == art_url then return end
    art_url = url
    if type(url) ~= "string" or url == "" then fact.nx_art_on = false; return end
    local path = url:match("^file://(.*)$")
    if path then
        text.nx_art = (path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)); fact.nx_art_on = true
    elseif url:match("^https?://") then
        covers = covers + 1
        local dest = data_folder .. "/nexus-cover-" .. (covers % 2) .. ".img"
        launch("curl", { "-fsSL", "--max-time", "8", "-o", dest, url }, function(ok)
            if ok and art_url == url then text.nx_art = dest; fact.nx_art_on = true end
        end)
    elseif url:match("^data:image/") and #url < 120000 then
        covers = covers + 1
        local dest = data_folder .. "/nexus-cover-" .. (covers % 2) .. ".png"
        launch("magick", { "inline:" .. url, dest }, function(ok)
            if ok and art_url == url then text.nx_art = dest; fact.nx_art_on = true end
        end)
    else fact.nx_art_on = false end
end
local function clock(s)
    s = math.max(0, math.floor(tonumber(s) or 0))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
local pos, pos_at = 0, os.time()
pcall(sys.watch, "media", function(m)
    media = type(m) == "table" and m or {}
    counts.playing = media.playing == true or (tostring(media.title or "") ~= "" and tostring(media.player or "") ~= "")
    relayout()
    cover(media.art)
    pos, pos_at = tonumber(media.position) or 0, os.time()
    text.nx_length = (tonumber(media.length) or 0) > 0 and clock(media.length) or ""
end)
every(1000, function()
    local len = tonumber(media.length) or 0
    if len <= 0 then fact.nx_prog = 0; text.nx_elapsed = ""; return end
    local p = pos + (media.playing and (os.time() - pos_at) * (tonumber(media.rate) or 1) or 0)
    fact.nx_prog = math.min(1, p / len)
    text.nx_elapsed = clock(p)
end)
on("nx_media", function(v)
    local n = tonumber(v)
    pcall(sys.call, n == 0 and "media.previous" or (n == 2 and "media.next" or "media.toggle"))
end)

-- ── The bar's own switches, asked every 2 s ──
local function bar_states()
    launch("pleamar", { "--say", "mooi", "get dnd_now", "get caffeine_on", "get recording", "get nl_on", "get pw_saver" }, function(out)
        if not out then return end
        local got = {}
        for line in out:gmatch("[^\n]+") do got[#got + 1] = trim(line) end
        if #got < 5 then return end
        fact.b_dnd, fact.b_awake, fact.b_rec, fact.b_night = got[1] == "true", got[2] == "true", got[3] == "true", got[4] == "true"
        fact.b_saver = (tonumber(got[5]) or 0) > 0
        text.t_s4 = fact.b_dnd and "Do not disturb" or "Off"
        text.t_s5 = fact.b_night and "4000 K" or "Off"
        text.t_s6 = fact.b_awake and "Kept awake" or "Idle"
        text.t_s7 = fact.b_saver and "On" or "Off"
        text.t_s8 = fact.b_rec and "Recording" or "Ready"
    end)
end
bar_states()
every(2000, bar_states)

-- ── The quick toggles ──
local TOGGLE = {
    [0] = function() pcall(sys.call, "network.wifi", not wifi_on) end,
    [1] = function() pcall(sys.call, "bluetooth.power", not bt_powered) end,
    [2] = function() pcall(sys.call, "audio.mute") end,
    [3] = function() pcall(sys.call, "audio.input_mute") end,
    [4] = function() bar("emit note_dnd") end,
    [5] = function() bar("emit night_light") end,
    [6] = function() bar("emit caffeine") end,
    [7] = function() bar("emit pw_set " .. (fact.b_saver and "0" or "1")) end,
    [8] = function() bar("emit record 0") end,
}
on("nx_tog", function(v)
    local f = TOGGLE[math.floor(tonumber(v) or -1)]
    if f then f(); after(250, bar_states) end
end)

-- ── The levels (a drag sends many: the last one in 40 ms is what is asked for) ──
local pending, flushing = {}, false
local function flush()
    flushing = false
    if pending.vol then pcall(sys.call, "audio.volume", pending.vol) end
    if pending.mic then pcall(sys.call, "audio.input", pending.mic) end
    if pending.bri then pcall(sys.call, "brightness.level", math.max(0.01, pending.bri)) end
    pending = {}
end
local function request(kind, v)
    local n = tonumber(v); if not n then return end
    pending[kind] = math.max(0, math.min(1, n))
    if not flushing then flushing = true; after(40, flush) end
end
on("vol", function(v) request("vol", v) end)
on("mic", function(v) request("mic", v) end)
on("bri", function(v) request("bri", v) end)
on("nx_app", function(v)
    local n = math.floor(tonumber(v) or -1)
    local a = apps[math.floor(n / 1000) + 1]
    if a and tonumber(a.id) then pcall(sys.call, "audio.app_volume", tonumber(a.id), (n % 1000) / 1000) end
end)

-- ── Rows: networks, devices, outputs, workspaces ──
on("nx_net", function(v)
    local w = nets[(tonumber(v) or -1) + 1]
    if not w or w.active then return end
    if w.known or not w.secure then pcall(sys.call, "network.connect", w.ssid)
    else close(); bar("emit open_settings") end     -- a password to type: the settings window
end)
on("nx_bt", function(v)
    local d = devices[(tonumber(v) or -1) + 1]
    if d and d.address then pcall(sys.call, d.connected and "bluetooth.disconnect" or "bluetooth.connect", d.address) end
end)
on("nx_out", function(v)
    local o = outputs[(tonumber(v) or -1) + 1]
    if o and o.id then pcall(sys.call, "audio.default", o.id) end
end)
on("nx_ws", function(v) pcall(sys.call, "workspaces.focus", math.floor(tonumber(v) or 0)) end)

-- ── Opening things: in the bar (its islands and panels) or as programs ──
-- An island opens under the drawer's edge, the drawer gone first.
local function island(name)
    bar("fact isl_cx " .. tostring(screen_w - 200), "fact open " .. name)
    close()
end
local GO = {
    [1] = function() close(); bar("emit open_settings") end,
    [2] = function() close(); bar("emit power 1") end,
    [3] = function() close(); bar("emit power 0") end,
    [10] = function() close(); pcall(spawn, "kitty", { "--title", "btop", "btop" }, function() end, function() end) end,
    [11] = function() island("calendar") end,
    [12] = function() island("weather") end,
    [13] = function() close(); bar("emit run_updates") end,
    [20] = function() close(); launch("mooi", { "player" }) end,
    [30] = function() close(); bar("emit open_notes") end,
    [31] = function() bar("emit note_clear") end,
    [40] = function() close(); launch("mooi", { "wallpaper" }) end,
    [41] = function() close(); bar("fact qn_open true") end,
    [42] = function() close(); launch("mooi", { "board" }) end,
    [43] = function() close(); bar("emit open_overview") end,
    [44] = function() close(); after(300, function() bar("emit shot 0") end) end,
    [45] = function() close(); bar("emit open_clips") end,
    [46] = function() launch("mooi", { "diagnostics" }) end,
}
on("nx_go", function(v)
    local f = GO[math.floor(tonumber(v) or -1)]
    if f then f() end
end)

-- ── Notifications and updates: what the bar wrote ──
local function show_feed()
    local f = read("nexus-feed.json")
    if type(f) ~= "table" then fact.feed_ok = false; fact.feed_n = 0; counts.notes = 0; relayout(); return end
    local rows = {}
    for i, it in ipairs(type(f.items) == "table" and f.items or {}) do
        rows[i] = { app = tostring(it.app or ""), title = tostring(it.title or ""),
                    ago = require("lib/nexusfeed").ago(os.time() - (tonumber(it.time) or os.time())) }
    end
    model.feed = rows
    fact.feed_ok = true
    fact.feed_n = tonumber(f.count) or #rows
    counts.notes = #rows; relayout()
end
show_feed()
pcall(sys.watch, "files:nexus-feed.json", show_feed)
local function show_updates()
    local u = read("updates.json")
    if type(u) ~= "table" then fact.upd_ok = false; return end
    fact.upd_ok = true
    fact.upd_n = tonumber(u.total) or 0
    text.upd_t = tostring(u.text or "")
end
show_updates()
pcall(sys.watch, "files:updates.json", show_updates)

-- ── The machine, every 2 s ──
local cpu_prev = nil
local function machine()
    launch("cat", { "/proc/stat" }, function(out) local v; v, cpu_prev = sysinfo.cpu(out, cpu_prev); if v then fact.m_cpu = v end end)
    launch("cat", { "/proc/meminfo" }, function(out)
        local m = stats.meminfo(out); fact.m_mem = m.frac; text.m_mem_t = string.format("%.1f / %.1f GiB", m.used, m.total)
    end)
    launch("df", { "-P", "/" }, function(out) local d = stats.df(out); fact.m_disk = d.frac; text.m_disk_t = d.text end)
    -- the GPU's busy share: whichever card has the file (cat fails as a whole when one is missing)
    for _, card in ipairs({ "card1", "card0" }) do
        launch("cat", { "/sys/class/drm/" .. card .. "/device/gpu_busy_percent" }, function(out)
            local g = out and stats.gpu(out) or nil
            if g then fact.m_gpu_ok = true; fact.m_gpu = g end
        end)
    end
    launch("sensors", { "-j" }, function(out)
        local ok, t = pcall(json.decode, out or ""); local c = ok and sysinfo.temp(t) or nil
        if c then fact.m_temp = c end
    end)
end
machine()
every(2000, machine)
pcall(sys.watch, "battery", function(b)
    if type(b) ~= "table" or not b.present then text.m_bat_t = ""; return end
    text.m_bat_t = string.format("Battery %d %% · %s", math.floor((tonumber(b.percent) or 0) + 0.5), b.charging and "charging" or "on battery")
end)

-- ── Today: the week from today, and the weather (kept 10 minutes in nexus-weather.json) ──
do
    local rows = {}
    local DAYS = { "MO", "TU", "WE", "TH", "FR", "SA", "SU" }
    local t = os.time()
    for i = 0, 6 do
        local when = t + i * 86400
        local y, m, d = tonumber(os.date("%Y", when)), tonumber(os.date("%m", when)), tonumber(os.date("%d", when))
        rows[#rows + 1] = { label = DAYS[calendar.weekday(y, m, d) + 1], day = d, today = i == 0 }
    end
    model.days = rows
end
local function kind_of(code, day)
    local k = sysinfo.weather(code, day)
    for i, name in ipairs(sysinfo.WEATHER_KINDS) do if name == k then return i - 1 end end
    return 2
end
local function show_weather(doc)
    local f = forecast.parse(doc.answer)
    if not f then return end
    local _, word = sysinfo.weather(f.now.code, f.now.day)
    fact.wx_kind = kind_of(f.now.code, f.now.day)
    fact.wx_temp = f.now.temp
    text.wx_word = word
    text.wx_place = tostring(doc.city or "")
    fact.wx_ok = true
end
do
    local cached = read("nexus-weather.json")
    if type(cached) == "table" and type(cached.answer) == "table" then show_weather(cached) end
    if type(cached) ~= "table" or os.time() - (tonumber(cached.at) or 0) > 600 then
        launch("curl", { "-fsSL", "--max-time", "8", "https://ipinfo.io/json" }, function(out)
            local ok, where = pcall(json.decode, out or "")
            local lat, lon = nil, nil
            if ok and type(where) == "table" then lat, lon = tostring(where.loc or ""):match("^([%d%.%-]+),([%d%.%-]+)$") end
            if not lat then return end
            launch("curl", { "-fsSL", "--max-time", "12", forecast.url(lat, lon) }, function(ans)
                local ok2, t = pcall(json.decode, ans or "")
                if not ok2 or type(t) ~= "table" then return end
                local doc = { at = os.time(), city = where.city, answer = t }
                pcall(sys.call, "files.write", "nexus-weather.json", doc)
                show_weather(doc)
            end)
        end)
    end
end
