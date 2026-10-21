-- The Mechanical Shutter's controller (D35): which window it is for, where it is, what it offers,
-- and what a press does. Placement and the action registry are lib/shutter (pure, tested); every
-- command goes through lib/hypr and mooi's `run_action`, which reads the window back before it
-- says anything happened. The scene draws it (shell/mooi.plm, `shutter_surface`).
--
-- Nothing runs while it is closed: the window is looked at again every 250 ms only while it is
-- open, to follow it when it moves and to go when it closes.

local shutter = require("lib/shutter")
local hypr = require("lib/hypr")

return function(ctx)
    local target = nil        -- the window (lib/hypr's client) it is for
    local mon = nil           -- its monitor: { name, x, y, w, h, area }
    local place = nil         -- lib/shutter's placement
    local plates = {}         -- the plates shown, in order (their names)
    local rows = {}           -- the open panel's actions
    local branch = nil        -- the open third level: { id, items = { … } }
    local context = {}        -- what the connections know (cwd, repo, siblings, terminal)
    local watch = nil         -- the timer that follows the window while it is open
    local armed = nil         -- a row that asks twice (closing), armed by the first press
    local others = {}         -- the same app's other windows (connections)

    -- What the connections ask the system is optional: a tool that is missing, or one the scene may
    -- not run, leaves that connection out and never stops the shutter opening.
    local function try_run(cmd, args, fn, how)
        local ok, why = pcall(run, cmd, args, fn, how)
        if not ok then log("shutter · " .. cmd .. ": " .. tostring(why)) end
        return ok
    end
    local function decode_json(out)
        local ok, v = pcall(json.decode, out or "")
        return ok and v or nil
    end

    -- ── Publishing ─────────────────────────────────────────────
    local function local_rect(c)
        return { x = c.x - mon.x, y = c.y - mon.y, w = c.w, h = c.h }
    end
    local function publish_place()
        local s = ctx.settings().shutter
        local enabled = {}
        for _, p in ipairs(shutter.PLATES) do if s[p] ~= false then enabled[#enabled + 1] = p end end
        plates = enabled
        local win = local_rect(target)
        place = shutter.place(win, mon.area, { edge = s.edge, density = s.density, plates = #plates })
        fact.sh_wx, fact.sh_wy, fact.sh_ww, fact.sh_wh = win.x, win.y, win.w, win.h
        fact.sh_ax, fact.sh_ay = place.anchor.x, place.anchor.y
        fact.sh_spine = place.spine
        fact.sh_px = place.plates[1].x
        fact.sh_py = place.plates[1].y
        fact.sh_pw, fact.sh_ph = place.pw, place.ph
        fact.sh_pgap = place.sizes.gap
        fact.sh_dir = place.dir
        fact.sh_side = ({ right = 0, left = 1, inside = 2 })[place.side]
        fact.sh_n = #plates
        local m = {}
        for i, p in ipairs(plates) do
            m[i] = { label = shutter.LABELS[p], icon = ({ arrange = 0, workspace = 1, behaviour = 2, connections = 3 })[p],
                     acts = #shutter.actions(p, target, context) }
        end
        model.sh_plates = m
        text.sh_mon = mon.name
        text.sh_title = string.upper(target.class ~= "" and target.class or "window")
    end

    local function publish_panel()
        local i = fact.sh_panel
        if i < 0 or not plates[i + 1] then model.sh_rows = {}; return end
        rows = shutter.actions(plates[i + 1], target, context)
        local m = {}
        for j, r in ipairs(rows) do
            m[j] = { label = r.label, hint = r.hint, kind = ({ act = 0, branch = 1, danger = 2 })[r.kind] or 0, on = r.on, toggle = r.toggle,
                     armed = armed == r.id }
        end
        model.sh_rows = m
        local b = shutter.panel(place, i + 1, #rows, mon.area)
        fact.sh_bx, fact.sh_by, fact.sh_bw, fact.sh_bh = b.x, b.y, b.w, b.h
        fact.sh_row_h = place.sizes.row
        fact.sh_brx = b.from_left and 1 or -1        -- the side of the plate it opens on
        if fact.sh_row >= #rows then fact.sh_row = math.max(0, #rows - 1) end
    end

    local function publish_branch()
        if not branch then fact.sh_ext = false; model.sh_items = {}; return end
        local m = {}
        for k, it in ipairs(branch.items) do m[k] = { label = it.label, on = it.on == true } end
        model.sh_items = m
        -- the third level stands beside the panel, level with the row that opened it, on screen
        local s = place.sizes
        local w, h = 180, 30 + #m * 30
        local x = fact.sh_bx + fact.sh_bw + s.pad
        if fact.sh_brx < 0 or x + w > mon.area.x + mon.area.w - s.pad then x = fact.sh_bx - s.pad - w end
        local y = fact.sh_by + 30 + branch.row * s.row
        y = math.max(mon.area.y + s.pad, math.min(y, mon.area.y + mon.area.h - h - s.pad))
        fact.sh_ex, fact.sh_ey, fact.sh_ew, fact.sh_eh = x, y, w, h
        fact.sh_ext = true
        if fact.sh_esel >= #m then fact.sh_esel = 0 end
    end

    local function message(ok, said)
        text.sh_msg = string.upper(said or "")
        fact.sh_ok = ok
        emit("sh_said")
    end

    -- ── Closing ─────────────────────────────────────────────────
    local function close()
        if watch then cancel(watch); watch = nil end
        target, branch, armed = nil, nil, nil
        fact.sh_panel = -1; fact.sh_ext = false
        if fact.open == "shutter" then fact.open = "none" end
    end
    on("sh_close", close)
    -- One level back: the third level, then the panel, then the shutter itself.
    on("sh_back", function()
        if branch then branch = nil; publish_branch()
        elseif fact.sh_panel >= 0 then fact.sh_panel = -1; armed = nil; publish_panel()
        else close() end
    end)

    -- ── Following the window ────────────────────────────────────
    local function follow()
        if not target then return end
        run("hyprctl", { "-j", "clients" }, function(out, code)
            if not target or code ~= 0 then return end
            local now = hypr.find(decode_json(out), target.address)
            local seen = now and { x = now.x, y = now.y, w = now.w, h = now.h } or nil
            local was = { x = target.x, y = target.y, w = target.w, h = target.h }
            local how = shutter.track(was, seen)
            if how == "gone" then close(); ctx.report(true, "The window closed"); return end
            local changed = how == "moved" or now.floating ~= target.floating or now.fullscreen_mode ~= target.fullscreen_mode
                or now.pinned ~= target.pinned or now.workspace ~= target.workspace
            target = now
            if changed then publish_place(); publish_panel(); publish_branch() end
        end)
    end

    -- ── What the connections know ──────────────────────────────
    -- Deterministic, nothing guessed: the folder the window's process (or, for a terminal, the
    -- shell in it) is working in, the Git repository that folder is in, and the same app's other
    -- windows. Each arrives when it is read; the plate's count follows.
    local function learn(pid, clients)
        context = { terminal = false, siblings = 0 }
        others = {}
        for _, c in ipairs(hypr.windows(clients)) do
            if c.class == target.class and c.address ~= target.address then others[#others + 1] = c end
        end
        context.siblings = #others
        try_run("kitty", { "--version" }, function(_, code) context.terminal = code == 0; if target then publish_place(); publish_panel() end end)
        if pid <= 0 then return end
        local function at(dir)
            if type(dir) ~= "string" or dir == "" or not target then return end
            context.cwd = dir
            try_run("git", { "-C", dir, "rev-parse", "--show-toplevel" }, function(out, code)
                if code == 0 and target then context.repo = string.gsub(out or "", "%s+$", ""); publish_place(); publish_panel() end
            end)
            publish_place(); publish_panel()
        end
        -- A terminal's folder is what runs in it: its shell (the newest child that is a shell — kitty's
        -- `kitten` helpers are newer, and sit in the home folder: D43), or what the shell is running
        -- now (its newest child); the window's own process otherwise.
        local function shell_of(p, fn)
            try_run("ps", { "-o", "pid=,comm=", "--ppid", tostring(p), "--sort=start_time" }, function(out) fn(hypr.terminal_shell(out)) end)
        end
        local function child_of(p, fn)
            try_run("ps", { "-o", "pid=", "--ppid", tostring(p), "--sort=start_time" }, function(out)
                local last = nil
                for n in string.gmatch(out or "", "%d+") do last = tonumber(n) end
                fn(last)
            end)
        end
        shell_of(pid, function(shell)
            local function read(p)
                try_run("readlink", { "/proc/" .. tostring(p) .. "/cwd" }, function(dir, code)
                    if code == 0 then at((string.gsub(dir or "", "%s+$", ""))) end
                end)
            end
            if not shell then read(pid); return end
            child_of(shell, function(running) read(running or shell) end)
        end)
    end

    -- ── Opening ─────────────────────────────────────────────────
    -- `v` 0: the focused window (the key); 1: the window under the pointer (Super+Alt+right-click).
    on("open_shutter", function(v)
        local s = ctx.settings().shutter
        if not s.enabled then return end
        if fact.open == "shutter" then close(); return end
        run("hyprctl", { "-j", "monitors" }, function(mout)
            local monitors = decode_json(mout) or {}
            run("hyprctl", { "-j", "clients" }, function(cout)
                local clients = decode_json(cout) or {}
                local function pick(c)
                    if not c then ctx.report(false, "No window to open the shutter on"); return end
                    mon = nil
                    table.sort(monitors, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
                    for n, m in ipairs(monitors) do
                        if tonumber(m.id) == c.monitor then
                            fact.sh_moni = n - 1
                            local scale = tonumber(m.scale) or 1
                            local w = math.floor((tonumber(m.width) or 1920) / scale + 0.5)
                            local h = math.floor((tonumber(m.height) or 1080) / scale + 0.5)
                            local r = type(m.reserved) == "table" and m.reserved or { 0, 0, 0, 0 }   -- left, top, right, bottom
                            mon = { name = tostring(m.name), x = tonumber(m.x) or 0, y = tonumber(m.y) or 0, w = w, h = h,
                                    area = { x = r[1] or 0, y = r[2] or 0, w = w - (r[1] or 0) - (r[3] or 0), h = h - (r[2] or 0) - (r[4] or 0) } }
                        end
                    end
                    if not mon then ctx.report(false, "Could not tell which monitor the window is on"); return end
                    target, branch, armed = c, nil, nil
                    fact.sh_panel = -1; fact.sh_plate = 0; fact.sh_row = 0; fact.sh_ext = false; fact.sh_esel = 0
                    text.sh_msg = ""
                    context = {}
                    publish_place()
                    learn(c.pid, clients)
                    fact.open = "shutter"
                    if watch then cancel(watch) end
                    watch = every(250, follow)
                end
                if tonumber(v) == 1 then
                    run("hyprctl", { "-j", "cursorpos" }, function(pout)
                        local p = decode_json(pout) or {}
                        local px, py = tonumber(p.x) or -1, tonumber(p.y) or -1
                        local best = nil
                        for _, c in ipairs(hypr.windows(clients)) do
                            if px >= c.x and px < c.x + c.w and py >= c.y and py < c.y + c.h then
                                -- the topmost there: floating over tiled, then the most recently focused
                                if not best or (c.floating and not best.floating) or (c.floating == best.floating and c.recency < best.recency) then best = c end
                            end
                        end
                        pick(best)
                    end)
                else
                    local focused = nil
                    for _, c in ipairs(hypr.windows(clients)) do if c.focused then focused = c end end
                    pick(focused)
                end
            end)
        end)
    end)

    -- ── Plates, rows, the third level ───────────────────────────
    on("sh_pick", function(v)
        local i = math.floor(tonumber(v) or -1)
        if not target or not plates[i + 1] then return end
        branch, armed = nil, nil
        if fact.sh_panel == i then fact.sh_panel = -1 else fact.sh_panel = i; fact.sh_row = 0 end
        fact.sh_plate = i
        publish_panel(); publish_branch()
    end)
    -- Hover preview (shutter.preview): a plate held under the pointer opens after a breath.
    local hovered = -1
    on("sh_hover", function(v)
        local i = math.floor(tonumber(v) or -1)
        hovered = i
        if not ctx.settings().shutter.preview or not target or i < 0 or i == fact.sh_panel then return end
        after(220, function()
            if hovered == i and target and fact.sh_panel ~= i then
                branch, armed = nil, nil
                fact.sh_panel = i; fact.sh_plate = i; fact.sh_row = 0
                publish_panel(); publish_branch()
            end
        end)
    end)

    -- After an action: gone where it should go (moved away, closed), it is put away; otherwise it
    -- stays, showing what happened — a failure stays open, so it can be tried again or otherwise.
    local function done(ok, now, stay)
        if now then target = now end
        armed = nil
        if ok and (not stay or not target) then close(); return end
        if not target then close(); return end
        branch = nil
        publish_place(); publish_panel(); publish_branch()
    end
    local function act(action, opts, stay)
        ctx.run_action(action, target.address, opts or {}, function(ok, now)
            message(ok, ok and "Done" or "It did not take")
            done(ok, now, stay)
        end)
    end
    local function opacity(alpha)
        local cmd = hypr.dispatch("opacity", target.address, { alpha = alpha })
        if not cmd then return end
        run("hyprctl", { "dispatch", cmd }, function()
            run("hyprctl", { "getprop", "address:" .. target.address, "opacity" }, function(out, code)
                local got = tonumber(string.match(out or "", "[%d.]+"))
                local ok = code == 0 and got ~= nil and math.abs(got - alpha) < 0.02
                message(ok, ok and string.format("Opacity %d%%", math.floor(alpha * 100 + 0.5)) or "Hyprland did not take the opacity")
                ctx.report(ok, ok and string.format("Opacity %d%%", math.floor(alpha * 100 + 0.5)) or "Hyprland did not take the opacity")
            end)
        end)
    end

    local function open_branch(r, row)
        local items = {}
        if r.id == "size" then
            for _, sz in ipairs(shutter.SIZES_FLOAT) do items[#items + 1] = { label = string.format("%s  %d × %d", sz[1], sz[2], sz[3]), w = sz[2], h = sz[3],
                on = target.w == sz[2] and target.h == sz[3] } end
        elseif r.id == "swap" then
            for _, d in ipairs(shutter.SWAP) do items[#items + 1] = { label = d[1], direction = d[2] } end
        elseif r.id == "opacity" then
            for _, o in ipairs(shutter.OPACITY) do items[#items + 1] = { label = o .. "%", alpha = o / 100 } end
        elseif r.id == "move" or r.id == "follow" then
            -- the real map: the workspaces the bar holds, the one it is on marked
            for _, w in ipairs(ctx.spaces()) do
                items[#items + 1] = { label = string.format("Workspace %d%s", w.id, (w.windows > 0) and string.format("  ·  %d", w.windows) or ""),
                                      ws = w.id, on = w.id == target.workspace }
            end
        elseif r.id == "siblings" then
            for _, c in ipairs(others) do
                items[#items + 1] = { label = (c.title ~= "" and c.title or c.class), address = c.address }
            end
        end
        branch = { id = r.id, row = row, items = items }
        fact.sh_esel = 0
        publish_branch()
    end

    on("sh_row", function(v)
        local j = math.floor(tonumber(v) or -1)
        local r = rows[j + 1]
        if not r or not target then return end
        fact.sh_row = j
        if r.kind == "branch" then
            if branch and branch.id == r.id then branch = nil; publish_branch() else open_branch(r, j) end
            return
        end
        branch = nil; publish_branch()
        if r.kind == "danger" and armed ~= r.id then
            armed = r.id; message(false, "Press again to " .. string.lower(r.label)); publish_panel()
            after(3000, function() if armed == r.id then armed = nil; if target then publish_panel() end end end)
            return
        end
        local id, ws = r.id, target.workspace
        if id == "maximize" or id == "fullscreen" or id == "float" or id == "pin" or id == "center" then act(id, {}, true)
        elseif id == "close" then act("close", {}, false)
        elseif id == "prev" then act("move", { workspace = ws - 1, follow = false }, false)
        elseif id == "next" then act("move", { workspace = ws + 1, follow = false }, false)
        elseif id == "bring" then act("bring", { workspace = ctx.active_ws() }, true)
        elseif id == "open_dir" or id == "open_repo" then
            local ok = try_run("xdg-open", { (id == "open_dir") and context.cwd or context.repo })
            ctx.report(ok, ok and "Opening it" or "Could not open it"); if ok then close() else message(false, "Could not open it") end
        elseif id == "term_here" then
            local ok = pcall(spawn, "kitty", { "--directory", context.cwd })
            ctx.report(ok, ok and "A terminal there" or "Could not start kitty"); if ok then close() else message(false, "Could not start kitty") end
        elseif id == "copy_path" or id == "copy_title" then
            local ok = try_run("wl-copy", {}, nil, { input = (id == "copy_path") and context.cwd or target.title, output = false })
            message(ok, ok and "Copied" or "Could not copy")
        end
    end)

    on("sh_item", function(v)
        local k = math.floor(tonumber(v) or -1)
        local it = branch and branch.items[k + 1]
        if not it or not target then return end
        local id = branch.id
        if id == "size" then act("size", { w = it.w, h = it.h }, true)
        elseif id == "swap" then act("swap", { direction = it.direction }, true)
        elseif id == "opacity" then opacity(it.alpha)
        elseif id == "move" then act("move", { workspace = it.ws, follow = false }, false)
        elseif id == "follow" then act("move", { workspace = it.ws, follow = true }, false)
        elseif id == "siblings" then
            local to = it.address
            close()
            ctx.run_action("focus", to, {}, function() end)
        end
    end)

    return { close = close }
end
