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
local forecast = require("lib/forecast")
local weathershare = require("lib/weathershare")
local updates = require("lib/updates")
local vizfeed = require("lib/vizfeed")
local coverart = require("lib/cover")
local sigilhosts = require("lib/sigil/hosts")   -- D207: where the Sigil may live
local chassis_look = require("lib/chassis").look

return function(ctx)
    local home = sys.ask("env", "HOME") or ""
    local folder = tostring(sys.ask("files.folder"))
    local placed = {}         -- id → true for every module the last layout placed
    local env = { screen = 1920, tray = 0, battery = false, brightness = false, bluetooth = true, playing = false }
    local readers = nil       -- starts and stops the readers; defined below, once they exist
    local geo_sent = nil      -- bar-geo.json as last written (the frame's program reads it)
    local dnd_hook = nil      -- do not disturb, looked at again when a focus block starts or ends
    -- The Pill (D168): what happens, noted for lib/pill; its own clock (a quarter-second tick, only
    -- doing anything in Pill mode), what it last showed, and where it sits
    local pillmod = require("lib/pill")
    local pillmorph = require("lib/pillmorph")   -- D204: the morph shape's form
    local hypr = require("lib/hypr")      -- Hyprland's Lua dispatch
    local pillface = require("lib/pillface")     -- D169: BMO's face, when the Pill shows it
    local pst, pill_ms, pill_now = pillmod.state(), 0, nil
    local face_st, face_said = pillface.new("happy"), ""
    -- D196: BMO as the Pill — a hop each time his face changes, a fresh typewriter for each new line,
    -- and a small reaction: one table (the counters the scene's springs follow)
    local bmo_fx = { bump = 0, say = 0, face = nil }
    local function bmo_react(face, ms)
        if fact.pill_on and fact.pill_face == 1 then
            pillface.react(face_st, face, pill_ms, ms)
            if bmo_fx.show then bmo_fx.show() end      -- face_show, set once it exists (below)
        end
    end
    local pill_room = nil          -- the width the Pill may take (relayout works it out)
    local pill_hovering = false    -- the pointer is on it (review M4)
    local cur_vol, cur_bri = nil, nil
    local pill_update        -- defined after relayout, which it calls when the Pill's size changes
    local pill_board = nil   -- D170: shell/pillboard.luau, once it is up (set_board)
    -- D207: the Sigil's side of the bar — what was last written, and whether the classic Pill steps aside
    local sig = { hosts_sent = nil, feed_sent = nil, classic_off = false, n = 0, pill = nil }
    local pill_view, pill_view_at = nil, 0   -- D171: a view the wheel turned to (nil: pill.face), and when
    -- D205: the second and third pills — each its view turned by the wheel (nil: its face), where it sits
    local extras = { [2] = { key = "two" }, [3] = { key = "three" } }
    local pill_idle_was = true               -- D175: the rest only runs while the Pill is idle
    local pill_called = -10000               -- D171: when Super last called it (twice quickly: the board)
    local pill_face_was = nil                -- D171: a new face chosen drops the view the wheel turned to
    local pill_sig = nil                     -- D181: what it showed last, for the surge on a change
    local pill_gst = nil                     -- D184: its shape without the words: a whole surge or a ripple
    local pill_swap_seq = 0                  -- D181: the newer surge settles the older one
    local pill_ws_step                       -- the wheel's next workspace (defined with the handlers)
    local pill_api               -- D170: what the board needs from the Pill (defined at the end)
    local tint_for, art_now = nil, ""   -- D172: the record's colours, from the song's cover (the media watch)

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
        -- Pill mode (D168): laid out as islands round an empty centre (the Pill sits there), the side
        -- groups left out when the Pill is alone; the saved lists are never changed
        local pillmode = b.mode == "pill"
        local sides = not (pillmode and type(s.pill) == "table" and s.pill.sides == "hide")
        local lists = pillmode and { left = sides and b.left or {}, center = {}, right = sides and b.right or {} } or b
        local out = barlayout.layout({ left = lists.left, center = lists.center, right = lists.right, show = show,
                                       frame = frame, mode = pillmode and "islands" or b.mode }, lctx)
        -- the room the Pill has (review I3): centred, so twice the distance from the middle to the nearest
        -- side group, less the moons' room on each side
        if pillmode then
            local mid, near = env.screen / 2, env.screen / 2
            for _, f in ipairs(out.frames or {}) do
                if f.w and f.w > 0 then
                    if f.x + f.w <= mid then near = math.min(near, mid - (f.x + f.w))
                    elseif f.x >= mid then near = math.min(near, f.x - mid) end
                end
            end
            pill_room = math.max(120, math.floor(2 * (near - 16) - 2 * 2 * (pillmod.MOON + pillmod.TRACE)))
        end
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
        -- the islands and the full panel too (D127): with the frame on, the frame paints every plate
        -- as part of one silhouette (the chassis) and the bar draws only what is on them
        local isl = {}
        -- each island names its module (a group's first), for its own look (D166, lib/modlook)
        for _, f in ipairs(out.frames) do isl[#isl + 1] = { x = f.x, w = f.w, id = f.id } end
        local geo = { left = cl.left and { x = cl.left.x, w = cl.left.w } or nil,
                      center = cl.center and { x = cl.center.x, w = cl.center.w } or nil,
                      right = cl.right and { x = cl.right.x, w = cl.right.w } or nil,
                      islands = isl,
                      panel = out.panel and { x = out.panel.x, w = out.panel.w } or nil,
                      saving = ctx.saving() == true,
                      screen = env.screen }   -- the frame's corners need the screen's width (lib/chassis)
        fact.pill_still = s.motion.reduced == true or s.motion.saver == "always"   -- D172: the record holds still
        -- D207: with sigil.pill = sigil the classic Pill is not drawn; its place stays (the frame's plate is the
        -- line's socket), 180 wide, no moons, and mooi-sigil draws in it
        sig.classic_off = pillmode and type(s.sigil) == "table" and s.sigil.pill == "sigil"
        fact.pill_on = pillmode and not sig.classic_off
        sig.pill = nil
        if pillmode then
            -- the Pill and its moons, for the frame's chassis and the scene's content
            local w = sig.classic_off and 180 or (pill_now and pill_now.width or 160)
            local n = (not sig.classic_off and pill_now) and #pill_now.moons or 0
            local pm = type(s.pill) == "table" and s.pill.multi or "satellites"
            local pl = pillmod.place(env.screen, w, n, pm)
            -- D187/D202: one capsule, one height — no face makes it taller
            geo.pill = { x = pl.x, w = w, slim = pill_now ~= nil and pill_now.hidden == true,
                         shape = type(s.pill) == "table" and s.pill.shape or "attached",
                         form = pill_now and pill_now.form or "capsule" }   -- D204: what the morph's outline is
            fact.pill_h = tonumber(b.height) or 24
            geo.nodes = pm == "nodes"      -- D169: square pads on traces
            fact.pill_nodes = geo.nodes
            geo.moons = {}
            for k, mx in ipairs(pl.moons) do geo.moons[k] = { x = mx, w = pillmod.MOON } end
            fact.pill_x, fact.pill_w = pl.x, w
            for k = 0, 3 do fact["moon_x" .. k] = pl.moons[k + 1] or pl.x end
            fact.moon_n = n
            -- D205: the second and third pills, placed round what is already there (lib/pill.place_extra)
            local taken = {}
            for _, f in ipairs(out.frames or {}) do taken[#taken + 1] = { x = f.x, w = f.w } end
            local lo, hi = pl.x, pl.x + w
            for _, mx in ipairs(pl.moons) do lo = math.min(lo, mx); hi = math.max(hi, mx + pillmod.MOON) end
            taken[#taken + 1] = { x = lo, w = hi - lo }
            geo.pills = {}
            local p = type(s.pill) == "table" and s.pill or {}
            for k = 2, 3 do
                local e = extras[k]
                local face = p[e.key]
                local on = type(face) == "string" and face ~= "off"
                if not on then e.view = nil end
                local shown = e.view or face
                local ex, ew = 0, 0
                if on then
                    ex, ew = pillmod.place_extra(env.screen, pillmod.face_width(shown, p.detail), p[e.key .. "_at"],
                                                 k == 2 and "left" or "right", taken)
                end
                if ew > 0 then
                    taken[#taken + 1] = { x = ex, w = ew }
                    geo.pills[#geo.pills + 1] = { x = ex, w = ew }
                end
                e.x, e.w, e.shown = ex, ew, shown
                fact["pill" .. k .. "_on"] = ew > 0
                fact["pill" .. k .. "_x"], fact["pill" .. k .. "_w"] = ex, ew
                local fi = 0
                for i, f in ipairs(pillmod.FACES) do if f == shown then fi = i - 1 end end
                fact["pill" .. k .. "_face"] = fi
            end
        end
        local enc = json.encode(geo)
        if enc ~= geo_sent then geo_sent = enc; pcall(sys.call, "files.write", "bar-geo.json", geo) end
        -- D207: the Sigil's hosts, written when they change
        if geo.pill then sig.pill = { x = geo.pill.x, w = geo.pill.w } end
        local hosts = sigilhosts.build(s, out, sig.pill, chassis_look(s), env.screen)
        sig.n = #hosts
        local henc = json.encode({ screen = env.screen, hosts = hosts })
        if henc ~= sig.hosts_sent then sig.hosts_sent = henc; pcall(sys.call, "files.write", "sigil-hosts.json", { screen = env.screen, hosts = hosts }) end
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

    -- ── The Pill (D168) ─────────────────────────────────────────
    local KIND = { idle = 0, music = 1, osd = 2, notify = 3, record = 4, battery = 5 }
    local GLYPH = { idle = 0, music = 1, vol = 2, bri = 3, notify = 4, record = 5, low = 6, charging = 7 }
    local function pill_cfg(s)
        local p = type(s.pill) == "table" and s.pill or {}
        local off = {}
        for _, id in ipairs(type(p.off) == "table" and p.off or {}) do off[id] = true end
        -- D185: do not disturb quiets the Pill too — a notice does not take it (it waits in the panel)
        if fact.dnd_now then off.notify = true end
        -- D170: never tucked away (or gone) while its own board is open — compute reads cfg.board (D202)
        return { order = p.order, off = off, moons = p.moons, multi = p.multi, face = pill_view or p.face,
                 shape = p.shape, detail = p.detail, hide = p.hide,
                 autohide = p.autohide == true, max_w = pill_room,
                 board = pill_board ~= nil and pill_board.open() == "board",
                 -- D191: ArchEclipse's rest face is as wide as its dots, the clock and its live chip
                 glance_w = bmo_fx.rest_w }        -- D199: the rest row's width (pill_rows below)
    end
    -- D199: the Pill's three rows laid out for what they say now (lib/pillrows), for the scene: the rest
    -- row is the glance face, the other two the reveal's. Published only when they change.
    local pillrows = require("lib/pillrows")
    local function pill_rows(s)
        local p = type(s.pill) == "table" and s.pill or {}
        local rows = pillrows.rows(p)
        local title = tostring(pst.media.title or "")
        local d = { spaces = ctx.space_count(), title = title, artist = title ~= "" and tostring(pst.media.artist or "") or "",
                    percent = pst.battery.percent, battery = env.battery, brightness = env.brightness }
        local out, sig = {}, {}
        for _, r in ipairs(pillrows.ROWS) do
            local lay, w = pillrows.layout(rows[r], d)
            local m = {}
            local sx = -1
            for i, it in ipairs(lay) do
                m[i] = { k = it.k, x = it.x, w = it.w, room = it.room }; sig[#sig + 1] = it.k .. ":" .. it.x .. ":" .. it.w
                if it.id == "spaces" then sx = it.x end
            end
            out[r] = { m = m, w = w, sx = sx }
            sig[#sig + 1] = "|"
        end
        bmo_fx.rest_w = out.rest.w
        local key = table.concat(sig, ",")
        if key == bmo_fx.rows_sig then return end
        bmo_fx.rows_sig = key
        model.pr_rest, model.pr_core, model.pr_detail = out.rest.m, out.core.m, out.detail.m
        fact.pr_rest_w, fact.pr_core_w, fact.pr_detail_w = out.rest.w, out.core.w, out.detail.w
        fact.pr_peek_w = math.max(out.core.w, out.detail.w)
        -- D202: the peek card is up and its rows just changed width — the card springs to the new one
        if pill_board and pill_board.rows then pill_board.rows() end
        fact.pr_rest_sx, fact.pr_core_sx, fact.pr_detail_sx = out.rest.sx, out.core.sx, out.detail.sx
    end
    function pill_update()
        local s = ctx.settings()
        if s.bar.mode ~= "pill" then fact.pill_on = false; fact.pill_swap = 0; pill_sig, pill_gst = nil, nil; return end
        pill_rows(s)
        local r = pillmod.compute(pst, pill_cfg(s), pill_ms)
        local v = r.view[r.main]
        fact.pill_kind = KIND[r.main] or 0
        fact.pill_glyph = GLYPH[v.glyph] or 0
        text.pill_t1, text.pill_t2 = v.t1 or "", v.t2 or ""
        fact.pill_val = v.value or 0
        fact.pill_split = r.split ~= nil
        if r.split then
            local sv = r.view[r.split]
            fact.pill_kind2, fact.pill_glyph2 = KIND[r.split] or 0, GLYPH[sv.glyph] or 0
            text.pill_s1, fact.pill_val2 = sv.t1 or "", sv.value or 0
            fact.pill_w1 = r.w1
        end
        for k = 0, 3 do
            local id = r.moons[k + 1]
            fact["moon_k" .. k] = id and (GLYPH[r.view[id].glyph] or 0) or -1
        end
        -- D169: the face and whether it is hidden (the chassis is told: slim = r.hidden)
        local p = type(s.pill) == "table" and s.pill or {}
        -- D174: the pointer warmth (0: blind) and whether it pings at all, handed to the scene
        fact.pill_warm = (tonumber(p.warmth) or 55) / 100
        fact.pill_ping = p.ping ~= false
        fact.pill_gl_n = math.max(1, math.min(10, math.floor(tonumber(ctx.space_count()) or 5)))     -- D191
        local fi = 0
        if p.face ~= pill_face_was then pill_face_was = p.face; pill_view = nil end
        local shown = pill_view or p.face        -- D171: the view turned to, or the default
        for i, f in ipairs(pillmod.FACES) do if f == shown then fi = i - 1 end end
        fact.pill_detail = ({ icon = 0, brief = 1, full = 2 })[p.detail] or 1
        -- D186: the board's look — the wash over the bar's plate, and the edge it wears
        fact.pk_tint = ({ theme = 0, phosphor = 1, accent = 2 })[p.board_tint] or 0
        fact.pk_edge = ({ theme = 0, hairline = 1, none = 2 })[p.board_edge] or 0
        fact.pill_shape = ({ attached = 0, floating = 1, dot = 2, morph = 3 })[p.shape] or 0
        fact.pill_face = fi     -- D170: 0 time · 1 bmo · 2 nexus · 3… a module's face (pill.FACES)
        -- D188: the saved face, which the editor marks (pill_face is the one showing: a turned view)
        local si = 0
        for i, f in ipairs(pillmod.FACES) do if f == p.face then si = i - 1 end end
        fact.pill_face_saved = si
        fact.pill_hidden = r.hidden == true
        fact.pill_vanish = r.vanish == true      -- D172: gone, 0 px wide; the scene keeps a seam
        -- D196: the mark over BMO's head: 1 low battery (a drop), 2 charging (a bolt), 3 a notice (!)
        local b = pst.battery or {}
        fact.pb_mark = (r.main == "notify" and 3) or ((b.charging and b.percent and b.percent < 100) and 2)
                       or ((b.percent and b.percent < pillmod.LOW and not b.charging) and 1) or 0
        -- D181: when what it shows changes, the scene surges once — a ring out of the capsule and a
        -- flash along its top — then settles. A first read does not: the Pill is where it already was.
        local sig = pillmod.signature(r, fi)
        local gst = pillmod.gesture(r, fi)     -- D184: the same reading, without its words
        if pill_sig and (sig ~= pill_sig or gst ~= pill_gst) then
            -- D184: the Pill itself changing surges whole; new words on the same face only ripple
            if gst ~= pill_gst then
                fact.pill_swap = 1
                if fact.dnd_now then fact.pill_swap = 0.4 end   -- D185: quiet holds
            else
                fact.pill_swap = 0.55
                if fact.dnd_now then fact.pill_swap = 0.3 end
            end
            pill_swap_seq = pill_swap_seq + 1
            local seq = pill_swap_seq
            after(240, function() if seq == pill_swap_seq then fact.pill_swap = 0 end end)
        end
        pill_sig, pill_gst = sig, gst
        -- D204: the morph's form (capsule · blob · drop · bead · none), held still under reduced motion
        r.form = pillmorph.form(r, { still = s.motion.reduced == true or s.motion.saver == "always",
                                     board = pill_board ~= nil and pill_board.open() == "board" })
        local changed = not pill_now or pill_now.width ~= r.width or #pill_now.moons ~= #r.moons
            or (pill_now.hidden == true) ~= (r.hidden == true)
            or (p.shape == "morph" and pill_now.form ~= r.form)
        pill_now = r
        if changed then relayout(true) end
    end
    -- looked at again while something timed is up or has just run out (a volume change showed on after
    -- its 2 s when the tick only ran while one was still pending), and every tick while recording
    local pill_timed = false
    -- D169: BMO's face — his expression's numbers for the scene, and his line, which widens the Pill
    local function face_show()
        local music = pst.media.playing == true and pst.media.title ~= ""
        local v = pillface.view(face_st, pill_ms, music)
        local f = pillface.numbers(v.face)
        if v.face ~= bmo_fx.face then
            bmo_fx.face = v.face
            bmo_fx.bump = bmo_fx.bump + 1
            fact.pb_bump = bmo_fx.bump
        end
        fact.pb_ew, fact.pb_eh, fact.pb_lid, fact.pb_brow, fact.pb_bron = f.ew, f.eh, f.lid, f.brow, f.bron
        fact.pb_tg = f.tg or 0
        fact.pb_sing = v.face == "singing"         -- the scene opens his mouth on the bass
        fact.pb_asleep = v.face == "asleep"
        fact.pb_sql, fact.pb_sqr, fact.pb_mc, fact.pb_mo, fact.pb_mw, fact.pb_bl = f.sql, f.sqr, f.mc, f.mo, f.mw, f.bl
        if v.say ~= face_said then
            face_said = v.say
            if v.say ~= "" then bmo_fx.say = bmo_fx.say + 1; fact.pb_say_n = bmo_fx.say end
            fact.pb_talk = v.say ~= ""
            pillmod.note(pst, "say", { text = v.say }, pill_ms)
            pill_update()
        end
    end
    bmo_fx.show = face_show
    -- D173: the Pill's half disc turns once when the workspace changes (fact.active_row, set by
    -- mooi.luau) or the wheel turns its view; held a moment, then it settles (a newer turn wins).
    local pill_turn_seq, ws_row_seen = 0, nil
    local function pill_flare()
        pill_turn_seq = pill_turn_seq + 1
        local seq = pill_turn_seq
        fact.pill_turn = 1
        after(650, function() if seq == pill_turn_seq then fact.pill_turn = 0 end end)
        bmo_react("curious", 500)      -- D196: he glances at the change
    end
    local face_beat = 0
    every(250, function()
        pill_ms = pill_ms + 250
        local row = tonumber(fact.active_row)
        if row and row ~= ws_row_seen then
            if ws_row_seen then pill_flare() end     -- the first read is where we already are
            ws_row_seen = row
        end
        -- a pointer resting on it keeps it peeked (review M4)
        if pill_hovering then pillmod.note(pst, "peek", {}, pill_ms); pill_timed = true end
        -- D171: a turned view rests back to the default after pill.rest seconds (0: it stays)
        local rest = tonumber(type(ctx.settings().pill) == "table" and ctx.settings().pill.rest or 10) or 10
        local open_board = pill_board and pill_board.open() == "board"
        -- the rest counts from when the pointer leaves and the board closes (review, re-graded)
        if pill_view and (pill_hovering or open_board) then pill_view_at = pill_ms end
        -- D175: the rest runs only while the Pill is idle — music, a notice or a recording takes the face
        -- for as long as it lasts, and when it is over you find the view you left, the rest starting again
        local pill_idle = not pill_now or pill_now.main == "idle"
        if pill_view and pill_idle and not pill_idle_was then pill_view_at = pill_ms end
        pill_idle_was = pill_idle
        if pill_view and pill_idle and not pill_hovering and not open_board
           and pillmod.view_hold(pill_view, pill_view_at, rest, pill_ms) == nil then
            pill_view = nil; pill_timed = true
        end
        if fact.pill_on and (pill_timed or pst.recording) then
            pill_update()
            pill_timed = pillmod.next_change(pst, pill_ms) ~= nil
        end
        face_beat = face_beat + 1
        if fact.pill_on and fact.pill_face == 1 and face_beat % 4 == 0 then
            local c = ctx.settings().companion
            pillface.tick(face_st, pill_ms, { hour = tonumber(os.date("%H")) or 12,
                                             talk = type(c) == "table" and c.talk or "rare" }, math.random(), math.random())
            face_show()
        end
    end)
    local function note(kind, payload)
        pillmod.note(pst, kind, payload, pill_ms); pill_timed = true; pill_update()
        if kind == "osd" then bmo_react("focused", 700) end      -- D196: he concentrates on the turn
    end
    -- what it hears: the volume and the brightness changing, notifications arriving (by their id)
    local last_vol, last_bri = nil, nil
    pcall(sys.watch, "audio", function(a)
        if type(a) ~= "table" then return end
        local v = tonumber(a.volume)
        if v then cur_vol = v > 1 and v / 100 or v end
        if v and last_vol and math.abs(v - last_vol) > 0.001 then note("osd", { kind = "vol", value = v > 1 and v / 100 or v }) end
        last_vol = v
    end)
    -- notifications as Signal Loom takes them in (review I2: the history is empty while mooi keeps them,
    -- and another program's is not mooi's to read); a whisper (muted, quiet time, low) never shows
    if ctx.on_signal then
        ctx.on_signal(function(n)
            note("notify", { app = (n.app or "") ~= "" and n.app or "notice", summary = n.title or n.summary or "" })
            -- D171: the Alerts face's newest, at full detail
            text.pill_alert = ((n.app or "") ~= "" and (n.app .. " · ") or "") .. tostring(n.title or n.summary or "")
            fact.pill_alert_on = true
            if not fact.dnd_now then pill_flare() end      -- D188: the edge flash says a notice came
            -- D170: BMO is surprised, then pleased: a letter
            if fact.pill_on and fact.pill_face == 1 and pill_api then
                pill_api.react("surprised", 700)
                after(650, function() pill_api.react("excited", 1000); pill_api.say("a letter!") end)
            end
        end)
    end
    -- what a press does: the thing it shows, opened; a scroll: volume or workspaces; a moon: brought in
    on("pill_press", function()
        local main = pill_now and pill_now.main or "idle"
        -- D170 fix: a hidden Pill pressed comes back AND does what it shows, in one press (pointing at
        -- it already brought it back; a press that only revealed it read as "nothing happens")
        if fact.pill_hidden then note("peek", {}) end
        fact.isl_cx = (fact.pill_x or 0) + (fact.pill_w or 0) / 2
        -- D170: the board decides (lib/pill.press): it unfolds, or the Nexus face opens the Nexus
        if pill_board then pill_board.press("left", main) end
    end)
    -- D170: the right press keeps the old jumps (the calendar, the player, the activity's island)
    on("pill_rpress", function()
        local main = pill_now and pill_now.main or "idle"
        if fact.pill_hidden then note("peek", {}) end
        fact.isl_cx = (fact.pill_x or 0) + (fact.pill_w or 0) / 2
        if pill_board then pill_board.press("right", main) end
    end)
    -- D205: the second and third pills — a press opens what its face shows (the board on its room, from
    -- under it), the wheel turns its own view through the owner's views
    on("pill_xpress", function(v)
        local e = extras[math.floor(tonumber(v) or 0)]
        if not e or not e.shown or (e.w or 0) <= 0 or not pill_board then return end
        fact.isl_cx = (e.x or 0) + (e.w or 0) / 2
        pill_board.face_press(e.shown)
    end)
    on("pill_xscroll", function(v)
        v = math.floor(tonumber(v) or 0)
        local e = extras[v // 2]
        if not e or not e.shown then return end
        local p = type(ctx.settings().pill) == "table" and ctx.settings().pill or {}
        e.view = pillmod.next_view(p.views, e.shown, v % 2 == 1 and -1 or 1)
        if e.view == p[e.key] then e.view = nil end
        relayout(true)
    end)
    -- D170: a moon's right press opens the board on its activity
    on("pill_rmoon", function(v)
        local id = pill_now and pill_now.moons[(math.floor(tonumber(v) or -1)) + 1]
        if id and pill_board then pill_board.press("left", id) end
    end)
    -- the next workspace along the ones the bar shows (lib/pill.ws_step), from the one Hyprland is on
    pill_ws_step = function(d)
        run("hyprctl", { "-j", "activeworkspace" }, function(out)
            local ok, w = pcall(json.decode, out or "")
            local id = ok and type(w) == "table" and tonumber(w.id) or 1
            local n = pillmod.ws_step(id, d, ctx.space_count and ctx.space_count() or 4)
            run("hyprctl", { "dispatch", hypr.go_workspace(n) })
        end)
    end
    -- D171: Super + wheel (`mooi wheel`): over a pill, its next view; elsewhere, the workspace
    on("pill_superwheel", function(v)
        local d = (tonumber(v) or 1) < 0 and -1 or 1
        if pill_hovering and fact.pill_on then
            local p = type(ctx.settings().pill) == "table" and ctx.settings().pill or {}
            pill_view = pillmod.next_view(p.views, pill_view or p.face or "time", d)
            pill_view_at = pill_ms
            note("peek", {})
            pill_flare()
        else
            pill_ws_step(d)
        end
    end)
    -- D171: Super (`mooi pill`): the Pill comes back (the dot opens); called again within a moment, the board
    on("pill_call", function()
        if not fact.pill_on then return end
        if pill_ms - pill_called < 1500 and pill_board then
            pill_called = -10000
            fact.isl_cx = (fact.pill_x or 0) + (fact.pill_w or 0) / 2
            pill_board.call(pill_now and pill_now.main or "idle")
        else
            pill_called = pill_ms
            note("peek", {})
        end
    end)
    -- D169: pointed at, a hidden Pill comes back for a while
    on("pill_hover", function(v)
        pill_hovering = tonumber(v) == 1
        -- D198: the peek follows where the mouse really is (pill_over, from cursor.x/y), not this zone's
        -- hover — the card opening over the capsule took the hover away, folded the card, and opened it
        -- again under a resting pointer, over and over
        -- D170: BMO notices the pointer (and wakes up)
        if pill_hovering and fact.pill_on and fact.pill_face == 1 then pill_api.touch(); pill_api.react("curious", 900) end
        -- on, or on leaving: 4 s more from now
        note("peek", {})
    end)
    -- D198: the mouse over the capsule, or over the peek's card while it shows (the scene measures it from
    -- the global cursor, so a card opening under a resting pointer does not count as leaving)
    on("pill_over", function(v)
        if pill_board and pill_board.hover then pill_board.hover(tonumber(v) == 1) end
    end)
    on("pill_scroll", function(v)
        local d = tonumber(v) or 0
        local main = pill_now and pill_now.main or "idle"
        if main == "idle" then
            -- D171: the wheel turns the idle Pill through the owner's views (pill.views)
            local p = type(ctx.settings().pill) == "table" and ctx.settings().pill or {}
            pill_view = pillmod.next_view(p.views, pill_view or p.face or "time", d > 0 and -1 or 1)
            pill_view_at = pill_ms
            note("peek", {})
            pill_flare()
        else
            -- review C1: audio.volume and brightness.level are absolute (0–1), so step from the current
            -- level; a brightness change steps brightness, music and volume step the volume, the rest
            -- nothing
            local step = (d > 0) and 0.05 or -0.05
            if main == "osd" and pst.osd and pst.osd.kind == "bri" then
                if cur_bri then pcall(sys.call, "brightness.level", math.max(0.01, math.min(1, cur_bri + step))) end
            elseif main == "music" or main == "osd" then
                if cur_vol then pcall(sys.call, "audio.volume", math.max(0, math.min(1, cur_vol + step))) end
            end
        end
    end)
    on("pill_moon", function(v)
        local id = pill_now and pill_now.moons[(math.floor(tonumber(v) or -1)) + 1]
        if id then note("pin", { id = id }) end
    end)

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
        if type(v) == "table" and v.present then note("battery", { percent = v.percent, charging = v.charging }) end
        local p = type(v) == "table" and v.present == true
        if p ~= env.battery then env.battery = p; relayout() end
    end)
    sys.watch("brightness", function(v)
        local lv = type(v) == "table" and tonumber(v.level) or nil
        if lv then cur_bri = lv > 1 and lv / 100 or lv end
        if lv and last_bri and math.abs(lv - last_bri) > 0.001 then note("osd", { kind = "bri", value = lv > 1 and lv / 100 or lv }) end
        last_bri = lv
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
            if v then fact.res_cpu = v; sig.res_ok = true end
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

    local read_weather
    function read_weather()
        -- One location memo and one forecast cache for every panel (audit 2026-11-06, G7): the bar
        -- reads the notch's/Nexus's answer instead of asking ipinfo and open-meteo on its own.
        local function fetch(url, done)
            run("curl", { "-fsSL", "--max-time", "15", url }, function(out, code)
                local ok, t = pcall(json.decode, out or "")
                done(code == 0 and ok and type(t) == "table" and t or nil)
            end)
        end
        local function get(name) local ok, v = pcall(sys.ask, "files.read", name); return ok and v or nil end
        weathershare.refresh({ read = get, fetch = fetch,
                               write = function(name, doc) pcall(sys.call, "files.write", name, doc) end }, function(doc)
            local f = doc and forecast.parse(doc.answer) or nil
            if not f then
                -- A failed fetch (open-meteo answers 503 now and then) keeps the last good
                -- reading on the bar, and tries again in a minute rather than in ten.
                log("bar · weather: no answer; trying again in 60 s")
                after(60000, function() if placed.weather then read_weather() end end)
                return
            end
            local kind, word = sysinfo.weather(f.now.code, f.now.day)
            for i, k in ipairs(sysinfo.WEATHER_KINDS) do if k == kind then fact.wx_kind = i - 1 end end
            fact.wx_temp = tonumber(f.now.temp) or 0
            text.wx_word = word
            text.wx_city = string.upper(tostring(doc.city or ""))
            fact.wx_ok = true
        end)
    end

    -- ── The visualizer: cava, while something plays ───────────
    local cava, playing = nil, false
    -- A cava that never printed a band is not installed (or cannot read PipeWire): say so once
    -- instead of respawning it on every relayout (audit 2026-10-29).
    local cava_lines, viz_missing = 0, false
    local CAVA = "cava.conf"
    sys.call("files.write", CAVA, table.concat({
        "[general]", "bars = 64", "framerate = 30",
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
    local gain_peak = 0                  -- the automatic gain's ceiling (lib/vizfeed gain)
    local seq, last_ms, prev = 0, 0, nil -- the published feed and its cadence
    local silent_written = nil           -- the missing flag last written at rest
    local function publish(cand, now_ms)
        if prev and not vizfeed.should_publish(prev, cand, now_ms, last_ms, 500) then return end
        seq = seq + 1
        cand.seq = seq
        prev, last_ms, silent_written = cand, now_ms, nil
        sys.call("files.write", vizfeed.FILE, vizfeed.encode(cand))
        -- the 64 bands beside it, only while the desktop widgets ask (feed_want)
        if cand.wide and feed_wanted > os.time() then
            sys.call("files.write", vizfeed.FILE_V2, vizfeed.encode_v2({ bands = cand.wide, bass = cand.bass, high = cand.high,
                beat = cand.beat, phase = cand.phase, playing = true, missing = cand.missing, seq = seq }))
        end
    end
    local function rest_feed(missing)
        missing = missing == true
        if seq > 0 and prev == nil and silent_written == missing then return end
        seq = seq + 1
        local t = vizfeed.silent(seq)
        t.missing = missing
        prev, last_ms, silent_written = nil, 0, missing
        sys.call("files.write", vizfeed.FILE, vizfeed.encode(t))
        -- and at rest in v2 too, so a widget never reads an old playing frame as new (D138 review)
        sys.call("files.write", vizfeed.FILE_V2, vizfeed.encode_v2(t))
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
                if i > 63 then break end
                b[i] = math.min(1, (tonumber(v) or 0) / 1000)
                i = i + 1
            end
            if i < 64 then return end
            local wide = {}
            for j = 1, 64 do wide[j] = b[j - 1] or 0 end
            -- read against what this music reaches, not against cava's full range (lib/vizfeed gain)
            wide, gain_peak = vizfeed.gain(gain_peak, wide)
            -- cava runs 64 bands for the desktop widgets (v2, D138); everyone else keeps 32 (v1)
            local bands = vizfeed.resample(wide, 32)
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
                          phase = state.phase, playing = true, missing = viz_missing, wide = wide }, frame * 1000 / 30)
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
        if type(url) ~= "string" or url == "" then art_now = ""; text.med_art = ""; fact.med_has_art = false; tint_for(""); return end
        local path = coverart.path(url)
        if path and path ~= art_now then bmo_fx.cov = (bmo_fx.cov or 0) + 1; fact.pk_cov_n = bmo_fx.cov end   -- D201: the dissolve
        if path then art_now = path; text.med_art = path; fact.med_has_art = true; tint_for(path); return end
        if coverart.remote(url) then
            -- two names in turn, so the image is a new file each time and not a cached one
            covers = covers + 1
            local dest = folder .. "/cover-" .. tostring(covers % 2) .. ".img"
            run("curl", { "-fsSL", "--max-time", "8", "-o", dest, url }, function(_, code)
                if code == 0 and art_url == url then
                    if dest ~= art_now then bmo_fx.cov = (bmo_fx.cov or 0) + 1; fact.pk_cov_n = bmo_fx.cov end
                    art_now = dest; text.med_art = dest; fact.med_has_art = true; tint_for(dest)
                end
            end)
        end
    end
    -- D172: the record's colours — the song's own cover through Matugen (a dry run, mooi's own scheme,
    -- as the player reads it), once per cover; until then the palette's phosphor, ember and trace.
    local tints, tint_busy = {}, false
    local function paint_tint(cols)
        local r1, g1, b1 = pillmod.hex_rgb(cols and cols[1])
        local r2, g2, b2 = pillmod.hex_rgb(cols and cols[2])
        local r3, g3, b3 = pillmod.hex_rgb(cols and cols[3])
        fact.pc1_r, fact.pc1_g, fact.pc1_b = r1 or 0.65, g1 or 0.95, b1 or 0.82
        fact.pc2_r, fact.pc2_g, fact.pc2_b = r2 or 1.00, g2 or 0.57, b2 or 0.37
        fact.pc3_r, fact.pc3_g, fact.pc3_b = r3 or 0.10, g3 or 0.14, b3 or 0.15
    end
    paint_tint(nil)
    tint_for = function(cover_path)
        local s = ctx.settings()
        -- D201: in Pill mode always (the music view's light is the cover's colours; the record shape that
        -- needed them first is gone, D188)
        local pill = s.bar.mode == "pill"
        if not pill or type(cover_path) ~= "string" or cover_path == "" then paint_tint(nil); return end
        local have = tints[cover_path]
        if have ~= nil then paint_tint(have or nil); return end
        if tint_busy then return end
        tint_busy = true
        run("matugen", { "image", cover_path, "-m", "dark", "--dry-run", "-j", "hex", "--source-color-index", "0" }, function(out, code)
            tint_busy = false
            local cols = nil
            if code == 0 then
                local ok, t = pcall(json.decode, out or "")
                if ok and type(t) == "table" and type(t.colors) == "table" then
                    local function role(name)
                        local v = t.colors[name]
                        local side = type(v) == "table" and v.dark or nil
                        return type(side) == "table" and side.color or nil
                    end
                    cols = { role("primary"), role("tertiary"), role("primary_container") }
                end
            end
            tints[cover_path] = cols or false
            if art_now == cover_path then paint_tint(cols) end
        end)
    end
    -- ── the music island (D142): the song as the media service has it, its clock while the island is
    -- open, shuffle and repeat from playerctl ──
    local mu = { pos = 0, len = 0, rate = 1, at = 0, open = false }
    local function mmss(t)
        t = math.max(0, math.floor((tonumber(t) or 0) + 0.5))
        if t >= 3600 then return string.format("%d:%02d:%02d", t // 3600, (t // 60) % 60, t % 60) end
        return string.format("%d:%02d", t // 60, t % 60)
    end
    local function mu_show()
        fact.med_pos, fact.med_len = mu.pos, mu.len
        text.med_tpos, text.med_tlen = mu.len > 0 and mmss(mu.pos) or "", mu.len > 0 and mmss(mu.len) or ""
    end
    local function mu_modes()
        run("playerctl", { "shuffle" }, function(out, code) if code == 0 then fact.med_shuf = tostring(out):match("On") ~= nil end end)
        run("playerctl", { "loop" }, function(out, code)
            if code == 0 then fact.med_loop = tostring(out):match("Track") and 2 or (tostring(out):match("Playlist") and 1 or 0) end
        end)
    end
    -- D207: what only the bar reads, for mooi-sigil (sigil-feed.json): once a second while it has a host,
    -- written only when it changed. `at` is the wall clock in ms, so the Sigil can tell a dead feed.
    every(1000, function()
        if sig.n == 0 then return end
        local function hex(r, g, b) return string.format("#%02x%02x%02x", math.floor((r or 0) * 255 + .5), math.floor((g or 0) * 255 + .5), math.floor((b or 0) * 255 + .5)) end
        local doc = {
            -- nothing before it was read: the Sigil shows a dash, not "0°" (review I2)
            resources = sig.res_ok and { cpu = fact.res_cpu, mem = fact.res_mem, temp = fact.res_temp } or nil,
            weather = fact.wx_ok and { temp = fact.wx_temp, word = text.wx_word, city = text.wx_city } or nil,
            music = { title = text.mu_title, artist = text.mu_artist, playing = fact.mu_playing == true },
            cover = fact.mu_has and { hex(fact.pc1_r, fact.pc1_g, fact.pc1_b), hex(fact.pc2_r, fact.pc2_g, fact.pc2_b), hex(fact.pc3_r, fact.pc3_g, fact.pc3_b) } or nil,
        }
        local enc = json.encode(doc)
        if enc == sig.feed_sent then
            -- unchanged: rewrite at most every 10 s so the Sigil still sees it alive
            if os.time() - (sig.feed_t or 0) < 10 then return end
        end
        sig.feed_sent, sig.feed_t = enc, os.time()
        doc.at = os.time() * 1000
        pcall(sys.call, "files.write", "sigil-feed.json", doc)
    end)
    every(500, function()
        if not mu.open or not playing or mu.len <= 0 then return end
        mu.pos = math.min(mu.len, mu.pos + 0.5 * mu.rate)
        mu_show()
    end)
    -- the music island says 1 or 0, the Pill's board 3 or 2 (D170, review I5): either keeps the song's
    -- position coming, and one closing in the frame the other opens never stops it
    on("music_isl", function(v)
        local n = math.floor(tonumber(v) or 0)
        if n >= 2 then mu.board = n == 3 else mu.isl = n == 1 end
        mu.open = mu.isl or mu.board
        if mu.open then mu_modes() end
        if readers then readers() end
    end)
    on("med_seek", function(v)
        if mu.len <= 0 then return end
        mu.pos = (math.floor(tonumber(v) or 0) / 999) * mu.len
        run("playerctl", { "position", string.format("%.1f", mu.pos) })
        mu_show()
    end)
    on("med_mode", function(v)
        v = math.floor(tonumber(v) or 0)
        if v == 0 then run("playerctl", { "shuffle", "toggle" }, function() mu_modes() end)
        elseif v == 4 then run("playerctl", { "loop", ({ [0] = "Playlist", "Track", "None" })[math.floor(fact.med_loop or 0)] or "None" }, function() mu_modes() end)
        else pcall(sys.call, ({ [1] = "media.previous", [2] = "media.toggle", [3] = "media.next" })[v]) end
    end)
    sys.watch("media", function(m)
        if type(m) == "table" then note("media", { playing = m.playing, title = m.title, artist = m.artist }) end
        local now = type(m) == "table" and m.playing == true
        if type(m) == "table" then
            cover(m.art)
            local title = type(m.title) == "string" and m.title or ""
            text.mu_title, text.mu_artist = title, tostring(m.artist or "")
            fact.pill_gl_art = tostring(m.artist or "") ~= ""      -- D191
            fact.pill_gl_tw = math.min(150, 7 * #title)            -- D191: the title's room, as lib/pillrows measures it
            text.med_album = string.upper(tostring(m.album or ""))
            text.med_player = string.upper((tostring(m.player or ""):gsub("^org%.mpris%.MediaPlayer2%.", ""):gsub("%..*$", "")))
            fact.mu_has, fact.mu_playing = title ~= "", now
            mu.pos, mu.len, mu.rate = tonumber(m.position) or 0, tonumber(m.length) or 0, tonumber(m.rate) or 1
            mu_show()
            if mu.open then mu_modes() end
        end
        local changed = now ~= playing
        if changed and now then bmo_react("excited", 900) end    -- D196: a song starts
        playing = now
        if changed then env.playing = now; relayout() elseif readers then readers() end
    end)

    -- Start what the placed modules need, stop the rest.
    readers = function()
        local s = ctx.settings()
        -- D170 (review I2): in Pill mode the pads, the face and Now read too, modules on the bar or not
        local pill_on_bar = s.bar.mode == "pill"
        local need = pill_on_bar and pillmod.needs(s.pill) or {}
        -- D207: the Sigil may show them whenever it has a host (review I2: unfetched, they read 0)
        if placed.resources or need.resources or sig.n > 0 then every_while("res", 2000, read_resources) else stop("res") end
        if placed.bandwidth or need.bandwidth then every_while("bw", 2000, read_bandwidth) else stop("bw") end
        if placed.keyboard or need.keyboard then every_while("kb", 3000, read_keyboard) else stop("kb") end
        if placed.weather or need.weather or sig.n > 0 then every_while("wx", 600000, read_weather) else stop("wx") end
        local still = s.motion.reduced == true or s.motion.saver == "always"
        want_swell = s.frame.on and s.frame.music and not still
        -- The frame's music follows whatever is audible, not only what the media module knows
        -- about: with frame.music on, cava runs whether or not that module says anything is
        -- playing, so a browser, a game or a video moves the frame too. For the player it runs
        -- only while something plays. Neither runs while the saver is on.
        want_viz = (placed.media and s.bar.visualizer ~= "off" and s.media.mode ~= "art") or mu.open   -- the music island's ring
            or (s.bar.mode == "pill" and env.playing)   -- the Pill's music bars (review I1)
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
                        if rec == mine then rec = nil; fact.recording = false; note("recording", { on = false }); log("bar · recording saved in ~/Videos") end
                    end)
                    rec = mine
                    fact.recording = true
                    note("recording", { on = true })
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

    -- Power: the session menu (wlogout, as ArchEclipse), or lock now. mooi's own lock screen since
    -- D160 (ext-session-lock, `mooi lock`): it starts the scene and takes the session, and hyprlock is
    -- what `lock-session.sh` falls back to when the scene cannot come up.
    on("power", function(v)
        if (tonumber(v) or 0) > 0.5 then run("mooi", { "lock" }) else run("wlogout", { "-b", "5", "-p", "layer-shell" }) end
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
        focus = "Focus", settings = "Settings", notes = "Quick notes", wallpaper = "Wallpaper", updates = "Updates",
        nexus = "Nexus", claude = "Claude", github = "GitHub", sigil = "Sigil" }
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
        -- D166: "Look…" — Settings at this module's own look (started if it is not open)
        if op == 6 then
            local k = math.floor(n / 10)
            if not fact.settings_open then run("pleamar", { "--say", "mooi", "emit open_settings" }) end
            -- a window just started may not hear the first one: said again a moment later (it is idempotent)
            for _, ms in ipairs(fact.settings_open and { 50 } or { 1500, 3000 }) do
                after(ms, function() run("pleamar", { "--say", "mooi-settings", "emit open_module " .. tostring(k) }) end)
            end
            return
        end
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
    -- a settings change arrives as relayout(): the Pill reads its face, hiding and order again first
    -- D170: what the board needs from the Pill: what it shows, the change showing, and BMO
    local function talk()
        local c = ctx.settings().companion
        return type(c) == "table" and c.talk or "rare"
    end
    pill_api = {
        now = function() return pill_now end,
        -- D171: the face showing (the view the wheel turned to, or pill.face)
        face = function()
            local p = type(ctx.settings().pill) == "table" and ctx.settings().pill or {}
            return pill_view or p.face or "time"
        end,
        osd = function() return pst.osd and pst.osd.kind or "vol" end,
        bmo = function() return fact.pill_on == true and fact.pill_face == 1 end,
        react = function(face, ms) pillface.react(face_st, face, pill_ms, ms); face_show() end,
        say = function(line) pillface.say(face_st, line, pill_ms, talk()); face_show() end,
        poke = function() pillface.poke(face_st, pill_ms, math.random(), talk()); face_show() end,
        touch = function()
            if pillface.touch(face_st, pill_ms) then
                pillface.react(face_st, "surprised", pill_ms, 900); pillface.say(face_st, "oh! hi", pill_ms, talk())
            end
            face_show()
        end,
    }
    return { relayout = function() pill_update(); relayout() end, measure = measure,
             pill = pill_api, set_board = function(b) pill_board = b end }
end
