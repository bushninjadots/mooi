import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../../core"
import "../../core/WindowRegistry.js" as LayoutMath
import "BarLayout.js" as BarLayout

// ============================================================================
// Bar — the position-agnostic bar.
//
// Replaces the old top-only TopBar.qml. The same island-pill aesthetic and all
// module/data machinery are preserved, but the bar can sit on any screen edge:
//
//   position: "top" | "bottom" | "left" | "right"
//   orientation: derived from position (horizontal / vertical)
//
// The visual + layout config lives in settings.json under "bar" (see
// BarLayout.js). Old "topbar" settings are migrated on first load. Colors
// come from the Matugen-free palette system (bar/Colors.qml).
//
// Data plumbing (watchers/pollers) is centralized here; modules read state
// through the `bar` object — same contract as the old TopBar, so existing
// modules keep working untouched while we migrate them to ModulePill.
// ============================================================================

Variants {
    model: Quickshell.screens

    delegate: Component {
        PanelWindow {
            id: barWindow

            required property var modelData
            screen: modelData

            // Inline replica of the parent dir's Caching.qml so this component
            // stays self-contained inside bar/.
            QtObject {
                id: paths
                readonly property string home: Quickshell.env("HOME")
                readonly property string xdgRuntimeDir: Quickshell.env("XDG_RUNTIME_DIR")
                readonly property string cacheDir: home + "/.cache/quickshell"
                readonly property string stateDir: home + "/.local/state/quickshell"
                readonly property string runDir: (xdgRuntimeDir !== "" ? xdgRuntimeDir : "/tmp") + "/quickshell"
                readonly property string logDir: runDir + "/logs"
                function getCacheDir(name) {
                    let envPath = Quickshell.env("QS_CACHE_" + name.toUpperCase());
                    let p = envPath ? envPath : (cacheDir + "/" + name);
                    Quickshell.execDetached(["mkdir", "-p", p]);
                    return p;
                }
                function getStateDir(name) {
                    let envPath = Quickshell.env("QS_STATE_" + name.toUpperCase());
                    let p = envPath ? envPath : (stateDir + "/" + name);
                    Quickshell.execDetached(["mkdir", "-p", p]);
                    return p;
                }
                function getRunDir(name) {
                    let envPath = Quickshell.env("QS_RUN_" + name.toUpperCase());
                    let p = envPath ? envPath : (runDir + "/" + name);
                    Quickshell.execDetached(["mkdir", "-p", p]);
                    return p;
                }
                function getLogDir(name) {
                    let envPath = Quickshell.env("QS_LOG_" + name.toUpperCase());
                    let p = envPath ? envPath : (logDir + "/" + name);
                    Quickshell.execDetached(["mkdir", "-p", p]);
                    return p;
                }
            }

            // ================================================================
            // SCALING (inlined — avoids importing Scaler.qml from the parent dir)
            // ================================================================
            property real uiScale: 1.0
            readonly property real baseScale: LayoutMath.getScale(
                barWindow.screen ? barWindow.screen.width : 1920,
                barWindow.screen ? barWindow.screen.height : 1080,
                barWindow.uiScale)
            function s(val) { return LayoutMath.s(val, baseScale); }

            // ================================================================
            // THEME COLORS (Matugen-free)
            // ================================================================
            Colors {
                id: barColors
            }
            // Exposed as a property so modules/zones can use `colors.<role>`
            // exactly like they did with the legacy MatugenColors component.
            readonly property var colors: barColors

            // ================================================================
            // DOCK CONFIG (settings.json "bar" key)
            //
            // CUSTOMIZATION HOOK: every visual/layout value the mega menu edits
            // lands here. `syncBarConfig()` copies the parsed barConfig into
            // plain properties in ONE synchronous pass so orientation/geometry/
            // zones always stay consistent (readonly binding chains evaluate
            // lazily and caused stale orientation bugs).
            // ================================================================
            property var barConfig: BarLayout.defaultBar()
            property var zones: barConfig.zones
            // Becomes true only after settings.json has been read AND the bar
            // config synced, so uiScale/baseScale are final before any module
            // renders (bar.s() is a function, so QML can't reactively rescale).
            property bool configReady: false

            // ================================================================
            // SHADOWS (settings.json "shadows", same config as popups)
            // The bar draws its own shadows (per island / strip): Hyprland does
            // not decorate layer surfaces. The surface is padded so they are
            // not clipped, and the padding is masked out for input.
            // ================================================================
            property var shadowsCfg: ({})
            readonly property bool shadowOn: shadowsCfg.enabled !== false
            readonly property real shadowBlur: s(shadowsCfg.blur !== undefined ? shadowsCfg.blur : 26)
            readonly property real shadowSpread: s(shadowsCfg.spread !== undefined ? shadowsCfg.spread : 0)
            readonly property real shadowOffX: s(shadowsCfg.offsetX !== undefined ? shadowsCfg.offsetX : 0)
            readonly property real shadowOffY: s(shadowsCfg.offsetY !== undefined ? shadowsCfg.offsetY : 6)
            readonly property real shadowOpacity: shadowsCfg.opacity !== undefined ? shadowsCfg.opacity : 0.5
            readonly property real shadowPad: shadowOn
                ? shadowBlur + shadowSpread + Math.max(shadowOffX, shadowOffY, 0)
                : 0
            readonly property bool barShadow: shadowOn && configReady && shadowPad > 0
            readonly property real padTop: !barShadow ? 0
                : (orientation === "horizontal" ? (position === "top" ? Math.min(shadowPad, s(edgeGap)) : shadowPad) : 0)
            readonly property real padBottom: !barShadow ? 0
                : (orientation === "horizontal" ? (position === "bottom" ? Math.min(shadowPad, s(edgeGap)) : shadowPad) : 0)
            readonly property real padLeft: !barShadow ? 0
                : (orientation === "vertical" ? (position === "left" ? Math.min(shadowPad, s(edgeGap)) : shadowPad) : 0)
            readonly property real padRight: !barShadow ? 0
                : (orientation === "vertical" ? (position === "right" ? Math.min(shadowPad, s(edgeGap)) : shadowPad) : 0)
            property string position: "top"
            property string orientation: "horizontal"
            property string paletteName: "x"
            property real thickness: 48
            property real edgeGap: 8
            property real roundness: 1.0
            property bool pillBg: true
            property bool pillSolid: false
            // "barBg" — solid/translucent background strip behind the whole bar;
            // islands then float INSIDE it instead of being standalone pills.
            property bool barBg: false
            property real borderWidth: 0
            property string borderColor: "surface1"
            // Configurable font for all module text/icons (bar.font).
            property string fontFamily: "Hack Nerd Font"
            // Alpha used by the optional full-bar background strip (bar.barOpacity).
            property real barOpacity: 0.85
            // Master switch for live island drag & drop (bar.dragModules).
            property bool dragModulesEnabled: true
            // Master switch for the whole bar (bar.enabled): a disabled bar
            // unmaps its windows (no UI, no reserved edge) and comes back
            // exactly as configured when re-enabled (see syncBarConfig).
            property bool barEnabled: true
            // Clock format for the clock island (bar.timeFormat).
            property string timeFormat: "HH:mm:ss"
            property string dateFormat: "dddd, MMMM dd" 
            // Tracks the last applied orientation: an axis change (horizontal ↔
            // vertical) remounts the zones in-process (Phase D3) so every module
            // re-reads bar.orientation at creation — no full shell reload.
            property string _lastOrientation: ""

            // Content choke point for the settings reader: text of the last
            // successfully parsed settings.json. Keeps the directory watcher's
            // wakeups on unrelated config files completely silent.
            property string lastSettingsJson: ""

            // ================================================================
            // LIVE ISLAND DRAG & DROP STATE (Phase D2)
            // ================================================================
            property bool dragBusy: false
            // Set right before a dragged island is released so the propagated
            // release cannot fire the pill's own click (see Zone slotDragArea).
            property bool consumeNextModuleClick: false
            property string dragId: ""
            property var dragStartBar: ({})
            property var dragWorkingBar: ({})
            property bool pendingBarConfigRefresh: false
            // Set when an axis flip arrived while a drag owned the config; the
            // remount then runs at the end of the gesture instead (see
            // endDragAt/cancelDrag).
            property bool pendingAxisRemount: false

            // Begin a drag session for module `id` (called by Zone slots).
            function startDrag(id) {
                if (barWindow.dragBusy || !barWindow.dragModulesEnabled) return;
                if (!barWindow.barConfig || !BarLayout.isList(barWindow.barConfig.zones)) return;
                try {
                    barWindow.dragStartBar = BarLayout.cloneBar(barWindow.barConfig);
                    barWindow.dragWorkingBar = BarLayout.cloneBar(barWindow.barConfig);
                } catch (e) { return; }
                barWindow.dragId = id;
                barWindow.dragBusy = true;
                barWindow.pendingBarConfigRefresh = false;
            }

            // Live reorder under the pointer (throttled). `px/py` are in this
            // window's coordinates.
            function updateDragAt(px, py) {
                if (!barWindow.dragBusy) return;
                let hit = null;
                let zones = barContent.children;
                for (let i = 0; i < zones.length; i++) {
                    let z = zones[i];
                    if (!z || !z.isBarZone) continue;
                    if (z.containsBarPoint(px, py)) {
                        hit = z.barPointToInsert(px, py);
                        if (hit) break;
                    }
                }
                if (!hit) return; // pointer not over any zone: keep last spot
                let next = BarLayout.moduleMoveTo(barWindow.dragWorkingBar, barWindow.dragId, hit.zoneId, hit.index);
                let nextStr = JSON.stringify(next);
                if (nextStr !== JSON.stringify(barWindow.barConfig)) {
                    barWindow.dragWorkingBar = next;
                    barWindow.barConfig = next;
                }
            }

            // Commit (drop inside a zone) or cancel (drop outside the bar).
            function endDragAt(px, py) {
                if (!barWindow.dragBusy) return;
                let inside = false;
                let zones = barContent.children;
                for (let i = 0; i < zones.length; i++) {
                    let z = zones[i];
                    if (z && z.isBarZone && z.containsBarPoint(px, py)) { inside = true; break; }
                }
                let finalBar = barWindow.dragWorkingBar;
                barWindow.dragBusy = false;
                barWindow.dragId = "";
                if (inside) {
                    // Write once, atomically; the in-memory config is already the
                    // result, so the watcher sees no diff and nothing flickers.
                    Config.setSetting("bar", finalBar);
                } else {
                    barWindow.barConfig = barWindow.dragStartBar;
                }
                if (barWindow.pendingBarConfigRefresh) {
                    barWindow.pendingBarConfigRefresh = false;
                    settingsReader.running = false;
                    settingsReader.running = true;
                }
                // An axis flip that arrived mid-drag remounts now that the
                // gesture no longer owns the config.
                barWindow.flushPendingAxisRemount();
            }

            // Abort the session (drag cancelled by the slot MouseArea).
            function cancelDrag() {
                if (!barWindow.dragBusy) return;
                let restore = barWindow.dragStartBar;
                barWindow.dragBusy = false;
                barWindow.dragId = "";
                barWindow.barConfig = restore;
                if (barWindow.pendingBarConfigRefresh) {
                    barWindow.pendingBarConfigRefresh = false;
                    settingsReader.running = false;
                    settingsReader.running = true;
                }
                barWindow.flushPendingAxisRemount();
            }

            // Rebuild every zone delegate in THIS process (Phase D3). Crossing
            // the axis used to IPC-reload the whole shell because modules baked
            // stale orientation state at creation. Emptying the zones model
            // destroys each Zone + its module Loaders, and Qt.callLater refills
            // it from the already-synced barConfig in the next event turn, so
            // fresh modules read the NEW orientation/geometry from the start.
            // syncBarConfig() (geometry, margins, anchors) already ran before
            // this is called, so the window relayouts and the zones mount
            // against the final values. Zone's entrance cascade replays because
            // the new delegates start with ready=false.
            function remountZones() {
                if (!barWindow.configReady) return;
                barWindow.zones = [];
                Qt.callLater(() => {
                    let z = (barWindow.barConfig && barWindow.barConfig.zones)
                          ? barWindow.barConfig.zones : [];
                    barWindow.zones = z;
                });
            }

            // Run a deferred remount after a drag gesture ends (axis flips are
            // impossible mid-drag, but the guard keeps the invariant anyway).
            function flushPendingAxisRemount() {
                if (!barWindow.pendingAxisRemount) return;
                barWindow.pendingAxisRemount = false;
                barWindow.remountZones();
            }

            onBarConfigChanged: {
                // syncBarConfig() applies the persisted bar values.
                syncBarConfig();
                // Only remount on an ACTUAL axis change (vertical ↔ horizontal),
                // and never during boot (before configReady). Same-axis position
                // moves and pure visual changes never rebuild anything.
                let axisFlip = barWindow.configReady && barWindow._lastOrientation !== "" && barWindow.orientation !== barWindow._lastOrientation;
                if (axisFlip) {
                    if (barWindow.dragBusy) barWindow.pendingAxisRemount = true;
                    else barWindow.remountZones();
                }
                barWindow._lastOrientation = barWindow.orientation;
            }
            Component.onCompleted: {
                syncBarConfig();
                barWindow._lastOrientation = barWindow.orientation;
                // Keep Hyprland window-border colors in sync with the palette /
                // border overrides at all times (the bar bar is always alive,
                // so this fires whether or not the BarEditor is open).
                barColors.paletteApplied.connect(function() { barColors.syncWindowBorders(); });
                barColors.settingsUpdated.connect(function() { barColors.syncWindowBorders(); });
            }

            function syncBarConfig() {
                if (!barConfig) return;
                barWindow.position = barConfig.position || "top";
                barWindow.orientation = (barWindow.position === "top" || barWindow.position === "bottom") ? "horizontal" : "vertical";
                barWindow.paletteName = barConfig.palette || "x";
                barWindow.thickness = barConfig.thickness;
                barWindow.edgeGap = barConfig.edgeGap;
                barWindow.roundness = barConfig.roundness;
                barWindow.pillBg = barConfig.pillBg;
                barWindow.pillSolid = barConfig.pillSolid;
                barWindow.barBg = barConfig.barBg;
                barWindow.barOpacity = (typeof barConfig.barOpacity === "number") ? barConfig.barOpacity : 0.85;
                barWindow.dragModulesEnabled = barConfig.dragModules !== false;
                barWindow.barEnabled = barConfig.enabled !== false;
                barWindow.workspacesMarker = (typeof barConfig.workspacesMarker === "string") ? barConfig.workspacesMarker : "number";
                barWindow.workspacesMarkerText = (typeof barConfig.workspacesMarkerText === "string") ? barConfig.workspacesMarkerText : "";
                barWindow.borderWidth = barConfig.borderWidth;
                barWindow.borderColor = barConfig.borderColor;
                barWindow.fontFamily = barConfig.font || "Hack Nerd Font";
                barWindow.timeFormat = (typeof barConfig.timeFormat === "string" && barConfig.timeFormat !== "") ? barConfig.timeFormat : "HH:mm:ss";
                barWindow.dateFormat = (typeof barConfig.dateFormat === "string" && barConfig.dateFormat !== "") ? barConfig.dateFormat : "dddd, MMMM dd";
                barWindow.zones = barConfig.zones;
                applyPosition();
            }

            // ================================================================
            // GEOMETRY
            // ================================================================
            property int barHeight: s(thickness)
            // Thickness is the bar cross-size in both orientations: for vertical
            // bars it is the width. Very small values make the islands compact;
            // below ~s(40) the HH:mm clock / long labels may clip by design.
            property int barWidth: s(thickness)
            property int pillHeight: orientation === "horizontal" ? barHeight - s(12) : barWidth - s(8)
            property int pillWidth: orientation === "horizontal" ? barHeight - s(12) : barWidth - s(8)
            function pillRadius(h) { return Math.round(h * 0.5 * roundness); }

            // Personalization API for modules (see the module personalization
            // API in BarLayout.js): bar-wide icon color + per-module config.
            readonly property string iconColor: (barConfig.iconColor !== undefined && barConfig.iconColor !== null) ? barConfig.iconColor : ""
            function moduleConfig(id) { return BarLayout.moduleConfig(barConfig, id); }

            implicitHeight: orientation === "horizontal"
                ? barHeight + barWindow.padTop + barWindow.padBottom
                : (barWindow.screen ? barWindow.screen.height : 1080)
            implicitWidth: orientation === "horizontal"
                ? (barWindow.screen ? barWindow.screen.width : 1920)
                : barWidth + barWindow.padLeft + barWindow.padRight

            // --- margins -------------------------------------------------------
            // The bar margins offset the whole surface from the anchored edges:
            // the screen-edge side carries edgeGap, the other sides s(4).
            margins {
                top: orientation === "vertical" ? s(4)
                    : (position === "top" ? s(edgeGap) - barWindow.padTop : s(4))
                bottom: orientation === "vertical" ? s(4)
                    : (position === "bottom" ? s(edgeGap) - barWindow.padBottom : s(4))
                left: orientation === "horizontal" ? s(4)
                    : (position === "left" ? s(edgeGap) - barWindow.padLeft : s(4))
                right: orientation === "horizontal" ? s(4)
                    : (position === "right" ? s(edgeGap) - barWindow.padRight : s(4))
            }
            // A hidden autohide bar reserves no edge space at all; every other
            // state reserves the same band as the bar engine.
            // A disabled bar (bar.enabled false) reserves no edge space: the
            // window is unmapped and exclusiveZone is 0 (belt & braces for the
            // frames around a live toggle).
            exclusiveZone: !barWindow.barEnabled ? 0
                : (orientation === "horizontal" ? barHeight : barWidth)
            color: "transparent"
            // bar.enabled master switch: off unmaps the window entirely (no
            // reserve, no input, no UI); on maps it back with the same config.
            visible: barWindow.barEnabled
            
            // --- clickthrough mask ------------------------------------------------
            // With shadows on, the surface is padded so the shadow fits; the
            // padding must not swallow input, so the mask tracks the visual bar
            // band (barContent) instead of the whole padded surface.
            Region {
                id: barBandMask
                Region {
                    item: barContent
                }
            }
            mask: barWindow.barShadow ? barBandMask : null

            function applyPosition() {
                barWindow.anchors.top = undefined;
                barWindow.anchors.bottom = undefined;
                barWindow.anchors.left = undefined;
                barWindow.anchors.right = undefined;
                if (position === "top") { barWindow.anchors.top = true; barWindow.anchors.left = true; barWindow.anchors.right = true; }
                else if (position === "bottom") { barWindow.anchors.bottom = true; barWindow.anchors.left = true; barWindow.anchors.right = true; }
                else if (position === "left") { barWindow.anchors.left = true; barWindow.anchors.top = true; barWindow.anchors.bottom = true; }
                else { barWindow.anchors.right = true; barWindow.anchors.top = true; barWindow.anchors.bottom = true; }
            }
            onPositionChanged: applyPosition()

            // ================================================================
            // IPC (same target as before so qs_manager / Config keep working)
            // ================================================================
            IpcHandler {
                target: "topbar"
                function forceReload() { Quickshell.reload(true) }
                function queueReload() {
                    if (!barWindow.isSettingsOpen) Quickshell.reload(true)
                    else barWindow.pendingReload = true
                }
                function reloadColors() { barColors.forceRefresh() }
                function toggleUpdate() { barWindow.forceUpdateShow = !barWindow.forceUpdateShow }
            }

            // ================================================================
            // WIDGET / RECORDING / UPDATE POLLERS
            // ================================================================
            property bool pendingReload: false
            property string activeWidget: ""
            // El panel Settings unificado (bar-editor, SUPER+SHIFT+S/D) sustituye
            // al antiguo popup "settings"; ambos ids cuentan como panel abierto.
            // Solo se usa para diferir reloads: el panel es CENTRADO, así que la
            // barra NO se desplaza.
            property bool isSettingsOpen: activeWidget === "settings" || activeWidget === "bar-editor"
            onIsSettingsOpenChanged: {
                if (!barWindow.isSettingsOpen && barWindow.pendingReload) {
                    barWindow.pendingReload = false;
                    Quickshell.reload(true);
                }
            }

            Process {
                id: widgetPoller
                command: ["bash", "-c", "cat " + paths.runDir + "/current_widget 2>/dev/null || echo ''"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (barWindow.activeWidget !== txt) barWindow.activeWidget = txt;
                    }
                }
            }
            Process {
                id: widgetWatcher
                command: ["bash", "-c", "while [ ! -f " + paths.runDir + "/current_widget ]; do sleep 1; done; inotifywait -qq -e modify,close_write " + paths.runDir + "/current_widget"]
                running: true
                onExited: {
                    widgetPoller.running = false;
                    widgetPoller.running = true;
                    running = false;
                    running = true;
                }
            }

            Process {
                id: updatePoller
                command: ["bash", "-c", "if [ -f " + paths.getCacheDir("updater") + "/update_pending ]; then echo '1'; else echo '0'; fi"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.updateAvailable = (this.text.trim() === "1");
                    }
                }
            }
            Process {
                id: settingsReader
                command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text ? this.text.trim() : "";
                        if (txt === "" || txt === "{}") return;
                        // Choke point (Theme.qml pattern): the directory watcher
                        // below wakes on ANY file event under ~/.config/hypr —
                        // identical settings.json content must not re-apply the
                        // config, reset configReady or replay animations.
                        if (txt === barWindow.lastSettingsJson) return;
                        try {
                            // A live drag owns barConfig; defer external reads
                            // until the gesture finishes (commit/cancel).
                            if (barWindow.dragBusy) {
                                barWindow.pendingBarConfigRefresh = true;
                                return;
                            }
                            let parsed = JSON.parse(txt);
                            barWindow.lastSettingsJson = txt;
                            let next = BarLayout.getBar(parsed);
                            if (JSON.stringify(next) !== JSON.stringify(barWindow.barConfig)) {
                                barWindow.barConfig = next;
                            }
                            if (parsed.uiScale !== undefined && barWindow.uiScale !== parsed.uiScale) {
                                barWindow.uiScale = parsed.uiScale;
                            }
                            barWindow.shadowsCfg = (parsed.shadows && typeof parsed.shadows === "object")
                                ? parsed.shadows : {};
                            if (parsed.workspaceCount !== undefined && barWindow.workspaceCount !== parsed.workspaceCount) {
                                barWindow.workspaceCount = parsed.workspaceCount;
                                wsDaemon.running = false;
                                wsDaemon.running = true;
                            }
                            // uiScale + barConfig are now final: safe to build modules.
                            barWindow.configReady = true;
                        } catch (e) {}
                    }
                }
            }
            // FileView watch (no shell processes, reload-safe): settings.json
            // is written atomically (tmp + mv), and FileView follows the file
            // across renames — unlike an inotify watch on the inode. On any
            // change the cat-based reader re-runs; identical content is choked
            // in the reader (lastSettingsJson) so unrelated edits stay silent.
            FileView {
                id: settingsWatcher
                path: Quickshell.env("HOME") + "/.config/hypr/settings.json"
                watchChanges: true
                onFileChanged: {
                    if (barWindow.dragBusy) {
                        barWindow.pendingBarConfigRefresh = true;
                        return;
                    }
                    settingsReader.running = false;
                    settingsReader.running = true;
                }
            }

            // ================================================================
            // SYSTEM STATE
            // ================================================================
            property bool updateAvailable: false
            property bool forceUpdateShow: false
            property bool isUpdateVisible: updateAvailable || forceUpdateShow
            property int workspaceCount: 8
            // Empty-workspace marker for the Workspaces module
            // (number|dot|letter|custom) + optional custom character.
            property string workspacesMarker: "number"
            property string workspacesMarkerText: "" 

            property bool isDesktop: false
            property string ethStatus: "Ethernet"

            Process {
                id: chassisDetector
                running: true
                command: ["bash", "-c", "if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then echo 'laptop'; else echo 'desktop'; fi"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.isDesktop = (this.text.trim() === "desktop");
                    }
                }
            }

            property bool isStartupReady: false
            Timer { interval: 10; running: true; onTriggered: barWindow.isStartupReady = true }
            property bool startupCascadeFinished: false
            Timer { interval: 1000; running: true; onTriggered: barWindow.startupCascadeFinished = true }
            property bool fastPollerLoaded: false
            property bool isDataReady: false
            Timer { interval: 600; running: true; onTriggered: barWindow.isDataReady = true }

            property string timeStr: ""
            property string fullDateStr: ""
            property int typeInIndex: 0
            property string dateStr: fullDateStr.substring(0, typeInIndex)


            // --- focused window (FocusModule) -------------------------------------
            property string focusTitle: ""
            property string focusClass: ""
            property string focusIcon: "󰋼"
            readonly property bool hasFocus: barWindow.focusTitle !== ""

            // Map common WM_CLASS values to Nerd Font glyphs so the focus island
            // shows a recognizable app icon without spawning any extra process.
            function focusIconForClass(cls) {
                const c = String(cls || "").toLowerCase();
                const icons = {
                    "firefox": "󰈹", "librewolf": "󰈹", "zen": "󰈹",
                    "google-chrome": "󰈹", "chromium": "󰈹", "brave": "󰈹",
                    "kitty": "󰄛", "alacritty": "󰄛", "ghostty": "󰄛", "konsole": "󰄛", "wezterm": "󰄛", "xterm": "󰄛",
                    "code": "󰨞", "codium": "󰨞", "code-oss": "󰨞",
                    "spotify": "󰓇", "discord": "󰙯", "vesktop": "󰙯",
                    "nautilus": "󰉋", "dolphin": "󰉋", "thunar": "󰉋", "nemo": "󰉋",
                    "obsidian": "󰠮", "zathura": "󰈇", "org.gnome.nautilus": "󰉋"
                };
                return icons[c] || "󰋼";
            }

            property string wifiStatus: "Off"
            property string wifiIcon: "󰤮"
            property string wifiSsid: ""
            property string btStatus: "Off"
            property string btIcon: "󰂲"
            property string btDevice: ""
            property string volPercent: "0%"
            property string volIcon: "󰕾"
            property bool isMuted: false
            property string batPercent: "100%"
            property string batIcon: "󰁹"
            property string batStatus: "Unknown"
            property string kbLayout: "us"

            ListModel {
                id: workspacesModel
                property int activeIndex: 0
            }
            readonly property var wsModel: workspacesModel
            function refreshMusic() { musicForceRefresh.running = true; }

            property var musicData: { "status": "Stopped", "title": "", "artUrl": "", "timeStr": "" }
            property string displayTitle: ""
            property string displayTime: ""
            property string displayArtUrl: ""
            onMusicDataChanged: {
                if (musicData && musicData.status !== "Stopped" && musicData.title !== "") {
                    displayTitle = musicData.title;
                    displayTime = musicData.timeStr;
                    displayArtUrl = musicData.artUrl;
                }
            }

            property bool isMediaActive: barWindow.musicData.status !== "Stopped" && barWindow.musicData.title !== ""
            property bool isWifiOn: barWindow.wifiStatus.toLowerCase() === "enabled" || barWindow.wifiStatus.toLowerCase() === "on"
            property bool isBtOn: barWindow.btStatus.toLowerCase() === "enabled" || barWindow.btStatus.toLowerCase() === "on"
            property bool showEthernet: barWindow.ethStatus === "Connected" || (barWindow.isDesktop && !barWindow.isWifiOn)
            property bool isSoundActive: !barWindow.isMuted && parseInt(barWindow.volPercent) > 0
            property int batCap: parseInt(barWindow.batPercent) || 0
            property bool isCharging: barWindow.batStatus === "Charging" || barWindow.batStatus === "Full"
            property color batDynamicColor: {
                if (isCharging) return colors.green;
                if (batCap <= 20) return colors.red;
                return colors.text;
            }

            // ================================================================
            // WORKSPACES
            // ================================================================
            Process {
                id: wsDaemon
                command: Compositor.workspacesCommand
                running: true
            }
            Process {
                id: wsReader
                running: true
                command: ["cat", paths.getRunDir("workspaces") + "/workspaces.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let newData = JSON.parse(txt);
                                while (workspacesModel.count < newData.length) {
                                    workspacesModel.append({ "wsId": "", "wsState": "", "wsClasses": "" });
                                }
                                while (workspacesModel.count > newData.length) {
                                    workspacesModel.remove(workspacesModel.count - 1);
                                }
                                let newActive = -1;
                                for (let i = 0; i < newData.length; i++) {
                                    if (newData[i].state === "active") newActive = i;
                                    if (workspacesModel.get(i).wsState !== newData[i].state) {
                                        workspacesModel.setProperty(i, "wsState", newData[i].state);
                                    }
                                    if (workspacesModel.get(i).wsId !== newData[i].id.toString()) {
                                        workspacesModel.setProperty(i, "wsId", newData[i].id.toString());
                                    }
                                    if (newData[i].classes != undefined && workspacesModel.get(i).wsClasses !== newData[i].classes) {
                                        workspacesModel.setProperty(i, "wsClasses", newData[i].classes);
                                    }
                                }
                                if (newActive !== -1 && workspacesModel.activeIndex !== newActive) {
                                    workspacesModel.activeIndex = newActive;
                                }
                            } catch(e) {}
                        }
                    }
                }
            }
            // FileView watch on the workspaces JSON (process-free, follows
            // atomic rewrites). Reload-safe: no shell children to orphan.
            FileView {
                id: wsWatcher
                path: paths.getRunDir("workspaces") + "/workspaces.json"
                watchChanges: true
                onFileChanged: {
                    wsReader.running = false;
                    wsReader.running = true;
                }
            }
            Process {
                id: musicForceRefresh
                running: true
                command: ["bash", "-c", "bash ~/.config/hypr/scripts/quickshell/ui/bar/popups/music/music_info.sh | tee " + paths.getRunDir("music") + "/music_info.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try { barWindow.musicData = JSON.parse(txt); } catch(e) {}
                        }
                    }
                }
            }
            Timer {
                interval: 1000
                running: barWindow.musicData !== null && barWindow.musicData.status === "Playing"
                repeat: true
                onTriggered: {
                    if (!barWindow.musicData || barWindow.musicData.status !== "Playing") return;
                    if (!barWindow.musicData.timeStr || barWindow.musicData.timeStr === "") return;
                    let parts = barWindow.musicData.timeStr.split(" / ");
                    if (parts.length !== 2) return;
                    let posParts = parts[0].split(":").map(Number);
                    let lenParts = parts[1].split(":").map(Number);
                    let posSecs = (posParts.length === 3)
                        ? (posParts[0] * 3600 + posParts[1] * 60 + posParts[2])
                        : (posParts[0] * 60 + posParts[1]);
                    let lenSecs = (lenParts.length === 3)
                        ? (lenParts[0] * 3600 + lenParts[1] * 60 + lenParts[2])
                        : (lenParts[0] * 60 + lenParts[1]);
                    if (isNaN(posSecs) || isNaN(lenSecs)) return;
                    posSecs++;
                    if (posSecs > lenSecs) posSecs = lenSecs;
                    let newPosStr = "";
                    if (posParts.length === 3) {
                        let h = Math.floor(posSecs / 3600);
                        let m = Math.floor((posSecs % 3600) / 60);
                        let s = posSecs % 60;
                        newPosStr = h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    } else {
                        let m = Math.floor(posSecs / 60);
                        let s = posSecs % 60;
                        newPosStr = (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    }
                    let newData = Object.assign({}, barWindow.musicData);
                    newData.timeStr = newPosStr + " / " + parts[1];
                    newData.positionStr = newPosStr;
                    if (lenSecs > 0) newData.percent = (posSecs / lenSecs) * 100;
                    barWindow.musicData = newData;
                }
            }
            Process {
                id: kbPoller; running: true
                command: Compositor.keyboardCommand
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "" && barWindow.kbLayout !== txt) barWindow.kbLayout = txt;
                        barWindow.fastPollerLoaded = true;
                    }
                }
            }


            Process {
                id: audioPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/core/scripts/watchers/audio_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                let newVol = data.volume.toString() + "%";
                                if (barWindow.volPercent !== newVol) barWindow.volPercent = newVol;
                                if (barWindow.volIcon !== data.icon) barWindow.volIcon = data.icon;
                                let newMuted = (data.is_muted === "true");
                                if (barWindow.isMuted !== newMuted) barWindow.isMuted = newMuted;
                            } catch(e) {}
                        }
                    }
                }
            }


            Process {
                id: networkPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/core/scripts/watchers/network_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                if (barWindow.wifiStatus !== data.status) barWindow.wifiStatus = data.status;
                                if (barWindow.wifiIcon !== data.icon) barWindow.wifiIcon = data.icon;
                                if (barWindow.wifiSsid !== data.ssid) barWindow.wifiSsid = data.ssid;
                                if (barWindow.ethStatus !== data.eth_status) barWindow.ethStatus = data.eth_status;
                            } catch(e) {}
                        }
                    }
                }
            }


            Process {
                id: btPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/core/scripts/watchers/bt_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                if (barWindow.btStatus !== data.status) barWindow.btStatus = data.status;
                                if (barWindow.btIcon !== data.icon) barWindow.btIcon = data.icon;
                                if (barWindow.btDevice !== data.connected) barWindow.btDevice = data.connected;
                            } catch(e) {}
                        }
                    }
                }
            }


            Process {
                id: batteryPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/core/scripts/watchers/battery_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                let newBat = data.percent.toString() + "%";
                                if (barWindow.batPercent !== newBat) barWindow.batPercent = newBat;
                                if (barWindow.batIcon !== data.icon) barWindow.batIcon = data.icon;
                                if (barWindow.batStatus !== data.status) barWindow.batStatus = data.status;
                            } catch(e) {}
                        }
                    }
                }
            }



            // ================================================================
            // POLLING TIMERS (process-free refresh)
            // ================================================================
            // The old fetch+wait/process watchers leaked long-running children
            // across in-process reloads (orphans exhausted inotify/process
            // limits). Polling Timers keep the same data fresh with zero
            // long-running processes.
            Timer { id: kbPollTimer; interval: 2000; running: true; repeat: true; onTriggered: { kbPoller.running = false; kbPoller.running = true; } }
            Timer { id: audioPollTimer; interval: 2000; running: true; repeat: true; onTriggered: { audioPoller.running = false; audioPoller.running = true; } }
            Timer { id: netPollTimer; interval: 3000; running: true; repeat: true; onTriggered: { networkPoller.running = false; networkPoller.running = true; } }
            Timer { id: btPollTimer; interval: 4000; running: true; repeat: true; onTriggered: { btPoller.running = false; btPoller.running = true; } }
            Timer { id: batPollTimer; interval: 3000; running: true; repeat: true; onTriggered: { batteryPoller.running = false; batteryPoller.running = true; } }
            Timer { id: updatePollTimer; interval: 4000; running: true; repeat: true; onTriggered: { updatePoller.running = false; updatePoller.running = true; } }
            Timer { id: musicPollTimer; interval: 3000; running: true; repeat: true; onTriggered: { musicForceRefresh.running = false; musicForceRefresh.running = true; } }
            Timer { id: wsPollTimer; interval: 1500; running: true; repeat: true; onTriggered: { wsReader.running = false; wsReader.running = true; } }

            // ================================================================
            // FOCUSED WINDOW (FocusModule)
            // ================================================================
            Process {
                id: focusPoller
                command: Compositor.focusCommand
                stdout: StdioCollector {
                    onStreamFinished: {
                        let line = this.text.trim();
                        if (line === "") {
                            if (barWindow.focusTitle !== "") barWindow.focusTitle = "";
                            if (barWindow.focusClass !== "") barWindow.focusClass = "";
                            if (barWindow.focusIcon !== "󰋼") barWindow.focusIcon = "󰋼";
                            return;
                        }
                        let nl = line.indexOf("\n");
                        let cls = nl !== -1 ? line.substring(0, nl) : line;
                        let title = nl !== -1 ? line.substring(nl + 1).trim() : "";
                        if (title === "") title = cls;
                        if (barWindow.focusClass !== cls) {
                            barWindow.focusClass = cls;
                            barWindow.focusIcon = barWindow.focusIconForClass(cls);
                        }
                        if (barWindow.focusTitle !== title) barWindow.focusTitle = title;
                    }
                }
            }
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: { focusPoller.running = false; focusPoller.running = true; }
            }

            // ================================================================
            // CLOCK + TYPEWRITER DATE
            // ================================================================
            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    let d = new Date();
                    let fmt = barWindow.timeFormat;
                    barWindow.timeStr = Qt.formatDateTime(d, fmt);
                    barWindow.fullDateStr = Qt.formatDateTime(d, barWindow.dateFormat);
                    if (barWindow.typeInIndex >= barWindow.fullDateStr.length) {
                        barWindow.typeInIndex = barWindow.fullDateStr.length;
                    }
                }
            }
            Timer {
                id: typewriterTimer
                interval: 40
                running: barWindow.isStartupReady && barWindow.typeInIndex < barWindow.fullDateStr.length
                repeat: true
                onTriggered: barWindow.typeInIndex += 1
            }

            // ================================================================
            // ZONES
            // ================================================================

            // Bar background strip (bar.barBg): a solid/translucent band behind
            // the whole bar with only the inner corners rounded, so the islands
            // float INSIDE it like a taskbar. Pill backgrounds then go transparent
            // (see ModulePill) and the accent islands stay as colored pills.
            // Strip shadow (barBg style): same "shadows" config as popups.
            RectangularShadow {
                visible: barWindow.barShadow && barWindow.barBg
                anchors.fill: barBackground
                radius: barBackground.radius
                topLeftRadius: barBackground.topLeftRadius
                topRightRadius: barBackground.topRightRadius
                bottomLeftRadius: barBackground.bottomLeftRadius
                bottomRightRadius: barBackground.bottomRightRadius
                blur: barWindow.shadowBlur
                spread: barWindow.shadowSpread
                offset: Qt.vector2d(barWindow.shadowOffX, barWindow.shadowOffY)
                color: Qt.rgba(0, 0, 0, barWindow.shadowOpacity)
            }
            Rectangle {
                id: barBackground
                anchors.fill: parent
                anchors.topMargin: barWindow.padTop
                anchors.bottomMargin: barWindow.padBottom
                anchors.leftMargin: barWindow.padLeft
                anchors.rightMargin: barWindow.padRight
                visible: barWindow.barBg && barWindow.barEnabled
                radius: barWindow.pillRadius(barWindow.pillHeight)
                topLeftRadius: orientation === "vertical" ? 0 : (position === "top" ? 0 : radius)
                topRightRadius: orientation === "vertical" ? 0 : (position === "top" ? 0 : radius)
                bottomLeftRadius: orientation === "vertical" ? 0 : (position === "bottom" ? 0 : radius)
                bottomRightRadius: orientation === "vertical" ? 0 : (position === "bottom" ? 0 : radius)
                // vertical: flat on the screen-edge side
                color: Qt.rgba(barColors.base.r, barColors.base.g, barColors.base.b, barWindow.pillSolid ? barColors.base.a : barWindow.barOpacity * barColors.base.a)
                border.width: barWindow.borderWidth
                border.color: barColors[borderColor] || barColors.surface1
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            Item {
                id: barContent
                anchors.fill: parent
                anchors.topMargin: barWindow.padTop
                anchors.bottomMargin: barWindow.padBottom
                anchors.leftMargin: barWindow.padLeft
                anchors.rightMargin: barWindow.padRight

                // Zones only build once uiScale/baseScale are final (bar.s() is a
                // function, so modules can't reactively rescale after creation).
                visible: barWindow.configReady
                Repeater {
                    model: barWindow.zones
                    delegate: Zone {
                        required property var modelData
                        required property int index
                        bar: barWindow
                        colors: barWindow.colors
                        zoneData: modelData
                        zoneIndex: index
                    }
                }

            }
        }
    }
}
