import QtQuick
import CaelestiaUI
import "Seams.js" as Seams

// One draggable handle on the seam between two tiles. Pure QtQuick: the host decides where the
// window lives and what to do with the ratios.
//
// The item spans its WHOLE seam and stays alive; floating windows only cut what is grabbable
// (`hitRects`, which the host turns into the window's input mask) and what is drawn (the hover
// bar, whose cuts open and close smoothly). Rebuilding the window whenever a floating window
// moved made the bar blink out and pop back; keeping it makes the hover state survive too.
//
// Pointer and touch both work: Qt turns a touch on a MouseArea into press/move/release.
// The drag is measured as a delta from the press point, so the item may stay put (the host
// freezes it during a drag) or move without disturbing the math.
Item {
    id: root

    // One entry from Seams.seams(), whole seam, layout coordinates. This item's top-left is at
    // (seam.x, seam.y).
    required property var seam
    // Floating-window rects in layout coordinates (Seams.floatingRects).
    property var blockers: []

    // Idle visibility of the handle bar. 0 = invisible until hovered/pressed.
    property real idleOpacity: 0
    // The host draws the line that follows the pointer while dragging (this item is frozen
    // in place during a drag), so hide our own bar while pressed.
    property bool externalGuide: true
    // How far (px) the guide may be pulled past the limit before it stops giving.
    property real give: 40
    property real barWidth: 3
    // Cut animation: how long a shrinking cut takes to settle (ms) and the recoil (px) after a cut-in.
    property int cutDuration: 260
    property real cutRecoil: 6

    readonly property bool dragging: area.pressed
    readonly property bool horizontal: seam.axis === "x"   // row seam: drag left/right

    // The stretches that can take input now (this item's coordinates), for the window's mask.
    readonly property var hitRects: Seams.shiftRects(Seams.pieces(seam, blockers, 24), seam.x, seam.y)

    signal dragStarted
    // Emitted on every pointer move while dragging. `ratio` is what the tiles can actually do
    // (clamped to the engine's limits); `shown` is for the guide line and stretches past the
    // limit like a rubber band.
    signal dragMoved(real ratio, real shown)
    signal dragFinished(real ratio)

    function rawFor(pos: real, start: real): real {
        return seam.ratio + (pos - start) / seam.span;
    }
    function ratioFor(pos: real, start: real): real {
        return Seams.clampRatio(rawFor(pos, start), seam);
    }
    function shownFor(pos: real, start: real): real {
        return Seams.rubberBand(rawFor(pos, start), seam, give);
    }

    // The visible bar: thin, centred in the (wider) grab area, cut around floating windows.
    CutLine {
        anchors.fill: parent
        line: root.horizontal ? {
            "x": (root.width - root.barWidth) / 2,
            "y": 0,
            "w": root.barWidth,
            "h": root.height
        } : {
            "x": 0,
            "y": (root.height - root.barWidth) / 2,
            "w": root.width,
            "h": root.barWidth
        }
        axis: root.seam.axis
        blockers: Seams.shiftRects(root.blockers, root.seam.x, root.seam.y)
        color: Theme.palette.m3primary
        duration: root.cutDuration
        recoil: root.cutRecoil
        opacity: area.pressed ? (root.externalGuide ? 0 : 0.9) : area.containsMouse ? 0.6 : root.idleOpacity

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
            root.dragMoved(lastRatio, root.shownFor(pos(mouse), startPos));
        }
        onReleased: mouse => {
            lastRatio = root.ratioFor(pos(mouse), startPos);
            root.dragFinished(lastRatio);
        }
        onCanceled: root.dragFinished(root.seam.ratio)
    }
}
