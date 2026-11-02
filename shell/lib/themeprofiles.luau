-- Reusable, portable mooi theme packages.
-- A package captures visual settings only: it never carries shortcuts, privacy choices,
-- workspace assignments, app preferences, personal identity or other behavioural state.
-- Pure: package validation and application are unit-tested under Lua 5.4.

local config = require("lib/config")
local theme = require("lib/theme")

local M = {}
M.FORMAT = "mooi-theme"
M.VERSION = 1

-- The visual boundary is deliberately explicit. A theme can shape the desktop without
-- silently changing how it behaves or what personal data it exposes.
M.PATHS = {
    "theme.preset", "theme.source", "theme.mode", "theme.light_at", "theme.dark_at",
    "theme.overrides", "theme.scheme", "theme.color_index", "theme.contrast",
    "theme.signal", "theme.finish", "theme.saturation",
    "look.corners", "look.corner_size",
    "fx.glow", "fx.aberration",
    "motion.speed",
    "bar.style", "bar.surface", "bar.radius", "bar.frame", "bar.ground",
    "bar.rail", "bar.accents", "bar.helix_frame", "bar.edge", "bar.outline_width",
    "bar.outline_colour", "bar.shadow", "bar.opacity", "bar.frost", "bar.smoke",
    "bar.bg", "bar.bg_colour", "bar.bg_light", "bar.bg_sat", "bar.bg_hue",
    "desktop.border", "desktop.border_colour", "desktop.rounding", "desktop.dim_inactive",
    "desktop.opacity_active", "desktop.opacity_inactive", "desktop.shadow",
    "desktop.shadow_size", "desktop.blur", "desktop.blur_vibrancy", "desktop.blur_xray",
    "desktop.blur_popups", "desktop.blur_variant", "desktop.wobble", "desktop.motion_blur",
    "signals.density", "signals.chamfer", "signals.travel", "signals.effects",
}

local allowed, schema = {}, {}
for _, path in ipairs(M.PATHS) do allowed[path] = true end
for _, row in ipairs(config.SCHEMA) do schema[row.path] = true end
for _, path in ipairs(M.PATHS) do
    assert(schema[path], "theme package path is not in config schema: " .. path)
end

local function copy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, x in pairs(v) do out[k] = copy(x, seen) end
    return out
end

local function get(t, path)
    local node = t
    for key in string.gmatch(path, "[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

local function set(t, path, value)
    local node, keys = t, {}
    for key in string.gmatch(path, "[^.]+") do keys[#keys + 1] = key end
    for i = 1, #keys - 1 do
        if type(node[keys[i]]) ~= "table" then node[keys[i]] = {} end
        node = node[keys[i]]
    end
    node[keys[#keys]] = copy(value)
end

local function plain_text(value, max)
    return type(value) == "string" and #value > 0 and #value <= max
        and string.find(value, "%S") ~= nil and not string.find(value, "[%c]")
end

local function known_overrides(settings)
    local overrides = settings.theme and settings.theme.overrides
    if type(overrides) ~= "table" then return true end
    local known = {}
    for _, token in ipairs(theme.TOKENS) do known[token] = true end
    for token in pairs(overrides) do
        if not known[token] then return false, "unknown colour token: " .. tostring(token) end
    end
    return true
end

local function collect_paths(node, prefix, found)
    if prefix == "theme.overrides" then
        found[prefix] = true
        return
    end
    if type(node) ~= "table" then
        found[prefix] = true
        return
    end
    local any = false
    for key, value in pairs(node) do
        any = true
        local path = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
        collect_paths(value, path, found)
    end
    if not any and prefix ~= "" then found[prefix] = true end
end

-- Validate and canonicalize a decoded package. Returns package, nil or nil, reason.
function M.validate(raw)
    if type(raw) ~= "table" then return nil, "package must be a JSON object" end
    local top_level = { format = true, version = true, name = true, description = true, settings = true }
    for key in pairs(raw) do
        if not top_level[key] then return nil, "unsupported package field: " .. tostring(key) end
    end
    if raw.format ~= M.FORMAT then return nil, "not a mooi theme package" end
    if raw.version ~= M.VERSION then return nil, "unsupported theme package version" end
    if not plain_text(raw.name, 48) then return nil, "package name must be 1–48 plain characters" end
    if raw.description ~= nil and (type(raw.description) ~= "string" or #raw.description > 160
        or string.find(raw.description, "[%c]")) then
        return nil, "description must be plain text up to 160 characters"
    end
    if type(raw.settings) ~= "table" then return nil, "package settings must be an object" end

    local found = {}
    collect_paths(raw.settings, "", found)
    local paths, count = {}, 0
    for path in pairs(found) do
        if not allowed[path] then return nil, "setting is not part of a theme package: " .. path end
        paths[#paths + 1] = path
        count = count + 1
    end
    if count == 0 then return nil, "package contains no theme settings" end
    table.sort(paths)

    local normalized, problems, notes = config.validate(copy(raw.settings))
    if #problems > 0 then return nil, table.concat(problems, "; ") end
    if #notes > 0 then return nil, table.concat(notes, "; ") end
    local ok, why = known_overrides(normalized)
    if not ok then return nil, why end

    local settings = {}
    for _, path in ipairs(paths) do
        local value = get(normalized, path)
        if value ~= nil then set(settings, path, value) end
    end
    return {
        format = M.FORMAT,
        version = M.VERSION,
        name = raw.name,
        description = raw.description or "",
        settings = settings,
    }
end

-- Capture the current validated visual settings as a portable package.
function M.capture(current, name, description)
    if type(current) ~= "table" then return nil, "current settings must be an object" end
    local normalized, problems = config.validate(copy(current))
    if #problems > 0 then return nil, table.concat(problems, "; ") end
    local settings = {}
    for _, path in ipairs(M.PATHS) do
        local value = get(normalized, path)
        if value ~= nil then set(settings, path, value) end
    end
    local package, why = M.validate({
        format = M.FORMAT, version = M.VERSION,
        name = name or "Custom theme", description = description or "",
        settings = settings,
    })
    if not package then return nil, why end
    return package
end

-- Apply only the package's visual paths. Every unrelated setting in the current document,
-- including unknown settings owned by another version or integration, is preserved.
function M.apply(current, raw_package)
    if type(current) ~= "table" then return nil, "current settings must be an object" end
    local package, why = M.validate(raw_package)
    if not package then return nil, why end
    local out = copy(current)
    for _, path in ipairs(M.PATHS) do
        local value = get(package.settings, path)
        if value ~= nil then set(out, path, value) end
    end
    return out
end

return M
