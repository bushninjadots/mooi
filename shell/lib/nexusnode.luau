-- The Control Nexus node catalogue and the arrangements the environment starts with.
-- Pure: no services, no files. Every node the scene can draw is declared here once, so
-- the renderer, the module library and the settings validator agree about ids, sizes
-- and which real provider a node needs before it may appear.

local M = {}

local CONNECTED = "connected"
local UNAVAILABLE = "unavailable"

local function kind(id, title, category, accent, requires, w, h, minw, minh, maxw, maxh, dw, dh, essential, status, reason)
    return {
        id = id,
        title = title,
        category = category,
        accent = accent,
        status = status or CONNECTED,
        requires = requires,
        reason = reason,
        size = { w = w, h = h },
        min = { w = minw, h = minh },
        max = { w = maxw, h = maxh },
        detail = { w = dw, h = dh },
        essential = essential == true,
        capabilities = { focus = true, resize = true, expand = false, duplicate = false, removable = true },
    }
end

-- Display order is the order the library lists them in. The connected ones are the
-- anchors the environment can show today; the last five have no provider and stay
-- library-only until one exists.
M.TYPES = {
    kind("core", "Nexus Core", "system", "phos", nil,
        260, 260, 200, 200, 520, 520, 420, 420, true),
    kind("system", "System", "system", "phos", nil,
        240, 160, 200, 110, 520, 360, 620, 420, true),
    kind("cpu", "CPU", "system", "phos", nil,
        210, 130, 170, 100, 400, 260, 460, 300, false),
    kind("memory", "Memory", "system", "phos", nil,
        210, 130, 170, 100, 400, 260, 460, 300, false),
    kind("gpu", "GPU", "system", "phos", "gpu",
        210, 130, 170, 100, 400, 260, 460, 300, false),
    kind("thermal", "Thermal", "system", "ember", "sensors",
        210, 130, 170, 100, 400, 260, 460, 300, false),
    kind("storage", "Storage", "system", "flare", nil,
        210, 130, 170, 100, 400, 260, 460, 300, false),
    kind("network", "Network", "connectivity", "flare", nil,
        240, 150, 200, 110, 480, 300, 560, 360, true),
    kind("audio", "Audio", "audio", "phos", nil,
        240, 150, 200, 110, 480, 300, 560, 360, false),
    kind("display", "Display", "system", "phos", "brightness",
        220, 130, 180, 100, 420, 260, 480, 300, false),
    kind("workspaces", "Workspaces", "workspaces", "trace_lit", nil,
        260, 170, 220, 120, 520, 340, 600, 400, false),
    kind("media", "Media", "audio", "phos", "media",
        280, 140, 230, 110, 560, 300, 620, 380, false),
    kind("clock", "Clock", "information", "trace_lit", nil,
        200, 120, 160, 96, 380, 240, 420, 280, true),
    kind("power", "Power", "system", "ember", "battery",
        220, 130, 180, 100, 420, 260, 480, 300, false),
    kind("applications", "Applications", "applications", "trace_lit", "windows",
        240, 150, 200, 110, 480, 300, 560, 360, false, UNAVAILABLE, "No window provider"),
    kind("projects", "Projects", "files", "phos", "projects",
        240, 150, 200, 110, 480, 300, 560, 360, false, UNAVAILABLE, "No project provider"),
    kind("notifications", "Notifications", "information", "flare", "notifications",
        240, 150, 200, 110, 480, 300, 560, 360, false, UNAVAILABLE, "Notifications live in the bar"),
    kind("quickactions", "Quick Actions", "actions", "ember", "actions",
        240, 150, 200, 110, 480, 300, 560, 360, false, UNAVAILABLE, "Not implemented yet"),
    kind("files", "Files", "files", "trace_lit", "files",
        260, 160, 220, 120, 520, 340, 600, 400, false, UNAVAILABLE, "No file provider"),
}

local by_id = {}
for _, def in ipairs(M.TYPES) do by_id[def.id] = def end

function M.get(id)
    return by_id[id]
end

