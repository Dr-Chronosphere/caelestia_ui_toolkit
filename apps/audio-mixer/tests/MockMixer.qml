import QtQuick

// Stand-in for the Mixer service with fake devices, to test MixerView without PipeWire.
QtObject {
    id: root

    property var sinks: [
        {"name": "alsa.speakers", "description": "Built-in Audio Analog Stereo", "properties": {}, "audio": {"volume": 0.6, "muted": false}},
        {"name": "bluez.xm5", "description": "WH-1000XM5", "properties": {"device.bus": "bluetooth"}, "audio": {"volume": 0.3, "muted": true}},
        {"name": "hdmi", "description": "HDMI / DisplayPort", "properties": {}, "audio": {"volume": 1, "muted": false}}
    ]
    property var streams: [
        {"name": "firefox", "description": "Firefox", "properties": {"application.name": "Firefox"}, "audio": {"volume": 0.8, "muted": false}},
        {"name": "mpv", "description": "mpv", "properties": {"application.name": "mpv"}, "audio": {"volume": 0.5, "muted": false}}
    ]
    property var defaultSink: sinks[0]
    property var combinedSink: null
    property var members: []
    property bool combinedActive: false
    property bool busy: false
    property string error: ""
    property int linksRevision: 0
    property var log: []

    function isMember(n) { return members.includes(n.name); }
    function setMember(n, on) {
        members = on ? [...members.filter(m => m !== n.name), n.name] : members.filter(m => m !== n.name);
    }
    function sinkOf(stream, rev) { return stream.name === "firefox" ? sinks[0] : sinks[1]; }
    function streamName(s) { return s.properties["application.name"]; }
    function setDefault(n) { defaultSink = n; log.push("default:" + n.name); }
    function setVolume(n, v) { log.push("volume:" + n.name + ":" + v.toFixed(2)); }
    function toggleMute(n) { log.push("mute:" + n.name); }
    function routeStream(s, n) { log.push("route:" + s.name + ">" + n.name); }
    function applyCombine() { log.push("combine"); combinedActive = true; }
    function stopCombine() { log.push("stop"); combinedActive = false; }
}
