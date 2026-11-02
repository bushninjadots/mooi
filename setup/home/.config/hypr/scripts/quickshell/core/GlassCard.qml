import QtQuick

// ============================================================================
// GlassCard — theme-free translucent "glass" surface for desktop-widget faces.
//
// Lives in core/ so faces reach it through their existing `import "../../../core"`
// (the implicit sibling-directory import does not resolve under Quickshell's
// component loader). Colors are passed in by the caller (Theme.glassFill /
// Theme.hairline). Renders the base fill, a 1px hairline border and a subtle
// top-down sheen so widgets read as frosted cards against the wallpaper.
// ============================================================================

Rectangle {
    id: card

    property color fill: "transparent"
    property color hairline: "transparent"
    property real cornerRadius: 10

    radius: cornerRadius
    antialiasing: true
    color: fill
    border.width: 1
    border.color: hairline

    // Frosted sheen: soft light at the top, faint shadow at the bottom.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, card.cornerRadius - 1)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.06) }
            GradientStop { position: 0.32; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.07) }
        }
    }
}
