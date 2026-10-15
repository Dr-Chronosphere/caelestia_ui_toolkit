import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";
const dir = path.dirname(fileURLToPath(import.meta.url));
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(dir, "../DragDrop.js"), "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.D={tiles,targetAt,highlight,intentCommand,create,seeTiles,floatEvent,pointer,closed,parseCursor,parseFloatEvent};", ctx);
const D = ctx.D;
const plain = v => JSON.parse(JSON.stringify(v));
const status = JSON.parse(fs.readFileSync(path.join(dir, "fixture.json"), "utf8"));

// tiles from the real engine fixture (a | (b / (c | d)))
const list = plain(D.tiles(status));
assert.equal(list.length, 4);
const a = list.find(t => t.address === "a"), c = list.find(t => t.address === "c");
assert.ok(a.box.w > 0 && c.box.w > 0);

// zones: edges (28%) vs centre
const mid = { x: a.box.x + a.box.w / 2, y: a.box.y + a.box.h / 2 };
let t = plain(D.targetAt(mid, list, "", { swap: true }));
assert.deepEqual([t.address, t.zone], ["a", "center"], "with swap enabled the middle swaps");
// by default there is no swap: the window goes to the side the pointer is on
const near = (fx, fy) => plain(D.targetAt({ x: a.box.x + a.box.w * fx, y: a.box.y + a.box.h * fy }, list, ""));
assert.equal(near(0.4, 0.5).zone, "left", "just left of the middle: left half");
assert.equal(near(0.6, 0.5).zone, "right");
assert.equal(near(0.5, 0.42).zone, "up");
assert.equal(near(0.5, 0.6).zone, "down");
assert.equal(near(0.42, 0.52).zone, "left", "the larger offset from the centre decides");
assert.equal(near(0.52, 0.65).zone, "down");
assert.ok(["left", "right", "up", "down"].includes(near(0.5, 0.5).zone), "the exact centre still picks a side");
t = plain(D.targetAt({ x: a.box.x + 3, y: mid.y }, list, ""));
assert.deepEqual([t.address, t.zone], ["a", "left"]);
t = plain(D.targetAt({ x: a.box.x + a.box.w - 3, y: mid.y }, list, ""));
assert.equal(t.zone, "right");
t = plain(D.targetAt({ x: mid.x, y: a.box.y + 2 }, list, ""));
assert.equal(t.zone, "up");
t = plain(D.targetAt({ x: mid.x, y: a.box.y + a.box.h - 2 }, list, ""));
assert.equal(t.zone, "down");
t = plain(D.targetAt({ x: a.box.x + 3, y: a.box.y + 2 }, list, ""));
assert.ok(["left", "up"].includes(t.zone), "corner: the nearer edge");
assert.equal(D.targetAt(mid, list, "a") === null || D.targetAt(mid, list, "a").address !== "a", true, "never targets the dragged window itself");
assert.equal(D.targetAt({ x: -50, y: -50 }, list, ""), null, "outside every tile: no target");

// highlight rectangles
const b = { x: 100, y: 40, w: 400, h: 200 };
assert.deepEqual(plain(D.highlight({ zone: "left", box: b })), { x: 100, y: 40, w: 200, h: 200 });
assert.deepEqual(plain(D.highlight({ zone: "right", box: b })), { x: 300, y: 40, w: 200, h: 200 });
assert.deepEqual(plain(D.highlight({ zone: "up", box: b })), { x: 100, y: 40, w: 400, h: 100 });
assert.deepEqual(plain(D.highlight({ zone: "down", box: b })), { x: 100, y: 140, w: 400, h: 100 });
assert.deepEqual(plain(D.highlight({ zone: "center", box: b })), b);

// commands (only safe ids make it into a layout command)
assert.equal(D.intentCommand("0xabc", { address: "0xdef", zone: "left" }), "drop-intent 0xabc 0xdef left");
assert.equal(D.intentCommand("0xabc", null), "drop-intent clear");
assert.equal(D.intentCommand("0xa bc", null), "", "unsafe ids are refused");
assert.equal(D.intentCommand("0xabc", { address: "x\"; boom", zone: "left" }), "");

// drag detection
const tr = D.create();
D.seeTiles(tr, list);
tr.known["0xaa"] = true;
assert.equal(D.floatEvent(tr, "0xzz", true, { x: 0, y: 0 }, 0), "", "a window that was never a tile is not a drag");
assert.equal(D.floatEvent(tr, "0xaa", true, { x: 500, y: 500 }, 1000), "candidate");
assert.equal(D.pointer(tr, { x: 502, y: 501 }, 1100).drag, "", "a tiny jiggle is not a drag yet");
assert.equal(D.pointer(tr, { x: 540, y: 520 }, 1200).drag, "0xaa", "pointer travel after the float = a drag");
assert.equal(D.pointer(tr, { x: 600, y: 520 }, 1300).drag, "0xaa");
assert.equal(D.floatEvent(tr, "0xaa", false, { x: 600, y: 520 }, 1400), "end", "re-tiled on release: the drag ends");
assert.equal(D.pointer(tr, { x: 900, y: 900 }, 1500).drag, "");
// a deliberate float (key bind): the pointer is still, then it moves much later
const t2 = D.create();
t2.known["0xbb"] = true;
D.floatEvent(t2, "0xbb", true, { x: 10, y: 10 }, 0);
assert.equal(D.pointer(t2, { x: 10, y: 10 }, 400).drag, "");
assert.equal(D.pointer(t2, { x: 300, y: 300 }, 1500).drag, "", "moving the pointer long after a float is not a drag");
// closing mid-drag
const t3 = D.create();
t3.known["0xcc"] = true;
D.floatEvent(t3, "0xcc", true, { x: 0, y: 0 }, 0);
D.pointer(t3, { x: 50, y: 0 }, 100);
D.closed(t3, "0xcc");
assert.equal(D.pointer(t3, { x: 90, y: 0 }, 200).drag, "");

assert.deepEqual(plain(D.parseCursor('{"x": 12.5, "y": 40}')), { x: 12.5, y: 40 });
assert.equal(D.parseCursor("nope"), null);
assert.deepEqual(plain(D.parseFloatEvent("55746c8f2d40,1")), { address: "0x55746c8f2d40", floating: true });
assert.deepEqual(plain(D.parseFloatEvent("0xAB,0")), { address: "0xab", floating: false });
assert.equal(D.parseFloatEvent("x"), null);
console.log("dragdrop tests passed");
