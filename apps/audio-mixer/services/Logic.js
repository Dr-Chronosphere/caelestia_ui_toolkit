.pragma library

// Pure helpers for the mixer service (no Quickshell dependency, unit-testable).

const COMBINED_NAME = "caelestia_combined";

// pactl command to create a combined sink. PipeWire's pulse module has used both
// `slaves=` (PulseAudio-compatible) and `sinks=` for the member list, so callers try
// both (see Mixer.qml).
function combineCommand(memberNames, memberArg) {
    return ["pactl", "load-module", "module-combine-sink",
        `sink_name=${COMBINED_NAME}`,
        `sink_properties=device.description="Combined output"`,
        `${memberArg}=${memberNames.join(",")}`];
}

// Playback streams only (not recording streams or sinks).
function isPlaybackStream(props) {
    return !!props && props["media.class"] === "Stream/Output/Audio";
}

// `pactl -f json list sink-inputs` -> { objectSerial: sinkInputIndex }
function parseSinkInputs(jsonText) {
    const map = {};
    let list;
    try { list = JSON.parse(jsonText); } catch (e) { return map; }
    for (const input of list) {
        const serial = input.properties?.["object.serial"];
        if (serial !== undefined)
            map[String(serial)] = input.index;
    }
    return map;
}

// `pactl -f json list modules` -> index of our combine module, or -1
function findCombineModule(jsonText) {
    let list;
    try { list = JSON.parse(jsonText); } catch (e) { return -1; }
    for (const m of list) {
        if (m.name === "module-combine-sink" && String(m.argument ?? "").includes(`sink_name=${COMBINED_NAME}`))
            return m.index;
    }
    return -1;
}

// Output "kind" icon from a PipeWire node's properties.
function sinkIcon(props, description) {
    const text = `${props?.["device.form-factor"] ?? ""} ${props?.["device.icon-name"] ?? ""} ${props?.["device.bus"] ?? ""} ${description ?? ""}`.toLowerCase();
    if (text.includes("bluetooth") || text.includes("bluez"))
        return "bluetooth_audio";
    if (text.includes("headphone") || text.includes("headset"))
        return "headphones";
    if (text.includes("hdmi") || text.includes("displayport") || text.includes("monitor") || text.includes("tv"))
        return "tv";
    if (text.includes("usb"))
        return "usb";
    return "speaker";
}

// Members that are valid for combining (excludes the combined sink itself).
function combinableNames(sinkNames) {
    return sinkNames.filter(n => n !== COMBINED_NAME);
}
