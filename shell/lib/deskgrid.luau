-- The desk (D175): the Pill board's first card — its core as a grid of tiles the owner chooses. Pure:
-- each tile the owner switched on is placed in reading order, two a row (296 × 76, an 8 px gap), and
-- anything it does not know, a duplicate, or a fifth tile is dropped rather than drawn over another.
-- The core is 608 × 160, so four tiles are two rows of two with 8 px round them.

local M = {
    COLS = 2,
    CELL_W = 296, CELL_H = 76, GAP = 8, H = 160,
    MAX = 4,
    -- the tiles, in the order they sit (their number is the scene's: ui/pillboard.plm's DeskTile)
    TILES = { clock = 0, playing = 1, diagnostics = 2, calendar = 3 },
    -- the settings that switch them on, in the same order (pill.desk_*)
    ON = { "clock", "playing", "diagnostics", "calendar" },
}

-- The tiles to draw: the ids switched on, duplicates and unknowns gone, `MAX` at most.
function M.chosen(on)
    on = type(on) == "table" and on or {}
    local out, seen = {}, {}
    for _, id in ipairs(M.ON) do
        if on[id] ~= false and not seen[id] then out[#out + 1] = id; seen[id] = true end
    end
    return out
end

-- Where each of them sits: reading order, two a row, a gap between them; a tile the owner made `wide`
-- takes the whole row; a fifth tile, or one that no longer fits the core, is dropped rather than drawn
-- over another.
function M.place(ids, sizes)
    sizes = type(sizes) == "table" and sizes or {}
    local out, seen = {}, {}
    local row, used = 0, 0            -- the row being filled, and the cells it holds (0 … 2)
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        if #out >= M.MAX then break end
        if M.TILES[id] ~= nil and not seen[id] then
            local wide = sizes[id] == "wide"
            if wide and used > 0 then row, used = row + 1, 0 end
            local y = row * (M.CELL_H + M.GAP)
            if y + M.CELL_H > M.H then break end      -- the core is full: it is not drawn
            seen[id] = true
            out[#out + 1] = { id = id, k = M.TILES[id],
                              x = wide and 0 or (used % 2) * (M.CELL_W + M.GAP),
                              y = y, w = wide and (M.CELL_W * 2 + M.GAP) or M.CELL_W, h = M.CELL_H }
            used = used + (wide and 2 or 1)
            if used >= 2 then row, used = row + 1, 0 end
        end
    end
    return out
end

return M
