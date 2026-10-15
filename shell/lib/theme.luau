-- mooi's theme model: the brief's palette, a palette taken from the wallpaper
-- (Matugen), and the user's overrides, resolved into the semantic tokens the scene
-- paints — then validated (completeness and contrast) before anything is shown.
-- Pure: tests/unit runs it under Lua 5.4.
--
-- The brief's pipeline, in order (docs/BRIEF.md §7):
--   wallpaper → palette → semantic tokens → user overrides → validate → contrast → apply
-- Applied atomically by the logic: all of the tokens or none of them, and the colours
-- that were showing stay if the new theme does not pass (docs/ARCHITECTURE.md).

local M = {}

M.VERSION = 1

-- The tokens the scene paints (the brief's semantic roles; mooi's names). Each one is
-- three facts in the scene (r, g, b, 0 to 1) handed to `rgb()`, because that is the
-- one way Pleamar lets the logic hand over a colour that did not exist when the scene
-- was read (docs/11-language-reference.md, `rgb(r, g, b)`).
M.TOKENS = {
    "bg.primary", "bg.secondary", "surface.primary", "surface.elevated",
    "border.subtle", "fg.primary", "fg.secondary", "fg.muted",
    "accent.primary", "accent.secondary", "status.ok", "status.error",
    "focus.ring", "selection.bg",
}

-- The brief's provisional palette: what mooi looks like with `theme.source = fixed`.
-- Contrast of these pairs is recorded in docs/AUDIT.md §7.
M.FIXED = {
    ["bg.primary"] = "#101416",
    ["bg.secondary"] = "#161B1E",
    ["surface.primary"] = "#191F22",
    ["surface.elevated"] = "#22292D",
    ["border.subtle"] = "#2C3539",
    ["fg.primary"] = "#E3E9EB",
    ["fg.secondary"] = "#A3B0B5",
    ["fg.muted"] = "#8A979C",
    ["accent.primary"] = "#A6F3D1",
    ["accent.secondary"] = "#FF925F",
    ["status.ok"] = "#A6F3D1",
    ["status.error"] = "#FF925F",
    ["focus.ring"] = "#A6F3D1",
    ["selection.bg"] = "#2A3A36",
}

-- Which Material role each token comes from, for a Matugen palette. One role each,
-- deliberately: a token that borrowed from two roles could not be blamed for being
-- unreadable. Roles are the ones Matugen 4.x publishes (theme/palette.json.hbs).
M.FROM_MATUGEN = {
    ["bg.primary"] = "surface_dim",
    ["bg.secondary"] = "surface_container_low",
    ["surface.primary"] = "surface_container",
    ["surface.elevated"] = "surface_container_high",
    ["border.subtle"] = "outline_variant",
    ["fg.primary"] = "on_surface",
    ["fg.secondary"] = "on_surface_variant",
    ["fg.muted"] = "outline",
    ["accent.primary"] = "primary",
    ["accent.secondary"] = "error",
    ["status.ok"] = "primary",
    ["status.error"] = "error",
    ["focus.ring"] = "primary",
}

-- `selection.bg` has no role of its own: it is the background with a little of the
-- accent in it. The blend is done here, numerically, so it is validated like the rest.
M.SELECTION_FROM = { base = "bg.primary", accent = "primary", amount = 0.18 }

-- What has to stay readable, and at least this ratio (WCAG 2.1). Below it, the theme
-- is refused whole and the previous one stays on screen.
M.REQUIRED = {
    { "fg.primary", "bg.primary", 4.5 },
    { "fg.primary", "surface.primary", 4.5 },
    { "fg.primary", "surface.elevated", 4.5 },
    { "fg.secondary", "bg.primary", 4.5 },
    { "fg.secondary", "surface.primary", 4.5 },
    { "fg.muted", "bg.primary", 4.5 },
    { "fg.muted", "surface.primary", 4.5 },
    { "fg.muted", "surface.elevated", 4.5 },
    { "accent.primary", "bg.primary", 3.0 },
    { "accent.primary", "surface.primary", 3.0 },
    { "status.error", "surface.primary", 3.0 },
}

-- ── Colours ─────────────────────────────────────────────────
-- A colour here is { r, g, b } with 0 to 1 each, the shape `rgb()` takes.

-- "#rrggbb" → colour, or nil and why not.
function M.hex(s)
    if type(s) ~= "string" then return nil, "not a colour" end
    local r, g, b = string.match(s, "^#(%x%x)(%x%x)(%x%x)$")
    if not r then return nil, "not a colour like #A6F3D1" end
    return {
        r = tonumber(r, 16) / 255,
        g = tonumber(g, 16) / 255,
        b = tonumber(b, 16) / 255,
    }
