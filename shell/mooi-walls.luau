-- mooi's wallpaper picker (D145): the list, and the windows of it the scene draws. The index is
-- tools/wallindex.py's (walls-index.json and walls-orbit.png in mooi's data folder — bin/mooi
-- links this program's folder to it); lib/walls filters it, keeps the strip's window and places
-- the orbit. Wearing is `mooi wall apply`; the picker then leaves.

local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")
local walls = require("lib/walls")
local desk = require("lib/desk")

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end
local function env(name, fallback)
    local ok, v = pcall(sys.ask, "env", name)
    if ok and type(v) == "string" and v ~= "" then return v end
    return fallback
end
local HOME = env("HOME", "")
local DATA = env("XDG_DATA_HOME", HOME .. "/.local/share") .. "/pleamar/mooi"
local SAFE = env("MOOI_SAFE", "") == "1"

local settings = config.parse(read("settings.json"), json.decode)
fact.cn_kind, fact.cn_scale = style.corners(settings)
local palette = read("palette.json", "json")
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
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)
local look = style.facts(settings)
if look and look.st_glow then fact.st_glow = look.st_glow end

-- What was chosen last time: the view, the source, the transition (walls-state.json).
local TR = { "random", "grow", "wipe", "slide", "fade" }
local TR_INDEX = { random = 0, grow = 1, wipe = 2, slide = 3, fade = 4 }
local kept = read("walls-state.json", "json")
kept = type(kept) == "table" and kept or {}
local cfg = walls.normalize(settings.walls, HOME)
-- the settings' defaults (Settings → Wallpaper, D147), then what was chosen last time
local W = type(settings.walls) == "table" and settings.walls or {}
local SRC_INDEX = { all = 0, pictures = 1, live = 2, wallhaven = 3 }
local view = walls.VIEW_INDEX[kept.view] or walls.VIEW_INDEX[W.view] or 0
local src = math.max(0, math.min(3, math.floor(tonumber(kept.src) or SRC_INDEX[W.source] or 0)))
fact.veil = math.max(50, math.min(100, tonumber(W.veil) or 93)) / 100
fact.slant = math.max(0, math.min(40, tonumber(W.slant) or 22)) / 100
fact.csz = ({ small = 0.8, medium = 1, large = 1.2 })[W.cards] or 1
local trk = TR_INDEX[kept.transition] or TR_INDEX[desk.normalize(settings.desk).transition] or 0
fact.view, fact.src, fact.trk = view, src, trk
local chip, light = -1, 0      -- the colour row (D147)
local function keep()
    if SAFE then return end
    pcall(sys.call, "files.write", "walls-state.json", { view = walls.VIEWS[view + 1], src = src, transition = TR[trk + 1],
                                                         chip = chip, light = light })
end

local function worn()
    local w = read("wall.json", "json")
    return type(w) == "table" and type(w.source) == "string" and w.source or nil
end

local all, list = {}, {}       -- the index, and what the source and the search leave of it
local places = {}              -- each of `list`'s places on the orbit (unit radius, before the turn)
local complete = false
local query = ""
local at = 1                   -- the strip's middle card in `list` (1-based)
local near = {}                -- the orbit's swollen ones, nearest first (indices into `list`)
local cell = nil               -- the orbit cell under the pointer (0..399), nil off the wheel
local on_path = worn()
local rolls = 0
local place_of = {}            -- each picture's place on the orbit, as walls-orbit.png has it (the whole index)

local show_dots, wh_thumbs     -- (below, with Wallhaven)
local refilter                 -- (below, with the list)
local show_circuit, show_orbit -- (below)
local wear, wh_fetch           -- (below)
local want_pal                 -- (below, with the orbit) the palette of the picture in view
-- Wallhaven, the fourth source (D147): its pages so far, the list's seed (random), the thumbnails
local wh = { items = {}, page = 0, last = 1, seed = nil, busy = false, failed = false, keyed = false, gen = 0 }
local function kind_word(it)
    if it.kind == "video" then return "LIVE · VIDEO" end
    if it.kind == "animated" then return "LIVE · ANIMATED" end
    return "PICTURE"
