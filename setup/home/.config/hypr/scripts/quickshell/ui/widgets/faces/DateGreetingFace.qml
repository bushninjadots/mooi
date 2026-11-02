import QtQuick
import QtQuick.Layouts
import "../../../core"

// ============================================================================
// DateGreetingFace — big date + time-of-day greeting + current time.
// Pure date logic (no external data). Greeting follows the local hour.
// ============================================================================

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 180
    property real minHeight: 110
    property real maxWidth: 900
    property real maxHeight: 600
    property real minAspect: 0.7
    property real maxAspect: 3.2
    property bool isRound: false

    property var now: new Date()
    readonly property bool isStacked: (width / height) < 1.2

    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    function pad2(n) {
        return (n < 10 ? "0" : "") + n;
    }

    function greetingFor(h) {
        if (h < 6) return "Good night";
        if (h < 12) return "Good morning";
        if (h < 18) return "Good afternoon";
        if (h < 22) return "Good evening";
        return "Good night";
    }

    readonly property string greeting: root.greetingFor(root.now.getHours())
    readonly property string dayNumber: String(root.now.getDate())
    readonly property string weekday: root.dayNames[root.now.getDay()]
    readonly property string monthYear: root.monthNames[root.now.getMonth()] + " " + root.now.getFullYear()
    readonly property string clock: root.pad2(root.now.getHours()) + ":" + root.pad2(root.now.getMinutes())

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

        // --- wide: day block | greeting block -----------------------------------
        RowLayout {
            visible: !root.isStacked
            anchors.fill: parent
            spacing: Math.min(parent.width, parent.height) * 0.10

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: true
                Layout.preferredWidth: Math.max(72, parent.height * 0.7)
                spacing: 0

                Text {
                    id: dayText
                    Layout.alignment: Qt.AlignHCenter
                    text: root.dayNumber
                    font.family: Theme.fontFamily
                    font.pixelSize: 96
                    font.weight: Font.Black
                    color: Theme.mauve
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 20
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    text: root.weekday
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.0
                    color: Theme.subtext0
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 1
                Layout.preferredHeight: parent.height * 0.8
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.10)
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: root.greeting
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    color: Theme.text
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.monthYear
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.subtext0
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.clock
                    font.family: Theme.fontFamily
                    font.pixelSize: 30
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
                text: root.dayNumber
                font.family: Theme.fontFamily
                font.pixelSize: 64
                font.weight: Font.Black
                color: Theme.mauve
                fontSizeMode: Text.Fit
                minimumPixelSize: 16
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                Layout.fillWidth: true
                text: root.greeting
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Theme.text
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.weekday + " · " + root.clock
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.subtext0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }
}
