#version 320 es
// mooi's window open (HyprWindowShade, `+shader_open:`): the window wakes the way a screen does —
// a lit line opens out of its middle row into the picture, the scanlines settle, the phosphor
// leaves it. `progress` runs 0 -> 1 over the animation; `// @duration` is how long that takes.
// The light is mooi's phosphor (lib/wsfx's PHOS at the palette's default teal).
// @duration 0.34
precision highp float;
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float progress;
uniform float seed;
uniform vec2 surface_size;

const vec3 PHOS = vec3(0.498, 0.812, 0.714);

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void main() {
    float p = clamp(progress, 0.0, 1.0);
    vec2 uv = v_texcoord;
    // the band of the window that exists yet: the middle row at p = 0, the whole of it at p = 1
    float band = 0.5 * pow(p, 0.55);
    float d = abs(uv.y - 0.5);
    float inside = 1.0 - smoothstep(band - 0.002, band + 0.002, d);
    // the picture is squeezed into that band and unwound as the band grows, so nothing jumps in
    float sy = max(0.002, 2.0 * band);
    vec2 q = vec2(uv.x, (uv.y - 0.5) / sy + 0.5);
    float split = 0.006 * (1.0 - p) * (0.5 + 0.5 * hash(vec2(floor(q.y * 90.0), seed)));
    vec3 c = vec3(texture(tex, q + vec2(split, 0.0)).r,
                  texture(tex, q).g,
                  texture(tex, q - vec2(split, 0.0)).b);
    // the scanlines it arrives through, and the lit edge of the band
    float scan = 0.5 + 0.5 * sin(uv.y * surface_size.y * 3.14159);
    c *= mix(1.0, 0.82 + 0.18 * scan, 1.0 - p);
    float edge = exp(-d * surface_size.y / 2.5);
    c += PHOS * edge * (0.9 - 0.5 * p) * step(0.001, p);
    // the phosphor drains out of the whole window as it settles
    c = mix(c, mix(c, PHOS * 0.5 + 0.45, 0.55), (1.0 - p) * (1.0 - p));
    fragColor = vec4(c * inside, inside);
}
