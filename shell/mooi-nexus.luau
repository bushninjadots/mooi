-- Control Nexus (D65): the system command centre, a program of its own. The scene
-- (`mooi-nexus.plm`) draws the plate and reads the bar's own services; this file paints the
-- shell's colours into it, keeps the player's text fields, and is the only place that calls
-- the system. The data folder is mooi's (bin/mooi links mooi-nexus to it), so settings.json
-- and palette.json are shared with the bar and a wallpaper change re-lights the plate too.

local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")
local nexus = require("lib/nexus")
local nexusnode = require("lib/nexusnode")
local nexuslayout = require("lib/nexuslayout")
local nexusgraph = require("lib/nexusgraph")
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
-- The appearance's brightness and contrast are applied here, to the roles themselves, so a
-- change reaches every surface the scene draws without a hex anywhere in the markup.
local look_bright, look_contrast = 1, 1

local function painted(v)
    v = 0.5 + (v * look_bright - 0.5) * look_contrast
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function paint()
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"] = painted(c.r)
        fact["fr_" .. role .. "_g"] = painted(c.g)
        fact["fr_" .. role .. "_b"] = painted(c.b)
    end
end
paint()
pcall(sys.watch, "files:" .. PALETTE, function()
    palette = read(PALETTE, "json")
    paint()
end)
-- ── The node workspace (D76) ───────────────────────────────
-- The plate's eleven modules are catalogue nodes now. The logic owns the arrangement,
-- its geometry and the selection; the scene draws the rows published here and sends a
-- press, a drag or a key back as an event. Facts carry what a rule can compare; text
-- fields carry what it only draws. Nothing here invents a reading: an absent provider
-- leaves its node out of the model, and the module library can say why.
local present = { battery = false, brightness = false }
local live = {
    volume = 0, muted = false, input = 0, input_muted = false,
    bright = 0, bright_on = false,
    power = 0, power_on = false, charging = false,
    net_on = false, net_name = "", net_kind = "none",
    bt_on = false, bt_present = false,
    ws = 1, time = "--:--", date = "",
}
local arrs, active_i, sel, last_arr_count = {}, 1, 0, nil
local mix, spaces = {}, {}

-- What the connection layer is doing: the hovered node, the hovered trace and the picked one.
-- The picked trace is kept by its id, because a republish can reorder the drawn list.
local hover_node, hover_edge, picked_edge = 0, 0, nil
local drawn_edges = {}
-- The module library's search, kept here because a text field can be drawn but not
-- compared in the scene; the filtered rows are what the library panel receives.
local lib_query = ""
-- The library shows a page at a time; the rest are one press away rather than lost. How
-- many rows a page holds follows the room the panel has on this screen, so a short band
-- gets four rows and a tall one gets ten, and no row is ever cut by the panel's foot.
local lib_page = 0

local function lib_page_size()
    local ch = tonumber(fact.nx_ch) or 0
    if ch <= 0 then return 10 end
    if ch < 380 then return 4 end
    if ch < 520 then return 6 end
    if ch < 660 then return 8 end
    return 10
end
-- Which arrangement name the rename field was last seeded with.
local draft_for = nil

-- Appearance is stored by role name, because a role name is what the scene's tokens read;
-- the scene gets the place in the list and picks the colour itself.
local ACCENTS = { "phos", "flare", "ember", "trace_lit" }
local ACCENT_INDEX = { phos = 1, flare = 2, ember = 3, trace_lit = 4 }
local ACCENT_TONE = { phos = 1, trace_lit = 1, flare = 2, ember = 3 }
local STYLES = { "circuit", "curved", "direct" }
local STYLE_INDEX = { circuit = 1, curved = 2, direct = 3 }

local function clamp(v, low, high)
    if v < low then return low end
    if v > high then return high end
    return v
end

-- The layout's own undo: snapshots of the arrangements taken before each edit, and the
-- steps a redo can walk forward again. Any new edit clears the forward list.
local past, future = {}, {}
local function remember()
    nexusnode.remember(past, arrs)
    future = {}
end

-- Switching an arrangement moves every node to its new slot; 320 ms of steps makes it a
-- move rather than a cut, and the arrangement itself is already the destination, so a
-- drag taken mid-flight lands on the real position.
local morph = nil

-- publish is defined with the model below; the morph steps are declared first, so the
-- name is reserved rather than reached for as a global.
local publish

local function positions(a)
    local map = {}
    if a then
        for _, node in ipairs(a.nodes) do
            map[node.type] = { x = node.x, y = node.y, w = node.w, h = node.h }
        end
    end
    return map
end

local function start_morph(from)
    if not from or next(from) == nil then return end
    -- Reduced motion is a setting, not a suggestion: the arrangement changes in one step.
    if fact.nx_motion == false then morph = nil; publish(); return end
    morph = { from = from, t = 0 }
    local function step()
        if not morph then return end
        morph.t = math.min(1, morph.t + 0.125)
        if morph.t >= 1 then morph = nil end
        publish()
        if morph then after(40, step) end
    end
    step()
end

-- Defined with the controls below; the mixer's handlers are declared before it, so the
-- name is reserved here rather than reached for as a global at press time.
local report_control_failure

local function node_list() return arrs[active_i] end

local function edge_live(activity)
    if activity == "cpu" then return fact.nx_cpu_on == true end
    if activity == "memory" then return fact.nx_ram_on == true end
    if activity == "gpu" then return fact.nx_gpu_on == true end
    if activity == "thermal" then return fact.nx_temp_on == true end
    if activity == "power" then return live.power_on end
    if activity == "storage" then return fact.nx_disk_on == true end
    if activity == "network" then return fact.nx_net_on == true end
    if activity == "media" then return fact.nx_has == true end
    return false
end

local function present_set()
    return {
        battery = present.battery,
        brightness = present.brightness,
        media = fact.nx_has == true,
        gpu = fact.nx_gpu_on == true,
        sensors = fact.nx_temp_on == true,
    }
end

local function safe_write()
    if tostring(sys.ask("env", "MOOI_SAFE") or "") == "1" then return false end
    local ok = pcall(sys.call, "files.write", FILE, settings)
    if not ok then
        fact.nx_notice = true
        text.nx_notice_text = "Could not save the Nexus layout"
        after(2600, function() fact.nx_notice = false end)
    end
    return ok
