-- The wallpaper studio's recipe (Lumen): what an edit is, the vibes it starts from, and the
-- ImageMagick arguments that make it. Pure: no files, no processes — tests/unit runs it under
-- Lua 5.4, and shell/mooi-wallpaper.luau is what runs the arguments.
--
-- A recipe is flat numbers:
--   exposure -50..50 · contrast -50..50 · fade 0..100 · saturation 0..200 · warmth -100..100
--   tint -100..100 · hue -180..180 · zoom 100..200 · fx 0..100 · fy 0..100
--   vignette 0..100 · grain 0..100
-- `zoom` and `fx`/`fy` are the crop: a zoom of 200 keeps half the picture, and the point at
-- fraction fx/fy of the frame stays at that fraction of the frame (click the picture to put
-- the subject there). The picture itself is never touched: the output is a new file.

local M = {}

M.VERSION = 1
M.PREVIEW_W, M.PREVIEW_H = 1600, 900   -- quick enough to redraw under a slider
M.RECIPES_MAX = 40                     -- remembered sources; the oldest is forgotten

-- The sliders, in tab order. `index` is the code the scene sends back (code * 1000 + offset).
M.FIELDS = {
    { key = "exposure",   label = "Exposure",   min = -50,  max = 50,  def = 0,   unit = "",  signed = true,  tab = 0 },
    { key = "contrast",   label = "Contrast",   min = -50,  max = 50,  def = 0,   unit = "",  signed = true,  tab = 0 },
    { key = "fade",       label = "Fade",       min = 0,    max = 100, def = 0,   unit = "%", signed = false, tab = 0 },
    { key = "saturation", label = "Saturation", min = 0,    max = 200, def = 100, unit = "%", signed = false, tab = 1 },
    { key = "warmth",     label = "Warmth",     min = -100, max = 100, def = 0,   unit = "",  signed = true,  tab = 1 },
    { key = "tint",       label = "Tint",       min = -100, max = 100, def = 0,   unit = "",  signed = true,  tab = 1 },
    { key = "hue",        label = "Hue",        min = -180, max = 180, def = 0,   unit = "°", signed = true,  tab = 1 },
    { key = "zoom",       label = "Zoom",       min = 100,  max = 200, def = 100, unit = "%", signed = false, tab = 2 },
    { key = "fx",         label = "Focus X",    min = 0,    max = 100, def = 50,  unit = "%", signed = false, tab = 2 },
    { key = "fy",         label = "Focus Y",    min = 0,    max = 100, def = 50,  unit = "%", signed = false, tab = 2 },
    { key = "vignette",   label = "Vignette",   min = 0,    max = 100, def = 0,   unit = "%", signed = false, tab = 3 },
    { key = "grain",      label = "Grain",      min = 0,    max = 100, def = 0,   unit = "%", signed = false, tab = 3 },
    -- The backdrop (D60): a matte round the picture, and what fills it — black, a blurred copy
    -- of the picture, or one of the three colours read from its edges. `bg` has no slider;
    -- the backdrop tab's swatches set it.
    { key = "matte",      label = "Matte",       min = 0,    max = 25,  def = 0,   unit = "%", signed = false, tab = 4 },
    { key = "bg",         label = "Backdrop",    min = 0,    max = 5,   def = 0,   unit = "",  signed = false, tab = -1 },
    { key = "bg_blur",    label = "Backdrop blur", min = 0,  max = 100, def = 35,  unit = "%", signed = false, tab = 4 },
    { key = "bg_dim",     label = "Backdrop dim", min = 0,   max = 100, def = 35,  unit = "%", signed = false, tab = 4 },
    -- Keying the background out (D61, D62): what the picture's edge is filled with becomes the
    -- backdrop, so its own background is replaced, not framed. `key` has no slider; the backdrop
    -- tab's toggle sets it. `bg_custom` is the colour mode 5 fills with (D62).
    { key = "key",        label = "Key background", min = 0, max = 1,   def = 0,   unit = "",  signed = false, tab = -1 },
    { key = "key_fuzz",   label = "Key fuzz",    min = 0,    max = 45,  def = 18,  unit = "%", signed = false, tab = 4 },
}
M.BG_INDEX = { black = 0, picture = 1, corners = 2, edges = 3, both = 4, custom = 5 }
M.BG_NAME = { "black", "picture", "corners", "edges", "both", "custom" }
M.CUSTOM_DEF = "#808080"

