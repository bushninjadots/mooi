-- The cover art the media service names (MPRIS `mpris:artUrl`), as something a scene can draw.
-- Pleamar 0.4 hands over the URL as the player wrote it (`file:///…/a%20b.jpg`); 0.7 already gives
-- the path (`/…/a b.jpg`). Both are read here, so every scene draws the cover on either.
local M = {}

-- The local file the cover is in, or nil when it is not a file (empty, or on the web).
function M.path(art)
    if type(art) ~= "string" or art == "" then return nil end
    if string.sub(art, 1, 1) == "/" then return art end
    local rest = string.match(art, "^file://(.*)$")
    if not rest or rest == "" then return nil end
    return (string.gsub(rest, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Whether the cover has to be fetched first.
function M.remote(art)
    return type(art) == "string" and string.match(art, "^https?://") ~= nil
end

return M
