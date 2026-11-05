-- Unit tests for the pure logic modules. Run: lua5.4 tests/unit/run.lua (from the repo root)
package.path = "shell/?.luau;" .. package.path

local failures, count = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then print("  ok    " .. name) else failures = failures + 1; print("  FAIL  " .. name .. "\n        " .. tostring(err)) end
end
local function eq(a, b, what) if a ~= b then error(string.format("%s: expected %s, got %s", what or "value", tostring(b), tostring(a)), 2) end end

-- A tiny JSON decoder double: tests hand it tables directly, or raise like a broken file.
local function decode_table(t) return function() return t end end
local function decode_broken() error("expected value at line 1 column 3") end

local config = require("lib/config")
local hypr = require("lib/hypr")
local apps = require("lib/apps")
local spaces = require("lib/spaces")


print("config")
test("defaults are complete and versioned", function()
    local d = config.defaults()
    eq(d.version, 2, "version"); eq(d.bar.modules.clock.show, true, "clock"); eq(d.spine.max_workspaces, 10, "max")
    eq(d.island.confirm_close, true, "confirm"); eq(d.island.follow_on_send, false, "follow"); eq(d.motion.reduced, false, "reduced")
    eq(d.command.max_results, 7, "results"); eq(d.atlas.previews, true, "previews")
    eq(d.bar.labels, true, "bar · labels on the chain"); eq(d.bar.wheel, "step", "bar · the wheel steps")
end)
test("missing file gives defaults and no problems", function()
    local s, p, n, state = config.parse(nil, decode_broken)
    eq(state, "missing", "state"); eq(#p, 0, "problems"); eq(s.bar.modules.clock.show, true, "clock")
end)
test("broken JSON gives defaults and a problem", function()
    local s, p, _, state = config.parse("{ nope", decode_broken)
    eq(state, "broken", "state"); eq(#p, 1, "problems"); eq(s.spine.max_workspaces, 10, "max")
end)
test("valid values are taken", function()
    local s, p, _, state = config.parse("x", decode_table({ version = 1, spine = { clock = false, max_workspaces = 6 }, atlas = { previews = false } }))
    eq(state, "ok", "state"); eq(#p, 0, "problems"); eq(s.bar.modules.clock.show, false, "clock"); eq(s.spine.max_workspaces, 6, "max")
    eq(s.island.confirm_close, true, "untouched default"); eq(s.atlas.previews, false, "previews off")
end)
test("an empty enum that allows it is the default, not a problem", function()
    -- settings.json held claude.model = "" (meaning "no --model") and every load reported it
    -- as a problem (audit 2026-10-29).
    local s, p, _, state = config.parse("x", decode_table({ claude = { model = "" } }))
    eq(state, "ok", "state"); eq(#p, 0, "no problem"); eq(s.claude.model, "default", "normalised")
    local bad, bp = config.validate({ claude = { model = "gpt" } })
    eq(#bp, 1, "a real unknown value is still refused"); eq(bad.claude.model, "default", "default kept")
end)
test("a wrong type falls back for that field only", function()
    local s, p, _, state = config.parse("x", decode_table({ spine = { clock = "yes", max_workspaces = 4 } }))
    eq(state, "partial", "state"); eq(#p, 1, "problems"); eq(s.bar.modules.clock.show, true, "clock default"); eq(s.spine.max_workspaces, 4, "max kept")
end)
test("spine.clock from an older mooi becomes the clock module's switch", function()
    local s, p, n = config.validate({ spine = { clock = false } })
    eq(#p, 0, "problems"); eq(#n, 0, "no unknown-setting note"); eq(s.bar.modules.clock.show, false, "clock hidden")
    local s2 = config.validate({ spine = { clock = false }, bar = { modules = { clock = { show = true } } } })
    eq(s2.bar.modules.clock.show, true, "the module's own switch wins")
    eq(config.defaults().spine.clock, nil, "no longer a setting of its own")
end)
test("previews are a setting, off only when false", function()
    local s, p = config.validate({ atlas = { previews = false } })
    eq(#p, 0, "problems"); eq(s.atlas.previews, false, "off")
    local _, p2 = config.validate({ atlas = { previews = "off" } })
    eq(#p2, 1, "a wrong type is reported")
end)
test("D90: the Atlas's bar module becomes the Overview's, and the layout is kept", function()
    local s, p = config.validate({ bar = { left = { "settings", "focus", "atlas", "clock" }, center = { "workspaces" },
                                           right = { "tray" },
                                           modules = { atlas = { show = false } } } })
    eq(#p, 0, "no problems")
    eq(s.bar.left[3], "overview", "a lone atlas entry is renamed")
    eq(s.bar.left[1], "settings", "the rest of the layout is kept, not reset to the default")
    eq(s.bar.modules.overview.show, false, "its per-module settings move with it")
    local g = config.validate({ bar = { left = { "actions+atlas", "clock" }, center = {}, right = { "tray" } } })
    eq(g.bar.left[1], "actions+overview", "inside a group too")
    eq(config.defaults().keys.atlas, nil, "the Atlas's key is gone")
end)
test("out-of-range and fractional numbers are rejected", function()
    local _, p1 = config.validate({ spine = { max_workspaces = 0 } }); eq(#p1, 1, "zero")
    local _, p2 = config.validate({ spine = { max_workspaces = 99 } }); eq(#p2, 1, "too many")
    local _, p3 = config.validate({ spine = { max_workspaces = 2.5 } }); eq(#p3, 1, "fraction")
end)
test("unknown keys are notes, not problems", function()
    local _, p, n = config.validate({ spine = { colour = "red" }, extra = 1 })
    eq(#p, 0, "problems"); eq(#n, 2, "notes"); eq(n[1], "unknown setting ignored: extra", "sorted first")
end)
test("a non-object is a problem", function()
    local _, p = config.validate({}); eq(#p, 0, "empty object fine")
    local _, p2 = config.validate("string"); eq(#p2, 1, "string")
end)
test("a whole section of the wrong type is reported, not silently reset", function()
    -- audit 2026-11-01, A1: { atlas = "nope" } gave no problem at all while every atlas setting
    -- quietly fell back to its default; a wrong leaf was reported, a wrong group was not.
    local s, p = config.validate({ atlas = "nope" })
    eq(#p, 1, "one problem"); eq(string.find(p[1], "atlas: expected a group", 1, true) ~= nil, true, "names the group")
    eq(s.atlas.overview, "grid", "and the defaults are used")
    local _, q = config.validate({ atlas = "nope", bar = 7, theme = { scheme = "tonal-spot" } })
    eq(#q, 2, "every wrong group, and nothing for the right one")
    eq(#(config.validate({ atlas = { rows = 2 } })), 0, "a right group stays quiet")
end)
test("the two choice transports have a default, and the window derives the real one", function()
    -- bar.edge / frame.motion had no default: a file carrying one kept a value nothing read.
    local d = config.defaults()
    eq(d.bar.edge, "none", "bar edge"); eq(d.frame.motion, "off", "frame motion")
    local style = require("lib/style")
    eq(style.edge_index(d), 3, "which edge is shown comes from bar.frame (line, 2 px: Regular)")
    eq(style.edge_index({ bar = { frame = "thin", outline_width = 2 } }), 3, "and from its width")
    eq(style.motion_index({ frame = { music = false } }), 0, "the frame's music, not the transport")
end)
test("a newer version is noted", function()
    local _, p, n = config.validate({ version = 3 }); eq(#p, 0, "problems"); eq(#n, 1, "notes")
end)

print("wfx")
local wfx = require("lib/wfx")
test("every pair writes both shaders, in the palette, for the plugin's ES 3.20", function()
    eq(wfx.pair("off", nil), nil, "off is no shader")
    eq(wfx.pair("nonsense"), nil, "and neither is a name that is not a pair's")
    for _, kind in ipairs(wfx.PAIRS) do
        local p = wfx.pair(kind, { phos = "#123456", ember = "#ff8800", trace = "#0a0b0c" })
        eq(type(p), "table", kind); eq(type(p.open), "string", kind .. " open"); eq(type(p.close), "string", kind .. " close")
        for _, src in ipairs({ p.open, p.close }) do
            assert(string.find(src, "#version 320 es", 1, true), kind .. " is ES 3.20")
            assert(string.find(src, "uniform float progress", 1, true), kind .. " runs on progress")
            eq(string.find(src, "uniform float time", 1, true), nil, kind .. " asks for no clock (nothing redraws for it)")
            -- `@duration` is the plugin's own marker and keeps its @; every other placeholder is filled
            assert(string.find(src, "@[%u]+@") == nil, kind .. " has every placeholder filled")
            assert(string.find(src, "@duration %d") ~= nil, kind .. " says how long it runs")
        end
        -- the palette reaches the shader as vec3s, and without one mooi's own phosphor is used
        assert(string.find(p.open, "0.071", 1, true), kind .. " uses the palette given")
        assert(string.find(wfx.pair(kind).open, "0.498", 1, true), kind .. " falls back to mooi's phosphor")
    end
end)
test("how long: the pair's own lengths, scaled by the setting", function()
    local function dur(src) return tonumber(string.match(src, "@duration (%d+%.?%d*)")) end
    eq(dur(wfx.pair("phosphor").open), 0.34, "as designed")
    eq(dur(wfx.pair("phosphor", nil, 50).open), 0.17, "half")
    eq(dur(wfx.pair("phosphor", nil, 200).close), 0.72, "twice as long (the close is 0.36)")
    assert(dur(wfx.pair("phosphor", nil, 0).open) > 0, "never nothing at all")
    assert(dur(wfx.pair("phosphor", nil, 9000).open) < 2, "never a minute")
    eq(wfx.duration("off"), nil, "off has no length")
end)
test("terminals and browsers carry a pair of their own, by class", function()
    local apps = wfx.apps(nil, 100)
    eq(#apps, #wfx.APPS, "one per app")
    local names = {}
    for _, a in ipairs(apps) do
        assert(type(a.class) == "string" and string.sub(a.class, 1, 1) == "^", a.name .. " matches a class")
        assert(type(a.open) == "string" and type(a.close) == "string", a.name .. " has both shaders")
        names[#names + 1] = a.name
    end
    eq(table.concat(names, ","), "terminal,browser", "the two there are")
end)
test("the window rules: two _default tags, or none while off", function()
    local desktop = require("lib/desktop")
    eq(#desktop.window_rules(nil), 0, "off writes no rule")
    eq(#desktop.window_rules({ open = "/x/open.glsl" }), 0, "half a pair is no pair")
    local rules = desktop.window_rules({ open = "/x/open.glsl", close = "/x/close.glsl" })
    eq(#rules, 2, "one each")
    assert(string.find(rules[1], "shader_open_default:/x/open.glsl", 1, true), rules[1])
    assert(string.find(rules[2], "shader_close_default:/x/close.glsl", 1, true), rules[2])
    for _, r in ipairs(rules) do assert(string.find(r, 'class = ".*"', 1, true), "every window takes them") end
    local with = desktop.window_rules({ open = "/x/o.glsl", close = "/x/c.glsl",
        apps = { { name = "terminal", class = "^(kitty)$", open = "/x/ot.glsl", close = "/x/ct.glsl" } } })
    eq(#with, 4, "the pair and the app's own")
    assert(string.find(with[3], "shader_open:/x/ot.glsl", 1, true), with[3])
    eq(string.find(with[3], "_default", 1, true), nil, "the app's tag is not a fallback, so it wins")
    assert(string.find(with[4], 'class = "^(kitty)$"', 1, true), "matched by class")
end)

print("fx colours")
local fxpal = require("lib/fxpal")
test("the shaders' light: the bar's palette, or a way of its own", function()
    local pal = { phos = "#112233", ember = "#445566", trace = "#778899" }
    eq(fxpal.of("palette", pal).phos, "#112233", "palette is used as it comes")
    eq(fxpal.of("palette", pal).trace, "#778899", "all three of it")
    eq(fxpal.of("amber").phos, fxpal.FIXED.amber.phos, "a way is its own")
    eq(fxpal.of("nonsense").phos, fxpal.FIXED.phosphor.phos, "an unknown way is mooi's phosphor")
    eq(fxpal.of("palette", nil).phos, fxpal.FIXED.phosphor.phos, "no palette yet, no trouble")
    for _, way in ipairs(fxpal.WAYS) do
        local w = fxpal.of(way)
        assert(type(w.phos) == "string" and string.sub(w.phos, 1, 1) == "#", way .. " is a colour")
        assert(type(w.ember) == "string" and type(w.trace) == "string", way .. " has all three")
    end
end)
test("the light of your own, and the wallpaper's as Matugen read it", function()
    local mine = fxpal.of("custom", nil, { phos = "#ff0000", ember = "#00ff00", trace = "#123456" })
    eq(mine.phos, "#ff0000", "the first colour is the light")
    eq(mine.ember, "#00ff00", "the second is its signal")
    eq(mine.trace, "#123456", "the third the ground")
    local broken = fxpal.of("custom", nil, { phos = "red", ember = "#abc" })
    eq(broken.phos, fxpal.FIXED.phosphor.phos, "what is not a colour falls back")
    eq(broken.trace, fxpal.FIXED.phosphor.trace, "each stop of its own, not all three")
    eq(fxpal.of("custom", nil, nil).phos, fxpal.FIXED.phosphor.phos, "nothing typed yet is mooi's phosphor")
    local scheme = { colours = { primary = "#0a0b0c", tertiary = "#0d0e0f", secondary = "#101112" } }
    local mat = fxpal.of("matugen", nil, nil, scheme)
    eq(mat.phos, "#0a0b0c", "Matugen's primary")
    eq(mat.ember, "#0d0e0f", "its tertiary as the second signal")
    eq(mat.trace, "#101112", "its secondary as the ground")
    local bare = fxpal.of("matugen", { phos = "#123456", ember = "#234567", trace = "#345678" }, nil, {})
    eq(bare.phos, "#123456", "a scheme that is not there keeps the bar's palette")
    local wsfx = require("lib/wsfx")
    assert(string.find(wsfx.glsl("channel", mine, 100), "const vec3 PHOS = vec3(1.000, 0.000, 0.000);", 1, true),
        "and the shader is drawn in it")
end)
test("the workspace shader's length scales, and its own clock with it", function()
    local wsfx = require("lib/wsfx")
    eq(wsfx.dur_ms("channel"), 620, "as designed")
    eq(wsfx.dur_ms("channel", 50), 310, "half")
    eq(wsfx.dur_ms("channel", 200), 1240, "twice as long")
    assert(string.find(wsfx.glsl("channel", nil, 50), "const float DUR = 0.310;", 1, true), "the shader agrees with the watcher")
    assert(string.find(wsfx.glsl("channel"), "const float DUR = 0.620;", 1, true), "and at 100 percent")
    eq(wsfx.dur_ms("off"), nil, "off has no length")
    eq(wsfx.duration("nothing"), nil, "an unknown kind too")
end)

print("hypr")
local A = "0x556d06fdfab0"
test("addresses are validated before reaching a command", function()
    eq(hypr.valid_address(A), true, "good")
    eq(hypr.valid_address('0x1" }) hl.dsp.exec_cmd("rm'), false, "injection")
    eq(hypr.valid_address(""), false, "empty"); eq(hypr.valid_address(nil), false, "nil")
    local cmd, err = hypr.dispatch("close", "0xZZ"); eq(cmd, nil, "no cmd"); eq(err, "invalid window address", "err")
end)
test("dispatch builds the verified Lua forms", function()
    eq(hypr.dispatch("float", A), 'hl.dsp.window.float({ action = "toggle", window = "address:' .. A .. '" })', "float")
    eq(hypr.dispatch("fullscreen", A), 'hl.dsp.window.fullscreen({ action = "toggle", window = "address:' .. A .. '" })', "fullscreen")
    eq(hypr.dispatch("pin", A), 'hl.dsp.window.pin({ window = "address:' .. A .. '" })', "pin")
    eq(hypr.dispatch("close", A), 'hl.dsp.window.close({ window = "address:' .. A .. '" })', "close")
    eq(hypr.dispatch("move", A, { workspace = 3 }), 'hl.dsp.window.move({ workspace = 3, follow = false, window = "address:' .. A .. '" })', "move")
    eq(hypr.dispatch("move", A, { workspace = 3, follow = true }), 'hl.dsp.window.move({ workspace = 3, follow = true, window = "address:' .. A .. '" })', "follow")
end)
test("move rejects bad workspaces", function()
    eq(hypr.dispatch("move", A, { workspace = 0 }), nil, "zero")
    eq(hypr.dispatch("move", A, { workspace = 1.5 }), nil, "fraction")
    eq(hypr.dispatch("move", A, { workspace = "3" }), nil, "string")
    eq(hypr.dispatch("explode", A), nil, "unknown action")
end)
local raw = { address = A, class = "kitty", title = "t", floating = false, pinned = false, fullscreen = 0, workspace = { id = 1, name = "1" } }
test("client() reduces hyprctl JSON", function()
    local c = hypr.client(raw)
    eq(c.class, "kitty", "class"); eq(c.workspace, 1, "ws"); eq(c.fullscreen, false, "fs")
    eq(hypr.client({ address = A, fullscreen = 2, workspace = { id = 4 } }).fullscreen, true, "fs 2")
    eq(hypr.client({ address = A, fullscreen = 1, workspace = { id = 4 } }).fullscreen, false, "maximized is not fullscreen")
    eq(hypr.client({}), nil, "empty activewindow"); eq(hypr.client(nil), nil, "nil")
end)
test("find() locates by address", function()
    eq(hypr.find({ raw }, A).class, "kitty", "found"); eq(hypr.find({ raw }, "0x1"), nil, "missing"); eq(hypr.find(nil, A), nil, "nil list")
end)
test("verify() only reports what changed", function()
    local before = hypr.client(raw)
    local floated = hypr.client({ address = A, floating = true, workspace = { id = 1 } })
    eq((hypr.verify("float", before, floated)), true, "float changed")
    eq((hypr.verify("float", before, before)), false, "float unchanged")
    eq((hypr.verify("float", before, nil)), false, "float gone")
    eq((hypr.verify("pin", before, before)), false, "pin on tiled")
    eq((hypr.verify("close", before, nil)), true, "closed")
    eq((hypr.verify("close", before, before)), false, "still open")
    local maxed = hypr.client({ address = A, fullscreen = 1, workspace = { id = 1 } })
    local full = hypr.client({ address = A, fullscreen = 2, workspace = { id = 1 } })
    eq((hypr.verify("fullscreen", maxed, full)), true, "maximized → fullscreen is a change")
    eq((hypr.verify("fullscreen", full, full)), false, "fullscreen unchanged")
    local moved = hypr.client({ address = A, workspace = { id = 5 } })
    eq((hypr.verify("move", before, moved, { workspace = 5 })), true, "moved")
    eq((hypr.verify("move", before, before, { workspace = 5 })), false, "not moved")
end)

print("apps")
local list = {
    { name = "Zen Browser", id = "zen", exec = "/opt/zen-browser-bin/zen-bin %u", icon = "zen-browser", wmclass = "zen" },
    { name = "Files", id = "org.gnome.Nautilus", exec = "nautilus --new-window %U", icon = "org.gnome.Nautilus" },
    { name = "kitty", id = "kitty", exec = "kitty", icon = "kitty" },
    { name = "No Icon", id = "noicon", exec = "noicon", icon = "" },
}
local idx = apps.index(list)
test("class resolves through wmclass, id, id tail, exec", function()
    eq(apps.icon_for(idx, "zen"), "zen-browser", "wmclass")
    eq(apps.icon_for(idx, "org.gnome.Nautilus"), "org.gnome.Nautilus", "id, any case")
    eq(apps.icon_for(idx, "nautilus"), "org.gnome.Nautilus", "id tail")
    eq(apps.icon_for(idx, "zen-bin"), "zen-browser", "exec basename")
    eq(apps.icon_for(idx, "Kitty"), "kitty", "case-insensitive")
end)
test("no match and empty icons give nil", function()
    eq(apps.icon_for(idx, "unknown"), nil, "unknown"); eq(apps.icon_for(idx, "noicon"), nil, "empty icon")
    eq(apps.icon_for(idx, ""), nil, "empty class"); eq(apps.icon_for(nil, "zen"), nil, "no index yet")
end)
test("letter fallback", function()
    eq(apps.letter("zen"), "z", "letter"); eq(apps.letter(""), "", "none"); eq(apps.letter("--x"), "x", "skips symbols")
end)

test("satellite actions: focus and bring", function()
    eq(hypr.dispatch("focus", A), 'hl.dsp.focus({ window = "address:' .. A .. '" })', "focus")
    eq(hypr.dispatch("bring", A, { workspace = 2, follow = true }), 'hl.dsp.window.move({ workspace = 2, follow = false, window = "address:' .. A .. '" })', "bring never follows")
    local before = hypr.client({ address = A, class = "k", focusHistoryID = 3, workspace = { id = 4 } })
    local now = hypr.client({ address = A, class = "k", focusHistoryID = 0, workspace = { id = 2 } })
    eq((hypr.verify("focus", before, now)), true, "focused"); eq((hypr.verify("focus", before, before)), false, "not focused")
    eq((hypr.verify("bring", before, now, { workspace = 2 })), true, "brought"); eq((hypr.verify("bring", before, before, { workspace = 2 })), false, "not brought")
end)
test("windows(): mapped, visible, most recent first", function()
    local list = hypr.windows({
        { address = "0x1", class = "a", focusHistoryID = 2, workspace = { id = 1 } },
        { address = "0x2", class = "b", focusHistoryID = 0, workspace = { id = 1 } },
        { address = "0x3", class = "c", focusHistoryID = 1, hidden = true, workspace = { id = 1 } },
        { address = "0x4", class = "d", focusHistoryID = 3, mapped = false, workspace = { id = 1 } },
    })
    eq(#list, 2, "hidden and unmapped left out"); eq(list[1].class, "b", "focused first"); eq(list[2].class, "a", "then older")
end)

print("spaces")
test("rows make a bounded map including empty slots", function()
    local rows = spaces.rows({ { id = 1, windows = 2, name = "1", monitor = "eDP-1" }, { id = 4, windows = 0, name = "mail" }, { id = -99, windows = 7 } }, 4, 6)
    eq(#rows, 6, "configured slot count")
    eq(rows[1].id, 1, "first workspace")
    eq(rows[1].windows, 2, "real window count")
    eq(rows[1].exists, true, "workspace exists")
    eq(rows[1].label, "01", "a workspace with no name of its own says its number, padded")
    eq(rows[1].monitor, "eDP-1", "the monitor it is on")
    eq(rows[2].windows, 0, "empty slot has no windows")
    eq(rows[2].exists, false, "empty slot is distinguished")
    eq(rows[4].active, true, "active workspace")
    eq(rows[4].label, "mai", "a named workspace says its name, shortened for the bar")
    eq(rows[6].id, 6, "last configured slot")
end)
test("rows clamp limits and reject invalid workspace identifiers", function()
    eq(#spaces.rows({}, 0, 0), 1, "minimum")
    eq(#spaces.rows({}, 0, 99), 16, "maximum")
    local rows = spaces.rows({ { id = 2.5, windows = 8 }, { id = 100, windows = 4 }, { id = 2, windows = -1 } }, 9, 3)
    eq(rows[2].exists, true, "integer positive workspace retained")
    eq(rows[2].windows, 0, "negative count clamped")
    eq(rows[3].exists, false, "invalid ids ignored")
end)
test("labels shorten a name to what the bar holds", function()
    eq(spaces.short("scratchpad", 3), "scr", "three letters")
    eq(spaces.short("ab", 3), "ab", "shorter than asked")
    eq(spaces.short("anything", 0), "a", "never nothing")
    eq(spaces.short(nil, 3), "", "no text")
    eq(spaces.short("Ñandú", 3), "Ñan", "letters, not bytes")
    eq(spaces.short("音楽です", 2), "音楽", "never through the middle of a letter")
    eq(spaces.short("\255\254abc", 3), "\255\254a", "text that is not UTF-8 is cut by bytes")
    eq(spaces.label("", 12), "12", "a number when there is no name")
    eq(spaces.label("", 3), "03", "one figure is padded to two")
    eq(spaces.label("3", 3), "03", "Hyprland's own name for an unnamed workspace is a number too")
    eq(spaces.label("web", 3), "web", "the name when there is one")
    eq(spaces.label("a-long-name", 9), "a-l", "shortened")
end)
test("tail keeps the end of a path, for a plate 196 px wide", function()
    eq(spaces.tail("abcdefghij", 5), "…ghij", "the end, as long as it was asked")
    eq(spaces.tail("/home/ñoño/música", 7), "…música", "the end, in letters")
    -- `n` counts what is shown, and an ellipsis is three bytes: 26 characters is at most 28.
    eq(#spaces.tail("/home/x/.local/share/pleamar/mooi/settings.json", 26) <= 28, true, "never longer than asked")
    eq(string.sub(spaces.tail("/home/x/.local/share/pleamar/mooi/settings.json", 26), -18), "mooi/settings.json", "the file name survives")
    eq(spaces.tail("short.json", 26), "short.json", "left as it is")
end)

print("theme")
local theme = require("lib/theme")
local matugen_dark = { version = 1, mode = "dark", colours = {
    surface_dim = "#16130b", surface_container_low = "#1e1b13", surface_container = "#221f17",
    surface_container_high = "#2d2a21", outline_variant = "#4b4639", outline = "#979080",
    on_surface = "#e9e2d4", on_surface_variant = "#cec6b4", primary = "#dfc56d", error = "#ffb4ab",
} }
test("hex parses, round-trips and refuses what is not a colour", function()
    local c = theme.hex("#A6F3D1"); eq(theme.to_hex(c), "#A6F3D1", "round trip")
    eq(theme.hex("A6F3D1"), nil, "no hash"); eq(theme.hex("#fff"), nil, "short"); eq(theme.hex(12), nil, "number")
    eq(math.abs(c.r - 0.6510) < 0.001, true, "red")
end)
test("contrast matches WCAG for known pairs", function()
    local white, black = theme.hex("#FFFFFF"), theme.hex("#000000")
    eq(math.floor(theme.contrast(white, black) + 0.5), 21, "white on black")
    eq(theme.contrast(white, white), 1, "same colour")
end)
local ferro_t = require("lib/ferro")
local function roles_of(source, palette, opts) return (ferro_t.resolve(source, palette, "auto", false, opts or {})) end
test("one palette: the tokens come from the shell's palette, complete and readable", function()
    eq(#theme.TOKENS, 14, "tokens")
    for _, source in ipairs({ "fixed", "wallpaper" }) do
        local colours, _, problems = theme.resolve({}, roles_of(source, matugen_dark))
        for _, t in ipairs(theme.TOKENS) do eq(type(colours[t]), "table", source .. " " .. t) end
        eq(#problems, 0, source .. " passes its own check")
    end
    local r = roles_of("wallpaper", matugen_dark)
    local colours = theme.resolve({}, r)
    eq(theme.to_hex(colours["accent.primary"]), theme.to_hex(r.phos), "the accent is the phosphor")
    eq(theme.to_hex(colours["accent.secondary"]), theme.to_hex(r.ember), "the second accent is the ember")
    eq(theme.to_hex(colours["surface.primary"]), theme.to_hex(r.hull), "surfaces are the hull")
end)
test("a background chosen for the shell reaches the islands, still readable", function()
    for _, tone in ipairs({ "concrete", "titanium", "sand", "alien" }) do
        local r = roles_of("wallpaper", matugen_dark, { bg = { kind = tone } })
        local colours, _, problems = theme.resolve({}, r)
        eq(#problems, 0, tone .. " passes")
        eq(theme.to_hex(colours["surface.primary"]), theme.to_hex(r.hull), tone .. " is the islands' surface")
    end
end)
test("a light, saturated base (the one that was refused) is held readable on every surface", function()
    local r = roles_of("wallpaper", matugen_dark, { bg = { kind = "obsidian", light = 40, sat = 150, hue = 90 } })
    local _, _, problems = theme.resolve({}, r)
    eq(#problems, 0, table.concat(problems, "; "))
    for _, tone in ipairs({ "black", "wallpaper", "accent", "concrete", "titanium", "sand", "alien", "gunmetal", "oxide" }) do
        for _, light in ipairs({ -10, 0, 20, 40 }) do
            local rr = roles_of("wallpaper", matugen_dark, { bg = { kind = tone, light = light, sat = 150, hue = 45 } })
            local _, _, p2 = theme.resolve({}, rr)
            eq(#p2, 0, tone .. " at " .. light .. ": " .. table.concat(p2, "; "))
        end
    end
end)
test("an override wins over the palette, and is reported", function()
    local colours, notes, problems = theme.resolve(
        { overrides = { ["accent.primary"] = "#00FF00", ["nonsense"] = "#FFFFFF", ["fg.primary"] = "green" } },
        roles_of("wallpaper", matugen_dark))
    eq(theme.to_hex(colours["accent.primary"]), "#00FF00", "override wins")
    eq(#problems, 0, "still valid")
    local said = table.concat(notes, " | ")
    assert(string.find(said, "override fg.primary: not a colour like #A6F3D1; ignored", 1, true), said)
    assert(string.find(said, "override for unknown token nonsense; ignored", 1, true), said)
    assert(string.find(said, "user overrides: accent.primary", 1, true), said)
end)
test("an override that makes text unreadable is refused, token by token", function()
    local _, _, problems = theme.resolve({ overrides = { ["fg.muted"] = "#050505" } }, roles_of("fixed"))
    eq(#problems, 3, "fg.muted on its three surfaces")
end)

test("theme settings are validated like any other", function()
    local s, p = config.validate({ theme = { source = "wallpaper", overrides = { ["accent.primary"] = "#112233" } } })
    eq(#p, 0, "problems"); eq(s.theme.source, "wallpaper", "source"); eq(s.theme.overrides["accent.primary"], "#112233", "override")
    local _, p2 = config.validate({ theme = { source = "blue" } }); eq(#p2, 1, "unknown source")
    local _, p3 = config.validate({ theme = { overrides = { ["fg.primary"] = "red" } } }); eq(#p3, 1, "bad colour")
    local d = config.defaults()
    eq(d.theme.source, "wallpaper", "the wallpaper colours the bar by default")
    eq(d.theme.overrides, nil, "no overrides written by default")
end)

test("the bar's own settings are validated like any other", function()
    local s, p = config.validate({ bar = { labels = false, wheel = "off" } })
    eq(#p, 0, "problems"); eq(s.bar.labels, false, "labels off"); eq(s.bar.wheel, "off", "wheel off")
    local _, p2 = config.validate({ bar = { wheel = "sometimes" } }); eq(#p2, 1, "unknown wheel")
    local _, p3 = config.validate({ bar = { labels = "off" } }); eq(#p3, 1, "labels is a boolean")
end)

print("search")
local search = require("lib/search")
test("score orders exact > prefix > word start > substring > fuzzy", function()
    local e, p, w, s, f = search.score("code", "code"), search.score("code", "codeblocks"),
        search.score("code", "visual studio code"), search.score("code", "xcodes"), search.score("vsc", "visual studio code")
    assert(e > p and p > w and w > s and s > f, string.format("%s %s %s %s %s", e, p, w, s, f))
    eq(search.score("zz", "firefox"), nil, "no match")
    eq(search.score("", "anything"), 0, "empty query")
end)
test("fuzzy rewards runs and word starts", function()
    assert(search.score("vsc", "visual studio code") > search.score("vsc", "avaslcxx"), "word starts")
    assert(search.score("fir", "fxixr") == nil or search.score("fire", "firefox") > search.score("fir", "fxixr"), "runs")
end)
local items = {
    { title = "Firefox", alt = { "firefox", "Web Browser" }, kind = "app", key = "app:firefox" },
    { title = "Files", alt = { "nautilus" }, kind = "app", key = "app:files" },
    { title = "Visual Studio Code", alt = { "code" }, kind = "app", key = "app:code" },
    { title = "kitty — ~/Projects", alt = { "kitty" }, kind = "window", key = "win:1" },
}
test("rank returns matches best first, limited", function()
    local r = search.rank(items, "fi", {}, 10)
    eq(r[1].title, "Files", "shorter prefix first"); eq(r[2].title, "Firefox", "then firefox"); eq(#r, 2, "two match")
    eq(#search.rank(items, "", {}, 3), 3, "empty query: everything, limited")
end)
test("alt names match at lower weight", function()
    local r = search.rank(items, "nautilus", {}, 5)
    eq(r[1].title, "Files", "found by alt")
    eq(search.rank(items, "browser", {}, 5)[1].title, "Firefox", "word in alt")
end)
test("usage lifts an item, capped", function()
    eq(search.rank(items, "fi", { ["app:firefox"] = 5 }, 5)[1].title, "Firefox", "used more wins")
    local r = search.rank(items, "code", { ["app:files"] = 1000 }, 5)
    eq(r[1].title, "Visual Studio Code", "cap keeps relevance first")
end)
test("parse prefixes", function()
    local p = search.parse("  @fire "); eq(p.kinds.window, true, "@ windows"); eq(p.text, "fire", "@ text")
    eq(search.parse(">sys").kinds.action, true, "> actions")
    eq(search.parse("3").workspace, 3, "number → workspace"); eq(search.parse("fire").kinds, nil, "plain")
end)
test("remember counts and forgets the least used half past the cap", function()
    local u = {}
    for i = 1, 5 do search.remember(u, "k" .. i, 4) end
    local n = 0; for _ in pairs(u) do n = n + 1 end
    assert(n <= 4, "capped at " .. n)
    search.remember(u, "k5", 4); eq(u.k5, 2, "counted")
end)

print("ferro")
local ferro = require("lib/ferro")
local black = { r = 0, g = 0, b = 0 }
-- A real Matugen dark palette (scheme-tonal-spot, a teal wallpaper), and a monochrome one.
local teal = { colours = { primary = "#82d5c7", secondary = "#b1ccc6", tertiary = "#adcae6",
    surface_container_lowest = "#090f0e", surface_container_low = "#171d1c" } }
local grey = { colours = { primary = "#c6c6c6", secondary = "#c6c6c6", tertiary = "#c6c6c6",
    surface_container_lowest = "#0e0e0e" } }
test("fixed is Ferrolume's own palette, every role", function()
    local out, why = ferro.resolve("fixed", nil, "auto", false)
    eq(why, "fixed", "source")
    for _, role in ipairs(ferro.ROLES) do assert(out[role], "missing " .. role) end
    eq(ferro.to_hex(out.phos), "#7fcfb6", "phos"); eq(ferro.to_hex(out.ember), "#e07b2e", "ember")
end)
test("alert wins over any source", function()
    local out, why = ferro.resolve("wallpaper", teal, "auto", true)
    eq(why, "alert", "source"); eq(ferro.to_hex(out.phos), "#f2b26a", "amber phosphor")
end)
test("a wallpaper palette keeps the design's contrast floors", function()
    for _, pal in ipairs({ teal, grey }) do
        local out = ferro.resolve("wallpaper", pal, "auto", false)
        for _, role in ipairs(ferro.ROLES) do assert(out[role], "missing " .. role) end
        assert(ferro.contrast(out.phos, black) >= 7, "phos 7:1")
        assert(ferro.contrast(out.ember, black) >= 6, "ember 6:1")
        assert(ferro.contrast(out.muted, black) >= 4.5, "muted 4.5:1")
        assert(ferro.contrast(out.trace, black) >= 3, "trace 3:1")
        assert(ferro.contrast(out.phos_fill, out.ink) >= 4.5, "ink on phos-fill 4.5:1")
        assert(ferro.contrast(out.ember_fill, out.ink) >= 4.5, "ink on ember-fill 4.5:1")
        assert(ferro.contrast(out.engrave, out.steel_700) >= 4.5, "engrave on steel 4.5:1")
    end
end)
test("the floors hold on the hulls strokes and muted text are painted on", function()
    -- Measured on the live wallpaper palette (audit 2026-10-29): holding against black alone left
    -- muted at 4.4:1 and trace at 2.8:1 on hull_raised, because only the ground is black.
    local cases = {
        { "fixed", nil, false, {} },
        { "wallpaper", teal, false, {} },
        { "wallpaper", teal, true, {} },
        { "wallpaper", grey, false, {} },
        { "wallpaper", teal, false, { mode = "light" } },
    }
    for _, c in ipairs(cases) do
        local out = ferro.resolve(c[1], c[2], "auto", c[3], c[4])
        assert(ferro.contrast(out.muted, out.hull) >= 4.5, "muted on hull")
        assert(ferro.contrast(out.muted, out.hull_raised) >= 4.5, "muted on raised hull")
        assert(ferro.contrast(out.trace, out.hull) >= 3, "trace on hull")
        assert(ferro.contrast(out.trace, out.hull_raised) >= 3, "trace on raised hull")
        assert(ferro.contrast(out.trace_lit, out.hull_raised) >= 3, "trace_lit on raised hull")
    end
end)
test("the phosphor keeps the wallpaper's hue", function()
    local out = ferro.resolve("wallpaper", teal, "auto", false)
    local h1 = ferro.to_hsl(ferro.hex("#82d5c7")); local h2 = ferro.to_hsl(out.phos)
    assert(math.abs(h1 - h2) < 3, "hue moved from " .. h1 .. " to " .. h2)
end)
test("the second signal is chosen to stand apart from the phosphor", function()
    -- teal's tertiary (blue) and secondary (grey-teal) are both near its primary: the
    -- complement wins, and a monochrome palette gets the complement too
    local _, why = ferro.resolve("wallpaper", teal, "auto", false)
    eq(why, "wallpaper · second signal from complement", "teal")
    local warm = { colours = { primary = "#82d5c7", tertiary = "#ffb68a", secondary = "#b1ccc6" } }
    local _, why2 = ferro.resolve("wallpaper", warm, "auto", false)
    eq(why2, "wallpaper · second signal from tertiary", "a distinct tertiary is used")
    local _, why3 = ferro.resolve("wallpaper", warm, "secondary", false)
    eq(why3, "wallpaper · second signal from secondary", "named source is respected")
end)
test("a grey palette keeps the whole bar grey, the signals parted by lightness", function()
    local out, why = ferro.resolve("wallpaper", grey, "auto", false)
    eq(why, "wallpaper · second signal from lightness (a grey palette)", "says how")
    for _, role in ipairs({ "phos", "phos_fill", "ember", "ember_fill", "trace", "steel_500" }) do
        local _, s = ferro.to_hsl(out[role]); assert(s < 0.01, role .. " is tinted (" .. s .. ")")
    end
    assert(math.abs(ferro.luminance(out.phos) - ferro.luminance(out.ember)) > 0.2, "signals part by lightness")
end)
test("no palette or no primary falls back to Ferrolume, with a note", function()
    local out, why = ferro.resolve("wallpaper", nil, "auto", false)
    eq(ferro.to_hex(out.phos), "#7fcfb6", "fixed"); eq(why, "fixed (the palette has no colours)", "says why")
    local _, why2 = ferro.resolve("wallpaper", { colours = {} }, "auto", false)
    eq(why2, "fixed (the palette has no primary)", "says why")
end)

print("barlayout")
local barlayout = require("lib/barlayout")
local function ctx(t)
    local c = { screen = 1920, inset = 12, gap = 10, ws_style = "dna", ws_count = 10, visualizer = "mirror",
                playing = false, media_mode = "full", media_idle = "collapse",
                tray = 2, battery = true, brightness = true, bluetooth = true }
    for k, v in pairs(t or {}) do c[k] = v end
    return c
end
test("every module in the catalogue is in the order, and the default places each once", function()
    local n = 0
    for _ in pairs(barlayout.MODULES) do n = n + 1 end
    eq(#barlayout.ORDER, n, "order covers the catalogue")
    local seen = {}
    for _, side in ipairs({ "left", "center", "right" }) do
        local ok, why = barlayout.check_list(barlayout.DEFAULT[side], seen); assert(ok, why)
    end
end)
test("the default layout fits a 1920 px screen", function()
    local out = barlayout.layout({ left = barlayout.DEFAULT.left, center = barlayout.DEFAULT.center,
        right = barlayout.DEFAULT.right, mode = "islands" }, ctx())
    eq(out.overflow, false, "no overflow")
    assert(out.x.workspaces == 12, "left starts at the inset")
    assert(out.x.core + 40 == 1920 - 12, "right ends at the inset")
end)
test("a group shares one frame, with a hairline between members", function()
    local out = barlayout.layout({ left = {}, center = {}, right = { "network+bluetooth" }, mode = "islands" }, ctx())
    eq(#out.frames, 1, "one frame"); eq(out.frames[1].w, 68 + 64, "both widths")
    eq(#out.dividers, 1, "one hairline"); eq(out.dividers[1].x, out.x.bluetooth, "at the seam")
end)
test("frames and dividers name the modules they sit between", function()
    local out = barlayout.layout({ left = {}, center = {}, right = { "network+bluetooth", "clock" }, mode = "islands" }, ctx())
    eq(out.frames[1].a, barlayout.INDEX.network, "first"); eq(out.frames[1].b, barlayout.INDEX.bluetooth, "last")
    eq(out.dividers[1].p, barlayout.INDEX.network, "after"); eq(out.dividers[1].m, barlayout.INDEX.bluetooth, "before")
end)
test("split, a group becomes two frames with a gap", function()
    local out = barlayout.layout({ left = {}, center = {}, right = { "network", "bluetooth" }, mode = "islands" }, ctx())
    eq(#out.frames, 2, "two frames"); eq(out.x.bluetooth - (out.x.network + 68), 10, "the gap")
end)
test("what is hidden or absent takes no room; an emptied group disappears", function()
    local out = barlayout.layout({ left = {}, center = {}, right = { "brightness+battery", "clock" },
        show = { clock = false }, mode = "islands" }, ctx({ battery = false, brightness = false }))
    eq(#out.frames, 0, "nothing left"); eq(out.x.clock, nil, "clock hidden"); eq(out.x.battery, nil, "no battery")
end)
test("the centre is centred, unless it would collide", function()
    local out = barlayout.layout({ left = { "window" }, center = { "clock" }, right = {}, mode = "islands" }, ctx())
    eq(out.x.clock, math.floor((1920 - 120) / 2 + 0.5), "centred on the screen")
    local wide = barlayout.layout({ left = { "workspaces", "window", "media" }, center = { "clock" }, right = {}, mode = "islands" }, ctx())
    assert(wide.x.clock >= 12 + 222 + 10 + 150 + 10 + 280 + 10, "pushed right of the left cluster")
end)
test("full mode: one panel, dividers between groups, boxes for the bays", function()
    local out = barlayout.layout({ left = { "workspaces" }, center = {}, right = { "clock", "power+core" }, mode = "full" }, ctx())
    eq(#out.frames, 3, "a box per group, for the bays"); assert(out.panel and out.panel.w > 1800, "a panel")
    local strong = 0
    for _, d in ipairs(out.dividers) do if d.strong then strong = strong + 1 end end
    eq(strong, 2, "between clock and power+core, and at the clusters' seam")
end)
test("dividers carry the line and gap the layout computed", function()
    local out = barlayout.layout({ left = { "workspaces" }, center = { "media" }, right = { "clock", "power+core" }, mode = "full" }, ctx())
    local strong = {}
    for _, d in ipairs(out.dividers) do
        eq(type(d.x), "number", "a line")
        eq(type(d.gap), "number", "a gap")
        if d.strong then strong[#strong + 1] = d
        else eq(d.x, out.x.core, "a member's seam"); eq(d.gap, 0, "no gap inside a group") end
    end
    eq(#strong, 3, "a seam between each pair of groups")
    for _, d in ipairs(strong) do
        assert(d.gap > 0, "a seam has room")
        assert(d.x > out.panel.x and d.x < out.panel.x + out.panel.w, "and sits on the panel")
    end
end)
test("the media follows its mode, and with nothing playing stays, collapses or leaves", function()
    local function mw(t) local c = ctx(t); return barlayout.layout({ left = {}, center = { "media" }, right = {}, mode = "islands" }, c) end
    eq(barlayout.width("media", ctx({ playing = true, media_mode = "full" })), 280, "full")
    eq(barlayout.width("media", ctx({ playing = true, media_mode = "art" })), 204, "art")
    eq(barlayout.width("media", ctx({ playing = true, media_mode = "viz" })), 96, "viz")
    eq(barlayout.width("media", ctx({ playing = false, media_mode = "full", media_idle = "collapse" })), 40, "collapsed")
    eq(mw({ playing = false, media_idle = "hide" }).x.media, nil, "hidden while idle")
    assert(mw({ playing = false, media_idle = "keep" }).x.media, "kept while idle")
end)
test("edit: a module dropped on another's middle joins its group", function()
    local cfg = { left = { "workspaces" }, center = {}, right = { "network", "clock" }, mode = "islands" }
    local out = barlayout.layout(cfg, ctx())
    local lists = barlayout.drop(cfg, ctx(), "battery", out.x.clock + 56)
    eq(lists.right[2], "clock+battery", "grouped with the clock")
end)
test("edit: dropped beside a module it goes before or after it, and leaves its old place", function()
    local cfg = { left = { "workspaces", "window" }, center = {}, right = { "network+bluetooth", "clock" }, mode = "islands" }
    local out = barlayout.layout(cfg, ctx())
    local lists = barlayout.drop(cfg, ctx(), "bluetooth", out.x.clock + 2)
    eq(lists.right[1], "network", "left its group"); eq(lists.right[2], "bluetooth", "before the clock"); eq(lists.right[3], "clock", "clock after")
    local l2 = barlayout.drop(cfg, ctx(), "window", out.x.clock + 110)
    eq(#l2.left, 1, "gone from the left"); eq(l2.right[#l2.right], "window", "after the clock")
end)
test("edit: dropped mid-screen with no centre, it starts the centre", function()
    local cfg = { left = { "workspaces" }, center = {}, right = { "clock" }, mode = "islands" }
    local lists = barlayout.drop(cfg, ctx(), "media", 960)
    eq(lists.center[1], "media", "the centre")
end)
test("edit: the arrows walk a module through its group, its list and into the next list", function()
    local cfg = { left = { "workspaces" }, center = { "media" }, right = { "network+bluetooth", "clock" } }
    local l1 = barlayout.nudge(cfg, "network", 1); eq(l1.right[1], "bluetooth+network", "within the group")
    local l2 = barlayout.nudge(cfg, "network", -1); eq(l2.right[1], "network", "out of the group, before it"); eq(l2.right[2], "bluetooth", "the rest stays")
    local l3 = barlayout.nudge(cfg, "clock", -1); eq(l3.right[1], "clock", "trades places")
    local l4 = barlayout.nudge(cfg, "media", -1); eq(#l4.center, 0, "left the centre"); eq(l4.left[2], "media", "at the end of the left")
    local l5 = barlayout.nudge(cfg, "workspaces", -1); eq(l5.left[1], "workspaces", "nowhere further left")
end)
test("edit: merge with either neighbour, and split", function()
    local cfg = { left = {}, center = {}, right = { "network", "bluetooth", "clock" } }
    eq(barlayout.join(cfg, "bluetooth", -1).right[1], "network+bluetooth", "with the one before")
    eq(barlayout.join(cfg, "bluetooth", 1).right[2], "bluetooth+clock", "with the one after")
    local g = { left = {}, center = {}, right = { "network+bluetooth+clock" } }
    local sp = barlayout.join(g, "bluetooth", 0)
    eq(sp.right[1], "network+clock", "split out"); eq(sp.right[2], "bluetooth", "as its own entry")
end)
test("notch: the three clusters' extents, and dividers between a piece's groups", function()
    local out = barlayout.layout({ left = { "workspaces" }, center = { "clock", "volume" }, right = { "power" }, mode = "notch" }, ctx())
    assert(out.clusters.left and out.clusters.center and out.clusters.right, "three pieces")
    eq(out.clusters.left.x, 12, "the left piece starts at the inset")
    eq(out.clusters.center.w, barlayout.width("clock", ctx()) + 10 + barlayout.width("volume", ctx()), "the centre spans its two groups")
    local strong = 0
    for _, d in ipairs(out.dividers) do if d.strong then strong = strong + 1 end end
    eq(strong, 1, "one divider between the centre's two groups")
    eq(out.panel, nil, "no full panel")
    local empty = barlayout.layout({ left = {}, center = { "clock" }, right = {}, mode = "notch" }, ctx())
    eq(empty.clusters.left, nil, "an empty cluster has no piece")
end)
test("a layout that places a module twice is refused whole", function()
    local s, problems = config.validate({ bar = { left = { "clock" }, right = { "clock" } } })
    eq(#problems, 1, "reported")
    eq(s.bar.left[1], barlayout.DEFAULT.left[1], "back to the default")
    local _, p2 = config.validate({ bar = { right = { "clock+nonsense" } } })
    eq(string.find(p2[1], "unknown module nonsense") ~= nil, true, "names the unknown module")
end)

print("sysinfo")
local sysinfo = require("lib/sysinfo")
test("cpu: busy fraction between two samples, nothing on the first", function()
    local v, p = sysinfo.cpu("cpu  100 0 100 700 100 0 0 0 0 0\ncpu0 1 2 3")
    eq(v, nil, "first sample")
    local v2 = sysinfo.cpu("cpu  150 0 100 750 100 0 0 0 0 0\n", p)
    eq(v2, 0.5, "half busy")
end)

test("cpu_cores parses numbered cores without aggregate cpu", function()
    local cores = sysinfo.cpu_cores("cpu 10 0 10 80 0 0 0 0\ncpu0 1 0 2 7 0 0 0 0\ncpu1 2 0 3 8 0 0 0 0\n")
    eq(cores.cpu0.total, 10, "core 0 total")
    eq(cores.cpu0.idle, 7, "core 0 idle")
    eq(cores.cpu1.total, 13, "core 1 total")
    eq(cores.cpu, nil, "aggregate excluded")
    eq(next(sysinfo.cpu_cores("bad data")), nil, "invalid input")
end)

test("mem_detail reads what is in use, what is left, and the swap beside it", function()
    local m = sysinfo.mem_detail("MemTotal: 16000000 kB\nMemAvailable: 8000000 kB\nSwapTotal: 2000000 kB\nSwapFree: 1500000 kB\n")
    eq(m and math.floor(m.used_gib * 10 + 0.5), 76, "used GiB")
    eq(m and math.floor(m.available_gib * 10 + 0.5), 76, "available GiB")
    eq(m and math.floor(m.swap_used_gib * 10 + 0.5), 5, "swap used")
    eq(m and math.floor(m.total_gib * 10 + 0.5), 153, "total GiB")
    eq(sysinfo.mem_detail("nothing here"), nil, "a file without the fields is refused")
    eq(sysinfo.mem_detail(nil), nil, "no file is refused")
end)
test("loadavg reads three averages and the running task count", function()
    local l = sysinfo.loadavg("0.42 0.51 0.63 2/812 34567\n")
    eq(l and l.one, 0.42, "one minute"); eq(l and l.five, 0.51, "five"); eq(l and l.fifteen, 0.63, "fifteen")
    eq(l and l.running, 2, "running"); eq(l and l.total, 812, "total")
    eq(sysinfo.loadavg(""), nil, "an empty file has no average")
end)
test("clock_ghz turns a cpufreq kHz file into gigahertz", function()
    eq(sysinfo.clock_ghz("3400000\n"), 3.4, "kHz to GHz")
    eq(sysinfo.clock_ghz("0"), nil, "a stopped clock is no reading")
    eq(sysinfo.clock_ghz(""), nil, "an empty file is no reading")
end)

test("gpu_busy accepts supported DRM percentage and rejects unavailable readings", function()
    eq(sysinfo.gpu_busy("42\n"), 0.42, "42 percent")
    eq(sysinfo.gpu_busy("0"), 0, "idle")
    eq(sysinfo.gpu_busy("100"), 1, "full load")
    eq(sysinfo.gpu_busy("N/A"), nil, "missing")
    eq(sysinfo.gpu_busy("101"), nil, "out of range")
end)

test("display_summary selects focused monitor and formats optional details", function()
    local summary, count = sysinfo.display_summary({
        { name = "DP-1", width = 2560, height = 1440, refreshRate = 144.0, scale = 1.25, focused = false },
        { name = "eDP-1", width = 1920, height = 1080, refreshRate = 60.0, scale = 1.0, focused = true }
    })
    eq(summary, "eDP-1 · 1920x1080 · 60 Hz · 1.00x · +1", "focused display summary")
    eq(count, 2, "display count")
    local first = sysinfo.display_summary({ { name = "HDMI-A-1", width = 1280, height = 720 } })
    eq(first, "HDMI-A-1 · 1280x720", "optional fields omitted")
    eq(sysinfo.display_summary({}), nil, "empty monitor list")
    eq(sysinfo.display_summary(nil), nil, "missing monitor list")
    eq(sysinfo.display_summary({ { name = "bad", width = 0, height = 0 } }), nil, "invalid dimensions")
end)
test("gpu_devices finds display controllers and tolerates missing lspci", function()
    local found = sysinfo.gpu_devices("00:02.0 VGA compatible controller: Intel Corporation UHD Graphics\n03:00.0 3D controller: NVIDIA Corporation Example GPU\n04:00.0 Ethernet controller: Example Network\n")
    eq(#found, 2, "display controller count")
    eq(found[1], "Intel Corporation UHD Graphics", "integrated GPU name")
    eq(found[2], "NVIDIA Corporation Example GPU", "discrete GPU name")
    eq(#sysinfo.gpu_devices(nil), 0, "missing lspci")
end)

test("storage_devices keeps whole disks and supports models with spaces", function()
    local found = sysinfo.storage_devices("nvme0n1 476.9G disk Samsung SSD 980\nsda 931.5G disk External Drive\nsda1 931.5G part External Drive\nloop0 4G loop\n")
    eq(#found, 2, "whole disk count")
    eq(found[1].name, "nvme0n1", "disk name")
    eq(found[1].size, "476.9G", "disk size")
    eq(found[1].model, "Samsung SSD 980", "disk model")
    eq(found[2].model, "External Drive", "model spaces")
    eq(#sysinfo.storage_devices(nil), 0, "missing lsblk")
end)
test("mem: used fraction from MemAvailable", function()
    local f, used, total = sysinfo.mem("MemTotal:       16000000 kB\nMemFree: 1 kB\nMemAvailable:    4000000 kB\n")
    eq(f, 0.75, "fraction"); assert(math.abs(total - 15.26) < 0.01, "total GiB")
end)
test("net: sums interfaces, leaves out loopback", function()
    local t = "Inter-|   Receive\n face |bytes\n    lo: 999 1 0 0 0 0 0 0 999 1 0 0 0 0 0 0\n  wlan0: 1000 5 0 0 0 0 0 0 200 3 0 0 0 0 0 0\n"
    local rx, tx = sysinfo.net(t); eq(rx, 1000, "rx"); eq(tx, 200, "tx")
end)
test("rate: three characters and a unit", function()
    eq(sysinfo.rate(512), "512B", "bytes"); eq(sysinfo.rate(34000), "34K", "kilo")
    eq(sysinfo.rate(1234567), "1.2M", "mega"); eq(sysinfo.rate(45e6), "45M", "tens of mega")
end)
test("temp: the processor's own reading, else the hottest", function()
    eq(sysinfo.temp({ ["k10temp-pci-00c3"] = { Tctl = { temp1_input = 48.5 } },
                      ["nvme-pci-0200"] = { Composite = { temp1_input = 61 } } }), 48.5, "Tctl")
    eq(sysinfo.temp({ ["acpitz-acpi-0"] = { temp1 = { temp1_input = 40 } }, ["x"] = { y = { temp2_input = 55 } } }), 55, "hottest")
    eq(sysinfo.temp(nil), nil, "nothing")
end)
test("weather: WMO codes to a glyph kind and a word", function()
    eq(sysinfo.weather(0, 1), "clear", "day"); eq(sysinfo.weather(0, 0), "night", "night")
    eq(select(2, sysinfo.weather(63, 1)), "RAIN", "rain"); eq(sysinfo.weather(95, 1), "storm", "storm")
end)

print("setters")
local setters = require("lib/setters")
function setters_code(path) for i, p in ipairs(setters.SETTERS) do if p == path then return i end end end
test("a control's number sets its setting, and nonsense sets nothing", function()
    local s = config.defaults()
    eq(setters.apply(s, 1001), "bar.mode", "path"); eq(s.bar.mode, "full", "enum by place")
    eq(setters.apply(s, 5000), "bar.rail", "switch"); eq(s.bar.rail, false, "off")
    eq(setters.apply(s, 16004), "frame.band", "number"); eq(s.frame.band, 6, "min 2 + 4")
    eq(setters.apply(s, 25000), "theme.contrast", "signed number"); eq(s.theme.contrast, -1, "min -1 + 0")
    eq(setters.apply(s, 110000), "bar.modules.volume.show", "module show"); eq(s.bar.modules.volume.show, false, "hidden")
    eq(setters.apply(s, 210002), "bar.modules.volume.frame", "module frame"); eq(s.bar.modules.volume.frame, "corners", "corners")
    eq(setters.apply(s, 2009), nil, "no such value"); eq(setters.apply(s, 180000), nil, "no such setting"); eq(setters.apply(s, 150000), nil, "a module code no module has")
    local long = {}; for i = 1, 101 do long[i] = "s" .. i end
    eq(setters.path(99, long), "s99", "the 99th setting is code 99")
    eq(setters.path(300, long), "s100", "the 100th is code 300, above the modules'")
    eq(setters.path(110, long), "bar.modules.volume.show", "the modules' codes are theirs")
end)
test("the wallpaper studio's defaults are settings, at codes that moved nothing", function()
    local d = config.defaults()
    eq(d.wallpaper.matte, 0, "no matte"); eq(d.wallpaper.backdrop, "black", "black")
    eq(d.wallpaper.key, false, "no key"); eq(d.wallpaper.fuzz, 18, "a fuzz")
    local s = config.defaults()
    local function code(path)
        local i = setters_code(path)
        return i >= 100 and i + 200 or i
    end
    eq(setters.apply(s, code("wallpaper.matte") * 1000 + 12), "wallpaper.matte", "the matte's code")
    eq(s.wallpaper.matte, 12, "a matte of 12 %")
    eq(setters.apply(s, code("wallpaper.backdrop") * 1000 + 2), "wallpaper.backdrop", "the backdrop's code")
    eq(s.wallpaper.backdrop, "corners", "the third backdrop")
    eq(setters.apply(s, code("wallpaper.key") * 1000 + 1), "wallpaper.key", "the key's code")
    eq(s.wallpaper.key, true, "on")
    eq(setters.apply(s, code("wallpaper.fuzz") * 1000 + 30), "wallpaper.fuzz", "the fuzz's code")
    eq(s.wallpaper.fuzz, 30, "30 %")
    setters.apply(s, code("wallpaper.fuzz") * 1000 + 99); eq(s.wallpaper.fuzz, 45, "past its range is clamped")
end)
test("the ported overview's hands are settings, at codes that moved nothing", function()
    local s = config.defaults()
    eq(s.atlas.wheel_desktops, true, "the wheel steps desktops by default")
    eq(s.atlas.search_apps, true, "and typing lists apps by default")
    local function code(path)
        local i = setters_code(path)
        return i >= 100 and i + 200 or i
    end
    eq(setters.apply(s, code("atlas.wheel_desktops") * 1000 + 0), "atlas.wheel_desktops", "the wheel's code")
    eq(s.atlas.wheel_desktops, false, "off")
    eq(setters.apply(s, code("atlas.search_apps") * 1000 + 1), "atlas.search_apps", "the app search's code")
    eq(s.atlas.search_apps, true, "on")
    eq(s.atlas.search_files, true, "files are searched by default")
    eq(setters.apply(s, code("atlas.search_files") * 1000 + 0), "atlas.search_files", "the file search's code")
    eq(s.atlas.search_files, false, "off")
    eq(s.atlas.hot_corner, "off", "no hot corner by default")
    eq(setters.apply(s, code("atlas.hot_corner") * 1000 + 2), "atlas.hot_corner", "the hot corner's code")
    eq(s.atlas.hot_corner, "top-right", "the second corner")
    eq(setters.apply(s, code("atlas.hot_corner_delay") * 1000 + 400), "atlas.hot_corner_delay", "the rest's code")
    eq(s.atlas.hot_corner_delay, 600, "200 ms + 400")
end)
test("settings from an older mooi: the outline's old names, the border switch", function()
    local s, problems = config.validate({ bar = { frame = "bracket", border = false, mode = "full",
        modules = { clock = { frame = "plate" }, volume = { frame = "bezel" } } } })
    eq(#problems, 0, "no problems"); eq(s.bar.frame, "corners", "bracket → corners")
    eq(s.bar.modules.clock.frame, "none", "plate → none"); eq(s.bar.modules.volume.frame, "line", "bezel → line")
    local s2 = config.validate({ bar = { frame = "bezel", border = false, mode = "full" } })
    eq(s2.bar.frame, "none", "a full panel with no border had no outline")
    local _, p3 = config.validate({ keys = { search = "SUPER + ALT + Space", window = "rm -rf; x" } })
    eq(#p3, 1, "a key that is not a key combination is refused")
end)

print("desktop")
local desktop = require("lib/desktop")
local pal = { phos = "#7fcfb6", ember = "#e07b2e", trace = "#3d6a60" }
test("the desktop's look: nothing unless managed, the palette on the border", function()
    local d = config.defaults().desktop
    eq(desktop.look(d, pal), nil, "not managed")
    d.manage = true
    local l = desktop.look(d, pal)
    assert(string.find(l, "border_size = 2", 1, true), "border")
    assert(string.find(l, '{ colors = { "rgba(7fcfb6ff)", "rgba(e07b2eff)" }, angle = 45 }', 1, true), "gradient")
    d.border_colour = "keep"
    assert(not string.find(desktop.look(d, pal), "col =", 1, true), "keep leaves the colours")
end)
test("the keys file is Lua that names every action", function()
    local f = desktop.file(config.defaults().keys, config.defaults().desktop, pal, "/x/bin/mooi")
    assert(string.find(f, '{ "SUPER + ALT + Space", "toggle" },', 1, true), "search")
    local n = 0; for _ in string.gmatch(f, "{ \"") do n = n + 1 end
    eq(n, #desktop.ACTIONS, "one line per action")
end)
test("the wallpaper studio has a module, a key and a command", function()
    eq(barlayout.known("wallpaper"), true, "a module")
    assert(barlayout.INDEX.wallpaper ~= nil, "in the catalogue's order")
    local on_bar = false
    for _, e in ipairs(barlayout.DEFAULT.right) do if e == "wallpaper" then on_bar = true end end
    eq(on_bar, true, "on the bar by default")
    local f = desktop.file(config.defaults().keys, config.defaults().desktop, pal, "/x/bin/mooi")
    assert(string.find(f, '{ "SUPER + ALT + P", "wallpaper" },', 1, true), "the key runs the command")
    local action = nil
    for _, a in ipairs(desktop.ACTIONS) do if a.key == "wallpaper" then action = a end end
    eq(action and action.cmd, "wallpaper", "an action, and its bin/mooi command")
    eq(config.defaults().keys.wallpaper, "SUPER + ALT + P", "the setting exists")
end)

test("windows and scrolling: nothing written while kept, Hyprland's names when chosen", function()
    local d = config.defaults().desktop
    d.manage = true
    local look = desktop.look(d, nil)
    assert(not string.find(look, "layout") and not string.find(look, "input") and not string.find(look, "scrolling"), "keep writes nothing: " .. look)
    eq(#desktop.claims(d), 0, "keep claims nothing")
    d.layout, d.column, d.column_fit, d.touchpad_natural, d.touchpad_speed, d.blur = "scrolling", 50, "center", "off", 30, "light"
    d.opacity_active, d.opacity_inactive, d.shadow, d.shadow_size = 95, 80, "neon", 20
    look = desktop.look(d, { phos = "#7fcfb6", ember = "#e07b2e", trace = "#3d6a60" })
    assert(string.find(look, 'layout = "scrolling"', 1, true), look)
    assert(string.find(look, "scrolling = { column_width = 0.50, focus_fit_method = 0 }", 1, true), look)
    assert(string.find(look, "active_opacity = 0.95, inactive_opacity = 0.80", 1, true), look)
    assert(string.find(look, 'shadow = { enabled = true, range = 20, render_power = 2, color = "rgba(7fcfb6aa)"', 1, true), look)
    assert(string.find(look, "input = { touchpad = { natural_scroll = false, scroll_factor = 0.30 } }", 1, true), look)
    assert(string.find(look, "blur = { enabled = true, size = 3, passes = 2 }", 1, true), look)
    local was = desktop.claims(d)
    d.layout = "keep"
    eq(desktop.covers(desktop.claims(d), was), false, "handing the layout back is noticed (Hyprland reloads)")
    eq(desktop.covers(was, desktop.claims(d)), true, "claiming more is not")
end)

test("D157: the workspaces' transition, the swipe and niri's columns; nothing while kept", function()
    local d = config.defaults().desktop
    d.manage = true
    local look = desktop.look(d, nil)
    assert(not string.find(look, "hl.animation", 1, true) and not string.find(look, "gestures") and not string.find(look, "hl.bind", 1, true), "keep writes nothing: " .. look)
    eq(desktop.workspaces(d), nil, "no transition while kept")
    -- tide: the incoming leaf rises faded, the outgoing dissolves; niri's spring under both
    d.ws_style, d.ws_feel = "tide", "spring"
    local ws = desktop.workspaces(d)
    assert(string.find(ws, 'hl.curve("mooi_ws", { type = "spring", mass = 1, stiffness = 1000, dampening = 63.2 })', 1, true), ws)
    assert(string.find(ws, 'leaf = "workspacesIn", enabled = true, speed = 2, spring = "mooi_ws", style = "slidefadevert 30%"', 1, true), ws)
    assert(string.find(ws, 'leaf = "workspacesOut", enabled = true, speed = 2, spring = "mooi_ws", style = "fade"', 1, true), ws)
    -- a kept feel moves by mooi's ease, not Hyprland's near-instant `default`; the duration in tenths
    d.ws_style, d.ws_feel, d.ws_speed = "column", "keep", 5
    ws = desktop.workspaces(d)
    assert(string.find(ws, 'type = "bezier"', 1, true) and string.find(ws, 'speed = 5, bezier = "mooi_ws", style = "slidevert"', 1, true), ws)
    d.ws_swipe, d.column_widths, d.column_follow, d.column_wrap, d.column_keys = "flick", "halves", "off", "on", true
    look = desktop.look(d, nil)
    assert(string.find(look, "gestures = { workspace_swipe_forever = true", 1, true), look)
    assert(string.find(look, 'scrolling = { explicit_column_widths = "0.5, 1.0", follow_focus = 0, wrap_focus = true }', 1, true), look)
    -- each key let go before it is bound, so applying the look twice binds it once
    local n = select(2, string.gsub(look, "hl%.bind%(", ""))
    eq(n, #desktop.COLUMN_KEYS, "one bind per column key")
    assert(string.find(look, 'pcall(hl.unbind, "SUPER + bracketright"); hl.bind("SUPER + bracketright", hl.dsp.layout("colresize +conf"))', 1, true), look)
    local was = desktop.claims(d)
    d.column_keys, d.ws_style = false, "keep"
    eq(desktop.covers(desktop.claims(d), was), false, "letting the keys and the transition go is noticed (Hyprland reloads)")
    -- the setter lists carry the new settings at their end, in step
    for _, p in ipairs({ "desktop.ws_style", "desktop.column_keys" }) do assert(setters_code(p), p .. " has a setter") end
end)

test("Hyprland 0.56: finer blur, the windows' spring and motion blur, nothing while kept", function()
    local d = config.defaults().desktop
    d.manage = true
    local look = desktop.look(d, nil)
    assert(not string.find(look, "blur") and not string.find(look, "hl.curve", 1, true), "keep writes nothing: " .. look)
    d.blur, d.blur_vibrancy, d.blur_xray, d.blur_popups = "medium", 30, "on", "off"
    d.wobble, d.motion_blur = "jelly", "soft"
    look = desktop.look(d, nil)
    assert(string.find(look, "blur = { enabled = true, size = 6, passes = 3, vibrancy = 0.30, xray = true, popups = false }", 1, true), look)
    assert(string.find(look, "motion_blur = { enabled = true, samples = 6 }", 1, true), look)
    assert(string.find(look, 'hl.curve("mooi_wobble", { type = "spring", mass = 1, stiffness = 220, dampening = 7.0 })', 1, true), look)
    assert(string.find(look, 'leaf = "windowsIn", enabled = true, speed = 5, spring = "mooi_wobble", style = "popin 87%"', 1, true), "the pop-in kept: " .. look)
    assert(string.find(look, 'leaf = "windowsMove"', 1, true), look)
    assert(load(look), "one chunk of Lua, as custom/mooi.lua loads it")
    d.blur, d.motion_blur = "keep", "off"
    look = desktop.look(d, nil)
    assert(string.find(look, "blur = { vibrancy = 0.30, xray = true, popups = false }", 1, true), "the details without the preset: " .. look)
    assert(string.find(look, "motion_blur = { enabled = false }", 1, true), look)
    local was = desktop.claims(d)
    d.wobble = "keep"
    eq(desktop.covers(desktop.claims(d), was), false, "handing the spring back is noticed (Hyprland reloads)")
    -- Hyprland 0.57: the real wobble and the blur variants, each on its own under pcall
    d.wobble, d.blur_variant = "jelly", "glass"
    look = desktop.look(d, nil)
    assert(string.find(look, "pcall(hl.config, { decoration = { wobble = { enabled = true, intensity = 1.70", 1, true), look)
    assert(string.find(look, 'pcall(hl.config, { decoration = { blur = { variant = "acrylic" } } })', 1, true),
        "glass (0.57 keeps it for aurora/drops/heat_shimmer/prism) asks for acrylic: " .. look)
    assert(load(look), "still one chunk of Lua")
    -- 0.57 accepts only its own names: `none` is refused, its plain blur is kawase
    d.blur_variant = "none"
    assert(string.find(desktop.look(d, nil), 'blur = { variant = "kawase" }', 1, true), "Plain asks for kawase")
    d.wobble = "off"
    assert(string.find(desktop.look(d, nil), "wobble = { enabled = false }", 1, true), "off: no bending either")
end)

test("the desktop's named choices of an earlier mooi become numbers", function()
    local s, p = config.validate({ desktop = { column = "half", touchpad_speed = "slow", mouse_speed = "keep" } })
    eq(#p, 0, "no problems"); eq(s.desktop.column, 50, "half → 50 %"); eq(s.desktop.touchpad_speed, 30, "slow → 30 %"); eq(s.desktop.mouse_speed, 4, "keep → its keep")
end)

test("the screen frame keeps the windows' outer gap wide enough to be seen", function()
    local d = config.defaults().desktop
    d.manage, d.gaps_out = true, 2
    assert(string.find(desktop.look(d, nil, { on = true, band = 8 }), "gaps_out = 12", 1, true), "band 8 + 4")
    assert(string.find(desktop.look(d, nil, { on = false, band = 8 }), "gaps_out = 2", 1, true), "off: the user's own")
    d.gaps_out = 30
    assert(string.find(desktop.look(d, nil, { on = true, band = 8 }), "gaps_out = 30", 1, true), "a wider gap stays")
end)

print("style")
test("presets: one choice writes a coherent set, and Custom once a detail differs", function()
    local s = config.defaults()
    eq(setters.apply(s, setters_code("bar.style") * 1000 + 1) ~= nil, true, "glass chosen")
    eq(s.bar.surface, "glass", "glass material"); eq(s.bar.ground, "clear", "nothing behind it"); eq(s.bar.shadow, "soft", "a soft shadow")
    local st = require("lib/style")
    eq(st.preset_index(s, st.BAR_PRESETS), 1, "it reads as Glass")
    s.bar.shadow = "strong"
    eq(st.preset_index(s, st.BAR_PRESETS), #st.BAR_PRESETS, "a detail changed: Custom")
    setters.apply(s, setters_code("theme.preset") * 1000 + 4)
    eq(s.bar.bg, "alien", "alien base"); eq(s.theme.finish, "neon", "neon finish")
    eq(st.preset_index(s, st.THEME_PRESETS), 4, "it reads as Alien")
    eq(st.preset_index(config.defaults(), st.BAR_PRESETS), 0, "the defaults are Instrument")
    eq(st.preset_index(config.defaults(), st.THEME_PRESETS), 0, "and Phosphor")
end)
test("one choice for two settings: the outline, and the frame's music", function()
    local st = require("lib/style")
    local s = config.defaults()
    setters.apply(s, setters_code("bar.edge") * 1000 + 4)
    eq(s.bar.frame, "line", "bold is a line"); eq(s.bar.outline_width, 3, "of weight 3"); eq(st.edge_index(s), 4, "and reads as Bold")
    setters.apply(s, setters_code("bar.edge") * 1000 + 1)
    eq(s.bar.frame, "corners", "corners"); eq(st.edge_index(s), 1, "reads as Corners")
    setters.apply(s, setters_code("frame.motion") * 1000)
    eq(s.frame.music, false, "off: the music is off"); eq(st.motion_index(s), 0, "reads as Off")
    setters.apply(s, setters_code("frame.motion") * 1000 + 2)
    eq(s.frame.music, true, "ripples: on"); eq(s.frame.style, "crests", "as crests"); eq(st.motion_index(s), 2, "reads as Ripples")
end)
test("a narrower bar is centred: its modules inside the inset", function()
    local c = ctx(); c.inset = 12 + math.floor(c.screen * 0.25 / 2 + 0.5)
    local out = barlayout.layout({ left = { "workspaces" }, center = {}, right = { "clock" }, mode = "full" }, c)
    eq(out.x.workspaces, c.inset, "the left starts at the inset")
    eq(out.x.clock + barlayout.width("clock", c), c.screen - c.inset, "the right ends at it")
    eq(out.panel.x, c.inset - 6, "the panel follows")
end)
test("pills: a run of occupied workspaces is joined", function()
    local rows = spaces.rows({ { id = 1, windows = 2 }, { id = 2, windows = 1 }, { id = 4, windows = 1 } }, 1, 5)
    eq(rows[1].joined, true, "1 joins 2"); eq(rows[2].joined, false, "2 does not join an empty 3"); eq(rows[4].joined, false, "4 is alone")
end)
test("the strip the windows leave the bar follows its thickness, its edge distance and the rail", function()
    local s = config.defaults()
    eq(require("lib/style").facts(s).st_res, 46, "the default strip is the 46 px it always was")
    s.bar.height, s.bar.offset = 40, 12
    eq(require("lib/style").facts(s).st_res, 12 + 15 + 40 + 1, "thicker and lower")
    s.bar.rail = false
    eq(require("lib/style").facts(s).st_res, 12 + 8 + 40 + 1, "no rail gives its band back")
    s.bar.mode = "notch"
    eq(require("lib/style").facts(s).st_res, 12 + 6 + 40 + 1, "a notch hangs 6 px down")
    eq(require("lib/style").facts(s).st_res < 128, true, "within the seven reserve surfaces' reach")
end)
test("the map reaches the focus and every occupied workspace past the setting", function()
    -- 4 positions set, on workspace 7 with windows on 5: the switcher must hold 7 (it parked on
    -- the first slot and never moved — 2026-10-20)
    local rows = spaces.rows({ { id = 5, windows = 1 }, { id = 7, windows = 1 } }, 7, 4)
    eq(#rows, 7, "grows to the active one"); eq(rows[7].active, true, "7 is active"); eq(rows[5].windows, 1, "5 is there")
    rows = spaces.rows({ { id = 9, windows = 2 } }, 1, 4)
    eq(#rows, 9, "grows to the last occupied one")
    rows = spaces.rows({ { id = 2, windows = 0 } }, 2, 4)
    eq(#rows, 4, "never shorter than the setting")
    eq(#spaces.rows({ { id = 30, windows = 1 } }, 30, 4), 4, "past the model's 16 it does not grow")
end)

local style = require("lib/style")
test("the look's facts: defaults are the bar as it was", function()
    local f = style.facts(config.defaults())
    eq(f.st_notch, false, "no notch"); eq(f.st_radius, 8, "radius"); eq(f.st_owidth, 1.4, "regular outline")
    eq(f.st_sh_a, 0, "no shadow"); eq(f.st_opacity, 1, "opaque"); eq(f.st_aberr, 0, "no aberration"); eq(f.st_glow, 1, "full glow")
    local s = config.defaults()
    s.bar.mode, s.bar.shadow, s.theme.finish, s.bar.wheel = "notch", "strong", "matte", "invert"
    f = style.facts(s)
    eq(f.st_notch, true, "notch"); eq(f.st_sh_a, 0.62, "strong shadow"); eq(f.st_glow, 0.25, "matte glows little"); eq(f.st_wheel, 2, "inverted wheel")
end)
test("colour: harmonies, saturation, matte, and a background the text is held against", function()
    local dark = { colours = { primary = "#dfc56d", surface_container_low = "#1e1b13", surface_dim = "#16130b" } }
    local h, name = ferro.signal_hue({}, 40, "triadic"); eq(name, "triadic", "triadic asked"); eq(h, 160, "a third of the wheel")
    h, name = ferro.signal_hue({}, 40, "analogous"); eq(h, 80, "a neighbour")
    local base = ferro.resolve("wallpaper", dark, "auto", false, {})
    local _, s0 = ferro.to_hsl(base.phos)
    local matte = ferro.resolve("wallpaper", dark, "auto", false, { finish = "matte" })
    local _, s1 = ferro.to_hsl(matte.phos)
    assert(s1 < s0 * 0.7, "matte is less saturated")
    local sand = ferro.resolve("wallpaper", dark, "auto", false, { bg = { kind = "sand" } })
    assert(ferro.contrast(sand.phos, sand.ground) >= 6.9, "text holds 7:1 on a light background")
    assert(ferro.luminance(sand.phos) < ferro.luminance(sand.ground), "and is darker than it")
    local custom = ferro.resolve("fixed", nil, "auto", false, { bg = { kind = "custom", colour = "#203040", light = 10, sat = 100, hue = 0 } })
    assert(ferro.luminance(custom.ground) > ferro.luminance(ferro.hex("#203040")), "lighter by its adjustment")
    local black = ferro.resolve("fixed", nil, "auto", false, { bg = { kind = "black" } })
    eq(ferro.to_hex(black.ground), "#000000", "black leaves the palette as it is")
end)

-- ── Arranging the bar: spacers, and moves by place (lib/arrange) ──
local arrange = require("lib/arrange")
local function lay_ctx() return { screen = 1920, inset = 12, gap = 10, ws_style = "pills", ws_count = 5, visualizer = "off", tray = 0 } end
test("a spacer stretches: what follows it goes to the middle, and spacers at an end are dropped", function()
    local cfg = { left = { "workspaces", "gap", "clock" }, center = {}, right = { "power" }, mode = "islands" }
    local out = barlayout.layout(cfg, lay_ctx())
    eq(out.x.workspaces, 12, "the first module keeps the edge")
    eq(out.x.clock + barlayout.width("clock", lay_ctx()), 1920 - 12 - barlayout.width("power", lay_ctx()) - 10, "the clock is pushed up against the right side")
    eq(#out.frames, 3, "a spacer has no frame")
    local edge = barlayout.layout({ left = { "gap", "clock", "gap" }, center = {}, right = {}, mode = "islands" }, lay_ctx())
    eq(edge.x.clock, 12, "a spacer at an end pushes nothing")
    local ok = barlayout.check_list({ "gap", "clock", "gap" }, {})
    eq(ok, true, "spacers can repeat")
    eq((barlayout.check_list({ "clock+gap" }, {})), false, "a spacer is never joined")
end)
test("with a centre, a side's spacer stops at the centre", function()
    local ctx = lay_ctx()
    local out = barlayout.layout({ left = { "workspaces", "gap", "window" }, center = { "clock" }, right = {}, mode = "islands" }, ctx)
    eq(out.x.window + barlayout.width("window", ctx), out.x.clock - 10, "the window ends a gap before the clock")
end)
test("arrange: walk, join, split, cross, remove and add by place", function()
    local b = { left = { "workspaces", "gap", "window" }, center = { "clock" }, right = { "volume+mic" } }
    local L, side, i, j = arrange.move(b, "left", 3, 1, 1)
    eq(side, "center", "past the end it crosses into the next list"); eq(L.center[1], "window", "first in the centre"); eq(#L.left, 2, "left keeps the spacer")
    L, side, i, j = arrange.move(b, "right", 1, 1, 1)
    eq(L.right[1], "mic+volume", "inside a group it trades places"); eq(j, 2, "and is second now")
    L, side, i = arrange.join(b, "center", 1, 1, 1)
    eq(L.center[1], "clock", "nothing after it in its list: nothing to join")
    L = arrange.join({ left = { "a", "workspaces", "window" } }, "left", 3, 1, -1)
    eq(L.left[2], "workspaces+window", "joins the entry before")
    L = arrange.join(b, "left", 3, 1, -1)
    eq(L.left[3], "window", "a spacer is never joined")
    L, side, i = arrange.split(b, "right", 1, 2)
    eq(L.right[1], "volume", "split: the group keeps the rest"); eq(L.right[2], "mic", "and it follows"); eq(i, 2, "where it is now")
    L = arrange.remove(b, "left", 2, 1)
    eq(#L.left, 2, "a spacer removed"); eq(L.left[2], "window", "the rest close up")
    L = arrange.add(b, "clock", "left")
    eq(#L.center, 0, "a module already placed moves"); eq(L.left[4], "clock", "to the end of its new list")
    L = arrange.add(b, "gap", "right")
    eq(L.right[2], "gap", "spacers add, never move")
    L = arrange.to_side(b, "right", 1, 2, "left")
    eq(L.left[4], "mic", "to another list, on its own"); eq(L.right[1], "volume", "its group keeps the rest")
    eq(arrange.placed(b, "window"), true, "placed"); eq(arrange.placed(b, "battery"), false, "on the shelf")
    -- the bar's own edit mode (a drag) keeps the spacers it is not moving
    local w = barlayout.without(b, "window")
    eq(w.left[2], "gap", "a drag on the bar leaves the spacers be"); eq(#w.left, 2, "and takes the module out")
end)

test("edit: dropped into empty space it stays where it was let go, and what lay beyond stays put", function()
    local c = lay_ctx()
    c.battery = true
    local cfg = { left = { "workspaces" }, center = { "clock" }, right = { "power" }, mode = "islands" }
    local lists = barlayout.drop(cfg, c, "battery", 600)
    eq(barlayout.gap_width(lists.left[2]) ~= nil, true, "a fixed gap goes in front of it")
    local out = barlayout.layout({ left = lists.left, center = lists.center, right = lists.right, mode = "islands" }, c)
    eq(math.abs(out.x.battery + barlayout.width("battery", c) / 2 - 600) <= 1, true, "its middle is where it was dropped")
    lists = barlayout.drop(cfg, c, "volume", 1500)
    out = barlayout.layout({ left = lists.left, center = lists.center, right = lists.right, mode = "islands" }, c)
    eq(math.abs(out.x.volume + barlayout.width("volume", c) / 2 - 1500) <= 1, true, "on the right too")
    eq(out.x.power, barlayout.layout(cfg, c).x.power, "the right end did not move")
    -- dropped again before the first, inside the gap: the gap shrinks and the battery stays put
    local l3 = barlayout.drop({ left = { "workspaces", barlayout.fixed_gap(400), "battery" }, center = { "clock" }, right = { "power" }, mode = "islands" }, c, "mic", 300)
    local o3 = barlayout.layout({ left = l3.left, center = l3.center, right = l3.right, mode = "islands" }, c)
    local o0 = barlayout.layout({ left = { "workspaces", barlayout.fixed_gap(400), "battery" }, center = { "clock" }, right = { "power" }, mode = "islands" }, c)
    eq(o3.x.battery, o0.x.battery, "what followed stays where it was")
    eq(math.abs(o3.x.mic + barlayout.width("mic", c) / 2 - 300) <= 1, true, "and the new one is where it was dropped")
end)
test("fixed gaps: kept where they measure something, dropped where they do not", function()
    local c = lay_ctx()
    local out = barlayout.layout({ left = { "gap:200", "clock" }, center = {}, right = { "power", "gap:50" }, mode = "islands" }, c)
    eq(out.x.clock, 12 + 200 + 10, "at the left list's start: the distance from the bar's end")
    eq(out.x.power + barlayout.width("power", c), 1920 - 12 - 50 - 10, "at the right list's end: the distance from the right end")
    local out2 = barlayout.layout({ left = { "clock", "gap:200" }, center = {}, right = { "gap:50", "power" }, mode = "islands" }, c)
    eq(out2.x.clock, 12, "a trailing left gap measures nothing")
    eq(out2.x.power + barlayout.width("power", c), 1920 - 12, "a leading right gap measures nothing")
    eq(#out.spacers, 2, "edit mode is told where the gaps are")
end)

-- ── Your apps in mooi's palette (lib/appcolors, theme/apps) ──
local appcolors = require("lib/appcolors")
test("apps: every tag mooi's templates use has a colour, and the terminal's hues are told apart", function()
    local roles = ferro.resolve("mooi", nil, "auto", false, {})
    local m = appcolors.material(roles)
    for _, name in ipairs({ "kitty.conf", "gtk3.css", "gtk4.css", "qt5ct.conf" }) do
        local f = assert(io.open("theme/apps/" .. name)); local s = f:read("a"); f:close()
        for role in string.gmatch(s, "{{colors%.([%w_]+)%.default%.hex") do
            eq(m[role] ~= nil, true, name .. " needs " .. role)
        end
    end
    eq(m.ansi_red ~= m.ansi_green and m.ansi_green ~= m.ansi_blue, true, "red, green and blue differ")
    eq(string.match(m.surface, "^#%x%x%x%x%x%x$") ~= nil, true, "colours are #rrggbb")
    local f = assert(io.open("theme/apps/kde.colors")); local s = f:read("a"); f:close()
    for role in string.gmatch(s, "{{colors%.([%w_]+)%.default%.hex") do eq(m[role] ~= nil, true, "kde.colors needs " .. role) end
end)

-- ── Day and night (D91) ──
-- A real Matugen light palette (scheme-tonal-spot, the user's violet wallpaper).
local violet_day = { mode = "light", colours = { primary = "#615690", secondary = "#615b71", tertiary = "#7d5263",
    surface_container = "#f1ecf4", surface_container_low = "#f7f2fa", surface_container_lowest = "#ffffff" } }
test("day: the palette is paper, and keeps its floors on it", function()
    for _, finish in ipairs({ "luminous", "matte", "neon" }) do
        for _, bg in ipairs({ "black", "obsidian", "accent", "wallpaper" }) do
            local out, why = ferro.resolve("wallpaper", violet_day, "auto", false, { finish = finish, saturation = 20, bg = { kind = bg, light = 0, sat = 100, hue = 0 } })
            local what = finish .. "/" .. bg
            eq(string.find(why, "day", 1, true) ~= nil, true, what .. ": the mode is read from the palette")
            assert(ferro.luminance(out.ground) > 0.6, what .. ": a light ground")
            assert(ferro.contrast(out.phos, out.ground) >= 6, what .. ": phos 6:1 on paper")
            assert(ferro.contrast(out.ember, out.ground) >= 4.5, what .. ": ember 4.5:1")
            assert(ferro.contrast(out.muted, out.ground) >= 4.5, what .. ": muted 4.5:1")
            assert(ferro.contrast(out.phos_fill, out.ink) >= 4.5, what .. ": ink on phos-fill 4.5:1")
            assert(ferro.contrast(out.engrave, out.steel_700) >= 4.5, what .. ": engrave on steel 4.5:1")
            local _, _, problems = require("lib/theme").resolve({}, out)
            eq(#problems, 0, what .. ": the islands' tokens pass")
        end
    end
    local fixed = ferro.resolve("fixed", { mode = "light" }, "auto", false)
    assert(ferro.luminance(fixed.ground) > 0.6, "the fixed palette turns light too")
    local dark = ferro.resolve("wallpaper", teal, "auto", false)
    eq(dark.ground.r, 0, "a palette with no mode stays dark")
end)
test("day: the terminal's hues are inks that read on its paper", function()
    local roles = ferro.resolve("wallpaper", violet_day, "auto", false, {})
    local m = appcolors.material(roles, "light")
    local bg = ferro.hex(m.surface_container_lowest)
    for name in pairs(appcolors.ANSI) do
        assert(ferro.contrast(ferro.hex(m["ansi_" .. name]), bg) >= 4.5, name .. " 4.5:1 on the background")
        assert(ferro.contrast(ferro.hex(m["ansi_bright_" .. name]), bg) >= 4.5, "bright " .. name .. " too")
    end
    eq(config.defaults().theme.mode, "dark", "dark until asked")
    eq(config.defaults().keys.mode, "SUPER + ALT + T", "the switch's key")
end)

-- ── The Mechanical Shutter: placement and the action registry (lib/shutter) ──
local shutter = require("lib/shutter")
local AREA = { x = 0, y = 46, w = 1920, h = 1034 }
local function inside(r, a, what) eq(r.x >= a.x and r.y >= a.y and r.x + (r.w or 0) <= a.x + a.w and r.y + (r.h or 0) <= a.y + a.h, true, what) end
test("shutter: it unfolds outside a window when it fits, inside one that fills the screen", function()
    local p = shutter.place({ x = 600, y = 200, w = 700, h = 500 }, AREA, {})
    eq(p.side, "right", "room on the right"); eq(p.dir, 1, "the panel opens outward"); eq(#p.plates, 4, "four plates")
    eq(p.plates[1].x > 1300, true, "beside the window's right edge")
    for i, pl in ipairs(p.plates) do inside({ x = pl.x, y = pl.y, w = p.pw, h = p.ph }, AREA, "plate " .. i .. " on screen") end
    local full = shutter.place({ x = 10, y = 56, w = 1900, h = 1014 }, AREA, {})
    eq(full.side, "inside", "a tiled window filling the area: inside its edge")
    eq(full.plates[1].x + full.pw <= 1910, true, "within the window")
    local pan = shutter.panel(full, 2, 5, AREA)
    inside(pan, AREA, "its panel stays on screen"); eq(pan.x < full.plates[2].x, true, "and opens inward")
    local edge = shutter.place({ x = 1500, y = 200, w = 400, h = 300 }, AREA, {})
    eq(edge.side, "left", "no room on the right: the left")
    eq(shutter.place({ x = 600, y = 200, w = 700, h = 500 }, AREA, { edge = "left" }).side, "left", "a preferred edge that fits is taken")
    local low = shutter.place({ x = 600, y = 900, w = 500, h = 170 }, AREA, {})
    inside({ x = low.plates[4].x, y = low.plates[4].y, w = low.pw, h = low.ph }, AREA, "near the foot the column slides up")
    inside(shutter.panel(low, 4, 6, AREA), AREA, "and so does the panel")
    local compact = shutter.place({ x = 600, y = 200, w = 700, h = 500 }, AREA, { density = "compact" })
    eq(compact.pw < p.pw, true, "compact plates are smaller")
end)
test("shutter: only what the window can do now is offered", function()
    local tiled = { floating = false, pinned = false, fullscreen_mode = 0, workspace = 1, class = "kitty", title = "t" }
    local ids = function(rows) local s = {} for _, r in ipairs(rows) do s[r.id] = true end return s end
    local a = ids(shutter.actions("arrange", tiled))
    eq(a.swap, true, "a tiled window swaps"); eq(a.size, nil, "but has no size of its own"); eq(a.center, nil, "nor a centre")
    local floating = { floating = true, pinned = true, fullscreen_mode = 0, workspace = 3, class = "kitty", title = "t" }
    a = ids(shutter.actions("arrange", floating)); eq(a.size, true, "a floating one is sized"); eq(a.swap, nil, "and does not swap")
    local b = shutter.actions("behaviour", floating)
    local pin = nil; for _, r in ipairs(b) do if r.id == "pin" then pin = r end end
    eq(pin ~= nil and pin.on, true, "pinning only for a floating window, showing it is on")
    eq(ids(shutter.actions("behaviour", tiled)).pin, nil, "never for a tiled one")
    local w = ids(shutter.actions("workspace", tiled, { active_ws = 1 }))
    eq(w.prev, nil, "no workspace before 1"); eq(w.next, true, "a next one"); eq(w.bring, nil, "already here")
    eq(ids(shutter.actions("workspace", floating, { active_ws = 1 })).bring, true, "elsewhere: bring it here")
    local c = shutter.actions("connections", tiled, {})
    eq(#c, 1, "no folder known: just the title"); eq(c[1].id, "copy_title", "")
    c = ids(shutter.actions("connections", tiled, { cwd = "/home/x/p/sub", repo = "/home/x/p", terminal = true, siblings = 2 }))
    eq(c.open_dir and c.term_here and c.copy_path and c.open_repo and c.siblings, true, "a folder, its repository, its siblings")
    local close = nil; for _, r in ipairs(shutter.actions("behaviour", tiled)) do if r.id == "close" then close = r end end
    eq(close.kind, "danger", "closing asks twice")
    eq(shutter.track({ x = 1, y = 1, w = 2, h = 2 }, nil), "gone", "a closed window dismisses")
    eq(shutter.track({ x = 1, y = 1, w = 2, h = 2 }, { x = 5, y = 1, w = 2, h = 2 }), "moved", "a moved one is followed")
end)
test("hypr: the shutter's commands, and only valid ones", function()
    local hypr = require("lib/hypr")
    local a = "0x1a2b"
    eq(string.find(hypr.dispatch("maximize", a), 'mode = "maximized"', 1, true) ~= nil, true, "maximize")
    eq(hypr.dispatch("size", a, { w = 50, h = 600 }), nil, "a size too small is refused")
    eq(hypr.dispatch("swap", a, { direction = "x" }), nil, "an unknown direction is refused")
    eq(string.find(hypr.dispatch("opacity", a, { alpha = 0.8 }), '"0.80"', 1, true) ~= nil, true, "opacity as Hyprland reads it")
    eq(hypr.dispatch("opacity", a, { alpha = 3 }), nil, "out of range")
    local before = { x = 0, y = 0, w = 900, h = 600, floating = true, fullscreen_mode = 0 }
    eq((hypr.verify("size", before, { x = 0, y = 0, w = 1280, h = 800 }, { w = 1280, h = 800 })), true, "a size read back")
    eq((hypr.verify("size", before, before, { w = 1280, h = 800 })), false, "one that did not take")
    eq((hypr.verify("swap", before, before, {})), false, "nothing moved: no swap")
end)

test("shutter: its key always, Super+Alt+right-click only while asked for, nothing while it is off", function()
    local desktop = require("lib/desktop")
    local keys = config.defaults().keys
    local function has(list, cmd) for _, b in ipairs(list) do if b[2] == cmd then return b[1] end end return nil end
    local on = desktop.binds(keys, { enabled = true, pointer = true })
    eq(has(on, "shutter"), "SUPER + ALT + D", "its key"); eq(has(on, "shutter-here"), desktop.POINTER, "the pointer gesture")
    eq(has(desktop.binds(keys, { enabled = true, pointer = false }), "shutter-here"), nil, "the gesture can be left out")
    local off = desktop.binds(keys, { enabled = false, pointer = true })
    eq(has(off, "shutter"), nil, "off: no key"); eq(has(off, "shutter-here"), nil, "and no gesture")
end)

test("the Overview's grid: miniatures in the screen's shape that fit", function()
    local atlas = require("lib/atlas")
    local g = atlas.grid(1920, 1080, 2, 5, 40)
    eq(math.abs(g.cw / g.ch - 1920 / 1080) < 0.001, true, "the Overview's miniatures have the screen's shape")
    eq(g.gx >= 0 and g.gx + 5 * g.cw + 4 * g.gap <= 1920 + 0.01, true, "and fit across it")
    eq(math.abs(g.cw - 1920 * atlas.SCALE) < 0.01, true, "iNiR's scale when it fits")
    eq(g.gy > 40 and g.gy < 40 + 90, true, "a panel just under the bar (a search row on top), not the middle of the screen")
    eq(math.abs(atlas.grid(1920, 1080, 2, 5, 40, 0.14).cw - 1920 * 0.14) < 0.01, true, "a size of its own")
    eq(atlas.grid(1920, 1080, 2, 5, 40, 0.24).cw < 1920 * 0.24, true, "too big to fit: shrunk to fit")
    local tall = atlas.grid(1920, 1080, 3, 6, 40)
    eq(tall.gy + 3 * tall.ch + 2 * tall.gap < 1080 - 60, true, "more rows shrink to leave room under them")
end)

test("overview strip: one row under the bar, never wider than the screen", function()
    local atlas = require("lib/atlas")
    local s = atlas.strip(1920, 1080, 6, 40)
    eq(math.abs(s.cw / s.ch - 1920 / 1080) < 0.001, true, "the screen's shape")
    eq(s.gy > 40 and s.gy + s.ch < 1080 * 0.25, true, "just under the bar, a band of the screen")
    eq(math.abs(s.gx * 2 + 6 * s.cw + 5 * s.gap - 1920) < 0.01, true, "centred")
    local many = atlas.strip(1920, 1080, 12, 40)
    eq(many.gx >= 1920 * 0.03 - 0.01 and many.cw < s.cw, true, "twelve shrink to fit")
end)

test("overview: Super+Tab while asked for, its own key always", function()
    local desktop = require("lib/desktop")
    local keys = config.defaults().keys
    local function has(list, key) for _, b in ipairs(list) do if b[1] == key then return b[2] end end return nil end
    eq(has(desktop.binds(keys, nil, { super_tab = true }), "SUPER + Tab"), "overview", "Super+Tab opens it")
    eq(has(desktop.binds(keys, nil, { super_tab = false }), "SUPER + Tab"), nil, "and can be left to another shell")
    eq(has(desktop.binds(keys, nil, { super_tab = false }), "SUPER + ALT + O"), "overview", "its own key stays")
end)

test("atlas privacy: sensitive windows keep to themselves, everything hides all", function()
    local atlas = require("lib/atlas")
    local function p(mode, app, title) return { atlas.private(mode, app, title) } end
    eq(p("off", "org.keepassxc.KeePassXC", "vault")[1], false, "off: shown")
    eq(p("sensitive", "org.keepassxc.KeePassXC", "vault")[1], true, "a password manager: no picture")
    eq(p("sensitive", "org.keepassxc.KeePassXC", "vault")[2], "Private window", "nor its title")
    eq(p("sensitive", "firefox", "Mozilla Firefox Private Browsing")[1], true, "private browsing, by its title")
    eq(p("sensitive", "kitty", "~/Projects")[2], "~/Projects", "the rest as they are")
    eq(p("everything", "kitty", "~/secret")[1], true, "everything: no picture")
    eq(p("everything", "kitty", "~/secret")[2], "kitty", "and the app's name for a title")
end)

test("overview keys: the next window in a cell, either way", function()
    local atlas = require("lib/atlas")
    local tiles = { { ocell = 0 }, { ocell = 2 }, { ocell = 0 }, { ocell = 0 } }
    eq(atlas.next_window(tiles, 0, -1), 0, "the first in the cell (0-based tile)")
    eq(atlas.next_window(tiles, 0, 0), 2, "then the next")
    eq(atlas.next_window(tiles, 0, 3), 0, "and round again")
    eq(atlas.next_window(tiles, 1, -1), -1, "an empty cell: none")
    eq(atlas.next_window(tiles, 2, 1), 1, "the only one stays")
    eq(atlas.next_window(tiles, 0, 2, -1), 0, "and backwards")
    eq(atlas.next_window(tiles, 0, -1, -1), 3, "from none, backwards: the last")
end)

test("overview steps desktops on the wheel and the arrows, round the ends", function()
    local atlas = require("lib/atlas")
    eq(atlas.step({ 1, 2, 5 }, 2, 1), 5, "the next")
    eq(atlas.step({ 1, 2, 5 }, 5, 1), 1, "round to the first")
    eq(atlas.step({ 1, 2, 5 }, 1, -1), 5, "back round")
    eq(atlas.step({ 1, 2, 5 }, 5, -1), 2, "the previous")
    eq(atlas.step({ 4 }, 4, 1), 4, "one stays")
    eq(atlas.step({}, 3, 1), nil, "none")
    eq(atlas.step({ 7 }, nil, 1), 7, "from none: the first")
end)

test("overview geometry survives a fact that has not arrived yet", function()
    -- audit 2026-11-01, A4: the pure geometry assumed numbers, so a nil screen threw.
    local atlas = require("lib/atlas")
    local g = atlas.grid(nil, nil, nil, nil, nil, nil)
    eq(g.cw, 0, "no screen, no cell"); eq(g.gap, 6, "with its gap")
    local s = atlas.strip(nil, nil, nil, nil)
    eq(s.cw, 0, "nor a strip"); eq(s.gy, 22, "its row still sits under the bar")
    local t = atlas.territories(nil, nil, nil, nil, nil)
    eq(#t, 0, "nor territories")
    local one = atlas.territories({ 1 }, nil, 1920, 1080, 5)
    eq(one[1].w, 1920, "a real screen still lays out")
end)

test("setters: a code applied to nothing sets nothing", function()
    local setters = require("lib/setters")
    eq(setters.apply(nil, 1000), nil, "no document")
    eq(setters.apply("nope", 1000), nil, "not a document")
    local d = require("lib/config").defaults()
    eq(setters.apply(d, 0), nil, "code 0")
    eq(setters.apply(d, -1), nil, "a negative code")
end)

test("overview spring edges: a band at each side, and the window landing where the hold stopped", function()
    local atlas = require("lib/atlas")
    eq(atlas.edge(0, 1920), -1, "the left edge")
    eq(atlas.edge(atlas.EDGE_BAND, 1920), -1, "its band")
    eq(atlas.edge(atlas.EDGE_BAND + 1, 1920), 0, "just inside it")
    eq(atlas.edge(1920, 1920), 1, "the right edge")
    eq(atlas.edge(1920 - atlas.EDGE_BAND, 1920), 1, "its band")
    eq(atlas.edge(960, 1920), 0, "the middle")
    eq(atlas.edge(10, 1920, 8), 0, "the band can be narrowed")
    eq(atlas.edge(nil, 1920), 0, "no pointer: no edge")
    eq(atlas.edge(4, 0), 0, "no screen: no edge")
    eq(atlas.spring_target(3, nil), 3, "let go off the board: the desktop the hold reached")
    eq(atlas.spring_target(3, 1), nil, "a cell under the pointer wins")
    eq(atlas.spring_target(nil, nil), nil, "the edges never stepped: nothing")
    -- the canvas (D116): the same band up and down, and a pan that is the same on the screen at any zoom
    eq(atlas.edge_y(0, 1080), -1, "the top edge")
    eq(atlas.edge_y(1080, 1080), 1, "the bottom edge")
    eq(atlas.edge_y(540, 1080), 0, "the middle")
    eq(atlas.edge_y(nil, 1080), 0, "no pointer: no edge")
    local panx, pany = atlas.pan_by(1, 0, 2)
    eq(panx, atlas.EDGE_PAN_SPEED * (atlas.EDGE_PAN_TICK / 1000) / 2, "the right edge pans right, in world units at that zoom")
    eq(pany, 0, "and not down")
    eq(select(2, atlas.pan_by(0, -1, 1)) < 0, true, "the top edge pans up")
    eq(atlas.pan_by(0, 0, 1), 0, "no edge, no pan")
    eq(atlas.pan_by(1, 0, 0.5) > atlas.pan_by(1, 0, 1), true, "zoomed out, the same screen speed is more world")
    eq(atlas.pan_by(1, 0, 0) > 0, true, "a zoom at the floor still pans")
    local config = require("lib/config")
    eq(config.defaults().atlas.spring_edges, true, "on by default, as Hyprdrive's")
    local SET = require("lib/setters").SETTERS
    local at = {}
    for i, p in ipairs(SET) do at[p] = i end
    eq(at["widgets.on"], at["atlas.spring_edges"] + 1, "the widgets' switch is appended after it")
    eq(at["widgets.mood"], at["widgets.on"] + 2, "then depth and mood (D139)")
    eq(at["desk.transition"], at["widgets.mood"] + 1, "D144's transition appended after them (D147)")
    local _, p = config.validate({ atlas = { spring_edges = "yes" } })
    eq(#p, 1, "a wrong type is reported")
end)

test("the retired Overview choices come back as the grid and mooi's own (D118)", function()
    local s, p = config.validate({ atlas = { overview = "mission", engine = "hyprdrive" } })
    eq(#p, 0, "no problems: they were choices, not mistakes")
    eq(s.atlas.overview, "grid", "Mission is the grid")
    eq(s.atlas.engine, "mooi", "Hyprdrive is mooi's own")
    eq(config.defaults().atlas.overview, "grid", "the grid is the default")
end)

test("overview sums: arithmetic only, bounded, never a divisor of zero", function()
    local calc = require("lib/calc")
    eq(calc.eval("1 + 2"), 3, "a sum")
    eq(calc.eval("2 * (3 + 4)"), 14, "parentheses")
    eq(calc.eval("10 / 4"), 2.5, "a fraction")
    eq(calc.eval("2 ^ 3"), 8, "a power")
    eq(calc.eval("-5 + 1"), -4, "a sign")
    eq(calc.eval("7 % 4"), 3, "a remainder")
    eq(calc.eval("1 / 0"), nil, "zero is not a divisor")
    eq(calc.eval("2 ^ 100"), nil, "too large to be useful")
    eq(calc.eval("firefox"), nil, "a name is not a sum")
    eq(calc.eval("mp3"), nil, "nor is a name with digits")
    eq(calc.eval("2 +"), nil, "an unfinished sum")
    eq(calc.format(2.5), "2.5", "a fraction as it is written")
    eq(calc.format(3), "3", "a whole number plainly")
end)

test("overview files: a literal bounded find, and rows from its output", function()
    local fs = require("lib/filesearch")
    eq(fs.escaped("a*b?[c]"), "a\\*b\\?\\[c\\]", "the query is a literal")
    local a = fs.args("/home/x", "re*port")
    eq(a[1], "/home/x/Desktop", "the first folder")
    eq(a[7], "-maxdepth", "bounded"); eq(a[8], "3", "three deep")
    eq(a[12], "*re\\*port*", "the escaped pattern")
    local out = "/home/x/Documents/note.txt\n/home/x/.config/x\n/home/x/Pictures/a.png\n/home/x/Documents/note.txt\n"
    local rows = fs.parse(out, 5)
    eq(#rows, 2, "hidden paths and duplicates left out")
    eq(rows[1].name, "note.txt", "a name")
    eq(rows[2].path, "/home/x/Pictures/a.png", "a path")
    eq(#fs.parse(out, 1), 1, "the cap is kept")
end)

test("overview moves: carry the marked together, undo only what can be undone", function()
    local atlas = require("lib/atlas")
    local tiles = { { address = "0xa", ws = 1 }, { address = "0xb", ws = 2 }, { address = "0xc", ws = 1 } }
    local m = atlas.carry(tiles, {}, 0, 3)
    eq(#m, 1, "unmarked: the one carried"); eq(m[1].address, "0xa", "it"); eq(m[1].from, 1, "from"); eq(m[1].to, 3, "to")
    m = atlas.carry(tiles, { ["0xa"] = true, ["0xc"] = true }, 0, 3)
    eq(#m, 2, "a marked one carries every marked one")
    m = atlas.carry(tiles, { ["0xa"] = true }, 1, 3)
    eq(#m, 1, "an unmarked one carries only itself"); eq(m[1].address, "0xb", "itself")
    m = atlas.carry(tiles, { ["0xa"] = true, ["0xb"] = true }, 1, 2)
    eq(#m, 1, "what is already there stays out"); eq(m[1].address, "0xa", "the other")
    eq(#atlas.carry(tiles, {}, 9, 3), 0, "no such tile: nothing")
    local moves = { { address = "0xa", from = 1, to = 3 }, { address = "0xc", from = 1, to = 3 }, { address = "0xd", from = 2, to = 3 } }
    local clients = { { address = "0xa", workspace = 3 }, { address = "0xc", workspace = 5 } }
    local back, skipped = atlas.undo(moves, clients)
    eq(#back, 1, "only a window still where it was put goes back"); eq(back[1].address, "0xa", "that one"); eq(back[1].to, 1, "to where it was")
    eq(skipped, 2, "one moved on since, one gone")
end)

test("overview search: windows by title or app, workspaces by name or number", function()
    local atlas = require("lib/atlas")
    local tiles = { { ocell = 0, title = "Inbox — Mail", app = "thunderbird" }, { ocell = 1, title = "~/Projects/mooi", app = "kitty" },
                    { ocell = 1, title = "Mozilla Firefox", app = "firefox" }, { ocell = -1, title = "fire drill", app = "x" } }
    local cells = { { id = 1, name = "" }, { id = 2, name = "Dev" }, { id = 3, name = "Research" } }
    local r = atlas.search(tiles, cells, "fire")
    eq(r.tiles[3], true, "the title matches"); eq(r.tiles[1], false, "the rest do not"); eq(r.tiles[4], false, "nor one off the page")
    eq(r.cells[2], true, "its workspace lights"); eq(r.cells[1], false, "others do not")
    eq(r.first_tile, 2, "Enter goes to the first window found (0-based)"); eq(r.first_cell, 1, "on its cell")
    r = atlas.search(tiles, cells, "KITTY"); eq(r.first_tile, 1, "the app, whatever the case")
    r = atlas.search(tiles, cells, "res"); eq(r.cells[3], true, "a workspace by its name"); eq(r.first_tile, -1, "no window"); eq(r.first_cell, 2, "that workspace")
    r = atlas.search(tiles, cells, "2"); eq(r.first_cell, 1, "a number is that workspace"); eq(r.first_tile, -1, "before any title with it in")
    r = atlas.search(tiles, cells, "  "); eq(r.active, false, "blank: no search")
    r = atlas.search(tiles, cells, "zzz"); eq(r.first_cell, -1, "nothing found: nowhere"); eq(r.count, 0, "and says so")
end)

test("overview menu: only what can be done there", function()
    local atlas = require("lib/atlas")
    local function kinds(m) local t = {} for _, it in ipairs(m) do t[#t + 1] = it.kind end return table.concat(t, ",") end
    eq(kinds(atlas.menu({ id = 3, windows = 0, active = false }, 0)), "go,rename,accent,group", "an empty workspace: go, name, accent, group")
    eq(kinds(atlas.menu({ id = 3, windows = 2, active = false }, 2)), "go,bring,rename,accent,group,close", "windows held to bring, windows to close")
    eq(kinds(atlas.menu({ id = 2, windows = 1, active = true }, 0)), "rename,accent,group,close", "the one you are on: no going there")
    eq(atlas.menu({ id = 2, windows = 0, active = true, group = "Dev" }, 0)[3].label, "Group: Dev ›", "says its group")
    eq(atlas.menu({ id = 3, windows = 2 }, 2)[2].label, "Move 2 windows here", "says how many")
    eq(atlas.menu({ id = 3, windows = 2 }, 0)[5].label, "Close its 2 windows", "and how many it closes")
    local w = atlas.menu({ id = 2, windows = 1, active = true }, 0, { app = "kitty", marked = false })
    eq(kinds(w), "mark,close_win,rename,accent,group,close", "a window's menu: its own rows first")
    eq(w[1].label, "Mark kitty", "named by its app"); eq(w[2].danger, true, "closing it is marked so")
    eq(atlas.menu({ id = 2, windows = 1 }, 0, { app = "kitty", marked = true })[1].label, "Unmark kitty", "and undone the same way")
end)

test("overview on several monitors: where each workspace lives, and what the others show", function()
    local atlas = require("lib/atlas")
    local monitors = { { name = "eDP-1", focused = true, activeWorkspace = { id = 2 } }, { name = "HDMI-A-1", focused = false, activeWorkspace = { id = 6 } } }
    local spaces = { { id = 1, monitor = "eDP-1" }, { id = 2, monitor = "eDP-1" }, { id = 6, monitor = "HDMI-A-1" }, { id = 7, monitor = "HDMI-A-1" } }
    local m = atlas.cell_monitors({ 1, 2, 3, 6, 7 }, spaces, monitors)
    eq(m.multi, true, "two monitors"); eq(m[1].mon, "eDP-1", "named by its monitor"); eq(m[3].mon, "", "one not made yet: no monitor")
    eq(m[4].elsewhere, true, "shown on the other monitor"); eq(m[4].mon, "HDMI-A-1", "which")
    eq(m[2].elsewhere, false, "the focused monitor's own is not elsewhere"); eq(m[5].elsewhere, false, "nor one the other monitor does not show")
    local one = atlas.cell_monitors({ 1, 2 }, { { id = 1, monitor = "eDP-1" } }, { { name = "eDP-1", focused = true, activeWorkspace = { id = 1 } } })
    eq(one.multi, false, "one monitor"); eq(one[1].mon, "", "then no names at all")
end)

test("overview gesture: off, or three or four fingers down, written beside the keys", function()
    local desktop = require("lib/desktop")
    eq(#desktop.gestures({ gesture = "off" }), 0, "off: none")
    local g = desktop.gestures({ gesture = "four" })
    eq(g[1][1], 4, "four fingers"); eq(g[1][2], "down", "down: the one direction the desktop leaves free"); eq(g[1][3], "overview", "opens it")
    eq(desktop.gestures({ gesture = "three" })[1][1], 3, "or three")
    local f = desktop.file(config.defaults().keys, config.defaults().desktop, nil, "/bin/mooi", nil, nil, { super_tab = true, gesture = "three" })
    eq(string.find(f, '{ 3, "down", "overview" }', 1, true) ~= nil, true, "in the file custom/mooi.lua reads")
end)

test("standalone: mooi as the whole desktop, written where Hyprland and the scripts read it", function()
    local desktop = require("lib/desktop")
    local d = config.defaults()
    eq(d.session.standalone, true, "on: mooi is the desktop (D134)")
    local f = desktop.file(d.keys, d.desktop, nil, "/bin/mooi", nil, nil, { super_tab = true }, { standalone = true })
    eq(string.find(f, "standalone = true", 1, true) ~= nil, true, "on: in the file custom/mooi.lua reads")
    f = desktop.file(d.keys, d.desktop, nil, "/bin/mooi", nil, nil, { super_tab = true }, { standalone = false })
    eq(string.find(f, "standalone = false", 1, true) ~= nil, true, "off: said so")
    local s, p = config.validate({ session = { standalone = "yes" } })
    eq(#p, 1, "a word is not a switch"); eq(s.session.standalone, true, "and the default stands")
    local n, np = config.validate({ notifications = { server = "takeover" } })
    eq(n.notifications.server, "desktop", "D134: a saved takeover is mooi as the desktop")
    eq(#np, 0, "moved quietly, not reported")
end)

test("overview rearrange: swap tiled windows, place a floating one, leave the rest to Hyprland", function()
    local atlas = require("lib/atlas")
    local tiles = { { address = "0xa", ocell = 1, fx = 0, fy = 0, fw = 0.5, fh = 1, floating = false },
                    { address = "0xb", ocell = 1, fx = 0.5, fy = 0, fw = 0.5, fh = 1, floating = false },
                    { address = "0xc", ocell = 1, fx = 0.3, fy = 0.3, fw = 0.4, fh = 0.4, floating = true },
                    { address = "0xd", ocell = 2, fx = 0, fy = 0, fw = 1, fh = 1, floating = false } }
    local r = atlas.rearrange(tiles, 0, 0.8, 0.2)
    eq(r.kind, "swap", "tiled onto tiled: swap"); eq(r.target, "0xb", "with the one under the pointer")
    eq(atlas.rearrange(tiles, 0, 0.45, 0.5).target, "0xc", "the topmost under the pointer (the floating one, drawn last)")
    eq(atlas.rearrange(tiles, 0, 0.45, 0.5).kind, "none", "but tiled onto floating: nothing")
    eq(atlas.rearrange(tiles, 0, 0.2, 0.5).kind, "none", "onto itself: nothing")
    r = atlas.rearrange(tiles, 2, 0.9, 0.9, 0.1, 0.1)
    eq(r.kind, "place", "a floating one is placed"); eq(math.abs(r.fx - 0.6) < 1e-9 and math.abs(r.fy - 0.6) < 1e-9, true, "kept on its screen (clamped)")
    r = atlas.rearrange(tiles, 2, 0.25, 0.25, 0.05, 0.05); eq(math.abs(r.fx - 0.2) < 1e-9, true, "where it was let go, less where it was held")
end)

test("hypr: swap with a window, place at a spot — dispatched and checked", function()
    eq(hypr.dispatch("swap_with", "0xa", { target = "0xb" }), "hl.dsp.window.swap({ target = \"address:0xb\", window = \"address:0xa\" })", "swap with one")
    eq(hypr.dispatch("swap_with", "0xa", { target = "x; rm" }), nil, "a target that is no address is refused")
    eq(hypr.dispatch("place", "0xa", { x = 300.4, y = 260 }), "hl.dsp.window.move({ x = 300, y = 260, window = \"address:0xa\" })", "placed")
    eq(hypr.dispatch("place", "0xa", { x = "a" }), nil, "a spot that is no number is refused")
    local before = { x = 0, y = 0 }
    eq(hypr.verify("swap_with", before, { x = 900, y = 0 }, {}), true, "moved: swapped")
    eq(hypr.verify("swap_with", before, { x = 0, y = 0 }, {}), false, "stayed: not")
    eq(hypr.verify("place", before, { x = 301, y = 259 }, { x = 300, y = 260 }), true, "where asked, give or take a pixel")
    eq(hypr.verify("place", before, { x = 0, y = 0 }, { x = 300, y = 260 }), false, "elsewhere: not")
end)

test("canvas territories: placed where they were put, the rest laid out around them", function()
    local atlas = require("lib/atlas")
    local r = atlas.territories({ 1, 2, 3 }, {}, 1920, 1080, 5)
    eq(r[1].x .. "," .. r[1].y, "0,0", "the first at the origin"); eq(r[1].w .. "x" .. r[1].h, "1920x1080", "a territory is the screen, full size")
    eq(r[2].x > 1920 and r[2].y == 0, true, "the next beside it, with a gap"); eq(r[3].x > r[2].x, true, "and on")
    local six = atlas.territories({ 1, 2, 3, 4, 5, 6 }, {}, 1920, 1080, 5)
    eq(six[6].x == 0 and six[6].y > 1080, true, "five across, then the next row")
    r = atlas.territories({ 1, 2, 3 }, { ["2"] = { 0, 0 } }, 1920, 1080, 5)
    eq(r[2].x .. "," .. r[2].y, "0,0", "a saved place kept"); eq(r[1].x ~= 0 or r[1].y ~= 0, true, "the unplaced one goes elsewhere, not on top of it")
    local function overlap(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end
    eq(overlap(r[1], r[2]) or overlap(r[1], r[3]) or overlap(r[2], r[3]), false, "none on top of another")
    eq(atlas.at_world(r, 10, 10), 2, "found by a point in it"); eq(atlas.at_world(r, -500, -500), nil, "empty canvas: none")
end)

test("canvas camera: fit them all, fill the screen with one, snap, the nearest one each way", function()
    local atlas = require("lib/atlas")
    local r = { { x = 0, y = 0, w = 1920, h = 1080 }, { x = 4000, y = 0, w = 1920, h = 1080 }, { x = 0, y = 3000, w = 1920, h = 1080 } }
    local cx, cy, z = atlas.fit(r, 1920, 1080, 100, 40)
    eq((5920 * z <= 1920 - 80 + 0.01) and (4080 * z <= 1080 - 100 - 80 + 0.01), true, "everything inside the view, margins kept")
    eq(math.abs(((0 - cx) * z + (5920 - cx) * z) / 2 - 960) < 0.5, true, "centred across")
    eq(math.abs(((0 - cy) * z + (4080 - cy) * z) / 2 - (100 + (1080 - 100) / 2)) < 0.5, true, "centred under the bar")
    cx, cy, z = atlas.focus_cam(r[2], 1920)
    eq(cx == 4000 and cy == 0 and z == 1, true, "one territory filling the screen: the camera on its corner at 100 %")
    eq(atlas.snap(97, 40), 80, "snapped down"); eq(atlas.snap(101, 40), 120, "and up")
    eq(atlas.near(r, 0, "right"), 1, "right of the first: the second"); eq(atlas.near(r, 0, "down"), 2, "below it: the third")
    eq(atlas.near(r, 1, "right"), nil, "nothing further right"); eq(atlas.near(r, 2, "up"), 0, "above the third: the first, straight up")
    local s = atlas.canvas_place({ version = 1, spaces = {}, groups = {}, canvas = {} }, 4, 1234.6, -40)
    eq(s.canvas["4"][1] .. "," .. s.canvas["4"][2], "1235,-40", "a place kept, whole pixels, anywhere")
    eq(atlas.identities({ version = 1, canvas = { ["2"] = { 5000000, 0 } } }).canvas["2"], nil, "absurdly far: dropped")
end)

test("group marks follow the slots: joined to the slot on the right, named on the first read", function()
    local atlas = require("lib/atlas")
    local s = atlas.identities({ version = 1, groups = { { name = "Dev", spaces = { 1, 2 } } } })
    local m = atlas.group_marks(s, { 1, 2, 3 }, 5, { { sc = 3, sr = 1 }, { sc = 4, sr = 1 }, { sc = 0, sr = 0 } })
    eq(m[1].glink, true, "1 sits left of 2: joined"); eq(m[2].glink, false, "nothing of it to 2's right")
    local m2 = atlas.group_marks(s, { 1, 2, 3 }, 5, { { sc = 4, sr = 1 }, { sc = 3, sr = 1 }, { sc = 0, sr = 0 } })
    eq(m2[2].glink, true, "2 left of 1 now: 2 joins"); eq(m2[2].gfirst, true, "and is read first, so it is named")
end)

test("workspace groups: one group a workspace, checked, never more than asked", function()
    local atlas = require("lib/atlas")
    local s = atlas.identities({ version = 1, spaces = {}, groups = {
        { name = "  Dev ", accent = "phos", spaces = { 3, 1, 2, 2, "x" } },
        { name = "Comms", accent = "neon", spaces = { 2, 4 } },
        { name = "Empty", spaces = {} }, "junk" } })
    eq(#s.groups, 2, "junk and empty groups dropped"); eq(s.groups[1].name, "Dev", "trimmed")
    eq(table.concat(s.groups[1].spaces, ","), "1,2,3", "sorted, once each"); eq(table.concat(s.groups[2].spaces, ","), "4", "a workspace already taken stays with the first")
    eq(s.groups[2].accent, "phos", "an unknown colour: the signal's")
    eq(atlas.group_of(s, 2), 1, "found by its workspace"); eq(atlas.group_of(s, 9), nil, "or none")
    s = atlas.group_join(s, 2, 3); eq(table.concat(s.groups[1].spaces, ","), "1,2", "joining one leaves the other"); eq(table.concat(s.groups[2].spaces, ","), "3,4", "for this")
    s = atlas.group_new(s, 6, "Research"); eq(#s.groups, 3, "a new group"); eq(atlas.group_of(s, 6), 3, "holding its workspace")
    s = atlas.group_leave(s, 6); eq(#s.groups, 2, "left empty, it goes")
    s = atlas.group_rename(s, 1, "  "); eq(s.groups[1].name, "Dev", "a blank name is not taken")
    s = atlas.group_rename(s, 1, "Code"); eq(s.groups[1].name, "Code", "a name is")
    s = atlas.group_next_accent(s, 1); eq(s.groups[1].accent, "ember", "colours go round")
    s = atlas.group_remove(s, 1); eq(#s.groups, 1, "taken away"); eq(atlas.group_of(s, 1), nil, "its workspaces in none")
    eq(atlas.identities({ version = 1, spaces = { ["2"] = { name = "hi", accent = "phos" } } }).spaces["2"].name, "hi", "a file from before groups reads as it was")
end)

test("workspace groups: marks on the page, and the menu's group page", function()
    local atlas = require("lib/atlas")
    local s = atlas.identities({ version = 1, groups = { { name = "Dev", accent = "ember", spaces = { 2, 3, 6, 7 } } } })
    local m = atlas.group_marks(s, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 5)
    eq(m[1].grp, -1, "not in one"); eq(m[2].grp, 0, "in the first"); eq(m[2].gacc, 2, "its colour")
    eq(m[2].gfirst, true, "named on its first"); eq(m[3].gfirst, false, "once"); eq(m[2].glink, true, "joined to the next in the row")
    eq(m[3].glink, false, "not to one outside"); eq(m[6].glink, true, "on the next row too"); eq(m[5].glink, false, "never across the row's end")
    local function kinds(t) local o = {} for _, it in ipairs(t) do o[#o + 1] = it.kind end return table.concat(o, ",") end
    eq(kinds(atlas.group_menu(s, 1)), "gjoin,gnew,back", "outside: join, start one, back")
    eq(kinds(atlas.group_menu(s, 2)), "gnew,gleave,grename,gaccent,gremove,back", "inside: leave, rename, colour, take away")
    eq(atlas.group_menu(s, 1)[1].label, "Join Dev", "named")
    local r = atlas.search({}, { { id = 2, name = "", group = "Dev" }, { id = 4, name = "" } }, "dev")
    eq(r.cells[1], true, "search finds a group's workspaces by its name"); eq(r.cells[2], false, "and not the others")
end)

test("workspace identity: names and accents of mooi's own, checked on the way in", function()
    local atlas = require("lib/atlas")
    local s = atlas.identities({ version = 1, spaces = { ["2"] = { name = "  Mail  ", accent = "ember" }, ["x"] = { name = "no" },
                                                       ["3"] = { name = string.rep("a", 60), accent = "neon" }, ["4"] = "junk" } })
    eq(atlas.identity(s, 2).name, "Mail", "trimmed"); eq(atlas.identity(s, 2).accent, "ember", "accent")
    eq(#atlas.identity(s, 3).name, atlas.NAME_MAX, "cut to length"); eq(atlas.identity(s, 3).accent, "none", "an unknown accent: none")
    eq(atlas.identity(s, 4).name, "", "junk: no name"); eq(atlas.identity(s, 9).accent, "none", "unset: none")
    eq(atlas.identities(nil).version, 1, "nothing: an empty store"); eq(next(atlas.identities({ version = 99, spaces = { ["1"] = { name = "x" } } }).spaces), nil, "a newer file: not guessed at")
    s = atlas.name(s, 2, ""); eq(atlas.identity(s, 2).name, "", "a name cleared"); eq(atlas.identity(s, 2).accent, "ember", "the accent kept")
    s = atlas.next_accent(s, 2); eq(atlas.identity(s, 2).accent, atlas.ACCENTS[1], "accents go round")
    s = atlas.next_accent(atlas.name(s, 2, ""), 2); s = atlas.name(s, 2, ""); s = atlas.identities(s)
    eq(s.spaces["2"] ~= nil, true, "an accent alone is kept")
    eq(atlas.accent_index("ember"), 2, "the scene's colour by number"); eq(atlas.accent_index("what"), 0, "none")
end)

test("apps: a window's .desktop entry, by the same matches as its icon", function()
    local list = { { id = "org.gnome.Nautilus", name = "Files", exec = "nautilus --new-window %U", icon = "x" },
                   { id = "kitty", name = "kitty", exec = "kitty", wmclass = "kitty", icon = "" } }
    eq(apps.app_for(list, "org.gnome.Nautilus").id, "org.gnome.Nautilus", "by its id")
    eq(apps.app_for(list, "nautilus").id, "org.gnome.Nautilus", "by the id's last part")
    eq(apps.app_for(list, "kitty").id, "kitty", "with no icon too")
    eq(apps.app_for(list, "nothing"), nil, "or none")
end)

test("a terminal's shell: the newest shell among its children, not its helpers", function()
    local out = " 347639 kitten\n 347648 zsh\n 347651 kitten\n"
    eq(hypr.terminal_shell(out), 347648, "kitty's kittens passed over")
    eq(hypr.terminal_shell(" 10 bash\n 12 fish\n"), 12, "the newest shell")
    eq(hypr.terminal_shell(" 10 kitten\n"), nil, "no shell: none")
    eq(hypr.terminal_shell(""), nil, "nothing: none")
end)

local envs = require("lib/environments")
test("environments: captured from the desktop, checked on the way back in", function()
    local idn = { version = 1, spaces = { ["2"] = { name = "Mail", accent = "phos" } }, groups = { { name = "Dev", accent = "phos", spaces = { 1, 2 } } } }
    local e = envs.capture("  Work ", 1760000000, idn, {
        { class = "kitty", desktop = "kitty", workspace = 1, title = "~/p", cwd = "/home/u/p" },
        { class = "firefox", desktop = "firefox", workspace = 2, title = "Mail" },
        { class = "x", desktop = nil, workspace = -98, title = "special" } })
    eq(e.name, "Work", "trimmed"); eq(#e.windows, 2, "special workspaces left out"); eq(e.windows[1].cwd, "/home/u/p", "a folder kept")
    eq(e.identities.groups[1].name, "Dev", "groups kept"); eq(e.identities.spaces["2"].name, "Mail", "names kept")
    local store = envs.clean({ version = 1, envs = { e,
        { name = "bad", windows = { { class = "a", desktop = "../../bin/sh", workspace = 1 }, { class = "b", desktop = "b", workspace = 1, cwd = "relative/dir" },
                                    { class = "c", desktop = "c", workspace = 1, cwd = "/tmp/x\nrm -rf ~" }, { class = "d", desktop = "d", workspace = 0 } } },
        "junk", { name = "" } } })
    eq(#store.envs, 2, "junk and nameless left out"); eq(store.envs[2].windows[1].desktop, "", "a desktop id that is a path is no id")
    eq(store.envs[2].windows[2].cwd, "", "a relative folder dropped"); eq(store.envs[2].windows[3].cwd, "", "and one with a line break")
    eq(#store.envs[2].windows, 3, "a window on no workspace dropped")
    eq(#envs.clean({ version = 2, envs = { e } }).envs, 0, "a newer file is not guessed at")
    eq(#envs.clean(nil).envs, 0, "nothing: empty")
end)

test("environments: a restore plan moves, opens, and never closes", function()
    local e = { windows = {
        { class = "kitty", desktop = "kitty", workspace = 1, cwd = "/p" },
        { class = "kitty", desktop = "kitty", workspace = 3, cwd = "/q" },
        { class = "firefox", desktop = "firefox", workspace = 2 },
        { class = "obsidian", desktop = "obsidian", workspace = 4 },
        { class = "zz", desktop = "", workspace = 5 } } }
    local now = { { address = "0xa", class = "kitty", workspace = 1 }, { address = "0xb", class = "firefox", workspace = 6 },
                  { address = "0xc", class = "kitty", workspace = 9 }, { address = "0xd", class = "zen", workspace = 1 } }
    local p = envs.plan(e, now, { kitty = true, firefox = true })
    eq(p.in_place, 1, "a kitty already on 1"); eq(#p.moves, 2, "another kitty and firefox move")
    local m = {}; for _, x in ipairs(p.moves) do m[x.address] = x.to end
    eq(m["0xb"], 2, "firefox to its workspace"); eq(m["0xc"], 3, "the other kitty to 3")
    eq(#p.launches, 0, "nothing to open: every saved window has one")
    eq(#p.cannot, 2, "not installed, and no app known"); eq(p.cannot[1].app, "obsidian", "named")
    p = envs.plan(e, {}, { kitty = true, firefox = true })
    eq(#p.launches, 3, "an empty desktop: open them"); eq(p.launches[1].cwd, "/p", "with their folders"); eq(p.launches[3].workspace, 2, "on their workspaces")
end)

test("environments: a launch line from the installed entry, the folder quoted", function()
    eq(envs.launch_line("firefox %u", "firefox", ""), "firefox", "field codes out")
    eq(envs.launch_line("kitty", "kitty", "/home/u/it's here"), "kitty --directory '/home/u/it'\\''s here'", "a terminal opens in its folder, quoted")
    eq(envs.launch_line("foot", "foot", "/a"), "foot --working-directory='/a'", "foot's way")
    eq(envs.launch_line("gedit %F", "gedit", "/a"), "gedit", "a folder only where the app takes one")
    eq(envs.exec_cmd(3, "kitty --directory '/a b'"), "hl.exec_cmd('[workspace 3 silent] kitty --directory \\'/a b\\'')", "onto its workspace, as Lua")
end)

print("signals")
local sig = require("lib/signals")
local function N(t)
    local base = { id = 1, app = "Chat", title = "Ana", body = "hi", icon = "", image = "", urgency = "normal", time = 100, actions = {} }
    for k, v in pairs(t or {}) do base[k] = v end
    return sig.clean(base)
end
test("signals: what comes in is cleaned, never trusted", function()
    eq(sig.plain("<b>Build</b> &amp; test&#33;\n\tdone"), "Build & test! done", "markup out, entities read, space folded")
    eq(sig.plain(nil), "", "not a string: empty")
    eq(sig.plain(string.rep("é", 200), 10):sub(-3), "…", "cut, and marked as cut")
    local n = sig.clean({ id = 7, app = 5, title = "T", urgency = "weird", actions = { { key = "default", label = "Open" }, { key = "r", label = "Reply" }, "bad" } })
    eq(n.app, "", "a number is not an app name"); eq(n.urgency, "normal", "an unknown urgency is normal")
    eq(n.default, true, "the default action is a press on the notice"); eq(#n.actions, 1, "the rest are buttons, the bad one dropped")
    eq(sig.clean({ app = "x" }), nil, "no id: nothing")
    eq(sig.clean({ id = 1, urgency = 2 }).urgency, "critical", "the server's 2 is critical")
    eq(sig.clean({ id = 1, urgency = 0 }).urgency, "low", "its 0 is low"); eq(sig.clean({ id = 1, urgency = 1 }).urgency, "normal", "its 1 normal")
end)
test("signals: the tier comes from urgency and your rules, not the words", function()
    eq(sig.tier(N({ urgency = "critical" }), { quiet = true }), sig.INTERVENTION, "critical breaks through quiet")
    eq(sig.tier(N({ urgency = "low" })), sig.WHISPER, "low whispers")
    eq(sig.tier(N({ title = "URGENT!!! server down" })), sig.MANIFEST, "shouting does not make it urgent")
    eq(sig.tier(N(), { muted = { Chat = true } }), sig.WHISPER, "a muted app whispers")
    eq(sig.tier(N(), { quiet = true }), sig.WHISPER, "quiet: a whisper")
    eq(sig.kind(N({ image = "/tmp/a.png" })), sig.CONVERSATION, "a picture: a conversation's layout")
    eq(sig.kind(N()), sig.EVENT, "otherwise an event")
end)
test("signals: related notices are one group, nothing unrelated joins it", function()
    local list = { N({ id = 3, title = "Ana", time = 30 }), N({ id = 2, title = "Bo", time = 20 }), N({ id = 1, title = "Ana", time = 10 }),
                   N({ id = 4, app = "Mail", title = "Ana", time = 5 }) }
    local g = sig.groups(list, "thread")
    eq(#g, 3, "Ana's thread, Bo's, and Mail's Ana (another app)"); eq(g[1].count, 2, "two in Ana's thread"); eq(g[1].newest.id, 3, "the newest speaks")
    eq(#sig.groups(list, "app"), 2, "by app: Chat and Mail"); eq(#sig.groups(list, "off"), 4, "off: each alone")
end)
test("signals: an update under the same id is a change, not a new arrival", function()
    local a = { N({ id = 1, body = "50%" }) }
    local d1 = sig.diff({}, a)
    eq(#d1.added, 1, "new")
    local d2 = sig.diff(d1.sigs, { N({ id = 1, body = "100%" }) })
    eq(#d2.added, 0, "not added again"); eq(#d2.changed, 1, "changed in place")
    local d3 = sig.diff(d2.sigs, {})
    eq(#d3.removed, 1, "gone")
end)
test("signals: what is out, and for how long", function()
    local g = sig.groups({ N({ id = 3, title = "a" }), N({ id = 2, title = "b" }), N({ id = 1, title = "c", urgency = "critical" }) }, "thread")
    local st = { seen = { [3] = 0, [2] = 0, [1] = 0 }, tiers = { [3] = sig.MANIFEST, [2] = sig.WHISPER, [1] = sig.INTERVENTION }, snooze = {}, shelved = {} }
    local live, more = sig.live(g, st, 3000, 4, 7)
    eq(#live, 3, "all out at 3 s"); eq(more, 0, "none over")
    live = sig.live(g, st, 5000, 4, 7)
    eq(#live, 2, "the whisper (3.5 s) has gone at 5 s")
    live = sig.live(g, st, 60000, 4, 7)
    eq(#live, 1, "only the critical one stays"); eq(live[1].newest.id, 1, "it")
    live = sig.live(g, st, 60000, 4, 7, true)
    eq(#live, 3, "the pointer on the cluster holds them all")
    st.snooze[1] = 90000
    eq(#sig.live(g, st, 60000, 4, 7), 0, "snoozed: not out until then")
    st.snooze[1] = nil
    live, more = sig.live(g, st, 1000, 1, 7)
    eq(#live, 1, "at most max"); eq(more, 2, "and how many more")
    eq(live[1].newest.id, 1, "the urgent one is never the one left waiting, though it is the oldest")
end)
test("signals: a group keeps its slot; a new one takes a free slot, not a retracting one", function()
    local function G(k) return { key = k } end
    local slots, gone = sig.place({}, { G("a"), G("b") }, 4)
    eq(slots[1], "a", "a in 1"); eq(slots[2], "b", "b in 2"); eq(#gone, 0, "none gone")
    slots, gone = sig.place(slots, { G("c"), G("b") }, 4)
    eq(slots[2], "b", "b stays in 2"); eq(gone[1], 1, "a's slot retracts"); eq(slots[1], nil, "not reused while it retracts")
    eq(slots[3], "c", "c takes a free one")
    slots = sig.place({ [2] = "b" }, { G("d"), G("b") }, 4, { [1] = true })
    eq(slots[3], "d", "a busy slot is skipped")
end)
test("signals: the stack, joined where one app follows itself", function()
    local live = { { key = "x", app = "A", newest = { id = 1 } }, { key = "y", app = "A", newest = { id = 2 } }, { key = "z", app = "B", newest = { id = 3 } } }
    local at, total = sig.stack(live, { [0] = 30, [1] = 64, [2] = 96 }, 8, { [1] = 1, [2] = 0, [3] = 2 })
    eq(at.x.y, 0, "first at the edge"); eq(at.y.linked, true, "same app: joined"); eq(at.y.y, 68, "closer, by half the gap")
    eq(at.z.linked, false, "another app: apart"); eq(at.z.y, 106, "after the whisper"); eq(total, 210, "the cluster's length")
    eq(sig.ago(100, 130), "now", "now"); eq(sig.ago(0, 600), "10 min", "minutes"); eq(sig.ago(0, 7200), "2 h", "hours")
    eq(sig.rail(0, 0, 3600), 0, "now at the start"); eq(sig.rail(0, 3600, 3600), 1, "the span at the end"); eq(sig.rail(0, 4000, 3600), nil, "past it: off")
end)

print("notes")
local notes = require("lib/notes")
test("notes: what is written is cleaned, never kept raw", function()
    eq(notes.clean("  call Ana \r\n  about the \tbuild  "), "call Ana\nabout the build", "edges trimmed, lines kept")
    eq(notes.clean(nil), "", "not a string: empty")
    eq(notes.clean("\0\7x"), "x", "control characters made spaces")
    eq(notes.clean("a\n\n\n\nb"), "a\n\nb", "runs of blank lines folded")
    eq(notes.clean(string.rep("é", 3000)):sub(-3), "…", "cut, and marked as cut")
    eq(#notes.clean(string.rep("é", 5000)), notes.TEXT_MAX + 3, "cut to the length (and the mark)")
end)
test("notes: a row is one line and says how long ago", function()
    eq(notes.one_line("buy\n  milk  \nand bread"), "buy milk and bread", "one line")
    eq(notes.one_line(nil), "", "not a string: empty")
    eq(notes.ago(1000, 1000), "now", "now"); eq(notes.ago(1000, 941), "now", "under a minute")
    eq(notes.ago(1000, 940), "1m", "a minute"); eq(notes.ago(10000, 1000), "2h", "hours")
    eq(notes.ago(1000000, 1000), "11d", "days"); eq(notes.ago(10000000, 1000), "16w", "weeks")
end)
test("notes: adding puts the newest first, refusing the empty", function()
    local list = {}
    local added
    list, added = notes.add(list, "   ", 5); eq(added, nil, "nothing written: nothing added"); eq(#list, 0, "still empty")
    list, added = notes.add(list, "first", 10); eq(added.id, 1, "first id"); eq(list[1].text, "first", "at the top")
    list, added = notes.add(list, "<b>second</b>", 20); eq(added.id, 2, "next id"); eq(list[1].text, "<b>second</b>", "the newest is first")
    eq(list[2].id, 1, "the older one follows")
    local full = {}
    for i = 1, notes.MAX do full[i] = { id = i, text = "n" .. i, time = i } end
    full, _ = notes.add(full, "one more", notes.MAX + 1)
    eq(#full, notes.MAX, "the cap holds"); eq(full[1].text, "one more", "the new one is kept")
    eq(notes.find(full, notes.MAX + 1).text, "one more", "find by id"); eq(notes.find(full, 9999), nil, "an id that is not there")
end)
test("notes: removing one, and a file read back is cleaned", function()
    local list = { { id = 1, text = "a", time = 1 }, { id = 2, text = "b", time = 2 } }
    local gone
    list, gone = notes.remove(list, 2); eq(gone, true, "removed"); eq(#list, 1, "one left"); eq(list[1].id, 1, "the other")
    list, gone = notes.remove(list, 2); eq(gone, false, "not there any more")
    local back = notes.decode({ version = 1, notes = {
        { id = 2, text = "  later  ", time = 20 }, { id = 1, text = "earlier", time = 10 },
        { id = 2, text = "duplicate", time = 30 }, { id = 0, text = "bad id", time = 40 },
        { id = 4, text = "   ", time = 50 }, { id = 5, text = 7, time = 60 }, "not a note" } })
    eq(#back, 4, "every note kept: a repeated or bad id is renumbered, never dropped")
    eq(back[1].text, "bad id", "newest first"); eq(back[1].id, 4, "a new number after the highest")
    eq(back[2].text, "duplicate", "the repeat kept"); eq(back[2].id, 3, "with its own number (renumbered in the order read)")
    eq(back[3].text, "later", "cleaned"); eq(back[4].text, "earlier", "the oldest last")
    back = { back[3], back[4] }
    eq(notes.decode("nope")[1], nil, "not a table: nothing"); eq(notes.decode({ notes = 5 })[1], nil, "notes not a list: nothing")
    local round = notes.decode(notes.encode(back))
    eq(round[1].text, "later", "encode then decode keeps it"); eq(round[1].id, 2, "and its id"); eq(round[2].time, 10, "and its time")
end)

test("notes: a pinned note stays on top, survives the cap, and is kept in the file", function()
    local list = {}
    for i = 1, 3 do list = notes.add(list, "n" .. i, i) end
    local pinned
    list, pinned = notes.pin(list, 1); eq(pinned, true, "pinned"); eq(list[1].text, "n1", "the oldest, pinned, on top")
    list = notes.add(list, "n4", 4); eq(list[1].text, "n1", "a new note goes under the pinned one"); eq(list[2].text, "n4", "first of the rest")
    local back = notes.decode(notes.encode(list)); eq(back[1].pinned, true, "pinned in the file"); eq(back[2].pinned, false, "the rest not")
    list, pinned = notes.pin(list, 1); eq(pinned, false, "let go"); eq(list[#list].text, "n1", "back among the rest, by its time")
    local big = {}
    for i = 1, notes.MAX do big = notes.add(big, "x" .. i, i) end
    big = notes.pin(big, 1)
    big = notes.add(big, "one more", notes.MAX + 1)
    eq(#big, notes.MAX, "capped"); eq(big[1].text, "x1", "the pinned oldest survives the cap")
    local t, r = notes.split("Buy cables\nthe long ones\nand tape"); eq(t, "Buy cables", "the first line is the card"); eq(r, "the long ones\nand tape", "the rest its note")
end)

test("notes: editing keeps the id and its place; a forgotten one comes back", function()
    local list = { { id = 2, text = "newer", time = 20 }, { id = 1, text = "older", time = 10 } }
    local edited
    list, edited = notes.update(list, 1, "  older, fixed  ", 30)
    eq(edited.id, 1, "same id"); eq(list[2].text, "older, fixed", "cleaned"); eq(list[2].time, 30, "time moves to now")
    eq(list[1].id, 2, "its place is kept")
    list, edited = notes.update(list, 1, "   ", 40); eq(edited, nil, "an empty edit is refused"); eq(list[2].text, "older, fixed", "unchanged")
    local gone = { id = 1, text = "older, fixed", time = 30 }
    list = notes.remove(list, 1)   -- as the dropdown's × does, before Undo
    local back
    list, back = notes.restore(list, gone, 50)
    eq(back.id, 1, "its id is back"); eq(#list, 2, "and it is back in the list")
    eq(list[1].id, 1, "where its time says"); eq(list[2].id, 2, "the other follows")
    local taken = { id = 1, text = "another", time = 60 }
    list, back = notes.restore(list, taken, 60)
    eq(back.id, 3, "a taken id gets a new one"); eq(#list, 3, "both are kept")
    local _, nothing = notes.restore(list, { id = 9, text = "  ", time = 1 })
    eq(nothing, nil, "an empty one is not restored")
end)

print("board")
local board = require("lib/board")
local function titles(b, col) local t = {}; for _, c in ipairs(board.cards_in(b, col)) do t[#t + 1] = c.title end; return table.concat(t, ",") end
test("board: a new board, cards added at the top, empty titles refused", function()
    local b = board.new()
    eq(#b.columns, 3, "inbox, doing, done"); eq(b.columns[2].wip, 3, "doing holds three")
    local a = board.add(b, 1, "  write   the brief ", "", 10); eq(a.title, "write the brief", "cleaned")
    board.add(b, 1, "second", "why", 11)
    eq(titles(b, 1), "second,write the brief", "the newest on top")
    local none, why = board.add(b, 1, "   ", "", 12); eq(none, nil, "no title, no card"); eq(why ~= nil, true, "and why")
    eq(board.add(b, 99, "x", "", 1), nil, "no such column")
    local d = board.add(b, 3, "already done", "", 13); eq(d.done_at, 13, "added straight to Done: done now")
end)
test("board: moving, stepping, and the done stamp", function()
    local b = board.new()
    local a = board.add(b, 1, "a", "", 1); local bb = board.add(b, 1, "b", "", 2); local c = board.add(b, 1, "c", "", 3)
    eq(titles(b, 1), "c,b,a", "top to bottom")
    eq(board.move(b, a.id, 1, 1, 5), true, "a to the top"); eq(titles(b, 1), "a,c,b", "reordered")
    eq(board.move(b, a.id, 1, 1, 6), false, "already there: no move")
    board.move(b, c.id, 2, 1, 7); eq(titles(b, 2), "c", "c to Doing")
    board.move(b, bb.id, 3, 9, 8); eq(titles(b, 3), "b", "an index past the end is the end"); eq(bb.done_at, 8, "done when it reaches Done")
    board.move(b, bb.id, 2, 1, 9); eq(bb.done_at, nil, "and not done when it leaves")
    eq(board.step(b, c.id, 1, 0, 10), true, "a step right"); eq(c.col, 3, "into Done")
    eq(board.step(b, c.id, 1, 0, 11), false, "no column past the last")
    board.step(b, bb.id, 0, 1, 12); eq(titles(b, 2), "b", "a step down past the end stays")
    board.move(b, a.id, 2, 2, 13); board.step(b, a.id, 0, -1, 14); eq(titles(b, 2), "a,b", "a step up")
end)
test("board: removed and put back where it was; columns kept tidy", function()
    local b = board.new()
    board.add(b, 1, "a", "", 1); local x = board.add(b, 1, "x", "", 2); board.add(b, 1, "c", "", 3)
    local taken = board.remove(b, x.id); eq(titles(b, 1), "c,a", "taken out")
    eq(board.restore(b, taken), true, "put back"); eq(titles(b, 1), "c,x,a", "where it was")
    eq(board.restore(b, taken), false, "not twice")
    local col = board.add_column(b, "Review"); eq(b.columns[3].id, col.id, "a new column goes before Done"); eq(b.columns[4].title, "Done", "Done stays last")
    eq(board.remove_column(b, 1), false, "a column with cards stays")
    eq(board.remove_column(b, col.id), true, "an empty one goes")
    eq(board.rename_column(b, 2, "  In progress "), true, "renamed"); eq(b.columns[2].title, "In progress", "cleaned")
    eq(board.move_column(b, 2, -1), true, "moved left"); eq(b.columns[1].id, 2, "now first")
    for i = 1, 3 do board.add_column(b, "c" .. i) end
    eq(#b.columns, 6, "six"); eq(board.add_column(b, "seventh"), nil, "and no more")
end)
test("board: days, the filter, the archive and the stats", function()
    eq(board.today(86400 * 100 + 3600, 0), 100, "UTC"); eq(board.today(86400 * 100 - 3600, 7200), 100, "a zone ahead is already tomorrow")
    eq(board.due_text(99, 100), "yesterday", "yesterday"); eq(board.due_text(97, 100), "3 d late", "late"); eq(board.due_text(100, 100), "today", "today")
    eq(board.due_text(101, 100), "tomorrow", "tomorrow"); eq(board.due_text(104, 100), "in 4 d", "days"); eq(board.due_text(114, 100), "in 2 w", "weeks")
    eq(board.due_state(99, 100), 4, "late"); eq(board.due_state(100, 100), 3, "today"); eq(board.due_state(102, 100), 2, "soon"); eq(board.due_state(nil, 100), 0, "none")
    eq(board.preset("week", 100), 107, "a week"); eq(board.preset("none", 100), false, "none clears")
    local b = board.new()
    local a = board.add(b, 1, "Buy cables", "the long ones", 1); board.update(b, a.id, { tag = 2, due = 99 }, 2)
    local c = board.add(b, 1, "Write", "", 3); board.update(b, c.id, { due = 100 }, 4)
    eq(board.shows(a, "LONG", 0), true, "the note is searched, any case"); eq(board.shows(c, "long", 0), false, "not there")
    eq(board.shows(a, "", 2), true, "its tag"); eq(board.shows(c, "", 2), false, "another tag")
    local st = board.stats(b, 100); eq(st.late, 1, "one late"); eq(st.today, 1, "one today")
    board.move(b, c.id, 3, 1, 5); eq(board.archive_done(b, 6), 1, "one archived"); eq(#b.archive, 1, "kept"); eq(board.stats(b, 100).today, 0, "gone from the count")
    eq(board.update(b, a.id, { title = "   " }, 7), false, "an empty title does not take"); eq(a.title, "Buy cables", "kept")
    eq(board.update(b, a.id, { due = false }, 8), true, "the due day cleared"); eq(a.due, nil, "none")
end)
test("board: a file read back, and where a dragged card lands", function()
    local b = board.decode({ columns = { { id = 1, title = "A" }, { id = 1, title = "B" }, { title = "" }, "x" },
        cards = { { id = 5, col = 1, title = "one" }, { id = 5, col = 1, title = "two" }, { id = 6, col = 42, title = "orphan" }, { col = 1, title = "" } } })
    eq(#b.columns, 2, "two columns (one blank dropped)"); eq(b.columns[2].id ~= 1, true, "the repeated id renumbered")
    eq(#b.cards, 2, "two cards: the orphan and the blank dropped"); eq(b.cards[1].id ~= b.cards[2].id, true, "ids unique")
    eq(b.next_id > 6, true, "next id past every one")
    eq(#board.decode("junk").columns, 3, "junk: a new board"); eq(#board.decode({ columns = {} }).columns, 3, "no columns: a new board")
    local r = board.decode(board.encode(b)); eq(#r.cards, 2, "round trip"); eq(r.cards[1].title, "one", "in order")
    local nb = board.new()
    local x = board.add(nb, 1, "x", "", 1); local y = board.add(nb, 1, "y", "note", 2); board.add(nb, 2, "z", "", 3)
    local lay = board.layout(nb, { x0 = 0, y0 = 0, width = 312, height = 600, gap = 12 })
    eq(lay.cols[1].w, 96, "three columns share the width"); eq(lay.cols[2].x, 108, "the second after a gap")
    eq(lay.cards[1].id, y.id, "y first"); eq(lay.cards[1].h, board.CARD_NOTE_H, "taller with a note"); eq(lay.cards[2].y, board.HEAD_H + board.CARD_NOTE_H + board.CARD_GAP, "x under it")
    local col, idx = board.drop_target(lay, 150, 0, x.id); eq(col, 2, "over Doing"); eq(idx, 1, "above z: first")
    col, idx = board.drop_target(lay, 150, 500, x.id); eq(idx, 2, "below z: after it")
    col, idx = board.drop_target(lay, 20, 500, y.id); eq(col, 1, "back in Inbox"); eq(idx, 2, "under x (y itself not counted)")
    col = board.drop_target(lay, 9999, 0, x.id); eq(col, 3, "past the right edge: the last column")
    local f = board.layout(nb, { x0 = 0, y0 = 0, width = 312, height = 600, query = "y" })
    eq(f.cards[2].shown, false, "the filter hides x"); eq(f.cols[1].len, board.CARD_NOTE_H + board.CARD_GAP, "and it takes no room")
end)

print("stash")
local stash = require("lib/stash")
test("stash: a drop is a link, an image, a video, a song, a file or text", function()
    eq(stash.kind_of("https://mooi.example/paper"), 0, "link")
    eq(stash.kind_of("file:///home/me/rose.PNG"), 1, "an image URI, any case")
    eq(stash.kind_of("/home/me/clip.mp4"), 2, "video")
    eq(stash.kind_of("/home/me/song.MP3"), 5, "a song")
    eq(stash.kind_of("/home/me/take.flac"), 5, "a lossless one")
    eq(stash.kind_of("/home/me/voice.opus"), 5, "a voice note")
    eq(stash.kind_of("/home/me/mix.mka"), 5, "a track out of a film")
    eq(stash.kind_of("/home/me/midi.mid"), 5, "a score")
    eq(stash.kind_of("/home/me/notes.txt"), 3, "file")
    eq(stash.kind_of("/home/me/scan.pdf"), 3, "a document is a file")
    eq(stash.kind_of("/home/me/holiday.3gp"), 2, "a phone's film")
    eq(stash.kind_of("/home/me/logo.jxl"), 1, "a newer picture")
    eq(stash.kind_of("a thought"), 4, "text")
    eq(stash.kind_of("  "), 4, "nothing is text")
end)
test("stash: a URI is a path, and a name says what it is", function()
    eq(stash.path_of("file:///home/me/a%20b%2Ec.png"), "/home/me/a b.c.png", "escapes read back")
    eq(stash.path_of(" /home/me/x "), "/home/me/x", "trimmed")
    eq(stash.basename("/home/me/rose.png"), "rose.png", "basename")
    eq(stash.basename("/home/me/rose/"), "rose", "a folder's")
    local n, d = stash.describe("https://www.example.org/paper/one", 0)
    eq(n, "example.org", "a link is its host"); eq(d, "/paper/one", "and its path")
    n, d = stash.describe("/home/me/rose.png", 1); eq(n, "rose.png", "a file is its name"); eq(d, "PNG", "its extension")
    n, d = stash.describe("a thought about tea", 4); eq(n, "a thought about tea", "text is its first line"); eq(d, "TEXT", "and says so")
    n, d = stash.describe("/home/me/song.mp3", 5); eq(n, "song.mp3", "a song is its name"); eq(d, "MP3", "and its kind")
    n, d = stash.describe("/home/me/x", 5); eq(d, "AUDIO", "a song with no extension says what it is")
    eq(stash.extension("/x/a.JPEG"), "jpeg", "extension")
end)
test("stash: files are kept under a safe name", function()
    eq(stash.safe_name("rose.png"), "rose.png", "plain")
    eq(stash.safe_name("../my rose.png"), "_my_rose.png", "slashes and spaces, never hidden")
    eq(stash.safe_name(".hidden"), "hidden", "no hidden file")
    eq(stash.safe_name("a/b\\c;d"), "a_b_c_d", "what a file system dislikes")
    eq(stash.safe_name(""), "item", "never empty")
    eq(stash.safe_name("résumé.png"), "résumé.png", "letters stay")
end)
test("stash: newest first, ids unique, a cap", function()
    local l = {}
    for i = 1, stash.MAX + 5 do l = stash.add(l, { kind = 0, url = "https://x/" .. i }, i) end
    eq(#l, stash.MAX, "capped"); eq(l[1].url, "https://x/" .. (stash.MAX + 5), "newest first")
    local seen = {}
    for _, it in ipairs(l) do eq(seen[it.id], nil, "ids unique"); seen[it.id] = true end
    eq(stash.add(l, { kind = 0, url = "" }, 1), l, "nothing without a url")
end)
test("stash: the same file is one item, and a bump moves it up", function()
    local l = {}
    l, _ = stash.add(l, { kind = 1, name = "a", url = "/stash/a.png", src = "/home/a.png", time = 10 }, 10)
    l, _ = stash.add(l, { kind = 3, name = "b", url = "/stash/b.pdf", src = "/home/b.pdf", time = 20 }, 20)
    eq(stash.find_src(l, "/home/a.png").name, "a", "found by where it came from")
    eq(stash.find_src(l, "/home/nope"), nil, "not there")
    local a = stash.find_src(l, "/home/a.png")
    stash.bump(l, a, 30)
    eq(l[1].name, "a", "moved to the top"); eq(a.time, 30, "its time moved")
    eq(stash.find_url(l, "https://x"), nil, "a url that is not there")
    eq(stash.remove(l, a.id), l, "removed"); eq(stash.find(l, a.id), nil, "gone")
    local _, taken = stash.remove(l, 999); eq(taken, nil, "nothing to remove")
end)
test("stash: a page of rows, and the file read back", function()
    local l = {}
    for i = 1, 8 do l = stash.add(l, { kind = i == 1 and 1 or 0, name = "n" .. i, detail = "LINK", url = (i == 1 and "/stash/a.png" or "https://x/" .. i), time = i }, 100 + i) end
    local rows, page, from, to, total, pages = stash.page(l, 0, 9)
    eq(#rows, stash.ROW_MAX, "a full page"); eq(page, 0, "first"); eq(from, 1, "from the first"); eq(to, 5, "to the fifth")
    eq(total, 8, "all of them"); eq(pages, 2, "two pages"); eq(rows[1].n, 0, "its place")
    eq(rows[1].sub, "LINK · now", "what it is and when"); eq(rows[1].pictured, false, "a link has no picture")
    local r2, p2 = stash.page(l, 9, 9); eq(p2, 1, "a page past the end is the last"); eq(#r2, 3, "the rest")
    eq(r2[3].kind, 1, "the image"); eq(r2[3].pictured, true, "has a picture")
    local rows0, page0, from0, to0, total0, pages0 = stash.page({}, 0, 200)
    eq(#rows0, 0, "empty"); eq(page0, 0, "page"); eq(from0, 0, "from"); eq(to0, 0, "to"); eq(total0, 0, "total"); eq(pages0, 1, "a page even so")
    local back = stash.decode(stash.encode(l))
    eq(#back, 8, "round trip"); eq(back[1].name, "n8", "in order")
    local d = stash.decode({ items = { { id = 2, kind = 1, url = "/stash/x.png" }, { id = 2, kind = 0, url = "https://y" }, { url = "" }, "junk" } })
    eq(#d, 2, "the empty and the junk dropped"); eq(d[1].id ~= d[2].id, true, "a repeated id renumbered")
    eq(type(stash.decode("junk")), "table", "junk is an empty list")
end)
test("stash: how long a song or a film runs", function()
    eq(stash.length(0), "0:00", "nothing")
    eq(stash.length(59), "0:59", "under a minute")
    eq(stash.length(61), "1:01", "a minute in")
    eq(stash.length(221.7), "3:41", "the seconds after the point are dropped")
    eq(stash.length(3721), "1:02:01", "past the hour")
    eq(stash.length(nil), "0:00", "nonsense is a zero")
    eq(stash.length(-4), "0:00", "never backwards")
    local l = {}
    l, _ = stash.add(l, { kind = 5, name = "a.mp3", url = "/stash/a.mp3", time = 1 }, 1)
    eq(l[1].kind, 5, "a song keeps its kind in the list")
    eq(stash.decode(stash.encode(l))[1].kind, 5, "and through the file")
    l, _ = stash.add(l, { kind = 9, url = "/stash/b" }, 2)
    eq(l[1].kind, 4, "a kind nobody knows is text")
end)
test("stash: folders, one level, and what goes where", function()
    local items, folders = {}, {}
    folders, _ = stash.folder_add(folders, "Papers", 1)
    folders, _ = stash.folder_add(folders, "Music", 2)
    eq(#folders, 2, "two folders"); eq(folders[1].name, "Papers", "in the order they were made")
    eq(folders[2].id, 2, "ids of their own")
    eq(stash.folder_label("   "), "FOLDER", "a name that says nothing still names it")
    eq(stash.folder_label(string.rep("x", 40)):sub(-3), "…", "a long name is cut")
    items, _ = stash.add(items, { kind = 0, name = "a", url = "https://a", time = 10 }, 10)
    items, _ = stash.add(items, { kind = 0, name = "b", url = "https://b", time = 11 }, 11)
    items, _ = stash.add(items, { kind = 0, name = "c", url = "https://c", time = 12 }, 12)
    eq(stash.folder_count(items, 0), 3, "everything starts at the root")
    items, moved = stash.move(items, 2, 1)
    eq(moved.folder, 1, "put in a folder")
    eq(stash.folder_count(items, 1), 1, "one there"); eq(stash.folder_count(items, 0), 2, "two at the root")
    eq(#stash.in_folder(items, 1), 1, "the ones in it"); eq(stash.in_folder(items, 1)[1].name, "b", "which")
    eq(#stash.in_folder(items, 0), 2, "and the rest")
    eq(stash.move(items, 99, 1), items, "nothing to move")
    items, _ = stash.move(items, 1, 2)
    eq(stash.folder_count(items, 2), 1, "another folder")
    items, back = stash.move(items, 2, 0); eq(back.folder, nil, "and back to the root")
    local left = #folders
    folders, gone = stash.folder_remove(folders, items, 2)
    eq(#folders, left - 1, "the folder goes"); eq(gone.name, "Music", "the one asked for")
    eq(stash.folder_count(items, 0), 3, "and its items come back to the root")
    local out, fs = stash.decode(stash.encode(items, folders))
    eq(#fs, #folders, "the folders are in the file"); eq(fs[1].name, "Papers", "by name")
    eq(out[1].folder, nil, "an item with no folder stays at the root")
    items, _ = stash.move(items, 3, 1)
    out, fs = stash.decode(stash.encode(items, folders))
    eq(#fs, 1, "one folder written"); eq(stash.in_folder(out, 1)[1].name, "c", "and the item is in it")
    local lost = stash.decode({ items = { { id = 1, url = "/x", folder = 9 } }, folders = {} })
    eq(lost[1].folder, nil, "a folder that is not there sends the item home")
    local full = {}
    for i = 1, stash.FOLDER_MAX + 3 do full = stash.folder_add(full, "f" .. i, i) end
    eq(#full, stash.FOLDER_MAX, "folders are capped"); eq(stash.folder_add(full, "more", 9), full, "and refuse more")
end)
test("stash: the tray walks the folders, and the row says which", function()
    local folders = {}
    folders, _ = stash.folder_add(folders, "Papers", 1)
    folders, _ = stash.folder_add(folders, "Music", 2)
    eq(stash.folder_next(folders, nil), 1, "from the root, the first")
    eq(stash.folder_next(folders, 0), 1, "and the root is the root")
    eq(stash.folder_next(folders, 1), 2, "then the next")
    eq(stash.folder_next(folders, 2), 0, "and home after the last")
    eq(stash.folder_next(folders, 9), 1, "a folder that is gone starts the walk again")
    eq(stash.folder_next({}, 0), 0, "no folders, no walk")
    local items = {}
    items, _ = stash.add(items, { kind = 0, name = "a", detail = "LINK", url = "https://a", time = 10, folder = 2 }, 10)
    local rows = stash.page(items, 0, 10, nil, { [2] = "MUSIC" })
    eq(rows[1].sub, "MUSIC · LINK · now", "its folder, what it is, when")
    local plain = stash.page(items, 0, 10, nil, {})
    eq(plain[1].sub, "LINK · now", "a folder the caller does not know is not invented")
end)
test("stash: how long ago, and a text item's name cut", function()
    eq(stash.ago(100, 100), "now", "now"); eq(stash.ago(160, 100), "1m", "minutes")
    eq(stash.ago(100 + 7200, 100), "2h", "hours");    eq(stash.ago(100 + 172800, 100), "2d", "days")
    eq(stash.ago(100 + 1209600, 100), "14d", "two weeks is still days")
    eq(stash.ago(100 + 2500000, 100), "4w", "weeks")
    local n = stash.describe(string.rep("a", 200), 4)
    eq(#n > 60 and string.sub(n, -3) == "…", true, "a long line is cut and marked")
end)

local desk_lib = require("lib/desk")
print("desk pictures")
test("desk: a file is a picture by its extension, whatever its case", function()
    eq(desk_lib.is_image("a.JPG"), true, "case does not matter")
    eq(desk_lib.is_image("a.webp"), true, "a picture")
    eq(desk_lib.is_image("notes.txt"), false, "not a picture")
    eq(desk_lib.is_image("noext"), false, "no extension")
end)

test("stash: the chips and the search narrow the box without changing the list", function()
    local st = require("lib/stash")
    local list = { { kind = 1, name = "sunset.png", detail = "PNG", url = "/s/sunset.png" },
                   { kind = 0, name = "github.com", detail = "/mooi", url = "https://github.com/mooi" },
                   { kind = 4, name = "remember the milk", detail = "TEXT", url = "remember the milk" },
                   { kind = 2, name = "clip.mp4", detail = "MP4", url = "/s/clip.mp4" } }
    eq(#st.filter(list, 0, ""), 4, "everything")
    eq(#st.filter(list, 1, ""), 2, "pictures and videos")
    eq(st.filter(list, 2, "")[1].name, "github.com", "links")
    eq(#st.filter(list, 0, "MILK"), 1, "search ignores case")
    eq(#st.filter(list, 1, "sun"), 1, "both at once")
    eq(#list, 4, "the list is untouched")
end)

test("notes: a colour, a tick and a search, kept in the file", function()
    local nt = require("lib/notes")
    local list = {}
    list = nt.add(list, "milk", 10); list = nt.add(list, "call mum", 20); list = nt.add(list, "fix the bike", 30)
    local _, tag = nt.tag(list, 1); eq(tag, 1, "first colour")
    for _ = 1, 4 do nt.tag(list, 1) end
    eq(nt.find(list, 1).tag, 0, "round to none")
    local _, done = nt.done(list, 3); eq(done, true, "ticked")
    eq(list[#list].id, 3, "a ticked note sinks below the open ones")
    eq(#nt.filter(list, "CALL"), 1, "search ignores case"); eq(#nt.filter(list, ""), 3, "empty search is every note")
    nt.tag(list, 2)
    local back = nt.decode(nt.encode(list))
    eq(nt.find(back, 2).tag, 1, "the colour is kept"); eq(nt.find(back, 3).done, true, "the tick is kept")
    eq(nt.decode({ notes = { { id = 1, text = "x", tag = 99 } } })[1].tag, 0, "a colour out of range is none")
end)

test("cover art: the URL pleamar 0.4 hands over and the path 0.7 does both draw", function()
    local cover = require("lib/cover")
    eq(cover.path("file:///home/me/My%20Music/c%2B1.jpg"), "/home/me/My Music/c+1.jpg", "0.4: a file URL, unescaped")
    eq(cover.path("/home/me/My Music/c+1.jpg"), "/home/me/My Music/c+1.jpg", "0.7: the path as it is")
    eq(cover.path("https://i.scdn.co/x.jpg"), nil, "on the web: not a file")
    eq(cover.remote("https://i.scdn.co/x.jpg"), true, "and fetched")
    eq(cover.path(""), nil, "nothing"); eq(cover.path(nil), nil, "not a text"); eq(cover.path("file://"), nil, "an empty URL")
end)

local player = require("lib/player")
print("player")
test("lyric_lines gives the lines around now", function()
    local d = player.parse_lrc("[00:01.00]one\n[00:02.00]two\n[00:03.00]three")
    local a, b, c = player.lyric_lines(d, 2.5, 0); eq(a, "one", "prev"); eq(b, "two", "cur"); eq(c, "three", "next")
end)
test("lyric_lines also says which line, so repeated words still move on", function()
    local d = player.parse_lrc("[00:01.00]Hey\n[00:02.00]Hey\n[00:03.00]Ho")
    local _, b1, _, i1 = player.lyric_lines(d, 1.5, 0)
    local _, b2, _, i2 = player.lyric_lines(d, 2.5, 0)
    eq(b1, b2, "same words"); eq(i1 ~= i2, true, "different lines")
end)
test("lyric_lines on nil data gives empty lines", function()
    local a, b, c = player.lyric_lines(nil, 10, 0); eq(a .. b .. c, "", "empty")
end)
local vizbands = require("lib/vizbands")
test("viz: the six styles and off, each with its place for the scene", function()
    eq(table.concat(vizbands.STYLES, ","), "spectrum,mirror,ring,aurora,led,orbit,off", "the set")
    eq(vizbands.index("spectrum"), 0, "first"); eq(vizbands.index("off"), 6, "off last")
    eq(vizbands.index("nonsense"), 1, "an unknown style is mirror")
    eq(vizbands.next("orbit"), "off", "cycles on"); eq(vizbands.next("off"), "spectrum", "and round")
end)
test("viz: the bar's styles map onto the set", function()
    eq(vizbands.from_bar("bars"), "spectrum", "bars"); eq(vizbands.from_bar("mirror"), "mirror", "mirror")
    eq(vizbands.from_bar("dots"), "led", "dots"); eq(vizbands.from_bar("line"), "aurora", "line")
    eq(vizbands.from_bar("off"), "off", "off"); eq(vizbands.from_bar("ring"), "ring", "a set style passes through")
end)
test("library: odd tags still make albums", function()
    local rows = { { albumartist = "", artist = "Björk", album = "Post", date = "1995", file = "a.flac" },
                   { albumartist = "Various Artists", artist = "X", album = "Hits", date = "", file = "b.flac" },
                   { albumartist = "", artist = "", album = "", date = "", file = "c.flac" },
                   { albumartist = "", artist = "Björk", album = "Post", date = "1995", file = "a2.flac" } }
    local al = player.albums(rows)
    eq(#al, 3, "three albums"); eq(al[1].artist, "Björk", "falls back to artist"); eq(al[1].n, 2, "two songs in Post")
    eq(al[2].artist, "Various Artists", "albumartist first")
    eq(al[3].artist, "Unknown artist", "no artist"); eq(al[3].album, "Unknown album", "no album")
    eq(al[1].year, "1995", "year"); eq(al[1].file, "a.flac", "its first song, for the cover")
end)
test("library: sorting by year puts undated last, names ignore case and The", function()
    local s = player.sort({ { year = "" }, { year = "2001" }, { year = "1995" } }, "year")
    eq(s[1].year, "1995", "oldest first"); eq(s[3].year, "", "undated last")
    local n = player.sort({ { artist = "the Zebras" }, { artist = "abba" }, { artist = "Beta" } }, "artist")
    eq(n[1].artist, "abba", "case"); eq(n[3].artist, "the Zebras", "The ignored")
    local e = player.sort({ { album = "" }, { album = "Post" } }, "album")
    eq(e[1].album, "Post", "an empty name sorts last")
    eq(player.song_line({ artist = "", album = "", date = "" }), "No tags", "an untagged song says so")
    eq(player.song_line({ artist = "Björk", album = "Post", date = "1995-06-13" }), "Björk  ·  Post  ·  1995", "the parts it has")
    eq(player.song_line({ artist = "Björk", album = "", date = "" }), "Björk", "only what is there")
end)
test("covers: a cache path per file and size", function()
    eq(player.cover_file("/c", "a/b.flac", 64) ~= player.cover_file("/c", "a/b.flac", 256), true, "sizes differ")
    eq(string.match(player.cover_file("/c", "a/b.flac", 64), "^/c/%x+%-64%.jpg$") ~= nil, true, "shape")
end)
test("covers: generated tones hold contrast in light and dark", function()
    local ferro = require("lib/ferro")
    for _, mode in ipairs({ "dark", "light" }) do
        local roles = ferro.resolve("fixed", { mode = mode }, "auto", false)
        local t = player.cover_tones("Bleed American", roles)
        eq(t.initials, "BA", mode .. " initials")
        assert(ferro.contrast(roles.engrave, t.a) >= 3, mode .. ": initials read on the cover")
    end
    eq(player.cover_tones("", require("lib/ferro").resolve("fixed", nil, "auto", false)).initials, "?", "nameless")
end)
test("covers: a new page replaces the queue", function()
    local q = require("player/library").next_cover_queue({ "old1", "old2" }, { "p1", "p2", "p3" }, { p2 = true })
    eq(#q, 2, "only the page's uncached"); eq(q[1], "p1", "in order"); eq(q[2], "p3", "skips cached")
    local big = {}; for i = 1, 40 do big[i] = "f" .. i end
    eq(#require("player/library").next_cover_queue({}, big, {}), 24, "at most 24")
end)
test("views: the file's audio format reads as rate, bits, channels", function()
    local a = player.audio_from_ffmpeg("  Stream #0:0: Audio: flac, 44100 Hz, stereo, s16\n")
    eq(a.rate, 44100, "rate"); eq(a.bits, 16, "bits"); eq(a.channels, 2, "ch")
    eq(player.audio_from_ffmpeg("Stream #0:0: Audio: mp3, 48000 Hz, mono, fltp, 320 kb/s").bits, 32, "float")
    eq(player.audio_from_ffmpeg("Stream #0:0: Audio: flac, 96000 Hz, stereo, s32 (24 bit)").bits, 24, "24 in 32")
    eq(player.audio_from_ffmpeg("no audio here"), nil, "none")
    eq(player.audio_line(a, "FLAC"), "FLAC · 44.1 kHz · 16 bit · stereo", "the rack's line")
    eq(player.audio_line(nil, "MP3"), "MP3", "only the format when mpd says nothing")
end)
test("views: cue goes to the last seek, else the start", function()
    eq(player.cue_point(42, 90), 42, "last seek"); eq(player.cue_point(nil, 90), 0, "none"); eq(player.cue_point(120, 90), 0, "seek after now")
end)
test("lyrics: an offset moves the sung line", function()
    local l = player.parse_lrc("[00:10.00]one\n[00:20.00]two")
    eq(player.lyric_at(l, 19), 1, "no offset, as before")
    eq(player.lyric_at(l, 19, 0), 1, "before the offset"); eq(player.lyric_at(l, 19, 1.5), 2, "1.5 s early")
    eq(player.lyric_at(l, 21, -2), 1, "late lyrics wait")
    eq(player.clamp_offset(12.3), 10, "capped"); eq(player.clamp_offset(0.74), 0.5, "steps of 0.5"); eq(player.clamp_offset(-0.26), -0.5, "and back")
end)
local eqpreset = require("lib/eqpreset")
test("eq: ten bands round-trip through the EasyEffects document", function()
    local doc = eqpreset.easyeffects(eqpreset.PRESETS.rock, -2)
    local e = doc.output.equalizer
    eq(e["num-bands"], 10, "ten bands"); eq(e["input-gain"], -2, "the preamp"); eq(e.left.band3.frequency, 250, "frequencies")
    eq(e.right.band9.gain, eqpreset.PRESETS.rock[10], "both channels"); eq(doc.output.plugins_order[1], "equalizer", "the plugin")
    local back = eqpreset.bands_from(doc)
    for i = 1, 10 do eq(back[i], eqpreset.PRESETS.rock[i], "band " .. i) end
    eq(eqpreset.bands_from({}), nil, "not a preset")
end)
test("eq: the rack's knobs move their bands", function()
    local b = eqpreset.from_knob(eqpreset.PRESETS.flat, 1, 6)
    local lo = eqpreset.knobs(b); eq(lo, 6, "low knob"); eq(b[4], 0, "mid untouched")
    eq(eqpreset.from_knob(b, 1, 30)[1], 12, "clamped")
    local _, mid, hi = eqpreset.knobs(eqpreset.from_knob(eqpreset.PRESETS.flat, 3, -4))
    eq(mid, 0, "mid"); eq(hi, -4, "high knob")
end)
test("eq: the preset that was loaded before mooi's, to give back on off", function()
    eq(eqpreset.last_output("input: mic\noutput: live_eq\n"), "live_eq", "read from -s")
    eq(eqpreset.last_output("output: mooi\n"), nil, "mooi's own is not the user's")
    eq(eqpreset.last_output("output: mooi-night\n"), nil, "nor one saved from here")
    eq(eqpreset.last_output(""), nil, "none")
end)
test("eq: every preset has ten bands within ±12 dB", function()
    local n = 0
    for name, p in pairs(eqpreset.PRESETS) do
        n = n + 1
        eq(#p, 10, name); for _, v in ipairs(p) do assert(v >= -12 and v <= 12, name) end
    end
    eq(n, 7, "seven presets"); eq(#eqpreset.ORDER, 7, "in an order for the chips")
end)
test("video: the search names the song", function()
    eq(player.video_query("Jimmy Eat World", "The Middle"), "ytsearch1:Jimmy Eat World - The Middle official video", "query")
    eq(player.video_query("", "The Middle"), "ytsearch1:The Middle official video", "no artist, the title alone")
    eq(player.video_query("X", ""), nil, "no title, no search")
end)
test("video: offered only for mpd songs with a title", function()
    local ok, why = player.video_allowed("remote", { title = "a" }); eq(ok, false, "remote"); eq(why ~= "", true, "says why")
    eq((player.video_allowed("library", { title = "a" })), true, "mpd song")
    local ok2, why2 = player.video_allowed("library", nil); eq(ok2, false, "nothing playing"); eq(why2 ~= "", true, "says why")
end)
test("video: yt-dlp's progress lines read as a percentage, and a cache file per song", function()
    eq(player.video_progress("[download]  42.7% of   38.10MiB at    2.11MiB/s ETA 00:10"), 42.7, "progress")
    eq(player.video_progress("[download] 100% of   38.10MiB in 00:00:12"), 100, "done")
    eq(player.video_progress("[youtube] Extracting URL"), nil, "not progress")
    local f = player.video_file("/c", "Jimmy Eat World", "The Middle")
    eq(string.match(f, "^/c/%x+%.mp4$") ~= nil, true, "shape"); eq(f == player.video_file("/c", "Jimmy Eat World", "The Middle"), true, "stable")
end)
test("video: mpd resumes where the video reached", function()
    eq(player.resume_at(65.2, 243), 65.2, "inside"); eq(player.resume_at(300, 243), 0, "past the end"); eq(player.resume_at(-1, 243), 0, "nonsense")
end)
test("review: an album's tracks in track order, the path breaking ties", function()
    local f = table.concat(player.LIB_FIELDS, ","); eq(string.find(f, "track", 1, true) ~= nil, true, "listall reads the track")
    local t = player.album_tracks({ { track = "10", file = "a/10.flac" }, { track = "2/12", file = "a/02.flac" }, { track = "", file = "a/zz.flac" },
                                     { track = "", file = "a/aa.flac" }, { track = "1", file = "a/01.flac" } })
    eq(t[1].file, "a/01.flac", "1"); eq(t[2].file, "a/02.flac", "2 of 12"); eq(t[3].file, "a/10.flac", "10")
    eq(t[4].file, "a/aa.flac", "untracked by path"); eq(t[5].file, "a/zz.flac", "then the next path")
end)
test("review: a preset handed out is a copy", function()
    local b = eqpreset.preset("flat"); b[1] = 6
    eq(eqpreset.PRESETS.flat[1], 0, "Flat itself untouched"); eq(eqpreset.preset("nope"), nil, "unknown")
end)
test("review: an artist's or a genre's row plays its songs", function()
    local lib = require("player/library")
    local all = { { albumartist = "", artist = "Björk", genre = "Pop", file = "1" }, { albumartist = "Björk", artist = "x", genre = "", file = "2" },
                  { albumartist = "", artist = "Other", genre = "Pop", file = "3" } }
    eq(table.concat(lib.files_for(all, "artists", "Björk"), ","), "1,2", "the artist's")
    eq(table.concat(lib.files_for(all, "genres", "Pop"), ","), "1,3", "the genre's")
    eq(table.concat(lib.files_for(all, "genres", "No genre"), ","), "2", "the ungenred")
end)
test("review: initials keep a whole letter, whatever the alphabet", function()
    local roles = require("lib/ferro").resolve("fixed", nil, "auto", false)
    eq(player.cover_tones("Ágætis byrjun", roles).initials, "ÁB", "accented first letter whole")
    eq(player.cover_tones("東京 事変", roles).initials, "東事", "not a lone byte")
end)
test("corners: one setting for every shape — its style and how big", function()
    local st = require("lib/style")
    local k, sc = st.corners(config.defaults())
    eq(k, 0, "chamfer by default (Ferrolume's cut)"); eq(sc, 1, "at the designed size")
    k, sc = st.corners({ look = { corners = "round", corner_size = 24 } }); eq(k, 2, "rounded"); eq(sc, 2, "twice the size")
    k, sc = st.corners({ look = { corners = "square", corner_size = 6 } }); eq(k, 3, "square"); eq(sc, 0, "square has none")
    k = st.corners({ look = { corners = "bevel", corner_size = 12 } }); eq(k, 1, "bevel")
    k, sc = st.corners({}); eq(k, 0, "missing → chamfer"); eq(sc, 1, "missing → designed size")
    eq(config.defaults().look.corners, "chamfer", "schema default"); eq(config.defaults().look.corner_size, 12, "schema size")
end)
test("sizes: escape steps back one size", function()
    eq(player.size_after("full", "escape"), "panel", "full → panel")
    eq(player.size_after("panel", "escape"), nil, "panel → closed")
    eq(player.size_after("mini", "escape"), nil, "mini → closed")
end)
test("sizes: the mini card grows, and closes on a press outside", function()
    eq(player.size_after("mini", "grow"), "panel", "OPEN PLAYER")
    eq(player.size_after("mini", "outside"), nil, "outside the card")
    eq(player.size_after("panel", "full"), "full", "FULL"); eq(player.size_after("full", "full"), "panel", "FULL again")
end)
test("sizes: the bar's press closes from every size", function()
    for _, s in ipairs({ "mini", "panel", "full" }) do eq(player.size_after(s, "bar"), nil, s) end
end)
test("player: mpc's status line, and none when mpd is not there", function()
    local st = player.parse_status("playing\t1:05\t3:13\t 72%\ton\toff\toff\toff\t4\t12")
    eq(st.state, "playing", "state"); eq(st.elapsed, 65, "elapsed"); eq(st.total, 193, "total"); eq(st.volume, 72, "volume")
    eq(st.random, true, "random"); eq(st["repeat"], false, "repeat"); eq(st.pos, 4, "song"); eq(st.length, 12, "queue")
    eq(player.parse_status("stopped\t0:00\t0:00\t -1%\toff\toff\toff\toff\t0\t0").volume, -1, "no mixer")
    eq(player.parse_status("error: Connection refused"), nil, "mpd down")
    eq(player.seconds("1:02:03"), 3723, "hours"); eq(player.clock(3723), "1:02:03", "clock"); eq(player.clock(65), "1:05", "minutes")
end)
test("player: songs from mpc rows, named even without tags, and the names lists", function()
    local out = "a/b/Song One.flac\tThe Artist\t\tAlbum\tOne\t1\t2014\t3:13\t0\nUntagged File.mp3\t\tAlbum Man\t\t\t\t\t0:45\t1\n"
    local list = player.parse_songs(out)
    eq(#list, 2, "two"); eq(list[1].title, "One", "title"); eq(list[1].seconds, 193, "time")
    eq(list[2].title, "Untagged File", "file name for a title"); eq(list[2].artist, "Album Man", "album artist for an artist")
    local names = player.parse_names("The Zebras\nabba\n\nBeta\nabba\n")
    eq(table.concat(names, ","), "abba,Beta,The Zebras", "sorted, de-duplicated, The ignored")
    eq(player.path("/home/u/Music", "x/y.flac"), "/home/u/Music/x/y.flac", "path")
    eq(player.music_dir('music_directory "~/Music"\n', "/home/u"), "/home/u/Music", "music dir")
end)
test("player: the tonearm sets down at the edge and travels in; dragged, it seeks", function()
    eq(player.arm(0, "stopped"), player.ARM_REST, "parked")
    eq(player.arm(0, "playing"), player.ARM_START, "the outer groove"); eq(player.arm(1, "paused"), player.ARM_END, "the label")
    eq(player.arm_fraction(30), 0.5, "half way"); eq(player.arm_fraction(99), 1, "clamped")
end)
test("player: LRC lyrics — stamps, several to a line, an offset, tags and plain text", function()
    local l = player.parse_lrc("[ar:Someone]\n[offset:+500]\n[00:10.50]Second\n[00:01.00][00:20.00]Again\nnot timed\n")
    eq(l.synced, true, "synced"); eq(#l.lines, 3, "three timed lines, tags dropped")
    eq(l.lines[1].text, "Again", "sorted by time"); eq(l.lines[1].t, 0.5, "offset applied"); eq(l.lines[2].t, 10, "second")
    eq(player.lyric_at(l, 11), 2, "the line being sung"); eq(player.lyric_at(l, 0.1), 0, "before the first")
    local p = player.parse_lrc("one\ntwo\n")
    eq(p.synced, false, "plain"); eq(#p.lines, 2, "plain lines")
end)
test("player: LRCLIB's address and answer", function()
    local u = player.lrclib_url("Lynyrd Skynyrd", "Free Bird", "(Pronounced)", 550.4)
    eq(u:find("artist_name=Lynyrd%20Skynyrd", 1, true) ~= nil, true, "encoded artist")
    eq(u:find("duration=550", 1, true) ~= nil, true, "duration")
    eq(player.from_lrclib({ syncedLyrics = "[00:01.00]Hi" }).synced, true, "synced preferred")
    eq(player.from_lrclib({ plainLyrics = "Hi" }).synced, false, "plain")
    eq(player.from_lrclib({ instrumental = true }).instrumental, true, "instrumental")
    eq(player.from_lrclib({}), nil, "nothing")
    eq(player.lrc_beside("/m/a.flac"), "/m/a.lrc", "beside")
end)

local desk = require("lib/desk")
print("desk")
test("desk: the settings are read whatever the file holds", function()
    local d = desk.normalize(nil)
    eq(d.on, false, "off by default"); eq(d.parallax, "workspaces", "parallax"); eq(d.cutout, true, "cutout"); eq(d.depth, true, "depth")
    d = desk.normalize({ on = true, parallax = "sideways", strength = 900 })
    eq(d.on, true, "on"); eq(d.parallax, "workspaces", "unknown parallax"); eq(d.strength, 100, "clamped")
end)
test("desk: the workspace row is at least four long and reaches the highest in use", function()
    eq(desk.workspace_fraction(1, {}), 0, "first"); eq(desk.workspace_fraction(4, {}), 1, "fourth of four")
    eq(desk.workspace_fraction(2, { 1, 2, 9 }), 1 / 8, "one step of nine")
    eq(desk.workspace_fraction(9, { 1, 2 }), 1, "the active one is the end")
end)
test("desk: the cutout and the plate belong to the picture they were made from", function()
    local st = { still = "/w.png", cutout = "/c.png", plate = "/p.png" }
    local l = desk.layers(st, "/w.png", { parallax = "both" })
    eq(l.wall, "/p.png", "the plate behind a floating subject"); eq(l.cut, "/c.png", "the subject"); eq(l.floats, true, "floats")
    l = desk.layers(st, "/other.png", {})
    eq(l.wall, "/other.png", "another wallpaper is drawn alone"); eq(l.cut, "", "no stale subject")
    l = desk.layers(st, "/w.png", { depth = false })
    eq(l.wall, "/w.png", "flat: the still itself"); eq(l.floats, false, "no float")
    l = desk.layers(st, "/w.png", { parallax = "off" })
    eq(l.wall, "/w.png", "no parallax, no plate needed"); eq(l.cut, "/c.png", "still over the widgets")
    eq(desk.layers(st, "/w.png", { cutout = false }).cut, "", "cutout off")
end)

local updates = require("lib/updates")
test("updates: counts checkupdates, the AUR helper and Flatpak, skipping noise", function()
    local repo = "btrfs-progs 7.1-1 -> 7.3-1\nfooyin 0.14.0-1 -> 0.14.1-1\n\n"
    local aur = "claude-code 2.1.310-1 -> 2.1.311-1\nold-thing 1-1 -> 2-1 [ignored]\n:: Looking for devel upgrades...\n"
    local flat = "com.stremio.Stremio\nio.github.peazip.PeaZip\n"
    eq(updates.count_pkgs(repo), 2, "repo"); eq(updates.count_pkgs(aur), 1, "aur, without the ignored one")
    eq(updates.count_apps(flat), 2, "flatpak"); eq(updates.count_pkgs(nil), 0, "nothing came")
    eq(updates.count_apps("Application ID\n"), 0, "a header is not an update")
end)
test("updates: what the module says", function()
    local s = updates.summary(9, 2, 1)
    eq(s.total, 12); eq(s.text, "12 updates · 9 packages · 2 AUR · 1 Flatpak")
    eq(updates.summary(1, 0, 0).text, "1 update · 1 package")
    eq(updates.summary(0, 0, 0).text, "Up to date")
end)
test("updates: a notice only when more arrived", function()
    eq(updates.should_notify(0, 5), true); eq(updates.should_notify(5, 5), false)
    eq(updates.should_notify(5, 2), false); eq(updates.should_notify(3, 7), true)
    eq(updates.should_notify(nil, 4), false, "the first check after starting is not news")
end)
test("updates: the updater runs the AUR helper there is, then Flatpak, and waits", function()
    local c = updates.command({ paru = true, yay = true, flatpak = true })
    assert(c:find("paru %-Syu"), "paru first"); assert(c:find("flatpak update"), "then flatpak")
    assert(c:find("read"), "waits for Enter before closing")
    assert(updates.command({ yay = true }):find("yay %-Syu"))
    assert(updates.command({}):find("sudo pacman %-Syu"), "no helper: pacman")
    assert(not updates.command({ paru = true }):find("flatpak"), "no flatpak: not run")
end)

local calendar = require("lib/calendar")
test("calendar: a month is six weeks from Monday, its own days marked", function()
    local m = calendar.month(2026, 10, { y = 2026, m = 10, d = 27 })
    eq(#m.cells, 42, "six rows of seven")
    -- 1 October 2026 is a Thursday: three days of September first
    eq(m.cells[1].day, 28, "Mon 28 Sep"); eq(m.cells[1].cur, false)
    eq(m.cells[4].day, 1, "Thu 1 Oct"); eq(m.cells[4].cur, true)
    eq(m.cells[30].day, 27, "the 27th"); eq(m.cells[30].today, true)
    eq(m.cells[34].day, 31); eq(m.cells[35].cur, false, "November after")
    eq(m.title, "October 2026")
    eq(m.cells[6].weekend, true, "Saturday"); eq(m.cells[5].weekend, false)
end)
test("calendar: leap years, year ends, and today only in its own month", function()
    eq(calendar.days_in(2024, 2), 29); eq(calendar.days_in(2025, 2), 28); eq(calendar.days_in(2000, 2), 29); eq(calendar.days_in(1900, 2), 28)
    local y, m = calendar.shift(2026, 12, 1); eq(y, 2027); eq(m, 1)
    y, m = calendar.shift(2026, 1, -1); eq(y, 2025); eq(m, 12)
    y, m = calendar.shift(2026, 3, -14); eq(y, 2025); eq(m, 1)
    local n = calendar.month(2026, 11, { y = 2026, m = 10, d = 27 })
    for _, c in ipairs(n.cells) do assert(not c.today, "no today in another month") end
    local f = calendar.month(2021, 2, nil)   -- February 2021 starts on a Monday
    eq(f.cells[1].day, 1); eq(f.cells[1].cur, true)
end)
test("calendar: ISO weeks", function()
    eq(calendar.iso_week(2026, 10, 27), 44); eq(calendar.iso_week(2021, 1, 3), 53, "3 Jan 2021 is in 2020's last week")
    eq(calendar.iso_week(2026, 1, 1), 1); eq(calendar.iso_week(2024, 12, 30), 1, "30 Dec 2024 is week 1 of 2025")
end)

local stats = require("lib/stats")
test("stats: load, memory and swap from /proc", function()
    local l1, l5 = stats.loadavg("2.36 2.16 2.27 4/1771 2332564\n"); eq(l1, 2.36); eq(l5, 2.16)
    eq(stats.loadavg("garbage"), nil, "unreadable")
    local m = stats.meminfo("MemTotal:       15725400 kB\nMemFree: 1 kB\nMemAvailable:    8908912 kB\nSwapTotal:      16250872 kB\nSwapFree:       12060296 kB\n")
    eq(string.format("%.1f", m.total), "15.0", "GiB total"); eq(string.format("%.1f", m.used), "6.5", "used = total - available")
    eq(string.format("%.2f", m.frac), "0.43"); eq(string.format("%.1f", m.swap_used), "4.0")
    eq(stats.meminfo("").frac, 0, "nothing read: zero, not an error")
end)
test("stats: the root disk, the busiest processes, the GPU", function()
    local d = stats.df("Filesystem     1024-blocks      Used Available Capacity Mounted on\n/dev/nvme0n1p2   498008372 362954444 131383828      74% /\n")
    eq(d.frac, 0.74); eq(d.text, "346 / 475 GiB")
    eq(stats.df("nonsense").frac, 0)
    local t = stats.top("ps               100\nzsh             33.3\nstacer          16.0\npleamar          6.9\n", 3)
    eq(#t, 3); eq(t[1].name, "zsh", "ps itself is left out"); eq(t[1].cpu, 33.3); eq(t[3].name, "pleamar")
    eq(#stats.top("", 3), 0)
    eq(stats.gpu("30\n"), 0.30); eq(stats.gpu("cat: no such file\n"), nil)
end)

local forecast = require("lib/forecast")
local function meteo()
    local hours, temps, codes, days = {}, {}, {}, {}
    for h = 0, 47 do
        local d = h < 24 and "2026-10-27" or "2026-10-28"
        hours[#hours + 1] = string.format("%sT%02d:00", d, h % 24); temps[#temps + 1] = 10 + h * 0.5; codes[#codes + 1] = (h % 2 == 0) and 0 or 61; days[#days + 1] = (h % 24 >= 7 and h % 24 < 19) and 1 or 0
    end
    return { current = { time = "2026-10-27T20:15", temperature_2m = 19.4, apparent_temperature = 18.1, relative_humidity_2m = 71,
                         wind_speed_10m = 12.6, weather_code = 3, is_day = 0 },
             hourly = { time = hours, temperature_2m = temps, weather_code = codes, is_day = days },
             daily = { time = { "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01" },
                       weather_code = { 3, 61, 0, 2, 95, 71 }, temperature_2m_max = { 21.2, 17.8, 19, 20, 15, 9 },
                       temperature_2m_min = { 12.1, 10, 9, 11, 8, 2 } } }
end
test("forecast: now, the next six hours, five days", function()
    local f = forecast.parse(meteo())
    eq(f.now.temp, 19.4); eq(f.now.feels, 18.1); eq(f.now.humidity, 71); eq(f.now.wind, 12.6); eq(f.now.code, 3); eq(f.now.day, 0)
    eq(f.today.hi, 21.2); eq(f.today.lo, 12.1)
    eq(#f.hours, 6); eq(f.hours[1].label, "21", "the hour after now"); eq(f.hours[4].label, "00", "across midnight")
    eq(f.hours[1].temp, 20.5); eq(f.hours[1].code, 61)
    eq(#f.days, 5); eq(f.days[1].label, "Today"); eq(f.days[2].label, "Wed"); eq(f.days[5].label, "Sat"); eq(f.days[5].code, 95)
end)
test("forecast: a broken or partial answer is nothing, not a crash", function()
    eq(forecast.parse(nil), nil); eq(forecast.parse({}), nil); eq(forecast.parse({ current = "x" }), nil)
    local t = meteo(); t.hourly = nil; t.daily = { time = "oops" }
    local f = forecast.parse(t)
    eq(f.now.temp, 19.4, "now still reads"); eq(#f.hours, 0); eq(#f.days, 0)
end)

local weathercache = require("lib/weathercache")
test("weather cache: only a parseable forecast with a sane timestamp is fresh", function()
    local valid = { at = 1000, answer = meteo(), city = "Springfield" }
    eq(weathercache.fresh(valid, 1599, 600), true, "inside TTL")
    eq(weathercache.fresh(valid, 1600, 600), false, "at TTL boundary")
    eq(weathercache.fresh(valid, 999, 600), false, "future timestamp")
    eq(weathercache.fresh({ at = 1000 }, 1100, 600), false, "missing answer")
    eq(weathercache.fresh({ at = 1000, answer = {} }, 1100, 600), false, "unparseable answer")
    eq(weathercache.fresh({ at = "bad", answer = meteo() }, 1100, 600), false, "invalid timestamp")
    eq(weathercache.fresh({ at = 1000, answer = meteo() }, 1100, 0), false, "invalid TTL")
    eq(weathercache.fresh(nil, 1100, 600), false, "missing cache")
end)
test("weather cache: coordinates are parsed and bounded before URL construction", function()
    local lat, lon = weathercache.coordinates({ loc = "39.7817,-89.6501" })
    eq(lat, 41.1189, "latitude"); eq(lon, 1.2445, "longitude")
    eq(select(1, weathercache.coordinates({ loc = "90,-180" })), 90, "valid lower longitude")
    eq(weathercache.coordinates({ loc = "91,0" }), nil, "latitude out of range")
    eq(weathercache.coordinates({ loc = "0,181" }), nil, "longitude out of range")
    eq(weathercache.coordinates({ loc = "nan,0" }), nil, "non-number")
    eq(weathercache.coordinates({ loc = "41.1;os.execute('bad'),1" }), nil, "injected text")
    eq(weathercache.coordinates({ loc = "41,1,2" }), nil, "extra coordinate")
    eq(weathercache.coordinates(nil), nil, "missing location")
end)

test("stats: upower's battery — state, time left, rate, health", function()
    local b = stats.upower("  native-path:          BAT1\n    state:               discharging\n    energy-rate:         7,412 W\n    percentage:          64%\n    capacity:            81,725%\n    time to empty:       3,2 hours\n")
    eq(b.state, "discharging"); eq(b.rate, "7.4 W"); eq(b.health, 82); eq(b.time, "3 h 12 min left")
    local c = stats.upower("    state:               charging\n    time to full:        45,0 minutes\n    energy-rate:         20.1 W\n")
    eq(c.time, "45 min to full"); eq(c.rate, "20.1 W")
    local f = stats.upower("    state:               fully-charged\n    energy-rate:         0 W\n")
    eq(f.time, ""); eq(f.rate, ""); eq(f.state, "fully-charged")
    eq(stats.upower("").state, "unknown")
end)

local nexusfeed = require("lib/nexusfeed")
test("nexus feed: the latest five, how long ago, never the bodies", function()
    local list = {}
    for i = 1, 7 do list[i] = { id = i, app = "App" .. i, title = "Title " .. i, body = "secret", time = 1000 - i * 90 } end
    local f = nexusfeed.feed(list, 1000, false)
    eq(f.count, 7); eq(#f.items, 5); eq(f.items[1].app, "App1"); eq(f.items[1].title, "Title 1")
    eq(f.items[1].ago, "1 min"); eq(f.items[5].ago, "7 min")
    for _, it in ipairs(f.items) do eq(it.body, nil, "no body leaves the bar") end
    local p = nexusfeed.feed(list, 1000, true)
    eq(p.items[1].title, "", "private: who it is from, not what it says")
    eq(nexusfeed.feed(nil, 1000, false).count, 0)
end)
test("nexus feed: ages, and the updates document", function()
    eq(nexusfeed.ago(30), "now"); eq(nexusfeed.ago(600), "10 min"); eq(nexusfeed.ago(7200), "2 h"); eq(nexusfeed.ago(200000), "2 d")
    eq(nexusfeed.ago(-5), "now", "a clock that drifted")
    local u = nexusfeed.updates_doc(48, "48 updates · 26 packages", 1234)
    eq(u.total, 48); eq(u.text, "48 updates · 26 packages"); eq(u.at, 1234)
end)

local deck = require("lib/nexusdeck")
test("nexus deck: cards in a row along the top or the bottom, filling the deck, gaps between them", function()
    for _, e in ipairs({ "bottom", "top" }) do
        local d = deck.layout(e, 1920, 1080, 52, { tiles = 3, hidden = deck.clean_hidden(nil, false) })
        eq(d.vertical, false); eq(d.x, (1920 - d.w) / 2, "centred")
        eq(d.parts[1].x, deck.PAD); eq(d.parts[1].y, deck.RAIL)
        local last = d.parts[#d.parts]
        eq(last.x + last.w, d.w - deck.PAD, "the last card meets the far side")
        for i = 2, #d.parts do eq(d.parts[i].x, d.parts[i - 1].x + d.parts[i - 1].w + deck.CARD_GAP, "card " .. i .. " a gap after the one before") end
        eq(d.h, deck.RAIL + deck.ROW + deck.PAD)
        eq(#d.dropped, 0, "the first deck fits a 1920 px screen whole")
        assert(d.bays.spaces.w >= 300, "with room for the workspaces")
    end
    eq(deck.layout("bottom", 1920, 1080, 52).y, 1080 - (deck.RAIL + deck.ROW + deck.PAD) - deck.GAP, "on the bottom edge")
    eq(deck.layout("top", 1920, 1080, 52).y, 58, "under the bar")
end)
test("nexus deck: two rows hold more, every card movable, the least kept giving way when there is no room", function()
    local one = deck.layout("bottom", 1920, 1080, 0, { hidden = {} })
    assert(#one.dropped > 0, "one row cannot hold every part")
    local two = deck.layout("bottom", 1920, 1080, 0, { hidden = {}, rows = 2 })
    assert(#two.dropped < #one.dropped, "two rows hold more")
    eq(two.h, deck.RAIL + 2 * deck.ROW + deck.CARD_GAP + deck.PAD)
    local seen = { false, false }
    for _, p in ipairs(two.parts) do seen[p.row] = true end
    assert(seen[1] and seen[2], "cards in both rows")
    -- two rows even when one would hold them: the cards split over them, half the width each
    local four, only = { "music", "machine", "today", "activity" }, {}
    for _, id in ipairs(deck.ORDER) do only[id] = true end
    for _, id in ipairs(four) do only[id] = nil end
    local flat = deck.layout("bottom", 1920, 1080, 0, { hidden = only })
    local split = deck.layout("bottom", 1920, 1080, 0, { hidden = only, rows = 2 })
    local r2 = 0
    for _, p in ipairs(split.parts) do if p.row == 2 then r2 = r2 + 1 end end
    eq(#split.parts, 4, "no card lost to the second row"); eq(r2, 2, "two cards in each row")
    eq(#flat.parts, 4, "one row holds four"); eq(split.h > flat.h, true, "two rows are taller")
    local mine = deck.layout("bottom", 1920, 1080, 0, { parts = { "scenes", "music" }, hidden = {} })
    eq(mine.parts[1].id, "scenes", "scenes move like anything else"); eq(mine.parts[2].id, "music")
    local big = deck.layout("bottom", 1920, 1080, 0, { parts = { "profile" }, hidden = {}, large = true })
    eq(big.bays.profile.w >= deck.PARTS.profile.wl, true, "the large profile")
    eq(deck.clean_hidden(nil, false).mixer, true, "a first deck keeps some parts on the shelf")
    eq(deck.clean_hidden({}, true).mixer, nil, "a saved choice is the choice")
end)
test("nexus deck: a part's order cleaned, moved, and placed where it is let go, row by row", function()
    local o = deck.clean_parts({ "music", "bogus", "music", "window" })
    eq(o[1], "music"); eq(o[2], "window"); eq(#o, #deck.ORDER, "every part, once")
    local m = deck.move(deck.ORDER, "today", 1, {})
    eq(m[1], "today"); eq(#m, #deck.ORDER)
    local h = deck.move(deck.ORDER, "window", 99, { music = true })
    eq(h[#h], "music", "a hidden part keeps out of the way")
    local d = deck.layout("bottom", 1920, 1080, 0, { tiles = 2, hidden = deck.clean_hidden(nil, false) })
    eq(deck.place_at(d, -5, 100), 1, "before everything")
    eq(deck.place_at(d, d.parts[1].x + d.parts[1].w / 2 + 1, 100), 2, "past the first's middle")
    eq(deck.place_at(d, d.w + 50, 100), #d.parts + 1, "after everything")
    local two = deck.layout("bottom", 1920, 1080, 0, { hidden = {}, rows = 2 })
    local first_in_two = 0
    for i, p in ipairs(two.parts) do if p.row == 2 and first_in_two == 0 then first_in_two = i end end
    eq(deck.place_at(two, 0, deck.RAIL + deck.ROW + 40), first_in_two, "the start of the second row")
end)
test("nexus deck: cards resized small, medium or large, the deck packing round them", function()
    local roomy = deck.clean_hidden(nil, false); roomy.window = true
    local base = deck.layout("bottom", 1920, 1080, 0, { hidden = roomy })
    local big = deck.layout("bottom", 1920, 1080, 0, { hidden = roomy, sizes = { music = "l" } })
    local tight = deck.layout("bottom", 1920, 1080, 0, { hidden = deck.clean_hidden(nil, false), sizes = { music = "l" } })
    eq(tight.dropped[1], "music", "no room for it large in a full row: it gives way, as any card would")
    assert(big.bays.music.w > base.bays.music.w, "a large card is wider")
    local first = deck.layout("bottom", 1920, 1080, 0, { hidden = deck.clean_hidden(nil, false) })
    local small = deck.layout("bottom", 1920, 1080, 0, { hidden = deck.clean_hidden(nil, false), sizes = { quick = "s" } })
    assert(small.bays.quick.w < first.bays.quick.w, "a small one narrower")
    assert(small.bays.spaces.w > first.bays.spaces.w, "and the workspaces take the room it gave")
    local s = deck.clean_sizes({ "music_l", "bogus_l", "quick_x", "today_s" })
    eq(s.music, "l"); eq(s.today, "s"); eq(s.bogus, nil); eq(s.quick, nil)
    eq(deck.sizes_list({ music = "l", quick = "m" })[1], "music_l"); eq(#deck.sizes_list({ quick = "m" }), 0)
    eq(deck.next_size("l"), "s"); eq(deck.next_size(nil), "l")
end)
test("nexus deck: the circuit wires every card to the bus and neighbours to each other", function()
    local d = deck.layout("bottom", 1920, 1080, 0, { hidden = deck.clean_hidden(nil, false) })
    local nodes, traces = deck.circuit(d)
    eq(#nodes, #d.parts); eq(#traces, 3 * (#d.parts - 1), "three segments between each pair in a row")
    eq(nodes[1].by, deck.RAIL - 7)
end)
test("nexus deck: a column down either side, its cards stacked, against the screen's edge", function()
    local l = deck.layout("left", 1920, 1080, 52, { hidden = deck.clean_hidden(nil, false) })
    eq(l.vertical, true); eq(l.x, deck.GAP); eq(l.y, 58); eq(l.out_x, -1)
    eq(l.parts[1].y, deck.RAIL)
    for i = 2, #l.parts do eq(l.parts[i].y, l.parts[i - 1].y + l.parts[i - 1].h + deck.CARD_GAP) end
    assert(l.h <= 1080 - 58 - deck.GAP, "never past the screen")
    assert(#deck.layout("left", 1920, 1080, 52, { hidden = {}, tiles = 6 }).dropped > 0, "every part with many workspaces gives way down a side")
    eq(deck.layout("right", 1920, 1080, 52, {}).x, 1920 - deck.COLUMN_W - deck.GAP, "against the right edge")
    -- two rows down a side are two columns: twice as wide, half as tall, the spine still clear
    local one = deck.layout("right", 1920, 1080, 52, { hidden = {} })
    local two = deck.layout("right", 1920, 1080, 52, { hidden = {}, rows = 2 })
    eq(two.w, 2 * (deck.COLUMN_W - 2 * deck.PAD) + deck.CARD_GAP + 2 * deck.PAD, "two columns wide")
    eq(two.x, 1920 - two.w - deck.GAP, "both columns against the right edge")
    assert(#two.dropped < #one.dropped, "two columns hold more")
    local cols, bottom = {}, 0
    for _, p in ipairs(two.parts) do
        cols[p.row] = true; eq(p.w, deck.COLUMN_W - 2 * deck.PAD, "a card one column wide")
        bottom = math.max(bottom, p.y + p.h)
    end
    assert(cols[1] and cols[2], "cards in both columns")
    assert(bottom + deck.PAD <= two.h, "both columns within the deck")
    eq(deck.place_at(two, deck.PAD + 4, two.parts[1].y + 2), 1, "let go at the top of the first column: first")
end)
test("nexus deck: the cut in two taken where both sides fit, so no card gives way for nothing", function()
    eq(deck.split(4, function() return true end), 2, "a middle cut when any will do")
    local mid = deck.split(11, function(a, b) return b - a < 6 end); eq(mid >= 5 and mid <= 6, true, "the middle of what fits")
    eq(deck.split(11, function() return false end) ~= nil, true, "a cut even when none fits")
    eq(deck.split(1, function() return true end), nil)
    -- the same cards on every edge: with two rows, a side holds what a strip holds
    local strip = deck.layout("bottom", 1920, 1080, 52, { tiles = 2, rows = 2, hidden = {} })
    local col = deck.layout("right", 1920, 1080, 52, { tiles = 2, rows = 2, hidden = {} })
    eq(#strip.dropped, 0, "a strip holds every card"); eq(#col.dropped, 0, "and so does a side")
    local ids = {}
    for _, p in ipairs(strip.parts) do ids[p.id] = true end
    for _, p in ipairs(col.parts) do eq(ids[p.id], true, p.id .. " on the side too"); ids[p.id] = nil end
    eq(next(ids), nil, "nothing on the strip that the side misses")
    -- the callers' shape: a cut is one this test can hold, not one the walk from the middle settled on
    local part = { 200, 120, 170, 150, 180, 140, 160, 190, 120, 130, 140 }
    local function stack(a, b)
        local t = deck.RAIL + deck.CARD_GAP * (b - a)
        for i = a, b do t = t + part[i] end
        return t
    end
    local at = deck.split(#part, function(a, b) return stack(a, b) <= 960 end)
    eq(stack(1, at) <= 960 and stack(at + 1, #part) <= 960, true, "both sides of the cut fit")
end)
test("nexus deck: the scene chips wrap to their card", function()
    local c = deck.chips(5, { w = 200, h = 214 })
    eq(c[1].x, 12); eq(c[2].y, c[1].y); eq(c[3].y, c[1].y + deck.CHIP_H + deck.CHIP_GAP, "two across, then the next row")
end)
test("nexus deck: what grows out sits on the open side, level with what it grew from, on the screen", function()
    local d = deck.layout("bottom", 1920, 1080, 52)
    local x, y = deck.grow(d, { x = 0, y = 40, w = 100, h = 60 }, 520, 330, 1920, 1080, 52)
    eq(y, d.y - 330 - deck.GAP, "above a bottom deck"); eq(x, deck.GAP, "kept on the screen")
    local t = deck.layout("top", 1920, 1080, 52)
    local _, ty = deck.grow(t, { x = 800, y = 40, w = 100, h = 60 }, 520, 330, 1920, 1080, 52)
    eq(ty, t.y + t.h + deck.GAP, "below a top deck")
    local r = deck.layout("right", 1920, 1080, 52)
    local rx, ry = deck.grow(r, { x = 0, y = 900, w = 100, h = 60 }, 520, 330, 1920, 1080, 52)
    eq(rx, r.x - 520 - deck.GAP, "beside a right column"); eq(ry, 1080 - 330 - deck.GAP, "and never off the bottom")
end)
test("nexus deck: the workspaces, in order, the active one even when empty, and where + goes", function()
    local list = { { id = 3, monitor = "eDP-1", windows = 2 }, { id = 1, monitor = "eDP-1", windows = 1 }, { id = 7, monitor = "HDMI-A-1", windows = 1 }, { id = -98, monitor = "eDP-1", name = "special" } }
    local s = deck.spaces(list, "eDP-1", 5)
    eq(#s, 3); eq(s[1].id, 1); eq(s[2].id, 3); eq(s[3].id, 5, "the active one, empty"); eq(s[3].active, true); eq(s[1].active, false)
    eq(deck.free_space(s), 2)
end)
test("nexus deck: tiles the screen's shape, fitted to the bay in a row or in columns", function()
    local row = deck.tiles(5, { x = 0, y = 0, w = 948, h = 200 }, false, 16 / 9)
    eq(#row, 6, "one more for +")
    for i, r in ipairs(row) do
        assert(math.abs(r.w / r.h - 16 / 9) < 0.05, "tile " .. i .. " is the screen's shape")
        if i > 1 then assert(r.x >= row[i - 1].x + row[i - 1].w, "side by side") end
    end
    assert(row[6].x + row[6].w <= 948 - 14 + 1, "inside the bay")
    local col = deck.tiles(9, { x = 0, y = 0, w = 404, h = 380 }, true, 16 / 9)
    local last = col[#col]
    assert(last.y + last.h + 16 <= 380, "every tile and its name fit down the column")
    -- left to choose, the bay's shape decides: a wide one a row, a tall one columns
    local wide = deck.tiles(3, { x = 0, y = 0, w = 948, h = 200 }, nil, 16 / 9)
    eq(wide[2].y, wide[1].y, "a wide bay: one row")
    local tall = deck.tiles(5, { x = 0, y = 0, w = 404, h = 600 }, nil, 16 / 9)
    eq(tall[2].y, tall[1].y, "a tall bay: two across"); eq(tall[3].y > tall[1].y, true, "and down")
end)
test("nexus deck: windows as parts of their screen, floating ones over the tiled", function()
    local mon = { id = 0, x = 0, y = 0, width = 1920, height = 1080, scale = 1 }
    local w = deck.windows({
        { address = "0x1", class = "zen", title = "a", at = { 960, 0 }, size = { 960, 540 }, workspace = { id = 2 }, monitor = 0, floating = true },
        { address = "0x2", class = "kitty", title = "b", at = { 0, 0 }, size = { 960, 1080 }, workspace = { id = 2 }, monitor = 0, focusHistoryID = 0 },
        { address = "0x3", class = "x", title = "c", at = { 0, 0 }, size = { 10, 10 }, workspace = { id = 2 }, monitor = 1 },
    }, mon)
    eq(#w, 2, "only this monitor's"); eq(w[1].app, "kitty", "tiled first"); eq(w[1].focused, true)
    eq(w[2].nx, 0.5); eq(w[2].nh, 0.5)
    local f = deck.focused({ { workspace = { id = 2 }, focusHistoryID = 3, class = "a" }, { workspace = { id = 2 }, focusHistoryID = 1, class = "b" }, { workspace = { id = 4 }, focusHistoryID = 0, class = "c" } }, 2)
    eq(f.class, "b", "the most recent on the workspace you are on")
end)
test("nexus deck: a window's own sound, by its process, then by its name", function()
    local apps = { { id = "7", name = "Spotify", binary = "spotify", pid = 50 }, { id = "8", name = "Firefox", binary = "firefox", pid = 60 } }
    eq(deck.stream(apps, "firefox", 99), 2); eq(deck.stream(apps, "whatever", 50), 1, "the process first")
    eq(deck.stream(apps, "kitty", 1), nil); eq(deck.stream(apps, "", 1), nil)
end)
test("nexus deck: what is waiting, the pressing first, each with what deals with it", function()
    local w = deck.waiting({ notes = 3, first_note = "Discord", updates = 14, weather = "Cloudy 20°", quiet = true, recording = true, battery = 12, charging = false })
    eq(w[1].word, "Recording the screen"); eq(w[1].tog, 8)
    eq(w[2].act, "SAVER"); eq(w[2].tog, 7)
    eq(w[3].word, "3 new · Discord"); eq(w[3].go, 30)
    eq(w[4].word, "14 updates waiting"); eq(w[4].go, 13)
    eq(w[#w].act, "END", "quiet last")
    local none = deck.waiting({})
    eq(#none, 1); eq(none[1].word, "All quiet")
end)
test("nexus deck: scenes cleaned, compared and carried out", function()
    eq(#deck.clean(nil), #deck.DEFAULTS, "nothing saved: the defaults")
    local c = deck.clean({ { name = "  Focus time is long  ", quiet = "yes", night = true, volume = 140 }, { name = "" }, 5 })
    eq(#c, 1); eq(c[1].name, "Focus time i", "twelve letters"); eq(c[1].quiet, nil, "not a switch"); eq(c[1].volume, 100)
    local state = { quiet = false, night = true, awake = false, saver = false, wifi = true, bluetooth = true, volume = 62, brightness = 80 }
    local night = { name = "Night", night = true, quiet = true, brightness = 35 }
    local d = deck.diff(night, state)
    eq(#d, 2); eq(d[1], "quiet on"); eq(d[2], "screen 35%")
    local s = deck.steps(night, state)
    eq(s[1].flip, "quiet"); eq(s[2].level, "brightness"); eq(s[2].to, 0.35)
    eq(#deck.diff(night, { quiet = true, night = true, brightness = 35 }), 0)
    eq(deck.live({ { name = "A", saver = true }, night }, { quiet = true, night = true, brightness = 35 }), 2)
    local mine = deck.capture(state, "Mine")
    eq(mine.volume, 62); eq(mine.night, true); eq(#deck.diff(mine, state), 0, "a captured scene is the desktop as it is")
    eq(#deck.diff({ name = "S", brightness = 50 }, { volume = 10 }), 0, "no backlight: brightness is left out")
    local e = deck.clean({ { name = "Work", quiet = true, env = "code day" } })[1]
    eq(e.env, "code day", "an environment rides along")
    eq(deck.diff(e, { quiet = true })[1], "restore code day", "and is said")
    eq(deck.live({ e }, { quiet = true }), nil, "a scene with an environment is never already so")
end)
test("config: the old Nexus settings go quietly; who you are stays, and the deck's edge", function()
    local s, problems, notes = config.validate({ version = 2, nexus = { view = "full", hub = { hero = "player" }, folded = { "machine" },
        orbit = { nodes = { "wifi" } }, identity = { name = "Alex" }, edge = "left", bars = "twentyfour" } })
    eq(s.nexus.identity.name, "Alex"); eq(s.nexus.edge, "left"); eq(s.nexus.mode, "deck")
    eq(s.nexus.bars, "twentyfour", "the deck's border keeps its bars")
    eq(s.nexus.folded, nil, "the drawer's folds are gone"); eq(s.nexus.orbit, nil, "and the orbit"); eq(#problems, 0)
    for _, n in ipairs(notes) do assert(not n:find("nexus"), "no unknown-setting note for the old Nexus: " .. n) end
end)

local activity = require("lib/activity")
test("activity: minutes by day, hour and app; only the last eight days kept", function()
    local doc = activity.add(nil, { year = 2026, month = 10, day = 28, hour = 9 }, "kitty")
    doc = activity.add(doc, { year = 2026, month = 10, day = 28, hour = 9 }, "kitty")
    doc = activity.add(doc, { year = 2026, month = 10, day = 28, hour = 21 }, "zen")
    eq(doc.days["2026-10-28"].hours["9"], 2); eq(doc.days["2026-10-28"].apps.kitty, 2); eq(doc.days["2026-10-28"].apps.zen, 1)
    for d = 1, 12 do doc = activity.add(doc, { year = 2026, month = 11, day = d, hour = 1 }, "x") end
    local n = 0
    for _ in pairs(doc.days) do n = n + 1 end
    eq(n, activity.KEEP_DAYS); eq(doc.days["2026-10-28"], nil, "the oldest went")
end)

local claude = require("lib/claude")
test("claude: asked lean, carried on by session, and its stream read", function()
    local joined = table.concat(claude.args("hi", { session = "8a91e81c-1234", persona = "bmo" }), " ")
    assert(joined:find("--tools  ", 1, true), "no tools"); assert(joined:find("disableAllHooks", 1, true), "no hooks")
    assert(joined:find("--resume 8a91e81c-1234", 1, true), "goes on from the last answer")
    assert(joined:find("BMO", 1, true), "as BMO")
    assert(not table.concat(claude.args("hi", { session = "x; reboot" }), " "):find("--resume", 1, true), "a session that is not an id is left out")
    local d = claude.read("", decode_table({ type = "stream_event", event = { type = "content_block_delta", delta = { type = "text_delta", text = "Hey" } } }))
    eq(d.delta, "Hey")
    local r = claude.read("", decode_table({ type = "result", subtype = "success", result = "Hey there", session_id = "abc", total_cost_usd = 0.004 }))
    eq(r.done, true); eq(r.session, "abc"); eq(r.text, "Hey there")
    eq(claude.read("", decode_table({ type = "result", subtype = "success", is_error = true, result = "Not logged in" })).error, "Not logged in")
    eq(claude.read("", decode_broken), nil)
    local w = claude.wrap("one two three four five\n\nsix", 9)
    eq(w[1], "one two"); eq(w[2], "three"); eq(w[4], ""); eq(w[5], "six")
end)

test("nexus canvas: two rows are a free canvas inside their band, every card where it was put", function()
    local nd = require("lib/nexusdeck")
    local d = nd.canvas_layout("bottom", 1920, 1049, 0, { rows = 2, hidden = {} })
    eq(d.canvas, true, "a canvas")
    eq(d.w, 1920 - 2 * nd.GAP, "the screen's width")
    eq(d.h, nd.RAIL + 2 * nd.ROW + nd.CARD_GAP + nd.PAD, "two rows tall, not the screen")
    eq(d.y + d.h, 1049 - nd.GAP, "on the bottom edge")
    local t = nd.canvas_layout("top", 1920, 1049, 0, { rows = 2, hidden = {} })
    eq(t.y, 6, "on the top edge, under the bar"); eq(t.h, d.h, "the same two rows")
    -- down a side: two columns wide, under the bar to the foot
    local side = nd.layout("right", 1920, 1049, 0, { rows = 2, hidden = {} })
    local r2 = nd.canvas_layout("right", 1920, 1049, 0, { rows = 2, hidden = {} })
    eq(r2.w, side.w, "the two columns' width"); eq(r2.x, side.x, "on the right edge"); eq(r2.vertical, true, "a column")
    for _, p in ipairs(r2.parts) do
        assert(p.x >= nd.PAD and p.x + p.w <= r2.w - nd.PAD, p.id .. " inside the side band")
    end
    for _, p in ipairs(d.parts) do
        assert(p.x >= nd.PAD and p.x + p.w <= d.w - nd.PAD, p.id .. " inside, across")
        assert(p.y >= nd.RAIL and p.y + p.h <= d.h - nd.PAD, p.id .. " inside, down")
    end
    -- alone on the canvas, carried to the middle: it is there, on the grid, and still there next time
    local alone = {}
    for _, id in ipairs(nd.ORDER) do if id ~= "music" then alone[id] = true end end
    local da = nd.canvas_layout("bottom", 1920, 1049, 0, { rows = 2, hidden = alone })
    local r = nd.canvas_drop(da, "music", da.w / 2, da.h / 2)
    local list = nd.canvas_list({ music = r })
    eq(#list, 1, "one card placed")
    local back = nd.clean_canvas(list)
    local d2 = nd.canvas_layout("bottom", 1920, 1049, 0, { rows = 2, hidden = alone, canvas = back })
    local m = d2.bays.music
    eq(math.abs(m.x + m.w / 2 - d2.w / 2) <= nd.GRID, true, "in the middle across")
    eq(math.abs(m.y + m.h / 2 - d2.h / 2) <= nd.GRID, true, "and down")
    eq((m.x - nd.PAD) % nd.GRID, 0, "on the grid, after being saved and read")
    eq(nd.clean_canvas({ "c6_500_500_100_100" }).music.x, 0.5, "the older thousandths still read")
    -- carried off the screen, it stays on the canvas; made tiny, it keeps the smallest size
    local off = nd.canvas_drop(d2, "music", -500, 99999)
    local d3 = nd.canvas_layout("bottom", 1920, 1049, 0, { rows = 2, hidden = alone, canvas = { music = off } })
    eq(d3.bays.music.x, nd.PAD, "kept at the left"); eq(d3.bays.music.y + d3.bays.music.h <= d3.h - nd.PAD, true, "and above the foot")
    local tiny = nd.canvas_resize(d3, "music", 3, 3)
    local d4 = nd.canvas_layout("bottom", 1920, 1049, 0, { rows = 2, hidden = alone, canvas = { music = tiny } })
    eq(d4.bays.music.w, nd.MIN_W, "never narrower than a card can be"); eq(d4.bays.music.h, nd.MIN_H, "or shorter")
    -- a card and a place as one number the scene can hold exactly (float32: whole up to 2^24)
    local c, x, y = nd.unpack_event(10 * 1000000 + 480 * 1000 + 269)
    eq(c .. "," .. x .. "," .. y, "10,1920,1076", "the last card, at the far corner")
    eq(10 * 1000000 + 999 * 1000 + 999 < 2 ^ 24, true, "the largest fits a float32 exactly")
    eq(nd.unpack_event("nonsense"), nil, "nonsense is nothing")
    -- a list that is not one is nothing; a name past the parts is nothing
    eq(next(nd.clean_canvas({ "c99_1_1_1_1", "music", 4 })), nil, "nonsense places nothing")
end)
test("nexus canvas: edges meet their neighbours, cards never land on each other", function()
    local nd = require("lib/nexusdeck")
    local two = {}
    for _, id in ipairs(nd.ORDER) do if id ~= "music" and id ~= "today" then two[id] = true end end
    local d = nd.canvas_layout("bottom", 1920, 1049, 0, { rows = 2, hidden = two,
        canvas = { music = { x = 100 / 1902, y = 30 / 474, w = 272 / 1902, h = 216 / 474 } } })
    local m = d.bays.music
    -- let go 9 px past music's right side: it meets it at the deck's gap, its top lined up with music's
    local x, y = nd.canvas_snap_move(d, "today", m.x + m.w + nd.CARD_GAP + 9, m.y + 5, 222, 134)
    eq(x, m.x + m.w + nd.CARD_GAP, "side by side, at the gap"); eq(y, m.y, "tops lined up")
    -- far from anything: the grid
    local gx, gy = nd.canvas_snap_move(d, "today", 1203, 180, 222, 134)
    eq((gx - nd.PAD) % nd.GRID, 0, "on the grid across"); eq((gy - nd.RAIL) % nd.GRID, 0, "and down")
    -- settling over music (not dropped on its middle): the nearest place beside it instead
    local ox, oy = nd.canvas_snap_move(d, "today", m.x + 20, m.y + 20, 222, 134)
    local clear = ox >= m.x + m.w + nd.CARD_GAP or ox + 222 + nd.CARD_GAP <= m.x or oy >= m.y + m.h + nd.CARD_GAP or oy + 134 + nd.CARD_GAP <= m.y
    eq(clear, true, "not over music")
    -- a gap a little narrower than it: it narrows to fit there rather than going far away
    local d5 = nd.canvas_layout("bottom", 1920, 1049, 0, { rows = 2, hidden = two,
        canvas = { music = { x = 600 / 1900, y = 30 / 474, w = 272 / 1900, h = 216 / 474 } } })
    local m5 = d5.bays.music
    local gx2, _, gw2 = nd.canvas_snap_move(d5, "today", m5.x - nd.CARD_GAP - 200, m5.y, 222, 134)
    eq(gx2 + gw2 + nd.CARD_GAP <= m5.x, true, "fits beside music"); eq(gw2 >= 0.6 * 222 and gw2 < 222, true, "narrowed, not past 60 %")
    -- let go with its middle over music: the two change slots, place and size together
    local t0 = d.bays.today
    local plan, other = nd.canvas_plan(d, "today", m.x + m.w / 2, m.y + m.h / 2)
    eq(other, "music", "dropped on music")
    eq(plan.today.x .. "," .. plan.today.y .. "," .. plan.today.w .. "," .. plan.today.h, m.x .. "," .. m.y .. "," .. m.w .. "," .. m.h, "today in music's slot")
    eq(plan.music.x .. "," .. plan.music.y .. "," .. plan.music.w .. "," .. plan.music.h, t0.x .. "," .. t0.y .. "," .. t0.w .. "," .. t0.h, "music in today's")
    -- a corner pulled into music stops at it; near the band's end it meets the end
    local d2 = nd.canvas_layout("bottom", 1920, 1049, 0, { rows = 2, hidden = two,
        canvas = { music = { x = 600 / 1902, y = 30 / 474, w = 272 / 1902, h = 216 / 474 },
                   today = { x = 200 / 1902, y = 30 / 474, w = 222 / 1902, h = 134 / 474 } } })
    local t, mm = d2.bays.today, d2.bays.music
    local _, _, w = nd.canvas_snap_size(d2, "today", t.x, t.y, 800, 134)
    eq(t.x + w, mm.x - nd.CARD_GAP, "stops a gap short of music")
    local _, _, _, h = nd.canvas_snap_size(d2, "today", t.x, t.y, 222, d2.h - t.y - nd.PAD - 6)
    eq(t.y + h, d2.h - nd.PAD, "meets the band's foot")
end)
test("nexus deck: a card's size is its height down a side, as its width along a strip", function()
    local nd = require("lib/nexusdeck")
    local few = {}
    for _, id in ipairs(nd.ORDER) do if id ~= "music" and id ~= "profile" then few[id] = true end end
    local s = nd.layout("right", 1920, 1049, 0, { rows = 1, hidden = few, sizes = { music = "s" } })
    local l = nd.layout("right", 1920, 1049, 0, { rows = 1, hidden = few, sizes = { music = "l" } })
    eq(l.bays.music.h > s.bays.music.h, true, "large is taller than small")
    eq(l.bays.music.w, s.bays.music.w, "and as wide: the column's width")
end)

test("vizfeed gain: quiet music fills the range, silence stays silent, a loud hit is not clipped forever", function()
    local vf = require("lib/vizfeed")
    local quiet = { 0.001, 0.003, 0.002, 0.0005 }
    local out, peak = vf.gain(0, quiet)
    eq(out[2] > 0.9, true, "the loudest band of quiet music reaches the top")
    eq(out[4] < out[1], true, "and the rest keep their order")
    local sil = vf.gain(0, { 0.0002, 0.0001 })
    eq(sil[1], 0, "under the floor it is silence")
    local _, p2 = vf.gain(peak, { 0.9 })
    eq(p2, 0.9, "a loud hit raises the ceiling at once")
    local p3 = p2
    for _ = 1, 300 do _, p3 = vf.gain(p3, { 0.01 }) end
    eq(p3 < 0.4, true, "and it sinks back within seconds")
end)

local notch = require("lib/notch")
test("notch: the fan's tabs on their arc, panels on the screen, the carousel, the weather's bars", function()
    local f = notch.fan(500)
    eq(#f, #notch.TABS)
    assert(f[1].y < 500 and f[#f].y > 500, "from above the nub to below it")
    assert(math.abs(f[1].y - 500 + (f[#f].y - 500)) < 0.01, "even about it")
    eq(notch.panel_y(500, 400, 1049), 300); eq(notch.panel_y(40, 400, 1049), 12, "kept on the screen")
    local a, seen = notch.arc(5, 5); eq(a, 0); eq(seen, true)
    local _, far = notch.arc(0, 9); eq(far, false, "far from the middle: not drawn")
    local b = notch.bars({ { temp = 10 }, { temp = 20 }, { temp = 15 } })
    eq(b[1], 0.15); eq(b[2], 1)
    eq(notch.thumb_name("/a/b.jpg"), notch.thumb_name("/a/b.jpg")); assert(notch.thumb_name("/a/b.jpg") ~= notch.thumb_name("/a/c.jpg"))
    local p = notch.pictures("/w/b.PNG\n/w/notes.txt\n/w/a.jpg\n", 5)
    eq(#p, 2); eq(p[1], "/w/a.jpg")
    -- a folder of thousands: forty drawn at a time, the same seed the same forty, all of them its own
    local many = {}
    for i = 1, 200 do many[i] = "/w/p" .. i .. ".jpg" end
    local d1, d2, d3 = notch.draw(many, 40, 7), notch.draw(many, 40, 7), notch.draw(many, 40, 8)
    eq(#d1, 40, "forty of them"); eq(d1[1], d2[1], "the same seed draws the same")
    local moved = 0
    for i = 1, 10 do if d1[i] ~= d3[i] then moved = moved + 1 end end
    eq(moved >= 8, true, "another seed draws others")
    local okall, got = true, {}
    for _, v in ipairs(d1) do if got[v] then okall = false end; got[v] = true; if not v:find("^/w/p%d+%.jpg$") then okall = false end end
    eq(okall, true, "each picture once, out of the folder")
    eq(notch.tab_index("walls"), 3)
    -- the colours: a mean colour's hue, and how grey it is; the band it is filed under
    local hh, ss = notch.hue(1, 0, 0); eq(hh, 0, "red"); eq(ss, 1)
    local hg = notch.hue(0, 1, 0); eq(hg, 120, "green")
    local hb = notch.hue(0, 0, 1); eq(hb, 240, "blue")
    eq(notch.hue(255, 255, 255), 0, "white has no hue"); eq(select(2, notch.hue(255, 255, 255)), 0, "and no colour")
    eq(math.floor(notch.hue(0.9, 0.2, 0.1) + 0.5), 8, "a red-orange, in degrees")
    eq(notch.band(notch.hue(0.9, 0.2, 0.1), 12), 0, "filed under the reds")
    eq(notch.band(notch.hue(0.1, 0.2, 0.9), 12), 8, "a blue under the blues")
    eq(notch.band(notch.hue(0.1, 0.8, 0.2), 12), 4, "a green under the greens")
    eq(notch.band(notch.hue(0.9, 0.9, 0.1), 12), 2, "a yellow under the yellows")
    eq(notch.band(notch.hue(0.1, 0.8, 0.8), 12), 6, "a cyan under the cyans")
    eq(notch.band(355, 12), 0, "red round the far side of the wheel too")
    -- from the Control Nexus: over a bottom strip's end, on a right column's open side
    local strip = deck.layout("bottom", 1920, 1049, 0, {})
    local l = notch.from_deck(strip, 0, true, 1920, 1049)
    eq(l.py + notch.PANELS[0].h + 14 + notch.EAR, strip.y, "over the deck, clear of its notch"); eq(l.dir, 1); eq(l.ox, 0)
    local r = notch.from_deck(strip, 5, false, 1920, 1049)
    eq(r.px + notch.PANELS[5].w <= 1920, true, "kept on the screen"); eq(r.dir, -1); eq(r.ox, 1920)
    local col = deck.layout("right", 1920, 1049, 0, {})
    local c = notch.from_deck(col, 1, false, 1920, 1049)
    eq(c.px + notch.PANELS[1].w + 14 + notch.EAR, col.x, "beside the column, on its open side, clear of its notch")
    -- the nub: kept on the surface, off the stash's tab; the band it leaves the stash's edge strip
    eq(notch.nub_cy(0.3, 1049, 31, 1080), 314)
    eq(notch.nub_cy(0.01, 1049), 160, "kept off the surface's top")
    eq(notch.nub_cy(0.47, 1049, 31, 1080) + 31 + 70 <= (1080 - notch.STASH_TAB) / 2, true, "pushed above the stash's tab")
    eq(notch.nub_cy(0.53, 1049, 31, 1080) + 31 - 70 >= (1080 + notch.STASH_TAB) / 2, true, "or below it")
    local c0, c1 = notch.cut(314, 31)
    eq(c0, 31 + 314 - notch.NUB_REACH); eq(c1, 31 + 314 + notch.NUB_REACH)
end)

print("games")
local games = require("lib/games")
test("games: Steam's libraries and manifests, the desktop's menus, one list of both", function()
    local vdf = '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"/home/u/.local/share/Steam"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"/mnt/games/SteamLibrary"\n\t}\n}\n'
    local libs = games.libraries(vdf)
    eq(#libs, 2, "two libraries"); eq(libs[2], "/mnt/games/SteamLibrary")
    eq(games.libraries('"path"\t\t"D:\\\\Games"')[1], "D:\\Games", "an escaped path")
    eq(#games.libraries(vdf .. '"path"\t\t"/mnt/games/SteamLibrary"'), 2, "each library once")
    local listing = '"appid"\t\t"211820"\n"name"\t\t"Starbound"\n"installdir"\t\t"Starbound"\n'
        .. '"appid"\t\t"1493710"\n"name"\t\t"Proton Experimental"\n"installdir"\t\t"Proton - Experimental"\n'
        .. '"appid"\t\t"1070560"\n"name"\t\t"Steam Linux Runtime 1.0 (scout)"\n'
        .. '"appid"\t\t"275850"\n"name"\t\t"No Man\'s Sky"\n'
    local m = games.manifests(listing)
    eq(#m, 4, "four manifests"); eq(m[2].name, "Proton Experimental"); eq(m[2].installdir, "Proton - Experimental")
    eq(games.is_game(m[1]), true, "a game")
    eq(games.is_game(m[2]), false, "Proton is not a game")
    eq(games.is_game(m[3]), false, "nor a runtime")
    eq(games.is_game(m[4]), true, "a game without an installdir still is one")
    eq(games.is_game({ appid = "nope", name = "A game" }), false, "an id that is not a number is no manifest")
    local men = table.concat({
        "/usr/share/applications/cdda.desktop:Name=Cataclysm: Dark Days Ahead",
        "/usr/share/applications/cdda.desktop:Exec=cataclysm-tiles",
        "/usr/share/applications/cdda.desktop:Categories=Game;RolePlaying;",
        "/usr/share/applications/cdda.desktop:Terminal=false",
        "/usr/share/applications/steam.desktop:Name=Steam",
        "/usr/share/applications/steam.desktop:Categories=Game;",
        "/usr/share/applications/net.lutris.Lutris.desktop:Name=Lutris",
        "/usr/share/applications/net.lutris.Lutris.desktop:Categories=Game;",
        "/usr/share/applications/hidden.desktop:Name=A hidden game",
        "/usr/share/applications/hidden.desktop:Categories=Game;",
        "/usr/share/applications/hidden.desktop:NoDisplay=true",
        "/usr/share/applications/term.desktop:Name=A terminal game",
        "/usr/share/applications/term.desktop:Categories=Game;",
        "/usr/share/applications/term.desktop:Terminal=true",
    }, "\n")
    local d = games.desktops(men)
    eq(#d, 5, "one entry per file"); eq(d[1].id, "cdda"); eq(d[1].name, "Cataclysm: Dark Days Ahead")
    eq(games.is_desktop_game(d[1]), true, "a game on the menu")
    eq(games.is_desktop_game(d[3]), false, "a launcher is not")
    eq(games.is_desktop_game(d[4]), false, "nor a hidden entry")
    eq(games.is_desktop_game(d[5]), false, "nor a terminal one")
    local h = games.headers("/s/appcache/librarycache/211820/library_header.jpg\n"
        .. "/s/appcache/librarycache/275850/library_600x900.jpg\n"
        .. "/s/appcache/librarycache/211820/header.jpg\n")
    eq(h["211820"].path, "/s/appcache/librarycache/211820/library_header.jpg", "a header wins over a poster")
    eq(h["211820"].wide, true); eq(h["275850"].wide, false, "a poster is drawn cropped"); eq(h["999"], nil)
    local rows = games.collect(listing, men, h, nil, nil, 400)
    eq(#rows, 3, "two Steam games and one of the desktop's")
    eq(rows[1].name, "No Man's Sky", "Steam's first, by name")
    eq(rows[1].sub, "STEAM · 275850"); eq(rows[1].pic ~= "", true, "a poster when there is no header")
    eq(rows[1].wide, false)
    eq(rows[2].name, "Starbound"); eq(rows[2].wide, true, "with its header picture")
    eq(rows[3].name, "Cataclysm: Dark Days Ahead"); eq(rows[3].steam, false); eq(rows[3].id, "cdda")
    eq(#games.filter(rows, 1), 2, "Steam's"); eq(#games.filter(rows, 2), 1, "the desktop's")
    eq(#games.filter(rows, 0), 3, "all of them")
    -- one to a name: a menu entry for a game already listed is not added twice
    local twice = games.collect(listing, men .. "\n/usr/share/applications/star.desktop:Name=Starbound\n/usr/share/applications/star.desktop:Categories=Game;", {}, nil, nil, 400)
    eq(#twice, 3, "no duplicate")
    eq(#games.collect(listing, men, {}, nil, nil, 2), 2, "no more than asked")
    eq(games.collect(nil, nil, nil, nil, nil, 10)[1], nil, "nothing installed: nothing to show")
end)

test("games: the folders on disk — extracted, native and PortProton's", function()
    local loose = table.concat({
        "/home/u/games/Balatro/Balatro.exe",
        "/home/u/games/Balatro/lua51.dll",
        "/home/u/games/Townscaper/Townscaper.exe",
        "/home/u/games/Townscaper/UnityCrashHandler32.exe",
        "/home/u/games/starsector/starsector.sh",
        "/home/u/games/starsector/data/x.jar",
        "/home/u/games/Homeworld Remastered Collection [GOG]/setup_homeworld_2.1.exe",
        "/home/u/Games/drive_c/windows/notepad.exe",
        "/home/u/.local/share/PortProton/prefixes/Fallout 3/drive_c/Games/Fallout3/Fallout3.exe",
        "/home/u/.local/share/PortProton/prefixes/Fallout 3/drive_c/windows/system32/regedit.exe",
    }, "\n")
    local g = games.on_disk(loose)
    eq(#g, 4, "the installer, the crash handler and the prefix are not games")
    eq(g[1].name, "Balatro"); eq(g[1].kind, "WINE"); eq(g[1].exe, "Balatro.exe")
    eq(g[2].name, "Fallout 3"); eq(g[2].kind, "PORTPROTON")
    eq(g[2].dir, "/home/u/.local/share/PortProton/prefixes/Fallout 3/drive_c/Games/Fallout3")
    eq(g[3].name, "starsector"); eq(g[3].kind, "NATIVE"); eq(g[3].exe, nil, "its own launcher is in the folder")
    eq(g[4].name, "Townscaper")
    eq(games.title("Homeworld Remastered Collection [GOG]"), "Homeworld Remastered Collection")
    eq(games.title("Sandustry-AnkerGames"), "Sandustry")
    -- and in the one list: Steam's, then these, then the desktop's
    local man = '"appid"\t\t"211820"\n"name"\t\t"Starbound"\n"appid"\t\t"275850"\n"name"\t\t"No Man\'s Sky"\n'
    local menu = "/usr/share/applications/cdda.desktop:Name=Cataclysm: Dark Days Ahead\n/usr/share/applications/cdda.desktop:Categories=Game;\n"
    local all = games.collect(man, menu, nil, loose, nil, 400)
    eq(#all, 7, "two Steam games, four on disk, one app")
    eq(all[3].name, "Balatro"); eq(all[3].sub, "LOCAL · WINE"); eq(all[3].disk, true)
    eq(#games.filter(all, 3), 4, "the folders on disk"); eq(#games.filter(all, 2), 1, "the desktop's")
end)
test("games: a preview for each — Steam's art, a folder's icon, the menus' icons", function()
    local menu = table.concat({
        "/usr/share/applications/cdda.desktop:Name=Cataclysm: Dark Days Ahead",
        "/usr/share/applications/cdda.desktop:Categories=Game;",
        "/usr/share/applications/cdda.desktop:Icon=org.cataclysmdda.CataclysmDDA",
        "/usr/share/applications/steam.desktop:Name=Steam",
        "/usr/share/applications/steam.desktop:Categories=Game;",
        "/usr/share/applications/steam.desktop:Icon=steam",
    }, "\n")
    eq(#games.icon_names(menu), 1, "the game's icon, not the launcher's")
    eq(games.icon_names(menu)[1], "org.cataclysmdda.CataclysmDDA")
    local found = table.concat({
        "/usr/share/icons/Papirus/48x48/apps/org.cataclysmdda.CataclysmDDA.png",
        "/usr/share/icons/hicolor/256x256/apps/org.cataclysmdda.CataclysmDDA.png",
        "/usr/share/icons/hicolor/256x256/apps/other.png",
    }, "\n")
    local map = games.icons(found)
    eq(map["org.cataclysmdda.CataclysmDDA"], "/usr/share/icons/hicolor/256x256/apps/org.cataclysmdda.CataclysmDDA.png",
       "the biggest one the theme has")
    eq(map["other"] ~= nil, true)
    local rows = games.collect(nil, menu, nil, nil, map, 50)
    eq(rows[1].name, "Cataclysm: Dark Days Ahead"); eq(rows[1].icon, true, "drawn as an icon, not full-bleed")
    eq(rows[1].pic, map["org.cataclysmdda.CataclysmDDA"])
    -- an Icon= that is already a path is the picture
    local abs = "/usr/share/applications/x.desktop:Name=X\n/usr/share/applications/x.desktop:Categories=Game;\n/usr/share/applications/x.desktop:Icon=/home/u/pics/x.png\n"
    eq(games.collect(nil, abs, nil, nil, nil, 5)[1].pic, "/home/u/pics/x.png")
    -- a folder's own icon, beside its program
    local loose = "/home/u/games/Balatro/Balatro.exe\n/home/u/games/Balatro/icon.png\n/home/u/games/Townscaper/Townscaper.exe\n"
    local disk = games.on_disk(loose)
    eq(#disk, 2, "an icon on its own is not a game")
    eq(disk[1].icon, "/home/u/games/Balatro/icon.png"); eq(disk[2].icon, nil)
    local all = games.collect(nil, nil, nil, loose, nil, 10)
    eq(all[1].icon, true, "a folder's icon is a preview too"); eq(all[2].pictured == true, false)
end)
test("games: a picture from Steam's store, for the games the machine has none of", function()
    eq(games.slug("Project Zomboid"):match("^project%-zomboid%-%x%x%x%x%x%x$") ~= nil, true, "a cache file's name")
    eq(games.slug("Balatro"), games.slug("Balatro"), "the same game, the same file")
    eq(games.slug("Hydra (4.0.3)") ~= games.slug("Hydra"), true, "two games, two files")
    eq(games.slug(""):match("^game%-%x%x%x%x%x%x$") ~= nil, true, "nothing to go on still makes a name")
    eq(games.search_url("Hotline Miami 2"),
       "https://store.steampowered.com/api/storesearch/?cc=us&l=en&term=Hotline%20Miami%202")
    eq(games.search_url("Cataclysm: Dark Days Ahead"):find("Cataclysm%%3A%%20Dark") ~= nil, true, "punctuation travels")
    eq(games.art_urls("2379780")[1],
       "https://cdn.cloudflare.steamstatic.com/steam/apps/2379780/capsule_616x353.jpg", "the card's shape first")
    eq(#games.art_urls("nope"), 0, "no appid, nothing to ask")
    local items = { { name = "Balatro", id = 2379780 }, { name = "Hotline Miami 2: Wrong Number", id = 274170 },
                    { name = "Hydra Heli 2", id = 4241690 } }
    eq(games.appid(items, "balatro"), "2379780", "the same title, whatever its case")
    eq(games.appid(items, "Hotline Miami 2"), "274170", "the store's longer title")
    eq(games.appid(items, "Hydra"), nil, "a name that merely starts the same is not the game")
    eq(games.appid({}, "Balatro"), nil, "nothing found")
    local listing = "/home/u/.cache/mooi/games/one.jpg\n/home/u/.cache/mooi/games/two.jpg\n"
    eq(games.online(listing)["two"], "/home/u/.cache/mooi/games/two.jpg")
    eq(games.asked(listing)["one"], nil, "a picture is not an answer")
    eq(games.asked("/c/two.json\n")["two"], true, "asked, whatever was said")
    eq(games.bare({ pic = "", wide = false }), true, "no picture at all")
    eq(games.bare({ pic = "/x/header.jpg", wide = true }), false, "a header is the card's shape already")
    eq(games.bare({ pic = "/x/library_600x900.jpg", wide = false }), true, "a poster cropped into the card gives way")
    eq(games.bare({ pic = "/x/icon.png", icon = true, wide = false }), true, "a menu's small icon gives way too")
    local rows = { { name = "Balatro", pic = "", icon = false }, { name = "Townscaper", pic = "", icon = false },
                   { name = "Hydra (4.0.3)", pic = "/usr/share/icons/hydra.png", icon = true },
                   { name = "POLYGON", pic = "/home/u/.local/share/Steam/h.jpg", wide = true },
                   { name = "Starbound", pic = "/home/u/.local/share/Steam/s/library_600x900.jpg", wide = false } }
    games.dress(rows, { [games.slug("Balatro")] = "/c/balatro.jpg", [games.slug("Hydra (4.0.3)")] = "/c/hydra.jpg",
                        [games.slug("Starbound")] = "/c/starbound.jpg" })
    eq(rows[1].pic, "/c/balatro.jpg"); eq(rows[1].wide, true); eq(rows[1].icon, false, "drawn whole")
    eq(rows[2].pic, "", "nothing online for it: the well stays")
    eq(rows[3].pic, "/c/hydra.jpg", "a menu's small icon gives way to the store's picture")
    eq(rows[4].pic, "/home/u/.local/share/Steam/h.jpg", "Steam's own header keeps its place")
    eq(rows[5].pic, "/c/starbound.jpg", "a portrait poster gives way to the wide capsule")
    eq(rows[5].wide, true, "and is drawn whole")
end)

print("vizfeed")
local vizfeed = require("lib/vizfeed")
test("vizfeed: a full frame round-trips", function()
    local t = vizfeed.silent(7)
    t.bands[1], t.bands[16], t.bands[32] = 1, 0.5, 0.25
    t.bass, t.high, t.beat, t.phase, t.playing, t.missing, t.seq = 0.9, 0.4, 1, 0.75, true, false, 8
    local back = vizfeed.decode(vizfeed.encode(t))
    eq(back.seq, 8, "the counter"); eq(back.bands[1], 1, "the first band")
    eq(back.bands[16], 0.5, "a middle band"); eq(back.bands[32], 0.25, "the last band")
    eq(back.playing, true, "playing"); eq(back.missing, false, "not missing")
    eq(back.phase, 0.75, "phase"); eq(back.beat, 1, "beat")
end)
test("vizfeed: a partial or unknown line is refused without throwing", function()
    eq(vizfeed.decode(""), nil, "empty")
    eq(vizfeed.decode("v2 1 2 3"), nil, "unknown version")
    local line = vizfeed.encode(vizfeed.silent(1))
    eq(vizfeed.decode(line:sub(1, #line - 6)), nil, "truncated")
    eq(vizfeed.decode(line:gsub("v1 ", "v1 5 ")), nil, "too many bands")
end)
test("vizfeed: trailing fields are accepted for forward compatibility", function()
    local t = vizfeed.silent(3); t.playing = true
    local back = vizfeed.decode(vizfeed.encode(t) .. " future field")
    eq(back.seq, 3, "the known part still reads")
end)
test("vizfeed: only a newer counter is new", function()
    eq(vizfeed.newer(4, 5), true, "newer"); eq(vizfeed.newer(5, 5), false, "same")
    eq(vizfeed.newer(5, 4), false, "older"); eq(vizfeed.newer(nil, 1), true, "first")
end)
test("vizfeed: freshness is a two-second window", function()
    eq(vizfeed.fresh(1000, 3000), true, "at the edge"); eq(vizfeed.fresh(1000, 3001), false, "past it")
    eq(vizfeed.fresh(nil, 3000), false, "never seen")
end)
test("vizfeed: 32 bands map onto 16 and 24 in order", function()
    local b = {}
    for i = 1, 32 do b[i] = i / 32 end
    local sixteen = vizfeed.map(b, 16)
    eq(#sixteen, 16, "sixteen"); eq(sixteen[1], b[1], "first"); eq(sixteen[16], b[32], "last")
    local twentyfour = vizfeed.map(b, 24)
    eq(#twentyfour, 24, "twenty-four"); eq(twentyfour[1], b[1], "first"); eq(twentyfour[24], b[32], "last")
    eq(vizfeed.map(b, 16)[2] < vizfeed.map(b, 16)[3], true, "order kept")
end)

test("vizfeed: analysis follows the bass and treble with an envelope", function()
    local b = {}; for i = 1, 32 do b[i] = 0.8 end
    local s = vizfeed.analyse(nil, b, 1 / 30)
    eq(s.bass > 0.8, true, "bass lifted"); eq(s.level > 0, true, "level moves")
    local quiet = {}; for i = 1, 32 do quiet[i] = 0 end
    local down = vizfeed.analyse(s, quiet, 1 / 30)
    eq(down.level < s.level, true, "and releases, slower than it attacked")
end)
test("vizfeed: a rising bass edge beats once, then waits out the refractory", function()
    local loud = {}; for i = 1, 32 do loud[i] = 0.9 end
    local quiet = {}; for i = 1, 32 do quiet[i] = 0 end
    local a = vizfeed.analyse(nil, quiet, 1 / 30)
    local beat = vizfeed.analyse(a, loud, 1 / 30)
    eq(beat.beat > 0.9, true, "the edge beats")
    local again = vizfeed.analyse(beat, loud, 1 / 30)
    eq(again.beat < beat.beat, true, "it decays")
    eq(vizfeed.analyse(again, loud, 1 / 30).beat < again.beat, true, "and keeps decaying")
end)
test("vizfeed: phase turns and wraps in 0..1", function()
    local b = {}; for i = 1, 32 do b[i] = 0.2 end
    local s = { level = 0, high = 0, bass = 0.2, beat = 0, phase = 0.98, tempo = 0, last_beat = 0, t = 0 }
    local n = vizfeed.analyse(s, b, 0.1)
    eq(n.phase < 0.98, true, "wrapped"); eq(n.phase >= 0, true, "and stayed in range")
    eq(n.t > s.t, true, "time advances")
end)

test("config: music on every edge, with the old foot switch as the fallback", function()
    local s = (config.validate({ music = { rim = false } }))
    eq(s.music.rim, false, "the master reads")
    eq((config.validate({ music = { rim = true }, bar = { foot_visualizer = false } })).music.rim, true, "the master wins when both are present")
    eq((config.validate({ bar = { foot_visualizer = false } })).music.rim, false, "the old switch is read when the master is absent")
    eq((config.validate({ bar = { foot_visualizer = true } })).music.rim, true, "including on")
    eq(config.defaults().music.rim, true, "on by default")
end)
test("config: the rim's strength and glow", function()
    eq(config.defaults().music.rim_gain, 100, "100 by default")
    eq(config.defaults().music.rim_glow, true, "glow by default")
    local s, problems = config.validate({ music = { rim_gain = 300 } })
    eq(s.music.rim_gain, 100, "out of range falls back")
    eq(#problems, 1, "and is reported")
    eq((config.validate({ music = { rim_gain = 25 } })).music.rim_gain, 25, "the low end")
    eq((config.validate({ music = { rim_gain = 150 } })).music.rim_gain, 150, "the high end")
end)
test("config: the screen frame's music is off by default", function()
    eq(config.defaults().frame.music, false, "retired unless asked for")
end)

test("vizfeed: publishing is capped at 30 a second and keeps alive at 2 Hz", function()
    local a = vizfeed.silent(1); a.bands[1] = 0.9
    local b = vizfeed.silent(2); b.bands[1] = 0.9
    eq(vizfeed.should_publish(a, b, 100, 0, 500), true, "50 ms since the last publish")
    eq(vizfeed.should_publish(a, b, 520, 500, 500), false, "same bands, not yet due")
    eq(vizfeed.should_publish(a, b, 1000, 500, 500), true, "the keepalive wins")
    local changed = vizfeed.silent(3); changed.bands[1] = 0.1
    eq(vizfeed.should_publish(a, changed, 520, 500, 500), true, "a real change goes at once")
end)

local wire = require("bmo/wire")
local geom = require("bmo/geom")
test("wire: a message survives as one word, whatever it holds", function()
    local messages = {
        "hello",
        [[he said "hi" and 'bye']],
        [[back\\slash and \n literally]],
        [[semi;colons {braces} $(echo) `x` & | > <]],
        "line one\nline two\ttabbed\r\n",
        "h\195\169llo \226\128\148 BMO \226\153\170 \226\152\133 \230\151\165\230\156\172\232\170\158 \240\159\142\137",
        "",
    }
    for _, m in ipairs(messages) do
        local token = wire.encode(m)
        eq(token:find("%s"), nil, "no whitespace in a token")
        eq(wire.decode(token), m, "round trip of " .. m)
    end
    local long = string.rep("BMO says a great deal. ", 400)
    eq(#long > 8000, true, "a long one")
    eq(wire.decode(wire.encode(long)), long, "and it comes back whole")
    eq(wire.encode(""), wire.EMPTY, "an empty message is one mark")
    eq(wire.decode(wire.EMPTY), "", "and reads back as nothing")
    eq(wire.decode(""), "", "an unset text is nothing too")
    eq(type(wire.decode("not base64!?")), "string", "garbage is skipped, not raised")
end)
test("wire: both ends speak one protocol", function()
    local said = [[what's "next"?]] .. "\nand \1674; {here}\\"
    local token = wire.ask(said):match("^text nb_q (%S+)$")
    assert(token, "the ask is one word after the name")
    eq(wire.asked({ nb_q = token }), said, "what the notch hears")
    local answer = "BMO is 100% here {not JSON}; \"quoted\""
    local atoken = wire.say(answer):match("^text bmo_line (%S+)$")
    assert(atoken, "the answer is one word after the name")
    eq(wire.said({ bmo_line = atoken }), answer, "what BMO says")
    eq(wire.asked({}), "", "nothing said is nothing")
    eq(type(wire.said({ bmo_line = "zz!!" })), "string", "garbage still reads")
end)
test("geom: his monitor, and where he goes when the screens change", function()
    local mons = geom.monitors({
        { name = "DP-1", width = 2560, height = 1440, scale = 1, x = 0, y = 0, focused = false, id = 0 },
        { name = "HDMI-A-1", width = 3840, height = 2160, scale = 2, x = 2560, y = 0, focused = true, id = 1 },
        { name = "DP-2", width = 1920, height = 1080, scale = 1, disabled = true, id = 2 },
    })
    eq(#mons, 2, "a disabled output is not a place to stand")
    eq(mons[2].w, 1920, "logical width"); eq(mons[2].h, 1080, "logical height")
    eq(mons[2].x, 2560, "where it is laid out")
    eq(geom.choose(mons, "DP-1", nil, nil).name, "DP-1", "the one he was on")
    eq(geom.choose(mons, "GONE", 1920, 1080).name, "HDMI-A-1", "gone: the one shaped like his surface")
    eq(geom.choose(mons, "GONE", 800, 600).name, "HDMI-A-1", "no match: the focused one")
    eq(geom.choose({}, "DP-1", 1920, 1080), nil, "nothing to stand on")
    local prev = { name = "DP-1", w = 2560, h = 1440 }
    local x, y = geom.fit(prev, { name = "DP-1", w = 2560, h = 1440 }, 1200, 700, true)
    eq(x, 1200, "an ordinary measure moves him not at all"); eq(y, 700)
    local bx, by = geom.fit(prev, { name = "DP-1", w = 5120, h = 2880 }, 1200, 700, true)
    eq(bx, 2400, "in proportion on a bigger screen"); eq(by, 1400, "and down it")
    local mx, my = geom.fit(prev, { name = "HDMI-A-1", w = 1920, h = 1080 }, 1200, 700, true)
    eq(mx, 1200, "another monitor: he is not scaled"); eq(my, 700)
    eq((geom.fit(prev, { name = "DP-1", w = 5120, h = 2880 }, 1200, 700, false)), 1200, "not standing yet: untouched")
end)

local settingsfile = require("lib/settingsfile")
print("vizfeed v2")
do
    local vf = require("lib/vizfeed")
    test("v2 round-trips 64 bands; v1 still decodes", function()
        local b = {}
        for i = 1, 64 do b[i] = i / 64 end
        local t = vf.decode_v2(vf.encode_v2({ bands = b, bass = 0.5, high = 0.25, beat = 1, phase = 0.5, playing = true, seq = 9 }))
        eq(#t.bands, 64, "64"); eq(math.abs(t.bands[64] - 1) < 0.002, true, "last"); eq(t.seq, 9, "seq"); eq(t.playing, true, "playing")
        eq(vf.decode_v2(vf.encode(vf.silent(3))), nil, "a v1 line is not v2")
        eq(vf.decode(vf.encode(vf.silent(3))).seq, 3, "v1 unchanged")
    end)
    test("resample 64→16 averages and keeps endpoints", function()
        local b = {}
        for i = 1, 64 do b[i] = (i <= 4) and 1 or 0 end
        local r = vf.resample(b, 16)
        eq(#r, 16, "16"); eq(r[1], 1, "first group"); eq(r[16], 0, "last")
    end)
    test("resample 32→128 has no gaps", function()
        local b = {}
        for i = 1, 32 do b[i] = 0.2 + 0.6 * ((i % 2 == 0) and 1 or 0) end
        local r = vf.resample(b, 128)
        eq(#r, 128, "128"); eq(math.abs(r[1] - b[1]) < 1e-9, true, "start"); eq(math.abs(r[128] - b[32]) < 1e-9, true, "end")
        for i = 1, 128 do if r[i] < 0.19 then error("gap at " .. i) end end
    end)
    test("resample n=1 is the mean", function()
        eq(vf.resample({ 0, 1 }, 1)[1], 0.5, "mean")
    end)
end

print("settingsfile")
test("changes: only the leaves that moved, with their key path", function()
    local before = { bar = { labels = true, wheel = "step" }, theme = { source = "wallpaper" } }
    local after = { bar = { labels = false, wheel = "step" }, theme = { source = "wallpaper" } }
    local c = settingsfile.changes(before, after)
    eq(#c, 1, "one change")
    eq(table.concat(c[1].keys, "."), "bar.labels", "path")
    eq(c[1].value, false, "value")
end)
test("changes: a list is replaced whole, not key by key", function()
    local before = { bar = { left = { "workspaces", "window" } } }
    local after = { bar = { left = { "workspaces", "media" } } }
    local c = settingsfile.changes(before, after)
    eq(#c, 1, "one change")
    eq(table.concat(c[1].keys, "."), "bar.left", "path")
    eq(c[1].value[2], "media", "whole list")
end)
test("merge: a foreign change is kept and ours laid over it", function()
    local disk = { bar = { labels = true, wheel = "off" }, island = { confirm_close = true } }
    local before = { bar = { labels = true, wheel = "step" } }
    local mine = { bar = { labels = true, wheel = "step" }, island = { confirm_close = false } }
    settingsfile.merge(disk, settingsfile.changes(before, mine))
    eq(disk.bar.wheel, "off", "the bar's own change is kept")
    eq(disk.island.confirm_close, false, "ours is written")
end)
test("changes/merge: a token key with dots stays one key", function()
    local before = { theme = { overrides = {} } }
    local mine = { theme = { overrides = { ["accent.primary"] = "#FF00FF" } } }
    local c = settingsfile.changes(before, mine)
    eq(#c, 1, "one change")
    eq(table.concat(c[1].keys, "|"), "theme|overrides|accent.primary", "keys")
    local disk = { theme = { overrides = { ["fg.muted"] = "#111111" } } }
    settingsfile.merge(disk, c)
    eq(disk.theme.overrides["accent.primary"], "#FF00FF", "ours")
    eq(disk.theme.overrides["fg.muted"], "#111111", "the other override is kept")
end)
test("copy: a snapshot does not alias the settings", function()
    local s = { bar = { labels = true } }
    local c = settingsfile.copy(s)
    s.bar.labels = false
    eq(c.bar.labels, true, "the snapshot kept the old value")
end)



local themeprofiles = require("lib/themeprofiles")
print("notch · wallhaven")
test("the search asks for safe pictures the screen's size and shape, a colour when one is chosen", function()
    local u = notch.wallhaven_url(3, -1, 1920, 1080)
    assert(u:find("purity=100", 1, true), "sfw only"); assert(u:find("atleast=1920x1080", 1, true), "size")
    assert(u:find("ratios=16x9", 1, true), "shape"); assert(u:find("page=3", 1, true), "page"); assert(not u:find("colors="), "no colour")
    assert(notch.wallhaven_url(1, 0, 1920, 1080):find("colors=cc0000", 1, true), "reds")
    assert(notch.wallhaven_url(1, 11, 2560, 1080):find("ratios=21x9", 1, true), "ultrawide snaps to 21x9")
    assert(notch.wallhaven_url(1, -1, 0, 0):find("atleast=1920x1080", 1, true), "an unknown screen falls back")
end)
test("an answer gives its pictures and pages; anything off Wallhaven's hosts is dropped", function()
    local list, last = notch.wallhaven_page({
        meta = { last_page = 40 },
        data = {
            { id = "yqkl97", path = "https://w.wallhaven.cc/full/yq/wallhaven-yqkl97.jpg", resolution = "2074x1166", purity = "sfw",
              thumbs = { small = "https://th.wallhaven.cc/small/yq/yqkl97.jpg" } },
            { id = "bad id", path = "https://w.wallhaven.cc/full/x.jpg", thumbs = { small = "https://th.wallhaven.cc/s.jpg" } },
            { id = "evil1", path = "https://example.com/x.jpg", thumbs = { small = "https://th.wallhaven.cc/s.jpg" } },
            { id = "nsfw1", path = "https://w.wallhaven.cc/full/a.png", purity = "nsfw", thumbs = { small = "https://th.wallhaven.cc/s.jpg" } },
            { id = "quote1", path = "https://w.wallhaven.cc/full/a'b.jpg", thumbs = { small = "https://th.wallhaven.cc/s.jpg" } },
        },
    })
    eq(#list, 1, "kept"); eq(last, 40, "pages"); eq(list[1].id, "yqkl97", "id"); eq(list[1].ext, "jpg", "ext")
    eq(list[1].thumb, "https://th.wallhaven.cc/small/yq/yqkl97.jpg", "thumb")
    eq(notch.wallhaven_page({ error = "x" }), nil, "not an answer")
end)

print("theme packages")
test("capture exports a complete visual profile but no personal or behavioural settings", function()
    local current = config.defaults()
    current.keys = { overview = "SUPER + Tab" }
    current.nexus = { identity = { name = "private name" } }
    current.integration_private = { enabled = true }
    local package, why = themeprofiles.capture(current, "Foundry", "Graphite and phosphor")
    eq(package ~= nil, true, "captured: " .. tostring(why)); eq(why, nil, "no error")
    eq(package.format, "mooi-theme", "format"); eq(package.version, 1, "version")
    eq(package.name, "Foundry", "name")
    eq(package.settings.theme.mode, current.theme.mode, "theme mode")
    eq(package.settings.look.corners, current.look.corners, "geometry")
    eq(package.settings.fx.glow, current.fx.glow, "effects")
    eq(package.settings.bar.surface, current.bar.surface, "bar material")
    eq(package.settings.keys, nil, "shortcuts excluded")
    eq(package.settings.nexus, nil, "identity excluded")
    eq(package.settings.bar.left, nil, "bar layout excluded")
    eq(package.settings.integration_private, nil, "unknown extension data excluded")
end)
test("theme package validation rejects malformed metadata and unsupported versions", function()
    local p = { format = "mooi-theme", version = 1, name = "Valid", settings = { theme = { mode = "dark" } } }
    local ok = themeprofiles.validate(p); eq(ok ~= nil, true, "valid package")
    local bad = themeprofiles.validate({ format = "other", version = 1, name = "X", settings = { theme = { mode = "dark" } } })
    eq(bad, nil, "wrong format")
    local future = themeprofiles.validate({ format = "mooi-theme", version = 99, name = "X", settings = { theme = { mode = "dark" } } })
    eq(future, nil, "future version")
    local empty = themeprofiles.validate({ format = "mooi-theme", version = 1, name = "", settings = { theme = { mode = "dark" } } })
    eq(empty, nil, "empty name")
    local blank = themeprofiles.validate({ format = "mooi-theme", version = 1, name = "   ", settings = { theme = { mode = "dark" } } })
    eq(blank, nil, "blank name")
    local extra = themeprofiles.validate({ format = "mooi-theme", version = 1, name = "X", execute = "anything",
        settings = { theme = { mode = "dark" } } })
    eq(extra, nil, "unknown metadata refused")
end)
test("theme package validation refuses unknown settings and behavioural payloads", function()
    local base = { format = "mooi-theme", version = 1, name = "Safe", settings = { theme = { mode = "dark" } } }
    local unknown = themeprofiles.validate({ format = base.format, version = base.version, name = base.name,
        settings = { theme = { mode = "dark" }, keys = { overview = "SUPER + Q" } } })
    eq(unknown, nil, "shortcuts are not theme data")
    local unknown_leaf = themeprofiles.validate({ format = base.format, version = base.version, name = base.name,
        settings = { theme = { mode = "dark", surprise = true } } })
    eq(unknown_leaf, nil, "unknown theme fields refused")
    local invalid = themeprofiles.validate({ format = base.format, version = base.version, name = base.name,
        settings = { theme = { mode = "daydream" } } })
    eq(invalid, nil, "invalid enum refused")
end)
test("theme packages reject invalid colours and unknown semantic tokens", function()
    local function package(overrides)
        return { format = "mooi-theme", version = 1, name = "Colours", settings = { theme = { overrides = overrides } } }
    end
    eq(themeprofiles.validate(package({ ["accent.primary"] = "#A6F3D1" })) ~= nil, true, "known token")
    eq(themeprofiles.validate(package({ ["accent.primary"] = "#GG00FF" })), nil, "malformed hex")
    eq(themeprofiles.validate(package({ ["accent.unknown"] = "#A6F3D1" })), nil, "unknown token")
end)
test("applying a package changes visual settings only and preserves unrelated data", function()
    local current = config.defaults()
    current.keys = { overview = "SUPER + Tab" }
    current.nexus = { identity = { name = "private name" } }
    current.bar.left = { "clock", "workspaces" }
    current.external = { retained = "yes" }
    local package = {
        format = "mooi-theme", version = 1, name = "Light Foundry",
        settings = { theme = { mode = "light", overrides = { ["accent.primary"] = "#A6F3D1" } },
                     look = { corners = "square", corner_size = 4 }, fx = { glow = 0 } }
    }
    local applied, why = themeprofiles.apply(current, package)
    eq(applied ~= nil, true, "applied"); eq(why, nil, "no error")
    eq(applied.theme.mode, "light", "mode changed")
    eq(applied.theme.overrides["accent.primary"], "#A6F3D1", "override applied")
    eq(applied.look.corners, "square", "geometry changed")
    eq(applied.keys.overview, "SUPER + Tab", "shortcuts kept")
    eq(applied.nexus.identity.name, "private name", "identity kept")
    eq(applied.bar.left[1], "clock", "layout kept")
    eq(applied.external.retained, "yes", "unknown extension data kept")
    eq(current.theme.mode, "dark", "source document not mutated")
end)
test("captured packages are independent copies and empty packages are refused", function()
    local current = config.defaults()
    current.theme.overrides = {}
    local package = themeprofiles.capture(current, "Copy")
    package.settings.theme.overrides["accent.primary"] = "#A6F3D1"
    eq(current.theme.overrides["accent.primary"], nil, "no alias to source")
    local empty = themeprofiles.validate({ format = "mooi-theme", version = 1, name = "Empty", settings = {} })
    eq(empty, nil, "empty package refused")
end)

local components = require("lib/components")
print("components")
test("catalogue lists the existing button surfaces in stable order", function()
    local ids = components.ids()
    eq(#ids, 1, "registered components (Lumen's went with the wallpaper studio, D118)")
    eq(ids[1], "ferrolume.button", "first id")
    eq(#components.list("actions"), 1, "action category")
    eq(components.get("missing"), nil, "unknown id")
end)
test("descriptors are defensive copies", function()
    local a = components.get("ferrolume.button")
    a.properties[1].name = "injected"
    local b = components.get("ferrolume.button")
    eq(b.properties[1].name, "x", "registry is not mutated by editor")
end)
test("Ferrolume editor properties accept bounded layout and appearance values", function()
    local ok, problems = components.validate("ferrolume.button", { x = 10, y = 20, w = 120, label = "Open", hot = true, en = false })
    eq(ok, true, "valid properties"); eq(#problems, 0, "no problems")
end)
test("editor validation refuses out-of-range and unknown executable fields", function()
    local ok, problems = components.validate("ferrolume.button", { x = 0, y = 0, w = 900, label = "Open", onClick = "os.execute('bad')" })
    eq(ok, false, "invalid properties rejected")
    eq(#problems, 2, "range and unknown field rejected")
end)
test("defaults are available without exposing event wiring", function()
    local d = components.defaults("ferrolume.button")
    eq(d.w, 104, "width default"); eq(d.label, "Action", "label default")
    eq(d.press, nil, "event is not a property")
end)
test("component metadata records implemented and missing states honestly", function()
    local d = components.get("ferrolume.button")
    eq(d.states[1].implemented, true, "enabled state")
    eq(d.states[3].implemented, false, "pressed state not falsely claimed")
    eq(d.events[1].name, "press", "event name")
end)


local W = require("lib/widgets")
local S = { w = 1920, h = 1080, top = 34 }
local json_decode_stub = decode_table(nil)
print("widgets")
test("widgets.on survives a reload", function()
    local s = config.parse("x", decode_table({ version = 2, widgets = { on = false } }))
    eq(s.widgets.on, false, "kept off")
    eq(config.parse(nil, decode_broken).widgets.on, true, "on by default")
end)
test("missing file gives one sleeve bottom-left", function()
    local d = W.parse(nil, json_decode_stub, S)
    eq(#d.widgets, 1, "count"); eq(d.widgets[1].layout, "sleeve", "layout")
    eq(d.widgets[1].x, 64, "x"); eq(d.widgets[1].y, 1080 - 152 - 64, "y"); eq(d.widgets[1].idle, "rest", "idle")
end)
test("broken file gives defaults and marks bad", function()
    local d, p = W.parse("{x", decode_broken, S); eq(d.bad, true, "bad"); eq(#d.widgets, 1, "defaults"); eq(#p > 0, true, "problem logged")
end)
test("unknown kind, layout and mode are dropped", function()
    local d = W.parse("", decode_table({ version = 1, widgets = {
        { id = "a", kind = "clock" }, { id = "b", kind = "nowplaying", layout = "poster", x = 0, y = 40, w = 300, h = 120 },
        { id = "c", kind = "visualiser", mode = "lava", x = 0, y = 40, w = 300, h = 100 } } }), S)
    eq(#d.widgets, 0, "all dropped")
end)
test("sizes clamp to the layout and to 8 px", function()
    local w = { kind = "nowplaying", layout = "sleeve" }
    local a, b = W.clamp_size(w, 100, 50); eq(a, 288, "min w"); eq(b, 104, "min h")
    a, b = W.clamp_size(w, 2000, 2000); eq(a, 864, "max w"); eq(b, 304, "max h")
    a, b = W.clamp_size(w, 433, 157); eq(a % 8, 0, "grid w"); eq(b % 8, 0, "grid h")
end)
test("record keeps its aspect", function()
    local a, b = W.clamp_size({ kind = "nowplaying", layout = "record" }, 400, 300)
    eq(math.abs(a / b - 280 / 352) < 0.03, true, "aspect")
end)
test("clamp_rect keeps a widget on screen and under the bar", function()
    local w = W.clamp_rect({ kind = "nowplaying", layout = "sleeve", x = 1800, y = 0, w = 432, h = 152 }, S)
    eq(w.x, 1920 - 432, "right edge"); eq(w.y >= 34, true, "below bar")
end)
test("snap pulls to grid, edges and other widgets", function()
    local d = W.parse("", decode_table({ version = 1, widgets = {
        { id = "np-1", kind = "nowplaying", layout = "sleeve", x = 64, y = 600, w = 432, h = 152, idle = "rest" },
        { id = "viz-1", kind = "visualiser", mode = "dust", x = 600, y = 300, w = 640, h = 160, idle = "hide" } } }), S)
    local x, y, _, _, g = W.snap(d, 2, 501, 303, 640, 160, S)
    eq(x, 496, "snapped to np-1's right edge"); eq(g.vx, 496, "vertical guide"); eq(y % 8, 0, "grid y")
    x = W.snap(d, 2, 3, 300, 640, 160, S); eq(x, 0, "screen edge")
end)
test("free_spot avoids existing widgets", function()
    local d = W.defaults(1920, 1080)
    local d2, id = W.add(d, "nowplaying", S)
    local a, b = d2.widgets[1], d2.widgets[2]
    local overlap = a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
    eq(overlap, false, "no overlap"); eq(id, "np-2", "next id")
end)
test("set_layout keeps place, takes the new default size", function()
    local d = W.set_layout(W.defaults(1920, 1080), "np-1", "record", S)
    eq(d.widgets[1].x, 64, "x kept"); eq(d.widgets[1].w, 280, "record w"); eq(d.widgets[1].y + d.widgets[1].h <= 1080, true, "on screen")
end)
test("duplicate ids are renumbered; more than 12 are dropped", function()
    local list = {}
    for i = 1, 14 do list[i] = { id = "np-1", kind = "nowplaying", layout = "sleeve", x = 0, y = 40, w = 288, h = 104 } end
    local d = W.parse("", decode_table({ version = 1, widgets = list }), S)
    eq(#d.widgets, 12, "cap"); eq(d.widgets[2].id ~= d.widgets[1].id, true, "unique")
end)
test("idle_state follows the rule", function()
    eq(W.idle_state({ idle = "rest" }, true), "shown", "playing")
    eq(W.idle_state({ idle = "rest" }, false), "rest", "rest"); eq(W.idle_state({ idle = "hide" }, false), "hidden", "hide")
    eq(W.idle_state({ idle = "marker" }, false), "marker", "marker")
end)
test("pack stays under 2^24 and round-trips", function()
    local n = W.pack(7, 239, 134); eq(n < 16777216, true, "float32 safe")
    local s, gx, gy = W.unpack(n); eq(s, 7, "slot"); eq(gx, 239, "gx"); eq(gy, 134, "gy")
end)
test("set_mode, set_idle and set_option change one widget and ignore nonsense", function()
    local d = W.add(W.defaults(1920, 1080), "visualiser", S)
    d = W.set_mode(d, "viz-1", "ripple"); eq(d.widgets[2].mode, "ripple", "mode")
    d = W.set_mode(d, "viz-1", "lava"); eq(d.widgets[2].mode, "ripple", "unknown mode ignored")
    d = W.set_idle(d, "viz-1", "marker"); eq(d.widgets[2].idle, "marker", "idle")
    d = W.set_option(d, "viz-1", "glow", 3); eq(d.widgets[2].options.glow, 1, "glow clamped")
    d = W.set_option(d, "np-1", "plate", true); eq(d.widgets[1].options.plate, true, "plate")
    d = W.set_option(d, "np-1", "nonsense", true); eq(d.widgets[1].options.nonsense, nil, "unknown option ignored")
    eq(W.OPTIONS.visualiser.mirror, nil, "no mirror option: the Mirror mode is the mirror")
end)
test("set_rect commits a clamped rectangle", function()
    local d = W.set_rect(W.defaults(1920, 1080), "np-1", 1900, 500, 5000, 50, S)
    local w = d.widgets[1]; eq(w.w, 864, "max w"); eq(w.h, 104, "min h"); eq(w.x + w.w <= 1920, true, "on screen")
end)
test("panel_spot opens beside the widget, on the side with room", function()
    local x, y = W.panel_spot({ x = 64, y = 600, w = 432, h = 152 }, 240, 300, S)
    eq(x, 64 + 432 + 12, "right of it"); eq(y + 300 <= 1080, true, "on screen")
    x = W.panel_spot({ x = 1600, y = 100, w = 300, h = 100 }, 240, 300, S)
    eq(x, 1600 - 12 - 240, "left when the right has no room")
    local y
    x, y = W.panel_spot({ x = 0, y = 846, w = 1920, h = 200 }, 248, 286, S)
    eq(y, 846 - 12 - 286, "above a full-width widget, not over it")
    x, y = W.panel_spot({ x = 0, y = 40, w = 1920, h = 200 }, 248, 286, S)
    eq(y, 40 + 200 + 12, "below it when there is no room above")
end)
test("should_reload: a file equal to what is shown is skipped, any other file is read", function()
    local d1 = W.defaults(1920, 1080)
    local d2 = W.set_idle(d1, "np-1", "hide")
    eq(W.should_reload(W.encode(d1), d1), false, "our own echo")
    eq(W.should_reload(W.encode(d1), d2), true, "settings put it back to an older doc: still read")
end)
test("prune_hover drops slots that no longer exist", function()
    local h = W.prune_hover({ [0] = true, [3] = true, [7] = true }, 2)
    eq(h[0], true, "kept"); eq(h[3], nil, "gone"); eq(h[7], nil, "gone")
end)
local function doc3()
    return W.parse("", decode_table({ version = 1, widgets = {
        { id = "np-1", kind = "nowplaying", layout = "sleeve", x = 64, y = 100, w = 432, h = 152 },
        { id = "np-2", kind = "nowplaying", layout = "sleeve", x = 600, y = 300, w = 432, h = 152 },
        { id = "viz-1", kind = "visualiser", mode = "dust", x = 1200, y = 600, w = 640, h = 160 } } }), S)
end
test("v1 file loads as v2 defaults", function()
    local d = doc3()
    eq(d.version, 2, "version"); eq(d.widgets[3].options.bars, 64, "bars"); eq(d.widgets[1].opacity, 1, "opacity")
    eq(d.widgets[1].locked, false, "locked"); eq(d.widgets[1].options.text, 1, "text size")
    eq(W.encode(d).version, 2, "written as 2"); eq(W.encode(d).widgets[2].z, 2, "z is the order")
end)
test("options clamp to their ranges", function()
    local d = W.set_option(doc3(), "viz-1", "bars", 500); eq(d.widgets[3].options.bars, 128, "bars max")
    d = W.set_option(d, "viz-1", "bars", 3); eq(d.widgets[3].options.bars, 16, "bars min")
    d = W.set_option(d, "viz-1", "gap", 0.9); eq(d.widgets[3].options.gap, 0.6, "gap")
    d = W.set_option(d, "np-1", "text", 3); eq(d.widgets[1].options.text, 1.4, "text")
    d = W.set_field(d, "np-1", "opacity", 0.1); eq(d.widgets[1].opacity, 0.3, "opacity floor")
end)
test("align left lines lefts; align skips locked", function()
    local d, sk = W.align(doc3(), { "np-1", "np-2" }, "left", S)
    eq(d.widgets[2].x, 64, "lined up"); eq(sk, 0, "none skipped")
    d = W.set_field(doc3(), "np-2", "locked", true)
    d, sk = W.align(d, { "np-1", "np-2", "viz-1" }, "top", S)
    eq(d.widgets[2].y, 300, "locked stays"); eq(d.widgets[3].y, 100, "others align"); eq(sk, 1, "one skipped")
end)
test("distribute spaces evenly", function()
    local d = W.distribute(doc3(), { "np-1", "np-2", "viz-1" }, "h", S)
    local g1 = d.widgets[2].x - (d.widgets[1].x + d.widgets[1].w)
    local g2 = d.widgets[3].x - (d.widgets[2].x + d.widgets[2].w)
    eq(math.abs(g1 - g2) <= 1, true, "equal gaps")
end)
test("match width", function()
    local d = W.match(doc3(), { "np-2", "np-1" }, "w", S); eq(d.widgets[1].w, 432, "matched to the first")
    d = W.match(doc3(), { "viz-1", "np-1" }, "w", S); eq(d.widgets[1].w, 640, "clamped into sleeve range")
end)
test("nudge clamps on screen", function()
    local d = W.nudge(doc3(), { "np-1" }, -500, 8, S); eq(d.widgets[1].x, 0, "left edge"); eq(d.widgets[1].y, 108, "down 8")
end)
test("resize from left keeps right edge at min", function()
    local d = doc3()
    local x, y, w, h = W.resize_from(d, "np-1", 7, 1000, 0, S)
    eq(w, 288, "min width"); eq(x + w, 64 + 432, "right edge fixed"); eq(y, 100, "y kept")
end)
test("resize tl keeps record aspect", function()
    local d = W.set_layout(doc3(), "np-1", "record", S)
    local x, y, w, h = W.resize_from(d, "np-1", 0, -100, -100, S)
    eq(math.abs(w / h - 280 / 352) < 0.04, true, "aspect")
    eq(x + w, d.widgets[1].x + d.widgets[1].w, "right fixed"); eq(y + h, d.widgets[1].y + d.widgets[1].h, "bottom fixed")
end)
test("resize a record from the left near the edge keeps its right edge", function()
    local d = W.parse("", decode_table({ version = 2, widgets = {
        { id = "np-1", kind = "nowplaying", layout = "record", x = 15, y = 400, w = 280, h = 352 } } }), S)
    local x, y, w, h = W.resize_from(d, "np-1", 0, -300, -300, S)
    eq(x + w, 15 + 280, "right edge"); eq(x >= 0, true, "on screen")
end)
test("marquee selects touched", function()
    local m = W.marquee(doc3(), 0, 0, 700, 350)
    local ids = W.ids_of(doc3(), m)
    eq(#ids, 2, "two touched"); eq(ids[1], "np-1", "first"); eq(W.mask_of(doc3(), ids), m, "round trip")
end)
test("raise front/back reorders", function()
    local d = W.raise(doc3(), { "np-1" }, "front"); eq(d.widgets[3].id, "np-1", "front is last")
    d = W.raise(d, { "np-1" }, "back"); eq(d.widgets[1].id, "np-1", "back is first")
    d = W.raise(d, { "np-1" }, "forward"); eq(d.widgets[2].id, "np-1", "one forward")
end)
test("history undo/redo round-trip; cleared; caps at 30", function()
    local h = W.history()
    local a, b = doc3(), W.nudge(doc3(), { "np-1" }, 8, 0, S)
    W.push(h, a)
    local back = W.undo(h, b); eq(back.widgets[1].x, 64, "undone")
    local fwd = W.redo(h, back); eq(fwd.widgets[1].x, 72, "redone")
    W.clear(h); eq(W.undo(h, fwd), nil, "nothing after clear"); eq(#h.redo, 0, "redo cleared")
    for i = 1, 40 do W.push(h, a) end
    eq(#h.undo, 30, "capped")
end)
test("at most three visualisers: add and duplicate refuse a fourth, parse drops it", function()
    local d = W.defaults(1920, 1080)
    local id
    for i = 1, 3 do d, id = W.add(d, "visualiser", S); eq(id ~= nil, true, "visualiser " .. i) end
    local _, four = W.add(d, "visualiser", S); eq(four, nil, "no fourth")
    local _, dup = W.duplicate(d, "viz-1", S); eq(dup, nil, "no duplicate either")
    local list = {}
    for i = 1, 4 do list[i] = { kind = "visualiser", mode = "dust", x = 0, y = 40, w = 300, h = 100 } end
    eq(#W.parse("", decode_table({ version = 2, widgets = list }), S).widgets, 3, "parse keeps three")
end)
test("adapt and behind: every widget has them, adapt on and behind off by default", function()
    local d = W.add(W.defaults(1920, 1080), "visualiser", S)
    eq(d.widgets[1].options.adapt, true, "np adapt"); eq(d.widgets[1].options.behind, false, "np behind")
    eq(d.widgets[2].options.adapt, true, "viz adapt"); eq(d.widgets[2].options.behind, false, "viz behind")
    d = W.set_option(d, "viz-1", "behind", true); eq(d.widgets[2].options.behind, true, "set")
end)
test("widgets.depth and widgets.mood: on by default, kept off", function()
    local s0 = config.parse(nil, decode_broken)
    eq(s0.widgets.depth, true, "depth on"); eq(s0.widgets.mood, true, "mood on")
    local s1 = config.parse("x", decode_table({ version = 2, widgets = { depth = false, mood = false } }))
    eq(s1.widgets.depth, false, "depth kept off"); eq(s1.widgets.mood, false, "mood kept off")
end)
test("same_doc ignores own write", function()
    local d = W.defaults(1920, 1080); eq(W.same_doc(W.encode(d), W.encode(d)), true, "equal")
end)

print("wallmap")
do
    local WM = require("lib/wallmap")
    local W2 = require("lib/widgets")
    local SC = { w = 1920, h = 1046, top = 0 }
    -- a 32x18 map: dark left half, bright right half; a subject block in cells 10..15 x 4..13
    local function fake()
        local cells = {}
        for r = 0, 17 do for c = 0, 31 do
            local subj = c >= 10 and c <= 15 and r >= 4 and r <= 13
            cells[#cells + 1] = { l = (c < 16) and 0.1 or 0.9, a = 0.3, b = -0.2, d = subj and 0.6 or 0.05, s = subj and 1 or 0 }
        end end
        return { cols = 32, rows = 18, cells = cells, mood = { luma = 0.5, sat = 0.2, contrast = 0.5, detail = 0.1 }, cut = true, depth = true, w = 1920, h = 1080 }
    end
    test("wallmap parse refuses junk, keeps a map", function()
        eq(WM.parse(nil), nil, "nil"); eq(WM.parse({ cols = 32 }), nil, "no cells")
        eq(WM.parse(fake()).cols, 32, "kept")
        local f = fake(); f.cutpath = "/x/cut.png"
        eq(WM.parse(f).cutpath, "/x/cut.png", "the cut-out's path is kept")
    end)
    test("under averages light and colour, takes the most subject", function()
        local m = WM.parse(fake())
        local u = WM.under(m, 0, 0, 200, 200, SC); eq(u.l < 0.2, true, "dark corner"); eq(u.s, 0, "no subject")
        u = WM.under(m, 1700, 900, 200, 120, SC); eq(u.l > 0.8, true, "bright corner")
        u = WM.under(m, 600, 300, 200, 200, SC); eq(u.s, 1, "over the subject")
    end)
    test("tone: dark text on light, light on dark", function()
        eq(WM.tone(0.9), "dark", "light ground"); eq(WM.tone(0.1), "light", "dark ground")
    end)
    test("haze grows with detail and mid greys, inside 0..1", function()
        eq(WM.haze(0, 0.1) < WM.haze(0.8, 0.1), true, "busier is hazier")
        eq(WM.haze(0.2, 0.5) > WM.haze(0.2, 0.1), true, "mid grey is hazier")
        eq(WM.haze(1, 0.5) <= 1, true, "at most 1")
    end)
    test("accent keeps 4.5:1 against the ground", function()
        for _, ground in ipairs({ { r = 0.02, g = 0.03, b = 0.03 }, { r = 0.95, g = 0.95, b = 0.95 } }) do
            local c = WM.accent({ l = 0.5, a = 0.3, b = -0.2 }, { r = 0.6, g = 0.8, b = 0.7 }, ground)
            eq(WM.contrast(c, ground) >= 4.5, true, "contrast")
            eq(c.r >= 0 and c.r <= 1 and c.g >= 0 and c.b <= 1, true, "in range")
        end
    end)
    test("calm_spot avoids the subject and the other widgets", function()
        local m = WM.parse(fake())
        local d = W2.parse("", decode_table({ version = 2, widgets = {
            { id = "np-1", kind = "nowplaying", layout = "sleeve", x = 600, y = 300, w = 432, h = 152 },
            { id = "np-2", kind = "nowplaying", layout = "sleeve", x = 1100, y = 300, w = 432, h = 152 } } }), SC)
        local x, y = WM.calm_spot(m, d, 1, SC)
        eq(x ~= nil, true, "found one")
        local u = WM.under(m, x, y, 432, 152, SC); eq(u.s < 0.15, true, "off the subject")
        local o = d.widgets[2]
        eq(x < o.x + o.w and o.x < x + 432 and y < o.y + o.h and o.y < y + 152, false, "not on the other")
    end)
    local PH, HULL = { r = 0.6, g = 0.8, b = 0.7 }, { r = 0.06, g = 0.08, b = 0.08 }
    test("look: dark words on a light-ish spot keep their accent readable on the ground as drawn", function()
        local L = WM.look({ l = 0.62, a = 0.2, b = 0.1, d = 0.3, s = 0, lmin = 0.6, lmax = 0.64 }, { plate = false, phos = PH, hull = HULL })
        eq(L.tn, 1, "dark words"); eq(WM.contrast(L.accent, L.ground) >= 4.5, true, "accent on the drawn ground")
        eq(WM.contrast(L.ink, L.ground) >= 4.5, true, "words on the drawn ground")
    end)
    test("look: a spot half black, half white gets a near-solid haze", function()
        local L = WM.look({ l = 0.5, a = 0, b = 0, d = 0.1, s = 0, lmin = 0.02, lmax = 0.98 }, { plate = false, phos = PH, hull = HULL })
        eq(L.hz >= 0.85, true, "haze carries it")
    end)
    test("look: on a plate the words are light and the accent reads on the plate", function()
        local L = WM.look({ l = 0.9, a = 0.1, b = 0.1, d = 0.1, s = 0, lmin = 0.88, lmax = 0.92 }, { plate = true, phos = PH, hull = HULL })
        eq(L.tn, 0, "light words on the dark plate"); eq(WM.contrast(L.accent, HULL) >= 4.5, true, "accent on the plate")
    end)
    test("under also gives the lightest and darkest cell", function()
        local m = WM.parse(fake())
        local u = WM.under(m, 900, 0, 300, 100, SC)
        eq(u.lmin < 0.2 and u.lmax > 0.8, true, "straddles")
    end)
    test("mood stays in its ranges", function()
        for _, md in ipairs({ { luma = 0, sat = 0, contrast = 0, detail = 0 }, { luma = 1, sat = 1, contrast = 1, detail = 1 } }) do
            local r = WM.mood(md)
            eq(r.glow >= 0.6 and r.glow <= 1.2, true, "glow"); eq(r.pace >= 0.7 and r.pace <= 1.2, true, "pace"); eq(r.soft >= 0 and r.soft <= 1, true, "soft")
        end
    end)
end

print("widgets scene ↔ logic")
test("every fact the widgets logic writes is declared in its scene", function()
    local function slurp(f) local h = assert(io.open(f)); local x = h:read("a"); h:close(); return x end
    local plm, lua = slurp("shell/mooi-widgets.plm"), slurp("shell/mooi-widgets.luau")
    local declared = {}
    for name in plm:gmatch("\n%s*fact%s+([%w_]+)") do declared[name] = true end
    for name in plm:gmatch("\n%s*prop%s+([%w_]+)") do declared[name] = true end
    local missing = {}
    for name in lua:gmatch("fact%.([%w_]+)%s*=[^=]") do if not declared[name] then missing[#missing + 1] = name end end
    for name in lua:gmatch("fact%.([%w_]+)%s*,") do if not declared[name] then missing[#missing + 1] = name end end
    eq(table.concat(missing, ", "), "", "facts written but not declared")
end)
test("every slot the logic can fill has its facts and its model row (W.MAX)", function()
    local function slurp(f) local h = assert(io.open(f)); local x = h:read("a"); h:close(); return x end
    local plm = slurp("shell/mooi-widgets.plm")
    local missing = {}
    for i = 0, W.MAX - 1 do
        for _, f in ipairs({ "op", "hl" }) do
            if not plm:find("\n%s*fact%s+" .. f .. i .. "%s") then missing[#missing + 1] = f .. i end
        end
    end
    eq(table.concat(missing, ", "), "", "slot facts")
    eq(tonumber(plm:match("model wg max (%d+)")), W.MAX, "the model holds W.MAX")
end)

print("clock face")
do
    local CF = require("lib/clockface")
    test("the time in words, rounded to five minutes", function()
        eq(CF.words(16, 10), "ten past four", "past"); eq(CF.words(11, 25), "twenty-five past eleven", "twenty-five")
        eq(CF.words(16, 44), "nearly quarter to five", "nearly, to"); eq(CF.words(17, 0), "five o'clock", "o'clock")
        eq(CF.words(16, 31), "just after half past four", "just after")
    end)
    test("midnight and noon in words", function()
        eq(CF.words(0, 0), "midnight", "midnight"); eq(CF.words(12, 1), "just after noon", "noon")
        eq(CF.words(23, 58), "nearly midnight", "rounds to midnight"); eq(CF.words(0, 15), "quarter past twelve", "after midnight")
    end)
    test("hands' angles", function()
        local a = CF.angles(3, 0, 0); eq(a.hour, 90, "hour"); eq(a.minute, 0, "minute")
        a = CF.angles(15, 30, 30); eq(a.hour, 105, "hour moves with minutes"); eq(a.minute, 183, "minute with seconds"); eq(a.second, 180, "second")
    end)
    test("hh:mm in 24 h and 12 h", function()
        eq(CF.hhmm(16, 5, true), "16:05", "24"); eq(CF.hhmm(16, 5, false), "4:05", "12"); eq(CF.hhmm(0, 7, false), "12:07", "12 at midnight")
        eq(CF.ampm(0), "AM", "am"); eq(CF.ampm(12), "PM", "pm")
    end)
    test("next_due: the earliest due card not done", function()
        local b = { columns = { { id = 1 }, { id = 2 }, { id = 3 } }, cards = {
            { id = 1, col = 1, title = "old", due = 100 }, { id = 2, col = 2, title = "soon", due = 205 },
            { id = 3, col = 3, title = "done one", due = 201 }, { id = 4, col = 1, title = "today's", due = 200 } } }
        local n = CF.next_due(b, 200); eq(n.title, "today's", "today first"); eq(n.label, "TODAY", "label")
        n = CF.next_due(b, 201); eq(n.title, "soon", "skips done and past"); eq(n.label, "SATURDAY", "weekday (day 205 is a Saturday)")
        eq(CF.next_due({ columns = {}, cards = {} }, 200), nil, "none")
    end)
end
print("github")
do
    local GP = require("lib/ghparse")
    local function slurp(f) local h = assert(io.open(f)); local x = h:read("a"); h:close(); return x end
    local MJ = dofile("tests/unit/minijson.lua")
    test("card and commits from the GraphQL answer", function()
        local c = GP.card(MJ.decode(slurp("tests/unit/gh-card.json")), MJ.NULL)
        eq(c.name, "bushninjadots/mooi", "name"); eq(c.lang, "QML", "language"); eq(type(c.stars), "number", "stars")
        eq(#c.commits >= 1, true, "commits"); eq(#c.commits[1].sha, 7, "short hash"); eq(type(c.commits[1].msg), "string", "message")
    end)
    test("runs: state from status and conclusion", function()
        local r = GP.runs(MJ.decode(slurp("tests/unit/gh-runs.json")), MJ.NULL)
        eq(#r >= 1, true, "some"); eq(r[1].branch, "main", "branch")
        eq(GP.run_state("in_progress", nil), "run", "running"); eq(GP.run_state("completed", "success"), "ok", "ok")
        eq(GP.run_state("completed", "failure"), "fail", "fail"); eq(GP.run_state("completed", "cancelled"), "other", "other")
    end)
    test("activity: twelve weeks, or nil while GitHub works it out", function()
        local weeks = {}
        for i = 1, 52 do weeks[i] = { total = i, week = i, days = {} } end
        local a = GP.activity(weeks); eq(#a, 12, "twelve"); eq(a[12], 52, "the last week last")
        eq(GP.activity({}), nil, "202 answers {}"); eq(GP.activity(nil), nil, "nothing")
    end)
    test("junk is refused", function()
        eq(GP.card(nil), nil, "nil"); eq(GP.card({ data = { repository = MJ.NULL } }, MJ.NULL), nil, "no repo"); eq(#GP.runs({}), 0, "no runs")
        eq(GP.repo_ok("bushninjadots/mooi"), true, "ok"); eq(GP.repo_ok("no spaces/x y"), false, "bad")
    end)
    test("ago is short", function()
        eq(GP.ago("2026-11-03T17:00:00Z", GP.utc("2026-11-03T19:30:00Z")), "2 H", "hours")
        eq(GP.ago("2026-11-01T17:00:00Z", GP.utc("2026-11-03T19:30:00Z")), "2 D", "days")
    end)
end
print("widgets · new kinds")
test("clock, notes and github: layouts, defaults and limits", function()
    local d = W.defaults(1920, 1080)
    local id
    d, id = W.add(d, "clock", S); eq(d.widgets[2].layout, "digital", "clock layout"); eq(d.widgets[2].options.h24, true, "24 h")
    d = W.set_layout(d, id, "analogue", S); eq(d.widgets[2].layout, "analogue", "analogue"); eq(d.widgets[2].w, d.widgets[2].h, "analogue is round")
    d = W.set_layout(d, id, "sleeve", S); eq(d.widgets[2].layout, "analogue", "a clock cannot be a sleeve")
    local n1, n2
    d, n1 = W.add(d, "notes", S); eq(n1 ~= nil, true, "notes"); d, n2 = W.add(d, "notes", S); eq(n2, nil, "one notes")
    local g1, g2, g3
    d, g1 = W.add(d, "github", S); d, g2 = W.add(d, "github", S); d, g3 = W.add(d, "github", S)
    eq(g2 ~= nil, true, "two github"); eq(g3, nil, "not three")
    eq(d.widgets[#d.widgets].options.repo, "bushninjadots/mooi", "default repo")
    d = W.set_option(d, g1, "repo", "torvalds/linux"); eq(select(2, W.find(d, g1)).options.repo, "torvalds/linux", "repo set")
    d = W.set_option(d, g1, "repo", "bad repo"); eq(select(2, W.find(d, g1)).options.repo, "torvalds/linux", "a bad repo is ignored")
end)

print("widgets · D141")
test("seven more kinds, one each; only music follows the idle rule", function()
    local d, id = W.defaults(1920, 1080), nil
    for _, k in ipairs({ "weather", "system", "calendar", "timer", "claude", "photo", "launch" }) do
        local id2
        d, id2 = W.add(d, k, S); eq(id2 ~= nil, true, k)
        d, id = W.add(d, k, S); eq(id, nil, "one " .. k)
    end
    eq(#d.widgets, 8, "eight"); eq(d.widgets[2].layout, "horizon", "weather first layout")
    eq(W.idle_state({ kind = "weather", idle = "hide" }, false), "shown", "not music: shown")
    eq(W.idle_state({ kind = "visualiser", idle = "hide" }, false), "hidden", "music: the rule")
    eq(W.KIND_NUM.launch, 11, "kind numbers")
end)
test("groups, look and the desk arrangement survive the file", function()
    local d = W.defaults(1920, 1080)
    local a, b
    d, a = W.add(d, "clock", S); d, b = W.add(d, "timer", S)
    d = W.group(d, { a, b })
    eq(select(2, W.find(d, a)).group ~= nil, true, "grouped"); eq(select(2, W.find(d, a)).group, select(2, W.find(d, b)).group, "same group")
    local ids = W.with_groups(d, { a }); eq(#ids, 2, "choosing one chooses its group")
    d.style, d.ambient, d.shadows = "paper", false, true
    local back = W.parse("", decode_table(W.encode(d)), S)
    eq(back.style, "paper", "style"); eq(back.ambient, false, "ambient"); eq(back.shadows, true, "shadows")
    eq(select(2, W.find(back, a)).group, select(2, W.find(d, a)).group, "group kept")
    eq(W.parse("", decode_table({ widgets = {}, style = "neon" }), S).style, "adaptive", "an unknown style is adaptive")
    eq(W.set_look(d, "style", "chrome").style, "chrome", "set_look"); eq(W.set_look(d, "style", "neon").style, d.style, "a bad style is ignored")
    d = W.ungroup(d, { b }); eq(select(2, W.find(d, a)).group, nil, "a group of one is no group")
    -- desk mode: every widget gets a place, all on screen, none overlapping
    local lay = W.desk_layout(d, S)
    eq(#lay, #d.widgets, "one place each")
    for i, p in ipairs(lay) do
        local w = d.widgets[i]
        eq(p.x >= 0 and p.y >= (S.top or 0) and p.x + w.w <= S.w and p.y + w.h <= S.h, true, "on screen " .. i)
        for j = i + 1, #lay do
            local q, v = lay[j], d.widgets[j]
            eq(p.x < q.x + v.w and q.x < p.x + w.w and p.y < q.y + v.h and q.y < p.y + w.h, false, "no overlap " .. i .. "," .. j)
        end
    end
end)

local json_null_stub = nil
print("github activity map")
do
    test("activity map: weeks of days, levels, the total", function()
        local GP2 = require("lib/ghparse")
        local weeks = {}
        for w = 1, 60 do
            local days = {}
            for wd = 0, (w == 60 and 2 or 6) do days[#days + 1] = { weekday = wd, contributionLevel = wd == 3 and "FOURTH_QUARTILE" or "NONE" } end
            weeks[w] = { contributionDays = days }
        end
        local h = GP2.heat({ data = { user = { contributionsCollection = { contributionCalendar = { totalContributions = 368, weeks = weeks } } } } }, 52)
        eq(#h.cells, 364, "52 weeks of 7"); eq(h.total, 368, "total"); eq(h.cells[4].lv, 4, "a Wednesday lit"); eq(h.cells[364].lv, -1, "days to come")
        eq(GP2.heat({ data = { user = json_null_stub } }), nil, "junk refused")
    end)
end
print("widgets data")
do
    local DD = require("lib/deskdata")
    local apps = require("lib/apps")
    test("weather: icons, the sky's hours, the week", function()
        eq(DD.icon_kind(0, 1), 0, "sun"); eq(DD.icon_kind(0, 0), 1, "moon"); eq(DD.icon_kind(2, 1), 3, "partly")
        eq(DD.icon_kind(61, 1), 5, "rain"); eq(DD.icon_kind(73, 1), 6, "snow"); eq(DD.icon_kind(95, 1), 7, "storm"); eq(DD.icon_kind(45, 1), 4, "fog")
        local times, temps, codes, days = {}, {}, {}, {}
        for i = 0, 47 do
            times[#times + 1] = string.format("2026-11-%02dT%02d:00", 3 + i // 24, i % 24)
            temps[#temps + 1] = 5 + (i % 24) / 2; codes[#codes + 1] = (i % 24 == 15) and 61 or 1
            days[#days + 1] = (i % 24 >= 7 and i % 24 < 17) and 1 or 0
        end
        local h, lo, hi = DD.horizon({ current = { time = "2026-11-03T14:15" }, hourly = { time = times, temperature_2m = temps, weather_code = codes, is_day = days } }, 24)
        eq(#h, 24, "a day of hours"); eq(h[1].label, "14", "from the current hour"); eq(h[1].now, true, "now first")
        eq(h[2].wet, 1, "15:00 rains"); eq(h[3].r > h[3].b, true, "16:00, the last light, is warm")
        eq(h[6].b > h[6].r, true, "19:00 is night blue"); eq(lo <= hi, true, "range")
        eq(DD.horizon({ current = {}, hourly = {} }), nil, "no hours, nothing")
        local w = DD.week({ { label = "Today", code = 0, hi = 14, lo = 4 }, { label = "Wednesday", code = 61, hi = 10, lo = 8 } })
        eq(w[2].lab, "WED", "short day"); eq(w[1].a, 0, "coldest low at 0"); eq(w[1].b, 1, "warmest high at 1"); eq(w[2].kind, 5, "rain")
    end)
    test("calendar: a month of 42 days, Monday first, with what is due", function()
        local today = DD.day_number(2026, 11, 3)
        eq(today, 20760, "days since 1970")
        local board = { columns = { { id = 1 }, { id = 9 } }, cards = { { due = today + 2, col = 1 }, { due = today + 2, col = 1 }, { due = today, col = 9 } } }
        local g = DD.month_grid(2026, 11, today, board)
        eq(#g, 42, "six weeks"); eq(g[1].d, "26", "November 2026 starts on a Sunday: Monday 26 October first"); eq(g[1].inm, false, "outside")
        eq(g[7].d, "1", "the 1st on Sunday"); eq(g[9].today, true, "the 3rd is today"); eq(g[11].due, 2, "two due on the 5th")
        eq(g[9].due, 0, "done cards are not due"); eq(g[36].d, "30", "the 30th"); eq(g[37].inm, false, "December after")
    end)
    test("focus timer: runs, pauses, takes more time", function()
        local t = DD.timer(25)
        eq(DD.timer_left(t, 100), 1500, "stopped, all of it")
        DD.timer_toggle(t, 100); eq(DD.timer_left(t, 160), 1440, "a minute in")
        DD.timer_toggle(t, 160); eq(DD.timer_left(t, 999), 1440, "paused")
        DD.timer_add(t, 300, 999); eq(DD.timer_left(t, 999), 1740, "five more"); eq(t.total >= 1740, true, "the ring's whole grows")
        DD.timer_add(t, -99999, 999); eq(DD.timer_left(t, 999), 60, "a minute at least")
        eq(DD.mmss(1500), "25:00"); eq(DD.mmss(3725), "1:02:05"); eq(DD.mmss(-3), "00:00")
    end)
    test("claude: the last thing said, plain; sessions counted", function()
        local c = DD.claude_last({ turns = { { who = "me", text = "hi" }, { who = "claude", text = "Here **is** `code`:\n```lua\nx()\n```\ndone" }, { who = "note", text = "x" } } })
        eq(c.who, "CLAUDE"); eq(c.text, "Here is code: [code] done", "markdown gone")
        eq(DD.claude_last({}), nil, "nothing said")
        eq(DD.count_lines("123\n456\n"), 2); eq(DD.count_lines(""), 0)
    end)
    test("launcher: the apps asked for, running and waiting", function()
        local list = { { name = "Kitty", id = "kitty", exec = "kitty", icon = "kitty", wmclass = "kitty" },
                       { name = "Zen Browser", id = "zen", exec = "zen-browser", icon = "zen", wmclass = "zen" } }
        local rows = DD.launch_rows("kitty, zen ,nope", list, { { class = "zen" } }, { { app = "Kitty" }, { app = "kitty" } }, apps.app_for)
        eq(#rows, 2, "not installed is left out"); eq(rows[1].pulse, 2, "two unseen"); eq(rows[2].run, true, "zen open"); eq(rows[1].run, false)
        eq(rows[2].letter, "Z")
    end)
    test("light: from the bright part of the wallpaper", function()
        local cells = {}
        for r = 0, 1 do for c = 0, 1 do cells[#cells + 1] = { l = (r == 0 and c == 0) and 0.95 or 0.2 } end end
        local dx, dy = DD.light({ cols = 2, rows = 2, cells = cells }, 1440, 810, { w = 1920, h = 1080 })
        eq(dx > 0 and dy > 0, true, "top-left light falls down-right")
        local fx, fy = DD.light(nil, 0, 0, { w = 1920, h = 1080 }); eq(fx, 0); eq(fy, 1, "down when unknown")
        eq(#DD.push({ 1, 2, 3 }, 4, 3), 3, "window kept")
    end)
end

print("claude fallback, BMO's jokes")
do
    local CL = require("lib/claude")
    local BR = require("bmo/brain")
    test("a free model when Claude cannot answer: its arguments and its answer read back", function()
        local a = CL.fallback_args("hi", "bmo", nil, { { who = "you", text = "earlier" } })
        eq(a[1], "run"); eq(a[3], CL.FALLBACK_MODELS[1], "the first free model")
        eq(a[4]:find("You are BMO", 1, true) ~= nil, true, "his persona"); eq(a[4]:find("you: earlier", 1, true) ~= nil, true, "the turns so far")
        eq(CL.fallback_text("\27[0m> build · big-pickle\n\nHello there!\n"), "Hello there!", "header and colours gone")
        eq(CL.fallback_text("\27[91mError: This model is not available"), nil, "an error is no answer")
        eq(CL.fallback_text(""), nil, "nothing is no answer")
    end)
    test("BMO has jokes of his own, one idle line in five", function()
        eq(#BR.LINES.joke >= 12, true, "a dozen at least"); eq(BR.idle_pool(0.1), "joke"); eq(BR.idle_pool(0.5), "idle")
        for _, j in ipairs(BR.LINES.joke) do eq(#j <= 228, true, "fits six bubble lines: " .. j) end
    end)
end

print("the settings window's codes (D147)")
test("tools/gen-settings.py and lib/setters list the same settings in the same order", function()
    local f = assert(io.open("tools/gen-settings.py"))
    local py = f:read("a"); f:close()
    local a = py:find("SETTERS = [", 1, true)
    local b = py:find("\n]", a, true)
    local theirs = {}
    for p in py:sub(a, b):gmatch('"([%a_]+%.[%a_.]+)"') do theirs[#theirs + 1] = p end
    local SET = require("lib/setters").SETTERS
    eq(#theirs, #SET, "as long")
    for i = 1, #SET do eq(theirs[i], SET[i], "code " .. i) end
    local config = require("lib/config")
    local d = config.defaults()
    eq(d.walls.view, "strip"); eq(d.wallhaven.purity, "sfw", "safe for work unless chosen"); eq(#d.walls.folders, 2)
    local _, p = config.validate({ walls = { folders = { "relative/path" } } }); eq(#p, 1, "a folder must be absolute or ~/")
end)

print("wallpapers (D145)")
do
    local W = require("lib/walls")
    test("kinds by extension, the index's word first", function()
        eq(W.kind("/a/b.JPG"), "still"); eq(W.kind("/a/b.gif"), "animated"); eq(W.kind("/a/b.mp4"), "video")
        eq(W.kind("/a/b.webp", "animated"), "animated", "the index looked inside"); eq(W.kind("/a/b.txt"), nil)
        eq(W.kind("/a/noext"), nil); eq(W.is_live("video"), true); eq(W.is_live("still"), false)
    end)
    test("settings: folders expanded, the view kept or defaulted", function()
        local n = W.normalize(nil, "/home/u")
        eq(#n.folders, 2); eq(n.folders[1], "/home/u/Pictures/wallpapers"); eq(n.view, "strip")
        n = W.normalize({ folders = { "/x", 3, "" }, view = "orbit" }, "/h")
        eq(#n.folders, 1, "junk left out"); eq(n.view, "orbit")
        eq(W.normalize({ view = "grid" }).view, "strip")
    end)
    test("index items made safe; filters by source and search", function()
        local items = W.items({ items = {
            { path = "/w/Red Sky.jpg", hue = 370, luma = 2, thumb = "/t/1.jpg" },
            { path = "/w/grey.png", hue = 10, grey = true },
            { path = "/l/fire.mp4", kind = "video", hue = 20, luma = 0.3, still = "/s/f.jpg" },
            { path = "/w/notes.md" }, "junk", { hue = 3 },
        } })
        eq(#items, 3, "only pictures with a path"); eq(items[1].hue, 10, "hue wrapped"); eq(items[1].luma, 1, "luma clamped")
        eq(items[2].hue, nil, "grey has no hue"); eq(items[3].kind, "video"); eq(items[1].name, "Red Sky.jpg")
        eq(#W.filter(items, "live"), 1); eq(#W.filter(items, "pictures"), 2); eq(#W.filter(items, "all"), 3)
        eq(#W.filter(items, "all", "SKY"), 1, "any case"); eq(#W.filter(items, "live", "sky"), 0)
        eq(W.find(items, "/l/fire.mp4"), 3); eq(W.find(items, "/nope"), nil)
        eq(#W.items(nil), 0); eq(#W.items({ items = 4 }), 0)
    end)
    test("the strip's window stays full near the ends", function()
        local a, b = W.window(100, 50, 15); eq(a, 43); eq(b, 57)
        a, b = W.window(100, 1, 15); eq(a, 1); eq(b, 15)
        a, b = W.window(100, 100, 15); eq(a, 86); eq(b, 100)
        a, b = W.window(5, 3, 15); eq(a, 1); eq(b, 5)
        a, b = W.window(0, 1, 15); eq(b, 0, "empty")
    end)
    test("the orbit: hue is the angle, lightness the distance, greys in the middle", function()
        local x, y, _, r = W.orbit_place({ hue = 0, luma = 1 }, 1, 0, 0)
        eq(math.abs(x) < 1e-9, true, "red at the top"); eq(math.abs(y + 1) < 1e-9, true); eq(r, 1)
        x, y = W.orbit_place({ hue = 90, luma = 0 }, 1, 0, 0)
        eq(math.abs(x - W.ORBIT.inner) < 1e-9, true, "a dark yellow-green to the right, near the inner ring")
        local _, _, _, gr = W.orbit_place({ hue = nil }, 2, 4, 0); eq(gr, W.ORBIT.grey)
        x = W.orbit_place({ hue = 0, luma = 1 }, 1, 0, 90); eq(math.abs(x - 1) < 1e-9, true, "spun a quarter turn")
        local places = W.orbit({ { hue = 0, luma = 1 }, { hue = 180, luma = 1 }, { hue = nil }, { hue = nil } })
        eq(#places, 4); eq(math.abs(places[3].x - 0) < 1e-9 and places[3].y < 0, true, "first grey at the top of its ring")
        eq(places[4].y > 0, true, "second grey opposite")
        local near = W.nearest(places, 0, -1, 2); eq(near[1], 1, "the red one nearest the top"); eq(#near, 2)
        eq(#W.nearest(places, 5, 5, 3, 0.5), 0, "nothing within reach")
        eq(math.floor(W.hue_at(1, 0, 0) + 0.5), 90); eq(math.floor(W.hue_at(0, -1, 0) + 0.5) % 360, 0)
        eq(math.floor(W.hue_at(1, 0, 90) + 0.5) % 360, 0, "spin turns it back")
        eq(W.band_name(0), "REDS"); eq(W.band_name(355), "REDS"); eq(W.band_name(215), "AZURES"); eq(W.band_name(nil), "GREYS")
    end)
    test("the colour filter: 24 hue chips, greys, light and dark", function()
        eq(W.chip_of(0), 0); eq(W.chip_of(359), 0, "red wraps"); eq(W.chip_of(8), 1); eq(W.chip_of(215), 14); eq(W.chip_of(nil), W.GREY_CHIP)
        local r, g, b = W.chip_rgb(0); eq(r > g and r > b, true, "chip 0 is red")
        r, g, b = W.chip_rgb(16); eq(b > r and b > g, true, "chip 16 is blue")
        local items = { { name = "a", kind = "still", hue = 2, luma = 0.8 }, { name = "b", kind = "still", hue = 120, luma = 0.2 },
                        { name = "c", kind = "video", hue = nil, luma = 0.5 } }
        eq(#W.filter(items, "all", "", 0), 1); eq(#W.filter(items, "all", "", W.GREY_CHIP), 1)
        eq(#W.filter(items, "all", "", -1, 1), 1, "light"); eq(#W.filter(items, "all", "", -1, 2), 1, "dark")
        eq(#W.filter(items, "all", "", 8, 2), 1, "green and dark"); eq(#W.filter(items, "live", "", W.GREY_CHIP), 1)
        eq(#W.filter(items, "all"), 3, "no filter")
    end)
    test("the circuit board: a core in a panel, twenty chips round it on square traces", function()
        local P = W.panel(1920, 1047)
        eq(P.x > 0 and P.x + P.w < 1920 and P.y + P.h < 1047, true, "a panel, not the whole screen")
        local R = W.ring(P)
        eq(#R.chips, W.RING_N)
        local c = R.core
        eq(c.w >= 560, true, "a large core")
        local function inside(b) return b.x >= P.x and b.y >= P.y and b.x + b.w <= P.x + P.w and b.y + b.h <= P.y + P.h end
        eq(inside(c), true, "the core in the panel")
        for i, k in ipairs(R.chips) do
            eq(inside(k), true, "chip " .. i .. " in the panel")
            eq(k.x + k.w <= c.x or k.x >= c.x + c.w or k.y + k.h <= c.y or k.y >= c.y + c.h, true, "chip " .. i .. " clear of the core")
            for j = 2, #k.pts do
                local dx, dy = math.abs(k.pts[j][1] - k.pts[j - 1][1]), math.abs(k.pts[j][2] - k.pts[j - 1][2])
                eq(dx < 0.01 or dy < 0.01, true, string.format("chip %d step %d square", i, j))
            end
            for m = i + 1, #R.chips do
                local o = R.chips[m]
                eq(k.x + k.w <= o.x or o.x + o.w <= k.x or k.y + k.h <= o.y or o.y + o.h <= k.y, true, string.format("chips %d and %d apart", i, m))
            end
        end
        local L = W.trace_lengths({ { 0, 0 }, { 3, 4 }, { 3, 4 }, { 3, 10 } }); eq(L[1], 5); eq(L[3], 11)
    end)
    test("Wallhaven: answers made safe, chips as its colours", function()
        local h, l = W.hex_hue("#cc0000"); eq(math.floor(h + 0.5), 0); eq(l > 0.3 and l < 0.5, true)
        eq((W.hex_hue("#999999")), nil, "grey"); eq((W.hex_hue("junk")), nil)
        eq(W.wh_colour(0), "cc0000", "red"); eq(W.wh_colour(14), "0066cc", "azure"); eq(W.wh_colour(16), "333399", "blue"); eq(W.wh_colour(W.GREY_CHIP), "999999"); eq(W.wh_colour(-1), nil)
        local items, last, seed = W.wh_items({ data = {
            { id = "abc123", path = "https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg", thumbs = { large = "https://th.wallhaven.cc/lg/ab/abc123.jpg" }, colors = { "#222222", "#0066cc", "#999999" } },
            { id = "x;rm", path = "https://w.wallhaven.cc/full/x.jpg", thumbs = { large = "https://th.wallhaven.cc/lg/x.jpg" } },
            { id = "evil1", path = "https://evil.example/x.jpg", thumbs = { large = "https://th.wallhaven.cc/lg/e.jpg" } },
        }, meta = { last_page = 7, seed = "Ab12" } })
        eq(#items, 1, "only the safe one"); eq(items[1].remote, true); eq(math.floor(items[1].hue + 0.5), 210); eq(last, 7); eq(seed, "Ab12")
        eq(W.wh_items({}), nil)
    end)
    test("the desk's state: a video is drawn as its still, junk is nil", function()
        local s = W.state({ source = "/l/a.mp4", still = "/s/a.jpg", transition = "grow", from_y = 300 })
        eq(s.kind, "video"); eq(s.still, "/s/a.jpg"); eq(s.from_y, 300); eq(s.from_x, nil)
        s = W.state({ source = "/w/a.jpg", still = "/elsewhere.jpg" }); eq(s.still, "/w/a.jpg", "a picture is its own still")
        eq(W.state({ source = "/w/a.txt" }), nil); eq(W.state({}), nil); eq(W.state("x"), nil)
    end)
end

print(string.format("\n%d tests, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
