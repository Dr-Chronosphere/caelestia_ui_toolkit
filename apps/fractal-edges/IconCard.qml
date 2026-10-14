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

    // Target opacity from how far below the size threshold the tile is (Lod.alphaFor): the card
    // fades in as its tile shrinks and out as it grows.
    property real alpha: 1
    // False while the card fades out because its tile grew (or the window closed).
    property bool shown: true
    // Ease opacity changes; false makes it follow `alpha` immediately (during a drag).
    property bool smooth: true
    // Tint opacity of the card's backing. The host blurs what is behind the card (a layer rule),
    // so the backing is translucent; use 1 for an opaque card when blur is off.
    property real tint: 0.62
    // Corner radius; negative uses the theme's medium rounding.
    property real cornerRadius: -1

    readonly property bool hasIcon: img.status === Image.Ready
    readonly property real iconEdge: Lod.iconSize(width, height)
    // Faint cards let taps through (the host also drops the window's input region).
    readonly property bool interactive: shown && alpha > 0.3

    // Tap / click: zoom into this window.
    signal activated

    // Fade with the shell's own effects curve. A new card starts at 0 and fades in.
    property bool ready: false
    Component.onCompleted: ready = true

    opacity: (ready && shown) ? alpha : 0

    Behavior on opacity {
        enabled: root.smooth

        Anim {
            type: Anim.DefaultEffects
        }
    }

    StyledRect {
        anchors.fill: parent
        radius: root.cornerRadius >= 0 ? root.cornerRadius : Theme.rounding.medium
        color: Qt.alpha(Theme.palette.m3surfaceContainerHigh, root.tint)
        border.width: 1
        border.color: Qt.alpha(Theme.palette.m3outlineVariant, 0.7)

        StateLayer {
            disabled: !root.interactive
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
