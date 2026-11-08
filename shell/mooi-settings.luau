-- mooi's settings window, its logic: the settings as facts, the palette as colours, and every
-- control's press written to settings.json — which mooi watches and applies (shell/mooi.luau).
-- The folder is mooi's own (bin/mooi links this program's folder to it), so the file read
-- and written here is the bar's.

local config = require("lib/config")
local ferro = require("lib/ferro")
local barlayout = require("lib/barlayout")
local setters = require("lib/setters")
local desktop = require("lib/desktop")
local style = require("lib/style")
local arrange = require("lib/arrange")
local index = require("lib/settings_index")
local settingsfile = require("lib/settingsfile")
local modlook = require("lib/modlook")

local FILE, PALETTE = "settings.json", "palette.json"
local settings = config.defaults()
local loaded = nil              -- settings.json as this window last read it: what `save` diffs against
local palette = nil

-- Each setting's position as the window's controls read it (`sv_`/`df_`): an enum's place in
-- its list, a number's distance from its minimum, a switch 0 or 1; the presets and the merged
-- choices as what the settings now are.
local function positions(s, prefix)
    local P = setters.position
    for _, path in ipairs(setters.SETTERS) do
        local row = nil
        for _, r in ipairs(config.SCHEMA) do if r.path == path then row = r end end
        if row then
            local v = s
            for k in string.gmatch(path, "[^.]+") do v = v[k] end
            local name = prefix .. string.gsub(path, "%.", "_")
            if row.kind == "enum" then fact[name] = P(path, v)
            elseif row.kind == "integer" then fact[name] = v - row.min
            elseif row.kind == "boolean" then fact[name] = v and 1 or 0 end
        end
    end
    fact[prefix .. "bar_style"] = style.preset_index(s, style.BAR_PRESETS)
    fact[prefix .. "theme_preset"] = style.preset_index(s, style.THEME_PRESETS)
    fact[prefix .. "bar_edge"] = style.edge_index(s)
    fact[prefix .. "frame_motion"] = style.motion_index(s)
end
-- What every revert arrow puts back: the defaults, once.
positions(config.defaults(), "df_")

local layout                 -- the Layout page (below), rebuilt with every change
local save                   -- writes settings.json as a read-merge-write (below)
local show_colour, show_power -- the custom colour's sliders and the Power page (below)
-- D168: the Pill's activities in their order, for the "What may take it" rows
local pillmod = require("lib/pill")
local PILL_NAME = { battery = "Battery", record = "Recording", notify = "Notifications", music = "Music", osd = "Volume & brightness", idle = "Time & workspaces" }
local PILL_DESC = { battery = "Low (15 % and less), or charging just started", record = "While the screen is being recorded",
    notify = "For six seconds after one arrives", music = "While something plays", osd = "For two seconds after a change",
    idle = "When nothing else is happening" }
local function pill_rows(s)
    local p = type(s.pill) == "table" and s.pill or {}
    local order = pillmod.reorder(p.order, p.off, -1, "")
    local off = {}
    for _, id in ipairs(type(p.off) == "table" and p.off or {}) do off[id] = true end
    for n = 0, 5 do
        local id = order[n + 1]
        text["pord" .. n] = id and PILL_NAME[id] or ""
        text["pdesc" .. n] = id and PILL_DESC[id] or ""
        fact["pon" .. n] = id ~= nil and not off[id]
    end
end
-- D194: Loom / Fold's status line, from the mode and what the keeper last wrote (loom-state.json)
local function loom_status(s)
    local lm = require("lib/loommode")
    local ok, h = pcall(sys.ask, "files.read", "loom-state.json", "json")
    local mode = type(s.loom) == "table" and s.loom.mode or "native"
    text.lf_status = lm.status_line(mode, ok and h or nil)
end
local function publish(s)
    pcall(pill_rows, s)
    pcall(loom_status, s)
    local P = setters.position
    fact.ws_style = P("bar.workspaces", s.bar.workspaces)
    fact.bar_frame = P("bar.frame", s.bar.frame)
    fact.bar_ground = P("bar.ground", s.bar.ground)
    fact.bar_rail = s.bar.rail
    fact.bar_accents = s.bar.accents
    fact.music_rim = s.music.rim == true
    fact.bar_full = s.bar.mode == "full"
    fact.bar_surface = P("bar.surface", s.bar.surface)
    fact.viz = P("bar.visualizer", s.bar.visualizer)
    fact.helix_frame = s.bar.helix_frame
    fact.bar_labels = s.bar.labels
    fact.bar_wheel = s.bar.wheel
    fact.media_mode = P("media.mode", s.media.mode)
    fact.media_idle = P("media.idle", s.media.idle)
    fact.frame_on = s.frame.on
    fact.frame_band = s.frame.band
    fact.frame_music = s.frame.music
    fact.frame_style = P("frame.style", s.frame.style)
    fact.frame_reach = s.frame.reach
    fact.frame_edges = P("frame.edges", s.frame.edges)
    fact.note_server = P("notifications.server", s.notifications.server)
    fact.th_scheme = P("theme.scheme", s.theme.scheme)
    fact.th_index = s.theme.color_index
    fact.th_contrast = s.theme.contrast + 1
    fact.th_signal = P("theme.signal", s.theme.signal)
    fact.theme_wallpaper = s.theme.source == "wallpaper"
    fact.show_clock = s.bar.modules.clock.show
    fact.previews = s.atlas.previews
    fact.confirm_close = s.island.confirm_close
    fact.ws_max = s.spine.max_workspaces
    fact.tray_style = P("tray.style", s.tray.style)
    fact.dk_manage = s.desktop.manage
    fact.dk_border = s.desktop.border
    fact.dk_colour = P("desktop.border_colour", s.desktop.border_colour)
    fact.dk_gin = s.desktop.gaps_in
    fact.dk_gout = s.desktop.gaps_out
    fact.dk_round = s.desktop.rounding
    fact.dk_dim = s.desktop.dim_inactive
    for name, v in pairs(style.facts(s)) do fact[name] = v end
    -- the settings' own positions, for the window's choices (lib/setters); the presets read as
    -- what the settings are now: a look, or Custom (one past the last)
    positions(s, "sv_")
    -- the keys, and any combination two of them share
    for _, a in ipairs(desktop.ACTIONS) do
        text["key_" .. a.key] = s.keys[a.key]
        local clash = ""
        for _, b in ipairs(desktop.ACTIONS) do
            if b.key ~= a.key and s.keys[b.key] == s.keys[a.key] then clash = "ALSO USED BY " .. string.upper(b.name) end
        end
        text["key_clash_" .. a.key] = clash
    end
    local grouped = {}
    for _, side in ipairs({ "left", "center", "right" }) do
        for _, entry in ipairs(s.bar[side] or {}) do
            local ids = barlayout.split(entry) or {}
            if #ids > 1 then for _, m in ipairs(ids) do grouped[m] = true end end
        end
    end
    for _, id in ipairs(barlayout.ORDER) do
        local mod = s.bar.modules[id]
        fact["m_" .. id] = mod.show
        fact["fi_" .. id] = P("bar.modules." .. id .. ".frame", mod.frame)
        fact["g_" .. id] = grouped[id] == true
    end
    -- the lock screen's picture (Settings → Lock): the identity the Nexus shows, which `mooi lock`
    -- copies beside the lock's scene
    local id = type(s.nexus) == "table" and type(s.nexus.identity) == "table" and s.nexus.identity or {}
    local function ispic(rel) return type(rel) == "string" and rel ~= "" end
    text.lock_pic_now = ispic(id.banner) and "BANNER" or (ispic(id.avatar) and "PROFILE PICTURE" or "NONE YET")
    -- the kitty pipeline the Custom choice picked (Settings → Windows): its last path part, and
    -- NONE YET when there is none to name
    local kp = tostring(s.desktop.kitty_shader_custom or "")
    text.kitty_shader_now = (kp ~= "" and string.match(kp, "[^/]+$")) or "NONE YET"
    if layout then layout(s) end
    if show_colour then show_colour() end
    if show_fxcolours then show_fxcolours() end
    if show_power then show_power() end
