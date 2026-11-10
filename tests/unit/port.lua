-- The k4 / Minflair port (docs/superpowers/specs/2026-11-10-k4-minflair-port-design.md): its pure helpers and the
-- wiring that ties them to the node. Loaded by tests/unit/run.lua with its section, test and eq.
local section, test, eq = ...
local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end

section("the gauge (D265, Minflair's OSD)")
do
    local GA = require("lib/node/gauge")
    test("each reading has its icon, words and fill", function()
        local v = GA.volume(0.42, false); eq(v.label, "VOLUME 42%"); eq(v.level, 0.42)
        eq(GA.volume(0.9, true).label, "MUTED"); eq(GA.volume(0.9, true).level, 0)
        eq(GA.volume(0, false).icon, "󰕿")
        eq(GA.light(0.7).label, "BRIGHTNESS 70%")
        eq(GA.mic(true).label, "MICROPHONE OFF"); eq(GA.mic(true).warm, true); eq(GA.mic(false).level, 1)
        eq(GA.cable(true, 54.4).label, "CHARGING · 54%"); eq(GA.cable(false, nil).label, "ON BATTERY")
    end)
    test("mooi osd's codes: tens say which, units whether it is on", function()
        eq(GA.decode(11).label, "CAPS LOCK ON"); eq(GA.decode(10).label, "CAPS LOCK OFF")
        eq(GA.decode(21).label, "NUM LOCK ON"); eq(GA.decode(31).label, "GAME MODE ON")
        eq(GA.decode(0), nil); eq(GA.decode(99), nil)
    end)
    test("the node watches the light and the mutes, and the scene may ask for the light", function()
        local l, g = read("shell/mooi-node.luau"), read("tools/gen-node.py")
        assert(l:find('pcall(sys.watch, "brightness", function(b)', 1, true))
        assert(l:find("if mic ~= N.mic_muted then gauge(GA.mic(mic)) end", 1, true))
        assert(l:find('on("nd_osd", function(v) gauge(GA.decode(v)); render() end)', 1, true))
        assert(g:find('"battery", "brightness", "network"', 1, true), "the brightness service is declared")
        assert(read("shell/mooi-node.plm"):find("event nd_osd ->", 1, true))
        assert(read("bin/mooi"):find('"$pleamar" --say mooi-node "emit nd_osd $n"', 1, true))
    end)
end

