-- The desk's logic (D85, D145): which picture is on the desktop, whether Lumen's cutout and plate
-- belong to it, where the active workspace sits along the parallax, and the settings. The data
-- folder is mooi's (bin/mooi links mooi-desk to it), so settings.json, wall.json and desk.json are
-- the shell's own. The desk is the wallpaper: it always runs; `desk.on` is whether it travels.

local config = require("lib/config")
local desk = require("lib/desk")
local walls = require("lib/walls")

local HOME = tostring(sys.ask("env", "HOME"))
-- the wallpaper's file, and its still (a video's frame), for anything that sets them by hand
local CURRENT = HOME .. "/.cache/current_wallpaper_source"
local STILL = HOME .. "/.cache/current_wallpaper"
local STATE = "desk.json"
-- what `mooi wall apply` wore (D145): the file, its still, its kind, the transition, the notch's edge
local WALL = "wall.json"

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end

local settings = config.parse(read("settings.json"), json.decode)
local cfg = desk.normalize(settings.desk)
local current = nil          -- the picture drawn (a video's still)
local source = nil           -- the file worn (the video itself)
local wall_tr = ""           -- the transition wall.json asked for ("" is the setting's)
local shown = { wall = nil, cut = nil }
local from_notch = false   -- the notch picked the next picture: it grows from where the notch is
on("from_notch", function(v)
    v = math.floor(tonumber(v) or 0)
    from_notch = true
    fact.tr_x, fact.tr_y = 0, v
end)

-- The settings the scene draws with. Motion saving (`motion.saver`) and reduced motion keep the
-- picture still: the cutout stays over the widgets, nothing travels.
local function apply_settings()
    cfg = desk.normalize(settings.desk)
    local motion = type(settings.motion) == "table" and settings.motion or {}
    local still = motion.reduced == true or motion.saver == "always"
    -- `desk.on` off: the picture still, at the screen's size
    fact.mode = cfg.on and (desk.PARALLAX_INDEX[cfg.parallax] or 0) or 0
    fact.over = fact.mode > 0 and desk.overscan(cfg.strength) or 0
    fact.depth = cfg.depth and desk.DEPTH or 0
    fact.moving = not still
    local w = type(settings.walls) == "table" and settings.walls or {}
    fact.pace = ({ quick = 0, normal = 1, slow = 2 })[w.speed] or 1
end

-- What to draw: the picture on the desktop now, and Lumen's layers while they belong to it. A new
-- picture goes into the hidden slot and the slots cross once it has had a moment to load.
-- A picture asked for while a transition is still running waits for it to end (the latest one wins):
-- put into the hidden slot at once, it replaced the picture still going out, half-way (D149).
local crossing, waiting = false, false
local function pace_ms()
    local w = type(settings.walls) == "table" and settings.walls or {}
    local base = ({ quick = 500, normal = 950, slow = 1600 })[w.speed] or 950
    local m = type(settings.motion) == "table" and tonumber(settings.motion.speed) or 100
    return math.floor(base * 100 / math.max(25, m or 100)) + 150
end
local function refresh()
    if not current then return end
    local state = read(STATE, "json")
    local l = desk.layers(state, current, cfg)
    if l.wall ~= shown.wall and crossing then waiting = true; return end
    if l.wall ~= shown.wall then
        shown.wall = l.wall
        crossing = true
        after(120 + pace_ms(), function()
            crossing = false
            if waiting then waiting = false; refresh() end
        end)
        if fact.slot == 0 then text.wall_b = l.wall; fact.has_b = true else text.wall_a = l.wall; fact.has_a = true end
        -- how it comes in (D144): the kind chosen (random: one of four); grown from the notch when it
        -- was picked there (it says so just before), else from the middle
        fact.tr = desk.transition(wall_tr ~= "" and wall_tr or cfg.transition, (os.time() % 97) / 97)
        wall_tr = ""
        if not from_notch then fact.tr_x, fact.tr_y = 960, 540 end
        from_notch = false
        after(120, function() fact.slot = fact.slot == 0 and 1 or 0 end)
    end
    -- only floating subjects need the plate; a flat one is laid over the picture as it is
    fact.depth = (cfg.depth and l.floats) and desk.DEPTH or 0
    if l.cut ~= shown.cut then
        shown.cut = l.cut
        text.cut_path = l.cut
        fact.has_cut = l.cut ~= ""
    end
end

-- What wall.json says is worn. A video is drawn as its still until mpvpaper is up underneath; the
-- desk asks `mooi wall live` for it whenever a video is worn and nothing plays it (at start, too).
local function read_wall()
    local st = walls.state(read(WALL, "json"))
    if not st then return false end
    if st.source ~= source then
        source = st.source
        wall_tr = st.transition or ""
        if st.from_y then from_notch = true; fact.tr_x, fact.tr_y = st.from_x or 0, st.from_y end
    end
    current = st.still
    if st.kind ~= "video" then fact.live = false end
    refresh()
    if st.kind == "video" and not fact.live then run("mooi", { "wall", "live" }, function() end) end
    return true
end
on("live_on", function(v) fact.live = (tonumber(v) or 0) ~= 0 end)

-- The wallpaper can still change from elsewhere (a script setting the links by hand): a look every
-- two seconds costs one readlink. A link that is not what wall.json wore is drawn as it is — the
-- still beside it when the file is not a picture the desk can draw.
local function read_links()
    run("readlink", { "-f", CURRENT }, function(out, code)
        local p = tostring(out or ""):gsub("%s+$", "")
        if code ~= 0 or p == "" or p == source then return end
        source = p
        if walls.kind(p) == "video" or not desk.is_image(p) then
            run("readlink", { "-f", STILL }, function(o2)
                local s2 = tostring(o2 or ""):gsub("%s+$", "")
                if s2 ~= "" then current = s2; refresh() end
            end)
        else
            current = p
            refresh()
        end
    end)
end
local function poll()
    read_links()
    after(2000, poll)
end

pcall(sys.watch, "files:" .. WALL, read_wall)
pcall(sys.watch, "files:settings.json", function()
    settings = config.parse(read("settings.json"), json.decode)
    apply_settings()
    shown.cut = nil
    refresh()
end)
pcall(sys.watch, "files:" .. STATE, function() shown.wall = nil; shown.cut = nil; refresh() end)

pcall(sys.watch, "workspaces", function(w)
    if type(w) ~= "table" then return end
    local ids = {}
    if type(w.list) == "table" then
        for _, row in ipairs(w.list) do
            if type(row) == "table" and tonumber(row.id) then ids[#ids + 1] = tonumber(row.id) end
        end
    end
    fact.ws_frac = desk.workspace_fraction(w.active, ids)
end)


-- ── The auto-change (walls.auto, D147): a new wallpaper every so many minutes ──
-- A look once a minute: long enough since the last change (wall.json's `at`, so a pick by hand counts),
-- and, when asked, no window fullscreen. `mooi wall next` chooses and wears it.
local function auto_tick()
    after(60000, auto_tick)
    local w = type(settings.walls) == "table" and settings.walls or {}
    if w.auto ~= true then return end
    local st = walls.state(read(WALL, "json"))
    local every = math.max(5, math.min(240, math.floor(tonumber(w.auto_every) or 30))) * 60
    if st and os.time() - (st.at or 0) < every then return end
    local function go() run("mooi", { "wall", "next", tostring(w.auto_from or "pictures") }, function() end) end
    if w.auto_fullscreen == false then go(); return end
    run("hyprctl", { "activewindow", "-j" }, function(out)
        local ok, win = pcall(json.decode, out or "")
        if ok and type(win) == "table" and (tonumber(win.fullscreen) or 0) > 0 then return end
        go()
    end)
end

apply_settings()
read_wall()
poll()
after(60000, auto_tick)
