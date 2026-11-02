import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../edit"
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// ShadowsPage — BarEditor tab (Theme group): drop shadows for popups/menus.
//
// The shadow is drawn in QML by the host (ui/Main.qml, RectangularShadow):
// Hyprland does not decorate layer-shell surfaces, so `decoration:shadow`
// does not reach the shell's panels. This page edits the settings.json
// "shadows" section; Main is reactive (Config.rev) so changes apply live.
// Each panel may expose `shadowRadius` to follow its own corners (the app
// launcher does); otherwise the global radius applies.
//
// Contract: receives the BarEditor root as `bar` (bar.s(), bar.colors).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent

    property var bar: null

    // Same defaults Main falls back to when settings.json has no "shadows".
    property bool shEnabled: true
    property real shBlur: 26
    property real shSpread: 0
    property real shOffsetX: 0
    property real shOffsetY: 6
    property real shOpacity: 0.5
    property real shRadius: 18

    readonly property var flickable: body.item ? body.item.flickable : null

    function syncFromConfig() {
        let s = (Config.rawSettings.shadows && typeof Config.rawSettings.shadows === "object")
                ? Config.rawSettings.shadows : {};
        root.shEnabled = s.enabled !== false;
        root.shBlur = s.blur !== undefined ? s.blur : 26;
        root.shSpread = s.spread !== undefined ? s.spread : 0;
        root.shOffsetX = s.offsetX !== undefined ? s.offsetX : 0;
        root.shOffsetY = s.offsetY !== undefined ? s.offsetY : 6;
        root.shOpacity = s.opacity !== undefined ? s.opacity : 0.5;
        root.shRadius = s.radius !== undefined ? s.radius : 18;
    }
    Component.onCompleted: root.syncFromConfig()

    // Debounced commit into settings.json "shadows" (drag friendly).
    property var _pending: ({})
    Timer { id: saveTimer; interval: 300; onTriggered: root.flush() }
    function set(key, v) {
        root._pending[key] = v;
        saveTimer.restart();
    }
    function flush() {
        let keys = Object.keys(root._pending);
        if (keys.length === 0) return;
        let base = (Config.rawSettings.shadows && typeof Config.rawSettings.shadows === "object")
                   ? Config.rawSettings.shadows : {};
        Config.setSetting("shadows", Object.assign({}, base, root._pending));
        root._pending = {};
    }
    Component.onDestruction: root.flush()

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

                    Text {
                        text: "Shadows"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }
                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Drop shadow for popups and menus, drawn by the shell (Hyprland does not decorate layer-shell surfaces). Applies live."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF5A8"
                        label: "Enabled"
                        checked: root.shEnabled
                        onToggled: { root.shEnabled = !root.shEnabled; root.set("enabled", root.shEnabled); }
                    }

                    Text {
                        text: "Shape"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF0EB"
                        label: "Blur"
                        from: 0; to: 60; step: 2
                        suffix: "px"
                        accentColor: bar.colors.peach
                        value: root.shBlur
                        onEdited: (v) => { root.shBlur = v; root.set("blur", v); }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF2C8"
                        label: "Spread"
                        from: -10; to: 20; step: 1
                        suffix: "px"
                        accentColor: bar.colors.sapphire
                        value: root.shSpread
                        onEdited: (v) => { root.shSpread = v; root.set("spread", v); }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF192"
                        label: "Corner radius"
                        from: 0; to: 30; step: 1
                        suffix: "px"
                        accentColor: bar.colors.green
                        value: root.shRadius
                        onEdited: (v) => { root.shRadius = v; root.set("radius", v); }
                    }

                    Text {
                        text: "Placement"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF061"
                        label: "Offset X"
                        from: -40; to: 40; step: 2
                        suffix: "px"
                        accentColor: bar.colors.mauve
                        value: root.shOffsetX
                        onEdited: (v) => { root.shOffsetX = v; root.set("offsetX", v); }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF063"
                        label: "Offset Y"
                        from: -40; to: 40; step: 2
                        suffix: "px"
                        accentColor: bar.colors.blue
                        value: root.shOffsetY
                        onEdited: (v) => { root.shOffsetY = v; root.set("offsetY", v); }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF06E"
                        label: "Opacity"
                        from: 0; to: 1.0; step: 0.05
                        decimals: 2
                        accentColor: bar.colors.sapphire
                        value: root.shOpacity
                        onEdited: (v) => { root.shOpacity = v; root.set("opacity", v); }
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Panels can follow their own corners (the app launcher does); the rest use the global radius. The bar draws its own shadows too (island capsules and the optional strip); notifications and the lock screen are separate surfaces and are not covered."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