-- Whether a node may appear at all. A missing provider is not an error: the node is
-- simply absent, with the reason the library card shows.
function M.available(id, present)
    local def = by_id[id]
    if not def then return false, "Unknown module" end
    if def.status == UNAVAILABLE then return false, def.reason end
    if def.requires then
        present = present or {}
        if present[def.requires] ~= true then
            local name = def.requires == "sensors" and "sensor" or def.requires
            return false, "No " .. name .. " provider"
        end
    end
    return true
end

local function number(value, fallback)
    local n = tonumber(value)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then return fallback end
    return n
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function place(value, size, extent)
    local high = extent - size
    if high < 0 then return 0 end
    return math.floor(clamp(value, 0, high))
end

-- Instances are stored as plain tables of numbers and booleans because Pleamar rules
-- can write facts but not record fields; the same shape persists and renders.
function M.normalize_nodes(list)
    local out, dropped, seen = {}, 0, {}
    if type(list) ~= "table" then return out, dropped end
    for _, raw in ipairs(list) do
        if #out >= 16 then
            dropped = dropped + 1
        elseif type(raw) ~= "table" then
            dropped = dropped + 1
        else
            local def = by_id[raw.type]
            if not def or seen[def.id] then
                dropped = dropped + 1
            else
                seen[def.id] = true
                local w = clamp(number(raw.w, def.size.w), def.min.w, def.max.w)
                local h = clamp(number(raw.h, def.size.h), def.min.h, def.max.h)
                local essential = raw.essential
                if essential == nil then essential = def.essential end
                out[#out + 1] = {
                    type = def.id,
                    x = number(raw.x, 0),
                    y = number(raw.y, 0),
                    w = w,
                    h = h,
                    vis = raw.vis ~= false,
                    min = raw.min == true,
                    essential = essential == true,
                }
            end
        end
    end
    return out, dropped
end

-- Ratios rather than pixels: the same arrangement has to work on a 1366-wide laptop
-- and a 4K display, and the user moves anything that does not suit them afterwards.
local RATIOS = {
    { "core",       0.50, 0.50 },
    { "system",     0.72, 0.42 },
    { "network",    0.80, 0.20 },
    { "storage",    0.76, 0.70 },
    { "audio",      0.30, 0.44 },
    { "clock",      0.22, 0.20 },
    { "workspaces", 0.24, 0.72 },
    { "media",      0.50, 0.84 },
    { "display",    0.62, 0.70 },
    { "power",      0.88, 0.55 },
}

function M.default_nodes(canvas)
    canvas = canvas or {}
    local cw = number(canvas.w, 1920)
    local ch = number(canvas.h, 892)
    local out = {}
    for _, row in ipairs(RATIOS) do
        local def = by_id[row[1]]
        local w, h = def.size.w, def.size.h
        out[#out + 1] = {
            type = def.id,
            x = place(row[2] * cw - w / 2, w, cw),
            y = place(row[3] * ch - h / 2, h, ch),
            w = w,
            h = h,
            vis = true,
            min = false,
            essential = def.essential,
        }
    end
    return out
end

-- The plate's ids that still mean something in the node world. RX and TX were two
-- readings of one Network node; CPU, Memory and Thermal survive as nodes even though
-- the default arrangement folds them into System.
local LEGACY = {
    output = "audio",
    display = "display",
    network = "network",
    player = "media",
    storage = "storage",
    cpu = "cpu",
    memory = "memory",
    temp = "thermal",
    rx = "network",
    tx = "network",
}

local STYLES = { circuit = true, curved = true, direct = true }
local MODES = { circuit = true, minimal = true }
local BANNERS = { full = true, compact = true, strip = true, hidden = true }
local ACCENTS = { phos = true, flare = true, ember = true, trace_lit = true }

local function edges_default()
    return { hidden = {}, style = "circuit", width = 1, animation = true }
end

local function appearance_default()
    return { accent = "phos", brightness = 100, contrast = 100, opacity = 100, glow = 60, grid = true, motion = true }
end

local function arrangement(name, mode, banner, nodes)
    return {
        name = name,
        mode = mode,
        banner = banner,
        focus = "core",
        nodes = nodes,
        edges = edges_default(),
        appearance = appearance_default(),
    }
end

