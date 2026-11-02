import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
// Sysmon — a floating system monitor. Host adapter (equisdots plugin standard).
//
// Publishes ONE overlay surface (via the SDK surface manager) whose content is
// a small card with live CPU / RAM / temperature bars. Reads the plugin's
// scope (`sysmon`) through the injected handle and the live stats via
// `host.stats` (SysData). Colors follow the active palette (`host.colors`).
//
// The floating monitor is opt-in: it only publishes the surface while
// `sysmon.panelEnabled === true` (its settings page toggles it). The plugin's
// bar island (bar/Sysmon.qml, provides.bar.modules) is independent of this
// flag — it follows the plugin master switch and its bar slot.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    visible: false
    width: 0
    height: 0

    property var host: null

    readonly property var _fb: ({
        base: "#1e1e2e", mantle: "#181825", crust: "#11111b",
        text: "#cdd6f4", subtext0: "#a6adc8", surface0: "#313244",
        surface1: "#45475a", mauve: "#cba6f7", green: "#a6e3a1",
        yellow: "#f9e2af", red: "#f38ba8", blue: "#89b4fa", teal: "#94e2d5"
    })
    readonly property var c: (host && host.colors) ? host.colors : _fb

    function num(v, d) { return (typeof v === "number" && isFinite(v)) ? v : d; }
    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

    // ── config (plain, set by syncCfg) ─────────────────────────────────────
    property string position: "top-right"
    property real uiScale: 1.0
    property real cardOpacity: 0.85
    property bool showCpu: true
    property bool showRam: true
    property bool showTemp: true
    property bool panelEnabled: false

    function syncCfg() {
        let d = (host && host.settings) ? host.settings.all() : {};
        let p = String(d.position || "top-right");
        if (["top-left", "top-right", "bottom-left", "bottom-right"].indexOf(p) < 0) p = "top-right";
        position = p;
        uiScale = clamp(num(d.uiScale, 1.0), 0.6, 2.0);
        cardOpacity = clamp(num(d.opacity, 0.85), 0.15, 1.0);
        showCpu = d.showCpu !== false;
        showRam = d.showRam !== false;
        showTemp = d.showTemp !== false;
        panelEnabled = d.panelEnabled === true;
    }
    function subscribeStats() { if (root.host && root.host.stats) root.host.stats.subscribe(); }
    Component.onCompleted: { root.syncCfg(); root.subscribeStats(); }
    Component.onDestruction: if (root.host && root.host.stats) root.host.stats.unsubscribe()
    Connections { target: root; function onHostChanged() { root.syncCfg(); root.subscribeStats(); } }
    Connections {
        target: root.host ? root.host.settings : null
        function onChanged() { root.syncCfg(); }
        function onKeyChanged() { root.syncCfg(); }
    }
    readonly property var stats: (host && host.stats) ? host.stats : ({ cpu: 0, ramPercent: 0, temp: 0 })
    function s(v) { return Math.round(v * uiScale); }

    // ── the surface (declared to the SDK manager) ──────────────────────────
    // Published only while the floating monitor is enabled (panelEnabled).
    readonly property var surfaces: root.panelEnabled ? [
        { id: "sysmon", kind: "overlay", screen: "all", content: contentComp }
    ] : []

    Component {
        id: contentComp
        Item {
            id: cr
            property var qsScreen: null
            readonly property var maskItem: card

            Rectangle {
                id: card
                x: (root.position.indexOf("right") >= 0) ? (parent.width - root.s(14) - width) : root.s(14)
                y: (root.position.indexOf("bottom") >= 0) ? (parent.height - root.s(14) - height) : root.s(14)
                width: col.implicitWidth + root.s(20)
                height: col.implicitHeight + root.s(16)
                radius: root.s(14)
                color: Qt.rgba(c.base.r, c.base.g, c.base.b, root.cardOpacity)
                border.width: 1
                border.color: Qt.rgba(c.surface1.r, c.surface1.g, c.surface1.b, 0.9)

                Column {
                    id: col
                    anchors.centerIn: parent
                    spacing: root.s(6)

                    Text {
                        text: "SYS"
                        visible: root.showCpu || root.showRam || root.showTemp
                        font.family: "Hack Nerd Font"; font.weight: Font.Black
                        font.pixelSize: root.s(10); color: c.mauve
                    }
                    Repeater {
                        model: {
                            let out = [];
                            if (root.showCpu) out.push({ k: "CPU", v: root.stats.cpu, f: root.stats.cpu / 100, col: c.blue });
                            if (root.showRam) out.push({ k: "RAM", v: root.stats.ramPercent, f: root.stats.ramPercent / 100, col: c.green });
                            if (root.showTemp) out.push({ k: "TMP", v: root.stats.temp, f: Math.min(1, root.stats.temp / 100), col: c.red });
                            return out;
                        }
                        delegate: Item {
                            required property var modelData
                            width: root.s(150); height: root.s(16)
                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.k; font.family: "Hack Nerd Font"; font.pixelSize: root.s(10)
                                color: c.subtext0
                            }
                            Rectangle {
                                id: track
                                anchors.left: parent.left; anchors.leftMargin: root.s(34)
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - root.s(74); height: root.s(6); radius: height / 2
                                color: Qt.rgba(c.surface0.r, c.surface0.g, c.surface0.b, 0.8)
                                Rectangle {
                                    width: Math.round(track.width * Math.max(0, Math.min(1, modelData.f)))
                                    height: parent.height; radius: parent.radius
                                    color: modelData.col
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                            Text {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(modelData.v) + (modelData.k === "TMP" ? "°" : "%")
                                font.family: "Hack Nerd Font"; font.pixelSize: root.s(10); color: c.text
                            }
                        }
                    }
                }
            }
        }
    }
}
