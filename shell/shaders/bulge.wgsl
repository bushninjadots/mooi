// Push up from below (spec §9, D217): a soft bulge in the wallpaper over a widget below, as news presses up. A group
// shader over the real wallpaper in a patch round the widget's place; `inside` is the picture, fitted. The eight
// values are (rise, patch x, patch y, box x, box y, box w, box h, strength): the patch's screen origin first, as
// a group's shader sees its own box from its top left corner. Outside the bulge it draws nothing, so a picture
// fitted a pixel apart from the wallpaper's own never shows a seam.
fn shade(s: Shader) -> vec4<f32> {
    let k = clamp(s.a.x, 0.0, 1.0);
    let origin = vec2<f32>(s.a.y, s.a.z);
    let half = max(vec2<f32>(s.b.y, s.b.z) * 0.5, vec2<f32>(1.0, 1.0));
    let c = vec2<f32>(s.a.w, s.b.x) + half;
    let strength = clamp(s.b.w, 0.0, 2.0);
    let p = s.pos + origin;
    // an ellipse a little wider than the widget, highest in its middle
    let q = (p - c) / (half + vec2<f32>(36.0, 36.0));
    let d2 = dot(q, q);
    let bump = exp(-d2 * 3.2) * k * strength;
    // the picture swells toward the eye: sampled nearer the middle, as through a lens
    let pull = 1.0 - 0.10 * bump;
    let pic = inside(s, c + (p - c) * pull - origin);
    // lit from the top left, shaded below right
    let dir = normalize(p - c + vec2<f32>(0.001, 0.001));
    let lit = dot(dir, vec2<f32>(-0.7071, -0.7071)) * bump * 0.16 + bump * 0.05;
    let col = clamp(pic.rgb * (1.0 + lit), vec3<f32>(0.0), vec3<f32>(1.0));
    // faded out well inside the patch: its clip's edge is never seen
    let alpha = smoothstep(0.03, 0.22, bump) * pic.a;
    return vec4<f32>(col, alpha);
}
