-- The desktop widgets' logic (D137): widgets.json through lib/widgets into the scene's model, what
-- is playing (any player, through the media service), its lyrics (player/lyricfetch, the
-- player's own cache) and the bar's visualiser feed. The data folder is mooi's (bin/mooi links
-- mooi-widgets to it), so settings.json, palette.json and widgets.json are the shell's own.

local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")
local W = require("lib/widgets")
local P = require("lib/player")
local vizfeed = require("lib/vizfeed")
local coverart = require("lib/cover")
local WM = require("lib/wallmap")
local CF = require("lib/clockface")
local GP = require("lib/ghparse")
local NOTES = require("lib/notes")
local sysinfo = require("lib/sysinfo")
local wire = require("bmo/wire")
local forecast = require("lib/forecast")
local calendar = require("lib/calendar")
local DD = require("lib/deskdata")
local apps_lib = require("lib/apps")
local DAYNAMES = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end
local HOME = tostring(sys.ask("env", "HOME"))
local folder = (function()
    local ok, f = pcall(sys.ask, "files.folder")
    return ok and type(f) == "string" and f ~= "" and f or (HOME .. "/.local/share/pleamar/mooi")
end)()
local COVERS = folder .. "/player-covers"
local fetch = require("player/lyricfetch")({ read = read })
-- the player's caches, which this may be the first to use
run("mkdir", { "-p", COVERS, folder .. "/player-lyrics" })

-- ── The shell's colours, corners and finish, as the board wears them ──
local settings = config.parse(read("settings.json"), json.decode)
local roles = nil        -- the palette's roles as painted (the accents lean towards phos)
local wall = nil         -- the wallpaper as tools/wallmap.py read it (lib/wallmap), nil until known
local apply_wall         -- defined with the wallpaper's watch below
local wall_light         -- the shadows' direction from the wallpaper's light (D141), defined with the feeders
local gh_lanes, show_github = {}, nil   -- the GitHub widgets' repositories (D140), and their drawing
local desk_at = nil      -- desk mode (D141): each widget's place in the gathering, by slot; nil when off
local on_kinds = nil     -- the D141 feeders, told when the widgets change (defined with them below)
local palette = read("palette.json", "json")
local function paint()
    fact.cn_kind, fact.cn_scale = style.corners(settings)
    local look = style.facts(settings)
    if look and look.st_glow then fact.st_glow = look.st_glow end
    local motion = type(settings.motion) == "table" and settings.motion or {}
    fact.viz_still = motion.reduced == true or motion.saver == "always"
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    roles = out
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
end
paint()
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)
pcall(sys.watch, "files:settings.json", function()
    settings = config.parse(read("settings.json"), json.decode)
    paint()
    if apply_wall then apply_wall() end
end)

-- ── The widgets ──
-- The room under the bar: the surface says how big it is once it is placed (`screen` is not known
-- while this file loads), so until then a 1080p screen under a 34 px bar.
local room = { w = 1920, h = 1046, top = 0 }
local doc = nil
local playing = false
local viz_extra = {}         -- D155: each visualiser lane's slot opacity and smoothing, for mooi-viz

-- Calm: nothing pointed at and no fade under way, so the surface can drop to a few frames a second.
local hovered, calm_at = {}, 0
local function unsettle()
    fact.wg_calm = false
    calm_at = os.time() + 2
end
every(1000, function()
    if fact.wg_calm or fact.editing or next(hovered) ~= nil or os.time() < calm_at then return end
    fact.wg_calm = true
end)

-- The widgets' own switches in settings.json (D139): depth and mood.
local function widgets_cfg()
    local t = type(settings.widgets) == "table" and settings.widgets or {}
    return { depth = t.depth ~= false, mood = t.mood ~= false }
end
local mood_now = { glow = 1, pace = 1, soft = 0 }

-- The editor's selection (widget ids) and its undo history (D138).
local selected, hist = {}, W.history()
local standing_down = false     -- another program is the widgets (save below)
-- what a gesture holds while it lasts (a carried widget, a handle, a slider, a marquee), the panel's
-- place once dragged, and the doc as last saved (what the file watch compares against)
local pending, grab, slide, marq0, panel_at, last_saved = nil, nil, nil, nil, nil, nil
local show_selection     -- defined with the editor below; load() needs it
local function is_sel(id) for _, s in ipairs(selected) do if s == id then return true end end; return false end