end
local function describe(it, i)
    if not it then text.wl_name = ""; text.wl_kind = ""; return end
    text.wl_name = it.name
    if it.remote then
        text.wl_kind = string.format("WALLHAVEN · %s · %s · %s · %d OF %d · ENTER SAVES AND WEARS IT", it.res,
            string.upper(it.purity or "sfw"), walls.band_name(it.hue), i, #list)
        return
    end
    text.wl_kind = string.format("%s · %s · %d OF %d%s", kind_word(it), walls.band_name(it.hue), i, #list,
        it.path == on_path and " · ON THE DESK NOW" or "")
end

-- The picture to show over the whole screen (Space): a still or an animated one as it is, a video
-- as its still.
local function preview(it)
    if not it then fact.has_prev = false; return end
    local p = it.remote and it.thumb or (it.kind == "video" and it.still or it.path)
    text.prev_path = p
    fact.has_prev = p ~= ""
end

local function say_line()
    local words = { "ALL", "PICTURES", "LIVE", "WALLHAVEN" }
    local s = string.format("%d %s", #list, src == 0 and "WALLPAPERS" or words[src + 1])
    if src == 3 then
        s = string.format("WALLHAVEN · %s · PAGE %d OF %d", string.upper(walls.WH_SORTS[(tonumber(fact.wh_sort) or 0) + 1]):gsub("_", " "), wh.page, wh.last)
        if wh.busy then s = s .. " · ASKING…" end
        if wh.failed then s = s .. " · NO ANSWER (OFFLINE?)" end
        if not wh.keyed then s = s .. " · SAFE FOR WORK (NO API KEY)" end
    end
    if query ~= "" then s = s .. " MATCHING “" .. string.upper(query) .. "”" end
    if chip >= 0 then s = s .. " · " .. (chip == walls.GREY_CHIP and "GREYS" or string.format("HUE %d°", chip * 15)) end
    if light > 0 then s = s .. (light == 1 and " · LIGHT" or " · DARK") end
    if not complete and src ~= 3 then s = s .. " · STILL READING THE FOLDERS…" end
    text.wl_line = s
end

-- ── The strip ──
local function show_strip()
    local first, last = walls.window(#list, at, 32)
    local rows = {}
    for k = first, last do
        local it = list[k]
        rows[#rows + 1] = { pic = it.thumb, k = k - 1, live = walls.is_live(it.kind), on = it.path == on_path }
    end
    model.strip = rows
    fact.at = math.max(0, at - 1)
    fact.count = #list
    if view == 0 then describe(list[at], at); preview(list[at]); want_pal(list[at]) end
end

-- ── The orbit ──
local PAL_ROLES = { "primary", "secondary", "tertiary", "primary_container", "tertiary_container", "surface_container_high" }
local pal_cache, pal_want, pal_busy = {}, nil, false
local function hex(c)
    local r, g, b = tostring(c or ""):match("#(%x%x)(%x%x)(%x%x)")
    if not r then return nil end
    return { cr = tonumber(r, 16) / 255, cg = tonumber(g, 16) / 255, cb = tonumber(b, 16) / 255 }
end
local function show_pal(rows) model.pal = rows or {}; fact.pal_n = rows and #rows or 0 end
local function read_pal()
    if pal_busy or not pal_want then return end
    local it = pal_want
    if pal_cache[it.path] then show_pal(pal_cache[it.path]); return end
    local still = it.remote and it.thumb or (it.kind == "video" and it.still or it.path)
    if still == "" then return end
    pal_busy = true
    local th = type(settings.theme) == "table" and settings.theme or {}
    local mode = type(palette) == "table" and palette.mode == "light" and "light" or "dark"
    run("matugen", { "image", still, "--dry-run", "-j", "hex", "-m", mode,
                     "--type", "scheme-" .. tostring(th.scheme or "tonal-spot"),
                     "--source-color-index", tostring(math.floor(tonumber(th.color_index) or 0)) }, function(out, code)
        pal_busy = false
        local rows = {}
        if code == 0 then
            local ok, doc = pcall(json.decode, out or "")
            local colors = ok and type(doc) == "table" and doc.colors or nil
            if type(colors) == "table" then
                for _, role in ipairs(PAL_ROLES) do
                    local c = type(colors[role]) == "table" and colors[role][mode] or nil
                    local v = type(c) == "table" and hex(c.color) or nil
                    if v then rows[#rows + 1] = v end
                end
            end
        end
        pal_cache[it.path] = rows
        if pal_want == it then show_pal(rows) else read_pal() end
    end)
end

-- The palette of the picture in view (the strip's middle card, the orbit's nearest), read once it
-- has stayed a quarter of a second.
want_pal = function(it)
    if it == pal_want then return end
    pal_want = it
    show_pal(it and pal_cache[it.path] or nil)
    local mine = it
    after(250, function() if pal_want == mine then read_pal() end end)
end

-- The panel the orbit and the board sit in (lib/walls `panel`, D149), for the screen as it is.
local SW, SH = 1920, 1047
local PANEL = walls.panel(SW, SH)
local function set_panel()
    PANEL = walls.panel(SW, SH)
    fact.pnx, fact.pny, fact.pnw, fact.pnh = PANEL.x, PANEL.y, PANEL.w, PANEL.h
end
set_panel()

-- A picture shown large (the orbit's preview, the board's core): its thumbnail at once, then — once
-- it has stayed a third of a second — the picture itself (a video's still; Wallhaven's large thumb).
local big_gen = 0
local function show_big(it)
    big_gen = big_gen + 1
    if not it then fact.core_on = false; return end
    text.core_pic = it.thumb ~= "" and it.thumb or (it.kind == "video" and it.still or it.path)
    fact.core_on = true
    local mine = big_gen
    if not it.remote then
        after(350, function()
            if mine ~= big_gen then return end
            text.core_pic = it.kind == "video" and it.still or it.path
        end)
    end
    describe(it, walls.find(list, it.path) or 0)
    preview(it)
    want_pal(it)
end

-- ── The orbit: a dial and a grid ──
-- The dial is every picture's colour (walls-orbit.png); the point on it — under the pointer, or held
-- by a press — gives the grid its twelve nearest pictures, and the grid is what is picked from: a
-- hover shows that one large, a press wears that one (D149: the swollen pile wore the nearest, which
-- was often not the one under the pointer).
local GRID_N = 12
local hold = nil                -- the cell a press holds (nil: the point follows the pointer)
local osel = 1                  -- the grid's picture in view (1-based)
local function dial()
    local rr = PANEL.h / 2 - 46
    return PANEL.x + 40 + rr, PANEL.y + PANEL.h / 2, rr
end
local function grid_boxes(n)
    local ocx, _, rr = dial()
    local ox0 = PANEL.x + 80 + rr * 2
    local ow = PANEL.x + PANEL.w - 36 - ox0
    local oh = ow * 9 / 16
    local top = PANEL.y + 124 + oh
    local cw = (ow - 3 * 10) / 4
    local ch = cw * 9 / 16
    local rows = math.max(1, math.min(3, math.floor((PANEL.y + PANEL.h - 20 - top + 10) / (ch + 10))))
    local out = {}
    for i = 0, math.min(n, rows * 4) - 1 do
        out[#out + 1] = { x = ox0 + (i % 4) * (cw + 10), y = top + math.floor(i / 4) * (ch + 10), w = cw, h = ch }
    end
    return out
end
show_orbit = function()
    local c = hold or cell
    if view ~= 1 then return end
    if c == nil then model.orb = {}; near = {}; fact.or_near = false; return end
    local ocx, ocy, rr = dial()
    local gx = ((c % 20) + 0.5) / 10 - 1
    local gy = (math.floor(c / 20) + 0.5) / 10 - 1
    fact.o_rx, fact.o_ry = ocx + gx * rr, ocy + gy * rr
    local a = math.rad(-(tonumber(fact.or_spin) or 0))
    local px, py = gx * math.cos(a) - gy * math.sin(a), gx * math.sin(a) + gy * math.cos(a)
    if px * px + py * py > 1.1 * 1.1 then model.orb = {}; near = {}; fact.or_near = false; return end
    local boxes = grid_boxes(GRID_N)
    near = walls.nearest(places, px, py, #boxes, 0.6)
    osel = math.max(1, math.min(osel, #near))
    local rows = {}
    for j, i in ipairs(near) do
        local it, bx = list[i], boxes[j]
        rows[j] = { pic = it.thumb, x = bx.x, y = bx.y, w = bx.w, h = bx.h, live = walls.is_live(it.kind),
                    on = it.path == on_path, sel = j == osel }
    end
    model.orb = rows
    fact.or_near = true
    fact.o_lock = hold ~= nil
    show_big(list[near[osel]])
    if src == 3 and wh_thumbs then wh_thumbs() end
end
on("wl_opick", function(v)
    local j = math.floor(tonumber(v) or -1) + 1
    if not near[j] or j == osel then return end
    osel = j
    show_orbit()
end)
on("wl_owear", function(v)
    local i = near[math.floor(tonumber(v) or -1) + 1]
    if i then wear(list[i]) end
end)
on("wl_olock", function(v)
    v = math.floor(tonumber(v) or -1)
    if hold ~= nil then hold = nil else hold = (v >= 0 and v < 400) and v or nil end
    osel = 1
    show_orbit()
end)

-- ── The circuit board ──
-- Twenty chips round the core, a page of the list at a time; the chosen one morphs from its chip
-- into the core along its lit trace, and a new page spreads out of the core.
local RING = walls.ring(PANEL)
local cpage = 0
local chip_at = {}              -- the board's chips → indices into `list`
local csel = -1                 -- the chosen chip (the model's index, from 0)
show_circuit = function()
    if view ~= 2 then return end
    local pages = math.max(1, math.ceil(#list / walls.RING_N))
    cpage = math.max(0, math.min(pages - 1, cpage))
    fact.cpage, fact.cpages = cpage, pages
    local crows, trows = {}, {}
    chip_at = {}
    for k, box in ipairs(RING.chips) do
        local li = cpage * walls.RING_N + k
        local it = list[li]
        if it then
            local idx = #crows
            crows[#crows + 1] = { pic = it.thumb, x = box.x, y = box.y, w = box.w, h = box.h, live = walls.is_live(it.kind),
                                  on = it.path == on_path, sel = idx == csel }
            chip_at[idx] = li
            local P = box.pts
            trows[#trows + 1] = { x0 = P[1][1], y0 = P[1][2], x1 = P[2][1], y1 = P[2][2], x2 = P[3][1], y2 = P[3][2],
                                  x3 = P[4][1], y3 = P[4][2], lit = idx == csel }
        end
    end
    model.cchips, model.ctr = crows, trows
    local c = RING.core
    fact.cox, fact.coy, fact.cow, fact.coh = c.x, c.y, c.w, c.h
    if src == 3 and wh_thumbs then wh_thumbs() end
end
local function choose_chip(i)
    local li = chip_at[i]
    if li == nil or i == csel then return end
    local box = RING.chips[li - cpage * walls.RING_N]
    -- the route from the core out to the chip, for the signal; the chip's box, for the morph
    local P = box.pts
    local pts = { P[4], P[3], P[2], P[1] }
    local Ls = walls.trace_lengths(pts)
    for k = 0, 3 do fact["a" .. k .. "x"], fact["a" .. k .. "y"] = pts[k + 1][1], pts[k + 1][2] end
    for k = 1, 3 do fact["al" .. k] = math.max(1, Ls[k]) end
    fact.gx, fact.gy, fact.gw, fact.gh = box.x, box.y, box.w, box.h
    text.core_old = tostring(text.core_pic or "")
    csel = i
    show_circuit()
    show_big(list[li])
    fact.pulse_n = (tonumber(fact.pulse_n) or 0) + 1
    fact.morph_n = (tonumber(fact.morph_n) or 0) + 1
end
on("wl_csel", function(v) choose_chip(math.floor(tonumber(v) or -1)) end)
on("wl_cwear", function(v)
    local li = chip_at[math.floor(tonumber(v) or -1)]
    if li then wear(list[li]) end
end)
on("wl_bpage", function(v)
    if view ~= 2 then return end
    local d = (tonumber(v) or 0) < 0 and -1 or 1
    local before = cpage
    cpage = cpage + d
    show_circuit()
    if cpage ~= before then
        csel = -1
        show_circuit()
        fact.page_n = (tonumber(fact.page_n) or 0) + 1
    end
    -- more of Wallhaven as its pages are reached
    if src == 3 and (cpage + 2) * walls.RING_N > #list then wh_fetch() end
end)
run("hyprctl", { "monitors", "-j" }, function(out)
    local ok, mons = pcall(json.decode, out or "")
    local m = ok and type(mons) == "table" and mons[1] or nil
    if type(m) == "table" and tonumber(m.width) and tonumber(m.height) then
        local sc = tonumber(m.scale) or 1
        SW, SH = tonumber(m.width) / sc, tonumber(m.height) / sc - 33
        set_panel()
        RING = walls.ring(PANEL)
        show_circuit(); show_orbit()
    end
end)

-- ── Wallhaven ──
-- The orbit has no dots image for it: up to 240 dots drawn as they come (their colour Wallhaven's own).
show_dots = function()
    if src ~= 3 then model.whdot = {}; return end
    local rows = {}
    for i = 1, math.min(240, #list) do
        local p, it = places[i], list[i]
        rows[i] = { x = p.x, y = p.y, cr = it.cr or 0.5, cg = it.cg or 0.5, cb = it.cb or 0.5 }
    end
    model.whdot = rows
end
wh_fetch = function()
    if wh.busy or wh.page >= wh.last then return end
    wh.busy, wh.failed = true, false
    say_line()
    local gen = wh.gen
    local args = { "wall", "wallhaven", "search", walls.WH_SORTS[(tonumber(fact.wh_sort) or 0) + 1],
                   walls.WH_RANGES[(tonumber(fact.wh_range) or 3) + 1], tostring(wh.page + 1), query,
                   walls.wh_colour(chip) or "", wh.seed or "" }
    run("mooi", args, function(out, code)
        if gen ~= wh.gen then return end                  -- the list was asked again meanwhile
        wh.busy = false
        local ok, doc = pcall(json.decode, out or "")
        local items, last, seed = nil, nil, nil
        if code == 0 and ok then items, last, seed = walls.wh_items(doc) end
        if not items then wh.failed = true; say_line(); return end
        for _, it in ipairs(items) do wh.items[#wh.items + 1] = it end
        wh.page, wh.last, wh.seed = wh.page + 1, last, seed or wh.seed
        refilter()
    end)
end
local function wh_restart()
    wh.gen = wh.gen + 1
    wh.items, wh.page, wh.last, wh.seed, wh.busy = {}, 0, 1, nil, false
    at = 1
    refilter()
    wh_fetch()
end
-- the thumbnails near what is shown (the strip's window, the orbit's nearest), two fetches at a time
local th_busy, th_tried = 0, {}
wh_thumbs = function()
    if src ~= 3 then return end
    local want = {}
    local first, last = walls.window(#list, at, 16)
    for k = first, last do want[#want + 1] = list[k] end
    for _, i in ipairs(near) do want[#want + 1] = list[i] end
    if view == 2 then for _, li in pairs(chip_at) do want[#want + 1] = list[li] end end
    for _, it in ipairs(want) do
        if th_busy >= 2 then return end
        if it and it.thumb == "" and not th_tried[it.id] then
            th_tried[it.id] = true
            th_busy = th_busy + 1
            run("mooi", { "wall", "wallhaven", "thumb", it.id, it.thumb_url }, function(out, code)
                th_busy = th_busy - 1
                local p = tostring(out or ""):gsub("%s+$", "")
                if code == 0 and p:sub(1, 1) == "/" then it.thumb = p end
                if src == 3 then show_strip(); show_orbit(); wh_thumbs() end
            end)
        end
    end
end

-- ── The list ──
refilter = function()
    local keep_path = list[at] and list[at].path or on_path
    if src == 3 then
        -- the search and the colour went to Wallhaven; the lightness is kept here
        list = walls.filter(wh.items, "all", "", -1, light)
        places = walls.orbit(list, 0)
        at = walls.find(list, keep_path) or math.min(at, math.max(1, #list))
        say_line(); show_strip(); show_orbit(); show_dots(); show_circuit(); wh_thumbs()
        return
    end
    list = walls.filter(all, walls.SOURCES[src + 1], query, chip, light)
    -- the places are the whole index's (the dots drawn are), so a filtered list keeps them
    places = {}
    for i, it in ipairs(list) do places[i] = place_of[it.path] or { x = 9, y = 9 } end
    at = walls.find(list, keep_path) or walls.find(list, on_path) or 1
    say_line()
    show_strip()
    show_orbit()
    show_circuit()
end

local function load_index()
    local doc = read("walls-index.json", "json")
    all = walls.items(doc)
    place_of = {}
    for i, p in ipairs(walls.orbit(all, 0)) do place_of[all[i].path] = p end
    complete = type(doc) == "table" and doc.complete == true
    local ok, there = pcall(sys.ask, "files.exists", "walls-orbit.png")
    -- the orbit's dots are of the whole index: drawn only while the list is all of it
    text.orbit_path = DATA .. "/walls-orbit.png"
    fact.has_orbit = ok and there == true
    refilter()
end
pcall(sys.watch, "files:walls-index.json", load_index)
pcall(sys.watch, "files:walls-orbit.png", function() text.orbit_path = ""; after(50, function() text.orbit_path = DATA .. "/walls-orbit.png"; fact.has_orbit = true end) end)

-- ── What the scene asks ──
local function close()
    if fact.wl_in == 0 then return end
    fact.wl_in = 0
    after(240, function() run("pleamar", { "--say", "mooi-walls", "quit" }) end)
end
on("wl_close", close)

wear = function(it)
    if not it then return end
    text.wl_line = (it.remote and "SAVING AND WEARING " or "WEARING ") .. string.upper(it.name) .. "…"
    local args = it.remote and { "wall", "wallhaven", "wear", it.id, it.url, "--transition", TR[trk + 1] }
                            or { "wall", "apply", it.path, "--transition", TR[trk + 1] }
    run("mooi", args, function(_, code)
        if code == 0 then close() else text.wl_line = "COULD NOT WEAR " .. string.upper(it.name) .. " · SEE `mooi wall apply`" end
    end)
end
on("wl_wear", function(v)
    v = math.floor(tonumber(v) or -1)
    if view == 1 then wear(list[near[osel] or 0])
    elseif view == 2 then local li = chip_at[csel]; if li then wear(list[li]) end
    else wear(list[at]) end
end)

on("wl_view", function(v)
    view = math.max(0, math.min(2, math.floor(tonumber(v) or 0)))
    fact.view = view
    keep()
    if view == 0 then show_strip() elseif view == 1 then show_orbit() else show_circuit() end
end)
on("wl_src", function(v)
    src = math.max(0, math.min(3, math.floor(tonumber(v) or 0)))
    fact.src = src
    keep()
    if src == 3 and #wh.items == 0 then wh_restart() else refilter() end
end)
on("wl_whsort", function(v)
    fact.wh_sort = math.max(0, math.min(3, math.floor(tonumber(v) or 0)))
    if src == 3 then wh_restart() end
end)
on("wl_whrange", function()
    fact.wh_range = ((tonumber(fact.wh_range) or 3) + 1) % #walls.WH_RANGES
    if src == 3 then wh_restart() end
end)
on("wl_tr", function()
    trk = (trk + 1) % #TR
    fact.trk = trk
    keep()
end)
on("wl_step", function(v)
    v = tonumber(v) or 0
    if #list == 0 then return end
    -- the board: ← → the next chip (↑ ↓ turn the page)
    if view == 2 then
        local n = 0
        for _ in pairs(chip_at) do n = n + 1 end
        if n == 0 then return end
        local i = csel < 0 and 0 or math.max(0, math.min(n - 1, csel + math.floor(v)))
        choose_chip(i)
        return
    end
    -- `r`: a picture at random (Luau's math.random is the same in every copy: the clock instead)
    if v == 0.5 then rolls = rolls + 1; at = ((os.time() * 7919 + rolls * 104729) % #list) + 1
    else at = math.max(1, math.min(#list, at + math.floor(v))) end
    show_strip()
    -- Wallhaven: the next page as the strip nears the end of what is loaded
    if src == 3 then wh_thumbs(); if at > #list - 8 then wh_fetch() end end
end)
on("wl_go", function(v)
    local k = math.floor(tonumber(v) or -1) + 1
    if not list[k] then return end
    if k == at then wear(list[k]); return end            -- a press on the middle card wears it
    at = k
    show_strip()
end)
on("wl_cell", function(v)
    cell = math.floor(tonumber(v) or -1)
    if cell < 0 or cell > 399 then cell = nil end
    if hold == nil then osel = 1; show_orbit() end
end)
on("wl_spin", function(v)
    fact.or_spin = (tonumber(fact.or_spin) or 0) + (tonumber(v) or 0) * 12
    show_orbit()
end)
on("wl_prev", function() fact.prev = not fact.prev end)
on("wl_chip", function(v)
    v = math.floor(tonumber(v) or -1)
    chip = (v == chip or v < 0 or v > walls.GREY_CHIP) and -1 or v
    fact.chip = chip
    keep()
    if src == 3 then wh_restart() else refilter() end
end)
on("wl_light", function(v)
    light = math.max(0, math.min(2, math.floor(tonumber(v) or 0)))
    fact.light = light
    keep()
    refilter()
end)

-- the colour row's chips, painted once
do
    local rows = {}
    for c = 0, walls.GREY_CHIP do
        local r, g, b = walls.chip_rgb(c)
        rows[#rows + 1] = { cr = r, cg = g, cb = b }
    end
    model.chips = rows
end
local q_gen = 0
on("text:wl_query", function(v)
    query = type(v) == "string" and v or ""
    fact.has_query = query ~= ""
    if src ~= 3 then refilter(); return end
    -- Wallhaven is asked once the typing stops
    q_gen = q_gen + 1
    local mine = q_gen
    after(700, function() if mine == q_gen and src == 3 then wh_restart() end end)
end)
pcall(sys.watch, "files:wall.json", function() on_path = worn(); show_strip() end)

-- Wallhaven's list and range as the settings choose (wallhaven.sorting / range), and whether a key is there
do
    local H = type(settings.wallhaven) == "table" and settings.wallhaven or {}
    local SORT = { toplist = 0, hot = 1, latest = 2, random = 3 }
    fact.wh_sort = SORT[H.sorting] or 0
    for i, r in ipairs(walls.WH_RANGES) do if r == H.range then fact.wh_range = i - 1 end end
    run("mooi", { "wall", "whkey" }, function(out) wh.keyed = tostring(out or ""):match("found") ~= nil; say_line() end)
end

load_index()
if src == 3 then wh_restart() end
fact.wl_in = 1
