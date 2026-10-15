import QtQuick
import QtQuick.Effects
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
    // Appear fully shown instead of fading in from nothing (a card that is just part of a workspace
    // that slides into view).
    property bool startShown: false
    property bool _applied: false
    // Length of the fade once it eases (after the layout settles or when a card leaves).
    property int fadeMs: 450
    // Tint opacity of the card's backing. The host blurs what is behind the card (a layer rule),
    // so the backing is translucent; use 1 for an opaque card when blur is off.
    property real tint: 0.62
    // Corner radius; negative uses the theme's medium rounding.
    property real cornerRadius: -1
    // A pre-blurred stand-in for the desktop behind the card: the wallpaper decoded at a tiny size
    // (so scaling it back up is the blur) and positioned so the card shows the part of it that
    // lies at the card's place on the screen. Empty = no backdrop (translucent tint only).
    property url backdrop
    property real backdropX: 0
    property real backdropY: 0
    property real backdropW: 0
    property real backdropH: 0
    property int backdropShrink: 12
    // 0..1 of the effect's maximum blur radius (measured in the tiny image's pixels).
    property real blurAmount: 0.5
    readonly property bool _gpu: GraphicsInfo.api !== GraphicsInfo.Software

    readonly property bool hasIcon: img.status === Image.Ready
    readonly property real iconEdge: Lod.iconSize(width, height)
    // Faint cards let taps through (the host also drops the window's input region).
    readonly property bool interactive: shown && alpha > 0.3

    // Tap / click: zoom into this window.
    signal activated
    // The pointer entered the card.
    signal hovered

    // Fade with the shell's own effects curve. A new card starts at 0 and fades in.
    property bool ready: false

    // The opacity we are heading for. Applied a tick after any of alpha/shown/smooth change
    // (Qt.callLater), so that `smooth` is up to date when the new alpha arrives: with a Behavior
    // toggled by `smooth`, bindings re-evaluated in the wrong order made the fade snap.
    readonly property real target: (ready && shown) ? alpha : 0
    onTargetChanged: Qt.callLater(root.applyTarget)
    Component.onCompleted: {
        ready = true;
        Qt.callLater(root.applyTarget);
    }

    function applyTarget() {
        const first = !root._applied;
        root._applied = true;
        if (!root.smooth || (first && root.startShown)) {
            fade.stop();
            root.level = root.target;
        } else if (fade.to !== root.target || !fade.running) {
            fade.stop();
            fade.from = root.level;
            fade.to = root.target;
            fade.start();
        }
    }

    // How far the card has faded in (0..1). The wallpaper backdrop crossfades with the live window
    // underneath on a smoothstep of it (gentle at both ends, so it neither pops in nor out);
    // backdropRamp > 1 makes it reach full strength at 1/backdropRamp of the fade instead.
    property real level: 0
    property real backdropRamp: 1

    Anim {
        id: fade

        target: root
        property: "level"
        type: Anim.DefaultEffects
        duration: root.fadeMs
    }

    readonly property real _radius: root.cornerRadius >= 0 ? root.cornerRadius : Theme.rounding.medium

    Item {
        anchors.fill: parent
        opacity: {
            const t = Math.min(1, root.level * root.backdropRamp);
            return t * t * (3 - 2 * t);
        }
        visible: root.backdrop.toString() !== "" && root.backdropW > 0 && opacity > 0
        layer.enabled: root._gpu && visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: frostMask
        }

        // The wallpaper at 1/backdropShrink size, blurred there (cheap: it is tiny and static, so
        // the effect is rendered once) and scaled up to screen size; MultiEffect's blur is a
        // multi-pass down/up-sample (Kawase-style), which is soft rather than boxy.
        Item {
            id: tiny

            x: -root.backdropX
            y: -root.backdropY
            width: Math.max(8, Math.ceil(root.backdropW / root.backdropShrink))
            height: Math.max(8, Math.ceil(root.backdropH / root.backdropShrink))
            scale: root.backdropW / width
            transformOrigin: Item.TopLeft

            Image {
                id: wall

                anchors.fill: parent
                source: root.backdrop
                sourceSize.width: tiny.width
                fillMode: Image.PreserveAspectCrop
                smooth: true
                asynchronous: true
                cache: true
                visible: !root._gpu
            }

            MultiEffect {
                anchors.fill: parent
                visible: root._gpu
                source: wall
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 32
                blur: root.blurAmount
            }
        }
    }

    Rectangle {
        id: frostMask

        anchors.fill: parent
        radius: root._radius
        visible: false
        layer.enabled: root._gpu
    }

    StyledRect {
        anchors.fill: parent
        opacity: root.level
        radius: root.cornerRadius >= 0 ? root.cornerRadius : Theme.rounding.medium
        color: Qt.alpha(Theme.palette.m3surfaceContainerHigh, root.tint)
        border.width: 1
        border.color: Qt.alpha(Theme.palette.m3outlineVariant, 0.7)

        StateLayer {
            disabled: !root.interactive
            onClicked: root.activated()
            onContainsMouseChanged: {
                if (containsMouse)
                    root.hovered();
            }
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
