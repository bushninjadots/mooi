-- BMO's logic: where he is, what he does, how he feels. The scene draws and moves; this decides.
-- brain.luau is the pure part (faces, moods, choices) and is unit-tested.
--
-- From outside: `pleamar --say bmo "emit ui N"` presses a control (codes in on("ui") below;
-- 120 walk, 121 dance, 122 look), and
-- `pleamar --say bmo get mood_t` (or act_t, energy, wx…) reads him.

local B = require("brain")

-- His settings are mooi's (settings.json's `companion` section, Settings → BMO), read through the
-- link bin/mooi keeps in his data folder; where he stands is his own (bmo-state.json).
local FILE = "mooi-settings.json"
local STATE = "bmo-state.json"

-- ── Settings ─────────────────────────────────────────────────
local function read(name)
    local ok, v = pcall(sys.ask, "files.read", name, "json")
    return ok and v or nil
end
local function companion_of(doc) return type(doc) == "table" and doc.companion or nil end
local cfg = B.settings(companion_of(read(FILE)))
local state = read(STATE)
if type(state) ~= "table" then
    -- his place from before the move into mooi's settings (his own settings.json)
    local old = read("settings.json")
    state = { x = type(old) == "table" and tonumber(old.x) or -1, y = type(old) == "table" and tonumber(old.y) or -1 }
end
state.x, state.y = tonumber(state.x) or -1, tonumber(state.y) or -1
local SIZES = { 0.5, 0.7, 0.9, 1.15 }
local DOZES = { 5, 10, 30, 100000 }
local MOTIONS = { "still", "calm", "lively" }

local function index_of(list, v)
    local best, bd = 1, math.huge
    for i, x in ipairs(list) do
        local d = math.abs(x - v)
        if d < bd then best, bd = i, d end
    end
    return best
end

-- His panel's choices go back into mooi's settings, the rest of the file as it is now.
local function save()
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
local function save_state() pcall(sys.call, "files.write", STATE, state) end

-- ── The screen and where he may stand ────────────────────────
local sw, sh = 1920, 1080
local function bw() return 160 * cfg.size end
local function bh() return 196 * cfg.size end
local function min_x() return 40 end
local function max_x() return math.max(min_x(), sw - bw() - 40) end
local function min_y() return 50 end
local function max_y() return math.max(min_y(), sh - bh() - 4) end
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
local say_token = 0
local function say(t, ms)
    text.bubble = t
    fact.bubble_on = true
    say_token = say_token + 1
    local mine = say_token
    if ms then after(ms, function() if say_token == mine and activity ~= "sleeping" then fact.bubble_on = false end end) end
end

-- ── Walking ──────────────────────────────────────────────────
local walk_timer, walk_to, walk_dir = nil, nil, 0
local function stop_walking()
    if walk_timer then cancel(walk_timer); walk_timer = nil end
    if fact.walking then fact.walking = false end
    fact.facing = 0
    if activity == "walking" then activity = "idle"; show_face() end
end

local function save_position()
    state.x, state.y = math.floor(x + 0.5), math.floor(y + 0.5)
    save_state()
end

local function walk(target)
    target = clamp(target, min_x(), max_x())
    if math.abs(target - x) < 16 then return end
    stop_walking()
    activity = "walking"
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
                activity = "idle"
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
    activity = "sleeping"
    reaction = ""
    fact.dancing = false
    show_face()
    local n = 0
    say("z", nil)
    zz_timer = every(1400, function()
        n = (n % 3) + 1
        text.bubble = ({ "z", "z z", "z z Z" })[n]
    end)
end

local function wake(poked)
    if activity ~= "sleeping" then return end
    if zz_timer then cancel(zz_timer); zz_timer = nil end
    fact.bubble_on = false
    activity = "idle"
    if poked then
        react("surprised", 900)
        set_mood(math.random() < 0.4 and "grumpy" or "sleepy")
    else
        move("stretch")
        react("yawn", 1400)
        set_mood("happy")
    end
    show_face()
end

local dance_token = 0
local function stop_dancing()
    if activity ~= "dancing" then return end
    activity = "idle"
    fact.dancing = false
    react("content", 1500)
end

local function dance()
    activity = "dancing"
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
        say("♪ " .. music.title, 3500)
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
        elseif a ~= "rest" then move(a) end
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
    if r.say then say(r.say, 1400) end
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

on("hit_down", function()
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
        activity = "dragged"
        fact.dragged = true
        react("surprised", 450)
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
        activity = "idle"
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
local function sync_settings()
    fact.s_wander = cfg.wander
    fact.s_locked = cfg.locked
    fact.s_size = index_of(SIZES, cfg.size) - 1
    fact.s_motion = (cfg.motion == "still" and 0) or (cfg.motion == "lively" and 2) or 1
    fact.s_music = cfg.music
    fact.s_doze = index_of(DOZES, cfg.doze) - 1
    fact.s_clock = cfg.clock
    fact.above = cfg.above
    fact.size = cfg.size
    fact.breathing = cfg.motion == "lively"
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

on("ui", function(v)
    local n = math.floor(tonumber(v) or -1)
    if n >= 1 and n <= 7 then fact.menu = false end
    touch()
    if n == 1 then toggle_panel(); return
    elseif n == 2 then
        if cfg.wander > 0 then last_wander = cfg.wander; cfg.wander = 0 else cfg.wander = last_wander end
    elseif n == 3 then cfg.locked = not cfg.locked
    elseif n == 4 then go_home(); return
    elseif n == 5 then if activity == "sleeping" then wake(false) else sleep() end; return
    elseif n == 6 then hide_for(10); return
    elseif n == 7 then run("pleamar", { "--say", "bmo", "quit" }); return
    elseif n >= 10 and n <= 13 then fact.tab = ({ "home", "music", "me", "setup" })[n - 9]; return
    elseif n == 20 then pcall(sys.call, "media.previous"); return
    elseif n == 21 then pcall(sys.call, "media.toggle"); return
    elseif n == 22 then pcall(sys.call, "media.next"); return
    elseif n >= 30 and n <= 37 then set_mood(B.MOODS[n - 29]); return
    elseif n >= 40 and n <= 42 then cfg.motion = MOTIONS[n - 39]
    elseif n >= 50 and n <= 53 then cfg.wander = n - 50
    elseif n >= 60 and n <= 62 then
        cfg.size = SIZES[n - 59]
        fact.size = cfg.size
        place(x, y)
    elseif n == 70 or n == 71 then cfg.above = n == 71
    elseif n == 80 or n == 81 then cfg.music = n == 80; if not cfg.music then stop_dancing() end
    elseif n >= 90 and n <= 93 then cfg.doze = DOZES[n - 89]
    elseif n == 100 or n == 101 then cfg.clock = n == 100
    elseif n == 110 then run("kitty", {}, nil, { output = false }); return
    elseif n == 111 then run("loginctl", { "lock-session" }); return
    -- for scripts: make him walk, dance or look about now
    elseif n == 120 then wander(); return
    elseif n == 121 then dance(); return
    elseif n == 122 then
        fact.glx = math.random() * 2 - 1
        after(1500, function() fact.glx = 0 end)
        return
    else return end
    sync_settings()
    save()
end)

-- mooi's settings changed (Settings → BMO, or his own panel): read them again
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
    fact.ready = true
    schedule()
end)
