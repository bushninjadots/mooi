-- A Presence (D208, spec §4): one thing left on the desktop — what it shows (a source), how (form, mode),
-- and where it lives (its memory, kept in surface.json). Pure. Positions are fractions of the screen for the
-- Presence's centre, so a different monitor still finds it; every load clamps it back onto the screen and
-- drops what it cannot trust (an unknown source or form, a position that is not a number), saying why.

local sources = require("lib/surface/sources")

local M = { VERSION = 1, GAP = 12, UNDO = 50 }
M.FORMS = { "pill", "bar", "island", "orb", "freeform", "woven" }
M.MODES = { "ghost", "embedded", "full" }
-- each mode's size (the Presence grows and shrinks between them; the stored w, h are its ghost size)
M.SIZE = { ghost = { 220, 28 }, embedded = { 320, 64 }, full = { 360, 96 } }
-- sources a Presence may show beyond the catalogue (the widgets' import, spec §4)
local EXTRA = { visualiser = true, photo = true, focus = true }

local function known(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
local function source_ok(id)
    if type(id) ~= "string" then return false end
    if sources.get(id) or EXTRA[id] then return true end
    return known(sources.LATER, id)
end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local seq = 0
local function new_id()
    seq = seq + 1
    return string.format("p%x%02x", os.time(), seq % 256)
end

-- its box on a screen ({ w, h }), clamped so it is wholly on it
function M.screen_box(p, screen)
    local w = math.min(p.w or M.SIZE.ghost[1], screen.w)
    local h = math.min(p.h or M.SIZE.ghost[2], screen.h)
    local x = clamp((p.fx or 0.5) * screen.w - w / 2, 0, screen.w - w)
    local y = clamp((p.fy or 0.5) * screen.h - h / 2, 0, screen.h - h)
    return { x = x, y = y, w = w, h = h }
end

-- the centre fraction that puts the box back on the screen
local function settle(p, screen)
    local b = M.screen_box(p, screen)
    p.fx, p.fy = (b.x + b.w / 2) / screen.w, (b.y + b.h / 2) / screen.h
    return p
end

function M.new(source, x, y, screen)
    local p = { id = new_id(), source = source, form = "pill", mode = "ghost",
                fx = x / screen.w, fy = y / screen.h, w = M.SIZE.ghost[1], h = M.SIZE.ghost[2],
                workspace = "all", state = "persistent", links = {} }
    return settle(p, screen)
end

local function num(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

function M.load(doc, screen)
    local out, problems = {}, {}
    local list = type(doc) == "table" and type(doc.presences) == "table" and doc.presences or {}
    for i, e in ipairs(list) do
        local why
        if type(e) ~= "table" then why = "not an object"
        elseif not source_ok(e.source) then why = "unknown source " .. tostring(e.source)
        elseif e.form ~= nil and not known(M.FORMS, e.form) then why = "unknown form " .. tostring(e.form)
        elseif not num(e.fx) or not num(e.fy) then why = "position is not a number" end
        if why then
            problems[#problems + 1] = string.format("presence %d (%s): %s", i, tostring(type(e) == "table" and e.id), why)
        else
            local p = { id = type(e.id) == "string" and e.id or new_id(), source = e.source, form = e.form or "pill",
                        mode = known(M.MODES, e.mode) and e.mode or "ghost", fx = e.fx, fy = e.fy,
                        w = num(e.w) and e.w > 0 and e.w or M.SIZE.ghost[1], h = num(e.h) and e.h > 0 and e.h or M.SIZE.ghost[2],
                        workspace = e.workspace == nil and "all" or e.workspace, state = type(e.state) == "string" and e.state or "persistent",
                        links = type(e.links) == "table" and e.links or {}, options = type(e.options) == "table" and e.options or nil }
            out[#out + 1] = settle(p, screen)
        end
    end
    return out, problems
end

function M.save(list)
    local ps = {}
    for i, p in ipairs(list or {}) do
        ps[i] = { id = p.id, source = p.source, form = p.form, mode = p.mode, fx = p.fx, fy = p.fy, w = p.w, h = p.h,
                  workspace = p.workspace, state = p.state, links = p.links, options = p.options }
    end
    return { version = M.VERSION, presences = ps }
end

local function overlap(a, b)
    local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
    local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
    if ox <= 0 or oy <= 0 then return 0 end
    return ox * oy
end

-- A drop onto another Presence is nudged clear: to the nearest side (below, above, right, left) where it
-- overlaps nothing, GAP apart; with no such side it stays where it was dropped.
function M.place(list, p, screen)
    local b = M.screen_box(p, screen)
    local hit
    for _, q in ipairs(list or {}) do
        if q ~= p and overlap(b, M.screen_box(q, screen)) > 0 then hit = q; break end
    end
    if not hit then return p end
    local h = M.screen_box(hit, screen)
    local tries = {
        { b.x, h.y + h.h + M.GAP }, { b.x, h.y - b.h - M.GAP },
        { h.x + h.w + M.GAP, b.y }, { h.x - b.w - M.GAP, b.y },
    }
    for _, t in ipairs(tries) do
        local c = { x = t[1], y = t[2], w = b.w, h = b.h }
        if c.x >= 0 and c.y >= 0 and c.x + c.w <= screen.w and c.y + c.h <= screen.h then
            local free = true
            for _, q in ipairs(list) do if q ~= p and overlap(c, M.screen_box(q, screen)) > 0 then free = false end end
            if free then p.fx, p.fy = (c.x + c.w / 2) / screen.w, (c.y + c.h / 2) / screen.h; return p end
        end
    end
    return p
end

-- Undo and redo over whole arrangements (surface.json documents): push after every edit; undo gives the one
-- before; a new edit after an undo clears what could have been redone. At most UNDO kept.
function M.undo_stack()
    local st, at = {}, 0
    local u = {}
    function u.push(doc)
        for i = #st, at + 1, -1 do st[i] = nil end
        st[#st + 1] = doc
        if #st > M.UNDO then table.remove(st, 1) end
        at = #st
    end
    function u.undo()
        if at <= 1 then return nil end
        at = at - 1
        return st[at]
    end
    function u.redo()
        if at >= #st then return nil end
        at = at + 1
        return st[at]
    end
    return u
end

return M
