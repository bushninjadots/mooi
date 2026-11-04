-- mooi's wallpapers (D145): what kind a file is, the picker's lists (source, search), the strip's
-- window and the colour orbit's places. Pure: tests/unit runs it under Lua 5.4. The index it reads
-- is tools/wallindex.py's (~/.cache/mooi/walls/index.json); `mooi wall apply` does the wearing.
--
-- `settings.walls`:
--   folders   { "~/Pictures/wallpapers", "~/Pictures/livewalls" }  where the pictures are
--   view      "strip" | "orbit"   the picker's last view

local M = {}

M.VIEWS = { "strip", "orbit", "circuit" }
M.VIEW_INDEX = { strip = 0, orbit = 1, circuit = 2 }
M.SOURCES = { "all", "pictures", "live" }   -- the picker's source row, in its order
M.DEFAULT_FOLDERS = { "~/Pictures/wallpapers", "~/Pictures/livewalls" }

-- What a file is drawn as, by its extension: a `still` and an `animated` picture are the desk's
-- (Pleamar plays a GIF, an animated PNG or WebP by itself), a `video` is mpvpaper's under it. A
-- WebP or PNG may move too: the index looks inside and says so (`hint`), the extension cannot.
M.STILL = { jpg = true, jpeg = true, png = true, webp = true, avif = true, jxl = true, bmp = true }
M.ANIMATED = { gif = true, apng = true }
M.VIDEO = { mp4 = true, webm = true, mkv = true, mov = true, m4v = true, avi = true }
function M.kind(path, hint)
    if hint == "still" or hint == "animated" or hint == "video" then return hint end
    local ext = tostring(path or ""):match("%.([%w]+)$")
    if not ext then return nil end
    ext = string.lower(ext)
    if M.VIDEO[ext] then return "video" end
    if M.ANIMATED[ext] then return "animated" end
    if M.STILL[ext] then return "still" end
    return nil
end
function M.is_live(kind) return kind == "video" or kind == "animated" end

local function expand(p, home)
    p = tostring(p or "")
    if p:sub(1, 2) == "~/" then return (home or "") .. p:sub(2) end
    return p
end

function M.normalize(v, home)
    v = type(v) == "table" and v or {}
    local out = { folders = {}, view = M.VIEW_INDEX[v.view] and v.view or "strip" }
    local src = type(v.folders) == "table" and #v.folders > 0 and v.folders or M.DEFAULT_FOLDERS
    for _, f in ipairs(src) do
        if type(f) == "string" and f ~= "" then out.folders[#out.folders + 1] = expand(f, home) end
    end
    return out
end

-- The index's items, made safe to use: each has a path, a kind, a name, a hue (0..360, or nil for a
-- grey picture), a luma 0..1 and a thumbnail path (or ""). Anything else is left out.
function M.items(doc)
    local out = {}
    if type(doc) ~= "table" or type(doc.items) ~= "table" then return out end
    for _, it in ipairs(doc.items) do
        if type(it) == "table" and type(it.path) == "string" then
            local kind = M.kind(it.path, it.kind)
            if kind then
                local h = tonumber(it.hue)
                local l = tonumber(it.luma) or 0.5
                out[#out + 1] = {
                    path = it.path,
                    kind = kind,
                    name = it.path:match("([^/]+)$") or it.path,
                    hue = (it.grey ~= true and h) and (h % 360) or nil,
                    luma = math.max(0, math.min(1, l)),
                    thumb = type(it.thumb) == "string" and it.thumb or "",
                    still = type(it.still) == "string" and it.still or "",
                }
            end
        end
    end
    return out
end

-- ── The colour filter (D147) ──
-- 24 hue chips of 15° each (chip 0 is red, centred on 0°), and chip 24 the greys; -1 is any colour.
-- `light` narrows by lightness: 0 any · 1 light (over 0.55) · 2 dark (under 0.4).
M.CHIPS = 24
M.GREY_CHIP = 24
function M.chip_of(hue)
    if hue == nil then return M.GREY_CHIP end
    return math.floor(((hue + 7.5) % 360) / 15)
end
-- A chip's colour, for the scene to paint it: the hue at full colour, a little softened; grey's grey.
function M.chip_rgb(c)
    if c == M.GREY_CHIP then return 0.55, 0.57, 0.58 end
    local h = (c * 15) % 360 / 60
    local x = 1 - math.abs(h % 2 - 1)
    local r, g, b
    if h < 1 then r, g, b = 1, x, 0 elseif h < 2 then r, g, b = x, 1, 0 elseif h < 3 then r, g, b = 0, 1, x
    elseif h < 4 then r, g, b = 0, x, 1 elseif h < 5 then r, g, b = x, 0, 1 else r, g, b = 1, 0, x end
    local s, v = 0.72, 0.92
    return v * (1 - s + s * r), v * (1 - s + s * g), v * (1 - s + s * b)
