pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "Logic.js" as Logic

// PipeWire state + actions for the mixer. Device/stream state comes from Quickshell's
// Pipewire service; routing and the combined sink go through `pactl` (pipewire-pulse).
Singleton {
    id: root

    // --- State ---------------------------------------------------------------

    property list<PwNode> sinks: []      // real output devices (combined sink excluded)
    property list<PwNode> streams: []    // playback streams (apps)
    readonly property PwNode defaultSink: Pipewire.defaultAudioSink
    property PwNode combinedSink: null

    // Sink node names the user ticked for simultaneous output.
    property var members: []
    readonly property bool combinedActive: combineModuleId >= 0
    property int combineModuleId: -1
    property int linksRevision: 0
    property bool busy: false
    property string error: ""

    property string _restoreSinkName: ""
    property bool _selectCombinedWhenReady: false
    property var _inputIndex: ({})
    property var _pendingRoute: null
    property string _memberArg: "slaves"
    property var _retryMembers: null

    // --- Actions -------------------------------------------------------------

    function setDefault(node: PwNode): void {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setVolume(node: PwNode, v: real): void {
        if (node?.ready && node.audio) {
            node.audio.muted = false;
            node.audio.volume = Math.max(0, Math.min(1.5, v));
        }
    }

    function toggleMute(node: PwNode): void {
        if (node?.ready && node.audio)
            node.audio.muted = !node.audio.muted;
    }

    function isMember(node: PwNode): bool {
        return members.includes(node.name);
    }

    function setMember(node: PwNode, on: bool): void {
        const next = members.filter(n => n !== node.name);
        if (on)
            next.push(node.name);
        members = next;
        // Keep a running combined sink in sync with the ticked set.
        if (combinedActive && next.length >= 2)
            applyCombine();
    }

    // The sink a stream is currently linked to (null if none). Pass `linksRevision` from a
    // binding so QML re-evaluates when links change.
    function sinkOf(stream: PwNode, _rev: int): PwNode {
        for (const link of Pipewire.linkGroups.values) {
            if (link.source === stream)
                return link.target;
        }
        return null;
    }

    function streamName(stream: PwNode): string {
        return stream?.properties["application.name"] || stream?.description || stream?.name || "Unknown";
    }

    // Move an app's stream to another output.
    function routeStream(stream: PwNode, sink: PwNode): void {
        if (!stream || !sink)
            return;
        root._pendingRoute = {
            "serial": String(stream.properties["object.serial"]),
            "sinkName": sink.name
        };
        sinkInputsProc.running = true;
    }

    function applyCombine(): void {
        if (members.length < 2) {
            error = "Select at least two outputs to combine.";
            return;
        }
        error = "";
        busy = true;
        root._selectCombinedWhenReady = true;
        if (root._restoreSinkName === "" && defaultSink && defaultSink.name !== Logic.COMBINED_NAME)
            root._restoreSinkName = defaultSink.name;
        root._retryMembers = members.slice();
        root._memberArg = "slaves";
        if (combinedActive) {
            unloadProc.thenLoad = true;
            unloadProc.command = ["pactl", "unload-module", String(combineModuleId)];
            unloadProc.running = true;
        } else {
            loadCombine();
        }
    }

    function stopCombine(): void {
        if (!combinedActive)
            return;
        busy = true;
        unloadProc.thenLoad = false;
        unloadProc.command = ["pactl", "unload-module", String(combineModuleId)];
        unloadProc.running = true;
    }

    function loadCombine(): void {
        loadProc.command = Logic.combineCommand(root._retryMembers ?? members, root._memberArg);
        loadProc.running = true;
    }

    function refreshModules(): void {
        modulesProc.running = true;
    }

    // --- Node tracking -------------------------------------------------------

    function refreshNodes(): void {
        const s = [], st = [];
        let combined = null;
        for (const node of Pipewire.nodes.values) {
            if (!node.audio && !node.isStream && !node.isSink)
                continue;
            if (node.isStream) {
                if (node.audio && Logic.isPlaybackStream(node.properties))
                    st.push(node);
            } else if (node.isSink) {
                if (node.name === Logic.COMBINED_NAME)
                    combined = node;
                else
                    s.push(node);
            }
        }
        sinks = s;
        streams = st;
        combinedSink = combined;

        if (_selectCombinedWhenReady && combined) {
            _selectCombinedWhenReady = false;
            Pipewire.preferredDefaultAudioSink = combined;
        }
    }

    Component.onCompleted: {
        refreshNodes();
        refreshModules();
    }

    Connections {
        target: Pipewire.nodes

        function onValuesChanged(): void {
            root.refreshNodes();
        }
    }

    Connections {
        target: Pipewire.linkGroups

        function onValuesChanged(): void {
            root.linksRevision++;
        }
    }

    PwObjectTracker {
        objects: [...Pipewire.linkGroups.values]
    }

    PwObjectTracker {
        objects: [root.defaultSink, root.combinedSink, ...root.sinks, ...root.streams].filter(n => n)
    }

    // --- pactl processes -----------------------------------------------------

    Process {
        id: modulesProc

        command: ["pactl", "-f", "json", "list", "modules"]
        stdout: StdioCollector {
            onStreamFinished: root.combineModuleId = Logic.findCombineModule(text)
        }
    }

    Process {
        id: loadProc

        stdout: StdioCollector {
            id: loadOut
        }
        stderr: StdioCollector {
            id: loadErr
        }
        onExited: code => {
            if (code === 0) {
                root.combineModuleId = parseInt(loadOut.text.trim());
                root.busy = false;
                return;
            }
            // Some PipeWire versions name the member list `sinks=` instead of `slaves=`.
            if (root._memberArg === "slaves") {
                root._memberArg = "sinks";
                root.loadCombine();
                return;
            }
            root.busy = false;
            root._selectCombinedWhenReady = false;
            root.error = loadErr.text.trim() || "Could not create combined output.";
        }
    }

    Process {
        id: unloadProc

        property bool thenLoad

        stderr: StdioCollector {
            id: unloadErr
        }
        onExited: code => {
            if (code !== 0) {
                root.busy = false;
                root.error = unloadErr.text.trim() || "Could not remove combined output.";
                return;
            }
            root.combineModuleId = -1;
            if (thenLoad) {
                root.loadCombine();
                return;
            }
            root.busy = false;
            // Fall back to the output that was active before combining.
            const prev = root.sinks.find(n => n.name === root._restoreSinkName);
            if (prev)
                Pipewire.preferredDefaultAudioSink = prev;
            root._restoreSinkName = "";
        }
    }

    Process {
        id: sinkInputsProc

        command: ["pactl", "-f", "json", "list", "sink-inputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                const route = root._pendingRoute;
                root._pendingRoute = null;
                if (!route)
                    return;
                const idx = Logic.parseSinkInputs(text)[route.serial];
                if (idx === undefined) {
                    root.error = "Could not find that app's audio stream.";
                    return;
                }
                moveProc.command = ["pactl", "move-sink-input", String(idx), route.sinkName];
                moveProc.running = true;
            }
        }
    }

    Process {
        id: moveProc

        stderr: StdioCollector {
            id: moveErr
        }
        onExited: code => {
            if (code !== 0)
                root.error = moveErr.text.trim() || "Could not move stream.";
        }
    }
}
