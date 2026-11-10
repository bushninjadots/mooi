-- The node's workspace-switch styles (D250): how a change of workspace is shown on the node — a bead moving
-- round a ring, the content sliding in, a card flipping, a pulse, or the number counting. Pure: it turns the
-- workspaces involved into a direction, an offset and flags for the scene to animate, and draws nothing itself.

local M = {}

-- in the order the studio offers them; the names are the studio's
M.STYLES = { "bead", "slide", "flip", "pulse", "count" }
M.NAMES = { "Bead", "Slide", "Flip", "Pulse", "Number" }

-- how far the content slides in from when the slide style is chosen
M.SLIDE_PX = 24

local function ring(count)
    count = math.floor(tonumber(count) or 0)
    if count < 1 then return 0 end
    return count
end

-- a workspace number as a place on the ring 1..count, so a number past the ring wraps round
local function place(v, count) return ((math.floor(tonumber(v) or 1) - 1) % count) + 1 end

-- -1, 0 or 1: the shortest way round the ring. A tie (an even ring, halfway round) goes forward, and a ring
-- of one has nowhere to go.
function M.direction(from, to, count)
    count = ring(count)
    if count < 2 then return 0 end
    local diff = (place(to, count) - place(from, count)) % count
    if diff == 0 then return 0 end
    if diff * 2 <= count then return 1 end
    return -1
end

-- what the scene animates toward: the way round, the pixels the content slides in from, whether to flip or
-- pulse, and the carried number. An unknown style is a bead.
function M.plan(style, from, to, count)
    if style ~= "slide" and style ~= "flip" and style ~= "pulse" and style ~= "count" then style = "bead" end
    local dir = M.direction(from, to, count)
    local offset = 0
    if style == "slide" then offset = dir * M.SLIDE_PX end
    return {
        dir = dir,
        offset = offset,
        flip = style == "flip" and 1 or 0,
        pulse = style == "pulse" and 1 or 0,
        label = tostring(to),
    }
end

return M