local function publish()
    if standing_down then return end
    local rows = {}
    for _, w in ipairs(doc.widgets) do
        local st = W.idle_state(w, playing)
        local o = w.options or {}
        rows[#rows + 1] = {
            kind = W.KIND_NUM[w.kind] or 0,
            lay = W.LAYOUT_INDEX[w.layout] or 0,
            mode = W.MODE_INDEX[w.mode] or 0,
            x = w.x, y = w.y, w = w.w, h = w.h, u = W.scale(w),
            idle = W.IDLE_INDEX[w.idle] or 1,
            st = ({ shown = 0, rest = 1, hidden = 2, marker = 3 })[st],
            op = ({ shown = 1, rest = 0.35, hidden = 0, marker = 0 })[st],
            glow = tonumber(o.glow) or 0, plate = o.plate == true,
            lyr = o.lyrics ~= false, prog = o.progress ~= false,
            gh = st == "hidden" or st == "marker",
            bars = math.floor(tonumber(o.bars) or 64), gap = tonumber(o.gap) or 0.3,
            peaks = o.peaks ~= false, refl = o.reflection == true,
            vslot = -1, opa = w.opacity or 1, txt = tonumber(o.text) or 1, locked = w.locked == true,
            sel = is_sel(w.id),
            h24 = o.h24 ~= false, secs = o.seconds ~= false, viz = o.viz == true, pop = o.pop ~= false,
            dx = 0, dy = 0, grp = 0,
            adapt = o.adapt ~= false, behind = false, tn = 0, hz = 0.32, ar = 0, ag = 0, ab = 0, over = false,
        }
        local r = rows[#rows]
        -- the wallpaper under it (D139): readable tone and haze, a local accent, depth
        local wl = widgets_cfg()
        r.behind = o.behind == true and wl.depth and wall ~= nil and wall.depth and wall.cutpath ~= ""
        if wall then
            local u = WM.under(wall, w.x, w.y, w.w, w.h, room)
            r.over = u.s > 0.3
            if r.adapt then
                local phos = roles and roles.phos or { r = 0.6, g = 0.8, b = 0.7 }
                local hull = roles and roles.hull or { r = 0.06, g = 0.08, b = 0.08 }
                if w.kind == "visualiser" then
                    -- no haze behind a visualiser: its colours read against the picture or its plate
                    local c = WM.accent(u, phos, o.plate and hull or WM.grey(u.l))
                    r.ar, r.ag, r.ab = c.r, c.g, c.b
                else
                    local L = WM.look(u, { plate = o.plate == true, phos = phos, hull = hull })
                    r.tn, r.hz = L.tn, L.hz
                    r.ar, r.ag, r.ab = L.accent.r, L.accent.g, L.accent.b
                end
            end
        end
    end
    -- which visualiser draws from which lane's bars (three at most, lib/widgets MAX_VIZ)
    local nv = 0
    for i, w in ipairs(doc.widgets) do
        if w.kind == "visualiser" then nv = nv + 1; rows[i].vslot = math.min(nv, 3) - 1 end
    end
    -- groups (their tags in edit mode) and desk mode's offsets to the gathering
    local gnum = W.group_numbers(doc)
    for i, r in ipairs(rows) do
        r.grp = gnum[i] or 0
        local at = desk_at and desk_at[i]
        if at then r.dx, r.dy = at.x - r.x, at.y - r.y end
    end
    -- a group rests as one: shown while any of it is
    local gshown = {}
    for i, w in ipairs(doc.widgets) do if w.group and rows[i].st == 0 then gshown[w.group] = true end end
    for i, w in ipairs(doc.widgets) do
        if w.group and gshown[w.group] and rows[i].st > 0 then rows[i].st, rows[i].op, rows[i].gh = 0, 1, false end
    end
    model.wg = rows
    -- the cut-out is drawn only round the widgets behind it (a full screen of it costs every frame)
    local l, t, r2, b2 = math.huge, math.huge, -math.huge, -math.huge
    for _, r in ipairs(rows) do
        if r.behind then
            l, t = math.min(l, r.x - 8), math.min(t, r.y - 8)
            r2, b2 = math.max(r2, r.x + r.w + 8), math.max(b2, r.y + r.h + 8)
        end
    end
    if l < math.huge then fact.cut_x, fact.cut_y, fact.cut_w, fact.cut_h = l, t, r2 - l, b2 - t
    else fact.cut_w, fact.cut_h = 0, 0 end
    fact.wg_nviz = W.count_kind(doc, "visualiser")
    fact.wg_nnt, fact.wg_ngh, fact.wg_count = W.count_kind(doc, "notes"), W.count_kind(doc, "github"), #doc.widgets
    -- the lanes: each visualiser's place and look, read by the scene's three Lane groups
    local lane = 0
    for i, w in ipairs(doc.widgets) do
        if w.kind == "visualiser" and lane < 3 then
            local r = rows[i]
            local L = ({ "A", "B", "C" })[lane + 1]
            local f = "l" .. L .. "_"
            fact[f .. "on"], fact[f .. "k"] = true, i - 1
            fact[f .. "x"], fact[f .. "y"], fact[f .. "w"], fact[f .. "h"], fact[f .. "u"] = r.x, r.y, r.w, r.h, r.u
            fact[f .. "mode"], fact[f .. "n"], fact[f .. "gap"], fact[f .. "glow"] = r.mode, r.bars, r.gap, r.glow
            fact[f .. "ang"] = tonumber((w.options or {}).angle) or 0
            fact[f .. "lean"] = tonumber((w.options or {}).lean) or 0
            fact[f .. "peaks"], fact[f .. "refl"], fact[f .. "plate"] = r.peaks, r.refl, r.plate
            fact[f .. "st"], fact[f .. "gh"], fact[f .. "opa"] = r.st, r.gh, r.opa
            fact[f .. "sel"] = r.sel and not r.locked
            fact[f .. "ad"], fact[f .. "beh"] = r.adapt and wall ~= nil, r.behind
            fact[f .. "ar"], fact[f .. "ag"], fact[f .. "ab"] = r.ar, r.ag, r.ab
            fact[f .. "dx"], fact[f .. "dy"] = r.dx, r.dy
            lane = lane + 1
        end
    end
    for j = lane, 2 do fact["l" .. ({ "A", "B", "C" })[j + 1] .. "_on"] = false end
    -- D155: what mooi-viz needs besides the lane facts: each lane's slot opacity and how slowly it falls
    viz_extra = {}
    lane = 0
    for i, w in ipairs(doc.widgets) do
        if w.kind == "visualiser" and lane < 3 then
            lane = lane + 1
            viz_extra[lane] = { po = rows[i].op or 1, sm = tonumber((w.options or {}).smooth) or 0.5 }
        end
    end
    local rec = false
    for _, w in ipairs(doc.widgets) do if w.kind == "nowplaying" and w.layout == "record" then rec = true end end
    fact.np_rec = rec
    -- notes (one) and GitHub (two) are drawn as lanes too: their lists cannot sit inside the loop
    local function lane_facts(f, i, r)
        fact[f .. "on"], fact[f .. "k"] = true, i - 1
        fact[f .. "x"], fact[f .. "y"], fact[f .. "w"], fact[f .. "h"], fact[f .. "u"] = r.x, r.y, r.w, r.h, r.u
        fact[f .. "lay"], fact[f .. "st"], fact[f .. "gh"], fact[f .. "opa"] = r.lay, r.st, r.gh, r.opa
        fact[f .. "beh"], fact[f .. "plate"], fact[f .. "sel"] = r.behind, r.plate, r.sel and not r.locked
        fact[f .. "tn"], fact[f .. "hz"] = r.tn, r.hz
        fact[f .. "ad"] = r.adapt and r.ar + r.ag + r.ab > 0
        fact[f .. "ar"], fact[f .. "ag"], fact[f .. "ab"] = r.ar, r.ag, r.ab
        fact[f .. "dx"], fact[f .. "dy"] = r.dx, r.dy
    end
    -- the D141 lanes (one each)
    local LANE = { weather = "wh_", system = "sp_", calendar = "cd_", launch = "ln_" }
    local lit = {}
    for i, w in ipairs(doc.widgets) do
        local f = LANE[w.kind]
        if f and not lit[f] then lit[f] = true; lane_facts(f, i, rows[i]) end
    end
    for _, f in pairs(LANE) do if not lit[f] then fact[f .. "on"] = false end end
    for i = 5, 11 do fact["wg_has" .. i] = W.count_kind(doc, W.ADD_ORDER[i + 1]) > 0 end
    fact.wg_style = W.STYLE_INDEX[doc.style or "adaptive"] or 0
    fact.wg_shad, fact.wg_ambon = doc.shadows == true, doc.ambient ~= false
    local nn, ng = 0, 0
    gh_lanes = {}
    for i, w in ipairs(doc.widgets) do
        if w.kind == "notes" and nn < 1 then nn = nn + 1; lane_facts("nl_", i, rows[i])
        elseif w.kind == "github" and ng < 2 then
            ng = ng + 1
            lane_facts("g" .. ng .. "_", i, rows[i])
            gh_lanes[ng] = (w.options or {}).repo or "bushninjadots/mooi"
        end
    end
    if nn == 0 then fact.nl_on = false end
    for j = ng + 1, 2 do fact["g" .. j .. "_on"] = false end
    -- the second's tick: the clocks, the timer and Claude's light
    fact.any_clock = W.count_kind(doc, "clock") + W.count_kind(doc, "timer") + W.count_kind(doc, "claude") > 0
    if show_github then show_github() end
    if on_kinds then on_kinds() end
    -- a slot that went (removed, or the file changed) cannot keep the surface awake
    hovered = W.prune_hover(hovered, #rows)
    for i = 0, W.MAX - 1 do
        local r = rows[i + 1]
        fact["op" .. i] = r and r.op or 0
        if not r then fact["hl" .. i] = 0 end
    end
    unsettle()
end

-- ── D155: the visualisers drawn by mooi-viz ──
-- Where each one is and how it looks, sent whenever any of it changes (looked at every 400 ms: a
-- string of what it would be told); `hold` while the widgets draw them themselves (editing, desk mode).
local VIZ_KEYS = { "on", "x", "y", "w", "h", "u", "mode", "n", "gap", "glow", "ang", "lean", "peaks", "refl", "plate", "st", "gh",
                   "opa", "ad", "ar", "ag", "ab" }
local viz_sent = nil
local function viz_cmds()
    local hold = fact.editing or fact.wg_desk or (tonumber(fact.wg_dkp) or 0) > 0.01
    local c = { "fact hold " .. tostring(hold), "fact viz_still " .. tostring(fact.viz_still == true),
                "fact mood_glow " .. tostring(tonumber(fact.mood_glow) or 1), "fact mood_pace " .. tostring(tonumber(fact.mood_pace) or 1) }
    for k, L in ipairs({ "A", "B", "C" }) do
        local f = "l" .. L .. "_"
        for _, key in ipairs(VIZ_KEYS) do
            local v = fact[f .. key]
            if v ~= nil then c[#c + 1] = "fact " .. f .. key .. " " .. tostring(v) end
        end
        local e = viz_extra[k] or { po = 1, sm = 0.5 }
        c[#c + 1] = "fact " .. f .. "po " .. tostring(e.po)
        c[#c + 1] = "fact " .. f .. "sm " .. tostring(e.sm)
    end
    return c
end
local function viz_send(force)
    if not fact.viz_ext or standing_down then return end
    local c = viz_cmds()
    local key = table.concat(c, ";")
    if key == viz_sent and not force then return end
    viz_sent = key
    local args = { "--say", "mooi-viz" }
    for _, x in ipairs(c) do args[#args + 1] = x end
    run("pleamar", args, function() end)
end
every(400, function() viz_send(false) end)
on("wg_viz_hello", function() fact.viz_ext = true; viz_send(true) end)
-- whether it is up (the bar starts it beside the widgets): asked every three seconds
every(3000, function()
    run("pleamar", { "--say", "mooi-viz", "get hold" }, function(_, code)
        local up = code == 0
        if up and not fact.viz_ext then fact.viz_ext = true; viz_send(true)
        elseif not up and fact.viz_ext then fact.viz_ext = false; viz_sent = nil end
    end)
end)

local function load()
    local raw = read(W.FILE)
    local d, problems = W.parse(raw, json.decode, room)
    for _, p in ipairs(problems) do log("widgets · " .. p) end
    if d.bad then
        run("mv", { "-f", folder .. "/" .. W.FILE, folder .. "/" .. W.FILE .. ".bad" })
        log("widgets · widgets.json kept as widgets.json.bad; the defaults are shown")
    end
    doc = d
    publish()
    if show_selection then show_selection() end
end

-- Saved whole: files.write writes beside the file and then moves it into place.
-- Only the program that answers to `mooi-widgets` is the widgets: a second one (Pleamar starts it
-- under another name) would draw everything twice and undo the first one's saves (D139 audit). It
-- checks its own token through that name, and an extra copy stands down: nothing drawn, nothing saved.
-- (math.random is the same in every copy here, so the token is the pid of a `cat` this copy runs:
-- unique by definition)
fact.wg_token = 0
run("cat", { "/proc/self/stat" }, function(out)
    fact.wg_token = tonumber(tostring(out or ""):match("^(%d+)")) or os.time()
end)
local function save()
    if standing_down then return end
    last_saved = W.encode(doc)
    pcall(sys.call, "files.write", W.FILE, last_saved)
end
-- a gesture ends without being saved: back to the doc it started from
local function drop_gestures(restore)
    if restore and slide then doc = slide.before end
    pending, grab, slide, marq0 = nil, nil, nil, nil
    fact.wg_rk, fact.wg_dk = -1, -1
end

load()
local function check_instance()
    run("pleamar", { "--say", "mooi-widgets", "get wg_token" }, function(out, code)
        local t = tonumber(tostring(out or ""):match("[%d%.]+"))
        if fact.wg_token == 0 then return end
        if code == 0 and t and math.floor(t) ~= math.floor(fact.wg_token) and not standing_down then
            standing_down = true
            model.wg = {}
            for _, L in ipairs({ "A", "B", "C" }) do fact["l" .. L .. "_on"] = false end
            log("widgets · another mooi-widgets is the widgets; this copy stands down")
        end
    end)
end
after(1500, check_instance)
every(10000, check_instance)
pcall(sys.watch, "files:" .. W.FILE, function()
    local raw = read(W.FILE)
    if raw == nil then return end
    local ok, t = pcall(json.decode, raw)
    if ok and last_saved and W.same_doc(t, last_saved) then return end
    if ok and not grab and not slide and not W.should_reload(t, doc) then return end
    -- changed elsewhere (Settings): undo would bring back what is not there any more, and a held
    -- slider or handle would put back what was there when it was taken
    drop_gestures(false)
    W.clear(hist)
    load()
end)
-- ── The wallpaper (D139): read once per picture by `mooi wallmap` (cached), applied from wall-map.json ──
local CURRENT = HOME .. "/.cache/current_wallpaper_source"
local current_wall, asked_for, in_flight = nil, nil, false
apply_wall = function()
    if wall_light then wall_light() end
    -- never rebuild the widgets under a hand that is carrying, pulling or sliding (D138 fix)
    if pending or grab or slide then after(400, apply_wall); return end
    local t = read("wall-map.json", "json")
    local m = WM.parse(t)
    -- only the picture on the desktop now (a slower read of an older one is not applied)
    if m and current_wall and m.src ~= current_wall then m = nil end
    wall = m
    local wl = widgets_cfg()
    mood_now = (wall and wl.mood) and WM.mood(wall.mood) or { glow = 1, pace = 1, soft = 0 }
    fact.mood_glow, fact.mood_pace = mood_now.glow, mood_now.pace
    fact.wall_depth = wall ~= nil and wall.depth and wl.depth and (wall.cutpath or "") ~= ""
    text.wall_cut = fact.wall_depth and wall.cutpath or ""
    fact.wall_bar = wall and math.max(0, wall.h - room.h) or 34
    -- the subject cells, for edit mode's shading
    local rows_s = {}
    if wall then
        local cw, ch = wall.w / wall.cols, wall.h / wall.rows
        for i, c in ipairs(wall.cells) do
            if (c.s or 0) > 0.3 then
                local col, row = (i - 1) % wall.cols, math.floor((i - 1) / wall.cols)
                rows_s[#rows_s + 1] = { x = col * cw, y = row * ch - fact.wall_bar, w = cw, h = ch }
            end
        end
    end
    model.subj = rows_s
    publish()
end
-- one reading at a time (a new picture takes ~40 s of rembg the first time); when one ends for a
-- picture that is no longer the one shown, the shown one is asked for next (instant if cached)
local function check_wall()
    run("readlink", { "-f", CURRENT }, function(out, code)
        local p = tostring(out or ""):gsub("%s+$", "")
        if code ~= 0 or p == "" then return end
        if p ~= current_wall then
            current_wall = p
            apply_wall()
        end
        if in_flight or asked_for == p or (wall and wall.src == p) then return end
        asked_for, in_flight = p, true
        -- the subject cut out (rembg, heavy) only while depth is on; the map alone otherwise (D150)
        local args = widgets_cfg().depth and { "wallmap", p } or { "wallmap", p, "nocut" }
        run("mooi", args, function(_, c2)
            in_flight = false
            if c2 ~= 0 then log("widgets · wallmap failed for " .. p) end
            apply_wall()
            -- read for an older picture (or failed): let the shown one be asked for again, once
            if c2 == 0 and p ~= current_wall then asked_for = nil end
        end)
    end)
end
check_wall()
every(2000, check_wall)
pcall(sys.watch, "files:wall-map.json", apply_wall)

-- packed as width · 4096 + height (under 2^24)
on("wg_room", function(v)
    v = math.floor(tonumber(v) or 0)
    local w, h = math.floor(v / 4096), v % 4096
    if w < 200 or h < 200 or (w == room.w and h == room.h) then return end
    room.w, room.h = w, h
    drop_gestures(false)
    W.clear(hist)
    load()
    -- the cut-out's offset and the subject's cells follow the room (the bar's height)
    if apply_wall then apply_wall() end
end)

-- ── What is playing ──
local np = { key = nil, data = nil, t = 0, at = os.time(), rate = 1, len = 0, sung = nil, art = nil, art_path = nil }
local function set_cover(path)
    text.np_cover_path = path or ""
    fact.np_cover_on = path ~= nil and path ~= ""
end
local function show_lyric()
    local a, b, c, at = P.lyric_lines(np.data, np.t, 0)
    if at == np.sung then return end
    np.sung = at
    text.np_prev, text.np_line, text.np_next = a, b, c
    fact.np_sung = at > 0 and b ~= ""
    -- the new line fades in
    fact.np_line_in = 0
    after(40, function() fact.np_line_in = 1 end)
end
local function lyrics_for(m)
    local artist, title = tostring(m.artist or ""), tostring(m.title or "")
    local key = "remote:" .. artist .. "\t" .. title
    if key == np.key then return end
    np.key, np.data, np.sung = key, nil, nil
    show_lyric()
    if artist == "" or title == "" then return end
    local path = coverart.path(type(m.url) == "string" and m.url or "")
    fetch(key, artist, title, tostring(m.album or ""), np.len, path, function(raw, _)
        if np.key ~= key then return end
        if raw == "none" or raw == "instrumental" or raw == "" then np.data = nil
        else np.data = P.parse_lrc(raw) end
        show_lyric()
    end)
end
-- shuffle and repeat as the player has them (playerctl answers On/Off and None/Playlist/Track)
local function read_modes()
    run("playerctl", { "shuffle" }, function(out, code) if code == 0 then fact.np_shuf = tostring(out):match("On") ~= nil end end)
    run("playerctl", { "loop" }, function(out, code)
        if code == 0 then fact.np_loop = tostring(out):match("Track") and 2 or (tostring(out):match("Playlist") and 1 or 0) end
    end)
end
local function show_progress()
    fact.np_progress = np.len > 0 and math.min(1, np.t / np.len) or 0
    text.np_tpos = np.len > 0 and DD.mmss(math.min(np.t, np.len)) or ""
    text.np_tlen = np.len > 0 and DD.mmss(np.len) or ""
    fact.np_arm_at = P.arm(fact.np_progress, playing and "playing" or (fact.np_has and "paused" or "stopped"))
end

pcall(sys.watch, "media", function(m)
    local has = type(m) == "table" and type(m.title) == "string" and m.title ~= ""
    local was = playing
    playing = has and m.playing == true
    fact.np_has, fact.np_playing = has, playing
    if not has then
        text.np_title, text.np_artist = "", ""
        np.key, np.data, np.len, np.t = nil, nil, 0, 0
        set_cover(nil)
    else
        text.np_title, text.np_artist = m.title, tostring(m.artist or "")
        np.t, np.at, np.rate = tonumber(m.position) or 0, os.time(), tonumber(m.rate) or 1
        np.len = tonumber(m.length) or 0
        lyrics_for(m)
        local art = type(m.art) == "string" and m.art or ""
        local path = coverart.path(art)
        if path then set_cover(path)
        elseif coverart.remote(art) then
            -- fetched once per picture; a slow answer for the last song is not shown on this one
            if np.art == art then
                if np.art_path then set_cover(np.art_path) end
            else
                np.art, np.art_path = art, nil
                local dest = COVERS .. "/remote-" .. P.hash(art) .. ".img"
                run("curl", { "-fsSL", "--max-time", "8", "-o", dest, art }, function(_, code)
                    if code == 0 and np.art == art then np.art_path = dest; set_cover(dest) end
                end)
            end
        else set_cover(nil) end
    end
    show_progress()
    show_lyric()
    if has then read_modes() end
    if was ~= playing then publish() end
end)
-- the song's clock between the service's readings, in quarter seconds
every(250, function()
    if not playing then return end
    np.t = np.t + 0.25 * np.rate
    show_progress()
    if np.data and np.data.synced then show_lyric() end
end)

-- ── The hands (calm until touched) ──
-- Pointed at: the hands come at once and stay 1.2 s after the pointer leaves.
local away_seq = {}
on("wg_hov", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, on_it = math.floor(v / 10), v % 10 == 1
    if k < 0 or k >= W.MAX then return end
    away_seq[k] = (away_seq[k] or 0) + 1
    if on_it then
        hovered[k] = true
        fact["hl" .. k] = 1
        unsettle()
    else
        hovered[k] = nil
        local mine = away_seq[k]
        after(1200, function() if away_seq[k] == mine then fact["hl" .. k] = 0; unsettle() end end)
    end
end)
on("wg_ctl", function(v)
    local c = math.floor(tonumber(v) or 0) % 10
    if c == 3 then run("playerctl", { "shuffle", "toggle" }, function() read_modes() end); return end
    if c == 4 then
        run("playerctl", { "loop", ({ [0] = "Playlist", "Track", "None" })[math.floor(fact.np_loop or 0)] or "None" }, function() read_modes() end)
        return
    end
    pcall(sys.call, ({ [0] = "media.previous", [1] = "media.toggle", [2] = "media.next" })[c] or "media.toggle")
end)
on("wg_seek", function(v)
    local f = (math.floor(tonumber(v) or 0) % 1000) / 999
    if np.len <= 0 then return end
    np.t = f * np.len
    run("playerctl", { "position", string.format("%.1f", np.t) })
    show_progress(); show_lyric()
end)
local volume = nil
pcall(sys.watch, "audio", function(a) if type(a) == "table" then volume = tonumber(a.volume) end end)
on("wg_vol", function(v)
    if not volume then return end
    for _, w in ipairs(doc.widgets) do
        if w.kind == "nowplaying" and W.find(doc, w.id) == math.floor((tonumber(v) or 0) / 10) + 1 then
            if (w.options or {}).scroll_volume == false then return end
        end
    end
    volume = math.max(0, math.min(1, volume + (math.floor(tonumber(v) or 0) % 10 == 1 and 0.05 or -0.05)))
    pcall(sys.call, "audio.volume", volume)
end)
on("wg_open", function() run("mooi", { "player" }) end)

-- ── Edit mode: carry, pull, choose, add (lib/widgets works it out; saved once per gesture) ──
fact.wg_snap = true
local function panel()
    local k = fact.wg_sel
    local w = doc.widgets[k + 1]
    if not w then fact.wg_sel = -1; return end
    if panel_at then fact.wg_px, fact.wg_py = panel_at[1], panel_at[2]
    else fact.wg_px, fact.wg_py = W.panel_spot(w, 320, ({ visualiser = 650, nowplaying = 466 })[w.kind] or 420, room) end
    local o = w.options or {}
    fact.wg_sl = W.LAYOUT_INDEX[w.layout] or 0
    fact.wg_sm = W.MODE_INDEX[w.mode] or 0
    fact.wg_si = W.IDLE_INDEX[w.idle] or 1
    fact.wg_o3, fact.wg_o4, fact.wg_o5, fact.wg_o6 = o.lyrics ~= false, o.progress ~= false, o.plate == true, o.scroll_volume ~= false
    fact.wg_o7, fact.wg_o8 = o.peaks ~= false, o.reflection == true
    fact.wg_og = tonumber(o.glow) or 0
    fact.wg_ob, fact.wg_ogap, fact.wg_osm = tonumber(o.bars) or 64, tonumber(o.gap) or 0.3, tonumber(o.smooth) or 0.5
    fact.wg_oa, fact.wg_ol = tonumber(o.angle) or 0, tonumber(o.lean) or 0
    fact.wg_otx, fact.wg_oop, fact.wg_olk = tonumber(o.text) or 1, w.opacity or 1, w.locked == true
    fact.wg_oad, fact.wg_obh = o.adapt ~= false, o.behind == true
    fact.wg_sk = W.KIND_NUM[w.kind] or 0
    fact.wg_oh24, fact.wg_osec = o.h24 ~= false, o.seconds ~= false
    text.wg_repo = o.repo or ""
    fact.wg_oviz, fact.wg_omin, fact.wg_opop, fact.wg_oevery = o.viz == true, tonumber(o.minutes) or 25, o.pop ~= false, tonumber(o.every) or 10
    text.wg_folder, text.wg_apps = o.folder or "", o.apps or ""
    text.wg_readout = string.format("%d × %d · %d, %d", w.w, w.h, w.x, w.y)
    local L = W.LAYOUTS[W.layout_of(w)]
    local maxw = L.max and L.max[1] or room.w
    fact.wg_osc = maxw > L.min[1] and math.max(0, math.min(1, (w.w - L.min[1]) / (maxw - L.min[1]))) or 0
end
-- the selection's count and the panel's widget (the last one chosen)
show_selection = function()
    local keep = {}
    for _, id in ipairs(selected) do if W.find(doc, id) then keep[#keep + 1] = id end end
    selected = keep
    fact.wg_nsel = #selected
    if #selected == 0 then fact.wg_sel = -1
    else fact.wg_sel = W.find(doc, selected[#selected]) - 1 end
    publish()
    if fact.wg_sel >= 0 then panel() end
end
local function commit(d)
    doc = d
    save()
    show_selection()
end
-- every change the editor makes goes through here, so it can be undone
local function change(d, note)
    if note and note ~= "" then text.wg_note = note; after(2500, function() if text.wg_note == note then text.wg_note = "" end end) end
    if W.same_doc(W.encode(d), W.encode(doc)) then return end
    W.push(hist, doc)
    commit(d)
end
local function skipped_note(n) return n > 0 and string.format("%d LOCKED, LEFT WHERE %s", n, n == 1 and "IT WAS" or "THEY WERE") or "" end
-- a group is chosen whole (D141)
local function choose(ids) selected = W.with_groups(doc, ids); show_selection() end

on("wg_edit", function(v)
    local on_it = math.floor(tonumber(v) or 0) == 1
    fact.editing = on_it
    if not on_it then selected = {}; drop_gestures(true); publish() end
    show_selection()
end)
-- slot · 10 + 0 choose only this · 1 add or take away (a right press) · 2 none
on("wg_sel", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, op = math.floor(v / 10), v % 10
    local w = doc.widgets[k + 1]
    if op == 2 or not w then choose({}); return end
    if op == 0 then
        if not is_sel(w.id) then choose({ w.id }) else choose(selected) end
    else
        local out, had = {}, false
        for _, id in ipairs(selected) do if id == w.id then had = true else out[#out + 1] = id end end
        if not had then out[#out + 1] = w.id end
        choose(out)
    end
end)
on("wg_pick", function(v) local w = doc.widgets[math.floor(tonumber(v) or -1) + 1]; if w then choose({ w.id }) end end)
-- the marquee: where it started, then where it ended (px, x · 4096 + y)
on("wg_marq0", function(v) v = math.floor(tonumber(v) or 0); marq0 = { math.floor(v / 4096), v % 4096 } end)
on("wg_marq1", function(v)
    if not marq0 then return end
    v = math.floor(tonumber(v) or 0)
    local x1, y1 = math.floor(v / 4096), v % 4096
    choose(W.ids_of(doc, W.marquee(doc, marq0[1], marq0[2], x1, y1)))
    marq0 = nil
end)
-- carrying: the one held snaps; the rest of the selection comes along by as much
on("wg_drag", function(v)
    local k, gx, gy = W.unpack(v)
    local w = doc.widgets[k + 1]
    if not w or w.locked then return end
    local x, y, ww, hh, g
    if fact.wg_snap then x, y, ww, hh, g = W.snap(doc, k + 1, gx * W.GRID, gy * W.GRID, w.w, w.h, room)
    else
        local r = W.clamp_rect({ x = gx * W.GRID, y = gy * W.GRID, w = w.w, h = w.h }, room)
        x, y, ww, hh, g = r.x, r.y, r.w, r.h, {}
    end
    pending = { k = k, x = x, y = y, w = ww, h = hh }
    fact.wg_dksel = is_sel(w.id)
    fact.wg_sx, fact.wg_sy, fact.wg_sw, fact.wg_sh = x, y, ww, hh
    fact.wg_gvx, fact.wg_ghy = g.vx or -1, g.hy or -1
    text.wg_readout = string.format("%d × %d · %d, %d", ww, hh, x, y)
end)
-- the scene keeps the carried offset until here: cleared once the widget is drawn where it settles
local function let_go()
    fact.wg_dk, fact.wg_dx, fact.wg_dy = -1, 0, 0
end
on("wg_drop", function(v)
    local k = math.floor(tonumber(v) or -1)
    local p = pending
    pending = nil
    fact.wg_gvx, fact.wg_ghy = -1, -1
    local w = doc.widgets[k + 1]
    if not p or p.k ~= k or not w then let_go(); return end
    local dx, dy = p.x - w.x, p.y - w.y
    local d = W.set_rect(doc, w.id, p.x, p.y, p.w, p.h, room)
    local others = {}
    if is_sel(w.id) then for _, id in ipairs(selected) do if id ~= w.id then others[#others + 1] = id end end end
    local sk = 0
    if #others > 0 then d, sk = W.nudge(d, others, dx, dy, room) end
    if not is_sel(w.id) then selected = { w.id } end
    change(d, skipped_note(sk))
    let_go()
end)
-- a handle held (slot · 8 + handle 0 … 7), pulled (dx + 2048) · 4096 + (dy + 2048), let go
on("wg_hgrab", function(v)
    v = math.floor(tonumber(v) or 0)
    local w = doc.widgets[math.floor(v / 8) + 1]
    if not w or w.locked then grab = nil; return end
    grab = { id = w.id, handle = v % 8, before = doc, x = w.x, y = w.y, w = w.w, h = w.h }
    if not is_sel(w.id) then selected = { w.id } end
    -- the scene draws it from these while it is pulled (nothing rebuilt under the pointer)
    fact.wg_sx, fact.wg_sy, fact.wg_sw, fact.wg_sh, fact.wg_ru = w.x, w.y, w.w, w.h, W.scale(w)
    fact.wg_rk = math.floor(v / 8)
end)
on("wg_hmove", function(v)
    if not grab then return end
    v = math.floor(tonumber(v) or 0)
    local dx, dy = math.floor(v / 4096) - 2048, v % 4096 - 2048
    local x, y, w, h = W.resize_from(grab.before, grab.id, grab.handle, dx, dy, room)
    if x == grab.x and y == grab.y and w == grab.w and h == grab.h then return end
    grab.x, grab.y, grab.w, grab.h = x, y, w, h
    local _, cur = W.find(grab.before, grab.id)
    fact.wg_sx, fact.wg_sy, fact.wg_sw, fact.wg_sh = x, y, w, h
    fact.wg_ru = W.scale({ kind = cur.kind, layout = cur.layout, w = w, h = h })
    text.wg_readout = string.format("%d × %d · %d, %d", w, h, x, y)
end)
on("wg_hdrop", function()
    if not grab then return end
    local g = grab
    grab = nil
    change(W.set_rect(g.before, g.id, g.x, g.y, g.w, g.h, room))
    -- drawn from the model again only once the model has it
    fact.wg_rk = -1
end)
-- 0 now playing · 1 visualiser · 2 clock · 3 notes · 4 GitHub
local KIND_WORDS = { visualiser = "THREE VISUALISERS", notes = "ONE NOTES", github = "TWO GITHUB WIDGETS", weather = "ONE WEATHER",
                     system = "ONE SYSTEM SCOPE", calendar = "ONE CALENDAR", timer = "ONE FOCUS TIMER", claude = "ONE CLAUDE",
                     photo = "ONE PHOTO", launch = "ONE LAUNCHER" }
on("wg_add", function(v)
    local kind = W.ADD_ORDER[math.floor(tonumber(v) or 0) + 1] or "nowplaying"
    local d, id = W.add(doc, kind, room)
    if not id then
        local full = #doc.widgets >= W.MAX
        change(doc, full and "TWELVE WIDGETS IS THE MOST" or ((KIND_WORDS[kind] or "THAT") .. " IS THE MOST"))
        return
    end
    selected = { id }
    change(d)
end)
local function remove_selected()
    local d, locked = doc, 0
    for _, id in ipairs(selected) do
        local _, w = W.find(d, id)
        if w and w.locked then locked = locked + 1
        elseif w then d = W.remove(d, id) end
    end
    change(d, locked > 0 and (locked == 1 and "LOCKED — UNLOCK IT TO REMOVE" or locked .. " LOCKED — UNLOCK THEM TO REMOVE") or nil)
end
local function duplicate_selected()
    local d, made = doc, {}
    for _, id in ipairs(selected) do
        local id2
        d, id2 = W.duplicate(d, id, room)
        if id2 then made[#made + 1] = id2 end
    end
    if #made > 0 then selected = made end
    change(d)
end
local function toggle_lock()
    local any_unlocked = false
    for _, id in ipairs(selected) do local _, w = W.find(doc, id); if w and not w.locked then any_unlocked = true end end
    local d = doc
    for _, id in ipairs(selected) do d = W.set_field(d, id, "locked", any_unlocked) end
    change(d)
end
local function undo_redo(back)
    local d = back and W.undo(hist, doc) or W.redo(hist, doc)
    if d then commit(d) end
end
-- the keys while editing: 1-4 ← → ↑ ↓ by 8 px · 5-8 by 1 px · 9 delete · 10 duplicate · 11 undo ·
-- 12 redo · 13 select all · 14 lock · 15 forward · 16 backward
-- A held key repeats (every 20 ms after 300): Delete, Ctrl+D, undo and redo act once per press; only
-- the arrows repeat (D139 audit: a long Ctrl+D made several copies, a long Delete took several).
local held, held_n = {}, {}
on("wg_key", function(v)
    local c = math.floor(tonumber(v) or 0)
    if c >= 9 then
        -- still held while its repeats keep coming (every 20 ms); let go once they stop for 150 ms
        held_n[c] = (held_n[c] or 0) + 1
        local mine = held_n[c]
        after(150, function() if held_n[c] == mine then held[c] = nil end end)
        if held[c] then return end
        held[c] = true
    end
    if c >= 1 and c <= 8 then
        local step = c <= 4 and W.GRID or 1
        local dir = (c - 1) % 4
        local dx = ({ [0] = -step, step, 0, 0 })[dir]
        local dy = ({ [0] = 0, 0, -step, step })[dir]
        local d, sk = W.nudge(doc, selected, dx, dy, room)
        change(d, skipped_note(sk))
    elseif c == 9 then remove_selected()
    elseif c == 10 then duplicate_selected()
    elseif c == 11 then undo_redo(true)
    elseif c == 12 then undo_redo(false)
    elseif c == 13 then
        local all = {}
        for _, w in ipairs(doc.widgets) do all[#all + 1] = w.id end
        choose(all)
    elseif c == 14 then toggle_lock()
    elseif c == 15 then change(W.raise(doc, selected, "forward"))
    elseif c == 16 then change(W.raise(doc, selected, "backward")) end
end)
-- the toolbar: 1-6 align left / centre / right / top / middle / bottom · 7-8 distribute · 9-10 match
-- width / height · 11 to the front · 12 to the back · 13 lock · 14 snapping on or off
local ALIGN = { "left", "centre", "right", "top", "middle", "bottom" }
on("wg_tool", function(v)
    local c = math.floor(tonumber(v) or 0)
    local d, sk = doc, 0
    if c >= 1 and c <= 6 then d, sk = W.align(doc, selected, ALIGN[c], room)
    elseif c == 7 or c == 8 then d, sk = W.distribute(doc, selected, c == 7 and "h" or "v", room)
    elseif c == 9 or c == 10 then d, sk = W.match(doc, selected, c == 9 and "w" or "h", room)
    elseif c == 11 then d = W.raise(doc, selected, "front")
    elseif c == 12 then d = W.raise(doc, selected, "back")
    elseif c == 13 then toggle_lock(); return
    elseif c == 14 then fact.wg_snap = not fact.wg_snap; return
    -- D141: groups, the look of them all, shadows, the ambient rest, desk mode
    elseif c == 15 then
        if #selected < 2 then change(doc, "CHOOSE TWO OR MORE TO GROUP"); return end
        d = W.group(doc, selected)
    elseif c == 16 then d = W.ungroup(doc, selected)
    elseif c >= 20 and c <= 24 then d = W.set_look(doc, "style", W.STYLES[c - 19])
    elseif c == 25 then d = W.set_look(doc, "shadows", not doc.shadows)
    elseif c == 26 then d = W.set_look(doc, "ambient", doc.ambient == false)
    elseif c == 27 then emit("wg_deskm", 2); return end
    change(d, skipped_note(sk))
end)
-- the panel: slot · 1000 + what · 100 + value (what: 1 layout or mode · 2 at rest · 3-6 lyric line,
-- progress, plate, wheel volume · 7 peaks · 8 reflection · 9 duplicate (1) / remove (2) / lock (3) /
-- calm spot (4) / adapt on, off (5, 6) / behind on, off (7, 8) / square (23, a visualiser's angle back to 0))
on("wg_opt", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, what, val = math.floor(v / 1000), math.floor((v % 1000) / 100), v % 100
    local w = doc.widgets[k + 1]
    if not w then return end
    local d = doc
    if what == 1 then
        if w.kind == "visualiser" then d = W.set_mode(doc, w.id, W.MODES[val + 1])
        else d = W.set_layout(doc, w.id, (W.KIND_LAYOUTS[w.kind] or {})[val + 1], room) end
    elseif what == 2 then d = W.set_idle(doc, w.id, W.IDLES[val + 1])
    elseif what >= 3 and what <= 8 then
        d = W.set_option(doc, w.id, ({ [3] = "lyrics", [4] = "progress", [5] = "plate", [6] = "scroll_volume", [7] = "peaks", [8] = "reflection" })[what], val == 1)
    elseif what == 9 and val == 1 then selected = { w.id }; duplicate_selected(); return
    elseif what == 9 and val == 2 then selected = { w.id }; remove_selected(); return
    elseif what == 9 and val == 3 then selected = { w.id }; toggle_lock(); return
    elseif what == 9 and val == 4 then
        -- the nearest calm, free place of its size (it moves only because it was asked to)
        if not wall then change(doc, "THE WALLPAPER IS NOT READ YET"); return end
        local x, y = WM.calm_spot(wall, doc, k + 1, room)
        if not x then change(doc, "NO CALM SPOT IS FREE FOR ITS SIZE"); return end
        d = W.set_rect(doc, w.id, x, y, w.w, w.h, room)
    elseif what == 9 and val >= 13 and val <= 15 then d = W.set_option(doc, w.id, "minutes", ({ 15, 25, 50 })[val - 12])
    elseif what == 9 and (val == 16 or val == 17) then d = W.set_option(doc, w.id, "pop", val == 16)
    elseif what == 9 and val == 18 then
        local nxt = ({ [5] = 10, [10] = 30, [30] = 5 })[tonumber((w.options or {}).every) or 10] or 10
        d = W.set_option(doc, w.id, "every", nxt)
    elseif what == 9 and (val == 21 or val == 22) then d = W.set_option(doc, w.id, "viz", val == 21)
    elseif what == 9 and val == 23 then d = W.set_option(W.set_option(doc, w.id, "lean", 0), w.id, "angle", 0)
    elseif what == 9 and (val == 9 or val == 10) then d = W.set_option(doc, w.id, "h24", val == 9)
    elseif what == 9 and (val == 11 or val == 12) then d = W.set_option(doc, w.id, "seconds", val == 11)
    elseif what == 9 and (val == 5 or val == 6) then d = W.set_option(doc, w.id, "adapt", val == 5)
    elseif what == 9 and (val == 7 or val == 8) then
        d = W.set_option(doc, w.id, "behind", val == 7)
        if val == 7 and not (wall and wall.depth and widgets_cfg().depth) then
            change(d, wall and wall.depth and "DEPTH IS OFF IN SETTINGS" or "THIS WALLPAPER HAS NO CUT-OUT (NEEDS REMBG, A STILL PICTURE)")
            return
        end
    end
    change(d)
end)
-- a slider (slot · 10000 + which · 1000 + value 0 … 999), live while held; `done` saves it
-- which: 1 opacity · 2 bars · 3 glow · 4 gap · 5 smoothing · 6 text size · 7 scale · 8 angle · 9 lean
local function slider_doc(base, w, which, f)
    if which == 1 then return W.set_field(base, w.id, "opacity", 0.3 + 0.7 * f)
    elseif which == 2 then return W.set_option(base, w.id, "bars", 16 + f * 112)
    elseif which == 3 then return W.set_option(base, w.id, "glow", f)
    elseif which == 4 then return W.set_option(base, w.id, "gap", f * 0.6)
    elseif which == 5 then return W.set_option(base, w.id, "smooth", f)
    elseif which == 6 then return W.set_option(base, w.id, "text", 0.8 + f * 0.6)
    elseif which == 8 then return W.set_option(base, w.id, "angle", -180 + f * 360)
    elseif which == 9 then return W.set_option(base, w.id, "lean", -40 + f * 80)
    elseif which == 7 then
        -- scale round the centre, from the layout's least to its most
        local L = W.LAYOUTS[W.layout_of(w)]
        local maxw = L.max and L.max[1] or room.w
        local nw = L.min[1] + (maxw - L.min[1]) * f
        local nh = w.h * nw / w.w
        local cw, ch = W.clamp_size(w, nw, nh)
        return W.set_rect(base, w.id, w.x + (w.w - cw) / 2, w.y + (w.h - ch) / 2, cw, ch, room)
    end
    return base
end
on("wg_slide", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, which, val = math.floor(v / 10000), math.floor((v % 10000) / 1000), v % 1000
    local w = (slide and slide.before or doc).widgets[k + 1]
    if not w then return end
    if not slide then slide = { before = doc } end
    doc = slider_doc(slide.before, w, which, val / 999)
    publish()
    panel()
end)
on("wg_slid", function()
    if not slide then return end
    local now = doc
    doc = slide.before
    slide = nil
    change(now)
end)
-- a visualiser's grip in the editor (the dot above it): slot · 1000 + angle + 180, live while it
-- is pulled; `wg_rotd` keeps the turn. The panel's ANGLE slider reaches the same option.
local turn = nil
on("wg_rot", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, a = math.floor(v / 1000), v % 1000 - 180
    local w = (turn and turn.before or doc).widgets[k + 1]
    if not w or w.kind ~= "visualiser" then return end
    if not turn then turn = { before = doc } end
    doc = W.set_option(turn.before, w.id, "angle", a)
    publish()
    panel()
end)
on("wg_rotd", function()
    if not turn then return end
    local now = doc
    doc = turn.before
    turn = nil
    change(now)
end)
-- the GitHub widget's repository, typed in its panel (owner/name)
local repo_draft = ""
on("text:wg_repo", function(v) repo_draft = type(v) == "string" and v or "" end)
on("submit:wg_repo", function()
    local w = doc.widgets[(fact.wg_sel or -1) + 1]
    if not w or w.kind ~= "github" then return end
    local r = repo_draft:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^https?://github.com/", ""):gsub("%.git$", "")
    if not GP.repo_ok(r) then change(doc, "A REPOSITORY IS OWNER/NAME"); return end
    change(W.set_option(doc, w.id, "repo", r))
end)
-- the photo's folder and the launcher's apps, typed in the panel
local folder_draft, apps_draft = "", ""
on("text:wg_folder", function(v) folder_draft = type(v) == "string" and v or "" end)
on("text:wg_apps", function(v) apps_draft = type(v) == "string" and v or "" end)
local function typed_option(kind, key, draft, why)
    local w = doc.widgets[(fact.wg_sel or -1) + 1]
    if not w or w.kind ~= kind then return end
    local v = draft:gsub("^%s+", ""):gsub("%s+$", "")
    if not W.option_string(key, v) then change(doc, why); return end
    change(W.set_option(doc, w.id, key, v))
end
on("submit:wg_folder", function() typed_option("photo", "folder", folder_draft, "A FOLDER, LIKE ~/Pictures") end)
on("submit:wg_apps", function() typed_option("launch", "apps", apps_draft, "APPS, COMMA-SEPARATED") end)
-- the panel's place, when its header is dragged (x · 4096 + y)
on("wg_pmove", function(v)
    v = math.floor(tonumber(v) or 0)
    panel_at = { math.max(0, math.min(room.w - 320, math.floor(v / 4096))), math.max(0, math.min(room.h - 60, v % 4096)) }
    fact.wg_px, fact.wg_py = panel_at[1], panel_at[2]
end)

-- ── The clocks (D140): the time once a second while there is a clock; the Info clock's strip ──
local zone_off = 0   -- seconds east of UTC, as `date +%z` says (the board's due days are local)
local strip_at = -60   -- when the Info strip was last read; a new clock reads it on its first second
local function info_strip()
    if not fact.any_clock then return end
    strip_at = os.time()
    local cached = read("nexus-weather.json", "json")
    local wx = forecast.parse(type(cached) == "table" and cached.answer or nil)
    if wx then
        text.ck_wx = string.format("%d°", math.floor(wx.now.temp + 0.5))
        text.ck_wxhl = wx.today.hi and string.format("%d° / %d°", math.floor(wx.today.hi + 0.5), math.floor(wx.today.lo + 0.5)) or ""
        fact.ck_wcode = wx.now.code
        fact.ck_wkind = DD.icon_kind(wx.now.code, wx.now.day)
        text.ck_wword = DD.ICON_WORD[fact.ck_wkind] or ""
        fact.ck_wx_on = true
    else fact.ck_wx_on = false end
    local board = read("board.json", "json")
    local today = math.floor((os.time() + zone_off) / 86400)   -- the board's day numbers (lib/board.today)
    local nd = CF.next_due(board, today)
    text.ck_due = nd and (nd.label .. " · " .. NOTES.one_line(nd.title, 48)) or "NOTHING DUE ON THE BOARD"
end
run("date", { "+%z" }, function(out, code)
    local sign, h, m = string.match(tostring(out or ""), "([+-])(%d%d)(%d%d)")
    if code == 0 and sign then
        zone_off = (tonumber(h) * 3600 + tonumber(m) * 60) * (sign == "-" and -1 or 1)
        info_strip()
    end
end)
local show_timer_tick   -- the focus timer's second (defined with the D141 feeders)
local function tick()
    if not fact.any_clock then return end
    if show_timer_tick then show_timer_tick() end
    if os.time() - strip_at >= 60 then info_strip() end
    local t = os.date("*t")
    fact.ck_h, fact.ck_m, fact.ck_s = t.hour, t.min, t.sec
    text.ck_words = CF.words(t.hour, t.min)
    -- (Pleamar's os.date knows the plain specifiers only: no %-d, no %V)
    local wd = calendar.weekday(t.year, t.month, t.day)
    text.ck_date = string.upper(DAYNAMES[wd + 1] .. " " .. t.day .. " " .. calendar.MONTHS[t.month])
    text.ck_week = "WEEK " .. calendar.iso_week(t.year, t.month, t.day)
    text.ck_ampm = CF.ampm(t.hour)
    text.ck_hm24, text.ck_hm12 = CF.hhmm(t.hour, t.min, true), CF.hhmm(t.hour, t.min, false)
end
every(1000, tick)
pcall(sys.watch, "battery", function(b)
    if type(b) ~= "table" then return end
    fact.ck_bat = math.floor((tonumber(b.percent) or 0) + 0.5)
    fact.ck_chg = b.charging == true
    fact.ck_bat_on = b.present == true
end)

-- ── Notes (D140): mooi's quick notes (notes.json, lib/notes), edited where they are ──
local notes = {}
local editing_note = nil   -- the id being changed, or -1 for a new one
local function show_notes()
    notes = NOTES.decode(read("notes.json", "json"))
    local rows = {}
    for i, n in ipairs(notes) do
        if i > 20 then break end
        rows[i] = { id = n.id, text = NOTES.one_line(n.text, 120), pinned = n.pinned == true, done = n.done == true, ago = NOTES.ago(os.time(), n.time) }
    end
    model.nt = rows
    fact.nt_count = #notes
end
local function save_notes() pcall(sys.call, "files.write", "notes.json", NOTES.encode(notes)) end
show_notes()
pcall(sys.watch, "files:notes.json", function() if editing_note == nil then show_notes() end end)
local draft = ""
on("text:nt_draft", function(v) draft = type(v) == "string" and v or "" end)
on("nt_edit", function(v)
    local id = math.floor(tonumber(v) or -1)
    editing_note = id
    local n = id >= 0 and NOTES.find(notes, id) or nil
    draft = n and n.text or ""
    text.nt_draft = draft
    fact.nt_ed = id
    emit("nt_focus")
end)
local function end_edit() editing_note = nil; fact.nt_ed = -2; text.nt_draft = ""; draft = ""; show_notes() end
on("submit:nt_draft", function()
    local t = NOTES.clean(draft)
    notes = NOTES.decode(read("notes.json", "json"))   -- what the side panel may have changed meanwhile
    if t ~= "" then
        if editing_note and editing_note >= 0 and NOTES.find(notes, editing_note) then notes = NOTES.update(notes, editing_note, t, os.time())
        else notes = NOTES.add(notes, t, os.time()) end
        save_notes()
    end
    end_edit()
end)
on("nt_cancel", end_edit)
local function note_op(fn) return function(v)
    notes = NOTES.decode(read("notes.json", "json"))
    notes = fn(notes, math.floor(tonumber(v) or -1))
    save_notes(); show_notes()
end end
on("nt_pin", note_op(function(l, id) return (NOTES.pin(l, id)) end))
on("nt_done", note_op(function(l, id) return (NOTES.done(l, id)) end))
on("nt_del", note_op(function(l, id) return (NOTES.remove(l, id)) end))

-- ── GitHub (D140): through `gh`, signed in as you; each repository read every 5 minutes (every
-- minute while a run is going), kept in gh-<owner>-<repo>.json ──
local gh = {}   -- repo -> { card, runs, act, at, err, asking }
local Q = [[query($o:String!,$n:String!){ repository(owner:$o,name:$n){ nameWithOwner description stargazerCount forkCount pushedAt url
  primaryLanguage{name} issues(states:OPEN){totalCount} pullRequests(states:OPEN){totalCount}
  defaultBranchRef{ name target{ ... on Commit { history(first:8){ nodes{ messageHeadline committedDate abbreviatedOid url author{ name user{login} } statusCheckRollup{state} } } } } } } }]]
local HEATQ = [[query($o:String!){ user(login:$o){ contributionsCollection{ contributionCalendar{ totalContributions weeks{ contributionDays{ weekday contributionLevel } } } } } }]]
local function bmo_say_ci(words) run("pleamar", { "--say", "bmo", wire.say(words), "emit speak" }) end
local function cache_name(repo) return "gh-" .. repo:gsub("/", "-") .. ".json" end
local STATE = { ok = 1, fail = 2, run = 3, other = 0, SUCCESS = 1, FAILURE = 2, ERROR = 2, PENDING = 3, EXPECTED = 3 }
show_github = function()
    local now = os.time()
    for j = 1, 2 do
        local repo = gh_lanes[j]
        local f = "g" .. j .. "_"
        local e = repo and gh[repo]
        if not e then
            local c = repo and read(cache_name(repo), "json")
            if type(c) == "table" then gh[repo] = { card = c.card, runs = c.runs or {}, act = c.act, heat = c.heat, at = tonumber(c.at) or 0 }; e = gh[repo] end
        end
        if repo then
            local card = e and e.card
            text[f .. "name"] = card and card.name or repo
            text[f .. "desc"] = card and (card.desc ~= "" and card.desc or "NO DESCRIPTION") or ""
            text[f .. "stats"] = card and string.format("★ %d   ⑂ %d   %d ISSUES   %d PRS", card.stars, card.forks, card.issues, card.prs) or ""
            text[f .. "meta"] = card and string.format("%s · %s · PUSHED %s AGO", string.upper(card.lang ~= "" and card.lang or "—"), string.upper(card.branch), GP.ago(card.pushed, now)) or ""
            text[f .. "state"] = (e and e.err) or (card and "" or "ASKING GITHUB…")
            local cs = {}
            for i, c in ipairs(card and card.commits or {}) do
                cs[i] = { msg = c.msg, who = string.upper(c.who), when = GP.ago(c.when, now), sha = c.sha, st = STATE[c.state] or 0 }
            end
            model["g" .. j .. "c"] = cs
            local rs = {}
            for i, r in ipairs(e and e.runs or {}) do
                if i > 6 then break end
                rs[i] = { name = string.upper(r.name), branch = r.branch, when = GP.ago(r.when, now), st = STATE[r.state] or 0 }
            end
            model["g" .. j .. "r"] = rs
            local as, top, total = {}, 1, 0
            for _, v in ipairs(e and e.act or {}) do top = math.max(top, v); total = total + v end
            for i, v in ipairs(e and e.act or {}) do as[i] = { v = v / top } end
            model["g" .. j .. "a"] = as
            text[f .. "total"] = e and e.act and string.format("%d COMMITS IN 12 WEEKS", total) or "COUNTING…"
            -- the activity map (D141): the owner's year
            model["g" .. j .. "h"] = e and e.heat and e.heat.cells or {}
            text[f .. "heat"] = e and e.heat and string.format("%d CONTRIBUTIONS BY %s IN THE LAST YEAR", e.heat.total, string.upper(repo:match("^[^/]+") or ""))
                or "READING THE ACTIVITY…"
        end
    end
end
local function gh_read(repo)
    local e = gh[repo] or { runs = {} }
    gh[repo] = e
    if e.asking then return end
    e.asking = true
    local owner, name = repo:match("^(.-)/(.+)$")
    local pending = 4
    local function done()
        pending = pending - 1
        if pending > 0 then return end
        e.asking, e.at = false, os.time()
        pcall(sys.call, "files.write", cache_name(repo), { card = e.card, runs = e.runs, act = e.act, heat = e.heat, at = e.at })
        show_github()
    end
    run("gh", { "api", "graphql", "-f", "query=" .. Q, "-F", "o=" .. owner, "-F", "n=" .. name }, function(out, code)
        local ok, d = pcall(json.decode, out or "")
        local card = ok and GP.card(d, json.null) or nil
        if card then e.card, e.err = card, nil
        else e.err = code == 127 and "INSTALL THE GITHUB CLI (gh) AND RUN `gh auth login`" or "GITHUB DID NOT ANSWER FOR " .. string.upper(repo) end
        done()
    end)
    run("gh", { "api", "repos/" .. repo .. "/actions/runs?per_page=6" }, function(out)
        local ok, d = pcall(json.decode, out or "")
        if ok then
            local runs = GP.runs(d, json.null)
            -- a run that has just failed (not one that was failing already): BMO says so (D141)
            local newest = runs[1]
            if newest and newest.state == "fail" and e.runs and #e.runs > 0 and e.told ~= newest.url
               and not (e.runs[1] and e.runs[1].url == newest.url and e.runs[1].state == "fail") then
                e.told = newest.url
                bmo_say_ci(string.format("Uh oh! %s failed on %s.", newest.name, repo))
            end
            e.runs = runs
        end
        done()
    end)
    -- the owner's contributions (a person: theirs; an organisation answers nothing, and it stays empty)
    run("gh", { "api", "graphql", "-f", "query=" .. HEATQ, "-F", "o=" .. owner }, function(out)
        local ok, d = pcall(json.decode, out or "")
        local h = ok and GP.heat(d, 52, json.null) or nil
        if h then e.heat = h end
        done()
    end)
    run("gh", { "api", "repos/" .. repo .. "/stats/commit_activity" }, function(out)
        local ok, d = pcall(json.decode, out or "")
        local a = ok and GP.activity(d) or nil
        if a then e.act = a end          -- while GitHub is still counting (202, {}), the last answer stays
        done()
    end)
end
every(15000, function()
    local now = os.time()
    for j = 1, 2 do
        local repo = gh_lanes[j]
        if repo then
            local e = gh[repo]
            local running = false
            for _, r in ipairs(e and e.runs or {}) do if r.state == "run" then running = true end end
            if not e or not e.at or now - e.at > (running and 60 or 300) then gh_read(repo) end
        end
    end
end)
after(2000, function() for j = 1, 2 do if gh_lanes[j] then gh_read(gh_lanes[j]) end end end)
-- lane · 100 + 0 the repository, 1-8 a commit, 11-16 a run
on("gh_open", function(v)
    v = math.floor(tonumber(v) or 0)
    local j, i = math.floor(v / 100), v % 100
    local repo = gh_lanes[j]
    local e = repo and gh[repo]
    if not e or not e.card then return end
    local url = i == 0 and e.card.url or (i <= 8 and e.card.commits[i] and e.card.commits[i].url) or (i >= 11 and e.runs[i - 10] and e.runs[i - 10].url)
    if url and url ~= "" then run("xdg-open", { url }) end
end)

-- ── D141: the feeders of the weather, system, calendar, focus timer, Claude, photo and launcher ──
local function has(kind) return doc ~= nil and W.count_kind(doc, kind) > 0 end
local function first(kind)
    for _, w in ipairs(doc and doc.widgets or {}) do if w.kind == kind then return w, w.options or {} end end
    return nil, {}
end
local function rnd(v) return math.floor((tonumber(v) or 0) + 0.5) end
local function bmo_say(words) run("pleamar", { "--say", "bmo", wire.say(words), "emit speak" }) end

-- the shadows fall away from the wallpaper's light
wall_light = function()
    local dx, dy = DD.light(wall, room.w / 2, room.h / 2, room)
    fact.wg_lx, fact.wg_ly = dx, dy
end

-- weather: the Nexus and the notch keep nexus-weather.json fresh; this only reads it
local function show_weather()
    if not has("weather") then return end
    local c = read("nexus-weather.json", "json")
    local ans = type(c) == "table" and c.answer or nil
    local f = forecast.parse(ans)
    if not f then fact.wx_on = false; return end
    fact.wx_on = true
    fact.wx_kind = DD.icon_kind(f.now.code, f.now.day)
    text.wx_now = string.format("%d°", rnd(f.now.temp))
    text.wx_word = string.format("%s · FEELS %d°", DD.ICON_WORD[fact.wx_kind] or "", rnd(f.now.feels))
    text.wx_hl = f.today.hi and string.format("%d° / %d°", rnd(f.today.hi), rnd(f.today.lo)) or ""
    text.wx_more = string.format("%sWIND %d KM/H · %d%%", c.city and (string.upper(c.city) .. " · ") or "", rnd(f.now.wind), rnd(f.now.humidity))
    local rows = {}
    for i, o in ipairs(DD.horizon(ans, 24) or {}) do rows[i] = { r = o.r, g = o.g, b = o.b, t = o.t, wet = o.wet, lab = o.label, kind = o.kind } end
    model.wxh = rows
    model.wxd = DD.week(f.days)
end
pcall(sys.watch, "files:nexus-weather.json", function() show_weather(); strip_at = -60 end)
every(600000, show_weather)

-- system: a sample every two seconds while it is on the desktop, the last 48 kept
local samples = { c = {}, m = {}, t = {} }
local sys_prev = nil
local function rows_of(list) local r = {}; for i, v in ipairs(list) do r[i] = { v = v } end; return r end
every(2000, function()
    if not has("system") or fact.wg_amb then return end
    run("cat", { "/proc/stat" }, function(out)
        local v; v, sys_prev = sysinfo.cpu(out, sys_prev)
        if not v then return end
        fact.sp_c = v; text.sp_ctx = string.format("%d%%", rnd(v * 100))
        model.spc = rows_of(DD.push(samples.c, v, 48))
    end)
    run("cat", { "/proc/meminfo" }, function(out)
        local f, used = sysinfo.mem(out)
        if not f then return end
        fact.sp_m = f; text.sp_mtx = string.format("%.1fG", used)
        model.spm = rows_of(DD.push(samples.m, f, 48))
    end)
    run("sensors", { "-j" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        local c = ok and sysinfo.temp(t) or nil
        if not c then text.sp_ttx = "—"; return end
        fact.sp_t = math.min(1, c / 100); text.sp_ttx = string.format("%d°", rnd(c))
        model.spt = rows_of(DD.push(samples.t, math.min(1, c / 100), 48))
    end)
end)

-- calendar: this month (‹ › move it), the board's cards due lit
local cal_shift = 0
local function show_cal()
    if not has("calendar") then return end
    local t = os.date("*t")
    local y, m = calendar.shift(t.year, t.month, cal_shift)
    local today = math.floor((os.time() + zone_off) / 86400)
    model.cal = DD.month_grid(y, m, today, read("board.json", "json"))
    text.cal_title = string.upper(calendar.MONTHS[m] .. " " .. y)
end
pcall(sys.watch, "files:board.json", function() show_cal(); strip_at = -60 end)
on("cal_nav", function(v) cal_shift = cal_shift + math.floor(tonumber(v) or 1) - 1; show_cal() end)
-- a day pressed: the board, filtered to what is due then (started first if it is not running)
on("cal_day", function(v)
    local day = math.floor(tonumber(v) or 0)
    run("pleamar", { "--say", "mooi-board", "emit kb_day " .. day }, function(_, code)
        if code == 0 then return end
        run("mooi", { "board" })
        after(1800, function() run("pleamar", { "--say", "mooi-board", "emit kb_day " .. day }) end)
    end)
end)

-- the focus timer: focus, then a five-minute break; BMO says when each ends
local timer = nil
local function timer_len() local _, o = first("timer"); return tonumber(o.minutes) or 25 end
local function show_timer()
    if not timer then timer = DD.timer(timer_len()) end
    local now = os.time()
    local left = DD.timer_left(timer, now)
    if timer.ends and left <= 0 then
        local was_break = timer.brk
        fact.tm_flash = true
        after(15000, function() fact.tm_flash = false end)
        bmo_say(was_break and "Break's over! Back to it, you've got this." or "Focus done! Time for a little break.")
        timer = DD.timer(was_break and timer_len() or 5, not was_break)
        text.tm_word = was_break and "BREAK OVER" or "DONE · TAKE A BREAK"
        left = DD.timer_left(timer, now)
    elseif not fact.tm_flash then
        text.tm_word = timer.ends and (timer.brk and "BREAK" or "FOCUS")
            or (left < timer.total and "PAUSED" or (timer.brk and "BREAK · READY" or "READY"))
    end
    fact.tm_left, fact.tm_total = left, timer.total
    fact.tm_run, fact.tm_brk = timer.ends ~= nil, timer.brk
    text.tm_txt = DD.mmss(left)
end
show_timer_tick = function() if has("timer") then show_timer() end end
on("tm_go", function(v)
    v = math.floor(tonumber(v) or 0)
    local now = os.time()
    if not timer then timer = DD.timer(timer_len()) end
    fact.tm_flash = false
    if v == 0 then DD.timer_toggle(timer, now)
    elseif v == 1 then timer = DD.timer(timer_len())
    elseif v == 2 then DD.timer_add(timer, 300, now)
    elseif v == 5 then DD.timer_add(timer, 60, now)
    elseif v == 6 then DD.timer_add(timer, -60, now) end
    show_timer()
end)

-- Claude: the last thing said in the notch, and whether Claude Code is at work (its processes' CPU)
local function show_claude()
    if not has("claude") then return end
    local c = DD.claude_last(read("notch-claude.json", "json"))
    text.cl_line = c and c.text or "Nothing said yet: ask in the notch."
    text.cl_who = c and c.who or "CLAUDE"
end
pcall(sys.watch, "files:notch-claude.json", show_claude)
every(4000, function()
    if not has("claude") then return end
    run("ps", { "-C", "claude", "-o", "%cpu=" }, function(out)
        local n, cpu = 0, 0
        for l in tostring(out or ""):gmatch("[^\n]+") do
            local v = tonumber(l:match("[%d%.]+"))
            if v then n = n + 1; cpu = cpu + v end
        end
        fact.cl_busy = cpu > 6
        text.cl_state = n == 0 and "NOT RUNNING" or string.format("%d SESSION%s · %s", n, n == 1 and "" or "S", cpu > 6 and "WORKING" or "IDLE")
    end)
end)
on("cl_open", function() run("mooi", { "notch", "claude" }) end)

-- the photo: a picture from its folder every few minutes, framed, its subject cut out to step out
local PHOTO_DIR = HOME .. "/.cache/mooi/photo"
local photo = { list = {}, i = 0, folder = nil, at = 0, key = nil }
local function photo_folder(o)
    local f = tostring(o.folder or "~/Pictures")
    return (f:gsub("^~", HOME))
end
local function photo_show()
    local w, o = first("photo")
    if not w or #photo.list == 0 then
        fact.pf_on = false
        text.pf_state = w and ("NO PICTURES IN " .. string.upper(tostring(o.folder or "~/Pictures"))) or ""
        return
    end
    photo.i = photo.i % #photo.list + 1
    photo.at = os.time()
    local src = photo.list[photo.i]
    local key = P.hash(src)
    photo.key = key
    text.pf_name = string.upper((src:match("([^/]+)$") or ""):gsub("%.[^.]+$", ""):gsub("[_%-]+", " "))
    run("mooi", { "photo-prep", src, PHOTO_DIR, key }, function(out)
        if photo.key ~= key then return end
        out = tostring(out or "")
        if out:match("pictures") then
            text.pf_path, text.pf_sqp = PHOTO_DIR .. "/" .. key .. "-43.jpg", PHOTO_DIR .. "/" .. key .. "-11.jpg"
            fact.pf_on = true
        else fact.pf_on = false; text.pf_state = "THAT PICTURE WOULD NOT OPEN" end
        if out:match("cut") then
            text.pf_cutp, text.pf_cutsqp = PHOTO_DIR .. "/" .. key .. "-43.png", PHOTO_DIR .. "/" .. key .. "-11.png"
            fact.pf_cut_on = true
        else fact.pf_cut_on = false end
    end)
end
local function photo_list()
    local _, o = first("photo")
    local dir = photo_folder(o)
    photo.folder = dir
    run("find", { dir, "-maxdepth", "2", "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")" }, function(out)
        local list = {}
        for l in tostring(out or ""):gmatch("[^\n]+") do list[#list + 1] = l end
        table.sort(list, function(a, b) return P.hash(a) < P.hash(b) end)   -- a shuffled order, the same each time
        photo.list, photo.i = list, (os.time() // 60) % math.max(1, #list)
        photo_show()
    end)
end
on("pf_next", photo_show)
every(30000, function()
    local w, o = first("photo")
    if not w then return end
    if photo_folder(o) ~= photo.folder then photo_list(); return end
    if os.time() - photo.at >= (tonumber(o.every) or 10) * 60 then photo_show() end
end)

-- the launcher: the apps asked for, which are open, which have notifications waiting (since last opened)
local apps_now, wins_now, unseen_now, launch_rows, opened_at = {}, {}, {}, {}, {}
local function show_launch()
    local w, o = first("launch")
    if not w then return end
    local waiting = {}
    for _, n in ipairs(unseen_now) do
        local a = string.lower(tostring(n.app or ""))
        if (tonumber(n.time) or 0) > (opened_at[a] or 0) then waiting[#waiting + 1] = n end
    end
    launch_rows = DD.launch_rows(o.apps or W.OPTIONS.launch.apps, apps_now, wins_now, waiting, apps_lib.app_for)
    model.ln = launch_rows
end
-- (a service hands over its list itself, or a record with it as `list`)
local function list_of(a) return type(a) == "table" and (type(a.list) == "table" and a.list or (a[1] ~= nil and a) or {}) or {} end
pcall(sys.watch, "apps", function(a) apps_now = list_of(a); show_launch() end)
pcall(sys.watch, "window", function(a) wins_now = list_of(a); show_launch() end)
pcall(sys.watch, "notification_history", function(a) unseen_now = list_of(a); show_launch() end)
on("ln_go", function(v)
    local r = launch_rows[math.floor(tonumber(v) or -1) + 1]
    if not r then return end
    opened_at[string.lower(r.name)] = os.time()
    pcall(sys.call, "apps.launch", r.exec)
    show_launch()
end)

-- desk mode: every widget gathered in the middle over the blurred desktop, then back
on("wg_deskm", function(v)
    v = math.floor(tonumber(v) or 0)
    local want = v == 1 or (v == 2 and not fact.wg_desk)
    if want then
        if fact.editing or standing_down then return end
        desk_at = W.desk_layout(doc, room)
        fact.wg_desk = true
        publish()
    else
        fact.wg_desk = false
        -- the offsets stay while they glide home
        after(700, function() if not fact.wg_desk then desk_at = nil; publish() end end)
    end
end)

-- told when the widgets change: start what a new one needs
local had = {}
on_kinds = function()
    local now = {}
    for _, k in ipairs(W.ADD_ORDER) do now[k] = has(k) end
    if now.weather and not had.weather then show_weather() end
    if now.calendar and not had.calendar then show_cal() end
    if now.claude and not had.claude then show_claude() end
    if now.launch then show_launch() end
    if now.photo and not had.photo then photo_list() end
    if now.timer and timer and not timer.ends and not timer.brk and timer.total ~= timer_len() * 60 then timer = DD.timer(timer_len()); show_timer() end
    had = now
end

-- ── The visualiser's feed (the bar's one cava) ──
-- the feed is wanted for a visualiser, a music widget showing one, and an analogue clock (its
-- second hand breathes with the bass, D141)
local function drawn_here()
    return not fact.viz_ext or fact.editing or fact.wg_desk or (tonumber(fact.wg_dkp) or 0) > 0.01
end
local function any_viz()
    for _, w in ipairs(doc.widgets) do
        if (w.kind == "visualiser" and drawn_here()) or (w.kind == "nowplaying" and (w.options or {}).viz == true) or w.layout == "analogue" then return true end
    end
    return false
end
local viz_seq, viz_at, last_beat = nil, 0, 0
local rings = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
-- Each visualiser slot's own bars (D138): smoothed levels and peak dots, as many as its `bars`.
local SLOTS = { "vzA", "vzB", "vzC" }
local lanes = { {}, {}, {} }            -- { lev = {}, pk = {}, hold = {} }
local frame_n = 0
local scope_hist = { {}, {}, {} }
local fc = {}                           -- the visualiser's facts as last written (setf, below)
local function hush()
    for i = 0, 15 do fact["vb" .. i] = 0.03; fc["vb" .. i] = 0.03 end
    for i = 0, 31 do fact["vs" .. i] = 0.03; fc["vs" .. i] = 0.03 end
    fact.np_beat = 0
    for k = 1, 4 do rings[k] = { 0, 0 }; fact["rp_a" .. (k - 1)] = 0 end
    for k = 1, 3 do lanes[k] = {}; model[SLOTS[k]] = {} end
end
-- the visualisers that get bars of their own: lanes 1…3 by list order (three at most)
local function viz_slots()
    local out, n = {}, 0
    for _, w in ipairs(doc.widgets) do
        if w.kind == "visualiser" then
            n = n + 1
            if n <= 3 then out[n] = w end
        end
    end
    return out
end
local function feed_lane(k, w, bands)
    local o = w.options or {}
    local n = math.floor(tonumber(o.bars) or 64)
    local target = vizfeed.resample(bands, n)
    local L = lanes[k]
    if L.n ~= n then L.n, L.lev, L.pk, L.hold = n, {}, {}, {} end
    -- rise at once, fall by `smooth` (0 quick … 1 slow); peaks hold 12 frames (400 ms), then fall 1.2 a second
    local fall = 0.02 + (1 - (tonumber(o.smooth) or 0.5)) * 0.16
    local now = frame_n
    local rows = {}
    for i = 1, n do
        local v = math.max(target[i], (L.lev[i] or 0) - fall)
        L.lev[i] = v
        local p = L.pk[i] or 0
        if v >= p then p = v; L.hold[i] = now + 12
        elseif now > (L.hold[i] or 0) then p = math.max(v, p - 0.04) end
        L.pk[i] = p
        rows[i] = { v = v, pk = p }
    end
    model[SLOTS[k]] = rows
end
-- A fact written only when it has moved enough to see (D154): the bands were written 30 times a second
-- whether or not they had changed, ~120 facts a tick, and every write wakes what reads it in the scene.
local function setf(name, v)
    local o = fc[name]
    if o == nil or math.abs(o - v) > 0.006 then fc[name] = v; fact[name] = v end
end
local function take_viz()
    local t, wide
    local ok2, raw2 = pcall(sys.ask, "files.read", vizfeed.FILE_V2)
    if ok2 and type(raw2) == "string" then
        t = vizfeed.decode_v2(raw2)
        if t and not vizfeed.newer(viz_seq, t.seq) then t = nil end
        wide = t ~= nil
    end
    if not t then
        local ok, raw = pcall(sys.ask, "files.read", vizfeed.FILE)
        if not ok or type(raw) ~= "string" then return end
        t = vizfeed.decode(raw)
        if not t or not vizfeed.newer(viz_seq, t.seq) then return end
    end
    viz_seq, viz_at = t.seq, os.time()
    if not t.playing then hush(); return end
    local b = vizfeed.resample(t.bands, 16)
    for i = 0, 15 do setf("vb" .. i, b[i + 1]) end
    if drawn_here() then
        local s32 = vizfeed.resample(t.bands, 32)
        for i = 0, 31 do setf("vs" .. i, s32[i + 1]) end
    end
    frame_n = frame_n + 1
    local slots = viz_slots()
    local scope = false
    if drawn_here() then
        for k, w in ipairs(slots) do
            feed_lane(k, w, t.bands)
            if w.mode == "scope" then scope = true end
        end
    end
    -- the scope's afterimages: the last three frames of 24 bands, one every other frame
    if scope and frame_n % 2 == 0 then
        scope_hist[3], scope_hist[2] = scope_hist[2], scope_hist[1]
        scope_hist[1] = vizfeed.resample(t.bands, 24)
        for h = 1, 3 do
            local f = scope_hist[h]
            for i = 0, 23 do setf("so" .. (h - 1) .. "_" .. i, f[i + 1] or 0.03) end
        end
    end
    local beat = (tonumber(t.beat) or 0) > 0.9 and last_beat <= 0.9
    last_beat = tonumber(t.beat) or 0
    if beat then
        fact.np_beat = 1
        after(60, function() fact.np_beat = 0 end)
        table.remove(rings, 1)
        rings[4] = { 0.02, math.min(1, 0.5 + (b[2] or 0)) }
    end
    fact.viz_wide = wide == true
end
every(33, function()
    if not (playing and any_viz() and not fact.viz_still) then return end
    take_viz()
    for k = 1, 4 do
        local r = rings[k]
        if r[2] > 0.02 then
            r[1] = r[1] + 0.025; r[2] = r[2] * 0.96
            fact["rp_r" .. (k - 1)], fact["rp_a" .. (k - 1)] = math.min(1.2, r[1]), r[2]
        elseif fact["rp_a" .. (k - 1)] ~= 0 then fact["rp_a" .. (k - 1)] = 0 end
    end
end)
-- The bar runs the one cava and writes the feed for a few seconds after each ask (D118).
every(3000, function()
    if playing and any_viz() and not fact.viz_still then run("pleamar", { "--say", "mooi", "emit feed_want" }) end
end)
every(400, function()
    if viz_seq and not vizfeed.fresh(viz_at * 1000, os.time() * 1000) then viz_seq, viz_at = nil, 0; hush() end
end)
