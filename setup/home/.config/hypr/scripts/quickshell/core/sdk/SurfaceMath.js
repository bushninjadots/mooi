.pragma library

// SurfaceMath — pure helpers for the surface manager (testable in isolation).

// Structural signature: any change forces the layer surface to be recreated
// (a PanelWindow's own anchors do not reliably re-apply on binding updates).
function structuralSig(spec) {
    spec = spec || {};
    return [
        spec.kind || "overlay",
        spec.edge || "",
        spec.layer || "top",
        spec.focus || "none",
        spec.contentMode || "fill",
        (spec.reserve === true ? "R" : "-"),
        Math.round(Number(spec.reserveThickness) || 0)
    ].join("~");
}

// Expand a spec's `screen` selector against the available screens.
function screensFor(spec, all) {
    all = all || [];
    var sel = spec.screen;
    if (sel === undefined || sel === null || sel === "all") return all;
    if (sel === "primary") return all.length ? [all[0]] : [];
    if (Array.isArray(sel)) return all.filter(function (s) { return sel.indexOf(s.name) !== -1; });
    return all.filter(function (s) { return String(s.name) === String(sel); });
}

// Derive a frame obstacle rect from a surface instance (edge + content box).
function deriveObstacle(inst) {
    var s = inst.spec || {};
    if (s.enabled === false) return null;
    if (typeof s.obstacle === "function") return s.obstacle(inst.screen, s);
    if (s.obstacle) { return s.obstacle; }
    return null; // no implicit derivation (plugins opt in with an explicit rect)
}
