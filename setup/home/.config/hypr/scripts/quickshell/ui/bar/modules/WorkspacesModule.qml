import QtQuick
import Quickshell
import "../../../core"
import "../../../core"
import ".."

// Workspaces — the centerpiece. A horizontal row of workspace pills (top/bottom
// bars) or a vertical stack (left/right bars), with a sliding highlight that
// follows the active workspace in both axes. Each pill shows the workspace
// number, or app icons when occupied.
//
// The active fill normally follows colors.mauve, but palettes may override it
// per-theme through the "workspaceActive" role (see bar/Colors.qml): theme "x"
// uses a golden fill, every other theme keeps mauve.
ModulePill {
    id: mod

    fullHeight: true
    bgRole: "crust"
    bgHoverRole: "crust"
    padH: bar.s(10)
    padV: bar.s(4)

    // Active-workspace fill color: per-palette "workspaceActive" when the
    // palette sets it (alpha > 0), otherwise the standard mauve.
    readonly property color wsActiveFill: {
        let v = (mod.moduleCfg.colors !== undefined) ? mod.moduleCfg.colors["active"] : "";
        if (v !== undefined && v !== "") return (colors[v] !== undefined) ? colors[v] : v;
        return (colors.workspaceActive !== undefined && colors.workspaceActive.a > 0) ? colors.workspaceActive : colors.mauve;
    }
    readonly property color wsActiveText: mod.slotColor("activeText", "crust")
    // Per-workspace fill/marker color slots (personalization; role or #hex).
    readonly property color slotOccupied: mod.slotColor("occupied", "color5")
    readonly property color slotEmpty: mod.slotColor("empty", "base")
    readonly property color slotHover: mod.slotColor("hover", "surface1")
    readonly property color slotMarker: mod.slotColor("marker", "text")
    readonly property color slotMarkerEmpty: mod.slotColor("markerEmpty", "overlay0")
    // How EMPTY workspaces render: "number" | "dot" | "letter" (bar config).
    readonly property string marker: bar.workspacesMarker || "number"
    // Custom character for marker === "custom" (user glyph, e.g. Japanese).
    readonly property string markerChar: (bar.workspacesMarkerText || "").trim() || "•"

    // NOTE: children of a ModulePill land in its contentHost via the default
    // property — do NOT use `content: Item {...}` (the alias-to-data assignment
    // silently drops the item, collapsing the pill to its padding).
    Item {
        id: wsContent
        width: mod.compact ? bar.pillWidth : wsFlowH.implicitWidth
        height: mod.compact ? wsFlowV.implicitHeight : bar.pillHeight

        // --- sliding active highlight (mauve) ----------------------------------
        Rectangle {
            id: activeHighlight
            radius: bar.pillRadius(mod.compact ? bar.pillWidth : bar.s(32))
            color: mod.wsActiveFill
            z: 0

            property int curIdx: bar.wsModel.activeIndex
            property int pillCount: mod.compact ? wsRepeaterV.count : wsRepeaterH.count
            property var activePill: (curIdx >= 0 && curIdx < pillCount)
                ? (mod.compact ? wsRepeaterV.itemAt(curIdx) : wsRepeaterH.itemAt(curIdx))
                : null

            property real targetL: activePill ? (mod.compact ? bar.s(4) : activePill.x) : 0
            property real targetT: activePill ? (mod.compact ? activePill.y : bar.s(6)) : 0
            property real targetW: activePill ? (mod.compact ? bar.pillWidth - bar.s(8) : activePill.width) : bar.s(32)
            property real targetH: activePill ? (mod.compact ? activePill.height : bar.s(32)) : bar.s(32)

            property real actualL: targetL
            property real actualT: targetT
            property real actualW: targetW
            property real actualH: targetH

            Behavior on actualL { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
            Behavior on actualT { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
            Behavior on actualW { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
            Behavior on actualH { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

            x: actualL; y: actualT; width: actualW; height: actualH
        }

        Row {
            id: wsFlowH
            visible: mod.horizontal
            z: 1
            spacing: bar.s(8)
            Repeater { id: wsRepeaterH; model: bar.wsModel; delegate: wsDelegate }
        }

        Column {
            id: wsFlowV
            visible: mod.compact
            z: 1
            spacing: bar.s(8)
            Repeater { id: wsRepeaterV; model: bar.wsModel; delegate: wsDelegate }
        }
    }

    Component {
        id: wsDelegate
        Rectangle {
            id: wsPill

            // `index` + `model.*` come from the Repeater context.
            property bool isLimited: !mod.compact && bar.isSettingsOpen && bar.isMediaActive && index >= 6
            visible: !isLimited

            property bool isHovered: wsMouse.containsMouse
            property string stateLabel: model.wsState
            property string wsName: model.wsId
            property int wsIndex: index

            readonly property var appClassList: (model.wsClasses || "") !== "" ? model.wsClasses.split(",") : []
            readonly property bool hasManyIcons: appClassList.length > 3
            // Vertical bars: how many glyphs fit across the pill. At least one
            // slot is kept so an occupied workspace never falls back to the dot
            // marker, even with a thin bar.
            readonly property int compactIconSlots: Math.max(1, Math.floor((bar.pillWidth - bar.s(8)) / (bar.s(12) + bar.s(2))))
            readonly property int maxShowIcons: mod.compact
                ? Math.min(appClassList.length, compactIconSlots)
                : (hasManyIcons ? 2 : Math.min(appClassList.length, 3))
            readonly property bool showIcons: appIconList.length > 0
            readonly property var appIconList: {
                var icons = [];
                for (var i = 0; i < appClassList.length && i < maxShowIcons; i++) icons.push(classIcon(appClassList[i]));
                return icons;
            }

            function classIcon(cls) {
                var c = String(cls).toLowerCase();
                // class -> Nerd Font glyph. Every codepoint is validated
                // against the Hack Nerd Font coverage (no tofu); reverse-DNS
                // classes are listed explicitly.
                var map = {
                    // Terminals
                    "kitty": "", "konsole": "", "gnome-terminal": "", "xfce4-terminal": "",
                    "tilix": "", "terminator": "", "guake": "", "yakuake": "",
                    "urxvt": "", "rxvt-unicode": "", "xterm": "", "st": "",
                    "st-256color": "", "alacritty": "", "foot": "", "footclient": "",
                    "ghostty": "", "wezterm": "", "org.wezfurlong.wezterm": "", "warp-terminal": "",
                    "tabby": "", "hyper": "", "com.raggesilver.blackbox": "", "blackbox": "",
                    "kgx": "", "console": "",
                    // Browsers
                    "firefox": "", "firefoxdeveloperedition": "", "firefox-esr": "", "librewolf": "",
                    "floorp": "", "waterfox": "", "tor-browser": "", "qutebrowser": "",
                    "zen": "", "zen-browser": "",
                    // Chromium browsers
                    "chromium": "", "chromium-browser": "", "ungoogled-chromium": "", "google-chrome": "",
                    "google-chrome-stable": "", "microsoft-edge": "", "microsoft-edge-stable": "", "msedge": "",
                    "vivaldi-stable": "", "vivaldi": "", "brave": "", "brave-browser": "",
                    "brave-browser-beta": "", "brave-browser-nightly": "", "brave-beta": "",
                    // Web (GTK/Qt)
                    "epiphany": "󰖟", "org.gnome.epiphany": "󰖟", "falkon": "󰖟", "org.kde.falkon": "󰖟",
                    "konqueror": "󰖟",
                    // Editors
                    "sublime_text": "", "sublime": "", "subl": "", "subl3": "",
                    // Editors
                    "emacs": "",
                    // Editors
                    "neovide": "", "nvim-qt": "", "gvim": "", "vimr": "",
                    // Editors
                    "zed": "", "dev.zed.zed": "", "zeditor": "", "helix": "",
                    "hx": "", "lapce": "", "cursor": "", "windsurf": "",
                    "geany": "", "kate": "", "gedit": "", "org.gnome.gedit": "",
                    "gnome-text-editor": "", "org.gnome.texteditor": "", "gnome-builder": "", "org.gnome.builder": "",
                    "eclipse": "", "netbeans": "", "code": "", "code-oss": "",
                    "code-insiders": "", "codium": "", "vscodium": "", "visual-studio-code": "",
                    "vscode": "",
                    // JetBrains IDEs
                    "jetbrains-idea": "", "idea": "", "intellij": "", "pycharm": "",
                    "webstorm": "", "clion": "", "goland": "", "rider": "",
                    "rustrover": "", "datagrip": "", "phpstorm": "", "fleet": "",
                    "jetbrains-toolbox": "", "aqua": "", "mps": "",
                    // Android
                    "android-studio": "", "studio": "",
                    // Python
                    "thonny": "", "spyder": "", "idle": "", "idle3": "",
                    "jupyter": "", "jupyter-notebook": "", "python": "",
                    // Game engines
                    "unity": "", "unityhub": "",
                    // Game engines
                    "godot": "", "godot_editor": "", "godot-engine": "",
                    // Electron apps
                    "electron": "",
                    // API clients
                    "postman": "", "insomnia": "", "bruno": "", "hoppscotch": "",
                    "postwoman": "", "apifox": "",
                    // Databases
                    "dbeaver": "󰆼", "dbeaver-ce": "󰆼", "pgadmin4": "󰆼", "pgadmin": "󰆼",
                    "mysql-workbench": "󰆼", "mongodb-compass": "󰆼", "redisinsight": "󰆼", "sqlitebrowser": "󰆼",
                    "org.sqlitebrowser.sqlitebrowser": "󰆼", "navicat": "󰆼", "beekeeper-studio": "󰆼", "tableplus": "󰆼",
                    // Containers
                    "docker-desktop": "", "lazydocker": "", "podman-desktop": "", "rancher-desktop": "",
                    // Remote/VMs
                    "remmina": "", "org.remmina.remmina": "", "virt-manager": "", "org.virt_manager.virt-manager": "",
                    "gnome-boxes": "", "org.gnome.boxes": "", "virtualbox": "", "virtualboxvm": "",
                    "qemu": "", "qemu-system-x86_64": "", "vinagre": "",
                    // Transfer
                    "filezilla": "", "termius": "", "cyberduck": "", "winscp": "",
                    // Network
                    "wireshark": "", "org.wireshark.wireshark": "", "netsniff-ng": "", "ettercap": "",
                    // Security
                    "burpsuite": "", "burp": "", "owasp-zap": "", "zaproxy": "",
                    "jd-gui": "", "ghidra": "", "ida": "", "ida64": "",
                    "radare2": "", "cutter": "",
                    // Git
                    "gitkraken": "",
                    // Git
                    "meld": "", "org.gnome.meld": "",
                    // Git
                    "git-cola": "", "gitg": "", "ungit": "", "gitbutler": "",
                    "gitbutlerapp": "",
                    // Docs
                    "zeal": "", "devdocs": "", "org.zealdocs.zeal": "", "obsidian": "",
                    "md.obsidian": "", "logseq": "", "com.logseq.logseq": "", "zotero": "",
                    "zotero-bin": "", "calibre": "", "calibre-ebook-viewer": "", "foliate": "",
                    "com.github.johnfactotum.foliate": "",
                    // Notes
                    "joplin": "󰠮", "app.joplin": "󰠮", "net.cozic.joplin_desktop": "󰠮", "siyuan": "󰠮",
                    "zettlr": "󰠮", "qownnotes": "󰠮",
                    // Markdown
                    "typora": "", "marktext": "", "ghostwriter": "", "apostrophe": "",
                    "retext": "",
                    // Passwords
                    "keepassxc": "󰌆", "org.keepassxc.keepassxc": "󰌆", "bitwarden": "󰌆", "1password": "󰌆",
                    "seahorse": "󰌆", "gcr-prompter": "󰌆", "gcr-viewer": "󰌆",
                    // Disks
                    "gparted": "󰋊", "gnome-disks": "󰋊", "org.gnome.diskutility": "󰋊", "baobab": "󰋊",
                    "org.gnome.baobab": "󰋊", "timeshift": "󰋊", "backintime-qt": "󰋊", "org.kde.partitionmanager": "󰋊",
                    // Qt
                    "qt5ct": "", "qt6ct": "", "qtcreator": "", "designer": "",
                    "assistant": "", "linguist": "", "qdbusviewer": "",
                    // GPU
                    "nvidia-settings": "", "corectrl": "", "lact": "",
                    // Screenshot
                    "satty": "", "com.gabm.satty": "", "flameshot": "", "org.flameshot.flameshot": "",
                    "spectacle": "", "org.kde.spectacle": "", "xfce4-screenshooter": "", "gnome-screenshot": "",
                    // Audio
                    "qtractor": "", "ardour": "", "ardour7": "", "lmms": "",
                    "reaper": "", "bitwig": "", "carla": "", "renoise": "",
                    "mixxx": "",
                    // Audio
                    "pavucontrol": "", "org.pulseaudio.pavucontrol": "", "easyeffects": "", "com.github.wwmm.easyeffects": "",
                    "qpwgraph": "", "helvum": "", "org.pipewire.helvum": "",
                    // Bluetooth
                    "blueman-manager": "", "blueman-adapters": "", "bluetooth-manager": "",
                    // Calculator
                    "kcalc": "", "galculator": "", "gnome-calculator": "", "org.gnome.calculator": "",
                    "qalculate-qt": "", "qalculate-gtk": "", "speedcrunch": "",
                    // Archives
                    "ark": "", "org.kde.ark": "", "file-roller": "", "org.gnome.file-roller": "",
                    "engrampa": "", "xarchiver": "",
                    // File managers
                    "nautilus": "", "org.gnome.nautilus": "", "org.gnome.files": "", "gnome-files": "",
                    "files": "", "nemo": "", "org.kde.dolphin": "", "dolphin": "",
                    "thunar": "", "pcmanfm": "", "pcmanfm-qt": "", "caja": "",
                    "krusader": "", "doublecmd": "", "double-commander": "", "mc": "",
                    "ranger": "", "nnn": "", "yazi": "", "lf": "",
                    "lfmanager": "", "spacefm": "", "sunflower": "",
                    // System
                    "mission-center": "", "io.missioncenter.missioncenter": "", "gnome-system-monitor": "", "org.gnome.systemmonitor": "",
                    "resources": "", "plasma-systemmonitor": "", "qps": "", "ksysguard": "",
                    "org.kde.plasma-systemmonitor": "", "system-monitor": "",
                    // Download
                    "qbittorrent": "", "org.qbittorrent.qbittorrent": "", "transmission": "", "transmission-gtk": "",
                    "deluge": "", "fragments": "", "nicotine": "",
                    // Sync
                    "syncthing": "󰓦", "syncthing-gtk": "󰓦", "localsend": "󰓦", "org.localsend.localsend_app": "󰓦",
                    "kdeconnect": "󰓦", "kdeconnect-app": "󰓦", "warpinator": "󰓦",
                    // Settings
                    "systemsettings": "", "kcmshell6": "", "kcmshell5": "", "gnome-control-center": "",
                    "org.gnome.settings": "", "gnome-tweaks": "", "org.gnome.tweaks": "", "xfce4-settings-manager": "",
                    // Launchers
                    "rofi": "", "rofi-theme-selector": "", "wofi": "", "fuzzel": "",
                    "anyrun": "", "ulauncher": "", "albert": "",
                    // PDF
                    "okular": "", "org.kde.okular": "", "xpdf": "", "mupdf": "",
                    "zathura": "",
                    // Office
                    "onlyoffice": "", "onlyoffice-desktopeditors": "", "wps": "", "wpp": "",
                    "et": "", "lowriter": "", "localc": "", "loimpress": "",
                    "libreoffice": "",
                    // Media play
                    "mpv": "", "io.mpv.mpv": "", "celluloid": "", "io.github.celluloid_player.celluloid": "",
                    "smplayer": "", "parole": "", "strawberry": "", "org.strawberrymusicplayer.strawberry": "",
                    "elisa": "", "org.kde.elisa": "", "rhythmbox": "", "org.gnome.rhythmbox": "",
                    "deadbeef": "", "audacious": "", "vlc": "", "org.videolan.vlc": "",
                    // Video
                    "zoom": "", "us.zoom.zoom": "", "obs": "", "obs-studio": "",
                    "com.obsproject.studio": "", "kdenlive": "", "org.kde.kdenlive": "", "shotcut": "",
                    "openshot": "", "handbrake": "", "fr.handbrake.handbrake": "", "kamoso": "",
                    // Creative
                    "blender": "", "org.blender.blender": "",
                    // Creative
                    "krita": "󰃣", "org.kde.krita": "󰃣", "mypaint": "󰃣", "pinta": "󰃣",
                    "gimp": "󰃣", "org.gimp.gimp": "󰃣", "inkscape": "󰃣", "org.inkscape.inkscape": "󰃣",
                    // Images
                    "darktable": "󰋩", "org.darktable.darktable": "󰋩", "rawtherapee": "󰋩", "gthumb": "󰋩",
                    "eog": "󰋩", "org.gnome.eog": "󰋩", "loupe": "󰋩", "org.gnome.loupe": "󰋩",
                    "ristretto": "󰋩", "feh": "󰋩", "imv": "󰋩", "gwenview": "󰋩",
                    "org.kde.gwenview": "󰋩",
                    // Audio edit
                    "audacity": "", "org.audacityteam.audacity": "", "tenacity": "", "com.github.tenacityteam.tenacity": "",
                    // Chat
                    "telegram-desktop": "", "org.telegram.desktop": "", "telegramdesktop": "",
                    // Chat
                    "signal": "", "signal-desktop": "", "org.signal.signal": "", "element": "",
                    "im.riot.element": "", "io.element.element": "", "cinny": "", "io.cinny.cinny": "",
                    "session": "",
                    // Chat
                    "teams": "󰊻", "microsoft-teams": "󰊻", "teams-for-linux": "󰊻",
                    // Mail
                    "thunderbird": "", "org.mozilla.thunderbird": "", "betterbird": "", "eu.betterbird.betterbird": "",
                    "geary": "", "org.gnome.geary": "", "evolution": "", "org.gnome.evolution": "",
                    // Discord clients
                    "discord": "", "vesktop": "", "dev.vencord.vesktop": "", "equibop": "",
                    "org.equibop.equibop": "", "discordcanary": "",
                    // Gaming
                    "steam": "", "steamwebhelper": "", "lutris": "", "net.lutris.lutris": "",
                    "heroic": "", "com.heroicgameslauncher.hgl": "", "retroarch": "", "org.libretro.retroarch": "",
                    "dolphin-emu": "", "org.dolphin_emu.dolphin_emu": "", "ryujinx": "", "org.ryujinx.ryujinx": "",
                    "ppsspp": "", "duckstation": "", "pcsx2": "",
                    // Minecraft
                    "prismlauncher": "", "org.prismlauncher.prismlauncher": "", "minecraft-launcher": "", "multimc": "",
                    "org.multimc.multimc": "",
                    // Wine
                    "bottles": "󰡔", "com.usebottles.bottles": "󰡔",
                    // AI
                    "chatgpt": "", "jan": "", "jan-ai": "", "lm-studio": "",
                    "lmstudio": "", "gpt4all": "", "anythingllm": "",
                    "": ""
                };
                // Explicit map wins; otherwise a conservative file-manager
                // heuristic (folder glyph) for unmapped classes. "dolphin"
                // is deliberately excluded so dolphin-emu keeps its explicit
                // gaming glyph above; everything else keeps the "?" fallback.
                if (map[c]) return map[c];
                if (c.indexOf("nautilus") !== -1 || c.indexOf("folder") !== -1
                    || c.indexOf("explorer") !== -1 || c.indexOf("file-manager") !== -1
                    || c.indexOf("filemanager") !== -1) return "";
                return "\uF128";
            }

            width: mod.compact
                ? bar.pillWidth - bar.s(8)
                : (appIconList.length > 0 ? bar.s(24) + appIconList.length * bar.s(16) + (hasManyIcons ? bar.s(18) : 0)
                    : (mod.marker === "dot" ? bar.s(20) : (mod.marker === "letter" || mod.marker === "custom" ? bar.s(28) : bar.s(36))))
            height: mod.compact ? bar.s(30) : bar.s(36)
            radius: bar.pillRadius(mod.compact ? bar.pillWidth : bar.s(36))

            color: stateLabel === "active" ? "transparent"
                : (bar.pillBg
                    ? (isHovered ? Qt.rgba(mod.slotHover.r, mod.slotHover.g, mod.slotHover.b, bar.pillSolid ? 1.0 : 0.6)
                        : (stateLabel === "occupied" ? Qt.rgba(mod.slotOccupied.r, mod.slotOccupied.g, mod.slotOccupied.b, bar.pillSolid ? 1.0 : 0.4)
                            : Qt.rgba(mod.slotEmpty.r, mod.slotEmpty.g, mod.slotEmpty.b, bar.pillSolid ? 1.0 : 0.4)))
                    : (isHovered ? Qt.rgba(mod.slotHover.r, mod.slotHover.g, mod.slotHover.b, 0.2)
                        : Qt.rgba(mod.slotOccupied.r, mod.slotOccupied.g, mod.slotOccupied.b, 0.3)))

            scale: isHovered && stateLabel !== "active" ? 1.08 : 1.0
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

            Item {
                anchors.fill: parent

                Item {
                    anchors.centerIn: parent
                    // Empty workspace marker (configurable: number/dot/letter).
                    // Occupied workspaces keep the app-icon row below; the
                    // number text only appears when there is nothing else.
                    visible: wsPill.appIconList.length === 0

                    readonly property color markerColor: index === bar.wsModel.activeIndex ? mod.wsActiveText
                        : (wsPill.isHovered ? mod.slotMarker : (wsPill.stateLabel === "occupied" ? mod.slotMarker : mod.slotMarkerEmpty))

                    // number / letter / custom-character marker
                    Text {
                        anchors.centerIn: parent
                        visible: mod.marker !== "dot"
                        text: mod.marker === "letter" ? String.fromCharCode(65 + wsPill.wsIndex)
                            : mod.marker === "custom" ? mod.markerChar
                            : wsPill.wsName
                        font.family: bar.fontFamily
                        font.pixelSize: mod.compact ? bar.s(13) : bar.s(18)
                        font.weight: wsPill.stateLabel === "active" ? Font.Black : (wsPill.stateLabel === "occupied" ? Font.Bold : Font.Medium)
                        color: parent.markerColor
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }
                    // dot marker for empty workspaces
                    Rectangle {
                        anchors.centerIn: parent
                        visible: mod.marker === "dot"
                        width: mod.compact ? bar.s(6) : bar.s(9)
                        height: width
                        radius: width / 2
                        color: parent.markerColor
                        Behavior on color { ColorAnimation { duration: 250 } }
                        scale: wsPill.isHovered ? 1.35 : 1.0
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: bar.s(2)
                    visible: wsPill.showIcons
                    Repeater {
                        model: wsPill.appIconList
                        delegate: Text {
                            text: modelData
                            font.family: bar.fontFamily
                            // Vertical pills scale the glyph down to the pill
                            // width so a thin bar keeps at least one icon inside.
                            font.pixelSize: mod.compact
                                ? Math.min(bar.s(12), Math.max(bar.s(8), wsPill.width - bar.s(2)))
                                : bar.s(12)
                            color: wsPill.wsIndex === bar.wsModel.activeIndex ? mod.wsActiveText : mod.slotMarker
                        }
                    }
                    Text {
                        // Horizontal bars show the overflow count; a vertical
                        // pill only fits a compact "+".
                        text: mod.compact
                            ? (wsPill.appClassList.length > wsPill.appIconList.length ? "+" : "")
                            : (wsPill.hasManyIcons ? "+" + (wsPill.appClassList.length - 2) : "")
                        font.family: bar.fontFamily
                        font.pixelSize: bar.s(10)
                        font.weight: Font.Black
                        color: index === bar.wsModel.activeIndex ? mod.wsActiveText : mod.slotMarkerEmpty
                        visible: text !== ""
                    }
                }
            }

            MouseArea {
                id: wsMouse
                hoverEnabled: true
                anchors.fill: parent
                onClicked: Compositor.switchWorkspace(wsPill.wsName)
            }
        }
    }
}
