-- mooi's theme model: the semantic tokens every island, panel and dialog paints, taken from the
-- one palette the whole shell wears (lib/ferro: the wallpaper's or mooi's own, its finish, its
-- background, the Alert re-light) — then the user's overrides, then validation (completeness and
-- contrast) before anything is shown. Pure: tests/unit runs it under Lua 5.4.
--
-- One palette, so a colour chosen in the settings is the bar's, the islands' and the windows'
-- borders' at once (D27). Applied atomically by the logic: all of the tokens or none of them, and
-- the colours that were showing stay if the new theme does not pass (docs/ARCHITECTURE.md).

local ferro = require("lib/ferro")

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

-- ── From the shell's palette ───────────────────────────────
-- Which Ferrolume role each token is: surfaces are the hull, text is the phosphor (Ferrolume
-- reads light on dark), the second accent is the ember, selection sits on the well.
M.FROM_FERRO = {
    ["bg.primary"] = "hull", ["bg.secondary"] = "hull", ["surface.primary"] = "hull",
    ["surface.elevated"] = "hull_raised", ["border.subtle"] = "trace", ["fg.primary"] = "phos",
    ["fg.secondary"] = "trace_lit", ["fg.muted"] = "muted", ["accent.primary"] = "phos",
    ["accent.secondary"] = "ember", ["status.ok"] = "phos", ["status.error"] = "ember",
    ["focus.ring"] = "trace_lit", ["selection.bg"] = "well",
}

-- The tokens from a resolved Ferrolume palette (`roles`: role → colour), every required pair
-- held to its floor by lightness alone (a surface a step lighter than the ground can take a
-- label below 4.5:1 otherwise). Returns the colours and the tokens it had to hold.
function M.from_ferro(roles)
    local colours = {}
    for _, token in ipairs(M.TOKENS) do colours[token] = roles[M.FROM_FERRO[token]] end
    colours["bg.primary"] = M.blend(roles.ground, roles.hull, 0.5)
    -- Each text token against all of its surfaces at once: held one pair at a time, holding it
    -- against one surface could undo the hold against another (a light base: 4.2:1, refused).
    -- It moves the way its surfaces need (lighter on dark ones), against the hardest of them.
    local needs, order = {}, {}
    for _, pair in ipairs(M.REQUIRED) do
        local fg = pair[1]
        if not needs[fg] then needs[fg] = {}; order[#order + 1] = fg end
        needs[fg][#needs[fg] + 1] = { colours[pair[2]], pair[3] }
    end
    local white, black = { r = 1, g = 1, b = 1 }, { r = 0, g = 0, b = 0 }
    local names = {}
    for _, fg in ipairs(order) do
        local c = colours[fg]
        local short, lum, light = false, 0, 0
        for _, need in ipairs(needs[fg]) do
            if M.contrast(c, need[1]) < need[2] then short = true end
            lum = lum + M.luminance(need[1]); light = math.max(light, M.contrast(white, need[1]) - M.contrast(black, need[1]))
        end
        if short then
            local up = light > 0          -- white reads better on these surfaces than black does
            local h, s = ferro.to_hsl(c)
            local _, _, l = ferro.to_hsl(c)
            for _ = 1, 100 do
                local ok = true
                for _, need in ipairs(needs[fg]) do if M.contrast(c, need[1]) < need[2] + 0.05 then ok = false end end
                if ok or l <= 0 or l >= 1 then break end
                l = up and math.min(1, l + 0.01) or math.max(0, l - 0.01)
                c = ferro.hsl(h, s, l)
            end
            colours[fg] = c
            names[#names + 1] = fg
        end
    end
    table.sort(names)
    return colours, names
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
-- `theme` is the settings section ({ overrides, … }); `roles` the palette lib/ferro resolved.
-- Returns the tokens, notes, and what is wrong with them. Never raises: a theme that does not
-- pass `check` comes back with problems and the caller keeps what is on screen.
function M.resolve(theme, roles)
    theme = type(theme) == "table" and theme or {}
    local notes = {}
    local colours, held = M.from_ferro(roles)
    if #held > 0 then notes[#notes + 1] = "held for contrast: " .. table.concat(held, ", ") end
    local known = {}
    for _, t in ipairs(M.TOKENS) do known[t] = true end
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
        elseif not known[token] then
            notes[#notes + 1] = "override for unknown token " .. token .. "; ignored"
        else
            colours[token] = c
            used[#used + 1] = token
        end
    end
    if #used > 0 then notes[#notes + 1] = "user overrides: " .. table.concat(used, ", ") end
    return colours, notes, M.check(colours)
end

return M
