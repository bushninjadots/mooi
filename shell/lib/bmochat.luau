-- One chat memory for BMO (D209). The bar owns it; the island, the desktop panel and the Pill render
-- the same turns. Pure, so tests can drive it without Claude, timers or files.

local M = { LIMIT = 24, TEXT_MAX = 4000 }

local function clean(v)
    if type(v) ~= "string" then return "" end
    v = v:gsub("\r\n", "\n"):gsub("\r", "\n")
    if #v > M.TEXT_MAX then v = v:sub(1, M.TEXT_MAX) end
    return v
end

function M.new()
    return { version = 1, turns = {}, busy = false, stream = "", at = 0, session = nil }
end

function M.normalise(doc, now)
    if type(doc) ~= "table" then return M.new() end
    local out = M.new()
    out.busy = doc.busy == true
    out.stream = clean(doc.stream)
    out.at = tonumber(doc.at) or tonumber(now) or 0
    out.session = type(doc.session) == "string" and doc.session or nil
    if type(doc.turns) == "table" then
        for _, turn in ipairs(doc.turns) do
            if type(turn) == "table" and (turn.role == "user" or turn.role == "bmo" or turn.role == "system") then
                out.turns[#out.turns + 1] = { role = turn.role, text = clean(turn.text), at = tonumber(turn.at) or 0 }
            end
        end
    end
    return M.trim(out, M.LIMIT)
end

function M.add(chat, role, text, now)
    if role ~= "user" and role ~= "bmo" and role ~= "system" then return chat end
    text = clean(text)
    if text == "" then return chat end
    chat.turns[#chat.turns + 1] = { role = role, text = text, at = tonumber(now) or 0 }
    chat.at = tonumber(now) or chat.at or 0
    return M.trim(chat, M.LIMIT)
end

function M.trim(chat, n)
    n = math.max(1, math.floor(tonumber(n) or M.LIMIT))
    while #chat.turns > n do table.remove(chat.turns, 1) end
    return chat
end

return M
