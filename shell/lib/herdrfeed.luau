-- Herdr's two JSON commands, turned into what the bar and the island draw (D210). Pure: the bar runs
-- the CLI, this parses, groups and sanitises. Herdr has no timestamps or branch in its snapshot, so
-- elapsed comes from the bar's `seen` map and branch from a cached `git` lookup passed in `meta`.

local M = {}

local function unwrap(doc)
    if type(doc) ~= "table" then return nil end
    if type(doc.result) == "table" and type(doc.result.snapshot) == "table" then return doc.result.snapshot end
    if type(doc.snapshot) == "table" then return doc.snapshot end
    return doc
end

function M.status(doc)
    doc = type(doc) == "table" and doc or {}
    local server = type(doc.server) == "table" and doc.server or {}
    local update = type(doc.update) == "table" and doc.update or {}
    local running = server.running == true or server.status == "running"
    local compatible = server.compatible ~= false and server.endpoint_compatible ~= false
    local restart = server.restart_needed == true or update.restart_needed == true
    local stale = server.server_binary_stale == true or update.server_binary_stale == true
    local problems = {}
    if not running then problems[#problems + 1] = "server down" end
    if not compatible then problems[#problems + 1] = "incompatible protocol" end
    if restart then problems[#problems + 1] = "restart needed" end
    if stale then problems[#problems + 1] = "server binary is stale" end
    return {
        running = running,
        compatible = compatible,
        version = type(server.version) == "string" and server.version or nil,
        socket = type(server.socket) == "string" and server.socket or nil,
        restart_needed = restart,
        problems = problems,
    }
end

local function text(v)
    return type(v) == "string" and v or ""
end

local function count(v)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    return math.max(0, math.floor(v))
end

function M.snapshot(doc)
    local snap = unwrap(doc)
    if type(snap) ~= "table" then return { agents = {}, error = "no snapshot" } end
    local agents = {}
    for _, a in ipairs(type(snap.agents) == "table" and snap.agents or {}) do
        if type(a) == "table" and text(a.pane_id) ~= "" then
            local status = text(a.agent_status)
            if status == "" then status = "unknown" end
            agents[#agents + 1] = {
                pane_id = text(a.pane_id),
                agent = text(a.agent),
                agent_status = status,
                terminal_title = text(a.terminal_title_stripped) ~= "" and text(a.terminal_title_stripped)
                    or text(a.terminal_title),
                cwd = text(a.cwd),
                foreground_cwd = text(a.foreground_cwd),
                workspace_id = text(a.workspace_id),
                tab_id = text(a.tab_id),
                state_change_seq = count(a.state_change_seq),
                completion_seq = count(a.completion_seq),
                focused = a.focused == true,
                tokens = count(a.tokens),
            }
        end
    end
    return {
        agents = agents,
        focused = text(snap.focused_pane_id),
        workspaces = type(snap.workspaces) == "table" and snap.workspaces or {},
        tabs = type(snap.tabs) == "table" and snap.tabs or {},
    }
end

local function key(a) return a.pane_id .. ":" .. a.agent_status end

-- groups: { attention, working, idle, done }; each row gains elapsed (seconds|nil) and branch.
-- `seen` is the bar's first-observation map, `meta[pane_id] = { branch = "…" }`.
function M.group(agents, now, seen, meta, opts)
    now = tonumber(now) or 0
    seen = type(seen) == "table" and seen or {}
    meta = type(meta) == "table" and meta or {}
    opts = type(opts) == "table" and opts or {}
    local out = { attention = {}, working = {}, idle = {}, done = {} }
    for _, a in ipairs(type(agents) == "table" and agents or {}) do
        local row = {}
        for k, v in pairs(a) do row[k] = v end
        local t = seen[key(a)]
        row.elapsed = type(t) == "number" and math.max(0, now - t) or nil
        row.since_known = type(t) == "number" and true or false
        row.branch = type(meta[a.pane_id]) == "table" and meta[a.pane_id].branch or nil
        if a.agent_status == "blocked" then out.attention[#out.attention + 1] = row
        elseif a.agent_status == "working" then out.working[#out.working + 1] = row
        elseif a.agent_status == "done" then out.done[#out.done + 1] = row
        else out.idle[#out.idle + 1] = row end
    end
    local function oldest(a, b)
        return (a.elapsed or math.huge) > (b.elapsed or math.huge)
    end
    table.sort(out.attention, oldest)
    table.sort(out.working, oldest)
    table.sort(out.idle, function(a, b) return a.pane_id < b.pane_id end)
    table.sort(out.done, oldest)
    if opts.show_idle == false then out.idle = {} end
    if opts.show_done ~= true then out.done = {} end
    return out
end

local function strip_ansi(s)
    s = tostring(s or "")
    s = s:gsub("\27%[[%d;?]*[%a]", "")
    s = s:gsub("\27%][^\7]*\7", "")
    return s
end

local function redact(s)
    s = s:gsub("sk%-[%w_%-]+", "[redacted]")
    s = s:gsub("ghp_%w+", "[redacted]")
    s = s:gsub("xox[abp]%-[%w_%-]+", "[redacted]")
    s = s:gsub("AKIA%w+", "[redacted]")
    return s
end

function M.brief(title, body, cols)
    cols = math.max(20, math.floor(tonumber(cols) or 120))
    local line = ""
    for raw in tostring(body or ""):gmatch("[^\n]+") do
        local clean = redact(strip_ansi(raw)):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if clean ~= "" then line = clean end
    end
    if line == "" then
        line = redact(strip_ansi(title or "")):gsub("%s+", " ")
    end
    if line == "" then return "" end
    if #line > cols then
        line = line:sub(1, cols - 3):gsub("%s+$", "") .. "..."
    end
    return line
end

function M.warn(status, snapshot)
    if type(status) ~= "table" or not status.running then return "Herdr is not running" end
    if not status.compatible then return "Herdr protocol is incompatible" end
    if status.restart_needed then return "Herdr needs a restart" end
    if type(snapshot) == "table" and snapshot.error then return "Herdr snapshot unavailable" end
    return nil
end

return M
