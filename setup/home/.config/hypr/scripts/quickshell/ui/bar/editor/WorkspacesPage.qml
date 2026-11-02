import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../edit"
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// WorkspacesPage — BarEditor tab: empty-workspace marker style.
//
// Fase 5 (look Guide): título s(24) Black + grid 2×2 de OptionCards
// (template cards GP:1276-1302, activo mauve/crust) + FieldCard para el
// carácter custom (visible solo con marcador "custom").
// Contract: receives the BarEditor root as `bar` (bar.s(), bar.colors,
// bar.bar, bar.applyBar, ...). NEVER touches ids of the editor root.
// Exposes the scroll Flickable via `flickable`.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent   // Phase 3: el item del Loader ocupa la stage

    property var bar: null

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
                        text: "Workspaces"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }

                    // Grid 2×2 de marcadores (cards template GP:1276-1302)
                    GridLayout {
                        width: parent.width
                        columns: 2
                        columnSpacing: bar.s(Theme.gapMd)
                        rowSpacing: bar.s(Theme.gapMd)
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "123"
                            label: "Numbers"
                            accentRole: "blue"
                            active: root.bar.bar.workspacesMarker === "number"
                            onActivated: root.bar.applyBar(Object.assign({}, root.bar.bar, { workspacesMarker: "number" }))
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "···"
                            label: "Dots"
                            active: root.bar.bar.workspacesMarker === "dot"
                            onActivated: root.bar.applyBar(Object.assign({}, root.bar.bar, { workspacesMarker: "dot" }))
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "abc"
                            label: "Letters"
                            accentRole: "green"
                            active: root.bar.bar.workspacesMarker === "letter"
                            onActivated: root.bar.applyBar(Object.assign({}, root.bar.bar, { workspacesMarker: "letter" }))
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            bar: root.bar
                            icon: "✦"
                            label: "Custom"
                            accentRole: "peach"
                            active: root.bar.bar.workspacesMarker === "custom"
                            onActivated: root.bar.applyBar(Object.assign({}, root.bar.bar, { workspacesMarker: "custom" }))
                        }
                    }

                    // Carácter custom (solo marcador custom): FieldCard
                    FieldCard {
                        width: parent.width
                        bar: root.bar
                        visible: bar.bar.workspacesMarker === "custom"
                        label: "Character"
                        value: root.bar.bar.workspacesMarkerText || ""
                        fieldWidth: 110
                        maxLength: 4
                        onEdited: (text) => {
                            let v = text.trim().slice(0, 4);
                            if (v !== root.bar.bar.workspacesMarkerText) {
                                root.bar.applyBar(Object.assign({}, root.bar.bar, { workspacesMarkerText: v }));
                            }
                        }
                    }

                    // Previews de cada caso: 5 workspaces de muestra; el caso activo
                    // toma mauve (fondo 18% + borde) como indicador de selección.
                    Rectangle {
                        width: parent.width
                        radius: bar.s(Theme.radiusLg)
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant
                        height: markerCol.height + bar.s(Theme.gapMd) * 2
                        Column {
                            id: markerCol
                            x: bar.s(Theme.gapMd); y: bar.s(Theme.gapMd)
                            width: parent.width - bar.s(Theme.gapMd) * 2
                            spacing: bar.s(Theme.gapMd)
                            EditLabel { bar: root.bar; text: "Preview"; font.pixelSize: bar.s(12); color: bar.colors.subtext0 }
                            GridLayout {
                                width: parent.width
                                columns: 4
                                columnSpacing: bar.s(Theme.gapMd)
                                Repeater {
                                    model: [
                                        { id: "number", label: "Numbers" },
                                        { id: "dot",    label: "Dots" },
                                        { id: "letter", label: "Letters" },
                                        { id: "custom", label: "Custom" }
                                    ]
                                    delegate: Rectangle {
                                        id: caseCard
                                        required property var modelData
                                        readonly property string caseId: modelData.id
                                        readonly property bool isActive: root.bar.bar.workspacesMarker === caseId
                                        Layout.fillWidth: true
                                        height: bar.s(78)
                                        radius: bar.s(Theme.radiusMd)
                                        color: isActive ? Qt.alpha(bar.colors.mauve, 0.18) : Theme.surfaceContainerLow
                                        border.width: 1
                                        border.color: isActive ? bar.colors.mauve : Theme.outlineVariant
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.bar.applyBar(Object.assign({}, root.bar.bar, { workspacesMarker: caseCard.caseId }))
                                        }
                                        Column {
                                            anchors.centerIn: parent
                                            spacing: bar.s(Theme.gapSm)
                                            Row {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                spacing: bar.s(Theme.gapXs)
                                                Repeater {
                                                    model: 5
                                                    delegate: Item {
                                                        required property int index
                                                        readonly property bool occupied: index === 1
                                                        width: bar.s(18); height: bar.s(18)
                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: bar.s(Theme.radiusXs)
                                                            color: parent.occupied
                                                                ? (caseCard.isActive ? Qt.alpha(bar.colors.mauve, 0.55) : Theme.surfaceContainer)
                                                                : Theme.surfaceContainerLow
                                                            border.width: 1
                                                            border.color: caseCard.isActive ? Qt.alpha(bar.colors.mauve, 0.8) : Theme.outlineVariant
                                                        }
                                                        Text {
                                                            anchors.centerIn: parent
                                                            visible: !parent.occupied
                                                            text: {
                                                                if (caseCard.caseId === "number") return String(index + 1);
                                                                if (caseCard.caseId === "dot") return "●";
                                                                if (caseCard.caseId === "letter") return String.fromCharCode(65 + index);
                                                                return root.bar.bar.workspacesMarkerText || "·";
                                                            }
                                                            font.family: "Hack Nerd Font"
                                                            font.pixelSize: bar.s(10)
                                                            color: caseCard.isActive ? bar.colors.mauve : bar.colors.text
                                                        }
                                                    }
                                                }
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: caseCard.modelData.label
                                                font.family: "Hack Nerd Font"
                                                font.pixelSize: bar.s(11)
                                                color: caseCard.isActive ? bar.colors.mauve : bar.colors.subtext0
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Only for empty workspaces — occupied ones keep showing their app icons. Tip: the Container bg option in each zone adds a themed background behind its islands without unifying them."
                        font.pixelSize: bar.s(12)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
