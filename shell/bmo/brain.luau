-- BMO's personality, pure: no timers, no facts, no system. bmo.luau owns the state and the
-- clock and asks this what a moment means. shell/bmo/test.lua runs it under Lua 5.4.
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
    -- after a hard landing: screwed-up eyes, a wobbly little o
    dizzy     = { ew = 9,  eh = 7,  sql = 1,   sqr = 1, lid = 0.3,  brow = -8,  bron = 1, mc = -0.2, mo = 0.6,  mw = 12, tg = 0.3, bl = 0 },
    -- flying: eyes wide, mouth open in delight
    whee      = { ew = 10, eh = 18, sql = 0,   sqr = 0, lid = 0,    brow = 6,   bron = 0, mc = 0.9,  mo = 1,    mw = 20, tg = 0, bl = 0.5 },
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
    if s.activity == "flying" then return "whee" end
    if s.activity == "humming" then return "singing" end
    if s.activity == "gaming" then return "focused" end
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
    -- sit down a while, play the little game on his own screen, hum a tune
    local w = { rest = 6, look = 3, walk = walk, hop = 0.4, stretch = 0.25, yawn = 0.1, wiggle = 0.15, nod = 0.2,
                sit = 0.45, game = 0.3, hum = 0.3 }
    local m = s.mood
    if m == "playful" then w.hop = w.hop * 3; w.wiggle = w.wiggle * 8; w.walk = w.walk * 1.5; w.game = w.game * 3
    elseif m == "excited" then w.hop = w.hop * 4; w.walk = w.walk * 1.8; w.rest = w.rest * 0.5; w.sit = w.sit * 0.3
    elseif m == "curious" then w.look = w.look * 2.5; w.walk = w.walk * 1.3
    elseif m == "sleepy" then w.walk = w.walk * 0.2; w.yawn = 2; w.stretch = w.stretch * 2; w.hop = 0; w.sit = w.sit * 4
    elseif m == "focused" then w.walk = w.walk * 0.3; w.look = w.look * 0.5; w.rest = w.rest * 1.5; w.game = w.game * 2
    elseif m == "grumpy" then w.walk = w.walk * 0.6; w.hop = 0; w.wiggle = 0; w.nod = 0; w.hum = 0
    elseif m == "happy" then w.hum = w.hum * 1.6 end
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

-- Settings as they are kept, whatever the file holds: mooi's `companion` section (settings.json,
-- Settings → BMO). His place on screen and his energy are not settings: bmo-state.json.
M.SIZES = { tiny = 0.5, small = 0.7, medium = 0.9, large = 1.15 }
M.SIZE_ORDER = { "tiny", "small", "medium", "large" }
M.VARIANTS = { "classic", "night", "pastel", "gameboy", "mooi" }
M.TALK = { "off", "rare", "chatty" }
M.REACTIONS = { "notes", "spaces", "battery", "focus", "time" }
M.DEFAULTS = { wander = 2, locked = false, size = 0.9, motion = "calm", music = true, above = false, doze = 10,
               clock = true, place = "desktop", variant = "classic", throw = true, talk = "rare" }

local function one_of(list, v, d)
    for _, x in ipairs(list) do if x == v then return v end end
    return d
end
-- A size's name, from its scale (the nearest).
function M.size_name(v)
    local best, bd = "medium", math.huge
    for name, s in pairs(M.SIZES) do
        local d = math.abs(s - (tonumber(v) or 0.9))
        if d < bd then best, bd = name, d end
    end
    return best
end

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
    out.size = M.SIZES[t.size] or num(t.size, 0.4, 1.6, M.DEFAULTS.size)
    out.motion = (t.motion == "still" or t.motion == "lively") and t.motion or "calm"
    out.music = t.music ~= false
    out.above = t.above == true
    out.doze = math.floor(num(t.doze, 1, 100000, M.DEFAULTS.doze))
    out.clock = t.clock ~= false
    out.place = t.place == "bar" and "bar" or "desktop"
    out.variant = one_of(M.VARIANTS, t.variant, "classic")
    out.throw = t.throw ~= false
    out.talk = one_of(M.TALK, t.talk, "rare")
    local r = type(t.react) == "table" and t.react or {}
    out.react = {}
    for _, k in ipairs(M.REACTIONS) do out.react[k] = r[k] ~= false end
    return out
end


