import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import CaelestiaUI
import "logic/Tabs.js" as Tabs
import "logic/Merge.js" as Merge

// Caelestia file manager: any number of explorer windows, each with tabs.
//
// Drag one explorer window over another (Super+drag, or whatever moves windows in your setup) and
// the one underneath blurs; leave it there for a moment and the two become one window with both
// windows' tabs. The compositor does the dragging, so the app finds out by sampling window
// geometry (see logic/Merge.js); `qs -p apps/files ipc call files drop` merges at once, which you
// can bind to the mouse-button release.
//
// Run:  QML_IMPORT_PATH=<repo>/qml qs -p apps/files      (or bin/caelestia-files)
ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    // Window translucency (0.3..1). The window is see-through; add a Hyprland window rule with blur
    // for it to frost the desktop behind (class "org.quickshell" / title "Files #*").
    readonly property real surfaceAlpha: {
        const v = parseFloat(Quickshell.env("FILES_OPACITY"));
        return v >= 0.3 && v <= 1 ? v : 0.92;
    }

    property var model: TabsModel {
        home: root.home
        onAllClosed: Qt.quit()
    }

    // Drag-to-merge: the explorer window being carried and the one it is over.
    property string carried: ""
    property string overWindow: ""
    readonly property bool merging: Quickshell.env("FILES_MERGE") !== "off"
    readonly property int settleMs: parseInt(Quickshell.env("FILES_MERGE_SETTLE")) || 450
    property var tracker: Merge.create()

    function merge(from: string, to: string): void {
        if (model.merge(from, to)) {
            carried = "";
            overWindow = "";
            tracker = Merge.create();
        }
    }

    function applySamples(text: string): void {
        const wins = Merge.samples(text).filter(w => model.winIndex(w.id) >= 0);
        const r = Merge.update(tracker, wins, Date.now(), { "settleMs": settleMs });
        carried = r.dragging;
        overWindow = r.target;
        if (r.drop)
            merge(r.drop.from, r.drop.to);
    }

    // Quickshell windows open floating on Hyprland. A window rule makes explorer windows tile like
    // any other app (rules are read when a window opens, so it is set before the first one, and
    // again after a config reload, which drops runtime rules). FILES_TILE=off skips it. The call is
    // wrapped in pcall, so a Hyprland whose rule syntax differs just ignores it.
    readonly property bool tile: Quickshell.env("FILES_TILE") !== "off"
    readonly property string tileRule: 'pcall(hl.window_rule, { name = "caelestia-files-tile", match = { title = "^Files #" }, tile = true })'

    function applyTileRule(): void {
        if (tile)
            Quickshell.execDetached(["hyprctl", "eval", tileRule]);
    }

    // Belt and braces: when one of our windows opens, tell Hyprland to un-float it directly (straight away, as the
    // event fires when it maps, and again after a beat), in case the window rule above is not honoured.
    property var untiled: ({})
    readonly property bool debugTile: Quickshell.env("FILES_DEBUG") === "1"

    function untile(address: string): void {
        const lua = 'pcall(function() hl.dispatch(hl.dsp.window.float({ action = "off", window = "address:0x' + address + '" })) end)';
        // Hyprland can decide a Quickshell window floats AFTER it maps (and after the first un-float
        // lands), so keep checking for about 3 s: whenever the window is reported floating, un-float
        // it; stop once it has read as tiled three times in a row. Without jq it just repeats the
        // command on a schedule (un-floating a tiled window is a no-op).
        const script = 'lua=\'' + lua + '\'; addr=0x' + address + '; ok=0; i=0; '
            // A window started from a keybind or launcher can lack the environment hyprctl needs
            // (the instance signature, a PATH with jq): fill both in, and log what happens.
            + 'log="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia-files/tile.log"; mkdir -p "$(dirname "$log")"; '
            + 'export PATH="$PATH:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"; '
            + 'if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -1); fi; '
            + 'echo "$(date +%T) window $addr: sig=${HYPRLAND_INSTANCE_SIGNATURE:-none} jq=$(command -v jq || echo none) hyprctl=$(command -v hyprctl || echo none)" >> "$log"; '
            + 'if command -v jq >/dev/null 2>&1; then '
            + 'while [ $i -lt 15 ] && [ $ok -lt 3 ]; do '
            + 'f=$(hyprctl clients -j 2>>"$log" | jq -r --arg a "$addr" \'.[] | select(.address == $a) | .floating\' 2>>"$log"); '
            + 'echo "$(date +%T)   floating=${f:-?}" >> "$log"; '
            + 'if [ "$f" = true ]; then hyprctl eval "$lua" >>"$log" 2>&1; ok=0; elif [ "$f" = false ]; then ok=$((ok+1)); fi; '
            + 'i=$((i+1)); sleep 0.2; done; '
            + 'else for d in 0 0.2 0.2 0.4 0.8 1.4; do sleep $d; hyprctl eval "$lua" >>"$log" 2>&1; done; fi; '
            + 'echo "$(date +%T)   done" >> "$log"';
        Quickshell.execDetached(["sh", "-c", script]);
    }

    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            if (event.name === "configreloaded")
                root.applyTileRule();
            // openwindow>>ADDRESS,WORKSPACE,CLASS,TITLE (the title may itself contain commas). The
            // title is not always set yet when the window opens, so windowtitlev2>>ADDRESS,TITLE is
            // watched too; each window is un-floated once, so a window you float on purpose stays.
            if (root.tile && (event.name === "openwindow" || event.name === "windowtitlev2")) {
                const parts = String(event.data).split(",");
                const title = parts.slice(event.name === "openwindow" ? 3 : 1).join(",");
                if (root.debugTile)
                    console.log("[files] " + event.name + " " + parts[0] + " title=" + title);
                if (/^[0-9a-f]+$/.test(parts[0]) && title.indexOf("Files #") === 0 && !root.untiled[parts[0]]) {
                    root.untiled[parts[0]] = true;
                    root.untile(parts[0]);
                }
            }
        }
    }

    Component.onCompleted: {
        applyTileRule();
        model.newWindow(Quickshell.env("FILES_START") || home);
    }

    // Sample window geometry only while there is something to merge into.
    Timer {
        interval: 70
        repeat: true
        running: root.merging && root.model.windows.length >= 2 && !sampler.running
        onTriggered: sampler.running = true
    }

    Process {
        id: sampler

        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: sampled

            waitForEnd: true
        }
        onExited: root.applySamples(String(sampled.text || ""))
    }

    IpcHandler {
        target: "files"

        function isRunning(): string {
            return "true";
        }
        function newWindow(path: string): void {
            root.model.newWindow(path);
        }
        function newTab(path: string): void {
            const w = root.model.windows;
            if (w.length === 0)
                root.model.newWindow(path);
            else
                root.model.addTab(w[w.length - 1].id, path);
        }
        // Merge the window being carried into the one it is over, without waiting for it to settle.
        function drop(): void {
            if (root.carried && root.overWindow)
                root.merge(root.carried, root.overWindow);
        }
    }

    Variants {
        model: root.model.windows.map(w => w.id)

        delegate: AppWindow {
            id: win

            required property string modelData
            readonly property var rec: root.model.windows[root.model.winIndex(modelData)]

            color: "transparent"
            title: "Files #" + modelData + " — " + tabs.activeLabel
            implicitWidth: 960
            implicitHeight: 680
            visible: true
            // The compositor closing the window (Super+Q) drops its tabs.
            onVisibleChanged: {
                if (!visible)
                    root.model.closeWindow(modelData);
            }

            FilesTabs {
                id: tabs

                anchors.fill: parent
                home: root.home
                tabs: win.rec ? win.rec.tabs : []
                active: win.rec ? win.rec.active : ""
                states: root.model.states
                surfaceAlpha: root.surfaceAlpha
                dropPreview: root.overWindow === win.modelData
                onNewTabRequested: root.model.addTab(win.modelData, "")
                onCloseTabRequested: id => root.model.closeTab(win.modelData, id)
                onActivateTabRequested: id => root.model.activateTab(win.modelData, id)
                onStateUpdated: (id, snap) => root.model.updateState(id, snap)
                onOpenRequested: p => Quickshell.execDetached(["xdg-open", p])
            }
        }
    }
}
