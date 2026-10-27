-- The player's equaliser, a part of mooi-player.luau: ten bands and a preamp drawn by mooi, applied
-- by EasyEffects (the user's choice). mooi writes one preset of its own (output/mooi.json, and
-- mooi-<name>.json for SAVE AS) and never touches the user's; off is EasyEffects' global bypass.
-- EasyEffects' command line waits forever when its service is not up, so the service is started
-- (and asked until it answers) before anything else is said to it. The state is player-eq.json.
local E = require("lib/eqpreset")

local M = {}

function M.new(ctx)
    local home, say = ctx.home, ctx.say
    local EE = home .. "/.local/share/easyeffects/output"
    local FILE = "player-eq.json"
    local saved = ctx.read(FILE, "json")
    local st = { on = false, preset = "flat", bands = E.preset("flat"), preamp = 0 }
    if type(saved) == "table" then
        st.on = saved.on == true
        st.preset = type(saved.preset) == "string" and saved.preset or "flat"
        if type(saved.bands) == "table" and #saved.bands == 10 then st.bands = saved.bands end
        st.preamp = tonumber(saved.preamp) or 0
        st.before = type(saved.before) == "string" and saved.before or nil
    end
    local theirs = {}           -- the user's own EasyEffects presets ({ file, label }), loadable, never written
    local up = false            -- the service answers
    -- EasyEffects there at all? Without it the switch is off-limits and says what to install
    fact.eq_ok = true
    run("easyeffects", { "--version" }, function(_, code)
        fact.eq_ok = code == 0
        if code ~= 0 then text.eq_name = "INSTALL EASYEFFECTS FOR THE EQUALISER" end
    end)

    local function show()
        fact.eq_on = st.on
        for i = 1, 10 do fact["eq_b" .. (i - 1)] = st.bands[i] end
        fact.eq_pre = st.preamp
        local lo, mid, hi = E.knobs(st.bands)
        fact.eq_lo, fact.eq_mid, fact.eq_hi = lo, mid, hi
        text.eq_name = string.upper(st.preset)
        local chips = {}
        for i, name in ipairs(E.ORDER) do chips[#chips + 1] = { name = string.upper(name), k = i, on = st.preset == name, mine = true, n = #chips } end
        for i, t in ipairs(theirs) do
            if #chips >= 12 then break end
            chips[#chips + 1] = { name = string.upper(t.label), k = 100 + i, on = st.preset == t.file, mine = false, n = #chips }
        end
        model.eqchips = chips
    end
    local function keep()
        if tostring(sys.ask("env", "MOOI_SAFE") or "") ~= "1" then pcall(sys.call, "files.write", FILE, st) end
    end

    -- the service, then `done`; it answers `-s` once it is up
    local function with_service(done)
        if up then done(); return end
        run("pgrep", { "-x", "easyeffects" }, function(_, code)
            if code ~= 0 then spawn("easyeffects", { "--service-mode", "--hide-window" }, function() end, function() up = false end) end
            local tries = 0
            local function ask()
                tries = tries + 1
                run("pgrep", { "-x", "easyeffects" }, function(_, c)
                    if c == 0 and tries > 2 then up = true; done()
                    elseif tries < 20 then after(300, ask)
                    else say("EASYEFFECTS DID NOT START") end
                end)
            end
            after(300, ask)
        end)
    end

    -- write mooi's preset beside the user's and load it, bypass off
    local function push(name, load)
        name = name or "mooi"
        if load == nil then load = true end
        pcall(sys.call, "files.write", "player-eq-ee.json", E.easyeffects(st.bands, st.preamp))
        run("mkdir", { "-p", EE }, function()
            run("cp", { ctx.folder .. "/player-eq-ee.json", EE .. "/" .. name .. ".json" }, function(_, code)
                if code ~= 0 then say("COULD NOT WRITE THE EQ PRESET"); return end
                -- written always; applied only when asked (SAVE AS while the EQ is off only keeps it)
                if not load then return end
                with_service(function()
                    run("easyeffects", { "-l", name })
                    run("easyeffects", { "-b", "2" })
                end)
            end)
        end)
    end
    -- On: remember the user's own preset first (once), then mooi's. Off: give theirs back, bypass
    -- off — EasyEffects keeps its state across runs, so leaving it bypassed or on mooi's preset
    -- would change the user's own EasyEffects. With nothing to give back, it is bypassed.
    local function apply()
        keep(); show()
        if st.on then
            with_service(function()
                -- asked every time it is switched on: the user may have picked another preset since
                -- (mooi's own loaded now tells nothing, so the last one known stands)
                run("easyeffects", { "-s" }, function(out)
                    st.before = E.last_output(out) or st.before
                    keep()
                    push()
                end)
            end)
        elseif up then
            if st.before then
                run("easyeffects", { "-l", st.before })
                run("easyeffects", { "-b", "2" })
            else
                run("easyeffects", { "-b", "1" })
            end
        end
    end
    local pending = 0
    local function soon()          -- a slider's drag settles before it is written (150 ms of quiet)
        show()
        pending = pending + 1
        local mine = pending
        after(150, function() if mine == pending then apply() end end)
    end

    run("ls", { EE }, function(out, code)
        if code == 0 then
            for f in tostring(out or ""):gmatch("[^\n]+") do
                local n = f:match("^(.-)%.json$")
                -- the user's own, and the ones saved from here (mooi-<name>); never mooi.json itself
                if n and n ~= "mooi" then theirs[#theirs + 1] = { file = n, label = n:match("^mooi%-(.+)$") or n } end
            end
            show()
        end
    end)

    on("eq_toggle", function()
        if not fact.eq_ok then say("INSTALL EASYEFFECTS FOR THE EQUALISER"); return end
        st.on = not st.on
        apply()
    end)
    on("eq_band", function(v)
        local n = math.floor(tonumber(v) or 0)
        local b = math.floor(n / 100) + 1
        if b < 1 or b > 10 then return end
        st.bands[b] = math.max(-12, math.min(12, n % 100 - 12))
        st.preset = "custom"
        soon()
    end)
    on("eq_pre", function(v) st.preamp = math.max(-12, math.min(12, (tonumber(v) or 12) - 12)); soon() end)
    on("eq_knob", function(v)
        local n = math.floor(tonumber(v) or 0)
        st.bands = E.from_knob(st.bands, math.floor(n / 100), n % 100 - 12)
        st.preset = "custom"
        soon()
    end)
    on("eq_preset", function(v)
        local k = math.floor(tonumber(v) or 0)
        if k >= 100 then
            local t = theirs[k - 100]
            if not t then return end
            local name = t.file
            st.preset = name
            keep(); show()
            -- the user's preset as it is: loaded, not rewritten
            if st.on then with_service(function() run("easyeffects", { "-l", name }); run("easyeffects", { "-b", "2" }) end) end
            return
        end
        local name = E.ORDER[k]
        if not name then return end
        st.preset = name
        st.bands = E.preset(name)
        apply()
    end)
    on("submit:eq_save", function(v)
        local name = tostring(v or ""):lower():gsub("[^%w_-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
        if name == "" then return end
        push("mooi-" .. name, st.on)
        st.preset = "mooi-" .. name
        local known = false
        for _, t in ipairs(theirs) do if t.file == st.preset then known = true end end
        if not known then theirs[#theirs + 1] = { file = st.preset, label = name } end
        keep(); show()
        text.eq_save = ""
        say("SAVED · " .. string.upper(name))
    end)

    show()
    if st.on then apply() end
    return {}
end

return M
