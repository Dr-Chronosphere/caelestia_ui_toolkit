import QtQuick
import Quickshell
import CaelestiaUI
import qs.services

// Caelestia audio mixer (standalone window).
// Run:  QML_IMPORT_PATH=<repo>/qml qs -p apps/audio-mixer      (or ./run.sh)
ShellRoot {
    AppWindow {
        title: "Audio"
        implicitWidth: 480
        implicitHeight: 720
        visible: true

        MixerView {
            anchors.fill: parent
            mixer: Mixer
        }
    }
}