end
function M.colour_ok(it, chip, light)
    chip = math.floor(tonumber(chip) or -1)
    if chip >= 0 and M.chip_of(it.hue) ~= chip then return false end
    light = math.floor(tonumber(light) or 0)
    local l = it.luma or 0.5
    if light == 1 and l <= 0.55 then return false end
    if light == 2 and l >= 0.4 then return false end
    return true
end

-- The picker's list: the source (all · pictures · live), the search (a plain substring of the file
-- name, any case) and the colour filter. Kept in the index's order (by hue, then name), so a filter
-- never reshuffles.
function M.filter(items, source, query, chip, light)
    local out = {}
    local q = string.lower(tostring(query or ""))
    for _, it in ipairs(items or {}) do
        local live = M.is_live(it.kind)
        local keep = source == "live" and live or source == "pictures" and not live or (source ~= "live" and source ~= "pictures")
        if keep and q ~= "" then keep = string.find(string.lower(it.name), q, 1, true) ~= nil end
        if keep then keep = M.colour_ok(it, chip, light) end
        if keep then out[#out + 1] = it end
    end
    return out
end

-- Where a picture is in a list (1-based), or nil.
function M.find(list, path)
    for i, it in ipairs(list or {}) do if it.path == path then return i end end
    return nil
end

-- The strip's window: the cards drawn round the one in the middle (`at`, 1-based, of `n`), as a first
-- and last index. `slots` cards at most; near an end the window stays full on the other side.
function M.window(n, at, slots)
    n = math.max(0, math.floor(tonumber(n) or 0))
    slots = math.max(1, math.floor(tonumber(slots) or 1))
    if n == 0 then return 1, 0 end
    at = math.max(1, math.min(n, math.floor(tonumber(at) or 1)))
    local first = at - slots // 2
    first = math.max(1, math.min(first, n - slots + 1))
    return first, math.min(n, first + slots - 1)
end

-- ── The colour orbit ──
-- Every picture on a wheel: its angle is its hue (red at the top, turning clockwise), its distance
-- from the middle its lightness — the darkest at `inner`, the lightest at `outer`. The grey ones
-- (no hue) make a small ring of their own round the middle, at `grey`, spread evenly by their place.
-- Angles in degrees; x grows to the right, y downwards, as on screen. `spin` turns the whole wheel.
M.ORBIT = { inner = 0.34, outer = 1.0, grey = 0.2 }
function M.orbit_place(it, i, greys, spin)
    spin = tonumber(spin) or 0
    local a, r
    if it.hue == nil then
        a = (360 * ((tonumber(i) or 1) - 1) / math.max(1, tonumber(greys) or 1)) + spin
        r = M.ORBIT.grey
    else
        a = it.hue + spin
        r = M.ORBIT.inner + (M.ORBIT.outer - M.ORBIT.inner) * (it.luma or 0.5)
    end
    local rad = math.rad(a)
    return math.sin(rad) * r, -math.cos(rad) * r, a, r
end

-- Every item's place on the wheel (unit radius), the greys counted in their own ring.
function M.orbit(items, spin)
    local greys = 0
    for _, it in ipairs(items or {}) do if it.hue == nil then greys = greys + 1 end end
    local out, g = {}, 0
    for k, it in ipairs(items or {}) do
        local gi = 1
        if it.hue == nil then g = g + 1; gi = g end
        local x, y = M.orbit_place(it, gi, greys, spin)
        out[k] = { x = x, y = y }
    end
    return out
end

-- The `k` pictures nearest to (px, py) on the wheel (unit radius), nearest first, as indices into
-- the places. Within `reach` only (unit radius too), so the pointer far outside the wheel finds none.
function M.nearest(places, px, py, k, reach)
    local cand = {}
    reach = tonumber(reach) or math.huge
    local r2 = reach * reach
    for i, p in ipairs(places or {}) do
        local dx, dy = p.x - px, p.y - py
        local d = dx * dx + dy * dy
        if d <= r2 then cand[#cand + 1] = { i = i, d = d } end
    end
    table.sort(cand, function(a, b) if a.d ~= b.d then return a.d < b.d end; return a.i < b.i end)
    local out = {}
    for j = 1, math.min(k or 0, #cand) do out[j] = cand[j].i end
    return out
end

-- The hue a point on the wheel points at, 0..360 (the wheel turned by `spin`).
-- (Luau's two-argument arctangent is atan2; Lua 5.4's is atan)
local atan2 = math.atan2 or math.atan
function M.hue_at(px, py, spin)
    local a = math.deg(atan2(px, -py)) - (tonumber(spin) or 0)
    return a % 360
end

-- A colour name for a hue, for the picker's line ("REDS", "BLUES"…): twelve bands, as the notch's.
M.BANDS = { "REDS", "ORANGES", "YELLOWS", "LIMES", "GREENS", "SPRINGS",
            "CYANS", "AZURES", "BLUES", "VIOLETS", "PURPLES", "PINKS" }
function M.band_name(h)
    if h == nil then return "GREYS" end
    return M.BANDS[(math.floor(((h + 15) % 360) / 30)) + 1]
end

-- ── The circuit board (D147, reworked D149) ──
-- A panel, not the whole screen: a large CORE in the middle showing the chosen picture, and twenty
-- chips round it — six above, six below, four each side — each on its own square trace into the
-- core's edge. The list is paged twenty at a time; the colour row narrows it.
M.RING_N = 20
-- The panel's box on a screen of `sw` × `sh` (under the picker's top rows).
function M.panel(sw, sh)
    local w, h = math.min(1440, sw - 120), math.min(820, sh - 210)
    return { x = (sw - w) / 2, y = 160, w = w, h = h }
end
function M.ring(P)
    local cw = math.min(620, P.w * 0.44)
    local chh = cw * 9 / 16 + 74                        -- the die and, under it, its palette and name
    local core = { x = P.x + (P.w - cw) / 2, y = P.y + (P.h - chh) / 2, w = cw, h = chh }
    local kw = math.min(150, (P.w - 80 - 5 * 16) / 6)    -- a chip
    local kh = kw * 9 / 16
    local chips = {}
    local function route(pts) return pts end
    -- above and below: six in a row, a trace down (or up) into the core's edge, spread along it
    local rx0 = P.x + (P.w - (6 * kw + 5 * 16)) / 2
    for i = 0, 5 do
        local x = rx0 + i * (kw + 16)
        local tx = core.x + 30 + i * (core.w - 60) / 5        -- where it lands on the core
        local top = { x = x, y = P.y + 24, w = kw, h = kh }
        local my = top.y + kh + (core.y - (top.y + kh)) * (0.35 + 0.05 * math.abs(i - 2.5))
        top.pts = route({ { x + kw / 2, top.y + kh }, { x + kw / 2, my }, { tx, my }, { tx, core.y } })
        chips[#chips + 1] = top
        local bot = { x = x, y = P.y + P.h - 24 - kh, w = kw, h = kh }
        local by = core.y + core.h + (bot.y - (core.y + core.h)) * (0.65 - 0.05 * math.abs(i - 2.5))
        bot.pts = route({ { x + kw / 2, bot.y }, { x + kw / 2, by }, { tx, by }, { tx, core.y + core.h } })
        chips[#chips + 1] = bot
    end
    -- the sides: four down each, a trace across into the core
    local band_top = P.y + 24 + kh + 34
    local band_h = (P.y + P.h - 24 - kh - 34) - band_top
    for i = 0, 3 do
        local y = band_top + (band_h - 4 * kh) / 5 * (i + 1) + i * kh
        local ty = core.y + 24 + i * (core.h - 48) / 3
        local L = { x = P.x + 28, y = y, w = kw, h = kh }
        local lx = L.x + kw + (core.x - (L.x + kw)) * (0.4 + 0.08 * i)
        L.pts = route({ { L.x + kw, y + kh / 2 }, { lx, y + kh / 2 }, { lx, ty }, { core.x, ty } })
        chips[#chips + 1] = L
        local R = { x = P.x + P.w - 28 - kw, y = y, w = kw, h = kh }
        local rx = R.x - (R.x - (core.x + core.w)) * (0.4 + 0.08 * i)
        R.pts = route({ { R.x, y + kh / 2 }, { rx, y + kh / 2 }, { rx, ty }, { core.x + core.w, ty } })
        chips[#chips + 1] = R
    end
    return { core = core, chips = chips, panel = P }
end

-- The lengths along a trace (cumulative, for the pulse that runs it).
function M.trace_lengths(pts)
    local out, sum = {}, 0
    for i = 2, #pts do
        local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
        sum = sum + math.sqrt(dx * dx + dy * dy)
        out[i - 1] = sum
    end
    return out
end

-- ── Wallhaven (D147): its answers made safe, and the colour row as its colours ──
-- A colour as hue (nil for grey) and lightness, from "#rrggbb".
function M.hex_hue(hex)
    local r, g, b = tostring(hex or ""):match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then return nil, 0.5 end
    r, g, b = tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
    local hi, lo = math.max(r, g, b), math.min(r, g, b)
    local l = (hi + lo) / 2
    local d = hi - lo
    if hi == 0 or d / hi < 0.12 then return nil, l end
    local h
    if hi == r then h = ((g - b) / d) % 6 elseif hi == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    return (h * 60) % 360, l
end
-- Wallhaven's search takes only these colours: a chip asks for the nearest of them by hue.
M.WH_COLOURS = { "660000", "990000", "cc0000", "cc3333", "ea4c88", "993399", "663399", "333399", "0066cc",
                 "0099cc", "66cccc", "77cc33", "669900", "336600", "666600", "999900", "cccc33", "ffff00",
                 "ffcc33", "ff9900", "ff6600", "cc6633", "996633", "663300", "000000", "999999", "cccccc",
                 "ffffff", "424153" }
function M.wh_colour(chip)
    chip = math.floor(tonumber(chip) or -1)
    if chip < 0 then return nil end
    if chip == M.GREY_CHIP then return "999999" end
    local want, best, gap = chip * 15, nil, math.huge
    for _, c in ipairs(M.WH_COLOURS) do
        local h, l = M.hex_hue("#" .. c)
        if h and l > 0.25 and l < 0.75 then
            -- by hue, and between equals the one nearest a mid lightness (the most vivid)
            local d = math.abs(((h - want + 540) % 360) - 180) + math.abs(l - 0.45) * 10
            if d < gap then best, gap = c, d end
        end
    end
    return best
end
local function on_wallhaven(url)
    return type(url) == "string" and (url:match("^https://w%.wallhaven%.cc/") or url:match("^https://th%.wallhaven%.cc/")) ~= nil
        and not url:find("[%s\"'`$]")
end
-- One page of an answer as the picker's items (`remote`: worn by saving it first), its last page, and
-- the random list's seed. Only what is safe to fetch: an id of letters and digits, links on Wallhaven's
-- own hosts. Anything else: nil.
function M.wh_items(doc)
    if type(doc) ~= "table" or type(doc.data) ~= "table" then return nil end
    local out = {}
    for _, d in ipairs(doc.data) do
        local id = type(d) == "table" and type(d.id) == "string" and d.id:match("^%w+$") and d.id or nil
        local th = id and type(d.thumbs) == "table" and (d.thumbs.large or d.thumbs.small) or nil
        if id and on_wallhaven(d.path) and on_wallhaven(th) then
            -- its place on the orbit by the most colourful of the colours Wallhaven lists for it (the
            -- first is often a dark neutral, which put nearly all of them in the greys)
            local c1, best = type(d.colors) == "table" and d.colors[1] or nil, -1
            for _, c in ipairs(type(d.colors) == "table" and d.colors or {}) do
                local h, l = M.hex_hue(c)
                local score = h and (1 - math.abs(l - 0.5) * 2) or -1
                if score > best then c1, best = c, score end
            end
            local hue, luma = M.hex_hue(c1)
            local r, g, b = tostring(c1 or ""):match("^#(%x%x)(%x%x)(%x%x)$")
            out[#out + 1] = { id = id, path = d.path, url = d.path, thumb_url = th, thumb = "", remote = true,
                              kind = "still", name = "wallhaven-" .. id, hue = hue, luma = luma,
                              res = tostring(d.resolution or ""), purity = tostring(d.purity or "sfw"),
                              cr = r and tonumber(r, 16) / 255 or 0.5, cg = g and tonumber(g, 16) / 255 or 0.5,
                              cb = b and tonumber(b, 16) / 255 or 0.5 }
        end
    end
    local meta = type(doc.meta) == "table" and doc.meta or {}
    local seed = type(meta.seed) == "string" and meta.seed:match("^%w+$") or nil
    return out, math.max(1, math.floor(tonumber(meta.last_page) or 1)), seed
end
M.WH_SORTS = { "toplist", "hot", "date_added", "random" }
M.WH_RANGES = { "1d", "3d", "1w", "1M", "3M", "6M", "1y" }

-- ── Wearing ──
-- What the desk is told (wall.json beside the settings, written by `mooi wall apply`): the file, the
-- still it is drawn as (the file itself, or a frame of a video), its kind, the transition and where a
-- growing circle starts. Read back here; anything malformed is nil.
function M.state(doc)
    if type(doc) ~= "table" or type(doc.source) ~= "string" or doc.source == "" then return nil end
    local kind = M.kind(doc.source, doc.kind)
    if not kind then return nil end
    local still = type(doc.still) == "string" and doc.still ~= "" and doc.still or doc.source
    return {
        source = doc.source,
        still = kind == "video" and still or doc.source,
        kind = kind,
        transition = type(doc.transition) == "string" and doc.transition or "",
        from_x = tonumber(doc.from_x),
        from_y = tonumber(doc.from_y),
        at = tonumber(doc.at) or 0,
    }
end

return M
