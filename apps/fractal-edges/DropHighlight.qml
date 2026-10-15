import QtQuick
import CaelestiaUI

// Where a dragged window will land: a rounded, tinted rectangle that glides between targets.
// Rect is in the overlay window's own coordinates.
Item {
    id: root

    property rect target: Qt.rect(0, 0, 0, 0)
    property bool shown: false
    property string zone: ""

    // Fades with the shell's curve; the rectangle itself moves with the spatial one.
    opacity: shown ? 1 : 0
    visible: opacity > 0.001

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Rectangle {
        x: root.target.x + 4
        y: root.target.y + 4
        width: Math.max(0, root.target.width - 8)
        height: Math.max(0, root.target.height - 8)
        radius: Theme.rounding.large
        color: Qt.alpha(Theme.palette.m3primary, 0.2)
        border.width: 2
        border.color: Qt.alpha(Theme.palette.m3primary, 0.85)

        Behavior on x {
            Anim {
                type: Anim.FastSpatial
            }
        }
        Behavior on y {
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

        MaterialIcon {
            anchors.centerIn: parent
            visible: root.zone === "center"
            text: "swap_horiz"
            iconSize: Theme.iconSize.extraLarge
            color: Theme.palette.m3primary
        }
    }
}
