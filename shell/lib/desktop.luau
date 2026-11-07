-- The desktop round the bar: Hyprland's look and mooi's keys, as Hyprland's own Lua. Pure, so
-- tests/unit runs it. mooi applies `look()` live (`hyprctl eval`) and writes `file()` where
-- ~/.config/hypr/config/custom/mooi.lua reads it at Hyprland's start, so both last.

local M = {}

-- What each of mooi's keys does: the `bin/mooi` command it runs.
M.ACTIONS = {
    { key = "search", cmd = "toggle", name = "Search" },
    { key = "window", cmd = "window", name = "Window actions" },
    { key = "overview", cmd = "overview", name = "Overview" },
    { key = "system", cmd = "system", name = "System controls" },
    { key = "shutter", cmd = "shutter", name = "Window shutter" },
    { key = "settings", cmd = "settings", name = "Settings" },
    { key = "wallpaper", cmd = "wallpaper", name = "Wallpapers (the picker)" },
    { key = "player", cmd = "player", name = "Music player" },
    { key = "desk", cmd = "widgets desk", name = "Desk mode (the widgets gathered)" },
    { key = "mode", cmd = "mode", name = "Light or dark" },
    { key = "edit", cmd = "edit", name = "Edit the bar" },
    -- D160: the lock screen at once (`mooi lock`, the same scene hypridle reaches when the session
    -- sits idle): the shell's own key for it, so it is rebindable and shown in Settings → Keys.
    { key = "lock", cmd = "lock", name = "Lock screen" },
    -- D195: Loom / Fold's Accordions (`mooi loom …`; nothing happens in Native mooi)
    { key = "loom_add", cmd = "loom add", name = "Accordion: add the window" },
    { key = "loom_next", cmd = "loom next", name = "Accordion: next layer" },
    { key = "loom_prev", cmd = "loom prev", name = "Accordion: previous layer" },
    { key = "loom_fold", cmd = "loom fold", name = "Accordion: fold or bring back" },
    { key = "loom_open", cmd = "loom open", name = "Accordion: every layer out" },
    { key = "loom_remove", cmd = "loom remove", name = "Accordion: take the window out" },
    { key = "loom_cube", cmd = "loom cube", name = "Make a Cube of this workspace" },      -- D197
    { key = "loom_join", cmd = "loom join", name = "The window joins the Cube" },
    { key = "loom_link", cmd = "loom link", name = "Link windows" },                       -- D200
    { key = "loom_flow", cmd = "loom flow", name = "Link windows as a workflow" },
    { key = "loom_hop", cmd = "loom hop", name = "Hop along a link" },
    { key = "loom_unlink", cmd = "loom unlink", name = "Unlink the window" },
    { key = "stop", cmd = "stop", name = "Stop mooi" },
}

local function rgba(hex, alpha)
    return string.format("rgba(%s%s)", string.gsub(hex, "#", ""), alpha or "ff")
end

