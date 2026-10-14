import QtQuick
import ".."

Rectangle {
    id: root

    color: "white"
    width: 500
    height: 300

    property var log: []
    function logText() {
        return root.log.join("|");
    }
    function clearLog() {
        root.log = [];
    }
    function opacities() {
        return JSON.stringify([big.opacity, small.opacity]);
    }
    function labelShown(which) {
        return which === "big" ? big.labelVisible : small.labelVisible;
    }

    IconCard {
        id: big

        readonly property bool labelVisible: width >= 96 && height >= 84

        x: 10
        y: 10
        width: 140
        height: 100
        label: "foot"
        onActivated: root.log = [...root.log, "big"]
    }
    IconCard {
        id: small

        readonly property bool labelVisible: width >= 96 && height >= 84

        x: 200
        y: 10
        width: 60
        height: 50
        label: "zen"
        onActivated: root.log = [...root.log, "small"]
    }
}
