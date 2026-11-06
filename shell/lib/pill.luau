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
    FACE_W = { time = 120, nexus = 104, bmo = 64 },
}

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
        st.battery = { percent = tonumber(p.percent), charging = p.charging == true }
        if st.battery.charging and not was then st.charge_at = now end
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
        local face = cfg and M.FACE_W[cfg.face] and cfg.face or "time"
        return M.FACE_W[face] + ((face == "bmo" and v.t1 ~= "") and (7 * #v.t1 + 16) or 0)
    end
    local n = #(v.t1 or "") + ((v.t2 and v.t2 ~= "" and v.glyph ~= "notify") and (#v.t2 + 2) or 0)
    if v.glyph == "notify" then n = math.max(#(v.t1 or ""), #(v.t2 or "")) end
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
    local w = width(views[main], cfg) + (split and (width(views[split], cfg) + 8) or 0)
    -- D169: idle and nothing beside it, with hiding on and not just pointed at: a sliver
    local hidden = cfg.autohide == true and main == "idle" and not split and not fresh(st.peek, M.PEEK_MS, now)
    if hidden then w = M.SLIVER end
    return { main = main, moons = moons, split = split, two_lines = main == "notify", width = w, view = views, hidden = hidden }
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
