import QtQuick
import Quickshell
import CaelestiaUI

// Caelestia file manager (standalone window).
// Run:  QML_IMPORT_PATH=<repo>/qml qs -p apps/files      (or bin/caelestia-files)
ShellRoot {
    AppWindow {
        title: "Files"
        implicitWidth: 960
        implicitHeight: 640
        visible: true

        FilesView {
            anchors.fill: parent
            home: Quickshell.env("HOME")
            onOpenRequested: p => Quickshell.execDetached(["xdg-open", p])
        }
    }
}
