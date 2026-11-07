-- Where the Sigil's line and words go inside a host (D207). Pure.
-- The Pill's display is a 600 x 220 box under it, centred on it and kept 8 px inside the screen; inside it
-- the line takes the part its kind needs (a disc or a ring on the left with the words beside it; a card,
-- ribbon or horizon across, the words placed in or over it; the rest on the left 40 %, the words on the
-- right). Compact: the line on the left 38 %, the words from 42 % (the scene draws them there).

local M = { DW = 600, DH = 220, GAP = 10, EDGE = 8 }

function M.display_box(host, screen_w)
    local cx = host.x + host.w / 2
    local x = math.max(M.EDGE, math.min((screen_w or 1920) - M.DW - M.EDGE, math.floor(cx - M.DW / 2)))
    return { x = x, y = host.y + host.h + M.GAP, w = M.DW, h = M.DH }
end

-- the line's box and where the words start (tx, ty: the first line's left centre), for a kind in D
function M.display(kind, D)
    if kind == "disc" or kind == "ring" then
        local r = math.min(D.h * 0.42, D.w * 0.2)
        local tx = math.floor(D.x + 2 * r + 26)
        return { x = D.x, y = D.y, w = D.w, h = D.h }, tx, math.floor(D.y + D.h / 2 - 14)
    elseif kind == "card" then
        return { x = D.x + 20, y = D.y + 40, w = D.w - 40, h = D.h - 80 }, D.x + 44, D.y + 82
    elseif kind == "ribbon" then
        return { x = D.x, y = D.y + D.h / 2 - 20, w = D.w, h = 40 }, math.floor(D.x + D.w * 0.05), D.y + 40
    elseif kind == "horizon" then
        return { x = D.x + 20, y = D.y + 60, w = D.w - 40, h = D.h - 70 }, D.x + 28, D.y + 30
    end
    local lw = math.floor(D.w * 0.4)
    return { x = D.x + 20, y = D.y + 30, w = lw - 40, h = D.h - 60 }, D.x + lw + 10, math.floor(D.y + D.h / 2 - 14)
end

function M.compact(host)
    return { x = host.x + 4, y = host.y + 3, w = math.max(4, host.w * 0.38 - 4), h = math.max(4, host.h - 6) }
end

function M.glyph(host)
    return { x = host.x + 2, y = host.y + 2, w = math.max(4, host.w - 4), h = math.max(4, host.h - 4) }
end

return M
