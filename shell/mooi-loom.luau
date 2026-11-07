-- Loom / Fold's program, the logic (D194 Phase 1, D195 Phase 2; spec §3.2, §4.1).
--
--   · The model (lib/loom) is read from loom.json and cleaned; whatever was invalid is kept aside in
--     loom.json.rejected, never silently lost. A backup is kept on every start and every stop
--     (loom.json.bak.1 … .5, the newest first).
--   · An operation the journal shows as pending (the program died in the middle of it) is resolved to
--     the side where windows are visible (lib/loom.recovery_for).
--   · The windows Hyprland reports are matched into the model whenever the workspaces change (debounced),
--     so an object keeps its identity across restarts (lib/loom.match).
--   · D195: Accordions (lib/loomaccordion) while lib/loommode says they are on: commands from the keys
--     (`mooi loom add|next|prev|fold|open|remove`) and the strip (shell/ui/loomstrip.plm) become plans,
--     run in order through Hyprland, journaled, then written into the model. A layer whose window closes
--     while this runs leaves its accordion; at start an absent one is kept (that is a restart). Turned
--     off, every accordion's windows come out.
--   · Asked to stop (`loom_quit`, the keeper), every parked window is brought back, the model saved, and
--     the program ends. Its health goes to its output for the keeper: `loom-ready`, then
--     `loom-health structures=… objects=… parked=…`.

local loom = require("lib/loom")
local park = require("lib/loompark")
local acc = require("lib/loomaccordion")
local cube = require("lib/loomcube")          -- D197
local links = require("lib/loomlinks")        -- D200
local hypr = require("lib/hypr")
local lm = require("lib/loommode")
local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")

local FILE = "loom.json"
local BACKUPS = 5

-- a JSON document, or (kind "raw") the file's text as it is
local function read(name, kind)
    local ok, v
    if kind == "raw" then ok, v = pcall(sys.ask, "files.read", name)
    else ok, v = pcall(sys.ask, "files.read", name, "json") end
    return ok and v or nil
end

-- ── Settings, features, the palette ───────────────────────
local settings = config.parse(read("settings.json", "raw"), json.decode)
local features = lm.effective("native", {}, nil)
local function read_settings()
    settings = config.parse(read("settings.json", "raw"), json.decode)
    local l = type(settings.loom) == "table" and settings.loom or {}
    features = lm.effective(l.mode, l, nil)
    fact.lf_edge = l.edge == "left" and 1 or 0
    fact.lf_side = l.edge == "left" and "left" or "right"
end
local palette = read("palette.json")
local function paint()
    fact.cn_kind, fact.cn_scale = style.corners(settings)
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
end
read_settings()
pcall(paint)

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

-- What the strip draws (D195): the accordions and their layers, only while the feature is on.
local function publish()
    local on = features.on.accordions == true
    local strips, layers = acc.rows(doc)
    if not on then strips, layers = {}, {} end
    model.lf_strips = strips
    model.lf_layers = layers
    fact.lf_n = #strips
    -- D197: the cubes, docked below the strips
    local cubes = features.on.cubes and cube.rows(doc) or {}
    model.lf_cubes = cubes
    fact.lf_cn = #cubes
    fact.lf_draw = #strips > 0 or #cubes > 0
end

-- D200: Loom's threads, for the workspace and monitor in front of the owner. `relevant` (the default)
-- shows them for a few seconds when the focused window has connections, and while a link is being made;
-- `always` while there are any; `hidden` only while a link is being made.
local thr = { ws = 1, ox = 0, oy = 0, w = 1920, h = 1080, focus = nil, pick = nil, until_ms = 0, seq = 0, last_hop = nil }
local function threads_mode()
    local l = type(settings.loom) == "table" and settings.loom or {}
    return l.threads == "always" and "always" or (l.threads == "hidden" and "hidden" or "relevant")
