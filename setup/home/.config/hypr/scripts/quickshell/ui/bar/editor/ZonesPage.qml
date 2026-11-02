import QtQuick
import QtQuick.Controls
import "../edit"
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// ZonesPage — BarEditor tab (bar engine only): zone management + the zone
// editor cards (module chips + DnD targets).
//
// Fase 5 (look Guide): título s(24) Black, fila de EditorButton y card hero
// r21 (estilo sysBox GP:684-695) que envuelve la Column `zonasCol` con las
// ZoneEditorCard (contrato DnD intacto).
// Contract: receives the BarEditor root as `bar` (bar.s(), bar.colors,
// bar.bar, ...). NEVER touches ids of the editor root. Exposes the scroll
// Flickable via `flickable` and the zone cards column via `zonasCol` so the
// root can drive DnD auto-scroll + enumerate drop targets (phase 2).
//
// The zone CRUD buttons need BarLayout, which lives in the editor root: this
// page only declares addZone()/centerAll()/resetBar() and the root connects
// them (phase 2). ZoneEditorCard DnD talks to bar.startDnd/updateDnd/endDnd.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent   // Phase 3: el item del Loader ocupa la stage

    property var bar: null

    // Gate: el cuerpo se crea cuando bar ya está inyectado (initial
    // property aplicada tras la creación del root). Evita bindings
    // evaluados con bar null que quedaban muertos en negro.
    readonly property var flickable: body.item ? body.item.flickable : null
    readonly property var zonasCol: body.item ? body.item.zonasCol : null

    // Emitidas por los EditorButton de la página; el root del BarEditor las
    // conecta (BarLayout.addZone / arrangeAllInZone / defaultBar + applyBar).
    signal addZone()
    signal centerAll()
    signal resetBar()


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
            property alias zonasCol: zonasCol

            Flickable {
                id: pageFlick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: pageCol.height + bar.s(Theme.gapLg) * 2
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
                    x: bar.s(Theme.gapLg)
                    y: bar.s(Theme.gapLg)
                    width: pageFlick.width - bar.s(Theme.gapLg) * 2
                    spacing: bar.s(Theme.gapLg)
                    visible: true

                    // Título de página (GP:1007-1014)
                    Text {
                        text: "Zones"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: bar.s(24)
                        color: bar.colors.text
                    }

                    // Fila de acciones
                    Row {
                        width: parent.width
                        spacing: bar.s(Theme.gapMd)
                        EditorButton { bar: root.bar; label: "+ Add"; active: true; onActivated: root.addZone() }
                        EditorButton { bar: root.bar; label: "Center all"; onActivated: root.centerAll() }
                        EditorButton { bar: root.bar; label: "Default"; onActivated: root.resetBar() }
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Center all gathers every enabled island into the center zone. Tip: drag a chip onto another zone card to move the island there (release between chips to choose the exact spot)."
                        font.pixelSize: bar.s(12)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    // ── Zone cards (targets DnD) ──────────────────────────────────
                    // No surrounding hero card: each ZoneEditorCard is already a
                    // section card, so the zones stack directly on the page with
                    // the same rhythm as the other redesigned pages. Grid keeps
                    // the responsive equal-width columns; the id `zonasCol` is the
                    // DnD contract (BarEditor enumerates its children + auto-scroll).
                    Grid {
                        id: zonasCol
                        width: parent.width
                        spacing: bar.s(Theme.gapLg)
                        columns: Math.max(1, Math.floor((width + spacing) / (bar.s(760) + spacing)))
                        Repeater {
                            model: bar.bar.zones
                            delegate: ZoneEditorCard {
                                required property var modelData
                                required property int index
                                width: (zonasCol.width - (zonasCol.columns - 1) * zonasCol.spacing) / zonasCol.columns
                                bar: root.bar
                                zoneData: modelData
                                zoneIndex: index
                            }
                        }
                    }
                }
            }
        }
    }
}
