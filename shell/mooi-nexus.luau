-- Control Nexus (D65): the system command centre, a program of its own. The scene
-- (`mooi-nexus.plm`) draws the plate and reads the bar's own services; this file paints the
-- shell's colours into it, keeps the player's text fields, and is the only place that calls
-- the system. The data folder is mooi's (bin/mooi links mooi-nexus to it), so settings.json
-- and palette.json are shared with the bar and a wallpaper change re-lights the plate too.

local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")
local nexus = require("lib/nexus")
local sysinfo = require("lib/sysinfo")
local telemetry = require("lib/telemetry")

local FILE = "settings.json"
local PALETTE = "palette.json"

local function env(name, fallback)
    local ok, v = pcall(sys.ask, "env", name)
    if ok and type(v) == "string" and v ~= "" then return v end
    return fallback
end

local data_home = env("XDG_DATA_HOME", env("HOME", "") .. "/.local/share")
local identity_home = data_home .. "/pleamar/mooi"

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end

local settings = config.parse(read(FILE), json.decode)
local palette = read(PALETTE, "json")

-- A text field can be drawn but not compared in the scene, so the presence facts and the
-- avatar's initial are published here beside the paths, from the one identity the settings own.
local function sync_identity()
    local identity = (type(settings.nexus) == "table" and type(settings.nexus.identity) == "table")
        and settings.nexus.identity or {}
    local name = type(identity.name) == "string" and identity.name or "mooi system"
    local avatar = type(identity.avatar) == "string" and identity.avatar or ""
    local banner = type(identity.banner) == "string" and identity.banner or ""
    text.nx_identity_name = name
    text.nx_initial = string.upper(string.sub(name, 1, 1))
    text.nx_avatar_path = avatar ~= "" and (identity_home .. "/" .. avatar) or ""
    text.nx_banner_path = banner ~= "" and (identity_home .. "/" .. banner) or ""
    fact.nx_avatar_on = avatar ~= ""
    fact.nx_banner_on = banner ~= ""
end
sync_identity()

-- The same roles the bar wears, from the same palette and settings; the tokens glide to them.
local function paint()
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"] = c.r
        fact["fr_" .. role .. "_g"] = c.g
        fact["fr_" .. role .. "_b"] = c.b
    end
end
paint()
pcall(sys.watch, "files:" .. PALETTE, function()
    palette = read(PALETTE, "json")
    paint()
end)
pcall(sys.watch, "files:" .. FILE, function()
    settings = config.parse(read(FILE), json.decode)
    fact.nx_pinned = settings.nexus and settings.nexus.pinned == true
    sync_identity()
end)

-- The glow the plate carries follows the theme's finish, as the bar's does.
local look = style.facts(settings)
if look and look.st_glow then fact.st_glow = look.st_glow end

-- Who is here: the session's own answers, never a made-up name. Each has a plain fallback
-- for a session that does not export it.
text.nx_user = env("USER", "operator")
text.nx_host = env("HOSTNAME", "Arch Linux")
text.nx_session = env("XDG_CURRENT_DESKTOP", "Hyprland")
fact.nx_pinned = settings.nexus and settings.nexus.pinned == true
sync_identity()

-- The player: the service's text fields can be drawn, but not compared, so the facts that say
-- "there is something here" and the fields themselves are kept on this side of the boundary.
local function clear_media()
    fact.nx_has = false
    fact.nx_playing = false
    fact.nx_progress = 0
    fact.nx_album_on = false
    fact.nx_player_on = false
    text.nx_title = ""
    text.nx_artist = ""
    text.nx_album = ""
    text.nx_player = ""
