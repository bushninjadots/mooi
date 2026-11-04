-- mooi's screen frame (D119, D127): its logic. The chassis takes the bar's palette and material (lib/ferro,
-- lib/style), the bar's pieces from bar-geo.json (the bar writes it when its layout changes), and the
-- music from the bar's feed (lib/vizfeed), turned into iNiR's level and wave phase every 33 ms.

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

-- ── The settings: the frame's own, and the bar's: the chassis is the bar's material ──
local function apply()
    local look = style.facts(settings) or {}
    for _, k in ipairs({ "st_offset", "st_notch", "st_height", "st_radius", "st_res", "st_glow", "st_width",
                         "st_owidth", "st_ocol", "st_frame_r", "st_frame_edge", "st_frame_op", "st_opacity",
                         "st_sh_y", "st_sh_blur", "st_sh_a", "st_frost", "st_smoke" }) do
        if look[k] ~= nil then fact[k] = look[k] end
    end
    local f = settings.frame
    -- the band only with the frame on; without it (island.morph alone) the frame draws the bar's pieces
    -- and what grows out of them (D153)
    fact.band_on = f.on == true
    fact.frame_band = f.on == true and f.band or 0
    fact.frame_reach = f.reach
    fact.frame_edges = position("frame.edges", f.edges)
    fact.bar_surface = position("bar.surface", settings.bar.surface)
    fact.bar_ground = position("bar.ground", settings.bar.ground)
    fact.bar_frame = position("bar.frame", settings.bar.frame)
    fact.bar_rail = settings.bar.rail == true
    fact.bar_mode = ({ islands = 0, full = 1, notch = 2 })[settings.bar.mode] or 0
end

-- ── The music: iNiR's IrisFramePulse, as it is ──
-- bass = the mean of the lowest four of sixteen bands, square-rooted, × 1.4 (its sensitivity);
-- the level follows it at 18 a second rising and 3.2 falling; the wave's phase runs at
-- (0.6 + 2.4 · level) a second. The bar's feed is already levelled (lib/vizfeed's gain).
local still = false
local function music_wanted()
    return settings.frame.music == true and not saving and not still
end
local SENSITIVITY = 1.4
local seq, at = nil, 0
local bass, level, phase = 0, 0, 0
local function rest()
    bass, level, phase = 0, 0, 0
    fact.flev, fact.fph = 0, 0
end
local function read_feed()
    local ok, raw = pcall(sys.ask, "files.read", vizfeed.FILE)
    if not ok or type(raw) ~= "string" then return end
    local t = vizfeed.decode(raw)
    if not t or not vizfeed.newer(seq, t.seq) then return end
    seq, at = t.seq, os.time()
    if not t.playing then bass = 0; return end
    local b16 = vizfeed.map(t.bands, 16)
    local sum = 0
    for i = 1, 4 do sum = sum + (tonumber(b16[i]) or 0) end
    bass = math.min(1, math.sqrt(math.max(0, sum / 4)) * SENSITIVITY)
end
local function step()
    read_feed()
    local dt = 0.033                  -- the timer's step (iNiR caps a frame's step at 0.05)
    local rate = bass > level and 18 or 3.2
    level = level + (bass - level) * math.min(1, rate * dt)
    if level < 0.002 and bass <= 0 then level = 0 end
    phase = (phase + dt * (0.6 + 2.4 * level)) % 6283.185
    -- only what moved is written: a fact that changes is the scene drawn again
    if math.abs(level - (fact.flev or 0)) > 0.004 or (level > 0 and math.abs(phase - (fact.fph or 0)) > 0.01) then
        fact.flev, fact.fph = level, phase
    elseif level == 0 and (fact.flev or 0) ~= 0 then
        fact.flev = 0
    end
end
local timer, asker = nil, nil
local function listen()
    still = type(settings.motion) == "table" and (settings.motion.reduced == true or settings.motion.saver == "always")
    fact.frame_music = music_wanted()
    if music_wanted() then
        if not timer then
            timer = every(33, step)
            -- the bar writes the feed while someone asks for it (and always while frame.music is on)
            asker = every(3000, function()
                run("pleamar", { "--say", "mooi", "emit feed_want" })
                if seq and not vizfeed.fresh(at * 1000, os.time() * 1000) then seq = nil; bass = 0 end
            end)
        end
    else
        if timer then cancel(timer); timer = nil end
        if asker then cancel(asker); asker = nil end
        rest()
    end
end

-- ── Where the bar's pieces are (bar-geo.json, written by shell/bar.luau) ──
local SLOTS = 16
local function geo()
    local g = read(GEO, "json")
    if type(g) ~= "table" then return end
    local function piece(p) return type(p) == "table" and tonumber(p.x) or 0, type(p) == "table" and tonumber(p.w) or 0 end
    fact.gl_x, fact.gl_w = piece(g.left)
    fact.gc_x, fact.gc_w = piece(g.center)
    fact.gr_x, fact.gr_w = piece(g.right)
    fact.gp_x, fact.gp_w = piece(g.panel)
    local isl = type(g.islands) == "table" and g.islands or {}
    local first, last = nil, nil          -- where the islands begin and end: does one sit in a corner?
    for i = 0, SLOTS - 1 do
        local x, w = piece(isl[i + 1])
        fact["ix" .. i], fact["iw" .. i] = x, w
        if w > 0 then first = first or x; last = x + w end
    end
    fact.il_x, fact.ir_e = first or -1, last or -1
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
