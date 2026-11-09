-- Super+Tab's universe (D226, spec §3, §16). Pure: the workspaces round the node — the active one in front, larger,
-- the rest further round and back — and stepping round them.

local M = { RX = 520, RY = 170 }

function M.layout(ws, active, scr)
    local out = {}
    local n = #ws
    if n == 0 then return out end
    local W, H = tonumber(scr and scr.w) or 1920, tonumber(scr and scr.h) or 1080
    local cx, cy = W / 2, H / 2
    local ai = 1
    for i, w in ipairs(ws) do if w.id == active then ai = i end end
    for i, w in ipairs(ws) do
        local a = math.rad(90 + (i - ai) * 360 / n)          -- the active one at the bottom: in front
        local depth = (math.sin(a) + 1) / 2                   -- 1 in front, 0 behind
        out[#out + 1] = { id = w.id, x = cx + math.cos(a) * M.RX, y = cy + math.sin(a) * M.RY,
                          s = 0.55 + 0.45 * depth, front = i == ai, windows = w.windows, apps = w.apps }
    end
    return out
end

function M.step(ws, active, dir)
    local n = #ws
    if n == 0 then return active end
    local ai = 1
    for i, w in ipairs(ws) do if w.id == active then ai = i end end
    return ws[(ai - 1 + (dir > 0 and 1 or -1)) % n + 1].id
end

return M
