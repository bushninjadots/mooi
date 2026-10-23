-- Pure helpers for Control Nexus behaviour, kept separate so unit tests can exercise
-- the mapping without invoking a real media player or compositor.

local M = {}

function M.media_action(value)
    local n = tonumber(value)
    if n == 1 then return "PREVIOUS TRACK", "media.previous" end
    if n == 2 then return "NEXT TRACK", "media.next" end
    if n == 0 then return "PLAY / PAUSE", "media.toggle" end
    return nil
end

return M
