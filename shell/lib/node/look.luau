-- The node's look (D229): everything the Pill studio sets, in one table kept in node-look.json. Pure: the schema
-- the studio draws its rows from, the four personalities as presets, a shuffle that makes a look of its own, the
-- check that keeps any file sane, and what the scene is told (facts) and the geometry is given (shape).
--
-- Values are kept in the units the studio shows (per cent, pixels, tenths of a pixel), so a file read by eye
-- says what the studio says. Choices are kept by name.

local M = {}

M.FILE = "node-look.json"
M.PRESETS = { "organic", "minimal", "technical", "cyber", "liquid", "neon" }
M.SLOTS = 3

-- the studio's tabs; the first is the presets' own page (no rows)
M.TABS = { "Presets", "Layout", "Modules", "Shape", "Surface", "Motion", "Music" }

-- each row: key, label, description, and either a range (lo, hi, unit) or a choice (values, names)
local function range(key, label, desc, lo, hi, unit) return { key = key, label = label, desc = desc, lo = lo, hi = hi, unit = unit or "" } end
local function choice(key, label, desc, values, names) return { key = key, label = label, desc = desc, values = values, names = names } end

-- D313: six pages, each one subject — where it is and what it holds (Layout, with the module editor beside), its
-- resting shape, its body, how it moves, and how music shows. Placement is all here (Side came from Settings).
local COLOURS_NAMED = { "Accent", "Warm", "Text", "Cool" }
M.SCHEMA = {
    Layout = {
        choice("place", "Place", "Floating under the top edge; attached to the frame as a notch; or attached only while music plays", { "floating", "attached", "music" }, { "Floating", "Attached", "With music" }),
        choice("side", "Side", "Where along the top it sits", { "centre", "left", "right" }, { "Centre", "Left", "Right" }),
        choice("ws_style", "Workspace switch", "What shows when you change workspace: a bead along a rail, a slide, a flip, a pulse, or its number", { "bead", "slide", "flip", "pulse", "count" }, { "Bead", "Slide", "Flip", "Pulse", "Number" }),
        range("cards", "Notice cards", "How many notices show at once", 1, 5, ""),
        choice("reactions", "Reactions", "A ring from it when something happens: music, a notice, the charger, the microphone", { "off", "subtle", "lively", "sparks" }, { "Off", "Subtle", "Lively", "Sparks" }),
        range("orbit", "Workspace orbit", "How wide the workspaces' orbit is (Super+Tab)", 300, 700, " px"),
    },
    -- what the pill and its corner notches hold: the editor below the one row (D313: a page of its own)
    Modules = {
        choice("music_mod", "Music module", "The Music module: four bars beside the title, the title alone, or the album cover and title", { "bars", "title", "cover" }, { "Visualiser", "Title", "Cover" }),
    },
    Shape = {
        choice("seed", "Seed", "What rests at the top while it holds no modules", { "line", "dot", "ring", "twin", "bar", "clock", "bmo", "orb", "comet" }, { "Line", "Dot", "Ring", "Twin", "Bar", "Clock", "BMO", "Orb", "Comet" }),
        choice("clock_style", "Clock style", "How the Clock seed tells the time", { "pixel", "digital", "analog", "words", "binary", "dots" }, { "Pixel", "Digits", "Hands", "Words", "Binary", "Dots" }),
        range("seed_w", "Seed width", "How long the resting seed is", 6, 80, " px"),
        range("seed_h", "Seed height", "How thick it is", 2, 16, " px"),
        range("round", "Roundness", "From square corners to a full capsule", 0, 100, "%"),
        choice("style", "Character", "The details it wears: soft, bare, ruled, or broken", { "organic", "minimal", "technical", "cyber" }, { "Organic", "Minimal", "Technical", "Cyber" }),
        range("top", "From the top", "How far below the screen's edge it floats", 0, 40, " px"),
    },
    Surface = {
        choice("texture", "Texture", "What its body is made of", { "solid", "hollow", "segmented", "scan", "dotted", "glass", "neon", "aurora" }, { "Solid", "Hollow", "Segmented", "Scan", "Dotted", "Glass", "Neon", "Aurora" }),
        range("fill", "Fill", "How solid the body is", 30, 100, "%"),
        range("outline", "Outline", "The edge's weight", 0, 30, ""),
        range("glow", "Glow", "How much light it gives off", 0, 100, "%"),
        choice("accent", "Colour", "Its own colour, from the theme", { "phos", "ember", "ink", "steel" }, COLOURS_NAMED),
        choice("glow_colour", "Glow colour", "The light's colour, from the theme", { "phos", "ember", "ink", "steel" }, COLOURS_NAMED),
        range("dim", "Search dim", "How far the desktop darkens behind the search", 0, 60, "%"),
    },
    Motion = {
        choice("speed", "Speed", "How quickly it changes shape", { "soft", "quick", "snap" }, { "Soft", "Quick", "Snap" }),
        choice("bounce", "Bounce", "How far it overshoots and settles", { "none", "some", "lots" }, { "None", "Some", "Lots" }),
        choice("growth", "Growth", "How fast what opens grows out of it", { "slow", "normal", "fast" }, { "Slow", "Normal", "Fast" }),
        range("stagger", "Stagger", "Parts one after another, or all at once", 0, 100, "%"),
        range("breath", "Breathing", "How deeply the seed breathes at rest (0: still)", 0, 100, "%"),
        range("music", "Music sway", "How much it moves with what plays", 0, 100, "%"),
        choice("trail", "Trail", "A faint ghost of its outline following it as it grows and folds", { "off", "on" }, { "Off", "On" }),
    },
    Music = {
        choice("music_form", "When music starts", "The capsule with the song, a visualiser strip, or a turning record", { "capsule", "visualiser", "vinyl" }, { "Capsule", "Spectrum", "Vinyl" }),
        choice("viz", "Capsule visualiser", "The music drawn inside the capsule", { "bars", "wave", "dots", "off" }, { "Bars", "Wave", "Dots", "Off" }),
        choice("cover", "Cover", "The album art's shape", { "square", "round" }, { "Square", "Round" }),
        choice("seed_music", "Seed with music", "What the resting seed does while music plays", { "still", "pulse", "bars" }, { "Still", "Pulse", "Bars" }),
    },
}

