import QtQuick
import Quickshell
import Quickshell.Io

// Watches the caelestia scheme file and feeds it to Theme.
// Created by Theme at startup; requires Quickshell.
Scope {
    id: root

    required property QtObject theme

    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/caelestia/scheme.json`

    FileView {
        path: root.theme.schemePath || root.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.theme.applyScheme(text())
    }
}
