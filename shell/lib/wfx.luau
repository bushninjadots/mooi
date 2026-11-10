-- The windows' own shader (HyprWindowShade, not one of Hyprland's animations): a window opens and
-- closes the way a screen does. Pure, so tests/unit runs it; mooi writes `pair()` beside its keys
-- as window-open.glsl / window-close.glsl and puts two window rules in front of them (lib/desktop
-- `window_rules`), one `+shader_open_default:` and one `+shader_close_default:` for every class.
--
-- What the plugin gives a one-shot shader (its README, read for this): the finished window (`tex`),
-- `progress` running 0 -> 1 over the animation, the window's size (`surface_size`), and a
-- `// @duration` in seconds that this file carries. A close is the one place with a rule of its
-- own: the plugin holds the snapshot's alpha for the whole duration, so a closing shader owns the
-- disappearance and has to reach 0 at progress 1 — each of these does, on its last line. An
-- opening ends exactly on the window, so nothing pops when the effect lets go of it.
--
-- No shader here asks for `time`: the plugin only redraws for them while `progress` moves, which is
-- the length of one open or close and no longer.

local M = {}

-- How long each half runs (seconds), and the order the settings window offers them in.
M.KINDS = {
    phosphor = { open = 0.34, close = 0.36 },   -- the window wakes out of a lit line, and goes out into one
    glitch = { open = 0.38, close = 0.34 },     -- it arrives in tearing slices and leaves the same way
    iris = { open = 0.42, close = 0.40 },       -- it opens out of the middle like a lens, and closes to a point
    -- D297: four more
    liquid = { open = 0.46, close = 0.42 },     -- it rises through rippling water that settles, and melts away downwards
    pixel = { open = 0.36, close = 0.34 },      -- it comes into focus out of big blocks, and breaks back into them
    fold = { open = 0.40, close = 0.36 },       -- it unfolds from its top edge like paper, and folds back up into it
    dust = { open = 0.48, close = 0.52 },       -- it gathers out of drifting grains, and blows away into them from the left
}
M.PAIRS = { "phosphor", "glitch", "iris", "liquid", "pixel", "fold", "dust" }

-- Two classes that keep a pair of their own, so the desktop does not do the same thing everywhere:
-- a terminal leaves harder than the rest (the glitch, whatever the pair is), a browser arrives
-- quietly (the iris). It is a rule by class, so every window of the app takes it, and without the
-- `_default` suffix, so it wins over the catch-all pair rather than tying with it.
M.APPS = {
    { name = "terminal", class = "^(kitty|Alacritty|alacritty|foot|com.mitchellh.ghostty|org.wezfurlong.wezterm|xterm|XTerm)$", pair = "glitch" },
    { name = "browser", class = "^(firefox|firefox-developer-edition|zen|Zen|zen-twilight|google-chrome|chromium|brave-browser|vivaldi-stable|org.qutebrowser.qutebrowser)$", pair = "iris" },
}

local function rgb(hex, fallback)
    hex = type(hex) == "string" and string.match(hex, "^#?(%x%x%x%x%x%x)$") or nil
    if not hex then return fallback end
    local r, g, b = tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16)
    return string.format("vec3(%.3f, %.3f, %.3f)", r / 255, g / 255, b / 255)
end

-- The palette's three signals, read the same way lib/wsfx reads them, so the windows and the
-- workspaces light up in one colour.
local HEAD = [[
#version 320 es
// written by mooi (shell/lib/wfx.luau): a window @WHAT@, played by HyprWindowShade
// @duration @DUR@
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
uniform float progress;
uniform vec2 surface_size;
out vec4 fragColor;
const vec3 PHOS = @PHOS@;
const vec3 EMBER = @EMBER@;
const vec3 BASE = @BASE@;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
]]

