import QtQuick
import ".."
import "../Model.js" as Model

Item {
    id: root

    property var log: []

    function load(text, layout) {
        view.workspaceLayout = layout
        view.workspaceId = 9
        view.opened = true
        view.status = Model.parseStatus(text)
        view.reset()
    }
    function get(name) {
        return view[name];
    }
    function set(name, value) {
        view[name] = value;
    }
    function call(name, a, b, c, d) {
        return view[name](a, b, c, d);
    }
    function logText() {
        return root.log.join("|");
    }
    function clearLog() {
        root.log = [];
    }
    // [{id, kind, x, y, w, h, isWindow}] in map coordinates, as JSON
    function rectsJson() {
        return JSON.stringify(view.rects.map(r => ({
                    "id": r.id,
                    "kind": r.kind,
                    "isWindow": r.isWindow,
                    "x": r.x,
                    "y": r.y,
                    "w": r.w,
                    "h": r.h
                })));
    }
    function selectionJson() {
        return JSON.stringify(Object.keys(view.pickedIds).sort());
    }

    MapView {
        id: view

        anchors.fill: parent
        onCommand: msg => root.log = [...root.log, msg]
        onDismissRequested: root.log = [...root.log, "dismiss"]
        onEnableRequested: root.log = [...root.log, "enable"]
        onRefreshRequested: root.log = [...root.log, "refresh"]
    }
}
