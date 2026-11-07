-- The morph (D204): `pill.shape = morph`. The Pill's silhouette is twelve control points that the frame
-- springs to and joins with quadratic curves through their midpoints (a closed quadratic B-spline), so
-- one outline flows between forms instead of one object being swapped for another (D187: one capsule).
-- Pure: what the outline's points are for a form, and which form the Pill's state asks for.
--
-- The points go round clockwise from the top-left corner: TL, four along the top, TR, BR, four along the
-- bottom (right to left), BL. With the corners as control points and the first top point 2r in from the
-- corner, the curve through the midpoints rounds each corner with radius r and runs straight between:
-- a capsule when r is half its height, a disc when it is also as wide as it is high.
--
-- Forms: capsule (idle and everything else), blob (music playing: the frame ripples the edges with the
-- bass along each point's normal), drop (a notice: a bead hangs from the middle of the foot), bead
-- (tucked away: a small disc where it rests), none (vanished: every point at the centre, nothing drawn).

local M = {
    N = 12,
    FORMS = { "capsule", "blob", "drop", "bead", "none" },
    BEAD = 14,            -- the tucked disc, as the dot shape's (lib/pill.DOT)
    DROP = 0.55,          -- how far the notice's bead hangs below the foot, in heights
    -- px the blob's edge moves at full bass. 0 since D204's live measure: rippled, the frame redraws its
    -- top strip 30 times a second at 60–90 ms a frame (a core, ~12 fps); still, the morph costs only while
    -- it flows. The frame's ripple stays wired: a positive value turns it back on.
    RIPPLE = 0,
    SWELL = 3,            -- px the blob's foot is fuller in the middle, sound or not
    OFF = -400,           -- where a collapsed outline sits (off the strip; a zero-area path draws nothing)
    MAX_W = 800,          -- the widest it is drawn: the frame holds it only in the tiles within 420 px of the middle
}

-- each point's outward normal (unit), in order; the corners at 45°
local D = math.sqrt(0.5)
M.NORMALS = {
    { -D, -D }, { 0, -1 }, { 0, -1 }, { 0, -1 }, { 0, -1 }, { D, -D },
    { D, D }, { 0, 1 }, { 0, 1 }, { 0, 1 }, { 0, 1 }, { -D, D },
}

-- the capsule's control points for a box (x, y, w, h) with corner radius r (clamped to fit)
local function capsule(x, y, w, h, r)
    w, h = math.max(0, w), math.max(0, h)
    r = math.max(0, math.min(r or h / 2, h / 2, w / 2))
    local pts = { { x, y } }
    local a, b = x + 2 * r, x + w - 2 * r
    for k = 0, 3 do pts[#pts + 1] = { a + (b - a) * k / 3, y } end
    pts[#pts + 1] = { x + w, y }
    pts[#pts + 1] = { x + w, y + h }
    for k = 0, 3 do pts[#pts + 1] = { b + (a - b) * k / 3, y + h } end
    pts[#pts + 1] = { x, y + h }
    return pts
end

-- The outline for a form in the box (x, y, w, h) with the bar's corner radius r (the module height's
-- half; the attached Pill's box starts above the screen, so its top corners are hidden in the band).
-- Returns { pts = { {x, y} × 12 }, ripple = px } — ripple is the bass's reach along the normals.
function M.points(form, x, y, w, h, r)
    x, y, w, h = tonumber(x) or 0, tonumber(y) or 0, tonumber(w) or 0, tonumber(h) or 0
    r = tonumber(r) or h / 2
    if form == "none" or w <= 0 or h <= 0 then
        -- gathered at the centre of the module (so the springs shrink it in place and grow it back from
        -- there), or off the strip when there is no box at all
        local cx, cy = M.OFF, M.OFF
        if h > 0 then cx, cy = x + math.max(0, w) / 2, y + h - r end
        local pts = {}
        for i = 1, M.N do pts[i] = { cx, cy } end
        return { pts = pts, ripple = 0 }
    end
    if form == "bead" then
        local d = math.min(M.BEAD, w)
        local foot = y + h
        local cx, cy = x + w / 2, foot - r      -- centred in the module's height, as the dot is
        return { pts = capsule(cx - d / 2, cy - d / 2, d, d, d / 2), ripple = 0 }
    end
    local pts = capsule(x, y, w, h, r)
    if form == "drop" then
        -- the four bottom points (8–11, right to left) gathered to the middle, the inner two pulled down:
        -- the foot runs straight to a narrow bead hanging under the centre
        local hang = math.min(r * 2, h) * M.DROP
        local cx = x + w / 2
        local half = math.min(r * 1.5, w / 2 - r)
        pts[8] = { cx + half, y + h }
        pts[9] = { cx + r * 0.5, y + h + hang }
        pts[10] = { cx - r * 0.5, y + h + hang }
        pts[11] = { cx - half, y + h }
        return { pts = pts, ripple = 0 }
    end
    if form == "blob" then
        -- fuller in the middle of the foot: the music's form, still
        pts[9][2] = pts[9][2] + M.SWELL
        pts[10][2] = pts[10][2] + M.SWELL
        return { pts = pts, ripple = M.RIPPLE }
    end
    return { pts = pts, ripple = 0 }
end

-- Which form the Pill's state asks for. r: lib/pill.compute's result; o: { still = reduced motion or the
-- saver, board = its board is open }. Still, it keeps the capsule (and the bead, a size, not a motion).
function M.form(r, o)
    o = type(o) == "table" and o or {}
    if type(r) ~= "table" then return "capsule" end
    if r.vanish then return "none" end
    if r.hidden then return "bead" end
    if o.board or o.still then return "capsule" end
    if r.main == "music" then return "blob" end
    if r.main == "notify" then return "drop" end
    return "capsule"
end

-- The quadratic B-spline the frame draws, as pleamar path steps for points named by `px(i)`, `py(i)`
-- (1-based): from the midpoint of the last and the first, a curve to each next midpoint via each point.
-- Used by tools/gen-frame.py's mirror and by the tests to check the outline is closed and smooth.
function M.steps(pts)
    local n = #pts
    local function mid(a, b) return { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 } end
    local out = { { "move", mid(pts[n], pts[1]) } }
    for i = 1, n do
        out[#out + 1] = { "curve", mid(pts[i], pts[i % n + 1]), pts[i] }
    end
    return out
end

return M
