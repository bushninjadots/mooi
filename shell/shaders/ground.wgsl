// The subsurface's ground (D209, spec §3): what the hole shows before anything lives there — the Aperture's dark
// phosphor shade and its 14 px grid, the grid fixed to the screen. s.a = (open 0…1, box x, box y, 0).
// Its twin: the `sub` colour and grid of the D208 aperture.wgsl, which painted them inside its hole. In D209 the
// Aperture's hole is clear (it is drawn on `edge`, above this) and they live only here: change them here.
fn shade(s: Shader) -> vec4<f32> {
    let p = s.pos + vec2<f32>(s.a.y, s.a.z);
    var sub = mix(vec3<f32>(0.035, 0.045, 0.035), vec3<f32>(0.10, 0.12, 0.07), 0.7);
    let grid = step(0.93, fract(p.x / 14.0)) + step(0.93, fract(p.y / 14.0));
    sub = sub + vec3<f32>(0.6, 0.7, 0.35) * 0.05 * grid;
    return vec4<f32>(sub, clamp(s.a.x, 0.0, 1.0));
}
