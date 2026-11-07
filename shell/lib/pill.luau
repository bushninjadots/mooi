-- The Pill (D168): what the capsule at the top centre shows. Pure: the bar's logic notes what happens
-- (music, battery, recording, a volume or brightness change, a notification, a moon pressed) and asks
-- what to show; a fake clock in the tests stands in for the real one.
--
-- The highest activity in the owner's order that is active is the Pill's main; the next ones are its
-- moons (satellites), or the first of them shares the Pill with it (split). Idle (the time and the
-- workspaces) is always there underneath and is never a moon.

local M = {
    ACTIVITIES = { "battery", "record", "notify", "music", "osd", "idle" },
    OSD_MS = 2000, NOTIFY_MS = 6000, CHARGE_MS = 4000, PIN_MS = 6000, LOW = 15,
    -- D169: pointed at, a hidden Pill comes back this long; hidden, it is this wide
    PEEK_MS = 4000, SLIVER = 44,
    -- the width of each face (BMO's grows with what he says)
    FACE_W = { time = 120, nexus = 104, bmo = 72,
               -- D170: a module's face: its icon and a short reading (ui/pill.plm)
               weather = 160, resources = 150, media = 220, battery = 104, workspaces = 140, network = 170, notifications = 130 },
    -- D170: what the closed Pill may show when nothing is happening: three of its own, and module faces
    FACES = { "time", "bmo", "nexus", "weather", "resources", "media", "battery", "workspaces", "network", "notifications",
              "visualiser" },     -- D171
    -- D171: the views the wheel turns through when the owner has not chosen (pill.views), and the dot
    VIEWS_DEFAULT = { "time", "workspaces", "notifications", "media", "weather", "resources", "bmo", "nexus" },
    DOT = 14,
    -- D171: detail full makes room for a second part (a date, hi/lo, memory, the artist…)
    FACE_W_FULL = { time = 190, weather = 230, resources = 220, media = 300, battery = 170, workspaces = 190,
                    network = 230, notifications = 260, visualiser = 170 },
}
M.FACE_W.visualiser = 110

local function is_face(id)
    for _, f in ipairs(M.FACES) do if f == id then return true end end
    return false
end

-- D171: the next view along the owner's list (dir 1 or -1), round the end; an unknown current view → the
-- list's first; unknown ids are skipped; nothing usable → the default list
function M.next_view(views, current, dir)
    local list = {}
    for _, v in ipairs(type(views) == "table" and views or {}) do if is_face(v) then list[#list + 1] = v end end
    if #list == 0 then list = M.VIEWS_DEFAULT end
    local at = nil
    for i, v in ipairs(list) do if v == current then at = i end end
    if not at then return list[1] end
    return list[(at - 1 + ((tonumber(dir) or 1) < 0 and -1 or 1)) % #list + 1]
end

function M.state()
    return { media = {}, battery = {}, recording = false, rec_since = 0, osd = nil, notify = nil, charge_at = nil, pin = nil,
             say = "", peek = nil }
end

function M.note(st, kind, p, now)
    p = type(p) == "table" and p or {}
    if kind == "media" then
        st.media = { playing = p.playing == true, title = tostring(p.title or ""), artist = tostring(p.artist or "") }
    elseif kind == "battery" then
        local was = st.battery.charging == true
        local first = st.battery.percent == nil      -- mooi starting on AC is not "plugged in" (review M2)
        st.battery = { percent = tonumber(p.percent), charging = p.charging == true }
        if st.battery.charging and not was and not first then st.charge_at = now end
        if not st.battery.charging then st.charge_at = nil end
    elseif kind == "recording" then
        if p.on and not st.recording then st.rec_since = now end
        st.recording = p.on == true
    elseif kind == "osd" then
        st.osd = { kind = p.kind == "bri" and "bri" or "vol", value = math.max(0, math.min(1, tonumber(p.value) or 0)), at = now }
    elseif kind == "notify" then
        st.notify = { app = tostring(p.app or ""), summary = tostring(p.summary or ""), at = now }
    elseif kind == "pin" then
        st.pin = { id = p.id, at = now }
    elseif kind == "say" then          -- D169: BMO's line, or "" when he is quiet (lib/pillface times it)
        st.say = tostring(p.text or "")
    elseif kind == "peek" then         -- D169: the hidden Pill pointed at
        st.peek = { at = now }
    end
end

local function fresh(ev, ms, now) return ev ~= nil and now - ev.at < ms end

local function active(st, id, now)
    if id == "idle" then return true end
    if id == "music" then return st.media.playing == true and st.media.title ~= "" end
    if id == "record" then return st.recording == true end
    if id == "osd" then return fresh(st.osd, M.OSD_MS, now) end
    if id == "notify" then return fresh(st.notify, M.NOTIFY_MS, now) end
    if id == "battery" then
        local b = st.battery
        if st.charge_at and now - st.charge_at < M.CHARGE_MS then return true end
        return b.percent ~= nil and b.percent <= M.LOW and not b.charging
    end
    return false
end

local function clock(ms)
    local s = math.floor(ms / 1000)
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

-- What each activity shows: a glyph name the scene maps to a mark, a first and a second line, a value.
local function view(st, id, now, cfg)
    if id == "music" then return { glyph = "music", t1 = st.media.title, t2 = st.media.artist } end
    if id == "osd" then
        local o = st.osd or { kind = "vol", value = 0 }
        return { glyph = o.kind, t1 = o.kind == "bri" and "BRI" or "VOL", t2 = string.format("%d", math.floor(o.value * 100 + 0.5)), value = o.value }
    end
    if id == "notify" then local n = st.notify or {}; return { glyph = "notify", t1 = n.app or "", t2 = n.summary or "" } end
    if id == "record" then return { glyph = "record", t1 = "REC " .. clock(now - (st.rec_since or now)) } end
    if id == "battery" then
        local b = st.battery
        local charging = b.charging and st.charge_at and now - st.charge_at < M.CHARGE_MS
        return { glyph = charging and "charging" or "low", t1 = (charging and "Charging " or "Battery ") .. tostring(b.percent or 0) .. "%" }
    end
    return { glyph = "idle", t1 = (cfg and cfg.face == "bmo") and (st.say or "") or "", t2 = "" }
end

local function width(v, cfg)
    if not v then return 0 end
    if v.glyph == "idle" then
        -- D170: a module's face is its glyph and a short reading (the bar works it out: cfg.face_text)
        local builtin = cfg and (cfg.face == "time" or cfg.face == "bmo" or cfg.face == "nexus")
        -- D171: the detail — icon is just the glyph (a module's face), full has room for a second part
        if cfg and not builtin and cfg.detail == "icon" and M.FACE_W[cfg.face] then return 44 end
        if cfg and cfg.detail == "full" and M.FACE_W_FULL[cfg.face] then return M.FACE_W_FULL[cfg.face] end
        if cfg and cfg.face and not builtin and cfg.face_text then
            return math.max(104, 44 + 7 * #tostring(cfg.face_text))
        end
        local face = cfg and M.FACE_W[cfg.face] and cfg.face or "time"
        return M.FACE_W[face] + ((face == "bmo" and v.t1 ~= "") and (7 * #v.t1 + 16) or 0)
    end
    -- what ui/pill.plm draws: "t1 · t2" on one line (a notice too: its app and its summary)
    local n = #(v.t1 or "") + ((v.t2 and v.t2 ~= "") and (#v.t2 + 2) or 0)
    if v.glyph == "vol" or v.glyph == "bri" then n = n + 16 end
    return math.max(120, 44 + 7 * n)
end

-- cfg = { order, off = { [id] = true }, moons, multi }
function M.compute(st, cfg, now)
    local order = cfg.order or M.ACTIVITIES
    local off = cfg.off or {}
    local list = {}
    if st.pin and now - st.pin.at < M.PIN_MS and st.pin.id ~= "idle" and active(st, st.pin.id, now) then
        list[1] = st.pin.id
    end
    for _, id in ipairs(order) do
        if id ~= "idle" and not off[id] and id ~= list[1] and active(st, id, now) then list[#list + 1] = id end
    end
    local main = list[1] or "idle"
    local rest = {}
    for i = 2, #list do rest[#rest + 1] = list[i] end
    local split = nil
    if cfg.multi == "split" and rest[1] then split = table.remove(rest, 1) end
    local moons = {}
    for i = 1, math.min(#rest, tonumber(cfg.moons) or 3) do moons[i] = rest[i] end
    local views = {}
    for _, id in ipairs(M.ACTIVITIES) do views[id] = view(st, id, now, cfg) end
    local w1 = width(views[main], cfg)
    local w = w1 + (split and (width(views[split], cfg) + 8) or 0)
    -- never past the room between the side groups (review I3): a long title is cut, not spread over them
    local cap = tonumber(cfg.max_w)
    if cap and cap >= 120 and w > cap then w1 = math.floor(w1 * cap / w); w = cap end
    -- D169: idle and nothing beside it, with hiding on and not just pointed at: a sliver
    local dot = cfg.shape == "dot"       -- D171: the dot hides when idle by being one
    local hidden = (cfg.autohide == true or dot) and main == "idle" and not split and not fresh(st.peek, M.PEEK_MS, now)
    if hidden then w = dot and M.DOT or M.SLIVER end
    return { main = main, moons = moons, split = split, two_lines = main == "notify", width = w, w1 = w1, view = views, hidden = hidden }
end

-- ms until a timed activity ends (so the logic can look again then), or nil
function M.next_change(st, now)
    local best = nil
    local function at(t) if t and t > now and (best == nil or t - now < best) then best = t - now end end
    if st.osd then at(st.osd.at + M.OSD_MS) end
    if st.notify then at(st.notify.at + M.NOTIFY_MS) end
    if st.charge_at then at(st.charge_at + M.CHARGE_MS) end
    if st.pin then at(st.pin.at + M.PIN_MS) end
    if st.peek then at(st.peek.at + M.PEEK_MS) end
    return best
end

-- Where the Pill and its moons sit: the Pill centred on the screen; moons 24 px, 8 px apart (nodes: on
-- an 18 px trace), the first to its left, the next to its right, and so on outwards.
M.MOON = 24
M.TRACE = 18
function M.place(screen_w, w, n, multi)
    local gap = multi == "nodes" and M.TRACE or 8
    local x = math.floor((screen_w - w) / 2)
    local out = { x = x, moons = {} }
    local l, r = x, x + w
    for k = 1, n do
        if k % 2 == 1 then l = l - gap - M.MOON; out.moons[k] = l
        else out.moons[k] = r + gap; r = r + gap + M.MOON end
    end
    return out
end

-- D170: what a press on the Pill does. main: the activity it shows; face: pill.face; button: "left" or
-- "right"; osd: "vol" or "bri" (which change is showing). Left unfolds the board on the activity's room
-- (the Nexus face's left is the Nexus button, while nothing is happening); right keeps the old jumps.
local ROOM = { idle = "now", music = "now", record = "now", battery = "power", notify = "signals" }
local FACE_ROOM = { weather = "weather", resources = "resources", media = "now", battery = "power", workspaces = "workspaces",
                    network = "connections", notifications = "signals", visualiser = "visualiser" }
function M.press(main, face, button, osd)
    main = main or "idle"
    local room = ROOM[main] or (main == "osd" and (osd == "bri" and "display" or "sound")) or "now"
    if button == "right" then
        if face == "nexus" and main == "idle" then return { kind = "board", room = "now" } end
        if main == "idle" then return { kind = "calendar" } end
        if main == "music" then return { kind = "player" } end
        if main == "record" then return { kind = "record" } end
        if main == "osd" then return { kind = "island", island = osd == "bri" and "display" or "sound" } end
        if main == "battery" then return { kind = "island", island = "power" } end
        return { kind = "board", room = room }
    end
    if face == "nexus" and main == "idle" then return { kind = "nexus" } end
    -- D171: idle, the board opens on the room of the view the Pill shows
    if main == "idle" then room = FACE_ROOM[face] or "now" end
    return { kind = "board", room = room }
end

-- D170 (review I2): the readers Pill mode needs although their modules are not on the bar: the pads',
-- the face's, and the weather Now shows. Returns a set of reader ids (resources, weather, bandwidth, keyboard).
function M.needs(p)
    p = type(p) == "table" and p or {}
    -- weather for Now; the processor and memory for the Resources view and room and Diagnostics (review I1)
    local out = { weather = true, resources = true }
    local function want(id)
        if id == "resources" then out.resources = true
        elseif id == "bandwidth" or id == "network" then out.bandwidth = true
        elseif id == "keyboard" then out.keyboard = true end
    end
    for _, id in ipairs(M.pads(p.pads)) do want(id) end
    want(p.face)
    return out
end

-- D170: the board's pads from pill.pads: known parts only, each once, eight at most, the owner's order.
-- Not a list at all → the default eight; an empty list is an empty board.
function M.pads(list)
    local parts = require("lib/pillpads")
    if type(list) ~= "table" then list = parts.DEFAULT end
    local out, seen = {}, {}
    for _, id in ipairs(list) do
        if #out >= 8 then break end
        if type(id) == "string" and parts.get(id) and not seen[id] then out[#out + 1] = id; seen[id] = true end
    end
    return out
end

-- The order list in Settings (row from 0): move up or down, switch on or off. Idle stays last and on —
-- it is what the Pill shows when nothing else is happening.
function M.reorder(order, off, row, op)
    local o = {}
    for _, id in ipairs(order or M.ACTIVITIES) do if id ~= "idle" then o[#o + 1] = id end end
    local f = {}
    for _, id in ipairs(off or {}) do if id ~= "idle" then f[#f + 1] = id end end
    local i = (tonumber(row) or -1) + 1
    if o[i] then
        if op == "up" and i > 1 then o[i], o[i - 1] = o[i - 1], o[i]
        elseif op == "down" and i < #o then o[i], o[i + 1] = o[i + 1], o[i]
        elseif op == "toggle" then
            local at = nil
            for k, id in ipairs(f) do if id == o[i] then at = k end end
            if at then table.remove(f, at) else f[#f + 1] = o[i] end
        end
    end
    o[#o + 1] = "idle"
    return o, f
end

return M
