-- Parking (D194, spec §3.3, §5.3): Loom / Fold hides a structure's windows by moving them to the
-- structure's own Hyprland special workspace (`special:loom-s3`) — off every workspace, still running —
-- and brings them back to the workspace (and, floating, the place) they came from. Pure: it builds the
-- Hyprland commands (through lib/hypr, the only place that knows Hyprland's syntax) and says what the
-- model should record once Hyprland has done them; the caller runs them and reads the result back.

local hypr = require("lib/hypr")
local loom = require("lib/loom")

local M = {}

-- The park of a structure: the name `lib/hypr`'s `park` action takes (`loom-s3`).
function M.park_name(sid)
    return (type(sid) == "string" and string.match(sid, "^s%d+$")) and ("loom-" .. sid) or nil
end

-- Park these objects (windows) of structure `sid`. Each step: { object, address, cmd, record } — `record`
-- is what to write into the object once Hyprland confirms (its state, and where it came from, which the
-- way back needs). Windows that are absent or already parked are skipped.
function M.park(doc, sid, oids)
    local name = M.park_name(sid)
    local steps = {}
    if not name or not doc.structures[sid] then return steps end
    for _, oid in ipairs(oids or {}) do
        local o = doc.objects[oid]
        if o and o.kind == "window" and o.state == "live" and o.address ~= "" then
            local cmd = hypr.dispatch("park", o.address, { park = name })
            if cmd then
                steps[#steps + 1] = { object = oid, address = o.address, cmd = cmd,
                                      record = { state = "parked", workspace = o.workspace, at = o.at, floating = o.floating } }
            end
        end
    end
    return steps
end

-- Bring these parked objects back where they came from: to their workspace (never following, so the
-- owner's view does not jump), then — a floating window — to its old place and size.
function M.unpark(doc, oids)
    local steps = {}
    for _, oid in ipairs(oids or {}) do
        local o = doc.objects[oid]
        if o and o.kind == "window" and o.state == "parked" and o.address ~= "" then
            local ws = (o.workspace and o.workspace >= 1 and o.workspace <= 99) and o.workspace or 1
            local cmds = {}
            local mv = hypr.dispatch("move", o.address, { workspace = ws, follow = false })
            if mv then cmds[#cmds + 1] = mv end
            if o.floating and o.at then
                local pl = hypr.dispatch("place", o.address, { x = o.at[1], y = o.at[2] })
                local sz = hypr.dispatch("size", o.address, { w = o.at[3], h = o.at[4] })
                if pl then cmds[#cmds + 1] = pl end
                if sz then cmds[#cmds + 1] = sz end
            end
            if #cmds > 0 then
                steps[#steps + 1] = { object = oid, address = o.address, cmds = cmds, record = { state = "live" } }
            end
        end
    end
    return steps
end

-- Every parked window, back: what the keeper runs when the program has died or Loom / Fold is turned
-- off, so a window is never left stranded (spec §5.3). Works from the document alone.
function M.unpark_all(doc)
    local ids = {}
    for _, p in ipairs(loom.parked(doc)) do ids[#ids + 1] = p.object end
    return M.unpark(doc, ids)
end

-- The windows Hyprland says are on a Loom park, whatever the document says (a document lost or behind):
-- clients from `hyprctl -j clients` → { address, structure } for each. The keeper brings these out too.
function M.stray(clients)
    local out = {}
    for _, c in ipairs(clients or {}) do
        local ws = type(c) == "table" and type(c.workspace) == "table" and c.workspace.name or nil
        local sid = loom.park_of(ws)
        if sid and hypr.valid_address(c.address) then out[#out + 1] = { address = c.address, structure = sid } end
    end
    return out
end

-- A stray window has no record of where it came from: it comes to the workspace the owner is on.
function M.rescue(strays, workspace)
    local ws = (tonumber(workspace) and tonumber(workspace) >= 1 and tonumber(workspace) <= 99) and math.floor(tonumber(workspace)) or 1
    local cmds = {}
    for _, s in ipairs(strays or {}) do
        local cmd = hypr.dispatch("move", s.address, { workspace = ws, follow = false })
        if cmd then cmds[#cmds + 1] = cmd end
    end
    return cmds
end

-- Write a step's record into the model (after Hyprland confirmed it).
function M.apply(doc, step)
    local o = doc.objects[step.object]
    if not o then return false end
    for k, v in pairs(step.record or {}) do o[k] = v end
    return true
end

return M
