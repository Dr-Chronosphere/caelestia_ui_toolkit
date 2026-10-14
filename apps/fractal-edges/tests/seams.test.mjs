import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import vm from "node:vm";

const src = readFileSync(new URL("../Seams.js", import.meta.url), "utf8").replace(".pragma library", "");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src + "\nthis.S={parse,seams,clampRatio,edgeCommand,guideRect,coverTargets,coversEqual,stepCovers,piecesFromCovers,pieces,shiftRects,limits,rubberBand,blockerSpans,guidePieces,layerRuleCommand,cardBlurRuleCommand,measureInsets,parseAnimEnabled,animCommand,floatingRects,uncovered,clipRect,clipSeams,guideRects};", ctx);
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
assert.equal(S.edgeCommand(s0, 5), `edge ${s0.a} ${s0.b} 0.9000`, "clamped to this seam's engine limit, not a global one");
assert.equal(S.edgeCommand(s0, -5), `edge ${s0.a} ${s0.b} 0.1000`);
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
// --- limits (mirror the engine's weight range 0.2..5) ---------------------------------------------
const lim = (a, b) => plain(S.limits(a, b));
assert.deepEqual(lim(1, 1), { lo: 0.1, hi: 0.9 }, "equal weights: each tile keeps at least 0.2/2");
assert.equal(lim(2, 2).lo, 0.05, "sum 4: 0.2/4");
assert.equal(lim(2, 2).hi, 0.95);
const big = lim(4, 4);                                  // sum 8: max weight 5 caps each tile at 5/8
assert.equal(big.hi, 5 / 8);
assert.equal(big.lo, 3 / 8, "the other tile cannot go below 8-5 = 3");
assert.deepEqual(lim(0, 0), { lo: 0.05, hi: 0.95 }, "degenerate weights fall back to safe defaults");
// every seam from the real fixture carries limits, consistent with weights of 1 and 1
assert.ok(seams.every(sm => Math.abs(sm.lo - 0.1) < 1e-9 && Math.abs(sm.hi - 0.9) < 1e-9));
assert.equal(S.clampRatio(0.95, s0), 0.9);
assert.equal(S.clampRatio(0.5, s0), 0.5);

// --- rubber band ---------------------------------------------------------------------------------
const rb = (raw, give) => S.rubberBand(raw, s0, give);       // s0: lo .1, hi .9, span 1200
assert.equal(rb(0.5), 0.5, "identity inside the limits");
assert.equal(rb(0.9), 0.9);
assert.equal(rb(0.1), 0.1);
const over1 = rb(0.9 + 20 / 1200, 40) - 0.9;                 // pulled 20 px past: gives less than 20 px
assert.ok(over1 > 0 && over1 * 1200 < 20, `gives less than it is pulled (${over1 * 1200}px)`);
const over2 = rb(0.9 + 500 / 1200, 40) - 0.9;                // pulled 500 px past: never beyond `give`
assert.ok(over2 * 1200 < 40 && over2 * 1200 > 39, `capped near give (${over2 * 1200}px)`);
let prev = 0;                                                  // monotonic: pulling further never moves it back
for (let d = 0; d <= 400; d += 10) {
  const o = (rb(0.9 + d / 1200, 40) - 0.9) * 1200;
  assert.ok(o >= prev - 1e-9);
  prev = o;
}
const low = rb(0.1 - 20 / 1200, 40);                          // symmetric on the low side
assert.ok(low < 0.1 && (0.1 - low) * 1200 < 20);
assert.equal((0.1 - rb(0.1 - 20 / 1200, 40)).toFixed(9), (rb(0.9 + 20 / 1200, 40) - 0.9).toFixed(9), "symmetric");

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
// --- smooth cuts ---------------------------------------------------------------------------------------
// thin vertical guide at x=598.5..601.5 (layout coords), y=40..840; a floating window y=300..400
const thin = { x: 598.5, y: 40, w: 3, h: 800 };
const blk = [{ x: 500, y: 300, w: 200, h: 100 }, { x: 900, y: 600, w: 100, h: 100 }];   // 2nd is far to the right
const sp = plain(S.blockerSpans(thin, "x", blk));
assert.deepEqual(sp, [{ a: 300, b: 400, on: true }, { a: 600, b: 700, on: false }]);
// the line to the right of the first window: not overlapping
assert.equal(plain(S.blockerSpans({ ...thin, x: 800 }, "x", blk))[0].on, false);
// horizontal line (axis y): extent along x
const hsp = plain(S.blockerSpans({ x: 100, y: 350, w: 600, h: 3 }, "y", blk));
assert.deepEqual(hsp[0], { a: 500, b: 700, on: true });

