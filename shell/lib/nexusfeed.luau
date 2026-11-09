-- What the bar shares with the Control Nexus (D98), which is a program of its own: the latest
-- notifications (only one program may receive them: the bar's Signal Loom) and the update count.
-- Written as small JSON files in mooi's data folder; pure, so tests/unit runs it. A notification's
-- body never leaves the bar, and under signals.private neither does its title.

local M = {}

function M.ago(secs)
    secs = math.max(0, tonumber(secs) or 0)
    if secs < 60 then return "now" end
    if secs < 3600 then return math.floor(secs / 60) .. " min" end
    if secs < 86400 then return math.floor(secs / 3600) .. " h" end
    return math.floor(secs / 86400) .. " d"
end

-- { count, items = up to 5 { app, title, ago } } from Signal Loom's list (newest first).
function M.feed(list, now, private)
    list = type(list) == "table" and list or {}
    local items = {}
    for i = 1, math.min(5, #list) do
        local n = list[i]
        -- D214: what the Subsurface's Notices hub can do with it — the app's own default, and its first two
        -- actions by label (kept out, like the title, while the signals are private)
        local acts = {}
        if not private then
            for _, a in ipairs(type(n.actions) == "table" and n.actions or {}) do
                if #acts < 2 and type(a) == "table" and type(a.label) == "string" and a.label ~= "" then acts[#acts + 1] = a.label end
            end
        end
        items[i] = { app = tostring(n.app or ""), title = private and "" or tostring(n.title or ""),
                     time = tonumber(n.time) or 0, ago = M.ago((tonumber(now) or 0) - (tonumber(n.time) or 0)),
                     actions = acts, default = n.default == true }
    end
    return { count = #list, items = items }
end

function M.updates_doc(total, text, at)
    return { total = tonumber(total) or 0, text = tostring(text or ""), at = tonumber(at) or 0 }
end

return M
