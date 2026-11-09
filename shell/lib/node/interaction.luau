-- The node and the pointer (D226, spec §5, §14). Pure. Inside the node's reach it wakes (near); resting there it
-- unfolds (hover, after the sensitivity's wait); leaving, it stays a moment, then retracts; then a cooldown, so the
-- pointer passing again does not flap it open. `side`: where the pointer came in, so expansion leans that way.

local M = { REACH = 16, LEAVE_MS = 600, COOLDOWN_MS = 400 }
M.HOVER_MS = { low = 600, normal = 250, high = 120 }

function M.new() return { near = false, since = nil, hover = false, left_at = nil, cool_till = 0, side = 0 } end

local function inside(p, b, m)
    return p.x >= b.x - m and p.x <= b.x + b.w + m and p.y >= b.y - m and p.y <= b.y + b.h + m
end

function M.pointer(ix, p, body, now, sensitivity)
    if sensitivity == "off" then ix.near, ix.hover = false, false; return { near = false, hover = false, side = 0 } end
    local wait = M.HOVER_MS[sensitivity] or M.HOVER_MS.normal
    -- once open, the reach is wider (hysteresis): the pointer may wander over what unfolded
    local reach = ix.hover and M.REACH + 40 or M.REACH
    if inside(p, body, reach) then
        if not ix.near then
            ix.near, ix.since = true, now
            ix.side = (p.x < body.x + body.w / 2) and -1 or 1
        end
        ix.left_at = nil
        if not ix.hover and now >= ix.cool_till and now - ix.since >= wait then ix.hover = true end
    else
        if ix.near then ix.near, ix.left_at = false, now end
        if ix.hover and ix.left_at and now - ix.left_at > M.LEAVE_MS then
            ix.hover = false
            ix.cool_till = now + M.COOLDOWN_MS
        end
    end
    return { near = ix.near, hover = ix.hover, side = ix.side }
end

return M
