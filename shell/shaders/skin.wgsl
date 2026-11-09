// Live wallpaper (D219; D217's moving wallpaper grown into its own feature): the real picture under a patch round
// a widget below — or the whole screen — bent and lit. A group shader over mooi's copy of the wallpaper, fitted as
// the wallpaper is; `inside` reads it. Eight values:
//   a.x  speed % (whole part) + amount (fraction): the music's level, or where the sweep's band is (0 … 1)
//   a.y, a.z  the patch's screen origin (a group's shader sees its own box from its top left corner)
//   a.w, b.x, b.y, b.z  the widget's box (the whole picture: the screen)
//   b.w  kind · 1e6 + strength · 1e4 + size · 100 + blend (each 0 … 99; lib/surface/skin `pack`)
// Kinds: 1 ripple · 2 breathe · 3 flow · 4 sweep. It draws only where the picture moves or is lit, feathered to the
// patch's edge by the blend, so a picture fitted a pixel apart from the wallpaper's own never shows a seam.
fn lw_box(p: vec2<f32>, c: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let q = abs(p - c) - half + vec2<f32>(r, r);
    return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn shade(s: Shader) -> vec4<f32> {
    let speed = floor(s.a.x) / 100.0;
    let amount = clamp(fract(s.a.x), 0.0, 1.0);
    let origin = vec2<f32>(s.a.y, s.a.z);
    let half = max(vec2<f32>(s.b.y, s.b.z) * 0.5, vec2<f32>(1.0, 1.0));
    let c = vec2<f32>(s.a.w, s.b.x) + half;
    let packed = s.b.w;
    let kind = floor(packed / 1000000.0);
    let rest = packed - kind * 1000000.0;
    let strength = floor(rest / 10000.0) / 99.0;
    let size = floor((rest - floor(rest / 10000.0) * 10000.0) / 100.0) / 99.0;
    let blend = (rest - floor(rest / 100.0) * 100.0) / 99.0;
    let p = s.pos + origin;
    let t = s.time * speed;
    let box = max(s.size, vec2<f32>(1.0, 1.0));
    // the whole picture: the widget's box is the patch itself
    let whole = box.x <= half.x * 2.0 + 1.0 && box.y <= half.y * 2.0 + 1.0;
    // feathered to the patch's edge: crisp at blend 0, soft and wide at 1
    let to_edge = min(min(s.pos.x, s.pos.y), min(box.x - s.pos.x, box.y - s.pos.y));
    let feather = 4.0 + blend * 0.45 * min(box.x, box.y) * select(0.5, 0.25, whole);
    let edge = smoothstep(0.0, feather, to_edge);
    let reach = 20.0 + size * 280.0;
    let sd = lw_box(p, c, half, 18.0);

    if (kind < 1.5) {
        // Ripple: rings run out with the music (whole: from the middle of the screen)
        var d = max(sd, 0.0);
        let dir = normalize(p - c + vec2<f32>(0.001, 0.001));
        if (whole) { d = length(p - c); }
        let wavelength = 14.0 + size * 70.0;
        let wave = sin(d / wavelength * 6.2832 - t * 3.0);
        var fade = exp(-d / reach) * step(0.0, sd);
        if (whole) { fade = 1.0; }
        let push = strength * (1.0 + 9.0 * amount) * wave * fade;
        let pic = inside(s, p - dir * push - origin);
        let lit = 1.0 + 0.07 * wave * fade * amount * strength;
        let alpha = clamp(abs(push) * (1.0 - 0.6 * blend), 0.0, 1.0) * edge * pic.a;
        return vec4<f32>(clamp(pic.rgb * lit, vec3<f32>(0.0), vec3<f32>(1.0)), alpha);
    }
    if (kind < 2.5) {
        // Breathe: the picture swells toward the eye and settles with the music's level
        var r = (half + vec2<f32>(reach, reach)) * (0.6 + 0.8 * size);
        if (whole) { r = half * (0.5 + 0.9 * size); }
        let q = (p - c) / r;
        let bump = exp(-dot(q, q) * 2.0);
        let swell = strength * amount * bump;
        let pic = inside(s, c + (p - c) * (1.0 - 0.07 * swell) - origin);
        let alpha = smoothstep(0.0, 0.02 + blend * 0.25, swell) * edge * pic.a;
        return vec4<f32>(clamp(pic.rgb * (1.0 + 0.08 * swell), vec3<f32>(0.0), vec3<f32>(1.0)), alpha);
    }
    if (kind < 3.5) {
        // Flow: a slow drift, two waves over each other, alive with no music
        let sc = 60.0 + size * 340.0;
        let off = vec2<f32>(sin(p.y / sc + t * 0.55) + 0.5 * sin((p.x + p.y) / (sc * 0.7) - t * 0.35),
                            cos(p.x / sc * 0.9 - t * 0.45) + 0.5 * cos((p.x - p.y) / (sc * 0.8) + t * 0.3));
        let push = off * strength * 7.0;
        var near = 1.0;
        if (!whole) { near = exp(-max(sd, 0.0) / reach); }
        let pic = inside(s, p + push - origin);
        let alpha = near * edge * (1.0 - 0.5 * blend) * smoothstep(0.0, 0.5, length(push)) * pic.a;
        return vec4<f32>(pic.rgb, alpha);
    }
    // Light sweep: a soft diagonal band crosses the place (the amount is where it is), warm light over the picture
    let width = 24.0 + size * 160.0;
    let span = half.x * 2.0 + half.y + width * 4.0;
    let along = (p.x - (c.x - half.x - width * 2.0)) + (p.y - (c.y - half.y)) * 0.5;
    let band = exp(-pow((along - amount * span) / width, 2.0)) * strength;
    let pic = inside(s, s.pos);
    let col = clamp(pic.rgb + vec3<f32>(1.0, 0.92, 0.78) * band * 0.35, vec3<f32>(0.0), vec3<f32>(1.0));
    return vec4<f32>(col, smoothstep(0.0, 0.03 + blend * 0.2, band) * edge * pic.a);
}
