-- Saved environments (D43): the Overview's Environments drawer. Save the desktop as it is now; later,
-- see what restoring it would do, and do it — moving the windows already open to their workspaces,
-- opening what is missing from its installed entry, putting the names, accents and groups back.
-- Nothing is ever closed. The rules are lib/environments (pure, unit-tested); this reads the desktop
-- for them and carries a restore out, saying what happened.
--
-- ctx: decode(json), apps() (the apps service's list), identities() / set_identities(store),
-- save_identities(), build_tiles(), say(ok, message), apply_moves(moves, done(made, failed)),
-- safe_mode.

local envs = require("lib/environments")
local apps = require("lib/apps")
local hypr = require("lib/hypr")

local FILE = "environments.json"

return function(ctx)
    local store = envs.clean((function()
        local ok, t = pcall(sys.ask, "files.read", FILE, "json")
        return ok and t or nil
    end)())
    local function save() if not ctx.safe_mode then sys.call("files.write", FILE, store) end end

    local view, current = "list", nil   -- list | env | preview; the environment open in the drawer
    local rows, armed, naming, plan = {}, nil, nil, nil

    local function now() local ok, t = pcall(os.time); return ok and t or 0 end
    local function when(t)
        if not t or t <= 0 then return "" end
        local ok, s = pcall(os.date, "%d %b %H:%M", t)
        return ok and s or ""
    end
    local function summary(e)
        local named, apps_n = 0, #e.windows
        for _ in pairs(type(e.identities.spaces) == "table" and e.identities.spaces or {}) do named = named + 1 end
        local groups = type(e.identities.groups) == "table" and #e.identities.groups or 0
        local parts = { apps_n == 1 and "1 window" or (apps_n .. " windows") }
        if named > 0 then parts[#parts + 1] = named .. " named" end
        if groups > 0 then parts[#parts + 1] = groups == 1 and "1 group" or (groups .. " groups") end
        local w = when(e.saved)
        if w ~= "" then parts[#parts + 1] = w end
        return table.concat(parts, " · ")
    end

    local function publish(title)
        local out = {}
        for i, r in ipairs(rows) do
            local label = r.label
            if armed == i then label = "Again to delete it · Esc keeps it" end
            out[i] = { label = label, sub = r.sub or "", danger = r.danger or false }
        end
        model.env_rows = out
        text.env_title = title
        fact.env_sel = math.min(fact.env_sel, math.max(#out - 1, 0))
    end
    local function show_list()
        view, current, armed, plan = "list", nil, nil, nil
        rows = { { kind = "save", label = "Save this desktop as…", sub = "its windows, folders, names and groups" } }
        for i, e in ipairs(store.envs) do rows[#rows + 1] = { kind = "open", i = i, label = e.name, sub = summary(e) } end
        model.env_lines = {}
        fact.env_open = 1
        publish(#store.envs == 0 and "ENVIRONMENTS · NONE SAVED YET" or "ENVIRONMENTS")
    end
    local function show_env(i)
        local e = store.envs[i]
        if not e then show_list(); return end
        view, current, armed, plan = "env", i, nil, nil
        rows = { { kind = "preview", label = "Restore…", sub = "see what it would do first" },
                 { kind = "rename", label = "Rename…" }, { kind = "duplicate", label = "Duplicate" },
                 { kind = "delete", label = "Delete", danger = true }, { kind = "back", label = "‹ Back" } }
        model.env_lines = {}
        fact.env_open, fact.env_sel = 2, 0
        publish(string.upper(e.name))
    end

    -- ── Saving: the clients, each app's entry, and for a terminal the folder its shell is in (the
    -- folder a terminal would be opened in again; lib/hypr `terminal_shell` finds the shell) ──
    local function folder_of(pid, done)
        if pid <= 0 then done(""); return end
        run("ps", { "-o", "pid=,comm=", "--ppid", tostring(pid), "--sort=start_time" }, function(out)
            local shell = hypr.terminal_shell(out)
            if not shell then done(""); return end
            run("readlink", { "/proc/" .. tostring(shell) .. "/cwd" }, function(dir, code)
                done(code == 0 and (string.gsub(dir or "", "%s+$", "")) or "")
            end)
        end)
    end
    local TERMINALS = { kitty = true, foot = true, alacritty = true, ghostty = true, ["com.mitchellh.ghostty"] = true }
    local function capture(name, done)
        run("hyprctl", { "-j", "clients" }, function(out, code)
            if code ~= 0 then ctx.say(false, "Could not read windows from Hyprland: nothing saved"); return end
            local list = ctx.apps()
            local windows, waiting = {}, 1
            local function finished()
                waiting = waiting - 1
                if waiting > 0 then return end
                done(envs.capture(name, now(), ctx.identities(), windows))
            end
            for _, c in ipairs(hypr.windows(ctx.decode(out))) do
                if c.workspace >= 1 then
                    local entry = apps.app_for(list, c.class)
                    local w = { class = c.class, desktop = entry and entry.id or "", workspace = c.workspace, title = c.title, cwd = "" }
                    windows[#windows + 1] = w
                    if TERMINALS[string.lower(c.class)] then
                        waiting = waiting + 1
                        folder_of(c.pid, function(dir) w.cwd = dir; finished() end)
                    end
                end
            end
            finished()
        end)
    end

    -- ── Restoring: first the plan, shown; then, asked, carried out ──
    local function preview(i)
        local e = store.envs[i]
        if not e then return end
        run("hyprctl", { "-j", "clients" }, function(out, code)
            if code ~= 0 then ctx.say(false, "Could not read windows from Hyprland"); return end
            local installed = {}
            for _, a in ipairs(ctx.apps()) do if type(a.id) == "string" then installed[a.id] = true end end
            local p = envs.plan(e, hypr.windows(ctx.decode(out)), installed)
            -- a folder that is gone opens in the home folder instead: checked before it is shown
            local waiting = 1
            local function ready()
                waiting = waiting - 1
                if waiting > 0 then return end
                plan = p
                view, current, armed = "preview", i, nil
                local lines = {}
                local function line(t, tone) if #lines < 14 then lines[#lines + 1] = { text = t, tone = tone } end end
                local named = 0
                for _ in pairs(type(e.identities.spaces) == "table" and e.identities.spaces or {}) do named = named + 1 end
                local groups = type(e.identities.groups) == "table" and #e.identities.groups or 0
                line(string.format("Names and groups: %d named, %d %s — replace what is set now", named, groups, groups == 1 and "group" or "groups"), 0)
                if p.in_place > 0 then line(string.format("Already in place: %d %s", p.in_place, p.in_place == 1 and "window" or "windows"), 3) end
                for _, m in ipairs(p.moves) do line(string.format("Move %s  %d → %d", m.app, m.from, m.to), 1) end
                for _, l in ipairs(p.launches) do
                    line(string.format("Open %s on %d%s", l.app, l.workspace, l.cwd ~= "" and ("  in " .. l.cwd) or (l.lost and "  (its folder is gone: home)" or "")), 1)
                end
                for _, c in ipairs(p.cannot) do line(string.format("Can't: %s (%s)", c.app, c.why), 2) end
                line("Nothing open is closed.", 3)
                model.env_lines = lines
                local todo = #p.moves + #p.launches
                rows = {}
                if todo > 0 or named > 0 or groups > 0 then rows[#rows + 1] = { kind = "restore", label = "Restore now", sub = string.format("%d to move, %d to open", #p.moves, #p.launches) } end
                rows[#rows + 1] = { kind = "back_env", label = "‹ Back" }
                fact.env_open, fact.env_sel = 3, 0
                publish("RESTORE " .. string.upper(e.name))
            end
            for _, l in ipairs(p.launches) do
                if l.cwd ~= "" then
                    waiting = waiting + 1
                    run("readlink", { "-e", l.cwd }, function(_, rc)
                        if rc ~= 0 then l.cwd, l.lost = "", true end
                        ready()
                    end)
                end
            end
            ready()
        end)
    end
    local function restore()
        local e, p = store.envs[current], plan
        if not e or not p then return end
        fact.env_open = 0
        ctx.set_identities(e.identities)
        ctx.save_identities()
        ctx.apply_moves(p.moves, function(made, failed)
            local list = ctx.apps()
            local asked, refused, n = 0, 0, 0
            local function step()
                n = n + 1
                local l = p.launches[n]
                if not l then
                    local parts = { string.format("%s restored", e.name) }
                    if #made > 0 then parts[#parts + 1] = string.format("%d moved", #made) end
                    if asked > 0 then parts[#parts + 1] = string.format("%d asked to open", asked) end
                    if failed + refused + #p.cannot > 0 then parts[#parts + 1] = string.format("%d could not be", failed + refused + #p.cannot) end
                    ctx.say(failed + refused == 0, table.concat(parts, " · "))
                    ctx.build_tiles()
                    return
                end
                local entry = nil
                for _, a in ipairs(list) do if a.id == l.desktop then entry = a; break end end
                if not entry or type(entry.exec) ~= "string" or entry.exec == "" then refused = refused + 1; step(); return end
                run("hyprctl", { "eval", envs.exec_cmd(l.workspace, envs.launch_line(entry.exec, l.app, l.cwd)) }, function(out, rc)
                    if rc == 0 and not string.find(string.lower(out or ""), "error") then asked = asked + 1 else refused = refused + 1 end
                    after(120, step)
                end)
            end
            step()
        end)
    end

    -- ── The drawer's rows ──
    local function name_field(kind, i, prefill)
        naming = { kind = kind, i = i }
        text.env_name = prefill or ""
        fact.env_naming = true
        emit("env_focus_name")
    end
    on("env_toggle", function()
        if fact.env_open > 0 then fact.env_open = 0; naming = nil; fact.env_naming = false else show_list() end
    end)
    on("env_back", function()
        if naming then naming = nil; fact.env_naming = false; return end
        if armed then armed = nil; publish(text.env_title); return end
        if view == "preview" and current then show_env(current)
        elseif view == "env" then show_list()
        else fact.env_open = 0 end
    end)
    on("env_do", function(v)
        local i = math.floor(tonumber(v) or -1) + 1
        local r = rows[i]
        if not r then return end
        if r.kind == "save" then name_field("save", nil, "")
        elseif r.kind == "open" then show_env(r.i)
        elseif r.kind == "preview" then preview(current)
        elseif r.kind == "rename" then name_field("rename", current, store.envs[current] and store.envs[current].name or "")
        elseif r.kind == "duplicate" then
            local e = store.envs[current]
            if e and #store.envs < envs.MAX_ENVS then
                table.insert(store.envs, current + 1, envs.clean({ version = envs.VERSION, envs = { e } }).envs[1])
                store.envs[current + 1].name = string.sub(e.name, 1, 26) .. " copy"
                save(); ctx.say(true, "Duplicated " .. e.name); show_list()
            else ctx.say(false, "Twenty environments is the most kept: delete one first") end
        elseif r.kind == "delete" then
            if armed ~= i then armed = i; publish(text.env_title); return end
            local name = store.envs[current] and store.envs[current].name or "it"
            table.remove(store.envs, current)
            save(); ctx.say(true, name .. " deleted · nothing on the desktop changed"); show_list()
        elseif r.kind == "restore" then restore()
        elseif r.kind == "back" then show_list()
        elseif r.kind == "back_env" then show_env(current) end
    end)
    on("env_named", function()
        local what = naming
        naming = nil
        fact.env_naming = false
        if not what then return end
        local name = text.env_name or ""
        if (string.gsub(name, "%s", "")) == "" then ctx.say(false, "An environment needs a name"); return end
        if what.kind == "rename" then
            if store.envs[what.i] then store.envs[what.i].name = envs.clean({ version = envs.VERSION, envs = { { name = name, windows = {} } } }).envs[1].name; save() end
            show_env(what.i)
            return
        end
        if #store.envs >= envs.MAX_ENVS then ctx.say(false, "Twenty environments is the most kept: delete one first"); return end
        capture(name, function(e)
            table.insert(store.envs, 1, envs.clean({ version = envs.VERSION, envs = { e } }).envs[1])
            save()
            ctx.say(true, string.format("Saved %s · %s", e.name, summary(e)))
            if fact.env_open > 0 then show_list() end
        end)
    end)
    -- the drawer goes with the Overview
    on("fact:open", function(v) if v ~= "overview" then fact.env_open = 0; fact.env_naming = false; naming = nil end end)
end
