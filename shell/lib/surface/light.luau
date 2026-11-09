-- Push up from below (the Subsurface spec §9, §9a; D217), run: a logic module of mooi-surface (whose main chunk
-- holds the Sigil and the opening), `require("lib/surface/light")(ctx)`. It watches nothing itself — mooi-surface's
-- watchers call it (one watcher per service): song(music), notice(item), news(count), clock(time), window(w),
-- refresh() for the settings and the widgets, opening(open). The decisions are lib/surface/skin's; this writes the
-- scene's facts: the rest (sk_*: the glow, the moving wallpaper, the hour's sweep), the push (pu_*: the bulge and
-- the words) and the light (lt_*: the spark, its line to the app's window, the border).
-- ctx: settings() → settings, widgets() → widgets.json's list, bar_h() → the bar's strip, open() → the opening
-- shows, scr() → { w, h }.

local skin = require("lib/surface/skin")

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
    local last_time, full_at = nil, -1e9

    local function su() local s = ctx.settings(); return type(s.surface) == "table" and s.surface or {} end
    local function reduced() local s = ctx.settings(); return type(s.motion) == "table" and s.motion.reduced == true end
    local function contrast() local s = ctx.settings(); return type(s.theme) == "table" and tonumber(s.theme.contrast) == 1 end
    -- may anything reach up now: Surface on, the opening shut, no window fullscreen
    local function may() return su().on == true and not ctx.open() and not full end
    local function centre(b) if b then return b.x + b.w / 2, b.y + b.h / 2 end; return -9999, -9999 end

    -- ── the rest: the glow, the moving wallpaper, the hour's sweep ──
    local function rest()
        local s, ws, bar = su(), ctx.widgets(), ctx.bar_h()
        local glow = s.glow == "off" and 0 or (s.glow == "bright" and 2 or 1)
        local np = skin.target(ws, "nowplaying", "woven", bar)
        local nc = skin.target(ws, "notices", "woven", bar)
        local vz = skin.target(ws, "visualiser", "moves", bar)
        local ck = skin.target(ws, "clock", "moves", bar)
        fact.sk_g = glow
        fact.sk_mx, fact.sk_my = centre(np)
        fact.sk_mp = np ~= nil and playing and glow > 0
        fact.sk_nx, fact.sk_ny = centre(nc)
        fact.sk_nn = nc ~= nil and news > 0 and glow > 0
        local v = vz or { x = -9999, y = -9999, w = 1, h = 1 }
        fact.sk_vx, fact.sk_vy, fact.sk_vw, fact.sk_vh = v.x, v.y, v.w, v.h
        fact.sk_vm = vz ~= nil and playing
        local c = ck or { x = -9999, y = -9999, w = 1, h = 1 }
        fact.sk_cx, fact.sk_cy, fact.sk_cw, fact.sk_ch = c.x, c.y, c.w, c.h
        fact.sk_on = may() and (fact.sk_mp or fact.sk_nn or fact.sk_vm or (sweeping and ck ~= nil))
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
                    fact.lt_sx, fact.lt_sy = sp.x, sp.y
                    fact.lt_n = item.n or 1
                    fact.lt_win = win ~= nil
                    if win then
                        local tp = skin.edge_point(sp, win)
                        fact.lt_tx, fact.lt_ty = tp.x, tp.y
                        fact.lt_so = skin.side(tp, win)
                        fact.lt_rx, fact.lt_ry, fact.lt_rw, fact.lt_rh = win.x, win.y, win.w, win.h
                    else
                        fact.lt_tx, fact.lt_ty = sp.x, sp.y
                    end
                    fact.lt_on, fact.lt_st, fact.lt_kt = true, 1, 1
                    if reduced() then
                        -- reduced motion: the spark and the border lit at once, no travel
                        fact.lt_tt, fact.lt_bt = 0, win and 1 or 0
                    else
                        after(LT_TRAVEL, function() if win then fact.lt_tt = 1 end end)
                        after(LT_BORDER, function() if win then fact.lt_bt = 1 end end)
                    end
                    after(LT_FADE, function() fact.lt_kt = 0 end)
                    after(LT_SPARK, function() fact.lt_st = 0 end)
                    after(LT_END, function() light_off(); next_light() end)
                end)
            end)
        end)
    end
    -- the spark pressed: the notices, in the Nexus
    on("lt_go", function() run("mooi", { "nexus" }, function() end) end)

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
        local it = { app = item.app, n = 1 }
        if skin.push(light_q, it) then start_light(it) end
    end
    function F.news(count)
        news = tonumber(count) or 0
        rest()
    end
    function F.clock(time)
        local turned = skin.hour(last_time, time)
        last_time = time
        if not turned or sweeping or not may() then return end
        if not skin.target(ctx.widgets(), "clock", "moves", ctx.bar_h()) then return end
        sweeping = true
        fact.sk_swt, fact.sk_swv = 1, 1
        rest()
        after(SW_HIDE, function() fact.sk_swv = 0 end)
        after(SW_BACK, function() fact.sk_swt = 0 end)
        after(SW_END, function() sweeping = false; rest() end)
    end
    -- a window made fullscreen (or not): asked of Hyprland at most once a second, only while the Surface is on
    function F.window(_)
        if su().on ~= true then return end
        local now = os.time()
        if now - full_at < 1 then return end
        full_at = now
        run("hyprctl", { "-j", "activewindow" }, function(out)
            local ok, aw = pcall(json.decode, out or "")
            local f = ok and type(aw) == "table" and (tonumber(aw.fullscreen) or 0) > 0 or false
            if f ~= full then full = f; rest() end
        end)
    end
    -- the opening opened or healed: the skin steps aside while it shows the real things
    function F.opening(open)
        if open == was_open then return end
        was_open = open
        rest()
    end

    light_off()
    fact.pu_on, fact.pu_bt, fact.pu_wt = false, 0, 0
    rest()
    return F
end
