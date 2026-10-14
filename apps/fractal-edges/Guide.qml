import QtQuick
import CaelestiaUI
import "Seams.js" as Seams

// The line that follows the pointer/finger while an edge is dragged. Pure QtQuick, placed by
// the host in a click-through window that covers the monitor. It is cut wherever a floating
// window covers the tiled layout, since layer surfaces would otherwise paint over that window.
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
    // Floating-window rects in layout coordinates (Seams.floatingRects).
    property var blockers: []

    readonly property var rects: seam ? Seams.guideRects(seam, ratio, originX, originY, thickness, blockers) : []

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
