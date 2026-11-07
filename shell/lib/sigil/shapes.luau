-- The Sigil's shapes (D207): the 64 points of the one line for every kind of display, in any box. Pure.
-- A kind is a parametric curve sampled at 64 places along one pen stroke; the scene springs each point to
-- its target and joins them, so a change of kind is the line rewriting itself (spec §4, §6).
--
-- outline(kind, box, form, t, opts): box = { x, y, w, h }; form = "glyph" | "compact" | "display" (the
-- display has room to spread, the others fold to the box's height); t = seconds (the clock's hand);
-- opts = { values = { 0…1, … } (strip, bars), n = cells, active = cell (spaces), angle = radians }.
-- Every point is clamped into the box: a host narrower than its form gets a squeezed line, never one
-- drawn over its neighbours.

local M = { N = 64 }
M.KINDS = { "clock", "wave", "disc", "ring", "card", "strip", "ribbon", "horizon", "spaces", "dots", "bars", "face" }

local PI = math.pi
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- piecewise: parts = { { share, fn(v) -> x, y }, … }; u in 0…1 lands in the part whose share holds it
local function pieces(u, parts)
    local acc = 0
    for i, p in ipairs(parts) do
        if u <= acc + p[1] or i == #parts then return p[2](math.min(1, math.max(0, (u - acc) / p[1]))) end
        acc = acc + p[1]
    end
end

local KIND = {}

function KIND.clock(u, b, form, t, o)
    local cx, cy = b.x + b.w / 2, b.y + b.h / 2
    local r = math.max(2, math.min(b.h, b.w) / 2 - 1)
    local a = o.angle or ((t or 0) * 0.1)
    return pieces(u, {
        { .72, function(v) local q = v * 2 * PI - PI / 2; return cx + math.cos(q) * r, cy + math.sin(q) * r end },
        { .12, function(v) return cx, cy - r + v * r end },
        { .16, function(v) return cx + math.cos(a) * v * r * .7, cy + math.sin(a) * v * r * .7 end },
    })
end

function KIND.wave(u, b)
    local cy = b.y + b.h / 2
    return b.x + 2 + u * (b.w - 4), cy + math.sin(u * PI * 4) * b.h * 0.15 * math.sin(u * PI)
end

function KIND.disc(u, b, form)
    local r = form == "display" and math.min(b.h * 0.42, b.w * 0.2) or math.max(2, b.h / 2 - 1)
    local dx, cy = b.x + r + 2, b.y + b.h / 2
    local lift = form == "display" and r * 0.45 or 0
    return pieces(u, {
        -- from its lowest point round, so the line rolls straight out of it
        { .55, function(v) local q = PI / 2 + v * 2 * PI; return dx + math.cos(q) * r, cy + math.sin(q) * r end },
        { .45, function(v)
            local x = dx + v * (b.x + b.w - 2 - dx)
            local off = clamp((x - dx - r) / 30, 0, 1)
            return x, cy + r - off * lift
        end },
    })
end

function KIND.ring(u, b, form)
    local r = form == "display" and math.min(b.h * 0.4, b.w * 0.2) or math.max(2, b.h / 2 - 1)
    local rx, cy = b.x + r + 2, b.y + b.h / 2
    local x0 = rx + r + 6
    return pieces(u, {
        { .58, function(v) local q = PI * .65 + v * PI * 1.7; return rx + math.cos(q) * r, cy + math.sin(q) * r end },
        { .42, function(v)
            local n = math.sin(v * 31) * .5 + math.sin(v * 77) * .3 + math.sin(v * 9) * .4
            return x0 + v * (b.x + b.w - 2 - x0), cy - n * r * 0.45
        end },
    })
end

-- a rounded rectangle traced once round from its top-left straight
local function rounded(u, x0, y0, W, H, rr)
    local straight = { W - 2 * rr, H - 2 * rr, W - 2 * rr, H - 2 * rr }
    local arc = PI * rr / 2
    local per = 2 * (W + H - 4 * rr) + 4 * arc
    local d = u * per
    local corners = { { x0 + W - rr, y0 + rr, -PI / 2 }, { x0 + W - rr, y0 + H - rr, 0 }, { x0 + rr, y0 + H - rr, PI / 2 }, { x0 + rr, y0 + rr, PI } }
    local starts = { { x0 + rr, y0, 1, 0 }, { x0 + W, y0 + rr, 0, 1 }, { x0 + W - rr, y0 + H, -1, 0 }, { x0, y0 + H - rr, 0, -1 } }
    for i = 1, 4 do
        local s = starts[i]
        if d <= straight[i] then return s[1] + s[3] * d, s[2] + s[4] * d end
        d = d - straight[i]
        local c = corners[i]
        if d <= arc then local q = c[3] + (rr > 0 and d / rr or 0); return c[1] + math.cos(q) * rr, c[2] + math.sin(q) * rr end
        d = d - arc
    end
    return x0 + rr, y0
end

function KIND.card(u, b, form)
    local rr = form == "display" and math.min(14, b.h / 2) or math.max(0, b.h / 2 - 1)
    return rounded(u, b.x + 1, b.y + 1, b.w - 2, b.h - 2, math.min(rr, (b.w - 2) / 2))
