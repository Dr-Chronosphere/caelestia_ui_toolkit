import QtQuick
import "Seams.js" as Seams

// A straight line (given as a rect) that is cut around blocker rects. Shared by the drag guide
// and the handle bar.
//
// All coordinates (line, blockers) are in the same frame. One rule governs every change of a cut,
// whatever caused it (the line sliding past a window's side, a window moving or resizing):
//
// - A cut that gets BIGGER is applied at once, so the line is never drawn over a window, not
//   even for the few frames an animation would take.
// - A cut that gets SMALLER eases (the gap closes inward from both ends), however slightly.
// - On a cut-in the line also recoils: it snaps to the window's edge, then pulls back `recoil`
//   px from it. That motion is always away from the window, so it cannot overlap.
Item {
    id: root

    // {x, y, w, h}, or null for nothing
    property var line: null
    // The seam axis: "x" = a vertical line (runs along y), "y" = a horizontal line.
    property string axis: "x"
    property var blockers: []
    property color color: "white"
    property int radius: 2
    // Roughly how long a shrinking cut takes to settle, in ms.
    property int duration: 260
    // Px the line pulls back from a window after cutting in (0 disables the recoil).
    property real recoil: 6

    // Displayed and target covers per blocker ({a, b, m}, see Seams.coverTargets).
    property var cur: []
    property var tgt: []
    property bool animating: false

    readonly property real tauMs: duration / 3.7
    readonly property var pieces: line ? Seams.piecesFromCovers(line, axis, cur) : []

    // Recompute targets. `snap`: jump everything (first state, or the set of blockers changed in
    // number). Otherwise growth is applied immediately and the rest eases on the next frames.
    function retarget(snap: bool): void {
        if (!line) {
            cur = [];
            tgt = [];
            animating = false;
            return;
        }
        const t = Seams.coverTargets(Seams.blockerSpans(line, axis, blockers), recoil);
        tgt = t;
        if (snap || cur.length !== t.length) {
            cur = t;
            animating = false;
            return;
        }
        const r = Seams.stepCovers(cur, t, 0);     // k = 0: only the snapping (growing) parts move
        cur = r.covers;
        animating = !r.done;
    }

    onLineChanged: retarget(false)
    onBlockersChanged: retarget(false)
    onAxisChanged: retarget(true)
    onRecoilChanged: retarget(false)

    FrameAnimation {
        running: root.animating

        onTriggered: {
            const k = 1 - Math.exp(-(frameTime * 1000) / root.tauMs);
            const r = Seams.stepCovers(root.cur, root.tgt, k);
            root.cur = r.covers;
            if (r.done)
                root.animating = false;
        }
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
