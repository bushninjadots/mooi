-- The Control Nexus drawer's column (D98): its sections in order, each one's height from what it
-- holds now (how many notices, networks, devices, outputs, apps, workspaces), folded ones down to
-- their header, and where each starts. The scene draws every section from these numbers. Pure,
-- so tests/unit runs it.

local M = {}

M.HEADER = 204     -- the drawer's own head (the profile card: banner, avatar, name, time) before the first section
M.GAP = 10         -- between sections
M.FOLDED = 30      -- a section's header line
M.ROW = 30         -- one row of a list

M.ORDER = { "toggles", "levels", "media", "notes", "connections", "sound", "machine", "today",
            "updates", "workspaces", "shortcuts" }
local KNOWN = {}
for _, id in ipairs(M.ORDER) do KNOWN[id] = true end

local function n(v) return math.max(0, tonumber(v) or 0) end

-- An open section's height for counts `c` (missing counts read as 0 / false).
local function open_height(id, c)
    if id == "toggles" then return M.FOLDED + 3 * 62 end
    if id == "levels" then return M.FOLDED + (c.bright and 3 or 2) * 40 end
    if id == "media" then return M.FOLDED + 96 end
    if id == "notes" then return M.FOLDED + math.max(1, math.min(5, n(c.notes))) * M.ROW + 36 end
    if id == "connections" then
        return M.FOLDED + 24 + math.max(1, math.min(5, n(c.nets))) * M.ROW + 24 + math.max(1, math.min(6, n(c.bt))) * M.ROW
    end
    if id == "sound" then return M.FOLDED + math.max(1, math.min(6, n(c.outs))) * 28 + math.min(6, n(c.apps)) * 40 + 6 end
    if id == "machine" then return M.FOLDED + 76 + 28 end
    if id == "today" then return M.FOLDED + 60 + 44 end
    if id == "updates" then return M.FOLDED + 40 end
    if id == "workspaces" then return M.FOLDED + 44 end
    if id == "shortcuts" then return M.FOLDED + 2 * 36 end
    return M.FOLDED
end

-- { order, shown[id], height[id], top[id], total } for counts `c` and folds `folded` (a set).
function M.layout(c, folded)
    c = c or {}; folded = folded or {}
    local out = { order = M.ORDER, shown = {}, height = {}, top = {}, total = 0 }
    local y = M.HEADER
    for _, id in ipairs(M.ORDER) do
        local shown = id ~= "media" or c.playing == true
        out.shown[id] = shown
        out.top[id] = y
        if shown then
            out.height[id] = folded[id] and M.FOLDED or open_height(id, c)
            y = y + out.height[id] + M.GAP
        else
            out.height[id] = 0
        end
    end
    out.total = y
    return out
end

-- The fold set with `id` flipped (a copy).
function M.toggle(folded, id)
    local out = {}
    for k, v in pairs(folded or {}) do out[k] = v end
    if out[id] then out[id] = nil else out[id] = true end
    return out
end

-- The fold set as it is kept in settings (nexus.folded): a list of known ids, in order.
function M.folded_list(folded)
    local out = {}
    for _, id in ipairs(M.ORDER) do if (folded or {})[id] then out[#out + 1] = id end end
    return out
end

function M.folded_set(list)
    local out = {}
    for _, id in ipairs(type(list) == "table" and list or {}) do if KNOWN[id] then out[id] = true end end
    return out
end

return M
