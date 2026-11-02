import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../../core"
import "../edit"

// ═══════════════════════════════════════════════════════════════════════════
// AppearancePage — BarEditor tab (Theme group): the Material-You structure
// scales (shape / density / motion) that drive the design tokens in
// core/Theme.qml. Writes settings.json -> appearance.{shapeScale,densityScale,
// motionScale}; Theme watches settings.json, so every panel and widget
// re-applies live (theme-sync untouched, Hack Nerd Font untouched).
//
// Contract: receives the BarEditor root as `bar` (bar.s(), bar.colors).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent

    property var bar: null

    readonly property var flickable: body.item ? body.item.flickable : null

    function current() {
        let a = (Theme.appearanceSettings && typeof Theme.appearanceSettings === "object")
                ? Theme.appearanceSettings : {};
        let num = (v) => (v !== undefined && !isNaN(Number(v)) && Number(v) > 0) ? Number(v) : 1.0;
        return {
            "shapeScale": num(a.shapeScale),
            "densityScale": num(a.densityScale),
            "motionScale": num(a.motionScale)
        };
    }

    function write(key, v) {
        let c = root.current();
        c[key] = v;
        Config.setSetting("appearance", c);
    }

    function bump(key, d) {
        let v = Math.round((root.current()[key] + d) * 10) / 10;
        v = Math.max(0.6, Math.min(1.6, v));
        root.write(key, v);
    }

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
                        text: "Appearance"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Material-You structure scales. Shape sets corner radii, Density sets the spacing grid and panel padding, Motion sets animation durations. 1.00 is the base; all panels and widgets follow live."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    StepperCard {
                        width: parent.width
                        bar: root.bar
                        label: "Shape scale"
                        value: Theme.shapeScale.toFixed(2) + "×"
                        onDec: root.bump("shapeScale", -0.1)
                        onInc: root.bump("shapeScale", 0.1)
                    }

                    StepperCard {
                        width: parent.width
                        bar: root.bar
                        label: "Density scale"
                        value: Theme.densityScale.toFixed(2) + "×"
                        onDec: root.bump("densityScale", -0.1)
                        onInc: root.bump("densityScale", 0.1)
                    }

                    StepperCard {
                        width: parent.width
                        bar: root.bar
                        label: "Motion scale"
                        value: Theme.motionScale.toFixed(2) + "×"
                        onDec: root.bump("motionScale", -0.1)
                        onInc: root.bump("motionScale", 0.1)
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Range 0.60–1.60. Lower = tighter/denser and faster; higher = rounder and slower. Glass mode and the palette are unaffected."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
