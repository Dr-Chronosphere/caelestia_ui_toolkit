import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import vm from "node:vm";

const src = readFileSync(new URL("../Lod.js", import.meta.url), "utf8").replace(".pragma library", "");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src + "\nthis.L={smallWindows,intersects,cards,thresholds,iconSize,showLabel,initial,scaleOf,alphaFor,alphaOut,nextAlpha,reconcile,purge};", ctx);
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
let cs = plain(L.cards(status, [], { minW: 350, minH: 100, inset: 4, outset: -4 }));
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
assert.equal(plain(L.cards(status, [], {minW:220,minH:140})).length, 0, "no tile in the fixture is below 220x140");

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
// --- size-dependent fade -------------------------------------------------------------------------------------
assert.equal(L.alphaFor(1), 0, "invisible at the threshold");
assert.equal(L.alphaFor(1.2), 0, "and above it");
assert.ok(Math.abs(L.alphaFor(0.7) - 1) < 1e-9, "fully visible 30% below it");
assert.equal(L.alphaFor(0.5), 1);
assert.ok(Math.abs(L.alphaFor(0.85) - 0.5) < 1e-9, "halfway in between");
let prevA = 2;
for (let sc = 1; sc >= 0.7; sc -= 0.02) {              // monotonic: smaller tile => never less visible
  const a = L.alphaFor(sc);
  assert.ok(a >= (prevA === 2 ? 0 : 0));
  assert.ok(prevA === 2 || a >= prevA - 1e-9);
  prevA = a;
}
assert.equal(L.scaleOf({ w: 110, h: 400 }, 220, 140), 0.5, "the tighter dimension decides");
assert.equal(L.scaleOf({ w: 440, h: 70 }, 220, 140), 0.5);
const fadeCards = plain(L.cards(status, [], { minW: 320, minH: 100, inset: 4 }));    // c, d are 300 wide: scale 0.9375
assert.equal(fadeCards.length, 2);
assert.ok(fadeCards.every(k => Math.abs(k.scale - 300 / 320) < 1e-9));
assert.ok(fadeCards.every(k => k.alpha > 0 && k.alpha < 1), "just under the threshold: partly faded in");
const deep = plain(L.cards(status, [], { minW: 500, minH: 100, inset: 4 }));          // scale 0.6
assert.ok(deep.every(k => k.alpha === 1 && k.address !== undefined), "well under: fully visible");

// --- reconcile / purge -----------------------------------------------------------------------------------------
const card = (id, extra) => ({ id, address: id, label: id, title: "", x: 0, y: 0, w: 10, h: 10, scale: 0.5, alpha: 1, ...extra });
let st = plain(L.reconcile({}, [card("c"), card("d")], ["c", "d"], 1000));
assert.deepEqual(st.keys, ["c", "d"]);
assert.ok(!st.map.c.leaving);
// d's tile grew (not in `unblocked` either): it stays, leaving, with alpha 0 and its last geometry
st = plain(L.reconcile(st.map, [card("c")], ["c"], 1100));
assert.deepEqual(st.keys, ["c", "d"]);
assert.equal(st.map.d.leaving, true);
assert.equal(st.map.d.alpha, 0);
assert.equal(st.map.d.leaveAt, 1100);
assert.equal(st.map.d.w, 10, "keeps its last geometry while fading");
// still leaving a moment later: the original leave time is kept
st = plain(L.reconcile(st.map, [card("c")], ["c"], 1200));
assert.equal(st.map.d.leaveAt, 1100);
// a floating window now covers c: c is unblocked-list member, so it is dropped at once, not faded
let blocked = plain(L.reconcile({ c: card("c") }, [], ["c"], 1300));
assert.deepEqual(blocked.keys, [], "blocked by a floating window: gone immediately (never drawn over it)");
// ...whereas a card whose tile grew while ALSO covered is not in `unblocked`, so it fades
assert.deepEqual(plain(L.reconcile({ c: card("c") }, [], [], 1300)).keys, ["c"]);
// the tile shrinks again while d is fading: it returns as a normal card
st = plain(L.reconcile(st.map, [card("c"), card("d")], ["c", "d"], 1250));
assert.ok(!st.map.d.leaving);
// purge drops finished fades only
let p2 = plain(L.reconcile({ c: card("c"), d: card("d") }, [card("c")], ["c"], 2000));
assert.deepEqual(plain(L.purge(p2.map, 2100, 260)).keys, ["c", "d"], "still fading at 100 ms");
assert.deepEqual(plain(L.purge(p2.map, 2300, 260)).keys, ["c"], "gone after 260 ms");
console.log("lod tests passed");

