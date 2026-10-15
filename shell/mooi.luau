-- mooi logic: settings, the island's target window, and Hyprland actions.
-- It never draws and never decides what the user meant: the scene's rules do that.

local config = require("lib/config")
local theme = require("lib/theme")
local hypr = require("lib/hypr")
local apps = require("lib/apps")
local spaces = require("lib/spaces")

local FILE = "settings.json"
local KNOWN_GOOD = "settings.known-good.json"

-- Safe mode (the tests run it) never writes the real settings file: a run that
-- toggles something must not become the user's settings.
local safe_mode = sys.ask("env", "MOOI_SAFE") == "1"

local settings = config.defaults()
local target = nil      -- the window the island acts on (hypr.client shape)
local generation = 0    -- bumps on every open, so late replies for an old target are dropped

-- ── Settings ────────────────────────────────────────────────
local function apply(s)
    fact.max_results = s.command.max_results
    fact.show_clock = s.spine.clock
    fact.ws_max = s.spine.max_workspaces
    fact.confirm_close = s.island.confirm_close
    fact.previews = s.atlas.previews
    -- The Mechanism's own settings, which the bar reads straight from these facts.
    fact.bar_labels = s.bar.labels
    fact.bar_wheel = s.bar.wheel
    fact.theme_wallpaper = (s.theme.source == "wallpaper")
end

local function load_settings()
    if sys.ask("env", "MOOI_SAFE") == "1" then
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

-- ── Theme ──────────────────────────────────────────────────
-- The brief's colour pipeline, in one place (lib/theme decides; this only reads and
-- paints): fixed palette → the wallpaper's Matugen palette → the user's overrides →
-- completeness and contrast. A theme that does not pass is refused *whole* and the last
-- good one stays on screen; colour facts are the only things anything here writes, so a
-- palette change can never move a surface or change a spring.
local PALETTE = "palette.json"
local palette = nil     -- what theme/palette.json.hbs wrote (Matugen, dark scheme)

local function load_palette()
    local ok, t = pcall(sys.ask, "files.read", PALETTE, "json")
    palette = (ok and type(t) == "table") and t or nil
end

-- The scene paints each token from three facts: `rgb()` is the only way the logic can
-- hand over a colour that did not exist when the scene was read, so every token has its
-- three. Written out in full so a scene name and a logic name cannot drift apart quietly
-- (the scene compile catches either one going missing).
local function paint(colours)
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

local function apply_theme(reason)
    local colours, source, notes, problems = theme.resolve(settings.theme, palette)
    for _, n in ipairs(notes) do log("theme · " .. n) end
    if #problems > 0 then
        fact.theme_error = true
        for _, p in ipairs(problems) do log("theme · problem · " .. p) end
        log("theme · refused the " .. tostring(source) .. " palette (" .. reason .. "); the last good one is showing")
        return false
    end
    paint(colours)          -- checked first, then written: the 42 facts together or not at all
    fact.theme_error = false
    log("theme · applied · " .. tostring(source) .. " · " .. reason)
    return true
end

load_settings()
load_palette()
apply_theme("first read")
sys.watch("files:" .. FILE, function() load_settings(); apply_theme("settings changed") end)
sys.watch("files:" .. PALETTE, function() load_palette(); apply_theme("a new palette arrived") end)
on("recolor", function() load_palette(); load_settings(); apply_theme("asked to recolour") end)

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
    if v ~= "window" then generation = generation + 1 end
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
local ws_rows = {}          -- the last map, for the names the bar asks about
local function name_of(id)
    for _, r in ipairs(ws_rows) do
        if r.id == id then
            -- Hyprland calls an unnamed workspace after its own number: saying so adds
            -- nothing, so the bar says "workspace 4" and not "4 4".
            if r.name ~= "" and r.name ~= tostring(r.id) then return r.name end
            return "workspace " .. tostring(r.id)
        end
    end
    return "workspace " .. tostring(id)
end
local function show_nav_name()
    local id = tonumber(fact.nav_sel) or 1
    local there = false
    for _, r in ipairs(ws_rows) do if r.id == id then there = r.exists end end
    text.nav_name = there and name_of(id) or (name_of(id) .. " · nothing on it yet")
