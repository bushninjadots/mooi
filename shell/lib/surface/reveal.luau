-- The Reveal (D208, D209): hold Super and the surface opens. Pure: the stages in time, what letting go does,
-- and the safeguards that close a reveal nothing else will.
-- Stages: 0 none · 1 faint · 2 open. `firm` is the gate for the keyboard and clicks: the opening has been
-- open for a moment and the pointer has really moved since Super went down.

local M = { DELAY = 250, OPEN_MS = 350, IDLE_MS = 6000, FIRM_MS = 300, FIRM_PX = 24 }

function M.state() return { stage = 0 } end

function M.down(st, now)
    st.down_at, st.stage, st.moved_at, st.last = now, 0, now, nil
    st.down_p, st.open_at, st.firm = nil, nil, false
end

local function close(st)
    st.down_at, st.stage, st.down_p, st.open_at, st.firm = nil, 0, nil, nil, false
end

-- Called often (the logic's tick) with the pointer: moves the stages on, closes on idle.
function M.tick(st, now, p)
    if not st.down_at then return st end
    if not st.down_p then st.down_p = { x = p.x, y = p.y } end
    if not st.last or st.last.x ~= p.x or st.last.y ~= p.y then st.moved_at, st.last = now, { x = p.x, y = p.y } end
    if st.stage > 0 and now - st.moved_at > M.IDLE_MS then close(st); return st end
    local age = now - st.down_at
    if age < M.DELAY then st.stage = 0
    elseif age < M.DELAY + M.OPEN_MS then st.stage = 1
    else
        st.stage = 2
        if not st.open_at then st.open_at = now end
    end
    if st.stage == 2 and not st.firm and now - st.open_at >= M.FIRM_MS then
        local dx, dy = p.x - st.down_p.x, p.y - st.down_p.y
        if dx * dx + dy * dy >= M.FIRM_PX * M.FIRM_PX then st.firm = true end
    end
    return st
end

-- true once the opening is firm (see the top); false before, and after a fresh down
function M.firm(st) return st.firm == true end

-- Super let go: "tap" (before the delay: today's Super tap), "release" (a reveal was open), or nil.
-- (review I2: an up whose down never arrived — Hyprland runs the two as separate processes, which can race —
-- and a release before any stage, at whatever age, are both taps)
function M.up(st, now)
    if not st.down_at then return "tap" end
    if st.stage == 0 then close(st); return "tap" end
    return "release"
end

function M.finish(st) close(st) end

-- the events that close a reveal whatever it shows (a Super shortcut never sends Super's "up")
local CLOSE = { workspace = true, focus = true, escape = true, outside = true, idle = true }
function M.close_on(event) return CLOSE[event] == true end

return M
