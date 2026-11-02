-- mooi's screen frame (D119): its logic. The look comes from the same palette and settings as the bar
-- (lib/ferro, lib/style), where the bar's notch pieces are from bar-geo.json (the bar writes it when
-- its layout changes), and the music from the bar's feed (lib/vizfeed), read at the feed's own pace
-- while the frame moves with it — a file watch alone delivered a few of its thirty lines a second.

local config = require("lib/config")
local ferro = require("lib/ferro")
local theme = require("lib/theme")
local style = require("lib/style")
local vizfeed = require("lib/vizfeed")

local FILE, GEO = "settings.json", "bar-geo.json"

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind) else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end
local function position(path, value)
    for _, row in ipairs(config.SCHEMA) do
        if row.path == path then
            for i, v in ipairs(row.values or {}) do if v == value then return i - 1 end end
        end
    end
    return 0
end

local settings = config.parse(read(FILE), json.decode)
local saving = false          -- the bar's battery saver (bar-geo.json says): the frame's music rests

-- ── The look ──
local function paint()
    local palette = read("palette.json", "json")
    local roles = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not roles then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = roles[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
    for name, c in pairs(theme.resolve(settings.theme, roles) or {}) do
        local f = "c_" .. string.gsub(name, "%.", "_")
        pcall(function() fact[f .. "_r"], fact[f .. "_g"], fact[f .. "_b"] = c.r, c.g, c.b end)
    end
end

-- ── The settings: the frame's own, and the bar's that its border shares ──
local function apply()
    local look = style.facts(settings) or {}
    for _, k in ipairs({ "st_offset", "st_notch", "st_height", "st_radius", "st_res", "st_glow", "st_width",
                         "st_owidth", "st_ocol", "st_frame_r", "st_frame_edge", "st_frame_op" }) do
        if look[k] ~= nil then fact[k] = look[k] end
    end
    local f = settings.frame
    fact.frame_band = f.band
    fact.frame_style = position("frame.style", f.style)
    fact.frame_reach = f.reach
    fact.frame_edges = position("frame.edges", f.edges)
    fact.bar_surface = position("bar.surface", settings.bar.surface)
    fact.bar_ground = position("bar.ground", settings.bar.ground)
    fact.bar_frame = position("bar.frame", settings.bar.frame)
    fact.bar_rail = settings.bar.rail == true
end

-- ── The music ──
local still = false
local function music_wanted()
    return settings.frame.music == true and not saving and not still
end
local function rim_wanted()
    return music_wanted() and settings.music.rim == true
end
local seq, at = nil, 0
local last = { bass = -1, high = -1, beat = -1 }
local rim_sent, rim_quiet = {}, false
local function rest()
    fact.fbass, fact.fhigh, fact.fbeat = 0, 0, 0
    last = { bass = -1, high = -1, beat = -1 }
    fact.rm_on = 0
    rim_sent, rim_quiet = {}, false
end
local function take()
    local ok, raw = pcall(sys.ask, "files.read", vizfeed.FILE)
    if not ok or type(raw) ~= "string" then return end
    local t = vizfeed.decode(raw)
    if not t or not vizfeed.newer(seq, t.seq) then return end
    seq, at = t.seq, os.time()
    if not t.playing then rest(); return end
    -- only what moved is written: a fact that changes is the scene read again
    local function put(name, key, v, step)
        if math.abs(v - last[key]) > step then fact[name] = v; last[key] = v end
    end
    put("fbass", "bass", tonumber(t.bass) or 0, 0.015)
    put("fhigh", "high", tonumber(t.high) or 0, 0.02)
    put("fbeat", "beat", tonumber(t.beat) or 0, 0.02)
    if rim_wanted() then
        local quiet = (tonumber(t.bass) or 0) < 0.01 and (tonumber(t.high) or 0) < 0.01
        if not (quiet and rim_quiet) then
            local folded = vizfeed.map(t.bands, 16)
            for j = 0, 15 do
                local x = folded[j + 1]
                if math.abs(x - (rim_sent[j] or -1)) > 0.02 then fact["rm" .. j] = x; rim_sent[j] = x end
            end
            fact.rm_bass, fact.rm_high, fact.rm_beat, fact.rm_phase = t.bass, t.high, t.beat, t.phase
            fact.rm_gain = math.min(1.5, math.max(0.25, (tonumber(settings.music.rim_gain) or 100) / 100))
            fact.rm_glow = settings.music.rim_glow == true and 1 or 0
            fact.rm_on = 1
        end
        rim_quiet = quiet
    end
end
local timer, asker = nil, nil
local function listen()
    still = type(settings.motion) == "table" and (settings.motion.reduced == true or settings.motion.saver == "always")
    fact.frame_music = music_wanted()
    if music_wanted() then
        if not timer then
            timer = every(33, take)
            -- the bar writes the feed while someone asks for it (and always while frame.music is on)
            asker = every(3000, function()
                run("pleamar", { "--say", "mooi", "emit feed_want" })
                if seq and not vizfeed.fresh(at * 1000, os.time() * 1000) then seq = nil; rest() end
            end)
        end
    else
        if timer then cancel(timer); timer = nil end
        if asker then cancel(asker); asker = nil end
        rest()
    end
    if not rim_wanted() then fact.rm_on = 0 end
end

-- ── Where the bar's pieces are ──
local function geo()
    local g = read(GEO, "json")
    if type(g) ~= "table" then return end
    local function piece(p) return type(p) == "table" and tonumber(p.x) or 0, type(p) == "table" and tonumber(p.w) or 0 end
    fact.gl_x, fact.gl_w = piece(g.left)
    fact.gc_x, fact.gc_w = piece(g.center)
    fact.gr_x, fact.gr_w = piece(g.right)
    local was = saving
    saving = g.saving == true
    if was ~= saving then listen() end
end

paint(); apply(); geo(); listen()
pcall(sys.watch, "files:palette.json", paint)
pcall(sys.watch, "files:" .. GEO, geo)
pcall(sys.watch, "files:" .. FILE, function()
    settings = config.parse(read(FILE), json.decode)
    paint(); apply(); listen()
end)
log("frame · up")
