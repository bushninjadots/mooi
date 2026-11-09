-- Unit tests for the pure logic modules. Run: lua5.4 tests/unit/run.lua (from the repo root)
package.path = "shell/?.luau;" .. package.path

local failures, count = 0, 0
-- --filter <text> (or MOOI_TEST_FILTER) runs only the sections or test names containing it.
local filter = os.getenv("MOOI_TEST_FILTER")
if arg[1] == "--filter" then filter = arg[2] elseif arg[1] then filter = arg[1] end
local current = ""
local function section(name) current = name; print(name) end
local function test(name, fn)
    if filter and filter ~= "" and not current:find(filter, 1, true) and not name:find(filter, 1, true) then return end
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


section("config")
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
test("styles: steel is gone; a file on steel keeps its look as instrument", function()
    local s, _, notes = config.validate({ bar = { style = "steel", surface = "mech", outline_colour = "accent", shadow = "medium" } })
    eq(s.bar.style, "instrument"); eq(s.bar.surface, "mech", "finer values kept"); eq(s.bar.outline_colour, "accent")
    local said = false; for _, n in ipairs(notes) do if n:find("steel", 1, true) then said = true end end
    eq(said, true, "the move is noted")
    eq(config.validate({ bar = { style = "hairline" } }).bar.style, "hairline")
end)
test("frame.islands: float by default, attach when chosen", function()
    eq(config.defaults().frame.islands, "float"); eq(config.validate({ frame = { islands = "attach" } }).frame.islands, "attach")
end)
test("module looks: defaults are the style's, bad values fall back with a problem", function()
    local d = config.defaults().bar.modules.clock
    eq(d.colour, "style"); eq(d.fill, "style"); eq(d.rounding, "style"); eq(d.outline, "style"); eq(d.glow, "off")
    eq(d.display, "icon+value"); eq(d.width, "fit")
    local s, p = config.validate({ bar = { modules = { clock = { fill = "chrome", colour = "#12", rounding = "pill" } } } })
    eq(s.bar.modules.clock.fill, "style"); eq(s.bar.modules.clock.colour, "style"); eq(s.bar.modules.clock.rounding, "pill"); eq(#p, 2)
    eq(config.validate({ bar = { modules = { clock = { colour = "#e07b2e" } } } }).bar.modules.clock.colour, "#e07b2e")
    eq(config.validate({ bar = { modules = { clock = { colour = "ember" } } } }).bar.modules.clock.colour, "ember")
end)
test("presets: five styles, hairline is an accent line with no fill, steel is not one", function()
    local st = require("lib/style")
    local names = {}; for _, p in ipairs(st.BAR_PRESETS) do names[#names + 1] = p.name end
    eq(table.concat(names, ","), "instrument,glass,floating,hairline,minimal")
    local s = config.defaults(); st.apply_preset(s, st.BAR_PRESETS, "hairline")
    eq(s.bar.surface, "clear"); eq(s.bar.frame, "line"); eq(s.bar.outline_width, 1); eq(s.bar.outline_colour, "accent")
    eq(st.preset_index(s, st.BAR_PRESETS), 3)
    -- every style sets every finer value, so it looks the same whatever was chosen before it
    local keys = {}
    for _, p in ipairs(st.BAR_PRESETS) do for k in pairs(p.set) do keys[k] = true end end
    for _, p in ipairs(st.BAR_PRESETS) do
        for k in pairs(keys) do assert(p.set[k] ~= nil, p.name .. " leaves " .. k .. " to whatever came before") end
    end
    local g0 = config.validate({ bar = { frost = 94, smoke = 69, opacity = 31 } })
    st.apply_preset(g0, st.BAR_PRESETS, "minimal")
    eq(g0.bar.frost, 70, "glass's frost is replaced by the style's own (frost only shows on glass)"); eq(g0.bar.smoke, 38)
    local f = io.open("tools/gen-settings.py"); local g = f:read("a"); f:close()
    assert(g:find('STYLES = [("Instrument", 0), ("Glass", 1), ("Floating", 2), ("Hairline", 3), ("Minimal", 4)]', 1, true), "the window lists the same five")
end)
test("edges: a style without an outline gives the frame no line either", function()
    local f = io.open("shell/mooi-frame.plm"); local plm = f:read("a"); f:close()
    assert(plm:find("border: if(bar_frame < 0.5 and (not band_on or st_frame_edge < 1.5), st_owidth, 0), fnec", 1, true))
end)
test("the bar's material and density: defaults, and an unknown one falls back", function()
    local d = config.defaults()
    eq(d.bar.material, "ferrolume"); eq(d.bar.density, "balanced")
    local s, p = config.validate({ bar = { material = "chrome", density = "rich", height = 30 } })
    eq(s.bar.material, "ferrolume", "unknown material falls back")
    eq(s.bar.density, "rich"); eq(s.bar.height, 30, "the rest is kept"); eq(#p, 1, "one problem")
end)
test("the two choice transports have a default, and the window derives the real one", function()
    -- bar.edge / frame.motion had no default: a file carrying one kept a value nothing read.
    local d = config.defaults()
    eq(d.bar.edge, "regular", "bar edge: the default line at width 2"); eq(d.frame.motion, "off", "frame motion")
    local style = require("lib/style")
    eq(style.edge_index(d), 3, "which edge is shown comes from bar.frame (line, 2 px: Regular)")
    eq(style.edge_index({ bar = { frame = "thin", outline_width = 2 } }), 3, "and from its width")
    eq(style.motion_index({ frame = { music = false } }), 0, "the frame's music, not the transport")
end)
test("a newer version is noted", function()
    local _, p, n = config.validate({ version = 3 }); eq(#p, 0, "problems"); eq(#n, 1, "notes")
end)

section("wfx")
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

section("fx colours")
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

section("hypr")
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

section("apps")
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

section("spaces")
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

section("theme")
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

section("search")
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

section("ferro")
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

section("barlayout")
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

section("sysinfo")
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

section("setters")
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

section("desktop")
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

section("style")
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
test("the Outline shown is the outline drawn: a stale bar.edge is repaired on load", function()
    -- 2026-11-06: settings.json said bar.edge = "bold" over bar.frame = "none" (a preset had set the
    -- pair), so Settings and the bar disagreed about whether there was a border at all.
    local s, _, notes = config.validate({ bar = { edge = "bold", frame = "none", outline_width = 2 } })
    eq(s.bar.edge, "none", "the drawn pair wins")
    local said = false
    for _, n in ipairs(notes) do if n:find("bar.edge", 1, true) then said = true end end
    eq(said, true, "and the repair is noted")
    eq(config.validate({ bar = { frame = "line", outline_width = 3 } }).bar.edge, "bold", "line at 3 is Bold")
    eq(config.validate({ bar = { frame = "line", outline_width = 1 } }).bar.edge, "thin", "line at 1 is Thin")
    eq(config.validate({ bar = { frame = "corners" } }).bar.edge, "corners", "corners")
end)
test("the frame draws one outline: no second music line, one width everywhere", function()
    local f = io.open("shell/mooi-frame.plm"); local plm = f:read("a"); f:close()
    eq(plm:find("stroke: 1.4", 1, true), nil, "the etched 1.4 px light beside the edge is gone")
    local widths = {}
    for b in plm:gmatch("border: ([^\n]+)") do
        -- D166: a floating plate's border is its own (its outline choice), still at the one width
        if b:find("po%d") then assert(b:find("st_owidth", 1, true), "a plate's outline is the one width") else widths[b] = true end
    end
    local n = 0; for _ in pairs(widths) do n = n + 1 end
    eq(n, 1, "every tile's border is the same expression")
    assert(next(widths):find("bar_frame", 1, true), "and it honours the bar's Outline when the band is off")
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

test("the lock screen's backdrop is a setting, and stays legible", function()
    local d = config.defaults()
    eq(d.lock.blur, "medium", "blurred as the design has it")
    eq(d.lock.dim, 72, "and dimmed to 72 percent")
    local s, problems = config.validate({ lock = { blur = "nonsense", dim = 200 } })
    eq(s.lock.blur, "medium", "an unknown blur is the default")
    eq(s.lock.dim, 72, "a dim out of range is the default too")
    eq(#problems, 2, "and both are reported")
    eq(require("lib/setters").path(420), "lock.blur", "the choice's code")
    eq(require("lib/setters").path(421), "lock.dim", "the slider's code")
    eq(require("lib/setters").path(422), "lock.banner", "the banner's switch")
    eq(require("lib/setters").path(423), "lock.avatar", "the picture's own, beside it")
    eq(d.lock.banner, true, "the banner shows unless it is turned off")
    eq(d.lock.avatar, true, "and so does the picture")
    local off = config.validate({ lock = { banner = false } })
    eq(off.lock.banner, false, "a banner turned off stays off")
    eq(off.lock.avatar, true, "while the picture beside it is untouched")
end)
test("the lock's backdrop can be seen before the screen locks (D160)", function()
    local f = io.open("shell/mooi-settings.plm", "r")
    local plm = f and f:read("a") or ""
    if f then f:close() end
    assert(plm:find("image lkwp = from lk_wp", 1, true), "the settings scene has no backdrop picture")
    assert(plm:find("blur: pick(sv_lock_blur, 0, 22, 54, 96)", 1, true), "the preview does not follow the blur")
    assert(plm:find("opacity: sv_lock_dim / 100", 1, true), "the preview does not follow the dimming")
    local l = io.open("shell/mooi-lock.luau", "r")
    local luau = l and l:read("a") or ""
    if l then l:close() end
    for _, call in ipairs({ "media.previous", "media.toggle", "media.next" }) do
        assert(luau:find('sys.call, "' .. call .. '"', 1, true), "the lock cannot reach " .. call)
    end
end)
test("the lock's picture and its visualiser are wired (D160/D161)", function()
    local function slurp(path)
        local f = io.open(path, "r")
        local t = f and f:read("a") or ""
        if f then f:close() end
        return t
    end
    local luau = slurp("shell/mooi-lock.luau")
    -- `files.exists` answers for a scene's own folder only, and its no was read as "no picture",
    -- so the banner and the profile picture never showed. Nothing may put that question back.
    assert(not luau:find('sys.ask, "files.exists"', 1, true), "the picture's presence is asked of a service that cannot see it")
    -- the bands: the bar writes cava's line, `mooi lock` carries it in, the scene thins it to sixteen
    local sh = slurp("bin/mooi")
    assert(sh:find("lock_feed_start", 1, true), "nothing carries cava's bands to the lock")
    -- the watch coalesces: without a reader at the feed's pace the bars move a dozen times a second
    assert(luau:find("every(33", 1, true), "the lock's bands are read only when the watch feels like it")
    assert(luau:find("vizfeed.newer", 1, true), "the lock redraws a line it has already drawn")
    assert(luau:find("vizfeed.resample", 1, true), "the lock does not thin the bands")
    -- an image fact draws a path as it stands, so each copy is named by its whole path
    assert(sh:find('printf \'%s\' "$3/$2.$ext"', 1, true), "a lock picture is named without its folder, and nothing draws it")
    assert(sh:find('lock_picture "$rel" avatar "$d"', 1, true), "the profile picture is not copied beside the lock")
    assert(sh:find('lock_picture "$rel" banner "$d"', 1, true), "the banner is not copied beside the lock")
    -- both at once: the strip is the place, the plate is the person
    local lockplm = slurp("shell/mooi-lock.plm")
    assert(lockplm:find("has_ban", 1, true), "a banner has nowhere to draw")
    assert(lockplm:find("image lockban", 1, true), "the banner's image is not declared")
    assert(luau:find("banpath", 1, true), "the logic never sets the banner's path")
    -- and each can be taken off the lock on its own swit
    assert(luau:find("lk_ban_on", 1, true) and luau:find("lk_av_on", 1, true), "the logic never reads the two switches")
    local lockplm2 = slurp("shell/mooi-lock.plm")
    assert(lockplm2:find("lk_ban_on", 1, true) and lockplm2:find("lk_av_on", 1, true), "nothing on the lock can hide either picture")
    -- a video has no decoder in a scene: the lock is handed its still, then a loop it can play
    assert(luau:find('kind == "video"', 1, true), "a video wallpaper is drawn as the video")
    assert(sh:find("wall-loop", 1, true), "a video wallpaper has nothing to draw on the lock")
    local scene = slurp("shell/mooi-lock.plm")
    assert(scene:find('import "ui/viz.plm"', 1, true), "the lock imports no visualiser")
    assert(scene:find("viz.Spectrum(", 1, true), "the lock's visualiser is not the shell's spectrum")
end)
test("the lock screen has a key of its own (D160)", function()
    local desktop = require("lib/desktop")
    local keys = config.defaults().keys
    local function has(list, cmd) for _, b in ipairs(list) do if b[2] == cmd then return b[1] end end end
    eq(has(desktop.binds(keys), "lock"), "SUPER + L", "Super+L locks at once")
    eq(keys.lock, "SUPER + L", "and it is a setting, so it can be another key")
    local f = desktop.file(keys, config.defaults().desktop, pal, "/x/bin/mooi")
    assert(string.find(f, '{ "SUPER + L", "lock" },', 1, true), "the key runs `mooi lock`")
    local action = nil
    for _, a in ipairs(desktop.ACTIONS) do if a.key == "lock" then action = a end end
    eq(action and action.cmd, "lock", "an action, and its bin/mooi command")
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

section("signals")
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

section("notes")
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

section("board")
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

section("stash")
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
section("desk pictures")
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
section("player")
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
section("desk")
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
    eq(lat, 39.7817, "latitude"); eq(lon, -89.6501, "longitude")
    eq(select(1, weathercache.coordinates({ loc = "90,-180" })), 90, "valid lower longitude")
    eq(weathercache.coordinates({ loc = "91,0" }), nil, "latitude out of range")
    eq(weathercache.coordinates({ loc = "0,181" }), nil, "longitude out of range")
    eq(weathercache.coordinates({ loc = "nan,0" }), nil, "non-number")
    eq(weathercache.coordinates({ loc = "41.1;os.execute('bad'),1" }), nil, "injected text")
    eq(weathercache.coordinates({ loc = "41,1,2" }), nil, "extra coordinate")
    eq(weathercache.coordinates(nil), nil, "missing location")
end)

local weathershare = require("lib/weathershare")
local function share_world(files)
    local fetched = {}
    return fetched, {
        now = 2000,
        read = function(name) return files[name] end,
        write = function(name, doc) files[name] = doc end,
        fetch = function(url, done)
            fetched[#fetched + 1] = url
            if url:find("ipinfo", 1, true) then done({ loc = "39.78,-89.65", city = "Springfield" }) else done(meteo()) end
        end,
    }
end
test("weather share: a fresh forecast is the answer, with nothing fetched", function()
    local files = { ["nexus-weather.json"] = { at = 1900, answer = meteo(), city = "Springfield" },
                    ["ipinfo.json"] = { at = 1900, loc = "39.78,-89.65", city = "Springfield" } }
    local fetched, opts = share_world(files)
    local got
    weathershare.refresh(opts, function(doc) got = doc end)
    eq(#fetched, 0, "no request"); eq(got.city, "Springfield", "cached doc handed back")
    opts.force = true
    weathershare.refresh(opts, function(doc) got = doc end)
    eq(#fetched, 1, "force asks open-meteo"); eq(fetched[1]:find("open%-meteo") ~= nil, true, "the forecast, not ipinfo")
end)
test("weather share: a cold start asks ipinfo once, then remembers the place", function()
    local files = {}
    local fetched, opts = share_world(files)
    weathershare.refresh(opts, function() end)
    eq(#fetched, 2, "ipinfo + forecast"); eq(files["ipinfo.json"].city, "Springfield", "location memo written")
    files["nexus-weather.json"] = nil
    weathershare.refresh(opts, function() end)
    eq(#fetched, 3, "only the forecast the second time")
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
test("claude: the prompt goes last, after --, so a dash is never a flag", function()
    local a = claude.args("--dangerously-skip-permissions", {})
    eq(a[#a], "--dangerously-skip-permissions", "prompt is the last argument")
    eq(a[#a - 1], "--", "after the end of options")
    eq(a[1], "-p", "print mode")
end)
test("claude: free models only when the setting says so", function()
    eq(claude.free_allowed(nil), false); eq(claude.free_allowed({}), false)
    eq(claude.free_allowed({ claude = { free_fallback = false } }), false)
    eq(claude.free_allowed({ claude = { free_fallback = true } }), true)
    eq(claude.FREE_ENV[1]:find('"*":"deny"', 1, true) ~= nil, true, "opencode denies every tool")
end)
test("github: only GitHub's own https pages reach xdg-open", function()
    local GPw = require("lib/ghparse")
    eq(GPw.web_url("https://github.com/bushninjadots/mooi/pull/3"), "https://github.com/bushninjadots/mooi/pull/3")
    eq(GPw.web_url("http://github.com/x"), nil, "not https")
    eq(GPw.web_url("https://github.com.evil.example/x"), nil, "lookalike host")
    eq(GPw.web_url("file:///etc/passwd"), nil, "file url")
    eq(GPw.web_url("https://github.com/x y"), nil, "space")
    eq(GPw.web_url("https://github.com/x\n--help"), nil, "control character")
    eq(GPw.web_url(nil), nil)
end)
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

section("games")
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

section("vizfeed")
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
section("vizfeed v2")
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

section("settingsfile")
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

local index = require("lib/settings_index")
section("settings index")
test("every row names a page, a title and a place", function()
    assert(#index >= 150, "the window has far fewer rows than expected")
    for i, row in ipairs(index) do
        eq(type(row.title), "string", "title " .. i)
        assert(row.title ~= "", "empty title " .. i)
        eq(type(row.page), "string", "page " .. i)
        assert(row.page ~= "", "empty page " .. i)
        eq(type(row.tab), "number", "tab " .. i)
        eq(type(row.y), "number", "y " .. i)
    end
end)
test("every Reset names a real setting or a page marker", function()
    local known = {}
    for _, r in ipairs(config.SCHEMA) do known[r.path] = true end
    for tab, paths in pairs(index.resets) do
        eq(type(tab), "number", "reset tab")
        for _, p in ipairs(paths) do
            assert(p == "@layout" or p == "@keys" or known[p], "unknown reset path: " .. tostring(p))
        end
    end
end)
test("the pages the window offers are the pages the rows carry", function()
    local pages = {}
    for _, r in ipairs(index) do pages[r.page] = true end
    for _, name in ipairs({ "Quick settings", "Theme & colour", "Bar & Frame", "Windows", "Wallpapers", "Control Nexus" }) do
        assert(pages[name], "missing page: " .. name)
    end
end)

local themeprofiles = require("lib/themeprofiles")
section("notch · wallhaven")
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

section("theme packages")
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
section("components")
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
section("widgets")
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
test("duplicate ids are renumbered; more than W.MAX are dropped", function()
    local list = {}
    for i = 1, W.MAX + 2 do list[i] = { id = "np-1", kind = "nowplaying", layout = "sleeve", x = 0, y = 40, w = 288, h = 104 } end
    local d = W.parse("", decode_table({ version = 1, widgets = list }), S)
    eq(#d.widgets, W.MAX, "cap"); eq(d.widgets[2].id ~= d.widgets[1].id, true, "unique")
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

section("wallmap")
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

section("widgets scene ↔ logic")
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

section("clock face")
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
section("github")
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
section("widgets · new kinds")
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

section("widgets · D141")
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
section("github activity map")
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
section("widgets data")
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

section("claude fallback, BMO's jokes")
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

section("the settings window's codes (D147)")
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

section("wallpapers (D145)")
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

section("chassis (D164 stage 1)")
do
    local chassis = require("lib/chassis")
    local function L(t) local l = { mode = "islands", band = true, top = 8, mod_h = 24, radius = 7, n_pad = 10, n_r = 11, n_b = 33,
                                    screen_w = 1920, band_w = 2, frame_r = 14, reach = 16 }
                        for k, v in pairs(t or {}) do l[k] = v end; return l end
    local geo = { islands = { { x = 12, w = 182 }, { x = 0, w = 0 }, { x = 637, w = 280 } },
                  left = { x = 12, w = 448 }, center = { x = 637, w = 646 }, right = { x = 1492, w = 416 }, panel = { x = 12, w = 1896 } }
    test("the bar's own plates are only a fallback for a missing frame", function()
        local f = io.open("shell/mooi.plm"); local plm = f:read("a"); f:close()
        assert(plm:find("let pf = chassis_up", 1, true), "pf follows the running frame")
        local g = io.open("shell/mooi.luau"); local lu = g:read("a"); g:close()
        local sync = lu:match("function frame_sync%(%)(.-)\nend\n")
        assert(sync and not sync:find("island.morph", 1, true), "the frame no longer depends on morph or frame.on")
        assert(not sync:find("fact.chassis_up = true", 1, true), "review I3: a spawned frame has not drawn yet")
        assert(lu:find('on("chassis_ready"', 1, true), "the bar takes the frame's word that it has drawn")
        local fr = io.open("shell/mooi-frame.luau"); local fl = fr:read("a"); fr:close()
        assert(fl:find("emit chassis_ready", 1, true), "the frame says so after it has placed the pieces")
        assert(fl:find('fact["pk" .. i] = 0', 1, true), "review M1: an unused slot keeps no blend")
        assert(sync:find("fact.chassis_up = false", 1, true), "an exited frame hands the plates back to the bar")
        assert(not sync:find("code ~= 0 and frame_tries", 1, true), "the frame comes back after any exit, not only a failure")
    end)
    test("the frame scene draws pieces only from the model's facts", function()
        local f = io.open("shell/mooi-frame.plm"); local plm = f:read("a"); f:close()
        assert(plm:find("box { from: px0, py0; size: if(pj0, pw0, 0), if(pj0, ph0, 0); corner: pr0; blend: pk0", 1, true), "slot 0 from facts")
        assert(plm:find("px19", 1, true), "all 20 slots")
        eq(plm:find("ix0 - 3", 1, true), nil, "no geometry re-derived in the scene")
        eq(plm:find("let covL", 1, true), nil, "corner coverage comes from the logic")
    end)
    test("swell moves only a band that is on, and never down onto floating plates", function()
        local f = io.open("shell/mooi-frame.plm"); local plm = f:read("a"); f:close()
        assert(plm:find("let wl = if(band_on and frame_edges != 2", 1, true), "no band, no side swell (show is ignored in a body)")
        assert(plm:find("let wt = if(band_on and frame_edges != 1", 1, true), "no band, no top/foot swell")
        assert(plm:find("let wtt = min(wt, troom)", 1, true), "the top's swell is capped by the room above the plates")
        assert(plm:find("line W * 0.015625, bt + ft1", 1, true), "the top edge uses the capped samples")
        eq(chassis.look(config.validate({ bar = { mode = "islands", offset = 0, rail = false }, frame = { on = true, band = 2 } })).top_room, 3,
           "islands: 8 px row top − 2 px band − 3 px air")
        assert(chassis.look(config.validate({ bar = { mode = "full" } })).top_room >= 999, "joined pieces: no cap")
    end)
    test("review I1: the corner's round shrinks so it never reaches a floating plate", function()
        local l = L({ top = 15, band_w = 6, frame_r = 40 })
        local edge = chassis.pieces({ islands = { { x = 12, w = 60 }, { x = 1860, w = 50 } } }, l)
        eq(chassis.corner_cap(edge, l, "left"), 7, "plate at y=15, band 6, 2 px air: round ≤ 7")
        eq(chassis.corner_cap(edge, l, "right"), 7)
        eq(chassis.corner_cap(chassis.pieces({ islands = { { x = 600, w = 60 } } }, l), l, "left"), 999, "nothing near: no cap")
    end)
    test("review I2: in islands mode the top band leaves 3 px of air above the plates", function()
        local s = config.validate({ bar = { mode = "islands", rail = false, offset = 0 }, frame = { on = true, band = 12 } })
        local l = chassis.look(s)
        eq(l.top_band, 5, "a 12 px band is held at 5 above a row at 8"); eq(l.top_room, 0)
        local j = chassis.look(config.validate({ bar = { mode = "full" }, frame = { on = true, band = 12 } }))
        eq(j.top_band, 12, "joined shapes keep the band")
    end)
    test("review I4: with the band off no corner turns", function()
        local full = chassis.pieces({ panel = { x = 0, w = 1920 } }, L({ mode = "full", band = false, band_w = 0 }))
        eq(chassis.covers(full, L({ mode = "full", band = false, band_w = 0 }), "left"), false)
    end)
    test("review I5: notch pieces hang from the top and stay on the screen, band or not", function()
        local n = chassis.pieces({ left = { x = 4, w = 300 }, right = { x = 1600, w = 316 } }, L({ mode = "notch", band = false, offset = 0 }))
        eq(n[1].y, -40, "hangs from above the screen, as the bar's own notch does")
        eq(n[1].x, 0, "never starts left of the screen"); eq(n[2].x + n[2].w, 1920, "nor ends past it")
    end)
    test("full + frame: the bar spans edge to edge and is the frame's top", function()
        local p = chassis.pieces({ panel = { x = 12, w = 1896 } }, L({ mode = "full", band = true }))
        eq(p[1].x, 0, "flush with the band's left side"); eq(p[1].w, 1920, "and its right")
        local q = chassis.pieces({ panel = { x = 12, w = 1896 } }, L({ mode = "full", band = false }))
        eq(q[1].x, 12, "without the frame it floats where the bar lays it")
        eq(p[1].r, 0, "square ends into the band: the frame's inner corner does the rounding")
        eq(p[1].k, 0, "no blend: it covers the band already, and a blend bulged where its foot meets the corner")
        eq(p[1].j, true, "but it is joined to the band")
        local l = L({ mode = "full", band = true })
        eq(chassis.covers(p, l, "left"), true, "so the frame's corner still turns at its foot")
        local f = io.open("shell/mooi.plm"); local plm = f:read("a"); f:close()
        assert(plm:find("show: hc_edge and not (pf and bar_full)", 1, true), "the bar's own full outline steps aside for the chassis")
        assert(plm:find("show: (bar_full or helix_edges) and hc_corners and not (pf and bar_full)", 1, true), "and its corner marks")
    end)
    test("frame off: no corner is drawn (a body ignores show)", function()
        local f = io.open("shell/mooi-frame.plm"); local plm = f:read("a"); f:close()
        assert(plm:find("let frr = if(band_on, clamp(st_frame_r, 0, 40), 0)", 1, true), "no band, no round in the screen's corners")
    end)
    test("attach: the band comes down to the islands' top and they hang from it, one body", function()
        local s = config.validate({ bar = { mode = "islands", rail = false, offset = 0, height = 24 }, frame = { on = true, islands = "attach", band = 2 } })
        local l = chassis.look(s)
        eq(l.attach, true); eq(l.top_band, 8, "band to the row's top: gaps are recesses, not tabs"); eq(l.top_room, 0)
        local p = chassis.pieces({ islands = { { x = 12, w = 100 } } }, l)
        eq(p[1].y, -40); eq(p[1].y + p[1].h, 32, "one foot"); eq(p[1].j, true)
        eq(p[1].r, l.radius, "rounded at the foot like any plate"); eq(p[1].k, 8, "a small fillet where it meets the band: no hard recess corners")
        local off = chassis.look(config.validate({ bar = { mode = "islands" }, frame = { on = false, islands = "attach" } }))
        eq(off.attach, false, "no frame, nothing to attach to")
    end)
    test("chassis: a floating island carries its own look", function()
        local p = chassis.pieces({ islands = { { x = 12, w = 100, id = "weather" } } }, L(),
            { [1] = { fill = 0, r = 12, outline = 2, glow = 1, colour = { r = 1, g = 0, b = 0 } } })
        eq(p[1].r, 12); eq(p[1].fill, 0); eq(p[1].outline, 2); eq(p[1].glow, 1); eq(p[1].colour.r, 1)
        local q = chassis.pieces({ islands = { { x = 12, w = 100 } } }, L())
        eq(q[1].fill, nil, "no look given: the frame draws the style's")
    end)
    test("bar-geo names each island's module, for its look", function()
        local f = io.open("shell/bar.luau"); local b = f:read("a"); f:close()
        assert(b:find("id = f.id", 1, true), "the bar writes each island's module id")
    end)
    test("floating plates are drawn by their own bodies with their own look", function()
        local f = io.open("shell/mooi-frame.plm"); local plm = f:read("a"); f:close()
        assert(plm:find("size: if(pj0, pw0, 0), if(pj0, ph0, 0)", 1, true), "the band's tiles draw only joined pieces")
        assert(plm:find("// plate 0", 1, true) and plm:find("pf0 > 2.5", 1, true) and plm:find("po0", 1, true) and plm:find("pc0_r", 1, true),
            "each floating plate is its own body, with its fill, outline and colour")
        assert(plm:find("let bt = if(battach, btop, min(frame_band, btop))", 1, true), "attach: the band reaches the islands' top")
        local g = io.open("shell/mooi-frame.luau"); local lu = g:read("a"); g:close()
        assert(lu:find("modlook.of", 1, true), "the frame resolves each island's look")
        assert(plm:find("size: if(pj0 or pf0 > 2.5, 0, pw0)", 1, true), "no fill: no body at all, not an invisible one")
        assert(plm:find("frost: 1% * st_frost * if(pf0 > 1.5 and pf0 < 2.5, 1, 0)", 1, true), "frost only on a glass plate")
        assert(plm:find("frost: 1% * st_frost * if(glassy, 1, 0)", 1, true), "and on the band only when glassy")
        assert(plm:find("size: if(pj0 or pf0 < 2.5 or if(po0 > 1.5", 1, true), "no outline: no outline box (stroke 0 would fill it)")
        assert(plm:find("show: not pj0 and pw0 > 0 and bar_frame > 0.5 and bar_frame < 1.5", 1, true), "Outline: Corners marks each floating plate")
        assert(plm:find("// plate 0 outline", 1, true),
            "a plate with no fill still draws its outline (a body's opacity takes its border with it)")
    end)
    test("chassis: the Pill and its moons, floating without the frame and hanging from it", function()
        local geo = { islands = { { x = 12, w = 100 } }, pill = { x = 860, w = 200 }, moons = { { x = 828, w = 24 } } }
        local off = chassis.pieces(geo, L({ mode = "pill", band = false }))
        eq(#off, 3, "a side island, the Pill, a moon")
        local p, m = off[2], off[3]
        eq(p.x, 860); eq(p.w, 200); eq(p.y, 8); eq(p.h, 24); eq(p.r, 12, "a capsule: half its height"); eq(p.j, false)
        eq(m.w, 24); eq(m.h, 24); eq(m.r, 12, "a moon is a circle"); eq(m.y, 8)
        local on = chassis.pieces(geo, L({ mode = "pill", band = true }))
        local q, n = on[2], on[3]
        eq(q.y, -40); eq(q.y + q.h, 32, "one foot"); eq(q.j, true, "hangs from the band")
        eq(n.j, true, "the moon pinches off the band"); eq(n.y + n.h, 30, "a little shorter than the Pill")
        local alone = chassis.pieces({ islands = {}, pill = { x = 860, w = 200 }, moons = {} }, L({ mode = "pill", band = false }))
        eq(#alone, 1, "Pill alone: no side islands")
    end)
    test("chassis: islands float as plates, one per visible module, never up into the band", function()
        local p = chassis.pieces(geo, L())
        eq(#p, 2, "the 0-wide module has no piece")
        eq(p[1].x, 9); eq(p[1].w, 188); eq(p[1].y, 8); eq(p[1].h, 24); eq(p[1].k, 0, "no blend: crisp plates")
        for _, q in ipairs(p) do assert(q.y >= 8, "no piece reaches above the row: no hump") end
    end)
    test("chassis: one foot whatever the frame does", function()
        for _, band in ipairs({ true, false }) do
            local p = chassis.pieces(geo, L({ band = band }))
            eq(p[1].y + p[1].h, 32, "islands foot, band " .. tostring(band))
            local f = chassis.pieces(geo, L({ mode = "full", band = band }))
            eq(f[1].y + f[1].h, 32, "full foot, band " .. tostring(band))
        end
        eq(chassis.foot(L()), 32); eq(chassis.foot(L({ mode = "notch" })), 33)
    end)
    test("chassis: the notch's foot is the same with the band on or off", function()
        local on = chassis.look(config.validate({ bar = { mode = "notch", height = 24, offset = 0 }, frame = { on = true } }))
        local off = chassis.look(config.validate({ bar = { mode = "notch", height = 24, offset = 0 }, frame = { on = false } }))
        eq(chassis.foot(on), chassis.foot(off), "one foot"); eq(chassis.foot(on), 31, "the windows' reserve line (st_res)")
        local f = io.open("shell/mooi.plm"); local plm = f:read("a"); f:close()
        assert(plm:find("let n_b = st_res", 1, true), "the bar's own notch plates use the same foot")
    end)
    test("chassis: offset and rail move the row and its foot together", function()
        local s = config.validate({ bar = { offset = 6, rail = true, height = 30 } })
        local l = chassis.look(s)
        eq(l.top, 21); eq(chassis.foot(l), 51)
    end)
    test("chassis: notch pieces hang from the top, full joins the band", function()
        local n = chassis.pieces(geo, L({ mode = "notch" }))
        eq(#n, 3); eq(n[1].y, -40); eq(n[1].x, 2); eq(n[1].w, 468); eq(n[1].y + n[1].h, 33); eq(n[1].k, 12)
        eq(chassis.pieces(geo, L({ mode = "full" }))[1].y, -40)
    end)
    test("chassis: the corner turns at a joined piece's foot; floating islands leave it alone", function()
        local edge = { islands = { { x = 4, w = 40 }, { x = 1880, w = 36 } }, panel = { x = 0, w = 1920 },
                       left = { x = 6, w = 300 }, right = { x = 1500, w = 410 } }
        eq(chassis.covers(chassis.pieces(edge, L()), L(), "left"), false, "a floating island never pulls the band down")
        local full = chassis.pieces(edge, L({ mode = "full" }))
        eq(chassis.covers(full, L(), "left"), true); eq(chassis.covers(full, L(), "right"), true)
        local notch = chassis.pieces(edge, L({ mode = "notch" }))
        eq(chassis.covers(notch, L(), "left"), true); eq(chassis.covers(notch, L(), "right"), true)
        local mid = chassis.pieces({ center = { x = 800, w = 300 } }, L({ mode = "notch" }))
        eq(chassis.covers(mid, L(), "left"), false); eq(chassis.covers(mid, L(), "right"), false)
    end)
end

section("modlook (D166)")
do
    local ML = require("lib/modlook")
    local roles = { ember = { r = 0.9, g = 0.5, b = 0.2 }, primary = { r = 0.5, g = 0.8, b = 0.7 } }
    test("modlook: style means the bar's own; overrides win; a group is styled by its head", function()
        local s = config.validate({ bar = { radius = 7, height = 24, surface = "glass", frame = "line",
            left = { "settings+resources", "weather" }, center = { "media" }, right = { "clock" },
            modules = { settings = { fill = "solid", rounding = "pill", colour = "ember" } } } })
        eq(ML.head(s, "resources"), "settings", "a member's look is its head's")
        eq(ML.head(s, "weather"), "weather")
        local l = ML.of(s, "resources", roles)
        eq(l.fill, 0); eq(l.r, 12, "pill = half the height"); eq(l.colour.r, 0.9)
        local w = ML.of(s, "weather", roles)
        eq(w.fill, 2, "glass from the bar's surface"); eq(w.r, 7); eq(w.outline, 1); eq(w.colour, nil)
    end)
    test("modlook: the Look card's codes round-trip, and a choice lands on the group's head", function()
        for k, key in ipairs(ML.KEYS) do
            for v, val in ipairs(ML.VALUES[key]) do
                local kk, vv = ML.decode((k - 1) * 16 + (v - 1))
                eq(kk, key); eq(vv, val)
            end
        end
        eq(ML.decode(15 * 16), "reset")
        local s = config.validate({ bar = { left = { "settings+resources" }, center = { "media" }, right = { "clock" } } })
        ML.apply(s, "resources", "fill", "glass")
        eq(s.bar.modules.settings.fill, "glass", "written on the head"); eq(s.bar.modules.resources.fill, "style", "not on the member")
        ML.apply(s, "settings", "reset")
        eq(s.bar.modules.settings.fill, "style", "reset puts the style back (a value, so a merge keeps it)")
        local idx = ML.index(config.validate({ bar = { left = { "weather" }, center = { "media" }, right = { "clock" },
            modules = { weather = { colour = "ember", rounding = "pill" } } } }), "weather")
        eq(idx.colour, 2); eq(idx.rounding, 4); eq(idx.fill, 0)
        eq(ML.index(config.validate({ bar = { modules = { clock = { colour = "#123456" } } } }), "clock").colour, -1, "a custom colour is none of the swatches")
    end)
    test("modlook: every value maps, and a hex or the wallpaper's colour is a colour", function()
        local s = config.validate({ bar = { surface = "clear", frame = "none", radius = 7, height = 30, modules = {
            clock = { colour = "#ff0000", rounding = "square", outline = "accent", glow = "strong", fill = "tinted" },
            weather = { colour = "wallpaper", rounding = "soft", outline = "none", fill = "none" } } } })
        local c = ML.of(s, "clock", roles)
        eq(c.colour.r, 1); eq(c.colour.g, 0); eq(c.r, 0); eq(c.outline, 2); eq(c.glow, 2); eq(c.fill, 1)
        local w = ML.of(s, "weather", roles)
        eq(w.colour.g, 0.8, "the wallpaper's primary"); eq(w.r, 4); eq(w.outline, 0); eq(w.fill, 3)
        local d = ML.of(s, "tray", roles)
        eq(d.fill, 3, "clear surface: no fill"); eq(d.outline, 0, "no outline style: none"); eq(d.glow, 0)
        eq(ML.of(config.validate({ bar = { surface = "mech" } }), "tray", roles).fill, 0, "machined reads as solid")
    end)
end

section("Bar & Frame settings (D166)")
do
    test("settings: one Bar & Frame page holds the bar, its layout, the frame, workspaces and media", function()
        local idx = require("lib/settings_index")
        local pages = {}
        for _, r in ipairs(idx) do pages[r.page] = true end
        for _, gone in ipairs({ "The bar", "Layout", "Screen frame", "Workspaces", "Media" }) do
            eq(pages[gone], nil, "no page " .. gone)
        end
        eq(pages["Bar & Frame"], true)
        local want = { "Shape", "Style", "Screen frame", "Outline", "Surface", "Thickness", "Islands with the frame", "Everyday", "Shows", "Layout", "Band thickness", "Frame corners" }
        for _, title in ipairs(want) do
            local found = false
            for _, r in ipairs(idx) do if r.title == title and r.page == "Bar & Frame" then found = true end end
            eq(found, true, title .. " is on Bar & Frame")
        end
    end)
    test("review I1/I2: search opens a row's fold, lands where it is, and the scroll stays on the page", function()
        local idx = require("lib/settings_index")
        local wheel, frame_edge
        for _, r in ipairs(idx) do
            if r.page == "Bar & Frame" and r.title == "Mouse wheel" then wheel = r end
            if r.page == "Bar & Frame" and r.title == "Frame edge" then frame_edge = r end
        end
        assert(wheel and wheel.fold == idx.modules_fold, "a row knows its fold")
        assert(wheel.fy > idx.modules_look_y + 300, "rows after the layout sit below it (" .. tostring(wheel.fy) .. ")")
        assert(frame_edge.fold ~= nil and frame_edge.fy < frame_edge.y, "with only its fold open it is higher than with all open")
        local f = io.open("shell/mooi-settings.luau"); local lu = f:read("a"); f:close()
        assert(lu:find("r.fold", 1, true) and lu:find("r.fy", 1, true), "jump opens the fold and uses its place")
        local g = io.open("shell/mooi-settings.plm"); local plm = g:read("a"); g:close()
        assert(plm:find("follow set_scroll_s = clamp(set_scroll, 0, ", 1, true), "the scroll never stays past a page that shrank")
    end)
    test("review I3/I4/I5/M1", function()
        local f = io.open("shell/mooi-frame.plm"); local plm = f:read("a"); f:close()
        local fp = plm:sub((plm:find("surface frame_p", 1, true)))
        assert(fp:find("box { from: px0, py0; size: pw0, ph0;", 1, true), "an island grows out of its plate in the place's body (no seam)")
        assert(plm:find("border: if(bar_frame < 0.5 and (not band_on or st_frame_edge < 1.5), st_owidth, 0)", 1, true),
            "frame edge None only matters with the band on")
        local g = io.open("shell/mooi-frame.luau"); local lu = g:read("a"); g:close()
        assert(lu:find("palette.colours", 1, true) and lu:find("ferro.hex", 1, true), "Wallpaper is the wallpaper's primary, not the theme's main")
        local st = require("lib/style")
        local old = config.validate({ bar = { style = "floating", surface = "solid", frame = "none", outline_width = 2, outline_colour = "subtle",
            shadow = "strong", ground = "clear", pill = "glow", opacity = 100, rail = false, accents = false } })
        eq(st.preset_index(old, st.BAR_PRESETS), 2, "a Floating bar from before still reads Floating, not Custom")
    end)
    test("Look…: the bar's edit mode opens Settings at the module's look", function()
        local f = io.open("shell/mooi.plm"); local plm = f:read("a"); f:close()
        assert(plm:find('"Look…", edit_op, ed_sel * 10 + 6', 1, true), "a Look… button in the inspector")
        local g = io.open("shell/bar.luau"); local b = g:read("a"); g:close()
        assert(b:find("op == 6", 1, true) and b:find("open_module", 1, true), "it opens Settings at that module")
        local h = io.open("shell/mooi-settings.luau"); local s = h:read("a"); h:close()
        assert(s:find('on("open_module"', 1, true), "Settings selects it and opens the Modules fold")
        local w = io.open("shell/mooi-settings.plm"); local wp = w:read("a"); w:close()
        assert(wp:find("event open_module ->", 1, true), "the window declares the event (an undeclared one is dropped)")
        local idx = require("lib/settings_index")
        assert(type(idx.modules_fold) == "string" and idx.modules_fold:match("^fd_%d+_%d+$"), "the Modules fold's fact is known")
    end)
    test("settings: folding sections, a renamed colour page, no Steel", function()
        local f = io.open("shell/mooi-settings.plm"); local plm = f:read("a"); f:close()
        assert(plm:find("fact fd_", 1, true), "fold state facts")
        assert(plm:find("= not fd_", 1, true), "a header press opens or folds it")
        eq(plm:find("color: fl.ink }", 1, true), nil, "no title in the dark ink (it is for light surfaces)")
        eq(plm:find("mix(fl.ink, fl.phos, fd_", 1, true), nil, "a closed fold's name is legible")
        assert(plm:find('"Theme & colour"', 1, true), "Colour is Theme & colour")
        eq(plm:find('"Steel"', 1, true), nil, "no Steel anywhere in the window")
        local idx = require("lib/settings_index")
        -- one name per thing, the same on every page; nothing shown that does nothing yet
        local titles = {}
        for _, r in ipairs(idx) do titles[r.title] = (titles[r.title] or 0) + 1 end
        eq(titles["Density"], nil, "Density waits until the modules follow it (stage 4)")
        for _, r in ipairs(idx) do
            if r.tab == 0 then assert(r.title ~= "Layout", "the bar's shape is called Shape on Quick too") end
        end
        eq(titles["Material"], nil, "the surface is called Surface (Material is D164's ferrolume/liquid/cartridge)")
        assert(titles["Surface"], "Surface")
        assert(plm:find('"Shape", "Islands, one bar across the screen, pieces hanging from the top, or the Pill", "bar.mode"', 1, true) == nil
            and select(2, plm:gsub('"Pill"', "")) >= 2, "Shape offers Pill on Quick as on Bar & Frame")
        assert(plm:find("a thin line round each, or no plates at all", 1, true), "Style says what each one is")
    end)
end

section("pill (D168)")
do
    local P = require("lib/pill")
    local CFG = { order = { "battery", "record", "notify", "music", "osd", "idle" }, off = {}, moons = 3, multi = "satellites" }
    local function cfg(t) local c = {}; for k, v in pairs(CFG) do c[k] = v end; for k, v in pairs(t or {}) do c[k] = v end; return c end
    test("pill settings: defaults, and an unknown activity is refused", function()
        local d = config.defaults()
        eq(d.bar.mode, "islands"); eq(d.pill.sides, "show"); eq(d.pill.multi, "satellites"); eq(d.pill.moons, 3)
        eq(table.concat(d.pill.order, ","), "battery,record,notify,music,osd,idle"); eq(#d.pill.off, 0)
        eq(config.validate({ bar = { mode = "pill" } }).bar.mode, "pill")
        local s, p = config.validate({ pill = { order = { "music", "lasers" } } })
        eq(table.concat(s.pill.order, ","), "battery,record,notify,music,osd,idle", "refused whole"); eq(#p, 1)
    end)
    test("pill: idle alone; music then a notification in the same second; music back after 6 s", function()
        local st = P.state()
        eq(P.compute(st, cfg(), 0).main, "idle")
        P.note(st, "media", { playing = true, title = "Hail to the King", artist = "A7X" }, 1000)
        P.note(st, "notify", { app = "Discord", summary = "hey" }, 1000)
        local r = P.compute(st, cfg(), 1200)
        eq(r.main, "notify"); eq(#r.moons, 1); eq(r.moons[1], "music")
        local later = P.compute(st, cfg(), 7100)
        eq(later.main, "music"); eq(#later.moons, 0, "no moon left")
        eq(P.next_change(st, 1200), 5800)
    end)
    test("pill.place: centred, moons alternate left and right with 8 px between", function()
        local p = P.place(1920, 200, 3)
        eq(p.x, 860); eq(#p.moons, 3)
        eq(p.moons[1], 860 - 8 - 24, "first moon to the left"); eq(p.moons[2], 860 + 200 + 8, "second to the right")
        eq(p.moons[3], 860 - 2 * (8 + 24), "third further left")
    end)
    test("bar: the Pill is fed and laid out without touching the saved layout", function()
        local f = io.open("shell/bar.luau"); local b = f:read("a"); f:close()
        assert(b:find('require("lib/pill")', 1, true), "the bar uses lib/pill")
        assert(b:find("center = {}", 1, true), "Pill mode lays out with an empty centre")
        assert(not b:find("b.center = {}", 1, true), "never writing the saved list")
        assert(b:find("geo.pill", 1, true) and b:find("geo.moons", 1, true), "the frame learns where the Pill and moons are")
        assert(b:find("ctx.on_signal(function(n)", 1, true), "notifications from Signal Loom (review I2)")
        assert(b:find("pill_timed = pillmod.next_change(pst, pill_ms) ~= nil", 1, true), "the Pill is looked at again after a timed thing ends")
        for _, ev in ipairs({ "pill_press", "pill_scroll", "pill_moon" }) do
            assert(b:find('on("' .. ev .. '"', 1, true), ev .. " handled")
        end
    end)
    test("edit mode's shelf can hold every module, each with a name", function()
        local bl = require("lib/barlayout")
        local f = io.open("shell/mooi.plm"); local plm = f:read("a"); f:close()
        local max = tonumber(plm:match("model shelf_items max (%d+)"))
        assert(max and max >= #bl.ORDER, "the shelf holds all " .. #bl.ORDER .. " modules (max " .. tostring(max) .. ")")
        local g = io.open("shell/bar.luau"); local b = g:read("a"); g:close()
        local names = b:match("local NAMES = (%b{})")
        assert(names, "the shelf's names")
        for _, id in ipairs(bl.ORDER) do
            assert(names:find("[%s{,]" .. id .. " = \"") or names:find('%["' .. id .. '"%] = "'), id .. " has a name on the shelf")
        end
    end)
    test("the bar draws the Pill: imported, drawn while on, its presses wired", function()
        local f = io.open("shell/mooi.plm"); local plm = f:read("a"); f:close()
        assert(plm:find('import "ui/pill.plm"', 1, true), "imported")
        assert(plm:find("PillBody()", 1, true), "drawn")
        local g = io.open("shell/ui/pill.plm"); local ui = g:read("a"); g:close()
        assert(ui:find("show: pill_on", 1, true), "only in Pill mode")
        -- an event without "->" stays in the scene: the logic never hears the press
        for _, ev in ipairs({ "pill_press", "pill_scroll", "pill_moon" }) do
            assert(plm:find("event " .. ev .. " ->", 1, true), ev .. " reaches the logic")
        end
        assert(ui:find("emit pill_press", 1, true) and ui:find("emit pill_scroll", 1, true) and ui:find("emit pill_moon", 1, true), "presses, scroll, moons")
    end)
    test("pill.reorder: up, down, on and off — idle always stays and stays on", function()
        local order = { "battery", "record", "notify", "music", "osd", "idle" }
        local o, off = P.reorder(order, {}, 3, "up")
        eq(table.concat(o, ","), "battery,record,music,notify,osd,idle")
        o, off = P.reorder(o, off, 0, "up"); eq(o[1], "battery", "the top cannot go higher")
        o, off = P.reorder(o, off, 4, "down"); eq(o[5], "osd", "osd cannot pass idle"); eq(o[6], "idle")
        o, off = P.reorder(o, off, 1, "toggle"); eq(off[1], "record", "switched off")
        o, off = P.reorder(o, off, 1, "toggle"); eq(#off, 0, "and on again")
        o, off = P.reorder(o, off, 5, "toggle"); eq(#off, 0, "idle cannot be switched off")
    end)
    test("settings: Shape offers Pill, and the Pill's own fold", function()
        local idx = require("lib/settings_index")
        local want = { ["Side groups"] = 1, ["Two at once"] = 1, ["Moons at most"] = 1, ["What may take it"] = 1 }   -- D188 titles
        for _, r in ipairs(idx) do if want[r.title] and r.page == "Bar & Frame" then want[r.title] = nil end end
        eq(next(want), nil, "every Pill row on Bar & Frame")
        local f = io.open("shell/mooi-settings.plm"); local plm = f:read("a"); f:close()
        assert(plm:find('"Pill", sv_bar_mode == 3', 1, true), "Shape lists Pill")
        assert(plm:find("emit pill_act", 1, true) or plm:find("pill_act, ", 1, true), "the order list's buttons")
    end)
    test("pill: everything switched off still shows idle", function()
        local st = P.state()
        P.note(st, "media", { playing = true, title = "x" }, 0)
        local off = { battery = true, record = true, notify = true, music = true, osd = true, idle = true }
        eq(P.compute(st, cfg({ off = off }), 10).main, "idle")
    end)
    test("pill: a volume change over music — a moon for 2 s, or the split partner", function()
        local st = P.state()
        P.note(st, "media", { playing = true, title = "Song" }, 0)
        P.note(st, "osd", { kind = "vol", value = 0.4 }, 100)
        local r = P.compute(st, cfg(), 200)
        eq(r.main, "music"); eq(r.moons[1], "osd")
        local sp = P.compute(st, cfg({ multi = "split" }), 200)
        eq(sp.split, "osd"); eq(#sp.moons, 0, "the partner is not also a moon")
        eq(P.compute(st, cfg(), 2200).moons[1], nil, "gone after 2 s")
        eq(r.view.osd.value, 0.4); eq(r.view.osd.t1, "VOL")
    end)
    test("pill: battery low at 15 % not charging, charging shown 4 s, pins and the moon cap", function()
        local st = P.state()
        P.note(st, "battery", { percent = 16, charging = false }, 0)
        eq(P.compute(st, cfg(), 10).main, "idle", "16 % is not low")
        P.note(st, "battery", { percent = 15, charging = false }, 20)
        eq(P.compute(st, cfg(), 30).main, "battery")
        P.note(st, "battery", { percent = 15, charging = true }, 1000)
        local c = P.compute(st, cfg(), 1500)
        eq(c.main, "battery"); eq(c.view.battery.glyph, "charging")
        eq(P.compute(st, cfg(), 5100).main, "idle", "charging shown 4 s, then not low any more")
        P.note(st, "recording", { on = true }, 6000)
        P.note(st, "media", { playing = true, title = "s" }, 6000)
        P.note(st, "notify", { app = "a", summary = "b" }, 6000)
        P.note(st, "osd", { kind = "bri", value = 0.5 }, 6000)
        local m = P.compute(st, cfg({ moons = 2 }), 6100)
        eq(m.main, "record"); eq(#m.moons, 2, "capped")
        P.note(st, "pin", { id = "music" }, 6200)
        eq(P.compute(st, cfg(), 6300).main, "music", "a pressed moon is main")
        eq(P.compute(st, cfg(), 12300).main, "record", "for 6 s")
    end)
end

section("the Pill's face, hiding and nodes (D169)")
do
    local P = require("lib/pill")
    local F = require("lib/pillface")
    local chassis = require("lib/chassis")
    local CFG = { order = { "battery", "record", "notify", "music", "osd", "idle" }, off = {}, moons = 3, multi = "satellites", face = "time", autohide = false }
    local function cfg(t) local c = {}; for k, v in pairs(CFG) do c[k] = v end; for k, v in pairs(t or {}) do c[k] = v end; return c end
    test("pill settings: the face, hiding, and nodes", function()
        local d = config.defaults()
        eq(d.pill.face, "time"); eq(d.pill.autohide, false)
        local s, p = config.validate({ pill = { face = "bmo", autohide = true, multi = "nodes" } })
        eq(#p, 0); eq(s.pill.face, "bmo"); eq(s.pill.autohide, true); eq(s.pill.multi, "nodes")
        local _, p2 = config.validate({ pill = { face = "dragon" } }); eq(#p2, 1, "an unknown face is refused")
    end)
    test("pill: each face has its own width; BMO widens to say a line", function()
        local st = P.state()
        eq(P.compute(st, cfg({ face = "time" }), 0).width, 120)
        eq(P.compute(st, cfg({ face = "nexus" }), 0).width, 104)
        eq(P.compute(st, cfg({ face = "bmo" }), 0).width, 72, "just his face (D170: his full face)")
        P.note(st, "say", { text = "beep boop!" }, 0)
        local r = P.compute(st, cfg({ face = "bmo" }), 100)
        eq(r.width, 72 + 7 * 10 + 16, "his line fits"); eq(r.view.idle.t1, "beep boop!")
        eq(P.compute(st, cfg({ face = "time" }), 100).view.idle.t1, "", "only BMO speaks")
    end)
    test("pill: hidden when idle, back while pointed at, never over something happening", function()
        local st = P.state()
        local r = P.compute(st, cfg({ autohide = true }), 0)
        eq(r.hidden, true); eq(r.width, 44, "a sliver")
        eq(P.compute(st, cfg({ autohide = false }), 0).hidden, false)
        P.note(st, "peek", {}, 1000)
        eq(P.compute(st, cfg({ autohide = true }), 4000).hidden, false, "pointed at: back for 4 s")
        eq(P.compute(st, cfg({ autohide = true }), 5100).hidden, true, "and away again")
        eq(P.next_change(st, 1000), 4000, "the logic looks again when the peek ends")
        P.note(st, "media", { playing = true, title = "Song" }, 6000)
        eq(P.compute(st, cfg({ autohide = true }), 6000).hidden, false, "music shows")
    end)
    test("pill: nodes sit further out, on a trace", function()
        local sat = P.place(1920, 200, 2)
        local nod = P.place(1920, 200, 2, "nodes")
        eq(sat.moons[1], 860 - 8 - 24); eq(nod.moons[1], 860 - 18 - 24, "an 18 px trace")
        eq(nod.moons[2], 1060 + 18)
    end)
    test("pillface: a poke giggles, five pokes make him grumpy", function()
        local st = F.new("happy")
        local v = F.poke(st, 0, 0.5)
        eq(F.view(st, 100).face, "giggle")
        eq(F.view(st, 5000).face, "happy", "the reaction passes")
        for i = 1, 5 do F.poke(st, 6000 + i * 150, 0.5) end
        eq(F.view(st, 6900).face, "grumpy"); eq(F.view(st, 6900).say, "hey!")
        eq(st.mood, "grumpy")
        assert(v.say == nil or type(v.say) == "string")
    end)
    test("pillface: a first poke always gets a line, whatever his mood (the face depends on it)", function()
        for _, mood in ipairs({ "happy", "curious", "sleepy", "excited", "surprised", "playful", "focused", "grumpy" }) do
            local st = F.new(mood)
            F.poke(st, 0, 0.9)
            assert(F.view(st, 100).say ~= "", mood .. ": a line")
        end
    end)
    test("pillface: sleepy at night; talks only as BMO's Talk allows", function()
        local st = F.new("happy")
        F.tick(st, 0, { hour = 2, talk = "off" }, 0.1, 0.0)
        eq(st.mood, "sleepy", "late at night")
        eq(F.view(st, 10).say, "", "talk off: silent")
        local st2 = F.new("happy")
        F.tick(st2, 0, { hour = 14, talk = "chatty" }, 0.0, 0.0)
        local said = F.view(st2, 10).say
        assert(said ~= "", "chatty: he says something")
        eq(F.view(st2, 10 + F.SAY_MS).say, "", "for a while")
    end)
    test("chassis: a hidden Pill is a sliver; nodes are square pads", function()
        local function L(t) local l = { mode = "pill", band = false, top = 8, mod_h = 24, radius = 7, screen_w = 1920, band_w = 2, frame_r = 14, reach = 16 }
            for k, v in pairs(t or {}) do l[k] = v end; return l end
        local off = chassis.pieces({ islands = {}, pill = { x = 938, w = 44, slim = true }, moons = {} }, L())
        eq(off[1].h, 6); eq(off[1].r, 3); eq(off[1].y, 8)
        local on = chassis.pieces({ islands = {}, pill = { x = 938, w = 44, slim = true }, moons = {} }, L({ band = true }))
        eq(on[1].y, -40); eq(on[1].y + on[1].h, 2 + 6, "a short tab from the band"); eq(on[1].j, true)
        local nodes = chassis.pieces({ islands = {}, pill = { x = 860, w = 200 }, moons = { { x = 818, w = 24 } }, nodes = true }, L())
        eq(nodes[2].r, 5, "a pad, not a circle"); eq(nodes[2].w, 24)
    end)
    test("settings: the Pill's face, hiding when idle, and Nodes", function()
        local idx = require("lib/settings_index")
        local want = { ["Face, wheel and pads"] = 1, ["When idle"] = 1 }   -- D188: the face is chosen on the Pill
        for _, r in ipairs(idx) do if want[r.title] and r.page == "Bar & Frame" then want[r.title] = nil end end
        eq(next(want), nil, "both rows on Bar & Frame")
        local f = io.open("shell/mooi-settings.plm"); local plm = f:read("a"); f:close()
        assert(plm:find('"Nodes"', 1, true), "Two at once offers Nodes")
        local setters = require("lib/setters")
        local seen = {}
        for _, p in ipairs(setters.SETTERS) do seen[p] = true end
        assert(seen["pill.face"] and seen["pill.autohide"], "setters appended")
    end)
    test("review: the Pill never grows past the room it has (I3)", function()
        local st = P.state()
        P.note(st, "media", { playing = true, title = string.rep("x", 70), artist = string.rep("y", 25) }, 0)
        local r = P.compute(st, cfg({ max_w = 400 }), 0)
        eq(r.width <= 400, true, "capped (" .. r.width .. ")")
        eq(P.compute(st, cfg(), 0).width > 400, true, "uncapped without a limit")
    end)
    test("review: in split, each half is its own width (I4)", function()
        local st = P.state()
        P.note(st, "media", { playing = true, title = "Song", artist = "Band" }, 0)
        P.note(st, "osd", { kind = "vol", value = 0.42 }, 0)
        local r = P.compute(st, cfg({ multi = "split" }), 100)
        eq(r.split, "osd")
        eq(r.w1, P.compute(P.state(), cfg(), 0).width == 120 and r.w1 or r.w1)   -- exists
        assert(r.w1 < r.width - r.w1, "music (short) is the narrower half: " .. r.w1 .. " of " .. r.width)
        local f = io.open("shell/bar.luau"); local b = f:read("a"); f:close()
        assert(b:find("fact.pill_w1 = r.w1", 1, true), "the bar uses compute's own w1")
    end)
    test("review: a notice's width fits the app and summary it draws (M1)", function()
        local st = P.state()
        P.note(st, "notify", { app = "notify-send", summary = "mooi review" }, 0)
        eq(P.compute(st, cfg(), 10).width, 44 + 7 * (11 + 11 + 2))
    end)
    test("review: the first battery report is not a charging edge (M2)", function()
        local st = P.state()
        P.note(st, "battery", { percent = 80, charging = true }, 0)
        eq(P.compute(st, cfg(), 100).main, "idle", "on AC at start: nothing to say")
        P.note(st, "battery", { percent = 80, charging = false }, 200)
        P.note(st, "battery", { percent = 80, charging = true }, 300)
        eq(P.compute(st, cfg(), 400).main, "battery", "plugged in later: shown")
    end)
    test("review: scroll, live bars, notifications, hover and the tab (C1, I1, I2, M4, M5)", function()
        local f = io.open("shell/bar.luau"); local b = f:read("a"); f:close()
        eq(b:find('"audio.volume", (d > 0) and "+5"', 1, true), nil, "no string to an absolute volume")
        assert(b:find('sys.call, "audio.volume", math.max(0, math.min(1, cur_vol + step))', 1, true), "volume stepped from the current level")
        assert(b:find('sys.call, "brightness.level", math.max(0.01, math.min(1, cur_bri + step))', 1, true), "brightness steps over a brightness change")
        assert(b:find('(s.bar.mode == "pill" and env.playing)', 1, true), "the Pill's music bars are live")
        eq(b:find('"notification_history"', 1, true), nil, "not the history (empty while mooi keeps them)")
        assert(b:find("ctx.on_signal", 1, true), "fed by Signal Loom's arrivals")
        local g = io.open("shell/signals.luau"); local sg = g:read("a"); g:close()
        assert(sg:find("on_signal = function(fn) pill_hook = fn end", 1, true), "Loom hands new signals on")
        local u = io.open("shell/ui/pill.plm"); local ui = u:read("a"); u:close()
        assert(ui:find("if(pill_hidden, 0, fl.top)", 1, true), "hidden: the zone reaches the top")
        assert(ui:find("emit pill_hover(0)", 1, true) and ui:find("emit pill_hover(1)", 1, true), "entering and leaving reach the logic")
        assert(b:find('if pill_hovering then pillmod.note(pst, "peek"', 1, true), "a resting pointer keeps it open")
    end)
    test("only Signal Loom runs the notification service (watching one claims the name)", function()
        local ls = io.popen("ls shell/*.luau shell/*.plm"); local files = ls:read("a"); ls:close()
        for f in files:gmatch("[^\n]+") do
            local h = io.open(f); local src = h:read("a"); h:close()
            local hit = src:find('"notification_history"', 1, true) or src:find('sys.watch("notifications"', 1, true)
            if f ~= "shell/signals.luau" then eq(hit, nil, f .. " leaves the notification service to Signal Loom") end
        end
        local w = io.open("shell/mooi-widgets.luau"); local wl = w:read("a"); w:close()
        assert(wl:find('sys.watch, "files:nexus-feed.json"', 1, true), "the launcher reads Loom's feed")
    end)
    test("the bar feeds the face, the hiding and the nodes", function()
        local f = io.open("shell/bar.luau"); local b = f:read("a"); f:close()
        assert(b:find('require("lib/pillface")', 1, true), "BMO's face")
        assert(b:find("face = pill_view or p.face", 1, true) and b:find("autohide = p.autohide", 1, true), "the settings reach compute")
        assert(b:find("slim = pill_now ~= nil and pill_now.hidden == true", 1, true), "the chassis is told")
        -- a settings change reaches the bar as relayout(): the Pill's face and hiding are read again then
        assert(b:find("relayout = function() pill_update(); relayout() end", 1, true), "settings re-read the Pill")
        local g = io.open("shell/mooi.plm"); local plm = g:read("a"); g:close()
        assert(plm:find("event pill_hover ->", 1, true), "pointing at it reaches the logic")
        assert(plm:find("follow pb_lx = clamp((cursor.x - pill_x - pill_w / 2) / 180, -1, 1) * 9", 1, true), "his eyes follow the mouse anywhere (D198)")
        local u = io.open("shell/ui/pill.plm"); local ui = u:read("a"); u:close()
        assert(ui:find("emit pill_hover", 1, true), "the sliver can be pointed at")
    end)
    -- D170 fix: the Pill's zone was on popup_surface, where a hand's press never arrived (a scripted
    -- `pleamar --say press` did, so every check passed while the real Pill did nothing)
    test("the Pill is on the bar's surface, with the other modules, not on popup_surface", function()
        local f = io.open(MOOI_PLM or "shell/mooi.plm"); local plm = f:read("a"); f:close()
        local at = plm:find("\n    PillBody()", 1, true)
        local popup = plm:find("surface popup_surface {", 1, true)
        assert(at and popup and at < popup, "PillBody() is drawn at the top level, before popup_surface")
    end)
    test("a press on a hidden Pill comes back and acts in the same press", function()
        local f = io.open("shell/bar.luau"); local b = f:read("a"); f:close()
        local h = b:match('on%("pill_press", function%(%)(.-)\n    end%)')
        assert(h, "the handler")
        assert(not h:find('elseif fact.pill_hidden then note%("peek"'), "a hidden press does not stop at the peek")
        assert(h:find('if fact.pill_hidden then note%("peek", {}%) end'), "it peeks and goes on")
    end)
end

section("the Pill board (D170)")
do
    local P = require("lib/pill")
    local PP = require("lib/pillpads")
    local bl = require("lib/barlayout")
    test("pill.press: left opens the board from every face and activity, right keeps the old jumps", function()
        for _, face in ipairs({ "time", "bmo", "weather", "resources" }) do
            for _, main in ipairs({ "idle", "music", "osd", "notify", "record", "battery" }) do
                eq(P.press(main, face, "left").kind, "board", face .. "/" .. main .. " left")
            end
        end
        eq(P.press("idle", "nexus", "left").kind, "nexus", "the Nexus face is the Nexus button")
        eq(P.press("music", "nexus", "left").kind, "board", "an activity on the Nexus face opens the board")
        eq(P.press("idle", "time", "right").kind, "calendar")
        eq(P.press("idle", "nexus", "right").kind, "board", "right on the Nexus face: the board")
        eq(P.press("music", "time", "right").kind, "player")
        local o = P.press("osd", "time", "right", "bri"); eq(o.kind, "island"); eq(o.island, "display")
        eq(P.press("osd", "time", "right", "vol").island, "sound")
        eq(P.press("battery", "time", "right").island, "power")
        local n = P.press("notify", "time", "right"); eq(n.kind, "board"); eq(n.room, "signals")
        eq(P.press("record", "time", "right").kind, "record", "right on a recording still stops it")
    end)
    test("pill.press: the board opens on the activity's room", function()
        eq(P.press("idle", "time", "left").room, "now")
        eq(P.press("music", "time", "left").room, "now", "Now is Now Playing while music plays")
        eq(P.press("osd", "time", "left", "vol").room, "sound")
        eq(P.press("osd", "time", "left", "bri").room, "display")
        eq(P.press("battery", "time", "left").room, "power")
        eq(P.press("notify", "time", "left").room, "signals")
    end)
    test("pill.pads: known ids, no repeats, eight at most; nothing usable → the default", function()
        local d = P.pads(nil); eq(#d, 8); eq(d[1], "volume"); eq(d[8], "nexus")
        local v = P.pads({ "weather", "dragon", "weather", "clock" }); eq(#v, 2); eq(v[1], "weather"); eq(v[2], "clock")
        local nine = P.pads({ "workspaces", "window", "media", "resources", "bandwidth", "keyboard", "weather", "tray", "mic" })
        eq(#nine, 8)
        eq(#P.pads({}), 0, "an empty board is allowed")
        eq(#P.pads("garbage"), 8)
    end)
    test("pillpads: every bar module is a part, with a room or an act, an icon and a place", function()
        eq(#PP.ORDER, #bl.ORDER - 1, "every module but the Sigil (D207)")
        for i, id in ipairs(PP.ORDER) do
            local p = PP.get(id)
            assert(p, id .. " is a part")
            assert(p.room or p.act, id .. " has a room or an act")
            assert(type(p.icon) == "number", id .. " has an icon")
            eq(PP.index(id), i - 1, id .. " index")
        end
        eq(PP.get("dragon"), nil)
        local rooms = {}
        for _, r in ipairs(PP.ROOMS) do rooms[r] = true end
        for _, id in ipairs(PP.ORDER) do local p = PP.get(id); if p.room then assert(rooms[p.room], id .. "'s room exists") end end
        eq(PP.room_index("now"), 0); eq(PP.room_index("signals"), 8)
        eq(PP.get("volume").room, "sound"); eq(PP.get("clock").room, "calendar"); eq(PP.get("caffeine").switch, true)
        eq(PP.get("notes").room, "notes", "D201: notes is a room now, not a pad that closes the board")
        for _, id in ipairs(PP.DEFAULT) do assert(PP.get(id), id) end
    end)
    test("pill faces: the module faces, each with a width its detail names", function()
        eq(#P.FACES, 12, "D171 added the visualiser, D191 the glance"); eq(P.FACES[12], "glance"); eq(P.FACES[1], "time"); eq(P.FACES[4], "weather")
        local st = P.state()
        eq(P.compute(st, { face = "weather" }, 0).width, P.FACE_W.weather)
        eq(P.compute(st, { face = "weather", detail = "full" }, 0).width, P.FACE_W_FULL.weather)
        eq(P.compute(st, { face = "weather", detail = "icon" }, 0).width, 44)
    end)
    test("pill settings: face from the modules, and the pads", function()
        local d = config.defaults()
        eq(#d.pill.pads, 8); eq(d.pill.viz, nil, "D202: the board's visualiser went with Cue")
        local s, p = config.validate({ pill = { face = "weather", pads = { "clock", "weather" } } })
        eq(#p, 0); eq(s.pill.face, "weather"); eq(s.pill.pads[2], "weather")
        local _, p2 = config.validate({ pill = { pads = { "dragon" } } }); eq(#p2, 1, "an unknown pad is refused")
        local s3 = config.validate({ pill = { viz = "river" } }); eq(s3.pill.viz, nil, "the old key is dropped quietly")
        local setters = require("lib/setters")
        local seen = {}
        for _, q in ipairs(setters.SETTERS) do seen[q] = true end
        assert(seen["pill.pads"] and not seen["pill.viz"], "only the pads are settable")
        local g = io.open("tools/gen-settings.py"); local py = g:read("a"); g:close()
        assert(py:find('"pill.pads",', 1, true) and not py:find('"pill.viz"', 1, true), "gen-settings mirrors the codes")
    end)
end

section("the Pill board: BMO (D170)")
do
    local F = require("lib/pillface")
    test("pillface.react: a face for a while, then his own again", function()
        local st = F.new("happy")
        F.react(st, "surprised", 1000, 700)
        eq(F.view(st, 1500).face, "surprised")
        eq(F.view(st, 1800).face, "happy")
        F.react(st, "dragon", 2000, 700); eq(F.view(st, 2100).face, "happy", "an unknown face is ignored")
    end)
    test("pillface.say: a line, or nothing when BMO → Talk is off", function()
        local st = F.new("happy")
        F.say(st, "sound!", 0, "rare"); eq(F.view(st, 100).say, "sound!")
        local q = F.new("happy")
        F.say(q, "sound!", 0, "off"); eq(F.view(q, 100).say, "")
    end)
    test("pillface.poke: Talk off keeps his faces, not his lines (D169 M3)", function()
        local st = F.new("happy")
        F.poke(st, 0, 0.5, "off")
        local v = F.view(st, 100)
        eq(v.face, "giggle"); eq(v.say, "")
        local t = F.new("happy")
        F.poke(t, 0, 0.5, "chatty"); assert(F.view(t, 100).say ~= "", "talking, the first poke speaks")
    end)
    test("pillface: left alone he gets sleepy, then falls asleep; touched he wakes", function()
        local st = F.new("happy")
        F.touch(st, 0)
        F.tick(st, F.SLEEPY_MS - 1000, { hour = 12, talk = "off" }, 0.5, 1)
        assert(F.view(st, F.SLEEPY_MS - 1000).face ~= "asleep")
        F.tick(st, F.SLEEPY_MS + 1000, { hour = 12, talk = "off" }, 0.5, 1)
        eq(F.view(st, F.SLEEPY_MS + 1000).face, "sleepy")
        F.tick(st, F.ASLEEP_MS + 1000, { hour = 12, talk = "off" }, 0.5, 1)
        eq(F.view(st, F.ASLEEP_MS + 1000).face, "asleep")
        eq(F.touch(st, F.ASLEEP_MS + 2000), true, "he was asleep")
        F.tick(st, F.ASLEEP_MS + 3000, { hour = 12, talk = "off" }, 0.5, 1)
        assert(F.view(st, F.ASLEEP_MS + 3000).face ~= "asleep", "awake again")
        eq(F.touch(st, F.ASLEEP_MS + 4000), false, "awake: a touch is just a touch")
    end)
    test("pillface: never touched, he still gets sleepy (D202)", function()
        local st = F.new("happy", 0)
        F.tick(st, F.SLEEPY_MS - 1000, { hour = 12, talk = "off" }, 0.5, 1)
        assert(F.view(st, F.SLEEPY_MS - 1000).face ~= "asleep")
        F.tick(st, F.SLEEPY_MS + 1000, { hour = 12, talk = "off" }, 0.5, 1)
        eq(F.view(st, F.SLEEPY_MS + 1000).face, "sleepy", "alone from the first moment, not only after a touch")
        local s2 = F.new("happy", 0)
        F.tick(s2, F.ASLEEP_MS - 1000, { hour = 12, talk = "off" }, 0.5, 1)
        F.tick(s2, F.ASLEEP_MS + 1000, { hour = 12, talk = "off" }, 0.5, 1)
        eq(F.view(s2, F.ASLEEP_MS + 1000).face, "asleep")
    end)
end

section("the Pill board: the scene and its logic (D170)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("the board's events reach the logic", function()
        local plm = read("shell/mooi.plm")
        for _, ev in ipairs({ "pk_pad", "pk_hover", "pk_back", "pk_go", "pk_turn", "pk_chip", "pk_key", "pk_edit_cmd", "pk_part", "pk_face", "pk_sig_clear", "pill_rpress", "pill_rmoon" }) do
            assert(plm:find("event " .. ev .. " ->", 1, true), ev .. " is declared with ->")
        end
        local lua = read("shell/pillboard.luau")
        for _, ev in ipairs({ "pk_pad", "pk_hover", "pk_back", "pk_go", "pk_turn", "pk_chip", "pk_key", "pk_edit_cmd", "pk_part", "pk_face", "pk_sig_clear" }) do
            assert(lua:find('on("' .. ev .. '"', 1, true), ev .. " is heard")
        end
        local bar = read("shell/bar.luau")
        assert(bar:find('on("pill_rpress"', 1, true) and bar:find('on("pill_rmoon"', 1, true), "the bar hears the right presses")
    end)
    test("the board is an island: drawn on popup_surface, its life, dismissed by a press outside and Escape", function()
        local plm = read("shell/mooi.plm")
        assert(plm:find("| board | bmo | herdr = none", 1, true), "open can be board")
        assert(plm:find("shown while open == board { rv.board: 1", 1, true), "its reveal")
        local popup = plm:find("surface popup_surface {", 1, true)
        local at = plm:find("        PillBoard()", 1, true)
        assert(at and popup and at > popup, "drawn with the panels")
        assert(plm:find("open == power or open == music or open == board { open = none }", 1, true), "a press outside closes it")
        assert(plm:find("on key Escape while open == board { emit pk_key(3) }", 1, true), "Escape backs out")
        local ui = read("shell/ui/pillboard.plm")
        assert(ui:find("IslandFrame(rv.board", 1, true), "the island kit draws it")
        assert(ui:find("want: open == board", 1, true), "the frame pours it from the Pill")
    end)
    test("the islands' readers run for the board's rooms", function()
        local isl = read("shell/islands.luau")
        assert(isl:find('on("fact:pk_room", told)', 1, true), "a room change is heard")
        assert(isl:find('[1] = "calendar", [5] = "power", [6] = "stats", [7] = "weather"', 1, true), "the rooms that need readers")
        local parts = require("lib/pillpads")
        eq(parts.room_index("calendar"), 1); eq(parts.room_index("power"), 5); eq(parts.room_index("resources"), 6); eq(parts.room_index("weather"), 7)
    end)
    test("the Pill's hover is heard once per crossing, and the right presses are wired", function()
        local ui = read("shell/ui/pill.plm")
        assert(not ui:find("on change pillz.hover while", 1, true), "not on every step of the hover's easing")
        assert(ui:find("on change pz_in while pz_in { emit pill_hover(1) }", 1, true))
        assert(ui:find("on press right pillz { emit pill_rpress }", 1, true))
        assert(ui:find("on press right pmoon0 { emit pill_rmoon(0) }", 1, true))
    end)
    test("Loom shares its newest signals and can clear them, without a second watch", function()
        local sig = read("shell/signals.luau")
        assert(sig:find("recent = function(n)", 1, true) and sig:find("clear = function()", 1, true))
        local board = read("shell/pillboard.luau")
        assert(not board:find("sys.watch", 1, true), "the board watches nothing itself (no notification server, D169)")
    end)
end

section("the Pill board: music (D170)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("the record turns and the song's position comes while the board plays", function()
        local plm = read("shell/mooi.plm")
        assert(plm:find("follow mu_spd = if(mu_playing and (open == music or (open == board and pk_room < 0.5 and pk_music)), 120, 0)", 1, true), "the record turns")
        local ui = read("shell/ui/pillboard.plm")
        assert(ui:find("on change pk_mus_on { emit music_isl(if(pk_mus_on, 3, 2)) }", 1, true), "position updates")
        assert(ui:find("pick(i, lv0, lv2, lv4", 1, true), "each trace carries a pair of bands")
    end)
    test("the Pill never tucks away while its board is open", function()
        local bar = read("shell/bar.luau")
        assert(bar:find('board = pill_board ~= nil and pill_board.open() == "board"', 1, true), "the bar says the board is open")
        local P = require("lib/pill")
        local st = P.state()
        local r = P.compute(st, { face = "time", hide = "tuck", board = true }, 0)
        eq(r.hidden, false); eq(r.width, P.FACE_W.time)
        eq(P.compute(st, { face = "time", hide = "tuck" }, 0).hidden, true, "closed, it tucks again")
    end)
end

section("the Pill board: its logic, run (D170)")
do
    -- shell/pillboard.luau against stand-ins for Pleamar's globals: events are called by hand
    local function board(settings)
        local handlers, ran, timers = {}, {}, {}
        local env = setmetatable({
            on = function(name, fn) handlers[name] = fn end,
            every = function() end,
            after = function(ms, fn) timers[#timers + 1] = { ms = ms, fn = fn } end,
            run = function(cmd, args) ran[#ran + 1] = table.concat(args or {}, " ") end,
            fact = { open = "none", pk_room = 0, pill_on = true, mu_playing = false, mu_has = false },
            model = {}, text = {},
        }, { __index = _G })
        local saved = 0
        local said, reacted, poked = {}, {}, 0
        local P = { now = function() return { main = "idle", moons = { "music" } } end, osd = function() return "vol" end,
                    bmo = function() return true end, touch = function() end,
                    react = function(f) reacted[#reacted + 1] = f end, say = function(l) said[#said + 1] = l end,
                    poke = function() poked = poked + 1 end }
        local chunk = assert(loadfile("shell/pillboard.luau", "t", env))
        local api = chunk()({ settings = function() return settings end, save = function() saved = saved + 1 end, pill = P,
                              loom = { recent = function() return { { app = "a", title = "t", ago = "now" } }, 1 end, clear = function() end } })
        return { api = api, h = handlers, fact = env.fact, model = env.model, ran = ran, saves = function() return saved end,
                 said = said, reacted = reacted, poked = function() return poked end,
                 -- run the timers set so far (Pleamar's `after`), as if their time had passed
                 tick = function() local t = timers; timers = {}; for _, x in ipairs(t) do x.fn() end; return t end }
    end
    local function S() return { pill = { face = "time", pads = { "volume", "clock", "caffeine", "notes" } } } end
    test("D189: closing keeps the editor drawn until the body has folded; a reopen is not reset", function()
        local b = board(S())
        b.api.press("left", "idle")
        b.h.pk_edit_cmd(0); eq(b.fact.pk_edit, true)
        b.tick()
        b.h["fact:open"]("none")                 -- a press outside, from the scene
        eq(b.fact.pk_edit, true)                 -- still drawn while it folds
        local t = b.tick()
        eq(#t > 0, true); eq(b.fact.pk_edit, false)
        b.api.press("left", "idle"); b.h.pk_edit_cmd(0)
        b.h["fact:open"]("none")
        b.api.press("left", "idle")              -- opened again before the fold's reset ran
        b.h.pk_edit_cmd(0)                       -- and edited
        b.tick()                                 -- the stale reset fires: it must not undo that
        eq(b.fact.open, "board"); eq(b.fact.pk_edit, true); eq(b.fact.pk_peek, false)
    end)
    test("D191: the reveal — an item opens the board on its room; its hover keeps the peek", function()
        local b = board(S())
        b.api.hover(true); b.tick()
        eq(b.fact.open, "board"); eq(b.fact.pk_peek, true)
        local W, H = require("lib/pill").PEEK_W, require("lib/pill").PEEK_H
        eq(b.fact.pk_bw, W); eq(b.fact.pk_bh, H)
        -- D198/D202: the pointer is measured from the global cursor, so no zone's enter or leave can fold it
        b.tick()
        eq(b.fact.open, "board", "still on the card: not folded")
        b.h.pk_rev(7)
        eq(b.fact.pk_peek, false); eq(b.fact.pk_room, 7); eq(b.fact.pk_bw, 640)
        b.tick()
        eq(b.fact.open, "board", "the whole board does not fold on leave")
    end)
    test("D191: the reveal folds when the pointer leaves the card and every item", function()
        local b = board(S())
        b.api.hover(true); b.tick()
        b.api.hover(false)
        b.tick()
        eq(b.fact.open, "none")
    end)
    test("a left press unfolds the board on Now; BMO says hi", function()
        local b = board(S())
        b.api.press("left", "idle")
        eq(b.fact.open, "board"); eq(b.fact.pk_room, 0); eq(b.fact.pk_n, 4)
        eq(b.said[1], "hi!")
        eq(#b.model.pk_week, 7)
    end)
    test("a press while it is open: BMO is poked (he is the face); a right press is the calendar", function()
        local b = board(S())
        b.api.press("left", "idle"); b.api.press("left", "idle")
        eq(b.poked(), 1); eq(b.fact.open, "board")
        local c = board(S()); c.api.press("right", "idle"); eq(c.fact.open, "calendar")
    end)
    test("pads: a room toggles, a switch acts in place, one that opens elsewhere closes the board", function()
        local b = board(S())
        b.api.press("left", "idle")
        b.h.pk_pad(0); eq(b.fact.pk_room, 2, "volume → Sound"); eq(b.fact.pk_on, 0)
        b.h.pk_pad(0); eq(b.fact.pk_room, 0, "again → Now")
        b.h.pk_pad(2); eq(b.fact.open, "board"); assert(b.ran[#b.ran]:find("emit caffeine", 1, true), "caffeine's own event")
        b.h.pk_pad(3); eq(b.fact.pk_room, require("lib/pillpads").room_index("notes"), "D201: notes is a room now"); eq(b.fact.open, "board")
    end)
    test("edit: a part goes on the chosen pad or at the end; × takes one off; ◂ ▸ move it; each saved", function()
        local st = S()
        local b = board(st)
        b.api.press("left", "idle")
        b.h.pk_edit_cmd(0); eq(b.fact.pk_edit, true)
        b.h.pk_part(6); eq(st.pill.pads[5], "weather", "added at the end")
        b.h.pk_pad(1); eq(b.fact.pk_sel, 1, "a press in edit chooses the pad")
        b.h.pk_part(3); eq(st.pill.pads[2], "resources", "put on the chosen pad")
        b.h.pk_part(3); eq(#st.pill.pads, 5, "a part already there is not added twice")
        b.h.pk_edit_cmd(31); eq(st.pill.pads[3], "resources"); eq(st.pill.pads[2], "caffeine", "moved right")
        b.h.pk_edit_cmd(10); eq(st.pill.pads[1], "caffeine", "the first taken off")
        assert(b.saves() >= 4, "saved each time")
        b.h.pk_key(3); eq(b.fact.pk_edit, false, "Escape leaves edit first")
    end)
    test("the face is chosen on the board", function()
        local st = S()
        local b = board(st)
        b.h.pk_face(3); eq(st.pill.face, "weather")
    end)
    test("Escape backs out: a room, then the board; a docked moon shows its room", function()
        local b = board(S())
        b.api.press("left", "idle")
        b.h.pk_go(5); eq(b.fact.pk_room, 5)
        b.h.pk_key(3); eq(b.fact.pk_room, 0)
        b.h.pk_chip(0); eq(b.fact.pk_room, 0); eq(b.fact.pk_music, true, "the music moon: Now Playing")
        b.h.pk_key(3); eq(b.fact.open, "none")
    end)
    test("the board tells the others when it opens or closes (the scene does not hear the logic's own write)", function()
        local handlers, told = {}, {}
        local env = setmetatable({ on = function(n, fn) handlers[n] = fn end, every = function() end, after = function() end, run = function() end,
            fact = { open = "none", pk_room = 0, pill_on = true }, model = {}, text = {} }, { __index = _G })
        local P = { now = function() return { main = "idle", moons = {} } end, osd = function() return "vol" end, bmo = function() return false end,
                    touch = function() end, react = function() end, say = function() end, poke = function() end }
        local api = assert(loadfile("shell/pillboard.luau", "t", env))()({ settings = function() return { pill = {} } end, save = function() end,
            pill = P, opened = function(v) told[#told + 1] = v; env.fact.open = v end })
        api.press("left", "idle"); eq(told[1], "board")
        api.press("left", "idle"); eq(told[2], "none")
    end)
    test("closed by the scene (a press outside, Escape), the next press opens it again", function()
        local b = board(S())
        b.api.press("left", "idle"); eq(b.fact.open, "board")
        b.h["fact:open"]("none")             -- the scene closed it; the logic's own fact still says board
        b.api.press("left", "idle")
        eq(b.poked(), 0, "not a poke: it was closed"); eq(b.api.open(), "board")
    end)
    test("the wheel over the board turns to the next room, and round", function()
        local b = board(S())
        b.api.press("left", "idle")
        b.h.pk_scroll(-1); eq(b.fact.pk_room, 1, "down: the next")
        b.h.pk_scroll(1); b.h.pk_scroll(1); eq(b.fact.pk_room, #require("lib/pillpads").ROOMS - 1, "up from Now: round to the last room")
    end)
    test("D203: the room rail — a tick per room, a jump, ↑↓ and the wheel, the light from its side", function()
        local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
        local b = board(S())
        local PP = require("lib/pillpads")
        b.api.press("left", "idle")
        eq(b.fact.pk_rn, #PP.ROOMS, "a tick for every room")
        b.h.pk_go(3); eq(b.fact.pk_room, 3, "a tick jumps straight there")
        eq(b.fact.pk_turn_dir, 1); eq(b.fact.pk_turn_on, true, "the light runs forward")
        b.h.pk_turn(-1); eq(b.fact.pk_room, 2); eq(b.fact.pk_turn_dir, -1, "↑ turns back, and says so")
        b.h.pk_go(0); b.h.pk_turn(-1); eq(b.fact.pk_room, #PP.ROOMS - 1, "back from Now: the last room")
        b.h.pk_turn(1); eq(b.fact.pk_room, 0, "and on round to Now")
        b.h.pk_scroll(1); eq(b.fact.pk_room, #PP.ROOMS - 1, "the wheel still turns one at a time")
        local plm = read("shell/mooi.plm")
        assert(plm:find("on key Up while open == board { emit pk_turn(-1) }", 1, true), "↑ turns back")
        assert(plm:find("on key Down while open == board { emit pk_turn(1) }", 1, true), "↓ turns on")
        assert(plm:find("follow pk_turn_f = if(pk_turn_on, 1, 0)", 1, true), "the light is a spring")
        local ui = read("shell/ui/pillboard.plm")
        assert(ui:find("component PkRailTick", 1, true) and ui:find("on press rt { emit pk_go(i) }", 1, true), "a tick jumps")
        assert(ui:find("repeat i in 0..17 { PkRailTick", 1, true), "the rail is drawn once per room")
        assert(ui:find("622 - 604 * pk_turn_f", 1, true), "and the light comes from the side it went")
    end)
    test("the keyboard walks the pads and presses one", function()
        local b = board(S())
        b.api.press("left", "idle")
        b.h.pk_key(1); eq(b.fact.pk_kb, 0)
        b.h.pk_key(0); eq(b.fact.pk_kb, 3, "left from the first wraps")
        b.h.pk_key(1); b.h.pk_key(1); eq(b.fact.pk_kb, 1)
        b.h.pk_key(2); eq(b.fact.pk_room, 1, "clock → the month")
    end)
end

section("the Pill board: Settings and faces (D170)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("Settings: one button edits the face, the wheel and the pads on the Pill (D188)", function()
        local plm = read("shell/mooi-settings.plm")
        assert(plm:find('"Behaviour"', 1, true) and plm:find('"What it shows"', 1, true), "the cards")
        assert(plm:find("pill_board_edit", 1, true), "Edit on the Pill")
        assert(not plm:find('"Halo", sv_pill_viz == 0', 1, true), "the board's music is chosen in the editor, not twice")
        local lua = read("shell/mooi-settings.luau")
        assert(lua:find('emit pill_edit_open', 1, true), "it opens the board in edit")
        assert(read("shell/pillboard.luau"):find('on("pill_edit_open"', 1, true))
    end)
    test("a module's face: its icon and reading in the closed Pill, a width of its own", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("pill_face > 2.5", 1, true) and ui:find("PkIcon(fk", 1, true))
        local P = require("lib/pill")
        for _, f in ipairs(P.FACES) do assert(P.FACE_W[f], f .. " has a width") end
        eq(P.compute(P.state(), { face = "media" }, 0).width, 220)
    end)
end

section("the Pill board: BMO in the Pill (D170)")
do
    local F = require("lib/pillface")
    local chassis = require("lib/chassis")
    test("pillface.view: music playing, he sings — unless something just made him react", function()
        local st = F.new("happy")
        eq(F.view(st, 1000, true).face, "singing")
        F.react(st, "surprised", 1000, 700)
        eq(F.view(st, 1200, true).face, "surprised")
        eq(F.view(st, 1800, true).face, "singing")
        eq(F.view(st, 1800, false).face, "happy")
    end)
    test("chassis: the Pill is always the bar's module height (D202)", function()
        local L = { mode = "pill", band = false, top = 8, mod_h = 24, radius = 7, screen_w = 1920, band_w = 2, frame_r = 14, reach = 16 }
        local off = chassis.pieces({ islands = {}, pill = { x = 860, w = 72 }, moons = {} }, L)
        eq(off[1].h, 24, "floating: the module's height"); eq(off[1].y, 8)
        L.band = true
        local on = chassis.pieces({ islands = {}, pill = { x = 860, w = 72 }, moons = {} }, L)
        eq(on[1].y + on[1].h, L.top + L.mod_h, "hanging from the band: its foot at the module's")
        local tall = chassis.pieces({ islands = {}, pill = { x = 860, w = 72, h = 40 }, moons = {} }, L)
        eq(tall[1].y + tall[1].h, L.top + L.mod_h, "a taller h in an old file is ignored")
        local g = io.open("shell/bar.luau"); local b = g:read("a"); g:close()
        assert(not b:find("pill_tall", 1, true), "no taller Pill any more")
        assert(b:find("fact.pb_tg = f.tg", 1, true) and b:find("fact.pb_sing", 1, true) and b:find("fact.pb_asleep", 1, true))
    end)
    test("BMO reacts in the Pill: pointed at, a signal", function()
        local g = io.open("shell/bar.luau"); local b = g:read("a"); g:close()
        assert(b:find('pill_api.react("curious"', 1, true), "pointed at: curious")
        assert(b:find('pill_api.react("surprised"', 1, true) and b:find('"a letter!"', 1, true), "a signal: surprised, then a letter")
    end)
end

section("the Pill board: the review's fixes (D170)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("review I1: the player quits while Now Playing shows: back to the idle Now", function()
        local handlers = {}
        local env = setmetatable({ on = function(n, fn) handlers[n] = fn end, every = function() end, after = function() end, run = function() end,
            fact = { open = "none", pk_room = 0, pill_on = true, mu_playing = true, mu_has = true }, model = {}, text = {} }, { __index = _G })
        local P = { now = function() return { main = "music", moons = {} } end, osd = function() return "vol" end, bmo = function() return false end,
                    touch = function() end, react = function() end, say = function() end, poke = function() end }
        local api = assert(loadfile("shell/pillboard.luau", "t", env))()({ settings = function() return { pill = {} } end, save = function() end, pill = P })
        api.press("left", "music")
        eq(env.fact.pk_music, true)
        assert(handlers["fact:mu_has"], "the board hears the player going")
        env.fact.mu_has = false; handlers["fact:mu_has"](false)
        eq(env.fact.pk_music, false)
    end)
    test("review I2: in Pill mode the readers run for the pads, the face and Now's weather", function()
        local P = require("lib/pill")
        local n = P.needs({ pads = { "resources", "volume" }, face = "time" })
        eq(n.resources, true); eq(n.weather, true, "Now shows the weather"); eq(n.keyboard, nil)
        eq(P.needs({ pads = {}, face = "resources" }).resources, true, "the CPU face")
        eq(P.needs({ pads = { "network" } }).bandwidth, true, "Connections shows the throughput")
        eq(P.needs({ pads = { "keyboard" } }).keyboard, true)
        local bar = read("shell/bar.luau")
        assert(bar:find("local need = pill_on_bar and pillmod.needs(s.pill) or {}", 1, true), "readers() asks")
        assert(bar:find("if placed.resources or need.resources or sig.n > 0 then", 1, true))
    end)
    test("review I3: the Signals room keeps signals.private", function()
        local sig = read("shell/signals.luau")
        assert(sig:find("local f = nexusfeed.feed(list, os.time(), private())", 1, true))
    end)
    test("review I4: the Tray pad does not press whichever app is first in the tray", function()
        local PP = require("lib/pillpads")
        assert(PP.get("tray").act ~= "tray_cmd")
    end)
    test("review I5: the board and the music island keep the song's position coming each on its own", function()
        local ui = read("shell/ui/pillboard.plm")
        assert(ui:find("emit music_isl(if(pk_mus_on, 3, 2))", 1, true), "the board says 3 or 2")
        local bar = read("shell/bar.luau")
        assert(bar:find("mu.open = mu.isl or mu.board", 1, true), "either keeps it open")
    end)
end

section("the Pill board: the frame lets go (D170 fix)")
do
    test("the frame's island follows open as the scene reports it, so a board closed in the scene leaves no plate", function()
        local f = io.open("shell/mooi.luau"); local src = f:read("a"); f:close()
        local body = src:match("local function pl_sync%(%)(.-)\nend")
        assert(body, "pl_sync")
        assert(not body:find("fact.open", 1, true), "pl_sync does not read fact.open back (it gives the logic's last write)")
        assert(src:find('on("fact:open", opens.pl_heard)', 1, true) and src:find("opens.listen(opens.pl_heard)", 1, true), "it hears the scene and the logic")
        local isl = io.open("shell/islands.luau"); local i = isl:read("a"); isl:close()
        assert(i:find("ctx.listen_open(heard)", 1, true), "the islands' readers hear the logic's opens too")
    end)
end

section("the Pill, round two: views, shapes, detail (D171)")
do
    local P = require("lib/pill")
    local chassis = require("lib/chassis")
    test("settings: the shape, the views, the detail, the rest", function()
        local d = config.defaults()
        eq(d.pill.shape, "attached"); eq(d.pill.detail, "brief"); eq(d.pill.rest, 10)
        assert(#d.pill.views >= 6, "a default list of views")
        local s, p = config.validate({ pill = { shape = "dot", views = { "nexus", "workspaces", "notifications" }, detail = "full", rest = 0 } })
        eq(#p, 0); eq(s.pill.shape, "dot"); eq(s.pill.views[2], "workspaces"); eq(s.pill.detail, "full"); eq(s.pill.rest, 0)
        local _, p2 = config.validate({ pill = { views = { "dragon" } } }); eq(#p2, 1)
        local setters = require("lib/setters")
        local seen = {}
        for _, q in ipairs(setters.SETTERS) do seen[q] = true end
        assert(seen["pill.shape"] and seen["pill.views"] and seen["pill.detail"] and seen["pill.rest"])
    end)
    test("pill.next_view: round the owner's list, either way; unknown or empty → the default list", function()
        local v = { "nexus", "workspaces", "notifications" }
        eq(P.next_view(v, "nexus", 1), "workspaces")
        eq(P.next_view(v, "notifications", 1), "nexus")
        eq(P.next_view(v, "nexus", -1), "notifications")
        eq(P.next_view(v, "weather", 1), "nexus", "not in the list: its first")
        eq(P.next_view({}, "time", 1), P.VIEWS_DEFAULT[2], "empty: the default list")
        eq(P.next_view({ "dragon", "bmo" }, "bmo", 1), "bmo", "unknown ids are skipped")
    end)
    test("widths by detail: icon is just the icon, full makes room for more", function()
        local st = P.state()
        eq(P.compute(st, { face = "weather", detail = "icon" }, 0).width, 44)
        eq(P.compute(st, { face = "time", detail = "icon" }, 0).width, 120, "time keeps its own form")
        assert(P.compute(st, { face = "weather", detail = "full" }, 0).width > P.compute(st, { face = "weather", detail = "brief" }, 0).width)
    end)
    test("the dot: idle, the Pill is a 14 px dot (hiding implied); pointed at, it comes back", function()
        local st = P.state()
        local r = P.compute(st, { face = "time", shape = "dot" }, 0)
        eq(r.hidden, true); eq(r.width, P.DOT)
        P.note(st, "peek", {}, 100)
        eq(P.compute(st, { face = "time", shape = "dot" }, 200).hidden, false)
    end)
    test("chassis: floating hovers under the band, never joined; the dot is a small circle", function()
        local L = { mode = "pill", band = true, top = 8, mod_h = 24, radius = 7, screen_w = 1920, band_w = 2, frame_r = 14, reach = 16 }
        local f = chassis.pieces({ islands = {}, pill = { x = 860, w = 120, shape = "floating" }, moons = {} }, L)[1]
        eq(f.j, false); eq(f.y, 8); eq(f.h, 24)
        local d = chassis.pieces({ islands = {}, pill = { x = 953, w = 14, slim = true, shape = "dot" }, moons = {} }, L)[1]
        eq(d.w, 14); eq(d.h, 14); eq(d.r, 7); eq(d.j, false); eq(d.y, 8 + 5)
        local a = chassis.pieces({ islands = {}, pill = { x = 860, w = 120, shape = "attached" }, moons = {} }, L)[1]
        eq(a.j, true, "attached: hangs from the band as before")
    end)
end

section("the Pill, round two: the bar turns its views (D171)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("the wheel over an idle Pill turns its view; over music or a volume change it stays the volume", function()
        local bar = read("shell/bar.luau")
        local h = bar:match('on%("pill_scroll", function%(v%)(.-)\n    end%)')
        assert(h, "the scroll handler")
        assert(h:find('pill_view = pillmod.next_view(', 1, true), "idle: the next view")
        assert(not h:find('"workspace", d > 0', 1, true), "idle no longer switches workspace")
        assert(h:find('cur_vol + step', 1, true), "music and volume keep the volume")
    end)
    test("a turned view rests back to the default after pill.rest, not while pointed at or open", function()
        local bar = read("shell/bar.luau")
        assert(bar:find("if pill_view and pill_idle and not pill_hovering and not open_board", 1, true), "the rest, while idle and away")
        assert(bar:find("pillmod.view_hold(pill_view, pill_view_at, rest, pill_ms) == nil then", 1, true), "pill.rest, by lib/pill's rule")
        assert(bar:find("face = pill_view or p.face", 1, true), "the face shown is the turned view")
        assert(bar:find("shape = p.shape", 1, true) and bar:find("detail = p.detail", 1, true))
    end)
    test("Super calls the Pill: it comes back; again within a moment, the board", function()
        local bar = read("shell/bar.luau")
        assert(bar:find('on("pill_call"', 1, true))
        local plm = read("shell/mooi.plm")
        assert(plm:find("event pill_call ->", 1, true))
        local sh = read("bin/mooi")
        assert(sh:find('pill) exec "$pleamar" --say "$name" "emit pill_call"', 1, true), "`mooi pill`")
        local hl = read("setup/home/.config/hypr/config/custom/mooi.lua")
        -- D208: Super's release goes through Surface (`mooi reveal up`), which keeps a quick tap as `pill_call`
        assert(hl:find('hl.bind, "SUPER + SUPER_L", hl.dsp.exec_cmd(mooi .. " reveal up"), { release = true }', 1, true), "Super alone, on release")
        assert(sh:find('up) "$pleamar" --say mooi-surface "emit rv_up" >/dev/null 2>&1 || exec "$pleamar" --say "$name" "emit pill_call"', 1, true), "without Surface, still the Pill")
    end)
end

section("the Pill, round two: faces (D171)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("BMO is the capsule's own glass, not a Pill of his own (D187, D196)", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("BmoScreen(px, pw, cy, pill_t1, pb_talk)", 1, true), "his screen is the capsule's inside")
        assert(ui:find("box { from: px + 2.5, gy; size: max(4, pw - 5), gh; corner: gh / 2; color: glass }", 1, true),
               "the glass inside the capsule's own outline, never larger")
        assert(not ui:find("color: #69c7bb", 1, true), "no teal body round a taller Pill")
        local bar = read("shell/bar.luau")
        assert(bar:find("fact.pill_h = tonumber(b.height) or 24", 1, true), "one height, whatever he shows")
    end)
    test("D196: BMO lives — a hop, a typed line, notes, a mark, a screen that sleeps; he stays as the mark", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("let rise = if(pill_still, 0, sin(min(h, 1) * 180) * 2.6)", 1, true), "the hop, still with reduced motion")
        assert(ui:find("let tf = clamp(pb_type - (pb_say_n - 1), 0, 1)", 1, true), "each new line typed out")
        assert(ui:find("show: pb_sing and not pill_still", 1, true), "notes while he sings")
        assert(ui:find("follow pb_pow = if(pb_asleep, 0.32, 1)", 1, true) == nil, "(declared in mooi.plm)")
        assert(read("shell/mooi.plm"):find("follow pb_pow = if(pb_asleep, 0.32, 1)", 1, true), "the glass dims asleep")
        assert(ui:find("let bmo = pill_face > 0.5 and pill_face < 1.5", 1, true) and ui:find("BmoMark(x + 6, cy)", 1, true),
               "with BMO as the face he is the mark for music, a level, a notice")
        local bar = read("shell/bar.luau")
        assert(bar:find('if kind == "osd" then bmo_react("focused", 700) end', 1, true), "a turn of the volume")
        assert(bar:find('bmo_react("curious", 500)', 1, true), "a workspace change")
        assert(bar:find('if changed and now then bmo_react("excited", 900) end', 1, true), "a song starting")
        assert(bar:find("fact.pb_mark = (r.main == \"notify\" and 3)", 1, true), "the mark over his head")
    end)
    test("faces at three details; workspaces as dots, alerts with the newest, the visualiser", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("if(detail < 0.5, px + pw / 2, px + 20)", 1, true), "icon: just the glyph, centred (D205: ModuleFace)")
        assert(ui:find("show: face == 7 and wx < px + pw - 10", 1, true), "workspaces: a dot each, inside the Pill")
        assert(ui:find("text pill_alert {", 1, true), "alerts: the newest at full")
        assert(ui:find("show: face == 10", 1, true), "the visualiser")
        assert(ui:find("text clock.date", 1, true), "time at full: the date")
    end)
    test("the Nexus face shows only as the Nexus face; a new face drops the turned view", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("pill_face > 1.5 and pill_face < 2.5\n                NexusFace", 1, true))
        local bar = read("shell/bar.luau")
        assert(bar:find("if p.face ~= pill_face_was then pill_face_was = p.face; pill_view = nil end", 1, true))
    end)
    test("the dot breathes, and has room round it to land on", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("let dotted = pill_hidden and pill_shape > 1.5", 1, true))
        assert(ui:find("if(dotted, px - 10, px)", 1, true))
        local plm = read("shell/mooi.plm")
        assert(plm:find("spin pill_pulse by if(pill_hidden and pill_shape > 1.5 and pill_shape < 2.5 and not pill_still, 140, 0)", 1, true), "only while it is a dot (not the morph, D204), and never in reduced motion")
    end)
end

section("the desk's visual editor, in Settings (D180)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("the desk is drawn as the choices make it; the rows under it are its only controls (D188)", function()
        local gen = read("tools/gen-settings.py")
        assert(gen:find('("deskstage",)', 1, true), "its row")
        assert(gen:find("SDeskStage({y + 6})", 1, true), "a picture, no codes of its own")
        local prev = read("shell/ui/pillpreview.plm")
        assert(prev:find("component SDeskStage(", 1, true) and prev:find("component SDeskCell(", 1, true))
        assert(not prev:find("emit set_value", 1, true), "no second set of controls in the picture")
        assert(prev:find("let fit = min(1, 2 / max(1, rows))", 1, true), "more than two rows are shown smaller, never spilling")
        assert(gen:find('[("Off", 2), ("Small", 0), ("Wide", 1)]', 1, true), "one Off · Small · Wide per tile")
        assert(prev:find("show: sv_pill_desk_form > 0.5", 1, true), "the vial drawn")
        local scene = read("shell/mooi-settings.plm")
        assert(scene:find("SDeskStage(", 1, true), "in the page")
    end)
end

section("the search, the stash and the internet panel (D178)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    local F = require("lib.pillfind")
    test("the search names the forms, and the best match comes first", function()
        eq(#F.search(""), 5, "an empty query: what the core has room for")
        eq(F.search("music")[1].key, "player")
        eq(F.search("loom")[1].key, "signals")
        eq(F.search("internet")[1].key, "wifi")
        eq(F.search("wifi")[1].key, "wifi")
        eq(F.search("stash")[1].key, "stash")
        eq(F.search("note")[1].key, "notes")
        eq(#F.search("zzzz"), 0)
        eq(#F.search("", 2), 2, "a cap")
        eq(F.get(0).key, "player")
        assert(F.search("wifi")[1].room, "Wi-Fi is a room of the board's")
    end)
    test("the board grows two rooms, draws them, and reads the radio", function()
        local PP = require("lib.pillpads")
        eq(PP.room_index("stash"), 14); eq(PP.room_index("find"), 15)
        local plm = read("shell/mooi.plm")
        assert(plm:find("text pk_q = \"\"", 1, true) and plm:find("model pk_finds max 5", 1, true), "the search")
        assert(plm:find("model pk_nets max 8", 1, true) and plm:find("event pk_find ->", 1, true), "the panel")
        local board = read("shell/pillboard.luau")
        assert(board:find('local pillfind = require("lib/pillfind")', 1, true))
        assert(board:find('on("text:pk_q"', 1, true), "typed in")
        assert(board:find('pcall(sys.ask, "network")', 1, true), "the networks, read")
        assert(board:find('on("pk_find"', 1, true), "a press opens it")
        local ui = read("shell/ui/pillboard.plm")
        assert(ui:find("input pk_q {", 1, true), "the field")
        assert(ui:find("for f in pk_finds {", 1, true) and ui:find("emit pk_find(f.k)", 1, true), "the rows")
        assert(ui:find("for r in stash {", 1, true) and ui:find("emit stash_open(r.id)", 1, true), "the stash")
        assert(ui:find("for w in pk_nets {", 1, true) and ui:find("emit sh_net(w.n)", 1, true), "the networks")
        assert(ui:find('"STASH", "FIND"', 1, true), "named in the header")
        local conf = read("shell/lib/config.luau")
        assert(conf:find('{ path = "pill.right"', 1, true), "the right button's choice (D179)")
        assert(read("shell/lib/setters.luau"):find('"pill.right"', 1, true) and read("tools/gen-settings.py"):find('"Right press"', 1, true), "its setter and page")
        assert(board:find('local r = pill_settings().right', 1, true), "the choice is read")
    end)
end

section("the desk's sizes and its look: the opened vial (D177)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("a wide tile takes its row, and a tile that no longer fits is dropped", function()
        local dg = require("lib.deskgrid")
        local wide = dg.place({ "clock", "playing" }, { clock = "wide" })
        eq(wide[1].w, 600); eq(wide[1].x, 0); eq(wide[1].y, 0)
        eq(wide[2].y, 84); eq(wide[2].w, 296, "the next tile starts a row")
        eq(dg.place({ "diagnostics" }, { diagnostics = "wide" })[1].x, 0, "wide leads the row")
        local two = dg.place({ "clock", "playing", "calendar", "diagnostics" }, { clock = "wide", playing = "wide" })
        eq(#two, 2, "two wide rows fill the core")
        eq(two[2].y, 84)
        eq(dg.place({ "clock", "playing" }, { clock = "wide", playing = "wide" })[2].w, 600, "both wide")
    end)
    test("the sizes are the owner's, the form is the vial, and a press goes somewhere", function()
        local conf = read("shell/lib/config.luau")
        for _, p in ipairs({ "pill.desk_clock_size", "pill.desk_playing_size", "pill.desk_diagnostics_size",
                             "pill.desk_calendar_size", "pill.desk_form", "pill.desk_tint", "pill.desk_glow" }) do
            assert(conf:find('{ path = "' .. p .. '"', 1, true), p)
        end
        local set = read("shell/lib/setters.luau")
        assert(set:find('"pill.desk_form", "pill.desk_tint", "pill.desk_glow"', 1, true), "three setters")
        local gen = read("tools/gen-settings.py")
        assert(gen:find('"pill.desk_clock_size", "sv_pill_desk_clock_size", [("Off", 2)', 1, true) and gen:find('["Tiles", "Opened vial"]', 1, true), "their rows")
        local board = read("shell/pillboard.luau")
        assert(board:find('sizes[id] = s["desk_" .. id .. "_size"]', 1, true), "a size each")
        assert(board:find('fact["pk_dk_w" .. i] = t and t.w or 0', 1, true), "published")
        assert(board:find('fact.pk_dk_form = s.desk_form == "vial" and 1 or 0', 1, true))
        assert(board:find('on("pk_dk_press"', 1, true), "a press inside one")
        assert(board:find('run("hyprctl", { "-j", "monitors" }, function(out)', 1, true), "the monitor's real size")
        assert(board:find('deskprev.cards(wv_rows, wv_at, wv_sw, wv_sh)', 1, true), "used, not 1920")
        local ui = read("shell/ui/pillboard.plm")
        assert(ui:find("component DeskTile(k, x, y, w, h, acc, ink, dim)", 1, true), "sized per tile")
        assert(ui:find("on press dkz { emit pk_dk_press(k) }", 1, true), "the press")
        assert(ui:find("glow: dglow, 0.5, tone", 1, true) and ui:find("pick(pk_dk_tint, acc, acc2, ink)", 1, true), "tint and glow")
        assert(ui:find("show: pk_dk_form > 0.5", 1, true), "the vial's two halves")
        local plm = read("shell/mooi.plm")
        assert(plm:find("fact pk_dk_w0 = 0", 1, true) and plm:find("fact pk_dk_form = 0", 1, true), "declared")
        assert(plm:find("event pk_dk_press ->", 1, true))
    end)
end

section("the desk as the workspace viewer (D176)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    local D = require("lib.deskprev")
    local function win(ws, x, y, w, h, cls, title, focus)
        return { workspace = { id = ws }, at = { x, y }, size = { w, h }, class = cls or "kitty",
                 title = title or "", focusHistoryID = focus or 1 }
    end
    test("the windows are grouped by their workspace, in order, and a card holds eight", function()
        local rows = D.group({ win(2, 0, 0, 800, 600), win(1, 1920, 0, 640, 480, "firefox", "mooi", 0), win(2, 40, 40, 400, 300) }, 1)
        eq(#rows, 2)
        eq(rows[1].id, 1); eq(rows[1].n, 1); eq(rows[1].active, true)
        eq(rows[2].id, 2); eq(rows[2].n, 2); eq(rows[2].active, false)
        eq(rows[1].wins[1].class, "firefox"); eq(rows[1].wins[1].focused, true)
        eq(D.group({ win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10),
                     win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10),
                     win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10) })[1].n, 10, "counted")
        eq(#D.group({ win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10),
                      win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10),
                      win(1, 0, 0, 10, 10), win(1, 0, 0, 10, 10) })[1].wins, D.WIN_MAX, "drawn")
        eq(#D.group({}), 0)
    end)
    test("a window sits where it really is in its miniature, and three cards show at once", function()
        local rows = D.group({ win(1, 960, 540, 960, 540), win(2, 0, 0, 1920, 1080), win(3, 100, 200, 800, 600) })
        local cards = D.cards(rows, 0, 1920, 1080)
        eq(#cards, 3, "three workspaces")
        eq(cards[1].wins[1].nx, 0.5); eq(cards[1].wins[1].ny, 0.5)
        eq(cards[1].wins[1].nw, 0.5); eq(cards[1].wins[1].nh, 0.5)
        eq(cards[1].slot, 0); eq(cards[2].slot, 1); eq(cards[2].wins[1].nw, 1)
        local many = { { id = 1, n = 0, wins = {} }, { id = 2, n = 0, wins = {} }, { id = 3, n = 0, wins = {} }, { id = 4, n = 0, wins = {} } }
        eq(#D.cards(many, 0, 1920, 1080), 3, "no more than three")
        eq(D.cards(many, 3, 1920, 1080)[1].id, 2, "the last is never past the end")
        eq(D.cards({}, 2, 1920, 1080)[1], nil)
    end)
    test("the thumbnails are matched by class and title", function()
        local pics = D.picture({ { class = "firefox", title = "mooi" }, { class = "kitty", title = "shell" } },
                               { { app = "firefox", title = "mooi", picture = "/tmp/a.png" },
                                 { app = "kitty", title = "other", picture = "/tmp/b.png" } })
        eq(pics[1], "/tmp/a.png")
        eq(pics[2], "")
        eq(D.picture({}, nil)[1], nil)
    end)
    test("the board draws it with the thumbnails service, and the settings own it", function()
        local conf = read("shell/lib/config.luau")
        assert(conf:find('{ path = "pill.desk_workspaces"', 1, true))
        local set = read("shell/lib/setters.luau")
        assert(set:find('"pill.desk_workspaces"', 1, true), "a setter, appended")
        local gen = read("tools/gen-settings.py")
        assert(gen:find('"Live workspaces instead"', 1, true), "its page")
        local board = read("shell/pillboard.luau")
        assert(board:find('local deskprev = require("lib/deskprev")', 1, true))
        assert(board:find('pcall(sys.ask, "thumbnails")', 1, true), "the pictures, read not watched (D169)")
        assert(board:find('run("hyprctl", { "-j", "clients" }, function(out)', 1, true), "the workspaces")
        assert(board:find('fact.pk_wv = s.desk_workspaces == true', 1, true), "published")
        assert(board:find('on("pk_wv_scroll"', 1, true) and board:find('on("pk_wv_go"', 1, true), "the wheel and the press")
        local ui = read("shell/ui/pillboard.plm")
        assert(ui:find("component WvCard(", 1, true), "drawn")
        assert(ui:find("show: pk_room < 0.5 and not pk_music and pk_wv", 1, true), "only Now, only when chosen")
        assert(ui:find("and pk_dk_n > 0.5 and not pk_wv", 1, true), "the tiles wait while the viewer shows")
        local plm = read("shell/mooi.plm")
        assert(plm:find("model pk_prev max 3", 1, true) and plm:find("model pk_wbox max 24", 1, true), "declared")
        assert(plm:find("event pk_wv_go ->", 1, true) and plm:find("event pk_wv_hover ->", 1, true), "and its events")
        assert(plm:find("model pk_prev max 3 { id: number; slot: number;", 1, true), "no `index` (the language's)")
    end)
end

section("where you left it, and the desk (D175)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("a turned view is kept while it is young, and forgotten after the rest", function()
        local P = require("lib/pill")
        eq(P.view_hold(nil, 0, 10, 5000), nil, "no view")
        eq(P.view_hold("media", 0, 10, 9999), "media", "come back inside the rest: where you left it")
        eq(P.view_hold("media", 0, 10, 10000), nil, "the rest is up: the default face")
        eq(P.view_hold("media", 0, 0, 999999), "media", "rest 0 keeps it")
        local bar = read("shell/bar.luau")
        assert(bar:find("local pill_idle = not pill_now or pill_now.main == \"idle\"", 1, true), "idle, not busy")
        assert(bar:find("if pill_view and pill_idle and not pill_idle_was then pill_view_at = pill_ms end", 1, true), "the rest starts again when an activity ends")
        assert(bar:find("pillmod.view_hold(pill_view, pill_view_at, rest, pill_ms) == nil", 1, true), "the rule is lib/pill's")
    end)
    test("the desk: tiles in reading order, two a row, no overlap, a fifth dropped", function()
        local dg = require("lib.deskgrid")
        local all = dg.place({ "clock", "playing", "diagnostics", "calendar" })
        eq(#all, 4)
        eq(all[1].x, 0); eq(all[1].y, 0); eq(all[1].k, 0)
        eq(all[2].x, 304); eq(all[2].y, 0); eq(all[2].k, 1)
        eq(all[3].x, 0); eq(all[3].y, 84); eq(all[3].k, 2)
        eq(all[4].x, 304); eq(all[4].y, 84); eq(all[4].k, 3)
        eq(dg.place({ "playing" })[1].id, "playing")
        local dirty = dg.place({ "clock", "clock", "nope", "playing", "calendar", "diagnostics" })
        eq(#dirty, 4, "a duplicate, an unknown and the fifth are dropped")
        eq(#dg.chosen({ clock = true, playing = false, diagnostics = true, calendar = true }), 3, "the switches")
    end)
    test("the board draws it, and the settings own it", function()
        local conf = read("shell/lib/config.luau")
        for _, p in ipairs({ "pill.desk_clock", "pill.desk_playing", "pill.desk_diagnostics", "pill.desk_calendar", "pill.desk_surface", "pill.desk_border" }) do
            assert(conf:find('{ path = "' .. p .. '"', 1, true), p)
        end
        local board = read("shell/pillboard.luau")
        assert(board:find('local deskgrid = require("lib/deskgrid")', 1, true))
        assert(board:find("fact.pk_dk_n = #tiles", 1, true) and board:find('fact["pk_dk_t" .. i] = t and t.k or -1', 1, true), "the tiles, and where")
        local ui = read("shell/ui/pillboard.plm")
        assert(ui:find("component DeskTile(", 1, true), "drawn once")
        assert(ui:find("show: pk_room < 0.5 and not pk_music and pk_dk_n > 0.5", 1, true), "only Now, only with tiles")
        assert(ui:find("show: pk_room < 0.5 and not pk_music and pk_dk_n < 0.5", 1, true), "the old clock waits when the desk is empty")
        local plm = read("shell/mooi.plm")
        assert(plm:find("fact pk_dk_n = 0", 1, true) and plm:find("fact pk_dk_surface = 0", 1, true), "declared")
        local gen = read("tools/gen-settings.py")
        assert(gen:find('"pill.desk_clock", "pill.desk_playing"', 1, true), "the setters, appended")
        assert(gen:find('("choice", "The time",', 1, true) and gen:find('("card", "The desk")', 1, true), "their page (D188: one choice each)")
    end)
end

section("the Pill's settings, one control for each thing (D188)")
do
    local config = require("lib/config")
    test("a tile switched off keeps being off; the record reads as the attached capsule", function()
        local t = config.validate({ pill = { desk_clock = false, desk_clock_size = "wide", shape = "record" } })
        eq(t.pill.desk_clock_size, "off", "the old switch becomes the size")
        eq(t.pill.shape, "attached", "no record shape")
    end)
    test("the peek is a setting, on unless switched off", function()
        local found
        for _, e in ipairs(config.SCHEMA or {}) do if e.path == "pill.peek" then found = e end end
        assert(found and found.default == true, "pill.peek, default on")
    end)
end

section("the Pill's page: pictures, not words (D174)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("settings: a warmth and a ping, appended after the hiding choice", function()
        local cfg = read("shell/lib/config.luau")
        assert(cfg:find('{ path = "pill.warmth", kind = "integer", default = 55, min = 0, max = 100 }', 1, true), "the warmth")
        assert(cfg:find('{ path = "pill.ping", kind = "boolean", default = true }', 1, true), "the ping")
        local setters = require("lib/setters")
        local at = nil
        for i, p in ipairs(setters.SETTERS) do if p == "pill.warmth" then at = i end end
        assert(at and setters.SETTERS[at + 1] == "pill.ping", "the pair, in order, after everything")
        local gen = read("tools/gen-settings.py")
        assert(gen:find('"pill.warmth", "pill.ping",', 1, true), "the generator's copy, in the same place")
    end)
    test("the bar hands them over; the Pill obeys them", function()
        local bar = read("shell/bar.luau")
        assert(bar:find("fact.pill_warm = (tonumber(p.warmth) or 55) / 100", 1, true), "the warmth, a number")
        assert(bar:find("fact.pill_ping = p.ping ~= false", 1, true), "the ping, on unless off")
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("* pill_warm", 1, true), "the warmth scales the nearness")
        assert(ui:find("not pill_vanish and pill_ping and pill_turn_f > 0.02", 1, true), "and can be turned off")
        local plm = read("shell/mooi.plm")
        assert(plm:find("fact pill_warm = 0.55", 1, true) and plm:find("fact pill_ping = true", 1, true), "declared")
    end)
    test("the page shows it: a stage, and a card for every shape and form", function()
        local gen = read("tools/gen-settings.py")
        assert(gen:find('import "ui/pillpreview.plm"', 1, true), "the preview library is imported")
        assert(gen:find('if k == "pillstage":', 1, true) and gen:find('if k == "pillshapes":', 1, true)
               and gen:find('if k == "pillhide":', 1, true), "the three rows")
        local plm = read("shell/mooi-settings.plm")
        assert(plm:find("SPillStage(", 1, true), "the stage")
        assert(plm:find("SPillShape(", 1, true) and plm:find("SPillHide(", 1, true), "the cards")
        local lib = read("shell/ui/pillpreview.plm")
        assert(lib:find("component SPillStage", 1, true) and lib:find("component SPillShape", 1, true)
               and lib:find("component SPillHide", 1, true), "drawn in one place")
        assert(lib:find("ellipse { at: x + w - 16, y + 16; radius: 8; color: fl.phos }", 1, true), "a check on the chosen one")
        assert(plm:find("spin sp_ang by if(sv_pill_ping > 0.5, 70, 0)", 1, true), "the stage's ping turns")
    end)
end

section("the Pill feels the pointer, and turns with the workspaces (D173)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("the pointer's warmth: brighter as it comes near, and the dot leans toward it", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("let near = clamp(1 - (abs(cursor.x - cx) + abs(cursor.y - cy)) / 260, 0, 1) * pill_warm", 1, true), "nearness from the global cursor (D198)")
        assert(ui:find("let lean = clamp((cursor.x - cx) / 70, -1, 1) * 2.5 * near", 1, true), "the lean")
        assert(ui:find("on change p_over while p_over { emit pill_over(1) }", 1, true), "the peek follows the measured mouse (D198)")
        assert(ui:find("ellipse { at: px + pw / 2 + lean, fl.cy; radius: 3;", 1, true), "the dot moves, not the mark")
        assert(ui:find("glow: 9, (0.5 * near) * st_glow, fl.phos", 1, true), "the warmth, on the theme's glow")
    end)
    test("the edge flash replaces the half disc: one switch, one effect (D188)", function()
        local ui = read("shell/ui/pill.plm")
        assert(not ui:find("rotate: pill_turn_ang * 1deg", 1, true), "no turning half disc")
        assert(ui:find("stroke: 2; color: fl.phos; opacity: pill_turn_f", 1, true), "the capsule's edge lights and fades")
        local plm = read("shell/mooi.plm")
        assert(not plm:find("spin pill_turn_ang", 1, true), "nothing spins")
        local bar = read("shell/bar.luau")
        assert(bar:find("if not fact.dnd_now then pill_flare() end", 1, true), "a notice flashes it, not while do not disturb")
    end)
    test("a workspace change and a turned view both turn it, and a newer turn wins", function()
        local bar = read("shell/bar.luau")
        assert(bar:find("local function pill_flare()", 1, true), "one turn for both")
        assert(bar:find("local row = tonumber(fact.active_row)", 1, true), "the workspace the bar reads")
        assert(bar:find("if seq == pill_turn_seq then fact.pill_turn = 0 end", 1, true), "the newer flare is not cut short")
        local _, n = bar:gsub("pill_flare", "")
        assert(n >= 4, "the definition, the tick and both view turns (" .. n .. ")")
    end)
end

section("the Pill when idle: stay, tuck, vanish (D172)")
do
    local P = require("lib/pill")
    local chassis = require("lib/chassis")
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("settings: hiding is a three-way choice; the old switch keeps its answer", function()
        local d = config.defaults()
        eq(d.pill.hide, "stay")
        local s, pr = config.validate({ pill = { hide = "vanish" } })
        eq(#pr, 0); eq(s.pill.hide, "vanish")
        local bad, p2 = config.validate({ pill = { hide = "poof" } })
        eq(#p2, 1); eq(bad.pill.hide, "stay", "refused: the default")
        eq(config.validate({ pill = { autohide = true } }).pill.hide, "tuck", "the old switch, read as tuck")
        eq(config.validate({ pill = { autohide = true, hide = "stay" } }).pill.hide, "stay", "the choice wins")
        local setters = require("lib/setters")
        local seen = false
        for _, q in ipairs(setters.SETTERS) do if q == "pill.hide" then seen = true end end
        assert(seen, "the setter is appended")
    end)
    test("hide_mode: the choice, else the old switch's answer", function()
        eq(P.hide_mode({ hide = "stay" }), "stay")
        eq(P.hide_mode({ hide = "tuck" }), "tuck")
        eq(P.hide_mode({ hide = "vanish" }), "vanish")
        eq(P.hide_mode({ autohide = true }), "tuck", "a file written before the choice")
        eq(P.hide_mode({}), "stay", "nothing asked: it stays")
        eq(P.hide_mode(nil), "stay", "no config at all")
    end)
    test("vanish: idle and gone (0 px), back on a point or a call, and away again", function()
        local st = P.state()
        local v = P.compute(st, { face = "time", hide = "vanish" }, 0)
        eq(v.hidden, true); eq(v.vanish, true); eq(v.width, 0)
        local stay = P.compute(st, { face = "time", hide = "stay" }, 0)
        eq(stay.hidden, false); eq(stay.width, 120)
        eq(P.compute(st, { face = "time", hide = "tuck" }, 0).width, P.SLIVER)
        P.note(st, "peek", {}, 1000)
        local back = P.compute(st, { face = "time", hide = "vanish" }, 2000)
        eq(back.hidden, false); eq(back.vanish, false); eq(back.width, 120, "called or pointed at")
        eq(P.compute(st, { face = "time", hide = "vanish" }, 5100).vanish, true, "and away again")
        P.note(st, "media", { playing = true, title = "Song" }, 6000)
        eq(P.compute(st, { face = "time", hide = "vanish" }, 6000).hidden, false, "something happening: back")
    end)
    test("the dot: tucking makes it a dot, and stay never hides it", function()
        local st = P.state()
        local dot = P.compute(st, { face = "time", shape = "dot", hide = "tuck" }, 0)
        eq(dot.hidden, true); eq(dot.width, P.DOT, "tucked: its own dot, not a sliver")
        eq(P.compute(st, { face = "time", shape = "dot", hide = "vanish" }, 0).width, 0)
        local stay = P.compute(st, { face = "time", shape = "dot", hide = "stay" }, 0)
        eq(stay.hidden, true); eq(stay.width, P.DOT, "a dot rests as its dot even in stay")
    end)
    test("hex_rgb: a colour, or nothing", function()
        local r, g, b = P.hex_rgb("#FF8000")
        eq(math.floor(r * 255 + 0.5), 255); eq(math.floor(g * 255 + 0.5), 128); eq(b, 0)
        eq(P.hex_rgb("dragon"), nil); eq(P.hex_rgb(nil), nil); eq(P.hex_rgb("#ff800"), nil)
    end)
    test("the bar, the scene and the cover's colours carry it", function()
        local bar = read("shell/bar.luau")
        assert(bar:find("hide = p.hide", 1, true), "the hiding choice reaches compute")
        assert(bar:find("fact.pill_vanish = r.vanish == true", 1, true))
        assert(not bar:find("pill_record", 1, true), "no record field (D202)")
        assert(bar:find('run("matugen"', 1, true) and bar:find("pillmod.hex_rgb", 1, true), "the song's own colours")
        local plm = read("shell/mooi.plm")
        assert(plm:find("fact pill_vanish = false", 1, true))
        assert(plm:find("fact pc1_r", 1, true), "the cover's colours are still declared")
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("show: vanished", 1, true), "the seam")
        assert(not ui:find("component Record", 1, true) and not ui:find("pill_record", 1, true), "the disc is gone")
    end)
end

section("the Pill, round two: the new rooms (D171)")
do
    local P = require("lib/pill")
    local PP = require("lib/pillpads")
    local function board(settings, files)
        local handlers, ran = {}, {}
        local env = setmetatable({ on = function(n, fn) handlers[n] = fn end, every = function() end, after = function() end,
            run = function(cmd, args, cb) ran[#ran + 1] = cmd .. " " .. table.concat(args or {}, " "); if cb then cb("", 0) end end,
            sys = { ask = function(what, name) return files and files[name] or nil end, call = function() end },
            json = { decode = function(t) return t end },
            fact = { open = "none", pk_room = 0, pill_on = true }, model = {}, text = {} }, { __index = _G })
        local P2 = { now = function() return { main = "idle", moons = {} } end, osd = function() return "vol" end, bmo = function() return false end,
                     touch = function() end, react = function() end, say = function() end, poke = function() end }
        local api = assert(loadfile("shell/pillboard.luau", "t", env))()({ settings = function() return settings end, save = function() end, pill = P2,
            opened = function(v) env.fact.open = v end })
        return { api = api, h = handlers, fact = env.fact, text = env.text, ran = ran }
    end
    test("five new rooms, reached by the wheel; workspaces and wallpaper pads open theirs", function()
        assert(#PP.ROOMS >= 16, "at least the five D171 added")
        eq(PP.room_index("notes"), #PP.ROOMS - 1, "D201: notes is a room too")
        for _, r in ipairs(PP.ROOMS) do assert(PP.ROOM_NAME[r], r .. " has a name for the board's wheel") end
        for _, r in ipairs({ "visualiser", "actions", "diagnostics", "workspaces", "wallpaper" }) do assert(PP.room_index(r), r) end
        eq(PP.get("workspaces").room, "workspaces"); eq(PP.get("wallpaper").room, "wallpaper")
    end)
    test("a press opens the board on the room of the view the Pill shows", function()
        eq(P.press("idle", "workspaces", "left").room, "workspaces")
        eq(P.press("idle", "notifications", "left").room, "signals")
        eq(P.press("idle", "weather", "left").room, "weather")
        eq(P.press("idle", "visualiser", "left").room, "visualiser")
        eq(P.press("idle", "time", "left").room, "now")
        eq(P.press("music", "weather", "left").room, "now", "something happening: its own room")
    end)
    test("a press means the view showing: turned to weather on the Nexus face, it opens the Weather room, not the Nexus", function()
        local handlers = {}
        local env = setmetatable({ on = function(n, fn) handlers[n] = fn end, every = function() end, after = function() end, run = function() end,
            fact = { open = "none", pk_room = 0, pill_on = true }, model = {}, text = {} }, { __index = _G })
        local P2 = { now = function() return { main = "idle", moons = {} } end, osd = function() return "vol" end, bmo = function() return false end,
                     face = function() return "weather" end,
                     touch = function() end, react = function() end, say = function() end, poke = function() end }
        local api = assert(loadfile("shell/pillboard.luau", "t", env))()({ settings = function() return { pill = { face = "nexus" } } end,
            save = function() end, pill = P2, opened = function(v) env.fact.open = v end })
        api.press("left", "idle")
        eq(env.fact.open, "board"); eq(env.fact.pk_room, PP.room_index("weather"))
    end)
    test("workspaces: a press switches; actions: the drop terminal toggles", function()
        local b = board({ pill = {} })
        b.api.press("left", "idle")
        b.h.pk_ws(3); assert(b.ran[#b.ran]:find('hyprctl dispatch hl.dsp.focus({ workspace = "3" })', 1, true), "Hyprland's Lua form")
        b.h.pk_term(); assert(b.ran[#b.ran]:find("mooi-drop", 1, true), "the terminal, by its class")
    end)
    test("wallpaper: the strip moves with the wheel, a press wears it", function()
        local items = {}
        for i = 1, 20 do items[i] = { path = "/w/" .. i .. ".jpg", kind = "still", thumb = "/t/" .. i .. ".jpg" } end
        local b = board({ pill = {} }, { ["walls-index.json"] = { items = items } })
        b.api.press("left", "idle")
        b.h.pk_go(PP.room_index("wallpaper"))
        eq(b.text.pk_wp0, "/t/1.jpg")
        b.h.pk_wp_scroll(-1); eq(b.text.pk_wp0, "/t/2.jpg", "on by one")
        b.h.pk_wp(2); assert(b.ran[#b.ran]:find("mooi wall apply /w/4.jpg", 1, true), "the third shown is the fourth")
    end)
    test("the board tells the islands' readers its room (fact:pk_room is not heard for the logic's write)", function()
        local told = {}
        local handlers = {}
        local env = setmetatable({ on = function(n, fn) handlers[n] = fn end, every = function() end, after = function() end, run = function() end,
            fact = { open = "none", pk_room = 0, pill_on = true }, model = {}, text = {} }, { __index = _G })
        local P2 = { now = function() return { main = "idle", moons = {} } end, osd = function() return "vol" end, bmo = function() return false end,
                     touch = function() end, react = function() end, say = function() end, poke = function() end }
        local api = assert(loadfile("shell/pillboard.luau", "t", env))()({ settings = function() return { pill = {} } end, save = function() end,
            pill = P2, roomed = function(r) told[#told + 1] = r; env.fact.pk_room = r end })
        api.press("left", "idle"); handlers.pk_go(6)
        eq(told[#told], 6)
        local f = io.open("shell/islands.luau"); local isl = f:read("a"); f:close()
        assert(isl:find("ctx.listen_room(function() told() end)", 1, true))
    end)
    test("diagnostics: the machine read once as the room opens", function()
        local b = board({ pill = {} })
        b.api.press("left", "idle")
        b.h.pk_go(PP.room_index("diagnostics"))
        local any = false
        for _, r in ipairs(b.ran) do if r:find("cat /proc/sys/kernel/osrelease", 1, true) then any = true end end
        assert(any, "the kernel and host are read (through cat: the logic may not run uname)")
    end)
end

section("the Pill, round two: choosing the views (D171)")
do
    test("edit: a face's toggle puts it in the wheel's views or takes it out, saved", function()
        local st = { pill = { views = { "time", "weather" } } }
        local handlers = {}
        local env = setmetatable({ on = function(n, fn) handlers[n] = fn end, every = function() end, after = function() end, run = function() end,
            fact = { open = "none", pk_room = 0, pill_on = true }, model = {}, text = {} }, { __index = _G })
        local P2 = { now = function() return { main = "idle", moons = {} } end, osd = function() return "vol" end, bmo = function() return false end,
                     touch = function() end, react = function() end, say = function() end, poke = function() end }
        assert(loadfile("shell/pillboard.luau", "t", env))()({ settings = function() return st end, save = function() end, pill = P2 })
        handlers.pk_view_toggle(7); eq(st.pill.views[3], "workspaces", "in")
        handlers.pk_view_toggle(3); eq(#st.pill.views, 2, "weather out"); eq(st.pill.views[2], "workspaces")
        handlers.pk_view_toggle(0); handlers.pk_view_toggle(7)
        eq(#st.pill.views, 0); handlers.pk_view_toggle(99); eq(#st.pill.views, 0, "an unknown face does nothing")
    end)
    test("Settings: the shape, the detail and the rest", function()
        local f = io.open("shell/mooi-settings.plm"); local plm = f:read("a"); f:close()
        assert(plm:find('"Attached"', 1, true) and plm:find('"Floating"', 1, true) and plm:find('"Dot"', 1, true))
        assert(plm:find('"Icon"', 1, true) and plm:find('"Full"', 1, true))
        assert(plm:find("sv_pill_rest", 1, true))
    end)
end

section("the theme watch (2026-11-07)")
do
    test("a mode changed while Matugen runs is not taken as done: seen is what was read before the recolour", function()
        local f = io.open("bin/mooi"); local sh = f:read("a"); f:close()
        assert(sh:find("resync; seen=$now", 1, true), "seen is the key the extraction was for")
        assert(not sh:find("resync; seen=$(key)", 1, true), "not the key read again after it")
    end)
end

section("the Pill: Super and the wheel (D171)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("Super + wheel: on a pill it turns the views, anywhere else the workspace", function()
        local hl = read("setup/home/.config/hypr/config/custom/mooi.lua")
        assert(hl:find('hl.bind, "SUPER + mouse_down", hl.dsp.exec_cmd(mooi .. " wheel 1")', 1, true))
        assert(hl:find('hl.bind, "SUPER + mouse_up", hl.dsp.exec_cmd(mooi .. " wheel -1")', 1, true))
        local sh = read("bin/mooi")
        -- D209: while the opening shows the wheel widens and narrows it; otherwise the bar is asked
        assert(sh:find('wtc=$("$pleamar" --say mooi-surface "get op_tc" 2>/dev/null)', 1, true) and sh:find('[ "$wtc" -ge 1000 ]', 1, true), "the opening first (a let cannot be read; op_tc is a fact)")
        assert(sh:find('"emit op_wheel ${1:-1}"', 1, true), "widens or narrows while open")
        assert(sh:find('"emit pill_superwheel ${1:-1}"', 1, true), "else asks the bar")
        assert(sh:find('|| hyprctl dispatch "hl.dsp.focus({ workspace', 1, true), "no bar: the workspace (Hyprland's Lua form)")
        local bar = read("shell/bar.luau")
        local h = bar:match('on%("pill_superwheel", function%(v%)(.-)\n    end%)')
        assert(h and h:find("if pill_hovering and fact.pill_on", 1, true), "on a pill")
        assert(h:find("pill_ws_step(d)", 1, true), "elsewhere: the workspace")
        -- e+1 only moves between workspaces that exist: with one, Super + wheel went nowhere (2026-11-07)
        assert(h:find("pill_ws_step(d)", 1, true), "steps within the workspaces the bar shows")
        local B = require("lib/pill")
        eq(B.ws_step(2, 1, 4), 3); eq(B.ws_step(4, 1, 4), 1, "round"); eq(B.ws_step(1, -1, 4), 4); eq(B.ws_step(9, 1, 4), 1, "past the count: back to 1")
    end)
end

section("the Pill, round two: the review's fixes (D171)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    local P = require("lib/pill")
    test("review I1: in Pill mode the processor and memory are read (the Resources view, Diagnostics)", function()
        eq(P.needs({ pads = {}, face = "time", views = { "time" } }).resources, true)
    end)
    test("review I2: workspaces by their own ids and places, not 1..count", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("for w in spaces", 1, true) and ui:find("w.active", 1, true), "the face's dots")
        local b = read("shell/ui/pillboard.plm")
        assert(b:find("for w in spaces", 1, true) and b:find("pk_ws, w.id", 1, true), "the room's tiles go to their id")
    end)
    test("review I3: the Alerts face's newest goes when the signals do", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("pill_alert_on and loom_count > 0.5", 1, true))
    end)
    test("review (re-graded): the rest counts from when the pointer leaves and the board closes, not from the scroll", function()
        local bar = read("shell/bar.luau")
        assert(bar:find("if pill_view and (pill_hovering or open_board) then pill_view_at = pill_ms end", 1, true))
    end)
    test("review I4: Super twice opens the board (never the Nexus), or closes it", function()
        local handlers = {}
        local env = setmetatable({ on = function(n, fn) handlers[n] = fn end, every = function() end, after = function() end, run = function() end,
            fact = { open = "none", pk_room = 0, pill_on = true }, model = {}, text = {} }, { __index = _G })
        local poked = 0
        local P2 = { now = function() return { main = "idle", moons = {} } end, osd = function() return "vol" end, bmo = function() return true end,
                     face = function() return "nexus" end, touch = function() end, react = function() end, say = function() end,
                     poke = function() poked = poked + 1 end }
        local api = assert(loadfile("shell/pillboard.luau", "t", env))()({ settings = function() return { pill = { face = "nexus" } } end,
            save = function() end, pill = P2, opened = function(v) env.fact.open = v end })
        api.call("idle"); eq(env.fact.open, "board", "the board, not the Nexus")
        api.call("idle"); eq(env.fact.open, "none", "again: it closes (no poke)"); eq(poked, 0)
        local bar = read("shell/bar.luau")
        assert(bar:find("pill_board.call(pill_now and pill_now.main or \"idle\")", 1, true))
    end)
end

section("Hyprland's Lua dispatch (2026-11-07)")
do
    local H = require("lib/hypr")
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("the workspace, a command and a window by class, as Lua (`hyprctl dispatch workspace 3` is refused)", function()
        eq(H.go_workspace(3), 'hl.dsp.focus({ workspace = "3" })')
        eq(H.go_workspace("e+1"), 'hl.dsp.focus({ workspace = "e+1" })')
        eq(H.exec('kitty --class mooi-drop'), 'hl.dsp.exec_cmd("kitty --class mooi-drop")')
        eq(H.exec('say "hi"'), 'hl.dsp.exec_cmd("say \\"hi\\"")', "quotes escaped")
        eq(H.close_class("mooi-drop"), 'hl.dsp.window.close({ window = "class:mooi-drop" })')
    end)
    test("no caller sends the old form", function()
        for _, f in ipairs({ "shell/bar.luau", "shell/pillboard.luau" }) do
            local src = read(f)
            assert(not src:find('{ "dispatch", "workspace"', 1, true), f .. ": old workspace form")
            assert(not src:find('{ "dispatch", "exec"', 1, true), f .. ": old exec form")
            assert(not src:find('{ "dispatch", "closewindow"', 1, true), f .. ": old close form")
        end
        local sh = read("bin/mooi")
        assert(not sh:find('hyprctl dispatch workspace "e', 1, true), "bin/mooi's wheel fallback")
        local hl = read("setup/home/.config/hypr/config/custom/mooi.lua")
        assert(hl:find('match = { class = "^(mooi%-drop)$" }', 1, false) or hl:find('match = { class = "^(mooi-drop)$" }', 1, true), "the drop terminal's rule")
    end)
end

section("the Pill is alive: it follows the sound and says when it changes (D181)")
do
    local P = require("lib/pill")
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("a signature: what it shows, in one string", function()
        local st = P.state()
        local idle = P.compute(st, { face = "time" }, 0)
        eq(P.signature(idle, 0), P.signature(idle, 0), "the same reading twice")
        eq(P.signature(nil, 0), "", "nothing to sign")
        assert(P.signature(idle, 0) ~= P.signature(idle, 1), "the face is part of it")
        local music = P.state()
        P.note(music, "media", { playing = true, title = "Song", artist = "Band" }, 0)
        local m = P.compute(music, { face = "time" }, 0)
        assert(P.signature(m, 0) ~= P.signature(idle, 0), "music playing")
        local other = P.state()
        P.note(other, "media", { playing = true, title = "Tune", artist = "Band" }, 0)
        assert(P.signature(P.compute(other, { face = "time" }, 0), 0) ~= P.signature(m, 0),
               "a new title of the same length is a new reading")
        local split = P.state()
        P.note(split, "media", { playing = true, title = "Song", artist = "Band" }, 0)
        P.note(split, "notify", { app = "app", summary = "hi" }, 0)
        local sp = P.compute(split, { face = "time", multi = "split" }, 0)
        assert(sp.split ~= nil, "a split")
        assert(P.signature(sp, 0) ~= P.signature(m, 0), "the split is part of it")
        local hid = P.compute(P.state(), { face = "time", hide = "tuck" }, 0)
        assert(P.signature(hid, 0) ~= P.signature(idle, 0), "hidden is not shown")
    end)
    test("the bar raises it on a change and lets it settle; the scene eases it back", function()
        local bar = read("shell/bar.luau")
        assert(bar:find("local sig = pillmod.signature(r, fi)", 1, true), "the reading, from lib/pill")
        assert(bar:find("if pill_sig and (sig ~= pill_sig or gst ~= pill_gst) then", 1, true), "only a change surges")
        assert(bar:find("fact.pill_swap = 1", 1, true), "raised")
        assert(bar:find("if seq == pill_swap_seq then fact.pill_swap = 0 end", 1, true), "settled, the newer one winning")
        assert(bar:find("pill_sig, pill_gst = nil, nil", 1, true), "leaving Pill mode forgets it, so coming back surges")
        local plm = read("shell/mooi.plm")
        assert(plm:find("fact pill_swap = 0", 1, true), "declared")
        assert(plm:find("prop pill_swap_f = 0 ~m.isl_out", 1, true), "on the island's spring out")
        assert(plm:find("follow pill_swap_f = pill_swap", 1, true), "eased, never snapped")
        local ui = read("shell/ui/pill.plm")
        assert(not ui:find("pill_swap_f", 1, true), "D187: the capsule itself does nothing on a change")
    end)
    test("D191: ArchEclipse's spectrum rises from the capsule's foot, silent when nothing plays", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("follow spec_f = if(mu_playing and not pill_still and not pill_hidden and not pill_vanish and rv.board < 0.02", 1, true),
               "only while a song plays, motion is allowed, the capsule is there and not the board")
        assert(ui:find("opacity: spec_f * 0.55", 1, true), "ArchEclipse's strength, 55 %")
        assert(ui:find("let k = if(b < 8, 7 - b, b - 8)", 1, true), "mirror: the bass in the middle")
        assert(ui:find("let bh = v * pill_h * 0.45", 1, true), "45 % of the capsule")
        assert(ui:find("clip box { from: px, fl.top; size: max(1, pw), pill_h; corner: pill_h / 2 }", 1, true), "inside the capsule")
        assert(not ui:find("ellipse { at: px + pw / 2, fl.top + pill_h + 1", 1, true), "the glow under the foot is gone")
    end)
    test("D193: the audit's fixes — rooms stay in their room, the networks are listed, the band is silent", function()
        local bd = read("shell/ui/pillboard.plm")
        assert(bd:find("show: pk_room > 12.5 and pk_room < 13.5", 1, true), "the wallpaper strip is the Wallpaper room's only")
        assert(not bd:find("show: pk_room > 12.5\n", 1, true))
        assert(bd:find("line 0, 160 - lv0 * 70", 1, true) and not bd:find("line 0, 156 - lv0 * 70", 1, true),
               "the visualiser's band starts at its foot: silent, it draws nothing")
        assert(bd:find("PkBtn(518, 6, 80, pick(bluetooth.powered", 1, true), "the Bluetooth button beside its name")
        local lua = read("shell/pillboard.luau")
        assert(lua:find("local list = ctx.networks and ctx.networks() or nil", 1, true), "the shelf's watched list")
        assert(read("shell/islands.luau"):find("return { networks = function() return nets end }", 1, true))
        assert(read("shell/mooi.luau"):find("networks = function() return opens.islands and opens.islands.networks() or nil end", 1, true))
    end)
    test("D191: the glance face — dots, the clock and the live chip, measured like ArchEclipse's", function()
        local P = require("lib/pill")
        local R = require("lib/pillrows")
        -- D202: the bar measures the rest row (lib/pillrows); 220 is only what it is before it has
        eq(P.FACE_W.glance, 220)
        local lay, w = R.layout(R.rows({}).rest, { spaces = 5, title = "", battery = true, percent = 80 })
        eq(lay[1].id, "spaces"); assert(w > 100 and w < 400, "a real rest row's width")
        eq(P.compute(P.state(), { face = "glance", glance_w = 333 }, 0).width, 333)
        eq(P.compute(P.state(), { face = "glance" }, 0).width, 220)
        eq(P.press("idle", "glance", "left").room, "now")
        local C = require("lib/config")
        local cfg = C.validate({ pill = { face = "glance", views = { "glance", "time" } } })
        eq(cfg.pill.face, "glance"); eq(cfg.pill.views[1], "glance")
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("pill_face > 2.5 and pill_face < 10.5", 1, true), "module faces stop before it")
        assert(ui:find("GlanceFace(px, pw, cy)", 1, true))
        local bd = read("shell/ui/pillboard.plm")
        assert(bd:find('"VISUALISER", "GLANCE")', 1, true), "the editor offers it")
    end)
end

section("the Pill arrives, and the board pours out of it (D182, D183)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("nothing lifts, dims, sweeps or flashes: the capsule sits still", function()
        local ui = read("shell/ui/pill.plm")
        assert(not ui:find("3 * pill_swap_f", 1, true), "no lift")
        assert(not ui:find("1 - 0.35 * pill_swap_f", 1, true), "no dim")
        assert(not ui:find("1 - pill_swap_f", 1, true), "no sweep band")
        assert(not ui:find("pill_swap_f", 1, true), "D187: the scene does not read the surge at all")
    end)
    test("every activity is the same capsule, in the same layout", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("component Half(x: number, w: number, g: number, t1: text, t2: text, v: number)", 1, true), "one layout")
        assert(ui:find("let cover = med_has_art and (g > 0.5 and g < 1.5 or g > 4.5)", 1, true), "the cover takes the mark's place")
        assert(ui:find("text \"{t1}{? · {t2}}\" { at: x + 34, cy", 1, true), "one line, one left edge, whatever it is")
        assert(ui:find("Half(px, pw, pill_glyph, pill_t1, pill_t2, pill_val)", 1, true), "the recording is the same capsule's mark")
        assert(not ui:find("Record(px + pw / 2", 1, true), "no disc replaces it")
        assert(not ui:find("#69c7bb", 1, true), "BMO no longer paints a body round a different Pill")
    end)
    test("one body: the board is the capsule stretched, not a plate with shoulders (D188)", function()
        local bd = read("shell/ui/pillboard.plm")
        assert(not bd:find("curve bx + 1, btop via nkx - 4", 1, true), "D186's shoulders are gone")
        assert(bd:find("let btop = fl.top", 1, true), "its top is the capsule's top")
        assert(bd:find("mg: mg, msx: ms_x - bx, msw: ms_w, msh: ms_h", 1, true), "it grows from the start box")
        assert(bd:find("let ms_x = if(pk_sw > 0, clamp(pcx - pk_sw / 2, 8, screen.width - pk_sw - 8), pill_x)", 1, true),
               "from the capsule, or from the size it had")
        local isl = read("shell/ui/island.plm")
        assert(isl:find("let mw = msw + (w - msw) * max(0, mg)", 1, true), "the morph is not clamped at 1: it overshoots")
        assert(isl:find("on change want while want and ch and not mo", 1, true), "a morph tells the frame itself")
        local fr = read("shell/mooi-frame.plm")
        assert(fr:find("let pl_g = if(pl_on, clamp(pl_qm - (pl_n - 1), 0, 1.3), pl_c)", 1, true), "the frame runs the same spring")
        assert(fr:find("let pl_s_x = if(pl_re, pl_sx, pp_x)", 1, true), "and closes back into the capsule")
        local pill = read("shell/ui/pill.plm")
        assert(pill:find("opacity: 1 - smooth(0, 0.2, rv.board)", 1, true), "the capsule's face makes way")
    end)
    test("the board takes the size of what it shows (D188)", function()
        local P = require("lib/pill")
        local w, h, c = P.board_size(0, false, false)
        eq(w, 640); eq(h, 312); eq(c, 160)
        w, h, c = P.board_size(2, false, false)
        eq(h, 312); eq(c, 160)                   -- D189: sound's outputs reach 154, it keeps 160
        w, h, c = P.board_size(10, false, false)
        eq(h, 34 + 144 + 118); eq(c, 144)
        w, h = P.board_size(2, false, true)
        eq(w, P.PEEK_W); eq(h, P.PEEK_H)
        w, h = P.board_size(2, true, true)
        eq(w, P.EDIT_W); eq(h, P.EDIT_H)
        w, h, c = P.board_size("nonsense", false, false)
        eq(h, 312); eq(c, 160)
    end)
    test("every room's core fits a 160 drawing or is listed with its own (D189)", function()
        local P = require("lib/pill")
        for r, core in pairs(P.CORE) do
            assert(r >= 0 and r < 16, "a room by index")
            assert(core >= 144 and core <= 160, "room " .. r .. " cut below its drawing: " .. core)
        end
    end)
    test("a close keeps the peek's card and the editor until the body has folded (D189)", function()
        local f = io.open("shell/pillboard.luau"); local src = f:read("a"); f:close()
        local close = src:match("local function close%(%)(.-)\n    end")
        assert(close and not close:find("pk_peek", 1, true), "close() does not clear the peek at once")
        assert(src:find("if v ~= \"board\" then fact.pk_sw, fact.pk_sh = 0, 0; fold.later() end", 1, true),
               "a close the logic makes resets them later")
        assert(src:find("after(pillmod.FOLD_MS", 1, true), "after the fold")
        assert(src:find("if mine ~= fold.seq or opened == \"board\" then return end", 1, true),
               "unless the board opened again")
        assert(src:find("fact.pk_peek = peek == true", 1, true), "an opening says whether it is the peek")
        assert(src:find("open_board(\"now\", true, true)", 1, true), "the peek opens as the peek")
        local P = require("lib/pill")
        assert(P.FOLD_MS >= 250 and P.FOLD_MS <= 600, "longer than the closing springs, short enough to reopen")
    end)
end

section("a change is read, a counter stepping is not (D184)")
do
    local P = require("lib/pill")
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("a view that counts up is not a new reading", function()
        local rec = P.state()
        P.note(rec, "recording", { on = true }, 0)
        local a = P.compute(rec, { face = "time" }, 1000)
        local b = P.compute(rec, { face = "time" }, 2000)
        eq(a.main, "record", "recording is showing")
        assert(a.view.record.t1 ~= b.view.record.t1, "the clock moves")
        eq(P.signature(a, 0), P.signature(b, 0), "but it is the same reading, so no surge a second")
        eq(P.gesture(a, 0), P.gesture(b, 0), "and the same shape")
        local osd = P.state()
        P.note(osd, "osd", { kind = "vol", value = 0.4 }, 0)
        local o1 = P.compute(osd, { face = "time" }, 0)
        P.note(osd, "osd", { kind = "vol", value = 0.45 }, 0)
        local o2 = P.compute(osd, { face = "time" }, 0)
        eq(o1.main, "osd", "the volume is showing")
        eq(P.signature(o1, 0), P.signature(o2, 0), "a notch of the wheel is not news")
        eq(o1.width, o2.width, "nor a resize")
        P.note(osd, "osd", { kind = "bri", value = 0.5 }, 0)
        assert(P.gesture(P.compute(osd, { face = "time" }, 0), 0) ~= P.gesture(o2, 0), "turning to brightness is")
    end)
    test("the battery's percent steps without a surge, plugging in is a change", function()
        local st = P.state()
        P.note(st, "battery", { percent = 10, charging = false }, 0)
        local a = P.compute(st, { face = "time" }, 0)
        eq(a.main, "battery", "low enough to show")
        P.note(st, "battery", { percent = 9, charging = false }, 0)
        local b = P.compute(st, { face = "time" }, 0)
        eq(P.signature(a, 0), P.signature(b, 0), "a percent step is the same reading")
        eq(P.gesture(a, 0), P.gesture(b, 0), "and the same shape")
        eq(a.width, b.width, "and it does not resize the capsule")
        P.note(st, "battery", { percent = 5, charging = false }, 0)
        eq(P.compute(st, { face = "time" }, 0).width, a.width, "measured by its longest form, not by its luck")
        P.note(st, "battery", { percent = 9, charging = true }, 0)
        local c = P.compute(st, { face = "time" }, 0)
        assert(P.gesture(c, 0) ~= P.gesture(b, 0), "plugging in turns the mark: a whole surge")
    end)
    test("new words on the same face are a ripple; a new shape is a surge", function()
        local st = P.state()
        P.note(st, "media", { playing = true, title = "Song", artist = "Band" }, 0)
        local a = P.compute(st, { face = "time" }, 0)
        P.note(st, "media", { playing = true, title = "Another", artist = "Band" }, 0)
        local b = P.compute(st, { face = "time" }, 0)
        assert(P.signature(a, 0) ~= P.signature(b, 0), "a new song is a new reading")
        eq(P.gesture(a, 0), P.gesture(b, 0), "but the same shape: the bar ripples")
        local n = P.state()
        P.note(n, "media", { playing = true, title = "Song", artist = "Band" }, 0)
        P.note(n, "notify", { app = "app", summary = "hi" }, 0)
        local s = P.compute(n, { face = "time", multi = "split" }, 0)
        assert(s.split ~= nil, "a notice beside the music splits the Pill")
        assert(P.gesture(s, 0) ~= P.gesture(a, 0), "its shape changed: the bar surges")
    end)
    test("the bar grades it: whole for a new shape, a ripple for new words", function()
        local bar = read("shell/bar.luau")
        assert(bar:find("local gst = pillmod.gesture(r, fi)", 1, true), "the shape, from lib/pill")
        assert(bar:find("if gst ~= pill_gst then", 1, true), "the shape is what makes it whole")
        assert(bar:find("fact.pill_swap = 0.55", 1, true), "new words only ripple")
        assert(bar:find("pill_sig, pill_gst = nil, nil", 1, true), "leaving Pill mode forgets both")
        local lib = read("shell/lib/pill.luau")
        assert(lib:find("if v.steady then return tostring(v.glyph or \"\") end", 1, true), "a counter is signed by its mark")
        assert(lib:find("return { glyph = \"record\", t1 = \"REC \" .. clock(now - (st.rec_since or now)), steady = true, chars = 9 }", 1, true),
               "the record's clock")
    end)
end

section("the Pill's audit: moons, quiet, grooves, and the board's look (D185, D186)")
do
    local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
    test("a moon slides out of the capsule and back in instead of popping", function()
        local plm = read("shell/mooi.plm")
        local ui = read("shell/ui/pill.plm")
        assert(plm:find("follow moon_f0 = if(moon_k0 > -0.5, 1, 0)", 1, true), "eased by the moon's own presence")
        assert(ui:find("show: moon_f0 > 0.02", 1, true), "shown while it has any body")
        assert(ui:find("move: (1 - moon_f0) * 8, 0", 1, true), "sliding out to the left")
        assert(ui:find("move: (1 - moon_f1) * -8, 0", 1, true), "and the other way on the right")
        assert(ui:find("Mark(moon_x0 + 12, cy, max(0, moon_k0))", 1, true), "fading as a mark that is valid at any moment")
    end)
    test("do not disturb quiets the Pill too", function()
        local bar = read("shell/bar.luau")
        assert(bar:find("if fact.dnd_now then off.notify = true end", 1, true), "a notice does not take it")
        assert(bar:find("if fact.dnd_now then fact.pill_swap = 0.4 end", 1, true), "and nothing surges hard")
        assert(bar:find("if fact.dnd_now then fact.pill_swap = 0.3 end", 1, true), "a ripple is quieter still")
    end)
    test("the recording is a capsule with its clock, not a disc", function()
        local ui = read("shell/ui/pill.plm")
        assert(ui:find("Half(px, pw, pill_glyph, pill_t1, pill_t2, pill_val)", 1, true), "the same layout, the recording's own mark")
        local lib = read("shell/lib/pill.luau")
        assert(not lib:find("local dw = tonumber(cfg.disc)", 1, true), "and it no longer resizes the Pill to a disc")
    end)
    test("the board's look is the bar's material with a wash and an edge of its own", function()
        local bd = read("shell/ui/pillboard.plm")
        assert(bd:find("group { show: pk_tint > 0.5", 1, true), "the wash, or none")
        assert(bd:find("color: if(pk_tint > 1.5, acc, fl.phos); opacity: 0.12", 1, true), "the theme's own light")
        assert(bd:find("show: rv.board > 0.02 and pk_edge > 0.5 and pk_edge < 1.5", 1, true), "the edge, hairline or none")
        local cfg = read("shell/lib/config.luau")
        assert(cfg:find("pill.board_tint", 1, true) and cfg:find("pill.board_edge", 1, true), "both are choices")
        assert(cfg:find("The plate under it is the bar's own material", 1, true), "the comment says where the material comes from")
    end)
end

section("Loom / Fold: the shared model, modes, parking (D194)")
do
    local L = require("lib/loom")
    local LM = require("lib/loommode")
    local LP = require("lib/loompark")
    local function win(doc, addr, ws, extra)
        local f = { kind = "window", app = "kitty", title = "t" .. addr, address = addr, workspace = ws, at = { 10, 20, 800, 600 } }
        for k, v in pairs(extra or {}) do f[k] = v end
        return L.add_object(doc, f)
    end
    test("a document from anything is valid; what was dropped is said", function()
        local d, p = L.clean(nil); eq(#p, 0); eq(d.version, 1)
        d, p = L.clean("nonsense"); eq(#p, 1)
        d, p = L.clean({ version = 1, seq = 3,
            objects = { o1 = { kind = "window", app = "kitty", state = "live", address = "0xab", parent = "s2" },
                        bad = { kind = "window" }, o9 = { kind = "spaceship" } },
            structures = { s2 = { kind = "accordion", members = { "o1", "o1", "o404" }, arrangement = { order = { "o404" } } },
                           s3 = { kind = "ring" } },
            connections = { c4 = { from = "o1", to = "s2", kind = "workflow" }, c5 = { from = "o1", to = "o77", kind = "association" },
                            c6 = { from = "o1", to = "o1", kind = "association" }, c7 = { from = "o1", to = "s2", kind = "workflow" } } })
        assert(d.objects.o1 and not d.objects.bad and not d.objects.o9, "valid objects only")
        assert(d.structures.s2 and not d.structures.s3, "only the structures mooi has (a ring is not built)")
        eq(#d.structures.s2.members, 1, "no duplicate, no missing member"); eq(d.structures.s2.arrangement.order[1], "o1")
        eq(d.objects.o1.parent, "s2")
        assert(d.connections.c4 and not d.connections.c5 and not d.connections.c6 and not d.connections.c7,
               "a connection needs both ends, two of them, and is not duplicated")
        assert(#p >= 3, "it says what it dropped")
        eq(d.seq >= 9, true, "the counter is past every id seen")
        d = L.clean({ version = 9 }); eq(d.version, 1)
    end)
    test("an object belongs to one structure; members, order and parent always agree", function()
        local d = L.empty()
        local a, b, c = win(d, "0x1", 1), win(d, "0x2", 1), win(d, "0x3", 2)
        local s1 = L.add_structure(d, "accordion", "Writing", { a, b })
        local s2 = L.add_structure(d, "cube", "Dev", { c })
        eq(d.objects[a].parent, s1); eq(#d.structures[s1].arrangement.order, 2)
        assert(L.add_member(d, s2, a), "moving a member")
        eq(d.objects[a].parent, s2); eq(#d.structures[s1].members, 1); eq(#d.structures[s2].members, 2)
        assert(L.reorder(d, s2, a, 1)); eq(d.structures[s2].arrangement.order[1], a)
        assert(not L.add_structure(d, "ring", "x"), "a structure mooi does not have is refused")
        assert(L.remove_structure(d, s1)); eq(d.objects[b].parent, nil, "its members are kept, loose")
        assert(d.objects[b], "nothing is lost with a structure")
    end)
    test("connections: kinds, ends, no duplicates, and they follow removals", function()
        local d = L.empty()
        local a, b = win(d, "0x1", 1), win(d, "0x2", 1)
        local s = L.add_structure(d, "accordion", "A", { a })
        local c1 = L.connect(d, a, b, "workflow", true)
        eq(L.connect(d, a, b, "workflow", true), c1, "the same connection twice is one")
        assert(not L.connect(d, a, a, "association"), "not to itself")
        assert(not L.connect(d, a, "o999", "association"), "both ends exist")
        assert(not L.connect(d, a, b, "friendship"), "a kind mooi knows")
        local c2 = L.connect(d, s, b, "dependency")
        local r = L.related(d, b); eq(#r, 2); eq(r[1].id, a); eq(r[1].out, false)
        L.remove_object(d, a)
        assert(not d.connections[c1] and d.connections[c2], "a removed object takes its connections with it")
    end)
    test("windows matched after a restart: by address, then app and title; the rest kept absent", function()
        local d = L.empty()
        local a = win(d, "0xaa", 2, { title = "notes" })
        local b = win(d, "0xbb", 3, { title = "build" })
        local c = win(d, "0xcc", 4, { title = "gone" })
        local s = L.add_structure(d, "accordion", "A", { a, b, c })
        local r = L.match(d, {
            { address = "0xaa", class = "kitty", title = "notes", workspace = { id = 5, name = "5" }, at = { 0, 0 }, size = { 900, 700 } },
            { address = "0x99", class = "kitty", title = "build", workspace = { id = -98, name = "special:loom-" .. s } },
            { address = "0x77", class = "firefox", title = "web", workspace = { id = 1, name = "1" } } })
        eq(r.matched, 2); eq(r.absent, 1); eq(#r.loose, 1); eq(r.loose[1].address, "0x77")
        eq(d.objects[a].workspace, 5); eq(d.objects[a].at[3], 900)
        eq(d.objects[b].address, "0x99", "the new handle"); eq(d.objects[b].state, "parked")
        eq(d.objects[b].workspace, 3, "where it came from is kept for the way back")
        eq(d.objects[c].state, "absent"); eq(d.objects[c].parent, s, "an absent window is kept in its structure")
    end)
    test("prune keeps what the owner organised, drops windows only registered because they were open", function()
        local d = L.empty()
        local a, b, c = win(d, "0x1", 1), win(d, "0x2", 1), win(d, "0x3", 1)
        L.add_structure(d, "accordion", "A", { a })
        L.connect(d, b, a, "association")
        local loose = win(d, "0x4", 1)
        eq(L.prune(d), 2, "c and the last one were only open")
        assert(d.objects[a] and d.objects[b], "a member and a connected window stay")
        assert(not d.objects[c] and not d.objects[loose])
    end)
    test("the journal: pending until done; at start the safe side is always windows visible", function()
        local d = L.empty()
        local j = L.journal_begin(d, "fold", "s1", { { object = "o1", from = "2", to = "special:loom-s1" } }, 100)
        eq(#L.pending(d), 1); eq(L.recovery_for(L.pending(d)[1]), "rollback")
        eq(L.recovery_for({ op = "unfold" }), "complete")
        L.journal_end(d, j); eq(#L.pending(d), 0)
        for i = 1, 60 do L.journal_end(d, L.journal_begin(d, "fold", "s1", {}, i)) end
        eq(#d.journal, L.MAX.journal, "the journal is bounded")
        local back = L.clean(d); eq(#back.journal, L.MAX.journal, "and survives a round trip")
    end)
    test("modes: native runs nothing; hybrid follows switches and needs; loomfold turns on what is built", function()
        eq(LM.runs("native"), false); eq(LM.runs("hybrid"), true); eq(LM.runs("weird"), false, "an unknown mode is native")
        local e = LM.effective("hybrid", {}, nil)
        assert(not e.on.transform and e.off.transform == "not built yet", "nothing is on before it is built")
        assert(e.on.cubes, "D197: Cubes are built")
        assert(e.on.fold and e.on.accordions, "D195: Fold and Accordions are built, on by default in Hybrid")
        local built = { fold = true, accordions = true, cubes = true, loom = true }
        e = LM.effective("hybrid", { fold = false, accordions = true }, built)
        assert(not e.on.accordions); eq(e.off.accordions, "Accordions needs Fold — turn Fold on first")
        assert(e.on.loom, "Loom does not need Fold")
        e = LM.effective("loomfold", { fold = false, loom = false }, built)
        assert(e.on.fold and e.on.accordions and e.on.loom, "full mode: every built feature, whatever Hybrid's switches")
        assert(not e.on.spatial and e.off.spatial == "not built yet")
        e = LM.effective("hybrid", {}, { spatial = true }); eq(e.off.spatial, "only in Loom / Fold mode")
        e = LM.effective("native", { fold = true }, built); assert(not e.on.fold)
        local offered = LM.offered("hybrid", {}, { fold = true, accordions = true, cubes = false, loom = false })
        eq(#offered, 2, "Settings offers only what is built")
        eq(LM.status_line("native", {}), "Off — Native mooi")
        eq(LM.status_line("hybrid", { running = true, structures = 2 }), "Hybrid · running · 2 structures")
        assert(LM.status_line("hybrid", { recovery = true }):find("repeated failures", 1, true))
    end)
    test("parking: to the structure's own special workspace and back where it came from", function()
        local d = L.empty()
        local a = win(d, "0xa1", 3)
        local b = win(d, "0xb1", 4, { floating = true })
        local s = L.add_structure(d, "accordion", "A", { a, b })
        local steps = LP.park(d, s, { a, b })
        eq(#steps, 2)
        assert(steps[1].cmd:find('workspace = "special:loom-' .. s .. '", follow = false', 1, true), steps[1].cmd)
        for _, st in ipairs(steps) do LP.apply(d, st) end
        eq(d.objects[a].state, "parked"); eq(#LP.park(d, s, { a }), 0, "a parked window is not parked twice")
        eq(#L.parked(d), 2)
        local back = LP.unpark_all(d)
        eq(#back, 2)
        assert(back[1].cmds[1]:find("workspace = 3, follow = false", 1, true), "to its own workspace, the view does not jump")
        eq(#back[2].cmds, 3, "a floating one also goes back to its place and size")
        assert(back[2].cmds[2]:find("x = 10, y = 20", 1, true))
        for _, st in ipairs(back) do LP.apply(d, st) end
        eq(#L.parked(d), 0)
        eq(LP.park_name("s12"), "loom-s12"); eq(LP.park_name("x; rm -rf"), nil)
        local hypr = require("lib/hypr")
        assert(not hypr.dispatch("park", "0xa1", { park = 'loom-s1" })' }), "a park name is checked")
    end)
    -- the keeper (shell/loomkeeper.luau) against stand-ins for Pleamar's globals
    local function keeper(settings, files)
        files = files or {}
        local h, ran, spawned, timers, killed = {}, {}, {}, {}, {}
        local env = setmetatable({
            on = function(n, fn) h[n] = fn end,
            after = function(ms, fn) timers[#timers + 1] = fn end,
            run = function(cmd, args, cb) ran[#ran + 1] = cmd .. " " .. table.concat(args or {}, " ")
                      if cb then cb(cmd == "hyprctl" and args[1] == "-j" and (args[2] == "clients" and "[]" or '{"id": 4}') or "") end end,
            spawn = function(cmd, args, on_line, on_exit) spawned[#spawned + 1] = { args = args, line = on_line, exit = on_exit }; return #spawned end,
            kill = function(id) killed[#killed + 1] = id end,
            sys = { ask = function(_, name) return files[name] end,
                    call = function(what, name, t) if what == "files.write" then files[name] = t end end },
        }, { __index = _G })
        local sync = assert(loadfile("shell/loomkeeper.luau", "t", env))()({
            settings = function() return settings end, shell_dir = function() return "/live" end,
            log = function() end, decode = function() return {} end, safe_mode = false })
        local function tick() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end
        return { sync = sync, h = h, ran = ran, spawned = spawned, tick = tick, killed = killed, files = files }
    end
    local function has(list, pat) for _, r in ipairs(list) do if r:find(pat, 1, true) then return true end end; return false end
    test("the keeper: native starts nothing; hybrid starts the program and says when it is up", function()
        local st = { loom = { mode = "native" } }
        local k = keeper(st)
        k.tick(); eq(#k.spawned, 0, "Native mooi runs none of it")
        st.loom.mode = "hybrid"; k.sync()
        eq(#k.spawned, 1); eq(k.spawned[1].args[2], "/live/mooi-loom.plm")
        k.spawned[1].line("logic · loom-ready"); eq(k.files["loom-state.json"].running, true)
        k.spawned[1].line("loom-health structures=2 objects=7 parked=1"); eq(k.files["loom-state.json"].structures, 2)
        st.loom.mode = "native"; k.sync()
        assert(has(k.ran, "--say mooi-loom emit loom_quit"), "asked to stop politely")
        k.tick(); eq(k.killed[1], 1, "and ended if it has not gone in 4 s")
    end)
    test("the keeper: three quick deaths → recovery, said once, every parked window brought back", function()
        local parked = { version = 1, objects = { o1 = { kind = "window", app = "kitty", state = "parked", address = "0xaa", workspace = 3 } },
                         structures = {}, connections = {}, environments = {}, journal = {} }
        local st = { loom = { mode = "hybrid" } }
        local k = keeper(st, { ["loom.json"] = parked })
        k.tick()
        for i = 1, 3 do
            eq(#k.spawned, i, "started again after death " .. (i - 1))
            k.spawned[i].exit(nil, 1)
            k.tick()
        end
        eq(#k.spawned, 3, "it gives up after three")
        eq(k.files["loom-state.json"].recovery, true)
        assert(has(k.ran, "notify-send"), "the owner is told")
        assert(has(k.ran, 'hl.dsp.window.move({ workspace = 3, follow = false, window = "address:0xaa" })'), "the parked window comes back")
        k.sync(); eq(#k.spawned, 3, "a recovery stands until Start again")
        k.h.loom_restart(); eq(#k.spawned, 4, "Start again starts it")
        eq(k.files["loom-state.json"].recovery, false)
    end)
    test("the keeper follows the settings file itself (the bar's watcher runs before `opens` exists)", function()
        local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
        local kp = read("shell/loomkeeper.luau")
        assert(kp:find('pcall(sys.watch, "files:settings.json", function() after(100, function() sync() end) end)', 1, true))
        local m = read("shell/mooi.luau")
        local at_watch = m:find('sys.watch("files:" .. FILE, function()', 1, true)
        local at_opens = m:find("local opens = {", 1, true)
        assert(at_watch < at_opens, "the watcher is above `opens`")
        assert(not m:sub(at_watch, at_opens):find("opens.loom", 1, true), "so it must not name opens.loom")
    end)
    test("the keeper: a recovery stands across a bar restart", function()
        local k = keeper({ loom = { mode = "hybrid" } }, { ["loom-state.json"] = { recovery = true } })
        k.tick(); eq(#k.spawned, 0)
    end)
    test("D195 accordion: add makes it the one in use; pull is one at a time; step goes round", function()
        local A = require("lib/loomaccordion")
        local d = L.empty()
        local a, b, c = win(d, "0xa", 2), win(d, "0xb", 2), win(d, "0xc", 3)
        local sid = A.create(d, "Work")
        local p = A.add(d, sid, a, 2); A.commit(d, sid, p, 1)
        eq(d.structures[sid].arrangement.open[1], a); eq(d.objects[a].state, "live")
        p = A.add(d, sid, b, 2)
        assert(p.cmds[1]:find("special:loom-" .. sid, 1, true), "the previous one parks first")
        assert(p.cmds[#p.cmds]:find("hl.dsp.focus", 1, true), "the added one takes the focus")
        A.commit(d, sid, p, 2)
        eq(d.objects[a].state, "parked"); eq(d.structures[sid].arrangement.open[1], b)
        A.commit(d, sid, A.add(d, sid, c, 2), 3)
        p = A.step(d, sid, 1, 5)    -- after c (the last) comes a, round the end
        assert(p.cmds[2]:find("workspace = 5, follow = false", 1, true), "a pulled layer comes to where you are: " .. tostring(p.cmds[2]))
        A.commit(d, sid, p, 4)
        eq(d.structures[sid].arrangement.open[1], a); eq(d.objects[a].workspace, 5); eq(d.objects[c].state, "parked")
        p = A.step(d, sid, -1, 5); A.commit(d, sid, p, 5)
        eq(d.structures[sid].arrangement.open[1], c, "previous, round the start")
    end)
    test("D195 accordion: open all, fold, push, remove, dissolve, reorder; rows for the scene", function()
        local A = require("lib/loomaccordion")
        local d = L.empty()
        local a, b = win(d, "0xa", 2), win(d, "0xb", 2)
        local sid = A.create(d, "Work")
        A.commit(d, sid, A.add(d, sid, a, 2), 1); A.commit(d, sid, A.add(d, sid, b, 2), 2)
        local p = A.open_all(d, sid, 4); A.commit(d, sid, p, 3)
        eq(d.structures[sid].state, "tiled"); eq(#d.structures[sid].arrangement.open, 2); eq(d.objects[a].workspace, 4)
        A.commit(d, sid, A.fold(d, sid), 4)
        eq(#L.parked(d), 2); eq(#d.structures[sid].arrangement.open, 0)
        A.commit(d, sid, A.pull(d, sid, b, 4), 5)
        A.commit(d, sid, A.push(d, sid, b), 6); eq(#L.parked(d), 2)
        L.reorder(d, sid, b, 1); eq(d.structures[sid].arrangement.order[1], b)
        local strips, layers = A.rows(d)
        eq(#strips, 1); eq(strips[1].n, 2); eq(layers[1].initial, "K"); eq(strips[1].open, -1)
        local k, o = A.layer_oid(d, 0, 1); eq(k, sid); eq(o, a)
        p = A.remove(d, sid, a, 4); A.commit(d, sid, p, 7)
        eq(d.objects[a].parent, nil); eq(d.objects[a].state, "live", "a removed layer comes out and stays")
        eq(A.of_window(d, "0xb"), sid); eq(A.active(d, "0xzz"), sid, "the one used last")
        p = A.dissolve(d, sid, 4); A.commit(d, sid, p, 8)
        assert(not d.structures[sid], "dissolved"); eq(d.objects[b].state, "live"); eq(#L.parked(d), 0)
    end)
    test("D195: the Accordion keys are mooi keys, and no two keys share a default", function()
        local C = require("lib/config")
        local D = require("lib/desktop")
        local d = C.defaults()
        local seen = {}
        for k, v in pairs(d.keys) do
            assert(not seen[v], "two keys default to " .. v .. ": " .. tostring(seen[v]) .. " and " .. k)
            seen[v] = k
        end
        local cmds = {}
        for _, a in ipairs(D.ACTIONS) do cmds[a.key] = a.cmd end
        eq(cmds.loom_add, "loom add"); eq(cmds.loom_open, "loom open")
        eq(d.keys.loom_open, "SUPER + ALT + U", "O is the Overview's")
    end)
    test("D195: the program runs plans one at a time, journaled; the strip is one zone per accordion", function()
        local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
        local lua = read("shell/mooi-loom.luau")
        assert(lua:find("if busy then queue[#queue + 1] = { op, sid, make, commit }; return end", 1, true), "one plan at a time")
        assert(lua:find("local j = loom.journal_begin(doc, op, target or \"\", p.moves, os.time())", 1, true), "journaled before it moves")
        assert(lua:find("(was and not features.on.accordions and s.kind == \"accordion\") or (was_c and not features.on.cubes and s.kind == \"cube\")", 1, true),
               "turned off, their windows come out")
        assert(lua:find("local closed = not first and before[oid] and before[oid] ~= \"absent\"", 1, true), "a closed window leaves, a restart keeps")
        local ui = read("shell/ui/loomstrip.plm")
        local zones = 0
        for _ in ui:gmatch("zone box ") do zones = zones + 1 end
        eq(zones, 2, "the strip's zone and its tag: a layer is never its own zone")
        assert(ui:find("on release z while abs(drag.dy) >= 6 { emit acc_move(", 1, true), "a drag reorders")
        local plm = read("shell/mooi-loom.plm")
        assert(plm:find("anchor: lf_side", 1, true) and plm:find("open: lf_draw", 1, true), "on the chosen edge, open only with a strip")
    end)
    test("D197 cube: made from windows by role; folds, unfolds home, opens one face; turns", function()
        local CB = require("lib/loomcube")
        local d = L.empty()
        local a = win(d, "0xa", 2, { app = "code" })
        local f = win(d, "0xf", 2, { app = "org.gnome.Nautilus" })
        local b = win(d, "0xb", 3, { app = "firefox" })
        local sid = CB.create(d, { a, f, b }, b, "Dev")
        local faces = CB.faces(d, sid)
        eq(faces.front[1], b, "the focused window on the front"); eq(faces.left[1], f, "files on the left"); eq(faces.right[1], a)
        local p = CB.fold(d, sid); eq(#p.cmds, 3); CB.commit(d, sid, p, 1)
        eq(d.structures[sid].state, "folded"); eq(#L.parked(d), 3)
        p = CB.unfold(d, sid, "left"); CB.commit(d, sid, p, 2)
        eq(d.objects[f].state, "live"); eq(d.structures[sid].state, "partial", "the rest stay folded")
        assert(p.cmds[1]:find("workspace = 2, follow = false", 1, true), "home, to its own workspace")
        p = CB.unfold(d, sid); CB.commit(d, sid, p, 3)
        eq(#L.parked(d), 0); eq(d.structures[sid].state, "unfolded")
        eq(d.objects[b].workspace, 3, "each to where it was")
        eq(CB.turn(d, sid, 1), 1); eq(select(2, CB.facing(d, sid)), "right"); eq(CB.turn(d, sid, -1), 0); eq(CB.turn(d, sid, -1), 3)
        local rows = CB.rows(d); eq(#rows, 1); eq(rows[1].n0, 1); eq(rows[1].i0, "F"); eq(rows[1].face, 3)
        eq(CB.cube_sid(d, 0), sid); eq(CB.of_window(d, "0xa"), sid)
    end)
    test("D197 cube: a window joins the facing face, folded if the cube is; dissolving keeps every window", function()
        local CB = require("lib/loomcube")
        local d = L.empty()
        local a, b = win(d, "0xa", 2), win(d, "0xb", 2)
        local sid = CB.create(d, { a }, a)
        CB.commit(d, sid, CB.fold(d, sid), 1)
        CB.turn(d, sid, 1)
        local p = CB.add(d, sid, b); CB.commit(d, sid, p, 2)
        eq(CB.faces(d, sid).right[#CB.faces(d, sid).right], b, "on the facing face"); eq(d.objects[b].state, "parked", "a folded cube takes it in folded")
        eq(CB.last(d, true), sid)
        p = CB.dissolve(d, sid); CB.commit(d, sid, p, 3)
        assert(not d.structures[sid]); eq(#L.parked(d), 0); assert(d.objects[a] and d.objects[b])
    end)
    test("D197: the cube is drawn as a projection, one zone; new keys reach Hyprland at start", function()
        local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
        local ui = read("shell/ui/loomcube.plm")
        assert(ui:find("follow yaw = 0 - turn * 90 - 25", 1, true), "it rolls round on a spring by its turn count, askew at rest")
        assert(ui:find("show: ca > 0.02", 1, true), "a side is drawn only while it faces you")
        local zones = 0
        for _ in ui:gmatch("zone box ") do zones = zones + 1 end
        eq(zones, 1, "one zone per cube")
        local plm = read("shell/mooi-loom.plm")
        assert(plm:find("lc.LoomCube(", 1, true) and plm:find("model lf_cubes max 6", 1, true))
        local m = read("shell/mooi.luau")
        local def = m:find("function sync_desktop()", 1, true)
        local call = m:find("if bar_palette then sync_desktop() end", 1, true)
        assert(def and call and call > def, "called once right after it is defined (start skipped it before)")
        local lua = read("shell/mooi-loom.luau")
        assert(lua:find("if sid then run_plan(\"fold\", sid, function() return cube.fold(doc, sid) end, cube.commit); return end", 1, true),
               "fold acts on the focused window's cube first")
    end)
    test("D198: the reveal's items arrive in turn; the strip swells and the cube leans toward the mouse", function()
        local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
        local bd = read("shell/ui/pillboard.plm")
        assert(bd:find("RowItem(it.k, d0 + it.x, 66, it.w, it.room, clamp((rf - 0.15 - it.x / pr_detail_w * 0.3) * 3, 0, 1), true, acc, ink, dim)", 1, true),
               "each item in its turn, along its row (D199: the rows are the owner's)")
        assert(bd:find("move: 0, 5 * (1 - f)", 1, true), "each rises as it fades in")
        local st = read("shell/ui/loomstrip.plm")
        assert(st:find("let mag = clamp(1 - abs(cursor.y - (y + lh / 2)) / 70, 0, 1) * edge_near * (1 - ext)", 1, true), "a dock's swell")
        local cb = read("shell/ui/loomcube.plm")
        assert(cb:find("let lean = clamp((cursor.x - cx) / 420, -1, 1) * 14", 1, true), "the cube leans")
        local pill = read("shell/ui/pill.plm")
        assert(not pill:find("pill_swap_f", 1, true), "and still no effect on the capsule itself (D187)")
    end)
    test("D199: the Pill's three rows (ArchEclipse's rest · core · detail): clean, lay out, move, shelf", function()
        local R = require("lib/pillrows")
        local rows = R.rows({})
        eq(rows.rest[1], "spaces"); eq(#rows.core, 4); eq(#rows.detail, 6)
        eq(#R.clean({ "clock", "clock", "nonsense", "date" }, "rest"), 2, "known, once")
        local lay, w = R.layout(rows.core, { title = "", battery = true })
        eq(#lay, 3, "no song: the media item leaves"); eq(lay[1].id, "bandwidth"); eq(lay[1].x, 14)
        eq(w, 14 + 150 + 14 + 84 + 14 + 46 + 14)
        local r2 = R.move(rows, "detail", 1, "rest", 2)               -- weather into the rest row, second
        eq(r2.rest[2], "weather"); eq(#r2.detail, 5); eq(rows.detail[1], "weather", "the old rows are left alone")
        local r3 = R.move(r2, "rest", 1, "rest", 5)                  -- spaces past the last: the end of its own row
        eq(r3.rest[#r3.rest], "spaces"); eq(r3.rest[1], "weather")
        local r4 = R.move(r3, "core", 2, "shelf")                    -- bandwidth hidden
        eq(#r4.core, 3); local sh = R.shelf(r4); assert(sh[1] == "bandwidth" or sh[2] == "bandwidth")
        local r5 = R.move(r4, "shelf", 1, "detail", 1)
        eq(r5.detail[1], R.shelf(r4)[1], "back from the shelf")
        local r6 = R.move(rows, "core", 4, "rest", 1)                -- clock is in rest already: one copy
        local n = 0; for _, id in ipairs(r6.rest) do if id == "clock" then n = n + 1 end end; eq(n, 1)
        eq(R.drop_at(lay, 0), 1); eq(R.drop_at(lay, 1000), 4)
    end)
    test("D199: the rows drive the glance face and the reveal; the ROWS tab drags chips between them", function()
        local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
        local pill = read("shell/ui/pill.plm")
        assert(pill:find("for it in pr_rest {", 1, true), "the capsule's rest row")
        local bd = read("shell/ui/pillboard.plm")
        assert(bd:find("for it in pr_core {", 1, true) and bd:find("for it in pr_detail {", 1, true), "the reveal's two rows")
        assert(not bd:find("component RevChip(", 1, true), "the fixed items are gone")
        assert(bd:find('PkBtn(354, 4, 96, "ROWS", if(pk_etab > 1.5, 1, 0), pk_etab, 2)', 1, true), "a ROWS tab")
        assert(bd:find("on release c { emit pe_drop(", 1, true), "let go where it goes")
        local lua = read("shell/pillboard.luau")
        assert(lua:find("local new = pillrows.move(rows, from, held_now.i, to, at)", 1, true), "the move is lib/pillrows'")
        local bar = read("shell/bar.luau")
        assert(bar:find("glance_w = bmo_fx.rest_w", 1, true), "the capsule is as wide as its rest row")
        local P = require("lib/pill")
        local w = P.board_size(0, false, true, 720); eq(w, 720, "the reveal as wide as its wider row")
        eq((P.board_size(0, false, true, 50)), 300); eq((P.board_size(0, false, true, 5000)), 900)
    end)
    test("D200 loom: jumps follow a workflow first; dependants; links survive a fold", function()
        local LK = require("lib/loomlinks")
        local d = L.empty()
        local a, b, c, e = win(d, "0xa", 1), win(d, "0xb", 1), win(d, "0xc", 2), win(d, "0xe", 1)
        LK.link(d, a, c, "association"); LK.link(d, a, b, "workflow"); LK.link(d, e, a, "dependency")
        local t = LK.targets(d, a); eq(t[1], b, "the workflow's next first"); eq(t[2], c); eq(#t, 3)
        eq(LK.next_target(d, a, b), c); eq(LK.next_target(d, a, e), b, "round")
        local back = LK.targets(d, b); eq(back[1], a, "a workflow walked backwards is still a way back")
        eq(LK.dependants(d, a)[1], e, "e → a: e depends on a")
        eq(#LK.dependants(d, e), 0, "and not the other way round")
        -- a fold: b parks; its links are by id, untouched
        local CB = require("lib/loomcube")
        local sid = CB.create(d, { b }, b); CB.commit(d, sid, CB.fold(d, sid), 1)
        eq(LK.targets(d, a)[1], b, "links survive folding")
        eq(LK.unlink_all(d, a) >= 3, true); eq(#LK.targets(d, a), 0)
    end)
    test("D200 loom: threads on the workspace — a curve that sags, an arrow, a stub toward the edge", function()
        local LK = require("lib/loomlinks")
        local d = L.empty()
        local a = win(d, "0xa", 1, { at = { 100, 100, 200, 100 } })
        local b = win(d, "0xb", 1, { at = { 700, 300, 200, 100 } })
        local c = win(d, "0xc", 2, { at = { 0, 0, 300, 300 }, app = "firefox" })
        LK.link(d, a, b, "workflow"); LK.link(d, a, c, "association")
        local th = LK.threads(d, 1, 1920, 1080, 0, 0, a)
        eq(#th, 2)
        eq(th[1].x1, 200); eq(th[1].y1, 150); eq(th[1].x2, 800); eq(th[1].y2, 350)
        assert(th[1].cy > (150 + 350) / 2, "it sags"); eq(th[1].directed, true); eq(th[1].lit, true)
        eq(th[2].stub, true); eq(th[2].label, "F"); eq(th[2].y2, 18, "to the nearest edge (the top)"); eq(th[2].x2, 200)
        eq(#LK.threads(d, 3, 1920, 1080), 0, "nothing on a workspace with neither end")
    end)
    test("D200: links in two presses, a hop that brings a parked window out, threads drawn and click-through", function()
        local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
        local lua = read("shell/mooi-loom.luau")
        assert(lua:find("if not thr.pick then thr.pick = oid; threads_publish(); return end", 1, true), "the first press marks")
        assert(lua:find("if thr.pick == oid then thr.pick = nil; threads_publish(); return end", 1, true), "the same window lets go")
        assert(lua:find('if o.state == "parked" then', 1, true) and lua:find('hypr.dispatch("focus", o.address)', 1, true), "a hop unparks, then focuses")
        assert(lua:find('pcall(sys.watch, "window", function() threads_look(false) end)', 1, true), "the threads follow the focus")
        local plm = read("shell/mooi-loom.plm")
        assert(plm:find("surface threads {", 1, true) and plm:find("open: lf_thr_f > 0.01", 1, true), "their own surface, open only while shown")
        local i = plm:find("surface threads {", 1, true); local j = plm:find("surface loom {", 1, true)
        assert(not plm:sub(i, j):find("zone ", 1, true), "no zones: every press goes through")
        local C = require("lib/config").defaults()
        eq(C.keys.loom_link, "SUPER + ALT + N"); eq(C.keys.loom_hop, "SUPER + ALT + H"); eq(C.loom.threads, "relevant")
    end)
    test("strays: a window on a Loom park the document does not know is still brought out", function()
        local st = LP.stray({ { address = "0xd1", workspace = { name = "special:loom-s4" } },
                              { address = "0xd2", workspace = { name = "special:scratch" } },
                              { address = "0xd3", workspace = { name = "2" } } })
        eq(#st, 1); eq(st[1].structure, "s4")
        local cmds = LP.rescue(st, 6)
        assert(cmds[1]:find("workspace = 6, follow = false", 1, true))
    end)
end

section("the morph (D204)")
do
    local PM = require("lib/pillmorph")
    local chassis = require("lib/chassis")
    local function near(a, b, what) if math.abs(a - b) > 0.01 then error(string.format("%s: expected %s, got %s", what, b, a), 2) end end
    -- the outline the B-spline draws: the midpoints of consecutive points are on it
    local function curve_pts(pts)
        local out = {}
        for _, st in ipairs(PM.steps(pts)) do out[#out + 1] = st[2] end
        return out
    end
    test("the capsule: twelve points, its curve runs straight along the top and the foot, round ends of radius r", function()
        local o = PM.points("capsule", 100, 10, 200, 24, 12)
        eq(#o.pts, 12); eq(o.ripple, 0)
        local c = curve_pts(o.pts)
        -- the first curve ends at (x + r, y): the top's straight starts one radius in
        near(c[2][1], 112, "top starts at x + r"); near(c[2][2], 10, "on the top")
        -- the end of the top's run is one radius from the right
        near(c[6][1], 288, "top ends at x + w - r")
        -- the right end's middle: (x + w, y + h / 2)
        near(c[7][1], 300, "the right end's middle x"); near(c[7][2], 22, "the right end's middle y")
        for i = 8, 12 do near(c[i][2], 34, "the foot runs straight") end
        near(c[13][1], 100, "the left end's middle"); near(c[13][2], 22, "half way down")
        eq(#PM.steps(o.pts), 13, "a move and twelve curves")
    end)
    test("a disc when it is as wide as it is high; the corner radius never exceeds half of either", function()
        local o = PM.points("capsule", 0, 0, 24, 24, 50)
        local c = curve_pts(o.pts)
        near(c[1][1], 0, "left middle x"); near(c[1][2], 12, "left middle y")
        near(c[2][1], 12, "top middle"); near(c[2][2], 0, "the top")
        for _, p in ipairs(o.pts) do assert(p[1] >= 0 and p[1] <= 24 and p[2] >= 0 and p[2] <= 24, "inside its box") end
    end)
    test("the forms: blob ripples, drop hangs a bead, bead is the dot's size, none gathers at the centre", function()
        local b = PM.points("blob", 100, 10, 200, 24, 12)
        eq(b.ripple, PM.RIPPLE); eq(PM.RIPPLE, 0, "still since the live measure"); assert(b.pts[9][2] >= 34 + PM.SWELL and b.pts[10][2] >= 34 + PM.SWELL, "fuller at the foot")
        local d = PM.points("drop", 100, 10, 200, 24, 12)
        assert(d.pts[9][2] > 34 + 10 and d.pts[10][2] > 34 + 10, "the bead hangs")
        near((d.pts[9][1] + d.pts[10][1]) / 2, 200, "under the middle")
        near(d.pts[8][2], 34, "its neighbours stay on the foot"); near(d.pts[11][2], 34, "both")
        local e = PM.points("bead", 100, 10, 200, 24, 12)
        local minx, maxx = 1e9, -1e9
        for _, p in ipairs(e.pts) do minx = math.min(minx, p[1]); maxx = math.max(maxx, p[1]) end
        near(maxx - minx, PM.BEAD, "the bead is as wide as the dot"); near((minx + maxx) / 2, 200, "where the Pill rests")
        local n = PM.points("none", 100, 10, 200, 24, 12)
        for _, p in ipairs(n.pts) do near(p[1], 200, "x at the centre"); near(p[2], 22, "y in the module's middle") end
        local z = PM.points("capsule", 100, 10, 0, 24, 12)
        for _, p in ipairs(z.pts) do near(p[1], 100, "a vanished Pill gathers where it was") end
        local off = PM.points("none", nil, nil, nil, nil, nil)
        eq(off.pts[1][1], PM.OFF, "no box: off the strip")
    end)
    test("the form follows the state; reduced motion and an open board keep the capsule", function()
        eq(PM.form({ main = "idle" }), "capsule")
        eq(PM.form({ main = "music" }), "blob")
        eq(PM.form({ main = "notify" }), "drop")
        eq(PM.form({ main = "osd" }), "capsule")
        eq(PM.form({ main = "idle", hidden = true }), "bead")
        eq(PM.form({ main = "idle", hidden = true, vanish = true }), "none")
        eq(PM.form({ main = "music" }, { still = true }), "capsule", "still: no blob")
        eq(PM.form({ main = "notify" }, { board = true }), "capsule", "the board unfolds from a capsule")
        eq(PM.form({ main = "idle", hidden = true }, { still = true }), "bead", "a size, not a motion")
        eq(PM.form(nil), "capsule")
    end)
    test("the chassis: a morph Pill is an outline, not a box; joined to the band with it, floating without", function()
        local L = chassis.look(require("lib/config").defaults())
        L.mode = "pill"; L.band = false; L.top = 6; L.mod_h = 24
        local geo = { islands = {}, pill = { x = 900, w = 160, shape = "morph", form = "blob" }, moons = {} }
        eq(#chassis.pieces(geo, L), 0, "no box for the Pill")
        local m = chassis.morph(geo, L)
        eq(m.form, "blob"); eq(m.x, 900); eq(m.w, 160); eq(m.y, 6); eq(m.h, 24); eq(m.k, 0)
        L.band = true
        local j = chassis.morph(geo, L)
        eq(j.y, -40, "hangs from above the screen, as the attached capsule does"); eq(j.k, 8, "melted into the band")
        geo.pill.w = 0
        eq(chassis.morph(geo, L).form, "none", "no width: nothing drawn")
        geo.pill.shape = "attached"
        eq(chassis.morph(geo, L), nil, "any other shape: no outline")
    end)
    test("config, settings and the scenes know the morph", function()
        local s, p = require("lib/config").validate({ pill = { shape = "morph" } })
        eq(#p, 0); eq(s.pill.shape, "morph")
        local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
        local bar = read("shell/bar.luau")
        assert(bar:find("dot = 2, morph = 3 }", 1, true), "the scene's pill_shape")
        assert(bar:find("form = pill_now and pill_now.form", 1, true), "the frame is told the form")
        local fr = read("shell/mooi-frame.plm")
        assert(fr:find("spring fr.ooze = 260, 20", 1, true) and fr:find("follow mx11 = mtx11", 1, true), "sprung points")
        assert(fr:find("path { blend: mk; show: m_on", 1, true), "the outline melts into the band")
        assert(not fr:find("path { show: band_on; blend: mk", 1, true), "and stays with the band off")
        local fl = read("shell/mooi-frame.luau")
        assert(fl:find("fact.mrip = (not still) and out.ripple or 0", 1, true), "no ripple in reduced motion")
        assert(read("shell/mooi-settings.plm"):find('"Morph", 3', 1, true), "a fourth shape in Settings")
    end)
end

section("more pills (D205)")
do
    local P = require("lib/pill")
    local chassis = require("lib/chassis")
    local function overlaps(a, b) return a.x < b.x + b.w and b.x < a.x + a.w end
    local SIDES = { { x = 20, w = 300 }, { x = 860, w = 200 }, { x = 1600, w = 300 } }
    test("automatic: the second in the gap left of the centre Pill, the third in the gap right", function()
        local x2, w2 = P.place_extra(1920, 160, 0, "left", SIDES)
        local x3, w3 = P.place_extra(1920, 160, 0, "right", SIDES)
        eq(w2, 160); eq(w3, 160)
        assert(x2 + w2 / 2 < 860 and x2 > 320, "left of the Pill, right of the left group")
        assert(x3 > 1060 and x3 + w3 < 1600, "right of the Pill, left of the right group")
    end)
    test("a place across the screen is clamped: never off it, never over anything, the nearest free spot", function()
        local x, w = P.place_extra(1920, 160, 100, "left", {})
        eq(x + w, 1920 - P.EDGE, "the right edge, less its air")
        local cx, cw = P.place_extra(1920, 160, 50, "left", { { x = 860, w = 200 } })
        assert(not overlaps({ x = cx, w = cw }, { x = 860 - P.EXTRA_GAP, w = 200 + 2 * P.EXTRA_GAP }), "beside the Pill, not on it")
        local x0 = P.place_extra(1920, 160, 1, "left", {})
        eq(x0, P.EDGE, "the left edge")
    end)
    test("no room at its width: its icon's; no room at all: not shown", function()
        local tight = { { x = 0, w = 900 }, { x = 990, w = 930 } }   -- a 90 px gap, 66 free after the air
        local x, w = P.place_extra(1920, 160, 0, "left", tight)
        eq(w, P.EXTRA_MIN, "shrunk to its icon"); assert(x >= 912 and x + w <= 978, "inside the gap")
        local _, none = P.place_extra(1920, 160, 0, "left", { { x = 0, w = 1920 } })
        eq(none, 0, "nowhere: hidden, never 0-wide while shown")
    end)
    test("two pills asking for the same place do not overlap", function()
        local taken = { { x = 860, w = 200 } }
        local ax, aw = P.place_extra(1920, 160, 30, "left", taken)
        taken[#taken + 1] = { x = ax, w = aw }
        local bx, bw = P.place_extra(1920, 160, 30, "right", taken)
        assert(bw > 0 and not overlaps({ x = ax, w = aw }, { x = bx, w = bw }), "side by side")
    end)
    test("a face's width is the centre Pill's measure of it", function()
        eq(P.face_width("weather", "brief"), P.FACE_W.weather)
        eq(P.face_width("weather", "icon"), 44)
        eq(P.face_width("media", "full"), P.FACE_W_FULL.media)
        eq(P.face_width("time", "brief"), P.FACE_W.time)
    end)
    test("settings: off by default, every face, a place 0–100; the chassis draws a capsule for each", function()
        local C = require("lib/config")
        local d = C.defaults()
        eq(d.pill.two, "off"); eq(d.pill.three, "off"); eq(d.pill.two_at, 0)
        local s, p = C.validate({ pill = { two = "weather", two_at = 30, three = "battery" } })
        eq(#p, 0); eq(s.pill.two, "weather"); eq(s.pill.two_at, 30)
        local _, bad = C.validate({ pill = { two = "kettle", three_at = 140 } })
        eq(#bad, 2, "an unknown face and a place past the screen are refused")
        local seen = {}
        for _, path in ipairs(require("lib/setters").SETTERS) do seen[path] = true end
        assert(seen["pill.two"] and seen["pill.two_at"] and seen["pill.three"] and seen["pill.three_at"])
        local L = chassis.look(C.defaults()); L.mode = "pill"; L.band = false; L.top = 6; L.mod_h = 24
        local pcs = chassis.pieces({ islands = {}, pill = { x = 900, w = 160, shape = "attached" }, moons = {},
                                     pills = { { x = 500, w = 120 }, { x = 1300, w = 0 } } }, L)
        eq(#pcs, 2, "the centre Pill and one extra (a 0-wide one is not drawn)")
        eq(pcs[2].x, 500); eq(pcs[2].w, 120); eq(pcs[2].r, 12)
    end)
    test("the scene: one face component for every pill, a zone and a wheel each", function()
        local function read(path) local f = io.open(path); local t = f:read("a"); f:close(); return t end
        local ui = read("shell/ui/pill.plm")
        local _, faces = ui:gsub("component ModuleFace%(", "")
        eq(faces, 1, "one module-face tree")
        assert(ui:find("ModuleFace(px, pw, cy, pill_face, pill_detail)", 1, true), "the centre Pill uses it")
        assert(ui:find("ModuleFace(px, pw, cy, face, pill_detail)", 1, true), "and the extras")
        assert(ui:find("on press xz { emit pill_xpress(k) }", 1, true))
        local plm = read("shell/mooi.plm")
        assert(plm:find("ExtraPill(2, pill2_on, pill2_x, pill2_w, pill2_face)", 1, true) and plm:find("ExtraPill(3,", 1, true))
        local bar = read("shell/bar.luau")
        assert(bar:find("pillmod.place_extra(env.screen", 1, true), "placed by the pure function")
        assert(read("shell/pillboard.luau"):find("face_press = face_press", 1, true), "a press opens its room")
    end)
end

section("the launcher's restarts (D206)")
test("a motion change restarts the bar the way refresh does: the keeper's mark first", function()
    local f = io.open("bin/mooi"); local sh = f:read("a"); f:close()
    local i = sh:find('if [ -n "$m" ] && [ "$m" != "$motion_seen" ]; then', 1, true)
    assert(i, "the motion watch")
    local block = sh:sub(i, i + 700)
    local mark, kill = block:find(': > "$again"', 1, true), block:find('kill -TERM', 1, true)
    assert(mark and kill and mark < kill, "the again mark is written before the scenes are ended")
end)

section("the sigil: settings (D207)")
test("sigil settings: defaults leave the classic Pill", function()
    local d = config.defaults()
    eq(d.sigil.pill, "classic"); eq(d.sigil.temperament, "lively"); eq(d.sigil.colour, "follow")
    eq(d.sigil.fixed, "#d6e38a"); eq(d.sigil.field, true); eq(d.sigil.pointer, "push"); eq(d.sigil.rest, "clock")
end)
test("sigil settings: bad values fall back, good ones stand", function()
    local s, p = config.validate({ sigil = { pill = "sigil", temperament = "manic", rest = "kettle" } })
    eq(s.sigil.pill, "sigil"); eq(s.sigil.temperament, "lively"); eq(s.sigil.rest, "clock"); eq(#p, 2)
end)
test("sigil settings: setters appended, the module placeable", function()
    local S = require("lib/setters").SETTERS
    local at = {}; for i, v in ipairs(S) do at[v] = i end
    assert(at["sigil.rest"] and at["sigil.rest"] - at["sigil.pill"] == 6, "the seven sigil setters, appended together")
    local bl = require("lib/barlayout")
    eq(bl.ORDER[#bl.ORDER - 2], "sigil"); eq(bl.ORDER[#bl.ORDER - 1], "bmo"); eq(bl.ORDER[#bl.ORDER], "herdr")
    eq(bl.width("sigil", { screen = 1920 }), 180)
end)
test("sigil settings: the page has its fold", function()
    local f = io.open("shell/mooi-settings.plm"); local t = f:read("a"); f:close()
    assert(t:find('"The Sigil"', 1, true), "fold title")
    assert(t:find("sv_sigil_pill", 1, true) and t:find("sv_sigil_temperament", 1, true))
end)

section("the settings window")
test("settings window declares a row for every bar module", function()
    local bl = require("lib/barlayout")
    local f = io.open("shell/mooi-settings.plm"); local plm = f:read("a"); f:close()
    for _, id in ipairs(bl.ORDER) do
        for _, prefix in ipairs({ "m_", "fi_", "g_" }) do
            assert(plm:find("fact " .. prefix .. id .. " ", 1, true),
                "the settings scene declares " .. prefix .. id)
        end
    end
end)

section("the sigil: shapes")
do
    local SH = require("lib/surface/shapes")
    test("shapes: every kind, every form, 64 points inside its box", function()
        for _, k in ipairs(SH.KINDS) do
            for _, form in ipairs({ "glyph", "compact", "display" }) do
                local b = form == "display" and { x = 660, y = 40, w = 600, h = 220 } or { x = 900, y = 4, w = 180, h = 24 }
                local p = SH.outline(k, b, form, 0, { values = { .2, .9, .1 }, n = 5, active = 2 })
                eq(#p, 64, k .. " " .. form)
                for _, q in ipairs(p) do
                    assert(q[1] >= b.x - 0.5 and q[1] <= b.x + b.w + 0.5 and q[2] >= b.y - 0.5 and q[2] <= b.y + b.h + 0.5, k .. " " .. form .. " outside its box")
                end
            end
        end
    end)
    test("shapes: every kind stays inside a 60 x 24 box", function()
        for _, k in ipairs(SH.KINDS) do
            for _, q in ipairs(SH.outline(k, { x = 0, y = 0, w = 60, h = 24 }, "compact", 0, {})) do
                assert(q[1] >= -0.5 and q[1] <= 60.5 and q[2] >= -0.5 and q[2] <= 24.5, k)
            end
        end
    end)
    test("shapes: the disc starts at its bottom, so the line rolls out of it", function()
        local p = SH.outline("disc", { x = 0, y = 0, w = 600, h = 220 }, "display", 0, {})
        assert(p[1][2] > p[17][2], "the first point is the disc's lowest")
        assert(p[64][1] > 400, "the line runs out to the right")
    end)
    test("shapes: front-first batches cover 1..64 in order", function()
        local b = SH.batches(nil, nil, 4)
        eq(#b, 4); eq(b[1][1], 1); eq(b[4][2], 64); eq(b[2][1], b[1][2] + 1)
    end)
    test("shapes: an unknown kind is the clock, never an error", function()
        eq(#SH.outline("kettle", { x = 0, y = 0, w = 100, h = 24 }, "compact"), 64)
    end)
end

section("the sigil: sources")
do
    local SRC = require("lib/surface/sources")
    local BL = require("lib/barlayout")
    test("sources: wave 1 complete, each with glyph, display, compact, press and a group", function()
        for _, id in ipairs(SRC.WAVE1) do
            local e = SRC.get(id); assert(e, id)
            assert(e.glyph and e.display and e.compact and e.press and e.group, id)
        end
    end)
    test("sources: every bar module is in wave 1, later, or explicitly not a source", function()
        local skip = { tray = true, keyboard = true, bandwidth = true, caffeine = true, actions = true, core = true,
                       focus = true, updates = true, claude = true, github = true, brightness = true, sigil = true,
                       bmo = true, herdr = true }
        local later = " " .. table.concat(SRC.LATER, " ") .. " "
        for _, m in ipairs(BL.ORDER) do
            local s = SRC.for_module(m)
            assert(skip[m] or (s and (SRC.get(s) or later:find(" " .. s .. " ", 1, true))), m)
        end
    end)
    test("sources: compact of a missing reading is a dash", function()
        for _, id in ipairs(SRC.WAVE1) do eq(SRC.get(id).compact(nil).t1, "—", id) end
    end)
    test("sources: compact readings", function()
        eq(SRC.get("volume").compact({ volume = 0.62 }).t1, "62%")
        eq(SRC.get("battery").compact({ percent = 82, charging = false }).t1, "82%")
        eq(SRC.get("music").compact({ title = "Renegade", artist = "(Hed) P.E." }).t1, "Renegade")
    end)
    test("sources: indexes are stable and 1-based", function()
        eq(SRC.index("clock"), 1); eq(SRC.index("bmo"), #SRC.WAVE1); eq(SRC.index("kettle"), nil)
    end)
    test("sources: sigil.rest's choices are exactly wave 1 (pre-flight ruling)", function()
        local row
        for _, r in ipairs(require("lib/config").SCHEMA) do if r.path == "sigil.rest" then row = r end end
        eq(table.concat(row.values, ","), table.concat(SRC.WAVE1, ","))
    end)
end

section("the sigil: palette")
do
    local PAL = require("lib/surface/palette")
    local base = { colours = { primary = "#fbba73", error = "#ffb4ab" } }
    local follow = { sigil = { colour = "follow" } }
    test("palette: base is the wallpaper's primary", function() local c = PAL.resolve("clock", { palette = base, settings = follow }); eq(c[1], 0xfb); eq(c[3], 0x73) end)
    test("palette: music takes the cover", function() local c = PAL.resolve("music", { palette = base, cover = { "#ec78aa" }, settings = follow }); eq(c[1], 0xec) end)
    test("palette: the cover is only music's", function() local c = PAL.resolve("clock", { palette = base, cover = { "#ec78aa" }, settings = follow }); eq(c[1], 0xfb) end)
    test("palette: an event beats the cover", function() local c = PAL.resolve("music", { palette = base, cover = { "#ec78aa" }, event = "warning", settings = follow }); eq(c[1], 0xe3) end)
    test("palette: an error is the palette's error", function() local c = PAL.resolve("clock", { palette = base, event = "error", settings = follow }); eq(c[1], 0xff); eq(c[2], 0xb4) end)
    test("palette: fixed beats everything", function() local c = PAL.resolve("music", { palette = base, event = "error", settings = { sigil = { colour = "fixed", fixed = "#102030" } } }); eq(c[1], 0x10) end)
    test("palette: no palette at all is the phosphor", function() local c = PAL.resolve("clock", { settings = follow }); eq(c[1], 0xd6) end)
    test("palette: easing moves part of the way", function() local c = PAL.ease({ 0, 0, 0 }, { 100, 200, 50 }, 0.5); eq(c[1], 50); eq(c[2], 100) end)
end
section("the sigil: bodies")
do
    local BOD = require("lib/surface/bodies")
    test("bodies: temperaments, and reduced motion stills them", function()
        eq(BOD.temperament("calm", false).wobble, 1); eq(BOD.temperament("restless", false).batches, 6)
        local r = BOD.temperament("restless", true); eq(r.wobble, 0); eq(r.breath, 0); eq(r.batches, 1); eq(r.lag_ms, 0)
        eq(BOD.temperament("kettle", false).wobble, 2.5, "unknown is lively")
        eq(BOD.pointer("push"), 1.6); eq(BOD.pointer("draw"), -1.0); eq(BOD.pointer("x"), 0)
    end)
end

section("the sigil: director")
do
    local DIR = require("lib/surface/director")
    local H = { { id = "pill", kind = "pill", rest = "clock", h = 24 }, { id = "isl1", kind = "island", rest = "clock", h = 24 } }
    test("director: nothing happening, each host rests", function()
        local r = DIR.choose(H, { feed_at = 0 }, 1000)
        eq(r.pill.source, "clock"); eq(r.pill.form, "compact"); assert(r.isl1.source ~= "clock", "a different one")
    end)
    test("director: music leads in the Pill", function() eq(DIR.choose(H, { music = { playing = true, title = "x" }, feed_at = 0 }, 1000).pill.source, "music") end)
    test("director: a fresh notice beats music, then music moves to the island", function()
        local r = DIR.choose(H, { music = { playing = true, title = "x" }, notice = { at = 900 }, feed_at = 0 }, 1000)
        eq(r.pill.source, "notifications"); eq(r.pill.event, "notable"); eq(r.isl1.source, "music")
    end)
    test("director: an old notice is over", function() eq(DIR.choose(H, { notice = { at = 0 }, feed_at = 0 }, 7000).pill.source, "clock") end)
    test("director: two hosts never share a source", function()
        local r = DIR.choose(H, { feed_at = 0 }, 1000); assert(r.pill.source ~= r.isl1.source)
    end)
    test("director: low battery is a warning; charging is not", function()
        local r = DIR.choose(H, { battery = { percent = 9, charging = false }, feed_at = 0 }, 1000)
        eq(r.pill.source, "battery"); eq(r.pill.event, "warning")
        eq(DIR.choose(H, { battery = { percent = 9, charging = true }, feed_at = 0 }, 1000).pill.source, "clock")
    end)
    test("director: a volume change shows for two seconds", function()
        eq(DIR.choose(H, { volume_at = 500, feed_at = 0 }, 1000).pill.source, "volume")
        eq(DIR.choose(H, { volume_at = 500, feed_at = 0 }, 3000).pill.source, "clock")
    end)
    test("director: hovered Pill shows its display; an island never does", function()
        eq(DIR.choose(H, { hover = { pill = true }, feed_at = 0 }, 1000).pill.form, "display")
        eq(DIR.choose(H, { hover = { isl1 = true }, feed_at = 0 }, 1000).isl1.form, "compact")
    end)
    test("director: a short host shows the glyph (box height, pre-flight ruling)", function()
        eq(DIR.choose({ { id = "isl1", kind = "island", rest = "clock", box = { h = 14 } } }, { feed_at = 0 }, 0).isl1.form, "glyph")
    end)
    test("director: stale feed sources are skipped", function()
        local r = DIR.choose({ { id = "pill", kind = "pill", rest = "weather", h = 24 } }, { feed_at = 0 }, 60000)
        assert(r.pill.source ~= "weather")
    end)
    test("director: no hosts, no choices", function() eq(next(DIR.choose({}, { feed_at = 0 }, 0)), nil) end)
end

section("the sigil: hosts")
do
    local HO = require("lib/surface/hosts")
    local cfg = function(pill, mode) local d = config.defaults(); d.sigil.pill = pill; d.bar.mode = mode; return d end
    local LOOK = { top = 6, mod_h = 24 }
    test("hosts: classic mode and no module, no hosts", function() eq(#HO.build(cfg("classic", "pill"), { x = {} }, { x = 870, w = 180 }, LOOK, 1920), 0) end)
    test("hosts: sigil in the Pill", function()
        local h = HO.build(cfg("sigil", "pill"), { x = {} }, { x = 870, w = 180 }, LOOK, 1920)
        eq(#h, 1); eq(h[1].id, "pill"); eq(h[1].kind, "pill"); eq(h[1].box.x, 870); eq(h[1].box.y, 6); eq(h[1].box.h, 24)
        eq(h[1].room, 240); eq(h[1].max_form, "display"); eq(h[1].rest, "clock")
    end)
    test("hosts: sigil chosen but the bar is not in Pill mode, no Pill host", function()
        eq(#HO.build(cfg("sigil", "islands"), { x = {} }, nil, LOOK, 1920), 0)
    end)
    test("hosts: an island module, at its place", function()
        local h = HO.build(cfg("classic", "islands"), { x = { sigil = 400 } }, nil, LOOK, 1920)
        eq(#h, 1); eq(h[1].id, "isl1"); eq(h[1].kind, "island"); eq(h[1].box.x, 400); eq(h[1].box.w, 180); eq(h[1].room, 0); eq(h[1].max_form, "compact")
    end)
    test("hosts: the Pill and an island together, the Pill first, never more than four", function()
        local h = HO.build(cfg("sigil", "pill"), { x = { sigil = 100 } }, { x = 870, w = 180 }, LOOK, 1920)
        assert(#h <= 4); eq(#h, 2); eq(h[1].id, "pill"); eq(h[2].id, "isl1")
    end)
    test("hosts: the bar writes them, and the feed, and turns the classic Pill off in sigil mode", function()
        local f = io.open("shell/bar.luau"); local b = f:read("a"); f:close()
        assert(b:find('"sigil-hosts.json"', 1, true) and b:find('"sigil-feed.json"', 1, true))
        assert(b:find("sigilhosts.build(", 1, true), "built by the pure function")
        assert(b:find("sig.classic_off", 1, true), "the classic Pill steps aside")
    end)
end

section("the sigil: running")
test("mooi: sigil respawn gives up after five and the bar falls back", function()
    local function read(p) local f = io.open(p); local t = f:read("a"); f:close(); return t end
    local m = read("shell/mooi.luau")
    assert(m:find("function surface_sync()", 1, true), "spawned like the frame")
    assert(m:find('on("surface_ready"', 1, true), "it says when it is up")
    assert(m:find("surface · gave up after five quick ends", 1, true))
    assert(read("bin/mooi"):find("mooi-surface.plm:Surface", 1, true), "compiled with the others")
    -- found live: without the link it read its files from an empty folder of its own and drew nothing
    assert(read("bin/mooi"):match("for prog in [^\n]*mooi%-surface"), "shares mooi's data folder")
    assert(read("shell/ui/pill.plm"):find("sigil_mode and not surface_up", 1, true), "the plain clock")
    -- found live: an undeclared event from another program is dropped, so surface_up never came on
    assert(read("shell/mooi.plm"):find("event surface_ready ->", 1, true), "the bar hears that it is up")
end)

section("the sigil: scene")
test("scene: generated, four hosts, 64 sprung points each, two surfaces", function()
    local f = io.open("shell/mooi-surface.plm"); local t = f:read("a"); f:close()
    assert(t:find("follow h3_x63 = h3_tx63", 1, true), "the last host's last point follows its target")
    assert(t:find("spring sg.pt = 260, 20", 1, true))
    assert(t:find("surface bar {", 1, true) and t:find("surface drop {", 1, true))
    assert(t:find("rate: 60, 20 while calm", 1, true), "it rests")
    assert(not t:find("notification", 1, true), "it never watches notifications (spec §3)")
end)

test("scene: the display stands on a plate, not over the windows", function()
    local f = io.open("shell/mooi-surface.plm"); local t = f:read("a"); f:close()
    assert(t:find("// the display's plate", 1, true) and t:find("fact pl_r", 1, true))
end)
section("the sigil: logic")
test("logic: requires the five modules, reads the feeds, never the notification service", function()
    local f = io.open("shell/mooi-surface.luau"); local t = f:read("a"); f:close()
    for _, m in ipairs({ "lib/surface/sources", "lib/surface/shapes", "lib/surface/director", "lib/surface/palette", "lib/surface/bodies" }) do
        assert(t:find('require("' .. m .. '")', 1, true), m)
    end
    assert(t:find("sigil-hosts.json", 1, true) and t:find("nexus-feed.json", 1, true))
    assert(not t:find('sys.watch("notification', 1, true))
    assert(t:find('"emit surface_ready"', 1, true))
end)
test("logic: the display's layout keeps its words beside the line, inside the box", function()
    package.loaded["lib/surface/layout"] = nil
    local LY = require("lib/surface/layout")
    local D = LY.display_box({ x = 870, y = 6, w = 180, h = 24 }, 1920)
    eq(D.w, 600); eq(D.h, 220); eq(D.x, 660); eq(D.y, 40)
    local edge = LY.display_box({ x = 1800, y = 6, w = 180, h = 24 }, 1920)
    eq(edge.x, 1920 - 608, "never past the screen's edge")
    for _, kind in ipairs(require("lib/surface/shapes").KINDS) do
        local line, tx, ty = LY.display(kind, D)
        assert(line.x >= D.x and line.x + line.w <= D.x + D.w, kind .. " line in the box")
        assert(tx >= D.x and tx < D.x + D.w and ty >= D.y and ty < D.y + D.h, kind .. " words in the box")
    end
    local c = LY.compact({ x = 400, y = 6, w = 180, h = 24 })
    assert(c.x >= 400 and c.x + c.w <= 400 + 180 * 0.42, "the compact line keeps left of its words")
    -- found live: a round glyph squeezed into the wide compact box read as a blob — round kinds get a square
    for _, k in ipairs({ "clock", "disc", "ring", "face", "dots" }) do
        local q = LY.compact({ x = 400, y = 6, w = 180, h = 24 }, k); eq(q.w, q.h, k .. " is square")
    end
    eq(LY.compact({ x = 400, y = 6, w = 180, h = 24 }, "ribbon").w > 24, true, "a long kind keeps its width")
    -- the clock's hands tell the real time: 15:00 points the hour hand right (0 rad), 18:00 down (pi/2)
    eq(LY.clock_angle(15, 0), 0); assert(math.abs(LY.clock_angle(18, 0) - math.pi / 2) < 1e-9)
end)

section("the sigil: review fixes")
do
    local function read(p) local f = io.open(p); local t = f:read("a"); f:close(); return t end
    test("review I1: mooi runs the Sigil only when the bar placed a host (sigil-hosts.json), and an empty scene rests", function()
        local m = read("shell/mooi.luau")
        assert(m:find('"sigil-hosts.json"', 1, true), "wanted() reads the bar's own hosts")
        assert(m:find('sys.watch, "files:sigil-hosts.json"', 1, true), "and follows them")
        local plm = read("shell/mooi-surface.plm")
        assert(plm:find("open: h0_on or h1_on or h2_on or h3_on", 1, true), "no host, no surface")
        assert(plm:find("spin ph by if((h0_on or h1_on or h2_on or h3_on) and", 1, true), "no host, nothing turns")
    end)
    test("review I2: the bar fetches weather and resources while the Sigil has a host, and sends nothing unfetched", function()
        local b = read("shell/bar.luau")
        assert(b:find("if placed.resources or need.resources or sig.n > 0 then", 1, true))
        assert(b:find("if placed.weather or need.weather or sig.n > 0 then", 1, true))
        assert(b:find("weather = fact.wx_ok and {", 1, true), "no weather before it is fetched")
        assert(b:find("resources = sig.res_ok and {", 1, true), "no resources before they are read")
    end)
    test("review I3: the first notice after a clean start takes the Pill", function()
        local DIR = require("lib/surface/director")
        local seen, n = DIR.notice_step(nil, nil, 0)
        eq(seen, 0, "an empty feed still sets the mark"); eq(n, nil)
        seen, n = DIR.notice_step(seen, 1794072791, 5000)
        eq(seen, 1794072791); assert(n and n.at == 5000, "the first notice of the day is fresh")
        local s2, n2 = DIR.notice_step(1794072791, 1794072791, 9000)
        eq(s2, 1794072791); eq(n2, nil, "the same notice again is not")
        local s3, n3 = DIR.notice_step(nil, 1794072791, 0)
        eq(s3, 1794072791); eq(n3, nil, "the feed's first read only sets the mark")
    end)
    test("review I4: the Sigil island can be moved in edit mode like any module", function()
        local plm = read("shell/mooi.plm")
        assert(plm:find("zone box ez_sigil", 1, true), "its edit zone")
        assert(plm:find("on press ez_sigil while bar_edit { ed_press = 32", 1, true), "code 32 (its place in barlayout.ORDER)")
        assert(plm:find("follow xs_sigil = x_sigil", 1, true) and plm:find("follow ws_sigil = w_sigil", 1, true))
    end)
end

section("surface: reveal (D208)")
do
    local RV = require("lib/surface/reveal")
    local P = { x = 800, y = 500 }
    test("reveal: a tap is a tap, a hold opens in stages", function()
        local st = RV.state()
        RV.down(st, 0); RV.tick(st, 100, P)
        eq(st.stage, 0, "not yet"); eq(RV.up(st, 120), "tap")
        st = RV.state(); RV.down(st, 0)
        RV.tick(st, RV.DELAY + 10, P); eq(st.stage, 1, "the touch")
        RV.tick(st, RV.DELAY + RV.OPEN_MS + 10, P); eq(st.stage, 2, "open")
        eq(RV.up(st, 2000), "release")
    end)
    test("reveal: two stages, no ring", function()
        local st = RV.state(); RV.down(st, 0)
        RV.tick(st, RV.DELAY + 10, P)
        RV.tick(st, RV.DELAY + RV.OPEN_MS + 500, P)
        eq(st.stage, 2, "open, and no further stage")
        eq(RV.pick, nil, "no picking"); eq(RV.GROUPS, nil, "no groups")
        eq(RV.release, nil, "no release outcomes"); eq(RV.groups, nil, "no group list")
    end)
    test("reveal: firm only after it has been open and the pointer moved", function()
        local st = RV.state(); RV.down(st, 0)
        RV.tick(st, RV.DELAY + 10, P)
        local t0 = RV.DELAY + RV.OPEN_MS + 10
        RV.tick(st, t0, P)
        RV.tick(st, t0 + 400, P)
        eq(RV.firm(st), false, "open 400 ms but the pointer is still")
        RV.tick(st, t0 + 450, { x = P.x + 30, y = P.y })
        eq(RV.firm(st), true, "open long enough and the pointer moved 30 px")
        RV.down(st, 5000)
        eq(RV.firm(st), false, "a fresh down starts over")
        local fresh = RV.state(); RV.down(fresh, 0)
        RV.tick(fresh, 10, P); RV.tick(fresh, t0, { x = P.x + 30, y = P.y })
        eq(RV.firm(fresh), false, "moved, but not yet open for 300 ms")
    end)
    test("reveal: a reveal never outlives its safeguards", function()
        for _, e in ipairs({ "workspace", "focus", "escape", "outside", "idle" }) do eq(RV.close_on(e), true, e) end
        eq(RV.close_on("pointer"), false)
        local st = RV.state(); RV.down(st, 0); RV.tick(st, 1000, P)
        RV.tick(st, 1000 + RV.IDLE_MS + 10, P)
        eq(st.stage, 0, "idle with the pointer still: it closes itself")
    end)
end

section("surface: opening (D209)")
do
    local OP = require("lib/surface/opening")
    local A = { id = "a", x = 100, y = 100, w = 200, h = 100 }
    local B = { id = "b", x = 400, y = 100, w = 50, h = 50 }
    local boxes = { A, B }
    local function same(h, x, y, w, hh, r, msg)
        eq(h.x, x, msg); eq(h.y, y, msg); eq(h.w, w, msg); eq(h.h, hh, msg); eq(h.r, r, msg)
    end
    test("opening: closed until opened, healed back", function()
        local st = OP.state()
        eq(st.mode, 0)
        OP.open(st)
        eq(st.mode, 1); eq(st.k, 1)
        OP.move(st, boxes, { x = 330, y = 150 })
        OP.heal(st)
        eq(st.mode, 0); eq(st.k, 0); eq(st.snap, nil); eq(st.step, 0)
    end)
    test("opening: snaps within 40 px, the nearest, back to follow when far", function()
        local st = OP.state(); OP.open(st)
        OP.move(st, boxes, { x = 330, y = 150 })
        eq(st.mode, OP.MODES.snapped); eq(st.snap.id, "a")
        OP.move(st, boxes, { x = 345, y = 150 })
        eq(st.mode, OP.MODES.follow); eq(st.snap, nil)
        OP.move(st, boxes, { x = 420, y = 120 })
        eq(st.mode, OP.MODES.snapped); eq(st.snap.id, "b")
    end)
    test("D218: with a clock, a widget is hugged only once the pointer rests on it; leaving lets go at once", function()
        local st = OP.state(); OP.open(st)
        OP.move(st, boxes, { x = 200, y = 150 }, 0, 1000)
        eq(st.mode, OP.MODES.follow, "passing over: the hole follows")
        OP.move(st, boxes, { x = 210, y = 150 }, 0, 1000 + OP.DWELL - 1)
        eq(st.mode, OP.MODES.follow, "not yet")
        OP.move(st, boxes, { x = 212, y = 150 }, 0, 1000 + OP.DWELL)
        eq(st.mode, OP.MODES.snapped, "rested: it hugs the widget"); eq(st.snap.id, "a")
        OP.move(st, boxes, { x = 700, y = 600 }, 0, 1400)
        eq(st.mode, OP.MODES.follow, "away: at once"); eq(st.snap, nil)
        OP.move(st, boxes, { x = 420, y = 120 }, 0, 1500)
        eq(st.mode, OP.MODES.follow, "another widget waits its own rest")
        OP.move(st, boxes, { x = 200, y = 150 }, 0, 1500 + OP.DWELL)
        eq(st.mode, OP.MODES.follow, "a different widget starts the wait again")
    end)
    test("opening: a tie goes to the smaller box", function()
        local big = { id = "big", x = 0, y = 0, w = 100, h = 100 }
        local small = { id = "small", x = 120, y = 0, w = 20, h = 20 }
        eq(OP.near({ big, small }, { x = 110, y = 10 }).id, "small")
        eq(OP.near({ small, big }, { x = 110, y = 10 }).id, "small")
    end)
    test("opening: the hole for each mode", function()
        local scr = { w = 1920, h = 1080 }
        local st = OP.state(); OP.open(st)
        same(OP.hole(st, { x = 500, y = 400 }, scr), 410, 310, 180, 180, 90, "follow")
        OP.move(st, boxes, { x = 330, y = 150 })
        same(OP.hole(st, { x = 330, y = 150 }, scr), 84, 84, 232, 132, 18, "snapped")
        OP.move(st, boxes, { x = 900, y = 900 })
        eq(st.mode, OP.MODES.follow, "far from every box")
        OP.move(st, boxes, { x = 330, y = 150 })
        OP.widen(st, scr)
        eq(st.mode, OP.MODES.section)
        same(OP.hole(st, { x = 330, y = 150 }, scr), 0, 0, 768, 432, 18, "section clamped")
        OP.move(st, boxes, { x = 900, y = 900 })
        eq(st.mode, OP.MODES.section, "move leaves a section alone")
        OP.widen(st, scr)
        same(OP.hole(st, { x = 0, y = 0 }, scr), 0, 0, 1920, 1080, 0, "full")
        OP.narrow(st, scr); eq(st.mode, OP.MODES.section)
        OP.narrow(st, scr); eq(st.mode, OP.MODES.snapped); eq(st.snap.id, "a")
    end)
    test("opening: a section without a snap centres on the pointer, on screen", function()
        local scr = { w = 1920, h = 1080 }
        local st = OP.state(); OP.open(st); OP.widen(st, scr)
        same(OP.hole(st, { x = 1900, y = 1070 }, scr), 1152, 648, 768, 432, 18)
        OP.narrow(st, scr); eq(st.mode, OP.MODES.follow)
    end)
    test("opening: a section opened by the wheel stays where it was put", function()
        local scr = { w = 1920, h = 1080 }
        local st = OP.state(); OP.open(st)
        OP.move(st, { { id = "apps", x = 50, y = 279, w = 360, h = 220 } }, { x = 60, y = 300 })
        OP.widen(st, scr, { x = 60, y = 300 })
        eq(st.mode, OP.MODES.section)
        local a = OP.hole(st, { x = 60, y = 300 }, scr)
        local b = OP.hole(st, { x = 1800, y = 1000 }, scr)
        eq(a.x, b.x, "the pointer moving does not move the section")
        eq(a.y, b.y, "nor down")
        eq(a.w, 768, "a section is 40 % of the screen")
        OP.narrow(st, scr)
        eq(st.mode, OP.MODES.snapped, "back to the thing it was over")
        eq(st.at, nil, "and the next section follows again")
    end)
    test("opening: pack stays under 2^24 and round-trips", function()
        local st = OP.state(); OP.open(st)
        local scr = { w = 4000, h = 3000 }
        OP.widen(st, scr); OP.widen(st, scr)
        local h = OP.hole(st, { x = 0, y = 0 }, scr)
        local a, b, c = OP.pack(st, h)
        for _, v in ipairs({ a, b, c }) do eq(v >= 0 and v < 2 ^ 24, true) end
        local u = OP.unpack(a, b, c)
        eq(u.x, 0); eq(u.y, 0); eq(u.w, 4000); eq(u.h, 3000); eq(u.mode, 4); eq(u.r, 0)
        local f = OP.state(); OP.open(f)
        local a2, b2, c2 = OP.pack(f, OP.hole(f, { x = -50, y = 5000 }, scr))
        for _, v in ipairs({ a2, b2, c2 }) do eq(v >= 0 and v < 2 ^ 24, true) end
        local u2 = OP.unpack(a2, b2, c2)
        eq(u2.x, 0); eq(u2.y, 4095); eq(u2.w, 180); eq(u2.h, 180); eq(u2.mode, 1); eq(u2.r, 90)
    end)
    test("opening: what reaches the citizens (D218: a follow move too)", function()
        local follow = { a = 100, b = 200, c = 1090 }
        -- D218: the programs no longer read their own (stale) cursor: a follow move is sent too
        eq(OP.changed(follow, 140, 240, 1090), true, "the hole moved, in follow mode")
        eq(OP.changed(follow, 100, 200, 1090), false, "nothing moved")
        eq(OP.changed(follow, 140, 240, 2018), true, "the mode changed")
        eq(OP.changed({ a = 1, b = 2, c = 2018 }, 3, 4, 2018), true, "the snapped box moved")
        eq(OP.changed(nil, 1, 2, 1090), true, "the first send")
    end)
end


section("surface: the shared opening (D209)")
test("opening block: one text in every program", function()
    local function read(p) local f = io.open(p); local t = f:read("a"); f:close(); return t end
    local function block(p)
        local a = assert(read(p):match("// <gen:opening>\n(.-)    // </gen:opening>"), p .. " lacks the markers")
        return a
    end
    local ref = block("shell/mooi-surface.plm")
    assert(#ref > 0, "non-empty")
    for _, p in ipairs({ "shell/mooi-widgets.plm", "shell/mooi-viz.plm", "shell/bmo/bmo.plm" }) do
        assert(block(p) == ref, p .. " differs from mooi-surface.plm")
    end
    for _, needle in ipairs({ "spring sg.op = 380, 34", "event op_a ->", "event sf_set ->", "let op_tx = op_ax", "on op_c(v)", "let op_faint = op_r1 > 499.5",
                            "follow op_k = if(op_mode > 0, if(op_faint, 0.45, 1), 0)", "let op_live = op_vis and not op_faint" }) do
        assert(ref:find(needle, 1, true), "the block has " .. needle)
    end
    -- D218: every mode draws the hole mooi-surface sends (it reads the pointer from Hyprland while Super is held)
    assert(ref:find("let op_tw = op_aw", 1, true) and not ref:find("op_px", 1, true), "follow: the hole as sent, never the scene's own cursor")
    assert(not ref:find("cursor", 1, true), "the block never names the pointer (it would start the cursor feed and the idle clock)")
    assert(ref:find("if(sf_on, floor(op_tc / 1000), 0)", 1, true), "Surface off: mode 0, nothing moves")
    for _, p in ipairs({ "shell/mooi-surface.plm", "shell/mooi-widgets.plm", "shell/mooi-viz.plm", "shell/bmo/bmo.plm" }) do
        local t = read(p)
        local outside = t:gsub("// <gen:opening>.-// </gen:opening>", "")
        assert(not outside:find("op_px", 1, true), p .. ": no cursor of its own for the opening (D218)")
    end
    local op = require("lib/surface/opening")
    eq(op.R, 90, "opening.R")
    -- the block's decode arithmetic, mirrored, against pack
    local function decode(a, b, c)
        local mode = math.floor(c / 1000); local r = c - mode * 1000
        local x = math.floor(a / 4096); local w = math.floor(b / 4096)
        return mode, r, x, a - x * 4096, w, b - w * 4096
    end
    for _, h in ipairs({ { 0, 0, 0, 0, 0, 0 }, { 2, 10, 20, 300, 200, 24 }, { 3, 4095, 4095, 4095, 4095, 499 }, { 4, 0, 0, 1920, 1080, 0 } }) do
        local a, b, c = op.pack({ mode = h[1] }, { x = h[2], y = h[3], w = h[4], h = h[5], r = h[6] })
        local mode, r, x, y, w, hh = decode(a, b, c)
        eq(mode, h[1], "mode"); eq(x, h[2], "x"); eq(y, h[3], "y"); eq(w, h[4], "w"); eq(hh, h[5], "h"); eq(r, h[6], "r")
    end
    assert(read("tools/gen-opening.py"):find("R = 90", 1, true), "the generator writes 90 from one constant")
end)

section("surface: scene (D209)")
test("scene: the opening at the wallpaper, never over windows", function()
    local function read(p) local f = io.open(p); local t = f:read("a"); f:close(); return t end
    local plm = read("shell/mooi-surface.plm")
    local function block(name)
        local a = plm:find("    surface " .. name .. " {", 1, true); assert(a, name .. " surface")
        local b = plm:find("\n    }\n", a, true); assert(b, name .. " closes")
        return plm:sub(a, b)
    end
    assert(not plm:find("surface reveal {", 1, true), "the old overlay is gone")
    local ground, edge = block("ground"), block("edge")
    for _, b in ipairs({ ground, edge }) do
        assert(not b:find("level: overlay", 1, true) and not b:find("level: top", 1, true), "never over windows")
        assert(b:find("open: op_vis", 1, true), "open only while the opening shows")
    end
    assert(ground:find("keyboard: none", 1, true), "the ground takes no keyboard")
    assert(edge:find("keyboard: exclusive while op_vis and sf_firm", 1, true), "the edge's, only once firm (Task 7)")
    assert(ground:find("level: background", 1, true), "the ground just above the wallpaper")
    assert(ground:find("clip box { from: op_x, op_y; size: op_w, op_h; corner: op_r }", 1, true), "clipped to the hole")
    assert(not ground:find("// below:", 1, true), "D215: nothing of its own below — the widgets are what lives there")
    assert(edge:find("level: bottom", 1, true), "the rim above the widgets")
    assert(not edge:find("zone", 1, true), "the edge catches nothing")
    for i, e in ipairs({ "tear", "aperture", "membrane", "ripple", "fold", "dissolve", "glass", "glow" }) do
        assert(edge:find("shader: " .. e .. ", op_k, op_x, op_y, op_w, op_h, op_r, sf_param, 0", 1, true), e .. " over the wallpaper")
        assert(edge:find("show: sf_fx > " .. (i - 0.5) .. " and sf_fx < " .. (i + 0.5), 1, true), e .. " is one of the looks")
    end
    assert(ground:find("rate: 60, 20 while calm", 1, true), "the ground rests when calm")
    assert(plm:find("fact sf_fx = 1", 1, true), "the Tear by default")
    -- found live (D208): screen.height is the first surface's (the 40 px bar strip); the wallpaper uses edge's
    assert(edge:find("image rv_img { at: 0, 0; size: edge.width, edge.height", 1, true), "the wallpaper at edge's own size")
    assert(not plm:find("size: screen.width, screen.height", 1, true), "never screen.height in this scene")
    assert(edge:find("emit rv_move(", 1, true) and edge:find("while rv_on or op_vis", 1, true), "the pointer, told while revealing")
    assert(not plm:find("rv_g0", 1, true) and not plm:find("rv_t1", 1, true) and not plm:find("rv_ring", 1, true), "the ring is gone")
    local w = read("shell/shaders/tear.wgsl")
    assert(w:find("fn shade(s: Shader) -> vec4<f32>", 1, true))
    assert(not w:find("pow(", 1, true), "no pow in the Tear")
    assert(not w:find("s.time", 1, true), "no per-frame animation: the tear is seeded, not moving")
    assert(not w:find("round(perim", 1, true) and w:find("fn tear_along(", 1, true), "noise by px along the edge: it does not boil as the hole grows")
    assert(not plm:find("    surface desk {", 1, true), "D215: no Presence layer — a widget kept above is one")
    assert(not plm:find("notification", 1, true))
    local ap = read("shell/shaders/aperture.wgsl")
    assert(ap:find("fn shade(s: Shader) -> vec4<f32>", 1, true))
    assert(ap:find("* (1.0 - hole)", 1, true) and not ap:find("pow(", 1, true), "the Aperture's hole is clear: ground and the hubs show")
end)

section("surface: settings and looks (D210)")
do
    local function read(p) local f = io.open(p); local t = f:read("a"); f:close(); return t end
    local paths = { "surface.intensity", "surface.edge", "surface.colour", "surface.speed", "surface.radius",
                    "surface.wall", "surface.dim", "surface.tint", "surface.fit", "surface.grid",
                    "surface.labels", "surface.glow", "surface.ping", "surface.layout", "surface.components",
                    "surface.bmo_side", "surface.overview", "surface.power_confirm", "surface.widget_style" }
    test("settings: every Surface setting is in the config, the setters and the page", function()
        local cfg, set, page = read("shell/lib/config.luau"), read("shell/lib/setters.luau"), read("shell/mooi-settings.plm")
        for _, p in ipairs(paths) do
            assert(cfg:find('path = "' .. p .. '"', 1, true), p .. " in config")
            assert(set:find('"' .. p .. '"', 1, true), p .. " in setters")
        end
        assert(cfg:find('surface.effect', 1, true) and cfg:find('membrane', 1, true) and cfg:find('glow', 1, true), "eight effects")
        assert(page:find("The Subsurface", 1, true), "its own page")
        for _, ev in ipairs({ "surface_arrange", "surface_above", "surface_below" }) do
            assert(page:find(ev, 1, true), ev .. " on the page")
        end
        assert(not page:find("surface_edit", 1, true) and not page:find("surface_reset", 1, true), "D215: no places to edit")
    end)
    test("settings: the logic applies the look, the wallpaper, the places and the ping", function()
        local l = read("shell/mooi-surface.luau")
        for _, s in ipairs({ "fact.sf_param = pc * 1000", "fact.sf_fx = fx", "opening.CORNER =", "reveal.OPEN_MS =",
                             "fact.sf_ping = SF.ping" }) do
            assert(l:find(s, 1, true), s)
        end
        assert(l:find('run("pleamar", { "--say", cname, "emit op_a " .. a, "emit op_b " .. b, "emit op_c " .. c })', 1, true), "one process per citizen")
    end)
    test("settings: the scene carries the wallpaper, the eight effects and the aura", function()
        local plm = read("shell/mooi-surface.plm")
        assert(plm:find("image sf_cover = from rv_wall", 1, true) and plm:find("image sf_contain = from rv_wall", 1, true), "the wallpaper")
        assert(plm:find("shader: ground, op_k, op_x, op_y, sf_dim, sf_grid, sf_tint", 1, true), "the ground reads it")
        assert(plm:find("shader aura {", 1, true) and plm:find("sf_glow + sf_ping", 1, true), "the light through the skin")
        assert(plm:find("show: op_vis and op_mode == 4 and sf_ovm > 0.5", 1, true), "the Overview's rim")
        assert(plm:find("sf_labels > 0.5 }", 1, true), "the Overview's hints can go")
        assert(plm:find("au_mx, au_my, au_nx, au_ny", 1, true), "D215: the glow sits at the Now Playing and Notices widgets")
        assert(read("shell/mooi-viz.plm"):find("open: (not sf_on or op_vis", 1, true), "the visualiser rests hidden")
        assert(read("shell/lib/widgets.luau"):find("function M.set_all", 1, true), "all widgets above or below")
    end)
end

section("surface: citizens (D209)")
do
    local function read(p) local f = io.open(p); local t = f:read("a"); f:close(); return t end
    test("citizens: widgets hide below and clip to the hole", function()
        local plm = read("shell/mooi-widgets.plm")
        assert(plm:find("// <gen:opening>", 1, true) and plm:find("let op_vis = sf_on and op_k > 0.01", 1, true), "the block")
        local gate = "show: not sf_on or w.above or editing or wg_desk or op_vis"
        assert(plm:find(gate, 1, true), "the widgets' gate")
        -- a clip cannot be shown or hidden (found live: `show: false` still clipped everything away), so when
        -- the widget is not below, its clip region is the whole surface
        assert(plm:find("let clip_on = sf_on and not w.above and not editing and not wg_desk", 1, true), "when to clip")
        assert(plm:find("clip box { from: if(clip_on, op_x, 0), if(clip_on, op_y - wall_bar, 0); size: if(clip_on, op_w, desk.width), if(clip_on, op_h, desk.height); corner: if(clip_on, op_r, 0) }", 1, true), "the hole's clip")
        assert(plm:find("above: bool", 1, true), "widgets.json carries it")
        -- the lanes drawn outside the loop (notes, GitHub, weather, system, calendar, launcher) and the held
        -- visualisers are gated too
        assert(plm:find("fact nl_above = false", 1, true), "a lane's above")
        assert(plm:find("show: (not sf_on or nl_above or editing or wg_desk or op_vis or nt_ed > -1.5) and nl_on", 1, true), "the lanes' gate; the notes editor stays whole")
        assert(plm:find("show: (not sf_on or lA_above or editing or wg_desk or op_vis) and lA_on", 1, true), "a held visualiser's gate")
        assert(plm:find("let nl_clip = sf_on and not nl_above and not editing and not wg_desk and nt_ed < -1.5", 1, true), "an edited notes lane is unclipped")
        for _, e in ipairs({ "wg_keep", "wg_keep_y", "wg_bury" }) do assert(plm:find("event " .. e .. " ->", 1, true), e) end
        assert(plm:find("emit wg_keep(", 1, true) and plm:find("emit wg_keep_y(", 1, true) and plm:find("emit wg_bury(", 1, true), "the drop tells the logic")
        assert(read("shell/mooi-widgets.luau"):find("citizen.hello(run, after, report_bar)", 1, true), "widgets ask for the hole")
        assert(read("shell/mooi-viz.luau"):find('require("lib/surface/citizen").hello(run, after)', 1, true), "the visualisers too")
        local viz = read("shell/mooi-viz.plm")
        assert(viz:find("let clip_A = sf_on and not lA_above", 1, true) and viz:find("clip box { from: if(clip_A, op_x, 0), if(clip_A, op_y - sf_top, 0)", 1, true), "the lanes clip too")
    end)
    test("citizens: BMO lives below, the opening's settings, the stand-down", function()
        local cfg = require("lib/config").defaults()
        eq(cfg.surface.effect, "tear"); eq(cfg.surface.bmo_below, true)
        eq(require("lib/config").validate({ surface = { effect = "nonsense" } }).surface.effect, "tear", "an unknown look: the Tear")
        local plm = read("shell/bmo/bmo.plm")
        assert(plm:find("// <gen:opening>", 1, true) and plm:find("let op_vis = sf_on and op_k > 0.01", 1, true), "the block")
        assert(plm:find("let bmo_below = sf_on and sf_bmo and not above and not on_bar and not walking", 1, true), "his home")
        assert(plm:find("show: not bmo_below or op_vis", 1, true), "below until opened")
        assert(plm:find("clip box { from: if(bmo_below, op_x, 0), if(bmo_below, op_y, 0); size: if(bmo_below, op_w, desk.width)", 1, true), "clipped to the hole")
        assert(read("shell/bmo/bmo.luau"):find('"emit op_want"', 1, true), "he asks for the hole")
        local m = read("bin/mooi")
        assert(m:find('"emit op_c 0"', 1, true), "the citizens stand down with the surface")
        local set = read("shell/lib/setters.luau")
        assert(set:find('"surface.effect"', 1, true) and set:find('"surface.bmo_below"', 1, true), "the settings' codes")
        local win = read("shell/mooi-settings.plm")
        assert(win:find("fact sv_surface_effect = 0", 1, true) and win:find("fact sv_surface_bmo_below = 0", 1, true), "their rows")
        local l = read("shell/mooi-surface.luau")
        assert(l:find("fact.sf_fx", 1, true), "the effect reaches the scene")
        assert(l:find("bmo_below", 1, true), "bit 2 follows the setting")
    end)
    test("citizens: a widget dragged out is kept above, wholly on screen and under the bar", function()
        local W = require("lib/widgets")
        local w = { w = 440, h = 192 }
        local c = W.keep_at(w, 1900, 1070, { w = 1920, h = 1080 }, 34)
        eq(c.x, 1480); eq(c.y, 1080 - 34 - 192); eq(c.above, true)
        local d = W.keep_at(w, -50, -50, { w = 1920, h = 1080 }, 34)
        eq(d.x, 0); eq(d.y, 0); eq(d.above, true)
        local doc = W.encode({ widgets = { { id = "a", kind = "clock", layout = "digital", mode = "normal",
                                             x = 0, y = 0, w = 100, h = 100, above = true } } })
        eq(doc.widgets[1].above, true, "widgets.json keeps it")
    end)
end

section("surface: logic (D209)")
test("logic: the opening live — follow, snap, widen, heal, the keyboard path", function()
    local function read(p) local f = io.open(p); local t = f:read("a"); f:close(); return t end
    local l = read("shell/mooi-surface.luau")
    assert(l:find('require("lib/surface/reveal")', 1, true) and not l:find('require("lib/surface/presence")', 1, true), "D215: no Presences of its own")
    assert(l:find('require("lib/surface/opening")', 1, true), "the opening is shared")
    for _, e in ipairs({ "rv_down", "rv_up", "rv_move", "rv_esc", "op_wheel", "op_want", "op_key",
                         "sb_drag", "sb_drop", "op_type", "op_bx", "op_wbar" }) do
        assert(l:find('on("' .. e .. '"', 1, true), e .. " handled")
    end
    assert(l:find('local CITIZENS = { "mooi-widgets", "mooi-viz", "bmo" }', 1, true), "the programs under the wallpaper")
    assert(l:find('"emit op_a "', 1, true) and l:find('"emit sf_set "', 1, true), "the opening and the Surface's bits reach them")
    assert(l:find('"surface.json"', 1, true), "surface.json is kept")
    assert(l:find('SF_guard("workspace")', 1, true) and l:find('SF_guard("focus")', 1, true), "a shortcut never leaves it open")
    -- found live: the window service also fires when a title changes (a terminal's, constantly); only a change of
    -- app is a change of focus
    assert(l:find("if was_class ~= nil and was_class ~= w.class and SF_guard then SF_guard(\"focus\") end", 1, true), "a title change keeps the reveal")
    assert(l:find('"emit pill_call"', 1, true), "a tap is still today's Super tap")
    -- found live (Task 1, F1 = no): Super + click never reached a layer zone, so the drag bind is put down while
    -- the opening is open and put back on heal, on load, and when the keeper restarts the surface
    assert(l:find('hl.unbind("SUPER + mouse:272")', 1, true), "the drag bind is put down")
    assert(l:find('hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })', 1, true), "and put back")
    local m = read("bin/mooi")
    assert(m:find("    reveal)", 1, true) and m:find('"emit rv_down"', 1, true) and m:find('"emit rv_up"', 1, true))
    assert(m:find("heal)", 1, true) and m:find('"emit op_wheel ', 1, true), "heal and the wheel's route")
    local plm = read("shell/mooi-surface.plm")
    assert(plm:find("emit rv_move(", 1, true), "the scene tells the logic where the pointer is while revealing")
    assert(plm:find("keyboard: exclusive while op_vis and sf_firm", 1, true), "the keyboard only once firm")
    assert(plm:find("fact sf_firm", 1, true), "its fact")
    assert(l:find("reveal.firm(st) or (SF.op.mode == opening.MODES.full and SF.opened == true)", 1, true), "a full opening keeps the keyboard after release")
    assert(l:find("and not SF.dragging", 1, true) and l:find("SF.op.mode = opening.MODES.snapped", 1, true), "a drag freezes the hole")
    assert(read("shell/mooi.luau"):find("if not desk_win then after(800, surface_sync); return end", 1, true), "the surface waits for the wallpaper's layer")
    assert(read("shell/lib/wbelow_feed.luau"):find("(net and net.wifi)", 1, true), "the Wi-Fi radio, not the connection (now the Controls widget's)")
    assert(read("shell/mooi.luau"):find('"emit sf_set 0"', 1, true), "Surface off brings the citizens back")
    for _, k in ipairs({ "Tab", "Shift+Tab", "Return", "Page_Up", "Page_Down" }) do
        assert(plm:find("on key " .. k .. " { emit op_", 1, true), k .. " is the opening's")
    end
    -- found live: without the permission surface.json was silently never written
    assert(plm:match('services: [^\n]*"files.write"'), "it may write surface.json")
    local cfg = require("lib/config").defaults()
    eq(cfg.surface.on, false); eq(cfg.surface.delay, 250)
    local h = read("setup/home/.config/hypr/config/custom/mooi.lua")
    assert(h:find('mooi .. " reveal down"', 1, true) and h:find('mooi .. " reveal up"', 1, true), "Super's press and release")
end)

section("surface: the spec, audited (D214)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    local op = require("lib/surface/opening")
    local BL = require("lib/surface/below")
    local CZ = require("lib/surface/citizen")
    local scr = { w = 1920, h = 1080 }

    test("opening: a fresh opening is faint until it is firm, snapped or widened", function()
        local st = op.state()
        op.open(st)
        eq(st.faint, true, "faint at first")
        local _, _, c = op.pack(st, op.hole(st, { x = 500, y = 500 }, scr))
        local u = op.unpack(0, 0, c)
        eq(u.faint, true, "the programs are told"); eq(u.mode, 1); eq(u.r, 90, "the rim survives the flag")
        op.firm(st)
        _, _, c = op.pack(st, op.hole(st, { x = 500, y = 500 }, scr))
        eq(op.unpack(0, 0, c).faint, false, "firm: all the way open")
        local s2 = op.state(); op.open(s2)
        op.move(s2, { { id = "apps", x = 480, y = 480, w = 100, h = 100 } }, { x = 500, y = 500 })
        eq(s2.mode, op.MODES.snapped); eq(s2.faint, false, "snapping opens it")
        local s3 = op.state(); op.open(s3); op.widen(s3, scr, { x = 500, y = 500 })
        eq(s3.faint, false, "the wheel opens it"); eq(s3.mode, op.MODES.section)
        op.heal(s3); eq(s3.faint, false); eq(s3.away, false)
    end)
    test("opening: no opening over the bar — it is told closed until the pointer comes down", function()
        local st = op.state(); op.open(st); op.firm(st)
        op.move(st, {}, { x = 400, y = 10 }, 34)
        eq(st.away, true, "over the bar"); eq(op.shown(st), op.MODES.closed)
        local _, _, c = op.pack(st, op.hole(st, { x = 400, y = 10 }, scr))
        eq(c // 1000, 0, "sent as closed"); eq(op.unpack(0, 0, c).faint, false, "closed is never faint")
        assert(op.changed({ a = 0, b = 0, c = 1090 }, 0, 0, c), "the change is sent")
        op.move(st, {}, { x = 400, y = 300 }, 34)
        eq(st.away, false); eq(op.shown(st), op.MODES.follow, "back down: open again")
        -- a section and the Overview do not follow, so the bar does not close them
        op.widen(st, scr, { x = 400, y = 300 })
        op.move(st, {}, { x = 400, y = 5 }, 34)
        eq(op.shown(st), op.MODES.section, "a section stays")
        op.widen(st, scr, { x = 400, y = 300 })
        eq(op.shown(st), op.MODES.full)
    end)
    test("opening: the logic sends the hole once per change, with no throttle that could drop one", function()
        local l = read("shell/mooi-surface.luau")
        assert(not l:find("SF.ship_at", 1, true), "the 100 ms throttle is gone")
        assert(l:find("opening.move(SF.op, boxes(), SF.ptr, bar_h(), SF.clock)", 1, true), "the bar's strip (and, D218, the clock) is passed")
        assert(l:find("if SF.op.faint and reveal.firm(SF.rv) then", 1, true), "firm opens it all the way")
        assert(l:find('fact.sf_snap = code', 1, true) and l:find('"emit op_wake"', 1, true), "the snapped thing rises; BMO wakes")
        assert(l:find("if not on and SF.op.mode ~= opening.MODES.closed then", 1, true), "Surface off heals at once")
    end)

    test("repaint: every surface that clips to the hole repaints whole while it shows (found by rendering it)", function()
        local veil = "box { from: 0, 0; size: 8192, 8192; color: #000000; opacity: 0.004 + 0.001 * fract((op_x + op_y + op_w + op_h) / 97); show: op_k > 0.001 }"
        for _, f in ipairs({ "shell/mooi-widgets.plm", "shell/mooi-viz.plm", "shell/bmo/bmo.plm" }) do
            local s = read(f)
            assert(s:find("// <gen:opening-probe>", 1, true) and s:find(veil, 1, true), f)
        end
        local plm = read("shell/mooi-surface.plm")
        local n = 0
        for _ in plm:gmatch("fract%(%(op_x %+ op_y %+ op_w %+ op_h%) / 97%)") do n = n + 1 end
        eq(n, 2, "the ground and the edge")
    end)
    test("citizen: one hello, boxes packed under 2^24, the hole's rule", function()
        local a, b = CZ.pack_box({ x = 1700, y = 820, w = 160, h = 196 })
        assert(a < 2 ^ 24 and b < 2 ^ 24, "float32 carries them whole")
        local u = CZ.unpack_box(a, b)
        eq(u.x, 1700); eq(u.y, 820); eq(u.w, 160); eq(u.h, 196)
        eq(CZ.unpack_box(CZ.pack_box({ x = -5, y = 9000, w = 0 / 0, h = 3 })).y, 4095, "clamped")
        eq(CZ.inside({ x = 0, y = 0, w = 100, h = 100 }, { x = 90, y = 90, w = 50, h = 50 }), true, "partly inside")
        eq(CZ.inside({ x = 0, y = 0, w = 100, h = 100 }, { x = 100, y = 0, w = 50, h = 50 }), false, "touching is outside")
        eq(CZ.inside({ x = 0, y = 0, w = 0, h = 0 }, { x = 0, y = 0, w = 5, h = 5 }), false, "a closed hole holds nothing")
        local said, later, reported = {}, nil, 0
        CZ.hello(function(_, args) said[#said + 1] = table.concat(args, " ") end, function(_, fn) later = fn end,
                 function() reported = reported + 1 end)
        eq(said[1], "--say mooi-surface emit op_want"); eq(reported, 1)
        later(); eq(#said, 2, "asked again"); eq(reported, 2)
        eq(table.concat(CZ.say("op_wbar", 33.6), " "), "--say mooi-surface emit op_wbar 34")
        -- BMO writes the same two sends out (his logic cannot require shell/lib)
        local bmo = read("shell/bmo/bmo.luau")
        assert(bmo:find('"emit op_bx " .. (c12(x) * 4096 + c12(y))', 1, true) and bmo:find('"emit op_bs " .. (c12(w) * 4096 + c12(h))', 1, true), "BMO reports his box")
        assert(bmo:find('on("op_wake"', 1, true) and read("shell/bmo/bmo.plm"):find("event op_wake ->", 1, true), "and wakes")
        assert(read("shell/mooi-widgets.luau"):find('citizen.say("op_wbar"', 1, true), "the widgets report their strip")
        local plm = read("shell/mooi-surface.plm")
        for _, e in ipairs({ "op_bx", "op_bs", "op_wbar", "op_type", "sb_drag", "sb_drop" }) do assert(plm:find("event " .. e .. " ->", 1, true), e .. " declared") end
    end)


    test("keeper: the subsurface's programs start with reduced motion when asked", function()
        local m = read("shell/mooi.luau")
        assert(m:find('if m.reduced == true then a[#a + 1] = "--reduced-motion" end', 1, true))
        for _, s in ipairs({ "mooi-surface.plm", "mooi-viz.plm", "mooi-widgets.plm", "bmo/bmo.plm" }) do
            assert(m:find('SURFACE.args(shell_dir() .. "/' .. s .. '")', 1, true), s)
        end
    end)
end

section("widgets below: the kinds (D215)")
do
    local W = require("lib/widgets")
    local scr = { w = 1920, h = 1080, top = 34 }
    local function empty() return { version = W.VERSION, widgets = {} } end
    test("kinds: four new single kinds with their layouts and sizes", function()
        eq(W.MAX, 16, "sixteen widgets")
        for kind, lay in pairs({ notices = "stack", wallpapers = "strip", settings = "pages", controls = "row" }) do
            local d, id = W.add(empty(), kind, scr)
            assert(id, kind .. " added")
            local w = d.widgets[1]
            eq(w.layout, lay, kind .. " layout")
            local _, id2 = W.add(d, kind, scr)
            eq(id2, nil, kind .. ": one only")
        end
        eq(W.LAYOUTS.stack.def[1], 360); eq(W.LAYOUTS.stack.def[2], 260); eq(W.LAYOUTS.stack.min[1], 280)
        eq(W.LAYOUTS.strip.def[1], 420); eq(W.LAYOUTS.strip.min[2], 110)
        eq(W.LAYOUTS.pages.def[2], 170); eq(W.LAYOUTS.row.def[1], 452); eq(W.LAYOUTS.ccolumn.def[2], 452)
        eq(W.KIND_NUM.notices, 12); eq(W.KIND_NUM.controls, 15)
        eq(W.ADD_ORDER[16], "controls")
    end)
    test("kinds: Launch has a grid; options clamp; the doc keeps its flags", function()
        local d, id = W.add(empty(), "launch", scr)
        d = W.set_layout(d, id, "grid", scr)
        eq(d.widgets[1].layout, "grid")
        local n, nid = W.add(empty(), "notices", scr)
        n = W.set_option(n, nid, "nrows", 99)
        eq(n.widgets[1].options.nrows, 6, "rows at most six")
        eq(W.OPTIONS.controls.power_confirm, true); eq(W.OPTIONS.controls.wifi, true)
        local raw = { version = 2, widgets = {}, below_seeded = true, migrated_presences = true, launch_counts = { kitty = 3 } }
        local p = W.parse("x", function() return raw end, scr)
        eq(p.below_seeded, true); eq(p.migrated_presences, true); eq(p.launch_counts.kitty, 3)
        local e = W.encode(p)
        eq(e.below_seeded, true); eq(e.migrated_presences, true); eq(e.launch_counts.kitty, 3)
    end)
end

section("widgets below: seeding, arranging, migrating (D215)")
do
    local W = require("lib/widgets")
    local WB = require("lib/wbelow")
    local BL = require("lib/surface/below")
    local scr = { w = 1920, h = 1080, top = 34 }
    local function empty() return { version = W.VERSION, widgets = {} } end
    local function apart(list)
        for i = 1, #list do for j = i + 1, #list do
            local a, b = list[i], list[j]
            if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then return false, a.id .. "/" .. b.id end
        end end
        return true
    end
    local function on(w, s) return w.x >= 0 and w.y >= 0 and w.x + w.w <= s.w and w.y + w.h <= s.h - (s.top or 0) end
    test("arrange: any list of boxes, every layout, on screen and apart", function()
        local items = {}
        for i, wh in ipairs({ { 432, 152 }, { 640, 160 }, { 360, 240 }, { 400, 150 }, { 340, 320 }, { 560, 170 },
                              { 360, 260 }, { 420, 140 }, { 320, 170 }, { 452, 80 } }) do
            items[i] = { id = "i" .. i, w = wh[1], h = wh[2] }
        end
        for _, lay in ipairs(BL.LAYOUTS) do
            local P = BL.arrange(items, { w = 1920, h = 1046 }, lay)
            local list = {}
            for _, it in ipairs(items) do
                local p = assert(P[it.id], lay .. " " .. it.id)
                eq(p.w, it.w); eq(p.h, it.h)
                eq(p.x >= 0 and p.y >= 0 and p.x + p.w <= 1920 and p.y + p.h <= 1046, true, lay .. " " .. it.id .. " on screen")
                list[#list + 1] = { id = it.id, x = p.x, y = p.y, w = p.w, h = p.h }
            end
            local ok, why = apart(list)
            eq(ok, true, lay .. " apart " .. tostring(why))
        end
        local small = BL.arrange(items, { w = 1366, h = 734 }, "arc")
        for _, it in ipairs(items) do local p = small[it.id]; eq(p.x + p.w <= 1366 and p.y + p.h <= 734 and p.x >= 0 and p.y >= 0, true, "small " .. it.id) end
    end)
    test("seed: the default set, only missing kinds, below, once", function()
        eq(#WB.DEFAULT_SET, 10)
        local d, n = WB.seed(empty(), scr, "arc")
        eq(n, 10, "ten placed"); eq(d.below_seeded, true)
        local kinds = {}
        for _, w in ipairs(d.widgets) do kinds[w.kind] = w.layout or w.mode; eq(w.above, false, w.kind .. " below"); eq(on(w, scr), true, w.kind .. " on screen") end
        eq(kinds.launch, "grid"); eq(kinds.controls, "row"); eq(kinds.nowplaying, "sleeve"); eq(kinds.clock, "digital")
        eq((apart(d.widgets)), true, "apart")
        local again, n2 = WB.seed(d, scr, "arc")
        eq(n2, 0, "never twice"); eq(#again.widgets, 10)
        local mine = W.add(empty(), "clock", scr)
        local m, n3 = WB.seed(mine, scr, "row")
        eq(n3, 9, "the owner's clock kept, nine more"); eq(W.count_kind(m, "clock"), 1)
        local small = WB.seed(empty(), { w = 1366, h = 768, top = 34 }, "calm")
        for _, w in ipairs(small.widgets) do eq(on(w, { w = 1366, h = 768, top = 34 }), true, "small " .. w.kind) end
    end)
    test("seed: a full file adds nothing and loses nothing", function()
        local d = empty()
        for i = 1, W.MAX do d.widgets[i] = { id = "viz-" .. i, kind = "visualiser", mode = "spectrum", x = 0, y = 0, w = 160, h = 64, options = {} } end
        local s, n, problems = WB.seed(d, scr, "arc")
        eq(n, 0); eq(#s.widgets, W.MAX); eq(#problems > 0, true, "said so"); eq(s.below_seeded, true)
    end)
    test("arrange_all: every widget below, by the arrangement; kept-above ones stay", function()
        local d = WB.seed(empty(), scr, "arc")
        d.widgets[1].above, d.widgets[1].x, d.widgets[1].y = true, 7, 9
        local r = WB.arrange_all(d, scr, "row")
        eq(r.widgets[1].x, 7, "kept above: not moved"); eq(r.widgets[1].y, 9)
        eq((apart(r.widgets)), true)
    end)
    test("migrate: Presences become widgets kept above, once, one per kind", function()
        local P = { { source = "music", fx = 0.24, fy = 0.78 }, { source = "clock", fx = 0.69, fy = 0.18 },
                    { source = "music", fx = 0.22, fy = 0.18 }, { source = "volume", fx = 0.5, fy = 0.5 },
                    { source = "network", fx = 0.6, fy = 0.6 }, { source = "workspaces", fx = 0.1, fy = 0.1 } }
        local d, problems = WB.migrate(P, empty(), scr)
        eq(d.migrated_presences, true)
        local by = {}
        for _, w in ipairs(d.widgets) do by[w.kind] = (by[w.kind] or 0) + 1; eq(w.above, true, w.kind .. " kept above") end
        eq(by.nowplaying, 1, "two music Presences: one Now Playing"); eq(by.clock, 1); eq(by.controls, 1, "volume and network: one Controls")
        eq(#problems, 1, "workspaces has no widget")
        local np
        for _, w in ipairs(d.widgets) do if w.kind == "nowplaying" then np = w end end
        eq(math.abs((np.x + np.w / 2) - 0.24 * 1920) <= 8, true, "centred where it was")
        local again = WB.migrate(P, d, scr)
        eq(#again.widgets, #d.widgets, "never twice")
        eq(WB.MIGRATE.resources, "system"); eq(WB.MIGRATE.notifications, "notices"); eq(WB.MIGRATE.battery, "controls")
    end)
    test("walls: the six newest with a thumbnail; migration knows the bar", function()
        local idx = { items = { { path = "/a", thumb = "/ta", mtime = 1 }, { path = "/b", thumb = "", mtime = 9 },
                                { path = "/c", thumb = "/tc", mtime = 5 } } }
        local r = WB.walls(idx, 6)
        eq(#r, 2, "only pictures with a thumbnail"); eq(r[1].path, "/c", "the newest first")
        eq(#WB.walls(nil, 6), 0)
        local d = WB.migrate({ { source = "clock", fx = 0.5, fy = 0.5 } }, { version = W.VERSION, widgets = {} }, { w = 1920, h = 1046, top = 0 }, 34)
        local c = d.widgets[1]
        eq(math.abs((c.y + c.h / 2) - (0.5 * 1080 - 34)) <= 8, true, "a Presence's screen fraction, in the widgets' surface")
    end)
    test("grid apps and the settings pages", function()
        local list = { { id = "a", name = "Kitty", exec = "kitty" }, { id = "b", name = "Firefox", exec = "firefox" },
                       { id = "d", name = "Files", exec = "nautilus" } }
        local r = WB.grid_apps(list, { d = 5 }, "", 12)
        eq(r[1].id, "d", "the most launched first")
        eq(#WB.grid_apps(list, {}, "fi", 12), 2)
        eq(WB.SETTINGS[8][1], "The Subsurface"); eq(WB.SETTINGS[8][2], 21)
    end)
end

section("widgets below: the drawings and lanes (D215)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    test("drawings: four components and Launch's grid, on the widgets' ground", function()
        local ui = read("shell/ui/wbelow.plm")
        for _, c in ipairs({ "component Notices(", "component Walls(", "component Pages(", "component Controls(", "component LaunchGrid(" }) do
            assert(ui:find(c, 1, true), c)
        end
        local n = 0
        for _ in ui:gmatch("wg%.Ground%(") do n = n + 1 end
        eq(n, 5, "every one stands on wg.Ground")
        for _, e in ipairs({ "emit nc_go(", "emit wp_go(", "emit pg_go(", "emit ct_go(", "emit ct_wheel(", "emit ct_pw(", "emit lg_go(" }) do
            assert(ui:find(e, 1, true), e)
        end
        assert(ui:find('"Theme & colour", "Bar & Frame", "Wallpapers", "Widgets", "Sound", "Power", "BMO", "The Subsurface"', 1, true), "the real pages")
    end)
    test("lanes: the four kinds and the grid are drawn, clipped to the hole like the rest", function()
        local plm = read("shell/mooi-widgets.plm")
        for _, c in ipairs({ "wb.Notices(", "wb.Walls(", "wb.Pages(", "wb.Controls(", "wb.LaunchGrid(" }) do assert(plm:find(c, 1, true), c) end
        for _, p in ipairs({ "nc", "wp", "pg", "ct" }) do
            assert(plm:find("let " .. p .. "_clip = sf_on and not " .. p .. "_above", 1, true), p .. " clips to the hole")
            assert(plm:find("fact " .. p .. "_on = false", 1, true), p .. " lane facts")
        end
        for _, e in ipairs({ "nc_go", "wp_go", "pg_go", "ct_go", "ct_wheel", "ct_pw", "lg_go", "ln_type", "wg_arrange" }) do
            assert(plm:find("event " .. e .. " ->", 1, true), e .. " declared")
        end
        assert(plm:find("repeat ai in 0..16 {", 1, true) and plm:find('"+ CONTROLS"', 1, true), "sixteen kinds can be added")
        assert(plm:find('"nmcli", "bluetoothctl", "systemctl", "hyprctl"', 1, true) and plm:find('"brightness", "brightness.*"', 1, true), "what the controls need")
        local panel = read("shell/ui/widgets.plm")
        assert(panel:find('Chip(x + 212, y + 52, 96, "GRID"', 1, true), "the grid can be chosen")
        assert(panel:find('"POWER ASKS TWICE"', 1, true) and panel:find('Chip(x + 156, y + wy, 34, "3"', 1, true), "the new kinds' switches")
    end)
end

section("widgets below: the logic (D215)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    test("logic: seeding and migration only with the Surface on, once each; Re-arrange undoable", function()
        local l = read("shell/mooi-widgets.luau")
        assert(l:find("if not doc or standing_down or surface_settings().on ~= true then return end", 1, true), "Surface off: nothing placed")
        assert(l:find("if doc.migrated_presences and doc.below_seeded then return end", 1, true), "once each")
        assert(l:find("WB.migrate(type(s) == \"table\" and s.presences or {}, d, room, tonumber(fact.wall_bar) or 34)", 1, true), "the Presences, with the bar")
        assert(l:find("WB.seed(d, room, surface_settings().layout or \"arc\")", 1, true), "the chosen arrangement")
        assert(l:find('on("sf_set"', 1, true) and l:find('on("wg_arrange"', 1, true))
        assert(l:find('change(WB.arrange_all(doc, room', 1, true), "through change: one undo puts them back")
        for _, h in ipairs({ "BF.audio(a)", "BF.battery(b)", "BF.apps(apps_now)", "BF.notices(f)", "BF.refresh()" }) do assert(l:find(h, 1, true), h) end
        assert(l:find('notices = "nc_", wallpapers = "wp_", settings = "pg_", controls = "ct_"', 1, true), "the lanes are lit")
    end)
    test("overview: the widgets' edit keys reach them while the opening holds the keyboard", function()
        local plm = read("shell/mooi-surface.plm")
        for code, k in pairs({ [11] = "Ctrl+z", [12] = "Ctrl+Shift+z", [9] = "Delete", [1] = "Left", [4] = "Down", [8] = "Shift+Down", [10] = "Ctrl+d", [13] = "Ctrl+a" }) do
            assert(plm:find("on key " .. k .. " while op_mode == 4 { emit op_wkey(" .. code .. ") }", 1, true), k)
        end
        assert(plm:find("event op_wkey ->", 1, true))
        assert(read("shell/mooi-surface.luau"):find('widgets_say("emit wg_key " ..', 1, true), "sent on as the widgets' own keys")
    end)
    test("feed: one watcher per service, the presses do what the spec says", function()
        local f = read("shell/lib/wbelow_feed.luau")
        for _, s in ipairs({ '"audio"', '"battery"', '"apps"', '"files:nexus-feed.json"' }) do
            assert(not f:find("sys.watch, " .. s, 1, true), "mooi-widgets already watches " .. s)
        end
        for _, s in ipairs({ '"network"', '"bluetooth"', '"brightness"', '"files:walls-index.json"' }) do assert(f:find("sys.watch, " .. s, 1, true), s) end
        assert(f:find('say_mooi("emit note_act " .. tostring(row * 10 + what))', 1, true) and f:find('say_mooi("emit note_clear")', 1, true), "notices")
        assert(f:find('run("mooi", { "wall", "apply", w.path }', 1, true), "wallpapers")
        assert(f:find('say_mooi("emit open_settings_at " .. tostring(p[2]))', 1, true), "settings")
        assert(f:find('opts("controls").power_confirm ~= false and fact.ct_pw_arm ~= n', 1, true), "power asks again, each for itself")
        assert(f:find("d.launch_counts[a.id] = (d.launch_counts[a.id] or 0) + 1", 1, true), "the grid learns what is launched")
        assert(f:find("if v == 27 then q = \"\"", 1, true), "Esc clears what is typed")
    end)
end

section("widgets below: the carry-overs (D216)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    local below = require("lib/surface/below")
    local ws = { { id = "np-1", kind = "nowplaying", layout = "sleeve" }, { id = "ln-1", kind = "launch", layout = "shelf" },
                 { id = "ln-2", kind = "launch", layout = "grid", above = true }, { id = "ln-3", kind = "launch", layout = "grid" } }
    test("slot: a snapped widget's place in widgets.json, 0-based; anything else is none", function()
        eq(below.slot(ws, "w:np-1"), 0, "the first")
        eq(below.slot(ws, "w:ln-3"), 3, "the fourth")
        eq(below.slot(ws, "w:gone"), -1, "a widget no longer there")
        eq(below.slot(ws, "bmo"), -1, "BMO is not a widget")
        eq(below.slot(ws, nil), -1, "nothing snapped")
        eq(below.slot(nil, "w:np-1"), -1, "no widgets")
    end)
    test("grid_slot: the Launch grid below the wallpaper that typing finds apps in", function()
        eq(below.grid_slot(ws), 3, "a grid kept above is not below")
        eq(below.grid_slot({ ws[1], ws[2] }), -1, "no grid")
    end)
    test("coming up: the snapped widget rises on a spring, the rest wait at 96 %, in the loop and every lane", function()
        local plm = read("shell/mooi-widgets.plm")
        assert(plm:find("event wg_rise ->", 1, true) and plm:find("on wg_rise(v) { wg_rise = v }", 1, true), "told what is snapped")
        assert(plm:find("spring wg.rise = 320, 26", 1, true), "a spring, never a long tween")
        for k = 0, 15 do
            assert(plm:find("prop ru" .. k .. " = 0 ~wg.rise", 1, true) and
                   plm:find("follow ru" .. k .. " = if(op_vis and (op_mode == 3 or wg_rise == " .. k .. "), 1, 0)", 1, true), "slot " .. k)
        end
        assert(plm:find("let rs = if(sf_on and not w.above and not editing and not wg_desk, pick(k, ru0, ru1, ru2", 1, true), "the loop's widgets")
        assert(plm:find("scale: 0.96 + 0.04 * rs", 1, true), "the loop's widgets rise")
        for _, p in ipairs({ "nl", "g1", "wh", "ln", "nc", "wp", "pg", "ct" }) do
            assert(plm:find("scale: 0.96 + 0.04 * " .. p .. "_rs", 1, true), p .. " rises")
        end
        for _, L in ipairs({ "lA", "lB", "lC" }) do assert(plm:find("scale: 0.96 + 0.04 * " .. L .. "_rs", 1, true), L .. " rises") end
        assert(plm:find("glow: 26, 0.55 * rs, #000000", 1, true), "a depth shadow under what rises")
    end)
    test("Return presses the snapped widget; typed in the Overview, it launches the first match", function()
        local s = read("shell/mooi-surface.luau")
        assert(s:find('widgets_say("emit wg_rise " .. tostring(rise))', 1, true), "what is snapped is told")
        assert(s:find('widgets_say("emit wg_press " .. tostring(k))', 1, true), "Return presses it")
        assert(s:find("below.grid_slot(S.widget_list)", 1, true), "typed: the grid's first match")
        assert(read("shell/mooi-widgets.plm"):find("event wg_press ->", 1, true))
        local f = read("shell/lib/wbelow_feed.luau")
        assert(f:find('on("wg_press"', 1, true), "the widgets answer")
        for _, k in ipairs({ "nowplaying", "launch", "notices", "wallpapers", "settings", "timer" }) do
            assert(f:find("PRESS." .. k .. " = ", 1, true) or f:find("PRESS%." .. k), k .. " has a press")
        end
        assert(f:find('say_mooi("emit open_wallpaper")', 1, true), "Return on the wallpapers opens the picker")
    end)
    test("the Overview's title sits at the canvas' foot, clear of the widgets' edit bar", function()
        local plm = read("shell/mooi-surface.plm")
        assert(plm:find('text "THE SUBSURFACE" { at: op_x + sf_ovm + 24, op_y + op_h - sf_ovm - 44;', 1, true), "the title")
        assert(not plm:find("op_y + sf_ovm + 48", 1, true), "not under the edit bar")
    end)
end

section("push up from below: the decisions (D217)")
do
    local skin = require("lib/surface/skin")
    local W = require("lib/widgets")
    local ws = {
        { id = "np", kind = "nowplaying", x = 100, y = 100, w = 360, h = 140, options = {} },
        { id = "nc", kind = "notices", x = 1400, y = 600, w = 360, h = 260, options = { meet = "still" } },
        { id = "nc2", kind = "notices", x = 900, y = 600, w = 360, h = 260, above = true },
        { id = "vz", kind = "visualiser", x = 500, y = 300, w = 400, h = 120 },
        { id = "ck", kind = "clock", x = 20, y = 20, w = 200, h = 80, options = { meet = "moves" } },
        { id = "wx", kind = "weather", x = 20, y = 300, w = 200, h = 80 },
    }
    test("meet: each kind's default, the option, still for the rest, above for one kept above", function()
        eq(skin.meet(ws[1]), "woven"); eq(skin.meet(ws[2]), "still"); eq(skin.meet(ws[3]), "above")
        eq(skin.meet(ws[4]), "moves"); eq(skin.meet(ws[5]), "moves"); eq(skin.meet(ws[6]), "still")
        eq(skin.meet({ kind = "nowplaying", options = { meet = "moves" } }), "woven", "a value the kind has not: its default")
    end)
    test("meet is an option of the four kinds, a word it knows", function()
        for k, v in pairs({ nowplaying = "woven", notices = "woven", visualiser = "moves", clock = "moves" }) do
            eq(W.OPTIONS[k].meet, v, k)
        end
        eq(W.option_string("meet", "still"), "still"); eq(W.option_string("meet", "woven"), "woven")
        eq(W.option_string("meet", "sideways"), nil)
        eq(W.OPTIONS.weather.meet, nil, "the rest have none")
    end)
    test("target: the first of the kind below that meets that way, on the screen (the bar added)", function()
        local b = skin.target(ws, "nowplaying", "woven", 34)
        eq(b.x, 100); eq(b.y, 134); eq(b.w, 360); eq(b.h, 140)
        eq(skin.target(ws, "notices", "woven", 34), nil, "still, and the other is kept above")
        eq(skin.target(ws, "visualiser", "moves", 0).x, 500)
        eq(skin.target({}, "clock", "moves", 0), nil)
        eq(skin.target(nil, "clock", "moves", 0), nil)
    end)
    test("words: the song or the notice, short", function()
        eq(skin.words("nowplaying", { title = "Teardrop", artist = "Massive Attack" }), "Teardrop — Massive Attack")
        eq(skin.words("nowplaying", { title = "Teardrop" }), "Teardrop")
        eq(skin.words("notices", { app = "Signal", title = "Dinner?" }), "Signal · Dinner?")
        local long = skin.words("notices", { app = "A", title = string.rep("x", 100) })
        assert(#long <= 64 and long:sub(-3) == "…", "an ellipsis")
        eq(skin.words("notices", {}), "")
    end)
    test("queue: one at a time; a burst waits as one, counted", function()
        local q = skin.queue()
        eq(skin.push(q, { kind = "notices", words = "a" }), true, "the first starts")
        eq(skin.push(q, { kind = "notices", words = "b" }), false)
        eq(skin.push(q, { kind = "notices", words = "c" }), false)
        eq(skin.push(q, { kind = "notices", words = "d" }), false)
        local nx = skin.done(q)
        eq(nx.words, "d", "the newest"); eq(nx.n, 3, "three merged")
        eq(skin.done(q), nil, "then nothing"); eq(q.busy, false)
        eq(skin.push(q, { kind = "nowplaying", words = "s" }), true, "free again")
    end)
    local clients = {
        { mapped = true, hidden = false, workspace = { id = 1 }, at = { 1900, 0 }, size = { 1020, 1080 }, class = "kitty", title = "~", fullscreen = 0, address = "0x1" },
        { mapped = true, hidden = false, workspace = { id = 1 }, at = { 1920 + 40, 600 }, size = { 400, 300 }, class = "org.signal.Signal", title = "Signal", fullscreen = 0, address = "0x2" },
        { mapped = true, hidden = false, workspace = { id = 2 }, at = { 2000, 0 }, size = { 500, 500 }, class = "firefox", title = "Firefox", fullscreen = 2, address = "0x3" },
    }
    local mon = { x = 1920, y = 0 }
    test("rects: the active workspace's windows, on this monitor's coordinates", function()
        local r = skin.rects(clients, 1, mon)
        eq(#r, 2); eq(r[1].x, -20); eq(r[2].x, 40); eq(r[2].y, 600)
        eq(skin.fullscreen(clients, 1), false); eq(skin.fullscreen(clients, 2), true)
    end)
    test("spark: the widget's middle, or the nearest edge when a window covers it, or the top right", function()
        local scr = { w = 1920, h = 1080 }
        local p = skin.spark({ x = 1400, y = 100, w = 200, h = 100 }, skin.rects(clients, 1, mon), scr)
        eq(p.x, 1500); eq(p.y, 150)
        local q = skin.spark({ x = 100, y = 600, w = 200, h = 100 }, skin.rects(clients, 1, mon), scr)
        eq(q.x, 14, "covered: the left edge is nearest"); eq(q.y, 650)
        local r = skin.spark(nil, {}, scr)
        eq(r.x, 1906); eq(r.y, 14)
    end)
    test("window_for: the sender's window by class or title, else the focused one, else none", function()
        local w = skin.window_for("Signal", clients, 1, mon, "0x1")
        eq(w.x, 40); eq(w.w, 400)
        local f = skin.window_for("Discord", clients, 1, mon, "0x1")
        eq(f.x, -20, "no match: the focused window")
        eq(skin.window_for("Discord", clients, 1, mon, nil), nil, "nothing focused here")
        eq(skin.window_for("Signal", {}, 1, mon, nil), nil)
    end)
    test("edge_point: where the line from the spark meets the window's border", function()
        local p = skin.edge_point({ x = 0, y = 500 }, { x = 400, y = 300, w = 400, h = 400 })
        eq(p.x, 400); eq(p.y, 500)
        local q = skin.edge_point({ x = 600, y = 0 }, { x = 400, y = 300, w = 400, h = 400 })
        eq(q.x, 600); eq(q.y, 300)
    end)
    test("side: which side of the window the line met (the border's trace starts there)", function()
        local r = { x = 400, y = 300, w = 400, h = 400 }
        eq(skin.side({ x = 600, y = 300 }, r), 0); eq(skin.side({ x = 800, y = 500 }, r), 1)
        eq(skin.side({ x = 600, y = 700 }, r), 2); eq(skin.side({ x = 400, y = 500 }, r), 3)
    end)
    test("hour: the sweep comes when the hour turns", function()
        eq(skin.hour("09:59", "10:00"), true); eq(skin.hour("10:00", "10:01"), false)
        eq(skin.hour(nil, "10:00"), false, "the first reading is not a turn"); eq(skin.hour("23:59", "00:00"), true)
    end)
end

section("push up from below: the logic (D217)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    test("light: guarded — Surface on, the opening shut, no window fullscreen; the push and the trace each a setting", function()
        local l = read("shell/lib/surface/light.luau")
        assert(l:find("local function may() return su().on == true and not ctx.open() and not full end", 1, true))
        assert(l:find("su().push == false", 1, true) and l:find("su().trace ~= false", 1, true) and l:find("s.ping == false", 1, true))
        assert(l:find("if skin.fullscreen(clients, ws) or not may() then", 1, true), "no light over a fullscreen window")
        assert(not l:find("sys.watch", 1, true), "one watcher per service: it watches nothing itself")
        assert(l:find("fact.lt_tt, fact.lt_bt = 0, win and 1 or 0", 1, true), "reduced motion: the border lit at once, no travel")
        assert(l:find('on("lt_go", function() run("mooi", { "nexus" }', 1, true), "the spark opens the notices")
    end)
    test("mooi-surface hands its watchers' news to it", function()
        local s = read("shell/mooi-surface.luau")
        assert(s:find('SK = require("lib/surface/light")(', 1, true))
        for _, h in ipairs({ "SK.song(S.r.music)", "SK.notice(first)", "SK.news(S.r.notifications.count)", "SK.clock(c.time)", "SK.window(w)", "SK.refresh()", "SK.opening(" }) do
            assert(s:find(h, 1, true), h)
        end
    end)
    test("settings: the push and the light's travel, on by default", function()
        local d = require("lib/config").defaults().surface
        eq(d.push, true); eq(d.trace, true)
    end)
end

section("push up from below: the scene (D217)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    local function block(plm, name)
        local a = plm:find("    surface " .. name .. " {", 1, true); assert(a, name)
        return plm:sub(a, plm:find("\n    }\n", a, true))
    end
    test("skin: over the wallpaper, under the windows, only while something reaches up and the opening is shut", function()
        local plm = read("shell/mooi-surface.plm")
        local sk = block(plm, "skin")
        assert(sk:find("level: bottom", 1, true) and sk:find("keyboard: none", 1, true))
        assert(sk:find("open: not op_vis and (lw_on or (sf_on and (sk_on or pu_on)))", 1, true), "nothing while the opening shows")
        assert(not sk:find("zone", 1, true), "it catches nothing")
        assert(sk:find("shader: bulge, pu_b,", 1, true) and sk:find("text pu_words", 1, true), "the bulge and its words")
        -- (D219: the moving wallpaper and the hour's sweep are Live wallpaper's, one pass per effect)
        for _, k in ipairs({ "ripple", "breathe", "flow", "sweep" }) do
            assert(sk:find("show: lw_" .. k .. "\n", 1, true) and sk:find("shader: skin, lw_speed + min(0.999, ", 1, true), k)
        end
        assert(sk:find("min(0.999, sk_swp)", 1, true) and sk:find("min(0.999, max(lv.level, lw_boost))", 1, true), "the sweep's place; the music (or Try it)")
        assert(sk:find("shader aura { at: sk_mx - 220, sk_my - 220; size: 440, 440;", 1, true), "the glow, a patch round the thing")
        assert(sk:find("show: pu_plate", 1, true), "high contrast: a plate under the words")
        assert(plm:find('shader bulge = file "shaders/bulge.wgsl"', 1, true) and plm:find('shader skin = file "shaders/skin.wgsl"', 1, true))
        assert(io.open("shell/shaders/bulge.wgsl") and io.open("shell/shaders/skin.wgsl"), "the shaders")
    end)
    test("light: over the windows, but every click goes through except on the spark", function()
        local plm = read("shell/mooi-surface.plm")
        local lt = block(plm, "light")
        assert(lt:find("level: overlay", 1, true) and lt:find("open: lt_on", 1, true) and lt:find("keyboard: none", 1, true))
        local n = 0
        for _ in lt:gmatch("zone ") do n = n + 1 end
        eq(n, 1, "one zone: the spark's")
        assert(lt:find("on press lt_z { emit lt_go }", 1, true))
        assert(plm:find("event lt_go ->", 1, true))
        for _, f in ipairs({ "lt_sx", "lt_tx", "lt_rx", "lt_rw", "lt_n", "lt_so", "pu_x", "lw_ripple_x", "lw_sweep_p", "sk_swt", "sk_swv" }) do
            assert(plm:find("fact " .. f .. " = ", 1, true), f)
        end
    end)
end

section("push up from below: settings and the editor (D217)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    test("the editor: each kind that meets the wallpaper has its switch", function()
        local ui = read("shell/ui/widgets.plm")
        assert(ui:find('"PUSHES UP THROUGH THE PICTURE", wg_omeet, base + if(wg_omeet, 944, 945)', 1, true))
        assert(ui:find('"MOVES THE WALLPAPER", wg_omeet, base + if(wg_omeet, 944, 945)', 1, true))
        local l = read("shell/mooi-widgets.luau")
        assert(l:find('W.set_option(doc, w.id, "meet", val == 45 and W.OPTIONS[w.kind].meet or "still")', 1, true))
        assert(l:find('fact.wg_omeet = o.meet ~= "still"', 1, true))
    end)
    test("settings: push and trace rows, their slots appended", function()
        local g = read("tools/gen-settings.py")
        assert(g:find('"herdr.focus_on_open",\n    # D217: push up from below. Appended.\n    "surface.push", "surface.trace",', 1, false) or
               g:find('"surface.push", "surface.trace",', 1, true), "appended")
        local a = g:find('"herdr.focus_on_open",', 1, true); local b = g:find('"surface.push", "surface.trace",', 1, true)
        assert(a and b and b > a, "after the last slot")
        assert(g:find('"surface.push", "sv_surface_push"', 1, true) and g:find('"surface.trace", "sv_surface_trace"', 1, true))
        assert(not g:find('"surface.ping", "sv_surface_ping", "sv_surface_glow > 0.5"', 1, true), "the ping no longer waits on the glow")
    end)
end

section("the opening follows the pointer (D218)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    test("mooi-surface reads the pointer from Hyprland while Super is held, a tenth of a second apart, one at a time", function()
        local l = read("shell/mooi-surface.luau")
        assert(l:find("local function poll_pointer()", 1, true))
        assert(l:find("if SF.dragging then return end", 1, true), "a drag freezes the hole")
        assert(l:find("if SF.polling and SF.clock - SF.poll_at < 500 then return end", 1, true), "never two at once (a lost one given up)")
        assert(l:find("if SF.clock % 100 == 0 then poll_pointer() end", 1, true), "every 100 ms of the reveal's tick")
        assert(l:find("opening.move(SF.op, boxes(), SF.ptr, bar_h(), SF.clock)", 1, true), "with the clock: resting hugs, passing follows")
        assert(l:find("SF.mox, SF.moy", 1, true), "the monitor's origin taken off")
    end)
end

section("widgets: a switch turned off stays off (D218)")
do
    local W = require("lib/widgets")
    test("an option whose default is on, saved off, is read back off", function()
        local t = { version = 2, widgets = {
            { id = "ct-1", kind = "controls", layout = "row", x = 10, y = 10, w = 452, h = 80, options = { power_confirm = false, wifi = false } },
            { id = "np-1", kind = "nowplaying", layout = "sleeve", x = 10, y = 200, w = 432, h = 152, options = { lyrics = false } } } }
        local doc = W.parse("x", decode_table(t), { w = 1920, h = 1080 })
        local ct, np
        for _, w in ipairs(doc.widgets) do if w.kind == "controls" then ct = w elseif w.kind == "nowplaying" then np = w end end
        eq(ct.options.power_confirm, false, "power asks once"); eq(ct.options.wifi, false, "wi-fi hidden")
        eq(ct.options.bt, true, "the rest keep their default"); eq(np.options.lyrics, false, "no lyric line")
    end)
end

section("live wallpaper: the decisions (D219)")
do
    local skin = require("lib/surface/skin")
    test("live: the settings read whole and clamped; the four effects with their defaults", function()
        local L = skin.live({})
        eq(L.on, true); eq(L.where, "widgets"); eq(L.speed, 100)
        eq(L.fx.ripple.on, true); eq(L.fx.ripple.strength, 60); eq(L.fx.breathe.strength, 40)
        eq(L.fx.flow.on, false); eq(L.fx.sweep.on, true); eq(L.fx.flow.blend, 70)
        local M = skin.live({ live = { on = false, where = "whole", speed = 999, ripple = { strength = -5, size = 101 }, sweep = { on = false } } })
        eq(M.on, false); eq(M.where, "whole"); eq(M.speed, 200)
        eq(M.fx.ripple.strength, 0); eq(M.fx.ripple.size, 100); eq(M.fx.sweep.on, false)
        eq(skin.live({ live = { where = "sideways" } }).where, "widgets", "an unknown place: the default")
        eq(skin.live(nil).on, true)
    end)
    test("pack: an effect's kind, strength, size and blend in one number a shader can read whole", function()
        eq(skin.pack(1, 60, 50, 50), 1605050)
        eq(skin.pack(4, 100, 100, 100), 4999999, "100 is read as 99")
        eq(skin.pack(2, 0, 0, 0), 2000000)
        assert(skin.pack(4, 100, 100, 100) < 2 ^ 24, "under float32's whole numbers")
    end)
    test("covered: how much of the screen the windows hide", function()
        local scr = { w = 1920, h = 1080 }
        eq(skin.covered_share({}, scr), 0)
        eq(skin.covered_share({ { x = 0, y = 0, w = 1920, h = 1080 } }, scr), 1)
        local half = skin.covered_share({ { x = 0, y = 0, w = 960, h = 1080 } }, scr)
        assert(half > 0.45 and half < 0.55, "half: " .. half)
        local two = skin.covered_share({ { x = 0, y = 0, w = 960, h = 1080 }, { x = 900, y = 0, w = 1020, h = 1080 } }, scr)
        eq(two, 1, "overlapping windows are not counted twice")
    end)
    test("reach: how far round a widget an effect's patch goes, by its size", function()
        eq(skin.reach(0), 20); eq(skin.reach(50), 160); eq(skin.reach(100), 300)
    end)
end

section("live wallpaper: its own page (D219)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    test("settings: a page of its own — on, where, speed, Try it, and each effect's strength, size and blend", function()
        local d = require("lib/config").defaults().live
        eq(d.on, true); eq(d.where, "widgets"); eq(d.speed, 100); eq(d.flow.on, false); eq(d.ripple.strength, 60)
        local g = read("tools/gen-settings.py")
        assert(g:find('("Live wallpaper", "Live wallpaper",', 1, true), "its page")
        for _, k in ipairs({ "ripple", "breathe", "flow", "sweep" }) do
            for _, f in ipairs({ "on", "strength", "size", "blend" }) do assert(g:find('"live.' .. k .. '.' .. f .. '"', 1, true), k .. "." .. f) end
        end
        assert(g:find('"Try it", "live_try", 0', 1, true))
        assert(read("shell/mooi-settings.luau"):find('"emit lw_try"', 1, true), "Try it reaches mooi-surface")
        assert(read("shell/mooi.luau"):find("settings.live.on ~= false then return true end", 1, true), "it runs with the Subsurface off")
    end)
end

section("live wallpaper: the logic (D219)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    test("it rests while off, the opening shows, a window is fullscreen, reduced motion, or windows cover the whole picture", function()
        local l = read("shell/lib/surface/light.luau")
        assert(l:find("local resting = not L.on or ctx.open() or full or reduced() or (whole and covered >= 0.9)", 1, true))
        assert(l:find('if k == "ripple" or k == "breathe" then wants = wants and (playing or trying)', 1, true), "the music drives them")
        assert(l:find('elseif k == "sweep" then wants = wants and (sweeping or trying) end', 1, true), "the hour, or Try it")
        assert(l:find('on("lw_try"', 1, true), "Try it")
        assert(l:find("skin.covered_share(skin.rects(clients, ws, mon), ctx.scr())", 1, true), "how much the windows hide")
        assert(l:find("if su().on ~= true and not skin.live(ctx.settings()).on then return end", 1, true), "asked only while something needs it")
        assert(read("shell/mooi-surface.luau"):find("    if SK then SK.window(w) end", 1, true))
    end)
end

section("the opening shows what lives below awake; the Overview edits (D220)")
do
    local function read(p) local f = assert(io.open(p)); local t = f:read("a"); f:close(); return t end
    test("inside the opening a widget below is awake: never at its rest (hidden or faded), never dimmed by the ambient rest", function()
        local plm = read("shell/mooi-widgets.plm")
        assert(plm:find("let opn = sf_on and op_vis and not w.above and not editing and not wg_desk", 1, true), "the loop")
        assert(plm:find("show: editing or wg_dkp > 0.01 or ((w.st < 1.5 or opn) and fo > 0.01)", 1, true), "shown though at rest")
        for _, p in ipairs({ "nl", "wh", "ln", "nc", "ct" }) do
            assert(plm:find("let " .. p .. "_opn = sf_on and op_vis and not " .. p .. "_above and not editing and not wg_desk", 1, true), p)
        end
        for _, L in ipairs({ "lA", "lB", "lC" }) do
            assert(plm:find("let " .. L .. "_opn = sf_on and op_vis and not " .. L .. "_above and not editing and not wg_desk", 1, true), L)
        end
    end)
    test("in the Overview (edit mode under an opening) a widget is moved like anywhere else", function()
        local plm = read("shell/mooi-widgets.plm")
        assert(plm:find("on drag mv while wg_hold == 100 + k and not w.locked and (not op_vis or editing) {", 1, true))
        assert(plm:find("on release mv while wg_hold == 100 + k and op_vis and not editing { wg_hold = 0; emit sb_drop(-1) }", 1, true),
               "the release that ends a below-drag leaves an edit drag alone")
    end)
end

section("surface: review fixes (D208)")
do
    local function read(p) local f = io.open(p); local t = f:read("a"); f:close(); return t end
    local RV = require("lib/surface/reveal")
    test("review I2: a release before any stage is a tap, at any age; an up without a down is a tap", function()
        local st = RV.state(); RV.down(st, 0)
        eq(RV.up(st, 400), "tap", "stage 0 though past the delay (no tick yet)")
        eq(RV.up(RV.state(), 10), "tap", "the down never arrived (Hyprland's two processes raced)")
    end)
    test("review C1/I1: off by default; a tap always reaches the Pill; the keyboard only from the hub", function()
        eq(require("lib/config").defaults().surface.on, false, "Surface waits for the owner to switch it on")
        local l = read("shell/mooi-surface.luau")
        assert(l:find("local function tap()", 1, true), "one tap path")
        assert(l:find("if not surface_on() then tap(); return end", 1, true), "off: Super's release is the old tap")
        local plm = read("shell/mooi-surface.plm")
        -- D209: the overlay that grabbed keys and clicks is gone; the edge's keyboard is the opening's own,
        -- only once the opening is firm, and it still catches no clicks
        local a = plm:find("    surface edge {", 1, true); assert(a, "the edge")
        local e = plm:sub(a, plm:find("\n    }\n", a, true))
        assert(e:find("keyboard: exclusive while op_vis and sf_firm", 1, true), "the keyboard only once firm")
        assert(not e:find("zone", 1, true), "no click-catching")
    end)
    test("review I3: a workspace guard only for a change of workspace", function()
        local l = read("shell/mooi-surface.luau")
        assert(l:find("if was_active ~= nil and was_active ~= S.r.workspaces.active and SF_guard then SF_guard(\"workspace\") end", 1, true))
    end)
    test("review I5/M6: the opening shows without a picture; no pow of a negative", function()
        -- D209: the subsurface is ground's own (it draws without any picture); the Aperture's rim still shows
        -- without one, and its hole is clear
        local w = read("shell/shaders/aperture.wgsl")
        assert(w:find("max(pic.a, rimline) * (1.0 - hole)", 1, true)); assert(not w:find("pow(", 1, true))
        assert(read("shell/shaders/ground.wgsl"):find("return vec4<f32>(col, k)", 1, true))
        assert(read("shell/mooi-surface.luau"):find('run("readlink", { "-e"', 1, true), "a missing wallpaper is no path")
    end)
    test("review I6: surface.json is backed up on save and never overwritten when it could not be read", function()
        local l = read("shell/mooi-surface.luau")
        assert(l:find('"surface.json.bak"', 1, true) and l:find("if SF.broken or not S.widgets_migrated then return end", 1, true))
    end)
    test("review I7/M7: no clock running while idle; one watcher on the palette", function()
        local l = read("shell/mooi-surface.luau")
        assert(not l:find("every(50, function() clock_ms", 1, true), "no 20 Hz clock forever")
        local _, n = l:gsub('sys.watch, "files:palette.json"', "")
        eq(n, 1, "one palette watcher")
    end)
end

test("found live: a plain read passes no kind (with an empty one Pleamar answers nothing — settings and surface.json read as empty)", function()
    local f = io.open("shell/mooi-surface.luau"); local l = f:read("a"); f:close()
    assert(l:find('if kind then ok, v = pcall(sys.ask, "files.read", name, kind) else ok, v = pcall(sys.ask, "files.read", name) end', 1, true))
end)

test("found live: the reveal's clock lives in SF (a local declared below tick() was nil inside it)", function()
    local f = io.open("shell/mooi-surface.luau"); local l = f:read("a"); f:close()
    assert(l:find("SF.clock = SF.clock + 50", 1, true) and not l:find("clock_ms", 1, true))
end)

section("bmostate")
local bmostate = require("lib/bmostate")
local bmochat = require("lib/bmochat")
test("a new BMO is awake, has a charge and a mood from brain", function()
    local st = bmostate.new(100)
    eq(st.charge, 0.6, "charge"); eq(st.mood, "happy", "mood"); eq(st.rev, 0, "rev")
    assert(bmostate.view(st, 100).face, "a face")
end)
test("a broken or partial document becomes a usable BMO", function()
    local st = bmostate.normalise({ charge = "x", mood = "nope", rev = -4, reaction = { face = "nope" } }, 50)
    eq(st.charge, 0.6, "charge default"); eq(st.mood, "happy", "mood default"); eq(st.rev, 0, "rev clamped")
    eq(st.reaction.face, nil, "unknown face dropped")
    local fresh = bmostate.normalise("nope", 50)
    eq(fresh.charge, 0.6, "string document gives defaults")
end)
test("five pokes make him grumpy and he says so", function()
    local st = bmostate.new(100)
    for i = 1, 5 do st = bmostate.apply(st, { kind = "poke" }, 100 + i * 0.1) end
    assert(st.grump > 0.3, "grump rose: " .. tostring(st.grump))
    assert(st.reaction.face == "grumpy", "grumpy face")
    assert(st.say.text == "hey!", "he objects")
end)
test("charge steps stay inside 0 and 1, and overcharging makes him dizzy", function()
    local st = bmostate.new(10)
    st.charge = 0.99
    st = bmostate.apply(st, { kind = "charge_step", arg = { delta = 0.5 } }, 11)
    eq(st.charge, 1, "full"); eq(st.reaction.face, "dizzy", "overcharged")
    st = bmostate.apply(st, { kind = "charge_step", arg = { delta = -2 } }, 12)
    eq(st.charge, 0, "empty")
end)
test("left alone he falls asleep, and a pet wakes him", function()
    local st = bmostate.new(0)
    st = bmostate.tick(st, 1300, {}, 0.5, 0.99)
    eq(st.asleep, true, "asleep"); eq(bmostate.view(st, 1300).face, "asleep", "asleep face")
    st = bmostate.apply(st, { kind = "pet" }, 1301)
    eq(st.asleep, false, "awake"); eq(st.mood, "happy", "happy")
end)
test("a reaction outranks the mood until it expires", function()
    local st = bmostate.new(0)
    st = bmostate.apply(st, { kind = "react", arg = { face = "curious", ms = 1000 } }, 10)
    eq(bmostate.view(st, 20).face, "curious", "reaction")
    eq(bmostate.view(st, 1100).face, "happy", "back to mood")
end)
test("unknown intents are refused, not applied", function()
    local st = bmostate.new(0)
    local _, ok, why = bmostate.apply(st, { kind = "launch_missiles" }, 1)
    eq(ok, false, "refused"); eq(why, "unknown intent", "reason")
end)
test("chat keeps the last 24 turns and refuses empty or unknown roles", function()
    local chat = bmochat.new()
    for i = 1, 30 do chat = bmochat.add(chat, "user", "turn " .. i, i) end
    eq(#chat.turns, 24, "trimmed"); eq(chat.turns[1].text, "turn 7", "oldest kept")
    chat = bmochat.add(chat, "user", "", 31)
    eq(#chat.turns, 24, "empty refused")
    chat = bmochat.add(chat, "hacker", "hi", 32)
    eq(#chat.turns, 24, "role refused")
end)

section("herdrfeed")
local herdrfeed = require("lib/herdrfeed")
test("status reads the server block and names every problem", function()
    local up = herdrfeed.status({ server = { running = true, compatible = true, version = "0.9.5", socket = "/tmp/h.sock" } })
    eq(up.running, true, "running"); eq(up.version, "0.9.5", "version"); eq(#up.problems, 0, "quiet")
    local bad = herdrfeed.status({ server = { running = false, compatible = false, restart_needed = true } })
    eq(bad.running, false, "down"); eq(#bad.problems, 3, "three problems")
end)
test("snapshot unwraps the CLI envelope and drops rows with no pane", function()
    local doc = { result = { snapshot = { agents = {
        { pane_id = "w1:p1", agent = "claude", agent_status = "blocked", terminal_title_stripped = "Fix tests", cwd = "/p", workspace_id = "w1", state_change_seq = 9 },
        { agent = "nobody" },
    }, focused_pane_id = "w1:p1" } } }
    local s = herdrfeed.snapshot(doc)
    eq(#s.agents, 1, "one agent"); eq(s.agents[1].terminal_title, "Fix tests", "title"); eq(s.focused, "w1:p1", "focus")
end)
test("groups put blocked first and derive elapsed from seen", function()
    local agents = {
        { pane_id = "w1:p1", agent_status = "working", cwd = "/a" },
        { pane_id = "w1:p2", agent_status = "blocked", cwd = "/b" },
        { pane_id = "w1:p3", agent_status = "idle", cwd = "/c" },
    }
    local seen = { ["w1:p2:blocked"] = 100, ["w1:p1:working"] = 90 }
    local g = herdrfeed.group(agents, 160, seen, { ["w1:p2"] = { branch = "main" } }, { show_idle = true })
    eq(g.attention[1].pane_id, "w1:p2", "blocked first"); eq(g.attention[1].elapsed, 60, "elapsed")
    eq(g.attention[1].branch, "main", "branch"); eq(g.working[1].elapsed, 70, "working elapsed")
end)
test("brief takes the last meaningful line, strips ansi and secrets, and truncates", function()
    local b = herdrfeed.brief("title", "first\n\27[31mworking\27[0m on it\n", 40)
    eq(b, "working on it", "last line clean")
    local sec = herdrfeed.brief("t", "token ghp_abcdef123", 40)
    eq(sec:find("ghp_", 1, true), nil, "secret gone")
    assert(#herdrfeed.brief("t", string.rep("x", 200), 30) <= 30, "truncated")
end)
test("a broken snapshot is a warning, not a crash", function()
    local s = herdrfeed.snapshot("nope")
    assert(herdrfeed.warn({ running = true, compatible = true }, s) ~= nil, "warned")
    eq(herdrfeed.warn({ running = true, compatible = true }, { agents = {} }), nil, "healthy")
end)

section("bmo and herdr: settings and registry (D209/D210)")
test("the two modules sit after the Sigil, on the shelf", function()
    local bl = require("lib/barlayout")
    eq(bl.ORDER[#bl.ORDER - 1], "bmo"); eq(bl.ORDER[#bl.ORDER], "herdr")
    eq(bl.width("bmo", { screen = 1920 }), 64); eq(bl.width("herdr", { screen = 1920 }), 56)
    eq(bl.INDEX.bmo, 33); eq(bl.INDEX.herdr, 34)
    for _, id in ipairs(bl.DEFAULT.left) do assert(id ~= "bmo" and id ~= "herdr") end
    for _, id in ipairs(bl.DEFAULT.right) do assert(id ~= "bmo" and id ~= "herdr") end
end)
test("companion and herdr settings have defaults", function()
    local d = config.defaults()
    eq(d.companion.eyes, true); eq(d.companion.cheek, "Tease"); eq(d.companion.hands, "Balanced")
    eq(d.companion.react.herdr, true); eq(d.companion.react.browser, true)
    eq(d.herdr.path, "herdr"); eq(d.herdr.poll, 3); eq(d.herdr.show_idle, false)
    eq(d.herdr.show_done, false); eq(d.herdr.brief, true); eq(d.herdr.brief_lines, 4)
    eq(d.herdr.focus_on_open, false)
end)
test("the new settings are appended, in one block", function()
    local S = require("lib/setters").SETTERS
    local at = {}; for i, v in ipairs(S) do at[v] = i end
    -- (D217's two follow it: the push and the light's travel)
    -- (D217's two follow it, then D219's nineteen: Live wallpaper)
    assert(at["surface.push"] == at["herdr.focus_on_open"] + 1 and at["surface.trace"] == at["herdr.focus_on_open"] + 2, "D217 after herdr")
    assert(at["live.on"] == at["surface.trace"] + 1 and at["live.sweep.blend"] == #S, "D219 ends the list")
    assert(at["companion.eyes"] and at["companion.eyes"] + 4 == at["companion.react.browser"], "companion block")
    assert(at["herdr.path"] and at["herdr.path"] + 6 == at["herdr.focus_on_open"], "herdr block")
end)
test("the settings window has a Herdr page and the new BMO rows", function()
    local f = io.open("shell/mooi-settings.plm"); local t = f:read("a"); f:close()
    assert(t:find('"Herdr"', 1, true), "the page")
    assert(t:find("sv_herdr_poll", 1, true) and t:find("sv_herdr_brief", 1, true))
    assert(t:find("sv_companion_cheek", 1, true) and t:find("sv_companion_hands", 1, true))
end)
test("both modules are placeable and keep the default row within 1920", function()
    local bl = require("lib/barlayout")
    local ok, why = bl.check_list({ "bmo", "herdr" }, {})
    assert(ok, why)
    local out = barlayout.layout({ left = barlayout.DEFAULT.left, center = barlayout.DEFAULT.center,
        right = barlayout.DEFAULT.right, mode = "islands" }, ctx())
    eq(out.overflow, false, "the default row still fits")
end)

section("bmo shared logic")
local function slurp(p) local f = io.open(p); local t = f:read("a"); f:close(); return t end
test("the bar owns the shared BMO and the desktop only reports its body", function()
    local b = slurp("shell/bar.luau")
    assert(b:find('"bmo-shared.json"', 1, true) and b:find('"bmo-cmd.json"', 1, true), "the shared files")
    assert(b:find('on("bmo_press"', 1, true) and b:find('on("bmo_release"', 1, true), "the hold")
    assert(b:find("bmostate.tick", 1, true) and b:find("bm_publish", 1, true), "the tick and facts")
    local d = slurp("shell/bmo/bmo.luau")
    assert(d:find('"bmo-shared.json"', 1, true) and d:find('"bmo-body.json"', 1, true), "desktop bridge")
    assert(d:find("sys.watch, \"files:bmo-shared.json\"", 1, true), "it follows the bar")
    assert(not d:find("emit nt_bmo_q", 1, true), "the old second chat is retired")
    assert(d:find('"bmo-cmd.json"', 1, true) and d:find('kind = "chat"', 1, true), "it asks the bar")
end)
test("the scene declares the bar face's facts", function()
    local s = slurp("shell/mooi.plm")
    for _, f in ipairs({ "bm_charge", "bm_bond", "bm_mischief", "bm_grump", "bm_asleep", "bm_mood", "bm_hold" }) do
        assert(s:find("fact " .. f .. " ", 1, true) or s:find("fact " .. f .. "=", 1, true), f)
    end
end)

test("the BMO face is a real module, placeable in edit mode", function()
    local s = slurp("shell/mooi.plm")
    assert(s:find("zone box zbmo", 1, true) and s:find("BmoFace(", 1, true), "the face and its zone")
    assert(s:find("follow xs_bmo = x_bmo", 1, true) and s:find("follow ws_bmo = w_bmo", 1, true), "springs")
    assert(s:find("zone box ez_bmo", 1, true) and s:find("on press ez_bmo while bar_edit { ed_press = 33", 1, true), "edit code 33")
    assert(s:find('"BMO"', 1, true) and s:find('"Herdr"', 1, true), "named on the shelf")
end)

test("BMO's island is a landing with care, quick settings and chat", function()
    local s = slurp("shell/mooi.plm")
    assert(s:find("layer life.bmo", 1, true) and s:find("shown while open == bmo", 1, true), "its life")
    assert(s:find("IslandFrame(rv.bmo, 360, 430", 1, true), "the plate")
    for _, z in ipairs({ "bpet", "bplay", "bnap", "bwake", "bcharge", "qeyes", "qmusic", "qcheek", "qhands" }) do
        assert(s:find("zone box " .. z, 1, true), z)
    end
    assert(s:find("input bm_q", 1, true) and s:find("on submit bm_q { emit bmo_chat }", 1, true), "chat")
end)

test("the frame draws BMO's and Herdr's island bodies", function()
    local m = slurp("shell/mooi.luau")
    local i = m:find("local CHASSIS = {", 1, true)
    assert(i, "the chassis list")
    local block = m:sub(i, m:find("}", i, true))
    assert(block:find("bmo = true", 1, true), "BMO's island has a body")
    assert(block:find("herdr = true", 1, true), "Herdr's island has a body")
end)

section("bmo hands")
local bmoact = require("lib/bmoact")
test("tiers are explicit and unknown kinds have none", function()
    eq(bmoact.tier("read_file"), "look"); eq(bmoact.tier("open_url"), "do")
    eq(bmoact.tier("write_file"), "change"); eq(bmoact.tier("launch_missiles"), nil)
end)
test("paths stay under home, secrets are refused, sudo is refused", function()
    local ok, why = bmoact.check({ kind = "read_file", path = "/home/u/notes/a.md" }, "/home/u")
    eq(ok, true); eq(why, "look")
    eq(bmoact.check({ kind = "read_file", path = "/etc/passwd" }, "/home/u"), false)
    eq(bmoact.check({ kind = "read_file", path = "/home/u/.ssh/id_rsa" }, "/home/u"), false)
    eq(bmoact.check({ kind = "run_command", command = "sudo rm -rf /" }, "/home/u"), false)
    eq(bmoact.check({ kind = "run_command", command = "rm -rf /" }, "/home/u"), false)
end)
test("a JSON reply becomes words plus one action", function()
    local said, act = bmoact.parse('{"say":"opening it","action":{"kind":"open_url","url":"https://example.com"}}',
        function() return { say = "opening it", action = { kind = "open_url", url = "https://example.com" } } end)
    eq(said, "opening it"); eq(act.kind, "open_url")
    local plain, none = bmoact.parse("just words")
    eq(plain, "just words"); eq(none, nil)
end)
test("safe do actions become commands, unsafe URLs do not", function()
    local cmd, args = bmoact.command({ kind = "open_url", url = "https://example.com" })
    eq(cmd, "xdg-open"); eq(args[1], "https://example.com")
    eq(bmoact.command({ kind = "open_url", url = "file:///etc/passwd" }), nil)
end)

test("Herdr is a module with an island of agent rows and actions", function()
    local s = slurp("shell/mooi.plm")
    assert(s:find("zone box zhd", 1, true) and s:find("zone box ez_herdr", 1, true), "module and edit zone")
    assert(s:find("on press ez_herdr while bar_edit { ed_press = 34", 1, true), "edit code 34")
    assert(s:find("layer life.herdr", 1, true) and s:find("IslandFrame(rv.herdr, 420, 360", 1, true), "the island")
    for _, z in ipairs({ "hdfocus", "hdattach", "hdrefresh" }) do assert(s:find("zone box " .. z, 1, true), z) end
    local b = slurp("shell/bar.luau")
    assert(b:find('"api", "snapshot"', 1, true) and b:find("herdrfeed.group", 1, true), "the poller")
    assert(b:find('"agent", "focus"', 1, true) and b:find('"agent", "attach"', 1, true), "the actions")
end)

print(string.format("\n%d tests, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
