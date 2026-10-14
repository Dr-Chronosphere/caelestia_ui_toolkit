// Mouse/touch edge handles for the fractal-wm layout.
//
// Hyprland's Lua layout API has no resize hook, so `resize_on_border` cannot drive a
// layout's weights. Instead this overlay puts a thin layer-shell window on every seam
// between neighbouring tiles; dragging it sends the layout's `edge <a> <b> <ratio>`
// command (needs integration/fractal-wm-edge-resize.patch applied to fractal-wm).
// Wayland delivers touch the same way as pointer input, so touch works too.
//
// Data: $XDG_RUNTIME_DIR/fractal-wm/ws-<id>.json for each monitor's active workspace.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import CaelestiaUI
import "Seams.js" as Seams

ShellRoot {
    id: root

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fractal-wm"
    readonly property string layoutName: "lua:fractal"
    // Handle thickness in px; bigger is easier to hit with a finger.
    readonly property int grab: parseInt(Quickshell.env("FRACTAL_EDGE_GRAB")) || 16
    // "live": tiles follow the drag (throttled); "release": a guide line follows the pointer
    // and tiles snap there when you let go (no lag at all, nothing resizes mid-drag).
    readonly property bool live: Quickshell.env("FRACTAL_EDGE_MODE") !== "release"
    // Minimum ms between live resize commands.
    readonly property int interval: parseInt(Quickshell.env("FRACTAL_EDGE_INTERVAL")) || 33

    // Switch Hyprland's animations off while a handle is dragged (so tiles follow the pointer
    // instead of easing toward it) and back on afterwards. `FRACTAL_EDGE_ANIM=keep` opts out.
    // If the overlay ever dies mid-drag, `hyprctl reload` restores your animation settings.
    readonly property bool suspendAnimations: Quickshell.env("FRACTAL_EDGE_ANIM") !== "keep"
    property int activeDrags: 0
    property bool animSuspended: false

    function setAnimations(on: bool): void {
        Quickshell.execDetached(["hyprctl", "eval", Seams.animCommand(on)]);
    }

    function dragBegan(): void {
        activeDrags++;
        restoreTimer.stop();
        if (!suspendAnimations || animSuspended || activeDrags !== 1)
            return;
        animProbe.running = true;
    }

    function dragEnded(): void {
        activeDrags = Math.max(0, activeDrags - 1);
        if (activeDrags === 0 && animSuspended)
            restoreTimer.restart();
    }

    function restoreAnimations(): void {
        if (animSuspended) {
            setAnimations(true);
            animSuspended = false;
        }
    }

    // Read the current setting first: never turn animations on for someone who had them off.
    Process {
        id: animProbe

        command: ["hyprctl", "getoption", "animations:enabled", "-j"]
        stdout: StdioCollector {
            id: probeOut

            waitForEnd: true
        }
        onExited: {
            if (Seams.parseAnimEnabled(String(probeOut.text || "")) === true && root.activeDrags > 0) {
                root.setAnimations(false);
                root.animSuspended = true;
            }
        }
    }

    // Wait a moment after the last resize command so that resize snaps instead of easing.
    Timer {
        id: restoreTimer

        interval: 150
        onTriggered: root.restoreAnimations()
    }

    Component.onDestruction: restoreAnimations()

    // Floating windows sit above the tiled layout, but layer-shell handles would paint over
    // them, so handles are cut wherever a floating window covers a seam. Refreshed on window
    // events, and polled lightly while a floating window exists (they can be dragged around
    // without any event).
    property string clientsText: ""
    property string monitorsText: ""
    readonly property bool floatingPresent: Seams.hasFloating(clientsText)
    readonly property var floatEvents: ["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode", "fullscreen", "workspace", "workspacev2", "focusedmon", "focusedmonv2", "activespecial", "activespecialv2", "configreloaded", "pin", "monitoradded", "monitorremoved"]

    function refreshFloating(): void {
        if (!monitorsProc.running && !clientsProc.running)
            monitorsProc.running = true;
    }

    Component.onCompleted: refreshFloating()

    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            if (root.floatEvents.indexOf(event.name) >= 0)
                floatDebounce.restart();
        }
    }

    Timer {
        id: floatDebounce

        interval: 60
        onTriggered: root.refreshFloating()
    }

    Timer {
        interval: 350
        repeat: true
        running: root.floatingPresent && !root.shuttingDown
        onTriggered: root.refreshFloating()
    }

    Process {
        id: monitorsProc

        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsOut

            waitForEnd: true
        }
        onExited: {
            const t = String(monitorsOut.text || "");
            if (t !== root.monitorsText)
                root.monitorsText = t;
            clientsProc.running = true;
        }
    }

    Process {
        id: clientsProc

        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsOut

            waitForEnd: true
        }
        onExited: {
            const t = String(clientsOut.text || "");
            if (t !== root.clientsText)
                root.clientsText = t;
        }
    }

    // Set by the `quit` IPC call: tear the handle windows down first, then exit. Killing the
    // process outright (`qs kill`) destroys windows whose items own a mouse cursor after Qt can
    // no longer unset it, which aborts inside QWindow::unsetCursor (seen in a crash report).
    property bool shuttingDown: false

    IpcHandler {
        target: "fractaledges"

        function quit(): void {
            root.restoreAnimations();
            root.shuttingDown = true;
            quitTimer.start();
        }
        function isRunning(): string {
            return "true";
        }
    }

    Timer {
        id: quitTimer

        interval: 200
        onTriggered: Qt.quit()
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: scope

            required property var modelData

            readonly property var mon: Hyprland.monitorFor(modelData)
            readonly property var ws: mon ? mon.activeWorkspace : null
            readonly property int wsId: ws ? ws.id : -1
            readonly property bool fractalActive: ((ws && ws.lastIpcObject) ? ws.lastIpcObject.tiledLayout : "") === root.layoutName
            // Monitor origin in Hyprland layout coordinates.
            readonly property real originX: mon ? (mon.x !== undefined ? mon.x : (mon.lastIpcObject ? mon.lastIpcObject.x : 0)) : 0
            readonly property real originY: mon ? (mon.y !== undefined ? mon.y : (mon.lastIpcObject ? mon.lastIpcObject.y : 0)) : 0

            property var status: null
            property var shownSeams: []
            property string shownKey: ""
            property var blockers: []
            property string blockersKey: ""
            property bool dragging: false
            property var dragSeam: null        // the seam being dragged, for the guide line
            property real dragRatio: 0
            property var pendingSeam: null
            property real pendingRatio: 0

            // Rebuild the handles, unless a drag is in progress: handles stay where they
            // were grabbed, so the drag maths is not disturbed by the layout reflowing.
            function rebuild(): void {
                if (root.shuttingDown) {
                    dragging = false;
                    dragSeam = null;
                    shownSeams = [];
                    return;
                }
                if (dragging)
                    return;
                const list = (fractalActive && status) ? Seams.clipSeams(Seams.seams(status, root.grab), blockers, 24) : [];
                // Only replace the handle windows when something actually changed.
                const key = JSON.stringify(list);
                if (key === shownKey)
                    return;
                shownKey = key;
                shownSeams = list;
            }

            function updateBlockers(): void {
                const list = Seams.floatingRects(root.clientsText, root.monitorsText, modelData.name, 3);
                const key = JSON.stringify(list);
                if (key === blockersKey)
                    return;
                blockersKey = key;
                blockers = list;
                rebuild();
            }

            function send(seam, ratio): void {
                Hyprland.dispatch("hl.dsp.layout(\"" + Seams.edgeCommand(seam, ratio) + "\")");
            }

            Connections {
                target: root

                function onShuttingDownChanged(): void {
                    scope.rebuild();
                }
                function onClientsTextChanged(): void {
                    scope.updateBlockers();
                }
                function onMonitorsTextChanged(): void {
                    scope.updateBlockers();
                }
            }

            Component.onCompleted: updateBlockers()

            onStatusChanged: rebuild()
            onFractalActiveChanged: rebuild()
            onWsIdChanged: {
                status = null;
                updateBlockers();
                rebuild();
            }

            FileView {
                path: scope.wsId >= 0 ? root.runtimeDir + "/ws-" + scope.wsId + ".json" : ""
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: {
                    // The layout may have been switched without a workspace event.
                    Hyprland.refreshWorkspaces();
                    scope.status = Seams.parse(text());
                }
                onLoadFailed: scope.status = null
            }

            // Leading + trailing throttle for live resizing.
            Timer {
                id: throttle

                interval: root.interval
                onTriggered: {
                    if (scope.pendingSeam) {
                        scope.send(scope.pendingSeam, scope.pendingRatio);
                        scope.pendingSeam = null;
                        restart();
                    }
                }
            }

            // The line that follows the pointer/finger while dragging. The handle windows are
            // frozen during a drag (moving a window under the pointer would corrupt the drag
            // maths), so this separate click-through window shows where the edge is going.
            PanelWindow {
                screen: scope.modelData
                visible: scope.dragSeam !== null
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "caelestia-fractal-guide"
                WlrLayershell.layer: WlrLayer.Top

                Guide {
                    anchors.fill: parent
                    seam: scope.dragSeam
                    ratio: scope.dragRatio
                    originX: scope.originX
                    originY: scope.originY
                    blockers: scope.blockers
                }
            }

            Variants {
                model: scope.shownSeams

                delegate: PanelWindow {
                    id: win

                    required property var modelData

                    screen: scope.modelData
                    anchors {
                        top: true
                        left: true
                    }
                    margins {
                        left: Math.max(0, Math.round(modelData.x - scope.originX))
                        top: Math.max(0, Math.round(modelData.y - scope.originY))
                    }
                    implicitWidth: Math.max(1, Math.round(modelData.w))
                    implicitHeight: Math.max(1, Math.round(modelData.h))
                    exclusionMode: ExclusionMode.Ignore
                    color: "transparent"
                    WlrLayershell.namespace: "caelestia-fractal-edge"
                    WlrLayershell.layer: WlrLayer.Top

                    EdgeStrip {
                        anchors.fill: parent
                        seam: win.modelData
                        onDragStarted: {
                            root.dragBegan();
                            scope.dragging = true;
                            scope.dragSeam = win.modelData;
                            scope.dragRatio = win.modelData.ratio;
                        }
                        onDragMoved: ratio => {
                            scope.dragRatio = ratio;
                            if (!root.live)
                                return;
                            if (throttle.running) {
                                scope.pendingSeam = win.modelData;
                                scope.pendingRatio = ratio;
                            } else {
                                scope.send(win.modelData, ratio);
                                throttle.start();
                            }
                        }
                        onDragFinished: ratio => {
                            throttle.stop();
                            scope.pendingSeam = null;
                            scope.send(win.modelData, ratio);
                            scope.dragSeam = null;
                            scope.dragging = false;
                            root.dragEnded();
                            scope.rebuild();
                        }
                    }
                }
            }
        }
    }
}
