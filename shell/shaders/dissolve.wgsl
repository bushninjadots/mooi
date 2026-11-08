// The Dissolve (spec §10): the wallpaper erodes into the hole through a coarse grain, leaving a luminous edge.
// Values: (open, x, y, w, h, corner, params, —); params packs intensity × 1000 + edge × 10 + colour, and the
// group's screen origin is derived from x/y and the 40 px the edge grows by.
fn ds_box(p: vec2<f32>, c: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let q = abs(p - c) - half + vec2<f32>(r, r);
    return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn ds_hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn ds_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(ds_hash(i), ds_hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(ds_hash(i + vec2<f32>(0.0, 1.0)), ds_hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
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
    let sd = ds_box(p, c, half, r);
    let pic = inside(s, s.pos);
    let hole = smoothstep(0.75, -0.75, sd) * step(0.001, k);
    // the grain's threshold, growing outward with the edge width
    let front = smoothstep(-6.0, 10.0 + edge * 24.0, sd);
    let n = ds_noise(p / 5.0) * 0.6 + ds_noise(p / 13.0) * 0.4;
    let mask = smoothstep(n * 0.85, n * 0.85 + 0.18, front);
    let spark = clamp(front * (1.0 - front) * 4.0, 0.0, 1.0) * (1.0 - hole) * k * strength;
    var col = mix(pic.rgb, rim, spark * 0.55);
    return vec4<f32>(col, max(pic.a * mask, spark * 0.38) * (1.0 - hole));
}