end
sys.watch("workspaces", function(w)
    atlas_active = tonumber(w.active) or atlas_active
    ws_rows = spaces.rows(w.list or {}, atlas_active, fact.ws_max)
    model.spaces = ws_rows   -- the Mechanism's scale and the Atlas's move strip, one map
    -- Where the carriage goes. An active workspace that is not on the scale at all (a
    -- special one, or one past the configured span) leaves it at the first position
    -- rather than off the rail.
    local row = 0
    for _, r in ipairs(ws_rows) do if r.active then row = r.id - 1 end end
    fact.active_row = row
    show_nav_name()
end)
on("fact:nav_sel", show_nav_name)

-- ── The Atlas: the windows Hyprland lists, with a picture where one is given ──
-- Hyprland's clients are the tiles: each brings its own address and workspace, so
-- every tile can be focused. `thumbnails` only lends the pictures —the ids it goes
-- by are the compositor's own, not Hyprland addresses— so a picture is matched to a
-- window by app and title, one window each.
local thumbs = {}
local thumbs_watching = false   -- the service answered and is watched
local pictures_asked = false    -- the compositor is copying the windows for us
local board = {}                -- the last tiles built, to open with something to show

local function atlas_tile(index)
    return model.atlas_tiles[(tonumber(index) or -1) + 1]
end

-- The move strip is about the selected tile: its name, and the workspace it is on
-- to start from (only while browsing: the strip's own choice is not taken back).
local function sync_move_target()
    local item = atlas_tile(fact.atlas_sel)
    if not item then text.atlas_target = "" return end
    text.atlas_target = tostring(item.app ~= "" and item.app or "window") .. ": " .. tostring(item.title or "")
    local ws = tonumber(item.ws)
    if fact.atlas_mode ~= "move" and ws and ws >= 1 and ws <= fact.ws_max then fact.atlas_ws = ws end
end

local function build_tiles()
    run("hyprctl", { "-j", "clients" }, function(out, code)
        local clients = code == 0 and hypr.windows(decode(out)) or {}
        local taken = {}
        local rows = {}
        for _, w in ipairs(clients) do
            local picture, stale = "", false
            -- Previews off: no picture is matched, so none is drawn — and the service
            -- has already been told to give the frames back.
            if fact.previews then
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
                title = w.title ~= "" and w.title or w.class,
                app = w.class ~= "" and w.class or "window",
                picture = picture,
                stale = stale,
            }
        end
        board = rows
        -- Only while the Atlas is up: a model nobody looks at is work for nothing, and
        -- the board is left as it is while it leaves, so the way out is whole.
        if fact.open == "atlas" then
            model.atlas_tiles = rows
            sync_move_target()
        end
    end)
end

-- Pictures are asked for only while the Atlas shows them: a compositor copying
-- nothing is a compositor doing nothing. Previews off means they are given back and
-- never asked for again until they are on.
local function ask_for_pictures()
    if not thumbs_watching then return end
    local want = fact.open == "atlas" and fact.previews
    if want == pictures_asked then return end
    if want then sys.call("thumbnails.want", "all") else sys.call("thumbnails.want") end
    pictures_asked = want
end

on("fact:atlas_sel", sync_move_target)

-- The board is built once at startup, so the first time the Atlas is opened it has its
-- tiles at once and the strip has a workspace to start on. After that it is built only
-- while the Atlas is up (see build_tiles): a board nobody looks at is work for nothing.
build_tiles()

on("fact:open", function(v)
    if v ~= "atlas" then ask_for_pictures() return end
    if not thumbs_watching then
        thumbs_watching = sys.watch("thumbnails", function(state)
            thumbs = state.list or {}
            if fact.open == "atlas" then build_tiles() end
            ask_for_pictures()
        end) == true
    end
    model.atlas_tiles = board   -- the last board at once: no empty frame while it is read
    -- The strip starts on the selected tile's workspace now, from the board we already
    -- have: the fresh board arrives from `hyprctl` a moment later, and the strip may be
    -- up by then — a late reply must not be what decides where it points.
    sync_move_target()
    ask_for_pictures()
    build_tiles()
end)

local atlas_request = 0
on("fact:open", function(v)
    if v ~= "atlas" then
        atlas_request = atlas_request + 1 -- ignore a late reply after close or hand-over
        fact.atlas_busy = false
    end
end)
on("atlas_window", function(index)
    local item = atlas_tile(index)
    if not item or not hypr.valid_address(item.address) then return end
    fact.atlas_busy = true
    run_action("focus", item.address, {}, function(ok)
        fact.atlas_busy = false
        if ok and fact.open == "atlas" then fact.open = "none" end
    end)
end)

