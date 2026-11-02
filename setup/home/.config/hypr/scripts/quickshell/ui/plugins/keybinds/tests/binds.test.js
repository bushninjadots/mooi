#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════
// binds.test.js — local test for ../ui/Binds.js (run: node tests/binds.test.js).
// No CI, no deps: loads the JS module in a vm context and asserts the pure
// matching/attribution rules (core ⇄ plugin separation).
// ═══════════════════════════════════════════════════════════════════════════
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const src = fs.readFileSync(path.join(__dirname, "..", "ui", "Binds.js"), "utf8");
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(src, ctx);
const B = ctx;

let errors = 0;
function ok(cond, msg) {
    if (!cond) { errors++; console.error("FAIL: " + msg); }
}

// ── normKey / displayKey ────────────────────────────────────────────────────
ok(B.normKey("SUPER + SHIFT + S") === B.normKey("shift+super+s"), "norm ignores case/order");
ok(B.normKey("  SUPER ++ S ") === "s+super", "norm drops empty tokens");
ok(B.displayKey(65, "s") === "SUPER + SHIFT + S", "display from modmask");
ok(B.displayKey(68, "s") === "SUPER + CTRL + S", "display multi-mod");
ok(B.displayKey(0, "Print") === "Print", "display plain key");
ok(B.normKey(B.displayKey(65, "s")) === B.normKey("SUPER + SHIFT + S"), "display→norm roundtrip");

// ── liveNorm ────────────────────────────────────────────────────────────────
ok(B.liveNorm({ modmask: 65, key: "s" }) === B.normKey("SUPER + SHIFT + S"), "liveNorm keybind");
ok(B.liveNorm({ modmask: 64, key: "", keycode: 114 }) === "keycode114+super", "liveNorm keycode-only");
ok(B.liveNorm({ modmask: 64, key: "q", mouse: true }) === "", "mouse binds excluded");
ok(B.liveNorm(null) === "", "null-safe");

// ── coreBinds: attribution ──────────────────────────────────────────────────
const live = [
    { modmask: 65, key: "s", dispatcher: "exec", arg: "qs_manager.sh toggle bar-editor" }, // core (settings)
    { modmask: 65, key: "x", dispatcher: "exec", arg: "xturing" },                          // core (xturing)
    { modmask: 64, key: "q", dispatcher: "killactive" },                                    // claimed by plugin
    { modmask: 64, key: "v", dispatcher: "exec", arg: "volume" },                           // core
    { modmask: 64, key: "b", dispatcher: "exec", arg: "sub", submap: "resize" },            // submap: excluded
    { modmask: 64, key: "q", mouse: true, dispatcher: "movewindow" }                        // mouse: excluded
];
const reportLive = [
    { id: "p1", enabled: true, binds: [{ id: "b1", key: "SUPER + Q", defaultKey: "SUPER + Q" }] }
];
let core = B.coreBinds(live, reportLive);
ok(core.length === 3, "core = live minus plugin-claimed minus submap minus mouse");
ok(!core.some(c => c.norm === B.normKey("SUPER + Q")), "claimed key not in core list");
ok(core.some(c => c.key === "SUPER + SHIFT + S"), "core keeps SUPER + SHIFT + S");
ok(core.every(c => String(c.action).length > 0), "every core bind carries an action summary");

// duplicated key: a plugin override took a core key → the CORE bind stays
// visible (attribution drops the LAST entry: plugins load after the core)
const liveDup = [
    { modmask: 65, key: "s", dispatcher: "exec", arg: "qs_manager.sh toggle bar-editor" }, // core first
    { modmask: 65, key: "s", dispatcher: "exec", arg: "clipboard toggle (override)" }       // plugin last
];
const reportDup = [
    { id: "clipboard", enabled: true, binds: [{ id: "b1", key: "SUPER + SHIFT + S" }] }
];
core = B.coreBinds(liveDup, reportDup);
ok(core.length === 1, "duplicated key keeps exactly the core entry");
ok(core[0].action.indexOf("qs_manager") !== -1, "kept entry is the core one (first in live order)");
ok(B.coreHit("SUPER + SHIFT + S", core) !== "", "hand-edited collision is still flagged");

// muted plugin bind claims nothing: the core bind on that key reappears
const reportMuted = [
    { id: "p1", enabled: true, binds: [{ id: "b1", key: "", defaultKey: "SUPER + Q", disabled: true }] }
];
core = B.coreBinds(live, reportMuted);
ok(core.some(c => c.norm === B.normKey("SUPER + Q")), "muted plugin bind claims nothing");

// disabled plugin (cached binds) claims nothing either
const reportDisabled = [
    { id: "p1", enabled: false, bindsCached: true, binds: [{ id: "b1", key: "SUPER + Q" }] }
];
core = B.coreBinds(live, reportDisabled);
ok(core.some(c => c.norm === B.normKey("SUPER + Q")), "cached binds of a disabled plugin claim nothing");

// ── coreHit: the refusal rule ───────────────────────────────────────────────
const list = B.coreBinds(live, reportLive);
ok(B.coreHit("SUPER + SHIFT + S", list) !== "", "core hit detected (settings)");
ok(B.coreHit("super+shift+s", list) !== "", "core hit is case/order insensitive");
ok(B.coreHit("SUPER + SHIFT + X", list) !== "", "core hit detected (xturing)");
ok(B.coreHit("CTRL + 9", list) === "", "free combo passes");
ok(B.coreHit("SUPER + Q", list) === "", "plugin-claimed key is not a core hit");

if (errors === 0) console.log("binds.js: ok");
else process.exit(1);