-- The phosphor, opening: a lit line opens out of the middle row into the picture, the picture
-- squeezed into that band and unwound as the band grows, scanlines settling, the phosphor leaving
-- the whole of it as it completes. At progress 1 the band is the window: what it draws is the
-- window's own pixels, untouched.
local PHOSPHOR_OPEN = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float band = 0.5 * pow(p, 0.55);                  // the part of the window that exists yet
    float d = abs(uv.y - 0.5);
    float inside = 1.0 - smoothstep(band + 0.0005, band + 0.02, d);
    float sy = max(0.002, 2.0 * band);
    vec2 q = vec2(uv.x, (uv.y - 0.5) / sy + 0.5);     // the picture squeezed into it, and unwound
    float split = 0.006 * (1.0 - p) * (0.5 + 0.5 * hash(vec2(floor(q.y * 90.0), 3.0)));
    vec3 c = vec3(texture(tex, q + vec2(split, 0.0)).r, texture(tex, q).g, texture(tex, q - vec2(split, 0.0)).b);
    float scan = 0.5 + 0.5 * sin(uv.y * surface_size.y * 3.14159);
    c *= mix(1.0, 0.82 + 0.18 * scan, 1.0 - p);       // the scanlines it arrives through
    float edge = exp(-d * surface_size.y / 2.5);      // the lit edge of the band, gone by the end
    c += PHOS * edge * smoothstep(0.0, 0.06, p) * (1.0 - smoothstep(0.5, 0.95, p)) * 0.9;
    c = mix(c, mix(c, PHOS * 0.5 + 0.45, 0.55), (1.0 - p) * (1.0 - p));   // the phosphor leaving it
    fragColor = vec4(c * inside, inside);
}
]]

-- The phosphor, closing: the picture collapses into the middle line, the line burns hotter than
-- the frame it came from, the window is pinched sideways at the last, and the line goes out —
-- alpha is 0 at progress 1, which is the close path's one rule.
local PHOSPHOR_CLOSE = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float band = 0.5 * pow(1.0 - p, 0.7);             // the whole window at p = 0, one row at p = 1
    float d = abs(uv.y - 0.5);
    float inside = 1.0 - smoothstep(band + 0.0005, band + 0.02, d);
    float sy = max(0.002, 2.0 * band);
    float sx = mix(1.0, 0.5, smoothstep(0.82, 1.0, p));
    vec2 q = vec2((uv.x - 0.5) / sx + 0.5, (uv.y - 0.5) / sy + 0.5);
    float split = 0.010 * p * (0.5 + 0.5 * hash(vec2(floor(q.x * 120.0), 5.0)));
    vec3 c = vec3(texture(tex, q + vec2(split, 0.0)).r, texture(tex, q).g, texture(tex, q - vec2(split, 0.0)).b);
    c = mix(c, PHOS * 1.25, smoothstep(0.35, 1.0, p) * 0.8);   // the picture burning to the phosphor
    float scan = 0.5 + 0.5 * sin(uv.y * surface_size.y * 3.14159);
    c *= mix(1.0, 0.75 + 0.25 * scan, smoothstep(0.0, 0.6, p));
    float edge = exp(-d * surface_size.y / 2.0);
    c += PHOS * edge * smoothstep(0.15, 0.85, p) * 1.1;
    float alpha = inside * (1.0 - smoothstep(0.92, 1.0, p));
    fragColor = vec4(c * alpha, alpha);
}
]]

