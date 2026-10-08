import QtQuick

// Horizontal slider in the shell's style: filled track, gap, handle bar, remaining track.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property bool disabled

    // Fires on user interaction only (not when `value` is set from outside).
    signal moved(real value)

    readonly property bool pressed: mouse.pressed
    readonly property real position: to === from ? 0 : Math.max(0, Math.min(1, (value - from) / (to - from)))

    readonly property color _fg: disabled ? Qt.alpha(Theme.palette.m3onSurface, 0.38) : Theme.palette.m3primary
    readonly property color _bg: disabled ? Qt.alpha(Theme.palette.m3onSurface, 0.1) : Theme.palette.m3secondaryContainer
    readonly property real _gap: Theme.spacing.extraSmall
    readonly property real _handleW: 4
    readonly property real _trackW: Math.max(0, width - _handleW - _gap * 2)

    implicitWidth: 200
    implicitHeight: 16

    StyledRect {
        id: filled

        anchors.verticalCenter: parent.verticalCenter
        width: root._trackW * root.position
        height: root.height
        radius: Theme.rounding.medium
        topRightRadius: Theme.rounding.extraSmall / 2
        bottomRightRadius: Theme.rounding.extraSmall / 2
        color: root._fg

        Behavior on width {
            enabled: !mouse.pressed

            Anim {}
        }
    }

    StyledRect {
        id: handle

        x: filled.width + root._gap
        anchors.verticalCenter: parent.verticalCenter
        width: root._handleW
        height: root.height * (mouse.pressed ? 1.5 : 1.8)
        radius: Theme.rounding.full
        color: root._fg

        Behavior on height {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    StyledRect {
        anchors.left: handle.right
        anchors.leftMargin: root._gap
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.height
        radius: Theme.rounding.medium
        topLeftRadius: Theme.rounding.extraSmall / 2
        bottomLeftRadius: Theme.rounding.extraSmall / 2
        color: root._bg
    }

    MouseArea {
        id: mouse

        function update(x: real): void {
            const p = Math.max(0, Math.min(1, (x - root._handleW / 2) / Math.max(1, root.width - root._handleW)));
            root.moved(root.from + p * (root.to - root.from));
        }

        anchors.fill: parent
        enabled: !root.disabled
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: e => update(e.x)
        onPositionChanged: e => {
            if (pressed)
                update(e.x);
        }
    }
}
