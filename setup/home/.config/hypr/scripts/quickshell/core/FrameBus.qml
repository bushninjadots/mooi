pragma Singleton
// ═══════════════════════════════════════════════════════════════════════════
// shell · core — FrameBus
//
// Tiny reactive bus between the master widget host (ui/Main.qml) and the
// screen frame (ui/frame/Frame.qml). The frame needs the LIVE morph box of the
// active widget (launcher/panels) to carve its notch in sync with the open/
// close animation; that box only exists inside Main, so Main publishes it here.
//
// `active` is always a valid object; `valid` is false when nothing is open.
// `edge` is the screen edge the widget is anchored to ("top"|"bottom"|"left"|
// "right") or "" when it is centered / should not notch.
// ═══════════════════════════════════════════════════════════════════════════
import QtQuick

QtObject {
    id: root

    readonly property var empty: ({ valid: false, x: 0, y: 0, w: 0, h: 0, edge: "" })

    property var active: ({ valid: false, x: 0, y: 0, w: 0, h: 0, edge: "" })

    function publish(x, y, w, h, edge) {
        root.active = {
            valid: w > 0 && h > 0,
            x: Math.round(x),
            y: Math.round(y),
            w: Math.round(w),
            h: Math.round(h),
            edge: edge === undefined || edge === null ? "" : String(edge)
        };
    }

    function clear() {
        root.active = root.empty;
    }

    // Host obstacles: rects published by plugin host adapters (republished by
    // ui/PluginHosts.qml from their `frameObstacle` property). The frame hugs
    // them and never reserves edges marked `avoidReserve`.
    property var hostObstacles: []

    function setHostObstacles(list) {
        root.hostObstacles = (list && list.length !== undefined) ? list : [];
    }
}
