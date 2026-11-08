// The Aperture (D208, spec §5, §6): over the wallpaper the program draws, a hole at (cx, cy) of radius r
// shows the subsurface — the picture darkened toward the phosphor's shade, a fine grid of the hidden layer —
// and the picture is pushed outward just past the rim, as a lens. s.a = (open 0…1, cx, cy, r).
fn shade(s: Shader) -> vec4<f32> {
    let k = s.a.x;
    let c = vec2<f32>(s.a.y, s.a.z);
    let r = max(s.a.w, 0.001);
    let d = s.pos - c;
    let dist = length(d);
    var push = vec2<f32>(0.0, 0.0);
    if (dist > 0.5) { push = d / dist * 14.0 * k * exp(-pow((dist - r) / 22.0, 2.0)); }
    let pic = inside(s, s.pos - push);
    let inner = smoothstep(r + 1.5, r - 1.5, dist);
    let g = dot(pic.rgb, vec3<f32>(0.3, 0.5, 0.2));
    var sub = mix(vec3<f32>(0.035, 0.045, 0.035), vec3<f32>(0.10, 0.12, 0.07) + g * vec3<f32>(0.07, 0.09, 0.04), 0.7);
    let grid = step(0.93, fract(s.pos.x / 14.0)) + step(0.93, fract(s.pos.y / 14.0));
    sub = sub + vec3<f32>(0.6, 0.7, 0.35) * 0.05 * grid;
    let col = mix(pic.rgb, sub, inner * k);
    return vec4<f32>(col, pic.a);
}
