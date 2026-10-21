-- Saved environments (D43): a working setup kept to come back to — the workspaces' names, accents
-- and groups, and which app was on which workspace (a terminal with the folder it was in). Pure, so
-- tests/unit runs it; shell/mooi.luau reads the desktop for it and carries a restore out.
--
-- A file of these is data, never a script: it names an installed app (its .desktop id) and a folder,
-- and a restore builds the launch from the app's own installed entry. Nothing is ever closed: a
-- restore moves the windows that are already open and opens only what is missing.

local M = {}

M.VERSION = 1
M.MAX_ENVS, M.MAX_WINDOWS = 20, 60
local NAME_MAX = 32

local function cut(s, n)
    local ok, len = pcall(utf8.len, s)
    if not ok or not len then return string.sub(s, 1, n) end
    if len <= n then return s end
    return string.sub(s, 1, utf8.offset(s, n + 1) - 1)
end
local function clean_name(s)
    return type(s) == "string" and cut((string.gsub(s, "^%s+", "")):gsub("%s+$", ""), NAME_MAX) or ""
end
-- A .desktop id: letters, digits and . _ - + @, no path.
local function clean_desktop(s)
    return (type(s) == "string" and #s <= 128 and string.match(s, "^[%w%._%-%+@]+$")) and s or ""
end
-- A folder: absolute, no control characters (a line break could end a command), not too long.
local function clean_dir(s)
    return (type(s) == "string" and #s <= 4096 and string.sub(s, 1, 1) == "/" and not string.find(s, "%c")) and s or ""
end
local function clean_text(s, n)
    return type(s) == "string" and cut((string.gsub(s, "%c", " ")), n) or ""
end
local function clean_ws(n)
    n = tonumber(n)
    return (n and n == math.floor(n) and n >= 1 and n <= 99) and n or nil
end
local function clean_window(w)
    if type(w) ~= "table" then return nil end
    local ws = clean_ws(w.workspace)
    if not ws then return nil end
    return { class = clean_text(w.class, 128), desktop = clean_desktop(w.desktop), workspace = ws,
             title = clean_text(w.title, 120), cwd = clean_dir(w.cwd) }
end

-- The current desktop, kept as an environment. `identities` is lib/atlas's store (names, accents,
-- groups — kept as they are, checked again when read back); `windows` { class, desktop, workspace,
-- title, cwd } as the logic found them. Special workspaces are left out.
function M.capture(name, when, identities, windows)
    local out = { name = clean_name(name), saved = math.floor(tonumber(when) or 0), identities = identities or {}, windows = {} }
    for _, w in ipairs(windows or {}) do
        local c = clean_window(w)
        if c and #out.windows < M.MAX_WINDOWS then out.windows[#out.windows + 1] = c end
    end
    return out
end

-- A file read back: whatever is not as it should be is left out, a newer version is not guessed at.
function M.clean(raw)
    local out = { version = M.VERSION, envs = {} }
    if type(raw) ~= "table" or (raw.version ~= nil and raw.version ~= M.VERSION) or type(raw.envs) ~= "table" then return out end
    for _, e in ipairs(raw.envs) do
        if type(e) == "table" and clean_name(e.name) ~= "" and #out.envs < M.MAX_ENVS then
            local env = { name = clean_name(e.name), saved = math.floor(tonumber(e.saved) or 0),
                          identities = type(e.identities) == "table" and e.identities or {}, windows = {} }
            for _, w in ipairs(type(e.windows) == "table" and e.windows or {}) do
                local c = clean_window(w)
                if c and #env.windows < M.MAX_WINDOWS then env.windows[#env.windows + 1] = c end
            end
            out.envs[#out.envs + 1] = env
        end
    end
    return out
end

-- What restoring `env` would do on the desktop as it is (`clients`: { address, class, workspace }),
-- with `installed` the set of installed .desktop ids. Each saved window takes a window of its app
-- that is still free — one already on its workspace first (in place), else any (moved there); with
-- none, its app is opened there if installed; else it cannot be. Returns
--   { in_place = n, moves = { { address, from, to, app } }, launches = { { desktop, workspace, cwd, app } },
--     cannot = { { app, why } } }
function M.plan(env, clients, installed)
    local out = { in_place = 0, moves = {}, launches = {}, cannot = {} }
    local free = {}
    for _, c in ipairs(clients or {}) do free[#free + 1] = c end
    local function take(pred)
        for i, c in ipairs(free) do if pred(c) then table.remove(free, i); return c end end
        return nil
    end
    -- in place first, for every saved window, so a move never takes the window another one sits in
    local pending = {}
    for _, w in ipairs(env.windows or {}) do
        local c = take(function(c) return c.class == w.class and c.workspace == w.workspace end)
        if c then out.in_place = out.in_place + 1 else pending[#pending + 1] = w end
    end
    for _, w in ipairs(pending) do
        local c = take(function(c) return c.class == w.class end)
        if c then
            out.moves[#out.moves + 1] = { address = c.address, from = c.workspace, to = w.workspace, app = w.class }
        elseif w.desktop ~= "" and installed[w.desktop] then
            out.launches[#out.launches + 1] = { desktop = w.desktop, workspace = w.workspace, cwd = w.cwd or "", app = w.class }
        else
            out.cannot[#out.cannot + 1] = { app = w.class ~= "" and w.class or "an app", why = w.desktop == "" and "no app known for it" or "not installed" }
        end
    end
    return out
end

-- How a terminal is told where to open; other apps are opened as their entry says.
local DIR_FLAG = {
    kitty = function(q) return "--directory " .. q end,
    foot = function(q) return "--working-directory=" .. q end,
    alacritty = function(q) return "--working-directory " .. q end,
    ["com.mitchellh.ghostty"] = function(q) return "--working-directory=" .. q end,
    ghostty = function(q) return "--working-directory=" .. q end,
}
function M.quote(s) return "'" .. string.gsub(s, "'", "'\\''") .. "'" end

-- The launch for an installed entry's `exec` (its field codes taken out), in `cwd` where the app is a
-- terminal that takes one.
function M.launch_line(exec, class, cwd)
    local line = string.gsub(string.gsub(tostring(exec or ""), "%%[fFuUdDnNickvm]", ""), "%s+$", "")
    line = string.gsub(line, "%s%s+", " ")
    local flag = DIR_FLAG[string.lower(tostring(class or ""))]
    if flag and cwd and cwd ~= "" then line = line .. " " .. flag(M.quote(cwd)) end
    return line
end

-- Hyprland's Lua for opening `line` on workspace `ws` without going there.
function M.exec_cmd(ws, line)
    local body = "[workspace " .. math.floor(ws) .. " silent] " .. line
    return "hl.exec_cmd('" .. string.gsub(string.gsub(body, "\\", "\\\\"), "'", "\\'") .. "')"
end

return M
