-- Push up from below (the Subsurface spec §9, §9a; D217), run: a logic module of mooi-surface (whose main chunk
-- holds the Sigil and the opening), `require("lib/surface/light")(ctx)`. It watches nothing itself — mooi-surface's
-- watchers call it (one watcher per service): song(music), notice(item), news(count), clock(time), window(w),
-- refresh() for the settings and the widgets, opening(open). The decisions are lib/surface/skin's; this writes the
-- scene's facts: the rest (sk_*: the glow, the moving wallpaper, the hour's sweep), the push (pu_*: the bulge and
-- the words) and the light (lt_*: the spark, its line to the app's window, the border).
-- ctx: settings() → settings, widgets() → widgets.json's list, bar_h() → the bar's strip, open() → the opening
-- shows, scr() → { w, h }.

local skin = require("lib/surface/skin")
local hypr = require("lib/hypr")
local mu = require("lib/surface/music")        -- D223
local vizfeed = require("lib/vizfeed")

-- the light's beats (ms): the spark, then the line, then the border, the line and border fade, the spark fades
local LT_TRAVEL, LT_BORDER, LT_FADE, LT_SPARK, LT_END = 300, 1000, 2600, 6000, 6600
-- the push: the bulge rises and settles, the words stay a while
local PU_SETTLE, PU_WORDS, PU_END = 500, 3800, 4600
-- the hour's sweep
local SW_HIDE, SW_BACK, SW_END = 2200, 3200, 4400

return function(ctx)
    local F = {}
    local push_q, light_q = skin.queue(), skin.queue()
    local last_title, playing, news, full, sweeping, was_open = nil, false, 0, false, false, nil
    local covered, trying, try_token, recheck = 0, false, 0, false
    local last_app = nil      -- D223: the app of the newest notice, for a press on its spark
    local last_time, full_at = nil, -1e9

    local function su() local s = ctx.settings(); return type(s.surface) == "table" and s.surface or {} end
    local function reduced() local s = ctx.settings(); return type(s.motion) == "table" and s.motion.reduced == true end
    local function contrast() local s = ctx.settings(); return type(s.theme) == "table" and tonumber(s.theme.contrast) == 1 end
    -- may anything reach up now: Surface on, the opening shut, no window fullscreen
    local function may() return su().on == true and not ctx.open() and not full end
    local function centre(b) if b then return b.x + b.w / 2, b.y + b.h / 2 end; return -9999, -9999 end

    -- ── Live wallpaper (D219): the picture moves, round the widgets that move it or all of it ──
    local SCR0 = { x = -9999, y = -9999, w = 1, h = 1 }
    local function live_now()
        local L, ws, bar = skin.live(ctx.settings()), ctx.widgets(), ctx.bar_h()
        local scr = ctx.scr()
        local whole = L.where == "whole"
        local screen = { x = 0, y = 0, w = scr.w, h = scr.h }
        local vz = whole and screen or skin.target(ws, "visualiser", "moves", bar)
        local ck = whole and screen or skin.target(ws, "clock", "moves", bar)
        local resting = not L.on or ctx.open() or full or reduced() or (whole and covered >= 0.9)
        local any = false
        fact.lw_whole = whole
        fact.lw_speed = L.speed
        fact.lw_boost = trying and 0.6 or 0
        for _, k in ipairs(skin.LIVE_FX) do
            local e = L.fx[k]
            local box = (k == "sweep") and ck or vz
            local wants = e.on and box ~= nil and not resting
            if k == "ripple" or k == "breathe" then wants = wants and (playing or trying)
            elseif k == "sweep" then wants = wants and (sweeping or trying) end
            any = any or wants
            local b = box or SCR0
            local r = whole and 0 or skin.reach(e.size)
            fact["lw_" .. k] = wants
            fact["lw_" .. k .. "_x"], fact["lw_" .. k .. "_y"] = b.x - r, b.y - r
            fact["lw_" .. k .. "_w"], fact["lw_" .. k .. "_h"] = b.w + 2 * r, b.h + 2 * r
            fact["lw_" .. k .. "_bx"], fact["lw_" .. k .. "_by"], fact["lw_" .. k .. "_bw"], fact["lw_" .. k .. "_bh"] = b.x, b.y, b.w, b.h
            fact["lw_" .. k .. "_p"] = skin.pack(skin.LIVE_MODE[k], e.strength, e.size, e.blend)
            fact["lw_" .. k .. "_s"] = math.min(99, e.strength)
        end
        -- D223: Music in the picture — where it grows from (surface.json's places), and whether it draws now
        local P = ctx.music and ctx.music() or mu.read(nil)
        local m_wants = L.music.on and not resting and (playing or trying)
        if covered >= 0.9 then m_wants = false end
        local e = mu.edge_rect(scr, P.edge_at, L.music.height)
        fact.mu_e = P.edge
        fact.mu_ex, fact.mu_ey, fact.mu_ew, fact.mu_eh = e.x, e.y, e.w, e.h
        for i = 1, mu.AREAS do
            local a = P.areas[i]
            fact["mu_a" .. i] = a ~= nil
            if a then fact["mu_a" .. i .. "x"], fact["mu_a" .. i .. "y"], fact["mu_a" .. i .. "w"], fact["mu_a" .. i .. "h"] = a.x, a.y, a.w, a.h end
        end
        for i = 1, mu.COLOURS do
            local c = P.colours[i]
            fact["mu_c" .. i] = c ~= nil
            local v = mu.hex(c)
            fact["mu_c" .. i .. "v"] = v
            fact["mu_c" .. i .. "r"], fact["mu_c" .. i .. "g"], fact["mu_c" .. i .. "b"] = (v // 65536) / 255, ((v // 256) % 256) / 255, (v % 256) / 255
        end
        local cut = ctx.cut and ctx.cut() or ""
        fact.mu_s = P.subject and cut ~= ""
        fact.lw_music = m_wants and (P.edge or #P.areas > 0 or #P.colours > 0 or fact.mu_s)
        fact.lw_music_p = skin.pack(5, L.music.strength, L.music.size, L.music.blend)
        fact.lw_on = any or fact.lw_music
    end

    -- ── the rest: the glow through (the Subsurface's) ──
    local function rest()
        local s, ws, bar = su(), ctx.widgets(), ctx.bar_h()
        local glow = s.glow == "off" and 0 or (s.glow == "bright" and 2 or 1)
        local np = skin.target(ws, "nowplaying", "woven", bar)
        local nc = skin.target(ws, "notices", "woven", bar)
        fact.sk_g = glow
        fact.sk_mx, fact.sk_my = centre(np)
        fact.sk_mp = np ~= nil and playing and glow > 0
        fact.sk_nx, fact.sk_ny = centre(nc)
        fact.sk_nn = nc ~= nil and news > 0 and glow > 0
        fact.sk_on = may() and (fact.sk_mp or fact.sk_nn)
        live_now()
    end
    F.refresh = rest

    -- ── the push: a bulge in the wallpaper over the widget, its words pressing up ──
    local start_push
    local function next_push()
        local nx = skin.done(push_q)
        if nx then start_push(nx) end
    end
    start_push = function(item)
        -- the moment passed (the opening opened, a window went fullscreen): nothing waits
        if not may() or su().push == false then fact.pu_on = false; push_q.busy, push_q.waiting = false, nil; return end
        local b = item.box
        fact.pu_x, fact.pu_y, fact.pu_w, fact.pu_h = b.x, b.y, b.w, b.h
        text.pu_words = item.words
        fact.pu_plate = contrast()
        fact.pu_on = true
        fact.pu_bt = reduced() and 0 or 1
        fact.pu_wt = 1
        after(PU_SETTLE, function() fact.pu_bt = 0 end)
        after(PU_WORDS, function() fact.pu_wt = 0 end)
        after(PU_END, function() fact.pu_on = false; next_push() end)
    end
    local function push(kind, data)
        if not may() or su().push == false then return end
        local box = skin.target(ctx.widgets(), kind, "woven", ctx.bar_h())
        local words = skin.words(kind, data)
        if not box or words == "" then return end
        local item = { kind = kind, box = box, words = words }
        if skin.push(push_q, item) then start_push(item) end
    end

    -- ── the light: a spark at the Notices, a line to the app's window, once round its border ──
    local start_light
    local function next_light()
        local nx = skin.done(light_q)
        if nx then start_light(nx) end
    end
    local function light_off()
        fact.lt_on, fact.lt_st, fact.lt_tt, fact.lt_bt, fact.lt_kt = false, 0, 0, 0, 0
        fact.lt_fon = false
    end
    start_light = function(item)
        -- the windows of the workspace shown, the monitor's origin and the focused window: read now (a notice is rare)
        run("hyprctl", { "-j", "monitors" }, function(mo)
            local okm, mons = pcall(json.decode, mo or "")
            local mon, ws = { x = 0, y = 0 }, nil
            for _, m in ipairs(okm and type(mons) == "table" and mons or {}) do
                if m.focused then
                    mon = { x = tonumber(m.x) or 0, y = tonumber(m.y) or 0 }
                    ws = type(m.activeWorkspace) == "table" and m.activeWorkspace.id or nil
                end
            end
            run("hyprctl", { "-j", "clients" }, function(co)
                local okc, clients = pcall(json.decode, co or "")
                clients = okc and type(clients) == "table" and clients or {}
                run("hyprctl", { "-j", "activewindow" }, function(ao)
                    local oka, aw = pcall(json.decode, ao or "")
                    local focused = oka and type(aw) == "table" and aw.address or nil
                    if skin.fullscreen(clients, ws) or not may() then light_off(); next_light(); return end
                    local list, bar = ctx.widgets(), ctx.bar_h()
                    local box = skin.target(list, "notices", "woven", bar) or skin.target(list, "notices", "still", bar)
                    local rects = skin.rects(clients, ws, mon)
                    local sp = skin.spark(box, rects, ctx.scr())
                    local win = su().trace ~= false and skin.window_for(item.app, clients, ws, mon, focused) or nil
                    -- D222: no window to reach — the light runs once round the screen's edge instead
                    local target = win or (su().trace ~= false and skin.frame(ctx.scr(), ctx.settings(), ctx.bar_h())) or nil
                    fact.lt_sx, fact.lt_sy = sp.x, sp.y
                    fact.lt_n = item.n or 1
                    fact.lt_win = target ~= nil and not target.frame
                    fact.lt_fon = target ~= nil and target.frame == true
                    if target and target.frame then
                        -- D310: the frame's border, lit from the top's middle down both sides; the spark sits there
                        fact.lt_fx, fact.lt_fy, fact.lt_fw, fact.lt_fh, fact.lt_fr = target.x, target.y, target.w, target.h, target.r
                        fact.lt_sx, fact.lt_sy = target.x + target.w / 2, target.y
                        fact.lt_tx, fact.lt_ty = fact.lt_sx, fact.lt_sy
                    elseif target then
                        local tp = skin.edge_point(sp, target)
                        fact.lt_tx, fact.lt_ty = tp.x, tp.y
                        fact.lt_so = skin.side(tp, target)
                        fact.lt_rx, fact.lt_ry, fact.lt_rw, fact.lt_rh = target.x, target.y, target.w, target.h
                    else
                        fact.lt_tx, fact.lt_ty = sp.x, sp.y
                    end
                    fact.lt_on, fact.lt_st, fact.lt_kt = true, 1, 1
                    if reduced() then
                        -- reduced motion: the spark and the border lit at once, no travel
                        fact.lt_tt, fact.lt_bt = 0, target and 1 or 0
                    else
                        after(LT_TRAVEL, function() if target then fact.lt_tt = 1 end end)
                        after(LT_BORDER, function() if target then fact.lt_bt = 1 end end)
                    end
                    after(LT_FADE, function() fact.lt_kt = 0 end)
                    after(LT_SPARK, function() fact.lt_st = 0 end)
                    after(LT_END, function() light_off(); next_light() end)
                end)
            end)
        end)
    end
    -- D223: a window's border lit once round, after a press on the spark took you to it
    local function highlight(addr)
        after(300, function()
            run("hyprctl", { "-j", "monitors" }, function(mo)
                local okm, mons = pcall(json.decode, mo or "")
                local mon = { x = 0, y = 0 }
                for _, m in ipairs(okm and type(mons) == "table" and mons or {}) do
                    if m.focused then mon = { x = tonumber(m.x) or 0, y = tonumber(m.y) or 0 } end
                end
                run("hyprctl", { "-j", "clients" }, function(co)
                    local okc, clients = pcall(json.decode, co or "")
                    for _, c in ipairs(okc and type(clients) == "table" and clients or {}) do
                        if c.address == addr and type(c.at) == "table" and type(c.size) == "table" then
                            fact.lt_rx, fact.lt_ry = (tonumber(c.at[1]) or 0) - mon.x, (tonumber(c.at[2]) or 0) - mon.y
                            fact.lt_rw, fact.lt_rh = tonumber(c.size[1]) or 1, tonumber(c.size[2]) or 1
                            fact.lt_so, fact.lt_win, fact.lt_fon, fact.lt_tt, fact.lt_st = 0, true, false, 0, 0
                            fact.lt_on, fact.lt_kt, fact.lt_bt = true, 1, 0
                            after(60, function() fact.lt_bt = 1 end)
                            after(1800, function() fact.lt_kt = 0 end)
                            after(2400, function() if not light_q.busy then light_off() end end)
                        end
                    end
                end)
            end)
        end)
    end
    -- the spark pressed: to the app the notice came from — its window focused (its workspace with it) and its
    -- border lit; the notices in the Nexus only when the app has no window
    on("lt_go", function()
        fact.lt_st = 0
        run("hyprctl", { "-j", "clients" }, function(out)
            local ok, clients = pcall(json.decode, out or "")
            clients = ok and type(clients) == "table" and clients or {}
            local addr = skin.find_app(last_app, clients)
            if not addr then run("mooi", { "nexus" }, function() end); return end
            run("hyprctl", { "dispatch", hypr.dispatch("focus", addr) }, function() highlight(addr) end)
        end)
    end)

    -- ── what mooi-surface's watchers bring ──
    function F.song(m)
        if type(m) ~= "table" then return end
        playing = m.playing == true
        local t = type(m.title) == "string" and m.title or ""
        if last_title ~= nil and t ~= "" and t ~= last_title and playing then push("nowplaying", m) end
        if t ~= "" then last_title = t end
        rest()
    end
    function F.notice(item)
        if type(item) ~= "table" then return end
        push("notices", item)
        local s = su()
        if s.ping == false or not may() then return end
        last_app = item.app
        local it = { app = item.app, n = 1 }
        if skin.push(light_q, it) then start_light(it) end
    end
    function F.news(count)
        news = tonumber(count) or 0
        rest()
    end
    -- the light sweep: when the hour turns (Live wallpaper's, D219), and for Try it
    local function sweep()
        if sweeping then return end
        sweeping = true
        fact.sk_swt, fact.sk_swv = 1, 1
        rest()
        after(SW_HIDE, function() fact.sk_swv = 0 end)
        after(SW_BACK, function() fact.sk_swt = 0 end)
        after(SW_END, function() sweeping = false; rest() end)
    end
    function F.clock(time)
        local turned = skin.hour(last_time, time)
        last_time = time
        if turned then sweep() end
    end
    -- Try it (the Live wallpaper page): every effect that is on, for a few seconds, music or not
    on("lw_try", function()
        try_token = try_token + 1
        local mine = try_token
        trying = true
        sweep()
        rest()
        after(SW_END + 1500, function() if try_token == mine then trying = false; rest() end end)
    end)
    -- the windows changed (a window or workspace event): whether one is fullscreen, and how much of the screen they
    -- cover (the whole picture rests under them) — asked of Hyprland at most once a second, and only while the
    -- Subsurface or Live wallpaper is on
    function F.window(_)
        if su().on ~= true and not skin.live(ctx.settings()).on then return end
        local now = os.time()
        -- (D221: one inside the wait is looked at after it — a workspace change dropped here left the whole
        -- picture resting under the windows of the workspace just left)
        if now - full_at < 1 then
            if not recheck then recheck = true; after(1100, function() recheck = false; F.window() end) end
            return
        end
        full_at = now
        run("hyprctl", { "-j", "monitors" }, function(mo)
            local okm, mons = pcall(json.decode, mo or "")
            local mon, ws = { x = 0, y = 0 }, nil
            for _, m in ipairs(okm and type(mons) == "table" and mons or {}) do
                if m.focused then
                    mon = { x = tonumber(m.x) or 0, y = tonumber(m.y) or 0 }
                    ws = type(m.activeWorkspace) == "table" and m.activeWorkspace.id or nil
                end
            end
            run("hyprctl", { "-j", "clients" }, function(co)
                local okc, clients = pcall(json.decode, co or "")
                clients = okc and type(clients) == "table" and clients or {}
                local f = skin.fullscreen(clients, ws)
                local c = skin.covered_share(skin.rects(clients, ws, mon), ctx.scr())
                if f ~= full or math.abs(c - covered) > 0.02 then full, covered = f, c; rest() end
            end)
        end)
    end
    -- the opening opened or healed: the skin steps aside while it shows the real things
    function F.opening(open)
        if open == was_open then return end
        was_open = open
        rest()
    end

    -- D223: the music's bands, read every 50 ms only while Music in the picture draws (Try it with nothing
    -- playing makes up its own); let fall to nothing once it stops
    local mb_was, tk = false, 0
    every(50, function()
        if not fact.lw_music then
            if mb_was then for i = 0, 15 do fact["mb_t" .. i] = 0 end; mb_was = false end
            return
        end
        mb_was = true
        local b
        if playing then
            local t
            local ok2, raw2 = pcall(sys.ask, "files.read", vizfeed.FILE_V2)
            if ok2 and type(raw2) == "string" then t = vizfeed.decode_v2(raw2) end
            if not t then
                local ok, raw = pcall(sys.ask, "files.read", vizfeed.FILE)
                if ok and type(raw) == "string" then t = vizfeed.decode(raw) end
            end
            if t and t.playing then
                t.bands = vizfeed.resample(t.bands, 32)
                b = mu.bands16(t.bands)
            end
        end
        if not b and trying then
            tk = tk + 1
            b = {}
            for i = 1, 16 do b[i] = math.max(0, 0.45 + 0.4 * math.sin(tk * 0.35 + i * 0.8) * math.sin(tk * 0.11 + i * 0.3)) end
        end
        b = b or {}
        for i = 1, 16 do fact["mb_t" .. (i - 1)] = b[i] or 0 end
    end)

    light_off()
    fact.pu_on, fact.pu_bt, fact.pu_wt = false, 0, 0
    rest()
    return F
end
