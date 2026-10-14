-- mooi settings: defaults, validation, and what to say about a bad file.
-- Pure: no pleamar globals, so tests/unit runs it under plain Lua 5.4.
-- Written in the subset Lua 5.4 and Luau share.

local M = {}

M.VERSION = 1

-- One row per setting: dotted path, type, default, and limits for numbers.
M.SCHEMA = {
    { path = "spine.clock", kind = "boolean", default = true },
    { path = "spine.max_workspaces", kind = "integer", default = 10, min = 1, max = 16 },
    { path = "island.confirm_close", kind = "boolean", default = true },
    { path = "island.follow_on_send", kind = "boolean", default = false },
    { path = "motion.reduced", kind = "boolean", default = false },
}

local function get(t, path)
    local node = t
    for key in string.gmatch(path, "[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

local function set(t, path, value)
    local node = t
    local keys = {}
    for key in string.gmatch(path, "[^.]+") do keys[#keys + 1] = key end
    for i = 1, #keys - 1 do
        node[keys[i]] = node[keys[i]] or {}
        node = node[keys[i]]
    end
    node[keys[#keys]] = value
end

function M.defaults()
    local out = { version = M.VERSION }
    for _, row in ipairs(M.SCHEMA) do set(out, row.path, row.default) end
    return out
end

local function check(row, value)
    if row.kind == "boolean" then
        if type(value) ~= "boolean" then return false, "expected true or false" end
    elseif row.kind == "integer" then
        if type(value) ~= "number" or value ~= math.floor(value) then return false, "expected a whole number" end
        if value < row.min or value > row.max then
            return false, string.format("expected %d to %d", row.min, row.max)
        end
    end
    return true
end

-- Keys present in the file that the schema does not know.
local function unknown_keys(t, prefix, known, out)
    for key, value in pairs(t) do
        local path = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
        if path ~= "version" then
            if type(value) == "table" and known.sections[path] then
                unknown_keys(value, path, known, out)
            elseif not known.leaves[path] then
                out[#out + 1] = path
            end
        end
    end
end

local function known_paths()
    local known = { leaves = {}, sections = {} }
    for _, row in ipairs(M.SCHEMA) do
        known.leaves[row.path] = true
        local section = string.match(row.path, "^(.*)%.[^.]+$")
        while section do
            known.sections[section] = true
            section = string.match(section, "^(.*)%.[^.]+$")
        end
    end
    return known
end

-- Validate an already-decoded table. Never fails: a bad value falls back to its
-- default and is reported. Returns settings, problems (fatal-ish), notes (harmless).
function M.validate(t)
    local out = M.defaults()
    local problems, notes = {}, {}
    if type(t) ~= "table" then
        problems[#problems + 1] = "settings are not a JSON object; using defaults"
        return out, problems, notes
    end
    if t.version ~= nil and t.version ~= M.VERSION then
        notes[#notes + 1] = string.format("settings say version %s, this mooi reads %d", tostring(t.version), M.VERSION)
    end
    for _, row in ipairs(M.SCHEMA) do
        local value = get(t, row.path)
        if value ~= nil then
            local ok, why = check(row, value)
            if ok then
                set(out, row.path, value)
            else
                problems[#problems + 1] = string.format("%s: %s, got %s; using %s",
                    row.path, why, tostring(value), tostring(row.default))
            end
        end
    end
    local unknown = {}
    unknown_keys(t, "", known_paths(), unknown)
    table.sort(unknown)
    for _, path in ipairs(unknown) do notes[#notes + 1] = "unknown setting ignored: " .. path end
    return out, problems, notes
end

-- From the raw file text. `decode` is pleamar's json.decode (or a test double);
-- it may raise on broken JSON. `raw == nil` means the file does not exist.
function M.parse(raw, decode)
    if raw == nil then return M.defaults(), {}, { "no settings.json yet; using defaults" }, "missing" end
    local ok, t = pcall(decode, raw)
    if not ok then
        return M.defaults(), { "settings.json is not valid JSON (" .. tostring(t) .. "); using defaults" }, {}, "broken"
    end
    local settings, problems, notes = M.validate(t)
    return settings, problems, notes, (#problems == 0) and "ok" or "partial"
end

return M
