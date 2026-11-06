-- The GitHub widget's reading of `gh` (D140): a repository's card and its last commits (GraphQL),
-- its Actions runs and its commit activity (REST), and how long ago things were. Pure: the logic
-- runs `gh` and decodes; `null` is the decoder's null (json.null), which tables carry for JSON null.

local M = {}

local function val(v, null) if v == nil or v == null then return nil end; return v end

function M.repo_ok(s)
    return type(s) == "string" and s:match("^[%w%-%._]+/[%w%-%._]+$") ~= nil
end

-- "2026-11-03T17:06:19Z" as seconds since 1970 (UTC)
function M.utc(iso)
    local y, mo, d, h, mi, se = tostring(iso or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):?(%d*)")
    if not y then return nil end
    y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
    -- days from 1970 by the civil calendar (no os.time: it is local)
    local a = math.floor((14 - mo) / 12)
    local yy, mm = y + 4800 - a, mo + 12 * a - 3
    local jdn = d + math.floor((153 * mm + 2) / 5) + 365 * yy + math.floor(yy / 4) - math.floor(yy / 100) + math.floor(yy / 400) - 32045
    return (jdn - 2440588) * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + (tonumber(se) or 0)
end
function M.ago(iso, now_utc)
    local t = M.utc(iso)
    if not t or not now_utc then return "" end
    local s = math.max(0, now_utc - t)
    if s < 3600 then return math.floor(s / 60) .. " M" end
    if s < 86400 then return math.floor(s / 3600) .. " H" end
    return math.floor(s / 86400) .. " D"
end

function M.card(doc, null)
    local data = type(doc) == "table" and val(doc.data, null)
    local r = type(data) == "table" and val(data.repository, null)
    if type(r) ~= "table" then return nil end
    local lang = val(r.primaryLanguage, null)
    local out = {
        name = tostring(r.nameWithOwner or ""), desc = tostring(val(r.description, null) or ""),
        stars = tonumber(r.stargazerCount) or 0, forks = tonumber(r.forkCount) or 0,
        issues = type(r.issues) == "table" and tonumber(r.issues.totalCount) or 0,
        prs = type(r.pullRequests) == "table" and tonumber(r.pullRequests.totalCount) or 0,
        lang = type(lang) == "table" and tostring(lang.name or "") or "", pushed = tostring(r.pushedAt or ""),
        url = tostring(r.url or ""), branch = "", commits = {},
    }
    local ref = val(r.defaultBranchRef, null)
    if type(ref) == "table" then
        out.branch = tostring(ref.name or "")
        local target = val(ref.target, null)
        local hist = type(target) == "table" and val(target.history, null)
        for _, n in ipairs(type(hist) == "table" and hist.nodes or {}) do
            local a = val(n.author, null)
            local user = type(a) == "table" and val(a.user, null)
            local roll = val(n.statusCheckRollup, null)
            out.commits[#out.commits + 1] = {
                msg = tostring(n.messageHeadline or ""), when = tostring(n.committedDate or ""), sha = tostring(n.abbreviatedOid or ""):sub(1, 7),
                url = tostring(n.url or ""), who = type(user) == "table" and tostring(user.login or "") or (type(a) == "table" and tostring(a.name or "") or ""),
                state = type(roll) == "table" and tostring(roll.state or "") or "",
            }
        end
    end
    return out
end

function M.run_state(status, conclusion)
    if status ~= "completed" then return "run" end
    if conclusion == "success" then return "ok" end
    if conclusion == "failure" or conclusion == "timed_out" or conclusion == "startup_failure" then return "fail" end
    return "other"
end

function M.runs(doc, null)
    local out = {}
    local list = type(doc) == "table" and val(doc.workflow_runs, null)
    for _, r in ipairs(type(list) == "table" and list or {}) do
        out[#out + 1] = { name = tostring(r.name or ""), branch = tostring(r.head_branch or ""), when = tostring(r.updated_at or ""),
                          url = tostring(r.html_url or ""), state = M.run_state(r.status, val(r.conclusion, null)) }
    end
    return out
end

-- The last twelve weeks' commit totals; nil while GitHub is still counting (it answers 202, {})
function M.activity(weeks)
    if type(weeks) ~= "table" or #weeks == 0 then return nil end
    local out = {}
    for i = math.max(1, #weeks - 11), #weeks do out[#out + 1] = tonumber(weeks[i].total) or 0 end
    return out
end

-- The contribution calendar (GraphQL `user.contributionsCollection.contributionCalendar`): the last
-- `weeks` weeks as cells, column by column (week), Sunday first — each { lv } 0 none … 4 most, and
-- -1 for the days not yet come in the last week — and the year's total. Nil for anything else.
local LEVEL = { NONE = 0, FIRST_QUARTILE = 1, SECOND_QUARTILE = 2, THIRD_QUARTILE = 3, FOURTH_QUARTILE = 4 }
function M.heat(doc, weeks, null)
    weeks = weeks or 52
    local d = type(doc) == "table" and val(doc.data, null)
    local u = type(d) == "table" and (val(d.user, null) or val(d.viewer, null))
    local cc = type(u) == "table" and val(u.contributionsCollection, null)
    local cal = type(cc) == "table" and val(cc.contributionCalendar, null)
    if type(cal) ~= "table" or type(cal.weeks) ~= "table" then return nil end
    local list = cal.weeks
    local cells = {}
    for wi = math.max(1, #list - weeks + 1), #list do
        local days = type(list[wi].contributionDays) == "table" and list[wi].contributionDays or {}
        local by = {}
        for _, day in ipairs(days) do by[(tonumber(day.weekday) or 0) + 1] = LEVEL[day.contributionLevel] or 0 end
        for wd = 1, 7 do cells[#cells + 1] = { lv = by[wd] or -1 } end
    end
    return { total = tonumber(cal.totalContributions) or 0, cells = cells }
end

-- A link from `gh`'s output that may be handed to xdg-open (fourth pass, L11): GitHub's own web
-- pages only, https, no spaces or control characters. Anything else is nil, so nothing else opens.
function M.web_url(u)
    if type(u) ~= "string" or #u > 2048 then return nil end
    if u:find("[%c%s]") then return nil end
    if not u:match("^https://github%.com/") then return nil end
    return u
end

return M
