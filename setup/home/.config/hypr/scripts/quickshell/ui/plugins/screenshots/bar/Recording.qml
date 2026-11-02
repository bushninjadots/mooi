// Recording — the screenshots plugin's bar module (equisdots plugin standard).
//
// Declared in the manifest as provides.bar.modules.recording; the bar loads it
// from the plugin UI tree with the standard module contract (bar, colors,
// slotIndex, ...). Self-contained: it polls the recording PID file the
// plugin's script writes (via Caching) and starts the recording flow through
// the plugin script resolver — no core state involved.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui.bar

ModulePill {
    id: mod
    moduleId: "recording"

    Caching { id: paths }

    property bool recording: false

    // screenshot.sh resolver (managed registry copy, managed UI tree, user
    // plugin, transitional core path).
    readonly property string shotCmd: "S=; for c in \"$HOME/.config/hypr/plugins/screenshots/scripts/screenshot.sh\" \"$HOME/.config/hypr/scripts/quickshell/ui/plugins/screenshots/scripts/screenshot.sh\" \"$HOME/.config/hypr/plugins-user/screenshots/scripts/screenshot.sh\" \"$HOME/.config/hypr/scripts/screenshot.sh\"; do [ -f \"$c\" ] && { S=\"$c\"; break; }; done; [ -n \"$S\" ] && exec bash \"$S\""

    Timer {
        interval: 2500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { recPoller.running = false; recPoller.running = true; }
    }

    Process {
        id: recPoller
        command: ["bash", "-c", "if [ -s " + paths.getCacheDir("recording") + "/rec_pid ] && kill -0 $(cat " + paths.getCacheDir("recording") + "/rec_pid) 2>/dev/null; then echo '1'; else echo '0'; fi"]
        stdout: StdioCollector {
            onStreamFinished: mod.recording = (this.text.trim() === "1")
        }
    }

    padH: bar.s(6)
    accentRole: "red"
    accentActive: mod.recording
    pulse: true
    showState: mod.recording

    onClicked: {
        mod.recording = false;
        Quickshell.execDetached(["bash", "-c", mod.shotCmd]);
    }

    Text {
        text: mod.glyph("\uf28d")
        font.family: bar.fontFamily
        font.pixelSize: bar.s(20)
        color: mod.contentColor

        SequentialAnimation on opacity {
            running: mod.recording && !mod.hovered
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
        }
    }
}
