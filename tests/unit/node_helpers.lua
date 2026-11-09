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
