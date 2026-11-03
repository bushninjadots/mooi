-- BMO's logic: where he is, what he does, how he feels. The scene draws and moves; this decides.
-- brain.luau is the pure part (faces, moods, choices) and is unit-tested.
--
-- From outside: `pleamar --say bmo "emit ui N"` presses a control (codes in on("ui") below;
-- 120 walk, 121 dance, 122 look, 123 sit, 124 his game, 125 hum, 126 peek, 127 tantrum), `emit tell N` tells him what
-- the bar saw (Desktop awareness, below), and
-- `pleamar --say bmo get mood_t` (or act_t, energy, wx…) reads him.

local B = require("brain")
local W = require("wire")     -- what crosses to the side notch, and back
local G = require("geom")     -- which monitor is his, and where he may stand on it

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
-- the monitor he was on: a restart puts him back on it rather than on whichever has the focus
state.mon = type(state.mon) == "string" and state.mon or ""
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
-- A second program called bmo gets `bmo-<pid>` for a name, and the bar's `--say bmo` cannot see
-- it, so two would live on. Each one marks itself and asks whoever answers to "bmo" for its mark;
-- one that is not the answer is the second, finds its own name by its mark among the bmo-<pid>
-- sockets, and quits. Until then it draws nothing and saves nothing.
--
-- Being the second is checked again while it lasts (found 2026-10-29: BMO gone from the desktop,
-- still running, `ready` false and saving nothing, for two hours). The name is asked for again
-- and again: the moment this one *is* what answers to "bmo" — the other ended as it was being
-- replaced, which is what a refresh does — it takes over instead of staying invisible for good.
local spare = false
local spare_since = 0        -- when this one last concluded it was the second one
local claim -- below, once show_face and save_state exist
local come_alive -- below, once show_face and save_state exist
-- the time, and where this process keeps a fresh table (each process its own place)
local mark = (os.time() % 100000) * 10000 + (tonumber(tostring({}):match("(%x+)$") or "0", 16) or 0) % 10000
fact.token = mark
-- for the shell: which BMO this is (a new one has a new boot), and that its logic is still going
-- (upkeep moves the beat, every 30 s; a logic that has stopped cannot)
fact.beat = 1
local function answer(cb) -- the token of whoever answers to "bmo" (nil: nobody)
    run("pleamar", { "--say", "bmo", "get token" }, function(out, code)
        cb(code == 0 and tonumber((out or ""):match("^%s*([%d.]+)%s*$")) or nil)
    end)
end
-- A spare ends itself: the socket that answers with its mark is its own (it is bmo-<pid>, and
-- it may not know which pid). Asked by its own name, it quits.
local function end_spare()
    local dir = tostring(sys.ask("env", "XDG_RUNTIME_DIR") or "") .. "/pleamar"
    run("ls", { dir }, function(list)
        for pid in tostring(list or ""):gmatch("bmo%-(%d+)%.sock") do
            local name = "bmo-" .. pid
            run("pleamar", { "--say", name, "get token" }, function(t)
                if tonumber((t or ""):match("[%d.]+")) == mark then run("pleamar", { "--say", name, "quit" }) end
            end)
        end
    end)
