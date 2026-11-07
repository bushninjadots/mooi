-- The Pill board (D170): a press on the Pill unfolds it into a board — a core of rooms over the owner's
-- pads (pill.pads), each wired to the core. lib/pill decides what a press does and which pads are valid,
-- lib/pillpads what each pad is; this carries it out: opens and closes the board (fact open = board),
-- picks the room (pk_room), publishes the pads (pk_n, pk_k0…7), runs a pad's act (the same event its
-- module's press sends), edits the pads and the face, and has BMO react. ui/pillboard.plm draws it; the
-- rooms read what the islands gather (shell/islands.luau gathers for the board's room too).

local pillmod = require("lib/pill")
local parts = require("lib/pillpads")
local calendar = require("lib/calendar")
local deskgrid = require("lib/deskgrid")
local deskprev = require("lib/deskprev")
local pillfind = require("lib/pillfind")
local hypr = require("lib/hypr")

-- what BMO says when a pad is pointed at
local WORDS = { volume = "sound!", brightness = "so bright", network = "wi-fi", bluetooth = "bluetooth",
    notifications = "letters!", clock = "calendar", battery = "power", nexus = "the nexus!", weather = "weather!",
    resources = "beep boop", media = "music!", caffeine = "coffee!", mic = "shh", recorder = "recording",
    screenshot = "cheese!", workspaces = "spaces", focus = "focus", updates = "updates", claude = "claude",
    github = "code", notes = "notes", wallpaper = "pretty", clipboard = "copy", power = "bye?", core = "find it",
    overview = "everything", settings = "settings", window = "window", actions = "window", keyboard = "typing",
    bandwidth = "zoom", tray = "tray" }

return function(ctx)
    local P = ctx.pill
    local pads = {}
    local finds_publish        -- D178: the search's rows (assigned with the handlers, called as a room opens)
    local nets_publish         -- D171: the networks the radio can see (same: forward-declared, or the room
                               -- that opens Connections calls a nil — it did, and the board never opened)
    -- what is open, as the scene says: a press outside or Escape closes it in the scene, and reading
    -- fact.open back gives the logic's last write, not that (a closed board read as open, D170)
    local opened = "none"
    -- D189: the editor and the peek are reset only after a close has folded the body (~the closing spring)
    local fold = { seq = 0 }
    function fold.later()
        fold.seq = fold.seq + 1
        local mine = fold.seq
        after(pillmod.FOLD_MS, function()
            if mine ~= fold.seq or opened == "board" then return end
            fact.pk_edit, fact.pk_peek = false, false
        end)
    end
    local function set_open(v)
        opened = v
        if v ~= "board" then fact.pk_sw, fact.pk_sh = 0, 0; fold.later() end      -- closing: back into the capsule (D188)
        -- told to the others who follow open (the frame's plate, the rooms' readers): the scene's
        -- fact:open is not heard for a change the logic makes
        if ctx.opened then ctx.opened(v) else fact.open = v end
    end

    local function emit_scene(ev, arg)
        run("pleamar", { "--say", "mooi", "emit " .. ev .. (arg ~= nil and (" " .. tostring(arg)) or "") })
    end
    local function pill_settings()
        local s = ctx.settings()
        if type(s.pill) ~= "table" then s.pill = {} end
        return s.pill
    end
    local function save()
        ctx.save()
        if ctx.relayout then ctx.relayout() end
    end

    -- the pads as the scene draws them, and which one's room is showing
    local function publish()
        pads = pillmod.pads(pill_settings().pads)
        fact.pk_n = #pads
        for i = 0, 7 do fact["pk_k" .. i] = pads[i + 1] and parts.index(pads[i + 1]) or -1 end
        local on = -1
        local r = fact.pk_room or 0
        if r > 0 then
            for i, id in ipairs(pads) do
                local p = parts.get(id)
                if p.room and parts.room_index(p.room) == r then on = i - 1; break end
            end
        end
        fact.pk_on = on
        -- D175: the desk — the tiles the owner switched on, placed by lib/deskgrid, and its own look
        local s = pill_settings()
        -- D188: a tile is on unless its size says Off (the old switch is migrated into it, lib/config)
        local function tile_on(id) return s["desk_" .. id] ~= false and s["desk_" .. id .. "_size"] ~= "off" end
        local on_tiles = { clock = tile_on("clock"), playing = tile_on("playing"),
                           diagnostics = tile_on("diagnostics"), calendar = tile_on("calendar") }
        -- D177: a tile's size is its own choice, and a wide one takes the row
        local sizes = {}
        for _, id in ipairs(deskgrid.ON) do sizes[id] = s["desk_" .. id .. "_size"] end
        local tiles = deskgrid.place(deskgrid.chosen(on_tiles), sizes)
        fact.pk_dk_n = #tiles
        for i = 0, 3 do
            local t = tiles[i + 1]
            fact["pk_dk_t" .. i] = t and t.k or -1
            fact["pk_dk_x" .. i] = t and t.x or 0
            fact["pk_dk_y" .. i] = t and t.y or 0
            fact["pk_dk_w" .. i] = t and t.w or 0
            fact["pk_dk_h" .. i] = t and t.h or 0
        end
        fact.pk_dk_surface = ({ plate = 0, glass = 1, tether = 2 })[s.desk_surface] or 0
        fact.pk_dk_border = ({ hairline = 0, cut = 1, none = 2 })[s.desk_border] or 0
        -- D177: the desk's look — the tiles, or the owner's opened vial; its tint and its glow
        fact.pk_dk_form = s.desk_form == "vial" and 1 or 0
        fact.pk_dk_tint = ({ wallpaper = 0, accent = 1, mono = 2 })[s.desk_tint] or 0
        fact.pk_dk_glow = ({ none = 0, soft = 1, bright = 2 })[s.desk_glow] or 1
        -- D176: the viewer takes the card instead of the tiles
        fact.pk_wv = s.desk_workspaces == true
        fact.pk_viz = pill_settings().viz == "river" and 1 or 0
        -- D171: which faces are in the wheel's views (the edit bin's dots)
        local views = pill_settings().views
        local on = {}
        for _, id in ipairs(type(views) == "table" and views or pillmod.VIEWS_DEFAULT) do on[id] = true end
        for i, id in ipairs(pillmod.FACES) do fact["pk_vw" .. (i - 1)] = on[id] == true end
    end

    -- Now's week strip and its date line
    local DAYS = { "MO", "TU", "WE", "TH", "FR", "SA", "SU" }
    local function week()
        local t = os.time()
        local now = os.date("*t", t)
        local wd = (now.wday + 5) % 7 + 1          -- Monday 1 … Sunday 7 (Luau's os.date has no %u)
        local rows = {}
        for i = 1, 7 do
            local d = os.date("*t", t + (i - wd) * 86400)
            rows[i] = { n = i - 1, label = DAYS[i], day = d.day, today = i == wd }
        end
        model.pk_week = rows
        text.pk_date = os.date("%A %d %B", t)
        text.pk_wk = "WEEK " .. calendar.iso_week(now.year, now.month, now.day)
    end

    -- ── D176: the workspace viewer (pill.desk_workspaces) ──
    -- Each workspace as a live miniature: lib/deskprev groups Hyprland's clients by workspace and places
    -- every window where it really is in the card; the thumbnails service lends the pictures. The wheel
    -- turns the cards, hover chooses one, a press goes there (the same way the wallpapers' orbit works).
    local clients, thumbs, wv_rows, wv_at = {}, {}, {}, 0
    local wv_sw, wv_sh = 1920, 1080        -- the monitor's real size, read once (D177: not a guess)
    local function wv_publish()
        local cards = deskprev.cards(wv_rows, wv_at, wv_sw, wv_sh)
        local prev, box = {}, {}
        for ci, c in ipairs(cards) do
            prev[ci] = { id = c.id, slot = c.slot, n = c.n, on = c.active == true }
            local pics = deskprev.picture(c.wins, thumbs)
            for wi, w in ipairs(c.wins) do
                box[#box + 1] = { k = c.index, nx = w.nx, ny = w.ny, nw = w.nw, nh = w.nh,
                                  pic = pics[wi] or "", pictured = (pics[wi] or "") ~= "", focused = w.focused == true }
            end
        end
        fact.pk_wv_n, fact.pk_wv_at = #cards, wv_at
        model.pk_prev = prev
        model.pk_wbox = box
    end
    local function wv_slice()
        wv_at = math.max(0, math.min(wv_at, math.max(0, #wv_rows - deskprev.MAX)))
    end
    -- the monitor's size once: Hyprland's focused monitor, so a window sits where it really is whatever the
    -- screen (scaled monitors report their logical size)
    local wv_sized = false
    local function wv_screen()
        run("hyprctl", { "-j", "monitors" }, function(out)
            local ok, list = pcall(json.decode, tostring(out or ""))
            if ok and type(list) == "table" then
                for _, m in ipairs(list) do
                    local w, h = tonumber(m.width), tonumber(m.height)
                    if type(m) == "table" and m.focused == true and w and h and w > 0 and h > 0 then
                        wv_sw, wv_sh, wv_sized = w, h, true
                        wv_publish()
                        return
                    end
                end
            end
        end)
    end
    local function wv_read()
        if not wv_sized then wv_screen() end
        -- the pictures: asked of the thumbnails service (a read, not a watch — only Loom watches, D169)
        if type(sys) == "table" then
            local ok, state = pcall(sys.ask, "thumbnails")
            if ok and type(state) == "table" and type(state.list) == "table" then thumbs = state.list end
            pcall(sys.call, "thumbnails.want", "all")
        end
        run("hyprctl", { "-j", "clients" }, function(out)
            local ok, list = pcall(json.decode, tostring(out or ""))
            if ok and type(list) == "table" then
                clients = list
                local focused = -1
                for _, c in ipairs(list) do
                    if type(c) == "table" and tonumber(c.focusHistoryID) == 0 and type(c.workspace) == "table" then
                        focused = tonumber(c.workspace.id) or -1
                        break
                    end
                end
                wv_rows = deskprev.group(clients, focused)
                wv_slice()
            end
            wv_publish()
        end)
    end

    -- the Signals room: the newest three from Signal Loom (only Loom watches notifications, D169)
    local function signals()
        if not (ctx.loom and ctx.loom.recent) then return end
        local items, count = ctx.loom.recent(3)
        local rows = {}
        for i, it in ipairs(items or {}) do rows[i] = { n = i - 1, app = it.app or "", title = it.title or "", ago = it.ago or "" } end
        model.pk_sigs = rows
        fact.pk_sig_n = tonumber(count) or 0
    end

    -- ── D171: the new rooms' data ──
    -- Diagnostics: the machine, read once as the room opens
    local function diagnostics()
        -- through cat: the logic may run cat, not uname or uptime
        run("cat", { "/proc/sys/kernel/osrelease" }, function(out) text.pk_dg_kernel = (tostring(out or ""):gsub("%s+$", "")) end)
        run("cat", { "/proc/sys/kernel/hostname" }, function(out) text.pk_dg_host = (tostring(out or ""):gsub("%s+$", "")) end)
        run("cat", { "/proc/uptime" }, function(out)
            local s = math.floor(tonumber(tostring(out or ""):match("^(%d+)")) or 0)
            local d, h, m = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
            text.pk_dg_up = d > 0 and string.format("%d d %d h", d, h) or string.format("%d h %d min", h, m)
        end)
    end
    -- Wallpaper: a strip of six from the picker's index, moved by the wheel
    local walls, wall_at = {}, 0
    local function wall_strip()
        for k = 0, 3 do
            local it = walls[wall_at + k + 1]
            text["pk_wp" .. k] = it and (it.thumb ~= "" and it.thumb or it.path) or ""
            fact["pk_wph" .. k] = it ~= nil
        end
        fact.pk_wp_n, fact.pk_wp_at = #walls, wall_at
    end
    local function wall_read()
        local ok, raw = pcall(function() return sys.ask("files.read", "walls-index.json") end)
        local doc = raw
        if ok and type(raw) == "string" then ok, doc = pcall(json.decode, raw) end
        walls = {}
        if ok and type(doc) == "table" and type(doc.items) == "table" then
            for _, it in ipairs(doc.items) do
                if type(it) == "table" and type(it.path) == "string" and it.kind ~= "video" then
                    walls[#walls + 1] = { path = it.path, thumb = type(it.thumb) == "string" and it.thumb or "" }
                end
            end
        end
        wall_at = math.max(0, math.min(wall_at, #walls - 4))
        wall_strip()
    end

    -- D188: the board's size, which its body springs to. One body takes the shape of what it shows: a
    -- room its own size, the peek a small card, edit the editor's. `fresh`: it has just opened, so it
    -- grows from the capsule; otherwise from the size it had (pk_sw/pk_sh), and only if that changed.
    local function reshape(fresh)
        if opened ~= "board" then return end
        local w, h, core = pillmod.board_size(fact.pk_room or 0, fact.pk_edit == true, fact.pk_peek == true)
        if core > 0 then fact.pk_ch = core end
        if not fresh and w == fact.pk_bw and h == fact.pk_bh then return end
        if fresh then fact.pk_sw, fact.pk_sh = 0, 0
        else fact.pk_sw, fact.pk_sh = fact.pk_bw or w, fact.pk_bh or h end
        fact.pk_bw, fact.pk_bh = w, h
        fact.pk_mn = (fact.pk_mn or 0) + 1
    end

    local function room(r)
        -- told to the islands' readers too (they follow fact:pk_room, not heard for the logic's write)
        if ctx.roomed then ctx.roomed(r) else fact.pk_room = r end
        if r == parts.room_index("diagnostics") then diagnostics() end
        if r == parts.room_index("wallpaper") then wall_read() end
        if r == 0 then fact.pk_music = fact.mu_playing == true end
        if r == parts.room_index("find") then finds_publish() end
        if r == parts.room_index("connections") then nets_publish() end
        if r == parts.room_index("signals") then signals() end
        publish()
        reshape(false)
    end

    -- `peek`: open as the peek's small card (D188), not the whole board
    local function open_board(name, quiet, peek)
        week(); signals()
        fold.seq = fold.seq + 1                      -- an opening outruns the last close's late reset
        fact.pk_edit, fact.pk_sel, fact.pk_kb = false, -1, -1
        fact.pk_peek = peek == true
        fact.isl_shelf = false
        room(parts.room_index(name or "now") or 0)
        if pill_settings().desk_workspaces == true then wv_read() end
        set_open("board")
        reshape(true)
        if P.bmo() and not quiet then P.react("excited", 1300); P.say("hi!") end
    end
    -- closing keeps what it showed (the peek's card, the editor) until the body has folded back into the
    -- capsule: clearing pk_peek / pk_edit at once swapped the full board's header and core into a shrinking
    -- card (D189). `fold.later` resets them once the close has run, unless the board opened again.
    local function close()
        if opened == "board" then set_open("none") end
    end

    -- D188: the peek (ZenoShell's): resting on the Pill grows it into a small card; a press makes it the
    -- whole board; the pointer off both the capsule and the card folds it back. `pill.peek = false` stops it.
    local peek_state = { cap = false, card = false, seq = 0 }
    local function peek_on()
        return pill_settings().peek ~= false and fact.pill_on == true
    end
    local function peek_full()
        if not fact.pk_peek then return end
        fact.pk_peek = false
        reshape(false)
    end
    local function peek_leave()
        peek_state.seq = peek_state.seq + 1
        local mine = peek_state.seq
        after(300, function()
            if mine ~= peek_state.seq then return end
            if fact.pk_peek and opened == "board" and not peek_state.cap and not peek_state.card then close() end
        end)
    end
    local function peek_hover(on)
        peek_state.cap = on
        if not on then peek_leave(); return end
        peek_state.seq = peek_state.seq + 1
        local mine = peek_state.seq
        after(250, function()
            if mine ~= peek_state.seq or not peek_state.cap or not peek_on() then return end
            if opened ~= "none" then return end           -- the board, or another island, is already out
            open_board("now", true, true)
        end)
    end
    on("pk_peek_hover", function(v)
        peek_state.card = tonumber(v) == 1
        if peek_state.card then peek_state.seq = peek_state.seq + 1 else peek_leave() end
    end)
    on("pk_peek_open", function() peek_full() end)

    on("fact:open", function(v)
        opened = tostring(v or "none")
        if v ~= "board" then
            fact.pk_sel, fact.pk_kb = -1, -1; fact.pk_sw, fact.pk_sh = 0, 0
            fold.later()
        end
        if ctx.refresh then ctx.refresh() end      -- the Pill stays out while its board is open
    end)
    -- the player gone while Now Playing shows: back to the idle Now (review I1)
    on("fact:mu_has", function(v)
        if not v and fact.pk_music then fact.pk_music = false end
    end)
    -- the Signals room keeps up while it shows
    every(2000, function()
        if opened == "board" and fact.pk_room == parts.room_index("signals") then signals() end
    end)
    -- the viewer stays live while it shows: its workspaces, and their pictures
    every(1500, function()
        if opened == "board" and fact.pk_room == 0 and fact.pk_wv then wv_read() end
    end)
    -- the internet panel keeps up while it shows
    every(2000, function()
        if opened == "board" and fact.pk_room == parts.room_index("connections") then nets_publish() end
    end)

    local function do_pad(i)
        local id = pads[i + 1]
        if not id then return end
        if fact.pk_edit then fact.pk_sel = (fact.pk_sel == i) and -1 or i; return end
        local p = parts.get(id)
        if p.room then
            local r = parts.room_index(p.room)
            if id == "media" then room(0); fact.pk_music = fact.mu_has == true
            else room((fact.pk_room == r and r ~= 0) and 0 or r) end
            if P.bmo() then P.react("happy", 700) end
            return
        end
        if p.closes then close() end
        if p.side then fact.side = p.side end
        emit_scene(p.act, p.arg)
        if P.bmo() then P.react("happy", 900) end
    end

    on("pk_pad", function(v) do_pad(math.floor(tonumber(v) or -1)) end)
    on("pk_hover", function(v)
        local id = pads[(math.floor(tonumber(v) or -1)) + 1]
        if not id or fact.pk_edit then return end
        if P.bmo() then P.react("curious", 800); P.say(WORDS[id] or id) end
    end)
    on("pk_back", function() room(0) end)
    -- D171: the Workspaces room switches; the Actions room's drop terminal; the Wallpaper strip
    on("pk_ws", function(v)
        local n = math.floor(tonumber(v) or 0)
        if n >= 1 then run("hyprctl", { "dispatch", hypr.go_workspace(n) }) end
    end)
    on("pk_term", function()
        run("hyprctl", { "-j", "clients" }, function(out)
            if tostring(out or ""):find('"class": "mooi-drop"', 1, true) then
                run("hyprctl", { "dispatch", hypr.close_class("mooi-drop") })
            else
                -- floating, pinned, a fixed size: its window rule (mooi's Hyprland file, class mooi-drop)
                run("hyprctl", { "dispatch", hypr.exec("kitty --class mooi-drop") })
            end
        end)
        close()
    end)
    on("pk_wp_scroll", function(v)
        local d = (tonumber(v) or 0) > 0 and -1 or 1
        wall_at = math.max(0, math.min(wall_at + d, math.max(0, #walls - 4)))
        wall_strip()
    end)
    on("pk_wp", function(v)
        local it = walls[wall_at + (math.floor(tonumber(v) or -1)) + 1]
        if it then run("mooi", { "wall", "apply", it.path }) end
    end)
    -- D178: the Wi-Fi panel's networks — read from the service, not watched (only Loom watches, D169)
    nets_publish = function()
        local rows = {}
        if type(sys) == "table" then
            local ok, n = pcall(sys.ask, "network")
            local list = ok and type(n) == "table" and type(n.networks) == "table" and n.networks or {}
            for i, w in ipairs(list) do
                rows[i] = { n = i - 1, ssid = tostring(w.ssid or ""), strength = tonumber(w.strength) or 0,
                            secure = w.secure == true, known = w.known == true, active = w.active == true }
            end
        end
        model.pk_nets = rows
        fact.pk_nets_n = #rows
    end

    -- ── D178: the Pill's search — the forms it knows, filtered as the owner types (lib/pillfind) ──
    local finds = {}
    finds_publish = function()
        finds = pillfind.search(text.pk_q or "")
        local rows = {}
        for i, f in ipairs(finds) do
            rows[i] = { n = i - 1, name = f.name, sub = f.sub, tag = f.tag, k = i - 1 }
        end
        model.pk_finds = rows
        fact.pk_find_n = #rows
    end
    on("text:pk_q", function() finds_publish() end)
    on("pk_find", function(v)
        local f = finds[(math.floor(tonumber(v) or -1)) + 1]
        if not f then return end
        if f.room then
            room(parts.room_index(f.room) or 0)
            if P.bmo() then P.react("happy", 700) end
        else
            emit_scene(f.act, f.arg)
            if f.closes then close() end
        end
    end)
    -- D177: a press inside a desk tile — the time opens the calendar, the song the player, the machine the
    -- Resources room, the week the board's month
    on("pk_dk_press", function(v)
        local k = math.floor(tonumber(v) or -1)
        if k == 0 then set_open("calendar")
        elseif k == 1 then emit_scene("open_player", 0); close()
        elseif k == 2 then room(parts.room_index("resources"))
        elseif k == 3 then room(1) end
    end)
    -- D176: the viewer's wheel (one card along), the card under the pointer, and the press that goes
    on("pk_wv_scroll", function(v)
        local d = (tonumber(v) or 0) > 0 and -1 or 1
        wv_at = wv_at + d
        wv_slice()
        wv_publish()
    end)
    on("pk_wv_hover", function(v) fact.pk_wv_focus = math.floor(tonumber(v) or -1) end)
    on("pk_wv_go", function(v)
        local id = math.floor(tonumber(v) or 0)
        if id >= 1 then
            run("hyprctl", { "dispatch", hypr.go_workspace(id) })
            close()
        end
    end)
    -- the wheel over the board: the next room, or the one before, and round (the owner asked, 2026-11-07)
    local NAMES = { [0] = "now", "the month", "sound", "display", "connections", "power", "resources", "weather", "signals",
                    "music!", "actions", "diagnostics", "workspaces", "wallpaper", "the stash", "find it" }
    on("pk_scroll", function(v)
        local d = (tonumber(v) or 0) > 0 and -1 or 1
        local r = ((fact.pk_room or 0) + d) % #parts.ROOMS
        room(r)
        if P.bmo() then P.say(NAMES[r]) end
    end)
    on("pk_go", function(v) room(math.floor(tonumber(v) or 0)) end)
    -- a docked moon: its activity's room
    on("pk_chip", function(v)
        local now = P.now()
        local id = now and now.moons[(math.floor(tonumber(v) or -1)) + 1]
        if not id then return end
        local a = pillmod.press(id, "time", "left", P.osd())
        room(parts.room_index(a.room or "now") or 0)
        if id == "music" then fact.pk_music = true end
    end)
    on("pk_key", function(v)
        local k = math.floor(tonumber(v) or -1)
        local n = #pads
        if k == 0 or k == 1 then
            if n == 0 then return end
            local kb = fact.pk_kb or -1
            kb = (kb < 0) and (k == 1 and 0 or n - 1) or ((kb + (k == 1 and 1 or -1)) % n)
            fact.pk_kb = kb
            if P.bmo() and pads[kb + 1] then P.say(WORDS[pads[kb + 1]] or pads[kb + 1]) end
        elseif k == 2 then
            if (fact.pk_kb or -1) >= 0 then do_pad(fact.pk_kb) end
        elseif k == 3 then
            if fact.pk_edit then fact.pk_edit, fact.pk_sel = false, -1; reshape(false)
            elseif (fact.pk_room or 0) ~= 0 then room(0)
            else close() end
        end
    end)

    -- ── Edit: the pads and the face ───────────────────────────
    local function set_pads(list)
        pill_settings().pads = list
        save(); publish()
    end
    on("pk_edit_cmd", function(v)
        local n = math.floor(tonumber(v) or -1)
        if n == 0 then
            fact.pk_edit = not fact.pk_edit
            fact.pk_sel = fact.pk_edit and math.min(#pads, 7) or -1      -- D188: the first empty slot
            fact.pk_etab = 0
            if fact.pk_edit and P.bmo() then P.react("focused", 1500) end
            reshape(false)
            return
        end
        local i = n % 10
        local list = {}
        for k, id in ipairs(pads) do list[k] = id end
        if n >= 10 and n < 20 and list[i + 1] then
            table.remove(list, i + 1); fact.pk_sel = math.min(i, #list)    -- D188: stays on that place
        elseif n >= 20 and n < 30 and i > 0 and list[i + 1] then
            list[i], list[i + 1] = list[i + 1], list[i]; fact.pk_sel = i - 1
        elseif n >= 30 and n < 40 and list[i + 2] then
            list[i + 1], list[i + 2] = list[i + 2], list[i + 1]; fact.pk_sel = i + 1
        else return end
        set_pads(list)
    end)
    on("pk_part", function(v)
        local id = parts.ORDER[(math.floor(tonumber(v) or -1)) + 1]
        if not id then return end
        for _, have in ipairs(pads) do if have == id then return end end
        local list = {}
        for k, x in ipairs(pads) do list[k] = x end
        local sel = fact.pk_sel or -1
        if sel >= 0 and list[sel + 1] then list[sel + 1] = id
        elseif #list < 8 then
            list[#list + 1] = id
            fact.pk_sel = math.min(#list, 7)       -- D188: on to the next empty slot
        else return end
        set_pads(list)
    end)
    -- D188: the editor — a slot chosen (an empty one means "add here"), and its tab
    on("pk_slot", function(v)
        local i = math.floor(tonumber(v) or -1)
        if i < 0 or i > 7 then return end
        fact.pk_sel = math.min(i, #pads, 7)
    end)
    on("pk_etab", function(v) fact.pk_etab = (math.floor(tonumber(v) or 0) == 1) and 1 or 0 end)
    on("pk_face", function(v)
        local f = pillmod.FACES[(math.floor(tonumber(v) or -1)) + 1]
        if not f then return end
        pill_settings().face = f
        save()
    end)
    -- D171: a face's toggle in the edit bin: in the wheel's views, or out
    on("pk_view_toggle", function(v)
        local f = pillmod.FACES[(math.floor(tonumber(v) or -1)) + 1]
        if not f then return end
        local p = pill_settings()
        local list, found = {}, false
        local src = type(p.views) == "table" and p.views or pillmod.VIEWS_DEFAULT
        for _, id in ipairs(src) do if id == f then found = true else list[#list + 1] = id end end
        if not found then list[#list + 1] = f end
        p.views = list
        save()
        local on = {}
        for _, id in ipairs(list) do on[id] = true end
        for i, id in ipairs(pillmod.FACES) do fact["pk_vw" .. (i - 1)] = on[id] == true end
    end)
    on("pk_viz", function(v)
        local p = pill_settings()
        local n = tonumber(v)
        -- D188: the editor names the one it wants (0 halo · 1 river); anything else turns it over
        if n == 0 then p.viz = "halo" elseif n == 1 then p.viz = "river"
        else p.viz = p.viz == "river" and "halo" or "river" end
        save(); publish()
    end)
    on("pill_edit_open", function()
        if not fact.pill_on then return end
        open_board("now")
        fact.pk_edit = true
        fact.pk_sel, fact.pk_etab = math.min(#pads, 7), 0
        reshape(true)
    end)
    on("pk_sig_clear", function()
        if ctx.loom and ctx.loom.clear then ctx.loom.clear() end
        signals()
    end)

    publish()

    return {
        -- a press on the Pill (bar.luau hears it): the board, or the old jumps on the right
        press = function(button, main)
            P.touch()
            -- D179: the right button, as the owner chose it in Settings (pill.right)
            if button == "right" then
                local r = pill_settings().right
                if r == "nothing" then return end
                if r == "board" then open_board("now"); return end
                if r == "notes" then emit_scene("qn_toggle"); return end
                if r == "settings" then emit_scene("bar_menu"); return end
            end
            if button == "left" and opened == "board" then
                if fact.pk_peek then peek_full(); return end          -- D188: the peek grows into the board
                if P.bmo() then P.poke() else close() end
                return
            end
            -- the face showing: a view the wheel turned to is what a press means, not the saved face
            local a = pillmod.press(main, (P.face and P.face()) or pill_settings().face or "time", button, P.osd())
            if a.kind == "board" then open_board(a.room)
            elseif a.kind == "nexus" then emit_scene("open_nexus")
            elseif a.kind == "calendar" then set_open("calendar")
            elseif a.kind == "player" then emit_scene("open_player", 0)
            elseif a.kind == "record" then emit_scene("record", 0)
            elseif a.kind == "island" then set_open(a.island) end
        end,
        publish = publish,
        -- Super twice (`mooi pill`): the board on the room of the view showing — never the Nexus — or,
        -- open, closed (no poke) (review I4)
        call = function(main)
            P.touch()
            if opened == "board" and fact.pk_peek then peek_full(); return end
            if opened == "board" then close(); return end
            local face = (P.face and P.face()) or pill_settings().face or "time"
            if face == "nexus" then face = "time" end
            local a = pillmod.press(main, face, "left", P.osd())
            open_board(a.room)
        end,
        open = function() return opened end,
        hover = peek_hover,     -- D188: the capsule pointed at (1) or left (0)
    }
end
