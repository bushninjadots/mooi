// The Aperture (D208 spec §5, §6; D209): the other look of the opening, drawn on `edge` over the wallpaper. The
// hole is the same rounded box as the Tear's, and it is clear: what shows there is `ground` and what lives below
// (the subsurface's shade and grid moved to ground.wgsl in D209). Round it the picture is pushed outward, as a
// lens, and a thin lit rim marks the border. s.a = (open 0…1, x, y, w), s.b = (h, corner, ox, oy): the hole's box
// on the screen, and where the group's box (whose top left corner s.pos counts from) begins on it.

fn ap_box(p: vec2<f32>, c: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let q = abs(p - c) - half + vec2<f32>(r, r);
    return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn shade(s: Shader) -> vec4<f32> {
    let k = clamp(s.a.x, 0.0, 1.0);
    let half = max(vec2<f32>(s.a.w, s.b.x) * 0.5, vec2<f32>(1.0, 1.0));
    let c = vec2<f32>(s.a.y, s.a.z) + half;
    let r = clamp(s.b.y, 0.0, min(half.x, half.y));
    let p = s.pos + vec2<f32>(s.b.z, s.b.w);                                     // the screen's coordinates
    let sd = ap_box(p, c, half, r);
    let e = 0.75;
    var nrm = vec2<f32>(ap_box(p + vec2<f32>(e, 0.0), c, half, r) - ap_box(p - vec2<f32>(e, 0.0), c, half, r),
                        ap_box(p + vec2<f32>(0.0, e), c, half, r) - ap_box(p - vec2<f32>(0.0, e), c, half, r));
    let nl = length(nrm);
    if (nl > 0.0001) { nrm = nrm / nl; } else { nrm = vec2<f32>(0.0, 0.0); }
    // the lens: up to 14 px outward at the rim, nothing left by the 40 px the group is clipped to
    let t = max(sd, 0.0) / 16.0;                                                 // t * t, never pow of a negative
    let pic = inside(s, s.pos - nrm * 14.0 * k * exp(-(t * t)));
    // the lit rim: the phosphor's light, 1.6 px, just outside the hole
    let rim = (1.0 - min(abs(sd - 0.8) / 1.6, 1.0)) * k;
    let col = mix(pic.rgb, vec3<f32>(0.78, 0.86, 0.55), 0.8 * rim);
    // the hole itself is clear
    let hole = smoothstep(0.75, -0.75, sd) * step(0.001, k);
    return vec4<f32>(col, max(pic.a, rim) * (1.0 - hole));
}
