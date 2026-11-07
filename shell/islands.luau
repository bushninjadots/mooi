-- The modules' own islands (D97): what each reads, only while it is open, and what its buttons
-- do. The scene draws them (shell/mooi.plm, the *_island groups, in the kit of ui/island.plm);
-- parsing is pure and tested (lib/calendar, lib/stats, lib/forecast). Nothing here runs while
-- every island is closed.

local calendar = require("lib/calendar")
local stats = require("lib/stats")
local forecast = require("lib/forecast")
local sysinfo = require("lib/sysinfo")
local weathershare = require("lib/weathershare")
local weatherpanel = require("lib/weatherpanel")

return function(ctx)
    -- D170: the Pill board's rooms read what the islands gather, so an island's readers run while it
    -- is open OR while the board shows its room (lib/pillpads.ROOMS: 1 calendar · 5 power ·
    -- 6 resources · 7 weather). `wanted` is the island the data is for now, or nil.
    local BOARD = { [1] = "calendar", [5] = "power", [6] = "stats", [7] = "weather" }
    local function wanted()
        if fact.open == "board" then return BOARD[math.floor(fact.pk_room or 0)] end
        return fact.open
    end
    local hooks = {}
    local function on_want(fn) hooks[#hooks + 1] = fn end
    local function told() local v = wanted(); for _, fn in ipairs(hooks) do fn(v) end end
    on("fact:open", told)
    on("fact:pk_room", told)
    -- ── The clock: what it shows (clock.view), a right press for the next ───
    local VIEWS = { "full", "time", "seconds" }
    on("clock_next", function()
        local s = ctx.settings()
        local i = 1
        for k, v in ipairs(VIEWS) do if v == s.clock.view then i = k end end
        s.clock.view = VIEWS[i % #VIEWS + 1]
        fact.clock_view = i % #VIEWS
        ctx.save()
    end)

    -- ── The media module: a right press shows its next view (media.mode) ──
    local MEDIA = { "full", "compact", "art", "viz" }
    on("media_view", function()
        local s = ctx.settings()
        local i = 1
        for k, v in ipairs(MEDIA) do if v == s.media.mode then i = k end end
        s.media.mode = MEDIA[i % #MEDIA + 1]
        fact.media_mode = i % #MEDIA
        ctx.save()
    end)

    -- ── The calendar ─────────────────────────────────────────
    local cal = { y = 0, m = 0 }
    local function today()
        return { y = tonumber(os.date("%Y")), m = tonumber(os.date("%m")), d = tonumber(os.date("%d")) }
    end
    local function show_month()
        local t = today()
        local month = calendar.month(cal.y, cal.m, t)
        local rows = {}
        for i, c in ipairs(month.cells) do
            rows[i] = { n = i - 1, day = c.day, cur = c.cur, today = c.today, weekend = c.weekend }
        end
        model.cal = rows
        text.cal_title = month.title
        local home = cal.y == t.y and cal.m == t.m
        fact.cal_home = home
        text.cal_sub = home and string.format("Week %d · %s", calendar.iso_week(t.y, t.m, t.d), os.date("%A"))
                            or string.format("%+d month%s", (cal.y - t.y) * 12 + (cal.m - t.m),
                                             math.abs((cal.y - t.y) * 12 + (cal.m - t.m)) == 1 and "" or "s")
    end
    on("cal_shift", function(v)
        local n = math.floor(tonumber(v) or 1)
        if n == 1 then local t = today(); cal.y, cal.m = t.y, t.m
        else cal.y, cal.m = calendar.shift(cal.y, cal.m, n == 0 and -1 or 1) end
        show_month()
    end)
    on_want(function(v)
        if v == "calendar" then local t = today(); cal.y, cal.m = t.y, t.m; show_month() end
    end)

    -- ── Stats: read every 2 s while the island is open ───────
    local have = {}
    run("nvtop", { "--version" }, function(_, code) have.nvtop = code == 0; fact.st_nvtop = have.nvtop end)
    local st_timer = nil
    local function read_stats()
        run("cat", { "/proc/loadavg" }, function(out)
            local a, b, c = stats.loadavg(out)
            text.st_load = a and string.format("load %.2f · %.2f · %.2f", a, b, c) or ""
        end)
        run("cat", { "/proc/meminfo" }, function(out)
            local m = stats.meminfo(out)
            fact.st_mem_f = m.frac
            text.st_mem_t = string.format("%.1f / %.1f GiB", m.used, m.total)
            text.st_swap_t = m.swap_total > 0 and string.format("SWAP %.1f / %.1f GIB", m.swap_used, m.swap_total) or "NO SWAP"
        end)
        run("df", { "-P", "/" }, function(out)
            local d = stats.df(out)
            fact.st_disk_f = d.frac; text.st_disk_t = d.text
        end)
        run("ps", { "-eo", "comm,%cpu", "--sort=-%cpu", "--no-headers" }, function(out)
            model.st_top = stats.top(out, 3)
        end)
        run("cat", { "/sys/class/drm/card0/device/gpu_busy_percent", "/sys/class/drm/card1/device/gpu_busy_percent" }, function(out)
            local g = stats.gpu(out)
            fact.st_gpu_ok = g ~= nil
            if g then fact.st_gpu_f = g end
        end)
    end
    on_want(function(v)
        if v == "stats" then
            read_stats()
            if not st_timer then st_timer = every(2000, read_stats) end
        elseif st_timer then cancel(st_timer); st_timer = nil end
    end)
    -- ── Weather: one request when it opens, kept 10 minutes ──
    -- The shared location memo and forecast cache (lib/weathershare): one cached IP lookup serves
    -- the bar, this island, the notch and the Nexus.
    local wx_at, wx_busy = 0, false
    local function show_forecast(f)
        local _, word = sysinfo.weather(f.now.code, f.now.day)
        fact.wxi_temp = f.now.temp
        fact.wxi_kind = weatherpanel.kind(f.now.code, f.now.day)
        text.wxi_word = word
        text.wxi_hilo = f.today.hi and string.format("H %d°  L %d°", math.floor(f.today.hi + 0.5), math.floor(f.today.lo + 0.5)) or ""
        text.wxi_line = string.format("feels %d° · wind %d km/h · %d %%", math.floor(f.now.feels + 0.5), math.floor(f.now.wind + 0.5), math.floor(f.now.humidity + 0.5))
        local hours = {}
        for i, h in ipairs(f.hours) do hours[i] = { n = i - 1, label = h.label, temp = h.temp, kind = weatherpanel.kind(h.code, h.day) } end
        model.wx_hours = hours
        local lo, hi = math.huge, -math.huge
        for _, d in ipairs(f.days) do lo = math.min(lo, d.lo); hi = math.max(hi, d.hi) end
        local span = math.max(1, hi - lo)
        local days = {}
        for i, d in ipairs(f.days) do
            days[i] = { n = i - 1, label = d.label, lo = d.lo, hi = d.hi, kind = weatherpanel.kind(d.code, 1),
                        a = (d.lo - lo) / span, b = (d.hi - lo) / span }
        end
        model.wx_days = days
        fact.wxi_ok = true
    end
    local function fetch_weather()
        if wx_busy then return end
        wx_busy = true; fact.wxi_busy = true
        local function fetch(url, done)
            run("curl", { "-fsSL", "--max-time", "15", url }, function(out, code)
                local ok, t = pcall(json.decode, out or "")
                done(code == 0 and ok and type(t) == "table" and t or nil)
            end)
        end
        local function get(name) local ok, v = pcall(sys.ask, "files.read", name); return ok and v or nil end
        weathershare.refresh({ read = get, fetch = fetch,
                              write = function(name, doc) pcall(sys.call, "files.write", name, doc) end }, function(doc)
            wx_busy = false; fact.wxi_busy = false
            local f = doc and forecast.parse(doc.answer) or nil
            if f then
                show_forecast(f)
                wx_at = os.time(); text.wxi_sub = "Updated " .. os.date("%H:%M")
                text.wxi_title = (doc.city and doc.city ~= "") and tostring(doc.city) or "Weather"
            else
                text.wxi_sub = fact.wxi_ok and ("Offline · from " .. os.date("%H:%M", wx_at)) or "Offline"
            end
        end)
    end
    on_want(function(v)
        if v == "weather" and os.time() - wx_at >= 600 then fetch_weather() end
    end)
    on("wx_refresh", fetch_weather)

    -- ── Sound: where it plays, and the mixer ─────────────────
    local outputs = {}
    pcall(sys.watch, "audio", function(a)
        if type(a) == "table" and type(a.outputs) == "table" then outputs = a.outputs end
    end)
    on("snd_out", function(n)
        local o = outputs[(tonumber(n) or -1) + 1]
        if o and o.id then pcall(sys.call, "audio.default", o.id) end
    end)
    run("pavucontrol", { "--version" }, function(_, code) have.mixer = code == 0 end)
    on("snd_mixer", function()
        if have.mixer then spawn("pavucontrol", {}, function() end, function() end) end
    end)

    -- ── Display: the night light (hyprsunset at 4000 K, ours to stop) ──
    local nl = nil
    fact.nl_on = false
    on("night_light", function()
        if nl then kill(nl, "term"); nl = nil; fact.nl_on = false; return end   -- killed: no exit callback
        local mine
        local ok, id = pcall(spawn, "hyprsunset", { "-t", "4000" }, function() end, function()
            if nl == mine then nl = nil; fact.nl_on = false end
        end)
        if not ok then log("display · night light did not start: " .. tostring(id)); return end
        mine = id; nl = id; fact.nl_on = true
    end)

    -- ── Power: upower's battery while the island is open; the saver and the profile ──
    run("powerprofilesctl", { "get" }, function(_, code) fact.pw_ppd = code == 0 end)
    local pw_timer = nil
    local STATES = { charging = "Charging", discharging = "On battery", ["fully-charged"] = "Full",
                     ["pending-charge"] = "Plugged in", empty = "Empty" }
    local rate, health = "", ""
    local function detail()   -- "7.4 W · health 82 %", either half alone, or nothing
        text.pw_rate = (rate ~= "" and health ~= "") and (rate .. "  ·  " .. health) or (rate .. health)
    end
    local function read_power()
        run("upower", { "-i", "/org/freedesktop/UPower/devices/DisplayDevice" }, function(out)
            local b = stats.upower(out)
            text.pw_state = STATES[b.state] or ""
            text.pw_time = b.time
            rate = b.rate; detail()
        end)
        run("upower", { "-e" }, function(list)
            local bat = tostring(list or ""):match("(/org/freedesktop/UPower/devices/battery_[%w_]+)")
            if not bat then health = ""; detail(); return end
            run("upower", { "-i", bat }, function(out)
                local b = stats.upower(out)
                health = b.health and string.format("health %d %%", b.health) or ""
                detail()
            end)
        end)
    end
    on_want(function(v)
        if v == "power" then
            read_power()
            if not pw_timer then pw_timer = every(10000, read_power) end
        elseif pw_timer then cancel(pw_timer); pw_timer = nil end
    end)
    local SAVER = { [0] = "off", [1] = "battery", [2] = "always" }
    local PROFILE = { [11] = "power-saver", [12] = "balanced", [13] = "performance" }
    on("pw_set", function(v)
        local n = math.floor(tonumber(v) or -1)
        local s = ctx.settings()
        if SAVER[n] then s.motion.saver = SAVER[n] elseif PROFILE[n] then s.power.profile = PROFILE[n] else return end
        ctx.save()
    end)

    -- ── The connections shelf (D100): the radios, joining, connecting ──
    local nets, devices, wifi_on, bt_on = {}, {}, true, false
    pcall(sys.watch, "network", function(n)
        if type(n) ~= "table" then return end
        nets = type(n.networks) == "table" and n.networks or {}
        wifi_on = n.wifi ~= false
    end)
    pcall(sys.watch, "bluetooth", function(b)
        if type(b) ~= "table" then return end
        devices = type(b.devices) == "table" and b.devices or {}
        bt_on = b.powered == true
    end)
    on("sh_net", function(v)
        local n = math.floor(tonumber(v) or -2)
        if n == -1 then pcall(sys.call, "network.wifi", not wifi_on); return end
        local w = nets[n + 1]
        if not w or w.active then return end
        if w.known or not w.secure then pcall(sys.call, "network.connect", w.ssid)
        else fact.open = "none"; emit("open_settings") end      -- a password to type: the settings window
    end)
    on("sh_bt", function(v)
        local n = math.floor(tonumber(v) or -2)
        if n == -1 then pcall(sys.call, "bluetooth.power", not bt_on); return end
        local d = devices[n + 1]
        if d and d.address then pcall(sys.call, d.connected and "bluetooth.disconnect" or "bluetooth.connect", d.address) end
    end)

    on("st_open", function(n)
        local tool = (tonumber(n) == 1 and have.nvtop) and "nvtop" or "btop"
        spawn("kitty", { "--title", tool, tool }, function() end, function() end)
    end)
end
