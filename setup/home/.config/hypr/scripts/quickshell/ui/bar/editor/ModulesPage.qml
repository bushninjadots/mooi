import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../edit"
import ".."
import "../BarLayout.js" as BarLayout
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// ModulesPage — BarEditor tab: per-module personalization (icon, color, fill,
// accent) plus the bar-wide icon color. Consumes the module personalization
// API in BarLayout.js through bar.applyBar(...).
//
// Layout: 2-column grid of module cards (Guide look: surfaceContainerLow
// radiusLg + outlineVariant border). Each card header previews the EFFECTIVE icon and
// accent; the fields hold overrides only, so their placeholders show the
// current default (empty field = module default).
//
// Contract: receives the BarEditor root as `bar` (bar.s(), bar.colors,
// bar.bar, bar.applyBar, ...). NEVER touches ids of the editor root. Exposes
// the scroll Flickable via `flickable`.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent

    property var bar: null

    // Modules whose component calls mod.glyph(): the icon field only has an
    // effect there. Kept in sync with docs/personalization.md.
    readonly property var iconModules: ["help", "search", "settings", "update",
                                        "keyboard", "wifi", "bluetooth", "volume",
                                        "battery", "weather", "focus", "recording"]

    // Per-module defaults for the field placeholders and the preview (state
    // icons stay empty; the component decides them at runtime).
    readonly property var moduleDefaults: ({
        "help":      { icon: "󰅖", accent: "peach" },
        "search":    { icon: "󰍉", accent: "sapphire" },
        "settings":  { icon: "󰒓", accent: "mauve" },
        "update":    { icon: "󰚰", accent: "green" },
        "keyboard":  { icon: "󰌌", accent: "color5" },
        "wifi":      { icon: "",       accent: "color6" },
        "bluetooth": { icon: "",       accent: "color4" },
        "volume":    { icon: "",       accent: "color3" },
        "battery":   { icon: "",       accent: "green" },
        "time":      { icon: "",       accent: "teal" },
        "weather":   { icon: "",       accent: "yellow" },
        "focus":     { icon: "",       accent: "" },
        "recording": { icon: "",       accent: "red" }
    })

    function defIcon(id) {
        let d = root.moduleDefaults[id];
        if (d && d.icon) return d.icon;
        let p = PluginsCatalog.barModule(id);
        return p && p.icon ? p.icon : "";
    }
    function defAccent(id) {
        let d = root.moduleDefaults[id];
        if (d && d.accent) return d.accent;
        return "";
    }
    // Core catalog + plugin-provided modules (provides.bar.modules) not in
    // the catalog; plugin entries carry their label/icon hints.
    readonly property var allModules: {
        PluginsCatalog.rev;
        let base = BarLayout.MODULES.map(m => Object.assign({}, m));
        let have = {};
        for (let i = 0; i < base.length; i++) have[base[i].id] = true;
        let extra = PluginsCatalog.barModuleEntries();
        for (let i = 0; i < extra.length; i++) {
            if (have[extra[i].id]) continue;
            base.push({ id: extra[i].id, label: extra[i].label, icon: extra[i].icon, component: "" });
        }
        return base;
    }
    function colorOf(value) {
        if (value === "") return root.bar.colors.text;
        return root.bar.colors[value] !== undefined ? root.bar.colors[value] : value;
    }

    // Effective colour of a workspaces slot (override or palette default) for
    // the little indicator dots.
    function slotSwatch(slotValue, fallbackRole) {
        let v = (slotValue !== undefined && slotValue !== "") ? slotValue : fallbackRole;
        if (v === "workspaceActive") {
            let wa = root.bar.colors.workspaceActive;
            return (wa !== undefined && wa.a > 0) ? wa : root.bar.colors.mauve;
        }
        return root.colorOf(v);
    }

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

                    Text {
                        text: "Modules"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }

                    Text {
                        text: "Per-island overrides; the fields hold only what you change (placeholders show the module default). Color accepts a colors.* role or a #hex."
                        font.family: "Hack Nerd Font"
                        font.pixelSize: bar.s(13)
                        color: bar.colors.subtext0
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }

                    FieldCard {
                        width: parent.width
                        bar: root.bar
                        label: "Icon color (global)"
                        value: root.bar.bar.iconColor !== undefined ? root.bar.bar.iconColor : ""
                        placeholder: "default (module roles)"
                        fieldWidth: 220
                        onEdited: (text) => root.bar.applyBar(BarLayout.setGlobalIconColor(root.bar.bar, text))
                    }

                    GridLayout {
                        width: parent.width
                        // Responsive: 2 columnas solo cuando la card conserva el
                        // ancho minimo (~s(680)); si no, 1 columna a lo ancho
                        // (evita solapes de los controles internos).
                        columns: Math.max(1, Math.floor((width + columnSpacing) / (bar.s(500) + columnSpacing)))
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)

                        Repeater {
                            model: root.allModules

                            delegate: Rectangle {
                                id: card

                                Layout.fillWidth: true
                                Layout.preferredWidth: (pageCol.width - bar.s(Theme.gapMd)) / 2
                                implicitHeight: cardCol.implicitHeight + bar.s(Theme.gapMd) * 2
                                radius: bar.s(Theme.radiusLg)
                                color: Theme.surfaceContainerLow
                                border.width: 1
                                border.color: Theme.outlineVariant

                                readonly property var cfg: BarLayout.moduleConfig(root.bar.bar, modelData.id)
                                readonly property string effIcon: card.cfg.icon !== "" ? card.cfg.icon : root.defIcon(modelData.id)
                                readonly property string effAccent: card.cfg.accent !== "" ? card.cfg.accent : root.defAccent(modelData.id)

                                Column {
                                    id: cardCol
                                    x: bar.s(Theme.gapMd)
                                    y: bar.s(Theme.gapMd)
                                    width: parent.width - bar.s(Theme.gapMd) * 2
                                    spacing: bar.s(Theme.gapSm)

                                    RowLayout {
                                        width: parent.width
                                        spacing: bar.s(Theme.gapSm)

                                        Text {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: card.effIcon !== "" ? card.effIcon : "·"
                                            font.family: "Hack Nerd Font"
                                            font.pixelSize: bar.s(18)
                                            color: card.cfg.color !== "" ? root.colorOf(card.cfg.color) : bar.colors.text
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: modelData.label
                                            font.family: "Hack Nerd Font"
                                            font.weight: Font.Bold
                                            font.pixelSize: bar.s(14)
                                            color: bar.colors.text
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: modelData.id
                                            font.family: "Hack Nerd Font"
                                            font.pixelSize: bar.s(10)
                                            color: bar.colors.subtext0
                                        }

                                        Item { Layout.fillWidth: true; height: 1 }

                                        Rectangle {
                                            Layout.alignment: Qt.AlignVCenter
                                            width: bar.s(10)
                                            height: bar.s(10)
                                            radius: bar.s(Theme.radiusFull)
                                            color: card.effAccent !== "" ? root.colorOf(card.effAccent) : Theme.surfaceContainer
                                        }

                                        // Add/remove the module from the bar. Plugin
                                        // modules are not in the core catalog, so
                                        // normalizeBar never auto-adds them: this
                                        // is the only way to place them.
                                        EditorButton {
                                            readonly property bool placed: BarLayout.modulePlaced(root.bar.bar, modelData.id)
                                            Layout.alignment: Qt.AlignVCenter
                                            compact: true
                                            bar: root.bar
                                            accentRole: "mauve"
                                            icon: placed ? "󰄬" : "󰐕"
                                            label: placed ? "On bar" : "Add"
                                            active: placed
                                            onActivated: root.bar.applyBar(placed
                                                ? BarLayout.removeModuleFromBar(root.bar.bar, modelData.id)
                                                : BarLayout.addModuleToBar(root.bar.bar, modelData.id))
                                        }
                                    }

                                    // Rows con anchos explícitos: los GridLayout anidados
                                    // calculaban mal su alto implícito y las filas se pisaban.
                                    Row {
                                        width: parent.width
                                        spacing: bar.s(Theme.gapSm)

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: root.iconModules.indexOf(modelData.id) !== -1 ? "Icon" : "Icon (unused)"
                                            value: card.cfg.icon
                                            placeholder: root.defIcon(modelData.id) !== "" ? "default: " + root.defIcon(modelData.id) : (root.iconModules.indexOf(modelData.id) !== -1 ? "state icon" : "not used")
                                            fieldWidth: 110
                                            maxLength: 4
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleIcon(root.bar.bar, modelData.id, text))
                                        }

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Color"
                                            value: card.cfg.color
                                            placeholder: "default"
                                            fieldWidth: 110
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleColor(root.bar.bar, modelData.id, text))
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: bar.s(Theme.gapSm)

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Accent"
                                            value: card.cfg.accent
                                            placeholder: root.defAccent(modelData.id) !== "" ? "default: " + root.defAccent(modelData.id) : "default: none"
                                            fieldWidth: 110
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleAccent(root.bar.bar, modelData.id, text))
                                        }

                                        Row {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: bar.s(Theme.gapSm)

                                            EditorButton {
                                                bar: root.bar
                                                compact: true
                                                label: "Default"
                                                active: card.cfg.fill === "default"
                                                onActivated: root.bar.applyBar(BarLayout.setModuleFill(root.bar.bar, modelData.id, "default"))
                                            }

                                            EditorButton {
                                                bar: root.bar
                                                compact: true
                                                label: "Filled"
                                                accentRole: "blue"
                                                active: card.cfg.fill === "on"
                                                onActivated: root.bar.applyBar(BarLayout.setModuleFill(root.bar.bar, modelData.id, "on"))
                                            }

                                            EditorButton {
                                                bar: root.bar
                                                compact: true
                                                label: "None"
                                                accentRole: "red"
                                                active: card.cfg.fill === "off"
                                                onActivated: root.bar.applyBar(BarLayout.setModuleFill(root.bar.bar, modelData.id, "off"))
                                            }
                                        }
                                    }

                                    // Reloj: formato + tamaño.
                                    Row {
                                        width: parent.width
                                        visible: modelData.id === "time"
                                        spacing: bar.s(Theme.gapSm)

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Clock format"
                                            value: root.bar.bar.timeFormat !== undefined ? root.bar.bar.timeFormat : ""
                                            placeholder: "default: HH:mm:ss"
                                            fieldWidth: 130
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setTimeFormat(root.bar.bar, text))
                                        }

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Size"
                                            value: card.cfg.size > 0 ? String(card.cfg.size) : ""
                                            placeholder: "default: 16"
                                            fieldWidth: 90
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleSize(root.bar.bar, modelData.id, parseInt(text) || 0))
                                        }
                                    }

                                    // Reloj: efecto typewriter + cursor.
                                    Row {
                                        width: parent.width
                                        visible: modelData.id === "time"
                                        spacing: bar.s(Theme.gapSm)

                                        EditorButton {
                                            bar: root.bar
                                            compact: true
                                            label: "No effect"
                                            active: card.cfg.effect !== "typewriter"
                                            onActivated: root.bar.applyBar(BarLayout.setModuleEffect(root.bar.bar, modelData.id, ""))
                                        }

                                        EditorButton {
                                            bar: root.bar
                                            compact: true
                                            label: "Typewriter"
                                            accentRole: "mauve"
                                            active: card.cfg.effect === "typewriter"
                                            onActivated: root.bar.applyBar(BarLayout.setModuleEffect(root.bar.bar, modelData.id, "typewriter"))
                                        }

                                        EditorButton {
                                            bar: root.bar
                                            compact: true
                                            label: "Cursor"
                                            accentRole: "sapphire"
                                            active: card.cfg.cursor
                                            onActivated: root.bar.applyBar(BarLayout.setModuleCursor(root.bar.bar, modelData.id, !card.cfg.cursor))
                                        }
                                    }

                                    // Fecha: formato + tamaño.
                                    Row {
                                        width: parent.width
                                        visible: modelData.id === "date"
                                        spacing: bar.s(Theme.gapSm)

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Date format"
                                            value: root.bar.bar.dateFormat !== undefined ? root.bar.bar.dateFormat : ""
                                            placeholder: "default: dddd, MMMM dd"
                                            fieldWidth: 130
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setDateFormat(root.bar.bar, text))
                                        }

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Size"
                                            value: card.cfg.size > 0 ? String(card.cfg.size) : ""
                                            placeholder: "default: 11"
                                            fieldWidth: 90
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleSize(root.bar.bar, modelData.id, parseInt(text) || 0))
                                        }
                                    }

                                    // Workspaces: marcador de workspaces vacios + caracter propio.
                                    Row {
                                        width: parent.width
                                        visible: modelData.id === "workspaces"
                                        spacing: bar.s(Theme.gapSm)

                                        EditorButton {
                                            bar: root.bar
                                            compact: true
                                            label: "Numbers"
                                            active: root.bar.bar.workspacesMarker === "number"
                                            onActivated: root.bar.applyBar(BarLayout.setWorkspacesMarker(root.bar.bar, "number"))
                                        }

                                        EditorButton {
                                            bar: root.bar
                                            compact: true
                                            label: "Dots"
                                            active: root.bar.bar.workspacesMarker === "dot"
                                            onActivated: root.bar.applyBar(BarLayout.setWorkspacesMarker(root.bar.bar, "dot"))
                                        }

                                        EditorButton {
                                            bar: root.bar
                                            compact: true
                                            label: "Letters"
                                            active: root.bar.bar.workspacesMarker === "letter"
                                            onActivated: root.bar.applyBar(BarLayout.setWorkspacesMarker(root.bar.bar, "letter"))
                                        }

                                        EditorButton {
                                            bar: root.bar
                                            compact: true
                                            label: "Custom"
                                            active: root.bar.bar.workspacesMarker === "custom"
                                            onActivated: root.bar.applyBar(BarLayout.setWorkspacesMarker(root.bar.bar, "custom"))
                                        }
                                    }

                                    FieldCard {
                                        width: cardCol.width
                                        visible: modelData.id === "workspaces" && root.bar.bar.workspacesMarker === "custom"
                                        bar: root.bar
                                        label: "Marker character"
                                        value: root.bar.bar.workspacesMarkerText !== undefined ? root.bar.bar.workspacesMarkerText : ""
                                        placeholder: "e.g. a glyph or short text"
                                        fieldWidth: 120
                                        maxLength: 4
                                        onEdited: (text) => root.bar.applyBar(BarLayout.setWorkspacesMarkerText(root.bar.bar, text))
                                    }

                                    // Workspaces: color slot (rol o #hex).
                                    Row {
                                        width: parent.width
                                        visible: modelData.id === "workspaces"
                                        spacing: bar.s(Theme.gapSm)

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Active fill"
                                            value: card.cfg.colors.active !== undefined ? card.cfg.colors.active : ""
                                            swatch: root.slotSwatch(card.cfg.colors.active, "workspaceActive")
                                            placeholder: "default: workspaceActive"
                                            fieldWidth: 100
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleColorSlot(root.bar.bar, modelData.id, "active", text))
                                        }

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Active text"
                                            value: card.cfg.colors.activeText !== undefined ? card.cfg.colors.activeText : ""
                                            swatch: root.slotSwatch(card.cfg.colors.activeText, "crust")
                                            placeholder: "default: crust"
                                            fieldWidth: 100
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleColorSlot(root.bar.bar, modelData.id, "activeText", text))
                                        }
                                    }

                                    // Workspaces: color slot (rol o #hex).
                                    Row {
                                        width: parent.width
                                        visible: modelData.id === "workspaces"
                                        spacing: bar.s(Theme.gapSm)

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Occupied fill"
                                            value: card.cfg.colors.occupied !== undefined ? card.cfg.colors.occupied : ""
                                            swatch: root.slotSwatch(card.cfg.colors.occupied, "color5")
                                            placeholder: "default: color5"
                                            fieldWidth: 100
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleColorSlot(root.bar.bar, modelData.id, "occupied", text))
                                        }

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Empty fill"
                                            value: card.cfg.colors.empty !== undefined ? card.cfg.colors.empty : ""
                                            swatch: root.slotSwatch(card.cfg.colors.empty, "base")
                                            placeholder: "default: base"
                                            fieldWidth: 100
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleColorSlot(root.bar.bar, modelData.id, "empty", text))
                                        }
                                    }

                                    // Workspaces: color slot (rol o #hex).
                                    Row {
                                        width: parent.width
                                        visible: modelData.id === "workspaces"
                                        spacing: bar.s(Theme.gapSm)

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Hover fill"
                                            value: card.cfg.colors.hover !== undefined ? card.cfg.colors.hover : ""
                                            swatch: root.slotSwatch(card.cfg.colors.hover, "surface1")
                                            placeholder: "default: surface1"
                                            fieldWidth: 100
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleColorSlot(root.bar.bar, modelData.id, "hover", text))
                                        }

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Marker"
                                            value: card.cfg.colors.marker !== undefined ? card.cfg.colors.marker : ""
                                            swatch: root.slotSwatch(card.cfg.colors.marker, "text")
                                            placeholder: "default: text"
                                            fieldWidth: 100
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleColorSlot(root.bar.bar, modelData.id, "marker", text))
                                        }
                                    }

                                    // Workspaces: color slot (rol o #hex).
                                    Row {
                                        width: parent.width
                                        visible: modelData.id === "workspaces"
                                        spacing: bar.s(Theme.gapSm)

                                        FieldCard {
                                            width: (cardCol.width - bar.s(Theme.gapSm)) / 2
                                            bar: root.bar
                                            label: "Marker empty"
                                            value: card.cfg.colors.markerEmpty !== undefined ? card.cfg.colors.markerEmpty : ""
                                            swatch: root.slotSwatch(card.cfg.colors.markerEmpty, "overlay0")
                                            placeholder: "default: overlay0"
                                            fieldWidth: 100
                                            onEdited: (text) => root.bar.applyBar(BarLayout.setModuleColorSlot(root.bar.bar, modelData.id, "markerEmpty", text))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
