import QtQuick
import Quickshell
import CaelestiaUI

// Run with:  QML_IMPORT_PATH=<repo>/qml qs -p examples/gallery
// (or use ./run.sh)
ShellRoot {
    AppWindow {
        title: "Caelestia UI Gallery"
        implicitWidth: gallery.implicitWidth
        implicitHeight: gallery.implicitHeight
        visible: true

        Gallery {
            id: gallery

            anchors.fill: parent
        }
    }
}