-- The glitch, opening: the window arrives in horizontal slices, each still out of its place,
-- slid sideways and split into its colours, out of snow and with the line along it lit; each lands
-- at its own moment, and by progress 1 every slice is home and the frame is its own.
local GLITCH_OPEN = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float rows = max(4.0, floor(surface_size.y / 18.0));
    float row = floor(uv.y * rows);
    float land = 0.35 + 0.55 * hash(vec2(row, 1.0));                 // when this slice stops moving
    float k = 1.0 - smoothstep(land - 0.20, land + 0.04, p);         // 1 while it is still off its place
    float dx = (hash(vec2(row, 4.0)) - 0.5) * 0.6 * k;
    float split = 0.014 * k;
    vec2 q = vec2(uv.x + dx, uv.y);
    vec3 c = vec3(texture(tex, q + vec2(split, 0.0)).r, texture(tex, q).g, texture(tex, q - vec2(split, 0.0)).b);
    float n = hash(floor(uv * surface_size / 2.0) + floor(p * 26.0));
    c = mix(c, vec3(n) * 0.55, k * 0.30);                            // the snow it arrives out of
    c += PHOS * exp(-abs(fract(uv.y * rows) - 0.5) * 20.0) * k * 0.8;
    fragColor = vec4(c, 1.0);
}
]]

-- The glitch, closing: the slices tear off one by one, each dragged out of the frame and left as
-- snow with its edge lit, until there is nothing left to draw — the alpha that goes with them is
-- 0 at progress 1.
local GLITCH_CLOSE = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float rows = max(4.0, floor(surface_size.y / 16.0));
    float row = floor(uv.y * rows);
    float r = hash(vec2(row, 7.0));
    float gone = 0.30 + 0.60 * r;                                    // when this slice tears off (the last at 0.9)
    float k = smoothstep(gone - 0.12, gone + 0.10, p);               // 0 whole .. 1 gone
    float dx = (r - 0.5) * 1.2 * k * k;
    float split = 0.016 * k;
    vec2 q = vec2(uv.x + dx, uv.y);
    vec3 c = vec3(texture(tex, q + vec2(split, 0.0)).r, texture(tex, q).g, texture(tex, q - vec2(split, 0.0)).b);
    float n = hash(floor(uv * surface_size / 2.0) + floor(p * 30.0));
    c = mix(c, vec3(n), k * 0.85);
    c += PHOS * exp(-abs(fract(uv.y * rows) - 0.5) * 18.0) * k;
    float alpha = 1.0 - k;
    fragColor = vec4(c * alpha, alpha);
}
]]

-- The iris, opening: a lens opens out of the middle of the window, the picture inside it and the
-- phosphor on its rim; by progress 1 the lens is wider than the window's corners and what is
-- drawn is the frame itself.
local IRIS_OPEN = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    vec2 q = (uv - 0.5) * vec2(surface_size.x / surface_size.y, 1.0);
    float rr = length(q);
    float reach = 1.45 * pow(p, 1.35);                               // out of nothing, past the corners at the end
    float inside = 1.0 - smoothstep(reach - 0.30, reach, rr);
    vec3 c = texture(tex, uv).rgb * inside;
    float ring = exp(-pow((rr - reach) * 90.0, 2.0)) * (1.0 - p);
    c += PHOS * ring * 0.9;
    fragColor = vec4(c, inside);
}
]]

-- The iris, closing: the lens shuts to a point, the rim hotter the smaller it gets, the picture
-- gone with it — alpha is 0 at progress 1.
local IRIS_CLOSE = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    vec2 q = (uv - 0.5) * vec2(surface_size.x / surface_size.y, 1.0);
    float rr = length(q);
    float reach = 1.45 * pow(1.0 - p, 1.2);                          // past the corners at p = 0, a point at p = 1
    float inside = 1.0 - smoothstep(reach - 0.30, reach, rr);
    vec3 c = texture(tex, uv).rgb;
    float ring = exp(-pow((rr - reach) * 35.0, 2.0)) * smoothstep(0.05, 0.2, p);
    c += PHOS * ring * (0.8 + 0.6 * p);
    fragColor = vec4(c * inside, inside);
}
]]


