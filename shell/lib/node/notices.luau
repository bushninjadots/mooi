-- The node's notices (D237): the feed's newest first, gathered by app — one card per app, its newest notice on
-- it and how many more that app has sent — and each card still pointing at the notice it shows, so its action
-- and its dismissal reach the right one. Pure.
--
-- The feed carries who and what, never the body (lib/nexusfeed: no body leaves the bar), and while the signals
-- are private not even the title: such a card says only that something came.

local M = {}

function M.group(list)
    local out, by = {}, {}
    if type(list) ~= "table" then return out end
    for i, n in ipairs(list) do
        if type(n) == "table" then
            local app = tostring(n.app or "")
            local key = app ~= "" and string.lower(app) or ("#" .. i)
            local g = by[key]
            if g then g.count = g.count + 1
            else
                local title = tostring(n.title or "")
                g = { idx = i, app = app ~= "" and app or "Notice", title = title ~= "" and title or "Something new",
                      body = tostring(n.body or ""),
                      actions = type(n.actions) == "table" and n.actions or {}, count = 1 }
                by[key] = g
                out[#out + 1] = g
            end
        end
    end
    return out
end

-- how tall a card opened to be read is: its body's lines (about 52 characters each, at most six) under the title
M.CARD_H, M.LINE_H, M.LINE_CHARS, M.LINES_MAX = 58, 15, 52, 6
function M.open_height(g)
    local b = type(g) == "table" and tostring(g.body or "") or ""
    if b == "" then return M.CARD_H end
    local lines = 0
    for para in (b .. "\n"):gmatch("([^\n]*)\n") do lines = lines + math.max(1, math.ceil(#para / M.LINE_CHARS)) end
    return M.CARD_H + math.min(M.LINES_MAX, lines) * M.LINE_H + 6
end

-- what a card's first line says: the app, and how many it has sent when more than one
function M.label(g) return string.upper(g.app) .. (g.count > 1 and ("  ·  " .. g.count) or "") end

return M
