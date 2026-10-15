-- The bounded workspace map. Pure, so it is testable under Lua 5.4: it never touches
-- pleamar.
--
-- The map is the positions mooi shows for workspaces, whether or not the compositor has
-- created them yet, and it is the only place workspace state is turned into rows:
-- **the Mechanism's scale** draws it, **the Atlas's move strip** draws it, and nothing
-- else mirrors workspace state. `id` is the workspace number the compositor uses (the
-- model is written for Hyprland, whose workspaces are numbered), so a row's id is also
-- what `workspaces.focus` is told.

local M = {}

-- A text, trimmed and shortened to what the rail can show. The scene cannot slice text
-- (there is no substring in the language), so the shortening happens here.
function M.short(text, n)
    n = math.floor(tonumber(n) or 3)
    if n < 1 then n = 1 end
    if type(text) ~= "string" then return "" end
    if #text <= n then return text end
    return string.sub(text, 1, n)
end

-- The end of a path, for a plate 196 px wide: `…/mooi/settings.json`.
function M.tail(text, n)
    n = math.floor(tonumber(n) or 20)
    if n < 2 then n = 2 end
    if type(text) ~= "string" then return "" end
    if #text <= n then return text end
    return "\226\128\166" .. string.sub(text, #text - n + 2)   -- an ellipsis, then the tail
end

-- What a position says on the rail: a named workspace's name, shortened; a workspace
-- with no name of its own, its number.
function M.label(name, id)
    local number = tostring(math.floor(tonumber(id) or 0))
    if type(name) ~= "string" or name == "" then return number end
    return M.short(name, 3)
end

-- `workspaces` is what the `workspaces` service reported: { id, name, windows, monitor }.
-- `active` is the workspace the compositor says is focused. Rows come out in order, one
-- per configured position, 1 to `limit` (clamped to 16, the model's size).
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

    local out = {}
    for id = 1, limit do
        local there = found[id]
        out[#out + 1] = {
            id = id,
            windows = there and there.windows or 0,
            active = id == active,
            exists = there ~= nil,
            name = there and there.name or "",
            monitor = there and there.monitor or "",
            label = M.label(there and there.name or "", id),
        }
    end
    return out
end

return M
