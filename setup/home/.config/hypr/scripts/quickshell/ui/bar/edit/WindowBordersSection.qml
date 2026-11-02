import QtQuick
import QtQuick.Layouts
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// WindowBordersSection — shared "Window borders" block for the BarEditor
// (Bar → Style page and Hyprland page).
//
// Edits settings.json bar.{borderFollowPalette, borderActive, borderInactive,
// borderGradient*, borderAngle*}; Colors.qml re-reads settings.json and pushes
// the border values live through the compositor adapter (hyprctl eval, no
// window restart). colors.lua builds the same value when Hyprland loads its
// config, so the choice survives reloads/restarts.
//
//   · Follow palette ON  → active = palette accent (color1), inactive =
//                          palette muted (color8).
//   · Follow palette OFF → pick any of the 16 palette colors for the
//                          active/inactive border. Optional two-stop gradient
//                          per border: second palette color + angle.
//
// API: bar      — the BarEditor root (bar.bar config, bar.colors,
//                 bar.applyBar, bar.borderTargetActive, bar.s()).
//      titlePx  — section title size (Style page uses 24, Hyprland 16).
// ═══════════════════════════════════════════════════════════════════════════

Column {
    id: section

    property var bar: null
    property int titlePx: 24

    readonly property bool customMode: section.bar ? section.bar.bar.borderFollowPalette === false : false
    readonly property bool targetActive: section.bar ? section.bar.borderTargetActive : true
    readonly property bool gradientOn: section.bar
        ? (section.targetActive ? section.bar.bar.borderGradientActive === true
                                : section.bar.bar.borderGradientInactive === true)
        : false
    readonly property string firstHex: section.bar
        ? section.bar.colors.borderHex(section.targetActive ? "active" : "inactive")
        : "#000000"
    readonly property string secondHex: section.bar
        ? (section.targetActive ? (section.bar.bar.borderActive2 || "")
                                : (section.bar.bar.borderInactive2 || ""))
        : ""
    readonly property int gradientAngle: section.bar
        ? (section.targetActive ? section.bar.bar.borderAngleActive : section.bar.bar.borderAngleInactive)
        : 45

    function apply(patch) {
        if (!section.bar) return;
        section.bar.applyBar(Object.assign({}, section.bar.bar, patch));
    }

    width: parent ? parent.width : 400
    spacing: section.bar ? section.bar.s(Theme.gapMd) : Theme.gapMd

    Text {
        text: "Window borders"
        font.family: "Hack Nerd Font"
        font.weight: Font.Black
        font.pixelSize: section.bar ? section.bar.s(section.titlePx) : section.titlePx
        color: section.bar ? section.bar.colors.text : "transparent"
    }

    ToggleCard {
        width: parent.width
        bar: section.bar
        icon: "󰢮"
        label: "Follow palette"
        checked: section.bar && section.bar.bar.borderFollowPalette !== false
        onToggled: section.apply({ borderFollowPalette: !(section.bar && section.bar.bar.borderFollowPalette !== false) })
    }

    // Active/inactive target (only when not following the palette)
    GridLayout {
        width: parent.width
        columns: 2
        columnSpacing: section.bar ? section.bar.s(Theme.gapSm) : Theme.gapSm
        rowSpacing: section.bar ? section.bar.s(Theme.gapSm) : Theme.gapSm
        visible: section.customMode
        OptionCard {
            Layout.fillWidth: true
            bar: section.bar
            icon: "◉"
            label: "Active"
            active: section.targetActive
            onActivated: if (section.bar) section.bar.borderTargetActive = true
        }
        OptionCard {
            Layout.fillWidth: true
            bar: section.bar
            icon: "○"
            label: "Inactive"
            accentRole: "blue"
            active: !section.targetActive
            onActivated: if (section.bar) section.bar.borderTargetActive = false
        }
    }

    // First stop: base16 swatch grid (only when not following the palette)
    SwatchGrid {
        width: parent.width
        bar: section.bar
        settingsKey: section.targetActive ? "borderActive" : "borderInactive"
        current: section.firstHex
        visible: section.customMode
    }

    // Gradient toggle per target (custom mode only)
    ToggleCard {
        width: parent.width
        bar: section.bar
        icon: "󰹹"
        label: "Gradient"
        visible: section.customMode
        checked: section.gradientOn
        onToggled: {
            if (!section.bar) return;
            let active = section.targetActive;
            let on = !section.gradientOn;
            let patch = {};
            if (active) patch.borderGradientActive = on;
            else patch.borderGradientInactive = on;
            // First activation: seed the second stop with a palette accent so
            // the gradient shows up immediately instead of falling back solid.
            if (on) {
                let cur2 = active ? section.bar.bar.borderActive2 : section.bar.bar.borderInactive2;
                if (!/^#[0-9a-fA-F]{6}$/.test(cur2 || "")) {
                    let seed = section.bar.colors.hexOf(section.bar.colors.mauve);
                    if (active) patch.borderActive2 = seed;
                    else patch.borderInactive2 = seed;
                }
            }
            section.apply(patch);
        }
    }

    // Second stop (gradient on only)
    EditLabel {
        bar: section.bar
        width: parent.width
        visible: section.customMode && section.gradientOn
        text: "Second color"
        font.pixelSize: section.bar ? section.bar.s(12) : 12
        color: section.bar ? section.bar.colors.subtext0 : "transparent"
    }
    SwatchGrid {
        width: parent.width
        bar: section.bar
        settingsKey: section.targetActive ? "borderActive2" : "borderInactive2"
        current: section.secondHex
        visible: section.customMode && section.gradientOn
    }

    // Angle (gradient on only)
    EffectSlider {
        width: parent.width
        visible: section.customMode && section.gradientOn
        bar: section.bar
        icon: "󰕦"
        label: "Gradient angle"
        from: 0; to: 360; step: 15
        suffix: "°"
        accentColor: section.bar ? section.bar.colors.mauve : "#cba6f7"
        value: section.gradientAngle
        onEdited: (v) => section.apply(section.targetActive ? { borderAngleActive: v } : { borderAngleInactive: v })
    }

    // Selected color preview (only when not following the palette)
    RowLayout {
        width: parent.width
        spacing: section.bar ? section.bar.s(Theme.gapSm) : Theme.gapSm
        visible: section.customMode
        EditLabel {
            bar: section.bar
            text: (section.targetActive ? "Active" : "Inactive")
                + (section.gradientOn ? " · " + section.gradientAngle + "°" : "")
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }
        Rectangle {
            Layout.preferredWidth: section.bar ? section.bar.s(92) : 92
            Layout.preferredHeight: section.bar ? section.bar.s(30) : 30
            Layout.alignment: Qt.AlignVCenter
            radius: section.bar ? section.bar.s(Theme.radiusMd) : Theme.radiusMd
            color: section.firstHex
            gradient: (section.gradientOn && /^#[0-9a-fA-F]{6}$/.test(section.secondHex)) ? previewGradient : null
            border.width: 1
            border.color: section.bar ? Theme.outlineVariant : "transparent"
            Gradient {
                id: previewGradient
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: section.firstHex }
                GradientStop { position: 1.0; color: section.secondHex }
            }
        }
    }

    // Caption while following the palette
    EditLabel {
        bar: section.bar
        width: parent.width
        visible: section.bar && section.bar.bar.borderFollowPalette !== false
        text: "Borders follow the active palette accent. Turn this off to pick custom colors (or a two-stop gradient) — applies live, no window restart)."
        font.pixelSize: section.bar ? section.bar.s(12) : 12
        color: section.bar ? section.bar.colors.subtext0 : "transparent"
        wrapMode: Text.WordWrap
    }

    // 16-color base16 grid that writes the color into `settingsKey`.
    component SwatchGrid: GridLayout {
        id: swatchGrid
        property var bar: null
        property string settingsKey: "borderActive"
        property string current: ""
        columns: 8
        columnSpacing: swatchGrid.bar ? swatchGrid.bar.s(Theme.gapSm) : Theme.gapSm
        rowSpacing: swatchGrid.bar ? swatchGrid.bar.s(Theme.gapSm) : Theme.gapSm
        Repeater {
            model: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
            delegate: Rectangle {
                id: swatch
                required property int modelData
                readonly property string hex: swatchGrid.bar ? swatchGrid.bar.colors.hexOf(swatchGrid.bar.colors["color" + modelData]) : ""
                readonly property bool isSel: swatchGrid.current.toLowerCase() === hex
                width: swatchGrid.bar ? swatchGrid.bar.s(24) : 24
                height: width
                radius: swatchGrid.bar ? swatchGrid.bar.s(Theme.radiusSm) : Theme.radiusSm
                color: swatchGrid.bar ? swatchGrid.bar.colors["color" + modelData] : "transparent"
                border.width: isSel ? 2 : 1
                border.color: isSel ? swatchGrid.bar.colors.text : (swMa.containsMouse ? swatchGrid.bar.colors.mauve : Theme.outlineVariant)
                Behavior on border.color { ColorAnimation { duration: 150 } }
                MouseArea {
                    id: swMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (swatchGrid.bar) {
                        let patch = {};
                        patch[swatchGrid.settingsKey] = swatch.hex;
                        swatchGrid.bar.applyBar(Object.assign({}, swatchGrid.bar.bar, patch));
                    }
                }
            }
        }
    }
}
