// The Membrane (spec §10): a soft film stretched round the hole, a slow bulge and a one-pixel rim — the wallpaper
// bends without tearing. Values: (open, x, y, w, h, corner, params, —); params packs intensity × 1000 + edge × 10 +
// colour, and the group's screen origin is derived from x/y and the 40 px the edge grows by.
fn mb_box(p: vec2<f32>, c: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
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
    let sd = mb_box(p, c, half, r);
    let e = 0.75;
    var nrm = vec2<f32>(mb_box(p + vec2<f32>(e, 0.0), c, half, r) - mb_box(p - vec2<f32>(e, 0.0), c, half, r),
                        mb_box(p + vec2<f32>(0.0, e), c, half, r) - mb_box(p - vec2<f32>(0.0, e), c, half, r));
    let nl = length(nrm);
    if (nl > 0.0001) { nrm = nrm / nl; } else { nrm = vec2<f32>(0.0, 0.0); }
    let wide = 0.5 + 1.1 * edge;
    let t = max(sd, 0.0) / 24.0;
    let push = 18.0 * k * strength * wide * exp(-(t * t));
    let pic = inside(s, s.pos - nrm * push);
    let hole = smoothstep(0.75, -0.75, sd) * step(0.001, k);
    let film = exp(-max(sd, 0.0) / 18.0) * (1.0 - hole) * k * strength;
    var col = mix(pic.rgb, rim, film * 0.34);
    let rimw = 1.0 + 1.2 * edge;
    let rimline = (1.0 - min(abs(sd - 0.7) / rimw, 1.0)) * (1.0 - hole) * k * strength;
    col = mix(col, rim, rimline * 0.8);
    return vec4<f32>(col, max(pic.a, max(film * 0.3, rimline)) * (1.0 - hole));
}