-- Move the selected tile's window to the workspace the strip chose. The window island's
-- own verified action: Hyprland's reply is never the proof, the window read back after it
-- is — and the Spine pulses where it went, as it does for a move from the island.
on("atlas_move", function()
    local item = atlas_tile(fact.atlas_sel)
    if not item or not hypr.valid_address(item.address) then
        report(false, "That tile is not a window any more")
        return
    end
    local ws = tonumber(fact.atlas_ws)
    if not ws or ws ~= math.floor(ws) or ws < 1 or ws > fact.ws_max then
        report(false, string.format("Workspace %s is outside the map (1 to %d)", tostring(fact.atlas_ws), fact.ws_max))
        return
    end
    fact.atlas_busy = true
    run_action("move", item.address, { workspace = ws, follow = false }, function(ok)
        fact.atlas_busy = false
        fact.atlas_mode = "browse"
        if ok then
            fact.flash_ws = ws
            emit("moved")
            build_tiles()     -- the tile now says where it went
        end
    end)
end)

-- Preview pictures on or off. Off is a promise that nothing is captured: the frames are
-- given back at once and none is asked for again while it holds. It is a setting, so it is
-- remembered — except in safe mode, which never writes the settings file.
on("atlas_previews", function()
    local on = not fact.previews
    fact.previews = on
    if not safe_mode then
        settings.atlas.previews = on
        sys.call("files.write", FILE, settings)
    end
    if not on then thumbs = {} end
    ask_for_pictures()
    build_tiles()
    report(true, on and "Preview pictures on" or "Preview pictures off")
    log("atlas · preview pictures " .. (on and "on" or "off"))
end)

on("atlas_go", function(id)
    local want = tonumber(id)
    if not want or want ~= math.floor(want) or want < 1 or want > fact.ws_max or want > 99 then
        fact.atlas_busy = false
        report(false, string.format("Workspace %s is outside the map (1 to %d)", tostring(id), fact.ws_max))
        return
    end
    atlas_request = atlas_request + 1
    local mine = atlas_request
    fact.atlas_busy = true

    local function finish(ok)
        if mine ~= atlas_request then return end
        fact.atlas_busy = false
        if ok then
            if fact.open == "atlas" then fact.open = "none" end
        else
            report(false, "Hyprland did not switch to workspace " .. want)
        end
    end
    if atlas_active == want then finish(true); return end

    sys.call("workspaces.focus", want)
    local tries = 0
    local function confirm()
        if mine ~= atlas_request then return end
        tries = tries + 1
        if atlas_active == want then finish(true)
        elseif tries < 12 then after(75, confirm)
        else finish(false) end
    end
    after(75, confirm)
end)

on("ws_pick", function(id)
    local n = tonumber(id)
    if n and n > 0 then sys.call("workspaces.focus", n) end
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

-- ── The bar's own controls ─────────────────────────────────
-- What the mark's menu says: the version `bin/mooi` passes in (a bare test run has no
-- one, and says so), and where the settings live, shortened to what the plate holds.
local version = sys.ask("env", "MOOI_VERSION")
if type(version) ~= "string" or version == "" then version = "dev" end
text.bar_version = spaces.tail(version, 18)
text.bar_path = spaces.tail(tostring(sys.ask("files.folder")) .. "/settings.json", 26)

-- A row of the mark's menu asks, the logic writes: the setting first, then the fact the
-- bar reads. Exactly how the Atlas's previews switch works — and, like it, a safe-mode run
-- (which is what the test harnesses use) never writes the user's file.
on("toggle_labels", function()
    local on = not fact.bar_labels
    if not safe_mode then settings.bar.labels = on; sys.call("files.write", FILE, settings) end
    fact.bar_labels = on
    log("bar · workspace labels " .. (on and "on" or "off"))
end)
on("toggle_wheel", function()
    local now = (fact.bar_wheel == "step") and "off" or "step"
    if not safe_mode then settings.bar.wheel = now; sys.call("files.write", FILE, settings) end
    fact.bar_wheel = now
    log("bar · the wheel over the scale: " .. now)
end)
on("toggle_theme", function()
    local wallpaper = not fact.theme_wallpaper
    settings.theme.source = wallpaper and "wallpaper" or "fixed"
    if not safe_mode then sys.call("files.write", FILE, settings) end
    fact.theme_wallpaper = wallpaper
    apply_theme("asked from the bar")
end)

log("mooi · logic ready · settings in " .. tostring(sys.ask("files.folder")))
