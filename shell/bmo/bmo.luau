-- BMO's logic: where he is, what he does, how he feels. The scene draws and moves; this decides.
-- brain.luau is the pure part (faces, moods, choices) and is unit-tested.
--
-- From outside: `pleamar --say bmo "emit ui N"` presses a control (codes in on("ui") below;
-- 120 walk, 121 dance, 122 look, 123 sit, 124 his game, 125 hum), `emit tell N` tells him what
-- the bar saw (Desktop awareness, below), and
-- `pleamar --say bmo get mood_t` (or act_t, energy, wx…) reads him.

local B = require("brain")

-- His settings are mooi's (settings.json's `companion` section, Settings → BMO): bin/mooi links his
-- data folder to mooi's. Where he stands is his own (bmo-state.json beside it).
local FILE = "settings.json"
local STATE = "bmo-state.json"

-- ── Settings ─────────────────────────────────────────────────
local function read(name)
    local ok, v = pcall(sys.ask, "files.read", name, "json")
    return ok and v or nil
end
local function companion_of(doc) return type(doc) == "table" and doc.companion or nil end
local cfg = B.settings(companion_of(read(FILE)))
local state = read(STATE)
if type(state) ~= "table" then state = { x = -1, y = -1 } end
state.x, state.y = tonumber(state.x) or -1, tonumber(state.y) or -1
local SIZES = { 0.5, 0.7, 0.9, 1.15 }
local DOZES = { 5, 10, 30, 100000 }
local MOTIONS = { "still", "calm", "lively" }

