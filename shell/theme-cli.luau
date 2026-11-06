-- mooi theme packages from the terminal: save the current visual settings, list the saved
-- ones, and wear one. The visual allowlist and every validation rule stay in lib/themeprofiles;
-- this file is only the file/JSON edge around it. A scene has Pleamar's `json` service, plain
-- Lua 5.4 does not, so the package format's reader and writer live here rather than in a lib.
package.path = "shell/?.luau;" .. package.path

local profiles = require("lib/themeprofiles")
local settingsfile = require("lib/settingsfile")

local home = os.getenv("HOME") or ""
local data = os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")
local folder = data .. "/pleamar/mooi"
local settings_path = folder .. "/settings.json"
local themes_dir = folder .. "/themes"

-- ── JSON ────────────────────────────────────────────────────────────────────
-- Objects, arrays, strings, numbers, true/false/null: the whole package format. Surrogate
-- pairs are joined so a theme name in any script survives the round trip.
local function decode_json(text)
    local i, n = 1, #text
    local parse_value

    local function fail(msg) error({ json = msg }, 0) end
    local function skip()
        while true do
            local c = text:sub(i, i)
            if c == " " or c == "\n" or c == "\r" or c == "\t" then i = i + 1 else return end
        end
    end

    local function parse_string()
        i = i + 1
        local out = {}
        while i <= n do
            local c = text:sub(i, i)
            if c == '"' then
                i = i + 1
                return table.concat(out)
            elseif c == "\\" then
                local e = text:sub(i + 1, i + 1)
                i = i + 2
                local named = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                if named[e] then
                    out[#out + 1] = named[e]
                elseif e == "u" then
                    local cp = tonumber(text:sub(i, i + 3), 16)
                    if not cp then fail("bad \\u escape") end
                    i = i + 4
                    if cp >= 0xD800 and cp <= 0xDBFF and text:sub(i, i) == "\\" and text:sub(i + 1, i + 1) == "u" then
                        local lo = tonumber(text:sub(i + 2, i + 5), 16)
                        if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                            i = i + 6
                        end
                    end
                    out[#out + 1] = utf8.char(cp)
                else
                    fail("bad escape in a string")
                end
            elseif c:byte() < 0x20 then
                fail("control character in a string")
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        fail("unterminated string")
    end

    local function parse_array()
        i = i + 1
        local out = {}
        skip()
        if text:sub(i, i) == "]" then i = i + 1; return out end
        while true do
            out[#out + 1] = parse_value()
            skip()
            local c = text:sub(i, i)
            i = i + 1
            if c == "]" then return out elseif c ~= "," then fail("expected ',' or ']'") end
        end
    end

    local function parse_object()
        i = i + 1
        local out = {}
        skip()
        if text:sub(i, i) == "}" then i = i + 1; return out end
        while true do
            skip()
            if text:sub(i, i) ~= '"' then fail("expected a key") end
            local key = parse_string()
            skip()
            if text:sub(i, i) ~= ":" then fail("expected ':'") end
            i = i + 1
            out[key] = parse_value()
            skip()
            local c = text:sub(i, i)
            i = i + 1
            if c == "}" then return out elseif c ~= "," then fail("expected ',' or '}'") end
        end
    end

    parse_value = function()
        skip()
        local c = text:sub(i, i)
        if c == "{" then return parse_object() end
        if c == "[" then return parse_array() end
        if c == '"' then return parse_string() end
        if text:sub(i, i + 3) == "true" then i = i + 4; return true end
        if text:sub(i, i + 4) == "false" then i = i + 5; return false end
        if text:sub(i, i + 3) == "null" then i = i + 4; return nil end
        local s, e = text:find("^-?%d+%.?%d*[eE][+-]?%d+", i)
        if not s then s, e = text:find("^-?%d+%.?%d*", i) end
        if s then
            i = e + 1
            return tonumber(text:sub(s, e))
        end
        fail("unexpected character")
    end

    local ok, value = pcall(parse_value)
    if not ok then
        return nil, type(value) == "table" and value.json or tostring(value)
    end
    skip()
    if i <= n then return nil, "trailing characters after the document" end
    return value
end

local function encode_json(value)
    local function scalar(v)
        local t = type(v)
        if t == "string" then
            return '"' .. v:gsub('[%c"\\]', function(c)
                local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
                                ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
                return named[c] or string.format("\\u%04x", c:byte())
            end) .. '"'
        elseif t == "boolean" then
            return v and "true" or "false"
        elseif t == "number" then
            if math.type(v) == "integer" then return tostring(v) end
            return string.format("%.14g", v)
        elseif t == "nil" then
            return "null"
        end
        return '"' .. tostring(v) .. '"'
    end

    local function is_array(t)
        local n = #t
        if n == 0 then return false end
        for k in pairs(t) do
            if math.type(k) ~= "integer" or k < 1 or k > n then return false end
        end
        return true
    end

    local function walk(v, depth)
        local t = type(v)
        if t ~= "table" then return scalar(v) end
        local pad = string.rep("  ", depth)
        local inner = pad .. "  "
        if is_array(v) then
            local parts = {}
            for idx = 1, #v do parts[#parts + 1] = inner .. walk(v[idx], depth + 1) end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
        end
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" then keys[#keys + 1] = k end
        end
        table.sort(keys)
        if #keys == 0 then return "{}" end
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = inner .. scalar(k) .. ": " .. walk(v[k], depth + 1)
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
    end

    return walk(value, 0)
end

-- ── files ───────────────────────────────────────────────────────────────────
local function shq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function read_text(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("a")
    f:close()
    return text
end

local function mkdirs(path)
    local ok = os.execute("mkdir -p " .. shq(path))
    return ok == true or ok == 0
end

local seq = 0
local function write_atomic(path, text)
    seq = seq + 1
    local tmp = path .. ".tmp." .. tostring(os.time()) .. "." .. tostring(seq)
    local f, err = io.open(tmp, "wb")
    if not f then return nil, err end
    local ok, werr = f:write(text)
    f:close()
    if not ok then os.remove(tmp); return nil, werr end
    local moved, rerr = os.rename(tmp, path)
    if not moved then os.remove(tmp); return nil, rerr end
    return true
end

local function slug(name)
    local s = name:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    s = s:sub(1, 48):gsub("%-+$", "")
    return s
end

local function load_settings()
    local text = read_text(settings_path)
    if not text then return nil, "no settings.json yet; start mooi once first (" .. settings_path .. ")" end
    local doc, err = decode_json(text)
    if type(doc) ~= "table" then return nil, "settings.json is not a JSON object (" .. tostring(err or "read as something else") .. ")" end
    return doc
end

local function count_leaves(t)
    if type(t) ~= "table" then return 1 end
    local n = 0
    for _, v in pairs(t) do n = n + count_leaves(v) end
    return n
end

local function fail(msg)
    io.stderr:write("mooi theme: " .. msg .. "\n")
    os.exit(1)
end

local function usage()
    io.stderr:write("usage: mooi theme save <name> [description] [--force]\n"
        .. "       mooi theme list\n"
        .. "       mooi theme apply <name|file>\n")
    os.exit(2)
end

-- ── commands ────────────────────────────────────────────────────────────────
local function cmd_save(args)
    local force, rest = false, {}
    for _, a in ipairs(args) do
        if a == "--force" then force = true else rest[#rest + 1] = a end
    end
    local name = rest[1]
    if not name then usage() end
    local description = #rest > 1 and table.concat(rest, " ", 2) or ""

    local doc, why = load_settings()
    if not doc then fail(why) end
    local package, perr = profiles.capture(doc, name, description)
    if not package then fail("not saved: " .. perr) end
    local id = slug(name)
    if id == "" then fail("not saved: a name needs a letter or a digit") end
    if not mkdirs(themes_dir) then fail("could not make " .. themes_dir) end

    local path = themes_dir .. "/" .. id .. ".json"
    if not force and read_text(path) then
        fail("'" .. id .. "' already exists; use --force to replace it")
    end
    local written, werr = write_atomic(path, encode_json(package) .. "\n")
    if not written then fail("could not write " .. path .. ": " .. tostring(werr)) end
    print("theme saved: " .. package.name .. " -> " .. path)
    print("  " .. count_leaves(package.settings) .. " visual settings, " .. package.format .. " v" .. tostring(package.version))
end

local function cmd_list()
    local pipe = io.popen("find " .. shq(themes_dir) .. " -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort")
    if not pipe then fail("could not read " .. themes_dir) end
    local found = 0
    for path in pipe:lines() do
        found = found + 1
        local id = path:match("([^/]+)%.json$") or path
        local text = read_text(path)
        local doc, derr
        if text then doc, derr = decode_json(text) else derr = "cannot be read" end
        local package, perr = nil, derr
        if doc then package, perr = profiles.validate(doc) end
        if package then
            local line = string.format("  %-16s %s", id, package.name)
            if package.description ~= "" then line = line .. " - " .. package.description end
            print(line)
        else
            print("  " .. id .. "  INVALID: " .. tostring(perr))
        end
    end
    pipe:close()
    if found == 0 then
        print("no theme packages yet; save one with: mooi theme save <name>")
    end
end

local function cmd_apply(args)
    local asked = args[1]
    if not asked then usage() end
    local path = asked
    if path:sub(1, 2) == "~/" then path = home .. path:sub(2) end
    if not (path:find("/", 1, true) or path:sub(-5) == ".json") then
        path = themes_dir .. "/" .. slug(asked) .. ".json"
    end
    local text = read_text(path)
    if not text then fail("no package at " .. path) end
    local raw, derr = decode_json(text)
    if not raw then fail("package is not valid JSON: " .. tostring(derr)) end

    if os.getenv("MOOI_SAFE") == "1" then fail("settings are disabled in safe mode") end

    local current, cerr = load_settings()
    if not current then fail(cerr) end
    local applied, perr = profiles.apply(current, raw)
    if not applied then fail("not applied: " .. perr) end

    -- Read-merge-write: re-read the file as it is now and lay only the package's own leaves
    -- over it, so a change another program made while this ran is kept (lib/settingsfile).
    local fresh_text = read_text(settings_path)
    local fresh = fresh_text and decode_json(fresh_text) or nil
    if type(fresh) ~= "table" then fail("settings.json changed and could not be read; nothing was written") end
    local changes = settingsfile.changes(current, applied)
    settingsfile.merge(fresh, changes)
    local written, werr = write_atomic(settings_path, encode_json(fresh) .. "\n")
    if not written then fail("could not write settings.json: " .. tostring(werr)) end

    print("theme applied: " .. raw.name .. " (" .. #changes .. " settings) -> " .. settings_path)
    print("  a running mooi reads settings.json and applies it as it is written")
end

local cmd = arg[1]
local args = {}
for i = 2, #arg do args[#args + 1] = arg[i] end

if cmd == "save" then
    cmd_save(args)
elseif cmd == "list" then
    cmd_list()
elseif cmd == "apply" then
    cmd_apply(args)
else
    usage()
end
