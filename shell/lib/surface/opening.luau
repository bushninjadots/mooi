-- The Opening (D209): hold Super and the wallpaper opens where the pointer is. Pure: the opening's mode and
-- the target hole every program clips to. Modes: 0 closed · 1 follow (a round hole under the pointer) ·
-- 2 snapped (the hole hugs the box the pointer is near) · 3 section (40 % of the screen each way) ·
-- 4 full (the whole wallpaper). The wheel widens and narrows between them.

local M = { R = 90, SNAP = 40, MARGIN = 16, SECTION = 0.4, CORNER = 18 }
M.MODES = { closed = 0, follow = 1, snapped = 2, section = 3, full = 4 }
local MD = M.MODES

function M.state() return { mode = MD.closed, k = 0, snap = nil, step = 0 } end

function M.open(st) st.mode, st.k = MD.follow, 1 end

function M.heal(st) st.mode, st.k, st.snap, st.step = MD.closed, 0, nil, 0 end

-- distance from p to a box's edge; 0 anywhere inside it
local function edge(b, p)
    local dx = math.max(b.x - p.x, 0, p.x - (b.x + b.w))
    local dy = math.max(b.y - p.y, 0, p.y - (b.y + b.h))
    return math.sqrt(dx * dx + dy * dy)
end

function M.near(boxes, p)
    local best, bd
    for _, b in ipairs(boxes) do
        local d = edge(b, p)
        if d <= M.SNAP and (not best or d < bd or (d == bd and b.w * b.h < best.w * best.h)) then
            best, bd = b, d
        end
    end
    return best
end

function M.move(st, boxes, p)
    if st.mode ~= MD.follow and st.mode ~= MD.snapped then return end
    local b = M.near(boxes, p)
    st.snap = b
    st.mode = b and MD.snapped or MD.follow
end

function M.widen(st, scr)
    if st.mode == MD.follow or st.mode == MD.snapped then st.mode = MD.section
    elseif st.mode == MD.section then st.mode = MD.full end
end

function M.narrow(st, scr)
    if st.mode == MD.full then st.mode = MD.section
    elseif st.mode == MD.section then st.mode = st.snap and MD.snapped or MD.follow end
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function M.hole(st, p, scr)
    if st.mode == MD.full then return { x = 0, y = 0, w = scr.w, h = scr.h, r = 0 } end
    if st.mode == MD.snapped and st.snap then
        local b, m = st.snap, M.MARGIN
        return { x = b.x - m, y = b.y - m, w = b.w + 2 * m, h = b.h + 2 * m, r = M.CORNER }
    end
    if st.mode == MD.section then
        local w, h = M.SECTION * scr.w, M.SECTION * scr.h
        local cx = st.snap and st.snap.x + st.snap.w / 2 or p.x
        local cy = st.snap and st.snap.y + st.snap.h / 2 or p.y
        return { x = clamp(cx - w / 2, 0, scr.w - w), y = clamp(cy - h / 2, 0, scr.h - h), w = w, h = h, r = M.CORNER }
    end
    return { x = p.x - M.R, y = p.y - M.R, w = 2 * M.R, h = 2 * M.R, r = M.R }
end

-- three integers under 2^24 (float32 carries them whole, D124); everything clamped to what 12 bits hold
local function c12(v) return math.floor(clamp(v, 0, 4095) + 0.5) end

function M.pack(st, hole)
    local r = math.floor(clamp(hole.r, 0, 999) + 0.5)
    return c12(hole.x) * 4096 + c12(hole.y), c12(hole.w) * 4096 + c12(hole.h), st.mode * 1000 + r
end

function M.unpack(a, b, c)
    return { x = a // 4096, y = a % 4096, w = b // 4096, h = b % 4096, mode = c // 1000, r = c % 1000 }
end

-- Whether the packed triple has to reach the programs under the wallpaper: the first send, any change of mode
-- or rim, and — outside follow mode — any move of the hole. In follow mode only the pointer moved and the
-- programs already follow it themselves, so a is not sent.
function M.changed(prev, a, b, c)
    if not prev then return true end
    if prev.c ~= c then return true end
    if c // 1000 == MD.follow then return false end
    return prev.a ~= a or prev.b ~= b
end

return M
