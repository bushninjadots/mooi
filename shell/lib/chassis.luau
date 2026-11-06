-- The chassis (D164, stage 1): the bar's pieces as one shape model, for mooi-frame to draw in every
-- mode. Pure: layout (bar-geo.json, written by shell/bar.luau) and look (settings) in, rectangles out.
--
-- Before this, the frame re-derived the pieces in its scene from per-mode formulas, and the bar drew
-- its own plates when the frame was not drawing them: three bottom edges (y 31, 34, 37 on 2026-11-06)
-- and, in islands mode, pieces that ran up into the screen's top so every gap between two groups read
-- as an empty tab. Here islands float as plates on the bar's row and never touch the band; full joins
-- the band; notch hangs from the top, as its design intends. One foot in every case.

local M = { SLOTS = 20, NOTCH_PAD = 10, BLEND = 12 }

-- `s` is validated settings (lib/config). The row's top is theme/ferrolume.plm's fl.top.
function M.look(s)
    local b, f = s.bar, s.frame
    local notch = b.mode == "notch"
    local top = b.offset + (notch and 6 or (b.rail and 15 or 8))
    local band = f.on == true
    return {
        mode = b.mode, band = band, top = top, mod_h = b.height, radius = b.radius,
        n_pad = M.NOTCH_PAD, n_r = b.radius + 4,
        n_b = band and (top + b.height + 1) or (top + b.height + 6),
        offset = b.offset, screen_w = 1920,
        band_w = band and f.band or 0, frame_r = f.radius, reach = f.reach * 1.6,
    }
end

local function span(p)
    if type(p) ~= "table" then return 0, 0 end
    return tonumber(p.x) or 0, tonumber(p.w) or 0
end

-- The pieces, in slot order, at most SLOTS: { x, y, w, h, r, k } (k: the blend radius with the band).
function M.pieces(geo, look)
    geo = type(geo) == "table" and geo or {}
    local out = {}
    local function add(x, y, w, h, r, k)
        if w > 0 and h > 0 and #out < M.SLOTS then out[#out + 1] = { x = x, y = y, w = w, h = h, r = r, k = k } end
    end
    local foot = look.top + look.mod_h
    if look.mode == "full" then
        local x, w = span(geo.panel)
        local y = look.band and -40 or look.top
        if w > 0 then add(x, y, w, foot - y, look.radius, M.BLEND) end
    elseif look.mode == "notch" then
        local y = look.band and -40 or look.offset
        for _, side in ipairs({ "left", "center", "right" }) do
            local x, w = span(geo[side])
            if w > 0 then add(x - look.n_pad, y, w + 2 * look.n_pad, look.n_b - y, look.n_r, M.BLEND) end
        end
    else
        for _, isl in ipairs(type(geo.islands) == "table" and geo.islands or {}) do
            local x, w = span(isl)
            if w > 0 then add(x - 3, look.top, w + 6, look.mod_h, look.radius, 0) end
        end
    end
    return out
end

function M.foot(look)
    return look.mode == "notch" and look.n_b or (look.top + look.mod_h)
end

-- Does a piece sit in that screen corner's reach? Then the frame's corner turns at the piece's foot.
function M.covers(pieces, look, side)
    local cr = look.band_w + look.frame_r + look.reach + M.BLEND
    for _, p in ipairs(pieces or {}) do
        if side == "left" and p.x <= cr then return true end
        if side == "right" and p.x + p.w >= look.screen_w - cr then return true end
    end
    return false
end

return M
