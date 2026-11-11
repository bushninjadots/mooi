-- The chassis (D164, stage 1): the bar's pieces as one shape model, for mooi-frame to draw in every
-- mode. Pure: layout (bar-geo.json, written by shell/bar.luau) and look (settings) in, rectangles out.
--
-- Before this, the frame re-derived the pieces in its scene from per-mode formulas, and the bar drew
-- its own plates when the frame was not drawing them: three bottom edges (y 31, 34, 37 on 2026-11-06)
-- and, in islands mode, pieces that ran up into the screen's top so every gap between two groups read
-- as an empty tab. Here islands float as plates on the bar's row and never touch the band; full joins
-- the band; notch hangs from the top, as its design intends. One foot in every case.

local M = { SLOTS = 20, NOTCH_PAD = 10, BLEND = 12, AIR = 3, NO_CAP = 999 }

-- `s` is validated settings (lib/config). The row's top is theme/ferrolume.plm's fl.top.
function M.look(s)
    local b, f = s.bar, s.frame
    local notch = b.mode == "notch"
    local top = b.offset + (notch and 6 or (b.rail and 15 or 8))
    local band = f.on == true
    local band_w = band and f.band or 0
    -- D166: with the frame on, islands may attach to it (frame.islands = attach): the band comes down to
    -- the islands' top and each hangs from it, so the gaps between them are recesses in one body, not tabs
    -- Pill mode's side groups are islands too (D168)
    local isl = b.mode == "islands" or b.mode == "pill"
    local attach = band and isl and f.islands == "attach"
    local floating = isl and not attach
    -- Floating plates keep AIR px between them and the band: a band thicker than the room above the
    -- row is held thinner along the top (it fused with every plate otherwise; review I2).
    local top_band = attach and top or (floating and math.min(band_w, math.max(0, top - M.AIR)) or band_w)
    return {
        mode = b.mode, band = band, attach = attach, top = top, mod_h = b.height, radius = b.radius,
        n_pad = M.NOTCH_PAD, n_r = b.radius + 4,
        -- the notch's foot: the windows' reserve line (st_res) with the band or without, so toggling the
        -- frame does not move it (it was 5 px lower without the band before D164)
        n_b = top + b.height + 1,
        offset = b.offset, screen_w = 1920,
        band_w = band_w, top_band = top_band, frame_r = f.radius, reach = f.reach * 1.6,
        -- how far the band's top edge may swell: down to AIR px above floating plates, or freely where
        -- the pieces join the band (full, notch)
        top_room = attach and 0 or (floating and math.max(0, top - top_band - M.AIR) or M.NO_CAP),
    }
end

local function span(p)
    if type(p) ~= "table" then return 0, 0 end
    return tonumber(p.x) or 0, tonumber(p.w) or 0
end

