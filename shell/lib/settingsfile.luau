-- One write policy for settings.json (audit 2026-10-31, F3).
--
-- Six programs write this file: the bar, the settings window, the music player, the wallpaper
-- studio, the Nexus and the notch. Writing an in-memory copy whole meant a save could revert a
-- change another program had just made — the settings window reverting a bar toggle, or the bar
-- reverting a change made in the window. Programs that re-read the file before writing (the
-- player, the studio, the Nexus) are already correct; this is the same rule for the ones that
-- edit a copy: read the file as it is now, lay only the leaves this program changed over it,
-- write that.
--
-- Pure, so tests/unit runs it: `changes` and `merge` never touch the filesystem, and `save` is
-- the thin part that does (`sys.call("files.write", …)` behind a pcall).

local M = {}

function M.copy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, x in pairs(v) do out[k] = M.copy(x, seen) end
    return out
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- A list (bar.left, …) is replaced whole, never key by key: a merge must not turn `{}` and
-- `{ "a" }` into a table with a string "1" key. Maps that merely happen to be empty (a
-- `theme.overrides` with no overrides) stay maps, so a token key with dots in it is kept as
-- one key.
local function numkeyed(t)
    if type(t) ~= "table" then return false end
    for k in pairs(t) do if type(k) == "number" then return true end end
    return false
end

-- Every leaf of `after` that differs from `before`, as { keys = { … }, value = … }: the key
-- path itself, not a dotted string, because a setting key may contain dots
-- (`theme.overrides["accent.primary"]`).
function M.changes(before, after)
    local out = {}
    local function walk(b, a, keys)
        for k, v in pairs(a) do
            local bk = type(b) == "table" and b[k] or nil
            local kk = {}
            for i, x in ipairs(keys) do kk[i] = x end
            kk[#kk + 1] = k
            if type(v) == "table" and type(bk) == "table" and not numkeyed(v) and not numkeyed(bk) then
                walk(bk, v, kk)
            elseif not same(bk, v) then
                out[#out + 1] = { keys = kk, value = M.copy(v) }
            end
        end
    end
    if type(after) == "table" then walk(type(before) == "table" and before or {}, after, {}) end
    return out
end

-- The changes laid onto `doc`, in place; nil values are skipped (settings are never removed,
-- the defaults fill them).
function M.merge(doc, changes)
    if type(doc) ~= "table" then return doc end
    for _, c in ipairs(changes or {}) do
        if c.value ~= nil then
            local node = doc
            for i = 1, #c.keys - 1 do
                local k = c.keys[i]
                if type(node[k]) ~= "table" then node[k] = {} end
                node = node[k]
            end
            node[c.keys[#c.keys]] = M.copy(c.value)
        end
    end
    return doc
end

-- Read, merge, write. `read_doc` returns the file's document, or nil when it cannot be trusted
-- (a broken file is never merged into: there is nothing to keep). Returns the document written
-- and true, or nil and why.
function M.save(sys, path, before, after, read_doc)
    local fresh = read_doc and read_doc() or nil
    if type(fresh) ~= "table" then return nil, "the file could not be read; nothing was written" end
    M.merge(fresh, M.changes(before, after))
    local ok, err = pcall(sys.call, "files.write", path, fresh)
    if not ok then return nil, tostring(err) end
    return fresh
end

return M
