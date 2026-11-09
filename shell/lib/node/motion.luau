-- The node's motion (D226, spec §8, §12): four personalities as springs, and how far a change overshoots by the
-- animation intensity. The scene declares one spring per personality; the logic picks which one the node follows.

local M = {}

M.ORDER = { "organic", "minimal", "technical", "cyber" }
M.PERSONALITY = {
    organic = { k = 240, d = 17 },   -- soft, elastic
    minimal = { k = 520, d = 42 },   -- fast, restrained
    technical = { k = 640, d = 52 }, -- precise, no bounce
    cyber = { k = 760, d = 26 },     -- quick, a little ragged
}
local OVER = { organic = 0.07, minimal = 0.02, technical = 0, cyber = 0.05 }
local INTENSITY = { calm = 0.5, normal = 1, lively = 1.6 }

-- 0-based, as the scene picks (pick(np, organic, minimal, technical, cyber)); an unknown one is organic
function M.index(p) for i, n in ipairs(M.ORDER) do if n == p then return i - 1 end end; return 0 end
function M.overshoot(p, intensity) return (OVER[p] or OVER.organic) * (INTENSITY[intensity] or 1) end

return M
