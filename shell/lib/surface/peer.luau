-- Peering and burying (the Subsurface spec §8, phase 4; D224). Pure.
-- Peering: Super held over a window with another behind it under the pointer — the one in front and the one behind
-- (Hyprland's stacking as the spec reads it: a fullscreen window over its workspace, floating over tiled, the focused
-- over the rest). Burying: a window sent to `special:mooi-buried` leaves a tile under the wallpaper where the pointer
-- was; the tiles are kept (surface.json `buried`), eight at most, one per window, and a window that closes takes
-- its tile with it.

local M = { TILE_W = 240, TILE_H = 150, MAX = 8 }

local function num(v) return type(v) == "number" and v == v end
local function addr_ok(a) return type(a) == "string" and a:match("^0x%x+$") ~= nil end

-- how far in front a window is: fullscreen, then floating, then tiled; the more recently focused first
local function rank(c)
    local r = 1e6
    if (tonumber(c.fullscreen) or 0) > 0 then r = 3e6 elseif c.floating then r = 2e6 end
    return r - (tonumber(c.focusHistoryID) or 999)
end

-- the windows of workspace `ws` under the pointer `p` (on the monitor's coordinates), the front one first
function M.stack_at(clients, ws, mon, p)
    local ox, oy = (mon and tonumber(mon.x)) or 0, (mon and tonumber(mon.y)) or 0
    local out = {}
    for _, c in ipairs(type(clients) == "table" and clients or {}) do
        if type(c) == "table" and c.mapped ~= false and c.hidden ~= true and type(c.workspace) == "table" and c.workspace.id == ws
            and type(c.at) == "table" and type(c.size) == "table" then
            local x, y = (tonumber(c.at[1]) or 0) - ox, (tonumber(c.at[2]) or 0) - oy
            local w, h = tonumber(c.size[1]) or 0, tonumber(c.size[2]) or 0
            if p.x >= x and p.x <= x + w and p.y >= y and p.y <= y + h then
                out[#out + 1] = { address = c.address, class = c.class, title = c.title, x = x, y = y, w = w, h = h, rank = rank(c) }
            end
        end
    end
    table.sort(out, function(a, b) return a.rank > b.rank end)
    return out
end

-- the window in front under the pointer and the one behind it (nil, nil over no window; front, nil with none behind)
function M.peer(clients, ws, mon, p)
    local s = M.stack_at(clients, ws, mon, p)
    return s[1], s[2]
end

-- a window's live picture in the thumbnails service: by app and title, else by app
function M.thumb_for(thumbs, c)
    if type(thumbs) ~= "table" or type(c) ~= "table" then return nil end
    local app = string.lower(tostring(c.class or ""))
    local by_app
    for _, t in ipairs(thumbs) do
        if type(t) == "table" and string.lower(tostring(t.app or "")) == app and app ~= "" then
            if t.title == c.title then return t.id end
            by_app = by_app or t.id
        end
    end
    return by_app
end

-- the tiles, read back valid
function M.read(list)
    local out = {}
    for _, t in ipairs(type(list) == "table" and list or {}) do
        if type(t) == "table" and addr_ok(t.address) and num(t.x) and num(t.y) and #out < M.MAX then
            out[#out + 1] = { address = t.address, class = tostring(t.class or ""), title = tostring(t.title or ""),
                              x = t.x, y = t.y, w = num(t.w) and t.w or M.TILE_W, h = num(t.h) and t.h or M.TILE_H }
        end
    end
    return out
end

-- a window buried at `p`: its tile centred there, on the screen; one per window (buried again, it moves); the
-- oldest let go past eight
function M.bury(list, c, p, scr)
    local W, H = tonumber(scr and scr.w) or 1920, tonumber(scr and scr.h) or 1080
    local out = {}
    for _, t in ipairs(M.read(list)) do if t.address ~= c.address then out[#out + 1] = t end end
    local x = math.max(0, math.min(W - M.TILE_W, (tonumber(p.x) or 0) - M.TILE_W / 2))
    local y = math.max(0, math.min(H - M.TILE_H, (tonumber(p.y) or 0) - M.TILE_H / 2))
    out[#out + 1] = { address = c.address, class = tostring(c.class or ""), title = tostring(c.title or ""),
                      x = x, y = y, w = M.TILE_W, h = M.TILE_H }
    while #out > M.MAX do table.remove(out, 1) end
    return out
end

-- the tiles whose windows still exist (nothing dropped when the list could not be read)
function M.prune(list, clients)
    if type(clients) ~= "table" then return list end
    local alive = {}
    for _, c in ipairs(clients) do if type(c) == "table" and c.address then alive[c.address] = true end end
    local out = {}
    for _, t in ipairs(list or {}) do if alive[t.address] then out[#out + 1] = t end end
    return out
end

return M
