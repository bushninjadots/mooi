-- BMO's personality, pure: no timers, no facts, no system. bmo.luau owns the state and the
-- clock and asks this what a moment means. companion/bmo/test.lua runs it under Lua 5.4.
--
--   mood      slow: changes on events, or drifts after a few minutes
--   activity  what he is doing: idle · walking · dancing · sleeping · dragged
--   reaction  a short-lived expression on top of both

local M = {}

M.MOODS = { "happy", "curious", "sleepy", "excited", "surprised", "playful", "focused", "grumpy" }

-- Every expression is one row of numbers the face glides between, so a new one is a line here
-- and not a new drawing.        eye w  eye h  squint L/R  lid   brow   brow on  mouth curve/open/width  tongue  blush
M.FACES = {
    happy     = { ew = 8,  eh = 14, sql = 0,   sqr = 0, lid = 0,    brow = 0,   bron = 0, mc = 0.7,  mo = 0.2,  mw = 24, tg = 0, bl = 0 },
    excited   = { ew = 9,  eh = 15, sql = 1,   sqr = 1, lid = 0,    brow = 0,   bron = 0, mc = 1.0,  mo = 0.8,  mw = 26, tg = 0, bl = 0.7 },
    curious   = { ew = 10, eh = 17, sql = 0,   sqr = 0, lid = 0,    brow = 10,  bron = 1, mc = 0,    mo = 0.35, mw = 11, tg = 0, bl = 0 },
    surprised = { ew = 11, eh = 19, sql = 0,   sqr = 0, lid = 0,    brow = 0,   bron = 0, mc = 0,    mo = 1,    mw = 13, tg = 0, bl = 0 },
    sleepy    = { ew = 8,  eh = 14, sql = 0,   sqr = 0, lid = 0.65, brow = 0,   bron = 0, mc = 0.15, mo = 0,    mw = 14, tg = 0, bl = 0 },
    asleep    = { ew = 8,  eh = 14, sql = 0,   sqr = 0, lid = 1,    brow = 0,   bron = 0, mc = 0,    mo = 0.18, mw = 8,  tg = 0, bl = 0 },
    playful   = { ew = 8,  eh = 14, sql = 0,   sqr = 1, lid = 0,    brow = 0,   bron = 0, mc = 0.85, mo = 0.45, mw = 22, tg = 1, bl = 0.4 },
    focused   = { ew = 7,  eh = 10, sql = 0,   sqr = 0, lid = 0.15, brow = 0,   bron = 1, mc = 0,    mo = 0,    mw = 14, tg = 0, bl = 0 },
    grumpy    = { ew = 8,  eh = 11, sql = 0,   sqr = 0, lid = 0.2,  brow = -18, bron = 1, mc = -0.6, mo = 0,    mw = 18, tg = 0, bl = 0 },
    sad       = { ew = 8,  eh = 13, sql = 0,   sqr = 0, lid = 0,    brow = 14,  bron = 1, mc = -0.8, mo = 0,    mw = 20, tg = 0, bl = 0 },
    giggle    = { ew = 8,  eh = 14, sql = 1,   sqr = 1, lid = 0,    brow = 0,   bron = 0, mc = 1.0,  mo = 0.55, mw = 22, tg = 0, bl = 1 },
    singing   = { ew = 8,  eh = 14, sql = 1,   sqr = 1, lid = 0,    brow = 0,   bron = 0, mc = 0.5,  mo = 0.5,  mw = 16, tg = 0, bl = 0.3 },
    yawn      = { ew = 8,  eh = 14, sql = 1,   sqr = 1, lid = 0,    brow = 0,   bron = 0, mc = 0,    mo = 1,    mw = 16, tg = 0, bl = 0 },
    content   = { ew = 8,  eh = 14, sql = 1,   sqr = 1, lid = 0,    brow = 0,   bron = 0, mc = 0.6,  mo = 0,    mw = 18, tg = 0, bl = 0.3 },
}

function M.is_mood(m)
    for _, v in ipairs(M.MOODS) do if v == m then return true end end
    return false
end

-- What the face shows: a reaction wins, then what he is doing, then how he feels.
function M.expression(s)
    if s.reaction and s.reaction ~= "" then return s.reaction end
    if s.activity == "sleeping" then return "asleep" end
    if s.activity == "dancing" then return "singing" end
    if s.activity == "dragged" then return "excited" end
    return s.mood
end

