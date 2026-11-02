pragma Singleton
import QtQuick
import Quickshell
import "SurfaceMath.js" as SMath

// ═══════════════════════════════════════════════════════════════════════════
// Surfaces — the shell-side surface registry + reservation arbiter.
//
// Plugins declare *descriptors* (plain objects); the shell materialises them
// (ui/surfaces/SurfaceHost.qml). This centralises the Quickshell pitfalls:
// panel-anchor recreation, input masks, exclusiveZone, and per-screen Variants.
//
// A descriptor:
//   { id, kind:"overlay"|"reserve", screen:"all"|"primary"|name|[names],
//     edge:"top"|"bottom"|"left"|"right", layer, focus, contentMode,
//     reserve, reserveThickness, visible, box, input, maskItems,
//     content:Component, props:{} , obstacle:{...}|fn }
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    property var owners: ({})       // ownerId -> { specs, source }
    property var instances: []      // flattened { key, owner, screen, spec, sig }
    property var obstacles: []      // rects derived from instances (the shell publishes them)
    property var conflicts: []      // reserve collisions (informational)

    function _key(owner, id, screenName) { return owner + "|" + id + "|" + screenName; }

    function register(owner, specs, source) {
        root.owners[owner] = { specs: specs || [], source: source || null };
        root.rebuild();
    }
    function update(owner, specs) {
        if (!root.owners[owner]) return;
        root.owners[owner].specs = specs || [];
        root.rebuild();
    }
    function unregister(owner) {
        if (!root.owners[owner]) return;
        delete root.owners[owner];
        root.rebuild();
    }

    function rebuild() {
        var all = Quickshell.screens || [];
        var out = [], res = {}, conflicts = [];
        var keys = Object.keys(root.owners);
        for (var oi = 0; oi < keys.length; oi++) {
            var owner = keys[oi], specs = root.owners[owner].specs || [];
            for (var si = 0; si < specs.length; si++) {
                var spec = specs[si] || {};
                if (spec.enabled === false) continue;
                var scrs = SMath.screensFor(spec, all);
                for (var gi = 0; gi < scrs.length; gi++) {
                    var scr = scrs[gi], id = spec.id || String(si);
                    out.push({ key: root._key(owner, id, scr.name), owner: owner,
                               screen: scr, spec: spec, sig: SMath.structuralSig(spec) });
                    if (spec.kind === "reserve" && spec.reserve !== false && spec.visible !== false) {
                        var sn = scr.name, e = String(spec.edge || "bottom");
                        if (!res[sn]) res[sn] = {};
                        if (res[sn][e] && res[sn][e].owner !== owner) {
                            conflicts.push({ owner: owner, screen: sn, edge: e, reason: "edge held by " + res[sn][e].owner });
                        } else {
                            res[sn][e] = { owner: owner, thickness: Math.round(Number(spec.reserveThickness) || 0) };
                        }
                    }
                }
            }
        }
        root.conflicts = conflicts;
        root.instances = out;
        root.obstacles = root.deriveObstacles();
    }

    function deriveObstacles() {
        var out = [];
        for (var i = 0; i < root.instances.length; i++) {
            var o = SMath.deriveObstacle(root.instances[i]);
            if (o) { o.screen = root.instances[i].screen.name; out.push(o); }
        }
        return out;
    }
}