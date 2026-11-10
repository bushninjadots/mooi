-- The workspaces' shader transitions (D158): Hyprland's screen shader, switched on for the length of
-- one transition and off again. Pure, so tests/unit runs it; mooi writes `glsl()` to its data folder
-- and `bin/mooi ws-fx` (the watcher on Hyprland's events) applies it at each workspace change.
--
-- What Hyprland 0.57 gives a screen shader (src/render/OpenGL.cpp, read for this): the finished frame
-- (`tex`), `time` in seconds *since the shader was applied* (so each transition starts at 0), and the
-- output's size (`screen_size`). The vertex stage is GLSL 300 es, so these are too (an ES 100 shader
-- fails to link, silently). `time` only runs with debug:damage_tracking off, and frames only keep
-- coming with debug:vfr off — both are the watcher's to switch for the effect and back.
--
-- A screen shader sees one frame, not the two workspaces, so each effect is laid over Hyprland's own
-- fade between them (desktop.luau gives these kinds a fade that holds, then swaps late), timed so the
-- swap happens while the effect hides the screen. Each is the identity at t = 0 and at t = 1: nothing
-- pops when the shader goes on or off.

local M = {}

-- The kinds, and how long each runs (seconds), as designed: the setting (desktop.ws_fx_speed)
-- scales that length, here and inside the shader, so the length the watcher holds the shader for and
-- the shader's own clock are the same number.
M.KINDS = {
    channel = { dur = 0.62 },   -- an old set changing channel: the picture folds to a lit line and opens again
    circuit = { dur = 0.95 },   -- a front of hexagon cells closes over the screen and opens again, lit as it goes
    stretch = { dur = 0.55 },   -- a lit line crosses and drags the picture behind it into streaked rows
    halftone = { dur = 0.78 },  -- the picture goes to print in dots, a wave from the left, and comes back whole
    board = { dur = 0.85 },     -- the picture becomes a circuit cell by cell: copper rows and columns, pads, signals running the wires
    sigil = { dur = 0.90 },     -- the picture winds round the middle and folds into six, and a turning seal of dashes holds the swap
    -- D297: four more
    ripple = { dur = 0.80 },    -- a ring of water runs out from the middle, the swap under its crest, and the water stills
    portal = { dur = 0.85 },    -- the picture swirls into the middle and out again, a lit ring at the eye
    shatter = { dur = 0.75 },   -- the screen breaks into shards that slide and light at their edges, and close again
    blocks = { dur = 0.60 },    -- the screen coarsens into lit blocks that hold the swap, then sharpens back
}

local function rgb(hex, fallback)
    hex = type(hex) == "string" and string.match(hex, "^#?(%x%x%x%x%x%x)$") or nil
    if not hex then return fallback end
    local r, g, b = tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16)
    return string.format("vec3(%.3f, %.3f, %.3f)", r / 255, g / 255, b / 255)
end

local HEAD = [[
#version 300 es
// written by mooi (shell/lib/wsfx.luau): the workspaces' transition, applied by `mooi ws-fx`
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
uniform vec2 screen_size;
out vec4 fragColor;
const vec3 PHOS = @PHOS@;
const vec3 EMBER = @EMBER@;
const vec3 BASE = @BASE@;
const float DUR = @DUR@;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
]]

