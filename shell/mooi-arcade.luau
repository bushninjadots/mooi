-- mooi's arcade (D276; k4's games, ported as mooi's own): the logic. A picker, then a game; every game's rules are
-- pure under lib/arcade/ and tested. Best scores live in arcade.json in mooi's data folder. Nothing runs while it
-- is shut: a game's clock is a chain of `after` that stops when the game does.

local ferro = require("lib/ferro")
local config = require("lib/config")
local SNAKE = require("lib/arcade/snake")

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind) else ok, v = pcall(sys.ask, "files.read", name) end
    if ok then return v end
end

A = { page = 0, sel = 0, settings = config.parse(read("settings.json"), json.decode), scores = {} }
local saved = read("arcade.json", "json")
if type(saved) == "table" and type(saved.best) == "table" then A.scores = saved.best end
local function save() pcall(sys.call, "files.write", "arcade.json", json.encode({ best = A.scores })) end

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
    { id = "grieta", name = "La Grieta", glyph = "󰌌", line = "Type the words to seal what crawls out of the crack.", ready = false },
    { id = "mazmorra", name = "Mazmorra", glyph = "󰞇", line = "An idle dungeon that fights on while you work.", ready = false },
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

-- ── pages ──
local function show(page)
    A.page = page
    fact.ac_page = page
    if page == 1 then picker() end
    if page == 2 then sn_new() end
end
local function play(i)
    local g = GAMES[i + 1]
    if g and g.ready and g.page then show(g.page) end
end

on("ac_cmd", function(v)
    v = math.floor(tonumber(v) or 0)
    if v == 0 or A.page > 0 then
        if sn then sn.state = sn.state == 1 and 2 or sn.state end
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
    end
end)

log("arcade · up")
