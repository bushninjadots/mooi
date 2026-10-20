-- mooi's palette in the names other programs' colour templates use: Material's roles, the ones
-- Matugen templates read (`{{colors.surface.default.hex}}`). With these, the user's own templates
-- for Kitty and GTK — and mooi's for Qt — render in mooi's palette (its finish, its base, its
-- presets), not the wallpaper's raw one (D34). Pure, so tests/unit runs it.

local ferro = require("lib/ferro")

local M = {}

-- Material role → the Ferrolume role (or a blend of two) it is drawn from. Surfaces climb from
-- the ground to the raised hull; text is engraved steel; the main colour is the phosphor, the
-- second the trace, the third the ember; errors are the ember too (Ferrolume has one warning hue).
local function mixc(a, b, t)
    return { r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t }
end
M.MAP = {
    surface = "hull", surface_dim = "ground", surface_bright = "hull_raised",
    surface_container_lowest = "ground", surface_container_low = { "ground", "hull", 0.6 },
    surface_container = "hull", surface_container_high = { "hull", "hull_raised", 0.6 },
    surface_container_highest = "hull_raised", surface_variant = "hull_raised",
    background = "ground", on_background = "engrave",
    on_surface = "engrave", on_surface_variant = "muted",
    outline = "trace", outline_variant = "trace_dim",
    primary = "phos", on_primary = "ink", primary_container = "well", on_primary_container = "phos",
    primary_fixed = "phos", primary_fixed_dim = "phos_fill", inverse_primary = "phos_fill",
    secondary = "trace_lit", on_secondary = "ink", secondary_container = "well", on_secondary_container = "trace_lit",
    secondary_fixed = "trace_lit", secondary_fixed_dim = "trace",
    tertiary = "ember", on_tertiary = "ink", tertiary_container = "ember_fill", on_tertiary_container = "ink",
    tertiary_fixed = "ember", tertiary_fixed_dim = "ember_fill",
    error = "ember", on_error = "ink", error_container = "ember_fill", on_error_container = "ink",
    inverse_surface = "engrave", inverse_on_surface = "ground",
    shadow = { "ground", "ground", 0 }, scrim = { "ground", "ground", 0 },
}

M.ANSI = { red = 356, green = 128, yellow = 46, blue = 214, magenta = 300, cyan = 182 }

-- `roles` is a resolved Ferrolume palette (role → { r, g, b }); returns Material role → "#rrggbb".
function M.material(roles)
    local out = {}
    for name, from in pairs(M.MAP) do
        local c
        if type(from) == "table" then c = mixc(roles[from[1]], roles[from[2]], from[3]) else c = roles[from] end
        if c then out[name] = string.lower(ferro.to_hex(c)) end
    end
    out.shadow, out.scrim = "#000000", "#000000"
    -- A terminal needs its eight hues to be told apart (red is an error, green a success),
    -- which a palette of two signal colours cannot give: they are drawn at the phosphor's own
    -- saturation and lightness (so they sit in the palette), at the hues a terminal expects,
    -- and the bright ones a step lighter.
    local _, s, l = ferro.to_hsl(roles.phos)
    s = math.max(0.45, math.min(0.85, s)); l = math.max(0.55, math.min(0.72, l))
    for name, h in pairs(M.ANSI) do
        out["ansi_" .. name] = string.lower(ferro.to_hex(ferro.hsl(h, s, l)))
        out["ansi_bright_" .. name] = string.lower(ferro.to_hex(ferro.hsl(h, s, math.min(0.86, l + 0.12))))
    end
    return out
end

return M