const pieces2 = (e, prev, target) => plain(S.guidePieces(thin, "x", sp, prev, target, e)).map(r => [r.y, r.h]);
// fully cut (target 1, e=1): the window's 300..400 is removed
assert.deepEqual(pieces2(1, [0, 0], [1, 0]), [[40, 260], [400, 440]]);
// not cut at all
assert.deepEqual(pieces2(1, [1, 0], [0, 0]), [[40, 800]]);
assert.deepEqual(pieces2(0, [0, 0], [1, 0]), [[40, 800]], "start of a cut-in: nothing cut yet");
// halfway: the cut is half the window's extent, centred on it (325..375)
assert.deepEqual(pieces2(0.5, [0, 0], [1, 0]), [[40, 285], [375, 465]]);
// halfway through a cut-out starting from fully cut
assert.deepEqual(pieces2(0.5, [1, 0], [0, 0]), [[40, 285], [375, 465]]);
// continuity: the cut shrinks smoothly (never jumps) as e goes 0 -> 1
let lastCut = -1;
for (let k = 0; k <= 10; k++) {
  const ps = pieces2(k / 10, [1, 0], [0, 0]);
  const cut = 800 - ps.reduce((a, p) => a + p[1], 0);
  assert.ok(lastCut < 0 || cut <= lastCut + 1e-9, "cut only shrinks");
  assert.ok(lastCut < 0 || lastCut - cut <= 10 + 1e-9, "in steps of at most 10 px (no popping)");
  lastCut = cut;
}
assert.equal(lastCut, 0);

// the layer rule that stops the ghost animation
assert.equal(S.layerRuleCommand(), 'hl.layer_rule({ name = "fractal-edges-noanim", match = { namespace = "caelestia-fractal-(edge|guide|card)" }, no_anim = true })');
// --- whole-seam handles ---------------------------------------------------------------------------------
const wholeSeam = { key: "a|b", axis: "x", x: 692, y: 40, w: 16, h: 800, ratio: 0.5, span: 1200 };
const pc = (bl, min) => plain(S.pieces(wholeSeam, bl, min));
assert.deepEqual(pc([], 24), [{ x: 692, y: 40, w: 16, h: 800 }], "no blockers: the whole seam");
assert.equal(pc([{ x: 600, y: 100, w: 200, h: 150 }], 24).length, 2, "a window in the middle: two pieces");
assert.equal(pc([{ x: 600, y: 60, w: 200, h: 770 }], 24).length, 0, "only slivers left: nothing to grab");
assert.equal(pc([{ x: 600, y: 60, w: 200, h: 770 }], 5).length, 2, "minLen is a parameter");
assert.deepEqual(plain(S.shiftRects([{ x: 700, y: 100, w: 5, h: 6 }], 692, 40)), [{ x: 8, y: 60, w: 5, h: 6 }]);
// --- general cut smoothing -------------------------------------------------------------------------------
const spansIn = [{ a: 300, b: 400, on: true }, { a: 600, b: 700, on: false }];
const tg = plain(S.coverTargets(spansIn, 6));
assert.deepEqual(tg, [{ a: 300, b: 400, m: 6 }, { a: 650, b: 650, m: 0 }], "on: the window's extent + recoil; off: collapsed at the centre");
assert.equal(S.coversEqual(tg, plain(tg)), true);
assert.equal(S.coversEqual(tg, [{ a: 300, b: 401, m: 6 }, tg[1]]), false);