local function index_of_name(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
    return 1
end
local function index_of(list, v)
    local best, bd = 1, math.huge
    for i, x in ipairs(list) do
        local d = math.abs(x - v)
        if d < bd then best, bd = i, d end
    end
    return best
end

-- ── Only one BMO ─────────────────────────────────────────────
-- A second program called bmo gets `bmo-<pid>` for a name, and nothing (the bar's `--say bmo`
-- included) can see it, so two would live on. Each one marks itself and asks whoever answers to
-- "bmo" for its mark; one that is not the answer is the second, finds its own name by its mark
-- among the bmo-<pid> sockets, and quits. Until then it draws nothing and saves nothing.
local spare = false
-- the time, and where this process keeps a fresh table (each process its own place)
local mark = (os.time() % 100000) * 10000 + (tonumber(tostring({}):match("(%x+)$") or "0", 16) or 0) % 10000
fact.token = mark
local function only_one()
    run("pleamar", { "--say", "bmo", "get token" }, function(out, code)
        -- only a clear answer that is not his own makes him the spare (no answer: he is not)
        local theirs = code == 0 and tonumber((out or ""):match("^%s*([%d.]+)%s*$")) or nil
        if not theirs or theirs == mark then return end
        spare = true
        fact.ready = false
        local dir = tostring(sys.ask("env", "XDG_RUNTIME_DIR") or "") .. "/pleamar"
        run("ls", { dir }, function(list)
            for pid in tostring(list or ""):gmatch("bmo%-(%d+)%.sock") do
                local name = "bmo-" .. pid
                run("pleamar", { "--say", name, "get token" }, function(t)
                    if tonumber((t or ""):match("[%d.]+")) == mark then run("pleamar", { "--say", name, "quit" }) end
                end)
            end
        end)
    end)
end
after(600, only_one)

-- His panel's choices go back into mooi's settings, the rest of the file as it is now.
local function save()
    if spare then return end
    if tostring(sys.ask("env", "MOOI_SAFE") or "") == "1" then return end
    local doc = read(FILE)
    if type(doc) ~= "table" then return end
    local c = type(doc.companion) == "table" and doc.companion or {}
    c.wander, c.locked, c.size, c.motion = cfg.wander, cfg.locked, B.size_name(cfg.size), cfg.motion
    c.music, c.above, c.doze, c.clock = cfg.music, cfg.above, cfg.doze, cfg.clock
    c.place, c.variant, c.throw, c.talk, c.react = cfg.place, cfg.variant, cfg.throw, cfg.talk, cfg.react
    doc.companion = c
    pcall(sys.call, "files.write", FILE, doc)
end
local function save_state() if not spare then pcall(sys.call, "files.write", STATE, state) end end

-- ── The screen and where he may stand ────────────────────────
local sw, sh = 1920, 1080
-- On the bar (companion.place) he is small, whatever his size, and stands just under the bar.
local function eff_size() return cfg.place == "bar" and math.min(cfg.size, 0.42) or cfg.size end
local function bar_floor()
    local b = type(read(FILE)) == "table" and read(FILE).bar or {}
    return (tonumber(type(b) == "table" and b.offset) or 0) + (tonumber(type(b) == "table" and b.height) or 30) + 6
end
local function bw() return 160 * eff_size() end
local function bh() return 196 * eff_size() end
local function min_x() return 40 end
local function max_x() return math.max(min_x(), sw - bw() - 40) end
local function min_y() return cfg.place == "bar" and bar_floor() or 50 end
local function max_y() return cfg.place == "bar" and bar_floor() or math.max(min_y(), sh - bh() - 4) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function home_x() return max_x() - 60 end
local function home_y() return max_y() - 24 end

local x, y = 0, 0
local function place(nx, ny)
    x = clamp(nx, min_x(), max_x())
    y = clamp(ny, min_y(), max_y())
    fact.wx = x
    fact.wy = y
end

-- ── State ────────────────────────────────────────────────────
local mood, mood_since = "happy", os.time()
local activity = "idle"
-- What he is doing; the idle acts (sitting, his game, humming) are drawn from it, so whatever
-- interrupts one (a walk, a hand, sleep) ends it too.
local function set_activity(a)
    activity = a
    fact.sitting = a == "sitting"
    fact.gaming = a == "gaming"
    fact.humming = a == "humming"
end
local reaction = ""
local energy = 1
local last_touch = os.time()
local hovered = false
local pokes, drags = {}, {}
local last_greet = 0

local function recent(list, seconds)
    local out, t = {}, os.time()
    for _, v in ipairs(list) do if t - v < seconds then out[#out + 1] = v end end
    return out
end

local function show_face()
    local f = B.FACES[B.expression({ mood = mood, activity = activity, reaction = reaction })] or B.FACES.happy
    fact.e_ew, fact.e_eh, fact.e_sql, fact.e_sqr = f.ew, f.eh, f.sql, f.sqr
    fact.e_lid, fact.e_brow, fact.e_bron = f.lid, f.brow, f.bron
    fact.e_mc, fact.e_mo, fact.e_mw, fact.e_tg, fact.e_bl = f.mc, f.mo, f.mw, f.tg, f.bl
    text.mood_t = mood
    text.act_t = activity ~= "idle" and activity or ""
    for i, m in ipairs(B.MOODS) do if m == mood then fact.mood_i = i - 1 end end
    fact.asleep = activity == "sleeping"
end

local function set_mood(m)
    if m == mood or not B.is_mood(m) then return end
    mood, mood_since = m, os.time()
    show_face()
end

local react_token = 0
local function react(face, ms)
    reaction = face
    react_token = react_token + 1
    local mine = react_token
    show_face()
    after(ms, function() if react_token == mine then reaction = ""; show_face() end end)
end

local function move(name)
    if cfg.motion == "still" then return end
    play(name)
end

-- ── Speech ───────────────────────────────────────────────────
-- One bubble at a time: a passing remark never covers what matters (a ding, his hunger, a cheer)
-- while that is still up. Returns whether it was said.
local say_token = 0
local important_up = false    -- the bubble showing is one that matters
local function say(t, ms, important)
    if not important and important_up and fact.bubble_on then return false end
    text.bubble = t
    fact.bubble_on = true
    say_token = say_token + 1
    local mine = say_token
    important_up = important == true
    if ms then
        after(ms, function()
            if say_token ~= mine then return end
            important_up = false
            if activity ~= "sleeping" then fact.bubble_on = false end
        end)
    end
    return true
end
-- A line from one of his pools (brain.luau LINES), at his talk level, not one he said lately.
local said_lately = {}
local function chat(pool, important, ms)
    local line = B.chatter(pool, cfg.talk, important, said_lately, math.random())
    if line and say(line, ms or 1800, important) then B.remember(said_lately, line) end
end

-- ── Walking ──────────────────────────────────────────────────
local walk_timer, walk_to, walk_dir = nil, nil, 0
local function stop_walking()
    if walk_timer then cancel(walk_timer); walk_timer = nil end
    if fact.walking then fact.walking = false end
    fact.facing = 0
    if activity == "walking" then set_activity("idle"); show_face() end
end

local function save_position()
    state.x, state.y = math.floor(x + 0.5), math.floor(y + 0.5)
    save_state()
end

local function walk(target)
    target = clamp(target, min_x(), max_x())
    if math.abs(target - x) < 16 then return end
    stop_walking()
    set_activity("walking")
    walk_to, walk_dir = target, target > x and 1 or -1
    fact.facing = walk_dir
    -- turn first, then stride
    after(240, function()
        if activity ~= "walking" then return end
        fact.walking = true
        local speed = 60 * cfg.size
        walk_timer = every(33, function()
            x = x + walk_dir * speed * 0.033
            if (walk_dir > 0 and x >= walk_to) or (walk_dir < 0 and x <= walk_to) then
                x = walk_to
                fact.wx = x
                cancel(walk_timer); walk_timer = nil
                fact.walking = false
                set_activity("idle")
                show_face()
                save_position()
                after(350, function() if activity ~= "walking" then fact.facing = 0 end end)
                return
            end
            fact.wx = x
        end)
    end)
end

local function wander()
    local d = (80 + math.random() * 280) * (math.random() < 0.5 and -1 or 1)
    if x + d < min_x() or x + d > max_x() then d = -d end
    walk(x + d)
end

-- ── Activities ───────────────────────────────────────────────
local zz_timer = nil
local function sleep()
    if activity == "sleeping" then return end
    stop_walking()
    set_activity("sleeping")
    reaction = ""
    fact.dancing = false
    show_face()
    local n = 0
    say("z", nil, true)
    zz_timer = every(1400, function()
        n = (n % 3) + 1
        text.bubble = ({ "z", "z z", "z z Z" })[n]
    end)
end

local function wake(poked)
    if activity ~= "sleeping" then return end
    if zz_timer then cancel(zz_timer); zz_timer = nil end
    fact.bubble_on = false
    set_activity("idle")
    if poked then
        react("surprised", 900)
        set_mood(math.random() < 0.4 and "grumpy" or "sleepy")
    else
        move("stretch")
        react("yawn", 1400)
        set_mood("happy")
        after(1500, function() chat("wake", false) end)
    end
    show_face()
end

local dance_token = 0
local function stop_dancing()
    if activity ~= "dancing" then return end
    set_activity("idle")
    fact.dancing = false
    react("content", 1500)
end

local function dance()
    set_activity("dancing")
    fact.dancing = true
    show_face()
    dance_token = dance_token + 1
    local mine = dance_token
    after(6000 + math.random() * 6000, function() if dance_token == mine then stop_dancing() end end)
end

-- ── Music (MPRIS through the media service) ──────────────────
local music = { playing = false, title = "" }
local function music_on() return cfg.music and music.playing end

local function decode_art(a)
    a = tostring(a or "")
    if a:sub(1, 7) == "file://" then
        return (a:sub(8):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
    end
    return ""
end

pcall(sys.watch, "media", function(m)
    if type(m) ~= "table" then return end
    local was_playing, was_title = music.playing, music.title
    music.playing = m.playing == true
    music.title = tostring(m.title or "")
    fact.m_on = tostring(m.player or "") ~= ""
    fact.m_playing = music.playing
    text.m_title = music.title ~= "" and music.title or "Nothing playing"
    text.m_artist = tostring(m.artist or "")
    local src = ""
    if type(m.players) == "table" then
        for _, p in ipairs(m.players) do if p.chosen then src = tostring(p.name or "") end end
    end
    text.m_src = src
    local art = decode_art(m.art)
    text.m_art = art
    fact.m_art_on = art ~= ""
    text.m_line = (fact.m_on and music.title ~= "")
        and ((music.playing and "♪ " or "❚❚ ") .. music.title .. (tostring(m.artist or "") ~= "" and (" — " .. tostring(m.artist)) or ""))
        or "Nothing playing."

    if not cfg.music then return end
    if music.playing and music.title ~= "" and music.title ~= was_title and activity ~= "sleeping" then
        react("excited", 1400)
        move("hop")
        if cfg.talk ~= "off" then say("♪ " .. music.title, 3500, true) end
    end
    if music.playing ~= was_playing then
        if music.playing then
            if activity ~= "sleeping" then set_mood(math.random() < 0.5 and "happy" or "playful") end
        else
            stop_dancing()
            if mood == "excited" or mood == "playful" then set_mood("happy") end
        end
    end
end)

-- ── Deciding, now and then ───────────────────────────────────
local function can_walk()
    return cfg.wander > 0 and not cfg.locked and not fact.panel and not hovered and not fact.dragged
end

local decide
-- An idle act (sitting, his game, humming) for `ms`, then `done` — unless something ended it first.
local function idle_act(name, ms, done)
    set_activity(name)
    show_face()
    after(ms, function()
        if activity ~= name then return end
        set_activity("idle")
        show_face()
        if done then done() end
    end)
end
-- How his game went: mostly he wins.
local function game_over()
    if math.random() < 0.65 then
        react("giggle", 1600); move("hop")
        chat("won", false)
    else
        react("grumpy", 1400); move("shake")
        chat("lost", false)
    end
end
local function schedule()
    local lively = cfg.motion == "lively"
    after((lively and 3000 or 5000) + math.random() * (lively and 4000 or 6000), decide)
end

function decide()
    if activity == "idle" and fact.ready then
        local a = B.decide({ mood = mood, wander = cfg.wander, can_walk = can_walk(), music = music_on(),
                             still = cfg.motion == "still" }, math.random(), math.random())
        if a == "dance" then dance()
        elseif a == "walk" then wander()
        elseif a == "look" then
            fact.glx = math.random() * 2 - 1
            fact.gly = math.random() * 1.4 - 0.7
            after(900 + math.random() * 1800, function() fact.glx = 0; fact.gly = 0 end)
        elseif a == "yawn" then react("yawn", 1600); move("stretch")
        elseif a == "sit" then idle_act("sitting", 9000 + math.random() * 12000)
        elseif a == "game" then idle_act("gaming", 6000 + math.random() * 6000, game_over)
        elseif a == "hum" then idle_act("humming", 5000 + math.random() * 4000)
        elseif a ~= "rest" then move(a) end
        -- now and then a line of his own (the level is the chance, so it counts as meant)
        if activity == "idle" and math.random() < B.idle_chance(cfg.talk) then chat("idle", true, 2200) end
    end
    schedule()
end

local last_upkeep = os.time()
local function upkeep()
    local t = os.time()
    local dt = t - last_upkeep
    last_upkeep = t
    local hour = tonumber(os.date("%H")) or 12
    local night = hour >= 23 or hour < 6
    energy = B.energy(energy, dt, activity == "sleeping", night)
    fact.energy = energy
    if activity == "sleeping" then
        if energy >= 0.95 and not night then wake(false) end
        return
    end
    local alone_min = (t - last_touch) / 60
    if activity == "idle" and not fact.panel and not hovered and not music_on() then
        if energy < 0.15 or alone_min >= cfg.doze then
            if mood == "sleepy" and t - mood_since > 45 then sleep() else set_mood("sleepy") end
            return
        end
    end
    if t - mood_since > 240 and reaction == "" then
        set_mood(B.drift({ music = music_on(), energy = energy }, math.random()))
    end
end
every(30000, upkeep)

local function touch() last_touch = os.time() end

-- ── His hands: press, click, double-click, drag, hover ────────
local press_x, press_y = 0, 0
local carrying = false
local click_pending = false
local single_token = 0
local calm_token = 0

local function poke()
    touch()
    pokes = recent(pokes, 3)
    pokes[#pokes + 1] = os.time()
    if activity == "sleeping" then wake(true); move("startle"); return end
    if activity == "dancing" then stop_dancing() end
    local r = B.poke(mood, #pokes, math.random())
    if #pokes >= 5 then pokes = {} end
    react(r.face, r.ms)
    move(r.move)
    if r.mood then set_mood(r.mood) end
    if r.say then
        if B.speaks(cfg.talk, true) then say(r.say, 1400, true) end
    elseif math.random() < 0.35 then chat("poke", false, 1200) end
end

local function toggle_panel()
    fact.panel = not fact.panel
    touch()
    if fact.panel then
        stop_walking()
        stop_dancing()
        if activity == "sleeping" then wake(false) end
        react("happy", 900)
    end
end

-- ── Thrown: the drag is sampled, a flick throws him, and he bounces off the edges (brain fly) ──
local samples, sampler = {}, nil
local flight = nil
local function stop_sampling() if sampler then cancel(sampler); sampler = nil end end
local function land_from_flight(hits, hardest)
    if flight then cancel(flight); flight = nil end
    fact.flying = false
    fact.lean = 0
    set_activity("idle")
    play("land")
    if hardest > 1400 or hits >= 4 then react("dizzy", 1800); chat("dizzy", true, 1600)
    else react("giggle", 1100); if math.random() < 0.5 then chat("landed", false, 1300) end end
    save_position()
end
local function throw(vx, vy)
    stop_walking()
    set_activity("flying")
    fact.flying = true
    show_face()
    local st = { x = x, y = y, vx = vx, vy = vy }
    local hits, hardest = 0, 0
    flight = every(16, function()
        st = B.fly(st, 0.016, { x0 = min_x(), x1 = max_x(), y0 = min_y(), y1 = max_y() })
        place(st.x, st.y)
        fact.lean = clamp(st.vx / 1500, -1, 1)
        if st.impact > 500 then
            hits = hits + 1
            hardest = math.max(hardest, st.impact)
            if cfg.motion ~= "still" then play("land") end
        end
        if st.rest then land_from_flight(hits, hardest) end
    end)
end

on("hit_down", function()
    -- caught in the air: the flight ends in the hand
    if flight then cancel(flight); flight = nil; fact.flying = false; set_activity("idle") end
    press_x, press_y = x, y
    carrying = false
    fact.ddx, fact.ddy = 0, 0
end)

local function carry()
    local dx, dy = tonumber(fact.ddx) or 0, tonumber(fact.ddy) or 0
    if not carrying then
        if cfg.locked or math.sqrt(dx * dx + dy * dy) < 6 then return end
        carrying = true
        single_token = single_token + 1
        click_pending = false
        stop_walking()
        touch()
        if activity == "sleeping" then
            if zz_timer then cancel(zz_timer); zz_timer = nil end
            fact.bubble_on = false
            set_mood("grumpy")
        end
        if activity == "dancing" then fact.dancing = false end
        set_activity("dragged")
        fact.dragged = true
        react("surprised", 450)
        samples = {}
        stop_sampling()
        sampler = every(16, function()
            samples[#samples + 1] = { x = x, y = y }
            if #samples > 6 then table.remove(samples, 1) end
        end)
    end
    local nx = clamp(press_x + dx, min_x(), max_x())
    fact.lean = clamp((nx - x) * 0.12, -1, 1)
    calm_token = calm_token + 1
    local mine = calm_token
    after(90, function() if calm_token == mine then fact.lean = 0 end end)
    place(nx, press_y + dy)
end
on("fact:ddx", carry)
on("fact:ddy", carry)

on("hit_up", function()
    if carrying then
        carrying = false
        fact.dragged = false
        fact.lean = 0
        stop_sampling()
        local vx, vy = B.release(samples, 16)
        -- a flick throws him (Settings → BMO: throwing); a gentle let-go just sets him down
        if cfg.throw and not cfg.locked and cfg.place ~= "bar" and math.sqrt(vx * vx + vy * vy) > 350 then
            touch()
            throw(vx, vy)
            return
        end
        set_activity("idle")
        drags = recent(drags, 20)
        drags[#drags + 1] = os.time()
        play("land")
        if #drags >= 4 then set_mood("grumpy"); react("grumpy", 1400)
        else
            react("giggle", 1000)
            if math.random() < 0.4 then set_mood("excited") end
        end
        save_position()
        return
    end
    -- a second click while the first still waits is a double-click
    if click_pending then
        click_pending = false
        single_token = single_token + 1
        toggle_panel()
        return
    end
    click_pending = true
    single_token = single_token + 1
    local mine = single_token
    after(280, function()
        if single_token == mine then click_pending = false; poke() end
    end)
end)

on("hov", function(v)
    hovered = tonumber(v) == 1
    if not hovered or activity == "sleeping" then return end
    touch()
    local t = os.time()
    if t - last_greet > 90 and cfg.motion ~= "still" then
        last_greet = t
        move("wave")
        react("happy", 1200)
    end
end)

-- ── Controls (the panel and the menu) ────────────────────────
-- His colours (companion.variant): brain.luau's palette, handed to the scene as rgb() numbers.
-- "mooi" is made from the shell's palette.json (beside settings.json), watched below.
local SLOTS = { "body", "side", "ink", "glass", "glass_dim", "paper", "pad", "tri", "go", "stop" }
local function shell_colours()
    local p = read("palette.json")
    return type(p) == "table" and p.colours or nil
end
local function paint()
    local shell = shell_colours()
    local pal = B.palette(cfg.variant, shell)
    for _, k in ipairs(SLOTS) do
        local cr, cg, cb = B.rgb(pal[k])
        fact["c_" .. k .. "_r"], fact["c_" .. k .. "_g"], fact["c_" .. k .. "_b"] = cr, cg, cb
    end
    if type(shell) == "table" and shell.primary then
        fact.c_mooi_r, fact.c_mooi_g, fact.c_mooi_b = B.rgb(shell.primary)
    end
    fact.s_variant = index_of_name(B.VARIANTS, cfg.variant) - 1
end

local function sync_settings()
    fact.s_wander = cfg.wander
    fact.s_locked = cfg.locked
    fact.s_size = index_of(SIZES, cfg.size) - 1
    fact.s_motion = (cfg.motion == "still" and 0) or (cfg.motion == "lively" and 2) or 1
    fact.s_music = cfg.music
    fact.s_doze = index_of(DOZES, cfg.doze) - 1
    fact.s_clock = cfg.clock
    fact.above = cfg.above
    fact.on_bar = cfg.place == "bar"
    fact.size = eff_size()
    fact.breathing = cfg.motion == "lively"
    paint()
end

local function go_home()
    stop_walking()
    place(home_x(), home_y())
    play("land")
    state.x, state.y = -1, -1
    save_state()
end

local last_wander = 2
local function hide_for(minutes)
    fact.panel = false
    fact.menu = false
    fact.ready = false
    after(minutes * 60000, function() fact.ready = true end)
end

-- ── Desktop awareness (companion.react; brain.luau react) ────
-- Workspaces and the battery he watches himself. Notifications and the focus timer belong to the
-- bar (only one program may receive notifications), which tells him: `emit tell N`, 1 a
-- notification arrived (only that: never what it says) · 2 a focus block began · 3 it ended ·
-- 4 the break is over · 5 the timer was stopped.
local memory = {}
local function feel(kind, arg)
    local r = B.react(kind, arg, { cfg = cfg, now = os.time(), last = memory, asleep = activity == "sleeping" })
    if not r then return end
    if r.mood then set_mood(r.mood) end
    if r.face then react(r.face, r.ms or 1500) end
    if r.move and activity ~= "dragged" and activity ~= "flying" then move(r.move) end
    if r.line then say(r.line, 2400, r.important) end
    if r.peek then
        fact.glx = math.random() < 0.5 and -1 or 1
        fact.gly = -0.3
        after(1600, function() fact.glx = 0; fact.gly = 0 end)
    end
end
local FOCUS = { [2] = "on", [3] = "done", [4] = "break_done", [5] = "off" }
-- An answer from Claude, as him (the side notch's chat in BMO's voice): said a bubble at a time, each
-- as long as it takes to read.
on("speak", function()
    local words = tostring(text.bmo_line or "")
    local lines, line = {}, ""
    for w in words:gmatch("%S+") do
        if #line > 0 and #line + 1 + #w > 38 then lines[#lines + 1] = line; line = w
        else line = #line > 0 and (line .. " " .. w) or w end
    end
    if line ~= "" then lines[#lines + 1] = line end
    local at = 0
    for i = 1, math.min(#lines, 6) do
        local l = lines[i]
        local ms = 900 + #l * 55
        after(at, function() say(l, ms, true) end)
        at = at + ms + 150
    end
end)

on("tell", function(v)
    local n = math.floor(tonumber(v) or 0)
    if n == 1 then feel("note") elseif FOCUS[n] then feel("focus", FOCUS[n]) end
end)
local space_now = nil
pcall(sys.watch, "workspaces", function(w)
    local a = type(w) == "table" and tonumber(w.active) or nil
    if a and space_now and a ~= space_now then feel("space", a) end
    space_now = a or space_now
end)
-- a window that was not there before: he peeks at it (the first report is only learnt)
local windows_seen = nil
pcall(sys.watch, "window", function(w)
    local list = type(w) == "table" and w.list or nil
    if type(list) ~= "table" then return end
    local now, fresh = {}, false
    for _, it in ipairs(list) do
        local id = it.id
        if id ~= nil then
            now[id] = true
            if windows_seen and not windows_seen[id] then fresh = true end
        end
    end
    if fresh then feel("window") end
    windows_seen = now
end)
pcall(sys.watch, "battery", function(b)
    if type(b) == "table" and b.present then feel("battery", { percent = b.percent, charging = b.charging }) end
end)
local function hour_check() feel("hour", { hour = tonumber(os.date("%H")), day = tonumber(os.date("%j")) }) end
after(8000, hour_check)
every(60000, hour_check)

on("ui", function(v)
    local n = math.floor(tonumber(v) or -1)
    if n >= 1 and n <= 9 then fact.menu = false end
    touch()
    if n == 1 then toggle_panel(); return
    elseif n == 2 then
        if cfg.wander > 0 then last_wander = cfg.wander; cfg.wander = 0 else cfg.wander = last_wander end
    elseif n == 3 then cfg.locked = not cfg.locked
    elseif n == 4 then go_home(); return
    elseif n == 5 then if activity == "sleeping" then wake(false) else sleep() end; return
    elseif n == 6 then hide_for(10); return
    elseif n == 7 then run("pleamar", { "--say", "bmo", "quit" }); return
    -- asking him (D106): the side notch's chat, as BMO; what Claude answers comes back here to be said
    elseif n == 8 then run("pleamar", { "--say", "mooi-notch", "emit nt_ask_bmo" }); say("ask BMO anything!", 2200, true); return
    elseif n == 9 then run("pleamar", { "--say", "mooi-notch", "emit nt_show 0" }); return
    elseif n >= 10 and n <= 14 then fact.tab = ({ "home", "music", "me", "setup", "look" })[n - 9]; return
    elseif n == 20 then pcall(sys.call, "media.previous"); return
    elseif n == 21 then pcall(sys.call, "media.toggle"); return
    elseif n == 22 then pcall(sys.call, "media.next"); return
    elseif n >= 30 and n <= 37 then set_mood(B.MOODS[n - 29]); return
    elseif n >= 40 and n <= 42 then cfg.motion = MOTIONS[n - 39]
    elseif n >= 50 and n <= 53 then cfg.wander = n - 50
    elseif n >= 60 and n <= 63 then
        cfg.size = SIZES[n - 59]
        fact.size = eff_size()
        place(x, y)
    elseif n == 70 or n == 71 then cfg.above = n == 71; cfg.place = "desktop"; sync_settings(); place(x, y)
    elseif n == 72 then cfg.place = "bar"; sync_settings(); place(x, y)
    elseif n == 80 or n == 81 then cfg.music = n == 80; if not cfg.music then stop_dancing() end
    elseif n >= 90 and n <= 93 then cfg.doze = DOZES[n - 89]
    elseif n == 100 or n == 101 then cfg.clock = n == 100
    elseif n >= 130 and n <= 134 then cfg.variant = B.VARIANTS[n - 129]
    elseif n == 110 then run("kitty", {}, nil, { output = false }); return
    elseif n == 111 then run("loginctl", { "lock-session" }); return
    -- for scripts: make him walk, dance or look about now
    elseif n == 120 then wander(); return
    elseif n == 121 then dance(); return
    elseif n == 123 then idle_act("sitting", 12000); return
    elseif n == 124 then idle_act("gaming", 8000, game_over); return
    elseif n == 125 then idle_act("humming", 7000); return
    elseif n == 122 then
        fact.glx = math.random() * 2 - 1
        after(1500, function() fact.glx = 0 end)
        return
    else return end
    sync_settings()
    save()
end)

-- mooi's settings changed (Settings → BMO, or his own panel): read them again
pcall(sys.watch, "files:palette.json", function() if cfg.variant == "mooi" then paint() end end)
pcall(sys.watch, "files:" .. FILE, function()
    cfg = B.settings(companion_of(read(FILE)))
    sync_settings()
    if fact.ready then place(x, y) end
end)

-- ── Up ───────────────────────────────────────────────────────
-- The monitor's logical size, for where he may stand.
run("hyprctl", { "-j", "monitors" }, function(out, code)
    if code == 0 then
        local ok, mons = pcall(json.decode, out or "")
        if ok and type(mons) == "table" then
            local m = mons[1]
            for _, mon in ipairs(mons) do if mon.focused then m = mon end end
            if m and tonumber(m.width) and tonumber(m.scale) then
                sw = math.floor(m.width / m.scale + 0.5)
                sh = math.floor(m.height / m.scale + 0.5)
            end
        end
    end
    sync_settings()
    place(state.x >= 0 and state.x or home_x(), state.y >= 0 and state.y or home_y())
    show_face()
    if not spare then fact.ready = true end
    schedule()
end)
