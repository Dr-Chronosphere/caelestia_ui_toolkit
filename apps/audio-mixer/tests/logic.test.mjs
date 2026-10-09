import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import vm from "node:vm";

const src = readFileSync(new URL("../services/Logic.js", import.meta.url), "utf8").replace(".pragma library", "");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src + "\nthis.L={COMBINED_NAME,combineCommand,isPlaybackStream,parseSinkInputs,findCombineModule,sinkIcon,combinableNames};", ctx);
const L = ctx.L;

assert.deepEqual([...L.combineCommand(["a", "b"], "slaves")], [
  "pactl", "load-module", "module-combine-sink", "sink_name=caelestia_combined",
  'sink_properties=device.description="Combined output"', "slaves=a,b"]);
assert.equal(L.combineCommand(["a"], "sinks").at(-1), "sinks=a");

assert.equal(L.isPlaybackStream({ "media.class": "Stream/Output/Audio" }), true);
assert.equal(L.isPlaybackStream({ "media.class": "Stream/Input/Audio" }), false);
assert.equal(L.isPlaybackStream(undefined), false);

assert.deepEqual(
  { ...L.parseSinkInputs(JSON.stringify([{ index: 7, properties: { "object.serial": "1234" } }, { index: 9, properties: {} }])) },
  { "1234": 7 });
assert.deepEqual({ ...L.parseSinkInputs("garbage") }, {});

const mods = [{ index: 1, name: "module-x", argument: "" },
  { index: 42, name: "module-combine-sink", argument: "sink_name=caelestia_combined slaves=a,b" },
  { index: 43, name: "module-combine-sink", argument: "sink_name=other" }];
assert.equal(L.findCombineModule(JSON.stringify(mods)), 42);
assert.equal(L.findCombineModule("[]"), -1);
assert.equal(L.findCombineModule("nope"), -1);

assert.equal(L.sinkIcon({ "device.bus": "bluetooth" }, "WH-1000XM5"), "bluetooth_audio");
assert.equal(L.sinkIcon({}, "HDMI / DisplayPort"), "tv");
assert.equal(L.sinkIcon({ "device.form-factor": "headphone" }, ""), "headphones");
assert.equal(L.sinkIcon({}, "Built-in Audio Analog Stereo"), "speaker");

assert.deepEqual([...L.combinableNames(["x", "caelestia_combined", "y"])], ["x", "y"]);
console.log("logic tests passed");
