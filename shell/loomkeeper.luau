-- Loom / Fold's keeper (D194, spec §3, §5): lives in the bar's logic and decides whether the Loom / Fold
-- program (shell/mooi-loom.plm) runs, starts and stops it, and keeps the desktop safe when it fails.
--
--   · What is *wanted* (lib/loommode.runs(settings.loom.mode), and no recovery standing) and what is
--     *happening* (the process) are kept apart, as for BMO: `sync` is the only way in, every callback
--     comes back to it, and `gen` names the process a callback belongs to.
--   · A death that was not asked for is restarted (1 s, 2 s…); three deaths within 10 s of starting →
--     it stops trying, says so once, and stands in `recovery` until the owner presses Start again
--     (Settings → Loom / Fold, `mooi loom restart`).
--   · Whenever the program ends — asked to, crashed, or given up on — every window it had parked is
--     brought back from what loom.json says, and any window Hyprland still shows on a Loom park is
--     brought to the workspace the owner is on. A dead program never strands a window (spec §5.3).
--   · It is the only writer of loom-state.json: { running, recovery, mode, structures, objects, parked,
--     error, since }. The settings window reads it for its status line.
--
-- ctx: settings(), shell_dir(), log(message). Returns sync() (the bar calls it when settings change).

local lm = require("lib/loommode")
local loom = require("lib/loom")
local park = require("lib/loompark")

local STATE_FILE = "loom-state.json"
local QUICK_S, GIVE_UP = 10, 3

return function(ctx)
    local st = { state = "stopped", gen = 0, id = nil, started = 0, tries = 0, recovery = false,
                 health = {}, error = "", stop_timer = 0 }

    -- what the last session left: a recovery stands across a restart of the bar
    do
        local ok, h = pcall(sys.ask, "files.read", STATE_FILE, "json")
        if ok and type(h) == "table" and h.recovery == true then st.recovery = true end
    end

    local function mode()
        local s = ctx.settings()
        return lm.valid_mode(type(s.loom) == "table" and s.loom.mode or "native")
    end
    local function write()
        local h = st.health
        pcall(sys.call, "files.write", STATE_FILE, {
            running = st.state == "running", recovery = st.recovery, mode = mode(),
            structures = tonumber(h.structures) or 0, objects = tonumber(h.objects) or 0, parked = tonumber(h.parked) or 0,
            error = st.error, since = st.started,
        })
    end

    -- Every window back: those loom.json says are parked, to where they came from; those Hyprland shows
    -- on a Loom park that the document does not know, to the workspace the owner is on.
    local function unpark_all(why)
        local ok, raw = pcall(sys.ask, "files.read", "loom.json", "json")
        local doc = loom.clean(ok and raw or nil)
        local n = 0
        for _, step in ipairs(park.unpark_all(doc)) do
            for _, cmd in ipairs(step.cmds) do run("hyprctl", { "dispatch", cmd }) end
            n = n + 1
        end
        run("hyprctl", { "-j", "activeworkspace" }, function(out)
            local ws = tonumber(string.match(tostring(out or ""), '"id"%s*:%s*(%-?%d+)')) or 1
            run("hyprctl", { "-j", "clients" }, function(cl)
                local okd, clients = pcall(ctx.decode, cl)
                for _, cmd in ipairs(park.rescue(park.stray(okd and clients or {}), ws)) do run("hyprctl", { "dispatch", cmd }) end
            end)
        end)
        if n > 0 then ctx.log("loom · " .. why .. ": " .. n .. " parked windows brought back") end
    end

    local sync   -- below
    local function launch()
        st.gen = st.gen + 1
        local mine = st.gen
        st.state, st.started, st.error, st.health = "starting", os.time(), "", {}
        local said = {}
        st.id = spawn("pleamar", { "--scene", ctx.shell_dir() .. "/mooi-loom.plm", "--no-hud", "--stall", "0" }, function(line)
            if mine ~= st.gen then return end
            line = tostring(line or "")
            -- the program says it is up, and how much it holds (shell/mooi-loom.luau `health`)
            if string.find(line, "loom-ready", 1, true) then st.state = "running"; write() end
            local s, o, p = string.match(line, "loom%-health structures=(%d+) objects=(%d+) parked=(%d+)")
            if s then st.health = { structures = tonumber(s), objects = tonumber(o), parked = tonumber(p) }; write() end
            if #said < 4 and string.find(line, "error") then said[#said + 1] = line end
        end, function(_, code)
            if mine ~= st.gen then return end
            local asked = st.state == "stopping"
            st.id, st.state = nil, "stopped"
            unpark_all(asked and "stopped" or "it ended")
            if not asked then
                st.error = table.concat(said, " / ")
                local lived = os.time() - st.started
                if lived < QUICK_S then st.tries = st.tries + 1 else st.tries = 0 end
                ctx.log("loom · ended (" .. tostring(code) .. ") after " .. lived .. " s · quick deaths " .. st.tries
                        .. (st.error ~= "" and (": " .. st.error) or ""))
                if st.tries >= GIVE_UP then
                    st.recovery = true
                    ctx.log("loom · failed " .. st.tries .. " times quickly; stopped (recovery)")
                    run("notify-send", { "-a", "mooi", "Loom / Fold stopped",
                        "It failed " .. st.tries .. " times in a row. Your windows are back on their workspaces; Settings → Loom / Fold starts it again." })
                    write()
                    return
                end
                write()
                after(1000 * math.max(1, st.tries), function() sync() end)
                return
            end
            write()
            sync()      -- wanted again meanwhile (a mode switched back quickly)?
        end, { errors = true })
        write()
    end

    local function stop()
        if st.state ~= "starting" and st.state ~= "running" then return end
        st.state = "stopping"
        local mine = st.gen
        -- asked politely: the program brings its windows back and saves; if it has not gone in 4 s, ended
        run("pleamar", { "--say", "mooi-loom", "emit loom_quit" })
        after(4000, function()
            if mine == st.gen and st.state == "stopping" and st.id then kill(st.id) end
        end)
    end

    sync = function()
        local want = lm.runs(mode()) and not st.recovery and not ctx.safe_mode
        if want and st.state == "stopped" then launch()
        elseif not want and (st.state == "starting" or st.state == "running") then stop()
        else write() end
    end

    -- Start again after a recovery (Settings → Loom / Fold, `mooi loom restart`)
    on("loom_restart", function()
        st.recovery, st.tries = false, 0
        write()
        sync()
    end)
    -- `mooi loom unpark`: every window back, whatever is running
    on("loom_unpark", function()
        if st.id and st.state == "running" then run("pleamar", { "--say", "mooi-loom", "emit loom_cmd 1" })
        else unpark_all("asked") end
    end)

    -- a moment after the bar is up, so the programs do not all start together; and whenever the settings
    -- change (a moment later, so the bar has read them first: `ctx.settings()` is the bar's own copy)
    after(1500, function() sync() end)
    pcall(sys.watch, "files:settings.json", function() after(100, function() sync() end) end)
    return sync
end
