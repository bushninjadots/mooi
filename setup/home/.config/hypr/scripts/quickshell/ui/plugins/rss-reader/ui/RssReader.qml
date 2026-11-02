// RssReader — the RSS Reader plugin's panel (equisdots plugin standard).
//
// Loaded by the shell's panel host from ui/plugins/rss-reader/ (manifest
// provides.panels.rss-reader); the qs.* imports resolve against the shell
// tree. Feeds, refresh interval and the description toggle live in
// settings.json → "rss-reader" and are edited by the plugin's own settings
// page (settings/ReaderPage.qml).
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui.bar
import "ReaderDefaults.js" as Defaults

Item {
    id: window

    Colors { id: _theme }
    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) }

    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color blue: _theme.blue

    // ── settings.json → rss-reader (the settings page edits the same object) ─
    readonly property var cfg: {
        Config.rev;
        let c = Config.rawSettings["rss-reader"];
        return (c && typeof c === "object") ? c : {};
    }
    readonly property var feeds: {
        let f = cfg.feeds;
        if (!Array.isArray(f)) return [];
        return f.filter(u => typeof u === "string" && u !== "");
    }
    readonly property int refreshMs: {
        let v = Number(cfg.refreshMs);
        return (v >= 60000) ? v : 600000;
    }
    readonly property bool showDesc: cfg.showDesc !== false

    // ── state ────────────────────────────────────────────────────────────────
    property var entries: []
    property string selectedFeed: ""
    property string query: ""
    property bool loading: false
    property string statusText: "Loading…"
    property bool failed: false
    property string updatedAt: ""

    property var feedNames: []
    property var feedCounts: ({})

    // ── data fetching ────────────────────────────────────────────────────────
    // fetch.py resolver: the plugin's copy across deploy layouts (managed
    // shell tree, user plugin) with the pre-cutover path as last resort.
    readonly property string fetchCmd: "S=; for c in \"$HOME/.config/hypr/scripts/quickshell/ui/plugins/rss-reader/scripts/fetch.py\" \"$HOME/.config/hypr/plugins-user/rss-reader/scripts/fetch.py\" \"$HOME/.config/hypr/scripts/quickshell/ui/panels/rss-reader/fetch.py\"; do [ -f \"$c\" ] && { S=\"$c\"; break; }; done; [ -n \"$S\" ] && exec python3 \"$S\" \"$@\""

    function refresh() {
        if (window.feeds.length === 0) return;
        window.loading = true;
        fetcher.running = false;
        fetcher.running = true;
    }

    Process {
        id: fetcher
        running: false
        command: ["bash", "-c", window.fetchCmd, "rss-reader"].concat(window.feeds)
        stdout: StdioCollector {
            onStreamFinished: {
                window.loading = false;
                try {
                    if (this.text && this.text.trim().length > 0) {
                        window.entries = JSON.parse(this.text.trim());
                    } else {
                        window.entries = [];
                    }
                    window.failed = false;
                    window.statusText = window.entries.length + " articles";
                    let d = new Date();
                    window.updatedAt = d.getHours().toString().padStart(2, "0") + ":"
                                     + d.getMinutes().toString().padStart(2, "0");
                    window.rebuildFeeds();
                } catch (e) {
                    window.failed = true;
                    window.statusText = "Could not parse the feed data";
                }
            }
        }
    }

    Timer {
        interval: window.refreshMs
        running: true
        repeat: true
        onTriggered: window.refresh()
    }

    // First run: seed the config from the legacy in-tree feeds.txt (pre-plugin
    // installs) or from the plugin defaults, so the page always shows a list.
    Process {
        id: legacyImport
        running: false
        command: ["bash", "-c", "cat \"$HOME/.config/hypr/scripts/quickshell/ui/panels/rss-reader/feeds.txt\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (window.feeds.length > 0) return;
                let urls = [];
                let lines = (this.text || "").split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let l = lines[i].trim();
                    if (l !== "" && l.charAt(0) !== "#" && l.indexOf("http") === 0) urls.push(l);
                }
                if (urls.length === 0) urls = Defaults.FEEDS.slice();
                window.persist({ feeds: urls });
            }
        }
    }

    function persist(patch) {
        let cur = Config.rawSettings["rss-reader"];
        let next = (cur && typeof cur === "object") ? Object.assign({}, cur) : {};
        for (let k in patch) next[k] = patch[k];
        Config.setSetting("rss-reader", next);
        refresh();
    }

    function init() {
        if (window.feeds.length === 0) legacyImport.running = true;
        else refresh();
    }

    Timer {
        id: initTimer
        interval: 300
        repeat: true
        running: false
        onTriggered: if (Config.dataReady) { stop(); window.init(); }
    }

    Component.onCompleted: {
        if (Config.dataReady) window.init();
        else initTimer.start();
    }

    // ── derived data ─────────────────────────────────────────────────────────
    function rebuildFeeds() {
        let names = [];
        let counts = {};
        for (let i = 0; i < entries.length; i++) {
            let f = entries[i].feed;
            if (!counts[f]) { counts[f] = 0; names.push(f); }
            counts[f]++;
        }
        window.feedNames = names;
        window.feedCounts = counts;
    }

    readonly property var filtered: {
        let q = window.query.trim().toLowerCase();
        let out = [];
        for (let i = 0; i < entries.length; i++) {
            let e = entries[i];
            if (window.selectedFeed !== "" && e.feed !== window.selectedFeed) continue;
            if (q !== "") {
                let hay = (e.title + " " + (e.desc || "") + " " + e.feed).toLowerCase();
                if (hay.indexOf(q) === -1) continue;
            }
            out.push(e);
        }
        return out;
    }

    function shortFeed(name) {
        let n = String(name || "").replace(/^https?:\/\//, "").replace(/^www\./, "");
        return n.split("/")[0];
    }

    function feedColor(name) {
        let roles = ["mauve", "blue", "green", "peach", "teal", "sapphire", "pink", "yellow"];
        let h = 0;
        let n = String(name || "");
        for (let i = 0; i < n.length; i++) h = (h * 31 + n.charCodeAt(i)) % 9973;
        return _theme[roles[h % roles.length]] || _theme.mauve;
    }

    function relTime(t) {
        if (!t) return "";
        let d = Math.max(0, Math.floor(Date.now() / 1000) - t);
        if (d < 60) return "now";
        if (d < 3600) return Math.floor(d / 60) + "m";
        if (d < 86400) return Math.floor(d / 3600) + "h";
        if (d < 604800) return Math.floor(d / 86400) + "d";
        return Math.floor(d / 604800) + "w";
    }

    // ── UI ───────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: window.base
        radius: s(16)

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header: title + count + search + refresh
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: s(54)
                Layout.leftMargin: s(18)
                Layout.rightMargin: s(14)
                spacing: s(10)

                Text {
                    text: "\uf09e"
                    font.family: "Hack Nerd Font"
                    font.pixelSize: s(18)
                    color: window.mauve
                }
                ColumnLayout {
                    spacing: 0
                    Text {
                        text: "RSS"
                        font.family: "Hack Nerd Font"
                        font.pixelSize: s(15)
                        font.weight: Font.Bold
                        color: window.text
                    }
                    Text {
                        text: window.failed ? "error" : (window.filtered.length + " shown")
                        font.family: "Hack Nerd Font"
                        font.pixelSize: s(9)
                        color: window.failed ? window.mauve : window.overlay0
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: s(190)
                    Layout.preferredHeight: s(30)
                    radius: s(10)
                    color: Qt.alpha(window.surface0, 0.6)
                    border.width: 1
                    border.color: searchField.activeFocus ? window.mauve : window.surface1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: s(9)
                        anchors.rightMargin: s(9)
                        spacing: s(6)
                        Text {
                            text: "\uf002"
                            font.family: "Hack Nerd Font"
                            font.pixelSize: s(11)
                            color: window.overlay0
                        }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            placeholderText: "Search…"
                            placeholderTextColor: window.overlay0
                            color: window.text
                            font.family: "Hack Nerd Font"
                            font.pixelSize: s(10)
                            background: Item {}
                            onTextChanged: window.query = text
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: s(30)
                    Layout.preferredHeight: s(30)
                    radius: s(9)
                    color: refreshMa.containsMouse ? Qt.alpha(window.mauve, 0.2) : Qt.alpha(window.surface0, 0.6)
                    border.width: 1
                    border.color: refreshMa.containsMouse ? window.mauve : window.surface1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf021"
                        font.family: "Hack Nerd Font"
                        font.pixelSize: s(13)
                        color: window.mauve
                        RotationAnimator on rotation {
                            running: window.loading
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 900
                        }
                    }
                    MouseArea {
                        id: refreshMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.refresh()
                    }
                }
            }

            // Feed filter pills
            ListView {
                id: feedBar
                Layout.fillWidth: true
                Layout.preferredHeight: s(38)
                orientation: ListView.Horizontal
                spacing: s(6)
                clip: true
                leftMargin: s(16)
                rightMargin: s(16)
                boundsBehavior: Flickable.StopAtBounds

                model: {
                    let items = [{ name: "All", count: window.entries.length }];
                    for (let i = 0; i < window.feedNames.length; i++)
                        items.push({ name: window.feedNames[i], count: window.feedCounts[window.feedNames[i]] });
                    return items;
                }

                delegate: Rectangle {
                    required property var modelData
                    height: s(28)
                    y: Math.round((feedBar.height - height) / 2)
                    width: pillRow.implicitWidth + s(20)
                    radius: s(14)
                    readonly property bool active: modelData.name === window.selectedFeed
                                                || (modelData.name === "All" && window.selectedFeed === "")
                    color: active ? window.mauve
                                  : (pillMa.containsMouse ? Qt.alpha(window.surface1, 0.8) : Qt.alpha(window.surface0, 0.5))
                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: s(6)
                        Text {
                            Layout.maximumWidth: s(130)
                            text: modelData.name === "All" ? "All" : window.shortFeed(modelData.name)
                            elide: Text.ElideRight
                            font.family: "Hack Nerd Font"
                            font.pixelSize: s(10)
                            color: active ? window.crust : window.text
                        }
                        Rectangle {
                            radius: s(7)
                            color: active ? Qt.alpha(window.crust, 0.25) : Qt.alpha(window.surface2, 0.7)
                            implicitWidth: countTxt.implicitWidth + s(10)
                            implicitHeight: countTxt.implicitHeight + s(2)
                            Text {
                                id: countTxt
                                anchors.centerIn: parent
                                text: modelData.count
                                font.family: "Hack Nerd Font"
                                font.pixelSize: s(8)
                                color: active ? window.crust : window.overlay0
                            }
                        }
                    }
                    MouseArea {
                        id: pillMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.selectedFeed = modelData.name === "All" ? "" : modelData.name
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: window.surface1
                opacity: 0.25
            }

            // Articles
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: feedList
                    anchors.fill: parent
                    anchors.topMargin: s(6)
                    anchors.bottomMargin: s(4)
                    clip: true
                    spacing: s(3)
                    focus: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: window.filtered

                    function openCurrent() {
                        let m = window.filtered[currentIndex];
                        if (m && m.link) Qt.openUrlExternally(m.link);
                    }

                    Keys.onReturnPressed: openCurrent()
                    Keys.onEnterPressed: openCurrent()

                    ScrollBar.vertical: ScrollBar {
                        active: true
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { implicitWidth: s(4); radius: s(2); color: window.surface2; opacity: 0.5 }
                    }

                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        required property int index
                        width: feedList.width - s(12)
                        x: s(6)
                        height: cardCol.implicitHeight + s(16)
                        radius: s(10)
                        color: (cardMa.containsMouse || feedList.currentIndex === index)
                               ? Qt.alpha(window.surface0, 0.55) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: s(10)
                            anchors.rightMargin: s(10)
                            anchors.topMargin: s(8)
                            anchors.bottomMargin: s(8)
                            spacing: s(10)

                            Rectangle {
                                Layout.preferredWidth: s(3)
                                Layout.fillHeight: true
                                radius: s(2)
                                color: window.feedColor(card.modelData.feed)
                                opacity: cardMa.containsMouse ? 1.0 : 0.55
                            }

                            ColumnLayout {
                                id: cardCol
                                Layout.fillWidth: true
                                spacing: s(3)

                                Text {
                                    Layout.fillWidth: true
                                    text: card.modelData.title
                                    font.family: "Hack Nerd Font"
                                    font.pixelSize: s(12)
                                    font.weight: feedList.currentIndex === index ? Font.Bold : Font.Medium
                                    color: window.text
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    spacing: s(6)
                                    Text {
                                        text: window.shortFeed(card.modelData.feed)
                                        font.family: "Hack Nerd Font"
                                        font.pixelSize: s(9)
                                        color: window.feedColor(card.modelData.feed)
                                    }
                                    Text {
                                        text: "·"
                                        font.family: "Hack Nerd Font"
                                        font.pixelSize: s(9)
                                        color: window.overlay0
                                    }
                                    Text {
                                        text: window.relTime(card.modelData.time)
                                        font.family: "Hack Nerd Font"
                                        font.pixelSize: s(9)
                                        color: window.overlay0
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: window.showDesc && text !== ""
                                    text: card.modelData.desc || ""
                                    font.family: "Hack Nerd Font"
                                    font.pixelSize: s(10)
                                    color: window.subtext0
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            Text {
                                text: "\uf08e"
                                font.family: "Hack Nerd Font"
                                font.pixelSize: s(11)
                                color: window.blue
                                opacity: cardMa.containsMouse ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }
                        }

                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: if (containsMouse) feedList.currentIndex = index
                            onClicked: if (card.modelData.link) Qt.openUrlExternally(card.modelData.link)
                        }
                    }
                }

                // Empty / error state
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - s(80)
                    spacing: s(8)
                    visible: window.filtered.length === 0

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: window.failed ? "\uf071" : "\uf09e"
                        font.family: "Hack Nerd Font"
                        font.pixelSize: s(26)
                        color: window.failed ? window.mauve : window.overlay0
                        opacity: 0.8
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: window.failed
                              ? "Could not load the feeds.\nCheck the URLs in the RSS Reader settings page."
                              : (window.feeds.length === 0
                                 ? "No feeds configured.\nAdd some in the RSS Reader settings page."
                                 : (window.query !== "" ? "No articles match the search."
                                                        : "No articles yet."))
                        font.family: "Hack Nerd Font"
                        font.pixelSize: s(10)
                        color: window.overlay0
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Footer
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: s(22)

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: s(18)
                    anchors.verticalCenter: parent.verticalCenter
                    text: window.statusText + (window.updatedAt !== "" ? " · updated " + window.updatedAt : "")
                    font.family: "Hack Nerd Font"
                    font.pixelSize: s(9)
                    color: window.overlay0
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    text: window.selectedFeed !== "" ? window.shortFeed(window.selectedFeed) : ""
                    font.family: "Hack Nerd Font"
                    font.pixelSize: s(9)
                    color: window.overlay0
                }
            }
        }
    }
}
