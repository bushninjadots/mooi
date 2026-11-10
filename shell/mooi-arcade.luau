-- mooi's arcade (D276; k4's games, ported as mooi's own): the logic. A picker, then a game; every game's rules are
-- pure under lib/arcade/ and tested. Best scores live in arcade.json in mooi's data folder. Nothing runs while it
-- is shut: a game's clock is a chain of `after` that stops when the game does.

local ferro = require("lib/ferro")
local config = require("lib/config")
local SNAKE = require("lib/arcade/snake")
local GRIETA = require("lib/arcade/grieta")
local MAZMORRA = require("lib/arcade/mazmorra")

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind) else ok, v = pcall(sys.ask, "files.read", name) end
    if ok then return v end
end

A = { page = 0, sel = 0, settings = config.parse(read("settings.json"), json.decode), scores = {}, maz = nil }
local saved = read("arcade.json", "json")
if type(saved) == "table" then
    if type(saved.best) == "table" then A.scores = saved.best end
    A.maz = MAZMORRA.restore(saved.mazmorra)
end
local function save()
    local payload = { best = A.scores }
    if A.maz then payload.mazmorra = A.maz end
    pcall(sys.call, "files.write", "arcade.json", json.encode(payload))
end

-- ── the palette ──
local palette = read("palette.json", "json")
local function paint()
    local s = A.settings
    local out = ferro.resolve(s.theme.source, palette, s.theme.signal, false, ferro.options(s))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
end
paint()
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)

-- ── the games, in the picker's order; `page` is the scene's page for each ──
local GAMES = {
    { id = "snake", name = "Snake", glyph = "󰉚", line = "Eat, grow, never bite yourself. Faster as you grow.", page = 2, ready = true },
    { id = "grieta", name = "La Grieta", glyph = "󰌌", line = "Type the words to seal what crawls out of the crack.", page = 3, ready = true },
    { id = "mazmorra", name = "Mazmorra", glyph = "󰞇", line = "An idle dungeon that fights on while you work.", page = 4, ready = true },
}
local function picker()
    local rows = {}
    for i, g in ipairs(GAMES) do
        local best = tonumber(A.scores[g.id])
        rows[i] = { name = g.name, glyph = g.glyph, line = g.line, ready = g.ready,
                    best = g.ready and (best and ("BEST " .. best) or "NEW") or "COMING NEXT" }
    end
    model.gm = rows
    fact.ac_sel = A.sel
end

