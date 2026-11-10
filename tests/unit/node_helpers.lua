-- The node's helpers (D230): its clock font, its mixer rows, its microphone and camera watch, and its lyrics.
-- Given the harness's section, test and eq by tests/unit/run.lua.
local section, test, eq = ...

section("the node's helpers (D230): the clock font")
do
    local F = require("lib/node/clockfont")
    local want = "0123456789:.-/ ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    test("every glyph is seven rows of five, only lit or dark, and the whole alphabet is there", function()
        for i = 1, #want do
            local ch = want:sub(i, i)
            local rows = F.GLYPHS[ch]
            assert(rows, "missing glyph " .. ch)
            eq(#rows, F.H, ch .. " rows")
            for y = 1, F.H do
                eq(#rows[y], F.W, ch .. " row " .. y)
                assert(not rows[y]:find("[^#%.]"), ch .. " row " .. y .. " has a strange mark")
            end
        end
        eq(F.GLYPHS[" "][4], ".....", "space is blank")
        eq(F.GLYPHS["0"][7], ".###.", "zero sits on its base")
        eq(F.GLYPHS["4"][5], "#####", "four is open-topped, crossed low")
        eq(F.GLYPHS[":"][3], "..#..", "the colon is on the middle column")
        eq(F.GLYPHS["."][7], "..#..", "and so is the full stop")
    end)
    test("glyph: letters are looked up upper-case; anything unknown is blank", function()
        eq(F.glyph("a")[1], F.GLYPHS["A"][1], "lower-case a")
        eq(F.glyph("q"), F.GLYPHS["Q"], "same rows, not a copy")
        eq(F.glyph("~"), F.GLYPHS[" "], "unknown")
        eq(F.glyph(nil), F.GLYPHS[" "], "nothing")
        eq(F.glyph(7), F.GLYPHS[" "], "a number")
    end)
    test("width: glyphs and one column between, nothing for nothing", function()
        eq(F.width(""), 0); eq(F.width(nil), 0)
        eq(F.width("1"), 5)
        eq(F.width("12"), 11)
        eq(F.width("A B"), 17, "the space still takes its cell")
        eq(F.width("12:34"), 5 * 5 + 4)
    end)
    test("cells: every lit pixel, 0-based, each glyph one gap further along", function()
        eq(#F.cells(""), 0); eq(#F.cells(" "), 0, "space lights nothing")
        local dash = F.cells("-")
        eq(#dash, 5)
        for i, c in ipairs(dash) do eq(c.x, i - 1); eq(c.y, 3) end
        local one = F.cells("1")
        eq(#one, 10, "the one's ten pixels")
        eq(one[1].x, 2); eq(one[1].y, 0)
        local two = F.cells("--")
        eq(#two, 10)
        eq(two[6].x, 6, "the second dash starts after the gap"); eq(two[6].y, 3)
        eq(F.cells(nil)[1], nil, "nothing")
    end)
    test("grid: the full panel, every cell once, lit exactly where cells says", function()
        local g = F.grid("2")
        eq(#g, F.width("2") * F.H, "five columns, seven rows")
        local lit = 0
        for _, c in ipairs(g) do
            if c.on then lit = lit + 1 end
            assert(c.x >= 0 and c.x < 5 and c.y >= 0 and c.y < 7)
        end
        eq(lit, #F.cells("2"), "same pixels as cells")
        eq(#F.grid(""), 0)
        local blank = F.grid("  ")
        eq(#blank, 11 * 7)
        for _, c in ipairs(blank) do eq(c.on, false, "two spaces light nothing") end
    end)
    test("a full clock reads across: the gap's column is dark, never a glyph's", function()
        local g = F.grid("1 2")
        local w = F.width("1 2")
        for _, c in ipairs(g) do
            if c.x % 6 == 5 then eq(c.on, false, "gap at " .. c.x) end
        end
        eq(w, 17)
        -- the same cell list the panel draws, with a lit count that grows with the string
        assert(#F.cells("12:34") > #F.cells("12"))
    end)
end

section("the node's helpers (D230): the mixer")
do
    local MX = require("lib/node/mixer")

    -- a real-looking `pactl -f json list sink-inputs`, with two Firefox streams, Spotify, mpv and one oddity
    local function sample()
        return {
            { index = 41, mute = false, volume = { { value_percent = "60%" }, { value_percent = "40%" } },
              properties = { ["application.name"] = "Firefox", ["application.process.binary"] = "firefox",
                             ["application.icon_name"] = "firefox" } },
            { index = 42, mute = true, volume = { { value_percent = "50%" }, { value_percent = "50%" } },
              properties = { ["application.name"] = "Firefox", ["application.process.binary"] = "firefox" } },
            { index = 50, mute = false, volume = { { value_percent = "100%" } },
              properties = { ["application.name"] = "Spotify", ["application.icon_name"] = "spotify-client" } },
            { index = 52, mute = false, volume = { { value_percent = "150%" } },
              properties = { ["application.process.binary"] = "mpv" } },
            { index = 60, mute = false, volume = {}, properties = {} },
        }
    end

    test("group: one row per application, in name order, its ids, icon, streams and the channels' average", function()
        local rows = MX.group(sample())
        eq(#rows, 4, "Firefox, mpv, Spotify, Unknown")
        eq(rows[1].name, "Firefox"); eq(rows[1].icon, "firefox")
        eq(#rows[1].ids, 2); eq(rows[1].ids[1], 41); eq(rows[1].ids[2], 42)
        eq(rows[1].streams, 2)
        eq(rows[1].volume, 0.5, "60, 40, 50, 50 average half")
        eq(rows[1].muted, false, "one stream is audible")
        eq(rows[2].name, "mpv", "no name: the binary"); eq(rows[2].icon, "")
        eq(rows[2].volume, 1, "150% is held to the top")
        eq(rows[3].name, "Spotify"); eq(rows[3].icon, "spotify-client"); eq(rows[3].volume, 1)
        eq(rows[4].name, "Unknown"); eq(rows[4].volume, 0, "no channels: silent")
        eq(rows[4].streams, 1)
    end)
    test("group: muted only when every stream is; names sort without case; the input is left alone", function()
        local rows = MX.group({
            { index = 1, mute = true, volume = { { value_percent = "20%" } }, properties = { ["application.name"] = "zsh" } },
            { index = 2, mute = true, volume = { { value_percent = "80%" } }, properties = { ["application.name"] = "Audacious" } },
            { index = 3, mute = true, volume = { { value_percent = "40%" } }, properties = { ["application.name"] = "zsh" } },
        })
        eq(rows[1].name, "Audacious", "the case does not decide")
        eq(rows[2].name, "zsh"); eq(rows[2].muted, true, "every stream muted")
        eq(rows[2].volume, 0.3, "20 and 40 average 30")
        local list = sample()
        MX.group(list)
        eq(list[1].volume[1].value_percent, "60%", "the decoded JSON is not changed")
        eq(list[1].mute, false)
    end)
    test("group: odd input is no row, never an error", function()
        eq(#MX.group(nil), 0); eq(#MX.group("junk"), 0); eq(#MX.group({}), 0)
        local rows = MX.group({
            "a string", 7, { index = "nope", mute = false },
            { index = 4, properties = "not a table", volume = "not a table" },
            { index = 5, mute = false, volume = { "junk", { value_percent = "wat" }, { value_percent = 25 } },
              properties = { ["application.name"] = "" } },
        })
        eq(#rows, 1, "only the two with a numeric index, both nameless: one Unknown row")
        eq(rows[1].name, "Unknown")
        eq(#rows[1].ids, 2); eq(rows[1].ids[1], 4); eq(rows[1].ids[2], 5)
        eq(rows[1].volume, 0.25, "the one readable channel across both streams")
        eq(rows[1].muted, false, "a missing mute is not muted")
    end)
    test("set_volume: one pactl call per stream, the fraction rounded to a whole per cent and held to 150", function()
        local app = { ids = { 41, 42 } }
        local cmds = MX.set_volume(app, 0.645)
        eq(#cmds, 2)
        eq(cmds[1][1], "pactl"); eq(cmds[1][2], "set-sink-input-volume")
        eq(cmds[1][3], "41"); eq(cmds[1][4], "65%", "rounded up")
        eq(cmds[2][3], "42")
        eq(MX.set_volume(app, 0.644)[1][4], "64%")
        eq(MX.set_volume(app, 1.2)[1][4], "120%", "a stream may be pushed up")
        eq(MX.set_volume(app, 9)[1][4], "150%", "but not past 150")
        eq(MX.set_volume(app, -1)[1][4], "0%")
        eq(MX.set_volume(app, nil)[1][4], "0%")
        eq(MX.set_volume(app, "0.5")[1][4], "50%", "a string is a number")
    end)
    test("set_volume and set_mute: nothing to set, nothing asked; mute is 1 or 0", function()
        eq(#MX.set_volume(nil, 0.5), 0); eq(#MX.set_volume({}, 0.5), 0)
        eq(#MX.set_volume({ ids = "41" }, 0.5), 0)
        local cmds = MX.set_mute({ ids = { 41, 42 } }, true)
        eq(#cmds, 2); eq(cmds[1][1], "pactl"); eq(cmds[1][2], "set-sink-input-mute")
        eq(cmds[1][3], "41"); eq(cmds[1][4], "1")
        eq(cmds[2][3], "42")
        eq(MX.set_mute({ ids = { 41 } }, false)[1][4], "0")
        eq(MX.set_mute({ ids = { 41 } }, nil)[1][4], "0")
        eq(#MX.set_mute(nil, true), 0)
    end)
    test("a group's own commands address exactly the streams it gathered", function()
        local rows = MX.group(sample())
        local cmds = MX.set_volume(rows[1], 0.25)
        eq(#cmds, 2)
        eq(cmds[1][3], "41"); eq(cmds[2][3], "42")
        eq(cmds[1][4], "25%")
        eq(#MX.set_mute(rows[3], true), 1, "Spotify's one stream")
    end)
end

section("the node's helpers (D230): the privacy watch")
do
    local PV = require("lib/node/privacy")

    test("mic_users: the apps on the microphone, once each, monitors and meters and helpers left out", function()
        local users = PV.mic_users({
            { source = 3, properties = { ["application.name"] = "Firefox", ["application.process.binary"] = "firefox",
                                         ["media.name"] = "Firefox" } },
            { source = 3, properties = { ["application.name"] = "Firefox", ["application.process.binary"] = "firefox" } },
            { source = 4, properties = { ["application.name"] = "Firefox", ["stream.monitor"] = "true" } },
            { source = 5, properties = { ["application.name"] = "cava", ["application.process.binary"] = "cava" } },
            { source = 6, properties = { ["application.name"] = "PulseAudio Volume Control",
                                         ["application.process.binary"] = "pavucontrol" } },
            { source = 7, properties = { ["application.name"] = "mooi", ["application.process.binary"] = "pleamar" } },
            { source = 8, properties = { ["application.name"] = "OBS", ["application.process.binary"] = "obs",
                                         ["media.name"] = "Speakers Peak Detect" } },
            { source = 9, properties = { ["application.process.binary"] = "zoom" } },
            { source = 10, properties = { ["media.name"] = "only the media" } },
        })
        eq(#users, 3, "Firefox, the binary fallback, and the nameless")
        eq(users[1], "Firefox")
        eq(users[2], "Unknown")
        eq(users[3], "zoom", "no name: its binary")
    end)
    test("mic_users: names sort without case and odd input is empty, never an error", function()
        local users = PV.mic_users({
            { properties = { ["application.name"] = "zsh" } },
            { properties = { ["application.name"] = "Audacious" } },
            { properties = { ["application.name"] = "" } },
            { properties = { ["application.name"] = "Firefox" } },
        })
        eq(#users, 4)
        eq(users[1], "Audacious"); eq(users[2], "Firefox"); eq(users[3], "Unknown"); eq(users[4], "zsh")
        eq(#PV.mic_users(nil), 0); eq(#PV.mic_users("junk"), 0); eq(#PV.mic_users({}), 0)
        eq(#PV.mic_users({ "a string", 4, { properties = "not a table" }, { source = 2 } }), 1, "one nameless row")
        eq(PV.mic_users({ { source = 2 } })[1], "Unknown")
    end)
    test("mic_users: monitor and peak-detect tests do not care about case, nor does the binary's name", function()
        local users = PV.mic_users({
            { properties = { ["application.name"] = "Discord", ["stream.monitor"] = "TRUE" } },
            { properties = { ["application.name"] = "Discord", ["application.process.binary"] = "Discord",
                             ["media.name"] = "microphone PEAK DETECT (source)" } },
            { properties = { ["application.name"] = "CAVA", ["application.process.binary"] = "CAVA" } },
            { properties = { ["application.name"] = "Real", ["application.process.binary"] = "discord" } },
        })
        eq(#users, 1); eq(users[1], "Real")
    end)
    test("camera_in_use: a /dev/video line with a process on it means open", function()
        eq(PV.camera_in_use("/dev/video0:  1234 5678\n/dev/video1:  999\n"), true)
        eq(PV.camera_in_use("/dev/video2: 4242"), true, "one line is enough")
        eq(PV.camera_in_use("  /dev/video3:   77m  88\n"), true, "fuser's marks do not hide the pid")
        eq(PV.camera_in_use("/dev/video0: 1234\n/dev/video1: 5678\n"), true, "either camera")
    end)
    test("camera_in_use: no pid, no camera; errors and nothing at all are not open", function()
        eq(PV.camera_in_use(""), false); eq(PV.camera_in_use(nil), false)
        eq(PV.camera_in_use("/dev/video0:\n/dev/video1: \n"), false, "listed but unused")
        eq(PV.camera_in_use("/dev/video0: No such file or directory"), false, "no pid on the line")
        eq(PV.camera_in_use("fuser: /dev/video2: No such file or directory\n"), false, "not a device line")
        eq(PV.camera_in_use("Cannot stat /dev/video0: Permission denied"), false)
        eq(PV.camera_in_use(42), false, "not text")
    end)
    test("changed: a yes that became a no says stopped, the other way started, and no change says nothing", function()
        eq(PV.changed(false, true), "started")
        eq(PV.changed(true, false), "stopped")
        eq(PV.changed(true, true), nil)
        eq(PV.changed(false, false), nil)
        eq(PV.changed(nil, true), "started", "not known before: it started")
        eq(PV.changed(nil, nil), nil)
        eq(PV.changed(nil, false), nil, "not known and off: nothing")
    end)
end

section("the node's helpers (D230): the lyrics")
do
    local LY = require("lib/node/lyrics")

    local lrc = table.concat({
        "[ti:A Song]",
        "[ar:Someone]",
        "[00:01.50]First",
        "[00:12.00][01:30.50]Chorus",
        "[00:20]Third",
        "[00:25.123]Fourth",
        "",
    }, "\n")

    test("parse: every stamp form, several on a line, tags ignored, in time order", function()
        local lines = LY.parse(lrc)
        eq(#lines, 5, "four stamps and the chorus twice")
        eq(lines[1].t, 1500); eq(lines[1].line, "First")
        eq(lines[2].t, 12000); eq(lines[2].line, "Chorus")
        eq(lines[3].t, 20000); eq(lines[3].line, "Third")
        eq(lines[4].t, 25123); eq(lines[4].line, "Fourth", "three decimals are milliseconds")
        eq(lines[5].t, 90500); eq(lines[5].line, "Chorus", "the second stamp of the line")
        for i = 2, #lines do assert(lines[i].t >= lines[i - 1].t, "sorted") end
    end)
    test("parse: one or two decimals, an offset moving every line, and the file's order kept", function()
        local one = LY.parse("[00:01.5]half")
        eq(one[1].t, 1500)
        eq(LY.parse("[00:01.05]hundredths")[1].t, 1050)
        local early = LY.parse("[offset:+250]\n[00:01.00]first\n[00:02.00]second")
        eq(early[1].t, 750, "positive: earlier"); eq(early[2].t, 1750)
        local late = LY.parse("[offset:-500]\n[00:01.00]first")
        eq(late[1].t, 1500, "negative: later")
        local unordered = LY.parse("[00:05.00]b\n[00:01.00]a")
        eq(unordered[1].line, "a"); eq(unordered[2].line, "b")
        eq(#LY.parse("[00:03.00][00:04.00]same"), 2, "the same words twice")
    end)
    test("parse: a pause is an empty line; spaces are trimmed; CRLF and odd input are fine", function()
        local lines = LY.parse("[00:05.00]\n[00:06.00]   spaced out   \r\n")
        eq(#lines, 2)
        eq(lines[1].t, 5000); eq(lines[1].line, "", "a pause kept")
        eq(lines[2].line, "spaced out")
        eq(#LY.parse(nil), 0); eq(#LY.parse(""), 0); eq(#LY.parse(42), 0)
        eq(#LY.parse("no stamps at all\n[ar:Someone]\n[ti:Title]\n[offset:+10]"), 0)
    end)
    test("at: the last line at or before the moment, 0 before the first", function()
        local lines = LY.parse(lrc)
        eq(LY.at(lines, 0), 0)
        eq(LY.at(lines, 1499), 0)
        eq(LY.at(lines, 1500), 1, "on the stamp")
        eq(LY.at(lines, 11999), 1)
        eq(LY.at(lines, 12000), 2)
        eq(LY.at(lines, 20000), 3)
        eq(LY.at(lines, 999999), 5, "the last")
        eq(LY.at(nil, 1000), 0); eq(LY.at({}, 1000), 0)
        eq(LY.at({ { t = 0, line = "a" } }, nil), 1, "no moment: the start")
    end)
    test("window: the line before, the current and the one after, blank where there is none", function()
        local lines = LY.parse(lrc)
        local w = LY.window(lines, 12000, 1)
        eq(w.prev, "First"); eq(w.cur, "Chorus"); eq(w.next, "Third")
        local before = LY.window(lines, 0, 1)
        eq(before.prev, ""); eq(before.cur, ""); eq(before.next, "First")
        local last = LY.window(lines, 999999, 1)
        eq(last.prev, "Fourth"); eq(last.cur, "Chorus"); eq(last.next, "")
        local p = LY.window({ { t = 0, line = "" }, { t = 1000, line = "a" } }, 0, 1)
        eq(p.cur, "", "a pause is still the current line"); eq(p.next, "a")
        eq(LY.window(nil, 10, 1).cur, "")
        eq(LY.window(lines, 12000, 9).cur, "Chorus", "the count does not change the three")
    end)
    test("query: the artist, the track and the seconds, everything unsafe escaped", function()
        eq(LY.query("Sigur Rós", "Hoppípolla (Live)", 245),
            "artist_name=Sigur%20R%C3%B3s&track_name=Hopp%C3%ADpolla%20%28Live%29&duration=245")
        eq(LY.query("a-b_c.d~e", "x&y/z", 0), "artist_name=a-b_c.d~e&track_name=x%26y%2Fz&duration=0",
            "the unreserved set stays as it is")
        eq(LY.query(nil, nil, nil), "artist_name=&track_name=&duration=0")
        eq(LY.query("", "", "245.9"), "artist_name=&track_name=&duration=245", "a whole second")
        eq(LY.query("", "", -5), "artist_name=&track_name=&duration=0", "never negative")
    end)
    test("a whole file reads as the scene will use it: find the line, show its neighbours, ask for another", function()
        local lines = LY.parse(table.concat({
            "[offset:+100]",
            "[00:10.00]I wake up",
            "[00:14.00]",
            "[00:18.50]and the day begins",
        }, "\n"))
        eq(#lines, 3)
        eq(lines[1].t, 9900)
        local w = LY.window(lines, 15000, 1)
        eq(w.prev, "I wake up"); eq(w.cur, ""); eq(w.next, "and the day begins")
        eq(LY.query("The Band", "Morning", 201):find("duration=201", 1, true) ~= nil, true)
    end)
end

section("the node's helpers (D232): privacy and monitor sources")
do
    local PV = require("lib/node/privacy")
    test("a stream recording from a monitor of the speakers is not the microphone (a visualiser listening to the music)", function()
        local mon = PV.monitors({ { index = 60, name = "alsa_output.pci.HiFi__Speaker__sink.monitor" },
                                  { index = 61, name = "alsa_input.pci.HiFi__Mic2__source" }, "junk", { name = "x" } })
        eq(mon[60], true); eq(mon[61], nil)
        local users = PV.mic_users({ { source = 60, properties = { ["media.name"] = "cava" } },
                                     { source = 61, properties = { ["application.name"] = "Firefox" } } }, mon)
        eq(#users, 1); eq(users[1], "Firefox")
        eq(#PV.mic_users({ { source = 60, properties = { ["media.name"] = "cava" } } }), 1, "without the sources it cannot tell")
        eq(next(PV.monitors(nil)), nil)
    end)
end

section("the node's helpers (D232): devices")
do
    local D = require("lib/node/devices")

    test("brightness: an empty field does not shift the others (Luau splits as Lua 5.4 does)", function()
        local b = D.brightness("amdgpu_bl1,backlight,62258,95%,65535")
        eq(b.device, "amdgpu_bl1"); assert(math.abs(b.frac - 62258 / 65535) < 1e-9)
        eq(D.brightness("amdgpu_bl1,backlight,,40%,255").frac, 0.4, "no current: the percentage")
    end)
    test("brightness: the backlight's name and its share of the maximum", function()
        local b = D.brightness("intel_backlight,backlight,4800,50%,9600\n")
        eq(b.device, "intel_backlight", "the device")
        eq(b.frac, 0.5, "4800 of 9600")
        eq(D.brightness("amdgpu_bl0,backlight,120,25%,480").frac, 0.25)
        eq(D.brightness("garbage\nintel_backlight,backlight,4800,50%,9600").device, "intel_backlight",
            "the first line that reads")
    end)
    test("brightness: the percentage is the fallback, and nonsense is nothing", function()
        eq(D.brightness("intel_backlight,backlight,0,40%,0").frac, 0.4, "no usable maximum")
        eq(D.brightness("intel_backlight,backlight,4800,40%").frac, 0.4, "no maximum field")
        eq(D.brightness("intel_backlight,backlight"), nil, "no readings")
        eq(D.brightness(""), nil); eq(D.brightness(nil), nil); eq(D.brightness("garbage"), nil)
        eq(D.brightness(",backlight,4800,50%,9600"), nil, "no device")
    end)
    test("set_brightness: a whole percentage, and never a black screen", function()
        eq(table.concat(D.set_brightness(0.5), " "), "brightnessctl -q set 50%")
        eq(table.concat(D.set_brightness(0), " "), "brightnessctl -q set 1%", "the floor is 1%")
        eq(table.concat(D.set_brightness(-2), " "), "brightnessctl -q set 1%")
        eq(table.concat(D.set_brightness(1), " "), "brightnessctl -q set 100%")
        eq(table.concat(D.set_brightness(2), " "), "brightnessctl -q set 100%", "no brighter than the maximum")
        eq(table.concat(D.set_brightness(nil), " "), "brightnessctl -q set 1%")
    end)
    test("source_volume: the average of the channels pactl prints", function()
        local text = "Volume: front-left: 45875 /  70% / -9.29 dB,   front-right: 45875 /  70% / -9.29 dB\n"
        eq(D.source_volume(text), 0.7)
        local uneven = "Volume: front-left: 45875 /  60% / -1 dB,   front-right: 45875 /  80% / -1 dB"
        eq(D.source_volume(uneven), 0.7, "the two channels average")
        eq(D.source_volume("Volume: front-left: 45875 / -9.29 dB"), nil)
        eq(D.source_volume(""), nil); eq(D.source_volume(nil), nil)
    end)
    test("source_mute: yes and no, and nothing else", function()
        eq(D.source_mute("Mute: yes\n"), true)
        eq(D.source_mute("Mute: no\n"), false)
        eq(D.source_mute("Mute: toggle"), nil)
        eq(D.source_mute("Volume: front-left: 45875 / 70%"), nil)
        eq(D.source_mute(nil), nil)
    end)
    test("the microphone's argv: set the level or flip the mute", function()
        eq(table.concat(D.set_source_volume(0.7), " "), "pactl set-source-volume @DEFAULT_SOURCE@ 70%")
        eq(table.concat(D.set_source_volume(1.5), " "), "pactl set-source-volume @DEFAULT_SOURCE@ 150%")
        eq(table.concat(D.set_source_volume(9), " "), "pactl set-source-volume @DEFAULT_SOURCE@ 150%")
        eq(table.concat(D.set_source_volume(-1), " "), "pactl set-source-volume @DEFAULT_SOURCE@ 0%")
        eq(table.concat(D.set_source_volume(nil), " "), "pactl set-source-volume @DEFAULT_SOURCE@ 0%")
        eq(table.concat(D.toggle_source_mute(), " "), "pactl set-source-mute @DEFAULT_SOURCE@ toggle")
    end)
    test("upower: a discharging battery, its comma decimal read as hours", function()
        local u = D.upower(table.concat({
            "  native-path:          /sys/class/power_supply/BAT0",
            "  state:               discharging",
            "  percentage:          42%",
            "  time to empty:       2,3 hours",
        }, "\n"))
        eq(u.percent, 42); eq(u.state, "discharging")
        eq(u.charging, false); eq(u.full, false)
        eq(u.minutes_left, 138, "2.3 hours")
        eq(u.minutes_to_full, nil)
    end)
    test("upower: charging with a dot decimal and a time to full in minutes", function()
        local u = D.upower(table.concat({
            "    state:               charging",
            "    percentage:          67.5%",
            "    time to full:        35.5 minutes",
        }, "\n"))
        eq(u.percent, 67.5); eq(u.charging, true); eq(u.full, false)
        eq(u.minutes_to_full, 36, "rounded")
        eq(u.minutes_left, nil)
        eq(D.upower("state: pending-charge\npercentage: 19%").charging, true, "pending-charge counts")
    end)
    test("upower: full, seconds left, and no percentage at all", function()
        local u = D.upower("state: fully-charged\npercentage: 100%\ntime to empty: 45 seconds")
        eq(u.full, true); eq(u.charging, false); eq(u.minutes_left, 1, "45 seconds rounds to a minute")
        eq(D.upower("state: charging\ntime to full: 10 minutes"), nil, "no percentage, no reading")
        eq(D.upower(""), nil); eq(D.upower(nil), nil); eq(D.upower("garbage"), nil)
    end)
    test("band: good, low, critical", function()
        eq(D.band(100), "good"); eq(D.band(50), "good")
        eq(D.band(49), "low"); eq(D.band(20), "low")
        eq(D.band(19), "critical"); eq(D.band(0), "critical")
        eq(D.band(nil), nil); eq(D.band("50"), nil)
    end)
    test("crossed_critical: only the fall below 20, and only while unplugged", function()
        eq(D.crossed_critical(nil, 19, false), true, "first reading already low")
        eq(D.crossed_critical(50, 19, false), true)
        eq(D.crossed_critical(20, 19, false), true)
        eq(D.crossed_critical(50, 19, true), false, "charging")
        eq(D.crossed_critical(50, 20, false), false, "still at 20")
        eq(D.crossed_critical(19, 10, false), false, "it was already low")
        eq(D.crossed_critical(50, nil, false), false)
        eq(D.crossed_critical("50", 19, false), false)
    end)
    test("format_minutes: hours and minutes, plain minutes, and less than one", function()
        eq(D.format_minutes(138), "2 h 18 min")
        eq(D.format_minutes(35), "35 min")
        eq(D.format_minutes(59), "59 min")
        eq(D.format_minutes(60), "1 h 0 min")
        eq(D.format_minutes(120), "2 h 0 min")
        eq(D.format_minutes(0), "< 1 min")
        eq(D.format_minutes(0.4), "< 1 min", "rounds down to nothing")
        eq(D.format_minutes(nil), ""); eq(D.format_minutes(-1), "")
    end)
    test("fullscreen: the window's flag or its client's", function()
        eq(D.fullscreen({ fullscreen = true }), true)
        eq(D.fullscreen({ fullscreen = 1 }), true)
        eq(D.fullscreen({ fullscreenClient = 2 }), true, "the client's flag counts")
        eq(D.fullscreen({ fullscreen = false }), false)
        eq(D.fullscreen({ fullscreen = 0 }), false)
        eq(D.fullscreen({ fullscreenClient = 0 }), false)
        eq(D.fullscreen({ fullscreen = "true" }), false, "a string is not a flag")
        eq(D.fullscreen({}), false); eq(D.fullscreen(nil), false)
    end)
    test("segments: how much of the meter is lit", function()
        eq(D.segments(0.5, 10), 5)
        eq(D.segments(0, 10), 0); eq(D.segments(1, 10), 10)
        eq(D.segments(1.5, 10), 10, "held to the whole")
        eq(D.segments(0.55, 10), 6, "rounded")
        eq(D.segments(0.5, 0), 0); eq(D.segments(0.5, nil), 0)
        eq(D.segments(nil, 10), 0)
    end)
    test("frac_at: where a drag sits on the meter, held to its ends", function()
        eq(D.frac_at(150, 100, 100), 0.5)
        eq(D.frac_at(50, 100, 100), 0, "left of it")
        eq(D.frac_at(250, 100, 100), 1, "right of it")
        eq(D.frac_at(100, 100, 0), 0, "no width")
        eq(D.frac_at(100, 100, -5), 0)
        eq(D.frac_at(nil, nil, 100), 0)
    end)
end

section("the node's helpers (D233): media")
do
    local K = require("lib/node/mediakit")

    local function line(...)
        return table.concat({ ... }, "\t")
    end

    test("FORMAT: the exact playerctl format this module reads", function()
        eq(K.FORMAT, "{{playerName}}\t{{status}}\t{{shuffle}}\t{{loop}}\t{{position}}\t" ..
            "{{mpris:length}}\t{{xesam:url}}\t{{mpris:artUrl}}")
    end)
    test("parse: a playing Spotify line becomes the card's state", function()
        local s = K.parse(line("Spotify", "Playing", "Off", "None", "187000000", "210000000",
            "https://open.spotify.com/track/abc", "https://i.scdn.co/image/abc"))
        eq(s.player, "Spotify"); eq(s.status, "Playing"); eq(s.playing, true)
        eq(s.shuffle, false); eq(s.loop, "None")
        eq(s.position_ms, 187000, "microseconds to milliseconds")
        eq(s.length_ms, 210000)
        eq(s.url, "https://open.spotify.com/track/abc")
        eq(s.art, "https://i.scdn.co/image/abc")
    end)
    test("parse: shuffle and loop read as playerctl writes them, empty fields fall back", function()
        local s = K.parse(line("firefox", "Paused", "true", "Track", "", "", "", ""))
        eq(s.status, "Paused"); eq(s.playing, false)
        eq(s.shuffle, true, "true is on"); eq(s.loop, "Track")
        eq(s.position_ms, 0); eq(s.length_ms, 0); eq(s.url, ""); eq(s.art, "")
        eq(K.parse(line("mpv", "Playing", "On", "Playlist", "1000", "2000", "u", "a")).shuffle, true)
    end)
    test("parse: unknown fields fall back, and a line that is not the format is nothing", function()
        local s = K.parse(line("x", "Buffering", "maybe", "Sideways", "-5", "junk", "", ""))
        eq(s.status, "Stopped"); eq(s.playing, false)
        eq(s.shuffle, false); eq(s.loop, "None")
        eq(s.position_ms, 0, "a negative position is no position"); eq(s.length_ms, 0)
        eq(K.parse(""), nil); eq(K.parse("garbage"), nil); eq(K.parse("a\tb"), nil)
        eq(K.parse(nil), nil); eq(K.parse(42), nil)
    end)
    test("next_loop: none, the playlist, the one track, none", function()
        eq(K.next_loop("None"), "Playlist")
        eq(K.next_loop("Playlist"), "Track")
        eq(K.next_loop("Track"), "None")
        eq(K.next_loop(nil), "Playlist", "nothing known reads as none")
        eq(K.next_loop("Sideways"), "Playlist")
    end)
    test("cmd_shuffle and cmd_loop: playerctl, with the player when there is one", function()
        eq(table.concat(K.cmd_shuffle("Spotify", true), " "), "playerctl -p Spotify shuffle On")
        eq(table.concat(K.cmd_shuffle("Spotify", false), " "), "playerctl -p Spotify shuffle Off")
        eq(table.concat(K.cmd_shuffle("", true), " "), "playerctl shuffle On", "no player to name")
        eq(table.concat(K.cmd_shuffle(nil, false), " "), "playerctl shuffle Off")
        eq(table.concat(K.cmd_loop("mpv", "Track"), " "), "playerctl -p mpv loop Track")
        eq(table.concat(K.cmd_loop(nil, nil), " "), "playerctl loop None")
    end)
    test("cmd_seek: a share of the track as seconds with one decimal", function()
        eq(table.concat(K.cmd_seek("vlc", 0.5, 180000), " "), "playerctl -p vlc position 90.0")
        eq(table.concat(K.cmd_seek("vlc", 2, 180000), " "), "playerctl -p vlc position 180.0", "held to the end")
        eq(table.concat(K.cmd_seek("vlc", -1, 180000), " "), "playerctl -p vlc position 0.0")
        eq(table.concat(K.cmd_seek(nil, 0.25, 180000), " "), "playerctl position 45.0")
        eq(K.cmd_seek("vlc", 0.5, 0), nil, "nothing to seek within")
        eq(K.cmd_seek("vlc", 0.5, nil), nil)
        eq(K.cmd_seek("vlc", 0.5, -10), nil)
    end)
    test("format_time: minutes, then hours, and a floor for nonsense", function()
        eq(K.format_time(187000), "3:07")
        eq(K.format_time(60000), "1:00")
        eq(K.format_time(59999), "0:59")
        eq(K.format_time(3729000), "1:02:09")
        eq(K.format_time(3599000), "59:59")
        eq(K.format_time(0), "0:00")
        eq(K.format_time(nil), "0:00")
        eq(K.format_time(-5), "0:00")
    end)
    test("youtube_id: every form of a video url", function()
        local id = "dQw4w9WgXcQ"
        eq(K.youtube_id("https://www.youtube.com/watch?v=" .. id), id)
        eq(K.youtube_id("http://youtube.com/watch?v=" .. id .. "&t=42"), id)
        eq(K.youtube_id("https://music.youtube.com/watch?v=" .. id), id)
        eq(K.youtube_id("https://youtu.be/" .. id .. "?t=42"), id)
        eq(K.youtube_id("https://m.youtube.com/shorts/" .. id), id)
        eq(K.youtube_id("https://youtube.com/live/" .. id .. "?feature=share"), id)
        eq(K.youtube_id("https://www.youtube.com/embed/" .. id), id)
        eq(K.youtube_id("https://www.youtube.com/watch?feature=share&v=" .. id), id, "v anywhere in the query")
    end)
    test("youtube_id: near misses are nothing", function()
        eq(K.youtube_id("https://youtube.com/watch?v=dQw4w9WgXc"), nil, "ten characters")
        eq(K.youtube_id("https://youtu.be/dQw4w9WgXcQextra"), nil, "too long")
        eq(K.youtube_id("https://vimeo.com/12345678901"), nil, "another host")
        eq(K.youtube_id("https://youtube.com/watch?feature=x"), nil, "no v")
        eq(K.youtube_id("https://youtube.com/shorts/dQw4w9WgXc!"), nil, "a mark outside the alphabet")
        eq(K.youtube_id("not a url"), nil); eq(K.youtube_id(nil), nil)
    end)
    test("thumbnails: the four stills, best first", function()
        local t = K.thumbnails("dQw4w9WgXcQ")
        eq(#t, 4)
        eq(t[1], "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg")
        eq(t[2], "https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg")
        eq(t[3], "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        eq(t[4], "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg")
        eq(#K.thumbnails(nil), 0); eq(#K.thumbnails(""), 0)
    end)
    test("art_for: the metadata's art, else a YouTube thumbnail, else nothing", function()
        eq(K.art_for({ art = "file:///home/me/cover.jpg" }), "file:///home/me/cover.jpg")
        eq(K.art_for({ art = "https://example.com/a.png" }), "https://example.com/a.png")
        eq(K.art_for({ art = "", url = "https://youtu.be/dQw4w9WgXcQ" }),
            "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg")
        eq(K.art_for({ art = "ftp://example.com/a.png", url = "https://youtu.be/dQw4w9WgXcQ" }),
            "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg", "another scheme is no art")
        eq(K.art_for({ url = "https://example.com/song" }), "")
        eq(K.art_for(nil), "")
    end)
    test("mirrored: four bands become eight, the low ones meeting in the middle", function()
        local m = K.mirrored({ 0.1, 0.4, 0.7, 1.0 }, 8)
        eq(#m, 8)
        for i, want in ipairs({ 1.0, 0.7, 0.4, 0.1, 0.1, 0.4, 0.7, 1.0 }) do eq(m[i], want, "slot " .. i) end
    end)
    test("mirrored: sixteen bands average into eight", function()
        local bands = {}
        for i = 1, 16 do bands[i] = i / 16 end
        local m = K.mirrored(bands, 8)
        for i, want in ipairs({ 0.90625, 0.65625, 0.40625, 0.15625, 0.15625, 0.40625, 0.65625, 0.90625 }) do
            eq(m[i], want, "slot " .. i)
        end
    end)
    test("mirrored: thirty-two bands into forty, symmetric and low at the centre", function()
        local bands = {}
        for i = 1, 32 do bands[i] = i / 32 end
        local m = K.mirrored(bands, 40)
        eq(#m, 40)
        for i = 1, 40 do
            eq(m[i], m[41 - i], "slot " .. i .. " mirrors")
            assert(m[i] >= 0 and m[i] <= 1, "slot " .. i .. " is a level")
        end
        eq(m[20], m[21], "the middle pair")
        eq(m[20] < m[1], true, "the low bands are inside")
    end)
    test("mirrored: fewer bands repeat, nothing gives zeros, and levels are held to 0..1", function()
        local m = K.mirrored({ 0.2, 0.8 }, 8)
        for i, want in ipairs({ 0.8, 0.8, 0.2, 0.2, 0.2, 0.2, 0.8, 0.8 }) do eq(m[i], want, "slot " .. i) end
        local z = K.mirrored({}, 8)
        eq(#z, 8)
        for i = 1, 8 do eq(z[i], 0) end
        local clamped = K.mirrored({ -1, 2 }, 4)
        for i, want in ipairs({ 1, 0, 0, 1 }) do eq(clamped[i], want, "clamped slot " .. i) end
        eq(#K.mirrored(nil, 0), 0); eq(#K.mirrored(nil, 1), 0)
    end)
end
