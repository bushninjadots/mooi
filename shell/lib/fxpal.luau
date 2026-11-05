-- The light the desktop's shaders are drawn in, for both families of them: the workspaces' transition
-- (lib/wsfx) and the windows' opening and closing (lib/wfx). Pure, so tests/unit runs it.
--
-- By default it is the bar's own palette — phosphor, ember and trace, the colours the wallpaper gave
-- it — so a new wallpaper re-lights the shaders with everything else. `palette` is that; `matugen` is
-- the wallpaper's own Matugen scheme as Matugen wrote it (primary, tertiary, secondary), before
-- lib/ferro re-lights it into the bar's roles, so the shaders can follow the picture more closely than
-- the bar does; `custom` is three colours of your own (desktop.fx_phos, fx_ember, fx_trace, any
-- #rrggbb). The other ways are fixed triples. A shader only ever reads three hex strings, so this is
-- the one place a way is chosen.

local M = {}

-- The ways, in the order the settings window offers them.
M.WAYS = { "palette", "phosphor", "amber", "ice", "magenta", "mono", "custom", "matugen" }

-- Each fixed way: { phos, ember, trace } as #rrggbb. `phosphor` is mooi's own (the same three the
-- shaders fall back to when they are handed no palette at all), so picking it is picking the design.
M.FIXED = {
    phosphor = { phos = "#7fcfb6", ember = "#e07b2e", trace = "#3d6a60" },
    amber = { phos = "#f2b26a", ember = "#e0503a", trace = "#6a4a2c" },   -- a warm terminal, a hot second signal
    ice = { phos = "#9fd8ff", ember = "#7f8cff", trace = "#2f4a66" },     -- cold, blue, the second signal violet
    magenta = { phos = "#f0a0d8", ember = "#ff7a5c", trace = "#5c2f52" }, -- acid pink against the ember
    mono = { phos = "#e6e6e6", ember = "#9a9a9a", trace = "#3a3a3a" },    -- no hue at all: the light, and its absence
}

local function colour(s) return type(s) == "string" and string.match(s, "^#%x%x%x%x%x%x$") ~= nil end
-- `b` when it is a colour, `a` otherwise: one unreadable stop is a stop of its own, not all three.
local function pick(a, b) if colour(b) then return b end return a end

-- The three colours for `way`: the palette given when it is `palette` (the bar's, as lib/ferro
-- resolved it); `scheme`'s own roles when it is `matugen` (`scheme` is palette.json, whose
-- `colours.primary`, `.tertiary` and `.secondary` are Matugen's); `own` ({ phos, ember, trace } as
-- #rrggbb, desktop.fx_*) when it is `custom`; a fixed triple otherwise. Anything unreadable — a
-- hand-written settings.json, a palette that has not arrived yet, a scheme with no primary — falls
-- back to the bar's, then to mooi's phosphor, so a shader always has something to draw with.
function M.of(way, pal, own, scheme)
    if way == "custom" then
        local mine = type(own) == "table" and own or {}
        return { phos = pick(M.FIXED.phosphor.phos, mine.phos),
                 ember = pick(M.FIXED.phosphor.ember, mine.ember),
                 trace = pick(M.FIXED.phosphor.trace, mine.trace) }
    end
    local base = (type(pal) == "table" and colour(pal.phos))
        and { phos = pal.phos, ember = pal.ember or pal.phos, trace = pal.trace or pal.phos }
        or M.FIXED.phosphor
    if way == "matugen" then
        local s = type(scheme) == "table" and scheme or {}
        local c = type(s.colours) == "table" and s.colours or s
        return { phos = pick(base.phos, c.primary), ember = pick(base.ember, c.tertiary), trace = pick(base.trace, c.secondary) }
    end
    if way ~= "palette" and M.FIXED[way] then return M.FIXED[way] end
    return base
end

return M
