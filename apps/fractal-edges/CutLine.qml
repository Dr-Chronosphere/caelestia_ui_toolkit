import QtQuick
import "Seams.js" as Seams

// A straight line (given as a rect) that is cut around blocker rects. Shared by the drag guide
// and the handle bar.
//
// All coordinates (line, blockers) are in the same frame. The cut around a blocker is its
// extent scaled by a per-blocker amount (0..1) around its centre.
//
// - Cutting IN is instant. A line that moves under a window must never be drawn over it, not
//   even for the few frames an animation would take (it looks natural too: the line simply goes
//   behind the window).
// - Cutting OUT is animated: when the line emerges from a window, the gap closes inward from
//   both ends toward its centre.
Item {
    id: root

    // {x, y, w, h}, or null for nothing
    property var line: null
    // The seam axis: "x" = a vertical line (runs along y), "y" = a horizontal line.
    property string axis: "x"
    property var blockers: []
    property color color: "white"
    property int radius: 2
    property int duration: 260

    property var spans: []
    property var prevT: []
    property var targetT: []
    property real progress: 1
    readonly property real eased: 1 - Math.pow(1 - progress, 3)

    readonly property var pieces: line ? Seams.guidePieces(line, axis, spans, prevT, targetT, eased) : []

    function currentT(): var {
        return prevT.map(function (p, i) {
            return p + (targetT[i] - p) * eased;
        });
    }

    // Recompute overlaps. `snap`: jump instead of animating (first state, or the set of
    // blockers changed in number).
    function retarget(snap: bool): void {
        if (!line) {
            spans = [];
            prevT = [];
            targetT = [];
            progress = 1;
            cutAnim.stop();
            return;
        }
        const sp = Seams.blockerSpans(line, axis, blockers);
        const nt = sp.map(function (s) {
            return s.on ? 1 : 0;
        });
        spans = sp;
        if (snap || targetT.length !== nt.length) {
            prevT = nt;
            targetT = nt;
            progress = 1;
            cutAnim.stop();
            return;
        }
        if (nt.every(function (v, i) {
            return v === targetT[i];
        }))
            return;
        // Blockers that now cut MORE jump straight to their target (prev = target); the ones
        // that cut less ease from where they are now.
        const base = currentT();
        prevT = base.map(function (b, i) {
            return nt[i] > b ? nt[i] : b;
        });
        targetT = nt;
        progress = 0;
        cutAnim.restart();
    }

    onLineChanged: retarget(false)
    onBlockersChanged: retarget(false)
    onAxisChanged: retarget(true)

    NumberAnimation {
        id: cutAnim

        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.duration
        easing.type: Easing.Linear
    }

    Repeater {
        model: root.pieces

        Rectangle {
            required property var modelData

            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
            radius: root.radius
            color: root.color
        }
    }
}
