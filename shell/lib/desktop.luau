-- The desktop round the bar: Hyprland's look and mooi's keys, as Hyprland's own Lua. Pure, so
-- tests/unit runs it. mooi applies `look()` live (`hyprctl eval`) and writes `file()` where
-- ~/.config/hypr/config/custom/mooi.lua reads it at Hyprland's start, so both last.

local M = {}

-- What each of mooi's keys does: the `bin/mooi` command it runs.
M.ACTIONS = {
    { key = "search", cmd = "toggle", name = "Search" },
    { key = "window", cmd = "window", name = "Window actions" },
    { key = "atlas", cmd = "atlas", name = "Workspace Atlas" },
    { key = "overview", cmd = "overview", name = "Overview" },
    { key = "system", cmd = "system", name = "System controls" },
    { key = "shutter", cmd = "shutter", name = "Window shutter" },
    { key = "settings", cmd = "settings", name = "Settings" },
    { key = "wallpaper", cmd = "wallpaper", name = "Wallpaper studio" },
    { key = "edit", cmd = "edit", name = "Edit the bar" },
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
    if b then decoration = decoration .. string.format(", blur = { enabled = %s, size = %d, passes = %d }", tostring(b[1]), b[2], b[3]) end
    if opacity(d.opacity_active) then decoration = decoration .. string.format(", active_opacity = %.2f", opacity(d.opacity_active)) end
    if opacity(d.opacity_inactive) then decoration = decoration .. string.format(", inactive_opacity = %.2f", opacity(d.opacity_inactive)) end
    local sh = M.shadow(d, pal)
    if sh then decoration = decoration .. ", shadow = { " .. sh .. " }" end
    local parts = { string.format("general = { %s }", general), string.format("decoration = { %s }", decoration) }
    local scrolling = {}
    if column(d) then scrolling[#scrolling + 1] = string.format("column_width = %.2f", column(d)) end
    if FIT[d.column_fit] then scrolling[#scrolling + 1] = string.format("focus_fit_method = %d", FIT[d.column_fit]) end
    if #scrolling > 0 then parts[#parts + 1] = "scrolling = { " .. table.concat(scrolling, ", ") .. " }" end
    local input, touchpad = {}, {}
    if NATURAL[d.mouse_natural] ~= nil then input[#input + 1] = "natural_scroll = " .. tostring(NATURAL[d.mouse_natural]) end
    if mouse_speed(d) then input[#input + 1] = string.format("scroll_factor = %.2f", mouse_speed(d)) end
    if NATURAL[d.touchpad_natural] ~= nil then touchpad[#touchpad + 1] = "natural_scroll = " .. tostring(NATURAL[d.touchpad_natural]) end
    if touch_speed(d) then touchpad[#touchpad + 1] = string.format("scroll_factor = %.2f", touch_speed(d)) end
    if #touchpad > 0 then input[#input + 1] = "touchpad = { " .. table.concat(touchpad, ", ") .. " }" end
    if #input > 0 then parts[#parts + 1] = "input = { " .. table.concat(input, ", ") .. " }" end
    return "hl.config({ " .. table.concat(parts, ", ") .. " })"
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
function M.file(keys, d, pal, mooi, frame, shutter, atlas, session)
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
    out[#out + 1] = "    look = " .. string.format("%q", M.look(d, pal, frame) or "") .. ","
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
end

return M