end

function M.to_hex(c)
    if type(c) ~= "table" then return "?" end
    return string.format("#%02X%02X%02X",
        math.floor((c.r or 0) * 255 + 0.5),
        math.floor((c.g or 0) * 255 + 0.5),
        math.floor((c.b or 0) * 255 + 0.5))
end

function M.blend(a, b, t)
    t = t or 0.5
    return {
        r = a.r + (b.r - a.r) * t,
        g = a.g + (b.g - a.g) * t,
        b = a.b + (b.b - a.b) * t,
    }
end

local function channel(v)     -- sRGB → linear
    if v <= 0.04045 then return v / 12.92 end
    return ((v + 0.055) / 1.055) ^ 2.4
end

function M.luminance(c)
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
end

-- WCAG contrast ratio, 1 to 21.
function M.contrast(a, b)
    local la, lb = M.luminance(a), M.luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

-- ── The palette the wallpaper gave us ───────────────────────
-- `palette` is what theme/palette.json.hbs writes: { version, mode, colours = { role = "#…" } }.
-- Returns the tokens it can fill and what it could not say.
function M.from_palette(palette)
    local roles = type(palette) == "table" and palette.colours or nil
    if type(roles) ~= "table" then return nil, "the palette has no colours" end
    local colours, missing = {}, {}
    for _, token in ipairs(M.TOKENS) do
        if token ~= "selection.bg" then
            local role = M.FROM_MATUGEN[token]
            local c = M.hex(roles[role])
            if c then colours[token] = c else missing[#missing + 1] = role end
        end
    end
    if colours["bg.primary"] and roles[M.SELECTION_FROM.accent] then
        local accent = M.hex(roles[M.SELECTION_FROM.accent])
        if accent then colours["selection.bg"] = M.blend(colours["bg.primary"], accent, M.SELECTION_FROM.amount) end
    end
    if #missing > 0 then
        return nil, "the palette is missing " .. table.concat(missing, ", ")
    end
    return colours
end

-- ── Validation ──────────────────────────────────────────────
-- Every token present, and every required pair readable. `problems` empty means the
-- theme can be applied.
function M.check(colours)
    local problems = {}
    if type(colours) ~= "table" then return { "no theme to check" } end
    for _, token in ipairs(M.TOKENS) do
        if type(colours[token]) ~= "table" then problems[#problems + 1] = token .. " is missing" end
    end
    if #problems > 0 then return problems end
    for _, pair in ipairs(M.REQUIRED) do
        local ratio = M.contrast(colours[pair[1]], colours[pair[2]])
        if ratio < pair[3] then
            problems[#problems + 1] = string.format("%s on %s is only %.1f:1 (needs %.1f:1)",
                pair[1], pair[2], ratio, pair[3])
        end
    end
    return problems
end

-- ── The whole pipeline ──────────────────────────────────────
-- `theme` is the settings section ({ source, overrides }); `palette` is the Matugen
-- file or nil. Returns the tokens, where they came from, and what is wrong with them.
-- Never raises: a missing or broken palette is a note, not an error (the fixed palette
-- is what shows instead); a theme that does not pass `check` comes back with problems
-- and the caller keeps what is on screen.
function M.resolve(theme, palette)
    theme = type(theme) == "table" and theme or {}
    local notes = {}

    local source = theme.source or "fixed"
    local colours = {}
    for _, token in ipairs(M.TOKENS) do colours[token] = M.hex(M.FIXED[token]) end

    if source == "wallpaper" then
        if palette == nil then
            notes[#notes + 1] = "no palette from the wallpaper yet; the fixed palette is showing"
        else
            local from_wallpaper, why = M.from_palette(palette)
            if from_wallpaper then
                colours = from_wallpaper
            else
                notes[#notes + 1] = why .. "; the fixed palette is showing"
            end
        end
    end

    local overrides = type(theme.overrides) == "table" and theme.overrides or {}
    local names, used = {}, {}
    for token in pairs(overrides) do
        if type(token) == "string" then names[#names + 1] = token end
    end
    table.sort(names)     -- the log reads the same way every time
    for _, token in ipairs(names) do
        local c, why = M.hex(overrides[token])
        if not c then
            notes[#notes + 1] = "override " .. token .. ": " .. why .. "; ignored"
        elseif not M.FIXED[token] then
            notes[#notes + 1] = "override for unknown token " .. token .. "; ignored"
        else
            colours[token] = c
            used[#used + 1] = token
        end
    end
    if #used > 0 then notes[#notes + 1] = "user overrides: " .. table.concat(used, ", ") end

    return colours, source, notes, M.check(colours)
end

return M
