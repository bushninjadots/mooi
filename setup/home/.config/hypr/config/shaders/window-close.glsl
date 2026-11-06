#version 320 es
// mooi's window close (HyprWindowShade, `+shader_close:`): the window shuts down the way a screen
// does — it collapses to a lit line, the line burns hotter than the picture it came from, and then
// the line goes out. The plugin pins the snapshot's alpha for the length of the effect, so this
// shader owns the disappearance and has to reach 0 at `progress` 1 (it does, on the last line).
// The light is mooi's phosphor (lib/wsfx's PHOS at the palette's default teal).
// @duration 0.36
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
    // the band the window is squeezed into: the whole of it at p = 0, one row at p = 1
    float band = 0.5 * pow(1.0 - p, 0.7);
    float d = abs(uv.y - 0.5);
    float inside = 1.0 - smoothstep(band - 0.002, band + 0.002, d);
    float sy = max(0.002, 2.0 * band);
    float sx = mix(1.0, 0.5, smoothstep(0.82, 1.0, p));       // and pinched sideways at the last
    vec2 q = vec2((uv.x - 0.5) / sx + 0.5, (uv.y - 0.5) / sy + 0.5);
    float split = 0.010 * p * (0.5 + 0.5 * hash(vec2(floor(q.x * 120.0), seed)));
    vec3 c = vec3(texture(tex, q + vec2(split, 0.0)).r,
                  texture(tex, q).g,
                  texture(tex, q - vec2(split, 0.0)).b);
    // the picture burns to the phosphor as it goes, the line brighter than what it carries
    c = mix(c, PHOS * 1.25, smoothstep(0.35, 1.0, p) * 0.8);
    float scan = 0.5 + 0.5 * sin(uv.y * surface_size.y * 3.14159);
    c *= mix(1.0, 0.75 + 0.25 * scan, smoothstep(0.0, 0.6, p));
    float edge = exp(-d * surface_size.y / 2.0);
    c += PHOS * edge * smoothstep(0.15, 0.85, p) * 1.1;
    // the line goes out: alpha is 0 at progress 1, which is the close path's one rule
    float alpha = inside * (1.0 - smoothstep(0.92, 1.0, p));
    fragColor = vec4(c * alpha, alpha);
}
