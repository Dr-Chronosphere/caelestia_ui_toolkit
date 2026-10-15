import QtQuick
import ".."

Rectangle {
    id: root

    color: "black"

    function show(seam, ratio) {
        guide.seam = seam;
        guide.ratio = ratio;
    }
    function hide() {
        guide.seam = null;
    }
    function setSettling(on) {
        guide.settling = on;
    }
    function drawnThickness() {
        return guide.drawnThickness;
    }
    function setBlockers(list) {
        guide.blockers = list;
    }

    Guide {
        id: guide

        anchors.fill: parent
        originX: 100
        originY: 0
    }
}
