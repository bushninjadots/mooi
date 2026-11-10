-- The node's terminal helper (D246): the argv that opens a program in the owner's terminal, which
-- terminal to use, and the command that asks which ones are installed. Pure: it builds argv tables and
-- reads text, and runs nothing itself.

local M = {}

-- the terminals the node knows, in the order it prefers them
local ORDER = { "kitty", "foot", "alacritty", "wezterm", "ghostty", "konsole", "xterm" }
local KNOWN = {}
for _, name in ipairs(ORDER) do KNOWN[name] = true end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- a command as a list of strings, or nil when it is not one
local function command(cmd)
    if type(cmd) ~= "table" then return nil end
    local out = {}
    for i = 1, #cmd do
        if type(cmd[i]) ~= "string" then return nil end
        out[i] = cmd[i]
    end
    if #out == 0 then return nil end
    return out
end

-- the terminal's own arguments before the program; each is a prefix of the final argv
local PREFIX = {
    kitty = { "kitty", "--class", "mooi-float", "-e" },
    foot = { "foot", "--app-id", "mooi-float" },
    alacritty = { "alacritty", "--class", "mooi-float", "-e" },
    wezterm = { "wezterm", "start", "--class", "mooi-float", "--" },
    ghostty = { "ghostty", "--class=mooi-float", "-e" },
    konsole = { "konsole", "-e" },
    xterm = { "xterm", "-e" },
}

-- the argv that runs a command in a terminal; nil for an unknown terminal or a bad command
function M.argv(term, cmd)
    if type(term) ~= "string" or not KNOWN[term] then return nil end
    local c = command(cmd)
    if not c then return nil end
    local out = {}
    for i, a in ipairs(PREFIX[term]) do out[i] = a end
    for i, a in ipairs(c) do out[#out + 1] = a end
    return out
end

-- the terminal to use: the preferred one when it is installed, else the first installed in ORDER
function M.pick(available, preferred)
    local have = type(available) == "table" and available or {}
    if type(preferred) == "string" and preferred ~= "" and KNOWN[preferred] and have[preferred] then return preferred end
    for _, name in ipairs(ORDER) do
        if have[name] then return name end
    end
    return nil
end

-- the argv that asks the shell which terminals are installed
function M.which_args()
    return { "sh", "-c", "command -v kitty foot alacritty wezterm ghostty konsole xterm" }
end

-- the set of terminal names found in `command -v` output (one path per installed command)
function M.parse_which(text)
    local out = {}
    if type(text) ~= "string" then return out end
    for line in text:gmatch("[^\r\n]+") do
        line = trim(line)
        local base = line:match("([^/]+)$") or line
        if KNOWN[base] then out[base] = true end
    end
    return out
end

return M
