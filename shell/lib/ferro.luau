-- Ferrolume colour engine: the bar's nineteen roles, from Ferrolume's fixed palette or from
-- the wallpaper's Matugen roles. Pure: no pleamar globals, so tests/unit runs it under plain
-- Lua 5.4 (written in the subset Lua 5.4 and Luau share).
--
-- Matugen gives Material roles (primary, tertiary, surface_container_lowest, …); Ferrolume
-- needs a phosphor, a counter-signal, near-black hulls, stroke greys and tinted steel. The
-- mapping is not one role to one token: each Ferrolume role is *built* from the palette's
-- hue and then held to the floor the design system promises — text 4.5:1 on the ground,
-- the phosphor 7:1, strokes 3:1, ink 4.5:1 on its fill — by moving lightness only, so the
-- wallpaper's hue always survives. The second signal is chosen, not assumed: the palette's
-- own tertiary or secondary when one stands at least 60° round the wheel from the phosphor,
-- the complement when neither does — so the two signals can always be told apart.

local M = {}

-- Every role, in the order the scene's facts are painted.
M.ROLES = {
    "ground", "hull", "hull_raised", "well", "trace_dim", "trace", "trace_lit",
    "phos", "phos_fill", "ember", "ember_fill", "flare", "muted", "ink",
    "steel_900", "steel_700", "steel_500", "steel_300", "engrave",
}

-- Ferrolume's own palette (tokens.json, Nominal), and its Alert re-light.
M.NOMINAL = {
    ground = "#000000", hull = "#040908", hull_raised = "#071311", well = "#052a25",
    trace_dim = "#1f3833", trace = "#3d6a60", trace_lit = "#6cc9ae", phos = "#7fcfb6",
    phos_fill = "#179a88", ember = "#e07b2e", ember_fill = "#d2691e", flare = "#f4b63c",
    muted = "#5a8a7e", ink = "#04211d",
    steel_900 = "#15191b", steel_700 = "#2a3134", steel_500 = "#4a5459", steel_300 = "#8b979c",
    engrave = "#9aa6ab",
}
M.ALERT = {
    ground = "#000000", hull = "#0a0503", hull_raised = "#120805", well = "#2a1405",
    trace_dim = "#3a2414", trace = "#7a5238", trace_lit = "#f0a050", phos = "#f2b26a",
    phos_fill = "#f0a040", ember = "#ff6a45", ember_fill = "#e0552c", flare = "#ffd36a",
    muted = "#a07258", ink = "#2a0f02",
    steel_900 = "#1b1716", steel_700 = "#342b28", steel_500 = "#594b46", steel_300 = "#9c8b85",
    engrave = "#ab9a94",
}

-- Where the second signal (ember) may come from. `auto` takes the most distinct of the three.
M.SIGNALS = { "auto", "tertiary", "secondary", "complement", "analogous", "triadic" }

-- ── Colour arithmetic ──────────────────────────────────────
function M.hex(s)
    if type(s) ~= "string" then return nil end
    local r, g, b = string.match(s, "^#(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return { r = tonumber(r, 16) / 255, g = tonumber(g, 16) / 255, b = tonumber(b, 16) / 255 }
end

function M.to_hex(c)
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("#%02x%02x%02x", byte(c.r), byte(c.g), byte(c.b))
end

local function lin(v) if v <= 0.04045 then return v / 12.92 end return ((v + 0.055) / 1.055) ^ 2.4 end
function M.luminance(c) return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) end
function M.contrast(a, b)
    local la, lb = M.luminance(a), M.luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

function M.to_hsl(c)
    local mx, mn = math.max(c.r, c.g, c.b), math.min(c.r, c.g, c.b)
    local l = (mx + mn) / 2
    if mx == mn then return 0, 0, l end
    local d = mx - mn
    local s = (l > 0.5) and d / (2 - mx - mn) or d / (mx + mn)
    local h
    if mx == c.r then h = (c.g - c.b) / d + ((c.g < c.b) and 6 or 0)
    elseif mx == c.g then h = (c.b - c.r) / d + 2
    else h = (c.r - c.g) / d + 4 end
    return h * 60, s, l
end

