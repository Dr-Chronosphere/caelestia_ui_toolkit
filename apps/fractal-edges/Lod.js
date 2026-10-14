.pragma library

// Level of detail for the fractal layout: tiles that are too small to use are covered by an icon
// card (like Trellis collapsing small windows to icons). Pure helpers, no Quickshell.
//
// Input is the status JSON (Seams.parse): every placed window carries a `box` in layout
// coordinates, plus `id`, `address`, `name` (the app class) and `title`.

// Windows whose tile is smaller than minW x minH, each as
// { id, address, label, title, box:{x,y,w,h} }.
function smallWindows(status, minW, minH) {
    var out = [];
    if (!status || !status.tree)
        return out;
    function walk(node) {
        if (node.kind === "window" && node.address && node.box && (node.box.w < minW || node.box.h < minH)) {
            out.push({
                id: node.id,
                address: node.address,
                label: node.name || "",
                title: node.title || "",
                box: { x: node.box.x, y: node.box.y, w: node.box.w, h: node.box.h }
            });
        }
        var kids = node.children || [];
        for (var i = 0; i < kids.length; i++)
            walk(kids[i]);
    }
    walk(status.tree);
    return out;
}

function intersects(r, b) {
    return r.x < b.x + b.w && r.x + r.w > b.x && r.y < b.y + b.h && r.y + r.h > b.y;
}

// How "small" a tile is relative to the threshold: 1 at the threshold, smaller below it.
function scaleOf(box, minW, minH) {
    return Math.min(box.w / minW, box.h / minH);
}

// Card opacity from the tile's scale: invisible at the threshold, fully visible once the tile is
// FADE below it. So cards fade in as a tile shrinks and out as it grows, instead of popping.
var FADE = 0.2;
function alphaFor(scale) {
    return Math.max(0, Math.min(1, (1 - scale) / FADE));
}

// The icon cards to show: small windows, inset a little so the card sits inside the tile's
// borders, minus any card a floating window overlaps (a layer surface would be drawn over it).
// opts: { minW, minH, inset }.
// Returns [{ id, address, label, title, x, y, w, h, scale, alpha }] sorted by id.
function cards(status, blockers, opts) {
    opts = opts || {};
    var minW = opts.minW === undefined ? 220 : opts.minW;
    var minH = opts.minH === undefined ? 140 : opts.minH;
    var inset = opts.inset === undefined ? 4 : opts.inset;
    var out = [];
    smallWindows(status, minW, minH).forEach(function (w) {
        var r = {
            x: w.box.x + inset,
            y: w.box.y + inset,
            w: Math.max(1, w.box.w - 2 * inset),
            h: Math.max(1, w.box.h - 2 * inset)
        };
        for (var i = 0; i < (blockers || []).length; i++) {
            if (intersects(r, blockers[i]))
                return;
        }
        var sc = scaleOf(w.box, minW, minH);
        out.push({ id: w.id, address: w.address, label: w.label, title: w.title, x: r.x, y: r.y, w: r.w, h: r.h, scale: sc, alpha: alphaFor(sc) });
    });
    out.sort(function (a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; });
    return out;
}

// Icon edge length in px for a card of this size: half the short side, within sensible bounds.
function iconSize(w, h) {
    return Math.max(16, Math.min(64, Math.round(Math.min(w, h) * 0.5)));
}

// A caption fits only on cards with room for it.
function showLabel(w, h) {
    return w >= 96 && h >= 84;
}

// One letter for the fallback glyph when no icon can be found.
function initial(label) {
    var m = String(label || "").match(/[A-Za-z0-9]/);
    return m ? m[0].toUpperCase() : "?";
}

// Reconcile the cards on screen with a fresh list. `prev` is the previous map {id: card};
// `fresh` the allowed cards now; `unblocked` the ids that would show if no floating window were in
// the way. A card that vanished because a floating window now covers it is dropped at once (it must
// never be drawn over that window); one that vanished because its tile grew (or the window closed)
// is kept as `leaving` so it can fade out. `now` is a ms clock.
// Returns { map, keys }, with keys in a stable (sorted) order.
function reconcile(prev, fresh, unblocked, now) {
    var map = {};
    var i;
    for (i = 0; i < fresh.length; i++)
        map[fresh[i].id] = fresh[i];
    for (var id in prev) {
        if (map[id])
            continue;
        if (unblocked.indexOf(id) >= 0)
            continue;                                   // blocked: gone immediately
        var old = prev[id];
        var copy = {};
        for (var k in old)
            copy[k] = old[k];
        copy.leaving = true;
        copy.leaveAt = old.leaving ? old.leaveAt : now;  // keep the original time while fading
        copy.alpha = 0;
        map[id] = copy;
    }
    return { map: map, keys: Object.keys(map).sort() };
}

// Drop cards that finished fading out (`ms` since they started leaving).
function purge(map, now, ms) {
    var out = {};
    for (var id in map) {
        if (map[id].leaving && now - map[id].leaveAt >= ms)
            continue;
        out[id] = map[id];
    }
    return { map: out, keys: Object.keys(out).sort() };
}
