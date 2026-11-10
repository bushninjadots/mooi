-- What the node's launcher finds besides apps (D234): mooi's own commands and the windows that are open, each a
-- row that says what it is. Pure: lists in, scored rows out; the logic runs what is chosen.
--
-- Only what is safe to reach from a search line is here: opening mooi's panels and tools, the light, the lock,
-- a recording. Nothing that stops, restarts or rewrites anything.

local M = {}
local FZ = require("lib/node/fuzzy")

M.LIST = {
    { name = "Settings", args = { "settings" }, words = "preferences options configure" },
    { name = "The Pill's studio", args = { "node", "studio" }, words = "pill node look style customise customize theme" },
    { name = "Time: timer, stopwatch, focus, alarm", args = { "node", "time" }, words = "timer stopwatch focus pomodoro alarm clock" },
    { name = "Wallpaper picker", args = { "walls" }, words = "wallpaper background picture image" },
    { name = "Arrange the widgets", args = { "widgets", "edit" }, words = "widgets desktop arrange edit" },
    { name = "Control Nexus", args = { "nexus" }, words = "nexus control centre center dashboard" },
    { name = "Music player", args = { "player" }, words = "music player songs library lyrics mpd" },
    { name = "Clipboard history", args = { "clipboard" }, words = "clipboard copy paste history" },
    { name = "Quick notes", args = { "notes" }, words = "notes notices" },
    { name = "The board", args = { "board" }, words = "kanban board tasks todo" },
    { name = "Every workspace", args = { "overview" }, words = "overview workspaces spaces expose" },
    { name = "Light or dark", args = { "mode" }, words = "light dark mode night day theme" },
    { name = "Lock the screen", args = { "lock" }, words = "lock screen away" },
    { name = "Record the screen", args = { "record" }, words = "record recording screen capture video" },
}

local function lower(s) return string.lower(tostring(s or "")) end

-- how well a query matches a name (and its other words): 3 the name starts with it, 2 a word of the name does,
-- 1 it is inside the name or the words, 0 not at all. Every word of the query must be found.
function M.score(q, name, words)
    q = lower(q):gsub("^%s+", ""):gsub("%s+$", "")
    if q == "" then return 0 end
    local n, w = lower(name), lower(words)
    local best = 3
    for part in q:gmatch("%S+") do
        local s
        if n:sub(1, #part) == part then s = 3
        elseif n:find("%f[%w]" .. part:gsub("%p", "%%%0")) then s = 2
        elseif n:find(part, 1, true) or w:find(part, 1, true) then s = 1
        -- D235: letters in order, mostly at the starts of words ("vsc", "nxs"): as weak as a match inside a word
        elseif FZ.score(part, name) >= 40 then s = 1
        else return 0 end
        if s < best then best = s end
    end
    return best
end

-- the commands that match, best first (a name's own order among equals)
function M.match(q, limit)
    local out = {}
    for i, c in ipairs(M.LIST) do
        local s = M.score(q, c.name, c.words)
        if s > 0 then out[#out + 1] = { kind = "command", name = c.name, args = c.args, score = s, order = i } end
    end
    table.sort(out, function(a, b) if a.score ~= b.score then return a.score > b.score end; return a.order < b.order end)
    while #out > (limit or 3) do table.remove(out) end
    return out
end

-- the open windows that match (hyprctl -j clients), by their title or their app; never mooi's own surfaces
function M.windows(clients, q, limit)
    local out = {}
    if type(clients) ~= "table" then return out end
    for i, c in ipairs(clients) do
        if type(c) == "table" and type(c.address) == "string" and c.address ~= "" and c.mapped ~= false then
            local class, title = tostring(c.class or ""), tostring(c.title or "")
            if class ~= "" and class ~= "pleamar" then
                local s = math.max(M.score(q, title, class), M.score(q, class, ""))
                if s > 0 then
                    local ws = type(c.workspace) == "table" and tostring(c.workspace.name or c.workspace.id or "") or ""
                    out[#out + 1] = { kind = "window", name = title ~= "" and title or class, app = class, address = c.address,
                                      workspace = ws, score = s, order = i }
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.score ~= b.score then return a.score > b.score end; return a.order < b.order end)
    while #out > (limit or 2) do table.remove(out) end
    return out
end

-- the launcher's rows: apps as the ranking gives them, with the best commands and windows put first when they
-- match the start of their names, after the apps otherwise; never more than `max`
function M.merge(apps, commands, windows, max)
    max = max or 6
    local first, after = {}, {}
    for _, list in ipairs({ commands or {}, windows or {} }) do
        for _, r in ipairs(list) do
            if r.score >= 3 then first[#first + 1] = r else after[#after + 1] = r end
        end
    end
    local out = {}
    local function add(r) if #out < max then out[#out + 1] = r end end
    for _, r in ipairs(first) do add(r) end
    -- leave room for what matched less well, so a search never shows only apps when a command matches
    local room = max - #out - math.min(#after, 2)
    for i, a in ipairs(apps or {}) do if i <= room then add(a) end end
    for _, r in ipairs(after) do add(r) end
    for _, a in ipairs(apps or {}) do
        local seen = false
        for _, r in ipairs(out) do if r == a then seen = true end end
        if not seen then add(a) end
    end
    return out
end

-- the word each kind wears on its row
M.TAG = { app = "", command = "MOOI", window = "WINDOW", calc = "=", web = "WEB" }

return M
