// Moves the wallpaper (spec §9, D217): what lives below drives the picture round its place. A group shader over the
// real wallpaper in a patch round the widget. Values: (amount, patch x, patch y, box x, box y, box w, box h, mode):
// mode 1 — a visualiser's ripple, the amount the music's level: rings run out from its place, bending the picture;
// mode 2 … 2.99 — the clock's hour: a band of light crosses its place, the amount where the band is (0 … 1), the
// fraction how seen it is. It draws only where the picture moves or is lit, so the patch never shows a seam.
fn sk_box(p: vec2<f32>, c: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let q = abs(p - c) - half + vec2<f32>(r, r);
    return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn shade(s: Shader) -> vec4<f32> {
    let amount = clamp(s.a.x, 0.0, 1.0);
    let origin = vec2<f32>(s.a.y, s.a.z);
    let half = max(vec2<f32>(s.b.y, s.b.z) * 0.5, vec2<f32>(1.0, 1.0));
    let c = vec2<f32>(s.a.w, s.b.x) + half;
    let mode = s.b.w;
    let p = s.pos + origin;
    if (mode < 1.5) {
        // the ripple: outside the widget's place, a few rings, stronger with the music
        let sd = sk_box(p, c, half, 18.0);
        let out = max(sd, 0.0);
        let e = 0.75;
        var nrm = vec2<f32>(sk_box(p + vec2<f32>(e, 0.0), c, half, 18.0) - sk_box(p - vec2<f32>(e, 0.0), c, half, 18.0),
                            sk_box(p + vec2<f32>(0.0, e), c, half, 18.0) - sk_box(p - vec2<f32>(0.0, e), c, half, 18.0));
        let nl = length(nrm);
        if (nl > 0.0001) { nrm = nrm / nl; } else { nrm = vec2<f32>(0.0, 0.0); }
        let wave = sin(out / 8.0 - s.time * 3.0);
        let fade = exp(-out / 30.0) * step(0.0, sd);
        let push = 5.0 * (0.25 + amount) * wave * fade;
        let pic = inside(s, p - nrm * push - origin);
        let alpha = clamp(abs(push) * 0.9, 0.0, 1.0) * pic.a;
        let shine = 1.0 + 0.06 * wave * fade * amount;
        return vec4<f32>(clamp(pic.rgb * shine, vec3<f32>(0.0), vec3<f32>(1.0)), alpha);
    }
    // the sweep: a soft diagonal band crossing the place, left to right
    let seen = clamp((mode - 2.0) / 0.99, 0.0, 1.0);
    let span = half.x * 2.0 + half.y * 2.0 + 240.0;
    let along = (p.x - (c.x - half.x - 120.0)) + (p.y - (c.y - half.y)) * 0.5;
    let band = exp(-pow((along - amount * span) / 46.0, 2.0)) * seen;
    let pic = inside(s, s.pos);
    let col = clamp(pic.rgb + vec3<f32>(1.0, 0.92, 0.78) * band * 0.22, vec3<f32>(0.0), vec3<f32>(1.0));
    return vec4<f32>(col, smoothstep(0.0, 0.05, band) * pic.a);
}
