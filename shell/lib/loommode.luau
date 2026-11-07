-- Loom / Fold's operating modes and features (D194, spec §3.4). Pure: what is on for a mode and the
-- owner's switches, and — for everything that is off — why, in words the settings page shows.
--
--   native   — today's mooi; the Loom / Fold program does not run at all
--   hybrid   — today's mooi plus the switched-on features whose dependencies hold
--   loomfold — every built feature on (the switches are Hybrid's), plus the spatial view

local M = {}

M.MODES = { "native", "hybrid", "loomfold" }
M.MODE_NAMES = { native = "Native mooi", hybrid = "Hybrid", loomfold = "Loom / Fold" }

-- Every feature, the setting that switches it in Hybrid, what it needs, and whether it is built yet.
-- A feature that is not built is never on and never offered in Settings (spec §7): flip `built` in the
-- phase that ships it.
M.FEATURES = {
    { id = "fold",       key = "fold",       name = "Fold",       needs = {},         built = false },  -- Phase 2
    { id = "accordions", key = "accordions", name = "Accordions", needs = { "fold" }, built = false },  -- Phase 2
    { id = "cubes",      key = "cubes",      name = "Cubes",      needs = { "fold" }, built = false },  -- Phase 3
    { id = "loom",       key = "loom",       name = "Loom",       needs = {},         built = false },  -- Phase 4
    { id = "transform",  key = "transform",  name = "Transformations", needs = { "fold" }, built = false },  -- Phase 5
    { id = "spatial",    key = nil,          name = "The spatial view", needs = {}, built = false, full_only = true },  -- Phase 6
}
local BY_ID = {}
for _, f in ipairs(M.FEATURES) do BY_ID[f.id] = f end
M.BY_ID = BY_ID

function M.valid_mode(m)
    for _, x in ipairs(M.MODES) do if x == m then return m end end
    return "native"
end

-- Does the program run in this mode? Only native keeps it off.
function M.runs(mode) return M.valid_mode(mode) ~= "native" end

local function is_built(f, built)
    if type(built) == "table" and built[f.id] ~= nil then return built[f.id] == true end
    return f.built
end

-- The features on, and why each other one is off.
-- `loom` is settings.loom (a table of switches by key); `built` overrides what is built (tests, phases).
-- Returns { on = { id = true }, off = { id = reason }, mode = m }.
function M.effective(mode, loom, built)
    mode = M.valid_mode(mode)
    loom = type(loom) == "table" and loom or {}
    local on, off = {}, {}
    local function wanted(f)
        if mode == "native" then return false, "Native mooi runs no Loom / Fold" end
        if not is_built(f, built) then return false, "not built yet" end
        if f.full_only and mode ~= "loomfold" then return false, "only in Loom / Fold mode" end
        if mode == "loomfold" then return true end
        if f.key and loom[f.key] == false then return false, "switched off" end
        return true
    end
    -- in order, so a feature's needs are decided before it (the list is written needs-first)
    for _, f in ipairs(M.FEATURES) do
        local w, why = wanted(f)
        if w then
            for _, n in ipairs(f.needs) do
                if not on[n] then w, why = false, f.name .. " needs " .. BY_ID[n].name .. " — turn " .. BY_ID[n].name .. " on first" end
            end
        end
        if w then on[f.id] = true else off[f.id] = why end
    end
    return { on = on, off = off, mode = mode }
end

-- The features Settings offers (built ones only), each with whether it is on and, if not, why.
function M.offered(mode, loom, built)
    local e = M.effective(mode, loom, built)
    local out = {}
    for _, f in ipairs(M.FEATURES) do
        if is_built(f, built) and f.key then out[#out + 1] = { id = f.id, name = f.name, on = e.on[f.id] == true, why = e.off[f.id] } end
    end
    return out
end

-- A short line for the status row in Settings and `mooi loom status`.
-- health: loom-state.json as the program and the keeper write it ({ running, recovery, error, objects… }).
function M.status_line(mode, health)
    mode = M.valid_mode(mode)
    health = type(health) == "table" and health or {}
    if health.recovery then return "Stopped after repeated failures — your windows are back on their workspaces" end
    if mode == "native" then return "Off — Native mooi" end
    if health.running then
        local n = tonumber(health.structures) or 0
        return M.MODE_NAMES[mode] .. " · running" .. (n > 0 and (" · " .. n .. (n == 1 and " structure" or " structures")) or "")
    end
    return M.MODE_NAMES[mode] .. " · starting"
end

return M
