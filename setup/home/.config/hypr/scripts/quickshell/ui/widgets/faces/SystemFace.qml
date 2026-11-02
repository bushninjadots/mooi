import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../../core"

// ============================================================================
// SystemFace — CPU / RAM / temperature ring gauges (+ network throughput).
// Reads the core SysData singleton and only subscribes while actually shown,
// so the redactor's hidden probe never starts the poller.
// ============================================================================

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 240
    property real minHeight: 120
    property real maxWidth: 900
    property real maxHeight: 420
    property real minAspect: 0.8
    property real maxAspect: 4.0
    property bool isRound: false

    readonly property bool active: root.visible && root.width > 0 && root.height > 0

    onActiveChanged: {
        if (root.active)
            SysData.subscribe();
        else
            SysData.unsubscribe();
    }
    Component.onDestruction: SysData.unsubscribe()

    GlassCard {
        anchors.fill: parent
        fill: Theme.widgetFill
        hairline: Theme.widgetHairline
        cornerRadius: Theme.radiusLg
    }

    component Ring: Item {
        id: ring
        property real value: 0          // 0..1
        property color accent: Theme.blue
        property string label: ""
        property string readout: ""
        implicitWidth: 88
        implicitHeight: 88
        readonly property real thick: Math.max(5, Math.min(width, height) * 0.10)
        readonly property real rad: (Math.min(width, height) - ring.thick) / 2

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
                strokeWidth: ring.thick
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: ring.rad
                    radiusY: ring.rad
                    startAngle: -90
                    sweepAngle: 360
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: ring.accent
                strokeWidth: ring.thick
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: ring.rad
                    radiusY: ring.rad
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0, Math.min(1, ring.value))
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: ring.readout
            font.family: Theme.fontFamily
            font.pixelSize: Math.min(18, ring.height * 0.24)
            font.weight: Font.Bold
            color: Theme.text
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 4
            text: ring.label
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 1.0
            color: Theme.subtext0
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: Math.min(parent.width, parent.height) * 0.10

        ColumnLayout {
            anchors.fill: parent
            spacing: 6

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                spacing: Math.min(parent.width, parent.height) * 0.10

                Ring {
                    Layout.alignment: Qt.AlignTop
                    Layout.fillHeight: true
                    Layout.preferredWidth: Math.min(parent.height * 0.6, parent.width / 3)
                    value: SysData.cpu / 100
                    accent: Theme.mauve
                    label: "CPU"
                    readout: SysData.cpu + "%"
                }

                Ring {
                    Layout.alignment: Qt.AlignTop
                    Layout.fillHeight: true
                    Layout.preferredWidth: Math.min(parent.height * 0.6, parent.width / 3)
                    value: SysData.ramPercent / 100
                    accent: Theme.green
                    label: "RAM"
                    readout: SysData.ramPercent + "%"
                }

                Ring {
                    Layout.alignment: Qt.AlignTop
                    Layout.fillHeight: true
                    Layout.preferredWidth: Math.min(parent.height * 0.6, parent.width / 3)
                    value: Math.max(0, Math.min(1, SysData.temp / 100))
                    accent: SysData.temp >= 80 ? Theme.red : Theme.peach
                    label: "TEMP"
                    readout: SysData.temp + "°"
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                text: "↓ " + (SysData.netRx / 1024).toFixed(1) + "  ↑ " + (SysData.netTx / 1024).toFixed(1) + " MB/s"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.subtext0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }
}