-- The colours the window border wears: `theme` the bar's two signals as a gradient, `accent`
-- the phosphor alone; `keep` none at all (Hyprland's own stay). `pal` is { phos, ember, trace }
-- as #rrggbb.
function M.colours(d, pal)
    if d.border_colour == "keep" or not pal then return nil end
    if d.border_colour == "accent" then
        return { active = '"' .. rgba(pal.phos) .. '"', inactive = '"' .. rgba(pal.trace, "88") .. '"' }
    end
    return { active = '{ colors = { "' .. rgba(pal.phos) .. '", "' .. rgba(pal.ember) .. '" }, angle = 45 }',
             inactive = '"' .. rgba(pal.trace, "88") .. '"' }
end

-- Windows and scrolling: each choice's value in Hyprland's own terms. `keep` is absent from
-- every table, so a setting left at `keep` writes nothing and Hyprland's own value stands.
local LAYOUT = { dwindle = "dwindle", master = "master", scrolling = "scrolling", monocle = "monocle" }
local FIT = { fit = 1, center = 0 }                       -- scrolling:focus_fit_method
local NATURAL = { on = true, off = false }
local BLUR = { off = { false, 0, 0 }, light = { true, 3, 2 }, medium = { true, 6, 3 }, heavy = { true, 10, 4 } }
-- Numbers whose lowest value keeps Hyprland's own (lib/config): nil while kept, else the fraction.
local function frac(v, keep) v = tonumber(v); if not v or v <= keep then return nil end; return v / 100 end
local function column(d) return frac(d.column, 9) end
local function touch_speed(d) return frac(d.touchpad_speed, 4) end
local function mouse_speed(d) return frac(d.mouse_speed, 4) end
local function opacity(v) return frac(v, 49) end
local function vibrancy(d) return frac(d.blur_vibrancy, 0) end
local ONOFF = { on = true, off = false }                   -- blur:xray, blur:popups
-- The spring under the windows' animations (Hyprland 0.56 `hl.curve` type spring): mass 1, so how
-- far it overshoots is the damping against 2·√stiffness (critical, no overshoot). `off` is
-- critical; each step after swings further before it settles.
local WOBBLE = { off = { 250, 31.6 }, subtle = { 300, 20 }, wobbly = { 260, 12 }, jelly = { 220, 7 } }
local MOTION_BLUR = { off = 0, soft = 6, strong = 16 }     -- decoration:motion_blur:samples (0: off)
-- Hyprland 0.57's real wobbly windows (decoration:wobble: a spring mesh that bends a window as it is
-- moved or resized): how hard each step wobbles. And its blur variants (decoration:blur:variant). Each
-- is asked for in a call of its own under pcall, so a Hyprland that does not know them yet (0.56) skips
-- them and keeps the rest of the look.
local MESH = { off = false, subtle = { 0.6, 320, 22 }, wobbly = { 1.0, 260, 14 }, jelly = { 1.7, 210, 8 } }
-- Hyprland 0.57 names its plain blur `kawase` and refuses any name it does not list, so the
-- settings' `none` ("Plain") is asked for as kawase; `glass` is a material 0.57 shares between
-- aurora/drops/heat_shimmer/prism rather than a variant of its own, so a saved `glass` asks for
-- acrylic, the liquid-glass look it stood for.
M.VARIANTS = { "acrylic", "aurora", "drops", "fluid_jar", "haze", "heat_shimmer", "ripple", "water" }
local LEGACY_VARIANTS = { none = "kawase", glass = "acrylic" }

