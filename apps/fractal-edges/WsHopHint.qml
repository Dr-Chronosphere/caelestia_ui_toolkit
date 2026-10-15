import QtQuick
import CaelestiaUI

// Shown while a dragged window waits in the extreme left/right strip of the screen: a glowing edge
// with the target workspace and a fill that shows how long until the window hops.
Item {
    id: root

    property string side: ""            // "prev" (left edge) | "next" (right edge) | "" (hidden)
    property real progress: 0           // 0..1 of the hold time
    property int workspace: 0
    property real stripWidth: 24

    readonly property bool atLeft: side === "prev"
    opacity: side !== "" ? 1 : 0
    visible: opacity > 0.001

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    // the strip itself
    Rectangle {
        x: root.atLeft ? 0 : root.width - width
        width: Math.max(root.stripWidth, 18) + root.progress * 60
        height: root.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: root.atLeft ? 0 : 1
                color: Qt.alpha(Theme.palette.m3primary, 0.35 + 0.35 * root.progress)
            }
            GradientStop {
                position: root.atLeft ? 1 : 0
                color: "transparent"
            }
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.atLeft ? Theme.padding.large : root.width - width - Theme.padding.large
        width: label.implicitWidth + Theme.padding.large * 2
        height: 40
        radius: Theme.rounding.full
        color: Theme.palette.m3primaryContainer

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * root.progress
            radius: parent.radius
            color: Qt.alpha(Theme.palette.m3primary, 0.35)
        }

        StyledText {
            id: label

            anchors.centerIn: parent
            text: (root.atLeft ? "← " : "") + "Workspace " + root.workspace + (root.atLeft ? "" : " →")
            color: Theme.palette.m3onPrimaryContainer
        }
    }
}
