// The Tear (D209, spec §3, §10): the wallpaper torn open over the hole. s.a = (open 0…1, x, y, w),
// s.b = (h, corner, ox, oy): the hole's rounded box on the screen, and where the group's box (whose top left
// corner s.pos counts from) begins on it.
// Outside the box: the picture, pushed outward up to 10 px; a ragged lip 6–22 px wide, lightened (the paper's
// underside); paper fibres reaching a few px over the hole. Inside: nothing but a 14 px shadow at its border.
// The raggedness is seeded by the place along the edge — no time, nothing moves but the hole itself.

fn tear_box(p: vec2<f32>, c: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let q = abs(p - c) - half + vec2<f32>(r, r);
    return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn tear_hash(i: f32, seed: f32) -> f32 {
    return fract(sin(i * 127.1 + seed * 311.7) * 43758.5453);
}

// value noise along the edge, periodic over n cells (so the seam where the angle wraps does not show)
fn tear_noise(x: f32, n: f32, seed: f32) -> f32 {
    let i = floor(x);
    let f = x - i;
    let j = i + 1.0;
    let a = tear_hash(i - n * floor(i / n), seed);
    let b = tear_hash(j - n * floor(j / n), seed);
    return mix(a, b, f * f * (3.0 - 2.0 * f));
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
    // where along the edge (0…1 round the hole), and how many cells each scale of noise has round it
    let d = p - c;
    let u = atan2(d.y, d.x) / 6.2831853 + 0.5;
    let perim = 2.0 * (half.x + half.y) * 2.0;
    let n_band = max(6.0, round(perim / 40.0));
    let n_push = max(8.0, round(perim / 18.0));
    let n_fib = max(12.0, round(perim / 7.0));
    let band = (6.0 + 16.0 * tear_noise(u * n_band, n_band, 1.0)) * k;          // the lip, 6–22 px
    let fib = (1.0 + 4.0 * tear_noise(u * n_fib, n_fib, 2.0)) * k;              // fibres over the hole, 1–5 px
    let lip_end = band * (0.75 + 0.25 * tear_noise(u * n_fib, n_fib, 3.0));      // the lip's own ragged outer line
    // the picture pushed outward, fading to nothing well inside the 40 px the group is clipped to
    let t = max(sd, 0.0) / 16.0;                                                 // t * t, never pow of a negative
    let push = 10.0 * k * (0.35 + 0.65 * tear_noise(u * n_push, n_push, 4.0)) * exp(-(t * t));
    let pic = inside(s, s.pos - nrm * push);
    // the hole: everything inside the fibres' line is open
    let hole = smoothstep(-fib + 0.75, -fib - 0.75, sd) * step(0.001, k);
    // the lip: from the hole to its ragged outer line, the paper's lighter underside
    let lip = smoothstep(lip_end + 0.75, lip_end - 0.75, sd) * (1.0 - hole);
    var col = mix(pic.rgb, vec3<f32>(1.0, 1.0, 1.0), 0.18 * lip);
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
