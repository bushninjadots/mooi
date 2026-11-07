-- The Cube (D197, spec §4.2): a whole working environment as one object. Unfolded, its windows are on
-- their workspaces where they were; folded, they wait on the structure's park and the Cube is a small
-- solid docked on the edge. Its faces hold its members by role — front the main app, right the
-- supporting ones, left files and resources, top quick actions, bottom background processes, back
-- related environments — and turning it brings a face round; opening a face unfolds only that face.
-- Pure: every operation returns a plan the program runs (the Accordion's shape:
--   { cmds, records, moves, state, faces?, remove?, dissolve? }), and `M.commit` writes it in.

local loom = require("lib/loom")
local park = require("lib/loompark")

local M = {}

M.FACES = { "front", "right", "back", "left", "top", "bottom" }
M.SIDES = 4                                 -- the four that turn round (front, right, back, left)
M.MAX_CUBES = 6
-- File managers go on the left face when a Cube is made (files and resources)
M.FILES = { nautilus = true, ["org.gnome.nautilus"] = true, thunar = true, dolphin = true, ["org.kde.dolphin"] = true,
            nemo = true, pcmanfm = true, yazi = true, ranger = true }

local function plan() return { cmds = {}, records = {}, moves = {} } end
local function add_steps(p, steps, from, to)
    for _, st in ipairs(steps) do
        for _, c in ipairs(st.cmds or { st.cmd }) do p.cmds[#p.cmds + 1] = c end
        p.records[#p.records + 1] = { object = st.object, record = st.record }
        p.moves[#p.moves + 1] = { object = st.object, from = from, to = to }
    end
end

-- The faces of a cube, each a list of its members (only members; a member on no face goes to right).
function M.faces(doc, sid)
    local s = doc.structures[sid]
    local out = {}
    for _, f in ipairs(M.FACES) do out[f] = {} end
    if not s then return out end
    local raw = type(s.arrangement.faces) == "table" and s.arrangement.faces or {}
    local placed = {}
    for _, f in ipairs(M.FACES) do
        for _, oid in ipairs(type(raw[f]) == "table" and raw[f] or {}) do
            local o = doc.objects[oid]
            if o and o.parent == sid and not placed[oid] then out[f][#out[f] + 1] = oid; placed[oid] = true end
        end
    end
    for _, oid in ipairs(s.members) do if not placed[oid] then out.right[#out.right + 1] = oid end end
    return out
end

-- Make a cube of these windows: `focus` on the front, file managers on the left, the rest on the right.
function M.create(doc, oids, focus, name)
    local sid, why = loom.add_structure(doc, "cube", name or "Cube")
    if not sid then return nil, why end
    local faces = { front = {}, right = {}, back = {}, left = {}, top = {}, bottom = {} }
    for _, oid in ipairs(oids or {}) do
        local o = doc.objects[oid]
        if o and loom.add_member(doc, sid, oid) then
            local app = string.lower(o.app or "")
            if oid == focus then table.insert(faces.front, 1, oid)
            elseif M.FILES[app] then faces.left[#faces.left + 1] = oid
            else faces.right[#faces.right + 1] = oid end
        end
    end
    if #faces.front == 0 and #faces.right > 0 then faces.front[1] = table.remove(faces.right, 1) end
    local s = doc.structures[sid]
    s.arrangement.faces = faces
    s.state = "unfolded"
    s.meta.face = 0
    return sid
end

-- Fold: every member that is out goes to the park (where it was is kept for the way back).
function M.fold(doc, sid)
    local p = plan()
    local s = doc.structures[sid]
    if not s then return p end
    add_steps(p, park.park(doc, sid, s.members), "out", "park")
    p.state = "folded"
    return p
end

-- Unfold: every parked member back to its own workspace and place — or, with `face`, only that face's
-- (a partial unfold).
function M.unfold(doc, sid, face)
    local p = plan()
    local s = doc.structures[sid]
    if not s then return p end
    local list = face and M.faces(doc, sid)[face] or s.members
    local parked = {}
    for _, oid in ipairs(list) do if doc.objects[oid] and doc.objects[oid].state == "parked" then parked[#parked + 1] = oid end end
    add_steps(p, park.unpark(doc, parked), "park", "home")
    if face then
        -- partial: what stays parked decides the state
        local left = 0
        for _, oid in ipairs(s.members) do
            local o = doc.objects[oid]
            local coming = false
            for _, x in ipairs(parked) do if x == oid then coming = true end end
            if o and o.state == "parked" and not coming then left = left + 1 end
        end
        p.state = left > 0 and "partial" or "unfolded"
    else
        p.state = "unfolded"
    end
    return p
end

-- The face that faces you, as an index into the four sides (0 front … 3 left), and its name.
function M.facing(doc, sid)
    local s = doc.structures[sid]
    local i = s and math.floor(tonumber(s.meta.face) or 0) % M.SIDES or 0
    return i, M.FACES[i + 1]
end

-- Turn it: the next side round (dir 1) or the previous (-1). Turning moves no window.
function M.turn(doc, sid, dir)
    local s = doc.structures[sid]
    if not s then return 0 end
    local step = dir < 0 and -1 or 1
    local i = (M.facing(doc, sid) + step) % M.SIDES
    s.meta.face = i
    -- the drawing turns by this count, never by the face (3 → 0 keeps turning the same way round)
    s.meta.turn = (math.floor(tonumber(s.meta.turn) or 0)) + step
    return i
end

-- Add a window to a face (the facing one by default). A folded cube takes it in folded: it parks.
function M.add(doc, sid, oid, face)
    local p = plan()
    local s = doc.structures[sid]
    if not s or not loom.add_member(doc, sid, oid) then return p end
    face = face or select(2, M.facing(doc, sid))
    local faces = M.faces(doc, sid)
    -- it was put on `right` by M.faces (it was on no face): move it to the chosen one
    for f, list in pairs(faces) do for i = #list, 1, -1 do if list[i] == oid then table.remove(list, i) end end end
    table.insert(faces[face], oid)
    p.faces = faces
    if s.state == "folded" then add_steps(p, park.park(doc, sid, { oid }), "out", "park") end
    return p
end

-- The cube gone: everything out where it was, the structure removed (its windows stay).
function M.dissolve(doc, sid)
    local p = M.unfold(doc, sid)
    p.dissolve = true
    return p
end

function M.commit(doc, sid, p, now)
    for _, r in ipairs(p.records or {}) do park.apply(doc, r) end
    local s = doc.structures[sid]
    if not s then return end
    if p.state then s.state = p.state end
    if p.faces then s.arrangement.faces = p.faces end
    for _, oid in ipairs(p.remove or {}) do loom.remove_member(doc, sid, oid) end
    s.meta.used = tonumber(now) or s.meta.used
    if p.dissolve then loom.remove_structure(doc, sid) end
    loom.settle(doc)
end

-- The cube a window belongs to.
function M.of_window(doc, address)
    for oid, o in pairs(doc.objects) do
        if o.address == address and o.address ~= "" and o.parent and doc.structures[o.parent]
           and doc.structures[o.parent].kind == "cube" then return o.parent, oid end
    end
    return nil
end

-- The cube used last (for "join" and for unfolding from the keys); `folded` limits it to folded ones.
function M.last(doc, folded)
    local best, at = nil, -1
    for _, sid in ipairs(loom.sorted_ids(doc.structures)) do
        local s = doc.structures[sid]
        if s.kind == "cube" and (not folded or s.state == "folded" or s.state == "partial") then
            local u = tonumber(s.meta.used) or 0
            if u >= at then best, at = sid, u end
        end
    end
    return best
end

-- What the scene draws: one row per cube (at most six) — its place, name, state, the facing side, and
-- each side's count and first initial.
function M.rows(doc)
    local out = {}
    for _, sid in ipairs(loom.sorted_ids(doc.structures)) do
        local s = doc.structures[sid]
        if s.kind == "cube" and #out < M.MAX_CUBES then
            local faces = M.faces(doc, sid)
            local r = { c = #out, name = s.name, folded = s.state == "folded", partial = s.state == "partial",
                        face = M.facing(doc, sid), turn = math.floor(tonumber(s.meta.turn) or 0), n = #s.members }
            for i, f in ipairs(M.FACES) do
                local list = faces[f]
                local o = list[1] and doc.objects[list[1]]
                r["n" .. (i - 1)] = #list
                r["i" .. (i - 1)] = o and string.upper(string.sub(o.app ~= "" and o.app or "?", 1, 1)) or ""
            end
            out[#out + 1] = r
        end
    end
    return out
end
function M.cube_sid(doc, c)
    local n = -1
    for _, sid in ipairs(loom.sorted_ids(doc.structures)) do
        if doc.structures[sid].kind == "cube" then
            n = n + 1
            if n == math.floor(tonumber(c) or -1) then return sid end
        end
    end
    return nil
end

return M
