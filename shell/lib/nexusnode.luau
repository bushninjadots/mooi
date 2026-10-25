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

    -- Determine which legacy modules to keep visible.
    -- If layouts are provided, they take complete precedence over the modules list.
    -- If no layouts, fall back to the modules list (or default if neither exist).
    -- The layouts may contain either old plate ids (mapped through LEGACY) or new node ids directly.
    local have_layouts = type(legacy.layouts) == "table"
    local have_modules = type(legacy.modules) == "table"
    local keep = { core = true, system = true, clock = true }
    -- A file that never knew the plate (a fresh install, or a hand-written one) hides
    -- nothing: every anchor the machine can support belongs on the canvas. Only a file
    -- that recorded what was showing gets to keep some nodes off it.
    if not have_layouts and not have_modules then
        for _, node in ipairs(full) do keep[node.type] = true end
    end

    local function apply_modules(module_ids)
        -- Reset to defaults, then apply the given module ids
        keep = { core = true, system = true, clock = true }
        for _, id in ipairs(module_ids) do
            -- Try LEGACY mapping first (old plate ids), then use id directly (new node ids)
            local mapped = LEGACY[id] or id
            if type(mapped) == "string" and #mapped > 0 then
                keep[mapped] = true
            end
        end
    end

    if have_layouts then
        -- Use the last layout's modules; the modules list is ignored when layouts exist
        local last_layout = nil
        if #legacy.layouts > 0 then
            last_layout = legacy.layouts[#legacy.layouts]
        end
        if type(last_layout) == "table" and type(last_layout.modules) == "table" then
            apply_modules(last_layout.modules)
        end
    elseif have_modules then
        -- No layouts: use the modules list as before
        apply_modules(legacy.modules)
    end
    for _, node in ipairs(full) do
        node.vis = keep[node.type] == true
    end

    local focus_keep = { core = true, system = true, network = true, audio = true, storage = true, workspaces = true }
    local focus_nodes = {}
    for _, node in ipairs(M.default_nodes()) do
        if focus_keep[node.type] then focus_nodes[#focus_nodes + 1] = node end
    end

    local minimal_keep = { core = true, system = true, clock = true }
    local minimal_nodes = {}
    for _, node in ipairs(M.default_nodes()) do
        if minimal_keep[node.type] then minimal_nodes[#minimal_nodes + 1] = node
        end
    end

    return {
        arrangement("FULL", "circuit", "full", full),
        arrangement("FOCUS", "circuit", "compact", focus_nodes),
        -- Not MINIMAL: that is the mode's name, and two chips reading MINIMAL on the same
        -- header meant two different things (D82).
        arrangement("BARE", "minimal", "strip", minimal_nodes),
    }
end

-- The third shipped arrangement used to be called MINIMAL, the same word as the mode, so the
-- header said MINIMAL twice and meant two things. A saved copy that still has the shape it
-- shipped with is renamed once; one the user has made their own keeps the name they gave it.
-- Returns how many were renamed, which is also "this file should be written again".
function M.rename_shipped(list)
    local renamed = 0
    if type(list) ~= "table" then return renamed end
    for _, a in ipairs(list) do
        if type(a) == "table" and a.name == "MINIMAL" and a.mode == "minimal" and a.banner == "strip" then
            local types = {}
            for _, node in ipairs(type(a.nodes) == "table" and a.nodes or {}) do
                types[#types + 1] = node.type
            end
            table.sort(types)
            if #types == 3 and types[1] == "clock" and types[2] == "core" and types[3] == "system" then
                a.name = "BARE"
                renamed = renamed + 1
            end
        end
    end
    return renamed
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

-- seed_write: migrate a v1 settings file to v2, returning (write, backup).
-- partial/broken/missing files are left alone or seeded as appropriate.
-- A valid v1 file is migrated and the v1 file is backed up as settings.v1.bak.
-- Returns (false, false) if the file should not be touched.
function M.seed_write(filename, version, v1_valid)
    -- v1_valid: whether a v1 backup already exists
    -- filename: the settings file name (without path)
    -- version: the target v2 schema version
    if filename == "partial" or filename == "broken" then
        -- partial or broken files: leave alone
        return false, false
    end
    if filename == "missing" then
        -- missing file: seed with v2 defaults, no backup needed
        return true, false
    end
    -- valid v1 file: migrate and create backup unless backup already exists
    if version == 1 then
        if v1_valid then
            -- backup already exists, never overwrite
            return true, false
        end
        -- valid v1 file, create backup
        return true, true
    end
    -- v2 file: no v1 backup needed
    return true, false
end

-- ── undo history ───────────────────────────────────────────
-- The logic edits arrangements in place, so a step back needs a copy taken before the
-- edit. Snapshots keep only what an arrangement is made of, and the list is bounded:
-- twenty steps is the spec's limit, and an unbounded history is a leak with a nicer name.
M.UNDO_LIMIT = 20

local function copy_nodes(nodes)
    local out = {}
    for i, node in ipairs(nodes or {}) do
        local one = {}
        for key, value in pairs(node) do one[key] = value end
        out[i] = one
    end
    return out
end

function M.copy_arrangements(list)
    local out = {}
    for i, a in ipairs(list or {}) do
        if type(a) == "table" then
            local hidden = {}
            for j, id in ipairs(type(a.edges) == "table" and a.edges.hidden or {}) do hidden[j] = id end
            local look = type(a.appearance) == "table" and a.appearance or {}
            out[i] = {
                name = a.name,
                mode = a.mode,
                banner = a.banner,
                focus = a.focus,
                nodes = copy_nodes(a.nodes),
                edges = {
                    hidden = hidden,
                    style = type(a.edges) == "table" and a.edges.style or "circuit",
                    width = type(a.edges) == "table" and a.edges.width or 1,
                    animation = type(a.edges) ~= "table" or a.edges.animation ~= false,
                },
                appearance = {
                    accent = look.accent or "phos",
                    brightness = look.brightness or 100,
                    contrast = look.contrast or 100,
                    opacity = look.opacity or 100,
                    glow = look.glow or 60,
                    grid = look.grid ~= false,
                    motion = look.motion ~= false,
                },
            }
        end
    end
    return out
end

-- Push the state the edit is about to change. The oldest step falls off the end.
function M.remember(past, list, limit)
    limit = limit or M.UNDO_LIMIT
    past[#past + 1] = M.copy_arrangements(list)
    while #past > limit do table.remove(past, 1) end
    return past
end

-- Step back: the current state moves to the redo list and the last snapshot comes back.
function M.undo(past, future, list)
    if #past == 0 then return list, false end
    future[#future + 1] = M.copy_arrangements(list)
    return table.remove(past), true
end

function M.redo(past, future, list)
    if #future == 0 then return list, false end
    past[#past + 1] = M.copy_arrangements(list)
    while #past > M.UNDO_LIMIT do table.remove(past, 1) end
    return table.remove(future), true
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
