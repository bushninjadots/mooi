// The Control Nexus field: the measured grid under the nodes, drawn in one pass instead of
// ninety lines. 36 px minor, 180 px major, a cross at every major intersection, and a soft
// lamp under the pointer that brings the grid up where the hand is. It reads no time, so it
// is painted only when something on the canvas changes or the pointer moves over it.
//
// values: a.x grid on (0/1) · a.y lamp strength (0 … 1) · a.z how lit the grid is (0 … 1)
// colors: color the minor rule (trace_dim) · color2 the major rule and the crosses (trace)

fn rule(p: f32, step: f32, width: f32) -> f32 {
    let d = abs(p - step * round(p / step));
    return 1.0 - smoothstep(0.0, width, d);
}

fn shade(s: Shader) -> vec4<f32> {
    let px = 1.0 / max(s.scale, 1.0);
    let p = s.pos;

    // the pointer's lamp, a wide soft pool
    let d = distance(p, s.pointer);
    let lamp = exp(-(d * d) / (2.0 * 150.0 * 150.0)) * s.a.y * s.hovered;

    var alpha = lamp * 0.035;
    var colour = s.color2.rgb;
    if (s.a.x > 0.5) {
        let minor = max(rule(p.x, 36.0, px), rule(p.y, 36.0, px));
        let major = max(rule(p.x, 180.0, px), rule(p.y, 180.0, px));
        let cx = abs(p.x - 180.0 * round(p.x / 180.0));
        let cy = abs(p.y - 180.0 * round(p.y / 180.0));
        let arm = select(0.0, 1.0, (cx < 5.0 && cy < px * 1.2) || (cy < 5.0 && cx < px * 1.2));
        let lit = 0.75 + s.a.z * 0.5;
        let g = max(minor * 0.09, major * 0.15) * lit * (1.0 + lamp * 3.0);
        colour = mix(s.color.rgb, s.color2.rgb, max(major, arm));
        alpha = max(alpha, g);
        alpha = max(alpha, arm * 0.5 * lit);
    }
    return vec4<f32>(colour, clamp(alpha, 0.0, 1.0));
}
