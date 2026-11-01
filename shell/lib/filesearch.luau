-- The Overview's file results (OVERVIEW-PORT stage 2): a bounded `find` over the folders people
-- keep things in. Pure argument building and output reading, so tests/unit can run it without
-- touching the disk.
--
-- The query is a literal: `*`, `?`, `[` and `\` are escaped before they reach `-iname`, so a name
-- typed into the search can never become a pattern of its own. `-exec` is never built here.

local M = {}

M.LIMIT = 4
M.DEPTH = 3
M.FOLDERS = { "Desktop", "Documents", "Downloads", "Pictures", "Videos", "Music" }
M.SKIP = { "/.git/", "/node_modules/", "/.cache/", "/.local/share/Trash/" }

-- A literal `-iname` fragment.
function M.escaped(q)
    local s = tostring(q or "")
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, "([%*%?%[%]])", "\\%1")
    return s
end

-- The folders searched under `home`; the working directory when there is no home.
function M.roots(home)
    home = tostring(home or "")
    if home == "" then return { "." } end
    local out = {}
    for _, name in ipairs(M.FOLDERS) do out[#out + 1] = home .. "/" .. name end
    return out
end

-- `find`'s arguments for `query`: the folders, then one bounded expression. A missing folder is
-- reported by find but does not stop the others.
function M.args(home, query)
    local a = M.roots(home)
    for _, v in ipairs({
        "-maxdepth", tostring(M.DEPTH), "-type", "f",
        "-iname", "*" .. M.escaped(query) .. "*",
        "-not", "-path", "*/.*",
    }) do
        a[#a + 1] = v
    end
    return a
end

-- The first `limit` absolute paths in find's output, without hidden paths, duplicates or the
-- folders that only hold machinery. Each row is { path, name }.
function M.parse(out, limit)
    limit = math.max(1, tonumber(limit) or M.LIMIT)
    local rows, seen = {}, {}
    for line in string.gmatch(tostring(out or ""), "[^\n]+") do
        if string.sub(line, 1, 1) == "/" and not seen[line] then
            local skip = false
            for _, part in ipairs(M.SKIP) do
                if string.find(line, part, 1, true) then skip = true; break end
            end
            if not skip then
                -- any hidden path component stays out, wherever it sits
                for part in string.gmatch(line, "/([^/]+)") do
                    if string.sub(part, 1, 1) == "." then skip = true; break end
                end
            end
            if not skip then
                seen[line] = true
                rows[#rows + 1] = { path = line, name = string.match(line, "([^/]+)$") or line }
                if #rows >= limit then break end
            end
        end
    end
    return rows
end

return M
