// The Glow (spec §10): no tear at all — the wallpaper simply gives way, and a soft coloured halo marks the
// opening. Values: (open, x, y, w, h, corner, params, —); params packs intensity × 1000 + edge × 10 + colour, and
// the group's screen origin is derived from x/y and the 40 px the edge grows by.
fn gw_box(p: vec2<f32>, c: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let q = abs(p - c) - half + vec2<f32>(r, r);
    return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn shade(s: Shader) -> vec4<f32> {
    let k = clamp(s.a.x, 0.0, 1.0);
    let half = max(vec2<f32>(s.a.w, s.b.x) * 0.5, vec2<f32>(1.0, 1.0));
    let c = vec2<f32>(s.a.y, s.a.z) + half;
    let r = clamp(s.b.y, 0.0, min(half.x, half.y));
    let param = s.b.z;
    let strength = clamp(floor(param / 1000.0) / 100.0, 0.0, 1.0);
    let rest = param - floor(param / 1000.0) * 1000.0;
    let edge = clamp(floor(rest / 10.0) / 100.0, 0.0, 1.0);
    let ci = rest - floor(rest / 10.0) * 10.0;
    var rim = vec3<f32>(0.62, 0.84, 0.74);
    if (ci > 0.5) { rim = vec3<f32>(0.86, 0.88, 0.86); }
    if (ci > 1.5) { rim = vec3<f32>(0.95, 0.62, 0.38); }
    let origin = max(vec2<f32>(0.0, 0.0), vec2<f32>(s.a.y, s.a.z) - 40.0);
    let p = s.pos + origin;
    let sd = gw_box(p, c, half, r);
    let hole = smoothstep(0.75, -0.75, sd) * step(0.001, k);
    let out = max(sd, 0.0);
    let wide = 0.5 + 1.4 * edge;
    let halo = exp(-out / (10.0 * wide)) * (1.0 - hole) * k * strength;
    let ring = exp(-pow((out - 12.0 * wide) / (7.0 * wide), 2.0)) * (1.0 - hole) * k * strength;
    let col = rim * (halo * 0.52 + ring * 0.42);
    return vec4<f32>(col, clamp(halo * 0.45 + ring * 0.6, 0.0, 1.0) * (1.0 - hole));
}
