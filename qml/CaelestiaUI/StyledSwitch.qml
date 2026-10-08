import QtQuick

Item {
    id: root

    property bool checked
    property bool disabled

    signal toggled

    readonly property real _h: 28

    implicitWidth: _h * 1.7
    implicitHeight: _h

    StyledRect {
        anchors.fill: parent
        radius: Theme.rounding.full
        color: {
            if (root.disabled)
                return root.checked ? Qt.alpha(Theme.palette.m3onSurface, 0.12) : Qt.alpha(Theme.palette.m3surfaceContainerHighest, 0.38);
            return root.checked ? Theme.palette.m3primary : Theme.palette.m3surfaceContainerHighest;
        }

        StyledRect {
            readonly property real size: mouse.pressed ? root._h - 4 : root.checked ? root._h - 8 : root._h - 12

            width: size
            height: size
            radius: Theme.rounding.full
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - (root._h - size) / 2 : (root._h - size) / 2
            color: root.disabled ? Qt.alpha(Theme.palette.m3onSurface, 0.38) : root.checked ? Theme.palette.m3onPrimary : Theme.palette.m3outline

            Behavior on x {
                Anim {
                    type: Anim.FastSpatial
                }
            }
            Behavior on width {
                Anim {
                    type: Anim.FastSpatial
                }
            }
            Behavior on height {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: !root.disabled
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.checked = !root.checked;
            root.toggled();
        }
    }
}