local BASE = {
    seed = "line", seed_w = 22, seed_h = 6, round = 100, style = "organic", top = 8,
    texture = "solid", fill = 95, outline = 10, glow = 70, accent = "phos", glow_colour = "phos",
    speed = "soft", bounce = "lots", growth = "normal", stagger = 50, breath = 35, music = 60,
    viz = "bars", cover = "square", music_form = "capsule", seed_music = "pulse", music_mod = "bars",
    place = "floating", clock_style = "pixel", ws_style = "bead", reactions = "subtle", cards = 3, dim = 28, orbit = 520,
    trail = "off", side = "centre",
}
local PRESET = {
    organic = {},
    minimal = { seed = "dot", seed_w = 6, seed_h = 6, style = "minimal", outline = 7, glow = 8, speed = "quick", bounce = "none",
                growth = "fast", stagger = 30, breath = 15, music = 20, viz = "dots", dim = 20 },
    technical = { seed = "bar", seed_w = 26, seed_h = 4, round = 18, style = "technical", texture = "scan", glow = 5,
                  speed = "quick", bounce = "none", stagger = 60, breath = 0, music = 35, cover = "square" },
    cyber = { seed = "twin", seed_w = 24, seed_h = 5, round = 32, style = "cyber", texture = "segmented", outline = 15, glow = 90,
              glow_colour = "ember", speed = "snap", bounce = "some", stagger = 80, breath = 20, music = 80, viz = "wave" },
    -- D296: two more characters to start from
    liquid = { seed = "orb", seed_w = 14, seed_h = 14, round = 100, texture = "glass", fill = 80, glow = 55, outline = 8,
               speed = "soft", bounce = "lots", growth = "normal", stagger = 40, breath = 50, music = 70,
               trail = "on", reactions = "lively", viz = "wave", cover = "round" },
    neon = { seed = "comet", seed_w = 34, seed_h = 6, round = 100, style = "cyber", texture = "neon", fill = 90, outline = 20,
             glow = 100, accent = "phos", glow_colour = "phos", speed = "quick", bounce = "some", stagger = 60, breath = 25,
             music = 90, reactions = "sparks", viz = "bars" },
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
    -- the pill's modules, in order (D257). D259: they live in the pill itself — none, and it is a seed. A look from
    -- before keeps its modules (D257) or its switched-on ones (D248); a notch is now a place, attached
    local src = t.modules
    if type(src) ~= "table" and (t.m_clock or t.m_window or t.m_spaces or t.m_battery or t.m_music) then
        src = {}
        for _, k in ipairs({ "spaces", "window", "music", "battery", "clock" }) do if t["m_" .. k] == "on" then src[#src + 1] = k end end
    end
    -- (modules someone added are kept whatever "at rest" said: they were added to be seen)
    if t.rest == "notch" and t.place == nil then out.place = "attached" end
    out.modules = M.modules(src or {})
    -- D295: the frame's corner notches (Minflair's): what the top-left and top-right ones hold; none, no notch there
    out.left = M.modules(t.left or {})
    out.right = M.modules(t.right or {})
    -- the saved looks: up to M.SLOTS, each a look of its own (or nothing)
    out.slots = {}
    if type(t.slots) == "table" then
        for i = 1, M.SLOTS do
            local s = t.slots[i]
            if type(s) == "table" then
                local c = {}
                for k, _ in pairs(base) do if k ~= "preset" then c[k] = s[k] end end
                c.preset, c.custom, c.modules = s.preset, s.custom, s.modules
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
    return word, (v - row.lo) / math.max(1, row.hi - row.lo), -1
end

-- whether a row can matter under the look as it stands (D261): a choice that has no effect is still worth
-- reading, but not worth dragging. Returns false and the reason it cannot matter.
local function applicable(t, row)
    local form = M.form(t)
    local seedless = "The pill holds modules: there is no seed to shape."
    if row.key == "seed" or row.key == "seed_w" or row.key == "seed_h" or row.key == "breath" then
        if form ~= "seed" then return false, seedless end
    end
    if row.key == "clock_style" then
        if form ~= "seed" or t.seed ~= "clock" then return false, "Only the clock seed tells the time this way (Shape → Seed → Clock)." end
    end
    if row.key == "music_mod" then
        local placed = false
        for _, side in ipairs({ "modules", "left", "right" }) do
            for _, k in ipairs(type(t[side]) == "table" and t[side] or {}) do if k == "music" then placed = true end end
        end
        if not placed then return false, "Add the Music module to the pill or a corner first." end
    end
    -- D313: attached, its body is the frame's — its fill and its line — so these do nothing there
    if t.place == "attached" and (row.key == "texture" or row.key == "fill" or row.key == "outline") then
        return false, "Attached, it wears the frame's own fill and line."
    end
    if row.key == "top" and t.place == "attached" then return false, "Attached, its top is the frame's." end
    if row.key == "round" and form == "notch" then return false, "A notch takes its corners from the frame." end
    if row.key == "viz" and t.music_form ~= "capsule" then return false, "The visualiser is the media capsule's shape." end
    if row.key == "cover" and t.music_form == "visualiser" then return false, "A visualiser shows no cover." end
    return true, row.desc
end
M.applicable = applicable

-- the rows of a tab, as the studio's model takes them
function M.rows(t, tab)
    local out = {}
    for i, row in ipairs(M.SCHEMA[tab] or {}) do
        local word, frac, sel = M.shown(t, row)
        local on, why = applicable(t, row)
        local r = { kind = row.values and 1 or 0, label = row.label, desc = row.desc, value = word, frac = frac, sel = sel,
                    n = row.values and #row.values or 0, off = not on, why = why }
        for j = 0, 8 do r["o" .. j] = row.names and row.names[j + 1] or "" end
        out[i] = r
    end
    return out
end

-- the modules a long pill or a notch can hold (D257), and the word each wears in the studio
M.MODULES = { "logo", "spaces", "window", "music", "clock", "date", "battery", "cpu", "ram", "volume", "weather", "notices", "tray", "status", "power" }
M.MODULE_NAMES = { spaces = "Workspaces", window = "Window", music = "Music", clock = "Clock", date = "Date",
                   battery = "Battery", cpu = "CPU", ram = "Memory", volume = "Volume", weather = "Weather",
                   notices = "Notices", logo = "Logo", tray = "Tray", status = "Status icons", power = "Power" }   -- D311: Minflair's own   -- (D310: the Clock face module, D308, is gone: the Clock module tells the time)
M.MODULES_MAX = 8
M.MODULES_DEFAULT = { "spaces", "window", "music", "clock" }
-- a list made sane: known names, each once, at most MODULES_MAX, in the order given (none is none: a seed)
function M.modules(list)
    if type(list) ~= "table" then return {} end
    local out, seen = {}, {}
    for _, k in ipairs(list) do
        if M.MODULE_NAMES[k] and not seen[k] and #out < M.MODULES_MAX then seen[k] = true; out[#out + 1] = k end
    end
    return out
end
-- the editor's moves: add one at the end, take one out, move one a place left (-1) or right (1). `field` is which
-- list: the pill's own ("modules", the default) or a corner notch's ("left", "right"; D295)
local FIELDS = { modules = true, left = true, right = true }
local function field_of(f) return FIELDS[f] and f or "modules" end
function M.module_add(t, k, field)
    field = field_of(field)
    local l = M.modules(t[field])
    for _, x in ipairs(l) do if x == k then return false end end
    if not M.MODULE_NAMES[k] or #l >= M.MODULES_MAX then return false end
    l[#l + 1] = k
    t[field], t.custom = l, true
    return true
end
function M.module_remove(t, i, field)
    field = field_of(field)
    local l = M.modules(t[field])
    if not l[i] then return false end
    table.remove(l, i)
    t[field], t.custom = l, true
    return true
end
function M.module_move(t, i, d, field)
    field = field_of(field)
    local l = M.modules(t[field])
    local j = i + d
    if not l[i] or not l[j] then return false end
    l[i], l[j] = l[j], l[i]
    t[field], t.custom = l, true
    return true
end

-- what the pill is at rest (D259): attached to the frame, a notch; holding modules, a pill as wide as they are;
-- neither, a seed. D264: "music" attaches it only while something plays (`playing`, from the logic)
function M.form(t, playing)
    if t.place == "attached" or (t.place == "music" and playing == true) then return "notch" end
    if type(t.modules) == "table" and #t.modules > 0 then return "long" end
    return "seed"
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
        nd_seed = ix({ "line", "dot", "ring", "twin", "bar", "clock", "bmo", "orb", "comet" }, t.seed), nd_rnd = t.round / 100,
        nd_tex = ix({ "solid", "hollow", "segmented", "scan", "dotted", "glass", "neon", "aurora" }, t.texture), nd_fill = t.fill / 100,
        nd_trl = ix({ "off", "on" }, t.trail), nd_mmod = ix({ "bars", "title", "cover" }, t.music_mod),
        nd_ol = t.outline / 10, nd_gw = t.glow / 100, nd_ac = ix(COLOURS, t.accent), nd_gc = ix(COLOURS, t.glow_colour),
        nd_stg = t.stagger / 100, nd_bd = t.breath / 100, nd_mu = t.music / 100,
        nd_viz = ix({ "bars", "wave", "dots", "off" }, t.viz), nd_cov = ix({ "square", "round" }, t.cover),
        nd_ldm = t.dim / 100, nd_ur = t.orbit,
        nd_long = ({ seed = 0, long = 1, notch = 2 })[M.form(t)],
        nd_cks = ix({ "pixel", "digital", "analog", "words", "binary", "dots" }, t.clock_style),
        nd_wss = ix({ "bead", "slide", "flip", "pulse", "count" }, t.ws_style),
        nd_rxl = ix({ "off", "subtle", "lively", "sparks" }, t.reactions),
        nd_mf = ix({ "capsule", "visualiser", "vinyl" }, t.music_form), nd_smu = ix({ "still", "pulse", "bars" }, t.seed_music),
    }
end

-- what the geometry needs: the seed's size, the corners, where it sits
function M.shape(t)
    local w, h = t.seed_w, t.seed_h
    if t.seed == "dot" or t.seed == "ring" then w = math.max(h, math.min(w, 16)); h = w end
    -- D296: an orb is round and a little larger; a comet is a head with its tail
    if t.seed == "orb" then w = math.max(10, math.min(math.max(w, h), 22)); h = w end
    if t.seed == "comet" then w = math.max(24, w); h = math.max(4, math.min(h, 10)) end
    -- the clock (D241): its matrix sets its size — 29 cells of 2 px across, 7 down, and a little air round it
    if t.seed == "clock" then
        -- (D255) each way of telling the time its own size
        local S = { pixel = { 74, 22 }, digital = { 62, 22 }, analog = { 26, 26 }, words = { 170, 22 }, binary = { 56, 22 }, dots = { 86, 22 } }
        local sz = S[t.clock_style] or S.pixel
        w, h = sz[1], sz[2]
    end
    -- BMO (D253): his face at three fifths of the bar's, on a small screen of its own
    if t.seed == "bmo" then w, h = 40, 28 end
    return { seed_w = w, seed_h = h, round = t.round / 100, top = t.top }
end

return M