-- D157: going from one workspace to the next. Each kind's Hyprland style for the workspace coming
-- in and the one going out (Hyprland 0.57 takes slide, slidevert, slidefade, slidefadevert and fade
-- here; popin and the gnome styles are windows' alone). `column` stacks the workspaces top to bottom,
-- as niri does; `tide` is mooi's own, the two leaves apart: the next one rises in faded while this
-- one dissolves where it stands.
local WS_STYLE = { slide = { "slide", "slide" }, column = { "slidevert", "slidevert" }, glide = { "slidefade 20%", "slidefade 20%" },
                   fade = { "fade", "fade" }, tide = { "slidefadevert 30%", "fade" } }
-- How the move feels: a curve of mooi's own each. `spring` is niri's (critically damped: stiffness
-- 1000 against 2·√1000 ≈ 63, mass 1), `bounce` swings past a little before it settles; `ease` an
-- out-expo bezier, which is also what a chosen style moves by while the feel is kept (`keep`):
-- Hyprland's own `default` is near instant in this desktop's config.
local WS_FEEL = { ease = { bezier = { 0.16, 1, 0.3, 1 } }, spring = { spring = { 1000, 63.2 } }, bounce = { spring = { 700, 32 } } }
-- A touchpad swipe's carry (gestures:workspace_swipe_*): `flick` goes over on a quick, short flick
-- and carries on past the next workspace on a long one; `steady` asks for half the way and a firm push.
local WS_SWIPE = { flick = "workspace_swipe_forever = true, workspace_swipe_cancel_ratio = 0.15, workspace_swipe_min_speed_to_force = 10, workspace_swipe_distance = 250",
                   steady = "workspace_swipe_forever = false, workspace_swipe_cancel_ratio = 0.5, workspace_swipe_min_speed_to_force = 50, workspace_swipe_distance = 450" }
-- The scrolling layout as niri's columns: the widths `colresize +conf/-conf` steps through.
local COLUMN_WIDTHS = { niri = "0.333, 0.5, 0.667, 1.0", halves = "0.5, 1.0", quarters = "0.25, 0.5, 0.75, 1.0" }
local FOLLOW = { on = 1, off = 0 }                         -- scrolling:follow_focus
-- niri's keys for the columns (desktop.column_keys), as Hyprland layout messages. Each is let go
-- first, so applying the look again does not bind a key twice (a press would then resize twice).
M.COLUMN_KEYS = {
    { "SUPER + bracketright", "colresize +conf" }, { "SUPER + bracketleft", "colresize -conf" },
    { "SUPER + equal", "colresize +0.1" }, { "SUPER + minus", "colresize -0.1" },
    { "SUPER + ALT + right", "swapcol r" }, { "SUPER + ALT + left", "swapcol l" },
    { "SUPER + C", "fit active" },
}
local function ws_speed(d) local v = tonumber(d.ws_speed); if not v or v < 1 then return 2 end; return math.floor(v) end
-- The workspaces' animations, as Hyprland calls; nil while kept.
function M.workspaces(d)
    local st = WS_STYLE[d.ws_style]
    if not st then return nil end
    local f = WS_FEEL[d.ws_feel] or WS_FEEL.ease
    local out, curve = {}, nil
    if f and f.bezier then
        out[#out + 1] = string.format('hl.curve("mooi_ws", { type = "bezier", points = { { %.2f, %.2f }, { %.2f, %.2f } } })', f.bezier[1], f.bezier[2], f.bezier[3], f.bezier[4])
        curve = 'bezier = "mooi_ws"'
    elseif f and f.spring then
        out[#out + 1] = string.format('hl.curve("mooi_ws", { type = "spring", mass = 1, stiffness = %d, dampening = %.1f })', f.spring[1], f.spring[2])
        curve = 'spring = "mooi_ws"'
    end
    for i, leaf in ipairs({ "workspaces", "workspacesIn", "workspacesOut" }) do
        local style = (i == 3) and st[2] or st[1]
        out[#out + 1] = string.format('hl.animation({ leaf = "%s", enabled = true, speed = %d, %s, style = "%s" })', leaf, ws_speed(d), curve, style)
    end
    return table.concat(out, "; ")
end
local function variant(d)
    for _, v in ipairs(M.VARIANTS) do if d.blur_variant == v then return v end end
    return LEGACY_VARIANTS[d.blur_variant]
end

-- The windows' shadow as Hyprland's own fields, or nil while kept. `soft` and `deep` are dark;
-- `neon` is a glow in the palette's main colour round the focused window, fainter round the rest.
function M.shadow(d, pal)
    local kind = d.shadow
    if kind == nil or kind == "keep" then return nil end
    if kind == "off" then return "enabled = false" end
    local size = math.floor(tonumber(d.shadow_size) or 14)
    if kind == "neon" and pal and pal.phos then
        return string.format('enabled = true, range = %d, render_power = 2, color = "%s", color_inactive = "%s"',
            size, rgba(pal.phos, "aa"), rgba(pal.phos, "22"))
    end
    local alpha = (kind == "deep") and "dd" or "77"
    return string.format('enabled = true, range = %d, render_power = %d, color = "rgba(000000%s)", color_inactive = "rgba(000000%s)"',
        size, (kind == "deep") and 2 or 3, alpha, (kind == "deep") and "99" or "44")
end

-- Which of Hyprland's settings mooi sets, by name: when one stops being set (back to `keep`),
-- Hyprland has to read its own config again to get its value back.
function M.claims(d)
    if not d.manage then return {} end
    local out = {}
    local function claim(name, on) if on then out[#out + 1] = name end end
    claim("layout", LAYOUT[d.layout]); claim("column", column(d)); claim("column_fit", FIT[d.column_fit])
    claim("touchpad_natural", NATURAL[d.touchpad_natural] ~= nil); claim("touchpad_speed", touch_speed(d))
    claim("mouse_natural", NATURAL[d.mouse_natural] ~= nil); claim("mouse_speed", mouse_speed(d))
    claim("blur", BLUR[d.blur]); claim("opacity_active", opacity(d.opacity_active)); claim("opacity_inactive", opacity(d.opacity_inactive))
    claim("shadow", d.shadow ~= nil and d.shadow ~= "keep")
    claim("blur_vibrancy", vibrancy(d)); claim("blur_xray", ONOFF[d.blur_xray] ~= nil); claim("blur_popups", ONOFF[d.blur_popups] ~= nil)
    claim("wobble", WOBBLE[d.wobble]); claim("motion_blur", MOTION_BLUR[d.motion_blur])
    claim("blur_variant", variant(d))
    claim("ws_style", WS_STYLE[d.ws_style]); claim("ws_feel", WS_STYLE[d.ws_style] and WS_FEEL[d.ws_feel])
    claim("ws_speed", WS_STYLE[d.ws_style] and tonumber(d.ws_speed) and d.ws_speed >= 1)
    claim("ws_swipe", WS_SWIPE[d.ws_swipe]); claim("column_widths", COLUMN_WIDTHS[d.column_widths])
    claim("column_follow", FOLLOW[d.column_follow]); claim("column_wrap", ONOFF[d.column_wrap] ~= nil)
    claim("column_keys", d.column_keys == true)
    return out
end

-- True when every name in `old` is still in `new`.
function M.covers(new, old)
    local have = {}
    for _, n in ipairs(new or {}) do have[n] = true end
    for _, n in ipairs(old or {}) do if not have[n] then return false end end
    return true
end

-- The look, as one `hl.config` call; nil while mooi does not manage the desktop. `frame` is the
-- screen frame's settings: it lies in the windows' outer gap, so while it is on the gap is at
-- least the band and a little air (else the windows cover it and it cannot be seen).
function M.look(d, pal, frame)
    if not d.manage then return nil end
    local gaps_out = d.gaps_out
    if type(frame) == "table" and frame.on then gaps_out = math.max(gaps_out, (tonumber(frame.band) or 6) + 4) end
    local general = string.format("border_size = %d, gaps_in = %d, gaps_out = %d", d.border, d.gaps_in, gaps_out)
    local c = M.colours(d, pal)
    if c then general = general .. ", col = { active_border = " .. c.active .. ", inactive_border = " .. c.inactive .. " }" end
    if LAYOUT[d.layout] then general = general .. string.format(', layout = "%s"', LAYOUT[d.layout]) end
    local decoration = string.format("rounding = %d, dim_inactive = %s", d.rounding, tostring(d.dim_inactive == true))
    local b = BLUR[d.blur]
    local blur = {}
    if b then blur[#blur + 1] = string.format("enabled = %s, size = %d, passes = %d", tostring(b[1]), b[2], b[3]) end
    if vibrancy(d) then blur[#blur + 1] = string.format("vibrancy = %.2f", vibrancy(d)) end
    if ONOFF[d.blur_xray] ~= nil then blur[#blur + 1] = "xray = " .. tostring(ONOFF[d.blur_xray]) end
    if ONOFF[d.blur_popups] ~= nil then blur[#blur + 1] = "popups = " .. tostring(ONOFF[d.blur_popups]) end
    if #blur > 0 then decoration = decoration .. ", blur = { " .. table.concat(blur, ", ") .. " }" end
    local mb = MOTION_BLUR[d.motion_blur]
    if mb then decoration = decoration .. (mb > 0 and string.format(", motion_blur = { enabled = true, samples = %d }", mb) or ", motion_blur = { enabled = false }") end
    if opacity(d.opacity_active) then decoration = decoration .. string.format(", active_opacity = %.2f", opacity(d.opacity_active)) end
    if opacity(d.opacity_inactive) then decoration = decoration .. string.format(", inactive_opacity = %.2f", opacity(d.opacity_inactive)) end
    local sh = M.shadow(d, pal)
    if sh then decoration = decoration .. ", shadow = { " .. sh .. " }" end
    local parts = { string.format("general = { %s }", general), string.format("decoration = { %s }", decoration) }
    local scrolling = {}
    if column(d) then scrolling[#scrolling + 1] = string.format("column_width = %.2f", column(d)) end
    if FIT[d.column_fit] then scrolling[#scrolling + 1] = string.format("focus_fit_method = %d", FIT[d.column_fit]) end
    if COLUMN_WIDTHS[d.column_widths] then scrolling[#scrolling + 1] = string.format("explicit_column_widths = %q", COLUMN_WIDTHS[d.column_widths]) end
    if FOLLOW[d.column_follow] then scrolling[#scrolling + 1] = string.format("follow_focus = %d", FOLLOW[d.column_follow]) end
    if ONOFF[d.column_wrap] ~= nil then scrolling[#scrolling + 1] = "wrap_focus = " .. tostring(ONOFF[d.column_wrap]) end
    if #scrolling > 0 then parts[#parts + 1] = "scrolling = { " .. table.concat(scrolling, ", ") .. " }" end
    local input, touchpad = {}, {}
    if NATURAL[d.mouse_natural] ~= nil then input[#input + 1] = "natural_scroll = " .. tostring(NATURAL[d.mouse_natural]) end
    if mouse_speed(d) then input[#input + 1] = string.format("scroll_factor = %.2f", mouse_speed(d)) end
    if NATURAL[d.touchpad_natural] ~= nil then touchpad[#touchpad + 1] = "natural_scroll = " .. tostring(NATURAL[d.touchpad_natural]) end
    if touch_speed(d) then touchpad[#touchpad + 1] = string.format("scroll_factor = %.2f", touch_speed(d)) end
    if #touchpad > 0 then input[#input + 1] = "touchpad = { " .. table.concat(touchpad, ", ") .. " }" end
    if #input > 0 then parts[#parts + 1] = "input = { " .. table.concat(input, ", ") .. " }" end
    if WS_SWIPE[d.ws_swipe] then parts[#parts + 1] = "gestures = { " .. WS_SWIPE[d.ws_swipe] .. " }" end
    local out = "hl.config({ " .. table.concat(parts, ", ") .. " })"
    -- the spring: a curve of mooi's own, under windows opening (keeping their pop-in) and moving.
    -- An `hl.animation` without a style clears the one set before, so the opening one is given.
    local w = WOBBLE[d.wobble]
    if w then
        out = out .. string.format('; hl.curve("mooi_wobble", { type = "spring", mass = 1, stiffness = %d, dampening = %.1f })', w[1], w[2])
            .. '; hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, spring = "mooi_wobble", style = "popin 87%" })'
            .. '; hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, spring = "mooi_wobble" })'
        local m = MESH[d.wobble]
        if m == false then out = out .. "; pcall(hl.config, { decoration = { wobble = { enabled = false } } })"
        elseif m then
            out = out .. string.format("; pcall(hl.config, { decoration = { wobble = { enabled = true, intensity = %.2f, stiffness = %d, damping = %d, mass = 1 } } })", m[1], m[2], m[3])
        end
    end
    local v = variant(d)
    if v then out = out .. string.format('; pcall(hl.config, { decoration = { blur = { variant = "%s" } } })', v) end
    local ws = M.workspaces(d)
    if ws then out = out .. "; " .. ws end
    if d.column_keys == true then
        for _, k in ipairs(M.COLUMN_KEYS) do
            out = out .. string.format('; pcall(hl.unbind, %q); hl.bind(%q, hl.dsp.layout(%q))', k[1], k[1], k[2])
        end
    end
    return out
end

-- Every bind mooi asks Hyprland for: its keys, and — while the shutter is on and asks for it —
-- Super+Alt+right-click, which opens the shutter on the window under the pointer (D35; Super with
-- the right button alone stays Hyprland's resize, and right-click alone stays the app's).
M.POINTER = "SUPER + ALT + mouse:273"
M.SUPER_TAB = "SUPER + Tab"
function M.binds(keys, shutter, atlas)
    local out = {}
    -- Super+Tab: the Overview, as it is in iNiR and most desktops (atlas.super_tab)
    if type(atlas) == "table" and atlas.super_tab ~= false then out[#out + 1] = { M.SUPER_TAB, "overview" } end
    for _, a in ipairs(M.ACTIONS) do
        if a.key ~= "shutter" or not shutter or shutter.enabled ~= false then out[#out + 1] = { keys[a.key], a.cmd } end
    end
    if type(shutter) == "table" and shutter.enabled ~= false and shutter.pointer ~= false then out[#out + 1] = { M.POINTER, "shutter-here" } end
    return out
end

-- The file custom/mooi.lua reads: a Lua table (no JSON reader there).
-- A touchpad swipe that opens the Overview (D45, atlas.gesture): three or four fingers down —
-- the one direction the desktop's own gestures leave free (sideways: workspaces; up: the special
-- workspace and fullscreen). { fingers, direction, command } each; none while it is off.
function M.gestures(atlas)
    local n = type(atlas) == "table" and ({ three = 3, four = 4 })[atlas.gesture] or nil
    return n and { { n, "down", "overview" } } or {}
end
-- The window rules custom/mooi.lua hands Hyprland for the windows' own shaders (lib/wfx writes the
-- two files beside mooi's keys): a tag for opening and a tag for closing, both `_default` so a rule
-- of your own — `+shader_close:` on one class — takes that half over without touching these.
-- Nothing while the effects are off: a tag is what plays a shader, so no tag is Hyprland's own
-- animation, which is exactly what off is.
function M.window_rules(w)
    if type(w) ~= "table" or type(w.open) ~= "string" or type(w.close) ~= "string" then return {} end
    local out = {
        string.format('{ name = "mooi-window-open", match = { class = ".*" }, tag = %q }', "+shader_open_default:" .. w.open),
        string.format('{ name = "mooi-window-close", match = { class = ".*" }, tag = %q }', "+shader_close_default:" .. w.close),
    }
    -- The apps that keep a pair of their own: the same tags without the suffix, so they win over
    -- the two above however the paths happen to sort (Hyprland keeps tags in a sorted set).
    for _, a in ipairs(type(w.apps) == "table" and w.apps or {}) do
        if type(a.class) == "string" and type(a.open) == "string" and type(a.close) == "string" then
            local name = type(a.name) == "string" and a.name or "app"
            out[#out + 1] = string.format('{ name = %q, match = { class = %q }, tag = %q }',
                "mooi-window-open-" .. name, a.class, "+shader_open:" .. a.open)
            out[#out + 1] = string.format('{ name = %q, match = { class = %q }, tag = %q }',
                "mooi-window-close-" .. name, a.class, "+shader_close:" .. a.close)
        end
    end
    return out
end
function M.file(keys, d, pal, mooi, frame, shutter, atlas, session, window)
    local out = { "-- written by mooi (shell/lib/desktop.luau); read by ~/.config/hypr/config/custom/mooi.lua", "return {",
                  string.format("    mooi = %q,", mooi), "    keys = {" }
    for _, b in ipairs(M.binds(keys, shutter, atlas)) do
        out[#out + 1] = string.format("        { %q, %q },", b[1], b[2])
    end
    out[#out + 1] = "    },"
    out[#out + 1] = "    standalone = " .. tostring(type(session) == "table" and session.standalone == true) .. ","
    out[#out + 1] = "    gestures = {"
    for _, g in ipairs(M.gestures(atlas)) do out[#out + 1] = string.format("        { %d, %q, %q },", g[1], g[2], g[3]) end
    out[#out + 1] = "    },"
    out[#out + 1] = "    window = {"
    for _, r in ipairs(M.window_rules(window)) do out[#out + 1] = "        " .. r .. "," end
    out[#out + 1] = "    },"
    out[#out + 1] = "    look = " .. string.format("%q", M.look(d, pal, frame) or "") .. ","
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
end

return M
