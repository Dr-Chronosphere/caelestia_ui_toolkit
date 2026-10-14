import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import vm from "node:vm";

const src = readFileSync(new URL("../Seams.js", import.meta.url), "utf8").replace(".pragma library", "");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src + "\nthis.S={parse,seams,clampRatio,edgeCommand,guideRect,parseAnimEnabled,animCommand};", ctx);
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
console.log("seams tests passed");
