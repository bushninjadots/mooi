-- The node's time tools (D231): a timer, a stopwatch with laps, a focus / break cycle and a daily alarm, as one
-- instrument. Pure: every function takes the time it is (`now`, milliseconds of the wall clock) and the state, and
-- says what changed; the logic keeps the state in node-time.json, so a timer survives a restart.
--
-- What finishes is told once by `tick` (a timer run out, a focus or break phase over, an alarm reached); the node
-- shows it as a card that waits to be answered. `capsule` is what the resting seed shows while something runs.

local M = {}

M.FILE = "node-time.json"
M.MODES = { "timer", "stopwatch", "focus", "alarm" }
M.FOCUS_MS, M.BREAK_MS, M.LONG_MS, M.ROUNDS = 25 * 60000, 5 * 60000, 15 * 60000, 4
M.ALARM_SOON_MS = 10 * 60000   -- an alarm this close shows on the seed
M.URGENT_MS = 60000            -- the last minute: the capsule turns warm

local function num(v, d) v = tonumber(v); return v or d end

function M.new()
    return {
        mode = "timer",
        timer = { set = 5 * 60000, ends = nil, left = nil },          -- running: ends; paused: left
        stopwatch = { since = nil, acc = 0, laps = {} },               -- running: since
        focus = { phase = "focus", ends = nil, left = nil, round = 1 },
        alarm = { h = 7, m = 30, on = false, next = nil },             -- next: the wall-clock ms it fires at
    }
end

