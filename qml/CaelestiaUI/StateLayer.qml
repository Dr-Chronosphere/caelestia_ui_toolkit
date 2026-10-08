import QtQuick

// Hover/press overlay (Material "state layer"). Fill a clickable parent with it;
// it picks up the parent's radius automatically.
MouseArea {
    id: root

    property bool disabled
    property color color: Theme.palette.m3onSurface
    property real radius: parent?.radius ?? 0
    property bool manualHover

    anchors.fill: parent
    enabled: !disabled
    hoverEnabled: true
    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.color
        opacity: root.pressed ? 0.1 : (root.containsMouse || root.manualHover) ? 0.08 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
