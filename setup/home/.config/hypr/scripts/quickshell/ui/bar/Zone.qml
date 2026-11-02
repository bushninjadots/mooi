import QtQuick
import QtQuick.Effects
import Quickshell
import "BarLayout.js" as BarLayout
import "../../core"

// ============================================================================
// Zone — renders ONE zone of the bar.
//
// Zones are pure data (see BarLayout.js). This component turns a zone object
// into a row (horizontal bar) or column (vertical bar) of module pills,
// positioned by the zone's `align` (start → center → end along the main axis).
// It also draws the optional "unified" pill behind the whole zone and forwards
// per-zone border styling to the modules via the shared module contract
// (bar, colors, zoneReady, slotIndex, effectiveBorderWidth/Color, unified).
//
// Drag & drop (Phase D2): every module slot carries a drag MouseArea. Once the
// pointer moves past the threshold the bar takes over (bar.startDrag) and,
// while bar.dragBusy, this zone exposes hit-test helpers (barPointToInsert /
// containsBarPoint) so the bar can reorder modules live under the cursor.
// Zone entrance animations are suppressed while a drag is in progress.
// ============================================================================

Item {
    id: zoneRoot

    required property var bar
    required property var colors
    required property var zoneData
    required property int zoneIndex

    readonly property bool isHorizontal: bar.orientation === "horizontal"
    readonly property bool unified: zoneData.unify === true
    // Block fill mode ("default" | "on" | "off"), part of the island fill API
    // in BarLayout.js. Islands without their own value inherit it.
    readonly property string zoneFillMode: BarLayout.normalizeFillMode(zoneRoot.zoneData.fill)

    // Zone marker used by the bar's drag manager to find zone delegates.
    property bool isBarZone: true
    // Id of the module currently being dragged (set by the bar).
    property string dragId: ""

    // Main-axis alignment: start | center | end
    anchors.left: undefined
    anchors.right: undefined
    anchors.top: undefined
    anchors.bottom: undefined
    anchors.horizontalCenter: undefined
    anchors.verticalCenter: undefined

    property bool ready: false
    Timer {
        running: bar.isStartupReady
        interval: 80 + zoneIndex * 90
        onTriggered: zoneRoot.ready = true
    }

    // --- sizing / anchoring ------------------------------------------------
    height: isHorizontal ? parent.height : (ready ? flowV.implicitHeight : 0)
    width: isHorizontal ? (ready ? flowH.implicitWidth : 0) : parent.width

    // Entrance animation: fade + small slide from the bar edge.
    opacity: ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    transform: Translate {
        x: zoneRoot.isHorizontal ? (zoneRoot.slideX * (zoneRoot.ready ? 0 : 1)) : 0
        y: !zoneRoot.isHorizontal ? (zoneRoot.slideY * (zoneRoot.ready ? 0 : 1)) : 0
        Behavior on x { NumberAnimation { duration: 550; easing.type: Easing.OutExpo } }
        Behavior on y { NumberAnimation { duration: 550; easing.type: Easing.OutExpo } }
    }

    readonly property int slideX: zoneRoot.isHorizontal ? (zoneData.align === "end" ? bar.s(40) : zoneData.align === "start" ? -bar.s(40) : 0) : 0
    readonly property int slideY: !zoneRoot.isHorizontal ? (zoneData.align === "end" ? bar.s(40) : zoneData.align === "start" ? -bar.s(40) : 0) : 0

    function applyAnchors() {
        let p = zoneRoot.parent;
        if (!p) return;
        zoneRoot.anchors.left = undefined;
        zoneRoot.anchors.right = undefined;
        zoneRoot.anchors.top = undefined;
        zoneRoot.anchors.bottom = undefined;
        zoneRoot.anchors.horizontalCenter = undefined;
        zoneRoot.anchors.verticalCenter = undefined;
        if (zoneRoot.isHorizontal) {
            zoneRoot.anchors.verticalCenter = p.verticalCenter;
            if (zoneData.align === "start") zoneRoot.anchors.left = p.left;
            else if (zoneData.align === "end") zoneRoot.anchors.right = p.right;
            else zoneRoot.anchors.horizontalCenter = p.horizontalCenter;
        } else {
            zoneRoot.anchors.horizontalCenter = p.horizontalCenter;
            if (zoneData.align === "start") zoneRoot.anchors.top = p.top;
            else if (zoneData.align === "end") zoneRoot.anchors.bottom = p.bottom;
            else zoneRoot.anchors.verticalCenter = p.verticalCenter;
        }
    }

    onParentChanged: applyAnchors()
    onIsHorizontalChanged: Qt.callLater(() => { try { applyAnchors(); } catch (e) {} })
    onZoneDataChanged: {
        // During a live drag the model is rewritten constantly; replaying the
        // entrance cascade on every hop would flicker the whole bar.
        if (bar && bar.dragBusy) {
            Qt.callLater(() => { try { applyAnchors(); } catch (e) {} });
            return;
        }
        zoneRoot.ready = false;
        Qt.callLater(() => { try { applyAnchors(); } catch (e) {} });
    }
    Component.onCompleted: applyAnchors()

    // --- optional container behind the whole zone ("capsule in a capsule") ----
    // zoneData.zoneBg = a colors.* role name ("" = off). Draws a translucent
    // rounded panel that hugs the zone's islands WITHOUT unifying them (each
    // ModulePill keeps its own fill on top). Not drawn when the zone is
    // unified (unify already provides the single background).
    // Drop shadow for the zone capsule (same shell-wide "shadows" config; the
    // bar pads its surface so this is never clipped).
    RectangularShadow {
        visible: zoneContainer.visible && bar.shadowOn === true
        anchors.centerIn: parent
        width: zoneContainer.width
        height: zoneContainer.height
        radius: zoneContainer.radius
        blur: bar.shadowBlur
        spread: bar.shadowSpread
        offset: Qt.vector2d(bar.shadowOffX, bar.shadowOffY)
        color: Qt.rgba(0, 0, 0, bar.shadowOpacity)
        opacity: zoneContainer.opacity
    }
    Rectangle {
        id: zoneContainer
        visible: zoneData.zoneBg !== "" && !zoneRoot.unified && zoneRoot.ready
        anchors.centerIn: parent
        // ~s(2) rim per side so the container reads as a soft neumorphic
        // cushion peeking out from behind the islands.
        width: parent.width + bar.s(4)
        height: parent.height + bar.s(4)
        radius: bar.pillRadius(bar.pillHeight + bar.s(4))
        opacity: 0
        color: {
            let c = colors[zoneData.zoneBg] || colors.surface0;
            return Qt.rgba(c.r, c.g, c.b, (zoneData.zoneBgSolid === true ? 1.0 : 0.35) * colors.glassAlpha);
        }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 200 } }
        onVisibleChanged: if (zoneContainer.visible) zoneContainer.opacity = 1
    }

    // --- unified pill behind the whole zone ---------------------------------
    RectangularShadow {
        visible: unifyPill.visible && bar.shadowOn === true
        anchors.fill: unifyPill
        radius: unifyPill.radius
        blur: bar.shadowBlur
        spread: bar.shadowSpread
        offset: Qt.vector2d(bar.shadowOffX, bar.shadowOffY)
        color: Qt.rgba(0, 0, 0, bar.shadowOpacity)
    }
    Rectangle {
        id: unifyPill
        visible: zoneRoot.unified && zoneRoot.zoneFillMode !== "off"
        anchors.fill: parent
        radius: isHorizontal ? bar.pillRadius(bar.pillHeight) : bar.pillRadius(bar.pillWidth)
        color: Qt.rgba(colors.surface0.r, colors.surface0.g, colors.surface0.b, colors.glassAlpha)
        border.width: zoneData.borderWidth || 0
        border.color: colors[zoneData.borderColor] || colors.surface1
        Behavior on border.width { NumberAnimation { duration: 200 } }
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    // --- module flow (shared delegate) ---------------------------------------
    // One wrapper per ENABLED module: it hosts the module Loader plus the drag
    // MouseArea. The wrapper is the flow child (Row/Column measure it), so the
    // drag overlay never interferes with the module's own click handling.
    Component {
        id: moduleDelegate
        Item {
            id: slotWrap
            required property string modelData
            required property int index
            // Occupies the full band on the CROSS axis so every island is
            // centered vertically (horizontal bars) / horizontally (vertical
            // bars) regardless of its own height — mixed-height islands stay
            // aligned. The module content is centered inside below.
            width: zoneRoot.isHorizontal ? slotLoader.width : zoneRoot.width
            height: zoneRoot.isHorizontal ? zoneRoot.height : slotLoader.height

            // Marker used by the zone hit-test to enumerate module slots.
            property bool isBarSlot: true
            readonly property string slotModuleId: modelData

            // Lift the island that is being dragged (visual only — layout
            // position follows the live model reorder done by the bar).
            scale: (bar.dragBusy && modelData === bar.dragId) ? 1.08 : 1.0
            opacity: (bar.dragBusy && modelData === bar.dragId) ? 0.9 : 1.0
            Behavior on scale { enabled: !bar.dragBusy; NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
            Behavior on opacity { NumberAnimation { duration: 150 } }
            z: (bar.dragBusy && modelData === bar.dragId) ? 50 : 0

            Loader {
                id: slotLoader
                anchors.centerIn: slotWrap
                width: item ? item.implicitWidth : 0
                height: item ? item.implicitHeight : 0

                // Resolve the component for this slot. Core modules come from the
                // JS catalog synchronously; plugin-provided modules (manifest
                // provides.bar.modules) are resolved from PluginsCatalog, which is
                // populated ASYNCHRONOUSLY by the plugin scan — so on the very
                // first pass it is still empty and returns "". We therefore retry
                // whenever the catalog updates (Connections below) instead of
                // giving up forever.
                function resolveComp(id) {
                    let mod = BarLayout.getModule(id);
                    let comp = mod ? mod.component : "";
                    if (comp === "") comp = PluginsCatalog.barModuleComp(id);
                    return comp;
                }
                function ensureLoaded() {
                    if (slotLoader.item !== null) return;      // already mounted
                    let comp = resolveComp(slotWrap.modelData);
                    if (comp === "") return;                   // not resolvable (yet)
                    // Module components live in bar/modules/ (same level as this file).
                    setSource(Qt.resolvedUrl(comp), {
                        "bar": zoneRoot.bar,
                        "colors": zoneRoot.colors,
                        "zoneReady": Qt.binding(() => zoneRoot.ready),
                        "slotIndex": slotWrap.index,
                        "effectiveBorderWidth": Qt.binding(() => zoneRoot.unified ? 0 : (zoneRoot.zoneData.borderWidth || 0)),
                        "effectiveBorderColor": Qt.binding(() => zoneRoot.unified ? "surface1" : (zoneRoot.zoneData.borderColor || "surface1")),
                        "unified": Qt.binding(() => zoneRoot.unified),
                        "fillMode": zoneRoot.zoneFillMode
                    });
                }
                Component.onCompleted: ensureLoaded()
                Connections {
                    target: PluginsCatalog
                    function onRevChanged() { slotLoader.ensureLoaded(); }
                }
            }

            // --- drag start handler ---------------------------------------------
            // Small movements stay clicks (ModulePill handles them); only after
            // the threshold does this area hand the gesture to the bar.
            //
            // Click pass-through: this area sits ABOVE the module content, so
            // without propagation it would swallow every island click. We
            // propagate composed events so presses/releases reach the
            // ModulePill MouseArea underneath; when a real drag happened, the
            // bar sets bar.consumeNextModuleClick so the pill's own click
            // (fired from the propagated release) is discarded once.
            MouseArea {
                id: slotDragArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                propagateComposedEvents: true
                enabled: bar.dragModulesEnabled

                property point pressPos: Qt.point(0, 0)
                property bool dragStarted: false
                property bool canDrag: bar.dragModulesEnabled

                onPressed: mouse => {
                    pressPos = Qt.point(mouse.x, mouse.y);
                    dragStarted = false;
                }
                onPositionChanged: mouse => {
                    if (!canDrag || !pressed) return;
                    if (!dragStarted) {
                        let dx = mouse.x - pressPos.x;
                        let dy = mouse.y - pressPos.y;
                        let dist = zoneRoot.isHorizontal ? Math.abs(dx) : Math.abs(dy);
                        if (dist > bar.s(12)) {
                            dragStarted = true;
                            zoneRoot.bar.startDrag(slotWrap.modelData);
                            if (!zoneRoot.bar.dragBusy) { dragStarted = false; return; }
                        }
                    }
                    if (dragStarted && zoneRoot.bar.dragBusy) {
                        // Everything below the threshold is a click; past it the
                        // bar's drag manager owns the gesture and we just feed
                        // it pointer positions (MouseArea keeps the grab while
                        // the button is held, even outside this item).
                        let p = slotWrap.mapToItem(zoneRoot.bar, mouse.x, mouse.y);
                        zoneRoot.bar.updateDragAt(p.x, p.y);
                    }
                }
                onReleased: mouse => {
                    if (dragStarted && zoneRoot.bar.dragBusy) {
                        // The propagated release is about to reach the pill's
                        // MouseArea and fire its clicked(): consume it once.
                        zoneRoot.bar.consumeNextModuleClick = true;
                        let p = slotWrap.mapToItem(zoneRoot.bar, mouse.x, mouse.y);
                        zoneRoot.bar.endDragAt(p.x, p.y);
                    }
                    dragStarted = false;
                }
                onCanceled: {
                    if (dragStarted && zoneRoot.bar.dragBusy) zoneRoot.bar.cancelDrag();
                    dragStarted = false;
                }
            }
        }
    }

    // --- drag hit-test helpers (called by the bar's drag manager) ------------
    // Map a point in bar-window coordinates to an insertion slot.
    // Returns null when the point is outside this zone; otherwise
    // { zoneId, index } where `index` counts ENABLED modules ignoring the
    // module currently being dragged (bar.dragId).
    function barPointToInsert(px, py) {
        let q = zoneRoot.mapFromItem(zoneRoot.bar, px, py);
        if (q.x < 0 || q.y < 0 || q.x > zoneRoot.width || q.y > zoneRoot.height) return null;
        let flow = zoneRoot.isHorizontal ? flowH : flowV;
        if (!flow || !flow.visible || !zoneRoot.ready) return null;

        let qMain = zoneRoot.isHorizontal ? q.x : q.y;
        let flowStart = zoneRoot.isHorizontal ? flow.x : flow.y;
        let dragged = zoneRoot.bar && zoneRoot.bar.dragBusy ? zoneRoot.bar.dragId : "";

        let kids = flow.children;
        let countBefore = 0;
        for (let i = 0; i < kids.length; i++) {
            let c = kids[i];
            if (!c || !c.isBarSlot) continue;
            let id = c.slotModuleId !== undefined ? c.slotModuleId : "";
            if (!id || id === dragged) continue;
            let start = flowStart + (zoneRoot.isHorizontal ? c.x : c.y);
            let size = zoneRoot.isHorizontal ? c.width : c.height;
            let center = start + size / 2;
            if (qMain > center) countBefore++;
        }
        return { zoneId: zoneData.id, index: countBefore };
    }

    // Is a bar-window point inside this zone's bounds?
    function containsBarPoint(px, py) {
        let q = zoneRoot.mapFromItem(zoneRoot.bar, px, py);
        return q.x >= 0 && q.y >= 0 && q.x <= zoneRoot.width && q.y <= zoneRoot.height;
    }

    // Row (horizontal bar) OR Column (vertical bar) of modules.
    // Positioners default to their implicit main-axis size, so we only pin the
    // cross axis. (No anchors.fill here — it would create a circular width
    // dependency with zoneRoot's size.)
    Row {
        id: flowH
        visible: zoneRoot.isHorizontal && zoneRoot.ready
        x: zoneRoot.unified ? bar.s(6) : 0
        y: (zoneRoot.parent.height - height) / 2
        height: Math.min(parent.height, implicitHeight)
        spacing: zoneRoot.unified ? 0 : bar.s(8)
        Repeater {
            id: flowRepeaterH
            model: BarLayout.zoneModel(zoneRoot.zoneData)
            delegate: moduleDelegate
        }
    }

    Column {
        id: flowV
        visible: !zoneRoot.isHorizontal && zoneRoot.ready
        x: (zoneRoot.parent.width - width) / 2
        y: zoneRoot.unified ? bar.s(6) : 0
        width: Math.min(parent.width, implicitWidth)
        spacing: zoneRoot.unified ? 0 : bar.s(8)
        Repeater {
            id: flowRepeaterV
            model: BarLayout.zoneModel(zoneRoot.zoneData)
            delegate: moduleDelegate
        }
    }
}
