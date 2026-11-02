import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../../core"
import "../../bar"

// ═══════════════════════════════════════════════════════════════════════════
// PaletteWidget — palette carousel (SUPER + SHIFT + P).
//
// Horizontal, card-style picker focused on colour: each palette is a card
// with a rich thumbnail (four mini apps — VS Code, kitty + xfetch, xtop, nvim —
// painted with that palette) plus the 16 base16 tokens as circles. Browse with
// ‹ › (or ← →), filter by name, apply with Enter or a click (writes bar.palette
// and closes). Fully dynamic: the list is rebuilt from the palette index every
// time the popup opens, so user-generated palettes appear automatically.
//
// Colours come from one python pass over the index + palette files.
// Position: settings.json -> widgets.palette.position (see core/WindowRegistry.js).
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: window

    Colors { id: _theme }
    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) }

    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color mauve: _theme.mauve || "#cba6f7"
    readonly property color crust: _theme.crust

    readonly property string palettesDir: Quickshell.env("HOME")
        + "/.config/hypr/scripts/quickshell/dock/palettes"

    property var palettes: []
    property string filter: ""

    readonly property var filtered: {
        let q = String(window.filter || "").trim().toLowerCase();
        let out = [];
        for (let i = 0; i < window.palettes.length; i++) {
            let p = window.palettes[i];
            if (!p) continue;
            if (q !== "" && String(p.name).toLowerCase().indexOf(q) === -1
                && String(p.slug).toLowerCase().indexOf(q) === -1) continue;
            out.push(p);
        }
        return out;
    }

    readonly property string activeSlug: (Config.rev,
        (Config.rawSettings.bar && Config.rawSettings.bar.palette) || "x")

    readonly property string _py: [
        "import json,os,sys",
        "pd=sys.argv[1]",
        "try: idx=json.load(open(os.path.join(pd,'index.json')))",
        "except Exception: idx=[]",
        "out=[]",
        "for e in idx:",
        "    slug=e.get('slug') or ''",
        "    if not slug: continue",
        "    f=os.path.join(pd,slug+'.json')",
        "    if not os.path.isfile(f): f=os.path.join(pd,'community',slug+'.json')",
        "    det={}",
        "    if os.path.isfile(f):",
        "        try: det=json.load(open(f))",
        "        except Exception: det={}",
        "    b=det.get('base16') or {}",
        "    cols=[b.get('color'+str(i)) for i in range(16)]",
        "    fx=[c for c in cols if c]",
        "    out.append({'slug':slug,'name':e.get('name') or det.get('name') or slug,",
        "        'category':e.get('category') or 'x',",
        "        'background':det.get('background') or (fx[0] if fx else '#1e1e2e'),",
        "        'foreground':det.get('foreground') or (fx[-1] if fx else '#cdd6f4'),",
        "        'colors':cols})",
        "# also pick up palette files not listed in the index (user-generated)",
        "seen=set(o['slug'] for o in out)",
        "import glob",
        "for d,cat in ((pd,'x'),(os.path.join(pd,'community'),'custom')):",
        "    for f in glob.glob(os.path.join(d,'*.json')):",
        "        base=os.path.basename(f)",
        "        if base=='index.json': continue",
        "        slug=base[:-5]",
        "        if slug in seen: continue",
        "        try: det=json.load(open(f))",
        "        except Exception: continue",
        "        b=det.get('base16') or {}",
        "        cols=[b.get('color'+str(i)) for i in range(16)]",
        "        fx=[c for c in cols if c]",
        "        out.append({'slug':slug,'name':det.get('name') or slug,'category':cat,",
        "            'background':det.get('background') or (fx[0] if fx else '#1e1e2e'),",
        "            'foreground':det.get('foreground') or (fx[-1] if fx else '#cdd6f4'),",
        "            'colors':cols})",
        "        seen.add(slug)",
        "print(json.dumps(out))"
    ].join("\n")

    Process {
        id: loader
        command: ["python3", "-c", window._py, window.palettesDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try { window.palettes = JSON.parse(this.text.trim()); }
                catch (e) { window.palettes = []; }
                window.centerActive();
            }
        }
    }

    function reload() { loader.running = false; loader.running = true; }
    function centerActive() {
        let fx = window.filtered;
        for (let i = 0; i < fx.length; i++) {
            if (fx[i].slug === window.activeSlug) { listView.currentIndex = i; return; }
        }
        listView.currentIndex = 0;
    }
    Component.onCompleted: reload()
    onVisibleChanged: if (visible) { filterField.text = ""; reload(); filterField.forceActiveFocus(); }

    function applyPalette(slug) {
        if (!slug) return;
        let next = Object.assign({}, Config.rawSettings.bar || {}, { palette: slug });
        Config.setSetting("bar", next);
        window.closePopup();
    }
    function closePopup() {
        Quickshell.execDetached(["bash", Quickshell.env("HOME")
            + "/.config/hypr/scripts/qs_manager.sh", "close"]);
    }
    function currentSlug() {
        let fx = window.filtered;
        if (fx.length === 0) return "";
        let i = Math.max(0, Math.min(listView.currentIndex, fx.length - 1));
        return fx[i].slug;
    }
    function applyCurrent() { window.applyPalette(window.currentSlug()); }

    // ── UI ──────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: Theme.radiusXl

        Column {
            anchors.fill: parent
            anchors.margins: s(14)
            spacing: s(10)

            Text {
                width: parent.width
                text: "Palette"
                horizontalAlignment: Text.AlignHCenter
                font.family: "Hack Nerd Font"; font.weight: Font.Black; font.pixelSize: s(18)
                color: window.text
            }
            Item {
                width: parent.width; height: s(38)
                Row {
                    anchors.centerIn: parent
                    spacing: s(10)
                    TextField {
                        id: filterField
                        width: s(420); height: s(38)
                        focus: true
                        placeholderText: "Filter palettes…"
                        color: window.text
                        placeholderTextColor: Qt.rgba(window.subtext0.r, window.subtext0.g, window.subtext0.b, 0.7)
                        font.family: "Hack Nerd Font"; font.pixelSize: s(13)
                        leftPadding: s(16); rightPadding: s(16)
                        onTextChanged: { window.filter = text; listView.currentIndex = 0; }
                        background: Rectangle {
                            radius: height / 2
                            color: Theme.surfaceContainer
                            border.width: 1
                            border.color: filterField.activeFocus ? window.mauve : Theme.outlineVariant
                        }
                        Keys.onLeftPressed: (event) => { listView.decrementCurrentIndex(); event.accepted = true; }
                        Keys.onRightPressed: (event) => { listView.incrementCurrentIndex(); event.accepted = true; }
                        Keys.onReturnPressed: (event) => { window.applyCurrent(); event.accepted = true; }
                        Keys.onEnterPressed: (event) => { window.applyCurrent(); event.accepted = true; }
                        Keys.onEscapePressed: (event) => { window.closePopup(); event.accepted = true; }
                    }
                    Rectangle {
                        width: s(38); height: s(38); radius: width / 2
                        color: closeMa.containsMouse ? Qt.darker(window.mauve, 1.1) : window.mauve
                        Text { anchors.centerIn: parent; text: "✕"; font.family: "Hack Nerd Font"; font.pixelSize: s(16); color: window.crust }
                        MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.closePopup() }
                    }
                }
            }

            Item {
                width: parent.width
                height: parent.height - s(140)
                clip: true

                ListView {
                    id: listView
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    model: window.filtered
                    spacing: s(16)
                    clip: true
                    snapMode: ListView.SnapOneItem
                    flickDeceleration: 5000
                    leftMargin: s(30); rightMargin: s(30)
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Center)
                    onCountChanged: if (currentIndex > count - 1) currentIndex = Math.max(0, count - 1)

                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property bool isActive: window.activeSlug === modelData.slug
                        readonly property bool isFocus: listView.currentIndex === index
                        readonly property bool hovered: cardMa.containsMouse

                        width: s(470)
                        height: cardCol.implicitHeight + s(32)
                        y: Math.max(0, (listView.height - height) / 2)
                        radius: Theme.radiusLg
                        color: Theme.surfaceContainer
                        border.width: 2
                        border.color: card.isActive ? window.mauve
                            : ((card.isFocus || card.hovered) ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.6) : Theme.outlineVariant)
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Column {
                            id: cardCol
                            x: s(16); y: s(16)
                            width: parent.width - s(32)
                            spacing: s(12)

                            // rich preview drawn at its design size (336x208) and
                            // scaled up to the card width so the content reads big.
                            Item {
                                width: parent.width
                                height: width * 448 / 336
                                Preview {
                                    anchors.centerIn: parent
                                    width: 336; height: 448
                                    scale: parent.width / 336
                                    bgc: card.modelData.background
                                    fgc: card.modelData.foreground
                                    cols: card.modelData.colors || []
                                }
                            }
                            Text {
                                width: parent.width
                                text: card.modelData.name
                                horizontalAlignment: Text.AlignHCenter
                                font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: s(16)
                                color: window.text
                                elide: Text.ElideRight
                            }
                            Grid {
                                anchors.horizontalCenter: parent.horizontalCenter
                                columns: 8; columnSpacing: s(7); rowSpacing: s(9)
                                Repeater {
                                    model: 16
                                    delegate: Rectangle {
                                        required property int index
                                        width: s(24); height: s(24); radius: width / 2
                                        color: (card.modelData.colors && card.modelData.colors[index]) ? card.modelData.colors[index] : Theme.outlineVariant
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.applyPalette(card.modelData.slug)
                        }
                    }
                }

                Rectangle {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: s(40); height: s(40); radius: width / 2
                    color: leftMa.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                    border.width: 1; border.color: Theme.outlineVariant
                    Text { anchors.centerIn: parent; text: "‹"; font.family: "Hack Nerd Font"; font.pixelSize: s(22); color: window.text }
                    MouseArea { id: leftMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: listView.decrementCurrentIndex() }
                }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: s(40); height: s(40); radius: width / 2
                    color: rightMa.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                    border.width: 1; border.color: Theme.outlineVariant
                    Text { anchors.centerIn: parent; text: "›"; font.family: "Hack Nerd Font"; font.pixelSize: s(22); color: window.text }
                    MouseArea { id: rightMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: listView.incrementCurrentIndex() }
                }

                Text {
                    anchors.centerIn: parent
                    visible: window.filtered.length === 0
                    text: window.palettes.length === 0 ? "Loading palettes…" : "No palettes match"
                    font.family: "Hack Nerd Font"; font.pixelSize: s(13)
                    color: window.subtext0
                }
            }

            Row {
                width: parent.width; height: s(18); spacing: s(8)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "‹ › browse  ·  type to filter  ·  Enter / click apply  ·  Esc close"
                    font.family: "Hack Nerd Font"; font.pixelSize: s(11)
                    color: window.subtext0
                }
                Item { width: parent.width - s(430); height: 1 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: window.filtered.length > 0 ? (listView.currentIndex + 1) + " / " + window.filtered.length : ""
                    font.family: "Hack Nerd Font"; font.pixelSize: s(11)
                    color: window.subtext0
                }
            }
        }
    }

    // ── shared window chrome (title bar with traffic dots) ──────────────────
    component Chrome: Item {
        id: ch
        property string title: ""
        property color base: "#11111b"
        property var dots: []
        Rectangle {
            anchors.fill: parent; radius: window.s(7); color: ch.base
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.08)
        }
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: window.s(14); radius: window.s(7); color: Qt.darker(ch.base, 1.12)
        }
        Row {
            anchors { left: parent.left; leftMargin: window.s(6); top: parent.top; topMargin: window.s(4) }
            spacing: window.s(3)
            Repeater {
                model: ch.dots
                delegate: Rectangle { required property var modelData; width: window.s(4); height: window.s(4); radius: width / 2; color: modelData }
            }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: window.s(3) }
            text: ch.title
            font.family: "Hack Nerd Font"; font.pixelSize: window.s(6); color: Qt.rgba(1, 1, 1, 0.5)
        }
    }

    // ── rich 4-window preview (inline; colours from the palette base16) ──────
    component Preview: Item {
        id: pv
        property color bgc: "#1e1e2e"
        property color fgc: "#cdd6f4"
        property var cols: []
        property real pad: window.s(9)
        property real gap: window.s(7)
        property real bar: window.s(14)
        readonly property real mw: (width - pad * 2 - gap) / 2
        readonly property real mh: (height - pad * 2 - gap) / 2
        readonly property string ff: "Hack Nerd Font"
        function c(i) { return (pv.cols && pv.cols[i]) ? pv.cols[i] : pv.fgc; }
        function dk(a) { return Qt.darker(pv.bgc, a); }
        function soft(a) { return Qt.rgba(pv.fgc.r, pv.fgc.g, pv.fgc.b, a); }
        readonly property var dots: [pv.c(1), pv.c(3), pv.c(2)]

        // ── VS Code ────────────────────────────────────────────────────────
        Item {
            x: pv.pad; y: pv.pad; width: pv.mw; height: pv.mh
            Chrome { anchors.fill: parent; title: "app.tsx — vscode"; base: pv.dk(1.12); dots: pv.dots }
            Rectangle { x: 1; y: pv.bar; width: window.s(46); height: parent.height - pv.bar - 1; color: pv.dk(1.2)
                Column { x: window.s(4); y: window.s(18); spacing: window.s(3)
                    Repeater {
                        model: [["index.ts", pv.c(6)], ["theme.ts", pv.c(5)], ["app.tsx", pv.c(2)], ["icon.svg", pv.c(4)]]
                        delegate: Row { required property var modelData; spacing: window.s(3)
                            Rectangle { width: window.s(4); height: window.s(4); radius: window.s(1); color: modelData[1]; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData[0]; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.soft(0.7) } } } } }
            Rectangle { x: window.s(46); y: pv.bar; width: window.s(48); height: window.s(12); color: pv.dk(1.1)
                Text { anchors.centerIn: parent; text: "app.tsx"; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.soft(0.78) } }
            Column { x: window.s(50); y: pv.bar + window.s(15); spacing: window.s(4)
                Repeater {
                    model: [
                        [["import", pv.c(5)], [" { Theme }", pv.c(7)], [" from", pv.c(5)]],
                        [["  \"catppuccin\"", pv.c(2)]],
                        [["const", pv.c(5)], [" colors", pv.c(6)], [" = use()", pv.c(3)]],
                        [["export const", pv.c(5)], [" App", pv.c(6)], [" = () => {", pv.c(7)]],
                        [["  const", pv.c(5)], [" [c]", pv.c(4)], [" = colors", pv.c(6)]],
                        [["  const", pv.c(5)], [" [x]", pv.c(4)], [" = usePalette()", pv.c(6)]],
                        [["  useEffect", pv.c(5)], ["(() => ...)", pv.c(4)]],
                        [["  return", pv.c(5)], [" <Card>", pv.c(3)]],
                        [["    theme", pv.c(6)], ["={c}", pv.c(4)], [" />", pv.c(7)]],
                        [["}", pv.c(7)]],
                        [["// palette ▸ done", pv.soft(0.45)]]
                    ]
                    delegate: Row { required property var modelData; spacing: window.s(2)
                        Repeater { model: modelData
                            delegate: Text { required property var modelData; text: modelData[0]; font.family: pv.ff; font.pixelSize: window.s(5); color: modelData[1] } } } } }
        }

        // ── kitty + xfetch ─────────────────────────────────────────────────
        Item {
            x: pv.pad + pv.mw + pv.gap; y: pv.pad; width: pv.mw; height: pv.mh
            Chrome { anchors.fill: parent; title: "kitty — ~"; base: pv.dk(1.18); dots: pv.dots }
            Text { x: window.s(8); y: pv.bar + window.s(6); text: "user@arch ~ % neofetch"; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.soft(0.7) }
            Rectangle { x: window.s(8); y: pv.bar + window.s(18); width: window.s(26); height: window.s(26); radius: window.s(5); color: pv.c(5)
                Column { anchors.centerIn: parent; spacing: window.s(3)
                    Repeater { model: 3; delegate: Rectangle { width: window.s(13); height: window.s(2.6); radius: 1; color: pv.dk(1.35) } } } }
            Column { x: window.s(40); y: pv.bar + window.s(17); spacing: window.s(1)
                Text { text: "user@arch"; font.family: pv.ff; font.pixelSize: window.s(5.5); color: pv.c(2) }
                Text { text: "OS    Arch Linux"; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.c(6) }
                Text { text: "WM    Hyprland"; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.c(3) }
                Text { text: "Shell zsh"; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.c(4) }
                Text { text: "Uptime 3h 12m"; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.c(1) }
                Text { text: "Pkgs  412"; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.c(5) }
                Text { text: "Colour 256"; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.c(7) } }
            Grid { x: window.s(8); y: pv.bar + window.s(50); columns: 8; columnSpacing: window.s(2); rowSpacing: window.s(2)
                Repeater { model: 16
                    delegate: Rectangle { required property int index; width: window.s(13); height: window.s(7); radius: window.s(1.5); color: pv.c(index) } } }
            Text { x: window.s(8); y: parent.height - window.s(12); text: "cava ▂▃▅▇▆▃▂"; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.soft(0.5) }
        }

        // ── xtop ───────────────────────────────────────────────────────────
        Item {
            x: pv.pad; y: pv.pad + pv.mh + pv.gap; width: pv.mw; height: pv.mh
            Chrome { anchors.fill: parent; title: "xtop — resources"; base: pv.dk(1.12); dots: pv.dots }
            Column { x: window.s(7); y: pv.bar + window.s(6); spacing: window.s(4)
                Repeater {
                    model: [["CPU", pv.c(2), 0.62, "62%"], ["MEM", pv.c(6), 0.48, "48%"], ["GPU", pv.c(3), 0.34, "34%"], ["NET", pv.c(4), 0.22, "2 MB/s"], ["TMP", pv.c(1), 0.15, "46°C"], ["DISK", pv.c(5), 0.31, "31%"], ["LOAD", pv.c(7), 0.12, "0.4"]]
                    delegate: Row { required property var modelData; spacing: window.s(4)
                        Text { text: modelData[0]; width: window.s(20); font.family: pv.ff; font.pixelSize: window.s(5.5); color: pv.c(7); anchors.verticalCenter: parent.verticalCenter }
                        Rectangle { width: pv.mw - window.s(60); height: window.s(5); radius: window.s(2.5); color: pv.dk(1.25); anchors.verticalCenter: parent.verticalCenter
                            Rectangle { width: parent.width * modelData[2]; height: parent.height; radius: parent.radius; color: modelData[1] } }
                        Text { text: modelData[3]; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.soft(0.6); anchors.verticalCenter: parent.verticalCenter } } } }
        }

        // ── nvim ───────────────────────────────────────────────────────────
        Item {
            x: pv.pad + pv.mw + pv.gap; y: pv.pad + pv.mh + pv.gap; width: pv.mw; height: pv.mh
            Chrome { anchors.fill: parent; title: "nvim — config.lua"; base: pv.dk(1.12); dots: pv.dots }
            Column { x: window.s(6); y: pv.bar + window.s(5); spacing: window.s(4)
                Repeater { model: ["1", "2", "3", "4", "5", "6"]
                    delegate: Text { required property var modelData; text: modelData; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.soft(0.4) } } }
            Column { x: window.s(16); y: pv.bar + window.s(5); spacing: window.s(4)
                Repeater {
                    model: [
                        [["local", pv.c(5)], [" M = {}", pv.c(7)]],
                        [["M.theme", pv.c(6)], [" = ", pv.c(7)], ["true", pv.c(4)]],
                        [["vim", pv.c(6)], [".o.foo = ", pv.c(7)], ["set", pv.c(3)]],
                        [["vim", pv.c(6)], [".g.colors = ", pv.c(7)], ["256", pv.c(4)]],
                        [["vim", pv.c(6)], [".opt.number = ", pv.c(7)], ["true", pv.c(4)]],
                        [["vim", pv.c(6)], [".o.termguicolors = ", pv.c(7)], ["true", pv.c(4)]],
                        [["vim", pv.c(6)], [".g.mapleader = ", pv.c(7)], ["\" \"", pv.c(2)]],
                        [["return", pv.c(5)], [" M", pv.c(6)]],
                        [["-- colours ▸", pv.soft(0.45)]],
                        [["require(", pv.c(5)], ["\"theme\"", pv.c(2)], [")", pv.c(5)]],
                        [["M", pv.c(6)], [".setup", pv.c(5)], ["()", pv.c(7)]],
                        [["-- fin", pv.soft(0.45)]]
                    ]
                    delegate: Row { required property var modelData; spacing: window.s(1)
                        Repeater { model: modelData
                            delegate: Text { required property var modelData; text: modelData[0]; font.family: pv.ff; font.pixelSize: window.s(5); color: modelData[1] } } } } }
            Rectangle { x: 1; y: parent.height - window.s(14); width: parent.width - 2; height: window.s(13); color: Qt.darker(pv.dk(1.12), 1.1)
                Rectangle { width: window.s(40); height: parent.height; color: pv.c(5)
                    Text { anchors.centerIn: parent; text: "NORMAL"; font.family: pv.ff; font.pixelSize: window.s(5.5); font.bold: true; color: pv.dk(1.45) } }
                Text { anchors { right: parent.right; rightMargin: window.s(5); verticalCenter: parent.verticalCenter } text: "lua  cfg.lua  12:3"; font.family: pv.ff; font.pixelSize: window.s(5); color: pv.c(7) } }
        }
    }
}
