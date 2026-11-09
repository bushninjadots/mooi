-- What lives below (D209, D215): the subsurface's arrangements and the boxes the opening snaps to. Since D215 the
-- things below are mooi's widgets (lib/wbelow places them); this keeps the maths they share with the opening.
-- Pure. Boxes are screen pixels { x, y, w, h }.

local M = { BOTTOM = 96 }
M.LAYOUTS = { "arc", "row", "grid", "calm" }
M.DEFAULT_LAYOUT = "arc"

local function round(v) return math.floor(v + 0.5) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function num(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- D215: any list of boxes laid out by an arrangement (the widgets below are what is arranged now). Items keep
-- their order and size; they flow into rows that fit the width (gaps of 24 px, a 48 px margin), and the
-- arrangement says where the rows go: `arc` from the top band, each row dipping at its ends; `row` the rows
-- centred as one block; `grid` rows from the left; `calm` packed from the bottom up. Every box ends wholly on
-- the screen (a screen too small for them all overlaps rather than spills).
function M.arrange(items, scr, layout)
    local W, H = scr.w, scr.h
    local GAPX, GAPY, SIDE = 24, 24, 48
    local DIP = layout == "arc" and math.floor(0.03 * H + 0.5) or 0
    local rows, cur, cw = {}, {}, 0
    for _, it in ipairs(items or {}) do
        local w = math.min(it.w, W)
        if #cur > 0 and cw + GAPX + w > W - 2 * SIDE then rows[#rows + 1] = cur; cur, cw = {}, 0 end
        cw = cw + (#cur > 0 and GAPX or 0) + w
        cur[#cur + 1] = it
    end
    if #cur > 0 then rows[#rows + 1] = cur end
    local heights, total = {}, 0
    for i, r in ipairs(rows) do
        local h = 0
        for _, it in ipairs(r) do h = math.max(h, it.h) end
        heights[i] = h + DIP
        total = total + heights[i] + (i > 1 and GAPY or 0)
    end
    local y
    if layout == "row" then y = (H - total) / 2
    elseif layout == "calm" then y = H - M.BOTTOM - total
    else y = 0.12 * H end
    local out = {}
    for i, r in ipairs(rows) do
        local rw = 0
        for j, it in ipairs(r) do rw = rw + it.w + (j > 1 and GAPX or 0) end
        local x = layout == "grid" and SIDE or (W - rw) / 2
        for j, it in ipairs(r) do
            local t = #r > 1 and ((j - 1) / (#r - 1) * 2 - 1) or 0
            local w, h = math.min(it.w, W), math.min(it.h, H)
            local px = round(clamp(x, 0, math.max(0, W - w)))
            local py = round(clamp(y + DIP * t * t, 0, math.max(0, H - h)))
            out[it.id] = { x = px, y = py, w = w, h = h }
            x = x + it.w + GAPX
        end
        y = y + heights[i] + GAPY
    end
    return out
end

-- Every box the opening may snap to (lib/surface/opening `near`): the places given (none since D215), BMO where
-- he stands (`bmo`, his own report; none while he is away or not below), then each widget that lives under the
-- wallpaper (widgets.json is in the widgets surface's pixels, which start below the bar's strip: bar_h down;
-- one kept above the wallpaper is not here).
function M.boxes(places, widgets, bar_h, bmo)
    local out = {}
    for id, p in pairs(type(places) == "table" and places or {}) do
        if num(p.x) and num(p.y) and num(p.w) and num(p.h) then out[#out + 1] = { id = id, x = p.x, y = p.y, w = p.w, h = p.h } end
    end
    if type(bmo) == "table" and num(bmo.x) and num(bmo.y) and num(bmo.w) and num(bmo.h) and bmo.w > 0 then
        out[#out + 1] = { id = "bmo", x = bmo.x, y = bmo.y, w = bmo.w, h = bmo.h }
    end
    for _, w in ipairs(type(widgets) == "table" and widgets or {}) do
        if type(w) == "table" and w.above ~= true and num(w.x) and num(w.y) and num(w.w) and num(w.h) then
            out[#out + 1] = { id = "w:" .. tostring(w.id), x = w.x, y = w.y + (bar_h or 0), w = w.w, h = w.h }
        end
    end
    return out
end

return M