function M.hsl(h, s, l)
    h = (h % 360) / 360
    s = math.max(0, math.min(1, s)); l = math.max(0, math.min(1, l))
    if s == 0 then return { r = l, g = l, b = l } end
    local q = (l < 0.5) and l * (1 + s) or (l + s - l * s)
    local p = 2 * l - q
    local function f(t)
        if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
        if t < 1 / 6 then return p + (q - p) * 6 * t end
        if t < 1 / 2 then return q end
        if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
        return p
    end
    return { r = f(h + 1 / 3), g = f(h), b = f(h - 1 / 3) }
end

function M.mix(a, b, t)
    return { r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t }
end

local function hue_gap(a, b)
    local d = math.abs(a - b) % 360
    return (d > 180) and (360 - d) or d
end

-- Raise (or lower) a colour's lightness, hue and saturation kept, until it holds `ratio`
-- against `against`. Moves away from the ground: lighter on a dark one.
function M.hold(c, against, ratio)
    if M.contrast(c, against) >= ratio then return c end
    local h, s, l = M.to_hsl(c)
    local up = M.luminance(against) < 0.18
    for _ = 1, 100 do
        l = up and (l + 0.01) or (l - 0.01)
        local n = M.hsl(h, s, l)
        if M.contrast(n, against) >= ratio or l <= 0 or l >= 1 then return n end
    end
    return M.hsl(h, s, l)
end

-- ── The mapping ────────────────────────────────────────────
local function from_table(t)
    local out = {}
    for _, role in ipairs(M.ROLES) do out[role] = M.hex(t[role]) end
    return out
end

