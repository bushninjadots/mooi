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
