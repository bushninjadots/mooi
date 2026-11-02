// ═══════════════════════════════════════════════════════════════════════════
// FrameGeometry.js — geometría pura del marco de pantalla (settings.json "frame").
//
// El marco es un borde que recorre los cuatro extremos del monitor, dibujado en
// la capa Bottom (por detrás de la barra, islas y ventanas) y con reserva de
// espacio por lado para que las ventanas nunca lo crucen (como la barra). Donde
// la barra, un overlay de host o un panel/launcher anclado a un borde tocan el
// marco, la línea se "hunde" y lo abraza con esquinas redondeadas (muesca).
//
// Todo aquí es puro (sin tipos QML) y testeable con node:
//   defaults()                          → configuración por defecto
//   normalize(raw)                      → clamps + keys desconocidas ignoradas
//   buildPath(w, h, cfg, obstacles)     → path SVG del borde con muescas
//   reserveEdges(cfg, barPosition)      → lados que deben reservar espacio
//
// Obstáculos (screen coords). a/b = rango a lo largo del borde; depth = coord
// de pantalla del borde INTERIOR del obstáculo (y para top/bottom, x para
// left/right). a<=0 y b>=tamaño ⇒ el obstáculo abarca todo el lado y desplaza
// la base del borde en vez de crear una muesca parcial.
//   { edge: "top"|"bottom"|"left"|"right", a, b, depth }
// ═══════════════════════════════════════════════════════════════════════════
.pragma library

var ROLES = ["overlay0", "overlay1", "overlay2", "surface0", "surface1", "surface2",
             "background", "base", "mantle", "crust", "foreground",
             "text", "subtext0", "mauve", "blue", "green", "red", "yellow",
             "peach", "teal", "sapphire", "pink", "maroon"];
var LAYERS = ["bottom", "background"];
var EDGES = ["top", "bottom", "left", "right"];

function defaults() {
    return {
        enabled: false,
        thickness: 4,     // band width on top/bottom in design px
        sideThickness: 4, // band width on left/right (defaults to thickness)
        radius: 18,       // screen corner radius
        inset: 0,         // outer edge of the frame from the screen edge (0 = flush)
        gap: 6,           // extra gap between the frame and an obstacle
        color: "overlay0",// palette role or "#rrggbb"
        alpha: 0.5,       // border alpha
        line: true,       // draw the inner border line (the one that hugs)
        lineWidth: 2,     // inner line stroke width
        fill: false,      // fill the border band (solid frame) instead of a hairline
        fillColor: "overlay0",
        fillAlpha: 0.12,
        reserve: true,    // reserve space so windows never cross the frame
        reserveExtra: 0,  // extra reserved px on top of inset + thickness
        notchRadius: 12,  // corner radius of the detours (muescas)
        notchBar: true,   // hug the bar
        notchWidget: true,// carve around the active widget (launcher/panels)
        notchHosts: true, // carve around host overlays (plugin host adapters)
        widgetReach: 140, // how far (design px) a widget may sit and still notch
        layer: "bottom"
    };
}

function _clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }

function _num(v, def) { v = Number(v); return isFinite(v) ? v : def; }

function normalize(raw) {
    var d = defaults();
    if (!raw || typeof raw !== "object") return d;

    var color = d.color;
    if (typeof raw.color === "string" && raw.color !== "") {
        if (ROLES.indexOf(raw.color) !== -1 || raw.color.charAt(0) === "#") color = raw.color;
    }
    var fillColor = d.fillColor;
    if (typeof raw.fillColor === "string" && raw.fillColor !== "") {
        if (ROLES.indexOf(raw.fillColor) !== -1 || raw.fillColor.charAt(0) === "#") fillColor = raw.fillColor;
    }

    return {
        enabled: typeof raw.enabled === "boolean" ? raw.enabled : d.enabled,
        thickness: _clamp(Math.round(_num(raw.thickness, d.thickness)), 0, 80),
        sideThickness: _clamp(Math.round(_num(raw.sideThickness, _num(raw.thickness, d.thickness))), 0, 120),
        radius: _clamp(Math.round(_num(raw.radius, d.radius)), 0, 120),
        inset: _clamp(Math.round(_num(raw.inset, d.inset)), -80, 400),
        gap: _clamp(Math.round(_num(raw.gap, d.gap)), 0, 120),
        color: color,
        alpha: _clamp(_num(raw.alpha, d.alpha), 0, 1),
        line: typeof raw.line === "boolean" ? raw.line : d.line,
        lineWidth: _clamp(Math.round(_num(raw.lineWidth, d.lineWidth)), 0, 20),
        fill: typeof raw.fill === "boolean" ? raw.fill : d.fill,
        fillColor: fillColor,
        fillAlpha: _clamp(_num(raw.fillAlpha, d.fillAlpha), 0, 1),
        reserve: typeof raw.reserve === "boolean" ? raw.reserve : d.reserve,
        reserveExtra: _clamp(Math.round(_num(raw.reserveExtra, d.reserveExtra)), 0, 200),
        notchRadius: _clamp(Math.round(_num(raw.notchRadius, d.notchRadius)), 0, 60),
        notchBar: typeof raw.notchBar === "boolean" ? raw.notchBar : d.notchBar,
        notchWidget: typeof raw.notchWidget === "boolean" ? raw.notchWidget : d.notchWidget,
        // Legacy key `notchMascot` (pre host-adapter era) still reads.
        notchHosts: typeof raw.notchHosts === "boolean" ? raw.notchHosts
                    : (typeof raw.notchMascot === "boolean" ? raw.notchMascot : d.notchHosts),
        widgetReach: _clamp(Math.round(_num(raw.widgetReach, d.widgetReach)), 0, 600),
        layer: LAYERS.indexOf(String(raw.layer)) !== -1 ? String(raw.layer) : d.layer
    };
}

