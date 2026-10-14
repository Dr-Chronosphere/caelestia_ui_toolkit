import QtQuick
import CaelestiaUI
import "Seams.js" as Seams

// The line that follows the pointer/finger while an edge is dragged. Pure QtQuick, placed by
// the host in a click-through window that covers the monitor.
//
// - It is cut wherever a floating window covers the tiled layout (layer surfaces would
//   otherwise paint over that window); the cut opens/closes smoothly (see CutLine) as the line
//   slides past a window's side.
// - Past the seam's limits it thickens (rubber band); `settling` animates it back on release,
//   and `fading` fades it out afterwards.
//
// (The host once read `parent.s` from inside a Quickshell window, where `parent` is the
// window's content item, so the line never appeared; keeping this a separate, tested
// component with plain properties avoids that.)
Item {
    id: root

    // One entry from Seams.seams() (the whole seam, never a clipped piece), or null.
    property var seam: null
    property real ratio: 0
    // Monitor origin in layout coordinates.
    property real originX: 0
    property real originY: 0
    property real thickness: 3
    // True while the line settles back to the limit after release (animates `ratio`).
    property bool settling: false
    // Fade the whole line out (after settling).
    property bool fading: false
    // Floating-window rects in layout coordinates (Seams.floatingRects).
    property var blockers: []
    // How long a cut takes to open or close as the line crosses a window's side, in ms.
    property int cutDuration: 140

    // px past the seam's limits (0 inside them): the line thickens as it is pulled further.
    readonly property real over: seam ? Math.max(0, (seam.lo !== undefined ? seam.lo : 0.05) - ratio, ratio - (seam.hi !== undefined ? seam.hi : 0.95)) * seam.span : 0
    readonly property real drawnThickness: thickness + Math.min(3, over / 12)

    // The line itself, in this item's coordinates (the monitor's).
    readonly property var thin: seam ? Seams.guideRect(seam, ratio, originX, originY, drawnThickness) : null

    opacity: fading ? 0 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: 170
        }
    }

    Behavior on ratio {
        enabled: root.settling

        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    CutLine {
        anchors.fill: parent
        line: root.thin
        axis: root.seam ? root.seam.axis : "x"
        blockers: Seams.shiftRects(root.blockers, root.originX, root.originY)
        color: Theme.palette.m3primary
        duration: root.cutDuration
    }
}
