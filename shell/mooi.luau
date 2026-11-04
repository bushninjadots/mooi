-- mooi logic: settings, the island's target window, and Hyprland actions.
-- It never draws and never decides what the user meant: the scene's rules do that.

local config = require("lib/config")
local theme = require("lib/theme")
local appcolors = require("lib/appcolors")
local ferro = require("lib/ferro")
local barlayout = require("lib/barlayout")
local setters = require("lib/setters")
local style = require("lib/style")
local desktop = require("lib/desktop")
local atlas_geo = require("lib/atlas")
local hypr = require("lib/hypr")
local apps = require("lib/apps")
local spaces = require("lib/spaces")
local settingsfile = require("lib/settingsfile")
local search = require("lib/search")
local calc = require("lib/calc")
local filesearch = require("lib/filesearch")

local FILE = "settings.json"
local KNOWN_GOOD = "settings.known-good.json"

-- Safe mode (the tests run it) never writes the real settings file: a run that
-- toggles something must not become the user's settings.
local safe_mode = sys.ask("env", "MOOI_SAFE") == "1"
-- Run by the keeper (bin/mooi session), which also runs the theme watch.
local kept = (sys.ask("env", "MOOI_MODE") or "") ~= ""
-- settings.json as this program last read or wrote it: what a save diffs against, so only what
-- the bar changed is written over whatever another program wrote in the meantime (lib/settingsfile).
local settings_snapshot = nil

local settings = config.defaults()
local target = nil      -- the window the island acts on (hypr.client shape)
local generation = 0    -- bumps on every open, so late replies for an old target are dropped

-- ── Settings ────────────────────────────────────────────────
-- The bar's modules, each of which has `bar.modules.<name>.show` and `.frame` (lib/barlayout).
local MODULES = barlayout.ORDER
local bar = nil           -- the bar's layout and readers (shell/bar.luau), once it is running
local loom = nil          -- Signal Loom, the notifications (shell/signals.luau), once it is running
local outlines = {}       -- each module's outline as the layout reads it (0 line · 2 corners · 3 none)
local profile_set = nil   -- the power profile last asked for
local on_battery = false  -- running on the battery, not charging (the saver's "on battery")
local function saving()
    local v = settings and settings.motion and settings.motion.saver
    return v == "always" or (v == "battery" and on_battery)
end
local bar_palette = nil   -- the bar's palette as #rrggbb, for the desktop's border (paint_ferro)
local day = false         -- the palette is a light one (D91): glow is a light's effect, and by day it is a smudge
local sync_desktop        -- the desktop's look and mooi's keys; defined at the end, once it can run

-- Where a choice sits in its setting's list of values, from 0: how an enum setting reaches
-- the scene. An unknown value (cannot happen past validation) is the first.
local function position(path, value)
    for _, row in ipairs(config.SCHEMA) do
        if row.path == path then
            for i, v in ipairs(row.values) do if v == value then return i - 1 end end
        end
    end
    return 0
end

local function apply(s)
    -- A settings signal can arrive more than once for one write (the file service reports a
    -- move and a close, and a control's own write comes back through the watch). This is the
    -- scene's largest fact write, so only paint it when something it reads really changed;
    -- `day` and `on_battery` ride along because they re-light the same facts from outside.
    local sig = json.encode(s) .. "|" .. tostring(day) .. "|" .. tostring(on_battery)
    if sig == applied_sig then return end
    applied_sig = sig

    fact.max_results = s.command.max_results
    fact.show_clock = s.bar.modules.clock.show       -- the clock module's own switch
    fact.tray_style = position("tray.style", s.tray.style)
    fact.ws_max = s.spine.max_workspaces
    fact.confirm_close = s.island.confirm_close
    fact.previews = s.atlas.previews
    fact.ov_apps = s.atlas.search_apps                 -- the ported type-to-run (OVERVIEW-PORT)
    fact.ov_files = s.atlas.search_files               -- and its bounded file results
    fact.ov_wheel = s.atlas.wheel_desktops             -- and the wheel/← → desktop stepping
    fact.ov_edges = s.atlas.spring_edges               -- and the spring edges (D115)
    fact.hot_corner = position("atlas.hot_corner", s.atlas.hot_corner)   -- 0 off · 1–4 the corners
    fact.ov_dim, fact.ov_zoom = s.atlas.dim / 100, s.atlas.zoom   -- the Overview's look (D44)
    -- The Mechanism's own settings, which the bar reads straight from these facts.
    fact.bar_labels = s.bar.labels
    fact.bar_wheel = s.bar.wheel
    fact.theme_wallpaper = (s.theme.source == "wallpaper")
    -- The Ferrolume bar's switches (docs/FERROLUME.md). Choices go over as their position
    -- in the schema's list, which is what the scene's `pick`s and comparisons read.
    fact.ws_style = position("bar.workspaces", s.bar.workspaces)
    -- The outline as the scene's Frame draws it: 0 line, 2 corners, 3 none (1 is a raised plate,
    -- which is a material now, not an outline).
    local OUTLINE = { line = 0, corners = 2, none = 3 }
    local frame = OUTLINE[s.bar.frame] or 0
    fact.bar_frame = position("bar.frame", s.bar.frame)
    fact.bar_ground = position("bar.ground", s.bar.ground)
    fact.bar_rail = s.bar.rail
    fact.bar_accents = s.bar.accents
    fact.music_rim = s.music.rim
    fact.music_rim_gain = s.music.rim_gain / 100
    fact.music_rim_glow = s.music.rim_glow
    fact.bar_full = (s.bar.mode == "full")
    fact.bar_surface = position("bar.surface", s.bar.surface)
    fact.viz = position("bar.visualizer", s.bar.visualizer)
    fact.helix_frame = s.bar.helix_frame
    fact.media_mode = position("media.mode", s.media.mode)
    fact.media_idle = position("media.idle", s.media.idle)
    fact.frame_on = s.frame.on
    fact.ch_on = s.island.morph ~= false                          -- D153: islands grown out of the bar (with or without the frame)
    fact.frame_band = s.frame.band
    fact.frame_music = s.frame.music
    fact.frame_style = position("frame.style", s.frame.style)
    fact.frame_reach = s.frame.reach
    fact.frame_edges = position("frame.edges", s.frame.edges)
    fact.note_server = position("notifications.server", s.notifications.server)
    for _, m in ipairs(MODULES) do
        local mod = s.bar.modules[m]
        fact["m_" .. m] = mod.show
        fact["fi_" .. m] = position("bar.modules." .. m .. ".frame", mod.frame)
        -- `inherit` takes the bar's frame; the layout only ever sees a frame (shell/bar.luau
        -- reads it from here; the scene reads the workspaces' alone, for the helix's edges)
        outlines[m] = (mod.frame == "inherit") and frame or (OUTLINE[mod.frame] or 0)
    end
    fact.f_workspaces = outlines.workspaces
    fact.th_scheme = position("theme.scheme", s.theme.scheme)
    fact.th_index = s.theme.color_index
    fact.th_contrast = s.theme.contrast + 1
    fact.th_signal = position("theme.signal", s.theme.signal)
    for name, v in pairs(style.facts(s)) do fact[name] = v end
    fact.cn_kind, fact.cn_scale = style.corners(s)   -- corners on every plate (look.corners, look.corner_size)
    fact.isl_style = position("island.style", s.island.style)   -- 0 plate · 1 tether (ui/island.plm)
    fact.clock_view = position("clock.view", s.clock.view)      -- 0 full · 1 time · 2 seconds
    fact.th_mode = position("theme.mode", s.theme.mode)         -- 0 dark · 1 light · 2 auto (the display island)
    fact.pw_saver = position("motion.saver", s.motion.saver)    -- 0 off · 1 on battery · 2 always (the power island)
    fact.pw_prof = position("power.profile", s.power.profile)   -- 0 keep · 1 saver · 2 balanced · 3 performance
    -- The battery saver (motion.saver): what costs frames and a process goes quiet.
    fact.saving = saving()
    if fact.saving then fact.st_glow = 0; fact.st_aberr = 0; fact.frame_music = false; fact.viz = 4 end
    -- by day a dark shadow under a light island reads as a stain: it keeps a third of its weight
    if day then fact.st_glow = (tonumber(fact.st_glow) or 0) * 0.3; fact.st_sh_a = (tonumber(fact.st_sh_a) or 0) * 0.35 end
    -- The power profile (power.profile), through power-profiles-daemon when it runs; `keep`
    -- leaves the system's own.
    if s.power.profile ~= "keep" and s.power.profile ~= profile_set then
        profile_set = s.power.profile
        run("powerprofilesctl", { "set", s.power.profile }, function(_, code)
            if code ~= 0 then log("power · powerprofilesctl could not set " .. s.power.profile .. " (is power-profiles-daemon running?)") end
        end)
    end
    if bar then bar.relayout() end
    if loom then loom.apply() end
    if sync_desktop and bar_palette then sync_desktop() end
end

local function load_settings()
    if safe_mode then
        settings = config.defaults()
        fact.cfg_error = false
        log("settings · safe mode: built-in defaults, settings.json not read")
        apply(settings)
        return
    end
    local raw = sys.ask("files.read", FILE)
    -- The same file read again (a second watch callback, or `recolor` after a palette write)
    -- cannot change anything: parse and repaint only when the text differs.
    if type(raw) == "string" and raw == last_raw then return end
    last_raw = raw
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
    settings_snapshot = settingsfile.copy(s)
    fact.cfg_error = #problems > 0
    apply(settings)
end

-- ── Theme ──────────────────────────────────────────────────
-- The brief's colour pipeline, in one place (lib/theme decides; this only reads and
-- paints): fixed palette → the wallpaper's Matugen palette → the user's overrides →
-- completeness and contrast. A theme that does not pass is refused *whole* and the last
-- good one stays on screen; colour facts are the only things anything here writes, so a
-- palette change can never move a surface or change a spring.
local PALETTE = "palette.json"
local palette = nil     -- what theme/palette.json.hbs wrote (Matugen, dark scheme)
local applied_sig = nil -- the settings `apply` last painted, so one write paints once
local last_raw = nil    -- settings.json as last parsed
local painted_sig = nil -- the tokens `paint` last wrote
local ferro_sig = nil   -- the bar's roles `paint_ferro` last wrote


local function load_palette()
    local ok, t = pcall(sys.ask, "files.read", PALETTE, "json")
    palette = (ok and type(t) == "table") and t or nil
end


