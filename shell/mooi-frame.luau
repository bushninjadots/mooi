-- mooi's screen frame (D119, D127): its logic. The chassis takes the bar's palette and material (lib/ferro,
-- lib/style), the bar's pieces from bar-geo.json (the bar writes it when its layout changes), and the
-- music from the bar's feed (lib/vizfeed), turned into iNiR's level and wave phase every 33 ms.

local config = require("lib/config")
local ferro = require("lib/ferro")
local theme = require("lib/theme")
local style = require("lib/style")
local vizfeed = require("lib/vizfeed")
local chassis = require("lib/chassis")
local modlook = require("lib/modlook")
local pillmorph = require("lib/pillmorph")

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
local roles_now = {}           -- the palette's roles, for the islands' own colours (lib/modlook)
local function paint()
    local palette = read("palette.json", "json")
    local roles = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not roles then return end
    roles_now = roles
    -- "from the wallpaper": the wallpaper's own primary (palette.json, Matugen), not the theme's main
    -- colour, which a preset like Phosphor sets apart from the wallpaper (review I4)
    local wall = type(palette) == "table" and type(palette.colours) == "table" and ferro.hex(palette.colours.primary) or nil
    roles_now.primary = wall or roles.phos
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
local morph_blob = false    -- D204: the morph Pill is a blob (music playing): its edge rides the same level
local function music_wanted()
    return (settings.frame.music == true or morph_blob) and not saving and not still
end
local SENSITIVITY = 1.4
local seq, at = nil, 0
local bass, level, phase = 0, 0, 0
local wrote = { lev = 0, ph = 0 }   -- what step() last wrote (the band's and the morph's alike)
local function rest()
    bass, level, phase = 0, 0, 0
    wrote.lev, wrote.ph = 0, 0
    fact.flev, fact.fph = 0, 0
    fact.mlev, fact.mph = 0, 0
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
    -- only what moved is written: a fact that changes is the scene drawn again. The band's wave (flev)
    -- only with frame.music; the morph's edge (mlev, D204) only while it is a blob
    local band = settings.frame.music == true
    local moved = math.abs(level - wrote.lev) > 0.004 or (level > 0 and math.abs(phase - wrote.ph) > 0.01)
    if moved or (level == 0 and wrote.lev ~= 0) then
        wrote.lev, wrote.ph = level, phase
        if band then fact.flev, fact.fph = level, phase end
        if morph_blob then fact.mlev, fact.mph = level, phase * 57.29578 end
    end
    if not morph_blob and (fact.mlev or 0) ~= 0 then fact.mlev = 0 end
    if not band and (fact.flev or 0) ~= 0 then fact.flev = 0 end
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

-- ── Where the bar's pieces are (bar-geo.json, written by shell/bar.luau), laid out by lib/chassis ──
local geo_doc = nil
local announced = false
local function place()
    local look = chassis.look(settings)
    if type(geo_doc) == "table" and tonumber(geo_doc.screen) then look.screen_w = tonumber(geo_doc.screen) end
    -- every island's own look (D166): style defaults, or what Settings → Modules set for its module
    local looks = {}
    if type(geo_doc) == "table" and type(geo_doc.islands) == "table" then
        for i, isl in ipairs(geo_doc.islands) do
            if type(isl) == "table" and type(isl.id) == "string" then looks[i] = modlook.of(settings, isl.id, roles_now) end
        end
    end
    local pieces = chassis.pieces(geo_doc, look, looks)
    -- D204: the morph Pill's outline — twelve targets the scene springs to (mt*), its ripple and blend
    local mo = chassis.morph(geo_doc, look)
    local gp0 = type(geo_doc) == "table" and type(geo_doc.pill) == "table" and geo_doc.pill or nil
    local out = mo and pillmorph.points(mo.form, mo.x, mo.y, mo.w, mo.h, mo.r)
        or pillmorph.points("none", gp0 and gp0.x, look.top, gp0 and gp0.w, gp0 and look.mod_h or 0, look.mod_h / 2)
    for i, p in ipairs(out.pts) do fact["mtx" .. (i - 1)], fact["mty" .. (i - 1)] = p[1], p[2] end
    fact.mrip = (not still) and out.ripple or 0
    fact.mk = mo and mo.k or 0
    fact.m_on = mo ~= nil and mo.form ~= "none"
    for i = 0, chassis.SLOTS - 1 do
        local p = pieces[i + 1]
        if p then
            fact["tx" .. i], fact["ty" .. i], fact["tw" .. i], fact["th" .. i] = p.x, p.y, p.w, p.h
            fact["pr" .. i], fact["pk" .. i] = p.r, p.k
            fact["pj" .. i] = p.j or p.fill == nil      -- a plate with no look of its own stays in the band's tiles
            fact["pf" .. i], fact["po" .. i], fact["pg" .. i] = p.fill or 0, p.outline or 1, p.glow or 0
            local c = p.colour
            fact["pc" .. i .. "_r"], fact["pc" .. i .. "_g"], fact["pc" .. i .. "_b"] = c and c.r or -1, c and c.g or 0, c and c.b or 0
        else
            -- every value of an unused slot: a zero-size box that kept its blend still pulled a bulge
            -- out of a neighbour (review M1)
            fact["tw" .. i], fact["th" .. i] = 0, 0
            fact["pr" .. i] = 0
            fact["pk" .. i] = 0
        end
    end
    -- D188: the Pill's capsule, where its board starts growing from (and goes back into)
    local gp = type(geo_doc) == "table" and type(geo_doc.pill) == "table" and geo_doc.pill or nil
    if gp and tonumber(gp.x) and tonumber(gp.w) then
        fact.pp_x, fact.pp_w = tonumber(gp.x), tonumber(gp.w)
        fact.pp_y, fact.pp_h = look.top or 0, tonumber(gp.h) or look.mod_h or 24
    end
    fact.covL = chassis.covers(pieces, look, "left")
    fact.covR = chassis.covers(pieces, look, "right")
    fact.pfoot = chassis.foot(look)
    fact.troom = look.top_room
    fact.btop = look.top_band
    fact.battach = look.attach == true
    fact.capL = chassis.corner_cap(pieces, look, "left")
    fact.capR = chassis.corner_cap(pieces, look, "right")
    -- the bar hides its own plates only once the pieces are placed (review I3): a frame that started but
    -- never drew must not leave the bar bare
    if type(geo_doc) == "table" and not announced then
        announced = true
        run("pleamar", { "--say", "mooi", "emit chassis_ready" })
    end
end
local function geo()
    local g = read(GEO, "json")
    if type(g) ~= "table" then return end
    geo_doc = g
    place()
    local was, blob_was = saving, morph_blob
    saving = g.saving == true
    -- only while the blob ripples (lib/pillmorph.RIPPLE > 0): a still blob needs no level at all
    morph_blob = pillmorph.RIPPLE > 0 and type(g.pill) == "table" and g.pill.shape == "morph" and g.pill.form == "blob"
    if was ~= saving or blob_was ~= morph_blob then listen() end
end

paint(); apply(); geo(); listen()
pcall(sys.watch, "files:palette.json", function() paint(); place() end)
pcall(sys.watch, "files:" .. GEO, geo)
pcall(sys.watch, "files:" .. FILE, function()
    settings = config.parse(read(FILE), json.decode)
    paint(); apply(); place(); listen()
end)
log("frame · up")
