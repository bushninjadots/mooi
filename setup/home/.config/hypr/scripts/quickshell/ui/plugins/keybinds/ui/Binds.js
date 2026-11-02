// ═══════════════════════════════════════════════════════════════════════════
// Binds — pure helpers for the Keybinds editor (core ⇄ plugin separation).
//
// Ships with the keybinds plugin and is imported by KeybindsPage; kept
// dependency-free and side-effect-free so tests/binds.test.js can run it
// under plain node.
//
// Rules:
//   · The CORE owns its shortcuts (keybinds.lua): they are shown read-only
//     and a plugin override must never silently remove one — captures that
//     collide with a core bind are refused ("core default, not editable").
//   · PLUGINS own their own state: their binds come from the report
//     (plugins-report.json) and only they can be re-keyed or muted.
// ═══════════════════════════════════════════════════════════════════════════

var MOD_SHIFT = 1, MOD_CAPS = 2, MOD_CTRL = 4, MOD_ALT = 8,
    MOD_MOD2 = 16, MOD_MOD3 = 32, MOD_SUPER = 64, MOD_MOD5 = 128;

var MOD_ORDER = [
    [MOD_SUPER, "SUPER"], [MOD_CTRL, "CTRL"], [MOD_ALT, "ALT"],
    [MOD_SHIFT, "SHIFT"], [MOD_CAPS, "CAPS"],
    [MOD_MOD2, "MOD2"], [MOD_MOD3, "MOD3"], [MOD_MOD5, "MOD5"]
];

// Normalized comparison form: tokens lowercased + sorted ("shift+super+s").
// Case and order never matter when matching keys.
function normKey(s) {
    let parts = String(s || "").toLowerCase().split("+");
    let out = [];
    for (let i = 0; i < parts.length; i++) {
        let t = parts[i].trim();
        if (t !== "") out.push(t);
    }
    return out.sort().join("+");
}

// Display form for a modmask + key ("SUPER + SHIFT + S").
function displayKey(modmask, key) {
    let mods = [];
    for (let i = 0; i < MOD_ORDER.length; i++) {
        if (Number(modmask || 0) & MOD_ORDER[i][0]) mods.push(MOD_ORDER[i][1]);
    }
    let k = String(key || "");
    if (k.length === 1) k = k.toUpperCase();
    return mods.concat(k !== "" ? [k] : []).join(" + ");
}

// Normalized key of one `hyprctl binds -j` entry ("" when unusable/mouse).
function liveNorm(bind) {
    if (!bind || bind.mouse === true) return "";
    let k = String(bind.key || "");
    if (k === "") {
        if (Number(bind.keycode) > 0) return normKey(displayKey(bind.modmask, "keycode" + bind.keycode));
        return "";
    }
    return normKey(displayKey(bind.modmask, k));
}

// Short human summary of a bind's action (core binds carry no description;
// fall back to dispatcher + argument, trimmed).
function actionText(bind) {
    if (!bind) return "";
    let d = String(bind.description || "");
    if (d !== "") return d;
    let disp = String(bind.dispatcher || "");
    let arg = String(bind.arg || "").trim();
    let s = arg !== "" ? (disp + "  " + arg) : disp;
    if (s.length > 90) s = s.slice(0, 87) + "…";
    return s;
}

// Core binds = live binds that no ENABLED plugin claims. The report tells
// which live keys belong to plugins (their own state); everything else is
// the core's. Attribution walks the live list in REVERSE (plugin fragments
// load after the core, so on a duplicated key the plugin bind comes last)
// and drops as many entries as the report claims — that keeps a core bind
// visible even after a hand-edited override duplicated its key.
// Submap binds and mouse binds are excluded (they cannot collide with a
// global capture). `report` is the parsed plugins-report.json.
function coreBinds(liveBinds, report) {
    let claims = {};
    let entries = report || [];
    for (let i = 0; i < entries.length; i++) {
        let e = entries[i] || {};
        if (e.enabled !== true || e.bindsCached === true) continue; // plugin must be live
        let binds = e.binds || [];
        for (let j = 0; j < binds.length; j++) {
            let b = binds[j] || {};
            if (b.disabled === true) continue; // muted plugin binds claim nothing
            let n = normKey(b.key);
            if (n !== "") claims[n] = (claims[n] || 0) + 1;
        }
    }
    let out = [];
    let lives = liveBinds || [];
    for (let i = lives.length - 1; i >= 0; i--) {
        let lb = lives[i] || {};
        if (String(lb.submap || "") !== "") continue;
        let n = liveNorm(lb);
        if (n === "") continue;
        if (claims[n] > 0) { claims[n]--; continue; }  // attributed to a plugin
        out.push({
            norm: n,
            key: displayKey(lb.modmask, lb.key || ("keycode" + (lb.keycode || 0))),
            action: actionText(lb)
        });
    }
    out.reverse(); // live order for display
    return out;
}

// "" when the combo is free; the core bind's summary when it is taken.
function coreHit(combo, coreList) {
    let n = normKey(combo);
    if (n === "") return "";
    let list = coreList || [];
    for (let i = 0; i < list.length; i++) {
        if (list[i] && list[i].norm === n)
            return String(list[i].key + " — " + list[i].action);
    }
    return "";
}
