import QtQuick
import ".."

Item {
    id: root

    property var log: []
    property var seam: ({
            "key": "a|b",
            "a": "a",
            "b": "b",
            "axis": "x",
            "ratio": 0.5,
            "span": 1000,
            "x": 0,
            "y": 0,
            "w": 16,
            "h": 400
        })

    function setSeam(s) {
        root.seam = s;
    }
    function logText() {
        return root.log.join("|");
    }
    function clearLog() {
        root.log = [];
    }
    function isDragging() {
        return strip.dragging;
    }

    EdgeStrip {
        id: strip

        x: 100
        y: 50
        width: root.seam.w
        height: root.seam.h
        seam: root.seam
        onDragStarted: root.log = [...root.log, "start"]
        onDragMoved: r => root.log = [...root.log, "move " + r.toFixed(3)]
        onDragFinished: r => root.log = [...root.log, "end " + r.toFixed(3)]
    }
}
