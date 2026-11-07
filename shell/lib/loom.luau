-- Loom / Fold's shared model (D194, docs/superpowers/specs/2026-11-07-loom-fold-design.md §3.3): the
-- objects (windows, apps, files), the structures they are folded into (Accordion, Cube…), the
-- connections between them, the environments that hold structures, and the journal of operations that
-- move windows. One document, `loom.json`, owned by the mooi-loom program; every other reader only
-- reads it. Pure: no Pleamar, no system — tests/unit runs it.
--
-- Rules that hold after every function here:
--   · an object belongs to at most one structure (`parent`), and a structure's `members` lists exactly
--     the objects whose parent it is;
--   · a connection's ends exist; a structure's members exist; nothing points at a removed id;
--   · ids are mooi's and permanent: `o12`, `s3`, `c1`, `e1`, `j7` — a window's address and pid are only
--     its current handle and may change.

local M = {}

M.VERSION = 1
M.MAX = { objects = 512, structures = 64, connections = 512, environments = 20, journal = 50, members = 64 }
M.OBJECT_KINDS = { window = true, app = true, file = true, resource = true }
-- Only the structures that are built; a later one (ring, spine, cluster, branch, island) is added here
-- with its own rules module, and the rest of the model does not change (spec §4.5).
M.STRUCTURE_KINDS = { accordion = true, cube = true }
M.LINK_KINDS = { association = true, containment = true, workflow = true, dependency = true, navigation = true }
M.STATES = { live = true, parked = true, absent = true }
local PREFIX = { objects = "o", structures = "s", connections = "c", environments = "e", journal = "j" }
local TEXT_MAX = 200

local function text(s, n)
    if type(s) ~= "string" then return "" end
    s = string.gsub(s, "%c", " ")
    n = n or TEXT_MAX
    if #s > n then
        local ok, off = pcall(utf8.offset, s, n + 1)
        s = string.sub(s, 1, (ok and off) and off - 1 or n)
    end
    return s
end
local function int(n, lo, hi)
    n = tonumber(n)
    if not n or n ~= math.floor(n) then return nil end
    if (lo and n < lo) or (hi and n > hi) then return nil end
    return n
end
local function valid_id(id, prefix)
    return type(id) == "string" and string.match(id, "^" .. prefix .. "%d+$") ~= nil and #id <= 12
