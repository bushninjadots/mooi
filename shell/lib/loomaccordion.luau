-- The Accordion (D195, spec §4.1): a sequence of windows kept as thin layers you can pull from. Its
-- windows sit on the structure's park (`special:loom-<sid>`) except the one in use — or all of them,
-- opened ("tiled") on the workspace you are on. Pure: every operation returns a plan the program runs —
--   { cmds = { Hyprland dispatches, in order }, records = { { object, record }… }, open = list|nil,
--     state = text|nil, moves = { journal moves } }
-- and `M.commit(doc, sid, plan)` writes the records and arrangement into the model once Hyprland has
-- done the commands.

local loom = require("lib/loom")
local park = require("lib/loompark")
local hypr = require("lib/hypr")

local M = {}

M.MAX_STRIPS, M.MAX_LAYERS = 4, 16

local function plan() return { cmds = {}, records = {}, moves = {} } end
local function add_steps(p, steps, from, to)
    for _, st in ipairs(steps) do
        for _, c in ipairs(st.cmds or { st.cmd }) do p.cmds[#p.cmds + 1] = c end
        p.records[#p.records + 1] = { object = st.object, record = st.record }
        p.moves[#p.moves + 1] = { object = st.object, from = from, to = to }
    end
end
local function members(doc, sid)
    local s = doc.structures[sid]
    return s and s.arrangement.order or {}
end
local function is_open(doc, sid, oid)
    for _, id in ipairs(doc.structures[sid].arrangement.open) do if id == oid then return true end end
    return false
end

function M.create(doc, name)
    return loom.add_structure(doc, "accordion", name or "Accordion")
end

-- The accordion a window belongs to: sid, oid (by its current address), or nil.
function M.of_window(doc, address)
    for oid, o in pairs(doc.objects) do
        if o.address == address and o.address ~= "" then
            local s = o.parent and doc.structures[o.parent]
            if s and s.kind == "accordion" then return o.parent, oid end
            return nil, oid
        end
    end
    return nil
end

-- Which accordion "add" puts the focused window in: the one it is already in, else the one used last,
-- else none (the caller creates one).
function M.active(doc, address)
    local sid = M.of_window(doc, address)
    if sid then return sid end
    local best, at = nil, -1
    for _, id in ipairs(loom.sorted_ids(doc.structures)) do
        local s = doc.structures[id]
        local u = tonumber(s.meta.used) or 0
        if s.kind == "accordion" and u >= at then best, at = id, u end
    end
    return best
end

-- Pull one layer out: it comes to workspace `ws` and takes the focus; whatever else of this accordion
-- was out goes back to its park (one in use at a time). Pulling the one already out only focuses it.
function M.pull(doc, sid, oid, ws)
    local p = plan()
    local s = doc.structures[sid]
    if not s or not doc.objects[oid] or doc.objects[oid].parent ~= sid then return p end
    local others = {}
    for _, id in ipairs(s.members) do if id ~= oid and doc.objects[id].state == "live" then others[#others + 1] = id end end
    add_steps(p, park.park(doc, sid, others), "out", "park")
    local o = doc.objects[oid]
    if o.state == "parked" then add_steps(p, park.unpark(doc, { oid }, ws), "park", tostring(ws)) end
    if o.state ~= "absent" and o.address ~= "" then
        local f = hypr.dispatch("focus", o.address)
        if f then p.cmds[#p.cmds + 1] = f end
    end
    p.open, p.state = { oid }, "compressed"
    return p
end

-- Put a layer back in the park.
function M.push(doc, sid, oid)
    local p = plan()
    if not doc.structures[sid] then return p end
    add_steps(p, park.park(doc, sid, { oid }), "out", "park")
    local open = {}
    for _, id in ipairs(doc.structures[sid].arrangement.open) do if id ~= oid then open[#open + 1] = id end end
    p.open = open
    return p
end

-- The next (dir 1) or previous (-1) layer after the one in use, round the end, skipping absent ones.
function M.step(doc, sid, dir, ws)
    local order = members(doc, sid)
    if #order == 0 then return plan() end
    local cur = 0
    for i, id in ipairs(order) do if is_open(doc, sid, id) then cur = i; break end end
    for k = 1, #order do
        local i = ((cur - 1 + k * (dir < 0 and -1 or 1)) % #order) + 1
        local o = doc.objects[order[i]]
        if o and o.state ~= "absent" then return M.pull(doc, sid, order[i], ws) end
    end
    return plan()
end

-- Add a window: it joins at the end and becomes the one in use (the previous one parks).
function M.add(doc, sid, oid, ws)
    local ok = loom.add_member(doc, sid, oid)
    if not ok then return plan() end
    return M.pull(doc, sid, oid, ws)
end

-- Every layer out on workspace `ws`, Hyprland tiling them.
function M.open_all(doc, sid, ws)
    local p = plan()
    if not doc.structures[sid] then return p end
    local parked = {}
    for _, id in ipairs(members(doc, sid)) do if doc.objects[id].state == "parked" then parked[#parked + 1] = id end end
    add_steps(p, park.unpark(doc, parked, ws), "park", tostring(ws))
    local open = {}
    for _, id in ipairs(members(doc, sid)) do if doc.objects[id].state ~= "absent" then open[#open + 1] = id end end
    p.open, p.state = open, "tiled"
    return p
end

-- Every layer back in the park.
function M.fold(doc, sid)
    local p = plan()
    if not doc.structures[sid] then return p end
    add_steps(p, park.park(doc, sid, members(doc, sid)), "out", "park")
    p.open, p.state = {}, "compressed"
    return p
end

-- Take a layer out of the accordion: its window comes to `ws` if it was parked, and stays.
function M.remove(doc, sid, oid, ws)
    local p = plan()
    if not doc.structures[sid] then return p end
    if doc.objects[oid] and doc.objects[oid].state == "parked" then add_steps(p, park.unpark(doc, { oid }, ws), "park", tostring(ws)) end
    p.remove = { oid }
    return p
end

-- The accordion gone: every window out on `ws`, the structure removed (its windows stay).
function M.dissolve(doc, sid, ws)
    local p = M.open_all(doc, sid, ws)
    p.dissolve = true
    return p
end

-- Write a plan into the model once Hyprland has done its commands.
function M.commit(doc, sid, p, now)
    for _, r in ipairs(p.records or {}) do park.apply(doc, r) end
    local s = doc.structures[sid]
    if not s then return end
    if p.open then s.arrangement.open = p.open end
    if p.state then s.state = p.state end
    for _, oid in ipairs(p.remove or {}) do loom.remove_member(doc, sid, oid) end
    s.meta.used = tonumber(now) or s.meta.used
    if p.dissolve then loom.remove_structure(doc, sid) end
    loom.settle(doc)
end

-- What the scene draws: the strips (at most four) and their layers (at most sixteen each).
-- strips: { s (0-based), sid, n, name, open (index of the layer in use, -1), tiled }
-- layers: { s, i, title, app, initial, open, absent }
function M.rows(doc)
    local strips, layers = {}, {}
    for _, sid in ipairs(loom.sorted_ids(doc.structures)) do
        local s = doc.structures[sid]
        if s.kind == "accordion" and #strips < M.MAX_STRIPS then
            local k = #strips
            local open_i, n = -1, 0
            for i, oid in ipairs(s.arrangement.order) do
                if i > M.MAX_LAYERS then break end
                local o = doc.objects[oid]
                local opened = is_open(doc, sid, oid)
                if opened and open_i < 0 then open_i = i - 1 end
                local app = o.app ~= "" and o.app or "window"
                layers[#layers + 1] = { s = k, i = i - 1, title = o.title ~= "" and o.title or app, app = app,
                                        initial = string.upper(string.sub(app, 1, 1)), open = opened, absent = o.state == "absent" }
                n = n + 1
            end
            strips[#strips + 1] = { s = k, sid = sid, n = n, name = s.name, open = open_i, tiled = s.state == "tiled" }
        end
    end
    return strips, layers
end

-- A strip by its place in the scene (0-based) → its structure id.
function M.strip_sid(doc, k)
    local strips = M.rows(doc)
    local s = strips[(tonumber(k) or -1) + 1]
    return s and s.sid or nil
end
-- A layer by strip and index (0-based) → the object.
function M.layer_oid(doc, k, i)
    local sid = M.strip_sid(doc, k)
    if not sid then return nil end
    return sid, doc.structures[sid].arrangement.order[(tonumber(i) or -1) + 1]
end

return M