-- ── Snake ──
local sn = nil
local function sn_draw()
    local cells = {}
    for i, c in ipairs(sn.body) do if i > 1 then cells[#cells + 1] = { x = c.x, y = c.y } end end
    model.sn = cells
    fact.sn_hx, fact.sn_hy = sn.body[1].x, sn.body[1].y
    fact.sn_fx, fact.sn_fy = sn.food and sn.food.x or -1, sn.food and sn.food.y or -1
    text.sn_score = tostring(sn.score)
    text.sn_best = tostring(tonumber(A.scores.snake) or 0)
end
local function sn_new()
    sn = SNAKE.new(os.time())
    sn.state = 0
    fact.sn_state = 0
    sn_draw()
end
local function sn_over(won)
    sn.state = won and 4 or 3
    fact.sn_state = sn.state
    if sn.score > (tonumber(A.scores.snake) or 0) then A.scores.snake = sn.score; save() end
    sn_draw()
    pcall(sound.tone, { wave = "triangle", freq = won and 880 or 196, ms = 260, volume = 0.25, release = 200 })
end
-- each start of the clock has its own number: a pause and a quick resume must not leave two clocks running
local sn_gen = 0
local function sn_tick(gen)
    if gen ~= sn_gen or A.page ~= 2 or not sn or sn.state ~= 1 then return end
    local r = SNAKE.step(sn)
    if r == "dead" then sn_over(false); return end
    if r == "won" then sn_over(true); return end
    if r == "ate" then pcall(sound.tone, { wave = "sine", freq = 660 + sn.score * 8, ms = 60, volume = 0.18, release = 50 }) end
    sn_draw()
    after(SNAKE.interval(sn), function() sn_tick(gen) end)
end
local function sn_go()
    if sn.state == 3 or sn.state == 4 then sn_new() end
    if sn.state == 1 then sn.state = 2; fact.sn_state = 2; return end
    sn.state = 1
    fact.sn_state = 1
    sn_gen = sn_gen + 1
    local gen = sn_gen
    after(SNAKE.interval(sn), function() sn_tick(gen) end)
end
local SN_KEYS = { [38] = "up", [87] = "up", [40] = "down", [83] = "down", [37] = "left", [65] = "left", [39] = "right", [68] = "right" }

-- ── La Grieta ──
local gz = nil
local gz_gen = 0
local GZ_STATE = { ready = 0, playing = 1, choose = 2, over = 3 }

local function gz_draw()
    if not gz then return end
    local rows = {}
    for i, w in ipairs(gz.words) do
        local done = ""
        if gz.typed ~= "" and w.text:sub(1, #gz.typed) == gz.typed then done = gz.typed end
        rows[i] = { text = w.text, done = done, n = #done, x = w.x, y = w.y }
    end
    model.gz = rows
    local ups = {}
    for i, u in ipairs(gz.options) do ups[i] = { name = u.name, line = u.line, glyph = u.glyph } end
    model.gzu = ups
    fact.gz_state = GZ_STATE[gz.state] or 0
    fact.gz_wave = gz.wave
    fact.gz_flash = gz.flash > 0 and 1 or 0
    fact.gz_sel = gz.pick
    fact.gz_charge = gz.charges > 0
    text.gz_score = tostring(gz.score)
    text.gz_best = tostring(tonumber(A.scores.grieta) or 0)
    text.gz_lives = string.rep("󰋑 ", math.max(0, gz.lives))
    text.gz_typed = gz.typed ~= "" and (gz.typed .. "_") or "TYPE A WORD"
    text.gz_charges = gz.charges > 0 and ("TAB · " .. gz.charges .. " SEAL") or ""
end

local function gz_over()
    if gz.score > (tonumber(A.scores.grieta) or 0) then A.scores.grieta = gz.score; save() end
    gz_draw()
    pcall(sound.tone, { wave = "sawtooth", freq = 150, ms = 340, volume = 0.25, release = 260 })
end

local function gz_tick(gen)
    if gen ~= gz_gen or A.page ~= 3 or not gz or gz.state ~= "playing" then return end
    local events = GRIETA.tick(gz, 50)
    for _, e in ipairs(events) do
        if e.kind == "hit" then
            pcall(sound.tone, { wave = "square", freq = 110, ms = 90, volume = 0.2, release = 70 })
        elseif e.kind == "wave" then
            pcall(sound.tone, { wave = "triangle", freq = 740, ms = 220, volume = 0.2, release = 160 })
        elseif e.kind == "over" then
            gz_over()
            return
        end
    end
    gz_draw()
    if gz.state == "playing" then after(50, function() gz_tick(gen) end) end
end

local function gz_run()
    gz_gen = gz_gen + 1
    local gen = gz_gen
    after(50, function() gz_tick(gen) end)
end

local function gz_start()
    if not gz then return end
    if gz.state == "over" then gz = GRIETA.new(os.time()); gz_draw() end
    if GRIETA.start(gz) then gz_draw(); gz_run() end
end

local function gz_choose(i)
    if not gz or gz.state ~= "choose" then return end
    if GRIETA.choose(gz, i) then
        gz_draw()
        gz_run()
        pcall(sound.tone, { wave = "triangle", freq = 620, ms = 130, volume = 0.18, release = 90 })
    end
end

local function gz_letter(ch)
    if not gz or gz.state ~= "playing" then return end
    local r, _, gain, wx, wy = GRIETA.type(gz, ch)
    if r == "sealed" then
        fact.gz_bx, fact.gz_by, fact.gz_burst = wx or 50, wy or 40, 1
        after(280, function() fact.gz_burst = 0 end)
        pcall(sound.tone, { wave = "sine", freq = 720 + math.min(260, (gain or 0) * 3), ms = 70, volume = 0.2, release = 60 })
    elseif r == "wrong" then
        pcall(sound.tone, { wave = "square", freq = 130, ms = 60, volume = 0.16, release = 50 })
    end
    gz_draw()
end

local function gz_seal()
    if not gz or gz.state ~= "playing" then return end
    local n = GRIETA.use_seal(gz)
    if n > 0 then pcall(sound.tone, { wave = "triangle", freq = 880, ms = 220, volume = 0.22, release = 180 }) end
    gz_draw()
end

-- ── Mazmorra ──
local mz = nil
local mz_gen = 0
local mz_saves = 0

local function mz_draw()
    if not mz then return end
    local mon = mz.monster
    fact.mz_floor = mz.floor
    fact.mz_gold = mz.gold
    fact.mz_best = mz.best
    fact.mz_hero = mz.hero_hp
    fact.mz_heromax = MAZMORRA.hero_max(mz)
    fact.mz_mon = mon and mon.hp or 0
    fact.mz_monmax = mon and mon.max_hp or 1
    fact.mz_boss = mon and mon.boss or false
    fact.mz_boost = mz.boost
    fact.mz_rest = mz.rest
    text.mz_name = mon and mon.name or "—"
    text.mz_glyph = mon and mon.glyph or "󰞇"
    if mz.boost > 0 then
        text.mz_state = "BOOST · " .. mz.boost .. " s"
    elseif mz.rest > 0 then
        text.mz_state = "REST · " .. mz.rest .. " s"
    else
        text.mz_state = "SPACE · BOOST 30 s"
    end
    local log = {}
    for i, line in ipairs(mz.log) do log[i] = { line = line } end
    model.mzlog = log
    local shop = {}
    for i, up in ipairs(MAZMORRA.UPGRADES) do
        local price = MAZMORRA.price(mz, i - 1) or 0
        shop[i] = { name = up.name, glyph = up.glyph, level = tostring(mz[up.id] or 0),
                    cost = tostring(price), afford = mz.gold >= price }
    end
    model.mzshop = shop
    if mz.best > (tonumber(A.scores.mazmorra) or 0) then A.scores.mazmorra = mz.best end
end

local function mz_persist()
    if not mz then return end
    mz_draw()
    A.maz = mz
    save()
end

local function mz_tick(gen)
    if gen ~= mz_gen or A.page ~= 4 or not mz then return end
    MAZMORRA.tick(mz, 1)
    mz.last = os.time()
    mz_draw()
    mz_saves = mz_saves + 1
    if mz_saves >= 5 then mz_saves = 0; mz_persist() end
    after(1000, function() mz_tick(gen) end)
end

local function mz_enter()
    if not mz then mz = A.maz or MAZMORRA.new(os.time()); A.maz = mz end
    MAZMORRA.offline(mz, os.time())
    mz.last = os.time()
    mz_draw()
    mz_gen = mz_gen + 1
    local gen = mz_gen
    after(1000, function() mz_tick(gen) end)
end

local function mz_buy(i)
    if not mz then return end
    local ok = MAZMORRA.buy(mz, i)
    if ok then
        mz_persist()
        pcall(sound.tone, { wave = "triangle", freq = 520, ms = 110, volume = 0.18, release = 80 })
    else
        pcall(sound.tone, { wave = "square", freq = 150, ms = 70, volume = 0.14, release = 60 })
    end
    mz_draw()
end

local function mz_boost()
    if not mz then return end
    if MAZMORRA.boost(mz) then
        mz_draw()
        pcall(sound.tone, { wave = "sine", freq = 820, ms = 150, volume = 0.2, release = 120 })
    end
end

-- ── pages ──
local function show(page)
    A.page = page
    fact.ac_page = page
    if page == 1 then picker() end
    if page == 2 then sn_new() end
    if page == 3 then
        gz = GRIETA.new(os.time())
        gz_gen = gz_gen + 1
        gz_draw()
    end
    if page == 4 then mz_enter() end
end
local function play(i)
    local g = GAMES[i + 1]
    if g and g.ready and g.page then show(g.page) end
end

on("ac_cmd", function(v)
    v = math.floor(tonumber(v) or 0)
    if v == 0 or A.page > 0 then
        if sn then sn.state = sn.state == 1 and 2 or sn.state end
        if A.page == 3 then gz_gen = gz_gen + 1 end
        if A.page == 4 and mz then mz.last = os.time(); mz_persist() end
        show(0)
    else
        show(1)
    end
end)
on("ac_pick", function(v) A.sel = math.floor(tonumber(v) or 0); play(A.sel) end)
on("ac_key", function(v)
    v = math.floor(tonumber(v) or 0)
    if A.page == 1 then
        if v == 27 then show(0)
        elseif v == 37 or v == 65 then A.sel = (A.sel - 1) % #GAMES; picker()
        elseif v == 39 or v == 68 then A.sel = (A.sel + 1) % #GAMES; picker()
        elseif v == 13 or v == 32 then play(A.sel) end
    elseif A.page == 2 then
        if v == 27 then
            if sn and sn.state == 1 then sn.state = 2 end
            show(1)
        elseif v == 32 or v == 13 or v == 80 then sn_go()
        elseif SN_KEYS[v] then
            if sn.state == 0 then sn_go() end
            SNAKE.turn(sn, SN_KEYS[v])
        end
    elseif A.page == 3 then
        if v == 27 then
            gz_gen = gz_gen + 1
            show(1)
        elseif v == 13 then
            if not gz then return end
            if gz.state == "choose" then
                gz_choose(gz.pick)
            else
                gz_start()
            end
        elseif gz and gz.state == "choose" and (v == 37 or v == 39) then
            GRIETA.select(gz, v == 37 and -1 or 1)
            gz_draw()
        elseif gz and gz.state == "choose" and ((v >= 49 and v <= 51) or v == 90 or v == 88 or v == 67) then
            local pick = v - 49
            if v == 90 then pick = 0 elseif v == 88 then pick = 1 elseif v == 67 then pick = 2 end
            gz_choose(pick)
        elseif gz and gz.state == "playing" and v == 9 then
            gz_seal()
        elseif gz and gz.state == "playing" and v == 8 then
            GRIETA.backspace(gz)
            gz_draw()
        elseif gz and gz.state == "playing" and v >= 1097 and v <= 1122 then
            gz_letter(string.char(v - 1000))
        end
    elseif A.page == 4 then
        if v == 27 then
            if mz then mz.last = os.time(); mz_persist() end
            show(1)
        elseif v == 32 then
            mz_boost()
        elseif (v >= 49 and v <= 52) or v == 90 or v == 88 or v == 67 or v == 86 then
            local which = v - 49
            if v == 90 then which = 0 elseif v == 88 then which = 1 elseif v == 67 then which = 2 elseif v == 86 then which = 3 end
            mz_buy(which)
        end
    end
end)

log("arcade · up")
