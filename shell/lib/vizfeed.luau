-- vizfeed: one line of analysis, written by the bar and read by every surface.
--
-- The file is `viz-levels.txt` in the scene's files folder:
--
--   v1 <32 bands 0..1000> <bass> <high> <beat> <phase> <playing> <missing> <seq>
--
-- Fields after the 39th are ignored, so a later version can append; a numeric
-- token in the 40th place is refused because it means a frame with too many
-- bands. `decode` never raises: a partial or unknown line is nil.

local M = {}

M.VERSION = "v1"
M.BANDS = 32
M.FILE = "viz-levels.txt"
M.STALE_MS = 2000

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function int(v, lo, hi)
    return math.floor(clamp(tonumber(v) or 0, lo or 0, hi or 1) * 1000 + 0.5)
end

function M.silent(seq)
    local bands = {}
    for i = 1, M.BANDS do bands[i] = 0 end
    return {
        bands = bands,
        bass = 0, high = 0, beat = 0, phase = 0,
        playing = false, missing = false, seq = tonumber(seq) or 0,
    }
end

function M.encode(t)
    local out = { M.VERSION }
    local bands = type(t.bands) == "table" and t.bands or {}
    for i = 1, M.BANDS do out[#out + 1] = tostring(int(bands[i])) end
    out[#out + 1] = tostring(int(t.bass))
    out[#out + 1] = tostring(int(t.high))
    out[#out + 1] = tostring(int(t.beat))
    out[#out + 1] = tostring(int(t.phase))
    out[#out + 1] = t.playing and "1" or "0"
    out[#out + 1] = t.missing and "1" or "0"
    out[#out + 1] = tostring(math.floor(tonumber(t.seq) or 0))
    return table.concat(out, " ")
end

function M.decode(text)
    if type(text) ~= "string" then return nil end
    local tok = {}
    for word in text:gmatch("%S+") do tok[#tok + 1] = word end
    if tok[1] ~= M.VERSION then return nil end

    -- 32 bands + bass, high, beat, phase + playing, missing, seq
    local need = 1 + M.BANDS + 7
    if #tok < need then return nil end
    local nums = {}
    for i = 2, need do
        local n = tonumber(tok[i])
        if n == nil or n ~= n then return nil end
        nums[#nums + 1] = n
    end
    -- A 40th numeric field means the frame carries too many bands; words are
    -- a later version's extension and are ignored.
    if tok[need + 1] and tonumber(tok[need + 1]) ~= nil then return nil end

    local bands = {}
    for i = 1, M.BANDS do bands[i] = clamp(nums[i] / 1000, 0, 1) end
    local f = M.BANDS
    return {
        bands = bands,
        bass = clamp(nums[f + 1] / 1000, 0, 1),
        high = clamp(nums[f + 2] / 1000, 0, 1),
        beat = clamp(nums[f + 3] / 1000, 0, 1),
        phase = clamp(nums[f + 4] / 1000, 0, 1),
        playing = nums[f + 5] == 1,
        missing = nums[f + 6] == 1,
        seq = math.floor(nums[f + 7]),
    }
end

function M.newer(prev_seq, seq)
    if type(seq) ~= "number" then return false end
    if prev_seq == nil then return true end
    return seq > prev_seq
end

function M.fresh(last_ms, now_ms)
    if type(last_ms) ~= "number" or type(now_ms) ~= "number" then return false end
    return now_ms - last_ms <= M.STALE_MS
end

-- Sample the 32 bands onto n values, keeping both endpoints and their order.
function M.map(bands, n)
    n = math.max(1, math.floor(n or M.BANDS))
    local len = #bands
    if len == 0 then return {} end
    if n == 1 then
        local sum = 0
        for i = 1, len do sum = sum + bands[i] end
        return { sum / len }
    end
    local out = {}
    for i = 1, n do
        local at = math.floor(1 + (i - 1) * (len - 1) / (n - 1) + 0.5)
        out[i] = bands[at] or 0
    end
    return out
end

return M