-- The channel change: the picture folds to a lit line (taller rows torn sideways, the colours split,
-- scanlines and snow), holds as a bright phosphor line while the workspaces swap, then opens again.
local CHANNEL = [[
void main() {
    float t = clamp(time / DUR, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float k = smoothstep(0.0, 0.42, t) * (1.0 - smoothstep(0.58, 1.0, t));   // 0 open .. 1 folded
    float sy = mix(1.0, 0.004, pow(k, 0.65));
    float sx = mix(1.0, 0.55, smoothstep(0.85, 1.0, k));
    float row = floor(uv.y * screen_size.y / 4.0);
    float tear = (hash(vec2(row, floor(time * 50.0))) - 0.5) * 0.05 * k * (1.0 - k * 0.6);
    vec2 p = vec2((uv.x - 0.5) / sx + 0.5 + tear, (uv.y - 0.5) / sy + 0.5);
    float split = 0.007 * k;
    vec3 c = vec3(texture(tex, p + vec2(split, 0.0)).r, texture(tex, p).g, texture(tex, p - vec2(split, 0.0)).b);
    float inside = step(0.0, p.y) * step(p.y, 1.0) * step(0.0, p.x) * step(p.x, 1.0);
    c = mix(c, PHOS * 0.6 + 0.55, smoothstep(0.5, 1.0, k)) * inside;
    float d = abs(uv.y - 0.5) * screen_size.y;
    float reach = step(abs(uv.x - 0.5), 0.5 * sx + 0.01);
    c += PHOS * exp(-d / (1.5 + 40.0 * (1.0 - k))) * smoothstep(0.25, 1.0, k) * reach * 1.4;
    float flick = k * (1.0 - k) * 4.0;
    c *= mix(1.0, 0.82 + 0.18 * sin(uv.y * screen_size.y * 3.14159), k);
    c += (hash(uv * screen_size + fract(time) * 97.0) - 0.5) * 0.22 * flick * inside;
    fragColor = vec4(c, 1.0);
}
]]

-- The circuit: hexagon cells close over the screen in a front from the left, each lit (now and then
-- in the warm tone) as it shuts, so the screen becomes a board of dark plates with lit traces; the
-- workspaces swap under it; the cells open again in the same direction.
local CIRCUIT = [[
const vec2 HS = vec2(1.0, 1.7320508);
vec4 hexcell(vec2 p) {
    vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / HS.xyxy) + 0.5;
    vec4 h = vec4(p - hc.xy * HS, p - (hc.zw + 0.5) * HS);
    return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy) : vec4(h.zw, hc.zw + 0.5);
}
float hexd(vec2 p) { p = abs(p); return max(dot(p, normalize(HS)), p.x); }
void main() {
    float t = clamp(time / DUR, 0.0, 1.0);
    vec2 uv = v_texcoord;
    vec3 c = texture(tex, uv).rgb;
    const float CELL = 44.0;
    vec4 h = hexcell(uv * screen_size / CELL);
    vec2 centre = h.zw * HS * CELL / screen_size;
    float r = hash(h.zw);
    float front = clamp(centre.x * 0.82 + centre.y * 0.18, 0.0, 1.0);
    float tc = 0.02 + front * 0.25 + r * 0.06;
    float to = 0.55 + front * 0.25 + r * 0.06;
    float shut = smoothstep(tc, tc + 0.07, t) * (1.0 - smoothstep(to, to + 0.07, t));
    float hd = hexd(h.xy);
    float plate = 1.0 - smoothstep(0.5 * shut - 0.012, 0.5 * shut, hd);
    vec3 tone = r > 0.88 ? EMBER : PHOS;
    float flash = smoothstep(tc, tc + 0.03, t) * (1.0 - smoothstep(tc + 0.03, tc + 0.14, t))
                + smoothstep(to - 0.02, to + 0.01, t) * (1.0 - smoothstep(to + 0.01, to + 0.09, t));
    vec3 board = BASE * 0.16 + tone * (0.02 + 0.42 * flash);
    float rim = smoothstep(0.022, 0.0, abs(hd - (0.5 * shut - 0.035))) * step(0.04, shut);
    float trace = smoothstep(0.016, 0.0, abs(hd - 0.2)) * step(0.72, r) * shut;
    float via = smoothstep(0.07, 0.04, length(h.xy)) * step(0.55, r) * shut;
    board += tone * (rim * (0.55 + 0.7 * flash) + trace * 0.7 + via * 0.5);
    c = mix(c, board, plate);
    fragColor = vec4(c, 1.0);
}
]]

-- The stretch: a lit line crosses the screen and drags the picture behind it into streaks, each row
-- keeping its own length and the colours splitting along the drag; the line leaves by the far edge and
-- the frame is whole again. After PixelStretch (gre, MIT, gl-transitions). The drag is the identity at
-- both ends by construction: the line starts and ends just outside the frame, and the streak's length
-- dies with it, so `mix(uv.x, a, drag)` becomes `uv.x` again.
local STRETCH = [[
void main() {
    float t = clamp(time / DUR, 0.0, 1.0);
    vec2 uv = v_texcoord;
    const float M = 0.02;                                  // the line starts and ends past the edge
    float a = mix(-M, 1.0 + M, t * t * (3.0 - 2.0 * t));   // it enters at once and slows as it goes
    float h = clamp(4.0 * a * (1.0 - a), 0.0, 1.0);         // longest as it crosses the middle
    float row = floor(uv.y * screen_size.y / 4.0);
    float drag = h * (1.0 - 0.55 * hash(vec2(row, 7.0)));   // a streak per row, no two the same
    float split = 0.018 * h;
    // behind the line each pixel repeats the one at the line; ahead of it the frame is untouched
    vec3 c = vec3(texture(tex, vec2(mix(uv.x, a + split, drag), uv.y)).r,
                  texture(tex, vec2(mix(uv.x, a, drag), uv.y)).g,
                  texture(tex, vec2(mix(uv.x, a - split, drag), uv.y)).b);
    c = mix(texture(tex, uv).rgb, c, step(uv.x, a));
    // the line itself, in the phosphor, dying away with the streaks
    float d = abs(uv.x - a) * screen_size.x;
    c += PHOS * exp(-d / 1.6) * smoothstep(0.01, 0.16, h);
    fragColor = vec4(c, 1.0);
}
]]

