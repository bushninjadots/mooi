-- mooi's Control Nexus as a deck (D102): its logic. What the deck shows is read only while it is
-- open (the program ends when it closes): the services the scene binds straight to, the windows and
-- workspaces from Hyprland, the machine every 2 s, the bar's own switches every 2 s, and the files
-- the bar writes (nexus-feed.json, updates.json). Where everything goes is lib/nexusdeck's; every
-- press goes to the system (sys.call), to Hyprland, or to the bar (`pleamar --say mooi`), which
-- alone can open its islands, record or run the updater. settings.json is mooi's own (bin/mooi
-- links the data folder); scenes are kept beside it in nexus-scenes.json.

local config = require("lib/config")
local ferro = require("lib/ferro")
local theme = require("lib/theme")
local style = require("lib/style")
local sysinfo = require("lib/sysinfo")
local stats = require("lib/stats")
local forecast = require("lib/forecast")
local weathercache = require("lib/weathercache")
local nexusfeed = require("lib/nexusfeed")
local hypr = require("lib/hypr")
local atlas = require("lib/atlas")
local deck = require("lib/nexusdeck")
local notch = require("lib/notch")

local FILE, SCENES = "settings.json", "nexus-scenes.json"

local function env(name, fallback)
    local ok, v = pcall(sys.ask, "env", name)
    if ok and type(v) == "string" and v ~= "" then return v end
    return fallback
end
local function read(name, kind)
    local ok, v = pcall(sys.ask, "files.read", name, kind or "json")
    return ok and v or nil
end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function launch(cmd, args, done)
    local ok = pcall(run, cmd, args, function(out, code) if done then done(code == 0 and out or nil) end end)
    if not ok and done then done(nil) end
end
local function bar(...) launch("pleamar", { "--say", "mooi", ... }) end
local function decode(out) local ok, t = pcall(json.decode, out or ""); return ok and t or nil end
local SAFE = env("MOOI_SAFE", "") == "1"

-- config.parse takes the file's text (it decodes and checks it itself)
local function read_text(name)
    local ok, v = pcall(sys.ask, "files.read", name)
    return ok and type(v) == "string" and v or nil
end
local settings = config.parse(read_text(FILE), json.decode)
local data_folder = env("XDG_DATA_HOME", env("HOME", "") .. "/.local/share") .. "/pleamar/mooi"
local screen = { w = 1920, h = 1080, mon = nil }
local d = nil                -- the deck's layout (lib/nexusdeck), once the screen is known
local this_stream = nil      -- the sound of the window you are in: its place in `apps`
local waiting_items = {}     -- what is waiting, as lib/nexusdeck listed it
local publish_window         -- defined with the windows, below
local publish_status         -- the lamps and the master caution, below

