-- The Sigil's bodies (D207, spec §6): in this phase the Sigil body's motion numbers. A temperament sets how
-- far each point wobbles (px), how much it breathes at rest (px), the delay between the batches a change is
-- written in (ms) and how many batches (the line rewriting itself front first). Reduced motion stills it all:
-- one batch, no wobble, no breath. Pure.

local M = {}

local T = {
    calm = { wobble = 1, breath = 1.5, lag_ms = 60, batches = 2 },
    lively = { wobble = 2.5, breath = 2.5, lag_ms = 90, batches = 4 },
    restless = { wobble = 5, breath = 3, lag_ms = 120, batches = 6 },
}

function M.temperament(name, reduced)
    if reduced then return { wobble = 0, breath = 0, lag_ms = 0, batches = 1 } end
    local t = T[name] or T.lively
    return { wobble = t.wobble, breath = t.breath, lag_ms = t.lag_ms, batches = t.batches }
end

-- how the line meets the pointer: pushed away (positive), drawn toward it (negative), or not at all
local P = { push = 1.6, draw = -1.0, ignore = 0 }
function M.pointer(mode) return P[mode] or 0 end

return M
