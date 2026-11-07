-- The desk's workspace viewer (D176): each workspace as a live miniature in the board's first card.
-- Pure: Hyprland's `clients` are grouped by workspace, each workspace's windows are placed in its card
-- (relative to the screen, so a window sits where it really is), and the pictures the thumbnails service
-- lends are matched to the windows by their class and title. The logic only runs hyprctl and watches the
-- service; this decides what is drawn, so it is tested without a compositor.

local M = {
    MAX = 3,          -- cards in the viewer at once
    WIN_MAX = 8,      -- windows drawn in a card
    CARD_W = 190, CARD_H = 140,
    MIN_W = 0.04,     -- a window smaller than this of the screen still gets a rectangle to see
}

-- Group Hyprland's clients (as `hyprctl -j clients` gives them) by their workspace: one row per
-- workspace, its windows in the order Hyprland lists them, sorted by workspace id.
function M.group(clients, active)
    local by, rows = {}, {}
    for _, c in ipairs(type(clients) == "table" and clients or {}) do
        local ws = type(c) == "table" and type(c.workspace) == "table" and tonumber(c.workspace.id) or nil
        if ws then
            local row = by[ws]
            if not row then
                row = { id = ws, n = 0, wins = {}, active = ws == (tonumber(active) or -1) }
                by[ws] = row
                rows[#rows + 1] = row
            end
            row.n = row.n + 1
            local at, size = c.at or {}, c.size or {}
            if row.n <= M.WIN_MAX then
                row.wins[#row.wins + 1] = {
                    class = tostring(c.class or ""), title = tostring(c.title or ""),
                    x = tonumber(at[1]) or 0, y = tonumber(at[2]) or 0,
                    w = tonumber(size[1]) or 0, h = tonumber(size[2]) or 0,
                    focused = tonumber(c.focusHistoryID) == 0,
                }
            end
        end
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

-- The cards shown, from `first` (0-based) on, three at most: each window's place and size as a share of
-- the screen (0 … 1), so the scene draws it where it really is in its miniature. `first` is clamped so
-- the strip never runs past the last card.
function M.cards(rows, first, screen_w, screen_h, count)
    local sw = math.max(1, tonumber(screen_w) or 1920)
    local sh = math.max(1, tonumber(screen_h) or 1080)
    local want = math.max(1, math.min(tonumber(count) or M.MAX, M.MAX))
    local out = {}
    rows = type(rows) == "table" and rows or {}
    if #rows == 0 then return out end
    local start = math.max(1, math.min((tonumber(first) or 0) + 1, math.max(1, #rows - want + 1)))
    for k = start, math.min(#rows, start + want - 1) do
        local r = rows[k]
        local card = { id = r.id, slot = k - start, n = r.n, active = r.active == true, wins = {} }
        for _, w in ipairs(r.wins) do
            card.wins[#card.wins + 1] = {
                nx = math.max(0, math.min(1, w.x / sw)),
                ny = math.max(0, math.min(1, w.y / sh)),
                nw = math.max(M.MIN_W, math.min(1, w.w / sw)),
                nh = math.max(M.MIN_W, math.min(1, w.h / sh)),
                class = w.class, title = w.title, focused = w.focused == true,
            }
        end
        out[#out + 1] = card
    end
    return out
end

-- For each window in `wins`, the picture the thumbnails service has for it (matched by its class and
-- title, as the notch does), or "" where it has none yet.
function M.picture(wins, thumbs)
    local by = {}
    for _, t in ipairs(type(thumbs) == "table" and thumbs or {}) do
        if type(t) == "table" and type(t.picture) == "string" and t.picture ~= "" then
            by[tostring(t.app or "") .. "\n" .. tostring(t.title or "")] = t.picture
        end
    end
    local out = {}
    for i, w in ipairs(type(wins) == "table" and wins or {}) do
        out[i] = by[(w.class or "") .. "\n" .. (w.title or "")] or ""
    end
    return out
end

return M
