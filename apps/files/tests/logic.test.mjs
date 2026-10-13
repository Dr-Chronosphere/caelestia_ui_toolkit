import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import vm from "node:vm";

const src = readFileSync(new URL("../logic/Files.js", import.meta.url), "utf8").replace(".pragma library", "");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src + "\nthis.F={toUrl,toPath,parentOf,baseName,join,breadcrumb,kindOf,isImage,humanSize,plural,places};", ctx);
const F = ctx.F;
const plain = v => JSON.parse(JSON.stringify(v));

assert.equal(F.toUrl("/home/a b/ü"), "file:///home/a%20b/%C3%BC");
assert.equal(F.toPath("file:///home/a%20b/%C3%BC"), "/home/a b/ü");
assert.equal(F.toPath(F.toUrl("/x/#y?z")), "/x/#y?z");

assert.equal(F.parentOf("/home/a/b"), "/home/a");
assert.equal(F.parentOf("/home"), "/");
assert.equal(F.parentOf("/"), "/");
assert.equal(F.parentOf("/home/a/"), "/home");
assert.equal(F.baseName("/home/a/"), "a");
assert.equal(F.baseName("/"), "/");
assert.equal(F.join("/", "x"), "/x");
assert.equal(F.join("/a/", "x"), "/a/x");

assert.deepEqual(plain(F.breadcrumb("/home/u/Projects/x", "/home/u")), [
  { label: "Home", path: "/home/u" }, { label: "Projects", path: "/home/u/Projects" }, { label: "x", path: "/home/u/Projects/x" }]);
assert.deepEqual(plain(F.breadcrumb("/home/u", "/home/u")), [{ label: "Home", path: "/home/u" }]);
assert.deepEqual(plain(F.breadcrumb("/etc/x", "/home/u")), [
  { label: "/", path: "/" }, { label: "etc", path: "/etc" }, { label: "x", path: "/etc/x" }]);
assert.deepEqual(plain(F.breadcrumb("/", "/home/u")), [{ label: "/", path: "/" }]);
// a sibling with a shared prefix is not "inside" home
assert.equal(F.breadcrumb("/home/user2", "/home/user")[0].label, "/");

assert.equal(F.kindOf("a", true).key, "folder");
assert.equal(F.kindOf("pic.JPG", false).key, "image");
assert.equal(F.kindOf("main.qml", false).key, "code");
assert.equal(F.kindOf("notes.txt", false).label, "Text");
assert.equal(F.kindOf("weird.xyz", false).label, "XYZ file");
assert.equal(F.kindOf(".bashrc", false).label, "File");
assert.equal(F.kindOf("Makefile", false).label, "File");
assert.equal(F.isImage("a.png"), true);
assert.equal(F.isImage("a.txt"), false);

assert.equal(F.humanSize(0), "0 B");
assert.equal(F.humanSize(999), "999 B");
assert.equal(F.humanSize(1500), "1.5 kB");
assert.equal(F.humanSize(2_500_000), "2.5 MB");
assert.equal(F.humanSize(150_000), "150 kB");
assert.equal(F.plural(1, "item", "items"), "1 item");
assert.equal(F.plural(4, "item", "items"), "4 items");

assert.deepEqual(plain(F.places("/home/u", ["Desktop", "Pictures", "src"])).map(p => p.label), ["Home", "Desktop", "Pictures"]);
assert.equal(F.places("/home/u", ["Music"])[1].path, "/home/u/Music");
console.log("files logic tests passed");