end
clear_media()
pcall(sys.watch, "media", function(m)
    if type(m) ~= "table" then clear_media(); return end
    local title = type(m.title) == "string" and m.title or ""
    local artist = type(m.artist) == "string" and m.artist or ""
    local album = type(m.album) == "string" and m.album or ""
    local player = type(m.player) == "string" and m.player or ""
    local length = tonumber(m.length) or 0
    local position = tonumber(m.position) or 0

    fact.nx_has = title ~= ""
    fact.nx_playing = m.playing == true
    fact.nx_progress = (fact.nx_has and length > 0) and math.max(0, math.min(1, position / length)) or 0
    fact.nx_album_on = album ~= ""
    fact.nx_player_on = player ~= ""
    text.nx_title = title
    text.nx_artist = artist
    text.nx_album = album
    text.nx_player = player
end)

-- Audio routing: the service owns the device lists; the logic keeps the last answer and names
-- the default, so a press can cycle to the next id without the scene iterating a list.
local routes = { out = {}, input = {} }
local function publish_routes()
    text.nx_out_name = nexus.default_device(routes.out) or "—"
    text.nx_in_name = nexus.default_device(routes.input) or "—"
end
local function read_routes(audio)
    if type(audio) ~= "table" then return end
    routes.out = type(audio.outputs) == "table" and audio.outputs or {}
    routes.input = type(audio.inputs) == "table" and audio.inputs or {}
    publish_routes()
end
pcall(sys.watch, "audio", read_routes)
local routed, initial_audio = pcall(sys.ask, "audio")
if routed then read_routes(initial_audio) end
publish_routes()

-- ── Linux system telemetry ───────────────────────────────────
-- Fixed, allowlisted reads only. Each optional source fails closed; no display text is ever
-- interpolated into a command. Static identity is read once, while proc counters are sampled
-- every two seconds so rates are derived from deltas instead of repeated heavyweight polling.
local cpu_previous, net_previous = nil, nil
local core_previous = nil
local function launch(command, args, done)
    local ok = pcall(run, command, args, function(out, code)
        if code == 0 and type(out) == "string" then done(out) else done(nil) end
    end)
    if not ok then done(nil) end
