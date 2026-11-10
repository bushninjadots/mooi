-- The node's look (D229): everything the Pill studio sets, in one table kept in node-look.json. Pure: the schema
-- the studio draws its rows from, the four personalities as presets, a shuffle that makes a look of its own, the
-- check that keeps any file sane, and what the scene is told (facts) and the geometry is given (shape).
--
-- Values are kept in the units the studio shows (per cent, pixels, tenths of a pixel), so a file read by eye
-- says what the studio says. Choices are kept by name.

local M = {}

M.FILE = "node-look.json"
M.PRESETS = { "organic", "minimal", "technical", "cyber" }
M.SLOTS = 3

-- the studio's tabs; the first is the presets' own page (no rows)
M.TABS = { "Presets", "Rest", "Shape", "Surface", "Motion", "Music", "Parts" }

-- each row: key, label, description, and either a range (lo, hi, unit) or a choice (values, names)
local function range(key, label, desc, lo, hi, unit) return { key = key, label = label, desc = desc, lo = lo, hi = hi, unit = unit or "" } end
local function choice(key, label, desc, values, names) return { key = key, label = label, desc = desc, values = values, names = names } end

M.SCHEMA = {
    Rest = {
        choice("rest", "At rest", "A seed, a longer pill that holds a few things, or a notch hanging from the top edge", { "seed", "long", "notch" }, { "Seed", "Long pill", "Notch" }),
        choice("m_clock", "Clock", "The time, in the long pill", { "off", "on" }, { "Off", "On" }),
        choice("m_window", "Window", "What has the focus, in the long pill", { "off", "on" }, { "Off", "On" }),
        choice("m_spaces", "Workspaces", "A dot for each, the one you are on lit", { "off", "on" }, { "Off", "On" }),
        choice("m_battery", "Battery", "How full it is (only where there is one)", { "off", "on" }, { "Off", "On" }),
        choice("m_music", "Music", "What plays, while something does", { "off", "on" }, { "Off", "On" }),
    },
    Shape = {
        choice("seed", "Seed", "What rests at the top while nothing happens", { "line", "dot", "ring", "twin", "bar", "clock", "bmo" }, { "Line", "Dot", "Ring", "Twin", "Bar", "Clock", "BMO" }),
        range("seed_w", "Seed width", "How long the resting seed is", 6, 80, " px"),
        range("seed_h", "Seed height", "How thick it is", 2, 16, " px"),
        range("round", "Roundness", "From square corners to a full capsule", 0, 100, "%"),
        choice("style", "Character", "The details it wears: soft, bare, ruled, or broken", { "organic", "minimal", "technical", "cyber" }, { "Organic", "Minimal", "Technical", "Cyber" }),
        range("top", "From the top", "How far below the screen's edge it sits", 0, 40, " px"),
    },
    Surface = {
        choice("texture", "Texture", "What its body is made of", { "solid", "hollow", "segmented", "scan", "dotted" }, { "Solid", "Hollow", "Segmented", "Scan", "Dotted" }),
        range("fill", "Fill", "How solid the body is", 30, 100, "%"),
        range("outline", "Outline", "The edge's weight", 0, 30, ""),
        range("glow", "Glow", "How much light it gives off", 0, 100, "%"),
        choice("accent", "Colour", "Its own colour, from the palette", { "phos", "ember", "ink", "steel" }, { "Signal", "Ember", "Ink", "Steel" }),
        choice("glow_colour", "Glow colour", "The light's colour", { "phos", "ember", "ink", "steel" }, { "Signal", "Ember", "Ink", "Steel" }),
    },
    Motion = {
        choice("speed", "Speed", "How quickly it changes shape", { "soft", "quick", "snap" }, { "Soft", "Quick", "Snap" }),
        choice("bounce", "Bounce", "How far it overshoots and settles", { "none", "some", "lots" }, { "None", "Some", "Lots" }),
        choice("growth", "Growth", "How fast what unfolds grows out of it", { "slow", "normal", "fast" }, { "Slow", "Normal", "Fast" }),
        range("stagger", "Stagger", "Parts one after another, or all at once", 0, 100, "%"),
        range("breath", "Breathing", "How deeply the seed breathes at rest (0: still)", 0, 100, "%"),
        range("music", "Music", "How much it moves with what plays", 0, 100, "%"),
    },
    Music = {
        choice("music_form", "Music as", "When music starts: the capsule with its song, a visualiser, or a turning record", { "capsule", "visualiser", "vinyl" }, { "Capsule", "Spectrum", "Vinyl" }),
        choice("seed_music", "Seed with music", "What the resting seed does while music plays", { "still", "pulse", "bars" }, { "Still", "Pulse", "Bars" }),
        choice("viz", "Visualiser", "The music inside the media capsule", { "bars", "wave", "dots", "off" }, { "Bars", "Wave", "Dots", "Off" }),
        choice("cover", "Cover", "The album art's shape", { "square", "round" }, { "Square", "Round" }),
    },
    Parts = {
        choice("sys_style", "System as", "How the machine's readings show: spokes, rings, or a short history each", { "spokes", "rings", "graphs" }, { "Spokes", "Rings", "Graphs" }),
        range("cards", "Notices", "How many notice cards branch from it", 1, 5, ""),
        range("satellites", "Satellites", "How many small marks may orbit the seed", 0, 6, ""),
        choice("sat_style", "Satellite style", "What those marks look like", { "pill", "dot", "tick" }, { "Pills", "Dots", "Ticks" }),
        range("dim", "Search dim", "How far the desktop steps back behind the search", 0, 60, "%"),
        range("orbit", "Orbit", "How wide the workspaces orbit (Super+Tab)", 300, 700, " px"),
    },
}

