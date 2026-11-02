import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../edit"
import "../../../core"
import "../../../core/FrameGeometry.js" as FG

// ═══════════════════════════════════════════════════════════════════════════
// FramePage — BarEditor tab (Theme group): the screen frame (settings.json
// "frame"). It edits the section that ui/frame/Frame.qml consumes live.
//
// The frame is a border wrapping all four screen edges, drawn on the Bottom
// layer (behind the bar, host overlays and windows) and reserving space on
// each side so tiled windows never cross it (same model as the bar). Where the
// bar, a host overlay or an edge-anchored widget (launcher/panels) meet it, the
// line sinks and hugs them with rounded corners (muescas).
//
// Contract: receives the BarEditor root as `bar` (bar.s(), bar.colors).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent

    property var bar: null

    // Color options: pure black/white + the full palette role set, so the frame
    // can match the palette's background/base and stay consistent everywhere.
    readonly property var frameColors: [
        "#ffffff", "#000000",
        "background", "base", "mantle", "crust",
        "surface0", "surface1", "surface2",
        "overlay0", "overlay1", "overlay2",
        "text", "subtext0", "mauve", "pink", "red", "maroon",
        "peach", "yellow", "green", "teal", "sapphire", "blue"
    ]
    function colorOf(v) {
        if (!root.bar || !root.bar.colors) return v;
        if (String(v).charAt(0) === "#") return v;
        var c = root.bar.colors[v];
        return (c !== undefined && c !== null) ? c : "#888888";
    }

    readonly property var d: FG.defaults()
    property bool frEnabled: d.enabled
    property real frThickness: d.thickness
    property real frSideThickness: d.sideThickness
    property real frInset: d.inset
    property real frRadius: d.radius
    property real frGap: d.gap
    property real frNotchRadius: d.notchRadius
    property real frAlpha: d.alpha
    property string frColor: d.color
    property bool frLine: d.line
    property real frLineWidth: d.lineWidth
    property bool frFill: d.fill
    property string frFillColor: d.fillColor
    property real frFillAlpha: d.fillAlpha
    property bool frReserve: d.reserve
    property real frReserveExtra: d.reserveExtra
    property bool frNotchBar: d.notchBar
    property bool frNotchWidget: d.notchWidget
    property bool frNotchHosts: d.notchHosts
    property bool frBackgroundLayer: d.layer === "background"

    readonly property var flickable: body.item ? body.item.flickable : null

    function syncFromConfig() {
        let c = FG.normalize(Config.rawSettings.frame || {});
        root.frEnabled = c.enabled;
        root.frThickness = c.thickness;
        root.frSideThickness = c.sideThickness;
        root.frInset = c.inset;
        root.frRadius = c.radius;
        root.frGap = c.gap;
        root.frNotchRadius = c.notchRadius;
        root.frAlpha = c.alpha;
        root.frColor = c.color;
        root.frLine = c.line;
        root.frLineWidth = c.lineWidth;
        root.frFill = c.fill;
        root.frFillColor = c.fillColor;
        root.frFillAlpha = c.fillAlpha;
        root.frReserve = c.reserve;
        root.frReserveExtra = c.reserveExtra;
        root.frNotchBar = c.notchBar;
        root.frNotchWidget = c.notchWidget;
        root.frNotchHosts = c.notchHosts;
        root.frBackgroundLayer = c.layer === "background";
    }
    Component.onCompleted: root.syncFromConfig()

    // Debounced commit into settings.json "frame" (drag friendly).
    property var _pending: ({})
    Timer { id: saveTimer; interval: 300; onTriggered: root.flush() }
    function set(key, v) {
        root._pending[key] = v;
        saveTimer.restart();
    }
    function flush() {
        let keys = Object.keys(root._pending);
        if (keys.length === 0) return;
        let base = (Config.rawSettings.frame && typeof Config.rawSettings.frame === "object")
                   ? Config.rawSettings.frame : {};
        Config.setSetting("frame", Object.assign({}, base, root._pending));
        root._pending = {};
    }
    Component.onDestruction: root.flush()

    function setLayer(background) {
        root.frBackgroundLayer = background;
        root.set("layer", background ? "background" : "bottom");
    }

    function applyPreset(p) {
        let base = (Config.rawSettings.frame && typeof Config.rawSettings.frame === "object")
                   ? Config.rawSettings.frame : {};
        Config.setSetting("frame", Object.assign({}, base, p.cfg));
        root.syncFromConfig();
    }
    function presetActive(p) {
        Config.rev; // reactive to settings mutations
        let cur = FG.normalize(Config.rawSettings.frame || {});
        let tgt = FG.normalize(Object.assign({}, FG.defaults(), p.cfg));
        return cur.thickness === tgt.thickness && cur.radius === tgt.radius
            && cur.inset === tgt.inset && cur.line === tgt.line
            && cur.fill === tgt.fill && String(cur.color) === String(tgt.color)
            && String(cur.fillColor) === String(tgt.fillColor);
    }
    function resetVisual() {
        let base = (Config.rawSettings.frame && typeof Config.rawSettings.frame === "object")
                   ? Config.rawSettings.frame : {};
        let d = FG.defaults();
        Config.setSetting("frame", Object.assign({}, base, {
            thickness: d.thickness, sideThickness: d.sideThickness,
            radius: d.radius, inset: d.inset, gap: d.gap,
            notchRadius: d.notchRadius, color: d.color, alpha: d.alpha,
            line: d.line, lineWidth: d.lineWidth, fill: d.fill,
            fillColor: d.fillColor, fillAlpha: d.fillAlpha
        }));
        root.syncFromConfig();
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
                        text: "Frame"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }
                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "A border wrapping all four screen edges, drawn behind the bar, host overlays and the windows. It reserves space on each side so tiled windows never cross it, and hugs the bar/overlay/launcher with rounded corners. Applies live."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        text: "Presets"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    Flow {
                        width: parent.width
                        spacing: bar.s(Theme.gapSm)
                        Repeater {
                            model: FG.presets()
                            delegate: EditorButton {
                                bar: root.bar
                                icon: modelData.icon
                                label: modelData.label
                                compact: true
                                active: root.presetActive(modelData)
                                onActivated: root.applyPreset(modelData)
                            }
                        }
                        EditorButton {
                            bar: root.bar
                            icon: "󰔄"
                            label: "Reset"
                            compact: true
                            onActivated: root.resetVisual()
                        }
                    }
                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Presets are shortcuts — manual tweaks below stay possible and keep enabled/reserve/hug settings."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "󰝴"
                        label: "Enabled"
                        checked: root.frEnabled
                        onToggled: { root.frEnabled = !root.frEnabled; root.set("enabled", root.frEnabled); }
                    }

                    // ── Shape ───────────────────────────────────────────────
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
                        icon: "󰧷"
                        label: "Band width (top/bottom)"
                        from: 0; to: 80; step: 1
                        suffix: "px"
                        accentColor: bar.colors.peach
                        value: root.frThickness
                        onEdited: (v) => { root.frThickness = v; root.set("thickness", v); }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "󰧸"
                        label: "Band width (left/right)"
                        from: 0; to: 120; step: 1
                        suffix: "px"
                        accentColor: bar.colors.mauve
                        value: root.frSideThickness
                        onEdited: (v) => { root.frSideThickness = v; root.set("sideThickness", v); }
                    }
                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "󰅁"
                        label: "Border line (hugs the bar/overlays)"
                        checked: root.frLine
                        onToggled: { root.frLine = !root.frLine; root.set("line", root.frLine); }
                    }
                    EffectSlider {
                        width: parent.width
                        visible: root.frLine
                        bar: root.bar
                        icon: "󰅁"
                        label: "Line width"
                        from: 0; to: 12; step: 1
                        suffix: "px"
                        accentColor: bar.colors.peach
                        value: root.frLineWidth
                        onEdited: (v) => { root.frLineWidth = v; root.set("lineWidth", v); }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "󰩬"
                        label: "Inset"
                        from: -40; to: 60; step: 1
                        suffix: "px"
                        accentColor: bar.colors.sapphire
                        value: root.frInset
                        onEdited: (v) => { root.frInset = v; root.set("inset", v); }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "󰜮"
                        label: "Corner radius"
                        from: 0; to: 60; step: 1
                        suffix: "px"
                        accentColor: bar.colors.green
                        value: root.frRadius
                        onEdited: (v) => { root.frRadius = v; root.set("radius", v); }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "󱗼"
                        label: "Notch radius"
                        from: 0; to: 40; step: 1
                        suffix: "px"
                        accentColor: bar.colors.teal
                        value: root.frNotchRadius
                        onEdited: (v) => { root.frNotchRadius = v; root.set("notchRadius", v); }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "󱗼"
                        label: "Notch gap"
                        from: 0; to: 40; step: 1
                        suffix: "px"
                        accentColor: bar.colors.mauve
                        value: root.frGap
                        onEdited: (v) => { root.frGap = v; root.set("gap", v); }
                    }

                    // ── Colors & fill ───────────────────────────────────────
                    Text {
                        text: "Color & fill"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    Item {
                        width: parent.width
                        height: bar.s(36)
                        EditLabel {
                            bar: root.bar
                            text: "Line color"
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: bar.s(64); height: bar.s(24); radius: bar.s(Theme.radiusSm)
                            color: root.colorOf(root.frColor)
                            border.width: 1; border.color: Theme.outlineVariant
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: bar.s(Theme.gapSm)
                        Repeater {
                            model: root.frameColors
                            delegate: Rectangle {
                                readonly property bool sel: String(root.frColor) === String(modelData)
                                width: bar.s(24); height: bar.s(24); radius: bar.s(Theme.radiusSm)
                                color: root.colorOf(modelData)
                                border.width: sel ? 2 : 1
                                border.color: sel ? bar.colors.text : Theme.outlineVariant
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.frColor = modelData; root.set("color", modelData); }
                                }
                            }
                        }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "󰖨"
                        label: "Line opacity"
                        from: 0; to: 1.0; step: 0.05
                        decimals: 2
                        accentColor: bar.colors.sapphire
                        value: root.frAlpha
                        onEdited: (v) => { root.frAlpha = v; root.set("alpha", v); }
                    }
                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "󰆣"
                        label: "Fill (solid band)"
                        checked: root.frFill
                        onToggled: { root.frFill = !root.frFill; root.set("fill", root.frFill); }
                    }
                    Item {
                        width: parent.width
                        height: bar.s(36)
                        visible: root.frFill
                        EditLabel {
                            bar: root.bar
                            text: "Fill color"
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: bar.s(64); height: bar.s(24); radius: bar.s(Theme.radiusSm)
                            color: root.colorOf(root.frFillColor)
                            border.width: 1; border.color: Theme.outlineVariant
                        }
                    }
                    Flow {
                        width: parent.width
                        visible: root.frFill
                        spacing: bar.s(Theme.gapSm)
                        Repeater {
                            model: root.frameColors
                            delegate: Rectangle {
                                readonly property bool sel: String(root.frFillColor) === String(modelData)
                                width: bar.s(24); height: bar.s(24); radius: bar.s(Theme.radiusSm)
                                color: root.colorOf(modelData)
                                border.width: sel ? 2 : 1
                                border.color: sel ? bar.colors.text : Theme.outlineVariant
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.frFillColor = modelData; root.set("fillColor", modelData); }
                                }
                            }
                        }
                    }
                    EffectSlider {
                        width: parent.width
                        visible: root.frFill
                        bar: root.bar
                        icon: "󰖨"
                        label: "Fill opacity"
                        from: 0; to: 1.0; step: 0.05
                        decimals: 2
                        accentColor: bar.colors.mauve
                        value: root.frFillAlpha
                        onEdited: (v) => { root.frFillAlpha = v; root.set("fillAlpha", v); }
                    }

                    // ── Hug (muescas) ───────────────────────────────────────
                    Text {
                        text: "Hug"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "󰮯"
                        label: "Hug the bar"
                        checked: root.frNotchBar
                        onToggled: { root.frNotchBar = !root.frNotchBar; root.set("notchBar", root.frNotchBar); }
                    }
                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "󰀻"
                        label: "Hug the launcher / panels"
                        checked: root.frNotchWidget
                        onToggled: { root.frNotchWidget = !root.frNotchWidget; root.set("notchWidget", root.frNotchWidget); }
                    }
                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: ""
                        label: "Hug host overlays"
                        checked: root.frNotchHosts
                        onToggled: { root.frNotchHosts = !root.frNotchHosts; root.set("notchHosts", root.frNotchHosts); }
                    }

                    // ── Space & layer ───────────────────────────────────────
                    Text {
                        text: "Space"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "󰍉"
                        label: "Reserve space (windows never cross)"
                        checked: root.frReserve
                        onToggled: { root.frReserve = !root.frReserve; root.set("reserve", root.frReserve); }
                    }
                    EffectSlider {
                        width: parent.width
                        bar: root.bar
                        icon: "󰩬"
                        label: "Extra reserve"
                        from: 0; to: 60; step: 1
                        suffix: "px"
                        accentColor: bar.colors.blue
                        value: root.frReserveExtra
                        onEdited: (v) => { root.frReserveExtra = v; root.set("reserveExtra", v); }
                    }
                    ToggleCard {
                        width: parent.width
                        bar: root.bar
                        icon: "󰚰"
                        label: "Background layer (behind the wallpaper is not affected; on = lower)"
                        checked: root.frBackgroundLayer
                        onToggled: root.setLayer(!root.frBackgroundLayer)
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Inset accepts negative values to push the border past the screen edge (slider to the far left). The bar's edge is never reserved twice: the frame skips the side the bar already occupies."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
