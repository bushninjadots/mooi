import QtQuick
import "../../core"
import qs.core.sdk

// ═══════════════════════════════════════════════════════════════════════════
// SurfaceHost — imperative diff of Surfaces.instances into SurfaceWindow items
// (one per instance key), plus obstacle republication through FrameBus.
// Mounted once in Shell.qml (before PluginHosts).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: host
    visible: false
    width: 0
    height: 0

    property var live: ({})

    Component { id: surfaceComp; SurfaceWindow {} }

    function sync() {
        let insts = Surfaces.instances || [];
        let seen = {};
        for (let i = 0; i < insts.length; i++) {
            let inst = insts[i];
            seen[inst.key] = true;
            let w = host.live[inst.key];
            if (!w) {
                w = surfaceComp.createObject(host, { instance: inst });
                if (w) host.live[inst.key] = w;
            } else {
                w.instance = inst;
            }
        }
        let keys = Object.keys(host.live);
        for (let k = 0; k < keys.length; k++) {
            if (!seen[keys[k]]) { host.live[keys[k]].destroy(); delete host.live[keys[k]]; }
        }
        FrameBus.setHostObstacles(Surfaces.obstacles || []);
    }

    Connections { target: Surfaces; function onInstancesChanged() { host.sync(); } }
    Component.onCompleted: host.sync()
}
