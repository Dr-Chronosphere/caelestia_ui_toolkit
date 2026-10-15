import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";
const dir = path.dirname(fileURLToPath(import.meta.url));
function load(file, names) {
  const ctx = vm.createContext({});
  vm.runInContext(fs.readFileSync(path.join(dir, "../logic", file), "utf8").replace(/^\.pragma.*$/m, "") + `\nthis.X={${names}};`, ctx);
  return ctx.X;
}
const plain = v => JSON.parse(JSON.stringify(v));
const T = load("Tabs.js", "make,open,close,activate,cycle,move,merge,labels");
const M = load("Merge.js", "area,overlap,centerIn,targetFor,create,update,idFromTitle,samples");

// ---- tabs ----
let w = plain(T.make(["a"]));
assert.deepEqual(w, { tabs: ["a"], active: "a" });
w = plain(T.open(w, "b"));                       // after the active tab, activated
w = plain(T.open(w, "c"));
assert.deepEqual(w, { tabs: ["a", "b", "c"], active: "c" });
w = plain(T.open(T.activate(w, "a"), "d"));
assert.deepEqual(w.tabs, ["a", "d", "b", "c"], "new tab opens next to the active one");
w = plain(T.close(w, "d"));                       // active closed: right neighbour
assert.equal(w.active, "b");
w = plain(T.close(T.activate(w, "c"), "c"));      // last tab closed: left neighbour
assert.equal(w.active, "b");
assert.equal(plain(T.close(T.activate(w, "a"), "b")).active, "a", "closing an inactive tab keeps the active one");
assert.deepEqual(plain(T.close(T.make(["z"]), "z")), { tabs: [], active: "" });
assert.deepEqual(plain(T.close(w, "nope")), w, "unknown id: unchanged");
assert.equal(plain(T.cycle(T.make(["a", "b", "c"], "c"), 1)).active, "a", "wraps forward");
assert.equal(plain(T.cycle(T.make(["a", "b", "c"], "a"), -1)).active, "c", "and back");
assert.deepEqual(plain(T.move(T.make(["a", "b", "c"], "a"), "a", 2)).tabs, ["b", "c", "a"]);
assert.deepEqual(plain(T.move(T.make(["a", "b", "c"], "a"), "c", -5)).tabs, ["c", "a", "b"], "clamped");
const merged = plain(T.merge(T.make(["a", "b"], "a"), T.make(["x", "y"], "y")));
assert.deepEqual(merged, { tabs: ["a", "b", "x", "y"], active: "y" }, "source tabs appended, its active tab wins");
assert.deepEqual(plain(T.merge(T.make(["a"]), T.make(["a", "x"], "x"))).tabs, ["a", "x"], "no duplicates");

// ---- labels ----
const L = plain(T.labels([{ id: "1", path: "/home/me" }, { id: "2", path: "/home/me/src" }, { id: "3", path: "/work/proj/src" }, { id: "4", path: "/" }], "/home/me"));
assert.deepEqual(L.map(l => l.label), ["Home", "src — me", "src — proj", "/"]);

// ---- merge geometry ----
const A = { id: "1", x: 0, y: 0, w: 400, h: 300, workspace: 1 };
const B = { id: "2", x: 500, y: 0, w: 400, h: 300, workspace: 1 };
assert.equal(M.targetFor({ id: "2", x: 100, y: 100, w: 200, h: 100, workspace: 1 }, [A, B]), "1", "centre inside A");
assert.equal(M.targetFor({ id: "2", x: 380, y: 100, w: 200, h: 100, workspace: 1 }, [A, B]), "", "centre (480) in the gap: no target");
assert.equal(M.targetFor({ id: "2", x: 100, y: 100, w: 200, h: 100, workspace: 2 }, [A, B]), "", "other workspace");