local BASE = {
    seed = "line", seed_w = 22, seed_h = 6, round = 100, style = "organic", top = 8,
    texture = "solid", fill = 95, outline = 10, glow = 70, accent = "phos", glow_colour = "phos",
    speed = "soft", bounce = "lots", growth = "normal", stagger = 50, breath = 35, music = 60,
    viz = "bars", cover = "square", music_form = "capsule", seed_music = "pulse",
    sys_style = "spokes", rest = "seed", m_clock = "on", m_window = "on", m_spaces = "on", m_battery = "off", m_music = "on", cards = 3, satellites = 6, sat_style = "pill", dim = 28, orbit = 520,
}
local PRESET = {
    organic = {},
    minimal = { seed = "dot", seed_w = 6, seed_h = 6, style = "minimal", outline = 7, glow = 8, speed = "quick", bounce = "none",
                growth = "fast", stagger = 30, breath = 15, music = 20, viz = "dots", sat_style = "dot", dim = 20 },
    technical = { seed = "bar", seed_w = 26, seed_h = 4, round = 18, style = "technical", texture = "scan", glow = 5,
                  speed = "quick", bounce = "none", stagger = 60, breath = 0, music = 35, sat_style = "tick", cover = "square" },
    cyber = { seed = "twin", seed_w = 24, seed_h = 5, round = 32, style = "cyber", texture = "segmented", outline = 15, glow = 90,
              glow_colour = "ember", speed = "snap", bounce = "some", stagger = 80, breath = 20, music = 80, viz = "wave" },
}

local function find(key)
    for _, tab in ipairs(M.TABS) do
        for _, row in ipairs(M.SCHEMA[tab] or {}) do if row.key == key then return row end end
    end
end
M.find = find

local function index_of(list, v) for i, x in ipairs(list) do if x == v then return i end end end
M.index_of = index_of

function M.preset(name)
    local t = {}
    for k, v in pairs(BASE) do t[k] = v end
    for k, v in pairs(PRESET[name] or {}) do t[k] = v end
    t.preset = PRESET[name] and name or "organic"
    return t
end

