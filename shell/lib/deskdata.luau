-- The desktop widgets' data for the D141 kinds: weather's sky and days, the calendar's month, the
-- focus timer, Claude's last line, the launcher's rows, the system scope's samples, and which way the
-- wallpaper's light falls. Pure: mooi-widgets.luau reads the files and services, this works them out
-- (tests/unit/run.lua, "widgets data").

local calendar = require("lib/calendar")

local M = {}

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

-- ── Weather ──
-- An icon for a WMO code: 0 sun · 1 moon · 2 cloud · 3 sun and cloud · 4 fog · 5 rain · 6 snow · 7 storm
function M.icon_kind(code, is_day)
    local c = tonumber(code) or -1
    local day = tonumber(is_day) ~= 0
    if c == 0 or c == 1 then return day and 0 or 1 end
    if c == 2 then return day and 3 or 2 end
    if c == 3 then return 2 end
    if c == 45 or c == 48 then return 4 end
    if (c >= 51 and c <= 67) or (c >= 80 and c <= 82) then return 5 end
    if (c >= 71 and c <= 77) or c == 85 or c == 86 then return 6 end
    if c >= 95 then return 7 end
    return 2
end
M.ICON_WORD = { [0] = "CLEAR", "CLEAR NIGHT", "CLOUDY", "PARTLY CLOUDY", "FOG", "RAIN", "SNOW", "STORM" }

-- The sky of one hour: night blue, a warm band where day and night meet, day blue greyed by cloud
-- and darkened by rain. { r, g, b } 0 … 1.
function M.sky(code, is_day, twilight)
    local k = M.icon_kind(code, is_day)
    local c
    if twilight then c = { 0.93, 0.52, 0.32 }
    elseif tonumber(is_day) == 0 then c = { 0.06, 0.09, 0.22 }
    else c = { 0.36, 0.62, 0.86 } end
    local grey = (k == 2 or k == 4) and 0.55 or (k == 3 and 0.25 or ((k == 5 or k == 7) and 0.65 or (k == 6 and 0.5 or 0)))
    local g = (c[1] + c[2] + c[3]) / 3
    local dark = (k == 5 or k == 7) and 0.75 or 1
    return { r = (c[1] + (g - c[1]) * grey) * dark, g = (c[2] + (g - c[2]) * grey) * dark, b = (c[3] + (g - c[3]) * grey) * dark }
end

