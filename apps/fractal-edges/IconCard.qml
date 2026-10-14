import QtQuick
import CaelestiaUI
import "Lod.js" as Lod

// The icon that covers a tile too small to use (level of detail, like Trellis collapsing small
// windows to icons). Tapping or clicking it asks the host to zoom into that window.
// Pure QtQuick, so it is testable headlessly; the host supplies the icon image URL.
Item {
    id: root

    // Image URL for the app icon; empty or unloadable falls back to a lettered badge.
    property string iconSource
    // The app name (class), shown under the icon when the card is big enough, and the source
    // of the fallback letter.
    property string label
    property string title

    readonly property bool hasIcon: img.status === Image.Ready
    readonly property real iconEdge: Lod.iconSize(width, height)

    // Tap / click: zoom into this window.
    signal activated

    opacity: 0

    // Fade in when the card appears (the tile collapsing to an icon).
    Component.onCompleted: opacity = 1

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    StyledRect {
        anchors.fill: parent
        radius: Theme.rounding.medium
        color: Theme.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: Theme.palette.m3outlineVariant

        StateLayer {
            onClicked: root.activated()
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - Theme.padding.small * 2
            spacing: Theme.spacing.extraSmall

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconEdge
                height: root.iconEdge

                Image {
                    id: img

                    anchors.fill: parent
                    source: root.iconSource
                    sourceSize: Qt.size(128, 128)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: status === Image.Ready
                }

                StyledRect {
                    anchors.fill: parent
                    visible: !root.hasIcon
                    radius: Theme.rounding.full
                    color: Theme.palette.m3primaryContainer

                    StyledText {
                        anchors.centerIn: parent
                        text: Lod.initial(root.label)
                        color: Theme.palette.m3onPrimaryContainer
                        font.pixelSize: Math.round(root.iconEdge * 0.5)
                        font.weight: Font.Medium
                    }
                }
            }

            StyledText {
                visible: Lod.showLabel(root.width, root.height)
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, parent.width)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.label
                font: Theme.label.medium
                color: Theme.palette.m3onSurfaceVariant
            }
        }
    }
}