-- ── The look: the shell's palette, the island style, the corners ──
local function paint()
    local palette = read("palette.json")
    local roles = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not roles then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = roles[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
    local colours = theme.resolve(settings.theme, roles)
    for name, c in pairs(colours or {}) do
        local f = "c_" .. string.gsub(name, "%.", "_")
        -- the scene declares the tokens it draws with; any other the theme names is skipped
        pcall(function() fact[f .. "_r"], fact[f .. "_g"], fact[f .. "_b"] = c.r, c.g, c.b end)
    end
    fact.cn_kind, fact.cn_scale = style.corners(settings)
    fact.isl_style = settings.island.style == "tether" and 1 or 0
    local look = style.facts(settings)
    if look and look.st_glow then fact.st_glow = look.st_glow end
end
paint()

-- ── Who you are ──
local function show_identity()
    local id = type(settings.nexus) == "table" and type(settings.nexus.identity) == "table" and settings.nexus.identity or {}
    local name = type(id.name) == "string" and id.name ~= "" and id.name or "mooi"
    text.nx_name = name
    text.nx_initial = string.upper(string.sub(name, 1, 1))
    local av = type(id.avatar) == "string" and id.avatar or ""
    text.nx_avatar = av ~= "" and (data_folder .. "/" .. av) or ""; fact.nx_avatar_on = av ~= ""
    local bn = type(id.banner) == "string" and id.banner or ""
    text.nx_banner = bn ~= "" and (data_folder .. "/" .. bn) or ""; fact.nx_banner_on = bn ~= ""
end
show_identity()
launch("whoami", {}, function(u) launch("hostname", {}, function(h) text.nx_who = string.lower(trim(u) .. "@" .. trim(h)) end) end)
local noticed = 0
local function notice(t)
    noticed = noticed + 1
    local mine = noticed
    text.nx_notice = t; fact.nx_noticed = true
    after(3500, function() if mine == noticed then fact.nx_noticed = false end end)
end

-- Changing who you are: a picture chosen (a file picker), imported by `mooi identity`
on("nx_pick", function(v)
    local kind = tonumber(v) == 1 and "banner" or "avatar"
    if SAFE then notice("not in safe mode"); return end
    local ok = pcall(run, "zenity", { "--file-selection", "--title=Choose your " .. (kind == "banner" and "banner" or "profile picture"),
                                      "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.avif" }, function(path, code)
        path = trim(path)
        if code ~= 0 or path == "" then return end
        launch("mooi", { "identity", kind, path }, function(out)
            if out then
                settings = config.parse(read_text(FILE), json.decode)
                show_identity(); notice(kind == "banner" and "banner changed" or "picture changed")
            else notice("that picture could not be used") end
        end)
    end)
    if not ok then notice("install zenity to choose a picture") end
end)

-- ── Opening and closing ──
-- The Nexus stays running while it is away (D118): the bar starts it once, hidden, and opening it
-- is a fact flipped, not a program started — no second of compiling before the deck appears, the
-- cards already hold their data, and the machine's graphs keep their history. `closing` is true
-- while it is away; the readers below rest then (the machine's graph keeps a slow sample).
local closing = true
local open_hooks = {}          -- what refreshes as it opens (registered with the readers, below)
local function tell_bar(on) pcall(run, "pleamar", { "--say", "mooi", "fact nexus_open " .. tostring(on) }, function() end) end
local function close(why)
    if closing then return end
    closing = true
    log("nexus · away: " .. tostring(why or "asked"))
    pcall(run, "pleamar", { "--say", "mooi-notch", "emit nt_close" }, function() end)   -- a panel it opened goes with it
    fact.dk_open = false
    pcall(sys.call, "thumbnails.want")
    tell_bar(false)
end
local function open()
    if not closing then return end
    closing = false
    for _, f in ipairs(open_hooks) do f() end
    fact.dk_open = true
    tell_bar(true)
end
on("nx_close", function() close("asked (Esc, × or the mark)") end)
on("nx_toggle", function() if closing then open() else close("asked (the mark)") end end)

-- ── The switches: their state, from the services and from the bar ──
local lit = {}               -- each switch's state by its nx_tog code (0 Wi-Fi … 8 record)
local wifi_on, bt_powered, bt_on = true, false, 0
local net_word = ""          -- what the Wi-Fi tile says it is on: the network, wired, or none
local levels = { volume = 0, muted = false, input = 0, bright = nil }
local apps, media = {}, {}
local publish_console, publish_wait, publish_scenes   -- defined below

-- the power profile (power-profiles-daemon, through the bar): 1 saver · 2 balanced · 3 performance
local power = { prof = 0, ppd = false }
local light = false          -- the palette is a day one
local TOGGLE = {
    [0] = function() pcall(sys.call, "network.wifi", not wifi_on) end,
    [1] = function() pcall(sys.call, "bluetooth.power", not bt_powered) end,
    [2] = function() pcall(sys.call, "audio.mute") end,
    [3] = function() pcall(sys.call, "audio.input_mute") end,
    [4] = function() bar("emit note_dnd") end,
    [5] = function() bar("emit night_light") end,
    [6] = function() bar("emit caffeine") end,
    [7] = function() if power.ppd then bar("emit pw_set " .. tostring(10 + (power.prof % 3) + 1)) end end,
    [8] = function() bar("emit record 0") end,
    [9] = function() bar("emit set_mode 9") end,
    [10] = function() close(); after(320, function() bar("emit shot 0") end) end,
    [11] = function() close(); bar("emit open_clips") end,
}
local function bar_states()
    launch("pleamar", { "--say", "mooi", "get dnd_now", "get caffeine_on", "get recording", "get nl_on", "get pw_prof", "get pw_ppd", "get light" }, function(out)
        if not out then return end
        local got = {}
        for line in out:gmatch("[^\n]+") do got[#got + 1] = trim(line) end
        if #got < 7 then return end
        lit[4], lit[6], lit[8], lit[5] = got[1] == "true", got[2] == "true", got[3] == "true", got[4] == "true"
        power.prof, power.ppd = tonumber(got[5]) or 0, got[6] == "true"
        lit[7] = power.prof == 1
        light = got[7] == "true"
        publish_console(); publish_wait(); publish_scenes(); publish_status()
    end)
end
on("nx_tog", function(v)
    local f = TOGGLE[math.floor(tonumber(v) or -1)]
    if f then f(); after(250, bar_states) end
end)

-- ── Opening things: in the bar (its islands and panels) or as programs ──
local function island(name)
    bar("fact isl_cx " .. tostring(screen.w - 200), "fact open " .. name)
    close()
end
local GO = {
    [1] = function() close(); bar("emit open_settings") end,
    [2] = function() close(); bar("emit power 1") end,
    [3] = function() close(); bar("emit power 0") end,
    [10] = function() close(); pcall(spawn, "kitty", { "--title", "btop", "btop" }, function() end, function() end) end,
    [11] = function() island("calendar") end,
    [12] = function() island("weather") end,
    [13] = function() close(); bar("emit run_updates") end,
    [20] = function() close(); launch("mooi", { "player" }) end,
    [30] = function() close(); bar("emit open_notes") end,
    -- the spine's own connections shelf (D100), beside its tab
    [50] = function() bar("fact isl_sy " .. tostring(math.floor(screen.h / 2 - 140)), "fact isl_shelf true", "fact open shnet"); close() end,
    -- Hyprland reads its config again, then the bar comes back on it (bin/mooi restart-hypr). Asked
    -- first and ended after: the deck is the bar's child, so the refresh takes it away mid-slide.
    [60] = function() launch("mooi", { "restart-hypr" }); close("restarting Hyprland") end,
}
on("nx_go", function(v)
    local f = GO[math.floor(tonumber(v) or -1)]
    if f then f() end
end)

-- ── The deck's place, and its bays ──
local scenes = deck.clean((read(SCENES) or {}).scenes)
local faders_n = 4           -- how many faders the mixer has (its width follows)
-- the parts: your order and the hidden ones (settings.json nexus.parts, nexus.hidden; ✎ on the deck)
local CODE = { window = 0, spaces = 1, mixer = 2, quick = 3, music = 4, machine = 5, today = 6, profile = 7, scenes = 8, waiting = 9, activity = 10 }
local PREFIX = { window = "pw", spaces = "ps", mixer = "pm", quick = "pq", music = "pu", machine = "pc", today = "pt",
                 profile = "pf", scenes = "pn", waiting = "pa", activity = "py" }
local BY_CODE = {}
for id, c in pairs(CODE) do BY_CODE[c] = id end
local parts, hidden
local sizes = {}             -- each card's size along a strip (✎ ⇔): id → s · m · l
local canvas = {}            -- two rows (D119): each card's place and size on the free canvas, as shares of it
local function read_parts()
    local n = type(settings.nexus) == "table" and settings.nexus or {}
    parts = deck.clean_parts(n.parts)
    -- arranged once (✎ saves the order): the hidden ones are yours; never arranged, the shelf's
    hidden = deck.clean_hidden(n.hidden, type(n.parts) == "table" and #n.parts > 0)
    fact.dk_rows = tonumber(n.rows) == 2 and 2 or 1
    fact.nx_large = n.profile == "large"
    fact.dk_notches = n.notches ~= false
    sizes = deck.clean_sizes(n.sizes)
    canvas = deck.clean_canvas(n.canvas)
end
read_parts()
local function save_settings(change)
    if SAFE then return end
    local doc = read(FILE)       -- read again: whatever changed elsewhere is kept
    if type(doc) ~= "table" then return end
    doc.nexus = type(doc.nexus) == "table" and doc.nexus or {}
    change(doc.nexus)
    pcall(sys.call, "files.write", FILE, doc)
end
local function save_parts()
    save_settings(function(n)
        n.parts = parts
        local h = {}
        for _, id in ipairs(parts) do if hidden[id] then h[#h + 1] = id end end
        n.hidden = h
    end)
end
local function edge() return deck.edge_of(type(settings.nexus) == "table" and settings.nexus.edge or nil) end
local relayout_rest      -- the tiles and chips, which follow the bays
local spaces = {}        -- the workspaces of this monitor (lib/nexusdeck spaces)
local function aspect() return screen.full_w and (screen.full_w / screen.full_h) or 16 / 9 end
local function place()
    local top = 0                -- the bar's reserve is already outside the surface
    local opts = { spine = settings.shelves and settings.shelves.on == true, scenes = #scenes + 1,
                   tiles = #spaces + 1, aspect = aspect(), parts = parts, hidden = hidden, faders = faders_n,
                   rows = fact.dk_rows, large = fact.nx_large, sizes = sizes, canvas = canvas }
    -- two rows: a free canvas, every card where you put it and as big as you made it (D119)
    if fact.dk_rows == 2 then d = deck.canvas_layout(edge(), screen.w, screen.h, top, opts)
    else d = deck.layout(edge(), screen.w, screen.h, top, opts) end
    fact.dk_canvas = d.canvas == true
    d.top, d.faders = top, faders_n
    fact.dk_edge = ({ bottom = 0, top = 1, left = 2, right = 3 })[d.edge]
    fact.dk_vert = d.vertical
    fact.dk_x, fact.dk_y, fact.dk_w, fact.dk_h = d.x, d.y, d.w, d.h
    fact.dk_ox, fact.dk_oy = d.out_x, d.out_y
    local nodes, traces = deck.circuit(d)
    model.nodes, model.traces = nodes, traces
    fact.ga_x, fact.ga_y = deck.grow(d, { x = 0, y = 0, w = d.w, h = d.h }, 620, 116, screen.w, screen.h, top)
    for id, pre in pairs(PREFIX) do fact[pre .. "_on"] = false; text[pre .. "_sz"] = string.upper(sizes[id] or "m") end
    for i, part in ipairs(d.parts) do
        local pre = PREFIX[part.id]
        fact[pre .. "_x"], fact[pre .. "_y"], fact[pre .. "_w"], fact[pre .. "_h"] = part.x, part.y, part.w, part.h
        text[pre .. "_n"] = string.format("%02d", i)
        fact[pre .. "_on"] = true
    end
    -- what is not on the deck: hidden by you (a press shows it), or with no room for it here
    local rows = {}
    for _, id in ipairs(parts) do if hidden[id] then rows[#rows + 1] = { word = deck.PARTS[id].word, code = CODE[id], room = false } end end
    for _, id in ipairs(d.dropped) do rows[#rows + 1] = { word = deck.PARTS[id].word, code = CODE[id], room = true } end
    model.hid = rows
    if relayout_rest then relayout_rest() end
end

-- ── The notches off the deck's ends: the side notch (shell/mooi-notch) opens that panel beside the deck ──
-- tab n of the deck: 0 Claude · 1 Music · 2 Weather (the left end) · 3 Workspaces · 4 Wallpapers · 5 GitHub
local NOTCH_TAB = { [0] = 0, [1] = 1, [2] = 4, [3] = 2, [4] = 3, [5] = 5 }
on("dk_notch", function(v)
    local n = math.floor(tonumber(v) or -1)
    local tab = NOTCH_TAB[n]
    if not tab or not d then return end
    local r = notch.from_deck(d, tab, n < 3, screen.w, screen.h)
    launch("pleamar", { "--say", "mooi-notch", "fact nt_px " .. r.px, "fact pn_y " .. r.py, "fact nt_ox " .. r.ox,
                        "fact nt_acy " .. r.acy, "fact nt_dir " .. r.dir, "emit nt_show_deck " .. tab })
end)

-- ── Arranging (✎): parts carried to a new place, hidden, shown again; the edge; the first order ──
on("dk_edit_on", function(v) fact.dk_edit = tonumber(v) == 1; fact.dk_hws, fact.dk_hsc = -1, -1 end)
on("dk_drop", function(v)
    local n = math.floor(tonumber(v) or -1)
    local id = BY_CODE[math.floor(n / 100000000)]
    if not id or not d then return end
    local x, y = math.floor(n % 100000000 / 10000), n % 10000
    if d.canvas then
        -- on the canvas a card stays exactly where it is let go (its middle there, on the grid)
        canvas[id] = deck.canvas_drop(d, id, x, y)
        save_settings(function(s) s.canvas = deck.canvas_list(canvas) end)
        place()
        return
    end
    parts = deck.move(parts, id, deck.place_at(d, x, y), hidden)
    save_parts(); place()
end)
on("dk_hide", function(v)
    local id = BY_CODE[math.floor(tonumber(v) or -1)]
    if not id then return end
    local shown = 0
    for _, x in ipairs(parts) do if not hidden[x] then shown = shown + 1 end end
    if shown <= 1 then notice("one part at least stays"); return end
    hidden[id] = true
    save_parts(); place()
end)
on("dk_show", function(v)
    local id = BY_CODE[math.floor(tonumber(v) or -1)]
    if not id then return end
    hidden[id] = nil
    parts = deck.move(parts, id, #parts + 1, hidden)
    save_parts(); place()
end)
on("dk_reset", function()
    parts, hidden, sizes, canvas = deck.clean_parts(nil), deck.clean_hidden(nil, false), {}, {}
    save_settings(function(s) s.sizes = {}; s.canvas = {} end)
    save_parts(); place()
    notice("every part back")
end)
-- the canvas: a card's corner let go (n = 100000000 · code + 10000 · width + height)
on("dk_resize", function(v)
    local n = math.floor(tonumber(v) or -1)
    local id = BY_CODE[math.floor(n / 100000000)]
    if not id or not d or not d.canvas then return end
    canvas[id] = deck.canvas_resize(d, id, math.floor(n % 100000000 / 10000), n % 10000)
    save_settings(function(s) s.canvas = deck.canvas_list(canvas) end)
    place()
end)
on("dk_size", function(v)
    local id = BY_CODE[math.floor(tonumber(v) or -1)]
    if not id then return end
    sizes[id] = deck.next_size(sizes[id])
    save_settings(function(n) n.sizes = deck.sizes_list(sizes) end)
    place()
    for _, gone in ipairs(d and d.dropped or {}) do
        if gone == id then notice("no room for it that large here: smaller, or two rows"); break end
    end
end)
on("dk_rows_set", function(v)
    local r = tonumber(v) == 2 and 2 or 1
    fact.dk_rows = r
    save_settings(function(n) n.rows = r end)
    place()
end)
on("dk_large_set", function(v)
    local large = tonumber(v) == 1
    fact.nx_large = large
    save_settings(function(n) n.profile = large and "large" or "small" end)
    place()
end)
on("dk_edge_set", function(v)
    local e = deck.EDGES[math.floor(tonumber(v) or 0) + 1]
    if not e then return end
    settings.nexus = type(settings.nexus) == "table" and settings.nexus or {}
    settings.nexus.edge = e
    save_settings(function(n) n.edge = e end)
    place()
end)

-- ── The console: the mixer, the switches, the machine ──
local PROFILES = { "Saver", "Balanced", "Performance" }
local function pct(v) return string.format("%d%%", math.floor((tonumber(v) or 0) * 100 + 0.5)) end
local playing = {}           -- the faders' apps: their places in `apps`
function publish_console()
    local rows = { { word = "All", shown = levels.muted and "mute" or pct(levels.volume), v = levels.muted and 0 or levels.volume, code = 0, hot = false } }
    playing = {}
    for i, a in ipairs(apps) do
        if #playing < 2 and a.playing then
            playing[#playing + 1] = i
            local name = tostring(a.name or a.binary or "app")
            rows[#rows + 1] = { word = string.sub(name, 1, 6), shown = a.muted and "mute" or pct(a.volume), v = a.muted and 0 or (tonumber(a.volume) or 0), code = 9 + #playing, hot = false }
        end
    end
    rows[#rows + 1] = { word = "Mic", shown = lit[3] == false and "off" or pct(levels.input), v = lit[3] == false and 0 or levels.input, code = 1, hot = lit[3] == false }
    if levels.bright then rows[#rows + 1] = { word = "Screen", shown = pct(levels.bright), v = levels.bright, code = 2, hot = false } end
    model.faders = rows
    faders_n = #rows
    if d and d.faders ~= #rows then place() end
    -- the quick settings: { word, state, on, hot, glyph, code }
    local q = {
        { "Wi-Fi", not wifi_on and "Off" or (lit[0] and (net_word ~= "" and net_word or "On") or "No network"), lit[0] == true, false, 0, 0 },
        { "Bluetooth", bt_powered and (bt_on > 0 and string.format("%d connected", bt_on) or "On") or "Off", bt_powered, false, 1, 1 },
        { "Sound", levels.muted and "Muted" or pct(levels.volume), not levels.muted, false, levels.muted and 12 or 2, 2 },
        { "Mic", lit[3] == false and "Muted" or "Live", lit[3] ~= false, false, 3, 3 },
        { "Quiet", lit[4] and "Do not disturb" or "Off", lit[4] == true, false, 4, 4 },
        { "Night", lit[5] and "Warm screen" or "Off", lit[5] == true, false, 5, 5 },
        { "Awake", lit[6] and "Kept awake" or "Idle sleeps", lit[6] == true, false, 6, 6 },
        { "Power", power.ppd and (PROFILES[power.prof] or "Keep") or "No daemon", power.ppd and power.prof == 1, false, 7, 7 },
        { "Record", lit[8] and "Recording" or "The screen", lit[8] == true, lit[8] == true, 9, 8 },
        { light and "Light" or "Dark", light and "Day palette" or "Night palette", light, false, 8, 9 },
        { "Screenshot", "An area", false, false, 10, 10 },
        { "Clipboard", "History", false, false, 11, 11 },
    }
    local rowsq = {}
    for i, t in ipairs(q) do rowsq[i] = { word = t[1], state = t[2], on = t[3], hot = t[4], glyph = t[5], code = t[6] } end
    model.quick = rowsq
end

-- the levels (a drag sends many: the last one in 40 ms is what is asked for)
local pending, flushing = {}, false
local function flush()
    flushing = false
    for code, v in pairs(pending) do
        if code == 0 then pcall(sys.call, "audio.volume", v)
        elseif code == 1 then pcall(sys.call, "audio.input", v)
        elseif code == 2 then pcall(sys.call, "brightness.level", math.max(0.01, v))
        else
            local a = code == 9 and apps[(fact.w_snd and this_stream) or 0] or apps[playing[code - 9] or 0]
            if a and tonumber(a.id) then pcall(sys.call, "audio.app_volume", tonumber(a.id), v) end
        end
    end
    pending = {}
end
on("dk_level", function(v)
    local n = math.floor(tonumber(v) or -1)
    if n < 0 then return end
    pending[math.floor(n / 1000)] = math.max(0, math.min(1, (n % 1000) / 1000))
    if not flushing then flushing = true; after(40, flush) end
end)

-- ── Status, HUD-fashion: each part's lamp (0 standby · 1 active · 2 caution · 3 alert), and the master
-- caution, which names the most pressing thing (the HUD's rule: a warning overrides everything else) ──
local battery = { present = false }
publish_status = function()
    local hot_machine = fact.m_cpu > 0.85 or fact.m_temp > 85
    fact.lp_w = fact.w_ok and 1 or 0
    fact.lp_m = levels.muted and 2 or 1
    fact.lp_q = lit[8] and 3 or 1
    fact.lp_u = media.playing and 1 or 0
    fact.lp_c = hot_machine and 3 or ((fact.m_mem > 0.9 or fact.m_disk > 0.9) and 2 or 1)
    local p = tonumber(battery.percent) or 100
    local why = nil
    if lit[8] then why = "● REC"
    elseif battery.present and p <= 20 and not battery.charging then why = string.format("BATT %d%%", math.floor(p + 0.5))
    elseif fact.m_temp > 85 then why = string.format("HEAT %d°", math.floor(fact.m_temp + 0.5))
    elseif fact.m_cpu > 0.9 then why = string.format("CPU %d%%", math.floor(fact.m_cpu * 100 + 0.5)) end
    fact.dk_caution = why ~= nil
    text.dk_caution_t = why or ""
end

-- ── What the services say ──
pcall(sys.watch, "network", function(n)
    wifi_on = not (type(n) == "table" and n.wifi == false)
    if not wifi_on then net_word = "Wi-Fi is off"
    elseif type(n) == "table" and n.online then
        net_word = n.kind == "wired" and "Wired" or (tonumber(n.strength) or 0) > 0 and string.format("%s · %d%%", tostring(n.name or "Connected"), math.floor(tonumber(n.strength))) or tostring(n.name or "Connected")
    else net_word = "No network" end
    lit[0] = wifi_on and type(n) == "table" and n.online == true
    publish_console(); publish_scenes()
end)
pcall(sys.watch, "bluetooth", function(b)
    bt_powered = type(b) == "table" and b.powered == true
    local on_now = 0
    for _, dv in ipairs(type(b) == "table" and type(b.devices) == "table" and b.devices or {}) do if dv.connected then on_now = on_now + 1 end end
    bt_on = on_now
    lit[1] = bt_powered
    publish_console(); publish_scenes()
end)
pcall(sys.watch, "audio", function(a)
    if type(a) ~= "table" then return end
    apps = type(a.apps) == "table" and a.apps or {}
    levels.volume, levels.muted, levels.input = tonumber(a.volume) or 0, a.muted == true, tonumber(a.input) or 0
    lit[2], lit[3] = not a.muted, not a.input_muted
    publish_console(); publish_scenes()
    if publish_window then publish_window() end
end)
pcall(sys.watch, "brightness", function(b)
    levels.bright = type(b) == "table" and b.present == true and (tonumber(b.level) or 0) or nil
    publish_console(); publish_scenes()
end)

-- ── Now playing: the cover, and the position carried at the player's rate ──
local art_url, covers = nil, 0
local function cover(url)
    if url == art_url then return end
    art_url = url
    if type(url) ~= "string" or url == "" then fact.nx_art_on = false; return end
    local path = url:match("^file://(.*)$")
    if path then
        text.nx_art = (path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)); fact.nx_art_on = true
    elseif url:match("^https?://") then
        covers = covers + 1
        local dest = data_folder .. "/nexus-cover-" .. (covers % 2) .. ".img"
        launch("curl", { "-fsSL", "--max-time", "8", "-o", dest, url }, function(ok)
            if ok and art_url == url then text.nx_art = dest; fact.nx_art_on = true end
        end)
    else fact.nx_art_on = false end
end
local pos, pos_at = 0, os.time()
pcall(sys.watch, "media", function(m)
    media = type(m) == "table" and m or {}
    fact.mus_on = tostring(media.title or "") ~= ""
    cover(media.art)
    pos, pos_at = tonumber(media.position) or 0, os.time()
    publish_status()
end)
every(1000, function()
    if closing then return end
    local len = tonumber(media.length) or 0
    if len <= 0 then fact.nx_prog = 0; return end
    local p = pos + (media.playing and (os.time() - pos_at) * (tonumber(media.rate) or 1) or 0)
    fact.nx_prog = math.min(1, p / len)
end)
-- The Music card's visualiser (D118): the bar owns the one cava and writes the feed while someone
-- asks; the deck asks while it is open and something plays, and reads it then.
local vizfeed = require("lib/vizfeed")
local viz_seq, viz_at = nil, 0
local function rest_viz() for i = 0, 15 do fact["dv" .. i] = 0 end end
local function take_viz()
    if not fact.dk_open then return end
    local ok, raw = pcall(sys.ask, "files.read", vizfeed.FILE)
    if not ok or type(raw) ~= "string" then return end
    local t = vizfeed.decode(raw)
    if not t or not vizfeed.newer(viz_seq, t.seq) then return end
    viz_seq, viz_at = t.seq, os.time()
    if not t.playing then rest_viz(); return end
    local bands = vizfeed.map(t.bands, 16)
    for i = 0, 15 do fact["dv" .. i] = bands[i + 1] end
end
pcall(sys.watch, "files:" .. vizfeed.FILE, take_viz)
-- the watch coalesces quick writes (~4 of 30 lines a second): open and playing, it reads at the feed's pace
every(33, function() if not closing and media.playing == true then take_viz() end end)
every(3000, function()
    if closing then return end
    if fact.dk_open and media.playing == true then run("pleamar", { "--say", "mooi", "emit feed_want" }) end
    if viz_seq and not vizfeed.fresh(viz_at * 1000, os.time() * 1000) then viz_seq, viz_at = nil, 0; rest_viz() end
end)
on("nx_media", function(v)
    local n = tonumber(v)
    pcall(sys.call, n == 0 and "media.previous" or (n == 2 and "media.next" or "media.toggle"))
end)

-- ── The machine: the processor and memory every second while open (every 5 s away), the rest every 4 s ──
local cpu_prev = nil
-- the last 40 s of the processor and the memory (every second), drawn as lines in their part
local HIST = 40
local hist = { cpu = {}, mem = {} }
local function remember(name, v)
    local h = hist[name]
    h[#h + 1] = math.max(0, math.min(1, v))
    if #h > HIST then table.remove(h, 1) end
    local rows = {}
    local off = HIST - #h
    for i = 2, #h do
        rows[#rows + 1] = { x1 = (off + i - 2) / (HIST - 1), y1 = h[i - 1], x2 = (off + i - 1) / (HIST - 1), y2 = h[i] }
    end
    model["sp_" .. name] = rows
end
local function pulse()
    launch("cat", { "/proc/stat" }, function(out)
        local v; v, cpu_prev = sysinfo.cpu(out, cpu_prev)
        if v then fact.m_cpu = v; text.m_cpu_t = pct(v); remember("cpu", v) end
    end)
    launch("cat", { "/proc/meminfo" }, function(out) local m = stats.meminfo(out); fact.m_mem = m.frac; text.m_mem_t = string.format("%.1f G", m.used); remember("mem", m.frac) end)
end
local function machine()
    launch("cat", { "/proc/uptime" }, function(out)
        local secs = tonumber(tostring(out or ""):match("^([%d.]+)"))
        if not secs then return end
        local h, m = math.floor(secs / 3600), math.floor(secs % 3600 / 60)
        text.m_up_t = h >= 24 and string.format("UP %d D %d H", math.floor(h / 24), h % 24) or string.format("UP %d H %02d", h, m)
    end)
    launch("df", { "-P", "/" }, function(out) local s = stats.df(out); fact.m_disk = s.frac; text.m_disk_t = pct(s.frac) end)
    launch("sensors", { "-j" }, function(out)
        local c = sysinfo.temp(decode(out))
        if c then fact.m_temp = c; text.m_temp_t = string.format("%d°", math.floor(c + 0.5)) end
    end)
end
pulse(); machine()
-- open: every second; away: one sample in five, so the graphs have their history when it opens
local pulses = 0
every(1000, function() pulses = pulses + 1; if not closing or pulses % 5 == 0 then pulse() end end)
every(4000, function() if not closing then machine() end end)
every(1000, function() if not closing then publish_status() end end)
open_hooks[#open_hooks + 1] = function() pulse(); machine(); publish_status() end
pcall(sys.watch, "battery", function(b)
    battery = type(b) == "table" and b or { present = false }
    if not battery.present then text.m_bat_t = "AC"; fact.m_bat = 1; fact.m_bat_hot = false
    else
        local p = tonumber(battery.percent) or 0
        text.m_bat_t = string.format("%d%%%s", math.floor(p + 0.5), battery.charging and " +" or "")
        fact.m_bat = p / 100
        fact.m_bat_hot = p <= 20 and not battery.charging
    end
    publish_wait()
end)

-- ── What is waiting ──
local feed, updates, weather = { count = 0, items = {} }, 0, ""
function publish_wait()
    local first = feed.items[1]
    local items = deck.waiting({
        recording = lit[8], quiet = lit[4], saver = lit[7],
        battery = battery.present and battery.percent or nil, charging = battery.charging,
        notes = feed.count, first_note = first and (first.app ~= "" and first.app or first.title) or "",
        updates = updates, weather = weather,
    })
    local rows = {}
    local card = d and d.bays.waiting
    local cw = card and card.w or 220
    for i, it in ipairs(items) do
        if i <= 6 then rows[#rows + 1] = { word = it.word, act = it.act, hot = it.hot, x = 10, y = 32 + (i - 1) * 28, w = cw - 20 } end
    end
    local hot = false
    for _, it in ipairs(items) do if it.hot then hot = true end end
    fact.lp_a = hot and 2 or (#items > 0 and items[1].act ~= "WEEK" and 1 or 0)
    model.wait = rows
    waiting_items = items
end
on("dk_wait", function(v)
    local it = (waiting_items or {})[(tonumber(v) or -1) + 1]
    if not it then return end
    if it.tog >= 0 and TOGGLE[it.tog] then TOGGLE[it.tog](); after(250, bar_states)
    elseif it.go >= 0 and GO[it.go] then GO[it.go]() end
end)
local function show_feed()
    local f = read("nexus-feed.json")
    local items = {}
    for i, it in ipairs(type(f) == "table" and type(f.items) == "table" and f.items or {}) do
        items[i] = { app = tostring(it.app or ""), title = tostring(it.title or ""), ago = nexusfeed.ago(os.time() - (tonumber(it.time) or os.time())) }
    end
    feed = { count = type(f) == "table" and (tonumber(f.count) or #items) or 0, items = items }
    publish_wait()
end
local function show_updates()
    local u = read("updates.json")
    updates = type(u) == "table" and tonumber(u.total) or 0
    publish_wait()
end
local function show_weather(doc)
    local f = forecast.parse(doc.answer)
    if not f then return end
    local kind, word = sysinfo.weather(f.now.code, f.now.day)
    weather = string.format("%s %d°", tostring(word or ""), math.floor((tonumber(f.now.temp) or 0) + 0.5))
    for i, name in ipairs(sysinfo.WEATHER_KINDS) do if name == kind then fact.wx_kind = i - 1 end end
    text.wx_t = string.format("%d°", math.floor((tonumber(f.now.temp) or 0) + 0.5))
    text.wx_word = string.upper(tostring(word or ""))
    fact.wx_ok = true
    publish_wait()
end
-- today: the date large, the week from Monday
do
    local t = os.time()
    text.td_day = os.date("%d", t):gsub("^0", "")
    text.td_week = string.upper(os.date("%A", t))
    text.td_month = os.date("%B %Y", t)
    local wd = tonumber(os.date("%w", t))         -- 0 is Sunday
    local back = (wd + 6) % 7                      -- days since Monday
    local LABELS = { "MO", "TU", "WE", "TH", "FR", "SA", "SU" }
    local rows = {}
    for i = 0, 6 do
        local when = t + (i - back) * 86400
        rows[#rows + 1] = { label = LABELS[i + 1], day = tonumber(os.date("%d", when)), today = i == back }
    end
    model.days = rows
end
do
    local cached = read("nexus-weather.json")
    if type(cached) == "table" and type(cached.answer) == "table" then show_weather(cached) end
    if not weathercache.fresh(cached, os.time(), 600) then
        launch("curl", { "-fsSL", "--max-time", "8", "https://ipinfo.io/json" }, function(out)
            local where = decode(out)
            local lat, lon = weathercache.coordinates(where)
            if not lat then return end
            launch("curl", { "-fsSL", "--max-time", "12", forecast.url(lat, lon) }, function(ans)
                local t = decode(ans)
                if type(t) ~= "table" then return end
                local doc = { at = os.time(), city = where.city, answer = t }
                pcall(sys.call, "files.write", "nexus-weather.json", doc)
                show_weather(doc)
            end)
        end)
    end
end

-- ── Scenes: whole setups at a press ──
local function now_state()
    return {
        quiet = lit[4] == true, night = lit[5] == true, awake = lit[6] == true, saver = power.ppd and power.prof == 1 or nil,
        wifi = wifi_on, bluetooth = bt_powered,
        volume = math.floor(levels.volume * 100 + 0.5),
        brightness = levels.bright and math.floor(levels.bright * 100 + 0.5) or nil,
    }
end
local FLIP = { quiet = 4, night = 5, awake = 6, wifi = 0, bluetooth = 1 }
-- the saved environments (D43, the Overview's): their names, in the bar's order
local function environments()
    local doc = read("environments.json")
    local out = {}
    for _, e in ipairs(type(doc) == "table" and type(doc.envs) == "table" and doc.envs or {}) do out[#out + 1] = tostring(e.name or "") end
    return out
end
local chips = {}
function publish_scenes()
    if not d then return end
    local live = deck.live(scenes, now_state())
    chips = deck.chips(#scenes + 1, d.bays.scenes or { w = 200, h = 214 })
    local rows = {}
    for i, s in ipairs(scenes) do rows[i] = { word = s.name, live = live == i, save = false, env = s.env ~= nil, x = chips[i].x, y = chips[i].y, w = chips[i].w } end
    local c = chips[#scenes + 1]
    rows[#rows + 1] = { word = "+ Save", live = false, save = true, env = false, x = c.x, y = c.y, w = c.w }
    model.scn = rows
end
local function save_scenes()
    if SAFE then return end
    pcall(sys.call, "files.write", SCENES, { scenes = scenes })
end
on("dk_hov_scene", function(v)
    local i = (tonumber(v) or -1) + 1
    local s, c = scenes[i], chips[i]
    if not s or not c or not d then return end
    local rows, w = {}, 32
    for _, word in ipairs(deck.diff(s, now_state())) do
        local cw = 16 + math.floor(#word * 6.2 + 0.5)
        rows[#rows + 1] = { word = word, w = cw }
        w = w + cw + 6
    end
    model.diff = rows
    text.diff_t = string.upper(s.name) .. " WOULD →"
    fact.gs_w = math.max(380, math.min(760, w))
    local a = { x = d.bays.scenes.x + c.x, y = d.bays.scenes.y + c.y, w = c.w, h = c.h }
    fact.gs_x, fact.gs_y = deck.grow(d, a, fact.gs_w, 86, screen.w, screen.h, d.top)
end)
-- "+ Save": the naming panel grows out of its chip, with the saved environments to choose from
local env_names, env_pick = {}, nil
local function publish_envs()
    local rows = {}
    for i, name in ipairs(env_names) do
        if i <= 6 then rows[i] = { word = string.upper(name), on = env_pick == i, w = 18 + math.floor(#name * 5.8 + 0.5) } end
    end
    model.envs = rows
end
on("dk_naming_on", function(v)
    if #scenes >= deck.MAX then fact.dk_naming = false; notice("seven scenes at most: right-press one to remove it"); return end
    text.dk_name_in = ""
    env_names, env_pick = environments(), nil
    publish_envs()
    local c = chips[(tonumber(v) or -1) + 1]
    if c and d then
        local a = { x = d.bays.scenes.x + c.x, y = d.bays.scenes.y + c.y, w = c.w, h = c.h }
        fact.gn_x, fact.gn_y = deck.grow(d, a, 440, 132, screen.w, screen.h, d.top)
    end
end)
on("dk_env", function(v)
    local i = (tonumber(v) or -1) + 1
    env_pick = env_pick ~= i and i or nil
    publish_envs()
end)
on("dk_save_named", function()
    local name = trim(text.dk_name_in)
    local taken = {}
    for _, s in ipairs(scenes) do taken[s.name] = true end
    if name == "" then
        local n = 1; name = "Mine"
        while taken[name] do n = n + 1; name = "Mine " .. n end
    end
    name = string.sub(name, 1, 12)
    if taken[name] then notice(name .. " is taken"); return end
    local s = deck.capture(now_state(), name)
    s.env = env_pick and env_names[env_pick] or nil
    scenes[#scenes + 1] = s
    save_scenes(); place(); publish_scenes()
    notice("saved as " .. name)
end)
on("dk_scene", function(v)
    local i = (tonumber(v) or -1) + 1
    local s = scenes[i]
    if not s then return end
    for _, step in ipairs(deck.steps(s, now_state())) do
        if step.flip == "saver" then bar("emit pw_set " .. (s.saver and "11" or "12"))
        elseif step.flip and TOGGLE[FLIP[step.flip]] then TOGGLE[FLIP[step.flip]]()
        elseif step.level == "volume" then pcall(sys.call, "audio.volume", step.to)
        elseif step.level == "brightness" then pcall(sys.call, "brightness.level", math.max(0.01, step.to)) end
    end
    if s.env then
        for k, name in ipairs(environments()) do
            if name == s.env then bar("emit env_restore_at " .. tostring(k - 1)); break end
        end
    end
    fact.dk_hsc = -1
    notice(s.name)
    after(300, bar_states)
end)
on("dk_unscene", function(v)
    local i = (tonumber(v) or -1) + 1
    local s = scenes[i]
    if not s then return end
    table.remove(scenes, i)
    scenes = deck.clean(scenes)
    fact.dk_hsc = -1
    save_scenes(); place(); publish_scenes()
    notice("removed " .. s.name)
end)

-- ── Activity: the last seven days hour by hour, the apps most used (the bar counts every minute) ──
local function show_activity()
    local doc = read("activity.json")
    local days = type(doc) == "table" and type(doc.days) == "table" and doc.days or {}
    local t = os.time()
    local cells, labels, apps, top, total = {}, {}, {}, 1, 0
    for back = 6, 0, -1 do
        local when = t - back * 86400
        local key = os.date("%Y-%m-%d", when)
        local day = type(days[key]) == "table" and days[key] or {}
        labels[#labels + 1] = { label = string.upper(string.sub(os.date("%a", when), 1, 2)) }
        for h = 0, 23 do
            local m = tonumber(type(day.hours) == "table" and day.hours[tostring(h)] or 0) or 0
            cells[#cells + 1] = m
            total = total + m
            if m > top then top = m end
        end
        for app, m in pairs(type(day.apps) == "table" and day.apps or {}) do apps[app] = (apps[app] or 0) + (tonumber(m) or 0) end
    end
    local heat = {}
    for i, m in ipairs(cells) do heat[i] = { v = m / math.max(top, 1) } end
    model.heat, model.aday = heat, labels
    local list = {}
    for app, m in pairs(apps) do list[#list + 1] = { app = app, m = m } end
    table.sort(list, function(a, b) return a.m > b.m end)
    local rows = {}
    for i = 1, math.min(3, #list) do
        local m = list[i].m
        rows[i] = { word = (tostring(list[i].app):gsub("^.*%.", "")), v = m / math.max(list[1].m, 1),
                    t = m >= 60 and string.format("%d H %02d", math.floor(m / 60), m % 60) or string.format("%d MIN", m) }
    end
    model.topa = rows
    text.act_t = string.format("THIS WEEK · %d H", math.floor(total / 60))
end
show_activity()
pcall(sys.watch, "files:activity.json", show_activity)

-- ── The window you are in, and the workspaces as miniatures ──
local clients, tiles_at, thumbs = {}, {}, {}
local mini = {}              -- the miniature windows: their addresses and workspaces, by place
local tile_rows = {}         -- the tiles as last published
local this = nil             -- the window you are in (a Hyprland client)
local active_ws = nil
local previews = settings.atlas == nil or settings.atlas.previews ~= false
local private = settings.atlas and settings.atlas.private or "off"
local function pretty(class)
    class = tostring(class or ""):gsub("^.*%.", "")
    return (class:gsub("^%l", string.upper))
end
local function picture_of(w)
    if not previews or atlas.private(private, w.app, w.title) then return "" end
    for _, t in ipairs(thumbs) do
        if t.app == w.app and t.title == w.title then return t.picture or "" end
    end
    return ""
end
function publish_window()
    local c = this
    fact.w_ok = c ~= nil
    if not c then return end
    local ws = type(c.workspace) == "table" and tonumber(c.workspace.id) or 0
    text.w_app = pretty(c.class)
    text.w_initial = string.upper(string.sub(text.w_app, 1, 1))
    local _, shown = atlas.private(private, c.class, c.title)
    text.w_title = shown ~= "" and shown or tostring(c.title or "")
    local here = 0
    for _, o in ipairs(clients) do if type(o.workspace) == "table" and tonumber(o.workspace.id) == ws and o.mapped ~= false then here = here + 1 end end
    text.w_where = string.format("WORKSPACE %d · %s · %d HERE", ws, c.floating and "FLOATING" or "TILED", here)
    fact.w_floating, fact.w_pinned, fact.w_full = c.floating == true, c.pinned == true, (tonumber(c.fullscreen) or 0) > 0
    local i, a = deck.stream(apps, c.class, c.pid)
    this_stream = i
    fact.w_snd = a ~= nil
    fact.w_vol = a and (a.muted and 0 or (tonumber(a.volume) or 0)) or 0
    local note = ""
    local k = string.lower(tostring(c.class or ""))
    for _, it in ipairs(feed.items) do
        local app = string.lower(it.app)
        if app ~= "" and (string.find(k, app, 1, true) or string.find(app, k, 1, true)) then note = "↳ " .. it.title .. " · " .. it.ago; break end
    end
    text.w_note = note; fact.w_noted = note ~= ""
    publish_status()
end
function relayout_rest()
    if not d then return end
    publish_scenes(); publish_wait()
    local bay = d.bays.spaces or { x = 0, y = 0, w = 600, h = deck.ROW }   -- hidden: the tiles for Cascade
    local rects = deck.tiles(#spaces, bay, d.vertical, aspect())
    tiles_at = {}
    local rows = {}
    local wins = deck.windows(clients, screen.mon)
    for i, s in ipairs(spaces) do
        local r = rects[i]
        local first = nil
        for _, w in ipairs(wins) do if w.ws == s.id and not first then first = w end end
        rows[i] = { id = s.id, label = first and string.format("%d · %s", s.id, string.lower(pretty(first.app))) or tostring(s.id),
                    n = s.windows > 0 and tostring(s.windows) or "", active = s.active, plus = false, x = r.x, y = r.y, w = r.w, h = r.h }
        tiles_at[s.id] = { r = r, i = i }
    end
    local r = rects[#spaces + 1]
    rows[#rows + 1] = { id = deck.free_space(spaces), label = "NEW", n = "", active = false, plus = true, x = r.x, y = r.y, w = r.w, h = r.h }
    model.tiles = rows
    tile_rows = rows
    local out = {}
    mini = {}
    for _, w in ipairs(wins) do
        local t = tiles_at[w.ws]
        if t and #out < 48 then
            local pic = picture_of(w)
            out[#out + 1] = { x = t.r.x + w.nx * t.r.w, y = t.r.y + w.ny * t.r.h, w = math.max(3, w.nw * t.r.w), h = math.max(3, w.nh * t.r.h),
                              focused = w.focused, app = pretty(w.app), pic = pic, pictured = pic ~= "" }
            mini[#out] = { address = w.address, ws = w.ws }
        end
    end
    model.wins = out
end
-- what Hyprland has, read again (on open, on a change, every 1.5 s while open)
local reading = false
local function read_desktop()
    if reading or closing then return end
    reading = true
    launch("hyprctl", { "-j", "monitors" }, function(mo)
        local mons = decode(mo) or {}
        for _, m in ipairs(mons) do
            if m.focused then
                -- the surface is what the monitor leaves once the bar's reserve is taken (`reserved`:
                -- left, top, right, bottom), and it starts below that reserve
                local s = tonumber(m.scale) or 1
                local r = type(m.reserved) == "table" and m.reserved or {}
                screen.mon = m
                screen.full_w, screen.full_h = math.floor(m.width / s + 0.5), math.floor(m.height / s + 0.5)
                screen.w = screen.full_w - (tonumber(r[1]) or 0) - (tonumber(r[3]) or 0)
                screen.h = screen.full_h - (tonumber(r[2]) or 0) - (tonumber(r[4]) or 0)
                active_ws = type(m.activeWorkspace) == "table" and tonumber(m.activeWorkspace.id) or active_ws
            end
        end
        launch("hyprctl", { "-j", "workspaces" }, function(wo)
            launch("hyprctl", { "-j", "clients" }, function(co)
                reading = false
                clients = decode(co) or {}
                spaces = deck.spaces(decode(wo), screen.mon and screen.mon.name or nil, active_ws)
                this = deck.focused(clients, active_ws)
                if not d or d.sw ~= screen.w or d.sh ~= screen.h or d.n ~= #spaces then place(); d.sw, d.sh, d.n = screen.w, screen.h, #spaces end
                relayout_rest()
                publish_window()
            end)
        end)
    end)
end

-- the windows' pictures: the compositor's own, asked for in a short burst (a picture is kept after it)
local function burst()
    if not previews or closing then return end
    if private == "off" then pcall(sys.call, "thumbnails.want", "all")
    else
        local ids = {}
        for _, t in ipairs(thumbs) do if not atlas.private(private, t.app, t.title) then ids[#ids + 1] = t.id end end
        pcall(sys.call, "thumbnails.want", ids)
    end
    after(900, function() pcall(sys.call, "thumbnails.want") end)
end
if previews then
    pcall(sys.watch, "thumbnails", function(state)
        thumbs = type(state) == "table" and state.list or {}
        relayout_rest()
    end)
end

local first_ws = nil
pcall(sys.watch, "workspaces", function(w)
    local active = type(w) == "table" and tonumber(w.active) or nil
    if first_ws ~= nil and active and active ~= first_ws then close("the workspace changed"); return end
    first_ws = first_ws or active
end)

-- this window's controls
on("dk_win", function(v)
    if not this or not hypr.valid_address(this.address) then return end
    local action = ({ [0] = "float", [1] = "fullscreen", [2] = "pin", [3] = "close" })[math.floor(tonumber(v) or -1)]
    local cmd = action and hypr.dispatch(action, this.address)
    if not cmd then return end
    launch("hyprctl", { "dispatch", cmd }, function() after(200, read_desktop) end)
end)
-- the tiles: go there; the preview: a window focused, this window sent
local function tile(v) return tile_rows[(tonumber(v) or -1) + 1] end
on("dk_ws", function(v)
    local t = tile(v)
    if t then pcall(sys.call, "workspaces.focus", math.floor(t.id)) end
end)
on("dk_send", function(v)
    local t = tile(v)
    if not t or not this then return end
    local cmd = hypr.dispatch("move", this.address, { workspace = math.floor(t.id), follow = false })
    if cmd then launch("hyprctl", { "dispatch", cmd }, function() after(200, read_desktop) end) end
end)
-- a miniature window let go: over another workspace's tile it goes there; over its own, a press
on("dk_wdrop", function(v)
    local n = math.floor(tonumber(v) or -1)
    local m = mini[math.floor(n / 100000000) + 1]
    local px, py = math.floor(n % 100000000 / 10000), n % 10000
    if not m or not d or not d.bays.spaces then return end
    local part = d.bays.spaces
    for _, t in ipairs(tile_rows) do
        local x0, y0 = d.x + part.x + t.x, d.y + part.y + t.y
        if px >= x0 and px <= x0 + t.w and py >= y0 and py <= y0 + t.h + 16 then
            if math.floor(t.id) == m.ws then pcall(sys.call, "workspaces.focus", m.ws); return end
            local cmd = hypr.dispatch("move", m.address, { workspace = math.floor(t.id), follow = false })
            if cmd then launch("hyprctl", { "dispatch", cmd }, function() after(150, read_desktop); notice(string.format("moved to %d", math.floor(t.id))) end) end
            return
        end
    end
end)
local big_windows = {}
on("dk_hov_ws", function(v)
    local t = tile(v)
    if not t or not d then return end
    local pw = 500
    local ph = math.floor(pw / aspect() + 0.5)
    fact.gw_w, fact.gw_h = pw + 20, ph + 54
    fact.gw_free = t.plus == true
    local part = d.bays.spaces
    if not part then return end
    local a = { x = part.x + t.x, y = part.y + t.y, w = t.w, h = t.h }
    fact.gw_x, fact.gw_y = deck.grow(d, a, fact.gw_w, fact.gw_h, screen.w, screen.h, d.top)
    local rows = {}
    big_windows = {}
    for _, w in ipairs(deck.windows(clients, screen.mon)) do
        if w.ws == t.id and #rows < 16 then
            local pic = picture_of(w)
            rows[#rows + 1] = { x = 10 + w.nx * pw, y = 10 + w.ny * ph, w = math.max(6, w.nw * pw), h = math.max(6, w.nh * ph),
                                focused = w.focused, app = pretty(w.app), pic = pic, pictured = pic ~= "" }
            big_windows[#rows] = w.address
        end
    end
    model.big = rows
    text.big_t = t.plus and string.format("WORKSPACE %d · NEW", t.id) or string.format("WORKSPACE %d · %d WINDOW%s", t.id, #rows, #rows == 1 and "" or "S")
    burst()
end)
on("dk_big", function(v)
    local address = big_windows[(tonumber(v) or -1) + 1]
    local cmd = address and hypr.dispatch("focus", address)
    if cmd then launch("hyprctl", { "dispatch", cmd }) end
end)

-- ── The wallpaper under the miniatures, and keeping up with the settings ──
do
    -- the picture the desktop wears now, made small (and given a name an image is known
    -- by: the studio's copy has none) for the miniatures
    local small = data_folder .. "/nexus-wall.jpg"
    launch("magick", { env("HOME", "") .. "/.cache/current_wallpaper[0]", "-resize", "640x360^", "-gravity", "center", "-extent", "640x360", "-quality", "82", small }, function(ok)
        if ok then text.dk_wall = small .. "?" .. tostring(os.time() % 100000); fact.dk_wall_on = true end
    end)
end
pcall(sys.watch, "files:" .. FILE, function()
    settings = config.parse(read_text(FILE), json.decode)
    paint(); show_identity(); read_parts()
    previews = settings.atlas == nil or settings.atlas.previews ~= false
    private = settings.atlas and settings.atlas.private or "off"
    place()
end)
pcall(sys.watch, "files:nexus-feed.json", show_feed)
pcall(sys.watch, "files:updates.json", show_updates)
pcall(sys.watch, "files:palette.json", paint)

show_feed(); show_updates()
bar_states()
every(2000, function() if not closing then bar_states() end end)
read_desktop()
every(1500, function() if not closing then read_desktop() end end)
open_hooks[#open_hooks + 1] = function()
    show_feed(); show_updates(); bar_states(); read_desktop()
    after(40, burst)
    after(1300, burst)       -- the compositor's pictures often arrive on the second asking
    if media.playing == true then run("pleamar", { "--say", "mooi", "emit feed_want" }) end
end
-- Started to be seen at once (`MOOI_NEXUS_OPEN=1`: the bar had no Nexus running when it was asked
-- for), or started hidden, to wait for the mark.
if tostring(sys.ask("env", "MOOI_NEXUS_OPEN") or "") == "1" then after(40, open) end
