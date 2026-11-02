// ═══════════════════════════════════════════════════════════════════════════
// StartupTab — pestaña "Startup" de SettingsPopup, extraída del Component
// inline para poder compartirla (popup de settings + BarEditor).
//
// `host` = root de SettingsPopup: el cuerpo del tab quedó intacto y usa
// root.s(), root.<rol>, root.highlightedBox, etc. mediante el bloque de
// forwarding de abajo (mismos nombres que el root del popup).
//
// Layout (MD3): Flickable → ColumnLayout (page inset gapLg) → cabecera de
// página + UNA card (surfaceContainerLow / outlineVariant / radiusLg) con
// cabecera de sección, las filas de comandos (surfaceContainer / radiusMd) y
// el botón "+ Add" como última fila en flujo normal. Cada fila expande su
// panel de edición EN FLUJO (la altura de la card crece con el contenido).
// ═══════════════════════════════════════════════════════════════════════════

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    // ════ Forwarding al host (SettingsPopup) ════
    // El cuerpo de este tab quedó intacto y sigue usando root.s(),
    // root.<rol>, root.highlightedBox… vía estos proxies.
    property var host: null
    readonly property color base: host ? host.base : "#363537"
    readonly property color green: host ? host.green : "#7bd88f"
    readonly property color overlay0: host ? host.overlay0 : "#f7f1ff"
    readonly property color red: host ? host.red : "#fc618d"
    readonly property color subtext0: host ? host.subtext0 : "#f7f1ff"
    readonly property color surface0: host ? host.surface0 : "#363537"
    readonly property color surface1: host ? host.surface1 : "#363537"
    readonly property color surface2: host ? host.surface2 : "#363537"
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

    property var dynamicStartupModel: host ? host.startupModel : null
    function saveAllStartup() { if (host) host.saveAllStartup(); }


    // ════ Cuerpo original del tab ════

    function scrollTo(y) {
        let maxY = Math.max(0, startupFlickable.contentHeight - startupFlickable.height);
        startupFlickable.contentY = Math.max(0, Math.min(y - root.s(40), maxY > 0 ? maxY : y));
    }
    function scrollToBottom() {
        startupFlickable.contentY = Math.max(0, startupColLayout.implicitHeight - startupFlickable.height + root.s(100));
    }
    function scrollToBox(approxItemY) {
        let viewH = startupFlickable.height;
        let itemTop = approxItemY;
        let itemBottom = approxItemY + root.s(56);
        let curY = startupFlickable.contentY;
        let maxY = Math.max(0, startupFlickable.contentHeight - viewH);
        if (itemTop < curY + root.s(10)) {
            startupFlickable.contentY = Math.max(0, itemTop - root.s(20));
        } else if (itemBottom > curY + viewH - root.s(10)) {
            startupFlickable.contentY = Math.min(maxY, itemBottom - viewH + root.s(20));
        }
    }

    Flickable {
        id: startupFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: startupColLayout.implicitHeight + root.s(Theme.gapXl)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        MouseArea { anchors.fill: parent; onClicked: root.clearHighlight(); z: -1 }

        ColumnLayout {
            id: startupColLayout
            x: root.s(Theme.gapLg)
            y: root.s(Theme.gapLg)
            width: parent.width - root.s(Theme.gapLg) * 2
            spacing: root.s(Theme.gapXl)

            // ── Cabecera de página ────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.s(Theme.gapXs)

                Text {
                    Layout.fillWidth: true
                    text: "Startup"
                    font.family: "Hack Nerd Font"
                    font.weight: Font.Black
                    font.pixelSize: root.s(24)
                    color: root.text
                }
                Text {
                    Layout.fillWidth: true
                    text: "Commands launched once at session start. Saving writes them to ~/.config/hypr/config/user-startup.lua and reloads Hyprland."
                    font.family: "Hack Nerd Font"
                    font.pixelSize: root.s(11)
                    color: root.subtext0
                    wrapMode: Text.WordWrap
                }
            }

            // ── Card de sección: lista de comandos ────────────────────────
            Rectangle {
                id: startupCard
                Layout.fillWidth: true
                radius: root.s(Theme.radiusLg)
                color: Theme.surfaceContainerLow
                border.width: 1
                border.color: Theme.outlineVariant
                implicitHeight: inner.implicitHeight + root.s(Theme.gapLg) * 2

                ColumnLayout {
                    id: inner
                    anchors.fill: parent
                    anchors.margins: root.s(Theme.gapLg)
                    spacing: root.s(Theme.gapMd)

                    Text {
                        Layout.fillWidth: true
                        text: "Autostart commands"
                        font.family: "Hack Nerd Font"
                        font.weight: Font.Medium
                        font.pixelSize: root.s(12)
                        color: root.text
                    }

                    // Filas en FLUJO NORMAL: el Repeater inserta sus items en el
                    // ColumnLayout en su propia posición, así la card mide a
                    // contenido y el panel de edición empuja el resto hacia abajo.
                    Repeater {
                        id: startupListView
                        model: dynamicStartupModel

                        delegate: Rectangle {
                            id: startupRowRect
                            property int outerIndex: index
                            property bool isJumpHighlighted: root.highlightedBox === outerIndex

                            property bool layoutReady: false
                            Component.onCompleted: Qt.callLater(() => layoutReady = true)

                            Layout.fillWidth: true
                            Layout.minimumHeight: root.s(48)
                            implicitHeight: rowCol.implicitHeight + root.s(Theme.gapMd) * 2
                            radius: root.s(Theme.radiusMd)

                            HoverHandler { id: startupRowHover }
                            property bool isHovered: startupRowHover.hovered || model.isEditing || isJumpHighlighted
                            color: isHovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer
                            border.color: isJumpHighlighted
                                ? root.green
                                : (isHovered ? Theme.stateLayer(root.green, 0.5) : Theme.outlineVariant)
                            border.width: isJumpHighlighted ? 2 : 1

                            Behavior on implicitHeight { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutQuart } }
                            Behavior on color { ColorAnimation { duration: Theme.durShort; easing.type: Easing.OutExpo } }
                            Behavior on border.color { ColorAnimation { duration: Theme.durShort; easing.type: Easing.OutExpo } }
                            Behavior on border.width { NumberAnimation { duration: Theme.durShort } }

                            MouseArea { anchors.fill: parent; z: -2; onClicked: root.highlightedBox = outerIndex; }

                            ColumnLayout {
                                id: rowCol
                                anchors.fill: parent
                                anchors.margins: root.s(Theme.gapMd)
                                spacing: root.s(Theme.gapMd)

                                // Comando (izquierda, elide) + controles (derecha)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(Theme.gapSm)

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: model.command !== "" ? model.command : "(empty command)"
                                        font.family: "Hack Nerd Font"
                                        font.pixelSize: root.s(11)
                                        color: model.command !== "" ? root.text : root.overlay0
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        id: startupEditBtn
                                        Layout.preferredWidth: root.s(28)
                                        Layout.preferredHeight: root.s(28)
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: root.s(Theme.radiusFull)
                                        color: model.isEditing
                                            ? root.green
                                            : (startupEditMa.containsMouse ? root.green : Theme.surfaceContainerHighest)
                                        border.width: 1
                                        border.color: model.isEditing
                                            ? root.green
                                            : (startupEditMa.containsMouse ? root.green : Theme.outlineVariant)
                                        Behavior on color { ColorAnimation { duration: Theme.durShort; easing.type: Easing.OutExpo } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: model.isEditing ? "▴" : "󰏫"
                                            font.family: model.isEditing ? "Inter" : "Hack Nerd Font"
                                            font.pixelSize: root.s(13)
                                            color: model.isEditing
                                                ? root.base
                                                : (startupEditMa.containsMouse ? root.base : root.subtext0)
                                            Behavior on color { ColorAnimation { duration: Theme.durShort; easing.type: Easing.OutExpo } }
                                        }
                                        MouseArea {
                                            id: startupEditMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor;
                                            onClicked: {
                                                dynamicStartupModel.setProperty(outerIndex, "isEditing", !model.isEditing);
                                                if (!model.isEditing) root.forceActiveFocus();
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: startupDelRow
                                        Layout.preferredWidth: root.s(28)
                                        Layout.preferredHeight: root.s(28)
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: root.s(Theme.radiusFull)
                                        color: startupDelMa.containsMouse ? root.red : Theme.surfaceContainerHighest
                                        border.color: startupDelMa.containsMouse ? root.red : Theme.outlineVariant
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰆴"
                                            font.family: "Hack Nerd Font"
                                            font.pixelSize: root.s(12)
                                            color: startupDelMa.containsMouse ? root.base : root.red
                                            Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                        }
                                        MouseArea {
                                            id: startupDelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor;
                                            onClicked: { dynamicStartupModel.remove(outerIndex); root.saveAllStartup(); }
                                        }
                                    }
                                }

                                // Panel de edición de la fila (en flujo: al abrirse
                                // crece la fila y, con ella, la card).
                                Item {
                                    id: editPanel
                                    Layout.fillWidth: true
                                    implicitHeight: editPanelCol.implicitHeight
                                    visible: model.isEditing
                                    opacity: model.isEditing ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutExpo } }

                                    ColumnLayout {
                                        id: editPanelCol
                                        anchors.left: parent.left; anchors.right: parent.right
                                        spacing: root.s(Theme.gapSm)

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: root.s(34)
                                            radius: root.s(Theme.radiusMd)
                                            color: Theme.surfaceContainerHigh
                                            border.color: cmdInputFocus.activeFocus ? root.green : Theme.outlineVariant
                                            border.width: 1
                                            Behavior on border.color { ColorAnimation { duration: Theme.durShort } }
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: root.s(Theme.gapMd)
                                                anchors.rightMargin: root.s(Theme.gapMd)
                                                spacing: root.s(Theme.gapSm)
                                                TextInput {
                                                    id: cmdInputFocus
                                                    Layout.fillWidth: true; Layout.fillHeight: true; verticalAlignment: TextInput.AlignVCenter
                                                    font.family: "Hack Nerd Font"; font.pixelSize: root.s(11); color: root.text; clip: true; selectByMouse: true
                                                    text: model.command
                                                    onTextChanged: dynamicStartupModel.setProperty(outerIndex, "command", text)
                                                    Keys.onEscapePressed: { dynamicStartupModel.setProperty(outerIndex, "isEditing", false); root.forceActiveFocus(); }
                                                    Text {
                                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                                        text: "e.g. waybar, dunst, nm-applet"
                                                        color: Qt.alpha(root.subtext0, 0.45); visible: !parent.text && !parent.activeFocus
                                                        font.family: "Hack Nerd Font"; font.pixelSize: root.s(11)
                                                    }
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignRight; spacing: root.s(Theme.gapSm)

                                            Rectangle {
                                                Layout.preferredHeight: root.s(30)
                                                Layout.preferredWidth: startupDoneRow.implicitWidth + root.s(Theme.gapLg)
                                                radius: root.s(Theme.radiusFull)
                                                color: startupDoneMa.containsMouse ? root.green : Theme.surfaceContainerHigh
                                                border.color: startupDoneMa.containsMouse ? root.green : Theme.outlineVariant; border.width: 1
                                                Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                                RowLayout {
                                                    id: startupDoneRow; anchors.centerIn: parent; spacing: root.s(Theme.gapXs)
                                                    Text { text: "󰸞"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(12); color: startupDoneMa.containsMouse ? root.base : root.green; Behavior on color { ColorAnimation { duration: Theme.durShort } } }
                                                    Text { text: "Done"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(10); color: startupDoneMa.containsMouse ? root.base : root.green; Behavior on color { ColorAnimation { duration: Theme.durShort } } }
                                                }
                                                MouseArea {
                                                    id: startupDoneMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        dynamicStartupModel.setProperty(outerIndex, "isEditing", false);
                                                        root.forceActiveFocus();
                                                        root.saveAllStartup();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── "+ Add": última fila de la card, alineada a la derecha,
                    //    en flujo (ya no flota sobre el contenido) ──────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(Theme.gapSm)

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            Layout.preferredHeight: root.s(32)
                            Layout.preferredWidth: startupAddRow.implicitWidth + root.s(Theme.gapLg)
                            radius: root.s(Theme.radiusFull)
                            color: startupAddMa.containsMouse ? root.green : Theme.surfaceContainer
                            border.color: startupAddMa.containsMouse ? root.green : Theme.outlineVariant
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: Theme.durShort } }

                            RowLayout {
                                id: startupAddRow
                                anchors.centerIn: parent
                                spacing: root.s(Theme.gapXs)
                                Text { text: "󰐕"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(12); color: startupAddMa.containsMouse ? root.base : root.green; Behavior on color { ColorAnimation { duration: Theme.durShort } } }
                                Text { text: "Add"; font.family: "Hack Nerd Font"; font.pixelSize: root.s(10); color: startupAddMa.containsMouse ? root.base : root.green; Behavior on color { ColorAnimation { duration: Theme.durShort } } }
                            }

                            MouseArea {
                                id: startupAddMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!dynamicStartupModel) return;
                                    dynamicStartupModel.append({ command: "", isEditing: true });
                                    Qt.callLater(() => root.scrollToBottom());
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
