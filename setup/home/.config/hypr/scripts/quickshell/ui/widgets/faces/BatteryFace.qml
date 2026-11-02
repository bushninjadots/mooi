import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../../core"

// ============================================================================
// BatteryFace — charge level + state, read from /sys/class/power_supply.
// Polls only while shown; renders "AC" on desktops without a battery.
// ============================================================================

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 160
    property real minHeight: 110
    property real maxWidth: 560
    property real maxHeight: 360
    property real minAspect: 0.7
    property real maxAspect: 2.8
    property bool isRound: false

    readonly property bool active: root.visible && root.width > 0 && root.height > 0

    property bool present: false
    property int capacity: 0
    property string status: ""

    readonly property bool charging: root.status === "Charging" || root.status === "Full"

    function glyph() {
        if (!root.present) return "󰚥";
        if (root.charging) return "󰂄";
        if (root.capacity >= 90) return "󰁹";
        if (root.capacity >= 70) return "󰂀";
        if (root.capacity >= 50) return "󰁾";
        if (root.capacity >= 30) return "󰁼";
        if (root.capacity >= 10) return "󰁺";
        return "󰂎";
    }

    function accent() {
        if (!root.present) return Theme.overlay0;
        if (root.charging) return Theme.green;
        if (root.capacity <= 15) return Theme.red;
        if (root.capacity <= 35) return Theme.yellow;
        return Theme.text;
    }

    function refresh() {
        poller.running = false;
        poller.running = true;
    }

    onActiveChanged: if (root.active) root.refresh()

    Timer {
        interval: 5000
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: poller
        running: false
        command: ["bash", "-c", "p=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1); if [ -n \"$p\" ]; then echo \"bat|$(cat $p/capacity 2>/dev/null)||$(cat $p/status 2>/dev/null)\"; else echo \"none||\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let t = (this.text || "").trim();
                if (t === "") return;
                let parts = t.split("|");
                if (parts[0] === "bat") {
                    root.present = true;
                    root.capacity = parseInt(parts[1]) || 0;
                    root.status = parts[2] || "";
                } else {
                    root.present = false;
                    root.capacity = 0;
                    root.status = "";
                }
            }
        }
    }

    GlassCard {
        anchors.fill: parent
        fill: Theme.widgetFill
        hairline: Theme.widgetHairline
        cornerRadius: Theme.radiusLg
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.min(parent.width, parent.height) * 0.12
        spacing: 0

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.glyph()
            font.family: Theme.fontFamily
            font.pixelSize: Math.min(48, parent.height * 0.5)
            color: root.accent()
            fontSizeMode: Text.Fit
            minimumPixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            Layout.fillWidth: true
            text: root.present ? (root.capacity + "%") : "AC"
            font.family: Theme.fontFamily
            font.pixelSize: Math.min(30, parent.height * 0.22)
            font.weight: Font.Black
            color: root.accent()
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            Layout.fillWidth: true
            visible: root.present
            text: root.status
            font.family: Theme.fontFamily
            font.pixelSize: Math.min(11, parent.height * 0.09)
            color: Theme.subtext0
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
