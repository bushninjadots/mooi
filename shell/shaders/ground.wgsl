// The subsurface's ground (D209, spec §3, §9; D221 depth): what the hole shows under the widgets. A group shader
// over mooi's copy of the wallpaper and its tint, so `inside` is the real picture, fitted. D221: it reads as a hole
// and not a smudge — the picture under it is seen deeper (a parallax toward the middle, quieter, darker), with an
// inner shadow under the rim; over it the quiet phosphor shade, the 14 px grid fixed to the screen, the dimming
// and the tint. Values: (open, x, y, dim, grid, tint, hole w, hole h).
fn shade(s: Shader) -> vec4<f32> {
    let k = clamp(s.a.x, 0.0, 1.0);
    let p = s.pos + vec2<f32>(s.a.y, s.a.z);
    let size = max(vec2<f32>(s.b.z, s.b.w), vec2<f32>(1.0, 1.0));
    let mid = size * 0.5;
    // parallax: the picture below sits deeper, pulled toward the hole's middle
    let deep = mid + (s.pos - mid) * 0.9;
    let under = inside(s, deep);
    var sub = vec3<f32>(0.03, 0.04, 0.035);
    // quieter: less colour, less light
    let grey = dot(under.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let quiet = mix(under.rgb, vec3<f32>(grey), 0.45) * 0.72;
    var col = mix(sub, quiet, under.a);
    let dim = clamp(s.a.w, 0.0, 1.0);
    col = mix(col, sub, 0.25 + dim * 0.6);
    let tint = clamp(s.b.y, 0.0, 1.0);
    col = mix(col, vec3<f32>(0.62, 0.84, 0.74), tint * 0.14);
    // the grid, anchored to the screen
    let grid = clamp(s.b.x, 0.0, 1.0);
    let g = step(0.93, fract(p.x / 14.0)) + step(0.93, fract(p.y / 14.0));
    col = col + vec3<f32>(0.45, 0.62, 0.52) * 0.09 * g * grid;
    // inner shadow: dark under the rim, fading in over ~40 px — looking down into it
    let edge = min(min(s.pos.x, s.pos.y), min(size.x - s.pos.x, size.y - s.pos.y));
    let shadow = 1.0 - 0.75 * exp(-max(edge, 0.0) / 26.0);
    col = col * shadow;
    return vec4<f32>(col, k);
}
