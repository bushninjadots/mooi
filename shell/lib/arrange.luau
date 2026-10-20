-- Arranging the bar by an entry's place: what the settings window's Layout page does to the
-- three lists (bar.left, bar.center, bar.right; lib/barlayout). Every operation names a member
-- by where it is — its side, its entry `i`, its place `j` in that entry's group — because a
-- spacer (`gap`) can be there many times and has no name of its own. Pure, so tests/unit runs it.
-- Each returns new lists and where the member it moved is now (side, i, j), or the lists alone.

local barlayout = require("lib/barlayout")

local M = {}

M.SIDES = { "left", "center", "right" }
local NEXT = { left = { nil, "center" }, center = { "left", "right" }, right = { "center", nil } }

local function members(entry)
    if barlayout.is_spacer(entry) then return { entry } end
    return barlayout.split(entry) or {}
end

function M.copy(b)
    local out = {}
    for _, side in ipairs(M.SIDES) do
        out[side] = {}
        for i, e in ipairs(b[side] or {}) do out[side][i] = e end
    end
    return out
end

-- Every member on the bar, in order: { side, i, j, id, n (members in its entry) }.
function M.items(b)
    local out = {}
    for _, side in ipairs(M.SIDES) do
        for i, e in ipairs(b[side] or {}) do
            local ms = members(e)
            for j, id in ipairs(ms) do out[#out + 1] = { side = side, i = i, j = j, id = id, n = #ms } end
        end
    end
    return out
end

-- Whether a module is on the bar at all.
function M.placed(b, id)
    for _, it in ipairs(M.items(b)) do if it.id == id then return true end end
    return false
end

-- Takes the member at (side, i, j) out; returns the lists and what was taken.
local function take(L, side, i, j)
    local list = L[side]
    local ms = members(list[i])
    local id = ms[j]
    if not id then return L, nil end
    table.remove(ms, j)
    if #ms == 0 then table.remove(list, i) else list[i] = table.concat(ms, "+") end
    return L, id
end

-- One place left (dir −1) or right (+1). Inside a group it trades places with its neighbour,
-- and at the group's edge it steps out of it; an entry trades places with the next entry, and
-- at the end of its list it crosses into the next list, so anything can be walked anywhere.
function M.move(b, side, i, j, dir)
    local L = M.copy(b)
    local list = L[side]
    if not list or not list[i] then return L end
    local ms = members(list[i])
    if #ms > 1 then
        local k = j + dir
        if k >= 1 and k <= #ms then
            ms[j], ms[k] = ms[k], ms[j]
            list[i] = table.concat(ms, "+")
            return L, side, i, k
        end
        local id = ms[j]
        table.remove(ms, j)
        list[i] = table.concat(ms, "+")
        local at = (dir < 0) and i or (i + 1)
        table.insert(list, at, id)
        return L, side, at, 1
    end
    local k = i + dir
    if k >= 1 and k <= #list then
        list[i], list[k] = list[k], list[i]
        return L, side, k, 1
    end
    local other = NEXT[side][(dir < 0) and 1 or 2]
    if not other then return L, side, i, j end
    local entry = table.remove(list, i)
    local dest = L[other]
    if dir < 0 then dest[#dest + 1] = entry; return L, other, #dest, 1 end
    table.insert(dest, 1, entry)
    return L, other, 1, 1
end

-- To the end of another list, on its own.
function M.to_side(b, side, i, j, dest)
    local L, id = take(M.copy(b), side, i, j)
    if not id or not L[dest] then return M.copy(b) end
    L[dest][#L[dest] + 1] = id
    return L, dest, #L[dest], 1
end

-- A module on its own joins the entry before it (dir −1) or after it (+1); spacers never join.
function M.join(b, side, i, j, dir)
    local L = M.copy(b)
    local list = L[side]
    if not list or not list[i] then return L end
    local ms = members(list[i])
    local k = i + dir
    if #ms ~= 1 or barlayout.is_spacer(ms[1]) or k < 1 or k > #list or barlayout.is_spacer(list[k]) then return L, side, i, j end
    local id = ms[1]
    local others = members(list[k])
    if dir < 0 then list[k] = list[k] .. "+" .. id else list[k] = id .. "+" .. list[k] end
    table.remove(list, i)
    local at = (dir < 0) and k or (k - 1)
    return L, side, at, (dir < 0) and (#others + 1) or 1
end

-- Out of its group: an entry of its own, just after the group.
function M.split(b, side, i, j)
    local L = M.copy(b)
    local list = L[side]
    if not list or not list[i] then return L end
    local ms = members(list[i])
    if #ms < 2 then return L, side, i, j end
    local id = table.remove(ms, j)
    list[i] = table.concat(ms, "+")
    table.insert(list, i + 1, id)
    return L, side, i + 1, 1
end

-- Off the bar (a spacer is gone; a module goes back to the shelf).
function M.remove(b, side, i, j)
    local L, id = take(M.copy(b), side, i, j)
    return L, id
end

-- A module (or a spacer) at the end of a list. A module already on the bar moves there.
function M.add(b, id, dest)
    local L = M.copy(b)
    if not barlayout.is_spacer(id) then
        for _, it in ipairs(M.items(L)) do
            if it.id == id then L = take(L, it.side, it.i, it.j); break end
        end
    end
    if not L[dest] then return L end
    L[dest][#L[dest] + 1] = id
    return L, dest, #L[dest], 1
end

return M
