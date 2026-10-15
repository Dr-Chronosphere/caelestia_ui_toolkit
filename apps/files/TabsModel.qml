import QtQuick
import "logic/Tabs.js" as Tabs

// All explorer windows and their tabs. Windows: [{ id, tabs: [tabId...], active: tabId }]. A tab's
// contents (path, history, view mode) live in `states`, keyed by tab id, so tabs survive moving
// between windows. QtQuick only (no Quickshell), so it is tested headlessly.
QtObject {
    id: model

    property string home: "/"
    property var windows: []
    property var states: ({})
    property int winCounter: 0
    property bool everOpened: false

    // Emitted when the last window has gone.
    signal allClosed

    function winIndex(id: string): int {
        return windows.findIndex(w => w.id === id);
    }

    // Replace a window's record; a record with no tabs removes the window.
    function setWindow(id: string, win: var): void {
        const i = winIndex(id);
        if (i < 0)
            return;
        const next = windows.slice();
        if (win.tabs.length === 0)
            next.splice(i, 1);
        else
            next[i] = { "id": id, "tabs": win.tabs, "active": win.active };
        windows = next;
        if (next.length === 0 && everOpened)
            allClosed();
    }

    function newWindow(path: string): string {
        const tid = Tabs.newId();
        winCounter++;
        const id = String(winCounter);
        states = Object.assign({}, states, { [tid]: { "path": path || home } });
        windows = [...windows, { "id": id, "tabs": [tid], "active": tid }];
        everOpened = true;
        return id;
    }

    function addTab(winId: string, path: string): void {
        const i = winIndex(winId);
        if (i < 0)
            return;
        const tid = Tabs.newId();
        states = Object.assign({}, states, { [tid]: { "path": path || home } });
        setWindow(winId, Tabs.open(windows[i], tid));
    }

    // Close a tab; closing a window's only tab closes the window.
    function closeTab(winId: string, tabId: string): void {
        const i = winIndex(winId);
        if (i < 0)
            return;
        const next = Object.assign({}, states);
        delete next[tabId];
        states = next;
        setWindow(winId, Tabs.close(windows[i], tabId));
    }

    function closeWindow(winId: string): void {
        const i = winIndex(winId);
        if (i < 0)
            return;
        const next = Object.assign({}, states);
        windows[i].tabs.forEach(t => delete next[t]);
        states = next;
        setWindow(winId, { "tabs": [], "active": "" });
    }

    function activateTab(winId: string, tabId: string): void {
        const i = winIndex(winId);
        if (i >= 0)
            setWindow(winId, Tabs.activate(windows[i], tabId));
    }

    // Move a tab to position `to` within its window.
    function moveTab(winId: string, tabId: string, to: int): void {
        const i = winIndex(winId);
        if (i >= 0)
            setWindow(winId, Tabs.move(windows[i], tabId, to));
    }

    // Tear a tab out into a window of its own (it keeps its folder and history). A window's only
    // tab stays where it is. Returns the new window's id, or "".
    function tearOut(winId: string, tabId: string): string {
        const i = winIndex(winId);
        if (i < 0 || windows[i].tabs.length < 2 || windows[i].tabs.indexOf(tabId) < 0)
            return "";
        const rest = Tabs.close(windows[i], tabId);
        winCounter++;
        const id = String(winCounter);
        const next = windows.slice();
        next[i] = { "id": winId, "tabs": rest.tabs, "active": rest.active };
        next.push({ "id": id, "tabs": [tabId], "active": tabId });
        windows = next;
        return id;
    }

    function updateState(tabId: string, snap: var): void {
        states = Object.assign({}, states, { [tabId]: snap });
    }

    // Fold window `from` into window `to`: its tabs are appended and its active tab shown.
    function merge(from: string, to: string): bool {
        const fi = winIndex(from), ti = winIndex(to);
        if (fi < 0 || ti < 0 || from === to)
            return false;
        const merged = Tabs.merge(windows[ti], windows[fi]);
        const next = windows.filter(w => w.id !== from);
        next[next.findIndex(w => w.id === to)] = { "id": to, "tabs": merged.tabs, "active": merged.active };
        windows = next;
        return true;
    }
}
