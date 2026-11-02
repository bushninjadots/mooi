import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../edit"
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// AnimationsPage — BarEditor tab (grupo System): on/off y velocidad global de
// las animaciones de Hyprland.
//
// Las 6 curvas y las 12 animaciones base viven en animations.lua; el panel NO
// las edita: regenera config/user-animations.lua (cargado al final de
// hyprland.lua → siempre gana) con la velocidad escalada (speed = base ×
// multiplier) y recarga. El guardado es debounced en BarEditor:
// applyAnimations → persist-hypr.sh animations, 600 ms.
// Gate: el cuerpo se crea cuando `bar` ya está inyectado (initial property
// aplicada tras la creación del root), evitando bindings evaluados con null.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent

    property var bar: null

    readonly property var flickable: body.item ? body.item.flickable : null

    Loader {
        id: body
        anchors.fill: parent
        active: root.bar !== null
        sourceComponent: pageBody
    }

    Component {
        id: pageBody
        Item {
            anchors.fill: parent
            property alias flickable: pageFlick

            Flickable {
                id: pageFlick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: pageCol.height + bar.s(Theme.gapLg)
                ScrollBar.vertical: ScrollBar {
                    id: vScroll
                    width: bar.s(4)
                    policy: ScrollBar.AsNeeded
                    hoverEnabled: true
                    active: pageFlick.moving || vScroll.hovered
                    contentItem: Rectangle {
                        radius: bar.s(Theme.radiusXs)
                        color: Theme.surfaceContainerHighest
                        opacity: vScroll.active ? 1.0 : 0.45
                    }
                    background: Item {}
                }

                Column {
                    id: pageCol
                    x: bar.s(Theme.gapSm)
                    y: bar.s(Theme.gapSm)
                    width: pageFlick.width - bar.s(Theme.gapLg)
                    spacing: bar.s(Theme.gapLg)

                    // Título de página (GP:1007-1014)
                    Text {
                        text: "Animations"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }

                    // ── General ─────────────────────────────────────────────
                    Text {
                        text: "General"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "󰔟"
                        label: "Enabled"
                        checked: root.bar.animationsCfg.enabled
                        onToggled: root.bar.applyAnimations({ enabled: !root.bar.animationsCfg.enabled })
                    }

                    // ── Velocidad ───────────────────────────────────────────
                    Text {
                        text: "Speed"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    GridLayout {
                        width: parent.width
                        columns: 4
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "󰒮"
                            label: "Snappy"
                            active: Math.abs(root.bar.animationsCfg.speed - 0.6) < 0.01
                            onActivated: root.bar.applyAnimations({ speed: 0.6 })
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "󰐊"
                            label: "Fast"
                            active: Math.abs(root.bar.animationsCfg.speed - 0.8) < 0.01
                            onActivated: root.bar.applyAnimations({ speed: 0.8 })
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "󰓅"
                            label: "Normal"
                            active: Math.abs(root.bar.animationsCfg.speed - 1.0) < 0.01
                            onActivated: root.bar.applyAnimations({ speed: 1.0 })
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "󰒲"
                            label: "Slow"
                            active: Math.abs(root.bar.animationsCfg.speed - 1.5) < 0.01
                            onActivated: root.bar.applyAnimations({ speed: 1.5 })
                        }
                    }
                    StepperCard {
                        width: parent.width
                        bar: root.bar
                        label: "Speed ×"
                        value: Number(root.bar.animationsCfg.speed).toFixed(1) + "×"
                        onDec: root.bar.applyAnimations({
                            speed: Math.max(0.5, Math.round((root.bar.animationsCfg.speed - 0.1) * 10) / 10)
                        })
                        onInc: root.bar.applyAnimations({
                            speed: Math.min(2.0, Math.round((root.bar.animationsCfg.speed + 0.1) * 10) / 10)
                        })
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Animations come from animations.lua; the panel regenerates config/user-animations.lua with the chosen speed and reloads Hyprland. Higher speed value = slower animation."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
