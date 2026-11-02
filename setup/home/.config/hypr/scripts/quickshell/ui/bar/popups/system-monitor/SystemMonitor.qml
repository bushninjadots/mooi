import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../../../core"
import "../../../../core/Personalization.js" as Personalization
import "../.."

// System monitor — circular gauge hub.
//
// Replaces the old flat card grid with ring gauges modelled on the battery
// popup's hero circle: a rounded track, a gradient progress arc, a soft aura
// that swells on hover and a centered glyph + readout. CPU, memory, storage
// and thermal each get a ring; processes, uptime and disk live in a compact
// footer. Everything is driven by a GridLayout with fill so the popup keeps
// its proportions at any window size instead of clipping.
Item {
    id: window

    Colors { id: _theme }

    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0 || "#6c7086"
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color mauve: _theme.mauve || "#cba6f7"
    readonly property color pink: _theme.pink || _theme.mauve || "#f5c2e7"
    readonly property color green: _theme.green || "#a6e3a1"
    readonly property color teal: _theme.teal || "#94e2d5"
    readonly property color blue: _theme.blue || "#89b4fa"
    readonly property color sapphire: _theme.sapphire || "#74c7ec"
    readonly property color yellow: _theme.yellow || "#f9e2af"
    readonly property color peach: _theme.peach || "#fab387"
    readonly property color red: _theme.red || "#f38ba8"

    readonly property string fontFamily: "Hack Nerd Font"

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) }

    // --- live metrics (fetch.sh) ---------------------------------------------
    property real cpuPct: 0
    property real ramPct: 0
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property real diskPct: 0
    property string diskUsed: "--"
    property string diskTotal: "--"
    property real tempC: 0
    property int procVal: 0
    property string uptimeVal: "--"
    property string rxStr: "0 B"
    property string txStr: "0 B"

    function fetchData() {
        runner.running = false
        runner.running = true
    }

    function formatBytes(bytes) {
        if (!bytes || bytes === 0) return "0 B"
        let u = ["B", "KB", "MB", "GB", "TB"]; let i = 0; let v = bytes
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
        return v.toFixed(i < 2 ? 0 : 1) + " " + u[i]
    }

    Process {
        id: runner
        running: true
        command: ["bash", "-c", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/ui/bar/popups/system-monitor/fetch.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (!this.text || this.text.trim().length === 0) return
                    let d = JSON.parse(this.text.trim())
                    window.cpuPct = Math.max(0, Math.min(100, d.cpu || 0))
                    window.ramPct = Math.max(0, Math.min(100, d.ram_pct || 0))
                    window.ramUsedGb = (d.ram_used || 0) / 1024
                    window.ramTotalGb = (d.ram_total || 0) / 1024
                    window.diskPct = Math.max(0, Math.min(100, d.disk_pct || 0))
                    window.diskUsed = d.disk_used || "--"
                    window.diskTotal = d.disk_total || "--"
                    window.tempC = d.temp || 0
                    window.procVal = d.procs || 0
                    window.uptimeVal = d.uptime || "--"
                    window.rxStr = window.formatBytes(d.rx_bytes)
                    window.txStr = window.formatBytes(d.tx_bytes)
                } catch (e) {
                    console.log("sysmon parse:", e)
                }
            }
        }
    }

    Timer {
        interval: Personalization.value("system-monitor", Config.rawSettings["system-monitor"], "pollMs") || 5000
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: window.fetchData()
    }

    // Gentle entrance so the popup feels part of the shell morph.
    property real intro: 0
    NumberAnimation on intro {
        from: 0; to: 1; duration: 650; easing.type: Easing.OutQuint; running: true
    }

    // =========================================================================
    // RingGauge — reusable circular meter (mirrors the battery hero circle).
    // =========================================================================
    component RingGauge: Item {
        id: gauge

        property real value: 0
        property string glyph: ""
        property string label: ""
        property string readout: Math.round(gauge.animVal) + "%"
        property color colA: window.mauve
        property color colB: window.pink

        property real animVal: value
        Behavior on animVal { NumberAnimation { duration: 1100; easing.type: Easing.OutQuint } }
        onAnimValChanged: gaugeCanvas.requestPaint()

        scale: gaugeHover.containsMouse ? 1.05 : 1.0
        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) + (gaugeHover.containsMouse ? window.s(10) : window.s(4))
            height: width; radius: width / 2
            color: gauge.colA
            opacity: gaugeHover.containsMouse ? 0.22 : 0.07
            Behavior on opacity { NumberAnimation { duration: 300 } }
            Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }
        }

        Canvas {
            id: gaugeCanvas
            anchors.fill: parent
            rotation: 180

            Connections {
                target: window
                function onBaseChanged() { gaugeCanvas.requestPaint() }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var d = Math.min(width, height)
                var cX = width / 2
                var cY = height / 2
                var rad = (d / 2) - window.s(10)
                if (rad <= 0) return

                var eA = (Math.min(100, Math.max(0, gauge.animVal)) / 100) * 2 * Math.PI

                ctx.lineCap = "round"

                ctx.lineWidth = window.s(7)
                ctx.beginPath()
                ctx.arc(cX, cY, rad, 0, 2 * Math.PI)
                ctx.strokeStyle = Theme.surfaceContainer.toString()
                ctx.stroke()

                var grad = ctx.createLinearGradient(0, height, width, 0)
                grad.addColorStop(0, gauge.colA.toString())
                grad.addColorStop(1, gauge.colB.toString())

                ctx.lineWidth = window.s(13)
                ctx.beginPath()
                ctx.arc(cX, cY, rad, 0, eA)
                ctx.strokeStyle = grad
                ctx.stroke()
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: window.s(-2)

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: window.s(Theme.gapXs)
                Text {
                    text: gauge.glyph
                    font.family: window.fontFamily
                    font.pixelSize: window.s(16)
                    color: gauge.colA
                }
                Text {
                    text: gauge.readout
                    font.family: window.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: window.s(22)
                    color: window.text
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: gauge.label
                font.family: window.fontFamily
                font.weight: Font.Bold
                font.pixelSize: window.s(10)
                color: window.subtext0
                font.letterSpacing: 1
            }
        }

        MouseArea {
            id: gaugeHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
        }
    }

    // =========================================================================
    // StatChip — compact footer tile.
    // =========================================================================
    component StatChip: Rectangle {
        id: chip

        property string glyph: ""
        property string label: ""
        property string value: ""
        property color accent: window.mauve

        radius: window.s(Theme.radiusMd)
        color: Theme.surfaceContainer
        border.color: Theme.outlineVariant
        border.width: 1
        implicitHeight: window.s(58)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: window.s(Theme.gapMd)
            anchors.rightMargin: window.s(Theme.gapMd)
            spacing: window.s(Theme.gapSm)

            Text {
                text: chip.glyph
                font.family: window.fontFamily
                font.pixelSize: window.s(17)
                color: chip.accent
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: window.s(1)

                Text {
                    text: chip.label
                    font.family: window.fontFamily
                    font.pixelSize: window.s(9)
                    color: window.overlay0
                    Layout.fillWidth: true
                }
                Text {
                    text: chip.value
                    font.family: window.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: window.s(13)
                    color: window.text
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }
    }

    // =========================================================================
    // Shell
    // =========================================================================
    Rectangle {
        anchors.fill: parent
        radius: window.s(Theme.radiusLg)
        color: Theme.surfaceContainerLow
        border.color: Theme.outlineVariant
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: window.s(Theme.gapXl)
            spacing: window.s(Theme.gapMd)
            opacity: window.intro
            transform: Translate { y: window.s(14) * (1 - window.intro) }

            // --- header ---
            RowLayout {
                Layout.fillWidth: true
                spacing: window.s(Theme.gapSm)

                Text {
                    text: "\uF109"
                    font.family: window.fontFamily
                    font.pixelSize: window.s(17)
                    color: window.mauve
                }
                Text {
                    text: "System Monitor"
                    font.family: window.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: window.s(16)
                    color: window.text
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: window.rxStr + "  \u2193   " + window.txStr + "  \u2191"
                    font.family: window.fontFamily
                    font.pixelSize: window.s(10)
                    color: window.overlay0
                }
            }

            // --- ring gauges ---
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 2
                rowSpacing: window.s(Theme.gapLg)
                columnSpacing: window.s(Theme.gapLg)

                RingGauge {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    value: window.cpuPct
                    glyph: "\uF0E4"
                    label: "CPU"
                    colA: window.mauve
                    colB: window.pink
                }
                RingGauge {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    value: window.ramPct
                    glyph: "\uF0351"
                    label: "MEMORY"
                    colA: window.blue
                    colB: window.sapphire
                }
                RingGauge {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    value: window.diskPct
                    glyph: "\uF0A0"
                    label: "STORAGE"
                    colA: window.green
                    colB: window.teal
                }
                RingGauge {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    value: Math.max(0, Math.min(100, window.tempC))
                    glyph: "\uF2C7"
                    label: "TEMP"
                    readout: Math.round(window.tempC) + "\u00B0"
                    colA: window.peach
                    colB: window.red
                }
            }

            // --- footer stats ---
            RowLayout {
                Layout.fillWidth: true
                spacing: window.s(Theme.gapMd)

                StatChip {
                    Layout.fillWidth: true
                    glyph: "\uE60B"
                    label: "PROCESSES"
                    value: String(window.procVal)
                    accent: window.sapphire
                }
                StatChip {
                    Layout.fillWidth: true
                    glyph: "\uF253"
                    label: "UPTIME"
                    value: window.uptimeVal
                    accent: window.yellow
                }
                StatChip {
                    Layout.fillWidth: true
                    glyph: "\uF0A0"
                    label: "DISK"
                    value: window.diskUsed + " / " + window.diskTotal
                    accent: window.green
                }
            }
        }
    }
}
