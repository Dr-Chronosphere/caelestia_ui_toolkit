import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import vm from "node:vm";

const src = readFileSync(new URL("../Seams.js", import.meta.url), "utf8").replace(".pragma library", "");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src + "\nthis.S={parse,seams,clampRatio,edgeCommand,guideRect,parseAnimEnabled,animCommand,floatingRects,uncovered,clipRect,clipSeams,guideRects};", ctx);
const S = ctx.S;
const plain = v => JSON.parse(JSON.stringify(v));
const fixture = readFileSync(new URL("./fixture.json", import.meta.url), "utf8");

// --- parse -----------------------------------------------------------------------
assert.equal(S.parse(""), null);
assert.equal(S.parse("{nope"), null);
assert.equal(S.parse('{"tree":{}}'), null, "needs area (older engine without geometry)");
const st = S.parse(fixture);
assert.ok(st && st.workspace === 3);

// --- seams from the real engine output: a | (b / (c | d)) ---------------------------
const seams = plain(S.seams(st, 16));
assert.equal(seams.length, 3);

const vert = seams.filter(s => s.axis === "x").sort((p, q) => p.x - q.x);
const horiz = seams.filter(s => s.axis === "y");
assert.equal(vert.length, 2);
assert.equal(horiz.length, 1);

// a | column  -> vertical line at x = 700, full height
assert.deepEqual([vert[0].x, vert[0].y, vert[0].w, vert[0].h], [692, 40, 16, 800]);
assert.equal(vert[0].ratio, 0.5);
assert.equal(vert[0].span, 1200);
// b / row     -> horizontal line at y = 440 across the column
assert.deepEqual([horiz[0].x, horiz[0].y, horiz[0].w, horiz[0].h], [700, 432, 600, 16]);
assert.equal(horiz[0].span, 800);
// c | d       -> vertical at x = 1000 within the lower half only
assert.deepEqual([vert[1].x, vert[1].y, vert[1].w, vert[1].h], [992, 440, 16, 400]);
assert.equal(vert[1].span, 600);
assert.ok(seams.every(s => s.key === s.a + "|" + s.b));

// --- unshown children make no seam; a lone child makes none -------------------------
const hidden = plain(st);
const col = hidden.tree.children[1];
delete col.children[0].box;           // b is hidden: column has one shown child
assert.equal(S.seams(hidden, 16).filter(s => s.container === col.id).length, 0);
// the row [a, column] keeps its seam, c|d keeps its own
assert.equal(S.seams(hidden, 16).length, 2);

// --- tabs never get seams --------------------------------------------------------------
const tabs = plain(st);
tabs.tree.kind = "tabs";
assert.equal(S.seams(tabs, 16).filter(s => s.container === tabs.tree.id).length, 0);

// --- grab thickness ----------------------------------------------------------------------
assert.equal(S.seams(st, 30).find(s => s.axis === "y").h, 30);

// --- commands ---------------------------------------------------------------------------
assert.equal(S.clampRatio(-1), 0.05);
assert.equal(S.clampRatio(2), 0.95);
assert.equal(S.clampRatio(0.4), 0.4);
const s0 = seams[0];
assert.equal(S.edgeCommand(s0, 0.25), `edge ${s0.a} ${s0.b} 0.2500`);
assert.equal(S.edgeCommand(s0, 5), `edge ${s0.a} ${s0.b} 0.9500`);
// --- guide line ----------------------------------------------------------------------------
// row seam at x=692..708 (centre 700), ratio 0.5, span 1200, monitor origin (100, 0)
const g0 = plain(S.guideRect(s0, 0.5, 100, 0, 3));
assert.deepEqual([g0.x, g0.y, g0.w, g0.h], [598.5, 40, 3, 800]);          // centre 700 - 100
const g1 = plain(S.guideRect(s0, 0.6, 100, 0, 3));
assert.equal(g1.x, 598.5 + 120, "ratio +0.1 of a 1200 span moves the line 120 px");
const g2 = plain(S.guideRect(s0, 0.4, 100, 0, 3));
assert.equal(g2.x, 598.5 - 120);
// column seam moves vertically and spans horizontally
const hs = plain(S.seams(st, 16).find(s => s.axis === "y"));
const g3 = plain(S.guideRect(hs, hs.ratio + 0.25, 100, 40, 3));
assert.deepEqual([g3.x, g3.w, g3.h], [hs.x - 100, hs.w, 3]);
assert.equal(g3.y, hs.y + hs.h / 2 + 0.25 * hs.span - 40 - 1.5);
// --- animation suspension helpers ------------------------------------------------------------
assert.equal(S.parseAnimEnabled('{"option":"animations:enabled","int":1,"set":true}'), true);
assert.equal(S.parseAnimEnabled('{"option":"animations:enabled","int":0,"set":true}'), false);
assert.equal(S.parseAnimEnabled('{"option":"animations:enabled","bool":false}'), false);
assert.equal(S.parseAnimEnabled('{"option":"x"}'), null, "unknown shape: leave animations alone");
assert.equal(S.parseAnimEnabled(""), null);
assert.equal(S.parseAnimEnabled("no such option"), null);
assert.equal(S.animCommand(false), "hl.config({ animations = { enabled = false } })");
assert.equal(S.animCommand(true), "hl.config({ animations = { enabled = true } })");
// --- floating windows ----------------------------------------------------------------------------
const monitors = JSON.stringify([
  { id: 0, name: "DP-1", activeWorkspace: { id: 3 }, specialWorkspace: { id: 0, name: "" } },
  { id: 1, name: "HDMI-A-1", activeWorkspace: { id: 7 }, specialWorkspace: { id: -98, name: "special:music" } }]);
