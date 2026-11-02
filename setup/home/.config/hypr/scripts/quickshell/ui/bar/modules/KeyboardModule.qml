import QtQuick
import Quickshell
import "../../../core"
import "../../../core"
import ".."

// Keyboard layout — purple accent island. Compact (vertical bar): icon only.
ModulePill {
    id: mod
    moduleId: "keyboard"

    accentRole: "color5"
    accentActive: true

    onClicked: Compositor.cycleKeyboardLayout()

    Row {
        visible: mod.horizontal
        spacing: bar.s(10)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: mod.glyph("󰌌")
            font.family: bar.fontFamily
            font.pixelSize: bar.s(16)
            color: mod.contentColor
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: bar.kbLayout
            font.family: bar.fontFamily
            font.pixelSize: bar.s(13)
            font.weight: Font.Black
            color: mod.contentColor
        }
    }

    // Compact: icon only.
    Text {
        visible: mod.compact
        text: mod.glyph("󰌌")
        font.family: bar.fontFamily
        font.pixelSize: bar.s(20)
        color: mod.contentColor
    }
}
