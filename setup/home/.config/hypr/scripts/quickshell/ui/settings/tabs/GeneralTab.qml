// ═══════════════════════════════════════════════════════════════════════════
// GeneralTab — pestaña "General" de SettingsPopup, extraída del Component
// inline para poder compartirla (popup de settings + BarEditor).
//
// `host` = root de SettingsPopup: el cuerpo del tab quedó intacto y usa
// root.s(), root.<rol>, root.highlightedBox, etc. mediante el bloque de
// forwarding de abajo (mismos nombres que el root del popup).
// ═══════════════════════════════════════════════════════════════════════════

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../../core"

Item {
    id: root

    // ════ Forwarding al host (SettingsPopup) ════
    // El cuerpo de este tab quedó intacto y sigue usando root.s(),
    // root.<rol>, root.highlightedBox… vía estos proxies.
    property var host: null
    readonly property color base: host ? host.base : "#363537"
    readonly property color blue: host ? host.blue : "#5ad4e6"
    readonly property color green: host ? host.green : "#7bd88f"
    readonly property color mauve: host ? host.mauve : "#948ae3"
    readonly property color peach: host ? host.peach : "#fd9353"
    readonly property color red: host ? host.red : "#fc618d"
    readonly property color sapphire: host ? host.sapphire : "#5ad4e6"
    readonly property color subtext0: host ? host.subtext0 : "#f7f1ff"
    readonly property color surface0: host ? host.surface0 : "#363537"
    readonly property color surface1: host ? host.surface1 : "#363537"
    readonly property color surface2: host ? host.surface2 : "#363537"
    readonly property color teal: host ? host.teal : "#5ad4e6"
    readonly property color text: host ? host.text : "#f7f1ff"
    function s(val) { return host ? host.s(val) : val; }
    // highlightedBox se escribe desde este tab y desde el host: proxy bidireccional
    // (re-arma el binding tras cada escritura local para no desincronizar).
    property int highlightedBox: host ? host.highlightedBox : -1
    onHighlightedBoxChanged: {
        if (host && host.highlightedBox !== highlightedBox) {
            host.highlightedBox = highlightedBox;
            highlightedBox = Qt.binding(function() { return host ? host.highlightedBox : -1; });
        }
    }

    function clearHighlight() { if (host) host.clearHighlight(); }

    // isLayoutDropdownOpen se escribe desde este tab y desde el host: proxy bidireccional
    // (re-arma el binding tras cada escritura local para no desincronizar).
    property bool isLayoutDropdownOpen: host ? host.isLayoutDropdownOpen : false
    onIsLayoutDropdownOpenChanged: {
        if (host && host.isLayoutDropdownOpen !== isLayoutDropdownOpen) {
            host.isLayoutDropdownOpen = isLayoutDropdownOpen;
            isLayoutDropdownOpen = Qt.binding(function() { return host ? host.isLayoutDropdownOpen : false; });
        }
    }

    function appScaleStep(dir) { if (host) host.appScaleStep(dir); }


    // ════ Movidos desde SettingsPopup.qml (exclusivos de este tab) ════

    property var kbToggleModelArr: [
        { label: "Alt + Shift", val: "grp:alt_shift_toggle" },
        { label: "Win + Space", val: "grp:win_space_toggle" },
        { label: "Caps Lock", val: "grp:caps_toggle" },
        { label: "Ctrl + Shift", val: "grp:ctrl_shift_toggle" },
        { label: "Ctrl + Alt", val: "grp:ctrl_alt_toggle" },
        { label: "Right Alt", val: "grp:toggle" },
        { label: "No Toggle", val: "" }
    ]

    function getKbToggleLabel(val) {
        for (let i = 0; i < root.kbToggleModelArr.length; i++) {
            if (root.kbToggleModelArr[i].val === val) return root.kbToggleModelArr[i].label;
        }
        return "Alt + Shift";
    }

    ListModel {
        id: langModel

        // --- Americas ---
        ListElement { code: "us"; name: "English (US)" }
        ListElement { code: "ca"; name: "English/French (Canada)" }
        ListElement { code: "ca-multix"; name: "Canadian Multilingual" }
        ListElement { code: "latam"; name: "Spanish (Latin America)" }
        ListElement { code: "br"; name: "Portuguese (Brazil)" }
        ListElement { code: "ar"; name: "Arabic (Latin America)" }
        ListElement { code: "bo"; name: "Bolivia" }
        ListElement { code: "cl"; name: "Chile" }
        ListElement { code: "co"; name: "Colombia" }
        ListElement { code: "cr"; name: "Costa Rica" }
        ListElement { code: "cu"; name: "Cuba" }
        ListElement { code: "do"; name: "Dominican Republic" }
        ListElement { code: "ec"; name: "Ecuador" }
        ListElement { code: "sv"; name: "El Salvador" }
        ListElement { code: "gt"; name: "Guatemala" }
        ListElement { code: "hn"; name: "Honduras" }
        ListElement { code: "mx"; name: "Mexico" }
        ListElement { code: "ni"; name: "Nicaragua" }
        ListElement { code: "pa"; name: "Panama" }
        ListElement { code: "py"; name: "Paraguay" }
        ListElement { code: "pe"; name: "Peru" }
        ListElement { code: "pr"; name: "Puerto Rico" }
        ListElement { code: "uy"; name: "Uruguay" }
        ListElement { code: "ve"; name: "Venezuela" }

        // --- Europe (West, Central, & North) ---
        ListElement { code: "gb"; name: "English (UK)" }
        ListElement { code: "ie"; name: "English (Ireland)" }
        ListElement { code: "gd"; name: "Scottish Gaelic" }
        ListElement { code: "cy-gb"; name: "Welsh" }
        ListElement { code: "fr"; name: "French" }
        ListElement { code: "be"; name: "Belgian" }
        ListElement { code: "ch"; name: "Swiss" }
        ListElement { code: "de"; name: "German" }
        ListElement { code: "at"; name: "Austrian" }
        ListElement { code: "nl"; name: "Dutch" }
        ListElement { code: "lu"; name: "Luxembourgish" }
        ListElement { code: "es"; name: "Spanish" }
        ListElement { code: "pt"; name: "Portuguese" }
        ListElement { code: "it"; name: "Italian" }
        ListElement { code: "mt"; name: "Maltese" }
        ListElement { code: "se"; name: "Swedish" }
        ListElement { code: "no"; name: "Norwegian" }
        ListElement { code: "dk"; name: "Danish" }
        ListElement { code: "fi"; name: "Finnish" }
        ListElement { code: "is"; name: "Icelandic" }
        ListElement { code: "fo"; name: "Faroese" }
        ListElement { code: "gl"; name: "Greenlandic" }
        ListElement { code: "pl"; name: "Polish" }
        ListElement { code: "cz"; name: "Czech" }
        ListElement { code: "sk"; name: "Slovak" }
        ListElement { code: "hu"; name: "Hungarian" }
        ListElement { code: "ad"; name: "Andorra" }
        ListElement { code: "mc"; name: "Monaco" }
        ListElement { code: "sm"; name: "San Marino" }
        ListElement { code: "va"; name: "Vatican" }
        ListElement { code: "epo"; name: "Esperanto" }
        ListElement { code: "eu"; name: "Basque" }
        ListElement { code: "ca-fr"; name: "Catalan" }

        // --- Europe (East) & Caucasus ---
        ListElement { code: "ru"; name: "Russian" }
        ListElement { code: "ua"; name: "Ukrainian" }
        ListElement { code: "by"; name: "Belarusian" }
        ListElement { code: "ro"; name: "Romanian" }
        ListElement { code: "bg"; name: "Bulgarian" }
        ListElement { code: "rs"; name: "Serbian" }
        ListElement { code: "hr"; name: "Croatian" }
        ListElement { code: "si"; name: "Slovenian" }
        ListElement { code: "mk"; name: "Macedonian" }
        ListElement { code: "ba"; name: "Bosnian" }
        ListElement { code: "me"; name: "Montenegrin" }
        ListElement { code: "gr"; name: "Greek" }
        ListElement { code: "cy"; name: "Cyprus" }
        ListElement { code: "ee"; name: "Estonian" }
        ListElement { code: "lv"; name: "Latvian" }
        ListElement { code: "lt"; name: "Lithuanian" }
        ListElement { code: "md"; name: "Moldovan" }
        ListElement { code: "am"; name: "Armenian" }
        ListElement { code: "ge"; name: "Georgian" }
        ListElement { code: "az"; name: "Azerbaijani" }
        ListElement { code: "kz"; name: "Kazakh" }
        ListElement { code: "kg"; name: "Kyrgyz" }
        ListElement { code: "tj"; name: "Tajik" }
        ListElement { code: "tm"; name: "Turkmen" }
        ListElement { code: "uz"; name: "Uzbek" }
        ListElement { code: "mn"; name: "Mongolian" }
        ListElement { code: "tat"; name: "Tatar" }
        ListElement { code: "chu"; name: "Chuvash" }
        ListElement { code: "os"; name: "Ossetian" }
        ListElement { code: "udm"; name: "Udmurt" }
        ListElement { code: "kbd"; name: "Kabardian" }
	ListElement { code: "che"; name: "Chechen" }
	ListElement { code: "tr"; name: "Turkish" }

        // --- Asia & Pacific ---
        ListElement { code: "au"; name: "English (Australia)" }
        ListElement { code: "nz"; name: "English (New Zealand)" }
        ListElement { code: "cn"; name: "Chinese" }
        ListElement { code: "jp"; name: "Japanese" }
        ListElement { code: "kr"; name: "Korean" }
        ListElement { code: "tw"; name: "Taiwanese" }
        ListElement { code: "hk"; name: "Hong Kong" }
        ListElement { code: "in"; name: "Indian" }
        ListElement { code: "pk"; name: "Pakistani" }
        ListElement { code: "bd"; name: "Bangla" }
        ListElement { code: "lk"; name: "Sri Lankan" }
        ListElement { code: "np"; name: "Nepali" }
        ListElement { code: "mv"; name: "Maldivian (Dhivehi)" }
        ListElement { code: "bt"; name: "Bhutanese (Dzongkha)" }
        ListElement { code: "af"; name: "Afghan (Pashto/Dari)" }
        ListElement { code: "th"; name: "Thai" }
        ListElement { code: "vn"; name: "Vietnamese" }
        ListElement { code: "la"; name: "Lao" }
        ListElement { code: "mm"; name: "Burmese" }
        ListElement { code: "kh"; name: "Khmer" }
        ListElement { code: "id"; name: "Indonesian" }
        ListElement { code: "my"; name: "Malay" }
        ListElement { code: "ph"; name: "Filipino" }
        ListElement { code: "sg"; name: "Singaporean" }
        ListElement { code: "bn"; name: "Bengali" }
        ListElement { code: "ta"; name: "Tamil" }
        ListElement { code: "te"; name: "Telugu" }
        ListElement { code: "gu"; name: "Gujarati" }
        ListElement { code: "pa"; name: "Punjabi" }
        ListElement { code: "ml"; name: "Malayalam" }
        ListElement { code: "kn"; name: "Kannada" }
        ListElement { code: "or"; name: "Odia" }
        ListElement { code: "as"; name: "Assamese" }
        ListElement { code: "ur"; name: "Urdu" }

        // --- Middle East & North Africa ---
        ListElement { code: "il"; name: "Hebrew" }
        ListElement { code: "ara"; name: "Arabic" }
        ListElement { code: "iq"; name: "Iraqi" }
        ListElement { code: "sy"; name: "Syrian" }
        ListElement { code: "ir"; name: "Persian (Farsi)" }
        ListElement { code: "ma"; name: "Moroccan" }
        ListElement { code: "dz"; name: "Algerian" }
        ListElement { code: "eg"; name: "Egyptian" }
        ListElement { code: "ly"; name: "Libyan" }
        ListElement { code: "tn"; name: "Tunisian" }
        ListElement { code: "sd"; name: "Sudanese" }
        ListElement { code: "lb"; name: "Lebanese" }
        ListElement { code: "jo"; name: "Jordanian" }
        ListElement { code: "ps"; name: "Palestinian" }
        ListElement { code: "sa"; name: "Saudi Arabian" }
        ListElement { code: "kw"; name: "Kuwaiti" }
        ListElement { code: "bh"; name: "Bahraini" }
        ListElement { code: "qa"; name: "Qatari" }
        ListElement { code: "ae"; name: "UAE" }
        ListElement { code: "om"; name: "Omani" }
        ListElement { code: "ye"; name: "Yemeni" }

        // --- Sub-Saharan Africa ---
        ListElement { code: "za"; name: "English (South Africa)" }
        ListElement { code: "ng"; name: "Nigerian" }
        ListElement { code: "et"; name: "Ethiopian" }
        ListElement { code: "sn"; name: "Senegalese" }
        ListElement { code: "ke"; name: "Kenyan" }
        ListElement { code: "tz"; name: "Tanzanian" }
        ListElement { code: "gh"; name: "Ghanaian" }
        ListElement { code: "cm"; name: "Cameroonian" }
        ListElement { code: "ci"; name: "Ivorian" }
        ListElement { code: "ml"; name: "Malian" }
        ListElement { code: "gn"; name: "Guinean" }
        ListElement { code: "cd"; name: "Congolese (DRC)" }
        ListElement { code: "cg"; name: "Congolese (RC)" }
        ListElement { code: "rw"; name: "Rwandan" }
        ListElement { code: "bi"; name: "Burundian" }
        ListElement { code: "ug"; name: "Ugandan" }
        ListElement { code: "zm"; name: "Zambian" }
        ListElement { code: "zw"; name: "Zimbabwean" }
        ListElement { code: "mw"; name: "Malawian" }
        ListElement { code: "mz"; name: "Mozambican" }
        ListElement { code: "ao"; name: "Angolan" }
        ListElement { code: "na"; name: "Namibian" }
        ListElement { code: "bw"; name: "Motswana" }
        ListElement { code: "mg"; name: "Malagasy" }
        ListElement { code: "so"; name: "Somali" }
        ListElement { code: "dj"; name: "Djiboutian" }
        ListElement { code: "er"; name: "Eritrean" }
        ListElement { code: "tg"; name: "Togolese" }
        ListElement { code: "bj"; name: "Beninese" }
        ListElement { code: "bf"; name: "Burkinabe" }
        ListElement { code: "ne"; name: "Nigerien" }
        ListElement { code: "td"; name: "Chadian" }
        ListElement { code: "cf"; name: "Central African" }
        ListElement { code: "gq"; name: "Equatorial Guinean" }
        ListElement { code: "ga"; name: "Gabonese" }

        // --- Alternative Layouts ---
        ListElement { code: "us-intl"; name: "US International" }
        ListElement { code: "dvorak"; name: "US Dvorak" }
        ListElement { code: "colemak"; name: "US Colemak" }
        ListElement { code: "norman"; name: "US Norman" }
        ListElement { code: "workman"; name: "US Workman" }
        ListElement { code: "math"; name: "Mathematics" }
        ListElement { code: "brai"; name: "Braille" }
    }

    ListModel { id: pathSuggestModel }
    ListModel { id: langSearchModel }

    function updateLangSearch(query) {
        langSearchModel.clear();
        let q = query.trim().toLowerCase();
        for (let i = 0; i < langModel.count; i++) {
            let item = langModel.get(i);
            if (q === "" || item.code.toLowerCase().includes(q) || item.name.toLowerCase().includes(q)) {
                langSearchModel.append({ code: item.code, name: item.name });
            }
        }
    }

    Process {
        id: pathSuggestProc
        property string query: ""
        command: ["bash", "-c", "eval ls -dp " + query + "* 2>/dev/null | grep '/$' | head -n 5 || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                pathSuggestModel.clear();
                if (this.text) {
                    let lines = this.text.trim().split('\n');
                    for (let i = 0; i < lines.length; i++) {
                        let line = lines[i];
                        if (line.length > 0) {
                            if (line.endsWith('/')) { line = line.slice(0, -1); }
                            pathSuggestModel.append({ path: line });
                        }
                    }
                }
            }
        }
    }

    // ════ Preview del wallpaper actual ════
    // Misma fuente que la pantalla de bloqueo: el still que deja el picker
    // (qs-wallpaperpicker/scripts/wallpaper-apply), no una caché propia.
    // FileView vigila el enlace: si el fondo cambia en caliente, la preview se
    // recarga sola (wpCacheBust fuerza un source distinto en la Image).
    Caching { id: paths }

    readonly property string currentWallpaperPath: Quickshell.env("HOME") + "/.cache/current_wallpaper"
    property int wpCacheBust: 0

    function openWallpaperPicker() {
        Quickshell.execDetached(["qs", "-p", Quickshell.env("HOME") + "/.config/qs-wallpaperpicker", "ipc", "call", "wallpaper", "toggle"]);
    }

    FileView {
        id: wallpaperWatcher
        path: root.currentWallpaperPath
        watchChanges: true
        onFileChanged: root.wpCacheBust++
    }

    // ════ Cuerpo original del tab ════

    function focusLangInput() { langInput.forceActiveFocus(); }
    function focusWpDirInput() { wpDirInput.forceActiveFocus(); }
    function layoutListIncrementIndex() { layoutListView.incrementCurrentIndex(); }
    function layoutListDecrementIndex() { layoutListView.decrementCurrentIndex(); }
    function acceptLayoutSelection() {
        if (layoutListView.currentIndex >= 0 && layoutListView.currentIndex < root.kbToggleModelArr.length) {
            Config.kbOptions = root.kbToggleModelArr[layoutListView.currentIndex].val;
        }
    }
    function scrollTo(y) {
        let maxY = Math.max(0, generalFlickable.contentHeight - generalFlickable.height);
        generalFlickable.contentY = Math.max(0, Math.min(y - root.s(40), maxY > 0 ? maxY : y));
    }
    function scrollToBox(approxItemY) {
        let viewH = generalFlickable.height;
        let itemTop = approxItemY;
        let itemBottom = approxItemY + root.s(80);
        let curY = generalFlickable.contentY;
        let maxY = Math.max(0, generalFlickable.contentHeight - viewH);
        if (itemTop < curY + root.s(10)) {
            generalFlickable.contentY = Math.max(0, itemTop - root.s(20));
        } else if (itemBottom > curY + viewH - root.s(10)) {
            generalFlickable.contentY = Math.min(maxY, itemBottom - viewH + root.s(20));
        }
    }

    Flickable {
        id: generalFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsMainCol.implicitHeight + root.s(Theme.gapXl)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        MouseArea {
            anchors.fill: parent
            onClicked: root.clearHighlight()
            z: -1
        }

        // Single, top-aligned column: page header + themed section cards.
        // Every card sizes to its content (implicitHeight) — no fillHeight, so
        // there are no stretched-card voids; all content is inset by gapLg and
        // shares one 4dp grid. Each ROW keeps its original highlight index
        // (box2..box7 / boxWall) so SearchOverlay's boxIndex jump still lands
        // on the right control.
        ColumnLayout {
            id: settingsMainCol
            x: root.s(Theme.gapLg)
            y: root.s(Theme.gapLg)
            width: parent.width - root.s(Theme.gapLg) * 2
            spacing: root.s(Theme.gapXl)

            // ── Page header ──────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.s(Theme.gapXs)

                Text {
                    text: "General"
                    font.family: "Hack Nerd Font"
                    font.weight: Font.Black
                    font.pixelSize: root.s(24)
                    color: root.text
                }
                Text {
                    Layout.fillWidth: true
                    text: "Shell scale, keyboard layout switching and the desktop wallpaper source."
                    font.family: "Hack Nerd Font"
                    font.pixelSize: root.s(11)
                    color: root.subtext0
                    wrapMode: Text.WordWrap
                }
            }

            // ═══ Section: Interface ══════════════════════════════════════
            Rectangle {
                id: sectionInterface
                Layout.fillWidth: true
                radius: root.s(Theme.radiusLg)
                color: Theme.surfaceContainerLow
                border.width: 1
                border.color: Theme.outlineVariant
                implicitHeight: innerInterface.implicitHeight + root.s(Theme.gapLg) * 2

                ColumnLayout {
                    id: innerInterface
                    anchors.fill: parent
                    anchors.margins: root.s(Theme.gapLg)
                    spacing: root.s(Theme.gapMd)

                    Text {
                        Layout.fillWidth: true
                        text: "Interface"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.DemiBold
                        font.pixelSize: root.s(13)
                        color: root.text
                    }

                    // ── UI Scale (highlight 0) ──────────────────────────
                    Rectangle {
                        id: box2
                        Layout.fillWidth: true
                        Layout.minimumHeight: root.s(44)
                        radius: root.s(Theme.radiusMd)
                        implicitHeight: col2.implicitHeight + root.s(Theme.gapSm) * 2
                        property bool isActive: root.highlightedBox === 0
                        color: box2.isActive
                            ? Theme.stateLayer(root.sapphire, 0.14)
                            : (uiScaleHover.hovered ? Theme.stateLayer(root.sapphire, Theme.stateHover) : "transparent")
                        border.width: box2.isActive ? 1 : 0
                        border.color: root.sapphire
                        Behavior on color { ColorAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }

                        HoverHandler { id: uiScaleHover }
                        MouseArea { anchors.fill: parent; z: -1; onClicked: root.highlightedBox = 0 }

                        RowLayout {
                            id: col2
                            anchors.fill: parent
                            anchors.topMargin: root.s(Theme.gapSm)
                            anchors.bottomMargin: root.s(Theme.gapSm)
                            spacing: root.s(Theme.gapMd)

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(Theme.gap2xs)
                                Text {
                                    Layout.fillWidth: true
                                    text: "UI Scale"
                                    font.family: "Hack Nerd Font"; font.weight: Font.Medium; font.pixelSize: root.s(12)
                                    color: root.text
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Base size scalar for the shell"
                                    font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                    color: root.subtext0
                                    wrapMode: Text.WordWrap
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(Theme.gapSm)
                                Rectangle {
                                    width: root.s(32); height: root.s(32)
                                    radius: root.s(Theme.radiusFull)
                                    color: sMinusMa.pressed
                                        ? Theme.stateLayer(root.sapphire, Theme.statePress)
                                        : (sMinusMa.containsMouse ? Theme.stateLayer(root.sapphire, Theme.stateHover) : Theme.surfaceContainerHighest)
                                    border.width: 1
                                    border.color: (sMinusMa.containsMouse || sMinusMa.pressed) ? root.sapphire : Theme.outlineVariant
                                    scale: sMinusMa.pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuart } }
                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                    Text {
                                        anchors.centerIn: parent; text: "−"
                                        font.family: "Hack Nerd Font"; font.weight: Font.Medium; font.pixelSize: root.s(15)
                                        color: root.sapphire
                                    }
                                    MouseArea {
                                        id: sMinusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: Config.uiScale = Math.max(0.5, (Config.uiScale - 0.1).toFixed(1))
                                    }
                                }
                                Text {
                                    text: Config.uiScale.toFixed(1) + "x"
                                    font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: root.s(13)
                                    color: root.sapphire
                                    Layout.minimumWidth: root.s(36)
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Rectangle {
                                    width: root.s(32); height: root.s(32)
                                    radius: root.s(Theme.radiusFull)
                                    color: sPlusMa.pressed
                                        ? Theme.stateLayer(root.sapphire, Theme.statePress)
                                        : (sPlusMa.containsMouse ? Theme.stateLayer(root.sapphire, Theme.stateHover) : Theme.surfaceContainerHighest)
                                    border.width: 1
                                    border.color: (sPlusMa.containsMouse || sPlusMa.pressed) ? root.sapphire : Theme.outlineVariant
                                    scale: sPlusMa.pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuart } }
                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                    Text {
                                        anchors.centerIn: parent; text: "+"
                                        font.family: "Hack Nerd Font"; font.weight: Font.Medium; font.pixelSize: root.s(15)
                                        color: root.sapphire
                                    }
                                    MouseArea {
                                        id: sPlusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: Config.uiScale = Math.min(2.0, (Config.uiScale + 0.1).toFixed(1))
                                    }
                                }
                            }
                        }
                    }

                    // ── Workspaces (highlight 4) ────────────────────────
                    Rectangle {
                        id: box6
                        Layout.fillWidth: true
                        Layout.minimumHeight: root.s(44)
                        radius: root.s(Theme.radiusMd)
                        implicitHeight: col6ws.implicitHeight + root.s(Theme.gapSm) * 2
                        property bool isActive: root.highlightedBox === 4
                        color: box6.isActive
                            ? Theme.stateLayer(root.red, 0.14)
                            : (wsHover.hovered ? Theme.stateLayer(root.red, Theme.stateHover) : "transparent")
                        border.width: box6.isActive ? 1 : 0
                        border.color: root.red
                        Behavior on color { ColorAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }

                        HoverHandler { id: wsHover }
                        MouseArea { anchors.fill: parent; z: -1; onClicked: root.highlightedBox = 4 }

                        RowLayout {
                            id: col6ws
                            anchors.fill: parent
                            anchors.topMargin: root.s(Theme.gapSm)
                            anchors.bottomMargin: root.s(Theme.gapSm)
                            spacing: root.s(Theme.gapMd)

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(Theme.gap2xs)
                                Text {
                                    Layout.fillWidth: true
                                    text: "Workspaces"
                                    font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: root.s(12)
                                    color: root.text
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Static count shown in the bar"
                                    font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                    color: root.subtext0
                                    wrapMode: Text.WordWrap
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(Theme.gapSm)
                                Rectangle {
                                    width: root.s(32); height: root.s(32)
                                    radius: root.s(Theme.radiusFull)
                                    color: wsMinusMa.pressed
                                        ? Theme.stateLayer(root.red, Theme.statePress)
                                        : (wsMinusMa.containsMouse ? Theme.stateLayer(root.red, Theme.stateHover) : Theme.surfaceContainerHighest)
                                    border.width: 1
                                    border.color: (wsMinusMa.containsMouse || wsMinusMa.pressed) ? root.red : Theme.outlineVariant
                                    scale: wsMinusMa.pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuart } }
                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                    Text {
                                        anchors.centerIn: parent; text: "−"
                                        font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: root.s(15)
                                        color: root.red
                                    }
                                    MouseArea {
                                        id: wsMinusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: Config.workspaceCount = Math.max(2, Config.workspaceCount - 1)
                                    }
                                }
                                Text {
                                    text: Config.workspaceCount.toString()
                                    font.family: "Hack Nerd Font"; font.weight: Font.Black; font.pixelSize: root.s(14)
                                    color: root.red
                                    Layout.minimumWidth: root.s(36)
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Rectangle {
                                    width: root.s(32); height: root.s(32)
                                    radius: root.s(Theme.radiusFull)
                                    color: wsPlusMa.pressed
                                        ? Theme.stateLayer(root.red, Theme.statePress)
                                        : (wsPlusMa.containsMouse ? Theme.stateLayer(root.red, Theme.stateHover) : Theme.surfaceContainerHighest)
                                    border.width: 1
                                    border.color: (wsPlusMa.containsMouse || wsPlusMa.pressed) ? root.red : Theme.outlineVariant
                                    scale: wsPlusMa.pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuart } }
                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                    Text {
                                        anchors.centerIn: parent; text: "+"
                                        font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: root.s(15)
                                        color: root.red
                                    }
                                    MouseArea {
                                        id: wsPlusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: Config.workspaceCount = Math.min(10, Config.workspaceCount + 1)
                                    }
                                }
                            }
                        }
                    }

                    // ── App scale (highlight 5) ─────────────────────────
                    Rectangle {
                        id: box7
                        Layout.fillWidth: true
                        Layout.minimumHeight: root.s(44)
                        radius: root.s(Theme.radiusMd)
                        implicitHeight: appScaleRow.implicitHeight + root.s(Theme.gapSm) * 2
                        property bool isActive: root.highlightedBox === 5
                        color: box7.isActive
                            ? Theme.stateLayer(root.sapphire, 0.14)
                            : (appScaleHover.hovered ? Theme.stateLayer(root.sapphire, Theme.stateHover) : "transparent")
                        border.width: box7.isActive ? 1 : 0
                        border.color: root.sapphire
                        Behavior on color { ColorAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }

                        HoverHandler { id: appScaleHover }
                        MouseArea { anchors.fill: parent; z: -1; onClicked: root.highlightedBox = 5 }

                        RowLayout {
                            id: appScaleRow
                            anchors.fill: parent
                            anchors.topMargin: root.s(Theme.gapSm)
                            anchors.bottomMargin: root.s(Theme.gapSm)
                            spacing: root.s(Theme.gapMd)

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(Theme.gap2xs)
                                Text {
                                    Layout.fillWidth: true
                                    text: "App scale"
                                    font.family: "Hack Nerd Font"; font.weight: Font.Medium; font.pixelSize: root.s(12)
                                    color: root.text
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "GTK / Electron apps — restart them to apply"
                                    font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                    color: root.subtext0
                                    wrapMode: Text.WordWrap
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(Theme.gapSm)
                                Rectangle {
                                    width: root.s(32); height: root.s(32)
                                    radius: root.s(Theme.radiusFull)
                                    color: asMinusMa.pressed
                                        ? Theme.stateLayer(root.sapphire, Theme.statePress)
                                        : (asMinusMa.containsMouse ? Theme.stateLayer(root.sapphire, Theme.stateHover) : Theme.surfaceContainerHighest)
                                    border.width: 1
                                    border.color: (asMinusMa.containsMouse || asMinusMa.pressed) ? root.sapphire : Theme.outlineVariant
                                    scale: asMinusMa.pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuart } }
                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                    Text {
                                        anchors.centerIn: parent; text: "−"
                                        font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: root.s(15)
                                        color: root.sapphire
                                    }
                                    MouseArea {
                                        id: asMinusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.appScaleStep(-1)
                                    }
                                }
                                Text {
                                    text: Config.appScale.toFixed(2) + "x"
                                    font.family: "Hack Nerd Font"; font.weight: Font.Black; font.pixelSize: root.s(14)
                                    color: root.sapphire
                                    Layout.minimumWidth: root.s(46)
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Rectangle {
                                    width: root.s(32); height: root.s(32)
                                    radius: root.s(Theme.radiusFull)
                                    color: asPlusMa.pressed
                                        ? Theme.stateLayer(root.sapphire, Theme.statePress)
                                        : (asPlusMa.containsMouse ? Theme.stateLayer(root.sapphire, Theme.stateHover) : Theme.surfaceContainerHighest)
                                    border.width: 1
                                    border.color: (asPlusMa.containsMouse || asPlusMa.pressed) ? root.sapphire : Theme.outlineVariant
                                    scale: asPlusMa.pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuart } }
                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                    Text {
                                        anchors.centerIn: parent; text: "+"
                                        font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: root.s(15)
                                        color: root.sapphire
                                    }
                                    MouseArea {
                                        id: asPlusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.appScaleStep(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ═══ Section: Keyboard ═══════════════════════════════════════
            Rectangle {
                id: sectionKeyboard
                Layout.fillWidth: true
                radius: root.s(Theme.radiusLg)
                color: Theme.surfaceContainerLow
                border.width: 1
                border.color: Theme.outlineVariant
                implicitHeight: innerKeyboard.implicitHeight + root.s(Theme.gapLg) * 2

                ColumnLayout {
                    id: innerKeyboard
                    anchors.fill: parent
                    anchors.margins: root.s(Theme.gapLg)
                    spacing: root.s(Theme.gapMd)

                    Text {
                        Layout.fillWidth: true
                        text: "Keyboard"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.DemiBold
                        font.pixelSize: root.s(13)
                        color: root.text
                    }

                    // ── Keyboard layouts (highlight 1) ──────────────────
                    Rectangle {
                        id: box3
                        Layout.fillWidth: true
                        Layout.minimumHeight: root.s(44)
                        radius: root.s(Theme.radiusMd)
                        implicitHeight: col3lang.implicitHeight + root.s(Theme.gapSm) * 2
                        property bool isActive: root.highlightedBox === 1
                        color: box3.isActive
                            ? Theme.stateLayer(root.green, 0.14)
                            : (kbHover.hovered ? Theme.stateLayer(root.green, Theme.stateHover) : "transparent")
                        border.width: box3.isActive ? 1 : 0
                        border.color: root.green
                        Behavior on color { ColorAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }

                        HoverHandler { id: kbHover }
                        MouseArea { anchors.fill: parent; z: -1; onClicked: root.highlightedBox = 1 }

                        RowLayout {
                            id: col3lang
                            anchors.fill: parent
                            anchors.topMargin: root.s(Theme.gapSm)
                            anchors.bottomMargin: root.s(Theme.gapSm)
                            spacing: root.s(Theme.gapMd)

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: root.s(Theme.gap2xs)
                                Text {
                                    Layout.fillWidth: true
                                    text: "Keyboard layouts"
                                    font.family: "Hack Nerd Font"; font.weight: Font.Medium; font.pixelSize: root.s(12)
                                    color: root.text
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Matches hyprland.conf. Click ✖ to remove."
                                    font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                    color: root.subtext0
                                    wrapMode: Text.WordWrap
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: root.s(260)
                                Layout.alignment: Qt.AlignTop
                                spacing: root.s(Theme.gapSm)

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: root.s(Theme.gapXs)
                                    Repeater {
                                        model: Config.language ? Config.language.split(",").filter(x => x.trim() !== "") : []
                                        Rectangle {
                                            width: langChipLayout.implicitWidth + root.s(20); height: root.s(26)
                                            radius: root.s(Theme.radiusFull)
                                            color: chipMa.containsMouse ? Theme.stateLayer(root.red, Theme.stateHover) : Theme.surfaceContainerHigh
                                            border.color: chipMa.containsMouse ? root.red : "transparent"
                                            border.width: 1
                                            scale: chipMa.containsMouse ? 1.05 : 1.0
                                            Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutBack } }
                                            Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                            Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                            RowLayout {
                                                id: langChipLayout; anchors.centerIn: parent; spacing: root.s(Theme.gapXs)
                                                Text {
                                                    text: modelData; font.family: "Hack Nerd Font"; font.weight: Font.Medium; font.pixelSize: root.s(11)
                                                    color: chipMa.containsMouse ? root.red : root.text
                                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                                }
                                                Text {
                                                    text: "✖"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                                    color: chipMa.containsMouse ? root.red : root.subtext0
                                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                                }
                                            }
                                            MouseArea {
                                                id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    let arr = Config.language.split(",").filter(x => x.trim() !== "");
                                                    arr.splice(index, 1);
                                                    Config.language = arr.join(",");
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: root.s(34)
                                    radius: root.s(Theme.radiusSm)
                                    color: Theme.surfaceContainer
                                    border.color: langInput.activeFocus ? root.green : Theme.outlineVariant
                                    border.width: 1
                                    Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                    TextInput {
                                        id: langInput
                                        anchors.fill: parent
                                        anchors.leftMargin: root.s(10); anchors.rightMargin: root.s(10)
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                        color: root.text; clip: true; selectByMouse: true
                                        Keys.onPressed: (event) => {
                                            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                                                if (langSearchModel.count > 0) { langListView.incrementCurrentIndex(); event.accepted = true; }
                                            } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
                                                if (langSearchModel.count > 0) { langListView.decrementCurrentIndex(); event.accepted = true; }
                                            }
                                        }
                                        Keys.onReturnPressed: (event) => langInputAccept(event)
                                        Keys.onEnterPressed: (event) => langInputAccept(event)
                                        function langInputAccept(event) {
                                            if (langSearchModel.count > 0 && langListView.currentIndex >= 0) {
                                                let item = langSearchModel.get(langListView.currentIndex);
                                                let arr = Config.language ? Config.language.split(",").filter(x => x.trim() !== "") : [];
                                                if (!arr.includes(item.code)) { arr.push(item.code); Config.language = arr.join(","); }
                                            }
                                            text = ""; focus = false; event.accepted = true;
                                        }
                                        onActiveFocusChanged: { if (activeFocus) root.updateLangSearch(text); }
                                        onTextChanged: { root.updateLangSearch(text); }
                                        Text {
                                            text: "Search to add..."
                                            color: Qt.alpha(root.subtext0, 0.7)
                                            visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: langInput.activeFocus && langSearchModel.count > 0 ? Math.min(root.s(160), langSearchModel.count * root.s(30) + root.s(8)) : 0
                                    radius: root.s(Theme.radiusSm)
                                    color: Theme.surfaceContainer
                                    border.color: Theme.outlineVariant
                                    border.width: 1
                                    clip: true
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }
                                    ListView {
                                        id: langListView
                                        anchors.fill: parent; anchors.topMargin: root.s(4); anchors.bottomMargin: root.s(4)
                                        model: langSearchModel; interactive: true
                                        opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                                        ScrollBar.vertical: ScrollBar { active: true; policy: ScrollBar.AsNeeded }
                                        delegate: Rectangle {
                                            width: parent.width - root.s(8); height: root.s(30)
                                            anchors.horizontalCenter: parent.horizontalCenter; radius: root.s(Theme.radiusSm)
                                            property bool isHovered: sMa.containsMouse
                                            color: isHovered
                                                ? Theme.stateLayer(root.green, Theme.stateHover)
                                                : (ListView.isCurrentItem ? Theme.stateLayer(root.green, 0.10) : "transparent")
                                            Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: root.s(8); anchors.rightMargin: root.s(8); spacing: root.s(8)
                                                Text { text: model.code; font.family: "Hack Nerd Font"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.text; Behavior on color { ColorAnimation { duration: Theme.durShort } } }
                                                Text { text: model.name; font.family: "Hack Nerd Font"; font.pixelSize: root.s(11); color: Qt.alpha(root.subtext0, 0.7); elide: Text.ElideRight; Layout.fillWidth: true; Behavior on color { ColorAnimation { duration: Theme.durShort } } }
                                            }
                                            MouseArea {
                                                id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    let arr = Config.language ? Config.language.split(",").filter(x => x.trim() !== "") : [];
                                                    if (!arr.includes(model.code)) { arr.push(model.code); Config.language = arr.join(","); }
                                                    langInput.text = ""; langInput.focus = false;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Layout shortcut (highlight 2) ───────────────────
                    Rectangle {
                        id: box4
                        Layout.fillWidth: true
                        Layout.minimumHeight: root.s(44)
                        radius: root.s(Theme.radiusMd)
                        implicitHeight: col4layout.implicitHeight + root.s(Theme.gapSm) * 2
                        property bool isActive: root.highlightedBox === 2
                        color: box4.isActive
                            ? Theme.stateLayer(root.teal, 0.14)
                            : (layoutHover.hovered ? Theme.stateLayer(root.teal, Theme.stateHover) : "transparent")
                        border.width: box4.isActive ? 1 : 0
                        border.color: root.teal
                        Behavior on color { ColorAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }

                        HoverHandler { id: layoutHover }
                        MouseArea { anchors.fill: parent; z: -1; onClicked: root.highlightedBox = 2 }

                        RowLayout {
                            id: col4layout
                            anchors.fill: parent
                            anchors.topMargin: root.s(Theme.gapSm)
                            anchors.bottomMargin: root.s(Theme.gapSm)
                            spacing: root.s(Theme.gapMd)

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: root.s(Theme.gap2xs)
                                Text {
                                    Layout.fillWidth: true
                                    text: "Layout shortcut"
                                    font.family: "Hack Nerd Font"; font.weight: Font.Medium; font.pixelSize: root.s(12)
                                    color: root.text
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Toggle combination"
                                    font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                    color: root.subtext0
                                    wrapMode: Text.WordWrap
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: root.s(260)
                                Layout.alignment: Qt.AlignTop
                                spacing: root.s(Theme.gapXs)

                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: root.s(34)
                                    radius: root.s(Theme.radiusSm)
                                    color: Theme.surfaceContainer
                                    border.color: root.isLayoutDropdownOpen ? root.teal : Theme.outlineVariant
                                    border.width: 1
                                    Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: root.s(10); anchors.rightMargin: root.s(10)
                                        Text {
                                            text: root.getKbToggleLabel(Config.kbOptions)
                                            font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                            color: root.text; Layout.fillWidth: true
                                        }
                                        Text {
                                            text: root.isLayoutDropdownOpen ? "▴" : "▾"; font.pixelSize: root.s(12)
                                            color: root.subtext0
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.isLayoutDropdownOpen = !root.isLayoutDropdownOpen;
                                            if (root.isLayoutDropdownOpen) {
                                                let idx = root.kbToggleModelArr.findIndex(x => x.val === Config.kbOptions);
                                                layoutListView.currentIndex = Math.max(0, idx);
                                            }
                                            root.forceActiveFocus();
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.isLayoutDropdownOpen ? root.kbToggleModelArr.length * root.s(30) + root.s(8) : 0
                                    radius: root.s(Theme.radiusSm)
                                    color: Theme.surfaceContainer
                                    border.color: Theme.outlineVariant
                                    border.width: 1
                                    clip: true
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }
                                    ListView {
                                        id: layoutListView
                                        anchors.fill: parent; anchors.topMargin: root.s(4); anchors.bottomMargin: root.s(4)
                                        model: root.kbToggleModelArr; interactive: false
                                        displayMarginBeginning: 0
                                        displayMarginEnd: 0
                                        opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                                        delegate: Rectangle {
                                            width: parent.width - root.s(8); height: root.s(30)
                                            anchors.horizontalCenter: parent.horizontalCenter; radius: root.s(Theme.radiusSm)
                                            property bool isHovered: toggleMa.containsMouse
                                            color: isHovered
                                                ? Theme.stateLayer(root.teal, Theme.stateHover)
                                                : (ListView.isCurrentItem ? Theme.stateLayer(root.teal, 0.10) : "transparent")
                                            Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: root.s(8); anchors.rightMargin: root.s(8)
                                                Text {
                                                    text: modelData.label; font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                                    color: Config.kbOptions === modelData.val ? root.teal : root.text
                                                    Layout.fillWidth: true
                                                }
                                            }
                                            MouseArea { id: toggleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Config.kbOptions = modelData.val; root.isLayoutDropdownOpen = false; } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ═══ Section: Wallpaper ══════════════════════════════════════
            Rectangle {
                id: sectionWallpaper
                Layout.fillWidth: true
                radius: root.s(Theme.radiusLg)
                color: Theme.surfaceContainerLow
                border.width: 1
                border.color: Theme.outlineVariant
                implicitHeight: innerWallpaper.implicitHeight + root.s(Theme.gapLg) * 2

                ColumnLayout {
                    id: innerWallpaper
                    anchors.fill: parent
                    anchors.margins: root.s(Theme.gapLg)
                    spacing: root.s(Theme.gapMd)

                    Text {
                        Layout.fillWidth: true
                        text: "Wallpaper"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.DemiBold
                        font.pixelSize: root.s(13)
                        color: root.text
                    }

                    // ── Wallpaper directory (highlight 3) ───────────────
                    Rectangle {
                        id: box5
                        Layout.fillWidth: true
                        Layout.minimumHeight: root.s(44)
                        radius: root.s(Theme.radiusMd)
                        implicitHeight: col5wp.implicitHeight + root.s(Theme.gapSm) * 2
                        property bool isActive: root.highlightedBox === 3
                        color: box5.isActive
                            ? Theme.stateLayer(root.mauve, 0.14)
                            : (wpDirHover.hovered ? Theme.stateLayer(root.mauve, Theme.stateHover) : "transparent")
                        border.width: box5.isActive ? 1 : 0
                        border.color: root.mauve
                        Behavior on color { ColorAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }

                        HoverHandler { id: wpDirHover }
                        MouseArea { anchors.fill: parent; z: -1; onClicked: root.highlightedBox = 3 }

                        RowLayout {
                            id: col5wp
                            anchors.fill: parent
                            anchors.topMargin: root.s(Theme.gapSm)
                            anchors.bottomMargin: root.s(Theme.gapSm)
                            spacing: root.s(Theme.gapMd)

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: root.s(Theme.gap2xs)
                                Text {
                                    Layout.fillWidth: true
                                    text: "Wallpaper directory"
                                    font.family: "Hack Nerd Font"; font.weight: Font.Medium; font.pixelSize: root.s(12)
                                    color: root.text
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Absolute source path"
                                    font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                    color: root.subtext0
                                    wrapMode: Text.WordWrap
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: root.s(260)
                                Layout.alignment: Qt.AlignTop
                                spacing: root.s(Theme.gapXs)

                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: root.s(34)
                                    radius: root.s(Theme.radiusSm)
                                    color: Theme.surfaceContainer
                                    border.color: wpDirInput.activeFocus ? root.mauve : Theme.outlineVariant
                                    border.width: 1
                                    Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                    TextInput {
                                        id: wpDirInput
                                        anchors.fill: parent
                                        anchors.leftMargin: root.s(10); anchors.rightMargin: root.s(10)
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: Config.wallpaperDir
                                        font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                        color: root.text; clip: true; selectByMouse: true
                                        Keys.onPressed: (event) => {
                                            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                                                if (pathSuggestModel.count > 0) { wpSuggestListView.incrementCurrentIndex(); event.accepted = true; }
                                            } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
                                                if (pathSuggestModel.count > 0) { wpSuggestListView.decrementCurrentIndex(); event.accepted = true; }
                                            }
                                        }
                                        Keys.onReturnPressed: (event) => wpDirInputAccept(event)
                                        Keys.onEnterPressed: (event) => wpDirInputAccept(event)
                                        function wpDirInputAccept(event) {
                                            if (pathSuggestModel.count > 0 && wpSuggestListView.currentIndex >= 0) {
                                                let item = pathSuggestModel.get(wpSuggestListView.currentIndex);
                                                if (item) { text = item.path; Config.wallpaperDir = text; }
                                            }
                                            pathSuggestModel.clear(); focus = false; event.accepted = true;
                                        }
                                        onActiveFocusChanged: {
                                            if (activeFocus) { pathSuggestProc.query = text; pathSuggestProc.running = false; pathSuggestProc.running = true; }
                                        }
                                        onTextChanged: {
                                            Config.wallpaperDir = text;
                                            if (activeFocus) { pathSuggestProc.query = text; pathSuggestProc.running = false; pathSuggestProc.running = true; }
                                        }
                                        Text {
                                            text: "Enter directory..."
                                            color: Qt.alpha(root.subtext0, 0.7)
                                            visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: wpDirInput.activeFocus && pathSuggestModel.count > 0 ? pathSuggestModel.count * root.s(28) + root.s(8) : 0
                                    radius: root.s(Theme.radiusSm)
                                    color: Theme.surfaceContainer
                                    border.color: Theme.outlineVariant
                                    border.width: 1
                                    clip: true
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }
                                    ListView {
                                        id: wpSuggestListView
                                        anchors.fill: parent; anchors.topMargin: root.s(4); anchors.bottomMargin: root.s(4)
                                        model: pathSuggestModel; interactive: false
                                        displayMarginBeginning: 0
                                        displayMarginEnd: 0
                                        opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                                        delegate: Rectangle {
                                            width: parent.width - root.s(8); height: root.s(28)
                                            anchors.horizontalCenter: parent.horizontalCenter; radius: root.s(Theme.radiusSm)
                                            property bool isHovered: suggestMa.containsMouse
                                            color: isHovered
                                                ? Theme.stateLayer(root.mauve, Theme.stateHover)
                                                : (ListView.isCurrentItem ? Theme.stateLayer(root.mauve, 0.10) : "transparent")
                                            Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter; x: root.s(8)
                                                text: model.path; font.family: "Hack Nerd Font"; font.pixelSize: root.s(10)
                                                color: root.text
                                                elide: Text.ElideMiddle; width: parent.width - root.s(16)
                                            }
                                            MouseArea { id: suggestMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { wpDirInput.text = model.path; pathSuggestModel.clear(); wpDirInput.focus = false; } }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Current wallpaper (highlight 6) ─────────────────
                    Rectangle {
                        id: boxWall
                        Layout.fillWidth: true
                        Layout.minimumHeight: root.s(44)
                        radius: root.s(Theme.radiusMd)
                        implicitHeight: colWall.implicitHeight + root.s(Theme.gapSm) * 2
                        property bool isActive: root.highlightedBox === 6
                        color: boxWall.isActive
                            ? Theme.stateLayer(root.peach, 0.14)
                            : (wallHover.hovered ? Theme.stateLayer(root.peach, Theme.stateHover) : "transparent")
                        border.width: boxWall.isActive ? 1 : 0
                        border.color: root.peach
                        Behavior on color { ColorAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }

                        HoverHandler { id: wallHover }
                        MouseArea { anchors.fill: parent; z: -1; onClicked: root.highlightedBox = 6 }

                        ColumnLayout {
                            id: colWall
                            anchors.fill: parent
                            anchors.topMargin: root.s(Theme.gapSm)
                            anchors.bottomMargin: root.s(Theme.gapSm)
                            spacing: root.s(Theme.gapMd)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(Theme.gapMd)

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: root.s(Theme.gap2xs)
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Wallpaper"
                                        font.family: "Hack Nerd Font"; font.weight: Font.Medium; font.pixelSize: root.s(12)
                                        color: root.text
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Current desktop background"
                                        font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                // Botón de cambio: abre el selector de fondos (qs-wallpaperpicker)
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: root.s(34); height: root.s(34); radius: root.s(Theme.radiusFull)
                                    color: wpChangeMa.pressed
                                        ? Theme.stateLayer(root.peach, Theme.statePress)
                                        : (wpChangeMa.containsMouse ? Theme.stateLayer(root.peach, Theme.stateHover) : Theme.surfaceContainerHighest)
                                    border.color: wpChangeMa.containsMouse ? root.peach : Theme.outlineVariant
                                    border.width: 1
                                    scale: wpChangeMa.pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuart } }
                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                    Text {
                                        anchors.centerIn: parent; text: "󰏫"
                                        font.family: "Hack Nerd Font"; font.pixelSize: root.s(16)
                                        color: root.peach
                                    }
                                    MouseArea {
                                        id: wpChangeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.highlightedBox = 6; root.openWallpaperPicker(); }
                                    }
                                }
                            }

                            // Preview: inset frame (radiusMd) with a rounded alpha
                            // mask so the Image follows the corner radius.
                            Rectangle {
                                id: wpPreviewFrame
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(360)
                                radius: root.s(Theme.radiusMd)
                                color: Theme.surfaceContainer
                                border.color: Theme.outlineVariant
                                border.width: 1

                                Item {
                                    id: wpPreviewLayer
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: wpPreviewMask
                                    }

                                    Image {
                                        id: wpPreviewImage
                                        anchors.fill: parent
                                        source: "file://" + root.currentWallpaperPath + "?v=" + root.wpCacheBust
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: false
                                        visible: status === Image.Ready
                                    }
                                }
                                Rectangle {
                                    id: wpPreviewMask
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: Math.max(0, wpPreviewFrame.radius - 1)
                                    visible: false
                                    layer.enabled: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "No wallpaper set"
                                    visible: wpPreviewImage.status === Image.Error || wpPreviewImage.status === Image.Null
                                    font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                    color: Qt.alpha(root.subtext0, 0.6)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