-- The scene paints each token from three facts: `rgb()` is the only way the logic can
-- hand over a colour that did not exist when the scene was read, so every token has its
-- three. Written out in full so a scene name and a logic name cannot drift apart quietly
-- (the scene compile catches either one going missing). The extended names in
-- theme/tokens.plm (`background`, `chassis`, …) are aliases of these, not facts of their own.
local function paint(colours)
    -- 42 facts, one per token channel: write them only when a colour actually moved. Pleamar
    -- re-reads the properties that read a fact when it changes, so repeating a palette's own
    -- values is the most expensive no-op in the scene.
    local keys = {}
    for k in pairs(colours) do keys[#keys + 1] = k end
    table.sort(keys)
    local sig = {}
    for _, k in ipairs(keys) do sig[#sig + 1] = k .. theme.to_hex(colours[k]) end
    sig = table.concat(sig, ";")
    if sig == painted_sig then return end
    painted_sig = sig

    -- Original brief tokens (backward compatible)
    local c = colours["bg.primary"]
    fact.c_bg_primary_r = c.r; fact.c_bg_primary_g = c.g; fact.c_bg_primary_b = c.b
    c = colours["bg.secondary"]
    fact.c_bg_secondary_r = c.r; fact.c_bg_secondary_g = c.g; fact.c_bg_secondary_b = c.b
    c = colours["surface.primary"]
    fact.c_surface_primary_r = c.r; fact.c_surface_primary_g = c.g; fact.c_surface_primary_b = c.b
    c = colours["surface.elevated"]
    fact.c_surface_elevated_r = c.r; fact.c_surface_elevated_g = c.g; fact.c_surface_elevated_b = c.b
    c = colours["border.subtle"]
    fact.c_border_subtle_r = c.r; fact.c_border_subtle_g = c.g; fact.c_border_subtle_b = c.b
    c = colours["fg.primary"]
    fact.c_fg_primary_r = c.r; fact.c_fg_primary_g = c.g; fact.c_fg_primary_b = c.b
    c = colours["fg.secondary"]
    fact.c_fg_secondary_r = c.r; fact.c_fg_secondary_g = c.g; fact.c_fg_secondary_b = c.b
    c = colours["fg.muted"]
    fact.c_fg_muted_r = c.r; fact.c_fg_muted_g = c.g; fact.c_fg_muted_b = c.b
    c = colours["accent.primary"]
    fact.c_accent_primary_r = c.r; fact.c_accent_primary_g = c.g; fact.c_accent_primary_b = c.b
    c = colours["accent.secondary"]
    fact.c_accent_secondary_r = c.r; fact.c_accent_secondary_g = c.g; fact.c_accent_secondary_b = c.b
    c = colours["status.ok"]
    fact.c_status_ok_r = c.r; fact.c_status_ok_g = c.g; fact.c_status_ok_b = c.b
    c = colours["status.error"]
    fact.c_status_error_r = c.r; fact.c_status_error_g = c.g; fact.c_status_error_b = c.b
    c = colours["focus.ring"]
    fact.c_focus_ring_r = c.r; fact.c_focus_ring_g = c.g; fact.c_focus_ring_b = c.b
    c = colours["selection.bg"]
    fact.c_selection_bg_r = c.r; fact.c_selection_bg_g = c.g; fact.c_selection_bg_b = c.b
end

-- The Ferrolume bar's own colours: nineteen roles, three facts each, from Ferrolume's
-- palette or derived from the wallpaper's (lib/ferro), Alert while the battery is critical.
-- The scene glides every role to its new value (one spring per channel), so a new
-- wallpaper, a new scheme and the Alert re-light all arrive as one 600 ms change.
local alert = false
local roles = nil            -- the palette as lib/ferro resolved it last: the bar's roles, and the tokens' source
local apps_said = nil        -- apps.json as last written (written again only when it changes)
local function paint_ferro(reason)
    local out, why = ferro.resolve(settings.theme.source, palette, settings.theme.signal, alert, ferro.options(settings))
    roles = out
    -- Your apps (apps.*): the palette in Matugen's role names, for `bin/mooi apps-sync` (the
    -- theme watch) to render into Kitty, GTK and Qt. Not the Alert re-light: that is the bar's.
    local mode = (type(palette) == "table" and palette.mode == "light") and "light" or "dark"
    fact.light = mode == "light"
    if day ~= fact.light then day = fact.light; apply(settings) end
    -- 57 more facts (nineteen roles, three channels each). A settings watch and the palette
    -- watch can both land for one theme-sync; only the first one has anything to paint.
    local fsig = {}
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fsig[#fsig + 1] = role .. ":" .. tostring(c.r) .. "," .. tostring(c.g) .. "," .. tostring(c.b)
    end
    fsig[#fsig + 1] = mode
    fsig[#fsig + 1] = tostring(alert)
    fsig = table.concat(fsig, ";")
    if fsig == ferro_sig then return end
    ferro_sig = fsig
    bar_palette = { phos = ferro.to_hex(out.phos), ember = ferro.to_hex(out.ember), trace = ferro.to_hex(out.trace) }
    if sync_desktop then sync_desktop() end
    if not alert then
        local doc = { kitty = settings.apps.kitty, gtk = settings.apps.gtk, qt = settings.apps.qt, mode = mode,
                      colors = appcolors.material(out, mode) }
        local said = json.encode(doc)
        if said ~= apps_said then apps_said = said; sys.call("files.write", "apps.json", doc) end
    end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"] = c.r; fact["fr_" .. role .. "_g"] = c.g; fact["fr_" .. role .. "_b"] = c.b
    end
    log("bar · colours · " .. why .. " · " .. reason)
end

-- One palette for the whole shell: the bar's roles (above), then the islands' tokens from them.
local function apply_theme(reason)
    paint_ferro(reason)
    local colours, notes, problems = theme.resolve(settings.theme, roles)
    for _, n in ipairs(notes) do log("theme · " .. n) end
    if #problems > 0 then
        fact.theme_error = true
        for _, p in ipairs(problems) do log("theme · problem · " .. p) end
        log("theme · refused the palette (" .. reason .. "); the last good one is showing")
        return false
    end
    -- Checked first, then written: all the tokens, or none.
    paint(colours)
    fact.theme_error = false
    log("theme · applied · " .. reason)
    return true
end

load_settings()

-- One write policy for settings.json (audit 2026-10-31, F3): read the file as it is now, lay
-- only what the bar (or a module it hosts) changed since the last read or write over it, write
-- that. The settings window, the Nexus, the player and the studio write the same file.
local function read_settings()
    local s, _, _, state = config.parse(sys.ask("files.read", FILE), json.decode)
    if state == "broken" then return nil end
    return s
end
local function save_settings()
    if safe_mode then return false end
    local doc, why = settingsfile.save(sys, FILE, settings_snapshot or settings, settings, read_settings)
    if not doc then log("settings · could not save: " .. tostring(why)); return false end
    settings_snapshot = settingsfile.copy(settings)
    return true
end

load_palette()
apply_theme("first read")
-- When the file changes (the settings window writes it), what Matugen is asked for may have
-- changed too: the palette is extracted again only then.
local extract   -- re-runs Matugen; defined with the bar's controls, below
local desk_sync -- starts or lets go of the desk (D85); defined with the programs, below
local bmo_sync  -- starts or lets go of BMO (companion.bmo); defined with the programs, below
local function extraction(t) return tostring(t.scheme) .. "/" .. tostring(t.color_index) .. "/" .. tostring(t.contrast) end
sys.watch("files:" .. FILE, function()
    local before = extraction(settings.theme)
    load_settings()
    if extraction(settings.theme) ~= before then extract() end
    apply_theme("settings changed")
    if widgets_sync then widgets_sync() end
    if desk_sync then desk_sync() end
    if bmo_sync then bmo_sync() end
    if notch_sync then notch_sync() end
    if frame_sync then frame_sync() end
    if notch_cut then notch_cut() end
end)
sys.watch("files:" .. PALETTE, function()
    load_palette(); apply_theme("a new palette arrived")
end)
on("recolor", function() load_palette(); apply_theme("asked to recolour") end)
-- Alert: a critical battery re-lights the whole bar (Ferrolume's Alert theme).
sys.watch("battery", function(b)
    local unplugged = type(b) == "table" and b.present == true and b.charging ~= true
    if unplugged ~= on_battery then
        on_battery = unplugged
        apply(settings); if bar then bar.relayout() end
    end
    local now = type(b) == "table" and b.present == true and (tonumber(b.percent) or 100) < 10 and b.charging ~= true
    if now ~= alert then alert = now; paint_ferro(now and "battery critical" or "battery recovered") end
end)

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

-- The window island closes only if it still holds the slot: the user may have
-- opened another island meanwhile, and that one is not ours to close.
local function close_window_island()
    if fact.open == "window" then fact.open = "none" end
end

on("fact:open", function(v)
    if v == "window" and not fact.target_ok and not fact.busy then capture() end
    if v ~= "window" then
        generation = generation + 1
        -- closed (not let go for a focus action, which comes back to the same window): the next
        -- opening reads the focused window again, never acts on the one before
        if not fact.busy then target = nil; fact.target_ok = false end
    end
end)

-- ── Actions ─────────────────────────────────────────────────
local function read_back(address, fn)
    run("hyprctl", { "-j", "clients" }, function(out, code)
        if code ~= 0 then fn(nil, false) return end
        fn(hypr.find(decode(out), address), true)
    end)
end

-- Giving a window the keyboard is what Hyprland will not do while our layer has it, and
-- a layer has it only while an island is up. So `focus` gives the slot up first —which is
-- what choosing a window means anyway—, waits the frame that hands the keyboard back, and
-- brings the island back with what happened if it did not happen.
-- (Not with an `on_demand` keyboard: its loan outlives the island by 300 ms.)
local HANDOVER_MS = 60

-- One verified window action: read the window, dispatch, read it back, compare.
-- `done(ok, now)` gets whether it happened and the window as it is now (nil: gone).
-- It always reports (feedback text, op_done / op_failed) and clears `busy`.
local function run_action(action, address, opts, done)
    done = done or function() end
    local held = fact.open                -- the island that asked, to come back to if it fails
    local function finish(happened, now)
        -- Only if that island had to let the slot go for this action: then it comes back
        -- with what happened, rather than leaving the user with nothing.
        if not happened and held ~= "none" and fact.open == "none" then fact.open = held end
        done(happened, now)
    end
    read_back(address, function(before, ok)
        if not ok then report(false, "Could not read windows from Hyprland"); finish(false, nil) return end
        if not before then report(false, "That window is gone"); finish(false, nil) return end
        local cmd, err = hypr.dispatch(action, address, opts)
        if not cmd then report(false, err); finish(false, before) return end
        local function dispatch()
            run("hyprctl", { "dispatch", cmd }, function(out, code)
                if code ~= 0 or not string.match(out or "", "^ok") then
                    report(false, "Hyprland refused: " .. string.gsub(out or "", "%s+$", ""))
                    finish(false, before)
                    return
                end
                local polls = action == "close" and hypr.CLOSE_POLLS or 1
                local function check(n)
                    read_back(address, function(now, readable)
                        if not readable then report(false, "Could not read windows back"); finish(false, nil) return end
                        local happened, message = hypr.verify(action, before, now, opts)
                        if not happened and n < polls then
                            after(hypr.CLOSE_POLL_MS, function() check(n + 1) end)
                            return
                        end
                        report(happened, message)
                        finish(happened, now)
                    end)
                end
                check(1)
            end)
        end
        if action == "focus" and held ~= "none" then
            fact.open = "none"            -- the layer lets the keyboard go with the slot
            after(HANDOVER_MS, dispatch)
        else
            dispatch()
        end
    end)
end

-- The window island's actions act on `target`, captured when it opened.
local function perform(action, opts)
    if not target then report(false, "No window selected") return end
    run_action(action, target.address, opts, function(done, now)
        if now then show_target(now) end
        if not now and not done then show_target(nil); close_window_island() return end
        if done and action == "move" then
            fact.flash_ws = opts.workspace   -- the Spine confirms where it went
            emit("moved")
        end
        if done and (action == "close" or action == "move") then
            show_target(nil)
            close_window_island()
        elseif action == "move" then
            fact.phase = "compact"
        end
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

-- ── System island ───────────────────────────────────────────
-- A dragged level asks for a new value every frame; the system is told at most
-- every 40 ms, always the latest. What the island shows is what the services
-- report back, so a refused change simply does not show.
local pending = {}
local flushing = false
local function flush()
    flushing = false
    if pending.vol then sys.call("audio.volume", pending.vol) end
    if pending.bri then sys.call("brightness.level", pending.bri) end
    pending = {}
end
local function request(kind, v)
    local n = tonumber(v)
    if not n then return end
    if n < 0 then n = 0 elseif n > 1 then n = 1 end
    if kind == "bri" and n < 0.01 then n = 0.01 end   -- never a black screen from a slider
    pending[kind] = n
    if not flushing then flushing = true; after(40, flush) end
end
on("vol", function(v) request("vol", v) end)
on("bri", function(v) request("bri", v) end)
on("mute", function() sys.call("audio.mute") end)

-- ── The media reading, and its transport ───────────────────
-- What the bar shows comes from the player itself (`media`): the state, the title and the
-- artist are its own. The one thing the scene cannot read for itself is whether there is a
-- player with anything on it at all — `title` is empty when nothing has played — and the
-- bar says so rather than offering a transport that would do nothing (D7: what is shown is
-- what the system reports, never what was asked for).
sys.watch("media", function(m)
    fact.media_on = (m ~= nil and type(m.title) == "string" and m.title ~= "")
end)
on("media_cmd", function(v)
    local n = tonumber(v) or 0
    if n < -0.5 then sys.call("media.previous")
    elseif n > 0.5 then sys.call("media.next")
    else sys.call("media.toggle") end
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
local app_list = {}
sys.watch("apps", function(list) app_list = list or {}; app_index = apps.index(list); show_icon() end)
sys.watch("window", function(w) focused_class = w.class or ""; show_icon() end)

local atlas_active = 0
local build_tiles          -- the board, built below; the workspace watch asks for it too
local ws_list = {}         -- the workspaces service's list as last told (each with its monitor)
local ws_rows = {}
-- The Overview's shape (D37, D38): how many workspaces it shows, and where, on monitor `m` (raw
-- from `hyprctl -j monitors`) — rows × columns, or one strip of the workspace map under the bar.
local STRIP_MAX = 12
local function ov_per()
    local a = settings.atlas
    if a.overview == "strip" then return math.min(math.max(#ws_rows, 1), STRIP_MAX) end
    return math.max(1, a.rows * a.columns)
end
local function ov_shape(m)
    local a = settings.atlas
    local sc = tonumber(m.scale) or 1
    local w, h = (tonumber(m.width) or 1920) / sc, (tonumber(m.height) or 1080) / sc
    if (tonumber(m.transform) or 0) % 2 == 1 then w, h = h, w end
    local strip = a.overview == "strip"
    local rows, cols = a.rows, a.columns
    if strip then rows, cols = 1, ov_per() end
    fact.ov_canvas = a.overview == "canvas"
    local g = strip and atlas_geo.strip(w, h, cols, tonumber(fact.st_res) or 0) or atlas_geo.grid(w, h, rows, cols, tonumber(fact.st_res) or 0, a.size / 100)
    fact.ov_strip, fact.ov_rows, fact.ov_cols = strip, rows, cols
    fact.ov_W, fact.ov_H, fact.ov_cw, fact.ov_ch, fact.ov_gx, fact.ov_gy, fact.ov_gap = w, h, g.cw, g.ch, g.gx, g.gy, g.gap
end
local monitors_seen = nil   -- the monitors the workspaces are on, last seen
-- The segments switcher opens to show each workspace's app: the icon of the window most recently
-- focused there (Hyprland's clients, the .desktop files' icons). Asked only for that switcher,
-- and one question at a time.
local icons_asked = false
local fill_icons
function fill_icons()
    if icons_asked then return end
    icons_asked = true
    run("hyprctl", { "-j", "clients" }, function(out, code)
        icons_asked = false
        local by_ws = {}
        if code == 0 then
            for _, w in ipairs(hypr.windows(decode(out))) do
                if by_ws[w.workspace] == nil then by_ws[w.workspace] = apps.icon_for(app_index, w.class) or "" end
            end
        end
        for _, r in ipairs(ws_rows) do r.icon = by_ws[r.id] or ""; r.iconed = r.icon ~= "" end
        model.spaces = ws_rows
    end)
end          -- the last map, for the names the Overview and the membrane ask about
sys.watch("workspaces", function(w)
    atlas_active = tonumber(w.active) or atlas_active
    ws_list = w.list or {}
    local count = #ws_rows
    ws_rows = spaces.rows(w.list or {}, atlas_active, fact.ws_max)
    model.spaces = ws_rows   -- the bar's switchers and the Overview, one map
    fact.ws_last = math.max(1, #ws_rows)
    -- The map grows past the setting to reach the focus (lib/spaces), so the switcher's width
    -- changes with it.
    if #ws_rows ~= count and bar then bar.relayout() end
    -- A monitor plugged in or out shows here first (its workspaces move): the bar is laid out
    -- again for the narrowest one there is now (shell/bar.luau measure).
    local names = {}
    for _, x in ipairs(w.list or {}) do if type(x.monitor) == "string" then names[x.monitor] = true end end
    local sig = {}
    for n in pairs(names) do sig[#sig + 1] = n end
    table.sort(sig)
    sig = table.concat(sig, ",")
    if sig ~= monitors_seen then monitors_seen = sig; if bar then bar.measure() end end
    -- How far the chain slides. An active workspace that is not on the chain at all (a
    -- special one) leaves it where it was rather than off the rail.
    local row = fact.active_row
    for _, r in ipairs(ws_rows) do if r.active then row = r.id - 1 end end
    -- A switch: every switcher's arrival ping (the scene's `arrive` layer).
    if row ~= fact.active_row then fact.active_row = row; emit("ws_arrived") end
    if settings.bar.workspaces == "segments" then fill_icons() end
    -- The Overview's active card follows the desktop it is on (the port's wheel and arrows step
    -- the desktops while it is open): a new board puts the large card on the new one.
    if atlas_up() then build_tiles() end
end)

-- ── The Overview's board: the windows Hyprland lists, with a picture where one is given ──
-- Hyprland's clients are the tiles: each brings its own address and workspace, so
-- every tile can be focused. `thumbnails` only lends the pictures —the ids it goes
-- by are the compositor's own, not Hyprland addresses— so a picture is matched to a
-- window by app and title, one window each.
local thumbs = {}
local thumbs_watching = false   -- the service answered and is watched
local pictures_asked = ""       -- what the compositor was asked to copy: "" none, "all", or the ids
local board = {}                -- the last tiles built, to open with something to show
local run_actions = {}          -- what each type-to-run row does: app, calc or file
local home = tostring(sys.ask("env", "HOME") or "")
local file_hits, file_query = {}, nil   -- the last file search, and the query it answered
local file_token = 0                    -- a newer query makes an older find's answer stale
local function short_path(p)
    local h = home ~= "" and (home .. "/") or ""
    if h ~= "" and string.sub(p, 1, #h) == h then return "~/" .. string.sub(p, #h + 1) end
    return p
end

local function atlas_tile(index)
    return model.atlas_tiles[(tonumber(index) or -1) + 1]
end

-- The Overview's hands (D39): the windows marked to go together (by address, so a rebuilt board
-- keeps them), the one the keyboard picked, and the last move, to take back.
local ov_marked = {}
-- What the name field is naming: the keyboard's workspace (nil), or a group — a new one starting
-- from workspace `id`, or group `gi` renamed (D42).
local naming_for = nil
local BURST_MS, SETTLE_MS = 450, 340   -- the Overview's picture bursts (below), and the wait for things to settle first
local ov_picked = nil
local last_moves = {}
fact.ov_search_h = atlas_geo.SEARCH_H   -- the search row the scene leaves room for
-- Workspace names and accents: mooi's own file, never a Hyprland rule (lib/atlas `identities`).
local SPACES_FILE = "workspaces.json"
local identities = atlas_geo.identities((function()
    local ok, t = pcall(sys.ask, "files.read", SPACES_FILE, "json")
    return ok and t or nil
end)())
local build_now
local ov_ids, ov_rects = {}, {}   -- the workspaces shown and each one's rectangle in the world (D47)
local fit_pending = false          -- the canvas opened: the next board sets the camera to show them all
-- The camera's ways in (D47): the one that fills the screen with workspace `k` (0-based) — how it
-- opens on the one you are on and dives into the one chosen — unless the strip or the zoom setting
-- says it stays put; and, on the canvas, the one that shows them all.
local function entry_cam(k)
    local r = ov_rects[k + 1]
    if not r or fact.ov_strip or not settings.atlas.zoom then
        fact.ov_qx, fact.ov_qy, fact.ov_qz = fact.ov_cx, fact.ov_cy, fact.ov_cz
        return
    end
    fact.ov_qx, fact.ov_qy, fact.ov_qz = atlas_geo.focus_cam(r, tonumber(fact.ov_W) or 1920)
end
-- The keyboard's workspace's rectangle, for the name field.
local function ov_sel_slot()
    local r = ov_rects[(tonumber(fact.ov_sel) or 0) + 1]
    fact.ov_nwx, fact.ov_nwy, fact.ov_nww = r and r.x or 0, r and r.y or 0, r and r.w or 0
end
on("fact:ov_sel", ov_sel_slot)   -- the scene's changes; the logic's own call ov_sel_slot() (a write here wakes no watcher)
local cells_plain = {}  -- the Overview's cells as last built, each with all it knows (the search and the menus read these)
local apply_search   -- the Overview's search, laid over each new board (below)
-- One board at a time: pictures arrive several times a second, and each used to start two
-- `hyprctl` calls of its own. Asked again while one is being read, it is read once more after; while a
-- window is carried it waits for the drop (a board replaced under the pointer jumps).
local building, build_again = false, false
-- workspaces.json, written whole (names, accents, groups, the canvas).
local function save_identities()
    if safe_mode then return end
    sys.call("files.write", SPACES_FILE, identities)
end
function build_tiles()
    if building or fact.bd_drag >= 0 then build_again = true return end
    building = true
    build_now(function()
        building = false
        if build_again and fact.bd_drag < 0 then build_again = false; build_tiles() end
    end)
end
on("fact:bd_drag", function(v) if (tonumber(v) or -1) < 0 and build_again and not building then build_again = false; build_tiles() end end)
function build_now(done)
    run("hyprctl", { "-j", "clients" }, function(out, code)
        local clients = code == 0 and hypr.windows(decode(out)) or {}
        local taken = {}
        local rows = {}
        for _, w in ipairs(clients) do
            local picture, stale = "", false
            -- Previews off, or a window privacy keeps to itself: no picture is matched, so none
            -- is drawn — and the service was never asked to copy it.
            local priv, shown = atlas_geo.private(settings.atlas.private, w.class, w.title)
            if fact.previews and not priv then
                for i, thumb in ipairs(thumbs) do
                    if not taken[i] and thumb.app == w.class and thumb.title == w.title then
                        taken[i] = true
                        picture = thumb.picture or ""
                        stale = thumb.stale == true
                        break
                    end
                end
            end
            rows[#rows + 1] = {
                ws = w.workspace,
                address = w.address,
                title = shown ~= "" and shown or w.class,
                app = w.class ~= "" and w.class or "window",
                picture = picture,
                stale = stale,
                priv = priv,
                mark = ov_marked[w.address] == true,
                floating = w.floating == true,
                icon = apps.icon_for(app_index, w.class) or "",
            }
            rows[#rows].iconed = rows[#rows].icon ~= ""
        end
        local function finish()
            board = rows
            -- the keyboard's pick follows its window, wherever the rebuilt board put it
            local picked, marks = -1, 0
            for i, r in ipairs(rows) do
                if r.address == ov_picked then picked = i - 1 end
                if r.mark then marks = marks + 1 end
            end
            if picked < 0 then ov_picked = nil end
            fact.ov_win, fact.ov_nmark = picked, marks
            -- Only while the Overview is up: a model nobody looks at is work for nothing, and
            -- the board is left as it is while it leaves, so the way out is whole.
            if atlas_up() then
                model.atlas_tiles = rows
                if fact.ov_searching then apply_search() end
            end
            if done then done() end
        end
        run("hyprctl", { "-j", "monitors" }, function(mout, mcode)
            local monitors = mcode == 0 and decode(mout) or {}
            -- The Overview (D37): a page of workspaces, rows × columns — the page the active one is
            -- on — each window placed in its workspace's cell by where it is on its monitor.
            for _, m in ipairs(monitors) do
                if m.focused then ov_shape(m) end
            end
            -- Which workspaces, and each one's rectangle in the world (D47): the grid's page in reading
            -- order, its cells on the screen; the canvas's every workspace on the map and every one placed
            -- on it, each a territory the size of the screen where it was put.
            local per = ov_per()
            local page = math.floor(math.max(0, atlas_active - 1) / per)
            local cells, ids, slots, rects = {}, {}, {}, {}
            if fact.ov_canvas then
                local seen = {}
                for id = 1, #ws_rows do seen[id] = true end
                for k in pairs(identities.canvas or {}) do seen[tonumber(k)] = true end
                for id in pairs(seen) do ids[#ids + 1] = id end
                table.sort(ids)
                while #ids > 18 do table.remove(ids) end
                page, per = 0, #ids
                rects = atlas_geo.territories(ids, identities.canvas, fact.ov_W, fact.ov_H, 5)
            else
                for k = 0, per - 1 do ids[k + 1] = page * per + k + 1 end
                local cols = math.max(fact.ov_cols, 1)
                for k = 1, #ids do
                    slots[k] = { sc = (k - 1) % cols, sr = math.floor((k - 1) / cols) }
                    rects[k] = { x = fact.ov_gx + slots[k].sc * (fact.ov_cw + fact.ov_gap), y = fact.ov_gy + slots[k].sr * (fact.ov_ch + fact.ov_gap), w = fact.ov_cw, h = fact.ov_ch }
                end
            end
            ov_ids, ov_rects = ids, rects
            if fact.ov_canvas then
                fact.ov_fx, fact.ov_fy, fact.ov_fz = atlas_geo.fit(rects, fact.ov_W, fact.ov_H, (tonumber(fact.st_res) or 0) + 70, 60)
                if fit_pending then fit_pending = false; fact.ov_cx, fact.ov_cy, fact.ov_cz = fact.ov_fx, fact.ov_fy, fact.ov_fz end
            else
                fact.ov_cx, fact.ov_cy, fact.ov_cz, fact.ov_fx, fact.ov_fy, fact.ov_fz = 0, 0, 1, 0, 0, 1
            end
            local marks = atlas_geo.group_marks(identities, ids, fact.ov_cols, (not fact.ov_canvas) and slots or nil)
            local where = atlas_geo.cell_monitors(ids, ws_list, monitors)
            fact.ov_multi = where.multi
            for k, id in ipairs(ids) do
                local r = ws_rows[id]
                local who = atlas_geo.identity(identities, id)
                local g = marks[k]
                cells[k] = { id = id, windows = r and r.windows or 0, active = id == atlas_active, exists = r and r.exists or false,
                             name = who.name, named = who.name ~= "", acc = atlas_geo.accent_index(who.accent),
                             group = g.gname, grp = g.grp, gacc = g.gacc, gname = string.upper(g.gname), gfirst = g.gfirst, glink = g.glink, hit = false,
                             mon = where[k].mon, monned = where[k].mon ~= "", elsewhere = where[k].elsewhere,
                             tx = rects[k].x, ty = rects[k].y, tw = rects[k].w, th = rects[k].h,
                             label = string.format("%02d", id) .. (who.name ~= "" and (" / " .. string.upper(who.name)) or ""),
                             sub = (r and r.windows or 0) == 1 and "1 WINDOW" or ((r and r.windows or 0) > 0 and ((r.windows) .. " WINDOWS") or "EMPTY") }
            end
            cells_plain = cells
            model.ov_cells = cells
            fact.ov_act = -1
            for k, id in ipairs(ids) do if id == atlas_active then fact.ov_act = k - 1 end end
            local act = rects[fact.ov_act + 1]
            fact.ov_awx, fact.ov_awy, fact.ov_aww, fact.ov_awh = act and act.x or 0, act and act.y or 0, act and act.w or 0, act and act.h or 0
            entry_cam(tonumber(fact.ov_zc) or 0)
            ov_sel_slot()
            local by_id = {}
            for _, m in ipairs(monitors) do by_id[tonumber(m.id) or -1] = m end
            for i, r in ipairs(rows) do
                local c = clients[i]
                local m = c and by_id[c.monitor]
                local k = -1
                for j, id in ipairs(ids) do if id == tonumber(r.ws) then k = j - 1 end end
                if m and k >= 0 then
                    local sc = tonumber(m.scale) or 1
                    local mw, mh = (tonumber(m.width) or 1920) / sc, (tonumber(m.height) or 1080) / sc
                    r.ocell = k
                    r.tx, r.ty, r.tw, r.th = rects[k + 1].x, rects[k + 1].y, rects[k + 1].w, rects[k + 1].h
                    r.mx, r.my, r.mw, r.mh = tonumber(m.x) or 0, tonumber(m.y) or 0, mw, mh   -- its monitor, for placing it (D45)
                    r.fx, r.fy = (c.x - (tonumber(m.x) or 0)) / mw, (c.y - (tonumber(m.y) or 0)) / mh
                    r.fw, r.fh = c.w / mw, c.h / mh
                else r.ocell, r.fx, r.fy, r.fw, r.fh = -1, 0, 0, 0, 0 end
            end
            finish()
        end)
    end)
end

-- The Overview: a window carried to another cell goes to that workspace (`n` = 100 · tile + cell);
-- a cell chosen is gone to (its id from the page the Overview shows).
-- What a move did, on the Overview's hint line for a few seconds.
local ov_says = 0
local function ov_say(ok, message)
    ov_says = ov_says + 1
    local mine = ov_says
    text.ov_msg, fact.ov_ok, fact.ov_said = message, ok, true
    after(3600, function() if mine == ov_says then fact.ov_said = false end end)
end
-- The scene lets go of a pick (an arrow, Escape): so does the logic.
on("fact:ov_win", function(v) if (tonumber(v) or -1) < 0 then ov_picked = nil end end)
-- The name field opens on the name the workspace (or the group) has.
on("fact:ov_naming", function(v)
    if v ~= true then naming_for = nil; return end   -- put away (Escape): it names nothing any more
    if naming_for then
        text.ov_name = naming_for.kind == "grename" and ((identities.groups[naming_for.gi] or {}).name or "") or ""
        return
    end
    local cell = cells_plain[fact.ov_sel + 1]
    text.ov_name = cell and atlas_geo.identity(identities, cell.id).name or ""
end)
-- Moves made one after another, each the window island's verified action (read back, never
-- taken on Hyprland's word). `done(made, failed)`: the moves that happened, and how many did not.
local function apply_moves(moves, done)
    fact.atlas_busy = true
    local made, failed = {}, 0
    local function step(k)
        local m = moves[k]
        if not m then fact.atlas_busy = false; done(made, failed) return end
        if not hypr.valid_address(m.address) then failed = failed + 1; step(k + 1) return end
        run_action("move", m.address, { workspace = m.to, follow = false }, function(ok)
            if ok then made[#made + 1] = m else failed = failed + 1 end
            step(k + 1)
        end)
    end
    step(1)
end
local function plural(n) return n == 1 and "1 window" or (n .. " windows") end
-- Carry, and say so: what moved is what can be undone; what failed says why (the action's own words).
local function carry(moves)
    if #moves == 0 then return end
    apply_moves(moves, function(made, failed)
        for _, m in ipairs(made) do ov_marked[m.address] = nil end
        if #made > 0 then
            last_moves = made
            fact.ov_undoable = true
            fact.flash_ws = made[#made].to
            emit("moved")
        end
        if failed > 0 then ov_say(false, string.format("%d of %d moved · %s", #made, #made + failed, text.feedback))
        else ov_say(true, string.format("%s to workspace %d · Ctrl+Z takes it back", plural(#made), made[#made].to)) end
        build_tiles()
        after(SETTLE_MS, picture_burst)
    end)
end
-- The Overview: a window carried to another cell goes to that workspace, and the marked ones with
-- it when it is one of them (`n` = 100 · tile + cell); a cell chosen is gone to (its id from the page
-- the Overview shows).
local function drop_on_cell(i, k)
    local cell = cells_plain[k + 1]
    if not cell then return end
    local moves = atlas_geo.carry(board, ov_marked, i, cell.id)
    -- Shown where it is going at once (each window glides from the pointer into the cell), then
    -- the verified move; one that fails is put back where Hyprland says it is by the rebuild.
    local going = {}
    for _, m in ipairs(moves) do going[m.address] = true end
    for _, r in ipairs(board) do if going[r.address] then r.ocell, r.sc, r.sr = k, cell.sc, cell.sr end end
    model.atlas_tiles = board
    carry(moves)
end
-- A window let go in its own workspace (D45): `px`, `py` the pointer as a share of the cell. A
-- floating one goes where it was let go, a tiled one dropped on another swaps with it — each the
-- verified action, shown there at once (lib/atlas `rearrange`).
local function rearrange(i, px, py)
    local item = board[i + 1]
    if not item or not hypr.valid_address(item.address) then return end
    local cw, ch = tonumber(fact.ov_cw) or 1, tonumber(fact.ov_ch) or 1
    local r = atlas_geo.rearrange(board, i, px, py, (tonumber(fact.bd_ox) or 0) / cw, (tonumber(fact.bd_oy) or 0) / ch)
    if r.kind == "none" then
        if r.target then ov_say(false, "A tiled window does not swap with a floating one") end
        return
    end
    local cmd, opts = nil, {}
    if r.kind == "place" then
        item.fx, item.fy = r.fx, r.fy
        cmd, opts = "place", { x = (item.mx or 0) + r.fx * (item.mw or 1920), y = (item.my or 0) + r.fy * (item.mh or 1080) }
    else
        for _, t in ipairs(board) do
            if t.address == r.target then
                item.fx, t.fx = t.fx, item.fx; item.fy, t.fy = t.fy, item.fy
                item.fw, t.fw = t.fw, item.fw; item.fh, t.fh = t.fh, item.fh
            end
        end
        cmd, opts = "swap_with", { target = r.target }
    end
    model.atlas_tiles = board
    fact.atlas_busy = true
    run_action(cmd, item.address, opts, function(ok)
        fact.atlas_busy = false
        ov_say(ok, ok and (cmd == "place" and ("Placed " .. item.app) or "Swapped") or text.feedback)
        build_tiles()
    end)
end
-- A point on the screen, in the world: where the camera puts it (D47).
local function to_world(x, y)
    local z = tonumber(fact.ov_cz) or 1
    return x / z + (tonumber(fact.ov_cx) or 0), y / z + (tonumber(fact.ov_cy) or 0)
end
-- Where something was let go: the scene sets it beside the event (packed into one number it lost its
-- last digits — the scene counts in 32-bit floats).
local function dropped_at() return tonumber(fact.ov_px) or 0, tonumber(fact.ov_py) or 0 end
-- Window `i` let go: on another workspace it goes there (the marked ones with it); on its own it is
-- placed or swapped; elsewhere, nothing.
on("ov_drop_xy", function(v)
    local i = math.floor(tonumber(v) or -1)
    local x, y = dropped_at()
    local item = board[i + 1]
    local landed = edge_land    -- the desktop the spring edges stepped to, taken by this drop
    edge_land = nil
    local wx, wy = to_world(x, y)
    local k = atlas_geo.at_world(ov_rects, wx, wy)
    if not item then return end
    if not k then
        -- Held in an edge: the window goes to the desktop the stepping reached, even though the
        -- pointer was over no cell when it was let go (lib/atlas `spring_target`).
        local to = atlas_geo.spring_target(landed, k)
        if to then carry(atlas_geo.carry(board, ov_marked, i, to)); return end
        -- A window let go past the strip's last cell makes the next desktop there and goes to it
        -- (Hyprdrive's "drop on an empty cell"): moving the window is what creates the workspace.
        if fact.ov_strip and not fact.ov_canvas then
            local top = 0
            for _, id in ipairs(ov_ids) do top = math.max(top, tonumber(id) or 0) end
            if top >= 99 then ov_say(false, "Ninety-nine desktops is every Hyprland has"); return end
            carry(atlas_geo.carry(board, ov_marked, i, top + 1))
        end
        return
    end
    k = k - 1
    local r = ov_rects[k + 1]
    if k == item.ocell then rearrange(i, (wx - r.x) / r.w, (wy - r.y) / r.h)
    else drop_on_cell(i, k) end
end)
-- The canvas (D47): territory `k` set down with its corner where it was let go: kept there, to 40
-- px of the world.
local SNAP = 40
on("ov_place", function(v)
    local k = math.floor(tonumber(v) or -1)
    local x, y = dropped_at()
    local cell = cells_plain[k + 1]
    if not fact.ov_canvas or not cell then return end
    local wx, wy = to_world(x, y)
    identities = atlas_geo.canvas_place(identities, cell.id, atlas_geo.snap(wx, SNAP), atlas_geo.snap(wy, SNAP))
    save_identities()
    build_tiles()
end)
-- A double press on the open canvas: a new workspace there — the next number after every one shown —
-- kept on the canvas; Hyprland makes it when it is first gone to.
on("ov_create", function(v)
    if not fact.ov_canvas then return end
    local wx, wy = to_world(dropped_at())
    local top = 0
    for _, id in ipairs(ov_ids) do top = math.max(top, id) end
    local id = top + 1
    if id > 99 or #ov_ids >= 18 then ov_say(false, "Eighteen workspaces is the most the canvas holds"); return end
    local W, H = tonumber(fact.ov_W) or 1920, tonumber(fact.ov_H) or 1080
    identities = atlas_geo.canvas_place(identities, id, atlas_geo.snap(wx - W / 2, SNAP), atlas_geo.snap(wy - H / 2, SNAP))
    save_identities()
    ov_say(true, string.format("Workspace %d made here · double-click it to open it", id))
    build_tiles()
end)
-- The canvas's camera back to the workspace you are on, as near as it is.
local function centre_on(k)
    local r = ov_rects[k + 1]
    if not r then return end
    local z = tonumber(fact.ov_cz) or 1
    local top = (tonumber(fact.st_res) or 0) + 70
    fact.ov_cx = r.x + r.w / 2 - (tonumber(fact.ov_W) or 1920) / 2 / z
    fact.ov_cy = r.y + r.h / 2 - (top + ((tonumber(fact.ov_H) or 1080) - top) / 2) / z
end
on("ov_here", function() centre_on(math.max(tonumber(fact.ov_act) or 0, 0)) end)
-- ↑ ↓: the nearest workspace above or below (on the canvas as on the grid).
on("ov_nav", function(v)
    local k = atlas_geo.near(ov_rects, tonumber(fact.ov_sel) or 0, tonumber(v) == -1 and "up" or "down")
    if not k then return end
    fact.ov_sel, fact.ov_win = k, -1; ov_sel_slot()
    -- on the canvas, one out of view is brought into it
    if fact.ov_canvas then
        local r, z = ov_rects[k + 1], tonumber(fact.ov_cz) or 1
        local sx, sy = (r.x - fact.ov_cx) * z, (r.y - fact.ov_cy) * z
        if sx < 0 or sy < 0 or sx + r.w * z > fact.ov_W or sy + r.h * z > fact.ov_H then centre_on(k) end
    end
end)
-- The workspace the camera dives into as the Overview closes (a press, Enter, a window chosen).
on("fact:ov_zc", function(v) entry_cam(tonumber(v) or 0) end)
-- Middle-click closes a window, as in iNiR: the window island's verified close (the app may ask
-- to save first; the board follows what Hyprland then says).
local function close_tile(v)
    local item = board[math.floor(tonumber(v) or -1) + 1]
    if not item or not hypr.valid_address(item.address) then return end
    fact.atlas_busy = true
    run_action("close", item.address, {}, function(ok)
        fact.atlas_busy = false
        ov_say(ok, ok and string.format("Closed %s", item.app) or text.feedback)
        build_tiles()
    end)
end
on("ov_close", close_tile)
-- The canvas's action strip under a selected window: focus it, float or tile it, fullscreen, close
-- (asked twice in the strip) — each the verified action.
on("ov_wact", function(v)
    local n = math.floor(tonumber(v) or -1)
    local i, a = math.floor(n / 10), n % 10
    local item = board[i + 1]
    if not item or not hypr.valid_address(item.address) then return end
    if a == 0 then
        fact.ov_zc = item.ocell; entry_cam(item.ocell)
        fact.open = "none"
        run_action("focus", item.address, {}, function() end)
    elseif a == 1 or a == 2 then
        fact.atlas_busy = true
        run_action(a == 1 and "float" or "fullscreen", item.address, {}, function(ok)
            fact.atlas_busy = false
            ov_say(ok, text.feedback)
            build_tiles()
        end)
    elseif a == 3 then
        fact.ov_win = -1
        close_tile(i)
    end
end)
-- Alt+↑ ↓: the next (or previous) window in the keyboard's cell (Enter then focuses it).
on("ov_pick", function(v)
    local i = atlas_geo.next_window(board, fact.ov_sel, fact.ov_win, tonumber(v) == -1 and -1 or 1)
    fact.ov_win = i
    ov_picked = i >= 0 and board[i + 1].address or nil
    if i < 0 then ov_say(false, "No windows on this workspace") end
end)
-- Ctrl+M, or Mark in its menu: a window marked, or unmarked, to go with the next carry.
local function toggle_mark(v)
    local item = board[math.floor(tonumber(v) or -1) + 1]
    if not item then return end
    ov_marked[item.address] = not ov_marked[item.address] or nil
    item.mark = ov_marked[item.address] == true
    local n = 0
    for _ in pairs(ov_marked) do n = n + 1 end
    fact.ov_nmark = n
    model.atlas_tiles = board
end
on("ov_mark", toggle_mark)
-- Escape with marks out clears them before it closes anything.
on("ov_unmark", function()
    ov_marked = {}
    for _, r in ipairs(board) do r.mark = false end
    fact.ov_nmark = 0
    model.atlas_tiles = board
end)
-- Ctrl+Z: the last move taken back, for the windows still where it put them (lib/atlas `undo`).
on("ov_undo", function()
    if #last_moves == 0 then ov_say(false, "Nothing to take back"); return end
    local moves = last_moves
    last_moves = {}
    fact.ov_undoable = false
    run("hyprctl", { "-j", "clients" }, function(out, code)
        if code ~= 0 then ov_say(false, "Could not read windows from Hyprland"); return end
        local back, skipped = atlas_geo.undo(moves, hypr.windows(decode(out)))
        if #back == 0 then ov_say(false, "Those windows have moved on or closed: nothing taken back"); return end
        apply_moves(back, function(made, failed)
            if #made > 0 then fact.flash_ws = made[1].to; emit("moved") end
            local left = skipped + failed
            ov_say(failed == 0, string.format("%s put back%s", plural(#made), left > 0 and string.format(" · %d could not be", left) or ""))
            build_tiles()
        end)
    end)
end)
-- F2 (or the menu) names the keyboard's cell, the menu gives it the next accent.
on("ov_rename", function()
    local cell = cells_plain[fact.ov_sel + 1]
    local what = naming_for
    naming_for = nil
    fact.ov_naming, fact.ov_naming_group = false, false
    if not cell then return end
    if what then
        local name = text.ov_name or ""
        if what.kind == "gnew" then
            identities = atlas_geo.group_new(identities, what.id, name)
            local gi, g = atlas_geo.group_of(identities, what.id)
            ov_say(true, string.format("Workspace %d is in %s · its menu adds the others", what.id, g and g.name or "a new group"))
        else
            identities = atlas_geo.group_rename(identities, what.gi, name)
            ov_say(true, "The group is " .. ((identities.groups[what.gi] or {}).name or name))
        end
        save_identities()
        build_tiles()
        return
    end
    identities = atlas_geo.name(identities, cell.id, text.ov_name or "")
    save_identities()
    local name = atlas_geo.identity(identities, cell.id).name
    ov_say(true, name ~= "" and string.format("Workspace %d is %s", cell.id, name) or string.format("Workspace %d has no name", cell.id))
    build_tiles()
end)
local function next_accent(cell)
    identities = atlas_geo.next_accent(identities, cell.id)
    save_identities()
    build_tiles()
end

-- ── The Overview's search (D41): typing in its row lights what matches and dims the rest; the
-- keyboard's cell and pick go to the first found, so Enter goes there (lib/atlas `search`).
function apply_search()
    local r = atlas_geo.search(board, cells_plain, text.ov_q)
    for i, t in ipairs(board) do t.hit = r.tiles[i] end
    for k, c in ipairs(cells_plain) do c.hit = r.cells[k] or false end
    fact.ov_searching, fact.ov_nfound = r.active, r.count
    -- The ported list under the row (OVERVIEW-PORT stage 2): a sum worked out as it is typed,
    -- installed apps, and files from the folders you keep. Board matches always win Enter; the
    -- list only speaks when nothing on the board does.
    local runs, actions = {}, {}
    local function add(row, act)
        if #runs >= 6 then return end
        runs[#runs + 1] = row
        actions[#actions + 1] = act
    end
    if r.active and r.count == 0 then
        local q = tostring(text.ov_q or "")
        local value = calc.eval(q)
        if value ~= nil then
            local shown = calc.format(value)
            add({ title = "= " .. shown, sub = "RESULT · ENTER COPIES", icon = "", iconed = false, letter = "=" },
                { kind = "calc", value = shown })
        end
        if fact.ov_apps then
            local items = {}
            for _, a in ipairs(app_list or {}) do
                if a.exec and a.exec ~= "" then
                    items[#items + 1] = {
                        title = a.name or a.id or "?", alt = { a.local_name, a.id, a.wmclass,
                            string.match(tostring(a.exec), "^%s*(%S+)") },
                        key = "app:" .. tostring(a.id or a.name), exec = a.exec, icon = a.icon,
                    }
                end
            end
            for _, it in ipairs(search.rank(items, q, nil, 6)) do
                local icon = it.icon or ""
                add({ title = it.title, sub = "APPLICATION", icon = icon, iconed = icon ~= "",
                      letter = icon == "" and apps.letter(it.title) or "" },
                    { kind = "app", value = it.exec })
            end
        end
        if fact.ov_files and file_query == q then
            for _, f in ipairs(file_hits) do
                add({ title = f.name, sub = "FILE · " .. short_path(f.path), icon = "", iconed = false, letter = "f" },
                    { kind = "file", value = f.path })
            end
        end
    end
    if fact.ov_appsel >= #runs then fact.ov_appsel = 0 end
    model.ov_runs = runs
    run_actions = actions
    if r.active then
        if r.count == 0 then
            text.ov_found = #runs > 0 and (#runs == 1 and "1 RESULT · ENTER USES IT" or (#runs .. " RESULTS · ENTER USES THE FIRST")) or "NOTHING FOUND"
        elseif r.first_tile >= 0 then
            text.ov_found = r.count == 1 and "1 WINDOW · ENTER FOCUSES" or (r.count .. " WINDOWS · ENTER FOCUSES THE FIRST")
        else
            text.ov_found = "ENTER GOES THERE"
        end
        if r.first_cell >= 0 then fact.ov_sel = r.first_cell; ov_sel_slot() end
        fact.ov_win = r.first_tile
        ov_picked = r.first_tile >= 0 and board[r.first_tile + 1].address or nil
    end
    model.ov_cells = cells_plain
    model.atlas_tiles = board
end
-- A bounded file search, a beat after typing stops: only while the Overview is up, the setting
-- is on, and nothing on the board matched. A newer query makes an older find's answer stale.
local function schedule_files(q)
    file_token = file_token + 1
    local mine = file_token
    file_hits, file_query = {}, nil
    if not (fact.open == "overview" and fact.ov_files and #q >= 2) then return end
    after(240, function()
        if mine ~= file_token or fact.open ~= "overview" then return end
        run("find", filesearch.args(home, q), function(out)
            if mine ~= file_token or fact.open ~= "overview" then return end
            file_hits, file_query = filesearch.parse(out, filesearch.LIMIT), q
            apply_search()
        end)
    end)
end
on("text:ov_q", function()
    if fact.open == "overview" then
        fact.ov_appsel = 0
        schedule_files(tostring(text.ov_q or ""))
        apply_search()
    end
end)
-- Enter uses the row under the keys: an app starts, a sum is copied, a file opens in its own
-- program. Apps go only through `apps.launch`, which accepts an application the service listed.
on("ov_run", function(v)
    local i = math.floor(tonumber(v) or -1)
    local act = run_actions[i + 1]
    local row = model.ov_runs[i + 1]
    if not act then return end
    if act.kind == "app" then
        if act.value == "" then return end
        sys.call("apps.launch", act.value)
        ov_say(true, "Opening " .. ((row and row.title) or "the app"))
        fact.open = "none"
    elseif act.kind == "calc" then
        run("wl-copy", {}, nil, { input = act.value, output = false })
        ov_say(true, "Copied " .. act.value)
    elseif act.kind == "file" then
        run("xdg-open", { act.value }, function(_, code)
            if code ~= 0 then ov_say(false, "Nothing opens that file") end
        end)
        fact.open = "none"
    end
end)
-- The wheel, ← → and the spring edges walk the existing desktops, round the ends, keeping the
-- Overview open on the one they reach. `from` is where the walk stands: the edges pass the desktop
-- they last stepped to, because the compositor has not reported it back yet while a window is
-- carried. Returns the id it went to, or nil when it could not move.
local function step_desktop(dir, from)
    local ids = {}
    for _, row in ipairs(ws_rows) do ids[#ids + 1] = row.id end
    local now = tonumber(from) or atlas_active
    local id = atlas_geo.step(ids, now, tonumber(dir) or 1)
    if not id or id == now then return nil end
    for k, shown in ipairs(ov_ids) do if shown == id then fact.ov_sel = k - 1; ov_sel_slot() end end
    sys.call("workspaces.focus", id)
    return id
end
on("ov_step", function(v) step_desktop(v) end)
-- Spring edges (D115, Hyprdrive's drag:spring_edges): a carried window pushed into the left or
-- right edge of the screen and held steps to the previous or next desktop, and keeps stepping while
-- it is held. Let go away from the board, it goes to the desktop the stepping reached
-- (`lib/atlas.spring_target`). The scene writes `ov_edging` from the pointer while it carries one;
-- leaving the edge, or letting go, is 0 and cancels the rest.
local edge_seq, edge_land, edge_was = 0, nil, 0
-- On the canvas the edges do not step desktops — there is no next one to step to — they pan the
-- camera toward the edge (D116), up and down as well as sideways, at the same speed on the screen
-- at any zoom (Hyprdrive's "push against the screen's edge while dragging to pan the canvas";
-- `lib/atlas.pan_by`). One loop, started when an edge is held, stopped by itself once none is.
local pan_on = false
local function canvas_pan_tick()
    if fact.open ~= "overview" or not fact.ov_canvas or not fact.ov_edges then pan_on = false; return end
    local dx, dy = tonumber(fact.ov_edging) or 0, tonumber(fact.ov_edgey) or 0
    if dx == 0 and dy == 0 then pan_on = false; return end
    local wx, wy = atlas_geo.pan_by(dx, dy, tonumber(fact.ov_cz) or 1)
    fact.ov_cx = (tonumber(fact.ov_cx) or 0) + wx
    fact.ov_cy = (tonumber(fact.ov_cy) or 0) + wy
    -- The camera takes the new corner at once, as a field drag does: a drop reads the world through
    -- this corner, and a camera still gliding in would put it a territory off.
    emit("ov_pan")
    after(atlas_geo.EDGE_PAN_TICK, canvas_pan_tick)
end
local function canvas_pan_start()
    if pan_on or fact.open ~= "overview" or not fact.ov_canvas then return end
    pan_on = true
    canvas_pan_tick()
end
local function edge_tick(mine, dir)
    if mine ~= edge_seq then return end
    if fact.open ~= "overview" or not fact.ov_edges or tonumber(fact.bd_drag) < 0 then return end
    local id = step_desktop(dir, edge_land or atlas_active)
    if not id then return end
    edge_land = id
    text.ov_edget = "WORKSPACE " .. id
    after(atlas_geo.EDGE_REPEAT, function() edge_tick(mine, dir) end)
end
on("fact:ov_edging", function(v)
    local dir = tonumber(v) or 0
    if dir == edge_was then return end   -- the same value written again is not a move
    edge_was = dir
    edge_seq = edge_seq + 1
    if fact.ov_canvas then                               -- the canvas pans instead of stepping
        if dir ~= 0 or (tonumber(fact.ov_edgey) or 0) ~= 0 then canvas_pan_start() end
        return
    end
    if dir == 0 then return end
    if fact.open ~= "overview" or not fact.ov_edges or tonumber(fact.bd_drag) < 0 then return end
    local mine = edge_seq
    after(atlas_geo.EDGE_REST, function() edge_tick(mine, dir) end)
end)
on("fact:ov_edgey", function() canvas_pan_start() end)
-- The hot corner (OVERVIEW-PORT stage 3): the pointer resting in the chosen corner for the set
-- time opens the Overview. Leaving cancels; an open panel or the Overview itself is left alone.
local hc_seq = 0
on("hc_enter", function()
    hc_seq = hc_seq + 1
    local mine = hc_seq
    if settings.atlas.hot_corner == "off" or fact.open ~= "none" then return end
    local wait = tonumber(settings.atlas.hot_corner_delay) or 600
    after(wait, function()
        if mine ~= hc_seq then return end
        if settings.atlas.hot_corner == "off" or fact.open ~= "none" then return end
        emit("open_overview")
    end)
end)
on("hc_leave", function() hc_seq = hc_seq + 1 end)
on("ov_clear", function() text.ov_q = ""; fact.ov_win = -1; apply_search() end)

-- ── A workspace's menu (D41): only what can be done there (lib/atlas `menu`). "Move here" brings
-- the marked windows, or the picked one; closing its windows asks twice.
local menu_items, menu_cell, menu_armed, menu_tile = {}, nil, nil, -1
-- What "Move here" would carry to `cell`: the marked windows, or the picked one — less any already there.
local function held_moves(cell)
    local from = fact.ov_win
    if next(ov_marked) then
        for i, r in ipairs(board) do if ov_marked[r.address] then from = i - 1; break end end
    end
    if from < 0 then return {} end
    return atlas_geo.carry(board, ov_marked, from, cell.id)
end
local function show_menu()
    local rows = {}
    for i, it in ipairs(menu_items) do
        local label = it.label
        if menu_armed == it.kind then
            label = it.kind == "close" and "Again to close them · Esc keeps them" or it.kind == "gremove" and "Again to take it away · Esc keeps it"
                    or "Again to close it · Esc keeps it"
        end
        rows[i] = { label = label, danger = it.danger }
    end
    model.ov_menu = rows
end
-- A workspace's menu, from its cell (`k`), or from window `tile` in it (that window picked, its rows first).
local function open_menu(k, tile)
    local cell = cells_plain[k + 1]
    if not cell then return end
    local item = tile >= 0 and board[tile + 1] or nil
    menu_cell, menu_armed, menu_tile = cell, nil, item and tile or -1
    menu_items = atlas_geo.menu(cell, #held_moves(cell), item and { app = item.app, marked = ov_marked[item.address] == true } or nil)
    if fact.ov_canvas and next(identities.canvas or {}) then
        table.insert(menu_items, #menu_items + 1, { kind = "tidy", label = "Put every workspace back in order", danger = false })
    end
    fact.ov_mwx, fact.ov_mwy, fact.ov_mww = cell.tx or 0, cell.ty or 0, cell.tw or 0   -- beside its workspace (D47)
    text.ov_mtitle = cell.named and string.format("WORKSPACE %d · %s", cell.id, string.upper(cell.name)) or ("WORKSPACE " .. cell.id)
    show_menu()
    fact.ov_msel, fact.ov_mopen = 0, k
end
on("ov_menu_open", function(v) open_menu(math.floor(tonumber(v) or -1), -1) end)
on("ov_menu_win", function(v)
    local item = board[math.floor(tonumber(v) or -1) + 1]
    if not item or (item.ocell or -1) < 0 then return end
    fact.ov_sel, fact.ov_win = item.ocell, math.floor(tonumber(v))
    ov_sel_slot()
    ov_picked = item.address
    open_menu(item.ocell, fact.ov_win)
end)
on("ov_menu_do", function(v)
    local it = menu_items[math.floor(tonumber(v) or -1) + 1]
    local cell, k = menu_cell, fact.ov_mopen
    if not it or not cell or k < 0 then return end
    if (it.kind == "close" or it.kind == "close_win" or it.kind == "gremove") and menu_armed ~= it.kind then menu_armed = it.kind; show_menu(); return end
    -- the group page (D42), in the same housing
    if it.kind == "group" or it.kind == "back" then
        menu_armed = nil
        menu_items = it.kind == "group" and atlas_geo.group_menu(identities, cell.id)
                     or atlas_geo.menu(cell, #held_moves(cell), menu_tile >= 0 and board[menu_tile + 1] and { app = board[menu_tile + 1].app, marked = ov_marked[board[menu_tile + 1].address] == true } or nil)
        text.ov_mtitle = it.kind == "group" and ("WORKSPACE " .. cell.id .. " · GROUP") or ("WORKSPACE " .. cell.id)
        fact.ov_msel = 0
        show_menu()
        return
    end
    fact.ov_mopen = -1
    if it.kind == "gjoin" then
        identities = atlas_geo.group_join(identities, it.group, cell.id)
        save_identities(); build_tiles()
        ov_say(true, string.format("Workspace %d joined %s", cell.id, identities.groups[it.group] and identities.groups[it.group].name or "the group"))
        return
    elseif it.kind == "gnew" or it.kind == "grename" then
        naming_for = { kind = it.kind, id = cell.id, gi = it.group }
        fact.ov_sel = k
        ov_sel_slot()
        fact.ov_naming, fact.ov_naming_group = true, true
        emit("ov_focus_name")
        return
    elseif it.kind == "gleave" or it.kind == "gaccent" or it.kind == "gremove" then
        local name = (identities.groups[it.group] or {}).name or "the group"
        if it.kind == "gleave" then identities = atlas_geo.group_leave(identities, cell.id)
        elseif it.kind == "gaccent" then identities = atlas_geo.group_next_accent(identities, it.group)
        else identities = atlas_geo.group_remove(identities, it.group) end
        save_identities(); build_tiles()
        if it.kind == "gleave" then ov_say(true, string.format("Workspace %d left %s", cell.id, name))
        elseif it.kind == "gremove" then ov_say(true, name .. " taken away · its workspaces and windows stay as they are") end
        return
    end
    if it.kind == "tidy" then
        identities = atlas_geo.canvas_reset(identities)
        save_identities(); build_tiles()
        ov_say(true, "Every workspace back in order")
        return
    end
    if it.kind == "mark" then
        toggle_mark(menu_tile)
    elseif it.kind == "close_win" then
        close_tile(menu_tile)
    elseif it.kind == "go" then
        fact.ov_zc = k
        sys.call("workspaces.focus", cell.id)
        fact.open = "none"
    elseif it.kind == "bring" then
        carry(held_moves(cell))
    elseif it.kind == "rename" then
        fact.ov_sel = k
        ov_sel_slot()
        fact.ov_naming = true
        emit("ov_focus_name")
    elseif it.kind == "accent" then
        next_accent(cell)
    elseif it.kind == "close" then
        -- each window's own verified close, one after another (an app may ask to save first)
        local list = {}
        for _, r in ipairs(board) do if tonumber(r.ws) == cell.id then list[#list + 1] = r end end
        fact.atlas_busy = true
        local closed = 0
        local function step(n)
            local r = list[n]
            if not r then
                fact.atlas_busy = false
                ov_say(closed == #list, string.format("Closed %d of %d on workspace %d", closed, #list, cell.id))
                build_tiles()
                return
            end
            run_action("close", r.address, {}, function(ok) if ok then closed = closed + 1 end; step(n + 1) end)
        end
        step(1)
    end
end)
on("ov_go", function(v)
    local k = math.floor(tonumber(v) or -1)
    local cell = cells_plain[k + 1]
    if cell then entry_cam(k); sys.call("workspaces.focus", cell.id) end
end)
-- What the Overview opens on: the monitor it is drawn on.
on("fact:open", function(v)
    if v ~= "overview" then
        -- what the hands held goes with the Overview; the last move stays to be undone next time
        if next(ov_marked) or ov_picked then ov_marked, ov_picked = {}, nil; fact.ov_nmark, fact.ov_win = 0, -1 end
        fact.ov_naming, fact.ov_naming_group, naming_for = false, false, nil
        fact.ov_mopen = -1
        return
    end
    text.ov_q, fact.ov_searching, fact.ov_appsel = "", false, 0
    model.ov_runs = {}
    file_token = file_token + 1
    file_hits, file_query = {}, nil
    -- the workspace to pull back from is the one you are on (the board comes a beat later); the canvas
    -- opens showing them all
    fact.ov_zc = math.max(fact.ov_act, 0)
    if fact.ov_canvas then fit_pending = true; fact.ov_cx, fact.ov_cy, fact.ov_cz = fact.ov_fx, fact.ov_fy, fact.ov_fz end
    fact.ov_sel = fact.ov_zc
    ov_sel_slot()
    run("hyprctl", { "-j", "monitors" }, function(out, code)
        local mons = code == 0 and decode(out) or {}
        table.sort(mons, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
        for n, m in ipairs(mons) do
            if m.focused then fact.ov_moni = n - 1; ov_shape(m) end
        end
    end)
end)

-- The bar's Overview button runs the same command as Super+Tab (`mooi overview`).
on("open_overview_cmd", function() run("mooi", { "overview" }) end)

-- Pictures are asked for only while the Overview shows them: a compositor copying
-- nothing is a compositor doing nothing. Previews off means they are given back and
-- never asked for again until they are on.
function atlas_up() return fact.open == "overview" end
-- Privacy (atlas.private) narrows it to the windows it lets be seen: the rest are never copied.
-- The Overview takes its pictures in bursts (D40): copying windows that change all the time —a
-- terminal at work, a browser— cost one frame in ten under a carried window, live copies one in two,
-- and starting or stopping the copies costs a frame or three of its own. So it copies for a moment
-- once it has unfolded and again after a move; in between, and all through a carry, the last
-- pictures stand.
local burst = false
local function ask_for_pictures()
    if not thumbs_watching then return end
    local mode = settings.atlas.private
    local ids, want = {}, ""
    if atlas_up() and fact.previews and mode ~= "everything" and (burst or fact.open ~= "overview") then
        if mode == "off" then want = "all" else
            for _, t in ipairs(thumbs) do
                if not atlas_geo.private(mode, t.app, t.title) then ids[#ids + 1] = t.id end
            end
            want = table.concat(ids, ",")
        end
    end
    if want == pictures_asked then return end
    if want == "all" then sys.call("thumbnails.want", "all")
    elseif want == "" then sys.call("thumbnails.want")
    else sys.call("thumbnails.want", ids) end
    pictures_asked = want
end

local bursts = 0
function picture_burst()
    if fact.open ~= "overview" or fact.bd_drag >= 0 or fact.bd_press >= 0 then return end
    bursts = bursts + 1
    local mine = bursts
    burst = true
    ask_for_pictures()
    after(BURST_MS, function() if mine == bursts then burst = false; ask_for_pictures() end end)
end
-- "Every 3 s" (Settings → Overview → Taken): a burst again every three seconds while it is open and
-- nothing is held — each one a small hitch, which is why it is not the default.
local REFRESH_MS = 3000
local refreshing = 0
on("fact:open", function(v)
    refreshing = refreshing + 1
    if v ~= "overview" then return end
    after(SETTLE_MS, picture_burst)
    if settings.atlas.refresh ~= "steady" then return end
    local mine = refreshing
    local function tick()
        if mine ~= refreshing or fact.open ~= "overview" then return end
        picture_burst()
        after(REFRESH_MS, tick)
    end
    after(REFRESH_MS, tick)
end)

-- The board is built once at startup, so the first time the Overview is opened it has its
-- tiles at once. After that it is built only while the Overview is up (see build_tiles): a
-- board nobody looks at is work for nothing.
build_tiles()

on("fact:open", function(v)
    if v ~= "overview" then ask_for_pictures() return end
    if not thumbs_watching then
        thumbs_watching = sys.watch("thumbnails", function(state)
            thumbs = state.list or {}
            if atlas_up() then build_tiles() end
            ask_for_pictures()
        end) == true
    end
    model.atlas_tiles = board   -- the last board at once: no empty frame while it is read
    ask_for_pictures()
    build_tiles()
end)

on("fact:open", function() fact.atlas_busy = false end)   -- a late reply after a close is not waited for
on("atlas_window", function(index)
    local item = atlas_tile(index)
    if not item or not hypr.valid_address(item.address) then return end
    fact.atlas_busy = true
    run_action("focus", item.address, {}, function(ok)
        fact.atlas_busy = false
    end)
end)

on("ws_pick", function(id)
    local n = tonumber(id)
    -- the one already there is left alone: Hyprland's workspace_back_and_forth would take it as "go back",
    -- so the wheel at the chain's end (or a press on the lit one) threw you to the last workspace
    if n and n > 0 and n ~= atlas_active then sys.call("workspaces.focus", n) end
end)

-- ── Command membrane ────────────────────────────────────────
require("command")({
    run_action = run_action,
    report = report,
    decode = decode,
    apps = function() return app_list end,
    icon_for = function(class) return apps.icon_for(app_index, class) end,
    letter = apps.letter,
})

-- ── The modules' own islands (shell/islands.luau, D97) ───────
require("islands")({
    settings = function() return settings end,
    save = save_settings,
})

-- ── The bar's own controls ─────────────────────────────────
-- What the mark's menu says: the version `bin/mooi` passes in (a bare test run has no
-- one, and says so), and where the settings live, shortened to what the plate holds.
local version = sys.ask("env", "MOOI_VERSION")
if type(version) ~= "string" or version == "" then version = "dev" end
text.bar_version = spaces.tail(version, 18)
text.bar_path = spaces.tail(tostring(sys.ask("files.folder")) .. "/settings.json", 26)

-- A row of the mark's menu asks, the logic writes: the setting first, then the fact the
-- bar reads. Like every setting written here, a safe-mode run
-- (which is what the test harnesses use) never writes the user's file.
on("toggle_labels", function()
    local on = not fact.bar_labels
    settings.bar.labels = on
    if not safe_mode then save_settings() end
    fact.bar_labels = on
    log("bar · workspace labels " .. (on and "on" or "off"))
end)
on("toggle_wheel", function()
    local now = (fact.bar_wheel == "step") and "off" or "step"
    settings.bar.wheel = now
    if not safe_mode then save_settings() end
    fact.bar_wheel = now
    log("bar · the wheel over the chain: " .. now)
end)
-- Day and night (D91): `mooi mode` and its key. 9 turns to whichever the desktop is not in now (out of
-- auto too: a hand on the switch means it). The theme watch sees the setting change and re-extracts.
on("set_mode", function(v)
    local n = math.floor(tonumber(v) or 9)
    local want = ({ [0] = "dark", [1] = "light", [2] = "auto" })[n] or (day and "dark" or "light")
    settings.theme.mode = want
    if not safe_mode then save_settings() end
    log("theme · mode " .. want)
    if not kept then extract() end
end)
on("toggle_theme", function()
    local wallpaper = not fact.theme_wallpaper
    settings.theme.source = wallpaper and "wallpaper" or "fixed"
    if not safe_mode then save_settings() end
    fact.theme_wallpaper = wallpaper
    apply_theme("asked from the bar")
end)

-- Re-extract the palette now, the way the settings say. Under the keeper (`mooi session`)
-- the theme watch does it: it follows these settings as well as the wallpaper and
-- holds the lock every Matugen run takes, so two runs never write the palette at once (a half
-- palette is refused whole and the bar would look stuck). A bare `mooi run` has no watch, so
-- it runs Matugen itself. Either way the palette watch repaints.
function extract()
    if kept then return end
    local home = sys.ask("env", "HOME")
    local cfg = tostring(sys.ask("files.folder")) .. "/matugen.toml"
    if type(home) ~= "string" then return end
    run("matugen", { "image", home .. "/.cache/current_wallpaper", "-c", cfg, "-m", "dark",
        "--type", "scheme-" .. settings.theme.scheme,
        "--source-color-index", tostring(settings.theme.color_index),
        "--contrast", tostring(settings.theme.contrast) }, function(_, code)
        if code ~= 0 then log("theme · matugen failed (" .. tostring(code) .. "); run `bin/mooi theme-sync` once to set it up") end
    end)
end


-- ── The desktop and mooi's keys ─────────────────────────────
-- Hyprland's look (window borders, gaps, corners; only while desktop.manage is on) is applied
-- live and, with mooi's keys, written where ~/.config/hypr/config/custom/mooi.lua reads it at
-- Hyprland's start. The border follows the bar's palette, so a new wallpaper re-colours the
-- windows' edges with the bar. Keys that change need Hyprland to read that file again (a
-- reload); the look does not.
local applied = { keys = nil, look = nil, managed = false, claims = nil }
-- The same spelling as custom/mooi.lua writes into hypr.loaded: "keys=command|…", then the
-- touchpad's "gesture 4 down=overview" (D45) — so a gesture switched on or off reloads Hyprland too.
local function keys_sig(k)
    local out = {}
    for _, b in ipairs(desktop.binds(k, settings.shutter, settings.atlas)) do out[#out + 1] = tostring(b[1]) .. "=" .. b[2] end
    for _, g in ipairs(desktop.gestures(settings.atlas)) do out[#out + 1] = string.format("gesture %d %s=%s", g[1], g[2], g[3]) end
    if settings.session.standalone then out[#out + 1] = "standalone" end   -- (D48: its keys too)
    return table.concat(out, "|")
end
function sync_desktop()
    if safe_mode then return end
    local d = settings.desktop
    local bin = sys.ask("env", "MOOI_BIN")
    if type(bin) ~= "string" or bin == "" then bin = tostring(sys.ask("env", "HOME")) .. "/Projects/mooi/bin/mooi" end
    local file = desktop.file(settings.keys, d, bar_palette, bin, settings.frame, settings.shutter, settings.atlas, settings.session)
    local ksig = keys_sig(settings.keys)
    if applied.keys == nil then
        -- The first look: the keys Hyprland really bound (custom/mooi.lua writes them down)
        -- are compared with these, and Hyprland reads the file again when they differ.
        local ok, was = pcall(sys.ask, "files.read", "hypr.loaded")
        local loaded = (ok and type(was) == "string") and was or ""
        if loaded ~= ksig then applied.keys = "" end
    end
    sys.call("files.write", "hypr.lua", file)
    local look = desktop.look(d, bar_palette, settings.frame)
    local claims = desktop.claims(d)
    -- a setting handed back to Hyprland (`keep`) needs its config read again to get its value back
    local released = applied.claims ~= nil and not desktop.covers(claims, applied.claims)
    if (applied.keys ~= nil and ksig ~= applied.keys) or released then
        run("hyprctl", { "reload" })                          -- the new keys (and the look) from the file
    elseif look and look ~= applied.look then
        run("hyprctl", { "eval", look })
    elseif not look and applied.managed then
        run("hyprctl", { "reload" })                          -- managed no more: Hyprland's own look again
    end
    applied.keys, applied.look, applied.managed, applied.claims = ksig, look, look ~= nil, claims
end

-- ── The settings window ─────────────────────────────────────
-- A program of its own (shell/mooi-settings.plm and .luau): a window in the same scene as the
-- bar intermittently took the keyboard's routing from the islands (← → in the membrane's
-- window actions were lost in half the runs), and a window that is its own process also ends
-- cleanly when the compositor closes it. It shares mooi's data folder (bin/mooi links it), so
-- it reads and writes this settings.json; the file watch above applies what it writes.
-- `set_value` stays here too, for scripts: `mooi say "emit set_value 1001"`.
on("set_value", function(raw)
    local path = setters.apply(settings, raw)
    if not path then return end
    if not safe_mode then save_settings() end
    apply(settings)
    if path == "theme.scheme" or path == "theme.color_index" or path == "theme.contrast" then extract() end
    if string.sub(path, 1, 6) == "theme." or path == "bar.mode" or string.sub(path, 1, 6) == "bar.bg" then apply_theme("set from the settings") end
end)

local settings_win = nil
local function shell_dir()
    local d = sys.ask("env", "MOOI_SHELL")
    if type(d) == "string" and d ~= "" then return d end
    return tostring(sys.ask("env", "HOME")) .. "/.local/state/mooi/live"
end
-- ── The islands as part of the frame (D152) ──
-- An island under a module is drawn by the frame (shell/mooi-frame.plm, `frame_p`): it grows out of the
-- bar's piece as one body with the band, after iNiR's chassis. As it opens, ui/island.plm says where it is
-- (three events); they go to the frame in one message with a count of openings, so its spring runs
-- from 0 even when one island follows another. When `open` changes, the frame lets the last one go.
-- Messages are sent one after another (two `--say`s at once could arrive the wrong way round).
local pl_q, pl_busy, pl_geo, pl_count = {}, false, {}, 0
local function pl_send(cmds)
    pl_q[#pl_q + 1] = cmds
    if pl_busy then return end
    local function next_one()
        local c = table.remove(pl_q, 1)
        if not c then pl_busy = false; return end
        pl_busy = true
        local args = { "--say", "mooi-frame" }
        for _, x in ipairs(c) do args[#args + 1] = x end
        run("pleamar", args, function() next_one() end)
    end
    next_one()
end
on("pl_xy", function(v) v = math.floor(tonumber(v) or 0); pl_geo.x, pl_geo.y = v // 4096, v % 4096 end)
on("pl_wh", function(v) v = math.floor(tonumber(v) or 0); pl_geo.w, pl_geo.h = v // 4096, v % 4096 end)
on("pl_t", function(v)
    if not (pl_geo.x and pl_geo.w) then return end
    pl_count = pl_count + 1
    pl_send({ "fact pl_x " .. pl_geo.x, "fact pl_y " .. pl_geo.y, "fact pl_w " .. pl_geo.w, "fact pl_h " .. pl_geo.h,
              "fact pl_tx " .. math.floor(tonumber(v) or 0), "fact pl_n " .. pl_count, "fact pl_on true" })
end)
-- `open` changed: unless another island has just been handed over (its geometry comes in the same
-- instant now, D153), the frame lets the last one go; 40 ms later, so the order cannot cross
on("fact:open", function()
    local before = pl_count
    after(40, function() if pl_count == before then pl_send({ "fact pl_on false" }) end end)
end)

on("open_settings", function()
    if settings_win then run("pleamar", { "--say", "mooi-settings", "quit" }); return end
    local mine
    local said = {}
    mine = spawn("pleamar", { "--scene", shell_dir() .. "/mooi-settings.plm", "--no-hud" }, function(line)
        if #said < 6 and string.find(line, "error") then said[#said + 1] = line end
    end, function(_, code)
        if settings_win == mine then settings_win = nil; fact.settings_open = false end
        if code ~= 0 then log("settings · the window ended (" .. tostring(code) .. "): " .. table.concat(said, " / ")) end
    end, { errors = true })
    settings_win = mine
    fact.settings_open = true
end)

-- The wallpaper picker (shell/mooi-walls.plm, D145): the strip and the colour orbit, a program of
-- its own that runs only while it is open. The bar's wallpaper button, Super+W and `mooi walls`
-- open it, and close it again while it is up. Opening it also asks for a fresh index of the folders
-- (new pictures since last time); the pass is quiet, incremental and runs once at a time.
local walls_win = nil
on("open_wallpaper", function()
    if walls_win then run("pleamar", { "--say", "mooi-walls", "quit" }); return end
    local mine
    local said = {}
    mine = spawn("pleamar", { "--scene", shell_dir() .. "/mooi-walls.plm", "--no-hud" }, function(line)
        if #said < 6 and string.find(line, "error") then said[#said + 1] = line end
    end, function(_, code)
        if walls_win == mine then walls_win = nil end
        if code ~= 0 then log("walls · the picker ended (" .. tostring(code) .. "): " .. table.concat(said, " / ")) end
    end, { errors = true })
    walls_win = mine
    run("mooi", { "wall", "index" }, function() end)
end)

-- The music player (shell/mooi-player.plm, D88): mpd's library and a remote for any other
-- player, a program of its own (it holds the keyboard). The media module's press or `mooi player`
-- opens it; the same again, Esc or its × closes it.
local player_win = nil
local player_started = 0   -- when the last one was started: a press while it starts is not a second launch
local function start_player(v)
    -- where the media module sits, so the panel hangs under it (-1: it is not on the bar)
    local cx = (tonumber(fact.x_media) or 0) + (tonumber(fact.w_media) or 0) / 2
    pcall(sys.call, "files.write", "player-anchor.json", { x = fact.p_media and cx or -1, size = (tonumber(v) == 0) and "mini" or "panel" })
    local mine
    local said = {}
    mine = spawn("pleamar", { "--scene", shell_dir() .. "/mooi-player.plm", "--no-hud", "--stall", "0" }, function(line)
        if #said < 6 and string.find(line, "error") then said[#said + 1] = line end
    end, function(_, code)
        if player_win == mine then player_win = nil; if bar then bar.relayout() end end
        if code ~= 0 then log("player · ended (" .. tostring(code) .. "): " .. table.concat(said, " / ")) end
    end, { errors = true })
    player_win = mine
    player_started = os.time()
    if bar then bar.relayout() end   -- the bar's cava feeds the player's visualizer while it is up
end
on("open_player", function(v)
    if not player_win then start_player(v); return end
    -- Open or on its way out? For a moment after it closes itself (it fades, then quits) the
    -- program is still there: a press then is a new opening, not a second close.
    run("pleamar", { "--say", "mooi-player", "get pl_open" }, function(out, code)
        if code == 0 and tonumber(out and out:match("[%d.]+")) == 1 then
            -- its own close: a video stops and mpd picks up, then it fades and quits
            run("pleamar", { "--say", "mooi-player", "emit pl_close" })
        elseif code ~= 0 and os.time() - player_started < 3 then
            return   -- still starting (its name not yet up): this press is not a second player
        else
            -- its own close fades for 260 ms and then quits: the new one waits it out, so two
            -- programs never ask for the same name at once
            player_win = nil
            after(code == 0 and 450 or 0, function() if not player_win then start_player(v) end end)
        end
    end)
end)

-- The desk (shell/mooi-desk.plm, D85, D145): the wallpaper, drawn by mooi — travelling with the
-- workspaces or the pointer while `desk.on` is set, still otherwise — and the picture's cutout over
-- the desktop widgets. A program of its own with two click-through surfaces; it always runs, and is
-- started again if it ends (a little later each time it fails at once).
local desk_win, desk_tries = nil, 0
function desk_sync()
    if desk_win then return end
    local mine
    local started = os.time()
    local said = {}
    -- spawn's line callback is required (nil is an error, which kept the desk from ever starting)
    mine = spawn("pleamar", { "--scene", shell_dir() .. "/mooi-desk.plm", "--no-hud", "--stall", "0" }, function(line)
        if #said < 6 and string.find(line, "error") then said[#said + 1] = line end
    end, function(_, code)
        if desk_win ~= mine then return end
        desk_win = nil
        if os.time() - started < 5 then desk_tries = desk_tries + 1 else desk_tries = 0 end
        if code ~= 0 then log("desk · ended (" .. tostring(code) .. "): " .. table.concat(said, " / ")) end
        if desk_tries < 5 then after(1000 * (desk_tries + 1), desk_sync) end
    end, { errors = true })
    desk_win = mine
end

-- The desktop widgets (shell/mooi-widgets.plm, D137): Now Playing and the visualiser on the bottom
-- layer, kept running while widgets.on (on unless turned off). Started before the desk, whose cutout
-- surface must stack over them; when they start again while the desk runs, the desk is asked to go
-- and desk_sync brings it back above them. Three ends within a minute and they are left down.
local widgets_win, widgets_ends, widgets_restacking, widgets_clearing = nil, {}, false, false
-- BMO's surface takes the clicks of anything under it on the same level (found 2026-11-03), so the
-- widgets go above him: whenever he comes up, they are started again (not counted as an end).
function widgets_restack()
    if not widgets_win then return end
    widgets_restacking = true
    kill(widgets_win, "term")
end
function widgets_sync()
    local want = type(settings.widgets) ~= "table" or settings.widgets.on ~= false
    if not want then
        widgets_ends = {}
        if widgets_win then kill(widgets_win, "term"); widgets_win = nil end
        return
    end
    if widgets_win then return end
    if widgets_clearing then return end
    -- one widgets program only: Pleamar starts a second beside the first (under another name), and
    -- two would draw every widget twice and undo each other's saves (D139 audit). Any left over
    -- (a slow exit, a reload) is asked to quit before ours starts.
    widgets_clearing = true
    -- every pleamar running mooi-widgets.plm, by any path
    local function strays(cb)
        run("ps", { "-eo", "pid=,args=" }, function(out)
            local list = {}
            for line in tostring(out or ""):gmatch("[^\n]+") do
                local pid, args = line:match("^%s*(%d+)%s+(.*)$")
                if pid and args:match("^pleamar%s") and args:match("%-%-scene%s+%S*mooi%-widgets%.plm") then list[#list + 1] = pid end
            end
            cb(list)
        end)
    end
    local function start_when_gone(tries)
        strays(function(list)
            if #list == 0 then widgets_clearing = false; widgets_start(); return end
            if tries == 0 then
                log("widgets · " .. #list .. " left running; asked to quit and waiting")
                run("pleamar", { "--say", "mooi-widgets", "quit" })
                local args = { "-TERM" }
                for _, pid in ipairs(list) do args[#args + 1] = pid end
                run("kill", args)
            elseif tries == 12 then
                local args = { "-KILL" }
                for _, pid in ipairs(list) do args[#args + 1] = pid end
                run("kill", args)
                log("widgets · " .. #list .. " would not quit; stopped")
            elseif tries > 16 then
                log("widgets · could not clear the old ones; not starting a second")
                widgets_clearing = false
                return
            end
            after(250, function() start_when_gone(tries + 1) end)
        end)
    end
    start_when_gone(0)
end
function widgets_start()
    if widgets_win then return end
    local want = type(settings.widgets) ~= "table" or settings.widgets.on ~= false
    if not want then return end
    local mine
    local said = {}
    mine = spawn("pleamar", { "--scene", shell_dir() .. "/mooi-widgets.plm", "--no-hud", "--stall", "0" }, function(line)
        if #said < 6 and string.find(line, "error") then said[#said + 1] = line end
    end, function(_, code)
        if widgets_win ~= mine then return end
        widgets_win = nil
        if widgets_restacking then widgets_restacking = false; widgets_start(); return end
        local now = os.time()
        local recent = {}
        for _, t in ipairs(widgets_ends) do if now - t < 60 then recent[#recent + 1] = t end end
        recent[#recent + 1] = now
        widgets_ends = recent
        if #recent >= 3 then
            log("widgets · stopped after 3 crashes in 60 s: " .. table.concat(said, " / "))
            return
        end
        if code ~= 0 then log("widgets · ended (" .. tostring(code) .. "): " .. table.concat(said, " / ")) end
        after(1000 * #recent, widgets_sync)
    end, { errors = true })
    widgets_win = mine
    if desk_win then run("pleamar", { "--say", "mooi-desk", "quit" }) end
end
after(1200, widgets_sync)
after(1500, desk_sync)

-- The side notch (shell/mooi-notch, D106): started with the bar while notch.on, kept running so that
-- pointing at it is instant, started again if it ends (later each time it fails at once).
local notch_win, notch_tries = nil, 0
function notch_sync()
    local want = type(settings.notch) ~= "table" or settings.notch.on ~= false
    if not want then notch_tries = 0; run("pleamar", { "--say", "mooi-notch", "quit" }); return end
    if notch_win then return end
    run("pleamar", { "--say", "mooi-notch", "get nt_open" }, function(_, up)
        if up == 0 or notch_win then return end
        local mine
        local started = os.time()
        local said = {}
        mine = spawn("pleamar", { "--scene", shell_dir() .. "/mooi-notch.plm", "--no-hud", "--stall", "0" }, function(line)
            if #said < 6 and string.find(line, "error") then said[#said + 1] = line end
        end, function(_, code)
            if notch_win ~= mine then return end
            notch_win = nil
            if os.time() - started < 5 then notch_tries = notch_tries + 1 else notch_tries = 0 end
            if code ~= 0 then log("notch · ended (" .. tostring(code) .. "): " .. table.concat(said, " / ")) end
            if code ~= 0 and notch_tries < 5 then after(1000 * (notch_tries + 1), notch_sync) end
        end, { errors = true })
        notch_win = mine
    end)
end
after(700, notch_sync)

-- The screen frame (shell/mooi-frame.plm, D119): a program of its own, under the bar, while frame.on
-- is set. It was drawn in this scene, where every swell of the music redrew the whole bar; its border
-- now runs round the bar's pieces from bar-geo.json, which the bar writes (shell/bar.luau).
local frame_win, frame_tries = nil, 0
function frame_sync()
    -- it also draws the bar's pieces and the islands grown out of them (island.morph) without its band
    local want = (type(settings.frame) == "table" and settings.frame.on == true)
              or (type(settings.island) == "table" and settings.island.morph ~= false)
    if not want then
        frame_tries = 0
        if frame_win then kill(frame_win, "term"); frame_win = nil end
        return
    end
    if frame_win then return end
    local mine
    local started = os.time()
    local said = {}
    mine = spawn("pleamar", { "--scene", shell_dir() .. "/mooi-frame.plm", "--no-hud", "--stall", "0" }, function(line)
        if #said < 6 and string.find(line, "error") then said[#said + 1] = line end
    end, function(_, code)
        if frame_win ~= mine then return end
        frame_win = nil
        if os.time() - started < 5 then frame_tries = frame_tries + 1 else frame_tries = 0 end
        if code ~= 0 then log("frame · ended (" .. tostring(code) .. "): " .. table.concat(said, " / ")) end
        if code ~= 0 and frame_tries < 5 then after(1000 * (frame_tries + 1), frame_sync) end
    end, { errors = true })
    frame_win = mine
end
-- At once: while the frame is on, the bar leaves its plates to the frame (D127), so until the frame
-- is up the bar's pieces stand on nothing. The notch and BMO follow soon after, one at a time, so
-- the programs do not all start together.
after(50, frame_sync)
-- Where the notch's nub is on the screen (it writes notch-state.json when it places it): the stash's
-- edge strip, overlay and over the same edge, leaves that band alone so pointing at the nub opens it.
function notch_cut()
    local on = type(settings.notch) ~= "table" or settings.notch.on ~= false
    local ok, t = pcall(sys.ask, "files.read", "notch-state.json", "json")
    t = ok and type(t) == "table" and t or {}
    local c0, c1 = tonumber(t.cut0), tonumber(t.cut1)
    if on and c0 and c1 then fact.nub_cut0, fact.nub_cut1 = c0, c1 else fact.nub_cut0, fact.nub_cut1 = 0, 0 end
end
notch_cut()
pcall(sys.watch, "files:notch-state.json", notch_cut)
on("open_claude", function() notch_sync(); run("pleamar", { "--say", "mooi-notch", "emit nt_show 0" }) end)
on("open_github", function() notch_sync(); run("pleamar", { "--say", "mooi-notch", "emit nt_show 5" }) end)

-- BMO (shell/bmo), the desktop companion: started with the bar — so at login — while
-- companion.bmo is on, and started again when he ends for any reason but being turned off (later
-- each time he fails at once). One already running (started by hand) is left be. A BMO that is
-- alive but no longer answering — a logic that stopped, or a process that lost the name to a
-- newer one — is ended and replaced: one that draws nothing is not worth keeping.
-- What is *wanted* (`companion.bmo`) and what is *happening* (his process) are kept apart, because
-- every step between them is asynchronous — a probe, a launch, a kill — and the setting can change
-- while one is in flight (found 2026-10-30: a BMO that started after being turned off, a quit sent
-- to nothing while a launch was pending, and a stop that left him running). The states are
-- `stopped` → `starting` → `running` → `stopping`; `bmo_sync` is the only way in and looks at both,
-- every callback comes back to it, and `bmo_gen` names the process a callback belongs to, so one
-- from an old process cannot touch a newer one.
local bmo_state = "stopped"
local bmo_win, bmo_gen = nil, 0
local bmo_tries, bmo_probe = 0, 0
local bmo_token, bmo_beat, bmo_miss = nil, nil, 0

local function bmo_wanted()
    return type(settings.companion) == "table" and settings.companion.bmo == true
end

local bmo_launch   -- starts one, below

-- Let go of the process we knew: its callbacks are stale from here, and the next start begins clean.
local function bmo_forget()
    bmo_gen = bmo_gen + 1
    bmo_win, bmo_state = nil, "stopped"
    bmo_tries, bmo_probe, bmo_token, bmo_beat, bmo_miss = 0, 0, nil, nil, 0
end

-- Start one. Only ever with `bmo_state` = starting and a generation of its own: a launch that finds
-- either gone (turned off, or replaced by a newer start) does nothing at all.
function bmo_launch(gen)
    if bmo_gen ~= gen or bmo_state ~= "starting" then return end
    local mine
    local started = os.time()
    local said = {}
    mine = spawn("pleamar", { "--scene", shell_dir() .. "/bmo/bmo.plm", "--no-hud", "--stall", "0" }, function(line)
        -- his errors are the shell's too: six of them, as they come (before, only an exit kept them)
        if #said < 6 and string.find(line, "error") then said[#said + 1] = line; log("bmo · " .. line) end
    end, function(_, code)
        -- a callback from a process we have already let go of changes nothing
        if bmo_gen ~= gen or bmo_win ~= mine then return end
        if code ~= 0 then log("bmo · ended (" .. tostring(code) .. "): " .. table.concat(said, " / ")) end
        bmo_win, bmo_state = nil, "stopped"
        bmo_token, bmo_beat, bmo_miss = nil, nil, 0
        if os.time() - started < 5 then bmo_tries = bmo_tries + 1 else bmo_tries = 0 end
        if not bmo_wanted() then bmo_forget(); return end         -- turned off while he was up
        if bmo_tries >= 5 then return end                         -- five that failed at once: let him be
        local next_gen = bmo_gen + 1
        bmo_gen = next_gen
        after(1000 * (bmo_tries + 1), function()
            if bmo_gen ~= next_gen or bmo_state ~= "stopped" then return end
            bmo_sync()
        end)
    end, { errors = true })
    if bmo_gen ~= gen or bmo_state ~= "starting" then
        -- turned off while the spawn was being made: nothing of his is wanted
        kill(mine, "term")
        bmo_forget()
        return
    end
    bmo_win = mine
    bmo_state = "running"
    if widgets_restack then after(400, widgets_restack) end
end

-- Ask whether one is already there before starting another: a BMO that is up but slow to answer
-- would otherwise get a second one spawned beside it (two lived on 2026-10-30, and the loser drew
-- nothing while its logic kept running). Twice more before deciding nobody is there.
local function bmo_probe_start(gen)
    if bmo_gen ~= gen or bmo_state ~= "starting" then return end
    if not bmo_wanted() then bmo_forget(); run("pleamar", { "--say", "bmo", "quit" }); return end
    run("pleamar", { "--say", "bmo", "get ready" }, function(_, up)
        if bmo_gen ~= gen or bmo_state ~= "starting" then return end
        if not bmo_wanted() then bmo_forget(); run("pleamar", { "--say", "bmo", "quit" }); return end
        if up == 0 then
            -- one is already there — the new one a refresh makes before the old is gone, or one
            -- started by hand — and he is left be: running, without a handle of ours to kill (a
            -- stop asks him to quit, and the guard takes over if he stops answering)
            bmo_win, bmo_state = nil, "running"
            bmo_probe, bmo_token, bmo_beat, bmo_miss = 0, nil, nil, 0
            return
        end
        if bmo_probe < 2 then
            bmo_probe = bmo_probe + 1
            after(900, function() bmo_probe_start(gen) end)
            return
        end
        bmo_probe = 0
        bmo_launch(gen)
    end)
end

function bmo_sync()
    if not bmo_wanted() then
        -- turned off: whatever is up goes — ours killed, one started by hand asked to quit
        bmo_tries, bmo_probe = 0, 0
        if bmo_state == "stopped" or bmo_state == "stopping" then
            run("pleamar", { "--say", "bmo", "quit" })
            return
        end
        local gen = bmo_gen + 1
        local win = bmo_win
        bmo_gen = gen
        bmo_win, bmo_state = nil, "stopping"
        if win then kill(win, "term") end
        run("pleamar", { "--say", "bmo", "quit" })
        after(1200, function()
            if bmo_gen ~= gen or bmo_state ~= "stopping" then return end
            bmo_forget()
            -- and not before nothing answers to his name: a next one that comes up while the old
            -- socket still replies is the second BMO and draws nothing for a while (his spare rule).
            -- Up to three looks, 700 ms apart, then he is started anyway.
            local looks = 0
            local function silent()
                if not bmo_wanted() then bmo_sync(); return end
                run("pleamar", { "--say", "bmo", "get token" }, function(_, code)
                    if code ~= 0 or looks >= 3 then bmo_sync(); return end
                    looks = looks + 1
                    after(700, silent)
                end)
            end
            silent()
        end)
        return
    end
    if bmo_state ~= "stopped" then return end                    -- already starting, running or stopping
    local gen = bmo_gen + 1
    bmo_gen = gen
    bmo_state = "starting"
    bmo_probe_start(gen)
end
after(1400, bmo_sync)
-- Is the BMO we started still the one answering, and still alive? Three ways it is not:
-- nothing answers to `bmo` twice in a row (the logic is gone, or the name went to another
-- process), the beat has not moved since the last look (his upkeep counts one every 30 s, so a
-- still counter is a logic that is stuck — a clock is not used: a scene's time is its own),
-- or another token answers (a newer BMO took the name). Any of them, and he is wanted but there
-- is no BMO at all: end ours (or start one) and look again.
-- (found 2026-10-29: a BMO that ran for two hours, drawing nothing and saving nothing, which no
-- restart rule could see.)
local function bmo_guard()
    if not bmo_wanted() then return end
    if bmo_state ~= "running" then return end                    -- a start or a stop is already under way
    local mine, gen = bmo_win, bmo_gen
    if not mine then
        -- one that answers to `bmo` and that we did not start (see bmo_probe_start): watched, not
        -- replaced, until it stops answering
        run("pleamar", { "--say", "bmo", "get token" }, function(out, code)
            if bmo_gen ~= gen or bmo_state ~= "running" then return end
            local token = code == 0 and tonumber((out or ""):match("^%s*([%d.]+)%s*$")) or nil
            if token then bmo_token = token; bmo_miss = 0; return end
            bmo_miss = bmo_miss + 1
            if bmo_miss >= 2 then replace("not answering") end
        end)
        return
    end
    local function replace(why)
        if bmo_gen ~= gen or bmo_win ~= mine then return end
        log("bmo · " .. why .. "; starting him again")
        local next_gen = bmo_gen + 1
        bmo_gen = next_gen
        bmo_win, bmo_state = nil, "stopping"
        if mine then kill(mine, "term") end
        run("pleamar", { "--say", "bmo", "quit" })
        after(1500, function()
            if bmo_gen ~= next_gen or bmo_state ~= "stopping" then return end
            bmo_forget()
            bmo_sync()
        end)
    end
    run("pleamar", { "--say", "bmo", "get token" }, function(out, code)
        if bmo_gen ~= gen or bmo_win ~= mine then return end
        local token = code == 0 and tonumber((out or ""):match("^%s*([%d.]+)%s*$")) or nil
        if not token then
            -- a BMO that has just started has not answered yet: one look is not enough
            bmo_miss = bmo_miss + 1
            if bmo_miss >= 2 then replace("not answering") end
            return
        end
        bmo_miss = 0
        if bmo_token and token ~= bmo_token then replace("another one has the name") return end
        bmo_token = bmo_token or token
        run("pleamar", { "--say", "bmo", "get beat" }, function(b, bc)
            if bmo_gen ~= gen or bmo_win ~= mine then return end
            local beat = bc == 0 and tonumber((b or ""):match("^%s*([%d.]+)%s*$")) or nil
            if not beat then return end
            if bmo_beat ~= nil and beat == bmo_beat then replace("its logic stopped") return end
            bmo_beat = beat
        end)
    end)
end
every(30000, bmo_guard)
-- What BMO hears from the bar (bmo.luau "Desktop awareness"): `emit tell N` while he is wanted.
local function bmo_tell(n)
    if type(settings.companion) == "table" and settings.companion.bmo == true then
        run("pleamar", { "--say", "bmo", "emit tell " .. n })
    end
end

-- Control Nexus (shell/mooi-nexus.plm, D65): the system command centre. A program of its own
-- for the same reason as the studio: it holds the keyboard exclusively and declares its own
-- full-screen surface. The bar starts it from the Arch mark; `mooi nexus` again, its ×, an
-- outside press or Escape ends it. The start waits for the bar to let go of the keyboard.
local nexus_win = nil
-- D118: the Nexus is started once and stays running, hidden; the mark (or `mooi nexus`) toggles it.
-- It tells the bar when it is open (fact nexus_open). Started with MOOI_NEXUS_OPEN=1 it opens as
-- soon as it is up: that is the path when it was not running yet (first press, or after a crash).
local function nexus_start(open_now)
    local mine
    local said = {}
    -- --stall 0: the default holds the logic for 600 ms after every decision to prove the
    -- renderer is decoupled, which is a demonstration, not a desktop. The bar runs the
    -- same way, so a press in the Nexus answers as fast as a press in the bar.
    mine = spawn("pleamar", { "--scene", shell_dir() .. "/mooi-nexus.plm", "--no-hud", "--stall", "0" }, function(line)
        if #said < 6 and string.find(line, "error") then said[#said + 1] = line end
    end, function(_, code)
        if nexus_win == mine then nexus_win = nil; fact.nexus_open = false end
        if code ~= 0 then log("nexus · the command centre ended (" .. tostring(code) .. "): " .. table.concat(said, " / ")) end
    end, { errors = true, env = { MOOI_NEXUS_OPEN = open_now and "1" or "0" } })
    nexus_win = mine
end
on("open_nexus", function()
    if nexus_win then run("pleamar", { "--say", "mooi-nexus", "emit nx_toggle" }); return end
    nexus_start(true)
end)
-- started hidden a little after the bar, so the first press opens it at once
after(4000, function() if not nexus_win then nexus_start(false) end end)

-- ── The board (D52, D64): a Kanban board, a program of its own (shell/mooi-board.plm) ──
-- The bar no longer draws it: it starts that program (and closes it again), and keeps only what the
-- pad's rail shows — how many cards there are and how many are late — by reading board.json through
-- the same pure rules (lib/board). A note sent from the pad is a card added to the file, which the
-- board's own watch picks up at once if it is up.
local kboard = require("lib/board")
local board_win = nil
local board_off = 0
local function board_read()
    local ok, t = pcall(sys.ask, "files.read", "board.json", "json")
    if ok and t ~= nil then return kboard.decode(t) end
    return kboard.new()
end
local function board_badge()
    local st = kboard.stats(board_read(), kboard.today(os.time(), board_off))
    fact.kb_count = st.cards
    fact.kb_late = st.late
end
local function board_add_note(title, note)
    if safe_mode then return false end
    local b = board_read()
    local c = kboard.add(b, b.columns[1].id, title, note, os.time())
    if not c then return false end
    sys.call("files.write", "board.json", kboard.encode(b))
    board_badge()
    return true
end
run("date", { "+%z" }, function(out)
    local sign, h, m = string.match(tostring(out or ""), "([+-])(%d%d)(%d%d)")
    if sign then board_off = (tonumber(h) * 3600 + tonumber(m) * 60) * (sign == "-" and -1 or 1) end
    board_badge()
end)
pcall(sys.watch, "files:board.json", board_badge)
board_badge()

-- ── Quick notes: the pad behind the bar's notes module (shell/notes.luau, D51) ──
require("notes")({ safe_mode = safe_mode, to_board = board_add_note })

-- The board's program: started when the pad's rail, its key or `mooi board` asks for it, closed by
-- the same again (or by a press outside it, its × or Escape in the board itself). The start waits
-- for the bar to have let go of the keyboard (the scene closes its panels in the same instant), as
-- a window focus waits for an island to let go.
on("board_show", function()
    if board_win then run("pleamar", { "--say", "mooi-board", "quit" }); return end
    local mine
    local said = {}
    after(90, function()
        if board_win then return end
        mine = spawn("pleamar", { "--scene", shell_dir() .. "/mooi-board.plm", "--no-hud" }, function(line)
            if #said < 6 and string.find(line, "error") then said[#said + 1] = line end
        end, function(_, code)
            if board_win == mine then board_win = nil; board_badge() end
            if code ~= 0 then log("board · the board ended (" .. tostring(code) .. "): " .. table.concat(said, " / ")) end
        end, { errors = true })
        board_win = mine
    end)
end)
-- ── The stash (shell/stash.luau, D54): the box on the left edge, and what is dropped in ──
require("stash")({ safe_mode = safe_mode })
-- the activity map (D105): which app had the focus, a minute at a time
require("activity")({ safe_mode = safe_mode })

-- ── Signal Loom: the notifications (shell/signals.luau, D50) ──
loom = require("signals")({
    bmo = bmo_tell,
    settings = function() return settings end,
    save = save_settings,
    mode = sys.ask("env", "MOOI_MODE") or "run",
    safe_mode = safe_mode,
})

-- ── The Ferrolume bar: layout, readers and actions (shell/bar.luau) ──
bar = require("bar")({
    bmo = bmo_tell,
    signal = loom.signal,
    requiet = loom.requiet,
    settings = function() return settings end,
    save = save_settings,
    mode = sys.ask("env", "MOOI_MODE") or "run",
    space_count = function() return #ws_rows > 0 and #ws_rows or fact.ws_max end,
    outline = function(id) return outlines[id] or 0 end,
    saving = function() return saving() end,
    player_up = function() return player_win ~= nil end,
})

-- ── The Mechanical Shutter: a window's controls, unfolding from its edge (shell/shutter.luau) ──
require("shutter")({
    settings = function() return settings end,
    run_action = run_action,
    report = report,
    spaces = function() return ws_rows end,
    active_ws = function() return atlas_active end,
})

-- ── Saved environments (D43): the Overview's Environments drawer (shell/environments.luau) ──
require("environments")({
    decode = decode,
    apps = function() return app_list end,
    identities = function() return identities end,
    set_identities = function(t) identities = atlas_geo.identities(t) end,
    save_identities = save_identities,
    build_tiles = build_tiles,
    say = ov_say,
    apply_moves = apply_moves,
    safe_mode = safe_mode,
})

log("mooi · logic ready · settings in " .. tostring(sys.ask("files.folder")))
