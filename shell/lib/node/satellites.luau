-- The node's satellites (D226, spec §4, §10, §11). Pure: what deserves a place round the node now, the strongest
-- kept, related ones merged (music and recording become one), arranged on an arc under the node.

local M = { MAX = 6, W = 96, H = 26 }

function M.collect(ctx)
    ctx = ctx or {}
    local out = {}
    local function add(kind, priority, label) out[#out + 1] = { kind = kind, priority = priority, label = label } end
    local music = ctx.playing and not ctx.media_open
    if music and ctx.recording then add("music_rec", 90, "REC · MUSIC")
    else
        if ctx.recording then add("rec", 85, "REC") end
        if music then add("music", 60, tostring(ctx.title or "MUSIC")) end
    end
    if (tonumber(ctx.notices) or 0) > 0 then add("notice", 70, tostring(ctx.notices)) end
    if tonumber(ctx.battery) and ctx.battery <= 15 and not ctx.charging then add("battery", 80, tostring(math.floor(ctx.battery)) .. "%") end
    if ctx.online == false then add("network", 75, "OFFLINE") end
    if ctx.mic then add("mic", 65, "MIC") end
    if ctx.cam then add("cam", 66, "CAM") end
    if ctx.timer then add("timer", 50, tostring(ctx.timer)) end
    table.sort(out, function(a, b) return a.priority > b.priority end)
    return out
end

-- an arc under the node, the strongest in the middle
function M.layout(list, body)
    local out = {}
    local n = math.min(#list, M.MAX)
    local cx = body.x + body.w / 2
    for i = 1, n do
        -- 1 in the middle, then alternating right, left, further out
        local k = i - 1
        local off = (k == 0) and 0 or (math.ceil(k / 2) * ((k % 2 == 1) and 1 or -1))
        local x = cx + off * (M.W + 10) - M.W / 2
        local y = body.y + body.h + 14 + math.abs(off) * 6
        out[i] = { kind = list[i].kind, label = list[i].label, x = x, y = y, w = M.W, h = M.H }
    end
    return out
end

return M
