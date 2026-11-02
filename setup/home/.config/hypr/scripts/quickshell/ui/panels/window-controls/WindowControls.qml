import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../../core"
import "../../bar"

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
    readonly property color blue: _theme.blue || "#89b4fa"
    readonly property color green: _theme.green || "#a6e3a1"
    readonly property color peach: _theme.peach || "#fab387"
    readonly property color sapphire: _theme.sapphire || "#74c7ec"
    readonly property color red: _theme.red || "#f38ba8"

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) }

    // The 12 knobs live in the shared HyprEffects singleton (same kernel as
    // the BarEditor Hyprland tab): robust live read + partial live apply.
    readonly property var fx: HyprEffects.values

    property bool isDirty: false

    // Re-read the live values every time the widget opens; persist the Lua
    // overrides on close (one Hyprland auto-reload, not one per knob).
    Component.onCompleted: HyprEffects.refresh()
    Component.onDestruction: HyprEffects.persist()

    // Changes preview live (debounced) through HyprEffects; Save persists the
    // Lua overrides now and clears the dirty dot.
    function saveChanges() {
        HyprEffects.persist()
        window.isDirty = false
    }

    function resetDefaults() {
        HyprEffects.resetEffects()
        window.isDirty = true
    }

    function markDirty() { window.isDirty = true }

    Rectangle {
        anchors.fill: parent; color: Theme.surfaceContainerLow; radius: Theme.radiusLg

        ColumnLayout {
            anchors.fill: parent; anchors.margins: Theme.gapLg; spacing: Theme.gapSm

            RowLayout {
                Layout.fillWidth: true
                Text { text: "\uF2D0  Window Effects"; font.family: "Hack Nerd Font"; font.pixelSize: s(15); font.weight: Font.Bold; color: window.text }
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredWidth: s(28); Layout.preferredHeight: s(28); radius: Theme.radiusSm
                    color: window.red; opacity: window.isDirty ? 0.25 : 0.08
                    Text { anchors.centerIn: parent; text: "\uF0E2"; font.family: "Hack Nerd Font"; font.pixelSize: s(12); color: window.red; opacity: window.isDirty ? 1.0 : 0.4 }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: resetDefaults() }
                }
                Rectangle {
                    Layout.preferredWidth: s(56); Layout.preferredHeight: s(28); radius: Theme.radiusSm
                    color: window.green; opacity: window.isDirty ? 0.85 : 0.15
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    RowLayout { anchors.centerIn: parent; spacing: Theme.gapXs
                        Text { text: "\uF0C7"; font.family: "Hack Nerd Font"; font.pixelSize: s(12); color: window.isDirty ? window.crust : window.green }
                        Text { text: "Save"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); font.weight: Font.Bold; color: window.isDirty ? window.crust : window.green }
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: if (window.isDirty) saveChanges() }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: s(1);                 color: Theme.outlineVariant; opacity: 0.25 }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF06E"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.mauve; Layout.preferredWidth: s(20) }
                Text { text: "Active Opacity"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: aoDs; from: 0.3; to: 1.0; step: 0.05; initial: fx.active_opacity; barColor: window.mauve
                    onDragged: function(v) { HyprEffects.set("active_opacity", v); markDirty() }
                }
                Text { text: aoDs.current.toFixed(2); font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF070"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.blue; Layout.preferredWidth: s(20) }
                Text { text: "Inactive Opacity"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: ioDs; from: 0.3; to: 1.0; step: 0.05; initial: fx.inactive_opacity; barColor: window.blue
                    onDragged: function(v) { HyprEffects.set("inactive_opacity", v); markDirty() }
                }
                Text { text: ioDs.current.toFixed(2); font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: s(1);                 color: Theme.outlineVariant; opacity: 0.2 }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF192"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.green; Layout.preferredWidth: s(20) }
                Text { text: "Rounding"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: roDs; from: 0; to: 35; step: 1; initial: fx.rounding; barColor: window.green
                    onDragged: function(v) { HyprEffects.set("rounding", v); markDirty() }
                }
                Text { text: Math.round(roDs.current) + "px"; font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: s(1);                 color: Theme.outlineVariant; opacity: 0.2 }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF0EB"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.peach; Layout.preferredWidth: s(20) }
                Text { text: "Blur Size"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: bsDs; from: 0; to: 24; step: 1; initial: fx.blur_size; barColor: window.peach
                    onDragged: function(v) { HyprEffects.set("blur_size", v); markDirty() }
                }
                Text { text: Math.round(bsDs.current) + "px"; font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF2C8"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.sapphire; Layout.preferredWidth: s(20) }
                Text { text: "Blur Passes"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: bpDs; from: 0; to: 10; step: 1; initial: fx.blur_passes; barColor: window.sapphire
                    onDragged: function(v) { HyprEffects.set("blur_passes", v); markDirty() }
                }
                Text { text: Math.round(bpDs.current); font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: s(1);                 color: Theme.outlineVariant; opacity: 0.2 }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF239"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.mauve; Layout.preferredWidth: s(20) }
                Text { text: "Gaps In"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: giDs; from: 0; to: 50; step: 2; initial: fx.gaps_in; barColor: window.mauve
                    onDragged: function(v) { HyprEffects.set("gaps_in", v); markDirty() }
                }
                Text { text: Math.round(giDs.current) + "px"; font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF108"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.blue; Layout.preferredWidth: s(20) }
                Text { text: "Gaps Out"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: goDs; from: 0; to: 50; step: 2; initial: fx.gaps_out; barColor: window.blue
                    onDragged: function(v) { HyprEffects.set("gaps_out", v); markDirty() }
                }
                Text { text: Math.round(goDs.current) + "px"; font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF358"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.peach; Layout.preferredWidth: s(20) }
                Text { text: "Border Width"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: bwDs; from: 0; to: 20; step: 1; initial: fx.border_size; barColor: window.peach
                    onDragged: function(v) { HyprEffects.set("border_size", v); markDirty() }
                }
                Text { text: Math.round(bwDs.current) + "px"; font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: s(1);                 color: Theme.outlineVariant; opacity: 0.2 }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF042"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.peach; Layout.preferredWidth: s(20) }
                Text { text: "Shadow Range"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: srDs; from: 0; to: 50; step: 1; initial: fx.shadow_range; barColor: window.peach
                    onDragged: function(v) { HyprEffects.set("shadow_range", v); markDirty() }
                }
                Text { text: Math.round(srDs.current) + "px"; font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF0E7"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.sapphire; Layout.preferredWidth: s(20) }
                Text { text: "Shadow Power"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: spDs; from: 0; to: 10; step: 1; initial: fx.shadow_render_power; barColor: window.sapphire
                    onDragged: function(v) { HyprEffects.set("shadow_render_power", v); markDirty() }
                }
                Text { text: Math.round(spDs.current); font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF061"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.mauve; Layout.preferredWidth: s(20) }
                Text { text: "Shadow Offset X"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: soxDs; from: -30; to: 30; step: 1; initial: fx.shadow_offset_x; barColor: window.mauve
                    onDragged: function(v) { HyprEffects.set("shadow_offset_x", v); markDirty() }
                }
                Text { text: Math.round(soxDs.current) + "px"; font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }

            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: s(44); spacing: Theme.gapSm
                Text { text: "\uF063"; font.family: "Hack Nerd Font"; font.pixelSize: s(14); color: window.green; Layout.preferredWidth: s(20) }
                Text { text: "Shadow Offset Y"; font.family: "Hack Nerd Font"; font.pixelSize: s(11); color: window.subtext0; Layout.preferredWidth: s(100) }
                DragSlider { id: soyDs; from: -30; to: 30; step: 1; initial: fx.shadow_offset_y; barColor: window.green
                    onDragged: function(v) { HyprEffects.set("shadow_offset_y", v); markDirty() }
                }
                Text { text: Math.round(soyDs.current) + "px"; font.family: "Hack Nerd Font"; font.pixelSize: s(12); font.weight: Font.Bold; color: window.text; Layout.preferredWidth: s(45); horizontalAlignment: Text.AlignRight }
            }
        }
    }

    component DragSlider: Rectangle {
        id: dslider
        property real from: 0; property real to: 1; property real step: 0.05
        property real initial: 0.5; property color barColor: window.mauve
        property real current: initial
        signal dragged(real val)

        Layout.fillWidth: true; Layout.preferredHeight: s(30)
        radius: Theme.radiusSm; color: Theme.surfaceContainerHigh

        Rectangle {
            id: fillBar
            height: parent.height; radius: Theme.radiusSm
            color: dslider.barColor; opacity: 0.5
            width: parent.width * ((dslider.current - dslider.from) / (dslider.to - dslider.from))
            Behavior on width { enabled: !dragArea.pressed; NumberAnimation { duration: 80 } }
        }

        Rectangle {
            id: knob
            y: (parent.height - height) / 2
            width: s(18); height: s(18); radius: width / 2
            color: dslider.barColor
            scale: dragArea.containsMouse || dragArea.pressed ? 1.2 : 1.0
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
            x: Math.max(0, Math.min(parent.width - width, parent.width * ((dslider.current - dslider.from) / (dslider.to - dslider.from)) - width / 2))
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            property real startX: 0
            property real startVal: 0

            onPressed: function(mouse) {
                startX = mouse.x
                startVal = dslider.current
                updateFromMouse(mouse.x)
            }
            onPositionChanged: function(mouse) {
                if (pressed) updateFromMouse(mouse.x)
            }
            function updateFromMouse(mx) {
                let frac = Math.max(0, Math.min(1, mx / parent.width))
                let range = dslider.to - dslider.from
                let raw = dslider.from + frac * range
                let stepped = Math.round(raw / dslider.step) * dslider.step
                stepped = Math.max(dslider.from, Math.min(dslider.to, stepped))
                dslider.current = stepped
                dslider.dragged(stepped)
            }
        }
    }
}
