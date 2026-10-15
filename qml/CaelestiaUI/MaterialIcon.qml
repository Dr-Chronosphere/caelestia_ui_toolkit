import QtQuick

// Material Symbols Rounded glyph. Set `text` to the icon name (ligature),
// e.g. "volume_up". Requires the "Material Symbols Rounded" font (installed
// with caelestia).
StyledText {
    id: root

    // 0 = outlined, 1 = filled
    property real fill: 0
    property int grade: Theme.light ? 0 : -25
    property int iconSize: Theme.iconSize.medium

    // Fixed square box so a missing icon font (names render as plain words) cannot
    // blow up layouts; the ligature name is simply clipped.
    width: implicitHeight
    clip: true
    horizontalAlignment: Text.AlignHCenter

    font.family: Theme.iconFamily
    font.pointSize: iconSize
    font.variableAxes: ({
            "FILL": Math.round(fill * 10) / 10,
            "GRAD": grade
        })
}