end

-- square bars over a baseline drawn by one pen: up, across, down, a gap
local function skyline(u, b, values, n)
    local base = b.y + b.h - 1
    local k = u * n
    local i = math.min(n - 1, math.floor(k))
    local f = k - i
    local hv = clamp(tonumber(values[i + 1]) or 0, 0, 1) * (b.h - 2)
    local x = b.x + 1 + (i + f) * (b.w - 2) / n
    local y = f < .15 and base - hv * (f / .15) or f < .7 and base - hv or f < .85 and base - hv * (1 - (f - .7) / .15) or base
    return x, y
end

function KIND.strip(u, b, _, _, o) return skyline(u, b, o.values or {}, 24) end
function KIND.bars(u, b, _, _, o) local v = o.values or {}; return skyline(u, b, v, math.max(1, #v)) end

function KIND.ribbon(u, b, form)
    local W = (b.w - 4) * (form == "display" and .9 or 1)
    local H = form == "display" and math.min(22, b.h * .5) or math.max(2, b.h - 6)
    local cx, cy = b.x + b.w / 2, b.y + b.h / 2
    local q = u * 2 * PI
    local sx = math.cos(q)
    return cx + (sx < 0 and -1 or 1) * math.abs(sx) ^ 0.18 * W / 2, cy + math.sin(q) * H / 2
end

function KIND.horizon(u, b)
    local base = b.y + b.h - 2
    local cx = b.x + b.w / 2
    local R, Rw = b.h - 4, (b.w - 4) * .36
    return pieces(u, {
        { .4, function(v) return b.x + 2 + v * (b.w - 4), base end },
        { .6, function(v) local q = PI + v * PI; return cx + math.cos(q) * Rw, base + math.sin(q) * R end },
    })
end

function KIND.spaces(u, b, _, _, o)
    local n = math.max(1, math.floor(tonumber(o.n) or 5))
    local act = math.floor(tonumber(o.active) or 1)
    local k = u * n
    local i = math.min(n - 1, math.floor(k))
    local f = k - i
    local cw = (b.w - 2) / n
    local x0 = b.x + 1 + i * cw + cw * .15
    local w = cw * .7
    local hh = (i + 1 == act) and (b.h - 2) or (b.h - 2) * .55
    local top, bot = b.y + b.h / 2 - hh / 2, b.y + b.h / 2 + hh / 2
    if f < .25 then return x0, bot - (f / .25) * hh end
    if f < .5 then return x0 + ((f - .25) / .25) * w, top end
    if f < .75 then return x0 + w, top + ((f - .5) / .25) * hh end
    return x0 + w - ((f - .75) / .25) * w, bot
end

-- three arcs over a dot (a signal), one pen: out along one, back along the next
function KIND.dots(u, b)
    local cx, base = b.x + b.w / 2, b.y + b.h - 1
    local R = math.min(b.h - 2, b.w / 2 - 1)
    local k = u * 3
    local i = math.min(2, math.floor(k))
    local f = k - i
    local r = R * (i + 1) / 3
    local q = (i % 2 == 0) and (PI * 1.25 + f * PI * .5) or (PI * 1.75 - f * PI * .5)
    return cx + math.cos(q) * r, base + math.sin(q) * r
end

-- BMO's face as one stroke: an eye, the other eye, the smile
function KIND.face(u, b)
    local cx, cy = b.x + b.w / 2, b.y + b.h / 2
    local s = math.min(b.w, b.h * 2) / 2
    local er = math.max(1, s * .12)
    return pieces(u, {
        { .3, function(v) local q = v * 2 * PI; return cx - s * .45 + math.cos(q) * er, cy - s * .15 + math.sin(q) * er end },
        { .3, function(v) local q = v * 2 * PI; return cx + s * .45 + math.cos(q) * er, cy - s * .15 + math.sin(q) * er end },
        { .4, function(v) local q = PI * .15 + v * PI * .7; return cx + math.cos(q) * s * .4, cy + math.sin(q) * s * .3 end },
    })
end

function M.outline(kind, box, form, t, opts)
    local f = KIND[kind] or KIND.clock
    opts = type(opts) == "table" and opts or {}
    form = form or "compact"
    local b = { x = tonumber(box.x) or 0, y = tonumber(box.y) or 0, w = math.max(1, tonumber(box.w) or 1), h = math.max(1, tonumber(box.h) or 1) }
    local out = {}
    for i = 1, M.N do
        local x, y = f((i - 1) / (M.N - 1), b, form, t, opts)
        out[i] = { clamp(x, b.x, b.x + b.w), clamp(y, b.y, b.y + b.h) }
    end
    return out
end

-- The order a change is written in, front first: n index ranges over 1 … N, the first range first, so the
-- line rewrites itself along its length (the scene's springs do the rest).
function M.batches(_, _, n)
    n = math.max(1, math.floor(tonumber(n) or 1))
    local out, size = {}, M.N / n
    for k = 1, n do out[k] = { math.floor((k - 1) * size) + 1, math.floor(k * size) } end
    out[n][2] = M.N
    return out
end

return M
