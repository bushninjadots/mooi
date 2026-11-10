-- mooi's side notch (D106): its logic. The fan's tabs and each panel's contents — a conversation with
-- Claude (lib/claude, through the `claude` command), the music (the media service, the bar's feed), your
-- workspaces and wallpapers as carousels, the weather (the Nexus's cache, or open-meteo), and GitHub
-- (the `gh` command, signed in as you). A panel is read when it is opened, not before. Pure parts are
-- lib/notch's.

local config = require("lib/config")
local ferro = require("lib/ferro")
local theme = require("lib/theme")
local coverart = require("lib/cover")
local style = require("lib/style")
local sysinfo = require("lib/sysinfo")
local forecast = require("lib/forecast")
local games = require("lib/games")
local weathershare = require("lib/weathershare")
local weatherpanel = require("lib/weatherpanel")
local nexusfeed = require("lib/nexusfeed")
local hypr = require("lib/hypr")
local walls = require("lib/walls")
local deck = require("lib/nexusdeck")
local atlas = require("lib/atlas")
local claude = require("lib/claude")
local N = require("lib/notch")
local vizfeed = require("lib/vizfeed")
local wire = require("bmo/wire")     -- what crosses to BMO and back: one token, never words on a line

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
-- What a command printed, whatever it exited with (D156): a `grep` over folders that are not there
-- exits 2 and a `find` over a missing library 1, and the answers — the games — are in their output
-- all the same. `launch` throws that away on a non-zero exit, which is right for magick and wrong here.
local function probe(cmd, args, done)
    local ok = pcall(run, cmd, args, function(out) done(out or "") end)
    if not ok then done("") end
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
    local top = tonumber((type(screen.mon) == "table" and type(screen.mon.reserved) == "table" and screen.mon.reserved[2]) or 0) or 0
    local cy = N.nub_cy(nub, screen.h, top, screen.full_h)
    fact.nt_cy, fact.nt_h = cy, screen.h
    -- where it is on the whole screen, for the bar: the stash's edge strip leaves that band to the nub
    local c0, c1 = N.cut(cy, top)
    if not SAFE and screen.mon then pcall(sys.call, "files.write", STATE, { y = nub, cut0 = c0, cut1 = c1 }) end
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
end)
local function badge(tab, word)
    local rows = tab_rows or {}
    if not rows[tab + 1] then return end
    rows[tab + 1].badge, rows[tab + 1].badged = word or "", (word or "") ~= ""
    model.tabs = rows
    local any = false
    for _, r in ipairs(rows) do if r.badged then any = true end end
    fact.nt_badged = any
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
-- Where Claude and the free models are run: an empty folder of mooi's own under the runtime dir that
-- `mooi` makes at session start (fourth pass, L3), not the runtime dir itself with its sockets in it.
-- The runtime dir stands in if the folder is not there (an older launcher), as before.
local ASK_DIR = env("MOOI_ASK_DIR", "")
if ASK_DIR == "" then ASK_DIR = env("XDG_RUNTIME_DIR", "/tmp") end
-- Claude could not answer (D143: no credits, offline, signed out): a free model through opencode, its
-- models tried in turn, in the same voice, with the last few turns. cb(answer, model) or cb(nil).
local function ask_free(prompt, persona, cb, i)
    i = i or 1
    if not claude.free_allowed(settings) then cb(nil, nil, "off"); return end
    local model = claude.FALLBACK_MODELS[i]
    if not model then cb(nil); return end
    local recent = {}
    for k = math.max(1, #chat.turns - 6), #chat.turns do
        local t = chat.turns[k]
        if t and t.who ~= "note" and t.text ~= prompt then recent[#recent + 1] = t end
    end
    local cmd = { "-C", ASK_DIR }
    for _, e in ipairs(claude.FREE_ENV) do cmd[#cmd + 1] = e end
    for _, a in ipairs({ "timeout", "90", "opencode" }) do cmd[#cmd + 1] = a end
    for _, a in ipairs(claude.fallback_args(prompt, persona, model, recent)) do cmd[#cmd + 1] = a end
    launch("env", cmd, function(out)
        local said = claude.fallback_text(out)
        if said then cb(said, model) else ask_free(prompt, persona, cb, i + 1) end
    end)
end
local function free_name(model) return string.upper((tostring(model or ""):gsub("^opencode/", ""))) end
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
    local cmd = { "-C", ASK_DIR, "claude" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local done, failed = false, nil
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
            if bmo then launch("pleamar", { "--say", "bmo", wire.say(said), "emit speak" }) end
            live = nil
            text.ch_status = r.cost and string.format("$%.3f", r.cost) or ""
        elseif r.error then
            failed = r.error
        end
    end, function(_, code)
        if asking ~= mine then return end
        local function finish()
            if asking == mine then asking = nil end
            fact.ch_busy = false
            save_chat(); show_chat()
        end
        if done then finish(); return end
        -- Claude did not answer: a free model instead (D143)
        live = nil
        local why = failed or (code == 127 and "CLAUDE CODE IS NOT INSTALLED" or "CLAUDE ENDED WITHOUT AN ANSWER")
        text.ch_status = claude.free_allowed(settings) and "CLAUDE DIDN'T ANSWER · ASKING A FREE MODEL…" or "CLAUDE DIDN'T ANSWER"
        show_chat()
        ask_free(prompt, bmo and "bmo" or "chat", function(said, model, off)
            if off then
                chat.turns[#chat.turns + 1] = { who = "note", text = "COULD NOT ASK: " .. string.upper(why) .. " · FREE MODELS ARE OFF (SETTINGS → NEXUS → CLAUDE)" }
                text.ch_status = "NOT ANSWERED"
            elseif said then
                chat.turns[#chat.turns + 1] = { who = bmo and "bmo" or "claude", text = said }
                chat.turns[#chat.turns + 1] = { who = "note", text = "ANSWERED BY " .. free_name(model) .. " (FREE) · CLAUDE: " .. string.upper(why) }
                if bmo then launch("pleamar", { "--say", "bmo", wire.say(said), "emit speak" }) end
                text.ch_status = "FREE MODEL"
            else
                chat.turns[#chat.turns + 1] = { who = "note", text = "COULD NOT ASK: " .. string.upper(why) .. " · NO FREE MODEL ANSWERED EITHER" }
                text.ch_status = "NOT ANSWERED"
            end
            finish()
        end)
    end)
    asking = mine
end
on("nt_ask", function() local t = text.ch_in; text.ch_in = ""; ask(t) end)
-- D281: `mooi ask` — words read off a region of the screen start the question; the file is read once, then gone
on("nt_region", function()
    local ok, words = pcall(sys.ask, "files.read", "ask-region.txt")
    pcall(sys.call, "files.remove", "ask-region.txt")
    if not ok or type(words) ~= "string" or words == "" then return end
    -- the field is one line: the words folded onto it, quoted, with room left for the question
    text.ch_in = "About this from my screen: \"" .. (words:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) .. "\" — "
end)
on("nt_sugg", function(v) ask(SUGGEST[(tonumber(v) or -1) + 1]) end)
-- BMO's own chat (his panel's CHAT tab, D109): he sends what was said (nb_q); asked in his voice, on
-- his own session, and the answer goes back to him to be said and written in his panel.
local bmo_asking = nil
on("nt_bmo_q", function()
    local q = wire.asked(text)          -- decoded at the door (bmo/wire): a message is one token
    if q:match("^%s*$") or bmo_asking then return end
    local args = claude.args(q, { session = chat.bmo_session, persona = "bmo",
                                  model = type(settings.claude) == "table" and settings.claude.model ~= "default" and settings.claude.model or nil })
    local cmd = { "-C", ASK_DIR, "claude" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local said = nil
    local mine
    mine = spawn("env", cmd, function(line)
        if bmo_asking ~= mine then return end
        local r = claude.read(line, json.decode)
        if r and r.done then said = r.text; chat.bmo_session = r.session or chat.bmo_session end
    end, function()
        if bmo_asking ~= mine then return end
        if said then
            bmo_asking = nil
            save_chat()
            launch("pleamar", { "--say", "bmo", wire.say(said), "emit speak" })
            return
        end
        -- Claude did not answer: a free model in his voice (D143); his own joke if none answers
        ask_free(q, "bmo", function(free)
            bmo_asking = nil
            local line = free or "BMO's brain is fuzzy right now… but BMO knows a joke!"
            launch("pleamar", { "--say", "bmo", wire.say(line), "emit speak" })
            if not free then after(5200, function() launch("pleamar", { "--say", "bmo", "emit joke" }) end) end
        end)
    end)
    bmo_asking = mine
end)
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

-- ── Music: the media service, the cover, where the song is, and the bar's feed while it is shown ──
local media, pos, pos_at = {}, 0, os.time()
local art_url = nil
local function clock(s) s = math.max(0, math.floor(tonumber(s) or 0)); return string.format("%d:%02d", math.floor(s / 60), s % 60) end
-- The Music panel's visualiser (D112/D118): the bar owns the one cava and writes the feed while
-- someone asks for it; this panel asks only while it is open on the Music tab, and reads it then.
-- A file watch coalesces quick writes (it delivered ~4 of the 30 lines a second, so the bars moved
-- once or twice a beat and stood still between), so while the panel shows the music it reads the
-- feed at the feed's own pace. (No music on the panels' borders any more: that is the frame's.)
local viz_seq, viz_at = nil, 0
local function music_up() return fact.nt_open == true and fact.nt_tab == 1 end
local function rest_viz() for i = 0, 23 do fact["mv" .. i] = 0 end end
local function take_viz()
    if not music_up() then return end
    local ok, raw = pcall(sys.ask, "files.read", vizfeed.FILE)
    if not ok or type(raw) ~= "string" then return end
    local t = vizfeed.decode(raw)
    if not t or not vizfeed.newer(viz_seq, t.seq) then return end
    viz_seq, viz_at = t.seq, os.time()
    fact.mu_viz_missing = t.missing == true
    if not t.playing then rest_viz(); return end
    local bands = vizfeed.map(t.bands, 24)
    for i = 0, 23 do fact["mv" .. i] = bands[i + 1] end
end
local viz_timer, ask_timer = nil, nil
local function viz()
    if music_up() and media.playing == true then
        if not viz_timer then
            run("pleamar", { "--say", "mooi", "emit feed_want" })
            viz_timer = every(33, take_viz)
            ask_timer = every(3000, function()
                run("pleamar", { "--say", "mooi", "emit feed_want" })
                if viz_seq and not vizfeed.fresh(viz_at * 1000, os.time() * 1000) then viz_seq, viz_at = nil, 0; rest_viz() end
            end)
        end
    else
        if viz_timer then cancel(viz_timer); viz_timer = nil end
        if ask_timer then cancel(ask_timer); ask_timer = nil end
        rest_viz()
    end
    -- every opening, closing and change of panel comes through here: the windows' pictures follow it
    if ask_pictures then ask_pictures() end
end
pcall(sys.watch, "media", function(m)
    media = type(m) == "table" and m or {}
    fact.mu_on = tostring(media.title or "") ~= ""
    pos, pos_at = tonumber(media.position) or 0, os.time()
    text.mu_len = (tonumber(media.length) or 0) > 0 and clock(media.length) or ""
    local url = media.art
    if url ~= art_url then
        art_url = url
        local path = coverart.path(url)
        if path then text.mu_art = path; fact.mu_art_on = true
        elseif coverart.remote(url) then
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
on("nt_open_player", function() fact.nt_open, fact.nt_tab, fact.nt_pin = false, -1, false; viz(); launch("mooi", { "player" }) end)

-- ── Workspaces: every one of this monitor's, its windows where they are, the one you are on in the middle ──
local spaces = {}
-- The windows in the miniatures are the windows themselves, live (pleamar's `thumbnails.live`): only
-- while the Workspaces panel is up, only those of the three workspaces round the arc's middle (the rest
-- on the arc get a still), and never one that Settings → Workspaces's privacy keeps back or with previews
-- off. A window the compositor is not drawing (another workspace, on Hyprland) keeps its last picture,
-- or none: its miniature is the plain box it always was.
local minis, thumbs, asked = {}, {}, nil
local function previews_on() return type(settings.atlas) ~= "table" or settings.atlas.previews ~= false end
local function privacy() return type(settings.atlas) == "table" and settings.atlas.private or "off" end
-- Each miniature's picture: the window of the same app and title, else one of the same app not yet
-- taken (a title can change between Hyprland's list and the compositor's: a terminal's spinner).
local function pair()
    local got, used = {}, {}
    for pass = 1, 2 do
        for i, b in ipairs(minis) do
            if not got[i] and not atlas.private(privacy(), b.app, b.title) then
                for _, t in ipairs(thumbs) do
                    if not used[t.id] and t.app == b.app and (pass == 2 or t.title == b.title) then
                        got[i], used[t.id] = t, true
                        break
                    end
                end
            end
        end
    end
    return got
end
function publish_minis()
    local got, out = previews_on() and pair() or {}, {}
    for i, b in ipairs(minis) do
        local pic = got[i] and got[i].picture or ""
        out[i] = { k = b.k, nx = b.nx, ny = b.ny, nw = b.nw, nh = b.nh, focused = b.focused, pic = pic, pictured = pic ~= "" }
    end
    model.wbox = out
end
local watching = false
function ask_pictures()
    local up = fact.nt_open == true and math.floor(tonumber(fact.nt_tab) or -1) == 2 and previews_on() and privacy() ~= "everything"
    local live, still = {}, {}
    if up then
        if not watching then
            watching = pcall(sys.watch, "thumbnails", function(state)
                thumbs = type(state) == "table" and type(state.list) == "table" and state.list or {}
                publish_minis()
                ask_pictures()
            end)
        end
        local c = tonumber(fact.sp_c) or 0
        local got = pair()
        for i, b in ipairs(minis) do
            local t = got[i]
            local d = math.abs(b.k - c)
            if t and d <= 3 then
                if d <= 1 then live[#live + 1] = t.id else still[#still + 1] = t.id end
            end
        end
    end
    table.sort(live); table.sort(still)
    local key = table.concat(live, ",") .. "|" .. table.concat(still, ",")
    if key == asked then return end
    asked = key
    if #live > 0 then pcall(sys.call, "thumbnails.live", live) else pcall(sys.call, "thumbnails.live") end
    if #still > 0 then pcall(sys.call, "thumbnails.want", still) else pcall(sys.call, "thumbnails.want") end
end
on("fact:nt_tab", function() ask_pictures() end)
on("fact:sp_c", function() ask_pictures() end)
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
                if at[w.ws] and #boxes < 60 then
                    boxes[#boxes + 1] = { k = at[w.ws], nx = w.nx, ny = w.ny, nw = w.nw, nh = w.nh, focused = w.focused, app = w.app, title = w.title }
                end
            end
            minis = boxes
            publish_minis()
            ask_pictures()
        end)
    end)
end
on("nt_ws", function(v)
    local s = spaces[(tonumber(v) or -1) + 1]
    if s then pcall(sys.call, "workspaces.focus", s.id); fact.sp_c = (tonumber(v) or 0); after(300, read_spaces) end
end)
pcall(sys.watch, "workspaces", function() if fact.nt_tab == 2 then read_screen(read_spaces) end end)

-- ── Wallpapers: the studio's folder, a thumbnail each (made once, kept), a press wears one ──
-- And the colours: each picture's hue, read once (wallpaper-hues.json) in the background, so the
-- arc can be narrowed to the reds, the blues… and the swatches along its inside choose them.
local pictures, made, draws = {}, {}, 0
local tried = {}             -- a thumbnail looked for once
local where = ""             -- the folder those came from, named under the arc
local left = -1              -- pictures whose colour is not read yet (the pass says so under the arc)
local pool = {}              -- every picture in the folder (the colour pass reads them all)
local hues = {}              -- picture path → its hue, 0..360
local hue_queue, hue_busy = {}, false
local thumb_queue, thumb_busy = {}, false
local BAND_N = 12
local BAND_WORD = { "REDS", "ORANGES", "YELLOWS", "LIMES", "GREENS", "SPRINGS",
                    "CYANS", "AZURES", "BLUES", "VIOLETS", "PURPLES", "PINKS" }

do
    local doc = read("wallpaper-hues.json")
    if type(doc) == "table" then
        for k, v in pairs(doc) do
            if type(k) == "string" then
                local h = tonumber(v)
                if h then hues[k] = h % 360 elseif v == false then hues[k] = false end
            end
        end
    end
end
local function wearing()
    local w = read("wall.json")
    return type(w) == "table" and type(w.source) == "string" and w.source or nil
end
local function save_hues()
    if SAFE then return end
    pcall(sys.call, "files.write", "wallpaper-hues.json", hues)
end

local function band()
    return math.floor(tonumber(fact.wp_hue) or -1)
end

local need_thumbs, pump_thumbs, pump_hues
local wh                     -- Wallhaven, the second source (below, after `wear`)

-- What the arc walks: the whole folder (shuffled afresh each time the panel opens, the worn one
-- first), or, a colour chosen, every picture of that colour. The scene holds a window of WIN of
-- them (`pics`, from `wp_base`): it slides along the list as the wheel turns, so every picture
-- can be reached while only forty are ever drawn (D118; before, a random forty were all it had).
local WIN = 40
local base = 0               -- the list's index of the window's first row
-- D307: the favourites every switcher shares (lib/walls FAVS); the third source shows only them, newest first
local fav_set, fav_list = walls.favs(read(walls.FAVS, "json"))
local function view()
    local b = band()
    local from = math.floor(tonumber(fact.wp_src) or 0) == 2 and fav_list or pictures
    if b < 0 then return from, #from end
    local out = {}
    for _, p in ipairs(from) do
        local h = hues[p]
        if type(h) == "number" and N.band(h, BAND_N) == b then out[#out + 1] = p end
    end
    return out, #out
end

-- `recenter` is for a new list (the panel opening, a colour chosen): the worn picture, or the
-- first. A thumbnail or a colour arriving in the background must leave the arc where the wheel
-- put it — otherwise every finished batch snaps the picture in the middle back to the start.
local function show_pictures(recenter)
    if wh and wh.on() then wh.show(recenter); return end
    local on = wearing()
    local list, all = view()
    local rows = {}
    -- where the middle of the arc is in the whole list (the window's row plus where it starts)
    local at = base + math.floor(tonumber(fact.wp_c) or 0)
    if recenter then
        at = 0
        for i, p in ipairs(list) do if p == on then at = i - 1; break end end
    end
    at = math.max(0, math.min(at, #list - 1))
    base = math.max(0, math.min(at - WIN // 2, #list - WIN))
    fact.wp_base, fact.wp_c = base, at - base
    for i = 1, math.min(WIN, #list - base) do
        local p = list[base + i]
        local name = N.thumb_name(p)
        local label = p:match("([^/]+)$") or p
        if N.is_live(p) then label = "LIVE · " .. label end
        rows[i] = { pic = made[name] and (data_folder .. "/" .. name) or "", name = label, on = p == on, fav = fav_set[p] == true }
    end
    model.pics = rows
    local b = band()
    if b >= 0 then
        local more = left > 0 and string.format(" · %d OF %d READ", #pool - left, #pool) or ""
        text.wp_t = all > 0 and (string.format("%d OF %d", at + 1, all) .. " · " .. BAND_WORD[b + 1] .. more)
                        or ("NONE OF THAT COLOUR YET · STILL READING THE FOLDER" .. more)
    else
        text.wp_t = #list > 0 and string.format("%d OF %d · %s", at + 1, #list, string.upper(where))
                        or ("NO PICTURES FOUND IN " .. string.upper(where == "" and "THE STUDIO'S FOLDER" or where))
    end
    -- the thumbnails nearest the middle first, then a little ahead of where the wheel is going
    local near = {}
    for d = 0, 10 do
        if list[at + 1 + d] then near[#near + 1] = list[at + 1 + d] end
        if d > 0 and list[at + 1 - d] then near[#near + 1] = list[at + 1 - d] end
    end
    need_thumbs(near)
end
-- The wheel moved the arc: past a quarter of the window from its middle, the window slides so the
-- middle is in the middle again (and the thumbnails ahead are made); the arc itself does not move,
-- since the scene draws each row at its place in the whole list (`wp_base`).
local last_at = -1
on("fact:wp_c", function()
    if not (fact.nt_open and math.floor(tonumber(fact.nt_tab) or -1) == 3) then return end
    if wh and wh.on() then wh.show(); return end
    local at = base + math.floor(tonumber(fact.wp_c) or 0)
    if at == last_at then return end
    last_at = at
    local c = math.floor(tonumber(fact.wp_c) or 0)
    if math.abs(c - WIN // 2) > WIN // 4 then show_pictures() else
        local list = view()
        local near = {}
        for d = 0, 10 do
            if list[at + 1 + d] then near[#near + 1] = list[at + 1 + d] end
            if d > 0 and list[at + 1 - d] then near[#near + 1] = list[at + 1 - d] end
        end
        need_thumbs(near)
    end
end)

-- The thumbnails missing, a few at a time (each a moment's work for magick).
need_thumbs = function(list)
    for _, p in ipairs(list) do
        local name = N.thumb_name(p)
        if not made[name] and not tried[name] then
            local ok, there = pcall(sys.ask, "files.exists", name)
            tried[name] = true
            if ok and there then made[name] = true
            else
                local queued = false
                for _, q in ipairs(thumb_queue) do if q.name == name then queued = true; break end end
                if not queued then thumb_queue[#thumb_queue + 1] = { p = p, name = name } end
                while #thumb_queue > 24 do table.remove(thumb_queue, 1) end   -- the wheel has moved past those
            end
        end
    end
    pump_thumbs()
end

pump_thumbs = function()
    if thumb_busy then return end
    local job = table.remove(thumb_queue, 1)
    if not job then return end
    thumb_busy = true
    local out = data_folder .. "/" .. job.name
    -- a video's thumbnail is a frame a second in (D145), cut to fill as the pictures' are
    local cmd, args = "magick", { "-define", "jpeg:size=320x180", job.p .. "[0]", "-thumbnail", "320x180^", "-gravity", "center", "-extent", "320x180", "-quality", "80", out }
    if N.is_video(job.p) then
        cmd, args = "ffmpeg", { "-v", "error", "-y", "-ss", "1", "-i", job.p, "-frames:v", "1", "-vf", "scale=320:180:force_original_aspect_ratio=increase,crop=320:180", "-q:v", "4", out }
    end
    launch(cmd, args, function(ok)
        thumb_busy = false
        if ok then made[job.name] = true; show_pictures() end
        pump_thumbs()
    end)
end

-- Every picture's hue, a batch at a time (one magick for the lot), so a colour can be browsed on
-- the whole folder, not just the forty drawn. Kept in wallpaper-hues.json.
-- Read a batch's colours. One picture magick cannot read makes the whole batch fail and print
-- nothing, so a short batch is tried again in halves until the bad picture is alone; it is filed
-- as colourless (false) and never asked for again, or the pass would retry the same batch forever.
local function read_hues(batch, done)
    local args = { "-define", "jpeg:size=64x64" }
    for _, p in ipairs(batch) do
        args[#args + 1] = p .. "[0]"; args[#args + 1] = "-resize"; args[#args + 1] = "8x8!"
    end
    -- sRGB first: a grey picture has one channel, and its green and blue would read as none
    args[#args + 1] = "-colorspace"; args[#args + 1] = "sRGB"
    args[#args + 1] = "-format"; args[#args + 1] = "%f %[fx:mean.r] %[fx:mean.g] %[fx:mean.b]\n"
    args[#args + 1] = "info:"
    launch("magick", args, function(out)
        local by, missing, got = {}, {}, 0
        for _, p in ipairs(batch) do
            by[p:match("([^/]+)$")] = p
            missing[p] = true
        end
        for line in tostring(out or ""):gmatch("[^\n]+") do
            local name, cr, cg, cb = line:match("^(.-)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)$")
            if name and by[name] and tonumber(cr) then
                local h, sat = N.hue(tonumber(cr), tonumber(cg), tonumber(cb))
                -- a grey has no colour to be filed under: it stays in the whole folder only
                hues[by[name]] = sat >= 0.15 and h or false
                missing[by[name]] = nil
                got = got + 1
            end
        end
        local left_paths = {}
        for _, p in ipairs(batch) do if missing[p] then left_paths[#left_paths + 1] = p end end
        if #left_paths == 0 then done(got); return end
        if #batch == 1 then hues[batch[1]] = false; done(got); return end
        if #left_paths < #batch then
            read_hues(left_paths, function(g) done(got + g) end); return
        end
        local half = math.floor(#batch / 2)
        local a, b = {}, {}
        for i = 1, half do a[i] = batch[i] end
        for i = half + 1, #batch do b[#b + 1] = batch[i] end
        read_hues(a, function(ga)
            read_hues(b, function(gb) done(ga + gb) end)
        end)
    end)
end

pump_hues = function()
    if hue_busy then return end
    if #hue_queue == 0 then
        -- what is on the arc first, so a colour pressed now has pictures under it; then the folder
        -- (the arc's list is the whole folder now, in the order it is walked: one pass covers it)
        -- (a video's colour is the index's to read, from its frame: magick cannot open one quickly)
        for _, p in ipairs(pictures) do if hues[p] == nil and not N.is_video(p) then hue_queue[#hue_queue + 1] = p end end
        if #hue_queue == 0 then return end
    end
    local batch = {}
    for i = 1, math.min(32, #hue_queue) do batch[i] = table.remove(hue_queue, 1) end
    -- a jpeg read at a sixty-fourth of its size: the same colour, in a third of the time
    hue_busy = true
    read_hues(batch, function(got)
        hue_busy = false
        if got > 0 then save_hues() end
        left = 0
        for _, p in ipairs(pool) do if hues[p] == nil and not N.is_video(p) then left = left + 1 end end
        if fact.nt_open and math.floor(tonumber(fact.nt_tab) or -1) == 3 then show_pictures() end
        if #hue_queue > 0 then after(120, pump_hues) end
    end)
end

local function read_pictures()
    local w = read("wallpapers.json")
    local folder = type(w) == "table" and type(w.folder) == "string" and w.folder or (HOME .. "/Pictures/wallpapers")
    where = folder:match("([^/]+)/*$") or folder
    -- and the live wallpapers' folders (D145: settings.walls.folders; a video is worn like a picture)
    local args, seen = { folder }, { [folder] = true }
    for _, f in ipairs(walls.normalize(settings.walls, HOME).folders) do
        if not seen[f] then seen[f] = true; args[#args + 1] = f end
    end
    for _, a in ipairs({ "-maxdepth", "1", "-type", "f" }) do args[#args + 1] = a end
    launch("find", args, function(out)
        -- the studio's folder can hold thousands: forty of them, drawn afresh each time the panel
        -- opens, so the arc is not the same first names over and over. The one on the desk stays in it.
        draws = draws + 1
        pool = N.pictures(out, 100000)
        pictures = N.draw(pool, #pool, os.time() + draws * 7919)
        local on = wearing()
        -- the one on the desk first, wherever the shuffle put it (or added, if it is not in the folder)
        if on then
            for i = #pictures, 1, -1 do if pictures[i] == on then table.remove(pictures, i) end end
            table.insert(pictures, 1, on)
        end
        show_pictures(true)
        pump_hues()
    end)
end
local wear
on("nt_wall", function(v)
    if wh and wh.on() then wh.wear(math.floor(tonumber(v) or -1)); return end
    local list = view()
    local p = list[base + (tonumber(v) or -1) + 1]
    if p then wear(p) end
end)
wear = function(p)
    text.wp_t = "WEARING " .. string.upper(p:match("([^/]+)$") or p) .. "…"
    -- the one way a wallpaper is worn (D145): mooi's desk draws it (a video: mpvpaper under it), with
    -- its transition grown out of the notch's edge; the theme watch recolours from its still
    launch("mooi", { "wall", "apply", p, "--from-y", tostring(math.floor(tonumber(fact.nt_cy) or 540)) }, function(out, code)
        if code == 0 then
            text.wp_t = N.is_video(p) and "WEARING IT · LIVE, THE PALETTE FOLLOWS" or "WEARING IT · THE PALETTE FOLLOWS"
            if fact.nt_open and math.floor(tonumber(fact.nt_tab) or -1) == 3 then show_pictures() end
        else
            text.wp_t = "COULD NOT WEAR IT · SEE `mooi wall apply`"
        end
    end)
end
-- a colour on the arc: that band of pictures, or, pressed again, all of them
on("nt_hue", function(v)
    local k = math.floor(tonumber(v) or -1)
    fact.wp_hue = k == band() and -1 or (k >= 0 and k < BAND_N and k or -1)
    fact.wp_c = 0
    if wh and wh.on() then wh.restart(); return end
    show_pictures(true)
end)

-- ── Wallhaven: the panel's second source (FOLDER · WALLHAVEN under its title) ──
-- The month's top list from wallhaven.cc (lib/notch: safe for work only, the screen's size and shape,
-- the arc's colour when one is chosen), a page of 24 at a time as the wheel nears the end of what is
-- loaded. Its small thumbnails are fetched and cut to the arc's 16:9 as they come near the middle and
-- kept in the data folder (wh-<id>.jpg). A press saves the full picture into the studio's folder as
-- wallhaven-<id>.<ext>, so it stays in the collection, and wears it as any other. Nothing is asked of
-- Wallhaven until its source is chosen.
wh = (function()
    local items, page, last, busy, seq = {}, 0, 1, false, 0
    local got, tried_t, queue, qbusy = {}, {}, {}, false
    local self = {}
    function self.on() return math.floor(tonumber(fact.wp_src) or 0) == 1 end
    local function folder()
        local w = read("wallpapers.json")
        return type(w) == "table" and type(w.folder) == "string" and w.folder or (HOME .. "/Pictures/wallpapers")
    end
    local function saved_as(it) return folder() .. "/wallhaven-" .. it.id .. "." .. it.ext end
    local fetch
    local function pump()
        if qbusy then return end
        local it = table.remove(queue, 1)
        if not it then return end
        qbusy = true
        local dst = data_folder .. "/wh-" .. it.id .. ".jpg"
        launch("curl", { "-fsL", "--max-time", "12", "-o", dst, it.thumb }, function(_, code)
            if code ~= 0 then qbusy = false; pump(); return end
            launch("magick", { dst, "-thumbnail", "320x180^", "-gravity", "center", "-extent", "320x180", "-quality", "82", dst }, function(_, mcode)
                qbusy = false
                if mcode == 0 then got[it.id] = true; if self.on() then self.show() end end
                pump()
            end)
        end)
    end
    local function need(near)
        for _, it in ipairs(near) do
            if not got[it.id] and not tried_t[it.id] then
                tried_t[it.id] = true
                local ok, there = pcall(sys.ask, "files.exists", "wh-" .. it.id .. ".jpg")
                if ok and there then got[it.id] = true else queue[#queue + 1] = it end
            end
        end
        while #queue > 24 do table.remove(queue, 1) end
        pump()
    end
    function self.show(recenter)
        local on = wearing()
        local at = recenter and 0 or (base + math.floor(tonumber(fact.wp_c) or 0))
        at = math.max(0, math.min(at, #items - 1))
        base = math.max(0, math.min(at - WIN // 2, #items - WIN))
        fact.wp_base, fact.wp_c = base, at - base
        local rows = {}
        for i = 1, math.min(WIN, #items - base) do
            local it = items[base + i]
            rows[i] = { pic = got[it.id] and (data_folder .. "/wh-" .. it.id .. ".jpg") or "",
                        name = "wallhaven " .. it.id .. (it.res ~= "" and (" · " .. it.res) or ""), on = on == saved_as(it) }
        end
        model.pics = rows
        local b = band()
        local colour = b >= 0 and (" · " .. BAND_WORD[b + 1]) or ""
        if busy and #items == 0 then text.wp_t = "ASKING WALLHAVEN…" .. colour
        elseif #items == 0 then text.wp_t = "NOTHING FROM WALLHAVEN" .. colour
        else text.wp_t = string.format("%d OF %d · WALLHAVEN · TOP OF THE MONTH%s%s", at + 1, #items, colour, page < last and " · MORE AS YOU TURN" or "") end
        local near = {}
        for d = 0, 8 do
            if items[at + 1 + d] then near[#near + 1] = items[at + 1 + d] end
            if d > 0 and items[at + 1 - d] then near[#near + 1] = items[at + 1 - d] end
        end
        need(near)
        if at >= #items - 8 then fetch() end
    end
    fetch = function()
        if busy or page >= last then return end
        busy = true
        seq = seq + 1
        local mine, first = seq, #items == 0
        local url = N.wallhaven_url(page + 1, band(), screen.full_w, screen.full_h)
        launch("curl", { "-fsL", "--max-time", "12", url }, function(out, code)
            if mine ~= seq then return end
            busy = false
            local list, pages = N.wallhaven_page(code == 0 and decode(out) or nil)
            if not list then
                if self.on() then text.wp_t = "WALLHAVEN DID NOT ANSWER · TRY AGAIN IN A MOMENT" end
                return
            end
            page, last = page + 1, pages
            for _, it in ipairs(list) do items[#items + 1] = it end
            if self.on() then self.show(first) end
        end)
    end
    -- a new search: the colour changed
    function self.restart()
        items, page, last, busy, queue = {}, 0, 1, false, {}
        seq = seq + 1
        base = 0
        model.pics = {}
        self.show(true)
        fetch()
    end
    function self.wear(k)
        local it = items[base + k + 1]
        if not it then return end
        local dst = saved_as(it)
        text.wp_t = "SAVING WALLHAVEN " .. string.upper(it.id) .. " TO " .. string.upper(folder():match("([^/]+)/*$") or "THE FOLDER") .. "…"
        launch("curl", { "-fsL", "--max-time", "60", "--create-dirs", "-o", dst, it.path }, function(_, code)
            if code ~= 0 then text.wp_t = "COULD NOT FETCH IT FROM WALLHAVEN"; return end
            wear(dst)
        end)
    end
    return self
end)()
on("nt_fav", function(v)
    local p = (view())[base + (tonumber(v) or -1) + 1]
    if not p then return end
    local doc = walls.toggle(read(walls.FAVS, "json"), p)
    pcall(sys.call, "files.write", walls.FAVS, json.encode(doc))
    fav_set, fav_list = walls.favs(doc)
    show_pictures(false)
end)
pcall(sys.watch, "files:" .. walls.FAVS, function()
    fav_set, fav_list = walls.favs(read(walls.FAVS, "json"))
    if fact.nt_open and math.floor(tonumber(fact.nt_tab) or -1) == 3 and not (wh and wh.on()) then show_pictures(false) end
end)
on("nt_src", function(v)
    v = math.floor(tonumber(v) or 0)
    local k = (v == 1 or v == 2) and v or 0
    if k == math.floor(tonumber(fact.wp_src) or 0) then return end
    fact.wp_src, fact.wp_c, fact.wp_hue = k, 0, -1
    base = 0
    if k == 1 then wh.restart() else show_pictures(true) end
end)
-- ── Weather: the shared cache and location memo, else open-meteo ──
local function show_weather(doc)
    local f = forecast.parse(doc.answer)
    if not f then return end
    local cur = weatherpanel.current(f)
    fact.wx_kind = cur.kind
    text.wx_temp = cur.temp
    text.wx_word = cur.word
    text.wx_feels = cur.feels
    text.wx_range = cur.range
    text.wx_place = string.upper(tostring(doc.city or ""))
    model.hrs = weatherpanel.hours(f, N.bars(f.hours))
    model.dys = weatherpanel.days(f)
    fact.wx_ok = true
end
local function read_weather()
    local cached = weathershare.cached(read, os.time())
    if cached then show_weather(cached) end
    local function fetch(url, done)
        launch("curl", { "-fsSL", "--max-time", "12", url }, function(out) done(decode(out)) end)
    end
    weathershare.refresh({ read = read, fetch = fetch,
                           write = function(name, doc) pcall(sys.call, "files.write", name, doc) end }, function(doc)
        if doc and doc ~= cached then show_weather(doc) end
    end)
end

-- ── GitHub: through `gh`, signed in as you; read when the panel opens, kept five minutes ──
local ghparse = require("lib/ghparse")
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
    url = ghparse.web_url(url)
    if url then launch("xdg-open", { url }); fact.nt_open, fact.nt_tab, fact.nt_pin = false, -1, false; viz() end
end)

-- ── Games: what is installed — Steam's libraries' manifests and the desktop's Game entries (D156) ──
-- Read when the panel opens and kept a minute. Steam's header pictures are already on disk with its
-- cache, so a row has a picture with nothing fetched; a press starts one and the notch folds away.
local gm_all, gm_list, gm_center, gm_base = {}, {}, 0, 0
local gm_read, gm_done = 0, false
local gm_steam, gm_desktops, gm_local, gm_headers, gm_icons, gm_hdr = nil, nil, nil, {}, {}, false
local GM_WIN = 12             -- the arc draws a window of the list; the logic slides it as the wheel turns
local function gm_show(recenter)
    gm_list = games.filter(gm_all, tonumber(fact.gm_src) or 0)
    gm_center = math.max(0, math.min(recenter and 0 or gm_center, math.max(0, #gm_list - 1)))
    local c = gm_center - gm_base
    if recenter or c < 0 or c > GM_WIN - 1 then
        gm_base = math.max(0, math.min(gm_center - GM_WIN // 2, math.max(0, #gm_list - GM_WIN)))
    end
    c = gm_center - gm_base
    fact.gm_base, fact.gm_c = gm_base, c
    local rows = {}
    for i = 1, math.min(GM_WIN, #gm_list - gm_base) do
        local g = gm_list[gm_base + i]
        rows[i] = { name = g.name, sub = g.sub, pic = g.pic, pictured = g.pic ~= "", steam = g.steam,
                    wide = g.wide == true, icon = g.icon == true }
    end
    model.gm = rows
    local s, l, a = 0, 0, 0
    for _, g in ipairs(gm_all) do
        if g.steam then s = s + 1 elseif g.disk then l = l + 1 else a = a + 1 end
    end
    text.gm_t = #gm_all > 0 and string.format("%d GAMES · %d STEAM · %d LOCAL · %d APPS", #gm_all, s, l, a) or ""
    text.gm_pos = #gm_list > 0 and string.format("%d OF %d · THE WHEEL TURNS THE ARC · A PRESS STARTS ONE", gm_center + 1, #gm_list)
                 or (fact.gm_ok and "NOTHING INSTALLED HERE" or "")
end
local gm_paint, gm_art   -- the pictures the cache holds, and the online pass, defined under each_find
local function gm_collect()
    if not (gm_steam and gm_desktops and gm_local and gm_hdr) then return end
    gm_all = games.collect(gm_steam, gm_desktops, gm_headers, gm_local, gm_icons, 500)
    gm_center, gm_base, gm_read, gm_done = 0, 0, os.time(), true
    fact.gm_ok = true
    gm_show(true)
    if gm_paint then gm_paint() end      -- the cache first: every collect, nothing fetched
    if gm_art then gm_art() end          -- then, at most every quarter hour, what is still bare
end
-- `find` over several starting points in turn (GNU find's -maxdepth is per run).
local function each_find(paths, args, done)
    local out, i = {}, 1
    local function step()
        local p = paths[i]
        if not p then done(table.concat(out)); return end
        i = i + 1
        local a = { p }
        for _, x in ipairs(args) do a[#a + 1] = x end
        probe("find", a, function(o) if o ~= "" then out[#out + 1] = o end; step() end)
    end
    step()
end
-- ── A picture for the games the machine has none of (asked for: "download proper icons online") ──
-- Steam's store search finds a game by its name; its CDN sends the capsule, which is the card's own
-- shape. Both answers are kept in ~/.cache/mooi/games — `<key>.json` for what the search said,
-- `<key>.jpg` for the picture — so a game is asked once and never again: a bare row is dressed from
-- that cache with nothing fetched, and only what is still bare goes online. Keyless, two curl calls a
-- game, once.
local GM_ART = HOME .. "/.cache/mooi/games"
local gm_tried, gm_art_at = {}, 0
gm_paint = function(done)
    probe("find", { GM_ART, "-maxdepth", "1", "-type", "f", "-name", "*.jpg", "-size", "+2k" }, function(o)
        games.dress(gm_all, games.online(o))
        gm_show()
        if done then done() end
    end)
end
local function gm_asked(done)     -- the games already asked, so a miss is not asked again every open
    probe("find", { GM_ART, "-maxdepth", "1", "-type", "f", "-name", "*.json", "-size", "+1c" }, function(o)
        done(games.asked(o))
    end)
end
gm_art = function()
    if os.time() - gm_art_at < 900 then return end
    gm_art_at = os.time()
    gm_paint(function()
        gm_asked(function(asked)
            local want = {}
            for _, g in ipairs(gm_all) do
                local k = games.slug(g.name)
                if games.bare(g) and not gm_tried[k] and #want < 24 then
                    gm_tried[k] = true
                    -- already asked once (its answer is in the cache): only the picture is missing
                    want[#want + 1] = { key = k, name = g.name, appid = g.steam and g.appid or nil,
                                        asked = asked[k] == true }
                end
            end
            if #want == 0 then return end
            local jobs = {}
            local function download(n)
                local j = jobs[n]
                if not j then gm_paint(); return end
                local urls = games.art_urls(j.appid)
                local function try(i)
                    if not urls[i] then download(n + 1); return end
                    launch("curl", { "-fsSL", "--max-time", "15", "--create-dirs", "-o", GM_ART .. "/" .. j.key .. ".jpg", urls[i] },
                        function(ok) if ok then download(n + 1) else try(i + 1) end end)
                end
                try(1)
            end
            local function found()   -- what the searches said: one `"name":"…","id":…` a game
                probe("grep", { "-rHoE", '"name":"[^"]*","id":[0-9]+', GM_ART }, function(o)
                    local by = {}
                    for line in o:gmatch("[^\n]+") do
                        local file, rest = line:match("^(.-%.json):(.*)$")
                        local key = file and file:match("([^/]+)%.json$")
                        local nm, id                            -- not `rest and match(...)`: an `and` keeps one value
                        if rest then nm, id = rest:match('^"name":"(.-)","id":(%d+)$') end
                        if key and nm and id then
                            by[key] = by[key] or {}
                            table.insert(by[key], { name = nm, id = id })
                        end
                    end
                    for _, w in ipairs(want) do
                        local id = w.appid or games.appid(by[w.key], w.name)
                        if id then jobs[#jobs + 1] = { key = w.key, appid = id } end
                    end
                    download(1)
                end)
            end
            -- a Steam game knows its own appid; the rest are asked by name, one at a time
            local i = 0
            local function ask()
                i = i + 1
                local w = want[i]
                if not w then found(); return end
                if w.appid or w.asked then ask(); return end
                probe("curl", { "-fsSL", "--max-time", "8", "--create-dirs", "-o", GM_ART .. "/" .. w.key .. ".json", games.search_url(w.name) },
                    function() ask() end)
            end
            ask()
        end)
    end)
end
local CACHE_ART = { "-maxdepth", "2", "(", "-name", "header.jpg", "-o", "-name", "library_header.jpg",
                    "-o", "-name", "library_600x900.jpg", ")", "-type", "f" }
local function read_games()
    if gm_done and os.time() - gm_read < 60 then return end
    gm_read = os.time()
    gm_steam, gm_desktops, gm_local, gm_headers, gm_icons, gm_hdr = nil, nil, nil, {}, {}, false
    -- where Steam lives: a package, the AUR's, the flatpak, the snap; each keeps its libraries'
    -- manifests in <library>/steamapps and its header pictures in <install>/appcache/librarycache
    local roots = {}
    for _, p in ipairs({ "/.local/share/Steam", "/.steam/steam", "/.steam/root",
                         "/.var/app/com.valvesoftware.Steam/.local/share/Steam", "/snap/steam/common/.local/share/Steam" }) do
        roots[#roots + 1] = HOME .. p
    end
    local ga = { "-h", "-E", '^[[:space:]]*"path"' }
    for _, r in ipairs(roots) do ga[#ga + 1] = r .. "/steamapps/libraryfolders.vdf" end
    probe("grep", ga, function(out)
        local libs, seen = {}, {}
        for _, p in ipairs(games.libraries(out)) do
            if not seen[p] then seen[p] = true; libs[#libs + 1] = p end
        end
        for _, r in ipairs(roots) do
            if not seen[r] then seen[r] = true; libs[#libs + 1] = r end
        end
        local dirs = {}
        for _, l in ipairs(libs) do dirs[#dirs + 1] = l .. "/steamapps" end
        each_find(dirs, { "-maxdepth", "1", "-name", "appmanifest_*.acf", "-type", "f" }, function(files_out)
            local cache = {}
            for _, r in ipairs(roots) do cache[#cache + 1] = r .. "/appcache/librarycache" end
            local function headers_done(h)
                gm_headers, gm_hdr = games.headers(h), true
                gm_collect()
            end
            local files = {}
            for line in files_out:gmatch("[^\n]+") do files[#files + 1] = line end
            if #files == 0 then
                gm_steam = ""
                each_find(cache, CACHE_ART, headers_done)
                return
            end
            local ma = { "-h", "-E", '^[[:space:]]*"(appid|name|installdir)"' }
            for _, f in ipairs(files) do ma[#ma + 1] = f end
            probe("grep", ma, function(manifests_out)
                gm_steam = manifests_out or ""
                each_find(cache, CACHE_ART, headers_done)
            end)
        end)
    end)
    -- the desktop's own: one grep over the menus, each entry's name, exec and categories
    local da = { "-rH", "--include=*.desktop", "-E", "^(Name|Exec|Categories|Icon|NoDisplay|Hidden|Terminal)=",
                 "/usr/share/applications", "/usr/local/share/applications", HOME .. "/.local/share/applications",
                 "/var/lib/flatpak/exports/share/applications", HOME .. "/.local/share/flatpak/exports/share/applications" }
    probe("grep", da, function(out)
        gm_desktops = out or ""
        -- the menus' icons, by name: one find for all of them, as big as the theme has them (PNG only)
        local names = games.icon_names(gm_desktops)
        if #names == 0 then gm_collect(); return end
        local args = { "-maxdepth", "5", "-type", "f", "(" }
        for i, n in ipairs(names) do
            if i > 1 then args[#args + 1] = "-o" end
            args[#args + 1] = "-iname"; args[#args + 1] = n .. ".png"
        end
        args[#args + 1] = ")"
        each_find({ "/usr/share/icons", HOME .. "/.local/share/icons",
                    "/var/lib/flatpak/exports/share/icons", HOME .. "/.local/share/flatpak/exports/share/icons" },
            args, function(o) gm_icons = games.icons(o); gm_collect() end)
    end)
    -- the folders somebody put on the disk: a launcher two levels under a root, deeper inside a
    -- PortProton prefix (drive_c\Games\<game>\<game>.exe), where the client keeps its own
    local function local_done(out) gm_local = out or ""; gm_collect() end
    each_find({ HOME .. "/games", HOME .. "/Games", HOME .. "/GOG Games", HOME .. "/GOG Games" },
        { "-mindepth", "2", "-maxdepth", "2", "-type", "f", "(", "-iname", "*.exe", "-o", "-iname", "*.sh",
          "-o", "-iname", "*.AppImage", "-o", "-iname", "*.x86_64", "-o", "-iname", "*.run",
          "-o", "-iname", "icon.png", "-o", "-iname", "logo.png", "-o", "-iname", "game.png",
          "-o", "-iname", "steam_icon.png", ")" },
        function(a)
            each_find({ HOME .. "/.local/share/PortProton/prefixes" },
                { "-maxdepth", "6", "-type", "f", "-iname", "*.exe" },
                function(b) local_done(a .. b) end)
        end)
end
on("nt_gsrc", function(v)
    fact.gm_src = math.max(0, math.min(3, math.floor(tonumber(v) or 0)))
    gm_show(true)
end)
on("nt_gscroll", function(v)
    gm_center = math.max(0, math.min(gm_center + math.floor(tonumber(v) or 0), math.max(0, #gm_list - 1)))
    gm_show()
end)
on("nt_game", function(v)
    local g = gm_list[gm_base + (tonumber(v) or -1) + 1]
    if not g then return end
    -- Steam's own URL: the client starts it as the game it is, Proton and all
    if g.steam then launch("xdg-open", { "steam://rungameid/" .. tostring(g.appid) })
    elseif g.disk then
        -- a folder on the disk: mooi's own launcher starts it (its script, AppImage, wine or PortProton)
        local args = { "game", tostring(g.dir) }
        if g.exe and g.exe ~= "" then args[#args + 1] = tostring(g.exe) end
        if g.proton then args[#args + 1] = "--proton" end
        launch("mooi", args)
    else launch("gtk-launch", { tostring(g.id) }) end
    fact.nt_open, fact.nt_tab, fact.nt_pin = false, -1, false
    viz()
end)

-- ── Opening a panel: read what it shows ──
local READ = { [2] = function() read_screen(read_spaces) end, [3] = read_pictures, [4] = read_weather, [5] = read_github,
               [6] = read_games }
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
-- The Wallpapers panel's button (audit 2026-11-01, A6): `nt_studio` was emitted by the scene and
-- handled nowhere, so the button did nothing. The studio is a program of its own; the launcher
-- opens it (it is on this scene's allowlist).
on("nt_studio", function() launch("mooi", { "walls" }) end)
on("nt_close", function() fact.nt_open, fact.nt_tab, fact.nt_pin, fact.nt_deck = false, -1, false, false; viz() end)
read_weather()
after(4000, read_github)        -- the badge of what waits on GitHub, read once at the start
every(600000, function() gh_at = 0; read_github() end)
