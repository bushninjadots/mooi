-- The bounded workspace map. Pure, so it is testable under Lua 5.4: it never touches
-- pleamar.
--
-- The map is the positions mooi shows for workspaces, whether or not the compositor has
-- created them yet, and it is the only place workspace state is turned into rows:
-- **the Mechanism's chain** draws it, **the Atlas's move strip** draws it, and nothing
-- else mirrors workspace state. `id` is the workspace number the compositor uses (the
-- model is written for Hyprland, whose workspaces are numbered), so a row's id is also
-- what `workspaces.focus` is told.

local M = {}

-- Characters, not bytes: a workspace called "Ñandú" or "音楽" must not be cut through the
-- middle of a letter. Text that is not valid UTF-8 is counted (and cut) by bytes.
local function length(text) return utf8.len(text) or #text end
local function head(text, n)
    if not utf8.len(text) then return string.sub(text, 1, n) end
    local stop = utf8.offset(text, n + 1)
    return stop and string.sub(text, 1, stop - 1) or text
end
local function rear(text, n)
    if not utf8.len(text) then return string.sub(text, #text - n + 1) end
    local from = utf8.offset(text, -n)
    return from and string.sub(text, from) or text
end

-- A text, trimmed and shortened to what the bar can show. The scene cannot slice text
-- (there is no substring in the language), so the shortening happens here.
function M.short(text, n)
    n = math.floor(tonumber(n) or 3)
    if n < 1 then n = 1 end
    if type(text) ~= "string" then return "" end
    if length(text) <= n then return text end
    return head(text, n)
end

-- The end of a path, for a plate 196 px wide: `…/mooi/settings.json`.
function M.tail(text, n)
    n = math.floor(tonumber(n) or 20)
    if n < 2 then n = 2 end
    if type(text) ~= "string" then return "" end
    if length(text) <= n then return text end
    return "\226\128\166" .. rear(text, n - 1)   -- an ellipsis, then the tail
end

-- What a position says on the bar: a named workspace's name, shortened; a workspace with no
-- name of its own, its number — zero-padded to two places, so the chain reads 01 … 10 the way
-- the rest of the instrument does. Hyprland calls an unnamed workspace after its own number,
-- so a name that *is* the number counts as no name at all.
function M.label(name, id)
    local number = tostring(math.floor(tonumber(id) or 0))
    if type(name) ~= "string" or name == "" or name == number then
        if #number == 1 then return "0" .. number end
        return number
    end
    return M.short(name, 3)
end

-- `workspaces` is what the `workspaces` service reported: { id, name, windows, monitor }.
-- `active` is the workspace the compositor says is focused. Rows come out in order, one
-- per position, 1 to `limit` — and further, to the active workspace or the last one holding
-- windows when either lies past it: the setting is how many the switcher always shows, never
-- a wall the focus can go behind (a map of 4 while on workspace 7 parked the switcher on the
-- first slot, and it never moved again — found 2026-10-20). Clamped to 16, the model's size.
function M.rows(workspaces, active, limit)
    limit = math.floor(tonumber(limit) or 10)
    if limit < 1 then limit = 1 elseif limit > 16 then limit = 16 end
    active = tonumber(active) or 0
    if active ~= math.floor(active) then active = 0 end

    local found = {}
    for _, workspace in ipairs(type(workspaces) == "table" and workspaces or {}) do
        local id = tonumber(workspace.id)
        if id and id >= 1 and id <= 99 and id == math.floor(id) then
            found[id] = {
                windows = math.max(0, tonumber(workspace.windows) or 0),
                name = type(workspace.name) == "string" and workspace.name or "",
                monitor = type(workspace.monitor) == "string" and workspace.monitor or "",
            }
        end
    end

    local last = limit
    if active >= 1 and active <= 16 then last = math.max(last, active) end
    for id, there in pairs(found) do
        if id <= 16 and there.windows > 0 then last = math.max(last, id) end
    end
    local out = {}
    for id = 1, last do
        local there = found[id]
        out[#out + 1] = {
            id = id,
            windows = there and there.windows or 0,
            active = id == active,
            exists = there ~= nil,
            name = there and there.name or "",
            monitor = there and there.monitor or "",
            label = M.label(there and there.name or "", id),
            icon = "",
        }
    end
    -- pills: an occupied workspace whose next one is occupied too is joined to it
    for i, r in ipairs(out) do
        local nxt = out[i + 1]
        r.joined = r.windows > 0 and nxt ~= nil and nxt.windows > 0
    end
    return out
end

return M