-- any table made usable (a file from an older version, a hand edit)
function M.normalise(t)
    local s = M.new()
    if type(t) ~= "table" then return s end
    for _, m in ipairs(M.MODES) do if t.mode == m then s.mode = m end end
    local tm = type(t.timer) == "table" and t.timer or {}
    s.timer.set = math.max(1000, math.min(24 * 3600000, num(tm.set, s.timer.set)))
    s.timer.ends, s.timer.left = num(tm.ends, nil), num(tm.left, nil)
    local sw = type(t.stopwatch) == "table" and t.stopwatch or {}
    s.stopwatch.since, s.stopwatch.acc = num(sw.since, nil), math.max(0, num(sw.acc, 0))
    if type(sw.laps) == "table" then for i = 1, math.min(#sw.laps, 99) do s.stopwatch.laps[i] = num(sw.laps[i], 0) end end
    local fo = type(t.focus) == "table" and t.focus or {}
    s.focus.phase = (fo.phase == "break" or fo.phase == "long") and fo.phase or "focus"
    s.focus.ends, s.focus.left = num(fo.ends, nil), num(fo.left, nil)
    s.focus.round = math.max(1, math.min(M.ROUNDS, math.floor(num(fo.round, 1))))
    local al = type(t.alarm) == "table" and t.alarm or {}
    s.alarm.h = math.max(0, math.min(23, math.floor(num(al.h, 7))))
    s.alarm.m = math.max(0, math.min(59, math.floor(num(al.m, 30))))
    s.alarm.on = al.on == true
    s.alarm.next = num(al.next, nil)
    return s
end

-- ── what each one reads ──
function M.timer_left(s, now)
    local t = s.timer
    if t.ends then return math.max(0, t.ends - now) end
    return t.left or t.set
end
function M.stopwatch_ms(s, now)
    local w = s.stopwatch
    return w.acc + (w.since and math.max(0, now - w.since) or 0)
end
local function phase_ms(phase) return phase == "break" and M.BREAK_MS or phase == "long" and M.LONG_MS or M.FOCUS_MS end
function M.focus_left(s, now)
    local f = s.focus
    if f.ends then return math.max(0, f.ends - now) end
    return f.left or phase_ms(f.phase)
end
function M.running(s, which)
    if which == "timer" then return s.timer.ends ~= nil end
    if which == "stopwatch" then return s.stopwatch.since ~= nil end
    if which == "focus" then return s.focus.ends ~= nil end
    if which == "alarm" then return s.alarm.on end
end

-- 1:05:09 · 04:59 · with hundredths for the stopwatch (04:59.37)
function M.format(ms, hundredths)
    ms = math.max(0, math.floor(ms or 0))
    local total = ms // 1000
    local h, m, sec = total // 3600, (total // 60) % 60, total % 60
    local out = h > 0 and string.format("%d:%02d:%02d", h, m, sec) or string.format("%02d:%02d", m, sec)
    if hundredths then out = out .. string.format(".%02d", (ms % 1000) // 10) end
    return out
end
-- a countdown shown rounded up, so 00:00 is the moment it ends and not a second before
function M.format_left(ms) return M.format(math.ceil(math.max(0, ms) / 1000) * 1000) end

-- ── the timer ──
function M.timer_add(s, ms)
    local t = s.timer
    -- running: its end moves, and so does what it was set to, so its progress never passes full
    if t.ends then t.ends = t.ends + ms; t.set = math.max(1000, t.set + ms)
    elseif t.left then t.left = math.max(1000, t.left + ms)
    else t.set = math.max(60000, math.min(24 * 3600000, t.set + ms)) end
end
function M.timer_go(s, now)   -- start, pause, or resume
    local t = s.timer
    if t.ends then t.left, t.ends = math.max(0, t.ends - now), nil
    else t.ends, t.left = now + (t.left or t.set), nil end
end
function M.timer_reset(s) s.timer.ends, s.timer.left = nil, nil end

-- ── the stopwatch ──
function M.stopwatch_go(s, now)
    local w = s.stopwatch
    if w.since then w.acc, w.since = w.acc + math.max(0, now - w.since), nil else w.since = now end
end
function M.lap(s, now)
    local w = s.stopwatch
    if not w.since then return false end
    table.insert(w.laps, 1, M.stopwatch_ms(s, now))
    while #w.laps > 99 do table.remove(w.laps) end
    return true
end
function M.stopwatch_reset(s) s.stopwatch.since, s.stopwatch.acc, s.stopwatch.laps = nil, 0, {} end

-- ── focus ──
function M.focus_go(s, now)
    local f = s.focus
    if f.ends then f.left, f.ends = math.max(0, f.ends - now), nil
    else f.ends, f.left = now + (f.left or phase_ms(f.phase)), nil end
end
local function next_phase(f)
    if f.phase == "focus" then f.phase = f.round >= M.ROUNDS and "long" or "break"
    else
        f.round = f.phase == "long" and 1 or f.round + 1
        f.phase = "focus"
    end
end
-- skipping moves to the next phase at once and keeps going if it was going
function M.focus_skip(s, now)
    local f = s.focus
    local was = f.ends ~= nil
    next_phase(f)
    f.left = nil
    f.ends = was and now + phase_ms(f.phase) or nil
end
function M.focus_reset(s) s.focus = { phase = "focus", ends = nil, left = nil, round = 1 } end

-- ── the alarm: hours and minutes of the local day; `wall` gives the local date of a time (os.date("*t", sec)) and
-- `mktime` the time of a local date (os.time{…}), so this stays pure and testable ──
function M.alarm_next(s, now, wall, mktime)
    local d = wall(now // 1000)
    local at = mktime({ year = d.year, month = d.month, day = d.day, hour = s.alarm.h, min = s.alarm.m, sec = 0 }) * 1000
    if at <= now then
        d = wall(now // 1000 + 86400)
        at = mktime({ year = d.year, month = d.month, day = d.day, hour = s.alarm.h, min = s.alarm.m, sec = 0 }) * 1000
    end
    return at
end
function M.alarm_set(s, on, now, wall, mktime)
    s.alarm.on = on and true or false
    s.alarm.next = s.alarm.on and M.alarm_next(s, now, wall, mktime) or nil
end
function M.alarm_nudge(s, dh, dm, now, wall, mktime)
    local total = ((s.alarm.h * 60 + s.alarm.m + dh * 60 + dm) % 1440 + 1440) % 1440
    s.alarm.h, s.alarm.m = total // 60, total % 60
    if s.alarm.on then s.alarm.next = M.alarm_next(s, now, wall, mktime) end
end

-- ── time passing: what finished since the last tick (each told once) ──
function M.tick(s, now, wall, mktime)
    local done = {}
    if s.timer.ends and now >= s.timer.ends then
        s.timer.ends, s.timer.left = nil, nil
        done[#done + 1] = { kind = "timer", title = "Time's up", detail = M.format(s.timer.set) .. " timer" }
    end
    local f = s.focus
    if f.ends and now >= f.ends then
        local was = f.phase
        next_phase(f)
        f.ends, f.left = nil, nil   -- the next phase waits for you: a break is taken, not imposed
        done[#done + 1] = was == "focus"
            and { kind = "focus", title = f.phase == "long" and "Focus done: a long break" or "Focus done: take a break", detail = "Round " .. tostring(math.max(1, f.round)) .. " of " .. M.ROUNDS }
            or { kind = "focus", title = "Break over", detail = "Round " .. tostring(f.round) .. " of " .. M.ROUNDS .. " next" }
    end
    if s.alarm.on and s.alarm.next and now >= s.alarm.next then
        done[#done + 1] = { kind = "alarm", title = "Alarm", detail = string.format("%02d:%02d", s.alarm.h, s.alarm.m) }
        s.alarm.next = wall and mktime and M.alarm_next(s, now + 1000, wall, mktime) or nil
    end
    return done
end

-- whether anything needs the clock to keep ticking
function M.busy(s) return s.timer.ends ~= nil or s.stopwatch.since ~= nil or s.focus.ends ~= nil or s.alarm.on end

-- ── what the resting seed shows: the most pressing thing that runs, or nil ──
-- { mode, text, frac (what is left of it, 0..1), urgent }
function M.capsule(s, now)
    local best
    local function take(c) if not best or c.rank > best.rank then best = c end end
    if s.timer.ends then
        local left = M.timer_left(s, now)
        take({ mode = "timer", text = M.format_left(left), frac = left / math.max(1, s.timer.set), urgent = left <= M.URGENT_MS, rank = 4 })
    end
    if s.focus.ends then
        local left = M.focus_left(s, now)
        take({ mode = "focus", text = M.format_left(left), frac = left / phase_ms(s.focus.phase), urgent = left <= M.URGENT_MS, rank = 3 })
    end
    if s.alarm.on and s.alarm.next and s.alarm.next - now <= M.ALARM_SOON_MS then
        local left = s.alarm.next - now
        take({ mode = "alarm", text = string.format("%02d:%02d", s.alarm.h, s.alarm.m), frac = left / M.ALARM_SOON_MS, urgent = left <= M.URGENT_MS, rank = 5 })
    end
    if s.stopwatch.since then
        take({ mode = "stopwatch", text = M.format(M.stopwatch_ms(s, now)), frac = 1, urgent = false, rank = 1 })
    end
    if best then best.frac = math.max(0, math.min(1, best.frac)); best.rank = nil end
    return best
end

-- the four as the panel's rail reads them (the one on stage first in the list is not left out: the panel decides)
function M.readouts(s, now)
    local f = s.focus
    return {
        timer = { value = M.format_left(M.timer_left(s, now)), on = s.timer.ends ~= nil, paused = s.timer.left ~= nil,
                  frac = math.min(1, M.timer_left(s, now) / math.max(1, s.timer.set)) },
        stopwatch = { value = M.format(M.stopwatch_ms(s, now), true), on = s.stopwatch.since ~= nil,
                      paused = s.stopwatch.since == nil and s.stopwatch.acc > 0, frac = 1 },
        focus = { value = M.format_left(M.focus_left(s, now)), on = f.ends ~= nil, paused = f.left ~= nil,
                  frac = M.focus_left(s, now) / phase_ms(f.phase),
                  phase = f.phase == "focus" and "FOCUS" or f.phase == "long" and "LONG BREAK" or "BREAK", round = f.round },
        alarm = { value = string.format("%02d:%02d", s.alarm.h, s.alarm.m), on = s.alarm.on, paused = false,
                  frac = s.alarm.on and s.alarm.next and math.max(0, math.min(1, (s.alarm.next - now) / 86400000)) or 0 },
    }
end

return M
