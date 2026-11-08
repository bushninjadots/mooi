// The Fold (spec §10): the wallpaper creased into straight facets round the hole, as if folded back along six
// radiating lines. Values: (open, x, y, w, h, corner, params, —); params packs intensity × 1000 + edge × 10 +
// colour, and the group's screen origin is derived from x/y and the 40 px the edge grows by.
fn fd_box(p: vec2<f32>, c: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
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
    let sd = fd_box(p, c, half, r);
    let e = 0.75;
    var nrm = vec2<f32>(fd_box(p + vec2<f32>(e, 0.0), c, half, r) - fd_box(p - vec2<f32>(e, 0.0), c, half, r),
                        fd_box(p + vec2<f32>(0.0, e), c, half, r) - fd_box(p - vec2<f32>(0.0, e), c, half, r));
    let nl = length(nrm);
    if (nl > 0.0001) { nrm = nrm / nl; } else { nrm = vec2<f32>(0.0, 0.0); }
    let d = p - c;
    let ang = atan2(d.y, d.x);
    let seg = 1.0471976;                                    // six creases
    let off = abs(fract(ang / seg + 0.5) - 0.5) * seg;      // radians to the nearest crease
    let reach = max(length(d), 1.0);
    let crease = exp(-pow(off * reach / 5.0, 2.0));
    let wide = 0.4 + 1.2 * edge;
    let push = 10.0 * k * strength * wide * cos(ang * 6.0 + 0.7) * exp(-max(sd, 0.0) / 24.0);
    let pic = inside(s, s.pos - nrm * push);
    let hole = smoothstep(0.75, -0.75, sd) * step(0.001, k);
    let line = crease * (1.0 - hole) * k * strength;
    var col = mix(pic.rgb, rim, line * 0.30);
    col = col * (1.0 - 0.22 * line);
    return vec4<f32>(col, max(pic.a, line * 0.55) * (1.0 - hole));
}