-- D297: liquid, opening: the window rises up out of the bottom through a ripple that settles as it
-- arrives; at progress 1 the ripple is gone and the window is its own pixels.
local LIQUID_OPEN = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float e = 1.0 - pow(1.0 - p, 3.0);
    float amp = 0.035 * (1.0 - e);
    vec2 q = uv + vec2(sin(uv.y * 26.0 + p * 18.0) * amp, (1.0 - e) * 0.22);
    float inside = step(0.0, q.y) * step(q.y, 1.0);
    vec3 c = texture(tex, clamp(q, 0.0, 1.0)).rgb;
    float a = inside * smoothstep(0.0, 0.35, p);
    c = mix(c, c + PHOS * 0.25, (1.0 - e) * 0.6);
    fragColor = vec4(c * a, a);
}
]]

-- D297: liquid, closing: it melts downwards in uneven drips, warming as it goes; alpha 0 at the end.
local LIQUID_CLOSE = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float drip = p * (0.6 + 0.8 * hash(vec2(floor(uv.x * 40.0), 7.0)));
    vec2 q = vec2(uv.x + sin(uv.y * 20.0 + p * 10.0) * 0.02 * p, uv.y - drip);
    float inside = step(0.0, q.y);
    vec3 c = texture(tex, clamp(q, 0.0, 1.0)).rgb + EMBER * 0.2 * p;
    float a = inside * (1.0 - p);
    fragColor = vec4(c * a, a);
}
]]

-- D297: pixel, opening: big blocks that halve and halve again until they are the window's pixels.
local PIXEL_OPEN = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float cells = mix(8.0, max(surface_size.x, surface_size.y), pow(p, 3.0));
    vec2 grid = vec2(cells, cells * surface_size.y / max(1.0, surface_size.x));
    vec2 q = p < 0.999 ? (floor(uv * grid) + 0.5) / grid : uv;
    vec3 c = texture(tex, q).rgb;
    float a = smoothstep(0.0, 0.25, p);
    fragColor = vec4(c * a, a);
}
]]

-- D297: pixel, closing: the window breaks into ever bigger blocks that go out one by one.
local PIXEL_CLOSE = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float cells = mix(max(surface_size.x, surface_size.y), 10.0, pow(p, 0.5));
    vec2 grid = vec2(cells, cells * surface_size.y / max(1.0, surface_size.x));
    vec2 cell = floor(uv * grid);
    vec3 c = texture(tex, (cell + 0.5) / grid).rgb;
    float gone = step(hash(cell), p * 1.15);
    float a = (1.0 - gone) * (1.0 - p);
    fragColor = vec4(c * a, a);
}
]]

-- D297: fold, opening: it unfolds downwards from its top edge, shaded along the fold, ending flat.
local FOLD_OPEN = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float e = 1.0 - pow(1.0 - p, 2.0);
    float reach = max(0.001, e);
    float inside = step(uv.y, reach);
    vec2 q = vec2(uv.x, uv.y / reach);
    vec3 c = texture(tex, clamp(q, 0.0, 1.0)).rgb;
    float shade = mix(0.55, 1.0, e) + 0.35 * (1.0 - e) * (1.0 - abs(q.y * 2.0 - 1.0));
    float a = inside * smoothstep(0.0, 0.2, p);
    fragColor = vec4(c * shade * a, a);
}
]]

-- D297: fold, closing: it folds back up into its top edge, darkening as it goes.
local FOLD_CLOSE = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    float reach = max(0.001, 1.0 - pow(p, 0.8));
    float inside = step(uv.y, reach);
    vec2 q = vec2(uv.x, uv.y / reach);
    vec3 c = texture(tex, clamp(q, 0.0, 1.0)).rgb * mix(1.0, 0.45, p);
    float a = inside * (1.0 - p);
    fragColor = vec4(c * a, a);
}
]]

