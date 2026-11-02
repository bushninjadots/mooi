import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core.sdk

// ═══════════════════════════════════════════════════════════════════════════
// PluginPopup — generic popup base for a plugin's bar module.
//
// The plugin SHIPS its own `*.qml` that roots on this type (so the popup is
// "included in the plugin"); the plugin fills the body through the default
// property. This base is fully self-contained:
//
//   • reads the plugin's OWN settings file for the chosen screen anchor
//     (key: `popupAnchor`, default "center"), so the position is configurable
//     in the plugin's settings sheet with no core involvement;
//   • positions the master window through `targetMasterX/Y` (honoured by
//     ui/Main.qml → applyMasterTargets) and sizes it through targetMaster*;
//   • provides a themed MD3 header (accent bar, title, subtitle, close).
//
// A plugin popup is declared in the manifest as
//   provides.panels.<id> = { comp: "ui/Popup.qml", w, h, label }
// and opened with `qs_manager.sh toggle <id>` (the bar module's onClicked).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: popup

    // Filled by the plugin.
    property string pluginId: ""
    property string scopeName: ""          // settings scope (usually == pluginId)
    property string title: ""
    property string subtitle: ""
    property color  accent: Theme.mauve
    property int    popupWidth: 460
    property int    popupHeight: 320

    default property alias content: body.data

    Scaler { id: sc; currentWidth: Screen.width; currentHeight: Screen.height }
    function s(v) { return sc.s(v) }

    readonly property string settingsPath:
        Quickshell.env("HOME") + "/.config/hypr/plugins/" + pluginId + "/settings.json"

    SettingsStore { id: store; filePath: popup.settingsPath }
    SettingsScope {
        id: cfg
        store: store
        scope: popup.scopeName !== "" ? popup.scopeName : popup.pluginId
    }

    // Expose the plugin's own SettingsScope to the popup content (read/write).
    readonly property var settings: cfg

    readonly property string anchor: cfg.get("popupAnchor", "center")

    readonly property real _w: s(popupWidth)
    readonly property real _h: s(popupHeight)
    readonly property real _m: s(12)

    property real targetMasterWidth: _w
    property real targetMasterHeight: _h
    property real targetMasterX: {
        if (anchor === "top-left" || anchor === "bottom-left" || anchor === "left") return _m;
        if (anchor === "top-right" || anchor === "bottom-right" || anchor === "right")
            return Math.round(Screen.width - _w - _m);
        return Math.round((Screen.width - _w) / 2);
    }
    property real targetMasterY: {
        if (anchor === "top-left" || anchor === "top-center" || anchor === "top-right") return _m;
        if (anchor === "bottom-left" || anchor === "bottom-center" || anchor === "bottom-right")
            return Math.round(Screen.height - _h - _m);
        return Math.round((Screen.height - _h) / 2);
    }

    function closeSelf() {
        Quickshell.execDetached(["bash",
            Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLg
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.outlineVariant
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── header ─────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                implicitHeight: hdr.implicitHeight + Theme.gapLg * 2

                RowLayout {
                    id: hdr
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.gapLg
                    anchors.rightMargin: Theme.gapSm
                    spacing: Theme.gapMd

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 4; height: popup.s(30); radius: 2
                        color: popup.accent
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: popup.title
                            font.family: "Hack Nerd Font"
                            font.weight: Font.Black
                            font.pixelSize: 18
                            color: Theme.text
                        }
                        Text {
                            visible: popup.subtitle !== ""
                            text: popup.subtitle
                            font.family: "Hack Nerd Font"
                            font.pixelSize: 11
                            color: Theme.subtext0
                        }
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: popup.s(30); height: popup.s(30)
                        radius: Theme.radiusSm
                        color: closeMa.containsMouse
                               ? Theme.stateLayer(Theme.text, Theme.stateHover) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            font.family: "Hack Nerd Font"
                            font.pixelSize: 15
                            color: Theme.subtext0
                        }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.closeSelf()
                        }
                    }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: Theme.outlineVariant
                }
            }

            // ── body (plugin content) ──────────────────────────────────────
            Item {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
