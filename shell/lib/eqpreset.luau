-- The player's equaliser (the music player overhaul): ten bands, the presets, and the EasyEffects
-- preset document mooi writes (~/.local/share/easyeffects/output/mooi.json, in the shape EasyEffects
-- 8.3 writes its own). Pure, so tests/unit runs it. The rack's three knobs are the means of the
-- low, middle and high bands.

local M = {}

M.FREQS = { 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 }
M.ORDER = { "flat", "bass", "treble", "vocal", "rock", "electronic", "acoustic" }
M.PRESETS = {
    flat = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    bass = { 6, 5, 4, 2, 0, 0, 0, 0, 0, 0 },
    treble = { 0, 0, 0, 0, 0, 1, 2, 4, 5, 6 },
    vocal = { -2, -2, -1, 1, 3, 4, 3, 1, 0, -1 },
    rock = { 4, 3, 2, 0, -1, -1, 1, 2, 3, 4 },
    electronic = { 5, 4, 1, 0, -2, 1, 0, 1, 4, 5 },
    acoustic = { 3, 2, 1, 1, 2, 2, 3, 3, 2, 1 },
}

-- A preset's gains, as a copy: what the bands start from must never be the preset itself.
function M.preset(name)
    local p = M.PRESETS[name]
    if not p then return nil end
    local out = {}
    for i, g in ipairs(p) do out[i] = g end
    return out
end

local function band(f, gain)
    return { frequency = f, gain = gain, mode = "Bell", mute = false, q = 1.0, solo = false, width = 1.0, slope = "x1" }
end

-- The preset document for these gains (dB) and preamp (dB).
function M.easyeffects(bands, preamp)
    local left, right = {}, {}
    for i, f in ipairs(M.FREQS) do
        local g = tonumber(bands and bands[i]) or 0
        left["band" .. (i - 1)] = band(f, g)
        right["band" .. (i - 1)] = band(f, g)
    end
    return { output = {
        blocklist = {},
        plugins_order = { "equalizer" },
        equalizer = { bypass = false, ["input-gain"] = tonumber(preamp) or 0, ["output-gain"] = 0,
                      mode = "IIR", ["num-bands"] = #M.FREQS, ["split-channels"] = false, left = left, right = right },
    } }
end

-- The gains back out of a document, or nil when it is not a ten-band equaliser of ours.
function M.bands_from(doc)
    local e = type(doc) == "table" and type(doc.output) == "table" and doc.output.equalizer
    if type(e) ~= "table" or type(e.left) ~= "table" then return nil end
    local out = {}
    for i = 1, #M.FREQS do
        local b = e.left["band" .. (i - 1)]
        if type(b) ~= "table" then return nil end
        out[i] = tonumber(b.gain) or 0
    end
    return out
end

local GROUPS = { { 1, 3 }, { 4, 7 }, { 8, 10 } }
local function mean(bands, g)
    local s = 0
    for i = g[1], g[2] do s = s + (tonumber(bands[i]) or 0) end
    return s / (g[2] - g[1] + 1)
end

-- The knobs: low, middle, high.
function M.knobs(bands)
    return mean(bands, GROUPS[1]), mean(bands, GROUPS[2]), mean(bands, GROUPS[3])
end

-- A knob turned to `value`: its group shifts so its mean is that, each band held to ±12 dB.
function M.from_knob(bands, which, value)
    local out = {}
    for i = 1, #M.FREQS do out[i] = tonumber(bands[i]) or 0 end
    local g = GROUPS[which]
    if not g then return out end
    local shift = (tonumber(value) or 0) - mean(out, g)
    for i = g[1], g[2] do out[i] = math.max(-12, math.min(12, out[i] + shift)) end
    return out
end

-- The user's output preset from `easyeffects -s` ("output: live_eq"), or nil — mooi's own presets
-- (mooi, mooi-<name>) are never the one to give back.
function M.last_output(text)
    local n = tostring(text or ""):match("output:%s*([^\n]+)")
    n = n and n:gsub("%s+$", "") or nil
    if not n or n == "" or n == "mooi" or n:match("^mooi%-") then return nil end
    return n
end

return M
