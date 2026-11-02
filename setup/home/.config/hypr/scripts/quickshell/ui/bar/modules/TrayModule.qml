import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import "../../../core"
import "../../../core/Personalization.js" as Personalization
import ".."

// System tray — icon grid. Single row on top/bottom bars, a 2-column grid on
// left/right bars so the icons stay readable in the narrow bar.
ModulePill {
    id: mod

    readonly property var trayCfg: Personalization.normalize("tray", Config.rawSettings.tray)
    readonly property bool trayTinted: trayCfg.tint === true
    readonly property color trayTintColor: trayCfg.useAccent
        ? (colors[accentRole] || colors.mauve)
        : contentColor
    noFill: true
    padH: bar.s(12)
    showState: trayRepeater.count > 0

    Item {
        id: trayHost
        width: showState ? (mod.compact ? bar.pillWidth : trayGrid.implicitWidth) : 0
        height: showState ? (mod.compact ? trayGrid.implicitHeight : bar.pillHeight) : 0

        Grid {
            id: trayGrid
            visible: mod.compact
            anchors.centerIn: parent
            columns: 2
            spacing: bar.s(4)
            Repeater { id: trayRepeaterC; model: SystemTray.items; delegate: trayDelegate }
        }

        Row {
            id: trayRow
            visible: mod.horizontal
            anchors.centerIn: parent
            spacing: bar.s(13)
            Repeater { id: trayRepeater; model: SystemTray.items; delegate: trayDelegate }
        }
    }

    Component {
        id: trayDelegate
        Image {
            id: trayIcon
            required property var modelData
            source: modelData.icon || ""
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(bar.s(mod.trayCfg.size), bar.s(mod.trayCfg.size))
            width: bar.s(mod.trayCfg.size)
            height: bar.s(mod.trayCfg.size)

            layer.enabled: mod.trayTinted
            layer.effect: MultiEffect {
                saturation: -1.0
                colorization: 1.0
                colorizationColor: mod.trayTintColor
            }

            opacity: initAnimTrigger ? (trayMouse.containsMouse ? 1.0 : 0.8) : 0.0
            scale: initAnimTrigger ? (trayMouse.containsMouse ? 1.15 : 1.0) : 0.0

            property bool initAnimTrigger: false
            Component.onCompleted: {
                if (!bar.startupCascadeFinished) {
                    anim.interval = trayIcon.index * 50;
                    anim.start();
                } else initAnimTrigger = true;
            }
            Timer { id: anim; running: false; repeat: false; onTriggered: trayIcon.initAnimTrigger = true }
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

            QsMenuAnchor {
                id: menuAnchor
                anchor.window: bar
                anchor.item: trayIcon
                menu: modelData.menu
            }

            MouseArea {
                id: trayMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        if (modelData.isMenuOnly || modelData.onlyMenu) menuAnchor.open();
                        else if (typeof modelData.activate === "function") modelData.activate();
                    } else if (mouse.button === Qt.MiddleButton) {
                        if (typeof modelData.secondaryActivate === "function") modelData.secondaryActivate();
                    } else if (mouse.button === Qt.RightButton) {
                        if (modelData.menu) menuAnchor.open();
                        else if (typeof modelData.contextMenu === "function") modelData.contextMenu(mouse.x, mouse.y);
                        else modelData.activate();
                    }
                }
            }
        }
    }
}
