import QtQuick
import Quickshell
import Quickshell.Wayland

// ═══════════════════════════════════════════════════════════════════════════
// SurfaceWindow — one materialised surface (overlay or reserve strip) for one
// instance from Surfaces.instances. Owns the Quickshell pitfalls:
//   - a PanelWindow's anchors do not re-apply on binding updates → structural
//     props are FROZEN and the delegate is recreated when the signature changes;
//   - input region limited to the plugin's `maskItem` (click-through elsewhere);
//   - reserve strips set exclusiveZone only (never exclusionMode).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    visible: false
    width: 0
    height: 0

    property var instance: null
    property var liveSpec: ({})
    property string curSig: ""
    // frozen structural props (written only while the surface is down)
    property string sKind: "overlay"
    property string sEdge: "bottom"
    property string sLayer: "top"
    property bool sFocus: false
    property int sReserveThickness: 0

    onInstanceChanged: root.apply()
    Timer { id: debounce; interval: 90; onTriggered: root.remount() }

    function apply() {
        if (!root.instance) return;
        root.liveSpec = root.instance.spec;
        if (root.instance.sig !== root.curSig) { root.curSig = root.instance.sig; debounce.restart(); }
        else win.sourceComponentChanged();
    }
    function remount() {
        var spec = root.liveSpec || {};
        win.active = false;
        Qt.callLater(function () {
            root.sKind = spec.kind || "overlay";
            root.sEdge = String(spec.edge || "bottom");
            root.sLayer = spec.layer || "top";
            root.sFocus = !!(spec.focus && spec.focus !== "none");
            root.sReserveThickness = Math.round(Number(spec.reserveThickness) || 0);
            win.active = true;
        });
    }

    Loader { id: win; active: false; sourceComponent: root.sKind === "reserve" ? reserveWin : overlayWin }

    Component {
        id: overlayWin
        PanelWindow {
            id: w
            property var liveSpec: root.liveSpec
            screen: root.instance ? root.instance.screen : null
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors.top: true; anchors.bottom: true; anchors.left: true; anchors.right: true
            implicitWidth: w.screen ? w.screen.width : 1920
            implicitHeight: w.screen ? w.screen.height : 1080
            focusable: root.sFocus
            WlrLayershell.namespace: "equisdots-surface-" + (root.instance ? root.instance.owner : "x")
            WlrLayershell.layer: root.sLayer === "overlay" ? WlrLayer.Overlay
                              : root.sLayer === "background" ? WlrLayer.Background
                              : root.sLayer === "bottom" ? WlrLayer.Bottom : WlrLayer.Top

            Loader {
                id: contentLoader
                anchors.fill: parent
                sourceComponent: w.liveSpec ? w.liveSpec.content : null
                onLoaded: {
                    if (!item) return;
                    item.qsScreen = root.instance ? root.instance.screen : null;
                    if (w.liveSpec && w.liveSpec.props)
                        for (var k in w.liveSpec.props) item[k] = w.liveSpec.props[k];
                }
            }
            // click-through except the plugin's declared maskItem (if any).
            mask: Region { item: contentLoader.item ? contentLoader.item.maskItem : null }
        }
    }

    Component {
        id: reserveWin
        PanelWindow {
            id: r
            property var liveSpec: root.liveSpec
            screen: root.instance ? root.instance.screen : null
            color: "transparent"
            visible: !!(r.liveSpec && r.liveSpec.visible !== false)
            anchors.top: root.sEdge === "top"
            anchors.bottom: root.sEdge === "bottom"
            anchors.left: root.sEdge !== "right"
            anchors.right: root.sEdge !== "left"
            exclusiveZone: root.sReserveThickness
            focusable: false
            implicitWidth: (root.sEdge === "left" || root.sEdge === "right") ? root.sReserveThickness : (r.screen ? r.screen.width : 1920)
            implicitHeight: (root.sEdge === "top" || root.sEdge === "bottom") ? root.sReserveThickness : (r.screen ? r.screen.height : 1080)
            WlrLayershell.namespace: "equisdots-surface-reserve"
            mask: Region { }
        }
    }
}