-- any table (a file, a hand edit, an old version) made sane: each key in its range or among its values, the
-- rest taken from the preset it names (or from the old Settings personality, `fallback`)
function M.normalise(t, fallback)
    t = type(t) == "table" and t or {}
    local base = M.preset(PRESET[t.preset] and t.preset or (PRESET[fallback] and fallback) or "organic")
    local out = { preset = base.preset }
    for k, def in pairs(base) do
        if k ~= "preset" then
            local row, v = find(k), t[k]
            if row and row.values then
                out[k] = index_of(row.values, v) and v or def
            elseif row then
                v = tonumber(v)
                out[k] = v and math.floor(math.max(row.lo, math.min(row.hi, v)) + 0.5) or def
            end
        end
    end
    out.custom = t.custom == true
    -- the saved looks: up to M.SLOTS, each a look of its own (or nothing)
    out.slots = {}
    if type(t.slots) == "table" then
        for i = 1, M.SLOTS do
            local s = t.slots[i]
            if type(s) == "table" then
                local c = {}
                for k, _ in pairs(base) do if k ~= "preset" then c[k] = s[k] end end
                c.preset, c.custom = s.preset, s.custom
                out.slots[i] = M.normalise(c)
                out.slots[i].slots = nil
            else out.slots[i] = false end
        end
    else for i = 1, M.SLOTS do out.slots[i] = false end end
    return out
end

