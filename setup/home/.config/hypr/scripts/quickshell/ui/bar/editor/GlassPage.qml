import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../edit"
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// GlassPage — BarEditor tab (Theme group): glassmorphism for popups, menus
// and the bar.
//
// The backdrop blur itself is a Hyprland layer rule (`hyprland/config/
// layers.lua`, blur = true + ignore_alpha) using the Blur Size / Passes from
// the Hyprland tab. This page edits the settings.json "glass" section, which
// the shell's Colors/Theme singletons apply as background alpha: `base`
// becomes translucent while cards (surface*) stay opaque, so text stays
// legible. Applies live (settings watcher + forced palette re-apply).
//
// Contract: receives the BarEditor root as `bar` (bar.s(), bar.colors).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent

    property var bar: null

    // Same defaults the Colors/Theme singletons fall back to.
    property bool gEnabled: false
    property real gOpacity: 0.85

    readonly property var flickable: body.item ? body.item.flickable : null

    function syncFromConfig() {
        // Live source: the editor's Colors instance watches settings.json, so
        // external edits are reflected too (Config is read once at startup).
        let s = (root.bar && root.bar.colors && root.bar.colors.glassSettings)
                ? root.bar.colors.glassSettings : {};
        root.gEnabled = s.enabled === true;
        root.gOpacity = s.opacity !== undefined ? s.opacity : 0.85;
    }
    Component.onCompleted: root.syncFromConfig()

    // Debounced commit into settings.json "glass" (drag friendly).
    property var _pending: ({})
    Timer { id: saveTimer; interval: 300; onTriggered: root.flush() }
    function set(key, v) {
        root._pending[key] = v;
        saveTimer.restart();
    }
    function flush() {
        let keys = Object.keys(root._pending);
        if (keys.length === 0) return;
        let base = (root.bar && root.bar.colors && root.bar.colors.glassSettings)
                   ? root.bar.colors.glassSettings : {};
        Config.setSetting("glass", Object.assign({}, base, root._pending));
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
                        text: "Glass"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }
                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Translucent backgrounds for popups, menus and the bar. The backdrop blur comes from a Hyprland layer rule (config/hypr/layers.lua) using the Blur Size / Passes from the Hyprland tab. Cards stay opaque so text remains legible."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF853"
                        label: "Enabled"
                        checked: root.gEnabled
                        onToggled: { root.gEnabled = !root.gEnabled; root.set("enabled", root.gEnabled); }
                    }

                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "\uF06E"
                        label: "Background opacity"
                        from: 0.4; to: 1.0; step: 0.05
                        decimals: 2
                        accentColor: bar.colors.mauve
                        value: root.gOpacity
                        onEdited: (v) => { root.gOpacity = v; root.set("opacity", v); }
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: root.gEnabled
                            ? "Lower values = more see-through (less contrast). 0.80-0.90 is a good balance with palette backgrounds."
                            : "Enable to apply background alpha; the compositor blur rule stays loaded but is invisible while backgrounds are opaque."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
