import QtQuick
import ".."

// Two explorer "windows" side by side over the real TabsModel, to test tabs and merging.
Item {
    id: root

    required property string home
    property alias model: m
    property string previewOn: ""

    TabsModel {
        id: m

        home: root.home
    }

    function win(id) {
        return m.windows[m.winIndex(id)];
    }
    function json() {
        return JSON.stringify({ "windows": m.windows, "states": m.states });
    }
    function viewPath(winId, tabId) {
        const t = winId === "1" ? left : right;
        const v = t.viewFor(tabId);
        return v ? v.path : null;
    }
    function viewDo(winId, tabId, path) {
        const t = winId === "1" ? left : right;
        const v = t.viewFor(tabId);
        if (v)
            v.go(path);
    }
    function chips(winId) {
        const t = winId === "1" ? left : right;
        return JSON.stringify(t.labels.map(l => l.label));
    }
    function activeLabel(winId) {
        return (winId === "1" ? left : right).activeLabel;
    }
    function previewOpacity(winId) {
        return (winId === "1" ? left : right).dropPreview ? 1 : 0;
    }
    function addTab(winId, path) {
        m.addTab(winId, path);
    }
    function closeTab(winId, tabId) {
        m.closeTab(winId, tabId);
    }
    function mergeWindows(from, to) {
        return m.merge(from, to);
    }
    function moveTab(winId, tabId, to) {
        m.moveTab(winId, tabId, to);
    }
    function tearOut(winId, tabId) {
        return m.tearOut(winId, tabId);
    }
    function chipCenter(winId, i) {
        return (winId === "1" ? left : right).tabBar.chipCenter(i);
    }
    function setPreview(winId) {
        previewOn = winId;
    }

    FilesTabs {
        id: left

        x: 0
        width: 480
        height: 400
        home: root.home
        tabs: root.win("1") ? root.win("1").tabs : []
        active: root.win("1") ? root.win("1").active : ""
        states: m.states
        dropPreview: root.previewOn === "1"
        onNewTabRequested: m.addTab("1", "")
        onCloseTabRequested: id => m.closeTab("1", id)
        onActivateTabRequested: id => m.activateTab("1", id)
        onMoveTabRequested: (id, to) => m.moveTab("1", id, to)
        onTearTabRequested: id => m.tearOut("1", id)
        onStateUpdated: (id, s) => m.updateState(id, s)
    }

    FilesTabs {
        id: right

        x: 500
        width: 480
        height: 400
        home: root.home
        tabs: root.win("2") ? root.win("2").tabs : []
        active: root.win("2") ? root.win("2").active : ""
        states: m.states
        dropPreview: root.previewOn === "2"
        onNewTabRequested: m.addTab("2", "")
        onCloseTabRequested: id => m.closeTab("2", id)
        onActivateTabRequested: id => m.activateTab("2", id)
        onMoveTabRequested: (id, to) => m.moveTab("2", id, to)
        onTearTabRequested: id => m.tearOut("2", id)
        onStateUpdated: (id, s) => m.updateState(id, s)
    }

    Component.onCompleted: {
        m.newWindow(home);
        m.newWindow(home + "/Projects");
    }
}
