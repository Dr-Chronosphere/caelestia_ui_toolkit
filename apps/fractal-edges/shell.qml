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
import "DragDrop.js" as DragDrop
import "Follow.js" as Follow

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
    // FRACTAL_CARD_BLUR: "wallpaper" (default) backs cards with a pre-blurred copy of the wallpaper,
    // "off" gives opaque cards. FRACTAL_CARD_BLUR_AMOUNT (0..1, default 0.5) sets how heavy the blur is.
    readonly property string cardBlurMode: Quickshell.env("FRACTAL_CARD_BLUR") || "wallpaper"
    readonly property bool translucent: cardBlurMode !== "off"
    readonly property real blurAmount: parseFloat(Quickshell.env("FRACTAL_CARD_BLUR_AMOUNT")) >= 0 ? parseFloat(Quickshell.env("FRACTAL_CARD_BLUR_AMOUNT")) : 0.5

    // The wallpaper Caelestia is showing (its state file), or FRACTAL_WALLPAPER.
    property string wallpaperPath: Quickshell.env("FRACTAL_WALLPAPER") || ""
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    FileView {
        path: Quickshell.env("FRACTAL_WALLPAPER") ? "" : root.stateDir + "/caelestia/wallpaper/path.txt"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.wallpaperPath = text().trim()
    }
    readonly property url wallpaperUrl: (cardBlurMode === "wallpaper" && wallpaperPath) ? "file://" + wallpaperPath : ""

    // The icon for an app class (window `name` in the status file): its desktop entry's icon,
    // else the lower-cased class as an icon name; the card falls back to a lettered badge.
    function iconFor(cls: string): string {
        if (!cls)
            return "";
        const entry = DesktopEntries.heuristicLookup(cls);
        const name = (entry && entry.icon) ? entry.icon : cls.toLowerCase();
        return Quickshell.iconPath(name, "application-x-executable");
    }

    // Focus a window through the layout. A card is a layer surface over a small window, so hovering it
    // does not focus that window; without this, zoom-in (and the zoom gestures) would zoom into
    // whatever was focused before instead of the app under the pointer.
    function focusWindow(address: string): void {
        if (/^[A-Za-z0-9_x-]+$/.test(address || ""))
            Hyprland.dispatch("hl.dsp.layout(\"focus " + address + "\")");
    }

    // Zoom the viewport onto one window (the layout's `zoom <node-id>`).
    function zoomTo(id: string): void {
        if (/^[A-Za-z0-9_-]+$/.test(id))
            Hyprland.dispatch("hl.dsp.layout(\"zoom " + id + "\")");
    }

    // FRACTAL_EDGE_DEBUG=1 logs what the overlay does (drags, handle windows appearing/vanishing,
    // floating windows changing) with a millisecond clock, to correlate with anything that looks off.
    readonly property bool debug: Quickshell.env("FRACTAL_EDGE_DEBUG") === "1"
    // FRACTAL_EDGE_PROFILE=1 logs smoothness data every 2 s: UI-thread frame gaps (stalls), how
    // often the layout status changes and cards are rebuilt, how long a rebuild takes, and each
    // card's scale/alpha/mode when it changes. Read with `qs -p <dir> log`.
    readonly property bool profile: Quickshell.env("FRACTAL_EDGE_PROFILE") === "1"
    property var prof: ({
            "frames": 0,
            "slow": 0,
            "worst": 0,
            "status": 0,
            "rebuilds": 0,
            "rebuildMs": 0,
            "rebuildWorst": 0
        })
    property real lastFrameMs: 0
    FrameAnimation {
        running: root.profile
        onTriggered: {
            const now = Date.now();
            if (root.lastFrameMs > 0) {
                const gap = now - root.lastFrameMs;
                root.prof.frames++;
                if (gap > 24)
                    root.prof.slow++;
                root.prof.worst = Math.max(root.prof.worst, gap);
            }
            root.lastFrameMs = now;
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.profile
        onTriggered: {
            const p = root.prof;
            if (p.frames > 0 || p.status > 0) {
                console.log("[fractal-prof " + (Date.now() % 100000) + "] frames=" + p.frames + " slow(>24ms)=" + p.slow + " worstGap=" + p.worst + "ms | status=" + p.status + " rebuilds=" + p.rebuilds + " avgRebuild=" + (p.rebuilds ? (p.rebuildMs / p.rebuilds).toFixed(2) : 0) + "ms worstRebuild=" + p.rebuildWorst + "ms");
            }
            root.prof = {
                "frames": 0,
                "slow": 0,
                "worst": 0,
                "status": 0,
                "rebuilds": 0,
                "rebuildMs": 0,
                "rebuildWorst": 0
            };
        }
    }

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
        if (!roundingProc.running)
            roundingProc.running = true;
        if (!animProc.running)
            animProc.running = true;
        Quickshell.execDetached(["hyprctl", "eval", Seams.layerRuleCommand()]);
    }

    Component.onCompleted: {
        applyLayerRule();
        roundingProc.running = true;
        animProc.running = true;
        refreshFloating();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            if (event.name === "configreloaded")
                root.applyLayerRule();
            root.ddHandleEvent(event.name, String(event.data));
            if (event.name === "workspace" || event.name === "workspacev2" || event.name === "createworkspacev2" || event.name === "focusedmonv2" || event.name === "configreloaded")
                wsRefresh.restart();
            if (root.floatEvents.indexOf(event.name) >= 0)
                floatDebounce.restart();
        }
    }

    // Workspace records (their layout flag) go stale after a switch; refresh them shortly after.
    Timer {
        id: wsRefresh

        interval: 120
        onTriggered: Hyprland.refreshWorkspaces()
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

    // The window corner radius (decoration:rounding), so cards match the windows they cover.
    // FRACTAL_CARD_RADIUS overrides; refreshed on config reload.
    property real windowRounding: -1
    readonly property real cardRadius: parseFloat(Quickshell.env("FRACTAL_CARD_RADIUS")) >= 0 ? parseFloat(Quickshell.env("FRACTAL_CARD_RADIUS")) : (windowRounding >= 0 ? windowRounding : -1)

    Process {
        id: roundingProc

        command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
        stdout: StdioCollector {
            id: roundingOut

            waitForEnd: true
        }
        onExited: {
            const v = Seams.parseRounding(String(roundingOut.text || ""));
            if (v !== null)
                root.windowRounding = v;
        }
    }

    // --- cards that follow their windows ---------------------------------------------------------
    // While Hyprland animates windows (a zoom, a reflow) the card tracks the window's CURRENT rect
    // (polled from `hyprctl clients -j`, which reports the animated position) instead of jumping to the
    // settled one; on a workspace switch the old workspace's cards slide out and the new one's slide in
    // like the workspaces do. FRACTAL_EDGE_FOLLOW=off / FRACTAL_EDGE_WS_SLIDE=off disable each.
    readonly property bool followCards: Quickshell.env("FRACTAL_EDGE_FOLLOW") !== "off"
    readonly property bool slideCards: Quickshell.env("FRACTAL_EDGE_WS_SLIDE") !== "off"
    property var wsAnim: null            // the workspaces animation { ms, curve, style }, or null if off
    property var moveAnim: null          // the windowsMove animation (what windows and so cards move with)

    Process {
        id: animProc

        command: ["hyprctl", "animations", "-j"]
        stdout: StdioCollector {
            id: animOut

            waitForEnd: true
        }
        onExited: {
            const t = String(animOut.text || "");
            root.wsAnim = Follow.parseAnimation(t, "workspaces");
            root.moveAnim = Follow.parseAnimation(t, "windowsMove");
        }
    }

    // --- dragging a tiled window: show where it will land, and tell the layout ------------------
    // Hyprland floats a tiled window while it is dragged and re-tiles it on release, and the layout
    // would put it next to the FOCUSED tile. So: when a tile floats and the pointer starts moving,
    // poll the pointer, find the tile and side under it, highlight where the window would go, and send
    // the layout a `drop-intent` so the re-tiled window lands exactly there. FRACTAL_EDGE_DRAG=off
    // disables it.
    readonly property bool dragDrop: Quickshell.env("FRACTAL_EDGE_DRAG") !== "off"
    // The middle of a tile (FRACTAL_EDGE_SWAP_SIZE of it, default 0.3; 0 = never) swaps the two windows;
    // anywhere else the window goes to the side of the tile the pointer is on.
    readonly property real dragSwapSize: Quickshell.env("FRACTAL_EDGE_SWAP_SIZE") !== "" && Quickshell.env("FRACTAL_EDGE_SWAP_SIZE") !== null && !isNaN(parseFloat(Quickshell.env("FRACTAL_EDGE_SWAP_SIZE"))) ? parseFloat(Quickshell.env("FRACTAL_EDGE_SWAP_SIZE")) : 0.3
    // Screen-edge zones: this fraction of the work area's width/height at its edges (0 = off).
    readonly property real dragBand: !isNaN(parseFloat(Quickshell.env("FRACTAL_EDGE_SCREEN_BAND"))) ? parseFloat(Quickshell.env("FRACTAL_EDGE_SCREEN_BAND")) : 0.1
    // Tabbable windows (the file explorer) are left to merge by drag-and-drop when carried over each
    // other; while this is on (bind `bin/caelestia-fractal-edges layoutdrop toggle|on|off`) the layout
    // drop applies to them too.
    property bool forceLayout: false
    // Dragging a window into the extreme left/right strip of the screen and holding it there carries
    // it to the previous/next workspace. FRACTAL_EDGE_WS_EDGE=off disables; _PX is the strip's width
    // (default 24), _MS the hold time (default 600).
    readonly property bool wsEdge: Quickshell.env("FRACTAL_EDGE_WS_EDGE") !== "off"
    readonly property real wsEdgePx: !isNaN(parseFloat(Quickshell.env("FRACTAL_EDGE_WS_EDGE_PX"))) ? parseFloat(Quickshell.env("FRACTAL_EDGE_WS_EDGE_PX")) : 24
    readonly property int wsEdgeMs: parseInt(Quickshell.env("FRACTAL_EDGE_WS_EDGE_MS")) || 600
    property string hopSide: ""          // "prev" | "next" while the pointer is in a strip
    property string hopMon: ""
    property int hopTargetWs: 0
    property real hopSince: 0
    property real hopProgress: 0
    property real hopCooldown: 0
    property string hopWindow: ""
    property int hopNextWs: 0
    property var ddTracker: DragDrop.create()
    property var tilesByMon: ({})
    property string ddDragging: ""
    property bool ddRunning: false      // the pointer poll (not reactive on the tracker, so tracked here)
    property string dropMon: ""
    property var dropRect: null          // {x, y, w, h} in layout coordinates, or null
    property string dropZone: ""
    property string intentKey: ""
    property string heldFor: ""
    property var lastCursor: ({
            "x": 0,
            "y": 0
        })

    function ddActive(): bool {
        return dragDrop && (ddTracker.cand !== null || ddTracker.drag !== null);
    }

    function ddStop(): void {
        ddDragging = "";
        dropRect = null;
        dropMon = "";
        dropZone = "";
        intentKey = "";
        heldFor = "";
        hopSide = "";
        hopMon = "";
        hopProgress = 0;
    }

    function ddHandleEvent(name: string, data: string): void {
        if (!dragDrop)
            return;
        if (name === "changefloatingmode") {
            const ev = DragDrop.parseFloatEvent(data);
            if (!ev)
                return;
            const r = DragDrop.floatEvent(ddTracker, ev.address, ev.floating, lastCursor, Date.now());
            dbg("float event " + ev.address + " floating=" + ev.floating + " -> " + (r || "ignored"));
            if (r === "end")
                ddStop();
            ddRunning = ddActive();
        } else if (name === "closewindow") {
            DragDrop.closed(ddTracker, "0x" + String(data).toLowerCase());
            if (!ddTracker.drag)
                ddStop();
            ddRunning = ddActive();
        }
    }

    // Carry the dragged window to workspace `to`: first let its slot go on this workspace's layout, then
    // move the window (the Lua API is best-effort: tried with follow, then move + focus).
    function hopWorkspace(address: string, to: int): void {
        dbg("workspace hop: " + address + " -> " + to);
        hopCooldown = Date.now() + 900;
        hopSince = hopCooldown;
        hopProgress = 0;
        if (!/^[A-Za-z0-9_x-]+$/.test(address))
            return;
        Hyprland.dispatch("hl.dsp.layout(\"drop-intent clear\")");
        Hyprland.dispatch("hl.dsp.layout(\"drag-release " + address + "\")");
        hopWindow = address;
        hopNextWs = to;
        hopDelay.restart();
    }

    Timer {
        id: hopDelay

        interval: 120
        onTriggered: {
            if (!hopProc.running)
                hopProc.running = true;
        }
    }

    Process {
        id: hopProc

        command: ["hyprctl", "eval", 'local w = "address:' + root.hopWindow + '"; local n = "' + root.hopNextWs + '"; ' + 'local ok = pcall(function() hl.dispatch(hl.dsp.window.move({ workspace = n, follow = true, window = w })) end); ' + 'if not ok then pcall(function() hl.dispatch(hl.dsp.window.move({ workspace = n, window = w })) end); pcall(function() hl.dispatch(hl.dsp.focus({ workspace = n })) end) end']
        stdout: StdioCollector {
            id: hopOut

            waitForEnd: true
        }
        onExited: root.dbg("workspace hop result: " + String(hopOut.text || "").trim())
    }

    function ddPointer(p): void {
        lastCursor = p;
        const r = DragDrop.pointer(ddTracker, p, Date.now());
        ddDragging = r.drag;
        ddRunning = ddActive();
        if (!r.drag) {
            if (dropRect !== null)
                ddStop();
            return;
        }
        // The extreme left/right strip: hold the window there to carry it to the neighbouring workspace.
        let hopping = false;
        if (wsEdge) {
            for (const name in tilesByMon) {
                const info = tilesByMon[name];
                const side = DragDrop.edgeHop(p, info.mon, wsEdgePx);
                const to = side ? DragDrop.hopTarget(info.ws, side) : 0;
                if (!side || !to)
                    continue;
                hopping = true;
                const now = Date.now();
                if (hopSide !== side || hopMon !== name) {
                    hopSide = side;
                    hopMon = name;
                    hopTargetWs = to;
                    hopSince = now;
                }
                hopProgress = Math.min(1, Math.max(0, (now - Math.max(hopSince, hopCooldown)) / wsEdgeMs));
                if (hopProgress >= 1 && now >= hopCooldown)
                    hopWorkspace(r.drag, to);
                break;
            }
        }
        if (!hopping) {
            hopSide = "";
            hopMon = "";
            hopProgress = 0;
        } else {
            // no drop target while hopping: clear any intent aimed at this workspace
            if (intentKey !== "") {
                intentKey = "";
                Hyprland.dispatch("hl.dsp.layout(\"drop-intent clear\")");
            }
            dropRect = null;
            dropZone = "";
            return;
        }
        // The edges of the screen come first: a half or a quadrant, whatever windows exist. Then the
        // tile under the pointer (its middle swaps, elsewhere the side the pointer is on).
        let hit = null, mon = "";
        for (const name in tilesByMon) {
            const info = tilesByMon[name];
            const zone = DragDrop.screenZone(p, info.area, { "band": dragBand });
            let t = zone ? DragDrop.screenTarget(zone, info.area) : DragDrop.targetAt(p, info.tiles, r.drag, { "swapSize": dragSwapSize });
            // explorer window over another explorer window: that app merges them into tabs
            if (t && !zone && !forceLayout && DragDrop.dragIsTabbable(ddTracker, r.drag) && DragDrop.targetIsTabbable(info.tiles, t.address)) {
                dbg("drag over a tabbable window: leaving it to the app (layoutdrop on to override)");
                t = null;
            }
            if (t) {
                hit = t;
                mon = name;
                break;
            }
        }
        if (heldFor !== r.drag) {
            // confirmed as a drag: keep the window's slot so the other tiles do not reflow
            heldFor = r.drag;
            if (/^[A-Za-z0-9_x-]+$/.test(r.drag))
                Hyprland.dispatch("hl.dsp.layout(\"drag-hold " + r.drag + "\")");
        }
        const key = hit ? r.drag + ">" + hit.address + ":" + hit.zone : "";
        if (key !== intentKey) {
            intentKey = key;
            const cmd = DragDrop.intentCommand(r.drag, hit);
            dbg("drop target " + (key || "none"));
            if (cmd)
                Hyprland.dispatch("hl.dsp.layout(\"" + cmd + "\")");
        }
        dropMon = mon;
        dropRect = hit ? DragDrop.highlight(hit) : null;
        dropZone = hit ? hit.zone : "";
    }

    Timer {
        id: cursorTimer

        interval: 33
        repeat: true
        running: root.ddRunning
        onTriggered: {
            if (!cursorProc.running)
                cursorProc.running = true;
        }
    }

    Process {
        id: cursorProc

        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            id: cursorOut

            waitForEnd: true
        }
        onExited: {
            const p = DragDrop.parseCursor(String(cursorOut.text || ""));
            if (p)
                root.ddPointer(p);
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
        // Let the layout drop apply to tabbable windows too (while held / toggled).
        function layoutDrop(on: bool): void {
            root.forceLayout = on;
        }
        function layoutDropToggle(): void {
            root.forceLayout = !root.forceLayout;
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
            // --- following windows through transitions ---
            property var liveRects: ({})
            property bool followOn: false
            property int followStable: 0
            property real followUntil: 0
            // Workspace slide: the old workspace's cards (a snapshot) and the progress of the slide.
            property var slideSnap: null
            property int slideDir: 1
            property real slideT: 1
            property int lastWs: -1
            readonly property bool sliding: slideT < 1
            readonly property string slideStyle: root.wsAnim ? root.wsAnim.style : "slide"

            function startFollow(): void {
                if (!root.followCards || dragging || sliding)
                    return;
                followUntil = Date.now() + 1600;
                followStable = 0;
                followOn = true;
            }

            function onFollowSample(text: string): void {
                const rects = Follow.rectsByAddress(text);
                const list = [];
                for (const k in cardMap)
                    list.push(cardMap[k]);
                const moving = Follow.transitioning(list, rects, root.cardOutset);
                liveRects = rects;
                if (moving) {
                    followStable = 0;
                    followUntil = Math.max(followUntil, Date.now() + 400);
                } else {
                    followStable++;
                }
                // While a window is being dragged its card keeps following it (the dragged window is
                // floating under the pointer; its tile is just a held slot), however long that takes.
                const carried = root.ddDragging !== "";
                if (carried)
                    followUntil = Date.now() + 400;
                if ((!carried && (followStable >= 3 || Date.now() > followUntil)) || dragging || sliding) {
                    followOn = false;
                    liveRects = ({});
                }
            }

            // A carried window is sampled as fast as the process round trip allows.
            Connections {
                target: root

                function onDdDraggingChanged(): void {
                    if (root.ddDragging !== "")
                        scope.startFollow();
                }
            }

            Timer {
                interval: root.ddDragging !== "" ? 16 : 33
                repeat: true
                running: scope.followOn
                onTriggered: {
                    if (!followProc.running)
                        followProc.running = true;
                }
            }

            Process {
                id: followProc

                command: ["hyprctl", "clients", "-j"]
                stdout: StdioCollector {
                    id: followOut

                    waitForEnd: true
                }
                onExited: scope.onFollowSample(String(followOut.text || ""))
            }

            NumberAnimation {
                id: slideAnim

                target: scope
                property: "slideT"
                from: 0
                to: 1
                duration: root.wsAnim ? root.wsAnim.ms : 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.wsAnim ? root.wsAnim.curve.concat([1, 1]) : [0, 0, 1, 1, 1, 1]
                onFinished: scope.slideSnap = null
            }

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
                // Not restarted while running, or constant updates would starve the purge.
                if (r.keys.some(k => r.map[k].leaving) && !leaveTimer.running)
                    leaveTimer.restart();
            }

            // Cards follow their tiles live (including while a handle is dragged): they resize with the
            // tile, fade in as it shrinks below the threshold and out as it grows. A card hidden by a
            // floating window goes at once; one whose tile grew fades out first.
            // Cards track their tile directly while a handle is held down (no easing, and pausing
            // does nothing); letting go settles them: each finishes fading to fully in or fully out,
            // gradually. Layout changes with no drag (a window opening, say) settle at once.
            property bool cardsIdle: true
            onCardsIdleChanged: rebuildCards()
            // A beat after release, so the layout's final size has arrived before cards pick a side.
            onDraggingChanged: {
                if (dragging) {
                    holdTimer.stop();
                    cardsIdle = false;
                } else {
                    holdTimer.restart();
                }
            }
            Timer {
                id: holdTimer

                interval: 140
                onTriggered: scope.cardsIdle = true
            }
            // Where windows sit inside their tiles. Measured only once the layout has stopped
            // moving (the client list is polled on events, so mid-drag or mid-animation it does not
            // match the live tile boxes) and kept between drags, so one app's size limits or
            // animation can't skew another's card.
            property var insets: ({
                    "inner": 0,
                    "edge": 0
                })
            function remeasure(): void {
                if (!cardsIdle || !status)
                    return;
                const m = Seams.measureInsets(root.clientsText, status);
                if (m && (m.inner !== insets.inner || m.edge !== insets.edge)) {
                    insets = m;
                    rebuildCards();
                }
            }
            Timer {
                id: measureTimer

                property bool fetched: false

                interval: 600
                onTriggered: {
                    if (!scope.cardsIdle)
                        return;
                    if (!fetched) {
                        fetched = true;
                        root.refreshFloating();
                        interval = 250;
                        restart();
                    } else {
                        fetched = false;
                        interval = 600;
                        scope.remeasure();
                    }
                }
            }

            function rebuildCards(): void {
                // Cards match where real windows sit inside their tiles (measured, so any gaps or
                // border setting works); FRACTAL_CARD_PAD grows (+) or shrinks (-) them further.
                const ins = insets;
                const opts = {
                    "frac": root.iconFrac,
                    "inset": ins.inner - root.cardOutset,
                    "outset": root.cardOutset - ins.edge,
                    "prev": cardMap,
                    "idle": cardsIdle,
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
                const t0 = Date.now();
                const on = root.iconsEnabled && fractalActive && status;
                const fresh = on ? Lod.cards(status, blockers, opts) : [];
                const unblocked = on ? Lod.cards(status, [], opts).map(c => c.id) : [];
                applyCards(Lod.reconcile(cardMap, fresh, unblocked, Date.now()));
                if (root.profile) {
                    const ms = Date.now() - t0;
                    root.prof.rebuilds++;
                    root.prof.rebuildMs += ms;
                    root.prof.rebuildWorst = Math.max(root.prof.rebuildWorst, ms);
                    fresh.forEach(c => console.log("[fractal-prof " + (Date.now() % 100000) + "] card " + c.id + " scale=" + c.scale.toFixed(3) + " alpha=" + c.alpha.toFixed(2) + " mode=" + c.mode + (cardsIdle ? " idle" : "")));
                }
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

            onStatusChanged: {
                const tl = DragDrop.tiles(status);
                DragDrop.seeTiles(root.ddTracker, tl);
                const m = Object.assign({}, root.tilesByMon);
                m[modelData.name] = {
                    "tiles": tl,
                    "area": status ? status.area : null,
                    "mon": {
                        "x": originX,
                        "y": originY,
                        "w": modelData.width,
                        "h": modelData.height
                    },
                    "ws": wsId
                };
                root.tilesByMon = m;
                if (root.profile)
                    root.prof.status++;
                measureTimer.fetched = false;
                measureTimer.interval = 600;
                measureTimer.restart();
                rebuild();
            }
            onWsIdChanged: {
                // Slide the old workspace's cards out (a snapshot) and the new one's in, with the
                // workspace animation; otherwise they would pop while the windows slide.
                if (root.slideCards && root.wsAnim && lastWs > 0 && wsId > 0 && wsId !== lastWs) {
                    if (cardKeys.length > 0)
                        slideSnap = {
                            "keys": cardKeys,
                            "map": cardMap
                        };
                    slideDir = wsId > lastWs ? 1 : -1;
                    cardKeys = [];
                    cardMap = ({});
                    cardKeysKey = "";
                    cardMapKey = "";
                    followOn = false;
                    slideAnim.restart();
                }
                if (wsId > 0)
                    lastWs = wsId;
                status = null;
                root.dbg(modelData.name + ": workspace " + wsId + " layout=" + (ws && ws.lastIpcObject ? ws.lastIpcObject.tiledLayout : "?") + " active=" + fractalActive);
                updateBlockers();
                rebuild();
                // The workspace's layout flag can lag the switch; ask Hyprland again.
                Hyprland.refreshWorkspaces();
                statusRetry.restart();
            }
            onFractalActiveChanged: {
                root.dbg(modelData.name + ": fractal layout active=" + fractalActive + " (workspace " + wsId + ")");
                rebuild();
                if (fractalActive)
                    statusFile.reload();
            }

            // A workspace's status file may not exist yet when you switch to it (fractal-wm writes
            // it when it first lays that workspace out), and a missing file cannot be watched, so
            // the FileView would never see it appear. Retry until it loads.
            Timer {
                id: statusRetry

                interval: 400
                repeat: true
                running: scope.wsId >= 0 && scope.status === null && scope.fractalActive
                onTriggered: statusFile.reload()
            }

            FileView {
                id: statusFile

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

            // Highlight of where a dragged window will land (click-through).
            PanelWindow {
                screen: scope.modelData
                visible: root.dragDrop && ((root.dropRect !== null && root.dropMon === scope.modelData.name) || (root.hopSide !== "" && root.hopMon === scope.modelData.name))
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "fractal-edges-drop"
                WlrLayershell.layer: WlrLayer.Overlay

                WsHopHint {
                    anchors.fill: parent
                    side: root.hopMon === scope.modelData.name ? root.hopSide : ""
                    progress: root.hopProgress
                    workspace: root.hopTargetWs
                    stripWidth: root.wsEdgePx
                }

                DropHighlight {
                    anchors.fill: parent
                    shown: root.dropRect !== null
                    zone: root.dropZone
                    target: root.dropRect ? Qt.rect(root.dropRect.x - scope.originX, root.dropRect.y - scope.originY, root.dropRect.w, root.dropRect.h) : Qt.rect(0, 0, 0, 0)
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
                WlrLayershell.namespace: "fractal-edges-guide"
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

            // Input regions of the first few interactive cards, in card order: [{x, y, w, h}] relative
            // to the screen. A faint (or fading) card takes no input: taps go to the window beneath.
            function cardRect(i: int): var {
                const g = cardMap[cardKeys[i]];
                if (!g || g.leaving || !(g.alpha > 0.3))
                    return {
                        "x": 0,
                        "y": 0,
                        "w": 0,
                        "h": 0
                    };
                return {
                    "x": Math.round(g.x - originX),
                    "y": Math.round(g.y - originY),
                    "w": Math.round(g.w),
                    "h": Math.round(g.h)
                };
            }

            // Icon cards cover tiles too small to use; tapping one zooms into that window. All of a
            // monitor's cards live in ONE screen-sized surface and are moved/resized as items:
            // resizing a layer surface per card per frame (a configure round-trip each) is what made
            // live card resizing stutter. Only the card rectangles take input.
            PanelWindow {
                screen: scope.modelData
                // Kept mapped whenever cards are possible, not only while one exists: opening the
                // surface, decoding the wallpaper and compiling the blur shaders on the first card
                // cost 70-95 ms stalls in the profile log. An idle surface is empty and takes no input.
                visible: root.iconsEnabled && scope.fractalActive && !root.shuttingDown
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                WlrLayershell.namespace: "fractal-edges-card"
                WlrLayershell.layer: WlrLayer.Top
                mask: Region {
                    CardRegion { rect: scope.cardRect(0) }
                    CardRegion { rect: scope.cardRect(1) }
                    CardRegion { rect: scope.cardRect(2) }
                    CardRegion { rect: scope.cardRect(3) }
                    CardRegion { rect: scope.cardRect(4) }
                    CardRegion { rect: scope.cardRect(5) }
                    CardRegion { rect: scope.cardRect(6) }
                    CardRegion { rect: scope.cardRect(7) }
                    CardRegion { rect: scope.cardRect(8) }
                    CardRegion { rect: scope.cardRect(9) }
                    CardRegion { rect: scope.cardRect(10) }
                    CardRegion { rect: scope.cardRect(11) }
                }

                // Warm-up: one faint, tiny card keeps the wallpaper decoded and the blur/mask
                // pipelines compiled, so the first real card appears without a hitch.
                IconCard {
                    width: 24
                    height: 24
                    alpha: 0.01
                    smooth: false
                    tint: 0
                    backdrop: root.wallpaperUrl
                    backdropW: scope.modelData.width
                    backdropH: scope.modelData.height
                    blurAmount: root.blurAmount
                    cornerRadius: root.cardRadius
                }

                // The previous workspace's cards, sliding out while the new ones slide in.
                Repeater {
                    model: scope.slideSnap ? scope.slideSnap.keys : []

                    delegate: IconCard {
                        required property string modelData

                        readonly property var geo: scope.slideSnap ? (scope.slideSnap.map[modelData] ?? null) : null
                        readonly property var slide: Follow.slideOffset(scope.slideDir, scope.slideStyle, false, scope.slideT, scope.modelData.width, scope.modelData.height)

                        visible: geo !== null
                        x: geo ? Math.round(geo.x - scope.originX + slide.x) : 0
                        y: geo ? Math.round(geo.y - scope.originY + slide.y) : 0
                        width: geo ? Math.max(1, Math.round(geo.w)) : 1
                        height: geo ? Math.max(1, Math.round(geo.h)) : 1
                        startShown: true
                        smooth: false
                        shown: true
                        alpha: geo && geo.alpha !== undefined ? geo.alpha : 1
                        tint: root.translucent ? 0.55 : 1
                        backdrop: root.wallpaperUrl
                        backdropX: x
                        backdropY: y
                        backdropW: scope.modelData.width
                        backdropH: scope.modelData.height
                        blurAmount: root.blurAmount
                        cornerRadius: root.cardRadius
                        iconSource: geo ? root.iconFor(geo.label) : ""
                        label: geo ? geo.label : ""
                        title: geo ? geo.title : ""
                    }
                }

                Repeater {
                    model: scope.cardKeys

                    delegate: IconCard {
                        id: cardItem

                        required property string modelData

                        readonly property var geo: scope.cardMap[modelData] ?? ({
                                "id": "",
                                "label": "",
                                "title": "",
                                "x": scope.originX,
                                "y": scope.originY,
                                "w": 1,
                                "h": 1,
                                "alpha": 0,
                                "leaving": true
                            })

                        // While a transition is under way the card tracks its window's current rect.
                        readonly property var live: scope.followOn ? scope.liveRects[geo.address] : undefined
                        readonly property var rect: live ? Follow.cardFromLive(live, root.cardOutset) : geo
                        readonly property var slide: scope.sliding ? Follow.slideOffset(scope.slideDir, scope.slideStyle, true, scope.slideT, scope.modelData.width, scope.modelData.height) : ({
                                "x": 0,
                                "y": 0
                            })

                        x: Math.round(rect.x - scope.originX + slide.x)
                        y: Math.round(rect.y - scope.originY + slide.y)
                        width: Math.max(1, Math.round(rect.w))
                        height: Math.max(1, Math.round(rect.h))
                        // A card made during a slide is simply there (no fade-in from nothing).
                        startShown: scope.sliding
                        // The card travels with the compositor's own animation (duration and bezier from
                        // `hyprctl animations -j`), started when the layout changes, so it moves in step
                        // with its window with no polling lag. A carried window (a drag) is followed by
                        // sampling its position instead, with a short linear glide between samples.
                        moveEnabled: !scope.sliding && !scope.dragging && !root.animSuspended && (scope.followOn || root.moveAnim !== null)
                        moveMs: scope.followOn ? (root.ddDragging !== "" ? 18 : 45) : (root.moveAnim ? root.moveAnim.ms : 0)
                        moveCurve: root.moveAnim ? root.moveAnim.curve : [0, 0, 1, 1]
                        moveLinear: scope.followOn
                        shown: !geo.leaving
                        // Opacity eases only for a settled card (after mouse-up, or no drag at all) or one
                        // leaving; while you drag it tracks the tile directly. The flag travels in the
                        // same card record as the alpha and is declared BEFORE it, so by the time the
                        // new alpha is written the Behavior already knows whether to ease (toggling it
                        // from a separate property raced, and the fade snapped).
                        smooth: !!geo.settle || !!geo.leaving
                        alpha: geo.alpha !== undefined ? geo.alpha : 1
                        tint: root.translucent ? 0.55 : 1
                        backdrop: root.wallpaperUrl
                        backdropX: x
                        backdropY: y
                        backdropW: scope.modelData.width
                        backdropH: scope.modelData.height
                        blurAmount: root.blurAmount
                        cornerRadius: root.cardRadius
                        iconSource: root.iconFor(geo.label)
                        label: geo.label
                        title: geo.title
                        onActivated: root.zoomTo(geo.id)
                        onHovered: root.focusWindow(geo.address)
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
                    WlrLayershell.namespace: "fractal-edges-edge"
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
