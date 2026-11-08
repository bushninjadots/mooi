// The subsurface's ground (D209, spec §3, §9): what the hole shows before anything lives there. It is a group
// shader over the wallpaper and its tint, so `inside` is the real picture, fitted; over it the quiet phosphor
// shade, the 14 px grid fixed to the screen, the dimming and the tint. The eight values are
// (open, x, y, dim, grid, tint, —, —).
fn shade(s: Shader) -> vec4<f32> {
    let k = clamp(s.a.x, 0.0, 1.0);
    let p = s.pos + vec2<f32>(s.a.y, s.a.z);
    let under = inside(s, s.pos);
    var sub = mix(vec3<f32>(0.035, 0.045, 0.035), vec3<f32>(0.10, 0.12, 0.07), 0.7);
    // the wallpaper, where it was drawn; no wallpaper: the shade alone
    var col = mix(sub, under.rgb, under.a);
    // how much of the shade is laid over the skin (the settings' dim)
    let dim = clamp(s.a.w, 0.0, 1.0);
    col = mix(col, sub, dim * 0.78);
    // the tint, always the accent
    let tint = clamp(s.b.y, 0.0, 1.0);
    col = mix(col, vec3<f32>(0.62, 0.84, 0.74), tint * 0.14);
    // the grid, anchored to the screen, as bright as the settings say
    let grid = clamp(s.b.x, 0.0, 1.0);
    let g = step(0.93, fract(p.x / 14.0)) + step(0.93, fract(p.y / 14.0));
    col = col + vec3<f32>(0.6, 0.7, 0.35) * 0.06 * g * grid;
    return vec4<f32>(col, k);
}