-- a look nobody else has: every row drawn at random, but held together — the character's own details kept,
-- and never so faint or so loud that it stops reading as the node. `rand(n)` gives 1..n (math.random)
function M.shuffle(rand, slots)
    local t = M.preset(M.PRESETS[rand(#M.PRESETS)])
    for _, tab in ipairs(M.TABS) do
        for _, row in ipairs(M.SCHEMA[tab] or {}) do
            if row.values then t[row.key] = row.values[rand(#row.values)]
            else t[row.key] = row.lo + (rand(1001) - 1) * (row.hi - row.lo) / 1000 end
        end
    end
    -- held together: something to see at rest, a glow that never swamps, the edge or the fill there
    t.seed_w = math.max(t.seed_w, (t.seed == "dot" or t.seed == "ring") and 6 or 14)
    t.seed_h = math.max(3, math.min(t.seed_h, 10))
    t.glow = math.min(t.glow, 85)
    t.fill = math.max(t.fill, 60)
    t.top = math.min(t.top, 20)
    t.orbit = math.max(t.orbit, 420)
    if t.texture == "hollow" then t.outline = math.max(t.outline, 10) end
    t.custom = true
    t.slots = slots
    return M.normalise(t)
end

-- one value moved: a range to the fraction f (0..1) of its span, a choice to its i-th value (1-based)
function M.set_frac(t, key, f)
    local row = find(key)
    if not row or row.values then return false end
    f = math.max(0, math.min(1, tonumber(f) or 0))
    t[key] = math.floor(row.lo + f * (row.hi - row.lo) + 0.5)
    t.custom = true
    return true
end
function M.set_choice(t, key, i)
    local row = find(key)
    if not row or not row.values or not row.values[i] then return false end
    t[key] = row.values[i]
    t.custom = true
    return true
end
-- the arrow keys over a row: a range by one step (a twentieth of its span, at least 1), a choice to the next
function M.nudge(t, key, dir)
    local row = find(key)
    if not row then return false end
    if row.values then
        local i = (index_of(row.values, t[key]) or 1) + dir
        i = (i - 1) % #row.values + 1
        return M.set_choice(t, key, i)
    end
    local step = math.max(1, (row.hi - row.lo) / 20)
    t[key] = math.floor(math.max(row.lo, math.min(row.hi, (tonumber(t[key]) or row.lo) + dir * step)) + 0.5)
    t.custom = true
    return true
end

-- what a row shows: its value as words, where its knob sits, which choice is lit
function M.shown(t, row)
    if row.values then
        local i = index_of(row.values, t[row.key]) or 1
        return row.names[i], 0, i - 1
    end
    local v = tonumber(t[row.key]) or row.lo
    local word = tostring(math.floor(v + 0.5)) .. row.unit
    if row.key == "outline" then word = string.format("%.1f px", v / 10) end
    if row.key == "satellites" and v == 0 then word = "None" end
    return word, (v - row.lo) / math.max(1, row.hi - row.lo), -1
end

-- the rows of a tab, as the studio's model takes them
function M.rows(t, tab)
    local out = {}
    for i, row in ipairs(M.SCHEMA[tab] or {}) do
        local word, frac, sel = M.shown(t, row)
        local r = { kind = row.values and 1 or 0, label = row.label, desc = row.desc, value = word, frac = frac, sel = sel,
                    n = row.values and #row.values or 0 }
        for j = 0, 5 do r["o" .. j] = row.names and row.names[j + 1] or "" end
        out[i] = r
    end
    return out
end

-- the springs the scene declares: speed × bounce, nine of them (index 0..8); and three for growth
M.SPEED = { soft = 240, quick = 520, snap = 760 }
M.BOUNCE = { none = 1.0, some = 0.7, lots = 0.5 }  -- of the critical damping
M.SPEEDS = { "soft", "quick", "snap" }
M.BOUNCES = { "none", "some", "lots" }
M.GROWTH = { slow = { 90, 15 }, normal = { 170, 19 }, fast = { 320, 30 } }
M.GROWTHS = { "slow", "normal", "fast" }
function M.springs()
    local out = {}
    for _, s in ipairs(M.SPEEDS) do
        for _, b in ipairs(M.BOUNCES) do
            local k = M.SPEED[s]
            out[#out + 1] = { name = s .. "_" .. b, k = k, d = math.floor(2 * math.sqrt(k) * M.BOUNCE[b] + 0.5) }
        end
    end
    return out
end
function M.spring_index(t)
    return ((index_of(M.SPEEDS, t.speed) or 1) - 1) * #M.BOUNCES + (index_of(M.BOUNCES, t.bounce) or 3) - 1
end
-- how far a change overshoots: none without bounce
function M.overshoot(t) return ({ none = 0, some = 0.03, lots = 0.07 })[t.bounce] or 0 end

local COLOURS = { "phos", "ember", "ink", "steel" }
-- the scene's facts: every name is the scene's (tools/gen-node.py declares them)
function M.facts(t)
    local function ix(list, v) return (index_of(list, v) or 1) - 1 end
    return {
        nd_np = ix(M.PRESETS, t.style), nd_sp = M.spring_index(t), nd_gs = ix(M.GROWTHS, t.growth),
        nd_seed = ix({ "line", "dot", "ring", "twin", "bar", "clock", "bmo" }, t.seed), nd_rnd = t.round / 100,
        nd_tex = ix({ "solid", "hollow", "segmented", "scan", "dotted" }, t.texture), nd_fill = t.fill / 100,
        nd_ol = t.outline / 10, nd_gw = t.glow / 100, nd_ac = ix(COLOURS, t.accent), nd_gc = ix(COLOURS, t.glow_colour),
        nd_stg = t.stagger / 100, nd_bd = t.breath / 100, nd_mu = t.music / 100,
        nd_viz = ix({ "bars", "wave", "dots", "off" }, t.viz), nd_cov = ix({ "square", "round" }, t.cover),
        nd_sst = ix({ "pill", "dot", "tick" }, t.sat_style), nd_ldm = t.dim / 100, nd_ur = t.orbit,
        nd_long = t.rest == "long" and 1 or t.rest == "notch" and 2 or 0,
        nd_sys = ix({ "spokes", "rings", "graphs" }, t.sys_style),
        nd_mf = ix({ "capsule", "visualiser", "vinyl" }, t.music_form), nd_smu = ix({ "still", "pulse", "bars" }, t.seed_music),
    }
end

-- what the geometry needs: the seed's size, the corners, where it sits
function M.shape(t)
    local w, h = t.seed_w, t.seed_h
    if t.seed == "dot" or t.seed == "ring" then w = math.max(h, math.min(w, 16)); h = w end
    -- the clock (D241): its matrix sets its size — 29 cells of 2 px across, 7 down, and a little air round it
    if t.seed == "clock" then w, h = 29 * 2 + 16, 7 * 2 + 8 end
    -- BMO (D253): his face at three fifths of the bar's, on a small screen of its own
    if t.seed == "bmo" then w, h = 40, 28 end
    return { seed_w = w, seed_h = h, round = t.round / 100, top = t.top }
end

return M