end
local function threads_publish()
    if not features.on.loom then model.lf_threads = {}; fact.lf_thr_on = false; return end
    local list = links.threads(doc, thr.ws, thr.w, thr.h, thr.ox, thr.oy, thr.focus)
    model.lf_threads = list
    local mode = threads_mode()
    local on = thr.pick ~= nil
    if mode == "always" then on = on or #list > 0
    elseif mode == "relevant" then
        local lit = false
        for _, t in ipairs(list) do if t.lit then lit = true end end
        on = on or (lit and thr.flash == true)
    end
    fact.lf_thr_on = on
    fact.lf_pick = thr.pick ~= nil
end
-- after a change of focus or a new link: the threads light for 4 s, then fade
local function threads_flash()
    thr.seq = thr.seq + 1
    local mine = thr.seq
    thr.flash = true
    threads_publish()
    after(4000, function() if mine == thr.seq then thr.flash = false; threads_publish() end end)
end
-- where the owner is: the focused window, its workspace and its monitor
local function threads_look(flash)
    run("hyprctl", { "-j", "monitors" }, function(mo)
        local okm, mons = pcall(json.decode, tostring(mo or ""))
        if okm and type(mons) == "table" then
            for _, m in ipairs(mons) do
                if m.focused then
                    local sc = tonumber(m.scale) or 1
                    thr.ox, thr.oy = tonumber(m.x) or 0, tonumber(m.y) or 0
                    thr.w, thr.h = math.floor((tonumber(m.width) or 1920) / sc), math.floor((tonumber(m.height) or 1080) / sc)
                    thr.ws = type(m.activeWorkspace) == "table" and tonumber(m.activeWorkspace.id) or thr.ws
                end
            end
        end
        run("hyprctl", { "-j", "activewindow" }, function(aw)
            local ok, a = pcall(json.decode, tostring(aw or ""))
            local addr = ok and type(a) == "table" and a.address or nil
            local _, oid = acc.of_window(doc, addr or "")
            local changed = oid ~= thr.focus
            thr.focus = oid
            if flash or changed then threads_flash() else threads_publish() end
        end)
    end)
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
local refreshing, again, first = false, false, true
local function refresh(done)
    if refreshing then again = true; return end
    refreshing = true
    run("hyprctl", { "-j", "clients" }, function(out)
        refreshing = false
        local ok, clients = pcall(json.decode, tostring(out or ""))
        if ok and type(clients) == "table" then
            local before = {}
            for oid, o in pairs(doc.objects) do before[oid] = o.state end
            local r = loom.match(doc, clients)
            -- every open window is an object while it is open (Hybrid and full mode act on any of them)
            for _, c in ipairs(r.loose) do
                local ws = type(c.workspace) == "table" and c.workspace or {}
                loom.add_object(doc, { kind = "window", app = c.class, title = c.title, address = c.address, pid = c.pid,
                                       workspace = ws.id, floating = c.floating,
                                       at = (type(c.at) == "table" and type(c.size) == "table") and { c.at[1], c.at[2], c.size[1], c.size[2] } or nil })
            end
            for oid, o in pairs(doc.objects) do
                if o.state == "absent" then
                    -- D195: closed while this runs (it was there a moment ago) → it leaves its accordion;
                    -- at start, absent means a restart, and it is kept to be matched later
                    local s = o.parent and doc.structures[o.parent]
                    local closed = not first and before[oid] and before[oid] ~= "absent"
                    if (s and s.kind == "accordion" and closed) or (not o.parent and #loom.related(doc, oid) == 0) then
                        loom.remove_object(doc, oid)
                    end
                end
            end
            -- an accordion whose every window has closed is gone (an empty strip says nothing)
            for sid, st in pairs(doc.structures) do
                if st.kind == "accordion" and #st.members == 0 then loom.remove_structure(doc, sid) end
            end
            first = false
            save_soon()
            health()
            publish()
            threads_look(false)
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

-- Every parked window back where it came from (the model updated as each is done); `only` limits it to
-- these structures' windows.
local function unpark_all(done, only)
    local ids = {}
    for _, p in ipairs(loom.parked(doc)) do
        if not only or (p.structure and only[p.structure]) then ids[#ids + 1] = p.object end
    end
    local steps = park.unpark(doc, ids)
    local cmds = {}
    for _, st in ipairs(steps) do for _, c in ipairs(st.cmds) do cmds[#cmds + 1] = c end end
    dispatch_all(cmds, function()
        for _, st in ipairs(steps) do park.apply(doc, st) end
        for sid, s in pairs(doc.structures) do
            if not only or only[sid] then s.arrangement.open = {}; s.state = "" end
        end
        save_now(); health(); publish()
        if only then if done then done() end; return end
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

-- ── Running a plan (D195) ─────────────────────────────────
-- One at a time: a second command while a plan is moving windows waits for it.
local busy, queue = false, {}
local function run_plan(op, sid, make, commit)
    commit = commit or acc.commit             -- D197: a cube's plan commits through lib/loomcube
    if busy then queue[#queue + 1] = { op, sid, make, commit }; return end
    busy = true
    local function finish()
        busy = false
        publish()
        refresh_soon()
        local q = table.remove(queue, 1)
        if q then run_plan(q[1], q[2], q[3], q[4]) end
    end
    run("hyprctl", { "-j", "activeworkspace" }, function(aw)
        local okw, w = pcall(json.decode, tostring(aw or ""))
        local ws = okw and type(w) == "table" and tonumber(w.id) or 1
        if ws < 1 then ws = 1 end
        local p, target = make(ws)
        target = target or sid
        if not p or (#p.cmds == 0 and not p.open and not p.remove and not p.dissolve and not p.state and not p.faces) then finish(); return end
        local j = loom.journal_begin(doc, op, target or "", p.moves, os.time())
        save_now()
        dispatch_all(p.cmds, function()
            commit(doc, target, p, os.time())
            loom.journal_end(doc, j, "done")
            save_now(); health()
            finish()
        end)
    end)
end

-- The focused window: its address and the model's object for it (registered if it is new).
local function with_focused(fn)
    run("hyprctl", { "-j", "activewindow" }, function(out)
        local ok, c = pcall(json.decode, tostring(out or ""))
        if not ok or type(c) ~= "table" or type(c.address) ~= "string" or c.address == "" then return end
        local _, oid = acc.of_window(doc, c.address)
        if not oid then
            local ws = type(c.workspace) == "table" and c.workspace or {}
            oid = loom.add_object(doc, { kind = "window", app = c.class, title = c.title, address = c.address, pid = c.pid,
                                         workspace = ws.id, floating = c.floating, state = "live" })
        end
        if oid then fn(c.address, oid) end
    end)
end

local function accordions_on()
    if features.on.accordions then return true end
    log("loom · accordions are off: " .. tostring(features.off.accordions or ""))
    return false
end

-- ── Commands: the keys (`mooi loom …`) and the strip ──────
local CMD = { unpark = 1, add = 10, next = 11, prev = 12, fold = 13, open = 14, remove = 15, push = 16,
              cube = 20, join = 21,       -- D197
              link = 30, flow = 31, hop = 32, unlink = 33 }      -- D200
local function loom_on()
    if features.on.loom then return true end
    log("loom · connections are off: " .. tostring(features.off.loom or ""))
    return false
end
-- D200: a link is made in two presses — the first marks the focused window, the second (on another
-- window) ties them; pressed again on the same window it lets go
local function link_press(kind)
    with_focused(function(_, oid)
        if not thr.pick then thr.pick = oid; threads_publish(); return end
        if thr.pick == oid then thr.pick = nil; threads_publish(); return end
        local from = thr.pick
        thr.pick = nil
        if doc.objects[from] and links.link(doc, from, oid, kind) then
            save_now(); health()
            thr.focus = oid
            threads_flash()
        else threads_publish() end
    end)
end
-- D200: along a connection — the next connected window, brought out of its park if it waits in one, and
-- focused (Hyprland goes to its workspace)
local function hop()
    with_focused(function(_, oid)
        local t = links.next_target(doc, oid, thr.last_hop)
        thr.last_hop = t
        local o = t and doc.objects[t]
        if not o or o.state == "absent" or o.address == "" then return end
        local cmds = {}
        if o.state == "parked" then
            for _, st in ipairs(park.unpark(doc, { t })) do for _, c in ipairs(st.cmds) do cmds[#cmds + 1] = c end; park.apply(doc, st) end
        end
        local f = hypr.dispatch("focus", o.address)
        if f then cmds[#cmds + 1] = f end
        dispatch_all(cmds, function() save_soon(); refresh_soon() end)
    end)
end
local function cubes_on()
    if features.on.cubes then return true end
    log("loom · cubes are off: " .. tostring(features.off.cubes or ""))
    return false
end
-- D197: every window on the focused window's workspace, into the model, then made a cube
local function make_cube()
    run("hyprctl", { "-j", "activewindow" }, function(aw)
        local ok, a = pcall(json.decode, tostring(aw or ""))
        if not ok or type(a) ~= "table" or type(a.workspace) ~= "table" then return end
        local ws = tonumber(a.workspace.id)
        run("hyprctl", { "-j", "clients" }, function(out)
            local okc, clients = pcall(json.decode, tostring(out or ""))
            if not okc or type(clients) ~= "table" then return end
            loom.match(doc, clients)
            local oids, focus = {}, nil
            for _, c in ipairs(clients) do
                if type(c.workspace) == "table" and tonumber(c.workspace.id) == ws then
                    local _, oid = acc.of_window(doc, c.address)
                    if not oid then
                        oid = loom.add_object(doc, { kind = "window", app = c.class, title = c.title, address = c.address, pid = c.pid,
                                                     workspace = ws, floating = c.floating, state = "live",
                                                     at = (type(c.at) == "table" and type(c.size) == "table") and { c.at[1], c.at[2], c.size[1], c.size[2] } or nil })
                    end
                    if oid then
                        oids[#oids + 1] = oid
                        if c.address == a.address then focus = oid end
                    end
                end
            end
            if #oids == 0 then return end
            run_plan("cube", nil, function()
                local sid = cube.create(doc, oids, focus, "Workspace " .. tostring(ws))
                if not sid then return nil end
                return { cmds = {}, records = {}, moves = {}, state = "unfolded" }, sid
            end, cube.commit)
        end)
    end)
end
local command_acc      -- the Accordion's commands (below)
local function command(n)
    if n == CMD.unpark then unpark_all(); return end
    -- D200: Loom's keys
    if n == CMD.link or n == CMD.flow then if loom_on() then link_press(n == CMD.flow and "workflow" or "association") end; return end
    if n == CMD.hop then if loom_on() then hop() end; return end
    if n == CMD.unlink then
        if loom_on() then with_focused(function(_, oid) if links.unlink_all(doc, oid) > 0 then save_now(); threads_flash() end end) end
        return
    end
    -- D197: the Cube's keys, and fold for whichever structure the focused window is in
    if n == CMD.cube then if cubes_on() then make_cube() end; return end
    if n == CMD.join then
        if not cubes_on() then return end
        with_focused(function(address, oid)
            local sid = cube.last(doc)
            if sid and doc.objects[oid].parent ~= sid then run_plan("join", sid, function() return cube.add(doc, sid, oid) end, cube.commit) end
        end)
        return
    end
    if n == CMD.fold and features.on.cubes then
        with_focused(function(address)
            local sid = cube.of_window(doc, address)
            if sid then run_plan("fold", sid, function() return cube.fold(doc, sid) end, cube.commit); return end
            if acc.of_window(doc, address) then command_acc(n); return end
            local last = cube.last(doc, true)
            if last then run_plan("unfold", last, function() return cube.unfold(doc, last) end, cube.commit)
            else command_acc(n) end
        end)
        return
    end
    if n == CMD.remove and features.on.cubes then
        with_focused(function(address, oid)
            local sid = cube.of_window(doc, address)
            if sid then run_plan("remove", sid, function() return { cmds = {}, records = {}, moves = {}, remove = { oid } } end, cube.commit)
            else command_acc(n) end
        end)
        return
    end
    command_acc(n)
end
command_acc = function(n)
    if not accordions_on() then return end
    if n == CMD.add then
        with_focused(function(address, oid)
            local sid = acc.active(doc, address)
            if sid and doc.objects[oid].parent == sid then return end      -- already in it
            run_plan("add", sid, function(ws)
                local s = sid or acc.create(doc, "Accordion")
                if not s then return nil end
                return acc.add(doc, s, oid, ws), s
            end)
        end)
    elseif n == CMD.next or n == CMD.prev then
        with_focused(function(address)
            local sid = acc.active(doc, address)
            if sid then run_plan("pull", sid, function(ws) return acc.step(doc, sid, n == CMD.next and 1 or -1, ws) end) end
        end)
    elseif n == CMD.fold then
        -- fold if any layer is out, else bring back the one used last
        with_focused(function(address)
            local sid = acc.active(doc, address)
            if not sid then return end
            local s = doc.structures[sid]
            if #s.arrangement.open > 0 then run_plan("fold", sid, function() return acc.fold(doc, sid) end)
            else run_plan("pull", sid, function(ws) return acc.step(doc, sid, 1, ws) end) end
        end)
    elseif n == CMD.open then
        with_focused(function(address)
            local sid = acc.active(doc, address)
            if sid then run_plan("unfold", sid, function(ws) return acc.open_all(doc, sid, ws) end) end
        end)
    elseif n == CMD.remove then
        with_focused(function(address, oid)
            local sid = acc.of_window(doc, address)
            if sid then run_plan("remove", sid, function(ws) return acc.remove(doc, sid, oid, ws) end) end
        end)
    elseif n == CMD.push then
        with_focused(function(address, oid)
            local sid = acc.of_window(doc, address)
            if sid then run_plan("park", sid, function() return acc.push(doc, sid, oid) end) end
        end)
    end
end

-- ── Interrupted operations (spec §5.4) ────────────────────
local function recover(done)
    local pending = loom.pending(doc)
    if #pending == 0 then if done then done() end; return end
    -- whatever was pending is resolved by bringing its windows out, which is right for both answers (a
    -- rolled-back fold and a completed unfold leave them visible)
    local only = {}
    for _, e in ipairs(pending) do
        log("loom · " .. e.op .. " " .. e.target .. " was interrupted: " .. loom.recovery_for(e))
        if doc.structures[e.target] then only[e.target] = true end
    end
    unpark_all(function()
        for _, e in ipairs(pending) do
            loom.journal_end(doc, e.id, loom.recovery_for(e) == "complete" and "done" or "undone")
        end
        save_now()
        if done then done() end
    end, only)
end

-- ── Start ─────────────────────────────────────────────────
backup()
refresh(function()
    recover(function()
        log("loom-ready")
        health()
        publish()
    end)
end)
pcall(sys.watch, "workspaces", function() refresh_soon() end)
pcall(sys.watch, "window", function() threads_look(false) end)        -- D200: the focus moved
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json"); pcall(paint) end)
pcall(sys.watch, "files:settings.json", function()
    local was, was_c = features.on.accordions, features.on.cubes
    read_settings(); pcall(paint)
    -- turned off: every accordion's windows come out (nothing stays hidden behind a switch)
    local only, any = {}, false
    for sid, s in pairs(doc.structures) do
        if (was and not features.on.accordions and s.kind == "accordion") or (was_c and not features.on.cubes and s.kind == "cube") then
            only[sid] = true; any = true
        end
    end
    if any then unpark_all(nil, only) end
    publish()
end)

-- ── Asked by the keeper, `mooi loom …` and the strip ──────
local quitting = false
on("loom_quit", function()
    if quitting then return end
    quitting = true
    unpark_all(function()
        backup()
        run("pleamar", { "--say", "mooi-loom", "quit" })
    end)
end)
on("loom_cmd", function(v) command(math.floor(tonumber(v) or 0)) end)

-- D197: a docked cube (shell/ui/loomcube.plm), by its place c (from 0)
on("cube_press", function(v)           -- c: folded or partly → unfold all; unfolded → fold
    if not cubes_on() then return end
    local sid = cube.cube_sid(doc, v)
    if not sid then return end
    if doc.structures[sid].state == "unfolded" then run_plan("fold", sid, function() return cube.fold(doc, sid) end, cube.commit)
    else run_plan("unfold", sid, function() return cube.unfold(doc, sid) end, cube.commit) end
end)
on("cube_face", function(v)            -- c: only the facing face out (a partial unfold)
    if not cubes_on() then return end
    local sid = cube.cube_sid(doc, v)
    if sid then
        local _, face = cube.facing(doc, sid)
        run_plan("unfold", sid, function() return cube.unfold(doc, sid, face) end, cube.commit)
    end
end)
on("cube_turn", function(v)            -- c·10 + (1 next · 0 previous): turning moves no window
    if not cubes_on() then return end
    v = math.floor(tonumber(v) or -1)
    local sid = cube.cube_sid(doc, v // 10)
    if sid then cube.turn(doc, sid, v % 10 == 1 and 1 or -1); save_soon(); publish() end
end)
on("cube_dissolve", function(v)        -- c: the cube gone, every window out where it was
    if not cubes_on() then return end
    local sid = cube.cube_sid(doc, v)
    if sid then run_plan("dissolve", sid, function() return cube.dissolve(doc, sid) end, cube.commit) end
end)

-- The strip (shell/ui/loomstrip.plm): k is the strip's place, i a layer's (both from 0)
on("acc_press", function(v)            -- k * 100 + i: pull that layer (pressing the one out folds it back)
    if not accordions_on() then return end
    v = math.floor(tonumber(v) or -1)
    local sid, oid = acc.layer_oid(doc, v // 100, v % 100)
    if not sid or not oid then return end
    local s = doc.structures[sid]
    local out = false
    for _, id in ipairs(s.arrangement.open) do if id == oid then out = true end end
    if out and s.state ~= "tiled" then run_plan("park", sid, function() return acc.push(doc, sid, oid) end)
    else run_plan("pull", sid, function(ws) return acc.pull(doc, sid, oid, ws) end) end
end)
on("acc_remove", function(v)           -- k * 100 + i: take that layer out (its window stays)
    if not accordions_on() then return end
    v = math.floor(tonumber(v) or -1)
    local sid, oid = acc.layer_oid(doc, v // 100, v % 100)
    if sid and oid then run_plan("remove", sid, function(ws) return acc.remove(doc, sid, oid, ws) end) end
end)
on("acc_step", function(v)             -- k * 10 + (1 next · 0 previous)
    if not accordions_on() then return end
    v = math.floor(tonumber(v) or -1)
    local sid = acc.strip_sid(doc, v // 10)
    if sid then run_plan("pull", sid, function(ws) return acc.step(doc, sid, v % 10 == 1 and 1 or -1, ws) end) end
end)
on("acc_move", function(v)             -- k * 10000 + from * 100 + to: reorder
    if not accordions_on() then return end
    v = math.floor(tonumber(v) or -1)
    local k, from, to = v // 10000, (v // 100) % 100, v % 100
    local sid, oid = acc.layer_oid(doc, k, from)
    if sid and oid and from ~= to then loom.reorder(doc, sid, oid, to + 1); save_soon(); publish() end
end)
on("acc_all", function(v)              -- k: every layer out, or (all out already) all back in
    if not accordions_on() then return end
    local sid = acc.strip_sid(doc, math.floor(tonumber(v) or -1))
    if not sid then return end
    if doc.structures[sid].state == "tiled" then run_plan("fold", sid, function() return acc.fold(doc, sid) end)
    else run_plan("unfold", sid, function(ws) return acc.open_all(doc, sid, ws) end) end
end)
on("acc_dissolve", function(v)         -- k: the accordion gone, its windows out on this workspace
    if not accordions_on() then return end
    local sid = acc.strip_sid(doc, math.floor(tonumber(v) or -1))
    if sid then run_plan("dissolve", sid, function(ws) return acc.dissolve(doc, sid, ws) end) end
end)
