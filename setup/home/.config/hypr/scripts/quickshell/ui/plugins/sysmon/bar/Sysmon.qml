// Sysmon — the sysmon plugin's bar module (equisdots plugin standard).
//
// Declared in the manifest as provides.bar.modules.sysmon; the bar loads it
// from the plugin UI tree with the standard module contract. Self-contained:
// it reads the core SysData singleton (shared fetch, ref-counted
// subscription) and opens the floating system monitor on click.
import QtQuick
import Quickshell
import qs.core
import qs.ui.bar

ModulePill {
    id: mod
    moduleId: "sysmon"

    accentRole: "color1"
    accentActive: SysData.ramPercent > 0

    Component.onCompleted: SysData.subscribe()
    Component.onDestruction: SysData.unsubscribe()

    onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle system-monitor"])

    // --- horizontal: glyphs + live values ------------------------------------
    Row {
        visible: mod.horizontal
        spacing: bar.s(10)

        Text { anchors.verticalCenter: parent.verticalCenter; text: "\uF0E4"; font.family: bar.fontFamily; font.pixelSize: bar.s(13); color: mod.contentColor }
        Text { anchors.verticalCenter: parent.verticalCenter; text: SysData.cpu + "%"; font.family: bar.fontFamily; font.pixelSize: bar.s(12); font.weight: Font.Black; color: mod.contentColor }
        Rectangle { width: bar.s(1); height: bar.s(16); color: colors.overlay0; opacity: 0.4 }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "\uF0351"; font.family: bar.fontFamily; font.pixelSize: bar.s(13); color: mod.contentColor }
        Text { anchors.verticalCenter: parent.verticalCenter; text: SysData.ramPercent + "%"; font.family: bar.fontFamily; font.pixelSize: bar.s(12); font.weight: Font.Black; color: mod.contentColor }
    }

    // --- compact: two tiny stacked values ------------------------------------
    Column {
        visible: mod.compact
        spacing: 1

        Text { anchors.horizontalCenter: parent.horizontalCenter; text: SysData.cpu + "%"; font.family: bar.fontFamily; font.pixelSize: bar.s(9); font.weight: Font.Black; color: mod.contentColor }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: SysData.ramPercent + "%"; font.family: bar.fontFamily; font.pixelSize: bar.s(9); font.weight: Font.Black; color: mod.contentColor }
    }
}
