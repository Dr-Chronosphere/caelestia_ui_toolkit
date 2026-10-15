import QtQuick
import ".."

Item {
    id: root

    property alias mixer: mock
    property alias view: view

    // Scene-coordinate centre of the first item whose text/title equals `s`, or null.
    function center(s) {
        function walk(it) {
            if (it.text === s || it.title === s)
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
    function logText() {
        return mock.log.join("|");
    }

    MockMixer {
        id: mock
    }
    MixerView {
        id: view

        anchors.fill: parent
        mixer: mock
    }
}
