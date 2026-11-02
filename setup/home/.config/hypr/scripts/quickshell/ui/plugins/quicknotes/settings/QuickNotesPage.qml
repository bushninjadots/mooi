// QuickNotesPage — the QuickNotes plugin's own settings page (equisdots
// plugin standard). Deployed with the plugin UI to <quickshell>/ui/plugins/
// quicknotes/settings/ and loaded by the editor as the dynamic p_quicknotes
// page.
//
// Edits settings.json → "quicknotes" (saveDebounceMs) and → "widgets".
// "quicknotes".position; the panel reads the same objects live.
//
// Contract: receives the BarEditor root as `bar` (bar.s(), bar.colors) and
// the injected SDK handle as `host` (equisdots/plugin-sdk).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.ui.bar.edit
import qs.ui.bar
import qs.core

Item {
    id: root
    anchors.fill: parent

    property var bar: null
    property var host: null

    property int saveDebounceMs: 800
    property string position: "default"

    readonly property var positions: [
        { id: "default",       icon: "▣", label: "Auto" },
        { id: "top-left",      icon: "↖", label: "Top left" },
        { id: "top-center",    icon: "↑", label: "Top center" },
        { id: "top-right",     icon: "↗", label: "Top right" },
        { id: "center-left",   icon: "←", label: "Center left" },
        { id: "center",        icon: "•", label: "Center" },
        { id: "center-right",  icon: "→", label: "Center right" },
        { id: "bottom-left",   icon: "↙", label: "Bottom left" },
        { id: "bottom-center", icon: "↓", label: "Bottom center" },
        { id: "bottom-right",  icon: "↘", label: "Bottom right" }
    ]

    function load() {
        Config.rev;
        let c = (Config.rawSettings && Config.rawSettings.quicknotes) ? Config.rawSettings.quicknotes : {};
        root.saveDebounceMs = (Number(c.saveDebounceMs) >= 200 && Number(c.saveDebounceMs) <= 5000)
                              ? Number(c.saveDebounceMs) : 800;
        let w = (Config.rawSettings && Config.rawSettings.widgets) ? Config.rawSettings.widgets : {};
        root.position = (w.quicknotes && w.quicknotes.position) ? w.quicknotes.position : "default";
    }
    Component.onCompleted: root.load()

    function setOpt(patch) {
        let cur = Config.rawSettings.quicknotes;
        let next = (cur && typeof cur === "object") ? Object.assign({}, cur) : {};
        for (let k in patch) next[k] = patch[k];
        Config.setSetting("quicknotes", next);
    }
    function bump(d) {
        root.saveDebounceMs = Math.max(200, Math.min(5000, root.saveDebounceMs + d));
        root.setOpt({ saveDebounceMs: root.saveDebounceMs });
    }
    function setPosition(pos) {
        let w = {};
        let cur = Config.rawSettings.widgets;
        if (cur && typeof cur === "object") for (let k in cur) w[k] = cur[k];
        let entry = (w.quicknotes && typeof w.quicknotes === "object") ? w.quicknotes : {};
        let next = {};
        for (let k in entry) next[k] = entry[k];
        next.position = pos;
        w.quicknotes = next;
        Config.setSetting("widgets", w);
        root.position = pos;
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: col.height + bar.s(16)
        ScrollBar.vertical: ScrollBar {
            width: bar.s(4)
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle { radius: bar.s(2); color: bar.colors.surface2; opacity: 0.5 }
            background: Item {}
        }

        Column {
            id: col
            x: bar.s(8)
            y: bar.s(8)
            width: flick.width - bar.s(16)
            spacing: bar.s(9)

            Text {
                text: "QuickNotes"
                font.family: "Hack Nerd Font"
                font.weight: Font.Black
                font.pixelSize: bar.s(24)
                color: bar.colors.text
            }
            EditLabel {
                bar: root.bar
                width: parent.width
                text: "The scratch notepad (SUPER + Y). Notes live at ~/.cache/quickshell/quicknotes.txt and auto-save while you type."
                font.pixelSize: bar.s(11)
                color: bar.colors.subtext0
                wrapMode: Text.WordWrap
            }

            SectionTitle { bar: root.bar; text: "Options" }

            StepperCard {
                bar: root.bar
                width: col.width
                label: "Auto-save delay"
                value: (root.saveDebounceMs / 1000).toFixed(1) + " s"
                onDec: root.bump(-100)
                onInc: root.bump(100)
            }

            SectionTitle { bar: root.bar; text: "Panel position" }

            Grid {
                width: col.width
                columns: 2
                spacing: bar.s(8)
                columnSpacing: bar.s(8)
                Repeater {
                    model: root.positions
                    delegate: OptionCard {
                        required property var modelData
                        bar: root.bar
                        width: (col.width - bar.s(8)) / 2
                        height: bar.s(38)
                        icon: modelData.icon
                        label: modelData.label
                        active: root.position === modelData.id
                        onActivated: root.setPosition(modelData.id)
                    }
                }
            }
        }
    }
}
