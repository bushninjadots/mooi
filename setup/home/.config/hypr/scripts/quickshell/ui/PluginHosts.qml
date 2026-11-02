import QtQuick
import Quickshell
import "../core"
import qs.core.sdk

// ═══════════════════════════════════════════════════════════════════════════
// PluginHosts — mounts the always-on components of installed plugins:
// host adapters (`host`) and complete plugin bars (provides.bar.provider).
//
// A managed plugin may declare a host entry in its manifest:
//   "host": "<qml file, relative to the plugin UI root>"
// or ship a complete bar:
//   "provides": { "bar": { "provider": { "comp": "<qml file>" } } }
// The shell loads each enabled plugin's entries here. Both kinds live in the
// shell tree (deployed with the plugin UI) and follow the same contract as
// the shell's own components: they may import the core kit through the
// documented relative paths (`../../../../core`, `../../../bar`) and render
// whatever they need (overlays, surfaces, watchers, reserved bar windows).
//
// A host/bar may expose a `frameObstacle` property — a list of rects
// ({ screen?, edge, a, b, depth, avoidReserve? }) the screen frame should
// hug. PluginHosts republishes them through FrameBus (a generic contract;
// the shell never knows which plugin provides what).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    visible: false
    width: 0
    height: 0

    readonly property var hosts: {
        PluginsCatalog.rev; // re-evaluate when the plugin catalog updates
        let out = [];
        let list = PluginsCatalog.plugins || [];
        for (let i = 0; i < list.length; i++) {
            let p = list[i] || {};
            let compatOk = !(p.compat && p.compat.ok === false); // refuse incompatible
            // Managed plugins only (hosts live in the shell tree), loaded
            // relatively like every shell component.
            if (p.enabled !== true || !compatOk || !PluginsCatalog.isManaged(p)) continue;
            let host = String(p.host || "").replace(/^\.\//, "");
            if (host !== "")
                out.push({ id: String(p.id), url: "plugins/" + p.id + "/" + host, entry: p });
            // Complete plugin bars (manifest provides.bar.provider): an
            // always-on component exactly like a host adapter — same mount,
            // same handle injection, same surfaces/frameObstacle contracts.
            // The plugin's master switch owns it; its settings page is its
            // menu. Managed-only for the same reason hosts are.
            let bar = (p.provides && typeof p.provides === "object") ? p.provides.bar : null;
            let prov = (bar && typeof bar === "object") ? bar.provider : null;
            let barComp = (prov && typeof prov === "object") ? String(prov.comp || "").replace(/^\.\//, "") : "";
            if (barComp !== "")
                out.push({ id: String(p.id), url: "plugins/" + p.id + "/" + barComp, entry: p });
        }
        return out;
    }

    function refreshObstacles() {
        let out = [];
        for (let i = 0; i < rep.count; i++) {
            let delegate = rep.itemAt(i);
            let item = delegate ? delegate.item : null;
            let list = (item && item.frameObstacle) ? item.frameObstacle : null;
            if (list && list.length !== undefined)
                for (let k = 0; k < list.length; k++) out.push(list[k]);
        }
        FrameBus.setHostObstacles(out);
    }

    Repeater {
        id: rep
        model: root.hosts
        delegate: Loader {
            required property var modelData
            source: modelData.url
            onLoaded: {
                // Inject the SDK handle only if the plugin declares `host`
                // (incremental migration: plugins without it are untouched).
                if (item && item.host !== undefined)
                    item.host = HostApi.forPlugin(modelData.entry || modelData);
                // Register plugin-declared surfaces with the manager.
                if (item && item.surfaces !== undefined) {
                    Surfaces.register(String(modelData.id), item.surfaces, item);
                    item.surfacesChanged.connect(function () {
                        Surfaces.update(String(modelData.id), item.surfaces);
                    });
                }
                if (item && item.frameObstacleChanged)
                    item.frameObstacleChanged.connect(root.refreshObstacles);
                root.refreshObstacles();
            }
            onStatusChanged: if (status !== Loader.Ready) root.refreshObstacles()
            Component.onDestruction: { Surfaces.unregister(String(modelData.id)); root.refreshObstacles(); }
        }
    }

    onHostsChanged: Qt.callLater(root.refreshObstacles)
}