end
local function only_one()
    answer(function(theirs)
        -- only a clear answer that is not his own makes him the spare (no answer: he is not).
        -- A lone BMO has to say so where the scene reads it: `ready` (found 2026-10-30: the only
        -- BMO alive, beat climbing, ready false, nothing drawn — the scene defaulted it and only
        -- the spare's claim ever lifted it).
        if not theirs or theirs == mark then
            if not fact.ready then come_alive() end
            return
        end
        spare = true
        spare_since = os.time()
        fact.ready = false
        end_spare()
        after(2000, claim)
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
local end_stride   -- the walking section's: an activity that is not walking ends the stride
-- What he is doing; the idle acts (sitting, his game, humming) are drawn from it, so whatever
-- interrupts one (a walk, a hand, sleep) ends it too.
local function set_activity(a)
    -- one owner: whatever he starts doing instead of walking stops the stride (a sit, a dance, sleep,
    -- a hand, a throw), so no timer of a walk that is over can keep moving him
    if a ~= "walking" and activity == "walking" and end_stride then end_stride() end
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

-- Come alive: stand where he was, remember it, and show his face. Every path that makes him ready
-- ends here, so a BMO that has just started answers for his mood at once instead of only after the
-- first thing that changes it (found 2026-10-31: a cold start answered `get ready` true and
-- `get mood_t` empty for minutes — the lone-BMO path lifted `ready` and nothing wrote his texts).
function come_alive()
    fact.ready = true
    place(state.x >= 0 and state.x or home_x(), state.y >= 0 and state.y or home_y())
    save_state()
    show_face()
end

-- The other one ended while this one was its spare (a refresh does exactly that: the new BMO is
-- up before the old is gone). We are what answers to "bmo" now, so take the name and come back;
-- until we are, ask again. A spare that never is ends itself on its own name, above.
local misses = 0
claim = function()
    if not spare then return end
    answer(function(theirs)
        if not spare then return end
        if theirs ~= mark then
            -- still someone else's name, or nobody's: the second case is one we cannot fix from
            -- here (we answer to bmo-<pid>), so ask our own name to quit and let the shell start
            -- a BMO that can take it
            -- A spare for this long is not a refresh race (a refresh replaces him in a second or
            -- two, and the shell starts him again 1.2 s after letting the old one go): show him
            -- rather than leave a live BMO invisible for as long as the other one answers, which is
            -- the state the user found on 2026-10-30. Four seconds, not fifteen: turning him off and
            -- on again left a visible BMO hidden for a quarter of a minute.
            if spare_since > 0 and os.time() - spare_since > 4 then
                spare = false
                come_alive()
                return
            end
            if theirs then misses = 0
            elseif (misses + 1) >= 4 then
                -- Nobody answers to "bmo" at all, and `end_spare` can only end a bmo-<pid>: this one
                -- may already hold the name behind a socket that answers nothing. Show him rather
                -- than leave a running BMO invisible (2026-10-30).
                spare = false
                come_alive()
                return
            else misses = misses + 1 end
            after(1500, claim)
            return
        end
        spare = false
        come_alive()
    end)
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
-- One walk at a time, and only the newest may move him. `walk_token` is what makes that true: every
-- walk takes the next number, and both halves of it — the turn (a delay) and the stride (a timer)
-- check it before touching anything. A walk that is over (stopped, replaced, or interrupted by
-- sitting, sleeping, a hand, a throw) cannot land on the next one's destination, facing or activity,
-- even when its delayed turn was already queued (found 2026-10-30: a second wander within 240 ms
-- left two strides running over the same x, and stopping him left a stale turn to start one).
local walk_timer, walk_to, walk_dir, walk_token = nil, nil, 0, 0
-- The stride alone: it ends, and no callback of it may go on, without touching what he is doing
-- (set_activity calls this whenever the walking gives way to something else).
function end_stride()
    walk_token = walk_token + 1            -- every callback of a walk that is over is stale now
    if walk_timer then cancel(walk_timer); walk_timer = nil end
    walk_to, walk_dir = nil, 0
    if fact.walking then fact.walking = false end
end
local function stop_walking()
    end_stride()
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
    walk_token = walk_token + 1
    local mine = walk_token
    set_activity("walking")
    walk_to, walk_dir = target, target > x and 1 or -1
    fact.facing = walk_dir
    -- turn first, then stride
    after(240, function()
        if walk_token ~= mine then return end           -- a newer walk, or none: this one is over
        if activity ~= "walking" then stop_walking(); return end
        fact.walking = true
        local speed = 60 * cfg.size
        local timer
        timer = every(33, function()
            if walk_token ~= mine or activity ~= "walking" then   -- stopped, replaced, or sat down
                cancel(timer)
                if walk_timer == timer then walk_timer = nil end
                if fact.walking then fact.walking = false end
                return
            end
            x = x + walk_dir * speed * 0.033
            if (walk_dir > 0 and x >= walk_to) or (walk_dir < 0 and x <= walk_to) then
                x = walk_to
                fact.wx = x
                cancel(timer)
                if walk_timer == timer then walk_timer = nil end
                fact.walking = false
                set_activity("idle")
                show_face()
                save_position()
                local settled = walk_token
                after(350, function()
                    if walk_token ~= settled then return end
                    if activity ~= "walking" then fact.facing = 0 end
                end)
                return
            end
            fact.wx = x
        end)
        walk_timer = timer
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
    if a:sub(1, 1) == "/" then return a end   -- pleamar 0.7 hands over the path itself
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
-- Peeking (D109): he lives under the windows, so a window hides him — he goes to one's edge on the
-- workspace you are on, tucked behind it, leans out to look, and goes back where he was.
local peek_token = 0
-- His monitor, and where it is laid out (measure, below). Declared here, before `peek` reads
-- them: declared after it, `peek` saw unset globals and threw on its first sum.
local mon, mon_id, mon_x, mon_y = nil, nil, 0, 0
function peek()
    run("hyprctl", { "-j", "clients" }, function(out, code)
        if code ~= 0 then return end
        local ok, list = pcall(json.decode, out or "")
        if not ok or type(list) ~= "table" then return end
        run("hyprctl", { "-j", "activeworkspace" }, function(wo)
            local okw, w = pcall(json.decode, wo or "")
            local ws = okw and type(w) == "table" and tonumber(w.id) or nil
            local wins = {}
            for _, c in ipairs(list) do
                -- only the windows on his monitor: he cannot peek from behind one on another screen
                if (mon_id == nil or tonumber(c.monitor) == mon_id)
                   and type(c.workspace) == "table" and tonumber(c.workspace.id) == ws and c.mapped ~= false and (tonumber(c.fullscreen) or 0) == 0
                   and type(c.at) == "table" and type(c.size) == "table" and c.size[1] > bw() * 1.5 and c.size[2] > bh() then
                    wins[#wins + 1] = c
                end
            end
            if #wins == 0 or activity ~= "idle" or not can_walk() then return end
            local c = wins[math.random(1, #wins)]
            -- hyprctl's coordinates are the desktop's; his are his monitor's, so the window is moved
            -- to where it is on his screen (mon_x, mon_y — bmo.luau's measure)
            local cx, cy = (tonumber(c.at[1]) or 0) - mon_x, (tonumber(c.at[2]) or 0) - mon_y
            local cw, ch = tonumber(c.size[1]) or 0, tonumber(c.size[2]) or 0
            local left = math.random() < 0.5
            local edge = left and cx or (cx + cw)
            local behind = left and (edge + 6) or (edge - bw() - 6)         -- tucked out of sight
            local out_x = left and (edge - bw() * 0.55) or (edge - bw() * 0.45)   -- leaning out of it
            local gy = cy + ch - bh() - 2
            if gy < min_y() or gy > max_y() then gy = clamp(gy, min_y(), max_y()) end
            local home_x, home_y = x, y
            stop_walking()
            set_activity("peeking")
            peek_token = peek_token + 1
            local mine = peek_token
            show_face()
            place(behind, gy)
            fact.facing = left and -1 or 1
            after(500, function()
                if peek_token ~= mine or activity ~= "peeking" then return end
                place(out_x, gy)
                fact.glx = left and -0.8 or 0.8
                if math.random() < 0.5 then say(({ "peekaboo!", "…hello?", "BMO sees you!", "hehehe" })[math.random(1, 4)], 1500, false) end
            end)
            after(3200, function()
                if peek_token ~= mine or activity ~= "peeking" then return end
                place(behind, gy)
                fact.glx = 0
            end)
            after(3900, function()
                if peek_token ~= mine or activity ~= "peeking" then return end
                place(home_x, home_y)
                fact.facing = 0
                set_activity("idle")
                show_face()
            end)
        end)
    end)
end
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
        elseif a == "walk" then if math.random() < 0.25 then peek() else wander() end
        elseif a == "look" then
            fact.glx = math.random() * 2 - 1
            fact.gly = math.random() * 1.4 - 0.7
            after(900 + math.random() * 1800, function() fact.glx = 0; fact.gly = 0 end)
        elseif a == "yawn" then react("yawn", 1600); move("stretch")
        elseif a == "sit" then idle_act("sitting", 9000 + math.random() * 12000)
        elseif a == "game" then
            idle_act("gaming", 6000 + math.random() * 6000, game_over)
            -- pop-ups on his screen while he plays
            local NOTES = { "1UP!", "HI-SCORE!", "LEVEL UP", "COMBO x3", "BOSS!", "+100", "PERFECT", "BONUS ★" }
            local function note()
                if activity ~= "gaming" then fact.game_note_on = false; return end
                text.game_note = NOTES[math.random(1, #NOTES)]
                fact.game_note_on = true
                after(1300, function() fact.game_note_on = false end)
                after(2200 + math.random() * 1600, note)
            end
            after(1200, note)
        elseif a == "hum" then idle_act("humming", 5000 + math.random() * 4000)
        elseif a ~= "rest" then move(a) end
        -- now and then a line of his own (the level is the chance, so it counts as meant)
        if activity == "idle" and math.random() < B.idle_chance(cfg.talk) then chat("idle", true, 2200) end
    end
    schedule()
end

local last_upkeep = os.time()
-- Until when he was asked to hide (his panel's "hide for 10 minutes"). A deadline, not a timer:
-- a refresh drops pending timers, and this way the next upkeep brings him back.
local hidden_until = 0
local function upkeep()
    local t = os.time()
    local dt = t - last_upkeep
    last_upkeep = t
    fact.beat = fact.beat + 1               -- the shell's sign that this logic is still going
    -- `ready` is the scene's drawing gate. Only a spare and a hide may leave it false, and nothing
    -- else may leave him running and invisible (found 2026-10-30: beat climbing, ready false,
    -- nothing drawn). It is only ever lifted here, never lowered.
    if not spare and not fact.ready and t >= hidden_until then fact.ready = true end
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

-- A tantrum (D109): poked four times in three seconds he has had enough — he stamps and shakes, red in
-- the face, steam out of his head, and stays grumpy a while after.
local tantrum_token = 0
local function tantrum()
    stop_walking()
    if activity == "dancing" then stop_dancing() end
    set_activity("tantrum")
    fact.tantrum = true
    tantrum_token = tantrum_token + 1
    local mine = tantrum_token
    react("angry", 2900)
    move("stomp")
    after(950, function() if tantrum_token == mine then move("stomp") end end)
    say(({ "GRRR! BMO IS SO MAD!", "STOP POKING BMO!", "BMO IS NOT A BUTTON! well… BMO IS. BUT STILL!", "HMPH!!" })[math.random(1, 4)], 2400, true)
    after(2900, function()
        if tantrum_token ~= mine then return end
        fact.tantrum = false
        set_activity("idle")
        set_mood("grumpy")
        show_face()
    end)
end

local function poke()
    touch()
    pokes = recent(pokes, 3)
    pokes[#pokes + 1] = os.time()
    if activity == "sleeping" then wake(true); move("startle"); return end
    if activity == "tantrum" then return end
    if #pokes >= 4 and cfg.motion ~= "still" then pokes = {}; tantrum(); return end
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

-- His breath (lively motion): a breath in, held half a second, then out; every 3.4–4.2 s while
-- `breathing`. Between breaths nothing of him moves, so his surface sends no frames (D131).
local breath_timer = nil
local function breathe()
    if fact.breathing and not breath_timer then
        local function one()
            if not fact.breathing then return end
            fact.inhale = true
            after(560, function() fact.inhale = false end)
            breath_timer = after(3400 + math.random(0, 800), one)
        end
        breath_timer = after(1200, one)
    elseif not fact.breathing and breath_timer then
        cancel(breath_timer); breath_timer = nil
        fact.inhale = false
    end
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
    breathe()
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
    hidden_until = os.time() + minutes * 60   -- upkeep lifts it again
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
-- His chat (D109, the panel's CHAT tab): what you say goes to the side notch, which asks Claude in his
-- voice and sends the answer back here (speak), to be said and kept in the panel.
local talk = {}
local function show_talk(thinking)
    local rows = {}
    for _, t in ipairs(talk) do
        local line, first = "", true
        for w in t.text:gmatch("%S+") do
            if #line > 0 and #line + 1 + #w > 32 then rows[#rows + 1] = { who = first and t.who or 3, t = line }; first = false; line = w
            else line = #line > 0 and (line .. " " .. w) or w end
        end
        if line ~= "" then rows[#rows + 1] = { who = first and t.who or 3, t = line } end
    end
    if thinking then rows[#rows + 1] = { who = 2, t = "hmm… BMO is thinking…" } end
    while #rows > 9 do table.remove(rows, 1) end
    -- a line that goes on from one above keeps its speaker's look but not the "BMO›"
    for _, r in ipairs(rows) do if r.who == 3 then r.who = 1 end end
    model.bc = rows
    fact.bc_empty = #talk == 0 and not thinking
end
on("bmo_ask", function()
    local q = tostring(text.bmo_q or ""):gsub("^%s+", ""):gsub("%s+$", "")
    text.bmo_q = ""
    if q == "" then return end
    talk[#talk + 1] = { who = 0, text = q }
    while #talk > 12 do table.remove(talk, 1) end
    fact.bc_busy = true
    show_talk(true)
    react("curious", 1800)
    run("pleamar", { "--say", "mooi-notch", W.ask(q), "emit nt_bmo_q" }, function(_, code)
        if code ~= 0 then
            fact.bc_busy = false
            talk[#talk + 1] = { who = 1, text = "BMO can't reach Claude… is the side notch on? (Settings → Control Nexus)" }
            show_talk(false)
        end
    end)
end)

on("speak", function()
    local words = W.said(text)          -- one token on the wire (wire.luau), whatever he is saying
    if fact.bc_busy or fact.tab == "chat" then
        fact.bc_busy = false
        talk[#talk + 1] = { who = 1, text = words }
        show_talk(false)
    end
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
    elseif n == 7 then
        -- Quit BMO: off in mooi's settings as well (Settings → BMO), so the shell does not start
        -- him again — a BMO that ended only for this would be back a second later
        local doc = read(FILE)
        if type(doc) == "table" then
            local c = type(doc.companion) == "table" and doc.companion or {}
            c.bmo = false
            doc.companion = c
            pcall(sys.call, "files.write", FILE, doc)
        end
        run("pleamar", { "--say", "bmo", "quit" }); return
    -- asking him (D106): the side notch's chat, as BMO; what Claude answers comes back here to be said
    elseif n == 8 then
        if not fact.panel then toggle_panel() end
        fact.tab = "chat"
        say("talk to BMO!", 1800, true)
        return
    elseif n == 9 then run("pleamar", { "--say", "mooi-notch", "emit nt_show 0" }); return
    elseif n >= 10 and n <= 15 then fact.tab = ({ "home", "music", "me", "setup", "look", "chat" })[n - 9]; return
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
    elseif n == 126 then peek(); return
    elseif n == 127 then tantrum(); return
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

-- ── His monitor ──────────────────────────────────────────────
-- Where he may stand, in the logical pixels of the monitor he is on, and which monitor that is:
-- bmo-state.json keeps its name, so a restart puts him back on it. The scene says when its own
-- surface changes size — a mode, a scale, a monitor plugged in or taken away — and the same measure
-- runs then, and now and then after it, so a resolution change or a monitor that went away never
-- leaves him walking off an edge that is no longer there, or peeking at a window that is not on his
-- screen (found 2026-10-30: the startup's geometry was all he ever had).
-- (his monitor and where it is laid out: declared above `peek`, which reads them)
local surf_w, surf_h = nil, nil                       -- what the scene last said its surface measures
local function measure(done)
    run("hyprctl", { "-j", "monitors" }, function(out, code)
        local ok, list = pcall(json.decode, out or "")
        local mons = ok and G.monitors(list) or {}
        local pick = G.choose(mons, state.mon, surf_w, surf_h)
        if pick then
            local nx, ny = G.fit(mon, pick, x, y, fact.ready)
            mon, mon_id, mon_x, mon_y = pick, pick.id, pick.x, pick.y
            sw, sh = pick.w, pick.h
            place(nx, ny)                             -- and clamped to the monitor he is on now
            if state.mon ~= pick.name then state.mon = pick.name; save_state() end
        end
        if done then done() end
    end)
end
on("screen_w", function(v)
    surf_w = tonumber(v) or surf_w
    measure()
end)
on("screen_h", function(v)
    surf_h = tonumber(v) or surf_h
    measure()
end)
every(30000, function() measure() end)
measure(function()
    sync_settings()
    place(state.x >= 0 and state.x or home_x(), state.y >= 0 and state.y or home_y())
    show_face()
    if not spare then fact.ready = true end
    schedule()
end)