-- ── Desktop awareness (companion.react) ──────────────────────
-- What happens around him and how he takes it: { face, ms, move, line, mood } or nil. `s` is
-- { cfg, now (seconds), last = {} (his memory, kept here), asleep }. A notification is only ever
-- "ding!": he never reads what it says.

-- Whether a line is spoken at this talk level: rare keeps to what matters.
function M.speaks(talk, important)
    if talk == "off" then return false end
    return important == true or talk == "chatty"
end

local BATTERY_LOW = 15
local GAP = { note = 20, space = 4, window = 45 }   -- seconds before the same thing moves him again

local function cooled(s, key)
    local t = s.last[key]
    if t and s.now - t < GAP[key] then return false end
    s.last[key] = s.now
    return true
end

local function judge(kind, arg, s)
    local react = s.cfg.react or {}
    if kind == "note" then
        if not react.notes or s.asleep or not cooled(s, "note") then return nil end
        return { face = "surprised", ms = 1400, move = "startle", line = "ding!", important = true }
    elseif kind == "space" then
        if not react.spaces or s.asleep or not cooled(s, "space") then return nil end
        return { move = "hop", line = "whoosh!" }
    elseif kind == "window" then
        -- a new window: he turns to look (under the workspaces switch: the desktop moving)
        if not react.spaces or s.asleep or not cooled(s, "window") then return nil end
        return { face = "curious", ms = 1600, peek = true, line = "ooh, what's that?" }
    elseif kind == "battery" then
        if not react.battery or type(arg) ~= "table" then return nil end
        local pct = tonumber(arg.percent) or 100
        local now = arg.charging and "charging" or (pct <= BATTERY_LOW and "low" or "ok")
        local was = s.last.battery or "ok"
        s.last.battery = now
        if now == was or s.asleep then return nil end
        if now == "low" then return { face = "sad", ms = 3000, move = "shake", line = "I'm hungry…", important = true } end
        if now == "charging" and was == "low" then return { face = "happy", ms = 2500, move = "hop", line = "yum, power!", important = true } end
        if now == "charging" then return { face = "content", ms = 1800, line = "yum!" } end
        return nil
    elseif kind == "focus" then
        if not react.focus then return nil end
        if arg == "on" then return { mood = "focused", line = "focus mode!" } end
        if arg == "done" then return { face = "excited", ms = 2500, move = "big_hop", line = "you did it!", mood = "happy", important = true } end
        if arg == "break_done" then return { face = "curious", ms = 1800, move = "nod", line = "back to it?" } end
        if arg == "off" then return { mood = "happy" } end
        return nil
    elseif kind == "hour" then
        if not react.time or type(arg) ~= "table" or s.asleep then return nil end
        local h, day = tonumber(arg.hour) or 12, tonumber(arg.day) or 0
        if h >= 6 and h < 11 and s.last.morning ~= day then
            s.last.morning = day
            return { face = "happy", ms = 2000, move = "wave", line = "good morning!" }
        end
        local night = h >= 23 and day or (h < 3 and day - 1) or nil
        if night and s.last.late ~= night then
            s.last.late = night
            return { face = "yawn", ms = 2200, move = "stretch", line = "it's late…" }
        end
        return nil
    end
    return nil
end

function M.react(kind, arg, s)
    s.last = s.last or {}
    local r = judge(kind, arg, s)
    if r and r.line and not M.speaks(s.cfg.talk, r.important) then r.line = nil end
    return r
end

-- ── Variants (companion.variant): his colours ────────────────
-- Ten slots: his body and its side, the ink of every outline and of his face, the screen and its
-- shade, the bubble's paper, and the D-pad, triangle, round and stop buttons. "mooi" takes the
-- shell's palette (palette.json's colours): the primary is his body, the tertiary tints the screen.
M.PALETTES = {
    classic = { body = "#69c7bb", side = "#4fa99d", ink = "#183d42", glass = "#b8f5df", glass_dim = "#9fe3c9",
                paper = "#f4fff9", pad = "#f1c94a", tri = "#5aa7e0", go = "#7bd66a", stop = "#e9606f" },
    night = { body = "#34506a", side = "#273d52", ink = "#0b1622", glass = "#86e1ff", glass_dim = "#5fc1e6",
              paper = "#e4f4ff", pad = "#c9a63e", tri = "#7a8fe8", go = "#4fb08a", stop = "#d0567a" },
    pastel = { body = "#f5b8c9", side = "#e39cb1", ink = "#5b3446", glass = "#fff1d9", glass_dim = "#f7dfb9",
               paper = "#fffaf3", pad = "#f7d98b", tri = "#a9c8f2", go = "#b6e3a8", stop = "#f19aa6" },
    gameboy = { body = "#c5c6b6", side = "#a9aa9b", ink = "#0f380f", glass = "#9bbc0f", glass_dim = "#8bac0f",
                paper = "#e0f0c8", pad = "#3c3c46", tri = "#3c3c46", go = "#8b2a5c", stop = "#8b2a5c" },
}

