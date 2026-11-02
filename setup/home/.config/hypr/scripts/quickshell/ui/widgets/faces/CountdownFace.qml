import QtQuick
import QtQuick.Layouts
import "../../../core"

// ============================================================================
// CountdownFace — days : hours : minutes : seconds until a target moment.
// `target` (ISO string) is configurable; when empty it counts to next New Year.
// ============================================================================

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 200
    property real minHeight: 110
    property real maxWidth: 900
    property real maxHeight: 360
    property real minAspect: 0.8
    property real maxAspect: 3.2
    property bool isRound: false

    property string label: "New Year"
    property string target: ""

    property var now: new Date()
    readonly property bool isStacked: (width / height) < 1.2

    readonly property var targetDate: {
        if (root.target) {
            let d = new Date(root.target);
            if (!isNaN(d.getTime())) return d;
        }
        return new Date(root.now.getFullYear() + 1, 0, 1, 0, 0, 0);
    }

    readonly property real remain: Math.max(0, root.targetDate.getTime() - root.now.getTime())
    readonly property int days: Math.floor(root.remain / 86400000)
    readonly property int hours: Math.floor((root.remain % 86400000) / 3600000)
    readonly property int minutes: Math.floor((root.remain % 3600000) / 60000)
    readonly property int seconds: Math.floor((root.remain % 60000) / 1000)

    function pad2(n) {
        return (n < 10 ? "0" : "") + n;
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    GlassCard {
        anchors.fill: parent
        fill: Theme.widgetFill
        hairline: Theme.widgetHairline
        cornerRadius: Theme.radiusLg
    }

    Item {
        anchors.fill: parent
        anchors.margins: Math.min(parent.width, parent.height) * 0.10

        // --- wide ---------------------------------------------------------------
        RowLayout {
            visible: !root.isStacked
            anchors.fill: parent
            spacing: Math.min(parent.width, parent.height) * 0.08

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: parent.height * 0.7
                spacing: 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    text: root.days
                    font.family: Theme.fontFamily
                    font.pixelSize: 72
                    font.weight: Font.Black
                    color: Theme.mauve
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 18
                    Layout.preferredHeight: Math.max(22, parent.height * 0.6)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    text: "DAYS"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                    color: Theme.subtext0
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: root.label
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    color: Theme.text
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.pad2(root.hours) + ":" + root.pad2(root.minutes) + ":" + root.pad2(root.seconds)
                    font.family: Theme.fontFamily
                    font.pixelSize: 26
                    font.weight: Font.Black
                    color: Theme.blue
                }
            }
        }

        // --- stacked ------------------------------------------------------------
        ColumnLayout {
            visible: root.isStacked
            anchors.fill: parent
            spacing: 0

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: root.days
                font.family: Theme.fontFamily
                font.pixelSize: 56
                font.weight: Font.Black
                color: Theme.mauve
                fontSizeMode: Text.Fit
                minimumPixelSize: 16
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                Layout.fillWidth: true
                text: root.hours + "h " + root.minutes + "m"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Theme.subtext0
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