-- The backdrop's palette (D63): the shell's own colours first — the same ones the bar wears, so a
-- fill can be part of the theme — and the two neutrals a backdrop usually wants. `role` is looked
-- up in the resolved palette (`lib/ferro`); `hex` is used as it is.
M.SWATCHES = {
    { name = "BLACK", hex = "#000000" },
    { name = "INK",   role = "ink" },
    { name = "HULL",  role = "hull" },
    { name = "WELL",  role = "well" },
    { name = "WHITE", hex = "#ffffff" },
    { name = "PHOS",  role = "phos" },
    { name = "TRACE", role = "trace_lit" },
    { name = "EMBER", role = "ember" },
    { name = "FLARE", role = "flare" },
}
M.BY = {}
for i, f in ipairs(M.FIELDS) do f.index = i - 1; M.BY[f.key] = f end
M.TABS = { "TONE", "COLOUR", "FRAME", "FX", "BACKDROP" }

-- The vibes. `values` is what differs from neutral; the rest of the recipe stays as it is when
-- a vibe is chosen (the crop is the user's, not the look's).
M.PRESETS = {
    { id = "natural",   name = "NATURAL",   hint = "the picture, as it is",
      values = {} },
    { id = "ferrolume", name = "FERROLUME", hint = "teal shadow, warm signal",
      values = { exposure = 2, contrast = 8, saturation = 108, warmth = -4, tint = 2, vignette = 12, grain = 4 } },
    { id = "dusk",      name = "DUSK",      hint = "low sun, long shadows",
      values = { exposure = -4, contrast = 10, saturation = 118, warmth = 16, tint = 4, hue = 6, vignette = 18, grain = 3 } },
    { id = "cold",      name = "COLD SIGNAL", hint = "ice, steel, distance",
      values = { exposure = -2, contrast = 12, saturation = 96, warmth = -18, tint = -4, hue = -4, vignette = 20, grain = 5 } },
    { id = "sunbleach", name = "SUNBLEACH", hint = "a print left in the sun",
      values = { exposure = 7, contrast = -12, fade = 22, saturation = 104, warmth = 12, tint = 2, vignette = 6, grain = 10 } },
    { id = "noir",      name = "NEON NOIR", hint = "ink blacks, hard light",
      values = { exposure = -8, contrast = 22, saturation = 126, warmth = -10, tint = 8, hue = -6, vignette = 36, grain = 7 } },
    { id = "ash",       name = "ASH",       hint = "soft, grey, quiet",
      values = { exposure = 1, contrast = -8, fade = 26, saturation = 72, warmth = -6, tint = -2, vignette = 10, grain = 14 } },
    { id = "bluehour",  name = "BLUE HOUR", hint = "just after sunset",
      values = { exposure = -6, contrast = 7, saturation = 98, warmth = -22, tint = 6, hue = 8, vignette = 22, grain = 4 } },
    { id = "mono",      name = "MONO",      hint = "no colour, only weight",
      values = { exposure = 2, contrast = 15, fade = 4, saturation = 0, vignette = 12, grain = 8 } },
}

