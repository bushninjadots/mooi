-- The dock (D280; k4's Dual mode's dock, ported): the logic. Its items are lib/dock's working-out over the apps
-- Pleamar knows, Hyprland's windows (asked when the workspaces or the focus change, never on a timer) and the
-- pins kept in dock.json. It shows while the pointer is at the bottom edge or on it, and, if Settings says so,
-- while the workspace is empty.

local config = require("lib/config")
local ferro = require("lib/ferro")
local DK = require("lib/dock")
local HY = require("lib/hypr")

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind) else ok, v = pcall(sys.ask, "files.read", name) end
    if ok then return v end
end

K = { settings = config.parse(read("settings.json"), json.decode), apps = {}, clients = {}, active = "", items = {},
      hover = false, empty = false, asking = false, again = false }
local saved = read("dock.json", "json")
K.pinned = type(saved) == "table" and type(saved.pinned) == "table" and saved.pinned or {}

local function cfg() local d = K.settings.dock; return type(d) == "table" and d or {} end

-- ── the palette ──
local palette = read("palette.json", "json")
local function paint()
    local s = K.settings
    local out = ferro.resolve(s.theme.source, palette, s.theme.signal, false, ferro.options(s))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
end
paint()
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)

-- ── shown or not ──
local hide_at = nil
local function shown()
    fact.dk_show = K.held or K.hover or (K.empty and cfg().empty == true)
end
on("dk_hold", function() K.held = not K.held; shown() end)
on("dk_hover", function(v)
    if math.floor(tonumber(v) or 0) == 1 then
        K.hover, hide_at = true, nil
    else
        -- a moment's grace: the pointer crossing the gap between two icons is not leaving
        local mine = {}
        hide_at = mine
        after(700, function() if hide_at == mine then K.hover = false; shown() end end)
    end
    shown()
end)

-- ── the items ──
local function draw()
    K.items = DK.items(K.pinned, K.apps, K.clients, K.active)
    local rows = {}
    for i, it in ipairs(K.items) do
        rows[i] = { name = it.name, icon = it.icon, iconed = it.icon ~= "", letter = string.upper(string.sub(it.name, 1, 1)),
                    n = #it.windows, active = it.active, pinned = it.pinned }
    end
    model.it = rows
end
-- Hyprland's windows, one question at a time: a change while one is out asks once more after it
local function ask()
    if K.asking then K.again = true; return end
    K.asking = true
    run("hyprctl", { "-j", "clients" }, function(out)
        local ok, c = pcall(json.decode, out or "")
        K.clients = ok and type(c) == "table" and c or {}
        run("hyprctl", { "-j", "activewindow" }, function(o2)
            local ok2, a = pcall(json.decode, o2 or "")
            K.active = ok2 and type(a) == "table" and tostring(a.address or "") or ""
            K.asking = false
            draw()
            if K.again then K.again = false; ask() end
        end)
    end)
end
pcall(sys.watch, "apps", function(a)
    K.apps = type(a) == "table" and type(a.list) == "table" and a.list or {}
    draw()
end)
pcall(sys.watch, "workspaces", function(w)
    if type(w) == "table" then
        local active = tonumber(w.active)
        local count = nil
        for _, x in ipairs(type(w.list) == "table" and w.list or {}) do
            if type(x) == "table" and tonumber(x.id) == active then count = tonumber(x.windows) end
        end
        K.empty = count == 0
        shown()
    end
    ask()
end)
pcall(sys.watch, "window", function() ask() end)

-- ── presses ──
on("dk_press", function(v)
    local it = K.items[math.floor(tonumber(v) or -1) + 1]
    local what = DK.press(it, K.active)
    if not what then return end
    if what[1] == "launch" then
        pcall(sys.call, "apps.launch", what[2])
    elseif DK.address(what[2]) then
        local d = HY.dispatch("focus", what[2])
        if d then run("hyprctl", { "dispatch", d }, function() ask() end) end
    end
end)
on("dk_pin", function(v)
    local it = K.items[math.floor(tonumber(v) or -1) + 1]
    if not it then return end
    K.pinned = DK.toggle_pin(K.pinned, it.key)
    pcall(sys.call, "files.write", "dock.json", json.encode({ pinned = K.pinned }))
    draw()
end)

pcall(sys.watch, "files:settings.json", function()
    K.settings = config.parse(read("settings.json"), json.decode)
    paint(); shown()
end)
ask()
log("dock · up")
