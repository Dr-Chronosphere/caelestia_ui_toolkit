import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import vm from "node:vm";

const src = readFileSync(new URL("../Lod.js", import.meta.url), "utf8").replace(".pragma library", "");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src + "\nthis.L={smallWindows,intersects,cards,iconSize,showLabel,initial};", ctx);
const L = ctx.L;
const plain = v => JSON.parse(JSON.stringify(v));

// a | (b / (c | d)) on a 1200x800 area: a=600x800, b=600x400, c=300x400, d=300x400 (real engine output)
const status = JSON.parse(readFileSync(new URL("./fixture.json", import.meta.url), "utf8"));

assert.deepEqual(plain(L.smallWindows(status, 100, 100)), [], "nothing is small at 100x100");
let small = plain(L.smallWindows(status, 350, 100));          // c and d are 300 wide
assert.deepEqual(small.map(w => w.address).sort(), ["c", "d"]);
small = plain(L.smallWindows(status, 100, 500));              // b, c, d are 400 high
assert.deepEqual(small.map(w => w.address).sort(), ["b", "c", "d"]);
assert.equal(plain(L.smallWindows(status, 1000, 1000)).length, 4, "everything is small when the threshold is huge");
const c = plain(L.smallWindows(status, 350, 100)).find(w => w.address === "c");
assert.deepEqual(c.box, { x: 700, y: 440, w: 300, h: 400 });
assert.ok(c.id && c.label.length > 0, "carries the node id (for zoom) and the app label");
assert.deepEqual(plain(L.smallWindows(null, 1, 1)), []);
assert.deepEqual(plain(L.smallWindows({ tree: { kind: "window", address: "x" } }, 1, 1)), [], "windows without a box (hidden/parked) get no card");

// cards: inset, sorted by id
let cs = plain(L.cards(status, [], { minW: 350, minH: 100, inset: 4 }));
assert.equal(cs.length, 2);
assert.deepEqual([cs[0].x, cs[0].y, cs[0].w, cs[0].h].length, 4);
const cardC = cs.find(k => k.address === "c");
assert.deepEqual([cardC.x, cardC.y, cardC.w, cardC.h], [704, 444, 292, 392], "inset 4px inside the tile");
assert.ok(cs[0].id <= cs[1].id, "sorted by id: stable order");
// a floating window over a tile removes its card (it would be drawn over the window)
cs = plain(L.cards(status, [{ x: 650, y: 400, w: 200, h: 200 }], { minW: 350, minH: 100 }));
assert.deepEqual(cs.map(k => k.address), ["d"], "c's card is hidden: the floating window covers part of it");
// touching without overlapping is fine
cs = plain(L.cards(status, [{ x: 600, y: 440, w: 99, h: 100 }], { minW: 350, minH: 100 }));
assert.equal(cs.length, 2);
// defaults: 220 x 140
assert.equal(plain(L.cards(status, [])).length, 0, "no tile in the fixture is below 220x140");

// icon size and label
assert.equal(L.iconSize(300, 400), 64, "capped");
assert.equal(L.iconSize(60, 50), 25);
assert.equal(L.iconSize(10, 10), 16, "floor");
assert.equal(L.showLabel(120, 90), true);
assert.equal(L.showLabel(120, 60), false);
assert.equal(L.showLabel(80, 90), false);
assert.equal(L.initial("foot"), "F");
assert.equal(L.initial("--"), "?");
assert.equal(L.initial(""), "?");
console.log("lod tests passed");
