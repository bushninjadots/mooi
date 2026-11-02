-- The desk's logic (D85): which picture is on the desktop, whether Lumen's cutout and plate
-- belong to it, where the active workspace sits along the parallax, and the settings. The data
-- folder is mooi's (bin/mooi links mooi-desk to it), so settings.json and desk.json are the
-- shell's own. The desk ends itself when `desk.on` is turned off; the bar starts it again.

local config = require("lib/config")
local desk = require("lib/desk")
local W = require("lib/wallpaper")

local HOME = tostring(sys.ask("env", "HOME"))
-- what the picker draws (`current_wallpaper` is a still made of it, for lock screens)
local CURRENT = HOME .. "/.cache/current_wallpaper_source"
local STATE = "desk.json"

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end

local settings = config.parse(read("settings.json"), json.decode)
local cfg = desk.normalize(settings.desk)
local current = nil
local shown = { wall = nil, cut = nil }

-- The settings the scene draws with. Motion saving (`motion.saver`) and reduced motion keep the
-- picture still: the cutout stays over the widgets, nothing travels.
local function apply_settings()
    cfg = desk.normalize(settings.desk)
    local motion = type(settings.motion) == "table" and settings.motion or {}
    local still = motion.reduced == true or motion.saver == "always"
    fact.mode = desk.PARALLAX_INDEX[cfg.parallax] or 0
    fact.over = desk.overscan(cfg.strength)
    fact.depth = cfg.depth and desk.DEPTH or 0
    fact.moving = not still
    fact.clock_on = cfg.clock
    fact.clock_pos = ({ ["top-right"] = 0, ["top-left"] = 1, ["bottom-right"] = 2, ["bottom-left"] = 3 })[cfg.clock_position] or 0
end

-- What to draw: the picture on the desktop now, and Lumen's layers while they belong to it. A new
-- picture goes into the hidden slot and the slots cross once it has had a moment to load.
local function refresh()
    if not current then return end
    local state = read(STATE, "json")
    local l = desk.layers(state, current, cfg)
    if l.wall ~= shown.wall then
        shown.wall = l.wall
        if fact.slot == 0 then text.wall_b = l.wall; fact.has_b = true else text.wall_a = l.wall; fact.has_a = true end
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

local function read_current()
    run("readlink", { "-f", CURRENT }, function(out, code)
        local p = tostring(out or ""):gsub("%s+$", "")
        if code == 0 and p ~= "" and p ~= current then current = p end
        -- a moving wallpaper (a video, a GIF) is the picker's to play: the desk steps aside
        fact.drawable = current ~= nil and W.is_image(current) and not current:lower():match("%.gif$")
        refresh()
    end)
end

-- The wallpaper can change from anywhere (the picker, Lumen, a script): a look every two seconds
-- costs one readlink.
local function poll()
    read_current()
    after(2000, poll)
end

pcall(sys.watch, "files:settings.json", function()
    settings = config.parse(read("settings.json"), json.decode)
    if not desk.normalize(settings.desk).on then
        run("pleamar", { "--say", "mooi-desk", "quit" })
        return
    end
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


local function update_clock()
    local now = os.date("*t")
    text.desk_clock_time = desk.clock_text(now, cfg.clock_24h, cfg.clock_seconds)
    text.desk_clock_date = string.upper(os.date("%A · %d %B"))
    after(1000, update_clock)
end

apply_settings()
update_clock()
poll()
