// Music in the picture (D223): strips of the wallpaper pulled up out of it by the music, in its own colours. A
// group shader over mooi's copy of the wallpaper (or, for the subject, its cut-out). Eight values:
//   a.x … b.y  sixteen bands, three bytes to a number (lib/surface/music `pack`), 0 … 255 each
//   b.z  kind · 1e6 + strength · 1e4 + size · 100 + blend (lib/surface/skin `pack`): 5 bars · 6 a colour · 7 the subject
//   b.w  the picked colour, 0xrrggbb (kind 6)
// Bars (5): the group's box is the place — an edge band or a drawn area; sixteen strips rise from its floor, each a
// slice of the picture just above the floor stretched up to its band's height, lit at its tip. Colour (6) and
// subject (7): over the whole screen, the picture's parts of that colour (or the subject) stretch up by the band of
// their column. Nothing else is drawn, so the still picture shows everywhere else.
fn byte(v: f32, k: i32) -> f32 {
    // k 0: the high byte · 1: the middle · 2: the low
    var x = v;
    if (k == 0) { return floor(x / 65536.0); }
    x = x - floor(x / 65536.0) * 65536.0;
    if (k == 1) { return floor(x / 256.0); }
    return x - floor(x / 256.0) * 256.0;
}

fn band(s: Shader, j: i32) -> f32 {
    let g = j / 3;
    let k = j - g * 3;
    var v = s.a.x;
    if (g == 1) { v = s.a.y; }
    if (g == 2) { v = s.a.z; }
    if (g == 3) { v = s.a.w; }
    if (g == 4) { v = s.b.x; }
    if (g == 5) { v = s.b.y; }
    return byte(v, k) / 255.0;
}

fn shade(s: Shader) -> vec4<f32> {
    let packed = s.b.z;
    let kind = floor(packed / 1000000.0);
    let rest = packed - kind * 1000000.0;
    let strength = floor(rest / 10000.0) / 99.0;
    let size = floor((rest - floor(rest / 10000.0) * 10000.0) / 100.0) / 99.0;
    let blend = (rest - floor(rest / 100.0) * 100.0) / 99.0;
    let box = max(s.size, vec2<f32>(1.0, 1.0));
    let warm = vec3<f32>(1.0, 0.94, 0.84);

    if (kind < 5.5) {
        // bars from the place's floor
        let bw = box.x / 16.0;
        let j = clamp(i32(floor(s.pos.x / bw)), 0, 15);
        let lvl = band(s, j) * strength;
        let h = max(lvl * box.y, 0.0);
        let up = box.y - s.pos.y;
        let fx = fract(s.pos.x / bw);
        let fill = 0.3 + 0.65 * size;
        let side = min(fx, fill - fx) * bw;
        if (fx > fill || up > h || h < 1.0) { return vec4<f32>(0.0); }
        let base = min(box.y * 0.12, 36.0);
        let src = vec2<f32>(s.pos.x, box.y - (up / h) * base);
        let pic = inside(s, src);
        let tip = smoothstep(4.0, 0.0, h - up);
        let col = clamp(pic.rgb * (1.0 + 0.25 * lvl) + warm * tip * 0.35, vec3<f32>(0.0), vec3<f32>(1.0));
        let soft = 1.0 + blend * 6.0;
        let a = smoothstep(0.0, soft, side) * smoothstep(0.0, soft, h - up + 1.0) * (1.0 - 0.4 * blend);
        return vec4<f32>(col, a * pic.a);
    }
    // a colour, or the subject: its parts stretch up by the band of their column
    let j = clamp(i32(floor(s.pos.x / box.x * 16.0)), 0, 15);
    let lvl = band(s, j) * strength;
    let reach = lvl * (30.0 + size * 160.0);
    // what is `d` below this pixel (d from 0 to the reach), stretched up to here
    var best = vec4<f32>(0.0);
    let want = vec3<f32>(floor(s.b.w / 65536.0), floor((s.b.w - floor(s.b.w / 65536.0) * 65536.0) / 256.0),
                         s.b.w - floor(s.b.w / 256.0) * 256.0) / 255.0;
    for (var i = 0; i < 6; i = i + 1) {
        let d = reach * f32(i) / 5.0;
        let src = inside(s, s.pos + vec2<f32>(0.0, d));
        var m = src.a;
        if (kind < 6.5) {
            m = smoothstep(0.32 - blend * 0.12, 0.12, distance(src.rgb, want)) * src.a;
        }
        if (m > best.a) {
            let lit = 1.0 + 0.3 * lvl * f32(i) / 5.0;
            best = vec4<f32>(clamp(src.rgb * lit, vec3<f32>(0.0), vec3<f32>(1.0)), m * (1.0 - 0.5 * blend * f32(i) / 5.0));
        }
    }
    if (reach < 1.0) { return vec4<f32>(0.0); }
    return best;
}
