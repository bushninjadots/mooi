-- Packages from the search line (D268; Minflair's package manager and k4's launcher, ported). Pure: what
-- `mooi pkg search` prints — `pacman -Ss` under `## repo`, the AUR helper's `-Ssa` under `## aur` — in, rows out.
-- Installing is never done here: a row's Return opens the owner's terminal on `mooi pkg install`, where the
-- password and the confirmation are theirs.

local M = {}

-- `pkg firefox`, `pkg: firefox` or `pacman firefox`: the words after, or nil when the line is not a package search
function M.query(q)
    q = tostring(q or ""):gsub("^%s+", "")
    local rest = q:match("^pkg:?%s+(.-)%s*$") or q:match("^pacman%s+(.-)%s*$") or q:match("^aur%s+(.-)%s*$")
    if rest and rest ~= "" and M.safe_query(rest) then return rest end
    return nil
end

-- what may be handed to pacman: words, never an option
function M.safe_query(s) return type(s) == "string" and #s <= 60 and s:match("^[%w][%w%s%._%+@%-]*$") ~= nil end
-- a package's name, as pacman allows it (it reaches a shell line in the terminal)
function M.safe_name(s) return type(s) == "string" and #s <= 100 and s:match("^[%w@%._%+][%w@%._%+%-]*$") ~= nil end

-- the rows: repo first, then the AUR, each in the order the tool gave (pacman sorts by repo, the helpers by
-- relevance); `installed` when the tool says so
function M.parse(text, limit, q)
    local out, source = {}, "repo"
    local pending = nil
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        local sec = line:match("^## (%a+)")
        if sec then source = sec; pending = nil
        else
            local repo, name, version, tail = line:match("^(%S+)/(%S+)%s+(%S+)%s*(.-)%s*$")
            if repo and M.safe_name(name) then
                pending = { kind = "pkg", source = source == "aur" and "aur" or "repo", repo = repo, pkg = name,
                            version = version, installed = tail:lower():find("installed", 1, true) ~= nil, desc = "" }
                out[#out + 1] = pending
            elseif pending and line:match("^%s+%S") then
                pending.desc = (line:gsub("^%s+", ""))
                pending = nil
            end
        end
    end
    -- room for the AUR's best two even when the repositories answer with dozens
    limit = limit or 5
    local repo, aur = {}, {}
    for _, r in ipairs(out) do if r.source == "aur" then aur[#aur + 1] = r else repo[#repo + 1] = r end end
    -- the package whose name is the query comes first in its list: `pkg ripgrep` is looking for ripgrep
    local exact = string.lower(tostring(q or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    local function first(list)
        for i, r in ipairs(list) do if string.lower(r.pkg) == exact then table.remove(list, i); table.insert(list, 1, r); return end end
    end
    if exact ~= "" then first(repo); first(aur) end
    local keep = math.max(0, limit - math.min(#aur, 2))
    out = {}
    for i = 1, math.min(keep, #repo) do out[#out + 1] = repo[i] end
    for i = 1, #aur do if #out < limit then out[#out + 1] = aur[i] end end
    for _, r in ipairs(out) do
        r.name = r.pkg .. (r.desc ~= "" and (" — " .. r.desc) or "")
        r.tag = (r.source == "aur" and "AUR" or string.upper(r.repo)) .. (r.installed and " · INSTALLED" or "")
    end
    return out
end

return M
