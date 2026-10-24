-- The Control Nexus connection graph.
--
-- Relationships are authored here, not discovered: every edge states what
-- it means, so a drawn line never implies an integration that does not
-- exist. Rendering and interaction live in the scene.

local M = {}

-- Draw order is trunk first: the core bus sits under the satellite
-- signals so a busy node never hides the spine of the network.
M.EDGES = {
    { id = "core-system", from = "core", to = "system", kind = "trunk", label = "SYSTEM", meaning = "core bus" },
    { id = "core-network", from = "core", to = "network", kind = "trunk", label = "LINK", meaning = "core bus" },
    { id = "core-audio", from = "core", to = "audio", kind = "trunk", label = "AUDIO", meaning = "core bus" },
    { id = "core-workspaces", from = "core", to = "workspaces", kind = "trunk", label = "SPACES", meaning = "core bus" },
    { id = "core-storage", from = "core", to = "storage", kind = "trunk", label = "STORE", meaning = "core bus" },

    { id = "cpu-system", from = "cpu", to = "system", kind = "signal", label = "LOAD", meaning = "processor load", activity = "cpu" },
    { id = "memory-system", from = "memory", to = "system", kind = "signal", label = "MEM", meaning = "memory pressure", activity = "memory" },
    { id = "gpu-system", from = "gpu", to = "system", kind = "signal", label = "GPU", meaning = "graphics load", activity = "gpu" },
    { id = "thermal-system", from = "thermal", to = "system", kind = "signal", label = "TEMP", meaning = "thermals", activity = "thermal" },
    { id = "power-system", from = "power", to = "system", kind = "signal", label = "PWR", meaning = "power draw", activity = "power" },
    { id = "storage-system", from = "storage", to = "system", kind = "signal", label = "DISK", meaning = "capacity", activity = "storage" },
    { id = "storage-files", from = "storage", to = "files", kind = "signal", label = "FILES", meaning = "storage appears in Files" },
    { id = "network-system", from = "network", to = "system", kind = "signal", label = "NET", meaning = "throughput", activity = "network" },
    { id = "audio-media", from = "audio", to = "media", kind = "signal", label = "MEDIA", meaning = "playback", activity = "media" },
    { id = "workspaces-applications", from = "workspaces", to = "applications", kind = "signal", label = "APPS", meaning = "windows in spaces" },
}

-- `types` is a set of node ids the caller has decided are drawable. Both
-- ends must exist; availability is the caller's judgement, not ours.
function M.instantiate(types)
    local edges = {}
    for _, edge in ipairs(M.EDGES) do
        if types[edge.from] and types[edge.to] then
            edges[#edges + 1] = edge
        end
    end
    return edges
end

function M.count(edges)
    return #edges
end

return M
