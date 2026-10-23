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

function M.format_time(seconds)
    local n = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(n / 3600)
    local minutes = math.floor((n % 3600) / 60)
    local remainder = n % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, remainder)
    end
    return string.format("%02d:%02d", minutes, remainder)
end

function M.media_progress(position, length)
    local duration = math.max(0, tonumber(length) or 0)
    local current = math.max(0, tonumber(position) or 0)
    if duration <= 0 then return 0, 0 end
    if current > duration then current = duration end
    return current, current / duration
end

return M
