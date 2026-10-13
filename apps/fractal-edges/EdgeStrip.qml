import QtQuick
import CaelestiaUI
import "Seams.js" as Seams

// One draggable handle on the seam between two tiles. Pure QtQuick: the host decides
// where the item lives and what to do with the ratios.
//
// Pointer and touch both work: Qt turns a touch on a MouseArea into press/move/release.
// The drag is measured as a delta from the press point, so the strip may stay put (the
// host freezes it) or move without disturbing the math.
Item {
    id: root

    // One entry from Seams.seams()
    required property var seam

    // Idle visibility of the handle line. 0 = invisible until hovered/pressed.
    property real idleOpacity: 0
    readonly property bool dragging: area.pressed
    readonly property bool horizontal: seam.axis === "x"   // row seam: drag left/right

    signal dragStarted
    // Emitted on every pointer move while dragging, with the clamped new ratio for `seam.a`.
    signal dragMoved(real ratio)
    signal dragFinished(real ratio)

    function ratioFor(pos: real, start: real): real {
        return Seams.clampRatio(seam.ratio + (pos - start) / seam.span);
    }

    // The visible line: thin, centred in the (wider) grab area.
    Rectangle {
        anchors.centerIn: parent
        width: root.horizontal ? 3 : parent.width
        height: root.horizontal ? parent.height : 3
        radius: 2
        color: Theme.palette.m3primary
        opacity: area.pressed ? 0.9 : area.containsMouse ? 0.6 : root.idleOpacity

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }
    }

    MouseArea {
        id: area

        property real startPos
        property real lastRatio

        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: root.horizontal ? Qt.SplitHCursor : Qt.SplitVCursor

        function pos(mouse): real {
            return root.horizontal ? mouse.x : mouse.y;
        }

        onPressed: mouse => {
            startPos = pos(mouse);
            lastRatio = root.seam.ratio;
            root.dragStarted();
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            lastRatio = root.ratioFor(pos(mouse), startPos);
            root.dragMoved(lastRatio);
        }
        onReleased: mouse => {
            lastRatio = root.ratioFor(pos(mouse), startPos);
            root.dragFinished(lastRatio);
        }
        onCanceled: root.dragFinished(root.seam.ratio)
    }
}