-- `looks` (optional): { [island index] = lib/modlook's look } for floating islands; their own fill, rounding,
-- outline, glow and colour ride on the piece. Without one the frame draws the style's.
-- The pieces, in slot order, at most SLOTS: { x, y, w, h, r, k, j } (k: the blend radius with the band;
-- j: joined to it).
function M.pieces(geo, look, looks)
    geo = type(geo) == "table" and geo or {}
    local out = {}
    -- j: joined to the band (full, notch); a floating plate is not
    local function add(x, y, w, h, r, k, j)
        if w > 0 and h > 0 and #out < M.SLOTS then out[#out + 1] = { x = x, y = y, w = w, h = h, r = r, k = k, j = j == true } end
    end
    local foot = look.top + look.mod_h
    if look.mode == "full" then
        local x, w = span(geo.panel)
        if w > 0 then
            if look.band then
                -- with the frame the full bar IS its top: edge to edge, into the band's sides, so the two
                -- never meet in a notch, and the frame's inner corners round off at the bar's foot
                add(0, -40, look.screen_w, foot + 40, 0, 0, true)
            else
                add(x, look.top, w, look.mod_h, look.radius, M.BLEND, false)
            end
        end
    elseif look.mode == "notch" then
        -- hanging from above the screen whether the band is on or not, as the bar's own notch does, and
        -- never past the screen's sides (review I5)
        for _, side in ipairs({ "left", "center", "right" }) do
            local x, w = span(geo[side])
            if w > 0 then
                local a = math.max(0, x - look.n_pad)
                local e = math.min(look.screen_w, x + w + look.n_pad)
                add(a, -40, e - a, look.n_b + 40, look.n_r, M.BLEND, true)
            end
        end
    else
        for i, isl in ipairs(type(geo.islands) == "table" and geo.islands or {}) do
            local x, w = span(isl)
            if w > 0 then
                if look.attach then
                    -- rounded at the foot as any plate; a small fillet (8) where it meets the band
                    add(x - 3, -40, w + 6, foot + 40, look.radius, 8, true)
                else
                    add(x - 3, look.top, w + 6, look.mod_h, look.radius, 0, false)
                    local lk = type(looks) == "table" and looks[i] or nil
                    if lk and #out > 0 then
                        local p = out[#out]
                        p.r, p.fill, p.outline, p.glow, p.colour = lk.r or p.r, lk.fill, lk.outline, lk.glow, lk.colour
                    end
                end
            end
        end
        -- (D227: no Pill capsule, moons or extra pills — in Pill mode the node stands at the top centre)
    end
    -- D257: the node as a notch is a piece of this body too — hung from above the screen, melted into the band
    -- with the same fillet as the bar's notches, so the frame and the notch are one thing (node-geo.json)
    local nd = type(geo.node) == "table" and geo.node or nil
    if nd then
        local x, w, h = tonumber(nd.x) or 0, tonumber(nd.w) or 0, tonumber(nd.h) or 0
        if w > 0 and h > 0 then add(math.max(0, x), -40, math.min(look.screen_w, x + w) - math.max(0, x), h + 40, tonumber(nd.r) or 12, M.BLEND, true) end
        -- D310: the corner notches too — each hung from above and run out past its side, so it joins the top band
        -- and the side band at once and the frame's corner turns at its foot (`covers`), as Minflair's do
        for _, side in ipairs({ "left", "right" }) do
            local c = type(nd[side]) == "table" and nd[side] or nil
            local cw, ch = c and tonumber(c.w) or 0, c and tonumber(c.h) or 0
            if cw > 0 and ch > 0 then
                local cx = side == "left" and -40 or (look.screen_w - cw)
                add(cx, -40, cw + 40, ch + 40, 12, M.BLEND, true)
            end
        end
    end
    return out
end

function M.foot(look)
    return look.mode == "notch" and look.n_b or (look.top + look.mod_h)
end

-- Is that screen corner within reach of the piece? (its round, the side's swing and the fillet)
local function near(p, look, side)
    local cr = look.band_w + look.frame_r + look.reach + M.BLEND
    if side == "left" then return p.x <= cr end
    return p.x + p.w >= look.screen_w - cr
end

-- Does a piece joined to the band sit in that screen corner's reach? Then the frame's corner turns at
-- the piece's foot. A floating plate (j false) never does: it would pull the band down over it. With the
-- band off there is no corner to turn (review I4).
function M.covers(pieces, look, side)
    if not look.band then return false end
    for _, p in ipairs(pieces or {}) do
        if p.j and near(p, look, side) then return true end
    end
    return false
end

-- The largest round that corner may have: a floating plate in its reach caps it so the round stops
-- 2 px above the plate's top (review I1); NO_CAP otherwise.
function M.corner_cap(pieces, look, side)
    local cap = M.NO_CAP
    for _, p in ipairs(pieces or {}) do
        if not p.j and near(p, look, side) then cap = math.min(cap, math.max(0, p.y - (look.top_band or look.band_w) - 2)) end
    end
    return cap
end

return M
