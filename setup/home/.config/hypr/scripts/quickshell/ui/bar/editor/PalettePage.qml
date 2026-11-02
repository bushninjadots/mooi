import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../edit"
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// PalettePage — BarEditor tab: shared palette selector + live base16 editor.
//
// Fase 5 (look Guide): título s(24) Black, grid 3 columnas de cards de paleta
// (template cards GP:1276-1302, activo mauve/crust) y card hero r21 para el
// editor base16 (chips + TextField estilo card).
// Contract: receives the BarEditor root as `bar` (bar.s(), bar.colors,
// bar.bar, bar.palettes, bar.applyBar, bar.paletteEditOpen,
// bar.slotDescriptors, bar.registerSlot/finishSlotEdit/resetActivePalette/
// activeSlug/checkBackupExists/syncSlotValues, ...). NEVER touches ids of the
// editor root. Exposes the scroll Flickable via `flickable`.
//
// The palette cards write through bar.applyBar({ palette }); the inline
// base16 editor registers its rows with the root (registerSlot) and commits
// hexes through the root's debounced atomic palette-file writer
// (finishSlotEdit). bar.colors is the root's own Colors instance.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent   // Phase 3: el item del Loader ocupa la stage

    property var bar: null
    // Case-insensitive filter over the palette name/slug (all sections).
    property string filter: ""

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
                        text: "Palette"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }

                    TextField {
                        width: parent.width
                        placeholderText: "Filter palettes"
                        color: bar.colors.text
                        placeholderTextColor: Qt.alpha(bar.colors.subtext0, 0.7)
                        font.family: "Hack Nerd Font"
                        font.pixelSize: bar.s(12)
                        leftPadding: bar.s(Theme.gapMd)
                        rightPadding: bar.s(Theme.gapMd)
                        onTextChanged: root.filter = text
                        background: Rectangle {
                            radius: bar.s(Theme.radiusMd)
                            color: Theme.surfaceContainerLow
                            border.width: 1
                            border.color: Theme.outlineVariant
                        }
                    }

                    // Section: X
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: root.bar.palettesOf("x", root.filter).length > 0
                        text: "X"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    GridLayout {
                        width: parent.width
                        columns: 3
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        visible: root.bar.palettesOf("x", root.filter).length > 0
                        Repeater {
                            model: root.bar.palettesOf("x", root.filter)
                            delegate: PaletteCard {}
                        }
                    }

                    // Section: Custom
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: root.bar.palettesOf("custom", root.filter).length > 0
                        text: "Custom"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    GridLayout {
                        width: parent.width
                        columns: 3
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        visible: root.bar.palettesOf("custom", root.filter).length > 0
                        Repeater {
                            model: root.bar.palettesOf("custom", root.filter)
                            delegate: PaletteCard {}
                        }
                    }

                    // Section: User
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: root.bar.palettesOf("user", root.filter).length > 0
                        text: "User"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(16)
                        color: bar.colors.text
                    }
                    GridLayout {
                        width: parent.width
                        columns: 3
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        visible: root.bar.palettesOf("user", root.filter).length > 0
                        Repeater {
                            model: root.bar.palettesOf("user", root.filter)
                            delegate: PaletteCard {}
                        }
                    }
                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        visible: root.bar.palettesOf("user").length === 0
                        text: "Your own palettes created with 'New palette' appear here."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    // Fila de acciones: Edit colors / Reset / New palette
                    Row {
                        width: parent.width
                        spacing: bar.s(Theme.gapMd)
                        EditorButton {
                            bar: root.bar
                            icon: "󰏘"
                            label: "Edit colors"
                            active: root.bar.paletteEditOpen
                            onActivated: {
                                root.bar.paletteEditOpen = !root.bar.paletteEditOpen;
                                if (root.bar.paletteEditOpen) {
                                    root.bar.syncSlotValues();
                                    root.bar.checkBackupExists();
                                }
                            }
                        }
                        EditorButton {
                            bar: root.bar
                            label: "Reset"
                            opacity: root.bar._hasSessionBackup ? 1 : 0.45
                            onActivated: root.bar.resetActivePalette()
                        }
                        EditorButton {
                            bar: root.bar
                            icon: "󰐕"
                            label: "New palette"
                            active: root.bar.paletteCreateOpen
                            onActivated: {
                                root.bar.paletteCreateOpen = !root.bar.paletteCreateOpen;
                                if (root.bar.paletteCreateOpen) {
                                    root.bar.seedPaletteDraft();
                                    root.bar.cancelDeletePalette();
                                } else {
                                    root.bar.paletteCreateStatus = "";
                                }
                            }
                        }
                        EditorButton {
                            bar: root.bar
                            icon: "󰆴"
                            label: "Delete"
                            active: root.bar.paletteDeleteConfirm
                            opacity: root.bar.activeSlug() === "x" ? 0.45 : 1
                            onActivated: {
                                if (root.bar.activeSlug() === "x") return;
                                if (root.bar.paletteDeleteConfirm) {
                                    root.bar.cancelDeletePalette();
                                } else {
                                    root.bar.paletteCreateOpen = false;
                                    root.bar.requestDeletePalette();
                                }
                            }
                        }
                    }

                    // ── Card hero: creador de paletas (8 colores base) ──
                    // El Loader se recrea en cada apertura, así los campos
                    // vuelven a sembrarse desde el draft sin bindings rotos.
                    Loader {
                        id: createLoader
                        width: parent.width
                        active: root.bar.paletteCreateOpen
                        visible: active
                        height: item ? item.height : 0
                        sourceComponent: createCard
                    }

                    // ── Card hero: confirmación de borrado ──
                    Loader {
                        id: deleteLoader
                        width: parent.width
                        active: root.bar.paletteDeleteConfirm
                        visible: active
                        height: item ? item.height : 0
                        sourceComponent: deleteCard
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        visible: !bar.paletteEditOpen
                        text: root.bar.paletteEditOpen ? ("Editing " + root.bar.activeSlug() + (root.bar._hasSessionBackup ? " · snapshot ready" : " · first edit saves a snapshot"))
                                                       : "Recolor the active palette file live."
                        font.pixelSize: bar.s(12)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    // ── Card hero: editor base16 (visible mientras paletteEditOpen) ──
                    // 18 slots (color0..15 + background + foreground), 3 por línea.
                    // Los slots se registran en el root (registerSlot) y los commits
                    // van por finishSlotEdit → escritura jq atómica agrupada.
                    Rectangle {
                        width: parent.width
                        visible: bar.paletteEditOpen
                        radius: bar.s(Theme.radiusLg)
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant
                        height: editCol.height + bar.s(Theme.gapLg) * 2

                Column {
                    id: editCol
                    x: bar.s(Theme.gapLg)
                    y: bar.s(Theme.gapLg)
                    width: parent.width - bar.s(Theme.gapLg) * 2
                    spacing: bar.s(Theme.gapMd)
                            Flow {
                                id: slotFlow
                                width: parent.width
                                spacing: bar.s(Theme.gapSm)
                                Repeater {
                                    model: root.bar.slotDescriptors
                                    delegate: Item {
                                        required property var modelData
                                        width: (slotFlow.width - bar.s(Theme.gapSm) * 2) / 3
                                        height: bar.s(30)
                                        Row {
                                            anchors.fill: parent
                                            spacing: bar.s(Theme.gapSm)
                                            Rectangle {
                                                id: chip
                                                width: bar.s(18)
                                                height: bar.s(18)
                                                anchors.verticalCenter: parent.verticalCenter
                                                radius: bar.s(Theme.radiusSm)
                                                border.width: 1
                                                border.color: Theme.outlineVariant
                                            }
                                            Text {
                                                text: modelData.label
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: bar.s(64)
                                                font.family: "Hack Nerd Font"
                                                font.pixelSize: bar.s(12)
                                                font.weight: Font.Bold
                                                color: bar.colors.text
                                            }
                                            TextField {
                                                id: hexField
                                                width: bar.s(96)
                                                height: bar.s(28)
                                                anchors.verticalCenter: parent.verticalCenter
                                                font.family: "Hack Nerd Font"
                                                font.pixelSize: bar.s(13)
                                                color: bar.colors.text
                                                selectByMouse: true
                                                maximumLength: 7
                                                validator: RegularExpressionValidator { regularExpression: /^#[0-9a-fA-F]{6}$/ }
                                                background: Rectangle {
                                                    color: Theme.surfaceContainerLow
                                                    radius: bar.s(Theme.radiusMd)
                                                    border.width: 1
                                                    border.color: hexField.activeFocus
                                                        ? bar.colors.mauve
                                                        : (hexField.acceptableInput ? Theme.outlineVariant : bar.colors.red)
                                                }
                                                onEditingFinished: root.bar.finishSlotEdit(hexField, modelData.key)
                                                onActiveFocusChanged: {
                                                    // Commit al perder el foco (click en otra fila / cierre).
                                                    if (!hexField.activeFocus) root.bar.finishSlotEdit(hexField, modelData.key);
                                                }
                                            }
                                        }
                                        Component.onCompleted: root.bar.registerSlot(modelData.key, hexField, chip)
                                    }
                                }
                            }
                            EditLabel {
                                bar: root.bar
                                width: parent.width
                                text: "Edits apply live to the bar, window borders and desktop widgets. Reset restores the session snapshot. Other palettes are untouched."
                                font.pixelSize: bar.s(12)
                                color: bar.colors.subtext0
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Creador de paletas: 8 colores base + preview + name/slug ──
    Component {
        id: createCard
        Rectangle {
            width: createLoader.width
            height: implicitHeight
            implicitHeight: createCol.height + bar.s(Theme.gapLg) * 2
            radius: bar.s(Theme.radiusLg)
            color: Theme.surfaceContainerLow
            border.width: 1
            border.color: Theme.outlineVariant

            Column {
                id: createCol
                x: bar.s(Theme.gapLg)
                y: bar.s(Theme.gapLg)
                width: parent.width - bar.s(Theme.gapLg) * 2
                spacing: bar.s(Theme.gapMd)

                RowLayout {
                    width: parent.width
                    spacing: bar.s(Theme.gapMd)

                    // Preview: misma card que el grid, no interactiva.
                    Rectangle {
                        Layout.preferredWidth: bar.s(150)
                        Layout.preferredHeight: bar.s(45)
                        radius: bar.s(Theme.radiusLg)
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: bar.s(Theme.gapMd)
                            spacing: bar.s(Theme.gapMd)
                            Item {
                                Layout.preferredWidth: bar.s(24)
                                Layout.preferredHeight: bar.s(24)
                                Column {
                                    anchors.centerIn: parent
                                    spacing: bar.s(Theme.gap2xs)
                                    Row {
                                        spacing: bar.s(Theme.gap2xs)
                                        Repeater {
                                            model: [0, 1]
                                            delegate: Rectangle { width: bar.s(9); height: bar.s(9); radius: bar.s(Theme.radiusXs); color: bar.paletteDraftColors[index] }
                                        }
                                    }
                                    Row {
                                        spacing: bar.s(Theme.gap2xs)
                                        Repeater {
                                            model: [0, 1]
                                            delegate: Rectangle { width: bar.s(9); height: bar.s(9); radius: bar.s(Theme.radiusXs); color: bar.paletteDraftColors[2 + index] }
                                        }
                                    }
                                }
                            }
                            Text {
                                text: bar.paletteDraftName.trim() !== "" ? bar.paletteDraftName : "New palette"
                                font.family: "Hack Nerd Font"
                                font.weight: Font.Bold
                                font.pixelSize: bar.s(12)
                                color: bar.colors.text
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Name + slug vivo
                    Column {
                        Layout.fillWidth: true
                        spacing: bar.s(Theme.gapXs)
                        Row {
                            spacing: bar.s(Theme.gapSm)
                            Text {
                                text: "Name"
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: "Hack Nerd Font"
                                font.weight: Font.Bold
                                font.pixelSize: bar.s(12)
                                color: bar.colors.text
                            }
                            TextField {
                                id: nameField
                                width: bar.s(220)
                                height: bar.s(28)
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: "Hack Nerd Font"
                                font.pixelSize: bar.s(13)
                                color: bar.colors.text
                                selectByMouse: true
                                maximumLength: 32
                                placeholderText: "My palette"
                                text: bar.paletteDraftName
                                onTextChanged: bar.paletteDraftName = text
                                background: Rectangle {
                                    color: Theme.surfaceContainerLow
                                    radius: bar.s(Theme.radiusMd)
                                    border.width: 1
                                    border.color: nameField.activeFocus ? bar.colors.mauve : Theme.outlineVariant
                                }
                            }
                        }
                        Text {
                            text: "slug: " + (bar.slugifyPaletteName(bar.paletteDraftName) !== ""
                                              ? bar.slugifyPaletteName(bar.paletteDraftName) : "—")
                            font.family: "Hack Nerd Font"
                            font.pixelSize: bar.s(11)
                            color: bar.colors.subtext0
                        }
                    }
                }

                // 8 slots base (3 por línea, como el editor base16)
                Flow {
                    id: baseFlow
                    width: parent.width
                    spacing: bar.s(Theme.gapSm)
                    Repeater {
                        model: 8
                        delegate: Item {
                            required property int index
                            width: (baseFlow.width - bar.s(Theme.gapSm) * 2) / 3
                            height: bar.s(30)
                            Row {
                                anchors.fill: parent
                                spacing: bar.s(Theme.gapSm)
                                Rectangle {
                                    width: bar.s(18)
                                    height: bar.s(18)
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: bar.s(Theme.radiusSm)
                                    border.width: 1
                                    border.color: Theme.outlineVariant
                                    color: bar.paletteDraftColors[index]
                                }
                                Text {
                                    text: bar.paletteBaseLabels[index]
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: bar.s(72)
                                    font.family: "Hack Nerd Font"
                                    font.pixelSize: bar.s(12)
                                    font.weight: Font.Bold
                                    color: bar.colors.text
                                    elide: Text.ElideRight
                                }
                                TextField {
                                    id: baseField
                                    width: bar.s(90)
                                    height: bar.s(28)
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: "Hack Nerd Font"
                                    font.pixelSize: bar.s(13)
                                    color: bar.colors.text
                                    selectByMouse: true
                                    maximumLength: 7
                                    text: bar.paletteDraftColors[index]
                                    validator: RegularExpressionValidator { regularExpression: /^#[0-9a-fA-F]{6}$/ }
                                    background: Rectangle {
                                        color: Theme.surfaceContainerLow
                                        radius: bar.s(Theme.radiusMd)
                                        border.width: 1
                                        border.color: baseField.activeFocus
                                            ? bar.colors.mauve
                                            : (baseField.acceptableInput ? Theme.outlineVariant : bar.colors.red)
                                    }
                                    onEditingFinished: bar.commitPaletteDraftColor(baseField, index)
                                    onActiveFocusChanged: {
                                        if (!baseField.activeFocus) bar.commitPaletteDraftColor(baseField, index);
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: bar.s(Theme.gapMd)
                    EditorButton {
                        bar: root.bar
                        icon: "󰄬"
                        label: "Create"
                        active: true
                        onActivated: root.bar.createPaletteFromDraft()
                    }
                    EditorButton {
                        bar: root.bar
                        label: "Cancel"
                        onActivated: {
                            root.bar.paletteCreateOpen = false;
                            root.bar.paletteCreateStatus = "";
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: bar.paletteCreateStatus
                        font.family: "Hack Nerd Font"
                        font.pixelSize: bar.s(12)
                        color: bar.colors.red
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Confirmación de borrado de la paleta activa ──
    Component {
        id: deleteCard
        Rectangle {
            width: deleteLoader.width
            height: implicitHeight
            implicitHeight: delCol.height + bar.s(Theme.gapLg) * 2
            radius: bar.s(Theme.radiusLg)
            color: Theme.surfaceContainerLow
            border.width: 1
            border.color: bar.colors.red

            Column {
                id: delCol
                x: bar.s(Theme.gapLg)
                y: bar.s(Theme.gapLg)
                width: parent.width - bar.s(Theme.gapLg) * 2
                spacing: bar.s(Theme.gapMd)

                Row {
                    spacing: bar.s(Theme.gapSm)
                    Text {
                        text: "󰆴"
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: "Hack Nerd Font"
                        font.pixelSize: bar.s(16)
                        color: bar.colors.red
                    }
                    Text {
                        text: "Delete palette '" + bar.paletteDisplayName(bar.activeSlug()) + "'?"
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: bar.s(14)
                        color: bar.colors.text
                    }
                }
                EditLabel {
                    bar: root.bar
                    width: parent.width
                    text: "Removes dock/palettes/" + bar.activeSlug() + ".json, its index.json entry and the session snapshot. This cannot be undone."
                    font.pixelSize: bar.s(12)
                    color: bar.colors.subtext0
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    width: parent.width
                    spacing: bar.s(Theme.gapMd)
                    EditorButton {
                        bar: root.bar
                        icon: "󰆴"
                        label: "Delete"
                        active: true
                        accentRole: "red"
                        onActivated: root.bar.deleteActivePalette()
                    }
                    EditorButton {
                        bar: root.bar
                        label: "Cancel"
                        onActivated: root.bar.cancelDeletePalette()
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: bar.paletteDeleteStatus
                        font.family: "Hack Nerd Font"
                        font.pixelSize: bar.s(12)
                        color: bar.colors.red
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
    // Palette card (3-col grid): preview swatches + name; click applies it.
    component PaletteCard: Rectangle {
        id: palCard
        required property var modelData
        readonly property var pal: modelData
        readonly property bool isSel: root.bar.bar.palette === pal.slug
        Layout.fillWidth: true
        height: bar.s(45)
        radius: bar.s(Theme.radiusLg)
        color: !bar ? "transparent"
            : (isSel ? bar.colors.mauve
                     : (palMa.containsMouse ? Qt.alpha(bar.colors.mauve, 0.1) : Theme.surfaceContainerLow))
        border.width: 1
        border.color: !bar ? "transparent"
            : ((isSel || palMa.containsMouse) ? bar.colors.mauve : Theme.outlineVariant)
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        RowLayout {
            anchors.fill: parent
            anchors.margins: bar.s(Theme.gapMd)
            spacing: bar.s(Theme.gapMd)
            Item {
                Layout.preferredWidth: bar.s(24)
                Layout.preferredHeight: bar.s(24)
                Column {
                    anchors.centerIn: parent
                    spacing: bar.s(Theme.gap2xs)
                    Row {
                        spacing: bar.s(Theme.gap2xs)
                        Repeater {
                            model: [0, 1]
                            delegate: Rectangle { width: bar.s(9); height: bar.s(9); radius: bar.s(Theme.radiusXs); color: palCard.pal.colors[index] }
                        }
                    }
                    Row {
                        spacing: bar.s(Theme.gap2xs)
                        Repeater {
                            model: [0, 1]
                            delegate: Rectangle { width: bar.s(9); height: bar.s(9); radius: bar.s(Theme.radiusXs); color: palCard.pal.colors[2 + index] }
                        }
                    }
                }
            }
            Text {
                text: palCard.pal.name
                font.family: "Hack Nerd Font"
                font.weight: palCard.isSel ? Font.Bold : Font.Medium
                font.pixelSize: bar.s(12)
                color: !bar ? "transparent" : (palCard.isSel ? bar.colors.crust : bar.colors.text)
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: palMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.bar.applyBar(Object.assign({}, root.bar.bar, { palette: palCard.pal.slug }))
        }
    }

}
