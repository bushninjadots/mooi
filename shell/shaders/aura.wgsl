// Light through the skin (spec §9, §9a): a soft coloured glow at Music and at the Notices, inside the opening,
// under the hubs. Values: (open, hole x, hole y, music x, music y, notices x, notices y, amount). It reads time,
// so it breathes — but it is only drawn while the opening is open, and its group is hidden otherwise.
fn glow_at(uv: vec2<f32>, at: vec2<f32>, tight: f32) -> f32 {
    let d = distance(uv, at);
    return exp(-d * d * tight);
}

fn shade(s: Shader) -> vec4<f32> {
    let k = clamp(s.a.x, 0.0, 1.0);
    let size = max(s.size, vec2<f32>(1.0, 1.0));
    let uv = clamp(s.pos / size, vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 1.0));
    let origin = vec2<f32>(s.a.y, s.a.z);
    let music = (vec2<f32>(s.a.w, s.b.x) - origin) / size;
    let notices = (vec2<f32>(s.b.y, s.b.z) - origin) / size;
    let amount = clamp(s.b.w, 0.0, 3.0);
    let pulse = 0.86 + 0.14 * sin(s.time * 1.15);
    let g1 = glow_at(uv, music, 22.0) * amount * 0.34;
    let g2 = glow_at(uv, notices, 26.0) * amount * 0.24;
    let col = s.color.rgb * g1 * pulse + s.color2.rgb * g2 * pulse;
    return vec4<f32>(col, clamp(g1 + g2, 0.0, 1.0) * 0.7 * k);
}
