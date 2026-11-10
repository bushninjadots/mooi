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
