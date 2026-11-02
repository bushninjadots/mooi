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

-- The producer's cadence: a frame goes out at most 30 times a second, at once
-- when its content moves, and at least every `keepalive` ms while it repeats.
function M.should_publish(prev, now, now_ms, last_ms, keepalive)
    if type(now) ~= "table" then return false end
    if type(prev) ~= "table" then return true end
    now_ms, last_ms = tonumber(now_ms) or 0, tonumber(last_ms) or 0
    keepalive = tonumber(keepalive) or 500
    if now_ms - last_ms >= keepalive then return true end

    local function moved(a, b)
        return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) > 0.002
    end
    for i = 1, M.BANDS do
        if moved(now.bands and now.bands[i], prev.bands and prev.bands[i]) then return true end
    end
    for _, k in ipairs({ "bass", "high", "beat", "phase" }) do
        if moved(now[k], prev[k]) then return true end
    end
    if (now.playing and true or false) ~= (prev.playing and true or false) then return true end
    if (now.missing and true or false) ~= (prev.missing and true or false) then return true end
    return now_ms - last_ms >= 33
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

local function mean(b, a, z)
    local sum = 0
    for i = a, z do sum = sum + (tonumber(b[i]) or 0) end
    return sum / (z - a + 1)
end

-- One envelope, one beat and one phase for every surface. Uses 1-indexed bands;
-- `prev` may be nil. `dt` is seconds since the previous analysis.
-- Automatic gain (D119): cava hears the music after the player's own volume, and the mooi player
-- runs mpd quietly, so its bands sat at a thousandth of their range and every visualiser stood still
-- with music playing. The loudest band of each line sets a ceiling that rises at once and sinks slowly
-- (half in about eight seconds at 30 lines a second), and the bands are read against it; under a floor
-- it is silence, not something to amplify. Returns the bands (a new table) and the ceiling to keep.
M.GAIN_DECAY = 0.997
M.GAIN_FLOOR = 0.0015
function M.gain(peak, bands)
    local m = 0
    for _, b in ipairs(bands or {}) do m = math.max(m, tonumber(b) or 0) end
    peak = math.max(m, (tonumber(peak) or 0) * M.GAIN_DECAY)
    local out = {}
    if peak < M.GAIN_FLOOR then
        for i = 1, #(bands or {}) do out[i] = 0 end
        return out, peak
    end
    local ceiling = math.max(peak, 0.002)
    for i, b in ipairs(bands or {}) do out[i] = math.min(1, (tonumber(b) or 0) / ceiling * 0.92) end
    return out, peak
end

function M.analyse(prev, bands, dt)
    dt = tonumber(dt) or 0
    if type(prev) ~= "table" then prev = nil end
    bands = bands or {}

    local bass = math.min(1, math.sqrt(mean(bands, 1, 4)) * 1.4)
    local high = math.min(1, math.sqrt(mean(bands, 27, 32)) * 1.8)
    local level = prev and (tonumber(prev.level) or 0) or 0
    local high_lv = prev and (tonumber(prev.high) or 0) or 0
    level = level + (bass - level) * math.min(1, (bass > level and 16 or (2.6 + 3 * level)) * dt)
    high_lv = high_lv + (high - high_lv) * math.min(1, (high > high_lv and 14 or 4) * dt)

    local t = (prev and (tonumber(prev.t) or 0) or 0) + dt
    local last_beat = prev and (tonumber(prev.last_beat) or -1e9) or -1e9
    local tempo = prev and (tonumber(prev.tempo) or 0) or 0
    local beat = prev and (tonumber(prev.beat) or 0) or 0
    local phase = prev and (tonumber(prev.phase) or 0) or 0
    local rise = prev and (bass - (tonumber(prev.bass) or 0)) or 0   -- the edge, not the level

    if bass > 0.55 and rise > 0.05 and t - last_beat >= 0.25 then
        local interval = t - last_beat
        if interval >= 0.25 and interval <= 2 then
            tempo = tempo > 0 and (tempo * 0.5 + interval * 0.5) or interval
        end
        beat = 1
        last_beat = t
    else
        beat = math.max(0, beat - 4 * dt)
    end

    phase = phase + (tempo > 0 and dt / tempo or dt * (0.35 + 0.65 * level))
    phase = phase % 1
    if phase < 0 then phase = phase + 1 end

    return {
        level = level, high = high_lv, bass = bass, beat = beat,
        phase = phase, tempo = tempo, last_beat = last_beat, t = t,
    }
end

return M