local function round(v) return math.floor(v + 0.5) end
local function clamp(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end

-- A fresh recipe: the picture as it is.
function M.neutral()
    local r = { preset = "natural", bg_custom = M.CUSTOM_DEF }
    for _, f in ipairs(M.FIELDS) do r[f.key] = f.def end
    return r
end

-- A recipe with every field a number in range, and a preset name (or "custom").
function M.clean(v)
    local r = M.neutral()
    if type(v) ~= "table" then return r end
    for _, f in ipairs(M.FIELDS) do
        local n = tonumber(v[f.key])
        if n and n == n then r[f.key] = round(clamp(n, f.min, f.max)) end
    end
    if type(v.bg_custom) == "string" then
        local hex = string.lower(v.bg_custom)
        if hex:match("^#%x%x%x%x%x%x$") then r.bg_custom = hex end
    end
    if v.preset ~= nil then
        local id = tostring(v.preset)
        if id == "custom" then r.preset = "custom" end
        for _, p in ipairs(M.PRESETS) do if p.id == id then r.preset = id; break end end
    end
    return r
end

-- The recipe a vibe starts from: the neutral recipe with the vibe's values, its name kept.
function M.preset(id)
    for _, p in ipairs(M.PRESETS) do
        if p.id == id then
            local r = M.neutral()
            for k, v in pairs(p.values) do r[k] = v end
            r.preset = p.id
            return M.clean(r)
        end
    end
    return M.neutral()
end

-- Which vibe a recipe is, or nil when it is one of its own.
function M.matches(r)
    r = M.clean(r)
    for _, p in ipairs(M.PRESETS) do
        local same = true
        for k in pairs({ exposure = 1, contrast = 1, fade = 1, saturation = 1, warmth = 1, tint = 1,
                         hue = 1, vignette = 1, grain = 1 }) do
            if r[k] ~= M.preset(p.id)[k] then same = false; break end
        end
        if same then return p.id end
    end
    return nil
end

-- A value as the studio writes it: +3, 118 %, −12 ° (the sign is the ASCII one the UI's mono face has).
function M.fmt(key, v)
    local f = M.BY[key]
    if not f then return tostring(v) end
    local n = round(tonumber(v) or f.def)
    local sign = ""
    if f.signed and n > 0 then sign = "+" end
    return sign .. tostring(n) .. f.unit
end

-- A recipe's size in words, for the record: "DUSK · 118 % · VIGNETTE 18".
function M.summary(r)
    r = M.clean(r)
    local id = M.matches(r) or "custom"
    local name = "CUSTOM"
    for _, p in ipairs(M.PRESETS) do if p.id == id then name = p.name end end
    local parts = { name }
    if r.zoom ~= 100 then parts[#parts + 1] = r.zoom .. "% ZOOM" end
    if r.vignette > 0 then parts[#parts + 1] = "VIGNETTE " .. r.vignette end
    if r.key > 0 then parts[#parts + 1] = "KEYED" end
    return table.concat(parts, " · ")
end

-- ── The pixels ─────────────────────────────────────────────────
-- Append the base's crop and the grade, from `source`, at `w × h`: the crop keeps the point at
-- (fx, fy) of the frame where it was, and the result is resized to the output. Every argument is
-- one argv entry; nothing goes through a shell.
local function grade(a, r, source, w, h, bw, bh, key)
    a[#a + 1] = source
    a[#a + 1] = "-auto-orient"

    -- The crop is cut from the base in the base's own pixels (the caller knows how big it is).
    bw, bh = tonumber(bw), tonumber(bh)
    if r.zoom > 100 and bw and bh and bw > 0 and bh > 0 then
        local ox, oy, cw, ch = M.crop(r, bw, bh)
        a[#a + 1] = "-crop"
        a[#a + 1] = string.format("%dx%d+%d+%d", cw, ch, ox, oy)
        a[#a + 1] = "+repage"
    end

    a[#a + 1] = "-resize"
    a[#a + 1] = string.format("%dx%d!", w, h)

    if r.saturation ~= 100 or r.hue ~= 0 then
        a[#a + 1] = "-modulate"
        a[#a + 1] = string.format("100,%d,%.2f", r.saturation, 100 + r.hue / 3.6)
    end
    local exposure = r.exposure * 0.5
    if exposure ~= 0 or r.contrast ~= 0 then
        a[#a + 1] = "-brightness-contrast"
        a[#a + 1] = string.format("%.1fx%.1f", exposure, r.contrast)
    end
    if r.warmth ~= 0 or r.tint ~= 0 then
        local mr = 1 + r.warmth * 0.0012
        local mb = 1 - r.warmth * 0.0012
        local tg = 1 - r.tint * 0.0010
        local tr = 1 + r.tint * 0.0006
        local tb = 1 + r.tint * 0.0006
        a[#a + 1] = "-color-matrix"
        a[#a + 1] = string.format("%.4f 0 0 0 %.4f 0 0 0 %.4f", mr * tr, tg, mb * tb)
    end
    if r.fade > 0 then
        a[#a + 1] = "-fill"; a[#a + 1] = "#8a8a8a"
        a[#a + 1] = "-colorize"; a[#a + 1] = string.format("%.1f%%", r.fade * 0.14)
    end
    if r.vignette > 0 then
        local s = 0.9 * r.vignette / 100
        a[#a + 1] = "("
        a[#a + 1] = "-size"; a[#a + 1] = string.format("%dx%d", w, h)
        a[#a + 1] = "radial-gradient:white-black"
        a[#a + 1] = "-level"; a[#a + 1] = "45%,100%"
        a[#a + 1] = "-evaluate"; a[#a + 1] = "multiply"; a[#a + 1] = string.format("%.3f", s)
        a[#a + 1] = "-evaluate"; a[#a + 1] = "add"; a[#a + 1] = string.format("%d%%", round((1 - s) * 100))
        a[#a + 1] = ")"
        a[#a + 1] = "-compose"; a[#a + 1] = "multiply"; a[#a + 1] = "-composite"
    end
    if r.grain > 0 then
        -- Colour channels only: a keyed picture's transparency has to survive its grain.
        a[#a + 1] = "-channel"; a[#a + 1] = "RGB"
        a[#a + 1] = "-attenuate"; a[#a + 1] = string.format("%.3f", 0.05 + r.grain * 0.0045)
        a[#a + 1] = "+noise"; a[#a + 1] = "Gaussian"
        a[#a + 1] = "+channel"
    end
    if key then
        -- Keyed out last (D62), so no composite or grain can put the transparency back. A flood
        -- fill from the eight border points takes the background the picture's edge is connected
        -- to — the picture's own background, not every pixel of that colour — so a white eye in
        -- the subject stays white. The fill seeds on the pixels themselves, so it needs no colour
        -- read from anywhere and holds after the grade has moved the colours.
        local x1, y1 = math.max(0, w - 1), math.max(0, h - 1)
        local xm, ym = math.floor(w / 2), math.floor(h / 2)
        local pts = { { 0, 0 }, { x1, 0 }, { 0, y1 }, { x1, y1 }, { xm, 0 }, { xm, y1 }, { 0, ym }, { x1, ym } }
        local draw = {}
        for i, p in ipairs(pts) do draw[i] = string.format("alpha %d,%d floodfill", p[1], p[2]) end
        a[#a + 1] = "-alpha"; a[#a + 1] = "set"
        a[#a + 1] = "-fuzz"; a[#a + 1] = string.format("%d%%", r.key_fuzz)
        a[#a + 1] = "-fill"; a[#a + 1] = "none"
        a[#a + 1] = "-draw"; a[#a + 1] = table.concat(draw, " ")
    end
end

-- `bg` is the backdrop (D60): `mode` 0 black, 1 the picture blurred and dimmed, 2–4 one of the
-- colours read from the picture (`hex`), 5 the colour typed in the studio (`bg_custom`); `blur`
-- and `dim` are its effects. A matte of 0 hides the backdrop, but a keyed picture still needs one
-- behind it.
function M.args(r, source, out, w, h, bw, bh, bg)
    r = M.clean(r)
    w, h = round(tonumber(w) or M.PREVIEW_W), round(tonumber(h) or M.PREVIEW_H)
    if type(source) ~= "string" or source == "" or type(out) ~= "string" or out == "" then return nil end
    local a = {}
    local m = round(math.min(w, h) * r.matte / 100)
    local key = r.key > 0

    if m > 0 or key then
        local iw, ih = math.max(1, w - 2 * m), math.max(1, h - 2 * m)
        a[#a + 1] = "("
        if bg and tonumber(bg.mode) == 1 then
            -- The picture itself, filling the screen and softened: the matte is the same picture
            -- out of focus, not a colour chosen beside it.
            a[#a + 1] = source; a[#a + 1] = "-auto-orient"
            a[#a + 1] = "-resize"; a[#a + 1] = string.format("%dx%d^", w, h)
            a[#a + 1] = "-gravity"; a[#a + 1] = "center"
            a[#a + 1] = "-crop"; a[#a + 1] = string.format("%dx%d+0+0", w, h); a[#a + 1] = "+repage"
            local blur = tonumber(bg.blur) or 0
            if blur > 0 then a[#a + 1] = "-blur"; a[#a + 1] = string.format("0x%.1f", 0.6 + blur * 0.12) end
            local dim = tonumber(bg.dim) or 0
            if dim > 0 then
                a[#a + 1] = "-fill"; a[#a + 1] = "#000000"
                a[#a + 1] = "-colorize"; a[#a + 1] = string.format("%.0f%%", dim * 0.65)
            end
        else
            local hex = bg and type(bg.hex) == "string" and bg.hex or "#000000"
            a[#a + 1] = "-size"; a[#a + 1] = string.format("%dx%d", w, h)
            a[#a + 1] = "xc:" .. hex
        end
        a[#a + 1] = ")"
        a[#a + 1] = "("
        grade(a, r, source, iw, ih, bw, bh, key)
        a[#a + 1] = ")"
        a[#a + 1] = "-gravity"; a[#a + 1] = "center"; a[#a + 1] = "-composite"
    else
        grade(a, r, source, w, h, bw, bh)
    end

    -- The output is written the way its extension asks (D63). A still that goes on the desktop is
    -- a PNG and lossless; a preview is a JPEG, and it keeps all of its colour detail: `4:4:4`
    -- writes the colour channels at full resolution, so a flat fill or a hard edge does not smear
    -- its hue into its neighbours the way the default 4:2:0 does.
    a[#a + 1] = "-strip"
    if M.is_png(out) then
        a[#a + 1] = "-define"; a[#a + 1] = "png:compression-level=6"
    else
        a[#a + 1] = "-sampling-factor"; a[#a + 1] = "4:4:4"
        a[#a + 1] = "-quality"; a[#a + 1] = "95"
    end
    a[#a + 1] = out
    return a
end

-- Whether an output name is a PNG, whose pixels are kept exactly.
function M.is_png(out)
    return string.lower(tostring(out or ""):match("%.([%w]+)$") or "") == "png"
end

-- ── The picture's background ─────────────────────────────────────
-- The colours the picture's edges wear, read from a 96 × 54 copy: four corners and four edge
-- midpoints, averaged into three: the corners, the edges, and all eight. `edge_colours` parses
-- the hex `magick` prints; it is pure, so tests/unit runs it under Lua.
M.EDGE_W, M.EDGE_H = 96, 54
local EDGE_POINTS = { { 0, 0 }, { 95, 0 }, { 0, 53 }, { 95, 53 }, { 47, 0 }, { 47, 53 }, { 0, 26 }, { 95, 26 } }
function M.edge_args(source)
    if type(source) ~= "string" or source == "" then return nil end
    local fmt = {}
    for i, p in ipairs(EDGE_POINTS) do fmt[i] = string.format("%%[hex:p{%d,%d}]", p[1], p[2]) end
    return { source, "-auto-orient", "-resize", string.format("%dx%d!", M.EDGE_W, M.EDGE_H),
             "-format", table.concat(fmt, " "), "info:" }
end
function M.edge_colours(out)
    local list = {}
    for hex in tostring(out or ""):gmatch("%x%x%x%x%x%x") do
        list[#list + 1] = { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) }
        if #list == 8 then break end
    end
    if #list < 8 then return nil end
    local function avg(from, to)
        local r, g, b = 0, 0, 0
        for i = from, to do r, g, b = r + list[i][1], g + list[i][2], b + list[i][3] end
        local n = to - from + 1
        return string.format("#%02x%02x%02x", round(r / n), round(g / n), round(b / n))
    end
    return { avg(1, 4), avg(5, 8), avg(1, 8) }
end

-- The crop rectangle for a base of `bw × bh` pixels: x, y, width, height in whole pixels.
function M.crop(r, bw, bh)
    r = M.clean(r)
    bw, bh = round(tonumber(bw) or 0), round(tonumber(bh) or 0)
    if bw < 1 or bh < 1 then return 0, 0, 1, 1 end
    if r.zoom <= 100 then return 0, 0, bw, bh end
    local cw = math.max(1, round(bw / (r.zoom / 100)))
    local ch = math.max(1, round(bh / (r.zoom / 100)))
    local ox = round((bw - cw) * r.fx / 100)
    local oy = round((bh - ch) * r.fy / 100)
    return clamp(ox, 0, bw - cw), clamp(oy, 0, bh - ch), cw, ch
end

-- The base arguments: the source, cropped to cover `bw × bh` and centred. This is made once per
-- source, then every preview and the final come off it.
function M.base_args(source, out, bw, bh)
    if type(source) ~= "string" or source == "" or type(out) ~= "string" or out == "" then return nil end
    bw, bh = round(tonumber(bw) or 0), round(tonumber(bh) or 0)
    if bw < 1 or bh < 1 then return nil end
    -- Lossless (D63): the base is what every preview and the still are cut from, so a JPEG here
    -- would be one more generation of loss under every edit. Lanczos is named rather than left to
    -- the build's default, so an upscaled base is the sharpest it can be.
    return { source, "-auto-orient",
             "-filter", "Lanczos",
             "-resize", string.format("%dx%d^", bw, bh),
             "-gravity", "center", "-crop", string.format("%dx%d+0+0", bw, bh), "+repage",
             "-strip", "-define", "png:compression-level=6", out }
end

-- A short, stable name for a source path (the base's file name).
function M.hash(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 4294967296 end
    return string.format("%08x", h)
end

-- ── The folder the pictures come from ─────────────────────────
-- A wallpaper folder is just a directory the studio reads: `find` lists it, and the studio keeps
-- the choice in wallpapers.json. The pictures themselves are never touched.
M.IMAGE_EXTS = {
    png = true, jpg = true, jpeg = true, jfif = true, jpe = true, webp = true, avif = true,
    gif = true, apng = true, jxl = true, bmp = true, tif = true, tiff = true, heic = true,
    heif = true, svg = true, ico = true, tga = true, dds = true, exr = true, hdr = true,
    pnm = true, ppm = true, pgm = true, pbm = true,
}

-- Whether a file is a picture by its extension (the folder is read by name: no file is opened to
-- decide whether to show it).
function M.is_image(name)
    local ext = tostring(name or ""):match("%.([%w]+)$")
    return ext ~= nil and M.IMAGE_EXTS[string.lower(ext)] == true
end

-- A folder typed in the studio: trimmed, `~` expanded (only `~` and `~/…`: `~other` is a name,
-- not this home), relative names taken under the home folder, no trailing slash. Empty stays empty.
function M.folder_path(s, home)
    s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return "" end
    home = tostring(home or "")
    if s == "~" or s:sub(1, 2) == "~/" then s = home .. s:sub(2) end
    if s:sub(1, 1) ~= "/" then s = home .. "/" .. s end
    s = s:gsub("//+", "/")
    if #s > 1 then s = s:gsub("/+$", "") end
    return s
end

-- The folder a file is in (`""` when the path has no folder at all).
function M.folder_of(path)
    local p = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if p == "" then return "" end
    local d = p:match("^(.*)/[^/]+$")
    if d == nil then return "" end
    if d == "" then return "/" end
    return d
end

-- The last part of a path, as a tile says it.
function M.base_name(path)
    return tostring(path or ""):match("([^/]+)$") or tostring(path or "")
end

-- The folder above `path`, for the picker: `/` stays `/`, and a folder that has no parent (or a
-- path with no folder at all) is the home folder's place — the caller gives it a start.
function M.parent(path)
    local p = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if p == "" or p == "/" then return "/" end
    local d = p:match("^(.*)/[^/]+$")
    if d == nil then return "" end
    if d == "" then return "/" end
    return d
end

-- A subfolder's path, from the folder and the name `find` printed.
function M.child(path, name)
    local p = tostring(path or "")
    local n = tostring(name or "")
    if n == "" then return p end
    if p == "" then return n end
    if p:sub(-1) == "/" then return p .. n end
    return p .. "/" .. n
end

-- What `find <folder> -mindepth 1 -maxdepth 1 -type d -printf '%f\n'` said: the names, A→Z (the
-- picker's order), never empty. `path` is where they were found.
function M.parse_dirs(out, path)
    local list = {}
    for line in tostring(out or ""):gmatch("[^\n]+") do
        local name = line:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then list[#list + 1] = { name = name, path = M.child(path, name) } end
    end
    table.sort(list, function(a, b)
        local la, lb = string.lower(a.name), string.lower(b.name)
        if la ~= lb then return la < lb end
        return a.name < b.name
    end)
    return list
end

-- What `find <folder> -maxdepth 1 -type f -printf '%T@\t%p\n'` said: pictures only, newest first,
-- then by name. A line that is not `<seconds>\t<path>` is skipped, so a warning on the output does
-- not become a tile.
function M.parse_find(out)
    local list = {}
    for line in tostring(out or ""):gmatch("[^\n]+") do
        local t, p = line:match("^([%d%.]+)\t(.+)$")
        if p and M.is_image(p) then
            list[#list + 1] = { path = p, name = M.base_name(p), mtime = tonumber(t) or 0, dims = "" }
        end
    end
    table.sort(list, function(a, b)
        if a.mtime ~= b.mtime then return a.mtime > b.mtime end
        return a.name < b.name
    end)
    return list
end

-- A tile's picture: the first frame, cropped to fill `w × h` in the middle. The thumbnail is a new
-- file in the studio's cache; the source is only read.
function M.thumb_args(source, out, w, h)
    if type(source) ~= "string" or source == "" or type(out) ~= "string" or out == "" then return nil end
    w, h = round(tonumber(w) or 282), round(tonumber(h) or 158)
    return { source .. "[0]", "-auto-orient",
             "-filter", "Lanczos",
             "-thumbnail", string.format("%dx%d^", w, h),
             "-gravity", "center", "-extent", string.format("%dx%d", w, h),
             "-strip", "-sampling-factor", "4:4:4", "-quality", "88", out }
end

-- ── The file ───────────────────────────────────────────────────
function M.state(v)
    local out = { version = 1, last = "", folder = "", recipes = {}, edges = {}, applied = nil }
    if type(v) ~= "table" then return out end
    if type(v.last) == "string" then out.last = v.last end
    if type(v.folder) == "string" then out.folder = v.folder end
    if type(v.edges) == "table" then
        for k, e in pairs(v.edges) do
            local c = type(e) == "table" and e.c
            if type(k) == "string" and type(c) == "table" then
                local hex = {}
                for i = 1, 3 do
                    local h = tostring(c[i] or "")
                    if h:match("^#%x%x%x%x%x%x$") then hex[i] = string.lower(h) end
                end
                if #hex == 3 then out.edges[k] = { c = hex, at = tonumber(e.at) or 0 } end
            end
        end
    end
    if type(v.recipes) == "table" then
        for k, e in pairs(v.recipes) do
            if type(k) == "string" and type(e) == "table" and type(e.r) == "table" then
                out.recipes[k] = { r = M.clean(e.r), at = tonumber(e.at) or 0 }
            end
        end
    end
    if type(v.applied) == "table" and type(v.applied.file) == "string" and type(v.applied.source) == "string" then
        out.applied = { source = v.applied.source, file = v.applied.file, at = tonumber(v.applied.at) or 0 }
    end
    return out
end

-- Remember one source's recipe; the oldest is dropped past RECIPES_MAX. Mutates and returns `s`.
function M.remember(s, source, r, now)
    if type(s) ~= "table" or type(source) ~= "string" or source == "" then return s end
    s.recipes = type(s.recipes) == "table" and s.recipes or {}
    s.recipes[source] = { r = M.clean(r), at = tonumber(now) or 0 }
    s.last = source
    local n = 0
    for _ in pairs(s.recipes) do n = n + 1 end
    if n > M.RECIPES_MAX then
        local oldest, when = nil, nil
        for k, e in pairs(s.recipes) do
            local t = tonumber(e.at) or 0
            if not when or t < when then oldest, when = k, t end
        end
        if oldest and oldest ~= source then s.recipes[oldest] = nil end
    end
    return s
end
-- The edges read from `source` last time (D61), or nil: the swatches can be drawn before
-- ImageMagick has run again.
function M.edges_of(s, source)
    if type(s) ~= "table" or type(s.edges) ~= "table" then return nil end
    local e = s.edges[source]
    if type(e) == "table" and type(e.c) == "table" and #e.c == 3 then return e.c end
end

-- Keep the three colours read from `source`'s edges; the oldest is dropped past RECIPES_MAX.
-- Mutates and returns `s`.
function M.remember_edges(s, source, cols, now)
    if type(s) ~= "table" or type(source) ~= "string" or source == "" or type(cols) ~= "table" then return s end
    local c = {}
    for i = 1, 3 do
        local h = tostring(cols[i] or "")
        if not h:match("^#%x%x%x%x%x%x$") then return s end
        c[i] = string.lower(h)
    end
    s.edges = type(s.edges) == "table" and s.edges or {}
    s.edges[source] = { c = c, at = tonumber(now) or 0 }
    local n = 0
    for _ in pairs(s.edges) do n = n + 1 end
    if n > M.RECIPES_MAX then
        local oldest, when = nil, nil
        for k, e in pairs(s.edges) do
            local t = tonumber(e.at) or 0
            if (not when or t < when) and k ~= source then oldest, when = k, t end
        end
        if oldest then s.edges[oldest] = nil end
    end
    return s
end

return M
