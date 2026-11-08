-- The Pill board's parts (D170): every bar module as a pad. Pure: what each pad opens in the board's core
-- (a room) or does (an act: the same event its module's press sends), whether it is a switch (its pad lit
-- while on) and whether doing it opens another surface (the board closes then). The scene draws pad n with
-- icon n and reading n (ui/pillboard.plm), so a part's place in ORDER is its number there.

local barlayout = require("lib/barlayout")

local M = {}

-- every bar module but the Sigil (D207): a Sigil inside the classic Pill's board means nothing, and it is last
-- in the bar's order, so every other part keeps its index
M.ORDER = {}
for _, id in ipairs(barlayout.ORDER) do if id ~= "sigil" then M.ORDER[#M.ORDER + 1] = id end end

-- The core's rooms, in the scene's numbering (fact pk_room).
M.ROOMS = { "now", "calendar", "sound", "display", "connections", "power", "resources", "weather", "signals",
            "visualiser", "actions", "diagnostics", "workspaces", "wallpaper",
            "stash", "find",      -- D171: the first five added; D178: the stash and the search
            "notes" }             -- D201: quick notes, grown out of the Pill like every room

-- What each room is called when it is said aloud (the board's wheel, and BMO's line): one name per room,
-- beside the room, so a new room cannot be added without one (D202).
M.ROOM_NAME = { now = "now", calendar = "the month", sound = "sound", display = "display",
                connections = "connections", power = "power", resources = "resources", weather = "weather",
                signals = "signals", visualiser = "music!", actions = "actions", diagnostics = "diagnostics",
                workspaces = "workspaces", wallpaper = "wallpaper", stash = "the stash", find = "find it",
                notes = "notes" }

M.DEFAULT = { "volume", "brightness", "network", "bluetooth", "notifications", "clock", "battery", "nexus" }

local PARTS = {
    workspaces    = { room = "workspaces" },     -- D171
    window        = { act = "open_window", closes = true },
    media         = { room = "now" },
    resources     = { room = "resources" },
    bandwidth     = { room = "connections" },
    keyboard      = { act = "open_settings", closes = true },
    weather       = { room = "weather" },
    -- the tray holds many apps, so its pad only shows and goes back to Now (review I4: tray_cmd 0
    -- pressed whichever app happened to be first)
    tray          = { room = "now" },
    notifications = { room = "signals" },
    mic           = { act = "mic_mute", switch = true },
    volume        = { room = "sound" },
    brightness    = { room = "display" },
    battery       = { room = "power" },
    network       = { room = "connections" },
    bluetooth     = { room = "connections" },
    clock         = { room = "calendar" },
    caffeine      = { act = "caffeine", switch = true },
    recorder      = { act = "record", arg = 1, switch = true },
    screenshot    = { act = "shot", arg = 0, closes = true },
    clipboard     = { act = "clips", side = "clips", closes = true },
    power         = { room = "power" },          -- D201: its room, not the session menu elsewhere
    actions       = { room = "actions" },        -- D201
    overview      = { act = "open_overview_cmd", closes = true },
    core          = { room = "find" },           -- D201: the Pill's own search
    focus         = { act = "focus_cmd", arg = 0, switch = true },
    settings      = { act = "bar_menu", closes = true },
    notes         = { room = "notes" },          -- D201: the notes grow out of the Pill
    wallpaper     = { room = "wallpaper" },      -- D171
    nexus         = { act = "open_nexus", closes = true },
    updates       = { act = "run_updates", closes = true },
    claude        = { act = "open_claude", closes = true },
    github        = { act = "open_github", closes = true },
    -- D209/D210: their own faces and islands, not rooms; the acts open them from the board
    bmo           = { act = "open_bmo", closes = true },
    herdr         = { act = "open_herdr", closes = true },
}

local INDEX = {}
for i, id in ipairs(M.ORDER) do INDEX[id] = i - 1 end

-- { icon, room?, act?, arg?, side?, switch, closes } for a module id, or nil
function M.get(id)
    local p = PARTS[id]
    if not p or INDEX[id] == nil then return nil end
    return { icon = INDEX[id], room = p.room, act = p.act, arg = p.arg, side = p.side,
             switch = p.switch == true, closes = p.closes == true }
end

function M.index(id) return INDEX[id] end

function M.room_index(name)
    for i, r in ipairs(M.ROOMS) do if r == name then return i - 1 end end
    return nil
end

return M