// ── Reserva de espacio ────────────────────────────────────────────────────
// Un lado no debe reservar si ya lo ocupa otro elemento (la barra, un overlay
// de host): los edges de skip se omiten para no empujar su capa.
function reserveEdges(cfg, skipEdges) {
    if (!cfg || cfg.reserve === false) return [];
    skipEdges = skipEdges || [];
    var out = [];
    for (var i = 0; i < EDGES.length; i++) {
        var e = EDGES[i];
        if (skipEdges.indexOf(e) !== -1) continue;
        out.push(e);
    }
    return out;
}

// Grosor (px) que cada strut reserva desde su borde.
function reservePx(cfg) {
    if (!cfg) return 0;
    var t = Math.max(cfg.thickness, (cfg.sideThickness !== undefined ? cfg.sideThickness : cfg.thickness));
    return Math.max(0, Math.round(cfg.inset + t + cfg.reserveExtra));
}

function _fmt(n) { return (Math.round(n * 100) / 100).toString(); }

// ── Constructor del path ──────────────────────────────────────────────────
// Devuelve una cadena SVG (con arcos "A") o "" si el marco no es dibujable.
function buildPath(w, h, cfg, obstacles) {
    w = Number(w) || 0;
    h = Number(h) || 0;
    if (w <= 0 || h <= 0 || !cfg) return "";

    var R = cfg.radius, gap = cfg.gap;
    var rr = Math.max(1, cfg.notchRadius);

    // Bases por lado (distancia del borde). Admite inset por lado
    // (insetTop/Bottom/Left/Right) para grosores asimétricos; si no, `inset`.
    var iT = cfg.insetTop !== undefined ? cfg.insetTop : cfg.inset;
    var iB = cfg.insetBottom !== undefined ? cfg.insetBottom : cfg.inset;
    var iL = cfg.insetLeft !== undefined ? cfg.insetLeft : cfg.inset;
    var iR = cfg.insetRight !== undefined ? cfg.insetRight : cfg.inset;
    // Un obstáculo que abarca todo el lado desplaza la base; uno parcial se
    // convierte en muesca.
    var base = { top: iT, bottom: iB, left: iL, right: iR };
    var list = { top: [], bottom: [], left: [], right: [] };

    obstacles = obstacles || [];
    for (var i = 0; i < obstacles.length; i++) {
        var o = obstacles[i];
        if (!o || !o.edge) continue;
        var e = o.edge;
        var full = (e === "top" || e === "bottom") ? (o.a <= 0 && o.b >= w)
                                                   : (o.a <= 0 && o.b >= h);
        var D;
        if (e === "top")         D = o.depth + gap;
        else if (e === "bottom") D = (h - o.depth) + gap;
        else if (e === "left")   D = o.depth + gap;
        else if (e === "right")  D = (w - o.depth) + gap;
        else continue;

        if (full) { if (D > base[e]) base[e] = D; }
        else list[e].push({ a: o.a, b: o.b, D: D });
    }

    var xL = base.left, xR = w - base.right, yT = base.top, yB = h - base.bottom;
    var Lh = (xR - R) - (xL + R);   // horizontal edge length (top/bottom)
    var Lv = (yB - R) - (yT + R);   // vertical edge length (right/left)
    if (Lh < 4 || Lv < 4) return "";

    // u-space origins per edge (see header): convert each partial obstacle to
    // { u1, u2, D }.
    var topI = [];
    for (i = 0; i < list.top.length; i++) {
        var it = list.top[i];
        topI.push({ u1: it.a - (xL + R), u2: it.b - (xL + R), D: it.D });
    }
    var rightI = [];
    for (i = 0; i < list.right.length; i++) {
        it = list.right[i];
        rightI.push({ u1: it.a - (yT + R), u2: it.b - (yT + R), D: it.D });
    }
    var bottomI = [];
    for (i = 0; i < list.bottom.length; i++) {
        it = list.bottom[i];
        bottomI.push({ u1: (xR - R) - it.b, u2: (xR - R) - it.a, D: it.D });
    }
    var leftI = [];
    for (i = 0; i < list.left.length; i++) {
        it = list.left[i];
        leftI.push({ u1: (yB - R) - it.b, u2: (yB - R) - it.a, D: it.D });
    }

    function P(x, y) { return _fmt(x) + " " + _fmt(y); }

    function edgePath(L, B, ints, toXY) {
        var cmds = [];
        ints.sort(function (p, q) { return p.u1 - q.u1; });
        var cur = 0;
        for (var j = 0; j < ints.length; j++) {
            var a = Math.max(ints[j].u1, rr);
            var b = Math.min(ints[j].u2, L - rr);
            var D = ints[j].D;
            if (D <= B + 0.5) continue;
            if (D < B + 2 * rr) continue;
            if (b - a < 2 * rr) continue;
            if (a < cur) continue; // overlapping a previous notch: skip
            function pt(u, d) { var p = toXY(u, d); return P(p.x, p.y); }
            cmds.push("L " + pt(Math.max(cur, a - rr), B));
            cmds.push("A " + rr + " " + rr + " 0 0 1 " + pt(a, B + rr));
            cmds.push("L " + pt(a, D - rr));
            cmds.push("A " + rr + " " + rr + " 0 0 0 " + pt(a + rr, D));
            cmds.push("L " + pt(b - rr, D));
            cmds.push("A " + rr + " " + rr + " 0 0 0 " + pt(b, D - rr));
            cmds.push("L " + pt(b, B + rr));
            cmds.push("A " + rr + " " + rr + " 0 0 1 " + pt(b + rr, B));
            cur = b + rr;
        }
        if (cur < L) {
            var pe = toXY(L, B);
            cmds.push("L " + P(pe.x, pe.y));
        }
        return cmds;
    }

    // Edge coordinate maps (u along the edge, d = cross distance):
    //   top:    (u,d) -> (xL+R+u, d)
    //   right:  (u,d) -> (d, yT+R+u)
    //   bottom: (u,d) -> (xR-R-u, d)   [d is screen y]
    //   left:   (u,d) -> (d, yB-R-u)   [d is screen x]
    function topXY(u, d)    { return { x: xL + R + u, y: d }; }
    function rightXY(u, d)  { return { x: d, y: yT + R + u }; }
    function bottomXY(u, d) { return { x: xR - R - u, y: d }; }
    function leftXY(u, d)   { return { x: d, y: yB - R - u }; }

    var d = [];
    d.push("M " + P(xL + R, yT));
    d = d.concat(edgePath(Lh, yT, topI, topXY));
    d.push("A " + R + " " + R + " 0 0 1 " + P(xR, yT + R));            // TR
    d = d.concat(edgePath(Lv, xR, rightI, rightXY));
    d.push("A " + R + " " + R + " 0 0 1 " + P(xR - R, yB));            // BR
    d = d.concat(edgePath(Lh, yB, bottomI, bottomXY));
    d.push("A " + R + " " + R + " 0 0 1 " + P(xL, yB - R));            // BL
    d = d.concat(edgePath(Lv, xL, leftI, leftXY));
    d.push("A " + R + " " + R + " 0 0 1 " + P(xL + R, yT));            // TL
    d.push("Z");
    return d.join(" ");
}

