.pragma library
// ═══════════════════════════════════════════════════════════════════════════
// shell · core — Notifications
//
// Personalization API for the notification popups: pure helpers that
// normalize the "notifications" settings section and produce the scaled
// layout. The UI consumes it; nothing here touches QML objects.
// ═══════════════════════════════════════════════════════════════════════════
var DEFAULTS = {
    width: 350,       // popup width (unscaled)
    maxHeight: 0,     // 0 = auto; otherwise max popup card height (unscaled)
    marginTop: 60,
    marginRight: 20,
    position: 2,      // 0 tl, 1 tc, 2 tr, 3 bl, 4 bc, 5 br
    shadow: 0,        // 0/1 like hyprland window shadow
    shadowBlur: 14,
    shadowOffset: 6,
    spacing: 12,
    radius: 14,
    padding: 12,
    timeout: 5000,    // ms for notifications without an explicit timeout (0 = never)
    maxVisible: 3     // how many popups stay on screen (0 = no limit)
};

// Normalized section: every known option with a valid value (defaults fill in).
function normalize(raw) {
    let out = {};
    let src = (raw && typeof raw === "object" && !Array.isArray(raw)) ? raw : {};
    for (let key in DEFAULTS) {
        let v = src[key];
        out[key] = (typeof v === "number" && v >= 0) ? v : DEFAULTS[key];
    }
    return out;
}

// Scaled layout for the popup window (scale comes from core/WindowRegistry).
function layout(raw, scale) {
    let o = normalize(raw);
    return {
        w: Math.round(o.width * scale),
        marginTop: Math.round(o.marginTop * scale),
        marginRight: Math.round(o.marginRight * scale),
        maxHeight: Math.round(o.maxHeight * scale),
        posTop: o.position === 0 || o.position === 1 || o.position === 2,
        posBottom: o.position === 3 || o.position === 4 || o.position === 5,
        posLeft: o.position === 0 || o.position === 3,
        posCenterX: o.position === 1 || o.position === 4,
        posRight: o.position === 2 || o.position === 5,
        shadow: o.shadow === 1,
        shadowBlur: Math.round(o.shadowBlur * scale),
        shadowOffset: Math.round(o.shadowOffset * scale),
        spacing: Math.round(o.spacing * scale),
        radius: Math.round(o.radius * scale),
        padding: Math.round(o.padding * scale)
    };
}

function defaultTimeout(raw) {
    return normalize(raw).timeout;
}

function maxVisible(raw) {
    return normalize(raw).maxVisible;
}

// New section with one option changed (for the editor / API users).
function setOption(raw, key, value) {
    let out = normalize(raw);
    if (DEFAULTS.hasOwnProperty(key)) out[key] = value;
    return out;
}
