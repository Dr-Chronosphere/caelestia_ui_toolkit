import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";
const dir = path.dirname(fileURLToPath(import.meta.url));
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(dir, "../DragDrop.js"), "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.D={tiles,targetAt,screenZone,screenTarget,isTabbable,dragIsTabbable,targetIsTabbable,highlight,intentCommand,create,seeTiles,floatEvent,pointer,closed,parseCursor,parseFloatEvent};", ctx);
const D = ctx.D;
const plain = v => JSON.parse(JSON.stringify(v));
const status = JSON.parse(fs.readFileSync(path.join(dir, "fixture.json"), "utf8"));

// tiles from the real engine fixture (a | (b / (c | d)))
const list = plain(D.tiles(status));
assert.equal(list.length, 4);
const a = list.find(t => t.address === "a"), c = list.find(t => t.address === "c");
assert.ok(a.box.w > 0 && c.box.w > 0);

// zones: a small middle swaps, everywhere else the window goes to the side the pointer is on
const near = (fx, fy, o) => plain(D.targetAt({ x: a.box.x + a.box.w * fx, y: a.box.y + a.box.h * fy }, list, "", o));
assert.deepEqual([near(0.5, 0.5).address, near(0.5, 0.5).zone], ["a", "center"], "the middle swaps");
assert.equal(near(0.58, 0.44).zone, "center", "the swap area is 30% of the tile each way (+-15% from the centre)");
assert.equal(near(0.7, 0.5).zone, "right", "outside it: the side the pointer is on");
assert.equal(near(0.3, 0.5).zone, "left");
assert.equal(near(0.5, 0.3).zone, "up");
assert.equal(near(0.5, 0.7).zone, "down");
assert.equal(near(0.02, 0.5).zone, "left");
assert.equal(near(0.5, 0.98).zone, "down");
assert.equal(near(0.35, 0.6).zone, "left", "the larger offset from the middle decides (x offset 0.15 beats y offset 0.10)");
assert.equal(near(0.42, 0.7).zone, "down");
assert.equal(near(0.5, 0.5, { swapSize: 0 }).zone === "center", false, "swapSize 0 turns swapping off");
assert.equal(near(0.9, 0.9).zone, "right", "corner: the larger offset (a tie goes to left/right)");
assert.equal(D.targetAt(near_pt(0.5, 0.5), list, "a") === null || D.targetAt(near_pt(0.5, 0.5), list, "a").address !== "a", true, "never targets the dragged window itself");
function near_pt(fx, fy) { return { x: a.box.x + a.box.w * fx, y: a.box.y + a.box.h * fy }; }
assert.equal(D.targetAt({ x: -50, y: -50 }, list, ""), null, "outside every tile: no target");

// highlight rectangles
const b = { x: 100, y: 40, w: 400, h: 200 };
assert.deepEqual(plain(D.highlight({ zone: "left", box: b })), { x: 100, y: 40, w: 200, h: 200 });
assert.deepEqual(plain(D.highlight({ zone: "right", box: b })), { x: 300, y: 40, w: 200, h: 200 });
assert.deepEqual(plain(D.highlight({ zone: "up", box: b })), { x: 100, y: 40, w: 400, h: 100 });
assert.deepEqual(plain(D.highlight({ zone: "down", box: b })), { x: 100, y: 140, w: 400, h: 100 });
assert.deepEqual(plain(D.highlight({ zone: "center", box: b })), b);

// screen edges: halves and quadrants, independent of the windows
const area = { x: 100, y: 40, w: 1200, h: 800 };
const sz = (fx, fy) => D.screenZone({ x: area.x + area.w * fx, y: area.y + area.h * fy }, area);
assert.equal(sz(0.5, 0.5), "", "the middle of the screen is no screen zone");
assert.equal(sz(0.02, 0.5), "sleft");
assert.equal(sz(0.98, 0.5), "sright");
assert.equal(sz(0.5, 0.02), "sup");
assert.equal(sz(0.5, 0.97), "sdown");
assert.equal(sz(0.02, 0.03), "qtl", "corner = quadrant");
assert.equal(sz(0.98, 0.03), "qtr");
assert.equal(sz(0.02, 0.97), "qbl");
assert.equal(sz(0.98, 0.97), "qbr");
assert.equal(D.screenZone({ x: 90, y: 400 }, area), "sleft", "just outside the work area (bar, gaps) still counts");
assert.equal(D.screenZone({ x: 20, y: 400 }, area), "sleft", "a pointer well outside the work area (screen edge past the bar) still counts");
assert.equal(D.screenZone({ x: -400, y: 400 }, area), "", "but not far outside it");
assert.equal(D.screenZone({ x: 105, y: 400 }, area, { band: 0 }), "", "band 0 turns screen zones off");
const sx = (z) => plain(D.highlight(D.screenTarget(z, area)));
assert.deepEqual(sx("sleft"), { x: 100, y: 40, w: 600, h: 800 });
assert.deepEqual(sx("sdown"), { x: 100, y: 440, w: 1200, h: 400 });
assert.deepEqual(sx("qbr"), { x: 700, y: 440, w: 600, h: 400 });
assert.deepEqual(sx("qtl"), { x: 100, y: 40, w: 600, h: 400 });
assert.equal(D.screenTarget("", area), null);
assert.equal(D.intentCommand("0xabc", D.screenTarget("qtl", area)), "drop-intent 0xabc screen qtl");

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
// tabbable windows (the file explorer)
assert.equal(D.isTabbable("Files #3 \u2014 Home"), true);
assert.equal(D.isTabbable("Terminal"), false);
const trT = D.create();
D.seeTiles(trT, [{ address: "0x1", title: "Files #1 \u2014 Home", box: { x: 0, y: 0, w: 1, h: 1 } }, { address: "0x2", title: "foot", box: { x: 0, y: 0, w: 1, h: 1 } }]);
assert.equal(D.dragIsTabbable(trT, "0x1"), true);
assert.equal(D.dragIsTabbable(trT, "0x2"), false);
assert.equal(D.dragIsTabbable(trT, "0x9"), false, "unknown windows are not tabbable");
assert.equal(D.targetIsTabbable([{ address: "0x1", title: "Files #1 \u2014 x" }], "0x1"), true);
assert.equal(D.targetIsTabbable([{ address: "0x2", title: "foot" }], "0x2"), false);
console.log("dragdrop tests passed");
