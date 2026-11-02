import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.ui.bar.edit
import qs.ui.bar
import qs.core
import "../ui/Binds.js" as Binds

// ═══════════════════════════════════════════════════════════════════════════
// KeybindsPage — the Keybinds plugin's own settings page (equisdots standard).
//
// The intermediate layer between the core and the plugins for keyboard
// shortcuts: consumes `plugins-report.json` (written by the Hyprland loader
// on every config load) and writes per-bind overrides into each plugin's OWN
// settings file (<scope>.binds.<id> = "KEY" | false). The plugin keeps its
// action (declared in its hypr.lua via mod.bind); the user owns the key.
//
// Live flow: write override -> `hyprctl reload` -> the loader re-evaluates
// (overrides applied) and rewrites the report -> the FileView refreshes here.
// A disabled plugin keeps its LAST KNOWN binds visible (report → bindsCached).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    anchors.fill: parent
    property var bar: null
    property var host: null

    // ── report (~/.cache/equisdots/plugins-report.json) ───────────────────
    readonly property string reportPath: {
        let c = Quickshell.env("XDG_CACHE_HOME");
        if (!c || c === "") c = Quickshell.env("HOME") + "/.cache";
        return c + "/equisdots/plugins-report.json";
    }
    property var report: []
    property string lastReportText: ""

    function applyReportText(txt) {
        if (!txt || txt === "") txt = "[]";
        if (txt === root.lastReportText) return;   // content choke point
        root.lastReportText = txt;
        try {
            let o = JSON.parse(txt);
            root.report = Array.isArray(o) ? o : [];
        } catch (e) { root.report = []; }
    }

    // The loader rewrites the report in place on every compositor config load.
    // Watch the file and RE-READ it through a Process: FileView.text() can lag
    // the change event (the shell's choke-point pattern, see Bar.qml/Theme.qml).
    function reloadReport() { reportReader.running = false; reportReader.running = true; }
    FileView {
        id: reportWatcher
        path: root.reportPath
        watchChanges: true
        onFileChanged: root.reloadReport()
        onLoaded: root.reloadReport()
        onLoadFailed: root.applyReportText("[]")
    }
    Process {
        id: reportReader
        command: ["bash", "-c", "cat '" + root.reportPath + "' 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: root.applyReportText(this.text)
        }
    }

    // Plugins that have binds (disabled ones come from the cached carry-over).
    readonly property var entries: {
        let out = [];
        for (let i = 0; i < root.report.length; i++) {
            let e = root.report[i] || {};
            if (e.binds && e.binds.length > 0) out.push(e);
        }
        return out;
    }

    function entryByDir(d) {
        for (let i = 0; i < root.report.length; i++) {
            let e = root.report[i] || {};
            if (String(e.dir || "") === d) return e;
        }
        return null;
    }

    // ── live binds (hyprctl) → the core's own shortcuts ───────────────────
    // The core owns its defaults (keybinds.lua): they are shown read-only and
    // a capture onto a core key is REFUSED — a plugin override must never
    // silently remove a core shortcut. Plugin binds are attributed through
    // the report (see ui/Binds.js).
    property var liveBinds: []
    readonly property var coreList: Binds.coreBinds(root.liveBinds, root.report)
    property string captureNotice: ""

    function reloadCoreBinds() { coreBindsReader.running = false; coreBindsReader.running = true; }
    Process {
        id: coreBindsReader
        command: ["bash", "-c", "hyprctl binds -j 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let o = JSON.parse(this.text || "[]");
                    root.liveBinds = Array.isArray(o) ? o : [];
                } catch (e) { root.liveBinds = []; }
            }
        }
    }
    Component.onCompleted: root.reloadCoreBinds()

    // ── capture state (one bind at a time) ────────────────────────────────
    property string captureDir: ""
    property string captureBind: ""
    readonly property bool capturing: root.captureBind !== ""

    function startCapture(e, b) {
        root.captureNotice = "";
        root.captureDir = String(e.dir || "");
        root.captureBind = String(b.id || "");
    }
    function cancelCapture() { root.captureDir = ""; root.captureBind = ""; }
    function commitCapture(combo) {
        let e = root.entryByDir(root.captureDir);
        let id = root.captureBind;
        let hit = Binds.coreHit(combo, root.coreList);
        if (hit !== "") {
            root.captureNotice = combo + " is a core shortcut (" + hit + ") — pick another key.";
            root.cancelCapture();
            return;
        }
        root.captureNotice = "";
        root.cancelCapture();
        if (e && id !== "") root.writeOverride(e, id, combo);
    }

    function keyName(key) {
        if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key);
        if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key);
        if (key >= Qt.Key_F1 && key <= Qt.Key_F35) return "F" + (key - Qt.Key_F1 + 1);
        switch (key) {
            case Qt.Key_Print: return "Print";
            case Qt.Key_Return: case Qt.Key_Enter: return "Return";
            case Qt.Key_Space: return "space";
            case Qt.Key_Tab: return "Tab";
            case Qt.Key_Backspace: return "BackSpace";
            case Qt.Key_Delete: return "Delete";
            case Qt.Key_Home: return "Home";
            case Qt.Key_End: return "End";
            case Qt.Key_PageUp: return "Page_Up";
            case Qt.Key_PageDown: return "Page_Down";
            case Qt.Key_Insert: return "Insert";
            case Qt.Key_Left: return "left";
            case Qt.Key_Right: return "right";
            case Qt.Key_Up: return "up";
            case Qt.Key_Down: return "down";
            case Qt.Key_Apostrophe: return "apostrophe";
            case Qt.Key_Minus: return "minus";
            case Qt.Key_Equal: return "equal";
            case Qt.Key_Comma: return "comma";
            case Qt.Key_Period: return "period";
            case Qt.Key_Slash: return "slash";
            case Qt.Key_Semicolon: return "semicolon";
            case Qt.Key_BracketLeft: return "bracketleft";
            case Qt.Key_BracketRight: return "bracketright";
            case Qt.Key_Backslash: return "backslash";
            case Qt.Key_QuoteLeft: return "grave";
        }
        return "";
    }
    function comboFor(event) {
        let mods = [];
        if (event.modifiers & Qt.MetaModifier) mods.push("SUPER");
        if (event.modifiers & Qt.ControlModifier) mods.push("CTRL");
        if (event.modifiers & Qt.AltModifier) mods.push("ALT");
        if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT");
        let k = root.keyName(event.key);
        if (k === "") return "";
        return mods.concat([k]).join(" + ");
    }

    // Invisible full-area focus trap: captures the combo while re-keying.
    // opacity (not visible:false — invisible items cannot hold focus).
    Item {
        id: captureTrap
        anchors.fill: parent
        opacity: 0
        focus: root.capturing
        Keys.onPressed: (event) => {
            if (!root.capturing) return;
            if (event.key === Qt.Key_Escape) { root.cancelCapture(); event.accepted = true; return; }
            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) return;
            let combo = root.comboFor(event);
            if (combo !== "") { root.commitCapture(combo); event.accepted = true; }
        }
    }

    // ── overrides (each plugin's own settings file) ───────────────────────
    function bindsPath(e, id) {
        let scope = String(e.scope || ("plugins." + e.id));
        return scope.split(".").concat(["binds", id]);
    }
    function writeOverride(e, id, value) {   // value: "KEY" | false
        let dir = String(e.dir || "");
        if (dir === "") return;
        let p = JSON.stringify(root.bindsPath(e, id));
        let v = (value === false) ? "false" : JSON.stringify(String(value));
        let cmd = "f='" + dir + "/settings.json'; mkdir -p \"$(dirname \"$f\")\"; " +
                  "[ -s \"$f\" ] || echo '{}' > \"$f\"; " +
                  "tmp=$(mktemp \"$f\".tmp.XXXXXX) && " +
                  "jq --argjson p '" + p + "' --argjson v " + v + " 'setpath($p; $v)' \"$f\" > \"$tmp\" && mv \"$tmp\" \"$f\"";
        Quickshell.execDetached(["bash", "-c", cmd]);
        reloadTimer.restart();
    }
    function removeOverride(e, id) {
        let dir = String(e.dir || "");
        if (dir === "") return;
        let p = JSON.stringify(root.bindsPath(e, id));
        let cmd = "f='" + dir + "/settings.json'; [ -s \"$f\" ] || exit 0; " +
                  "tmp=$(mktemp \"$f\".tmp.XXXXXX) && " +
                  "jq --argjson p '" + p + "' 'delpaths([$p])' \"$f\" > \"$tmp\" && mv \"$tmp\" \"$f\"";
        Quickshell.execDetached(["bash", "-c", cmd]);
        reloadTimer.restart();
    }
    function resetPlugin(e) {
        let dir = String(e.dir || "");
        if (dir === "") return;
        let paths = [];
        let bs = e.binds || [];
        for (let i = 0; i < bs.length; i++) {
            let b = bs[i] || {};
            if (b.overridden === true || b.disabled === true) paths.push(root.bindsPath(e, b.id));
        }
        if (paths.length === 0) return;
        let p = JSON.stringify(paths);
        let cmd = "f='" + dir + "/settings.json'; [ -s \"$f\" ] || exit 0; " +
                  "tmp=$(mktemp \"$f\".tmp.XXXXXX) && " +
                  "jq --argjson p '" + p + "' 'delpaths($p)' \"$f\" > \"$tmp\" && mv \"$tmp\" \"$f\"";
        Quickshell.execDetached(["bash", "-c", cmd]);
        reloadTimer.restart();
    }

    Process { id: hyprReload; command: ["hyprctl", "reload"]; onExited: root.reloadCoreBinds() }
    Timer { id: reloadTimer; interval: 250; onTriggered: { hyprReload.running = false; hyprReload.running = true; } }

    // ── derived helpers ────────────────────────────────────────────────────
    function hasOverrides(e) {
        let bs = e.binds || [];
        for (let i = 0; i < bs.length; i++) {
            let b = bs[i] || {};
            if (b.overridden === true || b.disabled === true) return true;
        }
        return false;
    }
    // Effective-key collision against the other plugins' binds (report) and
    // the core's own shortcuts (refused on capture; flagged here for
    // hand-edited files that already point at a core key).
    function conflictsFor(e, b) {
        let key = String(b.key || "");
        if (b.disabled === true || key === "") return "";
        let hits = [];
        for (let i = 0; i < root.report.length; i++) {
            let p = root.report[i] || {};
            if (String(p.dir || "") === String(e.dir || "")) continue;
            let bs = p.binds || [];
            for (let j = 0; j < bs.length; j++) {
                let o = bs[j] || {};
                if (o.disabled === true) continue;
                if (String(o.key) === key)
                    hits.push(String(p.id || "?") + ": " + String(o.label || o.id || ""));
            }
        }
        let hit = Binds.coreHit(key, root.coreList);
        if (hit !== "") hits.push("core — " + hit);
        return hits.join("  ·  ");
    }
    function statusText(e) {
        if (e.status === "collision") return "Collision";
        if (e.status === "incompatible") return "Incompatible";
        if (e.status === "error") return "Error";
        if (e.enabled !== true) return "Disabled";
        return "Enabled";
    }
    function statusColor(e) {
        if (e.status === "collision" || e.status === "error") return bar.colors.red;
        if (e.status === "incompatible") return bar.colors.yellow;
        if (e.enabled !== true) return bar.colors.subtext0;
        return bar.colors.mauve;
    }

    readonly property var flickable: body.item ? body.item.flickable : null

    Loader { id: body; anchors.fill: parent; active: root.bar !== null; sourceComponent: pageBody }

    Component {
        id: pageBody
        Item {
            anchors.fill: parent
            property alias flickable: flick

            Flickable {
                id: flick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: col.height + bar.s(16)
                ScrollBar.vertical: ScrollBar { width: bar.s(4); policy: ScrollBar.AsNeeded }

                Column {
                    id: col
                    x: bar.s(8); y: bar.s(8)
                    width: flick.width - bar.s(16)
                    spacing: bar.s(9)

                    Text {
                        text: "Keybinds"
                        font.family: "Hack Nerd Font"; font.weight: Font.Black
                        font.pixelSize: bar.s(24); color: bar.colors.text
                    }

                    RowLayout {
                        width: parent.width
                        spacing: bar.s(Theme.gapSm)
                        EditLabel {
                            bar: root.bar
                            Layout.fillWidth: true
                            text: "The shortcuts each plugin ships (declared in its hypr.lua). Change a key, mute a single bind or reset it — the plugin keeps its action; the compositor reloads to apply."
                            font.pixelSize: bar.s(11)
                            color: bar.colors.subtext0
                            wrapMode: Text.WordWrap
                        }
                        EditorButton {
                            bar: root.bar
                            compact: true
                            icon: ""
                            label: "Refresh"
                            onActivated: { root.reloadReport(); root.reloadCoreBinds(); }
                        }
                    }

                    // Capture refusal / collision notice (core keys are owned).
                    EditLabel {
                        visible: root.captureNotice !== ""
                        bar: root.bar
                        width: parent.width
                        text: root.captureNotice
                        font.pixelSize: bar.s(11)
                        color: bar.colors.peach
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: root.entries
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            width: col.width
                            height: inner.implicitHeight + bar.s(Theme.gapMd) * 2
                            radius: bar.s(Theme.radiusLg)
                            color: Theme.surfaceContainerLow
                            border.width: 1
                            border.color: Theme.outlineVariant

                            ColumnLayout {
                                id: inner
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: bar.s(Theme.gapMd)
                                anchors.rightMargin: bar.s(Theme.gapMd)
                                spacing: bar.s(Theme.gapSm)

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: bar.s(Theme.gapSm)
                                    Text {
                                        text: "󰌌"
                                        font.family: "Hack Nerd Font"
                                        font.pixelSize: bar.s(16)
                                        color: root.statusColor(card.modelData)
                                    }
                                    Text {
                                        text: card.modelData.id || "?"
                                        font.family: "Hack Nerd Font"
                                        font.weight: Font.Bold
                                        font.pixelSize: bar.s(13)
                                        color: bar.colors.text
                                    }
                                    Rectangle {
                                        radius: bar.s(Theme.radiusSm)
                                        color: Qt.alpha(root.statusColor(card.modelData), 0.15)
                                        border.width: 1
                                        border.color: root.statusColor(card.modelData)
                                        implicitWidth: stText.implicitWidth + bar.s(Theme.gapMd)
                                        implicitHeight: stText.implicitHeight + bar.s(Theme.gapXs)
                                        Text {
                                            id: stText
                                            anchors.centerIn: parent
                                            text: root.statusText(card.modelData)
                                            font.family: "Hack Nerd Font"
                                            font.pixelSize: bar.s(9)
                                            color: root.statusColor(card.modelData)
                                        }
                                    }
                                    Rectangle {
                                        visible: card.modelData.bindsCached === true
                                        radius: bar.s(Theme.radiusSm)
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.outlineVariant
                                        implicitWidth: cachedText.implicitWidth + bar.s(Theme.gapMd)
                                        implicitHeight: cachedText.implicitHeight + bar.s(Theme.gapXs)
                                        Text {
                                            id: cachedText
                                            anchors.centerIn: parent
                                            text: "cached"
                                            font.family: "Hack Nerd Font"
                                            font.pixelSize: bar.s(9)
                                            color: bar.colors.subtext0
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    EditorButton {
                                        visible: root.hasOverrides(card.modelData)
                                        bar: root.bar
                                        compact: true
                                        icon: "󰜺"
                                        label: "Reset all"
                                        onActivated: root.resetPlugin(card.modelData)
                                    }
                                }

                                Repeater {
                                    model: card.modelData.binds
                                    delegate: ColumnLayout {
                                        id: bindCol
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        spacing: bar.s(2)

                                        readonly property bool capturingThis: root.capturing
                                            && root.captureDir === String(card.modelData.dir || "")
                                            && root.captureBind === String(bindCol.modelData.id || "")
                                        readonly property string conflict: root.conflictsFor(card.modelData, bindCol.modelData)
                                        readonly property bool off: bindCol.modelData.disabled === true
                                        readonly property bool altered: bindCol.modelData.overridden === true || off

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: bar.s(Theme.gapSm)

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    text: bindCol.modelData.label || bindCol.modelData.id || "?"
                                                    font.family: "Hack Nerd Font"
                                                    font.pixelSize: bar.s(12)
                                                    color: bindCol.off ? bar.colors.subtext0 : bar.colors.text
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    visible: bindCol.altered
                                                    text: "default: " + (bindCol.modelData.defaultKey || "?")
                                                    font.family: "Hack Nerd Font"
                                                    font.pixelSize: bar.s(10)
                                                    color: bar.colors.subtext0
                                                }
                                            }

                                            Rectangle {
                                                radius: bar.s(Theme.radiusMd)
                                                color: Theme.surfaceContainer
                                                border.width: 1
                                                border.color: bindCol.capturingThis ? bar.colors.mauve : Theme.outlineVariant
                                                implicitWidth: keyLabel.implicitWidth + bar.s(24)
                                                implicitHeight: bar.s(28)
                                                Text {
                                                    id: keyLabel
                                                    anchors.centerIn: parent
                                                    text: bindCol.capturingThis ? "Press keys…"
                                                        : (bindCol.off ? "off" : (bindCol.modelData.key || "?"))
                                                    font.family: "Hack Nerd Font"
                                                    font.pixelSize: bar.s(11)
                                                    color: bindCol.capturingThis ? bar.colors.mauve
                                                        : (bindCol.off ? bar.colors.subtext0 : bar.colors.text)
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.startCapture(card.modelData, bindCol.modelData)
                                                }
                                            }

                                            EditorButton {
                                                visible: bindCol.modelData.overridden === true
                                                bar: root.bar
                                                compact: true
                                                icon: "󰜺"
                                                label: ""
                                                onActivated: root.removeOverride(card.modelData, bindCol.modelData.id)
                                            }

                                            ToggleSwitch {
                                                bar: root.bar
                                                checked: !bindCol.off
                                                onToggled: {
                                                    if (checked) root.removeOverride(card.modelData, bindCol.modelData.id);
                                                    else root.writeOverride(card.modelData, bindCol.modelData.id, false);
                                                }
                                            }
                                        }

                                        EditLabel {
                                            Layout.fillWidth: true
                                            visible: bindCol.conflict !== ""
                                            bar: root.bar
                                            text: "also used by " + bindCol.conflict
                                            font.pixelSize: bar.s(10)
                                            color: bar.colors.peach
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
                    }

                    EditLabel {
                        visible: root.entries.length === 0
                        bar: root.bar
                        width: parent.width
                        text: "No plugin shortcuts yet. Plugins declare their binds in their hypr.lua (mod.bind); enable one and press Refresh — the loader writes them to plugins-report.json."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    // ── Core (default): the core's own shortcuts ──────────
                    // Read-only reference: these belong to the core config
                    // (keybinds.lua). Plugin keys that collide with one are
                    // refused on capture — a plugin never removes a core bind.
                    SectionTitle {
                        width: parent.width
                        bar: root.bar
                        text: "Core (default)"
                    }
                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Shipped by the core (keybinds.lua) — always on, not editable here. They stay in the core's hands; plugin overrides below can never take one of these keys."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        width: parent.width
                        radius: bar.s(Theme.radiusLg)
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant
                        height: coreCol.implicitHeight + bar.s(Theme.gapMd) * 2
                        visible: root.liveBinds.length > 0

                        ColumnLayout {
                            id: coreCol
                            x: bar.s(Theme.gapMd)
                            y: bar.s(Theme.gapMd)
                            width: parent.width - bar.s(Theme.gapMd) * 2
                            spacing: bar.s(Theme.gapXs)

                            Repeater {
                                model: root.coreList
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: bar.s(Theme.gapSm)

                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: bar.s(Theme.radiusMd)
                                        color: Theme.surfaceContainer
                                        border.width: 1
                                        border.color: Theme.outlineVariant
                                        implicitWidth: coreKeyText.implicitWidth + bar.s(20)
                                        implicitHeight: bar.s(24)
                                        Text {
                                            id: coreKeyText
                                            anchors.centerIn: parent
                                            text: modelData.key
                                            font.family: "Hack Nerd Font"
                                            font.pixelSize: bar.s(10)
                                            color: bar.colors.text
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: modelData.action
                                        font.family: "Hack Nerd Font"
                                        font.pixelSize: bar.s(10)
                                        color: bar.colors.subtext0
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                    EditLabel {
                        visible: root.liveBinds.length === 0
                        bar: root.bar
                        width: parent.width
                        text: "The core bind list needs a running Hyprland session (hyprctl binds)."
                        font.pixelSize: bar.s(11)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }

                    EditLabel {
                        bar: root.bar
                        width: parent.width
                        text: "Overrides live in each plugin's own settings file (<scope>.binds.<id>) — the plugin's identity, action and defaults stay untouched."
                        font.pixelSize: bar.s(10)
                        color: bar.colors.subtext0
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
