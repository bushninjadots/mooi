-- The Pill board (D170): a press on the Pill unfolds it into a board — a core of rooms over the owner's
-- pads (pill.pads), each wired to the core. lib/pill decides what a press does and which pads are valid,
-- lib/pillpads what each pad is; this carries it out: opens and closes the board (fact open = board),
-- picks the room (pk_room), publishes the pads (pk_n, pk_k0…7), runs a pad's act (the same event its
-- module's press sends), edits the pads and the face, and has BMO react. ui/pillboard.plm draws it; the
-- rooms read what the islands gather (shell/islands.luau gathers for the board's room too).

local pillmod = require("lib/pill")
local parts = require("lib/pillpads")
local calendar = require("lib/calendar")

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
    -- what is open, as the scene says: a press outside or Escape closes it in the scene, and reading
    -- fact.open back gives the logic's last write, not that (a closed board read as open, D170)
    local opened = "none"
    local function set_open(v)
        opened = v
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
        fact.pk_viz = pill_settings().viz == "river" and 1 or 0
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

    -- the Signals room: the newest three from Signal Loom (only Loom watches notifications, D169)
    local function signals()
        if not (ctx.loom and ctx.loom.recent) then return end
        local items, count = ctx.loom.recent(3)
        local rows = {}
        for i, it in ipairs(items or {}) do rows[i] = { n = i - 1, app = it.app or "", title = it.title or "", ago = it.ago or "" } end
        model.pk_sigs = rows
        fact.pk_sig_n = tonumber(count) or 0
    end

    local function room(r)
        fact.pk_room = r
        if r == 0 then fact.pk_music = fact.mu_playing == true end
        if r == parts.room_index("signals") then signals() end
        publish()
    end

    local function open_board(name)
        week(); signals()
        fact.pk_edit, fact.pk_sel, fact.pk_kb = false, -1, -1
        fact.isl_shelf = false
        room(parts.room_index(name or "now") or 0)
        set_open("board")
        if P.bmo() then P.react("excited", 1300); P.say("hi!") end
    end
    local function close()
        if opened == "board" then set_open("none") end
    end

    on("fact:open", function(v)
        opened = tostring(v or "none")
        if v ~= "board" then fact.pk_edit, fact.pk_sel, fact.pk_kb = false, -1, -1 end
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
    -- the wheel over the board: the next room, or the one before, and round (the owner asked, 2026-11-07)
    local NAMES = { [0] = "now", "the month", "sound", "display", "connections", "power", "resources", "weather", "signals" }
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
            if fact.pk_edit then fact.pk_edit, fact.pk_sel = false, -1
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
            fact.pk_edit = not fact.pk_edit; fact.pk_sel = -1
            if fact.pk_edit and P.bmo() then P.react("focused", 1500) end
            return
        end
        local i = n % 10
        local list = {}
        for k, id in ipairs(pads) do list[k] = id end
        if n >= 10 and n < 20 and list[i + 1] then
            table.remove(list, i + 1); fact.pk_sel = -1
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
        elseif #list < 8 then list[#list + 1] = id
        else return end
        set_pads(list)
    end)
    on("pk_face", function(v)
        local f = pillmod.FACES[(math.floor(tonumber(v) or -1)) + 1]
        if not f then return end
        pill_settings().face = f
        save()
    end)
    on("pk_viz", function()
        local p = pill_settings()
        p.viz = p.viz == "river" and "halo" or "river"
        save(); publish()
    end)
    on("pill_edit_open", function()
        if not fact.pill_on then return end
        open_board("now")
        fact.pk_edit = true
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
            if button == "left" and opened == "board" then
                if P.bmo() then P.poke() else close() end
                return
            end
            local a = pillmod.press(main, pill_settings().face or "time", button, P.osd())
            if a.kind == "board" then open_board(a.room)
            elseif a.kind == "nexus" then emit_scene("open_nexus")
            elseif a.kind == "calendar" then set_open("calendar")
            elseif a.kind == "player" then emit_scene("open_player", 0)
            elseif a.kind == "record" then emit_scene("record", 0)
            elseif a.kind == "island" then set_open(a.island) end
        end,
        publish = publish,
        open = function() return opened end,
    }
end