end
local function trim(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
end
local function read_static()
    launch("cat", { "/etc/os-release" }, function(os_text)
        if os_text then
            local os = telemetry.os_release(os_text)
            local name = os.name or "Unknown distribution"
            local version = os.version
            text.nx_distro = (type(version) == "string" and version ~= "") and (name .. " · " .. version) or name
            text.nx_os_version = os.version or ""
            text.nx_os_id = os.id or ""
        else text.nx_distro = "Distribution unavailable" end
        fact.nx_telemetry_on = true
    end)
    launch("uname", { "-r" }, function(out)
        text.nx_kernel = trim(out) or "Kernel unavailable"
    end)
    launch("hostname", {}, function(out)
        text.nx_host = trim(out) or env("HOSTNAME", "Host unavailable")
    end)
    launch("cat", { "/proc/uptime" }, function(out)
        text.nx_uptime = telemetry.uptime(out) or "Uptime unavailable"
    end)
    launch("cat", { "/proc/cpuinfo" }, function(out)
        text.nx_cpu_model = telemetry.cpu_model(out) or "CPU model unavailable"
    end)
    launch("hyprctl", { "monitors", "-j" }, function(out)
        if not out then text.nx_display_value = "DISPLAY INFO N/A"; return end
        local ok, monitors = pcall(json.decode, out)
        local summary = ok and sysinfo.display_summary(monitors) or nil
        text.nx_display_value = summary or "DISPLAY INFO N/A"
    end)
end
read_static()

local function sample_live()
    launch("cat", { "/proc/stat" }, function(out)
        local value
        value, cpu_previous = sysinfo.cpu(out, cpu_previous)
        if value ~= nil then
            fact.nx_cpu_on = true
            fact.nx_cpu = value
            text.nx_cpu_value = string.format("%d%%", math.floor(value * 100 + 0.5))
        end
        local cores = sysinfo.cpu_cores(out)
        local count = 0
        for _ in pairs(cores) do count = count + 1 end
        if count > 0 then text.nx_cpu_label = string.format("CPU LOAD · %d CORES", count) end
        core_previous = cores
    end)
    -- Optional DRM interface; most but not all drivers expose this file. Fixed card paths keep
    -- the allowlist strict (no interpreter); every attempt fails closed and the first reading wins.
    local gpu_seen = false
    local function read_gpu(i)
        if i > 2 then
            if not gpu_seen then fact.nx_gpu_on = false; text.nx_gpu_value = "N/A" end
            return
        end
        launch("cat", { "/sys/class/drm/card" .. i .. "/device/gpu_busy_percent" }, function(out)
            local value = sysinfo.gpu_busy(out)
            if value ~= nil then
                gpu_seen = true
                fact.nx_gpu_on = true
                fact.nx_gpu = value
                text.nx_gpu_value = string.format("%d%%", math.floor(value * 100 + 0.5))
            end
            read_gpu(i + 1)
        end)
    end
    read_gpu(0)
    launch("cat", { "/proc/meminfo" }, function(out)
        local fraction, used, total = sysinfo.mem(out)
        if fraction ~= nil and used ~= nil and total ~= nil then
            fact.nx_ram_on = true
            fact.nx_ram = math.max(0, math.min(1, fraction))
            fact.nx_ram_used_gib, fact.nx_ram_total_gib = used, total
            text.nx_ram_value = string.format("%.1f / %.1f GiB", used, total)
        end
    end)
    launch("df", { "-Pk", "/" }, function(out)
        local disk = telemetry.disk(out)
        if disk then
            fact.nx_disk_on = true
            fact.nx_disk = disk.used_fraction
            text.nx_disk_value = string.format("%d%% used", disk.percent)
        end
    end)
    launch("cat", { "/proc/net/dev" }, function(out)
        if not out then return end
        local rx, tx = sysinfo.net(out)
        if net_previous then
            local rx_rate = math.max(0, (rx - net_previous.rx) / 2)
            local tx_rate = math.max(0, (tx - net_previous.tx) / 2)
            fact.nx_net_on = true
            fact.nx_rx, fact.nx_tx = rx_rate, tx_rate
            text.nx_rx_value, text.nx_tx_value = sysinfo.rate(rx_rate), sysinfo.rate(tx_rate)
        end
        net_previous = { rx = rx, tx = tx }
    end)
    launch("sensors", { "-j" }, function(out)
        if not out then fact.nx_temp_on = false; text.nx_temp_value = "N/A"; return end
        local ok, decoded = pcall(json.decode, out)
        local temperature = ok and sysinfo.temp(decoded) or nil
        if temperature then
            fact.nx_temp_on = true
            fact.nx_temp = temperature
            text.nx_temp_value = string.format("%.0f°C", temperature)
        else
            fact.nx_temp_on = false
            text.nx_temp_value = "N/A"
        end
    end)
    after(2000, sample_live)
end
sample_live()

-- ── The controls ────────────────────────────────────────────
-- A wheel asks for a new level every notch; the system is told at most every 40 ms, always
-- the latest. The services remain the source of truth for displayed values. If a command
-- raises an error, the footer reports which operation failed without exposing raw internals.
local notice_serial = 0
local function report_control_failure(label)
    notice_serial = notice_serial + 1
    local serial = notice_serial
    text.nx_notice_text = label .. " FAILED"
    fact.nx_notice = true
    after(2600, function()
        if notice_serial == serial then fact.nx_notice = false end
    end)
end

local function control_call(label, service, value)
    local ok, result
    if value == nil then
        ok, result = pcall(sys.call, service)
    else
        ok, result = pcall(sys.call, service, value)
    end
    if not ok or result == false then report_control_failure(label); return false end
    return true
end

local pending = {}
local flushing = false
local function flush()
    flushing = false
    if pending.vol ~= nil then control_call("VOLUME", "audio.volume", pending.vol) end
    if pending.mic ~= nil then control_call("MICROPHONE", "audio.input", pending.mic) end
    if pending.bri ~= nil then control_call("BRIGHTNESS", "brightness.level", pending.bri) end
    pending = {}
end
local function request(kind, v)
    local n = tonumber(v)
    if not n then return end
    if n < 0 then n = 0 elseif n > 1 then n = 1 end
    if kind == "bri" and n < 0.01 then n = 0.01 end
    pending[kind] = n
    if not flushing then flushing = true; after(40, flush) end
end

on("nx_about", function()
    local on = not fact.nx_about_on
    fact.nx_about_on = on
    if on then fact.nx_audio_on = false end
end)
on("nx_audio", function()
    local on = not fact.nx_audio_on
    fact.nx_audio_on = on
    if on then fact.nx_about_on = false end
end)
on("nx_out_cycle", function()
    local id = nexus.next_device(routes.out)
    if id then control_call("OUTPUT", "audio.default", id) end
end)
on("nx_in_cycle", function()
    local id = nexus.next_device(routes.input)
    if id then control_call("INPUT", "audio.default", id) end
end)
on("nx_mic", function() control_call("MICROPHONE", "audio.input_mute") end)
on("nx_mic_level", function(v) request("mic", v) end)
on("nx_bt", function(v) control_call("BLUETOOTH", "bluetooth.power", tonumber(v) == 1) end)
on("nx_diagnostics_copy", function()
    launch("mooi", { "diagnostics", "copy" }, function(out)
        fact.nx_notice = true
        if out and trim(out) then text.nx_notice_text = trim(out)
        else text.nx_notice_text = "COPY FAILED — install wl-clipboard or xclip" end
        after(3200, function() fact.nx_notice = false end)
    end)
end)

on("text:nx_identity_draft", function(value)
    if type(value) == "string" then text.nx_identity_draft = value end
end)

on("nx_identity_edit", function()
    fact.nx_identity_edit_on = true
    text.nx_identity_draft = settings.nexus.identity and settings.nexus.identity.name or "mooi system"
    focus("nx_identity_draft")
end)

on("nx_identity_cancel", function()
    fact.nx_identity_edit_on = false
    focus()
end)

on("nx_identity_save", function()
    local value = trim(text.nx_identity_draft)
    if not value then
        fact.nx_notice = true
        text.nx_notice_text = "Enter a system name before saving"
        after(2600, function() fact.nx_notice = false end)
        return
    end
    if #value > 48 or value:find("[%c]") then
        fact.nx_notice = true
        text.nx_notice_text = "Name must be plain text, 48 characters max"
        after(2600, function() fact.nx_notice = false end)
        return
    end
    if tostring(sys.ask("env", "MOOI_SAFE") or "") == "1" then
        fact.nx_identity_edit_on = false
        focus()
        fact.nx_notice = true
        text.nx_notice_text = "Safe mode: identity not saved"
        after(2600, function() fact.nx_notice = false end)
        return
    end
    if type(settings.nexus) ~= "table" then settings.nexus = {} end
    if type(settings.nexus.identity) ~= "table" then settings.nexus.identity = {} end
    local previous = settings.nexus.identity.name
    settings.nexus.identity.name = value
    local ok = pcall(sys.call, "files.write", FILE, settings)
    if ok then
        sync_identity()
        fact.nx_identity_edit_on = false
        focus()
        fact.nx_notice = true
        text.nx_notice_text = "System identity saved"
    else
        settings.nexus.identity.name = previous
        fact.nx_notice = true
        text.nx_notice_text = "Could not save identity settings"
    end
    after(2600, function() fact.nx_notice = false end)
end)

local function choose_identity_image(kind)
    if tostring(sys.ask("env", "MOOI_SAFE") or "") == "1" then
        fact.nx_notice = true
        text.nx_notice_text = "Image import is disabled in safe mode"
        after(2600, function() fact.nx_notice = false end)
        return
    end
    local ok = pcall(run, "zenity", {
        "--file-selection",
        "--title=Choose system " .. kind,
        "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.avif"
    }, function(path, code)
        if code ~= 0 or not trim(path) then return end
        launch("mooi", { "identity", kind, trim(path) }, function(out)
            if out then
                settings = config.parse(read(FILE), json.decode)
                sync_identity()
                fact.nx_notice = true
                text.nx_notice_text = string.upper(kind) .. " IMAGE UPDATED"
            else
                fact.nx_notice = true
                text.nx_notice_text = "Image import failed; check file type and mooi command"
            end
            after(3000, function() fact.nx_notice = false end)
        end)
    end)
    if not ok then
        fact.nx_notice = true
        text.nx_notice_text = "Install zenity to use the image picker"
        after(3000, function() fact.nx_notice = false end)
    end
end

on("nx_identity_avatar", function() choose_identity_image("avatar") end)
on("nx_identity_banner", function() choose_identity_image("banner") end)
on("nx_vol", function(v) request("vol", v) end)
on("nx_bri", function(v) request("bri", v) end)
on("nx_mute", function() control_call("MUTE", "audio.mute") end)
on("nx_media", function(v)
    local label, service = nexus.media_action(v)
    if service then control_call(label, service) end
end)

-- Pinned: a press toggles the setting and writes it, so the Nexus opens pinned next time.
-- If the write is refused the press is undone, and the plate keeps saying what is true.
on("nx_pin", function()
    if type(settings.nexus) ~= "table" then settings.nexus = { pinned = false } end
    local pinned = not settings.nexus.pinned
    settings.nexus.pinned = pinned
    if tostring(sys.ask("env", "MOOI_SAFE") or "") ~= "1" then
        local ok = pcall(sys.call, "files.write", FILE, settings)
        if not ok then
            settings.nexus.pinned = not pinned
            return
        end
    end
    fact.nx_pinned = pinned
end)

-- The entrance: the plate unfolds under the mark (the scene's springs).
fact.nx_open = 1

-- ×, Escape, or a press outside the plate: it leaves the way it came, then the program ends
-- and the compositor gives the keyboard back to whatever is under it.
on("nx_close", function()
    if fact.nx_open == 0 then return end
    fact.nx_open = 0
    after(240, function() run("pleamar", { "--say", "mooi-nexus", "quit" }) end)
end)

-- ── Node model (D90+) ─────────────────────────────────────
-- Every module is a node that can be moved, focused, and rearranged.
-- The node registry maps module ids to definitions; node state tracks
-- position, visibility, and expansion.

-- Node registry: module id → {x, y, expanded, visible, scale}
-- Initially populated from layout; users can drag to reposition.
local node_registry = {}

-- Which node is focused at center (0-indexed, -1 when none)
fact.nx_node_focus = -1

-- Distance field for reorganizing nodes around center
fact.nx_focus_distance = 0

-- Which layout variant: 0=circuit, 1=spiral, 2=focus, 3=minimal
fact.nx_layout_variant = 0

-- Number of modules/nodes in the workspace
fact.nx_node_count = 6

-- Global node visibility toggle
fact.nx_node_visible = true

-- Whether nodes are in expanded layout
fact.nx_node_expanded = false

-- Number of active connections between nodes
fact.nx_connection_count = 0

-- Connection mode: 0=circuit, 1=radial, 2=hierarchical
fact.nx_connection_mode = 0

-- Whether connections are visible
fact.nx_connection_visible = true

-- Whether connection animation is running
fact.nx_cable_animating = false

-- The node currently focused at center (its id, or false when none)
fact.nx_node_focus_id = false

-- Module library state
fact.nx_module_count = 6
fact.nx_module_selected = 0
fact.nx_module_hide = false
fact.nx_module_minimize = false
fact.nx_module_restore = false

-- Profile banner and view modes
fact.nx_banner_title = 0
fact.nx_banner_tagline = 0
fact.nx_view_mode = 0
fact.nx_view_saved = false
fact.nx_minimode = false

-- Live system integrations
fact.nx_integration_ram = false
fact.nx_integration_cpu = false
fact.nx_integration_gpu = false
fact.nx_integration_disk = false
fact.nx_integration_network = false
fact.nx_integration_telemetry = false
fact.nx_integration_refresh = 0
fact.nx_integration_error = false
fact.nx_integration_lastupdate = 0

-- Visual polish
fact.nx_reduced_motion = false
fact.nx_connection_width = 2
fact.nx_node_radius = 16
fact.nx_node_selected = false
fact.nx_undo_pending = false
fact.nx_redo_pending = false
fact.nx_keyboard_focus = -1
fact.nx_motion_enabled = true

-- Focus a node at center, reorganizing surrounding nodes
local function focus_node(node_id)
    fact.nx_node_focus = node_id
    fact.nx_node_focus_id = node_id
    fact.nx_layout_variant = 2 -- focus layout
    -- Reorganize surrounding nodes in a spiral or circuit pattern
    -- This is handled by the scene's draw logic based on nx_layout_variant
end

-- Cycle through layout variants
local function cycle_layout_variant()
    fact.nx_layout_variant = fact.nx_layout_variant + 1
    if fact.nx_layout_variant > 3 then
        fact.nx_layout_variant = 0
    end
end

-- Toggle node visibility
local function toggle_node_visibility()
    fact.nx_node_visible = not fact.nx_node_visible
end

-- Expand/collapse nodes
local function toggle_node_expand()
    fact.nx_node_expanded = not fact.nx_node_expanded
end

-- Add a module as a node
local function add_node(module_id, x, y)
    node_registry[module_id] = {x = x or 0, y = y or 0, expanded = false, visible = true, scale = 1}
    fact.nx_node_count = fact.nx_node_count + 1
end

-- Remove a node
local function remove_node(module_id)
    node_registry[module_id] = nil
    fact.nx_node_count = math.max(0, fact.nx_node_count - 1)
end

-- Update node position
local function set_node_position(module_id, x, y)
    if node_registry[module_id] then
        node_registry[module_id].x = x
        node_registry[module_id].y = y
    end
end

-- Get node position
local function get_node_position(module_id)
    if node_registry[module_id] then
        return node_registry[module_id].x, node_registry[module_id].y
    end
    return 0, 0
end

-- Select a node (keyboard focus)
local function select_node(module_id)
    fact.nx_keyboard_focus = module_id
    focus_node(module_id)
end

-- Deselect keyboard focus
local function deselect_node()
    fact.nx_keyboard_focus = -1
    fact.nx_node_focus = -1
end

-- Undo pending action
local function set_undo_pending(state)
    fact.nx_undo_pending = state
end

-- Redo pending action
local function set_redo_pending(state)
    fact.nx_redo_pending = state
end

-- Toggle reduced motion
local function toggle_reduced_motion()
    fact.nx_reduced_motion = not fact.nx_reduced_motion
end

-- Integrate system data
local function update_integration_ram(enabled)
    fact.nx_integration_ram = enabled
    fact.nx_integration_lastupdate = os.time()
end

local function update_integration_cpu(enabled)
    fact.nx_integration_cpu = enabled
    fact.nx_integration_lastupdate = os.time()
end

local function update_integration_gpu(enabled)
    fact.nx_integration_gpu = enabled
    fact.nx_integration_lastupdate = os.time()
end

local function update_integration_disk(enabled)
    fact.nx_integration_disk = enabled
    fact.nx_integration_lastupdate = os.time()
end

local function update_integration_network(enabled)
    fact.nx_integration_network = enabled
    fact.nx_integration_lastupdate = os.time()
end

local function update_integration_telemetry(enabled)
    fact.nx_integration_telemetry = enabled
    fact.nx_integration_lastupdate = os.time()
end