-- D297: dust, opening: grains drift in and settle into the window, the last of them lit.
local DUST_OPEN = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    vec2 grain = floor(uv * surface_size / 3.0);
    float h = hash(grain);
    float arrive = smoothstep(h * 0.7, h * 0.7 + 0.3, p);
    vec2 off = (vec2(hash(grain + 1.7), hash(grain + 4.1)) - 0.5) * 0.25 * (1.0 - arrive);
    vec3 c = texture(tex, clamp(uv + off, 0.0, 1.0)).rgb;
    c += PHOS * 0.4 * arrive * (1.0 - arrive) * 4.0;
    float a = p >= 0.999 ? 1.0 : arrive;
    fragColor = vec4(c * a, a);
}
]]

-- D297: dust, closing: from the left, the window comes apart into grains that blow away; alpha 0 at the end.
local DUST_CLOSE = [[
void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    vec2 grain = floor(uv * surface_size / 3.0);
    float h = hash(grain);
    float leave = smoothstep(uv.x * 0.6 + h * 0.3, uv.x * 0.6 + h * 0.3 + 0.25, p * 1.2);
    vec2 drift = vec2(0.35, -0.12 - 0.2 * h) * leave;
    vec3 c = texture(tex, clamp(uv - drift, 0.0, 1.0)).rgb + EMBER * 0.35 * leave;
    float a = (1.0 - leave) * (1.0 - p * p);
    fragColor = vec4(c * a, a);
}
]]

local OPEN = { phosphor = PHOSPHOR_OPEN, glitch = GLITCH_OPEN, iris = IRIS_OPEN, liquid = LIQUID_OPEN, pixel = PIXEL_OPEN,
               fold = FOLD_OPEN, dust = DUST_OPEN }
local CLOSE = { phosphor = PHOSPHOR_CLOSE, glitch = GLITCH_CLOSE, iris = IRIS_CLOSE, liquid = LIQUID_CLOSE, pixel = PIXEL_CLOSE,
                fold = FOLD_CLOSE, dust = DUST_CLOSE }

-- One file's text: the header with the palette and the length, then the body.
local function shader(body, what, dur, pal)
    return (string.gsub(HEAD .. body, "@(%u+)@", {
        WHAT = what,
        DUR = string.format("%.2f", dur),
        PHOS = rgb(pal.phos, "vec3(0.498, 0.812, 0.714)"),
        EMBER = rgb(pal.ember, "vec3(0.878, 0.482, 0.180)"),
        BASE = rgb(pal.trace, "vec3(0.239, 0.416, 0.376)"),
    }))
end

-- How long it runs, against the pair's own lengths: `speed` percent, 100 as designed. Held to a
-- range of its own, so a settings.json written by hand cannot leave a window in an effect for a
-- minute, nor in one that is over before it is seen.
local function scaled(dur, speed)
    local s = tonumber(speed) or 100
    if s < 25 then s = 25 elseif s > 300 then s = 300 end
    return dur * s / 100
end

-- How long `kind` runs at `speed` percent of its own length: { open, close } in seconds.
function M.duration(kind, speed)
    local k = M.KINDS[kind]
    return k and { open = scaled(k.open, speed), close = scaled(k.close, speed) } or nil
end

-- Both shaders of `kind` in the palette `pal` ({ phos, ember, trace } as #rrggbb), each as long as
-- `speed` percent of its own length: { open, close }. nil for `off` and for a name that is not a
-- pair's — no shader is the setting's off.
function M.pair(kind, pal, speed)
    local d = M.duration(kind, speed)
    if not d then return nil end
    pal = type(pal) == "table" and pal or {}
    return { open = shader(OPEN[kind], "opening", d.open, pal),
             close = shader(CLOSE[kind], "closing", d.close, pal) }
end

-- The overrides: for each of M.APPS its class and the two shaders it plays instead of the
-- catch-all pair (the app's own pair, at the same speed and in the same palette). Empty while the
-- setting has them off.
function M.apps(pal, speed)
    local out = {}
    for _, a in ipairs(M.APPS) do
        local p = M.pair(a.pair, pal, speed)
        if p then out[#out + 1] = { name = a.name, class = a.class, open = p.open, close = p.close } end
    end
    return out
end

return M
