// The Tear (D209, spec §3, §10): the wallpaper torn open over the hole. The eight values are
// (open 0…1, x, y, w, h, corner, params, —): params packs the settings — intensity × 1000 + edge × 10 + colour —
// and the group's screen origin is derived from x/y and the 40 px the edge grows by, so every value is free.
// Outside the box: the picture, pushed outward; a ragged lip, a little lighter than the picture under it, strongest
// at the tear; paper fibres reaching a few px over the hole. Inside: nothing but a shadow at its border.

fn tear_box(p: vec2<f32>, c: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let q = abs(p - c) - half + vec2<f32>(r, r);
    return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn tear_along(d: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let inner = half - vec2<f32>(r, r);
    let l1 = 2.0 * inner.x;
    let l2 = 2.0 * inner.y;
    let a = 1.5707963 * r;
    let q = abs(d) - inner;
    if (q.x > 0.0 && q.y > 0.0) {
        let v = d - sign(d) * inner;
        if (d.x > 0.0 && d.y < 0.0) { return l1 + r * clamp(atan2(v.x, -v.y), 0.0, 1.5707963); }
        if (d.x > 0.0) { return l1 + a + l2 + r * clamp(atan2(v.y, v.x), 0.0, 1.5707963); }
        if (d.y > 0.0) { return 2.0 * l1 + 2.0 * a + l2 + r * clamp(atan2(-v.x, v.y), 0.0, 1.5707963); }
        return 2.0 * l1 + 3.0 * a + 2.0 * l2 + r * clamp(atan2(-v.y, -v.x), 0.0, 1.5707963);
    }
    if (q.y >= q.x) {
        if (d.y < 0.0) { return d.x + inner.x; }
        return l1 + 2.0 * a + l2 + (inner.x - d.x);
    }
    if (d.x > 0.0) { return l1 + a + (d.y + inner.y); }
    return 2.0 * l1 + 3.0 * a + l2 + (inner.y - d.y);
}

fn tear_hash(i: f32, seed: f32) -> f32 {
    return fract(sin(i * 127.1 + seed * 311.7) * 43758.5453);
}

fn tear_vnoise(x: f32, seed: f32) -> f32 {
    let i = floor(x);
    let f = x - i;
    return mix(tear_hash(i, seed), tear_hash(i + 1.0, seed), f * f * (3.0 - 2.0 * f));
}

fn tear_noise(at: f32, perim: f32, cell: f32, seed: f32) -> f32 {
    let w = smoothstep(perim - 40.0, perim, at);
    return mix(tear_vnoise(at / cell, seed), tear_vnoise((at - perim) / cell, seed), w);
}

fn shade(s: Shader) -> vec4<f32> {
    let k = clamp(s.a.x, 0.0, 1.0);
    let half = max(vec2<f32>(s.a.w, s.b.x) * 0.5, vec2<f32>(1.0, 1.0));
    let c = vec2<f32>(s.a.y, s.a.z) + half;
    let param = s.b.z;
    let strength = clamp(floor(param / 1000.0) / 100.0, 0.0, 1.0);
    let rest = param - floor(param / 1000.0) * 1000.0;
    let edge = clamp(floor(rest / 10.0) / 100.0, 0.0, 1.0);
    let ci = rest - floor(rest / 10.0) * 10.0;
    var rim = vec3<f32>(0.62, 0.84, 0.74);
    if (ci > 0.5) { rim = vec3<f32>(0.86, 0.88, 0.86); }
    if (ci > 1.5) { rim = vec3<f32>(0.95, 0.62, 0.38); }
    let rr = clamp(s.b.y, 0.0, min(half.x, half.y));
    let origin = max(vec2<f32>(0.0, 0.0), vec2<f32>(s.a.y, s.a.z) - 40.0);
    let p = s.pos + origin;
    let sd = tear_box(p, c, half, rr);
    let e = 0.75;
    var nrm = vec2<f32>(tear_box(p + vec2<f32>(e, 0.0), c, half, rr) - tear_box(p - vec2<f32>(e, 0.0), c, half, rr),
                        tear_box(p + vec2<f32>(0.0, e), c, half, rr) - tear_box(p - vec2<f32>(0.0, e), c, half, rr));
    let nl = length(nrm);
    if (nl > 0.0001) { nrm = nrm / nl; } else { nrm = vec2<f32>(0.0, 0.0); }
    let perim = 4.0 * (half.x + half.y - 2.0 * rr) + 6.2831853 * rr;
    let at = tear_along(p - c, half, rr);
    let wide = 0.4 + 1.2 * edge;
    let band = (4.0 + 10.0 * tear_noise(at, perim, 40.0, 1.0)) * k * strength * wide;
    let fib = (1.0 + 4.0 * tear_noise(at, perim, 7.0, 2.0)) * k * strength;
    let lip_end = band * (0.4 + 0.6 * tear_noise(at, perim, 5.0, 3.0));
    let t = max(sd, 0.0) / 16.0;
    let push = 10.0 * k * strength * wide * (0.35 + 0.65 * tear_noise(at, perim, 18.0, 4.0)) * exp(-(t * t));
    let pic = inside(s, s.pos - nrm * push);
    let hole = smoothstep(-fib + 0.75, -fib - 0.75, sd) * step(0.001, k);
    let lip = smoothstep(lip_end + 0.75, lip_end - 0.75, sd) * (1.0 - hole);
    let fade = 1.0 - clamp((sd + fib) / max(lip_end + fib, 1.0), 0.0, 1.0);
    let lighter = mix(min(pic.rgb * 1.25 + vec3<f32>(0.06), vec3<f32>(1.0)), rim, 0.28 * strength);
    var col = mix(pic.rgb, lighter, 0.6 * lip * fade);
    let crease = 1.0 - min(abs(sd - lip_end) / 1.2, 1.0);
    col = col * (1.0 - 0.25 * crease * k);
    let st = clamp((-sd - fib) / 14.0, 0.0, 1.0);
    let shadow = (1.0 - st) * (1.0 - st) * 0.55 * k * strength;
    let a = mix(pic.a, shadow, hole);
    col = mix(col, vec3<f32>(0.0), hole);
    return vec4<f32>(col, a);
}