-- The next `n` hours from the open-meteo answer (the current one first): { label, temp, t (0 … 1 across
-- them), wet (0 … 1), kind, r, g, b, now }. Nil without hours.
function M.horizon(answer, n)
    n = n or 24
    if type(answer) ~= "table" or type(answer.hourly) ~= "table" or type(answer.current) ~= "table" then return nil end
    local h = answer.hourly
    local times, temps, codes, days = h.time or {}, h.temperature_2m or {}, h.weather_code or {}, h.is_day or {}
    local now = tostring(answer.current.time or ""):sub(1, 13)
    local start
    for i, t in ipairs(times) do if tostring(t):sub(1, 13) == now then start = i; break end end
    if not start then return nil end
    local out, lo, hi = {}, math.huge, -math.huge
    for i = start, math.min(#times, start + n - 1) do
        local tp = tonumber(temps[i]) or 0
        lo, hi = math.min(lo, tp), math.max(hi, tp)
        out[#out + 1] = { label = tostring(times[i]):sub(12, 13), temp = tp, code = tonumber(codes[i]) or -1, day = tonumber(days[i]) or 1 }
    end
    for i, o in ipairs(out) do
        local prev, nxt = out[i - 1], out[i + 1]
        local twi = (prev and prev.day ~= o.day) or (nxt and nxt.day ~= o.day) or false
        local c = M.sky(o.code, o.day, twi)
        o.r, o.g, o.b = c.r, c.g, c.b
        o.t = hi > lo and (o.temp - lo) / (hi - lo) or 0.5
        o.kind = M.icon_kind(o.code, o.day)
        o.wet = (o.kind == 5 or o.kind == 7) and 1 or (o.kind == 6 and 0.6 or 0)
        o.now = i == 1
    end
    return out, lo, hi
end

-- The days (lib/forecast's) with each one's low and high placed on the week's range (a, b: 0 … 1).
function M.week(days)
    local lo, hi = math.huge, -math.huge
    for _, d in ipairs(days or {}) do lo, hi = math.min(lo, d.lo or 0), math.max(hi, d.hi or 0) end
    local out = {}
    for i, d in ipairs(days or {}) do
        local span = hi > lo and (hi - lo) or 1
        out[i] = { lab = string.upper(string.sub(d.label or "", 1, 3)), kind = M.icon_kind(d.code, 1),
                   hi = string.format("%d°", math.floor((d.hi or 0) + 0.5)), lo = string.format("%d°", math.floor((d.lo or 0) + 0.5)),
                   a = ((d.lo or 0) - lo) / span, b = ((d.hi or 0) - lo) / span }
    end
    return out
end

-- D301: the next seven days straight from the weather answer, for the week layout. The first is
-- TODAY, the rest are the weekdays; a and b place each low and high on the week's shared range.
local WEEKDAY = { "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN" }
function M.week7(doc)
    if type(doc) ~= "table" or type(doc.answer) ~= "table" then return nil end
    local d = type(doc.answer.daily) == "table" and doc.answer.daily or {}
    local times = type(d.time) == "table" and d.time or {}
    local codes = type(d.weather_code) == "table" and d.weather_code or {}
    local maxs = type(d.temperature_2m_max) == "table" and d.temperature_2m_max or {}
    local mins = type(d.temperature_2m_min) == "table" and d.temperature_2m_min or {}
    local rows, lo, hi = {}, math.huge, -math.huge
    for i = 1, math.min(7, #times) do
        local high, low = tonumber(maxs[i]), tonumber(mins[i])
        if high and low then
            local y, m, day = tostring(times[i]):match("^(%d+)%-(%d+)%-(%d+)")
            local label = (i == 1 and "TODAY") or (y and WEEKDAY[calendar.weekday(tonumber(y), tonumber(m), tonumber(day)) + 1] or "")
            lo, hi = math.min(lo, low), math.max(hi, high)
            rows[#rows + 1] = { lab = label, kind = M.icon_kind(codes[i], 1),
                                hi = string.format("%d°", math.floor(high + 0.5)), lo = string.format("%d°", math.floor(low + 0.5)),
                                high = high, low = low }
        end
    end
    if #rows == 0 then return nil end
    local span = hi > lo and (hi - lo) or 1
    for _, r in ipairs(rows) do r.a, r.b = (r.low - lo) / span, (r.high - lo) / span end
    return rows
end

-- ── Calendar ──
-- A month as 42 cells (Monday first): { d, inm (in the month), today, due (cards due that day, not
-- done), key (the day as days since 1970: the board's due numbers) }. `today` is such a number.
local function days_from_civil(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end
M.day_number = days_from_civil
function M.month_grid(y, m, today, board)
    local due = {}
    if type(board) == "table" and type(board.cards) == "table" then
        local cols = type(board.columns) == "table" and board.columns or {}
        local done = #cols > 0 and cols[#cols].id or nil
        for _, c in ipairs(board.cards) do
            local d = tonumber(c.due)
            if d and c.col ~= done then due[d] = (due[d] or 0) + 1 end
        end
    end
    local first = days_from_civil(y, m, 1)
    local lead = calendar.weekday(y, m, 1)       -- 0 Monday
    local cells = {}
    for i = 0, 41 do
        local key = first - lead + i
        -- the day of the month back from the number (the cells around the month are its neighbours')
        local yy, mm = y, m
        local off = i - lead
        local d
        if off < 0 then
            yy, mm = calendar.shift(y, m, -1)
            d = calendar.days_in(yy, mm) + off + 1
        elseif off >= calendar.days_in(y, m) then
            d = off - calendar.days_in(y, m) + 1
        else d = off + 1 end
        cells[#cells + 1] = { d = tostring(d), inm = off >= 0 and off < calendar.days_in(y, m), today = key == today, due = due[key] or 0, key = key }
    end
    return cells
end

-- D301: the civil date of a day number, for the agenda's next days.
local function civil_from_days(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + (mp < 10 and 3 or -9)
    if m <= 2 then y = y + 1 end
    return y, m, d
end

-- D301: the next `count` days after today, for the agenda layout: { dow, d, due }.
function M.agenda(today, board, count)
    count = count or 6
    local due = {}
    if type(board) == "table" and type(board.cards) == "table" then
        local cols = type(board.columns) == "table" and board.columns or {}
        local done = #cols > 0 and cols[#cols].id or nil
        for _, c in ipairs(board.cards) do
            local d = tonumber(c.due)
            if d and c.col ~= done then due[d] = (due[d] or 0) + 1 end
        end
    end
    local out = {}
    for i = 1, count do
        local key = today + i
        local y, m, d = civil_from_days(key)
        out[i] = { dow = WEEKDAY[calendar.weekday(y, m, d) + 1], d = tostring(d), due = (due[key] or 0) > 0 }
    end
    return out
end

-- ── Focus timer ──
-- { total, left (when stopped), ends (when running: the time it ends), brk (a break) }
function M.timer(minutes, brk) return { total = minutes * 60, left = minutes * 60, ends = nil, brk = brk == true } end
function M.timer_left(t, now)
    if t.ends then return math.max(0, t.ends - now) end
    return t.left
end
function M.timer_toggle(t, now)
    if t.ends then t.left = math.max(0, t.ends - now); t.ends = nil
    elseif t.left > 0 then t.ends = now + t.left end
    return t
end
-- more or fewer minutes: running, it moves the end; stopped, the length (1 … 180 minutes)
function M.timer_add(t, seconds, now)
    local left = M.timer_left(t, now)
    local new = clamp(left + seconds, 60, 180 * 60)
    if t.ends then t.ends = now + new else t.left = new end
    t.total = math.max(t.total + (new - left), new)
    return t
end
function M.mmss(s)
    s = math.max(0, math.floor(s + 0.5))
    local h = math.floor(s / 3600)
    if h > 0 then return string.format("%d:%02d:%02d", h, math.floor(s / 60) % 60, s % 60) end
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

-- ── Claude ──
-- The last thing Claude (or BMO) said in the notch (notch-claude.json): text (one paragraph), who, time.
function M.claude_last(chat)
    local turns = type(chat) == "table" and type(chat.turns) == "table" and chat.turns or {}
    for i = #turns, 1, -1 do
        local t = turns[i]
        if type(t) == "table" and (t.who == "claude" or t.who == "bmo") and type(t.text) == "string" and t.text ~= "" then
            local s = t.text:gsub("```.-```", " [code] "):gsub("[%*_`#>]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
            return { text = s, who = t.who == "bmo" and "BMO" or "CLAUDE", time = tonumber(t.time) }
        end
    end
    return nil
end
-- How many Claude Code sessions run, from `pgrep -x claude` (one pid a line).
function M.count_lines(out)
    local n = 0
    for l in tostring(out or ""):gmatch("[^\n]+") do if l:match("^%s*%d+%s*$") then n = n + 1 end end
    return n
end

-- ── Launcher ──
-- The apps asked for ("kitty,zen,code"), each found in the apps service's list by the same matches as
-- a window's icon (lib/apps): { name, exec, icon, letter, run (a window of it is open), pulse (its
-- notifications not yet seen) }; the ones not installed are left out.
function M.launch_rows(spec, apps_list, windows, notes, app_for)
    local out = {}
    local open, unseen = {}, {}
    for _, w in ipairs(windows or {}) do open[string.lower(tostring(w.class or ""))] = true end
    for _, n in ipairs(notes or {}) do local a = string.lower(tostring(n.app or "")); unseen[a] = (unseen[a] or 0) + 1 end
    for want in tostring(spec or ""):gmatch("[^,]+") do
        want = want:gsub("^%s+", ""):gsub("%s+$", "")
        if want ~= "" and #out < 12 then
            local a = app_for(apps_list, want)
            if a then
                local keys = { string.lower(want), string.lower(tostring(a.wmclass or "")), string.lower(tostring(a.name or "")),
                               string.lower(tostring(a.id or ""):match("([^.]+)$") or "") }
                local run, pulse = false, 0
                for _, k in ipairs(keys) do
                    if k ~= "" then
                        if open[k] then run = true end
                        pulse = math.max(pulse, unseen[k] or 0)
                    end
                end
                out[#out + 1] = { name = tostring(a.name or want), exec = tostring(a.exec or ""), icon = tostring(a.icon or ""),
                                  iconed = (a.icon or "") ~= "", letter = string.upper(string.sub(want, 1, 1)), run = run, pulse = math.min(pulse, 9) }
            end
        end
    end
    return out
end

-- ── System ──
-- A window of the last `n` samples (oldest first).
function M.push(list, v, n)
    list[#list + 1] = v
    while #list > n do table.remove(list, 1) end
    return list
end

-- ── Light ──
-- Which way the wallpaper's light falls: from its brightest third towards the widget, as a unit
-- vector (dx, dy) shadows are cast along. Straight down when the map is flat or unknown.
function M.light(map, cx, cy, screen)
    if type(map) ~= "table" or type(map.cells) ~= "table" or not map.cols then return 0, 1 end
    local sx, sy, sw = 0, 0, 0
    for r = 0, map.rows - 1 do
        for c = 0, map.cols - 1 do
            local cell = map.cells[r * map.cols + c + 1]
            local l = cell and cell.l or 0
            local w = l > 0.6 and (l - 0.6) or 0
            sx, sy, sw = sx + w * (c + 0.5) / map.cols, sy + w * (r + 0.5) / map.rows, sw + w
        end
    end
    if sw < 0.05 then return 0, 1 end
    local lx, ly = sx / sw * screen.w, sy / sw * screen.h
    local dx, dy = (cx or screen.w / 2) - lx, (cy or screen.h / 2) - ly
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return 0, 1 end
    -- a light behind the widget still casts a little downwards
    return dx / len, math.max(dy / len, 0.25)
end

return M
