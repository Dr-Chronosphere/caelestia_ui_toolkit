import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";
const dir = path.dirname(fileURLToPath(import.meta.url));
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(dir, "../Follow.js"), "utf8").replace(/^\.pragma.*$/m, "") + "\nthis.F={rectsByAddress,cardFromLive,sameRect,transitioning,parseWorkspaceAnim,parseAnimation,slideOffset};", ctx);
const F = ctx.F;
const plain = v => JSON.parse(JSON.stringify(v));

const r = plain(F.rectsByAddress(JSON.stringify([
  { address: "0x1", at: [10, 20], size: [300, 200], workspace: { id: 2 }, mapped: true },
  { address: "0x2", at: [0, 0], size: [5, 5], mapped: false },
  { at: [0, 0], size: [1, 1] }])));
assert.deepEqual(r, { "0x1": { x: 10, y: 20, w: 300, h: 200, workspace: 2 } });
assert.deepEqual(plain(F.rectsByAddress("garbage")), {});

// the card covers the window plus its padding
assert.deepEqual(plain(F.cardFromLive({ x: 100, y: 50, w: 300, h: 200 }, 4)), { x: 96, y: 46, w: 308, h: 208 });
assert.deepEqual(plain(F.cardFromLive({ x: 0, y: 0, w: 10, h: 10 }, -20)), { x: 20, y: 20, w: 1, h: 1 }, "never collapses below 1px");

// transition detection: a card away from its window's current rect means "moving"
const card = { address: "0x1", x: 96, y: 46, w: 308, h: 208 };
assert.equal(F.transitioning([card], { "0x1": { x: 100, y: 50, w: 300, h: 200 } }, 4), false, "settled");
assert.equal(F.transitioning([card], { "0x1": { x: 300, y: 50, w: 300, h: 200 } }, 4), true, "window still sliding");
assert.equal(F.transitioning([card], {}, 4), false, "no live rect (window gone): nothing to follow");
assert.equal(F.transitioning([card], { "0x1": { x: 101, y: 51, w: 300, h: 200 } }, 4), false, "within tolerance");

// workspace animation config
const anims = JSON.stringify([[{ name: "global", overridden: true, bezier: "default", enabled: true, speed: 8, style: "" }, { name: "workspaces", overridden: true, bezier: "x", enabled: true, speed: 4, style: "slidevert" }], []]);
assert.deepEqual(plain(F.parseWorkspaceAnim(anims)), { ms: 400, style: "slidevert" });
assert.equal(F.parseWorkspaceAnim(JSON.stringify([[{ name: "workspaces", enabled: false, speed: 4 }], []])), null, "disabled");
assert.equal(F.parseWorkspaceAnim("nope"), null);
assert.equal(F.parseWorkspaceAnim(JSON.stringify([[{ name: "windows", enabled: true, speed: 4 }], []])), null, "no workspaces entry");

// slide offsets: going to a higher workspace, the old cards leave left and the new ones come in from the right
assert.deepEqual(plain(F.slideOffset(1, "slide", false, 0.5, 1000, 600)), { x: -500, y: 0 });
assert.deepEqual(plain(F.slideOffset(1, "slide", true, 0.5, 1000, 600)), { x: 500, y: 0 });
assert.deepEqual(plain(F.slideOffset(-1, "slide", true, 0, 1000, 600)), { x: -1000, y: 0 });
assert.deepEqual(plain(F.slideOffset(1, "slide", true, 1, 1000, 600)), { x: 0, y: 0 }, "arrived");
assert.deepEqual(plain(F.slideOffset(1, "slidevert", true, 0.5, 1000, 600)), { x: 0, y: 300 });
assert.deepEqual(plain(F.slideOffset(1, "fade", true, 0.3, 1000, 600)), { x: 0, y: 0 }, "other styles do not move");
// resolved animations with their bezier curves
const full = JSON.stringify([[
  { name: "global", overridden: true, bezier: "default", enabled: true, speed: 8, style: "" },
  { name: "windows", overridden: true, bezier: "snap", enabled: true, speed: 5, style: "popin 80%" },
  { name: "windowsMove", overridden: false, bezier: "default", enabled: true, speed: 8, style: "" },
  { name: "workspaces", overridden: true, bezier: "snap", enabled: true, speed: 4, style: "slide" },
  { name: "windowsIn", overridden: true, bezier: "nope", enabled: true, speed: 3, style: "" }
], [{ name: "snap", X0: 0.2, Y0: 0.9, X1: 0.3, Y1: 1 }]]);
let m = plain(F.parseAnimation(full, "windowsMove"));
assert.deepEqual([m.ms, m.curve], [500, [0.2, 0.9, 0.3, 1]], "windowsMove is not overridden: it uses windows (speed 5, the snap curve)");
m = plain(F.parseAnimation(full, "workspaces"));
assert.deepEqual([m.ms, m.curve, m.style], [400, [0.2, 0.9, 0.3, 1], "slide"]);
m = plain(F.parseAnimation(full, "windowsIn"));
assert.deepEqual(m.curve, [0, 0.75, 0.15, 1], "an unknown bezier name falls back to Hyprland's default");
assert.equal(F.parseAnimation(full, "nothing"), null);
assert.equal(F.parseAnimation(JSON.stringify([[{ name: "windows", overridden: true, enabled: false, speed: 5 }, { name: "windowsMove", overridden: false }], []]), "windowsMove"), null, "the parent is disabled: so is the child");
assert.equal(F.parseAnimation("nope", "windows"), null);
console.log("follow tests passed");
