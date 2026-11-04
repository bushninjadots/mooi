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

-- The kinds, and how long each runs (seconds). `hold` is when Hyprland's fade should swap the
-- workspaces (the share of its own duration, desktop.luau's late curve aims there).
M.KINDS = {
    channel = { dur = 0.62 },   -- an old set changing channel: the picture folds to a lit line and opens again
    circuit = { dur = 0.95 },   -- a front of hexagon cells closes over the screen and opens again, lit as it goes
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

-- The shader for `kind` in the palette `pal` ({ phos, ember, trace } as #rrggbb); nil for a kind
-- that is not a shader's.
function M.glsl(kind, pal)
    local k = M.KINDS[kind]
    if not k then return nil end
    pal = type(pal) == "table" and pal or {}
    local body = (kind == "channel") and CHANNEL or CIRCUIT
    local head = string.gsub(HEAD, "@(%u+)@", {
        PHOS = rgb(pal.phos, "vec3(0.498, 0.812, 0.714)"),
        EMBER = rgb(pal.ember, "vec3(0.878, 0.482, 0.180)"),
        BASE = rgb(pal.trace, "vec3(0.239, 0.416, 0.376)"),
        DUR = string.format("%.3f", k.dur),
    })
    return head .. body
end

-- What the watcher reads: the duration in milliseconds, on a line of its own (none: no shader kind).
function M.dur_ms(kind)
    local k = M.KINDS[kind]
    return k and math.floor(k.dur * 1000 + 0.5) or nil
end

return M