-- The halftone: the picture goes to print — a dot in each cell of a turned grid, sized by that cell's
-- own shade, the paper showing between them — arriving as a wave from the left, held while the
-- workspaces swap, then whole again. After Halftone (gre, MIT, gl-transitions). The print layer is laid
-- over the frame by the wave, so where the wave is 0 the frame is exactly itself.
local HALFTONE = [[
void main() {
    float t = clamp(time / DUR, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float h = smoothstep(0.0, 0.24, t) * (1.0 - smoothstep(0.76, 1.0, t));
    float wave = clamp(h * 1.3 - 0.3 * (1.0 - uv.x), 0.0, 1.0);   // the left goes first
    float cell = min(screen_size.x, screen_size.y) / 32.0;         // 32 dots across the short side
    vec2 g = ((uv - 0.5) * screen_size) / cell;
    const float A = 0.7853981;                                     // the grid turned 45°, as print does
    mat2 R = mat2(cos(A), sin(A), -sin(A), cos(A));
    mat2 Ri = mat2(cos(A), -sin(A), sin(A), cos(A));
    vec2 turned = R * g;
    vec2 base = floor(turned);
    float sd = 1e3;
    vec3 ink = vec3(0.0);
    // a dot reaches into its neighbours, so the four cells round the point are tried and the deepest wins
    for (int i = 0; i < 4; i++) {
        vec2 centre = base + vec2(float(i % 2), float(i / 2));
        vec3 col = texture(tex, clamp((Ri * centre) * cell / screen_size + 0.5, 0.0, 1.0)).rgb;
        float shade = 1.0 - dot(col, vec3(0.299, 0.587, 0.114));
        float r = mix(0.12, 0.72, sqrt(clamp(shade, 0.0, 1.0)));
        float d = length(turned - centre) - r;
        if (d < sd) { sd = d; ink = col; }
    }
    float on = 1.0 - smoothstep(-0.06, 0.06, sd);
    fragColor = vec4(mix(texture(tex, uv).rgb, mix(BASE, ink, on), wave), 1.0);
}
]]

-- The board: the frame is replaced, cell by cell, by a bit of circuitry — a copper run through the
-- middle of the cell on one axis or both, a pad where the two cross, and a signal crawling each run
-- that is laid, warm on some lines and phosphor on the rest. Each cell wires itself in at its own time
-- and unwires at its own, so the board never arrives or leaves all at once. The cell's own weight is
-- 0 at t = 0 and at t = 1, so the frame is exactly itself at both ends.
local BOARD = [[
const float CELL = 30.0;    // pixels: a cell is one unit of the wiring
void main() {
    float t = clamp(time / DUR, 0.0, 1.0);
    vec2 uv = v_texcoord;
    vec3 c = texture(tex, uv).rgb;
    vec2 p = uv * screen_size / CELL;     // the wiring holds still while the frame changes under it
    vec2 id = floor(p);
    vec2 f = fract(p) - 0.5;
    float r = hash(id);
    float tc = 0.02 + 0.26 * r;
    float to = 0.66 + 0.08 * hash(id + 7.0);
    float cw = smoothstep(tc, tc + 0.12, t) * (1.0 - smoothstep(to, to + 0.14, t));
    // the copper: a run through the middle of the cell, and the cell drops it now and then so no two
    // stretches of board are laid the same
    float rowOn = step(0.24, hash(vec2(id.y, 5.0))) * step(0.16, hash(id + vec2(3.1, 0.0)));
    float colOn = step(0.30, hash(vec2(id.x, 9.0))) * step(0.16, hash(id + vec2(0.0, 6.4)));
    float lineH = smoothstep(0.05, 0.0, abs(f.y)) * rowOn;
    float lineV = smoothstep(0.05, 0.0, abs(f.x)) * colOn;
    // a signal runs each line that is laid: its phase is the line's, its pace too, so they never agree
    vec2 span = screen_size / CELL;
    float px = fract(hash(vec2(id.y, 11.0)) + time * (0.22 + 0.30 * hash(vec2(id.y, 2.0)))) * span.x;
    float py = fract(hash(vec2(id.x, 17.0)) + time * (0.22 + 0.30 * hash(vec2(id.x, 4.0)))) * span.y;
    float dH = (p.x - px) * 0.7;
    float dV = (p.y - py) * 0.7;
    float sig = max(lineH * exp(-dH * dH), lineV * exp(-dV * dV));
    // a pad where the cell's two runs cross, and one in six of them blinks warm
    float pad = smoothstep(mix(0.10, 0.22, r), 0.0, length(f)) * step(0.45, r);
    float blink = 0.55 + 0.45 * sin(time * 4.0 + r * 30.0);
    vec3 board = BASE * 0.09;
    board += PHOS * (lineH + lineV) * 0.42;
    board += mix(PHOS, EMBER, step(0.86, hash(id + 2.7))) * pad * (0.35 + 0.7 * blink);
    board += mix(PHOS, EMBER, 0.45) * sig * 1.8;
    c = mix(c, board, cw);
    fragColor = vec4(c, 1.0);
}
]]

-- The sigil: the frame winds round the middle, tighter the closer in, then folds into six, until the
-- screen is a rosette of itself; a seal of dashed rings turns on top, each band against its neighbour,
-- and the middle goes out to make room for it. Both the winding and the seal carry k, so at t = 0 the
-- sample is the frame's own and no light is added.
local SIGIL = [[
const float TAU = 6.2831853;
// the frame read where the polar maths puts it (q is in the display's aspect, so the rosette is round)
vec3 wound(vec2 q, float asp) { return texture(tex, vec2(0.5) + vec2(q.x / asp, q.y)).rgb; }
void main() {
    float t = clamp(time / DUR, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float k = smoothstep(0.0, 0.32, t) * (1.0 - smoothstep(0.68, 1.0, t));   // 0 the frame .. 1 the seal
    float asp = screen_size.x / screen_size.y;
    vec2 q = (uv - 0.5) * vec2(asp, 1.0);
    float rr = length(q);
    float a = atan(q.y, q.x);
    float aa = a + k * 2.2 / (rr + 0.18);           // wound harder near the middle, so the frame spirals
    const float SEG = 1.0471976;                     // a sixth of a turn
    float af = aa - SEG * floor(aa / SEG + 0.5);     // folded into six
    vec3 c = mix(texture(tex, uv).rgb, wound(vec2(cos(aa), sin(aa)) * rr, asp), k);
    c = mix(c, wound(vec2(cos(af), sin(af)) * pow(rr, 1.0 + 0.9 * k), asp), k * 0.85);
    // the seal: rings of dashes, the bands turning against each other
    float bands = rr * 10.0 - time * 1.6;
    float band = floor(bands);
    float bf = fract(bands);
    float ticks = 10.0 + 2.0 * mod(band, 4.0);
    float spin = time * (mod(band, 2.0) * 0.8 - 0.4);
    float dashOn = step(0.42, fract(a / TAU * ticks + spin + hash(vec2(band, 3.0))));
    float ring = smoothstep(0.06, 0.0, abs(bf - 0.5));
    float seal = ring * dashOn * smoothstep(0.12, 0.30, rr);
    float iris = smoothstep(0.028, 0.0, abs(rr - (0.22 + 0.05 * sin(time * 2.0))));
    c *= 1.0 - 0.6 * k * smoothstep(0.34, 0.02, rr);
    c += (PHOS * seal * 0.55 + EMBER * (seal * step(0.72, hash(vec2(band, 9.0))) + iris)) * k;
    c += BASE * 0.25 * k * smoothstep(0.5, 0.0, rr);
    fragColor = vec4(c, 1.0);
}
]]


-- D297: ripple — rings out of the middle bend the picture; the swap happens under the tallest crest.
local RIPPLE = [[
void main() {
    float t = clamp(time / DUR, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float k = sin(3.14159 * t);
    vec2 d = (uv - 0.5) * vec2(screen_size.x / screen_size.y, 1.0);
    float r = length(d);
    float wave = sin(r * 42.0 - t * 30.0) * exp(-r * 2.2) * k;
    vec2 q = uv + normalize(d + 1e-5) * wave * 0.035;
    vec3 c = texture(tex, clamp(q, 0.0, 1.0)).rgb;
    c += PHOS * max(0.0, wave) * 0.45;
    c = mix(c, c * 0.6 + PHOS * 0.25, smoothstep(0.35, 0.5, k) * smoothstep(0.65, 0.5, abs(t - 0.5) + 0.5) * 0.4);
    fragColor = vec4(c, 1.0);
}
]]

-- D297: portal — the picture turns into the middle, darkening to a lit eye at the half, and turns back out.
local PORTAL = [[
void main() {
    float t = clamp(time / DUR, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float k = sin(3.14159 * t);
    vec2 d = (uv - 0.5) * vec2(screen_size.x / screen_size.y, 1.0);
    float r = length(d);
    float a = atan(d.y, d.x) + k * 5.0 * exp(-r * 1.6);
    float rr = r * (1.0 + k * 1.4);
    vec2 q = vec2(cos(a), sin(a)) * rr / vec2(screen_size.x / screen_size.y, 1.0) + 0.5;
    vec3 c = texture(tex, clamp(q, 0.0, 1.0)).rgb * (1.0 - k * smoothstep(0.0, 0.9, r) * 0.9);
    c += PHOS * exp(-pow((r - 0.12 * k) * 30.0, 2.0)) * k * 1.2;
    fragColor = vec4(c, 1.0);
}
]]

-- D297: shatter — cells of a jittered grid slide apart along their own way, edges lit, and close back.
local SHATTER = [[
void main() {
    float t = clamp(time / DUR, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float k = sin(3.14159 * t);
    vec2 g = uv * vec2(9.0, 9.0 * screen_size.y / screen_size.x);
    vec2 cell = floor(g + 0.15 * vec2(sin(g.y * 3.1), cos(g.x * 2.7)));
    vec2 dir = vec2(hash(cell) - 0.5, hash(cell + 3.3) - 0.5);
    vec2 q = uv - dir * 0.12 * k;
    vec3 c = texture(tex, clamp(q, 0.0, 1.0)).rgb * (1.0 - 0.45 * k);
    vec2 f = fract(g + 0.15 * vec2(sin(g.y * 3.1), cos(g.x * 2.7)));
    float edge = 1.0 - smoothstep(0.0, 0.05, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
    c += mix(PHOS, EMBER, hash(cell + 7.0)) * edge * k * 0.9;
    fragColor = vec4(c, 1.0);
}
]]

-- D297: blocks — the screen coarsens into blocks lit by their own colour, holds, then sharpens again.
local BLOCKS = [[
void main() {
    float t = clamp(time / DUR, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float k = sin(3.14159 * t);
    float cells = mix(screen_size.x, 24.0, pow(k, 0.6));
    vec2 grid = vec2(cells, cells * screen_size.y / screen_size.x);
    vec2 q = k > 0.01 ? (floor(uv * grid) + 0.5) / grid : uv;
    vec3 c = texture(tex, q).rgb;
    vec2 f = fract(uv * grid);
    float edge = step(0.92, max(f.x, f.y)) * smoothstep(0.3, 0.8, k);
    c = mix(c, c * 0.7 + PHOS * 0.2, smoothstep(0.4, 1.0, k) * 0.5) + PHOS * edge * 0.35;
    fragColor = vec4(c, 1.0);
}
]]

local BODY = {
    channel = CHANNEL, circuit = CIRCUIT, stretch = STRETCH, halftone = HALFTONE,
    board = BOARD, sigil = SIGIL, ripple = RIPPLE, portal = PORTAL, shatter = SHATTER, blocks = BLOCKS,
}

-- The shader for `kind` in the palette `pal` ({ phos, ember, trace } as #rrggbb); nil for a kind
-- that is not a shader's.
-- How long it runs, against the kind's own length: `speed` percent, 100 as designed, held to a
-- range of its own so a settings.json written by hand cannot leave the screen in a transition.
local function scaled(dur, speed)
    local s = tonumber(speed) or 100
    if s < 25 then s = 25 elseif s > 300 then s = 300 end
    return dur * s / 100
end

-- How long `kind` runs at `speed` percent of its own length, in seconds.
function M.duration(kind, speed)
    local k = M.KINDS[kind]
    return k and scaled(k.dur, speed) or nil
end

function M.glsl(kind, pal, speed)
    local k = M.KINDS[kind]
    if not k then return nil end
    pal = type(pal) == "table" and pal or {}
    local body = BODY[kind]
    local head = string.gsub(HEAD, "@(%u+)@", {
        PHOS = rgb(pal.phos, "vec3(0.498, 0.812, 0.714)"),
        EMBER = rgb(pal.ember, "vec3(0.878, 0.482, 0.180)"),
        BASE = rgb(pal.trace, "vec3(0.239, 0.416, 0.376)"),
        DUR = string.format("%.3f", scaled(k.dur, speed)),
    })
    return head .. body
end

-- What the watcher reads: the duration in milliseconds, on a line of its own (none: no shader kind).
function M.dur_ms(kind, speed)
    local k = M.KINDS[kind]
    return k and math.floor(scaled(k.dur, speed) * 1000 + 0.5) or nil
end

return M
