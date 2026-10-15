// Quickshell host for the Fractal Map (Caelestia port).
//
// Derived from the wiring in Map.qml of cgranier/fractal-wm (MIT, Copyright (c) 2026
// Carlos Granier; see LICENSE.fractal-wm). Runs as its own Quickshell instance, started
// once and toggled over IPC:   qs -p apps/fractal-map ipc call fractalmap toggle
// (bin/caelestia-fractal-map does this for you).
//
// Data flow: the fractal layout writes $XDG_RUNTIME_DIR/fractal-wm/ws-<id>.json on every
// change; we watch it, prune windows that no longer exist (hyprctl clients) and hand the
// result to MapView. Picks go back through `hyprctl dispatch 'hl.dsp.layout("...")'`.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import CaelestiaUI
import "Model.js" as Model

ShellRoot {
    id: root

    property bool opened: false
    property int workspaceId: -1
    property string workspaceLayout: ""
    property string clientsJson: ""
    property var status: null
    property string notice: ""

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fractal-wm"
    readonly property string layoutName: "lua:fractal"

    // ---- Lifecycle ---------------------------------------------------------------
    // `workspace` empty = the active workspace.
    function open(workspace: string): void {
        notice = "";
        clientsJson = "";
        if (workspace !== "" && !isNaN(parseInt(workspace))) {
            workspaceId = parseInt(workspace);
            workspaceLayout = layoutName;
            clients.running = true;
        } else {
            workspaceId = -1;
            activeWorkspace.running = true;
        }
        opened = true;
        view.reset();
    }

    function close(): void {
        opened = false;
    }

    function toggle(): void {
        if (opened)
            close();
        else
            open("");
    }

    function refresh(): void {
        if (workspaceId >= 0)
            statusFile.reload();
    }

    // ---- Hyprland ------------------------------------------------------------------
    function layoutMsg(msg: string): void {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.layout(\"" + msg.replace(/"/g, "") + "\")"]);
    }

    function enableHere(): void {
        if (workspaceId < 0)
            return;
        Quickshell.execDetached(["hyprctl", "eval", "hl.workspace_rule({ workspace = \"" + workspaceId + "\", layout = \"" + layoutName + "\" })"]);
        workspaceLayout = layoutName;
        notice = "Workspace " + workspaceId + " now uses " + layoutName + ". Run `fractal on` once to keep it across reloads.";
        refreshTimer.restart();
    }

    function applyStatus(text: string): void {
        let parsed = Model.parseStatus(text);
        if (parsed && clientsJson !== "")
            parsed = Model.prune(parsed, Model.liveAddresses(clientsJson, workspaceId));
        status = parsed;
    }

    // Live thumbnail source for a window, by Hyprland address (either spelling).
    function toplevelFor(address: string): var {
        if (!address)
            return null;
        const want = String(address).replace(/^0x/, "").toLowerCase();
        let list = [];
        try {
            list = Hyprland.toplevels.values;
        } catch (e) {
            return null;
        }
        for (let i = 0; i < list.length; i++) {
            const have = String(list[i].address || "").replace(/^0x/, "").toLowerCase();
            if (have === want)
                return list[i].wayland || null;
        }
        return null;
    }

    // ---- IPC -------------------------------------------------------------------------
    IpcHandler {
        target: "fractalmap"

        function toggle(): void {
            root.toggle();
        }
        function open(workspace: string): void {
            root.open(workspace);
        }
        function close(): void {
            root.close();
        }
        function isOpen(): string {
            return root.opened ? "true" : "false";
        }
        function refresh(): void {
            root.refresh();
        }
        // Test hooks: drive the pointer logic without a pointer (map pixels).
        function rects(): string {
            return JSON.stringify(view.rects.map(r => ({
                        "id": r.id,
                        "kind": r.kind,
                        "name": r.name,
                        "x": Math.round(r.x),
                        "y": Math.round(r.y),
                        "w": Math.round(r.w),
                        "h": Math.round(r.h),
                        "viewport": r.viewport,
                        "focused": r.focused
                    })));
        }
        function click(x: string, y: string): string {
            view.pointerPress(parseFloat(x), parseFloat(y), Qt.LeftButton, false);
            view.pointerRelease(parseFloat(x), parseFloat(y));
            return view.cursorId;
        }
        function selection(): string {
            return JSON.stringify(Object.keys(view.pickedIds));
        }
        function debug(): string {
            return JSON.stringify({
                "workspace": root.workspaceId,
                "layout": root.workspaceLayout,
                "clientsBytes": root.clientsJson.length,
                "windows": root.status ? root.status.windows : null
            });
        }
    }

    // hyprctl answers in milliseconds; give up rather than hold a process open.
    Timer {
        interval: 3000
        running: activeWorkspace.running || clients.running
        onTriggered: {
            activeWorkspace.running = false;
            clients.running = false;
        }
    }

    Process {
        id: activeWorkspace

        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            id: wsOut

            waitForEnd: true
        }
        onExited: {
            let ws = null;
            try {
                ws = JSON.parse(String(wsOut.text || "{}"));
            } catch (e) {
                ws = null;
            }
            root.workspaceId = ws && ws.id !== undefined ? ws.id : -1;
            root.workspaceLayout = ws && ws.tiledLayout ? String(ws.tiledLayout) : "";
            clients.running = true;
        }
    }

    Process {
        id: clients

        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsOut

            waitForEnd: true
        }
        onExited: {
            root.clientsJson = String(clientsOut.text || "");
            // The file may already be loaded; a reload with unchanged content
            // does not always re-emit `loaded`.
            root.applyStatus(statusFile.text());
            statusFile.reload();
        }
    }

    FileView {
        id: statusFile

        path: root.workspaceId >= 0 ? root.runtimeDir + "/ws-" + root.workspaceId + ".json" : ""
        watchChanges: root.opened
        printErrors: false
        blockLoading: false
        onLoaded: root.applyStatus(text())
        onLoadFailed: root.applyStatus("")
        onFileChanged: statusFile.reload()
    }

    Timer {
        id: refreshTimer

        interval: 400
        onTriggered: root.refresh()
    }

    // Safety net: never leave a full-screen overlay up.
    Timer {
        interval: 120000
        running: root.opened
        onTriggered: root.close()
    }

    // ---- Surface -----------------------------------------------------------------------
    PanelWindow {
        visible: root.opened
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        WlrLayershell.namespace: "caelestia-fractalmap"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        MapView {
            id: view

            anchors.fill: parent
            opened: root.opened
            status: root.status
            workspaceId: root.workspaceId
            workspaceLayout: root.workspaceLayout
            notice: root.notice
            thumbnailsSupported: true
            toplevelFor: root.toplevelFor
            onCommand: msg => root.layoutMsg(msg)
            onDismissRequested: root.close()
            onEnableRequested: root.enableHere()
            onRefreshRequested: root.refresh()
        }
    }
}
