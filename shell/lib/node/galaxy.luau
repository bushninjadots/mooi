-- The workspaces' galaxy (Super+Tab, D294): live pictures of each workspace's windows inside its tile. Pure: the
-- thumbnails service's windows (`{ id, title, app, picture }`) and Hyprland's (`hyprctl -j clients`) in; for each
-- tile, where each of its windows' pictures goes, out. Pleamar's thumbnails know nothing of workspaces, Hyprland's
-- clients know nothing of pictures: a window is the one whose app and title agree, else the next of that app.

local M = { PER_TILE = 4 }

local function low(s) return string.lower(tostring(s or "")) end

-- where n pictures go in a tile, as fractions of the space under its number: one fills it, two side by side,
-- three or four in a 2 × 2 grid; a small gap between them
function M.cells(n)
    n = math.max(0, math.min(M.PER_TILE, math.floor(tonumber(n) or 0)))
    local g = 0.03
    if n == 0 then return {} end
    if n == 1 then return { { fx = 0, fy = 0, fw = 1, fh = 1 } } end
    if n == 2 then return { { fx = 0, fy = 0, fw = 0.5 - g / 2, fh = 1 }, { fx = 0.5 + g / 2, fy = 0, fw = 0.5 - g / 2, fh = 1 } } end
    local w, h = 0.5 - g / 2, 0.5 - g / 2
    local out = {}
    for k = 0, n - 1 do out[#out + 1] = { fx = (k % 2) * (0.5 + g / 2), fy = (k // 2) * (0.5 + g / 2), fw = w, fh = h } end
    return out
end

-- each thumbnail's workspace id: an exact app-and-title match first, then the next window of the same app
function M.workspaces(thumbs, clients)
    local out, used = {}, {}
    local function try(t, exact)
        for ci, c in ipairs(type(clients) == "table" and clients or {}) do
            if not used[ci] and type(c) == "table" and type(c.workspace) == "table" and low(c.class) == low(t.app)
                and (not exact or tostring(c.title or "") == tostring(t.title or "")) then
                used[ci] = true
                return tonumber(c.workspace.id)
            end
        end
    end
    for i, t in ipairs(type(thumbs) == "table" and thumbs or {}) do
        if type(t) == "table" and tostring(t.app or "") ~= "pleamar" then out[i] = try(t, true) end
    end
    for i, t in ipairs(type(thumbs) == "table" and thumbs or {}) do
        if type(t) == "table" and out[i] == nil and tostring(t.app or "") ~= "pleamar" then out[i] = try(t, false) end
    end
    return out
end

-- the pictures the galaxy draws: for each workspace in `list` (its tile is its index from 0), up to PER_TILE of its
-- windows, each with its place in the tile; and whether any tile has a picture
function M.pictures(list, thumbs, clients, max)
    max = max or 32
    local ws = M.workspaces(thumbs, clients)
    local by = {}
    for i, t in ipairs(type(thumbs) == "table" and thumbs or {}) do
        local id = ws[i]
        if id and type(t.picture) == "string" and t.picture ~= "" then
            by[id] = by[id] or {}
            if #by[id] < M.PER_TILE then by[id][#by[id] + 1] = t end
        end
    end
    local out = {}
    for tile, w in ipairs(type(list) == "table" and list or {}) do
        local mine = by[tonumber(w.id)] or {}
        for k, c in ipairs(M.cells(#mine)) do
            if #out < max then
                out[#out + 1] = { tile = tile - 1, fx = c.fx, fy = c.fy, fw = c.fw, fh = c.fh, img = mine[k].picture }
            end
        end
    end
    return out
end

return M