// relative threshold: area is 1200x800, frac 0.3 -> 360x240; c,d (300 wide) qualify
assert.equal(plain(L.cards(status, [], { frac: 0.3 })).length >= 2, true);
assert.deepEqual([L.thresholds(status, { frac: 0.5 }).minW, L.thresholds(status, { frac: 0.5 }).minH], [600, 400]);
// edge outset: d touches the right/bottom of the work area (x 100..1300, y 40..840)
const od = plain(L.cards(status, [], { minW: 350, minH: 100, inset: 0, outset: 12 })).find(k => k.address === "d");
assert.equal(od.x + od.w, 1312, "grows 12px past the right work-area edge");
assert.equal(od.y + od.h, 852, "and the bottom");
const cl = plain(L.cards(status, [], { minW: 350, minH: 100, inset: 0, outset: 12, bounds: { x: 0, y: 0, w: 1305, h: 845 } })).find(k => k.address === "d");
assert.equal(cl.x + cl.w, 1305, "clamped to the monitor");
// --- hysteresis: fade-in pinned to the threshold going in, fade-out to the threshold going out ---
assert.equal(L.alphaOut(1), 1);
assert.equal(L.alphaOut(1.3) , 0);
assert.ok(Math.abs(L.alphaOut(1.15) - 0.5) < 1e-9);
assert.equal(L.nextAlpha(undefined, 1.1), 0, "new card above the threshold: nothing");
assert.ok(Math.abs(L.nextAlpha(undefined, 0.85) - 0.5) < 1e-9);
assert.equal(L.nextAlpha({ alpha: 1, scale: 0.5 }, 0.9), 1, "fully in stays in while growing up to the threshold");
assert.equal(L.nextAlpha({ alpha: 1, scale: 0.9 }, 1), 1, "...and only starts fading once it passes it");
assert.ok(Math.abs(L.nextAlpha({ alpha: 1, scale: 1 }, 1.15) - 0.5) < 1e-9);
assert.equal(L.nextAlpha({ alpha: 0.5, scale: 0.85 }, 0.9), 0.5, "a half-faded card does not retreat while still below the threshold");
assert.equal(L.nextAlpha({ alpha: 0.5, scale: 1.15 }, 1.1), 0.5, "shrinking back keeps it until it passes the threshold");
{
  const wide = { area: status.area, tree: { kind: "window", id: "w", address: "w", name: "x", title: "", box: { x: 100, y: 40, w: 1200 * 0.25 * 1.15, h: 800 } } };
  const o = { frac: 0.25, outset: 0, inset: 0 };
  assert.equal(plain(L.cards(wide, [], o)).length, 0, "just above the threshold, no prev: no card");
  const had = { w: { alpha: 1, scale: 1 } };
  const k = plain(L.cards(wide, [], { ...o, prev: had }));
  assert.equal(k.length, 1);
  assert.ok(Math.abs(k[0].alpha - 0.5) < 1e-6, "fading out above the threshold");
  assert.equal(plain(L.cards(wide, [], { ...o, prev: had, idle: true })).length, 0, "idle above the threshold: gone");
}
console.log("hysteresis ok");