-- A weighted choice; `r` is a number in [0, 1).
function M.pick(weights, r)
    local keys, total = {}, 0
    for k, w in pairs(weights) do
        if w > 0 then keys[#keys + 1] = k; total = total + w end
    end
    if total <= 0 then return nil end
    table.sort(keys) -- pairs() has no order; the same r must give the same answer
    local x = r * total
    for _, k in ipairs(keys) do
        x = x - weights[k]
        if x < 0 then return k end
    end
    return keys[#keys]
end

-- An idle moment: what to do with it. `s` = { mood, wander (0 off · 1 rare · 2 some · 3 often),
-- can_walk, music, still }. Most moments are "rest": calm is the default.
function M.decide(s, r1, r2)
    if s.still then return "rest" end
    if s.music and r1 < 0.3 then return "dance" end
    local walk = s.can_walk and ({ 0, 0.6, 1.6, 3.2 })[(s.wander or 0) + 1] or 0
    local w = { rest = 6, look = 3, walk = walk, hop = 0.4, stretch = 0.25, yawn = 0.1, wiggle = 0.15, nod = 0.2 }
    local m = s.mood
    if m == "playful" then w.hop = w.hop * 3; w.wiggle = w.wiggle * 8; w.walk = w.walk * 1.5
    elseif m == "excited" then w.hop = w.hop * 4; w.walk = w.walk * 1.8; w.rest = w.rest * 0.5
    elseif m == "curious" then w.look = w.look * 2.5; w.walk = w.walk * 1.3
    elseif m == "sleepy" then w.walk = w.walk * 0.2; w.yawn = 2; w.stretch = w.stretch * 2; w.hop = 0
    elseif m == "focused" then w.walk = w.walk * 0.3; w.look = w.look * 0.5; w.rest = w.rest * 1.5
    elseif m == "grumpy" then w.walk = w.walk * 0.6; w.hop = 0; w.wiggle = 0; w.nod = 0 end
    return M.pick(w, r2) or "rest"
end

-- A mood to drift to after a few minutes of the same one.
function M.drift(s, r)
    local w
    if s.music then w = { happy = 3, playful = 3, excited = 1.5 }
    else
        w = { happy = 4, curious = 3, playful = 2, focused = 2, grumpy = 0.3, excited = 0.5,
              sleepy = (s.energy or 1) < 0.4 and 3 or 0.3 }
    end
    return M.pick(w, r) or "happy"
end

-- A click, by mood and by how many came in the last three seconds (`n`, this one included).
-- Returns { face, ms, move, mood?, say? }.
function M.poke(mood, n, r)
    if n >= 5 then return { face = "grumpy", ms = 1800, move = "shake", mood = "grumpy", say = "hey!" } end
    if mood == "grumpy" then
        return { face = "grumpy", ms = 1100, move = "shake", mood = r < 0.35 and "happy" or nil }
    elseif mood == "sleepy" then return { face = "sleepy", ms = 1100, move = "nod" }
    elseif mood == "focused" then return { face = "content", ms = 1100, move = "nod" }
    elseif mood == "curious" then return { face = "surprised", ms = 900, move = "hop" }
    end
    return { face = "giggle", ms = 1100, move = n >= 3 and "big_hop" or "hop", mood = n >= 3 and "excited" or nil }
end

-- Energy over `dt` seconds: it drains in about two hours awake (one after 23:00) and fills in
-- ten minutes asleep.
function M.energy(e, dt, sleeping, night)
    if sleeping then return math.min(1, e + dt / 600) end
    return math.max(0, e - dt / (night and 3600 or 7200))
end

-- Settings as they are kept, whatever the file holds.
M.DEFAULTS = { wander = 2, locked = false, x = -1, y = -1, size = 0.9, motion = "calm", music = true,
               above = false, doze = 10, clock = true }

function M.settings(t)
    t = type(t) == "table" and t or {}
    local out = {}
    local function num(v, lo, hi, d)
        v = tonumber(v)
        if not v or v ~= v then return d end
        return math.max(lo, math.min(hi, v))
    end
    out.wander = math.floor(num(t.wander, 0, 3, M.DEFAULTS.wander))
    out.locked = t.locked == true
    out.x = num(t.x, -1, 100000, -1)
    out.y = num(t.y, -1, 100000, -1)
    out.size = num(t.size, 0.5, 1.6, M.DEFAULTS.size)
    out.motion = (t.motion == "still" or t.motion == "lively") and t.motion or "calm"
    out.music = t.music ~= false
    out.above = t.above == true
    out.doze = math.floor(num(t.doze, 1, 100000, M.DEFAULTS.doze))
    out.clock = t.clock ~= false
    return out
end

return M
