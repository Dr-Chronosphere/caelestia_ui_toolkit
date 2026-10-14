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
import "Lod.js" as Lod

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

    // Cut animation tuning: how long a shrinking cut takes to settle, and how far (px) the line
    // pulls back from a floating window after cutting in (0 = no recoil).
    readonly property int settleMs: parseInt(Quickshell.env("FRACTAL_EDGE_SETTLE")) || 260
    readonly property real recoilPx: Quickshell.env("FRACTAL_EDGE_RECOIL") !== null && Quickshell.env("FRACTAL_EDGE_RECOIL") !== "" ? parseFloat(Quickshell.env("FRACTAL_EDGE_RECOIL")) : 6

    // Level of detail: tiles smaller than this get an icon card; tapping it zooms into the window.
    // FRACTAL_ICONS=off disables it.
    readonly property bool iconsEnabled: Quickshell.env("FRACTAL_ICONS") !== "off"
    // "Small" is a fraction of the work area (default 0.25 of its width or height); the px knobs
    // override it. Cards grow `cardOutset` px past tile sides that touch the work-area edge.
    readonly property real iconFrac: parseFloat(Quickshell.env("FRACTAL_ICON_MIN_FRAC")) || 0.25
    readonly property var iconMinW: parseFloat(Quickshell.env("FRACTAL_ICON_MIN_W")) || undefined
    readonly property var iconMinH: parseFloat(Quickshell.env("FRACTAL_ICON_MIN_H")) || undefined
    readonly property real cardOutset: Quickshell.env("FRACTAL_CARD_PAD") !== null && Quickshell.env("FRACTAL_CARD_PAD") !== "" ? parseFloat(Quickshell.env("FRACTAL_CARD_PAD")) : 0
    // Stacking: cards are Top, handles and the guide Overlay, so they always draw above the cards
    // (surfaces in one layer stack by creation order, which a new card would break).

    // The cards' backing is translucent and Hyprland blurs what is behind them (a layer rule).
    // FRACTAL_CARD_BLUR=off gives opaque cards instead.
    readonly property bool cardBlur: Quickshell.env("FRACTAL_CARD_BLUR") !== "off"

    // The icon for an app class (window `name` in the status file): its desktop entry's icon,
    // else the lower-cased class as an icon name; the card falls back to a lettered badge.
    function iconFor(cls: string): string {
        if (!cls)
            return "";
        const entry = DesktopEntries.heuristicLookup(cls);
        const name = (entry && entry.icon) ? entry.icon : cls.toLowerCase();
        return Quickshell.iconPath(name, "application-x-executable");
    }

    // Zoom the viewport onto one window (the layout's `zoom <node-id>`).
    function zoomTo(id: string): void {
        if (/^[A-Za-z0-9_-]+$/.test(id))
            Hyprland.dispatch("hl.dsp.layout(\"zoom " + id + "\")");
    }

    // FRACTAL_EDGE_DEBUG=1 logs what the overlay does (drags, handle windows appearing/vanishing,
    // floating windows changing) with a millisecond clock, to correlate with anything that looks off.
    readonly property bool debug: Quickshell.env("FRACTAL_EDGE_DEBUG") === "1"
    function dbg(msg: string): void {
        if (debug)
            console.log("[fractal-edges " + (Date.now() % 100000) + "] " + msg);
    }

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
        dbg("drag began");
        activeDrags++;
        restoreTimer.stop();
        if (!suspendAnimations || animSuspended || activeDrags !== 1)
            return;
        animProbe.running = true;
    }

    function dragEnded(): void {
        dbg("drag ended");
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

    // Hyprland slides/fades layer surfaces in and out (your layersIn/layersOut animations), which
    // shows up as a "ghost" of the guide line floating away when it is hidden. A layer rule
    // switches that off for our surfaces only; runtime rules are dropped by a config reload, so
    // re-apply on `configreloaded`.
    function applyLayerRule(): void {
        Quickshell.execDetached(["hyprctl", "eval", Seams.layerRuleCommand()]);
        if (cardBlur)
            Quickshell.execDetached(["hyprctl", "eval", Seams.cardBlurRuleCommand()]);
    }

    Component.onCompleted: {
        applyLayerRule();
        refreshFloating();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            if (event.name === "configreloaded")
                root.applyLayerRule();
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
            // Handle windows are keyed by seam ("a|b") and kept alive; only their geometry
            // updates. The window delegates read their seam from `seamMap`.
            property var seamKeys: []
            property var seamMap: ({})
            property string keysKey: ""
            property string mapKey: ""
            // Icon cards for tiles too small to use, keyed by node id and kept alive.
            property var cardKeys: []
            property var cardMap: ({})
            property string cardKeysKey: ""
            property string cardMapKey: ""
            property var blockers: []
            property string blockersKey: ""
            property bool dragging: false
            property var dragSeam: null        // the seam being dragged, for the guide line
            property bool settling: false
            property bool fadeGuide: false
            property real dragRatio: 0
            property var pendingSeam: null
            property real pendingRatio: 0

            // Rebuild the handles, unless a drag is in progress: handles stay where they
            // were grabbed, so the drag maths is not disturbed by the layout reflowing.
            // Apply a { map, keys } result of Lod.reconcile / Lod.purge. Windows are keyed by tile id
            // and kept alive; only their geometry and fade change.
            function applyCards(r): void {
                const newMapKey = JSON.stringify(r.map);
                if (newMapKey === cardMapKey)
                    return;
                cardMapKey = newMapKey;
                const newKeysKey = JSON.stringify(r.keys);
                if (newKeysKey !== cardKeysKey) {
                    root.dbg(modelData.name + ": icon cards " + newKeysKey);
                    cardKeysKey = newKeysKey;
                    // Old entries stay readable until their windows are gone.
                    const merged = {};
                    for (const k in cardMap)
                        merged[k] = cardMap[k];
                    for (const k in r.map)
                        merged[k] = r.map[k];
                    cardMap = merged;
                    cardKeys = r.keys;
                }
                cardMap = r.map;
                if (r.keys.some(k => r.map[k].leaving))
                    leaveTimer.restart();
            }

            // Cards follow their tiles live (including while a handle is dragged): they resize with the
            // tile, fade in as it shrinks below the threshold and out as it grows. A card hidden by a
            // floating window goes at once; one whose tile grew fades out first.
            function rebuildCards(): void {
                // Cards match where real windows sit inside their tiles (measured, so any gaps or
                // border setting works); FRACTAL_CARD_PAD grows (+) or shrinks (-) them further.
                const ins = Seams.measureInsets(root.clientsText, status) || {
                    "inner": 0,
                    "edge": 0
                };
                const opts = {
                    "frac": root.iconFrac,
                    "inset": ins.inner - root.cardOutset,
                    "outset": root.cardOutset - ins.edge,
                    "bounds": {
                        "x": originX,
                        "y": originY,
                        "w": modelData.width,
                        "h": modelData.height
                    }
                };
                if (root.iconMinW !== undefined)
                    opts.minW = root.iconMinW;
                if (root.iconMinH !== undefined)
                    opts.minH = root.iconMinH;
                const on = root.iconsEnabled && fractalActive && status;
                const fresh = on ? Lod.cards(status, blockers, opts) : [];
                const unblocked = on ? Lod.cards(status, [], opts).map(c => c.id) : [];
                applyCards(Lod.reconcile(cardMap, fresh, unblocked, Date.now()));
            }

            function rebuild(): void {
                if (root.shuttingDown) {
                    cardKeys = [];
                    cardMap = ({});
                    cardKeysKey = "";
                    cardMapKey = "";
                    dragging = false;
                    dragSeam = null;
                    seamKeys = [];
                    seamMap = ({});
                    keysKey = "";
                    mapKey = "";
                    return;
                }
                rebuildCards();
                if (dragging)
                    return;
                const all = (fractalActive && status) ? Seams.seams(status, root.grab) : [];
                // A handle exists while at least one stretch of its seam is grabbable.
                const keep = all.filter(s => Seams.pieces(s, blockers, 24).length > 0);
                const map = {};
                const keys = [];
                for (const s of keep) {
                    map[s.key] = s;
                    keys.push(s.key);
                }
                const newMapKey = JSON.stringify(map);
                if (newMapKey === mapKey)
                    return;
                mapKey = newMapKey;
                const newKeysKey = JSON.stringify(keys);
                root.dbg(modelData.name + ": handles " + (newKeysKey !== keysKey ? "CHANGED (windows created/destroyed) " + newKeysKey : "moved/resized (windows kept)"));
                if (newKeysKey !== keysKey) {
                    keysKey = newKeysKey;
                    // Old entries stay readable until their windows are gone.
                    const merged = {};
                    for (const k in seamMap)
                        merged[k] = seamMap[k];
                    for (const k in map)
                        merged[k] = map[k];
                    seamMap = merged;
                    seamKeys = keys;
                }
                seamMap = map;
            }

            function updateBlockers(): void {
                const list = Seams.floatingRects(root.clientsText, root.monitorsText, modelData.name, 3);
                const key = JSON.stringify(list);
                if (key === blockersKey)
                    return;
                blockersKey = key;
                blockers = list;
                root.dbg(modelData.name + ": floating windows now " + key);
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

            // Drop cards that finished fading out.
            Timer {
                id: leaveTimer

                interval: 280
                onTriggered: scope.applyCards(Lod.purge(scope.cardMap, Date.now(), 260))
            }

            // After release the guide springs to the limit, then fades out (so it cross-fades
            // with the handle bar instead of vanishing).
            Timer {
                id: settleTimer

                interval: 240
                onTriggered: {
                    root.dbg("guide fading");
                    scope.fadeGuide = true;
                    fadeTimer.restart();
                }
            }

            Timer {
                id: fadeTimer

                interval: 190
                onTriggered: {
                    scope.dragSeam = null;
                    scope.settling = false;
                    scope.fadeGuide = false;
                }
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
                WlrLayershell.layer: WlrLayer.Overlay

                Guide {
                    anchors.fill: parent
                    seam: scope.dragSeam
                    ratio: scope.dragRatio
                    originX: scope.originX
                    originY: scope.originY
                    blockers: scope.blockers
                    settling: scope.settling
                    fading: scope.fadeGuide
                    cutDuration: root.settleMs
                    cutRecoil: root.recoilPx
                }
            }

            // Icon cards cover tiles too small to use; tapping one zooms into that window.
            Variants {
                model: scope.cardKeys

                delegate: PanelWindow {
                    id: cardWin

                    required property string modelData

                    readonly property var card: scope.cardMap[modelData]
                    readonly property bool ready: card !== undefined && card !== null
                    readonly property var geo: ready ? card : ({
                            "id": "",
                            "label": "",
                            "title": "",
                            "x": 0,
                            "y": 0,
                            "w": 1,
                            "h": 1,
                            "alpha": 0,
                            "leaving": true
                        })

                    screen: scope.modelData
                    visible: ready
                    anchors {
                        top: true
                        left: true
                    }
                    margins {
                        left: Math.max(0, Math.round(geo.x - scope.originX))
                        top: Math.max(0, Math.round(geo.y - scope.originY))
                    }
                    implicitWidth: Math.max(1, Math.round(geo.w))
                    implicitHeight: Math.max(1, Math.round(geo.h))
                    exclusionMode: ExclusionMode.Ignore
                    color: "transparent"
                    WlrLayershell.namespace: "caelestia-fractal-card"
                    WlrLayershell.layer: WlrLayer.Top
                    // A faint (or fading) card takes no input: taps go to the window beneath.
                    mask: Region {
                        x: 0
                        y: 0
                        width: cardItem.interactive ? cardWin.width : 0
                        height: cardItem.interactive ? cardWin.height : 0
                    }

                    IconCard {
                        id: cardItem

                        anchors.fill: parent
                        alpha: cardWin.geo.alpha !== undefined ? cardWin.geo.alpha : 1
                        shown: !cardWin.geo.leaving
                        tint: root.cardBlur ? 0.62 : 1
                        iconSource: root.iconFor(cardWin.geo.label)
                        label: cardWin.geo.label
                        title: cardWin.geo.title
                        onActivated: root.zoomTo(cardWin.geo.id)
                    }
                }
            }

            Variants {
                model: scope.seamKeys

                delegate: PanelWindow {
                    id: win

                    required property string modelData

                    readonly property var seam: scope.seamMap[modelData]
                    readonly property bool ready: seam !== undefined && seam !== null
                    // Placeholder while the seam is being removed, so bindings never see undefined.
                    readonly property var geo: ready ? seam : ({
                            "key": "",
                            "axis": "x",
                            "x": 0,
                            "y": 0,
                            "w": 1,
                            "h": 1,
                            "ratio": 0.5,
                            "span": 1
                        })

                    // Input only where nothing floats over the seam; the window itself spans the
                    // whole seam so it never has to be rebuilt when a window moves.
                    function hit(i: int): var {
                        const r = strip.hitRects[i];
                        return r ? r : {
                            "x": 0,
                            "y": 0,
                            "w": 0,
                            "h": 0
                        };
                    }

                    screen: scope.modelData
                    visible: ready
                    anchors {
                        top: true
                        left: true
                    }
                    margins {
                        left: Math.max(0, Math.round(geo.x - scope.originX))
                        top: Math.max(0, Math.round(geo.y - scope.originY))
                    }
                    implicitWidth: Math.max(1, Math.round(geo.w))
                    implicitHeight: Math.max(1, Math.round(geo.h))
                    exclusionMode: ExclusionMode.Ignore
                    color: "transparent"
                    WlrLayershell.namespace: "caelestia-fractal-edge"
                    WlrLayershell.layer: WlrLayer.Overlay
                    mask: Region {
                        Region {
                            x: win.hit(0).x
                            y: win.hit(0).y
                            width: win.hit(0).w
                            height: win.hit(0).h
                        }
                        Region {
                            x: win.hit(1).x
                            y: win.hit(1).y
                            width: win.hit(1).w
                            height: win.hit(1).h
                        }
                        Region {
                            x: win.hit(2).x
                            y: win.hit(2).y
                            width: win.hit(2).w
                            height: win.hit(2).h
                        }
                        Region {
                            x: win.hit(3).x
                            y: win.hit(3).y
                            width: win.hit(3).w
                            height: win.hit(3).h
                        }
                        Region {
                            x: win.hit(4).x
                            y: win.hit(4).y
                            width: win.hit(4).w
                            height: win.hit(4).h
                        }
                        Region {
                            x: win.hit(5).x
                            y: win.hit(5).y
                            width: win.hit(5).w
                            height: win.hit(5).h
                        }
                    }

                    EdgeStrip {
                        id: strip

                        anchors.fill: parent
                        seam: win.geo
                        blockers: scope.blockers
                        cutDuration: root.settleMs
                        cutRecoil: root.recoilPx
                        onDragStarted: {
                            root.dragBegan();
                            settleTimer.stop();
                            fadeTimer.stop();
                            scope.fadeGuide = false;
                            scope.settling = false;
                            scope.dragging = true;
                            // Ratio first: the guide must not appear at the previous drag's ratio.
                            scope.dragRatio = win.geo.ratio;
                            scope.dragSeam = win.geo;
                        }
                        onDragMoved: (ratio, shown) => {
                            scope.dragRatio = shown;
                            if (!root.live)
                                return;
                            if (throttle.running) {
                                scope.pendingSeam = win.geo;
                                scope.pendingRatio = ratio;
                            } else {
                                scope.send(win.geo, ratio);
                                throttle.start();
                            }
                        }
                        onDragFinished: ratio => {
                            throttle.stop();
                            scope.pendingSeam = null;
                            scope.send(win.geo, ratio);
                            // The line springs back from any overshoot to the limit, then fades.
                            scope.settling = true;
                            scope.dragRatio = ratio;
                            settleTimer.restart();
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
