-- The Reveal (D208, spec §5): hold Super and the surface opens at the pointer. Pure: the stages in time,
-- what the pointer picks, what letting go does, and the safeguards that close a reveal nothing else will.
-- Stages: 0 none · 1 touch (a faint ring) · 2 open (the Aperture) · 3 hub (the groups round the rim, anchored
-- where it began) · 4 approach (a group picked) · 5 expand (a source rested on). Angles run clockwise from
-- straight up.

local M = { DELAY = 250, OPEN_MS = 350, HUB_MS = 150, EXPAND_MS = 400, IDLE_MS = 6000, R = 120, RING = 170,
            DEAD = 46, LEAVE = 60, STEP = 0.35 }
M.GROUPS = { "time", "sound", "machine", "work", "you", "desk" }
M.SOURCES = { time = { "clock", "calendar", "weather" }, sound = { "music", "volume" },
              machine = { "resources", "battery", "network", "bluetooth" }, work = { "workspaces", "windows" },
              you = { "notifications" }, desk = {}, window = {} }

function M.state() return { stage = 0 } end

function M.groups(st)
    local g = {}
    for i, v in ipairs(M.GROUPS) do g[i] = v end
    if st.over_window then g[#g + 1] = "window" end
    return g
end

function M.down(st, now)
    st.down_at, st.stage, st.moved_at, st.last, st.ax, st.ay, st.pick_at, st.picked = now, 0, now, nil, nil, nil, nil, nil
end

local function close(st) st.down_at, st.stage, st.ax, st.ay = nil, 0, nil, nil end

-- Luau has math.atan2; Lua 5.4 (the unit tests) has the two-argument math.atan
local atan2 = math.atan2 or math.atan
local function angle(dx, dy) return atan2(dx, -dy) % (2 * math.pi) end

function M.pick(st, p)
    if not st.ax then return {} end
    local dx, dy = p.x - st.ax, p.y - st.ay
    local r = math.sqrt(dx * dx + dy * dy)
    if r < M.DEAD then return {} end
    local gs = M.groups(st)
    local n = #gs
    local a = angle(dx, dy)
    local w = 2 * math.pi / n
    local gi = math.floor(a / w + 0.5) % n + 1
    local out = { group = gi }
    if r > M.RING then
        -- the group's sources sit along the arc from its angle, clockwise, STEP apart: the nearest is picked
        local list = M.SOURCES[gs[gi]] or {}
        local centre = (gi - 1) * w
        local best, bd
        for k, id in ipairs(list) do
            local d = math.abs(((a - (centre + (k - 1) * M.STEP)) + math.pi) % (2 * math.pi) - math.pi)
            if not bd or d < bd then best, bd = id, d end
        end
        out.source = best
    end
    out.r = r
    return out
end

-- Called often (the logic's tick) with the pointer: moves the stages on, anchors the hub, closes on idle.
function M.tick(st, now, p)
    if not st.down_at then return st end
    if not st.last or st.last.x ~= p.x or st.last.y ~= p.y then st.moved_at, st.last = now, { x = p.x, y = p.y } end
    if st.stage > 0 and now - st.moved_at > M.IDLE_MS then close(st); return st end
    local age = now - st.down_at
    if age < M.DELAY then st.stage = 0
    elseif age < M.DELAY + M.OPEN_MS then st.stage = 1
    elseif age < M.DELAY + M.OPEN_MS + M.HUB_MS then st.stage = 2
    else
        if not st.ax then st.ax, st.ay = p.x, p.y end
        local pk = M.pick(st, p)
        if pk.source then
            if st.picked ~= pk.source then st.picked, st.pick_at = pk.source, now end
            st.stage = (now - st.pick_at >= M.EXPAND_MS) and 5 or 4
        elseif pk.group then st.stage, st.picked = 4, nil
        else st.stage, st.picked = 3, nil end
    end
    return st
end

-- Super let go: "tap" (before the delay: today's Super tap), "release" (a reveal was open), or nil.
-- (review I2: an up whose down never arrived — Hyprland runs the two as separate processes, which can race —
-- and a release before any stage, at whatever age, are both taps)
function M.up(st, now)
    if not st.down_at then return "tap" end
    if st.stage == 0 then close(st); return "tap" end
    return "release"
end

-- What letting go at p does: cancel (nothing picked), open (a source picked inside its ring), or leave (a
-- source dragged out past the ring: it stays on the desktop where it was let go).
function M.release(st, p)
    local pk = M.pick(st, p)
    local out
    if not pk.source then out = { kind = "cancel" }
    elseif pk.r > M.RING + M.LEAVE then out = { kind = "leave", source = pk.source, x = p.x, y = p.y }
    else out = { kind = "open", source = pk.source } end
    return out
end

function M.finish(st) close(st) end

-- the events that close a reveal whatever it shows (a Super shortcut never sends Super's "up")
local CLOSE = { workspace = true, focus = true, escape = true, outside = true, idle = true }
function M.close_on(event) return CLOSE[event] == true end

return M
