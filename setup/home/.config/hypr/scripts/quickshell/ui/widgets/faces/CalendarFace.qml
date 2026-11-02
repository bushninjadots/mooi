import QtQuick
import QtQuick.Layouts
import "../../../core"

// ============================================================================
// CalendarFace — current-month grid with today highlighted. Pure date logic.
// ============================================================================

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 220
    property real minHeight: 200
    property real maxWidth: 640
    property real maxHeight: 640
    property real minAspect: 0.7
    property real maxAspect: 1.5
    property bool isRound: false

    property var now: new Date()
    readonly property int year: root.now.getFullYear()
    readonly property int month: root.now.getMonth()
    readonly property int today: root.now.getDate()

    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property var dowShort: ["S", "M", "T", "W", "T", "F", "S"]

    readonly property int firstWeekday: new Date(root.year, root.month, 1).getDay()
    readonly property int daysInMonth: new Date(root.year, root.month + 1, 0).getDate()

    readonly property var cells: {
        let out = [];
        for (let i = 0; i < root.firstWeekday; i++)
            out.push({ "day": 0, "today": false });
        for (let d = 1; d <= root.daysInMonth; d++)
            out.push({ "day": d, "today": d === root.today });
        while (out.length % 7 !== 0)
            out.push({ "day": 0, "today": false });
        return out;
    }

    Timer {
        interval: 60000
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.min(parent.width, parent.height) * 0.08
        spacing: Math.min(parent.height * 0.03, 8)

        Text {
            Layout.fillWidth: true
            text: root.monthNames[root.month] + " " + root.year
            font.family: Theme.fontFamily
            font.pixelSize: Math.min(20, parent.height * 0.09)
            font.weight: Font.Bold
            color: Theme.text
            elide: Text.ElideRight
        }

        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: 14
            spacing: 0

            Repeater {
                model: root.dowShort

                delegate: Text {
                    required property var modelData
                    width: parent.width / 7
                    height: parent.height
                    text: modelData
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.overlay0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Grid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            rows: root.cells.length / 7
            readonly property real cellW: width / 7
            readonly property real cellH: height / Math.max(1, rows)

            Repeater {
                model: root.cells

                delegate: Item {
                    required property var modelData
                    width: parent.cellW
                    height: parent.cellH

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) * 0.78
                        height: width
                        radius: width / 2
                        visible: modelData.day > 0
                        color: modelData.today ? Theme.mauve : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: modelData.day > 0
                        text: modelData.day
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.min(13, parent.height * 0.46)
                        font.weight: modelData.today ? Font.Bold : Font.Normal
                        color: modelData.today ? Theme.crust : Theme.subtext1
                    }
                }
            }
        }
    }
}
