import QtQuick
import ".."

// The strip and the guide wired together the way shell.qml does it: the strip lives in a window
// at (stripX, stripY) of the monitor, the guide covers the whole monitor, origin (0, 0).
Item {
    id: root

    width: 1300
    height: 900

    property var seam: ({
            "key": "a|b",
            "a": "a",
            "b": "b",
            "axis": "x",
            "ratio": 0.5,
            "span": 1000,
            "lo": 0.1,
            "hi": 0.9,
            "x": 300,
            "y": 50,
            "w": 16,
            "h": 600
        })
    property var blockers: []
    property var dragSeam: null
    property real dragRatio: 0
    property bool settling: false
    property bool fading: false
    property var log: []

    function setBlockers(list) {
        root.blockers = list;
    }
    function setSeam(s) {
        root.seam = s;
    }
    function logText() {
        return root.log.join("|");
    }
    function clearLog() {
        root.log = [];
    }

    // The monitor's tiled layer: nothing here, just white so pixels are easy to read.
    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    function cutState() {
        const c = guide.cutLine;
        return JSON.stringify({
            "cur": c.cur,
            "tgt": c.tgt,
            "animating": c.animating
        });
    }

    Guide {
        id: guide

        anchors.fill: parent
        seam: root.dragSeam
        ratio: root.dragRatio
        blockers: root.blockers
        settling: root.settling
        fading: root.fading
    }

    EdgeStrip {
        x: root.seam.x
        y: root.seam.y
        width: root.seam.w
        height: root.seam.h
        seam: root.seam
        blockers: root.blockers
        onDragStarted: {
            root.settling = false;
            root.fading = false;
            root.dragRatio = root.seam.ratio;      // ratio first: the guide must not show a stale one
            root.dragSeam = root.seam;
        }
        onDragMoved: (ratio, shown) => {
            root.dragRatio = shown;
        }
        onDragFinished: ratio => {
            root.settling = true;
            root.dragRatio = ratio;
        }
    }
}
