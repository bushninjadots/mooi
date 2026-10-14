-- Tidal Shell logic: settings, the island's target window, and Hyprland actions.
-- It never draws and never decides what the user meant: the scene's rules do that.

local config = require("lib/config")
local hypr = require("lib/hypr")
local apps = require("lib/apps")

local FILE = "settings.json"
local KNOWN_GOOD = "settings.known-good.json"

local settings = config.defaults()
local target = nil      -- the window the island acts on (hypr.client shape)
local generation = 0    -- bumps on every open, so late replies for an old target are dropped

-- ── Settings ────────────────────────────────────────────────
local function apply(s)
    fact.show_clock = s.spine.clock
    fact.ws_max = s.spine.max_workspaces
    fact.confirm_close = s.island.confirm_close
end

local function load_settings()
    if sys.ask("env", "TIDAL_SAFE") == "1" then
        settings = config.defaults()
        fact.cfg_error = false
        log("settings · safe mode: built-in defaults, settings.json not read")
        apply(settings)
        return
    end
    local raw = sys.ask("files.read", FILE)
    local s, problems, notes, state = config.parse(raw, json.decode)
    for _, n in ipairs(notes) do log("settings · " .. n) end
    for _, p in ipairs(problems) do log("settings · problem · " .. p) end

    if state == "broken" then
        -- Fall back to the last file that loaded cleanly, if there is one.
        local good = sys.ask("files.read", KNOWN_GOOD)
        if good then
            local g, gp = config.parse(good, json.decode)
            if #gp == 0 then s = g; log("settings · using " .. KNOWN_GOOD) end
        end
    end
    if state == "missing" then
        sys.call("files.write", FILE, config.defaults())
        log("settings · wrote defaults to " .. sys.ask("files.folder") .. "/" .. FILE)
    end
    if state == "ok" then sys.call("files.write", KNOWN_GOOD, s) end

    settings = s
    fact.cfg_error = #problems > 0
    apply(settings)
end

load_settings()
sys.watch("files:" .. FILE, function() load_settings() end)

-- ── Reporting ───────────────────────────────────────────────
local function show_target(c)
    target = c
    fact.target_ok = c ~= nil
    if c then
        text.tgt_class = c.class ~= "" and c.class or "window"
        text.tgt_title = c.title ~= "" and c.title or "(untitled)"
        fact.floating = c.floating
        fact.fullscreen = c.fullscreen
        fact.pinned = c.pinned
        fact.ws_target = c.workspace
    end
end

local function report(ok, message)
    text.feedback = message
    fact.busy = false
    log((ok and "action · ok · " or "action · failed · ") .. message)
    emit(ok and "op_done" or "op_failed")
end

local function decode(out)
    local ok, t = pcall(json.decode, out or "")
    if ok then return t end
    return nil
end

-- ── The target: read when the island opens ──────────────────
local function capture()
    generation = generation + 1
    local mine = generation
    show_target(nil)
    text.tgt_class = ""
    text.tgt_title = "Reading window…"
    run("hyprctl", { "-j", "activewindow" }, function(out, code)
        if mine ~= generation then return end
        local c = code == 0 and hypr.client(decode(out)) or nil
        if c then
            show_target(c)
        else
            text.tgt_title = "No focused window"
            report(false, "Nothing to act on: no window has focus")
        end
    end)
end

on("fact:phase", function(p)
    if p == "compact" and not fact.target_ok and not fact.busy then capture() end
    if p == "hidden" then generation = generation + 1 end
end)

-- ── Actions ─────────────────────────────────────────────────
local function read_back(address, fn)
    run("hyprctl", { "-j", "clients" }, function(out, code)
        if code ~= 0 then fn(nil, false) return end
        fn(hypr.find(decode(out), address), true)
    end)
end

local function perform(action, opts)
    if not target then report(false, "No window selected") return end
    local address = target.address
    read_back(address, function(before, ok)
        if not ok then report(false, "Could not read windows from Hyprland") return end
        if not before then
            show_target(nil)
            fact.phase = "hidden"
            report(false, "That window is gone")
            return
        end
        local cmd, err = hypr.dispatch(action, address, opts)
        if not cmd then report(false, err) return end
        run("hyprctl", { "dispatch", cmd }, function(out, code)
            if code ~= 0 or not string.match(out or "", "^ok") then
                report(false, "Hyprland refused: " .. string.gsub(out or "", "%s+$", ""))
                return
            end
            local polls = action == "close" and hypr.CLOSE_POLLS or 1
            local function check(n)
                read_back(address, function(now, readable)
                    if not readable then report(false, "Could not read windows back") return end
                    local done, message = hypr.verify(action, before, now, opts)
                    if not done and n < polls then
                        after(hypr.CLOSE_POLL_MS, function() check(n + 1) end)
                        return
                    end
                    if now then show_target(now) end
                    report(done, message)
                    if done and (action == "close" or action == "move") then
                        show_target(nil)
                        fact.phase = "hidden"
                    elseif action == "move" then
                        fact.phase = "compact"
                    end
                end)
            end
            check(1)
        end)
    end)
end

on("act", function(i)
    local action = hypr.ACTIONS[(tonumber(i) or -1) + 1]
    if not action or action == "move" then report(false, "Unknown action") return end
    perform(action)
end)

on("send", function(n)
    perform("move", { workspace = tonumber(n), follow = settings.island.follow_on_send })
end)

-- ── Spine ───────────────────────────────────────────────────
-- The focused window's icon: Hyprland says its class, the .desktop files say the icon.
local app_index = nil
local focused_class = ""
local function show_icon()
    local icon = apps.icon_for(app_index, focused_class)
    text.win_icon = icon or ""
    text.win_letter = icon and "" or apps.letter(focused_class)
end
sys.watch("apps", function(list) app_index = apps.index(list); show_icon() end)
sys.watch("window", function(w) focused_class = w.class or ""; show_icon() end)

on("ws_pick", function(id)
    local n = tonumber(id)
    if n and n > 0 then sys.call("workspaces.focus", n) end
end)

log("tidal · logic ready · settings in " .. tostring(sys.ask("files.folder")))
