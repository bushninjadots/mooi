-- The side drawers (D275; Minflair's Convex panels, ported): a Dashboard out of the frame's left edge and the
-- notices out of its right. Pure: GitHub's answer, the bar's feeds and the day in; what the drawers show out.

local M = {}

M.W = 380                       -- a drawer's width
M.H = { left = 640, right = 520 } -- and height
M.WEEKS = 26                    -- the contributions grid: half a year, a column a week

local function str(v) if v == nil or (type(json) == "table" and v == json.null) then return "" end; return tostring(v) end

-- the GitHub card from `gh api graphql`'s viewer (see QUERY): name, login, the four numbers, the top repository
M.QUERY = [[query { viewer { login name bio avatarUrl followers { totalCount }
  repositories(first: 20, ownerAffiliations: OWNER, orderBy: { field: PUSHED_AT, direction: DESC }) {
    totalCount nodes { name description stargazerCount forkCount primaryLanguage { name } } }
  contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { contributionCount } } } } } }]]

function M.github(viewer)
    if type(viewer) ~= "table" or type(viewer.login) ~= "string" then return nil end
    local repos = type(viewer.repositories) == "table" and viewer.repositories or {}
    local nodes = type(repos.nodes) == "table" and repos.nodes or {}
    local stars, top = 0, nil
    for _, r in ipairs(nodes) do
        if type(r) == "table" then
            local s = tonumber(r.stargazerCount) or 0
            stars = stars + s
            if not top or s > (tonumber(top.stargazerCount) or 0) then top = r end
        end
    end
    local cal = type(viewer.contributionsCollection) == "table" and viewer.contributionsCollection.contributionCalendar or {}
    local name = str(viewer.name)
    local lang = top and type(top.primaryLanguage) == "table" and str(top.primaryLanguage.name) or ""
    return {
        login = viewer.login, name = name ~= "" and name or viewer.login, bio = str(viewer.bio),
        avatar = type(viewer.avatarUrl) == "string" and viewer.avatarUrl or "",
        contributions = tonumber(type(cal) == "table" and cal.totalContributions) or 0,
        repos = tonumber(repos.totalCount) or 0,
        followers = tonumber(type(viewer.followers) == "table" and viewer.followers.totalCount) or 0,
        stars = stars,
        top = top and { name = str(top.name), desc = str(top.description), stars = tonumber(top.stargazerCount) or 0,
                        forks = tonumber(top.forkCount) or 0, lang = lang } or nil,
    }
end

-- the grid: the last WEEKS weeks of days as levels 0 (none) … 4 (the busiest quarter), in column order (a week
-- top to bottom, Sunday first, as GitHub draws it); a missing day is level 0
function M.heat(viewer, weeks)
    weeks = weeks or M.WEEKS
    local cal = type(viewer) == "table" and type(viewer.contributionsCollection) == "table"
        and viewer.contributionsCollection.contributionCalendar or nil
    local all = type(cal) == "table" and type(cal.weeks) == "table" and cal.weeks or {}
    local days = {}
    for i = math.max(1, #all - weeks + 1), #all do
        local w = all[i]
        local d = type(w) == "table" and type(w.contributionDays) == "table" and w.contributionDays or {}
        for k = 1, 7 do days[#days + 1] = tonumber(type(d[k]) == "table" and d[k].contributionCount) or 0 end
    end
    local top = 0
    for _, v in ipairs(days) do if v > top then top = v end end
    local out = {}
    for i, v in ipairs(days) do
        out[i] = { v = (v == 0 or top == 0) and 0 or math.max(1, math.min(4, math.ceil(v / top * 4))) }
    end
    return out
end

-- the bar's updates.json as the drawer says it
function M.updates(doc)
    local n = tonumber(type(doc) == "table" and doc.total) or nil
    if not n then return "Not checked yet", 0 end
    if n == 0 then return "Up to date", 0 end
    return n .. (n == 1 and " update waiting" or " updates waiting"), n
end

-- D278: mooi's own state (self.json from `mooi self-check`): the line, whether an update can be brought in, and
-- whether it is time to ask again (every six hours)
function M.self_line(doc, now)
    if type(doc) ~= "table" then return "mooi · not checked yet", false, true end
    local behind, head = tonumber(doc.behind) or 0, tostring(doc.head or "")
    local stale = (tonumber(now) or 0) - (tonumber(doc.at) or 0) > 6 * 3600
    if behind > 0 and doc.dirty == true then return "mooi · " .. behind .. " new · your changes first", false, stale end
    if behind > 0 then return "mooi · " .. behind .. (behind == 1 and " new commit" or " new commits"), true, stale end
    return "mooi " .. head .. " · up to date", false, stale
end

-- a quote for the day: one of a short list of old public-domain lines, the same all day
M.QUOTES = {
    { "Well begun is half done.", "Aristotle" },
    { "The secret of getting ahead is getting started.", "Mark Twain" },
    { "Simplicity is the ultimate sophistication.", "Leonardo da Vinci" },
    { "It does not matter how slowly you go as long as you do not stop.", "Confucius" },
    { "Little by little, one travels far.", "J. R. R. Tolkien" },
    { "What we think, we become.", "Buddha" },
    { "Patience is bitter, but its fruit is sweet.", "Jean-Jacques Rousseau" },
    { "Energy and persistence conquer all things.", "Benjamin Franklin" },
    { "The best way out is always through.", "Robert Frost" },
    { "Knowing is not enough; we must apply.", "Johann Wolfgang von Goethe" },
}
function M.quote(t)
    local day = math.floor((tonumber(t) or 0) / 86400)
    local q = M.QUOTES[day % #M.QUOTES + 1]
    return q[1], q[2]
end

-- the notices' rows from the bar's nexus-feed.json: the app, the title, the body's start and when; and how many
-- there are in all (the feed carries the newest five)
function M.notices(feed)
    local items = type(feed) == "table" and type(feed.items) == "table" and feed.items or {}
    local rows = {}
    for i, n in ipairs(items) do
        if i > 5 then break end
        if type(n) == "table" then
            local body = str(n.body):gsub("%s+", " ")
            rows[#rows + 1] = { app = string.upper(str(n.app) ~= "" and str(n.app) or "mooi"), title = str(n.title),
                                body = body, ago = str(n.ago), act = type(n.actions) == "table" and str(n.actions[1]) or "" }
        end
    end
    return rows, tonumber(type(feed) == "table" and feed.count) or #rows
end

-- a big number, short: 1234 → "1.2k"
function M.short(n)
    n = tonumber(n) or 0
    if n >= 10000 then return string.format("%dk", math.floor(n / 1000)) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

return M
