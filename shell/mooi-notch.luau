-- mooi's side notch (D106): its logic. The fan's tabs and each panel's contents — a conversation with
-- Claude (lib/claude, through the `claude` command), the music (the media service, cava), your
-- workspaces and wallpapers as carousels, the weather (the Nexus's cache, or open-meteo), and GitHub
-- (the `gh` command, signed in as you). A panel is read when it is opened, not before. Pure parts are
-- lib/notch's.

local config = require("lib/config")
local ferro = require("lib/ferro")
local theme = require("lib/theme")
local style = require("lib/style")
local sysinfo = require("lib/sysinfo")
local forecast = require("lib/forecast")
local nexusfeed = require("lib/nexusfeed")
local hypr = require("lib/hypr")
local deck = require("lib/nexusdeck")
local claude = require("lib/claude")
local N = require("lib/notch")

local FILE, CHAT = "settings.json", "notch-claude.json"

local function env(name, fallback)
    local ok, v = pcall(sys.ask, "env", name)
    if ok and type(v) == "string" and v ~= "" then return v end
    return fallback
end
local function read(name, kind)
    local ok, v = pcall(sys.ask, "files.read", name, kind or "json")
    return ok and v or nil
end
local function read_text(name)
    local ok, v = pcall(sys.ask, "files.read", name)
    return ok and type(v) == "string" and v or nil
end
local function decode(out) local ok, t = pcall(json.decode, out or ""); return ok and t or nil end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function launch(cmd, args, done)
    local ok = pcall(run, cmd, args, function(out, code) if done then done(code == 0 and out or nil, code) end end)
    if not ok and done then done(nil, -1) end
end
local SAFE = env("MOOI_SAFE", "") == "1"
local HOME = env("HOME", "")
local data_folder = env("XDG_DATA_HOME", HOME .. "/.local/share") .. "/pleamar/mooi"
local settings = config.parse(read_text(FILE), json.decode)

-- ── The look: the shell's palette, the island style, the corners ──
local function paint()
    local palette = read("palette.json")
    local roles = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not roles then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = roles[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
    for name, c in pairs(theme.resolve(settings.theme, roles) or {}) do
        local f = "c_" .. string.gsub(name, "%.", "_")
        pcall(function() fact[f .. "_r"], fact[f .. "_g"], fact[f .. "_b"] = c.r, c.g, c.b end)
    end
    fact.cn_kind, fact.cn_scale = style.corners(settings)
    fact.isl_style = settings.island.style == "tether" and 1 or 0
    local look = style.facts(settings)
    if look and look.st_glow then fact.st_glow = look.st_glow end
end
paint()
pcall(sys.watch, "files:palette.json", paint)
pcall(sys.watch, "files:" .. FILE, function() settings = config.parse(read_text(FILE), json.decode); paint() end)

-- ── Where the nub is: half way down the screen the surface has (the bar's reserve outside it) ──
local screen = { w = 1920, h = 1049, mon = nil, full_w = 1920, full_h = 1080 }
local tab_rows = {}       -- the tabs as last published (their badges change)
-- the nub's height, as a share of the screen's (carried along the edge, kept in notch-state.json)
local STATE = "notch-state.json"
local nub = tonumber((read(STATE) or {}).y) or N.NUB_Y
local function place()
    local cy = math.floor(math.max(160, math.min(screen.h - 160, screen.h * nub)))
    fact.nt_cy, fact.nt_h = cy, screen.h
    local rows = {}
    for i, p in ipairs(N.fan(cy)) do rows[i] = { word = N.TABS[i].word, x = p.x + 22, y = p.y, glyph = i - 1, badge = "", badged = false } end
    model.tabs = rows
    tab_rows = rows
end
local function read_screen(done)
    launch("hyprctl", { "-j", "monitors" }, function(out)
        for _, m in ipairs(decode(out) or {}) do
            if m.focused then
                local s = tonumber(m.scale) or 1
                local r = type(m.reserved) == "table" and m.reserved or {}
                screen.mon = m
                screen.full_w, screen.full_h = math.floor(m.width / s + 0.5), math.floor(m.height / s + 0.5)
                screen.w = screen.full_w - (tonumber(r[1]) or 0) - (tonumber(r[3]) or 0)
                screen.h = screen.full_h - (tonumber(r[2]) or 0) - (tonumber(r[4]) or 0)
            end
        end
        place()
        if done then done() end
    end)
end
read_screen()
-- opened from the nub: beside the fan, level with it; the carousels turning from the screen's edge
local function panel_top(tab)
    if fact.nt_deck then return end
    fact.pn_y = N.panel_y(fact.nt_cy, (N.PANELS[tab] or { h = 400 }).h, screen.h)
    fact.nt_px, fact.nt_ox, fact.nt_dir = N.PANEL_X, 0, 1
    fact.nt_acy = math.max(430, math.min(screen.h - 430, fact.nt_cy))
end
on("nt_moved", function(v)
    local y = tonumber(v)
    if not y then return end
    nub = math.max(0.12, math.min(0.88, y / math.max(1, screen.h)))
    place()
    if not SAFE then pcall(sys.call, "files.write", STATE, { y = nub }) end
end)
local function badge(tab, word)
    local rows = tab_rows or {}
    if not rows[tab + 1] then return end
    rows[tab + 1].badge, rows[tab + 1].badged = word or "", (word or "") ~= ""
    model.tabs = rows
end

-- ── Claude: the conversation, kept in notch-claude.json; asked through `claude` ──
local chat = read(CHAT)
chat = type(chat) == "table" and chat or {}
chat.turns = type(chat.turns) == "table" and chat.turns or {}
local scroll = 0          -- lines up from the bottom
local live = nil          -- the answer as it grows
local COLS, SEEN = 56, 29
local SUGGEST = { "What can you help me with on this desktop?", "Explain Hyprland's dwindle and master layouts",
                  "A shell one-liner to find my largest files", "Plan my evening: three focused hours" }
do
    local rows = {}
    for i, t in ipairs(SUGGEST) do rows[i] = { t = t } end
    model.sugg = rows
end
local function save_chat()
    if SAFE then return end
    while #chat.turns > 40 do table.remove(chat.turns, 1) end
    pcall(sys.call, "files.write", CHAT, chat)
end
local function show_chat()
    local lines = {}
    local function add(kind, t) lines[#lines + 1] = { kind = kind, t = t } end
    local turns = {}
    for _, t in ipairs(chat.turns) do turns[#turns + 1] = t end
    if live then turns[#turns + 1] = { who = fact.ch_bmo and "bmo" or "claude", text = live == "" and "…" or live } end
    for i, t in ipairs(turns) do
        if i > 1 then add(4, "") end
        if t.who == "you" then
            add(0, "")
            for _, l in ipairs(claude.wrap(t.text, COLS)) do add(2, l) end
        elseif t.who == "note" then
            add(5, t.text)
        else
            add(t.who == "bmo" and 6 or 1, "")
            for _, l in ipairs(claude.wrap(t.text, COLS)) do add(3, l) end
        end
    end
    local first = math.max(1, #lines - SEEN + 1 - scroll)
    local rows = {}
    for i = first, math.min(#lines, first + SEEN - 1) do rows[#rows + 1] = lines[i] end
    model.cl = rows
    fact.ch_first = #chat.turns == 0 and not live
end
show_chat()
local asking = nil
local function ask(prompt)
    prompt = trim(prompt)
    if prompt == "" or asking then return end
    chat.turns[#chat.turns + 1] = { who = "you", text = prompt }
    live, scroll = "", 0
    fact.ch_busy, fact.nt_pin = true, true
    text.ch_status = "THINKING…"
    show_chat()
    local bmo = fact.ch_bmo
    local args = claude.args(prompt, { session = bmo and chat.bmo_session or chat.session, persona = bmo and "bmo" or "chat",
                                       model = type(settings.claude) == "table" and settings.claude.model ~= "default" and settings.claude.model or nil })
    local cmd = { "-C", env("XDG_RUNTIME_DIR", "/tmp"), "claude" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local done = false
    local mine
    mine = spawn("env", cmd, function(line)
        if asking ~= mine then return end
        local r = claude.read(line, json.decode)
        if not r then return end
        if r.delta then live = live .. r.delta; text.ch_status = "ANSWERING…"; show_chat()
        elseif r.done then
            done = true
            local said = r.text ~= "" and r.text or live
            if bmo then chat.bmo_session = r.session or chat.bmo_session else chat.session = r.session or chat.session end
            chat.turns[#chat.turns + 1] = { who = bmo and "bmo" or "claude", text = said }
            -- BMO says it on the desktop too
            if bmo then launch("pleamar", { "--say", "bmo", "text bmo_line " .. said:gsub("%s+", " "), "emit speak" }) end
            live = nil
            text.ch_status = r.cost and string.format("$%.3f", r.cost) or ""
        elseif r.error then
            done = true
            live = nil
            chat.turns[#chat.turns + 1] = { who = "note", text = "COULD NOT ASK: " .. string.upper(r.error) }
            text.ch_status = "NOT ANSWERED"
        end
    end, function(_, code)
        if asking ~= mine then return end
        asking = nil
        if not done then
            live = nil
            chat.turns[#chat.turns + 1] = { who = "note", text = code == 127 and "CLAUDE CODE IS NOT INSTALLED (THE `claude` COMMAND)" or "CLAUDE ENDED WITHOUT AN ANSWER" }
            text.ch_status = "NOT ANSWERED"
        end
        fact.ch_busy = false
        save_chat(); show_chat()
    end)
    asking = mine
end
on("nt_ask", function() local t = text.ch_in; text.ch_in = ""; ask(t) end)
on("nt_sugg", function(v) ask(SUGGEST[(tonumber(v) or -1) + 1]) end)
on("nt_mode", function(v) fact.ch_bmo = tonumber(v) == 1; text.ch_status = fact.ch_bmo and "IN BMO'S VOICE" or "" end)
on("nt_ask_bmo", function()
    fact.ch_bmo = true
    text.ch_status = "IN BMO'S VOICE"
    fact.nt_deck = false
    fact.nt_open, fact.nt_tab, fact.nt_pin = true, 0, true
    panel_top(0)
end)
on("nt_new", function()
    if asking then pcall(kill, asking, "term"); asking = nil end
    chat = { turns = {} }
    live, scroll = nil, 0
    fact.ch_busy = false
    text.ch_status = ""
    save_chat(); show_chat()
end)
on("nt_scroll", function(v) scroll = math.max(0, scroll + math.floor(tonumber(v) or 0) * 3); show_chat() end)

-- ── Music: the media service, the cover, where the song is, cava while it plays and is shown ──
local media, pos, pos_at = {}, 0, os.time()
local art_url = nil
local function clock(s) s = math.max(0, math.floor(tonumber(s) or 0)); return string.format("%d:%02d", math.floor(s / 60), s % 60) end
local cava, sent = nil, {}
local CAVA = "cava-notch.conf"
pcall(sys.call, "files.write", CAVA, table.concat({
    "[general]", "bars = 24", "framerate = 30", "[input]", "method = pipewire",
    "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
    "ascii_max_range = 1000", "bar_delimiter = 59", "frame_delimiter = 10", "[smoothing]", "noise_reduction = 70", "" }, "\n"))
local function viz()
    local want = fact.nt_open and fact.nt_tab == 1 and media.playing == true
    if not want then
        if cava then pcall(kill, cava, "term"); cava = nil end
        for i = 0, 23 do if (sent[i] or 0) ~= 0 then fact["mv" .. i] = 0; sent[i] = 0 end end
        return
    end
    if cava then return end
    local mine
    mine = spawn("cava", { "-p", data_folder .. "/" .. CAVA }, function(line)
        if cava ~= mine then return end
        local i = 0
        for v in line:gmatch("(%d+);") do
            if i > 23 then break end
            local x = math.min(1, (tonumber(v) or 0) / 1000)
            if math.abs(x - (sent[i] or 0)) > 0.025 then fact["mv" .. i] = x; sent[i] = x end
            i = i + 1
        end
    end, function() if cava == mine then cava = nil end end)
    cava = mine
end
pcall(sys.watch, "media", function(m)
    media = type(m) == "table" and m or {}
    fact.mu_on = tostring(media.title or "") ~= ""
    pos, pos_at = tonumber(media.position) or 0, os.time()
    text.mu_len = (tonumber(media.length) or 0) > 0 and clock(media.length) or ""
    local url = media.art
    if url ~= art_url then
        art_url = url
        local path = type(url) == "string" and url:match("^file://(.*)$")
        if path then text.mu_art = (path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)); fact.mu_art_on = true
        elseif type(url) == "string" and url:match("^https?://") then
            local dest = data_folder .. "/notch-cover.img"
            launch("curl", { "-fsSL", "--max-time", "8", "-o", dest, url }, function(ok) if ok and art_url == url then text.mu_art = dest .. "?" .. os.time() % 100000; fact.mu_art_on = true end end)
        else fact.mu_art_on = false end
    end
    badge(1, media.playing and "♪" or "")
    viz()
end)
every(1000, function()
    local len = tonumber(media.length) or 0
    if len <= 0 then fact.mu_prog = 0; text.mu_el = ""; return end
    local p = pos + (media.playing and (os.time() - pos_at) * (tonumber(media.rate) or 1) or 0)
    fact.mu_prog = math.min(1, p / len); text.mu_el = clock(p)
end)
on("nt_media", function(v)
    local n = tonumber(v)
    pcall(sys.call, n == 0 and "media.previous" or (n == 2 and "media.next" or "media.toggle"))
end)
on("nt_open_player", function() fact.nt_open, fact.nt_tab, fact.nt_pin = false, -1, false; launch("mooi", { "player" }) end)

-- ── Workspaces: every one of this monitor's, its windows where they are, the one you are on in the middle ──
local spaces = {}
local function read_spaces()
    launch("hyprctl", { "-j", "workspaces" }, function(wo)
        launch("hyprctl", { "-j", "clients" }, function(co)
            local mon = screen.mon
            local active = mon and type(mon.activeWorkspace) == "table" and tonumber(mon.activeWorkspace.id) or nil
            spaces = deck.spaces(decode(wo), mon and mon.name or nil, active)
            local rows, at = {}, {}
            for i, s in ipairs(spaces) do
                rows[i] = { id = s.id, label = string.format("WORKSPACE %d", s.id), n = s.windows > 0 and string.format("%d WIN", s.windows) or "EMPTY", active = s.active }
                at[s.id] = i - 1
                if s.active then fact.sp_c = i - 1 end
            end
            model.warc = rows
            local boxes = {}
            for _, w in ipairs(deck.windows(decode(co), mon)) do
                if at[w.ws] and #boxes < 60 then boxes[#boxes + 1] = { k = at[w.ws], nx = w.nx, ny = w.ny, nw = w.nw, nh = w.nh, focused = w.focused } end
            end
            model.wbox = boxes
        end)
    end)
end
on("nt_ws", function(v)
    local s = spaces[(tonumber(v) or -1) + 1]
    if s then pcall(sys.call, "workspaces.focus", s.id); fact.sp_c = (tonumber(v) or 0); after(300, read_spaces) end
end)
pcall(sys.watch, "workspaces", function() if fact.nt_tab == 2 then read_screen(read_spaces) end end)

-- ── Wallpapers: the studio's folder, a thumbnail each (made once, kept), a press wears one ──
local pictures, made = {}, {}
local function wearing()
    local w = read("wallpapers.json")
    return type(w) == "table" and type(w.applied) == "table" and w.applied.source or nil
end
local function show_pictures()
    local on = wearing()
    local rows = {}
    for i, p in ipairs(pictures) do
        local name = N.thumb_name(p)
        rows[i] = { pic = made[name] and (data_folder .. "/" .. name) or "", name = (p:match("([^/]+)$") or p), on = p == on }
        if p == on then fact.wp_c = i - 1 end
    end
    model.pics = rows
    text.wp_t = #pictures > 0 and string.format("%d PICTURES · %s", #pictures, string.upper(tostring((read("wallpapers.json") or {}).folder or ""))) or "NO PICTURES FOUND IN THE STUDIO'S FOLDER"
end
local function read_pictures()
    local w = read("wallpapers.json")
    local folder = type(w) == "table" and type(w.folder) == "string" and w.folder or (HOME .. "/Pictures/wallpapers")
    launch("find", { folder, "-maxdepth", "1", "-type", "f" }, function(out)
        pictures = N.pictures(out, 40)
        show_pictures()
        -- the thumbnails missing, one after another (each a moment's work for magick)
        local queue = {}
        for _, p in ipairs(pictures) do
            local name = N.thumb_name(p)
            if not made[name] then
                local ok, there = pcall(sys.ask, "files.exists", name)
                if ok and there then made[name] = true else queue[#queue + 1] = { p = p, name = name } end
            end
        end
        show_pictures()
        local function next_one()
            local job = table.remove(queue, 1)
            if not job then return end
            launch("magick", { job.p .. "[0]", "-thumbnail", "320x180^", "-gravity", "center", "-extent", "320x180", "-quality", "80", data_folder .. "/" .. job.name }, function(ok)
                if ok then made[job.name] = true; show_pictures() end
                next_one()
            end)
        end
        next_one()
    end)
end
on("nt_wall", function(v)
    local p = pictures[(tonumber(v) or -1) + 1]
    if not p then return end
    text.wp_t = "WEARING " .. string.upper(p:match("([^/]+)$") or p) .. "…"
    -- as the studio does (shell/mooi-wallpaper.luau): the picker, which also makes the palette; else awww
    launch("qs", { "-p", HOME .. "/.config/qs-wallpaperpicker", "ipc", "call", "wallpaper", "set", p }, function(_, code)
        if code == 0 then text.wp_t = "WEARING IT · THE PALETTE FOLLOWS"; return end
        launch("awww", { "img", p, "--transition-type", "grow", "--transition-duration", "0.8" }, function(_, acode)
            text.wp_t = acode == 0 and "WEARING IT (AWWW · THE PICKER WAS NOT RUNNING, SO THE PALETTE WAITS)" or "COULD NOT WEAR IT: START THE WALLPAPER PICKER OR AWWW"
        end)
    end)
end)
on("nt_studio", function() fact.nt_open, fact.nt_tab, fact.nt_pin = false, -1, false; launch("mooi", { "wallpaper" }) end)
do
    local small = data_folder .. "/nexus-wall.jpg"
    launch("magick", { HOME .. "/.cache/current_wallpaper[0]", "-resize", "640x360^", "-gravity", "center", "-extent", "640x360", "-quality", "82", small }, function(ok)
        if ok then text.nt_wall = small .. "?" .. os.time() % 100000; fact.nt_wall_on = true end
    end)
end

-- ── Weather: the Nexus's cache (ten minutes), else open-meteo ──
local function kind_of(code, day)
    local k = sysinfo.weather(code, day)
    for i, name in ipairs(sysinfo.WEATHER_KINDS) do if name == k then return i - 1 end end
    return 2
end
local function show_weather(doc)
    local f = forecast.parse(doc.answer)
    if not f then return end
    local _, word = sysinfo.weather(f.now.code, f.now.day)
    fact.wx_kind = kind_of(f.now.code, f.now.day)
    text.wx_temp = string.format("%d°", math.floor(f.now.temp + 0.5))
    text.wx_word = string.upper(tostring(word or ""))
    text.wx_feels = string.format("FEELS %d°", math.floor((tonumber(f.now.feels) or f.now.temp) + 0.5))
    text.wx_range = f.today and f.today.hi and string.format("↑ %d°  ↓ %d°", math.floor(f.today.hi + 0.5), math.floor(f.today.lo + 0.5)) or ""
    text.wx_place = string.upper(tostring(doc.city or ""))
    local bars = N.bars(f.hours)
    local rows = {}
    for i, h in ipairs(f.hours) do rows[i] = { label = h.label .. ":00", t = string.format("%d°", math.floor(h.temp + 0.5)), v = bars[i], kind = kind_of(h.code, h.day) } end
    model.hrs = rows
    local lo, hi = math.huge, -math.huge
    for _, d in ipairs(f.days) do lo, hi = math.min(lo, d.lo), math.max(hi, d.hi) end
    local span = math.max(1, hi - lo)
    local drows = {}
    for i, d in ipairs(f.days) do
        drows[i] = { label = string.upper(string.sub(d.label, 1, 3)), hi = tostring(math.floor(d.hi + 0.5)), lo = tostring(math.floor(d.lo + 0.5)),
                     kind = kind_of(d.code, 1), lo_v = (d.lo - lo) / span, hi_v = (d.hi - lo) / span }
    end
    model.dys = drows
    fact.wx_ok = true
end
local function read_weather()
    local cached = read("nexus-weather.json")
    if type(cached) == "table" and type(cached.answer) == "table" then show_weather(cached) end
    if type(cached) == "table" and os.time() - (tonumber(cached.at) or 0) < 600 then return end
    launch("curl", { "-fsSL", "--max-time", "8", "https://ipinfo.io/json" }, function(out)
        local where = decode(out)
        local lat, lon = nil, nil
        if type(where) == "table" then lat, lon = tostring(where.loc or ""):match("^([%d%.%-]+),([%d%.%-]+)$") end
        if not lat then return end
        launch("curl", { "-fsSL", "--max-time", "12", forecast.url(lat, lon) }, function(ans)
            local t = decode(ans)
            if type(t) ~= "table" then return end
            local doc = { at = os.time(), city = where.city, answer = t }
            pcall(sys.call, "files.write", "nexus-weather.json", doc)
            show_weather(doc)
        end)
    end)
end

-- ── GitHub: through `gh`, signed in as you; read when the panel opens, kept five minutes ──
local gh_at, gh_urls, gh_user = 0, {}, nil
local function ago(iso)
    local y, mo, d, h, mi = tostring(iso or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
    if not y then return "" end
    local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
    local off = os.time() - os.time(os.date("!*t"))           -- the zone: GitHub's times are UTC
    return string.upper(nexusfeed.ago(os.time() - (t + off)))
end
local EVENTS = { PushEvent = "pushed to", PullRequestEvent = "a pull request on", IssuesEvent = "an issue on", CreateEvent = "created",
                 WatchEvent = "starred", ForkEvent = "forked", IssueCommentEvent = "commented on", ReleaseEvent = "released", PullRequestReviewEvent = "reviewed" }
local function read_github()
    if os.time() - gh_at < 300 and fact.gh_ok then return end
    gh_at = os.time()
    text.gh_state = "ASKING GITHUB…"
    local q = [[query { viewer { login name avatarUrl followers { totalCount } following { totalCount }
        repositories(first: 4, ownerAffiliations: OWNER, orderBy: { field: PUSHED_AT, direction: DESC }) { totalCount nodes { name stargazerCount primaryLanguage { name } } }
        contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { contributionCount } } } } } }]]
    launch("gh", { "api", "graphql", "-f", "query=" .. q }, function(out, code)
        local doc = decode(out)
        local v = type(doc) == "table" and type(doc.data) == "table" and doc.data.viewer or nil
        if not v then
            fact.gh_ok = false
            text.gh_state = code == 127 and "INSTALL THE GITHUB CLI (gh) AND RUN `gh auth login`" or "GITHUB DID NOT ANSWER · IS `gh auth status` SIGNED IN?"
            return
        end
        gh_user = v.login
        text.gh_login, text.gh_name = "@" .. tostring(v.login or ""), tostring(v.name ~= nil and v.name ~= json.null and v.name or v.login or "")
        text.gh_stats = string.format("%d REPOS · %d FOLLOWERS", v.repositories and v.repositories.totalCount or 0, v.followers and v.followers.totalCount or 0)
        local cal = v.contributionsCollection and v.contributionsCollection.contributionCalendar or {}
        text.gh_total = string.format("%d THIS YEAR", tonumber(cal.totalContributions) or 0)
        local days = {}
        for _, w in ipairs(type(cal.weeks) == "table" and cal.weeks or {}) do
            for _, d in ipairs(w.contributionDays or {}) do days[#days + 1] = tonumber(d.contributionCount) or 0 end
        end
        local from = math.max(1, #days - 181)
        local top = 1
        for i = from, #days do top = math.max(top, days[i]) end
        local cells = {}
        for i = from, #days do cells[#cells + 1] = { v = days[i] / top } end
        model.gcal = cells
        local repos = {}
        for i, r in ipairs(v.repositories and v.repositories.nodes or {}) do
            repos[i] = { name = tostring(r.name), stars = tostring(r.stargazerCount or 0), lang = string.upper(tostring(type(r.primaryLanguage) == "table" and r.primaryLanguage.name or "—")) }
        end
        model.grep = repos
        if type(v.avatarUrl) == "string" then
            local dest = data_folder .. "/notch-github.img"
            launch("curl", { "-fsSL", "--max-time", "8", "-o", dest, v.avatarUrl }, function(ok) if ok then text.gh_avatar = dest .. "?" .. os.time() % 100000; fact.gh_avatar_on = true end end)
        end
        fact.gh_ok = true
        launch("gh", { "api", "users/" .. tostring(v.login) .. "/events?per_page=12" }, function(eo)
            local rows = {}
            for _, e in ipairs(decode(eo) or {}) do
                if #rows < 6 then
                    rows[#rows + 1] = { t = string.format("%s %s", EVENTS[e.type] or string.lower(tostring(e.type or ""):gsub("Event$", "")), tostring(e.repo and e.repo.name or "")),
                                        repo = tostring(e.repo and e.repo.name or ""), ago = ago(e.created_at) }
                end
            end
            model.gevt = rows
        end)
    end)
    launch("gh", { "search", "prs", "--author", "@me", "--state", "open", "--json", "title,repository,url", "--limit", "5" }, function(out)
        local rows = {}
        gh_urls = {}
        for i, p in ipairs(decode(out) or {}) do
            rows[i] = { t = tostring(p.title or ""), repo = tostring(p.repository and (p.repository.name or p.repository.nameWithOwner) or ""), url = tostring(p.url or "") }
            gh_urls[i] = p.url
        end
        model.gprs = rows
    end)
    launch("gh", { "api", "notifications" }, function(out)
        local n = #(decode(out) or {})
        text.gh_notes = n > 0 and string.format("%d UNREAD", n) or ""
        fact.gh_noted = n > 0
        badge(5, n > 0 and tostring(math.min(n, 99)) or "")
        launch("pleamar", { "--say", "mooi", "fact gh_unread " .. n })   -- the bar's GitHub module wears the count
    end)
end
on("nt_gh", function(v)
    local n = math.floor(tonumber(v) or -1)
    local url = n == 0 and gh_user and ("https://github.com/" .. gh_user) or (n == 10 and "https://github.com/notifications") or gh_urls[n]
    if url then launch("xdg-open", { url }); fact.nt_open, fact.nt_tab, fact.nt_pin = false, -1, false end
end)

-- ── Opening a panel: read what it shows ──
local READ = { [2] = function() read_screen(read_spaces) end, [3] = read_pictures, [4] = read_weather, [5] = read_github }
on("nt_tab_open", function(v)
    local n = math.floor(tonumber(v) or -1)
    panel_top(n)
    if READ[n] then READ[n]() end
    viz()
end)
-- from outside: the bar's Claude or GitHub module, `mooi notch <tab>`
on("nt_show", function(v)
    local n = math.floor(tonumber(v) or 0)
    fact.nt_deck = false
    fact.nt_open, fact.nt_tab, fact.nt_pin = true, n, true
    panel_top(n)
    if READ[n] then READ[n]() end
    viz()
end)
on("fact:nt_open", function() viz() end)
-- from the Control Nexus: it has said where (nt_px, pn_y, nt_ox, nt_acy, nt_dir); open that panel there
on("nt_show_deck", function(v)
    local n = math.floor(tonumber(v) or 0)
    fact.nt_deck, fact.nt_entered, fact.nt_pin = true, false, false
    fact.nt_open, fact.nt_tab = true, n
    if READ[n] then READ[n]() end
    viz()
end)
on("nt_close", function() fact.nt_open, fact.nt_tab, fact.nt_pin, fact.nt_deck = false, -1, false, false; viz() end)
read_weather()
after(4000, read_github)        -- the badge of what waits on GitHub, read once at the start
every(600000, function() gh_at = 0; read_github() end)
