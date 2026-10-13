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
import "Seams.js" as Seams

ShellRoot {
    id: root

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fractal-wm"
    readonly property string layoutName: "lua:fractal"
    // Handle thickness in px; bigger is easier to hit with a finger.
    readonly property int grab: parseInt(Quickshell.env("FRACTAL_EDGE_GRAB")) || 16

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
            property bool dragging: false
            property var pendingSeam: null
            property real pendingRatio: 0

            // Rebuild the handles, unless a drag is in progress: handles stay where they
            // were grabbed, so the drag maths is not disturbed by the layout reflowing.
            function rebuild(): void {
                if (dragging)
                    return;
                shownSeams = (fractalActive && status) ? Seams.seams(status, root.grab) : [];
            }

            function send(seam, ratio): void {
                Hyprland.dispatch("hl.dsp.layout(\"" + Seams.edgeCommand(seam, ratio) + "\")");
            }

            onStatusChanged: rebuild()
            onFractalActiveChanged: rebuild()
            onWsIdChanged: {
                status = null;
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

                interval: 33
                onTriggered: {
                    if (scope.pendingSeam) {
                        scope.send(scope.pendingSeam, scope.pendingRatio);
                        scope.pendingSeam = null;
                        restart();
                    }
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
                        onDragStarted: scope.dragging = true
                        onDragMoved: ratio => {
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
                            scope.dragging = false;
                            scope.rebuild();
                        }
                    }
                }
            }
        }
    }
}