section("the shortcut sheet (D267, k4's and Minflair's Super+K)")
do
    local KS = require("lib/node/keysheet")
    test("modifiers and keys are written as people say them", function()
        eq(KS.label(65, "S"), "Super + Shift + S"); eq(KS.label(76, "Return"), "Super + Ctrl + Alt + Return")
        eq(KS.label(0, "XF86AudioMute"), "Mute"); eq(KS.label(64, "mouse:272"), "Super + Left button")
        eq(KS.label(64, "SUPER_L"), "Super (alone)"); eq(KS.label(64, "comma"), "Super + ,")
    end)
    test("a combo as written and a bind as Hyprland holds it meet in one id", function()
        eq(KS.parse("SUPER + SHIFT + q"), KS.id(65, "q")); eq(KS.parse("ALT + F12"), "8:F12")
        eq(KS.parse("SUPER + ALT + mouse:273"), "72:MOUSE:273"); eq(KS.parse(""), nil)
        eq(KS.combo_of('mainMod .. " + SHIFT + " .. key'), "SUPER + SHIFT + *")
        eq(KS.combo_of('"CTRL + ALT + D"'), "CTRL + ALT + D"); eq(KS.combo_of("k[1]"), nil)
    end)
    test("the config's words: a --- comment covers the binds under it, until new code or a blank line", function()
        local text = table.concat({
            "--- volume up (XF86 + ALT fallback share one command)",
            'hl.bind("ALT + F12", hl.dsp.exec_cmd(volUp), { locked = true })',
            'hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(volUp),',
            "    { locked = true })",
            "",
            'hl.bind(mainMod .. " + Q", hl.dsp.window.close())',
            "for i = 1, 10 do",
            "    --- switch Workspace [key]",
            "    --- (the why, never the name)",
            '    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))',
            "end",
            "-- a plain comment",
            'pcall(hl.bind, "SUPER + W", hl.dsp.exec_cmd(mooi .. " walls"))',
            '        { "SUPER + r", "system" },                   -- the system panel (its right panel)',
            '        { "SUPER + J", "jump" },                     -- jump somewhere: far',
        }, "\n")
        local w = KS.words(text, function(c) return ({ walls = "Wallpapers", system = "System controls" })[c] end)
        eq(w["8:F12"], "volume up", "no parenthesis"); eq(w["0:XF86AUDIORAISEVOLUME"], "volume up", "the comment reaches the second bind")
        eq(w["64:Q"], nil, "a blank line ended it"); eq(w["64:*"], "switch workspace [key]", "one capital, at the row")
        eq(w["64:W"], "Wallpapers", "mooi's name for a mooi command"); eq(w["64:R"], "System controls")
        eq(w["64:J"], "jump somewhere", "a trailing comment, up to its colon")
    end)
    test("rows: Hyprland's binds in words, Super's first, guessed where nothing names them", function()
        local binds = {
            { modmask = 64, key = "1", dispatcher = "HL.Dispatcher(focus)" },
            { modmask = 68, key = "2", dispatcher = "HL.Dispatcher(move)" },
            { modmask = 64, key = "Q", dispatcher = "HL.Dispatcher(close)" },
            { modmask = 64, key = "Q", dispatcher = "HL.Dispatcher(close)" },
            { modmask = 0, key = "Caps_Lock", dispatcher = "HL.Dispatcher(exec_cmd)" },
            { modmask = 64, key = "mouse:272", dispatcher = "HL.Dispatcher(drag)" },
            { modmask = 64, key = "X", dispatcher = "x", has_description = true, description = "from Hyprland" },
            { modmask = 64, key = "Z", dispatcher = "HL.Dispatcher(exec_cmd)", submap = "resize" },
        }
        local rows = KS.rows(binds, { ["64:*"] = "Switch workspace [key]", ["64:MOUSE:272"] = "move to next workspace" })
        eq(#rows, 7, "one row a bind")
        eq(rows[#rows - 1].keys, "Super + 1"); eq(rows[#rows - 1].what, "Switch workspace 1", "the numbers last")
        eq(rows[1].keys, "Super + Left button", "Super's binds first"); eq(rows[5].keys, "Caps Lock", "then the rest")
        local by = {}; for _, r in ipairs(rows) do by[r.keys] = r.what end
        eq(by["Super + Ctrl + 2"], "Window to workspace 2"); eq(by["Super + Q"], "Close the window")
        eq(by["Super + Left button"], "Move the window", "a drag is a drag, whatever the comment says")
        eq(by["Super + X"], "From Hyprland"); eq(by["Super + Z"], "Runs a command (in resize)")
        eq(#KS.filter(rows, "super work"), 2); eq(#KS.filter(rows, "  "), 7); eq(#KS.filter(rows, "nothing"), 0)
    end)
    test("mooi's commands by Settings' names, then its own list", function()
        local D = require("lib/desktop")
        eq(KS.mooi_name("node keys", D.ACTIONS), "The Pill: shortcuts"); eq(KS.mooi_name("walls", D.ACTIONS), "Wallpapers")
        eq(KS.mooi_name("nothing", D.ACTIONS), nil)
    end)
    test("Super+K opens the sheet in the panel; it reads Hyprland and the config each time", function()
        local l, p = read("shell/mooi-node.luau"), read("shell/mooi-node.plm")
        eq(require("lib/config").defaults().keys.node_keys, "SUPER + K")
        assert(read("bin/mooi"):find("keys) n=6", 1, true) and read("bin/mooi"):find("keys-text)", 1, true))
        assert(l:find('run("hyprctl", { "binds", "-j" }', 1, true) and l:find('run("mooi", { "keys-text" }', 1, true))
        assert(l:find('if N.panel == "keys" then N.kq, N.ksc, text.nd_kq = "", 0, ""; load_keys() end', 1, true))
        assert(p:find("show: nd_kind == 13 and nd_pgp == 10", 1, true) and p:find("input nd_kq", 1, true))
        assert(p:find("on change nd_kb while nd_kb and nd_kind == 13 and nd_pgp == 10 { focus nd_kq }", 1, true))
    end)
end

section("the node's logic names only what Pleamar gives it (D267 fix)")
do
    test("every global the node's logic reads is one of the runtime's: a local used before it is declared is not", function()
        local p = io.popen("luac5.4 -l -l -p shell/mooi-node.luau 2>/dev/null")
        local listing = p and p:read("a") or ""
        if p then p:close() end
        if listing == "" then return end   -- no luac5.4 here (CI's image): the gate's parse still runs
        local ok = {}
        for _, g in ipairs({ "N", "fact", "text", "model", "on", "run", "every", "after", "sys", "json", "sound", "require",
                             "math", "string", "table", "os", "pairs", "ipairs", "type", "tonumber", "tostring", "pcall" }) do ok[g] = true end
        for g in listing:gmatch('[GS]ETTABUP[^\n]-_ENV "([%w_]+)"') do
            assert(ok[g], "the node's logic reads a global it is not given: " .. g)
        end
    end)
end

section("SSH hosts and packages in the search line (D268; k4's and Minflair's)")
do
    local SSH, PK = require("lib/node/ssh"), require("lib/node/pkgs")
    test("hosts: plain names only, each once, with where they go", function()
        local h = SSH.hosts(table.concat({
            "Host *", "  ServerAliveInterval 30", "Host box nas", "  HostName 10.0.0.2", "Host  pi.local",
            "  hostname=pi.lan", "Host !bad web-? me;rm", "Match host x", "  HostName nowhere", "host box",
        }, "\n"))
        eq(#h, 3); eq(h[1].name, "box"); eq(h[1].to, "10.0.0.2"); eq(h[2].name, "nas"); eq(h[3].to, "pi.lan")
        eq(SSH.safe("me;rm"), false); eq(SSH.safe("-oProxyCommand=x"), false); eq(SSH.safe("pi.local"), true)
    end)
    test("hosts match by name, by where they go, or all under `ssh`", function()
        local h = SSH.hosts("Host box\n HostName 10.0.0.2\nHost nas\n HostName storage.lan\n")
        eq(SSH.match(h, "box")[1].host, "box"); eq(SSH.match(h, "storage")[1].host, "nas")
        eq(#SSH.match(h, "ssh", 5), 2); eq(SSH.match(h, "ssh n")[1].host, "nas"); eq(#SSH.match(h, "zzz"), 0)
        eq(SSH.match(h, "box")[1].kind, "ssh")
    end)
    test("a package search is asked for with `pkg`, `pacman` or `aur`, and only with words", function()
        eq(PK.query("pkg firefox"), "firefox"); eq(PK.query("pkg: rip grep "), "rip grep"); eq(PK.query("aur yay-bin"), "yay-bin")
        eq(PK.query("pkg -Syu"), nil); eq(PK.query("pkg a;b"), nil); eq(PK.query("pkgfoo"), nil); eq(PK.query("pkg "), nil)
        eq(PK.safe_name("lib32-gcc-libs"), true); eq(PK.safe_name("-x"), false); eq(PK.safe_name("a b"), false)
    end)
    test("rows: the repositories', then the AUR's best two, installed marked", function()
        local out = table.concat({
            "## repo",
            "extra/ripgrep 15.2.0-1 [installed]", "    A search tool", "extra/repgrep 0.17.1-1", "    A replacer",
            "extra/a 1-1", "    x", "extra/b 1-1", "    x", "extra/c 1-1", "    x",
            "## aur",
            "aur/ripgrep-all-git 0.10-1 [+2 ~0.00]", "    rga", "aur/rg-bin 1-1 [+0 ~0.00] [Installed]", "    bin",
        }, "\n")
        local r = PK.parse(out, 5)
        eq(#r, 5); eq(r[1].pkg, "ripgrep"); eq(r[1].tag, "EXTRA · INSTALLED"); eq(r[1].name, "ripgrep — A search tool")
        eq(r[4].source, "aur"); eq(r[4].tag, "AUR"); eq(r[5].tag, "AUR · INSTALLED")
        eq(#PK.parse("## repo\n## aur\n"), 0)
        eq(PK.parse(out, 5, "repgrep")[1].pkg, "repgrep", "the exact name first")
    end)
    test("choosing opens the terminal on `mooi pkg install` or `ssh HOST`, checked again", function()
        local l = read("shell/mooi-node.luau")
        assert(l:find('in_terminal({ "pkg", "install", a.pkg, a.source == "aur" and "aur" or "repo" })', 1, true))
        assert(l:find('elseif a.kind == "ssh" and SSH.safe(a.host) then', 1, true))
        assert(l:find('if not tostring(w):match("^[%w@%._%+%-]+$") then return end', 1, true), "every word checked")
        local b = read("bin/mooi")
        assert(b:find('sudo pacman -S -- "$name"', 1, true) and b:find('"$h" -S -- "$name"', 1, true))
        assert(b:find("case \"$q\" in ''|-*)", 1, true), "an option is never a query")
        eq(require("lib/node/commands").match("update the system")[1].term, true)
    end)
end

section("the System page's GPU and disk (D270, Minflair's)")
do
    local SX = require("lib/node/sysextra")
    test("readings from the kernel's busy file, nvidia-smi and df", function()
        eq(SX.busy("48\n"), 48); eq(SX.busy("7\n12\n"), 7, "the first card"); eq(SX.busy("[N/A]"), nil); eq(SX.busy(""), nil)
        eq(SX.busy("250"), 100, "held to 100")
        local d = SX.disk("Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/nvme0n1p2 498008372 362050468 132614524 74% /home\n")
        eq(d.pct, 74); eq(d.size, 498008372 * 1024)
        eq(SX.disk("df: /nowhere: No such file"), nil); eq(SX.disk(""), nil)
        eq(#SX.BUSY, 4); eq(SX.BUSY[2], "/sys/class/drm/card1/device/gpu_busy_percent")
    end)
    test("asked only while the System page is open; seven cards; the GPU card opens btop", function()
        local l, g = read("shell/mooi-node.luau"), read("tools/gen-node.py")
        assert(l:find('every(2000, function() if N.kind == "panel" and (N.panel == "system" or N.panel == "home") then poll_extra() end end)', 1, true))
        assert(l:find('if row < 1 or (row > 3 and row ~= 6) then return end', 1, true))
        assert(g:find('"hyprctl", "df", "nvidia-smi"', 1, true), "the two commands are allowed")
        eq(require("lib/node/geometry").PANEL_H.system, 520)
    end)
end

section("Super is the Pill's again: holding it opens the Subsurface only when asked (D271)")
do
    test("hold is its own switch, off; Super+Alt+U opens the Overview on purpose", function()
        local c = require("lib/config").defaults()
        eq(c.surface.hold, false); eq(c.keys.surface, "SUPER + ALT + U")
        local l = read("shell/mooi-surface.luau")
        assert(l:find('on("rv_down", function()\n    if not hold_on() then return end', 1, true), "a Super press does nothing without hold")
        assert(l:find('on("rv_overview", function()', 1, true) and l:find("if SF.want_full then", 1, true))
        assert(read("bin/mooi"):find('overview) "$pleamar" --say mooi-surface "emit rv_overview"', 1, true))
        local g = read("tools/gen-settings.py")
        assert(g:find('"Hold Super to open it"', 1, true) and g:find('"surface.hold", "sv_surface_hold"', 1, true))
    end)
end

section("the panel's Home tells more (D272)")
do
    local HM = require("lib/node/home")
    test("the header's words: weather, battery, date, readings", function()
        local g, t = HM.weather_line({ temperature_2m = 19.6, weather_code = 2 }); eq(g, "󰖕"); eq(t, "20° · Partly cloudy")
        eq(select(2, HM.weather_line({ temperature_2m = 3, weather_code = 63 })), "3° · Rain"); eq(HM.weather_line(nil), "")
        eq(HM.battery(54.4, true), "󰂄 54%"); eq(HM.battery(96, false), "󰁹 96%"); eq(HM.battery(4, false), "󰁺 4%"); eq(HM.battery(nil), "")
        eq(HM.reading("CPU", 20.4), "CPU 20%"); eq(HM.reading("TEMP", 80, "°"), "TEMP 80°"); eq(HM.reading("GPU", nil), "GPU —")
        eq(HM.date(os.time({ year = 2026, month = 11, day = 10, hour = 12 })), "Tuesday 10 November")
    end)
    test("Home: the header and strip, five toggles with game mode, brightness from its service", function()
        local p, l = read("shell/mooi-node.plm"), read("shell/mooi-node.luau")
        assert(p:find("text nd_hclock {", 1, true) and p:find("text nd_hs4 {", 1, true))
        assert(p:find("zone box pt5 {", 1, true) and p:find('label: "Game mode"', 1, true))
        assert(l:find("fact.nd_hasbri = N.light ~= nil", 1, true))
        assert(l:find('run("mooi", { "game-mode" }', 1, true))
        eq(require("lib/node/geometry").PANEL_H.home, 732)
    end)
end

section("the side drawers (D275, Minflair's Convex panels)")
do
    local DR = require("lib/drawers")
    local function viewer(days)
        local weeks = {}
        for w = 1, 30 do
            local d = {}
            for k = 1, 7 do d[k] = { contributionCount = days and days(w, k) or 0 } end
            weeks[w] = { contributionDays = d }
        end
        return { login = "someone", name = "Some One", bio = "hi", avatarUrl = "https://avatars.githubusercontent.com/u/1",
                 followers = { totalCount = 3 },
                 repositories = { totalCount = 2, nodes = { { name = "a", stargazerCount = 1, forkCount = 0, primaryLanguage = { name = "Lua" } },
                                                            { name = "b", description = "best", stargazerCount = 5, forkCount = 2 } } },
                 contributionsCollection = { contributionCalendar = { totalContributions = 1234, weeks = weeks } } }
    end
    test("GitHub's answer becomes the card: four numbers and the starred-most repository", function()
        local g = DR.github(viewer())
        eq(g.login, "someone"); eq(g.name, "Some One"); eq(g.contributions, 1234); eq(g.repos, 2); eq(g.followers, 3); eq(g.stars, 6)
        eq(g.top.name, "b"); eq(g.top.desc, "best"); eq(g.top.lang, "")
        eq(DR.github(nil), nil); eq(DR.github({}), nil)
        eq(DR.short(1234), "1.2k"); eq(DR.short(45678), "45k"); eq(DR.short(12), "12")
    end)
    test("the grid: the last 26 weeks, levels 0 to 4 by the busiest day", function()
        local h = DR.heat(viewer(function(w, k) return w == 30 and k == 7 and 8 or (w == 30 and k == 6 and 2 or 0) end))
        eq(#h, 26 * 7); eq(h[#h].v, 4); eq(h[#h - 1].v, 1); eq(h[1].v, 0)
        eq(#DR.heat(nil), 0)
    end)
    test("updates, a quote for the day, the notices from the bar's feed", function()
        eq(DR.updates({ total = 0 }), "Up to date"); eq(DR.updates({ total = 1 }), "1 update waiting")
        eq(select(2, DR.updates({ total = 21 })), 21); eq(DR.updates(nil), "Not checked yet")
        local q1, a1 = DR.quote(0); local q2 = DR.quote(3600); local q3 = DR.quote(86400)
        eq(q1, q2, "the same all day"); assert(q1 ~= q3, "another the next"); assert(a1 ~= "")
        local rows, n = DR.notices({ count = 9, items = { { app = "firefox", title = "Done", body = "a\n b", ago = "1 min", actions = { "Open" } } } })
        eq(#rows, 1); eq(n, 9); eq(rows[1].app, "FIREFOX"); eq(rows[1].body, "a b"); eq(rows[1].act, "Open")
    end)
    test("the program: started by the bar, opened by Super+D and Super+N, its settings on their own page", function()
        local c = require("lib/config").defaults()
        eq(c.keys.drawer_left, "SUPER + D"); eq(c.keys.drawer_right, "SUPER + N"); eq(c.drawers.on, true); eq(c.drawers.edge, false)
        assert(read("shell/mooi.luau"):find('spawn("pleamar", SURFACE.args(shell_dir() .. "/mooi-drawers.plm")', 1, true))
        assert(read("bin/mooi"):find('"$pleamar" --say mooi-drawers "emit dr_cmd $n"', 1, true))
        local p = read("shell/mooi-drawers.plm")
        assert(p:find("event dr_cmd ->", 1, true) and p:find("keyboard: exclusive while dr_open > 0", 1, true))
        assert(read("tools/gen-settings.py"):find('("Side drawers", "Side drawers"', 1, true))
        -- the notices are the bar's: the drawer reads its feed and never receives notifications itself
        assert(not read("shell/mooi-drawers.luau"):find('sys.watch, "notifications"', 1, true))
    end)
end

section("the arcade and Snake (D276; k4's games, ported as mooi's own)")
do
    local SN = require("lib/arcade/snake")
    test("a new game: four long, heading right, food on a free cell, the same for the same seed", function()
        local a, b = SN.new(42), SN.new(42)
        eq(#a.body, 4); eq(a.dir, "right"); eq(a.body[1].x, SN.W // 2)
        eq(a.food.x, b.food.x); eq(a.food.y, b.food.y)
        for _, c in ipairs(a.body) do assert(not (c.x == a.food.x and c.y == a.food.y), "food never on the snake") end
    end)
    test("it moves, eats and grows by two, and never turns straight back", function()
        local st = SN.new(1)
        st.food = { x = st.body[1].x + 1, y = st.body[1].y }
        eq(SN.step(st), "ate"); eq(st.score, 1)
        SN.step(st); SN.step(st)
        eq(#st.body, 6, "grown by two")
        SN.turn(st, "left"); SN.step(st); eq(st.dir, "right", "no reversing")
        SN.turn(st, "up"); SN.step(st); eq(st.dir, "up")
    end)
    test("a wall or its own body ends it; the cell the tail leaves is free", function()
        local st = SN.new(1, 6, 4)
        local r
        for _ = 1, 10 do r = SN.step(st); if r == "dead" then break end end
        eq(r, "dead"); eq(st.alive, false)
        -- a square of four chasing its tail never bites it
        local sq = SN.new(1, 5, 5)
        sq.body = { { x = 1, y = 1 }, { x = 1, y = 2 }, { x = 2, y = 2 }, { x = 2, y = 1 } }
        sq.dir, sq.next_dir, sq.food = "right", "right", { x = 4, y = 4 }
        eq(SN.step(sq), "moved", "into the tail's cell as it leaves")
        eq(SN.interval({ score = 0 }), 140); eq(SN.interval({ score = 100 }), 60)
    end)
    test("the arcade: Super+G opens it, started on demand; Snake is in its picker and the search line", function()
        eq(require("lib/config").defaults().keys.arcade, "SUPER + G")
        assert(read("bin/mooi"):find('"$pleamar" --say mooi-arcade "emit ac_cmd 1"', 1, true))
        local l = read("shell/mooi-arcade.luau")
        assert(l:find('{ id = "snake", name = "Snake"', 1, true) and l:find("sn_gen = sn_gen + 1", 1, true))
        assert(read("shell/mooi-arcade.plm"):find("keyboard: exclusive while ac_page > 0", 1, true))
        eq(require("lib/node/commands").match("games")[1].args[1], "arcade")
    end)
end

section("La Grieta (D283; k4's typing roguelike, written fresh for mooi)")
do
    local GR = require("lib/arcade/grieta")
    test("the crack's words: three to nine letters, each once, and a pool of some three hundred", function()
        assert(#GR.WORDS >= 300, "the built-in list is a pool, not a handful: " .. #GR.WORDS)
        local seen = {}
        for _, w in ipairs(GR.WORDS) do
            assert(#w >= 3 and #w <= 9, "a word of the crack: " .. w)
            assert(not seen[w], "a word twice: " .. w); seen[w] = true
            assert(w:match("^[a-z]+$"), "letters only: " .. w)
        end
    end)
    test("a new game: ready, three lives, wave one; the same seed spills the same first word", function()
        local a, b = GR.new(42), GR.new(42)
        eq(a.state, "ready"); eq(a.lives, 3); eq(a.wave, 1); eq(a.score, 0)
        eq(GR.start(a), true); eq(a.state, "playing"); GR.start(b)
        GR.tick(a, 1000); GR.tick(b, 1000)
        eq(#a.words, #b.words); eq(a.words[1].text, b.words[1].text); eq(a.words[1].x, b.words[1].x)
    end)
    test("typing: a prefix holds, the exact word seals for its letters times the wave, a wrong letter flashes", function()
        local st = GR.new(1); GR.start(st)
        st.words = { { id = 1, text = "cat", x = 20, y = 10, speed = 1 } }
        eq(GR.type(st, "c"), "typed"); eq(st.typed, "c")
        eq(GR.type(st, "a"), "typed"); eq(st.typed, "ca")
        eq(GR.type(st, "z"), "wrong"); assert(st.flash > 0); eq(st.typed, "ca")
        local r, word, gain = GR.type(st, "t")
        eq(r, "sealed"); eq(word, "cat"); eq(gain, 3); eq(st.score, 3); eq(#st.words, 0); eq(st.typed, "")
        eq(GR.backspace({ typed = "ab" }), "a")
    end)
    test("a word at the line costs a life; the last one ends it; clearing a wave offers three of four", function()
        local st = GR.new(2); GR.start(st)
        st.spawn_left = 0
        st.words = { { id = 1, text = "dog", x = 20, y = 83, speed = 10 } }
        local ev = GR.tick(st, 300)
        eq(st.lives, 2); eq(#st.words, 0)
        eq(ev[1].kind, "hit"); eq(st.state, "choose"); eq(#st.options, 3)
        eq(GR.select(st, 1), 1); eq(GR.select(st, 1), 2)
        local st2 = GR.new(2); GR.start(st2); st2.lives = 1; st2.spawn_left = 0
        st2.words = { { id = 1, text = "dog", x = 20, y = 83, speed = 10 } }
        GR.tick(st2, 300); eq(st2.state, "over"); eq(st2.lives, 0)
    end)
    test("upgrades: slow, life, long words and a Tab charge; choosing one begins the next wave", function()
        local st = GR.new(3); GR.start(st)
        st.state, st.options = "choose", { { id = "slow" }, { id = "life" }, { id = "long" } }
        eq(GR.choose(st, 0), "slow"); eq(st.slow, 1); eq(st.wave, 2); eq(st.state, "playing")
        local base = st.base_speed
        GR.spawn(st, "cat"); assert(st.words[1].speed < base)
        st.state, st.options = "choose", { { id = "life" } }; st.lives = 2
        GR.choose(st, 0); eq(st.lives, 3)
        st.state, st.options = "choose", { { id = "long" } }; st.wave = 2
        GR.choose(st, 0); eq(GR.worth(st, "seventh"), 7 * 3 * 2)
        st.state, st.options = "choose", { { id = "seal" } }
        GR.choose(st, 0); eq(st.charges, 1)
        st.words = { { id = 1, text = "cat", x = 1, y = 1, speed = 1 } }
        local sum = GR.use_seal(st); eq(sum, 3 * st.wave); eq(st.charges, 0); eq(#st.words, 0)
    end)
end

section("Mazmorra (D284; k4's idle dungeon, written fresh for mooi)")
do
    local MZ = require("lib/arcade/mazmorra")
    test("a new run: floor one, the hero whole, a monster with a bar, the same for the same seed", function()
        local a, b = MZ.new(42), MZ.new(42)
        eq(a.floor, 1); eq(a.best, 1); eq(a.hero_hp, MZ.hero_max(a)); assert(a.monster.hp > 0)
        MZ.tick(a, 60); MZ.tick(b, 60)
        eq(a.floor, b.floor); eq(a.gold, b.gold); eq(a.monster.hp, b.monster.hp); eq(a.log[1], b.log[1])
    end)
    test("fights resolve by the second: the monster falls, gold drops, the floor rises and is the best", function()
        local st = MZ.new(1)
        local hp = st.monster.hp
        MZ.tick(st, 1); assert(st.monster.hp < hp)
        st.monster.hp = 1
        MZ.tick(st, 1)
        eq(st.floor, 2); eq(st.best, 2); assert(st.gold > 0)
        assert(st.log[1]:find("falls", 1, true) and st.log[1]:find("gold", 1, true))
    end)
    test("every tenth floor is a boss; its fall is the floor the hero returns to", function()
        local st = MZ.new(1); st.floor = 10; MZ.spawn(st)
        eq(st.monster.boss, true); assert(st.monster.name:find("Elder", 1, true))
        st.monster.hp = 1
        MZ.tick(st, 1)
        eq(st.floor, 11); eq(st.last_boss, 10)
    end)
    test("death returns the hero to the last boss floor, whole again", function()
        local st = MZ.new(1); st.floor, st.last_boss = 11, 10; MZ.spawn(st)
        st.hero_hp, st.monster.dmg, st.atk = 1, 99, 0
        MZ.tick(st, 1)
        eq(st.floor, 10); eq(st.hero_hp, MZ.hero_max(st)); assert(st.deaths > 0)
    end)
    test("buying needs the gold; costs rise; health fills the new bar", function()
        local st = MZ.new(7); st.gold = 0
        eq(MZ.cost(0), 12); eq(MZ.cost(1), 25); eq(MZ.cost(2), 44)
        eq(MZ.buy(st, 0), false)
        st.gold = 10000; local first = MZ.price(st, 1)
        eq(MZ.buy(st, 1), true); eq(st.hp, 1); eq(st.hero_hp, MZ.hero_max(st))
        assert(MZ.price(st, 1) > first, "the next costs more")
        eq(MZ.buy(st, 9), false)
    end)
    test("time away is fought through, capped at eight hours, and the last time moves to now", function()
        local st = MZ.new(2); local now = 10 ^ 9
        st.last = now - 20 * 3600
        eq(MZ.offline(st, now), 8 * 3600); eq(st.last, now)
        st.last = now - 30
        eq(MZ.offline(st, now), 30)
    end)
    test("Space doubles speed for thirty seconds, then rests for two minutes", function()
        local st = MZ.new(3)
        eq(MZ.boost(st), true); eq(st.boost, 30)
        MZ.tick(st, 31); eq(st.boost, 0); assert(st.rest >= 118 and st.rest <= 120)
        eq(MZ.boost(st), false)
        MZ.tick(st, 120); eq(st.rest, 0); eq(MZ.boost(st), true)
    end)
    test("a saved run comes back with its floor, gold and monster", function()
        local st = MZ.new(5); st.floor, st.gold, st.hp = 7, 123, 2
        local back = MZ.restore({ floor = st.floor, gold = st.gold, hp = st.hp, seed = 5, hero_hp = 1, log = {}, version = 1 })
        eq(back.floor, 7); eq(back.gold, 123); eq(MZ.hero_max(back), MZ.hero_max(st)); assert(back.monster.hp > 0)
        eq(MZ.restore({}), nil); eq(MZ.restore(nil), nil)
    end)
end

section("the arcade's two new games on their pages (D283, D284)")
do
    test("the picker knows them, their pages are drawn, and the logic has both games' state", function()
        local l, p, g = read("shell/mooi-arcade.luau"), read("shell/mooi-arcade.plm"), read("tools/gen-arcade.py")
        assert(l:find('{ id = "grieta", name = "La Grieta"', 1, true) and l:find("page = 3, ready = true", 1, true))
        assert(l:find('{ id = "mazmorra", name = "Mazmorra"', 1, true) and l:find("page = 4, ready = true", 1, true))
        assert(l:find("MAZMORRA.offline(mz, os.time())", 1, true) and l:find("MAZMORRA.buy(mz, i)", 1, true))
        assert(p:find("show: ac_page == 3", 1, true) and p:find("show: ac_page == 4", 1, true))
        assert(p:find("for w in gz", 1, true) and p:find("for u in gzu", 1, true))
        assert(p:find("zone box gzu", 1, true) and p:find("zone box mzu", 1, true))
        assert(p:find("for l in mzlog", 1, true) and p:find("for u in mzshop", 1, true))
        assert(p:find("emit ac_key(49 + u.index)", 1, true), "the upgrades and the shop are pressed through the key event")
        assert(p:find("event ac_key ->", 1, true) and p:find("keyboard: exclusive while ac_page > 0", 1, true))
        assert(g:find('"KP_1"', 1, true) and g:find('"KP_4"', 1, true), "the number keys are bound where the language allows")
        assert(l:find("mazmorra = A.maz", 1, true), "the run is saved under mazmorra")
    end)
end

section("where the sound plays, from Home (D277; k4's per-device sound)")
do
    local GA = require("lib/node/gauge")
    test("outputs: the next round the list, their names short, the gauge says which", function()
        local outs = { { id = 1, name = "Ryzen HD Audio Controller Speaker", default = true }, { id = 2, name = "Headphones" } }
        eq(GA.next_output(outs).id, 2); outs[1].default, outs[2].default = false, true; eq(GA.next_output(outs).id, 1)
        eq(GA.next_output({}), nil); eq(GA.next_output({ { id = 9 } }).id, 9)
        eq(GA.short_output("Ryzen HD Audio Controller Speaker"), "Speaker")
        eq(GA.short_output("A Very Long Output Name That Goes On"), "A Very Long Output Na…")
        eq(GA.output("Headphones").label, "PLAYS ON HEADPHONES")
        local l = read("shell/mooi-node.luau")
        assert(l:find('pcall(sys.call, "audio.default", o.id)', 1, true))
        assert(read("shell/mooi-node.plm"):find("zone box pouz {", 1, true))
    end)
end

section("mooi says when there is a newer mooi (D278, k4's)")
do
    local DR = require("lib/drawers")
    test("behind, dirty, up to date, and asking again after six hours", function()
        local now = 10 ^ 9
        local l, can, stale = DR.self_line({ at = now - 60, behind = 3, dirty = false, head = "abc" }, now)
        eq(l, "mooi · 3 new commits"); eq(can, true); eq(stale, false)
        eq(select(2, DR.self_line({ at = now, behind = 2, dirty = true }, now)), false, "your changes are never pulled over")
        eq(DR.self_line({ at = now, behind = 0, head = "f08abbf" }, now), "mooi f08abbf · up to date")
        eq(select(3, DR.self_line({ at = now - 7 * 3600, behind = 0 }, now)), true)
        eq(select(3, DR.self_line(nil, now)), true)
        local b = read("bin/mooi")
        assert(b:find("git -C \"$root\" pull --ff-only", 1, true) and b:find("rev-list --count HEAD..@{u}", 1, true))
    end)
end

section("the dock (D280; k4's Dual mode's dock)")
do
    local DK = require("lib/dock")
    local apps = { { id = "kitty.desktop", wmclass = "kitty", name = "kitty", icon = "kitty", exec = "kitty" },
                   { id = "org.gnome.Nautilus", name = "Files", icon = "org.gnome.Nautilus", exec = "nautilus --new-window" },
                   { id = "zen", wmclass = "zen", name = "Zen Browser", icon = "zen-browser", exec = "zen" } }
    local clients = { { class = "kitty", address = "0x1", workspace = { name = "1" } },
                      { class = "zen", address = "0x2", workspace = { name = "2" } },
                      { class = "kitty", address = "0x3", workspace = { name = "1" } },
                      { class = "org.gnome.Nautilus", address = "0x4", workspace = { name = "special:mooi-buried" } },
                      { class = "pleamar", address = "0x5", workspace = { name = "1" } },
                      { class = "mystery", address = "0x6", workspace = { name = "3" } } }
    test("items: the pinned first, then the running, windows grouped, the buried and mooi's own left out", function()
        local it = DK.items({ "org.gnome.Nautilus" }, apps, clients, "0x3")
        eq(#it, 4); eq(it[1].name, "Files"); eq(it[1].pinned, true); eq(#it[1].windows, 0, "a buried window is not its")
        eq(it[2].key, "kitty"); eq(#it[2].windows, 2); eq(it[2].active, true)
        eq(it[3].name, "Zen Browser"); eq(it[4].name, "mystery"); eq(it[4].icon, "mystery")
    end)
    test("a press: launch what does not run, else the next of its windows", function()
        local it = DK.items({ "org.gnome.Nautilus" }, apps, clients, "0x3")
        eq(DK.press(it[1], "0x3")[1], "launch"); eq(DK.press(it[1])[2], "nautilus --new-window")
        eq(DK.press(it[2], "0x3")[2], "0x1", "from the focused one to the next, round")
        eq(DK.press(it[2], "0x9")[2], "0x1"); eq(DK.press(nil), nil)
    end)
    test("pins toggle; addresses are checked", function()
        local p, added = DK.toggle_pin({ "kitty" }, "zen"); eq(#p, 2); eq(added, true)
        p, added = DK.toggle_pin(p, "kitty"); eq(#p, 1); eq(p[1], "zen"); eq(added, false)
        eq(DK.address("0xabc"), "0xabc"); eq(DK.address("0x1; rm"), nil)
        eq(DK.app_for("Nautilus", apps).name, "Files", "the id's last part")
    end)
    test("the dock: kept by the bar, held up by Super+Shift+D, pins in dock.json, its own Settings page", function()
        local c = require("lib/config").defaults()
        eq(c.dock.on, true); eq(c.dock.empty, false); eq(c.keys.dock, "SUPER + SHIFT + D")
        assert(read("shell/mooi.luau"):find('SURFACE.args(shell_dir() .. "/mooi-dock.plm")', 1, true))
        local l = read("shell/mooi-dock.luau")
        assert(l:find('"files.write", "dock.json"', 1, true) and not l:find('"settings.json", json.encode', 1, true))
        local p = read("shell/mooi-dock.plm")
        assert(p:find("on press right dkz_i { emit dk_pin(i.index) }", 1, true) and p:find("event dk_hold ->", 1, true))
        assert(read("tools/gen-settings.py"):find('("Dock", "Dock"', 1, true))
    end)
end

section("ask Claude about the screen (D281, k4's)")
do
    test("a region's words start the notch's question through a file, never a command line", function()
        local b, l = read("bin/mooi"), read("shell/mooi-notch.luau")
        assert(b:find('f="$(dirname "$settings")/ask-region.txt"', 1, true) and b:find("umask 077", 1, true))
        assert(b:find('--say mooi-notch "emit nt_region"', 1, true))
        assert(l:find('on("nt_region", function()', 1, true) and l:find('pcall(sys.call, "files.remove", "ask-region.txt")', 1, true))
        assert(read("shell/mooi-notch.plm"):find("event nt_region ->", 1, true))
        eq(require("lib/config").defaults().keys.ask, "SUPER + SHIFT + G")
    end)
end