const win = (o) => ({ floating: true, mapped: true, hidden: false, monitor: 0, workspace: { id: 3 }, at: [100, 100], size: [200, 150], pinned: false, ...o });
const clients = JSON.stringify([
  win({}),                                              // floating on DP-1's active workspace: blocks
  win({ floating: false, at: [0, 0] }),                 // tiled: never a blocker
  win({ workspace: { id: 4 }, at: [500, 500] }),        // floating on another workspace: not shown
  win({ hidden: true, at: [600, 600] }),                // hidden
  win({ mapped: false, at: [700, 700] }),               // not mapped
  win({ workspace: { id: 4 }, pinned: true, at: [800, 100], size: [50, 50] }),   // pinned: shown everywhere on its monitor
  win({ monitor: 1, workspace: { id: 7 }, at: [3000, 0] }),                       // other monitor
  win({ monitor: 1, workspace: { id: -98 }, at: [3100, 50], size: [100, 100] }),  // shown scratchpad on HDMI
  win({ monitor: 1, workspace: { id: -99 }, at: [3300, 50] }),                    // special workspace not shown
]);
const fr = plain(S.floatingRects(clients, monitors, "DP-1", 0));
assert.deepEqual(fr, [{ x: 100, y: 100, w: 200, h: 150 }, { x: 800, y: 100, w: 50, h: 50 }]);
assert.deepEqual(plain(S.floatingRects(clients, monitors, "DP-1", 3))[0], { x: 97, y: 97, w: 206, h: 156 }, "padding grows the rect");
const hdmi = plain(S.floatingRects(clients, monitors, "HDMI-A-1", 0));
assert.deepEqual(hdmi, [{ x: 3000, y: 0, w: 200, h: 150 }, { x: 3100, y: 50, w: 100, h: 100 }], "active workspace + shown scratchpad");
assert.deepEqual(plain(S.floatingRects(clients, monitors, "nope", 0)), []);
assert.deepEqual(plain(S.floatingRects("garbage", monitors, "DP-1")), []);

// uncovered intervals
const iv = (a, b, c) => plain(S.uncovered(a, b, c));
assert.deepEqual(iv(0, 100, []), [[0, 100]]);
assert.deepEqual(iv(0, 100, [[20, 40]]), [[0, 20], [40, 100]]);
assert.deepEqual(iv(0, 100, [[-50, 10], [90, 200]]), [[10, 90]]);
assert.deepEqual(iv(0, 100, [[10, 30], [20, 50], [70, 80]]), [[0, 10], [50, 70], [80, 100]], "overlapping covers merge");
assert.deepEqual(iv(0, 100, [[0, 100]]), []);

// a vertical seam (x=692..708, y=40..840) with a floating window over y=100..250
const vseam = { key: "a|b", axis: "x", x: 692, y: 40, w: 16, h: 800, ratio: 0.5, span: 1200 };
let pieces = plain(S.clipSeams([vseam], [{ x: 600, y: 100, w: 200, h: 150 }], 24));
assert.equal(pieces.length, 2);
assert.deepEqual([pieces[0].y, pieces[0].h], [40, 60]);
assert.deepEqual([pieces[1].y, pieces[1].h], [250, 590]);
assert.equal(pieces[0].ratio, 0.5);
assert.equal(pieces[0].span, 1200, "drag maths unchanged per piece");
assert.equal(pieces[0].key, "a|b#0");
assert.equal(pieces[1].key, "a|b#1");
// a window beside the seam (does not overlap its thickness) blocks nothing
assert.equal(plain(S.clipSeams([vseam], [{ x: 720, y: 100, w: 200, h: 150 }], 24)).length, 1);
// short leftover pieces are dropped
pieces = plain(S.clipSeams([vseam], [{ x: 600, y: 60, w: 200, h: 770 }], 24));
assert.equal(pieces.length, 0, "20px and 10px leftovers are below minLen");
// no blockers: the same list back
assert.equal(S.clipSeams([vseam], [], 24).length, 1);
// horizontal seam clips along x
const hseam = { key: "p|q", axis: "y", x: 700, y: 432, w: 600, h: 16, ratio: 0.5, span: 800 };
pieces = plain(S.clipSeams([hseam], [{ x: 900, y: 400, w: 100, h: 100 }], 24));
assert.deepEqual(pieces.map(p => [p.x, p.w]), [[700, 200], [1000, 300]]);

// guide: clipped in layout coordinates, then shifted to monitor coordinates
const gr = plain(S.guideRects(vseam, 0.6, 100, 0, 3, [{ x: 650, y: 300, w: 400, h: 100 }]));
assert.equal(gr.length, 2);
assert.equal(gr[0].x, 820 + 0 - 1.5 - 100 + 0, "ratio 0.6 shifts 120 px from centre 700, minus origin");
assert.deepEqual([gr[0].y, gr[0].h, gr[1].y, gr[1].h], [40, 260, 400, 440]);
assert.equal(plain(S.guideRects(vseam, 0.5, 100, 0, 3, [])).length, 1);
console.log("seams tests passed");
