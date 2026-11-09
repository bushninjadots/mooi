-- The widgets below, fed (D215): the notices, the wallpapers, the settings' pages, the controls and Launch's
-- grid — what their drawings (shell/ui/wbelow.plm) read, and what their presses do. A logic module of
-- mooi-widgets.luau, whose main chunk is near Lua's 200 locals: `require("lib/wbelow_feed")(ctx)`.
-- ctx: doc() (the widgets now), first(kind) → widget, options, commit(doc) (saved, not undoable),
-- read(name, kind). The services mooi-widgets already watches (audio, battery, apps, the notices' feed) reach
-- this through the hooks it returns; it watches network, Bluetooth, brightness and the wallpapers' index.

local WB = require("lib/wbelow")

return function(ctx)
    local F = {}
    local notes, walls, apps, q = {}, {}, {}, ""
    local net, bt, vol, bri, bat = nil, nil, nil, nil, nil
    local arm_token = 0

    local function opts(kind) local _, o = ctx.first(kind); return o or {} end
    local function say_mooi(cmd) run("pleamar", { "--say", "mooi", cmd }, function() end) end

    -- ── the notices: the bar's feed, newest first ──
    local function show_notices()
        local o = opts("notices")
        fact.nc_rows = math.max(3, math.min(6, tonumber(o.nrows) or 4))
        local rows = {}
        for i = 1, math.min(6, #notes) do
            local n = notes[i]
            local a1 = type(n.actions) == "table" and n.actions[1] or nil
            rows[i] = { title = tostring(n.title or ""), app = tostring(n.app or ""), ago = tostring(n.ago or ""),
                        act = type(a1) == "string" and a1 ~= "", a1 = type(a1) == "string" and a1 or "" }
        end
        model.nc = rows
        fact.nc_n = #notes
    end
    function F.notices(feed)
        notes = type(feed) == "table" and type(feed.items) == "table" and feed.items or {}
        show_notices()
    end
    -- row * 10 + 0 its default (or the Nexus) · 1 its action · 9 dismiss; 90 every one
    local function notice_go(v)
        v = math.floor(tonumber(v) or -1)
        if v == 90 then say_mooi("emit note_clear"); return end
        local row, what = v // 10, v % 10
        local n = notes[row + 1]
        if not n then return end
        if what == 0 and not n.default then run("mooi", { "nexus" }, function() end); return end
        say_mooi("emit note_act " .. tostring(row * 10 + what))
    end
    on("nc_go", notice_go)

    -- ── the wallpapers: the six newest of the picker's index ──
    local function show_walls()
        walls = WB.walls(ctx.read("walls-index.json", "json"), 6)
        local rows = {}
        for i, w in ipairs(walls) do rows[i] = { pic = w.thumb } end
        model.wp = rows
        fact.wp_n = #walls
    end
    pcall(sys.watch, "files:walls-index.json", show_walls)
    on("wp_go", function(v)
        local w = walls[math.floor(tonumber(v) or -1) + 1]
        if w then run("mooi", { "wall", "apply", w.path }, function() end) end
    end)

    -- ── the settings' pages ──
    local function page_go(v)
        local p = WB.SETTINGS[math.floor(tonumber(v) or -1) + 1]
        if p then say_mooi("emit open_settings_at " .. tostring(p[2])) end
    end
    on("pg_go", page_go)

    -- ── the controls ──
    local function pct(v) return tostring(math.floor((tonumber(v) or 0) * 100 + 0.5)) end
    local function show_controls()
        local o = opts("controls")
        fact.ct_s1, fact.ct_s2, fact.ct_s3 = o.wifi ~= false, o.bt ~= false, o.volume ~= false
        fact.ct_s4, fact.ct_s5, fact.ct_s6 = o.bright ~= false, o.battery ~= false, o.power ~= false
        fact.ct_wifi = net ~= nil and net.wifi == true
        text.ct_wifi_t = net and (not net.wifi and "off" or (net.online and tostring(net.name or "on") or "on")) or "off"
        fact.ct_bt = bt ~= nil and bt.powered == true
        text.ct_bt_t = bt and (((bt.connected or 0) > 0 and tostring(bt.connected)) or (bt.powered and "on" or "off")) or "off"
        fact.ct_vol = vol and vol.volume or 0
        text.ct_vol_t = vol and (vol.muted and "muted" or pct(vol.volume)) or ""
        fact.ct_bri = bri or 0
        text.ct_bri_t = bri and pct(bri) or ""
        fact.ct_bat_on = bat ~= nil
        fact.ct_bat = bat and math.max(0, math.min(1, bat.percent / 100)) or 0
        text.ct_bat_t = bat and (tostring(math.floor(bat.percent + 0.5)) .. "%" .. (bat.charging and "+" or "")) or ""
    end
    function F.audio(a)
        if type(a) ~= "table" then return end
        vol = { volume = tonumber(a.volume) or 0, muted = a.muted == true }
        show_controls()
    end
    function F.battery(b)
        bat = (type(b) == "table" and b.present ~= false and tonumber(b.percent)) and { percent = tonumber(b.percent), charging = b.charging == true } or nil
        show_controls()
    end
    pcall(sys.watch, "network", function(n)
        if type(n) ~= "table" then return end
        net = { online = n.online == true, wifi = n.wifi ~= false, name = n.name }
        show_controls()
    end)
    pcall(sys.watch, "bluetooth", function(v)
        if type(v) ~= "table" then return end
        local c = 0
        for _, d in ipairs(v.devices or {}) do if d.connected then c = c + 1 end end
        bt = { powered = v.powered == true, connected = c }
        show_controls()
    end)
    pcall(sys.watch, "brightness", function(b)
        if type(b) ~= "table" or b.present == false then bri = nil; show_controls(); return end
        local lv = tonumber(b.level)
        if lv and lv > 1 then lv = lv / 100 end
        bri = lv
        show_controls()
    end)
    local function power_close() fact.ct_pw_open, fact.ct_pw_arm = false, 0 end
    on("ct_go", function(v)
        v = math.floor(tonumber(v) or 0)
        if v == 1 then run("nmcli", { "radio", "wifi", (net and net.wifi) and "off" or "on" }, function() end)
        elseif v == 2 then run("bluetoothctl", { "power", (bt and bt.powered) and "off" or "on" }, function() end)
        elseif v == 6 then fact.ct_pw_open, fact.ct_pw_arm = not fact.ct_pw_open, 0 end
    end)
    on("ct_wheel", function(v)
        v = math.floor(tonumber(v) or 0)
        local k, d = v // 10, (v % 10 == 1) and 0.05 or -0.05
        if k == 3 and vol then pcall(sys.call, "audio.volume", math.max(0, math.min(1, vol.volume + d)))
        elseif k == 4 and bri then pcall(sys.call, "brightness.level", math.max(0.01, math.min(1, bri + d))) end
    end)
    -- lock and sleep go at once; log out, restart and shut down ask again within 3 s (each for itself)
    on("ct_pw", function(v)
        local n = math.floor(tonumber(v) or 0)
        if n < 1 or n > 5 then return end
        if n >= 3 and opts("controls").power_confirm ~= false and fact.ct_pw_arm ~= n then
            fact.ct_pw_arm = n
            arm_token = arm_token + 1
            local mine = arm_token
            after(3000, function() if arm_token == mine and fact.ct_pw_arm == n then fact.ct_pw_arm = 0 end end)
            return
        end
        power_close()
        if n == 1 then run("mooi", { "lock" }, function() end)
        elseif n == 2 then run("systemctl", { "suspend" }, function() end)
        elseif n == 3 then run("hyprctl", { "eval", "hl.dispatch(hl.dsp.exit())" }, function() end)
        elseif n == 4 then run("systemctl", { "reboot" }, function() end)
        elseif n == 5 then run("systemctl", { "poweroff" }, function() end) end
    end)

    -- ── Launch's grid: the most launched, filtered by what is typed ──
    local grid = {}
    local function show_grid()
        local d = ctx.doc()
        grid = WB.grid_apps(apps, d and d.launch_counts or {}, q, 12)
        local rows = {}
        for i, a in ipairs(grid) do
            local name = tostring(a.name or a.id or "")
            local icon = type(a.icon) == "string" and a.icon or ""
            rows[i] = { name = name, icon = icon, iconed = icon ~= "", letter = string.upper(string.sub(name ~= "" and name or "?", 1, 1)) }
        end
        model.lg = rows
        text.ln_q = q ~= "" and ("· " .. q .. "_") or ""
    end
    function F.apps(list) apps = type(list) == "table" and list or {}; show_grid() end
    local function grid_go(v)
        local a = grid[math.floor(tonumber(v) or -1) + 1]
        if not a then return end
        pcall(sys.call, "apps.launch", a.exec)
        local d = ctx.doc()
        if d and a.id then
            d.launch_counts = d.launch_counts or {}
            d.launch_counts[a.id] = (d.launch_counts[a.id] or 0) + 1
            ctx.commit(d)
        end
        show_grid()
    end
    on("lg_go", grid_go)
    -- 8 rubs one out, 27 clears, a printable letter is added
    on("ln_type", function(v)
        v = math.floor(tonumber(v) or 0)
        if v == 27 then q = ""
        elseif v == 8 then q = string.sub(q, 1, -2)
        elseif v >= 32 and v < 127 and #q < 24 then q = q .. string.char(v) end
        show_grid()
    end)

    -- ── Return on a snapped widget (D216): its main press, where it has one ──
    -- (mooi-widgets lends what lives in its own chunk: F.press_with.shelf and F.press_with.timer)
    F.press_with = {}
    local PRESS = {}
    PRESS.nowplaying = function() pcall(sys.call, "media.toggle") end
    PRESS.launch = function(w)
        if w.layout == "grid" then grid_go(0) elseif F.press_with.shelf then F.press_with.shelf(0) end
    end
    PRESS.notices = function() notice_go(0) end
    PRESS.wallpapers = function() say_mooi("emit open_wallpaper") end
    PRESS.settings = function() page_go(0) end
    PRESS.timer = function() if F.press_with.timer then F.press_with.timer(0) end end
    on("wg_press", function(v)
        local d = ctx.doc()
        local w = d and type(d.widgets) == "table" and d.widgets[math.floor(tonumber(v) or -1) + 1]
        local press = type(w) == "table" and PRESS[w.kind]
        if press then press(w) end
    end)

    -- whatever the widgets were told (their options changed, the file reloaded)
    function F.refresh() show_notices(); show_controls(); show_grid() end

    show_walls()
    show_controls()
    return F
end