-- The second signal's hue: the named candidate, or (auto) whichever of tertiary, secondary
-- and the complement stands furthest from the phosphor — so the two signals never blur.
function M.signal_hue(roles, phos_h, which)
    local cands = {}
    local function add(name, c)
        if c then local h, s = M.to_hsl(c); cands[#cands + 1] = { name = name, h = h, s = s } end
    end
    add("tertiary", M.hex(roles.tertiary))
    add("secondary", M.hex(roles.secondary))
    cands[#cands + 1] = { name = "complement", h = (phos_h + 180) % 360, s = 0.8 }
    -- two harmonies of the phosphor's own hue: a neighbour (close, calm) and a third of the wheel
    cands[#cands + 1] = { name = "analogous", h = (phos_h + 40) % 360, s = 0.8 }
    cands[#cands + 1] = { name = "triadic", h = (phos_h + 120) % 360, s = 0.8 }
    if which ~= "auto" then
        for _, c in ipairs(cands) do if c.name == which then return c.h, c.name end end
    end
    -- The wallpaper's own colours first: the palette candidate furthest from the phosphor,
    -- provided it stands at least 60° away and has a hue at all (a near-grey has none).
    -- Only when neither does is the complement invented.
    local best = nil
    for _, c in ipairs(cands) do
        if (c.name == "tertiary" or c.name == "secondary") and c.s > 0.12 and hue_gap(c.h, phos_h) >= 60
            and (best == nil or hue_gap(c.h, phos_h) > hue_gap(best.h, phos_h)) then best = c end
    end
    if best then return best.h, best.name end
    return (phos_h + 180) % 360, "complement"
end

-- Builds the nineteen roles from a Matugen palette's `colours` table. Returns the roles and
-- a note naming what the second signal was taken from, or nil and why.
function M.derive(roles, signal)
    if type(roles) ~= "table" then return nil, "the palette has no colours" end
    local primary = M.hex(roles.primary)
    if not primary then return nil, "the palette has no primary" end
    local black = { r = 0, g = 0, b = 0 }
    local ph, ps = M.to_hsl(primary)
    -- A grey primary (a monochrome scheme) has no hue to speak of — its "hue" is noise, 0°
    -- being red — so the whole bar stays grey and the two signals part by lightness alone.
    -- Otherwise a phosphor is a light: it keeps a little saturation however muted the scheme.
    local mono = ps < 0.1
    local function sat(x) if mono then return 0 end return x end
    ps = sat(math.max(ps, 0.35))
    local eh, from = M.signal_hue(roles, ph, signal or "auto")
    if mono then from = "lightness (a grey palette)" end
    local out = {}
    out.ground = black
    local low = M.hex(roles.surface_container_lowest) or M.hex(roles.surface_dim) or M.hsl(ph, 0.2, 0.06)
    local lowish = M.hex(roles.surface_container_low) or low
    out.hull = M.mix(black, low, 0.35)
    out.hull_raised = M.mix(black, lowish, 0.55)
    out.well = M.hsl(ph, math.min(ps, 0.75), 0.10)
    out.trace_dim = M.hsl(ph, math.min(ps, 0.3), 0.16)
    -- Strokes and muted labels are painted on the hulls, not on the black ground alone: a
    -- palette whose raised hull is not black left `muted` at 4.4:1 and `trace` at 2.8:1 there
    -- (audit 2026-10-29). Hold against both, so the floor holds wherever they are drawn.
    local on_ground = function(c, ratio) return M.hold(M.hold(c, black, ratio), out.hull_raised, ratio) end
    out.trace = on_ground(M.hsl(ph, math.min(ps, 0.28), 0.32), 3.0)
    out.phos = M.hold(M.hsl(ph, ps, math.max(0.62, select(3, M.to_hsl(primary)))), black, 7.0)
    out.trace_lit = on_ground(M.mix(out.phos, black, 0.12), 3.0)
    out.ink = M.hsl(ph, sat(0.7), 0.08)
    out.phos_fill = M.hold(M.hsl(ph, sat(math.min(math.max(ps, 0.55), 0.75)), 0.36), out.ink, 4.5)
    out.ember = M.hold(M.hsl(eh, sat(0.75), 0.55), black, 6.0)
    out.ember_fill = M.hold(M.hsl(eh, sat(0.72), 0.45), out.ink, 4.5)
    out.flare = M.hold(M.hsl((eh + 12) % 360, sat(0.9), 0.62), black, 9.0)
    out.muted = on_ground(M.hsl(ph, math.min(ps, 0.22), 0.42), 4.5)
    -- Steel takes the palette's hue at a whisper, so the metal belongs to the scheme.
    out.steel_900 = M.hsl(ph, sat(0.08), 0.10)
    out.steel_700 = M.hsl(ph, sat(0.08), 0.19)
    out.steel_500 = M.hsl(ph, sat(0.08), 0.32)
    out.steel_300 = M.hsl(ph, sat(0.08), 0.58)
    out.engrave = M.hold(M.hsl(ph, sat(0.08), 0.64), out.steel_700, 4.5)
    return out, from
end

-- Day (D91): the same nineteen roles for a light desktop — paper instead of steel. The roles keep
-- their meaning, not their lightness: the ground is a tinted off-white with raised surfaces whiter
-- still, the phosphor is a deep ink of the palette's hue (6:1 on the ground: a dark colour reads
-- heavier than a light one, so 7:1 would turn it black), fills are deep and `ink` — what is written
-- on a fill — is near-white. `roles` is Matugen's light palette; the dark one works too.
function M.derive_light(roles, signal)
    if type(roles) ~= "table" then return nil, "the palette has no colours" end
    local primary = M.hex(roles.primary)
    if not primary then return nil, "the palette has no primary" end
    local ph, ps = M.to_hsl(primary)
    local mono = ps < 0.1
    local function sat(x) if mono then return 0 end return x end
    ps = sat(math.max(ps, 0.35))
    local eh, from = M.signal_hue(roles, ph, signal or "auto")
    if mono then from = "lightness (a grey palette)" end
    -- Matugen's light surfaces when they are light; otherwise the palette's hue, barely tinted.
    local function surface(name, l)
        local c = M.hex(roles[name])
        if c and M.luminance(c) > 0.6 then return c end
        return M.hsl(ph, sat(0.14), l)
    end
    local out = {}
    out.ground = surface("surface_container", 0.935)
    out.hull = surface("surface_container_low", 0.955)
    out.hull_raised = surface("surface_container_lowest", 0.985)
    local g = out.ground
    out.well = M.hsl(ph, math.min(ps, 0.55), 0.87)
    out.trace_dim = M.hsl(ph, math.min(ps, 0.22), 0.80)
    out.trace = M.hold(M.hsl(ph, math.min(ps, 0.26), 0.60), g, 3.0)
    out.phos = M.hold(M.hsl(ph, ps, math.min(0.42, select(3, M.to_hsl(primary)))), g, 6.0)
    out.trace_lit = M.hold(M.mix(out.phos, g, 0.18), g, 3.0)
    out.ink = M.hsl(ph, sat(0.35), 0.985)
    out.phos_fill = M.hold(M.hsl(ph, sat(math.min(math.max(ps, 0.55), 0.75)), 0.42), out.ink, 4.5)
    out.ember = M.hold(M.hsl(eh, sat(0.75), 0.46), g, 4.5)
    out.ember_fill = M.hold(M.hsl(eh, sat(0.72), 0.44), out.ink, 4.5)
    out.flare = M.hold(M.hsl((eh + 12) % 360, sat(0.9), 0.44), g, 6.0)
    out.muted = M.hold(M.hsl(ph, math.min(ps, 0.18), 0.46), g, 4.5)
    out.steel_900 = M.hsl(ph, sat(0.08), 0.95)
    out.steel_700 = M.hsl(ph, sat(0.08), 0.87)
    out.steel_500 = M.hsl(ph, sat(0.08), 0.72)
    out.steel_300 = M.hsl(ph, sat(0.08), 0.44)
    out.engrave = M.hold(M.hsl(ph, sat(0.10), 0.22), out.steel_700, 4.5)
    return out, from
end

-- The whole decision: which palette, and Nominal or Alert. `source` is the setting
-- theme.source ("fixed" | "wallpaper"), `palette` the Matugen file (or nil), `alert` the
-- battery state. Always returns a complete set: a missing palette is a note, not a gap.
-- ── The palette's finish and the bar's background (`opts`) ───
-- `opts` = { saturation = -50…50, finish = "luminous" | "matte", bg = { kind, colour, light,
-- sat, hue } } (settings theme.saturation, theme.finish, bar.bg*). Applied after the palette is
-- built, to any palette, so the fixed one and the Alert re-light take them too.
local SIGNAL_ROLES = { "phos", "phos_fill", "ember", "ember_fill", "flare", "trace_lit" }
M.BACKGROUNDS = { graphite = "#1a1c1f", navy = "#0d1526", plum = "#1d1023", forest = "#0e1a14", wine = "#22090f", sand = "#d8cbb0",
    -- the industrial set: volcanic glass, gun-blued steel, poured concrete, bead-blasted titanium,
    -- oxidised iron, and the green-black of something that was not built here
    obsidian = "#0a0b0d", gunmetal = "#1b2026", concrete = "#2b2a28", titanium = "#34383c", oxide = "#2a1a14", alien = "#0c1a18" }
-- Each base by day (D91): the same material in daylight — the hue kept, the lightness of paper.
M.LIGHT_BACKGROUNDS = { graphite = "#e8e9eb", navy = "#e3e8f2", plum = "#efe6f1", forest = "#e3eee7", wine = "#f3e4e7", sand = "#efe6d4",
    obsidian = "#ebecee", gunmetal = "#e2e6ea", concrete = "#e9e7e2", titanium = "#e0e3e5", oxide = "#f0e3dc", alien = "#dfeeeb" }

local function scale_saturation(c, k)
    local h, sat, l = M.to_hsl(c)
    return M.hsl(h, math.min(1, sat * k), l)
end

-- The background's colour before its adjustments, or nil for black (the palette as it is).
function M.background(bg, out, palette, light)
    local kind = type(bg) == "table" and bg.kind or "black"
    if kind == "black" then return nil end
    local ph = M.to_hsl(out.phos)
    if kind == "wallpaper" then
        local roles = type(palette) == "table" and palette.colours or {}
        return M.hex(roles.surface_container_low) or M.hex(roles.surface_dim) or M.hsl(ph, 0.25, light and 0.94 or 0.09)
    end
    if kind == "accent" then return M.hsl(ph, 0.45, light and 0.92 or 0.10) end
    if kind == "custom" then return M.hex(bg.colour) or M.hex(light and "#eceef0" or "#101418") end
    if light then return M.hex(M.LIGHT_BACKGROUNDS[kind] or "#eceef0") end
    return M.hex(M.BACKGROUNDS[kind] or "#101418")
end

function M.adjust(out, opts, palette)
    opts = type(opts) == "table" and opts or {}
    local light = opts.mode == "light"
    local k = 1 + (tonumber(opts.saturation) or 0) / 100
    if opts.finish == "matte" then k = k * 0.55 end
    if opts.finish == "neon" then k = k * 1.6 end
    if k ~= 1 then
        for _, role in ipairs(SIGNAL_ROLES) do out[role] = scale_saturation(out[role], k) end
    end
    -- neon: the signals are tubes of light — at least nearly full saturation, lit bright (by day,
    -- the same saturation as a deep ink: a light colour on paper is the one thing that cannot be read)
    if opts.finish == "neon" then
        for _, role in ipairs({ "phos", "ember", "flare", "trace_lit" }) do
            local h, sat, l = M.to_hsl(out[role])
            out[role] = M.hsl(h, math.max(sat, 0.92), light and math.min(l, 0.45) or math.max(l, 0.6))
        end
    end
    if light then
        -- whatever moved them, the signals hold their floor on the paper
        out.phos = M.hold(out.phos, out.ground, 6.0)
        out.ember = M.hold(out.ember, out.ground, 4.5)
        out.flare = M.hold(out.flare, out.ground, 6.0)
        out.trace_lit = M.hold(out.trace_lit, out.ground, 3.0)
    end
    local bg = opts.bg or {}
    local base = M.background(bg, out, palette, light)
    if base then
        local h, sat, l = M.to_hsl(base)
        base = M.hsl(h + (tonumber(bg.hue) or 0), sat * (tonumber(bg.sat) or 100) / 100, l + (tonumber(bg.light) or 0) / 100)
        -- Out of the middle: on a surface between about 9 % and 42 % luminance no text colour reads
        -- 4.5:1 (neither white nor black gets there), so the base goes to the nearer side of that
        -- band, lightness only; its raised surfaces then step away from the band, not into it.
        local bh, bs, bl = M.to_hsl(base)
        local up = M.luminance(base) > 0.2
        for _ = 1, 100 do
            local y = M.luminance(M.hsl(bh, bs, bl))
            if (up and y >= 0.42) or (not up and y <= 0.085) then break end
            bl = up and math.min(1, bl + 0.01) or math.max(0, bl - 0.01)
        end
        base = M.hsl(bh, bs, bl)
        out.ground = base
        out.hull = M.hsl(bh, bs, math.min(1, bl + 0.025))
        out.hull_raised = M.hsl(bh, bs, math.min(1, bl + 0.055))
        out.well = M.mix(out.hull_raised, out.phos_fill, 0.25)
        -- what is read on it keeps its floor against the new ground (a light one darkens it)
        out.phos = M.hold(out.phos, base, light and 6.0 or 7.0)
        out.ember = M.hold(out.ember, base, light and 4.5 or 6.0)
        out.flare = M.hold(out.flare, base, 6.0)
        out.muted = M.hold(out.muted, base, 4.5)
        out.trace = M.hold(out.trace, base, 3.0)
        out.trace_lit = M.hold(out.trace_lit, base, 3.0)
        out.trace_dim = M.hold(out.trace_dim, base, 1.5)
    end
    -- Whatever moved them (a finish, a background, the day), the strokes and muted text keep
    -- their floor on the surface they are painted on, not only on the black ground.
    out.muted = M.hold(out.muted, out.hull_raised, 4.5)
    out.trace = M.hold(out.trace, out.hull_raised, 3.0)
    out.trace_lit = M.hold(out.trace_lit, out.hull_raised, 3.0)
    return out
end

-- Light or dark: `opts.mode` when given, else the palette's own `mode` (bin/mooi decides and stamps
-- it there), so every mooi window that reads the palette turns with the day. By day the fixed
-- palette and the Alert re-light are built the light way from their own two colours.
function M.resolve(source, palette, signal, alert, opts)
    local out, why
    opts = type(opts) == "table" and opts or {}
    if opts.mode == nil then opts.mode = type(palette) == "table" and palette.mode or "dark" end
    local light = opts.mode == "light"
    local function fixed(t)
        if not light then return from_table(t) end
        return (M.derive_light({ primary = t.phos, tertiary = t.ember }, "tertiary"))
    end
    if alert then out, why = fixed(M.ALERT), "alert"
    elseif source == "wallpaper" then
        local roles = type(palette) == "table" and palette.colours or nil
        local derived, from = (light and M.derive_light or M.derive)(roles, signal)
        if derived then out, why = derived, "wallpaper · second signal from " .. from
        else out, why = fixed(M.NOMINAL), "fixed (" .. tostring(from) .. ")" end
    else out, why = fixed(M.NOMINAL), "fixed" end
    if light then why = why .. " · day" end
    return M.adjust(out, opts, palette), why
end

-- The options above, from validated settings (lib/config).
function M.options(s, mode)
    local b = s.bar
    return { saturation = s.theme.saturation, finish = s.theme.finish, mode = mode,
             bg = { kind = b.bg, colour = b.bg_colour, light = b.bg_light, sat = b.bg_sat, hue = b.bg_hue } }
end

return M