end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
-- keys in a stable order (ids by their number), so a document and every walk over it are deterministic
local function sorted_ids(t)
    local out = {}
    for id in pairs(t) do out[#out + 1] = id end
    table.sort(out, function(a, b)
        local na, nb = tonumber(string.match(a, "%d+")), tonumber(string.match(b, "%d+"))
        if na and nb and na ~= nb then return na < nb end
        return a < b
    end)
    return out
end
M.sorted_ids = sorted_ids

function M.empty()
    return { version = M.VERSION, seq = 0, objects = {}, structures = {}, connections = {}, environments = {}, journal = {} }
end

-- A fresh id for one of the tables (`objects`, `structures`…). The counter only goes up, so an id is
-- never reused, even after its thing is removed.
function M.new_id(doc, what)
    doc.seq = (int(doc.seq, 0) or 0) + 1
    return PREFIX[what] .. doc.seq
end

local function clean_rect(r)
    if type(r) ~= "table" then return nil end
    local x, y, w, h = int(r[1], -20000, 20000), int(r[2], -20000, 20000), int(r[3], 1, 20000), int(r[4], 1, 20000)
    if x and y and w and h then return { x, y, w, h } end
    return nil
end
local function clean_meta(m)
    local out = {}
    if type(m) ~= "table" then return out end
    local n = 0
    for k, v in pairs(m) do
        if type(k) == "string" and #k <= 32 and n < 16 then
            if type(v) == "string" then out[k] = text(v, 1024); n = n + 1
            elseif type(v) == "number" or type(v) == "boolean" then out[k] = v; n = n + 1 end
        end
    end
    return out
end
local function clean_object(id, o)
    if not valid_id(id, "o") or type(o) ~= "table" or not M.OBJECT_KINDS[o.kind] then return nil end
    return {
        id = id, kind = o.kind, app = text(o.app, 128), desktop = text(o.desktop, 128), title = text(o.title),
        address = (type(o.address) == "string" and string.match(o.address, "^0x%x+$")) and o.address or "",
        pid = int(o.pid, 1) or 0,
        state = M.STATES[o.state] and o.state or "absent",
        workspace = int(o.workspace, -99, 99) or 0,
        at = clean_rect(o.at), floating = o.floating == true,
        parent = valid_id(o.parent, "s") and o.parent or nil,
        meta = clean_meta(o.meta),
    }
end
local function clean_list(l, prefix, max)
    local out, seen = {}, {}
    if type(l) ~= "table" then return out end
    for _, id in ipairs(l) do
        if #out >= max then break end
        if valid_id(id, prefix) and not seen[id] then out[#out + 1] = id; seen[id] = true end
    end
    return out
end
local function clean_structure(id, s)
    if not valid_id(id, "s") or type(s) ~= "table" or not M.STRUCTURE_KINDS[s.kind] then return nil end
    local arr = type(s.arrangement) == "table" and s.arrangement or {}
    return {
        id = id, kind = s.kind, name = text(s.name, 48), members = clean_list(s.members, "o", M.MAX.members),
        state = text(s.state, 24), accent = text(s.accent, 16),
        arrangement = { order = clean_list(arr.order, "o", M.MAX.members), open = clean_list(arr.open, "o", M.MAX.members),
                        faces = type(arr.faces) == "table" and arr.faces or nil, edge = text(arr.edge, 8) },
        parked_on = (type(s.parked_on) == "string" and string.match(s.parked_on, "^special:loom%-s%d+$")) and s.parked_on or "",
        saved = type(s.saved) == "table" and s.saved or {},
        meta = clean_meta(s.meta),
    }
end
local function clean_connection(id, c)
    if not valid_id(id, "c") or type(c) ~= "table" or not M.LINK_KINDS[c.kind] then return nil end
    if type(c.from) ~= "string" or type(c.to) ~= "string" or c.from == c.to then return nil end
    return { id = id, from = c.from, to = c.to, kind = c.kind, directed = c.directed == true, meta = clean_meta(c.meta) }
end
local function clean_env(id, e)
    if not valid_id(id, "e") or type(e) ~= "table" then return nil end
    return { id = id, name = text(e.name, 48), structures = clean_list(e.structures, "s", M.MAX.structures),
             restore = type(e.restore) == "table" and e.restore or {}, meta = clean_meta(e.meta) }
end
local function clean_move(m)
    if type(m) ~= "table" then return nil end
    local oid = valid_id(m.object, "o") and m.object or nil
    if not oid then return nil end
    return { object = oid, from = text(m.from, 40), to = text(m.to, 40), at = clean_rect(m.at) }
end
local function clean_entry(e)
    if type(e) ~= "table" or not valid_id(e.id, "j") then return nil end
    local op = text(e.op, 24)
    if op == "" then return nil end
    local moves = {}
    for _, m in ipairs(type(e.moves) == "table" and e.moves or {}) do
        local c = clean_move(m)
        if c and #moves < M.MAX.members * 2 then moves[#moves + 1] = c end
    end
    return { id = e.id, op = op, target = text(e.target, 12), moves = moves,
             state = (e.state == "pending" or e.state == "done" or e.state == "undone") and e.state or "done",
             at = int(e.at, 0) or 0 }
end

-- Make every rule hold again: the parent/members agreement, references to things that exist, limits.
-- Used after cleaning a document and after any edit that could break a rule.
function M.settle(doc)
    -- each structure's members exist and are not claimed twice; the parent follows the members
    local owner = {}
    for _, sid in ipairs(sorted_ids(doc.structures)) do
        local s = doc.structures[sid]
        local keep = {}
        for _, oid in ipairs(s.members) do
            if doc.objects[oid] and not owner[oid] then keep[#keep + 1] = oid; owner[oid] = sid end
        end
        s.members = keep
        local function filter(list)
            local out = {}
            for _, oid in ipairs(list or {}) do if owner[oid] == sid then out[#out + 1] = oid end end
            return out
        end
        s.arrangement.order = filter(s.arrangement.order)
        s.arrangement.open = filter(s.arrangement.open)
        -- the order lists every member exactly once: unordered members go at its end
        local inorder = {}
        for _, oid in ipairs(s.arrangement.order) do inorder[oid] = true end
        for _, oid in ipairs(s.members) do
            if not inorder[oid] then s.arrangement.order[#s.arrangement.order + 1] = oid end
        end
    end
    for oid, o in pairs(doc.objects) do o.parent = owner[oid] end
    -- a connection's ends exist (an object, a structure or an environment) and are not duplicated
    local seen = {}
    for _, cid in ipairs(sorted_ids(doc.connections)) do
        local c = doc.connections[cid]
        local key = c.from .. ">" .. c.to .. ":" .. c.kind
        if not M.exists(doc, c.from) or not M.exists(doc, c.to) or seen[key] then doc.connections[cid] = nil
        else seen[key] = true end
    end
    for _, e in pairs(doc.environments) do
        local keep = {}
        for _, sid in ipairs(e.structures) do if doc.structures[sid] then keep[#keep + 1] = sid end end
        e.structures = keep
    end
    while #doc.journal > M.MAX.journal do table.remove(doc.journal, 1) end
    return doc
end

function M.exists(doc, id)
    if type(id) ~= "string" then return false end
    return (doc.objects[id] or doc.structures[id] or doc.environments[id]) ~= nil
end

-- A document read from disk (anything at all) → a valid document, and what was dropped, in words.
function M.clean(raw)
    local doc, problems = M.empty(), {}
    if type(raw) ~= "table" then
        if raw ~= nil then problems[#problems + 1] = "loom.json is not a document; starting empty" end
        return doc, problems
    end
    if tonumber(raw.version) and tonumber(raw.version) > M.VERSION then
        problems[#problems + 1] = "loom.json is from a newer mooi (version " .. tostring(raw.version) .. "); read as far as understood"
    end
    doc.seq = int(raw.seq, 0) or 0
    local function each(name, fn)
        local n, bad = 0, 0
        for _, id in ipairs(sorted_ids(type(raw[name]) == "table" and raw[name] or {})) do
            local v = fn(id, raw[name][id])
            if v and n < M.MAX[name] then doc[name][id] = v; n = n + 1 else bad = bad + 1 end
            -- keep the counter past every id seen, so a new one never collides
            local num = tonumber(string.match(tostring(id), "%d+"))
            if num and num > doc.seq then doc.seq = num end
        end
        if bad > 0 then problems[#problems + 1] = bad .. " " .. name .. " dropped (invalid or over the limit)" end
    end
    each("objects", clean_object)
    each("structures", clean_structure)
    each("connections", clean_connection)
    each("environments", clean_env)
    for _, e in ipairs(type(raw.journal) == "table" and raw.journal or {}) do
        local c = clean_entry(e)
        if c then
            doc.journal[#doc.journal + 1] = c
            local num = tonumber(string.match(c.id, "%d+"))
            if num and num > doc.seq then doc.seq = num end
        end
    end
    local before = count(doc.connections)
    M.settle(doc)
    local lost = before - count(doc.connections)
    if lost > 0 then problems[#problems + 1] = lost .. " connections dropped (an end is missing, or a duplicate)" end
    return doc, problems
end

-- ── Objects ──────────────────────────────────────────────
function M.add_object(doc, fields)
    if count(doc.objects) >= M.MAX.objects then return nil, "too many objects" end
    local id = M.new_id(doc, "objects")
    local o = clean_object(id, { kind = fields.kind or "window", app = fields.app, desktop = fields.desktop, title = fields.title,
                                 address = fields.address, pid = fields.pid, state = fields.state or "live",
                                 workspace = fields.workspace, at = fields.at, floating = fields.floating, meta = fields.meta })
    if not o then return nil, "not a valid object" end
    doc.objects[id] = o
    return id
end

-- Remove an object: out of its structure, and every connection to it goes too (nothing points at a
-- removed id).
function M.remove_object(doc, oid)
    if not doc.objects[oid] then return false end
    doc.objects[oid] = nil
    M.settle(doc)
    return true
end

-- ── Structures ───────────────────────────────────────────
function M.add_structure(doc, kind, name, members)
    if not M.STRUCTURE_KINDS[kind] then return nil, "not a structure mooi has: " .. tostring(kind) end
    if count(doc.structures) >= M.MAX.structures then return nil, "too many structures" end
    local id = M.new_id(doc, "structures")
    doc.structures[id] = clean_structure(id, { kind = kind, name = name, members = {}, state = "", arrangement = {} })
    for _, oid in ipairs(members or {}) do M.add_member(doc, id, oid) end
    return id
end

-- Put an object in a structure (at `at` in its order, or last). An object in another structure moves:
-- it leaves that one first (an object belongs to one structure at most).
function M.add_member(doc, sid, oid, at)
    local s, o = doc.structures[sid], doc.objects[oid]
    if not s or not o then return false, "no such structure or object" end
    if o.parent == sid then return true end
    if #s.members >= M.MAX.members then return false, "this structure is full" end
    if o.parent then M.remove_member(doc, o.parent, oid) end
    s.members[#s.members + 1] = oid
    local order = s.arrangement.order
    local i = int(at, 1, #order + 1) or (#order + 1)
    table.insert(order, i, oid)
    o.parent = sid
    return true
end

function M.remove_member(doc, sid, oid)
    local s = doc.structures[sid]
    if not s then return false end
    local function drop(list) for i = #list, 1, -1 do if list[i] == oid then table.remove(list, i) end end end
    drop(s.members); drop(s.arrangement.order); drop(s.arrangement.open)
    if doc.objects[oid] and doc.objects[oid].parent == sid then doc.objects[oid].parent = nil end
    return true
end

-- Move a member to another place in its structure's order (1-based).
function M.reorder(doc, sid, oid, to)
    local s = doc.structures[sid]
    if not s then return false end
    local order = s.arrangement.order
    local from
    for i, id in ipairs(order) do if id == oid then from = i end end
    if not from then return false end
    table.remove(order, from)
    to = math.max(1, math.min(#order + 1, int(to) or (#order + 1)))
    table.insert(order, to, oid)
    return true
end

-- Remove a structure. Its members are kept as loose objects (nothing is lost with a structure), and
-- connections to the structure itself go.
function M.remove_structure(doc, sid)
    if not doc.structures[sid] then return false end
    doc.structures[sid] = nil
    M.settle(doc)
    return true
end

-- ── Connections ──────────────────────────────────────────
function M.connect(doc, from, to, kind, directed)
    if not M.LINK_KINDS[kind] then return nil, "not a kind of connection: " .. tostring(kind) end
    if from == to then return nil, "a thing cannot be connected to itself" end
    if not M.exists(doc, from) or not M.exists(doc, to) then return nil, "both ends must exist" end
    for _, c in pairs(doc.connections) do
        if c.from == from and c.to == to and c.kind == kind then return c.id end
    end
    if count(doc.connections) >= M.MAX.connections then return nil, "too many connections" end
    local id = M.new_id(doc, "connections")
    doc.connections[id] = { id = id, from = from, to = to, kind = kind, directed = directed == true, meta = {} }
    return id
end

function M.disconnect(doc, cid)
    if not doc.connections[cid] then return false end
    doc.connections[cid] = nil
    return true
end

-- What is connected to `id`: { id = the other end, via = the connection, kind, out = whether `id` is its
-- source }, in a stable order.
function M.related(doc, id)
    local out = {}
    for _, cid in ipairs(sorted_ids(doc.connections)) do
        local c = doc.connections[cid]
        if c.from == id then out[#out + 1] = { id = c.to, via = cid, kind = c.kind, out = true }
        elseif c.to == id then out[#out + 1] = { id = c.from, via = cid, kind = c.kind, out = false } end
    end
    return out
end

-- ── Windows: the tracker's view ──────────────────────────
-- Every window that is parked (on a Loom special workspace): what anyone needs to bring it back —
-- `{ object, address, structure, workspace (where it came from), at }`. The keeper uses this when the
-- program has died, so a window is never stranded (spec §5.3).
function M.parked(doc)
    local out = {}
    for _, oid in ipairs(sorted_ids(doc.objects)) do
        local o = doc.objects[oid]
        if o.kind == "window" and o.state == "parked" and o.address ~= "" then
            out[#out + 1] = { object = oid, address = o.address, structure = o.parent,
                              workspace = (o.workspace and o.workspace > 0) and o.workspace or 1, at = o.at }
        end
    end
    return out
end

-- Is this Hyprland workspace name one of Loom's parks? → the structure id, or nil.
function M.park_of(name)
    return type(name) == "string" and string.match(name, "^special:loom%-(s%d+)$") or nil
end

-- The windows Hyprland reports (`hyprctl -j clients`), matched to the objects: by address first (the
-- same session), then — for objects whose window has gone, as after a restart — by app and title, then
-- app and folder. Updates handle, place and state of matched objects (live, or parked when on a Loom
-- park); unmatched objects become `absent` (kept). Windows matching nothing are returned as `loose` for
-- the caller to register or ignore. Returns { matched = n, absent = n, loose = { client… } }.
function M.match(doc, clients)
    local by_addr, used = {}, {}
    for _, c in ipairs(clients or {}) do
        if type(c) == "table" and type(c.address) == "string" then by_addr[c.address] = c end
    end
    local function apply(o, c)
        used[c.address] = true
        o.address, o.pid = c.address, int(c.pid, 1) or o.pid
        o.title = text(c.title)
        if c.class and c.class ~= "" then o.app = text(c.class, 128) end
        local ws = type(c.workspace) == "table" and c.workspace or {}
        if M.park_of(ws.name) then
            o.state = "parked"           -- where it came from (o.workspace) is kept for the way back
        else
            o.state = "live"
            o.workspace = int(ws.id, -99, 99) or o.workspace
            if type(c.at) == "table" and type(c.size) == "table" then
                o.at = clean_rect({ c.at[1], c.at[2], c.size[1], c.size[2] }) or o.at
            end
            o.floating = c.floating == true
        end
    end
    local matched, absent = 0, 0
    local ids = sorted_ids(doc.objects)
    -- 1: the same window, by its address
    for _, oid in ipairs(ids) do
        local o = doc.objects[oid]
        if o.kind == "window" and o.address ~= "" and by_addr[o.address] then apply(o, by_addr[o.address]); matched = matched + 1; o._m = true end
    end
    -- 2: a window that came back (a restart): same app and title, then same app and folder, unused yet
    local function find(o, strict)
        for _, c in ipairs(clients or {}) do
            if type(c) == "table" and not used[c.address] and c.class == o.app and o.app ~= "" then
                if strict and c.title == o.title then return c end
                if not strict and o.meta.cwd and o.meta.cwd ~= "" and c.cwd == o.meta.cwd then return c end
            end
        end
    end
    for _, pass in ipairs({ true, false }) do
        for _, oid in ipairs(ids) do
            local o = doc.objects[oid]
            if o.kind == "window" and not o._m then
                local c = find(o, pass)
                if c then apply(o, c); matched = matched + 1; o._m = true end
            end
        end
    end
    for _, oid in ipairs(ids) do
        local o = doc.objects[oid]
        if o.kind == "window" and not o._m then o.state = "absent"; o.address = ""; o.pid = 0; absent = absent + 1 end
        o._m = nil
    end
    local loose = {}
    for _, c in ipairs(clients or {}) do
        if type(c) == "table" and type(c.address) == "string" and not used[c.address] then loose[#loose + 1] = c end
    end
    return { matched = matched, absent = absent, loose = loose }
end

-- Objects that nothing refers to and that are not parked: a window registered only because it was open
-- is not kept on disk (the document holds what the owner organised, not a log of every window).
function M.prune(doc)
    local referenced = {}
    for _, c in pairs(doc.connections) do referenced[c.from] = true; referenced[c.to] = true end
    local n = 0
    for oid, o in pairs(doc.objects) do
        if not o.parent and not referenced[oid] and o.state ~= "parked" then doc.objects[oid] = nil; n = n + 1 end
    end
    return n
end

-- ── The journal (spec §5.4) ──────────────────────────────
function M.journal_begin(doc, op, target, moves, now)
    local id = M.new_id(doc, "journal")
    local entry = clean_entry({ id = id, op = op, target = target, moves = moves, state = "pending", at = now })
    doc.journal[#doc.journal + 1] = entry
    M.settle(doc)
    return id
end
function M.journal_end(doc, jid, state)
    for _, e in ipairs(doc.journal) do
        if e.id == jid then e.state = state or "done"; return true end
    end
    return false
end
function M.pending(doc)
    local out = {}
    for _, e in ipairs(doc.journal) do if e.state == "pending" then out[#out + 1] = e end end
    return out
end
-- What to do with an operation found pending at start: always the side where the windows are visible.
-- A fold (or a park) is rolled back — its windows come out; an unfold is completed — the rest come out.
function M.recovery_for(entry)
    if type(entry) ~= "table" then return "none" end
    if entry.op == "unfold" or entry.op == "pull" or entry.op == "unpark" then return "complete" end
    return "rollback"
end

return M
