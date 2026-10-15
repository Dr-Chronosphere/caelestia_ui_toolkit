import QtQuick
import ".."

Item {
    id: root

    required property string home
    property alias view: view
    property string opened

    // Scene-coordinate centre of the first visible item whose `text` equals `s`, or null.
    function center(s) {
        function walk(it) {
            if (it.visible && it.text === s)
                return it;
            for (const c of it.children) {
                const r = walk(c);
                if (r)
                    return r;
            }
            return null;
        }
        const it = walk(root);
        if (!it)
            return null;
        const p = it.mapToItem(null, it.width / 2, it.height / 2);
        return Qt.point(p.x, p.y);
    }

    // Test helpers (PySide cannot hold QML object pointers).
    function get(name) {
        return view[name];
    }
    function set(name, value) {
        view[name] = value;
    }
    function call(name, a, b) {
        return view[name](a, b);
    }
    function setSearch(text) {
        view.searchField.text = text;
    }
    function placeLabels() {
        return view.places.map(p => p.label).join(",");
    }
    function backLength() {
        return view.backStack.length;
    }

    FilesView {
        id: view

        anchors.fill: parent
        home: root.home
        onOpenRequested: p => root.opened = p
    }
}
