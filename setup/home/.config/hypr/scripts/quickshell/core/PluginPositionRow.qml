import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core.sdk

// ═══════════════════════════════════════════════════════════════════════════
// PluginPositionRow — a settings control for a plugin's settings sheet.
//
// Writes the screen anchor of the plugin's popup ("popupAnchor") into the
// plugin's OWN settings file through the injected PluginHost. Drop it into any
// plugin settings page:
//
//   property var host: null              // injected by the shell
//   PluginPositionRow { host: page.host }
//
// The popup (PluginPopup) reads the same key, so the choice is live and needs
// no core change.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: row

    property var host: null
    property string label: "Popup position"
    property var options: [
        "center",
        "top-left", "top-center", "top-right",
        "bottom-left", "bottom-center", "bottom-right"
    ]

    Scaler { id: sc; currentWidth: Screen.width }
    function s(v) { return sc.s(v) }

    readonly property string value:
        (host && host.settings) ? host.settings.get("popupAnchor", "center") : "center"

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.gapSm

        Text {
            text: row.label
            font.family: "Hack Nerd Font"
            font.pixelSize: 12
            color: Theme.text
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.gapXs
            Repeater {
                model: row.options
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool on: modelData === row.value
                    width: lbl.implicitWidth + Theme.gapMd * 2
                    height: row.s(30)
                    radius: Theme.radiusSm
                    color: on ? Theme.stateLayer(Theme.mauve, Theme.statePress)
                              : Theme.surfaceContainerHigh
                    border.width: 1
                    border.color: on ? Theme.mauve : Theme.outlineVariant
                    Text {
                        id: lbl
                        anchors.centerIn: parent
                        text: modelData
                        font.family: "Hack Nerd Font"
                        font.pixelSize: 11
                        color: on ? Theme.text : Theme.subtext0
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (row.host && row.host.settings)
                                row.host.settings.set("popupAnchor", modelData);
                        }
                    }
                }
            }
        }
    }
}
