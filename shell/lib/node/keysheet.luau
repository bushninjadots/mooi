-- The shortcut sheet (D267; k4's and Minflair's Super+K, ported). Pure: Hyprland's binds as `hyprctl binds -j`
-- gives them, and the words for them, become rows of keys and what they do.
--
-- Hyprland 0.57's Lua config hides what a bind runs (its `arg` is a number), so the words come from the config's
-- own text: the `--- what it does` comment above an `hl.bind(…)` (the house style of bind.lua), a trailing comment
-- on a `{ "KEYS", "command" }` row (mooi's custom/mooi.lua), or mooi's own name for a `mooi` command. What is
-- bound is always Hyprland's answer, never the files' — a file can say what is no longer true.

local M = {}

-- Hyprland's modifier bits, in the order people say them
local MODS = { { 64, "Super" }, { 4, "Ctrl" }, { 8, "Alt" }, { 1, "Shift" }, { 128, "Mod5" }, { 32, "Mod3" } }
local BIT = { SUPER = 64, MOD4 = 64, WIN = 64, LOGO = 64, CTRL = 4, CONTROL = 4, ALT = 8, MOD1 = 8, SHIFT = 1,
              MOD5 = 128, MOD3 = 32 }

local KEYS = {
    RETURN = "Return", SPACE = "Space", TAB = "Tab", ESCAPE = "Esc", PRINT = "Print", DELETE = "Delete",
    BACKSPACE = "Backspace", COMMA = ",", PERIOD = ".", SLASH = "/", MINUS = "-", EQUAL = "=", GRAVE = "`",
    SUPER_L = "Super", SUPER_R = "Super", LEFT = "←", RIGHT = "→", UP = "↑", DOWN = "↓",
    ["MOUSE:272"] = "Left button", ["MOUSE:273"] = "Right button", ["MOUSE:274"] = "Middle button",
    MOUSE_DOWN = "Wheel down", MOUSE_UP = "Wheel up",
    XF86AUDIORAISEVOLUME = "Volume up", XF86AUDIOLOWERVOLUME = "Volume down", XF86AUDIOMUTE = "Mute",
    XF86AUDIOMICMUTE = "Mic mute", XF86AUDIOPLAY = "Play", XF86AUDIOPAUSE = "Pause", XF86AUDIONEXT = "Next track",
    XF86AUDIOPREV = "Previous track", XF86AUDIOSTOP = "Stop", XF86MONBRIGHTNESSUP = "Brightness up",
    XF86MONBRIGHTNESSDOWN = "Brightness down", CAPS_LOCK = "Caps Lock", NUM_LOCK = "Num Lock",
    KP_END = "Pad 1", KP_DOWN = "Pad 2", KP_NEXT = "Pad 3", KP_LEFT = "Pad 4", KP_BEGIN = "Pad 5",
    KP_RIGHT = "Pad 6", KP_HOME = "Pad 7", KP_UP = "Pad 8", KP_PRIOR = "Pad 9", KP_INSERT = "Pad 0",
}

-- whether a modifier's bit is set. Arithmetic, not `&`: Luau (what Pleamar runs) has no bitwise operators, and Lua
-- 5.4 (what the unit suite runs) has no bit32, so only this reads the same in both
local function has(mask, bit) return (mask // bit) % 2 == 1 end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function M.mods(mask)
    mask = math.floor(tonumber(mask) or 0)
    local out = {}
    for _, m in ipairs(MODS) do if has(mask, m[1]) then out[#out + 1] = m[2] end end
    return out
end

function M.keyname(key)
    key = trim(key)
    local k = KEYS[string.upper(key)]
    if k then return k end
    if #key == 1 then return string.upper(key) end
    return key
end

-- how a bind is written for people: "Super + Shift + S"
function M.label(mask, key)
    if string.upper(trim(key)):match("^SUPER_[LR]$") then return "Super (alone)" end
    local parts = M.mods(mask)
    parts[#parts + 1] = M.keyname(key)
    return table.concat(parts, " + ")
end

-- the one form both sides are compared in: "65:S" (the key in upper case; `*` for a loop's variable)
function M.id(mask, key) return math.floor(tonumber(mask) or 0) .. ":" .. string.upper(trim(key)) end

-- "SUPER + SHIFT + q" (as a bind is written in the config) as that same id, or nil if it is not a key
function M.parse(combo)
    combo = trim(combo)
    if combo == "" then return nil end
    local mask, key = 0, nil
    for part in (combo .. "+"):gmatch("(.-)%+") do
        part = trim(part)
        if part ~= "" then
            local bit = BIT[string.upper(part)]
            if bit and key == nil then if not has(mask, bit) then mask = mask + bit end
            elseif key == nil then key = part
            else key = key .. "+" .. part end   -- "mouse:272" has no plus; anything left is the key
        end
    end
    if not key then return nil end
    return M.id(mask, key)
end

-- a bind's first argument as written in Lua (`mainMod .. " + SHIFT + " .. key`) as the combo it makes: strings as
-- they are, the modifier variables as SUPER, any other name as `*` (a loop's key)
local MODVARS = { mainmod = "SUPER", mod = "SUPER", modkey = "SUPER", super = "SUPER" }
function M.combo_of(expr)
    local out = {}
    for piece in (tostring(expr or "") .. ".."):gmatch("(.-)%.%.") do
        piece = trim(piece)
        local str = piece:match('^"(.*)"$') or piece:match("^'(.*)'$")
        if str then out[#out + 1] = str
        elseif piece:match("^[%a_][%w_]*$") then out[#out + 1] = MODVARS[string.lower(piece)] or "*"
        elseif piece ~= "" then return nil end
    end
    return table.concat(out)
end

-- the words a config's text gives its binds: { id = what }, later files and lines winning (as Hyprland's own
-- unbind-then-bind does). `cmdname` names a `mooi` command ("walls" → "Wallpapers"); it is used where a row of
-- `{ "KEYS", "command" }` has no comment of its own.
-- a comment's words as a row says them: no parenthesis after them, one capital (bind.lua writes "switch Workspace")
local function said(s)
    s = trim(tostring(s or ""):gsub("%s*%b()%s*$", ""))
    return (s:gsub(" (%u)(%l)", function(a, b) return " " .. string.lower(a) .. b end))
end
function M.words(text, cmdname, into)
    local out = into or {}
    -- the `---` comment above a bind names it, and every bind after it until a blank line or the next comment
    -- (bind.lua's "volume up" covers the XF86 key and its Alt fallback); a block's first line is what it does
    local pending, in_doc = nil, false
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        local doc = line:match("^%s*%-%-%-+%s*(.-)%s*$")
        if doc and doc ~= "" then
            if not in_doc then pending = said(doc) end
            in_doc = true
        else
            in_doc = false
            -- a blank line, a plain comment or a new block of code ends what the comment above named
            if line:match("^%s*$") or line:match("^%s*%-%-") or line:match("^%s*end%f[%W]") or line:match("^%s*local%f[%W]")
                or line:match("^%s*for%f[%W]") or line:match("^%s*if%f[%W]") then pending = nil end
            local args = line:match("hl%.bind%((.*)") or line:match("pcall%(%s*hl%.bind%s*,%s*(.*)")
            if args then
                local first = args:match('^%s*(".-")%s*,') or args:match("^%s*([^,]+),")
                local combo = first and M.combo_of(first)
                local id = combo and M.parse(combo)
                local trailing = line:match("%-%-%s*(.-)%s*$")
                local mcmd = line:match('mooi%s*%.%.%s*"%s*([%w%-]+[%w%- ]*)"')
                local what = pending or (trailing and said(trailing)) or (mcmd and cmdname and cmdname(trim(mcmd)))
                if id and what and what ~= "" then out[id] = what end
            end
            local keys, cmd = line:match('{%s*"([^"]+)"%s*,%s*"([^"]+)"%s*}')
            if keys and not args then
                local id = M.parse(keys)
                local trailing = line:match("}%s*,?%s*%-%-%s*(.-)%s*$")
                if trailing then trailing = trailing:match("^(.-)[:(]") or trailing end
                local what = (cmdname and cmdname(cmd)) or (trailing and trim(trailing) ~= "" and said(trailing))
                if id and what then out[id] = what end
            end
        end
    end
    return out
end

local function cap(s) s = trim(s); return (s:gsub("^%l", string.upper)) end

-- a bind no comment names, said as well as Hyprland lets us: the dispatcher, and the workspace a digit means
local GUESS = { close = "Close the window", kill = "Kill the window", fullscreen = "Fullscreen", pin = "Pin the window",
                drag = "Move the window", resize = "Resize the window", toggle_special = "The special workspace",
                exec_cmd = "Runs a command", float = "Float the window", pseudo = "Pseudo-tile" }
local function guess(b)
    local d = tostring(b.dispatcher or ""):match("%((.-)%)") or tostring(b.dispatcher or "")
    local key = M.keyname(b.key)
    local n = key:match("^%d$") or key:match("^Pad (%d)$")
    if n and (d == "focus" or d == "workspace") then return "Workspace " .. (n == "0" and "10" or n) end
    if n and d == "move" then return "Window to workspace " .. (n == "0" and "10" or n) end
    if d == "focus" and key:match("^[←→↑↓]$") then return "Focus " .. key end
    if d == "move" and key:match("^[←→↑↓]$") then return "Move the window " .. key end
    return GUESS[d] or cap(d:gsub("_", " "))
end

-- mooi's own commands, named as Settings → Keys names them (`actions` is lib/desktop's ACTIONS) and the few bound
-- outside that list (custom/mooi.lua, bind.lua): what `mooi CMD` does, for a bind with no comment of its own
local MOOI = {
    walls = "Wallpapers", toggle = "Search and apps", clipboard = "Clipboard history", record = "Record the screen",
    ["record area"] = "Record an area", session = "Restart mooi", bury = "Bury the window under the wallpaper",
    ["shutter-here"] = "Window shutter, under the pointer", ["wheel 1"] = "Next workspace", ["wheel -1"] = "Previous workspace",
    ["reveal up"] = "Wake the Pill (Super alone)", ["reveal down"] = "Hold Super: look under the windows",
    ["osd caps"] = "Shows Caps Lock", ["osd num"] = "Shows Num Lock", ["node keys"] = "The Pill: shortcuts",
    ["game-mode"] = "Game mode", system = "System controls", settings = "Settings", lock = "Lock screen",
}
function M.mooi_name(cmd, actions)
    cmd = trim(cmd)
    for _, a in ipairs(type(actions) == "table" and actions or {}) do if a.cmd == cmd then return a.name end end
    return MOOI[cmd]
end

-- the rows: every bind Hyprland holds, its keys and what it does, in the order people look for them —
-- Super's first, then by key. `words` from M.words.
function M.rows(binds, words)
    words = words or {}
    local out, seen = {}, {}
    for _, b in ipairs(type(binds) == "table" and binds or {}) do
        if type(b) == "table" and b.key and tostring(b.key) ~= "" then
            local id = M.id(b.modmask, b.key)
            if not seen[id] then
                seen[id] = true
                local key = M.keyname(b.key)
                local loop = (key:match("^%d$") or key:match("^Pad %d$")) and words[M.id(b.modmask, "*")]
                -- a mouse bind that drags or resizes is what Hyprland says it is, whatever a comment claims
                local d = tostring(b.dispatcher or "")
                local hand = tostring(b.key):match("^mouse:") and (d:find("drag", 1, true) or d:find("resize", 1, true))
                local what = (b.has_description and trim(b.description) ~= "" and trim(b.description))
                    or (not hand and words[id]) or (loop and (loop:gsub("%[key%]", key))) or guess(b)
                if tostring(b.submap or "") ~= "" then what = what .. " (in " .. b.submap .. ")" end
                out[#out + 1] = { keys = M.label(b.modmask, b.key), what = cap(what), mask = tonumber(b.modmask) or 0,
                                  key = string.upper(tostring(b.key)) }
            end
        end
    end
    -- what people look up first: Super's keys, then the rest, then the thirty-odd workspace numbers (a pattern
    -- learned once, which would otherwise fill the first screens)
    local function rank(r)
        if r.key:match("^%d$") or r.key:match("^KP_") then return 2 end
        return has(r.mask, 64) and 0 or 1
    end
    table.sort(out, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        if a.key ~= b.key then return a.key < b.key end
        return a.mask < b.mask
    end)
    return out
end

-- the rows a filter leaves: every word of it in the keys or the words
function M.filter(rows, q)
    q = string.lower(trim(q))
    if q == "" then return rows end
    local out = {}
    for _, r in ipairs(rows) do
        local hay = string.lower(r.keys .. " " .. r.what)
        local all = true
        for w in q:gmatch("%S+") do if not hay:find(w, 1, true) then all = false; break end end
        if all then out[#out + 1] = r end
    end
    return out
end

return M