const step = (cur, t, k) => plain(S.stepCovers(cur, t, k));
// GROWTH snaps: a collapsed cover whose target is the window's extent jumps there at once (a, b), the margin eases
let r = step([{ a: 350, b: 350, m: 0 }], [{ a: 300, b: 400, m: 6 }], 0.1);
assert.equal(r.covers[0].a, 300, "cut-in: start snaps");
assert.equal(r.covers[0].b, 400, "cut-in: end snaps");
assert.ok(r.covers[0].m > 0 && r.covers[0].m < 6, "the recoil margin eases in (always away from the window)");
assert.equal(r.done, false);
// SHRINKING eases, at both ends, toward the centre
r = step([{ a: 300, b: 400, m: 6 }], [{ a: 350, b: 350, m: 0 }], 0.5);
assert.deepEqual([r.covers[0].a, r.covers[0].b, r.covers[0].m], [325, 375, 3]);
// ...and converges exactly
let cov = [{ a: 300, b: 400, m: 6 }];
let n = 0;
for (; n < 200; n++) {
  const st = plain(S.stepCovers(cov, [{ a: 350, b: 350, m: 0 }], 0.2));
  cov = st.covers;
  if (st.done) break;
}
assert.ok(n < 60, `converges in ${n} steps`);
assert.deepEqual(cov, [{ a: 350, b: 350, m: 0 }]);
// SMALL changes animate too (the case that used to snap): the window moves 10px down. Its end grows
// (snaps, so no overlap); its start shrinks (eases).
r = step([{ a: 300, b: 400, m: 6 }], [{ a: 310, b: 410, m: 6 }], 0.3);
assert.equal(r.covers[0].b, 410, "the edge the window moves toward snaps: never drawn over the window");
assert.ok(r.covers[0].a > 300 && r.covers[0].a < 310, "the edge it leaves eases");
// never overlap: while moving or emerging, the displayed cover always contains the window's extent
// (including after a size increase of just a few px)
for (const [from, to] of [[[300, 400], [305, 412]], [[300, 400], [296, 403]], [[300, 400], [300, 404]]]) {
  let c = [{ a: from[0], b: from[1], m: 6 }];
  const target = [{ a: to[0], b: to[1], m: 6 }];
  for (let i = 0; i < 30; i++) {
    c = plain(S.stepCovers(c, target, 0.25)).covers;
    assert.ok(c[0].a <= Math.max(to[0], from[0]) && c[0].b >= to[1], "the cover always reaches the window's far edge");
    assert.ok(c[0].a - c[0].m <= to[0] || c[0].a >= to[0], "(start edge only ever eases toward the window's start)");
  }
}
// pieces from covers: a 100px cover (+ margin) cut out of a line 40..840
const pf = (covers) => plain(S.piecesFromCovers({ x: 0, y: 40, w: 3, h: 800 }, "x", covers)).map(q => [q.y, q.h]);
assert.deepEqual(pf([{ a: 300, b: 400, m: 0 }]), [[40, 260], [400, 440]]);
assert.deepEqual(pf([{ a: 300, b: 400, m: 6 }]), [[40, 254], [406, 434]], "margin pulls the line back from the window on both sides");
assert.deepEqual(pf([{ a: 350, b: 350, m: 0 }]), [[40, 800]], "collapsed cover: whole line");
assert.deepEqual(pf([{ a: 350, b: 350, m: 3 }]), [[40, 800]], "empty cover ignores its margin (no stray gap)");
assert.equal(S.cardBlurRuleCommand(), 'hl.layer_rule({ name = "fractal-cards-blur", match = { namespace = "caelestia-fractal-card" }, blur = true, ignore_alpha = 0.2 })');
console.log("seams tests passed");

const st = { area: { x: 0, y: 0, w: 100, h: 100 }, tree: { kind: "split", children: [
  { kind: "window", address: "0xa", box: { x: 0, y: 0, w: 50, h: 100 } },
  { kind: "window", address: "0xb", box: { x: 50, y: 0, w: 50, h: 100 } } ] } };
const cl = JSON.stringify([{ address: "0xa", at: [10, 10], size: [35, 80] }, { address: "0xb", at: [55, 10], size: [35, 80] }]);
assert.deepEqual(JSON.parse(JSON.stringify(S.measureInsets(cl, st))), { inner: 5, edge: 10 });
assert.equal(S.measureInsets("[]", st), null);
