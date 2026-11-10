-- The side drawers (D275; Minflair's Convex panels, ported): the logic. The Dashboard out of the left side (GitHub
-- through `gh`, the bar's updates.json, a quote for the day) and the notices out of the right (the bar's
-- nexus-feed.json: only the bar may receive notifications, so the drawer reads its feed and asks the bar to act).
-- Nothing is asked while both are shut; GitHub is asked when the Dashboard opens, at most every five minutes.

local config = require("lib/config")
local ferro = require("lib/ferro")
local DR = require("lib/drawers")

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind) else ok, v = pcall(sys.ask, "files.read", name) end
    if ok then return v end
end

D = { settings = config.parse(read("settings.json"), json.decode), gh_at = -1e9, login = nil, scr_h = 1080, open = 0 }

local function cfg() local d = D.settings.drawers; return type(d) == "table" and d or {} end

-- ── the palette, as every program wearing Ferrolume paints it ──
local palette = read("palette.json", "json")
local function paint()
    local s = D.settings
    local out = ferro.resolve(s.theme.source, palette, s.theme.signal, false, ferro.options(s))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
end
paint()
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)

-- ── what Settings says: each drawer on or off, the sides' touch, the Dashboard's parts ──
local function apply()
    local c = cfg()
    fact.dr_lon = c.dashboard ~= false
    fact.dr_ron = c.notices ~= false
    fact.dr_edge = c.edge == true
    fact.dr_github = c.github ~= false
    fact.dr_quote_on = c.quote ~= false
    local n = type(D.settings.notifications) == "table" and D.settings.notifications or {}
    fact.dr_silent = n.dnd ~= nil and n.dnd ~= "off"
end
apply()
pcall(sys.watch, "files:settings.json", function()
    D.settings = config.parse(read("settings.json"), json.decode)
    paint(); apply()
end)

-- the drawers stand centred on the screen's height
run("hyprctl", { "-j", "monitors" }, function(out)
    local ok, mons = pcall(json.decode, out or "")
    for _, m in ipairs(ok and type(mons) == "table" and mons or {}) do
        if m.focused then D.scr_h = (tonumber(m.height) or 1080) / (tonumber(m.scale) or 1) end
    end
    fact.dr_top = math.max(40, math.floor((D.scr_h - DR.H.left) / 2))
    fact.dr_rtop = math.max(40, math.floor((D.scr_h - DR.H.right) / 2))
end)

-- ── the Dashboard ──
local function github()
    if cfg().github == false then return end
    if os.time() - D.gh_at < 300 then return end
    D.gh_at = os.time()
    run("gh", { "api", "graphql", "-f", "query=" .. DR.QUERY }, function(out, code)
        local ok, doc = pcall(json.decode, out or "")
        local v = ok and type(doc) == "table" and type(doc.data) == "table" and doc.data.viewer or nil
        local g = DR.github(v)
        if not g then
            fact.dr_gh = false
            text.dr_ghmsg = code == 127 and "Install the GitHub CLI (gh) and run `gh auth login`"
                or "GitHub did not answer — is `gh auth status` signed in?"
            D.gh_at = -1e9   -- ask again next time it opens
            return
        end
        D.login = g.login
        text.dr_name, text.dr_login, text.dr_bio = g.name, "@" .. g.login, g.bio
        text.dr_n1, text.dr_n2, text.dr_n3, text.dr_n4 = DR.short(g.contributions), DR.short(g.repos), DR.short(g.followers), DR.short(g.stars)
        fact.dr_top_on = g.top ~= nil
        if g.top then
            text.dr_tname, text.dr_tdesc = g.top.name, g.top.desc ~= "" and g.top.desc or "No description"
            text.dr_tmeta = (g.top.lang ~= "" and (string.upper(g.top.lang) .. " · ") or "") .. "★ " .. g.top.stars
        end
        model.hm = DR.heat(v, DR.WEEKS)
        fact.dr_gh = true
        -- the avatar, kept beside mooi's other files (the drawers' folder is mooi's)
        if g.avatar:match("^https://avatars%.githubusercontent%.com/") then
            local ok2, folder = pcall(sys.ask, "files.folder")
            if ok2 and type(folder) == "string" then
                local dest = folder .. "/drawers-avatar.img"
                run("curl", { "-fsSL", "--max-time", "8", "-o", dest, g.avatar }, function(_, c2)
                    if c2 == 0 then text.dr_av = dest; fact.dr_avon = true end
                end)
            end
        end
    end)
end
local function dashboard()
    local upd, n = DR.updates(read("updates.json", "json"))
    text.dr_upd, fact.dr_updn = upd, n
    text.dr_quote, text.dr_qby = DR.quote(os.time())
    text.dr_qby = "— " .. text.dr_qby
    github()
end

-- ── the notices ──
local function notices()
    local rows, count = DR.notices(read("nexus-feed.json", "json"))
    model.nt = rows
    fact.dr_ncount = count
end
pcall(sys.watch, "files:nexus-feed.json", function() if D.open == 2 then notices() end end)
pcall(sys.watch, "files:updates.json", function() if D.open == 1 then dashboard() end end)

-- ── opening and closing ──
local function open(which)
    if which == 1 and cfg().dashboard == false then which = 0 end
    if which == 2 and cfg().notices == false then which = 0 end
    D.open = which
    fact.dr_open = which
    if which == 1 then dashboard() elseif which == 2 then notices() end
end
on("dr_cmd", function(v)
    v = math.floor(tonumber(v) or 0)
    -- the same key again closes it
    if v ~= 0 and v == D.open then v = 0 end
    open(v)
end)
on("dr_key", function(v) if math.floor(tonumber(v) or 0) == 27 then open(0) end end)
on("dr_refresh", function() D.gh_at = -1e9; dashboard() end)
on("dr_ghweb", function()
    if D.login and D.login:match("^[%w%-]+$") then run("xdg-open", { "https://github.com/" .. D.login }, function() end) end
    open(0)
end)
on("dr_upd_go", function()
    open(0)
    run("mooi", { "drawer-update" }, function() end)
end)
on("dr_nact", function(v)
    v = math.floor(tonumber(v) or 0)
    local row, what = v // 10, v % 10
    -- the bar keeps the notices; it is asked, as the node asks it (its rows are the feed's order)
    run("pleamar", { "--say", "mooi", "emit note_act " .. tostring(row * 10 + (what == 9 and 9 or 0)) }, function() end)
end)
on("dr_nclear", function() run("pleamar", { "--say", "mooi", "emit note_clear" }, function() end) end)
on("dr_nsilent", function() run("pleamar", { "--say", "mooi", "emit note_dnd" }, function() end) end)

log("drawers · up")
