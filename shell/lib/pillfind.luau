-- The Pill's search (D178): the forms it can open, by name. Pure, so tests/unit runs it under plain
-- Lua 5.4. A form is { key, name, sub, tag, room?, act?, arg?, closes?, alt? }: a room of the board's
-- own, or an act (the event its module's press sends, closing the board where it opens another
-- surface). `alt` is what the owner might type instead of the name — "internet" for Wi-Fi, "loom" for
-- Signals. Nothing here touches the shell; shell/pillboard.luau publishes what it finds.

local M = {}

M.MAX = 5        -- the rows the core has room for

M.FORMS = {
    { key = "player", name = "Music player", sub = "The player, full", tag = "PLAYER", act = "open_player", arg = 0,
      closes = true, alt = { "music", "song", "album", "sound" } },
    { key = "signals", name = "Signals", sub = "What Loom has kept", tag = "LOOM", room = "signals",
      alt = { "notifications", "loom", "messages", "alerts" } },
    { key = "notes", name = "Notes", sub = "Quick notes, on the right", tag = "NOTES", act = "qn_toggle",
      closes = true, alt = { "note", "quick", "scratch" } },
    { key = "stash", name = "Stash", sub = "The little box on the left edge, in here", tag = "STASH",
      room = "stash", alt = { "clips", "kept", "files", "box" } },
    { key = "wifi", name = "Wi-Fi", sub = "The radio and the networks in reach", tag = "NET",
      room = "connections", alt = { "internet", "network", "wireless", "wlan" } },
    { key = "calendar", name = "Calendar", sub = "The month", tag = "TIME", room = "calendar",
      alt = { "month", "dates", "week" } },
    { key = "workspaces", name = "Workspaces", sub = "Where the windows are", tag = "SPACES",
      room = "workspaces", alt = { "space", "windows" } },
    { key = "diagnostics", name = "Diagnostics", sub = "The machine, the kernel, its uptime", tag = "SYS",
      room = "diagnostics", alt = { "system", "uptime", "kernel" } },
    { key = "resources", name = "Resources", sub = "The processor, the memory, the temperature", tag = "CPU",
      room = "resources", alt = { "cpu", "memory", "ram" } },
    { key = "overview", name = "Overview", sub = "Every workspace at once", tag = "ATLAS",
      act = "open_overview_cmd", closes = true, alt = { "atlas", "map" } },
    { key = "settings", name = "Settings", sub = "mooi's own", tag = "SET", act = "bar_menu",
      closes = true, alt = { "preferences", "options" } },
}

local function trim(s)
    s = string.gsub(tostring(s or ""), "^%s+", "")
    return string.gsub(s, "%s+$", "")
end

local function has(hay, needle) return string.find(hay, needle, 1, true) ~= nil end

-- The forms that answer `q`, the best first (a name that starts with it, then one that holds it, then
-- its reading or its other names); an empty query is all of them, `limit` (`MAX`) at most.
function M.search(q, limit)
    local s = string.lower(trim(q))
    local cap = math.max(1, math.min(tonumber(limit) or M.MAX, M.MAX))
    local out = {}
    for _, f in ipairs(M.FORMS) do
        local hit, near = s == "", 3
        if s ~= "" then
            local name = string.lower(f.name)
            if string.sub(name, 1, #s) == s then hit, near = true, 0
            elseif has(name, s) then hit, near = true, 1
            elseif has(f.key, s) then hit, near = true, 1
            elseif has(string.lower(f.sub or ""), s) then hit, near = true, 2
            else
                for _, a in ipairs(f.alt or {}) do
                    if has(string.lower(a), s) or string.sub(string.lower(a), 1, #s) == s then hit, near = true, 2; break end
                end
            end
        end
        if hit then out[#out + 1] = { f = f, near = near, n = #out } end
        if #out >= cap * 3 then break end
    end
    table.sort(out, function(a, b)
        if a.near ~= b.near then return a.near < b.near end
        return a.n < b.n
    end)
    local rows = {}
    for i = 1, math.min(#out, cap) do rows[i] = out[i].f end
    return rows
end

-- The form at `i` (0-based, as the scene's rows are), in the catalogue's own order.
function M.get(i) return M.FORMS[(tonumber(i) or -1) + 1] end

return M
