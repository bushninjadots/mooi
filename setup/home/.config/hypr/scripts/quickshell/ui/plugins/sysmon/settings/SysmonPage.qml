import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.ui.bar.edit
import qs.ui.bar
import qs.core

// ═══════════════════════════════════════════════════════════════════════════
// SysmonPage — the Sysmon plugin's own settings page (contract: `bar`).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent
    property var bar: null
    property var host: null

    property string dPosition: "top-right"
    property real dScale: 1.0
    property real dOpacity: 0.85
    property bool dShowCpu: true
    property bool dShowRam: true
    property bool dShowTemp: true
    property bool dPanelEnabled: false

    readonly property var cfg: {
        if (root.host && root.host.settings) return root.host.settings.section;
        Config.rev;
        let d = Config.rawSettings ? Config.rawSettings.sysmon : null;
        return (d && typeof d === "object") ? d : ({});
    }
    function num(v, d) { return (typeof v === "number" && isFinite(v)) ? v : d; }

    function syncFromConfig() {
        let d = root.cfg;
        root.dPosition = (["top-left","top-right","bottom-left","bottom-right"].indexOf(String(d.position)) >= 0) ? String(d.position) : "top-right";
        root.dScale = root.num(d.uiScale, 1.0);
        root.dOpacity = root.num(d.opacity, 0.85);
        root.dShowCpu = d.showCpu !== false;
        root.dShowRam = d.showRam !== false;
        root.dShowTemp = d.showTemp !== false;
        root.dPanelEnabled = d.panelEnabled === true;
    }
    Component.onCompleted: root.syncFromConfig()
    onHostChanged: if (root.host) root.syncFromConfig()

    property var _pending: ({})
    Timer { id: saveTimer; interval: 250; onTriggered: root.flush() }
    function set(key, v) { root._pending[key] = v; root.flush(); }
    function flush() {
        if (Object.keys(root._pending).length === 0) return;
        if (root.host && root.host.settings) {
            root.host.settings.setMany(root._pending);
        } else {
            let base = (Config.rawSettings.sysmon && typeof Config.rawSettings.sysmon === "object") ? Config.rawSettings.sysmon : {};
            Config.setSetting("sysmon", Object.assign({}, base, root._pending));
        }
        root._pending = {};
    }
    Component.onDestruction: root.flush()

    readonly property var flickable: body.item ? body.item.flickable : null

    Loader { id: body; anchors.fill: parent; active: root.bar !== null; sourceComponent: pageBody }

    Component {
        id: pageBody
        Item {
            anchors.fill: parent
            property alias flickable: flick
            Flickable {
                id: flick
                anchors.fill: parent; clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: col.height + bar.s(16)
                ScrollBar.vertical: ScrollBar { width: bar.s(4); policy: ScrollBar.AsNeeded }

                Column {
                    id: col
                    x: bar.s(8); y: bar.s(8)
                    width: flick.width - bar.s(16)
                    spacing: bar.s(9)

                    Text {
                        text: "Sysmon"
                        font.family: "Hack Nerd Font"; font.weight: Font.Black
                        font.pixelSize: bar.s(24); color: bar.colors.text
                    }
                    EditLabel {
                        bar: root.bar; width: parent.width
                        text: "The CPU/RAM bar island ships with the plugin; this page configures the optional floating monitor card (corner, scale, opacity and metrics)."
                        font.pixelSize: bar.s(11); color: bar.colors.subtext0; wrapMode: Text.WordWrap
                    }

                    SectionTitle { bar: root.bar; text: "Floating monitor" }
                    RowLayout {
                        width: parent.width; spacing: bar.s(12)
                        Text { text: "Show the monitor card"; font.family: "Hack Nerd Font"; font.pixelSize: bar.s(12); color: bar.colors.text; Layout.fillWidth: true }
                        ToggleSwitch { bar: root.bar; checked: root.dPanelEnabled; onToggled: { root.dPanelEnabled = checked; root.set("panelEnabled", checked); } }
                    }

                    SectionTitle { bar: root.bar; text: "Position" }
                    RowLayout {
                        width: parent.width; spacing: bar.s(8)
                        OptionCard { bar: root.bar; Layout.fillWidth: true; icon: "↖"; label: "Top left"; active: root.dPosition === "top-left"; onActivated: { root.dPosition = "top-left"; root.set("position", "top-left"); } }
                        OptionCard { bar: root.bar; Layout.fillWidth: true; icon: "↗"; label: "Top right"; active: root.dPosition === "top-right"; onActivated: { root.dPosition = "top-right"; root.set("position", "top-right"); } }
                        OptionCard { bar: root.bar; Layout.fillWidth: true; icon: "↙"; label: "Bottom left"; active: root.dPosition === "bottom-left"; onActivated: { root.dPosition = "bottom-left"; root.set("position", "bottom-left"); } }
                        OptionCard { bar: root.bar; Layout.fillWidth: true; icon: "↘"; label: "Bottom right"; active: root.dPosition === "bottom-right"; onActivated: { root.dPosition = "bottom-right"; root.set("position", "bottom-right"); } }
                    }

                    Grid {
                        width: parent.width; columns: 2; columnSpacing: bar.s(28); rowSpacing: bar.s(10)
                        Stepper { bar: root.bar; label: "Scale " + root.dScale.toFixed(2); onDec: { root.dScale = Math.max(0.6, Math.round((root.dScale - 0.1) * 100) / 100); root.set("uiScale", root.dScale); } onInc: { root.dScale = Math.min(2.0, Math.round((root.dScale + 0.1) * 100) / 100); root.set("uiScale", root.dScale); } }
                        Stepper { bar: root.bar; label: "Opacity " + Math.round(root.dOpacity * 100) + "%"; onDec: { root.dOpacity = Math.max(0.15, Math.round((root.dOpacity - 0.05) * 100) / 100); root.set("opacity", root.dOpacity); } onInc: { root.dOpacity = Math.min(1.0, Math.round((root.dOpacity + 0.05) * 100) / 100); root.set("opacity", root.dOpacity); } }
                    }

                    SectionTitle { bar: root.bar; text: "Metrics" }
                    RowLayout {
                        width: parent.width; spacing: bar.s(12)
                        Text { text: "CPU"; font.family: "Hack Nerd Font"; font.pixelSize: bar.s(12); color: bar.colors.text; Layout.fillWidth: true }
                        ToggleSwitch { bar: root.bar; checked: root.dShowCpu; onToggled: { root.dShowCpu = checked; root.set("showCpu", checked); } }
                    }
                    RowLayout {
                        width: parent.width; spacing: bar.s(12)
                        Text { text: "RAM"; font.family: "Hack Nerd Font"; font.pixelSize: bar.s(12); color: bar.colors.text; Layout.fillWidth: true }
                        ToggleSwitch { bar: root.bar; checked: root.dShowRam; onToggled: { root.dShowRam = checked; root.set("showRam", checked); } }
                    }
                    RowLayout {
                        width: parent.width; spacing: bar.s(12)
                        Text { text: "Temperature"; font.family: "Hack Nerd Font"; font.pixelSize: bar.s(12); color: bar.colors.text; Layout.fillWidth: true }
                        ToggleSwitch { bar: root.bar; checked: root.dShowTemp; onToggled: { root.dShowTemp = checked; root.set("showTemp", checked); } }
                    }
                }
            }
        }
    }
}
