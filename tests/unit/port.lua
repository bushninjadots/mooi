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
