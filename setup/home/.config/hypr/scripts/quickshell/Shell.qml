//@ pragma UseQApplication
import QtQuick
import Quickshell
import "./ui"
import "./ui/bar"
import "./ui/frame"
import "./ui/widgets"
import "./ui/surfaces"

ShellRoot {
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup() }
    }

    Main {}
    Frame {}
    Bar {}
    SurfaceHost {}
    Floating {}
    Widgets {}
    PluginHosts {}
}