-- Three shipped arrangements. FULL honours the plate's visible modules when legacy
-- settings exist, so upgrading does not silently resurrect modules the user hid.
function M.seed_arrangements(legacy)
    legacy = type(legacy) == "table" and legacy or {}
    local full = M.default_nodes()

    if type(legacy.modules) == "table" then
        local keep = { core = true, system = true, clock = true }
        for _, id in ipairs(legacy.modules) do
            local mapped = LEGACY[id]
            if mapped then keep[mapped] = true end
        end
        for _, node in ipairs(full) do
            node.vis = keep[node.type] == true
        end
    end

    local focus_keep = { core = true, system = true, network = true, audio = true, storage = true, workspaces = true }
    local focus_nodes = {}
    for _, node in ipairs(M.default_nodes()) do
        if focus_keep[node.type] then focus_nodes[#focus_nodes + 1] = node end
    end

    local minimal_keep = { core = true, system = true, clock = true }
    local minimal_nodes = {}
    for _, node in ipairs(M.default_nodes()) do
        if minimal_keep[node.type] then minimal_nodes[#minimal_nodes + 1] = node end
    end

    return {
        arrangement("FULL", "circuit", "full", full),
        arrangement("FOCUS", "circuit", "compact", focus_nodes),
        arrangement("MINIMAL", "minimal", "strip", minimal_nodes),
    }
end

-- Read back what a hand-edited or older settings file contains. Invalid entries are
-- dropped; a valid file is returned unchanged in shape. The config validator is the
-- gate that rejects the whole list on write, so this only has to be safe, not strict.
function M.normalize_arrangements(list)
    local out, dropped, names = {}, 0, {}
    if type(list) ~= "table" then return out, dropped end
    for _, raw in ipairs(list) do
        if #out >= 8 then
            dropped = dropped + 1
        elseif type(raw) ~= "table"
            or type(raw.name) ~= "string" or raw.name == "" or #raw.name > 16 or names[raw.name]
            or not MODES[raw.mode]
            or not BANNERS[raw.banner] then
            dropped = dropped + 1
        else
            names[raw.name] = true
            local nodes = M.normalize_nodes(raw.nodes)

            local focus = raw.focus
            local has_focus = false
            local has_core = false
            for _, node in ipairs(nodes) do
                if node.type == focus then has_focus = true end
                if node.type == "core" then has_core = true end
            end
            if not has_focus then
                focus = has_core and "core" or (nodes[1] and nodes[1].type or "core")
            end

            local edges = type(raw.edges) == "table" and raw.edges or {}
            local look = type(raw.appearance) == "table" and raw.appearance or {}
            local hidden = {}
            if type(edges.hidden) == "table" then
                for _, id in ipairs(edges.hidden) do
                    if type(id) == "string" and #hidden < 24 then hidden[#hidden + 1] = id end
                end
            end

            out[#out + 1] = {
                name = raw.name,
                mode = raw.mode,
                banner = raw.banner,
                focus = focus,
                nodes = nodes,
                edges = {
                    hidden = hidden,
                    style = STYLES[edges.style] and edges.style or "circuit",
                    width = edges.width == 2 and 2 or 1,
                    animation = edges.animation ~= false,
                },
                appearance = {
                    accent = ACCENTS[look.accent] and look.accent or "phos",
                    brightness = clamp(number(look.brightness, 100), 60, 140),
                    contrast = clamp(number(look.contrast, 100), 60, 140),
                    opacity = clamp(number(look.opacity, 100), 40, 100),
                    glow = clamp(number(look.glow, 60), 0, 100),
                    grid = look.grid ~= false,
                    motion = look.motion ~= false,
                },
            }
        end
    end
    return out, dropped
end

-- What the canvas may draw right now. Visibility is a separate decision the renderer
-- makes, so a hidden node still belongs to the arrangement and can be restored.
function M.visible_nodes(arrangement, present)
    local out = {}
    if type(arrangement) ~= "table" or type(arrangement.nodes) ~= "table" then return out end
    for _, node in ipairs(arrangement.nodes) do
        if M.available(node.type, present) then out[#out + 1] = node end
    end
    return out
end

return M
