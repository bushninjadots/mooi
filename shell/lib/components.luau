-- mooi component descriptors: the safe, editor-facing catalogue for visual components.
-- Pure Lua 5.4 / Luau. Descriptors describe existing scene components; they do not render,
-- execute callbacks, or own application state. See docs/COMPONENT-SYSTEM.md.
local M = { VERSION = 1 }

local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end

local registry = {
    ["ferrolume.button"] = {
        id = "ferrolume.button",
        name = "Ferrolume Action",
        category = "actions",
        description = "Compact chamfered action plate used by Settings.",
        source = { file = "shell/ui/ferrolume.plm", library = "FerrolumeParts", component = "SButton" },
        design = { direction = "industrial-technical", surface = "ferrolume" },
        geometry = {
            mode = "fixed-height",
            height = 30,
            min_width = 32,
            preferred_width = 104,
            bounds = "component",
        },
        properties = {
            { name = "x", type = "number", required = true, editor = false, unit = "px" },
            { name = "y", type = "number", required = true, editor = false, unit = "px" },
            { name = "w", type = "number", required = true, min = 32, max = 720, default = 104, editor = true, unit = "px", group = "layout" },
            { name = "label", type = "string", required = true, max_length = 48, default = "Action", editor = true, group = "content" },
            { name = "hot", type = "boolean", default = false, editor = true, group = "appearance" },
            { name = "en", type = "boolean", default = true, editor = true, group = "behaviour" },
        },
        bindings = {
            { name = "press", type = "event", required = true, editor = false },
            { name = "n", type = "number", required = true, editor = false, description = "Payload emitted through press." },
        },
        states = {
            { name = "enabled", source = "en", implemented = true },
            { name = "hovered", source = "hit.hover", implemented = true },
            { name = "pressed", source = "hit.pressed", implemented = false, note = "No pressed visual is currently drawn." },
            { name = "focused", source = "keyboard focus", implemented = false },
        },
        events = { { name = "press", payload = "n", trigger = "pointer press", implemented = true } },
        theme = { roles = { "steel_700", "steel_500", "steel_300", "engrave", "phos", "ember_fill" } },
        motion = { hover = "immediate", press = "none", reduced_motion_safe = true },
        preview = { kind = "component", label = "Action", variant = "compact", background = "surface.primary" },
        constraints = { min_width = 32, max_width = 720, fixed_height = 30, resizable = { "w" } },
    },
    ["lumen.button"] = {
        id = "lumen.button",
        name = "Lumen Action",
        category = "actions",
        description = "Variable-height cut plate with solid or outlined tone treatment for Wallpaper Studio.",
        source = { file = "shell/ui/lumen.plm", library = "Lumen", component = "Button" },
        design = { direction = "minimal-elegant", surface = "lumen" },
        geometry = {
            mode = "explicit",
            min_width = 32,
            min_height = 24,
            preferred_width = 112,
            preferred_height = 34,
            bounds = "component",
        },
        properties = {
            { name = "x", type = "number", required = true, editor = false, unit = "px" },
            { name = "y", type = "number", required = true, editor = false, unit = "px" },
            { name = "w", type = "number", required = true, min = 32, max = 720, default = 112, editor = true, unit = "px", group = "layout" },
            { name = "h", type = "number", required = true, min = 24, max = 120, default = 34, editor = true, unit = "px", group = "layout" },
            { name = "label", type = "string", required = true, max_length = 48, default = "Action", editor = true, group = "content" },
            { name = "tone", type = "color", required = true, default = "accent.primary", editor = true, group = "appearance" },
            { name = "solid", type = "boolean", required = true, default = false, editor = true, group = "appearance" },
            { name = "en", type = "boolean", default = true, editor = true, group = "behaviour" },
        },
        bindings = {
            { name = "press", type = "event", required = true, editor = false },
            { name = "n", type = "number", required = true, editor = false, description = "Payload emitted through press." },
        },
        states = {
            { name = "enabled", source = "en", implemented = true },
            { name = "hovered", source = "hit.hover", implemented = true },
            { name = "pressed", source = "hit.pressed", implemented = false, note = "No pressed visual is currently drawn." },
            { name = "focused", source = "keyboard focus", implemented = false },
        },
        events = { { name = "press", payload = "n", trigger = "pointer press", implemented = true } },
        theme = { roles = { "hull_raised", "well", "trace", "flare", "engrave", "ink" }, accepts_user_tone = true },
        motion = { hover = "immediate", press = "none", reduced_motion_safe = true },
        preview = { kind = "component", label = "Action", variant = "solid-or-outline", background = "surface.primary" },
        constraints = { min_width = 32, max_width = 720, min_height = 24, max_height = 120, resizable = { "w", "h" } },
    },
}

local function descriptor(id)
    return type(id) == "string" and registry[id] or nil
end

function M.get(id)
    local item = descriptor(id)
    return item and clone(item) or nil
end

function M.list(category)
    local out = {}
    for id, item in pairs(registry) do
        if category == nil or item.category == category then out[#out + 1] = clone(item) end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function M.ids()
    local out = {}
    for id in pairs(registry) do out[#out + 1] = id end
    table.sort(out)
    return out
end

-- Validate only editable/configurable properties. Event handlers and payload wiring are
-- deliberately not accepted here: the visual editor must never turn user property data into code.
function M.validate(id, values)
    local item = descriptor(id)
    if not item then return false, { "unknown component: " .. tostring(id) } end
    if type(values) ~= "table" then return false, { "properties must be a table" } end

    local schema, problems = {}, {}
    for _, prop in ipairs(item.properties) do schema[prop.name] = prop end
    for name, value in pairs(values) do
        local prop = schema[name]
        if not prop then
            problems[#problems + 1] = "unknown or non-editable property: " .. tostring(name)
        else
            local kind = prop.type
            local valid = (kind == "number" and type(value) == "number" and value == value
                    and value ~= math.huge and value ~= -math.huge)
                or (kind == "boolean" and type(value) == "boolean")
                or ((kind == "string" or kind == "color") and type(value) == "string")
            if not valid then
                problems[#problems + 1] = name .. " must be " .. kind
            elseif kind == "number" then
                if prop.min and value < prop.min then problems[#problems + 1] = name .. " is below " .. prop.min end
                if prop.max and value > prop.max then problems[#problems + 1] = name .. " is above " .. prop.max end
            elseif kind == "string" and prop.max_length and #value > prop.max_length then
                problems[#problems + 1] = name .. " is longer than " .. prop.max_length .. " characters"
            elseif kind == "color" and not value:match("^[%w_%.%-#]+$") then
                problems[#problems + 1] = name .. " must be a theme role or hex colour"
            end
        end
    end
    for _, prop in ipairs(item.properties) do
        if prop.required and values[prop.name] == nil and prop.default == nil then
            problems[#problems + 1] = "missing required property: " .. prop.name
        end
    end
    table.sort(problems)
    return #problems == 0, problems
end

function M.defaults(id)
    local item = descriptor(id)
    if not item then return nil end
    local out = {}
    for _, prop in ipairs(item.properties) do
        if prop.default ~= nil then out[prop.name] = clone(prop.default) end
    end
    return out
end

return M
