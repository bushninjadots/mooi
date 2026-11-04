// Lean: what a group holds, read back through a horizontal shear about the group's foot. The look
// slants inside its box and the box itself neither turns nor spills — what leans past an edge is
// simply not there, since `inside` answers transparent away from the drawing.
//
// values: a.x the lean in degrees, positive taking the top to the right (the italic way)

fn shade(s: Shader) -> vec4<f32> {
    let k = tan(clamp(s.a.x, -70.0, 70.0) * 0.0174532925);
    let at = vec2<f32>(s.pos.x - k * (s.size.y - s.pos.y), s.pos.y);
    return inside(s, at);
}
