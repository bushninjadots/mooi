-- Control Nexus node contract. Pure Lua 5.4 / Luau; no Pleamar globals.
-- Coordinates are normalized to the Nexus work area so layouts survive resolution changes.

local M = {}

local KINDS = {
    system = true, identity = true, control = true, monitor = true,
    collection = true, application = true, workspace = true,
}

local function finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function M.create(spec)
    if type(spec) ~= "table" then return nil, "node must be a table" end
    if type(spec.id) ~= "string" or not spec.id:match("^[%w][%w%._%-]*$") then
        return nil, "node id must be a stable non-empty identifier"
    end
    if type(spec.label) ~= "string" or spec.label == "" then
        return nil, "node label must be a non-empty string"
    end
    local kind = spec.kind or "control"
    if not KINDS[kind] then return nil, "unsupported node kind: " .. tostring(kind) end
    local x, y = spec.x or 0.5, spec.y or 0.5
    if not finite_number(x) or not finite_number(y) then
        return nil, "node coordinates must be finite numbers"
    end
    local width, height = spec.width or 0.16, spec.height or 0.12
    if not finite_number(width) or not finite_number(height) or width <= 0 or height <= 0 then
        return nil, "node dimensions must be positive finite numbers"
    end
    return {
        id = spec.id,
        label = spec.label,
        kind = kind,
        group = type(spec.group) == "string" and spec.group or "system",
        x = clamp(x, 0, 1),
        y = clamp(y, 0, 1),
        width = clamp(width, 0.04, 1),
        height = clamp(height, 0.04, 1),
        enabled = spec.enabled ~= false,
        pinned = spec.pinned == true,
        detail = type(spec.detail) == "string" and spec.detail or "",
        actions = type(spec.actions) == "table" and table.clone and table.clone(spec.actions)
            or (type(spec.actions) == "table" and { table.unpack(spec.actions) } or {}),
    }
end

function M.move(node, x, y)
    if type(node) ~= "table" then return nil, "node must be a table" end
    if not finite_number(x) or not finite_number(y) then return nil, "coordinates must be finite numbers" end
    local moved = {}
    for key, value in pairs(node) do moved[key] = value end
    moved.x, moved.y = clamp(x, 0, 1), clamp(y, 0, 1)
    return moved
end

function M.validate(node)
    local normalized, why = M.create(node)
    if not normalized then return false, why end
    return true
end

M.KINDS = { "system", "identity", "control", "monitor", "collection", "application", "workspace" }
return M
