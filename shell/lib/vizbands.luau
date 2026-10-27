-- The visualisers' styles (the music player overhaul): the six that shell/ui/viz.plm draws, and
-- off. Pure, so tests/unit runs it. The scene picks a style by its place in STYLES (from 0); the
-- bar's own setting (bar.visualizer, older names) maps onto the set.

local M = {}

M.STYLES = { "spectrum", "mirror", "ring", "aurora", "led", "orbit", "off" }

local AT = {}
for i, s in ipairs(M.STYLES) do AT[s] = i - 1 end

-- A style's place for the scene; an unknown one is Mirror (the bar's default).
function M.index(style) return AT[style] or AT.mirror end

-- The one after it, round to the start: what a press on a visualiser's chip asks for.
function M.next(style)
    local i = AT[style] or AT.mirror
    return M.STYLES[(i + 1) % #M.STYLES + 1]
end

-- bar.visualizer's values (D24's names) in the set's words.
local BAR = { bars = "spectrum", mirror = "mirror", dots = "led", line = "aurora", off = "off" }
function M.from_bar(v)
    if BAR[v] then return BAR[v] end
    if AT[v] then return v end
    return "mirror"
end

return M