// ---- tracker: pick up, hover, settle -> drop ----
const tr = M.create();
const base = [A, { ...B }];
let r = plain(M.update(tr, base, 0));
assert.deepEqual(r, { dragging: "", target: "", drop: null }, "first sample: nothing moved");
r = plain(M.update(tr, [A, { ...B, x: 300 }], 50));     // B starts moving, centre (500) not yet over A (0..400)
assert.deepEqual([r.dragging, r.target], ["2", ""]);
r = plain(M.update(tr, [A, { ...B, x: 100 }], 100));    // centre (300) over A
assert.deepEqual([r.dragging, r.target, r.drop], ["2", "1", null]);
r = plain(M.update(tr, [A, { ...B, x: 100 }], 300));    // still, but not long enough
assert.deepEqual([r.dragging, r.target, r.drop], ["2", "1", null]);
r = plain(M.update(tr, [A, { ...B, x: 100 }], 600));    // settled over A
assert.deepEqual(r.drop, { from: "2", to: "1" });
assert.equal(r.dragging, "", "tracker resets after a drop");
r = plain(M.update(tr, [A, { ...B, x: 100 }], 700));
assert.equal(r.drop, null, "no repeat drop");

// settling over empty space drops nothing; resizing is not dragging
const t2 = M.create();
M.update(t2, base, 0);
r = plain(M.update(t2, [A, { ...B, x: 700 }], 50));
assert.equal(r.dragging, "2");
r = plain(M.update(t2, [A, { ...B, x: 700 }], 600));
assert.deepEqual([r.dragging, r.drop], ["", null], "settled away from any window: no merge");
const t3 = M.create();
M.update(t3, base, 0);
r = plain(M.update(t3, [A, { ...B, x: 300, w: 300 }], 50));
assert.equal(r.dragging, "", "a size change is a resize, not a drag");
const t4 = M.create();                                    // window closed mid-drag
M.update(t4, base, 0);
M.update(t4, [A, { ...B, x: 100 }], 50);
r = plain(M.update(t4, [A], 80));
assert.deepEqual([r.dragging, r.drop], ["", null]);

// ---- hyprctl samples ----
assert.equal(M.idFromTitle("Files #12 — Home"), "12");
assert.equal(M.idFromTitle("Other"), "");
const s = plain(M.samples(JSON.stringify([
  { title: "Files #1 — Home", at: [10, 20], size: [300, 200], workspace: { id: 2 }, mapped: true },
  { title: "Files #2 — src", at: [0, 0], size: [1, 1], hidden: true },
  { title: "Terminal", at: [0, 0], size: [5, 5] }])));
assert.deepEqual(s, [{ id: "1", x: 10, y: 20, w: 300, h: 200, workspace: 2, floating: false }]);
assert.deepEqual(plain(M.samples("garbage")), []);
// ---- release over a window (tiled drag: floated while held, re-tiled on release) ----
{
  const A2 = { id: "1", x: 0, y: 0, w: 400, h: 300, workspace: 1, floating: false };
  const B2 = { id: "2", x: 500, y: 0, w: 400, h: 300, workspace: 1, floating: false };
  const tr = M.create();
  M.update(tr, [A2, B2], 0);
  let r = plain(M.update(tr, [A2, { ...B2, x: 300, floating: true }], 50));       // picked up
  assert.equal(r.dragging, "2");
  r = plain(M.update(tr, [A2, { ...B2, x: 100, y: 50, floating: true }], 100));    // over A
  assert.equal(r.target, "1");
  r = plain(M.update(tr, [A2, { ...B2, floating: false }], 160));                  // let go: re-tiled at once
  assert.deepEqual(r.drop, { from: "2", to: "1" }, "releasing over a window merges, without waiting for it to settle");
  // released away from any window: no merge
  const t2 = M.create();
  M.update(t2, [A2, B2], 0);
  M.update(t2, [A2, { ...B2, x: 700, floating: true }], 50);
  r = plain(M.update(t2, [A2, { ...B2, floating: false }], 100));
  assert.equal(r.drop, null);
  // passed over A, then moved on and released elsewhere a while later: not a merge
  const t3 = M.create();
  M.update(t3, [A2, B2], 0);
  M.update(t3, [A2, { ...B2, x: 100, y: 50, floating: true }], 50);
  M.update(t3, [A2, { ...B2, x: 650, y: 50, floating: true }], 1500);
  r = plain(M.update(t3, [A2, { ...B2, floating: false }], 1560));
  assert.equal(r.drop, null, "a target seen long before the release does not count");
}
console.log("tabs tests passed");
