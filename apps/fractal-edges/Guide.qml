import QtQuick
import CaelestiaUI
import "Seams.js" as Seams

// The line that follows the pointer/finger while an edge is dragged. Pure QtQuick, placed by
// the host in a click-through window that covers the monitor.
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

    readonly property var rect: seam ? Seams.guideRect(seam, ratio, originX, originY, thickness) : null

    Rectangle {
        visible: root.rect !== null
        x: root.rect ? root.rect.x : 0
        y: root.rect ? root.rect.y : 0
        width: root.rect ? root.rect.w : 0
        height: root.rect ? root.rect.h : 0
        radius: 2
        color: Theme.palette.m3primary
    }
}
