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
