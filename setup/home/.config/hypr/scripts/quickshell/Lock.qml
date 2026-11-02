import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "core"
import "core/Personalization.js" as Personalization
import "ui/bar"

// ═══════════════════════════════════════════════════════════════════════════
// equisdots · lock — minimalist palette-aware lock screen.
//
// Same language as the login: the (current) user, a password field with an
// expanding underline and a clock right below; the wallpaper currently set
// (the still qs-wallpaperpicker's wallpaper-apply keeps) is blurred behind.
//
// Personalizable from settings.json -> "lock" (see core/Personalization.js):
// blur amount, dim, clock/battery/power visibility and clock scale. Palette
// driven through the local Colors instance.
// ═══════════════════════════════════════════════════════════════════════════
ShellRoot {
    id: root

    Caching { id: paths }
    Colors { id: _theme }

    readonly property color base: _theme.base
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color red: _theme.red

    // ── Personalization (settings.json -> "lock") ─────────────────────────
    readonly property int revealDuration: Personalization.value("lock", Config.rawSettings.lock, "revealDurationMs")
    readonly property int clockPollMs: Personalization.value("lock", Config.rawSettings.lock, "clockPollMs")
    readonly property int batteryPollMs: Personalization.value("lock", Config.rawSettings.lock, "batteryPollMs")
    readonly property real wallpaperBlur: Math.max(0, Math.min(1, Personalization.value("lock", Config.rawSettings.lock, "wallpaperBlur")))
    readonly property real wallpaperDim: Math.max(0, Math.min(0.85, Personalization.value("lock", Config.rawSettings.lock, "wallpaperDim")))
    readonly property bool showClock: Personalization.value("lock", Config.rawSettings.lock, "showClock")
    readonly property bool showBattery: Personalization.value("lock", Config.rawSettings.lock, "showBattery")
    readonly property bool showPower: Personalization.value("lock", Config.rawSettings.lock, "showPower")
    readonly property real clockScale: Math.max(0.6, Math.min(1.6, Personalization.value("lock", Config.rawSettings.lock, "clockScale")))

    // ── Shared state ──────────────────────────────────────────────────────
    QtObject {
        id: lockUI
        property bool failed: false
        property bool authenticating: false
    }

    property date now: new Date()
    property bool isDesktop: true
    property int batPercent: 100
    property string batStatus: "AC"

    function batteryGlyph() {
        if (root.batStatus === "Charging") return "󰂅";
        if (root.batPercent >= 90) return "󰁹";
        if (root.batPercent >= 70) return "󰂀";
        if (root.batPercent >= 50) return "󰁾";
        if (root.batPercent >= 30) return "󰁼";
        if (root.batPercent >= 15) return "󰁺";
        return "󰂃";
    }

    Timer {
        interval: root.clockPollMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    Process {
        id: batPoller
        command: ["bash", "-c",
            "if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then " +
            "echo laptop; cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1; " +
            "cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1; " +
            "else echo desktop; echo 100; echo AC; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = this.text.trim().split("\n");
                root.isDesktop = (l[0] || "desktop").trim() === "desktop";
                root.batPercent = parseInt(l[1] || "100", 10);
                root.batStatus = (l[2] || "AC").trim();
            }
        }
    }

    Timer {
        interval: root.batteryPollMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { batPoller.running = false; batPoller.running = true; }
    }

    Process { id: poweroffProcess; command: ["systemctl", "poweroff"] }
    Process { id: rebootProcess; command: ["systemctl", "reboot"] }

    // ── Authentication (PAM) ──────────────────────────────────────────────
    Timer {
        id: pamActionTimer
        interval: 150
        onTriggered: pam.start()
    }

    PamContext {
        id: pam
        // Defer start until after component initialization (avoids startup races).
        Component.onCompleted: pamActionTimer.start()

        onCompleted: (result) => {
            lockUI.authenticating = false;
            if (result === PamResult.Success) {
                rootLock.locked = false;
                Qt.quit();
            } else {
                lockUI.failed = true;
                pamActionTimer.start();
            }
        }
    }

    // Minimal circular button used by the power row.
    component PowerButton: Rectangle {
        id: pb
        property string glyph: ""
        signal clicked()
        Layout.preferredWidth: Math.round(34 * screenRoot.sc)
        Layout.preferredHeight: Math.round(34 * screenRoot.sc)
        radius: width / 2
        color: pbMa.containsMouse ? Qt.alpha(root.text, 0.08) : "transparent"
        border.width: 1
        border.color: pbMa.containsMouse ? Qt.alpha(root.text, 0.25) : Qt.alpha(root.text, 0.10)
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
        Text {
            anchors.centerIn: parent
            text: pb.glyph
            font.family: "Hack Nerd Font"
            font.pixelSize: Math.round(17 * screenRoot.sc)
            color: pbMa.containsMouse ? root.text : root.subtext0
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        MouseArea {
            id: pbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }

    WlSessionLock {
        id: rootLock
        locked: true

        WlSessionLockSurface {
            id: surface

            Item {
                id: screenRoot
                anchors.fill: parent

                Scaler {
                    id: scaler
                    currentWidth: screenRoot.width > 0 ? screenRoot.width : Screen.width
                    currentHeight: screenRoot.height > 0 ? screenRoot.height : Screen.height
                }
                readonly property real sc: scaler.baseScale

                // Intro reveal (also gates the input focus).
                property real intro: 0
                NumberAnimation on intro {
                    to: 1.0
                    duration: root.revealDuration
                    easing.type: Easing.OutQuart
                    running: true
                    onFinished: inputField.forceActiveFocus()
                }

                // The wallpaper currently set: the still the picker's wallpaper-apply keeps
                // (audit 2026-10-31: the old picker's cache no longer exists).
                readonly property string staticWallpaperPath: "file://" + Quickshell.env("HOME") + "/.cache/current_wallpaper"

                Image {
                    id: bgWallpaper
                    anchors.fill: parent
                    source: screenRoot.staticWallpaperPath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    visible: false
                }
                MultiEffect {
                    anchors.fill: bgWallpaper
                    source: bgWallpaper
                    blurEnabled: root.wallpaperBlur > 0
                    blurMax: 64
                    blur: root.wallpaperBlur
                }
                Rectangle {
                    anchors.fill: parent
                    color: root.base
                    opacity: root.wallpaperDim
                }

                // ── Center: user + password + clock + power ───────────────
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.round(320 * screenRoot.sc)
                    spacing: Math.round(24 * screenRoot.sc)
                    opacity: screenRoot.intro
                    transform: Translate { y: Math.round(12 * screenRoot.sc) * (1 - screenRoot.intro) }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Quickshell.env("USER") || "user"
                        color: root.text
                        font.family: "Hack Nerd Font"
                        font.pixelSize: Math.round(18 * screenRoot.sc)
                        font.weight: Font.Bold
                    }

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.round(300 * screenRoot.sc)
                        Layout.preferredHeight: Math.round(46 * screenRoot.sc)
                        transform: Translate { id: shakeTranslate; x: 0 }

                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: shakeTranslate; property: "x"; from: 0; to: -8 * screenRoot.sc; duration: 120; easing.type: Easing.InOutSine }
                            NumberAnimation { target: shakeTranslate; property: "x"; from: -8 * screenRoot.sc; to: 8 * screenRoot.sc; duration: 120; easing.type: Easing.InOutSine }
                            NumberAnimation { target: shakeTranslate; property: "x"; from: 8 * screenRoot.sc; to: 0; duration: 120; easing.type: Easing.InOutSine }
                        }

                        Connections {
                            target: lockUI
                            function onFailedChanged() { if (lockUI.failed) shakeAnim.restart(); }
                        }

                        TextInput {
                            id: inputField
                            anchors.fill: parent
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            font.family: "Hack Nerd Font"
                            font.pixelSize: Math.round(20 * screenRoot.sc)
                            color: lockUI.failed ? root.red : root.text
                            clip: true
                            selectByMouse: true
                            enabled: screenRoot.intro > 0.95
                            Behavior on color { ColorAnimation { duration: 220 } }

                            Text {
                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "password"
                                color: Qt.alpha(root.text, 0.30)
                                font: inputField.font
                                visible: !inputField.text && !inputField.inputMethodComposing
                            }

                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Escape) {
                                    text = "";
                                    event.accepted = true;
                                }
                            }
                            onAccepted: {
                                if (text.length > 0 && pam.responseRequired && !lockUI.authenticating) {
                                    lockUI.authenticating = true;
                                    lockUI.failed = false;
                                    pam.respond(text);
                                    text = "";
                                }
                            }
                            onTextChanged: { if (lockUI.failed) lockUI.failed = false; }
                            onActiveFocusChanged: {
                                if (!activeFocus && screenRoot.intro > 0.95) forceActiveFocus();
                            }
                        }

                        // Underline: grows from the center when focused.
                        Rectangle {
                            id: underline
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: Math.max(1, Math.round(2 * screenRoot.sc))
                            radius: height / 2
                            width: inputField.activeFocus ? parent.width : Math.round(220 * screenRoot.sc)
                            color: lockUI.failed ? root.red
                                 : (inputField.activeFocus ? root.text : Qt.alpha(root.text, 0.28))
                            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 220 } }
                        }
                    }

                    Text {
                        id: statusText
                        Layout.alignment: Qt.AlignHCenter
                        text: lockUI.failed ? "access denied" : (lockUI.authenticating ? "authenticating…" : "")
                        color: lockUI.failed ? root.red : root.subtext0
                        font.family: "Hack Nerd Font"
                        font.pixelSize: Math.round(12 * screenRoot.sc)
                        opacity: text !== "" ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }
                    }

                    // Clock, right below the login fields.
                    ColumnLayout {
                        visible: root.showClock
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Math.round(8 * screenRoot.sc)
                        spacing: Math.round(2 * screenRoot.sc)
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatDateTime(root.now, "HH:mm")
                            color: root.text
                            font.family: "Hack Nerd Font"
                            font.weight: Font.Black
                            font.pixelSize: Math.round(44 * screenRoot.sc * root.clockScale)
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatDateTime(root.now, "dddd, d MMMM")
                            color: root.subtext0
                            font.family: "Hack Nerd Font"
                            font.pixelSize: Math.round(13 * screenRoot.sc)
                        }
                    }

                    RowLayout {
                        visible: root.showPower
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Math.round(6 * screenRoot.sc)
                        spacing: Math.round(16 * screenRoot.sc)
                        PowerButton {
                            glyph: "󰐥"
                            onClicked: poweroffProcess.running = true
                        }
                        PowerButton {
                            glyph: "󰜉"
                            onClicked: rebootProcess.running = true
                        }
                    }
                }

                // ── Battery chip (side, top-right; laptops) ───────────────
                Rectangle {
                    visible: root.showBattery && !root.isDesktop
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Math.round(22 * screenRoot.sc)
                    width: batRow.implicitWidth + Math.round(22 * screenRoot.sc)
                    height: Math.round(30 * screenRoot.sc)
                    radius: height / 2
                    color: Qt.alpha(root.surface0, 0.45)
                    opacity: screenRoot.intro
                    Row {
                        id: batRow
                        anchors.centerIn: parent
                        spacing: Math.round(7 * screenRoot.sc)
                        Text {
                            text: root.batteryGlyph()
                            color: root.text
                            font.family: "Hack Nerd Font"
                            font.pixelSize: Math.round(14 * screenRoot.sc)
                        }
                        Text {
                            text: root.batPercent + "%"
                            color: root.subtext0
                            font.family: "Hack Nerd Font"
                            font.pixelSize: Math.round(12 * screenRoot.sc)
                        }
                    }
                }
            }
        }
    }
}
