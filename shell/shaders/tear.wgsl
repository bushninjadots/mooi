// The Tear (D209, spec §3, §10): the wallpaper torn open over the hole. s.a = (open 0…1, x, y, w),
// s.b = (h, corner, ox, oy): the hole's rounded box on the screen, and where the group's box (whose top left
// corner s.pos counts from) begins on it.
// Outside the box: the picture, pushed outward up to 10 px; a thin ragged lip, a little lighter than the picture
// under it (the paper's underside), strongest at the tear; paper fibres reaching a few px over the hole. Inside:
// nothing but a 14 px shadow at its border. The raggedness is seeded by the distance along the hole's edge, in
// px from its top left corner — no time, and a hole that grows only lengthens it: nothing boils.

fn tear_box(p: vec2<f32>, c: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let q = abs(p - c) - half + vec2<f32>(r, r);
    return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// how far along the rounded box's edge, clockwise from where the top side begins, the point nearest d lies
// (d from the box's centre), in px
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

// value noise along the edge, cells of a fixed size in px; over its last 40 px it fades into its own start, so the
// loop closes without a seam at the top left corner
fn tear_noise(at: f32, perim: f32, cell: f32, seed: f32) -> f32 {
    let w = smoothstep(perim - 40.0, perim, at);
    return mix(tear_vnoise(at / cell, seed), tear_vnoise((at - perim) / cell, seed), w);
}

fn shade(s: Shader) -> vec4<f32> {
    let k = clamp(s.a.x, 0.0, 1.0);
    let half = max(vec2<f32>(s.a.w, s.b.x) * 0.5, vec2<f32>(1.0, 1.0));
    let c = vec2<f32>(s.a.y, s.a.z) + half;
    let r = clamp(s.b.y, 0.0, min(half.x, half.y));
    let p = s.pos + vec2<f32>(s.b.z, s.b.w);                                     // the screen's coordinates
    let sd = tear_box(p, c, half, r);
    // the outward direction: the distance's gradient
    let e = 0.75;
    var nrm = vec2<f32>(tear_box(p + vec2<f32>(e, 0.0), c, half, r) - tear_box(p - vec2<f32>(e, 0.0), c, half, r),
                        tear_box(p + vec2<f32>(0.0, e), c, half, r) - tear_box(p - vec2<f32>(0.0, e), c, half, r));
    let nl = length(nrm);
    if (nl > 0.0001) { nrm = nrm / nl; } else { nrm = vec2<f32>(0.0, 0.0); }
    // where along the edge, in px
    let perim = 4.0 * (half.x + half.y - 2.0 * r) + 6.2831853 * r;
    let at = tear_along(p - c, half, r);
    let band = (4.0 + 10.0 * tear_noise(at, perim, 40.0, 1.0)) * k;              // the lip, 4–14 px
    let fib = (1.0 + 4.0 * tear_noise(at, perim, 7.0, 2.0)) * k;                 // fibres over the hole, 1–5 px
    let lip_end = band * (0.4 + 0.6 * tear_noise(at, perim, 5.0, 3.0));          // the lip's own ragged outer line
    // the picture pushed outward, fading to nothing well inside the 40 px the group is clipped to
    let t = max(sd, 0.0) / 16.0;                                                 // t * t, never pow of a negative
    let push = 10.0 * k * (0.35 + 0.65 * tear_noise(at, perim, 18.0, 4.0)) * exp(-(t * t));
    let pic = inside(s, s.pos - nrm * push);
    // the hole: everything inside the fibres' line is open
    let hole = smoothstep(-fib + 0.75, -fib - 0.75, sd) * step(0.001, k);
    // the lip: from the hole to its ragged outer line, a lighter version of the picture, strongest at the tear
    let lip = smoothstep(lip_end + 0.75, lip_end - 0.75, sd) * (1.0 - hole);
    let fade = 1.0 - clamp((sd + fib) / max(lip_end + fib, 1.0), 0.0, 1.0);
    let lighter = min(pic.rgb * 1.25 + vec3<f32>(0.06, 0.06, 0.06), vec3<f32>(1.0, 1.0, 1.0));
    var col = mix(pic.rgb, lighter, 0.6 * lip * fade);
    // a fine dark line where the lip meets the face of the paper
    let crease = 1.0 - min(abs(sd - lip_end) / 1.2, 1.0);
    col = col * (1.0 - 0.25 * crease * k);
    // inside: a 14 px shadow the paper casts on the subsurface
    let st = clamp((-sd - fib) / 14.0, 0.0, 1.0);
    let shadow = (1.0 - st) * (1.0 - st) * 0.55 * k;
    let a = mix(pic.a, shadow, hole);
    col = mix(col, vec3<f32>(0.0, 0.0, 0.0), hole);
    return vec4<f32>(col, a);
}
