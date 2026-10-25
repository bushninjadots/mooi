-- Control Nexus spatial graph. Pure data operations only: callers decide how to render
-- nodes and when to persist a graph. Stable IDs are the link contract across views.
local node = require("lib/nexusnode")
local M = {}

local function copy_node(value)
    local result = {}
    for k, v in pairs(value) do
        if type(v) == "table" then
            local nested = {}
            for nk, nv in pairs(v) do nested[nk] = nv end
            result[k] = nested
        else
            result[k] = v
        end
    end
    return result
end

local function edge_key(from_id, to_id, relation)
    return from_id .. "\0" .. to_id .. "\0" .. relation
end

function M.new()
    return { nodes = {}, edges = {}, revision = 0 }
end

function M.add_node(graph, spec)
    if type(graph) ~= "table" or type(graph.nodes) ~= "table" or type(graph.edges) ~= "table" then
        return false, "invalid graph"
    end
    local normalized, why = node.create(spec)
    if not normalized then return false, why end
    if graph.nodes[normalized.id] then return false, "duplicate node id: " .. normalized.id end
    graph.nodes[normalized.id] = normalized
    graph.revision = (graph.revision or 0) + 1
    return true, normalized
end

function M.get_node(graph, id)
    local value = type(graph) == "table" and type(graph.nodes) == "table" and graph.nodes[id] or nil
    return value and copy_node(value) or nil
end

function M.move_node(graph, id, x, y)
    local current = type(graph) == "table" and graph.nodes and graph.nodes[id] or nil
    if not current then return false, "unknown node: " .. tostring(id) end
    local moved, why = node.move(current, x, y)
    if not moved then return false, why end
    graph.nodes[id] = moved
    graph.revision = (graph.revision or 0) + 1
    return true, copy_node(moved)
end

function M.remove_node(graph, id)
    if type(graph) ~= "table" or not graph.nodes or not graph.nodes[id] then
        return false, "unknown node: " .. tostring(id)
    end
    graph.nodes[id] = nil
    local kept = {}
    for _, edge in ipairs(graph.edges or {}) do
        if edge.from ~= id and edge.to ~= id then kept[#kept + 1] = edge end
    end
    graph.edges = kept
    graph.revision = (graph.revision or 0) + 1
    return true
end

function M.connect(graph, from_id, to_id, relation)
    relation = relation or "related"
    if type(relation) ~= "string" or relation == "" then return false, "relation must be a non-empty string" end
    if not graph.nodes[from_id] then return false, "unknown source node: " .. tostring(from_id) end
    if not graph.nodes[to_id] then return false, "unknown target node: " .. tostring(to_id) end
    local key = edge_key(from_id, to_id, relation)
    for _, edge in ipairs(graph.edges) do
        if edge_key(edge.from, edge.to, edge.relation) == key then return true, false end
    end
    graph.edges[#graph.edges + 1] = { from = from_id, to = to_id, relation = relation }
    graph.revision = (graph.revision or 0) + 1
    return true, true
end

function M.disconnect(graph, from_id, to_id, relation)
    local kept, removed = {}, false
    for _, edge in ipairs(graph.edges or {}) do
        local matches = edge.from == from_id and edge.to == to_id and (relation == nil or edge.relation == relation)
        if matches then removed = true else kept[#kept + 1] = edge end
    end
    if removed then graph.edges = kept; graph.revision = (graph.revision or 0) + 1 end
    return removed
end

function M.list_nodes(graph)
    local result = {}
    for _, value in pairs(graph.nodes or {}) do result[#result + 1] = copy_node(value) end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function M.neighbors(graph, id)
    local seen, result = {}, {}
    for _, edge in ipairs(graph.edges or {}) do
        local other
        if edge.from == id then other = edge.to elseif edge.to == id then other = edge.from end
        if other and not seen[other] and graph.nodes[other] then
            seen[other] = true
            result[#result + 1] = copy_node(graph.nodes[other])
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

-- Place a stable, ID-sorted collection on a normalized grid. The graph model owns positions;
-- the renderer converts them into pixels for its current viewport.
function M.layout_grid(graph, ids, columns, padding)
    columns = math.max(1, math.floor(tonumber(columns) or 3))
    padding = math.max(0, math.min(0.4, tonumber(padding) or 0.12))
    local ordered = {}
    if type(ids) == "table" then
        for _, id in ipairs(ids) do if graph.nodes[id] then ordered[#ordered + 1] = id end end
    else
        for id in pairs(graph.nodes or {}) do ordered[#ordered + 1] = id end
        table.sort(ordered)
    end
    local rows = math.max(1, math.ceil(#ordered / columns))
    local span = 1 - padding * 2
    for index, id in ipairs(ordered) do
        local col = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local x = columns == 1 and 0.5 or padding + span * (col / (columns - 1))
        local y = rows == 1 and 0.5 or padding + span * (row / (rows - 1))
        graph.nodes[id].x, graph.nodes[id].y = x, y
    end
    if #ordered > 0 then graph.revision = (graph.revision or 0) + 1 end
    return #ordered
end

function M.validate(graph)
    if type(graph) ~= "table" or type(graph.nodes) ~= "table" or type(graph.edges) ~= "table" then
        return false, "graph must contain nodes and edges"
    end
    for id, value in pairs(graph.nodes) do
        if id ~= value.id then return false, "node key does not match id: " .. tostring(id) end
        local ok, why = node.validate(value)
        if not ok then return false, why end
    end
    local seen = {}
    for _, edge in ipairs(graph.edges) do
        if type(edge) ~= "table" or not graph.nodes[edge.from] or not graph.nodes[edge.to] then
            return false, "edge points to a missing node"
        end
        local key = edge_key(edge.from, edge.to, edge.relation)
        if seen[key] then return false, "duplicate edge" end
        seen[key] = true
    end
    return true
end

return M