local function hex(c)
    local r, g, b = tostring(c or ""):match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end
local function to_hex(r, g, b)
    local function c(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("#%02x%02x%02x", c(r), c(g), c(b))
end
-- a toward b by t (0 … 1)
local function mix(a, b, t)
    local ar, ag, ab = hex(a)
    local br, bg, bb = hex(b)
    return to_hex(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end

-- A colour as the scene's rgb() takes it: three numbers 0 … 1 (black when it is not a colour).
function M.rgb(c)
    local r, g, b = hex(c)
    if not r then return 0, 0, 0 end
    return r, g, b
end

-- WCAG's contrast ratio of two colours (1 … 21).
local function lum(c)
    local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
    local r, g, b = hex(c)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
end
function M.contrast(a, b)
    local la, lb = lum(a), lum(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

-- His colours for a variant; `shell` is palette.json's colours (only "mooi" reads it).
function M.palette(variant, shell)
    local base = M.PALETTES[variant] or M.PALETTES.classic
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    if variant ~= "mooi" then return out end
    local p = type(shell) == "table" and shell or {}
    local body, tint = p.primary, p.tertiary or p.primary
    if not hex(body) then return out end
    out.body = body
    out.side = mix(body, "#000000", 0.18)
    -- the screen is always light and the ink always dark, whatever the shell's mode
    out.glass = mix(hex(tint) and tint or body, "#ffffff", 0.62)
    out.glass_dim = mix(out.glass, body, 0.25)
    out.ink = mix(body, "#000000", 0.78)
    for _ = 1, 8 do
        if M.contrast(out.ink, out.glass) >= 4.5 then break end
        out.ink = mix(out.ink, "#000000", 0.5)
        out.glass = mix(out.glass, "#ffffff", 0.4)
    end
    out.paper = mix(body, "#ffffff", 0.9)
    return out
end

-- ── Thrown (pick him up, flick, let go) ───────────────────────
M.GRAVITY = 2600        -- px/s²
M.BOUNCE = 0.55         -- what a bounce keeps of the speed it came in with
M.ROLL = 6              -- how fast he slows sliding along the floor (per second)

-- The flick: the speed across the last samples of a drag (one every `tick_ms`), in px/s.
function M.release(samples, tick_ms)
    local n = #(samples or {})
    if n < 2 then return 0, 0 end
    local first = samples[math.max(1, n - 4)]
    local last = samples[n]
    local steps = n - math.max(1, n - 4)
    local dt = steps * (tonumber(tick_ms) or 16) / 1000
    return (last.x - first.x) / dt, (last.y - first.y) / dt
end

-- One step of flight inside the box b = { x0, x1, y0, y1 } (y1 the floor). Returns the new state
-- with `impact` (the speed of the hardest wall or floor met this step) and `rest` once he stands.
function M.fly(s, dt, b)
    local x, y, vx, vy = s.x, s.y, s.vx, s.vy + M.GRAVITY * dt
    x, y = x + vx * dt, y + vy * dt
    local impact = 0
    if y >= b.y1 then
        impact = math.max(impact, math.abs(vy))
        y, vy = b.y1, -vy * M.BOUNCE
        vx = vx * 0.85
        if math.abs(vy) < 90 then vy = 0 end
    elseif y <= b.y0 then
        impact = math.max(impact, math.abs(vy))
        y, vy = b.y0, -vy * M.BOUNCE
    end
    if x >= b.x1 then impact = math.max(impact, math.abs(vx)); x, vx = b.x1, -vx * M.BOUNCE
    elseif x <= b.x0 then impact = math.max(impact, math.abs(vx)); x, vx = b.x0, -vx * M.BOUNCE end
    local rest = false
    if y >= b.y1 and vy == 0 then
        vx = vx * math.max(0, 1 - M.ROLL * dt)
        if math.abs(vx) < 15 then vx, rest = 0, true end
    end
    return { x = x, y = y, vx = vx, vy = vy, impact = impact, rest = rest }
end

return M
