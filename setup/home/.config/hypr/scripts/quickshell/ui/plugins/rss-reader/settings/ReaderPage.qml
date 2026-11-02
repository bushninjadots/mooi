// ReaderPage — the RSS Reader plugin's own settings page (equisdots plugin
// standard). Deployed with the plugin UI to <quickshell>/ui/plugins/
// rss-reader/settings/ and loaded by the editor as the dynamic p_rss-reader
// page: feeds manager, refresh cadence, reading options and the panel
// position — nothing lives in other pages.
//
// Everything it edits lives in settings.json → "rss-reader" (feeds,
// refreshMs, showDesc) and → "widgets"."rss-reader".position; the reader
// panel reads the same objects live.
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
import "../ui/ReaderDefaults.js" as Defaults

Item {
    id: root
    anchors.fill: parent

    property var bar: null
    property var host: null

    // ── local mirror of settings.json → rss-reader (+ widgets position) ─────
    property var feeds: []
    property int refreshMs: 600000
    property bool showDesc: true
    property string position: "default"
    property string note: ""

    function load() {
        Config.rev;
        let c = (Config.rawSettings && Config.rawSettings["rss-reader"]) ? Config.rawSettings["rss-reader"] : {};
        root.feeds = Array.isArray(c.feeds) ? c.feeds.slice() : [];
        root.refreshMs = (Number(c.refreshMs) >= 60000) ? Number(c.refreshMs) : 600000;
        root.showDesc = c.showDesc !== false;
        let w = (Config.rawSettings && Config.rawSettings.widgets) ? Config.rawSettings.widgets : {};
        root.position = (w["rss-reader"] && w["rss-reader"].position) ? w["rss-reader"].position : "default";
    }
    Component.onCompleted: root.load()

    function flash(msg) { root.note = msg; flashTimer.restart(); }
    Timer { id: flashTimer; interval: 2500; onTriggered: root.note = "" }

    function setOpt(patch) {
        let cur = Config.rawSettings["rss-reader"];
        let next = (cur && typeof cur === "object") ? Object.assign({}, cur) : {};
        for (let k in patch) next[k] = patch[k];
        Config.setSetting("rss-reader", next);
    }

    function addFeed(url) {
        url = String(url || "").trim();
        if (url.indexOf("http") !== 0 || url.length < 12) { root.flash("Enter a full feed URL"); return false; }
        if (root.feeds.indexOf(url) !== -1) { root.flash("Feed already in the list"); return false; }
        let list = root.feeds.slice();
        list.push(url);
        root.feeds = list;
        root.setOpt({ feeds: list });
        root.flash("Feed added");
        return true;
    }

    function removeFeed(i) {
        let list = root.feeds.slice();
        if (i < 0 || i >= list.length) return;
        list.splice(i, 1);
        root.feeds = list;
        root.setOpt({ feeds: list });
        root.flash("Feed removed");
    }

    function restoreDefaults() {
        let list = Defaults.FEEDS.slice();
        root.feeds = list;
        root.setOpt({ feeds: list });
        root.flash("Default feeds restored");
    }

    function setPosition(pos) {
        let w = {};
        let cur = Config.rawSettings.widgets;
        if (cur && typeof cur === "object") for (let k in cur) w[k] = cur[k];
        let entry = (w["rss-reader"] && typeof w["rss-reader"] === "object") ? w["rss-reader"] : {};
        let next = {};
        for (let k in entry) next[k] = entry[k];
        next.position = pos;
        w["rss-reader"] = next;
        Config.setSetting("widgets", w);
        root.position = pos;
    }

    function refreshLabel() {
        return Math.round(root.refreshMs / 60000) + " min";
    }
    function bumpRefresh(d) {
        let idx = Defaults.REFRESH_PRESETS_MS.indexOf(root.refreshMs);
        if (idx === -1) idx = 1;
        idx = Math.max(0, Math.min(Defaults.REFRESH_PRESETS_MS.length - 1, idx + d));
        root.refreshMs = Defaults.REFRESH_PRESETS_MS[idx];
        root.setOpt({ refreshMs: root.refreshMs });
    }

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

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: col.height + bar.s(16)
        ScrollBar.vertical: ScrollBar {
            id: vScroll
            width: bar.s(4)
            policy: ScrollBar.AsNeeded
            hoverEnabled: true
            active: flick.moving || vScroll.hovered
            contentItem: Rectangle {
                radius: bar.s(2)
                color: bar.colors.surface2
                opacity: vScroll.active ? 1.0 : 0.45
            }
            background: Item {}
        }

        Column {
            id: col
            x: bar.s(8)
            y: bar.s(8)
            width: flick.width - bar.s(16)
            spacing: bar.s(9)

            Text {
                text: "RSS Reader"
                font.family: "Hack Nerd Font"
                font.weight: Font.Black
                font.pixelSize: bar.s(24)
                color: bar.colors.text
            }

            EditLabel {
                bar: root.bar
                width: parent.width
                text: "Feeds, refresh cadence and reading options for the RSS panel (SUPER + O). Everything here is stored in settings.json → rss-reader; the panel applies changes live."
                font.pixelSize: bar.s(11)
                color: bar.colors.subtext0
                wrapMode: Text.WordWrap
            }

            // ── feeds ────────────────────────────────────────────────────────
            SectionTitle { bar: root.bar; text: "Feeds (" + root.feeds.length + ")" }

            Repeater {
                model: root.feeds
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: col.width
                    height: bar.s(42)
                    radius: bar.s(18)
                    color: Qt.alpha(bar.colors.surface0, 0.4)
                    border.width: 1
                    border.color: feedMa.containsMouse ? bar.colors.mauve : bar.colors.surface1
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: bar.s(14)
                        anchors.rightMargin: bar.s(8)
                        spacing: bar.s(8)

                        Text {
                            text: "\uf09e"
                            font.family: "Hack Nerd Font"
                            font.pixelSize: bar.s(12)
                            color: bar.colors.overlay1
                        }
                        Text {
                            Layout.fillWidth: true
                            text: String(modelData).replace(/^https?:\/\//, "").replace(/^www\./, "")
                            elide: Text.ElideRight
                            font.family: "Hack Nerd Font"
                            font.pixelSize: bar.s(11)
                            color: bar.colors.text
                        }
                        EditorButton {
                            bar: root.bar
                            compact: true
                            icon: "\uf00d"
                            label: ""
                            onActivated: root.removeFeed(index)
                        }
                    }
                    MouseArea {
                        id: feedMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
            }

            EditLabel {
                bar: root.bar
                width: parent.width
                visible: root.feeds.length === 0
                text: "No feeds yet. Add one below or restore the defaults."
                font.pixelSize: bar.s(11)
                color: bar.colors.subtext0
                wrapMode: Text.WordWrap
            }

            // Add row: the FieldCard is recreated after a successful add so the
            // input starts clean (its TextField stops following `value` once
            // the user types).
            Loader {
                id: addField
                width: col.width
                height: bar.s(44)
                sourceComponent: Component {
                    FieldCard {
                        bar: root.bar
                        label: "Add feed"
                        placeholder: "https://example.com/feed.xml"
                        onEdited: if (root.addFeed(text)) { addField.active = false; addField.active = true; }
                    }
                }
            }

            RowLayout {
                width: parent.width
                spacing: bar.s(8)

                EditorButton {
                    bar: root.bar
                    compact: true
                    icon: "\uf0c9"
                    label: "Restore defaults"
                    onActivated: root.restoreDefaults()
                }
                Item { Layout.fillWidth: true }
                EditLabel {
                    bar: root.bar
                    visible: root.note !== ""
                    text: root.note
                    font.pixelSize: bar.s(11)
                    color: bar.colors.green
                }
            }

            // ── reading ──────────────────────────────────────────────────────
            SectionTitle { bar: root.bar; text: "Reading" }

            StepperCard {
                bar: root.bar
                width: col.width
                label: "Refresh every"
                value: root.refreshLabel()
                onDec: root.bumpRefresh(-1)
                onInc: root.bumpRefresh(1)
            }

            RowLayout {
                width: parent.width
                spacing: bar.s(12)
                Text {
                    text: "Show descriptions"
                    font.family: "Hack Nerd Font"
                    font.pixelSize: bar.s(12)
                    color: bar.colors.text
                    Layout.fillWidth: true
                }
                ToggleSwitch {
                    bar: root.bar
                    checked: root.showDesc
                    onToggled: { root.showDesc = checked; root.setOpt({ showDesc: checked }); }
                }
            }

            // ── panel position ───────────────────────────────────────────────
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
