import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../core"

// ═══════════════════════════════════════════════════════════════════════════
// FieldCard — card de texto de ancho completo (familia GuidePopup).
//
// Card s(44) r18 alpha(surface0, 0.4) + borde surface1: label s(13) text +
// spacer + TextField estilo card (fondo alpha(surface0, 0.4), radio s(13),
// borde mauve en foco). `previewFont` usa el propio texto como familia (vista
// previa del campo Font). El commit emite edited(text) y la página aplica.
// API: bar / label / value / fieldWidth / maxLength / previewFont / edited().
// ═══════════════════════════════════════════════════════════════════════════

Rectangle {
    id: fld
    property var bar: null
    property string label: ""
    property string value: ""
    property int fieldWidth: 240
    property int maxLength: 32767
    property bool previewFont: false
    property string placeholder: ""
    property color swatch: "transparent"   // small colour dot before the label (a = 0 hides it)
    signal edited(string text)

    height: bar ? bar.s(44) : 44
    radius: bar ? bar.s(Theme.radiusLg) : Theme.radiusLg
    color: !bar ? "transparent" : Theme.surfaceContainerLow
    border.width: 1
    border.color: bar ? Theme.outlineVariant : "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: bar ? bar.s(Theme.gapLg) : Theme.gapLg
        anchors.rightMargin: bar ? bar.s(Theme.gapSm) : Theme.gapSm
        spacing: bar ? bar.s(Theme.gapSm) : Theme.gapSm
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: fld.swatch.a > 0
            width: bar ? bar.s(10) : 10
            height: bar ? bar.s(10) : 10
            radius: bar ? bar.s(Theme.radiusXs) : Theme.radiusXs
            color: fld.swatch
            border.width: 1
            border.color: bar ? Theme.outlineVariant : "transparent"
        }
        Text {
            text: fld.label
            font.family: "Hack Nerd Font"
            font.pixelSize: bar ? bar.s(13) : 13
            color: !bar ? "transparent" : bar.colors.text
            Layout.alignment: Qt.AlignVCenter
        }
        Item { Layout.fillWidth: true; height: 1 }
        TextField {
            id: field
            Layout.preferredWidth: bar ? bar.s(fld.fieldWidth) : fld.fieldWidth
            Layout.preferredHeight: bar ? bar.s(30) : 30
            Layout.alignment: Qt.AlignVCenter
            text: fld.value
            placeholderText: fld.placeholder
            placeholderTextColor: bar ? Qt.alpha(bar.colors.subtext0, 0.55) : "transparent"
            font.family: fld.previewFont && field.text !== "" ? field.text : "Hack Nerd Font"
            font.pixelSize: bar ? bar.s(13) : 13
            color: bar ? bar.colors.text : "transparent"
            selectByMouse: true
            maximumLength: fld.maxLength
            background: Rectangle {
                color: bar ? Theme.surfaceContainer : "transparent"
                radius: bar ? bar.s(Theme.radiusMd) : Theme.radiusMd
                border.width: 1
                border.color: bar ? (field.activeFocus ? bar.colors.mauve : Theme.outlineVariant) : "transparent"
            }
            onEditingFinished: fld.edited(field.text)
        }
    }
}
