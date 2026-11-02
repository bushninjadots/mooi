import QtQuick
import Quickshell
import "../../../core"
import ".."

// CUSTOMIZATION HOOK: action / icon / colors can be overridden from the mega menu
// via future bar.modules.help.{icon,action,accent}. Idle/hover roles are declared
// here as the defaults.
ModulePill {
    id: mod
    moduleId: "help"

    padH: bar.s(6)
    idleRole: "text"
    hoverRole: "teal"

    // Opens the unified settings panel on the About tab (same page as the
    // "About" entry at the end of the rail). SUPER+H does the same; the old
    // standalone guide popup was removed.
    onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle bar-editor about"])

    Text {
        text: mod.glyph("󰅖")
        font.family: bar.fontFamily
        font.pixelSize: bar.s(22)
        color: mod.contentColor
        Behavior on color { ColorAnimation { duration: 200 } }
    }
}
