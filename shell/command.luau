-- The command membrane: what it lists, and what choosing something does.
-- Ranking is lib/search (pure, tested). Window and app text is data: it is shown and
-- matched, never run. Apps start only through pleamar's `apps.launch`, which accepts
-- only applications the `apps` service itself reported.

local search = require("lib/search")
local hypr = require("lib/hypr")

return function(ctx)
    local USAGE = "usage.json"
    local usage = {}
    do
        local ok, t = pcall(sys.ask, "files.read", USAGE, "json")
        if ok and type(t) == "table" then usage = t end
    end
    local function remember(key)
        search.remember(usage, key, 200)
        sys.call("files.write", USAGE, usage)
    end

    local windows = {}       -- hypr.windows(), refreshed on every open and after actions
    local spaces = {}        -- { id, windows, active } from the workspaces service
    local active_ws = 0
    local current = {}       -- the ranked items behind model.res, same order

    sys.watch("workspaces", function(w)
        active_ws = tonumber(w.active) or active_ws
        spaces = {}
        for _, s in ipairs(w.list or {}) do
            if (tonumber(s.id) or 0) > 0 then spaces[#spaces + 1] = s end
        end
    end)

    local ACTIONS = {
        { title = "System controls", act = "system", alt = { "volume", "sound", "audio", "brightness", "battery", "wifi", "network" }, sub = "Volume, brightness, battery, network" },
        { title = "Window actions", act = "window", alt = { "float", "fullscreen", "pin", "move window", "close window" }, sub = "For the focused window" },
    }

    local function pool(p)
        local items = {}
        local empty = p.text == ""
        local only = p.kinds
        if not only or only.window then
            for i, w in ipairs(windows) do
                items[#items + 1] = {
                    kind = "win", title = w.title ~= "" and w.title or w.class, alt = { w.class },
                    sub = string.format("%s · workspace %d", w.class, w.workspace),
                    key = "win:" .. string.lower(w.class), address = w.address, class = w.class,
                    base = math.max(0, 300 - i * 20),    -- recently focused first when nothing is typed
                }
            end
        end
        if not only then
            for _, a in ipairs(ctx.apps() or {}) do
                items[#items + 1] = {
                    kind = "app", title = a.name or a.id or "?", sub = "Application",
                    alt = { a.local_name, a.id, a.wmclass, string.match(tostring(a.exec or ""), "^%s*(%S+)") },
                    key = "app:" .. tostring(a.id or a.name), exec = a.exec, icon = a.icon,
                }
            end
        end
        if not empty and (not only or p.workspace) then
            local seen = {}
            for _, s in ipairs(spaces) do
                local n = tonumber(s.id)
                seen[n] = true
                items[#items + 1] = {
                    kind = "space", title = "Workspace " .. n, alt = { "ws " .. n, "desktop " .. n, tostring(n) },
                    sub = n == active_ws and "You are here" or string.format("%d window%s", s.windows or 0, (s.windows == 1) and "" or "s"),
                    key = "space:" .. n, ws = n, base = (p.workspace == n) and 2000 or 0,
                }
            end
            if p.workspace and p.workspace >= 1 and p.workspace <= 99 and not seen[p.workspace] then
                items[#items + 1] = { kind = "space", title = "Workspace " .. p.workspace, sub = "Empty, created when you go there",
                    key = "space:" .. p.workspace, ws = p.workspace, base = 2000, alt = { tostring(p.workspace) } }
            end
        end
        if not empty and (not only or only.action) then
            for _, a in ipairs(ACTIONS) do
                items[#items + 1] = { kind = "mooi", title = a.title, alt = a.alt, sub = a.sub, key = "mooi:" .. a.act, act = a.act }
            end
        end
        return items
    end

    local function refresh(keep_selection)
        local p = search.parse(text.query)
        local q = p.text
        if p.workspace then q = "" end          -- a bare number matches by `base`, not by text
        current = search.rank(pool(p), q, usage, fact.max_results)
        local rows = {}
        for i, it in ipairs(current) do
            local icon = it.icon
            if it.kind == "win" then icon = ctx.icon_for(it.class) end
            local letter = ""
            if not icon or icon == "" then
                letter = it.kind == "space" and tostring(it.ws) or (it.kind == "mooi" and "m" or ctx.letter(it.title))
            end
            rows[i] = { kind = it.kind, title = it.title, sub = it.sub, icon = icon or "", letter = letter }
        end
        model.res = rows
        text.cempty = (text.query == "") and "Nothing open, and nothing used yet. Type to search."
            or "No match. @ searches windows, > searches mooi."
        if not keep_selection or fact.csel >= #rows then fact.csel = 0 end
    end

    local function load_windows(fn)
        run("hyprctl", { "-j", "clients" }, function(out, code)
            windows = code == 0 and hypr.windows(ctx.decode(out)) or {}
            if fn then fn() end
        end)
    end

    local function close()
        if fact.open == "command" then fact.open = "none" end
    end

    on("fact:open", function(v)
        if v == "command" then
            text.query = ""
            refresh()
            load_windows(function() refresh() end)
        end
    end)
    on("text:query", function() refresh() end)

    -- Choosing a result.
    on("crun", function(i)
        local it = current[(tonumber(i) or -1) + 1]
        if not it then return end
        if it.kind == "app" then
            if not it.exec then ctx.report(false, it.title .. " has no command to start") return end
            sys.call("apps.launch", it.exec)
            remember(it.key)
            log("command · started " .. it.title)
            close()
        elseif it.kind == "win" then
            fact.busy = true
            ctx.run_action("focus", it.address, {}, function(done)
                if done then remember(it.key); close() else load_windows(function() refresh(true) end) end
            end)
        elseif it.kind == "space" then
            local want = it.ws
            sys.call("workspaces.focus", want)
            -- Only closes once Hyprland says it is there.
            local tries = 0
            local function confirm()
                tries = tries + 1
                if active_ws == want then remember(it.key); close()
                elseif tries < 8 then after(50, confirm)
                else ctx.report(false, "Hyprland did not switch to workspace " .. want) end
            end
            confirm()
        elseif it.kind == "mooi" then
            remember(it.key)
            emit(it.act == "system" and "open_system" or "open_window")
        end
    end)

    -- A satellite action on the selected window result.
    on("csat", function(a)
        local it = current[(tonumber(fact.csel) or 0) + 1]
        local action = hypr.SATELLITE[(tonumber(a) or -1) + 1]
        if not it or it.kind ~= "win" or not action then ctx.report(false, "No window selected") return end
        local opts = {}
        if action == "bring" then opts.workspace = active_ws end
        ctx.run_action(action, it.address, opts, function(done, now)
            if done and action == "focus" then remember(it.key); close() return end
            if action == "close" and done then fact.cmode = "list" end
            load_windows(function() refresh(true) end)
        end)
    end)
end