end

-- One write per gesture, never per frame: the scene sends a drop or a resize release,
-- and the arrangement on disk is the one the model was published from.
local function save()
    if type(settings.nexus) ~= "table" then settings.nexus = {} end
    local a = node_list()
    settings.nexus.arrangements = arrs
    if a then
        settings.nexus.arrangement = a.name
        settings.nexus.focus = a.focus
        settings.nexus.mode = a.mode
        settings.nexus.banner = { mode = a.banner }
    end
    return safe_write()
end

local function str(value, fallback)
    if type(value) == "string" and value ~= "" then return value end
    return fallback
end

local function choose()
    arrs = nexusnode.normalize_arrangements((type(settings.nexus) == "table" and settings.nexus.arrangements) or {})
    local seeded = false
    if #arrs == 0 then
        arrs = nexusnode.seed_arrangements(type(settings.nexus) == "table" and settings.nexus or {})
        seeded = true
    end
    if #arrs == 0 then
        arrs = nexusnode.seed_arrangements({})
        seeded = true
    end
    active_i = 1
    local want = type(settings.nexus) == "table" and settings.nexus.arrangement or nil
    if type(want) == "string" then
        for i, a in ipairs(arrs) do
            if a.name == want then active_i = i; break end
        end
    end
    last_arr_count = #arrs
    return seeded
end

-- The compact body of a node: one reading, one line saying what it is, and a bar when
-- the reading has a range. A node with no provider is never published at all.
local function content(node, def, total)
    local tone, value, note, bar, baron = 1, "—", "", 0, false
    local t = node.type
    if t == "core" then
        value = string.upper((node_list() and node_list().mode) or "circuit")
        note = string.format("%d NODES", total)
    elseif t == "system" then
        value = str(text.nx_cpu_value, "—")
        note = str(text.nx_cpu_label, "SYSTEM")
        bar, baron = fact.nx_cpu or 0, fact.nx_cpu_on == true
        if not baron then tone = 0 end
    elseif t == "cpu" then
        value = str(text.nx_cpu_value, "—")
        note = str(text.nx_cpu_label, "PROCESSOR LOAD")
        bar, baron = fact.nx_cpu or 0, fact.nx_cpu_on == true
        if not baron then tone = 0 end
    elseif t == "memory" then
        value = str(text.nx_ram_value, "—")
        note = "OF TOTAL MEMORY"
        bar, baron = fact.nx_ram or 0, fact.nx_ram_on == true
        if not baron then tone = 0 end
    elseif t == "gpu" then
        value = str(text.nx_gpu_value, "N/A")
        note = "GRAPHICS LOAD"
        bar, baron = fact.nx_gpu or 0, fact.nx_gpu_on == true
        if not baron then tone = 0 end
    elseif t == "thermal" then
        value = str(text.nx_temp_value, "N/A")
        note = "THERMAL SENSOR"
        tone = (fact.nx_temp_on == true) and 2 or 0
    elseif t == "storage" then
        value = str(text.nx_disk_value, "—")
        note = "ROOT FILESYSTEM"
        bar, baron, tone = fact.nx_disk or 0, fact.nx_disk_on == true, 2
        if not baron then tone = 0 end
    elseif t == "network" then
        value = live.net_on and (live.net_kind == "wifi" and "WIFI" or "WIRED") or "OFFLINE"
        note = "IN " .. str(text.nx_rx_value, "—") .. "  ·  OUT " .. str(text.nx_tx_value, "—")
        tone = live.net_on and 2 or 3
    elseif t == "audio" then
        value = live.muted and "MUTED" or string.format("%d%%", math.floor(live.volume * 100 + 0.5))
        note = str(text.nx_out_name, "OUTPUT DEVICE")
        bar, baron = live.volume, true
        tone = live.muted and 3 or 1
    elseif t == "display" then
        value = live.bright_on and string.format("%d%%", math.floor(live.bright * 100 + 0.5)) or "N/A"
        note = str(text.nx_display_value, "DISPLAY")
        bar, baron = live.bright, live.bright_on
        if not baron then tone = 0 end
    elseif t == "workspaces" then
        value = string.format("%d", live.ws)
        note = "CURRENT WORKSPACE"
        tone = 1
    elseif t == "media" then
        value = str(text.nx_title, "No media session")
        note = str(text.nx_artist, "NOTHING IS PLAYING")
        bar, baron = fact.nx_progress or 0, fact.nx_has == true
        if not baron then tone = 0 end
    elseif t == "clock" then
        value = str(live.time, "--:--")
        note = str(live.date, "")
        tone = 2
    elseif t == "power" then
        value = live.power_on and string.format("%d%%", math.floor(live.power + 0.5)) or "N/A"
        note = not live.power_on and "NO BATTERY" or (live.charging and "CHARGING" or "ON BATTERY")
        bar, baron = live.power / 100, live.power_on
        tone = not live.power_on and 0 or (live.charging and 2 or 1)
    end
    return value, note, bar, baron, tone, def.accent
end

-- The detail body of a node: the rows a focused frame draws under its reading. They are
-- the same numbers the plate carried in its old views, moved to the node that owns them,
-- and each one says `N/A` rather than guessing when its provider is absent.
local KINDS = {
    core = 0, system = 1, cpu = 2, memory = 3, gpu = 4, thermal = 5, storage = 6,
    network = 7, audio = 8, display = 9, workspaces = 10, media = 11, clock = 12, power = 13,
}