end

local function paint()
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"] = c.r; fact["fr_" .. role .. "_g"] = c.g; fact["fr_" .. role .. "_b"] = c.b
    end
end

local function fresh_settings()
    local s, _, _, state = config.parse(sys.ask("files.read", FILE), json.decode)
    if state == "broken" then return nil end
    return s
end

local function load()
    local s = config.parse(sys.ask("files.read", FILE), json.decode)
    settings = s
    loaded = settingsfile.copy(s)
    publish(settings)
    local ok, t = pcall(sys.ask, "files.read", PALETTE, "json")
    palette = (ok and type(t) == "table") and t or nil
    paint()
end

-- ── What each choice would look like ─────────────────────────
-- Every palette style, and each of the wallpaper's five leading colours, as the two colours
-- the bar would wear: Matugen asked with --dry-run (nothing is written), the answer mapped as
-- the bar maps it (lib/ferro). Asked again when the wallpaper (the palette) changes.
local SCHEMES = { "tonal-spot", "content", "expressive", "fidelity", "fruit-salad", "monochrome", "neutral", "rainbow", "vibrant", "smart" }
local wallpaper = tostring(sys.ask("env", "HOME")) .. "/.cache/current_wallpaper"
-- The lock's backdrop preview (Settings → Lock): the still the shell keeps of what it is wearing
-- (a video's current frame too), so the blur and the dimming chosen there are seen on the picture
-- they will be applied to. No still, no picture: the scene says so rather than lie.
local function backdrop_pic()
    -- The files service stops at this scene's own folder, so it cannot say whether the still is
    -- there (asking it made this always say no); the picture is drawn from its path instead. A
    -- still that is not there leaves the ground, which is what a lock with no wallpaper is.
    local home = tostring(sys.ask("env", "HOME") or "")
    text.lk_wp = home ~= "" and wallpaper or ""
    fact.lk_wp_on = home ~= ""
end
local function roles_of(out)
    local ok, t = pcall(json.decode, out or "")
    if not ok or type(t) ~= "table" or type(t.colors) ~= "table" then return nil end
    local roles = {}
    for name, v in pairs(t.colors) do
        if type(v) == "table" and type(v.dark) == "table" then roles[name] = v.dark.color end
    end
    return roles
end
local function set_rgb(prefix, c) fact[prefix .. "_r"] = c.r; fact[prefix .. "_g"] = c.g; fact[prefix .. "_b"] = c.b end
local previewed = nil
local function previews()
    local key = tostring(settings.theme.color_index) .. "/" .. tostring(settings.theme.contrast) .. "/" .. tostring(settings.theme.scheme)
        .. "/" .. tostring(palette and palette.colours and palette.colours.primary)
    if key == previewed then return end
    previewed = key
    for i, sch in ipairs(SCHEMES) do
        run("matugen", { "image", wallpaper, "-m", "dark", "--dry-run", "-j", "hex", "--type", "scheme-" .. sch,
            "--source-color-index", tostring(settings.theme.color_index), "--contrast", tostring(settings.theme.contrast) }, function(out)
            local out2 = ferro.derive(roles_of(out), settings.theme.signal)
            if out2 then set_rgb("sp" .. (i - 1), out2.phos); set_rgb("se" .. (i - 1), out2.ember) end
        end)
    end
    for v = 0, 4 do
        run("matugen", { "image", wallpaper, "-m", "dark", "--dry-run", "-j", "hex", "--type", "scheme-" .. settings.theme.scheme,
            "--source-color-index", tostring(v) }, function(out)
            local out2 = ferro.derive(roles_of(out), settings.theme.signal)
            if out2 then set_rgb("sc" .. v, out2.phos) end
        end)
    end
end

load()
previews()
backdrop_pic()
sys.watch("files:" .. FILE, function() load(); previews(); backdrop_pic() end)
sys.watch("files:" .. PALETTE, function() load(); previews() end)

-- ── Changing a key ─────────────────────────────────────────
-- Change, then the keys: the modifiers held and the one key pressed with them, in Hyprland's
-- spelling ("SUPER + ALT + Space"). Escape cancels. 99 puts every key back to its default.
local MODS = { Super_L = "SUPER", Super_R = "SUPER", Alt_L = "ALT", Alt_R = "ALT", Shift_L = "SHIFT", Shift_R = "SHIFT",
               Control_L = "CTRL", Control_R = "CTRL", Meta_L = "SUPER", Meta_R = "SUPER" }
local ORDERED = { "SUPER", "CTRL", "ALT", "SHIFT" }
local held = {}
local function key_name(name)
    if #name == 1 then return string.upper(name) end
    if name == "space" then return "Space" end
    if name == "Return" or name == "Tab" or string.match(name, "^F%d+$") or name == "Escape" then return name end
    return name
end
on("key_change", function(v)
    local n = math.floor(tonumber(v) or -1)
    if n == 99 then
        settings.keys = config.defaults().keys
        save(); fact.capturing = -1
        return
    end
    fact.capturing = (fact.capturing == n) and -1 or n
    held = {}
end)
on("key_down", function(name)
    if fact.capturing < 0 then return end
    if MODS[name] then held[MODS[name]] = true; return end
    if name == "Escape" then fact.capturing = -1; return end
    local parts = {}
    for _, m in ipairs(ORDERED) do if held[m] then parts[#parts + 1] = m end end
    if #parts == 0 then text.cap_text = "Hold at least one of Super, Ctrl, Alt or Shift"; return end
    parts[#parts + 1] = key_name(name)
    local action = desktop.ACTIONS[fact.capturing + 1]
    if action then
        settings.keys[action.key] = table.concat(parts, " + ")
        save()
    end
    fact.capturing = -1
    text.cap_text = "Press the new keys… (Esc cancels)"
end)
on("key_up", function(name) if MODS[name] then held[MODS[name]] = nil end end)

-- A control pressed: the setting, written. mooi's file watch does the rest (and extracts a new
-- palette when the scheme, the colour or the contrast changed).
-- A strength dragged step by step would recompile the pipeline on every step, so the tint waits
-- for the hand to settle: one write 350 ms after the last step, and nothing while it is moving.
local tint_drag = 0
local apply_widget_style   -- D210: set below, once widgets.json's writer is in scope
on("set_value", function(n)
    local path = setters.apply(settings, n)
    if not path then return end
    save()
    paint()
    if path == "surface.widget_style" and apply_widget_style then apply_widget_style(settings.surface.widget_style) end
    -- kitty's own screen shader is a file kitty reads, not a fact the bar wears: the shell writes it
    -- and asks kitty to reload (`mooi kitty-shaders`), so a change lands in windows already open
    if path == "desktop.kitty_shader_tint" then
        tint_drag = tint_drag + 1
        local mine = tint_drag
        after(350, function() if tint_drag == mine then run("mooi", { "kitty-shaders" }) end end)
    elseif path == "desktop.kitty_shader_on" or path == "desktop.kitty_shader" then
        run("mooi", { "kitty-shaders" })
    end
end)

-- 1: the bar's edit mode (the bar is told, it is the bar's state); 9: close this window.
on("set_action", function(v)
    local n = math.floor(tonumber(v) or 0)
    if n == 1 then
        fact.bar_edit = not fact.bar_edit
        run("pleamar", { "--say", "mooi", "fact bar_edit " .. tostring(fact.bar_edit) })
    elseif n == 9 then
        run("pleamar", { "--say", "mooi-settings", "quit" })
    end
end)

local version = sys.ask("env", "MOOI_VERSION")
text.bar_version = (type(version) == "string" and version ~= "") and version or "dev"
text.bar_path = tostring(sys.ask("files.folder")) .. "/settings.json"

-- D190: the login screen is greetd running sysc-greet, and it wears this palette through the theme
-- `mooi greet-theme` writes. This window cannot read /var itself (files.read stays in its own folder),
-- so it asks the same script, which answers in one line — the Theme & colour page shows it.
run("mooi", { "greet-theme", "--status" }, function(out)
    text.gr_theme = string.gsub(tostring(out or ""), "%s+$", "")
end)

-- ── The Layout page ────────────────────────────────────────
-- The bar's three lists as chips in cards (Left, Centre, Right) and the modules not on it on a
-- shelf, every chip placed here (the scene cannot measure text); above them a preview of the bar
-- to scale, from the same layout the bar computes (lib/barlayout). A chip is selected by its
-- place, so a spacer — which can be there many times — is one thing to move like any module.
local NAMES = {
    workspaces = "Workspaces", window = "Window title", media = "Media", resources = "Resources",
    bandwidth = "Bandwidth", keyboard = "Keyboard", weather = "Weather", tray = "Tray",
    notifications = "Notifications", mic = "Microphone", volume = "Volume", brightness = "Brightness",
    battery = "Battery", network = "Network", bluetooth = "Bluetooth", clock = "Clock",
    caffeine = "Keep awake", recorder = "Recorder", screenshot = "Screenshot", clipboard = "Clipboard",
    power = "Session", actions = "Window actions", overview = "Overview", core = "Search", focus = "Focus timer", settings = "Settings",
    notes = "Quick notes", wallpaper = "Wallpapers", gap = "Spacer",
}
local SIDE_NAME = { left = "LEFT", center = "CENTRE", right = "RIGHT" }
local X0, X1 = 274, 1138                     -- a card's inside, as the window draws it
local sel = nil                              -- { side, i, j } on the bar, or { shelf = id }
local look_id = nil                          -- the module the Look card styles (D166)
local chips = {}                             -- the model's chips, by index from 0
local function chip_w(label) return math.max(68, 30 + math.floor(#label * 7.2 + 0.5)) end
local function name_of(id)
    local g = barlayout.gap_width(id)
    if g then return "Gap " .. tostring(g) .. " px" end
    return NAMES[id] or id
end
local function hidden(s, id) return not arrange.placed(s.bar, id) or not s.bar.modules[id].show end

function layout(s)
    local b = s.bar
    chips = {}
    local rows, grs = {}, {}
    local y = 0
    local function card(z, entries)
        local top = y
        local cx, cy, n = X0, top + 52, 0
        for _, e in ipairs(entries) do
            local ws = {}
            local total = 0
            for k, m in ipairs(e.members) do ws[k] = chip_w(name_of(m.id)); total = total + ws[k] + ((k > 1) and 4 or 0) end
            if cx > X0 and cx + total > X1 then cx = X0; cy = cy + 44 end
            if #e.members > 1 then grs[#grs + 1] = { x = cx - 3, y = cy - 3, w = total + 6 } end
            for k, m in ipairs(e.members) do
                local i = #chips
                chips[i + 1] = m
                local on = sel ~= nil and ((m.shelf and sel.shelf == m.id) or (not m.shelf and not sel.shelf and sel.side == m.side and sel.i == m.i and sel.j == m.j))
                rows[#rows + 1] = { x = cx, y = cy, w = ws[k], label = name_of(m.id), sel = on,
                                    kind = m.shelf and 3 or (barlayout.is_spacer(m.id) and 1 or 0), idx = i }
                cx = cx + ws[k] + 4
                n = n + 1
            end
            cx = cx + 10
        end
        local h = (n > 0) and (cy + 30 + 18 - top) or 86
        fact["lz" .. z .. "_y"], fact["lz" .. z .. "_h"], fact["lz" .. z .. "_n"] = top, h, n
        y = top + h + 14
    end
    for z, side in ipairs(arrange.SIDES) do
        local entries = {}
        for i, e in ipairs(b[side]) do
            local ms = {}
            local ids = barlayout.is_spacer(e) and { e } or (barlayout.split(e) or {})
            for j, id in ipairs(ids) do ms[#ms + 1] = { side = side, i = i, j = j, id = id, n = #ids } end
            entries[#entries + 1] = { members = ms }
        end
        card(z - 1, entries)
    end
    local shelf = {}
    for _, id in ipairs(barlayout.ORDER) do
        if hidden(s, id) then shelf[#shelf + 1] = { members = { { shelf = id, id = id } } } end
    end
    card(3, shelf)
    fact.lay_zh = y
    model.lay_chips = rows
    model.lay_groups = grs

    -- the preview: the bar as it lays out on a 1920 px screen, scaled into the card
    local scale = (X1 - X0) / 1920
    local cfg = { left = b.left, center = b.center, right = b.right, mode = b.mode, show = {} }
    for _, m in ipairs(barlayout.ORDER) do cfg.show[m] = b.modules[m].show end
    local out = barlayout.layout(cfg, { screen = 1920, inset = 12 + 1920 * (1 - b.width / 100) / 2, gap = barlayout.gap(b.mode),
        ws_style = b.workspaces, ws_count = s.spine.max_workspaces, visualizer = b.visualizer, tray = 3, battery = true,
        brightness = true, bluetooth = true, playing = true, media_mode = s.media.mode, media_idle = s.media.idle })
    local prev = {}
    for i, m in ipairs(chips) do
        local x = (not m.shelf) and not barlayout.is_spacer(m.id) and out.x[m.id]
        if x then
            prev[#prev + 1] = { x = X0 + x * scale, w = barlayout.width(m.id, { ws_style = b.workspaces, ws_count = s.spine.max_workspaces,
                visualizer = b.visualizer, tray = 3, playing = true, media_mode = s.media.mode, media_idle = s.media.idle }) * scale,
                label = string.upper(NAMES[m.id] or m.id), sel = rows[i].sel, chip = i - 1 }
        end
    end
    model.lay_prev = prev

    -- what is selected, and what it can do from where it is
    local m = nil
    for i, c in ipairs(chips) do if rows[i].sel then m = c end end
    if not m then sel = nil; fact.lay_kind = 0; return end
    text.lay_name = name_of(m.id)
    if m.shelf then
        fact.lay_kind = 3
        text.lay_where = "ON THE SHELF · NOT ON THE BAR"
        for k, id in ipairs(barlayout.ORDER) do if id == m.id then fact.lay_mod = k - 1 end end
        return
    end
    local spacer = barlayout.is_spacer(m.id)
    fact.lay_kind = spacer and 2 or 1
    local list = b[m.side]
    local first_side, last_side = m.side == "left", m.side == "right"
    text.lay_where = SIDE_NAME[m.side] .. " · " .. tostring(m.i) .. " OF " .. tostring(#list) .. ((m.n > 1) and (" · IN A GROUP OF " .. m.n) or "")
        .. (m.id == barlayout.SPACER and " · STRETCHES TO PUSH WHAT FOLLOWS TO THE MIDDLE" or (spacer and " · A FIXED GAP, LEFT BY A DROP ON THE BAR" or ""))
    fact.lay_c1 = not (first_side and m.i == 1 and m.j == 1)
    fact.lay_c2 = not (last_side and m.i == #list and m.j == m.n)
    local function joinable(k) return list[k] ~= nil and not barlayout.is_spacer(list[k]) end
    fact.lay_c3 = not spacer and m.n == 1 and joinable(m.i - 1)
    fact.lay_c4 = not spacer and m.n == 1 and joinable(m.i + 1)
    fact.lay_c5 = m.n > 1
    fact.lay_c6, fact.lay_c7, fact.lay_c8 = m.side ~= "left", m.side ~= "center", m.side ~= "right"
    if not spacer then
        for k, id in ipairs(barlayout.ORDER) do if id == m.id then fact.lay_mod = k - 1 end end
        fact.lay_fi = setters.position("bar.modules." .. m.id .. ".frame", b.modules[m.id].frame)
        fact.lay_grouped = m.n > 1
        -- D166: the selected module's own look, for the Look card (a group shows its first module's)
        look_id = m.id
        local li = modlook.index(s, m.id)
        fact.lk_colour, fact.lk_fill, fact.lk_round = li.colour, li.fill, li.rounding
        fact.lk_outline, fact.lk_glow, fact.lk_display, fact.lk_width = li.outline, li.glow, li.display, li.width
    end
end

layout(settings)

-- D166: the Look card — one event, key * 16 + value (lib/modlook), for the selected module or its group
on("lay_look", function(v)
    if not look_id or tostring(sys.ask("env", "MOOI_SAFE") or "") == "1" then return end
    local key, value = modlook.decode(v)
    if not key then return end
    modlook.apply(settings, look_id, key, value)
    save()
    layout(settings)
end)

-- One write policy for settings.json (audit 2026-10-31, F3): read the file as it is now and lay
-- this window's changes over it. Writing the in-memory copy whole reverted whatever the bar had
-- just written (a workspace label, the wheel, day or night) while this window was open.
function save()
    local was_idle = type(settings.lock) == "table" and settings.lock.idle or nil
    local doc, why = settingsfile.save(sys, FILE, loaded, settings, fresh_settings)
    if not doc then log("settings · could not save: " .. tostring(why)); publish(settings); return false end
    settings = doc                  -- what is on disk now: another program's change is kept
    loaded = settingsfile.copy(doc)
    publish(settings)
    -- the lock's timer is hypridle's, not this window's: `mooi idle` writes its file and restarts it
    if (type(settings.lock) == "table" and settings.lock.idle or nil) ~= was_idle then run("mooi", { "idle" }) end
    return true
end

-- ── The lock screen's picture (D161) ────────────────────────
-- The same picture the Nexus's profile card shows, chosen with zenity and imported by `mooi
-- identity` (a new file name for every import); `mooi lock` copies it beside the lock's scene.
-- Banner or picture, the lock takes whichever is set, the banner first.
-- The lock, now: the same scene the key and hypridle reach, so a lock is always one program.
-- A `mooi` that cannot lock says so in the log rather than failing quietly behind the window.
on("lock_now", function()
    run("mooi", { "lock" }, function(_, code) if code ~= 0 then log("lock · mooi lock refused; see `mooi lock`") end end)
end)
on("lock_pic", function(v)
    local kind = tonumber(v) == 0 and "avatar" or "banner"
    local ok = pcall(run, "zenity", { "--file-selection", "--title=Choose the lock screen's " .. (kind == "avatar" and "picture" or "banner"),
                                       "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.avif" }, function(out, code)
        local path = (out or ""):match("^%s*(.-)%s*$")
        if code ~= 0 or path == "" then return end
        run("mooi", { "identity", kind, path }, function(_, c)
            if c == 0 then load() else log("lock · the picture could not be imported") end
        end)
    end)
    if not ok then log("lock · install zenity to choose a picture") end
end)
on("lay_pick", function(v)
    local c = chips[(math.floor(tonumber(v) or -1)) + 1]
    if not c then sel = nil
    elseif c.shelf then sel = (sel and sel.shelf == c.id) and nil or { shelf = c.id }
    elseif sel and not sel.shelf and sel.side == c.side and sel.i == c.i and sel.j == c.j then sel = nil
    else sel = { side = c.side, i = c.i, j = c.j } end
    layout(settings)
end)
-- D168: the Pill's order list — on/off, up, down (lib/pill.reorder keeps idle last and on)
on("pill_act", function(v)
    if tostring(sys.ask("env", "MOOI_SAFE") or "") == "1" then return end
    local n = math.floor(tonumber(v) or -1)
    if n < 0 then return end
    local op = ({ [0] = "toggle", [1] = "up", [2] = "down" })[n % 4]
    if not op then return end
    settings.pill = type(settings.pill) == "table" and settings.pill or {}
    settings.pill.order, settings.pill.off = pillmod.reorder(settings.pill.order, settings.pill.off, math.floor(n / 4), op)
    save()
end)
-- D166: "Look…" in the bar's edit mode: this module, selected, on Bar & Frame with Modules open
on("open_module", function(v)
    local id = barlayout.ORDER[(math.floor(tonumber(v) or -1)) + 1]
    if not id then return end
    for _, c in ipairs(chips) do
        if c.id == id and not c.shelf then sel = { side = c.side, i = c.i, j = c.j } end
    end
    layout(settings)
    fact.set_tab = index.layout_tab
    -- only Modules open, so the page's place for the Look card is known; scrolled to it
    for _, f in ipairs(index.layout_folds or {}) do fact[f] = (f == index.modules_fold) end
    if index.modules_look_y then fact.set_scroll = math.max(0, index.modules_look_y - 160) end
end)
on("lay_act", function(v)
    local op = math.floor(tonumber(v) or 0)
    local b = settings.bar
    local L, side, i, j
    if op >= 10 and op <= 12 then
        L, side, i, j = arrange.add(b, barlayout.SPACER, arrange.SIDES[op - 9])
    elseif sel and sel.shelf then
        if op < 6 or op > 8 then return end
        L, side, i, j = arrange.add(b, sel.shelf, arrange.SIDES[op - 5])
        b.modules[sel.shelf].show = true
    elseif sel then
        if op == 1 or op == 2 then L, side, i, j = arrange.move(b, sel.side, sel.i, sel.j, (op == 1) and -1 or 1)
        elseif op == 3 or op == 4 then L, side, i, j = arrange.join(b, sel.side, sel.i, sel.j, (op == 3) and -1 or 1)
        elseif op == 5 then L, side, i, j = arrange.split(b, sel.side, sel.i, sel.j)
        elseif op >= 6 and op <= 8 then L, side, i, j = arrange.to_side(b, sel.side, sel.i, sel.j, arrange.SIDES[op - 5])
        elseif op == 9 then
            local id
            L, id = arrange.remove(b, sel.side, sel.i, sel.j)
            if id and not barlayout.is_spacer(id) then b.modules[id].show = true; sel = { shelf = id } else sel = nil end
        end
    end
    if not L then return end
    for _, sd in ipairs(arrange.SIDES) do b[sd] = L[sd] end
    if side then sel = { side = side, i = i, j = j } end
    save()
end)

-- ── Reset ──────────────────────────────────────────────────
-- A page's Reset puts every setting on it back to its default (lib/settings_index lists them):
-- the first press arms it for a few seconds, the second does it.
local function reset_page(tab)
    local d = config.defaults()
    for _, path in ipairs(index.resets[tab] or {}) do
        if path == "@layout" then
            for _, sd in ipairs(arrange.SIDES) do settings.bar[sd] = d.bar[sd] end
            for _, id in ipairs(barlayout.ORDER) do settings.bar.modules[id] = d.bar.modules[id] end
            sel = nil
        elseif path == "@keys" then
            settings.keys = d.keys
        else
            local src, dst = d, settings
            local keys = {}
            for k in string.gmatch(path, "[^.]+") do keys[#keys + 1] = k end
            for k = 1, #keys - 1 do src = src[keys[k]]; dst = dst[keys[k]] end
            dst[keys[#keys]] = src[keys[#keys]]
        end
    end
    save(); paint()
end
-- ── Kitty's own screen shaders (D159) ────────────────────
-- A pipeline of the user's own (desktop.kitty_shader = custom): chosen with zenity and kept as the
-- path kitty itself understands, never copied. It is kitty's file; mooi only points kitty at it.
on("set_kitty_shader_file", function()
    local ok = pcall(run, "zenity", { "--file-selection", "--title=Choose a kitty shader pipeline",
                                       "--file-filter=Pipelines | *.pipeline *.slang" }, function(out, code)
        local path = (out or ""):match("^%s*(.-)%s*$")
        if code ~= 0 or path == "" or #path > 200 then return end
        settings.desktop.kitty_shader = "custom"
        settings.desktop.kitty_shader_custom = path
        save()
        run("mooi", { "kitty-shaders" })
    end)
    if not ok then log("kitty · install zenity to choose a pipeline") end
end)

local armed_at = 0
on("set_reset", function(v)
    local tab = math.floor(tonumber(v) or -1)
    if fact.rs_armed == tab then fact.rs_armed = -1; reset_page(tab); return end
    fact.rs_armed = tab
    armed_at = armed_at + 1
    local mine = armed_at
    after(3000, function() if armed_at == mine and fact.rs_armed == tab then fact.rs_armed = -1 end end)
end)

-- ── Search ─────────────────────────────────────────────────
-- Every row the window shows (lib/settings_index, generated with the window), matched by its
-- name first, then what it does and its page; a press — or Enter, the first — opens its page at
-- it. Escape clears.
local hits = {}
local function find(q)
    q = string.lower((string.gsub(q or "", "^%s+", "")))
    hits = {}
    if q == "" then fact.searching = false; model.set_results = {}; fact.set_hits = 0; return end
    local named, described = {}, {}
    for _, row in ipairs(index) do
        if string.find(string.lower(row.title), q, 1, true) then named[#named + 1] = row
        elseif string.find(string.lower(row.desc .. " " .. row.page), q, 1, true) then described[#described + 1] = row end
    end
    for _, r in ipairs(named) do hits[#hits + 1] = r end
    for _, r in ipairs(described) do hits[#hits + 1] = r end
    local shown = {}
    for i = 1, math.min(#hits, 8) do shown[i] = { title = hits[i].title, desc = hits[i].desc, page = hits[i].page } end
    model.set_results = shown
    fact.set_hits = #hits
    fact.searching = true
end
on("text:set_query", function(q) find(q) end)
local function jump(n)
    local r = hits[n + 1]
    text.set_query = ""
    find("")
    if r then
        fact.set_tab = r.tab
        if r.fold then
            -- a row in a fold (review I1): that fold open, the page's others closed, so its place is known
            for _, f in ipairs((index.page_folds or {})[r.tab] or {}) do fact[f] = (f == r.fold) end
            fact.set_scroll = math.max(0, r.fy - 160)
        else
            fact.set_scroll = math.max(0, r.y - 160)
        end
    end
end
on("set_jump", function(v) jump(math.floor(tonumber(v) or -1)) end)
on("submit:set_query", function() jump(0) end)

-- ── Sound ──────────────────────────────────────────────────
-- Where sound plays and listens (the `audio` service's devices; a press makes one the default),
-- and what is playing, each with its own volume.
local outs, ins, apps_on = {}, {}, {}
sys.watch("audio", function(a)
    if type(a) ~= "table" then return end
    local function devices(list, base, keep)
        local rows = {}
        for i, d in ipairs(type(list) == "table" and list or {}) do
            keep[i] = d.id
            rows[#rows + 1] = { name = tostring(d.name or d.id or "?"), on = d.default == true, n = base + i - 1 }
        end
        return rows
    end
    outs, ins = {}, {}
    model.snd_out = devices(a.outputs, 0, outs)
    model.snd_in = devices(a.inputs, 100, ins)
    apps_on = {}
    local rows = {}
    for _, p in ipairs(type(a.apps) == "table" and a.apps or {}) do
        if #rows < 10 then
            apps_on[#rows + 1] = p.id
            rows[#rows + 1] = { name = tostring(p.name or p.binary or "?"), title = tostring(p.title or ""),
                                vol = math.floor((tonumber(p.volume) or 0) * 100 + 0.5) }
        end
    end
    model.snd_apps = rows
end)
on("snd_pick", function(v)
    local n = math.floor(tonumber(v) or -1)
    local id = (n >= 100) and ins[n - 99] or outs[n + 1]
    if id then pcall(sys.call, "audio.default", id) end
end)
on("snd_app", function(v)
    local n = math.floor(tonumber(v) or 0)
    local id = apps_on[math.floor(n / 1000)]
    if id then pcall(sys.call, "audio.app_volume", id, (n % 1000) / 100) end
end)

-- ── Displays ───────────────────────────────────────────────
-- Read-only for now: what Hyprland has, every few seconds while the window is open.
-- ── Desktop widgets (D137): widgets.json is the widgets program's; read fresh before every change,
-- written whole (files.write moves it into place), and the program follows the file. The room is
-- taken as 1080p under a 34 px bar; the program keeps each widget on its own screen when it reads.
local W = require("lib/widgets")
local WROOM = { w = 1920, h = 1046, top = 0 }
local WNAMES = { sleeve = "SLEEVE", lyricstage = "LYRIC STAGE", record = "RECORD", digital = "DIGITAL", analogue = "ANALOGUE",
                 words = "WORDS", info = "INFO", list = "LIST", card = "CARD", commits = "COMMITS", pulse = "PULSE", heat = "ACTIVITY",
                 horizon = "HORIZON", days = "DAYS", scope = "SCOPE", gauges = "GAUGES", month = "MONTH", ring = "RING", slab = "SLAB",
                 ticker = "TICKER", quote = "QUOTE", frame = "FRAME", polaroid = "POLAROID", shelf = "SHELF", column = "COLUMN" }
local KTITLE = { nowplaying = "Now Playing", visualiser = "Visualiser", clock = "Clock", notes = "Notes", github = "GitHub", weather = "Weather",
                 system = "System", calendar = "Calendar", timer = "Focus timer", claude = "Claude", photo = "Photo", launch = "Launcher" }
local function wdoc()
    local ok, raw = pcall(sys.ask, "files.read", W.FILE)
    return (W.parse(ok and raw or nil, json.decode, WROOM))
end
local function show_widgets(d)
    d = d or wdoc()
    local rows = {}
    for _, w in ipairs(d.widgets) do
        local vis = w.kind == "visualiser"
        local what = vis and string.upper(w.mode) or WNAMES[w.layout] or ""
        if w.kind == "github" then what = what .. " · " .. string.upper((w.options or {}).repo or "") end
        rows[#rows + 1] = {
            name = KTITLE[w.kind] or w.kind,
            detail = string.format("%s · %d × %d AT %d, %d", what, w.w, w.h, w.x, w.y),
            mode = vis and string.upper(w.mode) or (WNAMES[w.layout] or ""),
            kind = W.KIND_NUM[w.kind] or 0,
            choice = vis and W.MODE_INDEX[w.mode] or W.LAYOUT_INDEX[w.layout] or 0,
            nlay = vis and 12 or #(W.KIND_LAYOUTS[w.kind] or { 1 }),
            idle = W.IDLE_INDEX[w.idle] or 1,
            opa = w.opacity or 1, bars = tonumber((w.options or {}).bars) or 64,
        }
    end
    model.sw_list = rows
    fact.sw_nviz = W.count_kind(d, "visualiser")
    fact.sw_nnotes, fact.sw_ngh = W.count_kind(d, "notes"), W.count_kind(d, "github")
    -- the one-of kinds already there (D141): weather … launcher, a bit each (their add buttons dim)
    local bits = 0
    for i = 5, 11 do if W.count_kind(d, W.ADD_ORDER[i + 1]) > 0 then bits = bits + 2 ^ (i - 5) end end
    fact.sw_one = bits
end
local function write_widgets(d)
    pcall(sys.call, "files.write", W.FILE, W.encode(d))
    show_widgets(d)
end
apply_widget_style = function(style)
    local d = wdoc()
    write_widgets(W.set_look(d, "style", style))
end
-- D210: the Subsurface's page — its look is read from settings.json by mooi-surface; the widget
-- buttons write widgets.json, which mooi-widgets watches and reloads.
on("surface_above", function()
    write_widgets(W.set_all(wdoc(), "above", true))
end)
on("surface_below", function()
    write_widgets(W.set_all(wdoc(), "above", false))
end)
on("surface_edit", function()
    run("pleamar", { "--say", "mooi-surface", "emit sf_edit 1" })
    run("pleamar", { "--say", "mooi-settings", "quit" })
end)
on("surface_reset", function()
    run("pleamar", { "--say", "mooi-surface", "emit sf_reset" })
end)
show_widgets()
pcall(sys.watch, "files:" .. W.FILE, function() show_widgets() end)
on("sw_choice", function(v)
    v = math.floor(tonumber(v) or 0)
    local d = wdoc()
    local w = d.widgets[math.floor(v / 100) + 1]
    if not w then return end
    if w.kind == "visualiser" then write_widgets(W.set_mode(d, w.id, W.MODES[v % 100 + 1]))
    else write_widgets(W.set_layout(d, w.id, (W.KIND_LAYOUTS[w.kind] or {})[v % 100 + 1], WROOM)) end
end)
on("sw_idle", function(v)
    v = math.floor(tonumber(v) or 0)
    local d = wdoc()
    local w = d.widgets[math.floor(v / 10) + 1]
    if w then write_widgets(W.set_idle(d, w.id, W.IDLES[v % 10 + 1])) end
end)
on("sw_remove", function(v)
    local d = wdoc()
    local w = d.widgets[math.floor(tonumber(v) or -1) + 1]
    if w then write_widgets(W.remove(d, w.id)) end
end)
on("sw_slide", function(v)
    v = math.floor(tonumber(v) or 0)
    local code, val = math.floor(v / 1000), v % 1000
    local d = wdoc()
    local w = d.widgets[math.floor(code / 10) + 1]
    if not w then return end
    if code % 10 == 1 then write_widgets(W.set_field(d, w.id, "opacity", 0.3 + val / 100))
    elseif code % 10 == 2 then write_widgets(W.set_option(d, w.id, "bars", 16 + val)) end
end)
on("sw_add", function(v)
    local d, id = W.add(wdoc(), W.ADD_ORDER[math.floor(tonumber(v) or 0) + 1] or "nowplaying", WROOM)
    if id then write_widgets(d) end
end)
-- ── Settings → Wallpapers: the folders, and Wallhaven's key (D147) ──
local function folders() return type(settings.walls) == "table" and type(settings.walls.folders) == "table" and settings.walls.folders or {} end
local function show_folders()
    local rows = {}
    for i, f in ipairs(folders()) do rows[i] = { path = f, n = "", missing = false } end
    model.wf_list = rows
    for i, f in ipairs(folders()) do
        run("mooi", { "wall", "count", f }, function(out, code)
            if not rows[i] or rows[i].path ~= f then return end
            local n = tonumber(tostring(out or ""):match("%d+"))
            rows[i].missing = code ~= 0 or n == nil
            rows[i].n = rows[i].missing and "NOT THERE" or string.format("%d WALLPAPERS", n)
            model.wf_list = rows
        end)
    end
end
on("wf_add", function()
    local f = tostring(text.wf_new or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
    if f == "" or #f > 240 or f:find("[%c]") or not (f:sub(1, 1) == "/" or f:sub(1, 2) == "~/") then return end
    local list = folders()
    for _, g in ipairs(list) do if g == f then text.wf_new = ""; return end end
    if #list >= 8 then return end
    settings.walls = type(settings.walls) == "table" and settings.walls or {}
    local new = {}
    for i, g in ipairs(list) do new[i] = g end
    new[#new + 1] = f
    settings.walls.folders = new
    text.wf_new = ""
    if save() then show_folders(); run("mooi", { "wall", "index" }, function() end) end
end)
on("wf_del", function(v)
    local k = math.floor(tonumber(v) or -1) + 1
    local list = folders()
    if not list[k] or #list <= 1 then return end          -- one folder at least
    local new = {}
    for i, g in ipairs(list) do if i ~= k then new[#new + 1] = g end end
    settings.walls.folders = new
    if save() then show_folders() end
end)
local SAFE = sys.ask("env", "MOOI_SAFE") == "1"
-- Wallhaven's key (D150): typed hidden, written into mooi's data folder (files.write gives it 0600),
-- emptied from the field at once, then checked with Wallhaven by `mooi wall whkey check`.
local function key_state()
    text.wh_key = "CHECKING…"
    run("mooi", { "wall", "whkey", "check" }, function(out)
        local o = tostring(out or "")
        if o:match("valid") and not o:match("invalid") then text.wh_key = "SAVED · WALLHAVEN TOOK IT · SKETCHY AND NSFW CAN BE CHOSEN"
        elseif o:match("invalid") then text.wh_key = "SAVED · WALLHAVEN REFUSED IT (CHECK THE KEY)"
        elseif o:match("offline") then text.wh_key = "SAVED · WALLHAVEN DID NOT ANSWER"
        else text.wh_key = "NO KEY · SAFE FOR WORK ONLY" end
    end)
end
on("wh_key_save", function()
    local k = tostring(text.wh_key_in or ""):gsub("%s", "")
    text.wh_key_in = ""
    if not k:match("^[%w]+$") or #k < 16 or #k > 64 then text.wh_key = "THAT DOES NOT LOOK LIKE A KEY (32 LETTERS AND DIGITS)"; return end
    if SAFE then return end
    pcall(sys.call, "files.write", "wallhaven.key", k)
    key_state()
end)
on("wh_key_forget", function()
    text.wh_key_in = ""
    pcall(sys.call, "files.remove", "wallhaven.key")
    key_state()
end)
key_state()
after(300, show_folders)

on("wl_settings_open", function()
    run("mooi", { "walls" })
    run("pleamar", { "--say", "mooi-settings", "quit" })
end)
-- D170: the Pill's pads are chosen on the board itself
on("pill_board_edit", function()
    run("pleamar", { "--say", "mooi", "emit pill_edit_open" })
    run("pleamar", { "--say", "mooi-settings", "quit" })
end)
-- D194: Start again after a recovery — the bar's keeper clears it and starts the program
on("lf_act", function(v)
    if math.floor(tonumber(v) or 0) == 1 then run("mooi", { "loom", "restart" }) end
end)
pcall(sys.watch, "files:loom-state.json", function() pcall(loom_status, settings) end)
on("wg_settings_edit", function()
    run("mooi", { "widgets", "edit" })
    run("pleamar", { "--say", "mooi-settings", "quit" })
end)

local function read_displays()
    run("hyprctl", { "-j", "monitors" }, function(out, code)
        local ok, list = pcall(json.decode, out or "")
        if code ~= 0 or not ok or type(list) ~= "table" then return end
        local rows = {}
        for _, m in ipairs(list) do
            rows[#rows + 1] = {
                name = tostring(m.name or "?"),
                model = string.format("%s %s", tostring(m.make or ""), tostring(m.model or "")),
                mode = string.format("%d×%d @ %d Hz · ×%s", tonumber(m.width) or 0, tonumber(m.height) or 0,
                    math.floor((tonumber(m.refreshRate) or 0) + 0.5), tostring(m.scale or 1)),
                place = string.format("AT %d, %d%s", tonumber(m.x) or 0, tonumber(m.y) or 0, (m.transform or 0) ~= 0 and " · TURNED" or ""),
                focused = m.focused == true,
            }
        end
        model.dp_list = rows
    end)
end
read_displays()
every(5000, read_displays)

-- ── Power ──────────────────────────────────────────────────
local battery_now = nil
function show_power()
    local b = battery_now
    if type(b) ~= "table" or not b.present then text.pw_text = "NO BATTERY" else
        text.pw_text = string.format("%d%% · %s", math.floor((tonumber(b.percent) or 0) + 0.5), b.charging and "CHARGING" or "ON BATTERY")
    end
    local v = settings.motion.saver
    fact.saving = v == "always" or (v == "battery" and type(b) == "table" and b.present == true and not b.charging)
end
sys.watch("battery", function(b) battery_now = b; show_power() end)
run("powerprofilesctl", { "get" }, function(_, code) fact.pw_ppd = code == 0 end)

-- ── Advanced ───────────────────────────────────────────────
local home = tostring(sys.ask("env", "HOME"))
local log_path = home .. "/.local/state/mooi/mooi.log"
run("pleamar", { "--version" }, function(out)
    text.adv_version = string.upper(tostring(text.bar_version) .. " · " .. string.gsub(tostring(out or ""), "%s+$", ""))
end)
local function read_advanced()
    run("ps", { "-eo", "%cpu=,rss=,args=" }, function(out)
        for line in string.gmatch(out or "", "[^\n]+") do
            if string.find(line, "live/mooi.plm", 1, true) then
                local cpu, rss = string.match(line, "^%s*([%d.]+)%s+(%d+)")
                if cpu then text.adv_usage = string.format("%s%% OF A CORE · %d MB", cpu, math.floor(tonumber(rss) / 1024 + 0.5)) end
            end
        end
    end)
    run("tail", { "-n", "12", log_path }, function(out)
        local rows = {}
        for line in string.gmatch(out or "", "[^\n]+") do
            local lower = string.lower(line)
            rows[#rows + 1] = { line = line, warn = string.find(lower, "error", 1, true) ~= nil or string.find(lower, "fail", 1, true) ~= nil
                or string.find(lower, "refused", 1, true) ~= nil }
        end
        model.adv_log = rows
    end)
end
read_advanced()
every(3000, read_advanced)
on("adv_act", function(v)
    local n = math.floor(tonumber(v) or 0)
    -- 4: Hyprland reads its config again, then the bar comes back on it (bin/mooi restart-hypr);
    -- windows stay open, mooi's own windows restart with the bar
    if n == 4 then run("mooi", { "restart-hypr" }); return end
    local target = ({ text.bar_path, log_path, tostring(sys.ask("env", "MOOI_SHELL") or (home .. "/Projects/mooi/shell")) })[n]
    if target then run("xdg-open", { target }) end
end)

-- ── The custom base colour ─────────────────────────────────
-- bar.bg_colour as hue, richness and lightness; eight quick picks of the industrial kind.
local QUICK = { "#101418", "#16181c", "#1c1f24", "#22201c", "#1d1218", "#0f1a16", "#14121f", "#1a1410" }
function show_colour()
    local c = ferro.hex(settings.bar.bg_colour) or ferro.hex("#101418")
    local h, s, l = ferro.to_hsl(c)
    fact.cp_h, fact.cp_s, fact.cp_l = math.floor(h + 0.5), math.floor(s * 100 + 0.5), math.floor(l * 100 + 0.5)
    fact.cp_r, fact.cp_g, fact.cp_b = c.r, c.g, c.b
    text.cp_hex = string.upper(ferro.to_hex(c))
end
for n, hex in ipairs(QUICK) do
    local c = ferro.hex(hex)
    fact["cq" .. (n - 1) .. "_r"], fact["cq" .. (n - 1) .. "_g"], fact["cq" .. (n - 1) .. "_b"] = c.r, c.g, c.b
end
on("set_colour", function(v)
    local n = math.floor(tonumber(v) or 0)
    if n >= 9000 then
        settings.bar.bg_colour = QUICK[n - 8999] or settings.bar.bg_colour
    else
        local which, x = math.floor(n / 1000), n % 1000
        local h, s, l = fact.cp_h, fact.cp_s / 100, fact.cp_l / 100
        if which == 1 then h = x elseif which == 2 then s = x / 100 elseif which == 3 then l = x / 100 end
        settings.bar.bg_colour = ferro.to_hex(ferro.hsl(h, s, l))
    end
    save(); paint()
end)

-- ── The shaders' own three colours ─────────────────────────
-- desktop.fx_phos, fx_ember and fx_trace: the `custom` light (desktop.fx_light), any #rrggbb typed
-- into the field beside each. Three stops only, so a colour is a colour and nothing is derived.
local FX = { "fx_phos", "fx_ember", "fx_trace" }
function show_fxcolours()
    for i, key in ipairs(FX) do
        local c = ferro.hex(settings.desktop[key]) or ferro.hex("#7fcfb6")
        fact["fxp" .. i .. "_r"], fact["fxp" .. i .. "_g"], fact["fxp" .. i .. "_b"] = c.r, c.g, c.b
        local hex = string.upper(ferro.to_hex(c))
        if i == 1 then text.fxp1_hex = hex elseif i == 2 then text.fxp2_hex = hex else text.fxp3_hex = hex end
    end
end
on("set_fxcolour", function(v)
    local n = math.floor(tonumber(v) or 0)
    local key = FX[n]
    local typed = ({ text.fxp1_in, text.fxp2_in, text.fxp3_in })[n]
    if not key or typed == nil then return end
    if n == 1 then text.fxp1_in = "" elseif n == 2 then text.fxp2_in = "" else text.fxp3_in = "" end
    local hex = string.lower((tostring(typed):gsub("%s", "")))
    if not string.match(hex, "^#%x%x%x%x%x%x$") then return end   -- not a colour: the field is emptied, nothing saved
    settings.desktop[key] = hex
    show_fxcolours(); save(); paint()
end)
