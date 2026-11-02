import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../edit"
import "../BarLayout.js" as BarLayout
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// GeneralPage — BarEditor tab: bar master switch + live overview.
//
// Fase 5 (look Guide): título s(24) Black + cards. The master switch
// (bar.enabled) unmaps the bar on every screen live: off = no UI, no reserved
// edge, no input; the rest of the config is preserved so switching back on
// restores the bar exactly. Plugin-provided bars are configured from their
// own pages in the Plugins group — this page only owns the core bar.
// Contract: receives the BarEditor root as `bar` (bar.s(), bar.colors,
// bar.bar, bar.applyBar(), ...). NEVER touches ids of the editor root.
// Exposes the scroll Flickable via `flickable` so the root can drive DnD
// auto-scroll.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent   // Phase 3: el item del Loader ocupa la stage

    property var bar: null

    readonly property bool barEnabled: root.bar !== null && root.bar.bar.enabled !== false

    // ── Posiciones de popups (settings.widgets.<id>.position) ─────────────
    property int posTick: 0
    // Core popups + plugin-provided panels (manifest provides.panels; the
    // entry's label or the plugin name). Position keys are panel names — the
    // page never knows plugin ids.
    readonly property var pluginPanels: {
        PluginsCatalog.rev;
        let out = [];
        let list = PluginsCatalog.plugins || [];
        for (let i = 0; i < list.length; i++) {
            let p = list[i] || {};
            if (!p.enabled || !p.provides || typeof p.provides !== "object") continue;
            let panels = p.provides.panels;
            if (!panels || typeof panels !== "object") continue;
            for (let name in panels) {
                let e = panels[name] || {};
                out.push({ id: name, label: e.label || p.name || name });
            }
        }
        return out;
    }
    readonly property var widgetsList: [
        { id: "network", label: "Wifi / Bluetooth" },
        { id: "volume", label: "Sound" },
        { id: "battery", label: "Battery" },
        { id: "system-monitor", label: "System" },
        { id: "applauncher", label: "Launcher" },
        { id: "music", label: "Music" },
        { id: "updater", label: "Updater" },
        { id: "guide", label: "About (guide)" },
        { id: "scale", label: "Scale" },
        { id: "window-controls", label: "Window controls" }
    ].concat(pluginPanels)
    function widgetPosition(id) {
        let w = Config.rawSettings.widgets;
        return (w && w[id] && w[id].position) ? w[id].position : "default";
    }
    function setWidgetPosition(id, pos) {
        let w = {};
        let cur = Config.rawSettings.widgets;
        if (cur && typeof cur === "object") for (let k in cur) w[k] = cur[k];
        let entry = (w[id] && typeof w[id] === "object") ? w[id] : {};
        let next = {};
        for (let k in entry) next[k] = entry[k];
        next.position = pos;
        w[id] = next;
        Config.setSetting("widgets", w);
        root.posTick++;
    }

    // Tokens del preview: ids de módulos enabled, en orden de zonas.
    function previewTokens() {
        let out = [];
        if (root.bar === null) return out;
        let zones = root.bar.bar.zones || [];
        for (let z = 0; z < zones.length; z++) {
            let mods = zones[z].modules || [];
            for (let i = 0; i < mods.length; i++) {
                let m = mods[i];
                let id = (typeof m === "string") ? m : (m && m.id);
                if (!id) continue;
                if (m && typeof m === "object" && m.enabled === false) continue;
                out.push(id);
            }
        }
        return out;
    }

    // Gate: el cuerpo se crea cuando bar ya está inyectado (initial
    // property aplicada tras la creación del root). Evita bindings
    // evaluados con bar null que quedaban muertos en negro.
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
                        text: "Bar"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }

                    // ── Master switch (bar.enabled) ───────────────────────
                    Column {
                        width: parent.width
                        spacing: bar.s(Theme.gapSm)
                        ToggleCard {
                            width: parent.width
                            bar: root.bar
                            icon: "󰮯"
                            label: "Bar enabled"
                            checked: root.barEnabled
                            onToggled: root.bar.applyBar(BarLayout.setBarEnabled(root.bar.bar, !root.barEnabled))
                        }
                        EditLabel {
                            bar: root.bar
                            width: parent.width
                            text: "Off unmaps the bar on every screen (no UI, no reserved edge); the layout is preserved and restored when switched back on."
                            font.pixelSize: bar.s(11)
                            color: bar.colors.subtext0
                            wrapMode: Text.WordWrap
                        }
                    }

                    // ── Overview ──────────────────────────────────────────
                    Rectangle {
                        width: parent.width
                        radius: bar.s(Theme.radiusLg)
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant
                        height: infoCol.height + bar.s(Theme.gapMd) * 2
                        Column {
                            id: infoCol
                            x: bar.s(Theme.gapMd); y: bar.s(Theme.gapMd)
                            width: parent.width - bar.s(Theme.gapMd) * 2
                            spacing: bar.s(Theme.gapSm)
                            EditLabel { bar: root.bar; text: "Overview"; font.pixelSize: bar.s(12); color: bar.colors.subtext0 }
                            Text {
                                width: parent.width
                                text: "State: " + (root.barEnabled ? "enabled" : "disabled")
                                    + "  ·  position: " + (root.bar.bar.position || "top")
                                    + "  ·  zones: " + ((root.bar.bar.zones || []).length)
                                    + "  ·  modules: " + root.previewTokens().length
                                font.family: "Hack Nerd Font"
                                font.pixelSize: bar.s(12)
                                color: bar.colors.text
                                wrapMode: Text.WordWrap
                            }
                            EditLabel {
                                bar: root.bar
                                width: parent.width
                                text: "Every visual/layout option lives in its own page (Position, Style, Zones, Modules, Workspaces)."
                                font.pixelSize: bar.s(11)
                                color: bar.colors.subtext0
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ── Preview: mini-barra con los módulos reales ────────
                    Rectangle {
                        width: parent.width
                        radius: bar.s(Theme.radiusLg)
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant
                        height: bar.s(240)
                        Column {
                            anchors.fill: parent
                            anchors.margins: bar.s(Theme.gapMd)
                            spacing: bar.s(Theme.gapMd)
                            EditLabel { bar: root.bar; text: "Preview"; font.pixelSize: bar.s(12); color: bar.colors.subtext0 }
                            Rectangle {
                                width: parent.width
                                height: bar.s(44)
                                radius: bar.s(Theme.radiusMd)
                                color: Theme.surfaceContainer
                                border.width: 1
                                border.color: Theme.outlineVariant
                                Row {
                                    anchors.centerIn: parent
                                    spacing: bar.s(Theme.gapSm)
                                    Repeater {
                                        model: root.previewTokens()
                                        delegate: Rectangle {
                                            required property var modelData
                                            required property int index
                                            width: bar.s(28); height: bar.s(28); radius: bar.s(Theme.radiusSm)
                                            readonly property string role: ["mauve", "blue", "green", "peach", "pink", "teal", "yellow", "sapphire"][index % 8]
                                            color: Qt.alpha(bar.colors[role], 0.20)
                                            border.width: 1
                                            border.color: Qt.alpha(bar.colors[role], 0.75)
                                            Text {
                                                anchors.centerIn: parent
                                                text: {
                                                    let m = BarLayout.getModule(modelData);
                                                    if (!m || !m.icon) {
                                                        let pm = PluginsCatalog.barModule(modelData);
                                                        if (pm && pm.icon) return pm.icon;
                                                    }
                                                    return m && m.icon ? m.icon : "·";
                                                }
                                                font.family: "Hack Nerd Font"
                                                font.pixelSize: bar.s(13)
                                                color: bar.colors[role]
                                            }
                                        }
                                    }
                                }
                            }
                            EditLabel {
                                bar: root.bar
                                width: parent.width
                                text: "bar \u00b7 position " + (root.bar.bar.position || "top") + " \u00b7 zones " + (root.bar.bar.zones ? root.bar.bar.zones.length : 0)
                                font.pixelSize: bar.s(11)
                                color: bar.colors.subtext0
                            }
                        }
                    }

                    // Posiciones de los popups: matriz 3x3 espacial por widget.
                    Rectangle {
                        width: parent.width
                        radius: bar.s(Theme.radiusLg)
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant
                        height: posCol.height + bar.s(Theme.gapMd) * 2
                        Column {
                            id: posCol
                            x: bar.s(Theme.gapMd); y: bar.s(Theme.gapMd)
                            width: parent.width - bar.s(Theme.gapMd) * 2
                            spacing: bar.s(Theme.gapSm)
                            EditLabel { bar: root.bar; text: "Popup positions"; font.pixelSize: bar.s(12); color: bar.colors.subtext0 }
                            Repeater {
                                model: root.widgetsList
                                delegate: Row {
                                    id: parentWidget
                                    required property var modelData
                                    width: posCol.width
                                    spacing: bar.s(Theme.gapMd)
                                    Text {
                                        width: bar.s(170)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        font.family: "Hack Nerd Font"
                                        font.pixelSize: bar.s(12)
                                        color: bar.colors.text
                                    }
                                    GridLayout {
                                        columns: 3
                                        rowSpacing: bar.s(Theme.gapXs); columnSpacing: bar.s(Theme.gapXs)
                                        Repeater {
                                            model: ["top-left", "top-center", "top-right",
                                                    "center-left", "center", "center-right",
                                                    "bottom-left", "bottom-center", "bottom-right"]
                                            delegate: Rectangle {
                                                id: posCell
                                                required property var modelData
                                                readonly property bool act: root.posTick >= 0 && root.widgetPosition(parentWidget.modelData.id) === posCell.modelData
                                                width: bar.s(20); height: bar.s(20); radius: bar.s(Theme.radiusXs)
                                                color: act ? bar.colors.mauve : Theme.surfaceContainer
                                                border.width: 1
                                                border.color: act ? bar.colors.mauve : Theme.outlineVariant
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setWidgetPosition(parentWidget.modelData.id, posCell.modelData) }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        width: bar.s(46); height: bar.s(20); radius: bar.s(Theme.radiusXs)
                                        anchors.verticalCenter: parent.verticalCenter
                                        readonly property bool act: root.posTick >= 0 && root.widgetPosition(parentWidget.modelData.id) === "default"
                                        color: act ? bar.colors.mauve : Theme.surfaceContainerLow
                                        border.width: 1
                                        border.color: act ? bar.colors.mauve : Theme.outlineVariant
                                        Text { anchors.centerIn: parent; text: "auto"; font.family: "Hack Nerd Font"; font.pixelSize: bar.s(9); color: act ? bar.colors.crust : bar.colors.subtext0 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setWidgetPosition(parentWidget.modelData.id, "default") }
                                    }
                                }
                            }
                            EditLabel { bar: root.bar; text: "auto = the widget's own layout; the rest anchor with a 20px scaled margin."; font.pixelSize: bar.s(11); color: bar.colors.subtext0 }
                        }
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "The bar switch lives here; plugin-provided bars (complete bars shipped by plugins) have their own pages in the Plugins group."
                        font.pixelSize: bar.s(12)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
