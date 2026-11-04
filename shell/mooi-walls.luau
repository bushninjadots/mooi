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
local view = walls.VIEW_INDEX[kept.view] or walls.VIEW_INDEX[cfg.view] or 0
local src = math.max(0, math.min(2, math.floor(tonumber(kept.src) or 0)))
local trk = TR_INDEX[kept.transition] or TR_INDEX[desk.normalize(settings.desk).transition] or 0
fact.view, fact.src, fact.trk = view, src, trk
local function keep()
    if SAFE then return end
    pcall(sys.call, "files.write", "walls-state.json", { view = walls.VIEWS[view + 1], src = src, transition = TR[trk + 1] })
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

local function kind_word(it)
    if it.kind == "video" then return "LIVE · VIDEO" end
    if it.kind == "animated" then return "LIVE · ANIMATED" end
    return "PICTURE"
end
local function describe(it, i)
    if not it then text.wl_name = ""; text.wl_kind = ""; return end
    text.wl_name = it.name
    text.wl_kind = string.format("%s · %s · %d OF %d%s", kind_word(it), walls.band_name(it.hue), i, #list,
        it.path == on_path and " · ON THE DESK NOW" or "")
end

-- The picture to show over the whole screen (Space): a still or an animated one as it is, a video
-- as its still.
local function preview(it)
    if not it then fact.has_prev = false; return end
    local p = it.kind == "video" and it.still or it.path
    text.prev_path = p
    fact.has_prev = p ~= ""
end

local function say_line()
    local words = { "ALL", "PICTURES", "LIVE" }
    local s = string.format("%d %s", #list, src == 0 and "WALLPAPERS" or words[src + 1])
    if query ~= "" then s = s .. " MATCHING “" .. string.upper(query) .. "”" end
    if not complete then s = s .. " · STILL READING THE FOLDERS…" end
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
    if view == 0 then describe(list[at], at); preview(list[at]) end
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
    local still = it.kind == "video" and it.still or it.path
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

local REACH, MAG, NEAR_N = 0.26, 2.3, 16
local function show_orbit()
    if cell == nil then model.orb = {}; near = {}; fact.or_near = false; return end
    -- the cell's middle on the wheel (unit radius), turned back by the wheel's turn
    local gx = ((cell % 20) + 0.5) / 10 - 1
    local gy = (math.floor(cell / 20) + 0.5) / 10 - 1
    local a = math.rad(-(tonumber(fact.or_spin) or 0))
    local px, py = gx * math.cos(a) - gy * math.sin(a), gx * math.sin(a) + gy * math.cos(a)
    if px * px + py * py > 1.1 * 1.1 then model.orb = {}; near = {}; fact.or_near = false; return end
    near = walls.nearest(places, px, py, NEAR_N, REACH)
    local rows = {}
    for j, i in ipairs(near) do
        local p, it = places[i], list[i]
        local dx, dy = p.x - px, p.y - py
        local d = math.sqrt(dx * dx + dy * dy)
        -- a loupe: the ones round the pointer spread out from it, the nearest the largest
        rows[#rows + 1] = { pic = it.thumb, ux = px + dx * MAG, uy = py + dy * MAG,
                            r = j == 1 and 1 or math.max(0.05, 0.92 * (1 - d / REACH)),
                            live = walls.is_live(it.kind), on = it.path == on_path }
    end
    model.orb = rows
    fact.or_near = #rows > 0
    local first = list[near[1]]
    describe(first, near[1] or 0)
    preview(first)
    if first ~= pal_want then
        pal_want = first
        show_pal(first and pal_cache[first.path] or nil)
        local mine = first
        after(250, function() if pal_want == mine then read_pal() end end)
    end
end

-- ── The list ──
local function refilter()
    local keep_path = list[at] and list[at].path or on_path
    list = walls.filter(all, walls.SOURCES[src + 1], query)
    -- the places are the whole index's (the dots drawn are), so a filtered list keeps them
    places = {}
    for i, it in ipairs(list) do places[i] = place_of[it.path] or { x = 9, y = 9 } end
    at = walls.find(list, keep_path) or walls.find(list, on_path) or 1
    say_line()
    show_strip()
    show_orbit()
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

local function wear(it)
    if not it then return end
    text.wl_line = "WEARING " .. string.upper(it.name) .. "…"
    run("mooi", { "wall", "apply", it.path, "--transition", TR[trk + 1] }, function(_, code)
        if code == 0 then close() else text.wl_line = "COULD NOT WEAR " .. string.upper(it.name) .. " · SEE `mooi wall apply`" end
    end)
end
on("wl_wear", function(v)
    v = math.floor(tonumber(v) or -1)
    if view == 1 then wear(list[near[1] or 0]) else wear(list[at]) end
end)

on("wl_view", function(v)
    view = math.floor(tonumber(v) or 0) == 1 and 1 or 0
    fact.view = view
    keep()
    if view == 0 then show_strip() else show_orbit() end
end)
on("wl_src", function(v)
    src = math.max(0, math.min(2, math.floor(tonumber(v) or 0)))
    fact.src = src
    keep()
    refilter()
end)
on("wl_tr", function()
    trk = (trk + 1) % #TR
    fact.trk = trk
    keep()
end)
on("wl_step", function(v)
    v = tonumber(v) or 0
    if #list == 0 then return end
    -- `r`: a picture at random (Luau's math.random is the same in every copy: the clock instead)
    if v == 0.5 then rolls = rolls + 1; at = ((os.time() * 7919 + rolls * 104729) % #list) + 1
    else at = math.max(1, math.min(#list, at + math.floor(v))) end
    show_strip()
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
    show_orbit()
end)
on("wl_spin", function(v)
    fact.or_spin = (tonumber(fact.or_spin) or 0) + (tonumber(v) or 0) * 12
    show_orbit()
end)
on("wl_prev", function() fact.prev = not fact.prev end)
on("text:wl_query", function(v)
    query = type(v) == "string" and v or ""
    fact.has_query = query ~= ""
    refilter()
end)
pcall(sys.watch, "files:wall.json", function() on_path = worn(); show_strip() end)

load_index()
fact.wl_in = 1
