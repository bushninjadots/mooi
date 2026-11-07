-- Loom's connections (D200, spec §4.3): what each kind does, and the threads that show them. Pure.
--
--   association  "these go together"   — a jump goes along it either way
--   workflow     an ordered sequence      — a jump goes forward along it first (directed)
--   navigation   a route                  — a jump goes along it
--   dependency   one needs another        — folding the needed one warns that its dependants lose it
--   containment  belongs to a structure   — a structure's membership; never drawn as a thread
--
-- Threads are drawn between windows on the workspace you are on: a fine curve that sags with its length,
-- an arrowhead at the end of a directed one; a connection whose other end is elsewhere is a short stub
-- toward the nearest screen edge, carrying that end's initial.

local loom = require("lib/loom")

local M = {}

M.MAX_THREADS = 24
local JUMP_ORDER = { workflow = 1, navigation = 2, association = 3, dependency = 4 }

-- Where a jump from `oid` goes: the connected objects in order — workflow's next first, then navigation,
-- association, and dependency — each once; containment never (that is membership, not a route).
function M.targets(doc, oid)
    local list = {}
    for _, r in ipairs(loom.related(doc, oid)) do
        local c = doc.connections[r.via]
        if c and c.kind ~= "containment" and doc.objects[r.id] then
            -- a directed link is a route only from its source; backwards it is still a way back, but later
            local back = c.directed and not r.out
            list[#list + 1] = { id = r.id, kind = c.kind, rank = (JUMP_ORDER[c.kind] or 9) + (back and 10 or 0) }
        end
    end
    table.sort(list, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end; return a.id < b.id end)
    local out, seen = {}, {}
    for _, t in ipairs(list) do if not seen[t.id] then out[#out + 1] = t.id; seen[t.id] = true end end
    return out
end

-- The next target after `last` (a jump pressed again keeps going round), or the first.
function M.next_target(doc, oid, last)
    local t = M.targets(doc, oid)
    if #t == 0 then return nil end
    for i, id in ipairs(t) do if id == last then return t[(i % #t) + 1] end end
    return t[1]
end

-- What depends on `oid`: objects that have a dependency link pointing at it (or undirected ones touching it).
function M.dependants(doc, oid)
    local out = {}
    for _, r in ipairs(loom.related(doc, oid)) do
        local c = doc.connections[r.via]
        if c and c.kind == "dependency" and (not c.directed or c.to == oid) then out[#out + 1] = r.id end
    end
    return out
end

-- Connect two objects (a structure or an environment works the same). Directed for a workflow.
function M.link(doc, from, to, kind)
    kind = kind or "association"
    return loom.connect(doc, from, to, kind, kind == "workflow" or kind == "dependency")
end

-- Every connection touching `oid`, removed.
function M.unlink_all(doc, oid)
    local n = 0
    for _, r in ipairs(loom.related(doc, oid)) do
        if doc.connections[r.via] and doc.connections[r.via].kind ~= "containment" then loom.disconnect(doc, r.via); n = n + 1 end
    end
    return n
end

local function centre(o) return o.at[1] + o.at[3] / 2, o.at[2] + o.at[4] / 2 end

-- The threads on workspace `ws` (screen W × H, its origin ox, oy in the compositor's layout): one record
-- each — { x1, y1, x2, y2, cx, cy (the curve's control point), ax, ay, bx, by (the arrowhead's two wing
-- tips, at the end), kind (0 association · 1 workflow · 2 navigation · 3 dependency), directed, stub (the
-- other end is elsewhere), label (its initial), lit (it touches `focus`) }.
local KIND = { association = 0, workflow = 1, navigation = 2, dependency = 3 }
function M.threads(doc, ws, W, H, ox, oy, focus)
    ox, oy = ox or 0, oy or 0
    local out = {}
    for _, cid in ipairs(loom.sorted_ids(doc.connections)) do
        local c = doc.connections[cid]
        local a, b = doc.objects[c.from], doc.objects[c.to]
        if #out < M.MAX_THREADS and c.kind ~= "containment" and a and b and a.at and b.at then
            local a_here = a.state == "live" and a.workspace == ws
            local b_here = b.state == "live" and b.workspace == ws
            if a_here or b_here then
                local x1, y1, x2, y2, stub
                if a_here and b_here then
                    x1, y1 = centre(a); x2, y2 = centre(b); stub = false
                else
                    -- one end here: a short stub from its window toward the nearest screen edge
                    local here = a_here and a or b
                    x1, y1 = centre(here)
                    local lx, ly = x1 - ox, y1 - oy
                    local dl, dr, dt, db = lx, W - lx, ly, H - ly
                    local m = math.min(dl, dr, dt, db)
                    if m == dl then x2, y2 = ox + 18, y1 elseif m == dr then x2, y2 = ox + W - 18, y1
                    elseif m == dt then x2, y2 = x1, oy + 18 else x2, y2 = x1, oy + H - 18 end
                    stub = true
                    if not a_here then x1, y1, x2, y2 = x2, y2, x1, y1 end      -- keep its direction
                end
                local dx, dy = x2 - x1, y2 - y1
                local len = math.sqrt(dx * dx + dy * dy)
                local sag = math.max(8, math.min(80, len * 0.15))
                local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2 + sag
                -- the arrowhead: along the curve's last direction (control point → end)
                local ex, ey = x2 - cx, y2 - cy
                local el = math.sqrt(ex * ex + ey * ey); if el < 0.001 then el = 1 end
                ex, ey = ex / el, ey / el
                local ax, ay = x2 - ex * 9 - ey * 4.5, y2 - ey * 9 + ex * 4.5
                local bx, by = x2 - ex * 9 + ey * 4.5, y2 - ey * 9 - ex * 4.5
                local far = a_here and b or a
                local app = far.app ~= "" and far.app or "?"
                out[#out + 1] = { x1 = x1 - ox, y1 = y1 - oy, x2 = x2 - ox, y2 = y2 - oy, cx = cx - ox, cy = cy - oy,
                                  ax = ax - ox, ay = ay - oy, bx = bx - ox, by = by - oy,
                                  kind = KIND[c.kind] or 0, directed = c.directed, stub = stub,
                                  label = string.upper(string.sub(app, 1, 1)),
                                  lit = focus ~= nil and (c.from == focus or c.to == focus) }
            end
        end
    end
    return out
end

return M