local function detail_rows(node)
    local t = node.type
    local out = {}
    local function row(label, value)
        out[#out + 1] = { label = label, value = str(value, "N/A") }
    end
    if t == "core" then
        row("MODE", string.upper(node_list() and node_list().mode or "circuit"))
        row("FOCUS", str(text.nx_focus_name, "Core"))
        row("NODES", string.format("%d ON CANVAS", fact.nx_node_count or 0))
        row("LAYOUT", str(text.nx_arrangement_name, "—"))
    elseif t == "system" then
        row("DISTRIBUTION", text.nx_distro)
        row("KERNEL", text.nx_kernel)
        row("UPTIME", text.nx_uptime)
        row("CPU", text.nx_cpu_model)
        row("MEMORY", text.nx_ram_value)
        row("ROOT STORAGE", text.nx_disk_value)
        row("DISPLAYS", text.nx_display_value)
        row("GRAPHICS", text.nx_gpu_value)
    elseif t == "cpu" then
        row("LOAD", text.nx_cpu_value)
        row("CORES", text.nx_cpu_label)
        row("MEMORY", text.nx_ram_value)
        row("UPTIME", text.nx_uptime)
    elseif t == "memory" then
        row("USED", text.nx_ram_value)
        row("LOAD", text.nx_cpu_value)
        row("TEMPERATURE", text.nx_temp_value)
        row("UPTIME", text.nx_uptime)
    elseif t == "gpu" then
        row("LOAD", text.nx_gpu_value)
        row("TEMPERATURE", text.nx_temp_value)
        row("DISPLAYS", text.nx_display_value)
        row("KERNEL", text.nx_kernel)
    elseif t == "thermal" then
        row("TEMPERATURE", text.nx_temp_value)
        row("LOAD", text.nx_cpu_value)
        row("MEMORY", text.nx_ram_value)
        row("UPTIME", text.nx_uptime)
    elseif t == "storage" then
        row("ROOT STORAGE", text.nx_disk_value)
        row("MEMORY", text.nx_ram_value)
        row("UPTIME", text.nx_uptime)
        row("HOST", text.nx_host)
    elseif t == "network" then
        row("LINK", live.net_on and (live.net_kind == "wifi" and "WIFI" or "WIRED") or "OFFLINE")
        row("RECEIVE", text.nx_rx_value)
        row("SEND", text.nx_tx_value)
        row("HOST", text.nx_host)
    elseif t == "audio" then
        row("OUTPUT", text.nx_out_name)
        row("INPUT", text.nx_in_name)
        row("MICROPHONE", live.input_muted and "MUTED" or string.format("%d%%", math.floor(live.input * 100 + 0.5)))
        row("BLUETOOTH", live.bt_present and (live.bt_on and "ON" or "OFF") or "N/A")
    elseif t == "display" then
        row("BRIGHTNESS", live.bright_on and string.format("%d%%", math.floor(live.bright * 100 + 0.5)) or "N/A")
        row("DISPLAYS", text.nx_display_value)
        row("GRAPHICS", text.nx_gpu_value)
        row("KERNEL", text.nx_kernel)
    elseif t == "media" then
        row("TITLE", text.nx_title)
        row("ARTIST", text.nx_artist)
        row("ALBUM", text.nx_album)
        row("PLAYER", text.nx_player)
    elseif t == "clock" then
        row("TIME", live.time)
        row("DATE", live.date)
        row("UPTIME", text.nx_uptime)
        row("HOST", text.nx_host)
    elseif t == "power" then
        row("CHARGE", live.power_on and string.format("%d%%", math.floor(live.power + 0.5)) or "N/A")
        row("STATE", not live.power_on and "NO BATTERY" or (live.charging and "CHARGING" or "ON BATTERY"))
        row("LOAD", text.nx_cpu_value)
        row("TEMPERATURE", text.nx_temp_value)
    end
    return out
end

function publish()
    local a = node_list()
    local p = present_set()
    local mode = a and a.mode or "circuit"
    local focus = a and a.focus or "core"
    local shown, total = 0, 0
    if a then
        for _, node in ipairs(a.nodes) do
            local ok = nexusnode.available(node.type, p)
            if ok then
                total = total + 1
                if node.vis and (mode ~= "minimal" or node.essential) then shown = shown + 1 end
            end
        end
    end

    local rows, removed = {}, {}
    if a then
        for i, node in ipairs(a.nodes) do
            local def = nexusnode.get(node.type)
            local ok = nexusnode.available(node.type, p)
            if ok and def then
                if node.vis and (mode ~= "minimal" or node.essential) then
                    local value, note, bar, baron, tone = content(node, def, shown)
                    local detail = detail_rows(node)
                    local px, py, pw, ph = node.x, node.y, node.w, node.h
                    if morph then
                        local step = nexuslayout.blend(morph.from[node.type] or node, node, morph.t)
                        px, py, pw, ph = step.x, step.y, step.w, step.h
                    end
                    local entry = {
                        id = i, key = def.id, title = def.title,
                        value = value, note = note,
                        x = px, y = py, w = pw, h = ph,
                        tone = tone, bar = math.max(0, math.min(1, bar)), baron = baron,
                        mini = node.min == true, sel = i == sel, focus = node.type == focus,
                        minw = def.min.w, minh = def.min.h, maxw = def.max.w, maxh = def.max.h,
                        kind = KINDS[def.id] or 0, rows = #detail, endsel = false,
                    }
                    for k = 1, 8 do
                        entry["r" .. k .. "l"] = detail[k] and detail[k].label or ""
                        entry["r" .. k .. "v"] = detail[k] and detail[k].value or ""
                    end
                    rows[#rows + 1] = entry
                elseif not node.vis then
                    removed[#removed + 1] = { id = i, slot = #removed + 1, key = def.id, title = def.title }
                end
            end
        end
    end

    if sel > 0 then
        local holds = false
        for _, r in ipairs(rows) do if r.id == sel then holds = true break end end
        if not holds then sel = 0 end
    end

    -- The connection layer: only edges whose two ends are on the canvas, routed once here
    -- so the scene draws the same path every frame instead of solving it. A hidden edge is
    -- one the user put away; a dim one is unrelated to the focused node.
    local by_type = {}
    for _, r in ipairs(rows) do by_type[r.key] = r end
    local types = {}
    for key in pairs(by_type) do types[key] = true end
    local hidden = {}
    if a and type(a.edges) == "table" and type(a.edges.hidden) == "table" then
        for _, id in ipairs(a.edges.hidden) do hidden[id] = true end
    end
    local style = a and a.edges and a.edges.style or "circuit"
    local edges, sel_index = {}, 0
    drawn_edges = {}
    for _, edge in ipairs(nexusgraph.instantiate(types)) do
        local from, to = by_type[edge.from], by_type[edge.to]
        if from and to and not hidden[edge.id] then
            local active = edge_live(edge.activity)
            if mode ~= "minimal" or active then
                local pts = nexusgraph.route(
                    { x = from.x, y = from.y, w = from.w, h = from.h },
                    { x = to.x, y = to.y, w = to.w, h = to.h },
                    { style = style, clearance = 12, step = 12 })
                if #pts >= 2 then
                    local id = #edges + 1
                    drawn_edges[id] = edge.id
                    local hot = (hover_node > 0 and (from.id == hover_node or to.id == hover_node))
                        or picked_edge == edge.id
                        or hover_edge == id
                    local mid = pts[math.max(1, math.floor((#pts + 1) / 2))]
                    local row = {
                        id = id, key = edge.id,
                        from_id = from.id, to_id = to.id,
                        n = #pts, trunk = edge.kind == "trunk",
                        hot = hot, dim = focus ~= "core" and edge.from ~= focus and edge.to ~= focus,
                        active = active,
                        label = edge.label, meaning = edge.meaning,
                        mx = mid.x, my = mid.y,
                        x1 = pts[1].x, y1 = pts[1].y,
                        x2 = pts[2].x, y2 = pts[2].y,
                        x3 = (pts[3] or pts[#pts]).x, y3 = (pts[3] or pts[#pts]).y,
                        x4 = (pts[4] or pts[#pts]).x, y4 = (pts[4] or pts[#pts]).y,
                    }
                    edges[#edges + 1] = row
                    if edge.id == picked_edge then
                        sel_index = id
                        from.endsel = true
                        to.endsel = true
                    end
                end
            end
        end
    end
    if picked_edge and #edges == 0 then picked_edge = nil end

    -- The module library (S5): every type the catalogue declares, with the reason it is not
    -- drawing right now. `state` is 0 on canvas, 1 removed from this arrangement —the row
    -- carries the node index the restore event takes— 2 not connected on this machine, and
    -- 3 available but not part of this arrangement, which the row offers to add.
    local library = {}
    if a then
        local at = {}
        for i, node in ipairs(a.nodes) do at[node.type] = { index = i, node = node } end
        for code, def in ipairs(nexusnode.TYPES) do
            local ok, why = nexusnode.available(def.id, p)
            local entry = at[def.id]
            local state, note = 0, "ON CANVAS"
            if not ok then
                state, note = 2, str(why, "NOT CONNECTED")
            elseif not entry then
                state, note = 3, "PRESS TO ADD IT"
            elseif not entry.node.vis then
                state, note = 1, "REMOVED FROM THE LAYOUT"
            elseif mode == "minimal" and not entry.node.essential then
                note = "ESSENTIAL ONLY"
            end
            local haystack = string.lower(def.title .. " " .. def.category)
            if lib_query == "" or string.find(haystack, lib_query, 1, true) then
                library[#library + 1] = {
                    slot = #library + 1, id = entry and entry.index or 0, code = code,
                    key = def.id, title = def.title, category = string.upper(def.category),
                    state = state, note = note, tone = ACCENT_TONE[def.accent] or 1,
                }
            end
        end
    end

    -- The traces the user put away, with the meaning the graph gives each one, so the
    -- connection layer can offer them back one at a time and not only all at once.
    local put_away = {}
    if a and type(a.edges) == "table" and type(a.edges.hidden) == "table" then
        for slot, id in ipairs(a.edges.hidden) do
            local label, meaning = id, "hidden trace"
            for _, edge in ipairs(nexusgraph.EDGES) do
                if edge.id == id then label, meaning = edge.label, edge.meaning; break end
            end
            put_away[#put_away + 1] = { id = slot, key = id, label = label, meaning = meaning }
        end
    end

    local chips = {}
    for i, item in ipairs(arrs) do
        chips[#chips + 1] = { id = i, name = item.name, active = i == active_i }
    end

    local streams = {}
    for i, row in ipairs(mix) do
        local sid = tonumber(row.id) or 0
        streams[#streams + 1] = {
            id = i,
            sid = sid,
            name = str(row.name, "STREAM"),
            note = str(row.title, ""),
            level = tonumber(row.volume) or 0,
            muted = row.muted == 1,
        }
    end

    local blocks = {}
    for i, block in ipairs(spaces) do
        blocks[i] = { id = block.id, slot = i, label = block.label, windows = block.windows, active = block.active }
    end

    model.nx_nodes = rows
    model.nx_removed = removed
    model.nx_lib = library
    model.nx_hidden = put_away
    model.nx_edges = edges
    model.nx_arrs = chips
    model.nx_mix = streams
    model.nx_ws = blocks
    fact.nx_mix_count = #streams
    fact.nx_ws_count = #blocks
    local hidden_count = 0
    if a and type(a.edges) == "table" and type(a.edges.hidden) == "table" then
        hidden_count = #a.edges.hidden
    end
    fact.nx_edge_count = #edges
    fact.nx_edge_sel = sel_index
    fact.nx_edges_hidden = hidden_count
    fact.nx_edge_width = a and a.edges and a.edges.width or 1
    fact.nx_edge_labels = not (type(settings.nexus) == "table" and settings.nexus.edge
        and settings.nexus.edge.labels == false)
    fact.nx_hover = hover_node
    fact.nx_hover_edge = hover_edge
    fact.nx_arrangement_count = #arrs
    fact.nx_node_count = shown
    fact.nx_node_total = total
    fact.nx_removed_count = #removed
    local per_page = lib_page_size()
    local pages = math.max(1, math.ceil(#library / per_page))
    if lib_page > pages - 1 then lib_page = pages - 1 end
    if lib_page < 0 then lib_page = 0 end
    fact.nx_lib_page_size = per_page
    fact.nx_lib_count = #library
    fact.nx_lib_total = #nexusnode.TYPES
    fact.nx_lib_page = lib_page + 1
    fact.nx_lib_pages = pages
    fact.nx_hidden_count = #put_away
    fact.nx_undo_depth = #past
    fact.nx_redo_depth = #future
    fact.nx_morph = morph and 1 or 0
    fact.nx_sel = sel
    fact.nx_focus = focus
    fact.nx_mode = mode
    fact.nx_banner_mode = a and a.banner or "compact"
    fact.nx_grid = a and a.appearance and a.appearance.grid ~= false or false
    local look = a and a.appearance or {}
    local bright = clamp((tonumber(look.brightness) or 100) / 100, 0.6, 1.4)
    local contrast = clamp((tonumber(look.contrast) or 100) / 100, 0.6, 1.4)
    if bright ~= look_bright or contrast ~= look_contrast then
        look_bright, look_contrast = bright, contrast
        paint()
    end
    fact.nx_accent = ACCENT_INDEX[look.accent or "phos"] or 1
    fact.nx_glow = tonumber(look.glow) or 60
    fact.nx_bright = tonumber(look.brightness) or 100
    fact.nx_contrast = tonumber(look.contrast) or 100
    fact.nx_opacity = tonumber(look.opacity) or 100
    fact.nx_edge_style = STYLE_INDEX[style] or 1
    fact.nx_motion = look.motion ~= false
    text.nx_accent_name = string.upper(str(look.accent, "phos"))
    local picked_row = nil
    for _, r in ipairs(rows) do
        if r.id == sel then picked_row = r; break end
    end
    fact.nx_sel_on = picked_row and 1 or 0
    fact.nx_sel_kind = picked_row and picked_row.kind or 0
    text.nx_sel_title = picked_row and picked_row.title or "NO NODE SELECTED"
    text.nx_sel_note = picked_row and string.format("%d × %d", picked_row.w, picked_row.h) or "PRESS A NODE"
    text.nx_arrangement_name = a and a.name or "—"
    if draft_for ~= (a and a.name) then
        draft_for = a and a.name or nil
        text.nx_arr_draft = a and a.name or ""
    end
    text.nx_banner_name = string.upper(a and a.banner or "compact")
    local focus_def = nexusnode.get(focus)
    text.nx_focus_name = focus_def and focus_def.title or "Core"
    text.nx_mode_name = string.upper(mode)

    local bits = {}
    if fact.nx_cpu_on then bits[#bits + 1] = "LOAD " .. str(text.nx_cpu_value, "—") end
    if fact.nx_ram_on then bits[#bits + 1] = "MEM " .. str(text.nx_ram_value, "—") end
    if fact.nx_temp_on then bits[#bits + 1] = str(text.nx_temp_value, "—") end
    if fact.nx_net_on then
        bits[#bits + 1] = "IN " .. str(text.nx_rx_value, "—") .. " · OUT " .. str(text.nx_tx_value, "—")
    end
    text.nx_status = #bits > 0 and table.concat(bits, "   ·   ") or "NO LIVE READINGS"
end

local function touch(write)
    if write then save() end
    publish()
end

local function canvas_of()
    local w = tonumber(fact.nx_cw) or 0
    local h = tonumber(fact.nx_ch) or 0
    if w <= 0 or h <= 0 then return nil end
    return { w = w, h = h }
end

local function index_of(value)
    local i = math.floor(tonumber(value) or 0)
    local a = node_list()
    if not a or not a.nodes[i] then return nil, nil end
    return i, a.nodes[i]
end

-- A node press with no drag: select it. The same press on the selected node clears it,
-- so a click on empty canvas and a second click agree about what is selected.
on("nx_select", function(v)
    local i = index_of(v)
    if not i then return end
    sel = (sel == i) and 0 or i
    publish()
end)

-- A drag that moved: the scene has already clamped to the canvas and published the
-- proposed origin, so the logic snaps and records once, on release.
on("nx_drop", function(v)
    local i, node = index_of(v)
    local canvas = canvas_of()
    if not i or not canvas then return end
    sel = i
    local x = tonumber(fact.nx_gx) or node.x
    local y = tonumber(fact.nx_gy) or node.y
    remember()
    if nexuslayout.place(node, x, y, canvas, 8) then
        touch(true)
    else
        table.remove(past)
        publish()
    end
end)

on("nx_resize", function(v)
    local i, node = index_of(v)
    local canvas = canvas_of()
    if not i or not canvas then return end
    remember()
    local changed = nexuslayout.resize(node, tonumber(fact.nx_rw) or node.w, tonumber(fact.nx_rh) or node.h, 8)
    local moved = nexuslayout.place(node, node.x, node.y, canvas, 0)
    if changed or moved then touch(true) else table.remove(past); publish() end
end)

on("nx_min", function(v)
    local i, node = index_of(v)
    if not i then return end
    remember()
    node.min = not node.min
    touch(true)
end)

-- Focus at centre: the chosen node takes the middle at its detail size and the node
-- that was there inherits the vacated slot; every other node keeps its position.
on("nx_focus_node", function(v)
    local i, node = index_of(v)
    local canvas = canvas_of()
    local a = node_list()
    if not i or not canvas or not a then return end
    local from = positions(a)
    remember()
    local out, ok = nexuslayout.focus(a.nodes, node.type, canvas)
    if ok then
        a.nodes = out
        a.focus = node.type
        sel = i
        touch(true)
        start_morph(from)
    else
        a.focus = node.type
        touch(true)
    end
end)

-- Removal is layout-only: the node keeps its slot and its services, and the drawer's
-- REMOVED list can put it back where it was.
on("nx_remove", function(v)
    local i, node = index_of(v)
    local a = node_list()
    if not i or not a then return end
    remember()
    node.vis = false
    if a.focus == node.type then
        local fallback = "core"
        local holds = false
        for _, other in ipairs(a.nodes) do
            if other.vis and other.type == "core" then holds = true end
        end
        if not holds then
            for _, other in ipairs(a.nodes) do
                if other.vis then fallback = other.type; break end
            end
        end
        a.focus = fallback
    end
    if sel == i then sel = 0 end
    touch(true)
end)

on("nx_restore", function(v)
    local i = math.floor(tonumber(v) or 0)
    local canvas = canvas_of()
    local a = node_list()
    if not a or not canvas or not a.nodes[i] then return end
    remember()
    if nexuslayout.restore(a.nodes, i, canvas, 8) then
        sel = i
        touch(true)
    end
end)

-- One place for the strip's short messages, so a refused press always says why.
local function notify(message)
    fact.nx_notice = true
    text.nx_notice_text = message
    after(2800, function() fact.nx_notice = false end)
end

-- The library's ADD row: a type the arrangement simply did not carry yet. The node takes
-- the first grid slot that clears the others, so a press on the fifth library row never
-- lands on top of the clock. Types already in the arrangement are only brought back.
on("nx_lib_add", function(v)
    local code = math.floor(tonumber(v) or 0)
    local def = nexusnode.TYPES[code]
    local a = node_list()
    local canvas = canvas_of()
    if not def or not a or not canvas then return end
    local ok, why = nexusnode.available(def.id, present_set())
    if not ok then notify(string.upper(str(why, "NOT CONNECTED"))); return end
    for i, node in ipairs(a.nodes) do
        if node.type == def.id then
            if not node.vis then
                remember()
                node.vis = true
                touch(true)
            end
            sel = i
            notify(def.title .. " IS ON THE CANVAS")
            publish()
            return
        end
    end
    if #a.nodes >= 16 then notify("SIXTEEN NODES AT MOST"); return end
    local template
    for _, node in ipairs(nexusnode.default_nodes(canvas)) do
        if node.type == def.id then template = node; break end
    end
    remember()
    local from = positions(a)
    local x, y = nexuslayout.free_slot(a.nodes, def.id, canvas, 8)
    local node = template or { type = def.id, w = def.size.w, h = def.size.h, min = false }
    node.x, node.y = x, y
    node.vis = true
    node.min = false
    node.essential = def.essential
    a.nodes[#a.nodes + 1] = node
    sel = #a.nodes
    touch(true)
    start_morph(from)
    notify(def.title .. " ADDED")
end)

-- The module library's search field. The rows are filtered here, because a text field
-- can be drawn in the scene but not compared there.
on("text:nx_lib_query", function(value)
    if type(value) ~= "string" then return end
    lib_query = string.lower((value:gsub("^%s+", ""):gsub("%s+$", "")))
    lib_page = 0
    publish()
end)

-- A page of the library, forward or back. A press past either end stays put.
on("nx_lib_page", function(v)
    local step = tonumber(v) or 0
    lib_page = lib_page + (step > 0 and 1 or -1)
    if lib_page < 0 then lib_page = 0 end
    publish()
end)

-- The size presets of a node: S, M, L and the detail size it takes at the centre. The
-- type's own limits still decide, so a preset never draws outside what the catalogue says.
local function preset_size(def, preset)
    if preset == 1 then return def.min.w, def.min.h end
    if preset == 3 then return def.max.w, def.max.h end
    if preset == 4 then return def.detail.w, def.detail.h end
    return def.size.w, def.size.h
end

on("nx_node_preset", function(v)
    local i, node = index_of(sel)
    local a = node_list()
    local canvas = canvas_of()
    if not i or not a then return end
    local def = nexusnode.get(node.type)
    if not def then return end
    local w, h = preset_size(def, math.floor(tonumber(v) or 2))
    local from = positions(a)
    remember()
    node.w, node.h = nexuslayout.bounds(node.type, w, h)
    if canvas then nexuslayout.place(node, node.x, node.y, canvas, 0) end
    touch(true)
    start_morph(from)
end)

-- RESET NODE: the type's shipped size and the slot the default arrangement gives it.
on("nx_node_reset", function()
    local i, node = index_of(sel)
    local a = node_list()
    if not i or not a then return end
    local canvas = canvas_of() or { w = 1440, h = 860 }
    local home
    for _, d in ipairs(nexusnode.default_nodes(canvas)) do
        if d.type == node.type then home = d; break end
    end
    if not home then return end
    local from = positions(a)
    remember()
    node.w, node.h = home.w, home.h
    nexuslayout.place(node, home.x, home.y, canvas, 8)
    touch(true)
    start_morph(from)
end)

-- One hidden trace back: the panel lists them by slot, so a press restores only that one.
on("nx_edge_show", function(v)
    local slot = math.floor(tonumber(v) or 0)
    local a = node_list()
    if not a or type(a.edges) ~= "table" or type(a.edges.hidden) ~= "table" then return end
    if not a.edges.hidden[slot] then return end
    remember()
    table.remove(a.edges.hidden, slot)
    picked_edge = nil
    touch(true)
end)

-- The arrangement's own management. A new one is the current arrangement under another
-- name; adding, duplicating, renaming and deleting all go through the same memory, so
-- Ctrl+Z takes back a delete as easily as a drag.
local function arrangement_name(base)
    local used = {}
    for _, item in ipairs(arrs) do used[item.name] = true end
    if not used[base] then return base end
    for n = 2, 9 do
        local suffix = " " .. n
        local candidate = string.sub(base, 1, 16 - #suffix) .. suffix
        if not used[candidate] then return candidate end
    end
    return nil
end

local function add_arrangement(copy)
    if #arrs >= 8 then notify("EIGHT ARRANGEMENTS AT MOST"); return end
    remember()
    local name = arrangement_name(copy.name or "LAYOUT")
    if not name then notify("NO ROOM FOR ANOTHER NAME"); return end
    copy.name = name
    arrs[#arrs + 1] = copy
    active_i = #arrs
    sel = 0
    touch(true)
end

on("nx_arr_new", function()
    local a = node_list()
    if not a then return end
    local copy = nexusnode.copy_arrangements({ a })[1]
    if not copy then return end
    copy.name = "LAYOUT"
    add_arrangement(copy)
end)

on("nx_arr_dup", function()
    local a = node_list()
    if not a then return end
    local copy = nexusnode.copy_arrangements({ a })[1]
    if not copy then return end
    copy.name = string.sub(a.name, 1, 12) .. " 2"
    add_arrangement(copy)
end)

on("nx_arr_rename", function()
    local a = node_list()
    if not a then return end
    local draft = type(text.nx_arr_draft) == "string" and text.nx_arr_draft or ""
    draft = string.upper((draft:gsub("^%s+", ""):gsub("%s+$", "")))
    if draft == "" then notify("NAME THE ARRANGEMENT FIRST"); return end
    if #draft > 16 then notify("SIXTEEN CHARACTERS AT MOST"); return end
    if draft == a.name then return end
    for _, item in ipairs(arrs) do
        if item.name == draft then notify("THAT NAME IS ALREADY USED"); return end
    end
    remember()
    a.name = draft
    touch(true)
end)

on("nx_arr_del", function()
    if #arrs <= 1 then notify("ONE ARRANGEMENT MUST STAY"); return end
    remember()
    table.remove(arrs, active_i)
    if active_i > #arrs then active_i = #arrs end
    sel = 0
    touch(true)
end)

-- Appearance is one key and one number: accent, brightness, contrast, glow, grid, edge
-- width, edge style, edge labels, motion and surface opacity. Values are enums and bounded
-- numbers, never colours, so a theme change still reaches every surface.
on("nx_look", function()
    local a = node_list()
    if not a then return end
    if type(a.appearance) ~= "table" then a.appearance = {} end
    local look = a.appearance
    local key = math.floor(tonumber(fact.nx_look_key) or 0)
    local val = tonumber(fact.nx_look_val) or 0
    if key == 1 then
        local at = ACCENT_INDEX[look.accent or "phos"] or 1
        look.accent = ACCENTS[((at - 1 + math.floor(val)) % #ACCENTS) + 1]
    elseif key == 2 then
        look.brightness = math.floor(clamp((tonumber(look.brightness) or 100) + val, 60, 140))
    elseif key == 3 then
        look.contrast = math.floor(clamp((tonumber(look.contrast) or 100) + val, 60, 140))
    elseif key == 4 then
        look.glow = math.floor(clamp((tonumber(look.glow) or 60) + val, 0, 100))
    elseif key == 5 then
        look.grid = not (look.grid ~= false)
    elseif key == 9 then
        look.motion = not (look.motion ~= false)
    elseif key == 10 then
        look.opacity = math.floor(clamp((tonumber(look.opacity) or 100) + val, 40, 100))
    elseif key == 6 then
        if type(a.edges) ~= "table" then a.edges = {} end
        a.edges.width = (tonumber(a.edges.width) == 2) and 1 or 2
    elseif key == 7 then
        if type(a.edges) ~= "table" then a.edges = {} end
        local at = STYLE_INDEX[a.edges.style or "circuit"] or 1
        a.edges.style = STYLES[((at - 1 + math.floor(val)) % #STYLES) + 1]
    elseif key == 8 then
        if type(settings.nexus) ~= "table" then settings.nexus = {} end
        if type(settings.nexus.edge) ~= "table" then settings.nexus.edge = {} end
        settings.nexus.edge.labels = not (settings.nexus.edge.labels ~= false)
    else
        return
    end
    remember()
    touch(true)
end)

-- The canvas the scene is drawing on, published when it first settles and whenever the
-- screen changes size. Only a shrink moves anything: `fit` leaves a canvas that still
-- holds the arrangement alone, so opening on a bigger screen never rearranges the work.
local last_canvas = nil
on("nx_canvas", function()
    local canvas = canvas_of()
    if not canvas then return end
    local a = node_list()
    local changed = false
    if a and last_canvas and (last_canvas.w ~= canvas.w or last_canvas.h ~= canvas.h) then
        local fitted = nexuslayout.fit(a.nodes, canvas)
        if fitted ~= a.nodes then
            a.nodes = fitted
            changed = true
        end
    end
    last_canvas = canvas
    publish()
end)

-- The rename field keeps what was typed; the logic only reseeds it when the arrangement
-- itself changed, so a refused name is not wiped out from under the cursor.
on("text:nx_arr_draft", function(value)
    if type(value) == "string" then text.nx_arr_draft = value end
end)

-- The keys' way about: 1 left · 2 right · 3 up · 4 down, one snapped step at a time; with
-- Shift held the same key is four steps, as §5.4 asks. One move is one undo entry either way.
local function shift_node(direction, times)
    local canvas = canvas_of()
    local _, node = index_of(sel)
    if not canvas or not node then return end
    local dx = (direction == 1 and -1) or (direction == 2 and 1) or 0
    local dy = (direction == 3 and -1) or (direction == 4 and 1) or 0
    if dx == 0 and dy == 0 then return end
    remember()
    local moved = false
    for _ = 1, math.max(1, times) do
        local x, y = nexuslayout.move_step(node, dx, dy, canvas, 8)
        if nexuslayout.place(node, x, y, canvas, 8) then moved = true end
    end
    if moved then touch(true) else table.remove(past); publish() end
end

on("nx_move", function(v) shift_node(math.floor(tonumber(v) or 0), 1) end)
on("nx_move_fast", function(v) shift_node(math.floor(tonumber(v) or 0), 4) end)

on("nx_mode_switch", function(v)
    local mode = tonumber(v) == 1 and "minimal" or "circuit"
    local a = node_list()
    remember()
    if a then a.mode = mode end
    fact.nx_mode = mode
    touch(true)
end)

local BANNERS = { "full", "compact", "strip", "hidden" }
on("nx_banner_cycle", function()
    local a = node_list()
    local current = fact.nx_banner_mode or "compact"
    local next_banner = "compact"
    for i, mode in ipairs(BANNERS) do
        if mode == current then next_banner = BANNERS[(i % #BANNERS) + 1]; break end
    end
    remember()
    if a then a.banner = next_banner end
    fact.nx_banner_mode = next_banner
    touch(true)
end)

on("nx_arrangement", function(v)
    local i = math.floor(tonumber(v) or 0)
    if not arrs[i] or i == active_i then return end
    local from = positions(node_list())
    active_i = i
    sel = 0
    touch(true)
    start_morph(from)
end)

on("nx_tidy", function()
    local a = node_list()
    local canvas = canvas_of()
    if not a or not canvas then return end
    remember()
    a.nodes = nexuslayout.tidy(a.nodes, canvas, 8)
    touch(true)
end)

-- RESTORE CENTRE: the core goes back to the middle. The node that was there takes the
-- slot the core left, exactly as a focus swap does.
on("nx_hover_node", function(v)
    local i = math.floor(tonumber(v) or 0)
    if i == hover_node then return end
    hover_node = i
    publish()
end)
on("nx_hover_edge", function(v)
    local i = math.floor(tonumber(v) or 0)
    if i == hover_edge then return end
    hover_edge = i
    publish()
end)

-- A picked trace highlights the two endpoints; a press on the same trace puts it down.
on("nx_edge_pick", function(v)
    local i = math.floor(tonumber(v) or 0)
    local id = i > 0 and drawn_edges[i] or nil
    picked_edge = (id and id ~= picked_edge) and id or nil
    publish()
end)
on("nx_edge_hide", function()
    local a = node_list()
    if not a or not picked_edge then return end
    if type(a.edges) ~= "table" then a.edges = { hidden = {} } end
    if type(a.edges.hidden) ~= "table" then a.edges.hidden = {} end
    remember()
    a.edges.hidden[#a.edges.hidden + 1] = picked_edge
    picked_edge = nil
    touch(true)
end)
on("nx_edges_restore", function()
    local a = node_list()
    if not a or type(a.edges) ~= "table" then return end
    remember()
    a.edges.hidden = {}
    picked_edge = nil
    touch(true)
end)

on("nx_restore_centre", function()
    local a = node_list()
    local canvas = canvas_of()
    if not a or not canvas then return end
    for i, node in ipairs(a.nodes) do
        if node.vis and node.type == "core" then
            local from = positions(a)
            remember()
            local out, ok = nexuslayout.focus(a.nodes, "core", canvas)
            if ok then a.nodes = out end
            a.focus = "core"
            sel = i
            touch(true)
            start_morph(from)
            return
        end
    end
end)

-- Ctrl+Z and Ctrl+Shift+Z walk the layout history; each step is a whole arrangement, so a
-- focus swap and the slot it moved are undone together.
on("nx_undo", function()
    local from = positions(node_list())
    local restored, ok = nexusnode.undo(past, future, arrs)
    if not ok then return end
    arrs = restored
    if not arrs[active_i] then active_i = 1 end
    sel = 0
    save()
    publish()
    start_morph(from)
end)
on("nx_redo", function()
    local from = positions(node_list())
    local restored, ok = nexusnode.redo(past, future, arrs)
    if not ok then return end
    arrs = restored
    if not arrs[active_i] then active_i = 1 end
    sel = 0
    save()
    publish()
    start_morph(from)
end)

pcall(sys.watch, "files:" .. FILE, function()
    settings = config.parse(read(FILE), json.decode)
    fact.nx_pinned = settings.nexus and settings.nexus.pinned == true
    sync_identity()
    local count = (type(settings.nexus) == "table" and type(settings.nexus.arrangements) == "table")
        and #settings.nexus.arrangements or 0
    if last_arr_count ~= count then
        choose()
        publish()
    end
end)

-- Presence and the readings a compact body shows come from the same services the plate
-- always used; each watcher only republishes the model, never writes the settings.
pcall(sys.watch, "battery", function(b)
    present.battery = type(b) == "table" and b.present == true
    live.power_on = present.battery
    live.power = type(b) == "table" and (tonumber(b.percent) or 0) or 0
    live.charging = type(b) == "table" and b.charging == true
    publish()
end)
pcall(sys.watch, "brightness", function(b)
    present.brightness = type(b) == "table" and b.present == true
    live.bright_on = present.brightness
    live.bright = type(b) == "table" and (tonumber(b.level) or 0) or 0
    publish()
end)
pcall(sys.watch, "network", function(n)
    if type(n) ~= "table" then return end
    live.net_on = n.online == true
    live.net_name = str(n.name, "")
    live.net_kind = str(n.kind, "none")
    publish()
end)
pcall(sys.watch, "bluetooth", function(b)
    if type(b) ~= "table" then return end
    live.bt_present = b.present == true
    live.bt_on = b.powered == true
    publish()
end)
pcall(sys.watch, "clock", function(c)
    if type(c) ~= "table" then return end
    live.time = str(c.time, "--:--")
    live.date = str(c.date, "")
    publish()
end)
pcall(sys.watch, "workspaces", function(w)
    if type(w) ~= "table" then return end
    if tonumber(w.active) then live.ws = math.floor(tonumber(w.active)) end
    spaces = nexus.ws_rows(w.list, 10)
    publish()
end)

-- Tab walks the nodes that are on the canvas, in the arrangement's own order and, with
-- Shift, backwards. Both directions wrap, so the selection never strands on a removed node.
local function walk_selection(back)
    local a = node_list()
    local p = present_set()
    if not a then return end
    local mode = a.mode or "circuit"
    local order = {}
    for i, node in ipairs(a.nodes) do
        if node.vis and nexusnode.available(node.type, p) and (mode ~= "minimal" or node.essential) then
            order[#order + 1] = i
        end
    end
    if #order == 0 then return end
    local next_sel = order[#order]
    if not back then
        next_sel = order[1]
        for _, i in ipairs(order) do
            if i > sel then next_sel = i; break end
        end
    else
        for k = #order, 1, -1 do
            if order[k] < sel then next_sel = order[k]; break end
        end
    end
    sel = next_sel
    publish()
end

on("nx_cycle_sel", function() walk_selection(false) end)
on("nx_cycle_sel_back", function() walk_selection(true) end)

-- The mixer's two writes: a press mutes a stream, a wheel sets its level. The scene keeps
-- the stream id beside the event because a service call needs both the id and the level.
on("nx_app_mute", function(v)
    local id = math.floor(tonumber(v) or 0)
    if id <= 0 then return end
    local ok = pcall(sys.call, "audio.app_mute", id)
    if not ok then report_control_failure("STREAM MUTE") end
end)
on("nx_app_vol", function()
    local id = math.floor(tonumber(fact.nx_app_sid) or 0)
    local level = tonumber(fact.nx_app_lvl)
    if id <= 0 or not level then return end
    local ok = pcall(sys.call, "audio.app_volume", id, math.max(0, math.min(1, level)))
    if not ok then report_control_failure("STREAM VOLUME") end
end)
on("nx_ws_focus", function(v)
    local id = math.floor(tonumber(v) or 0)
    if id <= 0 then return end
    local ok = pcall(sys.call, "workspaces.focus", id)
    if not ok then report_control_failure("WORKSPACE") end
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
    live.volume = tonumber(audio.volume) or live.volume
    live.muted = audio.muted == true
    live.input = tonumber(audio.input) or live.input
    live.input_muted = audio.input_muted == true
    mix = nexus.app_rows(audio.apps, 7)
    publish_routes()
    publish()
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
    publish()
    after(2000, sample_live)
end

-- Seed before the first publish, so the model the scene receives on start is the one the
-- settings file will carry from then on.
local seeded = choose()
publish()
if seeded then save() end
sample_live()

-- ── The controls ────────────────────────────────────────────
-- A wheel asks for a new level every notch; the system is told at most every 40 ms, always
-- the latest. The services remain the source of truth for displayed values. If a command
-- raises an error, the footer reports which operation failed without exposing raw internals.
local notice_serial = 0
function report_control_failure(label)
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
