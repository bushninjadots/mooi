import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../core"
import "../core/WindowRegistry.js" as Registry

import "./notifications" as Notifs

PanelWindow {
    id: masterWindow
    color: "transparent"

    Caching { id: paths }

    IpcHandler {
        target: "main"

        function forceReload(): void {
            Quickshell.reload(true)
        }

        function handleCommand(cmd: string, targetWidget: string, arg: string): void {
            cmd = cmd || "";
            targetWidget = targetWidget || "";
            arg = arg || "";

            let isClosing = (masterWindow.currentActive !== "hidden" && !masterWindow.isVisible);
            let effectivelyActive = isClosing ? "hidden" : masterWindow.currentActive;

            if (cmd === "close") {
                switchWidget("hidden", "");
            } else if (cmd === "toggle" || cmd === "open") {
                delayedClear.stop();

                if (targetWidget === effectivelyActive) {
                    let currentItem = widgetStack.currentItem;

                    if (arg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== arg) {
                        currentItem.activeMode = arg;
                    } else if (cmd === "toggle") {
                        switchWidget("hidden", "");
                    }
                } else if (getLayout(targetWidget)) {
                    switchWidget(targetWidget, arg);
                }
            } else if (getLayout(cmd)) {
                let legacyArg = targetWidget;
                delayedClear.stop();

                if (cmd === effectivelyActive) {
                    let currentItem = widgetStack.currentItem;
                    if (legacyArg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== legacyArg) {
                        currentItem.activeMode = legacyArg;
                    } else {
                        switchWidget("hidden", "");
                    }
                } else {
                    switchWidget(cmd, legacyArg);
                }
            }
        }
    }

    WlrLayershell.namespace: "qs-master"
    WlrLayershell.layer: WlrLayer.Overlay

    exclusionMode: ExclusionMode.Ignore
    focusable: true

    implicitWidth: masterWindow.screen.width
    implicitHeight: masterWindow.screen.height

    visible: isVisible

    mask: Region { item: topBarHole; intersection: Intersection.Xor }

    Item {
        id: topBarHole
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 48

        anchors.leftMargin: (masterWindow.currentActive !== "hidden" && masterWindow.animX < 10 && masterWindow.animY < height) ? masterWindow.animW : 0
        anchors.rightMargin: (masterWindow.currentActive !== "hidden" && (masterWindow.animX + masterWindow.animW) > (parent.width - 10) && masterWindow.animY < height) ? masterWindow.animW : 0

        Behavior on anchors.leftMargin {
            enabled: masterWindow.currentActive !== "hidden"
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on anchors.rightMargin {
            enabled: masterWindow.currentActive !== "hidden"
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: masterWindow.isVisible
        onClicked: switchWidget("hidden", "")
    }

    // =========================================================
    // --- DAEMON: PRELOADING SYSTEM
    // =========================================================
    Item {
        id: preloaderContainer
        visible: false
    }

    property var widgetCache: ({})

    function preloadWidget(name) {
        if (widgetCache[name]) return;
        let t = getLayout(name);
        if (!t || !t.comp) return;
        // t.comp is a URL STRING from WindowRegistry — it has no createObject.
        // Create a real Component first (the old code called createObject on the
        // string, which always threw and silently killed the whole preload).
        let comp = Qt.createComponent(compUrl(t.comp));
        if (!comp) return;
        // El Component se mantiene vivo mientras existan sus objetos: destruirlo
        // invalidaba el contexto de los widgets creados (QQmlVMEMetaObject:
        // "attempted to evaluate a function in an invalid context" -> los popups
        // no abrian). Sin closures: funciones nombradas en este scope.
        function instantiate() {
            if (comp.status !== Component.Ready) return false;
            // Only force the widget invisible at preload; notifModel/liveNotifs
            // and layout props are injected when the widget is actually shown
            // (some widgets don't declare them, so passing them here warns).
            let obj = comp.createObject(preloaderContainer, { "visible": false });
            if (obj) widgetCache[name] = obj;
            return true;
        }
        if (comp.status === Component.Ready) {
            instantiate();
        } else if (comp.status === Component.Loading) {
            function onStatusChanged() {
                if (comp.status === Component.Ready) instantiate();
            }
            comp.statusChanged.connect(onStatusChanged);
        }
    }

    Component.onCompleted: {
        preloadStaggerTimer.start();
    }

    Timer {
        id: preloadStaggerTimer
        interval: 900
        repeat: false
        onTriggered: {
            preloadWidget("search");
            preloadWidget("help");
        }
    }

    // =========================================================

    property string currentActive: "hidden"

    onCurrentActiveChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + currentActive + "' > " + paths.runDir + "/current_widget"]);
    }

    property bool isVisible: false
    property string activeArg: ""
    property bool disableMorph: false

    property int morphDuration: 230
    property int morphDurationSwitch: 210
    property int exitDuration: 160

    property real animW: 1
    property real animH: 1
    property real animX: 0
    property real animY: 0

    property real targetW: 1
    property real targetH: 1

    property real globalUiScale: 1.0

    // =========================================================
    // --- PANEL/POPUP SHADOWS (settings.shadows) ---
    // Drawn in QML: Hyprland does not decorate layer-shell surfaces. Values
    // scale with the UI scale; each panel may expose its own `shadowRadius`
    // (e.g. the launcher) and otherwise the global radius is used.
    // shadowSettings is refreshed by the settings.json watcher below, so both
    // page edits and external edits apply live.
    // =========================================================
    property var shadowSettings: ({})
    readonly property real shadowUiScale: masterWindow.screen
        ? Registry.getScale(masterWindow.screen.width, masterWindow.screen.height, masterWindow.globalUiScale)
        : 1.0
    readonly property bool shadowsEnabled: shadowSettings.enabled !== false
    readonly property real shadowBlur: (shadowSettings.blur !== undefined ? shadowSettings.blur : 26) * shadowUiScale
    readonly property real shadowSpread: (shadowSettings.spread !== undefined ? shadowSettings.spread : 0) * shadowUiScale
    readonly property real shadowOffsetX: (shadowSettings.offsetX !== undefined ? shadowSettings.offsetX : 0) * shadowUiScale
    readonly property real shadowOffsetY: (shadowSettings.offsetY !== undefined ? shadowSettings.offsetY : 6) * shadowUiScale
    readonly property real shadowRadius: (shadowSettings.radius !== undefined ? shadowSettings.radius : 18) * shadowUiScale
    readonly property real shadowOpacity: shadowSettings.opacity !== undefined ? shadowSettings.opacity : 0.5

    // =========================================================
    // --- DAEMON: NOTIFICATION HANDLING
    // =========================================================
    ListModel { id: globalNotificationHistory }
    ListModel { id: activePopupsModel }

    property var liveNotifs: ({})
    property int _popupCounter: 0

    // --- NEW: Startup Grace Period Flag & Timer ---
    property bool isStartup: true
    Timer {
        interval: 500
        running: true
        onTriggered: masterWindow.isStartup = false
    }

    function removePopup(uid) {
        for (let i = 0; i < activePopupsModel.count; i++) {
            if (activePopupsModel.get(i).uid === uid) {
                activePopupsModel.remove(i);
                break;
            }
        }
    } 

    NotificationServer {
        id: globalNotificationServer
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: (n) => {
            n.tracked = true;

            let extractedActions = [];
            if (n.actions) {
                for (let i = 0; i < n.actions.length; i++) {
                    extractedActions.push({
                        "id": n.actions[i].identifier || "",
                        "text": n.actions[i].text || n.actions[i].name || "Action"
                    });
                }
            }

            masterWindow._popupCounter++;
            let currentUid = masterWindow._popupCounter;

            // Always store the live object so the history center can interact with it
            masterWindow.liveNotifs[currentUid] = n;

            let notifData = {
                "appName":     n.appName  !== "" ? n.appName  : "System",
                "summary":     n.summary  !== "" ? n.summary  : "No Title",
                "body":        n.body     !== "" ? n.body     : "",
                "iconPath":    n.appIcon  !== "" ? n.appIcon  : "",
                "actionsJson": JSON.stringify(extractedActions),
                "uid":         currentUid,
                "notif":       n
            };

            // Always silently add to the history list
            globalNotificationHistory.insert(0, notifData);

            // --- CHANGED: Only trigger the visual popup if we are past the startup phase ---
            if (!masterWindow.isStartup) {
                activePopupsModel.append(notifData);
                osdPopups.storeNotif(currentUid, n);
            }
        }
    }

    property var notifModel: globalNotificationHistory

    Notifs.NotificationPopups {
        id: osdPopups
        popupModel: activePopupsModel
        uiScale: masterWindow.globalUiScale
        onRemoveRequested: (uid) => masterWindow.removePopup(uid)
    }
    onGlobalUiScaleChanged: { handleNativeScreenChange(); }

    Process {
        id: settingsReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                        let parsed = JSON.parse(this.text);
                        if (parsed.uiScale !== undefined && masterWindow.globalUiScale !== parsed.uiScale) {
                            masterWindow.globalUiScale = parsed.uiScale;
                        }
                        masterWindow.shadowSettings = (parsed.shadows && typeof parsed.shadows === "object")
                            ? parsed.shadows : {};
                    }
                } catch (e) {
                    console.log("Error parsing settings.json in main.qml:", e);
                }
            }
        }
    }

    Process {
        id: settingsWatcher
        command: ["bash", "-c", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                settingsReader.running = false;
                settingsReader.running = true;
                settingsWatcher.running = false;
                settingsWatcher.running = true;
            }
        }
    }

    // =========================================================
    // --- LAYOUT CACHE
    // =========================================================
    property var    _layoutCache:    ({})
    property string _layoutCacheKey: ""

    // Posicion configurable por widget (settings.widgets.<name>.position).
    function userWidgetPosition(name) {
        let pos = "default";
        try {
            let w = Config.rawSettings.widgets;
            if (w && w[name] && w[name].position) pos = w[name].position;
        } catch(e) {}
        return pos;
    }

    function getLayout(name) {
        // El layout se calcula contra el TAMANO DE PANTALLA, no contra la
        // ventana master (que en estado oculto queda en animW/animH = 1px):
        // con mw=1 los rx/ry salian negativos y el popup nacia fuera de pantalla.
        let sw = masterWindow.screen ? masterWindow.screen.width  : masterWindow.width;
        let sh = masterWindow.screen ? masterWindow.screen.height : masterWindow.height;
        let pos = userWidgetPosition(name);
        let key = name + "|" + sw + "|" + sh + "|" + masterWindow.globalUiScale + "|" + pos
                  + "|" + PluginsCatalog.rev;
        if (_layoutCacheKey === key) return _layoutCache[key];
        let result = Registry.getLayout(name, 0, 0, sw, sh, masterWindow.globalUiScale);
        if (!result) result = pluginPanelLayout(name, sw, sh);
        result = Registry.positionLayout(result, pos, sw, sh, masterWindow.globalUiScale);
        _layoutCache = {};
        _layoutCache[key] = result;
        _layoutCacheKey = key;
        return result;
    }

    // Plugin panels (equisdots plugin standard → provides.panels): a plugin
    // declares `provides.panels.<name> = { comp, w, h, label? }` (comp is
    // relative to the plugin UI root; w/h use the same 1920x1080 base units as
    // the core registry). Enabled, compatible plugins only; the core never
    // knows plugin ids.
    function pluginPanelEntry(name) {
        let list = PluginsCatalog.plugins || [];
        for (let i = 0; i < list.length; i++) {
            let p = list[i] || {};
            if (p.enabled !== true) continue;
            if (p.compat && p.compat.ok === false) continue;
            let panels = (p.provides && typeof p.provides === "object") ? p.provides.panels : null;
            if (panels && typeof panels === "object" && panels[name]) return { p: p, e: panels[name] };
        }
        return null;
    }

    function pluginPanelLayout(name, sw, sh) {
        let hit = pluginPanelEntry(name);
        if (!hit) return null;
        let e = hit.e || {};
        if (!e.comp) return null;
        let scale = Registry.getScale(sw, sh, masterWindow.globalUiScale);
        let w = Math.max(1, Registry.s(Number(e.w) > 0 ? Number(e.w) : 600, scale));
        let h = Math.max(1, Registry.s(Number(e.h) > 0 ? Number(e.h) : 400, scale));
        let comp = PluginsCatalog.isManaged(hit.p)
            ? "ui/plugins/" + hit.p.id + "/" + String(e.comp).replace(/^\.\//, "")
            : PluginsCatalog.uiPath(hit.p, e.comp);
        return { w: w, h: h, rx: Math.floor((sw - w) / 2), ry: Math.floor((sh - h) / 2), comp: comp };
    }

    // Panel comp → URL: root-relative for managed plugins (inside the shell
    // tree), file:// for user plugins (their own folder).
    function compUrl(comp) {
        comp = String(comp || "");
        if (comp === "") return "";
        if (comp.charAt(0) === "/") return "file://" + comp;
        return Qt.resolvedUrl("../" + comp);
    }

    Connections {
        target: masterWindow
        function onWidthChanged()  { _layoutCacheKey = ""; handleNativeScreenChange(); }
        function onHeightChanged() { _layoutCacheKey = ""; handleNativeScreenChange(); }
    }

    function handleNativeScreenChange() {
        if (masterWindow.currentActive === "hidden") return;

        let t = getLayout(masterWindow.currentActive);
        if (!t) return;

        let currentItem = widgetStack.currentItem;
        let finalW = (currentItem && currentItem.targetMasterWidth  !== undefined) ? currentItem.targetMasterWidth  : t.w;
        let finalH = (currentItem && currentItem.targetMasterHeight !== undefined) ? currentItem.targetMasterHeight : t.h;
        let finalX = t.rx;
        // Recentrar solo con posición "default": una posición elegida en
        // Engine (settings.widgets.<name>.position) manda.
        if (masterWindow.userWidgetPosition(masterWindow.currentActive) === "default"
            && currentItem && currentItem.targetMasterWidth !== undefined && finalW !== t.w) {
            finalX = Math.floor((masterWindow.width / 2) - (finalW / 2));
        }
        let finalY = t.ry;
        // Soporte opcional (retrocompatible): widgets que calculan su propia
        // posición en pantalla (p.ej. el launcher con anclaje top/bottom/…).
        if (currentItem && currentItem.targetMasterX !== undefined) finalX = currentItem.targetMasterX;
        if (currentItem && currentItem.targetMasterY !== undefined) finalY = currentItem.targetMasterY;

        masterWindow.animX = finalX;
        masterWindow.animY = finalY;
        masterWindow.animW = finalW;
        masterWindow.animH = finalH;
        masterWindow.targetW = finalW;
        masterWindow.targetH = finalH;
    }

    // Aplica los targetMaster* del widget activo al morph. Se usa al abrir el
    // widget y, vía Connections, cuando el propio widget cambia sus targets en
    // vivo (p. ej. el panel Settings ensanchándose en la página Guide).
    function applyMasterTargets() {
        let it = widgetStack.currentItem;
        if (!it) return;
        if (it.targetMasterWidth !== undefined) {
            masterWindow.animW = it.targetMasterWidth;
            masterWindow.targetW = it.targetMasterWidth;
            if (masterWindow.userWidgetPosition(masterWindow.currentActive) === "default") {
                masterWindow.animX = Math.floor((masterWindow.width / 2) - (it.targetMasterWidth / 2));
            } else {
                // Posición elegida en Engine: recalcular X con el layout real.
                let t = masterWindow.getLayout(masterWindow.currentActive);
                if (t) masterWindow.animX = t.rx;
            }
        }
        if (it.targetMasterHeight !== undefined) {
            masterWindow.animH = it.targetMasterHeight;
            masterWindow.targetH = it.targetMasterHeight;
        }
        if (it.targetMasterX !== undefined) masterWindow.animX = it.targetMasterX;
        if (it.targetMasterY !== undefined) masterWindow.animY = it.targetMasterY;
    }

    Connections {
        target: widgetStack.currentItem
        function onTargetMasterWidthChanged()  { masterWindow.applyMasterTargets(); }
        function onTargetMasterHeightChanged() { masterWindow.applyMasterTargets(); }
        function onTargetMasterXChanged()      { masterWindow.applyMasterTargets(); }
        function onTargetMasterYChanged()      { masterWindow.applyMasterTargets(); }
    }

    // =========================================================
    // --- SCREEN FRAME BUS (core/FrameBus.qml)
    // Publishes the live morph box of the active widget so the screen frame
    // (ui/frame/Frame.qml) can carve its notch in sync with the open/close
    // animation. `edge` comes from the widget when it exposes a `frameEdge`
    // property (edge-anchored panels like the launcher); centred panels omit it.
    // =========================================================
    function publishFrameBox() {
        if (isVisible && currentActive !== "hidden") {
            let it = widgetStack.currentItem;
            let edge = (it && it.frameEdge !== undefined) ? it.frameEdge : "";
            FrameBus.publish(animX, animY, animW, animH, edge);
        } else {
            FrameBus.clear();
        }
    }

    Connections {
        target: masterWindow
        function onAnimXChanged()        { masterWindow.publishFrameBox(); }
        function onAnimYChanged()        { masterWindow.publishFrameBox(); }
        function onAnimWChanged()        { masterWindow.publishFrameBox(); }
        function onAnimHChanged()        { masterWindow.publishFrameBox(); }
        function onIsVisibleChanged()    { masterWindow.publishFrameBox(); }
        function onCurrentActiveChanged() { masterWindow.publishFrameBox(); }
    }

    onIsVisibleChanged: {
        if (isVisible) widgetStack.forceActiveFocus();
    }

    // =========================================================
    // --- PANEL/POPUP SHADOW ---
    // Sits behind the animated box and follows it (the box's Behaviors are
    // read through the bindings, so the shadow morphs with it). Rectangular
    // corner radius from the current panel's `shadowRadius` when defined.
    // =========================================================
    RectangularShadow {
        id: panelShadow
        visible: masterWindow.shadowsEnabled && masterWindow.isVisible && widgetStack.currentItem !== null
        x: widgetBox.x
        y: widgetBox.y
        width: widgetBox.width
        height: widgetBox.height
        radius: (widgetStack.currentItem && widgetStack.currentItem.shadowRadius !== undefined)
                ? widgetStack.currentItem.shadowRadius
                : masterWindow.shadowRadius
        blur: masterWindow.shadowBlur
        spread: masterWindow.shadowSpread
        offset: Qt.vector2d(masterWindow.shadowOffsetX, masterWindow.shadowOffsetY)
        color: Qt.rgba(0, 0, 0, masterWindow.shadowOpacity)
        opacity: widgetBox.opacity
    }

    // =========================================================
    // --- ANIMATED BOUNDING BOX
    // =========================================================
    Item {
        id: widgetBox
        x: masterWindow.animX
        y: masterWindow.animY
        width:  masterWindow.animW
        height: masterWindow.animH
        clip: true

        Behavior on x {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }

        opacity: masterWindow.isVisible ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: masterWindow.isVisible ? Easing.OutCubic : Easing.InCubic
            }
        }

        MouseArea { anchors.fill: parent }

        Item {
            anchors.fill: parent

            StackView {
                id: widgetStack
                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: {
                    switchWidget("hidden", "");
                    event.accepted = true;
                }

                onCurrentItemChanged: {
                    if (currentItem) currentItem.forceActiveFocus();
                }

                replaceEnter: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 0.0; to: 1.0
                            duration: masterWindow.morphDurationSwitch
                            easing.type: Easing.OutQuint
                        }
                        NumberAnimation {
                            property: "scale"
                            from: 0.98; to: 1.0
                            duration: masterWindow.morphDurationSwitch
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                replaceExit: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 1.0; to: 0.0
                            duration: masterWindow.morphDurationSwitch
                            easing.type: Easing.InQuint
                        }
                        NumberAnimation {
                            property: "scale"
                            from: 1.0; to: 0.98
                            duration: masterWindow.morphDurationSwitch
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    // =========================================================
    // --- WIDGET SWITCHING
    // =========================================================
    function switchWidget(newWidget, arg) {
        delayedClear.stop();

        if (newWidget === "hidden") {
            if (currentActive !== "hidden") {
                masterWindow.morphDuration = masterWindow.exitDuration;
                masterWindow.disableMorph = false;

                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.isVisible = false;

                delayedClear.start();
            }
        } else {
            if (currentActive === "hidden" || !masterWindow.isVisible) {
                masterWindow.morphDuration = 230;
                masterWindow.disableMorph = false;

                let t = getLayout(newWidget);
                masterWindow.animX = t.rx;
                masterWindow.animY = t.ry;
                masterWindow.animW = t.w;
                masterWindow.animH = t.h;
                masterWindow.targetW = t.w;
                masterWindow.targetH = t.h;
            } else {
                masterWindow.morphDuration = masterWindow.morphDurationSwitch;
                masterWindow.disableMorph = false;
            }

            Qt.callLater(() => executeSwitch(newWidget, arg, false));
        }
    }

    function executeSwitch(newWidget, arg, immediate) {
        masterWindow.currentActive = newWidget;
        masterWindow.activeArg = arg;

        let t = getLayout(newWidget);
        masterWindow.animX = t.rx;
        masterWindow.animY = t.ry;
        masterWindow.animW = t.w;
        masterWindow.animH = t.h;
        masterWindow.targetW = t.w;
        masterWindow.targetH = t.h;

        let cached = widgetCache[newWidget];
        if (cached) {
            if (cached.notifModel   !== undefined) cached.notifModel   = masterWindow.notifModel;
            if (cached.liveNotifs   !== undefined) cached.liveNotifs   = masterWindow.liveNotifs;
            if (cached.layoutWidth  !== undefined) cached.layoutWidth  = t.w;
            if (cached.layoutHeight !== undefined) cached.layoutHeight = t.h;
            if (newWidget === "wallpaper" && cached.widgetArg !== undefined) cached.widgetArg = arg;
            if (arg !== "" && cached.activeMode !== undefined) cached.activeMode = arg;

            cached.visible = true;
            if (immediate) {
                widgetStack.replace(cached, {}, StackView.Immediate);
            } else {
                widgetStack.replace(cached, {});
            }
        } else {
            if (immediate) {
                widgetStack.replace(compUrl(t.comp), {}, StackView.Immediate);
            } else {
                widgetStack.replace(compUrl(t.comp), {});
            }
        }

        let currentItem = widgetStack.currentItem;
        if (currentItem) {
            // Assign optional cross-widget props only when the target defines them.
            if (currentItem.notifModel   !== undefined) currentItem.notifModel   = masterWindow.notifModel;
            if (currentItem.liveNotifs   !== undefined) currentItem.liveNotifs   = masterWindow.liveNotifs;
            if (currentItem.layoutWidth  !== undefined) currentItem.layoutWidth  = t.w;
            if (currentItem.layoutHeight !== undefined) currentItem.layoutHeight = t.h;
            if (newWidget === "wallpaper" && currentItem.widgetArg !== undefined) currentItem.widgetArg = arg;
            if (arg !== "" && currentItem.activeMode !== undefined) currentItem.activeMode = arg;
            // Targets opcionales (tamaño/posición propia): mismo helper que usa
            // el seguimiento reactivo (Connections sobre el widget activo).
            masterWindow.applyMasterTargets();
        }

        masterWindow.isVisible = true;
    }

    Timer {
        id: delayedClear
        interval: 200
        onTriggered: {
            masterWindow.currentActive = "hidden";
            widgetStack.clear();
            masterWindow.disableMorph = false;
        }
    }
}
