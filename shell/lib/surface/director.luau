-- The Sigil's director (D207, spec §3, §5): what each host shows now. Pure. What is happening, in order of
-- weight — a fresh notice, a low battery, a volume change, music — goes to the first host without a source
-- (the Pill first, then the islands left to right); a host left over rests on its own source, or on the next
-- wave-1 source no other host shows. Two hosts never show the same source. Sources read from the bar's feed
-- are skipped when the feed is stale (a dead feed would show yesterday's weather).

local sources = require("lib/surface/sources")

local M = { NOTICE_MS = 6000, VOLUME_MS = 2000, STALE_MS = 30000, LOW = 15, GLYPH_H = 18 }
local FEED = { weather = true, resources = true }

local function height(h) return tonumber(h.h) or (type(h.box) == "table" and tonumber(h.box.h)) or 24 end

-- hosts = { { id, kind, rest, h | box } }; state = { music, notice, battery, volume_at, feed_at, open, hover }
function M.choose(hosts, state, now)
    state = type(state) == "table" and state or {}
    now = tonumber(now) or 0
    local stale = now - (tonumber(state.feed_at) or 0) > M.STALE_MS
    local usable = function(id) return sources.get(id) ~= nil and not (stale and FEED[id]) end
    local order = {}
    for _, h in ipairs(hosts or {}) do if h.kind == "pill" then order[#order + 1] = h end end
    for _, h in ipairs(hosts or {}) do if h.kind ~= "pill" then order[#order + 1] = h end end

    local wants = {}
    if state.notice and now - (tonumber(state.notice.at) or -1e9) < M.NOTICE_MS then wants[#wants + 1] = { "notifications", "notable" } end
    local b = state.battery
    if b and tonumber(b.percent) and b.percent <= M.LOW and not b.charging then wants[#wants + 1] = { "battery", "warning" } end
    if state.volume_at and now - state.volume_at < M.VOLUME_MS then wants[#wants + 1] = { "volume" } end
    if state.music and state.music.playing then wants[#wants + 1] = { "music" } end

    local out, used = {}, {}
    local function give(h, id, event) out[h.id] = { source = id, event = event }; used[id] = true end
    for _, w in ipairs(wants) do
        for _, h in ipairs(order) do
            if not out[h.id] and not used[w[1]] and usable(w[1]) then give(h, w[1], w[2]); break end
        end
    end
    for _, h in ipairs(order) do
        if not out[h.id] then
            if h.rest and not used[h.rest] and usable(h.rest) then give(h, h.rest)
            else
                for _, id in ipairs(sources.WAVE1) do if not used[id] and usable(id) then give(h, id); break end end
            end
        end
        local c = out[h.id]
        if c then
            local hover = type(state.hover) == "table" and state.hover[h.id]
            local open = type(state.open) == "table" and state.open[h.id]
            c.form = height(h) < M.GLYPH_H and "glyph" or (h.kind == "pill" and (hover or open)) and "display" or "compact"
        end
    end
    return out
end

-- A notice is fresh when the feed's newest item is newer than the last one seen. The feed's first read only
-- sets the mark — an empty feed sets it at 0, so the first notice after a clean start still counts (review I3).
-- Returns the new mark, and { at = now } for a fresh notice (or nil).
function M.notice_step(seen, t, now)
    t = tonumber(t)
    if seen == nil then return t or 0, nil end
    if t and t > seen then return t, { at = now } end
    return seen, nil
end

return M