// Contorno interior (el que abraza): inset + grosor por lado + obstáculos. Los
// obstáculos ya vienen en profundidad absoluta (coord. de pantalla), así que
// no se desplazan: A > base activa la muesca.
function buildInnerPath(w, h, cfg, obstacles) {
    var inner = {};
    for (var k in cfg) inner[k] = cfg[k];
    var tb = cfg.thickness;
    var lr = (cfg.sideThickness !== undefined) ? cfg.sideThickness : cfg.thickness;
    var o = cfg.inset;
    inner.insetTop = o + tb;
    inner.insetBottom = o + tb;
    inner.insetLeft = o + lr;
    inner.insetRight = o + lr;
    return buildPath(w, h, inner, obstacles);
}

// Banda rellena: even-odd con el exterior limpio y el interior que abraza.
function buildBandPath(w, h, cfg, obstacles) {
    var outer = buildPath(w, h, cfg, []);            // clean, no notches
    var inner = buildInnerPath(w, h, cfg, obstacles);
    if (outer === "") return inner;
    if (inner === "") return outer;
    return outer + " " + inner;
}

// ── Presets ───────────────────────────────────────────────────────────────
// Ready-made looks (visual keys only). Apply by merging over the current
// config, so enabled/reserve/notch*/layer are preserved. Colors are palette
// roles, so presets follow the active theme.
function presets() {
    return [
        { id: "x", label: "x", icon: "✕",
          cfg: { enabled: true, thickness: 25, sideThickness: 43, radius: 15, inset: -4,
                 gap: 4, notchRadius: 7, color: "blue", alpha: 0.1, line: true, lineWidth: 10,
                 fill: true, fillColor: "surface0", fillAlpha: 1, reserve: false, reserveExtra: 15,
                 notchBar: true, notchWidget: true, notchHosts: true, layer: "bottom" } },
        { id: "minimal", label: "Minimal", icon: "󰅁",
          cfg: { thickness: 8, sideThickness: 8, radius: 24, inset: 6, gap: 6, notchRadius: 12,
                 color: "surface1", alpha: 0.85, line: true, lineWidth: 1, fill: false } },
        { id: "soft", label: "Soft bezel", icon: "󰝴",
          cfg: { thickness: 14, sideThickness: 14, radius: 28, inset: 0, gap: 6, notchRadius: 12,
                 color: "surface1", alpha: 0.9, line: true, lineWidth: 1,
                 fill: true, fillColor: "surface0", fillAlpha: 0.35 } },
        { id: "bold", label: "Bold bezel", icon: "󰆣",
          cfg: { thickness: 26, sideThickness: 26, radius: 34, inset: 0, gap: 8, notchRadius: 16,
                 color: "surface1", alpha: 1, line: false, lineWidth: 2,
                 fill: true, fillColor: "surface1", fillAlpha: 0.7 } },
        { id: "neon", label: "Neon", icon: "󰐊",
          cfg: { thickness: 8, sideThickness: 8, radius: 30, inset: 10, gap: 6, notchRadius: 12,
                 color: "mauve", alpha: 1, line: true, lineWidth: 2, fill: false } },
        { id: "hollow", label: "Hollow", icon: "󰘣",
          cfg: { thickness: 10, sideThickness: 10, radius: 40, inset: 20, gap: 8, notchRadius: 18,
                 color: "overlay2", alpha: 0.8, line: true, lineWidth: 2, fill: false } },
        { id: "wrap", label: "Wrapping", icon: "󰜰",
          cfg: { thickness: 30, sideThickness: 30, radius: 30, inset: 0, gap: 12, notchRadius: 18,
                 color: "subtext0", alpha: 1, line: true, lineWidth: 3,
                 fill: true, fillColor: "base", fillAlpha: 0.55 } },
        { id: "glow", label: "Glow", icon: "✦",
          cfg: { thickness: 18, sideThickness: 18, radius: 30, inset: 0, gap: 8, notchRadius: 14,
                 color: "mauve", alpha: 0.9, line: true, lineWidth: 2,
                 fill: true, fillColor: "mauve", fillAlpha: 0.18 } },
        { id: "frost", label: "Frost", icon: "󰖌",
          cfg: { thickness: 16, sideThickness: 16, radius: 28, inset: 0, gap: 6, notchRadius: 12,
                 color: "overlay2", alpha: 0.7, line: true, lineWidth: 1,
                 fill: true, fillColor: "surface1", fillAlpha: 0.22 } },
        { id: "wide", label: "Wide sides", icon: "󰧷",
          cfg: { thickness: 8, sideThickness: 30, radius: 26, inset: 0, gap: 8, notchRadius: 14,
                 color: "surface1", alpha: 0.9, line: true, lineWidth: 1,
                 fill: true, fillColor: "surface0", fillAlpha: 0.45 } },
        { id: "edges", label: "Wide top/bot", icon: "󰅀",
          cfg: { thickness: 30, sideThickness: 8, radius: 26, inset: 0, gap: 8, notchRadius: 14,
                 color: "surface1", alpha: 0.9, line: true, lineWidth: 1,
                 fill: true, fillColor: "surface0", fillAlpha: 0.45 } }
    ];
}
