-- mooi's visualisers (D155), the logic: the shell's colours, the music, and the bars. Where each
-- visualiser is and how it looks comes from shell/mooi-widgets.luau (its lane facts, `hold` while
-- the widgets draw them themselves); the bars are taken from the bar's feed (lib/vizfeed) here, as
-- the widgets did before (D138): rise at once, fall by the widget's `smooth`, peaks hold 400 ms.

local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")
local vizfeed = require("lib/vizfeed")

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end

-- ── The colours, as every program of the shell paints them ──
local settings = config.parse(read("settings.json"), json.decode)
local palette = read("palette.json", "json")
local function paint()
    fact.cn_kind, fact.cn_scale = style.corners(settings)
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
    local look = style.facts(settings)
    if look and look.st_glow then fact.st_glow = look.st_glow end
end
paint()
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)
pcall(sys.watch, "files:settings.json", function() settings = config.parse(read("settings.json"), json.decode); paint() end)

-- ── The music ──
local playing = false
pcall(sys.watch, "media", function(m)
    playing = type(m) == "table" and type(m.title) == "string" and m.title ~= "" and m.playing == true
    fact.np_playing = playing
end)

-- A fact written only when it has moved enough to see: every write wakes what reads it.
local fc = {}
local function setf(name, v)
    local o = fc[name]
    if o == nil or math.abs(o - v) > 0.006 then fc[name] = v; fact[name] = v end
end

local LANES = { "A", "B", "C" }
local MODELS = { "vzA", "vzB", "vzC" }
local lanes = { {}, {}, {} }
local rings = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
local scope_hist = { {}, {}, {} }
local frame_n, viz_seq, viz_at, last_beat = 0, nil, 0, 0

local function hush()
    for i = 0, 31 do fact["vs" .. i] = 0.03; fc["vs" .. i] = 0.03 end
    fact.np_beat = 0
    for k = 1, 4 do rings[k] = { 0, 0 }; fact["rp_a" .. (k - 1)] = 0 end
    for k = 1, 3 do lanes[k] = {}; model[MODELS[k]] = {} end
end

local function lane_on(k) return fact["l" .. LANES[k] .. "_on"] == true end
local function any_lane() return not fact.hold and (lane_on(1) or lane_on(2) or lane_on(3)) end

local function feed_lane(k, bands)
    local f = "l" .. LANES[k] .. "_"
    local n = math.max(1, math.floor(tonumber(fact[f .. "n"]) or 64))
    local target = vizfeed.resample(bands, n)
    local L = lanes[k]
    if L.n ~= n then L.n, L.lev, L.pk, L.hold = n, {}, {}, {} end
    local fall = 0.02 + (1 - (tonumber(fact[f .. "sm"]) or 0.5)) * 0.16
    local rows = {}
    for i = 1, n do
        local v = math.max(target[i], (L.lev[i] or 0) - fall)
        L.lev[i] = v
        local p = L.pk[i] or 0
        if v >= p then p = v; L.hold[i] = frame_n + 12
        elseif frame_n > (L.hold[i] or 0) then p = math.max(v, p - 0.04) end
        L.pk[i] = p
        rows[i] = { v = v, pk = p }
    end
    model[MODELS[k]] = rows
end

local function take()
    local t
    local ok2, raw2 = pcall(sys.ask, "files.read", vizfeed.FILE_V2)
    if ok2 and type(raw2) == "string" then
        t = vizfeed.decode_v2(raw2)
        if t and not vizfeed.newer(viz_seq, t.seq) then t = nil end
    end
    if not t then
        local ok, raw = pcall(sys.ask, "files.read", vizfeed.FILE)
        if not ok or type(raw) ~= "string" then return end
        t = vizfeed.decode(raw)
        if not t or not vizfeed.newer(viz_seq, t.seq) then return end
    end
    viz_seq, viz_at = t.seq, os.time()
    if not t.playing then hush(); return end
    local s32 = vizfeed.resample(t.bands, 32)
    for i = 0, 31 do setf("vs" .. i, s32[i + 1]) end
    frame_n = frame_n + 1
    local scope = false
    for k = 1, 3 do
        if lane_on(k) then
            feed_lane(k, t.bands)
            if math.floor(tonumber(fact["l" .. LANES[k] .. "_mode"]) or -1) == 6 then scope = true end   -- lib/widgets MODES
        end
    end
    -- the scope's afterimages: the last three frames of 24 bands, one every other frame
    if scope and frame_n % 2 == 0 then
        scope_hist[3], scope_hist[2] = scope_hist[2], scope_hist[1]
        scope_hist[1] = vizfeed.resample(t.bands, 24)
        for h = 1, 3 do
            local f = scope_hist[h]
            for i = 0, 23 do setf("so" .. (h - 1) .. "_" .. i, f[i + 1] or 0.03) end
        end
    end
    local b = vizfeed.resample(t.bands, 16)
    local beat = (tonumber(t.beat) or 0) > 0.9 and last_beat <= 0.9
    last_beat = tonumber(t.beat) or 0
    if beat then
        fact.np_beat = 1
        after(60, function() fact.np_beat = 0 end)
        table.remove(rings, 1)
        rings[4] = { 0.02, math.min(1, 0.5 + (b[2] or 0)) }
    end
end

every(33, function()
    if not (playing and any_lane() and not fact.viz_still) then return end
    take()
    for k = 1, 4 do
        local r = rings[k]
        if r[2] > 0.02 then
            r[1] = r[1] + 0.025; r[2] = r[2] * 0.96
            fact["rp_r" .. (k - 1)], fact["rp_a" .. (k - 1)] = math.min(1.2, r[1]), r[2]
        elseif fact["rp_a" .. (k - 1)] ~= 0 then fact["rp_a" .. (k - 1)] = 0 end
    end
end)
-- the bar runs the one cava and writes the feed for a few seconds after each ask (D118)
every(3000, function()
    if playing and any_lane() and not fact.viz_still then run("pleamar", { "--say", "mooi", "emit feed_want" }, function() end) end
end)
every(400, function()
    if viz_seq and not vizfeed.fresh(viz_at * 1000, os.time() * 1000) then viz_seq, viz_at = nil, 0; hush() end
end)
-- the widgets tell this where everything is as soon as it is up
run("pleamar", { "--say", "mooi-widgets", "emit wg_viz_hello" }, function() end)

-- D209: the opening may already be up (and this program was restarted): ask for its hole; ask again
-- once the scene is surely listening, since the first ask can outrun the scene's own start
run("pleamar", { "--say", "mooi-surface", "emit op_want" }, function() end)
after(500, function() run("pleamar", { "--say", "mooi-surface", "emit op_want" }, function() end) end)
