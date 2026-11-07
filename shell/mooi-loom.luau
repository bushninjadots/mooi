-- Loom / Fold's program, the logic (D194, spec §3.2). Phase 1: the foundation.
--
--   · The model (lib/loom) is read from loom.json and cleaned; whatever was invalid is kept aside in
--     loom.json.rejected, never silently lost. A backup is kept on every start and every stop
--     (loom.json.bak.1 … .5, the newest first).
--   · An operation the journal shows as pending (the program died in the middle of it) is resolved to
--     the side where windows are visible: a fold rolled back, an unfold completed (lib/loom.recovery_for).
--   · The windows Hyprland reports are matched into the model whenever the workspaces change (debounced),
--     so an object keeps its identity across restarts (lib/loom.match).
--   · Asked to stop (`loom_quit`, the keeper), every parked window is brought back, the model saved, and
--     the program ends. Its health goes to its output for the keeper: `loom-ready`, then
--     `loom-health structures=… objects=… parked=…`.

local loom = require("lib/loom")
local park = require("lib/loompark")

local FILE = "loom.json"
local BACKUPS = 5

local function read(name)
    local ok, v = pcall(sys.ask, "files.read", name, "json")
    return ok and v or nil
end

-- ── The model ─────────────────────────────────────────────
local raw = read(FILE)
local doc, problems = loom.clean(raw)
if #problems > 0 then
    for _, p in ipairs(problems) do log("loom · " .. p) end
    if type(raw) == "table" then pcall(sys.call, "files.write", FILE .. ".rejected", raw) end
end

local function backup()
    -- shift .4 → .5 … .1 → .2, then the current document becomes .1
    for i = BACKUPS - 1, 1, -1 do
        local older = read(FILE .. ".bak." .. i)
        if type(older) == "table" then pcall(sys.call, "files.write", FILE .. ".bak." .. (i + 1), older) end
    end
    pcall(sys.call, "files.write", FILE .. ".bak.1", doc)
end

local dirty, save_at = false, 0
local function save_now()
    -- what is on disk is what the owner organised: windows registered only because they are open are
    -- pruned from the copy written, not from the live model
    local copy = loom.clean(doc)
    loom.prune(copy)
    pcall(sys.call, "files.write", FILE, copy)
    dirty = false
end
local function save_soon()
    dirty = true
    local mine = save_at + 1
    save_at = mine
    after(1000, function() if mine == save_at and dirty then save_now() end end)
end

local function counts()
    local s, o = 0, 0
    for _ in pairs(doc.structures) do s = s + 1 end
    for _ in pairs(doc.objects) do o = o + 1 end
    return s, o, #loom.parked(doc)
end
local last_health = ""
local function health()
    local s, o, p = counts()
    local line = string.format("loom-health structures=%d objects=%d parked=%d", s, o, p)
    if line ~= last_health then last_health = line; log(line) end
end

-- ── Hyprland ──────────────────────────────────────────────
-- Run these commands one after another, then `done` (every command answers, so the next one starts
-- only after Hyprland has had the last one).
local function dispatch_all(cmds, done)
    local i = 0
    local function next_one()
        i = i + 1
        if i > #cmds then if done then done() end; return end
        run("hyprctl", { "dispatch", cmds[i] }, function() next_one() end)
    end
    next_one()
end

-- The windows as Hyprland has them, into the model.
local refreshing, again = false, false
local function refresh(done)
    if refreshing then again = true; return end
    refreshing = true
    run("hyprctl", { "-j", "clients" }, function(out)
        refreshing = false
        local ok, clients = pcall(json.decode, tostring(out or ""))
        if ok and type(clients) == "table" then
            local r = loom.match(doc, clients)
            -- every open window is an object while it is open (Hybrid and full mode act on any of them)
            for _, c in ipairs(r.loose) do
                local ws = type(c.workspace) == "table" and c.workspace or {}
                loom.add_object(doc, { kind = "window", app = c.class, title = c.title, address = c.address, pid = c.pid,
                                       workspace = ws.id, floating = c.floating,
                                       at = (type(c.at) == "table" and type(c.size) == "table") and { c.at[1], c.at[2], c.size[1], c.size[2] } or nil })
            end
            -- a window that closed and belongs to nothing is forgotten from the live model too
            for oid, o in pairs(doc.objects) do
                if o.state == "absent" and not o.parent and #loom.related(doc, oid) == 0 then doc.objects[oid] = nil end
            end
            save_soon()
            health()
        end
        if done then done() end
        if again then again = false; refresh() end
    end)
end
local refresh_at = 0
local function refresh_soon()
    local mine = refresh_at + 1
    refresh_at = mine
    after(250, function() if mine == refresh_at then refresh() end end)
end

-- Every parked window back where it came from (the model updated as each is done).
local function unpark_all(done)
    local steps = park.unpark_all(doc)
    local cmds = {}
    for _, st in ipairs(steps) do for _, c in ipairs(st.cmds) do cmds[#cmds + 1] = c end end
    dispatch_all(cmds, function()
        for _, st in ipairs(steps) do park.apply(doc, st) end
        save_now(); health()
        -- and any window Hyprland still shows on a Loom park that the model does not know (a document
        -- lost or behind): to the workspace the owner is on
        run("hyprctl", { "-j", "activeworkspace" }, function(aw)
            local okw, w = pcall(json.decode, tostring(aw or ""))
            local ws = okw and type(w) == "table" and tonumber(w.id) or 1
            run("hyprctl", { "-j", "clients" }, function(out)
                local ok, clients = pcall(json.decode, tostring(out or ""))
                dispatch_all(park.rescue(park.stray(ok and clients or {}), ws), function()
                    if done then done() end
                end)
            end)
        end)
    end)
end

-- ── Interrupted operations (spec §5.4) ────────────────────
local function recover(done)
    local pending = loom.pending(doc)
    if #pending == 0 then if done then done() end; return end
    -- Phase 1 has no folding of its own yet; whatever was pending is resolved by bringing its windows
    -- out, which is right for both answers (a rolled-back fold and a completed unfold leave them visible)
    for _, e in ipairs(pending) do
        log("loom · " .. e.op .. " " .. e.target .. " was interrupted: " .. loom.recovery_for(e))
    end
    unpark_all(function()
        for _, e in ipairs(pending) do
            loom.journal_end(doc, e.id, loom.recovery_for(e) == "complete" and "done" or "undone")
        end
        save_now()
        if done then done() end
    end)
end

-- ── Start ─────────────────────────────────────────────────
backup()
refresh(function()
    recover(function()
        log("loom-ready")
        health()
    end)
end)
pcall(sys.watch, "workspaces", function() refresh_soon() end)

-- ── Asked by the keeper and `mooi loom …` ─────────────────
local quitting = false
on("loom_quit", function()
    if quitting then return end
    quitting = true
    unpark_all(function()
        backup()
        run("pleamar", { "--say", "mooi-loom", "quit" })
    end)
end)
on("loom_cmd", function(v)
    local n = math.floor(tonumber(v) or 0)
    if n == 1 then unpark_all() end
end)
