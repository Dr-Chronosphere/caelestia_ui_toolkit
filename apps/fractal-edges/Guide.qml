import QtQuick
import CaelestiaUI
import "Seams.js" as Seams

// The line that follows the pointer/finger while an edge is dragged. Pure QtQuick, placed by
// the host in a click-through window that covers the monitor.
//
// - It is cut wherever a floating window covers the tiled layout (layer surfaces would
//   otherwise paint over that window). When the line slides past a window's side, the cut grows
//   or shrinks smoothly around the window's centre instead of popping.
// - Past the seam's limits it thickens (rubber band); `settling` animates it back on release.
//
// (The host once read `parent.s` from inside a Quickshell window, where `parent` is the
// window's content item, so the line never appeared; keeping this a separate, tested
// component with plain properties avoids that.)
Item {
    id: root

    // One entry from Seams.seams(), or null when nothing is being dragged.
    property var seam: null
    property real ratio: 0
    // Monitor origin in layout coordinates.
    property real originX: 0
    property real originY: 0
    property real thickness: 3
    // True while the line settles back to the limit after release (animates `ratio`).
    property bool settling: false
    // Floating-window rects in layout coordinates (Seams.floatingRects).
    property var blockers: []
    // How long a cut takes to open or close as the line crosses a window's side, in ms.
    property int cutDuration: 140

    // px past the seam's limits (0 inside them): the line thickens as it is pulled further.
    readonly property real over: seam ? Math.max(0, (seam.lo !== undefined ? seam.lo : 0.05) - ratio, ratio - (seam.hi !== undefined ? seam.hi : 0.95)) * seam.span : 0
    readonly property real drawnThickness: thickness + Math.min(3, over / 12)

    // The line itself, in layout coordinates.
    readonly property var thin: seam ? Seams.guideRect(seam, ratio, 0, 0, drawnThickness) : null

    // Cut state per blocker: where each was (prevT), where it is heading (targetT), and how far
    // along (progress 0..1). Effective cut = prevT + (targetT - prevT) * eased progress.
    property var spans: []
    property var prevT: []
    property var targetT: []
    property real progress: 1
    readonly property real eased: 1 - Math.pow(1 - progress, 3)

    readonly property var rects: (thin && seam) ? Seams.guidePieces(thin, seam.axis, spans, prevT, targetT, eased).map(function (r) {
        return {
            "x": r.x - originX,
            "y": r.y - originY,
            "w": r.w,
            "h": r.h
        };
    }) : []

    function currentT(): var {
        return prevT.map(function (p, i) {
            return p + (targetT[i] - p) * eased;
        });
    }

    // Recompute which blockers the line overlaps. `snap`: jump instead of animating (a new
    // drag, or the windows themselves changed).
    function retarget(snap: bool): void {
        if (!thin || !seam) {
            spans = [];
            prevT = [];
            targetT = [];
            progress = 1;
            cutAnim.stop();
            return;
        }
        const sp = Seams.blockerSpans(thin, seam.axis, blockers);
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
        prevT = currentT();
        targetT = nt;
        progress = 0;
        cutAnim.restart();
    }

    onThinChanged: retarget(false)
    onBlockersChanged: retarget(true)
    onSeamChanged: retarget(true)

    NumberAnimation {
        id: cutAnim

        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.cutDuration
    }

    Behavior on ratio {
        enabled: root.settling

        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    Repeater {
        model: root.rects

        Rectangle {
            required property var modelData

            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
            radius: 2
            color: Theme.palette.m3primary
        }
    }
}
