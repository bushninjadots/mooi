-- The Ferrolume bar's logic: where every module goes, and what the modules read that no
-- pleamar service reports — the processor, memory, temperature, throughput, keyboard layout,
-- weather and the audio levels — plus the bar's own actions (keep awake, record, screenshot,
-- clipboard, tray, notifications, power). Layout arithmetic and parsing are pure and tested
-- (lib/barlayout, lib/sysinfo); this file only runs things and hands the results over.
--
-- Nothing is read for a module that is not on the bar: each reader starts when its module is
-- placed and stops when it leaves (`wanted`), and cava runs only while music plays with the
-- visualizer on.

local barlayout = require("lib/barlayout")
local sysinfo = require("lib/sysinfo")
local updates = require("lib/updates")
local vizfeed = require("lib/vizfeed")

return function(ctx)
    local home = sys.ask("env", "HOME") or ""
    local folder = tostring(sys.ask("files.folder"))
    local placed = {}         -- id → true for every module the last layout placed
    local env = { screen = 1920, tray = 0, battery = false, brightness = false, bluetooth = true, playing = false }
    local readers = nil       -- starts and stops the readers; defined below, once they exist
    local geo_sent = nil      -- bar-geo.json as last written (the frame's program reads it)
    local dnd_hook = nil      -- do not disturb, looked at again when a focus block starts or ends

    -- ── Layout ─────────────────────────────────────────────────
    -- The bar's edge inset: 12 px at full width; a narrower bar (bar.width) is centred.
    local function inset_of(b) return 12 + math.floor(env.screen * (1 - (b.width or 100) / 100) / 2 + 0.5) end
    local function relayout(quiet)
        local s = ctx.settings()
        local b = s.bar
        local show, frame = {}, {}
        for _, id in ipairs(barlayout.ORDER) do
            show[id] = b.modules[id].show
            frame[id] = ctx.outline(id)
        end
        local spaces = ctx.space_count()
        local inset = inset_of(b)
        fact.bar_x0, fact.bar_x1 = inset - 6, env.screen - inset + 6     -- the bar's extent, for the strip and the rail
        local lctx = { screen = env.screen, inset = inset, gap = barlayout.gap(b.mode), ws_style = b.workspaces, ws_count = spaces,
                       visualizer = b.visualizer, tray = env.tray, battery = env.battery,
                       brightness = env.brightness, bluetooth = env.bluetooth, playing = env.playing,
                       media_mode = s.media.mode, media_idle = s.media.idle }
        local out = barlayout.layout({ left = b.left, center = b.center, right = b.right, show = show,
                                       frame = frame, mode = b.mode }, lctx)
        local grouped = {}
        for _, side in ipairs({ "left", "center", "right" }) do
            for _, entry in ipairs(b[side] or {}) do
                local ids = barlayout.split(entry) or {}
                if #ids > 1 then for _, m in ipairs(ids) do grouped[m] = true end end
            end
        end
        placed = {}
        for _, id in ipairs(barlayout.ORDER) do
            fact["g_" .. id] = grouped[id] == true
            local x = out.x[id]
            -- A module that leaves keeps its last place (`x_`), so the scene can slide the ones
            -- that stay without one flying in from nowhere when it comes back; `p_` says placed.
            if x then fact["x_" .. id] = x end
            fact["p_" .. id] = x ~= nil
            fact["w_" .. id] = barlayout.width(id, lctx)
            placed[id] = x ~= nil
        end
        -- The frame that holds the workspaces (islands mode): the helix's edges are its edges.
        fact.wsf_x, fact.wsf_w = 0, 0
        for _, f in ipairs(out.frames) do
            if out.x.workspaces and f.x <= out.x.workspaces and out.x.workspaces < f.x + f.w then
                fact.wsf_x, fact.wsf_w = f.x, f.w
                fact.wsf_a, fact.wsf_b = f.a, f.b
            end
        end
        model.frames = out.frames
        model.dividers = out.dividers
        -- the notch's pieces (a cluster that is empty has no width, and its piece is not drawn)
        local cl = out.clusters or {}
        fact.nl_x, fact.nl_w = cl.left and cl.left.x or 0, cl.left and cl.left.w or 0
        fact.nc_x, fact.nc_w = cl.center and cl.center.x or 0, cl.center and cl.center.w or 0
        fact.nr_x, fact.nr_w = cl.right and cl.right.x or 0, cl.right and cl.right.w or 0
        -- the screen frame is a program of its own (D119): where the pieces are, for its border to
        -- run round them; written only when it changes
        local geo = { left = cl.left and { x = cl.left.x, w = cl.left.w } or nil,
                      center = cl.center and { x = cl.center.x, w = cl.center.w } or nil,
                      right = cl.right and { x = cl.right.x, w = cl.right.w } or nil,
                      saving = ctx.saving() == true }
        local enc = json.encode(geo)
        if enc ~= geo_sent then geo_sent = enc; pcall(sys.call, "files.write", "bar-geo.json", geo) end
        fact.px = out.panel and out.panel.x or 0
        fact.pw = out.panel and out.panel.w or 0
        -- the spacers and gaps, which edit mode shows (and can take out): `n` = 100 · side + entry
        local gaps = {}
        for _, g in ipairs(out.spacers or {}) do
            gaps[#gaps + 1] = { x = g.x, w = g.w, own = math.floor(g.own + 0.5), fixed = g.fixed, n = 100 * (({ left = 0, center = 1, right = 2 })[g.side] or 0) + g.i }
        end
        model.edit_gaps = gaps
        if out.overflow then log("bar · the modules do not fit " .. env.screen .. " px; hide some (bar menu → modules)") end
        -- a preview while a module is carried (`quiet`) starts and stops nothing
        if readers and not quiet then readers() end
    end

    -- The screen the bar is on, in logical pixels (the layout is arithmetic on it).
    local function measure()
        run("hyprctl", { "-j", "monitors" }, function(out)
            local ok, mons = pcall(json.decode, out or "")
            if not ok or type(mons) ~= "table" then return end
            -- Every monitor has a copy of the bar and they share one layout, so it is laid out
            -- for the narrowest: it fits them all (a wider one shows it from its left edge). The
            -- focused monitor's width alone left a narrower one's bar off its edge (D34).
            local narrowest = nil
            for _, m in ipairs(mons) do
                local w = math.floor((tonumber(m.width) or 1920) / (tonumber(m.scale) or 1) + 0.5)
                if (m.transform or 0) % 2 == 1 then w = math.floor((tonumber(m.height) or 1080) / (tonumber(m.scale) or 1) + 0.5) end
                if not m.disabled and w > 0 and (not narrowest or w < narrowest) then narrowest = w end
            end
            if narrowest and narrowest ~= env.screen then env.screen = narrowest; relayout() end
        end)
    end

    -- A monitor came, went, or changed its mode or scale: each copy of the bar says so (with its
    -- own width; the last to speak would win), so Hyprland is asked for all of them again.
    on("screen_w", function() measure() end)

    -- What the machine has decides what can be placed.
    sys.watch("battery", function(v)
        local p = type(v) == "table" and v.present == true
        if p ~= env.battery then env.battery = p; relayout() end
    end)
    sys.watch("brightness", function(v)
        local p = type(v) == "table" and v.present == true
        if p ~= env.brightness then env.brightness = p; relayout() end
    end)
    sys.watch("bluetooth", function(v)
        if type(v) ~= "table" then return end
        local p = v.present ~= false
        local n = 0
        for _, d in ipairs(v.devices or {}) do if d.connected then n = n + 1 end end
        fact.bt_conn = n
        if p ~= env.bluetooth then env.bluetooth = p; relayout() end
    end)

    -- ── Tray ───────────────────────────────────────────────────
    local tray = {}
    -- What mooi draws for a tray item: its own glyph where it knows the program — the network and
    -- Bluetooth applets name icons by state (nm-signal-75, blueman-disabled), which an icon theme
    -- may not have — else the program's picture, else its initial.
    local function tray_glyph(t)
        local id, icon = string.lower(tostring(t.id or "")), string.lower(tostring(t.icon or ""))
        if id == "nm-applet" or string.find(icon, "^nm%-") or string.find(icon, "^network%-") then
            if string.find(icon, "wired") or string.find(icon, "ethernet") then return 2, 1 end
            if string.find(icon, "no%-connection") or string.find(icon, "offline") or string.find(icon, "disconnect") then return 3, 0 end
            return 1, (tonumber(string.match(icon, "(%d+)")) or 75) / 100
        end
        if string.find(id, "blueman") or string.find(icon, "^blueman") or string.find(icon, "^bluetooth") then
            if string.find(icon, "disabled") or string.find(icon, "off") then return 5, 0 end
            return 4, 1
        end
        return 0, 0
    end
    sys.watch("tray", function(list)
        tray = type(list) == "table" and list or {}
        local rows = {}
        for i, t in ipairs(tray) do
            local glyph, level = tray_glyph(t)
            local name = tostring(t.title or t.id or "")
            rows[i] = { key = t.key, title = t.title or "", icon = t.icon or "", glyph = glyph, level = level,
                        letter = string.upper(string.sub(string.match(name, "%w") or "", 1, 1)),
                        lettered = (tostring(t.icon or "") == "") and 1 or 0 }
        end
        model.tray_items = rows
        if #tray ~= env.tray then env.tray = #tray; relayout() end
    end)
    -- `tray_cmd(4·i + k)`: k 0 the click, 1 its menu, 2 the middle button, for icon i.
    on("tray_cmd", function(v)
        local n = math.floor(tonumber(v) or -1)
        local item = tray[math.floor(n / 4) + 1]
        if not item then return end
        -- An item may not have the method asked for (blueman's Activate fails on its own side):
        -- the click then asks for its menu, which is what such items expect.
        local k = n % 4
        local ok
        if k == 0 then
            ok = pcall(sys.call, "tray.activate", item.key)
            if not ok then pcall(sys.call, "tray.context", item.key) end
        elseif k == 1 then ok = pcall(sys.call, "tray.context", item.key)
        else ok = pcall(sys.call, "tray.secondary", item.key) end
        if not ok then log("bar · tray: " .. tostring(item.id) .. " did not answer that press") end
    end)

    -- ── Readers ────────────────────────────────────────────────
    local timers = {}
    local function every_while(key, ms, fn)
        if timers[key] then return end
        fn()
        timers[key] = every(ms, fn)
    end
    local function stop(key) if timers[key] then cancel(timers[key]); timers[key] = nil end end

    local cpu_prev = nil
    local function read_resources()
        run("cat", { "/proc/stat" }, function(out)
            local v; v, cpu_prev = sysinfo.cpu(out, cpu_prev)
            if v then fact.res_cpu = v end
        end)
        run("cat", { "/proc/meminfo" }, function(out)
            local f, used = sysinfo.mem(out)
            if f then fact.res_mem = f; text.res_memgb = string.format("%.1fG", used) end
        end)
        run("sensors", { "-j" }, function(out)
            local ok, t = pcall(json.decode, out or "")
            local c = ok and sysinfo.temp(t) or nil
            if c then fact.res_temp = c end
        end)
    end

    local net_prev, net_t = nil, 0
    local function read_bandwidth()
        run("cat", { "/proc/net/dev" }, function(out)
            local rx, tx = sysinfo.net(out)
            if net_prev then
                text.bw_down = sysinfo.rate((rx - net_prev.rx) / 2)
                text.bw_up = sysinfo.rate((tx - net_prev.tx) / 2)
            end
            net_prev = { rx = rx, tx = tx }
        end)
    end

    local function read_keyboard()
        run("hyprctl", { "-j", "devices" }, function(out)
            local ok, t = pcall(json.decode, out or "")
            if not ok or type(t) ~= "table" then return end
            for _, k in ipairs(t.keyboards or {}) do
                if k.main then
                    local name = tostring(k.active_keymap or "")
                    local code = string.match(name, "%((%u%u)%)") or string.upper(string.sub(name, 1, 2))
                    text.kb_code = code ~= "" and code or "--"
                    text.kb_name = name
                end
            end
        end)
    end

    local loc = nil
    local read_weather
    function read_weather()
        local function forecast()
            run("curl", { "-fsSL", "--max-time", "15", "https://api.open-meteo.com/v1/forecast?latitude=" .. loc.lat
                .. "&longitude=" .. loc.lon .. "&current=temperature_2m,weather_code,is_day" }, function(out, code)
                local ok, t = pcall(json.decode, out or "")
                if code ~= 0 or not ok or type(t) ~= "table" or type(t.current) ~= "table" then
                    -- A failed fetch (open-meteo answers 503 now and then) keeps the last good
                    -- reading on the bar, and tries again in a minute rather than in ten.
                    log("bar · weather: no answer (" .. tostring(code) .. "); trying again in 60 s")
                    after(60000, function() if placed.weather then read_weather() end end)
                    return
                end
                local kind, word = sysinfo.weather(t.current.weather_code, t.current.is_day)
                for i, k in ipairs(sysinfo.WEATHER_KINDS) do if k == kind then fact.wx_kind = i - 1 end end
                fact.wx_temp = tonumber(t.current.temperature_2m) or 0
                text.wx_word = word
                fact.wx_ok = true
            end)
        end
        if loc then forecast(); return end
        run("curl", { "-fsSL", "--max-time", "10", "https://ipinfo.io/json" }, function(out, code)
            local ok, t = pcall(json.decode, out or "")
            local lat, lon = nil, nil
            if ok and type(t) == "table" then lat, lon = string.match(tostring(t.loc or ""), "^([%d%.%-]+),([%d%.%-]+)$") end
            if code ~= 0 or not lat then
                log("bar · weather: no location (" .. tostring(code) .. "); trying again in 60 s")
                after(60000, function() if placed.weather then read_weather() end end)
                return
            end
            loc = { lat = lat, lon = lon }
            text.wx_city = string.upper(tostring(t.city or ""))
            forecast()
        end)
    end

    -- ── The visualizer: cava, while something plays ───────────
    local cava, playing = nil, false
    -- A cava that never printed a band is not installed (or cannot read PipeWire): say so once
    -- instead of respawning it on every relayout (audit 2026-10-29).
    local cava_lines, viz_missing = 0, false
    local CAVA = "cava.conf"
    sys.call("files.write", CAVA, table.concat({
        "[general]", "bars = 32", "framerate = 30",
        "[input]", "method = pipewire",
        "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
        "ascii_max_range = 1000", "bar_delimiter = 59", "frame_delimiter = 10",
        "[smoothing]", "noise_reduction = 66", "" }, "\n"))
    local sent = {}
    -- The music shows inside the music components (the bar's media module, the notch's and the
    -- Nexus's music panels, the player) and, outside them, only on the screen frame (frame.on +
    -- frame.music) and the bar's border where it joins the frame (music.rim). Both of those are the
    -- frame's own program now (D119): the bar only writes the feed it reads. No other border moves.
    local want_swell = false             -- the screen frame moves with the music: the feed is written
    local want_feed = false              -- a reader is up (the player, the notch, the Nexus): publish
    local want_viz = false               -- the media module's visualizer is placed and shown
    local feed_wanted = 0                -- until when a music panel elsewhere asked for the feed
    local swell = nil                    -- the shared analysis: level, high, bass, beat, phase, tempo
    local seq, last_ms, prev = 0, 0, nil -- the published feed and its cadence
    local silent_written = nil           -- the missing flag last written at rest
    local function publish(cand, now_ms)
        if prev and not vizfeed.should_publish(prev, cand, now_ms, last_ms, 500) then return end
        seq = seq + 1
        cand.seq = seq
        prev, last_ms, silent_written = cand, now_ms, nil
        sys.call("files.write", vizfeed.FILE, vizfeed.encode(cand))
    end
    local function rest_feed(missing)
        missing = missing == true
        if seq > 0 and prev == nil and silent_written == missing then return end
        seq = seq + 1
        local t = vizfeed.silent(seq)
        t.missing = missing
        prev, last_ms, silent_written = nil, 0, missing
        sys.call("files.write", vizfeed.FILE, vizfeed.encode(t))
    end
    local function rest_levels()
        for i = 0, 15 do fact["lv" .. i] = 0.06; sent[i] = 0.06 end
        swell = nil
    end
    local function listen()
        if cava then return end
        local mine, frame = nil, 0
        cava_lines = 0
        mine = spawn("cava", { "-p", folder .. "/" .. CAVA }, function(line)
            if cava ~= mine then return end
            cava_lines = cava_lines + 1
            frame = frame + 1
            local i, b = 0, {}
            for v in string.gmatch(line, "(%d+);") do
                if i > 31 then break end
                b[i] = math.min(1, (tonumber(v) or 0) / 1000)
                i = i + 1
            end
            if i < 32 then return end
            local bands = {}
            for j = 1, 32 do bands[j] = b[j - 1] or 0 end
            -- the media module's own visualizer: the first 16 bands, only when they moved
            if want_viz then
                for j = 0, 15 do
                    local x = bands[j + 1]
                    if math.abs(x - (sent[j] or 0)) > 0.02 then fact["lv" .. j] = x; sent[j] = x end
                end
            end
            -- One analysis, for whoever reads the feed: the frame's program (its swell and the bar's
            -- border joining it, D119), the notch's and the Nexus's music panels, the player.
            local state = vizfeed.analyse(swell, bands, 1 / 30)
            swell = state
            if want_feed or want_swell then
                publish({ bands = bands, bass = state.bass, high = state.high, beat = state.beat,
                          phase = state.phase, playing = true, missing = viz_missing }, frame * 1000 / 30)
            end
        end, function()
            if cava ~= mine then return end
            cava = nil
            -- nothing ever came out: no cava on this machine. The bar says so; a refresh or a
            -- restart tries again once it is installed.
            if cava_lines == 0 then
                viz_missing = true
                rest_levels()
                rest_feed(true)
            end
        end)
        cava = mine
    end
    local function hush()
        if cava then kill(cava, "term"); cava = nil end
        rest_levels()
        rest_feed(viz_missing)
    end
    rest_levels()
    -- The cover: a file the player names is used as it is; one on the web is fetched once
    -- into the scene's folder (the image service reads files).
    local art_url, covers = nil, 0
    local function cover(url)
        if url == art_url then return end
        art_url = url
        if type(url) ~= "string" or url == "" then text.med_art = ""; fact.med_has_art = false; return end
        local path = string.match(url, "^file://(.*)$")
        if path then text.med_art = path; fact.med_has_art = true; return end
        if string.match(url, "^https?://") then
            -- two names in turn, so the image is a new file each time and not a cached one
            covers = covers + 1
            local dest = folder .. "/cover-" .. tostring(covers % 2) .. ".img"
            run("curl", { "-fsSL", "--max-time", "8", "-o", dest, url }, function(_, code)
                if code == 0 and art_url == url then text.med_art = dest; fact.med_has_art = true end
            end)
        end
    end
    sys.watch("media", function(m)
        local now = type(m) == "table" and m.playing == true
        if type(m) == "table" then cover(m.art) end
        local changed = now ~= playing
        playing = now
        if changed then env.playing = now; relayout() elseif readers then readers() end
    end)

    -- Start what the placed modules need, stop the rest.
    readers = function()
        local s = ctx.settings()
        if placed.resources then every_while("res", 2000, read_resources) else stop("res") end
        if placed.bandwidth then every_while("bw", 2000, read_bandwidth) else stop("bw") end
        if placed.keyboard then every_while("kb", 3000, read_keyboard) else stop("kb") end
        if placed.weather then every_while("wx", 600000, read_weather) else stop("wx") end
        local still = s.motion.reduced == true or s.motion.saver == "always"
        want_swell = s.frame.on and s.frame.music and not still
        -- The frame's music follows whatever is audible, not only what the media module knows
        -- about: with frame.music on, cava runs whether or not that module says anything is
        -- playing, so a browser, a game or a video moves the frame too. For the player it runs
        -- only while something plays. Neither runs while the saver is on.
        want_viz = placed.media and s.bar.visualizer ~= "off" and s.media.mode ~= "art"
        if not want_viz then for i = 0, 15 do fact["lv" .. i] = 0.06; sent[i] = 0.06 end end
        -- the feed file is for the other programs' music panels; it is written only while one is
        -- up to read it (the player; the notch and the Nexus say so with `mooi say … feed`)
        want_feed = (ctx.player_up ~= nil and ctx.player_up() == true) or feed_wanted > os.time()
        if not (want_feed or want_swell) then rest_feed(viz_missing) end
        local want_audio = want_viz or want_swell or want_feed
        if want_audio and (playing or want_swell) and not ctx.saving() and not viz_missing then listen() else hush() end
    end

    -- the notch's or the Nexus's music panel is open: it asks again every few seconds while it is
    on("feed_want", function()
        local was = feed_wanted > os.time()
        feed_wanted = os.time() + 6
        if not was and readers then readers() end
    end)
    every(3000, function() if feed_wanted > 0 and feed_wanted <= os.time() then feed_wanted = 0; if readers then readers() end end end)

    -- ── Actions ────────────────────────────────────────────────
    local function stamp(fn) run("date", { "+%Y%m%d_%H%M%S" }, function(out) fn((out or "now"):gsub("%s+", "")) end) end

    local inhibit = nil
    fact.caffeine_on = false
    on("caffeine", function()
        if inhibit then kill(inhibit, "term"); inhibit = nil; fact.caffeine_on = false; return end
        local mine
        mine = spawn("systemd-inhibit", { "--what=idle:sleep", "--who=mooi", "--why=Keep awake", "--mode=block", "sleep", "infinity" },
            function() end, function() if inhibit == mine then inhibit = nil; fact.caffeine_on = false end end)
        inhibit = mine
        fact.caffeine_on = true
    end)

    -- ── System updates (lib/updates) ───────────────────────────
    -- While the module is on the bar: an hour after the last look (and soon after starting) it
    -- asks pacman (checkupdates, which never touches the real database), the AUR helper and
    -- Flatpak how many are waiting; more than last time is a notice. A press runs the updater in
    -- a terminal, and its closing looks again.
    local have = {}
    for _, tool in ipairs({ "paru", "yay", "flatpak" }) do
        run(tool, { "--version" }, function(_, code) have[tool] = code == 0 end)
    end
    local upd = { last = nil, at = nil, busy = false, term = nil }
    fact.upd_n = 0; fact.upd_busy = false; fact.upd_running = false
    text.upd_t = "Checking for updates…"
    local function look()
        if upd.busy then return end
        upd.busy = true; fact.upd_busy = true
        local got, repo, aur, flat = 0, 0, 0, 0
        local want = 1 + ((have.paru or have.yay) and 1 or 0) + (have.flatpak and 1 or 0)
        local function done()
            got = got + 1
            if got < want then return end
            local s = updates.summary(repo, aur, flat)
            if updates.should_notify(upd.last, s.total) and ctx.signal then ctx.signal("Updates", "Updates are waiting", s.text) end
            upd.last, upd.at, upd.busy = s.total, os.time(), false
            fact.upd_n = s.total; fact.upd_busy = false
            text.upd_t = s.text
            -- the Control Nexus reads it (D98)
            pcall(sys.call, "files.write", "updates.json", require("lib/nexusfeed").updates_doc(s.total, s.text, upd.at))
        end
        run("checkupdates", {}, function(out) repo = updates.count_pkgs(out); done() end)
        if have.paru or have.yay then run(have.paru and "paru" or "yay", { "-Qua" }, function(out) aur = updates.count_pkgs(out); done() end) end
        if have.flatpak then run("flatpak", { "remote-ls", "--updates", "--columns=application" }, function(out) flat = updates.count_apps(out); done() end) end
    end
    every(300000, function()
        if fact.p_updates and not upd.term and (not upd.at or os.time() - upd.at >= 3600) then look() end
    end)
    after(45000, function() if fact.p_updates then look() end end)
    on("run_updates", function()
        if upd.term then return end
        local mine
        local ok, id = pcall(spawn, "kitty", { "--title", "mooi · updates", "--class", "mooi-updates", "sh", "-c", updates.command(have) },
            function() end, function()
                if upd.term ~= mine then return end
                upd.term = nil; fact.upd_running = false
                look()
            end)
        if not ok then log("updates · the terminal did not start: " .. tostring(id)); return end
        mine = id
        upd.term = mine
        fact.upd_running = true
    end)

    -- Recording: wf-recorder into ~/Videos; 0 the whole screen, 1 an area (slurp). Pressed
    -- again, it stops (asked, not killed, so the file is finished).
    local rec = nil
    fact.recording = false
    on("record", function(v)
        if rec then kill(rec, "int"); return end
        local function go(args)
            stamp(function(t)
                run("mkdir", { "-p", home .. "/Videos" }, function()
                    args[#args + 1] = "-f"; args[#args + 1] = home .. "/Videos/mooi_" .. t .. ".mp4"
                    local mine
                    mine = spawn("wf-recorder", args, function() end, function()
                        if rec == mine then rec = nil; fact.recording = false; log("bar · recording saved in ~/Videos") end
                    end)
                    rec = mine
                    fact.recording = true
                end)
            end)
        end
        if (tonumber(v) or 0) > 0.5 then
            run("slurp", {}, function(geo, code) if code == 0 and geo and geo ~= "" then go({ "-g", (geo:gsub("%s+$", "")) }) end end)
        else go({}) end
    end)

    -- Screenshots: into ~/Pictures/Screenshots and onto the clipboard; 0 an area, 1 the screen.
    on("shot", function(v)
        local function take(args)
            stamp(function(t)
                local dir = home .. "/Pictures/Screenshots"
                local file = dir .. "/mooi_" .. t .. ".png"
                run("mkdir", { "-p", dir }, function()
                    args[#args + 1] = file
                    run("grim", args, function(_, code)
                        if code == 0 then run("wl-copy", { "--type", "image/png" }, nil, { stdin = file, output = false }) end
                    end)
                end)
            end)
        end
        if (tonumber(v) or 0) > 0.5 then take({}) else
            run("slurp", {}, function(geo, code) if code == 0 and geo and geo ~= "" then take({ "-g", (geo:gsub("%s+$", "")) }) end end)
        end
    end)

    -- Clipboard history (cliphist): the last fourteen text entries; choosing one copies it.
    local clips = {}
    on("clips", function()
        run("cliphist", { "list" }, function(out)
            clips = {}
            for line in string.gmatch(out or "", "[^\n]+") do
                local id, body = string.match(line, "^(%d+)\t(.*)$")
                if id and not string.find(body, "^%[%[ binary") and #clips < 14 then
                    clips[#clips + 1] = { id = id, text = body }
                end
            end
            model.clips = clips
        end)
    end)
    on("clip_pick", function(v)
        local c = clips[math.floor(tonumber(v) or -1) + 1]
        if not c then return end
        run("cliphist", { "decode", c.id }, function(out, code)
            -- on its input, not its command line: an argument is visible to every process
            -- (ps) and has a length limit; `output = false`, since wl-copy stays to serve it
            if code == 0 and out then run("wl-copy", {}, nil, { input = out, output = false }) end
        end)
    end)

    -- Power: the session menu (wlogout, as ArchEclipse), or lock now.
    on("power", function(v)
        if (tonumber(v) or 0) > 0.5 then run("hyprlock", {}) else run("wlogout", { "-b", "5", "-p", "layer-shell" }) end
    end)

    -- ── Focus timer ────────────────────────────────────────────
    -- A block of work (`foc_len` minutes, 25 to start, 5 to 90 by the wheel), then a break of a
    -- fifth of it, at least five minutes; the toast says when each ends. Counted here by the
    -- second, and only while it runs.
    local foc = { left = 0, total = 0, timer = nil }
    local function foc_rest_text() text.foc_left = string.format("%02d:00", fact.foc_len) end
    local function foc_show()
        fact.foc_frac = foc.total > 0 and foc.left / foc.total or 0
        text.foc_left = string.format("%02d:%02d", math.floor(foc.left / 60), foc.left % 60)
    end
    local function foc_toast(title, body)
        if ctx.signal then ctx.signal("Focus", title, body) end
    end
    local function foc_stop()
        if foc.timer then cancel(foc.timer); foc.timer = nil end
        foc.left, foc.total = 0, 0
        fact.foc_state = 0; fact.foc_frac = 0
        if dnd_hook then dnd_hook() end
        foc_rest_text()
    end
    local function break_minutes() return math.max(5, math.floor(fact.foc_len / 5 + 0.5)) end
    local foc_phase
    function foc_phase(state)
        if foc.timer then cancel(foc.timer); foc.timer = nil end
        foc.total = (state == 1 and fact.foc_len or break_minutes()) * 60
        foc.left = foc.total
        fact.foc_state = state
        if dnd_hook then dnd_hook() end
        foc_show()
        foc.timer = every(1000, function()
            foc.left = foc.left - 1
            if foc.left > 0 then foc_show() return end
            if state == 1 then
                if ctx.bmo then ctx.bmo(3) end
                foc_toast("Time for a break", string.format("%d minutes of focus done · %d minutes off", fact.foc_len, break_minutes()))
                foc_phase(2)
            else
                if ctx.bmo then ctx.bmo(4) end
                foc_toast("Break over", "Press the timer for the next block")
                foc_stop()
            end
        end)
    end
    foc_rest_text()
    on("focus_cmd", function(v)
        local n = math.floor(tonumber(v) or -1)
        if n == 0 then
            if fact.foc_state > 0 then foc_stop(); if ctx.bmo then ctx.bmo(5) end
            else foc_phase(1); if ctx.bmo then ctx.bmo(2) end end
        elseif n == 1 then
            if fact.foc_state == 1 then foc_phase(2) elseif fact.foc_state == 2 then foc_stop() end
        elseif (n == 2 or n == 3) and fact.foc_state == 0 then
            fact.foc_len = math.max(5, math.min(90, fact.foc_len + (n == 2 and 5 or -5)))
            foc_rest_text()
        end
    end)

    -- The microphone.
    on("mic_mute", function() sys.call("audio.input_mute") end)
    on("mic_vol", function(v) local n = tonumber(v); if n then sys.call("audio.input", math.max(0, math.min(1, n))) end end)

    -- ── Notifications ──────────────────────────────────────────
    -- Signal Loom (shell/signals.luau, D50) receives and shows them; the bar's bell reads its facts.
    -- A focus block starting or ending moves the quiet time with it.
    dnd_hook = function() if ctx.requiet then ctx.requiet() end end

    -- ── Edit mode ──────────────────────────────────────────────
    -- The scene says when edit mode begins and ends, and where a dragged module is: while it
    -- moves, the layout is planned with the module at the pointer (`edit_hover`), so the
    -- others make room live; dropped (`edit_drop`) it is written. Dropped on the shelf (below
    -- the bar) it is hidden; dragged from the shelf onto the bar it is shown. Escape puts the
    -- layout back as edit mode found it. `n = 100000 · module + x (+ 50000 off the bar)`.
    local NAMES = { workspaces = "Workspaces", window = "Window", media = "Media", resources = "Resources",
        bandwidth = "Bandwidth", keyboard = "Keyboard", weather = "Weather", tray = "Tray", notifications = "Notices",
        mic = "Mic", volume = "Volume", brightness = "Brightness", battery = "Battery", network = "Network",
        bluetooth = "Bluetooth", clock = "Clock", caffeine = "Keep awake", recorder = "Recorder", screenshot = "Screenshot",
        clipboard = "Clipboard", power = "Session", actions = "Win actions", overview = "Overview", core = "Search",
        focus = "Focus", settings = "Settings", notes = "Quick notes", wallpaper = "Wallpaper", updates = "Updates" }
    local editing = nil      -- the layout a drag plans from: as edit mode found it, then as last dropped
    local previewed = nil    -- the last preview shown, so a pointer that moves within one place costs nothing
    local original = nil     -- the layout as edit mode found it, for Escape
    local function shelf()
        local items = {}
        for i, id in ipairs(barlayout.ORDER) do
            if not placed[id] then items[#items + 1] = { i = i - 1, name = NAMES[id] } end
        end
        model.shelf_items = items
    end
    local function decode(n)
        n = math.floor(tonumber(n) or -1)
        local id = barlayout.ORDER[math.floor(n / 100000) + 1]
        local rest = n % 100000
        return id, rest % 50000, rest >= 50000
    end
    local function plan(id, x, off)
        local b = ctx.settings().bar
        local cfg = { left = b.left, center = b.center, right = b.right, mode = b.mode, show = {} }
        for _, m in ipairs(barlayout.ORDER) do cfg.show[m] = b.modules[m].show end
        cfg.show[id] = true
        local lctx = { screen = env.screen, inset = inset_of(b), gap = barlayout.gap(b.mode), ws_style = b.workspaces, ws_count = ctx.space_count(),
                       visualizer = b.visualizer, tray = env.tray, battery = env.battery, brightness = env.brightness,
                       bluetooth = env.bluetooth, playing = env.playing, media_mode = ctx.settings().media.mode,
                       media_idle = ctx.settings().media.idle }
        if off then return barlayout.without(cfg, id) end
        return barlayout.drop(cfg, lctx, id, x)
    end
    local function use(lists)
        local b = ctx.settings().bar
        b.left, b.center, b.right = lists.left, lists.center, lists.right
    end
    on("edit_mode", function(v)
        if (tonumber(v) or 0) > 0.5 then
            local b = ctx.settings().bar
            editing = { left = {}, center = {}, right = {}, show = {} }
            for _, side in ipairs({ "left", "center", "right" }) do
                for i, e in ipairs(b[side]) do editing[side][i] = e end
            end
            for _, m in ipairs(barlayout.ORDER) do editing.show[m] = b.modules[m].show end
            original = { left = {}, center = {}, right = {}, show = {} }
            for _, side in ipairs({ "left", "center", "right" }) do
                for i, e in ipairs(b[side]) do original[side][i] = e end
            end
            for m, v in pairs(editing.show) do original.show[m] = v end
            shelf()
        else
            editing, original = nil, nil
        end
    end)
    on("edit_hover", function(n)
        if not editing then return end
        local id, x, off = decode(n)
        if not id then return end
        -- The preview is only what the scene shows: lay the candidate out, then put the
        -- settings back as edit mode holds them (a drop plans from that again).
        local b = ctx.settings().bar
        local shown = b.modules[id].show
        local lists = plan(id, x, off)
        -- the hint: will this drop join a group (the target lights), or take a place of its own
        local merged = false
        for _, side in ipairs({ "left", "center", "right" }) do
            for _, e in ipairs(lists[side]) do
                local ids = barlayout.split(e) or {}
                if #ids > 1 then for _, m in ipairs(ids) do if m == id then merged = true end end end
            end
        end
        local was_grouped = false
        for _, side in ipairs({ "left", "center", "right" }) do
            for _, e in ipairs(editing[side]) do
                local ids = barlayout.split(e) or {}
                if #ids > 1 then for _, m in ipairs(ids) do if m == id then was_grouped = true end end end
            end
        end
        fact.ed_merge = merged and not was_grouped
        -- The scene asks every few pixels; the layout only changes when the drop would land
        -- somewhere else, and only then is it laid out again (it was every few pixels, with the
        -- readers stopped and started each time: the drag stuttered).
        -- A gap's width follows the pointer pixel by pixel; it is the drop that measures it, so
        -- the preview changes only when the order does (the modules stay still in between).
        local key = string.gsub(table.concat(lists.left, ",") .. "|" .. table.concat(lists.center, ",") .. "|"
            .. table.concat(lists.right, ",") .. "|" .. id .. (off and "!" or ""), "gap:%d+", "gap:*")
        if key == previewed then return end
        previewed = key
        use(editing); use(lists)
        b.modules[id].show = not off
        relayout(true)
        use(editing)
        b.modules[id].show = shown
    end)
    on("edit_drop", function(n)
        previewed = nil
        if not editing then return end
        local id, x, off = decode(n)
        if not id then return end
        local b = ctx.settings().bar
        use(editing); use(plan(id, x, off))
        b.modules[id].show = not off
        fact.ed_merge = false
        ctx.save()
        -- the next drag plans from what was just dropped
        for _, side in ipairs({ "left", "center", "right" }) do
            editing[side] = {}
            for i, e in ipairs(b[side]) do editing[side][i] = e end
        end
        relayout(); shelf()
    end)
    on("edit_cancel", function()
        previewed = nil
        if not original then return end
        local b = ctx.settings().bar
        use(original)
        for _, m in ipairs(barlayout.ORDER) do b.modules[m].show = original.show[m] end
        ctx.save()
        relayout(); shelf()
    end)
    on("edit_reset", function()
        local b = ctx.settings().bar
        for _, side in ipairs({ "left", "center", "right" }) do
            b[side] = {}
            for i, e in ipairs(barlayout.DEFAULT[side]) do b[side][i] = e end
        end
        for _, m in ipairs(barlayout.ORDER) do b.modules[m].show = true end
        ctx.save()
        if editing then use(b) end
        relayout(); shelf()
    end)

    -- A spacer or a gap taken out (edit mode's × on it): `100 · side + entry`.
    on("edit_gap", function(v)
        local n = math.floor(tonumber(v) or -1)
        local side = ({ [0] = "left", [1] = "center", [2] = "right" })[math.floor(n / 100)]
        local b = ctx.settings().bar
        local list = side and b[side]
        if not list or not barlayout.is_spacer(list[n % 100]) then return end
        table.remove(list, n % 100)
        ctx.save()
        if editing then
            for _, sd in ipairs({ "left", "center", "right" }) do
                editing[sd] = {}
                for i, e in ipairs(b[sd]) do editing[sd][i] = e end
            end
        end
        relayout(); shelf()
    end)

    -- ── Edit mode's buttons and arrows ──────────────────────────
    -- `edit_op(10 · module + op)`: 0 one place left, 1 one place right, 2 merge with the one
    -- before, 3 merge with the one after, 4 split out of its group, 5 hide (lib/barlayout).
    on("edit_op", function(v)
        local n = math.floor(tonumber(v) or -1)
        local id = barlayout.ORDER[math.floor(n / 10) + 1]
        local op = n % 10
        if not id then return end
        local b = ctx.settings().bar
        if op == 5 then b.modules[id].show = false
        else
            local lists
            if op == 0 then lists = barlayout.nudge(b, id, -1)
            elseif op == 1 then lists = barlayout.nudge(b, id, 1)
            elseif op == 2 then lists = barlayout.join(b, id, -1)
            elseif op == 3 then lists = barlayout.join(b, id, 1)
            else lists = barlayout.join(b, id, 0) end
            use(lists)
        end
        ctx.save()
        if editing then
            for _, side in ipairs({ "left", "center", "right" }) do
                editing[side] = {}
                for i, e in ipairs(b[side]) do editing[side][i] = e end
            end
        end
        relayout(); shelf()
    end)

    measure()
    relayout()
    return { relayout = relayout, measure = measure }
end
