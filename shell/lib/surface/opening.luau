-- The Opening (D209): hold Super and the wallpaper opens where the pointer is. Pure: the opening's mode and
-- the target hole every program clips to. Modes: 0 closed · 1 follow (a round hole under the pointer) ·
-- 2 snapped (the hole hugs the box the pointer is near) · 3 section (40 % of the screen each way) ·
-- 4 full (the whole wallpaper). The wheel widens and narrows between them.
-- Two flags ride with the mode (the spec §4): `faint` — a fresh opening stays faint until it snaps to a thing,
-- the pointer has really moved (the reveal's `firm`) or the wheel turns, so a slow Super+key shortcut does no
-- harm; `away` — the pointer is over the bar, where there is no opening (the bar answers as today), so the
-- programs under the wallpaper are told it is closed until the pointer comes back down.

-- DWELL (D218): how long the pointer rests on a widget before the hole hugs it, so a sweep across the widgets
-- is followed rather than caught by each one in turn
local M = { R = 90, SNAP = 40, MARGIN = 16, SECTION = 0.4, CORNER = 18, FAINT = 0.45, DWELL = 260 }
M.MODES = { closed = 0, follow = 1, snapped = 2, section = 3, full = 4 }
local MD = M.MODES

function M.state() return { mode = MD.closed, k = 0, snap = nil, step = 0, at = nil, faint = false, away = false } end

function M.open(st) st.mode, st.k, st.at, st.faint, st.away = MD.follow, 1, nil, true, false end

function M.heal(st)
    st.mode, st.k, st.snap, st.step, st.at, st.faint, st.away = MD.closed, 0, nil, 0, nil, false, false
end

-- the opening is firm: the reveal says the pointer has moved, a key walked to a thing, or a drag began
function M.firm(st) st.faint = false end

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

-- `bar_h`: the bar's strip at the top of the screen; a follow or snapped opening goes away while the pointer
-- is in it (a section and the Overview stay where they are — they do not follow).
-- `now` (ms, D218): with a clock, a widget not yet hugged is hugged only once the pointer has rested near it for
-- DWELL; without one (the keyboard's walk, the old callers) at once.
function M.move(st, boxes, p, bar_h, now)
    if st.mode ~= MD.follow and st.mode ~= MD.snapped then return end
    if bar_h and p.y < bar_h then
        st.snap, st.mode, st.away, st.cand = nil, MD.follow, true, nil
        return
    end
    st.away = false
    local near = M.near(boxes, p)
    local b = near
    if near and now and not (st.snap and st.snap.id == near.id) then
        if not (st.cand and st.cand.id == near.id) then st.cand, st.cand_at = near, now end
        if now - st.cand_at < M.DWELL then b = nil end
    end
    if not near then st.cand = nil end
    st.snap = b
    st.mode = b and MD.snapped or MD.follow
    if b then st.faint = false end
end

-- `p` (the pointer at the moment the wheel turned) freezes a section where it opened: the hole no longer
-- follows the pointer, so a section that is not moving sends nothing to the programs under the wallpaper.
function M.widen(st, scr, p)
    st.faint = false
    if st.away then return end
    if st.mode == MD.follow or st.mode == MD.snapped then
        st.mode = MD.section
        st.at = p and { x = st.snap and st.snap.x + st.snap.w / 2 or p.x,
                        y = st.snap and st.snap.y + st.snap.h / 2 or p.y } or nil
    elseif st.mode == MD.section then
        st.mode, st.at = MD.full, nil
    end
end

function M.narrow(st, scr)
    st.at = nil
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
        local cx = st.at and st.at.x or (st.snap and st.snap.x + st.snap.w / 2 or p.x)
        local cy = st.at and st.at.y or (st.snap and st.snap.y + st.snap.h / 2 or p.y)
        return { x = clamp(cx - w / 2, 0, scr.w - w), y = clamp(cy - h / 2, 0, scr.h - h), w = w, h = h, r = M.CORNER }
    end
    return { x = p.x - M.R, y = p.y - M.R, w = 2 * M.R, h = 2 * M.R, r = M.R }
end

-- three integers under 2^24 (float32 carries them whole, D124); everything clamped to what 12 bits hold.
-- c = mode * 1000 + (500 while faint) + rim (0 … 499); an opening that is away is sent as closed.
local function c12(v) return math.floor(clamp(v, 0, 4095) + 0.5) end

-- the mode the programs under the wallpaper are told (away is closed for them)
function M.shown(st) return st.away and MD.closed or st.mode end

function M.pack(st, hole)
    local r = math.floor(clamp(hole.r, 0, 499) + 0.5)
    local mode = M.shown(st)
    local faint = (st.faint and mode ~= MD.closed) and 500 or 0
    return c12(hole.x) * 4096 + c12(hole.y), c12(hole.w) * 4096 + c12(hole.h), mode * 1000 + faint + r
end

function M.unpack(a, b, c)
    local rest = c % 1000
    return { x = a // 4096, y = a % 4096, w = b // 4096, h = b % 4096, mode = c // 1000,
             faint = rest >= 500, r = rest % 500 }
end

-- Whether the packed triple has to reach the programs under the wallpaper: the first send, any change of mode
-- or rim, any move of the hole. (D218: in follow mode too — the programs used to follow their own cursor, which
-- stands still while the pointer is over a window or any surface but theirs; mooi-surface reads the pointer from
-- Hyprland now and sends the hole.)
function M.changed(prev, a, b, c)
    if not prev then return true end
    if prev.c ~= c then return true end
    return prev.a ~= a or prev.b ~= b
end

return M
