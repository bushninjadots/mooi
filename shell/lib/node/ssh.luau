-- SSH hosts for the search line (D268; k4's SSH launcher, ported). Pure: ~/.ssh/config's text in, the hosts a
-- query matches out. Only plain names become rows — a pattern (`*`, `?`, `!`) is a rule for many hosts, not one to
-- connect to — and only names made of the characters a host alias can have, since the name reaches a shell
-- line (`ssh NAME` in the owner's terminal, through Hyprland's exec).

local M = {}
local CMD = require("lib/node/commands")

function M.safe(name) return type(name) == "string" and name:match("^[%w][%w%._%-]*$") ~= nil and #name <= 64 end

-- every Host line's names, in the file's order, each once; `HostName` lines are where they go, kept as detail
function M.hosts(text)
    local out, seen, last = {}, {}, {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\r?\n") do
        local key, rest = line:match("^%s*(%a+)%s*=?%s*(.-)%s*$")
        key = key and string.lower(key)
        if key == "host" then
            last = {}
            for name in rest:gmatch("%S+") do
                if M.safe(name) and not seen[name] then
                    seen[name] = true
                    local h = { name = name, to = "" }
                    out[#out + 1] = h; last[#last + 1] = h
                end
            end
        elseif key == "hostname" then
            for _, h in ipairs(last) do h.to = rest end
        elseif key == "match" then
            last = {}
        end
    end
    return out
end

-- the hosts a query matches, best first, as search rows; `ssh` alone (or `ssh `) lists them all
function M.match(hosts, q, limit)
    q = tostring(q or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local all = q == "ssh" or q:match("^ssh%s*$") ~= nil
    local want = q:match("^ssh%s+(.+)$") or q
    local out = {}
    for i, h in ipairs(type(hosts) == "table" and hosts or {}) do
        local s = all and 2 or math.max(CMD.score(want, h.name, h.to), CMD.score(q, "ssh " .. h.name, ""))
        if s > 0 then out[#out + 1] = { kind = "ssh", name = "ssh " .. h.name, host = h.name, detail = h.to, score = s, order = i } end
    end
    table.sort(out, function(a, b) if a.score ~= b.score then return a.score > b.score end; return a.order < b.order end)
    while #out > (limit or 2) do table.remove(out) end
    return out
end

return M
